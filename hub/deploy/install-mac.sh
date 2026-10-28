#!/bin/bash
# Installs the hub on this Mac as a background service that starts at login and restarts if it stops.
# Run again after pulling new code to update it.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
DATA="$HOME/Library/Application Support/HomeBase"
VENV="$DATA/venv"
PLIST="$HOME/Library/LaunchAgents/com.homebase.hub.plist"
PY="${PYTHON:-python3}"

"$PY" -c 'import sys; assert sys.version_info >= (3, 12), "Python 3.12 or newer is needed (brew install python@3.12)"'

mkdir -p "$DATA" "$HOME/Library/LaunchAgents"
[ -d "$VENV" ] || "$PY" -m venv "$VENV"
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet "$HERE"

if [ ! -f "$DATA/hub.toml" ]; then
  cp "$HERE/hub.example.toml" "$DATA/hub.toml"
  echo "Created $DATA/hub.toml. Fill in the LG TV's ip and mac, then run this script again."
  exit 0
fi

sed -e "s|__VENV__|$VENV|g" -e "s|__DATA__|$DATA|g" "$HERE/deploy/com.homebase.hub.plist" > "$PLIST"
DOMAIN="gui/$(id -u)"
launchctl bootout "$DOMAIN/com.homebase.hub" 2>/dev/null || true
# bootout returns before launchd has finished unloading; bootstrapping too soon fails with error 5.
for _ in $(seq 1 20); do
  launchctl print "$DOMAIN/com.homebase.hub" >/dev/null 2>&1 || break
  sleep 0.5
done
for attempt in 1 2 3; do
  launchctl bootstrap "$DOMAIN" "$PLIST" && break
  [ "$attempt" = 3 ] && { echo "Couldn't start the hub service. Check $DATA/hub.log"; exit 1; }
  sleep 2
done

for _ in $(seq 1 20); do
  if curl -fsS "http://127.0.0.1:4900/api/health" >/dev/null 2>&1; then
    echo "Hub is running: http://127.0.0.1:4900"
    exit 0
  fi
  sleep 0.5
done
echo "The hub didn't answer yet. Check $DATA/hub.log"
exit 1
