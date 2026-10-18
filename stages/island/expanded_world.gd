extends Node3D
class_name ExpandedIsland

# All terrain physics stays resident. Only new details stream: flying/teleports
# never outrun the ground, and the original scatter/animal systems keep ownership.
const HALF_SIZE := 192.0
const CHUNK_SIZE := 32.0
const STEP := 4.0
const DETAIL_RADIUS := 80.0
const UNLOAD_RADIUS := 112.0
const POND := Vector2(105, -62)
const PATH := [Vector2(36, 30), Vector2(70, 24), Vector2(104, 12), Vector2(112, -22), Vector2(76, -40), Vector2(75, -67), Vector2(95, -96), Vector2(90, -112), Vector2(69, -105)]
const POIS := {"Main Beach Camp":Vector2(-23,37),"Deep Jungle":Vector2(119,24),"Northern Viewpoint":Vector2(69,-105),"Freshwater Spring":Vector2(105,-36),"Rocky Coast Viewpoint":Vector2(128,53)}
const WILDLIFE_HOMES := {"Cow5":Vector2(98,29),"Cow6":Vector2(79,-48),"Cow7":Vector2(126,66),"Wolf2":Vector2(95,-96),"Wolf3":Vector2(115,-8)}
const SCENES := {
	"tree": preload("res://objects/hittable_objects/hittable_tree.tscn"),
	"fruit": preload("res://objects/fruit_bush.tscn"),
	"coal": preload("res://objects/hittable_objects/hittable_coal_boulder.tscn"),
	"flint": preload("res://objects/hittable_objects/hittable_flintstone_boulder.tscn"),
	"stick": preload("res://interactables/pickuppables/pickuppable_stick.tscn"),
	"stone": preload("res://interactables/pickuppables/pickuppable_stone.tscn"),
	"plant": preload("res://interactables/pickuppables/pickuppable_plant.tscn"),
	"mushroom": preload("res://interactables/pickuppables/pickuppable_mushroom.tscn")
}
var chunks := {}
var manifests := {}
var live_details := {}
var dormant_details := {}
var original_faces := PackedVector3Array()
var old_heights := {}
var original_cells := {}
var grid_x: Array = []
var grid_z: Array = []
var material: StandardMaterial3D
var elapsed := 0.0
var detail_queue: Array[Vector2i] = []
var terrain_triangles := 0
var grass_instances := 0
var ready_for_play := false
var nav_dirty := false
var nav_refresh_at := 0
var recovery_spawn := Vector3.ZERO
var tracked_player: Player

func _ready() -> void:
	recovery_spawn = get_node("../../Actors/Player").position
	var old_terrain: MeshInstance3D = get_parent().get_node("Terrain")
	var old_collision: CollisionShape3D = old_terrain.get_node("StaticBody3D/CollisionShape3D")
	original_faces = (old_collision.shape as ConcavePolygonShape3D).get_faces()
	cache_original_grid()
	material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	for x in range(-6,6):
		for z in range(-6,6):
			build_chunk(Vector2i(x,z))
	# Replace presentation/physics only after every new collider exists. The
	# authored terrain asset stays intact and supplies the protected core heights.
	old_terrain.hide()
	old_collision.disabled = true
	build_ocean_boundary()
	build_pond()
	build_landmarks()
	build_manifests()
	var living = preload("res://stages/island/living_island.gd").new()
	living.name = "LivingIsland"
	add_child(living)
	ready_for_play = true
	refresh_details()

func cache_original_grid() -> void:
	for vertex in original_faces:
		old_heights[Vector2(vertex.x,vertex.z)] = vertex.y
		if not grid_x.has(vertex.x): grid_x.append(vertex.x)
		if not grid_z.has(vertex.z): grid_z.append(vertex.z)
	grid_x.sort()
	grid_z.sort()
	for i in range(0,original_faces.size(),3):
		var center := (original_faces[i]+original_faces[i+1]+original_faces[i+2])/3
		var key := Vector2i(clampi(grid_x.bsearch(center.x)-1,0,grid_x.size()-2),clampi(grid_z.bsearch(center.z)-1,0,grid_z.size()-2))
		if not original_cells.has(key): original_cells[key] = []
		original_cells[key].append(i)

func original_height(p: Vector2) -> float:
	if absf(p.x)>150 or absf(p.y)>150: return -5.0
	var key := Vector2i(clampi(grid_x.bsearch(p.x)-1,0,grid_x.size()-2),clampi(grid_z.bsearch(p.y)-1,0,grid_z.size()-2))
	for i in original_cells.get(key,[]):
		var a := original_faces[i]
		var b := original_faces[i+1]
		var c := original_faces[i+2]
		var v0 := Vector2(b.x-a.x,b.z-a.z)
		var v1 := Vector2(c.x-a.x,c.z-a.z)
		var v2 := p-Vector2(a.x,a.z)
		var denominator := v0.cross(v1)
		if absf(denominator)<.00001: continue
		var u := v2.cross(v1)/denominator
		var v := v0.cross(v2)/denominator
		if u>=-.001 and v>=-.001 and u+v<=1.001:
			return a.y+u*(b.y-a.y)+v*(c.y-a.y)
	return -5.0

func path_distance(p: Vector2) -> float:
	var closest := INF
	for i in PATH.size()-1:
		closest = minf(closest,p.distance_to(Geometry2D.get_closest_point_to_segment(p,PATH[i],PATH[i+1])))
	return closest

func height_at(p: Vector2) -> float:
	var cache_key := Vector2(p.x,p.y)
	if old_heights.has(cache_key) and p.x >= -45 and p.x <= 55 and absf(p.y)<=65:
		return old_heights[cache_key]
	var original := original_height(p) if absf(p.x)<=150 and absf(p.y)<=150 else -5.0
	# Connected east/north extension. Preserve the spawn/core and its west beach;
	# broad smooth blends avoid artificial ledges at the old shoreline.
	var ellipse := Vector2((p.x-30)/135.0,(p.y+18)/155.0).length()
	var coast := smoothstep(.76,1.0,ellipse)
	var base := lerpf(2.8,-5.0,coast)
	var hills := 14.0*exp(-pow((p-Vector2(68,-108)).length()/39.0,2))
	hills += 9.0*exp(-pow((p-Vector2(129,42)).length()/32.0,2))
	var target := base+hills*(1.0-coast)
	# Spring pool has a level basin, shallow shore and a walkable perimeter.
	var pond_distance := p.distance_to(POND)

	var protection := maxf(smoothstep(45.0,95.0,p.x),smoothstep(64.0,114.0,-p.y))
	if p.x<0: protection *= smoothstep(-65.0,-35.0,p.x)
	var result := lerpf(original,maxf(original,target),protection)
	var basin := lerpf(.5,2.8,smoothstep(8.0,22.0,pond_distance))
	return lerpf(basin,result,smoothstep(22.0,48.0,pond_distance))

func surface_height(p: Vector2) -> float:
	# Match the actual two collision triangles, including fractional positions.
	var origin := (p/STEP).floor()*STEP
	var uv := (p-origin)/STEP
	var a := height_at(origin)
	var b := height_at(origin+Vector2(STEP,0))
	var c := height_at(origin+Vector2(0,STEP))
	var d := height_at(origin+Vector2(STEP,STEP))
	return a+(b-a)*uv.x+(c-a)*uv.y if uv.x+uv.y<=1.0 else d+(c-d)*(1.0-uv.x)+(b-d)*(1.0-uv.y)

func terrain_color(p: Vector2, height: float) -> Color:
	if height < -1.0: return Color(.64,.60,.43)
	if height < -.05: return Color(.82,.73,.48)
	if p.x<50 and absf(p.y)<60 and height>=-.01: return Color(.39,.49,.21)
	if p.x>112 and p.y>35: return Color(.37,.41,.37)
	if height>12: return Color(.44,.48,.34)
	if p.distance_to(POND)<30: return Color(.35,.50,.26)
	if path_distance(p)<3.0 and p.x>40: return Color(.62,.52,.32)
	return Color(.20,.38,.16) if p.x>55 else Color(.39,.49,.21)

func build_chunk(key: Vector2i) -> void:
	var root := Node3D.new()
	root.name = "Terrain_%d_%d" % [key.x,key.y]
	add_child(root)
	root.position = Vector3(key.x*CHUNK_SIZE,0,key.y*CHUNK_SIZE)
	chunks[key] = root
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for x in 8:
		for z in 8:
			var points: Array[Vector3] = []
			for offset in [Vector2(x,z),Vector2(x+1,z),Vector2(x,z+1),Vector2(x+1,z+1)]:
				var p: Vector2 = Vector2(key)*CHUNK_SIZE + offset*STEP
				points.append(Vector3(offset.x*STEP,height_at(p),offset.y*STEP))
			for index in [0,1,2,1,3,2]:
				var vertex: Vector3 = points[index]
				var world_point := Vector2(vertex.x+root.position.x,vertex.z+root.position.z)
				st.set_color(terrain_color(world_point,vertex.y))
				st.add_vertex(vertex)
				faces.append(vertex)
			terrain_triangles += 2
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = material
	root.add_child(mesh)
	var body := StaticBody3D.new()
	body.name = "StaticBody3D"
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)

func build_ocean_boundary() -> void:
	# Keep ordinary walkers on the finite seabed, well beyond the shoreline.
	# Flight keeps collision; above these guards it can still use safe recovery.
	for axis in [Vector3.RIGHT,Vector3.BACK]:
		for sign_value in [-1,1]:
			var body := StaticBody3D.new()
			body.name = "OceanBoundary"
			var collision := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(2,40,388) if axis==Vector3.RIGHT else Vector3(388,40,2)
			collision.shape = box
			body.add_child(collision)
			add_child(body)
			body.position = axis*(HALF_SIZE+1)*sign_value+Vector3.UP*5

func build_pond() -> void:
	var water := MeshInstance3D.new()
	water.name = "FreshwaterSpring"
	var disc := CylinderMesh.new()
	disc.top_radius = 22
	disc.bottom_radius = 22
	disc.height = .08
	disc.radial_segments = 24
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(.12,.48,.53)
	water_material.roughness = .25
	disc.material = water_material
	water.mesh = disc
	add_child(water)
	water.position = Vector3(POND.x,1.3,POND.y)
	# A landscape feature only: no drinking/swimming mechanics introduced.

func build_landmarks() -> void:
	for record in [["LookoutCrown",Vector2(70,-108),Vector3(3,6,3)], ["SplitCoastRock",Vector2(135,46),Vector3(4,7,3)], ["FutureCaveClearing",Vector2(120,-106),Vector3(2,3,2)]]:
		var p: Vector2 = record[1]
		var landmark := MeshInstance3D.new()
		landmark.name = record[0]
		var mesh := PrismMesh.new()
		mesh.size = record[2]
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color(.43,.46,.40)
		stone.roughness = 1
		mesh.material = stone
		landmark.mesh = mesh
		add_child(landmark)
		landmark.position = Vector3(p.x,surface_height(p)+mesh.size.y/2,p.y)
		var body := StaticBody3D.new()
		body.collision_layer = 64
		var collision := CollisionShape3D.new()
		collision.shape = mesh.create_convex_shape()
		body.add_child(collision)
		landmark.add_child(body)

func biome_at(p: Vector2) -> String:
	var h := surface_height(p)
	if h<1.1: return "beach"
	if p.distance_to(POND)<48: return "freshwater"
	if p.x>112 and p.y>35: return "rocky_coast"
	if h>8 or p.y< -87: return "hills"
	return "jungle"

func resource_biome(kind: String, index: int) -> String:
	match kind:
		"tree": return "jungle"
		"fruit": return "jungle" if index<9 else "freshwater"
		"plant": return "jungle" if index<12 else "freshwater"
		"mushroom": return "jungle" if index<12 else "freshwater"
		"stick": return "beach" if index<28 else ("jungle" if index<36 else "freshwater")
		"stone": return "beach" if index<18 else ("rocky_coast" if index<34 else "hills")
		"coal": return "hills" if index<6 else "rocky_coast"
		"flint": return "hills" if index<4 else "rocky_coast"
	return "jungle"

func clear_of_pois(p: Vector2) -> bool:
	for point in POIS.values():
		if p.distance_to(point)<6: return false
	for point in WILDLIFE_HOMES.values():
		if p.distance_to(point)<3: return false
	return true

func build_manifests() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8008
	# Fixed expansion budgets, independent of terrain area. Every placement has
	# ground clearance, avoids trails/pool and stays outside the original core.
	for kind in ["tree","fruit","coal","flint","stick","stone","plant","mushroom"]:
		var count: int = {"tree":64,"fruit":12,"coal":8,"flint":8,"stick":40,"stone":40,"plant":24,"mushroom":16}[kind]
		for index in count:
			var biome := resource_biome(kind,index)
			for attempt in 240:
				var bounds: Rect2 = {"beach":Rect2(60,55,93,55),"jungle":Rect2(80,-30,55,64),"freshwater":Rect2(64,-105,78,100),"hills":Rect2(60,-140,70,53),"rocky_coast":Rect2(114,36,39,70)}[biome]
				var p := bounds.position+Vector2(rng.randf(),rng.randf())*bounds.size
				if biome_at(p)!=biome or surface_height(p)< -1.5 or surface_height(p)>13 or p.distance_to(POND)<30 or path_distance(p)<5 or not clear_of_pois(p): continue
				var key := Vector2i(floori(p.x/CHUNK_SIZE),floori(p.y/CHUNK_SIZE))
				if not manifests.has(key): manifests[key] = []
				var clear := true
				for nearby_key in manifests:
					for other in manifests[nearby_key]:
						if Vector2(other.position.x,other.position.z).distance_to(p)<(3.0 if kind in ["tree","fruit","coal","flint"] or other.kind in ["tree","fruit","coal","flint"] else 1.0): clear = false
				if not clear: continue
				var record := {"biome":biome,"kind":kind,"position":Vector3(p.x,surface_height(p)+.03,p.y),"yaw":rng.randf_range(0,TAU)}
				manifests[key].append(record)
				break
	# Grass uses shared original geometry, no collision/shadows; only nearby
	# chunks instantiate a MultiMesh. Exactly 1200 candidates, not per chunk.
	for index in 1200:
		if grass_instances>=451: break
		var p := Vector2(rng.randf_range(75,135),rng.randf_range(-100,65))
		if height_at(p)<1 or height_at(p)>13 or p.distance_to(POND)<30 or path_distance(p)<4: continue
		var key := Vector2i(floori(p.x/CHUNK_SIZE),floori(p.y/CHUNK_SIZE))
		if not manifests.has(key): manifests[key] = []
		manifests[key].append({"kind":"grass","position":Vector3(p.x,surface_height(p)+.03,p.y),"yaw":rng.randf_range(0,TAU)})
		grass_instances += 1

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(tracked_player):
		tracked_player = get_tree().get_first_node_in_group("Player") as Player
	# A last-resort guard for tunneling/off-map falls; deliberate developer
	# flight below the seabed remains available until flight is disabled.
	if is_instance_valid(tracked_player) and tracked_player.global_position.y< -12 and not DeveloperTools.is_flying():
		tracked_player.global_position = recovery_spawn
		tracked_player.velocity = Vector3.ZERO

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed>=.25:
		elapsed = 0
		refresh_details()
	# Spread detail activation across frames. Terrain is already present.
	if not detail_queue.is_empty():
		activate_chunk(detail_queue.pop_front())
	if nav_dirty and detail_queue.is_empty() and Time.get_ticks_msec()>=nav_refresh_at and get_parent().get_parent().scatter_nodes_ready>=get_parent().get_parent().scatter_nodes.size():
		nav_dirty = false
		get_parent().request_bake()

func refresh_details() -> void:
	var player := get_tree().get_first_node_in_group("Player") as Node3D
	if player == null: return
	var p := Vector2(player.global_position.x,player.global_position.z)
	for key in manifests:
		var center := (Vector2(key)+Vector2(.5,.5))*CHUNK_SIZE
		var distance := p.distance_to(center)
		if distance<DETAIL_RADIUS and not live_details.has(key) and not detail_queue.has(key):
			detail_queue.append(key)
		elif distance>UNLOAD_RADIUS and live_details.has(key):
			var root: Node3D = live_details[key]
			live_details.erase(key)
			# Keep altered objects (including harvested stumps and missing pickups)
			# instead of respawning loot every time a player crosses a boundary.
			remove_child(root)
			dormant_details[key] = root
			mark_navigation_dirty()
	# Teleports can invalidate queued activations before the next frame.
	for index in range(detail_queue.size()-1,-1,-1):
		if p.distance_to((Vector2(detail_queue[index])+Vector2(.5,.5))*CHUNK_SIZE)>UNLOAD_RADIUS:
			detail_queue.remove_at(index)

func mark_navigation_dirty() -> void:
	nav_dirty = true
	nav_refresh_at = Time.get_ticks_msec()+1500

func activate_chunk(key: Vector2i) -> void:
	if live_details.has(key): return
	mark_navigation_dirty()
	if dormant_details.has(key):
		var existing: Node3D = dormant_details[key]
		dormant_details.erase(key)
		add_child(existing)
		live_details[key] = existing
		return
	var root := Node3D.new()
	root.name = "Details_%d_%d" % [key.x,key.y]
	add_child(root)
	live_details[key] = root
	for record in manifests[key]:
		if record.kind == "grass": continue
		var object: Node3D = SCENES[record.kind].instantiate()
		root.add_child(object)
		object.position = record.position
		object.rotation.y = record.yaw
		for geometry in object.find_children("*","GeometryInstance3D",true,false):
			geometry.visibility_range_end = 105.0
	var grass_records: Array = manifests[key].filter(func(record): return record.kind == "grass")
	if not grass_records.is_empty():
		var source: Node3D = preload("res://meshes/grass.tscn").instantiate()
		var grass_mesh: MeshInstance3D = source if source is MeshInstance3D else source.find_child("*",true,false)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = grass_mesh.mesh
		# Preserve the authored grass material override on the streamed batch.
		multimesh.instance_count = grass_records.size()
		var center := (Vector2(key)+Vector2(.5,.5))*CHUNK_SIZE
		var grass := MultiMeshInstance3D.new()
		grass.multimesh = multimesh
		grass.material_override = preload("res://stages/island/grass_wind.tres")
		grass.position = Vector3(center.x,0,center.y)
		grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grass.visibility_range_end = 50
		grass.visibility_range_end_margin = 8
		root.add_child(grass)
		for i in grass_records.size():
			var record: Dictionary = grass_records[i]
			multimesh.set_instance_transform(i,Transform3D(Basis(Vector3.UP,record.yaw).scaled(Vector3.ONE*.8),record.position-grass.position))
		source.free()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for root in dormant_details.values():
			if is_instance_valid(root): root.free()
