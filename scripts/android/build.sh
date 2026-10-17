#!/usr/bin/env bash
# Import using a graphical Vulkan display before invoking this script.
set -euo pipefail
cd "$(dirname "$0")/../.."
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-/workspace/.config}
export XDG_DATA_HOME=${XDG_DATA_HOME:-/workspace/.local/share}
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-/workspace/.cache}
export ANDROID_USER_HOME=${ANDROID_USER_HOME:-/workspace/.android}
export JAVA_HOME=${JAVA_HOME:-/workspace/tools/jdk-17.0.18+8}
export ANDROID_HOME=${ANDROID_HOME:-/workspace/tools/android-sdk}
GODOT_BIN=${GODOT_BIN:-/workspace/tools/godot-4.4/Godot_v4.4-stable_linux.x86_64}
case "$("$GODOT_BIN" --version)" in
  4.4.stable.official.4c311cbee) ;;
  *) echo 'This build requires official Godot 4.4 stable.' >&2; exit 1 ;;
esac
# Configure only tool locations. Godot keeps its generated debug key in XDG data,
# outside the checkout. No signing credentials are written to the preset.
python3 - <<'PY'
import json, os, pathlib, re
p = pathlib.Path(os.environ['XDG_CONFIG_HOME'])/'godot/editor_settings-4.4.tres'
p.parent.mkdir(parents=True, exist_ok=True)
s = p.read_text() if p.exists() else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
for key, value in {'export/android/java_sdk_path': os.environ['JAVA_HOME'], 'export/android/android_sdk_path': os.environ['ANDROID_HOME']}.items():
    line = key+' = '+json.dumps(value)
    pattern = r'^'+re.escape(key)+r' = .*'
    s = re.sub(pattern, lambda m: line, s, flags=re.M) if re.search(pattern,s,re.M) else s+'\n'+line+'\n'
key = 'export/android/shutdown_adb_on_exit'
s = re.sub(r'^'+re.escape(key)+r' = .*', key+' = false', s, flags=re.M) if re.search(r'^'+re.escape(key)+r' = ', s, re.M) else s+'\n'+key+' = false\n'
p.write_text(s)
PY
output=${1:-$PWD/builds/android/kawanan-island-debug.apk}
mkdir -p "$(dirname "$output")"
log_file=$(mktemp)
trap 'rm -f "$log_file"' EXIT
"$GODOT_BIN" --headless --audio-driver Dummy --path "$PWD" --export-debug 'Android Debug' "$output" 2>&1 | tee "$log_file"
if rg -q 'SCRIPT ERROR:|^ERROR:' "$log_file"; then exit 1; fi
python3 scripts/android/validate_apk.py "$output"
