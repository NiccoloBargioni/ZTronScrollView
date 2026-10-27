#!/bin/bash
log="$(mktemp -t ztronscroll-log)"
"$@" >"$log" 2>&1
rc=$?
grep -E '(error|warning):|\*\* (BUILD|TEST) (SUCCEEDED|FAILED) \*\*|Test Case .* failed|Executed [0-9]+ tests?|✘|Test run with' "$log" \
  | awk '!seen[$0]++' | head -n 120
# UIKit's "Observation tracking feedback loop detected" must stay at 0 (DBG-s9): any occurrence fails the run.
loops=$(grep -cF 'Observation tracking feedback loop detected! Make a symbolic breakpoint' "$log")
if [ "$loops" -gt 0 ]; then
  echo "error: $loops UIKit 'Observation tracking feedback loop detected' warnings (must be 0, DBG-s9); objects:"
  grep -o 'invalidations: <[A-Za-z_.]*: 0x[0-9a-f]*' "$log" | sort | uniq -c | sort -rn | head -n 5
  [ "$rc" -eq 0 ] && rc=1
fi
echo "exit=$rc · full log: $log"
exit "$rc"
