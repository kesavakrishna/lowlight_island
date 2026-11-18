extends RefCounted
## Seed preview: a coloured, hill-shaded map of a generated island with objectives,
## caves, burrows, cover and the validated routes. Used by `--preview-seeds` and tests.
##
## Legend: red = crash, yellow = battery, magenta = radio shed, cyan = dock,
## black squares = caves, brown = burrows; white line = crash->battery,
## orange = battery->radio, pink = second radio approach, cyan line = radio->dock.

const BIOME_COLORS := [
	Color(0.10, 0.22, 0.36),   # sea
	Color(0.80, 0.74, 0.55),   # coast
	Color(0.55, 0.66, 0.36),   # grassland
	Color(0.20, 0.38, 0.20),   # forest
	Color(0.52, 0.49, 0.45),   # mountains
	Color(0.36, 0.40, 0.25),   # swamp
]


static func render(gen: RefCounted, px: int = 3) -> Image:
	var n: int = gen.n
	var img := Image.create(n * px, n * px, false, Image.FORMAT_RGB8)
	var light := Vector3(-0.6, 0.7, -0.4).normalized()
	for j in n:
		for i in n:
			var k := j * n + i
			var b: int = gen.biome[k]
			var col: Color = BIOME_COLORS[b]
			var h: float = gen.height[k]
			if b == 0:
				col = col.darkened(clampf(-h / 10.0, 0.0, 0.6))
			else:
				var hx: float = gen.height[j * n + mini(i + 1, n - 1)] - gen.height[j * n + maxi(i - 1, 0)]
				var hz: float = gen.height[mini(j + 1, n - 1) * n + i] - gen.height[maxi(j - 1, 0) * n + i]
				var nrm := Vector3(-hx, 4.0, -hz).normalized()
				col = col * (0.55 + 0.6 * maxf(nrm.dot(light), 0.0))
				if b == 4:
					col = col.lightened(clampf(h / 40.0, 0.0, 0.35))
			if gen.pool[k] == 1:
				col = Color(0.16, 0.24, 0.22)
			if gen.cliff[k] == 1 and b != 0:
				col = col.darkened(0.45)
			img.fill_rect(Rect2i(i * px, j * px, px, px), col)
	for g in gen.grass:
		_disc(img, gen, g["center"], g["radius"], Color(0.78, 0.82, 0.45), px, true)
	for t in gen.trees:
		var c: Vector2i = gen.to_cell(t["pos"])
		img.fill_rect(Rect2i(c.x * px + px / 2, c.y * px + px / 2, 1, 1), Color(0.05, 0.14, 0.05))
	for r in gen.rocks:
		_dot(img, gen, r["pos"], Color(0.3, 0.3, 0.3), px, 1)
	_line(img, gen, gen.routes.get("crash_battery", PackedVector3Array()), Color(1, 1, 1), px)
	_line(img, gen, gen.routes.get("battery_radio_alt", PackedVector3Array()), Color(1.0, 0.5, 0.75), px)
	_line(img, gen, gen.routes.get("battery_radio", PackedVector3Array()), Color(1.0, 0.6, 0.1), px)
	_line(img, gen, gen.routes.get("radio_dock", PackedVector3Array()), Color(0.4, 0.95, 1.0), px)
	for cv in gen.caves:
		_dot(img, gen, cv["origin"], Color(1, 1, 1), px, 4)
		_dot(img, gen, cv["origin"], Color(0, 0, 0), px, 3)
	for b2 in gen.burrows:
		_dot(img, gen, b2, Color(0.35, 0.2, 0.08), px, 3)
	_dot(img, gen, gen.crash, Color(1, 0.15, 0.1), px, 4)
	_dot(img, gen, gen.battery, Color(1, 0.9, 0.1), px, 4)
	_dot(img, gen, gen.radio, Color(0.95, 0.2, 0.95), px, 4)
	_dot(img, gen, gen.dock, Color(0.2, 0.9, 1.0), px, 4)
	return img


static func _dot(img: Image, gen: RefCounted, p: Vector3, col: Color, px: int, r: int) -> void:
	var c: Vector2i = gen.to_cell(p)
	var cx := c.x * px + px / 2
	var cy := c.y * px + px / 2
	img.fill_rect(Rect2i(cx - r, cy - r, r * 2 + 1, r * 2 + 1).intersection(Rect2i(Vector2i.ZERO, img.get_size())), col)


static func _disc(img: Image, gen: RefCounted, p: Vector3, radius: float, col: Color, px: int, ring: bool) -> void:
	var c: Vector2i = gen.to_cell(p)
	var rp := int(radius / gen.cell * px)
	for a in 48:
		var ang := TAU * a / 48.0
		var x := c.x * px + int(cos(ang) * rp)
		var y := c.y * px + int(sin(ang) * rp)
		if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
			img.set_pixel(x, y, col)


static func _line(img: Image, gen: RefCounted, path: PackedVector3Array, col: Color, px: int) -> void:
	for i in range(1, path.size()):
		var a: Vector2i = gen.to_cell(path[i - 1]) * px + Vector2i(px / 2, px / 2)
		var b: Vector2i = gen.to_cell(path[i]) * px + Vector2i(px / 2, px / 2)
		var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
		for s in steps + 1:
			var t := float(s) / maxf(steps, 1.0)
			var q := Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)))
			img.fill_rect(Rect2i(q.x, q.y, 2, 2).intersection(Rect2i(Vector2i.ZERO, img.get_size())), col)


## Several seeds side by side; rejected seeds show a dark tile.
static func contact_sheet(images: Array, cols: int) -> Image:
	if images.is_empty():
		return Image.create(1, 1, false, Image.FORMAT_RGB8)
	var w: int = images[0].get_width()
	var h: int = images[0].get_height()
	var rows := int(ceil(images.size() / float(cols)))
	var sheet := Image.create(cols * (w + 6), rows * (h + 6), false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.05, 0.05, 0.06))
	for i in images.size():
		var im: Image = images[i]
		sheet.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i((i % cols) * (w + 6) + 3, (i / cols) * (h + 6) + 3))
	return sheet
