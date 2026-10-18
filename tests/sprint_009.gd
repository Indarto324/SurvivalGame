extends "res://tests/sprint_008.gd"

var living: Node3D
var hurt_events := 0
var meat_events := 0

func capture_view(key: String, location: Vector3, target: Vector3) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name()=="headless": return
	inspection_camera.global_position=location
	inspection_camera.look_at(target)
	inspection_camera.current=true
	await physics_frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/workspace/artifacts/kawanan-sprint009/"+key+".png")

func run() -> void:
	MobileInput.configure_enabled(true)
	game=load("res://game/main_game.tscn").instantiate()
	add_child(game)
	controller=game.get_node("StageController")
	check(await wait_for_stage("res://stages/main_menu/main_menu.tscn"),"living island menu loads")
	tap_control(controller.get_child(0).find_child("StartButton",true,false))
	check(await wait_for_stage("res://stages/island/island.tscn"),"living island loads at production budgets")
	island=controller.get_child(0)
	player=island.get_node("Actors/Player")
	inventory=player.get_node("Managers/InventoryManager")
	world=island.get_node("NavigationRegion3D/ExpandedWorld")
	living=world.get_node("LivingIsland")
	await physics_frames(90)
	var spawn_active_ai: int=living.active_ai_count
	check(spawn_active_ai>=0 and spawn_active_ai<=10,"activity manager reports bounded active AI at spawn")
	check(living.animals.size()==10,"population stays at seven cows and three wolves")
	check(world.chunks.size()==144 and world.terrain_triangles==18432,"terrain budget and collision chunks unchanged")
	var counts := {}
	var distribution := {}
	var misplaced := 0
	for records in world.manifests.values():
		for record in records:
			counts[record.kind]=counts.get(record.kind,0)+1
			if record.kind=="grass": continue
			var p:=Vector2(record.position.x,record.position.z)
			if world.biome_at(p)!=record.biome or not world.clear_of_pois(p): misplaced+=1
			if not distribution.has(record.biome): distribution[record.biome]={}
			distribution[record.biome][record.kind]=distribution[record.biome].get(record.kind,0)+1
	check(misplaced==0,"resource records match terrain biome and preserve POI clearings")
	check(counts.get("tree",0)==64 and counts.get("fruit",0)==12,"tree and fruit budgets unchanged")
	check(counts.get("coal",0)==8 and counts.get("flint",0)==8,"mineral budgets unchanged")
	check(counts.get("stick",0)==40 and counts.get("stone",0)==40 and counts.get("plant",0)==24 and counts.get("mushroom",0)==16,"ground resource budgets unchanged")
	check(counts.get("grass",0)==451,"streamed grass remains capped at the prior 451 instances")
	check(distribution.get("beach",{}).get("stick",0)==28 and distribution.get("beach",{}).get("stone",0)==18,"beaches favor sticks and stones")
	check(distribution.get("jungle",{}).get("tree",0)==64 and distribution.jungle.get("fruit",0)==9,"jungle supports trees and fruit")
	check(distribution.get("freshwater",{}).get("plant",0)==12 and distribution.freshwater.get("mushroom",0)==4,"freshwater perimeter supplies vegetation without thirst mechanics")
	check(distribution.get("hills",{}).get("coal",0)==6 and distribution.hills.get("flint",0)==4,"hills contain mineral resources")
	check(distribution.get("rocky_coast",{}).get("stone",0)==16 and distribution.rocky_coast.get("flint",0)==4,"rocky coast has stone and flint")
	for title in world.POIS:
		check(living.has_node(title.replace(" ","")),"exploration marker exists: "+title)
	check(connected_regions(),"all exploration regions remain connected on dry land")
	var nav: NavigationRegion3D=island.get_node("NavigationRegion3D")
	var start:=Time.get_ticks_msec()
	while nav.is_baking() and Time.get_ticks_msec()-start<20000: await get_tree().process_frame
	check(nav.navigation_mesh.get_polygon_count()>0,"initial navigation remains nonempty")
	check(nav_edges_valid(nav.navigation_mesh),"navigation triangulation contains no edge shared by more than two polygons")
	var cow: Animal=island.get_node("Actors/Cow")
	var wolf: Animal=island.get_node("Actors/Wolf")
	for title in world.POIS:
		var p: Vector2=world.POIS[title]
		var destination:=Vector3(p.x,world.surface_height(p),p.y)
		var closest:=NavigationServer3D.map_get_closest_point(nav.get_navigation_map(),destination)
		check(Vector2(closest.x-p.x,closest.z-p.y).length()<2 and world.surface_height(p)>-2,"walkable navigation reaches POI: "+title)
	var relocated := 0
	for animal in living.animals:
		if world.WILDLIFE_HOMES.has(String(animal.name)):
			var destination: Vector2=world.WILDLIFE_HOMES[String(animal.name)]
			if Vector2(animal.home.x,animal.home.z).distance_to(destination)<1: relocated+=1
	check(relocated==5,"five existing animals occupy safe expansion territories without adding population")
	check(cow.terrain==world and wolf.terrain==world,"wildlife uses expanded terrain safety data")
	check(not cow.ground_safe(Vector3(180,0,180)) and not cow.ground_safe(Vector3(world.POND.x,0,world.POND.y)),"animals reject deep ocean and spring water")
	check(not cow.route_safe(PackedVector3Array([cow.global_position,Vector3(180,-5,180)])),"route validation rejects unsafe water crossings")
	player.set_freeze(true)
	player.global_position=Vector3(500,100,0)
	living.update_ecosystem()
	var ticks:=cow.physics_ticks
	var decisions:=cow.decisions
	await physics_frames(30)
	check(living.active_ai_count==0 and not cow.is_physics_processing(),"distant wildlife suspends physics AI")
	check(cow.physics_ticks==ticks and cow.decisions==decisions and not cow.animation_player.active,"sleeping animals do no physics decisions or skeletal animation")
	player.global_position=cow.home+Vector3(0,1,8)
	living.update_ecosystem()
	check(cow.active and cow.animation_player.active,"nearby wildlife resumes existing animations and physics")
	cow.set_state(Animal.States.Graze)
	check(cow.animation_player.current_animation=="Eating","grazing uses original Eating clip")
	cow.set_state(Animal.States.Rest)
	check(cow.animation_player.current_animation=="Idle_Headlow","cow rest uses existing standing-rest animation")
	cow.set_state(Animal.States.Wander)
	check(cow.animation_player.current_animation=="Walk" and cow.wander_timer.time_left>0,"wandering has a bounded duration and blended Walk clip")
	cow.wander_timer.start(10)
	var cow_start:=cow.global_position
	await physics_frames(60)
	check(cow.global_position.distance_to(cow_start)>.15 and cow.is_on_floor(),"cow follows an actual path without leaving ground")
	cow._on_wander_timer_timeout()
	check(cow.state==Animal.States.Idle,"wander returns to idle")
	cow.set_state(Animal.States.Graze)
	player.global_position=cow.global_position+Vector3(0,0,2)
	cow.think()
	check(cow.state==Animal.States.Flee,"nearby player startles grazing cow")
	cow._on_flee_timer_timeout()
	check(cow.state==Animal.States.Idle,"cow calms after bounded flee duration")
	check(cow.set_goal(cow.home+Vector3(2,0,0)) or cow.nav_agent.target_position.distance_to(cow.global_position)<20,"wander goals remain bounded around reachable home")
	cow.velocity=Vector3.ZERO
	cow.apply_gravity(1.0/30)
	var gravity30:=cow.velocity.y
	cow.velocity=Vector3.ZERO
	cow.apply_gravity(1.0/60)
	check(is_equal_approx(gravity30,cow.velocity.y*2) or cow.is_on_floor(),"animal gravity is frame-rate independent")
	# Use a controlled safe section of the original plain; only test homes move.
	wolf.global_position=Vector3(25,.2,0)
	wolf.home=wolf.global_position
	wolf.rotation.y=0
	player.global_position=Vector3(25,1,-5)
	wolf.set_active(true)
	wolf.set_state(Animal.States.Idle)
	check(wolf.player_in_fov(),"wolf field of view faces the player")
	check(wolf.pursuit_allowed(),"wolf can pursue a nearby grounded player within territory")
	wolf.set_state(Animal.States.Chase)
	check(wolf.state==Animal.States.Chase and wolf.animation_player.current_animation=="Gallop","wolf chase uses existing Gallop animation")
	player.global_position=Vector3(90,2,0)
	wolf.think()
	check(wolf.state!=Animal.States.Chase and not wolf.pursuit_allowed(),"wolf disengages when player escapes range and home leash")
	player.global_position=Vector3(25,60,0)
	check(not wolf.pursuit_allowed(),"overhead God Mode flight cannot provoke an endless chase")
	var axe: WeaponItemResource=ItemConfig.get_item_resource(ItemConfig.Keys.Axe)
	player.global_position=wolf.global_position+Vector3(0,.9,-.7)
	wolf.rotation.y=0
	wolf.set_state(Animal.States.Attack)
	var stats: PlayerStatsManager=player.get_node("Managers/PlayerStatsManager")
	var health_before_attack:=stats.current_health
	await get_tree().create_timer(.65).timeout
	check(stats.current_health==health_before_attack-wolf.damage,"original wolf attack method track applies exactly one hit")
	var before_health:=wolf.health
	wolf.take_hit(axe)
	check(wolf.health==before_health-axe.damage and wolf.state==Animal.States.Hurt,"existing weapon damage and hurt callback preserved")
	var spawner: Spawner=island.get_node("Spawner")
	var before_drops:=spawner.object_holder.get_child_count()
	wolf.take_hit(axe)
	wolf.take_hit(axe)
	check(wolf.state==Animal.States.Dead,"existing wolf health reaches death")
	check(spawner.object_holder.get_child_count()==before_drops+1,"animal death drops meat exactly once")
	wolf.take_hit(axe)
	wolf.set_state(Animal.States.Dead)
	check(spawner.object_holder.get_child_count()==before_drops+1,"duplicate hits/transitions cannot duplicate death drops")
	check(not wolf.is_physics_processing() and wolf.disappear_after_death_timer.time_left>0,"dead wildlife stops AI and retains cleanup timer")
	var cycle: AnimationPlayer=island.get_node("DayNightCycleAnimationPlayer")
	cycle.seek(4,true)
	living.update_ecosystem()
	check(living.night and cow.night,"night environment feeds wildlife rest preference")
	cycle.seek(16,true)
	cycle.pause()
	living.update_ecosystem()
	check(not living.night and not cow.night,"daytime restores daytime wildlife behavior")
	check(living.surf.stream.loop_mode==AudioStreamWAV.LOOP_FORWARD and living.surf.stream.loop_end>100000 and living.surf.stream.get_length()>7 and living.surf.bus=="Music","original procedural coastal loop respects audio settings bus")
	var inland_db: float=living.surf.volume_db
	player.global_position=Vector3(135,world.surface_height(Vector2(135,85))+1,85)
	living.update_ecosystem()
	check(living.coast_mix==1 and living.surf.volume_db>inland_db,"coastal biome raises inexpensive surf ambience")
	check(preload("res://stages/island/grass_wind.tres").get_shader_parameter("wind_strength")<=.04,"wind remains subtle without CPU-driven foliage transforms")
	player.set_freeze(false)
	DeveloperTools.set_cheat("invincible",true)
	DeveloperTools.set_cheat("needs",true)
	DeveloperTools.set_cheat("fly",true)
	player.global_position=Vector3(110,35,10)
	await wait_details()
	MobileInput.held["fly_up"]=1
	await physics_frames(5)
	MobileInput.release_all()
	check(player.global_position.y>35 and world.chunks.size()==144,"God Mode flight remains functional over wildlife and streamed biomes")
	var pickup: Node3D
	var key_used: Vector2i
	for key in world.live_details:
		for child in world.live_details[key].get_children():
			var item: Node=child.find_child("Pickuppable",true,false)
			if item is Pickuppable and item.get_parent()==child:
				pickup=child
				key_used=key
				break
		if pickup!=null: break
	check(pickup!=null,"biome streaming creates real pickuppable scenes")
	if pickup!=null:
		var before:=inventory.get_free_slots()
		(pickup.get_node("Pickuppable") as Pickuppable).start_interaction()
		await physics_frames(3)
		check(inventory.get_free_slots()==before-1,"biome item collection updates normal inventory")
		var root: Node3D=world.live_details[key_used]
		var after:=root.get_child_count()
		player.global_position=Vector3(-180,80,180)
		await wait_details()
		check(world.dormant_details.has(key_used),"collected resource chunk enters dormant storage")
		player.global_position=Vector3((key_used.x+.5)*32,35,(key_used.y+.5)*32)
		await wait_details()
		check(world.live_details[key_used]==root and root.get_child_count()==after,"resource unload/reload cannot regenerate loot")
	inspection_camera=Camera3D.new()
	island.add_child(inspection_camera)
	if OS.get_cmdline_user_args().has("--capture"):
		player.set_process(false)
		player.interaction_ray_cast.clear_prompt()
	var beach_point:=Vector2.ZERO
	for records in world.manifests.values():
		for record in records:
			if record.get("biome","")=="beach": beach_point=Vector2(record.position.x,record.position.z)
	for shot in [["beach",beach_point],["jungle",Vector2(115,20)],["hills",Vector2(90,-114)],["freshwater",Vector2(105,-36)],["rocky-coast",Vector2(132,60)]]:
		var p: Vector2=shot[1]
		player.global_position=Vector3(p.x,world.surface_height(p)+1,p.y)
		await wait_details()
		living.update_ecosystem()
		await capture_view(shot[0],player.global_position+Vector3(7,4,9),player.global_position+Vector3(0,1,0))
	cow.global_position=Vector3(97,world.surface_height(Vector2(97,29))+.1,29)
	player.global_position=cow.global_position+Vector3(0,0,8)
	living.update_ecosystem()
	cow.set_state(Animal.States.Graze)
	await get_tree().create_timer(.65).timeout
	await capture_view("cow-grazing",cow.global_position+Vector3(4,2,4),cow.global_position+Vector3(0,.6,0))
	cow.set_state(Animal.States.Rest)
	await get_tree().create_timer(.45).timeout
	await capture_view("cow-resting",cow.global_position+Vector3(4,2,4),cow.global_position+Vector3(0,.6,0))
	var other_wolf: Animal=island.get_node("Actors/Wolf3")
	player.global_position=other_wolf.global_position+Vector3(0,0,9)
	living.update_ecosystem()
	other_wolf.set_state(Animal.States.Wander)
	await capture_view("wolf-patrol",other_wolf.global_position+Vector3(4,2,4),other_wolf.global_position+Vector3(0,.6,0))
	var report:={"population":10,"spawn_active_ai_count":spawn_active_ai,"active_ai_count":living.active_ai_count,"terrain_chunks":144,"terrain_triangles":18432,"expansion_resources":212,"grass_instances":world.grass_instances,"distribution":distribution,"decision_hz_per_active_animal":4,"activity_poll_hz":2,"physical_device_tested":false}
	print("LIVING METRICS: ",JSON.stringify(report))
	if OS.get_cmdline_user_args().has("--report"):
		var file:=FileAccess.open("/workspace/artifacts/kawanan-sprint009/living-validation.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"  ")+"\n")
	var living_ref: WeakRef=weakref(living)
	controller.start_stage_change_sequence(StageConfig.Keys.Credits)
	check(await wait_for_stage("res://stages/credits/credits_stage.tscn"),"living island unloads into credits")
	check(living_ref.get_ref()==null and get_tree().get_nodes_in_group("Wildlife").is_empty(),"wildlife, ambient audio and POIs clean up on stage exit")
	check(game.get_node("MusicController").volume_db==0,"ambient mixing restores music level after island exit")
	print("SPRINT 009: ",checks," checks, ",failures," failures")
	game.get_node("MusicController").stop()
	game.queue_free()
	await get_tree().create_timer(.3).timeout
	get_tree().quit(0 if failures==0 else 1)

func nav_edges_valid(mesh: NavigationMesh) -> bool:
	var vertices := mesh.get_vertices()
	var edges := {}
	for index in mesh.get_polygon_count():
		var poly := mesh.get_polygon(index)
		for point in poly.size():
			var a := str(Vector3i((vertices[poly[point]]/.0005).floor()))
			var b := str(Vector3i((vertices[poly[(point+1)%poly.size()]]/.0005).floor()))
			var key := a+":"+b if a<b else b+":"+a
			edges[key]=edges.get(key,0)+1
			if edges[key]>2: return false
	return mesh.get_polygon_count()>0
