extends SceneTree

func _initialize():
	call_deferred("run")

func run():
	var layouts := {}
	var climbed := {}
	var render := "--pictures" in OS.get_cmdline_user_args()
	for attempt in range(40):
		var g = load("res://island.tscn").instantiate()
		root.add_child(g)
		await physics_frame
		await physics_frame
		for site in g.perches:
			if site.kind not in g.CANOPY or climbed.has(site.kind): continue
			g.player.position=site.base+Vector3.UP*.05
			g.perch=null
			g.interact()
			if g.perch!=site: continue
			while not g.climb_path.is_empty(): g.advance_climb(.25)
			g.player.velocity=Vector3.ZERO
			for frame in range(16):
				await physics_frame
				g.player.velocity.y-=.30
				g.player.move_and_slide()
			if not g.player.is_on_floor() or g.player.position.distance_to(site.seat)>.58:
				push_error("Unusable landing on "+site.kind)
				quit(1)
				return
			climbed[site.kind]=true
			print("PASS crown landing ",site.kind)
		if not layouts.has(g.landscape):
			var count_ok: bool = g.swamps.size()>=4 if g.landscape==g.Landscape.WETLAND else g.swamps.size()==2
			var lip: float = -(g.river_origin(-1)+g.fall_distance)
			var drop: float = g.river_level(lip)-g.river_level(lip-2)
			if not count_ok or g.waters.size()!=g.swamps.size()+3 or ((drop>3.0)!=(g.landscape==g.Landscape.GORGE)):
				push_error("Basin and stream geometry disagree with the selected landscape")
				quit(1)
				return
			for step in range(-int(g.SHORE_RADIUS)+3,114,2):
				var point: Vector3=g.axis*step
				if g.swamp_weight(point)>.15 or g.ground_grade(point)>.91:
					push_error("Battery route crosses a basin or steep slope")
					quit(1)
					return
			var title: String=["Lake","Wetland","Gorge","Grassland"][g.landscape]
			print("PASS generated ",title," basins ",g.basin_sizes," waterfall drop ",g.fall_height)
			if render:
				g.hud.get_parent().hide()
				g.set_process(false)
				g.set_physics_process(false)
				var bank: Vector3=g.swamps[0]+Vector3.RIGHT*g.basin_sizes[0].x*1.09
				var target: Vector3=g.swamps[0]
				if title=="Gorge":
					var v: float=-(g.river_origin(-1)+g.fall_distance+14)
					bank=g.axis*(g.river_center(v)+10)+g.side*v
					v+=13
					target=g.axis*g.river_center(v)+g.side*v
					target.y=g.river_level(v)+1
				elif title=="Grassland":
					bank=g.axis*g.meadow_center.x+g.side*g.meadow_center.y
					target=bank+g.axis*45
				bank.y=g.ground_surface_height(bank)
				g.player.position=bank
				g.camera.look_at(target+Vector3.UP,Vector3.UP)
				for clock in [38.,83.,194.]:
					g.time=clock
					g.update_light(clock)
					for frame in range(3): await RenderingServer.frame_post_draw
					var path: String="res://"+title+("-dawn" if clock==38 else ("-day" if clock==83 else "-night"))+".png"
					if root.get_texture().get_image().save_png(path)!=OK:
						quit(1)
						return
			layouts[g.landscape]=true
		g.free()
		if layouts.size()==4 and climbed.size()==4:
			quit()
			return
	quit(1)
