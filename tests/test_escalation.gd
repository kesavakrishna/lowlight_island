extends "res://tests/suite.gd"


func test_speed_capped_below_sprint(_r) -> void:
	for n in range(1, 16):
		var s: Dictionary = Tuning.creature_stats("stalker", n)
		check(s["chase_speed"] < Tuning.sprint_speed, "night %d chase speed %.2f must stay below sprint" % [n, s["chase_speed"]])
		check(s["sight_range_dark"] <= Tuning.creature_types["stalker"]["sight_range_dark"] * Tuning.max_sense_mult + 0.001, "night %d sight capped" % n)


func test_nights_get_worse(_r) -> void:
	var prev: Dictionary = Tuning.creature_stats("stalker", 1)
	for n in range(2, 10):
		var s: Dictionary = Tuning.creature_stats("stalker", n)
		check(s["door_damage"] > prev["door_damage"], "night %d breaches faster than night %d" % [n, n - 1])
		check(s["search_time"] > prev["search_time"], "night %d searches longer" % n)
		prev = s
	var t := Tuning.escalation_threshold_night
	var a: float = Tuning.creature_stats("stalker", t)["door_damage"]
	var b: float = Tuning.creature_stats("stalker", t + 1)["door_damage"]
	var c: float = Tuning.creature_stats("stalker", t - 1)["door_damage"]
	check(b / a > a / c, "growth past the threshold is steeper than the ramp")


func test_patrol_count_grows(_r) -> void:
	check(Tuning.patrol_count(1) >= 1, "at least one creature on night one")
	check(Tuning.patrol_count(Tuning.escalation_threshold_night + 2) > Tuning.patrol_count(Tuning.escalation_threshold_night), "more creatures after the threshold")
