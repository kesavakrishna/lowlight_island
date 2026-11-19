extends "res://tests/suite.gd"
## Reconnect: a dropped player's slot keeps its avatar (and the battery) for a grace
## period, then hands everything to the new connection; an expired slot frees the battery.

const MatchScript = preload("res://src/match/match.gd")
const D = preload("res://src/core/defs.gd")


func _make(r: Node) -> Node:
	var m := MatchScript.new()
	m.setup({"seed": 3, "world": "island", "roster": {
		1: {"name": "Host", "slot": 0}, 2: {"name": "Guest", "slot": 1}}})
	r.add_child(m)
	return m


func test_slot_waits_and_hands_over(r: Node) -> void:
	var m := _make(r)
	var guest: Node = m.players[2]
	var obj: RefCounted = m.objectives
	# The guest is carrying the battery when the connection drops.
	obj.battery_state = obj.Bat.CARRIED
	obj.carrier = 2
	guest.carrying = true
	guest.last_seq = 500
	m._on_peer_left(2)
	check(guest.away and m.players.has(2), "the slot and avatar stay in the match")
	check(guest.carrying and obj.carrier == 2, "the avatar keeps the battery while away")
	for i in 30:
		await r.get_tree().physics_frame
	check(not m.over, "a dropped player doesn't end the run")
	m._on_peer_rejoined(2, 77)
	check(m.players.has(77) and not m.players.has(2), "the slot moved to the new connection")
	check(guest.peer_id == 77 and guest.name == "77", "same avatar, new id")
	check(not guest.away and guest.last_seq == 0, "back in control; input numbering restarts")
	check(obj.carrier == 77 and guest.carrying, "still carrying the battery")
	m.free()


func test_expired_slot_drops_the_battery(r: Node) -> void:
	var saved := Tuning.reconnect_grace
	Tuning.reconnect_grace = 0.3
	var m := _make(r)
	var guest: Node = m.players[2]
	var obj: RefCounted = m.objectives
	obj.battery_state = obj.Bat.CARRIED
	obj.carrier = 2
	guest.carrying = true
	m._on_peer_left(2)
	for i in 40:
		await r.get_tree().physics_frame
	check(not m.players.has(2), "the slot is freed after the grace period")
	check(obj.battery_state == obj.Bat.DROPPED and obj.carrier == -1, "the battery stays recoverable")
	check(absf(obj.battery_pos.y - m.world.ground_y(obj.battery_pos)) < 0.3, "dropped on the ground")
	m.free()
	Tuning.reconnect_grace = saved
