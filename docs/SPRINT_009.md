# Sprint 009 — Living Island (0.9.0-dev / Android code 6)

Repository branch: `kawanan-island`. The Sprint 008 terrain, original island,
controls, character/equipment animation, survival and developer access gates are
retained. No additional animals, islands, boats, models or external assets.

## Inspection and wildlife changes

The existing cow/wolf scenes inherit `animal_template.tscn`. They already provide
Idle, Walk, Eating, Gallop, hurt, death and attack clips, with a 0.2 s animation
blend. Cow also supplies `Idle_Headlow`. Originally, wandering chose random
velocity, chasing had no distance/territory limit, idle animals still processed
physics every frame, and gravity subtracted 2 units per tick. Vision ignored
static trees/boulders and interpreted the FOV value as a half-angle.

The original population remains **7 cows + 3 wolves**. Four cows and one wolf
keep their original homes. Three existing cows now occupy jungle, spring-side
and rocky-coast territories; two existing wolves occupy jungle/hill territories.
Resource placements reserve these homes. No wildlife respawn system was added.

Cows idle, wander, graze using Eating, and rest using standing `Idle_Headlow`.
There is no lying-down clip in the existing cow asset. Night raises the chance
of rest at the next idle decision, without interrupting hurt/combat. Players
within 3.5 m can startle cows into a short, bounded flee behavior.

Wolves patrol around a 24 m home radius. Detection is limited to 15 m with an
80° full FOV and environment line of sight. Pursuit stops when player distance
exceeds 26 m, the player leaves the home leash (home radius + 12 m), or a safe
route cannot be found. Cows normally wander within 14 m of home.

Goals must project onto navigation and have a reachable path. Paths sample dry,
walkable terrain at up to 2 m spacing (64-probe cap); ocean, the spring pool,
steep slopes and off-map positions are rejected. Moving animals also check the
next 1.4 m at each decision. Physical collision remains authoritative. Feet-level
animal origins need a 0.5 m path-height offset to advance past elevated voxel
waypoints; actual movement tests caught and verified this correction.

Gravity now uses 12 m/s² × delta. State transitions blend existing animations.
Damage still comes from the **original attack method track at 0.4 s**, not from
AI decisions or pose playback. The integration test verifies one hit per attack.
Existing weapon damage, hurt reactions, a single meat drop and the 10 s corpse
cleanup timer remain. Repeated death transitions cannot duplicate drops.

## Resources and exploration

The existing retained-node streaming model is unchanged: unload detaches a
visited chunk, and reload reattaches the same altered nodes. Collection, fruit,
mining, tree drops, inventory and crafting use the existing callbacks. There is
no new resource regeneration or persistence outside the current game session.

The expansion still has **212 resource objects** with these explicit quotas:

| Region | Manifest allocation |
| --- | --- |
| Beach | 28 sticks, 18 stones |
| Jungle | 64 trees, 9 fruit bushes, 12 plants, 12 mushrooms, 8 sticks |
| Freshwater perimeter | 3 fruit bushes, 12 plants, 4 mushrooms, 4 sticks |
| Hills | 6 coal boulders, 4 flint boulders, 6 stones |
| Rocky coast | 2 coal boulders, 4 flint boulders, 16 stones |

Beach gathering sits on dry shore above the sea, and freshwater gathering stays
outside the pool. Positions reserve 6 m around exploration points and 3 m around
new wildlife homes. Existing original-island scatter budgets remain untouched.

Five labeled, nonblocking landmarks mark Main Beach Camp, Deep Jungle, Northern
Viewpoint, Freshwater Spring and Rocky Coast Viewpoint. They use shared Godot
prisms and distance-limited Label3D nodes: **15 small mesh instances + 5 labels**,
with no collision, navigation, lights or particles. Original Sprint 008 landmarks
remain. All five positions are close to walkable navigation and their regions
remain connected. Clearings remain available for construction. The spring is
still a landscape feature; no thirst, drinking or swimming system was invented.

## Environment and navigation

The existing island ambience/day-night animation remains. An additional original
surf-like loop is deterministically generated from filtered noise by
`scripts/generate_coastal_ambience.py`; no external recording or samples are used.
The 7.5 s mono 16 kHz PCM source asset is approximately 240 KB; Godot imports
it using its compressed WAV setting. Imported sample-frame loop metadata is
retained rather than deriving duration from compressed byte counts. The loop increases near
coasts while the original ambience is attenuated there; night also softens the
base track. Both use the existing Music bus, and the original track volume is
restored on island exit. Audio setup/mixing was tested with a dummy output;
listening quality still needs human/device review.

Streamed grass uses a small shared GPU wind shader, with at most 3.5 cm tip sway.
No per-instance CPU transforms or animated collision are introduced. Existing
water motion, lighting and day/night effects are retained; no extra lights or
particle systems are added.

Visual validation found non-manifold edges in Recast's merged navigation
polygons on the northern hill contours. Baking triangles (`vertices_per_polygon
= 3`) eliminated the overlaps while retaining the same terrain and 0.5 m nav
cell size. A representative visual bake had 3,457 navigation polygons, versus
3,180 in the failing n-gon bake; this is an observed bake count, not a fixed
cross-platform budget. A new test rejects edges shared by more than two polygons.
The existing merge tolerance remains unchanged.

Navigation requests coalesce, wait one frame for queued scatter/build cleanup,
and streamed-detail rebakes wait until original scatter loading completes.
Construction and settled chunk changes still refresh navigation. Terrain physics
remains resident even while navigation refreshes.

## Budgets and estimated processing costs

| Budget | Sprint 008 | Sprint 009 |
| --- | ---: | ---: |
| Terrain | 384 × 384 m / 18,432 triangles | unchanged |
| Terrain chunks/collision | 144 resident chunks | unchanged |
| Expansion resource objects | 212 | 212, redistributed |
| Accepted expansion grass | 451 | 451 |
| Grass candidate cap | 1,200 | 1,200 |
| Original grass requests | 12,000 | unchanged |
| Wildlife population | 10 | 10, five homes redistributed |
| Added environmental lights / particles | 0 | 0 |

Streaming activation/removal radii remain 80/112 m, with a 0.25 s check and one
chunk activation per frame. Grass remains limited to 50 m drawing distance;
resource geometry to 105 m. Wildlife geometry uses a 95 m draw limit.

The activity manager polls ten animals at **2 Hz**: about 20 distance tests/s.
Animals activate within 55 m and sleep beyond 70 m. Sleeping animals have physics
AI and skeletal animation disabled and behavior timers paused; their bodies remain
available for collision. Dead animals retain their death/cleanup sequence.

Active animals make decisions at **4 Hz** and perform movement/ground collision
at the normal physics rate. Test scenarios observed **2 active at spawn** and
**4 in the jungle**. At 60 physics Hz that implies approximately:

| Scenario | Decisions/s | Movement callbacks/s |
| --- | ---: | ---: |
| Spawn, 2 active | 8 | 120 |
| Jungle sample, 4 active | 16 | 240 |
| Worst configured case, 10 active | 40 | 600 |
| Distant sleeping animal | 0 | 0 |

These are scheduling estimates, not measured CPU milliseconds or Android FPS.
The three wolves can request at most about 12 chase paths/s at the decision rate;
wander choices try at most six candidates per transition. Each route is capped
at 64 terrain probes. Grass sway has zero per-instance CPU updates. Ambient mixing
uses the same 2 Hz timer, one additional mono stream, and no distance emitters.

Local headless island readiness in the regression run was around 2 seconds
(example observations 1.94–2.62 s, including the existing transition). Software
Vulkan runs have different timings. These are current-host smoke observations,
not controlled before/after mobile performance measurements. Device profiling is
still required for navigation rebakes, rendering, memory, thermals and frame pacing.

## Validation, APK and artifacts

Pinned Godot 4.4.stable.official.4c311cbee, Mobile renderer; JDK 17 and Android
SDK/build tools 34 with matching export templates. Version **0.9.0-dev**, Android
code **6**, package **com.kawanangames.kawananisland**. Internal signed ARM64 debug
APK, landscape, zero permissions. Debug keystores and APK binaries stay out of Git.

The full runner preserves the **351 existing gameplay checks** and both developer
access-gate checks. Sprint 009 adds **68** checks covering real animal movement,
states, proximity, safe navigation, leashes, timed combat, death drops, biome
quotas, resource persistence/inventory, day/night mixing, POI reachability,
God Mode flight, budgets, loading and cleanup. Engine errors fail validation even
when individual assertions pass.

Final local results (2026-10-18): **419 gameplay checks passed, zero failures**
(351 existing + 68 new), plus both developer-access gates. The Mobile-renderer
visual run passed all 68 Sprint 009 checks with no script/runtime errors. Eight
screenshots were captured and reviewed. The signed APK passed package/version,
permissions, ZIP CRC/alignment and signature-v2 validation. `git diff --check`
and shell syntax checks passed. The exported APK resource pack also loaded all
144 terrain chunks, ten animal scenes and the complete coastal loop using a Linux
debug template. This is pack/dependency validation, not Android execution.

```bash
# Import once with a Vulkan-capable display, then:
GODOT_BIN=/path/to/Godot_v4.4-stable_linux.x86_64 bash tests/run.sh
bash scripts/android/build.sh /path/to/kawanan-island-debug.apk
```

Artifacts: `/workspace/artifacts/kawanan-sprint009/` and the downloadable bundle
`/workspace/artifacts/kawanan-sprint009.zip`. They contain APK/package validation,
logs, `living-validation.json`, and eight screenshots: beach, jungle, hills,
freshwater, rocky coast, cow grazing, standing rest and wolf patrol. Screenshots
use a test-only inspection camera and daytime hold. Production camera/time
progression is unchanged. CI uploads `kawanan-island-debug-<commit SHA>` for seven days.

## Limits and physical-device follow-up

No physical Android device was used. Install with `adb install -r` and the APK
path. A different debug signing key requires uninstalling the previous build,
which clears its data. Retest touchscreen multitouch, inventory/crafting,
construction, harvesting, chase/escape, repeated chunk revisits, app background /
resume, audio settings, prolonged memory use and real-device frame pacing.

Wildlife uses bounded waypoint behavior, not herd simulation, scent or a full
food chain. Rest is standing, as supported by the existing asset. Route validation
is conservative; animals may stop when no safe goal is available. Streamed
navigation has an update delay, and visited resources retain bounded in-memory
state rather than disk persistence. The freshwater landmark has no consumption
mechanic. Existing licensing/provenance limitations for inherited assets remain
unresolved; this is not a Google Play release. The new surf asset is original
procedural audio and does not resolve permissions for inherited recordings.

## Changed files

- `actors/animals/animal.gd`: behavior, path safety, activity, gravity and combat guards.
- `stages/island/expanded_world.gd`: biome manifests, wildlife-home/POI reservations,
  fixed grass count, wind material, living controller and safe nav scheduling.
- `stages/island/nav_region.gd`: triangular baking and deferred/coalesced requests.
- `stages/island/living_island.gd` (+ UID): bounded activity, home placement, ambience, POIs.
- `stages/island/grass_wind.gdshader` (+ UID), `grass_wind.tres`: shared wind effect.
- `audio/music/coastal_surf.wav` (+ import settings),
  `scripts/generate_coastal_ambience.py`: original deterministic coastal loop.
- `game/main_game.tscn`: group reference for existing island music controller.
- `project.godot`, `export_presets.cfg`, `scripts/android/validate_apk.py`: version/code.
- `tests/sprint_009.gd` (+ UID), `tests/sprint_009.tscn`, `tests/run.sh`,
  `.github/workflows/android-debug.yml`: integration checks and CI coverage.
- `docs/SPRINT_009.md`: this report.
