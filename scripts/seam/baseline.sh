#!/bin/bash
# M8b-3 R5 seam lab: runs a list of scenarios through scripts/seam/measure.sh, one after the other, on one simulator.
#
# usage: scripts/seam/baseline.sh <udid> <out-root> <scenario>...
#   scenario = <size>-<start>-<behavior>-<test>[-<extra>...], test = rotate | rotatel (from landscape) | width | pull | scroll | snap | kbrotate, extras (any order):
#              forced (the forced-fallback lane), capped | refit (-ZTronHeaderOverflow), ambient | glass | color | view
#              (-ZTronHeaderBackground), marker (-ZTronSeamMarker 1: a cyan row at content y 320), refresh (-ZTronSeamRefresh 2.5:
#              a refresher whose action holds 2.5 s, with pull: the refresh hold and its end), band (-ZTronSeamScrollBand 0.5:
#              seam.scroll stops half way into the band), combo (band + -ZTronSeamWidthThenScroll 0.5, with width: a
#              scroll command 0.5 s into the width animation closes the open resize inside its transaction), together
#              (band + -ZTronSeamWidthWithScroll 1: the size change and the scroll in one withAnimation), height<digits> (with width:
#              -ZTronSeamAnimateHeight 0.<digits>, the scroll view's height animates top-pinned instead of its width; height04 = 0.4), hold (-ZTronSeamHold 1: a held refresh from launch, white probe indicator),
#              sticky (-ZTronSeamSticky 1: a white bar in a bottom-aligned overlay of the header), opengap | follow (D65,
#              -ZTronSeamPull openGap | followContent: where a .preserve pull's gap opens; analyze with --open-gap for opengap
#              pulls, see analyze.py); e.g. fixed-rest-preserve-rotate, aspect-half-preserve-width,
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
      capped|refit|uncapped|capped[0-9]*) extra+=(-ZTronHeaderOverflow "$x") ;;   # capped25 = .capped(fraction: 0.25) (D64)
      ambient|glass|color|view) extra+=(-ZTronHeaderBackground "$x") ;;
      opengap) extra+=(-ZTronSeamPull openGap) ;;          # D65: the .preserve pull opens the gap below the still header (the default)
      follow) extra+=(-ZTronSeamPull followContent) ;;     # D65: the .preserve header follows the content (D61), the gap above it
      marker) extra+=(-ZTronSeamMarker 1) ;;
      horizontal) extra+=(-ZTronSeamAxis horizontal) ;;   # a horizontal scroll view: the header is a banner (review d16)
      grow) extra+=(-ZTronSeamFitGrow 1) ;;   # with width + fit: seam.width animates the header's content 16:9 <-> 4:3 (review d16)
      height[0-9]*) extra+=(-ZTronSeamAnimateHeight "0.${x#height0}") ;;   # with width: seam.width animates the HEIGHT to 0.<digits> (height04 = 0.4, height025 = 0.25), top-pinned (M8b-s6)
      refresh) extra+=(-ZTronSeamRefresh 2.5) ;;
      hold) extra+=(-ZTronSeamHold 1) ;;       # a held refresh from 0.8 s (white 20 pt probe indicator; scripts/seam/probe.py) (M8b-s6)
      noheader) extra+=(-ZTronSeamNoHeader 1) ;;   # no scaling header (open item 19: the hold's gap leaves the screen in a rotation)
      htop|hbottom|hleading|htrailing) extra+=(-ZTronSeamHoldEdge "${x#h}") ;;   # with hold: the held refresher's edge (an end edge scrolls there first)
      hoverlay) extra+=(-ZTronSeamHoldOverlay 1) ;;   # with hold: overlay placement (the indicator floats over the content)
      sticky) extra+=(-ZTronSeamSticky 1) ;;   # a white 120 x 16 pt bar in an .overlay(alignment: .bottom) of the header (probe.py) (M8b-s6)
      vbottom) extra+=(-ZTronSeamBottomPinned 1) ;;   # with height<digits>: bottom-pinned, the TOP inset goes 62 -> 0 (M8b-s6 close)
      vboth) extra+=(-ZTronSeamBoth 1) ;;             # with height<digits>: the width animates to 60 % too
      vspring) extra+=(-ZTronSeamSpring 1) ;;         # seam.width animates with .spring(response: 0.55, dampingFraction: 0.5)
      vretarget) extra+=(-ZTronSeamRetarget 0.5) ;;   # seam.width toggles back 0.5 s into the change (additive retarget)
      vland) extra+=(-ZTronSeamLandscape 1) ;;        # with width: in landscape
      near[0-9]*) extra+=(-ZTronSeamRetarget 0.5 -ZTronSeamRetargetNear "${x#near}") ;;   # with height<digits>: 0.5 s in, retarget to the DRAWN height + <digits> pt (core check)
      kbfake) extra+=(-ZTronSeamFakeKeyboard 150) ;;  # with width: seam.width toggles a 150 pt bottom .safeAreaInset, easeInOut 1.2 s (core check; a bottom hold: insetgap.py)
      kbreal) extra+=(-ZTronSeamKeyboard 1) ;;        # with width / kbrotate: seam.width toggles the system keyboard (D64)
      slide) extra+=(-ZTronSeamCollapse slideBehind) ;;      # D68: collapse .slideBehind (parallax 0.5): the header slides behind the content
      slide0|slide1) extra+=(-ZTronSeamCollapse "slideBehind:${x#slide}") ;;   # D68: parallax 0 (still) / 1 (with the content)
      ruler) extra+=(-ZTronSeamRuler 1) ;;   # D68: white position marks in the header (its top is clipped at the scroll view's frame as it slides up)
      fade) extra+=(-ZTronSeamFade split) ;;     # D70: a white split fade (rest from 0.5, collapse from 0, no pull fade); read with the fade tracker, not analyze.py
      fade1) extra+=(-ZTronSeamFade single) ;;   # D70: .linear(to: white, from: 0.5) in every state
      fade2) extra+=(-ZTronSeamFade split2) ;;   # D70: the split with a black collapse state (two colours)
      longpull) extra+=(-ZTronSeamPullDrag 450) ;;   # D70: with pull, a 450 pt drag (the pull passes R / 2)
      info) extra+=(-ZTronSeamInfo 2) ;;              # diagnostics only (draws the state line over the lab): DEBUG event log
      band) extra+=(-ZTronSeamScrollBand 0.5) ;;
      combo) extra+=(-ZTronSeamScrollBand 0.5 -ZTronSeamWidthThenScroll 0.5) ;;
      together) extra+=(-ZTronSeamScrollBand 0.5 -ZTronSeamWidthWithScroll 1) ;;
      *) echo "unknown scenario extra '$x' in $sc" >&2 ;;
    esac
  done
  [ -n "${ZS_SEAM_INSET:-}" ] && extra+=(-ZTronSeamInset "$ZS_SEAM_INSET")
  # D65: an .openGap pull is measured against the pull, a rotation / resize during its hold against the hold's gap.
  analyze=""
  if [ "$behavior" = "preserve" ] && [[ "-$rest-" == *-opengap-* ]]; then
    case "$test" in pull) analyze="--open-gap pull" ;; rotate|width) [[ "-$rest-" == *-hold-* ]] && analyze="--open-gap hold" ;; esac
  fi
  echo "=== $sc"
  ZS_SEAM_ANALYZE_ARGS="$analyze" "$root/scripts/seam/measure.sh" "$udid" "$test" "$out/$sc" -- -ZTronHeaderSize "$size" -ZTronSeamStart "$start" \
    -ZTronHeaderBehavior "$behavior" "${extra[@]}" 2>&1 | grep -E '^\{|^segment|^openGap|Executed|TEST (SUCCEEDED|FAILED)|hung|warning: the test'
done
