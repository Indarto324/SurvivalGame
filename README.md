# Kawanan Island

Godot 4.4 third-person survival prototype, developed from SurvivalGame on the `kawanan-island` branch. See [Sprint 002](docs/SPRINT_002.md) for controls, camera/equipment design, validation and remaining limitations, and [licensing review](docs/LICENSING_REVIEW.md) before distribution.

Not an official repo, here I am just following the Godot course by [Eerik Hirvonen](https://www.udemy.com/user/eerik-hirvonen/)

![screenshot](https://raw.github.com/afarber/SurvivalGame/master/screenshot.png)

---

## Table of Contents
- [Project Overview](#project-overview)
- [Architecture Overview](#architecture-overview)
- [Class Systems](#class-systems)
- [Resource Files](#resource-files)
- [Gameplay Systems](#gameplay-systems)
- [Development Notes](#development-notes)

---

## Project Overview

This is a 3D survival game built in Godot 4.4 following a course by Eerik Hirvonen. The game features resource gathering, crafting, construction, and survival mechanics on an island setting.

### Project Statistics
- **Total Custom Files**: 143 (excluding addons)
- **GDScript Classes**: 46 custom classes
- **Scene Files**: 58 .tscn files
- **Resource Files**: 39 .tres resources
- **Engine**: Godot 4.4 (Forward Plus)
- **Main Scene**: `res://game/main_game.tscn`

---

## Architecture Overview

### Central Event System (Signal Bus)
**File**: `game/event_system.gd`

The game uses a centralized event system that acts as a global autoload. All major game systems communicate through 41 signals with specific prefixes:

- **BUL_*** - Bulletin/UI system (5 signals)
- **INV_*** - Inventory system (9 signals)
- **PLA_*** - Player actions and stats (5 signals)
- **EQU_*** - Equipment system (4 signals)
- **SFX_*** - Sound effects (2 signals)
- **MUS_*** - Music system (1 signal)
- **STA_*** - Stage/scene management (1 signal)
- **GAM_*** - Game state (4 signals)
- **HUD_*** - HUD visibility (2 signals)
- **SET_*** - Settings (6 signals)
- **SPA_*** - Spawning system (2 signals)

### Key Architectural Patterns

1. **Signal-Based Decoupling** - All systems communicate via EventSystem, eliminating direct dependencies between game systems
2. **Configuration-Based Design** - Enum registries (ItemConfig, BulletinConfig, StageConfig) for centralized asset management
3. **Manager Pattern** - 12 singleton managers for different systems with clear separation of concerns
4. **Resource-Based Content** - All items defined as .tres resources for data-driven development
5. **Scene Composition** - Templates for common patterns (pickuppables, equippables, hittables)
6. **State Machines** - Used for animal AI behavior, player states, and equipment states

---

## Class Systems

### 1. Actors System (`actors/`)

#### Player System (`actors/player/`)

| Class | File | Purpose |
|-------|------|---------|
| **Player** | `player.gd` | Main character controller (extends CharacterBody3D) |
| ItemHolder | `item_holder.gd` | Manages equipped item visuals |
| InteractionRayCast | `interaction_ray_cast.gd` | Handles object interaction detection |
| MainCamera | `main_camera.gd` | Third-person orbit/follow camera rig |

**Player Features**:
- Movement speeds: normal (3.0 u/s), sprint (5.0 u/s)
- Energy consumption during movement
- Jump mechanics with gravity
- Mouse-look controls (0.005 sensitivity)
- Footstep audio with interval timing
- Freeze/unfreeze state management

#### Animal System (`actors/animals/`)

| Class | File | Purpose |
|-------|------|---------|
| **Animal** | `animal.gd` | Base AI character for cows/wolves |
| (Instances) | `cow.tscn`, `wolf.tscn` | Specific animal implementations |

**Animal States** (Enum):
- Idle, Wander, Dead, Flee, Hurt, Chase, Attack

**Animal Features**:
- Navigation agent pathfinding
- Vision area detection
- Multiple animation support
- Health/damage system
- Meat drop on death
- Configurable speeds and timers

---

### 2. Interactable System (`interactables/`)

#### Base Interactable Class
| Class | File | Purpose |
|-------|------|---------|
| **Interactable** | `interactable.gd` | Base Area3D for all interactive objects |

#### Pickuppable Items (`interactables/pickuppables/`)
| Class | File | Purpose |
|-------|------|---------|
| **Pickuppable** | `pickuppable.gd` | Base class for pickup-able items |
| (Scenes) | Multiple .tscn templates | Rigid and static pickuppables |

**Pickuppable Variants**:
- **Static pickuppables**: plant, fruit, mushroom, stone, stick
- **Rigid pickuppables**: log, coal, flintstone, raw meat
- Templates for custom items

#### Special Interactables
| Class | File | Purpose |
|-------|------|---------|
| InteractableCooker | `cooker/interactable_cooker.gd` | Cooking station interaction |
| InteractableRaft | `interactable_raft.gd` | Raft-specific interactions |
| InteractableSleepPoint | `interactable_sleep_point.gd` | Sleep mechanics |

---

### 3. Items & Equipment System (`items/equippables/`)

#### Class Hierarchy
```
EquippableItem (Base - extends Node3D)
├── EquippableWeapon (damage detection, hit checking)
├── EquippableConsumable (health/energy changes)
└── EquippableConstructable (placement preview, validity checking)
```

#### EquippableItem
**Base Class**: Node3D
- Manages animations via AnimationPlayer
- World-space item rendering (layer 1, single gameplay camera)
- `try_to_use()` - plays animation

#### EquippableWeapon
**Extends**: EquippableItem

**Features**:
- Weapon resource reference
- Hit check via raycasting (physics layer 8)
- Particle effect spawning on hit
- Energy consumption on use
- Swoosh audio playback

#### EquippableConsumable
**Extends**: EquippableItem

**Features**:
- Health restoration
- Energy restoration
- Auto-removal after consumption

#### EquippableConstructable
**Extends**: EquippableItem

**Features**:
- Place preview mesh with material switching
- Valid/invalid placement detection (green/red materials)
- Collision detection via Area3D
- Build validity checking via raycast
- Construction scene spawning

**Equippable Scenes**: 15+ equippable variants including axe, pickaxe, tent, campfire, torch, raft, consumables

---

### 4. Resource System (`resources/`)

#### Item Configuration (`game/configs/item_config.gd`)
Central enum-based item management:

**ItemConfig.Keys Enum**:
```gdscript
# Pickuppables
Stick, Stone, Plant, Mushroom, Fruit, Log, Coal, Flintstone, RawMeat, CookedMeat

# Craftables
Axe, Pickaxe, Campfire, Multitool, Rope, Tinderbox, Torch, Tent, Raft
```

Maps item keys to resource files and scene paths for centralized asset management.

#### Item Resource Classes (`resources/items/`)

| Class | File | Base | Purpose |
|-------|------|------|---------|
| **ItemResource** | `item_resource.gd` | Resource | Base item definition |
| **WeaponItemResource** | `weapon_item_resource.gd` | ItemResource | Weapons (damage, range, energy) |
| **ConsumableItemResource** | `consumable_item_resource.gd` | ItemResource | Consumables (health, energy) |

**ItemResource Properties**:
- item_key, display_name, icon, description
- is_equippable, cooking_recipe

**35+ item resource files** covering all 19 item types

#### Crafting System (`resources/crafting_blueprints/`)

| Class | File | Purpose |
|-------|------|---------|
| **CraftingBlueprintResource** | `crafting_blueprint.gd` | Blueprint base class |
| **CraftingBlueprintCostDataResource** | `crafting_blueprint_cost_data.gd` | Cost definitions |
| (Instances) | 9x blueprint .tres files | Individual crafting recipes |

**Crafting Features**:
- Cost-based item requirements
- Tool requirements (multitool, tinderbox)
- 9 craftable items: Axe, Pickaxe, Campfire, Multitool, Rope, Tinderbox, Torch, Tent, Raft

**Crafting Blueprints** (9 files):
- axe_blueprint.tres
- pickaxe_blueprint.tres
- campfire_blueprint.tres
- multitool_blueprint.tres
- rope_blueprint.tres
- tinderbox_blueprint.tres
- torch_blueprint.tres
- tent_blueprint.tres
- raft_blueprint.tres

#### Cooking System (`resources/cooking_recipes/`)

| Class | File | Purpose |
|-------|------|---------|
| **CookingRecipeResource** | `cooking_recipe_resource.gd` | Cooking recipe definition |
| (Instances) | .tres files | Individual recipes (meat_recipe.tres) |

**Cooking Properties**:
- uncooked_item, uncooked_item_visuals
- cooked_item, cooked_item_visuals
- cooking_time

#### Hittable Objects (`resources/hittable_object_attributes/`)

| Class | File | Purpose |
|-------|------|---------|
| **HittableObjectAttributes** | `hittable_object_attributes.gd` | Hit target definition |
| (Instances) | 3x .tres files | Tree, Coal, Flintstone attributes |

**Properties**:
- drop_item_key, max_health, weapon_filter

---

### 5. Game Managers (`game/managers/`)

**12 singleton managers** for different systems:

| Manager | File | Responsibility |
|---------|------|-----------------|
| **BulletinController** | `bulletin_controller.gd` | UI panel lifecycle (create/destroy) |
| **InventoryManager** | `inventory_manager.gd` | Item storage and manipulation |
| **EquippedItemManager** | `equipped_item_manager.gd` | Active item hotbar management |
| **PlayerStatsManager** | `player_stats_manager.gd` | Health/energy tracking (max 100 each) |
| **StageController** | `stage_controller.gd` | Scene loading/transitions |
| **SFXController** | `sfx_controller.gd` | Sound effects playback |
| **MusicController** | `music_controller.gd` | Music state management |
| **SettingsController** | `settings_controller.gd` | Game settings persistence |
| **HUDController** | `hud_controller.gd` | HUD visibility management |
| **GameFadeController** | `game_fade_controller.gd` | Screen fade animations |
| **DayNightCycleAnimPlayer** | `day_night_cycle_anim_player.gd` | Time progression animation |
| **SleepManager** | `sleep_manager.gd` | Rest mechanics |
| **Spawner** | `spawner.gd` | Scene instantiation system |

#### InventoryManager
**Structure**:
- Inventory: Fixed 28 slots
- Hotbar: Fixed 9 slots

**Key Methods**:
- `try_to_pickup_item()`
- `switch_two_item_indexes()`
- `add_item()`, `delete_item_by_index()`
- `delete_blueprint_costs()`
- `get_free_slots()`

#### EquippedItemManager
**Features**:
- Tracks active hotbar slot
- Handles hotkey input (1-9)
- Equip/unequip item state
- Responds to inventory changes

#### PlayerStatsManager
**Constants**:
- MAX_ENERGY = 100.0
- MAX_HEALTH = 100.0

**Methods**:
- `change_energy()`, `change_health()`

---

### 6. Configuration Classes (`game/configs/`)

| Config | File | Purpose |
|--------|------|---------|
| **ItemConfig** | `item_config.gd` | Central item definitions & mappings |
| **BulletinConfig** | `bulletin_config.gd` | UI panel enumeration |
| **StageConfig** | `stage_config.gd` | Scene enumeration (Island, MainMenu, Credits) |
| **MusicConfig** | `music_config.gd` | Music track enumeration |
| **SFXConfig** | `sfx_config.gd` | Sound effect enumeration |
| **VFXConfig** | `vfx_config.gd` | Particle effect enumeration |

**BulletinConfig.Keys Enum**:
- InteractionPrompt, CraftingMenu, CookingMenu, PauseMenu, SettingsMenu

**StageConfig.Keys Enum**:
- Island (main gameplay), MainMenu, Credits

---

### 7. Objects System (`objects/`)

#### Hittable Objects (`objects/hittable_objects/`)

**HittableObject** - `hittable_object.gd` (extends Node3D)

**Features**:
- Health system with weapon filtering
- `register_hit()` - applies weapon damage
- `die()` - spawns drops at spawn points
- Optional residue mesh for destruction aftermath
- VFX spawning on hit

**Instances**:
- Hittable Tree (drops logs)
- Coal Boulder (drops coal)
- Flintstone Boulder (drops flintstone)

#### Constructable Objects (`objects/constructables/`)
**Instances**: Tent, Campfire, Raft

---

### 8. UI/Bulletin System (`bulletins/`)

#### Base Classes

| Class | File | Base | Purpose |
|-------|------|------|---------|
| **Bulletin** | `bulletin.gd` | Control | Base UI panel |
| **PlayerMenuBase** | `player_menus/player_menu_base.gd` | Bulletin | Menu infrastructure |

#### UI Menus

| Menu | File | Extends | Purpose |
|------|------|---------|---------|
| CraftingMenu | `player_menus/crafting_menu/crafting_menu.gd` | PlayerMenuBase | Item crafting UI |
| CookingMenu | `player_menus/cooking_menu/cooking_menu.gd` | PlayerMenuBase | Cooking UI |
| PauseMenu | `pause_menu/pause_menu.gd` | Bulletin | Game pause |
| SettingsMenu | `settings_menu/settings_menu.gd` | Bulletin | Game settings |
| InteractionPrompt | `interaction_prompt/interaction_prompt.gd` | Bulletin | Interaction hints |
| FadingBulletin | `fading_bulletin/fading_bulletin.gd` | Bulletin | Temporary messages |

#### UI Components (`ui/custom_nodes/`)
- UIButton
- InventorySlot, HotbarSlot
- CraftButton
- FinalCookingSlot, ScrapItemSlot, StartingCookingSlot

#### HUD System (`ui/hud/`)
- **HotbarUI** - Equipment hotbar display
- **PlayerStatsContainer** - Health/energy display

---

### 9. Stages/Scenes System (`stages/`)

#### Base Stage Class
**File**: `stage.gd` | **Base**: Node

**Features**:
- Proton Scatter node integration
- Music selection
- Loading completion signal
- Mouse visibility control

#### Stage Implementations

| Stage | Files | Purpose |
|-------|-------|---------|
| **Island** | `island/island.tscn`, `island/nav_region.gd` | Main gameplay |
| **MainMenu** | `main_menu/main_menu.tscn`, `main_menu.gd` | Start screen |
| **Credits** | `credits/credits_stage.tscn`, `credits_stage.gd` | Credits display |

---

## Resource Files

### Item Resources (35 files)
**Location**: `resources/items/`

**Categories**:
- **Pickuppables**: stick, stone, plant, mushroom, fruit, log, coal, flintstone
- **Food**: raw_meat, cooked_meat
- **Tools**: axe, pickaxe, multitool, tinderbox
- **Light**: torch
- **Construction**: tent, campfire, raft
- **Consumables**: mushroom, fruit, cooked_meat, rope

### Crafting Blueprints (9 files)
**Location**: `resources/crafting_blueprints/`

Each craftable item has a blueprint defining material costs and tool requirements:
- axe_blueprint.tres
- pickaxe_blueprint.tres
- campfire_blueprint.tres
- multitool_blueprint.tres
- rope_blueprint.tres
- tinderbox_blueprint.tres
- torch_blueprint.tres
- tent_blueprint.tres
- raft_blueprint.tres

### Other Resources
- **Hittable Attributes** (3 files): tree, coal, flintstone
- **Cooking Recipes** (1 file): meat_recipe.tres
- **Materials** (2 files): constructable_valid (green), constructable_invalid (red)
- **Themes**: default_ui_theme.tres
- **Shaders**: water_shader.tres

---

## Gameplay Systems

### Core Gameplay Loop
**Explore → Gather/Harvest → Craft → Cook → Build → Fight → Survive → Rest**

### Inventory System
- **Fixed 28 slots** for main inventory
- **9 hotbar slots** for quick access
- Drag-and-drop UI management
- Signals for all inventory operations

### Energy System
- Walking consumes energy (-0.05 per meter traveled)
- Energy below 0 damages health
- Consumables restore energy and health
- Equipment usage consumes energy

### Crafting System
- **9 craftable items** total
- Some items require specific tools (multitool, tinderbox)
- Blueprint-based with cost requirements
- Access via crafting menu

### Cooking System
- Campfire-based cooking
- Raw meat → Cooked meat transformation
- Time-based cooking process
- Visual representation of cooking progress

### Construction System
- Place buildings: tent, campfire, raft
- Placement preview with validity checking
- Green/red material feedback for valid/invalid placement
- Collision detection prevents overlapping structures

### Combat System
- Weapon-based combat (axe, pickaxe)
- Raycast hit detection
- Animals have health and flee/chase/attack AI
- VFX on hit
- Energy consumption per attack

### Survival Mechanics
- **Health**: Max 100, damaged by energy depletion or combat
- **Energy**: Max 100, consumed by movement and actions
- **Consumables**: Restore health/energy (mushroom, fruit, cooked meat)
- **Rest**: Sleep at tent to recover

### Resource Gathering
1. **Pickuppables** - Collect from ground (stick, stone, plant, mushroom, fruit)
2. **Hittables** - Hit with tools to gather (trees → logs, boulders → coal/flintstone)
3. **Hunting** - Defeat animals for raw meat

### Item Categories (19 total)
- **10 Pickuppable items**: Stick, Stone, Plant, Mushroom, Fruit, Log, Coal, Flintstone, RawMeat, CookedMeat
- **9 Craftable items**: Axe, Pickaxe, Campfire, Multitool, Rope, Tinderbox, Torch, Tent, Raft

---

## Physics Layers

Defined in `project.godot`:

1. **ground** - Terrain surfaces
2. **actor** - Player and NPCs
3. **interactable** - Interactive objects
4. **hitbox** - Hit detection areas
5. **big_rigid_pickuppable** - Large physics-based items
6. **small_rigid_pickuppable** - Small physics-based items
7. **static_body** - Non-moving obstacles
8. **water** - Water bodies

---

## Development Notes

### Project Structure
- All items are defined in `ItemConfig.Keys` enum and mapped to resources
- Scene files use `.tscn` extension, scripts use `.gd`
- Audio files in `audio/` with separate music and SFX folders
- 3D models and textures in `meshes/` and `textures/`
- The game uses a day/night cycle system

### Third-Party Addons

**Proton Scatter** (`addons/proton_scatter/`)
- Used for procedural placement of foliage and environmental objects
- Provides modifier-based scattering system
- Includes various creation and transformation modifiers

### Development Commands
Since this is a Godot project, development is primarily done through the Godot editor rather than command line tools.

**Engine**: Godot 4.4 (Forward Plus rendering)
**Main Scene**: `res://game/main_game.tscn`
**Project Config**: `project.godot` contains input maps and layer configurations

---

## File Statistics by Category

| Category | GDScript | Scenes | Resources | Total |
|----------|----------|--------|-----------|-------|
| Player/Actors | 5 | 5 | 0 | 10 |
| Interactables | 4 | 15+ | 0 | 19+ |
| Items/Equippables | 5 | 15+ | 35 | 55+ |
| Objects/Hittables | 2 | 10+ | 3 | 15+ |
| Managers | 12 | 1 | 0 | 13 |
| UI/Bulletins | 8 | 10+ | 1 | 19+ |
| Configs | 6 | 0 | 0 | 6 |
| Stages | 4 | 3 | 0 | 7 |
| **TOTAL** | **46** | **58** | **39** | **143** |

---

## Credits

This project was created following the Godot course by [Eerik Hirvonen](https://www.udemy.com/user/eerik-hirvonen/).

**Engine**: Godot 4.4
**License**: Educational project
