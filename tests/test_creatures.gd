extends "res://tests/suite.gd"
## Milestone 5 creatures: types, memory, personality hooks, shove, drag / capture / raid, traces.

const MatchScript = preload("res://src/match/match.gd")
const D = preload("res://src/core/defs.gd")


func _make(r: Node, roster: Dictionary = {1: {"name": "Host", "slot": 0}}) -> Node:
	var m := MatchScript.new()
	m.setup({"seed": 3, "world": "island", "roster": roster})
	m.dev_start_phase = D.Phase.NIGHT
	r.add_child(m)
	return m


func _wait(r: Node, seconds: float) -> void:
	for i in int(seconds * 60.0):
		await r.get_tree().physics_frame


func _as_type(c: Node, t: String, night: int = 1) -> void:
	c.ctype = t
	c.stats = Tuning.creature_stats(t, night)


func _open_spot(m: Node, near: Vector3) -> Vector3:
	var g: RefCounted = m.world.grid
	var p: Vector3 = g.cell_to_world(g.nearest_walkable(g.world_to_cell(near)))
	p.y = m.world.ground_y(p) + 0.05
	return p


func test_types_drawn_per_seed(_r) -> void:
	var a: Array = MatchScript.creature_types_for(3, 6, true)
	check(a.size() == 6, "a type for every individual")
	var distinct := {}
	for t in a:
		distinct[t] = true
	check(distinct.size() >= 3, "a run meets several types over its nights (%s)" % [a])
	check(a == MatchScript.creature_types_for(3, 6, true), "the same seed draws the same pool")
	var differs := false
	for s in range(4, 20):
		if MatchScript.creature_types_for(s, 6, true)[0] != a[0]:
			differs = true
	check(differs, "night one's type changes between seeds")


func test_listener_is_blind_but_feels_and_hears(r: Node) -> void:
	var m := _make(r)
	await _wait(r, 0.1)
	var c: Node = m.creatures[0]
	_as_type(c, "listener")
	var p: Node = m.local_player
	var spot := _open_spot(m, m.world.landmarks["battery"])
	p.global_position = spot
	c.global_position = spot + Vector3(3.0, 0, 0)
	c.yaw = PI * 0.5
	p.moving = false
	p.lantern_open = true
	check(c.visibility_of(p) == 0.0, "a still player with a lantern is invisible to a Listener")
	p.moving = true
	check(c.visibility_of(p) > 0.0, "movement within reach is felt through the ground")
	p.global_position = spot + Vector3(-6.0, 0, 0)
	check(c.visibility_of(p) == 0.0, "beyond its feel range it senses nothing")
	c._set_state(D.CState.PATROL, "test")
	c._on_sound({"pos": p.global_position, "radius": 20.0, "kind": "footsteps", "peer": p.peer_id}, 9.0, 32.0)
	c._on_sound({"pos": p.global_position, "radius": 20.0, "kind": "footsteps", "peer": p.peer_id}, 9.0, 32.0)
	check(c.state == D.CState.CHASE, "close footsteps start a Listener's chase (%s)" % D.CSTATE_NAMES[c.state])
	m.free()


func test_digger_cannot_climb_and_needs_soil(r: Node) -> void:
	var m := _make(r)
	await _wait(r, 0.1)
	var c: Node = m.creatures[0]
	_as_type(c, "digger")
	c._set_state(D.CState.PATROL, "test")
	c._start_climb(0, "test")
	check(c.state == D.CState.SEARCH, "a Digger waits under the tree instead of climbing")
	var before: float = c.state_time
	m.sound_events = [{"pos": c.global_position + Vector3(4, 0, 0), "radius": 20.0, "kind": "footsteps", "ground": "rock"}]
	c._set_state(D.CState.PATROL, "test")
	c._hear()
	check(c.state == D.CState.PATROL, "footsteps on rock don't reach it")
	m.sound_events = [{"pos": c.global_position + Vector3(4, 0, 0), "radius": 20.0, "kind": "footsteps", "ground": "soil"}]
	c._hear()
	check(c.state == D.CState.INVESTIGATE, "footsteps on soil do")
	m.sound_events = []
	check(Tuning.creature_stats("climber", 1)["climb_time"] < Tuning.creature_stats("stalker", 1)["climb_time"] * 0.6, "Climbers climb much faster")
	m.free()


func test_shove_recoil_scar_grudge_and_immunity(r: Node) -> void:
	var m := _make(r)
	await _wait(r, 0.1)
	var c: Node = m.creatures[0]
	var p: Node = m.local_player
	c.wake(1, _open_spot(m, m.world.landmarks["battery"]))
	p.global_position = c.global_position + Vector3(0, 0.05, 1.5)
	m.look_yaw = 0.0
	p.yaw = 0.0
	p.stamina = 100.0
	m.request("shove", 0.0, 0.0)
	check(c.state == D.CState.RECOIL, "the shove makes it recoil (%s)" % D.CSTATE_NAMES[c.state])
	check(c.mind.scars.has("wound"), "a shoved creature carries a wound")
	check(c.mind.grudges.get(p.peer_id, 0.0) >= 3.0, "and holds a grudge")
	check(p.stamina < 60.0, "shoving costs most of your stamina")
	check(not c.on_shoved(p), "it can't be shoved again right away")
	m.free()


func test_drag_capture_and_raid(r: Node) -> void:
	var saved := Tuning.raid_wake_chance_day
	Tuning.raid_wake_chance_day = 0.0   # the risk is random; this test checks the mechanics
	var m := _make(r, {1: {"name": "Host", "slot": 0}, 2: {"name": "Guest", "slot": 1}})
	await _wait(r, 0.1)
	var c: Node = m.creatures[0]
	var guest: Node = m.players[2]
	var host: Node = m.local_player
	var burrow: Vector3 = m.burrow_list()[0]
	c.wake(1, burrow)
	guest.global_position = _open_spot(m, burrow + Vector3(6, 0, 0))
	host.global_position = _open_spot(m, burrow + Vector3(-25, 0, 0))
	m.down_player(guest, c)
	c.global_position = guest.global_position + Vector3(1.0, 0, 0)
	c._start_drag(guest, "test")
	var captured := false
	for i in 60 * 20:
		await r.get_tree().physics_frame
		if guest.mode == D.Mode.CAPTURED:
			captured = true
			break
	check(captured, "a downed player gets dragged into the burrow (%s: %s)" % [D.CSTATE_NAMES[c.state], c.reason])
	check(not m.over, "one captive with a teammate still free doesn't end the run")
	check(c.mind.scars.has("lantern"), "the creature carries its victim's lantern")
	# Daytime raid frees them.
	for cc in m.creatures.values():
		cc.go_home()
		cc._set_awake(false)
		cc.state = D.CState.DORMANT
	m._set_phase(D.Phase.DAY)
	host.global_position = _open_spot(m, burrow + Vector3(1.5, 0, 0))
	for i in int((Tuning.raid_time + 1.0) * 60.0):
		host.input_queue.clear()
		host.input_queue.append({"mx": 0.0, "my": 0.0, "yaw": 0.0, "pitch": 0.0, "stance": D.Stance.STAND, "btn": D.BTN_INTERACT})
		await r.get_tree().physics_frame
		if guest.mode == D.Mode.NORMAL:
			break
	check(guest.mode == D.Mode.NORMAL, "holding E at the burrow frees the captive")
	m.free()
	Tuning.raid_wake_chance_day = saved


func test_everyone_captured_or_down_ends_the_run(r: Node) -> void:
	var m := _make(r)
	await _wait(r, 0.1)
	var p: Node = m.local_player
	m.capture_player(p, m.burrow_list()[0], m.creatures[0])
	await _wait(r, 0.1)
	check(m.over, "the whole crew captured ends the run")
	m.free()


func test_learned_counters_cap_and_fade(r: Node) -> void:
	var m := _make(r)
	await _wait(r, 0.1)
	var c: Node = m.creatures[0]
	var mind: RefCounted = c.mind
	mind.learn("rope", 1)
	mind.learn("decoy", 1)
	mind.learn("grass", 1)
	mind.learn("cave", 1, 0)
	check(mind.counters.size() == Tuning.max_counters, "an individual holds at most %d counters" % Tuning.max_counters)
	mind.learn("rope", 2)
	check(mind.knows("rope"), "reinforced lessons stick")
	mind.fade(10)
	mind.fade(11)
	check(not mind.knows("decoy") or mind.counters.size() < Tuning.max_counters, "old lessons fade")
	# Two individuals of one type roll different personalities.
	var a: Node = m.creatures[0]
	var b: Node = m.creatures[1]
	check(absf(a.mind.boldness - b.mind.boldness) > 0.001 or absf(a.mind.patience - b.mind.patience) > 0.001, "personalities differ")
	m.free()


func test_rope_escape_teaches_and_decoy_lesson(r: Node) -> void:
	var m := _make(r)
	await _wait(r, 0.1)
	var c: Node = m.creatures[0]
	c.state = D.CState.TREE_ATTACK
	c.commit_tree = 2
	c.notice_rope(2, m.local_player)
	check(c.mind.knows("rope"), "a rope escape is remembered")
	c._set_state(D.CState.INVESTIGATE, "test")
	c.investigate_pos = c.global_position
	c.investigate_kind = "noisemaker"
	c.look_timer = 3.5
	c._st_investigate(0.1)
	check(c.mind.knows("decoy"), "finding nothing at a rattle teaches it about decoys")
	m.free()


func test_flush_and_wait_recruits_a_holder(r: Node) -> void:
	var m := _make(r)
	await _wait(r, 0.1)
	var a: Node = m.creatures[0]
	var b: Node = m.creatures[1]
	var cave: Dictionary = m.world.caves[0]
	a.wake(Tuning.trick_flush_night, cave["door_point"])
	b.wake(Tuning.trick_flush_night, _open_spot(m, cave["door_point"] + Vector3(12, 0, 0)))
	b._set_state(D.CState.PATROL, "test")
	a._start_breach(0, "test")
	check(b.state == D.CState.HOLD and b.reason.contains("back way"), "a second creature holds the cave's back exit (%s: %s)" % [D.CSTATE_NAMES[b.state], b.reason])
	m.free()


func test_traces_build_and_draw_a_patrol(r: Node) -> void:
	var m := _make(r)
	await _wait(r, 0.1)
	var p: Node = m.local_player
	var spot := _open_spot(m, m.world.landmarks["radio"] + Vector3(6, 0, 0))
	p.global_position = spot
	for i in 60 * 14:
		p.global_position = spot
		p.moving = true
		m._srv_traces(1.0 / 60.0)
	check(m.trace_hotspot_near(spot, 10.0) != Vector3.INF, "a place used for a while leaves fresh trails")
	m.free()
