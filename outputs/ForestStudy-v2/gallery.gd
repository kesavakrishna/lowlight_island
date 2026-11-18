extends Node3D

const NAMES := ["Shelfwood","Veil Banyan","Crown Fern","Tide Fern","Amethyst Rosette","Lantern Shelves","Canopy Crossing","Curtain Vine","Lantern Orchid","Mixed grove","Young Shelfwood","Arch Palm","Elephant Ear","Creeper Mat","Umbrella Fig","Tiered Copperwood","Leaning River Myrtle","Crest Palm","Giant Reed Bamboo","Brush Bamboo","Meadow Hairgrass","Rose Plume Grass","Bronze Seed Sedge","Marsh Rush","Silver Bank Grass","Forest Carpet","River Elephant Ear","Copper Bromeliad","Violet Shieldleaf","Lime Strapleaf","Blue Ripple Lily","Sword Fern","Bank Maidenhair","Tower Fern","Bedded Cliff Face","Moss Table Ledge","Fractured Twin Block","River Stair Outcrop","Shale Overhang","Waterworn Boulder","Mossback Boulder","Ford Stepping Slab","River Gravel Fan","Broken Talus"]
const HEIGHT := [33.0,22.0,14.0,3.4,3.5,2.8,19.0,5.8,2.1,38.0,6.5,11.0,2.4,1.2,15,19,8,9,12,5,1,.95,.95,1.6,1,1.1,1.6,1.4,1,1.6,1,2,1.2,2.5,2.4,2.6,2.2,2.3,2.3,2,2,2.3,2.2,2.3]
const GROVE := 9
var samples: Array[Node3D] = []
var camera := Camera3D.new()
var gallery := Node3D.new()
var heading := 0.55
var pitch := 0.16
var distance := 1.0
var focus := Vector3.ZERO
var selected := 0
var title := Label.new()
var sun := DirectionalLight3D.new()
var env := Environment.new()
var motes: MultiMeshInstance3D
var dusk := true

func _ready() -> void:
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	add_child(sun)
	sun.rotation_degrees = Vector3(-47,-28,0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 125
	lighting()
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(450,450)
	floor_mesh.mesh = plane
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color("#394a40")
	floor_mesh.material_override = ground
	floor_mesh.position.y = -0.05
	add_child(floor_mesh)
	add_child(camera)
	camera.fov = 43
	add_child(gallery)
	for i in range(NAMES.size()):
		if i == GROVE:
			samples.append(gallery)  # the mixed grove occupies this catalogue slot
			continue
		var doc := GLTFDocument.new()
		var data := GLTFState.new()
		var err := doc.append_from_file("res://models/"+NAMES[i]+".glb",data)
		if err != OK:
			push_error("Could not open "+NAMES[i])
			return
		var model := doc.generate_scene(data) as Node3D
		add_child(model)
		samples.append(model)
		model.hide()
	build_grove(floor_mesh)
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16,16)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	column.add_child(title)
	title.add_theme_font_size_override("font_size",22)
	var row := HBoxContainer.new()
	column.add_child(row)
	for i in range(NAMES.size()):
		if i == 6 or i == 10 or (i >= 14 and (i-14)%6 == 0):
			row = HBoxContainer.new()
			column.add_child(row)
		var button := Button.new()
		button.text = NAMES[i]
		button.pressed.connect(select.bind(i))
		row.add_child(button)
	var walk_button := Button.new()
	walk_button.text = "Walk the canopy"
	walk_button.pressed.connect(start_walk)
	row.add_child(walk_button)
	hint = Label.new()
	hint.text = "Drag to orbit   •   Wheel to zoom   •   Right-drag to pan   •   N for daylight / moonlight   •   1–7 to select"
	column.add_child(hint)
	select(9)

func lighting() -> void:
	if motes != null:
		motes.visible = dusk
	env.background_color = Color("#294652") if dusk else Color("#a8c4c5")
	env.fog_light_color = env.background_color
	env.fog_density = 0.009 if dusk else 0.002
	env.ambient_light_color = Color("#b1cbd6") if dusk else Color("#dae6e1")
	env.ambient_light_energy = 0.61 if dusk else 0.76
	sun.light_color = Color("#93bbdf") if dusk else Color("#fff0cf")
	sun.light_energy = 0.68 if dusk else 1.05

func select(i: int) -> void:
	stop_walk()
	selected = i
	for j in range(samples.size()):
		samples[j].visible = i == j
	gallery.visible = i == 9
	title.text = NAMES[i]
	hint.text = "Drag to orbit   •   Wheel to zoom   •   Right-drag to pan   •   N for lighting   •   Tab to walk the grove"
	distance = HEIGHT[i]*(1.9 if i==9 else 2.12)
	focus = Vector3.UP*HEIGHT[i]*(0.36 if i==9 else (0.29 if i>=3 else 0.50))
	if i == 6:
		focus = Vector3(0,6.4,0)
	elif i == 7:
		focus = Vector3(3,-1.6,0)
	if i == 11:
		focus = Vector3(1.4,HEIGHT[i]*0.5,0)
	pitch = 0.18 if (i<3 or i==10 or i==11) else 0.34
	position_camera()

func position_camera() -> void:
	if walking:
		return
	camera.position = focus + Vector3(sin(heading)*cos(pitch),sin(pitch),cos(heading)*cos(pitch))*distance
	camera.look_at(focus)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			if walking:
				select(9)
			else:
				start_walk()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and walking:
			select(9)
			get_viewport().set_input_as_handled()
			return
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			select(event.keycode-KEY_1)
		elif event.keycode == KEY_N:
			dusk = not dusk
			lighting()
	elif event is InputEventMouseMotion:
		if walking:
			body.rotate_y(-event.relative.x*0.0024)
			camera.rotation.x = clampf(camera.rotation.x-event.relative.y*0.0024,-1.4,1.4)
			return
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			heading -= event.relative.x*0.009
			pitch = clampf(pitch+event.relative.y*0.006,-0.12,1.38)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			focus += (camera.basis.y*event.relative.y-camera.basis.x*event.relative.x)*distance*0.001
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(0.24,distance*0.85)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(165,distance/0.85)
	position_camera()

var hint: Label
var body := CharacterBody3D.new()
var walking := false

func place(kind: int, pos: Vector3, angle := 0.0, size := 1.0) -> Node3D:
	var model := samples[kind].duplicate() as Node3D
	gallery.add_child(model)
	model.position = pos
	model.rotation.y = angle
	model.scale = Vector3.ONE*size
	model.show()
	return model

func bridge_point(t: float) -> Vector3:
	return Vector3(-14+28*t,6.2+0.85*sin(t*TAU),0.55*sin(t*TAU))

func build_grove(floor_mesh: MeshInstance3D) -> void:
	floor_mesh.create_trimesh_collision()
	var bridge := place(6,Vector3.ZERO)
	for part in bridge.find_children("*","MeshInstance3D",true,false):
		part.create_trimesh_collision()
	for i in range(3):
		var p := bridge_point(i*0.5)
		place(i%2,Vector3(p.x,0,p.z-1.8),0.6+i*1.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 207
	for i in range(245):
		var kind: int = i%3 if i<22 else [3,3,4,5,8,8][i%6]
		var radius := sqrt(rng.randf())*24.0
		var angle := i*2.39996
		var pos := Vector3(cos(angle)*radius,0,sin(angle)*radius)
		if kind<3 and absf(pos.z)<4 and absf(pos.x)<17:
			pos.z += 7.0
		place(kind,pos,angle,rng.randf_range(0.68,1.12))
	for k in range(7):
		var a := bridge_point(k/7.0)
		var b := bridge_point((k+1)/7.0)
		a.z += 0.84
		b.z += 0.84
		var vine := place(7,a)
		vine.basis = Basis((b-a)/6.0,Vector3.UP,Vector3.BACK)
	# Jungle additions: saplings and palms in the gaps, broad leaves and creepers on the floor.
	for i in range(150):
		var kind: int = [10,10,11,12,12,13,13,13][i%8]
		var radius := sqrt(rng.randf())*25.0
		var angle := rng.randf()*TAU
		var pos := Vector3(cos(angle)*radius,0,sin(angle)*radius)
		if kind == 11 and radius < 15.0:
			pos *= 18.0/maxf(radius,0.1)  # palms at the grove edge
		place(kind,pos,rng.randf()*TAU,rng.randf_range(0.75,1.15))
	for k in range(3):
		for j in range(9):
			var a := rng.randf()*TAU
			var d := rng.randf_range(1.8,4.2)
			place(8,Vector3((k-1)*14+cos(a)*d,0,-1.8+sin(a)*d),a)
	add_child(body)
	body.floor_snap_length = 0.32
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.27
	capsule.height = 1.68
	collider.shape = capsule
	collider.position.y = 0.84
	body.add_child(collider)
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14,0.14)
	batch.mesh = quad
	batch.instance_count = 52
	for i in range(batch.instance_count):
		var pos := Vector3(rng.randf_range(-20,20),rng.randf_range(.5,11.8),rng.randf_range(-14,14))
		batch.set_instance_transform(i,Transform3D(Basis.IDENTITY,pos))
	motes = MultiMeshInstance3D.new()
	motes.multimesh = batch
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	motes.extra_cull_margin = 2.0
	var material := ShaderMaterial.new()
	material.shader = preload("res://motes.gdshader")
	motes.material_override = material
	gallery.add_child(motes)

func start_walk() -> void:
	select(9)
	walking = true
	body.position = bridge_point(0.064)+Vector3.UP*1.5
	body.rotation.y = -PI/2
	body.velocity = Vector3.ZERO
	camera.reparent(body,false)
	camera.position = Vector3.UP*1.52
	camera.rotation = Vector3(-0.16,0,0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hint.text = "WASD to walk   •   Mouse to look   •   R to return to the branch   •   N for lighting   •   Esc for orbit"

func stop_walk() -> void:
	if walking:
		walking = false
		camera.reparent(self,false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	if not walking:
		return
	if Input.is_physical_key_pressed(KEY_R) or body.position.y < -5:
		start_walk()
		return
	var move := Vector3(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),0,float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	walk_step(move,delta)

func walk_step(move: Vector3,delta: float) -> void:
	var v := body.basis*move.normalized()*3.2
	body.velocity = Vector3(v.x,body.velocity.y-18.0*delta,v.z)
	body.move_and_slide()