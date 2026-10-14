#!/bin/bash
log="$(mktemp -t ztronscroll-log)"
"$@" >"$log" 2>&1
rc=$?
grep -E '(error|warning):|\*\* (BUILD|TEST) (SUCCEEDED|FAILED) \*\*|Test Case .* failed|Executed [0-9]+ tests?|✘|Test run with' "$log" \
  | awk '!seen[$0]++' | head -n 120
echo "exit=$rc · full log: $log"
exit "$rc"
