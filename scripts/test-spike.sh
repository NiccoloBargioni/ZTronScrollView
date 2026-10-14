#!/bin/bash
cd "$(dirname "$0")/../Packages/ScrollArbitration/Spike" || exit 1
: "${ZS_DEST:?set ZS_DEST in .claude/settings.json}"
[ -n "$SPIKE_DEVELOPER_DIR" ] && export DEVELOPER_DIR="$SPIKE_DEVELOPER_DIR"
exec ../../../scripts/run-filtered.sh xcodebuild test \
  -project ArbitrationSpike.xcodeproj -scheme ArbitrationSpike \
  -destination "${SPIKE_DEST:-$ZS_DEST}" "$@"
