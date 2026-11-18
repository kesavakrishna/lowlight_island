shader_type spatial;
render_mode cull_disabled, diffuse_burley;

varying vec2 leaf_uv;
varying vec3 leaf_color;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sway = sin(TIME * 1.46 + dot(origin, vec3(0.26, 0.19, 0.32)));
	VERTEX.x += UV.y * UV.y * sway * 0.035;
	leaf_uv = UV;
	leaf_color = COLOR.rgb;
}

void fragment() {
	float midrib = 1.0 - smoothstep(0.015, 0.070, abs(leaf_uv.x - 0.5));
	float tip_light = mix(0.76, 1.09, leaf_uv.y);
	ALBEDO = leaf_uv.x < 0.0 ? vec3(0.19,0.16,0.085) : leaf_color * (tip_light + midrib * 0.12);
	BACKLIGHT = leaf_color * 0.15;
	ROUGHNESS = 0.69;
	SPECULAR = 0.26;
}
