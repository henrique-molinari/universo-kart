shader_type spatial;
// Público estilizado (MultiMesh). COLOR.a do vértice = 1 corpo, 0 cabeça.
// INSTANCE_CUSTOM.rgb = cor da camiseta, .a = fase da animação (também sorteia o tom de pele).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

uniform float excitement = 0.35;
uniform float bounce_speed = 5.5;
uniform vec4 skin_light : source_color = vec4(0.96, 0.8, 0.66, 1.0);
uniform vec4 skin_dark : source_color = vec4(0.42, 0.27, 0.18, 1.0);

varying float body;
varying vec3 shirt;
varying float skin_t;
varying float ao;

vec3 srgb_to_linear(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	body = COLOR.a;
	ao = COLOR.r;
	shirt = srgb_to_linear(INSTANCE_CUSTOM.rgb);
	skin_t = fract(INSTANCE_CUSTOM.a * 7.13);
	float phase = INSTANCE_CUSTOM.a * 6.2831;
	float b = abs(sin(TIME * bounce_speed + phase));
	VERTEX.y += b * 0.12 * excitement;
	// Braços/ombros balançando (topo do corpo).
	VERTEX.x += sin(TIME * bounce_speed * 0.5 + phase) * 0.04 * excitement * smoothstep(0.3, 0.9, VERTEX.y);
}

void fragment() {
	vec3 skin = mix(skin_light.rgb, skin_dark.rgb, skin_t);
	ALBEDO = mix(skin, shirt, body) * mix(0.55, 1.0, ao);
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
}
