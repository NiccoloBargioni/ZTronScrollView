#!/bin/bash
# M8b-3 R5 seam lab: runs a list of scenarios through scripts/seam/measure.sh, one after the other, on one simulator.
#
# usage: scripts/seam/baseline.sh <udid> <out-root> <scenario>...
#   scenario = <size>-<start>-<behavior>-<test>[-forced], e.g. fixed-rest-preserve-rotate, aspect-half-preserve-width,
#              aspect-rest-preserve-rotate-forced; each lands in <out-root>/<scenario>/.
# env: ZS_SEAM_DD (derived data, see measure.sh), ZS_SEAM_INSET (adds -ZTronSeamInset <pt>).
root="$(cd "$(dirname "$0")/../.." && pwd)"
udid="${1:?udid}"; out="${2:?out-root}"; shift 2
for sc in "$@"; do
  IFS=- read -r size start behavior test forced <<<"$sc"
  extra=()
  [ "$forced" = "forced" ] && extra+=(--forced)
  [ -n "${ZS_SEAM_INSET:-}" ] && extra+=(-ZTronSeamInset "$ZS_SEAM_INSET")
  echo "=== $sc"
  "$root/scripts/seam/measure.sh" "$udid" "$test" "$out/$sc" -- -ZTronHeaderSize "$size" -ZTronSeamStart "$start" \
    -ZTronHeaderBehavior "$behavior" "${extra[@]}" 2>&1 | grep -E '^\{|^segment|Executed|TEST (SUCCEEDED|FAILED)|hung|warning: the test'
done
