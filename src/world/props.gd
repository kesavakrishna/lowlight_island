extends RefCounted
## Placeholder landmark and cover builders shared by the generated island.
## Gameplay data (cover zones, blocked cells) is returned or applied to the grid;
## the meshes are art and can be swapped later without touching the rules.

const D = preload("res://src/core/defs.gd")
const Geo = preload("res://src/world/geo.gd")

static var _grass_mat: ShaderMaterial
static var _blade: ArrayMesh


## Tall grass you can crawl through. `ground` maps (x, z) to terrain height.
static func tall_grass(parent: Node3D, center: Vector3, radius: float, seed_value: int, ground: Callable) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _blade_mesh()
	var count := int(PI * radius * radius * 30.0)
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in count:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * radius
		var edge := 1.0 - smoothstep(radius * 0.75, radius, d)
		var h := Tuning.grass_height * rng.randf_range(0.75, 1.2) * (0.45 + 0.55 * edge)
		var x := center.x + cos(a) * d
		var z := center.z + sin(a) * d
		var basis := Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3(1, 0, 0), rng.randf_range(-0.2, 0.2)).scaled(Vector3(1, h, 1))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x, ground.call(x, z) - 0.05, z)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.material_override = grass_material()
	mmi.visibility_range_end = 120.0
	parent.add_child(mmi)


static func grass_material() -> ShaderMaterial:
	if _grass_mat:
		return _grass_mat
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform vec3 base_color : source_color = vec3(0.07, 0.1, 0.04);
uniform vec3 tip_color : source_color = vec3(0.36, 0.40, 0.18);
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


static func _blade_mesh() -> ArrayMesh:
	if _blade:
		return _blade
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
		for k in [a, a + 1, a + 2, a + 1, a + 3, a + 2]:
			st.set_uv(uvs[k])
			st.set_normal(Vector3.UP)
			st.add_vertex(pts[k])
	_blade = st.commit()
	return _blade


## The wreck: fuselage, wing, tail and supply crates. Blocks the grid around it.
static func crash(parent: Node3D, pos: Vector3, yaw: float, grid: RefCounted) -> void:
	var root := Node3D.new()
	root.name = "Crash"
	root.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	parent.add_child(root)
	var metal := Geo.mat(Color(0.55, 0.57, 0.58), 0.5)
	var wood := Geo.mat(Color(0.45, 0.33, 0.2))
	Geo.rod(root, Vector3(-4.5, 0.9, 0), Vector3(4.5, 1.1, 0.3), 1.3, metal)
	Geo.sphere(root, 1.3, Vector3(4.5, 1.1, 0.3), metal, Vector3(1.2, 1, 1))
	Geo.box(root, Vector3(9.5, 2.4, 2.6), Vector3(0, 1.0, 0.15), metal, D.L_WORLD | D.L_SIGHT).get_child(1).visible = false
	Geo.box(root, Vector3(1.6, 0.18, 7.0), Vector3(1.0, 0.2, -4.6), metal, D.L_WORLD, 0.25, Vector3(0.08, 0, 0.05))
	Geo.box(root, Vector3(0.15, 2.0, 1.4), Vector3(-4.3, 2.3, 0), metal, 0)
	Geo.box(root, Vector3(1.0, 0.7, 0.8), Vector3(3.0, 0.3, 3.2), wood, D.L_WORLD | D.L_SIGHT, 0.4)
	var xf := root.transform
	_block_box(grid, xf, Vector3(-4.8, 0, -1.2), Vector3(5.8, 0, 1.5))


## The radio shed on high ground: a small hut with a doorway and an antenna mast.
static func radio_shed(parent: Node3D, pos: Vector3, yaw: float, grid: RefCounted) -> void:
	var root := Node3D.new()
	root.name = "RadioShed"
	root.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	parent.add_child(root)
	var plank := Geo.mat(Color(0.36, 0.3, 0.22))
	var roof := Geo.mat(Color(0.22, 0.2, 0.18))
	var metal := Geo.mat(Color(0.6, 0.58, 0.52), 0.5)
	# Back and side walls, front wall with a doorway (local +Z is the door side).
	Geo.box(root, Vector3(4.0, 2.6, 0.2), Vector3(0, 1.3, -1.9), plank)
	Geo.box(root, Vector3(0.2, 2.6, 4.0), Vector3(-1.9, 1.3, 0), plank)
	Geo.box(root, Vector3(0.2, 2.6, 4.0), Vector3(1.9, 1.3, 0), plank)
	Geo.box(root, Vector3(1.4, 2.6, 0.2), Vector3(-1.3, 1.3, 1.9), plank)
	Geo.box(root, Vector3(1.4, 2.6, 0.2), Vector3(1.3, 1.3, 1.9), plank)
	Geo.box(root, Vector3(1.2, 0.5, 0.2), Vector3(0, 2.35, 1.9), plank)
	Geo.box(root, Vector3(4.6, 0.15, 4.6), Vector3(0, 2.7, 0), roof, D.L_WORLD | D.L_SIGHT, 0.0, Vector3(0.08, 0, 0))
	Geo.box(root, Vector3(1.3, 0.9, 0.6), Vector3(0, 0.45, -1.4), Geo.mat(Color(0.28, 0.3, 0.26)))   # transmitter bench
	Geo.box(root, Vector3(0.12, 7.0, 0.12), Vector3(2.4, 3.5, -2.4), metal, D.L_WORLD)
	Geo.box(root, Vector3(2.4, 0.08, 0.08), Vector3(2.4, 6.6, -2.4), metal, 0)
	var xf := root.transform
	_block_box(grid, xf, Vector3(-2.0, 0, -2.0), Vector3(2.0, 0, -1.8))
	_block_box(grid, xf, Vector3(-2.0, 0, -2.0), Vector3(-1.8, 0, 2.0))
	_block_box(grid, xf, Vector3(1.8, 0, -2.0), Vector3(2.0, 0, 2.0))


## The old dock: planks out over the water with a moored skiff silhouette.
static func dock(parent: Node3D, pos: Vector3, out_dir: Vector3, water_y: float) -> void:
	var root := Node3D.new()
	root.name = "Dock"
	var yaw := atan2(out_dir.x, out_dir.z)
	root.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, 0, pos.z))
	parent.add_child(root)
	var wood := Geo.mat(Color(0.4, 0.31, 0.21))
	var deck_y := maxf(pos.y, water_y) + 0.35
	for i in 9:
		Geo.box(root, Vector3(2.4, 0.08, 0.32), Vector3(0, deck_y, i * 0.95), wood, D.L_WORLD, 0.0, Vector3(0, 0, (i % 3 - 1) * 0.02))
	for i in 5:
		for s in [-1.1, 1.1]:
			Geo.box(root, Vector3(0.18, 3.0, 0.18), Vector3(s, deck_y - 1.4, i * 2.0), Geo.mat(Color(0.25, 0.2, 0.15)), 0)


## Battery site: a beached skiff or a salvage crate under a tree.
static func battery_site(parent: Node3D, pos: Vector3, kind: String, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "BatterySite"
	root.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	parent.add_child(root)
	if kind == "skiff":
		var hull := Geo.mat(Color(0.5, 0.45, 0.4))
		Geo.box(root, Vector3(1.4, 0.5, 3.6), Vector3(0, 0.3, 0), hull, D.L_WORLD | D.L_SIGHT, 0.0, Vector3(0, 0, 0.25))
	else:
		Geo.box(root, Vector3(1.2, 0.8, 0.9), Vector3(0, 0.4, 0), Geo.mat(Color(0.35, 0.3, 0.22)), D.L_WORLD | D.L_SIGHT)
	# The battery itself is drawn by objectives.gd (it moves when carried).


static func burrow(parent: Node3D, pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Burrow"
	parent.add_child(root)
	var dirt := Geo.mat(Color(0.2, 0.14, 0.09))
	for i in 8:
		var a := TAU * i / 8.0
		Geo.sphere(root, 0.8, pos + Vector3(cos(a) * 1.5, 0.05, sin(a) * 1.5), dirt, Vector3(1, 0.4, 1))
	var hole := CylinderMesh.new()
	hole.top_radius = 1.2
	hole.bottom_radius = 0.6
	hole.height = 0.02
	Geo.mesh(root, hole, Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.03, 0)), Geo.mat(Color(0.01, 0.01, 0.01)), false)


static func _block_box(grid: RefCounted, xf: Transform3D, a: Vector3, b: Vector3) -> void:
	var p1 := xf * a
	var p2 := xf * b
	var p3 := xf * Vector3(a.x, 0, b.z)
	var p4 := xf * Vector3(b.x, 0, a.z)
	var mn := Vector2(minf(minf(p1.x, p2.x), minf(p3.x, p4.x)), minf(minf(p1.z, p2.z), minf(p3.z, p4.z)))
	var mx := Vector2(maxf(maxf(p1.x, p2.x), maxf(p3.x, p4.x)), maxf(maxf(p1.z, p2.z), maxf(p3.z, p4.z)))
	grid.block_rect(mn, mx, 0.3)
