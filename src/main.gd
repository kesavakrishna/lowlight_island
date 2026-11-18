extends Node
## Root: switches between the menu/lobby and a running match, and handles
## command-line options for development and automated smoke tests.
##
## User args (after `--`):
##   --host                 host immediately
##   --join=ADDR            join ADDR immediately
##   --port=N  --name=S
##   --autostart=N          host starts the run once N players are in the lobby
##   --seed=N               replay a specific world seed
##   --fast-clock=X         phases run X times faster
##   --start-phase=night    host starts the run at dusk/night (dev)
##   --bot                  scripted input (smoke tests)
##   --quit-after=SECONDS   print a SMOKE report and quit

const Menu = preload("res://src/ui/main_menu.gd")
const MatchScript = preload("res://src/match/match.gd")
const D = preload("res://src/core/defs.gd")
const IslandGen = preload("res://src/worldgen/island_gen.gd")
const Preview = preload("res://src/worldgen/preview.gd")

var menu: Control = null
var match_node: Node = null
var opts: Dictionary = {}


func _ready() -> void:
	_parse_args()
	if opts.has("preview-seeds"):
		_preview_seeds()
		return
	Net.match_begin.connect(_on_match_begin)
	Net.returned_to_lobby.connect(_on_returned)
	Net.left_session.connect(_on_left)
	if opts.has("seed"):
		Net.forced_seed = int(opts["seed"])
	if opts.has("fast-clock"):
		Tuning.clock_scale = float(opts["fast-clock"])
	_show_menu()
	var port := int(opts.get("port", Tuning.default_port))
	var pname: String = opts.get("name", Settings.player_name)
	if opts.has("host"):
		var err := Net.host_session(port, pname)
		print("[main] host on port %d -> %s" % [port, error_string(err)])
		DisplayServer.window_set_title("Lowlight Island — host")
	elif opts.has("join"):
		var err2 := Net.join_session(str(opts["join"]), port, pname)
		print("[main] join %s:%d -> %s" % [opts["join"], port, error_string(err2)])
		DisplayServer.window_set_title("Lowlight Island — %s" % pname)
	if opts.has("autostart"):
		Net.roster_changed.connect(_check_autostart)
		_check_autostart()
	if opts.has("quit-after"):
		get_tree().create_timer(float(opts["quit-after"])).timeout.connect(_smoke_quit)
	if opts.has("screenshot"):
		get_tree().create_timer(float(opts.get("shot-delay", "4"))).timeout.connect(_screenshot)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "1"


func _check_autostart() -> void:
	if Net.is_host and not Net.in_match and Net.roster.size() >= int(opts["autostart"]):
		Net.start_match()


func _show_menu(message: String = "") -> void:
	if menu == null:
		menu = Menu.new()
		add_child(menu)
	menu.visible = true
	if message != "":
		menu.set_message(message)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_match_begin(params: Dictionary) -> void:
	if match_node:
		match_node.free()
	if menu:
		menu.queue_free()
		menu = null
	match_node = MatchScript.new()
	match_node.setup(params)
	match_node.bot = opts.has("bot")
	if Net.is_host and opts.has("start-phase"):
		match_node.dev_start_phase = {"day": D.Phase.DAY, "dusk": D.Phase.DUSK, "night": D.Phase.NIGHT}.get(str(opts["start-phase"]), -1)
	add_child(match_node)
	if opts.has("view") and match_node.local_player:
		# Dev: --view=x,y,z,yaw_deg,pitch_deg places the local (host) player for screenshots.
		var v: PackedFloat64Array = str(opts["view"]).split_floats(",")
		match_node.local_player.global_position = Vector3(v[0], v[1], v[2])
		match_node.look_yaw = deg_to_rad(v[3]) if v.size() > 3 else 0.0
		match_node.look_pitch = deg_to_rad(v[4]) if v.size() > 4 else 0.0
		if v.size() > 5:
			match_node.want_stance = int(v[5])
	if opts.has("lantern") and match_node.local_player:
		match_node.local_player.lantern_open = true
		match_node.request("lantern", true)
	if opts.has("log-ai"):
		for c in match_node.creatures.values():
			c.log_ai = true


func _on_returned() -> void:
	if match_node:
		match_node.queue_free()
		match_node = null
	_show_menu("Back in the lobby. The next run gets a fresh island.")
	if opts.has("autostart"):
		_check_autostart()


func _on_left(reason: String) -> void:
	if match_node:
		match_node.queue_free()
		match_node = null
	_show_menu(reason)


func _smoke_quit() -> void:
	if match_node:
		print(match_node.smoke_report())
	else:
		print("SMOKE no-match in_session=%s roster=%d" % [Net.in_session, Net.roster.size()])
	get_tree().quit()


func _screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(str(opts["screenshot"]))
	print("[main] screenshot saved ", opts["screenshot"])
	if not opts.has("quit-after"):
		get_tree().quit()


## Dev tool: --preview-seeds=1-12 [--out=DIR] writes one PNG per seed plus a contact sheet
## and prints each island's route times, biome shares and any rejected attempts.
func _preview_seeds() -> void:
	var spec := str(opts["preview-seeds"])
	var seeds: Array[int] = []
	for part in spec.split(","):
		if part.contains("-"):
			var ab := part.split("-")
			for s in range(int(ab[0]), int(ab[1]) + 1):
				seeds.append(s)
		else:
			seeds.append(int(part))
	var out := str(opts.get("out", "user://previews"))
	DirAccess.make_dir_recursive_absolute(out)
	var images: Array = []
	var ok := 0
	var t0 := Time.get_ticks_msec()
	for s in seeds:
		var gen := IslandGen.new()
		var good := gen.generate(s)
		for line in gen.log_lines:
			print("  ", line)
		if good:
			ok += 1
			print(gen.summary())
			var img := Preview.render(gen, 3)
			img.save_png("%s/seed_%d.png" % [out, s])
			images.append(img)
		else:
			print("seed %d FAILED: %s" % [s, gen.reject_reason])
			var blank := Image.create(Tuning.island_cells * 3, Tuning.island_cells * 3, false, Image.FORMAT_RGB8)
			blank.fill(Color(0.15, 0.02, 0.02))
			images.append(blank)
	Preview.contact_sheet(images, 4).save_png("%s/contact_sheet.png" % out)
	print("previews: %d/%d seeds accepted in %.1fs -> %s" % [ok, seeds.size(), (Time.get_ticks_msec() - t0) / 1000.0, ProjectSettings.globalize_path(out)])
	get_tree().quit(0 if ok == seeds.size() else 1)
