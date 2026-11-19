shader_type sky;

// Canopy Realism sky: clean, matte, softly shaded.
// cloud_map: r = fbm density, g/b = packed density gradient (see work/bake-weather.gd).
uniform sampler2D cloud_map : repeat_enable, filter_linear_mipmap;
uniform vec4 upper : source_color;
uniform vec4 horizon : source_color;
uniform vec4 cloud_color : source_color;
uniform float night;
uniform float twilight;
uniform vec3 sun_direction = vec3(-0.75, 0.3, -0.55);
uniform vec3 moon_direction = vec3(0.3, 0.35, -0.88);

const float SUN_RADIUS = 0.0125;  // radians, a little larger than life so it reads in game
const float MOON_RADIUS = 0.019;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// Isotropic star field: one candidate star per 3D cell, so no stretching toward the horizon.
float stars(vec3 dir, float scale, float keep, float size, float t) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	float h = hash13(cell);
	if (h < keep) {
		return 0.0;
	}
	vec3 centre = cell + 0.2 + hash33(cell) * 0.6;
	float d = length(p - centre);
	float r = fract(h * 71.3);
	float brightness = 0.25 + 0.75 * r * r * r;
	float twinkle = 0.8 + 0.2 * sin(t * (1.7 + 3.0 * fract(h * 13.1)) + h * 40.0);
	return brightness * twinkle * exp(-d * d / (size * size));
}

void sky() {
	vec3 dir = EYEDIR;
	float height = max(dir.y, 0.0);
	float sun = max(0.0, dot(dir, sun_direction));
	float moon = max(0.0, dot(dir, moon_direction));
	float day = 1.0 - night;
	float solar_strength = day * smoothstep(-0.055, 0.07, sun_direction.y);
	float lunar_strength = night * smoothstep(-0.04, 0.12, moon_direction.y);

	// Sky gradient: deep zenith, pale horizon, brighter toward the sun.
	vec3 tone = mix(horizon.rgb, upper.rgb, 1.0 - exp(-3.2 * height));
	float flat_sun = max(0.0, dot(normalize(vec3(dir.x, 0.0, dir.z) + 1e-5), normalize(vec3(sun_direction.x, 0.0, sun_direction.z) + 1e-5)));
	tone += day * vec3(0.10, 0.09, 0.07) * pow(flat_sun, 3.0) * exp(-height * 4.0);
	// Warm band at sunrise and sunset, strongest on the sun's side.
	float sunset = twilight * (1.0 - night) * (0.35 + 0.65 * pow(flat_sun, 2.0)) * exp(-height * 3.2);
	tone += vec3(0.42, 0.17, 0.05) * sunset;
	tone = mix(tone, horizon.rgb * 0.9, smoothstep(0.0, -0.08, dir.y));

	// Stars and a faint galactic band; hidden by daylight, moonglow and low haze.
	if (night > 0.01 && dir.y > 0.0) {
		float star_vis = night * night * smoothstep(0.02, 0.22, height) * (1.0 - 0.85 * pow(moon, 18.0) * lunar_strength);
		float s = stars(dir, 170.0, 0.93, 0.13, TIME) * 0.55 + stars(dir, 68.0, 0.975, 0.11, TIME) * 1.25;
		vec3 star_tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.9, 0.78), hash13(floor(dir * 68.0)));
		tone += star_tint * s * star_vis;
		vec3 band_axis = normalize(vec3(0.35, 0.42, 0.84));
		float band = exp(-pow(dot(dir, band_axis) / 0.2, 2.0));
		float dust = texture(cloud_map, dir.xz * 0.9 + dir.y * 0.3).r;
		tone += vec3(0.035, 0.04, 0.06) * band * smoothstep(0.35, 0.75, dust) * star_vis;
	}

	// Sun: crisp disc, tight corona and wide soft glow. Warmer and larger glow when low.
	vec3 sun_tint = mix(vec3(1.0, 0.96, 0.88), vec3(1.0, 0.62, 0.32), twilight);
	float sun_angle = acos(clamp(dot(dir, sun_direction), -1.0, 1.0));
	float disc = 1.0 - smoothstep(SUN_RADIUS * 0.85, SUN_RADIUS, sun_angle);
	tone += solar_strength * sun_tint * (disc * 2.4 + pow(sun, 900.0) * 0.55 + pow(sun, 60.0) * 0.16 + pow(sun, 8.0) * (0.05 + 0.12 * twilight));

	// Moon: soft-edged disc with darker maria and a cool halo.
	float moon_angle = acos(clamp(dot(dir, moon_direction), -1.0, 1.0));
	float moon_disc = 1.0 - smoothstep(MOON_RADIUS * 0.9, MOON_RADIUS, moon_angle);
	vec3 m_right = normalize(cross(moon_direction, vec3(0.0, 1.0, 0.0)) + vec3(1e-4, 0.0, 0.0));
	vec3 m_up = cross(m_right, moon_direction);
	vec2 m_uv = vec2(dot(dir, m_right), dot(dir, m_up)) / MOON_RADIUS;
	float maria = texture(cloud_map, m_uv * 0.11 + vec2(0.37, 0.61)).r;
	float limb = sqrt(max(0.0, 1.0 - dot(m_uv, m_uv)));
	vec3 moon_surface = vec3(0.86, 0.89, 0.94) * (0.72 + 0.28 * limb) * (1.0 - 0.35 * smoothstep(0.45, 0.62, maria));
	tone = mix(tone, moon_surface * 1.15, moon_disc * lunar_strength);
	tone += lunar_strength * vec3(0.45, 0.55, 0.75) * (pow(moon, 1500.0) * 0.18 + pow(moon, 90.0) * 0.06 + pow(moon, 10.0) * 0.025);

	// Clouds: flat cumulus layer projected on a plane overhead, drifting slowly.
	vec2 drift = vec2(TIME * 0.0011, -TIME * 0.0004);
	vec2 uv = dir.xz / (height + 0.09) * 0.085 + drift;
	vec3 bank = texture(cloud_map, uv).rgb;
	float detail = texture(cloud_map, uv * 3.1 + vec2(0.31, 0.17) + drift * 0.6).r;
	float density = bank.r * 0.74 + detail * 0.26;
	float coverage = mix(0.505, 0.5, night);
	float opacity = smoothstep(coverage, coverage + 0.07, density) * smoothstep(0.0, 0.1, height);
	// Light from the sun by day and the moon by night; gradient gives lit faces and shaded cores.
	vec3 light_vec = mix(sun_direction, moon_direction, night);
	vec2 light_dir = normalize(light_vec.xz + 1e-5);
	float lit_edge = dot(bank.gb - 0.5, light_dir) * 2.2;
	float core = smoothstep(coverage + 0.04, coverage + 0.24, density);
	float shade = clamp(1.0 - core * 0.32 + lit_edge * 0.55, 0.55, 1.12);
	vec3 shadow_tint = mix(upper.rgb * 0.7 + vec3(0.25), cloud_color.rgb * 0.6, night);
	vec3 clouds = mix(shadow_tint, cloud_color.rgb, clamp(shade - 0.1, 0.0, 1.0));
	// Silver lining where thin cloud passes near the sun or moon.
	float thin = 1.0 - core;
	clouds += thin * (solar_strength * sun_tint * pow(sun, 24.0) * 0.9 + lunar_strength * vec3(0.4, 0.48, 0.62) * pow(moon, 30.0) * 0.6);
	clouds += vec3(0.32, 0.13, 0.04) * sunset * (1.0 - core * 0.5);
	// Fade distant clouds into the horizon haze.
	clouds = mix(clouds, tone, smoothstep(0.22, 0.0, height) * 0.55);
	COLOR = mix(tone, clouds, opacity);
}
