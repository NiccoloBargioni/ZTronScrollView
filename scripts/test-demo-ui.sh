#!/bin/bash
# usage: scripts/test-demo-ui.sh <destination> [--forced] [--uikit] [extra xcodebuild args]
# --forced: the UI tests launch the demo with -ZTronForceAllFallbacks (ZS_DEMO_FORCED=1 read by the test bundle).
# --uikit: ... and with -ZTronForceUIKitObserver, the iOS 15-16 UIKit touch observer path (D31; ZS_DEMO_UIKIT=1,
#          read by PanUITests / ZoomUITests; UIKitObserverUITests always force it).
cd "$(dirname "$0")/../Demo" || exit 1
dest="${1:?destination required}"; shift
forced=0; uikit=0
while [ "$1" = "--forced" ] || [ "$1" = "--uikit" ]; do
  if [ "$1" = "--forced" ]; then forced=1; else uikit=1; fi
  shift
done
ZS_DEMO_UIKIT=$uikit TEST_RUNNER_ZS_DEMO_UIKIT=$uikit ZS_DEMO_FORCED=$forced TEST_RUNNER_ZS_DEMO_FORCED=$forced exec ../scripts/run-filtered.sh xcodebuild test \
  -project ZTronScrollViewDemo.xcodeproj -scheme ZTronScrollViewDemo -destination "$dest" "$@"
