shader_type spatial;
// Logo recortado pelo alfa (letreiro vazado), cor sólida.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D logo : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform float emission_strength = 0.0;

void fragment() {
	float a = texture(logo, UV).a;
	ALBEDO = tint.rgb;
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.35;
	SPECULAR = 0.5;
	EMISSION = tint.rgb * emission_strength;
}
