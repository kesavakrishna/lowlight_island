extends "res://tests/suite.gd"
## Integration tests on a generated island: the match, physics, climbing anchors on
## real branches, caves cut into terrain, and creature pathing all on one seed.

const MatchScript = preload("res://src/match/match.gd")
const D = preload("res://src/core/defs.gd")
const SEED := 3


func _make(r: Node, start_phase: int = -1) -> Node:
	var m := MatchScript.new()
	m.setup({"seed": SEED, "world": "island", "roster": {1: {"name": "Tester", "slot": 0}}})
	m.dev_start_phase = start_phase
	r.add_child(m)
	return m


func _wait(r: Node, seconds: float) -> void:
	for i in int(seconds * 60.0):
		await r.get_tree().physics_frame


func _place(m: Node, pos: Vector3, yaw: float = 0.0) -> void:
	m.local_player.global_position = pos
	m.local_player.velocity = Vector3.ZERO
	m.local_player.last_dry = pos
	m.look_yaw = yaw
	m.local_player.yaw = yaw


func _climb_id(m: Node, tree_id: int) -> int:
	for it in m.world.interactables:
		if it["kind"] == "climb" and it["tree"] == tree_id:
			return it["id"]
	return -1


func test_spawn_on_solid_ground(r: Node) -> void:
	var m := _make(r)
	var p: Node = m.local_player
	var start: Vector3 = p.global_position
	await _wait(r, 1.0)
	check(p.is_on_floor(), "player stands on the terrain at spawn")
	check(absf(p.global_position.y - start.y) < 0.6, "player did not fall through or pop up (%.2f -> %.2f)" % [start.y, p.global_position.y])
	check(not m.world.in_water(p.global_position), "spawn is dry")
	m.free()


func test_climb_low_tree_on_real_branches(r: Node) -> void:
	var m := _make(r)
	var p: Node = m.local_player
	var t: Dictionary = {}
	for tr in m.world.trees:
		if tr["type"] == "low" and tr.has("perch_pos"):
			t = tr
			break
	check(not t.is_empty(), "island has a low-branch tree with a perch")
	if t.is_empty():
		m.free()
		return
	var base: Vector3 = t["pos"]
	var away := Vector3(1, 0, 0)
	_place(m, base + away * (t["trunk_r"] + 0.9) + Vector3(0, 0.1, 0), PI * 0.5)
	await _wait(r, 0.3)
	m.request("interact", "climb", _climb_id(m, t["id"]))
	await _wait(r, Tuning.climb_to_perch_time + 0.3)
	check(p.mode == D.Mode.PERCHED and p.perch == "perch", "reaches the low perch (mode %d)" % p.mode)
	check(p.global_position.distance_to(t["perch_pos"]) < 0.5, "perch sits on the recorded branch")
	check(p.global_position.y - base.y > 1.5, "the perch is off the ground (%.1f m)" % (p.global_position.y - base.y))
	m.request("perch", "up")
	await _wait(r, Tuning.climb_perch_to_canopy_time + 0.4)
	check(p.mode == D.Mode.PERCHED and p.perch == "canopy", "reaches the canopy")
	check(p.global_position.y - base.y > t["perch_h"], "canopy is above the perch")
	m.request("perch", "down")
	await _wait(r, Tuning.climb_down_time + 0.5)
	check(p.mode == D.Mode.NORMAL, "climbs back down")
	check(absf(p.global_position.y - m.world.ground_y(p.global_position)) < 0.6, "lands on the ground")
	m.free()


func test_cave_is_enterable_and_breachable(r: Node) -> void:
	var m := _make(r, D.Phase.NIGHT)
	var p: Node = m.local_player
	check(m.world.caves.size() >= 2, "island has caves")
	var cave: Dictionary = m.world.caves[0]
	m.world.set_door(true, Tuning.door_hp, 0)
	var door_point: Vector3 = cave["door_point"]
	var inside: Vector3 = cave["inside_point"]
	var yaw := atan2(door_point.x - inside.x, door_point.z - inside.z)
	_place(m, door_point + Vector3(0, 0.3, 0), yaw)
	await _wait(r, 0.2)
	var reached := false
	for i in 240:
		p.input_queue.clear()
		p.input_queue.append({"mx": 0.0, "my": -1.0, "yaw": yaw, "pitch": 0.0, "stance": D.Stance.STAND, "btn": 0})
		await r.get_tree().physics_frame
		if p.inside_cave:
			reached = true
			break
	check(reached, "walked through the open door into the cave (at %s)" % p.global_position)
	await _wait(r, 0.5)
	check(absf(p.global_position.y - (cave["xform"] as Transform3D).origin.y) < 0.5, "stands on the cave floor, not the terrain above")
	# The creature can path to the door from its burrow.
	var path: PackedVector3Array = m.world.grid.find_path(m.world.burrow_pos, door_point)
	check(not path.is_empty(), "creature can reach the cave door")
	m.world.set_door(false, Tuning.door_hp, 0)
	var c: Node = m.creatures[0]
	c.global_position = door_point + Vector3(0, 0.2, 0)
	c._start_breach(0, "test")
	var hit := false
	for i in 60 * 6:
		await r.get_tree().physics_frame
		if m.world.caves[0]["door_hp"] < Tuning.door_hp:
			hit = true
			break
	check(hit, "creature reaches and damages an island cave door (%s)" % c.reason)
	m.free()


func test_creature_paths_across_the_island(r: Node) -> void:
	var m := _make(r)
	var lm: Dictionary = m.world.landmarks
	for name in ["crash", "battery", "radio", "dock"]:
		var path: PackedVector3Array = m.world.grid.find_path(m.world.burrow_pos, lm[name])
		check(not path.is_empty(), "creature path from burrow to %s" % name)
	check(m.world.patrol_points.size() >= 10, "patrol points cover the island")
	m.free()
