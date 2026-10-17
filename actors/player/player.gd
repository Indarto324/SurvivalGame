extends CharacterBody3D
class_name Player


@export var normal_speed := 3.0
@export var sprint_speed := 5.0
@export var walking_energy_consumption_per_1m := -0.05
@export var jump_velocity := 4.0
@export var gravity := 12.0
@export var mouse_sensitivity := 0.005
@export var walking_footstep_audio_interval := 0.6
@export var sprinting_footstep_audio_interval := 0.3

@onready var camera_rig: MainCamera = $CameraRig
@onready var character_visuals: Node3D = $CharacterVisuals
@onready var equipment_pivot: Node3D = $EquipmentPivot
@onready var interaction_ray_cast: RayCast3D = %InteractionRayCast
@onready var item_holder: Node3D = %ItemHolder
@onready var footstep_audio_timer: Timer = $FootstepAudioTimer


var is_grounded := true
var is_sprinting := false


func _enter_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	EventSystem.PLA_freeze_player.connect(set_freeze.bind(true))
	EventSystem.PLA_unfreeze_player.connect(set_freeze.bind(false))


func _ready() -> void:
	EventSystem.HUD_show_hud.emit()


func _exit_tree() -> void:
	EventSystem.HUD_hide_hud.emit()


func set_freeze(freeze:bool) -> void:
	set_process(!freeze)
	set_physics_process(!freeze)
	set_process_input(!freeze)
	set_process_unhandled_key_input(!freeze)
	camera_rig.controls_enabled = not freeze
	if freeze:
		interaction_ray_cast.clear_prompt()


func _process(_delta: float) -> void:
	interaction_ray_cast.check_interaction()


func _physics_process(delta: float) -> void:
	move(delta)
	check_walking_consumption(delta)
	
	if Input.is_action_just_pressed("use_equipped_item"):
		character_visuals.rotation.y = camera_rig.rotation.y
		equipment_pivot.rotation = camera_rig.rotation
		item_holder.try_to_use_item()


func move(delta: float) -> void:
	if is_on_floor():
		is_sprinting = Input.is_action_pressed("sprint")
		
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
		
		if velocity != Vector3.ZERO and footstep_audio_timer.is_stopped():
			EventSystem.SFX_play_dynamic_sfx.emit(SFXConfig.Keys.Footstep, global_position, 0.3)
			footstep_audio_timer.start(walking_footstep_audio_interval if not is_sprinting else sprinting_footstep_audio_interval)
		
		if not is_grounded:
			is_grounded = true
			EventSystem.SFX_play_dynamic_sfx.emit(SFXConfig.Keys.JumpLand, global_position)
	
	else:
		velocity.y -= gravity * delta
		
		if is_grounded:
			is_grounded = false
	
	var speed := normal_speed if not is_sprinting else sprint_speed
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (Basis(Vector3.UP, camera_rig.global_rotation.y) * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if not direction.is_zero_approx():
		character_visuals.rotation.y = lerp_angle(character_visuals.rotation.y, atan2(-direction.x, -direction.z) - global_rotation.y, 1.0 - exp(-15.0 * delta))
	if item_holder.current_item_scene is EquippableConstructable:
		equipment_pivot.rotation = camera_rig.rotation
	else:
		equipment_pivot.rotation = Vector3(camera_rig.rotation.x, character_visuals.rotation.y, 0)
	
	velocity.z = direction.z * speed
	velocity.x = direction.x * speed
	
	move_and_slide()


func check_walking_consumption(delta:float) -> void:
	if velocity.z or velocity.x:
		EventSystem.PLA_change_energy.emit(
			delta *
			walking_energy_consumption_per_1m *
			Vector2(velocity.z, velocity.x).length()
		)


func _input(event) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_rig.zoom(-0.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_rig.zoom(0.5)
	if event is InputEventMouseMotion:
		look_around(event.relative)


func look_around(relative:Vector2):
	camera_rig.rotate_view(relative, mouse_sensitivity)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		EventSystem.BUL_create_bulletin.emit(BulletinConfig.Keys.PauseMenu)
	
	elif event.is_action_pressed("open_crafting_menu"):
		EventSystem.BUL_create_bulletin.emit(BulletinConfig.Keys.CraftingMenu)
	
	elif event.is_action_pressed("item_hotkey"):
		EventSystem.EQU_hotkey_pressed.emit(int(event.as_text()))
