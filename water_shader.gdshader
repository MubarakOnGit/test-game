shader_type spatial;
render_mode diffuse_lambert, blend_mix;

uniform vec4 water_color : source_color = vec4(0.16, 0.71, 0.96, 0.85);

void fragment() {
	ALBEDO = water_color.rgb;
	ALPHA = water_color.a;
	ROUGHNESS = 0.1;
	SPECULAR = 0.8;
}
