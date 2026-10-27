#!/bin/bash
# M8b-3 R5 seam lab: runs a list of scenarios through scripts/seam/measure.sh, one after the other, on one simulator.
#
# usage: scripts/seam/baseline.sh <udid> <out-root> <scenario>...
#   scenario = <size>-<start>-<behavior>-<test>[-<extra>...], test = rotate | width | pull | scroll | snap, extras (any order):
#              forced (the forced-fallback lane), capped | refit (-ZTronHeaderOverflow), ambient | glass | color | view
#              (-ZTronHeaderBackground), marker (-ZTronSeamMarker 1: a cyan row at content y 320), refresh (-ZTronSeamRefresh 2.5:
#              a refresher whose action holds 2.5 s, with pull: the refresh hold and its end); e.g. fixed-rest-preserve-rotate, aspect-half-preserve-width,
#              aspect-rest-preserve-rotate-capped-forced, fixed-rest-preserve-pull; each lands in <out-root>/<scenario>/.
# env: ZS_SEAM_DD (derived data, see measure.sh), ZS_SEAM_INSET (adds -ZTronSeamInset <pt>).
root="$(cd "$(dirname "$0")/../.." && pwd)"
udid="${1:?udid}"; out="${2:?out-root}"; shift 2
for sc in "$@"; do
  IFS=- read -r size start behavior test rest <<<"$sc"
  extra=()
  for x in ${rest//-/ }; do
    case "$x" in
      forced) extra+=(--forced) ;;
      capped|refit|uncapped) extra+=(-ZTronHeaderOverflow "$x") ;;
      ambient|glass|color|view) extra+=(-ZTronHeaderBackground "$x") ;;
      marker) extra+=(-ZTronSeamMarker 1) ;;
      refresh) extra+=(-ZTronSeamRefresh 2.5) ;;
      *) echo "unknown scenario extra '$x' in $sc" >&2 ;;
    esac
  done
  [ -n "${ZS_SEAM_INSET:-}" ] && extra+=(-ZTronSeamInset "$ZS_SEAM_INSET")
  echo "=== $sc"
  "$root/scripts/seam/measure.sh" "$udid" "$test" "$out/$sc" -- -ZTronHeaderSize "$size" -ZTronSeamStart "$start" \
    -ZTronHeaderBehavior "$behavior" "${extra[@]}" 2>&1 | grep -E '^\{|^segment|Executed|TEST (SUCCEEDED|FAILED)|hung|warning: the test'
done
