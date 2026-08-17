shader_type spatial;
render_mode diffuse_lambert, cull_disabled;

// ── Entity interaction (up to 8 entities) ─────────────────────────────────────
uniform vec3 entity_positions[8];
uniform int  entity_count = 0;
uniform float interaction_radius = 2.5;
uniform float interaction_strength = 0.6;

// ── Wind ───────────────────────────────────────────────────────────────────────
uniform float wind_strength   : hint_range(0.0, 1.0) = 0.18;
uniform float wind_speed      : hint_range(0.0, 5.0) = 1.2;
uniform vec2  wind_direction  = vec2(1.0, 0.5);

// ── Color ──────────────────────────────────────────────────────────────────────
uniform vec3 color_tip  : source_color = vec3(0.388, 0.678, 0.149);  // #63ad26
uniform vec3 color_mid  : source_color = vec3(0.298, 0.549, 0.110);  // #4c8c1c
uniform vec3 color_base : source_color = vec3(0.180, 0.380, 0.055);  // #2e6110

varying float local_height;   // local Y of vertex (0 = root, 1 = tip)

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	// Normalized height: 0 at root, 1 at tip
	// Grass blades are about 0.5 units tall in local space
	local_height = clamp(VERTEX.y / 0.55, 0.0, 1.0);

	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float height_factor = local_height * local_height;

	if (height_factor < 0.01) {
		return;
	}

	// ── Wind ──────────────────────────────────────────────────────────────────
	float phase = hash2(floor(world.xz / 3.0)) * 6.2832;
	float time_val = TIME * wind_speed + phase;
	vec2 wind_dir_n = normalize(wind_direction);
	float wind_wave = sin(time_val) * 0.7 + sin(time_val * 1.73 + 0.5) * 0.3;
	vec2 wind_offset = wind_dir_n * wind_wave * wind_strength * height_factor;

	// ── Entity interaction ─────────────────────────────────────────────────────
	vec2 push = vec2(0.0);
	for (int i = 0; i < 8; i++) {
		if (i >= entity_count) break;
		vec2 to_entity = world.xz - entity_positions[i].xz;
		float dist = length(to_entity);
		if (dist < interaction_radius && dist > 0.001) {
			float strength = (1.0 - smoothstep(0.0, interaction_radius, dist))
			                 * interaction_strength * height_factor;
			push -= normalize(to_entity) * strength;
		}
	}

	vec3 total_offset = vec3(wind_offset.x + push.x, 0.0, wind_offset.y + push.y);
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * total_offset);
}

void fragment() {
	// Height-based green gradient: dark root -> bright tip
	// Side faces (detected by local_height) get a slight shade
	vec3 grass_col;
	if (local_height > 0.65) {
		grass_col = mix(color_mid, color_tip, (local_height - 0.65) / 0.35);
	} else {
		grass_col = mix(color_base, color_mid, local_height / 0.65);
	}

	// Darken sides slightly using the fragment normal
	float side_shade = mix(0.72, 1.0, clamp(NORMAL.y + 0.5, 0.0, 1.0));
	ALBEDO    = grass_col * side_shade;
	ROUGHNESS = 1.0;
	METALLIC  = 0.0;
}
