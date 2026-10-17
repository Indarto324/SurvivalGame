extends Node3D
class_name CharacterAnimator

# Presentation only: never move the player/camera/equipment or call gameplay
# callbacks. Virtual joints preserve the seven original primitive mesh nodes.
const NAMES := ["Torso", "Head", "Face", "LeftLeg", "RightLeg", "LeftArm", "RightArm"]
const HIP := Vector3(0, -0.28, 0)
const PICKUP_DURATION := 0.48
const LAND_DURATION := 0.22
var meshes: Array[MeshInstance3D] = []
var rest: Array[Transform3D] = []
var locomotion_state: StringName = &"Idle"
var action_state: StringName = &"None"
var gait_phase := 0.0
var elapsed := 0.0
var horizontal_speed := 0.0
var pickup_remaining := 0.0
var landing_remaining := 0.0
var was_grounded := true
var sampled_item_id := 0
var tool_hit_time := 0.2
var tool_sample_time := 0.0
var action_progress := 0.0

func _ready() -> void:
	for mesh_name in NAMES:
		var mesh := get_node(NodePath(mesh_name)) as MeshInstance3D
		meshes.append(mesh)
		rest.append(mesh.transform)
	EventSystem.PLA_pickup_collected.connect(begin_pickup)

func begin_pickup() -> void:
	# Emitted only by the successful inventory pickup callback, not Interact.
	pickup_remaining = PICKUP_DURATION

func advance(delta: float, actual_velocity: Vector3, grounded: bool, sprinting: bool, walk_speed: float) -> void:
	elapsed += delta
	horizontal_speed = Vector2(actual_velocity.x, actual_velocity.z).length()
	# Distance-driven cadence: a blocked player does not walk in place.
	gait_phase = fmod(gait_phase + horizontal_speed * delta * 2.8, TAU)
	if grounded and not was_grounded:
		landing_remaining = LAND_DURATION
	was_grounded = grounded
	landing_remaining = maxf(0, landing_remaining - delta)
	if not grounded:
		locomotion_state = &"Jump" if actual_velocity.y > 0.1 else &"Fall"
	elif landing_remaining > 0:
		locomotion_state = &"Landing"
	elif horizontal_speed > 0.08:
		locomotion_state = &"Sprint" if sprinting and horizontal_speed > walk_speed * 0.95 else &"Walk"
	else:
		locomotion_state = &"Idle"

	var moving := grounded and horizontal_speed > 0.08
	var running := locomotion_state == &"Sprint"
	var stride := minf(horizontal_speed / maxf(walk_speed, 0.1), 1.5) if moving else 0.0
	var swing := sin(gait_phase) * (0.65 if running else 0.5) * stride
	var bob := absf(sin(gait_phase)) * 0.045 * stride if running else -0.6 * (1.0 - cos(swing))
	var leg_length := 1.0
	var body := Vector3(-0.16 if running else -0.035 * stride, 0, sin(gait_phase) * 0.025 * stride)
	if not moving and grounded:
		body.y += sin(elapsed * 0.7) * 0.006
		body.z += sin(elapsed * 0.9) * 0.008
	var left_leg := Vector3(swing, 0, 0)
	var right_leg := Vector3(-swing, 0, 0)
	var left_arm := Vector3(-swing * 0.85, 0, -0.04)
	var right_arm := Vector3(swing * 0.85, 0, 0.04)
	if not grounded:
		var rising := locomotion_state == &"Jump"
		left_leg.x = 0.6 if rising else 0.15
		right_leg.x = -0.2 if rising else -0.1
		left_arm = Vector3(0.4, 0, -0.35)
		right_arm = Vector3(0.4, 0, 0.35)
		bob = 0
		body.x = -0.08 if rising else 0.06
	if landing_remaining > 0 and grounded:
		var compression := sin(PI * (1.0 - landing_remaining / LAND_DURATION))
		bob -= compression * 0.1
		leg_length -= compression * 0.14
		body.x -= compression * 0.16
		left_leg.x += compression * 0.25
		right_leg.x += compression * 0.25

	action_state = &"None"
	action_progress = 0
	var holder := get_parent().get_node("EquipmentPivot/ItemHolder") as ItemHolder
	var item := holder.current_item_scene
	if item is EquippableWeapon and item.animation_player.is_playing() and item.animation_player.current_animation == "use_item":
		action_state = &"Chop"
		var anim := item.animation_player.get_animation("use_item")
		if sampled_item_id != item.get_instance_id():
			sampled_item_id = item.get_instance_id()
			tool_hit_time = anim.length * 0.3
			for track in anim.get_track_count():
				if anim.track_get_type(track) == Animation.TYPE_METHOD:
					for key in anim.track_get_key_count(track):
						if anim.method_track_get_name(track, key) == &"check_hit":
							tool_hit_time = anim.track_get_key_time(track, key)
		tool_sample_time = item.animation_player.current_animation_position
		action_progress = clampf(tool_sample_time / maxf(anim.length, 0.001), 0, 1)
		var windup := maxf(tool_hit_time * 0.5, 0.001)
		if tool_sample_time < windup:
			right_arm.x = lerpf(0.25, 2.3, tool_sample_time / windup)
		elif tool_sample_time < tool_hit_time:
			right_arm.x = lerpf(2.3, 0.9, (tool_sample_time - windup) / maxf(tool_hit_time - windup, 0.001))
		else:
			right_arm.x = lerpf(0.9, 0.25, (tool_sample_time - tool_hit_time) / maxf(anim.length - tool_hit_time, 0.001))
		var power := sin(action_progress * PI)
		body.y = (action_progress * 0.8 - 0.4) * power
		body.x -= 0.16 * power
		left_arm.x = 0.45 * power
		right_arm.z = 0.15 * power
	else:
		sampled_item_id = 0
		if item is EquippableWeapon:
			right_arm.x = 0.25 + swing * 0.15
		if pickup_remaining > 0:
			action_state = &"Pickup"
			action_progress = 1.0 - pickup_remaining / PICKUP_DURATION
			var reach := sin(action_progress * PI)
			body.x -= reach * 0.65
			right_arm.x = reach * 1.0
			left_arm.x = reach * 0.25
			bob -= reach * 0.04
			leg_length -= reach * 0.06
	if action_state != &"Chop":
		pickup_remaining = maxf(0, pickup_remaining - delta)

	var upper := Basis.from_euler(body)
	var breath := sin(elapsed * 2.2) * 0.012
	var blend := 1.0 - exp(-24.0 * delta)
	for index in meshes.size():
		var pivot := HIP
		var angles := Vector3.ZERO
		match index:
			3:
				pivot = Vector3(-0.13, -0.28, 0)
				angles = left_leg
			4:
				pivot = Vector3(0.13, -0.28, 0)
				angles = right_leg
			5:
				pivot = Vector3(-0.34, 0.36, 0)
				angles = left_arm
			6:
				pivot = Vector3(0.34, 0.36, 0)
				angles = right_arm
		var joint := Basis.from_euler(angles)
		var offset := rest[index].origin - pivot
		var limb_scale := Vector3.ONE
		if index == 3 or index == 4:
			offset.y *= leg_length
			limb_scale.y = leg_length
		var point := pivot + joint * offset
		var basis := joint * rest[index].basis.scaled(limb_scale)
		if index != 3 and index != 4:
			point = HIP + upper * (point - HIP)
			basis = upper * basis
		if index == 0:
			basis = basis.scaled(Vector3(1, 1 + breath, 1))
		if index == 1 or index == 2:
			point.y += breath * 0.4
		point.y += bob
		meshes[index].transform = meshes[index].transform.interpolate_with(Transform3D(basis, point), blend)
