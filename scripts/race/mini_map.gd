class_name MiniMap
extends Control
## Minimapa do HUD (canto superior direito de cada tela): traçado da pista visto de cima (norte = -Z),
## linha de chegada e a cabeça de cada personagem na posição do seu kart (ET verde, ET rosa com laço,
## capacete de cada piloto nas cores dele), com anel na cor do kart. O próprio corredor fica por cima,
## maior e com anel branco.

const SAMPLES := 220
const PAD := 28.0
const HEAD_R := 15.0

var me: Kart
var karts: Array[Kart] = []
var _pts := PackedVector2Array()     ## traçado em coordenadas do mundo (x, z)
var _start := PackedVector2Array()   ## linha de chegada (2 pontos, mundo)
var _bounds := Rect2()


func setup(tp: TrackPath, all_karts: Array[Kart], own: Kart) -> void:
	me = own
	karts = all_karts
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pts.clear()
	for i in SAMPLES:
		var p := tp.to_world(tp.length * float(i) / SAMPLES, 0.0)
		_pts.append(Vector2(p.x, p.z))
	_pts.append(_pts[0])
	var fwd := tp.get_forward(0.0)
	var side := Vector2(-fwd.z, fwd.x).normalized() * 9.0
	_start = PackedVector2Array([_pts[0] - side, _pts[0] + side])
	_bounds = Rect2(_pts[0], Vector2.ZERO)
	for p in _pts:
		_bounds = _bounds.expand(p)


func _process(_delta: float) -> void:
	queue_redraw()


func _to_map(w: Vector2) -> Vector2:
	var avail := size - Vector2(PAD, PAD) * 2.0
	var sc := minf(avail.x / maxf(_bounds.size.x, 1.0), avail.y / maxf(_bounds.size.y, 1.0))
	var off := (size - _bounds.size * sc) * 0.5
	return off + (w - _bounds.position) * sc


func _draw() -> void:
	if _pts.is_empty():
		return
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.05, 0.25, 0.55)
	bg.border_color = Color(1, 1, 1, 0.65)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(16)
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	var line := PackedVector2Array()
	for p in _pts:
		line.append(_to_map(p))
	draw_polyline(line, Color(0.02, 0.03, 0.15, 0.9), 11.0, true)
	draw_polyline(line, Color(0.85, 0.87, 0.92), 6.0, true)
	var a := _to_map(_start[0])
	var b := _to_map(_start[1])
	draw_line(a, b, Color(0.02, 0.03, 0.15), 6.0, true)
	draw_line(a, b, Palette.YELLOW, 3.0, true)
	for k in karts:
		if k != me and is_instance_valid(k):
			_draw_racer(k, HEAD_R, false)
	if is_instance_valid(me):
		_draw_racer(me, HEAD_R * 1.25, true)


func _draw_racer(k: Kart, r: float, own: bool) -> void:
	var c := _to_map(Vector2(k.global_position.x, k.global_position.z))
	var ring := Palette.WHITE if own else k.config.kart_color
	draw_circle(c + Vector2(1.5, 2.0), r + 3.5, Color(0, 0, 0, 0.35))
	draw_circle(c, r + 3.0, Color(0.02, 0.03, 0.15))
	draw_circle(c, r + 2.0, ring)
	draw_head(self, c, r, k.model.character)


## Cabeça do personagem `char_id` desenhada em vetor (centro `c`, raio ~`r`).
static func draw_head(ci: CanvasItem, c: Vector2, r: float, char_id: int) -> void:
	if Characters.is_astronaut(char_id):
		# Capacete branco com viseira dourada e emblema azul.
		ci.draw_circle(c, r, AstronautDriver.SCHEME["helmet"])
		_ellipse(ci, c + Vector2(0, r * 0.1), Vector2(r * 0.72, r * 0.5), 0.0, Color(0.95, 0.68, 0.22))
		ci.draw_circle(c + Vector2(-r * 0.25, -r * 0.05), r * 0.12, Color(1, 1, 1, 0.8))
		return
	if Characters.is_pilot(char_id):
		_draw_helmet(ci, c, r, PilotDriver.scheme_of(char_id))
		return
	var skin: Color = AlienDriver.SKIN_COLORS[clampi(char_id, 0, AlienDriver.SKIN_COLORS.size() - 1)]
	# Crânio redondo que afina num queixo pequeno (como o modelo).
	var poly := PackedVector2Array()
	for i in 28:
		var t := TAU * float(i) / 28.0
		var yn := -cos(t)
		var w := lerpf(1.0, 0.68, smoothstep(0.0, 1.0, yn))
		poly.append(c + Vector2(sin(t) * r * w, yn * r * 1.05))
	ci.draw_colored_polygon(poly, skin)
	# Olhos pretos grandes em amêndoa, inclinados, com brilho.
	for s: float in [-1.0, 1.0]:
		var e := c + Vector2(s * r * 0.4, r * 0.05)
		_ellipse(ci, e, Vector2(r * 0.36, r * 0.24), s * 0.35, Color(0.02, 0.02, 0.03))
		ci.draw_circle(e + Vector2(-s * r * 0.08, -r * 0.06), r * 0.07, Color(1, 1, 1, 0.9))
	if char_id == AlienDriver.Character.TURISTA:
		# Laço vermelho no alto da cabeça.
		var bc := c + Vector2(r * 0.45, -r * 0.82)
		var red := Color(0.9, 0.06, 0.2)
		_ellipse(ci, bc + Vector2(-r * 0.22, 0), Vector2(r * 0.24, r * 0.16), 0.3, red)
		_ellipse(ci, bc + Vector2(r * 0.22, 0), Vector2(r * 0.24, r * 0.16), -0.3, red)
		ci.draw_circle(bc, r * 0.11, red.darkened(0.15))


static func _draw_helmet(ci: CanvasItem, c: Vector2, r: float, sch: Dictionary) -> void:
	ci.draw_circle(c, r, sch["helmet"])
	var top := -r * 0.2   # a faixa vai do alto do capacete até a viseira
	if sch["rainbow"]:
		var n := PilotDriver.RAINBOW.size()
		for i in n:
			var x0 := lerpf(-r, r, float(i) / n)
			var x1 := lerpf(-r, r, float(i + 1) / n)
			_band(ci, c, r, x0, x1, r * 0.95, PilotDriver.RAINBOW[i])
	else:
		_band(ci, c, r, -r * 0.3, r * 0.3, top, sch["accent"])
		_band(ci, c, r, -r * 0.2, r * 0.2, top, sch["stripe"])
	# Viseira escura com reflexo.
	_ellipse(ci, c + Vector2(0, r * 0.18), Vector2(r * 0.8, r * 0.36), 0.0, Color(0.04, 0.05, 0.08))
	_ellipse(ci, c + Vector2(-r * 0.3, r * 0.08), Vector2(r * 0.22, r * 0.07), -0.2, Color(1, 1, 1, 0.75))


## Faixa vertical (x0..x1) dentro do círculo, do topo até y_bottom (relativo ao centro).
static func _band(ci: CanvasItem, c: Vector2, r: float, x0: float, x1: float, y_bottom: float, col: Color) -> void:
	var poly := PackedVector2Array()
	var steps := 6
	for i in steps + 1:
		var x := lerpf(x0, x1, float(i) / steps)
		poly.append(c + Vector2(x, -sqrt(maxf(r * r - x * x, 0.0))))
	for x: float in [x1, x0]:
		var yb := minf(y_bottom, sqrt(maxf(r * r - x * x, 0.0)))
		poly.append(c + Vector2(x, yb))
	ci.draw_colored_polygon(poly, col)


static func _ellipse(ci: CanvasItem, c: Vector2, radii: Vector2, rot: float, col: Color) -> void:
	var poly := PackedVector2Array()
	for i in 20:
		var t := TAU * float(i) / 20.0
		poly.append(c + Vector2(cos(t) * radii.x, sin(t) * radii.y).rotated(rot))
	ci.draw_colored_polygon(poly, col)
