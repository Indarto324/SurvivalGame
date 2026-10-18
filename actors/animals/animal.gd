extends CharacterBody3D
class_name Animal

const ANIM_BLEND_TIME := 0.2
const GRAVITY := 12.0
# Keep the original combat state values; append presentation/behavior states.
enum States { Idle, Wander, Dead, Flee, Hurt, Chase, Attack, Graze, Rest }
var state := States.Idle
@onready var idle_timer: Timer = $Timers/IdleTimer
@onready var wander_timer: Timer = $Timers/WanderTimer
@onready var disappear_after_death_timer: Timer = $Timers/DisappearAfterDeathTimer
@onready var flee_timer: Timer = $Timers/FleeTimer
@onready var player: CharacterBody3D = get_tree().get_first_node_in_group("Player")
@onready var main_collision_shape: CollisionShape3D = $CollisionShape3D
@onready var meat_spawn_marker: Marker3D = $MeatSpawnMarker
@onready var eyes_marker: Marker3D = $EyesMarker
@onready var attack_hit_area: Area3D = $AttackHitArea
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var animation_player: AnimationPlayer = %AnimationPlayer
@onready var vision_area_collision_shape: CollisionShape3D = $VisionArea/CollisionShape3D
@export var normal_speed := 0.6
@export var alarmed_speed := 1.8
@export var max_health := 80
@export var idle_animations: Array[String] = []
@export var hurt_animations: Array[String] = []
@export var turn_speed_weight := 0.07
@export var min_idle_time := 2.0
@export var max_idle_time := 7.0
@export var min_wander_time := 2.0
@export var max_wander_time := 4.0
@export var flee_time := 3.0
@export var is_aggressive := false
@export var attack_distance := 2.0
@export var damage := 20.0
@export var vision_range := 15.0
@export var vision_fov := 80.0
@export var attack_audio_key := SFXConfig.Keys.WolfAttack
var player_in_vision_range := false
@onready var health := max_health
var terrain: ExpandedIsland
var home := Vector3.ZERO
var home_radius := 14.0
var active := false
var night := false
var decision_elapsed := 0.0
var decisions := 0
var physics_ticks := 0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("Wildlife")
	rng.seed = hash(name)
	home = global_position
	home_radius = 24.0 if is_aggressive else 14.0
	# These animals use a feet-level origin; the voxelized path sits above it.
	nav_agent.path_height_offset = .5
	nav_agent.path_desired_distance = .35
	nav_agent.target_desired_distance = .6
	vision_area_collision_shape.shape = vision_area_collision_shape.shape.duplicate()
	vision_area_collision_shape.shape.radius = vision_range
	animation_player.animation_finished.connect(animation_finished)
	for geometry in find_children("*","GeometryInstance3D",true,false):
		geometry.visibility_range_end = 95
	set_state(States.Idle)
	set_active(false)

func set_active(value: bool) -> void:
	if state == States.Dead: return
	active = value
	set_physics_process(value)
	animation_player.active = value
	for timer in [idle_timer,wander_timer,flee_timer]: timer.paused = not value
	if not value: velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
	physics_ticks += 1
	decision_elapsed += delta
	if decision_elapsed >= .25:
		decision_elapsed = 0
		think()
	if state in [States.Wander,States.Flee,States.Chase]:
		var waypoint := nav_agent.get_next_path_position() if nav_ready() else global_position
		if not nav_ready() or nav_agent.is_navigation_finished():
			velocity.x = 0
			velocity.z = 0
			if state in [States.Wander,States.Flee]: set_state(States.Idle)
		else:
			var direction := global_position.direction_to(waypoint)
			direction.y = 0
			direction = direction.normalized()
			var speed := alarmed_speed if state in [States.Flee,States.Chase] else normal_speed
			velocity.x = direction.x*speed
			velocity.z = direction.z*speed
			if not direction.is_zero_approx():
				rotation.y = lerp_angle(rotation.y,atan2(direction.x,direction.z)+PI,1.0-exp(-6.0*delta))
	else:
		velocity.x = 0
		velocity.z = 0
		if state == States.Attack and is_instance_valid(player):
			var direction := global_position.direction_to(player.global_position)
			rotation.y = lerp_angle(rotation.y,atan2(direction.x,direction.z)+PI,1.0-exp(-6.0*delta))
	apply_gravity(delta)
	move_and_slide()

func think() -> void:
	decisions += 1
	if not is_instance_valid(player): return
	if state in [States.Dead,States.Hurt,States.Attack]: return
	if state == States.Chase:
		if not pursuit_allowed():
			set_state(States.Wander)
			set_goal(home)
		elif global_position.distance_to(player.global_position)<attack_distance:
			set_state(States.Attack)
		else:
			if not set_goal(player.global_position): set_state(States.Idle)
	elif is_aggressive and can_see_player():
		set_state(States.Chase)
	elif not is_aggressive and state in [States.Idle,States.Graze,States.Rest,States.Wander] and global_position.distance_to(player.global_position)<3.5 and player_in_los():
		set_state(States.Flee)
	if state in [States.Wander,States.Flee,States.Chase]:
		var forward := Vector3(velocity.x,0,velocity.z).normalized()
		if not ground_safe(global_position+forward*1.4): set_state(States.Idle)

func nav_ready() -> bool:
	return NavigationServer3D.map_get_iteration_id(nav_agent.get_navigation_map())>0

func ground_safe(point: Vector3) -> bool:
	if not is_instance_valid(terrain): return false
	var p := Vector2(point.x,point.z)
	if absf(p.x)>180 or absf(p.y)>180 or p.distance_to(terrain.POND)<24: return false
	var h := terrain.surface_height(p)
	var dx := (terrain.surface_height(p+Vector2(.5,0))-h)*2
	var dz := (terrain.surface_height(p+Vector2(0,.5))-h)*2
	return h>=-.5 and Vector2(dx,dz).length()<tan(deg_to_rad(35.0))

func route_safe(path: PackedVector3Array) -> bool:
	if path.is_empty(): return false
	var probes := 0
	for i in path.size()-1:
		var count := maxi(1,ceili(path[i].distance_to(path[i+1])/2.0))
		for j in count+1:
			probes += 1
			if probes>64 or not ground_safe(path[i].lerp(path[i+1],float(j)/count)): return false
	return true

func set_goal(point: Vector3) -> bool:
	if not nav_ready() or not ground_safe(point): return false
	var closest := NavigationServer3D.map_get_closest_point(nav_agent.get_navigation_map(),point)
	if Vector2(closest.x-point.x,closest.z-point.z).length()>1.5: return false
	var path := NavigationServer3D.map_get_path(nav_agent.get_navigation_map(),global_position,closest,true)
	if path.is_empty() or path[-1].distance_to(closest)>1 or not route_safe(path): return false
	nav_agent.target_position = closest
	return true

func pick_wander_velocity() -> void:
	for attempt in 6:
		var angle := rng.randf_range(0,TAU)
		var target := home+Vector3(cos(angle),0,sin(angle))*rng.randf_range(3,home_radius)
		if is_instance_valid(terrain): target.y = terrain.surface_height(Vector2(target.x,target.z))
		if set_goal(target): return
	nav_agent.target_position = global_position

func pick_away_from_player_velocity() -> void:
	if not is_instance_valid(player): return
	var away := (global_position-player.global_position).normalized()
	for angle in [0.0,.6,-.6,1.2,-1.2]:
		var target := global_position+away.rotated(Vector3.UP,angle)*6
		if target.distance_to(home)>home_radius+8: continue
		if is_instance_valid(terrain): target.y = terrain.surface_height(Vector2(target.x,target.z))
		if set_goal(target): return
	nav_agent.target_position = global_position

func pursuit_allowed() -> bool:
	return is_instance_valid(player) and global_position.distance_to(player.global_position)<=26 and player.global_position.distance_to(home)<=home_radius+12 and ground_safe(player.global_position)

func can_see_player() -> bool:
	return is_instance_valid(player) and global_position.distance_to(player.global_position)<=vision_range and pursuit_allowed() and player_in_fov() and player_in_los()

func player_in_fov() -> bool:
	if not is_instance_valid(player): return false
	return global_position.direction_to(player.global_position).angle_to(-global_transform.basis.z)<=deg_to_rad(vision_fov*.5)

func player_in_los() -> bool:
	if not is_instance_valid(player): return false
	var query := PhysicsRayQueryParameters3D.create(eyes_marker.global_position,player.global_position+Vector3(0,.5,0),65)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func apply_gravity(delta := 1.0/60.0) -> void:
	velocity.y = 0 if is_on_floor() else velocity.y-GRAVITY*delta

func set_state(new_state: States) -> void:
	if state == States.Dead: return
	state = new_state
	for timer in [idle_timer,wander_timer,flee_timer]: timer.stop()
	match state:
		States.Idle:
			idle_timer.start(rng.randf_range(min_idle_time,max_idle_time))
			animation_player.play("Idle",ANIM_BLEND_TIME)
		States.Graze:
			idle_timer.start(rng.randf_range(5,9))
			animation_player.play("Eating",ANIM_BLEND_TIME)
		States.Rest:
			idle_timer.start(rng.randf_range(7,12))
			animation_player.play("Idle_2" if is_aggressive else "Idle_Headlow",ANIM_BLEND_TIME)
		States.Wander:
			pick_wander_velocity()
			wander_timer.start(rng.randf_range(min_wander_time,max_wander_time))
			animation_player.play("Walk",ANIM_BLEND_TIME)
		States.Hurt:
			animation_player.play(hurt_animations.pick_random(),ANIM_BLEND_TIME)
		States.Flee:
			pick_away_from_player_velocity()
			flee_timer.start(flee_time)
			animation_player.play("Gallop",ANIM_BLEND_TIME)
		States.Chase:
			set_goal(player.global_position)
			animation_player.play("Gallop",ANIM_BLEND_TIME)
		States.Attack:
			animation_player.play("Attack",ANIM_BLEND_TIME)
		States.Dead:
			main_collision_shape.set_deferred("disabled",true)
			animation_player.play("Death",ANIM_BLEND_TIME)
			EventSystem.SPA_spawn_scene.emit(ItemConfig.get_pickuppable_item_scene(ItemConfig.Keys.RawMeat),meat_spawn_marker.global_transform)
			set_physics_process(false)
			disappear_after_death_timer.start()

func animation_finished(_animation: StringName) -> void:
	match state:
		States.Hurt: set_state(States.Chase if is_aggressive and pursuit_allowed() else States.Flee)
		States.Attack: set_state(States.Chase if pursuit_allowed() else States.Idle)
		States.Idle: animation_player.play("Idle",ANIM_BLEND_TIME)
		States.Graze: animation_player.play("Eating",ANIM_BLEND_TIME)
		States.Rest: animation_player.play("Idle_2" if is_aggressive else "Idle_Headlow",ANIM_BLEND_TIME)

func _on_idle_timer_timeout() -> void:
	if state not in [States.Idle,States.Graze,States.Rest]: return
	var choice := rng.randf()
	set_state(States.Rest if night and choice<.7 else (States.Graze if not is_aggressive and choice<.5 else States.Wander))
func _on_wander_timer_timeout() -> void:
	if state == States.Wander: set_state(States.Idle)
func _on_flee_timer_timeout() -> void:
	if state == States.Flee: set_state(States.Idle)
func _on_disappear_after_death_timer_timeout() -> void: queue_free()
func attack() -> void:
	# Only the existing equipment/animal animation method track causes damage.
	if state == States.Attack and is_instance_valid(player) and global_position.distance_to(player.global_position)<attack_distance+.75 and player in attack_hit_area.get_overlapping_bodies():
		EventSystem.PLA_change_health.emit(-damage)
func play_attack_audio() -> void: EventSystem.SFX_play_dynamic_sfx.emit(attack_audio_key,global_position)
func take_hit(weapon: WeaponItemResource) -> void:
	if state == States.Dead: return
	set_active(true)
	health -= weapon.damage
	if health<=0: set_state(States.Dead)
	elif state != States.Flee: set_state(States.Hurt)
func _on_vision_area_body_entered(body: Node3D) -> void:
	if body == player: player_in_vision_range = true
func _on_vision_area_body_exited(body: Node3D) -> void:
	if body == player: player_in_vision_range = false
