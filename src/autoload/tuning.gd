extends Node
## Every tuned gameplay value lives here (autoload `Tuning`).
## Numbers are playtest starting points, not final balance.

# ---------------------------------------------------------------- session
var min_players_to_start := 1        # release target is 2–4; 1 is allowed for dev tests
var max_players := 4
var snapshot_rate := 20.0            # host -> client state snapshots per second
var reconnect_grace := 120.0         # a dropped player's slot (and avatar) waits this long
var default_port := 24680

# ---------------------------------------------------------------- clock (real seconds)
var day_length := 180.0
var dusk_length := 40.0
var night_length := 240.0
var dawn_length := 15.0
var clock_scale := 1.0               # --fast-clock speeds every phase up

# ---------------------------------------------------------------- player movement
var walk_speed := 3.2
var sprint_speed := 5.8
var crouch_speed := 1.8
var prone_speed := 0.9
var downed_crawl_speed := 0.45
var jump_velocity := 4.2
var gravity := 14.0
var accel := 14.0
var stand_height := 1.8
var crouch_height := 1.2
var prone_height := 0.6
var body_radius := 0.3
var eye_stand := 1.62
var eye_crouch := 1.02
var eye_prone := 0.36

# ---------------------------------------------------------------- stamina
var stamina_max := 100.0
var sprint_drain := 16.0
var stamina_regen := 14.0
var stamina_regen_delay := 1.0
var sprint_min_to_start := 15.0

# ---------------------------------------------------------------- noise radii (m, before creature hearing multiplier)
var noise_walk := 7.0
var noise_sprint := 20.0
var noise_crouch := 2.5
var noise_prone := 1.2
var noise_grass_rustle := 6.0
var noise_branch := 8.0
var noise_door := 12.0
var noise_noisemaker := 32.0
var noise_rope := 6.0
var footstep_interval := 0.45        # seconds between movement noise pulses
var cave_muffle := 0.5               # sounds made inside a closed cave carry this fraction

# ---------------------------------------------------------------- cover
var grass_height := 0.95
var grass_reveal_prone := 2.2        # a creature this close spots a prone player in grass
var grass_reveal_crouch := 3.5
var bush_reveal := 2.0

# ---------------------------------------------------------------- lantern and decoys
var lantern_range := 22.0
var lantern_angle := 30.0
var lantern_flicker_dist := 12.0     # real, host-driven warning: lantern flickers near a creature
var noisemakers_start := 2
var throw_speed := 13.0
var noisemaker_pulses := 4
var noisemaker_pulse_interval := 1.0

# ---------------------------------------------------------------- interaction and recovery
var interact_range := 2.2
var revive_time := 3.0
var revive_stamina := 30.0

# ---------------------------------------------------------------- trees
var climb_to_perch_time := 1.2
var climb_perch_to_canopy_time := 3.0
var climb_rough_time := 4.5
var climb_ladder_time := 1.6
var climb_bare_partway_time := 2.0
var bare_hang_time := 3.0
var climb_down_time := 1.6
var rope_time := 1.4
var climb_stamina_cost := 25.0

# ---------------------------------------------------------------- cave door
var door_hp := 100.0
var door_damaged_below := 60.0       # intact -> damaged (still blocks body sight, leaks light)
var door_breach_warn_below := 30.0   # "final moments before a breach" cue

# ---------------------------------------------------------------- island generation (milestone 3)
var island_cells := 150              # grid cells per side
var island_cell_size := 2.0          # metres per cell -> 300 m square, island ~250 m across
var island_cliff_step := 1.6         # max walkable height change between neighbouring cells (~39 deg)
var island_max_attempts := 16        # bounded retries before surfacing a failure
var island_min_biome_share := 0.04   # grassland, forest, mountains and swamp must each cover this much land
var carry_speed := 2.5               # battery carrier (no sprint, no climb) — used for route checks
var route_budget_frac := 0.85        # crash->battery (walk) + battery->radio (carry) must fit in this share of day+dusk
var alt_route_max_overlap := 0.45    # second radio approach may share at most this fraction with the first
var alt_route_max_cost := 1.8        # ...and cost at most this multiple of the first
var biome_cost := {                  # travel cost multipliers (1 = open grass)
	"coast": 1.05, "grassland": 1.0, "forest": 1.3, "mountains": 1.45, "swamp": 2.2,
}

# ---------------------------------------------------------------- escape run (milestone 4)
var broadcast_time := 150.0          # seconds of tended transmission (kept across interruptions)
var broadcast_noise := 70.0          # hum radius, before each creature's hearing multiplier
var broadcast_tend_radius := 3.0     # someone must stay this close to the transmitter
var broadcast_light_mult := 1.8      # the lit shed is seen this much farther than a lantern
var boarding_window := 100.0         # seconds the boat waits at the dock from dawn
var max_creatures := 6               # individuals in the pool; escalation decides how many wake
var wood_cap := 12                   # wood a survivor can carry
var wood_take := 2                   # per gather
var wood_near_wreck := 4             # three piles near the crash
var wood_far_piles := 7
var wood_far_amount := 3
var repair_cost := 1                 # repairs stay cheaper than replacing
var repair_hp := 35.0
var rebuild_cost := 3
var rebuild_hp := 60.0

# ---------------------------------------------------------------- creatures: night-one baseline per type
var creature_types := {
	"stalker": {
		"patrol_speed": 2.0,
		"investigate_speed": 3.0,
		"chase_speed": 5.0,           # hard-capped below sprint_speed, see creature_stats()
		"sight_range_day": 40.0,
		"sight_range_dark": 13.0,     # unlit player at night
		"lit_sight_range": 32.0,      # player carrying an open lantern
		"light_sight_range": 45.0,    # how far it notices a light source itself
		"fov_deg": 140.0,
		"hearing_mult": 0.6,          # weak hearing
		"awareness_rate": 2.2,        # per second at full visibility
		"climb_time": 8.0,
		"door_damage": 14.0,
		"door_hit_interval": 1.4,
		"search_time": 22.0,
		"catch_range": 1.35,
		"eye_height": 2.0,
	},
}

# ---------------------------------------------------------------- nightly escalation
# Ramp phase: linear additions per night up to the threshold night.
# Exponential phase: multiply readable values by growth_factor per night after it.
var escalation_threshold_night := 4
var escalation_growth := 1.5
var escalation_ramp := {
	"patrol_count": 0.5,      # extra individuals per night (rounded down)
	"speed": 0.06,            # +6% movement speed per night
	"sense": 0.06,            # +6% sight/hearing range per night
	"breach": 0.12,           # +12% door damage per night
	"search": 0.15,           # +15% search time per night
}
var max_sense_mult := 1.6     # sight/hearing ranges stop here
var max_speed_frac_of_sprint := 0.95


## Stats for one creature type on a given night, with escalation applied and caps enforced.
func creature_stats(type_name: String, night: int) -> Dictionary:
	var base: Dictionary = creature_types.get(type_name, creature_types["stalker"])
	var s := base.duplicate()
	var n: int = maxi(night, 1)
	var ramp_n: int = mini(n, escalation_threshold_night) - 1
	var exp_n: int = maxi(0, n - escalation_threshold_night)
	var speed_mult: float = 1.0 + escalation_ramp["speed"] * ramp_n
	var sense_mult: float = 1.0 + escalation_ramp["sense"] * ramp_n
	var breach_mult: float = (1.0 + escalation_ramp["breach"] * ramp_n) * pow(escalation_growth, exp_n)
	var search_mult: float = (1.0 + escalation_ramp["search"] * ramp_n) * pow(escalation_growth, exp_n)
	sense_mult = minf(sense_mult * pow(1.1, exp_n), max_sense_mult)
	for k in ["patrol_speed", "investigate_speed", "chase_speed"]:
		s[k] = minf(base[k] * speed_mult * pow(1.05, exp_n), sprint_speed * max_speed_frac_of_sprint)
	for k in ["sight_range_day", "sight_range_dark", "lit_sight_range", "light_sight_range"]:
		s[k] = base[k] * sense_mult
	s["hearing_mult"] = base["hearing_mult"] * sense_mult
	s["door_damage"] = base["door_damage"] * breach_mult
	s["search_time"] = base["search_time"] * search_mult
	s["climb_time"] = maxf(base["climb_time"] / speed_mult, 4.0)
	return s


## How many individuals patrol on a given night (before per-map caps).
func patrol_count(night: int) -> int:
	var n: int = maxi(night, 1)
	var ramp_n: int = mini(n, escalation_threshold_night) - 1
	var exp_n: int = maxi(0, n - escalation_threshold_night)
	var count: float = (1.0 + escalation_ramp["patrol_count"] * ramp_n) * pow(escalation_growth, exp_n)
	return int(floor(count))


func phase_length(phase: int) -> float:
	var l: float
	match phase:
		0: l = day_length
		1: l = dusk_length
		2: l = night_length
		_: l = dawn_length
	return l / maxf(clock_scale, 0.01)
