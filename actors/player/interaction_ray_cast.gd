extends RayCast3D
class_name InteractionRayCast

@export var interaction_distance := 2.4
@onready var player: Player = get_parent()
var current_interactable: Interactable
var prompt_visible := false

func _ready() -> void:
	add_exception(player)

func update_aim() -> void:
	var camera := player.camera_rig.camera
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,
		camera.global_position - camera.global_basis.z * (camera.global_position.distance_to(global_position) + interaction_distance), collision_mask)
	query.collide_with_areas = true
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var aim_point: Vector3 = query.to if hit.is_empty() else hit.position
	var offset := aim_point - global_position
	# Cross the aimed surface slightly to avoid ending exactly on its boundary.
	offset += offset.normalized() * 0.05
	target_position = to_local(global_position + offset.limit_length(interaction_distance))
	force_raycast_update()

func check_interaction() -> void:
	var interact_requested := MobileInput.just_pressed("interact")
	update_aim()
	var target: Interactable = get_collider() as Interactable if is_colliding() else null
	if target != current_interactable or (prompt_visible and not is_instance_valid(target)):
		clear_prompt()
		current_interactable = target
		if is_instance_valid(target):
			prompt_visible = true
			EventSystem.BUL_create_bulletin.emit(BulletinConfig.Keys.InteractionPrompt, target.prompt)
	if is_instance_valid(target) and interact_requested:
		target.start_interaction()

func clear_prompt() -> void:
	if prompt_visible:
		EventSystem.BUL_destroy_bulletin.emit(BulletinConfig.Keys.InteractionPrompt)
	prompt_visible = false
	current_interactable = null

func _exit_tree() -> void:
	clear_prompt()
