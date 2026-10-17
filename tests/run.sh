#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN=${GODOT_BIN:-godot}
case "$("$GODOT_BIN" --version)" in
  4.4.*) ;;
  *) echo 'Gameplay regressions require Godot 4.4.' >&2; exit 1 ;;
esac
log_file=$(mktemp)
trap 'rm -f "$log_file"' EXIT
# Run both shipped regression scenes and reject errors even on exit zero.
for sprint in 001 002; do
  set +e
  timeout --kill-after=10 180 "$GODOT_BIN" --headless --audio-driver Dummy --path "$PWD" "res://tests/sprint_${sprint}.tscn" >"$log_file" 2>&1
  result=$?
  set -e
  cat "$log_file"
  if (( result != 0 )); then exit "$result"; fi
  if rg -q 'SCRIPT ERROR:|^ERROR:|^FAIL:' "$log_file"; then exit 1; fi
  rg -q "^SPRINT ${sprint}: [1-9][0-9]* checks, 0 failures$" "$log_file"
done
