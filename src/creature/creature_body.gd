extends RefCounted
## Placeholder silhouettes, sounds and tracks per creature type. Each type keeps a
## distinct base silhouette so a crew can tell them apart; scars attach on top so a
## returning individual is recognisable. Swap these builders for real models later.

const Geo = preload("res://src/world/geo.gd")

const CALLS := {          # sound, pitch, volume
	"stalker": ["call", 1.0, 4.0],
	"listener": ["chitter", 0.45, 8.0],
	"digger": ["breach_warn", 0.55, 8.0],
	"climber": ["call", 1.55, 2.0],
}
const STEPS := {
	"stalker": ["creature_step", 0.9, -4.0],
	"listener": ["step_soft", 0.6, -6.0],
	"digger": ["creature_step", 0.6, -1.0],
	"climber": ["step", 1.3, -8.0],
}


static func build(ctype: String, parent: Node3D) -> Dictionary:
	match ctype:
		"listener": return _listener(parent)
		"digger": return _digger(parent)
		"climber": return _climber(parent)
	return _stalker(parent)


static func _parts(parent: Node3D, torso_y: float) -> Dictionary:
	var vis := Node3D.new()
	parent.add_child(vis)
	var torso := Node3D.new()
	torso.position = Vector3(0, torso_y, 0)
	vis.add_child(torso)
	return {"vis": vis, "torso": torso, "eyes": []}


static func _stalker(parent: Node3D) -> Dictionary:
	var skin := Geo.mat(Color(0.035, 0.03, 0.035), 0.45)
	var eye_m := Geo.mat(Color(0.9, 0.6, 0.2), 0.3, Color(1.0, 0.55, 0.15), 2.5)
	var d := _parts(parent, 1.15)
	var torso: Node3D = d["torso"]
	Geo.mesh(torso, _capsule(0.24, 1.2), Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0)), skin)
	Geo.sphere(torso, 0.26, Vector3(0, 1.05, 0.05), skin, Vector3(1.6, 0.6, 1.0))
	var head := Node3D.new()
	head.position = Vector3(0, 1.3, -0.2)
	torso.add_child(head)
	Geo.sphere(head, 0.17, Vector3.ZERO, skin, Vector3(0.75, 0.85, 1.5))
	d["eyes"] = [Geo.sphere(head, 0.03, Vector3(0.07, 0.03, -0.22), eye_m, Vector3.ONE, false),
		Geo.sphere(head, 0.03, Vector3(-0.07, 0.03, -0.22), eye_m, Vector3.ONE, false)]
	d["head"] = head
	d["arm_l"] = _limb(torso, Vector3(0.36, 1.05, 0), 1.45, 0.06, skin)
	d["arm_r"] = _limb(torso, Vector3(-0.36, 1.05, 0), 1.45, 0.06, skin)
	d["leg_l"] = _limb(d["vis"], Vector3(0.17, 1.15, 0), 1.15, 0.08, skin)
	d["leg_r"] = _limb(d["vis"], Vector3(-0.17, 1.15, 0), 1.15, 0.08, skin)
	d["lean"] = 0.35
	return d


## Blind, low and hunched, with wide ear flaps and no eyes at all.
static func _listener(parent: Node3D) -> Dictionary:
	var skin := Geo.mat(Color(0.32, 0.29, 0.27), 0.6)
	var dark := Geo.mat(Color(0.05, 0.03, 0.03), 0.8)
	var d := _parts(parent, 0.85)
	var torso: Node3D = d["torso"]
	Geo.mesh(torso, _capsule(0.3, 1.3), Transform3D(Basis(Vector3.RIGHT, PI * 0.42), Vector3(0, 0.25, 0.05)), skin)
	var head := Node3D.new()
	head.position = Vector3(0, 0.45, -0.75)
	torso.add_child(head)
	Geo.sphere(head, 0.24, Vector3.ZERO, skin, Vector3(1.3, 0.7, 1.1))
	Geo.sphere(head, 0.22, Vector3(0.32, 0.05, 0.05), skin, Vector3(0.25, 1.1, 1.0))    # ear flaps
	Geo.sphere(head, 0.22, Vector3(-0.32, 0.05, 0.05), skin, Vector3(0.25, 1.1, 1.0))
	Geo.box(head, Vector3(0.3, 0.06, 0.12), Vector3(0, -0.08, -0.22), dark, 0)           # open maw
	d["head"] = head
	d["arm_l"] = _limb(torso, Vector3(0.28, 0.4, -0.55), 1.0, 0.07, skin)
	d["arm_r"] = _limb(torso, Vector3(-0.28, 0.4, -0.55), 1.0, 0.07, skin)
	d["leg_l"] = _limb(d["vis"], Vector3(0.22, 0.95, 0.35), 0.95, 0.09, skin)
	d["leg_r"] = _limb(d["vis"], Vector3(-0.22, 0.95, 0.35), 0.95, 0.09, skin)
	d["lean"] = 0.1
	return d


## Squat and broad with armoured back plates, heavy claws and small low red eyes.
static func _digger(parent: Node3D) -> Dictionary:
	var skin := Geo.mat(Color(0.12, 0.09, 0.06), 0.8)
	var plate := Geo.mat(Color(0.2, 0.16, 0.12), 0.6)
	var eye_m := Geo.mat(Color(0.6, 0.1, 0.05), 0.3, Color(0.9, 0.15, 0.05), 1.6)
	var d := _parts(parent, 0.7)
	var torso: Node3D = d["torso"]
	Geo.sphere(torso, 0.55, Vector3(0, 0.25, 0), skin, Vector3(1.25, 0.85, 1.35))
	for i in 4:
		Geo.box(torso, Vector3(0.9 - i * 0.1, 0.08, 0.3), Vector3(0, 0.68 - i * 0.05, -0.35 + i * 0.28), plate, 0, 0.0, Vector3(0.3, 0, 0))
	var head := Node3D.new()
	head.position = Vector3(0, 0.25, -0.62)
	torso.add_child(head)
	Geo.sphere(head, 0.25, Vector3.ZERO, skin, Vector3(1.2, 0.8, 1.1))
	d["eyes"] = [Geo.sphere(head, 0.025, Vector3(0.1, 0.05, -0.24), eye_m, Vector3.ONE, false),
		Geo.sphere(head, 0.025, Vector3(-0.1, 0.05, -0.24), eye_m, Vector3.ONE, false)]
	d["head"] = head
	d["arm_l"] = _limb(torso, Vector3(0.55, 0.35, -0.3), 0.75, 0.11, skin)
	d["arm_r"] = _limb(torso, Vector3(-0.55, 0.35, -0.3), 0.75, 0.11, skin)
	for arm in [d["arm_l"], d["arm_r"]]:
		for c in 3:
			Geo.box(arm, Vector3(0.04, 0.04, 0.22), Vector3(-0.06 + c * 0.06, -0.75, -0.25), plate, 0)
	d["leg_l"] = _limb(d["vis"], Vector3(0.3, 0.7, 0.2), 0.7, 0.12, skin)
	d["leg_r"] = _limb(d["vis"], Vector3(-0.3, 0.7, 0.2), 0.7, 0.12, skin)
	d["lean"] = 0.2
	return d


## Spindly: a small body on very long arms with hooked claws and four pale eyes.
static func _climber(parent: Node3D) -> Dictionary:
	var skin := Geo.mat(Color(0.07, 0.08, 0.07), 0.5)
	var claw := Geo.mat(Color(0.5, 0.48, 0.42), 0.4)
	var eye_m := Geo.mat(Color(0.6, 0.9, 0.6), 0.3, Color(0.5, 0.95, 0.55), 1.8)
	var d := _parts(parent, 1.25)
	var torso: Node3D = d["torso"]
	Geo.mesh(torso, _capsule(0.17, 0.8), Transform3D(Basis.IDENTITY, Vector3(0, 0.4, 0)), skin)
	var head := Node3D.new()
	head.position = Vector3(0, 0.95, -0.12)
	torso.add_child(head)
	Geo.sphere(head, 0.13, Vector3.ZERO, skin, Vector3(0.9, 0.8, 1.3))
	var eyes: Array = []
	for ex in [0.05, -0.05]:
		for ey in [0.04, -0.02]:
			eyes.append(Geo.sphere(head, 0.018, Vector3(ex * (1.4 if ey < 0 else 1.0), ey, -0.15), eye_m, Vector3.ONE, false))
	d["eyes"] = eyes
	d["head"] = head
	d["arm_l"] = _limb(torso, Vector3(0.24, 0.75, 0), 1.9, 0.045, skin)
	d["arm_r"] = _limb(torso, Vector3(-0.24, 0.75, 0), 1.9, 0.045, skin)
	for arm in [d["arm_l"], d["arm_r"]]:
		Geo.rod(arm, Vector3(0, -1.9, -0.12), Vector3(0, -2.05, -0.3), 0.02, claw)
	d["leg_l"] = _limb(d["vis"], Vector3(0.14, 1.25, 0), 1.25, 0.05, skin)
	d["leg_r"] = _limb(d["vis"], Vector3(-0.14, 1.25, 0), 1.25, 0.05, skin)
	d["lean"] = 0.5
	return d


## Scars on top of the base silhouette so a returning individual is recognisable.
static func apply_scars(d: Dictionary, scars: Array) -> void:
	var root: Node3D = d.get("scar_root")
	if root:
		root.queue_free()
	root = Node3D.new()
	(d["torso"] as Node3D).add_child(root)
	d["scar_root"] = root
	for e in d["eyes"]:
		(e as Node3D).visible = true
	for s in scars:
		match s:
			"wound":
				Geo.box(root, Vector3(0.06, 0.45, 0.02), Vector3(0.12, 0.6, -0.22), Geo.mat(Color(0.5, 0.12, 0.1), 0.4, Color(0.35, 0.05, 0.03), 0.6), 0, 0.0, Vector3(0, 0, 0.5))
			"blind":
				if not d["eyes"].is_empty():
					var eye: Node3D = d["eyes"][0]
					eye.visible = false
					Geo.sphere(d["head"], 0.035, eye.position, Geo.mat(Color(0.8, 0.82, 0.8), 0.2), Vector3.ONE, false).reparent(root, true)
			"lantern":
				# Carries a captured player's dropped lantern, still glowing faintly.
				var arm: Node3D = d["arm_l"]
				var lan := Node3D.new()
				arm.add_child(lan)
				lan.position = Vector3(0, -1.0, -0.2)
				Geo.box(lan, Vector3(0.08, 0.12, 0.08), Vector3.ZERO, Geo.mat(Color(0.9, 0.7, 0.4), 0.3, Color(1.0, 0.65, 0.3), 0.8), 0)
				var glow := OmniLight3D.new()
				glow.light_color = Color(1.0, 0.7, 0.4)
				glow.omni_range = 2.5
				glow.light_energy = 0.35
				lan.add_child(glow)
				root.tree_exiting.connect(lan.queue_free)
	var limp := scars.has("limp")
	(d["leg_r"] as Node3D).scale = Vector3(1, 0.86 if limp else 1.0, 1)


# ------------------------------------------------------------------ tracks

static var _track_mats: Dictionary = {}
static var _track_meshes: Dictionary = {}


## A footprint / drag mark mesh and material per type (read at dawn as evidence).
static func track(ctype: String) -> Array:
	if not _track_meshes.has(ctype):
		var pm := PlaneMesh.new()
		match ctype:
			"listener": pm.size = Vector2(0.32, 0.3)
			"digger": pm.size = Vector2(0.55, 1.2)
			"climber": pm.size = Vector2(0.12, 0.3)
			_: pm.size = Vector2(0.17, 0.42)
		_track_meshes[ctype] = pm
		var m := StandardMaterial3D.new()
		m.albedo_color = {"listener": Color(0.1, 0.08, 0.06, 0.75), "digger": Color(0.16, 0.1, 0.05, 0.85),
			"climber": Color(0.05, 0.06, 0.05, 0.8)}.get(ctype, Color(0.04, 0.03, 0.03, 0.8))
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 1.0
		_track_mats[ctype] = m
	return [_track_meshes[ctype], _track_mats[ctype]]


static func _limb(parent: Node3D, origin: Vector3, length: float, radius: float, m: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = origin
	parent.add_child(pivot)
	Geo.rod(pivot, Vector3.ZERO, Vector3(0, -length * 0.55, -0.05), radius, m)
	Geo.rod(pivot, Vector3(0, -length * 0.55, -0.05), Vector3(0, -length, -0.12), radius * 0.75, m)
	Geo.sphere(pivot, radius * 1.4, Vector3(0, -length, -0.14), m, Vector3(1, 0.6, 1.8))
	return pivot


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c
