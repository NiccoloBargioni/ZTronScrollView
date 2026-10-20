#!/bin/bash
# 100 % line-coverage gate of Sources/ZTronScrollView/Gesture/UIKit/ (SPEC S14, D31; design docs/design/UIKIT-touch-observer.md §5, R5/R6).
# usage: scripts/coverage-uikit.sh [--run] [--dest <xcodebuild destination>] [--also-dest <destination>] [--out <dir>] [--dd <derivedDataPath> ...]
#   --run   first run, with coverage, the unit suites of the pure core (+ shell) and UIKitObserverUITests twice (preferred and
#           -ZTronForceAllFallbacks) into <out>/dd-unit, dd-ui, dd-ui-forced; stops at the first red run.
#   --also-dest  with --run: one more UIKitObserverUITests run (forced) on a second destination into <out>/dd-ui-also. The
#           iOS 17.5 simulator is the one where sending the app to Settings mid-press makes UIKit cancel the touch
#           (`touchesCancelled` for real); the 27.0 one does not (R6).
#   --dd    add a derived-data dir that already ran with -enableCodeCoverage YES (repeatable; --run adds its own).
#   --dest  destination for --run (default $ZS_DEST); --out defaults to .build/coverage-uikit.
# The union of all bundles counts: a line is covered if ANY bundle executed it. Output: per-file line coverage and every
# uncovered file:line; exit 1 unless every file of the directory is 100 %.
# Route (UIKIT-s1 finding): on this SwiftPM scheme `xccov` lists no package files, so the profile is read with llvm-cov
# (Coverage.profdata + the test bundle / demo app binaries of the derived-data dir).
cd "$(dirname "$0")/.." || exit 1
run=0; dest="${ZS_DEST:-}"; also=""; out=".build/coverage-uikit"; dds=()
while [ $# -gt 0 ]; do
  case "$1" in
    --run) run=1 ;;
    --dest) dest="$2"; shift ;;
    --also-dest) also="$2"; shift ;;
    --out) out="$2"; shift ;;
    --dd) dds+=("$2"); shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
if [ "$run" = 1 ]; then
  : "${dest:?set --dest or ZS_DEST}"
  mkdir -p "$out" && out="$(cd "$out" && pwd)"   # absolute: the demo run starts from Demo/
  suites=(-only-testing:ZTronScrollViewTests/TouchObserverCoreTests -only-testing:ZTronScrollViewTests/TouchObserverSpatialEquivalenceTests
          -only-testing:ZTronScrollViewTests/UIKitObserverGatingTests -only-testing:ZTronScrollViewTests/UIKitObserverShellTests)
  ZS_DEST="$dest" scripts/test.sh -derivedDataPath "$out/dd-unit" -enableCodeCoverage YES "${suites[@]}" || { echo "unit run failed"; exit 1; }
  scripts/test-demo-ui.sh "$dest" -derivedDataPath "$out/dd-ui" -enableCodeCoverage YES \
    -only-testing:ZTronScrollViewDemoUITests/UIKitObserverUITests || { echo "UI run failed"; exit 1; }
  scripts/test-demo-ui.sh "$dest" --forced -derivedDataPath "$out/dd-ui-forced" -enableCodeCoverage YES \
    -only-testing:ZTronScrollViewDemoUITests/UIKitObserverUITests || { echo "forced UI run failed"; exit 1; }
  dds+=("$out/dd-unit" "$out/dd-ui" "$out/dd-ui-forced")
  if [ -n "$also" ]; then
    scripts/test-demo-ui.sh "$also" --forced -derivedDataPath "$out/dd-ui-also" -enableCodeCoverage YES \
      -only-testing:ZTronScrollViewDemoUITests/UIKitObserverUITests || { echo "UI run on $also failed"; exit 1; }
    dds+=("$out/dd-ui-also")
  fi
fi
[ ${#dds[@]} -gt 0 ] || { echo "no bundles: pass --run or --dd <derivedDataPath>" >&2; exit 2; }

python3 -I - "${dds[@]}" <<'EOF'
import glob, os, re, subprocess, sys

DIR = "Sources/ZTronScrollView/Gesture/UIKit/"
expected = sorted(f for f in glob.glob(DIR + "*.swift"))
covered, executable, fatal = {}, {}, False   # file -> {line}
unit_only, ui_seen = {}, False                 # file -> {line} executed by the unit bundle(s) only (R6 report)
by_kind = {"unit": {}, "ui": {}}               # kind -> file -> {line} executed

def objects(dd):
    """Instrumented binaries of one derived-data dir: test bundle executable(s), demo app executable + debug dylibs."""
    found = []
    for prod in glob.glob(os.path.join(dd, "Build/Products/*-iphonesimulator")):
        for bundle in glob.glob(prod + "/*.xctest") + glob.glob(prod + "/*.app"):
            name = os.path.splitext(os.path.basename(bundle))[0]
            if name.endswith("-Runner"): continue   # the XCUITest runner app: no library code
            for f in glob.glob(bundle + "/*"):
                if os.path.isfile(f) and (os.path.basename(f) == name or f.endswith(".debug.dylib")): found.append(f)
    return sorted(found)

for dd in sys.argv[1:]:
    profs = sorted(glob.glob(os.path.join(dd, "Build/ProfileData/*/Coverage.profdata")), key=os.path.getmtime)
    objs = objects(dd)
    if not profs or not objs:
        print(f"FAIL {dd}: no Coverage.profdata / binaries (was it run with -enableCodeCoverage YES?)"); fatal = True; continue
    cmd = ["xcrun", "llvm-cov", "export", "-format=lcov", f"-instr-profile={profs[-1]}", objs[0]]
    for o in objs[1:]: cmd += ["-object", o]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"FAIL {dd}: llvm-cov export: {res.stderr.strip()[:300]}"); fatal = True; continue
    kind = "unit" if any(".xctest/" in o for o in objs) else "ui"
    ui_seen = ui_seen or kind == "ui"
    seen, cur = set(), None
    for line in res.stdout.splitlines():
        if line.startswith("SF:"):
            path = line[3:]
            cur = next((e for e in expected if path.endswith("/" + e)), None)
            if cur: seen.add(cur); executable.setdefault(cur, set()); covered.setdefault(cur, set())
        elif cur and line.startswith("DA:"):
            n, count = line[3:].split(",")[:2]
            executable[cur].add(int(n))
            if int(count) > 0:
                covered[cur].add(int(n))
                by_kind[kind].setdefault(cur, set()).add(int(n))
        elif line == "end_of_record": cur = None
    missing = [e for e in expected if e not in seen]
    print(f"bundle {dd}: {len(seen)}/{len(expected)} files of {DIR} listed, binaries: {len(objs)}")
    if missing:
        print(f"FAIL {dd}: coverage lists no {missing}: the scheme must instrument the package target (design risk 4)"); fatal = True

total_bad = 0
for f in expected:
    ex, co = executable.get(f, set()), covered.get(f, set())
    pct = 100.0 * len(co) / len(ex) if ex else 0.0
    status = "OK  " if ex and len(co) == len(ex) else "FAIL"
    print(f"{status} {f}: {pct:.1f} % lines ({len(co)}/{len(ex)})")
    src = open(f, encoding="utf-8").read().splitlines()
    for n in sorted(ex - co):
        print(f"  uncovered {f}:{n}: {src[n-1].strip()}"); total_bad += 1
    if not ex: total_bad += 1
if ui_seen:
    # Lines the demo UI run never reached with a real touch, covered by the unit run only: UIKit never asks a recognizer
    # that never recognizes for `canPrevent` / `shouldRecognizeSimultaneouslyWith`, and the simulators never cancel a touch
    # (R6: `touchesCancelled` is executed by a direct call in `UIKitObserverShellTests`, line gate only; the cancel behaviour
    # is the core tests', the real delivery is the user's device check on iOS 15/16). Core lines are the cancel / replaced-`began`
    # branches, covered by synthetic batches.
    for f in expected:
        only = sorted(covered.get(f, set()) - by_kind["ui"].get(f, set()))
        for n in only: print(f"  unit-run only (R6 / pinned answers / synthetic batch): {f}:{n}: {open(f, encoding='utf-8').read().splitlines()[n-1].strip()}")
ok = not fatal and total_bad == 0
print("coverage-uikit:", "PASS (100 % lines in every file)" if ok else f"FAIL ({total_bad} uncovered line(s)/file(s))")
sys.exit(0 if ok else 1)
EOF
