shader_type spatial;
render_mode diffuse_lambert;

uniform vec4 grass_color : source_color;
uniform vec4 dirt_color : source_color;
uniform vec4 rock_color : source_color;
uniform vec4 sand_color : source_color;
uniform vec4 snow_color : source_color;
uniform float surface_y;
uniform float neighbor_n;
uniform float neighbor_s;
uniform float neighbor_e;
uniform float neighbor_w;
uniform bool is_sand;
uniform bool is_rock;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	
	vec3 albedo;
	float dist_from_top = surface_y - world_pos.y;
	
	// ─── TOP face ───
	if (world_normal.y > 0.5) {
		if (surface_y >= 5.0) {
			albedo = snow_color.rgb;
		} else if (surface_y >= 4.0 || is_rock) {
			albedo = rock_color.rgb;
		} else if (is_sand) {
			albedo = sand_color.rgb;
		} else {
			albedo = grass_color.rgb;
		}
	}
	// ─── BOTTOM face ───
	else if (world_normal.y < -0.5) {
		albedo = rock_color.rgb * 0.2;
	}
	// ─── SIDE faces ───
	else {
		float neighbor_y = surface_y;
		bool has_neighbor = true;
		
		if (world_normal.z < -0.5) { 
			neighbor_y = neighbor_n; has_neighbor = neighbor_n > -500.0; 
		} else if (world_normal.z > 0.5) { 
			neighbor_y = neighbor_s; has_neighbor = neighbor_s > -500.0; 
		} else if (world_normal.x > 0.5) { 
			neighbor_y = neighbor_e; has_neighbor = neighbor_e > -500.0; 
		} else if (world_normal.x < -0.5) { 
			neighbor_y = neighbor_w; has_neighbor = neighbor_w > -500.0; 
		}
		
		float drop = surface_y - neighbor_y;
		// A cliff is when neighbor is lower, or neighbor is missing entirely (water edge)
		bool is_cliff = drop > 0.1 || !has_neighbor;
		
		if (is_cliff) {
			// Stratified bands
			if (dist_from_top < 0.12) {
				// Top sliver matches surface type
				if (surface_y >= 5.0) albedo = snow_color.rgb;
				else if (surface_y >= 4.0 || is_rock) albedo = rock_color.rgb;
				else if (is_sand) albedo = sand_color.rgb;
				else albedo = grass_color.rgb;
			} else if (dist_from_top < 0.85) {
				albedo = dirt_color.rgb;
			} else {
				albedo = rock_color.rgb;
			}
		} else {
			// Hidden face between same-height tiles
			albedo = dirt_color.rgb * 0.3;
		}
	}
	
	// Ambient occlusion
	float ao = clamp(0.78 + world_pos.y * 0.04, 0.5, 1.0);
	albedo *= ao;
	
	// Underwater darkening and blue tint (water plane is at 0.5)
	if (world_pos.y < 0.5) {
		float depth_factor = clamp(1.0 + world_pos.y * 0.15, 0.2, 1.0);
		albedo *= depth_factor;
		albedo = mix(albedo, vec3(0.1, 0.3, 0.6), 0.3);
	}
	
	ALBEDO = albedo;
}
