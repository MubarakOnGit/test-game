shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

void fragment() {
	ALBEDO = vec3(0.15, 0.55, 0.95); // More saturated, deeper blue
	ALPHA  = 1.0;
	ROUGHNESS = 0.05; // Smoother for better sky reflections
	METALLIC = 0.1;
	SPECULAR = 0.8;   // Catch sun highlights better
}
