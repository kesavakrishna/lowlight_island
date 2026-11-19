#!/usr/bin/env bash
# Soak test: a host and two clients, all "chaos" bots pressing every action at random,
# over several fast day/night cycles. Fails if any instance logs a script or engine error.
# Usage: GODOT=/path/to/godot tools/soak_test.sh [seconds]
set -u
GODOT="${GODOT:-godot}"
SECS="${1:-200}"
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
"$GODOT" --headless --path . -- --host --autostart=3 --name=Host --bot=chaos --fast-clock=6 --quit-after="$SECS" > "$tmp/h.log" 2>&1 &
sleep 2
"$GODOT" --headless --path . -- --join=127.0.0.1 --name=BotA --bot=chaos --quit-after=$((SECS - 10)) > "$tmp/a.log" 2>&1 &
"$GODOT" --headless --path . -- --join=127.0.0.1 --name=BotB --bot=chaos --quit-after=$((SECS - 12)) > "$tmp/b.log" 2>&1
wait
status=0
for f in h a b; do
  grep -h SMOKE "$tmp/$f.log"
  if grep -qE "SCRIPT ERROR|^ERROR:" "$tmp/$f.log"; then
    echo "soak: errors in $f.log"; grep -E -A3 "SCRIPT ERROR|^ERROR:" "$tmp/$f.log" | head -20; status=1
  fi
done
exit $status
