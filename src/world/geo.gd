extends RefCounted
## Small helpers for building placeholder geometry in code.

const D = preload("res://src/core/defs.gd")

static var _mats: Dictionary = {}


static func mat(color: Color, roughness: float = 0.92, emission: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%s|%.2f" % [color.to_html(), roughness, emission.to_html(), emission_energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	_mats[key] = m
	return m


static func mesh(parent: Node3D, m: Mesh, xform: Transform3D, material: Material, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.transform = xform
	mi.material_override = material
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func static_body(parent: Node3D, shape: Shape3D, xform: Transform3D, layers: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layers
	body.collision_mask = 0
	body.transform = xform
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body


## A solid box: visible mesh plus collision on the given layers.
static func box(parent: Node3D, size: Vector3, center: Vector3, material: Material, layers: int = D.L_WORLD | D.L_SIGHT, rot_y: float = 0.0, rot: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var xf := Transform3D(Basis.from_euler(Vector3(rot.x, rot_y + rot.y, rot.z)), center)
	var bm := BoxMesh.new()
	bm.size = size
	var shape := BoxShape3D.new()
	shape.size = size
	var body: StaticBody3D = null
	if layers != 0:
		body = static_body(parent, shape, xf, layers)
		mesh(body, bm, Transform3D.IDENTITY, material)
	else:
		mesh(parent, bm, xf, material)
	return body


static func cylinder(parent: Node3D, radius: float, height: float, base: Vector3, material: Material, layers: int = D.L_WORLD | D.L_SIGHT, top_radius: float = -1.0, segments: int = 12) -> StaticBody3D:
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius if top_radius < 0.0 else top_radius
	cm.height = height
	cm.radial_segments = segments
	var xf := Transform3D(Basis.IDENTITY, base + Vector3(0, height * 0.5, 0))
	if layers == 0:
		mesh(parent, cm, xf, material)
		return null
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var body := static_body(parent, shape, xf, layers)
	mesh(body, cm, Transform3D.IDENTITY, material)
	return body


## A cylinder between two points (branches, rails, rope). Visual only.
static func rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material, shadows: bool = true) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = a.distance_to(b)
	cm.radial_segments = 6
	var dir := (b - a).normalized()
	var up := Vector3.UP
	var basis := Basis.IDENTITY
	if absf(dir.dot(up)) < 0.999:
		var x := up.cross(dir).normalized()
		var z := x.cross(dir).normalized()
		basis = Basis(x, dir, z)
	return mesh(parent, cm, Transform3D(basis, (a + b) * 0.5), material, shadows)


static func sphere(parent: Node3D, radius: float, center: Vector3, material: Material, squash: Vector3 = Vector3.ONE, shadows: bool = true) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	return mesh(parent, sm, Transform3D(Basis.from_scale(squash), center), material, shadows)
