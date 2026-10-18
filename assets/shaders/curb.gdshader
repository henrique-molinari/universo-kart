shader_type spatial;
// Zebras listradas (UV.y = metros ao longo da borda, UV.x = 0 interno .. 1 externo).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 color_a : source_color = vec4(1.0, 0.094, 0.388, 1.0);
uniform vec4 color_b : source_color = vec4(0.96, 0.965, 1.0, 1.0);
uniform float stripe_length = 2.0;
uniform sampler2D noise_grain : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float s = UV.y / stripe_length;
	float tri = abs(fract(s) - 0.5) * 2.0;
	float w = max(fwidth(s) * 2.0, 0.001);
	float t = smoothstep(0.5 - w, 0.5 + w, tri);
	vec3 col = mix(color_a.rgb, color_b.rgb, t);
	float g = texture(noise_grain, world_pos.xz * 0.6).r;
	col *= 0.9 + 0.12 * g;
	// Sujeira leve na borda interna.
	col *= mix(0.82, 1.0, smoothstep(0.0, 0.25, UV.x));
	ALBEDO = col;
	ROUGHNESS = 0.45 + g * 0.15;
	SPECULAR = 0.45;
}
