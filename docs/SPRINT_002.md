# Sprint 002 — third-person camera and character

Work is limited to `kawanan-island`. The first-person gameplay rig is replaced; the menu, island and credits remain the same game stages. No Android controls/export, God Mode, external character assets or changes to animal AI behavior are introduced.

## Player rig

`Player` remains a `CharacterBody3D` with the original capsule, movement speeds, jump, gravity, energy consumption and managers. Its independent `CameraRig` orbits a shoulder-height pivot. `SpringArm3D` sweeps a sphere against terrain and physical props, excluding the player collider, and retracts the single `FollowCamera` before obstructions. Mouse yaw/pitch and follow-distance changes use exponential smoothing in the physics step. The requested follow distance is 4 m by default, clamped to 1.5–8 m. Pitch is limited to −60° through +35°.

Movement uses camera yaw projected onto the ground, including when a level rotates the player spawn. `CharacterVisuals` turns smoothly toward movement, while orbiting alone leaves the body facing unchanged. Item use turns the character toward camera aim. Construction previews track camera aim continuously so clicking does not unexpectedly relocate a preview just because the camera was orbited.

The visible placeholder consists only of seven original Godot primitive meshes (box torso/arms/legs, low-resolution sphere head and a simple face marker), with flat materials authored in `player.tscn`. It is a static prototype character, without a skeleton, gait or hand-grip animation. It borrows no character design, models, textures or animations from The Sims or Castaway. Existing game assets and their unresolved licensing status are unchanged; see `LICENSING_REVIEW.md`.

## Interaction and equipment

A camera-center physics query chooses an aim point. The existing `InteractionRayCast` then checks that point from the player's shoulder, limited to 2.4 m and blocked by solid world geometry. It excludes the player, accepts only `Interactable` targets and updates/clears prompts when targets change, disappear, become obstructed or the player freezes. The camera's 4 m offset does not increase pickup range. A small surface-crossing allowance avoids missing a collider when the camera query ends exactly on its boundary; it never increases the player reach cap.

The first-person `EquippableCamera`, `SubViewportContainer` and `SubViewport` are removed. There is one world-space `EquipmentPivot/ItemHolder`, one active equipped item, and one player camera. Existing equippable scenes, animation callbacks, weapon range/energy/hit logic, consumables, construction validation and crafting resources are retained. Held item meshes use the world visual layer. No item scene or animation was duplicated to simulate a second render pass.

A new real-building regression exposed an inherited runtime navigation synchronization error that Sprint 001 did not exercise. Runtime rebakes now parse ground/static collision geometry (layers 1 and 7), including constructed objects, rather than reading visual meshes back from the GPU. The navigation map uses Godot's recommended finer merge rasterization scale (0.001) to avoid coincident merge cells on narrow baked edges. The regression requires a completed, nonempty, changed navigation mesh after constructing a real campfire. Animal scripts and the startup baked mesh are retained.

## Desktop controls

Existing project input actions remain unchanged: WASD/arrows move, Shift sprints, Space jumps, E interacts, Tab opens crafting, Escape pauses/closes menus, number keys select equipment, and left click uses the equipped item. Mouse movement now orbits the third-person camera. Mouse wheel adjusts follow distance in 0.5 m steps. Camera and gameplay input are disabled while a player menu freezes the player; UI input remains available. Aim the reticle at nearby pickups/cookers; look down when placing a construction on the ground. Trees retain axe/hitbox interaction rather than gaining a new E action.

## Validation

Use the published Godot 4.4 environment. The shared runner now runs both sprints and rejects engine/script errors, missing success summaries, nonzero exits and timeouts:

```bash
XDG_CACHE_HOME=/workspace/.cache \
XDG_DATA_HOME=/workspace/.local/share \
XDG_CONFIG_HOME=/workspace/.config \
GODOT_BIN=/workspace/tools/godot-4.4/Godot_v4.4-stable_linux.x86_64 \
bash tests/run.sh
```

The new suite uses shipped production-density scenes. It verifies the primitive character and single-camera hierarchy; smooth rotation and pitch/zoom bounds; camera self-exclusion, wall retraction and recovery; camera-relative movement and facing with normal and rotated spawns; menu input freezing; real E pickup, reach limits, occlusion and prompt cleanup; world-space weapon animation hits and energy; single item instance after switching; consumable animation effects; ground construction preview; real campfire construction/consumption/navigation rebake; and clean scene transitions. Sprint 001 retains its existing movement, sprint, jump, gravity, HUD, inventory, crafting, survival, harvesting and restart coverage.

Renderer check and optional screenshot:

```bash
timeout --kill-after=10 240 bash /workspace/tools/survivalgame/run.sh \
  res://tests/sprint_002.tscn -- --capture
```

With a display, `--capture` saves `/tmp/kawanan-sprint002.png` after the island fade completes, before the test moves the player to its isolated physics arena. It is a local validation artifact, not a new game asset or a web preview.

### Recorded results

- Godot 4.4.stable.official.4c311cbee, Linux x86_64: shared headless runner **Sprint 001: 59 checks, 0 failures; Sprint 002: 46 checks, 0 failures**, exit 0, no engine/script errors or warnings.
- New checks use the shipped production-density island. The inherited Sprint 001 suite is unchanged; the common shell runner adds Sprint 002.
- Forward+ / software Vulkan (Mesa llvmpipe, Xvfb): **Sprint 002: 46 checks, 0 failures**, exit 0, no engine/script errors or warnings. This also exercised real construction and the subsequent navigation rebuild.
- Inspected `/tmp/kawanan-sprint002.png`: the default third-person view shows the primitive character from behind, the island and the existing HUD. This single frame does not validate hand/item posing or animation quality.
- The preview regression waits for its `_process` update rather than assuming that six physics ticks imply six rendered frames; this matters on a slow software renderer. It also waits for an in-progress navigation bake with a bounded timeout.
- Final Godot editor import/project scan: **passed**, exit 0, no engine/script errors or warnings.
- `bash -n tests/run.sh` and `git diff --check` passed.

### Changed and added files

- `README.md` — current prototype name, report link and camera/rendering descriptions.
- `actors/player/player.gd` — camera-relative movement, visual facing, input routing, equipment aiming and menu freezing.
- `actors/player/player.tscn` — follow rig, collision spring arm, original primitive character and single world equipment holder; remove overlay camera/viewport.
- `actors/player/main_camera.gd` — smooth orbit, zoom, limits and player collider exclusion.
- `actors/player/interaction_ray_cast.gd` — camera aim plus player reach/occlusion query and prompt lifecycle.
- `items/equippables/equippable_item.gd` — world render layer.
- `project.godot` — precise navigation edge merge rasterization.
- `stages/island/island.tscn` — runtime navmesh source uses ground/static colliders.
- `tests/run.sh` — run and validate both regression scenes.
- `tests/sprint_002.gd` — new integration/physics/animation tests and optional renderer capture.
- `tests/sprint_002.gd.uid` — Godot script UID.
- `tests/sprint_002.tscn` — new regression scene.
- `docs/SPRINT_002.md` — design, controls, tests, file inventory and limitations.

`actors/player/item_holder.gd`, equippable animation scenes and all existing art/audio files were reviewed and retained without modification. No main-branch changes or Android export settings are included.

## Remaining limitations

- A rendered frame and automated physics checks do not establish mouse feel, visual quality across every camera angle, sustained frame rate, long-session AI behavior or hardware performance. Close walls/corners, foliage occlusion and rapid camera motion still need a desktop human playtest.
- This is a primitive static character. Hand alignment, attachment poses and inherited first-person item animation presentation need an art/animation pass; no skeletal third-person animation is claimed.
- The camera sweep excludes characters/animals and interaction volumes, while blocking physical scenery. Temporary occlusion by animals or transparent foliage may still occur. No automatic character transparency or shoulder-switching feature is included.
- Third-person interaction requires aiming at a target within player reach; it does not introduce auto-targeting or remote pickup.
- Original source and asset redistribution permissions remain unresolved as documented in Sprint 001. The new primitives do not clear inherited licensing limitations.
- Android touchscreen input, export/signing, mobile performance, God Mode and combat/cooking balance are not part of this sprint.
