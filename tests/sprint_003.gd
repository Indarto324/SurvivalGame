extends "res://tests/sprint_001.gd"

func touch(index: int, point: Vector2, down: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = down
	event.canceled = canceled
	get_viewport().push_input(event, true)

func drag(index: int, point: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	event.relative = relative
	get_viewport().push_input(event, true)

func center(key: String) -> Vector2:
	return MobileInput.buttons[key].get_center()

func tap_control(control: Control, index := 12) -> void:
	var point := control.get_global_transform_with_canvas() * (control.size / 2)
	touch(index, point, true)
	touch(index, point, false)

func run() -> void:
	MobileInput.configure_enabled(true)
	game = load("res://game/main_game.tscn").instantiate()
	add_child(game)
	controller = game.get_node("StageController")
	var ready := await wait_for_stage("res://stages/main_menu/main_menu.tscn")
	check(ready, "mobile main menu loads")
	if not ready:
		finish()
		return
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "touch mode never captures mouse on menu transition")
	check(not Input.emulate_mouse_from_touch, "touch UI does not synthesize left clicks")
	var start_button = controller.get_child(0).find_child("StartButton", true, false)
	tap_control(start_button)
	ready = await wait_for_stage("res://stages/island/island.tscn")
	check(ready, "raw touch starts game through the real menu button")
	if not ready:
		finish()
		return
	var island = controller.get_child(0)
	var player: Player = island.get_node("Actors/Player")
	var inventory: InventoryManager = player.get_node("Managers/InventoryManager")
	var stats: PlayerStatsManager = player.get_node("Managers/PlayerStatsManager")
	check(MobileInput.can_control(), "touch gameplay controls enabled on island")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "player entry leaves Android-style pointer uncaptured")
	# Validate safe rectangles for 16:9, wide phone, and tablet layouts.
	for area in [Rect2(40, 20, 1200, 680), Rect2(60, 24, 2280, 1032), Rect2(24, 24, 1392, 1032)]:
		MobileInput.configure_layout(area)
		var contained := true
		for rect in MobileInput.buttons.values():
			contained = contained and area.encloses(rect)
		var nonoverlapping := true
		var rectangles := MobileInput.buttons.values()
		for first in rectangles.size():
			for second in range(first + 1, rectangles.size()):
				nonoverlapping = nonoverlapping and not rectangles[first].intersects(rectangles[second])
		check(nonoverlapping, "touch buttons do not overlap at this aspect ratio")
		check(contained, "all touch buttons remain inside simulated safe area %s" % area.size)
		var joystick := Rect2(MobileInput.joystick_center - Vector2.ONE*MobileInput.joystick_radius, Vector2.ONE*MobileInput.joystick_radius*2)
		check(area.encloses(joystick), "joystick stays outside simulated cutouts")
	var transformed: Rect2 = MobileInput.logical_safe_rect(Rect2(40, 20, 1200, 680), Transform2D(Vector2(2.0/3, 0), Vector2(0, 2.0/3), Vector2.ZERO), Rect2(0, 0, 1920, 1080))
	check(transformed.position.is_equal_approx(Vector2(60, 30)) and transformed.size.is_equal_approx(Vector2(1800, 1020)), "physical safe area maps into stretched viewport coordinates")
	MobileInput.refresh_layout()
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/kawanan-sprint003.png")
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 2, 100)
	collision.shape = box
	floor_body.add_child(collision)
	island.add_child(floor_body)
	floor_body.position = Vector3(500, 98, 0)
	player.global_position = Vector3(500, 101, 0)
	player.velocity = Vector3.ZERO
	player.camera_rig.target_yaw = PI / 2
	player.camera_rig.rotation.y = PI / 2
	await physics_frames(90)
	var origin := player.global_position
	var stick: Vector2 = MobileInput.joystick_center
	var look := MobileInput.safe_rect.position + MobileInput.safe_rect.size * Vector2(0.75, 0.4)
	touch(0, stick, true)
	drag(0, stick + Vector2(0, -MobileInput.joystick_radius*0.55), Vector2(0, -40))
	check(MobileInput.movement.length() > 0.4 and MobileInput.movement.length() < 0.6, "joystick retains analog magnitude after dead zone")
	await physics_frames(30)
	var distance := player.global_position.distance_to(origin)
	check(distance > 0.4 and distance < 1.0 and player.global_position.x < origin.x, "analog movement is proportional and camera-relative")
	check(stats.current_energy < 100, "touch movement consumes survival energy")
	touch(1, look, true)
	var yaw := player.camera_rig.target_yaw
	drag(1, look + Vector2(60, 0), Vector2(60, 0))
	check(player.camera_rig.target_yaw != yaw and MobileInput.move_finger == 0, "second finger rotates camera without stealing joystick")
	touch(2, center("sprint"), true)
	await physics_frames(2)
	check(player.is_sprinting and MobileInput.look_finger == 1, "sprint, movement and look coexist")
	touch(3, center("jump"), true)
	await physics_frames(2)
	check(player.velocity.y > 0, "fourth finger triggers jump while moving/sprinting/looking")
	touch(3, center("jump"), false)
	touch(18, center("jump"), true)
	touch(18, center("jump"), false)
	await physics_frames(2)
	check(not MobileInput.pending.has("jump"), "midair jump press does not remain queued until landing")
	touch(2, center("sprint"), false)
	check(not MobileInput.pressed("sprint") and MobileInput.move_finger == 0, "sprint release preserves movement finger")
	touch(1, look, false)
	check(MobileInput.look_finger == -1 and MobileInput.movement.length() > 0, "camera release preserves movement")
	touch(0, stick, false, true)
	check(MobileInput.movement == Vector2.ZERO and MobileInput.fingers.is_empty(), "canceled joystick clears all owned movement")
	# Multiple fingers may hold the same action without releasing one another.
	touch(4, center("sprint"), true)
	touch(5, center("sprint"), true)
	touch(4, center("sprint"), false)
	check(MobileInput.pressed("sprint"), "one sprint finger can release while another remains held")
	touch(5, center("sprint"), false)
	var target_yaw := player.camera_rig.target_yaw
	touch(6, center("use_equipped_item"), true)
	drag(6, look, Vector2(120, 0))
	check(player.camera_rig.target_yaw == target_yaw, "dragging from an action button cannot rotate the camera")
	touch(6, look, false)
	MobileInput.release_all()
	touch(7, stick, true)
	MobileInput._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(MobileInput.movement == Vector2.ZERO and MobileInput.fingers.is_empty(), "focus loss clears touch ownership and queued actions")
	touch(17, stick, true)
	var old_safe: Rect2 = MobileInput.safe_rect
	MobileInput.configure_layout(old_safe.grow(-8))
	check(MobileInput.fingers.is_empty() and MobileInput.movement == Vector2.ZERO, "safe-area changes cancel stale touch coordinates")
	MobileInput.refresh_layout()
	touch(19, center("interact"), true)
	touch(19, center("interact"), false)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not MobileInput.pending.has("interact"), "Interact with no target cannot trigger a later remote pickup")
	# Open the original combined inventory/crafting menu via its mobile button.
	touch(8, center("inventory"), true)
	var bulletins = game.get_node("UILayer/BulletinController")
	check(bulletins.bulletins.has(BulletinConfig.Keys.CraftingMenu), "Bag opens the real inventory/crafting menu")
	var menu: CraftingMenu = bulletins.bulletins[BulletinConfig.Keys.CraftingMenu]
	await get_tree().process_frame
	check(not MobileInput.can_control() and not player.is_physics_processing(), "menu entry freezes world controls and clears fingers")
	var mobile_stats = game.get_node("UILayer/HUDController/HUD").find_child("PlayerStatsContainer", true, false)
	check(not mobile_stats.visible, "mobile stat bars cannot cover inventory touch slots")
	check(not MobileInput.just_pressed("use_equipped_item"), "menu touch cannot activate a world item")
	var slot0 = menu.inventory_slot_container.get_child(0)
	inventory.inventory.fill(null)
	inventory.add_item(ItemConfig.Keys.Fruit)
	tap_control(slot0)
	check(MobileInput.selected_slot == slot0, "touch selects inventory item without dragging")
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/kawanan-sprint003-inventory.png")
	var mobile_bar = menu.get_child(menu.get_child_count()-1)
	var hotbar_slot = mobile_bar.get_child(0)
	tap_control(hotbar_slot)
	check(inventory.hotbar[0] == ItemConfig.Keys.Fruit and inventory.inventory[0] == null, "second slot tap moves item into hotbar through existing validation")
	inventory.add_item(ItemConfig.Keys.Stick)
	tap_control(slot0)
	tap_control(mobile_bar.get_child(1))
	check(inventory.hotbar[1] == null, "touch cannot equip a non-equippable inventory item")
	MobileInput.clear_selection()
	inventory.inventory.fill(null)
	inventory.add_item(ItemConfig.Keys.Plant)
	inventory.add_item(ItemConfig.Keys.Plant)
	var rope = craft_button(menu, ItemConfig.Keys.Rope)
	tap_control(rope)
	check(inventory.inventory.has(ItemConfig.Keys.Rope) and not inventory.inventory.has(ItemConfig.Keys.Plant), "raw touch crafts once through native recipe button")
	tap_control(menu.find_child("CloseButton", true, false))
	await get_tree().process_frame
	check(MobileInput.can_control() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "touch close restores controls without mouse capture")
	check(mobile_stats.visible, "closing inventory restores mobile survival bars")
	# Touch selects equipment; GUI-emulated clicks must not consume it.
	touch(9, center("slot_0"), true)
	touch(9, center("slot_0"), false)
	check(player.item_holder.current_item_scene is EquippableConsumable, "touch hotbar selects equipment")
	var emulated := InputEventMouseButton.new()
	emulated.device = -1
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.pressed = true
	Input.parse_input_event(emulated)
	await physics_frames(2)
	check(inventory.hotbar[0] == ItemConfig.Keys.Fruit, "emulated GUI mouse click cannot use world equipment")
	emulated.pressed = false
	Input.parse_input_event(emulated)
	stats.change_health(-30)
	touch(10, center("use_equipped_item"), true)
	touch(10, center("use_equipped_item"), false)
	await get_tree().create_timer(1.5).timeout
	check(inventory.hotbar[0] == null and stats.current_health == 90, "Use touch runs real consumable animation and item removal")
	# Interact uses the existing camera-aim/reach query and a real pickup.
	player.camera_rig.target_yaw = 0
	player.camera_rig.target_pitch = 0
	player.camera_rig.rotation = Vector3.ZERO
	var pickup = load("res://interactables/pickuppables/pickuppable_stick.tscn").instantiate()
	island.add_child(pickup)
	pickup.global_position = player.global_position + Vector3(0, 0.65, -1.5)
	await physics_frames(4)
	touch(14, center("interact"), true)
	touch(14, center("interact"), false)
	await get_tree().process_frame
	await get_tree().process_frame
	check(inventory.inventory.has(ItemConfig.Keys.Stick), "Interact touch collects a real in-reach world item")
	touch(15, center("craft"), true)
	check(bulletins.bulletins.has(BulletinConfig.Keys.CraftingMenu), "Craft touch opens combined crafting/inventory view")
	var reopened = bulletins.bulletins[BulletinConfig.Keys.CraftingMenu]
	await get_tree().process_frame
	tap_control(reopened.find_child("CloseButton", true, false))
	await get_tree().process_frame
	MobileInput.refresh_layout()
	check(MobileInput.can_control(), "closed menus can be pruned and layout refreshed safely")
	touch(11, center("pause"), true)
	check(get_tree().paused and not MobileInput.can_control(), "Pause touch pauses gameplay and clears controls")
	var pause = bulletins.bulletins[BulletinConfig.Keys.PauseMenu]
	await get_tree().process_frame
	tap_control(pause.settings_button)
	await get_tree().create_timer(0.5).timeout
	check(bulletins.bulletins.has(BulletinConfig.Keys.SettingsMenu), "touch opens real settings while paused")
	var settings = bulletins.bulletins[BulletinConfig.Keys.SettingsMenu]
	var slider: HSlider = settings.music_volume_slider
	var old_volume := slider.value
	var slider_point := slider.get_global_transform_with_canvas() * Vector2(slider.size.x * 0.25, slider.size.y / 2)
	touch(16, slider_point, true)
	var slide_end := slider.get_global_transform_with_canvas() * Vector2(slider.size.x * 0.75, slider.size.y / 2)
	drag(16, slide_end, slide_end - slider_point)
	touch(16, slide_end, false)
	check(absf(slider.value - 0.75) < 0.02, "raw touch drag adjusts native settings slider")
	slider.value = old_volume
	tap_control(settings.find_child("CloseButton", true, false))
	await get_tree().create_timer(0.5).timeout
	pause = bulletins.bulletins[BulletinConfig.Keys.PauseMenu]
	tap_control(pause.resume_button)
	await get_tree().create_timer(0.5).timeout
	check(not get_tree().paused and MobileInput.can_control(), "touch Resume works while tree is paused")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "resume retains touch cursor policy")
	touch(20, center("pause"), true)
	var exit_pause = bulletins.bulletins[BulletinConfig.Keys.PauseMenu]
	await get_tree().process_frame
	tap_control(exit_pause.exit_button)
	check(await wait_for_stage("res://stages/main_menu/main_menu.tscn"), "touch Pause exit returns to main menu")
	check(not get_tree().paused, "Pause exit cannot leave the next game paused")
	tap_control(controller.get_child(0).find_child("StartButton", true, false))
	check(await wait_for_stage("res://stages/island/island.tscn"), "touch starts a new game after Pause exit")
	var new_player = controller.get_child(0).get_node("Actors/Player")
	new_player.get_node("Managers/PlayerStatsManager").change_health(-1000)
	check(await wait_for_stage("res://stages/main_menu/main_menu.tscn"), "touch session death returns to menu")
	tap_control(controller.get_child(0).find_child("StartButton", true, false))
	check(await wait_for_stage("res://stages/island/island.tscn"), "touch starts a new game after death")
	check(MobileInput.can_control() and MobileInput.fingers.is_empty(), "new player resets frozen touch state and ownership")
	controller.start_stage_change_sequence(StageConfig.Keys.Credits)
	check(await wait_for_stage("res://stages/credits/credits_stage.tscn"), "touch player unloads cleanly")
	check(MobileInput.fingers.is_empty() and MobileInput.movement == Vector2.ZERO, "stage exit releases all virtual inputs")
	finish()

func finish() -> void:
	print("SPRINT 003: ", checks, " checks, ", failures, " failures")
	game.get_node("MusicController").stop()
	await get_tree().create_timer(0.25).timeout
	game.queue_free()
	await get_tree().create_timer(0.25).timeout
	MobileInput.configure_enabled(false)
	get_tree().quit(0 if failures == 0 else 1)
