extends Node3D
## A generated island turned into a playable 3D world (milestone 3).
## Same interface as test_clearing.gd so the match, creatures and HUD work on either.
## Everything is rebuilt deterministically from (seed, attempt) on every peer.

const D = preload("res://src/core/defs.gd")
const Geo = preload("res://src/world/geo.gd")
const WalkGrid = preload("res://src/world/walk_grid.gd")
const CaveBuilder = preload("res://src/world/cave_builder.gd")
const IslandGen = preload("res://src/worldgen/island_gen.gd")
const Props = preload("res://src/world/props.gd")

const WATER_LEVEL := 0.3
const CHUNK := 30                    # quads per terrain chunk side
const BIOME_ALBEDO := [
	Color(0.42, 0.38, 0.28, 1.0),    # sea floor
	Color(0.56, 0.49, 0.34, 0.0),    # coast sand
	Color(0.30, 0.36, 0.19, 0.0),    # grassland
	Color(0.17, 0.19, 0.11, 0.1),    # forest floor
	Color(0.35, 0.34, 0.30, 0.0),    # mountains
	Color(0.21, 0.21, 0.13, 0.8),    # swamp mud
]
# Climbable tree types (LOWLIGHT_ISLAND.md §7) mapped to the v2 Canopy Realism models.
# Anchors come from each model's recorded branch skeleton, scaled with the tree.
const TREE_MODELS := {
	"low": {"mesh": "Umbrella Fig", "scale": 0.4},        # low branches: quick perch, canopy above
	"rough": {"mesh": "Tiered Copperwood", "scale": 0.42}, # rough trunk: hand-climb to the canopy
	"bare": {"mesh": "Crest Palm", "scale": 0.95},        # tall bare trunk: partway by hand
}

var gen: IslandGen
var grid: WalkGrid
var trees: Array[Dictionary] = []
var grass: Array[Dictionary] = []
var bushes: Array[Dictionary] = []
var hide_spots: Array[Vector3] = []
var patrol_points: Array[Vector3] = []
var spawn_points: Array[Vector3] = []
var interactables: Array[Dictionary] = []
var caves: Array[Dictionary] = []
var cave := {}
var burrows: Array[Vector3] = []
var burrow_pos := Vector3.ZERO
var landmarks := {}
# Objective anchors (used by objectives.gd)
var battery_spot := Vector3.ZERO
var battery_kind := ""
var radio_bench := Vector3.ZERO
var radio_mast_top := Vector3.ZERO
var dock_board := Vector3.ZERO
var boat_pos := Vector3.ZERO
var wood_piles: Array[Dictionary] = []
var lurk_points: Array[Vector3] = []     # shaded stretches of the radio->dock route (dawn ambush)
var water_materials: Array[ShaderMaterial] = []
var checksum := 0
var _headless := false
var _meshes := {}
var _cave_frames: Array[Dictionary] = []   # cave transforms, known before the scenes are built
var _skeletons := {}


## Build from a known-good (seed, attempt). Returns false if the attempt does not validate.
func build(seed_value: int, attempt: int = -1) -> bool:
	_headless = DisplayServer.get_name() == "headless"
	var cached: RefCounted = Net.take_cached_island(seed_value, attempt)
	gen = cached if cached else IslandGen.new()
	var ok := true if cached else (gen.generate_attempt(seed_value, attempt) if attempt >= 0 else gen.generate(seed_value))
	if not ok:
		push_error("island seed %d attempt %d failed: %s" % [seed_value, attempt, gen.reject_reason])
		return false
	checksum = compute_checksum(gen)
	_build_grid()
	_cave_xforms()
	_build_terrain()
	_build_water()
	_build_caves()
	_build_trees()
	_build_cover()
	_build_landmarks()
	for p in gen.patrol_points:
		patrol_points.append(p)
	for b in gen.burrows:
		burrows.append(b)
		Props.burrow(self, b)
	burrow_pos = burrows[0]
	return true


static func compute_checksum(g: RefCounted) -> int:
	var h := 0
	for k in range(0, g.height.size(), 7):
		h = (h * 31 + int(g.height[k] * 100.0)) & 0x7fffffff
	return (h * 31 + g.trees.size() * 7 + g.caves.size()) & 0x7fffffff


# ------------------------------------------------------------------ queries (world interface)

func ground_y(p: Vector3) -> float:
	for c in _cave_frames:
		if CaveBuilder.covers(c, p):
			return (c["xform"] as Transform3D).origin.y
	return gen.height_at(p.x, p.z)


func in_water(p: Vector3) -> bool:
	return ground_y(p) < WATER_LEVEL - 0.05 and p.y < WATER_LEVEL + 0.2


## Movement multiplier for wading (applied identically on host and predicting client).
func move_mult(p: Vector3) -> float:
	return 0.62 if in_water(p) else 1.0


func cover_at(p: Vector3) -> String:
	var above := p.y - ground_y(p)
	if above > 2.5:
		if deck_tree_at(p) >= 0:
			return ""   # a platform is exposed from some angles until screened
		for t in trees:
			var h := Vector2(p.x - t["pos"].x, p.z - t["pos"].z).length()
			if h < 3.0 and p.y - t["pos"].y > t["canopy_h"] - 1.2:
				return "canopy"
		return ""
	for g in grass:
		if Vector2(p.x - g["center"].x, p.z - g["center"].z).length() < g["radius"]:
			return "grass"
	for b in bushes:
		if Vector2(p.x - b["center"].x, p.z - b["center"].z).length() < b["radius"]:
			return "bush"
	return ""


func cave_at(p: Vector3) -> int:
	for c in caves:
		if CaveBuilder.contains(c, p):
			return c["id"]
	return -1


func in_cave(p: Vector3) -> bool:
	return cave_at(p) >= 0


func deck_tree_at(p: Vector3) -> int:
	for t in trees:
		if not t["deck"]:
			continue
		var d := Vector2(p.x - t["pos"].x, p.z - t["pos"].z)
		if absf(d.x) <= t["deck_half"] + 0.3 and absf(d.y) <= t["deck_half"] + 0.3 and p.y - t["pos"].y > t["deck_h"] - 0.4:
			return t["id"]
	return -1


func tree_by_id(id: int) -> Dictionary:
	if id >= 0 and id < trees.size():
		return trees[id]
	return {}


func set_door(open: bool, hp: float, id: int = 0) -> void:
	CaveBuilder.apply_door(caves[id], grid, open, hp)


func door_blocks(id: int = 0) -> bool:
	return id >= 0 and id < caves.size() and CaveBuilder.door_blocks(caves[id])


func door_body(id: int = 0) -> StaticBody3D:
	return caves[id]["door_body"]


# ------------------------------------------------------------------ builders

func _build_grid() -> void:
	grid = WalkGrid.new()
	grid.setup(gen.origin(), Vector2i(gen.n, gen.n), gen.cell)
	for k in gen.n * gen.n:
		var c := Vector2i(k % gen.n, k / gen.n)
		if gen.walk[k] == 0 or gen.blocked[k] == 1:
			grid.set_solid(c)
		else:
			grid.astar.set_point_weight_scale(c, gen.cost_of(k))


func _build_terrain() -> void:
	var n: int = gen.n
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/terrain.gdshader")
	mat.set_shader_parameter("water_level", WATER_LEVEL)
	var root := Node3D.new()
	root.name = "Terrain"
	add_child(root)
	# Per-vertex data once (vertices sit at cell centres and are shared by six triangles).
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	verts.resize(n * n)
	cols.resize(n * n)
	norms.resize(n * n)
	for j in n:
		for i in n:
			var c := Vector2i(i, j)
			verts[j * n + i] = _vtx(i, j)
			cols[j * n + i] = _vertex_color(c)
			norms[j * n + i] = _vertex_normal(c)
	var headless_build := _headless
	for cj in range(0, n - 1, CHUNK):
		for ci in range(0, n - 1, CHUNK):
			var idx := PackedInt32Array()
			var faces := PackedVector3Array()
			var i1 := mini(ci + CHUNK, n - 1)
			var j1 := mini(cj + CHUNK, n - 1)
			for j in range(cj, j1):
				for i in range(ci, i1):
					if _under_cave(i, j):
						continue
					var a := j * n + i
					var b := j * n + i + 1
					var c2 := (j + 1) * n + i + 1
					var d := (j + 1) * n + i
					# Same split as IslandGen.height_at: (i,j)-(i+1,j+1) diagonal, clockwise from above.
					idx.append_array([a, b, c2, a, c2, d])
					faces.append_array([verts[a], verts[b], verts[c2], verts[a], verts[c2], verts[d]])
			if faces.is_empty():
				continue
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			Geo.static_body(root, shape, Transform3D.IDENTITY, D.L_WORLD | D.L_SIGHT)
			if headless_build:
				continue
			# Compact the chunk's vertices so each mesh only carries what it uses.
			var remap := {}
			var cv := PackedVector3Array()
			var cc := PackedColorArray()
			var cn := PackedVector3Array()
			var ci_idx := PackedInt32Array()
			ci_idx.resize(idx.size())
			for q in idx.size():
				var g: int = idx[q]
				if not remap.has(g):
					remap[g] = cv.size()
					cv.append(verts[g])
					cc.append(cols[g])
					cn.append(norms[g])
				ci_idx[q] = remap[g]
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = cv
			arrays[Mesh.ARRAY_NORMAL] = cn
			arrays[Mesh.ARRAY_COLOR] = cc
			arrays[Mesh.ARRAY_INDEX] = ci_idx
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.mesh = am
			mi.material_override = mat
			root.add_child(mi)
	# Sea floor beyond the generated square so the horizon is not an edge.
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(1400, 1400)
	Geo.mesh(root, floor_mesh, Transform3D(Basis.IDENTITY, Vector3(0, -7.5, 0)), Geo.mat(Color(0.3, 0.28, 0.22)), false)


func _cave_xforms() -> void:
	for cv in gen.caves:
		var o: Vector3 = cv["origin"]
		_cave_frames.append({"xform": Transform3D(Basis(Vector3.UP, int(cv["facing"]) * PI * 0.5), o)})


func _under_cave(i: int, j: int) -> bool:
	var a := _vtx(i, j)
	var b := _vtx(i + 1, j + 1)
	var mid := Vector3((a.x + b.x) * 0.5, 0, (a.z + b.z) * 0.5)
	for c in _cave_frames:
		if CaveBuilder.covers(c, mid):
			return true
	return false


func _vtx(i: int, j: int) -> Vector3:
	return gen.cell_center(Vector2i(i, j))


func _vertex_color(c: Vector2i) -> Color:
	# Average a 3x3 neighbourhood so biome edges blend instead of stair-stepping.
	var acc := Color(0, 0, 0, 0)
	var w := 0.0
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var nc := c + Vector2i(di, dj)
			if gen.inside(nc):
				var b: int = gen.biome[gen.idx(nc)]
				acc += BIOME_ALBEDO[b]
				w += 1.0
	return acc / w


func _vertex_normal(c: Vector2i) -> Vector3:
	var n: int = gen.n
	var hl: float = gen.height[c.y * n + maxi(c.x - 1, 0)]
	var hr: float = gen.height[c.y * n + mini(c.x + 1, n - 1)]
	var hd: float = gen.height[maxi(c.y - 1, 0) * n + c.x]
	var hu: float = gen.height[mini(c.y + 1, n - 1) * n + c.x]
	return Vector3(-(hr - hl), 2.0 * gen.cell, -(hu - hd)).normalized()


func _build_water() -> void:
	if _headless:
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, 1400)
	plane.subdivide_width = 0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/water.gdshader")
	mat.set_shader_parameter("marsh", false)
	mat.set_shader_parameter("basin_radius", Vector2(700, 700))
	mat.set_shader_parameter("ripple_map", load("res://assets/textures/weather_noise.res"))
	var mi := Geo.mesh(self, plane, Transform3D(Basis.IDENTITY, Vector3(0, WATER_LEVEL, 0)), mat, false)
	mi.name = "Water"
	water_materials.append(mat)


func _build_caves() -> void:
	for i in gen.caves.size():
		var cv: Dictionary = gen.caves[i]
		var c := CaveBuilder.build(self, grid, i, cv["origin"], cv["facing"], false)
		CaveBuilder.open_interior(c, grid)
		caves.append(c)
		_dress_cave(c)
		set_door(false, Tuning.door_hp, i)
		interactables.append({"id": interactables.size(), "kind": "door", "pos": c["door_center"], "cave": i, "label": "door"})
		hide_spots.append(c["door_point"])
	cave = caves[0] if not caves.is_empty() else {}


## Break the cave scene's silhouette with rock models so it reads as a hollow in the cliff.
## Visual only: the cave walls and terrain already carry the collision and sight blocking.
func _dress_cave(c: Dictionary) -> void:
	if _headless:
		return
	var xf: Transform3D = c["xform"]
	var pieces := [
		["Shale Overhang", Vector3(0.0, 3.3, -0.6), Vector3(4.6, 2.2, 3.4), 0.0],
		["Bedded Cliff Face", Vector3(-3.6, 3.0, -2.5), Vector3(3.2, 2.8, 3.6), 0.4],
		["Bedded Cliff Face", Vector3(3.8, 2.9, -3.0), Vector3(3.4, 3.0, 3.8), -0.3],
		["Moss Table Ledge", Vector3(0.5, 3.6, -5.5), Vector3(4.2, 2.4, 4.0), 1.2],
		["Mossback Boulder", Vector3(5.8, 0.2, 0.4), Vector3(2.6, 2.4, 2.4), 0.7],
		["Bedded Cliff Face", Vector3(5.6, 1.0, -2.0), Vector3(2.4, 2.6, 2.6), 1.9],
		["Mossback Boulder", Vector3(-9.6, 0.1, 0.8), Vector3(2.2, 1.8, 2.0), 2.4],
		["Broken Talus", Vector3(2.8, 0.0, 1.8), Vector3(1.6, 1.2, 1.6), 0.0],
	]
	for pc in pieces:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh(pc[0])
		var local := Transform3D(Basis(Vector3.UP, pc[3]).scaled(pc[2]), pc[1])
		mi.transform = xf * local
		add_child(mi)


func _mesh(name: String) -> Mesh:
	if not _meshes.has(name):
		_meshes[name] = load("res://assets/flora/%s.res" % name)
	return _meshes[name]


func _skeleton(name: String) -> Dictionary:
	if not _skeletons.has(name):
		var txt := FileAccess.get_file_as_string("res://assets/flora/%s.skeleton.json" % name)
		_skeletons[name] = JSON.parse_string(txt) if txt != "" else {}
	return _skeletons[name]


func _build_trees() -> void:
	var root := Node3D.new()
	root.name = "Trees"
	add_child(root)
	for t0 in gen.trees:
		var model: Dictionary = TREE_MODELS[t0["type"]]
		var scale: float = model["scale"] * t0["scale"]
		var yaw: float = t0["yaw"]
		var base: Vector3 = t0["pos"]
		base.y = ground_y(base)
		var sk := _skeleton(model["mesh"])
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
		var xf := Transform3D(basis, base)
		var trunk_r := 0.35
		if sk.has("trunkRadii"):
			trunk_r = maxf(float(sk["trunkRadii"][0]) * scale * 0.8, 0.18)
		var t := {
			"id": trees.size(), "type": t0["type"], "pos": base, "trunk_r": trunk_r,
			"perch_h": 0.0, "canopy_h": 6.0, "partway_h": 3.0, "perch_dir": Vector3(1, 0, 0),
			"deck": false, "deck_h": 0.0, "deck_half": 0.0, "rope": false, "ladder": false,
			"sturdy": t0["type"] != "bare", "rope_top": Vector3.ZERO, "rope_land": t0["rope_land"],
		}
		_anchors_from_skeleton(t, sk, xf, scale)
		trees.append(t)
		# Collision: the trunk only (players and creatures weave between trees).
		var shape := CylinderShape3D.new()
		shape.radius = trunk_r
		shape.height = t["canopy_h"] + 1.0
		Geo.static_body(root, shape, Transform3D(Basis.IDENTITY, base + Vector3(0, shape.height * 0.5, 0)), D.L_WORLD | D.L_SIGHT)
		if not _headless:
			var mi := MeshInstance3D.new()
			mi.mesh = _mesh(model["mesh"])
			mi.transform = xf
			mi.lod_bias = 4.0   # keep leaves well past the point where auto-LOD would thin them
			mi.visibility_range_end = 160.0
			mi.visibility_range_end_margin = 10.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			root.add_child(mi)
		interactables.append({"id": interactables.size(), "kind": "climb", "pos": base + Vector3(0, 1.0, 0), "tree": t["id"], "label": "tree"})
		if t["type"] != "bare":
			hide_spots.append(base + Vector3(1.2, 0, 0))


## Perch and canopy anchors sit on real branches recorded from the model's geometry.
func _anchors_from_skeleton(t: Dictionary, sk: Dictionary, xf: Transform3D, scale: float) -> void:
	var height: float = float(sk.get("height", 8.0)) * scale
	if t["type"] == "bare":
		var trunk: Array = sk.get("trunk", [])
		var top := Vector3(0, height * 0.92, 0)
		if not trunk.is_empty():
			var tp: Array = trunk[trunk.size() - 1]
			top = Vector3(tp[0], tp[1], tp[2]) * 0.97
		var top_w: Vector3 = xf * top
		t["canopy_h"] = top_w.y - t["pos"].y
		t["canopy_pos"] = top_w
		t["partway_h"] = minf(3.0, t["canopy_h"] * 0.4)
		return
	var tiers := {}
	for b in sk.get("branches", []):
		var pts: Array = b.get("points", [])
		if pts.size() < 2:
			continue
		var y0: float = snappedf(float(pts[0][1]), 0.1)
		if not tiers.has(y0):
			tiers[y0] = []
		tiers[y0].append(pts)
	var levels: Array = tiers.keys()
	levels.sort()
	if levels.is_empty():
		t["canopy_h"] = height * 0.6
		return
	var low: Array = tiers[levels[0]][0]
	var high: Array = tiers[levels[mini(1, levels.size() - 1)]][0]
	var perch_pt: Array = low[mini(2, low.size() - 1)]
	var canopy_pt: Array = high[mini(2, high.size() - 1)]
	var perch_w: Vector3 = xf * Vector3(perch_pt[0], perch_pt[1], perch_pt[2])
	var canopy_w: Vector3 = xf * Vector3(canopy_pt[0], canopy_pt[1], canopy_pt[2])
	if t["type"] == "low":
		t["perch_h"] = perch_w.y - t["pos"].y
		t["perch_pos"] = perch_w + Vector3(0, 0.15, 0)
		t["perch_dir"] = Vector3(perch_w.x - t["pos"].x, 0, perch_w.z - t["pos"].z).normalized()
	t["canopy_h"] = canopy_w.y - t["pos"].y
	t["canopy_pos"] = canopy_w + Vector3(0, 0.15, 0)


func _build_cover() -> void:
	for i in gen.grass.size():
		var g: Dictionary = gen.grass[i]
		var center: Vector3 = g["center"]
		grass.append({"center": center, "radius": g["radius"]})
		hide_spots.append(center)
		Props.tall_grass(self, center, g["radius"], gen.seed_value * 31 + i, func(x: float, z: float) -> float: return gen.height_at(x, z))
	for b in gen.bushes:
		bushes.append(b)
		hide_spots.append(b["center"])
	for r in gen.rocks:
		var p: Vector3 = r["pos"]
		var size: float = r["size"]
		var shape := BoxShape3D.new()
		shape.size = Vector3(size * 1.5, size * 0.9, size * 1.2)
		Geo.static_body(self, shape, Transform3D(Basis(Vector3.UP, r["yaw"]), p + Vector3(0, size * 0.35, 0)), D.L_WORLD | D.L_SIGHT)
		hide_spots.append(p + Vector3(size + 0.8, 0, 0))
	if _headless:
		return
	_dress_plants()


## Visual dressing only (no gameplay effect): batched per species and per chunk.
func _dress_plants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.seed_value * 7 + 3
	var buckets := {}   # "species|chunk" -> Array[Transform3D]
	var n: int = gen.n
	var per_biome := {
		IslandGen.Biome.GRASS: [["Meadow Hairgrass", 0.35, 1.4], ["Rose Plume Grass", 0.12, 1.2], ["Bronze Seed Sedge", 0.06, 1.0]],
		IslandGen.Biome.FOREST: [["Sword Fern", 0.3, 1.2], ["Forest Carpet", 0.4, 1.6], ["Elephant Ear", 0.03, 0.9]],
		IslandGen.Biome.SWAMP: [["Marsh Rush", 0.45, 1.1], ["Bronze Seed Sedge", 0.1, 1.0]],
		IslandGen.Biome.COAST: [["Bronze Seed Sedge", 0.05, 0.9]],
		IslandGen.Biome.MOUNTAIN: [["Broken Talus", 0.05, 1.2], ["Meadow Hairgrass", 0.05, 1.0]],
	}
	for k in n * n:
		if gen.walk[k] == 0:
			continue
		var b: int = gen.biome[k]
		if not per_biome.has(b):
			continue
		var c := Vector2i(k % n, k / n)
		for entry in per_biome[b]:
			if rng.randf() >= entry[1]:
				continue
			var p: Vector3 = gen.cell_center(c) + Vector3(rng.randf_range(-0.9, 0.9), 0, rng.randf_range(-0.9, 0.9))
			p.y = ground_y(p) - 0.03
			var s: float = entry[2] * rng.randf_range(0.7, 1.2)
			var key := "%s|%d|%d" % [entry[0], c.x / CHUNK, c.y / CHUNK]
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
	# Bushes are visible cover: Tide Fern clumps sized to the bush radius.
	for bsh in bushes:
		var bp: Vector3 = bsh["center"]
		bp.y = ground_y(bp)
		var key2 := "Tide Fern|b"
		if not buckets.has(key2):
			buckets[key2] = []
		buckets[key2].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, 1.15, 1.0) * float(bsh["radius"]) / 1.9), bp))
	for r in gen.rocks:
		var key3 := "Mossback Boulder|r" if int(r["size"] * 10) % 2 == 0 else "Waterworn Boulder|r"
		if not buckets.has(key3):
			buckets[key3] = []
		var rs: float = r["size"]
		buckets[key3].append(Transform3D(Basis(Vector3.UP, r["yaw"]).scaled(Vector3(rs * 0.85, rs * 0.85, rs * 0.75)), r["pos"] + Vector3(0, -0.1, 0)))
	for key in buckets:
		var species: String = key.split("|")[0]
		var xfs: Array = buckets[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _mesh(species)
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = key
		var small := species in ["Meadow Hairgrass", "Forest Carpet", "Bronze Seed Sedge", "Rose Plume Grass", "Sword Fern", "Broken Talus"]
		if small:
			mmi.visibility_range_end = 75.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


func _build_landmarks() -> void:
	landmarks = {"crash": gen.crash, "battery": gen.battery, "radio": gen.radio, "dock": gen.dock}
	# The wreck lies along the shoreline; survivors start on its inland side.
	var inland := Vector3(-gen.crash.x, 0, -gen.crash.z).normalized()
	var along := Vector3(inland.z, 0, -inland.x)
	Props.crash(self, gen.crash - inland * 2.5 + Vector3(0, -0.2, 0), atan2(inland.x, inland.z), grid)
	spawn_points.clear()
	for i in 4:
		var sp: Vector3 = gen.crash + inland * 3.5 + along * (i - 1.5) * 1.6
		spawn_points.append(Vector3(sp.x, ground_y(sp) + 0.05, sp.z))
	var shed_yaw := _facing_open(gen.radio)
	Props.radio_shed(self, gen.radio, shed_yaw, grid)
	var shed := Basis(Vector3.UP, shed_yaw)
	radio_bench = gen.radio + shed * Vector3(0, 0, -0.6)
	radio_mast_top = gen.radio + shed * Vector3(2.4, 7.0, -2.4)
	var out := Vector3(gen.dock.x, 0, gen.dock.z).normalized()
	Props.dock(self, gen.dock, out, WATER_LEVEL)
	var deck_y := maxf(gen.dock.y, WATER_LEVEL) + 0.4
	dock_board = Vector3(gen.dock.x, deck_y, gen.dock.z) + out * 6.5
	boat_pos = Vector3(gen.dock.x, WATER_LEVEL, gen.dock.z) + out * 11.0
	var bat_yaw := atan2(-gen.battery.x, -gen.battery.z)
	Props.battery_site(self, gen.battery, gen.battery_kind, bat_yaw)
	battery_kind = gen.battery_kind
	battery_spot = gen.battery + Basis(Vector3.UP, bat_yaw) * Vector3(1.4, 0, 0.6)
	battery_spot.y = ground_y(battery_spot) + 0.02
	for wp in gen.wood_piles:
		wood_piles.append(wp)
	var route: PackedVector3Array = gen.routes.get("radio_dock", PackedVector3Array())
	for i in range(6, route.size() - 4, 7):
		var q: Vector3 = route[i]
		var b: int = gen.biome_at(q)
		if b == IslandGen.Biome.FOREST or b == IslandGen.Biome.SWAMP or lurk_points.size() < 2:
			lurk_points.append(q)


func _facing_open(p: Vector3) -> float:
	# Door toward the most walkable neighbouring direction.
	var best := 0.0
	var best_score := -1
	for f in 8:
		var a := TAU * f / 8.0
		var score := 0
		for d in range(3, 9):
			var q := p + Vector3(sin(a), 0, cos(a)) * d
			if gen.is_walkable_cell(gen.to_cell(q)):
				score += 1
		if score > best_score:
			best_score = score
			best = a
	return best


## "soil" carries vibration; "rock" (mountains, cave floors) and anything up a tree don't.
func ground_kind(p: Vector3) -> String:
	if cave_at(p) >= 0 or p.y - ground_y(p) > 1.0:
		return "rock"
	return "rock" if gen.biome_at(p) == IslandGen.Biome.MOUNTAIN else "soil"
