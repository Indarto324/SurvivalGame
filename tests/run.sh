#!/usr/bin/env bash
set -euo pipefail
GODOT_BIN=${GODOT_BIN:-godot}
# Fail before loading a scene when a runner dependency is missing.
for tool in rg timeout mktemp cat dirname rm "$GODOT_BIN"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: Missing required regression command: $tool (install ripgrep/coreutils and set GODOT_BIN to Godot 4.4)." >&2
    exit 127
  fi
done
cd "$(dirname "$0")/.."
case "$("$GODOT_BIN" --version)" in
  4.4.*) ;;
  *) echo 'Gameplay regressions require Godot 4.4.' >&2; exit 1 ;;
esac
log_file=$(mktemp)
trap 'rm -f "$log_file"' EXIT
# Run all shipped regression scenes and reject errors even on exit zero.
for sprint in 001 002 003 005 006 007 008; do
  args=()
  if [[ "$sprint" == 007 || "$sprint" == 008 ]]; then args=(-- --internal-dev); fi
  set +e
  timeout --kill-after=10 180 "$GODOT_BIN" --headless --audio-driver Dummy --path "$PWD" "res://tests/sprint_${sprint}.tscn" "${args[@]}" >"$log_file" 2>&1
  result=$?
  set -e
  cat "$log_file"
  if (( result != 0 )); then exit "$result"; fi
  if rg -q 'SCRIPT ERROR:|^ERROR:|^FAIL:' "$log_file"; then exit 1; fi
  rg -q "^SPRINT ${sprint}: [1-9][0-9]* checks, 0 failures$" "$log_file"
done

# Gate checks also reject engine errors even if the script exits zero.
GODOT_RELEASE_BIN=${GODOT_RELEASE_BIN:-$(dirname "$GODOT_BIN")/linux_release.x86_64}
if [[ ! -x "$GODOT_RELEASE_BIN" ]]; then
  echo "ERROR: Missing Godot 4.4 release template: $GODOT_RELEASE_BIN (run scripts/android/setup.sh)." >&2
  exit 127
fi
for gate_engine in "$GODOT_BIN" "$GODOT_RELEASE_BIN"; do
  args=()
  if [[ "$gate_engine" == "$GODOT_RELEASE_BIN" ]]; then args=(-- --internal-dev); fi
  set +e
  timeout --kill-after=10 30 "$gate_engine" --headless --audio-driver Dummy --path "$PWD" res://tests/developer_gate.tscn "${args[@]}" >"$log_file" 2>&1
  result=$?
  set -e
  cat "$log_file"
  if (( result != 0 )); then exit "$result"; fi
  if rg -q 'SCRIPT ERROR:|^ERROR:|FAIL' "$log_file"; then exit 1; fi
  rg -q '^DEVELOPER GATE: PASS' "$log_file"
done
