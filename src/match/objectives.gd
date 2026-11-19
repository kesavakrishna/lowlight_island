extends RefCounted
## The escape objective chain (milestone 4): crash -> battery -> radio shed -> broadcast -> dock.
## The host owns every value here; clients mirror it from snapshots and draw it.
## One authoritative battery state from spawn to pickup, drop and installation.

const D = preload("res://src/core/defs.gd")
const Geo = preload("res://src/world/geo.gd")

enum Bat { SITE, CARRIED, DROPPED, INSTALLED }

var m: Node = null                 # match.gd
var enabled := false               # only generated islands have the objective chain

# ---- replicated state
var battery_state: int = Bat.SITE
var battery_pos := Vector3.ZERO
var carrier := -1
var radio_powered := false
var broadcast := 0.0               # 0..1, kept when interrupted
var broadcast_running := false     # the crew chose to transmit
var broadcast_active := false      # running, tended, after dark: loud and bright right now
var broadcast_done := false
var boat_due := false
var boat_window := -1.0            # seconds left at the dock, -1 when no boat
var escaped: Array = []            # peer ids aboard
var dock_known := false
var battery_found := false
var caves_known: Array = []        # cave ids someone has seen
var burrows_known: Array = []      # burrow indices someone has seen (or been dragged into)
var wood_amounts: Array = []

# ---- host bookkeeping
var _hum_timer := 0.0
var _gather_cd := {}

# ---- visuals (every peer)
var _battery_node: Node3D
var _radio_light: OmniLight3D
var _beacon: OmniLight3D
var _hum: AudioStreamPlayer3D
var _boat: Node3D
var _wood_nodes: Array = []


func setup(p_match: Node) -> void:
	m = p_match
	var w: Node = m.world
	enabled = "landmarks" in w and not w.landmarks.is_empty()
	if not enabled:
		return
	battery_pos = w.battery_spot
	for wp in w.wood_piles:
		wood_amounts.append(int(wp["amount"]))
	caves_known.resize(w.caves.size())
	caves_known.fill(false)
	burrows_known.resize(w.burrows.size())
	burrows_known.fill(false)
	_build_visuals()


# ================================================================== host

func server_tick(delta: float) -> void:
	if not enabled:
		return
	var w: Node = m.world
	# Battery follows its carrier; a missing carrier drops it where they were.
	if battery_state == Bat.CARRIED:
		var c: Node = m.players.get(carrier)
		if c == null or c.mode == D.Mode.ESCAPED:
			battery_state = Bat.DROPPED
			carrier = -1
		else:
			battery_pos = c.global_position
	# Discovery shared by the crew.
	for p in m.players.values():
		if p.mode == D.Mode.ESCAPED:
			continue
		var pos: Vector3 = p.global_position
		if not battery_found and pos.distance_to(battery_pos) < 10.0:
			battery_found = true
			m.emit_cue("found", battery_pos, {"what": "the battery"})
		if not dock_known and pos.distance_to(w.landmarks["dock"]) < 35.0:
			dock_known = true
		for i in w.caves.size():
			if not caves_known[i] and pos.distance_to(w.caves[i]["door_point"]) < 25.0:
				caves_known[i] = true
		for i in w.burrows.size():
			if not burrows_known[i] and pos.distance_to(w.burrows[i]) < 20.0:
				burrows_known[i] = true
	_tick_broadcast(delta)
	_tick_boat(delta)


func _tick_broadcast(delta: float) -> void:
	var w: Node = m.world
	var after_dark: bool = m.phase == D.Phase.DUSK or m.phase == D.Phase.NIGHT
	var tended := false
	for p in m.players.values():
		if p.mode == D.Mode.NORMAL and p.global_position.distance_to(w.radio_bench) < Tuning.broadcast_tend_radius:
			tended = true
			break
	broadcast_active = radio_powered and broadcast_running and not broadcast_done and tended and after_dark
	if not broadcast_active:
		return
	broadcast = minf(1.0, broadcast + delta / Tuning.broadcast_time)
	_hum_timer -= delta
	if _hum_timer <= 0.0:
		_hum_timer = 2.5
		# Loud and bright: every creature in range converges on the shed.
		m.emit_sound(w.radio_bench, Tuning.broadcast_noise, "broadcast")
	if broadcast >= 1.0:
		broadcast_done = true
		broadcast_running = false
		broadcast_active = false
		boat_due = true
		dock_known = true
		m.emit_cue("broadcast_done", w.radio_bench)


func _tick_boat(delta: float) -> void:
	if boat_window < 0.0:
		return
	boat_window -= delta
	var remaining := 0
	var standing := 0
	for p in m.players.values():
		if p.mode != D.Mode.ESCAPED:
			remaining += 1
			if p.mode != D.Mode.DOWNED:
				standing += 1
	if not escaped.is_empty() and (remaining == 0 or standing == 0):
		boat_window = -1.0
		m.end_match(true)
		return
	if boat_window <= 0.0:
		boat_window = -1.0
		for c in m.creatures.values():
			c.go_home()
		if escaped.is_empty():
			# Nobody made it aboard: the boat leaves and the call must go out again.
			broadcast = 0.0
			broadcast_done = false
			m.emit_cue("boat_left", m.world.boat_pos)
		else:
			m.end_match(true)


## Called by the match when the phase changes (host).
func on_phase(phase: int) -> void:
	if not enabled:
		return
	if phase == D.Phase.DAWN and boat_due:
		boat_due = false
		boat_window = Tuning.boarding_window
		m.emit_cue("boat_arrived", m.world.boat_pos)


func burrow_known(i: int) -> void:
	if i >= 0 and i < burrows_known.size():
		burrows_known[i] = true


func boat_here() -> bool:
	return boat_window > 0.0


## Interactables this player could use right now.
func candidates(p: Node) -> Array:
	var out: Array = []
	if not enabled or p.mode != D.Mode.NORMAL:
		return out
	var w: Node = m.world
	if (battery_state == Bat.SITE or battery_state == Bat.DROPPED) and not p.carrying:
		out.append({"kind": "battery", "id": 0, "pos": battery_pos + Vector3(0, 0.3, 0)})
	if p.carrying:
		out.append({"kind": "install", "id": 0, "pos": w.radio_bench + Vector3(0, 0.9, 0)})
	elif radio_powered and not broadcast_done:
		out.append({"kind": "transmitter", "id": 0, "pos": w.radio_bench + Vector3(0, 0.9, 0)})
	for i in wood_amounts.size():
		if wood_amounts[i] > 0:
			out.append({"kind": "wood", "id": i, "pos": (w.wood_piles[i]["pos"] as Vector3) + Vector3(0, 0.4, 0)})
	if boat_here():
		out.append({"kind": "board", "id": 0, "pos": w.dock_board + Vector3(0, 0.8, 0)})
	return out


func interact(p: Node, kind: String, id: int) -> bool:
	if not enabled:
		return false
	var w: Node = m.world
	match kind:
		"battery":
			if p.carrying or (battery_state != Bat.SITE and battery_state != Bat.DROPPED):
				return true
			battery_state = Bat.CARRIED
			carrier = p.peer_id
			p.carrying = true
			p.sprinting = false
			battery_found = true
			m.emit_cue("battery_pick", battery_pos, {"name": p.display_name})
		"install":
			if not p.carrying:
				return true
			battery_state = Bat.INSTALLED
			battery_pos = w.radio_bench + Vector3(0, 0.95, 0)
			carrier = -1
			p.carrying = false
			radio_powered = true
			m.emit_cue("radio_powered", w.radio_bench)
		"transmitter":
			if not (m.phase == D.Phase.DUSK or m.phase == D.Phase.NIGHT):
				m.notify(p, "The keeper's log: the signal only carries after dark.")
				return true
			broadcast_running = not broadcast_running
			m.emit_cue("broadcast_on" if broadcast_running else "broadcast_off", w.radio_bench)
		"wood":
			var now: float = m.match_time
			if _gather_cd.get(p.peer_id, -10.0) > now - 0.6 or id < 0 or id >= wood_amounts.size():
				return true
			var take: int = mini(mini(Tuning.wood_take, wood_amounts[id]), Tuning.wood_cap - p.wood)
			if take <= 0:
				m.notify(p, "You can't carry more wood.")
				return true
			_gather_cd[p.peer_id] = now
			wood_amounts[id] -= take
			p.wood += take
			m.emit_sound(p.global_position, 4.0, "gathering")
		"board":
			if not boat_here():
				return true
			if p.carrying:
				drop_battery(p)
			escaped.append(p.peer_id)
			p.mode = D.Mode.ESCAPED
			p.lantern_open = false
			p.global_position = w.boat_pos + Vector3(0, 0.6, 0)
			p.velocity = Vector3.ZERO
			m.emit_cue("boarded", w.boat_pos, {"name": p.display_name})
		_:
			return false
	return true


## Put the battery down on valid, reachable ground where the crew can find it again.
func drop_battery(p: Node) -> void:
	if not enabled or not p.carrying:
		return
	var w: Node = m.world
	var pos: Vector3 = p.global_position
	if w.has_method("in_water") and w.in_water(pos):
		pos = p.last_dry
	pos.y = w.ground_y(pos) + 0.02
	battery_state = Bat.DROPPED
	battery_pos = pos
	carrier = -1
	p.carrying = false
	m.emit_cue("battery_drop", pos)


## V near a cave door: patch it (cheap) or rebuild a broken one (more wood).
func repair(p: Node) -> void:
	var w: Node = m.world
	for c in w.caves:
		var dc: Vector3 = c["door_center"]
		if p.global_position.distance_to(dc) > Tuning.interact_range + 0.8:
			continue
		var hp: float = c["door_hp"]
		if hp >= Tuning.door_hp:
			m.notify(p, "The door holds. Nothing to repair.")
			return
		var cost := Tuning.rebuild_cost if hp <= 0.0 else Tuning.repair_cost
		if p.wood < cost:
			m.notify(p, "You need %d wood for that." % cost)
			return
		p.wood -= cost
		var new_hp := Tuning.rebuild_hp if hp <= 0.0 else minf(Tuning.door_hp, hp + Tuning.repair_hp)
		w.set_door(false if hp <= 0.0 else c["door_open"], new_hp, c["id"])
		m.emit_sound(dc, Tuning.noise_door, "building")
		m.emit_cue("repair", dc)
		return
	m.notify(p, "Get next to a cave door to repair it.")


# ================================================================== replication

func serialize() -> Array:
	return [battery_state, battery_pos, carrier, radio_powered, broadcast, broadcast_running,
		broadcast_active, broadcast_done, boat_window, escaped, dock_known, battery_found, caves_known, wood_amounts, boat_due, burrows_known]


func apply(a: Array) -> void:
	if not enabled or a.size() < 15:
		return
	battery_state = a[0]
	battery_pos = a[1]
	carrier = a[2]
	radio_powered = a[3]
	broadcast = a[4]
	broadcast_running = a[5]
	broadcast_active = a[6]
	broadcast_done = a[7]
	boat_window = a[8]
	escaped = a[9]
	dock_known = a[10]
	battery_found = a[11]
	caves_known = a[12]
	wood_amounts = a[13]
	boat_due = a[14]
	if a.size() > 15:
		burrows_known = a[15]


# ================================================================== presentation

func objective_text() -> String:
	if not enabled:
		return ""
	var lp: Node = m.local_player
	if lp and lp.mode == D.Mode.ESCAPED:
		return "You're aboard. Waiting for the others..." if boat_here() else "You're aboard."
	if boat_here():
		return "The boat is at the old dock - get aboard!  %d s" % int(boat_window)
	if broadcast_done:
		return "The call went out. Survive the night, then reach the old dock at dawn."
	if radio_powered:
		if broadcast_running and not broadcast_active:
			return "Broadcast paused at %d%% - someone has to tend the transmitter after dark." % int(broadcast * 100.0)
		if broadcast > 0.0:
			return "Run the broadcast after dark: %d%% sent. It lights up the shed and draws them in." % int(broadcast * 100.0)
		return "The radio has power. Run the broadcast after dark - it will draw them in."
	match battery_state:
		Bat.CARRIED:
			if lp and carrier == lp.peer_id:
				return "Carry the battery to the radio shed. No sprinting or climbing with it.  [Q] put it down"
			var c: Node = m.players.get(carrier)
			return "%s is carrying the battery to the radio shed." % (c.display_name if c else "Someone")
		Bat.DROPPED:
			return "The battery is on the ground. Pick it up and get it to the radio shed."
	var w: Node = m.world
	var where := "a beached skiff on the shore" if w.battery_kind == "skiff" else "a salvage crate under a tree"
	return "Find the battery. The sketch from the wreck marks %s.  [M] map" % where


func prompt(it: Dictionary) -> String:
	match it["kind"]:
		"battery": return "[E] Pick up the battery (heavy)"
		"install": return "[E] Connect the battery to the radio"
		"transmitter":
			return "[E] Stop the broadcast" if broadcast_running else "[E] Start the broadcast (loud and bright)"
		"wood": return "[E] Take wood (%d left)" % wood_amounts[it["id"]]
		"board": return "[E] Board the boat"
	return ""


## Called every frame on every peer.
func process_visuals(delta: float) -> void:
	if not enabled or _battery_node == null:
		return
	var w: Node = m.world
	match battery_state:
		Bat.CARRIED:
			var c: Node = m.players.get(carrier)
			if c:
				var fwd := Vector3(-sin(c.yaw), 0, -cos(c.yaw))
				_battery_node.global_position = c.visual.global_position + fwd * 0.38 + Vector3(0, 0.85, 0)
				_battery_node.rotation.y = c.yaw
		_:
			_battery_node.global_position = battery_pos
	var t := Time.get_ticks_msec() / 1000.0
	_radio_light.visible = radio_powered
	if broadcast_active:
		_radio_light.light_energy = 2.6 + 0.6 * sin(t * 13.0) * sin(t * 3.1)
		_radio_light.omni_range = 16.0
	else:
		_radio_light.light_energy = 0.15
		_radio_light.omni_range = 3.0
	_beacon.visible = radio_powered and (broadcast_active or fmod(t, 2.0) < 0.15)
	if _hum.stream:
		if broadcast_active and not _hum.playing:
			_hum.play()
		elif not broadcast_active and _hum.playing:
			_hum.stop()
	_boat.visible = boat_here()
	for i in mini(_wood_nodes.size(), wood_amounts.size()):
		var n: Node3D = _wood_nodes[i]
		n.visible = wood_amounts[i] > 0
		n.scale = Vector3(1, clampf(wood_amounts[i] / 4.0, 0.3, 1.2), 1)


func _build_visuals() -> void:
	var w: Node = m.world
	var root := Node3D.new()
	root.name = "Objectives"
	m.items_root.add_child(root)
	_battery_node = Node3D.new()
	root.add_child(_battery_node)
	Geo.box(_battery_node, Vector3(0.7, 0.46, 0.43), Vector3(0, 0.23, 0), Geo.mat(Color(0.84, 0.58, 0.26), 0.5, Color(0.6, 0.35, 0.05), 0.35), 0)
	Geo.box(_battery_node, Vector3(0.1, 0.06, 0.1), Vector3(-0.2, 0.49, 0), Geo.mat(Color(0.1, 0.1, 0.1)), 0)
	Geo.box(_battery_node, Vector3(0.1, 0.06, 0.1), Vector3(0.2, 0.49, 0), Geo.mat(Color(0.7, 0.15, 0.1)), 0)
	_radio_light = OmniLight3D.new()
	_radio_light.light_color = Color(0.75, 0.88, 1.0)
	_radio_light.shadow_enabled = false
	_radio_light.position = w.radio_bench + Vector3(0, 1.8, 0)
	root.add_child(_radio_light)
	_beacon = OmniLight3D.new()
	_beacon.light_color = Color(1.0, 0.2, 0.15)
	_beacon.omni_range = 6.0
	_beacon.light_energy = 1.5
	_beacon.position = w.radio_mast_top
	root.add_child(_beacon)
	_hum = AudioStreamPlayer3D.new()
	if Sfx.enabled:
		_hum.stream = Sfx.streams.get("drone")
	_hum.pitch_scale = 2.4
	_hum.volume_db = 6.0
	_hum.max_distance = 110.0
	_hum.unit_size = 10.0
	_hum.position = w.radio_bench
	root.add_child(_hum)
	_boat = Node3D.new()
	_boat.position = w.boat_pos
	_boat.rotation.y = atan2(w.boat_pos.x - w.landmarks["dock"].x, w.boat_pos.z - w.landmarks["dock"].z)
	root.add_child(_boat)
	var hull := Geo.mat(Color(0.82, 0.8, 0.74))
	Geo.box(_boat, Vector3(2.6, 1.0, 7.0), Vector3(0, 0.2, 0), hull, 0)
	Geo.box(_boat, Vector3(1.8, 1.3, 2.2), Vector3(0, 1.3, -0.8), Geo.mat(Color(0.3, 0.4, 0.5)), 0)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.9, 0.6)
	lamp.omni_range = 9.0
	lamp.position = Vector3(0, 2.4, 0)
	_boat.add_child(lamp)
	_boat.visible = false
	var wood := Geo.mat(Color(0.55, 0.42, 0.27))
	for wp in w.wood_piles:
		var pile := Node3D.new()
		pile.position = wp["pos"]
		root.add_child(pile)
		for i in 4:
			Geo.box(pile, Vector3(1.2, 0.1, 0.22), Vector3(0, 0.06 + i * 0.11, (i % 2) * 0.12 - 0.06), wood, 0, 0.15 * i)
		_wood_nodes.append(pile)
