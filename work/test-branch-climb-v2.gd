extends SceneTree
# Free-climbing checks for LowlightIsland-v2 (stage A):
#  - climbing to a real-branch fork leaves the player standing on that tree's footing
#  - the player can walk outward along the branch for a couple of metres
#  - Space climbs to the higher fork, E climbs down to the ground
#  - reports leaf cover at seats so LEAFY_COVER can be tuned
var failures := 0

func _initialize(): call_deferred("test")

func check(ok: bool, name: String) -> void:
	print(("PASS " if ok else "FAIL ")+name)
	if not ok:
		failures += 1

func settle(g, frames: int, move := Vector3.ZERO) -> void:
	for i in range(frames):
		await physics_frame
		g.player.velocity = Vector3(move.x,g.player.velocity.y-18.0/60.0,move.z)
		g.player.move_and_slide()
		g.perch = g.tree_perch_at(g.player.position) if on_tree_wood(g) else g.perch
		if g.perch != null:
			g.step_over_twig(move/60.0)

func on_tree_wood(g) -> bool:
	for i in range(g.player.get_slide_collision_count()):
		var hit = g.player.get_slide_collision(i).get_collider()
		if hit is Node and hit.has_meta("climbable"):
			return true
	return false

func test():
	var covers: Array[int] = []
	var palms: Array = []
	var palm_tried := 0
	var palm_ok := 0
	var tried := 0
	var stood := 0
	var walked := 0
	var cycles := 0
	for run in range(4):
		var g = load("res://island.tscn").instantiate()
		root.add_child(g)
		await physics_frame
		await physics_frame
		var sample := 0
		for root_perch in g.perches:
			if root_perch == g.landmark_perch or root_perch == g.perches[0]:
				continue
			if root_perch.higher == null:
				palms.append(root_perch)
				continue
			for fork in [root_perch,root_perch.higher]:
				covers.append(g.leaf_cover(fork,fork.seat+Vector3.UP*0.82))
			sample += 1
			if sample > 12:
				continue
			# Climb from the ground like a player.
			tried += 1
			g.perch = null
			g.climb_path.clear()
			g.player.position = root_perch.base+Vector3.UP*0.05
			var act: String = g.action()
			g.interact()
			if g.perch != root_perch:
				# Another action or a closer trunk took the E press; not this tree's climb.
				print("  skipped: E at this base did '%s'" % act)
				tried -= 1
				continue
			while not g.climb_path.is_empty():
				g.advance_climb(0.25)
			g.player.velocity = Vector3.ZERO
			await settle(g,20)
			if g.player.is_on_floor() and on_tree_wood(g) and g.player.position.distance_to(root_perch.seat) < 0.6:
				stood += 1
			else:
				var at: Array = g.trunk_at(root_perch,root_perch.seat.y)
				print("  did not settle on fork: drop %.2f m, %s scale %.2f, seat %.2f m from trunk axis (bark at %.2f), high fork %s" % [root_perch.seat.y-g.player.position.y, root_perch.kind, root_perch.pose.basis.x.length(), Vector2(root_perch.seat.x-at[0].x,root_perch.seat.z-at[0].z).length(), at[1], root_perch.higher.kind])
			# Walk outward along the branch for 0.8 s.
			var start: Vector3 = g.player.position
			await settle(g,48,root_perch.heading*2.6)
			var out: float = (g.player.position-start).dot(root_perch.heading)
			if out > 1.2 and g.player.position.y > start.y-0.6:
				walked += 1
			else:
				print("  branch walk: out %.2f m, height change %.2f" % [out,g.player.position.y-start.y])
			# Back to the trunk, up, and down again.
			g.perch = root_perch
			g.player.position = root_perch.seat
			g.climb_higher()
			while not g.climb_path.is_empty():
				g.advance_climb(0.25)
			var high_ok: bool = g.perch == root_perch.higher and g.player.position.is_equal_approx(root_perch.higher.seat)
			g.interact()
			while not g.climb_path.is_empty():
				g.advance_climb(0.25)
			if high_ok and g.perch == null and g.player.position.is_equal_approx(root_perch.base):
				cycles += 1
		# Palms: climb the leaning trunk, stand in the crown, climb down.
		for palm in palms.slice(0,4):
			palm_tried += 1
			g.perch = null
			g.climb_path.clear()
			g.player.position = palm.base+Vector3.UP*0.05
			g.interact()
			if g.perch != palm:
				palm_tried -= 1
				continue
			while not g.climb_path.is_empty():
				g.advance_climb(0.25)
			g.player.velocity = Vector3.ZERO
			await settle(g,20)
			var up_ok: bool = g.player.is_on_floor() and on_tree_wood(g) and g.player.position.distance_to(palm.seat) < 0.6
			g.perch = palm
			g.interact()
			while not g.climb_path.is_empty():
				g.advance_climb(0.25)
			if up_ok and g.perch == null and g.player.position.is_equal_approx(palm.base):
				palm_ok += 1
			else:
				print("  palm: up_ok=%s down at %s base %s" % [up_ok,g.player.position,palm.base])
		palms.clear()
		g.queue_free()
		await physics_frame
	check(palm_tried > 0 and palm_ok == palm_tried,"climb a palm, stand in its crown, climb down (%d/%d)" % [palm_ok,palm_tried])
	covers.sort()
	var n := covers.size()
	print("leaf cover at crouched head height over %d forks: 10%%=%d 25%%=%d median=%d 75%%=%d 90%%=%d" % [n,covers[n/10],covers[n/4],covers[n/2],covers[n*3/4],covers[n*9/10]])
	check(stood >= tried*0.9,"climbing settles onto the tree's footing (%d/%d)" % [stood,tried])
	check(walked >= tried*0.75,"walk outward along a branch from the seat (%d/%d)" % [walked,tried])
	check(cycles == tried,"climb higher with Space, then climb down to the ground (%d/%d)" % [cycles,tried])
	quit(1 if failures else 0)
