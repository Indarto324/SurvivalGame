#!/usr/bin/env bash
# Linux x86_64 tooling. Downloads are verified before installation.
set -euo pipefail
TOOLS_DIR=${TOOLS_DIR:-/workspace/tools}
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-/workspace/.cache}
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-/workspace/.config}
export XDG_DATA_HOME=${XDG_DATA_HOME:-/workspace/.local/share}
export ANDROID_HOME="$TOOLS_DIR/android-sdk"
export ANDROID_USER_HOME=${ANDROID_USER_HOME:-/workspace/.android}
export JAVA_HOME="$TOOLS_DIR/jdk-17.0.18+8"
cache="$TOOLS_DIR/android-downloads"
mkdir -p "$ANDROID_USER_HOME" "$cache" "$TOOLS_DIR/godot-4.4" "$ANDROID_HOME/cmdline-tools"
fetch() { test -f "$2" || curl -fLsS --retry 2 "$1" -o "$2"; }
jdk=OpenJDK17U-jdk_x64_linux_hotspot_17.0.18_8.tar.gz
fetch "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.18%2B8/$jdk" "$cache/$jdk"
echo "0c94cbb54325c40dcf026143eb621562017db5525727f2d9131a11250f72c450  $cache/$jdk" | sha256sum -c -
if ! test -x "$JAVA_HOME/bin/javac"; then tar -xzf "$cache/$jdk" -C "$TOOLS_DIR"; fi
fetch https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip "$cache/commandline.zip"
echo "2d2d50857e4eb553af5a6dc3ad507a17adf43d115264b1afc116f95c92e5e258  $cache/commandline.zip" | sha256sum -c -
if ! test -d "$ANDROID_HOME/cmdline-tools/12.0"; then
  unzip -q "$cache/commandline.zip" -d "$ANDROID_HOME/cmdline-tools/staging"
  mv "$ANDROID_HOME/cmdline-tools/staging/cmdline-tools" "$ANDROID_HOME/cmdline-tools/12.0"
  rmdir "$ANDROID_HOME/cmdline-tools/staging"
fi
# Preserve TLS verification behind the cloud HTTPS proxy. Import only the
# machine's provisioned CA certificates into a private copy of the JDK truststore.
cp "$JAVA_HOME/lib/security/cacerts" "$cache/cacerts"
for certificate in /usr/local/share/ca-certificates/*.crt; do
  test -f "$certificate" || continue
  "$JAVA_HOME/bin/keytool" -importcert -noprompt -trustcacerts \
    -keystore "$cache/cacerts" -storepass changeit \
    -alias "cloud-$(basename "$certificate")" -file "$certificate"
done
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Djavax.net.ssl.trustStore=$cache/cacerts"
sdkmanager="$ANDROID_HOME/cmdline-tools/12.0/bin/sdkmanager"
# Installing the requested SDK entails accepting the Android SDK licenses.
# Ignore yes's SIGPIPE, but preserve sdkmanager's exit status.
set +o pipefail
yes | "$sdkmanager" --sdk_root="$ANDROID_HOME" --licenses
license_result=${PIPESTATUS[1]}
set -o pipefail
test "$license_result" -eq 0
"$sdkmanager" --sdk_root="$ANDROID_HOME" 'platform-tools' 'build-tools;34.0.0' 'platforms;android-34'
base=https://github.com/godotengine/godot/releases/download/4.4-stable
for name in SHA512-SUMS.txt Godot_v4.4-stable_linux.x86_64.zip Godot_v4.4-stable_export_templates.tpz; do
  fetch "$base/$name" "$TOOLS_DIR/godot-4.4/$name"
done
export TOOLS_DIR
python3 - <<'PY'
import hashlib, os, pathlib, zipfile
p = pathlib.Path(os.environ['TOOLS_DIR']) / 'godot-4.4'
checks = {l.split()[-1].lstrip('*'): l.split()[0] for l in (p/'SHA512-SUMS.txt').read_text().splitlines()}
for name in ['Godot_v4.4-stable_linux.x86_64.zip', 'Godot_v4.4-stable_export_templates.tpz']:
    with (p/name).open('rb') as f:
        assert hashlib.file_digest(f, 'sha512').hexdigest() == checks[name], name
    with zipfile.ZipFile(p/name) as z:
        if name.endswith('.zip'):
            binary = p/'Godot_v4.4-stable_linux.x86_64'
            if not binary.exists():
                binary.write_bytes(z.read(binary.name))
                binary.chmod(0o755)
        else:
            release = p/'linux_release.x86_64'
            release.write_bytes(z.read('templates/linux_release.x86_64'))
            release.chmod(0o755)
            out = pathlib.Path(os.environ['XDG_DATA_HOME'])/'godot/export_templates/4.4.stable'
            out.mkdir(parents=True, exist_ok=True)
            for resource in ['android_debug.apk', 'android_release.apk', 'version.txt']:
                (out/resource).write_bytes(z.read('templates/'+resource))
PY
"$JAVA_HOME/bin/javac" -version
"$ANDROID_HOME/build-tools/34.0.0/apksigner" version
"$TOOLS_DIR/godot-4.4/Godot_v4.4-stable_linux.x86_64" --version
