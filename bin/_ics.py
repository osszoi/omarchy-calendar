"""Read a calendar from an iCalendar URL (Google's "secret address" and friends).

The API path gets its occurrences expanded server-side by singleEvents=true; a
feed hands us the rules instead, so recurrence, exceptions and individually
moved instances are expanded here before anything else sees an event.
"""

import gzip
import re
import urllib.request
from datetime import date, datetime, timezone

import _common as C

USER_AGENT = "omarchy-calendar/0.1 (+https://github.com/osszoi)"


def fetch(url, timeout=30):
    request = urllib.request.Request(url, headers={
        "User-Agent": USER_AGENT,
        "Accept-Encoding": "gzip",
    })
    with urllib.request.urlopen(request, timeout=timeout) as response:
        raw = response.read()
        if response.headers.get("Content-Encoding") == "gzip":
            raw = gzip.decompress(raw)
        return raw.decode("utf-8", "replace")


def _epoch(value):
    """A date means all-day, and all-day is local midnight, not UTC midnight."""
    if isinstance(value, datetime):
        if value.tzinfo is None:
            return int(value.timestamp())
        return int(value.astimezone(timezone.utc).timestamp())
    if isinstance(value, date):
        return int(datetime(value.year, value.month, value.day).timestamp())
    return 0


def _text(component, name):
    value = component.get(name)
    if value is None:
        return ""
    try:
        return str(value)
    except Exception:
        return ""


def _attendees(component, self_email):
    """Everyone invited who is not you, plus your own reply if it is in there."""
    raw = component.get("ATTENDEE")
    if raw is None:
        return 0, "unknown"
    entries = raw if isinstance(raw, list) else [raw]
    mine = "unknown"
    others = 0
    for entry in entries:
        address = str(entry).replace("MAILTO:", "").replace("mailto:", "").strip().lower()
        params = getattr(entry, "params", {}) or {}
        if self_email and address == self_email.lower():
            status = str(params.get("PARTSTAT", "")).lower()
            mine = {"declined": "declined", "accepted": "accepted",
                    "tentative": "tentative", "needs-action": "needsAction"}.get(status, "unknown")
            continue
        if str(params.get("CUTYPE", "")).upper() == "RESOURCE":
            continue
        others += 1

    organizer = _text(component, "ORGANIZER").replace("MAILTO:", "").replace("mailto:", "").strip().lower()
    if mine == "unknown" and self_email and organizer == self_email.lower():
        mine = "accepted"
    return others, mine


def _link(component):
    conference = _text(component, "X-GOOGLE-CONFERENCE").strip()
    if conference:
        return conference
    for field in ("LOCATION", "DESCRIPTION"):
        text = _text(component, field)
        for pattern in C.MEET_PATTERNS:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                return match.group(0)
    match = re.search(r"https?://[^\s<>\"']+", _text(component, "LOCATION"))
    return match.group(0) if match else ""


def events_from(text, account, window_start, window_end):
    import icalendar
    import recurring_ical_events

    calendar = icalendar.Calendar.from_ical(text)
    name = str(calendar.get("X-WR-CALNAME") or account.get("label") or "calendar")
    self_email = str(account.get("email") or "")

    occurrences = recurring_ical_events.of(calendar).between(window_start, window_end)
    events = []
    for component in occurrences:
        start = component.get("DTSTART")
        end = component.get("DTEND") or component.get("DUE")
        if start is None:
            continue
        start_value = start.dt
        end_value = end.dt if end is not None else start_value
        all_day = not isinstance(start_value, datetime)

        others, response = _attendees(component, self_email)
        uid = _text(component, "UID") or _text(component, "SUMMARY")
        start_epoch = _epoch(start_value)

        events.append({
            "id": "%s:ics:%s:%d" % (account["label"], uid, start_epoch),
            "account": account["label"],
            "priority": int(account.get("priority", 99)),
            "color": account.get("color") or "#7aa2f7",
            "calendar": name,
            "calendarId": "ics",
            "title": (_text(component, "SUMMARY") or "(no title)").strip(),
            "start": start_epoch,
            "end": _epoch(end_value),
            "allDay": all_day,
            "link": _link(component),
            "htmlLink": _text(component, "URL"),
            "location": _text(component, "LOCATION").strip(),
            "response": response,
            "attendees": others,
            "transparency": (_text(component, "TRANSP") or "OPAQUE").lower().replace("opaque", "opaque").replace("transparent", "transparent"),
            "status": (_text(component, "STATUS") or "CONFIRMED").lower(),
        })
    return name, events


def span(text):
    """How far the feed actually reaches, which is not the window we asked for."""
    stamps = [int(m) for m in []]
    starts = re.findall(r"^DTSTART[^:]*:(\d{8})", text, re.MULTILINE)
    if not starts:
        return None, None
    return min(starts), max(starts)
