extends "res://tests/sprint_001.gd"

var weapon_hits := 0

func run() -> void:
	game = load("res://game/main_game.tscn").instantiate()
	add_child(game)
	controller = game.get_node("StageController")
	if not await wait_for_stage("res://stages/main_menu/main_menu.tscn"):
		check(false, "main menu loading")
		finish()
		return
	controller.get_child(0)._on_start_button_pressed()
	if not await wait_for_stage("res://stages/island/island.tscn"):
		check(false, "island loading")
		finish()
		return
	var island = controller.get_child(0)
	var player: Player = island.get_node("Actors/Player")
	var rig: MainCamera = player.camera_rig
	var inventory: InventoryManager = player.get_node("Managers/InventoryManager")
	var stats: PlayerStatsManager = player.get_node("Managers/PlayerStatsManager")
	check(player.find_children("*", "Camera3D", true, false).size() == 1, "exactly one player camera")
	check(player.find_children("*", "SubViewport", true, false).is_empty(), "no equipment overlay viewport")
	check(player.character_visuals.get_child_count() == 7, "original primitive character has seven visible parts")
	for mesh in player.character_visuals.get_children():
		check(mesh.mesh is PrimitiveMesh and mesh.visible, "placeholder uses a visible Godot primitive")
	check(is_equal_approx(rig.follow_distance, 4.0), "default follow distance is four meters")
	# A flat arena preserves shipped player scripts while isolating random scenery.
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/kawanan-sprint002.png")
	var floor_body := obstacle(Vector3(100, 2, 100), Vector3(500, 98, 0))
	island.add_child(floor_body)
	player.global_position = Vector3(500, 101, 0)
	player.velocity = Vector3.ZERO
	await physics_frames(90)
	player.set_physics_process(false)
	player.set_process(false)
	rig.target_yaw = 0
	rig.rotation.y = 0
	var root_yaw := player.rotation.y
	player.look_around(Vector2(-200, 0))
	check(is_zero_approx(rig.rotation.y), "mouse input sets a target without snapping camera")
	await physics_frames(6)
	check(rig.rotation.y > 0 and rig.rotation.y < rig.target_yaw, "camera rotation smoothly approaches target")
	check(is_equal_approx(player.rotation.y, root_yaw), "orbiting does not rotate the collision body")
	player.look_around(Vector2(0, 100000))
	check(is_equal_approx(rig.target_pitch, rig.minimum_pitch), "lower pitch target clamps")
	await physics_frames(30)
	check(rig.rotation.x >= rig.minimum_pitch and rig.rotation.x <= rig.maximum_pitch, "smoothed pitch stays inside limits")
	player.look_around(Vector2(0, -100000))
	check(is_equal_approx(rig.target_pitch, rig.maximum_pitch), "upper pitch target clamps")
	rig.zoom(100)
	check(rig.follow_distance == 8, "zoom out clamps at eight meters")
	rig.zoom(-100)
	check(rig.follow_distance == 1.5, "zoom in clamps at one and a half meters")
	rig.follow_distance = 4
	rig.target_yaw = 0
	rig.target_pitch = 0
	rig.rotation = Vector3.ZERO
	rig.spring_arm.spring_length = 4
	await physics_frames(10)
	check(rig.spring_arm.get_hit_length() > 3.8, "camera excludes player collider")
	var wall := obstacle(Vector3(5, 5, 0.3), player.global_position + Vector3(0, 1, 2))
	island.add_child(wall)
	await physics_frames(6)
	check(rig.spring_arm.get_hit_length() < 2, "sphere spring arm retracts before a wall")
	wall.queue_free()
	await physics_frames(6)
	check(rig.spring_arm.get_hit_length() > 3.8, "camera restores follow distance after obstruction clears")
	rig.rotation.y = PI / 2
	rig.target_yaw = PI / 2
	player.set_physics_process(true)
	var origin := player.global_position
	Input.action_press("move_forward")
	await physics_frames(30)
	Input.action_release("move_forward")
	check(player.global_position.x < origin.x - 1 and absf(player.global_position.z - origin.z) < 0.2, "forward movement follows camera yaw")
	check((-player.character_visuals.global_basis.z).dot(Vector3.LEFT) > 0.98, "character turns toward movement")
	check(stats.current_energy < 100, "camera-relative movement consumes energy")
	player.rotation.y = PI / 4
	origin = player.global_position
	var expected_forward := -rig.global_basis.z
	expected_forward.y = 0
	Input.action_press("move_forward")
	await physics_frames(30)
	Input.action_release("move_forward")
	var actual_direction := (player.global_position - origin).normalized()
	check(actual_direction.dot(expected_forward.normalized()) > 0.98, "camera-relative movement supports rotated player spawns")
	check((-player.character_visuals.global_basis.z).dot(expected_forward.normalized()) > 0.98, "character facing supports rotated player spawns")
	player.rotation.y = 0
	player.set_freeze(true)
	var yaw_target := rig.target_yaw
	var distance_target := rig.follow_distance
	player.look_around(Vector2(200, 200))
	rig.zoom(1)
	check(rig.target_yaw == yaw_target and rig.follow_distance == distance_target, "menus freeze camera controls")
	player.set_freeze(false)
	player.set_process(false)
	player.set_physics_process(false)
	player.global_position = Vector3(500, 100, 0)
	player.velocity = Vector3.ZERO
	rig.target_yaw = 0
	rig.target_pitch = 0
	rig.rotation = Vector3.ZERO
	player.character_visuals.rotation = Vector3.ZERO
	player.equipment_pivot.rotation = Vector3.ZERO
	await physics_frames(6)
	var pickup = load("res://interactables/pickuppables/pickuppable_stick.tscn").instantiate()
	island.add_child(pickup)
	pickup.global_position = player.global_position + Vector3(0, 0.65, -1.5)
	await physics_frames(3)
	var ray: InteractionRayCast = player.interaction_ray_cast
	ray.check_interaction()
	check(ray.current_interactable == pickup.get_node("Pickuppable"), "camera aim resolves a nearby real pickup")
	Input.action_press("interact")
	player.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release("interact")
	player.set_process(false)
	await get_tree().process_frame
	check(inventory.inventory.has(ItemConfig.Keys.Stick), "E interaction collects real item into inventory")
	ray.check_interaction()
	check(not ray.prompt_visible, "destroyed target clears interaction prompt")
	var distant := target_area(player.global_position + Vector3(0, 0.65, -4))
	island.add_child(distant)
	await physics_frames(3)
	ray.check_interaction()
	check(ray.current_interactable == null, "camera distance cannot extend player pickup reach")
	distant.position.z = -1.7
	await physics_frames(3)
	ray.check_interaction()
	check(ray.current_interactable == distant, "within-reach target is selected")
	var blocker := obstacle(Vector3(3, 3, 0.3), player.global_position + Vector3(0, 0.5, -0.8))
	island.add_child(blocker)
	await physics_frames(3)
	ray.check_interaction()
	check(ray.current_interactable == null and not ray.prompt_visible, "solid wall blocks interaction and clears prompt")
	blocker.queue_free()
	distant.queue_free()
	await physics_frames(3)
	# Exercise the same animation callbacks as left-click, in the world holder.
	inventory.add_item_by_index(ItemConfig.Keys.Axe, 0, true)
	EventSystem.EQU_hotkey_pressed.emit(1)
	var weapon: EquippableWeapon = player.item_holder.current_item_scene
	check(weapon != null and weapon.get_viewport() == player.get_viewport(), "weapon shares the world viewport")
	check(weapon.get_node("MeshHolder").get_child(0).layers == 1, "weapon mesh uses the world visual layer")
	var hitbox := Hitbox.new()
	hitbox.collision_layer = 8
	hitbox.collision_mask = 0
	var hit_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	hit_shape.shape = sphere
	hitbox.add_child(hit_shape)
	island.add_child(hitbox)
	hitbox.global_position = player.equipment_pivot.global_position + Vector3(0, 0, -1)
	hitbox.register_hit.connect(func(_resource): weapon_hits += 1)
	await physics_frames(3)
	var energy_before := stats.current_energy
	player.item_holder.try_to_use_item()
	await get_tree().create_timer(1.0).timeout
	check(weapon_hits == 1, "weapon use animation hits from world-space holder")
	check(stats.current_energy < energy_before, "weapon animation consumes energy")
	hitbox.queue_free()
	inventory.add_item_by_index(ItemConfig.Keys.Fruit, 1, true)
	EventSystem.EQU_hotkey_pressed.emit(2)
	await get_tree().process_frame
	check(player.item_holder.get_child_count() == 1, "switching equipment leaves one item instance")
	stats.change_health(-30)
	player.item_holder.try_to_use_item()
	await get_tree().create_timer(1.5).timeout
	check(inventory.hotbar[1] == null and stats.current_health == 90, "consumable animation restores health and removes item")
	inventory.add_item_by_index(ItemConfig.Keys.Campfire, 2, true)
	EventSystem.EQU_hotkey_pressed.emit(3)
	var build: EquippableConstructable = player.item_holder.current_item_scene
	rig.rotation = Vector3(-0.7, 0, 0)
	rig.target_pitch = -0.7
	rig.target_yaw = 0
	player.set_physics_process(true)
	await physics_frames(6)
	player.set_physics_process(false)
	# The preview updates in _process; several physics ticks may share one
	# rendered frame on a slow software renderer.
	var preview_started := Time.get_ticks_msec()
	while (not build.place_valid or build.constructable_area.global_position.distance_to(player.global_position) >= 3.5) and Time.get_ticks_msec() - preview_started < 5000:
		await get_tree().process_frame
	check(build.item_place_ray.is_colliding() and build.place_valid, "construction preview reaches ground from player instead of camera")
	check(build.constructable_area.global_position.distance_to(player.global_position) < 3.5, "construction preview remains near player")
	var spawner: Spawner = island.find_children("*", "Spawner", true, false)[0]
	var nav: NavigationRegion3D = island.get_node("NavigationRegion3D")
	var previous_nav_vertices := nav.navigation_mesh.get_vertices()
	var constructions_before: int = spawner.constructable_holder.get_child_count()
	player.item_holder.try_to_use_item()
	await get_tree().create_timer(1.5).timeout
	var bake_started := Time.get_ticks_msec()
	while nav.is_baking() and Time.get_ticks_msec() - bake_started < 20000:
		await get_tree().process_frame
	check(not nav.is_baking() and nav.navigation_mesh.get_vertices() != previous_nav_vertices and nav.navigation_mesh.get_polygon_count() > 0, "construction completes a nonempty navigation rebake")
	check(inventory.hotbar[2] == null, "building animation consumes equipped construction item")
	check(spawner.constructable_holder.get_child_count() == constructions_before + 1, "building animation creates a real campfire")
	controller.start_stage_change_sequence(StageConfig.Keys.Credits)
	check(await wait_for_stage("res://stages/credits/credits_stage.tscn"), "new player rig unloads cleanly on scene transition")
	finish()

func obstacle(size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	return body

func target_area(position: Vector3) -> Interactable:
	var area := Interactable.new()
	area.position = position
	area.collision_layer = 4
	area.collision_mask = 0
	var collider := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	collider.shape = sphere
	area.add_child(collider)
	return area

func finish() -> void:
	print("SPRINT 002: ", checks, " checks, ", failures, " failures")
	game.get_node("MusicController").stop()
	await get_tree().create_timer(0.25).timeout
	game.queue_free()
	await get_tree().create_timer(0.25).timeout
	get_tree().quit(0 if failures == 0 else 1)
