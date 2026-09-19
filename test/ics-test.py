#!/usr/bin/env python3
"""Recurrence, exceptions and moved instances, parsed offline."""

import os
import sys
from datetime import datetime, timedelta

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin"))

import _common as C  # noqa: E402

C.reexec_into_venv()

import _ics  # noqa: E402

FEED = """BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//test//EN
X-WR-CALNAME:Other job
BEGIN:VEVENT
UID:standup@test
DTSTART;TZID=Europe/Madrid:20260914T090000
DTEND;TZID=Europe/Madrid:20260914T091500
RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;COUNT=10
EXDATE;TZID=Europe/Madrid:20260916T090000
SUMMARY:Daily standup
X-GOOGLE-CONFERENCE:https://meet.google.com/aaa-bbbb-ccc
ATTENDEE;PARTSTAT=ACCEPTED:mailto:me@other.com
ATTENDEE;PARTSTAT=ACCEPTED:mailto:someone@other.com
END:VEVENT
BEGIN:VEVENT
UID:standup@test
RECURRENCE-ID;TZID=Europe/Madrid:20260917T090000
DTSTART;TZID=Europe/Madrid:20260917T113000
DTEND;TZID=Europe/Madrid:20260917T120000
SUMMARY:Daily standup (moved)
ATTENDEE;PARTSTAT=ACCEPTED:mailto:me@other.com
ATTENDEE;PARTSTAT=ACCEPTED:mailto:someone@other.com
END:VEVENT
BEGIN:VEVENT
UID:holiday@test
DTSTART;VALUE=DATE:20260921
DTEND;VALUE=DATE:20260922
SUMMARY:Company holiday
TRANSP:TRANSPARENT
END:VEVENT
BEGIN:VEVENT
UID:nope@test
DTSTART;TZID=Europe/Madrid:20260918T150000
DTEND;TZID=Europe/Madrid:20260918T160000
SUMMARY:Thing I declined
ATTENDEE;PARTSTAT=DECLINED:mailto:me@other.com
ATTENDEE;PARTSTAT=ACCEPTED:mailto:someone@other.com
END:VEVENT
END:VCALENDAR
"""

ACCOUNT = {"label": "otherjob", "email": "me@other.com", "priority": 1, "color": "#f7768e"}
FILTERS = {"skipDeclined": True, "skipAllDay": True, "skipSolo": True, "skipFree": True}

failures = 0


def check(name, condition, detail=""):
    global failures
    if condition:
        print("  ok  %s" % name)
    else:
        failures += 1
        print("  FAIL %s %s" % (name, detail))


name, events = _ics.events_from(FEED, ACCOUNT, datetime(2026, 9, 13), datetime(2026, 9, 30))
by_title = {}
for event in events:
    by_title.setdefault(event["title"], []).append(event)

print("feed: %s, %d occurrences" % (name, len(events)))
check("recurring event expands into occurrences", len(by_title.get("Daily standup", [])) >= 5,
      len(by_title.get("Daily standup", [])))
check("EXDATE removes the deleted instance",
      all(datetime.fromtimestamp(e["start"]).date() != datetime(2026, 9, 16).date()
          for e in by_title.get("Daily standup", [])))
check("RECURRENCE-ID keeps the moved instance at its new time",
      any(datetime.fromtimestamp(e["start"]).strftime("%Y-%m-%d %H:%M") == "2026-09-17 11:30"
          for e in by_title.get("Daily standup (moved)", [])))
check("timezone is honoured (09:00 Madrid, not UTC)",
      datetime.fromtimestamp(by_title["Daily standup"][0]["start"]).strftime("%H:%M") == "09:00",
      datetime.fromtimestamp(by_title["Daily standup"][0]["start"]).strftime("%H:%M"))
check("conference link is picked up",
      by_title["Daily standup"][0]["link"] == "https://meet.google.com/aaa-bbbb-ccc")
check("other attendees are counted, self excluded", by_title["Daily standup"][0]["attendees"] == 1)
check("all-day event is flagged", by_title["Company holiday"][0]["allDay"] is True)
check("free/busy is read", by_title["Company holiday"][0]["transparency"] == "transparent")
check("own decline is detected", by_title["Thing I declined"][0]["response"] == "declined")

kept = [e for e in events if C.should_keep(e, FILTERS)]
kept_titles = {e["title"] for e in kept}
check("filters drop the declined one", "Thing I declined" not in kept_titles)
check("filters drop the all-day holiday", "Company holiday" not in kept_titles)
check("filters keep the standups", "Daily standup" in kept_titles)

print("%d failure(s)" % failures)
sys.exit(1 if failures else 0)
