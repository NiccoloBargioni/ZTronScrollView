#!/bin/bash
# M8b-s8 s6 (D76, from the i28 spike): shot.sh <udid> <outdir> <label> <wait-seconds> [launch args...]
# Launches the scratch demo's seam lab with the args, waits, takes a lossless PNG screenshot, saves stdout, terminates.
udid="$1"; out="$2"; label="$3"; wait="$4"; shift 4
mkdir -p "$out"
B=dev.ztron.ZTronScrollViewDemo
xcrun simctl terminate "$udid" "$B" >/dev/null 2>&1
xcrun simctl launch --console-pty --terminate-running-process "$udid" "$B" -ZTronScreen seamlab "$@" > "$out/$label.log" 2>&1 &
pid=$!
sleep "$wait"
xcrun simctl io "$udid" screenshot --type=png "$out/$label.png" >/dev/null 2>&1
echo "$label $(date +%T) load $(uptime | sed 's/.*averages: //')" >> "$out/shots.txt"
sleep "${SHOT_TAIL:-0}"
xcrun simctl terminate "$udid" "$B" >/dev/null 2>&1
sleep 0.5
kill "$pid" >/dev/null 2>&1
wait "$pid" 2>/dev/null
exit 0
