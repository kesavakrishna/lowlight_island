#!/usr/bin/env bash
# Headless unit + integration tests, then a two-instance network smoke test.
# Usage: GODOT=/path/to/godot tools/run_tests.sh
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."

echo "== unit + integration tests"
"$GODOT" --headless --path . res://tests/test_runner.tscn 2>&1 | grep -E "FAIL|tests:"
status=${PIPESTATUS[0]}

echo "== network smoke test (host + bot client over ENet on localhost)"
tmp="$(mktemp -d)"
"$GODOT" --headless --path . -- --host --autostart=2 --name=Host --start-phase=night --quit-after=16 > "$tmp/host.log" 2>&1 &
sleep 2
"$GODOT" --headless --path . -- --join=127.0.0.1 --name=Bot --bot --quit-after=10 > "$tmp/client.log" 2>&1
wait
grep SMOKE "$tmp/host.log" "$tmp/client.log"
if ! grep -q "SMOKE host players=2" "$tmp/host.log"; then
  echo "smoke: host did not see two players"; status=1
fi
if ! grep -qE "SMOKE client snapshots=[1-9][0-9]+" "$tmp/client.log"; then
  echo "smoke: client received no snapshots"; status=1
fi
exit $status
