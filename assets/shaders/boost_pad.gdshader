shader_type spatial;
render_mode unshaded, cull_disabled;
// Faixa de turbo: setas (chevrons) emissivas rolando no sentido da corrida (UV.y = comprimento).

uniform vec4 base_color : source_color = vec4(0.05, 0.08, 0.35, 1.0);
uniform vec4 arrow_color : source_color = vec4(1.0, 0.75, 0.1, 1.0);
uniform vec4 edge_color : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform float arrows = 5.0;
uniform float speed = 1.6;
uniform float glow = 2.2;

void fragment() {
	vec2 uv = UV;
	float x = abs(uv.x - 0.5) * 2.0;
	float v = fract(uv.y * arrows + TIME * speed);
	float chevron = v - x * 0.35;
	float a = smoothstep(0.30, 0.36, chevron) * (1.0 - smoothstep(0.62, 0.68, chevron));
	a *= step(x, 0.8);
	float edge = smoothstep(0.86, 0.92, x);
	vec3 col = mix(base_color.rgb, arrow_color.rgb * glow, a);
	col = mix(col, edge_color.rgb * glow, edge);
	ALBEDO = col;
}
