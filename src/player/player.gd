extends CharacterBody3D
## One survivor. The host simulates every avatar from input intent; the owning client
## predicts its own movement with the same `simulate()` and reconciles to host state.
## Other clients interpolate snapshots.

const D = preload("res://src/core/defs.gd")
const Geo = preload("res://src/world/geo.gd")

var peer_id := 0
var display_name := ""
var slot := 0
var is_local := false
var is_server := false

# ---- authoritative state (host) / replicated state (clients)
var yaw := 0.0
var pitch := 0.0
var stance: int = D.Stance.STAND
var mode: int = D.Mode.NORMAL
var stamina := 100.0
var lantern_open := false
var noisemakers := 2
var sprinting := false
var moving := false
var tree_id := -1
var cover := ""
var inside_cave := false
var cave_id := -1
var speed_mult := 1.0            # terrain multiplier (wading), set before simulate()
var carrying := false            # the radio battery: no sprint, no climb, no prone, slower
var away := false                # connection dropped; the avatar waits for a reconnect
var grace := 0.0
var wood := 0
var nerve := 100.0               # host-owned; each client hallucinates only from its own value
var dragged_by := -1             # creature id dragging this downed player
var lean := 0.0                  # -1 left .. 1 right (peeking)
var resting := false             # resting in a dark shelter while someone keeps watch
var last_dry := Vector3.ZERO
var revive_progress := 0.0
var downed_time := 0.0

# ---- host-only simulation bookkeeping
var input_queue: Array = []
var last_input: Dictionary = {}
var last_seq := 0
var regen_timer := 0.0
var step_timer := 0.0
var branch_timer := 0.0
var climb: Dictionary = {}       # active climb {from, to, t, dur, target, tree}
var perch: String = ""           # "perch" | "canopy" | "partway" when PERCHED
var hang_timer := 0.0

# ---- client prediction
var seq := 0
var history: Dictionary = {}     # seq -> predicted position
var visual_offset := Vector3.ZERO
var last_err := 0.0

# ---- remote interpolation
var snaps: Array = []            # [time, pos, yaw, pitch]

# ---- nodes
var collider: CollisionShape3D
var visual: Node3D
var body_mesh: Node3D
var head: Node3D
var camera: Camera3D
var lantern_rig: Node3D
var spot: SpotLight3D
var glow: OmniLight3D
var name_label: Label3D
var _shapes: Dictionary = {}
var _glass: Node3D
var _shutter: Node3D
var _eye_h := 1.62
var _shake := 0.0
var _flicker := 0.0
var _foot_timer := 0.0
var _rng := RandomNumberGenerator.new()

const COLORS := [Color(0.75, 0.45, 0.25), Color(0.3, 0.5, 0.75), Color(0.45, 0.65, 0.35), Color(0.7, 0.6, 0.3)]


func setup(p_id: int, p_name: String, p_slot: int, p_local: bool, p_server: bool) -> void:
	peer_id = p_id
	display_name = p_name
	slot = p_slot
	is_local = p_local
	is_server = p_server
	name = str(p_id)
	noisemakers = Tuning.noisemakers_start
	stamina = Tuning.stamina_max


func _ready() -> void:
	_rng.seed = peer_id
	collision_layer = D.L_PLAYER
	collision_mask = D.L_WORLD
	floor_snap_length = 0.3
	for s in [D.Stance.STAND, D.Stance.CROUCH, D.Stance.PRONE]:
		var cap := CapsuleShape3D.new()
		cap.radius = Tuning.body_radius
		cap.height = _height_for(s)
		_shapes[s] = cap
	collider = CollisionShape3D.new()
	add_child(collider)
	_apply_shape()

	visual = Node3D.new()
	add_child(visual)
	body_mesh = Node3D.new()
	visual.add_child(body_mesh)
	var cloth := Geo.mat(COLORS[slot % COLORS.size()])
	var skin := Geo.mat(Color(0.62, 0.48, 0.38))
	Geo.mesh(body_mesh, _capsule(0.28, 1.15), Transform3D(Basis.IDENTITY, Vector3(0, 0.95, 0)), cloth)
	Geo.mesh(body_mesh, _capsule(0.12, 0.8), Transform3D(Basis.IDENTITY, Vector3(0.12, 0.4, 0)), Geo.mat(Color(0.2, 0.2, 0.22)))
	Geo.mesh(body_mesh, _capsule(0.12, 0.8), Transform3D(Basis.IDENTITY, Vector3(-0.12, 0.4, 0)), Geo.mat(Color(0.2, 0.2, 0.22)))

	Geo.sphere(body_mesh, 0.15, Vector3(0, 1.66, 0.02), skin)
	head = Node3D.new()
	head.position = Vector3(0, Tuning.eye_stand, 0)
	visual.add_child(head)

	lantern_rig = Node3D.new()
	lantern_rig.position = Vector3(0.3, -0.34, -0.62) if is_local else Vector3(0.3, -0.45, -0.25)
	head.add_child(lantern_rig)
	var frame := Geo.mat(Color(0.22, 0.2, 0.17), 0.5)
	Geo.box(lantern_rig, Vector3(0.1, 0.02, 0.1), Vector3(0, 0.07, 0), frame, 0)
	Geo.box(lantern_rig, Vector3(0.1, 0.02, 0.1), Vector3(0, -0.07, 0), frame, 0)
	Geo.box(lantern_rig, Vector3(0.012, 0.06, 0.012), Vector3(0, 0.11, 0), frame, 0)
	_glass = Node3D.new()
	lantern_rig.add_child(_glass)
	Geo.box(_glass, Vector3(0.075, 0.11, 0.075), Vector3.ZERO, Geo.mat(Color(0.9, 0.7, 0.42), 0.3, Color(1.0, 0.7, 0.35), 0.8), 0)
	_shutter = Node3D.new()
	lantern_rig.add_child(_shutter)
	Geo.box(_shutter, Vector3(0.085, 0.125, 0.085), Vector3.ZERO, Geo.mat(Color(0.3, 0.27, 0.22), 0.6), 0)
	spot = SpotLight3D.new()
	spot.light_color = Color(1.0, 0.86, 0.62)
	spot.spot_range = Tuning.lantern_range
	spot.spot_angle = Tuning.lantern_angle
	spot.spot_angle_attenuation = 1.4
	spot.spot_attenuation = 0.55
	spot.light_energy = 7.0
	spot.shadow_enabled = true
	spot.position = Vector3(0, 0, -0.08)
	lantern_rig.add_child(spot)
	glow = OmniLight3D.new()
	glow.light_color = Color(1.0, 0.8, 0.55)
	glow.omni_range = 3.5
	glow.light_energy = 0.5
	glow.shadow_enabled = false
	lantern_rig.add_child(glow)

	if is_local:
		camera = Camera3D.new()
		camera.fov = Settings.fov
		camera.near = 0.05
		camera.far = 400.0
		head.add_child(camera)
		camera.current = true
		Settings.changed.connect(func() -> void: camera.fov = Settings.fov)
		for c in body_mesh.get_children():
			if c is GeometryInstance3D:
				c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	else:
		name_label = Label3D.new()
		name_label.text = display_name
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.font_size = 28
		name_label.pixel_size = 0.004
		name_label.modulate = Color(1, 1, 1, 0.55)
		name_label.position = Vector3(0, 2.05, 0)
		name_label.no_depth_test = false
		visual.add_child(name_label)
	_update_lantern_visual(0.0)


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 10
	c.rings = 4
	return c


func _height_for(s: int) -> float:
	match s:
		D.Stance.CROUCH: return Tuning.crouch_height
		D.Stance.PRONE: return Tuning.prone_height
	return Tuning.stand_height


func eye_height() -> float:
	if mode == D.Mode.DOWNED:
		return Tuning.eye_prone
	match stance:
		D.Stance.CROUCH: return Tuning.eye_crouch
		D.Stance.PRONE: return Tuning.eye_prone
	return Tuning.eye_stand


func eye_position() -> Vector3:
	return global_position + Vector3(0, eye_height(), 0)


## Sideways head offset from leaning; creatures see the exposure points move with it.
func lean_offset() -> Vector3:
	if absf(lean) < 0.01:
		return Vector3.ZERO
	return Vector3(cos(yaw), 0, -sin(yaw)) * lean * 0.45


func look_dir() -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0)) * Vector3.FORWARD


func _apply_shape() -> void:
	var cap: CapsuleShape3D = _shapes[stance]
	collider.shape = cap
	collider.position = Vector3(0, cap.height * 0.5, 0)


## Change stance if there is headroom. Lowering always succeeds.
func try_set_stance(s: int) -> void:
	if s == stance:
		return
	var dh := _height_for(s) - _height_for(stance)
	if dh > 0.0 and test_move(global_transform, Vector3(0, dh, 0)):
		return
	stance = s
	_apply_shape()


# ------------------------------------------------------------------ simulation (host + owner prediction)

func simulate(inp: Dictionary, delta: float) -> void:
	yaw = inp.get("yaw", yaw)
	pitch = inp.get("pitch", pitch)
	if mode == D.Mode.CLIMBING or mode == D.Mode.PERCHED or mode == D.Mode.ESCAPED or mode == D.Mode.CAPTURED or dragged_by >= 0:
		velocity = Vector3.ZERO
		return
	var want: int = inp.get("stance", D.Stance.STAND)
	if mode == D.Mode.DOWNED:
		want = D.Stance.PRONE
	elif carrying and want == D.Stance.PRONE:
		want = D.Stance.CROUCH   # the bulky battery doesn't fit under anything you'd crawl through
	try_set_stance(want)

	var mv := Vector2(inp.get("mx", 0.0), inp.get("my", 0.0)).limit_length(1.0)
	var dir := Basis(Vector3.UP, yaw) * Vector3(mv.x, 0, mv.y)
	var btn: int = inp.get("btn", 0)
	var wants_sprint := (btn & D.BTN_SPRINT) != 0 and stance == D.Stance.STAND and mode == D.Mode.NORMAL and mv.length() > 0.2 and not carrying
	if wants_sprint and stamina > 0.0 and (sprinting or stamina >= Tuning.sprint_min_to_start):
		sprinting = true
	else:
		sprinting = false

	var speed := Tuning.walk_speed
	if mode == D.Mode.DOWNED:
		speed = Tuning.downed_crawl_speed
	elif sprinting:
		speed = Tuning.sprint_speed
	elif stance == D.Stance.CROUCH:
		speed = Tuning.crouch_speed
	elif stance == D.Stance.PRONE:
		speed = Tuning.prone_speed
	if carrying:
		speed = minf(speed, Tuning.carry_speed)

	if sprinting:
		stamina = maxf(0.0, stamina - Tuning.sprint_drain * delta)
		regen_timer = Tuning.stamina_regen_delay
	else:
		regen_timer -= delta
		if regen_timer <= 0.0:
			stamina = minf(Tuning.stamina_max, stamina + Tuning.stamina_regen * delta)

	var target := dir * speed * speed_mult
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(target, Tuning.accel * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		if (btn & D.BTN_JUMP) != 0 and stance == D.Stance.STAND and mode == D.Mode.NORMAL and not carrying:
			velocity.y = Tuning.jump_velocity
		else:
			velocity.y = minf(velocity.y, 0.0)
	velocity.y -= Tuning.gravity * delta
	move_and_slide()
	moving = Vector2(velocity.x, velocity.z).length() > 0.4


# ------------------------------------------------------------------ client side

func apply_remote_snapshot(t: float, pos: Vector3, p_yaw: float, p_pitch: float) -> void:
	snaps.append([t, pos, p_yaw, p_pitch])
	while snaps.size() > 30:
		snaps.pop_front()


## Owning client: correct prediction against the host position for an acknowledged input.
func reconcile(ack: int, server_pos: Vector3) -> void:
	last_err = 0.0
	if mode == D.Mode.CLIMBING or mode == D.Mode.PERCHED:
		history.clear()   # position follows interpolated host state while climbing
		return
	if not history.has(ack):
		if (server_pos - global_position).length() > 3.0:
			global_position = server_pos
			history.clear()
		return
	var err: Vector3 = server_pos - history[ack]
	last_err = err.length()
	for k in history.keys():
		if k <= ack:
			history.erase(k)
	if err.length() > 3.0:
		global_position = server_pos
		history.clear()
		visual_offset = Vector3.ZERO
	elif err.length() > 0.02:
		global_position += err
		for k in history.keys():
			history[k] += err
		visual_offset -= err
		visual_offset = visual_offset.limit_length(1.0)


func interpolate(render_time: float) -> void:
	if snaps.is_empty():
		return
	var a: Array = snaps[0]
	var b: Array = snaps[0]
	for i in range(snaps.size() - 1, -1, -1):
		if snaps[i][0] <= render_time:
			a = snaps[i]
			b = snaps[mini(i + 1, snaps.size() - 1)]
			break
	var span: float = b[0] - a[0]
	var f := 0.0 if span <= 0.0001 else clampf((render_time - a[0]) / span, 0.0, 1.0)
	var new_pos: Vector3 = a[1].lerp(b[1], f)
	moving = (new_pos - global_position).length() > 0.01
	global_position = new_pos
	yaw = lerp_angle(a[2], b[2], f)
	pitch = lerpf(a[3], b[3], f)


func add_shake(amount: float) -> void:
	_shake = clampf(_shake + amount * Settings.camera_shake, 0.0, 1.0)


func set_flicker(strength: float) -> void:
	_flicker = strength


# ------------------------------------------------------------------ visuals

func _process(delta: float) -> void:
	visual_offset = visual_offset.lerp(Vector3.ZERO, clampf(delta * 10.0, 0.0, 1.0))
	visual.position = visual_offset
	visual.rotation.y = yaw
	var gone := mode == D.Mode.ESCAPED or mode == D.Mode.CAPTURED
	visual.visible = not gone
	collider.disabled = gone
	var target_eye := eye_height()
	_eye_h = lerpf(_eye_h, target_eye, clampf(delta * 10.0, 0.0, 1.0))
	head.position.y = _eye_h
	head.rotation.x = pitch
	# Body pose by stance.
	var lying := stance == D.Stance.PRONE or mode == D.Mode.DOWNED
	body_mesh.rotation.x = lerpf(body_mesh.rotation.x, -PI * 0.5 if lying else 0.0, clampf(delta * 8.0, 0.0, 1.0))
	body_mesh.position.y = 0.3 if lying else 0.0
	body_mesh.scale.y = 0.7 if stance == D.Stance.CROUCH and not lying else 1.0
	if name_label:
		name_label.text = display_name + ("  (reconnecting)" if away else "")
		name_label.position.y = 0.9 if lying else 2.05
		name_label.modulate = Color(1, 0.4, 0.3, 0.8) if mode == D.Mode.DOWNED else Color(1, 1, 1, 0.55)
	_update_lantern_visual(delta)
	if camera:
		_shake = maxf(0.0, _shake - delta * 1.8)
		var s := _shake * _shake * 0.12
		camera.h_offset = _rng.randf_range(-s, s)
		camera.v_offset = _rng.randf_range(-s, s)
	_footsteps(delta)


func _update_lantern_visual(delta: float) -> void:
	var on := lantern_open and mode != D.Mode.DOWNED
	var energy := 7.0
	if _flicker > 0.0 and on:
		# Real warning from host state: a creature is near.
		var n := _rng.randf()
		if n < 0.25 * _flicker:
			energy *= _rng.randf_range(0.05, 0.5)
	spot.visible = on
	glow.visible = on
	spot.light_energy = energy
	glow.light_energy = energy * 0.09
	_glass.visible = on
	_shutter.visible = not on
	lantern_rig.visible = on or not is_local


func _footsteps(delta: float) -> void:
	if not Sfx.enabled or mode == D.Mode.CLIMBING or mode == D.Mode.PERCHED:
		return
	var spd := Vector2(velocity.x, velocity.z).length() if (is_local or is_server) else (1.0 if moving else 0.0)
	if not moving or spd < 0.3:
		_foot_timer = 0.0
		return
	var interval := 0.5
	var vol := -8.0
	var snd := "step"
	if sprinting:
		interval = 0.3
		vol = -2.0
	elif stance == D.Stance.CROUCH:
		interval = 0.65
		vol = -18.0
		snd = "step_soft"
	elif stance == D.Stance.PRONE or mode == D.Mode.DOWNED:
		interval = 0.9
		vol = -22.0
		snd = "rustle"
	_foot_timer -= delta
	if _foot_timer <= 0.0:
		_foot_timer = interval
		if cover == "grass":
			Sfx.play_3d("rustle", global_position, vol + 2.0, _rng.randf_range(0.9, 1.2), 25.0)
		Sfx.play_3d(snd, global_position, vol, _rng.randf_range(0.85, 1.15), 30.0)
