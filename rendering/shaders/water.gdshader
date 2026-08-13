shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, shadows_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

uniform float absorption = 0.5;
uniform float foam_distance = 0.35;
uniform float edge_softness = 0.15;

uniform vec4 shallow_color : source_color = vec4(0.3, 0.7, 0.8, 0.6);
uniform vec4 deep_color    : source_color = vec4(0.1, 0.3, 0.6, 0.95);
uniform vec4 foam_color    : source_color = vec4(1.0, 1.0, 1.0, 1.0);

uniform sampler2D noise1;
uniform sampler2D noise2;
uniform vec2 noise1_scroll = vec2(0.02, 0.015);
uniform vec2 noise2_scroll = vec2(-0.01, 0.025);

varying vec3 view_pos;

void vertex() {
	view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 reconstruct_view_position(vec2 uv, float depth, mat4 inv_proj) {
	vec4 clip = vec4(uv * 2.0 - 1.0, depth, 1.0);
	vec4 view = inv_proj * clip;
	return view.xyz / view.w;
}

void fragment() {
	// Reconstruct terrain view position
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec3 terrain_pos = reconstruct_view_position(SCREEN_UV, depth, INV_PROJECTION_MATRIX);

	// Calculate screen-space thickness (distance in view space along the Z axis)
	// Note: View space Z is negative and goes deeper into the screen.
	// So terrain_pos.z is more negative than view_pos.z.
	float water_thickness = view_pos.z - terrain_pos.z;
	
	// Beer's Law for deep/shallow color blend
	float transmission = exp(-water_thickness * absorption);
	vec4 base_color = mix(deep_color, shallow_color, transmission);
	
	// Sample noise textures
	float n1 = texture(noise1, UV * 4.0 + TIME * noise1_scroll).r;
	float n2 = texture(noise2, UV * 3.0 + TIME * noise2_scroll).r;
	float combined_noise = n1 * n2;
	
	// Small wave normal distortion
	// We use the noise to perturb the normal slightly
	vec3 wave_normal = normalize(vec3(n1 * 0.1, 1.0, n2 * 0.1));
	NORMAL = (VIEW_MATRIX * vec4(wave_normal, 0.0)).xyz; // Convert to view space for proper Fresnel
	
	// Subtle Fresnel
	// Note: since our camera is isometric and orthographic, VIEW is essentially constant, 
	// but the distorted normal makes the fresnel shimmer nicely on the waves.
	float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 4.0);
	base_color = mix(base_color, vec4(1.0, 1.0, 1.0, base_color.a), fresnel * 0.2);
	
	// Foam Logic
	float foam = 1.0 - smoothstep(0.0, foam_distance, water_thickness);
	foam *= combined_noise * 2.0; // Boost noise strength slightly
	foam = clamp(foam, 0.0, 1.0);
	
	// Edge fade (soft shoreline instead of hard cut)
	float edge = smoothstep(0.0, edge_softness, water_thickness);
	
	vec4 final_color = mix(base_color, foam_color, foam);
	
	ALBEDO = final_color.rgb;
	ALPHA = final_color.a * edge;
}
