extends Node3D
## One run. Exists on every peer at /root/Main/Match.
## Host: owns the clock, player state, creatures, structures, items and results.
## Clients: send input intent, predict their own avatar, render replicated state.

const D = preload("res://src/core/defs.gd")
const Geo = preload("res://src/world/geo.gd")
const PlayerScript = preload("res://src/player/player.gd")
const CreatureScript = preload("res://src/creature/creature.gd")
const Clearing = preload("res://src/world/test_clearing.gd")
const EnvCtl = preload("res://src/world/environment_ctl.gd")
const Hud = preload("res://src/ui/hud.gd")

var params: Dictionary = {}
var is_server := false
var headless := false
var world: Node3D
var env: Node3D
var hud: CanvasLayer
var players: Dictionary = {}       # peer_id -> player.gd
var creatures: Dictionary = {}     # id -> creature.gd
var local_player: CharacterBody3D = null
var players_root: Node3D
var creatures_root: Node3D
var items_root: Node3D

# ---- shared clock (host authoritative, replicated)
var match_time := 0.0
var phase: int = D.Phase.DAY
var phase_time := 0.0
var day_index := 1
var nights_survived := 0
var over := false

# ---- host-only
var sound_events: Array = []       # consumed by creatures each tick, then cleared
var _snap_accum := 0.0
var _snap_count := 0
var dev_start_phase := -1

# ---- items (noisemakers): id -> {pos, vel, landed, pulses, timer, idle, flight, node}
var noisemakers: Dictionary = {}
var _next_nm := 1

# ---- client
var _time_offset := 0.0
var _have_offset := false
var debug_on := false
var look_yaw := 0.0
var look_pitch := 0.0
var want_stance: int = D.Stance.STAND
var bot := false
var _bot_t := 0.0
var _spawn_pos := Vector3.ZERO
var smoke := {"snapshots": 0, "inputs": 0, "max_err": 0.0, "max_players": 0, "remote_moved": 0.0}


func setup(p: Dictionary) -> void:
	params = p


func _ready() -> void:
	name = "Match"
	is_server = multiplayer.is_server()
	headless = DisplayServer.get_name() == "headless"
	world = Clearing.new()
	world.name = "World"
	add_child(world)
	world.build(int(params.get("seed", 0)))
	if not headless:
		env = EnvCtl.new()
		env.match_ref = self
		add_child(env)
	players_root = _child_root("Players")
	creatures_root = _child_root("Creatures")
	items_root = _child_root("Items")
	var roster: Dictionary = params.get("roster", {})
	var ids: Array = roster.keys()
	ids.sort()
	for pid in ids:
		_spawn_player(int(pid), roster[pid])
	_spawn_creatures()
	if not headless:
		hud = Hud.new()
		hud.match_ref = self
		add_child(hud)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Net.peer_left.connect(_on_peer_left)
	if local_player:
		look_yaw = local_player.yaw
		_spawn_pos = local_player.global_position
	if is_server and dev_start_phase >= 0:
		_set_phase(dev_start_phase)
	print("[match] started seed=%d players=%d server=%s" % [int(params.get("seed", 0)), players.size(), is_server])


func _child_root(n: String) -> Node3D:
	var r := Node3D.new()
	r.name = n
	add_child(r)
	return r


func _spawn_player(pid: int, info: Dictionary) -> void:
	var p := PlayerScript.new()
	var slot: int = info.get("slot", 0)
	p.setup(pid, info.get("name", "Survivor"), slot, pid == multiplayer.get_unique_id(), is_server)
	players_root.add_child(p)
	var sp: Vector3 = world.spawn_points[slot % world.spawn_points.size()]
	p.global_position = sp + Vector3(0, 0.05, 0)
	p.yaw = atan2(sp.x, sp.z)   # face the clearing center
	players[pid] = p
	if p.is_local:
		local_player = p


func _spawn_creatures() -> void:
	# Milestone 2: a single Stalker. Later milestones draw types from the pool by seed.
	var c := CreatureScript.new()
	c.setup(0, "stalker", is_server, self, world)
	creatures_root.add_child(c)
	c.global_position = world.burrow_pos
	creatures[0] = c


func _remove_player(pid: int) -> void:
	if players.has(pid):
		var p: Node = players[pid]
		players.erase(pid)
		p.queue_free()
		if hud:
			hud.notice("A survivor left the island.")


func _wall() -> float:
	return Time.get_ticks_usec() / 1000000.0


func daylight() -> float:
	var f := clampf(phase_time / Tuning.phase_length(phase), 0.0, 1.0)
	match phase:
		D.Phase.DAY: return 1.0
		D.Phase.DUSK: return 1.0 - f
		D.Phase.NIGHT: return 0.0
	return f


# ================================================================== main loop

func _physics_process(delta: float) -> void:
	if is_server:
		if not over:
			_advance_clock(delta)
		if local_player:
			var inp := _local_input(delta)
			local_player.input_queue.append(inp)
		for p in players.values():
			_srv_step_player(p, delta)
		_srv_update_noisemakers(delta)
		for c in creatures.values():
			c.server_tick(delta)
		sound_events.clear()
		_srv_revive(delta)
		if not over:
			_check_loss()
		_snap_accum += delta
		if _snap_accum >= 1.0 / Tuning.snapshot_rate:
			_snap_accum = 0.0
			_send_snapshot()
	else:
		match_time += delta
		phase_time += delta
		if local_player:
			_client_predict(delta)
		_client_update_noisemakers(delta)


func _process(_delta: float) -> void:
	var rt := _wall() + _time_offset - 0.1
	if not is_server:
		for p in players.values():
			if not p.is_local:
				p.interpolate(rt)
		if local_player and (local_player.mode == D.Mode.CLIMBING or local_player.mode == D.Mode.PERCHED):
			local_player.interpolate(rt)
		for c in creatures.values():
			if c.awake:
				c.interpolate(rt)
	if local_player:
		local_player.yaw = look_yaw
		local_player.pitch = look_pitch
		# Real, host-driven warning: the lantern flickers when a creature is close.
		var nearest := INF
		for c in creatures.values():
			if c.awake:
				nearest = minf(nearest, c.global_position.distance_to(local_player.global_position))
		local_player.set_flicker(clampf(1.0 - nearest / Tuning.lantern_flicker_dist, 0.0, 1.0))


# ================================================================== clock

func _advance_clock(delta: float) -> void:
	match_time += delta
	phase_time += delta
	if phase_time >= Tuning.phase_length(phase):
		_set_phase((phase + 1) % 4)


func _set_phase(new_phase: int) -> void:
	phase_time = 0.0
	if new_phase == D.Phase.DAY and phase != D.Phase.DAY:
		day_index += 1
	phase = new_phase
	match phase:
		D.Phase.NIGHT:
			var count: int = mini(Tuning.patrol_count(day_index), creatures.size())
			var i := 0
			for c in creatures.values():
				if i < count:
					c.wake(day_index, world.burrow_pos + Vector3(i * 1.5, 0, 0))
				i += 1
			emit_cue("call", world.burrow_pos + Vector3(0, 1, 0))
		D.Phase.DAWN:
			nights_survived += 1
			for c in creatures.values():
				c.go_home()
	_rpc_event.rpc("phase", Vector3.ZERO, {"phase": phase, "day": day_index})


# ================================================================== input

func _input_active() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not over


func _local_input(delta: float) -> Dictionary:
	var mv := Vector2.ZERO
	var btn := 0
	if bot:
		return _bot_input(delta)
	if _input_active():
		mv = Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_forward", "move_back"))
		if Input.is_action_pressed("sprint"):
			btn |= D.BTN_SPRINT
		if Input.is_action_pressed("jump") and want_stance == D.Stance.STAND:
			btn |= D.BTN_JUMP
		if Input.is_action_pressed("interact"):
			btn |= D.BTN_INTERACT
	return {"mx": mv.x, "my": mv.y, "yaw": look_yaw, "pitch": look_pitch, "stance": want_stance, "btn": btn}


func _bot_input(delta: float) -> Dictionary:
	# Scripted movement for the headless two-instance smoke test.
	_bot_t += delta
	var mv := Vector2(0, -1)
	var btn := 0
	if _bot_t > 2.0 and _bot_t < 3.5:
		btn |= D.BTN_SPRINT
	if _bot_t > 3.5:
		mv = Vector2(sin(_bot_t), -0.5)
	look_yaw = 0.3 * sin(_bot_t * 0.5)
	return {"mx": mv.x, "my": mv.y, "yaw": look_yaw, "pitch": 0.0, "stance": D.Stance.STAND, "btn": btn}


func _unhandled_input(event: InputEvent) -> void:
	if local_player == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.relative
		look_yaw -= rel.x * deg_to_rad(Settings.mouse_sensitivity)
		look_pitch = clampf(look_pitch - rel.y * deg_to_rad(Settings.mouse_sensitivity), -1.5, 1.5)
		return
	if event.is_action_pressed("debug_overlay"):
		debug_on = not debug_on
		for c in creatures.values():
			c.set_debug_visible(debug_on)
		return
	if not _input_active():
		return
	var lp := local_player
	if event.is_action_pressed("crouch"):
		want_stance = D.Stance.STAND if want_stance == D.Stance.CROUCH else D.Stance.CROUCH
	elif event.is_action_pressed("prone"):
		want_stance = D.Stance.STAND if want_stance == D.Stance.PRONE else D.Stance.PRONE
	elif event.is_action_pressed("jump"):
		if lp.mode == D.Mode.PERCHED:
			request("perch", "down")
		elif want_stance != D.Stance.STAND:
			want_stance = D.Stance.STAND
	elif event.is_action_pressed("sprint"):
		if want_stance != D.Stance.STAND:
			want_stance = D.Stance.STAND
	elif event.is_action_pressed("interact"):
		_press_interact()
	elif event.is_action_pressed("lantern"):
		if lp.mode != D.Mode.DOWNED:
			lp.lantern_open = not lp.lantern_open
			request("lantern", lp.lantern_open)
	elif event.is_action_pressed("throw"):
		if lp.noisemakers > 0 and lp.mode == D.Mode.NORMAL:
			request("throw", look_yaw, look_pitch)
	elif event.is_action_pressed("rope"):
		if lp.mode == D.Mode.PERCHED:
			request("perch", "rope")
		else:
			var it := best_interactable(lp)
			if it.get("kind", "") == "rope":
				request("interact", "rope", it["id"])
	elif event.is_action_pressed("dev_skip_phase"):
		if is_server:
			request("skip_phase")


func _press_interact() -> void:
	var p := local_player
	if p.mode == D.Mode.PERCHED:
		request("perch", "up")
		return
	var it := best_interactable(p)
	if it.is_empty() or it["kind"] == "revive":
		return  # revive is a hold, carried in the input bits
	request("interact", it["kind"], it["id"])


## Send an action intent to the host (or handle it directly when we are the host).
func request(kind: String, a: Variant = null, b: Variant = null) -> void:
	if is_server:
		_handle_request(multiplayer.get_unique_id(), kind, a, b)
	else:
		_rpc_request.rpc_id(1, kind, a, b)


func _client_predict(delta: float) -> void:
	var lp := local_player
	var inp := _local_input(delta)
	lp.seq += 1
	var s: int = lp.seq
	_rpc_input.rpc_id(1, s, inp["mx"], inp["my"], inp["yaw"], inp["pitch"], inp["stance"], inp["btn"])
	if lp.mode == D.Mode.NORMAL or lp.mode == D.Mode.DOWNED:
		lp.simulate(inp, delta)
		lp.history[s] = lp.global_position
		if lp.history.size() > 240:
			lp.history.erase(s - 240)
	lp.cover = world.cover_at(lp.global_position)


# ================================================================== host: players

@rpc("any_peer", "unreliable_ordered")
func _rpc_input(s: int, mx: float, my: float, y: float, pt: float, st: int, btn: int) -> void:
	if not is_server:
		return
	var p: Node = players.get(multiplayer.get_remote_sender_id())
	if p == null or s <= p.last_seq:
		return
	if not (is_finite(mx) and is_finite(my) and is_finite(y) and is_finite(pt)):
		return
	p.input_queue.append({
		"seq": s, "mx": clampf(mx, -1.0, 1.0), "my": clampf(my, -1.0, 1.0),
		"yaw": y, "pitch": clampf(pt, -1.55, 1.55), "stance": clampi(st, 0, 2), "btn": btn & 7,
	})
	if p.input_queue.size() > 12:
		p.input_queue = p.input_queue.slice(-6)
	smoke["inputs"] += 1


func _srv_step_player(p: Node, delta: float) -> void:
	if p.input_queue.is_empty():
		var idle: Dictionary = p.last_input.duplicate()
		idle["mx"] = 0.0
		idle["my"] = 0.0
		idle["btn"] = 0
		_srv_apply(p, idle, delta)
	else:
		var n := 2 if p.input_queue.size() > 3 else 1
		for i in n:
			if p.input_queue.is_empty():
				break
			var inp: Dictionary = p.input_queue.pop_front()
			p.last_seq = inp.get("seq", p.last_seq)
			p.last_input = inp
			_srv_apply(p, inp, delta)
	_srv_post_step(p, delta)


func _srv_apply(p: Node, inp: Dictionary, delta: float) -> void:
	if p.mode == D.Mode.CLIMBING or p.mode == D.Mode.PERCHED:
		p.yaw = inp.get("yaw", p.yaw)
		p.pitch = inp.get("pitch", p.pitch)
		return
	p.simulate(inp, delta)


func _srv_post_step(p: Node, delta: float) -> void:
	match p.mode:
		D.Mode.CLIMBING:
			_srv_climb_tick(p, delta)
		D.Mode.PERCHED:
			_srv_perch_tick(p, delta)
		D.Mode.DOWNED:
			p.downed_time += delta
	var pos: Vector3 = p.global_position
	p.cover = "" if p.mode == D.Mode.CLIMBING else world.cover_at(pos)
	p.inside_cave = world.in_cave(pos) and pos.y < 2.5
	if p.mode == D.Mode.NORMAL:
		p.tree_id = world.deck_tree_at(pos)
	if pos.y < -10.0:
		p.global_position = world.spawn_points[0]  # safety net, never lose an avatar
	# Movement noise heard by creatures.
	if (p.mode == D.Mode.NORMAL or p.mode == D.Mode.DOWNED) and p.moving:
		p.step_timer -= delta
		if p.step_timer <= 0.0:
			p.step_timer = Tuning.footstep_interval
			var r := Tuning.noise_walk
			var kind := "footsteps"
			if p.sprinting:
				r = Tuning.noise_sprint
			elif p.mode == D.Mode.DOWNED or p.stance == D.Stance.PRONE:
				r = Tuning.noise_prone
			elif p.stance == D.Stance.CROUCH:
				r = Tuning.noise_crouch
			if p.cover == "grass" or p.cover == "bush":
				r = maxf(r, Tuning.noise_grass_rustle)
				kind = "rustling"
			if p.tree_id >= 0:
				emit_sound(pos, maxf(r, Tuning.noise_branch), "branch", {"tree": p.tree_id})
				emit_cue("branch", pos)
			else:
				emit_sound(pos, r, kind)
	elif p.mode == D.Mode.CLIMBING:
		p.branch_timer -= delta
		if p.branch_timer <= 0.0:
			p.branch_timer = 0.8
			emit_sound(pos, Tuning.noise_branch, "branch", {"tree": p.tree_id})
			emit_cue("branch", pos)


func emit_sound(pos: Vector3, radius: float, kind: String, extra: Dictionary = {}) -> void:
	var ev := {"pos": pos, "radius": radius, "kind": kind}
	var inside: bool = world.in_cave(pos) and pos.y < 2.5
	ev["in_cave"] = inside
	ev["muffled"] = inside and world.door_blocks()
	ev.merge(extra)
	sound_events.append(ev)


@rpc("any_peer", "reliable")
func _rpc_request(kind: String, a: Variant, b: Variant) -> void:
	if is_server:
		_handle_request(multiplayer.get_remote_sender_id(), kind, a, b)


func _handle_request(pid: int, kind: String, a: Variant, b: Variant) -> void:
	var p: Node = players.get(pid)
	if p == null or over:
		return
	match kind:
		"lantern":
			if p.mode != D.Mode.DOWNED:
				p.lantern_open = bool(a)
		"throw":
			if typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_FLOAT:
				_srv_throw(p, a, b)
		"interact":
			if typeof(a) == TYPE_STRING and typeof(b) == TYPE_INT:
				_srv_interact(p, a, b)
		"perch":
			if typeof(a) == TYPE_STRING:
				_srv_perch_action(p, a)
		"skip_phase":
			if pid == 1:
				_set_phase((phase + 1) % 4)


func notify(p: Node, text: String) -> void:
	if p.is_local:
		if hud:
			hud.notice(text)
	else:
		_rpc_notice.rpc_id(p.peer_id, text)


@rpc("authority", "reliable")
func _rpc_notice(text: String) -> void:
	if hud:
		hud.notice(text)


# ------------------------------------------------------------------ interactables

func interact_candidates(p: Node) -> Array:
	var out: Array = []
	if p.mode != D.Mode.NORMAL:
		return out
	for it in world.interactables:
		match it["kind"]:
			"climb":
				if p.global_position.y < 1.5:
					out.append(it)
			"door":
				if world.cave["door_hp"] > 0.0:
					out.append(it)
			"deck_down", "rope":
				if p.tree_id == it["tree"]:
					out.append(it)
	for id in noisemakers:
		var nm: Dictionary = noisemakers[id]
		if nm["idle"]:
			out.append({"kind": "pickup", "id": id, "pos": nm["pos"] + Vector3(0, 0.1, 0)})
	for q in players.values():
		if q != p and q.mode == D.Mode.DOWNED:
			out.append({"kind": "revive", "id": q.peer_id, "pos": q.global_position + Vector3(0, 0.3, 0)})
	return out


## Best interactable in front of the player. `lenient` is used by the host to validate
## a client's request: wider range and no facing requirement.
func best_interactable(p: Node, lenient: bool = false, kind: String = "", id: int = -1) -> Dictionary:
	var eye: Vector3 = p.eye_position()
	var look: Vector3 = Basis.from_euler(Vector3(p.pitch, p.yaw, 0)) * Vector3.FORWARD
	var slack := 0.8 if lenient else 0.0
	var best: Dictionary = {}
	var best_score := -INF
	for it in interact_candidates(p):
		if kind != "" and (it["kind"] != kind or it["id"] != id):
			continue
		var target: Vector3 = it["pos"]
		var dist: float
		if it["kind"] == "climb":
			var t: Dictionary = world.tree_by_id(it["tree"])
			dist = Vector2(p.global_position.x - t["pos"].x, p.global_position.z - t["pos"].z).length() - t["trunk_r"]
			if dist > 1.3 + slack:
				continue
			target = Vector3(t["pos"].x, eye.y, t["pos"].z)
		else:
			dist = eye.distance_to(target)
			if dist > Tuning.interact_range + slack:
				continue
		var facing := look.dot((target - eye).normalized())
		if not lenient and facing < 0.35 and dist > 0.9:
			continue
		var score := facing * 2.0 - dist
		if score > best_score:
			best_score = score
			best = it
	return best


func _srv_interact(p: Node, kind: String, id: int) -> void:
	var it := best_interactable(p, true, kind, id)
	if it.is_empty():
		return
	match kind:
		"climb":
			_srv_start_climb(p, world.tree_by_id(it["tree"]))
		"door":
			_srv_toggle_door(p)
		"deck_down":
			var t: Dictionary = world.tree_by_id(it["tree"])
			var dur := Tuning.climb_ladder_time if t["ladder"] else Tuning.climb_down_time * 1.4
			_begin_climb(p, t, _anchor(t, "ground", _dir_from_trunk(t, p.global_position)), dur, "ground")
		"rope":
			var t2: Dictionary = world.tree_by_id(it["tree"])
			_begin_climb(p, t2, t2["rope_land"], Tuning.rope_time, "rope", t2["rope_top"])
			emit_sound(t2["rope_top"], Tuning.noise_rope, "rope")
			emit_cue("rope", t2["rope_top"])
		"pickup":
			if noisemakers.has(id):
				p.noisemakers += 1
				noisemakers.erase(id)
				_rpc_event.rpc("nm_remove", Vector3.ZERO, {"id": id})


func _srv_toggle_door(p: Node) -> void:
	var hp: float = world.cave["door_hp"]
	if hp <= 0.0:
		return
	var open: bool = not world.cave["door_open"]
	if not open:
		var dc: Vector3 = world.cave["door_center"]
		for q in players.values():
			if Vector2(q.global_position.x - dc.x, q.global_position.z - dc.z).length() < 0.55:
				notify(p, "Someone is standing in the doorway.")
				return
	world.set_door(open, hp)
	emit_sound(world.cave["door_center"], Tuning.noise_door, "door")
	emit_cue("door", world.cave["door_center"])


func damage_door(amount: float, _by: Node) -> void:
	var hp: float = maxf(0.0, world.cave["door_hp"] - amount)
	world.set_door(world.cave["door_open"], hp)
	var dc: Vector3 = world.cave["door_center"]
	emit_cue("door_hit", dc, {"hp": hp})
	if hp <= 0.0:
		emit_cue("door_break", dc)
	elif hp <= Tuning.door_breach_warn_below:
		emit_cue("breach_warn", dc)


# ------------------------------------------------------------------ climbing

func _dir_from_trunk(t: Dictionary, pos: Vector3) -> Vector3:
	var d := Vector3(pos.x - t["pos"].x, 0, pos.z - t["pos"].z)
	return Vector3(1, 0, 0) if d.length() < 0.05 else d.normalized()


func _anchor(t: Dictionary, which: String, dir: Vector3) -> Vector3:
	var base: Vector3 = t["pos"]
	var r: float = t["trunk_r"]
	match which:
		"perch":
			return base + (t["perch_dir"] as Vector3) * (r + 0.55) + Vector3(0, t["perch_h"] + 0.25, 0)
		"canopy":
			if t["deck"]:
				return base + dir * (r + 0.7) + Vector3(0, t["deck_h"] + 0.02, 0)
			return base + dir * (r + 0.4) + Vector3(0, t["canopy_h"] - 0.6, 0)
		"partway":
			return base + dir * (r + 0.4) + Vector3(0, t["partway_h"], 0)
	return base + dir * (r + 0.55)


func _srv_start_climb(p: Node, t: Dictionary) -> void:
	if t.is_empty() or p.mode != D.Mode.NORMAL or p.global_position.y > 1.5:
		return
	var dir := _dir_from_trunk(t, p.global_position)
	if t["ladder"]:
		_begin_climb(p, t, _anchor(t, "canopy", dir), Tuning.climb_ladder_time, "canopy")
		return
	match t["type"]:
		"low":
			_begin_climb(p, t, _anchor(t, "perch", dir), Tuning.climb_to_perch_time, "perch")
		"rough":
			if p.stamina < Tuning.climb_stamina_cost * 0.6:
				notify(p, "Too winded to climb. Catch your breath.")
				return
			p.stamina = maxf(0.0, p.stamina - Tuning.climb_stamina_cost)
			_begin_climb(p, t, _anchor(t, "canopy", dir), Tuning.climb_rough_time, "canopy")
		"bare":
			_begin_climb(p, t, _anchor(t, "partway", dir), Tuning.climb_bare_partway_time, "partway")


func _begin_climb(p: Node, t: Dictionary, to: Vector3, dur: float, target: String, from: Variant = null) -> void:
	p.mode = D.Mode.CLIMBING
	p.velocity = Vector3.ZERO
	p.sprinting = false
	var start: Vector3 = p.global_position if from == null else from
	p.climb = {"from": start, "to": to, "t": 0.0, "dur": maxf(dur, 0.1), "target": target, "tree": t["id"]}
	p.tree_id = t["id"]
	p.perch = ""
	p.stance = D.Stance.STAND
	p._apply_shape()
	p.branch_timer = 0.0


func _srv_climb_tick(p: Node, delta: float) -> void:
	var c: Dictionary = p.climb
	if c.is_empty():
		p.mode = D.Mode.NORMAL
		return
	c["t"] += delta / c["dur"]
	var f := smoothstep(0.0, 1.0, minf(c["t"], 1.0))
	p.global_position = (c["from"] as Vector3).lerp(c["to"], f)
	if c["t"] >= 1.0:
		var t: Dictionary = world.tree_by_id(c["tree"])
		var target: String = c["target"]
		p.climb = {}
		p.velocity = Vector3.ZERO
		match target:
			"perch", "partway":
				p.mode = D.Mode.PERCHED
				p.perch = target
				p.hang_timer = Tuning.bare_hang_time
			"canopy":
				if t["deck"]:
					p.mode = D.Mode.NORMAL
				else:
					p.mode = D.Mode.PERCHED
					p.perch = "canopy"
			_:
				p.mode = D.Mode.NORMAL
				p.tree_id = -1


func _srv_perch_tick(p: Node, delta: float) -> void:
	p.regen_timer -= delta
	if p.regen_timer <= 0.0:
		p.stamina = minf(Tuning.stamina_max, p.stamina + Tuning.stamina_regen * 0.5 * delta)
	if p.perch == "partway":
		p.hang_timer -= delta
		p.stamina = maxf(0.0, p.stamina - 6.0 * delta)
		if p.hang_timer <= 0.0:
			notify(p, "Your grip gives out.")
			_srv_perch_action(p, "down")
			return
	# Shifting your weight on a branch shakes it.
	var li: Dictionary = p.last_input
	if absf(li.get("mx", 0.0)) + absf(li.get("my", 0.0)) > 0.3:
		p.branch_timer -= delta
		if p.branch_timer <= 0.0:
			p.branch_timer = 0.8
			emit_sound(p.global_position, Tuning.noise_branch, "branch", {"tree": p.tree_id})
			emit_cue("branch", p.global_position)


func _srv_perch_action(p: Node, action: String) -> void:
	if p.mode != D.Mode.PERCHED:
		return
	var t: Dictionary = world.tree_by_id(p.tree_id)
	if t.is_empty():
		return
	var dir := _dir_from_trunk(t, p.global_position)
	match action:
		"up":
			if p.perch == "perch":
				if p.stamina < Tuning.climb_stamina_cost * 0.3:
					notify(p, "Too winded to climb higher.")
					return
				p.stamina = maxf(0.0, p.stamina - Tuning.climb_stamina_cost * 0.5)
				_begin_climb(p, t, _anchor(t, "canopy", dir), Tuning.climb_perch_to_canopy_time, "canopy")
		"down":
			var dur := Tuning.climb_down_time
			if p.perch == "partway":
				dur = 0.5
			elif p.perch == "perch":
				dur = 0.6
			if t["ladder"]:
				dur = minf(dur, Tuning.climb_ladder_time)
			_begin_climb(p, t, _anchor(t, "ground", dir), dur, "ground")
		"rope":
			if p.perch == "canopy" and t["rope"]:
				_begin_climb(p, t, t["rope_land"], Tuning.rope_time, "rope", t["rope_top"])


# ------------------------------------------------------------------ downed / revive / loss

func down_player(p: Node, _by: Node) -> void:
	if p.mode == D.Mode.DOWNED:
		return
	var tid: int = p.tree_id
	if tid < 0 and not p.climb.is_empty():
		tid = p.climb["tree"]
	if tid >= 0 or p.mode == D.Mode.CLIMBING or p.mode == D.Mode.PERCHED:
		# Knocked out of the tree: land on valid ground beside the trunk.
		var t: Dictionary = world.tree_by_id(maxi(tid, 0))
		var a := randf() * TAU
		p.global_position = t["pos"] + Vector3(cos(a), 0, sin(a)) * (t["trunk_r"] + 1.0) + Vector3(0, 0.05, 0)
	p.mode = D.Mode.DOWNED
	p.climb = {}
	p.perch = ""
	p.tree_id = -1
	p.lantern_open = false
	p.sprinting = false
	p.velocity = Vector3.ZERO
	p.revive_progress = 0.0
	p.downed_time = 0.0
	p.try_set_stance(D.Stance.PRONE)
	emit_cue("down", p.global_position, {"name": p.display_name, "peer": p.peer_id})


func _srv_revive(delta: float) -> void:
	for q in players.values():
		if q.mode != D.Mode.DOWNED:
			continue
		var helper: Node = null
		for r in players.values():
			if r == q or r.mode != D.Mode.NORMAL:
				continue
			if (int(r.last_input.get("btn", 0)) & D.BTN_INTERACT) != 0 and r.global_position.distance_to(q.global_position) < 2.2:
				helper = r
				break
		if helper:
			q.revive_progress += delta / Tuning.revive_time
		else:
			q.revive_progress = maxf(0.0, q.revive_progress - delta)
		if q.revive_progress >= 1.0:
			q.mode = D.Mode.NORMAL
			q.revive_progress = 0.0
			q.stamina = Tuning.revive_stamina
			emit_cue("revived", q.global_position, {"name": q.display_name, "by": helper.display_name})


func _check_loss() -> void:
	if players.is_empty():
		return
	for p in players.values():
		if p.mode != D.Mode.DOWNED:
			return
	_end_match(false)


func _end_match(won: bool) -> void:
	over = true
	_rpc_game_over.rpc({"won": won, "nights": nights_survived, "day": day_index})


@rpc("authority", "call_local", "reliable")
func _rpc_game_over(summary: Dictionary) -> void:
	over = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hud:
		hud.show_results(summary)


func _on_peer_left(pid: int) -> void:
	if is_server:
		_remove_player(pid)
		_rpc_player_left.rpc(pid)


@rpc("authority", "reliable")
func _rpc_player_left(pid: int) -> void:
	_remove_player(pid)


# ------------------------------------------------------------------ noisemakers

func _srv_throw(p: Node, y: float, pt: float) -> void:
	if p.noisemakers <= 0 or p.mode != D.Mode.NORMAL:
		return
	p.noisemakers -= 1
	var dir := Basis.from_euler(Vector3(clampf(pt, -1.5, 1.5) + 0.15, y, 0)) * Vector3.FORWARD
	var id := _next_nm
	_next_nm += 1
	var pos: Vector3 = p.eye_position() + dir * 0.4
	var vel := dir * Tuning.throw_speed
	noisemakers[id] = {"pos": pos, "vel": vel, "landed": false, "pulses": Tuning.noisemaker_pulses, "timer": 0.0, "idle": false, "flight": 0.0, "node": null}
	_rpc_event.rpc("nm_spawn", pos, {"id": id, "vel": vel})


func _step_projectile(nm: Dictionary, delta: float) -> void:
	var v: Vector3 = nm["vel"]
	v.y -= 9.8 * delta
	nm["flight"] += delta
	var from: Vector3 = nm["pos"]
	var to := from + v * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, D.L_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		nm["pos"] = to
		nm["vel"] = v
	else:
		var n: Vector3 = hit["normal"]
		nm["pos"] = (hit["position"] as Vector3) + n * 0.06
		if n.y > 0.6 and v.length() < 6.0:
			nm["landed"] = true
			nm["vel"] = Vector3.ZERO
		else:
			nm["vel"] = v.bounce(n) * 0.35
	if nm["flight"] > 6.0:
		nm["landed"] = true
	if nm["node"]:
		nm["node"].position = nm["pos"]


func _srv_update_noisemakers(delta: float) -> void:
	for id in noisemakers.keys():
		var nm: Dictionary = noisemakers[id]
		if not nm["landed"]:
			_step_projectile(nm, delta)
			if nm["landed"]:
				_rpc_event.rpc("nm_land", nm["pos"], {"id": id})
		elif nm["pulses"] > 0:
			nm["timer"] -= delta
			if nm["timer"] <= 0.0:
				nm["timer"] = Tuning.noisemaker_pulse_interval
				nm["pulses"] -= 1
				emit_sound(nm["pos"], Tuning.noise_noisemaker, "noisemaker")
				emit_cue("rattle", nm["pos"])
				if nm["pulses"] == 0:
					nm["idle"] = true
					_rpc_event.rpc("nm_idle", nm["pos"], {"id": id})


func _client_update_noisemakers(delta: float) -> void:
	for nm in noisemakers.values():
		if not nm["landed"]:
			_step_projectile(nm, delta)


func _nm_node(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	items_root.add_child(n)
	n.position = pos
	Geo.box(n, Vector3(0.12, 0.12, 0.12), Vector3.ZERO, Geo.mat(Color(0.7, 0.6, 0.25), 0.4, Color(0.6, 0.45, 0.1), 0.4), 0, 0.5)
	return n


# ================================================================== replication

func emit_cue(kind: String, pos: Vector3, data: Dictionary = {}) -> void:
	if is_server:
		_rpc_event.rpc(kind, pos, data)


func _send_snapshot() -> void:
	_snap_count += 1
	smoke["max_players"] = maxi(smoke["max_players"], players.size())
	for p in players.values():
		if not p.is_local:
			var sp: Vector3 = world.spawn_points[p.slot % world.spawn_points.size()]
			smoke["remote_moved"] = maxf(smoke["remote_moved"], p.global_position.distance_to(sp))
	var ps: Array = []
	for p in players.values():
		var flags := 0
		if p.lantern_open: flags |= 1
		if p.sprinting: flags |= 2
		if p.moving: flags |= 4
		if p.inside_cave: flags |= 8
		match p.cover:
			"grass": flags |= 16
			"bush": flags |= 32
			"canopy": flags |= 64
		ps.append([p.peer_id, p.global_position, p.yaw, p.pitch, p.stance, p.mode, p.stamina, flags, p.last_seq, p.tree_id, p.noisemakers, p.revive_progress, p.perch])
	var cs: Array = []
	for c in creatures.values():
		cs.append([c.cid, c.global_position, c.yaw, c.state, c.climbing, c.awake])
	var snap := {
		"t": match_time, "ph": phase, "pt": phase_time, "d": day_index, "n": nights_survived,
		"p": ps, "c": cs, "door": [world.cave["door_open"], world.cave["door_hp"]],
	}
	if _snap_count % 10 == 0:
		var dbg := {}
		for c in creatures.values():
			dbg[c.cid] = c.debug_text
		snap["dbg"] = dbg
	_rpc_snapshot.rpc(snap)


@rpc("authority", "unreliable_ordered")
func _rpc_snapshot(s: Dictionary) -> void:
	if is_server:
		return
	smoke["snapshots"] += 1
	var sample: float = float(s["t"]) - _wall()
	if not _have_offset:
		_time_offset = sample
		_have_offset = true
	else:
		_time_offset = lerpf(_time_offset, sample, 0.05)
	match_time = s["t"]
	phase = s["ph"]
	phase_time = s["pt"]
	day_index = s["d"]
	nights_survived = s["n"]
	for e in s["p"]:
		var p: Node = players.get(e[0])
		if p == null:
			continue
		var flags: int = e[7]
		p.mode = e[5]
		p.stamina = e[6]
		p.tree_id = e[9]
		p.noisemakers = e[10]
		p.revive_progress = e[11]
		p.perch = e[12]
		p.sprinting = (flags & 2) != 0
		p.inside_cave = (flags & 8) != 0
		p.cover = "grass" if flags & 16 else ("bush" if flags & 32 else ("canopy" if flags & 64 else ""))
		p.apply_remote_snapshot(s["t"], e[1], e[2], e[3])
		if p.is_local:
			if p.mode != D.Mode.NORMAL and p.mode != D.Mode.DOWNED:
				p.stance = e[4]
			if p.mode == D.Mode.DOWNED:
				p.lantern_open = false
			p.reconcile(e[8], e[1])
			smoke["max_err"] = maxf(smoke["max_err"], p.last_err)
		else:
			if p.stance != e[4]:
				p.stance = e[4]
				p._apply_shape()
			p.lantern_open = (flags & 1) != 0
	for e in s["c"]:
		var c: Node = creatures.get(e[0])
		if c == null:
			continue
		c.state = e[3]
		c.climbing = e[4]
		if bool(e[5]) != c.awake:
			c._set_awake(e[5])
			c.snaps.clear()
			c.global_position = e[1]
		c.apply_remote_snapshot(s["t"], e[1], e[2])
	var door: Array = s["door"]
	if door[0] != world.cave["door_open"] or absf(door[1] - world.cave["door_hp"]) > 0.01:
		world.set_door(door[0], door[1])
	if s.has("dbg"):
		for k in s["dbg"]:
			if creatures.has(k):
				creatures[k].debug_text = s["dbg"][k]


@rpc("authority", "call_local", "reliable")
func _rpc_event(kind: String, pos: Vector3, data: Dictionary) -> void:
	_on_event(kind, pos, data)


func _on_event(kind: String, pos: Vector3, data: Dictionary) -> void:
	var lp := local_player
	var near_tree: bool = lp != null and data.has("tree") and lp.tree_id == data["tree"]
	match kind:
		"phase":
			if hud:
				hud.phase_banner(data["phase"], data["day"])
		"call":
			Sfx.play_3d("call", pos, 4.0, 1.0, 200.0)
			if hud:
				hud.notice("A long call rises from underground.")
		"screech":
			Sfx.play_3d("screech", pos, 2.0, randf_range(0.9, 1.05), 90.0)
			if hud:
				hud.cue("It's hunting", pos, true)
		"chitter":
			Sfx.play_3d("chitter", pos, -2.0, randf_range(0.9, 1.1), 40.0)
		"scrape":
			Sfx.play_3d("scrape", pos, 2.0, randf_range(0.85, 1.1), 60.0)
			if hud:
				hud.cue("Bark scraping — something is climbing", pos, true)
			if near_tree:
				lp.add_shake(0.25)
		"deck_shake":
			Sfx.play_3d("branch", pos, 6.0, 0.7, 50.0)
			if near_tree:
				lp.add_shake(0.6)
			if hud:
				hud.cue("The canopy is shaking", pos, true)
		"branch":
			Sfx.play_3d("branch", pos, -6.0, randf_range(0.9, 1.2), 30.0)
		"rope":
			Sfx.play_3d("rope", pos, -4.0, 1.0, 30.0)
		"door":
			Sfx.play_3d("door_creak", pos, -2.0, randf_range(0.9, 1.1), 40.0)
		"door_hit":
			Sfx.play_3d("door_hit", pos, 6.0, randf_range(0.85, 1.0), 70.0)
			if hud:
				hud.cue("Door under pressure", pos, true)
			if lp and lp.inside_cave:
				lp.add_shake(0.35)
		"breach_warn":
			Sfx.play_3d("breach_warn", pos, 6.0, 1.0, 60.0)
			if hud:
				hud.cue("The door is about to give!", pos, true)
		"door_break":
			Sfx.play_3d("door_hit", pos, 10.0, 0.6, 90.0)
			if hud:
				hud.cue("The door broke", pos, true)
			if lp and lp.inside_cave:
				lp.add_shake(0.8)
		"down":
			Sfx.play_3d("down", pos, 4.0, 1.0, 80.0)
			if hud:
				hud.notice("%s is down! Crawl to cover; hold E beside them to revive." % data.get("name", "Someone"))
			if lp and data.get("peer", -1) == lp.peer_id:
				lp.add_shake(1.0)
				want_stance = D.Stance.PRONE
		"revived":
			if hud:
				hud.notice("%s was revived by %s." % [data.get("name", "?"), data.get("by", "?")])
			if lp and lp.display_name == data.get("name", ""):
				want_stance = D.Stance.CROUCH
		"rattle":
			Sfx.play_3d("rattle", pos, 4.0, randf_range(0.95, 1.05), 70.0)
		"nm_spawn":
			var id: int = data["id"]
			if not noisemakers.has(id):
				noisemakers[id] = {"pos": pos, "vel": data["vel"], "landed": false, "pulses": 0, "timer": 0.0, "idle": false, "flight": 0.0, "node": null}
			noisemakers[id]["node"] = _nm_node(pos)
		"nm_land":
			var id2: int = data["id"]
			if noisemakers.has(id2):
				noisemakers[id2]["landed"] = true
				noisemakers[id2]["pos"] = pos
				if noisemakers[id2]["node"]:
					noisemakers[id2]["node"].position = pos
		"nm_idle":
			var id3: int = data["id"]
			if noisemakers.has(id3):
				noisemakers[id3]["idle"] = true
		"nm_remove":
			var id4: int = data["id"]
			if noisemakers.has(id4):
				if noisemakers[id4]["node"]:
					noisemakers[id4]["node"].queue_free()
				noisemakers.erase(id4)
			elif is_server:
				pass


# ================================================================== HUD helpers

func prompt_text() -> String:
	var p := local_player
	if p == null or over:
		return ""
	match p.mode:
		D.Mode.DOWNED:
			return "You are down. Crawl to cover — a teammate can revive you."
		D.Mode.CLIMBING:
			return ""
		D.Mode.PERCHED:
			match p.perch:
				"perch": return "[E] Climb higher     [Space] Climb down"
				"canopy": return "[Space] Climb down"
				"partway": return "Hanging on — no perch here.     [Space] Let go"
			return ""
	var it := best_interactable(p)
	if it.is_empty():
		return ""
	match it["kind"]:
		"climb":
			var t: Dictionary = world.tree_by_id(it["tree"])
			if t["ladder"]:
				return "[E] Climb the ladder"
			match t["type"]:
				"low": return "[E] Climb to the low branch"
				"rough": return "[E] Climb the rough trunk (stamina)"
				"bare": return "[E] Grab the bare trunk"
		"door":
			return "[E] Open the door" if not world.cave["door_open"] else "[E] Close the door"
		"deck_down":
			return "[E] Climb down the trunk"
		"rope":
			return "[E] / [R] Rope down"
		"pickup":
			return "[E] Pick up noisemaker"
		"revive":
			var q: Node = players.get(it["id"])
			var pct := 0
			if q:
				pct = int(q.revive_progress * 100.0)
			return "[Hold E] Revive %s  %d%%" % [q.display_name if q else "?", pct]
	return ""


func smoke_report() -> String:
	if is_server:
		return "SMOKE host players=%d inputs=%d remote_moved=%.2f phase=%s" % [smoke["max_players"], smoke["inputs"], smoke["remote_moved"], D.PHASE_NAMES[phase]]
	var lm := 0.0
	if local_player:
		lm = local_player.global_position.distance_to(_spawn_pos)
	return "SMOKE client snapshots=%d moved=%.2f max_err=%.3f phase=%s" % [smoke["snapshots"], lm, smoke["max_err"], D.PHASE_NAMES[phase]]
