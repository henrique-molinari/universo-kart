shader_type canvas_item;
// Fundo sóbrio: gradiente radial dessaturado + listras diagonais de baixíssimo contraste.
uniform vec4 center_color : source_color = vec4(0.17, 0.18, 0.23, 1.0);
uniform vec4 edge_color : source_color = vec4(0.055, 0.06, 0.08, 1.0);
uniform float stripe_px = 46.0;
uniform float stripe_alpha = 0.018;

void fragment() {
	float d = distance(UV, vec2(0.5, 0.42));
	vec3 c = mix(center_color.rgb, edge_color.rgb, smoothstep(0.0, 0.85, d));
	float s = step(0.5, fract((FRAGCOORD.x + FRAGCOORD.y) / stripe_px));
	c += vec3(stripe_alpha) * s;
	COLOR = vec4(c, 1.0);
}
