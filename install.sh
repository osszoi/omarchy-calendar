#!/bin/bash
# Symlink the plugin into omarchy, build the python venv, install the sync
# timer, and put the widget where the stock clock was.

set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_ID=eduardo.calendar
PLUGIN_DIR=$HOME/.config/omarchy/plugins/$PLUGIN_ID
CONFIG_DIR=$HOME/.config/omarchy-calendar
DATA_DIR=$HOME/.local/share/omarchy-calendar
VENV_DIR=$DATA_DIR/venv
SHELL_JSON=$HOME/.config/omarchy/shell.json
UNIT_DIR=$HOME/.config/systemd/user

say() { printf '\033[1;32m==>\033[0m %s\n' "$1"; }

say "Linking $PLUGIN_DIR -> $REPO_DIR"
mkdir -p "$(dirname "$PLUGIN_DIR")"
ln -sfn "$REPO_DIR" "$PLUGIN_DIR"

say "Python environment"
mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$DATA_DIR/tokens"
chmod 700 "$DATA_DIR/tokens"
[[ -d $VENV_DIR ]] || /usr/bin/python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet google-api-python-client google-auth-httplib2 google-auth-oauthlib

if [[ ! -f $CONFIG_DIR/config.json ]]; then
  say "Writing default config"
  cat > "$CONFIG_DIR/config.json" <<'JSON'
{
  "version": 1,
  "accounts": [],
  "leadMinutes": [5, 1],
  "upcomingWindowMinutes": 60,
  "syncWindowDays": 60,
  "syncPastDays": 7,
  "catchUpMinutes": 10,
  "maxTitleChars": 28,
  "filters": {
    "skipDeclined": true,
    "skipAllDay": true,
    "skipSolo": true,
    "skipFree": true
  }
}
JSON
fi

say "Sync timer"
mkdir -p "$UNIT_DIR"
cat > "$UNIT_DIR/omarchy-calendar-sync.service" <<UNIT
[Unit]
Description=Sync Google calendars for the omarchy calendar widget
After=network-online.target

[Service]
Type=oneshot
ExecStart=$REPO_DIR/bin/omarchy-calendar-sync
UNIT

cat > "$UNIT_DIR/omarchy-calendar-sync.timer" <<'UNIT'
[Unit]
Description=Keep the omarchy calendar events fresh

[Timer]
OnBootSec=20s
OnUnitActiveSec=60s
AccuracySec=5s

[Install]
WantedBy=timers.target
UNIT

systemctl --user daemon-reload
# Only worth running once an account exists; connecting one starts it.
if [[ -n $(find "$DATA_DIR/tokens" -name '*.json' -print -quit 2>/dev/null) ]]; then
  systemctl --user enable --now omarchy-calendar-sync.timer
else
  say "No account connected yet — the sync timer starts when you add one"
fi

say "Registering the plugin"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

# Take the stock clock's slot rather than being appended somewhere else: same
# position in the center section, and the bar's center anchor moves with it.
if [[ -f $SHELL_JSON ]] && command -v jq >/dev/null; then
  if jq -e '[.bar.layout[]?[]? | select(.id == "'"$PLUGIN_ID"'")] | length > 0' "$SHELL_JSON" >/dev/null; then
    say "Already in the bar layout"
  else
    backup=$SHELL_JSON.bak.$(date +%Y%m%d%H%M%S)
    cp "$SHELL_JSON" "$backup"
    say "Swapping omarchy.clock for $PLUGIN_ID (backup: $backup)"
    tmp=$(mktemp)
    jq --arg id "$PLUGIN_ID" '
      (.bar.layout |= with_entries(.value |= map(if .id == "omarchy.clock" then .id = $id else . end)))
      | (if .bar.centerAnchor == "omarchy.clock" then .bar.centerAnchor = $id else . end)
    ' "$SHELL_JSON" > "$tmp"
    mv "$tmp" "$SHELL_JSON"
  fi
fi

say "Done. Restart the shell with: omarchy restart shell"
