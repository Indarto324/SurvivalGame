# Sprint 008 — expanded main island (0.8.0-dev)

Branch `kawanan-island` only. Original assets retained; no external assets,
additional islands, boats or unrelated mechanics added. Internal debug build.

## Measurements before editing

Measured from Sprint 007 commit `0828bb79bed16c4fabe1186f1eed8866cc4e3da4`.
The original mesh is a hand-authored/imported ArrayMesh, not a runtime terrain
noise generator. Its 300 × 300 m bounding box includes extensive submerged seabed.
Nominal water surface is y = -2.81352 m. Triangle clipping at that level gives:

| Measurement | Before | After |
| --- | ---: | ---: |
| Terrain/seabed footprint | 300 × 300 m | 384 × 384 m |
| Nominal shoreline span X × Z | 116.404 × 160.303 m | 206.389 × 271.039 m |
| Projected land above nominal water | 11,779.777 m² | 39,563.303 m² |
| Terrain triangles | 3,362 | 18,432 |
| Terrain collision | one concave shape | 144 resident 32 × 32 m chunks |
| Original scatter box | 146.020 × 170.144 m | unchanged |
| Authored player spawn | (-23.2617, 1.58943, 37.1292) | unchanged |

Land area grows approximately **3.36×**. These are mesh measurements at a fixed
water level, not the animated wave contour. The former near-flat plateau above
-0.01 m occupies about 6,348 m². Both nominal shorelines and land areas are
computed by clipping triangles, rather than counting a rectangular map envelope.
Baseline data is included in the task artifact as `baseline.json`.

## World design

Expansion is connected north and east of the protected original spawn/core.
The original terrain scene and collision data remain intact in source; generated
chunks sample its actual triangles to preserve the core elevation. The original
render instance and collider are disabled only after all replacement chunks exist,
preventing overlapping surfaces. New terrain uses deterministic 4 m cells,
vertex colors and shared materials. Regridding approximates the old shoreline;
the original flat spawn ground remains y = 0.

- The west/south approach retains the original spawn, gathering and animals.
- Sandy shores lead into an eastern jungle with a concentrated, fixed tree budget.
- Northern hills have a primitive stone crown landmark and a winding approach.
- A shallow freshwater spring has a solid basin, enclosed shore and water surface
  whose outer edge is buried by terrain. The trail goes around the pool.
- Rocky eastern/southeastern ground has a split-coast stone landmark.
- Open beach/building areas, hill clearings and a future cave clearing remain
  available. There are no new cave, boat, drinking or swimming mechanics.

The marked route is dry above the ocean and its sampled maximum slope is about
31.2°. Other slopes, banks and landmark faces may be steeper. Ground collision
and a dry-land connectivity search verify all five regions are on the same main
island. Deep-ocean perimeter colliders keep ordinary walkers within the finite
seabed. Developer flight can go above these guards; disabling flight/recovery
still uses the established grounded checkpoint or island spawn. A below-seabed
fall guard also restores the authored spawn if normal physics ever falls below
y = -12 m; it does not interfere with deliberate developer flight.

## Android budgets and streaming

Original resource generators, seeds, animals and spawn positions are preserved.
New resources use the same harvestable and pickup scenes/callbacks.

| Object | Original generator budget | Additional manifest |
| --- | ---: | ---: |
| Trees | 200 | 64 |
| Fruit bushes | 20 | 12 |
| Coal boulders | 20 | 8 |
| Flintstone boulders | 20 | 8 |
| Mushrooms | 50 | 16 |
| Mixed sticks/stones/plants | 600 | 104 (40/40/24) |
| Grass | 12,000 candidates | 1,200 candidates; 451 accepted |
| Animals | 7 cows + 3 wolves | 0 |

Generator budgets precede terrain filtering and are not final instance counts.
The expansion has exactly 212 resource records, regardless of terrain area.
The combined tree budget increases 32%, versus 236% more land. Additional grass
is capped at 10% of the original budget; only 451 valid new placements remain.
The main menu and its 3,000-grass budget are unchanged.

- All terrain collision remains resident: neither walking, teleports nor flight
  can outrun ground loading. Terrain chunks receive normal renderer frustum
  culling. At 18,432 triangles, terrain mesh LOD/unloading is unnecessary here;
  retaining a single collision resolution avoids LOD cracks and missing ground.
- New detail manifests load by horizontal player distance: 80 m activation,
  112 m removal, checked every 0.25 s. One chunk activates per frame. A teleport
  removes stale queued activations. This provides hysteresis at chunk boundaries.
- New grass uses shared existing geometry/material in per-chunk MultiMeshes,
  no collision/shadows, and a 50 m visibility limit. Original 15 m grass batches
  now also have a 50 m limit. New resource geometry has a 105 m draw limit.
- Unvisited distant resource nodes are not instantiated. Visited chunks detach
  from the scene/physics tree and retain their altered nodes in memory. This
  preserves collected items, tree damage and stumps rather than regenerating loot.
  Retained memory is bounded by the fixed manifest, but it is not a disk cache.
  All detached objects are freed when leaving the island.
- Navigation gets an initial bake and covers all island ground/construction
  holders, including streamed collision. Cell size is 0.5 m (formerly 0.25 m)
  to limit rasterization cost. Settled detail changes trigger a debounced 1.5 s
  rebake; overlapping construction/stream requests are coalesced. Navigation may
  briefly lag a streamed obstacle; physical collision remains authoritative.

The existing 1,000 × 1,000 m ocean mesh/shader remains unchanged. No Android FPS
or memory improvement is claimed from these budgets. Device profiling is still
required, particularly while generating the initial terrain or rebaking navigation.

## Validation and artifacts

Pinned Godot 4.4.stable.official.4c311cbee; Mobile renderer, Linux software Vulkan
for visual checks; JDK 17, Android SDK/build tools 34 and matching export templates.

`tests/run.sh` preserves the existing **307 gameplay checks** and both developer
access-gate runs. Sprint 008 adds **44** checks: scene readiness, fixed budgets,
spawn grounding, 2,304 coverage probes, 363 chunk-corner probes, dry/walkable
routes, connected regions, resource placement, freshwater shore, initial
navigation, actual walking across a seam, flight, pickup/inventory callbacks,
chunk unload/revisit without loot duplication, far recovery and cleanup.

Final local results (2026-10-18): **351 gameplay checks passed, zero failures**,
plus both editor/release developer-gate checks. The graphical Mobile-renderer run
passed all 44 Sprint 008 checks. The actual exported APK asset pack also loaded
all 144 terrain chunks and grounded the player using a Linux debug template;
that dependency/pack smoke test is not Android device or emulator testing.
The signed debug APK passed package, permissions, version, CRC/alignment and
signature validation. `git diff --check` and shell syntax validation passed.

Run after a graphical Vulkan import:

```bash
GODOT_BIN=/path/to/Godot_v4.4-stable_linux.x86_64 bash tests/run.sh
bash scripts/android/build.sh /path/to/kawanan-island-debug.apk
```

The local artifact directory is `/workspace/artifacts/kawanan-sprint008/`:
APK, validation JSON, badging/manifest/signature/alignment reports, baseline and
world measurements, regression/build/import logs and seven screenshots. The
bundle is `/workspace/artifacts/kawanan-sprint008.zip`.

Screenshots use a test-only inspection camera at ground and aerial positions,
with the existing day/night animation held at daytime for readability. Production
camera and time progression are unchanged. Visual checks are desktop Mobile
rendering, not Android execution or a physical-device benchmark.

APK validation requires version **0.8.0-dev**, code **5**, package
`com.kawanangames.kawananisland`, ARM64, landscape, debug signing, zero permissions,
ZIP CRC/alignment and signature v2. Development tools retain the Sprint 007 debug
and internal-feature gates. CI uploads `kawanan-island-debug-<commit SHA>` with
seven-day retention. APK binaries and signing credentials are excluded from Git.

## Remaining limitations and device checks

No physical Android device was used in this task. Install the APK with
`adb install -r kawanan-island-debug.apk`; a different debug signing key requires
uninstalling the previous build first, clearing its data.

Test walking/sprinting/jumping through every region, three-finger flight/look,
fast travel across loading radii, foreground/background transitions, resource
pickup and harvesting after repeated revisits, building/navigation updates,
recovery near shores/hills, sustained memory use, thermals and frame pacing.

At extreme aerial heights, the finite seabed edge and distance culling are
visible. This remains a deliberately stylized prototype. The pool is landscape only,
foliage appears/disappears by distance, and retained visited objects consume
bounded memory. Navigation has a short update delay after chunk changes and
harvested obstacles otherwise retain the game's existing rebake behavior. The
world has no save/load persistence, caves or boats. Source/course and bundled
asset licensing issues from earlier sprints remain unresolved; do not publish
this internal build to Google Play.

## Changed files

- `stages/island/expanded_world.gd` (+ UID): generated terrain, biome colors,
  paths, spring/landmarks, safe perimeter and streamed resource state.
- `stages/island/island.tscn`: expansion child and original grass draw limits.
- `stages/island/nav_region.gd`: initial/group-source/debounced-request baking.
- `project.godot`: version and matching navigation map cell size.
- `export_presets.cfg`, `scripts/android/validate_apk.py`: version/code validation.
- `tests/sprint_008.gd` (+ UID), `tests/sprint_008.tscn`: integration and visuals.
- `tests/run.sh`, `.github/workflows/android-debug.yml`: run Sprint 008 in CI.
- `docs/SPRINT_008.md`: dimensions, budgets, validation and limitations.
