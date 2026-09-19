"""Shared paths, config and Google plumbing for the omarchy-calendar helpers."""

import json
import os
import re
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone

HOME = os.path.expanduser("~")
CONFIG_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")), "omarchy-calendar")
DATA_DIR = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.join(HOME, ".local", "share")), "omarchy-calendar")
CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")), "omarchy-calendar")

CONFIG_PATH = os.path.join(CONFIG_DIR, "config.json")
CLIENT_SECRET_PATH = os.path.join(CONFIG_DIR, "client_secret.json")
TOKEN_DIR = os.path.join(DATA_DIR, "tokens")
VENV_DIR = os.path.join(DATA_DIR, "venv")

EVENTS_PATH = os.path.join(CACHE_DIR, "events.json")
STATUS_PATH = os.path.join(CACHE_DIR, "status.json")

SCOPES = ["https://www.googleapis.com/auth/calendar.readonly"]

DEFAULT_CONFIG = {
    "version": 1,
    "accounts": [],
    "leadMinutes": [5, 1],
    "upcomingWindowMinutes": 60,
    "syncWindowDays": 60,
    "syncPastDays": 7,
    "catchUpMinutes": 10,
    "maxTitleChars": 28,
    "filters": {
        "skipDeclined": True,
        "skipAllDay": True,
        "skipSolo": True,
        "skipFree": True,
    },
}

PALETTE = ["#7aa2f7", "#9ece6a", "#e0af68", "#bb9af7", "#f7768e", "#7dcfff", "#c0caf5", "#ff9e64"]


def reexec_into_venv():
    """Helpers are launched by the shell/systemd, not by a shell with the venv active.

    The test is sys.prefix, not the interpreter path: a venv's `bin/python` is a
    symlink to the system interpreter, so comparing resolved executables says
    "already inside" while none of the venv's packages are importable. The env
    flag is the loop guard, in case a venv is ever too broken to set prefix."""
    venv_python = os.path.join(VENV_DIR, "bin", "python")
    if os.path.realpath(sys.prefix) == os.path.realpath(VENV_DIR):
        return
    if not os.path.exists(venv_python):
        return
    # One helper execs another (account -> sync), and the child starts from its
    # own shebang, so the guard counts attempts instead of latching: a flag set
    # by the parent would tell the child it was already inside the venv.
    tries = int(os.environ.get("OMARCHY_CALENDAR_VENV_TRIES") or 0)
    if tries >= 2:
        return
    os.environ["OMARCHY_CALENDAR_VENV_TRIES"] = str(tries + 1)
    os.execv(venv_python, [venv_python] + sys.argv)


def ensure_dirs():
    for path in (CONFIG_DIR, DATA_DIR, CACHE_DIR, TOKEN_DIR):
        os.makedirs(path, exist_ok=True)
    os.chmod(TOKEN_DIR, 0o700)


def write_json_atomic(path, payload, mode=0o644):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".tmp-")
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(payload, handle, indent=2, sort_keys=False)
            handle.write("\n")
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def read_json(path, fallback=None):
    try:
        with open(path) as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return fallback


def load_config():
    config = dict(DEFAULT_CONFIG)
    stored = read_json(CONFIG_PATH)
    if isinstance(stored, dict):
        filters = dict(DEFAULT_CONFIG["filters"])
        filters.update(stored.get("filters") or {})
        config.update(stored)
        config["filters"] = filters
    if not isinstance(config.get("accounts"), list):
        config["accounts"] = []
    return config


def save_config(config):
    ensure_dirs()
    write_json_atomic(CONFIG_PATH, config)


def token_path(label):
    return os.path.join(TOKEN_DIR, "%s.json" % slugify(label))


def slugify(label):
    return re.sub(r"[^a-z0-9._-]+", "-", str(label).strip().lower()).strip("-") or "account"


def next_color(config):
    used = {str(a.get("color", "")).lower() for a in config.get("accounts", [])}
    for color in PALETTE:
        if color.lower() not in used:
            return color
    return PALETTE[len(config.get("accounts", [])) % len(PALETTE)]


def account_by_label(config, label):
    for account in config.get("accounts", []):
        if account.get("label") == label:
            return account
    return None


# ---------------------------------------------------------------- google

def load_credentials(label):
    from google.oauth2.credentials import Credentials

    path = token_path(label)
    if not os.path.exists(path):
        return None
    return Credentials.from_authorized_user_file(path, SCOPES)


def refresh_credentials(label, creds):
    """Returns (creds, error). A revoked or expired-beyond-refresh token is an error the UI shows."""
    from google.auth.transport.requests import Request
    from google.auth.exceptions import RefreshError

    if creds and creds.valid:
        return creds, None
    if creds and creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
        except RefreshError as exc:
            return None, "needs-reauth: %s" % exc
        except Exception as exc:  # network down, DNS, proxy
            return None, "refresh-failed: %s" % exc
        save_credentials(label, creds)
        return creds, None
    return None, "needs-reauth"


def save_credentials(label, creds):
    ensure_dirs()
    fd, tmp = tempfile.mkstemp(dir=TOKEN_DIR, prefix=".tmp-")
    with os.fdopen(fd, "w") as handle:
        handle.write(creds.to_json())
    os.chmod(tmp, 0o600)
    os.replace(tmp, token_path(label))


def build_service(creds):
    from googleapiclient.discovery import build

    return build("calendar", "v3", credentials=creds, cache_discovery=False)


# ---------------------------------------------------------------- events

MEET_PATTERNS = [
    r"https://meet\.google\.com/[a-z0-9-]+",
    r"https://[a-z0-9.-]*zoom\.us/j/[^\s<>\"']+",
    r"https://teams\.microsoft\.com/l/meetup-join/[^\s<>\"']+",
    r"https://[a-z0-9.-]*whereby\.com/[^\s<>\"']+",
    r"https://meet\.jit\.si/[^\s<>\"']+",
    r"https://[a-z0-9.-]*around\.co/[^\s<>\"']+",
]


def meeting_link(event):
    link = event.get("hangoutLink")
    if link:
        return link
    conference = event.get("conferenceData") or {}
    for entry in conference.get("entryPoints") or []:
        if entry.get("entryPointType") == "video" and entry.get("uri"):
            return entry["uri"]
    for field in ("location", "description"):
        text = event.get(field) or ""
        for pattern in MEET_PATTERNS:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                return match.group(0)
    # A bare URL in the location is almost always the call
    match = re.search(r"https?://[^\s<>\"']+", event.get("location") or "")
    return match.group(0) if match else ""


def self_response(event):
    for attendee in event.get("attendees") or []:
        if attendee.get("self"):
            return attendee.get("responseStatus") or "needsAction"
    if (event.get("creator") or {}).get("self") or (event.get("organizer") or {}).get("self"):
        return "accepted"
    return "unknown"


def other_attendees(event):
    return [a for a in (event.get("attendees") or []) if not a.get("self") and not a.get("resource")]


def to_epoch(stamp):
    """RFC3339 with offset, or a bare date for all-day."""
    if not stamp:
        return 0
    if len(stamp) == 10:
        return int(datetime.fromisoformat(stamp).replace(tzinfo=None).timestamp())
    return int(datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp())


def normalize_event(event, account, calendar_id, calendar_name):
    start = event.get("start") or {}
    end = event.get("end") or {}
    all_day = "date" in start
    return {
        "id": "%s:%s:%s" % (account["label"], calendar_id, event.get("id") or ""),
        "account": account["label"],
        "priority": int(account.get("priority", 99)),
        "color": account.get("color") or "#7aa2f7",
        "calendar": calendar_name or calendar_id,
        "calendarId": calendar_id,
        "title": (event.get("summary") or "(no title)").strip(),
        "start": to_epoch(start.get("dateTime") or start.get("date")),
        "end": to_epoch(end.get("dateTime") or end.get("date")),
        "allDay": all_day,
        "link": meeting_link(event),
        "htmlLink": event.get("htmlLink") or "",
        "location": (event.get("location") or "").strip(),
        "response": self_response(event),
        "attendees": len(other_attendees(event)),
        "transparency": event.get("transparency") or "opaque",
        "status": event.get("status") or "confirmed",
    }


def should_keep(event, filters):
    if event["status"] == "cancelled":
        return False
    if filters.get("skipAllDay", True) and event["allDay"]:
        return False
    if filters.get("skipDeclined", True) and event["response"] == "declined":
        return False
    if filters.get("skipFree", True) and event["transparency"] == "transparent":
        return False
    if filters.get("skipSolo", True) and event["attendees"] == 0:
        return False
    return event["end"] > event["start"] or event["allDay"]


def filters_for(config, account):
    """Global filters, with the account's own overrides on top.

    A work calendar wants solo focus blocks and holidays out of the way; a
    personal one is mostly those, and filtering them leaves nothing at all.
    """
    merged = dict(DEFAULT_CONFIG["filters"])
    merged.update(config.get("filters") or {})
    merged.update(account.get("filters") or {})
    return merged


def window(config, now=None):
    start, end = window_dt(config, now)
    return (start.isoformat().replace("+00:00", "Z"),
            end.isoformat().replace("+00:00", "Z"))


def window_dt(config, now=None):
    now = now or datetime.now(timezone.utc)
    start = now - timedelta(days=int(config.get("syncPastDays", 7)))
    end = now + timedelta(days=int(config.get("syncWindowDays", 60)))
    return start, end


def now_epoch():
    return int(time.time())
