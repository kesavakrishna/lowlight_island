extends "res://tests/suite.gd"
## Middle-path content: the keeper's notes and cache, the lighthouse lookout, and the
## optional skiff escape (three parts, after dark, a loud warm-up, then board).

const MatchScript = preload("res://src/match/match.gd")
const D = preload("res://src/core/defs.gd")


func _make(r: Node, start_phase: int = -1) -> Node:
	var m := MatchScript.new()
	m.setup({"seed": 3, "world": "island", "roster": {1: {"name": "Keeper's Guest", "slot": 0}}})
	m.dev_start_phase = start_phase
	r.add_child(m)
	return m


func _wait(r: Node, seconds: float) -> void:
	for i in int(seconds * 60.0):
		await r.get_tree().physics_frame


func _at(m: Node, pos: Vector3) -> void:
	var p: Node = m.local_player
	var q := pos + Vector3(0.6, 0, 0.6)
	q.y = m.world.ground_y(q) + 0.05
	p.global_position = q
	p.velocity = Vector3.ZERO
	p.last_dry = q


func test_notes_cache_and_lookout(r: Node) -> void:
	var m := _make(r)
	var ex: RefCounted = m.expedition
	check(ex.enabled, "this island has the keeper's content")
	check(ex.notes_read.size() == 8, "eight notes to find")
	var note7: Dictionary = m.world.gen.notes[7]
	_at(m, note7["pos"])
	await _wait(r, 0.1)
	m.request("interact", "note", 7)
	check(ex.notes_read[7] and ex.known["parts"], "the skiff note reveals where the parts are")
	var t: Array = ex.note_text(0)
	check(t[1].contains("SKIFF") or t[1].contains("SALVAGE"), "the wreck sketch matches this island's battery site")
	var p: Node = m.local_player
	var nm: int = p.noisemakers
	_at(m, m.world.gen.cottage + Vector3(-0.8, 0, 0.9))
	await _wait(r, 0.1)
	m.request("interact", "cache", 0)
	check(ex.cache_taken and p.noisemakers == nm + 1, "the keeper's cupboard has supplies")
	_at(m, m.world.lighthouse_door)
	await _wait(r, 0.1)
	m.request("interact", "lookout", 0)
	check(m.objectives.dock_known and not m.objectives.caves_known.has(false), "the gallery shows the dock and every cave")
	m.free()


func test_skiff_escape(r: Node) -> void:
	var saved := Tuning.launch_time
	Tuning.launch_time = 2.0
	var m := _make(r)
	var ex: RefCounted = m.expedition
	var p: Node = m.local_player
	var skiff: Vector3 = m.world.gen.skiff
	for i in ex.parts.size():
		_at(m, ex.parts[i]["pos"])
		await _wait(r, 0.1)
		m.request("interact", "part", i)
		check(p.part == i, "picked up part %d" % i)
		if i == 1:
			# A downed carrier drops the part where it can be recovered.
			m.down_player(p, null)
			check(p.part == -1 and ex.parts[i]["state"] == ex.Part.DROPPED, "a downed carrier drops the part")
			p.mode = D.Mode.NORMAL
			m.over = false
			_at(m, ex.parts[i]["pos"])
			await _wait(r, 0.1)
			m.request("interact", "part", i)
		_at(m, skiff)
		await _wait(r, 0.1)
		m.request("interact", "fit", i)
	check(ex._fitted() == 3, "all three parts fitted")
	m.request("interact", "launch", 0)
	check(not ex.launching, "she won't float by day")
	m._set_phase(D.Phase.DUSK)
	m._set_phase(D.Phase.NIGHT)
	var c: Node = m.creatures[0]
	var spot: Vector3 = m.world.grid.cell_to_world(m.world.grid.nearest_walkable(m.world.grid.world_to_cell(skiff + Vector3(20, 0, 0))))
	c.wake(1, spot)
	c._set_state(D.CState.PATROL, "test")
	_at(m, skiff)
	m.request("interact", "launch", 0)
	check(ex.launching, "the engine starts after dark")
	await _wait(r, 0.5)
	check(c.state == D.CState.INVESTIGATE or c.state == D.CState.CHASE or c.state == D.CState.SEARCH, "the engine draws them in (%s: %s)" % [D.CSTATE_NAMES[c.state], c.reason])
	c._set_awake(false)
	c.state = D.CState.DORMANT
	await _wait(r, 2.0)
	check(ex.ready_window > 0.0, "she floats after the warm-up")
	m.request("interact", "board_skiff", 0)
	await _wait(r, 0.2)
	check(p.mode == D.Mode.ESCAPED and m.over, "boarding the skiff is an escape")
	m.free()
	Tuning.launch_time = saved
