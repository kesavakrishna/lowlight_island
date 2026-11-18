shader_type spatial;
render_mode unshaded, depth_draw_never;

uniform vec2 current = vec2(0.0);
uniform vec2 basin_radius;
uniform bool marsh = false;
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 sky_tint : source_color = vec4(0.47, 0.58, 0.64, 1.0);
uniform vec4 zenith : source_color;
uniform sampler2D ripple_map : repeat_enable, filter_linear_mipmap;
uniform vec3 sun_direction;
uniform vec3 moon_direction;
uniform float night = 0.0;
varying vec3 local_pos;
varying vec3 world_pos;

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float depth_at(vec2 uv, float depth, mat4 inv_projection) {
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		depth = depth * 2.0 - 1.0;
	#endif
	vec4 p = inv_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return -p.z / p.w;
}

vec2 wave_slope(vec2 p, vec2 direction, float frequency, float rate, float strength) {
	return direction * cos(dot(p, direction) * frequency + TIME * rate) * strength;
}

void fragment() {
	if (marsh && length(local_pos.xz / basin_radius) > 0.98) {
		discard;
	}
	vec2 p = world_pos.xz - current*TIME;
	vec2 slopes = wave_slope(p, vec2(0.82, 0.57), 0.72, 1.18, 0.035);
	slopes += wave_slope(p, vec2(-0.33, 0.94), 1.56, 1.68, 0.029);
	vec2 capillary = texture(ripple_map, p*vec2(0.043,0.102)+vec2(TIME*0.004,0.0)).gb-0.5;
	vec2 crossing = texture(ripple_map, p.yx*vec2(0.12,0.068)-vec2(0.0,TIME*0.006)).gb-0.5;
	slopes += (capillary + crossing.yx*0.55)*0.52;
	slopes *= marsh ? 0.42 : 0.98;
	NORMAL = normalize((VIEW_MATRIX * vec4(slopes.x, 1.0, slopes.y, 0.0)).xyz);

	float distance_underwater = max(0.0, depth_at(SCREEN_UV, texture(scene_depth, SCREEN_UV).r, INV_PROJECTION_MATRIX) + VERTEX.z);
	float shore = exp(-distance_underwater * (marsh ? 1.35 : 2.12));
	vec2 distorted = clamp(SCREEN_UV + slopes * 0.12 * (1.0 - shore), vec2(0.001), vec2(0.999));
	float refracted_depth = depth_at(distorted, texture(scene_depth, distorted).r, INV_PROJECTION_MATRIX);
	vec3 floor_color = texture(scene_color, refracted_depth + VERTEX.z > 0.0 ? distorted : SCREEN_UV).rgb;
	vec3 tint = marsh ? vec3(0.116, 0.158, 0.076) : vec3(0.035, 0.145, 0.168);
	tint *= mix(1.0, 0.31, night);
	vec3 body = mix(tint, floor_color * vec3(0.71, 0.83, 0.69), shore * 0.82);

	float facing = clamp(dot(VIEW, NORMAL), 0.0, 1.0);
	float fresnel = 0.035 + 0.88 * pow(1.0 - facing, 5.0);
	vec3 reflected_ray = reflect(-VIEW, NORMAL);
	vec3 bounce = (INV_VIEW_MATRIX * vec4(reflected_ray, 0.0)).xyz;
	vec3 reflection = mix(sky_tint.rgb, zenith.rgb, 1.0-exp(-3.6*max(bounce.y,0.0)));
	if (marsh) {
		reflection *= mix(vec3(0.42, 0.52, 0.45), vec3(0.92), smoothstep(0.05, 0.24, bounce.y));
		if (fresnel > 0.08 && bounce.y > 0.0 && -VERTEX.z < 50.0) {
			// Reflect the visible far bank at its distance from this patch of water.
			vec2 radius = basin_radius;
			vec2 origin = local_pos.xz / radius;
			vec2 ray = bounce.xz / radius;
			float a = max(dot(ray,ray),0.00001);
			float b = dot(origin,ray);
			float bank_distance = (sqrt(max(b*b+a*(1.0-dot(origin,origin)),0.0))-b)/a;
			vec3 probe = VERTEX + reflected_ray * (bank_distance + 3.0);
			vec4 clip = PROJECTION_MATRIX * vec4(probe,1.0);
			if (clip.w > 0.0) {
				vec2 uv = clip.xy/clip.w*0.5+0.5;
				float edge_distance = min(min(uv.x,1.0-uv.x),min(uv.y,1.0-uv.y));
				if (edge_distance > 0.0) {
					float sampled = depth_at(uv,texture(scene_depth,uv).r,INV_PROJECTION_MATRIX);
					float foreground = smoothstep(-6.0,-1.0,sampled+probe.z);
					float weight = smoothstep(0.0,0.07,edge_distance)*foreground;
					reflection = mix(reflection,texture(scene_color,uv).rgb,weight*0.89);
				}
			}
		}
	}
	float ripple = sin(p.x * 4.6 + p.y * 5.8 + sin(p.y * 3.1) - TIME * 1.65);
	float edge = smoothstep(0.91, 0.999, shore) * smoothstep(0.13, 0.84, ripple);
	vec3 lit_water = mix(body, reflection, fresnel);
	// The highlight follows the same moving light that casts the island's shadows.
	float sunlight = pow(max(dot(bounce,sun_direction),0.0),240.0) * (1.0-night) * smoothstep(-0.02,0.09,sun_direction.y);
	float moonlight = pow(max(dot(bounce,moon_direction),0.0),330.0) * night * smoothstep(0.0,0.12,moon_direction.y);
	lit_water += (vec3(1.0,0.84,0.63)*sunlight + vec3(0.50,0.65,0.85)*moonlight) * (0.35+fresnel);
	lit_water += vec3(0.18, 0.22, 0.20) * edge * (marsh ? 0.09 : 0.44) * mix(1.0, 0.35, night);
	vec3 face = normalize(cross(dFdx(world_pos),dFdy(world_pos)));
	float cascade = 1.0-smoothstep(0.55,0.94,abs(face.y));
	float streak = texture(ripple_map,vec2(dot(world_pos.xz,vec2(0.47,0.69)),world_pos.y*0.09+TIME*0.46)).r;
	ALBEDO = mix(lit_water,mix(zenith.rgb,sky_tint.rgb,0.8)*(0.65+0.65*streak),cascade*0.92);
	ALPHA = 1.0;
}
