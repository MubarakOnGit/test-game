shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Activated only when player is in water. Full wave + ripple effect.
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform float absorption    = 0.5;
uniform float foam_distance = 0.35;
uniform float edge_softness = 0.15;

uniform vec4 shallow_color : source_color = vec4(0.20, 0.70, 0.95, 0.65);
uniform vec4 deep_color    : source_color = vec4(0.05, 0.35, 0.85, 0.95);
uniform vec4 foam_color    : source_color = vec4(0.92, 0.97, 1.0, 1.0);
uniform float wave_strength = 0.30;

uniform sampler2D noise1;
uniform sampler2D noise2;

uniform vec4 ripple_data[16];
uniform vec4 ripple_params[16];
uniform float global_time;

varying vec3 world_vertex;
varying vec3 view_pos;

void vertex() {
	world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	view_pos     = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 reconstruct_view_position(vec2 uv, float depth, mat4 inv_proj) {
	vec4 clip = vec4(uv * 2.0 - 1.0, depth, 1.0);
	vec4 view = inv_proj * clip;
	return view.xyz / view.w;
}

void fragment() {
	float raw_depth   = texture(depth_texture, SCREEN_UV).r;
	vec3  terrain_pos = reconstruct_view_position(SCREEN_UV, raw_depth, INV_PROJECTION_MATRIX);
	float thickness   = max(0.0, view_pos.z - terrain_pos.z);

	float transmission = exp(-thickness * absorption);
	vec4  base_color   = mix(deep_color, shallow_color, transmission);

	vec2 wpos = world_vertex.xz * 0.22;
	float n1 = texture(noise1, wpos + vec2( 0.08,  0.06) * TIME).r;
	float n2 = texture(noise2, wpos * 0.65 + vec2(-0.06,  0.10) * TIME).r;

	float wave = (n1 + n2) * 0.5 * 2.0 - 1.0;
	base_color.rgb += wave * wave_strength;

	float shore_mask = 1.0 - smoothstep(0.0, foam_distance, thickness);
	shore_mask = pow(shore_mask, 2.5);
	float band = sin(thickness * 8.0 + TIME * 1.5) * 0.5 + 0.5;
	float foam_noise = clamp(n1 * n2 * 4.0, 0.0, 1.0);
	float foam = clamp(shore_mask * band * foam_noise, 0.0, 1.0);

	float ripple_brightness = 0.0;
	float ripple_foam = 0.0;
	for (int i = 0; i < 8; i++) {
		float spawn_time = ripple_data[i].w;
		if (spawn_time <= 0.0) continue;
		float age = global_time - spawn_time;
		float max_age = ripple_params[i].x;
		if (age <= 0.0 || age >= max_age) continue;
		vec2  delta = world_vertex.xz - ripple_data[i].xz;
		float r = length(delta) + 0.001;
		float wavefront = ripple_params[i].w * age / 3.0;
		float env = 1.0 - smoothstep(0.0, wavefront + 1.0, r);
		float life_fade = 1.0 - (age / max_age);
		life_fade *= life_fade;
		float ring = sin(3.0 * r - ripple_params[i].w * age);
		ripple_brightness += ring * env * life_fade * ripple_params[i].y * 0.4;
		ripple_foam += max(0.0, ring) * env * life_fade * ripple_params[i].z;
	}
	base_color.rgb = clamp(base_color.rgb + ripple_brightness, 0.0, 1.0);
	foam = clamp(foam + ripple_foam, 0.0, 1.0);

	float edge = smoothstep(0.0, edge_softness, thickness);
	vec4 final_color = mix(base_color, foam_color, foam);
	ALBEDO = clamp(final_color.rgb, 0.0, 1.0);
	ALPHA  = final_color.a * edge;
	ROUGHNESS = 0.05; // Smoother for better sky reflections
	METALLIC = 0.1;
	SPECULAR = 0.8;   // Catch sun highlights better
}
