extends "res://tests/suite.gd"

const Clearing = preload("res://src/world/test_clearing.gd")
const D = preload("res://src/core/defs.gd")


func _world() -> Node3D:
	var w := Clearing.new()
	w.build(1)
	return w


func test_routes_exist(_r) -> void:
	var w := _world()
	var spawn: Vector3 = w.spawn_points[0]
	check(w.grid.reachable(spawn, w.cave["door_point"]), "spawn -> cave door")
	check(w.grid.reachable(spawn, w.burrow_pos), "spawn -> burrow")
	for t in w.trees:
		check(w.grid.reachable(spawn, t["pos"] + Vector3(1.2, 0, 0)), "spawn -> tree %d" % t["id"])
		if t["rope"]:
			check(w.grid.is_walkable(t["rope_land"]), "rope %d lands on walkable ground" % t["id"])
	for p in w.patrol_points:
		check(w.grid.reachable(spawn, p), "spawn -> patrol point %s" % p)
	w.free()


func test_cave_door_controls_creature_access(_r) -> void:
	var w := _world()
	var outside: Vector3 = w.cave["door_point"]
	var inside: Vector3 = w.cave["inside_point"]
	w.set_door(false, Tuning.door_hp)
	var p: PackedVector3Array = w.grid.find_path(outside, inside)
	check(p.is_empty() or w.grid.world_to_cell(p[p.size() - 1]) != w.grid.world_to_cell(inside), "closed door must block the path inside")
	w.set_door(true, Tuning.door_hp)
	check(w.grid.reachable(outside, inside), "open door lets creatures in")
	w.set_door(false, 0.0)
	check(w.grid.reachable(outside, inside), "broken door lets creatures in")
	check(not w.door_blocks(), "broken door does not block")
	# The crawl tunnel never admits creatures.
	check(w.grid.is_solid(w.grid.world_to_cell(Vector3(0, 0, -26))), "tunnel is solid for creatures")
	w.free()


func test_cover_and_cave_queries(_r) -> void:
	var w := _world()
	check(w.cover_at(w.grass[0]["center"]) == "grass", "grass center is grass cover")
	check(w.cover_at(w.bushes[0]["center"]) == "bush", "bush center is bush cover")
	check(w.cover_at(Vector3(0, 0, -5)) == "", "open ground has no cover")
	check(w.in_cave(w.cave["inside_point"]), "inside point is in cave")
	check(w.in_cave(Vector3(0, 0, -26)), "tunnel counts as cave")
	check(not w.in_cave(w.cave["door_point"]), "door point is outside")
	var deck_tree: Dictionary = w.trees[0]
	check(w.deck_tree_at(deck_tree["pos"] + Vector3(1.0, deck_tree["deck_h"], 0)) == 0, "standing on the deck is in tree 0")
	check(w.deck_tree_at(deck_tree["pos"] + Vector3(1.0, 0, 0)) == -1, "ground under the deck is not in the tree")
	w.free()


func test_every_tree_climbable(_r) -> void:
	var w := _world()
	for t in w.trees:
		var ok: bool = t["ladder"] or t["type"] in ["low", "rough", "bare"]
		check(ok, "tree %d has a hand-climb or ladder route" % t["id"])
		check(t["canopy_h"] > 3.0, "tree %d has real height" % t["id"])
		if t["deck"]:
			check(t["sturdy"], "only sturdy trees take a platform")
	w.free()
