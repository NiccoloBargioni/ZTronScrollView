#!/bin/bash
# M8b-s8 s6 (D76, from the i28 spike): mixseq.sh <udid> <outdir> <label> <first-shot-s> <n-shots> [launch args...]
# Launches the seam lab, waits <first-shot-s>, then takes <n-shots> lossless screenshots back to back (t logged).
udid="$1"; out="$2"; label="$3"; first="$4"; n="$5"; shift 5
mkdir -p "$out"
B=dev.ztron.ZTronScrollViewDemo
xcrun simctl terminate "$udid" "$B" >/dev/null 2>&1
t0=$(python3 -c 'import time; print(time.time())')
xcrun simctl launch --console-pty --terminate-running-process "$udid" "$B" -ZTronScreen seamlab "$@" > "$out/$label.log" 2>&1 &
pid=$!
sleep "$first"
for i in $(seq -w 1 "$n"); do
  xcrun simctl io "$udid" screenshot --type=png "$out/$label-$i.png" >/dev/null 2>&1
  python3 -c "import time; print('$label-$i %.3f' % (time.time() - $t0))" >> "$out/times.txt"
done
echo "$label $(date +%T) load $(uptime | sed 's/.*averages: //')" >> "$out/shots.txt"
xcrun simctl terminate "$udid" "$B" >/dev/null 2>&1
sleep 0.5; kill "$pid" >/dev/null 2>&1; wait "$pid" 2>/dev/null
exit 0
