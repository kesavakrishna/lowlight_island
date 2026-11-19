extends Node3D
## Client-side sky, sun and moon, ambient light, fog and water tint driven by the shared clock.
## Uses the v2 prototype's Canopy Realism sky (clouds, stars, moon disc).
## Purely cosmetic: creature detection never reads anything from here.

const D = preload("res://src/core/defs.gd")

var match_ref: Node = null
var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var wind: AudioStreamPlayer
var drone: AudioStreamPlayer


func _ready() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://assets/shaders/sky.gdshader")
	sky_mat.set_shader_parameter("cloud_map", load("res://assets/textures/weather_noise.res"))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_sky_affect = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = _light(80.0)
	moon = _light(70.0)
	moon.light_color = Color("9cbcf0")
	wind = Sfx.make_loop("wind", -14.0)
	add_child(wind)
	drone = Sfx.make_loop("drone", -40.0)
	add_child(drone)
	if Sfx.enabled:
		wind.play()
		drone.play()
	_update()


func _light(shadow_dist: float) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.shadow_enabled = true
	l.directional_shadow_max_distance = shadow_dist
	l.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(l)
	return l


func _process(_delta: float) -> void:
	_update()


## Continuous sun path: rises through dawn, crosses the day, sets during dusk.
func _sun_phase(phase: int, f: float) -> float:
	match phase:
		D.Phase.DAWN: return lerpf(-0.08, 0.1, f)
		D.Phase.DAY: return lerpf(0.1, 0.86, f)
		D.Phase.DUSK: return lerpf(0.86, 1.06, f)
	return 1.2   # night: well below the horizon


func _update() -> void:
	if match_ref == null:
		return
	var phase: int = match_ref.phase
	var f: float = clampf(match_ref.phase_time / Tuning.phase_length(phase), 0.0, 1.0)
	var sp := _sun_phase(phase, f)
	var solar_height := sin(sp * PI) if sp < 1.1 else -0.6
	var sun_dir := Vector3(cos(sp * PI) * 0.88, solar_height, 0.42).normalized()
	var night_f := f if phase == D.Phase.NIGHT else (0.0 if phase == D.Phase.DUSK else 1.0)
	var moon_dir := Vector3(-cos(night_f * PI) * 0.7, 0.28 + 0.5 * sin(night_f * PI), -0.45).normalized()
	var darkness := 1.0 - smoothstep(-0.14, 0.15, solar_height)
	var warm := (1.0 - smoothstep(0.08, 0.56, absf(solar_height))) * (1.0 - darkness * 0.78)
	var sunlight := smoothstep(-0.03, 0.25, solar_height)

	var horizon := Color("c4dcec").lerp(Color("e8b488"), warm).lerp(Color("1c2a42"), darkness)
	var upper := Color("3d7cc0").lerp(Color("5b6aa0"), warm).lerp(Color("070e1e"), darkness)
	sky_mat.set_shader_parameter("upper", upper)
	sky_mat.set_shader_parameter("horizon", horizon)
	sky_mat.set_shader_parameter("cloud_color", Color("fbfcff").lerp(Color("f4c49c"), warm).lerp(Color("1e2a3e"), darkness))
	sky_mat.set_shader_parameter("night", darkness)
	sky_mat.set_shader_parameter("twilight", warm)
	sky_mat.set_shader_parameter("sun_direction", sun_dir)
	sky_mat.set_shader_parameter("moon_direction", moon_dir)

	sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.FORWARD)
	sun.light_color = Color("fff3de").lerp(Color("f4a468"), warm)
	sun.light_energy = sunlight * (1.16 - warm * 0.27)
	sun.visible = sunlight > 0.012
	moon.look_at_from_position(Vector3.ZERO, -moon_dir, Vector3.UP)
	# Moonlight stays readable across open ground: silhouettes must survive the dark.
	moon.light_energy = darkness * (0.10 + 0.14 * maxf(moon_dir.y, 0.0))
	moon.visible = darkness > 0.02

	env.ambient_light_color = Color(0.55, 0.6, 0.65).lerp(Color(0.25, 0.3, 0.45), darkness)
	env.ambient_light_energy = lerpf(0.55, 0.075, darkness)
	env.fog_light_color = horizon.lerp(Color(0.015, 0.018, 0.03), darkness * 0.7)
	env.fog_density = lerpf(0.0022, 0.035, darkness)

	var world: Node = match_ref.world
	if world and "water_materials" in world:
		for w in world.water_materials:
			w.set_shader_parameter("sky_tint", horizon)
			w.set_shader_parameter("zenith", upper)
			w.set_shader_parameter("sun_direction", sun_dir)
			w.set_shader_parameter("moon_direction", moon_dir)
			w.set_shader_parameter("night", darkness)
	if drone.stream:
		drone.volume_db = lerpf(-40.0, -16.0, darkness)
		wind.volume_db = lerpf(-14.0, -19.0, darkness)
