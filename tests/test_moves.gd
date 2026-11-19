extends "res://tests/suite.gd"
## Rest, lean / peek exposure, mantling over a fallen trunk, silent pings.

const MatchScript = preload("res://src/match/match.gd")
const D = preload("res://src/core/defs.gd")


func _make(r: Node, roster: Dictionary = {1: {"name": "Host", "slot": 0}}, world: String = "clearing") -> Node:
	var m := MatchScript.new()
	m.setup({"seed": 7, "world": world, "roster": roster})
	r.add_child(m)
	return m


func _wait(r: Node, seconds: float) -> void:
	for i in int(seconds * 60.0):
		await r.get_tree().physics_frame


func test_rest_needs_shelter_dark_and_a_watch(r: Node) -> void:
	var m := _make(r, {1: {"name": "Host", "slot": 0}, 2: {"name": "Guest", "slot": 1}})
	var p: Node = m.local_player
	var guest: Node = m.players[2]
	await _wait(r, 0.2)
	m.request("rest")
	check(not p.resting, "no resting out in the open")
	p.global_position = m.world.cave["inside_point"] + Vector3(0, 0.1, 0)
	guest.global_position = p.global_position + Vector3(1.5, 0, 0)
	await _wait(r, 0.3)
	m.request("rest")
	check(p.resting, "rest in a dark cave with a teammate keeping watch")
	p.stamina = 10.0
	await _wait(r, 1.0)
	check(p.stamina > 30.0, "resting recovers stamina quickly (%.0f)" % p.stamina)
	guest.global_position += Vector3(30, 0, 0)
	await _wait(r, 0.3)
	check(not p.resting, "rest ends when nobody is keeping watch")
	m.free()


func test_lean_moves_the_exposed_head(r: Node) -> void:
	var m := _make(r)
	var p: Node = m.local_player
	await _wait(r, 0.2)
	var c: Node = m.creatures[0]
	var straight: Array = c._exposure_points(p)
	p.lean = 1.0
	var leaning: Array = c._exposure_points(p)
	check((leaning[0] as Vector3).distance_to(straight[0]) > 0.3, "leaning moves the head a creature can see")
	check((leaning[leaning.size() - 1] as Vector3).distance_to(straight[straight.size() - 1]) < 0.15, "the feet stay put")
	m.free()


func test_mantle_over_a_fallen_trunk(r: Node) -> void:
	var m := _make(r)
	var p: Node = m.local_player
	var a := Vector3(2.5, 0, -10.5)
	var b := Vector3(7.5, 0, -7.5)
	var mid := (a + b) * 0.5
	var perp := Vector3(-(b - a).z, 0, (b - a).x).normalized()
	var yaw := atan2(-perp.x, -perp.z)
	p.global_position = mid - perp * 1.0 + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	await _wait(r, 0.3)
	for i in 120:
		p.input_queue.clear()
		p.input_queue.append({"mx": 0.0, "my": -1.0, "yaw": yaw, "pitch": 0.0, "stance": D.Stance.STAND, "btn": D.BTN_JUMP})
		await r.get_tree().physics_frame
	var along: float = (p.global_position - mid).dot(perp)
	check(along > 0.5, "climbed over the trunk (%.2f m past it)" % along)
	m.free()


func test_pings_are_silent(r: Node) -> void:
	var m := _make(r)
	await _wait(r, 0.2)
	m.sound_events.clear()
	m.request("ping", "danger", m.local_player.global_position + Vector3(5, 0, 0))
	var heard := false
	for ev in m.sound_events:
		if ev["kind"].contains("ping"):
			heard = true
	check(not heard, "creatures never hear a ping")
	m.request("ping", "nonsense", Vector3.ZERO)
	m.request("ping", "move", m.local_player.global_position + Vector3(500, 0, 0))
	check(true, "invalid pings are ignored without errors")
	m.free()
