extends "res://tests/suite.gd"
## Building at slots: ladder -> platform -> rope / screens, damage stages, collapse,
## the cave wall, interrupted builds refunded, and a screen blocking a creature's view.

const MatchScript = preload("res://src/match/match.gd")
const D = preload("res://src/core/defs.gd")


func _make(r: Node) -> Node:
	var m := MatchScript.new()
	m.setup({"seed": 3, "world": "island", "roster": {1: {"name": "Builder", "slot": 0}}})
	r.add_child(m)
	return m


func _wait(r: Node, seconds: float) -> void:
	for i in int(seconds * 60.0):
		await r.get_tree().physics_frame


func _sturdy_tree(m: Node) -> Dictionary:
	for t in m.world.trees:
		if t["sturdy"] and t.get("rope_land", Vector3.INF) != Vector3.INF and t.has("canopy_pos"):
			return t
	return {}


func _climb_id(m: Node, tree_id: int) -> int:
	for it in m.world.interactables:
		if it["kind"] == "climb" and it["tree"] == tree_id:
			return it["id"]
	return -1


func test_ladder_platform_rope_and_screen(r: Node) -> void:
	var m := _make(r)
	var p: Node = m.local_player
	var t := _sturdy_tree(m)
	check(not t.is_empty(), "a sturdy tree with a rope landing exists")
	p.wood = 12
	var base: Vector3 = t["pos"]
	p.global_position = base + Vector3(t["trunk_r"] + 0.8, 0.1, 0)
	p.last_dry = p.global_position
	await _wait(r, 0.3)
	m.request("repair")   # V
	check(not m.building.jobs.is_empty(), "V at a trunk starts building a ladder")
	await _wait(r, Tuning.build_time + 0.3)
	check(t["ladder"] and p.wood == 10, "ladder built for 2 wood")
	m.request("interact", "climb", _climb_id(m, t["id"]))
	await _wait(r, Tuning.climb_ladder_time + 0.4)
	check(p.mode == D.Mode.PERCHED and p.perch == "canopy", "the ladder reaches the canopy")
	m.request("repair")
	await _wait(r, Tuning.build_time + 0.3)
	check(t["deck"] and p.mode == D.Mode.NORMAL, "built a platform and stand on it")
	await _wait(r, 0.5)
	check(p.tree_id == t["id"], "standing on the platform counts as in the tree (y %.1f)" % (p.global_position.y - base.y))
	m.request("repair")
	await _wait(r, Tuning.build_time + 0.3)
	check(t["rope"], "rope exit added toward the checked landing")
	m.request("repair")
	await _wait(r, Tuning.build_time + 0.3)
	var screens := 0
	for k in m.building.builds:
		if k.begins_with("screen:"):
			screens += 1
	check(screens == 1, "a screen on the side you face")
	# Shaking: damaged first, then the platform gives way and drops whoever is on it.
	m.building.shake(t["id"], 50.0)
	check(m.building.builds["deck:%d" % t["id"]]["hp"] == 50.0, "the platform is damaged, not gone")
	m.building.shake(t["id"], 60.0)
	check(not t["deck"] and not t["rope"], "a broken platform takes its rope with it")
	await _wait(r, 0.5)
	check(p.global_position.y - m.world.ground_y(p.global_position) < 1.0, "players on a collapsed platform end up on the ground")
	m.free()


func test_interrupted_build_refunds(r: Node) -> void:
	var m := _make(r)
	var p: Node = m.local_player
	var t: Dictionary = m.world.trees[0]
	p.wood = 4
	p.global_position = t["pos"] + Vector3(t["trunk_r"] + 0.8, 0.1, 0)
	await _wait(r, 0.2)
	m.request("repair")
	check(p.wood == 2, "wood is committed when building starts")
	p.global_position += Vector3(8, 0, 0)
	await _wait(r, 0.3)
	check(m.building.jobs.is_empty() and p.wood == 4, "walking away cancels and refunds")
	m.free()


func test_cave_wall_and_screen_blocks_sight(r: Node) -> void:
	var m := _make(r)
	var p: Node = m.local_player
	var cave: Dictionary = m.world.caves[0]
	p.global_position = cave["inside_point"] + Vector3(0, 0.1, 0)
	p.wood = 5
	await _wait(r, 0.3)
	check(p.cave_id == 0, "inside the cave")
	m.request("repair")
	await _wait(r, Tuning.build_time + 0.3)
	check(m.building.builds.has("wall:0"), "a low wall goes up inside the cave")
	check(p.wood == 3, "for 2 wood")
	m.building.damage("wall:0", 40.0)
	check(m.building.builds["wall:0"]["hp"] == 40.0, "walls take damage in stages")
	m.request("repair")
	await _wait(r, Tuning.build_time + 0.3)
	check(m.building.builds["wall:0"]["hp"] > 40.0 and p.wood == 2, "repairs cost less than building")
	m.free()
