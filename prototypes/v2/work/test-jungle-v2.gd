extends SceneTree
# Jungle checks for LowlightIsland-v2: patch variety per seed, and every jungle crossing is walkable.
var failures := 0

func _initialize(): call_deferred("test")

func walk(g, a: Vector3, b: Vector3) -> bool:
	var dir := (b-a)*Vector3(1,0,1)
	var along := dir.normalized()
	var across := along.cross(Vector3.UP)
	var start := 0.09
	g.player.position = a.lerp(b,start)+across*(0.55*sin(start*TAU))+Vector3.UP*(0.85*sin(start*TAU)+0.36)
	g.player.velocity = Vector3.ZERO
	for i in range(900):
		await physics_frame
		var t: float = (g.player.position-a).dot(along)/dir.length()
		if t > 0.90:
			return true
		var target := a.lerp(b,t+0.03)+across*0.55*sin((t+0.03)*TAU)
		var move: Vector3 = ((target-g.player.position)*Vector3(1,0,1)).normalized()*4.0
		g.player.velocity = move+Vector3.UP*(g.player.velocity.y-18/60.0)
		g.player.move_and_slide()
		if g.player.position.y < a.lerp(b,t).y-3:
			break
	print("  stuck at t=",(g.player.position-a).dot(along)/dir.length()," pos ",g.player.position)
	g.player.velocity = along*4.0
	g.player.move_and_slide()
	for i in range(g.player.get_slide_collision_count()):
		var c: KinematicCollision3D = g.player.get_slide_collision(i)
		var body: Node3D = c.get_collider()
		var mi := ""
		for ch in body.get_children():
			mi += ch.get_class()+" "
		print("   touching ",body.name," children [",mi,"] origin ",body.global_position," at ",c.get_position()," normal ",c.get_normal())
	for h in [0.3,0.9,1.5]:
		var q := PhysicsRayQueryParameters3D.create(g.player.position+Vector3.UP*h,g.player.position+Vector3.UP*h+along*1.5)
		q.exclude = [g.player.get_rid()]
		var hit: Dictionary = g.get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			var body: Node3D = hit.collider
			var shape := ""
			for c in body.get_children():
				if c is CollisionShape3D:
					shape = c.shape.get_class()
			var origin := body.global_position
			var nearest := INF
			var site_r := 0.0
			for s in g.tree_sites:
				var d := Vector2(s.x-origin.x,s.z-origin.z).length()
				if d < nearest:
					nearest = d
					site_r = s.y
			print("   blocked at +",h," m by ",body.name," ",shape," origin ",origin," nearest tree site ",nearest," m (site radius ",site_r,")")
	return false

func test():
	for run in range(6):
		var g = load("res://island.tscn").instantiate()
		root.add_child(g)
		await physics_frame
		var radii := []
		for j in g.jungles:
			radii.append(int(j.w))
		print("island ",run,": ",g.jungles.size()," jungle patches, radii ",radii,", ",g.jungle_bridges.size()," jungle crossings, ",g.tree_sites.size()," trees total, ",g.bushes.size()," cover plants")
		for span in g.jungle_bridges:
			var ok: bool = await walk(g,span[0],span[1])
			print("  crossing ",span[0].distance_to(span[1])," m: ","PASS" if ok else "FAIL")
			if not ok:
				failures += 1
		g.queue_free()
		await process_frame
	quit(1 if failures else 0)
