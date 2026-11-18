extends SceneTree
# Stage 3 check for LowlightIsland-v2: the same creature/player setup is spotted in the open
# but not at the same distance deep under a jungle canopy; and the shade darkens the light.
var failures := 0

func _initialize(): call_deferred("test")

func check(ok: bool, name: String) -> void:
	print(("PASS " if ok else "FAIL ")+name)
	if not ok:
		failures += 1

# Stand the creature 15 m away, facing the player with clear sight, and run detection for 2 s.
func spotted(g, spot: Vector3, away: Vector3) -> bool:
	g.player.position = spot
	g.player.position.y = g.elevation(spot)+0.05
	g.creature.position = spot+away*15.0
	g.creature.position.y = g.elevation(g.creature.position)
	g.creature.look_at(Vector3(spot.x,g.creature.position.y,spot.z))
	g.detection = 0.0
	g.chase = false
	g.light.visible = false
	g.crouched = false
	for i in range(120):
		# Re-aim each step; stays put because the goal is the player and we reset position.
		g.creature.position = spot+away*15.0
		g.creature.position.y = g.elevation(g.creature.position)
		g.creature.look_at(Vector3(spot.x,g.creature.position.y,spot.z))
		g.update_creature(1.0/60.0,false)
	return g.chase

func test():
	var tested := 0
	for run in range(6):
		var g = load("res://island.tscn").instantiate()
		root.add_child(g)
		await physics_frame
		g.time = 80.0
		for patch in g.jungles:
			var center := Vector3(patch.x,0,patch.z)
			# Deep spot: centre of the patch. Direction with clear line of sight, else skip.
			var deep := center
			deep.y = g.elevation(deep)+0.05
			if g.canopy_cover(deep) < 0.9:
				continue
			for k in range(12):
				var away := Vector3.RIGHT.rotated(Vector3.UP,TAU*k/12.0)
				var eye := deep+away*15.0
				eye.y = g.elevation(eye)+1.91
				if g.blocked(eye,deep+Vector3.UP*1.6,5):
					continue
				var open_spot := Vector3(0,0,0)
				var hidden_ok: bool = not spotted(g,deep,away)
				# Same geometry in open grassland near the battery field.
				var open_ok: bool = spotted(g,g.field+g.side*3.0,away)
				check(hidden_ok and open_ok,"15 m away: spotted in the open, not deep under canopy (island %d)" % run)
				tested += 1
				break
			break
		# Shade lowers the light.
		g.player.position = g.field
		g.canopy_shade = 0.0
		g.update_light(80.0)
		var open_sun: float = g.sun.light_energy
		var open_ambient: float = g.atmosphere.ambient_light_energy
		g.canopy_shade = 1.0
		g.update_light(80.0)
		check(g.sun.light_energy < open_sun*0.6 and g.atmosphere.ambient_light_energy < open_ambient*0.7,"canopy shade dims sun and ambient (island %d)" % run)
		g.queue_free()
		await process_frame
	check(tested >= 2,"tested stealth on at least two islands (%d)" % tested)
	quit(1 if failures else 0)
