extends SceneTree
func _initialize(): call_deferred("test")
func test():
	var g = load("res://island.tscn").instantiate()
	root.add_child(g)
	await physics_frame
	var a: Vector3 = g.perches[0].higher.seat
	var b: Vector3 = g.landmark_perch.higher.seat
	var dir := (b-a)*Vector3(1,0,1)
	var along := dir.normalized()
	var across := along.cross(Vector3.UP)
	var start := 0.09
	g.player.position = a.lerp(b,start)+across*(0.55*sin(start*TAU))+Vector3.UP*(0.85*sin(start*TAU)+0.36)
	for i in range(900):
		await physics_frame
		var t: float = (g.player.position-a).dot(along)/dir.length()
		if t>0.90:
			print("PASS player walked canopy crossing")
			quit()
			return
		var target := a.lerp(b,t+0.03)+across*0.55*sin((t+0.03)*TAU)
		var move: Vector3 = ((target-g.player.position)*Vector3(1,0,1)).normalized()*4.0
		g.player.velocity = move+Vector3.UP*(g.player.velocity.y-18/60.0)
		g.player.move_and_slide()
		if g.player.position.y < a.lerp(b,t).y-3:
			break
	print("a ",a," b ",b," player ",g.player.position," t ",(g.player.position-a).dot(along)/dir.length())
	push_error("Could not walk canopy crossing")
	quit(1)
