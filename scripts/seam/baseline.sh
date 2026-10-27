#!/bin/bash
# M8b-3 R5 seam lab: runs a list of scenarios through scripts/seam/measure.sh, one after the other, on one simulator.
#
# usage: scripts/seam/baseline.sh <udid> <out-root> <scenario>...
#   scenario = <size>-<start>-<behavior>-<test>[-<extra>...], test = rotate | width | pull | scroll | snap, extras (any order):
#              forced (the forced-fallback lane), capped | refit (-ZTronHeaderOverflow), ambient | glass | color | view
#              (-ZTronHeaderBackground), marker (-ZTronSeamMarker 1: a cyan row at content y 320), refresh (-ZTronSeamRefresh 2.5:
#              a refresher whose action holds 2.5 s, with pull: the refresh hold and its end), band (-ZTronSeamScrollBand 0.5:
#              seam.scroll stops half way into the band), combo (band + -ZTronSeamWidthThenScroll 0.5, with width: a
#              scroll command 0.5 s into the width animation closes the open resize inside its transaction), together
#              (band + -ZTronSeamWidthWithScroll 1: the size change and the scroll in one withAnimation); e.g. fixed-rest-preserve-rotate, aspect-half-preserve-width,
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
      horizontal) extra+=(-ZTronSeamAxis horizontal) ;;   # a horizontal scroll view: the header is a banner (review d16)
      grow) extra+=(-ZTronSeamFitGrow 1) ;;   # with width + fit: seam.width animates the header's content 16:9 <-> 4:3 (review d16)
      refresh) extra+=(-ZTronSeamRefresh 2.5) ;;
      band) extra+=(-ZTronSeamScrollBand 0.5) ;;
      combo) extra+=(-ZTronSeamScrollBand 0.5 -ZTronSeamWidthThenScroll 0.5) ;;
      together) extra+=(-ZTronSeamScrollBand 0.5 -ZTronSeamWidthWithScroll 1) ;;
      *) echo "unknown scenario extra '$x' in $sc" >&2 ;;
    esac
  done
  [ -n "${ZS_SEAM_INSET:-}" ] && extra+=(-ZTronSeamInset "$ZS_SEAM_INSET")
  echo "=== $sc"
  "$root/scripts/seam/measure.sh" "$udid" "$test" "$out/$sc" -- -ZTronHeaderSize "$size" -ZTronSeamStart "$start" \
    -ZTronHeaderBehavior "$behavior" "${extra[@]}" 2>&1 | grep -E '^\{|^segment|Executed|TEST (SUCCEEDED|FAILED)|hung|warning: the test'
done
