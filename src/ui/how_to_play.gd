extends VBoxContainer
## The "How to play" card shown from the menu and the lobby: the goal, the night,
## the creatures in general terms, Nerve, and the controls.

signal closed

const TEXT := """[b]Get off the island.[/b] Find the battery (the wreck's sketch shows roughly where), carry it to the radio shed on high ground, and run the broadcast after dark. A boat comes to the old dock at the next dawn - and waits only briefly.

[b]Days are for work.[/b] Scout, take wood, build shelter, move the battery. [b]Nights are for surviving.[/b] They come up out of the ground at dusk. There is no timer: each night more of them come, faster and smarter. Past the fourth night they stop hiding.

[b]They are not all alike.[/b] Some hunt by sight and are drawn to light. Some are blind and listen. Some feel you through soft ground. Some climb better than you. Read their tracks and tell each other what you think you're facing. They remember how you got away - and who hurt them.

[b]Light keeps you steady. Light gets you found.[/b] Darkness wears your nerve down; low nerve makes you breathe loudly and see things that aren't there. Your lantern only flickers on its own when one is really close.

[b]Hide:[/b] tall grass (crouch or prone), bushes, behind rocks, up trees, in caves behind a closed door. [b]Help:[/b] revive the downed, shove one off a friend, raid a burrow by day to free whoever was taken.

[b]Optional:[/b] the keeper's notes, her cottage and lighthouse, and her old skiff - a second way off if you can find its parts."""

const CONTROLS := [
	["WASD / mouse", "move / look"], ["Shift", "sprint (loud)"], ["Ctrl or C", "crouch"], ["Z", "prone"],
	["Space", "jump · stand · climb down · vault a ledge"], ["E", "interact (hold: revive, raid)"],
	["F", "lantern shutter"], ["G", "throw a noisemaker"], ["Left click", "shove"], ["Q", "put the battery down"],
	["V", "build / repair (wood)"], ["R", "rope down"], ["H", "rest (dark shelter, someone on watch)"],
	["Hold 1 / 3", "lean to peek"], ["X / B / N", "ping: move / danger / hold"], ["M", "map"], ["Esc", "menu and settings"],
]


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "How to play"
	title.add_theme_font_size_override("font_size", 28)
	add_child(title)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(620, 0)
	body.text = TEXT
	add_child(body)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	for c in CONTROLS:
		var k := Label.new()
		k.text = c[0]
		k.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
		grid.add_child(k)
		var v := Label.new()
		v.text = c[1]
		v.add_theme_color_override("font_color", Color(0.75, 0.78, 0.76))
		grid.add_child(v)
	add_child(grid)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func() -> void: closed.emit())
	add_child(back)
