extends "res://tests/sprint_003.gd"

var player: Player
var inventory: InventoryManager
var island: Node
var bulletins: Node

func tap_action(action: String) -> void:
	touch(30, center(action), true)
	touch(30, center(action), false)

func open_bag() -> CraftingMenu:
	tap_action("inventory")
	await get_tree().process_frame
	return bulletins.bulletins[BulletinConfig.Keys.CraftingMenu]

func close_bag(menu: CraftingMenu) -> void:
	tap_control(menu.find_child("CloseButton", true, false))
	await get_tree().process_frame

func equip_from_bag(menu: CraftingMenu, key: ItemConfig.Keys, slot: int) -> void:
	var index := inventory.inventory.find(key)
	check(index >= 0, "crafted item exists in inventory before touch transfer")
	if index < 0:
		return
	tap_control(menu.inventory_slot_container.get_child(index))
	var bar := menu.get_child(menu.get_child_count()-1)
	tap_control(bar.get_child(slot))
	check(inventory.hotbar[slot] == key, "touch transfers crafted item into equipment hotbar")

func pickup_scene(key: ItemConfig.Keys, offset: Vector3) -> Node3D:
	var names := {ItemConfig.Keys.Stick:"stick", ItemConfig.Keys.Stone:"stone", ItemConfig.Keys.Fruit:"fruit", ItemConfig.Keys.Plant:"plant"}
	var item = load("res://interactables/pickuppables/pickuppable_%s.tscn" % names[key]).instantiate()
	island.add_child(item)
	item.global_position = Vector3(player.global_position.x, 99.08, player.global_position.z) + offset
	return item

func collect(key: ItemConfig.Keys) -> void:
	var count := inventory.inventory.count(key)
	var item := pickup_scene(key, Vector3(0.3, 0, -1.2))
	await physics_frames(3)
	# Rendering may batch several physics ticks before _process. Wait for
	# real target selection, rather than assuming one process_frame signal
	# (emitted before node processing) has already updated the aim.
	var started := Time.get_ticks_msec()
	while player.interaction_ray_cast.current_interactable != item.get_node("Pickuppable") and Time.get_ticks_msec() - started < 2000:
		await get_tree().process_frame
	if key == ItemConfig.Keys.Stick:
		player.interaction_ray_cast.update_aim()
		check(not player.interaction_ray_cast.is_colliding() or not player.interaction_ray_cast.get_collider() is Interactable, "ground fixture reproduces original exact-ray targeting miss")
	check(player.interaction_ray_cast.current_interactable == item.get_node("Pickuppable"), "ground-level pickup selected at default follow pitch")
	check(MobileInput.interaction_target == item.get_node("Pickuppable"), "visible target marker and Interact highlight track selected pickup")
	if key == ItemConfig.Keys.Stick and OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/workspace/artifacts/kawanan-sprint005/target-feedback.png")
	tap_action("interact")
	await get_tree().process_frame
	await get_tree().process_frame
	check(inventory.inventory.count(key) == count + 1 and not is_instance_valid(item), "raw Interact touch collects ground item exactly once into inventory")

func run() -> void:
	MobileInput.configure_enabled(true)
	game = load("res://game/main_game.tscn").instantiate()
	add_child(game)
	controller = game.get_node("StageController")
	check(await wait_for_stage("res://stages/main_menu/main_menu.tscn"), "main menu loads")
	tap_control(controller.get_child(0).find_child("StartButton", true, false))
	check(await wait_for_stage("res://stages/island/island.tscn"), "touch starts island")
	island = controller.get_child(0)
	player = island.get_node("Actors/Player")
	inventory = player.get_node("Managers/InventoryManager")
	bulletins = game.get_node("UILayer/BulletinController")
	# Real ground height / capsule height, not the chest-height pickups used in 003.
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 2, 100)
	shape.shape = box
	floor_body.add_child(shape)
	island.add_child(floor_body)
	floor_body.position = Vector3(500, 98, 0)
	player.global_position = Vector3(500, 100, 0)
	player.velocity = Vector3.ZERO
	await physics_frames(60)
	check(is_equal_approx(player.camera_rig.target_pitch, -0.2), "test keeps shipped default follow-camera pitch")
	var neutral_stick: Vector2 = MobileInput.joystick_center
	var look_point: Vector2 = MobileInput.safe_rect.position + MobileInput.safe_rect.size * Vector2(0.75, 0.4)
	touch(0, neutral_stick, true)
	touch(1, look_point, true)
	for key in [ItemConfig.Keys.Stick, ItemConfig.Keys.Stone, ItemConfig.Keys.Fruit, ItemConfig.Keys.Plant, ItemConfig.Keys.Plant]:
		await collect(key)
	check(MobileInput.move_finger == 0 and MobileInput.look_finger == 1, "Interact preserves simultaneous joystick and look finger ownership")
	touch(0, neutral_stick, false)
	touch(1, look_point, false)
	var menu := await open_bag()
	check(not MobileInput.can_control() and MobileInput.interaction_target == null, "inventory freezes interactions and clears target feedback")
	check(menu.inventory_slot_container.get_child(inventory.inventory.find(ItemConfig.Keys.Stone)).item_key == ItemConfig.Keys.Stone, "collected stone is displayed in inventory UI")
	tap_control(craft_button(menu, ItemConfig.Keys.Rope))
	check(inventory.inventory.has(ItemConfig.Keys.Rope), "touch crafts rope from two collected plants")
	tap_control(craft_button(menu, ItemConfig.Keys.Axe))
	check(inventory.inventory.has(ItemConfig.Keys.Axe) and not inventory.inventory.has(ItemConfig.Keys.Stick) and not inventory.inventory.has(ItemConfig.Keys.Stone), "touch crafts axe from collected stick, stone and rope")
	await equip_from_bag(menu, ItemConfig.Keys.Axe, 0)
	await close_bag(menu)
	tap_action("slot_0")
	check(player.item_holder.current_item_scene is EquippableWeapon, "hotbar touch equips crafted axe")
	var tree = load("res://objects/hittable_objects/hittable_tree.tscn").instantiate()
	island.add_child(tree)
	tree.global_position = Vector3(player.global_position.x, 99, player.global_position.z - 1.1)
	await physics_frames(4)
	var energy: float = player.get_node("Managers/PlayerStatsManager").current_energy
	for swing in 3:
		tap_action("use_equipped_item")
		await get_tree().create_timer(0.85).timeout
	check(tree.current_health <= 0 and tree.get_child_count() == 1, "three Use touches harvest real tree into stump")
	check(player.get_node("Managers/PlayerStatsManager").current_energy < energy, "axe swings preserve survival energy consumption")
	var logs := island.find_children("*", "RigidBody3D", true, false).filter(func(body): return body.has_node("Pickuppable") and body.get_node("Pickuppable").item_key == ItemConfig.Keys.Log)
	check(logs.size() >= 2, "harvest spawns collectible logs")
	# Verify an actual harvested rigid pickup, whose body can intercept the ray
	# before its Interactable area. Freeze only the test fixture's settling.
	tree.queue_free()
	if not logs.is_empty():
		var harvested_log: RigidBody3D = logs.pop_back()
		harvested_log.freeze = true
		harvested_log.global_position = player.global_position + Vector3(0.4, -0.4, -1.2)
		for log_item in logs:
			log_item.queue_free()
		await physics_frames(4)
		await get_tree().process_frame
		check(player.interaction_ray_cast.current_interactable == harvested_log.get_node("Pickuppable"), "harvested rigid-body log resolves its pickup area")
		tap_action("interact")
		await get_tree().process_frame
		await get_tree().process_frame
		check(inventory.inventory.has(ItemConfig.Keys.Log), "Interact collects harvested log through real inventory manager")
	await physics_frames(4)
	var hidden := pickup_scene(ItemConfig.Keys.Stone, Vector3(0, 0, -1.3))
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(4, 4, 0.2)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	island.add_child(wall)
	wall.global_position = player.global_position + Vector3(0, 0, -0.6)
	await physics_frames(4)
	await get_tree().process_frame
	check(player.interaction_ray_cast.current_interactable == null, "touch targeting cannot collect through solid walls")
	wall.queue_free()
	hidden.queue_free()
	await physics_frames(4)
	var distant := pickup_scene(ItemConfig.Keys.Stone, Vector3(0, 0, -4))
	var behind := pickup_scene(ItemConfig.Keys.Stick, Vector3(0, 0, 1))
	await physics_frames(4)
	await get_tree().process_frame
	check(player.interaction_ray_cast.current_interactable == null, "assist rejects out-of-reach and behind-player pickups")
	distant.queue_free()
	behind.queue_free()
	await physics_frames(4)
	# Construction recipe costs are fixture-seeded; original recipes/tool gates
	# and native touch crafting, transfer, equip, preview and Use are exercised.
	var spawner: Spawner = island.find_children("*", "Spawner", true, false)[0]
	for key in [ItemConfig.Keys.Campfire, ItemConfig.Keys.Tent]:
		inventory.inventory.fill(null)
		var blueprint := ItemConfig.get_crafting_blueprint_resource(key)
		for cost in blueprint.costs:
			for n in cost.amount:
				inventory.add_item(cost.item_key)
		menu = await open_bag()
		if key == ItemConfig.Keys.Campfire:
			check(craft_button(menu, key).disabled, "campfire still requires tinderbox")
			inventory.add_item(ItemConfig.Keys.Tinderbox)
		tap_control(craft_button(menu, key))
		check(inventory.inventory.has(key), "touch crafts construction using existing resource costs")
		await equip_from_bag(menu, key, 1)
		await close_bag(menu)
		tap_action("slot_1")
		await physics_frames(5)
		await get_tree().create_timer(0.2).timeout
		var build: EquippableConstructable = player.item_holder.current_item_scene
		check(build != null and build.place_valid, "touch construction preview reaches nearby ground at default pitch")
		var before: int = spawner.constructable_holder.get_child_count()
		if key == ItemConfig.Keys.Campfire:
			var blocker := StaticBody3D.new()
			blocker.collision_layer = 64
			var blocker_shape := CollisionShape3D.new()
			var blocker_box := BoxShape3D.new()
			blocker_box.size = Vector3(4, 4, 0.2)
			blocker_shape.shape = blocker_box
			blocker.add_child(blocker_shape)
			island.add_child(blocker)
			blocker.global_position = player.global_position + Vector3(0, 0, -1)
			await physics_frames(4)
			await get_tree().create_timer(0.1).timeout
			check(not build.place_valid, "ground fallback cannot place a campfire through a solid wall")
			tap_action("use_equipped_item")
			await get_tree().create_timer(1.0).timeout
			check(inventory.hotbar[1] == key and spawner.constructable_holder.get_child_count() == before, "invalid Use preserves construction item and creates no object")
			blocker.queue_free()
			await physics_frames(4)
			await get_tree().create_timer(0.1).timeout
		tap_action("use_equipped_item")
		await get_tree().create_timer(1.5).timeout
		check(inventory.hotbar[1] == null and spawner.constructable_holder.get_child_count() == before + 1, "Use touch places construction and consumes exactly one equipped item")
		var nav: NavigationRegion3D = island.get_node("NavigationRegion3D")
		while nav.is_baking():
			await get_tree().process_frame
		# Move to another flat area so existing structures legitimately block
		# overlap rather than contaminating the next placement check.
		player.global_position.x += 8
		await physics_frames(4)
	controller.start_stage_change_sequence(StageConfig.Keys.Credits)
	check(await wait_for_stage("res://stages/credits/credits_stage.tscn"), "interaction session unloads safely")
	finish()

func finish() -> void:
	print("SPRINT 005: ", checks, " checks, ", failures, " failures")
	game.get_node("MusicController").stop()
	await get_tree().create_timer(0.25).timeout
	game.queue_free()
	await get_tree().create_timer(0.25).timeout
	MobileInput.configure_enabled(false)
	get_tree().quit(0 if failures == 0 else 1)
