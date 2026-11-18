shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform vec4 base_color : source_color = vec4(0.4, 0.4, 0.4, 1.0);
uniform vec3 grain = vec3(2.0);
uniform float variation = 0.35;
uniform bool bark = false;
uniform bool stone = false;
uniform bool merged_geometry = false;
varying vec3 surface_point;
varying vec3 world_normal;
varying vec3 world_pos;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x),
			mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
			mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
	surface_point = merged_geometry ? CUSTOM0.xyz : VERTEX;
	world_pos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec3 p = surface_point * grain;
	float mottling = noise3(p) * 0.66 + noise3(p * 4.1) * 0.25 + noise3(p * 11.7) * 0.09;
	vec3 color = base_color.rgb * (1.0 + (mottling - 0.48) * variation * 1.20);
	float relief = mottling;
	if (bark) {
		float broad = noise3(world_pos*vec3(0.73,0.38,0.73));
		float grain_detail = noise3(p*vec3(1.8,0.54,1.8)+broad*3.0);
		float grooves = smoothstep(0.54,0.78,grain_detail);
		float shade = 0.12*dot(normalize(world_normal),normalize(vec3(-0.6,0.25,0.7)));
		float green = smoothstep(0.50,0.68,broad+shade+0.13*mottling-0.14*smoothstep(2.0,10.0,surface_point.y));
		color = mix(color*(1.10-0.42*grooves),mix(vec3(0.095,0.14,0.066),vec3(0.24,0.28,0.12),grain_detail),green*0.83);
		relief += grooves*0.42;
	}
	if (stone) {
		float strata = noise3(p * vec3(0.32,2.1,0.37) + noise3(p*0.34)*1.15);
		float seams = smoothstep(0.44,0.49,strata) * (1.0-smoothstep(0.49,0.56,strata));
		float moss = smoothstep(0.45,0.8,world_normal.y) * smoothstep(0.35,0.69,noise3(p*0.49));
		color = mix(color*(1.04-seams*0.23),vec3(0.29,0.32,0.18),moss*0.81);
		float joint = abs(fract(world_pos.y*0.63+world_pos.x*0.11+noise3(world_pos*0.47)*0.48)-0.5);
		float fracture = 1.0-smoothstep(0.012,0.060,joint);
		float mineral = smoothstep(0.65,0.83,noise3(world_pos*vec3(1.3,7.0,1.3)));
		color = mix(color,vec3(0.51,0.49,0.43),mineral*0.36)*(1.0-fracture*0.33);
		relief += strata*0.46-fracture*0.33+mineral*0.17;
	}
	vec3 edge_x = dFdx(VERTEX);
	vec3 edge_y = dFdy(VERTEX);
	vec3 slope = cross(edge_y,NORMAL)*dFdx(relief) + cross(NORMAL,edge_x)*dFdy(relief);
	float area = dot(edge_x,cross(edge_y,NORMAL));
	NORMAL = normalize(NORMAL - clamp(0.019*slope/(max(abs(area),0.0001)),vec3(-0.29),vec3(0.29))*sign(area));
	ALBEDO = color;
	ROUGHNESS = 0.95;
}
