class_name ItemIcon
extends Control
## Ícone vetorial do item (desenhado com _draw, estilo arredondado com contorno escuro, sem texto):
## escudo (bolha), foguete, banana e turbo (nitro com chama). Ao trocar de item, faz um "pop" rápido.

const OUTLINE := Color(0.03, 0.04, 0.2)

var item: int = Kart.Item.NONE:
	set(v):
		if v != item:
			item = v
			queue_redraw()
			if v != Kart.Item.NONE:
				_pop()


func _pop() -> void:
	pivot_offset = size * 0.5
	scale = Vector2(0.4, 0.4)
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.25)


## Pontos de um círculo/elipse.
static func _ellipse(c: Vector2, rx: float, ry: float, n: int = 28, a0: float = 0.0, a1: float = TAU) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := lerpf(a0, a1, float(i) / float(n if is_equal_approx(a1 - a0, TAU) else n - 1))
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func _xf(pts: PackedVector2Array, xf: Transform2D) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(xf * p)
	return out


func _shape(pts: PackedVector2Array, fill: Color, outline_w: float = 4.0) -> void:
	draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, OUTLINE, outline_w, true)


func _draw() -> void:
	if item == Kart.Item.NONE:
		return
	# Desenha num quadro 100x100 centrado.
	var s := minf(size.x, size.y) / 100.0
	var base := Transform2D(0.0, Vector2(s, s), 0.0, (size - Vector2(100, 100) * s) * 0.5)
	var ow := maxf(3.0, 4.5 * s)
	match item:
		Kart.Item.SHIELD:
			_shape(_xf(_ellipse(Vector2(50, 50), 42, 42, 40), base), Color(0.55, 0.85, 1.0, 0.75), ow)
			var sh := PackedVector2Array([Vector2(50, 24), Vector2(71, 32), Vector2(69, 57), Vector2(50, 76), Vector2(31, 57), Vector2(29, 32)])
			_shape(_xf(sh, base), Color(0.1, 0.3, 1.0), ow)
			var inner := PackedVector2Array([Vector2(50, 33), Vector2(62, 38), Vector2(61, 55), Vector2(50, 66), Vector2(39, 55), Vector2(38, 38)])
			draw_colored_polygon(_xf(inner, base), Color(0.45, 0.7, 1.0))
			draw_polyline(_xf(_ellipse(Vector2(50, 50), 33, 33, 12, deg_to_rad(200), deg_to_rad(250)), base), Color(1, 1, 1, 0.9), 5.0 * s, true)
		Kart.Item.ROCKET:
			var rx := base * Transform2D(deg_to_rad(40.0), Vector2(50, 52))
			var flame := _ellipse(Vector2(0, 34), 10, 16, 20)
			_shape(_xf(flame, rx), Color(1.0, 0.55, 0.1), ow)
			draw_colored_polygon(_xf(_ellipse(Vector2(0, 30), 5, 9, 16), rx), Color(1.0, 0.95, 0.4))
			for sx: float in [-1.0, 1.0]:
				_shape(_xf(PackedVector2Array([Vector2(sx * 10, 6), Vector2(sx * 22, 24), Vector2(sx * 8, 22)]), rx), Color(0.9, 0.12, 0.1), ow)
			var body := PackedVector2Array([Vector2(-11, -18), Vector2(11, -18), Vector2(11, 20), Vector2(6, 25), Vector2(-6, 25), Vector2(-11, 20)])
			_shape(_xf(body, rx), Color(0.96, 0.96, 1.0), ow)
			_shape(_xf(PackedVector2Array([Vector2(-11, -18), Vector2(0, -42), Vector2(11, -18)]), rx), Color(0.9, 0.12, 0.1), ow)
			_shape(_xf(_ellipse(Vector2(0, -4), 5.5, 5.5, 16), rx), Color(0.2, 0.55, 1.0), ow * 0.7)
		Kart.Item.BANANA:
			var bx := base * Transform2D(deg_to_rad(-18.0), Vector2(50, 40))
			var outer := _ellipse(Vector2(0, -4), 40, 38, 22, deg_to_rad(18), deg_to_rad(162))
			var inner2 := _ellipse(Vector2(0, -16), 30, 30, 22, deg_to_rad(162), deg_to_rad(18))
			var cres := PackedVector2Array()
			cres.append_array(outer)
			cres.append_array(inner2)
			_shape(_xf(cres, bx), Color(1.0, 0.86, 0.15), ow)
			draw_polyline(_xf(_ellipse(Vector2(0, -8), 34, 33, 16, deg_to_rad(40), deg_to_rad(140)), bx), Color(1.0, 0.97, 0.6), 3.0 * s, true)
			_shape(_xf(_ellipse(Vector2(-37, 7), 5, 5, 10), bx), Color(0.4, 0.26, 0.08), ow * 0.7)
			_shape(_xf(_ellipse(Vector2(37, 7), 5, 5, 10), bx), Color(0.4, 0.26, 0.08), ow * 0.7)
		Kart.Item.PULSE:
			# Pulso UNIFEOB: disco azul com ondas magenta e um raio amarelo.
			_shape(_xf(_ellipse(Vector2(50, 50), 40, 40, 40), base), Color(0.0, 0.1, 1.0), ow)
			for r: float in [30.0, 20.0]:
				draw_polyline(_xf(_ellipse(Vector2(50, 50), r, r, 24, deg_to_rad(-60), deg_to_rad(240)), base), Color(1.0, 0.1, 0.39, 0.95), 4.0 * s, true)
			var bolt := PackedVector2Array([Vector2(56, 14), Vector2(34, 54), Vector2(48, 54), Vector2(40, 86), Vector2(68, 42), Vector2(53, 42), Vector2(64, 14)])
			_shape(_xf(bolt, base), Color(1.0, 0.92, 0.2), ow)
			draw_polyline(_xf(PackedVector2Array([Vector2(57, 20), Vector2(42, 49)]), base), Color(1, 1, 1, 0.85), 3.0 * s, true)
		Kart.Item.TURBO:
			var tx := base * Transform2D(deg_to_rad(-25.0), Vector2(48, 50))
			var fl := PackedVector2Array([Vector2(-12, 26), Vector2(-20, 46), Vector2(-6, 38), Vector2(0, 52), Vector2(6, 38), Vector2(20, 46), Vector2(12, 26)])
			_shape(_xf(fl, tx), Color(1.0, 0.5, 0.08), ow)
			draw_colored_polygon(_xf(PackedVector2Array([Vector2(-7, 26), Vector2(0, 42), Vector2(7, 26)]), tx), Color(1.0, 0.93, 0.35))
			var can := _ellipse(Vector2(0, -20), 14, 7, 12, PI, TAU)
			can.append_array(_ellipse(Vector2(0, 26), 14, 7, 12, 0.0, PI))
			_shape(_xf(can, tx), Color(0.95, 0.2, 0.15), ow)
			draw_colored_polygon(_xf(PackedVector2Array([Vector2(-14, -2), Vector2(14, -2), Vector2(14, 8), Vector2(-14, 8)]), tx), Color(1, 1, 1))
			_shape(_xf(PackedVector2Array([Vector2(-6, -36), Vector2(6, -36), Vector2(6, -25), Vector2(-6, -25)]), tx), Color(0.7, 0.72, 0.78), ow)
			draw_polyline(_xf(PackedVector2Array([Vector2(-8, -15), Vector2(-8, 18)]), tx), Color(1, 1, 1, 0.6), 3.0 * s, true)
