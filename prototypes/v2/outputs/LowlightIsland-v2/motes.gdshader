shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform float intensity = 0.0;
varying float phase;
void vertex(){
	vec3 p=MODEL_MATRIX[3].xyz;
	phase=dot(p,vec3(1.17,0.79,1.51));
	float t=TIME*(0.42+0.12*sin(phase))+phase;
	p+=vec3(0.72*sin(t)+0.24*cos(2.1*t),0.46*sin(t*1.41),0.64*cos(t*0.81));
	vec4 center=VIEW_MATRIX*vec4(p,1.0);
	center.xy+=VERTEX.xy*(1.0+0.28*sin(phase));
	POSITION=PROJECTION_MATRIX*center;
}
void fragment(){
	float d=length(UV-0.5)*2.0;
	float core=exp(-20.0*d*d);
	float halo=exp(-4.8*d*d)*(1.0-smoothstep(0.72,1.0,d));
	ALBEDO=mix(vec3(0.32,0.90,0.79),vec3(0.99,0.78,0.39),smoothstep(-0.4,0.7,sin(phase)))+vec3(core);
	ALPHA=intensity*(core+halo*0.48)*(0.64+0.28*sin(TIME*1.65+phase));
}
