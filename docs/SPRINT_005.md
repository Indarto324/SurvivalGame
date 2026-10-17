# Sprint 005 — Android survival interactions

Date: 2026-10-18 (Asia/Tokyo). Branch: `kawanan-island`; do not change `main`.
Build: **0.5.0-dev**, Android version code **2**, official Godot 4.4 stable.

## Root causes and evidence

The physical-device report establishes that the preceding APK installs, launches,
and supports movement/camera controls. The assistant has not physically tested
this new APK. Inspection and integration fixtures identified targeting and
placement problems rather than a broken Interact button dispatch:

1. The interaction system demanded an exact camera-center ray intersection with
   tiny item colliders. The follow camera sits four meters behind the player;
   its default pitch does not point precisely at ground-level sticks/stones.
   Sprint 003's pickup test placed its stick at chest height and set pitch to zero,
   so it missed this usability problem. The new test explicitly confirms that the
   original exact ray misses a ground fixture while touch targeting selects it.
2. Rigid pickup bodies can intercept the ray before their child pickup areas.
   Casting that collider directly to Interactable discarded the target.
3. The short forward placement ray misses flat ground from equipment/hand height
   at the default follow-camera pitch. Previously the player needed a substantial
   downward camera tilt before any building preview became valid.
4. Target feedback still displayed a desktop `E` instruction on touch devices and
   did not identify which small ground object was selected.

The touch action queue itself was verified through real InputEventScreenTouch
press/release events. No evidence established a separate Android-only OS input
failure. Physical-device confirmation of this fix still requires retesting.

## Fixes

- Keep exact camera aiming as first choice. In touch mode only, fall back to a
  bounded nearby query (32 collider results) within the existing **2.4 m** reach
  measured from the player interaction origin. Select visible targets within a
  60-degree forward camera cone, favoring nearby centered targets. Ray-test from
  the player to the candidate to prevent interactions through solid obstructions.
  Reject targets behind the player, outside the viewport/reach, or being deleted.
- Resolve a rigid pickup body's `Pickuppable` child, including in obstruction
  checks. Preserve the original pickup callback and inventory capacity handling.
- Draw a cyan ring at the selected object's screen position and highlight the
  Interact button. Display a larger outlined **Tap Interact** prompt with the
  object's existing description. Clear feedback on menu entry or target loss.
- When the original placement ray misses, touch mode casts down at a point
  2.5 meters ahead along camera yaw. Preserve preview materials, overlap rules,
  inventory consumption, spawning, navigation rebaking and existing item-use
  callbacks. An additional sight check prevents fallback placement through walls.
- Preserve desktop controls, player movement, sprint, jump, camera, original
  crafting recipes/tool gates, inventory validation and equipment animations.
  No character animations, God Mode, new gameplay systems or external assets added.

## Integration coverage

`tests/sprint_005.gd` extends the established touch helpers and loads the production
menu, island, player, inventory, crafting UI, item scenes and tree. It uses an
isolated flat arena with normal capsule/ground heights and the shipped default
camera pitch; it does not reduce island foliage or replace gameplay managers.

The 48 checks cover:

- The original exact-ray miss, ground sticks/stones/fruits/plants, selected-target
  feedback, raw Interact touch pickup exactly once, and visible inventory contents.
- Simultaneous joystick/look ownership retained during Interact.
- Touch crafting rope from collected plants, then axe from collected stick/stone
  and rope. Touch transfer to a real hotbar slot, equipment selection and three
  Use touches harvesting a real tree, consuming energy and spawning logs.
- Targeting and collecting a harvested rigid-body log.
- Wall obstruction, behind-player targets and out-of-reach rejection.
- Crafting campfire and tent/shelter, equipment transfer/selection, valid placement
  at the default camera pitch, consumption of one equipped construction item and
  navigation rebakes. Invalid wall-blocked Use preserves inventory and spawns none.
- Campfire's tinderbox gate and safe scene unloading.

Construction recipe resource inventories/tool presence are seeded test fixtures;
the tests still use the real crafting buttons and original resource costs/gates.
The axe chain uses resources collected through actual simulated touch events.
Rendering can batch physics ticks before node processing, so the pickup test waits
for real target selection instead of assuming a process_frame signal means the
player's process callback has already executed.

## Validation and artifacts

Run all shipped gameplay suites (001, 002, 003, 005):

```bash
cd /workspace/SurvivalGame
export XDG_CACHE_HOME=/workspace/.cache
export XDG_DATA_HOME=/workspace/.local/share
export XDG_CONFIG_HOME=/workspace/.config
export GODOT_BIN=/workspace/tools/godot-4.4/Godot_v4.4-stable_linux.x86_64
bash tests/run.sh
bash scripts/android/build.sh
```

Expected checks: **59 + 46 + 60 + 48 = 213**, zero failures. Sprint 004 has no
separate gameplay test scene: its Android export, manifest/signature/ZIP/ABI/
permission/license validation is performed by the existing build/validation
scripts. The validator now expects version `0.5.0-dev`, code `2`.

A second Sprint 005 run with Vulkan/Mobile rendering at 1280×720 passed all 48
checks; its target-feedback screenshot was visually inspected. This is Linux
software Vulkan with simulated touch, not an Android emulator or physical device.
The screenshot uses the isolated test arena outside the island; its lighting and
terrain do not represent normal island gameplay.

Cloud build/evidence directory: `/workspace/artifacts/kawanan-sprint005/`.
APK: `kawanan-island-debug.apk`. Logs include `import.log`, `regressions.log`,
`visual-integration.log`, `build.log`, metadata/signature/alignment sidecars and
`target-feedback.png`. The normal ignored build destination remains
`builds/android/kawanan-island-debug.apk`. No APK or signing key is committed.

GitHub Actions now includes Sprint 005 in its regression step and uploads the
validated internal APK as `kawanan-island-debug-<commit SHA>` for seven days.
Use the pushed commit's run status to distinguish hosted CI results from local
validation. Source and asset licensing restrictions from Sprint 004 still apply;
do not publish to Google Play or distribute publicly.

## Physical-device retest required

Install the new internal APK (see Sprint 004 installation instructions). A newly
generated CI debug key may differ from the previous build: if Android reports a
signature mismatch, uninstalling the older build is required and deletes app data.
Only do so when that data loss is intended.

1. Walk within roughly two meters of a visible ground stick/stone/fruit. Confirm
   the cyan target ring, highlighted Interact button and named Tap Interact prompt.
2. Press Interact while also holding joystick/camera touches. Confirm the item
   disappears once and appears in Bag. Verify walls and distant items block pickup.
3. Collect two plants, craft rope, then craft an axe with one stick and one stone.
   Tap axe inventory slot, tap an empty equipment slot, close Bag and select it.
4. Stand within the existing axe range (1.5 m), face a tree and tap Use three times.
   Verify tree/stump/log drops, energy use, and log pickup.
5. With required resources/tool available, craft campfire and tent. Transfer to
   equipment, select it and check the colored preview on open ground. Tap Use to
   build once. Verify blocked locations preserve the item.
6. Repeat on slopes, in foliage, with multiple nearby objects, varied aspect ratios
   and display cutouts. Test inventory capacity, menu/pause/resume, multitouch and
   device performance. Confirm the previously working movement/camera controls.

Known unchanged limits: licensing gaps, stock template themed-icon warning,
4 KiB native library alignment, unvalidated 16 KiB-page devices and driver-specific
Vulkan compatibility. This sprint does not claim new physical-device results.

## Modified files

- `.github/workflows/android-debug.yml`
- `actors/player/interaction_ray_cast.gd`
- `bulletins/interaction_prompt/interaction_prompt.gd`
- `docs/SPRINT_005.md`
- `export_presets.cfg`
- `items/equippables/equippable_constructable.gd`
- `project.godot`
- `scripts/android/validate_apk.py`
- `tests/run.sh`
- `tests/sprint_005.gd`
- `tests/sprint_005.gd.uid`
- `tests/sprint_005.tscn`
- `ui/mobile/mobile_input.gd`
