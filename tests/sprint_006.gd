extends "res://tests/sprint_005.gd"

var pickup_events := 0
var weapon_hits := 0
var hit_positions: Array[float] = []
var captures := {}
var capture_camera: Camera3D

func _process(_delta: float) -> void:
	if is_instance_valid(capture_camera) and is_instance_valid(player):
		capture_camera.global_position = player.global_position + Vector3(3, 1.3, -3)
		capture_camera.look_at(player.global_position + Vector3(0, 0.05, 0))

func capture_pose(key: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name() == "headless" or captures.has(key):
		return
	captures[key] = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/workspace/artifacts/kawanan-sprint006/" + key + ".png")

func run() -> void:
	MobileInput.configure_enabled(true)
	game = load("res://game/main_game.tscn").instantiate()
	add_child(game)
	controller = game.get_node("StageController")
	check(await wait_for_stage("res://stages/main_menu/main_menu.tscn"), "menu loads with animated player resources")
	tap_control(controller.get_child(0).find_child("StartButton", true, false))
	check(await wait_for_stage("res://stages/island/island.tscn"), "touch loads animated player on island")
	island = controller.get_child(0)
	player = island.get_node("Actors/Player")
	inventory = player.get_node("Managers/InventoryManager")
	bulletins = game.get_node("UILayer/BulletinController")
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 2, 100)
	collision.shape = box
	floor_body.add_child(collision)
	var floor_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.4, 0.32)
	mesh.material = material
	floor_mesh.mesh = mesh
	floor_body.add_child(floor_mesh)
	island.add_child(floor_body)
	floor_body.position = Vector3(500, 98, 0)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.8, -0.5, 0)
	light.light_energy = 1.5
	island.add_child(light)
	player.global_position = Vector3(500, 100, 0)
	player.velocity = Vector3.ZERO
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		# Test-only viewer for clearer limb/pose footage. The gameplay camera,
		# its aim, and all shipped scene resources remain unchanged.
		capture_camera = Camera3D.new()
		island.add_child(capture_camera)
		capture_camera.current = true
	await physics_frames(90)
	var animator: CharacterAnimator = player.character_visuals
	var capsule: CollisionShape3D = player.get_node("CollisionShape3D")
	var capsule_rest := capsule.transform
	var camera_rest := player.camera_rig.transform
	var equipment_rest := player.equipment_pivot.transform
	var torso: MeshInstance3D = animator.get_node("Torso")
	check(animator.locomotion_state == &"Idle", "stationary grounded character enters Idle")
	var torso_before := torso.transform
	var root_before := player.global_transform
	await physics_frames(20)
	check(not torso.transform.is_equal_approx(torso_before), "idle breathing changes primitive torso pose")
	check(player.global_transform.is_equal_approx(root_before), "idle animation cannot move player collision body")
	check(capsule.transform == capsule_rest and player.camera_rig.transform == camera_rest, "breathing cannot move camera rig or capsule")
	check(player.equipment_pivot.transform.is_equal_approx(equipment_rest), "breathing cannot alter equipment origin or aim")
	await capture_pose("idle")
	var stick: Vector2 = MobileInput.joystick_center
	touch(0, stick, true)
	drag(0, stick - Vector2(0, MobileInput.joystick_radius * 0.55), Vector2(0, -40))
	var origin := player.global_position
	var phase_before := animator.gait_phase
	await physics_frames(30)
	check(animator.locomotion_state == &"Walk" and animator.horizontal_speed > 1.0 and animator.horizontal_speed < 2.0, "analog movement drives Walk using actual speed")
	var measured := player.global_position.distance_to(origin)
	var phase_delta := fposmod(animator.gait_phase - phase_before, TAU)
	check(absf(phase_delta - measured * 2.8) < 0.12, "walking cadence is synchronized to actual distance traveled")
	check(animator.get_node("LeftLeg").rotation.x * animator.get_node("RightLeg").rotation.x < 0, "walking legs alternate around virtual hip pivots")
	check(animator.get_node("LeftArm").rotation.x * animator.get_node("LeftLeg").rotation.x < 0, "walking arms counter-swing against legs")
	await capture_pose("walk")
	drag(0, stick - Vector2(0, MobileInput.joystick_radius), Vector2(0, -40))
	touch(1, center("sprint"), true)
	await physics_frames(30)
	check(animator.locomotion_state == &"Sprint" and animator.horizontal_speed > 4.8, "actual running speed drives Sprint state")
	check(torso.rotation.x < -0.1, "sprint adds blended upper-body lean")
	await capture_pose("sprint")
	tap_action("jump")
	await physics_frames(2)
	check(animator.locomotion_state == &"Jump" and player.velocity.y > 0, "jump velocity drives takeoff and ascending pose")
	await capture_pose("jump")
	touch(0, stick, false)
	touch(1, center("sprint"), false)
	var seen := {}
	for frame in 120:
		await physics_frames(1)
		seen[animator.locomotion_state] = true
		if animator.locomotion_state == &"Fall":
			await capture_pose("fall")
		elif animator.locomotion_state == &"Landing":
			await capture_pose("landing")
	check(seen.has(&"Fall"), "descending velocity produces Fall state")
	check(seen.has(&"Landing"), "air-to-ground contact produces Landing transition")
	check(animator.locomotion_state == &"Idle", "landing compression blends back to Idle")
	check(capsule.transform == capsule_rest and player.camera_rig.transform == camera_rest, "jump/fall/landing only pose meshes, never camera or capsule")
	# Input can remain held while blocked: use measured velocity, not intent.
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(5, 4, 0.3)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	island.add_child(wall)
	wall.global_position = player.global_position + Vector3(0, 0, -0.7)
	touch(0, stick, true)
	drag(0, stick - Vector2(0, MobileInput.joystick_radius), Vector2(0, -80))
	await physics_frames(60)
	phase_before = animator.gait_phase
	await physics_frames(15)
	check(animator.locomotion_state == &"Idle" and animator.horizontal_speed < 0.08, "blocked movement is Idle despite held joystick")
	check(absf(animator.gait_phase - phase_before) < 0.001, "blocked player does not advance walk cycle")
	touch(0, stick, false)
	wall.queue_free()
	await physics_frames(4)
	EventSystem.PLA_pickup_collected.connect(func(): pickup_events += 1)
	await collect(ItemConfig.Keys.Stone)
	await physics_frames(2)
	check(pickup_events == 1 and animator.action_state == &"Pickup", "successful touch pickup emits one visual event and starts reach")
	await physics_frames(10)
	check(torso.rotation.x < -0.2, "pickup bends body toward ground resource")
	await capture_pose("pickup")
	await physics_frames(40)
	check(animator.action_state == &"None" and inventory.inventory.count(ItemConfig.Keys.Stone) == 1, "pickup animation finishes without duplicating collected item")
	var saved_inventory := inventory.inventory.duplicate()
	inventory.inventory.fill(ItemConfig.Keys.Stone)
	var uncollected := pickup_scene(ItemConfig.Keys.Fruit, Vector3(0.3, 0, -1.2))
	await physics_frames(4)
	await get_tree().process_frame
	tap_action("interact")
	await physics_frames(4)
	check(is_instance_valid(uncollected) and pickup_events == 1 and animator.pickup_remaining == 0, "full inventory neither collects resource nor plays a false pickup gesture")
	inventory.inventory = saved_inventory
	animator.begin_pickup()
	await physics_frames(12)
	check(is_instance_valid(uncollected) and inventory.inventory == saved_inventory and pickup_events == 1, "playing reach pose alone cannot collect any item or emit pickup events")
	uncollected.queue_free()
	await physics_frames(40)
	inventory.add_item_by_index(ItemConfig.Keys.Axe, 0, true)
	tap_action("slot_0")
	var weapon: EquippableWeapon = player.item_holder.current_item_scene
	var hitbox := Hitbox.new()
	hitbox.collision_layer = 8
	hitbox.collision_mask = 0
	var hit_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	hit_shape.shape = sphere
	hitbox.add_child(hit_shape)
	island.add_child(hitbox)
	hitbox.global_position = player.equipment_pivot.global_position - player.equipment_pivot.global_basis.z
	hitbox.register_hit.connect(func(_resource):
		weapon_hits += 1
		hit_positions.append(player.item_holder.current_item_scene.animation_player.current_animation_position))
	await physics_frames(4)
	var stats: PlayerStatsManager = player.get_node("Managers/PlayerStatsManager")
	var energy_before := stats.current_energy
	tap_action("use_equipped_item")
	await physics_frames(2)
	check(animator.action_state == &"Chop", "Use starts character Chop only when equipment clip plays")
	check(is_equal_approx(animator.tool_hit_time, 0.2), "character reads original axe hit key time without modifying it")
	check(absf(animator.tool_sample_time - weapon.animation_player.current_animation_position) < 0.12, "body action samples actual equipment playback time")
	var before_hits := weapon_hits
	for n in 20:
		animator.advance(1.0/60.0, Vector3.ZERO, true, false, player.normal_speed)
	check(weapon_hits == before_hits, "repeated character posing cannot invoke hit callbacks")
	player.item_holder.try_to_use_item()
	player.item_holder.try_to_use_item()
	await get_tree().create_timer(0.12).timeout
	await capture_pose("chop")
	await get_tree().create_timer(0.8).timeout
	check(weapon_hits == 1, "repeated Use during active clip still produces exactly one hit")
	check(hit_positions.size() == 1 and hit_positions[0] >= 0.19, "weapon hit does not occur before original 0.2 second key")
	check(is_equal_approx(stats.current_energy, energy_before - 0.5), "one axe use consumes original energy exactly once")
	check(inventory.hotbar[0] == ItemConfig.Keys.Axe, "chop pose never consumes harvesting tool")
	check(animator.action_state == &"None", "body action blends out after equipment clip finishes")
	await get_tree().create_timer(0.5).timeout
	check(weapon_hits == 1, "idle blending cannot generate extra damage events")
	inventory.add_item_by_index(ItemConfig.Keys.Pickaxe, 1, true)
	tap_action("slot_1")
	await physics_frames(4)
	energy_before = stats.current_energy
	tap_action("use_equipped_item")
	await physics_frames(2)
	check(animator.action_state == &"Chop", "pickaxe uses the same equipment-driven body action")
	await get_tree().create_timer(0.9).timeout
	check(weapon_hits == 2, "pickaxe preserves exactly one original hit event")
	var pickaxe_resource := ItemConfig.get_item_resource(ItemConfig.Keys.Pickaxe) as WeaponItemResource
	check(is_equal_approx(stats.current_energy, energy_before + pickaxe_resource.energy_change_per_use), "pickaxe keeps its original energy cost exactly once")
	check(inventory.hotbar[1] == ItemConfig.Keys.Pickaxe, "body action cannot consume pickaxe")
	hitbox.queue_free()
	# Sample abrupt state changes at a fixed animation step. Transforms must
	# blend rather than snap even when motion/action targets change instantly.
	var maximum_angle := 0.0
	var maximum_distance := 0.0
	for frame in 80:
		var poses: Array[Transform3D] = []
		for part in animator.meshes:
			poses.append(part.transform)
		var grounded := frame < 30 or frame >= 60
		var velocity_sample := Vector3(0, 4 if frame < 45 else -4, -5)
		animator.advance(1.0/60.0, velocity_sample, grounded, frame < 30, player.normal_speed)
		for index in animator.meshes.size():
			var pose: Transform3D = animator.meshes[index].transform
			maximum_angle = maxf(maximum_angle, pose.basis.get_rotation_quaternion().angle_to(poses[index].basis.get_rotation_quaternion()))
			maximum_distance = maxf(maximum_distance, pose.origin.distance_to(poses[index].origin))
	check(maximum_angle < 0.55 and maximum_distance < 0.25, "abrupt locomotion state changes blend mesh poses without frame-sized snaps")
	await physics_frames(30)
	# Menus pause poses with the existing player freeze mechanism.
	player.set_freeze(true)
	var frozen_pose := torso.transform
	phase_before = animator.gait_phase
	await physics_frames(15)
	check(torso.transform == frozen_pose and animator.gait_phase == phase_before, "player freeze suspends procedural animation")
	player.set_freeze(false)
	await physics_frames(4)
	check(animator.locomotion_state == &"Idle", "unfreeze resumes animation from actual stationary state")
	var animator_ref: WeakRef = weakref(animator)
	controller.start_stage_change_sequence(StageConfig.Keys.Credits)
	check(await wait_for_stage("res://stages/credits/credits_stage.tscn"), "animated player unloads safely")
	check(animator_ref.get_ref() == null and EventSystem.PLA_pickup_collected.get_connections().size() == 1, "stage exit frees animator and disconnects pickup listener")
	finish()

func finish() -> void:
	print("SPRINT 006: ", checks, " checks, ", failures, " failures")
	game.get_node("MusicController").stop()
	await get_tree().create_timer(0.25).timeout
	game.queue_free()
	await get_tree().create_timer(0.25).timeout
	MobileInput.configure_enabled(false)
	get_tree().quit(0 if failures == 0 else 1)
