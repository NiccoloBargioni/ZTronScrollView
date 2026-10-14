#!/bin/bash
cd "$(dirname "$0")/../Packages/ZTronScrollPhysics" || exit 1
exec ../../scripts/run-filtered.sh swift test "$@"
