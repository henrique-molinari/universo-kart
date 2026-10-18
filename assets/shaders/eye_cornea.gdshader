shader_type spatial;
// Córnea do olho do ET: casca de vidro escuro sobre a íris. Quase transparente de frente (vê-se a
// íris funda, com paralaxe real) e espelhada nas bordas (fresnel), com reflexo nítido do ambiente.
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.01, 0.012, 0.016);
uniform float alpha_front = 0.2;
uniform float alpha_edge = 0.97;

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	ALBEDO = tint;
	ROUGHNESS = 0.02;
	SPECULAR = 1.0;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.0;
	ALPHA = mix(alpha_front, alpha_edge, f);
}
