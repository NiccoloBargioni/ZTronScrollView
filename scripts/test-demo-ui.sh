#!/bin/bash
# usage: scripts/test-demo-ui.sh <destination> [--forced] [--uikit] [--native] [extra xcodebuild args]
# --forced: the UI tests launch the demo with -ZTronForceAllFallbacks (ZS_DEMO_FORCED=1 read by the test bundle).
# --uikit: ... and with -ZTronForceUIKitObserver, the iOS 15-16 UIKit touch observer path (D31; ZS_DEMO_UIKIT=1,
#          read by PanUITests / ZoomUITests; UIKitObserverUITests always force it).
# --native: the baseline lane of UIKitControlsUITests (ZS_NATIVE=1): the same screen on SwiftUI's own ScrollView, no ZTron code
#          under the controls (a failure there is a test or OS problem, not the library's).
# --picker: spike PICKER-s1: builds with ZTRON_PICKER_DECLINE (the picker decline, open items 37-39) and sets ZS_PICKER=1, so
#          UIKitControlsUITests asserts those required fixes instead of expecting them to fail. Use its own derived data.
cd "$(dirname "$0")/../Demo" || exit 1
dest="${1:?destination required}"; shift
forced=0; uikit=0; native=0; picker=0
while [ "$1" = "--forced" ] || [ "$1" = "--uikit" ] || [ "$1" = "--native" ] || [ "$1" = "--picker" ]; do
  case "$1" in --forced) forced=1;; --uikit) uikit=1;; --native) native=1;; --picker) picker=1;; esac
  shift
done
if [ "$picker" = 1 ]; then set -- "$@" 'OTHER_SWIFT_FLAGS=$(inherited) -DZTRON_PICKER_DECLINE'; fi
ZS_PICKER=$picker TEST_RUNNER_ZS_PICKER=$picker ZS_NATIVE=$native TEST_RUNNER_ZS_NATIVE=$native ZS_DEMO_UIKIT=$uikit TEST_RUNNER_ZS_DEMO_UIKIT=$uikit ZS_DEMO_FORCED=$forced TEST_RUNNER_ZS_DEMO_FORCED=$forced exec ../scripts/run-filtered.sh xcodebuild test \
  -project ZTronScrollViewDemo.xcodeproj -scheme ZTronScrollViewDemo -destination "$dest" "$@"
