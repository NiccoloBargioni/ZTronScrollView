#!/bin/bash
# M8b-3 R5 seam lab: runs a list of scenarios through scripts/seam/measure.sh, one after the other, on one simulator.
#
# usage: scripts/seam/baseline.sh <udid> <out-root> <scenario>...
#   scenario = <size>-<start>-<behavior>-<test>[-<extra>...], test = rotate | width | pull | scroll | snap | kbrotate, extras (any order):
#              forced (the forced-fallback lane), capped | refit (-ZTronHeaderOverflow), ambient | glass | color | view
#              (-ZTronHeaderBackground), marker (-ZTronSeamMarker 1: a cyan row at content y 320), refresh (-ZTronSeamRefresh 2.5:
#              a refresher whose action holds 2.5 s, with pull: the refresh hold and its end), band (-ZTronSeamScrollBand 0.5:
#              seam.scroll stops half way into the band), combo (band + -ZTronSeamWidthThenScroll 0.5, with width: a
#              scroll command 0.5 s into the width animation closes the open resize inside its transaction), together
#              (band + -ZTronSeamWidthWithScroll 1: the size change and the scroll in one withAnimation), height<digits> (with width:
#              -ZTronSeamAnimateHeight 0.<digits>, the scroll view's height animates top-pinned instead of its width; height04 = 0.4), hold (-ZTronSeamHold 1: a held refresh from launch, white probe indicator),
#              sticky (-ZTronSeamSticky 1: a white bar in a bottom-aligned overlay of the header); e.g. fixed-rest-preserve-rotate, aspect-half-preserve-width,
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
      height[0-9]*) extra+=(-ZTronSeamAnimateHeight "0.${x#height0}") ;;   # with width: seam.width animates the HEIGHT to 0.<digits> (height04 = 0.4, height025 = 0.25), top-pinned (M8b-s6)
      refresh) extra+=(-ZTronSeamRefresh 2.5) ;;
      hold) extra+=(-ZTronSeamHold 1) ;;       # a held refresh from 0.8 s (white 20 pt probe indicator; scripts/seam/probe.py) (M8b-s6)
      sticky) extra+=(-ZTronSeamSticky 1) ;;   # a white 120 x 16 pt bar in an .overlay(alignment: .bottom) of the header (probe.py) (M8b-s6)
      vbottom) extra+=(-ZTronSeamBottomPinned 1) ;;   # with height<digits>: bottom-pinned, the TOP inset goes 62 -> 0 (M8b-s6 close)
      vboth) extra+=(-ZTronSeamBoth 1) ;;             # with height<digits>: the width animates to 60 % too
      vspring) extra+=(-ZTronSeamSpring 1) ;;         # seam.width animates with .spring(response: 0.55, dampingFraction: 0.5)
      vretarget) extra+=(-ZTronSeamRetarget 0.5) ;;   # seam.width toggles back 0.5 s into the change (additive retarget)
      vland) extra+=(-ZTronSeamLandscape 1) ;;        # with width: in landscape
      near[0-9]*) extra+=(-ZTronSeamRetarget 0.5 -ZTronSeamRetargetNear "${x#near}") ;;   # with height<digits>: 0.5 s in, retarget to the DRAWN height + <digits> pt (core check)
      kbfake) extra+=(-ZTronSeamFakeKeyboard 150) ;;  # with width: seam.width toggles a 150 pt bottom .safeAreaInset, easeInOut 1.2 s (core check)
      kbreal) extra+=(-ZTronSeamKeyboard 1) ;;        # with width / kbrotate: seam.width toggles the system keyboard (D64)
      info) extra+=(-ZTronSeamInfo 2) ;;              # diagnostics only (draws the state line over the lab): DEBUG event log
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
