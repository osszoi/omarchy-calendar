#!/usr/bin/env python3
"""Write a believable events.json so the panel can be looked at without OAuth."""
import json, os, sys, time
from datetime import datetime, timedelta

now = datetime.now()
def ts(day_offset, hour, minute=0):
    day = (now + timedelta(days=day_offset)).replace(hour=hour, minute=minute, second=0, microsecond=0)
    return int(day.timestamp())

def rel(minutes):
    return int((now + timedelta(minutes=minutes)).timestamp())

WORK = {"account": "work", "priority": 1, "color": "#7aa2f7"}
HOME = {"account": "personal", "priority": 2, "color": "#9ece6a"}

def ev(n, title, start, end, who, link="", location=""):
    return dict(who, id="fix:%d" % n, title=title, start=start, end=end, allDay=False,
                link=link, htmlLink="https://calendar.google.com/", location=location,
                calendar=who["account"], calendarId="primary", response="accepted",
                attendees=3, transparency="opaque", status="confirmed")

events = [
    ev(1, "Standup", rel(-20), rel(25), WORK, "https://meet.google.com/abc-defg-hij"),
    ev(2, "Design review with the platform team", rel(50), rel(110), WORK, "https://meet.google.com/xyz-1234-abc"),
    ev(3, "Dentist", rel(200), rel(260), HOME, "", "Calle Mayor 4"),
    ev(4, "1:1 with Ana", ts(0, 9, 30), ts(0, 10, 0), WORK, "https://meet.google.com/aaa-bbbb-ccc"),
    ev(5, "Sprint planning", ts(0, 10, 0), ts(0, 11, 30), WORK, "https://meet.google.com/ddd-eeee-fff"),
    ev(6, "Overlapping catch-up", ts(0, 10, 30), ts(0, 11, 0), HOME),
    ev(7, "Third at the same time", ts(0, 10, 45), ts(0, 11, 15), WORK),
    ev(8, "Backlog grooming", ts(-1, 11, 0), ts(-1, 12, 0), WORK),
    ev(9, "Gym", ts(-1, 19, 0), ts(-1, 20, 30), HOME),
    ev(10, "Retro", ts(1, 15, 0), ts(1, 16, 0), WORK, "https://meet.google.com/ggg-hhhh-iii"),
    ev(11, "Lunch with Marta", ts(1, 13, 0), ts(1, 14, 30), HOME),
    ev(12, "Quarterly review", ts(2, 9, 0), ts(2, 12, 0), WORK),
    ev(13, "School run", ts(2, 8, 0), ts(2, 9, 0), HOME),
    ev(14, "Late night deploy", ts(3, 23, 30), ts(4, 1, 0), WORK),
    ev(15, "Incident review", ts(-2, 16, 0), ts(-2, 17, 0), WORK),
]

payload = {
    "version": 1,
    "syncedAt": int(time.time()),
    "accounts": [
        {"label": "work", "priority": 1, "color": "#7aa2f7", "status": "ok", "error": "", "syncedAt": int(time.time()), "lastOkAt": int(time.time()), "events": 11},
        {"label": "personal", "priority": 2, "color": "#9ece6a", "status": "ok", "error": "", "syncedAt": int(time.time()), "lastOkAt": int(time.time()), "events": 4},
    ],
    "leadMinutes": [5, 1],
    "upcomingWindowMinutes": 60,
    "catchUpMinutes": 10,
    "maxTitleChars": 28,
    "events": sorted(events, key=lambda e: e["start"]),
}

path = os.path.expanduser("~/.cache/omarchy-calendar/events.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as handle:
    json.dump(payload, handle, indent=2)
print("wrote", len(events), "events to", path)

# Demo events must not wake anybody: claim their alert keys up front so the
# widget finds them already fired.
alerted = os.path.expanduser("~/.cache/omarchy-calendar/alerted.json")
fired = {}
for e in events:
    for lead in (5, 1):
        fired["%s|%d|%d" % (e["id"], e["start"], lead)] = int(time.time())
with open(alerted, "w") as handle:
    json.dump(fired, handle, indent=2)
print("silenced", len(fired), "demo alert keys")

config = os.path.expanduser("~/.config/omarchy-calendar/config.json")
if "--config" in sys.argv:
    os.makedirs(os.path.dirname(config), exist_ok=True)
    stored = {}
    if os.path.exists(config):
        stored = json.load(open(config))
    stored.setdefault("version", 1)
    stored["accounts"] = [
        {"label": "work", "email": "you@work.example", "priority": 1, "color": "#7aa2f7", "calendars": ["*"], "enabled": True},
        {"label": "personal", "email": "you@gmail.example", "priority": 2, "color": "#9ece6a", "calendars": ["*"], "enabled": True},
    ]
    json.dump(stored, open(config, "w"), indent=2)
    print("wrote fixture accounts to", config)
