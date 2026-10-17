extends CanvasLayer

# A public/release binary cannot enable this, even with the custom feature or
# command-line argument. Editor opt-in exists only for automated development.
var invincible := false
var unlimited_needs := false
var flying := false
var speed_multiplier := 1.0
var player: Player
var safe_position := Vector3.ZERO
var spawn_position := Vector3.ZERO
var panel: Control
var status: Label
var feedback: Label
var item_index := 0
var item_label: Label
var toggles: Dictionary = {}
var speed_slider: HSlider

func available() -> bool:
	return OS.is_debug_build() and (OS.has_feature("internal_dev") or (OS.has_feature("editor") and OS.get_cmdline_user_args().has("--internal-dev")))

func _ready() -> void:
	layer = 30
	if not available():
		set_process(false)
		set_process_input(false)
		return
	build_panel()
	get_viewport().size_changed.connect(layout)
	layout()

func attach_player(value: Player) -> void:
	player = value
	safe_position = value.global_position
	spawn_position = value.global_position
	reset_cheats(false)

func detach_player(value: Player) -> void:
	if player != value:
		return
	reset_cheats(false)
	player = null
	if is_instance_valid(panel):
		panel.hide()

func damage_protected() -> bool:
	return available() and is_instance_valid(player) and invincible

func needs_protected() -> bool:
	return available() and is_instance_valid(player) and unlimited_needs

func is_flying() -> bool:
	return available() and is_instance_valid(player) and flying

func movement_multiplier() -> float:
	return speed_multiplier if available() and is_instance_valid(player) else 1.0

func set_cheat(key: String, value: bool) -> bool:
	if not available() or not is_instance_valid(player):
		return false
	match key:
		"invincible": invincible = value
		"needs":
			unlimited_needs = value
			if value:
				EventSystem.PLA_change_energy.emit(0.0)
		"fly":
			if flying and not value:
				recover()
			flying = value
			player.velocity = Vector3.ZERO
			MobileInput.release_all()
		_: return false
	MobileInput.configure_layout(MobileInput.safe_rect)
	return true

func set_speed(value: float) -> void:
	if available() and is_instance_valid(player) and is_finite(value):
		speed_multiplier = clampf(value, 0.5, 3.0)

func reset_cheats(land := true) -> void:
	if land and is_flying():
		recover()
	invincible = false
	unlimited_needs = false
	flying = false
	speed_multiplier = 1.0
	MobileInput.release_all()
	if is_instance_valid(MobileInput.surface):
		MobileInput.configure_layout(MobileInput.safe_rect)
	for button in toggles.values():
		button.set_pressed_no_signal(false)
	if is_instance_valid(speed_slider):
		speed_slider.set_value_no_signal(1.0)

func record_ground() -> void:
	if available() and is_instance_valid(player) and not flying and player.is_on_floor():
		safe_position = player.global_position

func recover(to_spawn := false) -> bool:
	if not available() or not is_instance_valid(player):
		return false
	# Recheck the remembered capsule volume: buildings may have occupied it.
	var capsule: CollisionShape3D = player.get_node("CollisionShape3D")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule.shape
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	for height in [0.08, 1.0, 2.0, 4.0, 8.0]:
		var destination: Vector3 = (spawn_position if to_spawn else safe_position) + Vector3.UP * height
		query.transform = player.global_transform
		query.transform.origin = destination + capsule.position
		if player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			player.global_position = destination
			player.velocity = Vector3.ZERO
			return true
	return false

func move_flight(delta: float) -> void:
	if not is_flying():
		return
	var input := MobileInput.input_vector()
	var direction := Basis(Vector3.UP, player.camera_rig.global_rotation.y) * Vector3(input.x, 0, input.y)
	var vertical := float(MobileInput.pressed("fly_up")) - float(MobileInput.pressed("fly_down"))
	# Desktop Space/Control complement the two mobile hold buttons.
	if not MobileInput.enabled:
		vertical = float(Input.is_physical_key_pressed(KEY_SPACE)) - float(Input.is_physical_key_pressed(KEY_CTRL))
	player.is_sprinting = MobileInput.pressed("sprint")
	player.velocity = Vector3(direction.x, vertical, direction.z).limit_length() * (player.sprint_speed if player.is_sprinting else player.normal_speed) * speed_multiplier
	if not direction.is_zero_approx():
		player.character_visuals.rotation.y = lerp_angle(player.character_visuals.rotation.y, atan2(-direction.x, -direction.z)-player.global_rotation.y, 1.0-exp(-15.0*delta))
	player.equipment_pivot.rotation = player.camera_rig.rotation if player.item_holder.current_item_scene is EquippableConstructable else Vector3(player.camera_rig.rotation.x, player.character_visuals.rotation.y, 0)
	player.move_and_slide()

func give_item(key: int, quantity: int) -> int:
	if not available() or not is_instance_valid(player) or not ItemConfig.ITEM_RESOURCES.has(key) or quantity <= 0:
		return 0
	var inventory: InventoryManager = player.get_node("Managers/InventoryManager")
	var count := mini(quantity, inventory.get_free_slots())
	for index in count:
		inventory.add_item(key)
	return count

func toggle_panel() -> void:
	if not available() or not is_instance_valid(player) or get_tree().paused:
		return
	if panel.visible:
		panel.hide()
		EventSystem.PLA_unfreeze_player.emit()
		MobileInput.capture_mouse()
	elif not MobileInput.frozen:
		EventSystem.PLA_freeze_player.emit()
		panel.show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		layout()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		toggle_panel()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	status.visible = is_instance_valid(player)
	var area := MobileInput.safe_rect
	status.position = area.position + (Vector2(16, area.size.y-32) if panel.visible else Vector2(16,80)*area.size.y/720.0)
	var active: Array[String] = []
	if invincible: active.append("INVINCIBLE")
	if unlimited_needs: active.append("UNLIMITED ENERGY")
	if flying: active.append("FLY")
	if speed_multiplier != 1.0: active.append("SPEED %.1fx" % speed_multiplier)
	for button in toggles.values():
		button.text = ("[ON] " if button.button_pressed else "[OFF] ") + str(button.get_meta("caption"))
	status.text = "INTERNAL DEV | " + ("Cheats OFF" if active.is_empty() else ", ".join(active))

func add_button(parent: Node, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(0, 76)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func build_panel() -> void:
	status = Label.new()
	status.add_theme_font_size_override("font_size", 22)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.modulate = Color(1.0,0.85,0.35)
	add_child(status)
	panel = Panel.new()
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.035,0.055,0.07,0.97)
	panel.add_theme_stylebox_override("panel", background)
	panel.theme = Theme.new()
	panel.theme.default_font_size = 28
	panel.size = Vector2(1920,1080)
	add_child(panel)
	move_child(status, -1)
	var column := VBoxContainer.new()
	column.position = Vector2(420,30)
	column.size = Vector2(1080,1020)
	panel.add_child(column)
	var title := Label.new()
	title.text = "INTERNAL DEVELOPER TOOLS — F8 / DEV\nAll cheats reset when leaving the island."
	column.add_child(title)
	for pair in [["invincible", "Invincibility"], ["needs", "Unlimited energy / existing survival needs"], ["fly", "Fly (Up / Down; disable to recover grounded position)"]]:
		var key: String = pair[0]
		var button := add_button(column, pair[1], func(): set_cheat(key, toggles[key].button_pressed))
		button.set_meta("caption", pair[1])
		button.toggle_mode = true
		toggles[key] = button
	var label := Label.new()
	label.text = "Movement speed: 0.5x–3x (default 1x)"
	column.add_child(label)
	speed_slider = HSlider.new()
	speed_slider.min_value = 0.5
	speed_slider.max_value = 3
	speed_slider.step = 0.1
	speed_slider.value = 1
	speed_slider.value_changed.connect(set_speed)
	column.add_child(speed_slider)
	var row := HBoxContainer.new()
	column.add_child(row)
	add_button(row, "Previous item", select_item.bind(-1))
	item_label = Label.new()
	item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(item_label)
	add_button(row, "Next item", select_item.bind(1))
	select_item(0)
	var amounts := HBoxContainer.new()
	column.add_child(amounts)
	for quantity in [1,5,10]:
		add_button(amounts, "Give %d" % quantity, func(): feedback.text = "Added %d item(s); full inventory is never overwritten." % give_item(item_index, quantity))
	feedback = Label.new()
	column.add_child(feedback)
	var recovery_row := HBoxContainer.new()
	column.add_child(recovery_row)
	add_button(recovery_row, "Last grounded position", func(): feedback.text = "Recovered" if recover() else "No clear recovery point available")
	add_button(recovery_row, "Reset to island spawn", func(): feedback.text = "Reset to spawn" if recover(true) else "Spawn is obstructed")
	add_button(column, "Disable ALL cheats / land safely", reset_cheats)
	add_button(column, "Close", toggle_panel)
	panel.hide()

func select_item(offset: int) -> void:
	item_index = wrapi(item_index + offset, 0, ItemConfig.ITEM_RESOURCES.size())
	item_label.text = ItemConfig.Keys.keys()[item_index]

func layout() -> void:
	if not available() or not is_instance_valid(panel):
		return
	var area := MobileInput.platform_safe_rect()
	var ratio := minf(area.size.x/1920.0, area.size.y/1080.0)
	panel.scale = Vector2.ONE * ratio
	panel.position = area.position + (area.size-panel.size*ratio)/2
	status.position = area.position + Vector2(16,80)*area.size.y/720.0
	MobileInput.register_gui(panel)
