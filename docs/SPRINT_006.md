# Sprint 006 — primitive character animation

Date: 2026-10-18 (Asia/Tokyo). Branch: `kawanan-island`; `main` unchanged.
Development version **0.6.0-dev**, Android version code **3**, Godot **4.4 stable**.

## Implementation

`CharacterAnimator` is a lightweight procedural presentation layer attached to the
existing `CharacterVisuals` node. It retains the original seven primitive meshes,
materials, hierarchy and character silhouette. Cached rest transforms and virtual
shoulder/hip pivots articulate the limbs without adding a model, skeleton, skinning,
third-party assets or another AnimationPlayer. Mesh transforms blend exponentially
at the existing player physics rate; no independent animation process is added.

- **Idle:** torso breathing, subtle head movement and upper-body sway.
- **Walk:** opposite arm/leg swings; phase advances by actual distance traveled.
  A stationary character pressing into a wall remains Idle. Small vertical
  compensation keeps the straight primitive legs near the floor during walking.
- **Sprint:** faster cadence from measured speed, larger swings and upper-body
  lean/roll. Low analog speeds stay in Walk even if Sprint is held.
- **Jump/Fall:** ascending/descending poses use measured vertical velocity and
  actual grounded state after move_and_slide, rather than input intent.
- **Landing:** a short blended compression/recovery after airborne-to-ground
  contact, including primitive leg shortening to compensate for body compression.
- **Pickup:** a 0.48-second reaching/bending gesture follows the successful world
  pickup callback. A full inventory does not play a false pickup. The item still
  enters inventory immediately, at its original gameplay timing.
- **Chop/Attack:** arm windup/swing/recovery and body twist sample the equipped
  weapon AnimationPlayer's actual playback position. The existing check_hit
  method-track key provides the timing reference. Axe and pickaxe are tested;
  other EquippableWeapon items use the same observer path. Tool action takes
  priority over reaching; a pickup arriving during it can play afterward.

The animator changes only the seven mesh transforms. Character collision, camera
rig, equipment origin, interaction rays, hit rays and root movement are unchanged.
Player freeze suspends its animation updates along with existing player physics.
Stage exit automatically disconnects its successful-pickup notification listener.

## Gameplay callback boundaries

The existing equipment AnimationPlayers remain the only owners of hit, energy,
consumption, construction and related method-track callbacks. This sprint does not
edit their clips, durations, key times or item-use guards. Character animation only
reads them; it never advances, plays or seeks an equipment clip.

`PLA_pickup_collected` is a presentation notification emitted from the existing
successful Pickuppable.destroy callback, after the inventory manager accepts the
item. Calling the reaching pose cannot collect anything. Repeatedly evaluating
character poses cannot cause weapon hits. Animations do not impose a new movement
lock or delay item collection, harvesting or building.

The per-tick work is bounded to seven mesh poses and simple trigonometry. Rest
transforms are cached and weapon method-track metadata is inspected once per use,
not on every sampled frame. There are no new models, materials, textures or GPU
skinning passes in the production scene. Physical Android CPU/GPU performance has
not been measured; software-renderer movie timings are not a device benchmark.

## Validation

The final headless run completed **260 checks, zero failures**:

| Suite | Checks | Failures |
| --- | ---: | ---: |
| Sprint 001 | 59 | 0 |
| Sprint 002 | 46 | 0 |
| Sprint 003 | 60 | 0 |
| Sprint 005 | 48 | 0 |
| Sprint 006 | 47 | 0 |

The original 213 checks are retained. The new tests load the real menu/island,
player, touch controls, pickup scene, inventory, weapons and hitbox in a flat test
arena. They verify breathing, actual-speed cadence, alternating limbs, sprint,
jump/fall/landing, blocked movement, stable camera/capsule/equipment transforms,
pickup acceptance/full-inventory handling, presentation-only reaching, original
0.2-second axe hit key, exactly one hit and original energy cost per axe/pickaxe
use, repeated-use guards, tool retention, pose blending, freeze/resume and cleanup.
The fixed-step transition test bounds frame-to-frame mesh rotation/translation
when locomotion targets change abruptly.

A separate Vulkan/Mobile-renderer Movie Maker run also passed all **47** animation
checks. Captured and inspected pose screenshots cover idle, walk, sprint, jump,
fall, landing, pickup and chop. The silent H.264 clip is **16.6 seconds**, 1280×720,
30 recorded frames/second. It uses a test-only three-quarter viewer camera, flat
floor and light to expose limb motion clearly; these additions are excluded from
shipping exports. The normal gameplay camera remains unchanged. This is Linux
software Vulkan validation with simulated touch, not an Android device recording.

Godot project import, shell/Python/YAML checks and Android APK export/validation
passed. Sprint 004's static validation checks the actual APK's package, version,
launcher, landscape orientation, ARM64 ELF, debug signature, ZIP CRC/alignment,
license notices, zero requested permissions and excluded tests/signing files.
The expected package remains `com.kawanangames.kawananisland` / Kawanan Island.

## Reproduce and download

```bash
cd /workspace/SurvivalGame
export XDG_CACHE_HOME=/workspace/.cache
export XDG_DATA_HOME=/workspace/.local/share
export XDG_CONFIG_HOME=/workspace/.config
export GODOT_BIN=/workspace/tools/godot-4.4/Godot_v4.4-stable_linux.x86_64
bash tests/run.sh
bash scripts/android/build.sh
```

`tests/run.sh` and GitHub Actions now include Sprint 006. Default APK output is
ignored `builds/android/kawanan-island-debug.apk`. Cloud artifacts are under
`/workspace/artifacts/kawanan-sprint006/`:

- `kawanan-island-debug.apk` — validated ARM64 internal debug APK, 39,996,293 bytes.
- `animation-validation.mp4` — silent animation validation clip.
- `idle.png`, `walk.png`, `sprint.png`, `jump.png`, `fall.png`, `landing.png`,
  `pickup.png`, `chop.png` — captured poses.
- `regressions.log`, `visual-validation.log`, `import.log`, `build.log` and APK
  manifest/signature/alignment/validation sidecars — verification evidence.

APK SHA-256:
`917dc78ba4e6002de0c78a7407caa967f3ad28c6fd58afc3f99870ef2e44034a`.
A ZIP containing APK, video, screenshots and reports is available at
`/workspace/artifacts/kawanan-sprint006.zip`. GitHub Actions uploads the internal
APK as `kawanan-island-debug-<full commit SHA>` for seven days on a successful run.
No APK, recording, generated cache, signing key or credentials are committed.

## Remaining limits and device retest

No physical-device test of this new build was performed. The preceding device
report remains evidence only for the prior build's installation/movement/camera.
On Android, retest all seven animation categories while moving, looking, using
multiple fingers, collecting/crafting/equipping, harvesting and building. Verify
unchanged hit/energy/item counts, menu/pause/resume/background behavior, animation
smoothness on slopes and sustained frame pacing/heat on mid-range devices.

This remains an articulated primitive placeholder: no elbow/knee skeleton,
terrain foot IK, root motion, exact hand-to-tool grip IK, or new consumable/building
character gestures. Some limb/tool separation and foot sliding on uneven terrain
remain possible. Those refinements would require further visual/device testing.
Existing item animations remain intact, including their mesh movement.

Install using Sprint 004's instructions. Fresh CI debug signing keys can differ
between runs; a signature mismatch requires uninstalling the previous debug build,
which deletes app data. Do so only when that loss is intended. Stock-template icon
warnings, 4 KiB native alignment/16 KiB-device compatibility limits and unresolved
source/asset licensing remain as previously documented. Internal testing only;
no Google Play/public release is configured or authorized by this sprint.

## Modified files

- `.github/workflows/android-debug.yml`
- `actors/player/character_animator.gd`
- `actors/player/character_animator.gd.uid`
- `actors/player/player.gd`
- `actors/player/player.tscn`
- `docs/SPRINT_006.md`
- `export_presets.cfg`
- `game/event_system.gd`
- `interactables/pickuppables/pickuppable.gd`
- `project.godot`
- `scripts/android/validate_apk.py`
- `tests/run.sh`
- `tests/sprint_006.gd`
- `tests/sprint_006.gd.uid`
- `tests/sprint_006.tscn`
