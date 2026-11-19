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
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func() -> void:
		Settings.save_settings()
		closed.emit())
	add_child(back)


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
