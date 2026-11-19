extends RefCounted
## Organic creature geometry built in code: smooth tapered tubes along curved paths
## (limbs, spines, tails, claws) with rounded ends, and a wet, rim-lit skin material so
## silhouettes read against lantern light. Darkness and silhouette carry the horror.

static var _skins: Dictionary = {}


## A tube through `points` (Catmull-Rom smoothed) with a radius per point.
static func tube(points: PackedVector3Array, radii: PackedFloat32Array, sides: int = 8, steps_per_seg: int = 4) -> ArrayMesh:
	var path := PackedVector3Array()
	var rad := PackedFloat32Array()
	var n := points.size()
	for i in n - 1:
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, n - 1)]
		for sstep in steps_per_seg:
			var t := float(sstep) / steps_per_seg
			path.append(_catmull(p0, p1, p2, p3, t))
			rad.append(lerpf(radii[i], radii[i + 1], t))
	path.append(points[n - 1])
	rad.append(radii[n - 1])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	var prev_side := Vector3.RIGHT
	for i in path.size():
		var fwd := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		if fwd.length() < 0.001:
			fwd = Vector3.UP
		var side := (prev_side - fwd * prev_side.dot(fwd)).normalized()
		if side.length() < 0.001:
			side = fwd.cross(Vector3.FORWARD).normalized()
		prev_side = side
		var up := fwd.cross(side).normalized()
		var ring: Array = []
		for k in sides:
			var a := TAU * k / sides
			var nrm := (side * cos(a) + up * sin(a)).normalized()
			ring.append([path[i] + nrm * rad[i], nrm])
		rings.append(ring)
	for i in rings.size() - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			var a: Array = rings[i][k]
			var b: Array = rings[i][k2]
			var c: Array = rings[i + 1][k]
			var d: Array = rings[i + 1][k2]
			for v in [a, c, b, b, c, d]:
				st.set_normal(v[1])
				st.add_vertex(v[0])
	# Rounded caps.
	for end in [0, rings.size() - 1]:
		var center := path[end]
		var dir := (path[mini(1, path.size() - 1)] - path[0]).normalized() * -1.0 if end == 0 else (path[end] - path[end - 1]).normalized()
		var tip := center + dir * rad[end] * 0.8
		for k in sides:
			var a2: Array = rings[end][k]
			var b2: Array = rings[end][(k + 1) % sides]
			var tri := [a2, b2] if end != 0 else [b2, a2]
			st.set_normal(dir)
			st.add_vertex(tip)
			for v in tri:
				st.set_normal(v[1])
				st.add_vertex(v[0])
	return st.commit()


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Wet, dark skin with a rim highlight so the outline catches the lantern.
static func skin(color: Color, wet: float = 0.4) -> StandardMaterial3D:
	var key := "%s|%.2f" % [color.to_html(), wet]
	if _skins.has(key):
		return _skins[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0 - wet
	m.metallic_specular = 0.6
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.4
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_skins[key] = m
	return m


static func add(parent: Node3D, mesh: Mesh, mat: Material, xform: Transform3D = Transform3D.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xform
	parent.add_child(mi)
	return mi
