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
echo "== reconnect test (client drops mid-run and gets its slot back)"
"$GODOT" --headless --path . -- --host --autostart=2 --name=Host --start-phase=night --quit-after=34 > "$tmp/rhost.log" 2>&1 &
sleep 2
"$GODOT" --headless --path . -- --join=127.0.0.1 --name=Bot --bot --drop-after=8 --quit-after=28 > "$tmp/rclient.log" 2>&1
wait
grep -h "rejoined as" "$tmp/rhost.log"
grep -h SMOKE "$tmp/rclient.log"
if ! grep -q "rejoined as" "$tmp/rhost.log"; then
  echo "reconnect: the host never handed the slot back"; status=1
fi
if [ "$(grep -c 'match\] started' "$tmp/rclient.log")" -lt 2 ] || ! grep -qE "SMOKE client snapshots=[1-9][0-9]+" "$tmp/rclient.log"; then
  echo "reconnect: the client did not get back into the run"; status=1
fi
if grep -q "Node not found" "$tmp/rclient.log"; then
  echo "reconnect: match traffic arrived before the client was ready"; status=1
fi
exit $status
