extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("check_run")

func check(condition: bool, name: String) -> void:
	if condition:
		print("PASS ", name)
	else:
		failures += 1
		push_error("FAIL " + name)

func check_run() -> void:
	for attempt in range(3):
		var game = load("res://island.tscn").instantiate()
		root.add_child(game)
		await physics_frame
		await physics_frame
		check(game.blocked(Vector3.UP*2,Vector3.DOWN*0.9), "terrain is walkable")
		var ridge: Vector3 = game.ridges[1]
		check(game.elevation(ridge) > 12 and game.blocked(Vector3(ridge.x,36,ridge.z),Vector3(ridge.x,10,ridge.z),8), "raised hills have terrain collision")
		var route_open := true
		for step in range(-88,80,2):
			if game.ground_grade(game.axis*step) > 0.91:
				route_open = false
		check(route_open, "main route avoids cliffs")
		var saplings := 0
		var close_grove := false
		for a in game.tree_sites:
			if not is_equal_approx(a.y,1.7):
				continue
			saplings += 1
			for p in game.perches:
				if Vector2(a.x,a.z).distance_to(Vector2(p.trunk.x,p.trunk.z)) < 0.05:
					saplings = -500
			for b in game.tree_sites:
				var separation: float = Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))
				if separation > 0.1 and separation < 2.8:
					close_grove = true
		check(saplings > 4 and close_grove, "very small trees have no perches and form tight groves")
		game.player.position = game.bushes[0]
		check(game.foliage_hidden(), "bush is a usable concealment spot")
		game.time = 69.0
		game.update_light()
		var bright: float = game.sun.light_energy
		var high_sun: Vector3 = -game.sun.basis.z
		game.time = 138.0
		game.update_light()
		check(game.sun.light_energy < bright and (-game.sun.basis.z).distance_to(high_sun) > 0.1,"sun moves and fades at dusk")
		game.time = 192.0
		game.update_light()
		check(not game.sun.visible and game.moon.visible, "night uses moonlight")
		game.time = 279.0
		game.update_light()
		check(game.sun.visible and not game.moon.visible, "sunlight recovers after dawn")
		game.time = 0.0
		var marsh: Vector3 = game.swamps[0]
		check(game.blocked(marsh + Vector3.UP,marsh+Vector3.DOWN*0.82)
				and not game.blocked(marsh + Vector3.UP,marsh+Vector3.DOWN*0.22), "marsh has a submerged floor")
		var rock: MeshInstance3D = get_nodes_in_group("rocks")[0]
		check(game.blocked(rock.position+Vector3.UP*22,rock.position), "rock top blocks collision")
		var start := Transform3D(Basis.IDENTITY,rock.position+Vector3.UP*20)
		check(game.player.test_move(start, Vector3.DOWN*21), "player capsule collides with rock")
		check(not game.blocked(game.cave+Vector3(0,1,-4),game.cave+Vector3(0,1,1)), "cave has usable interior")
		game.player.position = game.supply_spot
		game.interact()
		check(game.wood == 4, "collect planks")
		var tree = game.perches[0]
		game.player.position = tree.base
		game.interact()
		while not game.climb_path.is_empty():
			game.advance_climb(0.25)
		check(game.perch == tree and game.player.position.is_equal_approx(tree.seat), "climb a regular tree")
		game.build_branch_platform()
		check(tree.platform != null and game.wood == 2, "build branch platform")
		game.player.position = tree.seat - tree.heading*0.46
		game.player.look_at(game.player.position+tree.heading*4)
		game.camera.rotation.x = -1.0
		game.screen_angle = game.player.rotation.y
		game.placing_screen = true
		await physics_frame
		game.interact()
		check(game.wood == 1 and not game.placing_screen, "aim and place a screen on a branch platform")
		game.placing_screen = false
		game.climb_higher()
		while not game.climb_path.is_empty():
			game.advance_climb(0.25)
		check(game.perch == tree.higher and game.player.position.y > 18, "climb into giant tree canopy")
		game.interact()
		while not game.climb_path.is_empty():
			game.advance_climb(0.25)
		check(game.perch == null and game.player.position.is_equal_approx(tree.base), "descend to ground")
		game.player.position = game.cave
		game.interact()
		game.interact()
		check(game.door.visible, "build and close the cave door")
		game.interact()
		game.player.position = game.battery.position
		game.interact()
		game.player.position = game.radio + Vector3(0,0,1.6)
		game.interact()
		check(game.powered and not game.carrying, "recover the battery and power the radio")
		tree = game.landmark_perch
		game.player.position = tree.base
		game.time = 180.0
		game.creature.show()
		game.creature.position = tree.base + game.axis*3.5
		game.creature.position.y = game.elevation(game.creature.position)
		game.chase = true
		game.interact()
		check(game.pursuing_perch == tree, "witnessed climb becomes an active pursuit")
		for i in range(460):
			if not game.climb_path.is_empty():
				game.advance_climb(1.0/60.0)
			game.update_creature(1.0/60.0,false)
			if game.creature_up:
				break
		check(game.creature_up and game.creature.position.y > 4, "creature reaches deck height")
		for i in range(240):
			if game.ended:
				break
			game.update_creature(1.0/60.0,false)
		check(game.ended and game.notice.text.contains("caught"), "creature can catch an exposed player on the deck")
		game.ended = false
		game.perch = tree
		game.player.position = tree.seat
		game.creature.position = tree.base
		game.pursuing_perch = null
		game.chase = true
		game.pursue_tree(tree)
		game.climb_higher()
		for i in range(900):
			if not game.climb_path.is_empty():
				game.advance_climb(1.0/60.0)
			game.update_creature(1.0/60.0,false)
			if game.ended:
				break
		check(game.ended and game.creature.position.y > 18, "creature catches exposed player at upper canopy")
		game.ended = false
		game.time = 260.0
		game.perch = null
		game.climb_path.clear()
		game.player.position = game.dock
		game.interact()
		check(game.ended and game.notice.text.begins_with("ESCAPED"), "escape at dawn")
		check(game.howl.stream != null and game.find_children("*","AudioStreamPlayer3D",true,false).size() == 1
				and game.find_children("*","AudioStreamPlayer",true,false).is_empty(), "only creature howls have an audio source")
		game.queue_free()
		await physics_frame
		await physics_frame
	quit(0 if failures == 0 else 1)
