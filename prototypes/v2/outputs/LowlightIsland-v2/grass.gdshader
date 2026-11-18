shader_type spatial;
render_mode cull_disabled, specular_disabled;

varying float height;
varying vec3 tint;

void vertex() {
	height = VERTEX.y;
	tint = COLOR.rgb;
	tint *= mix(vec3(1.0),vec3(0.58,0.40,0.28),UV.x);
	vec2 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz;
	float gust = sin(TIME * 1.7 + dot(world, vec2(0.31, 0.22)));
	VERTEX.x += height * height * gust * 0.083;
}

void fragment() {
	float fold = 1.0 - 0.21*sin(UV.y*3.14159) + 0.075*UV.y;
	ALBEDO = tint * mix(0.50, 1.06, clamp(height * 1.3, 0.0, 1.0))*fold;
	ROUGHNESS = 1.0;
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0, 1, 0, 0)).xyz, 0.7));
}
