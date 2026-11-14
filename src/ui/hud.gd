extends CanvasLayer
## In-run HUD: shared clock, prompts, stamina, cover feedback, directional cue arrows
## for critical audio (also visible with audio muted), notices, debug overlay,
## pause menu and results.

const D = preload("res://src/core/defs.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")

var match_ref: Node = null

var _clock: Label
var _prompt: Label
var _status: Label
var _stamina: ProgressBar
var _banner: Label
var _banner_sub: Label
var _banner_t := 0.0
var _notices: VBoxContainer
var _cues: Control
var _debug: Label
var _pause: PanelContainer
var _pause_main: VBoxContainer
var _settings: Control
var _results: PanelContainer
var _vignette: ColorRect
var _cue_list: Array = []   # {text, pos, t, critical}


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.color = Color(0.35, 0.0, 0.0, 0.0)
	root.add_child(_vignette)

	var cross := ColorRect.new()
	cross.color = Color(1, 1, 1, 0.55)
	cross.size = Vector2(4, 4)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-2, -2)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)

	_clock = _label(root, 20, Control.PRESET_CENTER_TOP, Vector2(-300, 12), Vector2(600, 30))
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_banner = _label(root, 44, Control.PRESET_CENTER_TOP, Vector2(-400, 120), Vector2(800, 60))
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub = _label(root, 20, Control.PRESET_CENTER_TOP, Vector2(-400, 180), Vector2(800, 30))
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_prompt = _label(root, 22, Control.PRESET_CENTER_BOTTOM, Vector2(-400, -170), Vector2(800, 32))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_stamina = ProgressBar.new()
	_stamina.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stamina.position = Vector2(-120, -120)
	_stamina.size = Vector2(240, 10)
	_stamina.show_percentage = false
	_stamina.max_value = Tuning.stamina_max
	_stamina.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.8, 0.6, 0.8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	_stamina.add_theme_stylebox_override("fill", fill)
	_stamina.add_theme_stylebox_override("background", bg)
	root.add_child(_stamina)

	_status = _label(root, 17, Control.PRESET_BOTTOM_LEFT, Vector2(20, -90), Vector2(700, 70))
	_status.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

	_notices = VBoxContainer.new()
	_notices.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_notices.position = Vector2(20, 40)
	_notices.size = Vector2(560, 300)
	_notices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_notices)

	_cues = Control.new()
	_cues.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cues.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cues.draw.connect(_draw_cues)
	root.add_child(_cues)

	_debug = _label(root, 15, Control.PRESET_TOP_LEFT, Vector2(16, 60), Vector2(620, 400))
	_debug.visible = false
	_debug.add_theme_color_override("font_color", Color(1, 0.85, 0.45))

	_build_pause(root)
	_build_results(root)


func _label(parent: Control, size: int, preset: int, pos: Vector2, sz: Vector2) -> Label:
	var l := Label.new()
	l.set_anchors_preset(preset)
	l.position = pos
	l.size = sz
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.06, 0.93)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(28)
	p.add_theme_stylebox_override("panel", sb)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	parent.add_child(p)
	return p


func _build_pause(root: Control) -> void:
	_pause = _panel(root)
	_pause.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_pause.add_child(box)
	_pause_main = VBoxContainer.new()
	_pause_main.add_theme_constant_override("separation", 10)
	box.add_child(_pause_main)
	var t := Label.new()
	t.text = "Paused (the island is not)"
	t.add_theme_font_size_override("font_size", 26)
	_pause_main.add_child(t)
	var controls := Label.new()
	controls.text = "WASD move · Shift sprint · Ctrl/C crouch · Z prone · Space jump/stand/climb down\nE interact (hold to revive) · F lantern shutter · G throw noisemaker · R rope\nF3 creature debug overlay · F6 skip phase (host, dev)"
	controls.add_theme_font_size_override("font_size", 15)
	_pause_main.add_child(controls)
	for b in [["Resume", _resume], ["Settings", _open_settings], ["Leave run", _leave]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(b[1])
		_pause_main.add_child(btn)
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(func() -> void:
		_settings.visible = false
		_pause_main.visible = true)
	box.add_child(_settings)


func _build_results(root: Control) -> void:
	_results = _panel(root)
	_results.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _results.visible:
			return
		if _pause.visible:
			_resume()
		else:
			_pause.visible = true
			_pause_main.visible = true
			_settings.visible = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not _pause.visible and not _results.visible:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _resume() -> void:
	_pause.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open_settings() -> void:
	_pause_main.visible = false
	_settings.visible = true


func _leave() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.leave_session("You left the run.")


# ------------------------------------------------------------------ API used by match

func notice(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	_notices.add_child(l)
	while _notices.get_child_count() > 6:
		_notices.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(l.queue_free)


func cue(text: String, pos: Vector3, critical: bool) -> void:
	for c in _cue_list:
		if c["text"] == text:
			c["t"] = 2.5
			c["pos"] = pos
			return
	_cue_list.append({"text": text, "pos": pos, "t": 2.5, "critical": critical})


func phase_banner(phase: int, day: int) -> void:
	match phase:
		D.Phase.DAY:
			_show_banner("Day %d" % day, "Scout, gather, and prepare before dusk.")
		D.Phase.DUSK:
			_show_banner("Dusk", "They come up at nightfall. Commit to a shelter.")
		D.Phase.NIGHT:
			_show_banner("Night %d" % day, "Light keeps you steady. Light gets you found.")
		D.Phase.DAWN:
			_show_banner("Dawn", "They're going back under.")


func _show_banner(title: String, sub: String) -> void:
	_banner.text = title
	_banner_sub.text = sub
	_banner_t = 5.0


func show_results(summary: Dictionary) -> void:
	_pause.visible = false
	for c in _results.get_children():
		c.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_results.add_child(box)
	var t := Label.new()
	t.text = "The crew escaped" if summary.get("won", false) else "The crew was lost"
	t.add_theme_font_size_override("font_size", 40)
	box.add_child(t)
	var info := Label.new()
	info.text = "Nights survived: %d\nThe island keeps its secrets — for now." % int(summary.get("nights", 0))
	box.add_child(info)
	if Net.is_host:
		var b := Button.new()
		b.text = "Back to lobby (rematch)"
		b.pressed.connect(Net.return_to_lobby)
		box.add_child(b)
	else:
		var w := Label.new()
		w.text = "Waiting for the host to start a rematch..."
		box.add_child(w)
	var leave := Button.new()
	leave.text = "Leave session"
	leave.pressed.connect(_leave)
	box.add_child(leave)
	_results.visible = true


# ------------------------------------------------------------------ per-frame

func _process(delta: float) -> void:
	if match_ref == null:
		return
	var m := match_ref
	var left: float = maxf(0.0, Tuning.phase_length(m.phase) - m.phase_time)
	var label: String = D.PHASE_NAMES[m.phase]
	var next_names := ["dusk", "night", "dawn", "day"]
	var ordinal := ""
	if m.phase == D.Phase.DAY or m.phase == D.Phase.NIGHT:
		ordinal = " %d" % m.day_index
	_clock.text = "%s%s  ·  %d:%02d until %s" % [label, ordinal, int(left) / 60, int(left) % 60, next_names[m.phase]]
	_prompt.text = m.prompt_text()

	var p: Node = m.local_player
	if p:
		_stamina.value = p.stamina
		_stamina.visible = p.stamina < Tuning.stamina_max - 0.5
		var lines: Array[String] = []
		match p.cover:
			"grass":
				lines.append("Cover: tall grass" + (" — stay low" if p.stance == D.Stance.STAND else ""))
			"bush":
				lines.append("Cover: bush" + (" — keep still and low" if p.stance == D.Stance.STAND or p.moving else ""))
			"canopy":
				lines.append("Cover: canopy — movement shakes the branches")
		if p.inside_cave:
			lines.append("Inside the cave")
		var stance_name: String = ["Standing", "Crouched", "Prone"][p.stance]
		lines.append("%s · Lantern %s · Noisemakers %d" % [stance_name, "OPEN" if p.lantern_open else "shuttered", p.noisemakers])
		_status.text = "\n".join(lines)
		var target_a := 0.0
		if p.mode == D.Mode.DOWNED:
			target_a = 0.35 + 0.08 * sin(Time.get_ticks_msec() / 300.0)
		_vignette.color.a = lerpf(_vignette.color.a, target_a, clampf(delta * 4.0, 0.0, 1.0))

	if _banner_t > 0.0:
		_banner_t -= delta
		var a := clampf(_banner_t, 0.0, 1.0)
		_banner.modulate.a = a
		_banner_sub.modulate.a = a
	else:
		_banner.modulate.a = 0.0
		_banner_sub.modulate.a = 0.0

	for c in _cue_list:
		c["t"] -= delta
	_cue_list = _cue_list.filter(func(c: Dictionary) -> bool: return c["t"] > 0.0)
	_cues.queue_redraw()

	_debug.visible = m.debug_on
	if m.debug_on:
		var txt := "DEBUG (F3)  phase %s t=%.0f daylight %.2f\n" % [D.PHASE_NAMES[m.phase], m.phase_time, m.daylight()]
		for c in m.creatures.values():
			txt += "\n" + c.debug_text + "\n"
		if p:
			txt += "\nyou: mode %d stance %d tree %d cover '%s' cave %s err %.3f" % [p.mode, p.stance, p.tree_id, p.cover, p.inside_cave, p.last_err]
		_debug.text = txt


func _draw_cues() -> void:
	var m := match_ref
	if m == null or m.local_player == null:
		return
	var p: Node = m.local_player
	var center := _cues.size * 0.5
	var radius := minf(center.x, center.y) * 0.55
	var font := ThemeDB.fallback_font
	for c in _cue_list:
		var d: Vector3 = c["pos"] - p.global_position
		var ang := atan2(-d.x, -d.z) - float(m.look_yaw)
		ang = wrapf(ang, -PI, PI)
		var dir := Vector2(-sin(ang), -cos(ang))
		var tip := center + dir * radius
		var a := clampf(c["t"], 0.0, 1.0)
		var col := Color(1.0, 0.35, 0.25, a) if c["critical"] else Color(1, 1, 1, a * 0.7)
		var side := Vector2(-dir.y, dir.x) * 12.0
		_cues.draw_colored_polygon(PackedVector2Array([tip + dir * 18.0, tip + side, tip - side]), col)
		var txt: String = c["text"]
		var dist := d.length()
		txt += "  (%dm)" % int(dist)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var lp := tip - dir * 26.0 - Vector2(tw * 0.5, -6)
		_cues.draw_string(font, lp + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0, 0, 0, a))
		_cues.draw_string(font, lp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col)
