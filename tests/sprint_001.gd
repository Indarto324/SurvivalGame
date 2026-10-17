extends Node

# Runs the shipped scenes and managers, without lowering scatter counts.
var checks := 0
var failures := 0
var pickup_destroyed := false
var game: Node
var controller: Node
var hud: Control

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func wait_for_stage(path: String, seconds := 90.0) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < seconds * 1000:
		await get_tree().process_frame
		if not controller.is_stage_changing and controller.get_child_count() == 1:
			if controller.get_child(0).scene_file_path == path:
				print("STAGE READY: ", path, " in ", (Time.get_ticks_msec() - started) / 1000.0, "s")
				return true
	return false

func physics_frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame

func run() -> void:
	game = load("res://game/main_game.tscn").instantiate()
	add_child(game)
	controller = game.get_node("StageController")
	hud = game.get_node("UILayer/HUDController/HUD")
	var ready := await wait_for_stage("res://stages/main_menu/main_menu.tscn")
	check(ready, "production-density main menu completes scatter loading")
	if not ready:
		finish()
		return
	check(not hud.visible, "HUD hidden in menu and retained in scene tree")
	for iteration in 5:
		EventSystem.HUD_show_hud.emit()
		EventSystem.HUD_show_hud.emit()
		EventSystem.HUD_hide_hud.emit()
		EventSystem.HUD_hide_hud.emit()
	check(hud.is_inside_tree() and not hud.visible, "repeated HUD show/hide is idempotent")
	var hud_parent := hud.get_parent()
	hud_parent.remove_child(hud)
	hud_parent.add_child(hud)
	var hotbar_ui = hud.get_node("MarginContainer/Hotbar")
	check(EventSystem.INV_hotbar_updated.get_connections().size() == 1, "one HUD hotbar subscription before player spawn")
	for slot in hotbar_ui.get_children():
		check(slot.mouse_entered.get_connections().size() == 1 and slot.mouse_exited.get_connections().size() == 1,
			"hotbar slot hover handlers connected once")
	controller.get_child(0)._on_start_button_pressed()
	ready = await wait_for_stage("res://stages/island/island.tscn")
	check(ready, "production-density island completes all scatter generators")
	if not ready:
		finish()
		return
	check(hud.visible, "HUD visible on island")
	var island = controller.get_child(0)
	var player = island.get_node("Actors/Player")
	var inventory = player.get_node("Managers/InventoryManager")
	var stats = player.get_node("Managers/PlayerStatsManager")
	var equipped = player.get_node("Managers/EquippedItemManager")
	check(inventory.inventory.size() == 28 and inventory.hotbar.size() == 9, "inventory and hotbar initialize")
	equipped.hotkey_pressed(1)
	check(equipped.active_slot == null, "empty hotbar key is safe before first item")
	var stat_ui = hud.get_node("MarginContainer/PlayerStatsContainer")
	check(stat_ui.health_bar.value == 100 and stat_ui.energy_bar.value == 100, "new player publishes initial HUD stats")
	# A flat test arena isolates movement from random vegetation and animal AI.
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 2, 100)
	floor_collision.shape = box
	floor_body.add_child(floor_collision)
	island.add_child(floor_body)
	floor_body.global_position = Vector3(500, 98, 0)
	for physics_rate in [30, 120]:
		Engine.physics_ticks_per_second = physics_rate
		player.global_position = Vector3(500, 150, 0)
		player.velocity = Vector3.ZERO
		await physics_frames(2)
		player.velocity = Vector3.ZERO
		await physics_frames(physics_rate)
		print("GRAVITY: ", physics_rate, " Hz: ", player.velocity.y)
		check(absf(player.velocity.y + player.gravity) < 0.5, "gravity is time based at %d Hz" % physics_rate)
	Engine.physics_ticks_per_second = 60
	player.global_position = Vector3(500, 101, 0)
	player.velocity = Vector3.ZERO
	await physics_frames(90)
	check(player.is_on_floor(), "player lands on collision geometry")
	var origin: Vector3 = player.global_position
	var energy_before: float = stats.current_energy
	Input.action_press("move_forward")
	await physics_frames(30)
	Input.action_release("move_forward")
	var walk_distance: float = origin.distance_to(player.global_position)
	check(walk_distance > 1.0 and walk_distance < 2.0, "walking moves at configured speed")
	check(stats.current_energy < energy_before, "walking consumes survival energy")
	origin = player.global_position
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await physics_frames(30)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	check(origin.distance_to(player.global_position) > walk_distance * 1.3, "sprinting is faster than walking")
	await physics_frames(2)
	Input.action_press("jump")
	await physics_frames(2)
	Input.action_release("jump")
	check(player.velocity.y > 0 and not player.is_on_floor(), "jump leaves the ground")
	EventSystem.PLA_freeze_player.emit()
	check(not player.is_physics_processing() and not player.is_processing_input(), "menus freeze player movement and input")
	EventSystem.PLA_unfreeze_player.emit()
	check(player.is_physics_processing() and player.is_processing_input(), "closing menus restores player input")
	player.set_freeze(true)
	# Full inventory of enum-zero sticks must reject pickup without destroying it.
	inventory.inventory.fill(ItemConfig.Keys.Stick)
	check(inventory.get_free_slots() == 0, "Stick enum zero occupies inventory space")
	inventory.try_to_pickup_item(ItemConfig.Keys.Stone, func(): pickup_destroyed = true)
	check(not pickup_destroyed and inventory.inventory.count(ItemConfig.Keys.Stick) == 28, "full inventory preserves world pickup")
	inventory.delete_item_by_index(0, false)
	inventory.try_to_pickup_item(ItemConfig.Keys.Stone, func(): pickup_destroyed = true)
	check(pickup_destroyed and inventory.inventory[0] == ItemConfig.Keys.Stone, "pickup fills free slot and consumes world item")
	inventory.switch_two_item_indexes(0, false, 0, true)
	check(inventory.inventory[0] == null and inventory.hotbar[0] == ItemConfig.Keys.Stone, "inventory to hotbar swap")
	check(hotbar_ui.get_child(0).item_key == ItemConfig.Keys.Stone, "hotbar renders inventory update")
	inventory.delete_item_by_index(0, true)
	inventory.inventory.fill(null)
	inventory.send_inventory()
	EventSystem.BUL_create_bulletin.emit(BulletinConfig.Keys.CraftingMenu)
	var bulletins = game.get_node("UILayer/BulletinController")
	var crafting = bulletins.bulletins[BulletinConfig.Keys.CraftingMenu]
	var rope_button = craft_button(crafting, ItemConfig.Keys.Rope)
	check(rope_button.disabled, "crafting rejects missing ingredients")
	inventory.add_item(ItemConfig.Keys.Plant)
	check(rope_button.disabled, "crafting rejects insufficient ingredient quantities")
	inventory.add_item(ItemConfig.Keys.Plant)
	check(not rope_button.disabled, "crafting enables when recipe costs are present")
	rope_button.pressed.emit()
	check(inventory.inventory.has(ItemConfig.Keys.Rope) and not inventory.inventory.has(ItemConfig.Keys.Plant), "crafting creates rope and consumes exact recipe costs")
	var campfire_recipe = ItemConfig.get_crafting_blueprint_resource(ItemConfig.Keys.Campfire)
	for cost in campfire_recipe.costs:
		for amount in cost.amount:
			inventory.add_item(cost.item_key)
	check(craft_button(crafting, ItemConfig.Keys.Campfire).disabled, "crafting enforces tinderbox requirement")
	inventory.add_item(ItemConfig.Keys.Tinderbox)
	check(not craft_button(crafting, ItemConfig.Keys.Campfire).disabled, "required tool unlocks crafting")
	craft_button(crafting, ItemConfig.Keys.Campfire).pressed.emit()
	check(inventory.inventory.has(ItemConfig.Keys.Campfire) and inventory.inventory.has(ItemConfig.Keys.Tinderbox), "crafting retains required tool")
	inventory.inventory.fill(null)
	var tinderbox_recipe = ItemConfig.get_crafting_blueprint_resource(ItemConfig.Keys.Tinderbox)
	for cost in tinderbox_recipe.costs:
		for amount in cost.amount:
			inventory.add_item(cost.item_key)
	check(craft_button(crafting, ItemConfig.Keys.Tinderbox).disabled, "crafting enforces multitool requirement")
	inventory.add_item(ItemConfig.Keys.Multitool)
	check(not craft_button(crafting, ItemConfig.Keys.Tinderbox).disabled, "multitool unlocks crafting")
	craft_button(crafting, ItemConfig.Keys.Tinderbox).pressed.emit()
	check(inventory.inventory.has(ItemConfig.Keys.Tinderbox) and inventory.inventory.has(ItemConfig.Keys.Multitool), "crafting retains multitool")
	crafting.close()
	await get_tree().process_frame
	player.set_freeze(true)
	stats.change_health(-40)
	stats.change_energy(1000)
	stats.change_energy(-50)
	inventory.add_item_by_index(ItemConfig.Keys.Fruit, 0, true)
	equipped.hotkey_pressed(1)
	check(player.item_holder.current_item_scene is EquippableConsumable, "hotbar equips consumable")
	player.item_holder.current_item_scene.consume()
	check(is_equal_approx(stats.current_health, 80.0) and is_equal_approx(stats.current_energy, 60.0), "fruit restores configured health and energy")
	check(inventory.hotbar[0] == null, "consumed item removed from hotbar")
	stats.change_health(1000)
	stats.change_energy(1000)
	check(stats.current_health == 100 and stats.current_energy == 100, "health and energy clamp at maxima")
	stats.change_energy(-105)
	check(stats.current_energy == 0 and stats.current_health == 95, "energy exhaustion spills deficit into health")
	check(stat_ui.energy_bar.value == 0 and stat_ui.health_bar.value == 95, "HUD reflects survival damage")
	# Harvestable trees and their drops/stumps remain functional after foliage tuning.
	var tree = load("res://objects/hittable_objects/hittable_tree.tscn").instantiate()
	island.add_child(tree)
	tree.position = Vector3(505, 100, 0)
	var spawner = island.find_children("*", "Spawner", true, false)[0]
	var drops_before: int = spawner.object_holder.get_child_count()
	var stump = tree.residue_static_body
	var axe = ItemConfig.get_item_resource(ItemConfig.Keys.Axe)
	for hit in 3:
		tree.register_hit(axe)
	check(stump.get_parent() == tree, "harvesting replaces tree with stump")
	check(spawner.object_holder.get_child_count() == drops_before + 2, "harvesting preserves log drops")
	var unharvested = load("res://objects/hittable_objects/hittable_tree.tscn").instantiate()
	island.add_child(unharvested)
	var stump_reference: WeakRef = weakref(unharvested.residue_static_body)
	var day_night = island.get_node("DayNightCycleAnimationPlayer")
	var clock_before: float = day_night.current_animation_position
	EventSystem.GAM_fast_forward_day_night_anim.emit(8.0)
	check(absf(day_night.current_animation_position - fmod(clock_before + 8.0, day_night.current_animation_length)) < 0.1, "sleep time advance wraps the day/night clock")
	stats.change_health(-1000)
	check(stats.current_health == 0 and not player.is_physics_processing(), "death clamps health and freezes player")
	ready = await wait_for_stage("res://stages/main_menu/main_menu.tscn")
	check(ready and not hud.visible, "death returns to menu and hides HUD")
	check(stump_reference.get_ref() == null, "unharvested detached stumps freed on stage exit")
	if ready:
		check(EventSystem.INV_hotbar_updated.get_connections().size() == 1, "old player subscriptions removed on stage exit")
		controller.get_child(0)._on_start_button_pressed()
		ready = await wait_for_stage("res://stages/island/island.tscn")
		check(ready, "second island session loads")
		if ready:
			check(hud.visible and stat_ui.health_bar.value == 100 and stat_ui.energy_bar.value == 100, "HUD resets for a new survival session")
			check(hotbar_ui.get_child(0).item_key == null, "new session clears previous hotbar")
		controller.start_stage_change_sequence(StageConfig.Keys.Credits)
		check(await wait_for_stage("res://stages/credits/credits_stage.tscn"), "credits transition completes")
	finish()

func craft_button(menu: CraftingMenu, item_key: ItemConfig.Keys) -> Button:
	for craft in menu.craft_button_container.get_children():
		if craft.item_key == item_key:
			return craft.button
	return null

func finish() -> void:
	print("SPRINT 001: ", checks, " checks, ", failures, " failures")
	game.get_node("MusicController").stop()
	await get_tree().create_timer(0.25).timeout
	game.queue_free()
	await get_tree().create_timer(0.25).timeout
	get_tree().quit(0 if failures == 0 else 1)
