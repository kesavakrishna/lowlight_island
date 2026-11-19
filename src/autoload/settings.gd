extends Node
## Player preferences (autoload `Settings`) and input map. Saved to user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"

var mouse_sensitivity := 0.12   # degrees per pixel
var fov := 80.0
var camera_shake := 1.0         # 0 disables shake
var master_volume := 0.8
var show_nerve := false         # optional numeric Nerve meter (default: body and senses only)
var player_name := "Survivor"
var last_address := "127.0.0.1"


func _ready() -> void:
	_setup_input()
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
		fov = cfg.get_value("video", "fov", fov)
		camera_shake = cfg.get_value("video", "camera_shake", camera_shake)
		master_volume = cfg.get_value("audio", "master_volume", master_volume)
		show_nerve = cfg.get_value("video", "show_nerve", show_nerve)
		player_name = cfg.get_value("profile", "name", player_name)
		last_address = cfg.get_value("profile", "last_address", last_address)
	apply()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "camera_shake", camera_shake)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("video", "show_nerve", show_nerve)
	cfg.set_value("profile", "name", player_name)
	cfg.set_value("profile", "last_address", last_address)
	cfg.save(PATH)


func apply() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))
	changed.emit()


func _setup_input() -> void:
	_key("move_forward", [KEY_W, KEY_UP])
	_key("move_back", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("sprint", [KEY_SHIFT])
	_key("crouch", [KEY_CTRL, KEY_C])
	_key("prone", [KEY_Z])
	_key("jump", [KEY_SPACE])
	_key("interact", [KEY_E])
	_key("lantern", [KEY_F])
	_key("throw", [KEY_G])
	_key("rope", [KEY_R])
	_key("drop", [KEY_Q])
	_key("repair", [KEY_V])
	_key("map", [KEY_M])
	_key("lean_left", [KEY_1])
	_key("lean_right", [KEY_3])
	_key("ping", [KEY_X])
	_key("ping_danger", [KEY_B])
	_key("ping_hold", [KEY_N])
	_key("rest", [KEY_H])
	if not InputMap.has_action("shove"):
		InputMap.add_action("shove")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("shove", mb)
	_key("debug_overlay", [KEY_F3])
	_key("dev_skip_phase", [KEY_F6])
	_key("pause", [KEY_ESCAPE])


func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
