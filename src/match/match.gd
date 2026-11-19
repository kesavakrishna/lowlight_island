extends Node3D
## One run. Exists on every peer at /root/Main/Match.
## Host: owns the clock, player state, creatures, structures, items and results.
## Clients: send input intent, predict their own avatar, render replicated state.

const D = preload("res://src/core/defs.gd")
const Geo = preload("res://src/world/geo.gd")
const PlayerScript = preload("res://src/player/player.gd")
const CreatureScript = preload("res://src/creature/creature.gd")
const Clearing = preload("res://src/world/test_clearing.gd")
const IslandWorld = preload("res://src/world/island_world.gd")
const EnvCtl = preload("res://src/world/environment_ctl.gd")
const Hud = preload("res://src/ui/hud.gd")
const Objectives = preload("res://src/match/objectives.gd")
const CreatureBody = preload("res://src/creature/creature_body.gd")

var params: Dictionary = {}
var is_server := false
var headless := false
var world: Node3D
var objectives: RefCounted = null
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
var traces: Dictionary = {}          # host: trace bin -> evidence of the crew being there
var _trace_t := 0.0
var _types_met: Dictionary = {}
var _new_type_tonight := false
var captives: Dictionary = {}        # host: burrow index -> [peer ids]
var raid_progress: Dictionary = {}   # burrow index -> 0..1
var _shove_cd: Dictionary = {}

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
var _bot_yaw0 := 0.0
var _spawn_pos := Vector3.ZERO
var _client_raids: Dictionary = {}
var smoke := {"snapshots": 0, "inputs": 0, "max_err": 0.0, "max_players": 0, "remote_moved": 0.0}


func setup(p: Dictionary) -> void:
	params = p


func _ready() -> void:
	name = "Match"
	is_server = multiplayer.is_server()
	headless = DisplayServer.get_name() == "headless"
	var t_build := Time.get_ticks_msec()
	if params.get("world", "clearing") == "island":
		world = IslandWorld.new()
		world.name = "World"
		add_child(world)
		if not world.build(int(params.get("seed", 0)), int(params.get("attempt", -1))):
			push_error("could not rebuild the host's island")
		elif params.has("checksum") and int(params["checksum"]) != world.checksum:
			push_error("island checksum mismatch: host %d, here %d" % [int(params["checksum"]), world.checksum])
	else:
		world = Clearing.new()
		world.name = "World"
		add_child(world)
		world.build(int(params.get("seed", 0)))
	print("[match] world built in %d ms" % (Time.get_ticks_msec() - t_build))
	if not headless:
		env = EnvCtl.new()
		env.match_ref = self
		add_child(env)
	players_root = _child_root("Players")
	creatures_root = _child_root("Creatures")
	items_root = _child_root("Items")
	objectives = Objectives.new()
	objectives.setup(self)
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
	Net.peer_rejoined.connect(_on_peer_rejoined)
	if params.get("rejoin", false) and hud:
		hud.big_message("Back in the run", "Your slot was kept while you were away.")
	if local_player:
		look_yaw = local_player.yaw
		_bot_yaw0 = local_player.yaw
		_spawn_pos = local_player.global_position
	if is_server:
		_ready_set[multiplayer.get_unique_id()] = true
	else:
		_rpc_client_ready.rpc_id(1)
	if is_server and dev_start_phase >= 0:
		_set_phase(dev_start_phase)
	print("[match] started seed=%d players=%d server=%s" % [int(params.get("seed", 0)), players.size(), is_server])
	if "landmarks" in world:
		var cave_txt := []
		for c in world.caves:
			cave_txt.append("%s f%d" % [c["door_point"].snapped(Vector3.ONE * 0.1), c["facing"]])
		print("[match] island landmarks %s caves %s" % [world.landmarks, cave_txt])


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
	p.last_dry = p.global_position
	p.yaw = atan2(sp.x, sp.z)   # face the clearing center
	players[pid] = p
	if p.is_local:
		local_player = p


func _spawn_creatures() -> void:
	# The whole pool exists from the start (dormant) so every peer agrees on ids;
	# nightly escalation decides how many wake. Milestone 5 adds the other types.
	var count: int = Tuning.max_creatures if params.get("world", "clearing") == "island" else 1
	var types := creature_types_for(int(params.get("seed", 0)), count, params.get("world", "clearing") == "island")
	for i in count:
		var c := CreatureScript.new()
		c.setup(i, types[i], is_server, self, world, int(params.get("seed", 0)))
		creatures_root.add_child(c)
		c.global_position = _burrow_for(i)
		creatures[i] = c


## Which type each individual in the pool is. Night one draws one or two types; later
## individuals (woken as nights escalate) can be a type the crew hasn't met yet.
static func creature_types_for(seed_value: int, count: int, island: bool) -> Array:
	if not island:
		return ["stalker"]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 7
	var order: Array = D.CREATURE_TYPES.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	var out: Array = []
	for i in count:
		match i:
			0: out.append(order[0])
			1: out.append(order[0] if rng.randf() < 0.5 else order[1])
			2: out.append(order[1])
			3: out.append(order[2])
			4: out.append(order[3])
			_: out.append(order[rng.randi() % order.size()])
	return out


func burrow_list() -> Array:
	if "burrows" in world and not world.burrows.is_empty():
		return world.burrows
	return [world.burrow_pos]


func _burrow_for(i: int) -> Vector3:
	if "burrows" in world and not world.burrows.is_empty():
		var b: Vector3 = world.burrows[i % world.burrows.size()]
		return b + Vector3((i / world.burrows.size()) * 1.6, 0, 0)
	return world.burrow_pos + Vector3(i * 1.5, 0, 0)


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
		objectives.server_tick(delta)
		for c in creatures.values():
			c.server_tick(delta)
		sound_events.clear()
		_srv_revive(delta)
		_srv_tick_away(delta)
		_srv_traces(delta)
		_srv_drags()
		_srv_raids(delta)
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


func _process(delta: float) -> void:
	objectives.process_visuals(delta)
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
		_spectate_if_captured()
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
		D.Phase.DAY:
			if _new_type_tonight and day_index > 2:
				emit_cue("new_tracks", world.burrow_pos)
			_new_type_tonight = false
			# Evidence fades by day, but a shelter used night after night stays warm.
			for k in traces.keys():
				traces[k] *= Tuning.trace_day_keep
		D.Phase.DUSK:
			# First night past the threshold: they stop hiding. Make the shift unmistakable.
			if day_index == Tuning.escalation_threshold_night + 1:
				emit_cue("threshold", world.burrow_pos + Vector3(0, 1, 0))
		D.Phase.NIGHT:
			# Escalation: more individuals each night, each one stronger (Tuning.creature_stats).
			var count: int = mini(Tuning.patrol_count(day_index), creatures.size())
			var i := 0
			for c in creatures.values():
				if i < count:
					c.wake(day_index, _burrow_for(i))
					if not _types_met.has(c.ctype):
						_types_met[c.ctype] = true
						_new_type_tonight = true
				i += 1
			emit_cue("call", world.burrow_pos + Vector3(0, 1, 0), {"count": count})
		D.Phase.DAWN:
			nights_survived += 1
			objectives.on_phase(phase)
			var lurk: Array = world.lurk_points if "lurk_points" in world else []
			var li := 0
			for c in creatures.values():
				if objectives.boat_here() and c.awake and not lurk.is_empty():
					# Creatures linger in the shade along the route to the dock: the last leg is a run.
					c.lurk(lurk[li % lurk.size()])
					li += 1
				else:
					c.go_home()
	_broadcast_event("phase", Vector3.ZERO, {"phase": phase, "day": day_index})


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
	look_yaw = _bot_yaw0 + 0.3 * sin(_bot_t * 0.5)
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
	elif event.is_action_pressed("shove"):
		if lp.mode == D.Mode.NORMAL:
			request("shove", look_yaw, look_pitch)
	elif event.is_action_pressed("drop"):
		if lp.carrying:
			request("drop")
	elif event.is_action_pressed("repair"):
		request("repair")
	elif event.is_action_pressed("dev_skip_phase"):
		if is_server:
			request("skip_phase")


func _press_interact() -> void:
	var p := local_player
	if p.mode == D.Mode.PERCHED:
		request("perch", "up")
		return
	var it := best_interactable(p)
	if it.is_empty() or it["kind"] == "revive" or it["kind"] == "raid":
		return  # revive and raids are holds, carried in the input bits
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
		lp.speed_mult = _move_mult(lp.global_position)
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
	p.speed_mult = _move_mult(p.global_position)
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
	p.cave_id = world.cave_at(pos)
	p.inside_cave = p.cave_id >= 0
	if p.mode == D.Mode.NORMAL:
		p.tree_id = world.deck_tree_at(pos)
	if pos.y < world.ground_y(pos) - 10.0:
		p.global_position = world.spawn_points[0]  # safety net, never lose an avatar
	# Deep water: no swimming in v1. Turn back to the last dry footing.
	if p.mode == D.Mode.NORMAL or p.mode == D.Mode.DOWNED:
		if pos.y < 0.3 - 1.25 and world.has_method("in_water"):
			p.global_position = p.last_dry
			p.velocity = Vector3.ZERO
			notify(p, "Too deep to wade any further.")
		elif not _in_water(pos) and p.is_on_floor():
			p.last_dry = pos
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
			if _in_water(pos):
				r = maxf(r * 1.6, Tuning.noise_walk * 1.4)
				kind = "splashing"
			if p.tree_id >= 0:
				emit_sound(pos, maxf(r, Tuning.noise_branch), "branch", {"tree": p.tree_id})
				emit_cue("branch", pos)
			else:
				emit_sound(pos, r, kind, {"peer": p.peer_id})
	elif p.mode == D.Mode.CLIMBING:
		p.branch_timer -= delta
		if p.branch_timer <= 0.0:
			p.branch_timer = 0.8
			emit_sound(pos, Tuning.noise_branch, "branch", {"tree": p.tree_id})
			emit_cue("branch", pos)


func _move_mult(pos: Vector3) -> float:
	return world.move_mult(pos) if world.has_method("move_mult") else 1.0


func _in_water(pos: Vector3) -> bool:
	return world.has_method("in_water") and world.in_water(pos)


func emit_sound(pos: Vector3, radius: float, kind: String, extra: Dictionary = {}) -> void:
	var ev := {"pos": pos, "radius": radius, "kind": kind}
	var cid: int = world.cave_at(pos)
	ev["in_cave"] = cid >= 0
	ev["cave"] = cid
	ev["muffled"] = cid >= 0 and world.door_blocks(cid)
	ev["ground"] = world.ground_kind(pos) if world.has_method("ground_kind") else "soil"
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
		"drop":
			if p.mode == D.Mode.NORMAL:
				objectives.drop_battery(p)
		"shove":
			if p.mode == D.Mode.NORMAL and typeof(a) == TYPE_FLOAT:
				_srv_shove(p)
		"repair":
			if p.mode == D.Mode.NORMAL:
				objectives.repair(p)
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
				if p.global_position.y - world.ground_y(p.global_position) < 1.5:
					out.append(it)
			"door":
				if world.caves[it["cave"]]["door_hp"] > 0.0:
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
	out.append_array(objectives.candidates(p))
	var bl: Array = burrow_list()
	for bi in bl.size():
		if not captive_names(bi).is_empty():
			out.append({"kind": "raid", "id": bi, "pos": (bl[bi] as Vector3) + Vector3(0, 0.4, 0)})
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
			_srv_toggle_door(p, it["cave"])
		"deck_down":
			var t: Dictionary = world.tree_by_id(it["tree"])
			var dur := Tuning.climb_ladder_time if t["ladder"] else Tuning.climb_down_time * 1.4
			_begin_climb(p, t, _anchor(t, "ground", _dir_from_trunk(t, p.global_position)), dur, "ground")
		"rope":
			var t2: Dictionary = world.tree_by_id(it["tree"])
			_begin_climb(p, t2, t2["rope_land"], Tuning.rope_time, "rope", t2["rope_top"])
			for c in creatures.values():
				c.notice_rope(t2["id"], p)
			emit_sound(t2["rope_top"], Tuning.noise_rope, "rope")
			emit_cue("rope", t2["rope_top"])
		"pickup":
			if noisemakers.has(id):
				p.noisemakers += 1
				noisemakers.erase(id)
				_broadcast_event("nm_remove", Vector3.ZERO, {"id": id})
		_:
			objectives.interact(p, kind, id)


func _srv_toggle_door(p: Node, cid: int) -> void:
	var cave: Dictionary = world.caves[cid]
	var hp: float = cave["door_hp"]
	if hp <= 0.0:
		return
	var open: bool = not cave["door_open"]
	if not open:
		var dc: Vector3 = cave["door_center"]
		for q in players.values():
			if Vector2(q.global_position.x - dc.x, q.global_position.z - dc.z).length() < 0.55:
				notify(p, "Someone is standing in the doorway.")
				return
	world.set_door(open, hp, cid)
	emit_sound(cave["door_center"], Tuning.noise_door, "door")
	emit_cue("door", cave["door_center"])


func damage_door(amount: float, cid: int, _by: Node) -> void:
	var cave: Dictionary = world.caves[cid]
	var hp: float = maxf(0.0, cave["door_hp"] - amount)
	world.set_door(cave["door_open"], hp, cid)
	var dc: Vector3 = cave["door_center"]
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
			if t.has("perch_pos"):
				return t["perch_pos"]
			return base + (t["perch_dir"] as Vector3) * (r + 0.55) + Vector3(0, t["perch_h"] + 0.25, 0)
		"canopy":
			if not t["deck"] and t.has("canopy_pos"):
				return t["canopy_pos"]
			if t["deck"]:
				return base + dir * (r + 0.7) + Vector3(0, t["deck_h"] + 0.02, 0)
			return base + dir * (r + 0.4) + Vector3(0, t["canopy_h"] - 0.6, 0)
		"partway":
			return base + dir * (r + 0.4) + Vector3(0, t["partway_h"], 0)
	return base + dir * (r + 0.55)


func _srv_start_climb(p: Node, t: Dictionary) -> void:
	if t.is_empty() or p.mode != D.Mode.NORMAL or p.global_position.y - t["pos"].y > 1.5:
		return
	if p.carrying:
		notify(p, "The battery is too heavy to climb with. Put it down first [Q].")
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
	if p.carrying:
		objectives.drop_battery(p)   # a downed carrier drops it where the crew can get it back
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
		if q.mode != D.Mode.DOWNED or q.dragged_by >= 0:
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
	var aboard := 0
	for p in players.values():
		if p.mode == D.Mode.ESCAPED:
			aboard += 1
		elif p.mode != D.Mode.DOWNED and p.mode != D.Mode.CAPTURED:
			return
	# Everyone left on the island is down or captured. Anyone aboard still counts as a crew win.
	end_match(aboard > 0)


func end_match(won: bool) -> void:
	if over:
		return
	over = true
	var crew: Array = []
	for p in players.values():
		crew.append([p.display_name, p.mode == D.Mode.ESCAPED])
	var summary := {"won": won, "nights": nights_survived, "day": day_index, "crew": crew}
	_rpc_game_over(summary)
	for pid in _ready_peers():
		_rpc_game_over.rpc_id(pid, summary)


@rpc("authority", "call_local", "reliable")
func _rpc_game_over(summary: Dictionary) -> void:
	over = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hud:
		hud.show_results(summary)


func _on_peer_left(pid: int) -> void:
	if not is_server:
		return
	var p: Node = players.get(pid)
	if p == null:
		return
	if over:
		_remove_player(pid)
		_send_ready("_rpc_player_left", [pid])
		return
	# Keep the slot: the avatar stays in the match (and keeps what it carries) for a while.
	p.away = true
	p.grace = Tuning.reconnect_grace
	p.input_queue.clear()
	p.last_input = {"yaw": p.yaw, "pitch": p.pitch, "stance": p.stance}
	p.lantern_open = false
	emit_cue("away", p.global_position, {"name": p.display_name})


func _srv_tick_away(delta: float) -> void:
	for pid in players.keys():
		var p: Node = players[pid]
		if not p.away:
			continue
		p.grace -= delta
		if p.grace <= 0.0:
			if p.carrying:
				objectives.drop_battery(p)
			_remove_player(pid)
			_send_ready("_rpc_player_left", [pid])
			Net.forget_peer(pid)


## Host: a dropped player came back on a new connection. Hand them their avatar.
func _on_peer_rejoined(old_id: int, new_id: int) -> void:
	if not is_server or not players.has(old_id):
		return
	_rekey(old_id, new_id)
	var p: Node = players[new_id]
	p.away = false
	p.grace = 0.0
	p.last_seq = 0            # the new connection numbers its inputs from zero
	p.input_queue.clear()
	_ready_set.erase(old_id)
	for pid in _ready_peers():
		if pid != new_id:
			_rpc_rekey.rpc_id(pid, old_id, new_id)
	emit_cue("back", p.global_position, {"name": p.display_name})


func _rekey(old_id: int, new_id: int) -> void:
	var p: Node = players[old_id]
	players.erase(old_id)
	players[new_id] = p
	p.peer_id = new_id
	p.name = str(new_id)
	if objectives.carrier == old_id:
		objectives.carrier = new_id
	var i: int = objectives.escaped.find(old_id)
	if i >= 0:
		objectives.escaped[i] = new_id
	for c in creatures.values():
		if c.target_peer == old_id:
			c.target_peer = new_id
		if c.awareness.has(old_id):
			c.awareness[new_id] = c.awareness[old_id]
			c.awareness.erase(old_id)


@rpc("authority", "reliable")
func _rpc_rekey(old_id: int, new_id: int) -> void:
	if players.has(old_id):
		_rekey(old_id, new_id)


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
	_broadcast_event("nm_spawn", pos, {"id": id, "vel": vel})


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
				_broadcast_event("nm_land", nm["pos"], {"id": id})
		elif nm["pulses"] > 0:
			nm["timer"] -= delta
			if nm["timer"] <= 0.0:
				nm["timer"] = Tuning.noisemaker_pulse_interval
				nm["pulses"] -= 1
				emit_sound(nm["pos"], Tuning.noise_noisemaker, "noisemaker")
				emit_cue("rattle", nm["pos"])
				if nm["pulses"] == 0:
					nm["idle"] = true
					_broadcast_event("nm_idle", nm["pos"], {"id": id})


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


# ================================================================== creatures: shove, drag, capture, raids, traces

func _srv_shove(p: Node) -> void:
	if match_time - _shove_cd.get(p.peer_id, -99.0) < Tuning.shove_cooldown:
		return
	if p.stamina < Tuning.shove_stamina * 0.6:
		notify(p, "Too winded to shove.")
		return
	var eye: Vector3 = p.eye_position()
	var look: Vector3 = p.look_dir()
	var target: Node = null
	var best := INF
	for c in creatures.values():
		if not c.awake or c.underground:
			continue
		var to: Vector3 = c.global_position + Vector3(0, 1.0, 0) - eye
		if to.length() < Tuning.shove_range and to.normalized().dot(look) > 0.4 and to.length() < best:
			best = to.length()
			target = c
	_shove_cd[p.peer_id] = match_time
	p.stamina = maxf(0.0, p.stamina - Tuning.shove_stamina)
	p.regen_timer = Tuning.stamina_regen_delay * 2.0
	if target and target.on_shoved(p):
		emit_cue("shove", target.global_position + Vector3(0, 1.2, 0), {"name": p.display_name})


func attach_drag(p: Node, c: Node) -> void:
	p.dragged_by = c.cid


func release_drag(peer: int) -> void:
	var p: Node = players.get(peer)
	if p:
		p.dragged_by = -1


func _srv_drags() -> void:
	for p in players.values():
		if p.dragged_by < 0:
			continue
		var c: Node = creatures.get(p.dragged_by)
		if c == null or c.state != D.CState.DRAG or p.mode != D.Mode.DOWNED:
			p.dragged_by = -1
			continue
		var behind: Vector3 = c.global_position - c.forward() * 1.1
		behind.y = world.ground_y(behind) + 0.05
		p.global_position = behind
		p.velocity = Vector3.ZERO


func capture_player(p: Node, burrow: Vector3, _c: Node) -> void:
	var bl: Array = burrow_list()
	var bi := 0
	for i in bl.size():
		if (bl[i] as Vector3).distance_to(burrow) < (bl[bi] as Vector3).distance_to(burrow):
			bi = i
	p.dragged_by = -1
	p.mode = D.Mode.CAPTURED
	p.lantern_open = false
	if p.carrying:
		objectives.drop_battery(p)
	p.global_position = (bl[bi] as Vector3) + Vector3(0, -3.0, 0)
	if not captives.has(bi):
		captives[bi] = []
	captives[bi].append(p.peer_id)
	if objectives.enabled:
		objectives.burrow_known(bi)
	emit_cue("captured", bl[bi], {"name": p.display_name})


func captive_names(bi: int) -> Array:
	if not is_server:
		var r: Array = _client_raids.get(bi, [])
		return r[0] if not r.is_empty() else []
	var out: Array = []
	for pid in captives.get(bi, []):
		if players.has(pid):
			out.append(players[pid].display_name)
	return out


## Hold E at a burrow to free its captives. Sleeping creatures may stir - far more at night.
func _srv_raids(delta: float) -> void:
	var bl: Array = burrow_list()
	for bi in captives.keys():
		if (captives[bi] as Array).is_empty():
			continue
		var raider: Node = null
		for r in players.values():
			if r.mode == D.Mode.NORMAL and (int(r.last_input.get("btn", 0)) & D.BTN_INTERACT) != 0 and r.global_position.distance_to(bl[bi]) < 3.0:
				raider = r
				break
		if raider == null:
			raid_progress[bi] = maxf(0.0, raid_progress.get(bi, 0.0) - delta * 0.5)
			continue
		raid_progress[bi] = raid_progress.get(bi, 0.0) + delta / Tuning.raid_time
		emit_sound(bl[bi], 6.0, "digging", {"peer": raider.peer_id})
		var chance := Tuning.raid_wake_chance_day if daylight() > 0.5 else Tuning.raid_wake_chance_night
		for c in creatures.values():
			if c.state == D.CState.DORMANT and c.home.distance_to(bl[bi]) < 4.0 and randf() < chance * delta:
				c.wake(day_index, bl[bi])
				if daylight() > 0.5:
					c.lurk(bl[bi])   # sluggish in daylight: it stays near the burrow mouth
				emit_cue("surface", bl[bi])
		if raid_progress[bi] >= 1.0:
			raid_progress[bi] = 0.0
			var freed: Array = captives[bi]
			captives[bi] = []
			var k := 0
			for pid in freed:
				var q: Node = players.get(pid)
				if q == null:
					continue
				q.mode = D.Mode.NORMAL
				q.stamina = 40.0
				q.revive_progress = 0.0
				var a := TAU * k / maxf(freed.size(), 1.0)
				var out: Vector3 = (bl[bi] as Vector3) + Vector3(cos(a), 0, sin(a)) * 2.5
				out.y = world.ground_y(out) + 0.1
				q.global_position = out
				q.last_dry = out
				q.try_set_stance(D.Stance.CROUCH)
				k += 1
				emit_cue("freed", out, {"name": q.display_name})


## Evidence builds where the crew spends time (more people, more movement = faster) and
## fades when a place is vacant. Staying put night after night builds risk; moving resets it.
func _srv_traces(delta: float) -> void:
	_trace_t += delta
	if _trace_t < 0.5:
		return
	var dt := _trace_t
	_trace_t = 0.0
	var occupied := {}
	for p in players.values():
		if p.mode == D.Mode.ESCAPED or p.mode == D.Mode.CAPTURED or p.away:
			continue
		var key := _trace_key(p.global_position)
		var rate := 0.3 if (not p.moving and p.stance != D.Stance.STAND) else (2.0 if p.moving else 1.0)
		traces[key] = traces.get(key, 0.0) + rate * dt
		occupied[key] = true
	for key in traces.keys():
		if not occupied.has(key):
			traces[key] = traces[key] - Tuning.trace_fade_per_s * dt * maxf(traces[key], 1.0) * 0.1
			if traces[key] <= 0.05:
				traces.erase(key)


func _trace_key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / Tuning.trace_bin), floori(p.z / Tuning.trace_bin))


## The strongest trail within r metres of pos, or Vector3.INF.
func trace_hotspot_near(pos: Vector3, r: float) -> Vector3:
	var best := Vector3.INF
	var best_v := Tuning.trace_threshold
	var c := _trace_key(pos)
	var span := int(ceil(r / Tuning.trace_bin))
	for dj in range(-span, span + 1):
		for di in range(-span, span + 1):
			var k := c + Vector2i(di, dj)
			var v: float = traces.get(k, 0.0)
			if v > best_v:
				var center := Vector3((k.x + 0.5) * Tuning.trace_bin, 0, (k.y + 0.5) * Tuning.trace_bin)
				center.y = world.ground_y(center)
				if center.distance_to(pos) <= r + Tuning.trace_bin:
					best_v = v
					best = center
	return best


## Flush and wait: the nearest other calm creature goes and holds an exit, silent.
func recruit_holder(caller: Node, point: Vector3, face: Vector3, why: String) -> void:
	var pick: Node = null
	var best := 45.0
	for c in creatures.values():
		if c == caller or not c.awake or not c.is_calm():
			continue
		var d: float = c.global_position.distance_to(point)
		if d < best:
			best = d
			pick = c
	if pick:
		pick.hold_at(point, face, 20.0, why)


func shake_platform(_tree_id: int, _strength: float) -> void:
	pass   # built platforms take damage here (building at slots)


## A captured player's view: ride along with a teammate who's still out there.
func _spectate_if_captured() -> void:
	var lp := local_player
	if lp.camera == null:
		return
	if lp.mode != D.Mode.CAPTURED:
		if lp.camera.top_level:
			lp.camera.top_level = false
			lp.camera.transform = Transform3D.IDENTITY
		return
	var watch: Node = null
	for p in players.values():
		if p != lp and (p.mode == D.Mode.NORMAL or p.mode == D.Mode.CLIMBING or p.mode == D.Mode.PERCHED or p.mode == D.Mode.DOWNED):
			watch = p
			break
	if watch == null:
		return
	lp.camera.top_level = true
	var eye: Vector3 = watch.global_position + Vector3(0, 2.3, 0) - Vector3(-sin(watch.yaw), 0, -cos(watch.yaw)) * 2.6
	lp.camera.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(watch.global_position + Vector3(0, 1.2, 0), Vector3.UP)


# ================================================================== replication

## Host: peers whose match scene is built and can receive match traffic.
## A client joining (or rejoining) builds its island first, then reports in.
var _ready_set: Dictionary = {}


func _ready_peers() -> Array:
	var out: Array = []
	for pid in _ready_set.keys():
		if pid != multiplayer.get_unique_id() and players.has(pid) and not players[pid].away:
			out.append(pid)
	return out


func _send_ready(method: String, args: Array) -> void:
	for pid in _ready_peers():
		callv("rpc_id", [pid, method] + args)


func _broadcast_event(kind: String, pos: Vector3, data: Dictionary) -> void:
	_on_event(kind, pos, data)
	for pid in _ready_peers():
		_rpc_event.rpc_id(pid, kind, pos, data)


@rpc("any_peer", "reliable")
func _rpc_client_ready() -> void:
	if is_server:
		_ready_set[multiplayer.get_remote_sender_id()] = true


func emit_cue(kind: String, pos: Vector3, data: Dictionary = {}) -> void:
	if is_server:
		_broadcast_event(kind, pos, data)


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
		if p.carrying: flags |= 128
		if p.away: flags |= 256
		ps.append([p.peer_id, p.global_position, p.yaw, p.pitch, p.stance, p.mode, p.stamina, flags, p.last_seq, p.tree_id, p.noisemakers, p.revive_progress, p.perch, p.wood, p.nerve, p.dragged_by, p.lean])
	var cs: Array = []
	for c in creatures.values():
		cs.append([c.cid, c.global_position, c.yaw, c.state, c.climbing, c.awake, c.underground, c.scars])
	var raids := {}
	for bi in captives:
		raids[bi] = [captive_names(bi), raid_progress.get(bi, 0.0)]
	var snap := {
		"raids": raids,
		"t": match_time, "ph": phase, "pt": phase_time, "d": day_index, "n": nights_survived,
		"p": ps, "c": cs, "doors": _door_states(), "obj": objectives.serialize(),
	}
	if _snap_count % 10 == 0:
		var dbg := {}
		for c in creatures.values():
			dbg[c.cid] = c.debug_text
		snap["dbg"] = dbg
	for pid in _ready_peers():
		_rpc_snapshot.rpc_id(pid, snap)


func _door_states() -> Array:
	var out: Array = []
	for c in world.caves:
		out.append([c["door_open"], c["door_hp"]])
	return out


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
		p.carrying = (flags & 128) != 0
		p.nerve = e[14]
		p.dragged_by = e[15]
		if not p.is_local:
			p.lean = e[16]
		p.away = (flags & 256) != 0
		p.wood = e[13]
		p.inside_cave = (flags & 8) != 0
		p.cave_id = world.cave_at(p.global_position) if p.inside_cave else -1
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
		c.underground = e[6]
		if c.scars != e[7]:
			c.scars = e[7]
		if bool(e[5]) != c.awake:
			c._set_awake(e[5])
			c.snaps.clear()
			c.global_position = e[1]
		c.apply_remote_snapshot(s["t"], e[1], e[2])
	var doors: Array = s["doors"]
	for i in mini(doors.size(), world.caves.size()):
		var cv: Dictionary = world.caves[i]
		if doors[i][0] != cv["door_open"] or absf(doors[i][1] - cv["door_hp"]) > 0.01:
			world.set_door(doors[i][0], doors[i][1], i)
	objectives.apply(s["obj"])
	_client_raids = s.get("raids", {})
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
				var n: int = data.get("count", 1)
				hud.notice("A long call rises from underground." if n <= 1 else "Calls rise from underground - more than one voice.")
		"threshold":
			Sfx.play_3d("call", pos, 10.0, 0.8, 300.0)
			Sfx.play_3d("screech", pos, 6.0, 0.7, 300.0)
			if hud:
				hud.big_message("They stop hiding", "The keeper's last entry: \"After the fourth night they stop hiding.\"")
		"found":
			if hud:
				hud.notice("Found %s." % data.get("what", "it"))
		"battery_pick":
			Sfx.play_3d("step", pos, 0.0, 0.6, 20.0)
			if hud:
				hud.notice("%s picked up the battery." % data.get("name", "Someone"))
		"battery_drop":
			Sfx.play_3d("down", pos, -6.0, 1.6, 25.0)
			if hud:
				hud.notice("The battery is on the ground.")
		"radio_powered":
			Sfx.play_3d("door_creak", pos, 0.0, 2.0, 30.0)
			if hud:
				hud.big_message("The radio has power", "Run the broadcast after dark. It will light up the shed - and they will come.")
		"broadcast_on":
			if hud:
				hud.notice("The transmitter hums to life. Someone has to stay with it.")
		"broadcast_off":
			if hud:
				hud.notice("The transmitter goes quiet. Progress is kept.")
		"broadcast_done":
			if hud:
				hud.big_message("The call went out", "A boat will come to the old dock at dawn. Survive until then.")
		"boat_arrived":
			Sfx.play_3d("call", pos, 2.0, 2.2, 400.0)
			if hud:
				hud.big_message("The boat is here", "Get to the old dock before it leaves. They are lingering in the shade.")
		"boat_left":
			if hud:
				hud.big_message("The boat left", "Nobody made it aboard. The call has to go out again.")
		"boarded":
			if hud:
				hud.notice("%s is aboard." % data.get("name", "Someone"))
		"ccall":
			var cc: Array = CreatureBody.CALLS.get(data.get("type", "stalker"), CreatureBody.CALLS["stalker"])
			Sfx.play_3d(cc[0], pos, cc[2], cc[1], 220.0)
		"shriek":
			Sfx.play_3d("screech", pos, 8.0, 1.4, 80.0)
			if hud:
				hud.cue("It recoils from the light", pos, false)
		"dig":
			Sfx.play_3d("creature_step", pos, 4.0, 0.35, 45.0)
			if hud:
				hud.cue("Something went under the ground", pos, true)
		"surface":
			Sfx.play_3d("door_hit", pos, 2.0, 0.45, 50.0)
			if hud:
				hud.cue("The ground heaves", pos, true)
		"shove":
			Sfx.play_3d("door_hit", pos, 0.0, 1.4, 30.0)
			if hud:
				hud.notice("%s shoved it back!" % data.get("name", "Someone"))
		"captured":
			Sfx.play_3d("down", pos, 6.0, 0.6, 120.0)
			if hud:
				hud.big_message("%s was dragged underground" % data.get("name", "Someone"), "The burrow is on the map. By day the things inside are sluggish - raid it.")
		"freed":
			if hud:
				hud.big_message("%s is free" % data.get("name", "Someone"), "Get out of there before they wake.")
		"new_tracks":
			if hud:
				hud.notice("Unfamiliar tracks near the burrows this morning. Something new came up last night.")
		"away":
			if hud:
				hud.notice("%s lost their connection. Their slot is held for %d s." % [data.get("name", "Someone"), int(Tuning.reconnect_grace)])
		"back":
			if hud:
				hud.notice("%s is back." % data.get("name", "Someone"))
		"repair":
			Sfx.play_3d("door_hit", pos, -4.0, 1.5, 30.0)
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
		D.Mode.ESCAPED:
			return ""
		D.Mode.CAPTURED:
			return "Captured in a burrow. Your crew can raid it - by day the things inside are sluggish."
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
			return "[E] Open the door" if not world.caves[it["cave"]]["door_open"] else "[E] Close the door"
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
		"raid":
			return "[Hold E] Raid the burrow - free %s  %d%%" % [", ".join(captive_names(it["id"])), int(raid_progress.get(it["id"], 0.0) * 100.0)]
	return objectives.prompt(it)


func smoke_report() -> String:
	if is_server:
		return "SMOKE host players=%d inputs=%d remote_moved=%.2f phase=%s" % [smoke["max_players"], smoke["inputs"], smoke["remote_moved"], D.PHASE_NAMES[phase]]
	var lm := 0.0
	if local_player:
		lm = local_player.global_position.distance_to(_spawn_pos)
	return "SMOKE client snapshots=%d moved=%.2f max_err=%.3f phase=%s" % [smoke["snapshots"], lm, smoke["max_err"], D.PHASE_NAMES[phase]]
