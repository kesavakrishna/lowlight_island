extends "res://tests/suite.gd"
## Milestone 4: the full escape chain on a generated island
## (crash -> battery -> radio shed -> broadcast -> dock), escalation, wood and repairs.

const MatchScript = preload("res://src/match/match.gd")
const D = preload("res://src/core/defs.gd")
const SEED := 3


func _make(r: Node, start_phase: int = -1) -> Node:
	var m := MatchScript.new()
	m.setup({"seed": SEED, "world": "island", "roster": {1: {"name": "Carrier", "slot": 0}}})
	m.dev_start_phase = start_phase
	r.add_child(m)
	return m


func _wait(r: Node, seconds: float) -> void:
	for i in int(seconds * 60.0):
		await r.get_tree().physics_frame


func _place(m: Node, pos: Vector3, look_at: Vector3) -> void:
	var p: Node = m.local_player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.last_dry = pos
	var yaw := atan2(pos.x - look_at.x, pos.z - look_at.z)
	m.look_yaw = yaw
	p.yaw = yaw


func _near(m: Node, target: Vector3, dist: float = 0.9) -> Vector3:
	# A walkable spot `dist` metres from target, on the ground.
	for a in 12:
		var ang := TAU * a / 12.0
		var q := target + Vector3(cos(ang), 0, sin(ang)) * dist
		q.y = m.world.ground_y(q) + 0.05
		if m.world.grid.is_walkable(q):
			return q
	return target + Vector3(dist, 0.05, 0)


func _drive(r: Node, m: Node, inp: Dictionary, seconds: float) -> void:
	for i in int(seconds * 60.0):
		m.local_player.input_queue.clear()
		m.local_player.input_queue.append(inp)
		await r.get_tree().physics_frame


func test_battery_carry_drop_and_install(r: Node) -> void:
	var m := _make(r)
	var p: Node = m.local_player
	var obj: RefCounted = m.objectives
	check(obj.enabled, "objectives run on generated islands")
	var bat: Vector3 = obj.battery_pos
	_place(m, _near(m, bat, 1.0), bat)
	await _wait(r, 0.2)
	m.request("interact", "battery", 0)
	check(p.carrying and obj.battery_state == obj.Bat.CARRIED and obj.carrier == p.peer_id, "picked up the battery")
	# Heavy: no sprinting, slower than a walk.
	var start: Vector3 = p.global_position
	await _drive(r, m, {"mx": 0.0, "my": -1.0, "yaw": m.look_yaw + PI, "pitch": 0.0, "stance": D.Stance.STAND, "btn": D.BTN_SPRINT}, 1.0)
	var spd := Vector2(p.velocity.x, p.velocity.z).length()
	check(not p.sprinting and spd <= Tuning.carry_speed + 0.05, "carrier cannot sprint (speed %.2f)" % spd)
	# No climbing with it.
	var tree: Dictionary = m.world.trees[0]
	_place(m, _near(m, tree["pos"], tree["trunk_r"] + 0.8), tree["pos"])
	await _wait(r, 0.1)
	for it in m.world.interactables:
		if it["kind"] == "climb" and it["tree"] == 0:
			m.request("interact", "climb", it["id"])
	await _wait(r, 0.5)
	check(p.mode == D.Mode.NORMAL, "cannot climb while carrying the battery")
	# Put it down quickly; it lands on reachable ground.
	m.request("drop")
	check(not p.carrying and obj.battery_state == obj.Bat.DROPPED, "dropped the battery")
	check(absf(obj.battery_pos.y - m.world.ground_y(obj.battery_pos)) < 0.2, "the battery rests on the ground")
	check(m.world.grid.is_walkable(obj.battery_pos) or m.world.grid.reachable(m.world.landmarks["crash"], obj.battery_pos), "the dropped battery stays reachable")
	# A downed carrier drops it where the crew can get it back.
	_place(m, _near(m, obj.battery_pos, 1.0), obj.battery_pos)
	await _wait(r, 0.1)
	m.request("interact", "battery", 0)
	check(p.carrying, "picked it up again")
	m.down_player(p, null)
	check(not p.carrying and obj.battery_state == obj.Bat.DROPPED, "a downed carrier drops the battery")
	# Revive and install at the radio.
	p.mode = D.Mode.NORMAL
	m.over = false
	_place(m, _near(m, obj.battery_pos, 1.0), obj.battery_pos)
	await _wait(r, 0.1)
	m.request("interact", "battery", 0)
	var bench: Vector3 = m.world.radio_bench
	_place(m, _near(m, bench, 1.2), bench)
	await _wait(r, 0.2)
	m.request("interact", "install", 0)
	check(obj.radio_powered and obj.battery_state == obj.Bat.INSTALLED and not p.carrying, "battery installed, radio powered")
	m.free()


func test_broadcast_draws_them_and_calls_the_boat(r: Node) -> void:
	var saved := Tuning.broadcast_time
	Tuning.broadcast_time = 4.0
	var m := _make(r, D.Phase.NIGHT)
	var p: Node = m.local_player
	var obj: RefCounted = m.objectives
	obj.radio_powered = true
	obj.battery_state = obj.Bat.INSTALLED
	var bench: Vector3 = m.world.radio_bench
	var tend := _near(m, bench, 1.0)
	_place(m, tend, bench)
	await _wait(r, 0.2)
	# A creature well within range of the beacon but out of sight.
	var c: Node = m.creatures[0]
	var spot := _near(m, bench + Vector3(35, 0, 0), 0.0)
	c.global_position = spot
	c._set_state(D.CState.PATROL, "test")
	c.patrol_target = spot
	m.request("interact", "transmitter", 0)
	check(obj.broadcast_running, "the crew started the broadcast")
	await _wait(r, 1.5)
	check(obj.broadcast > 0.2 and obj.broadcast_active, "progress while someone tends it (%.2f)" % obj.broadcast)
	var drawn: bool = c.state == D.CState.INVESTIGATE or c.state == D.CState.CHASE or c.state == D.CState.SEARCH
	check(drawn, "a creature is drawn to the broadcast (%s: %s)" % [D.CSTATE_NAMES[c.state], c.reason])
	c._set_awake(false)
	c.state = D.CState.DORMANT
	# Step away: it pauses but keeps its progress.
	_place(m, _near(m, bench, 8.0), bench)
	await _wait(r, 0.3)
	var kept: float = obj.broadcast
	await _wait(r, 0.8)
	check(not obj.broadcast_active and absf(obj.broadcast - kept) < 0.001 and kept > 0.2, "an interrupted broadcast keeps its progress")
	_place(m, tend, bench)
	await _wait(r, 3.5)
	check(obj.broadcast_done and obj.boat_due, "the completed call brings a boat")
	# Dawn: the boat waits; creatures linger in the shade on the way to the dock.
	m.creatures[1].wake(1, m.world.burrow_pos)
	m._set_phase(D.Phase.DAWN)
	check(obj.boat_here(), "boat at the dock at dawn (%.0f s)" % obj.boat_window)
	check(m.creatures[1].leash != Vector3.INF, "an awake creature lingers by the dock route")
	var board: Vector3 = m.world.dock_board
	_place(m, board + Vector3(0, 0.1, 0) - (Vector3(board.x, 0, board.z).normalized() * 1.0), board)
	await _wait(r, 0.3)
	m.request("interact", "board", 0)
	check(p.mode == D.Mode.ESCAPED, "boarded the boat")
	await _wait(r, 0.2)
	check(m.over, "everyone aboard ends the run as a crew win")
	m.free()
	Tuning.broadcast_time = saved


func test_boat_leaves_without_anyone(r: Node) -> void:
	var saved := Tuning.boarding_window
	Tuning.boarding_window = 0.5
	var m := _make(r, D.Phase.NIGHT)
	var obj: RefCounted = m.objectives
	obj.radio_powered = true
	obj.broadcast = 1.0
	obj.broadcast_done = true
	obj.boat_due = true
	m._set_phase(D.Phase.DAWN)
	check(obj.boat_here(), "boat arrived")
	await _wait(r, 1.0)
	check(not obj.boat_here() and not obj.broadcast_done and obj.broadcast == 0.0, "a missed boat means the call has to go out again")
	check(not m.over, "the run continues")
	m.free()
	Tuning.boarding_window = saved


func test_nights_escalate(r: Node) -> void:
	var m := _make(r)
	m.day_index = 1
	m._set_phase(D.Phase.NIGHT)
	var first := 0
	for c in m.creatures.values():
		if c.awake:
			first += 1
	var speed1: float = m.creatures[0].stats["chase_speed"]
	m._set_phase(D.Phase.DAWN)
	m.day_index = Tuning.escalation_threshold_night + 3
	m._set_phase(D.Phase.NIGHT)
	var later := 0
	for c in m.creatures.values():
		if c.awake:
			later += 1
	check(first >= 1, "at least one creature on night one (%d)" % first)
	check(later > first, "more of them later (%d -> %d)" % [first, later])
	check(m.creatures[0].stats["door_damage"] > Tuning.creature_types["stalker"]["door_damage"], "they break doors faster on later nights")
	check(m.creatures[0].stats["chase_speed"] >= speed1 and m.creatures[0].stats["chase_speed"] < Tuning.sprint_speed, "faster but still below a sprint")
	m.free()


func test_wood_and_door_repair(r: Node) -> void:
	var m := _make(r)
	var p: Node = m.local_player
	var obj: RefCounted = m.objectives
	check(m.world.wood_piles.size() >= 4, "wood near the wreck and farther out")
	var near_wreck := 0
	for wp in m.world.wood_piles:
		if (wp["pos"] as Vector3).distance_to(m.world.landmarks["crash"]) < 20.0:
			near_wreck += 1
	check(near_wreck >= 1, "some wood near the wreck")
	var pile: Vector3 = m.world.wood_piles[0]["pos"]
	_place(m, _near(m, pile, 1.0), pile)
	await _wait(r, 0.1)
	m.request("interact", "wood", 0)
	check(p.wood == Tuning.wood_take, "gathered wood (%d)" % p.wood)
	var cave: Dictionary = m.world.caves[0]
	m.world.set_door(false, 50.0, 0)
	_place(m, cave["door_point"] + Vector3(0, 0.1, 0), cave["door_center"])
	await _wait(r, 0.1)
	m.request("repair")
	check(absf(m.world.caves[0]["door_hp"] - (50.0 + Tuning.repair_hp)) < 0.01, "repair restores the door (%.0f)" % m.world.caves[0]["door_hp"])
	check(p.wood == Tuning.wood_take - Tuning.repair_cost, "repair costs wood")
	m.free()
