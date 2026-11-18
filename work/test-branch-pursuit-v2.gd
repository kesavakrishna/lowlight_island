extends SceneTree
# Stage B checks for LowlightIsland-v2:
#  - the creature climbs and walks out along the player's branch to catch them
#  - it never floats off the tree: away from the trunk it is always heading along the player's branch
#  - a player on a different branch is still reached (via the trunk)
#  - a player who leaves the tree makes it climb back down and end the pursuit
#  - V builds a platform where the player stands; a screen fits on it; no second platform on the same spot
var failures := 0

func _initialize(): call_deferred("test")

func check(ok: bool, name: String) -> void:
	print(("PASS " if ok else "FAIL ")+name)
	if not ok:
		failures += 1

func walk_out(g, site, metres: float) -> void:
	g.player.position = site.seat
	g.player.velocity = Vector3.ZERO
	for i in range(int(metres/2.0*60.0)+20):
		await physics_frame
		var move: Vector3 = site.heading*2.0 if i < int(metres/2.0*60.0) else Vector3.ZERO
		g.player.velocity = Vector3(move.x,g.player.velocity.y-0.3,move.z)
		g.player.move_and_slide()
	g.perch = g.tree_perch_at(g.player.position)

# Run the chase; returns [caught, floated_frames, max_height_above_feet].
func chase(g, site) -> Array:
	g.ended = false
	g.creature.position = site.base+site.approach*4.0
	g.creature.position.y = g.elevation(g.creature.position)
	g.pursuing_perch = null
	g.creature_up = false
	g.chase = true
	g.investigate = 5.0
	g.pursue_tree(g.perch)
	var floated := 0
	var top := 0.0
	for i in range(60*40):
		g.update_creature(1.0/60.0,false)
		if g.ended:
			break
		var at: Array = g.trunk_at(site,g.creature.position.y)
		var c_out: Vector3 = (g.creature.position-at[0])*Vector3(1,0,1)
		var p_at: Array = g.trunk_at(site,g.player.position.y)
		var p_out: Vector3 = (g.player.position-p_at[0])*Vector3(1,0,1)
		if g.creature_up and c_out.length() > at[1]+1.2 and c_out.normalized().dot(p_out.normalized()) < 0.75:
			floated += 1
		top = maxf(top,g.creature.position.y-site.base.y)
	if floated > 0:
		print("  off-wood frames %d on %s (scale %.2f), creature %s player %s" % [floated,site.kind,site.pose.basis.x.length(),g.creature.position,g.player.position])
	return [g.ended and g.notice.text.contains("caught"),floated,top]

func test():
	var caught := 0
	var other_caught := 0
	var floats := 0
	var gave_up := 0
	var built := 0
	var screens := 0
	var palm_runs := 0
	var palm_caught := 0
	var trees := 0
	for run in range(3):
		var g = load("res://island.tscn").instantiate()
		root.add_child(g)
		await physics_frame
		await physics_frame
		g.time = 180.0
		g.creature.show()
		var used := 0
		# A palm: the creature climbs the trunk into the crown after you.
		for site in g.perches:
			if site.higher != null or palm_runs >= 2:
				continue
			palm_runs += 1
			g.player.position = site.seat
			g.perch = site
			g.climb_path.clear()
			var r: Array = await chase(g,site)
			if r[0]:
				palm_caught += 1
			else:
				print("  palm: not caught, creature at %s player %s" % [g.creature.position,g.player.position])
		for site in g.perches:
			if site == g.landmark_perch or site == g.perches[0] or site.higher == null or site.higher.limb_t < 0.0 or site.pose.basis.x.length() < 0.45:
				continue
			if used >= 3:
				break
			used += 1
			trees += 1
			# 1. Out on the low branch.
			await walk_out(g,site,1.6)
			var r: Array = await chase(g,site)
			if r[0]:
				caught += 1
			else:
				print("  low branch: not caught, creature at %s up=%s player %s" % [g.creature.position,g.creature_up,g.player.position])
			floats += r[1]
			# 2. Player on the high branch, creature already up on the low one.
			await walk_out(g,site.higher,1.0)
			g.ended = false
			g.creature.position = site.seat+site.heading*0.8
			g.creature_up = true
			g.pursuing_perch = site
			g.chase = true
			g.pursue_tree(g.perch)
			var ok := false
			for i in range(60*40):
				g.update_creature(1.0/60.0,false)
				if g.ended:
					ok = g.notice.text.contains("caught")
					break
			if ok:
				other_caught += 1
			else:
				print("  other branch: not caught, creature at %s player %s" % [g.creature.position,g.player.position])
			# 3. Player drops out of the tree; the creature climbs down and stops pursuing.
			g.ended = false
			g.creature.position = site.seat+site.heading*0.8
			g.creature_up = true
			g.pursuing_perch = site
			g.chase = false
			g.investigate = 0.0
			g.perch = null
			var away: Vector3 = site.trunk-site.heading*25.0
			away.y = g.elevation(away)
			g.player.position = away
			for i in range(60*30):
				g.update_creature(1.0/60.0,false)
				if g.pursuing_perch == null:
					break
			if g.pursuing_perch == null and g.creature.position.y < site.base.y+0.6:
				gave_up += 1
			else:
				print("  leave tree: still pursuing, creature at %s" % g.creature.position)
			# 4. Build where you stand, then a screen on it.
			await walk_out(g,site,1.4)
			g.wood = 4
			var before: int = g.branch_platforms.size()
			g.build_branch_platform()
			var second_blocked: bool = g.platform_spot() == null
			var made: bool = g.branch_platforms.size() == before+1 and g.wood == 2
			var platform: StaticBody3D = g.branch_platforms.back()
			await physics_frame
			g.player.position = platform.position+Vector3.UP*0.14-platform.basis.z*0.4
			g.player.look_at(g.player.position+platform.basis.z*4.0,Vector3.UP)
			g.camera.rotation.x = -1.0
			g.screen_angle = g.player.rotation.y
			g.placing_screen = true
			await physics_frame
			g.interact()
			if made and second_blocked:
				built += 1
			else:
				print("  build: made=%s second_blocked=%s" % [made,second_blocked])
			if g.wood == 1:
				screens += 1
			g.placing_screen = false
		g.queue_free()
		await physics_frame
	check(caught >= trees-1,"creature walks out along the branch and catches the player (%d/%d)" % [caught,trees])
	check(floats == 0,"creature never leaves the wood: frames off-branch %d" % floats)
	check(other_caught >= trees-1,"player on another branch is reached via the trunk (%d/%d)" % [other_caught,trees])
	check(gave_up == trees,"player leaving the tree ends the pursuit on the ground (%d/%d)" % [gave_up,trees])
	check(palm_runs > 0 and palm_caught == palm_runs,"creature climbs a palm into the crown after you (%d/%d)" % [palm_caught,palm_runs])
	check(built == trees,"V builds where you stand; no second platform on the same spot (%d/%d)" % [built,trees])
	check(screens*2 >= trees,"a screen fits on the new platform unless real branches are in the way (%d/%d)" % [screens,trees])
	quit(1 if failures else 0)
