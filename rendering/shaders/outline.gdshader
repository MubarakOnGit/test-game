shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture,           filter_nearest;
uniform sampler2D DEPTH_TEXTURE  : hint_depth_texture,            filter_nearest;
uniform sampler2D NORMAL_TEXTURE : hint_normal_roughness_texture, filter_nearest;

uniform vec4  outline_color     : source_color = vec4(0.0, 0.0, 0.0, 0.82);
uniform float outline_thickness : hint_range(0.5, 3.0, 0.5) = 1.0;
uniform float depth_threshold   : hint_range(0.0, 2.0, 0.05) = 0.05;
uniform float normal_threshold  : hint_range(0.0, 2.0, 0.05) = 0.5;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 uv  = SCREEN_UV;
	vec3 original = texture(SCREEN_TEXTURE, uv).rgb;

	vec2 px = outline_thickness / vec2(textureSize(SCREEN_TEXTURE, 0));

	// 8-point sampling
	vec2 dirs[8] = {
		vec2(-px.x, -px.y), vec2(0.0, -px.y), vec2(px.x, -px.y),
		vec2(-px.x,  0.0),                    vec2(px.x,  0.0),
		vec2(-px.x,  px.y), vec2(0.0,  px.y), vec2(px.x,  px.y)
	};

	// ── Depth edges ───────────────────────────────────────────────────────────
	float dc = texture(DEPTH_TEXTURE, uv).r;
	float depth_diff = 0.0;
	for (int i = 0; i < 8; i++) {
		depth_diff = max(depth_diff, abs(dc - texture(DEPTH_TEXTURE, uv + dirs[i]).r));
	}

	// ── Normal edges ──────────────────────────────────────────────────────────
	vec3 nc = texture(NORMAL_TEXTURE, uv).rgb;
	float normal_diff = 0.0;
	for (int i = 0; i < 8; i++) {
		normal_diff = max(normal_diff, distance(nc, texture(NORMAL_TEXTURE, uv + dirs[i]).rgb));
	}

	bool is_edge = (depth_diff > depth_threshold) || (normal_diff > normal_threshold);

	if (is_edge) {
		ALBEDO = mix(original, outline_color.rgb, outline_color.a);
	} else {
		ALBEDO = original;
	}
}
