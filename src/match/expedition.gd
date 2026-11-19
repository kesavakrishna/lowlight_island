extends RefCounted
## Optional per-island content beyond the main escape (the "middle path"):
## the keeper's notes, her cottage cache, the lighthouse lookout and lamp, and the old
## skiff - a second way off the island. Three parts to find and fit; the tide only floats
## her after dark, and the engine's long, loud warm-up draws every creature in range.
## Host-authoritative like objectives.gd; clients mirror it and draw it.

const D = preload("res://src/core/defs.gd")
const Geo = preload("res://src/world/geo.gd")

enum Part { SITE, CARRIED, DROPPED, FITTED }

const PART_NAMES := {"motor": "the motor head", "fuel": "the fuel can", "oars": "the oars"}
const NOTES := [
	["Pilot's kneeboard sketch",
		"Torn from the pilot's kneeboard: a rough outline of the island, the crash marked with an X. Someone has circled a spot and written SPARE CELL - %s. Under it, in different ink: 'radio shed on the high ground'."],
	["Keeper's log, page 41",
		"If you see the lamp flash after dark, get below the windows. They come up at dusk, out of the ground, and they follow steady light. A shuttered lamp is a friend. An open one is a promise."],
	["Keeper's log, page 58",
		"They are not all the same. One never once looked at the lamp - it turned its head toward every footstep instead. Another came up through the soft earth of the garden but never through the rock by the point. And the thin one goes up the trees like they're ladders."],
	["Note pinned in the radio shed",
		"Moved the transmitter up here after we lost the dock. Wired the battery leads myself. It's a beacon both ways: it glows, it hums, and they come to it. The signal won't carry by day. Run it after dark, and don't run it alone."],
	["Scratched into the cave wall",
		"Three nights here. On the fourth they were at the door before it was properly dark. They remember where you've been. Don't stay anywhere too long."],
	["Tin box nailed to the dock",
		"Supply boat log. It still comes when the radio calls - comes at first light and doesn't wait long. Last entry is months old."],
	["Keeper's log, last page",
		"After the fourth night they stop hiding. From the gallery you can see the whole island - the dock, the caves, their holes. I'm going down to finish the repairs. If you are reading this, I"],
	["Notes in the skiff",
		"Patched her hull. The motor's in pieces: the head is in one of the caves, I hid the fuel under the biggest tree I could find, and the oars are with the nets on the far beach. The tide only floats her after dark - and that engine will wake everything on this island."],
]

var m: Node = null
var enabled := false

# ---- replicated
var notes_read: Array = []
var parts: Array = []                # {kind, state, pos, carrier}
var launch := 0.0                    # engine warm-up 0..1
var launching := false
var ready_window := -1.0
var aboard: Array = []
var cache_taken := false
var lookout_used := false
var known := {"lighthouse": false, "cottage": false, "skiff": false, "parts": false}

# ---- host
var _noise_t := 0.0

# ---- visuals
var _part_nodes: Array = []
var _note_nodes: Array = []
var _lamp: OmniLight3D
var _lamp_t := -1.0
var _engine: AudioStreamPlayer3D
var _skiff_parts_vis: Dictionary = {}


func setup(p_match: Node) -> void:
	m = p_match
	var w: Node = m.world
	enabled = "gen" in w and w.gen != null and w.gen.expedition_ok
	if not enabled:
		return
	notes_read.resize(w.gen.notes.size())
	notes_read.fill(false)
	for pt in w.gen.skiff_parts:
		var pos: Vector3 = pt["pos"]
		pos.y = w.ground_y(pos) + 0.02
		parts.append({"kind": pt["kind"], "state": Part.SITE, "pos": pos, "carrier": -1})
	_build_visuals()


# ================================================================== host

func candidates(p: Node) -> Array:
	var out: Array = []
	if not enabled or p.mode != D.Mode.NORMAL:
		return out
	var w: Node = m.world
	for n in w.gen.notes:
		out.append({"kind": "note", "id": n["id"], "pos": (n["pos"] as Vector3) + Vector3(0, 0.4, 0)})
	if not cache_taken:
		out.append({"kind": "cache", "id": 0, "pos": w.gen.cottage + Vector3(-0.8, 0.7, 0.9)})
	out.append({"kind": "lookout", "id": 0, "pos": w.lighthouse_door + Vector3(0, 1.0, 0)})
	for i in parts.size():
		var pt: Dictionary = parts[i]
		if (pt["state"] == Part.SITE or pt["state"] == Part.DROPPED) and p.part < 0 and not p.carrying:
			out.append({"kind": "part", "id": i, "pos": (pt["pos"] as Vector3) + Vector3(0, 0.3, 0)})
	var at_skiff: Vector3 = w.gen.skiff + Vector3(0, 0.8, 0)
	if p.part >= 0:
		out.append({"kind": "fit", "id": p.part, "pos": at_skiff})
	elif _fitted() == parts.size() and not launching and ready_window < 0.0:
		out.append({"kind": "launch", "id": 0, "pos": at_skiff})
	elif ready_window > 0.0:
		out.append({"kind": "board_skiff", "id": 0, "pos": at_skiff})
	return out


func interact(p: Node, kind: String, id: int) -> bool:
	if not enabled:
		return false
	var w: Node = m.world
	match kind:
		"note":
			if id < 0 or id >= notes_read.size():
				return true
			notes_read[id] = true
			if id == 7:
				known["parts"] = true
			if id == 6:
				known["lighthouse"] = true
			m.send_note(p, id)
		"cache":
			if cache_taken:
				return true
			cache_taken = true
			for q in m.players.values():
				q.noisemakers += 1
			p.wood = mini(p.wood + 4, Tuning.wood_cap)
			m.emit_cue("found", w.gen.cottage, {"what": "the keeper's supplies: a noisemaker each, and wood"})
		"lookout":
			lookout_used = true
			_reveal_from_gallery()
			m.notify(p, "From the gallery you can see the whole island. The map fills in.")
		"part":
			var pt: Dictionary = parts[id]
			if pt["state"] != Part.SITE and pt["state"] != Part.DROPPED:
				return true
			pt["state"] = Part.CARRIED
			pt["carrier"] = p.peer_id
			p.part = id
			known["parts"] = true
			known["skiff"] = true
			m.emit_cue("found", pt["pos"], {"what": PART_NAMES[pt["kind"]]})
		"fit":
			if p.part < 0:
				return true
			var pf: Dictionary = parts[p.part]
			pf["state"] = Part.FITTED
			pf["carrier"] = -1
			pf["pos"] = w.gen.skiff
			p.part = -1
			m.emit_cue("part_fitted", w.gen.skiff, {"count": _fitted(), "of": parts.size()})
		"launch":
			if not (m.phase == D.Phase.DUSK or m.phase == D.Phase.NIGHT):
				m.notify(p, "She's sitting on the sand. The tide only floats her after dark.")
				return true
			launching = true
			m.emit_cue("engine_start", w.gen.skiff)
		"board_skiff":
			if ready_window <= 0.0:
				return true
			if p.carrying:
				m.objectives.drop_battery(p)
			aboard.append(p.peer_id)
			p.mode = D.Mode.ESCAPED
			p.lantern_open = false
			p.global_position = w.gen.skiff + Vector3(0, 0.6, 0)
			p.velocity = Vector3.ZERO
			m.emit_cue("boarded", w.gen.skiff, {"name": p.display_name})
		_:
			return false
	return true


func drop_part(p: Node) -> void:
	if not enabled or p.part < 0:
		return
	var pt: Dictionary = parts[p.part]
	var pos: Vector3 = p.global_position
	if m.world.has_method("in_water") and m.world.in_water(pos):
		pos = p.last_dry
	pos.y = m.world.ground_y(pos) + 0.02
	pt["state"] = Part.DROPPED
	pt["pos"] = pos
	pt["carrier"] = -1
	p.part = -1


func _fitted() -> int:
	var n := 0
	for pt in parts:
		if pt["state"] == Part.FITTED:
			n += 1
	return n


func _reveal_from_gallery() -> void:
	var w: Node = m.world
	var obj: RefCounted = m.objectives
	obj.dock_known = true
	for i in w.caves.size():
		obj.caves_known[i] = true
	for i in w.burrows.size():
		obj.burrows_known[i] = true
	known["skiff"] = true
	known["cottage"] = true
	known["lighthouse"] = true


func server_tick(delta: float) -> void:
	if not enabled:
		return
	var w: Node = m.world
	for pt in parts:
		if pt["state"] == Part.CARRIED:
			var c: Node = m.players.get(pt["carrier"])
			if c == null or c.mode != D.Mode.NORMAL and c.mode != D.Mode.CLIMBING and c.mode != D.Mode.PERCHED:
				pt["state"] = Part.DROPPED
				pt["carrier"] = -1
				if c:
					c.part = -1
			else:
				pt["pos"] = c.global_position
	for p in m.players.values():
		var pos: Vector3 = p.global_position
		if not known["lighthouse"] and pos.distance_to(w.gen.lighthouse) < 40.0:
			known["lighthouse"] = true
		if not known["cottage"] and pos.distance_to(w.gen.cottage) < 25.0:
			known["cottage"] = true
		if not known["skiff"] and pos.distance_to(w.gen.skiff) < 25.0:
			known["skiff"] = true
	if launching:
		launch = minf(1.0, launch + delta / Tuning.launch_time)
		_noise_t -= delta
		if _noise_t <= 0.0:
			_noise_t = 2.0
			m.emit_sound(w.gen.skiff, Tuning.launch_noise, "engine")
		if launch >= 1.0:
			launching = false
			ready_window = Tuning.skiff_window
			m.emit_cue("skiff_ready", w.gen.skiff)
	if ready_window > 0.0:
		ready_window -= delta
		var remaining := 0
		for p in m.players.values():
			if p.mode != D.Mode.ESCAPED and p.mode != D.Mode.CAPTURED and p.mode != D.Mode.DOWNED:
				remaining += 1
		if not aboard.is_empty() and remaining == 0:
			ready_window = -1.0
			m.end_match(true)
		elif ready_window <= 0.0:
			ready_window = -1.0
			if aboard.is_empty():
				launch = 0.0
				m.emit_cue("skiff_missed", w.gen.skiff)
			else:
				m.end_match(true)


## Night begins: the lamp flashes three times - get below the windows.
func on_phase(phase: int) -> void:
	if enabled and phase == D.Phase.NIGHT:
		m.emit_cue("lamp", m.world.gen.lighthouse + Vector3(0, 13.0, 0))


# ================================================================== replication / presentation

func serialize() -> Array:
	var ps: Array = []
	for pt in parts:
		ps.append([pt["state"], pt["pos"], pt["carrier"]])
	return [notes_read, ps, launch, launching, ready_window, aboard, cache_taken, lookout_used, known]


func apply(a: Array) -> void:
	if not enabled or a.size() < 9:
		return
	notes_read = a[0]
	for i in mini(parts.size(), a[1].size()):
		parts[i]["state"] = a[1][i][0]
		parts[i]["pos"] = a[1][i][1]
		parts[i]["carrier"] = a[1][i][2]
	launch = a[2]
	launching = a[3]
	ready_window = a[4]
	aboard = a[5]
	cache_taken = a[6]
	lookout_used = a[7]
	known = a[8]


func note_text(id: int) -> Array:
	var title: String = NOTES[id][0]
	var body: String = NOTES[id][1]
	if id == 0:
		body = body % ("BEACHED SKIFF" if m.world.battery_kind == "skiff" else "SALVAGE CRATE UNDER THE TREE")
	return [title, body]


func objective_text() -> String:
	if not enabled or not (known["skiff"] or known["parts"]):
		return ""
	if ready_window > 0.0:
		return "Optional: the skiff is afloat - board her!  %d s" % int(ready_window)
	if launching:
		return "Optional: the skiff's engine is warming up (%d%%). It's loud - hold them off." % int(launch * 100.0)
	var f := _fitted()
	if f == parts.size():
		return "Optional: the skiff is repaired. Launch her after dark - the engine will draw them in."
	return "Optional: the keeper's skiff needs its parts - %d / %d fitted." % [f, parts.size()]


func prompt(it: Dictionary) -> String:
	match it["kind"]:
		"note": return "[E] Read: %s" % NOTES[it["id"]][0]
		"cache": return "[E] Search the keeper's cupboard"
		"lookout": return "[E] Climb to the gallery and look out"
		"part": return "[E] Take %s" % PART_NAMES[parts[it["id"]]["kind"]]
		"fit": return "[E] Fit %s to the skiff" % PART_NAMES[parts[it["id"]]["kind"]]
		"launch": return "[E] Start the skiff's engine (loud, after dark)"
		"board_skiff": return "[E] Board the skiff"
	return ""


func process_visuals(delta: float) -> void:
	if not enabled:
		return
	for i in mini(parts.size(), _part_nodes.size()):
		var n: Node3D = _part_nodes[i]
		var pt: Dictionary = parts[i]
		n.visible = pt["state"] != Part.FITTED
		if pt["state"] == Part.CARRIED:
			var c: Node = m.players.get(pt["carrier"])
			if c:
				n.global_position = c.visual.global_position + Vector3(0, 1.0, 0) + Vector3(cos(c.yaw), 0, -sin(c.yaw)) * 0.35
		else:
			n.global_position = pt["pos"]
	for k in _skiff_parts_vis:
		(_skiff_parts_vis[k] as Node3D).visible = false
	for pt in parts:
		if pt["state"] == Part.FITTED and _skiff_parts_vis.has(pt["kind"]):
			(_skiff_parts_vis[pt["kind"]] as Node3D).visible = true
	for i in mini(notes_read.size(), _note_nodes.size()):
		(_note_nodes[i] as Node3D).scale = Vector3.ONE * (0.7 if notes_read[i] else 1.0)
	# Lamp: three flashes.
	if _lamp_t >= 0.0:
		_lamp_t += delta
		var phase := fmod(_lamp_t, 0.9)
		_lamp.visible = _lamp_t < 2.7 and phase < 0.35
		if _lamp_t >= 2.7:
			_lamp_t = -1.0
			_lamp.visible = false
	if _engine.stream:
		var loud := launching or ready_window > 0.0
		if loud and not _engine.playing:
			_engine.play()
		elif not loud and _engine.playing:
			_engine.stop()


func flash_lamp() -> void:
	_lamp_t = 0.0


func _build_visuals() -> void:
	var w: Node = m.world
	var root := Node3D.new()
	root.name = "Expedition"
	m.items_root.add_child(root)
	var paper := Geo.mat(Color(0.85, 0.82, 0.7), 0.9, Color(0.4, 0.38, 0.3), 0.15)
	for n in w.gen.notes:
		var nn := Node3D.new()
		root.add_child(nn)
		nn.position = (n["pos"] as Vector3) + Vector3(0, 0.03, 0)
		Geo.box(nn, Vector3(0.28, 0.02, 0.36), Vector3.ZERO, paper, 0, 0.4)
		_note_nodes.append(nn)
	var looks := {
		"motor": [Vector3(0.45, 0.35, 0.4), Color(0.22, 0.24, 0.25)],
		"fuel": [Vector3(0.3, 0.42, 0.18), Color(0.65, 0.12, 0.08)],
		"oars": [Vector3(0.12, 0.08, 2.2), Color(0.55, 0.42, 0.26)],
	}
	for pt in parts:
		var pn := Node3D.new()
		root.add_child(pn)
		var lk: Array = looks[pt["kind"]]
		Geo.box(pn, lk[0], Vector3(0, (lk[0] as Vector3).y * 0.5, 0), Geo.mat(lk[1], 0.6), 0)
		_part_nodes.append(pn)
	var sk: Node3D = w.skiff_node
	var fit_looks := {
		"motor": [Vector3(0.4, 0.5, 0.4), Vector3(0, 0.75, 1.9), Color(0.22, 0.24, 0.25)],
		"fuel": [Vector3(0.28, 0.38, 0.16), Vector3(0.35, 0.65, 1.2), Color(0.65, 0.12, 0.08)],
		"oars": [Vector3(0.08, 0.06, 2.3), Vector3(-0.45, 0.62, 0), Color(0.55, 0.42, 0.26)],
	}
	for k in fit_looks:
		var holder := Node3D.new()
		sk.add_child(holder)
		var fl: Array = fit_looks[k]
		Geo.box(holder, fl[0], fl[1], Geo.mat(fl[2], 0.5), 0)
		_skiff_parts_vis[k] = holder
	for k in _skiff_parts_vis:
		(_skiff_parts_vis[k] as Node3D).visible = false
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.9, 0.65)
	_lamp.omni_range = 60.0
	_lamp.light_energy = 6.0
	_lamp.position = w.gen.lighthouse + Vector3(0, 13.0, 0)
	_lamp.visible = false
	root.add_child(_lamp)
	_engine = AudioStreamPlayer3D.new()
	if Sfx.enabled:
		_engine.stream = Sfx.streams.get("drone")
	_engine.pitch_scale = 3.4
	_engine.volume_db = 8.0
	_engine.max_distance = 140.0
	_engine.unit_size = 12.0
	_engine.position = w.gen.skiff
	root.add_child(_engine)
