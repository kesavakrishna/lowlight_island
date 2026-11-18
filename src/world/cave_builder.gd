extends RefCounted
## Builds one cave scene: rock walls with real interior space, a hinged door with
## intact / damaged / broken states, and a prone-only crawl exit at the back.
## Authored in a local frame (door centre on the floor at the origin, mouth facing +Z),
## then placed with one of four facings so its footprint lines up with the walk grid.

const D = preload("res://src/core/defs.gd")
const Geo = preload("res://src/world/geo.gd")

# [min_x, max_x, min_z, max_z, min_y, max_y] in the cave's local frame.
const WALLS := [
	[-5.0, 5.0, -8.5, -6.5, 0.0, 3.6],     # back
	[-5.0, -3.0, -6.5, -6.0, 0.0, 3.6],    # left, behind the tunnel
	[-5.0, -3.0, -5.0, 0.5, 0.0, 3.6],     # left, in front of the tunnel
	[-5.0, -3.0, -6.0, -5.0, 0.8, 3.6],    # tunnel lintel (0.8 m clearance: prone only)
	[3.0, 5.0, -6.5, 0.5, 0.0, 3.6],       # right
	[-3.0, -1.0, -0.5, 0.5, 0.0, 3.6],     # front left
	[1.0, 3.0, -0.5, 0.5, 0.0, 3.6],       # front right
	[-1.0, 1.0, -0.5, 0.5, 2.2, 3.6],      # lintel over the door
	[-5.0, 5.0, -8.5, 0.5, 2.6, 3.6],      # roof
]
const INTERIOR := Rect2(Vector2(-3.0, -6.5), Vector2(6.0, 7.0))   # local x/z, includes the door passage
const TUNNEL := Rect2(Vector2(-5.0, -6.0), Vector2(2.0, 1.0))
const OUTCROP := [
	[Vector3(0, 3.9, -4.0), Vector3(11.5, 1.4, 10.0), 0.05],
	[Vector3(-3.0, 4.6, -5.5), Vector3(5.0, 1.8, 6.0), 0.4],
	[Vector3(3.5, 4.3, -2.5), Vector3(4.0, 1.6, 5.0), -0.3],
	[Vector3(6.2, 1.6, -3.5), Vector3(2.5, 3.2, 7.0), 0.15],
	[Vector3(0.0, 1.8, -9.5), Vector3(12.0, 3.6, 2.4), 0.0],
	[Vector3(-6.2, 1.5, -1.5), Vector3(2.0, 3.0, 4.0), 0.25],
	[Vector3(-6.0, 1.6, -8.5), Vector3(2.4, 3.2, 3.0), -0.2],
]


## facing: 0 = mouth toward +Z, 1 = +X, 2 = -Z, 3 = -X.
static func build(parent: Node3D, grid: RefCounted, id: int, origin: Vector3, facing: int, outcrop: bool = true) -> Dictionary:
	var basis := Basis(Vector3.UP, facing * PI * 0.5)
	var xf := Transform3D(basis, origin)
	var root := Node3D.new()
	root.name = "Cave%d" % id
	root.transform = xf
	parent.add_child(root)
	var rock_dark := Geo.mat(Color(0.2, 0.2, 0.19))
	var rock := Geo.mat(Color(0.33, 0.32, 0.3))
	var wood := Geo.mat(Color(0.45, 0.33, 0.2))
	var wood_dark := Geo.mat(Color(0.28, 0.2, 0.12))

	for w in WALLS:
		var size := Vector3(w[1] - w[0], w[5] - w[4], w[3] - w[2])
		var center := Vector3((w[0] + w[1]) * 0.5, (w[4] + w[5]) * 0.5, (w[2] + w[3]) * 0.5)
		Geo.box(root, size, center, rock_dark)
		if w[4] < 0.5:
			_block_local(grid, xf, Vector2(w[0], w[2]), Vector2(w[1], w[3]), 0.2)
	# The crawl tunnel is too narrow for creatures.
	_block_local(grid, xf, TUNNEL.position, TUNNEL.end, 0.1)
	if outcrop:
		for r in OUTCROP:
			Geo.box(root, r[1], r[0], rock, D.L_WORLD | D.L_SIGHT, r[2])
			if r[0].y - r[1].y * 0.5 < 0.5:
				var half := Vector2(r[1].x, r[1].z) * 0.5
				_block_local(grid, xf, Vector2(r[0].x, r[0].z) - half, Vector2(r[0].x, r[0].z) + half, 0.35)
	Geo.box(root, Vector3(6, 0.02, 7), Vector3(0, 0.01, -3.0), rock_dark, 0)
	Geo.box(root, Vector3(2, 0.02, 1), Vector3(-4, 0.01, -5.5), rock_dark, 0)

	# Door hinged at local x = -1, swings outward when open.
	var pivot := Node3D.new()
	pivot.position = Vector3(-1.0, 0, 0)
	root.add_child(pivot)
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 2.2, 0.14)
	var body := Geo.static_body(pivot, shape, Transform3D(Basis.IDENTITY, Vector3(1.0, 1.1, 0)), D.L_WORLD | D.L_SIGHT)
	body.name = "CaveDoor%d" % id
	var intact := Node3D.new()
	pivot.add_child(intact)
	Geo.box(intact, Vector3(1.96, 2.18, 0.12), Vector3(1.0, 1.1, 0), wood, 0)
	Geo.box(intact, Vector3(1.96, 0.14, 0.16), Vector3(1.0, 0.5, 0.03), wood_dark, 0)
	Geo.box(intact, Vector3(1.96, 0.14, 0.16), Vector3(1.0, 1.7, 0.03), wood_dark, 0)
	var damaged := Node3D.new()
	pivot.add_child(damaged)
	for i in 5:
		var h := 2.18 - (0.35 if i % 2 == 1 else 0.0)
		Geo.box(damaged, Vector3(0.34, h, 0.12), Vector3(0.2 + i * 0.4, h * 0.5, 0), wood_dark, 0, 0.0, Vector3(0, 0, (i - 2) * 0.03))
	Geo.box(damaged, Vector3(1.96, 0.14, 0.16), Vector3(1.0, 0.5, 0.03), wood_dark, 0, 0.0, Vector3(0, 0, 0.06))
	var broken := Node3D.new()
	pivot.add_child(broken)
	for i in 6:
		Geo.box(broken, Vector3(0.3, 0.08, 1.0 + (i % 3) * 0.3), Vector3(0.2 + i * 0.33, 0.04, 0.8 + (i % 2) * 0.5), wood_dark, 0, 0.4 * i)

	var cells: Array = []
	for lx in [-0.5, 0.5]:
		var c: Vector2i = grid.world_to_cell(xf * Vector3(lx, 0, 0))
		if not cells.has(c):
			cells.append(c)
	var cave := {
		"id": id, "xform": xf, "facing": facing,
		"door_point": xf * Vector3(0, 0, 1.6),
		"inside_point": xf * Vector3(0, 0, -3.0),
		"door_center": xf * Vector3(0, 1.1, 0),
		"tunnel_exit": xf * Vector3(-5.8, 0, -5.5),
		"search_spots": [xf * Vector3(0, 0, -3.0), xf * Vector3(-2.0, 0, -5.5), xf * Vector3(2.0, 0, -5.5), xf * Vector3(-2.4, 0, -5.5)],
		"door_cells": cells, "door_open": false, "door_hp": Tuning.door_hp,
		"door_body": body, "door_pivot": pivot,
		"door_vis": {"intact": intact, "damaged": damaged, "broken": broken},
	}
	return cave


static func contains(cave: Dictionary, p: Vector3) -> bool:
	var xf: Transform3D = cave["xform"]
	var l := xf.affine_inverse() * p
	if l.y < -1.0 or l.y > 2.5:
		return false
	var xz := Vector2(l.x, l.z)
	return INTERIOR.has_point(xz) or TUNNEL.has_point(xz)


static func apply_door(cave: Dictionary, grid: RefCounted, open: bool, hp: float) -> void:
	var broken := hp <= 0.0
	var damaged := hp < Tuning.door_damaged_below
	cave["door_open"] = open
	cave["door_hp"] = hp
	var blocks := not open and not broken
	var body: StaticBody3D = cave["door_body"]
	body.collision_layer = (D.L_WORLD | D.L_SIGHT) if blocks else 0
	var pivot: Node3D = cave["door_pivot"]
	pivot.rotation.y = 0.0 if (blocks or broken) else deg_to_rad(-100.0)
	var vis: Dictionary = cave["door_vis"]
	vis["intact"].visible = not broken and not damaged
	vis["damaged"].visible = not broken and damaged
	vis["broken"].visible = broken
	for c in cave["door_cells"]:
		grid.set_solid(c, blocks)


static func door_blocks(cave: Dictionary) -> bool:
	return not cave["door_open"] and cave["door_hp"] > 0.0


static func _block_local(grid: RefCounted, xf: Transform3D, a: Vector2, b: Vector2, pad: float) -> void:
	var p1 := xf * Vector3(a.x, 0, a.y)
	var p2 := xf * Vector3(b.x, 0, b.y)
	grid.block_rect(Vector2(minf(p1.x, p2.x), minf(p1.z, p2.z)), Vector2(maxf(p1.x, p2.x), maxf(p1.z, p2.z)), pad)
