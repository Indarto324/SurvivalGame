# Sprint 001 — stabilization

Branch: `kawanan-island`. No changes are intended for `main`. Third-person camera, Android controls and Android export are outside this sprint.

## Changes

- Keep the HUD attached and toggle its visibility. Connect persistent HUD/slot signals in `_ready()` so re-entry cannot duplicate subscriptions; retain the inherited hotbar hover setup.
- Initialize hotbar state before the first hotkey, broadcast the new session's empty hotbar, publish initial survival stats, and clamp health to 0–100. These prevent empty-slot errors and stale HUD values after death/restart.
- Count only `null` inventory slots as empty. `Stick` is enum value zero and must still occupy space; a full inventory must not destroy an uncollected world item.
- Apply player gravity per second using physics delta (12 m/s², matching the old 0.2 per tick at 60 Hz). Walking, sprinting, jumping and the existing first-person camera remain in place.
- Free detached, unharvested tree stumps when their owning tree is deleted. Harvested trees still leave a stump and drop two logs. Clear collision shape ownership when Proton Scatter moves it into a temporary collision body. This is a local MIT-addon fix; its license notice remains intact.
- Attach spawned objects/VFX before applying their world transforms, so drops and constructions work under transformed holders without querying a detached node's world transform.

## Foliage policy

| Decorative grass generator | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Island | 200,000 | 12,000 | 94% |
| Main menu | 40,000 | 3,000 | 92.5% |

Disable only these two grass relaxation modifiers. Random placement, scale, terrain projection and grass meshes remain. Relaxation compares every point with every other point, making startup quadratic; the original island requests about 40 billion comparisons per iteration. Grass does not require that spacing calculation.

Harvestable tree (200), fruit bush (20), coal (20), flintstone (20), mushroom (50) and mixed plant/stone/stick (600) generator budgets are unchanged. Animals, terrain, navigation, recipes, resources, equipment, construction, audio and asset files are retained. These are generator budgets before terrain filtering, not guaranteed final instance counts. No mobile FPS claim follows from these reductions; visual density and device performance still need human review on target hardware.

## Running validation

Use Godot **4.4**, the existing checkout, and its imported assets. Import through a Vulkan-capable editor at least once: Proton Scatter has a compute shader that the headless importer cannot compile. No package install or external service is required by the game.

```bash
# On a machine with a display and Vulkan:
godot --editor --path . --import
GODOT_BIN=godot bash tests/run.sh
```

In the published cloud environment:

```bash
bash /workspace/tools/survivalgame/run.sh --editor --import
XDG_CACHE_HOME=/workspace/.cache \
XDG_DATA_HOME=/workspace/.local/share \
XDG_CONFIG_HOME=/workspace/.config \
GODOT_BIN=/workspace/tools/godot-4.4/Godot_v4.4-stable_linux.x86_64 \
bash tests/run.sh
```

`tests/run.sh` checks the Godot version, enforces an external timeout, preserves the engine exit code, requires a nonzero successful check count, and rejects runtime/script errors. The test scene loads the shipped menu and island at their production scatter counts; it does not patch scenes or lower density. It uses an isolated flat collision arena within the island to avoid random vegetation/animal interference in movement measurements.

The suite exercises HUD visibility and re-entry/subscriptions, full scene readiness, walking/sprinting/jumping, gravity at 30/120 Hz, freeze/unfreeze, inventory capacity and pickups, hotbar swaps/equipping, crafting quantity/tool requirements and consumption, fruit effects, survival bounds/exhaustion/death, harvesting/log drops/stump lifetime, day/night time advancement, a second survival session and credits. Sleep's clock signal is tested; the complete timed fade/sleep interaction is not automated.

`addons/proton_scatter/tests/unit_testing.tscn` is an interactive demonstration scene, not an assertion-based test runner. No other pre-existing automated gameplay suite was found.

## Limitations

The automated checks do not establish visual quality, audible output, mouse feel, complete combat/build/cook balancing, every recipe combination, long sessions, or Android readiness. The existing animal AI and physics deserve separate frame-rate and navigation profiling before mobile conversion. Review [licensing limitations](LICENSING_REVIEW.md) before any game distribution; missing project/asset permissions remain unresolved.

## Validation results

Godot 4.4.stable.official.4c311cbee, Linux x86_64, 2026-10-17:

| Check | Outcome |
| --- | --- |
| `tests/run.sh` (headless, production scenes/density) | **59 checks passed, 0 failed**, exit 0; no script/runtime errors, ownership warnings or shutdown leaks. |
| Same scene suite with Forward+ / Vulkan / Mesa llvmpipe / private Xvfb / dummy audio | **59 checks passed, 0 failed**, exit 0; no script/runtime errors, ownership warnings or shutdown leaks. |
| Godot editor asset import / project scan | Passed final refresh, exit 0; no script/runtime errors or warnings. |
| `git diff --check` | Passed. |

Observed scene readiness, including the existing fade: headless menu 1.295 s, island 1.962 s; software Vulkan menu 3.389 s, island 3.897 s. A second island load also passed in each run. These are current-instance smoke timings, not a controlled before/after FPS benchmark or an Android performance result. Original full-density island readiness was not established during onboarding, so no numerical startup speedup is claimed.

## Modified and added files

Application fixes:

- `actors/player/player.gd`
- `game/managers/equipped_item_manager.gd`
- `game/managers/hud_controller.gd`
- `game/managers/inventory_manager.gd`
- `game/managers/player_stats_manager.gd`
- `game/managers/spawner.gd`
- `objects/hittable_objects/hittable_object.gd`
- `ui/custom_nodes/hotbar_slot.gd`
- `ui/custom_nodes/inventory_slot.gd`
- `ui/hud/hotbar_ui.gd`
- `ui/hud/player_stats_container.gd`

Scene configuration and addon fix:

- `stages/island/island.tscn`
- `stages/main_menu/main_menu.tscn`
- `addons/proton_scatter/src/common/scatter_util.gd`

New tests and documentation:

- `tests/run.sh`
- `tests/sprint_001.gd`
- `tests/sprint_001.gd.uid`
- `tests/sprint_001.tscn`
- `docs/LICENSING_REVIEW.md`
- `docs/SPRINT_001.md`
