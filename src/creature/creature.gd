extends CharacterBody3D
## A creature individual. The host runs the brain (`server_tick`); clients only
## interpolate position/state and animate the silhouette.
## Shared behavior core: patrol -> investigate -> search -> chase / climb / breach.
## Type traits (senses, speeds) come from Tuning.creature_stats(type, night).

const D = preload("res://src/core/defs.gd")
const Geo = preload("res://src/world/geo.gd")

var cid := 0
var ctype := "stalker"
var is_server := false
var match_ref: Node = null      # match.gd (untyped to avoid a preload cycle)
var world: Node = null          # test_clearing.gd
var stats: Dictionary = {}

# ---- brain state (host)
var state: int = D.CState.DORMANT
var state_time := 0.0
var reason := "asleep in the burrow"
var target_peer := -1
var awareness: Dictionary = {}  # peer -> 0..1.5
var last_known := Vector3.ZERO
var last_seen_t := -100.0
var investigate_pos := Vector3.ZERO
var investigate_priority := 0.0
var search_spots: Array[Vector3] = []
var search_end := 0.0
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
var _rng := RandomNumberGenerator.new()

# ---- replicated / visual
var awake := false
var snaps: Array = []
var debug_text := ""
var vis: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _torso: Node3D
var _debug_label: Label3D
var _anim_phase := 0.0
var _last_vis_pos := Vector3.ZERO
var _step_timer := 0.0
var _vis_speed := 0.0


func setup(p_id: int, p_type: String, p_server: bool, p_match: Node, p_world: Node) -> void:
	cid = p_id
	ctype = p_type
	is_server = p_server
	match_ref = p_match
	world = p_world
	name = "C%d" % p_id
	_rng.seed = p_id * 977 + 13
	stats = Tuning.creature_stats(ctype, 1)


func _ready() -> void:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 2.1
	var cs := CollisionShape3D.new()
	cs.shape = cap
	cs.position = Vector3(0, 1.05, 0)
	add_child(cs)
	collision_layer = 0
	collision_mask = D.L_WORLD if is_server else 0
	_build_visual()
	_set_awake(false)


# ================================================================== host brain

func wake(night: int, at: Vector3) -> void:
	stats = Tuning.creature_stats(ctype, night)
	global_position = at
	awareness.clear()
	climbing = false
	_set_awake(true)
	_set_state(D.CState.PATROL, "emerged at dusk")
	patrol_target = Vector3.INF


func go_home() -> void:
	if state == D.CState.DORMANT:
		return
	climbing = false
	global_position.y = world.ground_y(global_position)
	_set_state(D.CState.RETURN, "dawn: returning to the burrow")


func _set_awake(a: bool) -> void:
	awake = a
	visible = a
	collision_layer = D.L_CREATURE if (a and is_server) else 0


func _set_state(s: int, why: String) -> void:
	if log_ai and (s != state or why != reason):
		print("[ai] t=%.1f %s -> %s : %s @ (%.1f, %.1f, %.1f)" % [match_ref.match_time, D.CSTATE_NAMES[state], D.CSTATE_NAMES[s], why, global_position.x, global_position.y, global_position.z])
	if s != state:
		state = s
		state_time = 0.0
		look_timer = 0.0
		pause_time = 0.0
		path = PackedVector3Array()
		path_goal = Vector3.INF
	reason = why


func server_tick(delta: float) -> void:
	if state == D.CState.DORMANT:
		return
	state_time += delta
	attack_cd -= delta
	light_cd -= delta
	if state != D.CState.LINGER and state != D.CState.RETURN:
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


# ------------------------------------------------------------------ perception

func _perceive(delta: float) -> void:
	var now := _now()
	var best: Node = null
	var best_aw := 0.0
	for p in match_ref.players.values():
		var pid: int = p.peer_id
		if p.mode == D.Mode.DOWNED:
			awareness[pid] = 0.0
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
			if aw > best_aw:
				best_aw = aw
				best = p
		else:
			aw = maxf(0.0, aw - 0.3 * delta)
		awareness[pid] = aw
		# The light itself is a cue, visible further than the body.
		if p.lantern_open and light_cd <= 0.0 and _light_visible(p):
			light_cd = 1.0
			if state == D.CState.PATROL or state == D.CState.SEARCH or state == D.CState.INVESTIGATE:
				_investigate(p.eye_position(), 0.7, "saw a light")
	if best == null:
		return
	var calm := state == D.CState.PATROL or state == D.CState.INVESTIGATE or state == D.CState.SEARCH
	if best.tree_id >= 0 and best_aw >= 0.5 and (calm or state == D.CState.CHASE):
		_start_climb(best.tree_id, "watched %s in a tree" % best.display_name)
		return
	if calm and best_aw >= 1.0:
		_start_chase(best, "spotted %s" % best.display_name)
	elif calm and best_aw >= 0.35:
		_investigate(best.global_position, 0.6, "glimpsed movement")


## 0 when hidden, otherwise a 0.2..1 strength. Pure gameplay rules + raycasts;
## graphics settings never affect it.
func visibility_of(p: Node) -> float:
	var eye := eye_pos()
	var tp: Vector3 = p.global_position
	var to := tp - global_position
	var dist := to.length()
	var day: float = match_ref.daylight()
	var rng := lerpf(stats["sight_range_dark"], stats["sight_range_day"], day)
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
	for h in _exposure_heights(p):
		if ray_clear(eye, tp + Vector3(0, h, 0)):
			return clampf(1.0 - dist / rng * 0.8, 0.2, 1.0)
	return 0.0


func _exposure_heights(p: Node) -> Array:
	if p.mode == D.Mode.DOWNED or p.stance == D.Stance.PRONE:
		return [0.25]
	if p.stance == D.Stance.CROUCH:
		return [1.0, 0.6]
	return [1.6, 1.1, 0.5]


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


func _hear() -> void:
	for ev in match_ref.sound_events:
		var r: float = ev["radius"] * stats["hearing_mult"]
		if ev.get("muffled", false):
			r *= Tuning.cave_muffle
		var d := global_position.distance_to(ev["pos"])
		if d <= r:
			_on_sound(ev, d, r)


func _on_sound(ev: Dictionary, d: float, r: float) -> void:
	match state:
		D.CState.CLIMB, D.CState.TREE_ATTACK, D.CState.CLIMB_DOWN, D.CState.BREACH, D.CState.LINGER, D.CState.RETURN:
			return  # committed
	if state == D.CState.CHASE and _now() - last_seen_t < 2.0:
		return  # a creature that still sees a player keeps pursuing
	var kind: String = ev["kind"]
	if kind == "branch" and ev.has("tree"):
		var t: Dictionary = world.tree_by_id(ev["tree"])
		if not t.is_empty() and state != D.CState.PATROL:
			var hd := Vector2(global_position.x - t["pos"].x, global_position.z - t["pos"].z).length()
			if hd < 7.0:
				_start_climb(t["id"], "branches shook overhead")
				return
	var cid: int = ev.get("cave", -1)
	if cid >= 0 and world.door_blocks(cid):
		if cid != suspect_cave:
			cave_suspicion = 0.0
		suspect_cave = cid
		cave_suspicion += 0.7 if kind == "door" else 0.4
		var door_point: Vector3 = world.caves[cid]["door_point"]
		if cave_suspicion >= 1.0 and global_position.distance_to(door_point) < 4.0:
			_start_breach(cid, "heard them inside the cave")
			return
		_investigate(door_point, 0.8, "heard something inside the cave")
		return
	var pri := 0.5 + (1.0 - d / r) * 0.4
	if kind == "noisemaker":
		pri = 0.95
	_investigate(ev["pos"], pri, "heard %s" % kind)


# ------------------------------------------------------------------ transitions

func _investigate(pos: Vector3, pri: float, why: String) -> void:
	if state == D.CState.INVESTIGATE and pri < investigate_priority - 0.2 and state_time < 6.0:
		return
	investigate_pos = pos
	investigate_priority = pri
	if state != D.CState.INVESTIGATE:
		_set_state(D.CState.INVESTIGATE, why)
	else:
		reason = why
		state_time = 0.0
		look_timer = 0.0


func _begin_search(center: Vector3, scale: float, why: String) -> void:
	search_spots.clear()
	search_spots.append(center)
	var near: Array = []
	for s in world.hide_spots:
		var d: float = s.distance_to(center)
		if d < 14.0 and d > 1.0:
			near.append([d, s])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(3, near.size()):
		search_spots.append(near[i][1])
	var in_cid: int = world.cave_at(center + Vector3(0, 0.5, 0))
	if in_cid >= 0:
		search_spots.clear()
		for sp in world.caves[in_cid]["search_spots"]:
			search_spots.append(sp)
	search_end = _now() + stats["search_time"] * scale
	_set_state(D.CState.SEARCH, why)
	match_ref.emit_cue("chitter", global_position)


func _start_chase(p: Node, why: String) -> void:
	target_peer = p.peer_id
	last_known = p.global_position
	last_seen_t = _now()
	_set_state(D.CState.CHASE, why)
	match_ref.emit_cue("screech", global_position + Vector3(0, 1.8, 0))


func _start_climb(tree_id: int, why: String) -> void:
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


func _start_breach(cid: int, why: String) -> void:
	breach_cave = cid
	cave_suspicion = 0.0
	breach_timer = 0.6
	_set_state(D.CState.BREACH, why)


# ------------------------------------------------------------------ states

func _st_patrol(delta: float) -> void:
	if patrol_target == Vector3.INF:
		_pick_patrol_target()
		return
	if _go(patrol_target, stats["patrol_speed"]):
		pause_time += delta
		_look_around(delta)
		if pause_time > 1.5 + _rng.randf() * 0.1:
			_pick_patrol_target()


func _pick_patrol_target() -> void:
	pause_time = 0.0
	var pts: Array = world.patrol_points
	var choice: Vector3 = pts[_rng.randi() % pts.size()]
	# Weight toward the crew's general region so nights produce encounters.
	if _rng.randf() < 0.45 and not match_ref.players.is_empty():
		var ps: Array = match_ref.players.values()
		var p: Node = ps[_rng.randi() % ps.size()]
		var best_d := INF
		for q in pts:
			var d: float = (q as Vector3).distance_to(p.global_position) + _rng.randf_range(0.0, 8.0)
			if d < best_d:
				best_d = d
				choice = q
	if choice.distance_to(global_position) < 3.0:
		choice = pts[(pts.find(choice) + 3) % pts.size()]
	patrol_target = choice
	reason = "patrolling"


func _st_investigate(delta: float) -> void:
	if _go(investigate_pos, stats["investigate_speed"]):
		look_timer += delta
		_look_around(delta)
		if look_timer > 3.0:
			_begin_search(investigate_pos, 0.5, "nothing at the source; searching nearby")
	if state == D.CState.INVESTIGATE and state_time > 25.0:
		_set_state(D.CState.PATROL, "lost interest")


func _st_search(delta: float) -> void:
	if search_spots.is_empty() or _now() > search_end:
		cave_suspicion *= 0.5
		patrol_target = Vector3.INF
		_set_state(D.CState.PATROL, "search came up empty")
		return
	if _go(search_spots[0], stats["investigate_speed"] * 0.85):
		look_timer += delta
		_look_around(delta)
		if look_timer > 1.8:
			search_spots.pop_front()
			look_timer = 0.0


func _st_chase(_delta: float) -> void:
	var p: Node = match_ref.players.get(target_peer)
	if p == null or p.mode == D.Mode.DOWNED:
		patrol_target = Vector3.INF
		_set_state(D.CState.PATROL, "target gone")
		return
	var now := _now()
	var seen_recently := now - last_seen_t < 0.2
	if p.tree_id >= 0 and now - last_seen_t < 2.0:
		_start_climb(p.tree_id, "watched %s climb" % p.display_name)
		return
	if p.cave_id >= 0 and world.door_blocks(p.cave_id) and now - last_seen_t < 3.0:
		_start_breach(p.cave_id, "saw %s shut themselves in" % p.display_name)
		return
	var dist := global_position.distance_to(p.global_position)
	if seen_recently and dist < stats["catch_range"] and absf(p.global_position.y - global_position.y) < 1.2:
		match_ref.down_player(p, self)
		linger_victim = p.peer_id
		linger_timer = 0.0
		_set_state(D.CState.LINGER, "caught %s" % p.display_name)
		return
	if now - last_seen_t > 1.2:
		_begin_search(last_known, 1.0, "lost sight of %s" % p.display_name)
		return
	_go(p.global_position if seen_recently else last_known, stats["chase_speed"], 0.25)


func _st_climb(delta: float) -> void:
	var t: Dictionary = world.tree_by_id(commit_tree)
	if not climbing:
		if _go(climb_base, stats["chase_speed"]):
			climbing = true
			velocity = Vector3.ZERO
			cue_timer = 0.0
			reason = "climbing the trunk"
		return
	_face(t["pos"], delta)
	climb_progress = minf(1.0, climb_progress + delta / stats["climb_time"])
	global_position = Vector3(climb_base.x, climb_base.y + climb_progress * _canopy_y(t), climb_base.z)
	cue_timer -= delta
	if cue_timer <= 0.0:
		cue_timer = 0.7
		match_ref.emit_cue("scrape", global_position + Vector3(0, 1.0, 0), {"tree": commit_tree})
	if climb_progress >= 1.0:
		tree_timer = 0.0
		attack_cd = 1.5
		_set_state(D.CState.TREE_ATTACK, "reached the canopy")


func _canopy_y(t: Dictionary) -> float:
	return t["deck_h"] if t["deck"] else t["canopy_h"] - 0.6


func _st_tree_attack(delta: float) -> void:
	tree_timer += delta
	cue_timer -= delta
	if cue_timer <= 0.0:
		cue_timer = 0.9
		match_ref.emit_cue("deck_shake", global_position + Vector3(0, 1.0, 0), {"tree": commit_tree})
	var victim: Node = null
	var best := INF
	for p in match_ref.players.values():
		if p.tree_id == commit_tree and p.mode != D.Mode.DOWNED:
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
		attack_cd = 1.5
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
	if linger_timer > 4.0:
		patrol_target = Vector3.INF
		_set_state(D.CState.PATROL, "left its victim")


func _st_return(_delta: float) -> void:
	if _go(world.burrow_pos, stats["patrol_speed"] * 1.3):
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


func _move(delta: float) -> void:
	repath_timer -= delta
	var desired := Vector3.ZERO
	while path_i < path.size():
		var p: Vector3 = path[path_i]
		var d := Vector3(p.x - global_position.x, 0, p.z - global_position.z)
		if d.length() < 0.45:
			path_i += 1
			continue
		desired = d.normalized() * move_speed
		break
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(desired, 12.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - Tuning.gravity * delta
	var before := global_position
	move_and_slide()
	if hv.length() > 0.3:
		yaw = lerp_angle(yaw, atan2(-hv.x, -hv.z), clampf(delta * 8.0, 0.0, 1.0))
	if desired.length() > 0.1 and before.distance_to(global_position) < move_speed * delta * 0.2:
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
	return "%s #%d [%s]\nwhy: %s\naware %.2f  target %s  cave? %.1f" % [ctype, cid, D.CSTATE_NAMES[state], reason, aw_max, tgt, cave_suspicion]


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
	var moved := global_position - _last_vis_pos
	_last_vis_pos = global_position
	var spd := Vector2(moved.x, moved.z).length() / maxf(delta, 0.0001)
	_vis_speed = lerpf(_vis_speed, spd, clampf(delta * 6.0, 0.0, 1.0))
	_anim_phase += delta * (2.0 + _vis_speed * 2.2)
	var sw := clampf(_vis_speed / 5.0, 0.0, 1.0)
	var climbing_pose := state == D.CState.CLIMB and moved.y > 0.0005 or state == D.CState.TREE_ATTACK or state == D.CState.CLIMB_DOWN
	if climbing_pose:
		_arm_l.rotation.x = -2.6 + sin(_anim_phase * 2.0) * 0.4
		_arm_r.rotation.x = -2.6 - sin(_anim_phase * 2.0) * 0.4
		_torso.rotation.x = -0.1
	elif state == D.CState.BREACH:
		var hit := sin(_anim_phase * 2.5)
		_arm_l.rotation.x = -1.4 + hit * 0.9
		_arm_r.rotation.x = -1.4 - hit * 0.9
		_torso.rotation.x = 0.45
	else:
		_arm_l.rotation.x = 0.35 + sin(_anim_phase) * 0.7 * sw
		_arm_r.rotation.x = 0.35 - sin(_anim_phase) * 0.7 * sw
		_torso.rotation.x = 0.35 + sw * 0.25
	_leg_l.rotation.x = -sin(_anim_phase) * 0.8 * sw
	_leg_r.rotation.x = sin(_anim_phase) * 0.8 * sw
	vis.position.y = absf(sin(_anim_phase)) * 0.06 * sw
	if sw > 0.15 and not climbing_pose:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = clampf(1.6 / maxf(_vis_speed, 0.5), 0.22, 0.8)
			Sfx.play_3d("creature_step", global_position, -6.0 + sw * 6.0, _rng.randf_range(0.8, 1.0), 40.0)
	if _debug_label and _debug_label.visible:
		_debug_label.text = debug_text


func _build_visual() -> void:
	vis = Node3D.new()
	add_child(vis)
	var skin := Geo.mat(Color(0.035, 0.03, 0.035), 0.45)
	var eye_m := Geo.mat(Color(0.9, 0.6, 0.2), 0.3, Color(1.0, 0.55, 0.15), 2.5)
	_torso = Node3D.new()
	_torso.position = Vector3(0, 1.15, 0)
	vis.add_child(_torso)
	Geo.mesh(_torso, _capsule(0.24, 1.2), Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0)), skin)
	Geo.sphere(_torso, 0.26, Vector3(0, 1.05, 0.05), skin, Vector3(1.6, 0.6, 1.0))   # shoulders
	var head := Node3D.new()
	head.position = Vector3(0, 1.3, -0.2)
	_torso.add_child(head)
	Geo.sphere(head, 0.17, Vector3.ZERO, skin, Vector3(0.75, 0.85, 1.5))
	Geo.sphere(head, 0.03, Vector3(0.07, 0.03, -0.22), eye_m, Vector3.ONE, false)
	Geo.sphere(head, 0.03, Vector3(-0.07, 0.03, -0.22), eye_m, Vector3.ONE, false)
	_arm_l = _limb(_torso, Vector3(0.36, 1.05, 0), 1.45, 0.06, skin)
	_arm_r = _limb(_torso, Vector3(-0.36, 1.05, 0), 1.45, 0.06, skin)
	_leg_l = _limb(vis, Vector3(0.17, 1.15, 0), 1.15, 0.08, skin)
	_leg_r = _limb(vis, Vector3(-0.17, 1.15, 0), 1.15, 0.08, skin)
	_debug_label = Label3D.new()
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_label.no_depth_test = true
	_debug_label.font_size = 24
	_debug_label.pixel_size = 0.005
	_debug_label.modulate = Color(1, 0.85, 0.4)
	_debug_label.position = Vector3(0, 3.0, 0)
	_debug_label.visible = false
	add_child(_debug_label)


func _limb(parent: Node3D, origin: Vector3, length: float, radius: float, m: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = origin
	parent.add_child(pivot)
	Geo.rod(pivot, Vector3.ZERO, Vector3(0, -length * 0.55, -0.05), radius, m)
	Geo.rod(pivot, Vector3(0, -length * 0.55, -0.05), Vector3(0, -length, -0.12), radius * 0.75, m)
	Geo.sphere(pivot, radius * 1.4, Vector3(0, -length, -0.14), m, Vector3(1, 0.6, 1.8))
	return pivot


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c
