extends Node3D
## Milestone 1–2 development fixture: one clearing with three climbable trees,
## a cave with a door and crawl exit, tall grass, bushes, rocks, the crash and a burrow.
## Builds identical geometry and gameplay markers on every peer.
## Gameplay markers (trees, cover, cave, hide spots) are plain data, separate from art.

const D = preload("res://src/core/defs.gd")
const Geo = preload("res://src/world/geo.gd")
const WalkGrid = preload("res://src/world/walk_grid.gd")
const CaveBuilder = preload("res://src/world/cave_builder.gd")

const PLAY_RADIUS := 30.0

var grid: WalkGrid
var trees: Array[Dictionary] = []
var grass: Array[Dictionary] = []       # {center, radius}
var bushes: Array[Dictionary] = []      # {center, radius}
var hide_spots: Array[Vector3] = []
var patrol_points: Array[Vector3] = []
var spawn_points: Array[Vector3] = []
var interactables: Array[Dictionary] = []
var burrow_pos := Vector3(24, 0, -6)
var caves: Array[Dictionary] = []
var cave := {}                          # caves[0], kept for convenience in tests and tools
var _headless := false

# Materials
var m_bark: Material
var m_leaf: Material
var m_leaf2: Material
var m_rock: Material
var m_rock_dark: Material
var m_wood: Material
var m_wood_dark: Material
var m_metal: Material
var m_dirt: Material
var m_black: Material


func build(_seed_value: int) -> void:
	_headless = DisplayServer.get_name() == "headless"
	m_bark = Geo.mat(Color(0.26, 0.19, 0.13))
	m_leaf = Geo.mat(Color(0.09, 0.17, 0.08))
	m_leaf2 = Geo.mat(Color(0.12, 0.2, 0.09))
	m_rock = Geo.mat(Color(0.33, 0.32, 0.3))
	m_rock_dark = Geo.mat(Color(0.2, 0.2, 0.19))
	m_wood = Geo.mat(Color(0.45, 0.33, 0.2))
	m_wood_dark = Geo.mat(Color(0.28, 0.2, 0.12))
	m_metal = Geo.mat(Color(0.55, 0.57, 0.58), 0.5)
	m_dirt = Geo.mat(Color(0.2, 0.14, 0.09))
	m_black = Geo.mat(Color(0.01, 0.01, 0.01))

	grid = WalkGrid.new()
	grid.setup(Vector2(-34, -34), Vector2i(68, 68), 1.0)
	grid.block_outside_circle(Vector3.ZERO, PLAY_RADIUS - 0.5)

	_build_ground()
	_build_boundary()
	_build_crash()
	_build_cave()
	_build_trees()
	_build_cover()
	_build_rocks()
	_build_burrow()
	_build_decor()

	patrol_points = [
		Vector3(20, 0, -6), Vector3(14, 0, 4), Vector3(6, 0, -12), Vector3(-4, 0, -10),
		Vector3(-14, 0, 0), Vector3(-6, 0, 12), Vector3(8, 0, 12), Vector3(18, 0, 14),
		Vector3(2, 0, -17), Vector3(-18, 0, -12),
	]
	spawn_points = [Vector3(-13, 0, 11.5), Vector3(-11.5, 0, 13), Vector3(-14.5, 0, 13), Vector3(-12, 0, 10)]
	for g in grass:
		hide_spots.append(g["center"])
	for b in bushes:
		hide_spots.append(b["center"])
	for t in trees:
		hide_spots.append(t["pos"] + Vector3(1.0, 0, 0))
		if t["rope"]:
			hide_spots.append(t["rope_land"])
	for c in caves:
		hide_spots.append(c["door_point"])


# ------------------------------------------------------------------ queries

func ground_y(_p: Vector3) -> float:
	return 0.0


func cover_at(p: Vector3) -> String:
	var above := p.y - ground_y(p)
	if above > 2.5:
		for t in trees:
			var h := Vector2(p.x - t["pos"].x, p.z - t["pos"].z).length()
			if h < 2.5 and p.y - t["pos"].y > t["canopy_h"] - 1.0:
				return "canopy"
		return ""
	for g in grass:
		if Vector2(p.x - g["center"].x, p.z - g["center"].z).length() < g["radius"]:
			return "grass"
	for b in bushes:
		if Vector2(p.x - b["center"].x, p.z - b["center"].z).length() < b["radius"]:
			return "bush"
	return ""


## Id of the cave containing p, or -1.
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


func trees_near(p: Vector3, r: float) -> Array:
	var out := []
	for t in trees:
		if Vector2(p.x - t["pos"].x, p.z - t["pos"].z).length() <= r:
			out.append(t)
	return out


# ------------------------------------------------------------------ door state (driven by match)

func set_door(open: bool, hp: float, id: int = 0) -> void:
	CaveBuilder.apply_door(caves[id], grid, open, hp)


func door_blocks(id: int = 0) -> bool:
	return id >= 0 and id < caves.size() and CaveBuilder.door_blocks(caves[id])


func door_body(id: int = 0) -> StaticBody3D:
	return caves[id]["door_body"]


# ------------------------------------------------------------------ builders

func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(180, 180)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode diffuse_lambert;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 c_grass : source_color = vec3(0.16, 0.2, 0.1);
uniform vec3 c_dirt : source_color = vec3(0.22, 0.17, 0.11);
uniform vec3 c_dark : source_color = vec3(0.09, 0.11, 0.07);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float n1 = texture(noise_tex, wp.xz * 0.025).r;
	float n2 = texture(noise_tex, wp.xz * 0.21).r;
	vec3 c = mix(c_grass, c_dirt, smoothstep(0.45, 0.7, n1));
	c = mix(c, c_dark, smoothstep(0.55, 0.85, n2) * 0.6);
	ALBEDO = c * (0.85 + n2 * 0.3);
	ROUGHNESS = 0.95;
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	nt.noise = fn
	sm.set_shader_parameter("noise_tex", nt)
	Geo.mesh(self, plane, Transform3D.IDENTITY, sm, false)
	var shape := BoxShape3D.new()
	shape.size = Vector3(180, 1, 180)
	Geo.static_body(self, shape, Transform3D(Basis.IDENTITY, Vector3(0, -0.5, 0)), D.L_WORLD | D.L_SIGHT)


func _build_boundary() -> void:
	# Invisible collision ring; decor trees and hills beyond it hide the edge.
	var segs := 36
	for i in segs:
		var a := TAU * i / segs
		var p := Vector3(cos(a), 0, sin(a)) * (PLAY_RADIUS + 0.5)
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.0, 6.0, TAU * (PLAY_RADIUS + 0.5) / segs + 0.4)
		var xf := Transform3D(Basis(Vector3.UP, -a), p + Vector3(0, 3, 0))
		Geo.static_body(self, shape, xf, D.L_WORLD)


func _build_crash() -> void:
	var root := Node3D.new()
	root.name = "Crash"
	add_child(root)
	var c := Vector3(-17, 0, 16)
	# Fuselage lying on its side, half buried.
	Geo.rod(root, c + Vector3(-4.5, 1.0, 0), c + Vector3(4.5, 1.2, 0.3), 1.3, m_metal)
	Geo.sphere(root, 1.3, c + Vector3(4.5, 1.2, 0.3), m_metal, Vector3(1.2, 1, 1))
	Geo.box(root, Vector3(9.5, 2.4, 2.6), c + Vector3(0, 1.1, 0.15), m_metal, D.L_WORLD | D.L_SIGHT).get_child(1).visible = false
	grid.block_rect(Vector2(c.x - 4.8, c.z - 1.2), Vector2(c.x + 5.8, c.z + 1.5))
	# Broken wing and tail.
	Geo.box(root, Vector3(1.6, 0.18, 7.0), c + Vector3(1.0, 0.25, -4.6), m_metal, D.L_WORLD, 0.25, Vector3(0.08, 0, 0.05))
	Geo.box(root, Vector3(0.15, 2.0, 1.4), c + Vector3(-4.3, 2.4, 0), m_metal, 0)
	# Debris and supply crates.
	Geo.box(root, Vector3(1.0, 0.7, 0.8), c + Vector3(3.0, 0.35, 3.2), m_wood, D.L_WORLD | D.L_SIGHT, 0.4)
	Geo.box(root, Vector3(0.8, 0.5, 0.8), c + Vector3(4.2, 0.25, 2.6), m_wood_dark, D.L_WORLD | D.L_SIGHT, -0.2)
	Geo.box(root, Vector3(2.2, 0.05, 1.0), c + Vector3(-1.0, 0.03, 3.5), m_metal, 0, 1.1)
	grid.block_rect(Vector2(c.x + 2.4, c.z + 2.1), Vector2(c.x + 4.7, c.z + 3.7))


func _build_cave() -> void:
	caves = [CaveBuilder.build(self, grid, 0, Vector3(4.0, 0, -20.5), 0)]
	cave = caves[0]
	set_door(false, Tuning.door_hp, 0)
	interactables.append({"id": interactables.size(), "kind": "door", "pos": cave["door_center"], "cave": 0, "label": "door"})


func _build_trees() -> void:
	var defs := [
		{"type": "low", "pos": Vector3(-4, 0, 3), "trunk_r": 0.38, "perch_h": 2.2, "canopy_h": 5.0,
			"deck": true, "rope": true, "rope_dir": Vector3(1, 0, 0.4).normalized(), "ladder": false, "perch_dir": Vector3(-0.6, 0, -1).normalized()},
		{"type": "rough", "pos": Vector3(11, 0, -5), "trunk_r": 0.45, "perch_h": 0.0, "canopy_h": 6.0,
			"deck": false, "rope": false, "ladder": false, "perch_dir": Vector3(-1, 0, 0.3).normalized()},
		{"type": "bare", "pos": Vector3(-13, 0, -7), "trunk_r": 0.3, "perch_h": 0.0, "canopy_h": 7.0, "partway_h": 3.0,
			"deck": false, "rope": false, "ladder": true, "perch_dir": Vector3(1, 0, 0.5).normalized()},
	]
	for d in defs:
		var t: Dictionary = {
			"id": trees.size(), "type": d["type"], "pos": d["pos"], "trunk_r": d["trunk_r"],
			"perch_h": d["perch_h"], "canopy_h": d["canopy_h"], "partway_h": d.get("partway_h", 0.0),
			"deck": d["deck"], "deck_h": d["canopy_h"], "deck_half": 1.6, "rope": d["rope"],
			"ladder": d["ladder"], "perch_dir": d["perch_dir"], "sturdy": d["type"] != "bare",
			"rope_top": Vector3.ZERO, "rope_land": Vector3.ZERO,
		}
		if t["rope"]:
			var rd: Vector3 = d["rope_dir"]
			t["rope_top"] = t["pos"] + rd * 1.5 + Vector3(0, t["deck_h"], 0)
			t["rope_land"] = t["pos"] + rd * 6.5
		trees.append(t)
		_build_tree_visual(t)
		grid.block_circle(t["pos"], t["trunk_r"])
		interactables.append({"id": interactables.size(), "kind": "climb", "pos": t["pos"] + Vector3(0, 1.0, 0), "tree": t["id"], "label": "tree"})
		if t["deck"]:
			interactables.append({"id": interactables.size(), "kind": "deck_down", "pos": t["pos"] + Vector3(0, t["deck_h"] + 1.0, 0), "tree": t["id"], "label": "trunk"})
		if t["rope"]:
			interactables.append({"id": interactables.size(), "kind": "rope", "pos": t["rope_top"] + Vector3(0, 0.6, 0), "tree": t["id"], "label": "rope"})


func _build_tree_visual(t: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Tree%d" % t["id"]
	add_child(root)
	var base: Vector3 = t["pos"]
	var r: float = t["trunk_r"]
	var top: float = t["canopy_h"] + (3.8 if t["deck"] else 2.6)
	Geo.cylinder(root, r, top, base, m_bark, D.L_WORLD | D.L_SIGHT, r * 0.6, 10)
	# Root flare.
	Geo.cylinder(root, r * 1.6, 0.5, base, m_bark, 0, r, 10)
	var canopy_y: float = t["canopy_h"]
	var rng := RandomNumberGenerator.new()
	rng.seed = t["id"] * 31 + 5
	for i in 6:
		# Deck trees keep the foliage above head height so the platform is usable.
		var lift := Vector2(3.1, 4.2) if t["deck"] else Vector2(1.2, 2.8)
		var off := Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(lift.x, lift.y), rng.randf_range(-1.6, 1.6))
		var rad := rng.randf_range(1.2, 1.6) if t["deck"] else rng.randf_range(1.3, 1.9)
		Geo.sphere(root, rad, base + Vector3(0, canopy_y, 0) + off, m_leaf if i % 2 == 0 else m_leaf2, Vector3(1.0, 0.7, 1.0))
	match t["type"]:
		"low":
			var pd: Vector3 = t["perch_dir"]
			Geo.rod(root, base + Vector3(0, t["perch_h"], 0), base + pd * 1.6 + Vector3(0, t["perch_h"] + 0.25, 0), 0.12, m_bark)
			Geo.rod(root, base + Vector3(0, 1.3, 0), base + pd.rotated(Vector3.UP, 2.2) * 1.3 + Vector3(0, 1.6, 0), 0.09, m_bark)
			Geo.rod(root, base + Vector3(0, 3.4, 0), base + pd.rotated(Vector3.UP, -1.9) * 1.5 + Vector3(0, 3.8, 0), 0.1, m_bark)
		"rough":
			for i in 7:
				var a := i * 1.3
				Geo.box(root, Vector3(0.25, 0.12, 0.12), base + Vector3(cos(a) * r, 0.6 + i * 0.75, sin(a) * r), m_wood_dark, 0, -a)
		"bare":
			pass
	if t["deck"]:
		var dh: float = t["deck_h"]
		var half: float = t["deck_half"]
		var deck := Geo.box(root, Vector3(half * 2, 0.15, half * 2), base + Vector3(0, dh - 0.075, 0), m_wood)
		deck.name = "Deck"
		for i in 4:
			var a := i * PI * 0.5
			Geo.rod(root, base + Vector3(0, dh - 0.1, 0), base + Vector3(cos(a), 0, sin(a)) * half * 1.3 + Vector3(0, dh - 1.6, 0), 0.07, m_wood_dark)
	if t["rope"]:
		Geo.rod(root, t["rope_top"] + Vector3(0, 0.4, 0), t["rope_land"] + Vector3(0, 0.05, 0), 0.03, Geo.mat(Color(0.6, 0.52, 0.36)))
		Geo.box(root, Vector3(0.3, 0.15, 0.3), t["rope_land"] + Vector3(0, 0.07, 0), m_wood_dark, 0)
	if t["ladder"]:
		var ld: Vector3 = -t["perch_dir"]
		var side := ld.cross(Vector3.UP).normalized() * 0.22
		var lb: Vector3 = base + ld * (r + 0.12)
		var lt: float = t["canopy_h"] + 0.3
		Geo.rod(root, lb + side, lb + side + Vector3(0, lt, 0), 0.035, m_wood)
		Geo.rod(root, lb - side, lb - side + Vector3(0, lt, 0), 0.035, m_wood)
		var rung := 0.35
		while rung < lt:
			Geo.rod(root, lb + side + Vector3(0, rung, 0), lb - side + Vector3(0, rung, 0), 0.025, m_wood)
			rung += 0.4


func _build_cover() -> void:
	grass = [
		{"center": Vector3(3, 0, 6), "radius": 4.0},
		{"center": Vector3(-9, 0, 9), "radius": 3.5},
		{"center": Vector3(15, 0, 9), "radius": 5.0},
		{"center": Vector3(-6, 0, -14), "radius": 3.2},
	]
	bushes = [
		{"center": Vector3(9, 0, -14), "radius": 1.3},
		{"center": Vector3(-18, 0, -1), "radius": 1.4},
		{"center": Vector3(18, 0, -12), "radius": 1.2},
		{"center": Vector3(0, 0, 15), "radius": 1.3},
	]
	if not _headless:
		for i in grass.size():
			_build_grass_patch(grass[i], i)
	for b in bushes:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(b["center"].x * 100 + b["center"].z)
		for i in 5:
			var off: Vector3 = Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.4, 0.8), rng.randf_range(-0.6, 0.6)) * b["radius"]
			Geo.sphere(self, b["radius"] * rng.randf_range(0.5, 0.75), b["center"] + off, m_leaf2 if i % 2 else m_leaf, Vector3(1, 0.8, 1))


func _build_grass_patch(g: Dictionary, idx: int) -> void:
	var blade := _blade_mesh()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = blade
	var r: float = g["radius"]
	var count := int(PI * r * r * 34.0)
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + idx
	for i in count:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r
		var edge := 1.0 - smoothstep(r * 0.75, r, d)
		var h := Tuning.grass_height * rng.randf_range(0.75, 1.2) * (0.45 + 0.55 * edge)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3(1, 0, 0), rng.randf_range(-0.2, 0.2)).scaled(Vector3(1, h, 1))
		mm.set_instance_transform(i, Transform3D(basis, g["center"] + Vector3(cos(a) * d, 0, sin(a) * d)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.material_override = _grass_material()
	add_child(mmi)


static var _grass_mat: ShaderMaterial
func _grass_material() -> ShaderMaterial:
	if _grass_mat:
		return _grass_mat
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform vec3 base_color : source_color = vec3(0.07, 0.1, 0.04);
uniform vec3 tip_color : source_color = vec3(0.34, 0.38, 0.17);
uniform float sway = 0.1;
void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = UV.y;
	float t = TIME * 1.4 + origin.x * 0.31 + origin.z * 0.23;
	VERTEX.x += sin(t) * sway * h * h;
	VERTEX.z += cos(t * 0.83) * sway * 0.6 * h * h;
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	ALBEDO = mix(base_color, tip_color, UV.y);
	ROUGHNESS = 1.0;
}
"""
	_grass_mat = ShaderMaterial.new()
	_grass_mat.shader = sh
	return _grass_mat


func _blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 3
	var w := 0.07
	var pts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for i in segs + 1:
		var f := float(i) / segs
		var ww := w * (1.0 - f * 0.9)
		var bend := f * f * 0.12
		pts.append(Vector3(-ww, f, bend))
		pts.append(Vector3(ww, f, bend))
		uvs.append(Vector2(0, f))
		uvs.append(Vector2(1, f))
	for i in segs:
		var a := i * 2
		for idx in [a, a + 1, a + 2, a + 1, a + 3, a + 2]:
			st.set_uv(uvs[idx])
			st.set_normal(Vector3.UP)
			st.add_vertex(pts[idx])
	return st.commit()


func _build_rocks() -> void:
	var rocks := [
		[Vector3(7, 1.0, 13), Vector3(3.0, 2.0, 2.0), 0.3],
		[Vector3(-8, 0.8, -3), Vector3(2.0, 1.6, 2.6), 0.8],
		[Vector3(20, 1.1, 2), Vector3(2.5, 2.2, 3.0), -0.4],
	]
	for r in rocks:
		Geo.box(self, r[1], r[0], m_rock, D.L_WORLD | D.L_SIGHT, r[2])
		var rad: float = maxf(r[1].x, r[1].z) * 0.55
		grid.block_circle(Vector3(r[0].x, 0, r[0].z), rad, 0.2)
		hide_spots.append(Vector3(r[0].x, 0, r[0].z) + Vector3(rad + 1.0, 0, 0).rotated(Vector3.UP, r[2] + PI))
	# Fallen trunk: low sight blocker you can crouch behind.
	var a := Vector3(2.5, 0.4, -10.5)
	var b := Vector3(7.5, 0.35, -7.5)
	Geo.rod(self, a, b, 0.42, m_bark)
	var dir := (b - a)
	var shape := BoxShape3D.new()
	shape.size = Vector3(dir.length(), 0.8, 0.8)
	var xf := Transform3D(Basis(Vector3.UP, -atan2(dir.z, dir.x)), (a + b) * 0.5)
	Geo.static_body(self, shape, xf, D.L_WORLD | D.L_SIGHT)
	for s in 6:
		grid.block_circle(a.lerp(b, s / 5.0), 0.4, 0.15)


func _build_burrow() -> void:
	var root := Node3D.new()
	root.name = "Burrow"
	add_child(root)
	for i in 8:
		var a := TAU * i / 8.0
		Geo.sphere(root, 0.8, burrow_pos + Vector3(cos(a) * 1.5, 0.05, sin(a) * 1.5), m_dirt, Vector3(1, 0.4, 1))
	var hole := CylinderMesh.new()
	hole.top_radius = 1.2
	hole.bottom_radius = 0.6
	hole.height = 0.02
	Geo.mesh(root, hole, Transform3D(Basis.IDENTITY, burrow_pos + Vector3(0, 0.02, 0)), m_black, false)
	# Gouges in nearby wood hint at what the creatures are.
	Geo.box(root, Vector3(0.05, 0.6, 0.02), burrow_pos + Vector3(-2.6, 0.5, 1.0), m_black, 0, 0.3, Vector3(0, 0, 0.3))


func _build_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 90:
		var a := rng.randf() * TAU
		var d := rng.randf_range(PLAY_RADIUS + 1.5, PLAY_RADIUS + 16.0)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		if Vector2(p.x - 4, p.z + 25).length() < 9.0:
			continue  # keep the cave outcrop clear
		var h := rng.randf_range(6.0, 11.0)
		Geo.cylinder(self, rng.randf_range(0.25, 0.5), h, p, m_bark, 0, 0.15, 6)
		for j in 3:
			Geo.sphere(self, rng.randf_range(1.6, 2.6), p + Vector3(rng.randf_range(-1, 1), h - 1.0 + j * 0.8, rng.randf_range(-1, 1)), m_leaf if j % 2 else m_leaf2, Vector3(1, 0.75, 1))
	for i in 14:
		var a := rng.randf() * TAU
		var d := rng.randf_range(PLAY_RADIUS + 10.0, PLAY_RADIUS + 30.0)
		Geo.sphere(self, rng.randf_range(8.0, 14.0), Vector3(cos(a) * d, -3.0, sin(a) * d), m_leaf, Vector3(1.4, 0.7, 1.4), false)


func ground_kind(p: Vector3) -> String:
	return "rock" if cave_at(p) >= 0 or p.y > 1.0 else "soil"
