#!/bin/bash
cd "$(dirname "$0")/../Packages/ScrollArbitration" || exit 1
exec ../../scripts/run-filtered.sh swift test "$@"
