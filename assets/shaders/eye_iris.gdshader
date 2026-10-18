shader_type spatial;
// Íris do ET (cor por vértice): fosca, com leve brilho próprio para "acender" no fundo do olho.
render_mode specular_schlick_ggx;

uniform float glow = 0.3;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.5;
	SPECULAR = 0.2;
	EMISSION = COLOR.rgb * glow;
}
