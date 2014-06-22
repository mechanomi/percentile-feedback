#!/usr/bin/env python

print "This is a test version of data.py"

import datetime
import itertools
import re
import sys
import time

# Import CouchDB, or prompt the user how to install it
try: import couchdb
except ImportError:
    print "ERROR: The CouchDB python package is not installed!"
    print "You can insall using pip: $ pip install CouchDB"
    print "Or get it from here: https://pypi.python.org/pypi/CouchDB"
    sys.exit(1)

database_name = "pf-periods"

def iso_offset(seconds, strict=False):
    """Format an offset (integer of seconds) as an ISO timezone.

    This function expects a number of seconds that is cleanly divisible by 60,
    i.e. is rounded to a minute. If strict is False, the default, then we'll
    ignore any seconds that don't align to the nearest minute. Otherwise we
    raise a ValueError.

    Examples:

    >>> iso_offset(60)
    '+00:01'
    >>> iso_offset(600)
    '+00:10'
    >>> iso_offset(3600)
    '+01:00'
    >>> iso_offset(7200)
    '+02:00'
    >>> iso_offset(7260)
    '+02:01'
    >>> iso_offset(-7260)
    '-02:01'
    """
    if seconds < 0:
        seconds = abs(seconds)
        sign = "-"
    else:
        sign = "+"

    hours, seconds = divmod(seconds, 3600)
    minutes, seconds = divmod(seconds, 60)

    if (hours > 99) or (hours < -99):
        raise ValueError("Unexpectedly large timezone offset from UTC")
    if (minutes > 60) or (minutes < 0):
        # This shouldn't happen, because of mathematics
        raise ValueError("Unexpected number of minutes")
    if seconds and strict:
        raise ValueError("Timezone offset is not rounded to a minute")

    return "%s%02i:%02i" % (sign, hours, minutes)

def timeinfo(now):
    """Return the unixtime and timezone offset in seconds from a datetime.

    This function heuristically determines the timezone for a given
    datetime. The input data from org-mode does not contain timezones, but we
    want to store timezone data in CouchDB for possible use. We use the
    computer's current local time to compute the current local time zone, and
    then we apply this retroactively to the datetime values.

    To create this, I went through all of the functions that python has for
    converting times (there are four relevant ones), and used the one that gave
    the correct value - time.mktime. This takes a python time-9-tuple and
    interprets it as a local time, and emits the corresponding correct
    unixtime.

    Next, we create a UTC counterpart to the local time, which we can do easily
    from the unixtime. Then the important step is to remember that the original
    input is still a naive value. In other words, it doesn't have a timezone
    associated with it. Therefore we can get the offset simply by measuring the
    duration between this original time and the newly constructed UTC
    counterpart.
    """
    rounded = now.replace(microsecond=0)
    unixtime = int(time.mktime(rounded.timetuple()))
    utc = datetime.datetime.utcfromtimestamp(unixtime)
    offset = (rounded - utc).total_seconds()
    return unixtime - offset, offset

# ### UNCOMMENT ME FOR A SIMPLER VERSION OF THE timeinfo FUNCTION ###
# def offset(now=None):
#     if now is None:
#         now = datetime.datetime.now()
#     rounded = now.replace(microsecond=0)
#     unixtime = time.mktime(rounded.timetuple())
#     utc = datetime.datetime.utcfromtimestamp(unixtime)
#     return (rounded - utc).total_seconds()

def isounix(now=None):
    """Return an ISO formatted time and unixtime from a datetime object.

    This function takes in a python datetime.datetime object and converts it to
    an ISO formatted string representing the local time, and the corresponding
    unixtime.

    As the input is a datetime.datetime object, this is naive and carries no
    timezone information. In order to determine the timezone, we use an
    heuristic approach implemented in the timeinfo function, which returns the
    timezone as an offset from UTC in seconds. We then use iso_offset to format
    this offset into an ISO compatible timezone string, +HH:MM or -HH:MM.
    """
    if now is None:
        now = datetime.datetime.now()
    unixtime, offset = timeinfo(now)
    tz = iso_offset(offset)
    return now.strftime("%Y-%m-%dT%H:%M:%S") + tz, unixtime

def normalised_datetimes(started, completed):
    """Return datatimes with microsecond set to 0.

    We do this to avoid any potential problems with formatting, rounding, etc.
    """
    started = started.replace(microsecond=0)
    completed = completed.replace(microsecond=0)
    return started, completed

def org_datetimes(org_filename):
    """Parse an org-mode file and return datetime pairs.

    This function takes an org-mode filename, and searches for any CLOCK
    periods contained in the file. It then converts those to a 2-tuple of
    (started, completed) datatime.datetime objects.

    See the documentation for parse_org, which uses the present function, for
    further explanation of datetime pairs.
    """
    def clock_lines(f):
        """Filter a file to a generator of lines only containing CLOCK."""
        # In python3 we would be able to use this:
        # yield from (line for line in f if "CLOCK" in line)
        for line in f:
            if "CLOCK" in line:
                yield line

    def clock_to_datetime(clock):
        """Convert an org-mode formatted time into a python datetime."""
        return datetime.datetime.strptime(clock, "%Y-%m-%d %a %H:%M")

    clock_regexp = re.compile(r"\[([^\]]+)\]")
    def line_to_datetimes(line):
        """Find all org-mode formatted times, and convert to datetimes."""
        clocks = clock_regexp.findall(line)
        return [clock_to_datetime(clock) for clock in clocks]

    def datetimes_to_span(datetimes):
        """Convert one or two datetimes to a datetime pair tuple.

        This function is unusual in that we take elements from the start of the
        list, using .pop(0) - which is called shift in most programming
        languages. This is just the most efficient way of coping with lists
        that can be either one or two elements long.

        If the list is only one element long, then that represents a clock
        period that hasn't been closed. We use the current time as the value
        for the completion of the period.
        """
        started = datetimes.pop(0)
        try: completed = datetimes.pop(0)
        except IndexError:
            completed = datetime.datetime.now()
        return started, completed

    # Open the org-mode file
    with open(org_filename) as f:
        # Filter so that only CLOCK lines remain
        for line in clock_lines(f):
            # Get all individual org-mode formatted times from this line
            datetimes = line_to_datetimes(line)

            # We should have either one (ongoing) or two (completed) times in
            # this line, representing either an unclosed span [START]- or a
            # closed span [START]-[COMPLETE]. We check this, and then simply
            # skip/ignore this line if there are 0 or 3+ values.
            if len(datetimes) not in {1, 2}:
                # Corrupt line. Warn the user?
                continue

            # We either have one or two datetimes in this list. If we have one,
            # then we need to supply a dummy completed value, which is provided
            # by datetimes_to_span. Another way of doing this would be:
            #
            #   started = datetimes[0]
            #   if len(datetimes) == 2:
            #       completed = datetimes[1]
            #   else:
            #       completed = datetime.datetime.now()
            started, completed = datetimes_to_span(datetimes)
            if completed <= started:
                # < means corrupt line. Warn the user?
                #
                # (In other words, the completed time is before the start
                # time. In fact, org-mode files can do this. We may need to
                # treat this differently.)
                #
                # = means a 0 duration, which we ignore
                #
                # (In other words, we may have clocked on and off within the
                # same minute, and so we have a period which is effectively a
                # point, having no duration. So we just discard it.)
                continue

            # We now set the microseconds in the datetime objects to 0, just in
            # case it causes any formatting problems, rounding problems, etc.
            yield normalised_datetimes(started, completed)

def check_overlaps(periods, discard=False):
    """Check for overlaps in period data.

    Takes, and returns, a generator of period values. Used in parse_org, which
    also documents period values.

    Has two different strategies for dealing with overlaps:

    * Truncate the earliest of the two periods that overlap.
    * Discard the earliest(?) of the two periods that overlap.

    By default we use truncation. Set discard to True to discard.
    """
    def pairwise(iterable):
        """Return a sliding window of length 2 over an iterable.

        Example: If we have input (a, b, c, d, e), then we'll return (a, b),
        (b, c), (c, d), and (d, e). Input can be any iterable, but the output
        will be a generator.
        """
        a, b = itertools.tee(iterable)
        next(b, None)
        return itertools.izip(a, b)

    for a, b in pairwise(sorted(periods)):
        # a and b are two datetime pairs, so a is actually (a-started,
        # a-completed), and b is (b-started, b-completed). Therefore, a[1] is
        # the completion time of the earlier of the two periods, and b[0] is
        # the start time of the later of the two periods.
        previous_completed = a[1]
        next_started = b[0]

        # If the periods are chronological, then everything is fine
        if previous_completed <= next_started:
            yield a
        # Otherwise, they overlap, so truncate if discard is False
        elif discard is False:
            yield a[0], b[0]
        # Otherwise, check to make sure that discard is True
        elif discard is not True:
            raise ValueError("Expected boolean, discard")
    yield b

def check_durations(periods, discard=True):
    """Check for faulty durations in period data.

    Takes, and returns, a generator of period values. Used in parse_org, which
    also documents period values.

    A faulty duration is defined as anything over 86400 seconds, i.e. 24
    hours. We perform this check because org-mode file data can be corrupt in
    having old unclosed periods. If a period wasn't closed, then not only will
    it create an extremely large period, but it will also conflict with and
    overlap all periods logged from that point on.

    We choose 24 hours as a sensible cut-off point because nobody is likely to
    be working for more than that length of time on a single task, unless
    they're a submariner. Other heuristics may be desirable, e.g. using the
    same length as the previous logged time.

    We implement two different strategies for dealing with faulty durations:

    * Discard the period.
    * Truncate the period to 24 hours.

    By default we discard. Set discard to False to truncate.
    """
    for (started, completed) in periods:
        # If the period is under 24h, then we consider it reasonable
        if (completed - started).total_seconds() < 86400: # <=?
            yield started, completed
        # Otherwise, we truncate by default
        elif discard is False:
            completed = started + datetime.timedelta(seconds=86400)
            completed = completed.replace(microsecond=0)
            yield started, completed
        # If we're discarding, check that discard is True
        elif discard is not True:
            raise ValueError("Expected boolean, discard")

def datetimes_to_period(datetimes):
    """Convert datetime pairs (2-tuples) to period values (3-tuples).

    We use ISO formatted times, i.e. YYYY-MM-DDTHH:MM:SS(ZONE).

    Example: 2014-01-10T11:20:30Z (UTC)
    Example: 2014-01-10T12:20:30+01:00 (UTC+1)

    A period value is a 3-tuple of (utc, iso, duration), where UTC is the
    normalised start time, iso is the local start time, and duration is the
    entire length of the period in seconds as an integer.

    This function is used by parse_org.
    """
    # Destructure the input
    started, completed = datetimes
    # Convert the start datetime to ISO formatted localtime and unixtime
    iso, unix = isounix(started)
    # Use the unixtime to create the ISO formatted normalised start time
    utc = datetime.datetime.fromtimestamp(unix).strftime("%Y-%m-%dT%H:%M:%SZ")
    # Compute the duration from the original datetime objects
    duration = (completed - started).total_seconds()
    return utc, iso, int(duration) # floor of duration

def store_in_database(couch, periods):
    """Store period values (3-tuples) in a CouchDB database.

    Each period is stored in a single CouchDB doc. We store the docs en masse
    using db.update, which is much more efficient than storing each document
    individually.

    The format of each doc is as follows:

    {_id: <String: ISO formatted UTC normalised start time>,
     timestamp: <String: ISO formatted local start time>,
     duration: <Integer: total elapsed time of the period in seconds>,
     category: <Array: set to [], reserved for possible use>}

    The name of the CouchDB database used is set in a global, database_name,
    and cannot be configured parametrically.
    """
    # The following test, "if database_name not in couch", is where we get an
    # error if CouchDB is not running. We could catch this error and display a
    # useful message to the user.
    if database_name not in couch:
        # Create the database if it doesn't already exist
        db = couch.create(database_name)
    else:
        # Otherwise use the existing database
        db = couch[database_name]

    p = []
    for (utc, iso, duration) in periods:
        doc = couchdb.Document(
            _id=utc,
            timestamp=iso,
            duration=duration,
            category=[]
        )
        p.append(doc)

    db.update(p)

def read_from_database(couch):
    """Return the present database or None.

    This is a debug function which allows us to, for example, check how many
    entries were actually stored in the CouchDB database.
    """
    if database_name not in couch:
        return
    return couch[database_name]

def parse_org(org_filename):
    """Parse an org-mode file and return a generator of period values.

    Period values are a tuple of (utc, iso, duration), where utc is the UTC
    normalised start time of the period, in ISO format; iso is the local start
    time, with time zone, in ISO format; and duration is an integer
    representing the entire elapsed time of the period from the start time in
    seconds.

    This function also performs some data integrity checks. These checks should
    probably be moved to CouchDB, so that any input source can undergo the same
    integrity checking without code duplication. This is possible because these
    integrity checks are independent of the input format. (There may also be
    sensible integrity checks which are format dependent, and these would have
    to be done on a per-parser basis.)

    This function uses another internal interchange format referred to as
    datetime pairs, which is a tuple of (started, completed), where started
    represents the beginning of the period as a python datetime.datetime
    instance with microseconds normalised to 0, and completed represents the
    same for the end of the period.

    We use datetime pairs (2-tuple) because it is easier to perform integrity
    checks on the datetime pairs. We emit period values (3-tuple) because these
    are more suitable for feeding into CouchDB.
    """
    # This parses the org-mode file and returns datetime pairs
    datetimes = org_datetimes(org_filename)
    # These are the two integrity checks that we currently perform
    datetimes = check_overlaps(datetimes)
    datetimes = check_durations(datetimes)
    for d in datetimes:
        # datetimes_to_period converts from datetime pairs to period values
        # a 2-tuple of datetimes goes in; a 3-tuple (str, str, int) comes out
        yield datetimes_to_period(d)

def test():
    """Parse an org-mode file and store the data in CouchDB.

    We parse the org-mode file using parse_org, which returns a generator of
    period values, which are an internal interchange format only used in this
    script temporarily. See parse_org for documentation on period values.

    We then feed the period values into store_in_database, which actually
    stores the values in CouchDB.
    """
    # This is a shim to remove data, so that everything is replaced
    # It may be better to check how to only replace conflicting data
    couch = couchdb.Server()
    if database_name in couch:
        del couch[database_name]

    # Parse the org file, store in CouchDB. This is the main portion
    periods = parse_org(sys.argv[1])
    store_in_database(couch, periods)

    # This is just to check that we stored data correctly
    data = read_from_database(couch)
    print len(data), "items stored"

    # ### UNCOMMENT ME TO SHOW DEBUG INFORMATION ###
    # for isotime in sorted(data):
    #     if not isotime.startswith("_"):
    #         print isotime, data[isotime]

if __name__ == "__main__":
    test()
