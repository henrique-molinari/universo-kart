shader_type canvas_item;
// Recolore uma arte monocromática (ex.: logo) usando apenas o canal alfa.
uniform vec4 tint : source_color = vec4(1.0);
uniform bool keep_original = false;

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	COLOR = keep_original ? t : vec4(tint.rgb, t.a * tint.a);
}
