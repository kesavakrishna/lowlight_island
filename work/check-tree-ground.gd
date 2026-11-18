extends SceneTree

func _initialize():
	call_deferred("check")

func check():
	var game = load("res://island.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	await physics_frame
	var space = game.get_world_3d().direct_space_state
	var count := 0
	var probes := 0
	for node in game.get_children():
		if not node is MeshInstance3D:
			continue
		for kind in ["Shelfwood","Veil Banyan","Crown Fern"]:
			if node.mesh != game.flora[kind]:
				continue
			count += 1
			var contacts: PackedVector3Array = game.root_contacts[kind]
			if contacts.is_empty():
				push_error("Missing basal contacts")
				quit(1)
				return
			for j in range(0,contacts.size(),maxi(1,contacts.size()/24)):
				var p: Vector3 = node.transform*contacts[j]
				var q := PhysicsRayQueryParameters3D.create(p+Vector3.UP*50,p-Vector3.UP*50,8)
				var hit: Dictionary = space.intersect_ray(q)
				if hit.is_empty() or p.y>hit.position.y-0.055 or absf(game.ground_surface_height(p)-hit.position.y)>0.03:
					push_error("Base exposed or terrain height mismatched at "+str(p))
					quit(1)
					return
				probes += 1
	print("PASS planted bases on ",count," trees, ",probes," terrain collision probes")
	var tree = game.perches[0]
	var trunk: Vector3 = tree.trunk
	var start: Vector3 = trunk+game.side*4.5-game.axis*2.4
	game.player.position = start
	game.player.position.y = game.ground_surface_height(start)+0.12
	for i in range(135):
		await physics_frame
		game.player.velocity = game.axis*3.4+Vector3.UP*(game.player.velocity.y-18.0/60)
		game.player.move_and_slide()
		if (game.player.position-start).dot(game.axis)>4.8:
			print("PASS walked across the outer root zone of a giant without jumping")
			quit()
			return
	push_error("Outer root zone blocked")
	quit(1)
