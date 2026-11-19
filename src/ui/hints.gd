extends Control
## Teaching the controls in the first run: short contextual hints, each shown once the
## first time its situation comes up, remembered across runs (Settings.hints_seen).
## They never compete with critical warnings (those keep their own direction arrows).

const D = preload("res://src/core/defs.gd")

var match_ref: Node = null
var _panel: PanelContainer
var _label: Label
var _queue: Array[String] = []
var _show_t := 0.0
var _check_t := 0.0

# id -> text. Conditions live in _check().
const HINTS := {
	"start": "Find the battery and get it to the radio shed. [M] opens the rough map from the wreck. [F] opens or shutters your lantern.",
	"tree": "Every tree can be climbed - [E] at the trunk. Some only partway by hand; a ladder ([V], 2 wood) reaches the top.",
	"wood": "[E] takes wood. [V] builds where you stand: ladders, platforms up a tree, screens, rope exits, low walls in caves.",
	"cave": "Caves hide light and break sight. [E] opens / closes the door; it holds for a while and [V] repairs it. The crawl hole at the back fits you lying down ([Z]).",
	"battery": "The battery is heavy: no sprinting, jumping or climbing with it. [Q] puts it down - anyone can pick it up again.",
	"dusk": "Dusk. They come up at nightfall. Choose a shelter while there's light: a cave, up a tree, or tall grass.",
	"night": "Night. Crouch ([Ctrl]) or go prone ([Z]) in tall grass; keep still when one passes. Sprinting is loud. [G] throws a noisemaker to pull one away.",
	"flicker": "Your lantern flickers when one of them is close. That is always real.",
	"nerve": "Your nerve is fraying - breathing gets loud enough for them to hear. Light, company, rest ([H]) and daylight steady you. Not everything you see is there.",
	"down": "A teammate is down. Hold [E] beside them to revive. If one is dragging them off, shove it (left click) or throw a noisemaker.",
	"radio": "The radio has power. The broadcast only carries after dark, someone has to stay with it, and it draws every creature in range. Choose your night.",
	"note": "The keeper left notes around the island. [E] to read - they're worth it.",
	"peek": "Hold [1] / [3] to lean around cover. [X] / [B] / [N] ping silently: move here / danger / hold.",
}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.08, 0.82)
	sb.border_color = Color(0.85, 0.75, 0.5, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -330.0
	_panel.offset_right = 330.0
	_panel.offset_top = -300.0
	_panel.offset_bottom = -210.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(630, 0)
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
	_panel.add_child(_label)


func show_hint(id: String) -> void:
	if not Settings.show_hints or Settings.hints_seen.has(id) or _queue.has(id):
		return
	Settings.hints_seen[id] = true
	Settings.save_settings()
	_queue.append(id)


func _process(delta: float) -> void:
	if match_ref == null:
		return
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.5
		_check()
	if _show_t > 0.0:
		_show_t -= delta
		_panel.modulate.a = clampf(_show_t, 0.0, 1.0)
		if _show_t <= 0.0:
			_panel.visible = false
	elif not _queue.is_empty():
		_label.text = HINTS.get(_queue.pop_front(), "")
		_panel.visible = true
		_panel.modulate.a = 1.0
		_show_t = 9.0


func _check() -> void:
	var m := match_ref
	var p: Node = m.local_player
	if p == null or m.over:
		return
	var obj: RefCounted = m.objectives
	if obj and obj.enabled:
		show_hint("start")
	if m.match_time > 40.0:
		show_hint("peek")
	match m.phase:
		D.Phase.DUSK: show_hint("dusk")
		D.Phase.NIGHT: show_hint("night")
	var pos: Vector3 = p.global_position
	for t in m.world.trees:
		if (t["pos"] as Vector3).distance_to(pos) < 2.5:
			show_hint("tree")
			break
	if "wood_piles" in m.world:
		for wp in m.world.wood_piles:
			if (wp["pos"] as Vector3).distance_to(pos) < 4.0:
				show_hint("wood")
				break
	for c in m.world.caves:
		if (c["door_point"] as Vector3).distance_to(pos) < 5.0:
			show_hint("cave")
			break
	if p.carrying:
		show_hint("battery")
	if p.nerve < Tuning.nerve_hallucinate_below + 10.0:
		show_hint("nerve")
	if obj and obj.enabled and obj.radio_powered:
		show_hint("radio")
	for c2 in m.creatures.values():
		if c2.awake and c2.global_position.distance_to(pos) < Tuning.lantern_flicker_dist and p.lantern_open:
			show_hint("flicker")
			break
	for q in m.players.values():
		if q != p and q.mode == D.Mode.DOWNED:
			show_hint("down")
			break
	var ex: RefCounted = m.expedition
	if ex and ex.enabled:
		for n in m.world.gen.notes:
			if (n["pos"] as Vector3).distance_to(pos) < 6.0:
				show_hint("note")
				break
