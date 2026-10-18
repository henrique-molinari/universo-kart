shader_type canvas_item;
// Fundo "universo" da abertura: degradê azul UNIFEOB, nebulosa magenta suave nas bordas,
// estrelas em duas camadas cintilando e vinheta.
uniform vec4 center_col : source_color = vec4(0.0, 0.1, 0.85, 1.0);
uniform vec4 edge_col : source_color = vec4(0.0, 0.01, 0.12, 1.0);
uniform vec4 nebula_col : source_color = vec4(0.55, 0.02, 0.3, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 asp = vec2(16.0 / 9.0, 1.0);
	vec2 p = (UV - 0.5) * asp;
	float r = length(p);
	vec3 col = mix(center_col.rgb, edge_col.rgb, smoothstep(0.0, 0.95, r));
	float neb = sin(p.x * 3.1 + TIME * 0.05) * sin(p.y * 4.3 - 1.2 + TIME * 0.03) * 0.5 + 0.5;
	col += nebula_col.rgb * pow(neb, 3.0) * 0.35 * smoothstep(0.25, 0.95, r);
	for (int l = 0; l < 2; l++) {
		float sc = l == 0 ? 70.0 : 180.0;
		vec2 g = UV * asp * sc;
		vec2 id = floor(g);
		vec2 f = fract(g) - 0.5;
		float h = hash(id + float(l) * 17.0);
		if (h > 0.96) {
			vec2 o = vec2(hash(id + 3.1), hash(id + 7.7)) - 0.5;
			float d = length(f - o * 0.6);
			float tw = 0.55 + 0.45 * sin(TIME * 2.2 + h * 60.0);
			float size = l == 0 ? 0.14 : 0.09;
			col += vec3(1.0, 0.97, 0.85) * smoothstep(size, 0.0, d) * tw * (l == 0 ? 0.9 : 0.55) * smoothstep(0.08, 0.4, r);
		}
	}
	col *= 1.0 - smoothstep(0.55, 1.15, r) * 0.45;
	COLOR = vec4(col, 1.0);
}
