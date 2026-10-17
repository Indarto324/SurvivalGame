extends CanvasLayer

# Touch state is separate from Input.action_press so releasing a finger never
# releases a physical key, and GUI-emulated mouse clicks cannot use an item.
class Surface extends Control:
	var host: Node
	func _draw() -> void:
		host.draw_controls(self)

var enabled := OS.has_feature("android") or OS.get_cmdline_user_args().has("--touch-controls")
var gameplay_active := false
var frozen := false
var movement := Vector2.ZERO
var fingers := {}
var ui_fingers := {}
var held := {}
var pending := {}
var move_finger := -1
var look_finger := -1
var safe_rect := Rect2()
var buttons := {}
var joystick_center := Vector2.ZERO
var joystick_radius := 80.0
var surface: Surface
var idle_style: StyleBoxFlat
var down_style: StyleBoxFlat
var hotbar_keys: Array = []
var hotbar_icons: Array[Texture2D] = []
var active_slot = null
var selected_slot: Control
var inventory_menu: Control
var menus: Array[Control] = []
var safe_check_elapsed := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	idle_style = panel_style(Color(0.06, 0.16, 0.2, 0.8))
	down_style = panel_style(Color(0.2, 0.5, 0.55, 0.9))
	surface = Surface.new()
	surface.host = self
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(surface)
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	EventSystem.HUD_show_hud.connect(set_gameplay.bind(true))
	EventSystem.HUD_hide_hud.connect(set_gameplay.bind(false))
	EventSystem.PLA_freeze_player.connect(set_frozen.bind(true))
	EventSystem.PLA_unfreeze_player.connect(set_frozen.bind(false))
	configure_enabled(enabled)
	get_viewport().size_changed.connect(refresh_layout)
	refresh_layout()
	if enabled:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func configure_enabled(value: bool) -> void:
	enabled = value
	Input.emulate_mouse_from_touch = not enabled
	release_all()
	if enabled and not EventSystem.INV_hotbar_updated.is_connected(update_hotbar):
		EventSystem.INV_hotbar_updated.connect(update_hotbar)
		EventSystem.EQU_active_hotbar_slot_updated.connect(update_active)
	elif not enabled and EventSystem.INV_hotbar_updated.is_connected(update_hotbar):
		EventSystem.INV_hotbar_updated.disconnect(update_hotbar)
		EventSystem.EQU_active_hotbar_slot_updated.disconnect(update_active)
	refresh_layout()
	capture_mouse()

func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if enabled else Input.MOUSE_MODE_CAPTURED

func can_control() -> bool:
	return enabled and gameplay_active and not frozen and not get_tree().paused

func set_gameplay(value: bool) -> void:
	gameplay_active = value
	if not value:
		release_all()
	surface.queue_redraw()

func set_frozen(value: bool) -> void:
	frozen = value
	release_all()
	surface.queue_redraw()

func release_all() -> void:
	for index in ui_fingers.keys():
		release_ui_finger(index, Vector2.ZERO, true)
	fingers.clear()
	held.clear()
	pending.clear()
	movement = Vector2.ZERO
	move_finger = -1
	look_finger = -1
	clear_selection()
	if is_instance_valid(surface):
		surface.queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		release_all()

func input_vector() -> Vector2:
	return (Input.get_vector("move_left", "move_right", "move_forward", "move_backward") + movement).limit_length()

func pressed(action: String) -> bool:
	return held.get(action, 0) > 0 or Input.is_action_pressed(action)

func just_pressed(action: String) -> bool:
	if pending.has(action):
		pending.erase(action)
		return true
	# Never let emulated mouse clicks map to the world item action.
	if enabled and action == "use_equipped_item":
		return false
	return Input.is_action_just_pressed(action)

func _process(delta: float) -> void:
	if enabled and OS.has_feature("android"):
		safe_check_elapsed += delta
		if safe_check_elapsed >= 0.5:
			safe_check_elapsed = 0
			if platform_safe_rect() != safe_rect:
				refresh_layout()

func logical_safe_rect(screen_safe: Rect2, screen_transform: Transform2D, viewport_rect: Rect2) -> Rect2:
	var intersection := viewport_rect.intersection(screen_transform.affine_inverse() * screen_safe)
	return intersection if intersection.has_area() else viewport_rect

func platform_safe_rect() -> Rect2:
	var viewport_rect := get_viewport().get_visible_rect()
	if OS.has_feature("android"):
		var screen_safe := Rect2(DisplayServer.get_display_safe_area())
		return logical_safe_rect(screen_safe, get_viewport().get_screen_transform(), viewport_rect)
	return viewport_rect

func refresh_layout() -> void:
	configure_layout(platform_safe_rect())
	for index in range(menus.size() - 1, -1, -1):
		if is_instance_valid(menus[index]):
			fit_menu(menus[index])
		else:
			menus.remove_at(index)
	if can_control():
		EventSystem.HUD_show_hud.emit()

func configure_layout(area: Rect2) -> void:
	# Viewport coordinates, also used by ScreenTouch/ScreenDrag after stretch.
	if area != safe_rect:
		release_all()
	safe_rect = area
	buttons.clear()
	var u := area.size.y / 720.0
	joystick_radius = 80 * u
	joystick_center = area.position + Vector2(128 * u, area.size.y - 190 * u)
	var right := area.end.x
	var bottom := area.end.y
	buttons["sprint"] = Rect2(Vector2(right - 202*u, bottom - 284*u), Vector2(80, 80)*u)
	buttons["jump"] = Rect2(Vector2(right - 110*u, bottom - 284*u), Vector2(80, 80)*u)
	buttons["interact"] = Rect2(Vector2(right - 202*u, bottom - 192*u), Vector2(80, 80)*u)
	buttons["use_equipped_item"] = Rect2(Vector2(right - 110*u, bottom - 192*u), Vector2(80, 80)*u)
	for index in 3:
		var key: String = ["craft", "inventory", "pause"][index]
		buttons[key] = Rect2(Vector2(area.get_center().x + (index-1.5)*104*u, area.position.y + 16*u), Vector2(96, 56)*u)
	for index in 9:
		buttons["slot_%d" % index] = Rect2(Vector2(area.get_center().x - 394*u + index*88*u, bottom-94*u), Vector2(84, 84)*u)
	if is_instance_valid(surface):
		surface.queue_redraw()

func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			if not can_control():
				if tap_menu_slot(event.position) or press_ui_finger(event.index, event.position):
					get_viewport().set_input_as_handled()
				return
			var role := "ignored"
			for key in buttons:
				if buttons[key].has_point(event.position):
					role = key
					break
			if role == "ignored" and event.position.distance_to(joystick_center) <= joystick_radius * 1.2 and move_finger == -1:
				role = "move"
				move_finger = event.index
			elif role == "ignored" and event.position.x > safe_rect.get_center().x and safe_rect.has_point(event.position) and look_finger == -1:
				role = "look"
				look_finger = event.index
			fingers[event.index] = role
			if role == "move":
				update_stick(event.position)
			elif buttons.has(role):
				activate(role)
			get_viewport().set_input_as_handled()
		else:
			if ui_fingers.has(event.index):
				release_ui_finger(event.index, event.position, event.canceled)
				get_viewport().set_input_as_handled()
			else:
				release_finger(event.index)
	elif event is InputEventScreenDrag and ui_fingers.has(event.index):
		var control = ui_fingers[event.index]
		if is_instance_valid(control) and control is Slider:
			update_slider(control, event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and fingers.has(event.index):
		var role: String = fingers[event.index]
		if role == "move":
			update_stick(event.position)
		elif role == "look" and can_control():
			var player := get_tree().get_first_node_in_group("Player")
			if is_instance_valid(player):
				player.look_around(event.relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.device != -1 and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and can_control():
		# Keep real desktop mouse use available in the opt-in touch preview.
		for rect in buttons.values():
			if rect.has_point(event.position):
				return
		pending["use_equipped_item"] = true

func update_stick(position: Vector2) -> void:
	var raw := ((position - joystick_center) / joystick_radius).limit_length()
	var length := raw.length()
	movement = Vector2.ZERO if length < 0.12 else raw.normalized() * ((length - 0.12) / 0.88)
	surface.queue_redraw()

func release_finger(index: int) -> void:
	var role: String = fingers.get(index, "ignored")
	fingers.erase(index)
	if role == "move":
		move_finger = -1
		movement = Vector2.ZERO
	elif role == "look":
		look_finger = -1
	elif held.has(role):
		held[role] = maxi(0, held[role] - 1)
	surface.queue_redraw()

func activate(role: String) -> void:
	if role == "craft" or role == "inventory":
		EventSystem.BUL_create_bulletin.emit(BulletinConfig.Keys.CraftingMenu)
	elif role == "pause":
		EventSystem.BUL_create_bulletin.emit(BulletinConfig.Keys.PauseMenu)
	elif role.begins_with("slot_"):
		EventSystem.EQU_hotkey_pressed.emit(role.trim_prefix("slot_").to_int() + 1)
	elif role == "sprint":
		held[role] = held.get(role, 0) + 1
	else:
		pending[role] = true
	surface.queue_redraw()

func update_hotbar(keys: Array) -> void:
	hotbar_keys = keys.duplicate()
	hotbar_icons.clear()
	for key in keys:
		hotbar_icons.append(null if key == null else ItemConfig.get_item_resource(key).icon)
	surface.queue_redraw()

func update_active(index) -> void:
	active_slot = index
	surface.queue_redraw()

func draw_controls(canvas: Control) -> void:
	if not can_control():
		return
	var u := safe_rect.size.y / 720.0
	canvas.draw_circle(joystick_center, joystick_radius, Color(0.05, 0.12, 0.15, 0.65))
	canvas.draw_circle(joystick_center + movement * joystick_radius, 30*u, Color(0.6, 0.85, 0.85, 0.9))
	var labels := {"jump":"Jump", "sprint":"Sprint", "interact":"Interact", "use_equipped_item":"Use", "craft":"Craft", "inventory":"Bag", "pause":"Pause"}
	for key in buttons:
		var rect: Rect2 = buttons[key]
		canvas.draw_style_box(down_style if key in fingers.values() else idle_style, rect)
		var text: String = labels.get(key, "")
		if key.begins_with("slot_"):
			var index: int = key.trim_prefix("slot_").to_int()
			text = str(index + 1)
			if index < hotbar_icons.size() and hotbar_icons[index] != null:
				canvas.draw_texture_rect(hotbar_icons[index], rect.grow(-6*u), false)
			if active_slot == index:
				canvas.draw_rect(rect, Color.CYAN, false, 3*u)
		canvas.draw_string(ThemeDB.fallback_font, rect.position + Vector2(0, rect.size.y * 0.65), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, int((19 if key == "interact" else 22)*u), Color.WHITE)

func panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(12)
	return style

func fit_menu(menu: Control) -> void:
	if not enabled:
		return
	menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	menu.size = Vector2(1920, 1080)
	var ratio := minf(safe_rect.size.x / 1920.0, safe_rect.size.y / 1080.0)
	menu.scale = Vector2.ONE * ratio
	menu.position = safe_rect.position + (safe_rect.size - menu.size*ratio) / 2
	register_gui(menu)
	if not menus.has(menu):
		menus.append(menu)

func prepare_inventory_menu(menu: Control) -> void:
	if not enabled:
		return
	inventory_menu = menu
	fit_menu(menu)
	var close_button := menu.find_child("CloseButton", true, false) as Button
	close_button.custom_minimum_size = Vector2(88, 88)
	var bar = load("res://ui/hud/hotbar_ui.gd").new()
	bar.position = Vector2(464, 952)
	bar.add_theme_constant_override("separation", 16)
	for index in 9:
		bar.add_child(load("res://ui/custom_nodes/hotbar_slot.tscn").instantiate())
	menu.add_child(bar)
	if hotbar_keys.size() == 9:
		bar.update_hotbar(hotbar_keys)

func tap_menu_slot(position: Vector2) -> bool:
	if not is_instance_valid(inventory_menu):
		return false
	for slot in get_tree().get_nodes_in_group("touch_inventory_targets"):
		if inventory_menu.is_ancestor_of(slot) and slot.is_visible_in_tree() and Rect2(Vector2.ZERO, slot.size).has_point(slot.get_global_transform_with_canvas().affine_inverse() * position):
			tap_slot(slot)
			return true
	for craft in get_tree().get_nodes_in_group("touch_craft_info"):
		if inventory_menu.is_ancestor_of(craft) and craft.is_visible_in_tree() and contains_point(craft, position):
			craft.send_crafting_info()
	return false

func contains_point(control: Control, point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, control.size).has_point(control.get_global_transform_with_canvas().affine_inverse() * point)

func register_gui(menu: Node) -> void:
	for control in menu.find_children("*", "BaseButton", true, false):
		control.add_to_group("touch_native_gui")
		control.custom_minimum_size.y = maxf(control.custom_minimum_size.y, 72)
	for slider in menu.find_children("*", "Slider", true, false):
		slider.add_to_group("touch_native_gui")
		slider.custom_minimum_size.y = maxf(slider.custom_minimum_size.y, 64)

func press_ui_finger(index: int, point: Vector2) -> bool:
	var controls := get_tree().get_nodes_in_group("touch_native_gui")
	controls.reverse()
	for control in controls:
		if not control.is_visible_in_tree() or not contains_point(control, point):
			continue
		if (control is BaseButton and control.disabled) or (control is Slider and not control.editable):
			return true
		ui_fingers[index] = control
		if control is BaseButton and not control.toggle_mode:
			control.set_pressed_no_signal(true)
		elif control is Slider:
			update_slider(control, point)
		return true
	return false

func release_ui_finger(index: int, point: Vector2, canceled := false) -> void:
	var control = ui_fingers.get(index)
	ui_fingers.erase(index)
	if not is_instance_valid(control) or not control is BaseButton:
		return
	if not control.toggle_mode:
		control.set_pressed_no_signal(false)
	if not canceled and control.is_visible_in_tree() and not control.disabled and contains_point(control, point):
		if control.toggle_mode:
			control.button_pressed = not control.button_pressed
		control.pressed.emit()

func update_slider(slider: Slider, point: Vector2) -> void:
	var local: Vector2 = slider.get_global_transform_with_canvas().affine_inverse() * point
	var ratio := clampf(local.x / slider.size.x, 0, 1)
	slider.value = lerpf(slider.min_value, slider.max_value, ratio)

func clear_selection() -> void:
	if is_instance_valid(selected_slot):
		selected_slot.self_modulate = Color.WHITE
	selected_slot = null

func tap_slot(slot: Control) -> void:
	if slot is StartingCookingSlot and slot.cooking_in_progress:
		return
	if is_instance_valid(selected_slot) and selected_slot != slot:
		if slot._can_drop_data(Vector2.ZERO, selected_slot):
			slot._drop_data(Vector2.ZERO, selected_slot)
			clear_selection()
	elif selected_slot == slot:
		clear_selection()
	elif slot is InventorySlot and slot.item_key != null:
		selected_slot = slot
		slot.self_modulate = Color(0.5, 1, 1)
		slot.send_description()
