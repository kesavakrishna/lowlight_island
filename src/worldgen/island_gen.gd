extends RefCounted
## Seeded island generator (milestone 3). Pure data — no nodes, no rendering — so the
## host, every client and the headless tests produce the identical island from a seed.
##
## Pipeline (see LOWLIGHT_ISLAND.md §4):
##   1. land: low-frequency elevation with an edge falloff, ridged mountain ranges
##   2. biomes: elevation + moisture -> coast, grassland, forest, mountains, swamp
##   3. routes and cover: cliffs from slope, swamp pools, trees, tall grass, bushes, rocks, caves
##   4. landmarks: crash and dock on the coast, radio on high ground, battery site, burrows
##   5. validation: walk / carry routes, time budget, two radio approaches, reachable caves
## A rejected attempt is retried with the next attempt number, up to Tuning.island_max_attempts.

enum Biome { SEA, COAST, GRASS, FOREST, MOUNTAIN, SWAMP }
const BIOME_NAMES := ["sea", "coast", "grassland", "forest", "mountains", "swamp"]
const DIRS4 := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]   # matches cave facing 0..3 (+Z, +X, -Z, -X)
const RIGHTS := [Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1)]  # each facing's local +X in grid terms

var n := 150
var cell := 2.0
var seed_value := 0
var attempt := 0
var rng := RandomNumberGenerator.new()

var height := PackedFloat32Array()     # metres, per cell centre
var biome := PackedByteArray()
var walk := PackedByteArray()          # 1 = walkable on foot
var cliff := PackedByteArray()
var pool := PackedByteArray()          # deep swamp water
var blocked := PackedByteArray()       # structures / trunks / rocks (filled during placement)
var astar := AStarGrid2D.new()

# Results
var crash := Vector3.ZERO
var dock := Vector3.ZERO
var radio := Vector3.ZERO
var battery := Vector3.ZERO
var battery_kind := ""
var caves: Array[Dictionary] = []      # {origin: Vector3, facing: int}
var burrows: Array[Vector3] = []
var trees: Array[Dictionary] = []      # {pos, type, scale, yaw, rope_land}
var grass: Array[Dictionary] = []      # {center, radius}
var bushes: Array[Dictionary] = []     # {center, radius}
var rocks: Array[Dictionary] = []      # {pos, size, yaw}
var patrol_points: Array[Vector3] = []
var spawn_points: Array[Vector3] = []
var build_slots: Array[Dictionary] = []
var routes: Dictionary = {}            # name -> PackedVector3Array
var times: Dictionary = {}             # name -> seconds
var shares: Dictionary = {}            # biome name -> share of land
var reject_reason := ""
var log_lines: Array[String] = []


# ================================================================== entry points

## Generate the first valid island for `seed`. Returns true on success; on failure
## `reject_reason` explains the last rejection and the caller can surface a retry.
func generate(p_seed: int, max_attempts: int = -1) -> bool:
	var tries := Tuning.island_max_attempts if max_attempts < 0 else max_attempts
	for a in tries:
		if generate_attempt(p_seed, a):
			return true
		log_lines.append("seed %d attempt %d rejected: %s" % [p_seed, a, reject_reason])
	return false


## One deterministic attempt. Same (seed, attempt) -> same island on every machine.
func generate_attempt(p_seed: int, p_attempt: int) -> bool:
	seed_value = p_seed
	attempt = p_attempt
	n = Tuning.island_cells
	cell = Tuning.island_cell_size
	rng.seed = (p_seed * 1000003 + p_attempt * 7919 + 12345) & 0x7fffffffffffffff
	_reset()
	_build_land()
	_assign_biomes()
	_compute_walk()
	if not _place_landmarks():
		return false
	_place_caves()
	_compute_walk()
	_main = _component_from(to_cell(crash))
	_setup_astar()
	if not _validate_routes():
		return false
	_place_trees()
	_place_cover()
	_assign_rope_landings()
	# Trunks and boulders now block cells: the objective routes must still hold.
	_setup_astar()
	if not _validate_routes():
		reject_reason = "vegetation closed a route: " + reject_reason
		return false
	_place_burrows_and_patrols()
	if caves.size() < 2:
		reject_reason = "fewer than two usable caves"
		return false
	if burrows.is_empty():
		reject_reason = "no reachable burrow site"
		return false
	return true


# ================================================================== coordinates

func idx(c: Vector2i) -> int:
	return c.y * n + c.x


func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < n and c.y < n


func origin() -> Vector2:
	# World XZ of the corner of cell (0, 0). The island is centred on the world origin.
	return Vector2(-n * cell * 0.5, -n * cell * 0.5)


func cell_center(c: Vector2i) -> Vector3:
	var o := origin()
	return Vector3(o.x + (c.x + 0.5) * cell, height[idx(c)], o.y + (c.y + 0.5) * cell)


func to_cell(p: Vector3) -> Vector2i:
	var o := origin()
	return Vector2i(floori((p.x - o.x) / cell), floori((p.z - o.y) / cell))


## Ground height using the same triangulation the terrain mesh and its collision use:
## vertices at cell centres, each quad split along its (i, j)-(i+1, j+1) diagonal.
func height_at(x: float, z: float) -> float:
	var o := origin()
	var fx := (x - o.x) / cell - 0.5
	var fz := (z - o.y) / cell - 0.5
	var i := clampi(floori(fx), 0, n - 2)
	var j := clampi(floori(fz), 0, n - 2)
	var u := clampf(fx - i, 0.0, 1.0)
	var v := clampf(fz - j, 0.0, 1.0)
	var h00 := height[j * n + i]
	var h10 := height[j * n + i + 1]
	var h01 := height[(j + 1) * n + i]
	var h11 := height[(j + 1) * n + i + 1]
	if u >= v:
		return h00 + u * (h10 - h00) + v * (h11 - h10)
	return h00 + v * (h01 - h00) + u * (h11 - h01)


func biome_at(p: Vector3) -> int:
	var c := to_cell(p)
	return biome[idx(c)] if inside(c) else Biome.SEA


func is_walkable_cell(c: Vector2i) -> bool:
	return inside(c) and walk[idx(c)] == 1 and blocked[idx(c)] == 0


# ================================================================== 1. land

func _reset() -> void:
	var total := n * n
	height.resize(total)
	biome.resize(total)
	walk.resize(total)
	cliff.resize(total)
	pool.resize(total)
	blocked.resize(total)
	biome.fill(0)
	walk.fill(0)
	cliff.fill(0)
	pool.fill(0)
	blocked.fill(0)
	caves.clear()
	burrows.clear()
	trees.clear()
	grass.clear()
	bushes.clear()
	rocks.clear()
	patrol_points.clear()
	spawn_points.clear()
	build_slots.clear()
	routes.clear()
	times.clear()
	shares.clear()
	reject_reason = ""


func _noise(freq: float, octaves: int, kind: int = FastNoiseLite.FRACTAL_FBM) -> FastNoiseLite:
	var f := FastNoiseLite.new()
	f.seed = rng.randi()
	f.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	f.frequency = freq
	f.fractal_type = kind
	f.fractal_octaves = octaves
	return f


var _moist: FastNoiseLite
var _wood: FastNoiseLite
var _swamp_w := PackedFloat32Array()
var _mtn_w := PackedFloat32Array()
var _r_eff := PackedFloat32Array()


func _build_land() -> void:
	var shape := _noise(1.0 / 95.0, 3)
	var coast_wobble := _noise(1.0 / 38.0, 2)
	var hills := _noise(1.0 / 55.0, 4)
	var ridge := _noise(1.0 / 105.0, 4, FastNoiseLite.FRACTAL_RIDGED)
	var mtn_mask := _noise(1.0 / 140.0, 2)
	_moist = _noise(1.0 / 85.0, 3)
	_wood = _noise(1.0 / 70.0, 3)
	var radius := n * cell * 0.46
	# Random offsets pull mountains and swamps into different parts of each island.
	var mtn_bias := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.0, 0.35)
	var total := n * n
	_swamp_w.resize(total)
	_mtn_w.resize(total)
	_r_eff.resize(total)
	for j in n:
		for i in n:
			var c := Vector2i(i, j)
			var p := cell_center_xz(c)
			var r := p.length() / radius
			var re := r + coast_wobble.get_noise_2dv(p) * 0.16 + shape.get_noise_2dv(p) * 0.12
			var land := 1.0 - smoothstep(0.66, 1.0, re)
			var h := lerpf(-7.0, 2.6, land)
			h += hills.get_noise_2dv(p) * 2.6 * land
			var pn := p / radius
			var mask := smoothstep(0.05, 0.4, mtn_mask.get_noise_2dv(p) + mtn_bias.dot(pn) * 0.6) * (1.0 - smoothstep(0.45, 0.78, re))
			var rv := (ridge.get_noise_2dv(p) + 1.0) * 0.5
			var mtn := pow(rv, 2.4) * 26.0 * mask
			h += mtn
			_mtn_w[idx(c)] = mtn
			_r_eff[idx(c)] = re
			height[idx(c)] = h
	_smooth_land(1)
	# Swamps: wet lowland basins, flattened to just above sea level, with deep pools.
	for j in n:
		for i in n:
			var c := Vector2i(i, j)
			var k := idx(c)
			var p := cell_center_xz(c)
			var m := _moist.get_noise_2dv(p)
			var w := smoothstep(0.22, 0.34, m) * (1.0 - smoothstep(0.55, 0.72, _r_eff[k])) * (1.0 - smoothstep(4.0, 6.5, height[k])) * (1.0 - smoothstep(0.5, 2.0, _mtn_w[k]))
			_swamp_w[k] = w
			if w > 0.0:
				height[k] = lerpf(height[k], 0.25, w)
				if w > 0.85 and m > 0.46:
					height[k] = -0.7
					pool[k] = 1


func cell_center_xz(c: Vector2i) -> Vector2:
	var o := origin()
	return Vector2(o.x + (c.x + 0.5) * cell, o.y + (c.y + 0.5) * cell)


func _smooth_land(passes: int) -> void:
	for _p in passes:
		var src := height.duplicate()
		for j in range(1, n - 1):
			for i in range(1, n - 1):
				var s := 0.0
				for dj in range(-1, 2):
					for di in range(-1, 2):
						s += src[(j + dj) * n + i + di]
				height[j * n + i] = lerpf(src[j * n + i], s / 9.0, 0.6)


# ================================================================== 2. biomes

func _assign_biomes() -> void:
	# Distance to open sea (in cells) decides the coastal band.
	var sea_dist := _distance_field(func(k: int) -> bool: return height[k] < -0.4 and pool[k] == 0)
	_sea_dist = sea_dist
	for k in n * n:
		var h := height[k]
		var b := Biome.GRASS
		if h < -0.4 and pool[k] == 0:
			b = Biome.SEA
		elif _swamp_w[k] > 0.5 or pool[k] == 1:
			b = Biome.SWAMP
		elif sea_dist[k] <= 4 and h < 1.8:
			b = Biome.COAST
		elif _mtn_w[k] > 3.5 or h > 9.0:
			b = Biome.MOUNTAIN
		else:
			var c := Vector2i(k % n, k / n)
			b = Biome.FOREST if _wood.get_noise_2dv(cell_center_xz(c)) > -0.02 else Biome.GRASS
		biome[k] = b
	var land := 0
	var counts := [0, 0, 0, 0, 0, 0]
	for k in n * n:
		if biome[k] != Biome.SEA:
			land += 1
			counts[biome[k]] += 1
	for b in range(1, 6):
		shares[BIOME_NAMES[b]] = float(counts[b]) / maxf(land, 1.0)


func _distance_field(is_source: Callable) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(n * n)
	dist.fill(1 << 20)
	var queue: Array[int] = []
	for k in n * n:
		if is_source.call(k):
			dist[k] = 0
			queue.append(k)
	var head := 0
	while head < queue.size():
		var k := queue[head]
		head += 1
		var c := Vector2i(k % n, k / n)
		for d in DIRS4:
			var nc: Vector2i = c + d
			if inside(nc) and dist[idx(nc)] > dist[k] + 1:
				dist[idx(nc)] = dist[k] + 1
				queue.append(idx(nc))
	return dist


# ================================================================== walkability

func _compute_walk() -> void:
	var step := Tuning.island_cliff_step
	for j in n:
		for i in n:
			var c := Vector2i(i, j)
			var k := idx(c)
			var h := height[k]
			var steep := false
			for d in DIRS4:
				var nc: Vector2i = c + d
				if inside(nc) and absf(height[idx(nc)] - h) > step:
					steep = true
					break
			cliff[k] = 1 if steep else 0
			var ok := biome[k] != Biome.SEA and pool[k] == 0 and not steep and h > -0.45
			walk[k] = 1 if ok else 0


func _component_from(start: Vector2i) -> PackedByteArray:
	var comp := PackedByteArray()
	comp.resize(n * n)
	comp.fill(0)
	if not is_walkable_cell(start):
		return comp
	var queue: Array[Vector2i] = [start]
	comp[idx(start)] = 1
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in DIRS4:
			var nc: Vector2i = c + d
			if is_walkable_cell(nc) and comp[idx(nc)] == 0:
				comp[idx(nc)] = 1
				queue.append(nc)
	return comp


# ================================================================== 4. landmarks

var _main: PackedByteArray

func _largest_component() -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(n * n)
	seen.fill(0)
	var best := PackedByteArray()
	var best_size := 0
	for k in n * n:
		if walk[k] == 1 and seen[k] == 0:
			var comp := _component_from(Vector2i(k % n, k / n))
			var size := 0
			for q in n * n:
				if comp[q] == 1:
					seen[q] = 1
					size += 1
			if size > best_size:
				best_size = size
				best = comp
	return best


func _flat(c: Vector2i, r: int, tol: float) -> bool:
	var h := height[idx(c)]
	for dj in range(-r, r + 1):
		for di in range(-r, r + 1):
			var nc := c + Vector2i(di, dj)
			if not inside(nc) or _main[idx(nc)] == 0 or absf(height[idx(nc)] - h) > tol:
				return false
	return true


func _pick(cands: Array, score: Callable, top_frac: float) -> Vector2i:
	# Choose randomly among the best-scoring fraction so islands vary but stay sensible.
	if cands.is_empty():
		return Vector2i(-1, -1)
	var scored := []
	for c in cands:
		scored.append([score.call(c), c])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var take := maxi(1, int(scored.size() * top_frac))
	return scored[rng.randi() % take][1]


func _place_landmarks() -> bool:
	_main = _largest_component()
	var main_size := 0
	for k in n * n:
		main_size += _main[k]
	if main_size < n * n * 0.18:
		reject_reason = "walkable land too small or broken up (%d cells)" % main_size
		return false
	var span := n * cell
	var coast: Array = []
	var high: Array = []
	for k in n * n:
		if _main[k] == 0:
			continue
		var c := Vector2i(k % n, k / n)
		if biome[k] == Biome.COAST and _flat(c, 1, 0.8) and _near_sea(c, 5):
			coast.append(c)
		if biome[k] != Biome.SWAMP and biome[k] != Biome.COAST and _flat(c, 2, 0.9):
			high.append(c)
	if coast.size() < 10 or high.is_empty():
		reject_reason = "no usable coastline or high ground"
		return false
	var crash_c: Vector2i = coast[rng.randi() % coast.size()]
	crash = cell_center(crash_c)
	var dock_c := _pick(coast, func(c: Vector2i) -> float: return cell_center(c).distance_to(crash), 0.12)
	dock = cell_center(dock_c)
	if dock.distance_to(crash) < span * 0.4:
		reject_reason = "dock too close to the crash"
		return false
	var radio_c := _pick(high, func(c: Vector2i) -> float:
		var p := cell_center(c)
		var away := minf(p.distance_to(crash), p.distance_to(dock) * 1.4)
		var inland := minf(_dist_sea(c), 20) * 2.0
		return p.y * 9.0 + inland + minf(away, span * 0.28) - _open_penalty(c), 0.1)
	radio = cell_center(radio_c)
	if radio.distance_to(crash) < span * 0.25:
		reject_reason = "radio too close to the crash"
		return false
	# Battery: a beached skiff on the coast or salvage under a distinctive tree.
	battery_kind = "skiff" if rng.randf() < 0.5 else "salvage"
	var bat_cands: Array = []
	for k in n * n:
		if _main[k] == 0:
			continue
		var c := Vector2i(k % n, k / n)
		var ok := biome[k] == Biome.COAST if battery_kind == "skiff" else (biome[k] == Biome.FOREST or biome[k] == Biome.GRASS)
		if not ok or not _flat(c, 1, 0.6):
			continue
		var p := cell_center(c)
		var dc := p.distance_to(crash)
		if dc > span * 0.18 and dc < span * 0.55 and p.distance_to(radio) > span * 0.22 and p.distance_to(dock) > span * 0.12:
			bat_cands.append(c)
	if bat_cands.is_empty():
		reject_reason = "no battery site at a fair distance"
		return false
	var bat_c := _pick(bat_cands, func(c: Vector2i) -> float: return -absf(cell_center(c).distance_to(crash) - span * 0.33), 0.3)
	battery = cell_center(bat_c)
	for c in [crash_c, dock_c, radio_c, bat_c]:
		_flatten(c, 3, height[idx(c)])
	for i in 4:
		var a := TAU * i / 4.0 + 0.6
		spawn_points.append(crash + Vector3(cos(a), 0, sin(a)) * 3.5)
	return true


var _sea_dist := PackedInt32Array()

func _dist_sea(c: Vector2i) -> int:
	return _sea_dist[idx(c)]


func _near_sea(c: Vector2i, r: int) -> bool:
	for dj in range(-r, r + 1):
		for di in range(-r, r + 1):
			var nc := c + Vector2i(di, dj)
			if inside(nc) and biome[idx(nc)] == Biome.SEA:
				return true
	return false


func _open_penalty(c: Vector2i) -> float:
	# Prefer radio plots with room for several approaches.
	var blockedn := 0
	for dj in range(-5, 6):
		for di in range(-5, 6):
			var nc := c + Vector2i(di, dj)
			if not inside(nc) or _main[idx(nc)] == 0:
				blockedn += 1
	return blockedn * 0.6


func _flatten(c: Vector2i, r: int, h: float) -> void:
	for dj in range(-r - 1, r + 2):
		for di in range(-r - 1, r + 2):
			var nc := c + Vector2i(di, dj)
			if not inside(nc):
				continue
			var d := Vector2(di, dj).length()
			var w := 1.0 - smoothstep(float(r), float(r) + 1.5, d)
			height[idx(nc)] = lerpf(height[idx(nc)], h, w)


# ================================================================== 3. caves

func _place_caves() -> void:
	# A cave sits where walkable ground meets a rising cliff: mouth on the open side,
	# interior dug into the rock. Facing snaps to four directions so it fits the grid.
	var cands: Array = []
	for k in n * n:
		if _main[k] == 0 or biome[k] == Biome.SWAMP or biome[k] == Biome.COAST:
			continue
		var c := Vector2i(k % n, k / n)
		var h := height[k]
		for f in 4:
			var out: Vector2i = DIRS4[f]
			var back: Vector2i = -out
			var rise := height[idx(c + back * 3)] - h if inside(c + back * 3) else 0.0
			var rise2 := height[idx(c + back * 4)] - h if inside(c + back * 4) else 0.0
			if rise > 3.5 and rise2 > 3.5 and _front_clear(c, out):
				cands.append([c, f])
	_shuffle(cands)
	var want := 3
	for cf in cands:
		if caves.size() >= want:
			break
		var c: Vector2i = cf[0]
		var p := cell_center(c)
		var far_enough := true
		for cv in caves:
			if (cv["origin"] as Vector3).distance_to(p) < 45.0:
				far_enough = false
		for lm in [crash, dock, radio, battery]:
			if p.distance_to(lm) < 14.0:
				far_enough = false
		if not far_enough:
			continue
		_carve_cave(c, cf[1])
		caves.append({"origin": cell_center(c), "facing": cf[1]})


func _front_clear(c: Vector2i, out: Vector2i) -> bool:
	for s in range(0, 4):
		for side in range(-2, 3):
			var lateral := Vector2i(out.y, out.x) * side
			var nc: Vector2i = c + out * s + lateral
			if not inside(nc) or _main[idx(nc)] == 0 or absf(height[idx(nc)] - height[idx(c)]) > 1.2:
				return false
	return true


func _carve_cave(c: Vector2i, facing: int) -> void:
	var floor_h := height[idx(c)]
	var out: Vector2i = DIRS4[facing]
	var right: Vector2i = RIGHTS[facing]
	# Footprint (local z -4..1 cells, x -2..2) at floor height; the rock around it stays as cliff.
	for dz in range(-4, 2):
		for dx in range(-2, 3):
			var nc: Vector2i = c + out * dz + right * dx
			if inside(nc):
				height[idx(nc)] = floor_h
	# A trench on the local -X side from the crawl exit back out to the front.
	for dz in range(-3, 2):
		for dx in range(-4, -2):
			var nc2: Vector2i = c + out * dz + right * dx
			if inside(nc2):
				height[idx(nc2)] = floor_h


# ================================================================== 5. routes

func cost_of(k: int) -> float:
	var name: String = BIOME_NAMES[biome[k]]
	return Tuning.biome_cost.get(name, 1.0)


func _setup_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, n, n)
	astar.cell_size = Vector2(cell, cell)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for k in n * n:
		var c := Vector2i(k % n, k / n)
		if walk[k] == 0 or blocked[k] == 1:
			astar.set_point_solid(c, true)
		else:
			astar.set_point_weight_scale(c, cost_of(k))


func _path(a: Vector3, b: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var ids: Array[Vector2i] = astar.get_id_path(to_cell(a), to_cell(b))
	for id in ids:
		out.append(cell_center(id))
	return out


func path_cost(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		var seg := path[i - 1].distance_to(path[i])
		total += seg * cost_of(idx(to_cell(path[i])))
	return total


func _validate_routes() -> bool:
	var legs := {
		"crash_battery": [crash, battery, Tuning.walk_speed],
		"battery_radio": [battery, radio, Tuning.carry_speed],
		"radio_dock": [radio, dock, Tuning.walk_speed],
	}
	for name in legs:
		var leg: Array = legs[name]
		var path := _path(leg[0], leg[1])
		if path.is_empty():
			reject_reason = "no walkable route for %s" % name
			return false
		routes[name] = path
		times[name] = path_cost(path) / leg[2]
	var budget := (Tuning.day_length + Tuning.dusk_length) * Tuning.route_budget_frac
	var direct: float = times["crash_battery"] + times["battery_radio"]
	times["direct_objective"] = direct
	if direct > budget:
		reject_reason = "direct objective route takes %.0fs, budget %.0fs" % [direct, budget]
		return false
	# A second, materially different approach to the radio.
	var main_path: PackedVector3Array = routes["battery_radio"]
	var near_main := {}
	for pt in main_path:
		var c := to_cell(pt)
		for dj in range(-3, 4):
			for di in range(-3, 4):
				var nc := c + Vector2i(di, dj)
				if inside(nc):
					near_main[nc] = true
	# Keep the approach to the shed itself open: everyone must reach the same door.
	var radio_c := to_cell(radio)
	for nc in near_main.keys():
		var gate: Vector2i = nc
		if Vector2(gate - radio_c).length() > 6.0 and Vector2(gate - to_cell(battery)).length() > 6.0 and not astar.is_point_solid(gate):
			astar.set_point_weight_scale(gate, astar.get_point_weight_scale(gate) * 12.0)
	var alt := _path(battery, radio)
	for nc in near_main.keys():
		var gate2: Vector2i = nc
		if not astar.is_point_solid(gate2):
			astar.set_point_weight_scale(gate2, cost_of(idx(gate2)))
	if alt.is_empty():
		reject_reason = "only one approach to the radio"
		return false
	var shared := 0
	for pt in alt:
		var c2 := to_cell(pt)
		if near_main.has(c2) and Vector2(c2 - radio_c).length() > 6.0 and Vector2(c2 - to_cell(battery)).length() > 6.0:
			shared += 1
	var overlap := float(shared) / maxf(alt.size(), 1.0)
	var alt_ratio := path_cost(alt) / maxf(path_cost(main_path), 1.0)
	routes["battery_radio_alt"] = alt
	times["battery_radio_alt"] = path_cost(alt) / Tuning.carry_speed
	times["alt_overlap"] = overlap
	if overlap > Tuning.alt_route_max_overlap or alt_ratio > Tuning.alt_route_max_cost:
		reject_reason = "second radio approach not distinct enough (overlap %.0f%%, cost x%.2f)" % [overlap * 100.0, alt_ratio]
		return false
	for b in ["grassland", "forest", "mountains", "swamp"]:
		if shares.get(b, 0.0) < Tuning.island_min_biome_share:
			reject_reason = "too little %s (%.1f%%)" % [b, shares.get(b, 0.0) * 100.0]
			return false
	return true


# ================================================================== trees, cover, burrows

func _reserved(p: Vector3, r: float) -> bool:
	for lm in [crash, dock, radio, battery]:
		if Vector2(p.x - lm.x, p.z - lm.z).length() < r + 6.0:
			return true
	for cv in caves:
		var o: Vector3 = cv["origin"]
		if Vector2(p.x - o.x, p.z - o.z).length() < r + 11.0:
			return true
	return false


func _place_trees() -> void:
	var order: Array[int] = []
	for k in n * n:
		if _main[k] == 1:
			order.append(k)
	_shuffle(order)
	var spacing_grid := {}
	for k in order:
		var b := biome[k]
		var chance := 0.0
		var spacing := 6.0
		match b:
			Biome.FOREST:
				chance = 0.55
				spacing = 4.6
			Biome.GRASS:
				chance = 0.025
				spacing = 9.0
			Biome.COAST:
				chance = 0.04
				spacing = 7.0
			Biome.SWAMP:
				chance = 0.06
				spacing = 6.0
			Biome.MOUNTAIN:
				chance = 0.05
				spacing = 7.0
		if rng.randf() >= chance:
			continue
		var c := Vector2i(k % n, k / n)
		var p := cell_center(c) + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
		p.y = height_at(p.x, p.z)
		if _reserved(p, 1.0) or not _flat(c, 1, 1.0) or _too_close(spacing_grid, p, spacing):
			continue
		var type := "low"
		var roll := rng.randf()
		match b:
			Biome.COAST: type = "bare"
			Biome.GRASS: type = "low" if roll < 0.7 else "rough"
			Biome.SWAMP: type = "rough" if roll < 0.6 else "bare"
			Biome.MOUNTAIN: type = "rough"
			_: type = "low" if roll < 0.45 else ("rough" if roll < 0.88 else "bare")
		var t := {"pos": p, "type": type, "scale": rng.randf_range(0.88, 1.12), "yaw": rng.randf() * TAU, "rope_land": Vector3.INF}
		trees.append(t)
		_mark_spacing(spacing_grid, p)
		blocked[k] = 1


## Rope landings and platform build slots on sturdy trees (after rocks are placed).
func _assign_rope_landings() -> void:
	for i in trees.size():
		var t2: Dictionary = trees[i]
		if t2["type"] == "bare":
			continue
		for a in 8:
			var ang := TAU * a / 8.0 + rng.randf() * 0.3
			var land: Vector3 = t2["pos"] + Vector3(cos(ang), 0, sin(ang)) * 6.0
			var lc := to_cell(land)
			if is_walkable_cell(lc) and _main[idx(lc)] == 1:
				land.y = height_at(land.x, land.z)
				t2["rope_land"] = land
				build_slots.append({"kind": "platform", "tree": i, "rope_land": land})
				break


## Fisher-Yates with the island's own rng so every peer gets the same order.
func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func _too_close(grid: Dictionary, p: Vector3, spacing: float) -> bool:
	var key := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	for dj in range(-2, 3):
		for di in range(-2, 3):
			for q in grid.get(key + Vector2i(di, dj), []):
				if Vector2(p.x - q.x, p.z - q.z).length() < spacing:
					return true
	return false


func _mark_spacing(grid: Dictionary, p: Vector3) -> void:
	var key := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	if not grid.has(key):
		grid[key] = []
	grid[key].append(p)


func _place_cover() -> void:
	# Tall grass patches across grassland (and some forest edges); bushes in forest and swamp edges.
	var spacing := {}
	var tries := 0
	while tries < 900 and grass.size() < 26:
		tries += 1
		var k := rng.randi() % (n * n)
		if _main[k] == 0:
			continue
		var b := biome[k]
		if b != Biome.GRASS and not (b == Biome.FOREST and rng.randf() < 0.15) and not (b == Biome.SWAMP and rng.randf() < 0.3):
			continue
		var p := cell_center(Vector2i(k % n, k / n))
		if _reserved(p, 2.0) or _too_close(spacing, p, 13.0):
			continue
		grass.append({"center": p, "radius": rng.randf_range(3.0, 6.0)})
		_mark_spacing(spacing, p)
	tries = 0
	while tries < 900 and bushes.size() < 40:
		tries += 1
		var k2 := rng.randi() % (n * n)
		if _main[k2] == 0 or (biome[k2] != Biome.FOREST and biome[k2] != Biome.SWAMP and biome[k2] != Biome.GRASS):
			continue
		var p2 := cell_center(Vector2i(k2 % n, k2 / n))
		if _reserved(p2, 1.0) or _too_close(spacing, p2, 7.0):
			continue
		bushes.append({"center": p2, "radius": rng.randf_range(1.1, 1.6)})
		_mark_spacing(spacing, p2)
	# Boulders: line-of-sight breakers on grassland and at mountain feet.
	tries = 0
	while tries < 900 and rocks.size() < 30:
		tries += 1
		var k3 := rng.randi() % (n * n)
		if _main[k3] == 0 or (biome[k3] != Biome.GRASS and biome[k3] != Biome.MOUNTAIN and biome[k3] != Biome.COAST):
			continue
		var c3 := Vector2i(k3 % n, k3 / n)
		var p3 := cell_center(c3)
		if _reserved(p3, 2.5) or _too_close(spacing, p3, 9.0) or blocked[k3] == 1:
			continue
		var size := rng.randf_range(1.2, 2.4)
		rocks.append({"pos": p3, "size": size, "yaw": rng.randf() * TAU})
		_mark_spacing(spacing, p3)
		blocked[k3] = 1


func _place_burrows_and_patrols() -> void:
	_setup_astar()   # trees and rocks now block cells
	var span := n * cell
	var cands: Array = []
	for k in n * n:
		if _main[k] == 1 and blocked[k] == 0 and (biome[k] == Biome.FOREST or biome[k] == Biome.MOUNTAIN or biome[k] == Biome.GRASS):
			var c := Vector2i(k % n, k / n)
			var p := cell_center(c)
			if p.distance_to(crash) > span * 0.28 and not _reserved(p, 3.0) and _flat(c, 1, 0.8):
				cands.append(c)
	_shuffle(cands)
	for c in cands:
		if burrows.size() >= 3:
			break
		var p := cell_center(c)
		var ok := true
		for b in burrows:
			if b.distance_to(p) < span * 0.25:
				ok = false
		if ok and not astar.get_id_path(to_cell(crash), c).is_empty():
			burrows.append(p)
	# Patrol points: spread over the walkable island, weighted toward the objective legs.
	for name in ["crash_battery", "battery_radio", "battery_radio_alt", "radio_dock"]:
		var path: PackedVector3Array = routes.get(name, PackedVector3Array())
		for i in range(0, path.size(), 14):
			patrol_points.append(path[i])
	var pt_tries := 0
	while patrol_points.size() < 40 and pt_tries < 2000:
		pt_tries += 1
		var k4 := rng.randi() % (n * n)
		if _main[k4] == 1 and blocked[k4] == 0:
			var p4 := cell_center(Vector2i(k4 % n, k4 / n))
			var far := true
			for q in patrol_points:
				if q.distance_to(p4) < 22.0:
					far = false
					break
			if far:
				patrol_points.append(p4)
	# Drop caves whose door is no longer reachable after trees and rocks.
	var keep: Array[Dictionary] = []
	for cv in caves:
		var o: Vector3 = cv["origin"]
		var front: Vector3 = o + Vector3(DIRS4[cv["facing"]].x, 0, DIRS4[cv["facing"]].y) * cell * 2.0
		if not astar.get_id_path(to_cell(crash), to_cell(front)).is_empty():
			keep.append(cv)
	caves = keep
	for ci in caves.size():
		build_slots.append({"kind": "low_wall", "cave": ci})


## Short summary for logs and the preview tool.
func summary() -> String:
	return "seed %d (attempt %d): land %s | crash->battery %.0fs, battery->radio %.0fs carry (alt %.0fs, overlap %.0f%%), radio->dock %.0fs | %d caves, %d trees, %d grass patches, %d burrows" % [
		seed_value, attempt, _share_text(), times.get("crash_battery", 0.0), times.get("battery_radio", 0.0),
		times.get("battery_radio_alt", 0.0), times.get("alt_overlap", 0.0) * 100.0, times.get("radio_dock", 0.0),
		caves.size(), trees.size(), grass.size(), burrows.size()]


func _share_text() -> String:
	var parts: Array[String] = []
	for b in ["grassland", "forest", "mountains", "swamp", "coast"]:
		parts.append("%s %d%%" % [b, int(shares.get(b, 0.0) * 100.0)])
	return ", ".join(parts)
