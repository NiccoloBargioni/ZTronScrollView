#!/bin/bash
# usage: scripts/test-demo-ui.sh <destination> [--forced] [extra xcodebuild args]
# --forced: the UI tests launch the demo with -ZTronForceAllFallbacks (ZS_DEMO_FORCED=1 read by the test bundle).
cd "$(dirname "$0")/../Demo" || exit 1
dest="${1:?destination required}"; shift
forced=0
if [ "$1" = "--forced" ]; then forced=1; shift; fi
ZS_DEMO_FORCED=$forced TEST_RUNNER_ZS_DEMO_FORCED=$forced exec ../scripts/run-filtered.sh xcodebuild test \
  -project ZTronScrollViewDemo.xcodeproj -scheme ZTronScrollViewDemo -destination "$dest" "$@"
