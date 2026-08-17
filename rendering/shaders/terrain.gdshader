shader_type spatial;
render_mode diffuse_lambert;

varying vec3 world_pos;
varying vec4 v_color;

const vec3 grass_colors[7] = vec3[](
	vec3(0.329, 0.620, 0.118), // #549e1e  mid grass
	vec3(0.278, 0.549, 0.094), // #478c18  slightly darker
	vec3(0.388, 0.678, 0.149), // #63ad26  bright patch
	vec3(0.251, 0.490, 0.082), // #407d15  deep meadow
	vec3(0.420, 0.710, 0.165), // #6bb52a  lush highlight
	vec3(0.298, 0.580, 0.110), // #4c9420  cool green
	vec3(0.357, 0.647, 0.133)  // #5ba522  neutral mid
);

const vec3 dirt_colors[4] = vec3[](
	vec3(0.545, 0.369, 0.235), // #8b5e3c
	vec3(0.478, 0.314, 0.188), // #7a5030
	vec3(0.604, 0.416, 0.282), // #9a6a48
	vec3(0.431, 0.267, 0.157)  // #6e4428
);

const vec3 sand_colors[3] = vec3[](
	vec3(0.831, 0.710, 0.353), // #d4b55a
	vec3(0.902, 0.784, 0.416), // #e6c86a
	vec3(0.784, 0.659, 0.282)  // #c8a848
);

// Rock: 3 depth-strata variants + top highlight + side
const vec3 rock_top  = vec3(0.533, 0.533, 0.565); // #888890
const vec3 rock_side = vec3(0.486, 0.486, 0.518); // #7c7c84
const vec3 rock_colors[3] = vec3[](
	vec3(0.580, 0.580, 0.612), // #94949c
	vec3(0.439, 0.439, 0.471), // #707078
	vec3(0.350, 0.350, 0.380)  // Darker fallback
);
const vec3 snow_color = vec3(0.930, 0.930, 0.940);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// 2D Value Noise for smooth, clustered color patches
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Large-scale meadow blend for flat plains
// Returns 0.0 = Lime Green, 1.0 = Yellowish Green
float meadow_blend(vec2 world_xz) {
	vec2 p = world_xz * 0.012; // Very low frequency = large sweeping colour patches
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_color = COLOR; // Read from vertex color
}

void fragment() {
	// Decode biome, height, face type, and cliff drop from vertex color
	float biome  = round(v_color.r * 4.0); // 0=Grass, 1=Sand, 2=Rock, 3=Snow
	float norm_y = v_color.g; // surface_y / 12.0
	bool  is_top = v_color.b > 0.5; // 1.0 = top, 0.0 = side
	float cliff  = v_color.a; // drop depth (normalized for side stratification)

	vec3 albedo;
	
	// Snap to block grid (TILE_SIZE = 3.0) — ensures entire voxel face is one solid color
	vec2 block_id = floor(world_pos.xz / 3.0);
	
	// Sample value noise using block coordinates (not world coords)
	// so each block gets a stable unique value regardless of tile size
	float patch_val = noise(block_id * 0.25);

	if (is_top) {
		// Top face - color determined by biome
		if (biome < 0.5) {
			// Grass: blend individual per-block patch variation
			// with a large-scale meadow gradient for a beautiful meadow look.
			int base_idx = int(patch_val * 6.99); // 0 to 6 per-block variation
			
			// Meadow blend using block_id — large sweeping patches between lush/dry grass
			float mblend = noise(block_id * 0.04);
			vec3 lush_col = mix(grass_colors[0], grass_colors[6], patch_val);
			vec3 dry_col  = mix(grass_colors[3], grass_colors[1], patch_val);
			albedo = mix(lush_col, dry_col, mblend);
		} else if (biome < 1.5) {
			int idx = int(patch_val * 2.99); // 0 to 2
			albedo = sand_colors[idx];
		} else if (biome < 2.5) {
			albedo = rock_top;
		} else {
			albedo = snow_color;
		}
	} else {
		// Side face - strata based on depth from the top of the block column
		float dist_from_top = v_color.g - world_pos.y;
		
		// ─── SIDE faces ───
		// Stratified bands — thresholds are in world Y units, not block units
		int dirt_idx = int(patch_val * 3.99);
		if (dist_from_top < 0.4) {
			// Top sliver — matches surface type (grass shows dirt on side)
			if (biome > 2.5) albedo = snow_color;
			else if (biome > 1.5) albedo = rock_colors[0];
			else if (biome > 0.5) albedo = sand_colors[0];
			else albedo = dirt_colors[dirt_idx];
		} else {
			// Deep stratum — always rock/dirt mix
			albedo = mix(dirt_colors[dirt_idx], rock_colors[1], clamp((dist_from_top - 0.4) * 0.5, 0.0, 1.0));
		}
		
	}

	// Ambient occlusion (darken crevices)
	float ao = clamp(0.78 + v_color.g * 0.04, 0.5, 1.0);
	albedo *= ao;

	// ── Underwater override ────────────────────────────────────────────────────
	// Any block below the water surface becomes sand / wet-sand,
	// then gets a sky-blue depth tint on top.
	const float WATER_Y = 0.45;
	if (world_pos.y < WATER_Y) {
		// Replace color: top face → sand, side face → darker sandy dirt
		int sand_idx = int(patch_val * 2.99);
		if (is_top) {
			albedo = sand_colors[sand_idx];
		} else {
			// Sides: blend sand with dirt for a wet-sand look
			int dirt_idx = int(patch_val * 3.99);
			albedo = mix(sand_colors[sand_idx], dirt_colors[dirt_idx], 0.5);
		}

		// Depth darkening: deeper = darker
		float depth_factor = clamp(1.0 + (world_pos.y - WATER_Y) * 0.20, 0.30, 1.0);
		albedo *= depth_factor;

		// Subtle blue tint — keeps sand visible but underwater
		float tint_strength = clamp(0.20 - world_pos.y * 0.08, 0.10, 0.35);
		albedo = mix(albedo, vec3(0.15, 0.45, 0.75), tint_strength);

		// ── Caustic shimmer (top faces near surface only) ──────────────────────
		// Slow dappled light like sunlight refracted through the water surface.
		// Only on top faces within 2 units of the surface, never overpowers depth.
		if (is_top) {
			float depth_below  = WATER_Y - world_pos.y;
			float shallow_mask = 1.0 - smoothstep(0.0, 2.0, depth_below);
			if (shallow_mask > 0.001) {
				vec2 c1 = world_pos.xz * 0.4  + vec2( TIME * 0.06,  TIME * 0.04);
				vec2 c2 = world_pos.xz * 0.55 + vec2(-TIME * 0.05,  TIME * 0.07);
				float cn1    = noise(c1);
				float cn2    = noise(c2);
				float caustic = smoothstep(0.25, 0.75, cn1 * cn2);
				// Cap: caustic can brighten but never exceed the pre-depth-darkened level
				float max_add = (1.0 / depth_factor - 1.0) * length(albedo);
				albedo += caustic * shallow_mask * min(0.07, max_add);
			}
		}
	}

	ALBEDO = albedo;
}
