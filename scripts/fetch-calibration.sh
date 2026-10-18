#!/bin/bash
# usage: scripts/fetch-calibration.sh <simulator udid> <out dir>
# Copies the calibration trajectories (Documents/cal/*.json written by the demo's `-ZTronScreen calibrate`) to <out dir>.
udid="${1:?udid required}"; out="${2:?out dir required}"
container="$(xcrun simctl get_app_container "$udid" dev.ztron.ZTronScrollViewDemo data)" || exit 1
mkdir -p "$out"
cp "$container"/Documents/cal/*.json "$out"/ && ls "$out"
