#!/bin/bash
input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
case "$cmd" in
  *run-filtered*|*'|'*|*';'*|*'&'*|*'$('*|*'`'*) echo '{}'; exit 0 ;;
esac
if [[ "$cmd" =~ ^(xcodebuild|swift\ (build|test))([[:space:]]|$) ]]; then
  wrapped="\"${CLAUDE_PROJECT_DIR:-$PWD}/scripts/run-filtered.sh\" $cmd"
  jq --arg c "$wrapped" '{hookSpecificOutput: {hookEventName: "PreToolUse",
      permissionDecision: "allow", updatedInput: (.tool_input + {command: $c})}}' <<<"$input"
else
  echo '{}'
fi
