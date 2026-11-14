extends RefCounted
## Top-down walkable grid used for creature pathing and route validation.
## Kept independent of rendering so it runs in headless tests.

var astar := AStarGrid2D.new()
var origin := Vector2.ZERO        # world XZ of the corner of cell (0, 0)
var size := Vector2i.ZERO
var cell := 1.0


func setup(p_origin: Vector2, p_size: Vector2i, p_cell: float = 1.0) -> void:
	origin = p_origin
	size = p_size
	cell = p_cell
	astar.region = Rect2i(Vector2i.ZERO, size)
	astar.cell_size = Vector2(cell, cell)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x - origin.x) / cell), floori((p.z - origin.y) / cell))


func cell_to_world(c: Vector2i, y: float = 0.0) -> Vector3:
	return Vector3(origin.x + (c.x + 0.5) * cell, y, origin.y + (c.y + 0.5) * cell)


func in_bounds(c: Vector2i) -> bool:
	return astar.is_in_boundsv(c)


func set_solid(c: Vector2i, solid: bool = true) -> void:
	if in_bounds(c):
		astar.set_point_solid(c, solid)


func is_solid(c: Vector2i) -> bool:
	return (not in_bounds(c)) or astar.is_point_solid(c)


func is_walkable(p: Vector3) -> bool:
	return not is_solid(world_to_cell(p))


## Mark every cell whose center lies inside an axis-aligned XZ rectangle (plus padding).
func block_rect(min_xz: Vector2, max_xz: Vector2, pad: float = 0.35, solid: bool = true) -> void:
	var a := Vector2i(ceili((min_xz.x - pad - origin.x) / cell - 0.5), ceili((min_xz.y - pad - origin.y) / cell - 0.5))
	var b := Vector2i(floori((max_xz.x + pad - origin.x) / cell - 0.5), floori((max_xz.y + pad - origin.y) / cell - 0.5))
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			set_solid(Vector2i(x, y), solid)


func block_circle(center: Vector3, radius: float, pad: float = 0.35) -> void:
	var r := radius + pad
	var a := world_to_cell(center - Vector3(r, 0, r))
	var b := world_to_cell(center + Vector3(r, 0, r))
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			var c := Vector2i(x, y)
			var w := cell_to_world(c)
			if Vector2(w.x - center.x, w.z - center.z).length() <= r:
				set_solid(c)


## Block everything outside a circle (island / clearing boundary).
func block_outside_circle(center: Vector3, radius: float) -> void:
	for x in size.x:
		for y in size.y:
			var c := Vector2i(x, y)
			var w := cell_to_world(c)
			if Vector2(w.x - center.x, w.z - center.z).length() > radius:
				set_solid(c)


func nearest_walkable(c: Vector2i, max_r: int = 8) -> Vector2i:
	if not is_solid(c):
		return c
	for r in range(1, max_r + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for x in range(c.x - r, c.x + r + 1):
			for y in range(c.y - r, c.y + r + 1):
				if absi(x - c.x) != r and absi(y - c.y) != r:
					continue
				var n := Vector2i(x, y)
				if not is_solid(n):
					var d := Vector2(n - c).length()
					if d < best_d:
						best_d = d
						best = n
		if best.x >= 0:
			return best
	return c


## Path in world space. Returns an empty array when unreachable.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var a := nearest_walkable(world_to_cell(from))
	var b := nearest_walkable(world_to_cell(to))
	if is_solid(a) or is_solid(b):
		return out
	var ids: Array[Vector2i] = astar.get_id_path(a, b)
	if ids.is_empty():
		return out
	var pts: Array[Vector3] = []
	for id in ids:
		pts.append(cell_to_world(id))
	if not is_solid(world_to_cell(to)):
		pts[pts.size() - 1] = Vector3(to.x, 0.0, to.z)
	# String-pull: drop points we can skip with a clear straight line.
	var i := 0
	out.append(pts[0])
	while i < pts.size() - 1:
		var j := pts.size() - 1
		while j > i + 1 and not line_clear(pts[i], pts[j]):
			j -= 1
		out.append(pts[j])
		i = j
	return out


func line_clear(a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var steps := int(ceil(d.length() / (cell * 0.35)))
	for s in range(steps + 1):
		var t := float(s) / maxf(steps, 1)
		var p := a.lerp(b, t)
		if is_solid(world_to_cell(p)):
			return false
		# Check a little to each side so paths keep clearance from corners.
		var side := Vector3(-d.y, 0, d.x).normalized() * (cell * 0.45)
		if is_solid(world_to_cell(p + side)) or is_solid(world_to_cell(p - side)):
			return false
	return true


func reachable(from: Vector3, to: Vector3) -> bool:
	return not find_path(from, to).is_empty()
