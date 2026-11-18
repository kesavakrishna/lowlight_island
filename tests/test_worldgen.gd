extends "res://tests/suite.gd"
## Milestone 3 generator checks (LOWLIGHT_ISLAND.md §4 and §12 "Fresh world" / "Fair objective").

const IslandGen = preload("res://src/worldgen/island_gen.gd")
const SEEDS := [3, 17, 101, 2024, 77777, 424242]

var _cache := {}


func _gen(seed_value: int) -> RefCounted:
	if not _cache.has(seed_value):
		var g := IslandGen.new()
		g.generate(seed_value)
		_cache[seed_value] = g
	return _cache[seed_value]


func test_seeds_generate_valid_islands(_r) -> void:
	for s in SEEDS:
		var g := _gen(s)
		check(g.reject_reason == "" or g.routes.size() >= 4, "seed %d generated (%s)" % [s, g.reject_reason])
		for name in ["crash_battery", "battery_radio", "battery_radio_alt", "radio_dock"]:
			check(not (g.routes.get(name, PackedVector3Array()) as PackedVector3Array).is_empty(), "seed %d has route %s" % [s, name])


func test_replayed_seed_is_identical(_r) -> void:
	var a := IslandGen.new()
	var b := IslandGen.new()
	a.generate(555)
	b.generate(555)
	check(a.attempt == b.attempt, "same attempt accepted")
	check(a.height == b.height, "same heights")
	check(a.biome == b.biome, "same biomes")
	check(a.crash == b.crash and a.radio == b.radio and a.battery == b.battery and a.dock == b.dock, "same landmarks")
	check(a.trees.size() == b.trees.size() and a.caves.size() == b.caves.size(), "same trees and caves")


func test_new_seed_changes_the_layout(_r) -> void:
	var a := _gen(SEEDS[0])
	var b := _gen(SEEDS[1])
	var differ := 0
	for k in a.biome.size():
		if a.biome[k] != b.biome[k]:
			differ += 1
	check(float(differ) / a.biome.size() > 0.2, "biome layout differs between seeds (%.0f%%)" % (100.0 * differ / a.biome.size()))
	check(a.radio.distance_to(b.radio) > 20.0 or a.crash.distance_to(b.crash) > 20.0, "objectives move between seeds")


func test_all_core_biomes_present(_r) -> void:
	for s in SEEDS:
		var g := _gen(s)
		for b in ["grassland", "forest", "mountains", "swamp", "coast"]:
			check(g.shares.get(b, 0.0) >= Tuning.island_min_biome_share * (0.5 if b == "coast" else 1.0), "seed %d has %s (%.1f%%)" % [s, b, g.shares.get(b, 0.0) * 100.0])


func test_objectives_are_fair(_r) -> void:
	var budget := (Tuning.day_length + Tuning.dusk_length) * Tuning.route_budget_frac
	for s in SEEDS:
		var g := _gen(s)
		check(g.times["direct_objective"] <= budget, "seed %d direct route %.0fs within %.0fs" % [s, g.times["direct_objective"], budget])
		check(g.times["alt_overlap"] <= Tuning.alt_route_max_overlap, "seed %d radio approaches differ" % s)
		for lm in [g.crash, g.battery, g.radio, g.dock]:
			check(g.is_walkable_cell(g.to_cell(lm)), "seed %d objective at %s is on walkable ground" % [s, lm])
		check(g.biome_at(g.crash) == IslandGen.Biome.COAST, "seed %d crash on the coast" % s)
		check(g.biome_at(g.dock) == IslandGen.Biome.COAST, "seed %d dock on the coast" % s)
		check(g.spawn_points.size() >= 4, "seed %d has spawn points" % s)


func test_shelters_and_cover(_r) -> void:
	for s in SEEDS:
		var g := _gen(s)
		check(g.caves.size() >= 2, "seed %d has at least two caves" % s)
		check(g.burrows.size() >= 1, "seed %d has burrows" % s)
		check(g.trees.size() > 100, "seed %d has a real forest (%d trees)" % [s, g.trees.size()])
		check(g.grass.size() >= 8, "seed %d has tall grass" % s)
		var sturdy_with_landing := 0
		for t in g.trees:
			if t["rope_land"] != Vector3.INF:
				sturdy_with_landing += 1
				check(g.is_walkable_cell(g.to_cell(t["rope_land"])), "seed %d rope lands on walkable ground" % s)
		check(sturdy_with_landing > 20, "seed %d has rope landings" % s)


func test_height_lookup_matches_cells(_r) -> void:
	var g := _gen(SEEDS[2])
	for k in [g.n * 40 + 40, g.n * 75 + 75, g.n * 100 + 60]:
		var c := Vector2i(k % g.n, k / g.n)
		var p: Vector3 = g.cell_center(c)
		check(absf(g.height_at(p.x, p.z) - p.y) < 0.01, "height_at at cell centre %s" % c)
