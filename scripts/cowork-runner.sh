#!/bin/bash
# scripts/cowork-runner.sh — executes command files queued by a Cowork (cloud) session.
# Start it on the Mac, in Terminal:   bash scripts/cowork-runner.sh      (Ctrl-C to stop)
# Protocol (dir .build/cowork/queue, gitignored):
#   <name>.cmd      a bash script dropped by the session (written as .cmd.tmp, then renamed)
#   <name>.started  epoch when the runner picked it up (a .cmd is run once)
#   <name>.log      stdout + stderr of `bash <name>.cmd` run from the repo root
#   <name>.done     exit code, written when the command finished
# The session (Linux VM, no Xcode) only sees this folder; xcodebuild/simulators run here, on the Mac.
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
Q="$ROOT/.build/cowork/queue"
mkdir -p "$Q"
export LANG=en_US.UTF-8
echo "[cowork-runner] root=$ROOT"
echo "[cowork-runner] queue=$Q  (Ctrl-C to stop)"
date +%s > "$Q/.runner-alive"
while :; do
  date +%s > "$Q/.runner-alive"
  for f in "$Q"/*.cmd; do
    [ -e "$f" ] || continue
    base="${f%.cmd}"
    [ -e "$base.started" ] && continue
    date +%s > "$base.started"
    echo "[cowork-runner] $(date +%H:%M:%S) start $(basename "$base")"
    ( cd "$ROOT" && bash "$f" ) > "$base.log" 2>&1
    rc=$?
    echo "$rc" > "$base.done"
    echo "[cowork-runner] $(date +%H:%M:%S) done  $(basename "$base") exit=$rc"
  done
  sleep 2
done
