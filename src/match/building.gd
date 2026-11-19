extends RefCounted
## Construction at fixed slots (LOWLIGHT_ISLAND.md §7): ladders on any tree, platforms on
## sturdy trees, screens on platform edges, rope exits to a checked landing, low walls in
## caves. The host owns `builds`; every peer realises the same pieces from it.
## Pieces that delay a creature show intact / damaged / broken; repairs cost less than
## building again. Building takes a few seconds and makes noise.

const D = preload("res://src/core/defs.gd")
const Geo = preload("res://src/world/geo.gd")

const COST := {"ladder": 2, "deck": 3, "screen": 1, "rope": 2, "wall": 2}
const HP := {"deck": 100.0, "screen": 60.0, "wall": 80.0}
const LABEL := {"ladder": "a ladder", "deck": "a platform", "screen": "a screen", "rope": "a rope exit", "wall": "a low wall"}
const SIDES := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]

var m: Node = null
var builds: Dictionary = {}      # key -> {kind, tree, cave, side, hp}
var jobs: Dictionary = {}        # host: peer -> {key, kind, t, pos, repair}
var _nodes: Dictionary = {}      # key -> Node3D
var _bodies: Dictionary = {}     # key -> StaticBody3D (for light leaks)
var _noise_t := 0.0


func setup(p_match: Node) -> void:
	m = p_match


# ------------------------------------------------------------------ choosing what V does here

## The build or repair V would do for this player right now, or {}.
func option(p: Node) -> Dictionary:
	var w: Node = m.world
	if p.mode == D.Mode.NORMAL and p.tree_id >= 0:
		var t: Dictionary = w.tree_by_id(p.tree_id)
		if t.get("deck", false):
			var dk := "deck:%d" % t["id"]
			if builds.has(dk) and builds[dk]["hp"] < HP["deck"]:
				return {"key": dk, "kind": "deck", "repair": true, "pos": p.global_position}
			if not t["rope"] and t.get("rope_land", Vector3.INF) != Vector3.INF:
				return {"key": "rope:%d" % t["id"], "kind": "rope", "repair": false, "pos": p.global_position}
			var side := _facing_side(p)
			var sk := "screen:%d:%d" % [t["id"], side]
			if builds.has(sk):
				if builds[sk]["hp"] < HP["screen"]:
					return {"key": sk, "kind": "screen", "repair": true, "pos": p.global_position}
			else:
				return {"key": sk, "kind": "screen", "repair": false, "pos": p.global_position, "side": side}
		return {}
	if p.mode == D.Mode.PERCHED and p.perch == "canopy":
		var t2: Dictionary = w.tree_by_id(p.tree_id)
		if t2.get("sturdy", false) and not t2.get("deck", false) and not builds.has("deck:%d" % t2["id"]):
			return {"key": "deck:%d" % t2["id"], "kind": "deck", "repair": false, "pos": p.global_position}
		return {}
	if p.mode != D.Mode.NORMAL:
		return {}
	# Cave: the inner low wall.
	if p.cave_id >= 0:
		var wk := "wall:%d" % p.cave_id
		if builds.has(wk):
			if builds[wk]["hp"] < HP["wall"]:
				return {"key": wk, "kind": "wall", "repair": true, "pos": p.global_position}
		else:
			return {"key": wk, "kind": "wall", "repair": false, "pos": p.global_position}
		return {}
	# At a trunk: a ladder.
	for t3 in w.trees:
		var base: Vector3 = t3["pos"]
		if Vector2(p.global_position.x - base.x, p.global_position.z - base.z).length() - t3["trunk_r"] < 1.4 and p.global_position.y - base.y < 1.5:
			if not t3["ladder"]:
				return {"key": "ladder:%d" % t3["id"], "kind": "ladder", "repair": false, "pos": p.global_position}
			break
	return {}


func _facing_side(p: Node) -> int:
	var f: Vector3 = p.look_dir()
	var best := 0
	var best_d := -INF
	for i in 4:
		var d: float = f.dot(SIDES[i])
		if d > best_d:
			best_d = d
			best = i
	return best


func cost(opt: Dictionary) -> int:
	if opt.is_empty():
		return 0
	if opt["repair"]:
		return 1
	return COST[opt["kind"]]


func prompt(p: Node) -> String:
	var opt := option(p)
	if opt.is_empty():
		return ""
	var what: String = LABEL[opt["kind"]]
	if opt["repair"]:
		return "[V] Repair %s (1 wood)" % what
	return "[V] Build %s (%d wood)" % [what, cost(opt)]


# ------------------------------------------------------------------ host

## V pressed. Returns true if a build job started.
func start(p: Node) -> bool:
	var opt := option(p)
	if opt.is_empty():
		return false
	var c := cost(opt)
	if p.wood < c:
		m.notify(p, "You need %d wood for %s." % [c, LABEL[opt["kind"]]])
		return true
	p.wood -= c
	opt["t"] = 0.0
	opt["cost"] = c
	jobs[p.peer_id] = opt
	return true


func tick(delta: float) -> void:
	_noise_t -= delta
	for pid in jobs.keys():
		var job: Dictionary = jobs[pid]
		var p: Node = m.players.get(pid)
		if p == null or p.mode == D.Mode.DOWNED or p.global_position.distance_to(job["pos"]) > 2.5:
			if p:
				p.wood += job["cost"]   # abandoned: materials back
				m.notify(p, "Building interrupted.")
			jobs.erase(pid)
			continue
		job["t"] += delta / Tuning.build_time
		if _noise_t <= 0.0:
			_noise_t = 0.7
			m.emit_sound(job["pos"], Tuning.noise_build, "building", {"peer": pid})
			m.emit_cue("hammer", job["pos"])
		if job["t"] >= 1.0:
			jobs.erase(pid)
			_finish(p, job)


func _finish(p: Node, job: Dictionary) -> void:
	var key: String = job["key"]
	if job["repair"]:
		var b: Dictionary = builds[key]
		b["hp"] = minf(HP[b["kind"]], b["hp"] + Tuning.repair_hp)
		_realize(key)
		return
	var parts := key.split(":")
	var b2 := {"kind": job["kind"], "hp": HP.get(job["kind"], 1.0)}
	if job["kind"] == "wall":
		b2["cave"] = int(parts[1])
	else:
		b2["tree"] = int(parts[1])
	if job["kind"] == "screen":
		b2["side"] = int(parts[2])
	builds[key] = b2
	_realize(key)
	if job["kind"] == "deck":
		# Standing on the new platform rather than clinging to the canopy.
		var t: Dictionary = m.world.tree_by_id(b2["tree"])
		p.mode = D.Mode.NORMAL
		p.perch = ""
		var dir := Vector3(p.global_position.x - t["pos"].x, 0, p.global_position.z - t["pos"].z).normalized()
		p.global_position = t["pos"] + dir * (t["trunk_r"] + 0.7) + Vector3(0, t["deck_h"] + 0.05, 0)


## Creatures shaking a platform or tearing at a wall.
func damage(key: String, amount: float) -> void:
	if not builds.has(key):
		return
	var b: Dictionary = builds[key]
	b["hp"] = maxf(0.0, b["hp"] - amount)
	if b["hp"] <= 0.0:
		builds.erase(key)
		_unrealize(key)
		m.emit_cue("collapse", _anchor(key))
		if b["kind"] == "deck":
			# A broken platform drops whoever was on it (and takes its screens and rope).
			for k in builds.keys():
				if k.begins_with("screen:%d:" % b["tree"]) or k == "rope:%d" % b["tree"]:
					builds.erase(k)
					_unrealize(k)
			var t: Dictionary = m.world.tree_by_id(b["tree"])
			for p in m.players.values():
				if p.tree_id == b["tree"] and p.mode == D.Mode.NORMAL:
					var a := randf() * TAU
					p.global_position = t["pos"] + Vector3(cos(a), 0, sin(a)) * (t["trunk_r"] + 1.0) + Vector3(0, 0.1, 0)
					p.tree_id = -1
	else:
		_realize(key)


func shake(tree_id: int, strength: float) -> void:
	damage("deck:%d" % tree_id, strength)
	for i in 4:
		damage("screen:%d:%d" % [tree_id, i], strength * 0.6)


## A torn screen lets light through (its body still blocks sight of a crouched body).
func leaks_light(collider: Object) -> bool:
	for key in _bodies:
		if _bodies[key] == collider and builds.has(key):
			return builds[key]["hp"] < HP.get(builds[key]["kind"], 1.0) * 0.6
	return false


# ------------------------------------------------------------------ replication

func serialize() -> Dictionary:
	return builds


func apply_remote(d: Dictionary) -> void:
	for key in builds.keys():
		if not d.has(key):
			builds.erase(key)
			_unrealize(key)
	for key in d:
		var changed: bool = not builds.has(key) or builds[key]["hp"] != d[key]["hp"]
		builds[key] = d[key]
		if changed:
			_realize(key)


# ------------------------------------------------------------------ realisation (every peer)

func _anchor(key: String) -> Vector3:
	var parts := key.split(":")
	if parts[0] == "wall":
		return m.world.caves[int(parts[1])]["inside_point"]
	var t: Dictionary = m.world.tree_by_id(int(parts[1]))
	return t["pos"] + Vector3(0, t.get("deck_h", 3.0), 0)


func _stage(b: Dictionary) -> String:
	var full: float = HP.get(b["kind"], 1.0)
	return "intact" if b["hp"] >= full * 0.6 else "damaged"


func _realize(key: String) -> void:
	_unrealize(key, false)
	var b: Dictionary = builds[key]
	var w: Node = m.world
	var root := Node3D.new()
	root.name = "Build_" + key.replace(":", "_")
	w.add_child(root)
	_nodes[key] = root
	var damaged := _stage(b) == "damaged"
	var wood := Geo.mat(Color(0.36, 0.26, 0.16) if damaged else Color(0.5, 0.38, 0.24))
	var dark := Geo.mat(Color(0.27, 0.2, 0.13))
	match b["kind"]:
		"ladder":
			var t: Dictionary = w.tree_by_id(b["tree"])
			t["ladder"] = true
			var base: Vector3 = t["pos"]
			var out := Vector3(1, 0, 0).rotated(Vector3.UP, float(t["id"]) * 1.7)
			var side := out.cross(Vector3.UP).normalized() * 0.22
			var lb: Vector3 = base + out * (t["trunk_r"] + 0.1)
			var top: float = t["canopy_h"]
			Geo.rod(root, lb + side, lb + side + Vector3(0, top, 0), 0.035, wood)
			Geo.rod(root, lb - side, lb - side + Vector3(0, top, 0), 0.035, wood)
			var rung := 0.35
			while rung < top:
				Geo.rod(root, lb + side + Vector3(0, rung, 0), lb - side + Vector3(0, rung, 0), 0.025, wood)
				rung += 0.4
		"deck":
			var t2: Dictionary = w.tree_by_id(b["tree"])
			t2["deck"] = true
			t2["deck_h"] = t2["canopy_h"] - 0.3
			t2["deck_half"] = 1.4
			var dh: float = t2["deck_h"]
			var tilt := Vector3(0.06, 0, 0.04) if damaged else Vector3.ZERO
			var body := Geo.box(root, Vector3(2.8, 0.15, 2.8), t2["pos"] + Vector3(0, dh - 0.075, 0), wood, D.L_WORLD | D.L_SIGHT, 0.0, tilt)
			_bodies[key] = body
			for i in 4:
				var a := i * PI * 0.5
				Geo.rod(root, t2["pos"] + Vector3(0, dh - 0.1, 0), t2["pos"] + Vector3(cos(a), 0, sin(a)) * 1.8 + Vector3(0, dh - 1.5, 0), 0.06, dark)
			if not _has_interactable("deck_down", t2["id"]):
				w.interactables.append({"id": w.interactables.size(), "kind": "deck_down", "pos": t2["pos"] + Vector3(0, dh + 1.0, 0), "tree": t2["id"], "label": "trunk"})
		"rope":
			var t3: Dictionary = w.tree_by_id(b["tree"])
			var land: Vector3 = t3["rope_land"]
			var dir := Vector3(land.x - t3["pos"].x, 0, land.z - t3["pos"].z).normalized()
			t3["rope"] = true
			t3["rope_top"] = t3["pos"] + dir * 1.3 + Vector3(0, t3["deck_h"], 0)
			Geo.rod(root, t3["rope_top"] + Vector3(0, 0.4, 0), land + Vector3(0, 0.05, 0), 0.03, Geo.mat(Color(0.6, 0.52, 0.36)))
			Geo.box(root, Vector3(0.3, 0.15, 0.3), land + Vector3(0, 0.07, 0), dark, 0)
			if not _has_interactable("rope", t3["id"]):
				w.interactables.append({"id": w.interactables.size(), "kind": "rope", "pos": t3["rope_top"] + Vector3(0, 0.6, 0), "tree": t3["id"], "label": "rope"})
		"screen":
			var t4: Dictionary = w.tree_by_id(b["tree"])
			var s: Vector3 = SIDES[int(b["side"])]
			var center: Vector3 = t4["pos"] + s * 1.4 + Vector3(0, t4["deck_h"] + 0.65, 0)
			var yaw := atan2(s.x, s.z)
			var size := Vector3(2.8, 1.3, 0.06)
			if damaged:
				# Torn: visible gaps and a sag. Light leaks through (see leaks_light).
				for i in 5:
					Geo.box(root, Vector3(0.4, 1.3 - (i % 2) * 0.4, 0.06), center + Vector3(0, -(i % 2) * 0.2, 0) + Basis(Vector3.UP, yaw) * Vector3(-1.1 + i * 0.55, 0, 0), wood, 0, yaw)
				var shape := BoxShape3D.new()
				shape.size = size
				_bodies[key] = Geo.static_body(root, shape, Transform3D(Basis(Vector3.UP, yaw), center), D.L_SIGHT)
			else:
				_bodies[key] = Geo.box(root, size, center, Geo.mat(Color(0.32, 0.36, 0.22)), D.L_SIGHT | D.L_WORLD, yaw)
		"wall":
			var cave: Dictionary = w.caves[b["cave"]]
			var xf: Transform3D = cave["xform"]
			var h := 1.1 if not damaged else 0.8
			var body2 := Geo.box(root, Vector3(4.0, h, 0.2), xf * Vector3(-0.6, h * 0.5, -2.2), wood, D.L_WORLD | D.L_SIGHT, int(cave["facing"]) * PI * 0.5)
			_bodies[key] = body2


func _unrealize(key: String, reset_tree: bool = true) -> void:
	if _nodes.has(key):
		(_nodes[key] as Node).queue_free()
		_nodes.erase(key)
	_bodies.erase(key)
	if not reset_tree:
		return
	var parts := key.split(":")
	if parts[0] == "wall":
		return
	var t: Dictionary = m.world.tree_by_id(int(parts[1]))
	match parts[0]:
		"ladder": t["ladder"] = false
		"deck": t["deck"] = false
		"rope": t["rope"] = false


func _has_interactable(kind: String, tree: int) -> bool:
	for it in m.world.interactables:
		if it["kind"] == kind and it.get("tree", -1) == tree:
			return true
	return false
