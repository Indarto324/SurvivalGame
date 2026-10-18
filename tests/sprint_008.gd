extends "res://tests/sprint_005.gd"

var world: ExpandedIsland
var inspection_camera: Camera3D
var captures := {}

func ground_hit(p: Vector2) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(Vector3(p.x,60,p.y),Vector3(p.x,-20,p.y),1)
	return world.get_world_3d().direct_space_state.intersect_ray(ray)

func capture_view(key: String, location: Vector3, target: Vector3) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name()=="headless": return
	inspection_camera.global_position = location
	inspection_camera.look_at(target)
	inspection_camera.current = true
	await physics_frames(3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/workspace/artifacts/kawanan-sprint008/"+key+".png")

func wait_details() -> void:
	world.refresh_details()
	var start := Time.get_ticks_msec()
	while not world.detail_queue.is_empty() and Time.get_ticks_msec()-start<10000:
		await get_tree().process_frame
	await physics_frames(3)

func run() -> void:
	MobileInput.configure_enabled(true)
	game = load("res://game/main_game.tscn").instantiate()
	add_child(game)
	controller = game.get_node("StageController")
	check(await wait_for_stage("res://stages/main_menu/main_menu.tscn"),"menu loads before expanded island")
	tap_control(controller.get_child(0).find_child("StartButton",true,false))
	check(await wait_for_stage("res://stages/island/island.tscn"),"expanded island completes all original scatter loading")
	island = controller.get_child(0)
	player = island.get_node("Actors/Player")
	inventory = player.get_node("Managers/InventoryManager")
	world = island.get_node("NavigationRegion3D/ExpandedWorld")
	check(world.ready_for_play and world.chunks.size()==144,"all 144 terrain chunks ready before gameplay")
	check(world.terrain_triangles==18432,"terrain geometry stays within fixed 18432 triangle budget")
	check(not island.get_node("NavigationRegion3D/Terrain").visible and island.get_node("NavigationRegion3D/Terrain/StaticBody3D/CollisionShape3D").disabled,"original terrain retained as height source without duplicate rendering/collision")
	await physics_frames(90)
	var spawn := Vector2(-23.2617,37.1292)
	var spawn_hit := ground_hit(spawn)
	check(not spawn_hit.is_empty() and absf(spawn_hit.position.y)<.02,"original spawn ground remains at authored height")
	check(player.is_on_floor() and player.global_position.y>.8 and player.global_position.y<1.1,"player safely lands on valid spawn terrain")
	check(absf(world.surface_height(spawn)-world.original_height(spawn))<.001,"protected spawn preserves original terrain height")
	var misses := 0
	var mismatches := 0
	var max_slope := 0.0
	var min_trail_height := INF
	for x in range(-188,189,8):
		for z in range(-188,189,8):
			var p := Vector2(x,z)
			var hit := ground_hit(p)
			if hit.is_empty(): misses += 1
			elif absf(hit.position.y-world.surface_height(p))>.04: mismatches += 1
	check(misses==0,"2304 coverage probes hit resident terrain across complete 384m square")
	check(mismatches==0,"collision heights agree with generated surface across terrain grid")
	var edge_ray := PhysicsRayQueryParameters3D.create(Vector3(180,-2,0),Vector3(200,-2,0),1)
	check(not world.get_world_3d().direct_space_state.intersect_ray(edge_ray).is_empty(),"deep-ocean perimeter prevents walkers leaving finite terrain")
	var seam_misses := 0
	for x in range(-160,161,32):
		for z in range(-160,161,32):
			for offset in [-.01,0.0,.01]:
				if ground_hit(Vector2(x+offset,z+offset)).is_empty(): seam_misses += 1
	check(seam_misses==0,"363 boundary probes find no collision holes at chunk corners")
	for i in world.PATH.size()-1:
		for step_index in 20:
			var p: Vector2 = world.PATH[i].lerp(world.PATH[i+1],step_index/20.0)
			var hit := ground_hit(p)
			min_trail_height=minf(min_trail_height,world.surface_height(p))
			if not hit.is_empty():
				var slope := rad_to_deg(acos(clampf(hit.normal.y,-1,1)))
				if slope>35: print("TRAIL STEEP: ",p," slope=",slope)
				max_slope=maxf(max_slope,slope)
	check(max_slope<35,"natural trail remains walkable below 35 degrees")
	check(min_trail_height> -2.0,"entire marked trail stays dry above ocean")
	check(connected_regions(),"spawn, jungle, hills, spring and coast belong to one connected dry island")
	var kinds := {}
	var bad_placement := 0
	var resources := 0
	for key in world.manifests:
		for record in world.manifests[key]:
			kinds[record.kind]=kinds.get(record.kind,0)+1
			var p := Vector2(record.position.x,record.position.z)
			if record.kind!="grass": resources+=1
			if p.x<60 or world.path_distance(p)<(3.9 if record.kind=="grass" else 4.9) or p.distance_to(world.POND)<29.9: bad_placement+=1
			if absf(record.position.y-world.surface_height(p)-.03)>.01: bad_placement+=1
	check(bad_placement==0,"every expansion placement is grounded and clear of core, paths and pool")
	check(kinds.get("tree",0)==64 and kinds.get("fruit",0)==12,"fixed 64-tree and 12-fruit-bush expansion budgets are populated")
	check(resources==212,"212 new resource objects independent of terrain area")
	check(world.grass_instances<=1200 and world.grass_instances>0,"new grass budget capped at 1200 candidates")
	check(island.get_node("Items/ScatterGrass").modifier_stack.stack[0].amount==12000,"existing 12000 grass budget preserved")
	var original_grass = island.get_node("Items/ScatterGrass/ScatterItem")
	check(original_grass.visibility_range_end==50,"original chunked grass receives 50m draw limit")
	check(world.live_details.size()<world.manifests.size(),"distant expansion chunks are not instantiated on spawn")
	var pond_hit := ground_hit(world.POND)
	check(not pond_hit.is_empty() and pond_hit.position.y<1.3,"freshwater visual sits above its solid shallow basin")
	var water_edge_buried := true
	for index in 24:
		var edge := world.POND+Vector2(cos(index*TAU/24),sin(index*TAU/24))*22
		if world.surface_height(edge)<1.34: water_edge_buried=false
	check(water_edge_buried,"freshwater edge intersects natural shore instead of floating above basin")
	check(world.has_node("FreshwaterSpring") and world.has_node("LookoutCrown") and world.has_node("SplitCoastRock"),"spring and original primitive landmarks exist")
	var hills_hit := ground_hit(Vector2(70,-108))
	check(not hills_hit.is_empty() and hills_hit.position.y>14,"northern hills provide meaningful elevation")
	var nav: NavigationRegion3D = island.get_node("NavigationRegion3D")
	var baking_start := Time.get_ticks_msec()
	while (nav.is_baking() or nav.navigation_mesh.get_polygon_count()==0) and Time.get_ticks_msec()-baking_start<20000:
		await get_tree().process_frame
	check(not nav.is_baking() and nav.navigation_mesh.get_polygon_count()>0,"expanded terrain has initial nonempty animal navigation")
	check(nav.navigation_mesh.cell_size==.5,"navigation voxel size bounded for expanded Android world")
	var nav_point := NavigationServer3D.map_get_closest_point(nav.get_navigation_map(),Vector3(102,3,15))
	check(Vector2(nav_point.x,nav_point.z).distance_to(Vector2(102,15))<5,"navigation covers eastern extension")
	var cycle: AnimationPlayer = island.get_node("DayNightCycleAnimationPlayer")
	cycle.seek(16,true)
	cycle.pause()
	inspection_camera = Camera3D.new()
	island.add_child(inspection_camera)
	await capture_view("air-overview",Vector3(180,190,160),Vector3(35,0,-20))
	await capture_view("spawn-ground",player.global_position+Vector3(4,2.5,4),player.global_position+Vector3(0,.2,0))
	var seam_start := Vector2(94,15)
	player.global_position=Vector3(seam_start.x,world.surface_height(seam_start)+1,seam_start.y)
	player.velocity=Vector3.ZERO
	player.camera_rig.rotation.y=0
	player.camera_rig.target_yaw=0
	await physics_frames(30)
	check(player.is_on_floor(),"character grounds on eastern trail before crossing a chunk boundary")
	MobileInput.movement=Vector2(1,0)
	await physics_frames(75)
	MobileInput.release_all()
	check(player.global_position.x>96 and player.is_on_floor(),"walking across 32m terrain chunk seam preserves floor collision")
	DeveloperTools.set_cheat("invincible",true)
	DeveloperTools.set_cheat("needs",true)
	DeveloperTools.set_cheat("fly",true)
	player.global_position=Vector3(110,35,-25)
	await wait_details()
	check(world.live_details.size()>0,"flying into expanded jungle activates nearby resource chunks")
	var fly_origin := player.global_position
	MobileInput.held["fly_up"]=1
	await physics_frames(8)
	check(player.global_position.y>fly_origin.y and player.gravity==12,"God Mode flight remains functional over expansion")
	MobileInput.release_all()
	check(not ground_hit(Vector2(player.global_position.x,player.global_position.z)).is_empty(),"resident terrain remains below flying player")
	player.global_position=Vector3(103,world.surface_height(Vector2(103,16))+1,16)
	player.velocity=Vector3.ZERO
	await wait_details()
	await capture_view("air-jungle",Vector3(110,65,70),Vector3(100,2,0))
	await capture_view("jungle-trail",player.global_position+Vector3(-5,2.5,6),player.global_position+Vector3(0,.5,0))
	await capture_view("freshwater",Vector3(125,14,-42),Vector3(105,1.3,-62))
	await capture_view("hill-lookout",Vector3(80,30,-83),Vector3(65,16,-111))
	await capture_view("rocky-coast",Vector3(158,15,75),Vector3(130,5,45))
	# Test actual streamed pickup callbacks and retained destruction state.
	var test_key: Vector2i
	var pickup: Node3D
	for key in world.live_details:
		for child in world.live_details[key].get_children():
			if child.find_child("Pickuppable",true,false)!=null and child.find_child("Pickuppable",true,false).get_parent()==child:
				test_key=key
				pickup=child
				break
		if pickup!=null: break
	check(pickup!=null,"streamed expansion includes usable original pickup scenes")
	if pickup!=null:
		var before := inventory.get_free_slots()
		var pickup_ref: WeakRef = weakref(pickup)
		var interactable := pickup.find_child("Pickuppable",true,false) as Pickuppable
		interactable.start_interaction()
		await physics_frames(3)
		check(inventory.get_free_slots()==before-1 and pickup_ref.get_ref()==null,"streamed item uses real inventory callback and disappears once")
		var root: Node3D = world.live_details[test_key]
		var after_count := root.get_child_count()
		player.global_position=Vector3(-180,100,180)
		await wait_details()
		check(not world.live_details.has(test_key) and world.dormant_details.has(test_key),"distant resource chunk detaches from active physics")
		player.global_position=Vector3((test_key.x+.5)*32,40,(test_key.y+.5)*32)
		await wait_details()
		check(world.live_details[test_key]==root and root.get_child_count()==after_count,"returning to a chunk cannot regenerate collected resources")
	# Teleport to a completely unvisited far boundary: ground still exists.
	player.global_position=Vector3(172,30,-150)
	await physics_frames(3)
	check(not ground_hit(Vector2(172,-150)).is_empty(),"teleport/flight cannot outrun terrain collision")
	check(DeveloperTools.recover(true),"developer spawn recovery works from far expansion")
	DeveloperTools.reset_cheats(false)
	await physics_frames(90)
	check(player.is_on_floor() and Vector2(player.global_position.x,player.global_position.z).distance_to(spawn)<1,"recovery returns to valid original spawn ground")
	player.global_position=Vector3(170,-20,150)
	player.velocity=Vector3.DOWN*30
	await physics_frames(90)
	check(player.is_on_floor() and Vector2(player.global_position.x,player.global_position.z).distance_to(spawn)<1,"below-seabed fall guard restores valid spawn with cheats disabled")
	# Export measurable counts and exact projected above-water triangle area.
	var report := measure_world(kinds, max_slope)
	if OS.get_cmdline_user_args().has("--report"):
		var file := FileAccess.open("/workspace/artifacts/kawanan-sprint008/world-validation.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"  ")+"\n")
	print("WORLD METRICS: ",JSON.stringify(report))
	var world_ref: WeakRef = weakref(world)
	controller.start_stage_change_sequence(StageConfig.Keys.Credits)
	check(await wait_for_stage("res://stages/credits/credits_stage.tscn"),"expanded world unloads safely")
	check(world_ref.get_ref()==null,"world frees terrain, live and dormant details on stage exit")
	print("SPRINT 008: ",checks," checks, ",failures," failures")
	game.get_node("MusicController").stop()
	game.queue_free()
	await get_tree().create_timer(.3).timeout
	get_tree().quit(0 if failures==0 else 1)

func measure_world(kinds: Dictionary, max_slope: float) -> Dictionary:
	var area := 0.0
	var minimum := Vector2(INF,INF)
	var maximum := Vector2(-INF,-INF)
	for root in world.chunks.values():
		var shape: ConcavePolygonShape3D = root.get_node("StaticBody3D/CollisionShape3D").shape
		var faces := shape.get_faces()
		for i in range(0,faces.size(),3):
			var poly: Array[Vector3]=[faces[i]+root.position,faces[i+1]+root.position,faces[i+2]+root.position]
			var clipped: Array[Vector3]=[]
			for j in 3:
				var a:=poly[j]
				var b:=poly[(j+1)%3]
				if a.y>=-2.81352: clipped.append(a)
				if (a.y>=-2.81352)!=(b.y>=-2.81352): clipped.append(a.lerp(b,(-2.81352-a.y)/(b.y-a.y)))
			var double_area := 0.0
			for j in clipped.size():
				var a:=clipped[j]
				var b:=clipped[(j+1)%clipped.size()]
				double_area+=a.x*b.z-a.z*b.x
				minimum=minimum.min(Vector2(a.x,a.z))
				maximum=maximum.max(Vector2(a.x,a.z))
			area+=absf(double_area)/2
	return {"terrain_extent_m":384,"chunks":world.chunks.size(),"terrain_triangles":world.terrain_triangles,"shoreline_bounds_min":[minimum.x,minimum.y],"shoreline_bounds_max":[maximum.x,maximum.y],"land_area_m2":area,"new_details":kinds,"max_trail_slope_degrees":max_slope,"active_detail_chunks":world.live_details.size(),"dormant_detail_chunks":world.dormant_details.size(),"physical_device_tested":false}

func connected_regions() -> bool:
	var dry := {}
	for x in range(-48,48):
		for z in range(-48,48):
			if world.surface_height(Vector2(x*4+2,z*4+2))> -2.0: dry[Vector2i(x,z)]=true
	var queue: Array[Vector2i]=[Vector2i(-6,9)]
	var seen := {Vector2i(-6,9):true}
	var cursor := 0
	while cursor<queue.size():
		var cell := queue[cursor]
		cursor+=1
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i=cell+direction
			if dry.has(next) and not seen.has(next):
				seen[next]=true
				queue.append(next)
	for region in [Vector2(103,16),Vector2(70,-108),Vector2(105,-62),Vector2(130,45)]:
		if not seen.has(Vector2i((region/4).floor())): return false
	return true
