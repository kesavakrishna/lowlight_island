extends CanvasLayer
## In-run HUD: shared clock, prompts, stamina, cover feedback, directional cue arrows
## for critical audio (also visible with audio muted), notices, debug overlay,
## pause menu and results.

const D = preload("res://src/core/defs.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const Preview = preload("res://src/worldgen/preview.gd")
const Hints = preload("res://src/ui/hints.gd")
const HowToPlay = preload("res://src/ui/how_to_play.gd")

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
var _objective: Label
var _broadcast_bar: ProgressBar
var _map: Control
var _map_tex: TextureRect
var _map_marks: Control
var _map_px := 4
var _pings: Array = []   # {pos, kind, name, t, node}
var _note_panel: PanelContainer
var _note_title: Label
var _note_body: Label
var _note_t := 0.0
var hints: Control
var _captions: VBoxContainer
var _how: Control
var _feedback: LineEdit
var _nerve_veil: TextureRect
var _nerve_label: Label


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Low nerve closes in from the edges of vision.
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, 1))
	grad.set_offset(0, 0.45)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 1.05)
	gt.width = 256
	gt.height = 256
	_nerve_veil = TextureRect.new()
	_nerve_veil.texture = gt
	_nerve_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_nerve_veil.stretch_mode = TextureRect.STRETCH_SCALE
	_nerve_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nerve_veil.modulate.a = 0.0
	root.add_child(_nerve_veil)
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

	_objective = _label(root, 18, Control.PRESET_CENTER_TOP, Vector2(-420, 44), Vector2(840, 50))
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	_broadcast_bar = ProgressBar.new()
	_broadcast_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_broadcast_bar.position = Vector2(-150, 98)
	_broadcast_bar.size = Vector2(300, 8)
	_broadcast_bar.show_percentage = false
	_broadcast_bar.max_value = 1.0
	_broadcast_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bfill := StyleBoxFlat.new()
	bfill.bg_color = Color(0.6, 0.8, 1.0, 0.9)
	var bbg := StyleBoxFlat.new()
	bbg.bg_color = Color(0, 0, 0, 0.5)
	_broadcast_bar.add_theme_stylebox_override("fill", bfill)
	_broadcast_bar.add_theme_stylebox_override("background", bbg)
	_broadcast_bar.visible = false
	root.add_child(_broadcast_bar)

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
	_nerve_label = _label(root, 15, Control.PRESET_BOTTOM_RIGHT, Vector2(-180, -40), Vector2(160, 24))
	_nerve_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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

	hints = Hints.new()
	hints.match_ref = match_ref
	root.add_child(hints)
	_captions = VBoxContainer.new()
	_captions.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_captions.position = Vector2(-420, -230)
	_captions.size = Vector2(400, 150)
	_captions.alignment = BoxContainer.ALIGNMENT_END
	_captions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_captions)
	_build_map(root)
	_feedback = LineEdit.new()
	_feedback.placeholder_text = "Playtest note (Enter to save, Esc to cancel)"
	_feedback.anchor_left = 0.5
	_feedback.anchor_right = 0.5
	_feedback.anchor_top = 0.0
	_feedback.offset_left = -300.0
	_feedback.offset_right = 300.0
	_feedback.offset_top = 120.0
	_feedback.offset_bottom = 156.0
	_feedback.visible = false
	_feedback.text_submitted.connect(func(t: String) -> void:
		if t.strip_edges() != "":
			match_ref.save_feedback(t)
			notice("Note saved to user://feedback.log")
		_close_feedback())
	root.add_child(_feedback)
	_note_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.86, 0.82, 0.7, 0.94)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(18)
	_note_panel.add_theme_stylebox_override("panel", sb)
	_note_panel.anchor_left = 1.0
	_note_panel.anchor_right = 1.0
	_note_panel.anchor_top = 0.5
	_note_panel.anchor_bottom = 0.5
	_note_panel.offset_left = -470.0
	_note_panel.offset_right = -30.0
	_note_panel.offset_top = -160.0
	_note_panel.offset_bottom = 60.0
	_note_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note_panel.visible = false
	root.add_child(_note_panel)
	var nb := VBoxContainer.new()
	_note_panel.add_child(nb)
	_note_title = Label.new()
	_note_title.add_theme_font_size_override("font_size", 20)
	_note_title.add_theme_color_override("font_color", Color(0.18, 0.14, 0.1))
	nb.add_child(_note_title)
	_note_body = Label.new()
	_note_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_body.custom_minimum_size = Vector2(400, 0)
	_note_body.add_theme_color_override("font_color", Color(0.22, 0.18, 0.12))
	nb.add_child(_note_body)
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


func _build_map(root: Control) -> void:
	_map = Control.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.visible = false
	root.add_child(_map)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.add_child(shade)
	_map_tex = TextureRect.new()
	_map_tex.set_anchors_preset(Control.PRESET_CENTER)
	_map_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.add_child(_map_tex)
	_map_marks = Control.new()
	_map_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_marks.draw.connect(_draw_map)
	_map_tex.add_child(_map_marks)


## A keeper's note, shown beside the view without stopping play.
func show_note(title: String, body: String) -> void:
	_note_title.text = title
	_note_body.text = body
	_note_panel.visible = true
	_note_t = 14.0


const PING_COLORS := {"move": Color(0.45, 0.9, 1.0), "danger": Color(1.0, 0.35, 0.3), "hold": Color(1.0, 0.85, 0.35)}
const PING_TEXT := {"move": "MOVE HERE", "danger": "DANGER", "hold": "HOLD"}


## A silent marker from a teammate, visible in the world and on the map for a few seconds.
func add_ping(pos: Vector3, kind: String, who: String) -> void:
	var l := Label3D.new()
	l.text = "%s\n%s" % [PING_TEXT.get(kind, kind), who]
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0018
	l.font_size = 30
	l.outline_size = 8
	l.modulate = PING_COLORS.get(kind, Color.WHITE)
	l.position = pos + Vector3(0, 1.2, 0)
	match_ref.add_child(l)
	_pings.append({"pos": pos, "kind": kind, "name": who, "t": 8.0, "node": l})
	notice("%s: %s" % [who, PING_TEXT.get(kind, kind).to_lower()])


func _tick_pings(delta: float) -> void:
	for pg in _pings:
		pg["t"] -= delta
		var n: Label3D = pg["node"]
		n.modulate.a = clampf(pg["t"] / 2.0, 0.0, 1.0)
	for pg in _pings.filter(func(x: Dictionary) -> bool: return x["t"] <= 0.0):
		(pg["node"] as Node).queue_free()
	_pings = _pings.filter(func(x: Dictionary) -> bool: return x["t"] > 0.0)


func toggle_map() -> void:
	if match_ref and _ensure_map_texture():
		_map.visible = not _map.visible


func _ensure_map_texture() -> bool:
	if _map_tex.texture:
		return true
	var w: Node = match_ref.world
	if not ("gen" in w) or w.gen == null:
		return false
	# A rough sketch: terrain only. Landmarks appear as the crew learns them.
	var img: Image = Preview.render(w.gen, _map_px, false)
	img.adjust_bcs(1.05, 0.75, 0.85)
	_map_tex.texture = ImageTexture.create_from_image(img)
	_map_tex.custom_minimum_size = img.get_size()
	_map_tex.size = img.get_size()
	_map_tex.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	_map_marks.size = img.get_size()
	return true


func _map_point(p: Vector3) -> Vector2:
	var g: RefCounted = match_ref.world.gen
	var o: Vector2 = g.origin()
	return Vector2((p.x - o.x) / g.cell, (p.z - o.y) / g.cell) * _map_px


func _draw_map() -> void:
	var m := match_ref
	var w: Node = m.world
	var obj: RefCounted = m.objectives
	var font := ThemeDB.fallback_font
	var lm: Dictionary = w.landmarks
	_map_mark(_map_point(lm["crash"]), Color(1, 0.3, 0.2), "wreck", font)
	_map_mark(_map_point(lm["radio"]), Color(0.95, 0.35, 0.95), "radio shed", font)
	if obj.dock_known:
		_map_mark(_map_point(lm["dock"]), Color(0.3, 0.9, 1.0), "old dock", font)
	if obj.battery_found or obj.battery_state != obj.Bat.SITE:
		_map_mark(_map_point(obj.battery_pos), Color(1, 0.85, 0.2), "battery", font)
	else:
		# The wreck sketch: a rough circle around the battery site, not the exact spot.
		var g: RefCounted = w.gen
		var hint: Vector3 = w.battery_spot + Vector3(sin(g.seed_value) * 9.0, 0, cos(g.seed_value * 1.7) * 9.0)
		_map_marks.draw_arc(_map_point(hint), 22.0 / g.cell * _map_px, 0, TAU, 40, Color(1, 0.85, 0.2, 0.9), 2.0)
		_map_marks.draw_string(font, _map_point(hint) + Vector2(-30, -26), "battery?", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.85, 0.2))
	for i in w.caves.size():
		if i < obj.caves_known.size() and obj.caves_known[i]:
			_map_mark(_map_point(w.caves[i]["door_point"]), Color(0.85, 0.85, 0.85), "cave", font)
	for i in w.burrows.size():
		if i < obj.burrows_known.size() and obj.burrows_known[i]:
			var names: Array = m.captive_names(i)
			_map_mark(_map_point(w.burrows[i]), Color(0.6, 0.35, 0.15), "burrow" + ("  (" + ", ".join(names) + ")" if not names.is_empty() else ""), font)
	var ex: RefCounted = m.expedition
	if ex and ex.enabled:
		var g: RefCounted = w.gen
		if ex.known["lighthouse"]:
			_map_mark(_map_point(g.lighthouse), Color(0.95, 0.95, 0.85), "lighthouse", font)
		if ex.known["cottage"]:
			_map_mark(_map_point(g.cottage), Color(0.8, 0.7, 0.55), "keeper's cottage", font)
		if ex.known["skiff"] or ex.known["parts"]:
			_map_mark(_map_point(g.skiff), Color(0.55, 0.75, 0.85), "skiff", font)
		if ex.known["parts"]:
			for pt in ex.parts:
				if pt["state"] != ex.Part.FITTED and pt["state"] != ex.Part.CARRIED:
					_map_marks.draw_arc(_map_point(pt["pos"]), 10.0, 0, TAU, 20, Color(0.55, 0.75, 0.85), 2.0)
	for pg in _pings:
		var pp := _map_point(pg["pos"])
		_map_marks.draw_circle(pp, 6.0, PING_COLORS.get(pg["kind"], Color.WHITE))
		_map_marks.draw_string(font, pp + Vector2(8, -6), PING_TEXT.get(pg["kind"], ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PING_COLORS.get(pg["kind"], Color.WHITE))
	for p in m.players.values():
		if p.mode == D.Mode.ESCAPED or p.mode == D.Mode.CAPTURED:
			continue
		var pt := _map_point(p.global_position)
		if p == m.local_player:
			var dir := Vector2(-sin(p.yaw), -cos(p.yaw))
			var side := Vector2(-dir.y, dir.x)
			_map_marks.draw_colored_polygon(PackedVector2Array([pt + dir * 9.0, pt + side * 5.0 - dir * 4.0, pt - side * 5.0 - dir * 4.0]), Color(1, 1, 1))
		else:
			_map_marks.draw_circle(pt, 4.0, Color(0.6, 1.0, 0.6) if p.mode != D.Mode.DOWNED else Color(1, 0.3, 0.3))
			_map_marks.draw_string(font, pt + Vector2(6, 4), p.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 1, 0.8))


func _map_mark(pt: Vector2, col: Color, text: String, font: Font) -> void:
	_map_marks.draw_rect(Rect2(pt - Vector2(5, 5), Vector2(10, 10)), Color(0, 0, 0))
	_map_marks.draw_rect(Rect2(pt - Vector2(4, 4), Vector2(8, 8)), col)
	_map_marks.draw_string(font, pt + Vector2(8, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


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
	controls.text = "WASD move · Shift sprint · Ctrl/C crouch · Z prone · Space jump/stand/climb down\nE interact (hold to revive) · F lantern shutter · G throw noisemaker · R rope\nQ put the battery down · V build / repair (wood) · M map · H rest\nLeft click shove · hold 1 / 3 lean · X move / B danger / N hold ping · Space into a ledge to climb over\nF3 creature debug overlay · F6 skip phase (host, dev)"
	controls.add_theme_font_size_override("font_size", 15)
	_pause_main.add_child(controls)
	for b in [["Resume", _resume], ["How to play", _open_how], ["Settings", _open_settings], ["Leave run", _leave]]:
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


func _close_feedback() -> void:
	_feedback.visible = false
	_feedback.text = ""
	if not _pause.visible and not _results.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if _feedback.visible:
		if event.is_action_pressed("pause"):
			_close_feedback()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("feedback"):
		_feedback.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_feedback.grab_focus()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("map"):
		if match_ref and _ensure_map_texture():
			_map.visible = not _map.visible
		get_viewport().set_input_as_handled()
		return
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


func _open_how() -> void:
	_pause_main.visible = false
	if _how == null:
		_how = HowToPlay.new()
		_how.closed.connect(func() -> void:
			_how.visible = false
			_pause_main.visible = true)
		_settings.get_parent().add_child(_how)
	_how.visible = true


func _open_settings() -> void:
	_pause_main.visible = false
	_settings.visible = true


func _leave() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.leave_session("You left the run.")


# ------------------------------------------------------------------ API used by match

## Optional captions for notable sounds (Settings.captions), with a rough direction.
func caption(text: String, pos: Vector3) -> void:
	if not Settings.captions or match_ref == null or match_ref.local_player == null:
		return
	var p: Node = match_ref.local_player
	var d: Vector3 = pos - p.global_position
	var ang := wrapf(atan2(-d.x, -d.z) - float(match_ref.look_yaw), -PI, PI)
	var dir := "ahead" if absf(ang) < 0.6 else ("behind" if absf(ang) > 2.5 else ("left" if ang > 0.0 else "right"))
	for c in _captions.get_children():
		if (c as Label).text.begins_with(text):
			c.queue_free()
	var l := Label.new()
	l.text = "%s (%s)" % [text, dir]
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.85, 0.88, 0.9))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_captions.add_child(l)
	while _captions.get_child_count() > 5:
		_captions.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)


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


func big_message(title: String, sub: String) -> void:
	_show_banner(title, sub)
	_banner_t = 7.0
	notice(sub)


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
	var lines: Array[String] = ["Nights on the island: %d" % int(summary.get("nights", 0))]
	for c in summary.get("crew", []):
		lines.append("%s  -  %s" % [c[0], "escaped" if c[1] else "left behind"])
	if not summary.get("won", false):
		lines.append("The island keeps its secrets - for now.")
	info.text = "\n".join(lines)
	box.add_child(info)
	# The playtest question from the brief: what would you do differently?
	var q := Label.new()
	q.text = "What would you do differently next time?"
	box.add_child(q)
	var answer := LineEdit.new()
	answer.placeholder_text = "e.g. take the dry bank, build the ladder early, leave the battery under cover before dark"
	answer.custom_minimum_size = Vector2(520, 0)
	box.add_child(answer)
	var save := Button.new()
	save.text = "Save answer with this run's report"
	save.pressed.connect(func() -> void:
		match_ref.save_answer(answer.text)
		save.text = "Saved (user://runs)")
	box.add_child(save)
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
	_tick_pings(delta)
	var obj: RefCounted = m.objectives
	_objective.text = obj.objective_text() if obj else ""
	var ex: RefCounted = m.expedition
	if ex and ex.objective_text() != "":
		_objective.text += "\n" + ex.objective_text()
	if _note_t > 0.0:
		_note_t -= delta
		_note_panel.visible = _note_t > 0.0
	_broadcast_bar.visible = obj != null and obj.enabled and obj.radio_powered and not obj.broadcast_done and obj.broadcast > 0.0
	if _broadcast_bar.visible:
		_broadcast_bar.value = obj.broadcast
	if _map.visible:
		_map_marks.queue_redraw()

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
		if p.carrying:
			lines.append("Carrying the battery  [Q] put down")
		if p.resting:
			lines.append("Resting while someone keeps watch")
		lines.append("%s · Lantern %s · Noisemakers %d · Wood %d" % [stance_name, "OPEN" if p.lantern_open else "shuttered", p.noisemakers, p.wood])
		_status.text = "\n".join(lines)
		var low := clampf(1.0 - p.nerve / Tuning.nerve_max, 0.0, 1.0)
		_nerve_veil.modulate.a = lerpf(_nerve_veil.modulate.a, smoothstep(0.3, 1.0, low) * 0.85, clampf(delta * 2.0, 0.0, 1.0))
		_nerve_label.visible = Settings.show_nerve
		_nerve_label.text = "Nerve %d" % int(p.nerve)
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
