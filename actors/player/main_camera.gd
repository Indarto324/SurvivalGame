extends Node3D
class_name MainCamera

@export_range(1.5, 8.0) var follow_distance := 4.0:
	set(value):
		follow_distance = clampf(value, 1.5, 8.0)
@export var rotation_smoothing := 14.0
@export var zoom_smoothing := 10.0
@export var minimum_pitch := deg_to_rad(-60.0)
@export var maximum_pitch := deg_to_rad(35.0)

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/FollowCamera
var target_yaw := 0.0
var target_pitch := -0.2
var controls_enabled := true

func _ready() -> void:
	rotation = Vector3(target_pitch, target_yaw, 0)
	spring_arm.spring_length = follow_distance
	spring_arm.add_excluded_object(get_parent().get_rid())

func rotate_view(relative: Vector2, sensitivity: float) -> void:
	if not controls_enabled:
		return
	target_yaw = wrapf(target_yaw - relative.x * sensitivity, -PI, PI)
	target_pitch = clampf(target_pitch - relative.y * sensitivity, minimum_pitch, maximum_pitch)

func zoom(amount: float) -> void:
	if controls_enabled:
		follow_distance += amount

func _physics_process(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-rotation_smoothing * delta))
	rotation.x = lerpf(rotation.x, target_pitch, 1.0 - exp(-rotation_smoothing * delta))
	spring_arm.spring_length = lerpf(spring_arm.spring_length, follow_distance, 1.0 - exp(-zoom_smoothing * delta))
