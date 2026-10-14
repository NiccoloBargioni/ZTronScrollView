#!/bin/bash
# usage: scripts/test.sh [-only-testing:Target/Suite ...]
cd "$(dirname "$0")/.." || exit 1
: "${ZS_DEST:?set ZS_DEST in .claude/settings.json}"
exec scripts/run-filtered.sh xcodebuild test \
  -scheme "${ZS_SCHEME:-ZTronScrollView}" -destination "$ZS_DEST" "$@"
