shader_type spatial;
// Cúpula perolada do planetário: gomos (meridianos), anéis de latitude, reflexo iridescente.
// UV.x = longitude (0..1), UV.y = latitude (0 no topo, 0.5 no equador).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 pearl : source_color = vec4(0.95, 0.95, 1.0, 1.0);
uniform vec4 tint_a : source_color = vec4(0.84, 0.86, 1.0, 1.0);
uniform vec4 tint_b : source_color = vec4(1.0, 0.86, 0.94, 1.0);
uniform vec4 seam : source_color = vec4(0.0, 0.094, 0.996, 1.0);
uniform float gores = 24.0;
uniform float rings = 7.0;

void fragment() {
	float u = UV.x * gores;
	float v = UV.y * 2.0 * rings;
	float au = fwidth(u) * 1.2;
	float av = fwidth(v) * 1.2;
	float gu = abs(fract(u) - 0.5) * 2.0;
	float gv = abs(fract(v) - 0.5) * 2.0;
	float line_u = smoothstep(1.0 - 0.06 - au, 1.0 - 0.06 + au, gu) * smoothstep(0.02, 0.1, UV.y);
	float line_v = smoothstep(1.0 - 0.05 - av, 1.0 - 0.05 + av, gv);
	float lines = max(line_u, line_v);
	// Painéis levemente abaulados: variação de brilho por gomo.
	float panel = 0.95 + 0.05 * sin(fract(u) * 3.14159);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	vec3 col = pearl.rgb * panel;
	col = mix(col, mix(tint_a.rgb, tint_b.rgb, 0.5 + 0.5 * sin(UV.x * 12.566 + UV.y * 6.0)), fres * 0.6);
	col = mix(col, seam.rgb, lines * 0.85);
	ALBEDO = col;
	METALLIC = mix(0.35, 0.1, lines);
	ROUGHNESS = mix(0.22, 0.5, lines);
	SPECULAR = 0.7;
}
