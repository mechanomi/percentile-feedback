#!/usr/bin/env python

import argparse
import datetime
import os.path
import re
import sys

def periods(now, duration, continuous=False):
    results = []

    date = now.strftime("%Y-%m-%d")
    completed = (now.hour * 3600) + (now.minute * 60) + now.second
    started = completed - duration

    if started < 0:
        yesterday = now - datetime.timedelta(days=1)
        yesterdate = yesterday.strftime("%Y-%m-%d")
        yesterstarted = (3600 * 24) - abs(started)
        yestercompleted = 3600 * 24
        started = 0
        args = (yesterdate, yesterstarted, yestercompleted)
        results.append("%s %s %s" % args)

    if continuous:
        completed = "-"
    args = (date, started, completed)
    results.append("%s %s %s" % args)
    return results

# def add_period_to_log(log, period):
#     # log = log filename
#     # period = period in seconds
#     ...

def process_log_lines(dates, lines):
    # modifies dates (a dict) in place
    # lines = iterable of lines
    for line in lines:
        if line.count(" ") == 2:
            line = line.rstrip()
            date, started, completed = line.split(" ")
            if date not in dates:
                dates[date] = []
            dates[date].append((started, completed))

# python format is:
# dates["YYYY-MM-DD"] = [("SECS-START", "SECS-COMPLETE"), ...]
# e.g. {"2014-04-03": [("1000", "2000")]}

def log_to_python(log):
    # log = log filename
    dates = {}
    with open(log) as f:
        process_log_lines(dates, f)
    return dates

# python_to_log?

def org_to_python(org):
    # org = org filename
    dates = {}
    log = []
    with open(org) as f:
        for line in sorted(f):
            if "CLOCK" not in line:
                continue
            continuous = False
            try:
                tstr = re.compile(r"\[([^\]]+)\]")
                sc = tstr.findall(line)
                strptime = datetime.datetime.strptime
                started = strptime(sc[0], "%Y-%m-%d %a %H:%M")
                if len(sc) > 1:
                    completed = strptime(sc[1], "%Y-%m-%d %a %H:%M")
                else:
                    completed = datetime.datetime.now()
                    continuous = True
            except:
                continue
            if completed > started:
                delta = completed - started
                if delta.days:
                    # Error, continue! TODO: Detect overlaps
                    print "Warning, unclosed value:", line.strip()
                    continue
                secs = delta.seconds
                log.extend(periods(completed, secs, continuous))

    process_log_lines(dates, log)
    return dates

def iso2js(date):
    # helper function for javascript_object
    y, m, d = date.split("-")
    return "%s, %s, %s" % (int(y), int(m) - 1, int(d))

def javascript_object(date, pairs):
    starts = []
    stops = []
    for (start, stop) in pairs:
        starts.append(start)
        if stop != "-":
            stops.append(stop)
    obj = "{date: new Date(%s), starts: [%s], stops: [%s]}"
    starts = ", ".join([start + ".0" for start in starts])
    stops = ", ".join([stop + ".0" for stop in stops])
    return obj % (iso2js(date), starts, stops)

def compensate(dates, midnight):
    # dates = python format
    # midnight = offset from midnight in positive seconds
    def yesterday(day):
        y = datetime.datetime.strptime(day, "%Y-%m-%d")
        y = y - datetime.timedelta(days=1)
        return y.strftime("%Y-%m-%d")

    compensated = {}
    for day in dates:
        for (started, completed) in dates[day]:
            started = int(started)
            sday = day
            if started < midnight:
                started = (3600 * 24) - midnight + started
                sday = yesterday(day)
            else:
                started = started - midnight

            cday = day
            if completed != "-":
                completed = int(completed)
                if completed < midnight:
                    completed = (3600 * 24) - midnight + completed
                    cday = yesterday(day)
                else:
                    completed = completed - midnight

            if sday not in compensated:
                compensated[sday] = []

            # Adding ints for now, so that we can sort them afterwards
            if sday != cday:
                if cday not in compensated:
                    compensated[cday] = []
                compensated[sday].append((started, 24 * 3600))
                compensated[cday].append((0, completed))
            else:
                compensated[sday].append((started, completed))

    # Sort the items, and stringify them
    for day in compensated:
        ordered = sorted(compensated[day])
        compensated[day] = [(str(s), str(c)) for (s, c) in ordered]
    return compensated

def python_to_javascript(dates, midnight=None):
    lines = []

    if midnight is not None:
        dates = compensate(dates, midnight=midnight)
        hours = midnight // 3600
        seconds = midnight % 3600
        epoch = "%02i:%02i" % (hours, seconds // 60)
    else:
        epoch = "00:00"
    lines.append("var midnight = \"%s\";" % epoch)
    lines.append("var midnight_seconds = %s;" % (midnight or 0))

    now = datetime.datetime.now()
    if midnight is not None:
        now = now - datetime.timedelta(seconds=midnight)
    today = now.strftime("%Y-%m-%d")
    if today in dates:
        obj = javascript_object(today, dates[today])
        del dates[today]
    else:
        obj = javascript_object(today, [])
    lines.append("var today_wr = %s;" % obj)

    lines.append("var updateInterval;")
    lines.append("var refresh_delay = 43733.87873;")
    lines.append("var past_wrs = [];")

    for date in sorted(dates):
        obj = javascript_object(date, dates[date])
        lines.append("past_wrs.push(%s);" % obj)

    return "\n".join(lines)

def log_to_javascript(log, midnight=None):
    dates = log_to_python(log)
    return python_to_javascript(dates, midnight=midnight)

def org_to_javascript(org, midnight=None):
    dates = org_to_python(org)
    return python_to_javascript(dates, midnight=midnight)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-m", "--midnight", help="Set midnight, as HH:MM")
    parser.add_argument("-l", "--convert-log", metavar="PATH",
                        help="Convert a log file to data.js")
    parser.add_argument("-o", "--convert-org", metavar="PATH",
                        help="Convert an org-mode file to data.js")
    parser.add_argument("-p", "--log-period", metavar="SECONDS",
                        help="Log a period, and update data.js")
    args = parser.parse_args()

    midnight = None
    if args.midnight is not None:
        hours, minutes = args.midnight.split(":")
        midnight = (int(hours) * 3600) + (int(minutes) * 60)

    directory = os.path.dirname(os.path.realpath(__file__))

    if args.log_period is not None:
        periods_txt = os.path.join(directory, "periods.txt")
        with open(periods_txt, "a") as f:
            now = datetime.datetime.now()
            duration = int(args.log_period)
            for period in periods(now, duration):
                f.write(period + "\n")

        if args.convert_log is None:
            args.convert_log = periods_txt

    if args.convert_log is not None:
        js = log_to_javascript(args.convert_log, midnight=midnight)
        with open(os.path.join(directory, "data.js"), "w") as f:
            f.write(js)
        sys.exit()

    if args.convert_org is not None:
        js = org_to_javascript(args.convert_org, midnight=midnight)
        with open(os.path.join(directory, "data.js"), "w") as f:
            f.write(js)
        sys.exit()

    parser.print_help()
    sys.exit(2)

if __name__ == "__main__":
    main()
