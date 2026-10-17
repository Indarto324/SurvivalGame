extends RayCast3D
class_name InteractionRayCast

@export var interaction_distance := 2.4
@onready var player: Player = get_parent()
var current_interactable: Interactable
var prompt_visible := false
var pickup_search := SphereShape3D.new()

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

func resolve_interactable(collider: Object) -> Interactable:
	if collider is Interactable:
		return collider
	if collider is RigidBody3D:
		return collider.get_node_or_null("Pickuppable") as Interactable
	return null

func nearby_touch_target() -> Interactable:
	# Ground pickups are far smaller than a finger's aiming precision. Search
	# only within player reach and the forward camera cone, never through solids.
	pickup_search.radius = interaction_distance
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = pickup_search
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = 4
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var forward := -player.camera_rig.camera.global_basis.z
	forward.y = 0
	forward = forward.normalized()
	var best: Interactable
	var best_score := INF
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var candidate := hit.collider as Interactable
		if not is_instance_valid(candidate) or candidate.is_queued_for_deletion() or candidate.get_parent().is_queued_for_deletion():
			continue
		var shape := candidate.get_node_or_null("CollisionShape3D") as CollisionShape3D
		var point := candidate.global_position if shape == null else shape.global_position
		var offset := point - global_position
		if offset.length() > interaction_distance:
			continue
		var planar := Vector3(offset.x, 0, offset.z).normalized()
		var alignment := forward.dot(planar)
		if alignment < 0.5:
			continue
		var camera := player.camera_rig.camera
		if camera.is_position_behind(point) or not get_viewport().get_visible_rect().has_point(camera.unproject_position(point)):
			continue
		var score := (1.0 - alignment) * 3.0 + offset.length()
		if score >= best_score:
			continue
		var sight := PhysicsRayQueryParameters3D.create(global_position, point, collision_mask)
		sight.collide_with_areas = true
		sight.exclude = [player.get_rid()]
		var obstruction := get_world_3d().direct_space_state.intersect_ray(sight)
		if not obstruction.is_empty() and resolve_interactable(obstruction.collider) != candidate:
			continue
		best = candidate
		best_score = score
	return best

func check_interaction() -> void:
	var interact_requested := MobileInput.just_pressed("interact")
	update_aim()
	var target := resolve_interactable(get_collider()) if is_colliding() else null
	if target == null and MobileInput.enabled:
		target = nearby_touch_target()
	if target != current_interactable or (prompt_visible and not is_instance_valid(target)):
		clear_prompt()
		current_interactable = target
		if is_instance_valid(target):
			prompt_visible = true
			EventSystem.BUL_create_bulletin.emit(BulletinConfig.Keys.InteractionPrompt, target.prompt)
	MobileInput.set_interaction_target(target)
	if is_instance_valid(target) and interact_requested:
		target.start_interaction()

func clear_prompt() -> void:
	MobileInput.set_interaction_target(null)
	if prompt_visible:
		EventSystem.BUL_destroy_bulletin.emit(BulletinConfig.Keys.InteractionPrompt)
	prompt_visible = false
	current_interactable = null

func _exit_tree() -> void:
	clear_prompt()
