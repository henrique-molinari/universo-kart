class_name ItemIcon
extends Control
## Ícone do item na HUD: o modelo 3D pré-renderizado do item (ItemIcons3D), sobre um halo suave na cor
## do item, com um reflexo de brilho que atravessa o ícone (ao receber o item e, depois, a cada poucos
## segundos). Ao trocar de item, faz um "pop" rápido.

const SHINE_CODE := """
shader_type canvas_item;
uniform float shine = -1.0;   // posição da faixa de brilho (-0.5..1.5); fora disso, sem brilho
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float d = (UV.x + UV.y) * 0.5 - shine;
	float band = exp(-d * d * 260.0) * step(0.6, c.a);
	c.rgb += band * 0.55;
	COLOR = c;
}
"""
const SHINE_EVERY := 3.2

static var _shader: Shader
static var _halo: GradientTexture2D

var item: int = Kart.Item.NONE:
	set(v):
		if v != item:
			item = v
			queue_redraw()
			if v != Kart.Item.NONE:
				_pop()

var _shine_t := 99.0


func _ready() -> void:
	ItemIcons3D.ensure()
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHINE_CODE
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.85))
		g.set_color(1, Color(1, 1, 1, 0.0))
		_halo = GradientTexture2D.new()
		_halo.gradient = g
		_halo.fill = GradientTexture2D.FILL_RADIAL
		_halo.fill_from = Vector2(0.5, 0.5)
		_halo.fill_to = Vector2(1.0, 0.5)
		_halo.width = 128
		_halo.height = 128
	var m := ShaderMaterial.new()
	m.shader = _shader
	material = m


func _pop() -> void:
	pivot_offset = size * 0.5
	scale = Vector2(0.4, 0.4)
	_shine_t = 0.0
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.25)


func _process(delta: float) -> void:
	if item == Kart.Item.NONE:
		return
	_shine_t += delta
	if _shine_t > SHINE_EVERY:
		_shine_t = 0.0
	(material as ShaderMaterial).set_shader_parameter(&"shine", lerpf(-0.5, 1.5, _shine_t / 0.55))
	if ItemIcons3D.texture(item) == null:
		queue_redraw()  # o viewport dos ícones ainda está entrando na árvore


func _draw() -> void:
	if item == Kart.Item.NONE:
		return
	var s := minf(size.x, size.y)
	var r := Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s))
	var hc: Color = Kart.ITEM_COLORS[item]
	hc.a = 0.45
	draw_texture_rect(_halo, r.grow(s * 0.08), false, hc)
	var tex := ItemIcons3D.texture(item)
	if tex != null:
		draw_texture_rect(tex, r.grow(s * 0.06), false)
