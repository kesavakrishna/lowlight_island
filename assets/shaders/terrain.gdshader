// Island terrain. Adapted from the v2 prototype's terrain shader: biome colour comes from
// the generator through vertex COLOR (rgb = biome albedo, a = wetness); slope adds bedded
// rock with fissures and moss; fine grain and relief keep it readable at arm's length.
shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform float water_level = 0.3;
varying vec3 ground;
varying float ground_up;
varying vec4 tint;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise2(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ground_up = NORMAL.y;
	tint = COLOR;
}

void fragment() {
	vec2 p = ground.xz;
	float broad = noise2(p * 0.24) * 0.7 + noise2(p * 0.89) * 0.3;
	float grain = noise2(p * 12.0) * 0.6 + noise2(p * 34.0) * 0.4;
	vec3 land = tint.rgb * (0.82 + broad * 0.36);
	float bare = smoothstep(0.6, 0.8, noise2(p * 0.19 + 11.0)) * 0.35;
	land = mix(land, vec3(0.30, 0.25, 0.18), bare * (1.0 - tint.a));
	float slope = 1.0 - clamp(ground_up, 0.0, 1.0);
	float cliff = smoothstep(0.16, 0.42, slope + (broad - 0.53) * 0.1);
	vec2 rock_bands = vec2(p.x * 0.21 + p.y * 0.15, ground.y * 1.38 + broad * 2.1);
	float layers = noise2(rock_bands) * 0.7 + noise2(rock_bands * 2.76) * 0.3;
	float fissure = pow(1.0 - abs(2.0 * noise2(p * 0.42 + ground.y * 0.085) - 1.0), 19.0);
	vec3 stone = mix(vec3(0.25, 0.25, 0.228), vec3(0.44, 0.43, 0.375), layers);
	stone *= 1.0 - 0.22 * fissure;
	float moss = smoothstep(0.45, 0.68, noise2(p * 0.42)) * smoothstep(0.35, 0.84, ground_up);
	land = mix(land, mix(stone, tint.rgb * 0.9, moss * 0.6), cliff);
	// Wet ground near and under the water line.
	float wet = max(tint.a, 1.0 - smoothstep(water_level - 0.2, water_level + 0.45, ground.y));
	land = mix(land, land * vec3(0.62, 0.6, 0.55), wet * 0.8);
	float relief = (layers * 0.78 - fissure * 0.13) * cliff;
	vec3 dx = dFdx(VERTEX);
	vec3 dy = dFdy(VERTEX);
	float area = dot(dx, cross(dy, NORMAL));
	vec3 shading = cross(dy, NORMAL) * dFdx(relief) + cross(NORMAL, dx) * dFdy(relief);
	NORMAL = normalize(NORMAL - clamp(shading * (0.064 * sign(area) / max(abs(area), 0.0001)), vec3(-0.24), vec3(0.24)));
	ALBEDO = land * (0.91 + grain * 0.18);
	ROUGHNESS = 0.92;
}
