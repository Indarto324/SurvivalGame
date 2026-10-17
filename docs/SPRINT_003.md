# Sprint 003 — Android touch controls

Target branch: `kawanan-island`; `main` is unchanged. This sprint adds input and UI, not an APK, God Mode, new character art, or unrelated survival mechanics.

## Controls and input ownership

Touch controls enable automatically when `OS.has_feature("android")` is true. Desktop keyboard/mouse behavior remains the default elsewhere. `--touch-controls` enables the overlay/cursor policy for desktop development previews; it does not turn Linux into Android.

- Bottom-left analog joystick: movement relative to the third-person camera. A radial dead zone removes accidental small movement; magnitude controls walking/sprinting speed and the existing distance-based energy cost.
- Right-side open space: drag to orbit the camera, retaining Sprint 002 smoothing, pitch limits and collision avoidance.
- Right-side buttons: Jump, hold Sprint, Interact and Use. Interact and Use use the existing raycast and equipment/animation logic.
- Top buttons: Craft, Bag and Pause. Craft and Bag both open the existing combined inventory/crafting view, rather than introducing a separate inventory model.
- Bottom hotbar: tap any of the nine numbered item slots to equip/unequip it.

Each touch index owns one role until release/cancellation. A joystick finger, look finger and several action fingers can coexist. A second look/joystick finger cannot steal the first; fingers that begin on buttons cannot become camera drags. Multiple Sprint fingers are reference-counted. Touch state never calls `Input.action_press/release`, so releasing touch does not release a physical keyboard key. Input vectors are limited to unit length when keyboard and touch are combined.

Touch mode disables mouse-from-touch emulation. The touch router operates real menu buttons, toggles and horizontal sliders directly on press/release/drag, including while the scene tree is paused. This avoids a GUI tap becoming the desktop left-click Use action, and allows menu interactions from any finger index. Explicitly emulated mouse events are also ignored for camera/world item input. Mouse capture requests go through one platform-aware policy used by stage transitions, player entry, menu close and pause resume.

Menu entry, stage exit, application focus loss/backgrounding and safe-area changes cancel owned touches, queued world actions and selections. Jump and Interact pulses are consumed at their next gameplay poll even when jumping is unavailable or no target is present; they cannot remain queued for an unrelated later action. New player sessions reset frozen touch state after death. Pause→Exit also unpauses the scene tree before loading the menu, so a subsequent game can run. A drag from an old/canceled finger cannot restart movement or rotation without a new press.

## Inventory, crafting and equipment

In touch mode the existing inventory menu adds a nine-slot hotbar row. Tap an occupied inventory slot to select it (cyan tint and item information), then a valid destination to move/swap it. Tap the selected slot again to cancel. The existing slot validators and inventory signals still perform the transfer, including cooking source/result and scrap slots; non-equippable items cannot be moved into the hotbar and active cooking ingredients cannot be removed. Desktop drag-and-drop is retained. The existing cooking-recipe field typo in the reverse inventory/cooking drop check is corrected.

Craft buttons retain recipe cost/tool checks and display information on touch, including disabled recipes. Native Close, Pause/Resume, Settings buttons and sliders have explicit touch routing and larger mobile hit targets. Closing menus restores touch controls without capturing an Android pointer. A menu touch never queues a world interaction or item use.

## Responsive layout and cost

The control layout uses viewport coordinates and `DisplayServer.get_display_safe_area()` transformed through the inverse viewport screen transform. It intersects that rectangle with the visible viewport, keeping controls outside reported cutouts and system insets. Viewport resize refits controls and registered menus. Android safe-area changes are also checked at 2 Hz, including while paused. Old menu entries are pruned safely by index.

The world hotbar is replaced by larger touch targets in touch mode, while health/energy move to the safe top-left and hide during inventory menus so they cannot cover item slots. Touch buttons and the joystick occupy separate bottom regions, with camera drag space above them. Menu content is uniformly fitted into the safe landscape rectangle using the existing 1920×1080 UI; inventory slots remain 96 logical units and mobile Close buttons have a larger minimum size. Layout is tested for standard/wide phone and tablet aspect ratios. Actual density, cutouts, accessibility and reachability still require device review.

The overlay draws native circles, cached style boxes, text and existing item icons. It redraws on state/layout changes instead of rebuilding nodes every frame. GUI controls register once per menu; event routing uses groups on touch-down rather than walking the 3D scene each frame. No external art, UI package or plugin is introduced.

Project settings request landscape orientation, retain desktop rendering, and select Godot's Mobile rendering method through the `.mobile` override. The next export stage must determine the supported Android/Vulkan device baseline; this sprint does not establish support for every Android GPU or add an OpenGL fallback.

## Reproduce validation

```bash
# Published Godot 4.4 environment; runs all three suites.
XDG_CACHE_HOME=/workspace/.cache \
XDG_DATA_HOME=/workspace/.local/share \
XDG_CONFIG_HOME=/workspace/.config \
GODOT_BIN=/workspace/tools/godot-4.4/Godot_v4.4-stable_linux.x86_64 \
bash tests/run.sh

# Linux software-Vulkan Mobile renderer and optional local screenshot.
timeout --kill-after=10 240 bash /workspace/tools/survivalgame/run.sh \
  --rendering-method mobile --resolution 1280x720 \
  res://tests/sprint_003.tscn -- --capture

# Refresh editor imports / project validation.
bash /workspace/tools/survivalgame/run.sh --editor --import
```

The Sprint 003 fixture pushes real `InputEventScreenTouch` and `InputEventScreenDrag` events through the viewport with coordinates already in viewport space. This matches the coordinates received by `_input` after Godot's screen/stretch conversion; it does not claim an Android OS input driver was exercised. The fixture checks the physical-to-logical safe-area conversion separately. Sprints 001 and 002 remain unchanged and run with normal desktop input.

## Recorded validation results

Godot **4.4.stable.official.4c311cbee**, Linux x86_64, 2026-10-17:

| Check | Result |
| --- | --- |
| Shared headless runner, default desktop mode for prior suites | Sprint 001 **59/59**, Sprint 002 **46/46**, Sprint 003 **60/60**; exit 0; no engine/script errors or warnings. |
| Mobile rendering method, software Vulkan / Mesa llvmpipe, private Xvfb, 1280×720 | Sprint 003 **60/60**, exit 0; no engine/script errors or warnings. This is Linux Mobile-renderer evidence, not Android device evidence. |
| Final Godot editor import/project scan | Exit 0; no engine/script errors or warnings. |
| Shell syntax and `git diff --check` | Passed. |

The new suite exercises raw viewport touch/drag dispatch, real main-menu Start, proportional camera-relative movement/energy, joystick/look/Sprint/Jump simultaneously, independent release/cancellation, multiple Sprint fingers, button-to-camera conflict isolation, focus/resize cleanup, simulated safe areas and non-overlapping controls across three aspect ratios, physical-to-logical safe-area conversion, raw inventory/hotbar transfers and refusal of invalid equipment, real crafting, emulated mouse rejection, consumable animation/use, real world pickup via Interact, Craft/Bag menu routing, paused Settings and slider dragging, Close/Resume, Pause→Exit→new game, death→new game and clean stage transitions. Existing Sprint 001/002 tests are unchanged.

Inspected local captures:

- `/tmp/kawanan-sprint003.png` — landscape gameplay with joystick, action buttons, all nine hotbar targets, safe top status bars and the third-person character.
- `/tmp/kawanan-sprint003-inventory.png` — selected item, inventory/crafting panels, large Close control and touch transfer hotbar. Mobile status bars are hidden here to prevent inventory overlap.

These frames verify the displayed layout at one desktop-rendered resolution, not touch feel or physical-device ergonomics. The captures are local test artifacts and are not added as game assets.

## Modified and added files

- `README.md` — link to the touch controls and validation report.
- `ui/mobile/mobile_input.gd` — mobile input/cursor policy, finger ownership, lightweight overlay, safe-area layout, native GUI routing, inventory tap selection and cleanup.
- `ui/mobile/mobile_input.gd.uid` — Godot script UID.
- `actors/player/player.gd` — analog movement magnitude, action adapter, emulated-mouse guard and new-session reset.
- `actors/player/interaction_ray_cast.gd` — consume touch Interact at the current poll rather than storing a stale request.
- `game/managers/stage_controller.gd` — platform-aware cursor policy.
- `game/managers/hud_controller.gd` — mobile hotbar/status layout and inventory overlap prevention.
- `stages/main_menu/main_menu.gd` — register/fit touchable main-menu controls.
- `bulletins/fading_bulletin/fading_bulletin.gd` — safe-area fitting and touch registration for Pause/Settings.
- `bulletins/pause_menu/pause_menu.gd` — cursor policy and unpause on exit.
- `bulletins/player_menus/player_menu_base.gd` — prepare touch inventory/hotbar UI and restore cursor policy on close.
- `bulletins/player_menus/cooking_menu/cooking_menu.gd` — touch-safe cursor policy on close.
- `ui/custom_nodes/inventory_slot.gd` — register transfer targets and correct the existing cooking-recipe property reference.
- `ui/custom_nodes/scrap_item_slot.gd` — register the existing scrap transfer target.
- `ui/custom_nodes/craft_button.gd` — show recipe information on touch.
- `project.godot` — mobile input autoload, landscape orientation, explicit pointer-emulation defaults and Mobile renderer override.
- `tests/run.sh` — run and validate all three suites.
- `tests/sprint_003.gd` — touch integration/physics/UI/lifecycle regressions and optional captures.
- `tests/sprint_003.gd.uid` — Godot test script UID.
- `tests/sprint_003.tscn` — regression scene.
- `docs/SPRINT_003.md` — controls, design, validation, file inventory and limitations.


## Remaining limitations and next export stage

- **No physical Android device, Android emulator, APK export/install, SDK/signing or store validation was performed.** No Android build tools were found on the published command path. Linux headless/Mobile-renderer results are not physical-device evidence.
- Device DPI, actual cutout/system-bar reports, Android lifecycle delivery, touch sampling, OEM gestures, thermal behavior and sustained frame rate require real device testing. Touch target dimensions scale with the viewport height; accessibility and handedness tuning are not yet settings.
- The desktop `--touch-controls` preview displays touch UI and keeps the pointer visible; synthetic touch events or a touch-capable display exercise the controls. It is not a mouse-to-multitouch emulator.
- Inventory uses tap-to-select/tap-to-move, not a new touch drag/drop implementation. Craft and Bag intentionally share the existing combined screen. Horizontal sliders are supported; there is no new text-entry, scrolling or hardware Android Back navigation system in this sprint.
- The Sprint 002 static primitive character and inherited item posing/animation limitations remain. Existing source and asset licensing limitations remain in `LICENSING_REVIEW.md`.
- Before APK export, configure the Android package ID, SDK/JDK/templates matching Godot 4.4, signing, permissions and device/GPU baseline. Profile the existing procedural scatter, navigation rebakes and rendering on hardware. No claim of APK readiness beyond the implemented touch-control foundation is made.
