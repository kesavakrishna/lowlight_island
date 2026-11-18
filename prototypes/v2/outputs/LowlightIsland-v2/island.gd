extends Node3D

const DAY := 145.0
const FIRST_DAWN := 32.0
const NIGHT := 245.0
const DEADLINE := 365.0
const ISLAND_RADIUS := 210.0
const SHORE_RADIUS := 203.0
const WALK := 4.7
const LOWEST_CLIMBABLE_TREE := 5.0

# A fork you can climb to. Seats sit on the tree's own branches (from the model skeleton); from there the
# player walks the branches freely on invisible footing. Bridge anchors keep a computed seat with a hidden pad.
class TreePerch:
	var trunk: Vector3
	var base: Vector3
	var seat: Vector3
	var heading: Vector3          # outward along the seat's branch
	var approach: Vector3         # side of the trunk the climb goes up, clear of the branch itself
	var step_off: Vector3         # trunk-side point above the branch where the player steps onto it
	var platform: StaticBody3D
	var leafy := true
	var higher: TreePerch
	var climb_anchor: Vector3
	var pose: Transform3D         # the tree model's transform
	var kind := ""
	var wood: Array[RID] = []     # this tree's own colliders, ignored when fitting a screen onto it
	var pad: StaticBody3D         # hidden footpad under a real-branch seat
	var width := 0.0
	var limb_t := -1.0            # skeleton branch the seat is on (-1: computed bridge seat)
	var reach := 0.0              # horizontal crown reach in metres; beyond it you have left this tree

var flora := {}
var skeletons := {}       # climbable species: trunk axis and main branches (flora/<kind>.skeleton.json)
var footing_shapes := {}  # invisible flat walking strips along thick branches, one shape per species
var leaf_grids := {}      # foliage vertex counts per LEAF_CELL, in model units, for hiding up a tree
const LEAF_CELL := 1.5
const LEAFY_COVER := 1100 # foliage vertices in the 3x3x3 cells around the head that count as hidden
                          # (about the 20th percentile at fork seats: bare outer wood stays exposed)
var trunk_shapes := {}
var root_contacts := {}
var terrain_vertices := PackedVector3Array()
const SEGMENTS := 368
const RINGS := 164
var rng := RandomNumberGenerator.new()
var player := CharacterBody3D.new()
var camera := Camera3D.new()
var light := SpotLight3D.new()
var sun := DirectionalLight3D.new()
var moon := DirectionalLight3D.new()
var atmosphere := Environment.new()
var river_phase := 0.0
var motes := MultiMeshInstance3D.new()
var mote_material := ShaderMaterial.new()
var sky_material := ShaderMaterial.new()
var surfaces: Dictionary = {}
var leaf_clusters: Array[Transform3D] = []
var forest_meshes: Array[MeshInstance3D] = []
var collecting_forest := false
var creature := Node3D.new()
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var creature_head: MeshInstance3D
var stride := 0.0
var perches: Array[TreePerch] = []
var landmark_perch: TreePerch
var tree_sites: Array[Vector3] = []
var jungles: Array[Vector4] = []        # dense jungle patches: centre x, outline phase, centre z, radius
var jungle_trails: Array[Array] = []    # winding gaps: [centre, along, across, amplitude, frequency, phase]
var jungle_bridges: Array[Array] = []   # [start seat, end seat] of walkable crossings in the jungle
var canopy_shade := 0.0                 # 0 in the open, 1 deep under a joined jungle canopy (eased)
var branch_platforms: Array[StaticBody3D] = []   # player-built plank platforms up in trees
var jump_requested := false             # Space pressed; applied on the next physics step if standing
const JUMP := 5.4                       # about 0.8 m high with the game's 18 m/s² gravity
const JUMP_CARRYING := 3.4              # the battery's weight keeps it to a hop (about 0.3 m)
var perch: TreePerch
var pursuing_perch: TreePerch
var creature_up := false
var climb_path := PackedVector3Array()
var preview: MeshInstance3D
var preview_material := StandardMaterial3D.new()
var placing_screen := false
var screen_angle := 0.0
var swamps: Array[Vector3] = []
const CANOPY := ["Umbrella Fig","Tiered Copperwood","Leaning River Myrtle","Crest Palm"]
const BAMBOO := ["Giant Reed Bamboo","Brush Bamboo"]
const MEADOW := ["Meadow Hairgrass","Rose Plume Grass","Bronze Seed Sedge","Copper Bromeliad"]
const MARGIN := ["Marsh Rush","Silver Bank Grass","River Elephant Ear","Blue Ripple Lily","Bank Maidenhair"]
const UNDERGROWTH := ["Forest Carpet","Sword Fern","Violet Shieldleaf","Lime Strapleaf","Tower Fern"]
const OUTCROPS := ["Bedded Cliff Face","Moss Table Ledge","Fractured Twin Block","River Stair Outcrop","Shale Overhang"]
const STONES := ["Waterworn Boulder","Mossback Boulder","Ford Stepping Slab","River Gravel Fan","Broken Talus"]
enum Landscape { LAKE, WETLAND, GORGE, GRASSLAND }
var landscape: Landscape
var basin_sizes: Array[Vector2] = []
var fall_height := 0.0
var fall_distance := 0.0
var meadow_center := Vector2.ZERO
var meadow_size := Vector2.ZERO
var ridges: Array[Vector3] = []
var landmark_pads: Array[Vector3] = []
var terrain_noise := FastNoiseLite.new()
var terrain_body: StaticBody3D
var waters: Array[ShaderMaterial] = []
var rock_noise := FastNoiseLite.new()
var supply_caches: Array[Node3D] = []
var howl := AudioStreamPlayer3D.new()
var howl_timer := 7.0
var warned_climb := false
var battery := Node3D.new()
var hud := Label.new()
var prompt := Label.new()
var notice := Label.new()
var cover: Array[Vector3] = []
var bushes: Array[Vector3] = []
var tree: Vector3
var deck_center: Vector3
var cave: Vector3
var radio: Vector3
var dock: Vector3
var field: Vector3
var door: StaticBody3D
var door_built := false
var door_broken := false
var time := 0.0
var last_light_time := -1.0
var started := false
var ended := false
var carrying := false
var powered := false
var crouched := false
var wood := 0
var decoys := 2
var stamina := 100.0
var chase := false
var detection := 0.0
var investigate := 0.0
var target := Vector3.ZERO
var display_time := 0.0
var patrol := 0.0
var door_pressure := 0.0
var axis := Vector3.RIGHT
var side := Vector3.BACK

func _ready() -> void:
	rng.randomize()
	river_phase = rng.randf_range(0.0,TAU)
	var angle := rng.randf_range(0.0, TAU)
	axis = Vector3(cos(angle), 0, sin(angle))
	side = Vector3(-axis.z, 0, axis.x)
	field = axis * 39.0
	tree = field + side * 17.0
	deck_center = tree + side * 2.65 + axis * 1.35
	cave = field - side * 19.0
	radio = axis * 112.0 + side * rng.randf_range(-7.0, 7.0)
	dock = -axis * (SHORE_RADIUS-2.0)
	landscape = rng.randi_range(0,3) as Landscape
	var wetland := landscape == Landscape.WETLAND
	swamps = [axis*rng.randf_range(-14,17)+side*rng.randf_range(65,88), -axis*rng.randf_range(24,56)-side*rng.randf_range(64,86)]
	basin_sizes = [Vector2(rng.randf_range(29,43),rng.randf_range(23,36)) if landscape == Landscape.LAKE else Vector2(rng.randf_range(9,18),rng.randf_range(9,16)), Vector2(rng.randf_range(12,22),rng.randf_range(10,18))]
	if wetland:
		for i in range(rng.randi_range(2,4)):
			swamps.append(axis*(75.0 if i%2==0 else -95.0)+side*((105.0+i*8) if i<2 else -95.0)+axis*rng.randf_range(-9,9))
			basin_sizes.append(Vector2(rng.randf_range(9,18),rng.randf_range(8,15)))
	if landscape == Landscape.GORGE:
		fall_height = rng.randf_range(4.2,7.5)
		fall_distance = rng.randf_range(27,42)
	meadow_center = Vector2(rng.randf_range(-110,-66),rng.randf_range(-30,28))
	meadow_size = Vector2(70,53) if landscape == Landscape.GRASSLAND else Vector2(35,21)
	for point in [Vector3(80,23,63), Vector3(-73,21,58), Vector3(29,17,-94)]:
		var center: Vector3 = axis*(point.x+rng.randf_range(-10,10)) + side*(point.z+rng.randf_range(-8,8))
		center.y = point.y + (rng.randf_range(4,9) if landscape == Landscape.GORGE else rng.randf_range(-2,2))
		ridges.append(center)
	for pad in [Vector3(0,10,0), Vector3(tree.x,9,tree.z), Vector3(cave.x,8,cave.z),
			Vector3(field.x,10,field.z), Vector3(radio.x,8,radio.z), Vector3(dock.x,6,dock.z)]:
		landmark_pads.append(pad)
	terrain_noise.seed = rng.randi()
	terrain_noise.frequency = 0.012
	build_world()
	add_child(player)
	player.collision_layer = 2
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.33
	capsule.height = 1.1
	shape.shape = capsule
	shape.position.y = 0.55
	player.add_child(shape)
	player.floor_snap_length = 0.34
	player.add_child(camera)
	camera.position.y = 1.65
	camera.fov = 76
	player.look_at(axis*17.0+side*13.0)
	player.position.y = 0.1
	camera.add_child(light)
	light.spot_range = 24
	light.spot_angle = 30
	light.light_energy = 2.4
	light.shadow_enabled = true
	light.light_color = Color("ffddae")
	light.hide()
	howl.stream = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://audio/howl.wav"))
	howl.volume_db = -8.0
	howl.unit_size = 8.0
	howl.max_distance = 90.0
	add_child(howl)
	setup_build_preview()
	update_light()
	setup_hud()
	show_message("LOWLIGHT ISLAND\nThe island is dark. Click to start.", 0.0)

func material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mat.metallic_specular = 0.19
	return mat

func mesh(parent: Node3D, model: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var obj := MeshInstance3D.new()
	obj.mesh = model
	obj.material_override = material(color)
	parent.add_child(obj)
	obj.position = pos
	if collecting_forest and parent == self:
		forest_meshes.append(obj)
	return obj

func box(pos: Vector3, size: Vector3, color: Color, solid := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	add_child(body)
	body.position = pos
	var model := BoxMesh.new()
	model.size = size
	mesh(body, model, Vector3.ZERO, color)
	if solid:
		var collision := CollisionShape3D.new()
		var bounds := BoxShape3D.new()
		bounds.size = size
		collision.shape = bounds
		body.add_child(collision)
	return body

func surface(obj: MeshInstance3D, color: Color, grain: Vector3, variation: float, stone := false, bark := false) -> void:
	var key := [color, grain, variation, stone,bark]
	if not surfaces.has(key):
		var shader_material := ShaderMaterial.new()
		shader_material.shader = preload("res://surface.gdshader")
		shader_material.set_shader_parameter("base_color", color)
		shader_material.set_shader_parameter("grain", grain)
		shader_material.set_shader_parameter("variation", variation)
		shader_material.set_shader_parameter("stone", stone)
		shader_material.set_shader_parameter("bark",bark)
		surfaces[key] = shader_material
	obj.material_override = surfaces[key]

func timber(parent: Node3D, pos: Vector3, size: Vector3, tint: Color) -> MeshInstance3D:
	var plank := BoxMesh.new()
	plank.size = size
	var obj := mesh(parent, plank, pos, tint)
	var grain := Vector3(6,6,11)
	if size.y > size.x and size.y > size.z:
		grain = Vector3(13,0.75,13)
	elif size.x > size.z:
		grain.x = 0.75
	else:
		grain.z = 0.75
	surface(obj,tint,grain,0.38)
	return obj

func branch(parent: Node3D, start: Vector3, end: Vector3, base_radius: float, tip_radius: float) -> MeshInstance3D:
	var wood_mesh := CylinderMesh.new()
	wood_mesh.height = start.distance_to(end)
	wood_mesh.bottom_radius = base_radius
	wood_mesh.top_radius = tip_radius
	wood_mesh.radial_segments = 9
	var obj := mesh(parent,wood_mesh,start.lerp(end,0.5),Color("5a4d37"))
	obj.quaternion = Quaternion(Vector3.UP,(end-start).normalized())
	surface(obj,Color("5a4d37"),Vector3(8,0.52,8),0.54)
	return obj

func build_world() -> void:
	var world := WorldEnvironment.new()
	world.environment = atmosphere
	atmosphere.background_mode = Environment.BG_SKY
	atmosphere.sky = Sky.new()
	atmosphere.sky.process_mode = Sky.PROCESS_MODE_REALTIME
	atmosphere.sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky_material.shader = preload("res://sky.gdshader")
	sky_material.set_shader_parameter("cloud_map",preload("res://weather_noise.res"))
	atmosphere.sky.sky_material = sky_material
	atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	atmosphere.fog_enabled = true
	atmosphere.fog_density = 0.006
	atmosphere.fog_sky_affect = 0.0
	atmosphere.fog_height = 0.5
	add_child(world)
	add_child(sun)
	add_child(moon)
	sun.shadow_enabled = true
	moon.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 105
	moon.directional_shadow_max_distance = 96
	for species in ["Shelfwood","Veil Banyan","Crown Fern","Tide Fern","Amethyst Rosette","Lantern Shelves","Canopy Crossing","Curtain Vine","Lantern Orchid","Young Shelfwood","Arch Palm","Elephant Ear","Creeper Mat"]+CANOPY+BAMBOO+MEADOW+MARGIN+UNDERGROWTH+OUTCROPS+STONES:
		flora[species] = load("res://flora/"+species+".res")
		if species in ["Shelfwood","Veil Banyan","Crown Fern","Tide Fern","Young Shelfwood","Arch Palm"]:
			flora[species+" distant"] = load("res://flora/"+species+" distant.res")
	for species in ["Shelfwood","Veil Banyan","Arch Palm"]+CANOPY:
		skeletons[species] = JSON.parse_string(FileAccess.get_file_as_string("res://flora/"+species+".skeleton.json"))
	build_terrain()
	rock_noise.seed = rng.randi()
	rock_noise.frequency = 2.1
	var rock := rock_mesh()
	var grove: Array[Vector3] = [side*18.0 + axis*3.0, -side*25.0 + axis*18.0, swamps[0]+axis*(maxf(basin_sizes[0].x,basin_sizes[0].y)+6.0)]
	grove.append(axis*135.0-side*62.0)
	grove.append(-axis*148.0+side*57.0)
	collecting_forest = true
	for spot in grove:
		add_tree(spot,rng.randf_range(25.0,32.0))
	build_rainforest(grove)
	build_jungle(grove)
	for i in range(940):
		var spot := Vector3(rng.randf_range(-197,197),0,rng.randf_range(-197,197))
		if spot.length() > 197 or spot.distance_to(field) < 15 or spot.distance_to(tree) < 12 or spot.distance_to(cave) < 10 or spot.distance_to(radio) < 7 or absf(spot.dot(side)) < 3 or swamp_weight(spot) > 0.5:
			continue
		var size := rng.randf()
		var height := rng.randf_range(5.7,9.0) if size < 0.44 else (rng.randf_range(11.0,17.0) if size < 0.94 else rng.randf_range(22.0,30.0))
		if reserved_lowland(spot) or on_cliff_approach(spot) or not tree_clearance(spot,9.4 if height > 20.0 else 4.8) or ground_grade(spot) > 0.68 or near_jungle_bridge(spot,9.5 if height > 14.0 else 4.5):
			continue
		if i%4 == 0 and spot.distance_to(tree)>22 and spot.distance_to(side*18.0+axis*3.0)>22:
			var variant := i/4%4
			add_tree(spot,[15.0,19.0,8.0,9.0][variant]*rng.randf_range(.82,1.14),false,3+variant)
		else:
			add_tree(spot,height,false,1 if size > 0.44 and height < 20.0 else 0)
	add_tree(tree,29.0,true)
	add_understory(grove)
	collecting_forest = false
	batch_forest()
	build_treehouse()
	for x in [-3.55,3.55]:
		solid_rock(rock,cave+Vector3(x,1.4,-1.15),Vector3(3.2,5.2,4.6))
		solid_rock(rock,cave+Vector3(x,1.5,1.55),Vector3(3.15,4.9,4.8))
		var frame := box(cave+Vector3(signf(x)*2.1,1.1,-2.65),Vector3(0.31,2.25,0.42),Color("5c4b38"))
		surface(frame.get_child(0),Color("5c4b38"),Vector3(13,0.75,13),0.38)
	solid_rock(rock,cave+Vector3(0,3.65,0),Vector3(9.5,3.4,8))
	solid_rock(rock,cave+Vector3(0,1.2,3.45),Vector3(8,4.1,3.4))
	timber(self,cave+Vector3(0,2.1,-2.65),Vector3(4.3,0.24,0.28),Color("69503a"))
	for i in range(43):
		var angle := rng.randf_range(0,TAU)
		var spot := Vector3(cos(angle),0,sin(angle))*rng.randf_range(14,81)
		if spot.distance_to(side*18.0+axis*3.0)<10.0 or reserved_lowland(spot) or on_cliff_approach(spot) or absf(spot.dot(side)) < 7 or spot.distance_to(field+side*3.0) < 18 or spot.distance_to(cave) < 9 or spot.distance_to(tree) < 10 or spot.distance_to(radio) < 7:
			continue
		if swamps.any(func(marsh: Vector3) -> bool: return marsh.distance_to(spot) < 6.0):
			continue
		if perches.any(func(p: TreePerch) -> bool: return p.trunk.distance_to(spot) < 4.6):
			continue
		var size := rng.randf_range(0.8,2.15)
		spot.y = elevation(spot)
		solid_rock(rock,spot+Vector3.DOWN*size*0.24,Vector3(size*1.55,size,size*0.9))
	door = box(cave + Vector3(0,1.0,-2.65), Vector3(4,2,0.23), Color("755437"))
	door.get_child(0).hide()
	for i in range(10):
		timber(door,Vector3(-1.8+i*0.4,0,0),Vector3(0.395,1.98,0.19),Color("755638").lightened((i%3)*0.035))
	for level in [-0.52,0.55]:
		timber(door,Vector3(0,level,-0.13),Vector3(4.05,0.15,0.1),Color("513822"))
	set_door_closed(false)
	box(radio + Vector3(0,0.8,0), Vector3(1.9,1.6,1.3), Color("474b43"))
	box(radio + Vector3(0,3.5,0), Vector3(0.14,6,0.14), Color("b3a688"), false)
	box(radio + Vector3(0,5.5,0), Vector3(2.7,0.1,0.1), Color("b3a688"), false)
	box(dock - axis * 1.8, Vector3(5,0.22,5), Color("7d634c"))
	box(dock - axis * 3.0 + Vector3.UP * 0.3, Vector3(2.6,0.5,1.4), Color("8eaaa3"), false)
	box(-axis * 5.5 + side * 2.5 + Vector3.UP * 0.5, Vector3(4,1,1.8), Color("a3aba0"))
	var wing := box(-axis * 5.5 + side * 2.5 + Vector3.UP * 0.9, Vector3(1,0.2,6.5), Color("86968d"), false)
	wing.rotation.z = 0.17
	supply_spot = -axis * 3.1 + side * 1.4
	for location in [supply_spot, field-axis*8.0, cave+Vector3.FORWARD*4.2, radio-axis*7.0]:
		var cache := Node3D.new()
		add_child(cache)
		cache.position = location
		for i in range(4):
			timber(cache,Vector3(0,0.08+i*0.11,0),Vector3(1.1,0.1,0.58),Color("93714c"))
		marker(cache,"PLANKS",0.85)
		supply_caches.append(cache)
	add_child(battery)
	battery.position = field + side * rng.randf_range(-6,6)
	var casing := BoxMesh.new()
	casing.size = Vector3(0.7,0.46,0.43)
	mesh(battery,casing,Vector3.UP * 0.24,Color("d79543"))
	marker(battery,"BATTERY",0.95)
	marker_at(radio,"RADIO",2.2)
	marker_at(dock,"DOCK",1.6)
	marker_at(tree,"TREEHOUSE",2.2)
	marker_at(cave,"CAVE",3.75)
	for basin in range(swamps.size()):
		var marsh:=swamps[basin]
		marker_at(marsh,"MARSH",1.9)
		for i in range(15):
			var angle := TAU*i/15.0
			var amount := rng.randf_range(0.85,1.06)
			cover.append(marsh + Vector3(cos(angle)*basin_sizes[basin].x*.9,0,sin(angle)*basin_sizes[basin].y*.9)*amount)
	for i in range(28):
		var spot := axis * rng.randf_range(-66,63) + side * rng.randf_range(-36,36)
		if spot.distance_to(cave) > 6 and spot.distance_to(tree) > 5 and spot.length() < 73:
			cover.append(spot)
	for i in range(cover.size()):
		cover[i].y = elevation(cover[i])
	add_leaves()
	add_grass()
	build_cliff_faces()
	add_talus(rock)
	dress_grove()
	refit_blocked_forks()
	build_motes()
	build_creature()

func build_motes() -> void:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(0.115,0.115)
	batch.mesh = quad
	batch.instance_count = 52
	for i in range(batch.instance_count):
		var center: Vector3 = [swamps[0],swamps[1],tree,side*18.0][i%4]
		var pos := center + Vector3(rng.randf_range(-16,16),0,rng.randf_range(-16,16))
		pos.y = elevation(pos)+rng.randf_range(0.65,4.6)
		batch.set_instance_transform(i,Transform3D(Basis.IDENTITY,pos))
	motes.multimesh = batch
	mote_material.shader = preload("res://motes.gdshader")
	motes.material_override = mote_material
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	motes.extra_cull_margin = 2.0
	add_child(motes)

func dress_grove() -> void:
	add_crossing(perches[0].higher.seat,landmark_perch.higher.seat)
	for i in range(13):
		var basin:=i%swamps.size()
		var pos:=swamps[basin]+Vector3(cos(i*2.4)*basin_sizes[basin].x,0,sin(i*2.4)*basin_sizes[basin].y)
		pos.y = elevation(pos)
		place_flora("Lantern Orchid",Transform3D(Basis(Vector3.UP,i*2.4).scaled(Vector3.ONE*0.68),pos),64)

# A walkable Canopy Crossing trunk from one high perch seat to another, with draped vines.
func add_crossing(start: Vector3, end: Vector3) -> void:
	var length_axis := (end-start)/28.0
	var bridge_basis := Basis(length_axis,Vector3.UP,length_axis.cross(Vector3.UP).normalized())
	var bridge_pos := (start+end)*0.5-Vector3.UP*7.36
	var bridge := place_flora("Canopy Crossing",Transform3D(bridge_basis,bridge_pos))
	# Bake the sloping transform into the collider so physics uses the same surface.
	var data := bridge.mesh.get_faces()
	for i in range(data.size()):
		data[i] = bridge.transform*data[i]
	var solid := ConcavePolygonShape3D.new()
	solid.set_faces(data)
	var crossing := StaticBody3D.new()
	crossing.set_meta("climbable",true)
	var collision := CollisionShape3D.new()
	collision.shape = solid
	crossing.add_child(collision)
	add_child(crossing)
	for i in range(7):
		var t := i/7.0
		var next := (i+1)/7.0
		var a := bridge.transform*Vector3(-14+28*t,6.2+0.85*sin(t*TAU),0.55*sin(t*TAU)+0.92)
		var b := bridge.transform*Vector3(-14+28*next,6.2+0.85*sin(next*TAU),0.55*sin(next*TAU)+0.92)
		place_flora("Curtain Vine",Transform3D(Basis((b-a)/6.0,Vector3.UP,bridge_basis.z),a),90.0)

func add_talus(rock: Mesh) -> void:
	for ridge in ridges:
		for i in range(19):
			var u := rng.randf_range(-28.0,28.0)
			var front := -10.0 + 1.5*sin(u*0.17) + 0.72*sin(u*0.41)
			var toe := Vector3(ridge.x,0,ridge.z)+axis*u+side*(front-rng.randf_range(1.8,9.5))
			var size := rng.randf_range(0.45,2.5)
			toe.y = elevation(toe)+size*0.13
			var stone: String = OUTCROPS[i%5] if i%2==0 else STONES[i%5]
			solid_rock(flora[stone],toe,Vector3(size*1.8,size*0.78,size))

func build_cliff_faces() -> void:
	# Join fractured rock columns into a single solid mesh per escarpment.
	for ridge in ridges:
		var wall := SurfaceTool.new()
		wall.begin(Mesh.PRIMITIVE_TRIANGLES)
		var center := Vector3(ridge.x,0,ridge.z)
		for col in range(-7,8):
			var u := col*3.8
			var front := -10.0 + 1.5*sin(u*0.17) + 0.72*sin(u*0.41)
			var crest := center + axis*u + side*(front+4.4)
			var height := elevation(crest)*(0.76+0.19*sin(col*2.37+ridge.x))
			var prev := PackedVector3Array()
			for level in [0.0,0.28,0.34,0.64,0.73,1.0]:
				var v: float = front-2.2+level*4.6 + (0.85 if level == 0.34 or level == 0.73 else 0.0)
				var ring := PackedVector3Array()
				for k in range(6):
					var angle := TAU*k/6.0
					var breadth := 2.55+0.62*sin(col*2.1+level*9.0)
					var point: Vector3 = center+axis*(u+cos(angle)*breadth+level*1.4*sin(col*1.7))+side*(v+sin(angle)*2.6)
					point.y = lerpf(-0.7,height-0.35,level)+level*0.95*cos(angle+col)
					ring.append(point)
				if not prev.is_empty():
					for k in range(6):
						var n := (k+1)%6
						for p in [prev[k],prev[n],ring[k],ring[k],prev[n],ring[n]]:
							wall.set_smooth_group(-1)
							wall.add_vertex(p)
				if level == 1.0:
					for k in range(1,5):
						for p in [ring[0],ring[k],ring[k+1]]:
							wall.set_smooth_group(-1)
							wall.add_vertex(p)
				prev = ring
		wall.generate_normals()
		var face := mesh(self,wall.commit(),Vector3.ZERO,Color("66685f"))
		surface(face,Color("74736a"),Vector3(1.6,11.0,1.6),0.58,true)
		face.create_trimesh_collision()

func batch_forest() -> void:
	# Combine static tree parts by location and material, retaining their collision bodies.
	var batches := {}
	var batch_materials := {}
	for source in forest_meshes:
		var source_material := source.material_override as ShaderMaterial
		if source_material == null or source_material.shader != preload("res://surface.gdshader"):
			continue
		var section := Vector2i(floori(source.position.x/20.0),floori(source.position.z/20.0))
		var key := [section,source_material]
		if not batches.has(key):
			var builder := SurfaceTool.new()
			builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			builder.set_custom_format(0,SurfaceTool.CUSTOM_RGB_FLOAT)
			batches[key] = [builder,0]
		var data: Array = batches[key]
		var builder: SurfaceTool = data[0]
		var arrays := source.mesh.surface_get_arrays(0)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var normal_basis := source.basis.inverse().transposed()
		for i in range(positions.size()):
			var local := positions[i]
			builder.set_custom(0,Color(local.x,local.y,local.z))
			builder.set_normal((normal_basis*normals[i]).normalized())
			builder.add_vertex(source.transform*local)
		if arrays[Mesh.ARRAY_INDEX] != null:
			for index in arrays[Mesh.ARRAY_INDEX]:
				builder.add_index(index+data[1])
		else:
			for index in range(positions.size()):
				builder.add_index(index+data[1])
		data[1] += positions.size()
		if source.get_child_count() > 0:
			source.mesh = null
		else:
			source.queue_free()
	for key in batches:
		var builder: SurfaceTool = batches[key][0]
		var source_material: ShaderMaterial = key[1]
		if not batch_materials.has(source_material):
			var combined_material := source_material.duplicate() as ShaderMaterial
			combined_material.set_shader_parameter("merged_geometry",true)
			batch_materials[source_material] = combined_material
		var batch := MeshInstance3D.new()
		batch.mesh = builder.commit()
		batch.material_override = batch_materials[source_material]
		add_child(batch)
	forest_meshes.clear()

func swamp_weight(pos: Vector3) -> float:
	var amount := 0.0
	for i in range(swamps.size()):
		var marsh:=swamps[i]
		var radius := (Vector2(pos.x-marsh.x,pos.z-marsh.z)/basin_sizes[i]).length()
		amount = maxf(amount,1.0-smoothstep(0.5,1.0,radius))
	return amount

func elevation(pos: Vector3) -> float:
	var flat := Vector2(pos.x,pos.z)
	var h := 1.6 + terrain_noise.get_noise_2d(pos.x,pos.z)*1.6
	for ridge in ridges:
		var across := flat-Vector2(ridge.x,ridge.z)
		var u := across.dot(Vector2(axis.x,axis.z))
		var v := across.dot(Vector2(side.x,side.z))
		if absf(u) > 42.0 or v < -16.0 or v > 60.0:
			continue
		var front := -10.0 + 1.5*sin(u*0.17) + 0.72*sin(u*0.41)
		var face := smoothstep(front,front+3.2,v)
		var ramp := 1.0-smoothstep(0.0,58.0,v)
		var ends := 1.0-smoothstep(16.0,42.0,absf(u))
		h += ridge.y*face*ramp*ends
	for pad in landmark_pads:
		var t := smoothstep(pad.y,pad.y+12.0,flat.distance_to(Vector2(pad.x,pad.z)))
		h *= t
	for i in range(swamps.size()):
		var marsh:=swamps[i]
		var shore := ((flat-Vector2(marsh.x,marsh.z))/basin_sizes[i]).length()
		h = lerpf(fall_height if i==1 else 0.0,h,smoothstep(0.95,1.57,shore))
	var coast := smoothstep(SHORE_RADIUS-10.0,ISLAND_RADIUS,flat.length())
	coast *= smoothstep(3.1,10.0,flat.distance_to(Vector2(dock.x,dock.z)))
	h = lerpf(h,-1.24,coast)-0.65*swamp_weight(pos)
	var v := pos.dot(side)
	var distance_down := absf(v)-river_origin(v)
	if distance_down > 0.0:
		var offset := absf(pos.dot(axis)-river_center(v))
		if v<0 and fall_height>0:
			var crest := river_level(v)+2.5
			h = lerpf(h,crest,(1.0-smoothstep(10.0,25.0,offset))*smoothstep(0.0,12.0,distance_down))
		var channel := (1.0-smoothstep(2.7,12.0,offset))*smoothstep(0.0,12.0,distance_down)
		var bed:=river_level(v)-0.33
		if fall_height>0 and v<0:
			# Cut the lip slightly upstream so interpolated terrain cannot poke through falling water.
			bed=minf(bed,river_level(v-3.0)-.4)
		h = lerpf(h,bed,channel)
	return h

func river_origin(v: float) -> float:
	return absf(swamps[0 if v>=0 else 1].dot(side))

func river_center(v: float) -> float:
	var d := maxf(0.0,absf(v)-river_origin(v))
	return swamps[0 if v>=0 else 1].dot(axis) + 5.5*(sin(d*0.045+river_phase)-sin(river_phase)) + 2.8*sin(d*0.087)

func river_level(v: float) -> float:
	var head := fall_height*(1.0-smoothstep(fall_distance,fall_distance+2.0,absf(v)-river_origin(v))) if v<0 else 0.0
	return head+lerpf(-0.23,-1.22,smoothstep(river_origin(v)+10,SHORE_RADIUS-5,absf(v)))

func reserved_lowland(pos: Vector3) -> bool:
	var v := pos.dot(side)
	var meadow := (Vector2(pos.dot(axis),v)-meadow_center)/meadow_size
	return meadow.length_squared()<1.0 or (absf(v)>river_origin(v) and absf(pos.dot(axis)-river_center(v))<8.0)

func build_stream(sign_v: float) -> void:
	var mesh_builder := SurfaceTool.new()
	mesh_builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var last := PackedVector3Array()
	for i in range(95):
		var v := sign_v*lerpf(river_origin(sign_v)+4.0,ISLAND_RADIUS,float(i)/94.0)
		var mid := axis*river_center(v)+side*v+Vector3.UP*river_level(v)
		var row := PackedVector3Array([mid-axis*9.0,mid+axis*9.0])
		if not last.is_empty():
			var points := [last[0],row[1],last[1],last[0],row[0],row[1]]
			if sign_v > 0:
				points.reverse()
			for point in points:
				mesh_builder.set_normal(Vector3.UP)
				mesh_builder.add_vertex(point)
		last = row
	var stream := mesh(self,mesh_builder.commit(),Vector3.ZERO,Color.WHITE)
	var mat := waters[0].duplicate() as ShaderMaterial
	mat.set_shader_parameter("current",Vector2(side.x,side.z)*sign_v*0.74)
	stream.material_override = mat
	stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	waters.append(mat)

func ground_grade(pos: Vector3) -> float:
	var dx := elevation(pos+Vector3.RIGHT)-elevation(pos+Vector3.LEFT)
	var dz := elevation(pos+Vector3.BACK)-elevation(pos+Vector3.FORWARD)
	return Vector2(dx,dz).length()*0.5

func build_terrain() -> void:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := PackedVector3Array([Vector3.ZERO])

	for ring in range(1,RINGS+1):
		for i in range(SEGMENTS):
			var angle := TAU*i/SEGMENTS
			var pos := Vector3(cos(angle),0,sin(angle))*(ISLAND_RADIUS*ring/RINGS)
			pos.y = elevation(pos)
			points.append(pos)
	for i in range(SEGMENTS):
		for index in [0,1+i,1+(i+1)%SEGMENTS]:
			builder.add_vertex(points[index])
	for ring in range(RINGS-1):
		for i in range(SEGMENTS):
			var a := 1+ring*SEGMENTS+i
			var b := 1+ring*SEGMENTS+(i+1)%SEGMENTS
			for index in [a,a+SEGMENTS,b,b,a+SEGMENTS,b+SEGMENTS]:
				builder.add_vertex(points[index])
	builder.index()
	builder.generate_normals()
	terrain_vertices = points
	var terrain := builder.commit()
	var ground := mesh(self,terrain,Vector3.ZERO,Color.WHITE)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://terrain.gdshader")
	var basins:=PackedVector4Array()
	for i in range(6):
		basins.append(Vector4(swamps[i].x,swamps[i].z,basin_sizes[i].x,basin_sizes[i].y) if i<swamps.size() else Vector4(9999,9999,1,1))
	mat.set_shader_parameter("basins",basins)
	mat.set_shader_parameter("shore_radius",SHORE_RADIUS)
	mat.set_shader_parameter("island_axis",Vector2(axis.x,axis.z))
	ground.material_override = mat
	ground.create_trimesh_collision()
	terrain_body = ground.get_child(0)
	terrain_body.collision_layer = 9
	add_water(Vector3(0,-1.22,0),Vector2(690,690),false)
	for i in range(swamps.size()):
		add_water(swamps[i]+Vector3.UP*((fall_height if i==1 else 0.0)-.23),basin_sizes[i]*2.0,true)

	build_stream(1.0)
	build_stream(-1.0)

func add_water(pos: Vector3, size: Vector2, marsh: bool) -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	var water := mesh(self,plane,pos,Color.WHITE)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://water.gdshader")
	mat.set_shader_parameter("marsh",marsh)
	mat.set_shader_parameter("basin_radius",size*.5)
	mat.set_shader_parameter("ripple_map",preload("res://weather_noise.res"))
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	waters.append(mat)

func rock_mesh() -> ArrayMesh:
	var source := SphereMesh.new()
	source.radial_segments = 14
	source.rings = 7
	var arrays := source.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(vertices.size()):
		var p := vertices[i]
		var chipped := 1.0+rock_noise.get_noise_3dv(p)*0.36+rock_noise.get_noise_3dv(p*3.7)*0.075
		vertices[i] = p*chipped
		vertices[i].y = clampf(vertices[i].y,-0.43,0.42+p.x*0.11-p.z*0.06)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var raw := ArrayMesh.new()
	raw.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var builder := SurfaceTool.new()
	builder.create_from(raw,0)
	builder.generate_normals()
	return builder.commit()

func solid_rock(shape: Mesh, pos: Vector3, size: Vector3) -> void:
	var obj := mesh(self,shape,pos,Color("77746c"))
	obj.add_to_group("rocks")
	obj.scale = size
	surface(obj,Color("77746c"),Vector3(13,17,13),0.62,true)
	obj.create_convex_collision(true,false)

func build_treehouse() -> void:
	var platform := box(deck_center + Vector3.UP * 4, Vector3(5,0.35,5), Color("664932"))
	platform.set_meta("climbable",true)
	platform.rotation.y = atan2(-axis.z, axis.x)
	platform.get_child(0).hide()
	for i in range(13):
		timber(platform,Vector3(-2.31+i*0.385,0.05,0),Vector3(0.378,0.25,5),Color("735639").lightened((i%4)*0.04))
	for x in [-1.9,1.9]:
		var brace := timber(platform,Vector3(x,-0.9,-0.65),Vector3(0.17,2.1,0.17),Color("60452d"))
		brace.rotation.x = -0.64
		for z in [-2.31,2.31]:
			timber(platform,Vector3(x,0.59,z),Vector3(0.15,1.12,0.15),Color("76583b"))
		timber(platform,Vector3(x,0.92,0.9),Vector3(0.12,0.12,2.95),Color("866344"))
	landmark_perch.platform = platform
	var ladder := Node3D.new()
	add_child(ladder)
	ladder.position = landmark_perch.base
	ladder.rotation.y = platform.rotation.y + PI*0.5
	for x in [-0.49,0.49]:
		timber(ladder,Vector3(x,2.05,0),Vector3(0.125,4.19,0.12),Color("806346"))
	for i in range(12):
		timber(ladder,Vector3(0,0.24+i*0.34,0),Vector3(1.02,0.088,0.12),Color("a07b54"))
	var rope_mesh := CylinderMesh.new()
	rope_mesh.height = 4.04
	rope_mesh.top_radius = 0.035
	rope_mesh.bottom_radius = 0.035
	mesh(platform,rope_mesh,Vector3(1.45,-1.9,2.53),Color("a48b5e"))

func tree_clearance(pos: Vector3, clearance: float) -> bool:
	var horizontal := Vector2(pos.x,pos.z)
	for site in tree_sites:
		if horizontal.distance_squared_to(Vector2(site.x,site.z)) < pow(maxf(clearance,site.y),2.0):
			return false
	return true

func add_understory(grove: Array[Vector3]) -> void:
	var thickets := grove + [axis*43.0+side*34.0, -axis*36.0+side*26.0, -axis*14.0-side*39.0, axis*61.0-side*23.0]
	for center in thickets:
		for i in range(30):
			var spot: Vector3 = center + Vector3(rng.randf_range(-10.0,10.0),0,rng.randf_range(-10.0,10.0))
			if not vegetation_ground(spot) or not tree_clearance(spot,1.9):
				continue
			if i % 4 == 0 and tree_clearance(spot,3.7):
				add_tree(spot,rng.randf_range(6.5,10.0),false,1)
			else:
				add_tree(spot,rng.randf_range(2.4,4.7),false,2 if swamp_weight(spot) > 0.04 else 0)
	for i in range(185):
		var spot := Vector3(rng.randf_range(-195,195),0,rng.randf_range(-195,195))
		if i < 45:
			spot = thickets[i%thickets.size()] + Vector3(rng.randf_range(-15,15),0,rng.randf_range(-15,15))
		elif i < 88:
			var ridge := ridges[i%ridges.size()]
			spot = Vector3(ridge.x,0,ridge.z)+axis*rng.randf_range(-23,23)+side*rng.randf_range(-2,15)
		if not vegetation_ground(spot) or not tree_clearance(spot,1.05):
			continue
		spot.y = elevation(spot)
		bushes.append(spot)
		place_flora("Tide Fern",Transform3D(Basis(Vector3.UP,rng.randf()*TAU),spot),72.0)

func place_flora(species: String, pose: Transform3D, reach := 200.0) -> MeshInstance3D:
	var model := MeshInstance3D.new()
	model.mesh = flora[species]
	model.transform = pose
	model.visibility_range_end = reach
	add_child(model)
	if flora.has(species+" distant"):
		var distant := MeshInstance3D.new()
		distant.mesh = flora[species+" distant"]
		distant.transform = pose
		# Swap to the coarse leaves only well beyond leaf-reading distance (the swap is measured to the
		# whole tree, so it used to happen right beside you up in a neighbouring crown). Both versions cast
		# shadows so shadows don't blink at the swap, and a 2 m margin stops flicker at the threshold.
		var detail_distance := clampf(24.0*pose.basis.y.length(),10.0,30.0)
		model.visibility_range_end = detail_distance
		model.visibility_range_end_margin = 2.0
		distant.visibility_range_begin = detail_distance
		distant.visibility_range_begin_margin = 2.0
		distant.visibility_range_end = reach
		add_child(distant)
	return model

func build_rainforest(groves: Array[Vector3]) -> void:
	# Offset the belts from the crash-to-radio path so there is always a clear way through.
	for center in groves:
		for i in range(46):
			var pos := center+axis*rng.randf_range(-22,25)+side*rng.randf_range(-14,15)
			if not vegetation_ground(pos) or absf(pos.dot(side))<6.5 or not tree_clearance(pos,5.8):
				continue
			add_tree(pos,rng.randf_range(20,31) if i%3==0 else rng.randf_range(11,20),false,i%2)
		for i in range(84):
			var pos := center+axis*rng.randf_range(-23,26)+side*rng.randf_range(-16,17)
			if not vegetation_ground(pos):
				continue
			pos.y = elevation(pos)
			var kind := "Tide Fern"
			if i%11 == 0:
				kind = "Lantern Shelves"
			elif i%5 == 0:
				kind = "Amethyst Rosette"
			var basis := Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(0.64,1.18))
			place_flora(kind,Transform3D(basis,pos),68)
			if kind == "Tide Fern":
				bushes.append(pos)

# ---- Dense jungle patches (ForestStudy grove as the reference) ----
# How many patches, how big, and how lush all vary per seed. Trees are layered (giants, a joined
# mid canopy, palms at the edges, saplings in the gaps) over a thick floor with natural trails.
func build_jungle(groves: Array[Vector3]) -> void:
	var lushness := rng.randf()
	var wanted := int(round(lerpf(1.0,7.0,lushness*lushness)))+(1 if rng.randf()<0.3 else 0)
	var keep_clear: Array[Vector3] = [Vector3.ZERO,field,tree,cave,radio,dock,side*18.0+axis*3.0]
	keep_clear.append_array(groves)
	var tries := 0
	while jungles.size() < wanted and tries < 80:
		tries += 1
		var angle := rng.randf()*TAU
		var center := Vector3(cos(angle),0,sin(angle))*rng.randf_range(30.0,165.0)
		var radius := rng.randf_range(15.0,lerpf(26.0,46.0,lushness))
		if center.length()+radius*0.7 > SHORE_RADIUS-6.0 or swamp_weight(center) > 0.1 or reserved_lowland(center):
			continue
		if keep_clear.any(func(p: Vector3) -> bool: return Vector2(p.x-center.x,p.z-center.z).length() < radius*1.2+12.0):
			continue
		if jungles.any(func(j: Vector4) -> bool: return Vector2(j.x-center.x,j.z-center.z).length() < (j.w+radius)*0.6):
			continue
		jungles.append(Vector4(center.x,rng.randf()*TAU,center.z,radius))
	var plants := {}
	for patch in jungles:
		grow_jungle(patch,plants)
	for i in range(400):
		var pos:=axis*rng.randf_range(-160,160)+side*rng.randf_range(-142,142)
		var group:=MEADOW
		if i%3==0:
			var n:=i/3%swamps.size()
			var a:=rng.randf()*TAU
			pos=swamps[n]+Vector3(cos(a)*basin_sizes[n].x,0,sin(a)*basin_sizes[n].y)*rng.randf_range(.95,1.18)
			group=MARGIN
		elif i%3==1:
			group=UNDERGROWTH
			var center: Vector3=groves[i%groves.size()]
			pos=center+axis*rng.randf_range(-15,15)+side*rng.randf_range(-15,15)
		if pos.length()>SHORE_RADIUS-5: continue
		for k in range(5):
			var p:=pos+Vector3(rng.randf_range(-2,2),0,rng.randf_range(-2,2))
			if absf(p.dot(side))<6 or near_jungle_bridge(p,4) or ground_grade(p)>.65: continue
			p.y=ground_surface_height(p)-.035
			add_jungle_plant(plants,group[(i/3)%group.size()],Transform3D(Basis(Vector3.UP,rng.randf()*TAU),p))
		if group==UNDERGROWTH and i%9==1 and tree_clearance(pos,2.0) and not near_jungle_bridge(pos,8) and absf(pos.dot(side))>10 and pos.distance_to(tree)>13 and pos.distance_to(cave)>13:
			pos.y=ground_surface_height(pos)-.08
			add_jungle_plant(plants,BAMBOO[(i/9)%2],Transform3D(Basis(Vector3.UP,rng.randf()*TAU),pos))
	batch_jungle_plants(plants)

func jungle_point(patch: Vector4) -> Vector3:
	var a := rng.randf()*TAU
	var reach := sqrt(rng.randf())*jungle_reach(patch,a)
	return Vector3(patch.x+cos(a)*reach,0,patch.z+sin(a)*reach)

# Irregular outline so patches read as natural growth, not circles.
func jungle_reach(patch: Vector4, a: float) -> float:
	return patch.w*(0.86+0.2*sin(3.0*a+patch.y)+0.1*sin(5.0*a+patch.y*1.7))

# 0 at the centre, 1 at the outline.
func jungle_depth(pos: Vector3, patch: Vector4) -> float:
	var offset := Vector2(pos.x-patch.x,pos.z-patch.z)
	return offset.length()/jungle_reach(patch,offset.angle())

func trail_distance(pos: Vector3, trails: Array) -> float:
	var best := INF
	for trail in trails:
		var rel: Vector3 = pos-trail[0]
		var u := rel.dot(trail[1])
		var expected: float = trail[3]*sin(u*trail[4]+trail[5])
		best = minf(best,absf(rel.dot(trail[2])-expected))
	return best

func near_jungle_bridge(pos: Vector3, reach: float) -> bool:
	for span in jungle_bridges:
		var a := Vector2(span[0].x,span[0].z)
		var b := Vector2(span[1].x,span[1].z)
		var p := Vector2(pos.x,pos.z)
		var t := clampf((p-a).dot(b-a)/(b-a).length_squared(),0.0,1.0)
		if p.distance_to(a.lerp(b,t)) < reach:
			return true
	return false

# How deep under the joined jungle roof a point is. Only counts below the canopy, not on top of it.
func canopy_cover(pos: Vector3) -> float:
	if pos.y-elevation(pos) > 12.0:
		return 0.0
	var amount := 0.0
	for patch in jungles:
		if Vector2(pos.x-patch.x,pos.z-patch.z).length() < patch.w*1.3:
			amount = maxf(amount,1.0-smoothstep(0.55,0.95,jungle_depth(pos,patch)))
	return amount

func jungle_ground(pos: Vector3) -> bool:
	return vegetation_ground(pos) and absf(pos.dot(side)) > 6.5 and pos.distance_to(Vector3.ZERO) > 14.0

func grow_jungle(patch: Vector4, plants: Dictionary) -> void:
	var center := Vector3(patch.x,0,patch.z)
	var radius := patch.w
	var trails: Array = []
	for i in range(1 if rng.randf() < 0.55 else 2):
		var along := Vector3.RIGHT.rotated(Vector3.UP,rng.randf()*TAU)
		trails.append([center+along.cross(Vector3.UP)*rng.randf_range(-radius,radius)*0.3,along,along.cross(Vector3.UP),rng.randf_range(2.0,6.0),rng.randf_range(0.05,0.13),rng.randf()*TAU])
	jungle_trails.append_array(trails)
	# Walkable crossings first, so the rest of the patch grows around them.
	var bridges := rng.randi_range(1,2) if radius > 24.0 else (1 if rng.randf() < 0.6 else 0)
	for b in range(bridges):
		for attempt in range(40):
			var a := jungle_point(patch)
			var dir := Vector3.RIGHT.rotated(Vector3.UP,rng.randf()*TAU)
			var far := a+dir*rng.randf_range(15.0,19.0)
			if jungle_depth(a,patch) > 0.85 or jungle_depth(far,patch) > 0.85 or not jungle_ground(a) or not jungle_ground(far):
				continue
			# Level ground at both ends keeps the trunk walkable rather than a ramp.
			if absf(elevation(a)-elevation(far)) > 1.6 or ground_grade(a) > 0.55 or ground_grade(far) > 0.55:
				continue
			if trail_distance(a,trails) < 4.0 or trail_distance(far,trails) < 4.0:
				continue
			if range(6).any(func(k: int) -> bool: return near_jungle_bridge(a.lerp(far,k/5.0),7.0)):
				continue
			if not tree_clearance(a,7.0) or not tree_clearance(far,7.0):
				continue
			# Nothing already standing (e.g. an older grove) may reach into the span.
			if not range(1,6).all(func(k: int) -> bool: return tree_clearance(a.lerp(far,k/6.0),7.5)):
				continue
			var before := perches.size()
			if not add_tree(a,rng.randf_range(24.0,28.0),false,0,dir) or perches.size() == before:
				continue
			var first: TreePerch = perches.back()
			if add_tree(far,rng.randf_range(24.0,28.0),false,0,-dir) and perches.size() == before+2:
				var second: TreePerch = perches.back()
				if not crossing_clear(first.higher.seat,second.higher.seat):
					continue  # the giants stay; only the bridge is skipped
				add_crossing(first.higher.seat,second.higher.seat)
				jungle_bridges.append([first.higher.seat,second.higher.seat])
				break
	# Layered trees, packed so the mid canopy closes overhead.
	var crowns: Array[Vector4] = []
	for i in range(int(PI*radius*radius/7.0)):
		var pos := jungle_point(patch)
		var depth := jungle_depth(pos,patch)
		if rng.randf() < smoothstep(0.72,1.0,depth) or not jungle_ground(pos) or trail_distance(pos,trails) < 2.6 or near_jungle_bridge(pos,4.5):
			continue
		var roll := rng.randf()
		var height := 0.0
		if roll < 0.08 and depth < 0.75 and tree_clearance(pos,6.5) and not near_jungle_bridge(pos,9.5):
			height = rng.randf_range(21.0,29.0)
			if not add_tree(pos,height):
				continue
		elif roll < 0.6 and tree_clearance(pos,3.6) and not near_jungle_bridge(pos,6.5):
			height = rng.randf_range(10.0,17.0)
			if not add_tree(pos,height,false,rng.randi()%2):
				continue
		elif roll < 0.7 and depth > 0.5 and tree_clearance(pos,6.8):
			add_jungle_tree("Arch Palm",pos,rng.randf_range(6.8,10.0),6.8)
			continue
		elif tree_clearance(pos,1.6):
			add_jungle_tree("Young Shelfwood",pos,rng.randf_range(3.4,4.8),1.4)
			continue
		else:
			continue
		crowns.append(Vector4(pos.x,elevation(pos),pos.z,height))
	# Vines draped between neighbouring crowns.
	for c in crowns:
		if rng.randf() > 0.45:
			continue
		for other in crowns:
			var gap := Vector2(other.x-c.x,other.z-c.z).length()
			if gap < 4.0 or gap > 11.0:
				continue
			var a := Vector3(c.x,c.y+c.w*rng.randf_range(0.5,0.62),c.z)
			var b := Vector3(other.x,other.y+other.w*rng.randf_range(0.5,0.62),other.z)
			a += (b-a).normalized()*1.2
			b -= (b-a).normalized()*1.2
			var span := b-a
			add_jungle_plant(plants,"Curtain Vine",Transform3D(Basis(span/6.0,Vector3.UP,span.cross(Vector3.UP).normalized()),a))
			break
	# Floor: dense, with only creepers on the trails.
	var trunks: Array[Vector3] = []
	for site in tree_sites:
		if Vector2(site.x-center.x,site.z-center.z).length() < radius*1.35+4.0:
			trunks.append(site)
	for i in range(int(PI*radius*radius/2.6)):
		var pos := jungle_point(patch)
		if rng.randf() < smoothstep(0.75,1.05,jungle_depth(pos,patch)) or not jungle_ground(pos):
			continue
		var kind := "Creeper Mat"
		if trail_distance(pos,trails) < 2.3:
			if rng.randf() > 0.35:
				continue
		else:
			var roll := rng.randf()
			kind = "Elephant Ear" if roll < 0.32 else ("Creeper Mat" if roll < 0.56 else ("Tide Fern" if roll < 0.82 else ("Amethyst Rosette" if roll < 0.89 else ("Lantern Shelves" if roll < 0.95 else "Lantern Orchid"))))
		if kind != "Creeper Mat" and trunks.any(func(t: Vector3) -> bool: return Vector2(t.x-pos.x,t.z-pos.z).length() < 1.15):
			continue
		pos.y = elevation(pos)
		var size := rng.randf_range(0.7,1.2)
		add_jungle_plant(plants,kind,Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*size),pos))
		if kind in ["Elephant Ear","Tide Fern"]:
			bushes.append(pos)

# Sweep a player-sized capsule along the planned crossing; any branch in the way rejects it.
# Follows the trunk's own sway (see bridge_point in the crossing model) between the two seats.
func crossing_clear(start: Vector3, end: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var body_shape := CapsuleShape3D.new()
	body_shape.radius = 0.36
	body_shape.height = 1.15
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body_shape
	query.collision_mask = 1
	var across := (end-start).cross(Vector3.UP).normalized()
	# Every 0.3 m, so a thin branch can't slip between samples.
	var samples := maxi(13,ceili(start.distance_to(end)*0.76/0.3))
	for k in range(samples+1):
		var t := lerpf(0.12,0.88,float(k)/samples)
		var path := start.lerp(end,t)+across*0.55*sin(t*TAU)+Vector3.UP*(0.85*sin(t*TAU)+0.72)
		query.transform = Transform3D(Basis.IDENTITY,path)
		if not space.intersect_shape(query,1).is_empty():
			return false
	return true

# Saplings and palms: rooted like the big trees, solid trunks, but too small or smooth to climb.
func add_jungle_tree(kind: String, pos: Vector3, height: float, site_radius: float) -> void:
	pos.y = elevation(pos)
	var basis := Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*height/(4.6 if kind == "Young Shelfwood" else 8.4))
	var planted := rooted_height(kind,basis,pos)
	if pos.y-planted > 0.8:
		return
	pos.y = planted
	tree_sites.append(Vector3(pos.x,site_radius,pos.z))
	var pose := Transform3D(basis,pos)
	place_flora(kind,pose,95.0 if kind == "Arch Palm" else 70.0)
	if not trunk_shapes.has(kind):
		var woody := ArrayMesh.new()
		woody.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,flora[kind].surface_get_arrays(0))
		trunk_shapes[kind] = woody.create_trimesh_shape()
	var body := StaticBody3D.new()
	var hit := CollisionShape3D.new()
	hit.shape = trunk_shapes[kind]
	body.add_child(hit)
	body.transform = pose
	add_child(body)
	if kind == "Arch Palm" and height >= LOWEST_CLIMBABLE_TREE:
		body.set_meta("climbable",true)
		palm_perch(pose,pos,body)

# Palms have no walkable limbs: one fork up in the crown, reached by climbing the leaning trunk on its side.
func palm_perch(pose: Transform3D, pos: Vector3, trunk_body: StaticBody3D, kind := "Arch Palm") -> void:
	var skel: Dictionary = skeletons[kind]
	var site := TreePerch.new()
	site.trunk = pos
	site.pose = pose
	site.kind = kind
	var s := pose.basis.x.length()
	site.reach = float(skel.crownReach)*s+1.0
	var top_local := sk_point(skel.trunk[skel.trunk.size()-1])
	var lean := pose.basis*Vector3(top_local.x,0,top_local.z)
	site.heading = lean.normalized() if lean.length() > 0.05 else Vector3.FORWARD
	site.approach = site.heading.rotated(Vector3.UP,PI*0.5)
	site.seat = pose*top_local+Vector3.UP*0.12
	site.climb_anchor = trunk_point(site,site.seat.y-0.35,site.approach)
	site.step_off = site.climb_anchor
	site.width = float(skel.trunkRadii[0])*s
	site.base = pos+site.approach*(site.width+0.55)
	site.base.y = ground_surface_height(site.base)
	site.pad = box(site.seat-Vector3.UP*0.06,Vector3(1.5,0.1,1.5),Color.BLACK)
	site.pad.get_child(0).hide()
	site.pad.set_meta("climbable",true)
	site.wood.append_array([site.pad.get_rid(),trunk_body.get_rid()])
	perches.append(site)

# Points up the trunk on one side, about every 1.5 m, so climbs follow a bending or leaning trunk.
func trunk_line(site: TreePerch, from_y: float, to_y: float, side_dir: Vector3) -> PackedVector3Array:
	var line := PackedVector3Array()
	var steps := maxi(1,ceili(absf(to_y-from_y)/1.5))
	for k in range(1,steps):
		line.append(trunk_point(site,lerpf(from_y,to_y,float(k)/steps),side_dir))
	return line

func add_jungle_plant(plants: Dictionary, kind: String, pose: Transform3D) -> void:
	var key := [kind,Vector2i(floori(pose.origin.x/28.0),floori(pose.origin.z/28.0))]
	if not plants.has(key):
		plants[key] = []
	plants[key].append(pose)

# One MultiMesh per species per 28 m cell keeps thousands of floor plants to a few draw calls.
func batch_jungle_plants(plants: Dictionary) -> void:
	const REACH := {"Elephant Ear":78.0,"Creeper Mat":48.0,"Tide Fern":72.0,"Amethyst Rosette":60.0,"Lantern Shelves":64.0,"Lantern Orchid":64.0,"Curtain Vine":90.0}
	for key in plants:
		var poses: Array = plants[key]
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = flora[key[0]]
		batch.instance_count = poses.size()
		for i in range(poses.size()):
			batch.set_instance_transform(i,poses[i])
		var chunk := MultiMeshInstance3D.new()
		chunk.multimesh = batch
		chunk.visibility_range_end = REACH.get(key[0],62.0)
		chunk.visibility_range_end_margin = 6.0
		if key[0] in ["Creeper Mat","Lantern Orchid","Curtain Vine"]:
			chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(chunk)

func on_cliff_approach(pos: Vector3) -> bool:
	for ridge in ridges:
		var offset := pos - Vector3(ridge.x,0,ridge.z)
		if absf(offset.dot(axis)) < 3.6 and offset.dot(side) > -4.0 and offset.dot(side) < 60.0:
			return true
	return false

func vegetation_ground(pos: Vector3) -> bool:
	return (not reserved_lowland(pos) and not on_cliff_approach(pos) and pos.length() < SHORE_RADIUS-2.0 and absf(pos.dot(side)) > 3.7
		and pos.distance_to(tree) > 7.5 and pos.distance_to(field) > 8.0
		and pos.distance_to(cave) > 7.6 and pos.distance_to(radio) > 5.0
		and swamp_weight(pos) < 0.52 and ground_grade(pos) < 0.69)

# Interpolate the same polar triangles used for terrain rendering and collision.
func ground_surface_height(p: Vector3) -> float:
	var angle := fposmod(atan2(p.z,p.x),TAU)*SEGMENTS/TAU
	var sector := floori(angle)%SEGMENTS
	var step := TAU/SEGMENTS
	var inside := (angle-floorf(angle))*step
	var radius := Vector2(p.x,p.z).length()*RINGS/ISLAND_RADIUS
	var u := radius*sin(step-inside)/sin(step)
	var v := radius*sin(inside)/sin(step)
	var ring := clampi(floori(u+v),0,RINGS-1)
	var t := clampf(u+v-ring,0.0,1.0)
	var next := (sector+1)%SEGMENTS
	var c := terrain_vertices[1+ring*SEGMENTS+sector].y
	var d := terrain_vertices[1+ring*SEGMENTS+next].y
	if ring == 0:
		return terrain_vertices[0].y*(1.0-t)+c*u+d*v
	var a := terrain_vertices[1+(ring-1)*SEGMENTS+sector].y
	var b := terrain_vertices[1+(ring-1)*SEGMENTS+next].y
	if v <= ring*(1.0-t):
		return a*(1.0-t-v/ring)+b*v/ring+c*t
	return b*(1.0-t)+c*u/(ring+1)+d*(t-u/(ring+1))

func rooted_height(kind: String, basis: Basis, pos: Vector3) -> float:
	if not root_contacts.has(kind):
		var contacts := PackedVector3Array()
		var wood: PackedVector3Array = flora[kind].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in wood:
			if vertex.y <= 0.10:
				contacts.append(vertex)
		root_contacts[kind] = contacts
	var y := ground_surface_height(pos)
	for contact in root_contacts[kind]:
		var offset: Vector3 = basis*contact
		y = minf(y,ground_surface_height(pos+offset)-offset.y)
	return y-0.08

# facing: for a Shelfwood that anchors a jungle crossing, turn its crown opening and high perch that way.
func add_tree(pos: Vector3, height: float, landmark := false, species := 0, facing := Vector3.ZERO) -> bool:
	pos.y = 0.0
	var kind: String = (["Shelfwood","Veil Banyan","Crown Fern"]+CANOPY)[species]
	if kind=="Crest Palm" and not tree_clearance(pos,6.8): return false
	var native_height: float = [29.0,18.0,13.0,15.0,19.0,8.0,9.0][species]
	var scale_factor := height/native_height
	var roots := (3.0 if species==2 else 8.5)*scale_factor
	var first_tree := side*18.0+axis*3.0
	if pos != first_tree and pos.distance_to(first_tree) < 9.0: return false
	var on_span := pos != first_tree and pos.distance_to(Geometry3D.get_closest_point_to_segment(pos,first_tree,tree)) < maxf(3.8,scale_factor*(13.0 if height>17.0 else 4.0))
	if not landmark and (pos.distance_to(field+side*3.0)<17.0 or on_span or pos.distance_to(cave)<roots+6.0 or pos.distance_to(tree)<roots+6.0 or absf(pos.dot(side))<roots+2.0 or pos.distance_to(radio)<roots+4.0):
		return false
	pos.y = elevation(pos)
	var rotation_basis := Basis(Vector3.UP,rng.randf()*TAU)
	if landmark or Vector2(pos.x-first_tree.x,pos.z-first_tree.z).length()<0.1:
		var exit_dir := (first_tree-tree).normalized() if landmark else (tree-first_tree).normalized()
		rotation_basis = align_crossing_tree(exit_dir)
	elif facing != Vector3.ZERO:
		rotation_basis = align_crossing_tree(facing)
	var model_basis := rotation_basis.scaled(Vector3.ONE*scale_factor)
	var planting_height := rooted_height(kind,model_basis,pos)
	if not landmark and pos.distance_to(first_tree)>4.0 and pos.y-planting_height>minf(2.4,height*0.16):
		return false
	pos.y = planting_height
	tree_sites.append(Vector3(pos.x,6.8 if kind=="Crest Palm" else 6.2 if height > 20.0 else (3.1 if height >= LOWEST_CLIMBABLE_TREE else 1.70),pos.z))
	var pose := Transform3D(model_basis,pos)
	place_flora(kind,pose,clampf(height*7.0,47.0,188.0))
	# Share the actual woody surface for trunk, buttress, and aerial-root collisions.
	if not trunk_shapes.has(kind):
		var woody := ArrayMesh.new()
		woody.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,flora[kind].surface_get_arrays(0))
		trunk_shapes[kind] = woody.create_trimesh_shape()
	var body := StaticBody3D.new()
	var hit := CollisionShape3D.new()
	hit.shape = trunk_shapes[kind]
	body.add_child(hit)
	body.transform = pose
	add_child(body)
	if kind == "Crest Palm" and height >= LOWEST_CLIMBABLE_TREE:
		body.set_meta("climbable",true)
		palm_perch(pose,pos,body,kind)
	elif height >= LOWEST_CLIMBABLE_TREE and skeletons.has(kind):
		var heading := axis if landmark else rotation_basis.x
		var anchored := landmark or facing != Vector3.ZERO or pos.distance_to(first_tree)<3.0
		if pos.distance_to(first_tree)<3.0:
			heading = (tree-first_tree).normalized()
		elif facing != Vector3.ZERO:
			heading = facing
		var width := (float(skeletons[kind].trunkRadii[0]) if species>=3 else (1.85 if species==0 else 1.45))*scale_factor
		add_tree_perches(pos,height,width,heading,rotation_basis.x*(0.9*scale_factor),landmark,pose,kind,anchored)
		var footing := StaticBody3D.new()
		var footing_hit := CollisionShape3D.new()
		footing_hit.shape = footing_shape(kind)
		footing.add_child(footing_hit)
		footing.transform = pose
		footing.set_meta("climbable",true)
		add_child(footing)
		body.set_meta("climbable",true)
		var root: TreePerch = landmark_perch if landmark else perches.back()
		for fork: TreePerch in [root,root.higher]:
			fork.wood.append_array([footing.get_rid(),body.get_rid()])
	return true

# Invisible flat strips along the tops of the main branches (from the trunk to the outer fork).
# Their tips and all side twigs keep only round bark collision, so thin wood stays awkward to walk.
func footing_shape(kind: String) -> ConcavePolygonShape3D:
	if footing_shapes.has(kind):
		return footing_shapes[kind]
	var faces := PackedVector3Array()
	for limb in skeletons[kind].branches:
		for k in range(2):
			var a := sk_point(limb.points[k])
			var b := sk_point(limb.points[k+1])
			var ra: float = limb.radii[k]
			var rb: float = limb.radii[k+1]
			var across := Vector3(b.z-a.z,0,a.x-b.x).normalized()
			var ta := a+Vector3.UP*ra
			var tb := b+Vector3.UP*rb
			faces.append_array([ta-across*ra*1.15,tb-across*rb*1.15,tb+across*rb*1.15,ta-across*ra*1.15,tb+across*rb*1.15,ta+across*ra*1.15])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	footing_shapes[kind] = shape
	return shape

func sk_point(p: Array) -> Vector3:
	return Vector3(p[0],p[1],p[2])

# Trunk axis and radius at a world height, read from the skeleton. Returns [centre, radius].
func trunk_at(site: TreePerch, y: float) -> Array:
	var skel: Dictionary = skeletons[site.kind]
	var s := site.pose.basis.x.length()
	var segments: int = skel.trunk.size()-1
	var f := clampf((y-site.pose.origin.y)/s/float(skel.height)*segments,0.0,segments-0.001)
	var j := int(f)
	var center := sk_point(skel.trunk[j]).lerp(sk_point(skel.trunk[j+1]),f-j)
	var world := site.pose*center
	world.y = y
	return [world,lerpf(skel.trunkRadii[j],skel.trunkRadii[j+1],f-j)*s]

# A point just off the bark at height y, on the given side of the trunk.
func trunk_point(site: TreePerch, y: float, dir: Vector3) -> Vector3:
	var at := trunk_at(site,y)
	return at[0]+dir*(at[1]+0.49)

# Points around the trunk at one height, so a climb never cuts through the wood.
func trunk_arc(site: TreePerch, y: float, from: Vector3, to: Vector3) -> PackedVector3Array:
	var turn := Vector2(from.x,from.z).angle_to(Vector2(to.x,to.z))
	var steps := maxi(1,ceili(absf(turn)/0.7))
	var route := PackedVector3Array()
	for k in range(steps+1):
		route.append(trunk_point(site,y,from.rotated(Vector3.UP,-turn*k/steps)))
	return route

# Put a fork on one of the model's main branches: the seat is on top of the branch a little way out.
func branch_perch(site: TreePerch, limb: Dictionary, width: float) -> void:
	var s := site.pose.basis.x.length()
	var pts: Array[Vector3] = []
	for p in limb.points:
		pts.append(sk_point(p))
	var trunk_r: float = trunk_at(site,(site.pose*pts[0]).y)[1]/s
	var want := trunk_r+0.9/s
	var seat_local := pts[2]
	var r_local: float = limb.radii[2]
	for k in range(2):
		var da := Vector2(pts[k].x-pts[0].x,pts[k].z-pts[0].z).length()
		var db := Vector2(pts[k+1].x-pts[0].x,pts[k+1].z-pts[0].z).length()
		if db >= want:
			var u := clampf((want-da)/maxf(db-da,0.001),0.0,1.0)
			seat_local = pts[k].lerp(pts[k+1],u)
			r_local = lerpf(limb.radii[k],limb.radii[k+1],u)
			break
	site.seat = site.pose*seat_local+Vector3.UP*(r_local*s+0.03)
	var out := site.pose.basis*(pts[1]-pts[0])
	site.heading = Vector3(out.x,0,out.z).normalized()
	site.width = width
	site.limb_t = limb.t
	# Hidden footpad so arriving at the fork never slips off on a twig.
	if site.pad != null:
		site.wood.erase(site.pad.get_rid())
		site.pad.free()
	site.pad = box(site.seat-Vector3.UP*0.06,Vector3(0.95,0.1,1.1),Color.BLACK)
	site.pad.rotation.y = atan2(site.heading.x,site.heading.z)
	site.pad.get_child(0).hide()
	site.pad.set_meta("climbable",true)
	site.wood.append(site.pad.get_rid())
	site.approach = site.heading.rotated(Vector3.UP,0.8)
	site.climb_anchor = trunk_point(site,site.seat.y+0.05,site.approach)
	site.step_off = trunk_point(site,site.seat.y+0.05,site.heading)
	site.base = site.trunk+site.approach*(width+0.53)
	site.base.y = ground_surface_height(site.base)

func align_crossing_tree(exit_dir: Vector3) -> Basis:
	# Fit the exit through an existing opening in the Shelfwood crown.
	var wood: PackedVector3Array = flora["Shelfwood"].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var best := Basis.IDENTITY
	var best_score := -INF
	for i in range(36):
		var basis := Basis(Vector3.UP,TAU*i/36.0)
		var local_dir := basis.inverse()*exit_dir
		var lateral := local_dir.cross(Vector3.UP)
		var seat_center := Vector3(0.9*sin(0.74*3.0),29*0.74,0.47*sin(0.74*5.0))
		var clearance := 8.0
		for vertex in wood:
			var rel := vertex-seat_center
			# The crossing log now reaches the bark, so the opening must be clear from close to the trunk.
			if rel.dot(local_dir)<1.0 or rel.y < -0.7 or rel.y > 3.4:
				continue
			clearance = minf(clearance,absf(rel.dot(lateral)))
		if clearance>best_score:
			best_score = clearance
			best = basis
	return best

# Two forks per tree: the lowest real branch, and a high one. Bridge anchors (anchored) keep their high seat
# where the crossing lands, on a hidden pad; everything else sits on the model's own branches.
func add_tree_perches(pos: Vector3, height: float, width: float, heading: Vector3, bend: Vector3, landmark: bool, pose: Transform3D, kind: String, anchored: bool) -> void:
	var limbs: Array = skeletons[kind].branches
	var reach := 0.0
	for limb in limbs:
		var tip := sk_point(limb.points[3])
		reach = maxf(reach,Vector2(tip.x,tip.z).length())
	var spot := TreePerch.new()
	spot.trunk = pos
	spot.pose = pose
	spot.kind = kind
	spot.reach = reach*pose.basis.x.length()+1.0
	spot.heading = heading
	if landmark:
		spot.base = deck_center + side*2.05 + axis*1.10
		spot.seat = deck_center + Vector3.UP*4.18
		spot.climb_anchor = Vector3(spot.base.x,spot.seat.y+0.10,spot.base.z)
		spot.approach = heading
		spot.step_off = spot.climb_anchor
		spot.leafy = false
	else:
		branch_perch(spot,limbs[0],width)
	var high := TreePerch.new()
	high.trunk = pos
	high.pose = pose
	high.kind = kind
	high.reach = spot.reach
	high.base = spot.base
	var high_t := 0.74 if height > 20.0 else 0.69
	if anchored:
		high.heading = (side*18.0+axis*3.0-tree).normalized() if landmark else heading
		high.approach = high.heading
		build_limb_perch(high,bend,height,width,height*high_t)
		high.step_off = high.climb_anchor
	else:
		var best: Dictionary = limbs[limbs.size()-1]
		for limb in limbs:
			if limb.t > limbs[0].t+0.1 and absf(limb.t-high_t) < absf(best.t-high_t):
				best = limb
		branch_perch(high,best,width)
		high.base = spot.base
	spot.higher = high
	perches.append(spot)
	if landmark:
		landmark_perch = spot

func trunk_center(pos: Vector3, bend: Vector3, height: float, y: float) -> Vector3:
	return pos + Vector3.UP*y + bend*sin(3.0*y/height) + bend.cross(Vector3.UP)*(0.47/0.9)*sin(5.0*y/height)

func trunk_radius(width: float, t: float) -> float:
	return width*(0.72*pow(1.0-t,0.70)+0.19*exp(-t*18.0)+0.07)

func build_limb_perch(site: TreePerch, bend: Vector3, height: float, width: float, y: float) -> void:
	var center := trunk_center(site.trunk,bend,height,y)
	var radius := trunk_radius(width,y/height)
	# Only bridge anchors use this. The crossing log runs right up to the bark in the crown opening that
	# align_crossing_tree turned toward the partner tree, so the seat is the log's end beside the trunk.
	site.climb_anchor = center+site.heading*(radius+0.49)+Vector3.UP*0.10
	site.seat = center+site.heading*(radius+0.8)

# Each spray begins at a woody fork. Its stems and leaves share the same transform.
func spray_stem(shape: SurfaceTool, a: Vector3, b: Vector3, radius: float) -> void:
	var side := (b-a).cross(Vector3.UP).normalized()*radius
	for width in [side,Vector3.UP*radius]:
		for point in [a-width,a+width,b-width*0.4,a+width,b+width*0.4,b-width*0.4]:
			shape.set_normal(Vector3.UP)
			shape.set_uv(Vector2(-1,0))
			shape.add_vertex(point)

func add_leaves() -> void:
	var shape := SurfaceTool.new()
	shape.begin(Mesh.PRIMITIVE_TRIANGLES)
	var end := Vector3(0,0.23,1.0)
	spray_stem(shape,Vector3.ZERO,end,0.021)
	for shoot in range(7):
		var start := end*(0.14+float(shoot)*0.12)
		var sign_x := -1.0 if shoot%2 == 0 else 1.0
		var tip := start+Vector3(sign_x*(0.45-0.028*shoot),0.05,0.24)
		spray_stem(shape,start,tip,0.009)
		for i in range(9):
			var root := start.lerp(tip,0.13+0.10*i)
			var direction := Vector3(sign_x*0.13,0.032*sin(i*2.1),0.17 if i%2 == 0 else -0.16)
			var across := direction.cross(Vector3.UP).normalized()*0.05
			var middle := root+direction*0.51+Vector3.UP*0.015
			var points := [root,middle-across,root+direction,middle+across]
			var coords := [Vector2(0.5,0),Vector2(0,0.5),Vector2(0.5,1),Vector2(1,0.5)]
			for k in [0,1,2,0,2,3]:
				shape.set_normal(Vector3.UP)
				shape.set_uv(coords[k])
				shape.add_vertex(points[k])
	var chunks := {}
	var near_chunks := {}
	for cluster in leaf_clusters:
		var phase := rng.randf_range(0,TAU)
		for j in range(7):
			var yaw := phase+j*2.4
			var tilt := rng.randf_range(-0.46,0.22)
			var basis := Basis(Vector3.UP,yaw)*Basis(Vector3.RIGHT,tilt)
			var reach := rng.randf_range(0.78,1.15)
			var spray := cluster*Transform3D(basis.scaled(Vector3.ONE*reach),Vector3.ZERO)
			var tint := Color("314d38").lerp(Color("738653"),rng.randf())
			add_vegetation(chunks if j%2 == 0 else near_chunks,spray,tint)
	var leaf_material := ShaderMaterial.new()
	leaf_material.shader = preload("res://leaves.gdshader")
	var spray_mesh := shape.commit()
	build_vegetation(chunks,spray_mesh,leaf_material,195.0)
	build_vegetation(near_chunks,spray_mesh,leaf_material,68.0)
	leaf_clusters.clear()

func add_vegetation(chunks: Dictionary, transform_in_world: Transform3D, tint: Color) -> void:
	var pos := transform_in_world.origin
	var key := Vector3(floorf(pos.x/16.0)*16.0,0,floorf(pos.z/16.0)*16.0)
	if not chunks.has(key):
		chunks[key] = [[],[]]
	transform_in_world.origin -= key
	chunks[key][0].append(transform_in_world)
	chunks[key][1].append(tint)

func build_vegetation(chunks: Dictionary, model: Mesh, mat: Material, max_distance: float) -> void:
	for key in chunks:
		var data: Array = chunks[key]
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.use_colors = true
		instances.mesh = model
		instances.instance_count = data[0].size()
		for i in range(instances.instance_count):
			instances.set_instance_transform(i,data[0][i])
			instances.set_instance_color(i,data[1][i])
		var chunk := MultiMeshInstance3D.new()
		chunk.multimesh = instances
		chunk.material_override = mat
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.visibility_range_end = max_distance
		chunk.visibility_range_end_margin = 9.0
		add_child(chunk)
		chunk.position = key

func add_grass() -> void:
	var blender := SurfaceTool.new()
	blender.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(24):
		var angle := i*2.39996
		var direction := Vector3(cos(angle),0,sin(angle))
		var across := Vector3(-direction.z,0,direction.x)
		var root := direction*(0.82*sqrt(float(i)/24.0))
		var blade_height := 0.30+0.32*fmod(i*0.618,1.0)
		var tip := root+direction*0.13+Vector3.UP*blade_height
		for vertex in [root-across*0.023,tip,root+across*0.023]:
			blender.set_normal(Vector3.UP)
			blender.add_vertex(vertex)
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = preload("res://grass.gdshader")
	var ordinary := 106000
	var chunks := {}
	var reed_chunks := {}
	var cattail_chunks := {}
	var grades := {}
	for i in range(ordinary + cover.size() * 150):
		var spot: Vector3
		var bank := false
		var scale_y := rng.randf_range(0.55,0.98)
		if i < ordinary:
			var angle := rng.randf_range(0,TAU)
			spot = Vector3(cos(angle),0,sin(angle)) * sqrt(rng.randf()) * (SHORE_RADIUS-2.0)
		else:
			var patch := cover[floori(float(i-ordinary)/150.0)]
			spot = patch + Vector3(rng.randf_range(-1.9,1.9),0,rng.randf_range(-1.9,1.9))
			bank = swamp_weight(patch) > 0.01
			scale_y = rng.randf_range(1.1,1.75)
		var sector := Vector2i(floori(spot.x/3.0),floori(spot.z/3.0))
		if not grades.has(sector):
			grades[sector] = ground_grade(Vector3(sector.x*3.0+1.5,0,sector.y*3.0+1.5))
		if (absf(spot.dot(side)) > river_origin(spot.dot(side))+9 and absf(spot.dot(axis)-river_center(spot.dot(side))) < 4.2) or grades[sector] > 0.95 or spot.distance_to(cave) < 4.0 or swamp_weight(spot) > (0.9 if bank else 0.61):
			continue
		spot.y = elevation(spot)-0.035
		var width := rng.randf_range(0.65,1.25)
		var basis := Basis(Vector3.UP,rng.randf_range(0,TAU)).scaled(Vector3(width,scale_y,width))
		if bank:
			var reeds := cattail_chunks if i % 9 == 0 else reed_chunks
			add_vegetation(reeds,Transform3D(basis,spot),Color("44523c").lerp(Color("807c52"),rng.randf()))
		else:
			add_vegetation(chunks,Transform3D(basis,spot),Color("496441").lerp(Color("77844f"),rng.randf()))
	build_vegetation(chunks,blender.commit(),grass_mat,55.0)
	build_vegetation(reed_chunks,marsh_reed_mesh(false),grass_mat,55.0)
	build_vegetation(cattail_chunks,marsh_reed_mesh(true),grass_mat,50.0)

func marsh_reed_mesh(seed_head: bool) -> ArrayMesh:
	var blades := SurfaceTool.new()
	blades.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(5):
		var out := Vector3.FORWARD.rotated(Vector3.UP,i*2.4)
		var width := out.cross(Vector3.UP)*0.028
		var base := out*0.04
		var bend := out*(0.10+0.024*i) + Vector3.UP*(0.55+0.06*i)
		var tip := bend + out*(0.15+0.06*i) + Vector3.UP*(0.18+0.06*i)
		var points := [base-width,base+width,bend-width*0.55,bend+width*0.55,tip]
		for index in [0,2,1,1,2,3,2,4,3]:
			blades.set_uv(Vector2(0.0,[0.0,1.0,0.0,1.0,0.5][index]))
			blades.set_normal(Vector3.UP)
			blades.add_vertex(points[index])
	if seed_head:
		var profile := [Vector2(0.008,0),Vector2(0.008,1.02),Vector2(0.022,1.05),
			Vector2(0.021,1.17),Vector2(0.005,1.20),Vector2(0.001,1.23)]
		for level in range(profile.size()-1):
			for face in range(5):
				for corner in [0,2,1,1,2,3]:
					var ring: Vector2 = profile[level + (corner >> 1)]
					var radial := Vector3.RIGHT.rotated(Vector3.UP,TAU*(face + (corner % 2))/5.0)
					blades.set_uv(Vector2(1.0 if level > 0 else 0.0,0.5))
					blades.set_normal(radial)
					blades.add_vertex(radial*ring.x + Vector3(0.028,1.0,0.036)*ring.y)
	return blades.commit()

func marker_at(pos: Vector3, label: String, height: float) -> void:
	var anchor := Node3D.new()
	add_child(anchor)
	anchor.position = pos
	marker(anchor,label,height)

func marker(parent: Node3D, label: String, height: float) -> void:
	var tag := Label3D.new()
	tag.text = label
	tag.font_size = 40
	tag.pixel_size = 0.012
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color("f8dfae")
	parent.add_child(tag)
	tag.position.y = height

func build_creature() -> void:
	add_child(creature)
	creature.position = field + side * 8
	creature.position.y = elevation(creature.position)
	creature.hide()
	var grey := Color("788780")
	var torso := CapsuleMesh.new()
	torso.radius = 0.23
	torso.height = 0.9
	var chest := mesh(creature,torso,Vector3(0,1.43,0),grey)
	chest.scale = Vector3(0.96,1.13,0.77)
	chest.rotation.x = -0.29
	surface(chest,grey,Vector3(11,6,11),0.56)
	var ridge := SphereMesh.new()
	ridge.radius = 0.11
	ridge.height = 0.22
	for i in range(4):
		for direction in [-1.0,1.0]:
			var rib := mesh(chest,ridge,Vector3(direction*(0.093-i*0.01),0.07-i*0.079,-0.12),grey.lightened(0.11))
			rib.scale = Vector3(0.87-i*0.10,0.16,0.34)
			rib.rotation.z = direction*0.38
	var pelvis := SphereMesh.new()
	pelvis.radius = 0.19
	pelvis.height = 0.28
	var hip := mesh(creature,pelvis,Vector3(0,1.01,0.037),grey.darkened(0.17))
	hip.scale.z = 0.66
	var neck := CapsuleMesh.new()
	neck.radius = 0.09
	neck.height = 0.34
	var throat := mesh(creature,neck,Vector3(0,1.81,-0.08),grey)
	throat.rotation.x = -0.44
	var head := SphereMesh.new()
	head.radius = 0.17
	head.height = 0.39
	creature_head = mesh(creature,head,Vector3(0,1.99,-0.11),grey.lightened(0.17))
	creature_head.scale = Vector3(0.86,1.18,0.89)
	surface(creature_head,grey.lightened(0.19),Vector3(9,4,10),0.44)
	var eye := SphereMesh.new()
	eye.radius = 0.033
	eye.height = 0.058
	for x in [-0.05,0.05]:
		var socket := mesh(creature_head,eye,Vector3(x,0.026,-0.155),Color("201b19"))
		socket.scale = Vector3(1.12,0.68,0.29)
	var mouth := mesh(creature_head,eye,Vector3(0,-0.076,-0.142),Color("2b2421"))
	mouth.scale = Vector3(0.98,1.33,0.51)
	var jaw := mesh(creature_head,ridge,Vector3(0,-0.121,-0.062),grey.darkened(0.08))
	jaw.scale = Vector3(0.63,0.45,0.88)
	for x in [-0.16,0.16]:
		var limb := CapsuleMesh.new()
		limb.radius = 0.082
		limb.height = 0.96
		var pivot := Node3D.new()
		creature.add_child(pivot)
		pivot.position = Vector3(x,0.98,0)
		mesh(pivot,limb,Vector3.DOWN*0.45,grey)
		legs.append(pivot)
		var shoulder := Node3D.new()
		creature.add_child(shoulder)
		shoulder.position = Vector3(x*1.28,1.64,-0.04)
		var arm := mesh(shoulder,limb,Vector3.DOWN*0.51,grey)
		arm.scale = Vector3(0.81,1.18,0.81)
		shoulder.rotation.z = signf(x)*0.21
		arms.append(shoulder)
		var hand := CapsuleMesh.new()
		hand.radius = 0.053
		hand.height = 0.17
		mesh(shoulder,hand,Vector3(0,-1.06,0),grey.darkened(0.16))
		for j in range(3):
			var finger := CapsuleMesh.new()
			finger.radius = 0.0125
			finger.height = 0.15 - absf(j-1.0)*0.035
			var digit := mesh(shoulder,finger,Vector3(-0.032+0.032*j,-1.17,-0.018),grey.darkened(0.24))
			digit.rotation.x = -0.29

func update_howl(delta: float) -> void:
	howl_timer -= delta
	if howl_timer <= 0.0:
		howl_timer = rng.randf_range(18.0,31.0)
		var direction := Vector3.FORWARD.rotated(Vector3.UP,rng.randf_range(0,TAU))
		howl.position = player.position + direction*rng.randf_range(26.0,49.0)
		howl.pitch_scale = rng.randf_range(0.82,1.05)
		howl.play()

func setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	for label in [hud,prompt,notice]:
		layer.add_child(label)
		label.add_theme_color_override("font_outline_color",Color("192021"))
		label.add_theme_constant_override("outline_size", 8)
		label.add_theme_font_size_override("font_size", 20)
	hud.position = Vector2(24,18)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	prompt.offset_left = -310
	prompt.offset_right = 310
	prompt.offset_top = 24
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	notice.offset_left = -360
	notice.offset_right = 360
	notice.offset_top = -96
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_theme_font_size_override("font_size", 28)
	var controls := Label.new()
	layer.add_child(controls)
	controls.position = Vector2(24,650)
	controls.add_theme_constant_override("outline_size", 6)
	controls.text = "WASD  Move     Shift  Sprint     Space  Jump     C  Crouch     F  Flashlight     G  Decoy     E  Use\nQ  Climb higher     V  Platform     B  Screen     T  Rotate     Esc  Pause     F11  Full screen"

func show_message(message: String, seconds := 3.0) -> void:
	notice.text = message
	display_time = seconds

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not ended:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if not started:
			started = true
			show_message("Stay low until first light. C to crouch.", 4.0)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.rotate_y(-event.relative.x * 0.0023)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * 0.0023,-1.45,1.45)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			var mode := DisplayServer.window_get_mode()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
			return
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if event.keycode == KEY_R and ended:
			get_tree().reload_current_scene()
		if not started or ended or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		match event.keycode:
			KEY_F: light.visible = not light.visible
			KEY_C: crouched = not crouched
			KEY_E: interact()
			KEY_SPACE: jump_requested = true
			KEY_Q: climb_higher()
			KEY_G: throw_decoy()
			KEY_V: build_branch_platform()
			KEY_B:
				placing_screen = not placing_screen and wood > 0 and not carrying and climb_path.is_empty()
				screen_angle = player.rotation.y
			KEY_T: screen_angle += PI/12.0

func throw_decoy() -> void:
	if decoys == 0 or not creature.visible:
		return
	decoys -= 1
	var direction := -player.transform.basis.z
	if not chase:
		target = player.position + direction * 11.0
		target.y = 0
		investigate = 7.0
	show_message("Decoy thrown")

func action() -> String:
	if not climb_path.is_empty():
		return ""
	if placing_screen:
		return "place_screen"
	if perch != null:
		return "descend" if near_trunk() else ""
	if player.position.distance_to(dock) < 4 and powered and time >= NIGHT:
		return "escape"
	if player.position.distance_to(radio) < 3 and carrying:
		return "power"
	if battery.visible and player.position.distance_to(battery.position) < 2.5:
		return "pickup"
	if player.position.distance_to(door.position) < 3.1:
		if door_built and not door_broken:
			return "open_door" if door.visible else "close_door"
		if wood > 0:
			return "build_door"
	if nearby_wood() != null:
		return "wood"
	if not carrying and nearby_tree() != null:
		return "climb"
	return "drop" if carrying else ""

var supply_spot := Vector3.ZERO

func nearby_wood() -> Node3D:
	for cache in supply_caches:
		if cache.visible and player.position.distance_to(cache.position) < 2.7:
			return cache
	return null

func nearby_tree() -> TreePerch:
	var closest: TreePerch
	var best := 3.6
	for site in perches:
		var distance := minf(player.position.distance_to(site.base),player.position.distance_to(site.trunk))
		if distance < best:
			closest = site
			best = distance
	return closest

func set_door_closed(closed: bool) -> void:
	door.visible = closed
	door.collision_layer = 1 if closed else 0

func interact() -> void:
	match action():
		"wood":
			nearby_wood().hide()
			wood += 4
			show_message("Picked up four planks")
		"pickup":
			battery.hide()
			carrying = true
		"drop":
			battery.position = player.position
			battery.show()
			carrying = false
		"power":
			powered = true
			carrying = false
			show_message("Rescue confirmed. Board at the dock after dawn.",5.0)
		"climb":
			var site := nearby_tree()
			if blocked(player.position+Vector3.UP*0.48,site.base+Vector3.UP*0.48):
				show_message("Circle the trunk to the low branch or ladder.")
				return
			perch = site
			if chase and creature.position.distance_to(player.position) < 25.0 and not blocked(creature.position+Vector3.UP*1.91,camera.global_position,5):
				pursue_tree(perch)
			climb_path = PackedVector3Array([perch.base])
			if perch != landmark_perch:
				climb_path.append_array(trunk_line(perch,perch.base.y+0.3,perch.climb_anchor.y,perch.approach))
			climb_path.append(climb_top(perch))
			if perch != landmark_perch:
				climb_path.append_array(trunk_arc(perch,perch.climb_anchor.y,perch.approach,perch.heading))
			climb_path.append(perch.seat)
		"descend":
			var landing := deck_center + side*2.65 + axis*1.45 + Vector3.UP*0.05
			if perch == landmark_perch and player.position.distance_to(landing+Vector3.UP*4.15) < 2.3:
				climb_path = PackedVector3Array([landing+Vector3.UP*4.15,landing])
			elif perch != landmark_perch and perch != landmark_perch.higher:
				# Round the trunk at the current height to the climbing side, then down to the ground.
				var root := lower_of(perch)
				climb_path = trunk_arc(perch,player.position.y+0.05,away_from_trunk(),root.approach)
				climb_path.append_array(trunk_line(perch,player.position.y+0.05,root.base.y+0.3,root.approach))
				climb_path.append(root.base)
			else:
				climb_path = PackedVector3Array([climb_top(perch)])
				for lower in perches:
					if lower.higher == perch:
						climb_path.append(climb_top(lower))
						break
				climb_path.append(perch.base)
			perch = null
		"place_screen":
			place_screen()
		"build_door":
			wood -= 1
			door_built = true
			door_broken = false
			set_door_closed(false)
			show_message("Door built. Step inside, then close it with E.")
		"open_door": set_door_closed(false)
		"close_door":
			if absf(player.position.z - door.position.z) > 0.55:
				set_door_closed(true)
		"escape": finish(true,"You reached the rescue boat.")

func climb_top(site: TreePerch) -> Vector3:
	return site.climb_anchor

# Trees planted later can grow into an earlier tree's fork. Once the island is built, move any fork whose
# seat is inside foreign wood to another real branch on its own tree (nearest in height first).
func refit_blocked_forks() -> void:
	var space := get_world_3d().direct_space_state
	var body_shape := CapsuleShape3D.new()
	body_shape.radius = 0.36
	body_shape.height = 1.15
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body_shape
	query.collision_mask = 1
	var seat_free := func(site: TreePerch) -> bool:
		query.transform = Transform3D(Basis.IDENTITY,site.seat+Vector3.UP*0.6)
		query.exclude = site.wood
		return space.intersect_shape(query,1).is_empty()
	for root in perches:
		if root.higher == null:
			# Keep the crown landing usable when a neighbouring limb overlaps it.
			if not seat_free.call(root):
				var original:=root.seat
				for k in range(8):
					root.seat=original+root.heading.rotated(Vector3.UP,k*TAU/8.0)*.64
					if seat_free.call(root):
						root.pad.position=root.seat-Vector3.UP*.06
						break
					root.seat=original
			continue
		for site: TreePerch in [root,root.higher]:
			if site.limb_t < 0.0 or seat_free.call(site):
				continue
			var limbs: Array = skeletons[site.kind].branches.duplicate()
			var target := site.limb_t
			limbs.sort_custom(func(a,b): return absf(a.t-target) < absf(b.t-target))
			var low_limit: float = 0.0 if site == root else root.limb_t+0.1
			for limb in limbs:
				if limb.t == target or limb.t < low_limit or (site == root and root.higher.limb_t >= 0.0 and limb.t > root.higher.limb_t-0.1):
					continue
				branch_perch(site,limb,site.width)
				if seat_free.call(site):
					break
		root.higher.base = root.base

# The tree's lowest fork (forks only link upward, so RefCounted perches never form a cycle).
func lower_of(site: TreePerch) -> TreePerch:
	for root in perches:
		if root == site or root.higher == site:
			return root
	return site

func away_from_trunk() -> Vector3:
	var at: Vector3 = trunk_at(perch,player.position.y)[0]
	var out := Vector3(player.position.x-at.x,0,player.position.z-at.z)
	return out.normalized() if out.length() > 0.05 else perch.heading

# Climbing up or down happens at the trunk; out on a branch you walk back first (or drop).
func near_trunk() -> bool:
	if perch == landmark_perch:
		return true
	var at := trunk_at(perch,player.position.y)
	return Vector2(player.position.x-at[0].x,player.position.z-at[0].z).length() < at[1]+2.4

# The tree (and fork, by height) the player is standing in, or null. Called while on climbable wood.
func tree_perch_at(pos: Vector3) -> TreePerch:
	var best: TreePerch
	var best_distance := INF
	# Interlocking crowns can put a second trunk closer than the branch underfoot.
	var support := RID()
	if player.is_on_floor() and player.position.is_equal_approx(pos):
		for i in range(player.get_slide_collision_count()):
			var hit:=player.get_slide_collision(i)
			if hit.get_normal().y>.55 and hit.get_collider() is StaticBody3D and hit.get_collider().has_meta("climbable"):
				support=hit.get_collider_rid()
				break
	for root in perches:
		if support.is_valid() and (support in root.wood or (root.higher!=null and support in root.higher.wood)):
			best=root
			break
		var d := Vector2(pos.x-root.trunk.x,pos.z-root.trunk.z).length()
		if d < root.reach and d < best_distance:
			best = root
			best_distance = d
	if best != null and best.higher != null and absf(pos.y-best.higher.seat.y) < absf(pos.y-best.seat.y):
		return best.higher
	return best

# Hidden up a tree only where the crown's own leaves are thick around your head.
func leaf_cover(site: TreePerch, at: Vector3) -> int:
	if not leaf_grids.has(site.kind):
		var grid := {}
		var model: Mesh = flora[site.kind]
		for i in range(model.get_surface_count()):
			var mat := model.surface_get_material(i)
			if mat == null or mat.resource_name != "Foliage":
				continue
			for v in model.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
				var cell := Vector3i((v/LEAF_CELL).floor())
				grid[cell] = grid.get(cell,0)+1
		leaf_grids[site.kind] = grid
	var counts: Dictionary = leaf_grids[site.kind]
	var centre := Vector3i((site.pose.affine_inverse()*at/LEAF_CELL).floor())
	var total := 0
	for dx in range(-1,2):
		for dy in range(-1,2):
			for dz in range(-1,2):
				total += counts.get(centre+Vector3i(dx,dy,dz),0)
	return total

func perch_leafy() -> bool:
	if perch == null or perch == landmark_perch:
		return false
	return leaf_cover(perch,camera.global_position) >= LEAFY_COVER

func climb_higher() -> void:
	if perch == null or perch.higher == null or not climb_path.is_empty() or placing_screen:
		return
	if not near_trunk():
		show_message("Walk back to the trunk to climb higher.")
		return
	if perch == landmark_perch:
		climb_path = PackedVector3Array([climb_top(perch),climb_top(perch.higher),perch.higher.seat])
	else:
		var up := perch.higher
		var from := away_from_trunk()
		climb_path = PackedVector3Array([trunk_point(perch,player.position.y+0.05,from)])
		climb_path.append_array(trunk_arc(perch,up.climb_anchor.y,from,up.approach))
		climb_path.append(up.step_off)
		climb_path.append(up.seat)
	if pursuing_perch == perch:
		pursue_tree(perch.higher)
	perch = perch.higher

# Where a platform would go if built from the player's current spot, or null if it can't go here.
func platform_spot() -> Variant:
	if perch == null or not climb_path.is_empty():
		return null
	var out := perch.heading
	var clear := INF
	if perch != landmark_perch:
		var at := trunk_at(perch,player.position.y)
		var offset := Vector3(player.position.x-at[0].x,0,player.position.z-at[0].z)
		clear = offset.length()-at[1]
		if offset.length() > 0.05:
			out = offset.normalized()
	elif perch.platform != null:
		return null  # the treehouse deck is already a floor
	if clear < 0.6:
		return null
	var center := player.position+out*0.6-Vector3.UP*0.14
	for other in branch_platforms:
		if is_instance_valid(other) and other.position.distance_to(center) < 1.8:
			return null
	return Transform3D(Basis(Vector3.UP,atan2(out.x,out.z)),center)

# V: a small plank platform wherever you stand on a thick branch (two planks).
func build_branch_platform() -> void:
	var spot: Variant = platform_spot()
	if spot == null:
		if perch != null and climb_path.is_empty():
			show_message("No room for a platform here. Step further out along the branch.")
		return
	if wood < 2:
		show_message("A platform needs two planks.")
		return
	wood -= 2
	var floor_pos: Vector3 = spot.origin
	var platform := box(floor_pos,Vector3(2.56,0.22,2.3),Color("6c5032"))
	platform.set_meta("climbable",true)
	platform.basis = spot.basis
	branch_platforms.append(platform)
	platform.get_child(0).hide()
	for i in range(7):
		timber(platform,Vector3(-1.09+i*0.364,0,0),Vector3(0.358,0.22,2.3),Color("735639").lightened((i%3)*0.035))
	for x in [-0.87,0.87]:
		var support := timber(platform,Vector3(x,-0.53,-0.42),Vector3(0.11,1.3,0.11),Color("64472e"))
		support.rotation.x = -0.72
	perch.platform = platform
	show_message("Platform built. Aim at the edge and press B to add a screen.")

func setup_build_preview() -> void:
	var panel := BoxMesh.new()
	panel.size = Vector3(1.46,1.13,0.14)
	preview = mesh(self,panel,Vector3.ZERO,Color.WHITE)
	preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview.material_override = preview_material
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview.hide()

func update_screen_preview() -> bool:
	var direction := -camera.global_basis.z
	var eye := camera.global_position
	if direction.y > -0.02:
		preview.hide()
		return false
	var base: Vector3
	if perch != null:
		var distance := (player.position.y-eye.y)/direction.y
		if distance < 0.25 or distance > 6.0:
			preview.hide()
			return false
		base = eye+direction*distance
	else:
		var ray := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye,eye+direction*6.0,1))
		if ray.is_empty() or ray.collider != terrain_body or ray.normal.y < 0.91:
			preview.hide()
			return false
		base = ray.position
	var across := Vector3.RIGHT.rotated(Vector3.UP,screen_angle)*0.73
	var valid := base.distance_to(player.position) > 0.85 and wood > 0
	if perch != null:
		# Up a tree a screen needs a floor: any built platform (or the treehouse deck) under both feet.
		var floor_found := false
		var floors: Array = branch_platforms.duplicate()
		floors.append(landmark_perch.platform)
		for candidate in floors:
			if not is_instance_valid(candidate):
				continue
			var bounds := (candidate.get_child(1) as CollisionShape3D).shape as BoxShape3D
			var inside := true
			for foot in [base-across,base+across]:
				var local: Vector3 = candidate.to_local(foot)
				inside = inside and absf(local.x) <= bounds.size.x*0.5 and absf(local.z) <= bounds.size.z*0.5 and absf(local.y) < 0.45
			if inside:
				floor_found = true
				break
		valid = valid and floor_found
		if perch != landmark_perch:
			var at := trunk_at(perch,base.y)
			valid = valid and Vector2(base.x-at[0].x,base.z-at[0].z).length() > at[1]+0.3
	else:
		for foot in [base-across,base+across]:
			valid = valid and Vector2(foot.x,foot.z).length() < SHORE_RADIUS-1.0 and swamp_weight(foot) < 0.46
			valid = valid and absf(elevation(foot)-base.y) < 0.16
	preview.position = base+Vector3.UP*0.57
	preview.rotation.y = screen_angle
	var query := PhysicsShapeQueryParameters3D.new()
	var bounds := BoxShape3D.new()
	bounds.size = Vector3(1.45,0.98,0.13)
	query.shape = bounds
	query.transform = preview.transform
	query.collision_mask = 7
	if perch != null:
		query.exclude = perch.wood
	valid = valid and get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
	preview_material.albedo_color = Color(0.49,0.86,0.64,0.42) if valid else Color(0.93,0.32,0.23,0.42)
	preview.show()
	return valid

func place_screen() -> void:
	if not update_screen_preview():
		return
	wood -= 1
	var panel := box(preview.position,Vector3(1.46,1.13,0.14),Color("77573b"))
	panel.rotation.y = screen_angle
	panel.collision_layer = 4
	panel.get_child(0).hide()
	for i in range(5):
		timber(panel,Vector3(0,-0.45+i*0.225,0),Vector3(1.46,0.225,0.14),Color("705234").lightened((i%3)*0.04))
	placing_screen = false
	preview.hide()
	show_message("Screen placed. Crouch behind it to break sight.")

func _process(delta: float) -> void:
	var clock := time
	if started and not ended and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		clock += Engine.get_physics_interpolation_fraction()/Engine.physics_ticks_per_second
	# Ease into and out of the shade over about a second, like eyes adjusting.
	var shade := move_toward(canopy_shade,canopy_cover(player.position),delta*0.9)
	if shade != canopy_shade:
		canopy_shade = shade
		last_light_time = -1.0
	if clock != last_light_time:
		update_light(clock)

func _physics_process(delta: float) -> void:
	if not started or ended:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		show_message("Paused\nClick to resume")
		return
	step_world(delta)

# One unpaused game step (split from _physics_process so headless tests can drive the real movement).
func step_world(delta: float) -> void:
	time += delta
	display_time -= delta
	if display_time <= 0:
		notice.text = ""
	if time >= DEADLINE:
		finish(false,"The pickup window closed.")
		return
	var move := Vector3.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		move.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		move.z = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	var sprinting := not carrying and not crouched and move.length() > 0 and stamina > 4 and Input.is_physical_key_pressed(KEY_SHIFT)
	stamina = clampf(stamina + (-29.0 if sprinting else 17.0)*delta,0,100)
	var waterline := -.23
	if fall_height>0 and (Vector2(player.position.x-swamps[1].x,player.position.z-swamps[1].z)/basin_sizes[1]).length()<1:
		waterline += fall_height
	var wading := player.position.y < waterline and swamp_weight(player.position) > 0.44
	var speed := 6.9 if sprinting else (2.25 if crouched else (3.05 if carrying else WALK))
	if not climb_path.is_empty():
		player.velocity = Vector3.ZERO
		jump_requested = false  # no stored jump firing the moment a climb ends
		advance_climb(delta)
	else:
		var horizontal := player.transform.basis * move.normalized() * speed * (0.58 if wading else 1.0)
		player.velocity.x = horizontal.x
		player.velocity.z = horizontal.z
		player.velocity.y -= 18.0 * delta
		if jump_requested and player.is_on_floor() and not placing_screen:
			player.velocity.y = JUMP_CARRYING if carrying else JUMP
		jump_requested = false
		player.move_and_slide()
		if perch != null:
			step_over_twig(horizontal*delta)
		# Free walking: whichever tree's wood you stand on is the one you are in. Mid-air keeps it.
		if player.is_on_floor():
			var on_wood := false
			for i in range(player.get_slide_collision_count()):
				var hit := player.get_slide_collision(i).get_collider()
				if hit is Node and (hit as Node).has_meta("climbable"):
					on_wood = true
			var now: TreePerch = tree_perch_at(player.position) if on_wood else null
			if now == null and perch != null:
				placing_screen = false
			perch = now
	if player.position.y < -1.35:
		player.position.y = 0.0
		player.position = player.position.normalized() * (SHORE_RADIUS-2.0)
		player.position.y = elevation(player.position)+0.15
	if placing_screen:
		update_screen_preview()
	else:
		preview.hide()
	camera.position.y = move_toward(camera.position.y,0.82 if crouched else 1.65,delta*5)
	if time < FIRST_DAWN or (time >= DAY and time < NIGHT):
		creature.show()
		update_creature(delta,sprinting or (wading and move.length_squared() > 0.0))
		update_howl(delta)
	elif creature.visible:
		creature.hide()
		creature.position = field + side*8.0
		creature.position.y = elevation(creature.position)
		chase = false
		detection = 0.0
		investigate = 0.0
		door_pressure = 0.0
		creature_up = false
		warned_climb = false
		pursuing_perch = null
		howl.stop()
	update_hud()

# Up a tree, side twigs crossing a branch would stop the capsule dead. Lift over anything up to 0.32 m
# when the space above is clear; walking *along* thin wood (no footing) stays awkward.
func step_over_twig(motion: Vector3) -> void:
	if not player.is_on_wall() or motion.length_squared() < 0.000001:
		return
	var lifted := player.global_transform.translated(Vector3.UP*0.32)
	if player.test_move(player.global_transform,Vector3.UP*0.32) or player.test_move(lifted,motion*1.5):
		return
	player.global_position += Vector3.UP*0.32+motion

func advance_climb(delta: float) -> void:
	player.position = player.position.move_toward(climb_path[0],delta*3.8)
	if player.position.is_equal_approx(climb_path[0]):
		climb_path.remove_at(0)

func update_light(clock := -1.0) -> void:
	if clock < 0.0:
		clock = time
	last_light_time = clock
	var first_day := clampf((clock-FIRST_DAWN)/(DAY-FIRST_DAWN),-0.26,1.06)
	var next_day := clampf((clock-NIGHT+2.0)/(DAY+12.0),-0.07,0.76)
	var solar_phase := first_day if clock < (DAY+NIGHT)*0.5 else next_day
	var solar_height := sin(solar_phase*PI)
	var sunlight := smoothstep(-0.03,0.25,solar_height)
	var darkness := 1.0-smoothstep(-0.14,0.15,solar_height)
	var warm := (1.0-smoothstep(0.08,0.56,absf(solar_height)))*(1.0-darkness*0.78)
	var glow := 1.0-smoothstep(FIRST_DAWN-12.0,FIRST_DAWN,clock) if clock < FIRST_DAWN else smoothstep(DAY,DAY+18.0,clock)*(1.0-smoothstep(NIGHT-14.0,NIGHT,clock))
	motes.visible = glow > 0.0
	mote_material.set_shader_parameter("intensity",glow)
	var lunar_phase := clampf((clock-DAY)/(NIGHT-DAY),-0.04,1.04)
	if clock < FIRST_DAWN + 5.0:
		lunar_phase = minf(1.04,0.61 + clock/FIRST_DAWN*0.39)
	var sun_dir := orbital_direction(solar_phase,1.14,0.0)
	var moon_dir := orbital_direction(lunar_phase,0.73,0.58)
	var horizon := Color("c4dcec").lerp(Color("e8b488"),warm).lerp(Color("1c2a42"),darkness)
	var upper := Color("3d7cc0").lerp(Color("5b6aa0"),warm).lerp(Color("070e1e"),darkness)
	sky_material.set_shader_parameter("upper", upper)
	sky_material.set_shader_parameter("horizon", horizon)
	sky_material.set_shader_parameter("cloud_color",Color("fbfcff").lerp(Color("f4c49c"),warm).lerp(Color("1e2a3e"),darkness))
	sky_material.set_shader_parameter("night",darkness)
	sky_material.set_shader_parameter("twilight",warm)
	sky_material.set_shader_parameter("sun_direction",sun_dir)
	sky_material.set_shader_parameter("moon_direction",moon_dir)
	# Under the jungle roof: dimmer, greener ambient, filtered sun and a thicker green-grey haze.
	var shade := canopy_shade
	atmosphere.ambient_light_color = Color("cfdde6").lerp(Color("7f9bcc"),darkness).lerp(Color("9fbfa4"),shade*0.5)
	atmosphere.ambient_light_energy = lerpf(0.68-0.12*warm,0.14,darkness)*(1.0-0.47*shade)
	atmosphere.fog_light_color = horizon.lerp(Color("3d5a48").lerp(Color("0f1a1c"),darkness),shade*0.6)
	var marsh := swamp_weight(player.position)
	atmosphere.fog_density = lerpf(0.0028,0.019,darkness)+marsh*lerpf(0.011,0.019,darkness)+shade*lerpf(0.012,0.016,darkness)
	atmosphere.fog_height_density = darkness*0.25 + marsh*lerpf(0.28,0.58,darkness)
	for water in waters:
		water.set_shader_parameter("sky_tint",horizon)
		water.set_shader_parameter("zenith",upper)
		water.set_shader_parameter("sun_direction",sun_dir)
		water.set_shader_parameter("moon_direction",moon_dir)
		water.set_shader_parameter("night",darkness)
	sun.look_at(-sun_dir)
	sun.light_color = Color("fff3de").lerp(Color("f4a468"),warm)
	sun.light_energy = sunlight*(1.16-warm*0.27)*(1.0-0.50*shade)
	sun.visible = sunlight > 0.012
	moon.look_at(-moon_dir)
	moon.light_color = Color("9cbcf0")
	moon.light_energy = darkness*(0.20+0.52*maxf(moon_dir.y,0.0))*(1.0-0.68*shade)
	moon.visible = darkness > 0.02

func orbital_direction(progress: float, lift: float, alignment: float) -> Vector3:
	var heading := -2.28 + progress*2.62 + alignment
	var angle := sin(progress*PI)*lift
	return Vector3(cos(heading)*cos(angle),sin(angle),sin(heading)*cos(angle))

func blocked(from: Vector3, to: Vector3, mask := 1) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from,to,mask)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func pursue_tree(site: TreePerch) -> void:
	if site == pursuing_perch:
		return
	# Free climbing: moving between forks of the same tree keeps the creature's progress.
	if pursuing_perch != null and site.trunk == pursuing_perch.trunk and lower_of(site) != landmark_perch:
		pursuing_perch = site
		return
	if pursuing_perch != null and site.trunk != pursuing_perch.trunk and creature.position.y > 0.5:
		return
	if pursuing_perch == null:
		warned_climb = false
	pursuing_perch = site
	creature_up = false

func update_creature(delta: float, sprinting: bool) -> void:
	var offset := player.position - creature.position
	var distance := offset.length()
	var inside_cave := player.position.distance_to(cave) < 2.3
	var hidden := door.visible and inside_cave
	if crouched and perch_leafy() and distance > 5.5 and climb_path.is_empty():
		hidden = true
	if crouched and perch == null and foliage_hidden():
		hidden = true
	var facing := -creature.basis.z.dot(offset.normalized()) > 0.25
	# Jungle shade hides you; a lit flashlight mostly gives that back.
	var under_canopy := canopy_cover(player.position)*(0.15 if light.visible else 0.42)
	var sight_range := (33.0 if light.visible else (10.5 if crouched else 20.0)) * (1.0-0.37*swamp_weight(player.position)) * (1.0-under_canopy)
	var seen := distance < sight_range and (facing or distance < 3.0) and (not hidden or light.visible) and not blocked(creature.position + Vector3.UP * 1.91, camera.global_position,5)
	if seen:
		detection = minf(detection + delta * (2.8 if light.visible else 1.7),1.0)
		if detection >= 1.0:
			if not chase:
				show_message("It saw you!")
			chase = true
			target = player.position
			investigate = 5.0
			if perch != null:
				pursue_tree(perch)
	else:
		detection = maxf(detection - delta * 0.9,0.0)
		investigate = maxf(investigate - delta,0.0)
		if investigate == 0.0 and pursuing_perch == null:
			chase = false
		if sprinting and distance < 14 and not chase and investigate < 1.0:
			target = player.position
			investigate = 3.0
	var goal := target
	if investigate <= 0.0 and pursuing_perch == null:
		patrol += delta * 0.15
		goal = field + (axis*cos(patrol) + side*sin(patrol))*8
	var climbing := false
	if pursuing_perch != null and lower_of(pursuing_perch) != landmark_perch:
		var branch_goal := creature_branch_goal()
		goal = branch_goal[0]
		climbing = branch_goal[1]
	elif pursuing_perch != null:
		var top := climb_top(pursuing_perch)
		var feet := pursuing_perch.base
		feet.y = elevation(Vector3(feet.x,0,feet.z))
		if not creature_up:
			goal = feet
			if Vector2(creature.position.x-feet.x,creature.position.z-feet.z).length() < 0.45 or creature.position.y > feet.y+0.30:
				goal = top
				climbing = true
				if not warned_climb:
					warned_climb = true
					show_message("It's climbing the tree!")
				if creature.position.distance_to(top) < 0.09:
					creature_up = true
		elif perch == pursuing_perch:
			goal = player.position if climb_path.is_empty() else pursuing_perch.seat
			climbing = true
		elif creature.position.y > feet.y+0.08:
			goal = top if Vector2(creature.position.x-top.x,creature.position.z-top.z).length() > 0.09 else feet
			climbing = true
		else:
			pursuing_perch = null
			creature_up = false
	if door.visible and inside_cave and chase and distance < 5.0:
		goal = door.position + Vector3.FORWARD * 0.85
		goal.y = 0.0
		door_pressure += delta
		if door_pressure >= 2.5:
			set_door_closed(false)
			door_broken = true
			door_pressure = 0.0
			show_message("The cave door broke!")
	var next := creature.position.move_toward(goal,delta*2.6) if climbing else creature_ground_step(goal, delta*(4.05 if chase else 2.25))
	var step := next - creature.position
	if Vector2(step.x,step.z).length() > 0.001:
		creature.look_at(Vector3(goal.x,creature.position.y,goal.z))
	var moving := step.length_squared() > 0.000001
	if moving:
		creature.position = next
		stride += delta * (12.5 if chase else 6.3)
	var swing := sin(stride)*0.58 if moving else 0.0
	for i in range(2):
		var sign := 1.0 if i == 0 else -1.0
		legs[i].rotation.x = lerpf(legs[i].rotation.x,swing*sign,minf(delta*12,1.0))
		var arm_pose := (-1.85 if climbing else -0.11) - swing*sign
		arms[i].rotation.x = lerpf(arms[i].rotation.x,arm_pose,minf(delta*10,1.0))
	var upward := clampf(atan2(offset.y,maxf(Vector2(offset.x,offset.z).length(),0.1)),-0.35,0.65)
	var head_pose := upward if chase or detection > 0.15 else -0.30+0.08*sin(stride*0.5)
	creature_head.rotation.x = lerpf(creature_head.rotation.x,head_pose,minf(delta*7,1.0))
	if chase and distance < 1.1 and not blocked(creature.position+Vector3.UP,camera.global_position,5):
		finish(false,"A creature caught you.")

# Free-climbing pursuit on an ordinary tree. Returns [goal, climbing].
# Up the trunk on the climbing side to the player's height, round the bark to the player's branch, then out
# along it. A player on another branch draws it back to the trunk first; a player who left the tree draws
# it back down to the ground, where the pursuit ends.
func creature_branch_goal() -> Array:
	var site := pursuing_perch
	var feet := site.base
	feet.y = elevation(Vector3(feet.x,0,feet.z))
	var player_here := perch != null and perch.trunk == site.trunk
	var target_y := player.position.y if player_here else site.seat.y
	if not climb_path.is_empty() and player_here:
		target_y = climb_path[climb_path.size()-1].y
	var c_trunk := trunk_at(site,creature.position.y)
	var c_out := Vector3(creature.position.x-c_trunk[0].x,0,creature.position.z-c_trunk[0].z)
	var on_trunk: bool = c_out.length() < c_trunk[1]+0.9
	if not creature_up:
		# Walk to the foot, then climb.
		if Vector2(creature.position.x-feet.x,creature.position.z-feet.z).length() > 0.45 and creature.position.y < feet.y+0.3:
			return [feet,false]
		if not warned_climb:
			warned_climb = true
			show_message("It's climbing the tree!")
		var top := trunk_point(site,target_y,site.approach)
		if creature.position.distance_to(top) < 0.12:
			creature_up = true
		return [top,true]
	if not player_here:
		# Back to the trunk, then down the climbing side to the ground.
		if not on_trunk:
			return [trunk_point(site,creature.position.y,c_out.normalized()),true]
		if creature.position.y > feet.y+0.08:
			var down := trunk_point(site,creature.position.y,site.approach)
			if Vector2(creature.position.x-down.x,creature.position.z-down.z).length() > 0.12:
				return [down,true]
			return [feet,true]
		pursuing_perch = null
		creature_up = false
		return [creature.position,false]
	var p_trunk := trunk_at(site,player.position.y)
	var p_out := Vector3(player.position.x-p_trunk[0].x,0,player.position.z-p_trunk[0].z)
	var p_dir := p_out.normalized() if p_out.length() > 0.05 else site.heading
	if not on_trunk:
		var same_branch := c_out.normalized().dot(p_dir) > 0.82 and absf(creature.position.y-player.position.y) < 1.6
		if same_branch:
			return [player.position,true]
		return [trunk_point(site,creature.position.y,c_out.normalized()),true]
	# Lined up with the player's branch at their height: commit to walking out (no flip-flopping at the bark).
	var c_dir_now := c_out.normalized() if c_out.length() > 0.05 else site.approach
	if c_dir_now.dot(p_dir) > 0.9 and absf(creature.position.y-(target_y+0.05)) < 0.5:
		return [player.position,true]
	var beside := trunk_point(site,target_y+0.05,p_dir)
	if creature.position.distance_to(beside) > 0.15:
		# Round the bark in short steps so it never cuts through the trunk.
		var c_dir := c_out.normalized() if c_out.length() > 0.05 else site.approach
		var turn := Vector2(c_dir.x,c_dir.z).angle_to(Vector2(p_dir.x,p_dir.z))
		var next_dir := c_dir.rotated(Vector3.UP,-clampf(turn,-0.6,0.6))
		var y := move_toward(creature.position.y,target_y+0.05,1.0)
		return [trunk_point(site,y,next_dir),true]
	return [player.position,true]

func creature_ground_step(goal: Vector3, step_size: float) -> Vector3:
	var direction := Vector3(goal.x-creature.position.x,0,goal.z-creature.position.z)
	if direction.length_squared() < 0.0025:
		return creature.position
	var direction_unit := direction.normalized()
	var chest := creature.position+Vector3.UP*0.96
	for degrees in [0.0,32.0,-32.0,65.0,-65.0,100.0,-100.0]:
		var steer := direction_unit.rotated(Vector3.UP,deg_to_rad(degrees))
		if blocked(chest,chest + steer * minf(0.74,direction.length())):
			continue
		var next := creature.position + steer*minf(step_size,direction.length())
		if Vector2(next.x,next.z).length() >= ISLAND_RADIUS-1.0:
			continue
		next.y = elevation(Vector3(next.x,0,next.z))
		if absf(next.y-creature.position.y) > step_size*1.35:
			continue
		return next
	return creature.position

func update_hud() -> void:
	var objective := "Find the battery in the clearing"
	if carrying:
		objective = "Carry the battery to the radio mast"
	if powered:
		objective = "Reach the dock. Board after the second dawn." if time < NIGHT else "Board the rescue boat at the dock."
	var phase := ("DAY" if time < DAY-28.0 else "DUSK") if time < DAY else ("NIGHT" if time < NIGHT else "DAWN")
	var limit := DAY if time < DAY else (NIGHT if time < NIGHT else DEADLINE)
	if time < FIRST_DAWN:
		phase = "NIGHT"
		limit = FIRST_DAWN
		if not carrying and not powered:
			objective = "Stay low. Find the battery in the clearing."
	hud.text = "%s  %ds     WOOD %d     DECOYS %d     STAMINA %d\n%s" % [phase,ceili(limit-time),wood,decoys,roundi(stamina),objective]
	if detection > 0.03 and not chase:
		hud.text += "\nCreature awareness %d%%" % roundi(detection*100)
	if crouched and perch == null and foliage_hidden() and not light.visible:
		hud.text += "\nConcealed in foliage"
	if crouched and perch_leafy() and not light.visible and climb_path.is_empty():
		hud.text += "\nHidden in the leaves"
	var actions := {"wood":"Collect wood","pickup":"Pick up battery","power":"Power radio and call rescue","drop":"Set down battery","climb":"Climb tree","descend":"Climb down","place_screen":"Place screen   •   T Rotate   •   B Cancel","build_door":"Build cave door","open_door":"Open cave door","close_door":"Close cave door","escape":"Board rescue boat"}
	var key := action()
	prompt.text = "+" if key.is_empty() else "+\nE  " + str(actions[key])
	if platform_spot() != null:
		prompt.text += "\nV  Build platform (2 planks)"
	if perch != null and perch.higher != null and climb_path.is_empty() and not placing_screen and near_trunk():
		prompt.text += "\nQ  Climb higher"
	if perch != null and climb_path.is_empty() and not near_trunk():
		prompt.text += "\nWalk back to the trunk to climb"

func foliage_hidden() -> bool:
	for bush in bushes:
		if player.position.distance_squared_to(bush) < 1.05*1.05:
			return true
	for grass in cover:
		if player.position.distance_squared_to(grass) < 1.9*1.9:
			return true
	return false

func finish(won: bool, reason: String) -> void:
	ended = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	prompt.text = ""
	show_message(("ESCAPED" if won else "RUN ENDED") + "\n" + reason + "\nPress R for a new island",0.0)
