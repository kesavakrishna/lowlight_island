extends Node
## Low-Nerve effects for the LOCAL player only (LOWLIGHT_ISLAND.md §6a).
## The host owns the Nerve value; this node only reads it. Hallucinations live
## entirely on this client and never reach other players or the host.
##
## Fairness: hallucinations never imitate a critical warning (bark scraping, a door
## under pressure, the final moments of a breach, the lantern's creature flicker or any
## on-screen direction arrow). They use phantom footsteps, distant calls from the wrong
## direction, a silhouette in the tree line and a shape crossing the edge of the beam.

const Geo = preload("res://src/world/geo.gd")

var player: Node = null
var match_ref: Node = null
var _breath: AudioStreamPlayer
var _next_hallucination := 12.0
var _rng := RandomNumberGenerator.new()
var _phantom: Node3D
var _phantom_t := 0.0
var _beam_shape: Node3D
var _beam_t := 0.0


func _ready() -> void:
	_rng.randomize()
	_breath = AudioStreamPlayer.new()
	if Sfx.enabled:
		_breath.stream = Sfx.streams.get("breath")
	_breath.volume_db = -40.0
	add_child(_breath)
	if _breath.stream:
		_breath.play()
	_phantom = _silhouette(Color(0.02, 0.02, 0.025))
	_beam_shape = _silhouette(Color(0.01, 0.01, 0.01))


func _silhouette(col: Color) -> Node3D:
	var n := Node3D.new()
	var m := Geo.mat(col, 0.9)
	Geo.mesh(n, _capsule(0.22, 1.5), Transform3D(Basis.IDENTITY, Vector3(0, 1.3, 0)), m, false)
	Geo.sphere(n, 0.16, Vector3(0, 2.15, -0.05), m, Vector3(0.8, 0.9, 1.3), false)
	Geo.rod(n, Vector3(0.3, 1.9, 0), Vector3(0.4, 0.5, -0.2), 0.05, m, false)
	Geo.rod(n, Vector3(-0.3, 1.9, 0), Vector3(-0.4, 0.5, -0.2), 0.05, m, false)
	n.top_level = true
	n.visible = false
	add_child(n)
	return n


func low() -> float:
	## 0 when steady, 1 at rock bottom.
	return clampf(1.0 - player.nerve / Tuning.nerve_max, 0.0, 1.0)


func _process(delta: float) -> void:
	if player == null or match_ref == null:
		return
	var l := low()
	# Breathing you can hear yourself; below a threshold the host also makes it audible to creatures.
	if _breath.stream:
		_breath.volume_db = lerpf(-40.0, -6.0, smoothstep(0.4, 0.95, l))
		_breath.pitch_scale = lerpf(0.9, 1.25, l)
	# Shaky light: the beam wavers as nerve goes.
	if player.spot:
		var wob := smoothstep(0.35, 1.0, l) * 0.06
		var t := Time.get_ticks_msec() / 1000.0
		player.spot.rotation = Vector3(sin(t * 7.3) * wob + sin(t * 13.1) * wob * 0.5, cos(t * 6.1) * wob, 0)
	_tick_phantoms(delta)
	if player.nerve > Tuning.nerve_hallucinate_below or player.mode != 0:
		_next_hallucination = maxf(_next_hallucination, 6.0)
		return
	_next_hallucination -= delta * (0.5 + l)
	if _next_hallucination <= 0.0:
		_next_hallucination = _rng.randf_range(9.0, 22.0)
		_hallucinate()


func _hallucinate() -> void:
	var eye: Vector3 = player.eye_position()
	var fwd: Vector3 = player.look_dir()
	fwd.y = 0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0, fwd.x)
	match _rng.randi() % 4:
		0:
			# Phantom footsteps behind you.
			var p := eye - fwd * _rng.randf_range(6.0, 12.0) + right * _rng.randf_range(-4.0, 4.0)
			for i in 3:
				get_tree().create_timer(i * 0.45).timeout.connect(func() -> void: Sfx.play_3d("creature_step", p, -8.0, 0.9, 30.0))
		1:
			# A silhouette standing in the tree line, gone when you look properly.
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var p2 := eye + fwd * _rng.randf_range(22.0, 32.0) + right * side * _rng.randf_range(8.0, 14.0)
			p2.y = match_ref.world.ground_y(p2)
			_phantom.global_position = p2
			_phantom.look_at(Vector3(eye.x, p2.y, eye.z), Vector3.UP)
			_phantom.visible = true
			_phantom_t = 1.6
		2:
			# A shape slipping across the edge of the beam (only if the lantern is open).
			if player.lantern_open:
				var p3 := eye + fwd * 9.0 + right * 3.2
				p3.y = match_ref.world.ground_y(p3)
				_beam_shape.global_position = p3
				_beam_shape.look_at(Vector3(eye.x, p3.y, eye.z), Vector3.UP)
				_beam_shape.visible = true
				_beam_t = 0.35
		3:
			# A call from the wrong direction: distant and quieter than a real one.
			var away := -fwd.rotated(Vector3.UP, _rng.randf_range(-0.8, 0.8)) * 45.0
			Sfx.play_3d("call", eye + away, -10.0, _rng.randf_range(0.85, 1.1), 200.0)


func _tick_phantoms(delta: float) -> void:
	if _phantom.visible:
		_phantom_t -= delta
		var to: Vector3 = (_phantom.global_position - player.eye_position()).normalized()
		# Vanishes when stared at, or after a moment.
		if _phantom_t <= 0.0 or player.look_dir().dot(to) > 0.985:
			_phantom.visible = false
	if _beam_shape.visible:
		_beam_t -= delta
		_beam_shape.global_position += Vector3(-player.look_dir().z, 0, player.look_dir().x) * delta * 9.0
		if _beam_t <= 0.0:
			_beam_shape.visible = false


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c
