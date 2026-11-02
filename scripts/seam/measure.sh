#!/bin/bash
# M8b-3 R5 seam lab: records the simulator screen while one SeamLabUITests method drives the seam lab, then measures
# the header/content seam per frame (scripts/seam/analyze.py).
#
# usage: scripts/seam/measure.sh <udid> <rotate|rotatel|width|pull|scroll|snap|kbrotate|fling> <out-dir> -- <launch args...> [--forced]
#   e.g. scripts/seam/measure.sh 7190…60FA rotate out/aspect-rest -- -ZTronHeaderSize aspect -ZTronSeamStart rest
# env: ZS_SEAM_DD     derived-data path (default: <repo>/.dd/<udid>; one xcodebuild per path)
#      ZS_SEAM_TIMEOUT seconds before the test run is killed as hung (default 1500)
#      ZS_SEAM_ANALYZE_ARGS extra analyze.py arguments (default none; e.g. "--open-gap pull", D65)
# Output in <out-dir>: rec.mov (the recording), meta.json, test.log, frames.csv, summary.json, worst-*.png.
set -u
root="$(cd "$(dirname "$0")/../.." && pwd)"
udid="${1:?udid}"; test="${2:?rotate|rotatel|width|pull|scroll|snap|kbrotate|fling}"; out="${3:?out-dir}"; shift 3
[ "${1:-}" = "--" ] && shift
forced=""; args=()
for a in "$@"; do
  if [ "$a" = "--forced" ]; then forced="--forced"; else args+=("$a"); fi
done
case "$test" in
  rotate) method="testRotate" ;;
  rotatel) method="testRotateFromLandscape" ;;   # open item 19: landscape rest, portrait, landscape again
  width) method="testWidth" ;;
  pull) method="testPull" ;;
  scroll) method="testScroll" ;;
  snap) method="testSnap" ;;
  kbrotate) method="testKeyboardRotate" ;;   # D64: keyboard up, rotation there and back, keyboard down (with kbreal)
  fling) method="testFling" ;;   # a finger fling up, then one back (fdown / fv / fb / fd extras in baseline.sh)
  *) echo "test must be rotate, rotatel, width, pull, scroll, snap, kbrotate or fling" >&2; exit 2 ;;
esac
mkdir -p "$out"; out="$(cd "$out" && pwd)"
dd="${ZS_SEAM_DD:-$root/.dd/$udid}"
timeout="${ZS_SEAM_TIMEOUT:-1500}"

# Boot (no-op when booted) and wait until the device is usable.
xcrun simctl bootstatus "$udid" -b >/dev/null || { echo "cannot boot $udid" >&2; exit 1; }

# Metadata: the device type gives the display scale (points -> pixels); the analyzer reads meta.json.
xcrun simctl list devices -j | python3 -I -c '
import json, sys
udid, test, args, forced, out = sys.argv[1:6]
scales = {"iPhone-18-Pro": 3, "iPhone-18-Pro-Max": 3, "iPhone-17-Pro": 3, "iPhone-16-Pro": 3, "iPhone-15-Pro": 3,
          "iPhone-15-Pro-Max": 3}
for runtime, devs in json.load(sys.stdin)["devices"].items():
    for d in devs:
        if d["udid"] == udid:
            kind = d["deviceTypeIdentifier"].rsplit(".", 1)[-1]
            meta = {"udid": udid, "name": d["name"], "deviceType": kind, "runtime": runtime.rsplit(".", 1)[-1],
                    "scale": scales.get(kind, 3), "test": test, "launchArgs": args.split(), "forced": forced == "1"}
            json.dump(meta, open(out + "/meta.json", "w"), indent=1)
            print("device", d["name"], kind, runtime.rsplit(".", 1)[-1], "scale", meta["scale"])
            sys.exit(0)
sys.exit("udid not found")
' "$udid" "$test" "${args[*]:-}" "$([ -n "$forced" ] && echo 1 || echo 0)" "$out" || exit 1

# Start the recording and wait until it runs.
rm -f "$out/rec.mov"
xcrun simctl io "$udid" recordVideo --codec h264 --force "$out/rec.mov" >"$out/rec.log" 2>&1 &
rec=$!
for _ in $(seq 1 100); do
  grep -q "Recording started" "$out/rec.log" 2>/dev/null && break
  kill -0 "$rec" 2>/dev/null || { echo "recordVideo exited: $(cat "$out/rec.log")" >&2; exit 1; }
  sleep 0.2
done

# The UI test (the scenario's launch arguments travel in ZS_SEAM_ARGS / TEST_RUNNER_ZS_SEAM_ARGS).
export ZS_SEAM_ARGS="${args[*]:-}" TEST_RUNNER_ZS_SEAM_ARGS="${args[*]:-}"
"$root/scripts/test-demo-ui.sh" "id=$udid" $forced -derivedDataPath "$dd" -collect-test-diagnostics never \
  "-only-testing:ZTronScrollViewDemoUITests/SeamLabUITests/$method" >"$out/test.log" 2>&1 &
run=$!
elapsed=0
while kill -0 "$run" 2>/dev/null; do
  if [ "$elapsed" -ge "$timeout" ]; then
    echo "test run hung after ${timeout}s: killing" >&2
    pkill -P "$run" 2>/dev/null; kill "$run" 2>/dev/null
    break
  fi
  sleep 2; elapsed=$((elapsed + 2))
done
wait "$run"; rc=$?
cat "$out/test.log"

# Stop the recording (SIGINT finalizes the file) and wait for the writer to exit.
kill -INT "$rec" 2>/dev/null
wait "$rec" 2>/dev/null
for _ in $(seq 1 50); do ffprobe -v error "$out/rec.mov" >/dev/null 2>&1 && break; sleep 0.2; done
[ "$rc" -eq 0 ] || echo "warning: the test run exited $rc (measuring the recording anyway)" >&2

python3 -I "$root/scripts/seam/analyze.py" "$out/rec.mov" --meta "$out/meta.json" --out "$out" ${ZS_SEAM_ANALYZE_ARGS:-}
