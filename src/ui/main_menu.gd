extends Control
## Title screen, Host / Join by Address, lobby roster and settings.

const SettingsPanel = preload("res://src/ui/settings_panel.gd")

var _status: Label
var _name: LineEdit
var _addr: LineEdit
var _port: LineEdit
var _main_box: VBoxContainer
var _lobby_box: VBoxContainer
var _settings: Control
var _roster: Label
var _start: Button
var _hosting_info: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var beam := ColorRect.new()
	beam.color = Color(0.95, 0.82, 0.5, 0.05)
	beam.size = Vector2(2400, 160)
	beam.position = Vector2(-200, 120)
	beam.rotation = -0.18
	add_child(beam)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(560, 0)
	center.add_child(col)

	var title := Label.new()
	title.text = "LOWLIGHT ISLAND"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.92, 0.86, 0.7))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := Label.new()
	sub.text = "If you see the lamp flash after dark, get below the windows."
	sub.add_theme_color_override("font_color", Color(0.6, 0.62, 0.6))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(HSeparator.new())

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 10)
	col.add_child(_main_box)
	_name = _field(_main_box, "Your name", Settings.player_name)
	_addr = _field(_main_box, "Host address (IP, LAN or Tailscale/Radmin)", Settings.last_address)
	_port = _field(_main_box, "Port", str(Tuning.default_port))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_main_box.add_child(row)
	_button(row, "Host a run", _on_host)
	_button(row, "Join by address", _on_join)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	_main_box.add_child(row2)
	_button(row2, "Settings", _on_settings)
	_button(row2, "Quit", func() -> void: get_tree().quit())

	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 10)
	_lobby_box.visible = false
	col.add_child(_lobby_box)
	var lt := Label.new()
	lt.text = "Crew"
	lt.add_theme_font_size_override("font_size", 28)
	_lobby_box.add_child(lt)
	_roster = Label.new()
	_lobby_box.add_child(_roster)
	_hosting_info = Label.new()
	_hosting_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hosting_info.add_theme_color_override("font_color", Color(0.65, 0.7, 0.68))
	_lobby_box.add_child(_hosting_info)
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 10)
	_lobby_box.add_child(lrow)
	_start = _button(lrow, "Start run", func() -> void: Net.start_match())
	_button(lrow, "Leave", func() -> void: Net.leave_session())

	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(func() -> void:
		_settings.visible = false
		_main_box.visible = true)
	col.add_child(_settings)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(0.85, 0.75, 0.5))
	col.add_child(_status)

	var help := Label.new()
	help.text = "WASD move · Shift sprint · Ctrl crouch · Z prone · E interact · F lantern · G noisemaker · Q drop battery · V repair · M map · Esc menu"
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color(0.45, 0.48, 0.47))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(help)

	Net.roster_changed.connect(_refresh)
	Net.status.connect(func(m: String) -> void: _status.text = m)
	_refresh()


func set_message(msg: String) -> void:
	if _status:
		_status.text = msg


func _field(parent: Control, label: String, value: String) -> LineEdit:
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 14)
	parent.add_child(l)
	var e := LineEdit.new()
	e.text = value
	parent.add_child(e)
	return e


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(170, 40)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _save_fields() -> void:
	Settings.player_name = _name.text.strip_edges()
	Settings.last_address = _addr.text.strip_edges()
	Settings.save_settings()


func _on_host() -> void:
	_save_fields()
	var err := Net.host_session(int(_port.text), Settings.player_name)
	if err != OK:
		_status.text = "Could not host on port %s (error %d). Is another copy already hosting?" % [_port.text, err]


func _on_join() -> void:
	_save_fields()
	if Settings.last_address.is_empty():
		_status.text = "Enter the host's address."
		return
	var err := Net.join_session(Settings.last_address, int(_port.text), Settings.player_name)
	if err != OK:
		_status.text = "Could not start connecting (error %d)." % err


func _on_settings() -> void:
	_main_box.visible = false
	_settings.visible = true


func _refresh() -> void:
	var in_lobby := Net.in_session and not Net.roster.is_empty()
	_lobby_box.visible = in_lobby
	_main_box.visible = not in_lobby and not _settings.visible
	if not in_lobby:
		return
	var lines: Array[String] = []
	var ids: Array = Net.roster.keys()
	ids.sort()
	for id in ids:
		var r: Dictionary = Net.roster[id]
		lines.append("•  %s%s%s" % [r["name"], "  (host)" if int(id) == 1 else "", "  (you)" if int(id) == Net.local_id() else ""])
	_roster.text = "\n".join(lines) + "\n\n%d / %d survivors" % [Net.roster.size(), Tuning.max_players]
	_start.visible = Net.is_host
	_start.disabled = Net.roster.size() < Tuning.min_players_to_start
	if Net.is_host:
		var addrs: Array[String] = []
		for a in IP.get_local_addresses():
			if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
				addrs.append(a)
		_hosting_info.text = "Friends join with one of your addresses and port %s:\n%s\nRemote friends: use a mesh VPN such as Tailscale (100.x addresses) — see docs/REMOTE_PLAY.md." % [_port.text, ", ".join(addrs)]
	else:
		_hosting_info.text = "Waiting for the host to start the run..."
