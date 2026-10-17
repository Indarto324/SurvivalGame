# Sprint 007 — internal developer tools (0.7.0-dev)

Internal development build only. Branch: `kawanan-island`. No external assets.

## Access and defaults

The Android Debug export explicitly includes `internal_dev`. Runtime access also
requires `OS.is_debug_build()`: release executables cannot enable the panel or
cheat effects, even with `--internal-dev`. Ordinary editor runs are gated off;
editor testing requires `-- --internal-dev`. Use **DEV** on Android or **F8** on
desktop. Opening the panel freezes the player and releases active touch owners.
Close resumes normal controls. Tools cannot open over inventory or pause menus.

Every island session starts with invincibility, unlimited needs and flight OFF,
and speed 1x. The persistent INTERNAL DEV status lists active modifiers. Toggles
also show ON/OFF. Leaving the island clears modifiers and the player reference.
The public release build must not use this internal debug APK or its preset.
A release engine remains gated even if a preset accidentally retains the feature.

## Behavior

- Invincibility rejects negative health changes; healing still works.
- Unlimited needs replenishes energy and prevents energy depletion/exhaustion
  damage. Existing survival meters are health and energy; no hunger or thirst
  systems were added. Health damage is controlled separately by invincibility.
- Previous/Next selects an existing ItemConfig key. Give 1/5/10 inserts through
  InventoryManager, limited to free slots. It never replaces occupied slots or
  writes directly into equipment. Use the existing bag/hotbar interface to equip.
  Granted resources persist after cheats are disabled; they are ordinary items.
- Speed adjusts 0.5x–3x without changing the exported movement constants. Reset
  restores 1x. Analog input, sprinting and camera-relative facing remain intact.
- Flight uses the existing colliding CharacterBody3D and move_and_slide. Hold
  Up/Down with joystick and camera touches, or desktop Space/Control. Gravity,
  collision masks, capsule and floor settings are never rewritten. Releasing
  fingers or losing application focus clears held input. Equipment aim continues
  to follow the camera/character and action callbacks remain unchanged.
- Disabling flight returns to the last grounded checkpoint, checking the capsule
  volume and trying small upward offsets if something has occupied the point.
  Reset to island spawn is a separate recovery option for horizontal traps.
  Recovery clears velocity. A completely obstructed destination reports failure;
  normal gravity/collision still operate when flight is disabled. No noclip or
  world editing is included. The game currently has no fall-damage mechanic.
- Disable ALL removes modifiers and touch holds. Animations, damage callbacks,
  collection, crafting costs and weapon hit timing are not driven by this UI.

## Validation

Godot 4.4.stable.official.4c311cbee, Mobile renderer, JDK 17, Android SDK 34 / build
tools 34.0.0 and matching verified Godot export templates.

Run `GODOT_BIN=/path/to/Godot_v4.4-stable_linux.x86_64 bash tests/run.sh` after a
Vulkan editor import. `scripts/android/setup.sh` also extracts the verified Linux
release executable used by the gate test. Override `GODOT_RELEASE_BIN` if needed.

Existing checks: Sprint 001 (59), 002 (46), 003 (60), 005 (48), 006 (47): **260**.
Sprint 007 adds **47** checks covering defaults, health/energy reset, safe grants,
speed limits/actual movement, mobile flight/ceiling collision/multitouch, recovery,
menu controls, input isolation, jumping/landing after disabling, and stage exit.
Final result: **307 gameplay checks passed, zero failures**, plus both gate runs.
The graphical Mobile-renderer run passed all 47 Sprint 007 checks.
Two additional gate runs check an ordinary editor and an actual release binary
with the opt-in argument. The actual exported APK resource pack was also loaded
using Linux debug and release templates: internal_dev was present in both,
but only debug enabled the tools. This is desktop pack validation, not Android
execution. Engine errors, failing assertions and timeouts fail CI.

A graphical Mobile-renderer run and `developer-panel.png` provide desktop visual
validation. They are not Android device testing or a mobile performance benchmark.

Build: `bash scripts/android/build.sh /path/to/kawanan-island-debug.apk`.
Validation checks APK ZIP/CRC/alignment, ARM64 ELF, package ID, version 0.7.0-dev
(code 4), landscape, debuggable flag, zero permissions and signature v2.

Local artifacts: `/workspace/artifacts/kawanan-sprint007/` (APK, validation JSON,
package/signature/alignment reports, import/build/regression/visual logs and PNG).
GitHub Actions uploads `kawanan-island-debug-<commit SHA>` on the branch, retained
for seven days. Generated APKs and signing keys stay out of Git.

## Physical-device follow-up and limitations

No new APK was installed on a physical Android device in this task. Install with
`adb install -r kawanan-island-debug.apk`. A different debug signing key requires
uninstalling the previous package first, which clears its data.

Verify three-finger movement/look/vertical flight, cutouts and narrow landscapes,
application background/resume, panel slider/buttons, inventory-full feedback,
resource-to-hotbar equipment, axe/crafting/building with cheats both on and off,
blocked recovery points, flight near cliffs/water/ceilings, and session restart.
The recovery algorithm checks the player capsule rather than providing navigation
or guaranteeing safety after arbitrary world obstruction. It does not save cheats.
Source/course and bundled asset licensing remains unresolved from earlier sprints;
do not publish this internal build to Google Play.

## Changed files

- `ui/developer/developer_tools.gd` (+ Godot UID): gated controller/panel, modifiers,
  inventory-safe grants, flight and recovery.
- `actors/player/player.gd`: session attachment, speed and flight hooks.
- `game/managers/player_stats_manager.gd`: guarded health/energy hooks.
- `ui/mobile/mobile_input.gd`: internal DEV and Up/Down hit regions/held input.
- `project.godot`, `export_presets.cfg`: autoload, version, internal debug feature.
- `tests/sprint_007.gd` (+ UID), `tests/sprint_007.tscn`: gameplay integration tests.
- `tests/developer_gate.gd` (+ UID), `tests/developer_gate.tscn`: fail-closed tests.
- `tests/run.sh`, `.github/workflows/android-debug.yml`: run all suites and gates.
- `scripts/android/setup.sh`: verified release-engine extraction for gate tests.
- `scripts/android/validate_apk.py`: expected development version/code.
- `docs/SPRINT_007.md`: this report.
