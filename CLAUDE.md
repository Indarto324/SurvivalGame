# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a 3D survival game built in Godot 4.4 following a course by Eerik Hirvonen. The game features resource gathering, crafting, construction, and survival mechanics on an island setting.

## Development Commands

Since this is a Godot project, development is primarily done through the Godot editor rather than command line tools. The project uses:

- **Engine**: Godot 4.4 (Forward Plus rendering)
- **Main Scene**: `res://game/main_game.tscn`
- **Project Config**: `project.godot` contains input maps and layer configurations

## Code Architecture

### Signal-Based Event System
The game uses a centralized event system (`game/event_system.gd`) that acts as a global autoload. All major game systems communicate through signals with specific prefixes:
- `BUL_*` - Bulletin/UI system
- `INV_*` - Inventory system
- `PLA_*` - Player actions and stats
- `EQU_*` - Equipment system
- `SFX_*` - Sound effects
- `MUS_*` - Music system
- `STA_*` - Stage/scene management

### Core Systems

**Player System** (`actors/player/`)
- `Player` class handles movement, input, and basic interactions
- Uses `InteractionRayCast` for object interaction
- `ItemHolder` manages equipped items

**Inventory System** (`game/managers/inventory_manager.gd`)
- Fixed-size inventory (28 slots) and hotbar (9 slots)
- Uses `ItemConfig.Keys` enum for item identification
- Supports drag-and-drop between inventory and hotbar

**Item System** (`game/configs/item_config.gd`)
- Central configuration for all items using enum-based keys
- Separates pickuppable, equippable, craftable, and constructable items
- Maps item keys to their respective resource files and scenes

**Crafting System** (`resources/crafting_blueprints/`)
- Blueprint-based crafting with cost requirements
- Some items require tools (multitool, tinderbox)
- Managed through dedicated UI systems

**Interactable System** (`interactables/`)
- Base `Interactable` class for all interactive objects
- Includes pickuppables, hittable objects, and constructables
- Uses Area3D for interaction detection

### Manager Pattern
Game uses multiple manager classes in `game/managers/`:
- `InventoryManager` - Item storage and manipulation
- `EquippedItemManager` - Currently held items
- `PlayerStatsManager` - Health, energy tracking
- `BulletinController` - UI state management
- `SFXController` - Audio management
- `StageController` - Scene transitions

### UI System (`bulletins/`)
The game uses a "bulletin" system for UI management:
- `BulletinController` creates/destroys UI panels
- Player menus inherit from `PlayerMenuBase`
- Includes crafting, cooking, settings, and pause menus

### Physics Layers
Defined in `project.godot`:
1. ground
2. actor  
3. interactable
4. hitbox
5. big_rigid_pickuppable
6. small_rigid_pickuppable
7. static_body
8. water

## Third-Party Addons

**Proton Scatter** (`addons/proton_scatter/`)
- Used for procedural placement of foliage and environmental objects
- Provides modifier-based scattering system
- Includes various creation and transformation modifiers

## Development Notes

- All items are defined in `ItemConfig.Keys` enum and mapped to resources
- Scene files use `.tscn` extension, scripts use `.gd`
- Audio files are in `audio/` with separate music and SFX folders
- 3D models and textures are in `meshes/` and `textures/`
- The game uses a day/night cycle system
- Player stats include energy consumption for movement
- Construction system allows building tents, campfires, and rafts