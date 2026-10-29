#!/bin/bash
# Installs the Home Base helper on a Mac (e.g. the MacBook Air) so the hub can sleep or shut it down.
# Prints the token to put in the hub's hub.toml.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="$HOME/Library/Application Support/HomeBase"
PLIST="$HOME/Library/LaunchAgents/com.homebase.agent.plist"
DOMAIN="gui/$(id -u)"
PY="$(command -v python3)"

mkdir -p "$DATA" "$HOME/Library/LaunchAgents"
cp "$HERE/homebase_agent.py" "$DATA/homebase_agent.py"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.homebase.agent</string>
  <key>ProgramArguments</key><array><string>$PY</string><string>$DATA/homebase_agent.py</string></array>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$DATA/agent.log</string>
</dict></plist>
PL

launchctl bootout "$DOMAIN/com.homebase.agent" 2>/dev/null || true
for _ in $(seq 1 20); do launchctl print "$DOMAIN/com.homebase.agent" >/dev/null 2>&1 || break; sleep 0.5; done
for attempt in 1 2 3; do
  launchctl bootstrap "$DOMAIN" "$PLIST" && break
  [ "$attempt" = 3 ] && { echo "Couldn't start the helper. Check $DATA/agent.log"; exit 1; }
  sleep 2
done

echo "Helper running on port 4901. Token for hub.toml:"
"$PY" "$DATA/homebase_agent.py" --token
