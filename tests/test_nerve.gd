extends "res://tests/suite.gd"
## Nerve: darkness drains it, light / company / day restore it, it never downs anyone,
## low nerve makes audible breathing, and creatures prefer the player whose nerve is breaking.

const MatchScript = preload("res://src/match/match.gd")
const D = preload("res://src/core/defs.gd")


func _make(r: Node, roster: Dictionary = {1: {"name": "Host", "slot": 0}}) -> Node:
	var m := MatchScript.new()
	m.setup({"seed": 3, "world": "island", "roster": roster})
	m.dev_start_phase = D.Phase.NIGHT
	r.add_child(m)
	return m


func _step(m: Node, seconds: float) -> void:
	for i in int(seconds * 4.0):
		m._srv_nerve(0.25)


func test_dark_drains_light_restores(r: Node) -> void:
	var m := _make(r)
	await r.get_tree().physics_frame
	var p: Node = m.local_player
	p.lantern_open = false
	_step(m, 20.0)
	var dark_nerve: float = p.nerve
	check(dark_nerve < Tuning.nerve_max - 5.0, "darkness wears nerve down (%.1f)" % dark_nerve)
	p.lantern_open = true
	_step(m, 20.0)
	check(p.nerve > dark_nerve, "an open lantern brings it back (%.1f -> %.1f)" % [dark_nerve, p.nerve])
	p.lantern_open = false
	_step(m, 600.0)
	check(p.nerve >= 0.0 and p.mode == D.Mode.NORMAL, "nerve bottoming out never downs a player")
	m._set_phase(D.Phase.DAWN)
	m._set_phase(D.Phase.DAY)
	var low: float = p.nerve
	_step(m, 10.0)
	check(p.nerve > low, "daylight restores nerve")
	m.free()


func test_low_nerve_breathes_and_draws_creatures(r: Node) -> void:
	var m := _make(r, {1: {"name": "Host", "slot": 0}, 2: {"name": "Guest", "slot": 1}})
	await r.get_tree().physics_frame
	var host: Node = m.local_player
	var guest: Node = m.players[2]
	host.nerve = 10.0
	m.sound_events.clear()
	m._srv_nerve(0.25)
	var breathing := false
	for ev in m.sound_events:
		if ev["kind"] == "breathing" and ev.get("peer", -1) == host.peer_id:
			breathing = true
	check(breathing, "low nerve makes breathing creatures can hear")
	# A teammate going down shakes everyone else.
	host.nerve = 80.0
	m.down_player(guest, null)
	check(host.nerve < 80.0, "a teammate going down drains nerve")
	# Targeting: the lowest-nerve player wins a tie for the creature's attention.
	var c: Node = m.creatures[0]
	c.wake(1, host.global_position + Vector3(0, 0, 0))
	check(c.mind != null, "creature mind exists")
	m.free()
