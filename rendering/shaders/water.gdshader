shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, shadows_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

// ─── Depth & Color ─────────────────────────────────────────────────────────
uniform float absorption    = 0.5;   // Restored — same as committed version
uniform float foam_distance = 0.35;  // Tight shore foam (same as committed)
uniform float edge_softness = 0.15;  // Soft edge fade (same as committed)

uniform vec4 shallow_color : source_color = vec4(0.25, 0.72, 0.82, 0.65);
uniform vec4 deep_color    : source_color = vec4(0.05, 0.22, 0.50, 0.95);
uniform vec4 foam_color    : source_color = vec4(0.92, 0.97, 1.0, 1.0);

// ─── Wave Surface ────────────────────────────────────────────────────────────
uniform sampler2D noise1;
uniform sampler2D noise2;
uniform float wave_strength = 0.38;  // Boosted — clearly visible brightness waves

// ─── Ripples ─────────────────────────────────────────────────────────────────
uniform vec4 ripple_data[16];    // xyz = world pos, w = spawn_time (0 = inactive)
uniform vec4 ripple_params[16];  // x = max_age, y = normal_strength, z = foam_strength, w = speed
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
	// ── Depth thickness ───────────────────────────────────────────────────────
	float raw_depth   = texture(depth_texture, SCREEN_UV).r;
	vec3  terrain_pos = reconstruct_view_position(SCREEN_UV, raw_depth, INV_PROJECTION_MATRIX);
	float thickness   = max(0.0, view_pos.z - terrain_pos.z);

	// ── Beer's Law depth color ─────────────────────────────────────────────────
	float transmission = exp(-thickness * absorption);
	vec4  base_color   = mix(deep_color, shallow_color, transmission);

	// ── Animated surface noise (world-space UVs — no tiling jump) ────────────
	// Two layers scroll in different directions at a visible speed
	vec2 wpos = world_vertex.xz * 0.22;  // Slightly larger scale for broader wave patches
	float n1 = texture(noise1, wpos + vec2( 0.08,  0.06) * TIME).r;
	float n2 = texture(noise2, wpos * 0.65 + vec2(-0.06,  0.10) * TIME).r;

	// Average and centre around zero → visible brightening / darkening patches
	float wave = (n1 + n2) * 0.5 * 2.0 - 1.0;
	base_color.rgb += wave * wave_strength;

	// ── Normal distortion from noise ──────────────────────────────────────────
	// Stronger normal tilt = more Fresnel shimmer visible in isometric view
	float nx = (n1 - 0.5) * 0.7;
	float nz = (n2 - 0.5) * 0.7;
	vec3 wave_normal = normalize(vec3(nx, 1.0, nz));
	NORMAL = normalize((VIEW_MATRIX * vec4(wave_normal, 0.0)).xyz);

	// ── Fresnel shimmer ────────────────────────────────────────────────────────
	float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 2.5);
	base_color.rgb = mix(base_color.rgb, vec3(0.85, 0.95, 1.0), fresnel * 0.40);

	// ── Shore foam (world-space bands moving TOWARD shore) ────────────────────
	// Shore mask: tight band at the very waterline only
	float shore_mask = 1.0 - smoothstep(0.0, foam_distance, thickness);
	// Sharpen it so only the thinnest sliver glows
	shore_mask = pow(shore_mask, 2.5);

	// Animated band moving toward shore (+TIME = toward lower thickness = toward land)
	float band = sin(thickness * 8.0 + TIME * 1.5) * 0.5 + 0.5;

	// Noise breaks up the hard sine bands
	float foam_noise = n1 * n2 * 4.0;
	foam_noise = clamp(foam_noise, 0.0, 1.0);

	float foam = shore_mask * band * foam_noise;
	foam = clamp(foam, 0.0, 1.0);

	// ── Ripples: sin(k*r - ω*t) wave physics ─────────────────────────────────
	float ripple_foam    = 0.0;
	float ripple_brightness = 0.0;

	for (int i = 0; i < 16; i++) {
		float spawn_time = ripple_data[i].w;
		if (spawn_time <= 0.0) continue;

		float age     = global_time - spawn_time;
		float max_age = ripple_params[i].x;
		if (age <= 0.0 || age >= max_age) continue;

		vec2  delta  = world_vertex.xz - ripple_data[i].xz;
		float r      = length(delta) + 0.001;

		// k = wave-number (rings per unit distance)
		// ω = angular velocity (expansion speed)
		float k = 3.0;
		float omega = ripple_params[i].w;  // speed parameter

		// Proper water-ripple formula: sin(k*r - ω*age)
		// Positive ω means rings EXPAND outward (natural)
		float ring = sin(k * r - omega * age);

		// Spatial envelope: fades beyond expanding wavefront radius
		float wavefront = omega * age / k;   // approximate outer radius
		float env = 1.0 - smoothstep(0.0, wavefront + 1.0, r);

		// Temporal envelope: fades as ripple ages
		float life_fade = 1.0 - (age / max_age);
		life_fade *= life_fade;

		float strength = ring * env * life_fade * ripple_params[i].y;

		// Add brightness perturbation (makes ring visible as lighter water)
		ripple_brightness += strength * 0.4;

		// Foam on the leading edge only (positive phase of the ring)
		ripple_foam += max(0.0, ring) * env * life_fade * ripple_params[i].z;
	}

	base_color.rgb = clamp(base_color.rgb + ripple_brightness, 0.0, 1.0);
	foam += clamp(ripple_foam, 0.0, 1.0);
	foam  = clamp(foam, 0.0, 1.0);

	// ── Edge fade (soft shoreline transparency) ───────────────────────────────
	float edge = smoothstep(0.0, edge_softness, thickness);

	// ── Final composite ───────────────────────────────────────────────────────
	vec4 final_color = mix(base_color, foam_color, foam);
	final_color.rgb  = clamp(final_color.rgb, 0.0, 1.0);

	ALBEDO = final_color.rgb;
	ALPHA  = final_color.a * edge;
}
