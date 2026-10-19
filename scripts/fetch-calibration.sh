#!/bin/bash
# usage: scripts/fetch-calibration.sh <simulator udid> <out dir> [bundle id]
# Copies the calibration trajectories (Documents/cal/*.json written by the demo's `-ZTronScreen calibrate`, or by the
# spike's `-zoomCal` with bundle id dev.ztron.ArbitrationSpike) to <out dir>.
udid="${1:?udid required}"; out="${2:?out dir required}"; bundle="${3:-dev.ztron.ZTronScrollViewDemo}"
container="$(xcrun simctl get_app_container "$udid" "$bundle" data)" || exit 1
mkdir -p "$out"
cp "$container"/Documents/cal/*.json "$out"/ && ls "$out"
