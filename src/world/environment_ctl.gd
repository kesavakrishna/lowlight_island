extends Node3D
## Client-side sky, sun/moon, ambient and fog driven by the shared clock.
## Purely cosmetic: creature detection never reads anything from here.

const D = preload("res://src/core/defs.gd")

var match_ref: Node = null
var env: Environment
var sky_mat: ProceduralSkyMaterial
var light: DirectionalLight3D
var wind: AudioStreamPlayer
var drone: AudioStreamPlayer


func _ready() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_sky_affect = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	light = DirectionalLight3D.new()
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 70.0
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(light)
	wind = Sfx.make_loop("wind", -14.0)
	add_child(wind)
	drone = Sfx.make_loop("drone", -40.0)
	add_child(drone)
	if Sfx.enabled:
		wind.play()
		drone.play()
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	if match_ref == null:
		return
	var phase: int = match_ref.phase
	var f: float = clampf(match_ref.phase_time / Tuning.phase_length(phase), 0.0, 1.0)
	var day: float = match_ref.daylight()
	var elev := 0.0
	var az := 0.0
	var col := Color(1.0, 0.96, 0.88)
	var energy := 1.15
	match phase:
		D.Phase.DAY:
			elev = lerpf(25.0, 62.0, sin(PI * f) * 0.9 + 0.1 * f)
			az = lerpf(-60.0, 60.0, f)
			col = Color(1.0, 0.95, 0.85)
		D.Phase.DUSK:
			elev = lerpf(22.0, 2.0, f)
			az = lerpf(60.0, 80.0, f)
			col = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.45, 0.25), f)
			energy = lerpf(1.1, 0.25, f)
		D.Phase.NIGHT:
			# Moonlight: dim, cool, still casts shadows so silhouettes read.
			elev = 42.0
			az = -30.0
			col = Color(0.55, 0.65, 0.95)
			energy = 0.13
		D.Phase.DAWN:
			elev = lerpf(3.0, 20.0, f)
			az = lerpf(-80.0, -60.0, f)
			col = Color(1.0, 0.6, 0.45).lerp(Color(1.0, 0.92, 0.85), f)
			energy = lerpf(0.15, 1.0, f)
	light.rotation_degrees = Vector3(-elev, az, 0)
	light.light_color = col
	light.light_energy = energy
	var night := 1.0 - day
	sky_mat.sky_top_color = Color(0.32, 0.47, 0.68).lerp(Color(0.008, 0.01, 0.025), night)
	sky_mat.sky_horizon_color = Color(0.68, 0.72, 0.74).lerp(Color(0.03, 0.035, 0.05), night)
	if phase == D.Phase.DUSK or phase == D.Phase.DAWN:
		sky_mat.sky_horizon_color = sky_mat.sky_horizon_color.lerp(Color(0.6, 0.3, 0.2), 0.5 * sin(PI * f))
	sky_mat.ground_bottom_color = Color(0.1, 0.1, 0.09).lerp(Color(0.005, 0.005, 0.008), night)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.sun_angle_max = 20.0
	env.ambient_light_color = Color(0.55, 0.6, 0.65).lerp(Color(0.25, 0.3, 0.45), night)
	env.ambient_light_energy = lerpf(0.55, 0.075, night)
	env.fog_light_color = Color(0.62, 0.66, 0.7).lerp(Color(0.015, 0.018, 0.03), night)
	env.fog_density = lerpf(0.006, 0.035, night)
	if drone.stream:
		drone.volume_db = lerpf(-40.0, -16.0, night)
		wind.volume_db = lerpf(-14.0, -19.0, night)
