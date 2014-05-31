#!/usr/bin/env python

print "This is a test version of data.py"

import datetime
import itertools
import re
import sys
import time

import couchdb

# >>> import couchdb
# >>> couch = couchdb.Server()
# >>> test = couch.create("test")
# >>> test.save({"example": 123})

# def offset(now=None):
#     if now is None:
#         now = datetime.datetime.now()
#     rounded = now.replace(microsecond=0)
#     unixtime = time.mktime(rounded.timetuple())
#     utc = datetime.datetime.utcfromtimestamp(unixtime)
#     return (rounded - utc).total_seconds()

database_name = "pf-periods"

def iso_offset(seconds, strict=False):
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
    rounded = now.replace(microsecond=0)
    unixtime = int(time.mktime(rounded.timetuple()))
    utc = datetime.datetime.utcfromtimestamp(unixtime)
    offset = (rounded - utc).total_seconds()
    return unixtime - offset, offset

def isounix(now=None):
    if now is None:
        now = datetime.datetime.now()
    unixtime, offset = timeinfo(now)
    tz = iso_offset(offset)
    return now.strftime("%Y-%m-%dT%H:%M:%S") + tz, unixtime

def normalised_datetimes(started, completed):
    started = started.replace(microsecond=0)
    completed = completed.replace(microsecond=0)
    return started, completed

def org_periods(org_filename):
    def clock_lines(f):
        # yield from (line for line in f if "CLOCK" in line)
        for line in f:
            if "CLOCK" in line:
                yield line

    def clock_to_datetime(clock):
        return datetime.datetime.strptime(clock, "%Y-%m-%d %a %H:%M")

    clock_regexp = re.compile(r"\[([^\]]+)\]")
    def line_to_datetimes(line):
        clocks = clock_regexp.findall(line)
        return [clock_to_datetime(clock) for clock in clocks]

    def datetimes_to_span(datetimes):
        started = datetimes.pop(0)
        try: completed = datetimes.pop(0)
        except IndexError:
            completed = datetime.datetime.now()
        return started, completed

    with open(org_filename) as f:
        for line in clock_lines(f):
            datetimes = line_to_datetimes(line)
            if len(datetimes) not in {1, 2}:
                # Corrupt line. Warn the user?
                continue

            started, completed = datetimes_to_span(datetimes)
            if completed <= started:
                # < means corrupt line. Warn the user?
                # = means a 0 duration, which we ignore
                continue

            yield normalised_datetimes(started, completed)

def check_overlaps(periods, discard=False):
    def pairwise(iterable):
        a, b = itertools.tee(iterable)
        next(b, None)
        return itertools.izip(a, b)

    for a, b in pairwise(sorted(periods)):
        previous_completed = a[1]
        next_started = b[0]
        if previous_completed <= next_started:
            yield a
        elif discard is False:
            yield a[0], b[0]
        elif discard is not True:
            raise ValueError("Expected boolean, discard")
    yield b

def check_durations(periods, discard=True):
    for (started, completed) in periods:
        if (completed - started).total_seconds() < 86400: # <=?
            yield started, completed
        elif discard is False:
            completed = started + datetime.timedelta(seconds=86400)
            completed = completed.replace(microsecond=0)
            yield started, completed
        elif discard is not True:
            raise ValueError("Expected boolean, discard")

def datetimes_to_period(datetimes):
    started, completed = datetimes
    iso, unix = isounix(started)
    utc = datetime.datetime.fromtimestamp(unix).strftime("%Y-%m-%dT%H:%M:%SZ")
    duration = (completed - started).total_seconds()
    return utc, iso, int(duration) # floor of duration

# check CouchDB db already exists
#    otherwise, create it
# store data in db
# one doc per period?

def store_in_database(couch, periods):
    if database_name not in couch: # connection error would come here
        db = couch.create(database_name)
    else:
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
    if database_name not in couch:
        return
    db = couch[database_name]
    return db

def parse_org(org_filename):
    periods = org_periods(org_filename)
    periods = check_overlaps(periods)
    periods = check_durations(periods)
    for period in periods:
        # Nomenclature needs sorting
        yield datetimes_to_period(period)

def test():
    couch = couchdb.Server()
    if database_name in couch:
        del couch[database_name]

    periods = parse_org(sys.argv[1])
    store_in_database(couch, periods)

    data = read_from_database(couch)
    print len(data), "items stored"
    # for isotime in sorted(data):
    #     if not isotime.startswith("_"):
    #         print isotime, data[isotime]

if __name__ == "__main__":
    test()
