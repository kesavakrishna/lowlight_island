extends VBoxContainer
## Mouse sensitivity, FOV, camera shake and volume. Used by the main menu and pause menu.

signal closed


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 28)
	add_child(title)
	_slider("Mouse sensitivity", 0.02, 0.5, 0.01, Settings.mouse_sensitivity, func(v: float) -> void: Settings.mouse_sensitivity = v)
	_slider("Field of view", 60.0, 110.0, 1.0, Settings.fov, func(v: float) -> void: Settings.fov = v)
	_slider("Camera shake", 0.0, 1.0, 0.05, Settings.camera_shake, func(v: float) -> void: Settings.camera_shake = v)
	_slider("Master volume", 0.0, 1.0, 0.05, Settings.master_volume, func(v: float) -> void: Settings.master_volume = v)
	var nerve_box := CheckBox.new()
	nerve_box.text = "Show a numeric Nerve meter"
	nerve_box.button_pressed = Settings.show_nerve
	nerve_box.toggled.connect(func(on: bool) -> void:
		Settings.show_nerve = on
		Settings.apply())
	add_child(nerve_box)
	_slider("Brightness", 0.6, 1.8, 0.05, Settings.brightness, func(v: float) -> void: Settings.brightness = v)
	_check("Show hints", Settings.show_hints, func(on: bool) -> void: Settings.show_hints = on)
	_check("Captions for sounds", Settings.captions, func(on: bool) -> void: Settings.captions = on)
	var reset := Button.new()
	reset.text = "Show all hints again"
	reset.pressed.connect(func() -> void:
		Settings.hints_seen = {}
		Settings.save_settings()
		reset.text = "Hints reset")
	add_child(reset)
	var keys_title := Label.new()
	keys_title.text = "Controls (click, then press a key or mouse button)"
	add_child(keys_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 220)
	add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	scroll.add_child(grid)
	for entry in Settings.REBINDABLE:
		var l := Label.new()
		l.text = entry[1]
		l.custom_minimum_size = Vector2(200, 0)
		grid.add_child(l)
		var b := Button.new()
		b.text = Settings.binding_text(entry[0])
		b.custom_minimum_size = Vector2(240, 0)
		var action: String = entry[0]
		b.pressed.connect(func() -> void:
			_listening = action
			_listen_button = b
			b.text = "press a key...")
		grid.add_child(b)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func() -> void:
		Settings.save_settings()
		closed.emit())
	add_child(back)


var _listening := ""
var _listen_button: Button


func _input(event: InputEvent) -> void:
	if _listening == "" or not is_visible_in_tree():
		return
	var code := 0
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_listen_button.text = Settings.binding_text(_listening)
			_listening = ""
			get_viewport().set_input_as_handled()
			return
		code = event.physical_keycode
	elif event is InputEventMouseButton and event.pressed:
		code = -event.button_index
	if code == 0:
		return
	Settings.rebind(_listening, code)
	_listen_button.text = Settings.binding_text(_listening)
	_listening = ""
	get_viewport().set_input_as_handled()


func _check(label: String, value: bool, setter: Callable) -> void:
	var c := CheckBox.new()
	c.text = label
	c.button_pressed = value
	c.toggled.connect(func(on: bool) -> void:
		setter.call(on)
		Settings.apply())
	add_child(c)


func _slider(label: String, lo: float, hi: float, step: float, value: float, setter: Callable) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(200, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(240, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := Label.new()
	val.custom_minimum_size = Vector2(60, 0)
	val.text = _fmt(value, step)
	s.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		val.text = _fmt(v, step)
		Settings.apply())
	row.add_child(s)
	row.add_child(val)
	add_child(row)


func _fmt(v: float, step: float) -> String:
	return "%d" % int(v) if step >= 1.0 else "%.2f" % v
