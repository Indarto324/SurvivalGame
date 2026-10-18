extends NavigationRegion3D

var rebake_pending := false

func _enter_tree() -> void:
	EventSystem.GAM_update_navmesh.connect(request_bake)

func _ready() -> void:
	# Terrain is built before scatter completes. Bake once for initial animal
	# navigation as well as after construction; coalesce overlapping requests.
	navigation_mesh.cell_size = 0.5
	# Include all island ground/construction holders, not just this subtree.
	get_parent().add_to_group("island_navigation_source")
	navigation_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	navigation_mesh.geometry_source_group_name = "island_navigation_source"
	get_parent().loading_complete.connect(request_bake)
	bake_finished.connect(finished_bake)

func request_bake() -> void:
	if is_baking():
		rebake_pending = true
		return
	bake_navigation_mesh()

func finished_bake() -> void:
	if rebake_pending:
		rebake_pending = false
		request_bake.call_deferred()
