extends Node
## Procedural placeholder audio (autoload `Sfx`). Every cue is synthesized at startup
## so the prototype has distinct sounds before recorded audio exists. Replace streams
## in `streams` with recorded files later without touching call sites.

const RATE := 22050

var streams: Dictionary = {}
var enabled := true
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	enabled = DisplayServer.get_name() != "headless"
	if not enabled:
		return
	_rng.seed = 7
	streams["step"] = _wav(_thump(0.10, 85.0, 0.35, 0.12))
	streams["step_soft"] = _wav(_thump(0.08, 70.0, 0.18, 0.08))
	streams["creature_step"] = _wav(_thump(0.20, 50.0, 0.8, 0.25))
	streams["call"] = _wav(_call())
	streams["screech"] = _wav(_screech())
	streams["chitter"] = _wav(_chitter())
	streams["scrape"] = _wav(_scrape())
	streams["door_hit"] = _wav(_door_hit())
	streams["door_creak"] = _wav(_creak())
	streams["rattle"] = _wav(_rattle())
	streams["rustle"] = _wav(_rustle(0.35))
	streams["branch"] = _wav(_rustle(0.5, 0.6))
	streams["breach_warn"] = _wav(_growl())
	streams["down"] = _wav(_down())
	streams["rope"] = _wav(_rustle(0.9, 0.3))
	streams["wind"] = _wav(_wind(), true)
	streams["drone"] = _wav(_drone(), true)
	streams["breath"] = _wav(_breath(), true)


func play_3d(sound: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0, max_dist: float = 70.0) -> void:
	if not enabled or not streams.has(sound):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = max_dist
	p.unit_size = 5.0
	p.position = pos
	p.autoplay = true
	p.finished.connect(p.queue_free)
	get_tree().root.add_child.call_deferred(p)


func play_ui(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not enabled or not streams.has(sound):
		return
	var p := AudioStreamPlayer.new()
	p.stream = streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.autoplay = true
	p.finished.connect(p.queue_free)
	get_tree().root.add_child.call_deferred(p)


func make_loop(sound: String, volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if enabled and streams.has(sound):
		p.stream = streams[sound]
	p.volume_db = volume_db
	return p


# ------------------------------------------------------------------ synthesis helpers

func _wav(s: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


func _buf(dur: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(dur * RATE))
	return s


func _n() -> float:
	return _rng.randf_range(-1.0, 1.0)


func _thump(dur: float, freq: float, noise_amt: float, click: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var env := exp(-t * 38.0)
		lp += (_n() - lp) * 0.12
		var click_env := exp(-t * 400.0) * click
		s[i] = (sin(TAU * freq * t) * 0.7 + lp * noise_amt * 3.0) * env + _n() * click_env
	return s


func _call() -> PackedFloat32Array:
	var s := _buf(1.9)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var u := t / 1.9
		var f := lerpf(560.0, 240.0, u) * (1.0 + 0.025 * sin(TAU * 6.0 * t))
		phase += TAU * f / RATE
		var env := sin(PI * minf(u * 1.4, 1.0)) * (1.0 - u * 0.4)
		var v := sin(phase) * 0.5 + sin(phase * 2.01) * 0.22 + sin(phase * 3.03) * 0.12 + _n() * 0.08
		s[i] = v * env * 0.85
	return s


func _screech() -> PackedFloat32Array:
	var s := _buf(0.75)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var u := t / 0.75
		var f := lerpf(900.0, 1350.0, u)
		phase += TAU * f / RATE
		var saw := fmod(phase / TAU, 1.0) * 2.0 - 1.0
		var am := 0.6 + 0.4 * sin(TAU * 31.0 * t)
		var env := minf(u * 12.0, 1.0) * (1.0 - u)
		s[i] = (saw * 0.45 + _n() * 0.25) * am * env
	return s


func _chitter() -> PackedFloat32Array:
	var s := _buf(0.55)
	for i in s.size():
		var t := float(i) / RATE
		var k := fmod(t * 22.0, 1.0)
		var env := exp(-k * 18.0) * (1.0 - t / 0.55)
		s[i] = (_n() * 0.5 + sin(TAU * 2400.0 * t) * 0.3) * env * 0.6
	return s


func _scrape() -> PackedFloat32Array:
	var s := _buf(0.55)
	var a := 0.0
	var b := 0.0
	var grain := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var x := _n()
		a += (x - a) * 0.35
		b += (x - b) * 0.05
		if i % 300 == 0:
			grain = _rng.randf_range(0.3, 1.0)
		var env := sin(PI * t / 0.55)
		s[i] = (a - b) * grain * env * 1.6
	return s


func _door_hit() -> PackedFloat32Array:
	var s := _buf(0.5)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (_n() - lp) * 0.2
		var body := sin(TAU * 68.0 * t) * exp(-t * 14.0)
		var crack := _n() * exp(-t * 70.0)
		var rattle := lp * exp(-t * 9.0) * 0.6
		s[i] = body * 0.9 + crack * 0.6 + rattle
	return s


func _creak() -> PackedFloat32Array:
	var s := _buf(0.7)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 260.0 + 80.0 * sin(TAU * 1.3 * t) + _rng.randf_range(-30.0, 30.0)
		phase += TAU * f / RATE
		var grain := 0.5 + 0.5 * sin(TAU * 40.0 * t)
		var env := sin(PI * t / 0.7)
		s[i] = (fmod(phase / TAU, 1.0) * 2.0 - 1.0) * grain * env * 0.3
	return s


func _rattle() -> PackedFloat32Array:
	var s := _buf(0.8)
	var amp := 0.0
	var hp_prev := 0.0
	for i in s.size():
		var t := float(i) / RATE
		if i % int(RATE / 19.0) == 0:
			amp = _rng.randf_range(0.5, 1.0)
		var k := fmod(t * 19.0, 1.0)
		var x := _n()
		var hp := x - hp_prev
		hp_prev = x
		s[i] = hp * exp(-k * 25.0) * amp * 0.5 * (1.0 - t / 0.8 * 0.5)
	return s


func _rustle(dur: float, low: float = 0.0) -> PackedFloat32Array:
	var s := _buf(dur)
	var prev := 0.0
	var lp := 0.0
	var grain := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var x := _n()
		var hp := x - prev
		prev = x
		lp += (x - lp) * 0.08
		if i % 220 == 0:
			grain = _rng.randf() * _rng.randf()
		var env := sin(PI * t / dur)
		s[i] = (hp * (1.0 - low) + lp * low * 2.0) * grain * env * 0.7
	return s


func _growl() -> PackedFloat32Array:
	var s := _buf(1.1)
	var phase := 0.0
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		phase += TAU * (58.0 + 6.0 * sin(TAU * 3.0 * t)) / RATE
		lp += (_n() - lp) * 0.05
		var saw := fmod(phase / TAU, 1.0) * 2.0 - 1.0
		var trem := 0.55 + 0.45 * sin(TAU * 11.0 * t)
		var env := sin(PI * t / 1.1)
		s[i] = (saw * 0.5 + lp * 2.0) * trem * env * 0.8
	return s


func _down() -> PackedFloat32Array:
	var s := _buf(0.8)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		phase += TAU * lerpf(160.0, 90.0, t / 0.8) / RATE
		var thud := sin(TAU * 55.0 * t) * exp(-t * 12.0)
		var groan := sin(phase) * exp(-t * 3.0) * 0.4
		s[i] = thud + groan + _n() * exp(-t * 50.0) * 0.4
	return s


func _wind() -> PackedFloat32Array:
	var dur := 6.0
	var s := _buf(dur)
	var lp := 0.0
	var lp2 := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (_n() - lp) * 0.03
		lp2 += (lp - lp2) * 0.2
		var gust := 0.55 + 0.45 * sin(TAU * t / dur * 2.0) * sin(TAU * t / dur)
		s[i] = lp2 * 3.5 * gust
	return s


func _drone() -> PackedFloat32Array:
	var dur := 8.0
	var s := _buf(dur)
	for i in s.size():
		var t := float(i) / RATE
		var beat := 0.6 + 0.4 * sin(TAU * t / dur * 3.0)
		s[i] = (sin(TAU * 41.25 * t) * 0.5 + sin(TAU * 61.875 * t) * 0.3 + sin(TAU * 82.5 * t) * 0.1) * beat * 0.5
	return s


func _breath() -> PackedFloat32Array:
	# Two ragged breaths a loop: in (rising hiss) and out (falling, lower).
	var dur := 3.2
	var s := _buf(dur)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var cyc := fmod(t, 1.6) / 1.6
		var inhale := sin(PI * clampf(cyc / 0.4, 0.0, 1.0)) if cyc < 0.4 else 0.0
		var exhale := sin(PI * clampf((cyc - 0.45) / 0.45, 0.0, 1.0)) if cyc >= 0.45 and cyc < 0.9 else 0.0
		lp += (_n() - lp) * (0.25 if inhale > 0.0 else 0.12)
		s[i] = lp * (inhale * 0.7 + exhale * 0.55) * 1.4
	return s
