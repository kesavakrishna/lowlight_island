extends CharacterBody3D
## A creature individual. The host runs the brain (`server_tick`); clients interpolate
## position / state and animate the silhouette.
##
## Shared behavior core for every type: patrol -> investigate -> search -> chase / climb /
## breach, plus hold (ambush / freeze / watching an exit), drag (a downed player toward a
## burrow) and recoil (shoved or blinded). Types differ only through the sense and ability
## flags in Tuning.creature_types; personality (creature_mind.gd) weights the choices and
## never changes what it can perceive.

const D = preload("res://src/core/defs.gd")
const Geo = preload("res://src/world/geo.gd")
const Mind = preload("res://src/creature/creature_mind.gd")
const Body = preload("res://src/creature/creature_body.gd")

var cid := 0
var ctype := "stalker"
var is_server := false
var match_ref: Node = null      # match.gd (untyped to avoid a preload cycle)
var world: Node = null
var stats: Dictionary = {}
var mind: Mind = Mind.new()
var home := Vector3.ZERO        # its burrow

# ---- brain state (host)
var state: int = D.CState.DORMANT
var state_time := 0.0
var reason := "asleep in the burrow"
var night := 1
var target_peer := -1
var awareness: Dictionary = {}  # peer -> 0..1.5
var last_known := Vector3.ZERO
var last_seen_t := -100.0
var lost_in_cover := ""
var investigate_pos := Vector3.ZERO
var investigate_priority := 0.0
var investigate_kind := ""
var search_spots: Array[Vector3] = []
var search_end := 0.0
var search_kind := ""
var look_timer := 0.0
var pause_time := 0.0
var commit_tree := -1
var climbing := false
var climb_progress := 0.0
var climb_base := Vector3.ZERO
var tree_timer := 0.0
var attack_cd := 0.0
var breach_timer := 0.0
var cave_suspicion := 0.0
var suspect_cave := -1
var breach_cave := 0
var linger_timer := 0.0
var linger_victim := -1
var drag_victim := -1
var drag_pulling := false
var hold_until := 0.0
var hold_face := Vector3.ZERO
var hold_next: Dictionary = {}
var feint_pos := Vector3.INF
var recoil_until := 0.0
var immune_until := 0.0
var blind_timers: Dictionary = {}
var trace_seen: Dictionary = {}
var trace_cd := 0.0
var canopy_cd := 0.0
var patrol_target := Vector3.INF
var cue_timer := 0.0
var light_cd := 0.0
var path := PackedVector3Array()
var path_i := 0
var path_goal := Vector3.INF
var repath_timer := 0.0
var stuck_timer := 0.0
var move_speed := 0.0
var yaw := 0.0
var log_ai := false
var dev_statue := false           # --dev-lineup: stands still and senses nothing
var leash := Vector3.INF          # dawn: stay in the shade near this point
var leash_r := 14.0
var underground := false          # diggers travel below soft ground
var _rng := RandomNumberGenerator.new()

# ---- replicated / visual
var awake := false
var scars: Array = []
var snaps: Array = []
var debug_text := ""
var _body: Dictionary = {}
var _shown_scars := []
var _ripple: Node3D
var _debug_label: Label3D
var _anim_phase := 0.0
var _last_vis_pos := Vector3.ZERO
var _step_timer := 0.0
var _vis_speed := 0.0
var _track_dist := 0.0
var _tracks: Array = []
var _rumble_t := 0.0


func setup(p_id: int, p_type: String, p_server: bool, p_match: Node, p_world: Node, p_seed: int = 0) -> void:
	cid = p_id
	ctype = p_type
	is_server = p_server
	match_ref = p_match
	world = p_world
	name = "C%d" % p_id
	_rng.seed = p_seed * 7919 + p_id * 977 + 13
	mind.roll(_rng)
	stats = Tuning.creature_stats(ctype, 1)


func _ready() -> void:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 2.1 if ctype != "digger" else 1.3
	var cs := CollisionShape3D.new()
	cs.shape = cap
	cs.position = Vector3(0, cap.height * 0.5, 0)
	add_child(cs)
	collision_layer = 0
	collision_mask = D.L_WORLD if is_server else 0
	_body = Body.build(ctype, self)
	Body.apply_scars(_body, scars)
	_ripple = Node3D.new()
	add_child(_ripple)
	for i in 5:
		Geo.sphere(_ripple, 0.35, Vector3(0, 0.05, i * 0.45), Geo.mat(Color(0.2, 0.14, 0.09)), Vector3(1.2, 0.35, 1.0), false)
	_ripple.visible = false
	_debug_label = Label3D.new()
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_label.no_depth_test = true
	_debug_label.font_size = 22
	_debug_label.pixel_size = 0.005
	_debug_label.modulate = Color(1, 0.85, 0.4)
	_debug_label.position = Vector3(0, 3.0, 0)
	_debug_label.visible = false
	add_child(_debug_label)
	_set_awake(false)


func flag(key: String) -> bool:
	return bool(stats.get(key, false))


# ================================================================== host: lifecycle and hooks

func wake(p_night: int, at: Vector3) -> void:
	night = p_night
	leash = Vector3.INF
	stats = Tuning.creature_stats(ctype, night)
	if mind.scars.has("limp"):
		for k in ["patrol_speed", "investigate_speed", "chase_speed"]:
			stats[k] *= 0.9
	mind.fade(night)
	home = at
	global_position = at
	awareness.clear()
	climbing = false
	underground = false
	drag_victim = -1
	_set_awake(true)
	_set_state(D.CState.PATROL, "emerged at dusk")
	patrol_target = Vector3.INF
	# A door it couldn't break last time: it comes back to that cave first.
	if mind.knows("cave"):
		var c: int = int(mind.counter_arg("cave"))
		if c >= 0 and c < world.caves.size():
			patrol_target = world.caves[c]["door_point"]
			suspect_cave = c
			cave_suspicion = 0.5
			reason = "returning to the cave it couldn't break"
	match_ref.emit_cue("ccall", at + Vector3(0, 1, 0), {"type": ctype})


## Dawn with the boat in: linger in a shaded stretch of the route to the dock.
func lurk(point: Vector3) -> void:
	leash = point
	patrol_target = Vector3.INF
	_end_climb()
	_set_state(D.CState.PATROL, "lingering in the shade by the dock route")


func go_home() -> void:
	leash = Vector3.INF
	if state == D.CState.DORMANT:
		return
	if state == D.CState.BREACH and world.door_blocks(breach_cave):
		if mind.learn("cave", night, breach_cave):
			_log("learned: the cave door held")
	if state == D.CState.DRAG and drag_pulling:
		return   # finishes the drag, then goes under
	_end_climb()
	_release_drag()
	_set_state(D.CState.RETURN, "dawn: returning to the burrow")


func _end_climb() -> void:
	if climbing or state == D.CState.CLIMB or state == D.CState.TREE_ATTACK or state == D.CState.CLIMB_DOWN:
		climbing = false
		global_position.y = world.ground_y(global_position)


## A shove: brief recoil, a wound, a grudge. Returns false if it can't be shoved yet.
func on_shoved(p: Node) -> bool:
	if not awake or _now() < immune_until or state == D.CState.DORMANT:
		return false
	immune_until = _now() + Tuning.shove_immunity
	_release_drag()
	_end_climb()
	if not mind.scar("wound"):
		mind.scar("limp")
	scars = mind.scars.duplicate()
	mind.add_grudge(p.peer_id, 3.0, "shoved it")
	var away: Vector3 = global_position - p.global_position
	away.y = 0
	velocity = away.normalized() * 4.0
	recoil_until = _now() + Tuning.recoil_time
	target_peer = p.peer_id
	last_known = p.global_position
	_set_state(D.CState.RECOIL, "shoved by %s" % p.display_name)
	return true


## A player roped down out of the tree it was climbing: next time it watches the landing.
func notice_rope(tree_id: int, p: Node) -> void:
	if (state == D.CState.CLIMB or state == D.CState.TREE_ATTACK) and commit_tree == tree_id:
		if mind.learn("rope", night):
			_log("learned: they rope down")
		mind.add_grudge(p.peer_id, 1.0, "escaped it")


func hold_at(point: Vector3, face: Vector3, seconds: float, why: String, next: Dictionary = {}) -> void:
	if state == D.CState.DORMANT:
		return
	_end_climb()
	_release_drag()
	hold_face = face
	hold_until = _now() + seconds
	hold_next = next
	hold_next["at"] = point
	_set_state(D.CState.HOLD, why)


func is_calm() -> bool:
	return state == D.CState.PATROL or state == D.CState.INVESTIGATE or state == D.CState.SEARCH or state == D.CState.HOLD


func _set_awake(a: bool) -> void:
	awake = a
	visible = a
	collision_layer = D.L_CREATURE if (a and is_server) else 0


func _set_state(s: int, why: String) -> void:
	if log_ai and (s != state or why != reason):
		print("[ai] t=%.1f %s#%d %s -> %s : %s" % [match_ref.match_time, ctype, cid, D.CSTATE_NAMES[state], D.CSTATE_NAMES[s], why])
	if s != state:
		state = s
		state_time = 0.0
		look_timer = 0.0
		pause_time = 0.0
		path = PackedVector3Array()
		path_goal = Vector3.INF
	reason = why


func _log(text: String) -> void:
	if log_ai:
		print("[ai] %s#%d %s" % [ctype, cid, text])


func server_tick(delta: float) -> void:
	if state == D.CState.DORMANT or dev_statue:
		return
	state_time += delta
	attack_cd -= delta
	light_cd -= delta
	trace_cd -= delta
	canopy_cd -= delta
	if state != D.CState.LINGER and state != D.CState.RETURN and state != D.CState.RECOIL and not (state == D.CState.DRAG and drag_pulling):
		_perceive(delta)
		_hear()
	match state:
		D.CState.PATROL: _st_patrol(delta)
		D.CState.INVESTIGATE: _st_investigate(delta)
		D.CState.SEARCH: _st_search(delta)
		D.CState.CHASE: _st_chase(delta)
		D.CState.CLIMB: _st_climb(delta)
		D.CState.TREE_ATTACK: _st_tree_attack(delta)
		D.CState.CLIMB_DOWN: _st_climb_down(delta)
		D.CState.BREACH: _st_breach(delta)
		D.CState.LINGER: _st_linger(delta)
		D.CState.RETURN: _st_return(delta)
		D.CState.HOLD: _st_hold(delta)
		D.CState.DRAG: _st_drag(delta)
		D.CState.RECOIL: _st_recoil(delta)
	if not _kinematic():
		_move(delta)
	rotation.y = yaw
	debug_text = _make_debug_text()


func _kinematic() -> bool:
	return climbing or state == D.CState.TREE_ATTACK or state == D.CState.CLIMB_DOWN or state == D.CState.DORMANT


func _now() -> float:
	return match_ref.match_time


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func eye_pos() -> Vector3:
	return global_position + Vector3(0, stats["eye_height"], 0)


func _tricks(min_night: int) -> bool:
	return night >= min_night


# ------------------------------------------------------------------ perception

func _perceive(delta: float) -> void:
	var now := _now()
	var best: Node = null
	var best_score := 0.0
	var best_aw := 0.0
	var grudge := mind.grudge_peer()
	var downed_seen: Node = null
	for p in match_ref.players.values():
		var pid: int = p.peer_id
		if p.mode == D.Mode.ESCAPED or p.mode == D.Mode.CAPTURED:
			continue
		if p.mode == D.Mode.DOWNED:
			awareness[pid] = 0.0
			if p.dragged_by < 0 and downed_seen == null and global_position.distance_to(p.global_position) < 14.0 and _senses(p):
				downed_seen = p
			continue
		var aw: float = awareness.get(pid, 0.0)
		var vis_amt := visibility_of(p)
		if vis_amt > 0.0:
			var dist := global_position.distance_to(p.global_position)
			var close := 1.0 + maxf(0.0, (8.0 - dist) / 8.0) * 1.5
			aw = minf(aw + stats["awareness_rate"] * vis_amt * close * delta, 1.5)
			if pid == target_peer:
				last_known = p.global_position
				last_seen_t = now
			# Prefer its grudge target and whoever's nerve is breaking.
			var score: float = aw + (0.35 if pid == grudge else 0.0) + (1.0 - p.nerve / Tuning.nerve_max) * 0.25
			if score > best_score:
				best_score = score
				best_aw = aw
				best = p
		else:
			aw = maxf(0.0, aw - 0.3 * delta)
		awareness[pid] = aw
		_check_blinding(p, delta)
		# The light itself is a cue, visible further than the body.
		if flag("light") and p.lantern_open and light_cd <= 0.0 and not underground and _light_visible(p):
			light_cd = 1.0
			if is_calm():
				_react_to_light(p.eye_position(), "saw a light")
	# The broadcast lights up the shed: a beacon seen from far across the island.
	var obj: RefCounted = match_ref.objectives
	if flag("light") and obj and obj.broadcast_active and light_cd <= 0.0 and leash == Vector3.INF:
		var bench: Vector3 = world.radio_bench
		if global_position.distance_to(bench) < stats["light_sight_range"] * Tuning.broadcast_light_mult:
			light_cd = 2.0
			if is_calm():
				_investigate(bench, 0.9, "drawn to the broadcast")
	if best == null:
		if downed_seen and is_calm():
			_start_drag(downed_seen, "found %s lying in the dark" % downed_seen.display_name)
			return
		_check_traces()
		_check_canopies()
		return
	if best.tree_id >= 0 and best_aw >= 0.5 and (is_calm() or state == D.CState.CHASE):
		_start_climb(best.tree_id, "watched %s in a tree" % best.display_name)
		return
	if is_calm() and best_aw >= mind.chase_threshold():
		_start_chase(best, "spotted %s" % best.display_name if flag("sight") else "felt %s through the ground" % best.display_name)
	elif is_calm() and best_aw >= 0.35 and state != D.CState.HOLD:
		_investigate(best.global_position, 0.6, "glimpsed movement" if flag("sight") else "felt movement")


## Can it sense a (downed) player at all right now? Used for finding the fallen.
func _senses(p: Node) -> bool:
	if flag("sight") and not underground:
		return ray_clear(eye_pos(), p.global_position + Vector3(0, 0.3, 0))
	return global_position.distance_to(p.global_position) < maxf(stats["feel_range"], 3.0)


## 0 when undetected, otherwise a 0.2..1 strength. Pure gameplay rules + raycasts;
## graphics settings never affect it.
func visibility_of(p: Node) -> float:
	var to: Vector3 = p.global_position - global_position
	var dist := to.length()
	# Blind hunters feel movement through the ground instead of seeing it.
	if not flag("sight") or underground:
		var feel: float = stats["feel_range"]
		if underground and _ground_soft(p.global_position):
			feel = maxf(feel, 3.5)
		if dist < feel and p.moving and p.stance != D.Stance.PRONE and p.mode != D.Mode.CLIMBING and p.mode != D.Mode.PERCHED:
			return 1.0
		return 0.0
	var eye := eye_pos()
	var tp: Vector3 = p.global_position
	var day: float = match_ref.daylight()
	var rng := lerpf(stats["sight_range_dark"], stats["sight_range_day"], day)
	if leash != Vector3.INF:
		rng = minf(rng, stats["sight_range_dark"] * 1.5)   # watching from the shade, not the open
	if p.lantern_open:
		rng = maxf(rng, stats["lit_sight_range"])
	var mult := 1.0
	match p.stance:
		D.Stance.CROUCH: mult = 0.7
		D.Stance.PRONE: mult = 0.4
	if p.moving:
		mult *= 1.2
	if p.sprinting:
		mult *= 1.4
	if p.mode == D.Mode.CLIMBING:
		mult *= 1.3
	rng *= mult
	if dist > rng:
		return 0.0
	if dist > 2.5:
		var flat := Vector3(to.x, 0, to.z).normalized()
		if forward().dot(flat) < cos(deg_to_rad(stats["fov_deg"] * 0.5)):
			return 0.0
	if not p.lantern_open:
		match p.cover:
			"grass":
				if p.stance != D.Stance.STAND:
					var reveal := Tuning.grass_reveal_prone if p.stance == D.Stance.PRONE else Tuning.grass_reveal_crouch
					if dist > reveal:
						return 0.0
			"bush":
				if not p.moving and p.stance != D.Stance.STAND and dist > Tuning.bush_reveal:
					return 0.0
			"canopy":
				if not p.moving and p.mode != D.Mode.CLIMBING and dist > 6.0:
					return 0.0
	for h in _exposure_points(p):
		if ray_clear(eye, h):
			return clampf(1.0 - dist / rng * 0.8, 0.2, 1.0)
	return 0.0


## Points on the player a creature could see: by stance, shifted by a lean so peeking
## around cover exposes the head that's peeking.
func _exposure_points(p: Node) -> Array:
	var base: Vector3 = p.global_position
	var heights: Array
	if p.mode == D.Mode.DOWNED or p.stance == D.Stance.PRONE:
		heights = [0.25]
	elif p.stance == D.Stance.CROUCH:
		heights = [1.0, 0.6]
	else:
		heights = [1.6, 1.1, 0.5]
	var out: Array = []
	var lean_off: Vector3 = p.lean_offset() if p.has_method("lean_offset") else Vector3.ZERO
	for h in heights:
		var w := clampf((h - 0.4) / 1.2, 0.0, 1.0)   # the head moves with a lean, the feet don't
		out.append(base + Vector3(0, h, 0) + lean_off * w)
	return out


func ray_clear(a: Vector3, b: Vector3, light_passes_damaged_door: bool = false) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(a, b, D.L_SIGHT)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return true
	if light_passes_damaged_door and _is_damaged_door(hit["collider"]):
		q.exclude = [hit["rid"]]
		return space.intersect_ray(q).is_empty()
	return false


func _is_damaged_door(collider: Object) -> bool:
	if match_ref.building and match_ref.building.leaks_light(collider):
		return true
	for c in world.caves:
		if collider == c["door_body"]:
			return c["door_hp"] < Tuning.door_damaged_below
	return false


func _light_visible(p: Node) -> bool:
	if match_ref.daylight() > 0.6:
		return false
	var lp: Vector3 = p.eye_position()
	if eye_pos().distance_to(lp) > stats["light_sight_range"]:
		return false
	return ray_clear(eye_pos(), lp, true)


## Bold ones go straight at a light; cautious ones close in, stop short and watch.
func _react_to_light(at: Vector3, why: String) -> void:
	if mind.boldness < -0.25 and global_position.distance_to(at) > 12.0:
		var short := at + (global_position - at).normalized() * 10.0
		hold_face = at
		_investigate(short, 0.7, why + "; circling closer")
		investigate_kind = "stalk_light"
		hold_next = {"kind": "investigate", "pos": at, "why": "closing on the light"}
	else:
		_investigate(at, 0.8 if mind.boldness > 0.25 else 0.7, why)


func _check_blinding(p: Node, delta: float) -> void:
	if not flag("sight") or not p.lantern_open or underground:
		blind_timers.erase(p.peer_id)
		return
	var eye := eye_pos()
	var d := eye.distance_to(p.eye_position())
	if d > 5.0 or p.look_dir().dot((eye - p.eye_position()).normalized()) < 0.94:
		blind_timers[p.peer_id] = maxf(0.0, blind_timers.get(p.peer_id, 0.0) - delta)
		return
	blind_timers[p.peer_id] = blind_timers.get(p.peer_id, 0.0) + delta
	if blind_timers[p.peer_id] >= Tuning.blind_time:
		blind_timers[p.peer_id] = 0.0
		mind.scar("blind")
		scars = mind.scars.duplicate()
		mind.add_grudge(p.peer_id, 2.0, "blinded it with light")
		recoil_until = _now() + 1.0
		_release_drag()
		target_peer = p.peer_id
		last_known = p.global_position
		_set_state(D.CState.RECOIL, "blinded by %s's lantern" % p.display_name)
		match_ref.emit_cue("shriek", eye, {"type": ctype})


## Fresh trails: places the crew keeps using build up evidence a passing patrol follows.
func _check_traces() -> void:
	if trace_cd > 0.0 or not is_calm() or state == D.CState.HOLD:
		return
	trace_cd = 1.0
	var spot: Vector3 = match_ref.trace_hotspot_near(global_position, 12.0)
	if spot == Vector3.INF:
		return
	var key := Vector2i(roundi(spot.x), roundi(spot.z))
	if _now() - trace_seen.get(key, -999.0) < 40.0:
		return
	trace_seen[key] = _now()
	_investigate(spot, 0.65, "found fresh trails")


## Climbers inspect trees someone is hiding in, even without seeing them.
func _check_canopies() -> void:
	if not flag("canopy_check") or canopy_cd > 0.0 or not is_calm():
		return
	canopy_cd = 1.0
	for p in match_ref.players.values():
		if p.tree_id < 0 or p.mode == D.Mode.DOWNED:
			continue
		var t: Dictionary = world.tree_by_id(p.tree_id)
		if t.is_empty():
			continue
		var hd := Vector2(global_position.x - t["pos"].x, global_position.z - t["pos"].z).length()
		if hd < 6.0 and _rng.randf() < 0.15 * (1.0 + mind.curiosity):
			_start_climb(p.tree_id, "checking the canopy")
			return


func _hear() -> void:
	for ev in match_ref.sound_events:
		if flag("soft_only") and ev.get("ground", "soil") != "soil" and ev["kind"] != "noisemaker" and ev["kind"] != "broadcast":
			continue   # vibration doesn't carry through rock, cave floors or trees
		var r: float = ev["radius"] * stats["hearing_mult"]
		if ev.get("muffled", false):
			r *= Tuning.cave_muffle
		var d := global_position.distance_to(ev["pos"])
		if d <= r:
			_on_sound(ev, d, r)


func _on_sound(ev: Dictionary, d: float, r: float) -> void:
	var kind: String = ev["kind"]
	var peer: int = ev.get("peer", -1)
	# Whatever it hears of its target keeps the chase going (all a blind hunter has).
	if peer >= 0 and peer == target_peer and state == D.CState.CHASE:
		last_known = ev["pos"]
		if not flag("sight") or underground:
			last_seen_t = _now()
		return
	match state:
		D.CState.CLIMB, D.CState.TREE_ATTACK, D.CState.CLIMB_DOWN, D.CState.BREACH, D.CState.LINGER, D.CState.RETURN, D.CState.RECOIL:
			return  # committed
		D.CState.DRAG:
			# A well-timed decoy can break a drag.
			if kind == "noisemaker" and drag_pulling and not mind.knows("decoy") and _rng.randf() < 0.6:
				_release_drag()
				_investigate(ev["pos"], 0.95, "dropped its prey for a noise")
				investigate_kind = "noisemaker"
			return
	if state == D.CState.CHASE and _now() - last_seen_t < 2.0:
		return  # a creature that still senses a player keeps pursuing
	# Blind hunters pin a player down from the sounds they make.
	if peer >= 0 and not flag("sight") and d < r * 0.7 and match_ref.players.has(peer):
		var p: Node = match_ref.players[peer]
		awareness[peer] = minf(awareness.get(peer, 0.0) + 0.55, 1.5)
		if awareness[peer] >= mind.chase_threshold() and is_calm():
			_start_chase(p, "heard %s up close" % p.display_name)
			last_known = ev["pos"]
			return
	if kind == "branch" and ev.has("tree") and flag("can_climb"):
		var t: Dictionary = world.tree_by_id(ev["tree"])
		if not t.is_empty() and state != D.CState.PATROL:
			var hd := Vector2(global_position.x - t["pos"].x, global_position.z - t["pos"].z).length()
			if hd < stats["tree_sense"]:
				if _tricks(Tuning.trick_freeze_night) and _rng.randf() < 0.35 and state != D.CState.HOLD:
					hold_at(global_position, t["pos"], _rng.randf_range(6.0, 11.0), "froze under the branches",
						{"kind": "climb", "tree": t["id"], "why": "branches shook overhead"})
					return
				_start_climb(t["id"], "branches shook overhead")
				return
	var c: int = ev.get("cave", -1)
	if c >= 0 and world.door_blocks(c):
		if c != suspect_cave:
			cave_suspicion = 0.0
		suspect_cave = c
		cave_suspicion += 0.7 if kind == "door" else 0.4
		var door_point: Vector3 = world.caves[c]["door_point"]
		var near_door := global_position.distance_to(door_point)
		if cave_suspicion >= 1.0 and near_door < 4.0:
			_start_breach(c, "heard them inside the cave")
			return
		if _tricks(Tuning.trick_freeze_night) and near_door < 14.0 and _rng.randf() < 0.35 and state != D.CState.HOLD:
			hold_at(global_position, door_point, _rng.randf_range(8.0, 14.0), "went still outside the cave",
				{"kind": "investigate", "pos": door_point, "why": "creeping to the cave door"})
			return
		_investigate(door_point, 0.8, "heard something inside the cave")
		return
	if leash != Vector3.INF and ev["pos"].distance_to(leash) > leash_r + 10.0:
		return   # won't leave the shade at dawn
	var pri := 0.5 + (1.0 - d / r) * 0.4 + mind.curiosity * 0.1
	if kind == "broadcast" or kind == "engine":
		pri = 0.95
	if kind == "noisemaker":
		if mind.knows("decoy"):
			if _rng.randf() < 0.7:
				return   # fooled before; ignores the rattle
			pri = 0.3
		else:
			pri = 0.95
	if state == D.CState.HOLD and pri < 0.9:
		return
	_investigate(ev["pos"], pri, "heard %s" % kind)
	investigate_kind = kind


# ------------------------------------------------------------------ transitions

func _investigate(pos: Vector3, pri: float, why: String) -> void:
	# Patient ones stick with what they're doing; impulsive ones switch readily.
	if state == D.CState.INVESTIGATE and pri < investigate_priority - 0.2 + 0.25 * mind.patience and state_time < 6.0:
		return
	investigate_pos = pos
	investigate_priority = pri
	investigate_kind = ""
	if state != D.CState.INVESTIGATE:
		_set_state(D.CState.INVESTIGATE, why)
	else:
		reason = why
		state_time = 0.0
		look_timer = 0.0


func _begin_search(center: Vector3, scale: float, why: String, kind: String = "") -> void:
	search_spots.clear()
	search_kind = kind
	search_spots.append(center)
	var near: Array = []
	for s in world.hide_spots:
		var d: float = s.distance_to(center)
		if d < 14.0 and d > 1.0:
			near.append([d, s])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(3, near.size()):
		search_spots.append(near[i][1])
	# Learned: they hide in grass -> rake the nearby patches.
	if mind.knows("grass"):
		for g in world.grass:
			var gc: Vector3 = g["center"]
			if gc.distance_to(center) < 16.0:
				var r: float = g["radius"]
				search_spots.push_front(gc + Vector3(r * 0.5, 0, 0))
				search_spots.push_front(gc + Vector3(-r * 0.5, 0, r * 0.3))
	# Learned: they rope down -> check rope landings first.
	if mind.knows("rope"):
		for t in world.trees:
			if t["rope_land"] != Vector3.INF and (t["rope_land"] as Vector3).distance_to(center) < 14.0:
				search_spots.push_front(t["rope_land"])
	var in_cid: int = world.cave_at(center + Vector3(0, 0.5, 0))
	if in_cid >= 0:
		search_spots.clear()
		for sp in world.caves[in_cid]["search_spots"]:
			search_spots.append(sp)
	search_end = _now() + stats["search_time"] * scale * mind.search_mult()
	_set_state(D.CState.SEARCH, why)
	match_ref.emit_cue("chitter", global_position)


func _start_chase(p: Node, why: String) -> void:
	target_peer = p.peer_id
	last_known = p.global_position
	last_seen_t = _now()
	feint_pos = Vector3.INF
	_set_state(D.CState.CHASE, why)
	match_ref.emit_cue("screech", global_position + Vector3(0, 1.8, 0), {"type": ctype})


func _start_climb(tree_id: int, why: String) -> void:
	var t: Dictionary = world.tree_by_id(tree_id)
	if t.is_empty():
		return
	if not flag("can_climb"):
		# Diggers can't climb: they wait below and circle the trunk.
		_begin_search(t["pos"] + Vector3(1.5, 0, 0), 1.2, "can't climb; waiting under the tree")
		return
	commit_tree = tree_id
	var dir := Vector3(global_position.x - t["pos"].x, 0, global_position.z - t["pos"].z)
	dir = Vector3(1, 0, 0) if dir.length() < 0.1 else dir.normalized()
	climb_base = t["pos"] + dir * (t["trunk_r"] + 0.6)
	climbing = false
	climb_progress = 0.0
	var land: Vector3 = t.get("rope_land", Vector3.INF)
	if mind.knows("rope") and land != Vector3.INF and state != D.CState.HOLD:
		# Learned: they rope down. Watch the landing first, then go up.
		hold_at(land, t["pos"], 7.0, "watching the rope landing", {"kind": "climb", "tree": tree_id, "why": why})
		return
	_set_state(D.CState.CLIMB, why)
	_recruit_exit(_tree_exit(t), t["pos"], "holding the ground under the tree")


func _tree_exit(t: Dictionary) -> Vector3:
	var land: Vector3 = t.get("rope_land", Vector3.INF)
	if land != Vector3.INF:
		return land
	var away := Vector3(t["pos"].x - global_position.x, 0, t["pos"].z - global_position.z).normalized()
	return t["pos"] + away * 4.0


func _start_breach(c: int, why: String) -> void:
	breach_cave = c
	cave_suspicion = 0.0
	breach_timer = 0.6
	_set_state(D.CState.BREACH, why)
	var cave: Dictionary = world.caves[c]
	_recruit_exit(cave["tunnel_exit"], cave["door_point"], "holding the cave's back way out")


## Flush and wait: on later nights one drives the crew out while another holds the exit.
func _recruit_exit(point: Vector3, face: Vector3, why: String) -> void:
	if _tricks(Tuning.trick_flush_night):
		match_ref.recruit_holder(self, point, face, why)


func _start_drag(p: Node, why: String) -> void:
	drag_victim = p.peer_id
	drag_pulling = false
	_set_state(D.CState.DRAG, why)


func _release_drag() -> void:
	if drag_victim >= 0:
		match_ref.release_drag(drag_victim)
	drag_victim = -1
	drag_pulling = false


func _nearest_burrow() -> Vector3:
	var best := home
	var best_d := INF
	for b in match_ref.burrow_list():
		var d: float = (b as Vector3).distance_to(global_position)
		if d < best_d:
			best_d = d
			best = b
	return best


# ------------------------------------------------------------------ states

func _st_patrol(delta: float) -> void:
	if patrol_target == Vector3.INF:
		_pick_patrol_target()
		return
	if _go(patrol_target, stats["patrol_speed"]):
		# Feigned retreat: walked away, now goes silent and doubles back.
		if feint_pos != Vector3.INF:
			var back := feint_pos
			feint_pos = Vector3.INF
			hold_at(global_position, back, _rng.randf_range(6.0, 9.0), "went quiet out of sight",
				{"kind": "investigate", "pos": back, "why": "doubled back"})
			return
		pause_time += delta
		_look_around(delta)
		if pause_time > 1.5 + _rng.randf() * 0.1:
			_pick_patrol_target()


func _pick_patrol_target() -> void:
	pause_time = 0.0
	if leash != Vector3.INF:
		var off := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(2.0, leash_r)
		patrol_target = leash + off
		reason = "lingering in the shade"
		return
	var pts: Array = world.patrol_points
	var choice: Vector3 = pts[_rng.randi() % pts.size()]
	var roll := _rng.randf()
	var grudge := mind.grudge_peer()
	if grudge >= 0 and match_ref.players.has(grudge) and roll < 0.5:
		choice = _closest_point(pts, match_ref.players[grudge].global_position, 6.0)
		reason = "hunting the one it holds a grudge against"
	elif roll < 0.45 and not match_ref.players.is_empty():
		# Weight toward the crew's general region so nights produce encounters.
		var ps: Array = match_ref.players.values()
		var p: Node = ps[_rng.randi() % ps.size()]
		choice = _closest_point(pts, p.global_position, 8.0)
		reason = "patrolling"
	elif _rng.randf() < mind.territorial * 0.6:
		choice = _closest_point(pts, home, 20.0)
		reason = "patrolling near its burrow"
	elif _rng.randf() < mind.curiosity * 0.4 and not world.hide_spots.is_empty():
		choice = world.hide_spots[_rng.randi() % world.hide_spots.size()]
		reason = "poking at a hiding place"
	else:
		reason = "patrolling"
	if choice.distance_to(global_position) < 3.0:
		choice = pts[(pts.find(choice) + 3) % pts.size()] if pts.has(choice) else pts[_rng.randi() % pts.size()]
	patrol_target = choice


func _closest_point(pts: Array, to: Vector3, jitter: float) -> Vector3:
	var best: Vector3 = pts[0]
	var best_d := INF
	for q in pts:
		var d: float = (q as Vector3).distance_to(to) + _rng.randf_range(0.0, jitter)
		if d < best_d:
			best_d = d
			best = q
	return best


func _st_investigate(delta: float) -> void:
	if _go(investigate_pos, stats["investigate_speed"]):
		if investigate_kind == "stalk_light" and not hold_next.is_empty():
			var nx := hold_next
			hold_next = {}
			hold_at(global_position, hold_face, _rng.randf_range(3.0, 5.0), "watching the light", nx)
			return
		look_timer += delta
		_look_around(delta)
		if look_timer > 3.0:
			if investigate_kind == "noisemaker":
				if mind.learn("decoy", night):
					_log("learned: the rattles are decoys")
			_begin_search(investigate_pos, 0.5, "nothing at the source; searching nearby")
	if state == D.CState.INVESTIGATE and state_time > 25.0:
		_set_state(D.CState.PATROL, "lost interest")


func _st_search(delta: float) -> void:
	if search_spots.is_empty() or _now() > search_end:
		cave_suspicion *= 0.5
		patrol_target = Vector3.INF
		# Feigned retreat: walk off as if giving up, then come back quietly.
		if search_kind == "lost" and _tricks(Tuning.trick_feint_night) and mind.patience > -0.3 and _rng.randf() < 0.6:
			var away := global_position - last_known
			away.y = 0
			away = (away.normalized() if away.length() > 0.5 else forward()) * 14.0
			var spot: Vector3 = world.grid.cell_to_world(world.grid.nearest_walkable(world.grid.world_to_cell(global_position + away)))
			spot.y = world.ground_y(spot)
			patrol_target = spot
			feint_pos = last_known
			_set_state(D.CState.PATROL, "gave up the search (or did it?)")
			return
		_set_state(D.CState.PATROL, "search came up empty")
		return
	if _go(search_spots[0], stats["investigate_speed"] * 0.85):
		look_timer += delta
		_look_around(delta)
		if look_timer > 1.8 * (1.0 + 0.3 * mind.patience):
			search_spots.pop_front()
			look_timer = 0.0


func _st_chase(_delta: float) -> void:
	var p: Node = match_ref.players.get(target_peer)
	if p == null or p.mode == D.Mode.DOWNED or p.mode == D.Mode.ESCAPED or p.mode == D.Mode.CAPTURED:
		patrol_target = Vector3.INF
		_set_state(D.CState.PATROL, "target gone")
		return
	var now := _now()
	var sensing := flag("sight") and not underground
	var fresh := 0.2 if sensing else 1.5
	var recent := now - last_seen_t < fresh
	if p.tree_id >= 0 and now - last_seen_t < 2.0:
		_start_climb(p.tree_id, "watched %s climb" % p.display_name)
		return
	if p.cave_id >= 0 and world.door_blocks(p.cave_id) and now - last_seen_t < 3.0:
		_start_breach(p.cave_id, "saw %s shut themselves in" % p.display_name)
		return
	var dist := global_position.distance_to(p.global_position)
	if recent and dist < stats["catch_range"] and absf(p.global_position.y - global_position.y) < 1.2 and not underground:
		match_ref.down_player(p, self)
		linger_victim = p.peer_id
		linger_timer = 0.0
		_set_state(D.CState.LINGER, "caught %s" % p.display_name)
		return
	var give_up := 1.2 if sensing else 3.5
	if now - last_seen_t > give_up:
		if p.cover == "grass" and mind.learn("grass", night):
			_log("learned: they hide in the grass")
		mind.add_grudge(p.peer_id, 1.0, "escaped it")
		_begin_search(last_known, 1.0, "lost %s" % p.display_name, "lost")
		return
	if leash != Vector3.INF and global_position.distance_to(leash) > leash_r + 14.0:
		patrol_target = Vector3.INF
		_set_state(D.CState.PATROL, "won't leave the shade")
		return
	# Blind hunters go where they last heard you, not where you are.
	_go(p.global_position if (recent and sensing) else last_known, stats["chase_speed"], 0.25)


func _st_climb(delta: float) -> void:
	var t: Dictionary = world.tree_by_id(commit_tree)
	if not climbing:
		if _go(climb_base, stats["chase_speed"]):
			climbing = true
			underground = false
			velocity = Vector3.ZERO
			cue_timer = 0.0
			reason = "climbing the trunk"
		return
	_face(t["pos"], delta)
	climb_progress = minf(1.0, climb_progress + delta / stats["climb_time"])
	global_position = Vector3(climb_base.x, climb_base.y + climb_progress * _canopy_y(t), climb_base.z)
	cue_timer -= delta
	if cue_timer <= 0.0:
		cue_timer = 0.7 if stats["climb_time"] > 5.0 else 0.4
		match_ref.emit_cue("scrape", global_position + Vector3(0, 1.0, 0), {"tree": commit_tree})
	if climb_progress >= 1.0:
		tree_timer = 0.0
		attack_cd = stats["tree_attack_cd"]
		_set_state(D.CState.TREE_ATTACK, "reached the canopy")


func _canopy_y(t: Dictionary) -> float:
	return t["deck_h"] if t["deck"] else t["canopy_h"] - 0.6


func _st_tree_attack(delta: float) -> void:
	tree_timer += delta
	cue_timer -= delta
	if cue_timer <= 0.0:
		cue_timer = 0.9 if ctype != "climber" else 0.5
		match_ref.emit_cue("deck_shake", global_position + Vector3(0, 1.0, 0), {"tree": commit_tree})
		match_ref.shake_platform(commit_tree, 8.0 if ctype == "climber" else 4.0)
	var victim: Node = null
	var best := INF
	for p in match_ref.players.values():
		if p.tree_id == commit_tree and p.mode != D.Mode.DOWNED and p.mode != D.Mode.ESCAPED:
			var d: float = p.global_position.distance_to(global_position)
			if d < best:
				best = d
				victim = p
	if victim == null:
		if tree_timer > 2.5:
			_set_state(D.CState.CLIMB_DOWN, "the canopy is empty")
		return
	_face(victim.global_position, delta)
	if attack_cd <= 0.0:
		attack_cd = stats["tree_attack_cd"]
		match_ref.down_player(victim, self)


func _st_climb_down(delta: float) -> void:
	var t: Dictionary = world.tree_by_id(commit_tree)
	climb_progress = maxf(0.0, climb_progress - delta / (stats["climb_time"] * 0.4))
	global_position = Vector3(climb_base.x, climb_base.y + climb_progress * _canopy_y(t), climb_base.z)
	if climb_progress <= 0.0:
		climbing = false
		global_position.y = climb_base.y
		_begin_search(climb_base, 0.8, "climbed down; searching around the trunk")


func _st_breach(delta: float) -> void:
	var cave: Dictionary = world.caves[breach_cave]
	if not world.door_blocks(breach_cave):
		_begin_search(cave["inside_point"], 0.8, "the door is open; checking inside")
		return
	var door_point: Vector3 = cave["door_point"]
	if not _go(door_point, stats["investigate_speed"]):
		return
	underground = false
	_face(cave["door_center"], delta)
	breach_timer -= delta
	if breach_timer <= 0.0:
		breach_timer = stats["door_hit_interval"]
		reason = "breaking the cave door"
		match_ref.damage_door(stats["door_damage"], breach_cave, self)


func _st_linger(delta: float) -> void:
	linger_timer += delta
	var p: Node = match_ref.players.get(linger_victim)
	if p != null:
		_face(p.global_position, delta)
	if linger_timer > Tuning.linger_before_drag:
		if p != null and p.mode == D.Mode.DOWNED and p.dragged_by < 0:
			_start_drag(p, "dragging %s away" % p.display_name)
		else:
			patrol_target = Vector3.INF
			_set_state(D.CState.PATROL, "left its victim")


func _st_drag(delta: float) -> void:
	var p: Node = match_ref.players.get(drag_victim)
	if p == null or p.mode != D.Mode.DOWNED:
		_release_drag()
		patrol_target = Vector3.INF
		_set_state(D.CState.PATROL, "lost its prey")
		return
	if not drag_pulling:
		if _go(p.global_position, stats["investigate_speed"]):
			if global_position.distance_to(p.global_position) < 2.2 and p.dragged_by < 0:
				drag_pulling = true
				underground = false
				match_ref.attach_drag(p, self)
				reason = "dragging %s toward a burrow" % p.display_name
		return
	var burrow := _nearest_burrow()
	if _go(burrow, Tuning.drag_speed, 1.5) or global_position.distance_to(burrow) < 2.4:
		match_ref.capture_player(p, burrow, self)
		drag_victim = -1
		drag_pulling = false
		if mind.scar("lantern"):
			scars = mind.scars.duplicate()
		if match_ref.daylight() > 0.5:
			_set_state(D.CState.DORMANT, "went under with its prey")
			_set_awake(false)
		else:
			patrol_target = Vector3.INF
			_set_state(D.CState.PATROL, "left its prey in the burrow")


func _st_hold(delta: float) -> void:
	# Standing still and silent: an ambush, a freeze, or holding an exit.
	var at: Vector3 = hold_next.get("at", global_position)
	if Vector2(at.x - global_position.x, at.z - global_position.z).length() > 1.0 and state_time < 12.0:
		_go(at, stats["investigate_speed"])
		return
	path = PackedVector3Array()
	_face(hold_face, delta)
	if _now() < hold_until:
		return
	var nx := hold_next
	hold_next = {}
	match nx.get("kind", ""):
		"investigate":
			_investigate(nx["pos"], 0.85, nx.get("why", "moving in"))
		"climb":
			_set_state(D.CState.PATROL, "done waiting")
			_start_climb_now(int(nx["tree"]), nx.get("why", "climbing"))
		_:
			patrol_target = Vector3.INF
			_set_state(D.CState.PATROL, "moved on")


func _start_climb_now(tree_id: int, why: String) -> void:
	var t: Dictionary = world.tree_by_id(tree_id)
	if t.is_empty():
		return
	commit_tree = tree_id
	var dir := Vector3(global_position.x - t["pos"].x, 0, global_position.z - t["pos"].z)
	dir = Vector3(1, 0, 0) if dir.length() < 0.1 else dir.normalized()
	climb_base = t["pos"] + dir * (t["trunk_r"] + 0.6)
	climbing = false
	climb_progress = 0.0
	_set_state(D.CState.CLIMB, why)


func _st_recoil(_delta: float) -> void:
	velocity = velocity.move_toward(Vector3.ZERO, 6.0 * _delta)
	if _now() < recoil_until:
		return
	var p: Node = match_ref.players.get(target_peer)
	if p and p.mode == D.Mode.NORMAL and visibility_of(p) > 0.0:
		_start_chase(p, "furious at %s" % p.display_name)
	else:
		_begin_search(last_known, 0.8, "shook it off; searching", "lost")


func _st_return(_delta: float) -> void:
	if _go(home, stats["patrol_speed"] * 1.3):
		_set_state(D.CState.DORMANT, "asleep in the burrow")
		_set_awake(false)


# ------------------------------------------------------------------ movement

## Head toward `to` along the walk grid. Returns true on arrival (or if unreachable).
func _go(to: Vector3, speed: float, repath: float = 1.0) -> bool:
	move_speed = speed
	var flat := Vector2(to.x - global_position.x, to.z - global_position.z).length()
	if flat < 0.8:
		path = PackedVector3Array()
		return true
	if path_goal == Vector3.INF or path_goal.distance_to(to) > 1.0 or repath_timer <= 0.0:
		path = world.grid.find_path(global_position, to)
		path_i = 1 if path.size() > 1 else 0
		path_goal = to
		repath_timer = repath
		if path.is_empty():
			return true
	return path_i >= path.size()


func _ground_soft(p: Vector3) -> bool:
	return not world.has_method("ground_kind") or world.ground_kind(p) == "soil"


func _remaining() -> float:
	var total := 0.0
	var prev := global_position
	for i in range(path_i, path.size()):
		total += Vector2(path[i].x - prev.x, path[i].z - prev.z).length()
		prev = path[i]
	return total


func _update_burrowing() -> void:
	if not flag("burrows"):
		return
	var travelling := state == D.CState.PATROL or state == D.CState.INVESTIGATE or state == D.CState.SEARCH or state == D.CState.CHASE or state == D.CState.RETURN
	var want := travelling and _ground_soft(global_position) and _remaining() > 10.0
	if want and not underground:
		underground = true
		match_ref.emit_cue("dig", global_position)
	elif not want and underground and (_remaining() < 5.0 or not travelling or not _ground_soft(global_position)):
		underground = false
		match_ref.emit_cue("surface", global_position)


func _move(delta: float) -> void:
	repath_timer -= delta
	_update_burrowing()
	var desired := Vector3.ZERO
	var spd := move_speed * (1.3 if underground else 1.0)
	while path_i < path.size():
		var p: Vector3 = path[path_i]
		var d := Vector3(p.x - global_position.x, 0, p.z - global_position.z)
		if d.length() < 0.45:
			path_i += 1
			continue
		desired = d.normalized() * spd
		break
	if state == D.CState.RECOIL or state == D.CState.HOLD and path.is_empty():
		desired = Vector3.ZERO
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(desired, 12.0 * delta)
	if state == D.CState.RECOIL:
		hv = Vector3(velocity.x, 0, velocity.z)
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - Tuning.gravity * delta
	var before := global_position
	move_and_slide()
	if hv.length() > 0.3 and state != D.CState.RECOIL:
		yaw = lerp_angle(yaw, atan2(-hv.x, -hv.z), clampf(delta * 8.0, 0.0, 1.0))
	if desired.length() > 0.1 and before.distance_to(global_position) < spd * delta * 0.2:
		stuck_timer += delta
		if stuck_timer > 1.0:
			stuck_timer = 0.0
			repath_timer = 0.0
			path_goal = Vector3.INF
	else:
		stuck_timer = 0.0


func _face(p: Vector3, delta: float) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		yaw = lerp_angle(yaw, atan2(-d.x, -d.z), clampf(delta * 6.0, 0.0, 1.0))


func _look_around(delta: float) -> void:
	yaw += sin(state_time * 1.3 + cid) * delta * 1.6


func _make_debug_text() -> String:
	var aw_max := 0.0
	for v in awareness.values():
		aw_max = maxf(aw_max, v)
	var tgt := "-"
	if target_peer != -1 and match_ref.players.has(target_peer):
		tgt = match_ref.players[target_peer].display_name
	var g := mind.grudge_peer()
	var grudge_txt := "-"
	if g >= 0 and match_ref.players.has(g):
		grudge_txt = "%s (%s)" % [match_ref.players[g].display_name, mind.grudge_reason]
	return "%s #%d [%s]%s\nwhy: %s\ntraits: %s   scars: %s\nlearned: %s   grudge: %s\naware %.2f  target %s" % [
		ctype, cid, D.CSTATE_NAMES[state], "  (underground)" if underground else "", reason,
		mind.traits_text(), ", ".join(mind.scars) if not mind.scars.is_empty() else "-",
		mind.counters_text(), grudge_txt, aw_max, tgt]


# ================================================================== client side + visuals

func apply_remote_snapshot(t: float, pos: Vector3, p_yaw: float) -> void:
	snaps.append([t, pos, p_yaw])
	while snaps.size() > 30:
		snaps.pop_front()


func interpolate(render_time: float) -> void:
	if snaps.is_empty():
		return
	var a: Array = snaps[0]
	var b: Array = snaps[0]
	for i in range(snaps.size() - 1, -1, -1):
		if snaps[i][0] <= render_time:
			a = snaps[i]
			b = snaps[mini(i + 1, snaps.size() - 1)]
			break
	var span: float = b[0] - a[0]
	var f := 0.0 if span <= 0.0001 else clampf((render_time - a[0]) / span, 0.0, 1.0)
	global_position = (a[1] as Vector3).lerp(b[1], f)
	yaw = lerp_angle(a[2], b[2], f)
	rotation.y = yaw


func set_debug_visible(on: bool) -> void:
	if _debug_label:
		_debug_label.visible = on and awake


func _process(delta: float) -> void:
	if not awake:
		return
	if _shown_scars != scars:
		_shown_scars = scars.duplicate()
		Body.apply_scars(_body, scars)
	var vis: Node3D = _body["vis"]
	vis.visible = not underground
	_ripple.visible = underground
	var moved := global_position - _last_vis_pos
	_last_vis_pos = global_position
	var spd := Vector2(moved.x, moved.z).length() / maxf(delta, 0.0001)
	_vis_speed = lerpf(_vis_speed, spd, clampf(delta * 6.0, 0.0, 1.0))
	if underground:
		_ripple.rotation.y = 0.0
		_rumble_t -= delta
		if _rumble_t <= 0.0 and _vis_speed > 0.3:
			_rumble_t = 0.9
			Sfx.play_3d("creature_step", global_position, 2.0, 0.4, 35.0)
		_lay_track(Vector2(moved.x, moved.z).length())
		_update_label()
		return
	_anim_phase += delta * (2.0 + _vis_speed * 2.2)
	var sw := clampf(_vis_speed / 5.0, 0.0, 1.0)
	var limp: float = 0.35 if scars.has("limp") else 0.0
	var arm_l: Node3D = _body["arm_l"]
	var arm_r: Node3D = _body["arm_r"]
	var torso: Node3D = _body["torso"]
	var lean: float = _body.get("lean", 0.35)
	var climbing_pose := state == D.CState.CLIMB and moved.y > 0.0005 or state == D.CState.TREE_ATTACK or state == D.CState.CLIMB_DOWN
	if climbing_pose:
		arm_l.rotation.x = -2.6 + sin(_anim_phase * 2.0) * 0.4
		arm_r.rotation.x = -2.6 - sin(_anim_phase * 2.0) * 0.4
		torso.rotation.x = -0.1
	elif state == D.CState.BREACH:
		var hit := sin(_anim_phase * 2.5)
		arm_l.rotation.x = -1.4 + hit * 0.9
		arm_r.rotation.x = -1.4 - hit * 0.9
		torso.rotation.x = lean + 0.15
	elif state == D.CState.RECOIL:
		arm_l.rotation.x = -0.8
		arm_r.rotation.x = -1.1
		torso.rotation.x = -0.35
	elif state == D.CState.HOLD:
		# A silhouette that doesn't move: the tell for an ambush.
		arm_l.rotation.x = 0.15
		arm_r.rotation.x = 0.15
		torso.rotation.x = lean
	else:
		arm_l.rotation.x = 0.35 + sin(_anim_phase) * 0.7 * sw
		arm_r.rotation.x = 0.35 - sin(_anim_phase) * 0.7 * sw
		torso.rotation.x = lean + sw * 0.25
	(_body["leg_l"] as Node3D).rotation.x = -sin(_anim_phase) * 0.8 * sw
	(_body["leg_r"] as Node3D).rotation.x = sin(_anim_phase) * 0.8 * sw * (1.0 - limp)
	vis.position.y = absf(sin(_anim_phase)) * 0.06 * sw - limp * 0.04 * absf(sin(_anim_phase * 0.5))
	if sw > 0.15 and not climbing_pose:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = clampf(1.6 / maxf(_vis_speed, 0.5), 0.22, 0.8)
			var st: Array = Body.STEPS.get(ctype, Body.STEPS["stalker"])
			if match_ref.hud and match_ref.local_player and match_ref.local_player.global_position.distance_to(global_position) < 16.0:
				match_ref.hud.caption("Footsteps that aren't ours", global_position)
			Sfx.play_3d(st[0], global_position, st[2] + sw * 6.0, st[1] * _rng.randf_range(0.9, 1.05), 40.0)
	if not climbing_pose:
		_lay_track(Vector2(moved.x, moved.z).length())
	_update_label()


func _update_label() -> void:
	if _debug_label and _debug_label.visible:
		_debug_label.text = debug_text


## Footprints / drag marks left on the ground: evidence the crew can read at dawn.
func _lay_track(step: float) -> void:
	if not Sfx.enabled or match_ref == null or match_ref.items_root == null:
		return
	_track_dist += step
	var gap := 0.9 if ctype == "digger" else 1.3
	if _track_dist < gap:
		return
	_track_dist = 0.0
	var tm: Array = Body.track(ctype)
	var mi := MeshInstance3D.new()
	mi.mesh = tm[0]
	mi.material_override = tm[1]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var side := 0.18 if _tracks.size() % 2 == 0 else -0.18
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var p := global_position + right * (side if ctype != "digger" else 0.0)
	p.y = world.ground_y(p) + 0.03
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), p)
	match_ref.items_root.add_child(mi)
	_tracks.append(mi)
	if _tracks.size() > 160:
		var old: Node = _tracks.pop_front()
		old.queue_free()
