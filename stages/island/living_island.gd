extends Node3D

var world: ExpandedIsland
var animals: Array[Animal] = []
var active_ai_count := 0
var night := false
var coast_mix := 0.0
var music: AudioStreamPlayer
var original_music_db := 0.0
var surf: AudioStreamPlayer
var timer: Timer

func _ready() -> void:
	world = get_parent() as ExpandedIsland
	setup.call_deferred()

func setup() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var actor_root := world.get_node("../../Actors")
	for child in actor_root.get_children():
		if child is Animal:
			animals.append(child)
			child.terrain = world
	# Reuse, rather than increase, the original population. Four cows and one
	# wolf keep their original homes; five occupy safe expansion territories.
	var territories := world.WILDLIFE_HOMES
	for animal in animals:
		if territories.has(String(animal.name)):
			var p: Vector2 = territories[String(animal.name)]
			if animal.ground_safe(Vector3(p.x,0,p.y)):
				animal.global_position = Vector3(p.x,world.surface_height(p)+.15,p.y)
				animal.home = animal.global_position
	build_pois()
	surf = AudioStreamPlayer.new()
	surf.name = "CoastalAmbience"
	surf.stream = preload("res://audio/music/coastal_surf.wav").duplicate()
	surf.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	surf.bus = "Music"
	surf.volume_db = -40
	add_child(surf)
	surf.play()
	music = get_tree().get_first_node_in_group("IslandMusic") as AudioStreamPlayer
	if is_instance_valid(music): original_music_db = music.volume_db
	timer = Timer.new()
	timer.wait_time = .5
	timer.timeout.connect(update_ecosystem)
	add_child(timer)
	timer.start()
	update_ecosystem()

func update_ecosystem() -> void:
	var player := get_tree().get_first_node_in_group("Player") as Node3D
	if not is_instance_valid(player): return
	var cycle: AnimationPlayer = world.get_node("../../DayNightCycleAnimationPlayer")
	var hour := cycle.current_animation_position
	night = hour<12.0 or hour>22.6
	active_ai_count = 0
	for animal in animals:
		if not is_instance_valid(animal) or animal.state == Animal.States.Dead: continue
		animal.night = night
		var distance := animal.global_position.distance_to(player.global_position)
		var should_activate := distance<(70.0 if animal.active else 55.0)
		animal.set_active(should_activate)
		if should_activate: active_ai_count += 1
	var p := Vector2(player.global_position.x,player.global_position.z)
	coast_mix = 1.0 if world.biome_at(p) in ["beach","rocky_coast"] else 0.0
	surf.volume_db = lerpf(surf.volume_db,(-19.0 if coast_mix>0 else -38.0),.25)
	if is_instance_valid(music):
		music.volume_db = lerpf(music.volume_db,original_music_db+(-8.0 if coast_mix>0 else (-5.0 if night else 0.0)),.25)

func build_pois() -> void:
	var mesh := PrismMesh.new()
	mesh.size = Vector3(.6,.8,.6)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.52,.46,.30)
	mesh.material = material
	for title in world.POIS:
		var p: Vector2 = world.POIS[title]
		var root := Node3D.new()
		root.name = title.replace(" ","")
		add_child(root)
		root.position = Vector3(p.x,world.surface_height(p),p.y)
		# Markers stay off collision/navigation and leave the clearing buildable.
		for i in 3:
			var stone := MeshInstance3D.new()
			stone.mesh = mesh
			stone.position = Vector3(.5*i,.4,1.2)
			stone.visibility_range_end = 55
			stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(stone)
		var label := Label3D.new()
		label.text = title
		label.position.y = 2
		label.pixel_size = .008
		label.font_size = 32
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.visibility_range_end = 40
		root.add_child(label)

func _exit_tree() -> void:
	if is_instance_valid(music): music.volume_db = original_music_db
