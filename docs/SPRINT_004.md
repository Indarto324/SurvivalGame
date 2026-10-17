# Sprint 004 — internal Android debug APK

2026-10-17. Source branch: `kawanan-island`. No changes to `main`.

## Build result

Built and inspected a signed ARM64 debug APK with official Godot
`4.4.stable.official.4c311cbee`. Application: **Kawanan Island**;
package: `com.kawanangames.kawananisland`; version: `0.4.0-dev`, code `1`.
Landscape orientation and immersive mode are enabled. The manifest requests
**zero Android permissions**. Backup, expansion files and remote debugging are
disabled. This is an internal development build, not a Google Play release.

Cloud artifact directory: `/workspace/artifacts/kawanan-island/`.
APK: `kawanan-island-debug.apk` (39,987,918 bytes, approximately 38.1 MiB).
SHA-256: `5e8d1f69d6b66061f02c2d5c22ca79fe20e80f8beeabac39a94fa8e0091e8671`.
Sidecars contain package metadata, manifest, signature/alignment output and a
machine-readable validation report. `build.log`, `import.log`, `regressions.log`,
`toolchain-setup.log` and `exported-runtime.log` preserve verification evidence.

The GitHub Actions workflow `android-debug.yml` also builds on pushes to
`kawanan-island`, runs regressions and uploads `builds/android/` as artifact
`kawanan-island-debug-<commit SHA>` for seven days. Download it from the completed
workflow run's **Artifacts** section. CI execution is separate from the verified
cloud build; consult the run status before treating a CI artifact as validated.
Manual dispatch is additionally available once GitHub registers the workflow
on the repository's default branch; no default-branch change is required for
push-triggered builds. No GitHub Release or Play publication is configured.

## Toolchain and reproduction

- Temurin JDK **17.0.18+8**, downloaded from the official Adoptium release and
  verified against its published SHA-256.
- Android command-line tools **12.0**, verified against Google's repository
  checksum and pinned SHA-256; SDK platform **34**, build-tools **34.0.0**,
  platform-tools **37.0.1** in this environment. SDK Manager verifies SDK downloads.
- Official Godot **4.4 stable** editor and matching Android debug/release templates,
  checked against the publisher's SHA-512 manifest.
- Standard template export uses `apksigner` and `zipalign`; no Gradle, NDK or CMake
  installation is needed because this game contains no custom native plugins.

```bash
cd /workspace/SurvivalGame
bash scripts/android/setup.sh
bash /workspace/tools/survivalgame/run.sh --editor --import
export XDG_CACHE_HOME=/workspace/.cache
export XDG_DATA_HOME=/workspace/.local/share
export XDG_CONFIG_HOME=/workspace/.config
export GODOT_BIN=/workspace/tools/godot-4.4/Godot_v4.4-stable_linux.x86_64
bash tests/run.sh
bash scripts/android/build.sh
```

Default output: ignored `builds/android/kawanan-island-debug.apk`. Pass an absolute
APK filename to `build.sh` to change the destination. `setup.sh` uses `TOOLS_DIR`
to relocate its toolchain; CI sets its environment paths outside the checkout.
Python 3.11+ is required. The cloud Vulkan/Xvfb launcher comes from the published
development environment; CI installs equivalent system packages.

`ANDROID_USER_HOME` uses writable storage. Java uses a private truststore containing
the machine-provisioned HTTPS certificates; TLS verification remains enabled.
SDK licenses are accepted as part of installing the requested Android toolchain.
Godot generates its debug keystore outside Git at
`/workspace/.local/share/godot/keystores/debug.keystore`. No signing credentials,
keystores, APKs or other generated build outputs are committed or uploaded as keys.
Build logs redact signing arguments. Builds with a different generated debug key
cannot update an existing installation signed with the previous key.

## Rendering and preserved systems

Mobile Vulkan rendering is now the project default. Android 3D render scale is
0.75; the existing logical 1920×1080 responsive touch UI retains full resolution.
ETC2/ASTC texture imports are enabled and their metadata is committed alongside
existing desktop texture variants. No gameplay systems or source assets were
removed. Unused addon demo/test scenes and two obsolete editor-only preset dialogs
are excluded from export because they refer to absent demos or Godot 3 node types.
Godot and Proton Scatter license notices are explicitly included in the APK.

## Validation

- Godot 4.4 Vulkan/Mobile project import: passed.
- Sprint 001: **59 checks, zero failures**.
- Sprint 002: **46 checks, zero failures**.
- Sprint 003: **60 checks, zero failures**.
- Final export: completed without Godot script/export errors; signed and verified.
- APK validation: AAPT2 package/label/version/ABI; launcher and landscape manifest;
  zero permissions; debuggable flag; signature v2; ZIP alignment/CRC/duplicate-entry
  checks; ARM64 ELF; main scene and license notices; exclusion of test scripts,
  documentation, build scripts and signing files: passed.
- Exported Android resource tree loads its menu, full-density island and player
  using the matching **Linux runtime export template**, including touch mode.
  This checks exported resources outside the editor, not Android OS behavior.
- Shell scripts and Python syntax checked; workflow YAML parsed locally. Hosted CI
  has not been verified from this cloud environment.

## Installation and required device checks

Use a trusted internal tester's ARM64 device with Vulkan support, preferably
Android 9 or newer and a conventional 4 KiB page size. The stock template declares
minimum SDK 21 and target SDK 34; that install floor does not establish that the
Mobile renderer works on older Android versions. Vulkan needs Android 7+ and
suitable drivers. Neither GLES fallback nor 16 KiB-page devices are validated.
The pinned Godot 4.4 native libraries use 4 KiB ELF load alignment.

1. Download the APK directly, or extract it from the CI artifact ZIP.
2. For direct installation, temporarily allow installing unknown apps for the
   file manager/browser used to open the APK, then open the APK and install.
3. Alternatively, enable USB debugging on a trusted test workstation and run:
   `adb install -r kawanan-island-debug.apk`.
4. Launch from the app drawer, or run:
   `adb shell am start -n com.kawanangames.kawananisland/com.godot.game.GodotApp`.
5. On a signature mismatch, uninstall the older internal build before installing;
   uninstalling deletes its local app data. Do this only when that loss is intended.

Physical device acceptance checklist (all still **unperformed**):

- Cold launch, splash/menu and island loading time; missing materials/shaders,
  crashes and `adb logcat` errors; memory usage, frame pacing, heat and battery.
- Simultaneous joystick, camera drag, sprint, jump, interact and use-item touches;
  no camera movement from UI controls, stuck fingers or unintended mouse capture.
- Inventory transfer, hotbar/equipment selection, crafting and pause/settings;
  tree harvesting, pickup, item actions, animal AI and survival/energy updates.
- Landscape, tall/wide screens, notches and gesture navigation; Android Back,
  background/resume, interrupted touches, screen lock and audio interruptions.
- Repeated menu/game transitions and death/restart; multiple Android/GPU versions.

## Remaining limitations

No APK installation, emulator run or physical-device testing occurred. Android
performance, Vulkan driver compatibility, cutouts and lifecycle behavior remain
unverified. AAPT2 reports a dangling optional `themed_icon.xml` reference from the
stock Godot template; ordinary launcher and manifest inspection pass, but themed
launcher behavior needs a device check. Legacy `aapt dump badging` rejects the stock
Vulkan feature attributes encoded as strings; AAPT2 handles them, and legacy aapt
successfully dumps the complete manifest. The validator deliberately uses AAPT2
for badging. The exported Linux runtime probe can report two to four resources retained
at process shutdown; this is recorded separately from the passing regressions and
clean export. It has not been established as an Android runtime problem.

Source/course-derived code and several asset/audio provenance issues remain open
in `LICENSING_REVIEW.md`. Including engine/addon notices does not resolve those
rights. **Do not publish this build to Google Play or distribute it publicly.**
No God Mode, external character assets or unrelated gameplay changes were added.

## Modified files

- `.github/workflows/android-debug.yml`
- `.gitignore`
- `addons/proton_scatter/icons/loading/progress1.svg.import`
- `addons/proton_scatter/icons/loading/progress2.svg.import`
- `addons/proton_scatter/icons/loading/progress3.svg.import`
- `addons/proton_scatter/icons/loading/progress4.svg.import`
- `addons/proton_scatter/icons/loading/progress5.svg.import`
- `addons/proton_scatter/icons/loading/progress6.svg.import`
- `addons/proton_scatter/icons/loading/progress7.svg.import`
- `addons/proton_scatter/icons/loading/progress8.svg.import`
- `addons/proton_scatter/src/shapes/gizmos_plugin/icons/main_handle.svg.import`
- `addons/proton_scatter/src/shapes/gizmos_plugin/icons/secondary_handle.svg.import`
- `docs/SPRINT_004.md`
- `export_presets.cfg`
- `licenses/Godot-COPYRIGHT.txt`
- `licenses/Godot-LICENSE.txt`
- `meshes/meshes_TerrainTexture.png.import`
- `project.godot`
- `scripts/android/build.sh`
- `scripts/android/setup.sh`
- `scripts/android/validate_apk.py`
- `textures/circle32.png.import`
