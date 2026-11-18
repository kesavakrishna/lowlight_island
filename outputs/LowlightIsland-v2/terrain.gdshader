shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform vec2 island_axis;
uniform vec4 basins[6];
uniform float shore_radius = 93.0;
varying vec3 ground;
varying float ground_up;

float hash(vec2 p) {
	return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453);
}
float noise2(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),
		mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() {
	ground=VERTEX;
	ground_up=NORMAL.y;
}
void fragment() {
	vec2 p=ground.xz;
	float broad=noise2(p*0.24)*0.7+noise2(p*0.89)*0.3;
	float grain=noise2(p*12.0)*0.6+noise2(p*34.0)*0.4;
	float water_distance=99.0;
	for(int i=0;i<6;i++){water_distance=min(water_distance,length((p-basins[i].xy)/basins[i].zw));}
	float wet=1.0-smoothstep(0.72,1.09,water_distance+(broad-0.5)*0.21);
	vec3 green=mix(vec3(0.18,0.25,0.17),vec3(0.32,0.38,0.24),broad);
	float bare=smoothstep(0.57,0.78,noise2(p*0.19+11.0))*0.62;
	vec3 land=mix(green,vec3(0.33,0.27,0.19),bare);
	vec2 local=vec2(dot(p,island_axis),dot(p,vec2(-island_axis.y,island_axis.x)));
	float canopy=min(length((local-vec2(3,18))/vec2(26,18)),length((local-vec2(18,-25))/vec2(26,18)));
	float litter=(1.0-smoothstep(0.53,1.2,canopy))*(0.65+0.28*broad);
	land=mix(land,mix(vec3(0.16,0.18,0.12),vec3(0.23,0.21,0.14),broad),litter);
	float slope=1.0-clamp(ground_up,0.0,1.0);
	float cliff=smoothstep(0.12,0.39,slope+(broad-0.53)*0.1);
	vec2 rock_bands=vec2(p.x*0.21+p.y*0.15,ground.y*1.38+broad*2.1);
	float layers=noise2(rock_bands)*0.7+noise2(rock_bands*2.76)*0.3;
	float fissure=pow(1.0-abs(2.0*noise2(p*0.42+ground.y*0.085)-1.0),19.0);
	vec3 stone=mix(vec3(0.25,0.25,0.228),vec3(0.44,0.43,0.375),layers);
	stone *= 1.0-0.22*fissure;
	float moss=smoothstep(0.45,0.68,noise2(p*0.42))*smoothstep(0.35,0.84,ground_up);
	land=mix(land,mix(stone,green*0.91,moss*0.65),cliff);
	land=mix(land,vec3(0.27,0.23,0.16),wet);
	land=mix(land,vec3(0.54,0.47,0.33),smoothstep(shore_radius,shore_radius+3.8,length(p)));
	float relief=(layers*0.78-fissure*0.13)*cliff;
	vec3 dx=dFdx(VERTEX);
	vec3 dy=dFdy(VERTEX);
	float area=dot(dx,cross(dy,NORMAL));
	vec3 shading=cross(dy,NORMAL)*dFdx(relief)+cross(NORMAL,dx)*dFdy(relief);
	NORMAL=normalize(NORMAL-clamp(shading*(0.064*sign(area)/max(abs(area),0.0001)),vec3(-0.24),vec3(0.24)));
	ALBEDO=land*(0.91+grain*0.18);
	ROUGHNESS=0.92;
}
