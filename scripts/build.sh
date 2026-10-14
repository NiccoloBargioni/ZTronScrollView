#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
exec scripts/run-filtered.sh xcodebuild build -quiet \
  -scheme "${ZS_SCHEME:-ZTronScrollView}" -destination "generic/platform=iOS Simulator" "$@"
