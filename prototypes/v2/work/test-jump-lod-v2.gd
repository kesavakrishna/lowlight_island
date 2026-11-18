extends SceneTree
# LowlightIsland-v2: Space jump through the game's own _physics_process, and tree LOD settings.
var failures := 0

func _initialize(): call_deferred("test")

func check(ok: bool, name: String) -> void:
	print(("PASS " if ok else "FAIL ")+name)
	if not ok:
		failures += 1

# Drop the player at a spot, let them settle, press Space, and return the peak height gained.
func jump_peak(g, spot: Vector3) -> float:
	g.player.position = spot
	g.player.velocity = Vector3.ZERO
	for i in range(30):
		await physics_frame
		g.step_world(1.0/60.0)
	var floor_y: float = g.player.position.y
	var peak := floor_y
	g.jump_requested = true
	for i in range(90):
		await physics_frame
		g.step_world(1.0/60.0)
		peak = maxf(peak,g.player.position.y)
	return peak-floor_y

func test():
	var g = load("res://island.tscn").instantiate()
	root.add_child(g)
	await physics_frame
	g.started = true
	g.time = 60.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Headless cannot capture the mouse (the game would sit paused), so drive step_world directly.
	var open_ground: Vector3 = g.field+g.side*4.0
	open_ground.y = g.elevation(open_ground)+0.2
	var h: float = await jump_peak(g,open_ground)
	check(h > 0.6 and h < 1.0,"Space jumps about 0.8 m on open ground (%.2f m)" % h)
	var landed: bool = absf(g.player.position.y-(g.elevation(g.player.position))) < 0.3
	check(landed,"lands back on the ground")
	g.carrying = true
	h = await jump_peak(g,open_ground)
	check(h > 0.15 and h < 0.5,"carrying the battery only hops (%.2f m)" % h)
	g.carrying = false
	# A jump pressed during a climb must not fire when the climb ends.
	var site = g.perches[1]
	for p in g.perches:
		if p != g.landmark_perch and p != g.perches[0] and p.higher != null and p.higher.limb_t >= 0.0:
			site = p
			break
	g.player.position = site.base+Vector3.UP*0.05
	g.interact()
	g.jump_requested = true
	var max_rise := 0.0
	for i in range(600):
		await physics_frame
		g.step_world(1.0/60.0)
		if g.climb_path.is_empty():
			break
	var seat_y: float = g.player.position.y
	for i in range(40):
		await physics_frame
		g.step_world(1.0/60.0)
		max_rise = maxf(max_rise,g.player.position.y-seat_y)
	check(max_rise < 0.2,"Space pressed while climbing does not fire afterwards (rise %.2f m)" % max_rise)
	# Jump on the branch and land back on it, still in the tree.
	h = await jump_peak(g,site.seat+Vector3.UP*0.05)
	check(h > 0.6 and g.perch != null and g.player.position.y > site.seat.y-0.5,"jump on a branch and land back on it (%.2f m, in tree %s)" % [h,g.perch != null])
	# LOD: every distant tree mesh casts shadows and takes over no closer than 10 m.
	var distant := 0
	var bad := 0
	for node in g.find_children("*","MeshInstance3D",true,false):
		var m: MeshInstance3D = node
		if m.visibility_range_begin > 0.0:
			distant += 1
			if m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or m.visibility_range_begin < 10.0 or m.visibility_range_begin_margin < 1.0:
				bad += 1
	check(distant > 100 and bad == 0,"distant tree meshes cast shadows and swap at 10 m+ with a margin (%d meshes, %d wrong)" % [distant,bad])
	quit(1 if failures else 0)
