extends "res://tests/suite.gd"
## Integration tests: a real host-side match on an offline peer, stepped by physics.

const MatchScript = preload("res://src/match/match.gd")
const D = preload("res://src/core/defs.gd")


func _make(r: Node, start_phase: int = -1) -> Node:
	var m := MatchScript.new()
	m.setup({"seed": 7, "roster": {1: {"name": "Tester", "slot": 0}}})
	m.dev_start_phase = start_phase
	r.add_child(m)
	return m


func _wait(r: Node, seconds: float) -> void:
	var frames := int(seconds * 60.0)
	for i in frames:
		await r.get_tree().physics_frame


func _place(m: Node, pos: Vector3, yaw: float = 0.0) -> void:
	m.local_player.global_position = pos
	m.local_player.velocity = Vector3.ZERO
	m.look_yaw = yaw
	m.local_player.yaw = yaw


func _interactable_id(m: Node, kind: String, tree: int = -1) -> int:
	for it in m.world.interactables:
		if it["kind"] == kind and (tree < 0 or it.get("tree", -1) == tree):
			return it["id"]
	return -1


func test_climb_perch_canopy_and_rope(r: Node) -> void:
	var m := _make(r)
	var t: Dictionary = m.world.trees[0]
	var p: Node = m.local_player
	_place(m, t["pos"] + Vector3(1.2, 0.05, 0), PI * 0.5)   # face the trunk (-x)
	await _wait(r, 0.2)
	m.request("interact", "climb", _interactable_id(m, "climb", 0))
	await _wait(r, Tuning.climb_to_perch_time + 0.3)
	check(p.mode == D.Mode.PERCHED and p.perch == "perch", "hand climb reaches the low perch (mode %d perch '%s')" % [p.mode, p.perch])
	m.request("perch", "up")
	await _wait(r, Tuning.climb_perch_to_canopy_time + 0.6)
	check(p.mode == D.Mode.NORMAL and p.tree_id == 0, "reaches the deck and stands on it (mode %d tree %d y %.2f)" % [p.mode, p.tree_id, p.global_position.y])
	check(absf(p.global_position.y - t["deck_h"]) < 0.3, "standing at deck height (y %.2f)" % p.global_position.y)
	# Walk to the rope and slide down.
	var rope_top: Vector3 = t["rope_top"]
	var inward: Vector3 = (Vector3(t["pos"].x, rope_top.y, t["pos"].z) - rope_top).normalized()
	_place(m, rope_top + inward * 0.4 + Vector3(0, 0.05, 0), 0.0)
	await _wait(r, 0.2)
	m.request("interact", "rope", _interactable_id(m, "rope", 0))
	await _wait(r, Tuning.rope_time + 0.4)
	check(p.mode == D.Mode.NORMAL and p.tree_id == -1, "rope exit lands on the ground (mode %d tree %d)" % [p.mode, p.tree_id])
	check(p.global_position.distance_to(t["rope_land"]) < 1.0, "rope lands away from the trunk")
	m.free()


func test_bare_trunk_lets_go(r: Node) -> void:
	var m := _make(r)
	var t: Dictionary = m.world.trees[2]
	var p: Node = m.local_player
	# The bare tree has a ladder in the fixture; remove it to test the hand climb.
	t["ladder"] = false
	_place(m, t["pos"] + Vector3(0, 0.05, 1.1), 0.0)
	await _wait(r, 0.2)
	m.request("interact", "climb", _interactable_id(m, "climb", 2))
	await _wait(r, Tuning.climb_bare_partway_time + 0.3)
	check(p.mode == D.Mode.PERCHED and p.perch == "partway", "bare trunk: hang partway")
	await _wait(r, Tuning.bare_hang_time + 1.0)
	check(p.mode == D.Mode.NORMAL and p.global_position.y < 0.5, "grip gives out and the player drops (mode %d y %.2f)" % [p.mode, p.global_position.y])
	m.free()


func test_grass_conceals_prone_player(r: Node) -> void:
	var m := _make(r, D.Phase.NIGHT)
	await _wait(r, 0.1)
	var c: Node = m.creatures[0]
	var p: Node = m.local_player
	var g: Dictionary = m.world.grass[2]
	_place(m, g["center"] + Vector3(0, 0.05, 0))
	m.want_stance = D.Stance.PRONE
	await _wait(r, 0.3)
	c.global_position = g["center"] + Vector3(6.0, 0, 0)
	c.yaw = PI * 0.5   # facing -x, toward the player
	check(p.cover == "grass", "player registers grass cover")
	check(c.visibility_of(p) == 0.0, "prone player in grass is hidden at 6m")
	p.lantern_open = true
	check(c.visibility_of(p) > 0.0, "an open lantern gives the hide away")
	p.lantern_open = false
	m.want_stance = D.Stance.STAND
	await _wait(r, 0.3)
	check(c.visibility_of(p) > 0.0, "standing in grass is visible at 6m")
	c.yaw = -PI * 0.5
	check(c.visibility_of(p) == 0.0, "outside the field of view is unseen")
	m.free()


func test_witnessed_climb_commits_creature(r: Node) -> void:
	var m := _make(r, D.Phase.NIGHT)
	await _wait(r, 0.1)
	var c: Node = m.creatures[0]
	var t: Dictionary = m.world.trees[0]
	_place(m, t["pos"] + Vector3(1.2, 0.05, 0), PI * 0.5)
	c.global_position = t["pos"] + Vector3(9.0, 0, 0)
	c.yaw = PI * 0.5
	c._set_state(D.CState.PATROL, "test")
	c.patrol_target = c.global_position
	m.local_player.lantern_open = true
	m.request("interact", "climb", _interactable_id(m, "climb", 0))
	var committed := false
	for i in 240:
		await r.get_tree().physics_frame
		if c.state == D.CState.CLIMB and c.commit_tree == 0:
			committed = true
			break
	check(committed, "creature commits to the trunk it saw the player climb (state %s: %s)" % [D.CSTATE_NAMES[c.state], c.reason])
	m.free()


func test_unseen_patrol_passes(r: Node) -> void:
	# An unseen player crouched behind a rock lets a patrol walk by.
	var m := _make(r, D.Phase.NIGHT)
	await _wait(r, 0.1)
	var c: Node = m.creatures[0]
	var p: Node = m.local_player
	m.want_stance = D.Stance.CROUCH
	_place(m, Vector3(-8, 0.05, -5.6))     # behind the rock at (-8, -3)
	c.global_position = Vector3(-8, 0, 4)
	c._set_state(D.CState.PATROL, "test")
	c.patrol_target = Vector3(-8, 0, 12)
	c.yaw = PI
	for i in 180:
		await r.get_tree().physics_frame
	check(c.state != D.CState.CHASE, "a creature that never sees the player does not chase (%s: %s)" % [D.CSTATE_NAMES[c.state], c.reason])
	check(p.mode != D.Mode.DOWNED, "player survives the patrol")
	m.free()


func test_noisemaker_draws_creature(r: Node) -> void:
	var m := _make(r, D.Phase.NIGHT)
	await _wait(r, 0.1)
	var c: Node = m.creatures[0]
	_place(m, Vector3(-14, 0.05, 0), -PI * 0.5)   # far west, facing east
	c.global_position = Vector3(6, 0, 0)
	c.yaw = 0.0
	c._set_state(D.CState.PATROL, "test")
	c.patrol_target = Vector3(6, 0, -12)
	m.request("throw", -PI * 0.5, 0.2)
	var drawn := false
	for i in 360:
		await r.get_tree().physics_frame
		if c.state == D.CState.INVESTIGATE and c.reason.contains("noisemaker"):
			drawn = true
			break
	check(drawn, "creature investigates the noisemaker (%s: %s)" % [D.CSTATE_NAMES[c.state], c.reason])
	check(m.local_player.noisemakers == Tuning.noisemakers_start - 1, "throwing spends a noisemaker")
	m.free()


func test_cave_breach_damages_then_breaks_door(r: Node) -> void:
	var m := _make(r, D.Phase.NIGHT)
	await _wait(r, 0.1)
	var c: Node = m.creatures[0]
	var p: Node = m.local_player
	_place(m, m.world.cave["inside_point"] + Vector3(0, 0.05, 0))
	m.want_stance = D.Stance.CROUCH
	await _wait(r, 0.2)
	check(p.inside_cave, "player is inside the cave")
	check(m.world.door_blocks(), "door starts closed")
	c.global_position = m.world.cave["door_point"] + Vector3(0, 0, 1.5)
	c._start_breach("test")
	var saw_damaged := false
	var broke := false
	for i in 60 * 20:
		await r.get_tree().physics_frame
		var hp: float = m.world.cave["door_hp"]
		if hp < Tuning.door_damaged_below and hp > 0.0:
			saw_damaged = true
			check(m.world.door_blocks(), "a damaged door still blocks")
		if hp <= 0.0:
			broke = true
			break
	check(saw_damaged, "door passes through a damaged stage")
	check(broke, "a committed breach eventually breaks the door")
	check(not m.world.door_blocks(), "broken door no longer blocks")
	m.free()


func test_crawl_tunnel_needs_prone(r: Node) -> void:
	var m := _make(r)
	var p: Node = m.local_player
	_place(m, Vector3(1.8, 0.05, -26.0), PI * 0.5)   # inside, facing west into the tunnel
	m.want_stance = D.Stance.CROUCH
	await _wait(r, 0.2)
	for i in 120:
		m.local_player.input_queue.clear()
		p.simulate({"mx": 0.0, "my": -1.0, "yaw": PI * 0.5, "pitch": 0.0, "stance": D.Stance.CROUCH, "btn": 0}, 1.0 / 60.0)
	check(p.global_position.x > 0.9, "crouched players cannot fit the crawl tunnel (x %.2f)" % p.global_position.x)
	for i in 600:
		p.simulate({"mx": 0.0, "my": -1.0, "yaw": PI * 0.5, "pitch": 0.0, "stance": D.Stance.PRONE, "btn": 0}, 1.0 / 60.0)
	check(p.global_position.x < -1.2, "prone players crawl out the back (x %.2f)" % p.global_position.x)
	m.free()


func test_downed_ends_run_when_whole_crew_is_down(r: Node) -> void:
	var m := _make(r, D.Phase.NIGHT)
	await _wait(r, 0.1)
	var p: Node = m.local_player
	m.down_player(p, null)
	check(p.mode == D.Mode.DOWNED and p.stance == D.Stance.PRONE, "downed players are prone")
	await _wait(r, 0.1)
	check(m.over, "a fully downed crew ends the run")
	m.free()
