shader_type spatial;
// Asfalto estilizado PBR: grão, manchas, marcas de pneu, faixas pintadas,
// linha de largada quadriculada e marcações do grid.
// UV.x = deslocamento lateral (m), UV.y = distância ao longo da pista (m).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 asphalt_dark : source_color = vec4(0.205, 0.2, 0.2, 1.0);
uniform vec4 asphalt_light : source_color = vec4(0.32, 0.31, 0.305, 1.0);
uniform vec4 paint_white : source_color = vec4(0.93, 0.94, 0.97, 1.0);
uniform vec4 paint_accent : source_color = vec4(0.96, 0.906, 0.153, 1.0);
uniform vec4 checker_dark : source_color = vec4(0.07, 0.07, 0.08, 1.0);
uniform float half_width = 9.0;
uniform float track_length = 1000.0;
uniform float dash_period = 8.0;
uniform float grid_first_row = 9.0;
uniform float grid_row_spacing = 6.5;
uniform float grid_lateral = 4.5;
uniform float grid_stagger = 3.0;
uniform int grid_slots = 8;
uniform float pole_side = -1.0;
uniform sampler2D noise_soft : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_grain : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 world_pos;

float band(float x, float a, float b) {
	float w = max(fwidth(x), 0.0005) * 0.75;
	return smoothstep(a - w, a + w, x) - smoothstep(b - w, b + w, x);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float au = abs(u);

	// --- base do asfalto
	float patches = texture(noise_soft, world_pos.xz * 0.012).r;
	float mid = texture(noise_soft, world_pos.xz * 0.07 + vec2(0.37, 0.11)).r;
	float grain = texture(noise_grain, world_pos.xz * 0.45).r;
	vec3 col = mix(asphalt_dark.rgb, asphalt_light.rgb, smoothstep(0.25, 0.8, patches * 0.7 + mid * 0.3));
	col *= 0.82 + 0.36 * grain;

	// --- marcas de pneu (faixas escuras alongadas perto da trajetória ideal)
	float streak = texture(noise_soft, vec2(u * 0.16, v * 0.0045)).r;
	float streak2 = texture(noise_soft, vec2(u * 0.55 + 3.1, v * 0.012)).r;
	float marks = smoothstep(0.58, 0.78, streak) * smoothstep(0.35, 0.7, streak2);
	col *= 1.0 - marks * 0.28 * (1.0 - smoothstep(half_width - 2.5, half_width, au));
	// Asfalto levemente mais claro/gasto nas bordas.
	col = mix(col, col * 1.12, smoothstep(half_width - 2.0, half_width, au) * 0.6);

	float rough = 0.78 - grain * 0.1;
	float paint = 0.0;
	vec3 paint_col = paint_white.rgb;

	// --- faixas de borda (branca) + filete amarelo interno
	float edge = band(au, half_width - 0.75, half_width - 0.3);
	float edge_in = band(au, half_width - 1.05, half_width - 0.9);
	paint = max(paint, edge);
	// --- linha central tracejada
	float dash = step(fract(v / dash_period), 0.45);
	float center = band(u, -0.14, 0.14) * dash;
	paint = max(paint, center);

	// --- linha de largada/chegada (quadriculado 4 fileiras de 0.9 m)
	float d = v;
	if (d > track_length * 0.5) { d -= track_length; }
	float sq = 0.9;
	float in_start = band(d, -1.8, 1.8) * (1.0 - step(half_width - 0.3, au));
	float checker = mod(floor(u / sq) + floor(d / sq), 2.0);
	vec3 start_col = mix(checker_dark.rgb, paint_white.rgb, checker);

	// --- marcações do grid de largada (colchetes brancos)
	float grid_mark = 0.0;
	for (int c = 0; c < 2; c++) {
		float side = (c == 0) ? pole_side : -pole_side;
		float lc = side * grid_lateral;
		float q = -d - grid_first_row - float(c) * grid_stagger;
		float rows = ceil(float(grid_slots) * 0.5);
		if (q > -0.6 && q < (rows - 1.0) * grid_row_spacing + 1.5 && abs(u - lc) < 1.7) {
			float fq = mod(q + 0.6, grid_row_spacing) - 0.6;
			float front = band(fq, -0.6, -0.3) * step(abs(u - lc), 1.6);
			float sides = band(abs(u - lc), 1.3, 1.6) * band(fq, -0.6, 1.4);
			grid_mark = max(grid_mark, max(front, sides));
		}
	}
	paint = max(paint, grid_mark);

	// Tinta com leve desgaste.
	float wear = smoothstep(0.2, 0.55, texture(noise_grain, world_pos.xz * 0.9).r);
	paint *= mix(0.75, 1.0, wear);
	col = mix(col, paint_col, paint);
	col = mix(col, paint_accent.rgb, edge_in * 0.9);
	col = mix(col, start_col, in_start);
	rough = mix(rough, 0.55, max(max(paint, edge_in), in_start));

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	NORMAL_MAP = texture(grain_normal, world_pos.xz * 0.35).rgb;
	NORMAL_MAP_DEPTH = 0.6 * (1.0 - max(paint, in_start) * 0.7);
}
