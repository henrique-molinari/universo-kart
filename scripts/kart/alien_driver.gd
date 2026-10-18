class_name AlienDriver
extends Node3D
## Piloto ET procedural (MeshKit), fiel à referência (images/2.png): ET "chibi" com cabeça enorme em gota
## invertida, olhos pretos gigantes e reflexivos (com brilhos), pele lisa (variação sutil só na cor,
## SSS), sorriso pequeno, olhos em camadas (íris funda com brilho sob uma córnea
## de vidro com fresnel) e traje espacial na cor do ET (SUIT_COLORS): painéis laterais claros com
## filete branco, zíper, cinto/joelheiras/botas em grafite e vincos de tecido reais nas juntas.
## Rosto liso, sem relevos (sobrancelhas, bochechas e nariz só por cor/forma da cabeça).
## Dois personagens:
##   0 "Visitante do Universo": masculino, pele verde.
##   1 "Turista do Universo": feminina, pele rosa, cílios, laço vermelho de bolinhas, blush e lábios rosados.
## Articulado: Rig (pulinhos/postura) -> Body (traje, pernas, pescoço), Head (pivô no pescoço),
## ArmL/R (braço), ForearmL/R (antebraço), HandL/R (mão) -> IndexL/R e MiddleL/R (dedos do "V").
## Os braços usam IK analítico de 2 ossos até o alvo de cada pose (volante / paz e amor / mãos nos joelhos).
## Local: -Z = frente. A geometria é escrita em coordenadas do kart menos ORIGIN.

## Também é a base do PilotDriver (mesmo rig/IK/interface; geometria e comemoração próprias).
## Elenco completo (ETs + pilotos) em Characters.

enum Character { VISITANTE, TURISTA }
enum Pose { DRIVE, VICTORY, DEFEAT }

const NAMES: Array[String] = ["Visitante do Universo", "Turista do Universo"]
const SKIN_COLORS: Array[Color] = [Color(0.36, 0.8, 0.04), Color(1.0, 0.42, 0.66)]
const LED_COLORS: Array[Color] = [Color(0.45, 1.0, 0.7), Color(1.0, 0.45, 0.85)]
## Traje de cada ET (tom mais fechado da pele, para destacar a cabeça).
const SUIT_COLORS: Array[Color] = [Color(0.0, 0.36, 0.07), Color(0.6, 0.06, 0.3)]
## Pintas na cabeça (rentes à pele, sem relevo): direção (x, y, z) na esfera da cabeça e raio; topo, têmporas,
## nuca e sardinhas na testa, longe dos olhos. Na Turista o x é espelhado.
const SPOTS: Array[Vector4] = [
	Vector4(0.0, 0.95, -0.3, 0.16), Vector4(0.32, 0.84, -0.42, 0.1), Vector4(-0.3, 0.87, -0.35, 0.12),
	Vector4(0.55, 0.62, -0.55, 0.08), Vector4(0.86, 0.35, -0.2, 0.13), Vector4(-0.88, 0.32, -0.1, 0.1),
	Vector4(0.8, 0.5, 0.25, 0.1), Vector4(-0.7, 0.6, 0.35, 0.14), Vector4(0.1, 0.75, 0.65, 0.15),
	Vector4(-0.3, 0.45, 0.85, 0.1), Vector4(0.48, 0.3, 0.82, 0.12), Vector4(-0.62, 0.05, 0.75, 0.08),
	Vector4(0.18, 0.56, -0.8, 0.055), Vector4(-0.14, 0.62, -0.77, 0.045), Vector4(0.04, 0.7, -0.71, 0.04),
	Vector4(-0.32, 0.5, -0.8, 0.04),
]
const SPOT_COLORS: Array[Color] = [Color(0.1, 0.34, 0.04), Color(0.82, 0.16, 0.46)]
const IRIS_COLORS: Array[Color] = [Color(0.08, 0.62, 0.58), Color(0.45, 0.1, 0.5)]
const TRIM := Color(0.13, 0.14, 0.16)         ## grafite: cinto, joelheiras, botas, punhos
const PIPING := Color(0.93, 0.94, 0.95)       ## filetes brancos do traje
const CORNEA_SHADER := preload("res://assets/shaders/eye_cornea.gdshader")
const IRIS_SHADER := preload("res://assets/shaders/eye_iris.gdshader")
## Vincos de tecido ao longo de um membro: (t do centro, largura, ângulo do lado mais fundo, peso).
## Concentrados perto das juntas (dobras de cotovelo/joelho) e alguns suaves no meio.
const FOLD_CREASES: Array[Vector4] = [
	Vector4(0.1, 0.03, 0.0, 1.0), Vector4(0.19, 0.035, 2.1, 0.75), Vector4(0.31, 0.05, 4.0, 0.35),
	Vector4(0.7, 0.05, 1.0, 0.35), Vector4(0.81, 0.035, 3.3, 0.8), Vector4(0.9, 0.03, 5.2, 1.0),
]
const ORIGIN := Vector3(0, 0.5, 0.3)          ## posição deste nó no kart (pivô da inclinação)
const HEAD_PIVOT := Vector3(0, 0.96, 0.25)    ## pescoço (coordenadas do kart)
const HEAD_CENTER := Vector3(0, 0.36, -0.01)  ## centro da cabeça em relação ao pivô
const HEAD_R := Vector3(0.33, 0.34, 0.29)
const SHOULDER := Vector3(0.17, 0.83, 0.2)    ## ombro direito (x espelhado no esquerdo)
const L1 := 0.27                              ## braço
const L2 := 0.27                              ## antebraço
const TORSO_TILT := -0.22
const SKIN_NORMAL := preload("res://assets/materials/noise_grain_normal.tres")

var character := 0
var pose: Pose = Pose.DRIVE
var rig: Node3D
var body: MeshInstance3D
var head: Node3D
var arms: Array[Node3D] = []
var forearms: Array[Node3D] = []
var hands: Array[Node3D] = []
var fingers: Array = [[], []]   ## por lado: [indicador, médio]
var v_amount := 0.0              ## 0 = dedos no volante, 1 = "V" aberto
var hop := 0.0                   ## altura atual do pulinho
var head_pitch := 0.0
var wrist_error := 0.0           ## distância do punho ao alvo (IK); testes
var _w := Vector3(1, 0, 0)       ## pesos das poses (volante, vitória, derrota)
var _t := 0.0
var _fx: GPUParticles3D
var _gesture := 0.0              ## tempo restante do gesto de arremesso (uso de item)
const GESTURE_TIME := 0.55


# ------------------------------------------------------------------ materiais

static func _mat(rough: float, clearcoat: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	if clearcoat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = clearcoat
		m.clearcoat_roughness = 0.25
	return m


static func _skin_mat() -> StandardMaterial3D:
	var m := _mat(0.5, 0.12)  # pele acetinada (pouco verniz: sem brilhos estourados)
	m.rim_enabled = true  # pele lisa, sem relevo (personagem estilizado)
	m.rim = 0.2
	m.rim_tint = 0.8
	# Pele com dispersão subsuperficial leve (bordas translúcidas, menos "plástico").
	m.subsurf_scatter_enabled = true
	m.subsurf_scatter_strength = 0.18
	m.subsurf_scatter_skin_mode = true
	m.roughness = 0.5
	m.clearcoat_roughness = 0.45
	return m


static func _fabric_mat() -> StandardMaterial3D:
	var m := _mat(0.68)
	m.normal_enabled = true
	m.normal_texture = SKIN_NORMAL
	m.normal_scale = 0.45
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(14, 14, 14)
	m.rim_enabled = true  # brilho aveludado do tecido nas bordas
	m.rim = 0.3
	m.rim_tint = 0.45
	return m


static func _unshaded() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _rubber_mat() -> StandardMaterial3D:
	var m := _mat(0.5, 0.2)
	m.rim_enabled = true
	m.rim = 0.15
	return m


# ------------------------------------------------------------------ geometria auxiliar

static func _basis_y(d: Vector3, ref: Vector3 = Vector3.FORWARD) -> Basis:
	var y := d.normalized()
	var r := ref if absf(y.dot(ref.normalized())) < 0.95 else Vector3.RIGHT
	var x := r.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func _fold_at(t: float, a: float) -> float:
	var f := 0.0
	for cr in FOLD_CREASES:
		var g := (t - cr.x) / cr.y
		f += exp(-g * g) * cr.w * (0.5 + 0.5 * cos(a - cr.z))
	return f


## Membro orgânico: superfície de revolução ao longo de +Y local (0..length) com raio por perfil
## anatômico (amostras igualmente espaçadas, interpoladas suavemente) e pontas hemisféricas que se
## fundem às juntas (sem emenda seca cilindro/esfera).
## `folds` > 0: vincos de tecido (fração do raio) com normais exatas e oclusão pintada nos sulcos.
## `stripe`: faixa lateral na direção `stripe_axis` (espaço do pai), como a faixa de um macacão.
static func _limb(k: MeshKit, xf: Transform3D, length: float, prof: PackedFloat32Array, segs: int, c: Color,
		folds: float = 0.0, stripe: Color = Color(0, 0, 0, 0), stripe_axis: Vector3 = Vector3.ZERO) -> void:
	segs = MeshKit.seg_count(segs)
	var body_rows := MeshKit.seg_count(24 if folds > 0.0 else 10)
	var cap_rows := MeshKit.seg_count(4)
	var n := prof.size()
	var rad := func(t: float) -> float:
		var x := clampf(t, 0.0, 1.0) * float(n - 1)
		var i := mini(int(x), n - 2)
		var f := x - float(i)
		var p0 := prof[maxi(i - 1, 0)]
		var p1 := prof[i]
		var p2 := prof[i + 1]
		var p3 := prof[mini(i + 2, n - 1)]
		return 0.5 * (2.0 * p1 + (p2 - p0) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f * f + (3.0 * p1 - p0 - 3.0 * p2 + p3) * f * f * f)
	# Linhas (y, raio, inclinação do perfil dr/dy, normal y extra) de baixo para cima.
	var rows: Array[Vector4] = []
	var r0: float = rad.call(0.0)
	var r1: float = rad.call(1.0)
	for j in cap_rows:
		var ph := -PI * 0.5 + PI * 0.5 * float(j) / cap_rows
		rows.append(Vector4(r0 * sin(ph), r0 * cos(ph), 0.0, sin(ph)))
	for j in body_rows + 1:
		var t := float(j) / body_rows
		var rr: float = rad.call(t)
		var dr: float = (float(rad.call(t + 0.01)) - float(rad.call(t - 0.01))) / (0.02 * length)
		rows.append(Vector4(t * length, rr, dr, 0.0))
	for j in range(1, cap_rows + 1):
		var ph := PI * 0.5 * float(j) / cap_rows
		rows.append(Vector4(length + r1 * sin(ph), r1 * cos(ph), 0.0, sin(ph)))
	var nb := xf.basis.inverse().transposed()
	var base_i := k.verts.size()
	var e := 0.01
	for row in rows:
		var t := row.x / length
		for s in segs + 1:
			var a := TAU * float(s) / segs
			var d := Vector3(cos(a), 0.0, sin(a))
			var nrm: Vector3
			var r := row.y
			var col := c
			if row.w != 0.0:
				nrm = (d * sqrt(maxf(1.0 - row.w * row.w, 0.0)) + Vector3(0, row.w, 0)).normalized()
			elif folds > 0.0:
				# r(y, a) = R(y) * (1 - F): normal = dP/dy x dP/da.
				var fv := _fold_at(t, a) * folds
				r = row.y * (1.0 - fv)
				var r_y := (float(rad.call(t + e)) * (1.0 - _fold_at(t + e, a) * folds) - float(rad.call(t - e)) * (1.0 - _fold_at(t - e, a) * folds)) / (2.0 * e * length)
				var r_a := -row.y * (_fold_at(t, a + e) - _fold_at(t, a - e)) * folds / (2.0 * e)
				nrm = (d * r_y + Vector3.UP).cross(Vector3(-sin(a), 0.0, cos(a)) * r + d * r_a).normalized()
				if nrm.dot(d) < 0.0:
					nrm = -nrm
				col = c.darkened(clampf(fv * 3.0, 0.0, 0.3))
			else:
				nrm = (d - Vector3(0, row.z, 0)).normalized()
			if stripe.a > 0.0 and row.w == 0.0 and (xf.basis * d).normalized().dot(stripe_axis) > 0.93:
				col = stripe
			k.add_vertex(xf * (d * r + Vector3(0, row.x, 0)), (nb * nrm).normalized(), Vector2(float(s) / segs, row.x), col)
	var stride := segs + 1
	for j in rows.size() - 1:
		for s in segs:
			var a0 := base_i + j * stride + s
			k.quad(a0, a0 + 1, a0 + stride, a0 + stride + 1)


static func _limb_ab(k: MeshKit, a: Vector3, b: Vector3, prof: PackedFloat32Array, segs: int, c: Color,
		folds: float = 0.0, stripe: Color = Color(0, 0, 0, 0), stripe_axis: Vector3 = Vector3.ZERO) -> void:
	_limb(k, Transform3D(_basis_y(b - a), a), a.distance_to(b), prof, segs, c, folds, stripe, stripe_axis)


## Elipsoide com cor por vértice: `paint(d)` recebe a direção unitária (espaço local do elipsoide).
static func _ell_paint(k: MeshKit, center: Vector3, b: Basis, sc: Vector3, rings: int, segs: int, paint: Callable) -> void:
	rings = MeshKit.seg_count(rings)
	segs = MeshKit.seg_count(segs)
	var base_i := k.verts.size()
	for r in rings + 1:
		var phi := PI * float(r) / float(rings)
		for s in segs + 1:
			var th := TAU * float(s) / float(segs)
			var d := Vector3(cos(th) * sin(phi), cos(phi), sin(th) * sin(phi))
			if r == 0 or r == rings:
				d = Vector3(0, signf(d.y), 0)
			var n := (b * Vector3(d.x / sc.x, d.y / sc.y, d.z / sc.z)).normalized()
			k.add_vertex(center + b * (d * sc), n, Vector2(float(s) / segs, float(r) / rings), paint.call(d))
	var stride := segs + 1
	for r in rings:
		for s in segs:
			var a0 := base_i + r * stride + s
			var b0 := a0 + stride
			if r > 0:
				k.tri(a0, a0 + 1, b0)
			if r < rings - 1:
				k.tri(a0 + 1, b0 + 1, b0)


static func _seg(k: MeshKit, a: Vector3, b: Vector3, r0: float, r1: float, segs: int, c: Color) -> void:
	k.cylinder(Transform3D(_basis_y(b - a), a), r0, r1, a.distance_to(b), segs, c)


## Elipsoide com eixos (x, y, z) e semi-eixos `sc`.
static func _ell(k: MeshKit, center: Vector3, b: Basis, sc: Vector3, c: Color, rings: int = 10, segs: int = 16, ao: float = 0.0) -> void:
	k.sphere(Transform3D(b * Basis.from_scale(sc), center), 1.0, rings, segs, c, ao)


## Largura da cabeça em função da altura (lâmpada: crânio largo e redondo, queixo estreito e arredondado).
static func _head_w(y: float) -> float:
	return lerpf(0.58, 1.0, smoothstep(-1.1, 0.55, y))


## Ponto da superfície da cabeça na direção unitária `d` (em relação a HEAD_CENTER).
static func _head_pt(d: Vector3) -> Vector3:
	var w := _head_w(d.y)
	var yk := 1.02 if d.y < 0.0 else 1.0
	return Vector3(d.x * HEAD_R.x * w, d.y * HEAD_R.y * yk, d.z * HEAD_R.z * w)


static func _head_n(d: Vector3) -> Vector3:
	d = d.normalized()
	var t1 := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	var t2 := d.cross(t1).normalized()
	var e := 0.01
	var a := _head_pt((d + t1 * e).normalized()) - _head_pt((d - t1 * e).normalized())
	var b := _head_pt((d + t2 * e).normalized()) - _head_pt((d - t2 * e).normalized())
	var n := a.cross(b).normalized()
	return n if n.dot(_head_pt(d)) >= 0.0 else -n


## Base tangente à cabeça no ponto `d`: z = normal, x ~ direita.
static func _face_basis(d: Vector3, roll: float = 0.0) -> Basis:
	var n := _head_n(d)
	var x := (Vector3.RIGHT - n * n.x).normalized()
	var y := n.cross(x)
	if roll != 0.0:
		x = x.rotated(n, roll)
		y = y.rotated(n, roll)
	return Basis(x, y, n)


# ------------------------------------------------------------------ construção

func build(char_id: int, suit: Color) -> void:
	character = clampi(char_id, 0, NAMES.size() - 1)
	name = "Driver"
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	var skin := SKIN_COLORS[character]
	var skin_mat := _skin_mat()
	var fabric := _fabric_mat()
	_build_body(suit, skin, skin_mat, fabric)
	_build_head(skin, skin_mat)
	_build_arms(suit, skin, skin_mat, fabric)


func _build_body(kc: Color, skin: Color, skin_mat: Material, fabric: Material) -> void:
	var o := -ORIGIN
	var tb := Basis(Vector3.RIGHT, TORSO_TILT)
	var panel := kc.lightened(0.22)
	var t := MeshKit.new()
	# Quadril primeiro (o 1º vértice tem exatamente a cor do traje).
	_ell(t, o + Vector3(0, 0.5, 0.32), Basis.IDENTITY, Vector3(0.18, 0.12, 0.16), kc, 10, 18, 0.25)
	# Tronco: painel lateral claro com filete branco, zíper frontal e leve oclusão na barriga.
	var torso_paint := func(d: Vector3) -> Color:
		var ax := absf(d.x)
		if ax > 0.86:
			return panel
		if ax > 0.8:
			return PIPING
		if d.z < -0.3 and ax < 0.035 and d.y < 0.2:
			return TRIM
		return kc.darkened(0.18 * clampf(-d.y - 0.4, 0.0, 1.0))
	_ell_paint(t, o + Vector3(0, 0.7, 0.3), tb, Vector3(0.19, 0.23, 0.155), 20, 32, torso_paint)
	_ell(t, o + Vector3(0, 0.56, 0.31), Basis.IDENTITY, Vector3(0.188, 0.035, 0.166), TRIM, 6, 20)  # cinto
	_ell(t, o + Vector3(0, 0.555, 0.148), Basis(Vector3.RIGHT, -0.15), Vector3(0.048, 0.028, 0.012), Color(0.75, 0.76, 0.78), 4, 10)  # fivela
	_ell(t, o + Vector3(0, 0.9, 0.255), Basis.IDENTITY, Vector3(0.108, 0.04, 0.098), PIPING, 6, 18)  # gola
	_ell(t, o + Vector3(0, 0.925, 0.257), Basis.IDENTITY, Vector3(0.09, 0.022, 0.082), kc.darkened(0.25), 6, 18)
	for s: float in [-1.0, 1.0]:
		var sh := o + Vector3(s * SHOULDER.x, SHOULDER.y, SHOULDER.z)
		t.sphere(Transform3D(Basis.IDENTITY, sh), 0.07, 8, 12, kc)
		_ell(t, sh + Vector3(-s * 0.015, 0.05, 0.0), Basis(Vector3.BACK, s * 0.35), Vector3(0.08, 0.02, 0.055), panel, 6, 14)  # ombreira
		_ell(t, sh + Vector3(-s * 0.015, 0.043, 0.0), Basis(Vector3.BACK, s * 0.35), Vector3(0.083, 0.012, 0.058), PIPING, 4, 14)
		var hip := o + Vector3(s * 0.09, 0.5, 0.28)
		var knee := o + Vector3(s * 0.16, 0.645, -0.36)
		var ankle := o + Vector3(s * 0.15, 0.4, -0.56)
		var side := Vector3(s, 0.0, 0.0)
		_limb_ab(t, hip, knee, PackedFloat32Array([0.078, 0.083, 0.078, 0.069]), 14, kc, 0.09, PIPING, side)   # coxa
		t.sphere(Transform3D(Basis.IDENTITY, knee), 0.075, 8, 12, TRIM)                                          # joelheira
		_limb_ab(t, knee, ankle, PackedFloat32Array([0.066, 0.069, 0.061, 0.054]), 14, kc, 0.09, PIPING, side) # panturrilha
		# Bota: cano, corpo e sola branca.
		_seg(t, ankle + Vector3(0, 0.05, 0.03), ankle + Vector3(0, -0.04, 0), 0.062, 0.067, 12, TRIM)
		_ell(t, o + Vector3(s * 0.15, 0.36, -0.63), Basis.IDENTITY, Vector3(0.068, 0.062, 0.102), TRIM, 8, 12)
		_ell(t, o + Vector3(s * 0.15, 0.325, -0.63), Basis.IDENTITY, Vector3(0.072, 0.022, 0.107), PIPING, 6, 12)
	var mesh := t.commit(null, fabric)
	_chest_panel(mesh)
	var neck := MeshKit.new()
	_limb_ab(neck, o + Vector3(0, 0.86, 0.26), o + HEAD_PIVOT + Vector3(0, 0.08, 0), PackedFloat32Array([0.06, 0.052, 0.05]), 14, skin.darkened(0.08))
	neck.commit(mesh, skin_mat)
	body = MeshInstance3D.new()
	body.name = "Suit"
	body.mesh = mesh
	rig.add_child(body)


## Painel no peito (placa clara com moldura e dois botões redondos) + LEDs.
func _chest_panel(mesh: ArrayMesh) -> void:
	var o := -ORIGIN
	var tb := Basis(Vector3.RIGHT, TORSO_TILT)
	var n := tb * Vector3(0, 0, -1)
	var up := tb * Vector3.UP
	var pb := Basis(Vector3.RIGHT, n, Vector3.RIGHT.cross(n))
	var pc := o + Vector3(0, 0.7, 0.3) + up * 0.035 + n * 0.128
	var p := MeshKit.new()
	p.rounded_prism(Transform3D(pb, pc), 0.16, 0.105, 0.03, 0.028, 3, Color(0.42, 0.45, 0.47), Color(0.72, 0.76, 0.76), false)
	var led := MeshKit.new()
	for bx: float in [-0.036, 0.036]:
		p.cylinder(Transform3D(pb, pc + Vector3(bx, 0, 0) + n * 0.029), 0.027, 0.027, 0.008, 18, Color(0.88, 0.9, 0.9))
		p.cylinder(Transform3D(pb, pc + Vector3(bx, 0, 0) + n * 0.03), 0.019, 0.019, 0.012, 18, Color(0.08, 0.1, 0.11))
		led.cylinder(Transform3D(pb, pc + Vector3(bx, 0, 0) + n * 0.041), 0.009, 0.009, 0.002, 10, LED_COLORS[character])
	p.commit(mesh, _mat(0.35, 0.6))
	led.commit(mesh, _unshaded())


## Pele procedural da cabeça (sem modelo esculpido).
func _head_skin(k: MeshKit, skin: Color, noise: FastNoiseLite) -> void:
	var hc := HEAD_CENTER
	var rings := MeshKit.seg_count(28)
	var segs := MeshKit.seg_count(40)
	var base_i := k.verts.size()
	for r in rings + 1:
		var phi := PI * float(r) / float(rings)
		for s in segs + 1:
			var th := TAU * float(s) / float(segs)
			var d := Vector3(cos(th) * sin(phi), cos(phi), sin(th) * sin(phi))
			if r == 0 or r == rings:
				d = Vector3(0, signf(d.y), 0)
			k.add_vertex(hc + _head_pt(d), _head_n(d), Vector2(float(s) / segs, float(r) / rings), _skin_color(d, skin, noise))
	var stride := segs + 1
	for r in rings:
		for s in segs:
			var a0 := base_i + r * stride + s
			var b0 := a0 + stride
			if r > 0:
				k.tri(a0, a0 + 1, b0)
			if r < rings - 1:
				k.tri(a0 + 1, b0 + 1, b0)


func _skin_color(d: Vector3, skin: Color, noise: FastNoiseLite) -> Color:
	var v := noise.get_noise_3d(d.x * 40.0, d.y * 40.0, d.z * 40.0)
	var v2 := noise.get_noise_3d(d.x * 9.0 + 50.0, d.y * 9.0, d.z * 9.0)
	var shade := 0.94 + 0.05 * v + 0.05 * v2
	shade += 0.07 * clampf(-d.z, 0.0, 1.0) - 0.08 * clampf(d.y, 0.0, 1.0) * clampf(d.z + 0.3, 0.0, 1.0)
	var c := skin * shade
	if character == Character.TURISTA:
		# Blush pintado nas maçãs do rosto (sem relevo).
		for s: float in [-1.0, 1.0]:
			var f := 1.0 - smoothstep(0.07, 0.17, d.normalized().distance_to(Vector3(s * 0.62, -0.5, -1.0).normalized()))
			c = c.lerp(Color(1.0, 0.36, 0.5), 0.55 * f)
	c.a = 1.0
	return c


## Olho: `eye` = [direção central, eixo x, eixo y, lado, raio angular x, raio angular y].
## (u, v) no disco unitário; o lado interno (nariz) afina, formando a gota.
static func _eye_dir(eye: Array, u: float, v: float) -> Vector3:
	var side: float = eye[3]
	var taper := lerpf(1.0, 0.7, clampf(-side * u, 0.0, 1.0))
	var d0: Vector3 = eye[0]
	var ex: Vector3 = eye[1]
	var ey: Vector3 = eye[2]
	return (d0 + ex * (u * float(eye[4])) + ey * (v * taper * float(eye[5]))).normalized()


static func _eye_pt(eye: Array, u: float, v: float, bulge: float) -> Vector3:
	var d := _eye_dir(eye, u, v)
	var off := -0.004 + bulge * sqrt(maxf(1.0 - u * u - v * v, 0.0))
	return _head_pt(d) + _head_n(d) * off


## Casca do olho colada à cabeça (malha polar), normais numéricas. `paint(rho, ângulo)` colore por anel.
func _eye_shell(k: MeshKit, eye: Array, bulge: float, c: Color, paint: Callable = Callable()) -> void:
	var rings := MeshKit.seg_count(9)
	var segs := MeshKit.seg_count(30)
	var e := 0.01
	var base_i := k.verts.size()
	for r in rings + 1:
		var rho := float(r) / float(rings)
		for j in segs + 1:
			var th := TAU * float(j) / float(segs)
			var u := rho * cos(th)
			var v := rho * sin(th)
			var p := _eye_pt(eye, u, v, bulge)
			var du := _eye_pt(eye, u + e, v, bulge) - _eye_pt(eye, u - e, v, bulge)
			var dv := _eye_pt(eye, u, v + e, bulge) - _eye_pt(eye, u, v - e, bulge)
			var n := du.cross(dv).normalized()
			var hn := _head_n(_eye_dir(eye, u, v))
			if n.dot(hn) < 0.0:
				n = -n
			if r == rings:
				n = (n + hn).normalized()
			k.add_vertex(HEAD_CENTER + p, n, Vector2(u, v), paint.call(rho, th) if paint.is_valid() else c)
	var stride := segs + 1
	for r in rings:
		for j in segs:
			var a0 := base_i + r * stride + j
			k.quad(a0, a0 + 1, a0 + stride, a0 + stride + 1)


func _build_head(skin: Color, skin_mat: Material) -> void:
	head = Node3D.new()
	head.name = "Head"
	head.position = HEAD_PIVOT - ORIGIN
	rig.add_child(head)
	var hc := HEAD_CENTER
	var noise := FastNoiseLite.new()
	noise.seed = 7 + character
	noise.frequency = 0.05
	var k := MeshKit.new()
	_head_skin(k, skin, noise)
	# Pintas: discos coladas à curvatura da cabeça (mesma casca dos olhos, quase sem saliência).
	var mx := 1.0 if character == Character.VISITANTE else -1.0
	for sp in SPOTS:
		var sd := Vector3(sp.x * mx, sp.y, sp.z).normalized()
		var sb := _face_basis(sd)
		var tone := 0.9 + 0.2 * (noise.get_noise_3d(sd.x * 30.0, sd.y * 30.0, sd.z * 30.0) * 0.5 + 0.5)
		_eye_shell(k, [sd, sb.x, sb.y, 0.0, sp.w, sp.w * 0.85], 0.0055, SPOT_COLORS[character] * tone)
	var fem := character == Character.TURISTA
	var dark := skin.darkened(0.72)
	var eyes := MeshKit.new()
	var iris := MeshKit.new()
	var glint := MeshKit.new()
	# Íris funda: pupila enorme, anel colorido com fibras e aro escuro (vista através da córnea).
	var iris_c := IRIS_COLORS[character]
	var iris_paint := func(rho: float, th: float) -> Color:
		if rho < 0.77 or rho > 0.95:
			return Color(0.004, 0.004, 0.006)
		var x := (rho - 0.77) / 0.18
		var fib := 0.85 + 0.15 * sin(th * 29.0 + sin(th * 7.0) * 2.0)
		var ic := iris_c * (fib * lerpf(0.35, 1.0, sin(x * PI)))
		ic.a = 1.0
		return ic
	for s: float in [-1.0, 1.0]:
		# Olho enorme em gota (ponta para o nariz), inclinado e colado à curvatura da cabeça.
		var d0 := Vector3(s * 0.48, -0.06, -1.0).normalized()
		var eb := _face_basis(d0, -s * (0.38 if fem else 0.22))
		var eye := [d0, eb.x, eb.y, s, 0.42 if fem else 0.38, 0.3 if fem else 0.34]
		_eye_shell(iris, eye, 0.012, Color.BLACK, iris_paint)
		_eye_shell(eyes, eye, 0.03, Color(0.01, 0.012, 0.016))
		for g: Array in [[-0.3, -0.38, 0.036, 0.03], [0.4, 0.4, 0.016, 0.013]]:
			var gd := _eye_dir(eye, float(g[0]), float(g[1]))
			var gp := hc + _eye_pt(eye, float(g[0]), float(g[1]), 0.03) + _head_n(gd) * 0.001
			_ell(glint, gp, _face_basis(gd), Vector3(g[2], g[3], 0.004), Color(1, 1, 1), 8, 14)
		# Narinas (pontinhos rentes à pele).
		var nd := Vector3(s * 0.05, -0.23, -1.0).normalized()
		_ell(k, hc + _head_pt(nd) - _head_n(nd) * 0.003, _face_basis(nd), Vector3(0.008, 0.005, 0.004), dark, 4, 8)
		if fem:
			# Cílios: três fios curvos no canto externo superior de cada olho.
			for j in 3:
				var ang := 0.3 + float(j) * 0.38
				var u := s * cos(ang)
				var v := sin(ang)
				var en := _head_n(_eye_dir(eye, u, v))
				var base := hc + _eye_pt(eye, u * 1.02, v * 1.02, 0.0) + en * 0.004
				var out := (eb.x * u + eb.y * v).normalized()
				# Fio curvo e fino: sai para fora/cima e curva para trás (2 segmentos afinando).
				var ln := 0.026 + 0.008 * float(j)
				var mid := base + (out * 0.55 + en * 0.6 + eb.y * 0.2).normalized() * ln * 0.55
				var tip := mid + (out * 0.75 + eb.y * 0.45 - en * 0.1).normalized() * ln * 0.55
				_seg(k, base, mid, 0.0042, 0.0028, 6, Color(0.04, 0.02, 0.04))
				_seg(k, mid, tip, 0.0028, 0.0012, 6, Color(0.04, 0.02, 0.04))
	# Sorriso pequeno (cantos para cima).
	var lip := Color(0.75, 0.12, 0.32) if fem else skin.darkened(0.6)
	var prev := Vector3.ZERO
	for j in 17:
		var tt := -1.0 + 2.0 * float(j) / 16.0
		var md := Vector3(tt * 0.15, -0.45 + 0.07 * tt * tt, -1.0).normalized()
		var mp := hc + _head_pt(md) - _head_n(md) * 0.002
		if j > 0:
			_seg(k, prev, mp, 0.0075 if fem else 0.0055, 0.0075 if fem else 0.0055, 6, lip)
		prev = mp
	var mesh := k.commit(null, skin_mat)
	var iris_mat := ShaderMaterial.new()
	iris_mat.shader = IRIS_SHADER
	iris.commit(mesh, iris_mat)
	var cornea := ShaderMaterial.new()
	cornea.shader = CORNEA_SHADER
	eyes.commit(mesh, cornea)
	var glint_mat := StandardMaterial3D.new()  # branco puro emissivo (o unshaded acinzenta no tonemap)
	glint_mat.albedo_color = Color.BLACK
	glint_mat.emission_enabled = true
	glint_mat.emission = Color.WHITE
	glint_mat.emission_energy_multiplier = 2.2
	glint.commit(mesh, glint_mat)
	if fem:
		# Laço vermelho de bolinhas brancas no alto da cabeça (inclinado para a direita).
		var bow := MeshKit.new()
		var dd := Vector3(0.38, 0.9, 0.08).normalized()
		var bn := _head_n(dd)
		var bt := (Vector3(1, -0.2, 0) - bn * bn.dot(Vector3(1, -0.2, 0))).normalized()
		var bb := bn.cross(bt)
		var bp := hc + _head_pt(dd) + bn * 0.02
		var red := Color(0.9, 0.06, 0.2)
		_ell(bow, bp + bn * 0.02, Basis(bt, bn, bb), Vector3(0.034, 0.034, 0.03), red.darkened(0.1), 8, 12)
		for s: float in [-1.0, 1.0]:
			var lb := Basis(bt, bn, bb).rotated(bb, s * 0.25)
			var lc := bp + bn * 0.03 + bt * s * 0.075
			_ell(bow, lc, lb, Vector3(0.07, 0.05, 0.034), red, 10, 16)
			for q: Array in [[0.35, 0.3], [0.65, -0.15], [0.2, -0.45]]:
				var qp: Vector3 = lc + lb.x * s * 0.07 * float(q[0]) + lb.y * 0.05 * float(q[1]) - bb * 0.029
				_ell(bow, qp, lb, Vector3(0.011, 0.011, 0.006), Color(1, 0.97, 0.97), 4, 8)
				_ell(bow, qp + bb * 0.058, lb, Vector3(0.011, 0.011, 0.006), Color(1, 0.97, 0.97), 4, 8)
		var bmat := _mat(0.25, 1.0)
		bow.commit(mesh, bmat)
	var mi := MeshInstance3D.new()
	mi.name = "HeadMesh"
	mi.mesh = mesh
	head.add_child(mi)


func _build_arms(kc: Color, skin: Color, skin_mat: Material, fabric: Material) -> void:
	var ua := MeshKit.new()
	_limb(ua, Transform3D.IDENTITY, L1, PackedFloat32Array([0.057, 0.06, 0.055, 0.049]), 14, kc, 0.09)
	ua.sphere(Transform3D(Basis.IDENTITY, Vector3(0, L1, 0)), 0.053, 6, 12, kc.darkened(0.12))
	var ua_mesh := ua.commit(null, fabric)
	var fa := MeshKit.new()
	_limb(fa, Transform3D.IDENTITY, L2, PackedFloat32Array([0.05, 0.052, 0.047, 0.043]), 14, kc, 0.09)
	fa.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, L2 - 0.05, 0)), 0.056, 0.058, 0.05, 14, TRIM)  # punho
	fa.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, L2 - 0.056, 0)), 0.0575, 0.0575, 0.008, 14, PIPING)
	var fa_mesh := fa.commit(null, fabric)
	var finger := MeshKit.new()
	finger.sphere(Transform3D.IDENTITY, 0.0145, 5, 8, skin)
	finger.cylinder(Transform3D.IDENTITY, 0.0135, 0.0125, 0.058, 8, skin, false)
	finger.sphere(Transform3D(Basis.IDENTITY, Vector3(0, 0.064, 0)), 0.0185, 6, 10, skin * 1.04)    # ponta arredondada de ET
	var finger_mesh := finger.commit(null, skin_mat)
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var suffix := "L" if i == 0 else "R"
		var a := MeshInstance3D.new()
		a.name = "Arm" + suffix
		a.mesh = ua_mesh
		rig.add_child(a)
		arms.append(a)
		var f := MeshInstance3D.new()
		f.name = "Forearm" + suffix
		f.mesh = fa_mesh
		rig.add_child(f)
		forearms.append(f)
		# Mão: palma (dorso para +Z local, dedos para +Y), anelar dobrado e polegar.
		var h := MeshKit.new()
		_ell(h, Vector3(0, 0.045, 0), Basis.IDENTITY, Vector3(0.043, 0.05, 0.027), skin, 8, 14)
		_ell(h, Vector3(s * 0.03, 0.082, -0.018), Basis(Vector3.RIGHT, -0.9), Vector3(0.014, 0.024, 0.017), skin, 6, 8)
		var tb := Vector3(-s * 0.032, 0.03, -0.012)
		var tt := Vector3(-s * 0.018, 0.075, -0.04)
		_seg(h, tb, tt, 0.016, 0.014, 8, skin)
		h.sphere(Transform3D(Basis.IDENTITY, tt), 0.017, 5, 8, skin)
		var hand := MeshInstance3D.new()
		hand.name = "Hand" + suffix
		hand.mesh = h.commit(null, skin_mat)
		rig.add_child(hand)
		hands.append(hand)
		for j in 2:
			var fi := MeshInstance3D.new()
			fi.name = ("Index" if j == 0 else "Middle") + suffix
			fi.mesh = finger_mesh
			fi.position = Vector3(-s * 0.013 if j == 0 else s * 0.014, 0.086, 0.0)
			hand.add_child(fi)
			fingers[i].append(fi)


# ------------------------------------------------------------------ animação

func set_pose(p: Pose) -> void:
	if p == pose:
		return
	pose = p
	_t = 0.0
	if p == Pose.VICTORY and _fx == null:
		_fx = _make_fx()
		rig.add_child(_fx)
	if _fx != null:
		_fx.emitting = p == Pose.VICTORY


## Comemoração própria: corações (Turista) ou estrelinhas (Visitante) subindo.
func _make_fx() -> GPUParticles3D:
	var fx := GPUParticles3D.new()
	fx.name = "CelebrationFx"
	fx.amount = 14
	fx.lifetime = 1.8
	fx.position = HEAD_PIVOT - ORIGIN + Vector3(0, 0.45, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = Vector3.UP
	pm.spread = 35.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, 0.25, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.15, 1))
	curve.add_point(Vector2(0.8, 1))
	curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	fx.process_material = pm
	var k := MeshKit.new()
	var mat := _unshaded()
	if character == Character.TURISTA:
		var c := Color(1.0, 0.3, 0.55)
		for s: float in [-1.0, 1.0]:
			k.sphere(Transform3D(Basis.IDENTITY, Vector3(s * 0.035, 0.03, 0)), 0.042, 6, 10, c)
		k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, 0.035, 0)), 0.068, 0.0, 0.09, 12, c)
	else:
		var c := Color(1.0, 0.92, 0.35)
		k.sphere(Transform3D(Basis.from_scale(Vector3(1, 1, 0.35)), Vector3.ZERO), 0.06, 2, 4, c)
		k.sphere(Transform3D(Basis(Vector3.FORWARD, PI * 0.25) * Basis.from_scale(Vector3(1, 1, 0.35)), Vector3.ZERO), 0.06, 2, 4, c.lightened(0.3))
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	fx.draw_pass_1 = k.commit(null, mat)
	return fx


## Atualiza a pose (grips = pontos de pega no volante, no espaço deste nó).
func animate_rig(delta: float, steer: float, grip_l: Vector3, grip_r: Vector3) -> void:
	_t += delta
	_gesture = maxf(_gesture - delta, 0.0)
	var pw := _pose_weights(delta)
	var wd := pw.x
	var wv := pw.y
	var wl := pw.z
	var fem := character == Character.TURISTA
	# Pulinhos na vitória.
	var hz := 1.45 if fem else 1.1
	hop = absf(sin(_t * PI * hz)) * (0.09 if fem else 0.13) * wv
	rig.position = Vector3(0, hop - 0.02 * wl, 0)
	rig.rotation = Vector3(-0.1 * wl + 0.015 * sin(_t * 1.6) * wl, 0.0, sin(_t * PI * hz * 0.5) * 0.06 * wv)
	# Cabeça: acompanha a curva / comemora / baixa balançando.
	var hd := Vector3(0.0, -steer * 0.22, steer * 0.05)
	var hv := Vector3(0.12 + 0.1 * sin(_t * 7.0), 0.0, 0.0)
	if fem:
		hv = Vector3(0.1, 0.0, sin(_t * 3.4) * 0.24)
	var hl := Vector3(-0.5 + 0.04 * sin(_t * 2.0), sin(_t * 3.6) * 0.38 * (0.62 + 0.38 * exp(-_t * 0.7)), 0.0)
	head.rotation = hd * wd + hv * wv + hl * wl
	head_pitch = head.rotation.x
	# Braços (IK) e mãos.
	var grips: Array[Vector3] = [grip_l, grip_r]
	wrist_error = 0.0
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var fd := Vector3(-s * 0.35, -0.25, -1.0).normalized()
		var pd := Vector3(s, 0.3, 0.0)
		var wdr := grips[i] + pd.normalized() * 0.03 - fd * 0.045
		var wvw: Vector3
		var fv: Vector3
		if fem:
			wvw = Vector3(s * 0.42, 1.1 + 0.03 * sin(_t * 6.0), -0.02) - ORIGIN
			fv = Vector3(s * 0.45, 1.0, -0.2)
		else:
			wvw = Vector3(s * 0.4, 1.22 + 0.05 * sin(_t * 7.0 + (PI if s > 0.0 else 0.0)), 0.1) - ORIGIN
			fv = Vector3(s * 0.25, 1.0, -0.1)
		var wlw := Vector3(s * 0.17, 0.73, -0.24) - ORIGIN
		var fl := Vector3(s * 0.1, -0.35, -1.0)
		var wrist := wdr * wd + wvw * wv + wlw * wl
		var fdir := (fd * wd + fv.normalized() * wv + fl.normalized() * wl).normalized()
		var back := (pd.normalized() * wd + Vector3(0, 0, 1) * wv + Vector3.UP * wl).normalized()
		var gw := _apply_gesture(i, wrist, fdir)
		wrist_error = maxf(wrist_error, _solve_arm(i, s, gw[0], gw[1], back))
	v_amount = wv
	var curl := -1.55 * wd - 0.45 * wl
	var spread := 0.24 * wv
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		(fingers[i][0] as Node3D).basis = Basis(Vector3.BACK, s * spread) * Basis(Vector3.RIGHT, curl)
		(fingers[i][1] as Node3D).basis = Basis(Vector3.BACK, -s * spread) * Basis(Vector3.RIGHT, curl)


## Pesos das poses (volante, vitória, derrota) com transição suavizada (ease in/out), normalizados.
func _pose_weights(delta: float) -> Vector3:
	var target := Vector3(1, 0, 0) if pose == Pose.DRIVE else (Vector3(0, 1, 0) if pose == Pose.VICTORY else Vector3(0, 0, 1))
	_w = _w.move_toward(target, delta * 2.6) if delta > 0.0 else target
	var e := Vector3(_w.x * _w.x * (3.0 - 2.0 * _w.x), _w.y * _w.y * (3.0 - 2.0 * _w.y), _w.z * _w.z * (3.0 - 2.0 * _w.z))
	return e / maxf(e.x + e.y + e.z, 0.001)


## Volta ao estado recém-construído (modelo reaproveitado do pool).
func reset_pose() -> void:
	_fx = null
	pose = Pose.DRIVE
	_w = Vector3(1, 0, 0)
	_t = 0.0
	_gesture = 0.0
	hop = 0.0
	rig.position = Vector3.ZERO
	rig.rotation = Vector3.ZERO


## Gesto de uso de item: a mão direita recolhe por cima do ombro (preparação), lança para a frente
## e volta ao volante com desaceleração suave.
func throw_gesture() -> void:
	_gesture = GESTURE_TIME


func _apply_gesture(i: int, wrist: Vector3, fdir: Vector3) -> Array:
	if i != 1 or _gesture <= 0.0:
		return [wrist, fdir]
	var p := 1.0 - _gesture / GESTURE_TIME
	var k := smoothstep(0.0, 0.28, p) * (1.0 - smoothstep(0.6, 1.0, p))
	var thr := smoothstep(0.3, 0.5, p)
	var tgt := (Vector3(0.36, 1.24, 0.4) - ORIGIN).lerp(Vector3(0.3, 1.08, -0.18) - ORIGIN, thr)
	var fd := Vector3(0.1, lerpf(1.0, 0.35, thr), lerpf(0.3, -1.0, thr)).normalized()
	return [wrist.lerp(tgt, k), fdir.lerp(fd, k).normalized()]


## IK de 2 ossos (ombro -> cotovelo -> punho), cotovelo para fora/baixo. Devolve o erro de alcance.
func _solve_arm(i: int, s: float, wrist: Vector3, fdir: Vector3, back: Vector3) -> float:
	var sh := Vector3(s * SHOULDER.x, SHOULDER.y, SHOULDER.z) - ORIGIN
	var to := wrist - sh
	var dist := to.length()
	var d := clampf(dist, 0.08, (L1 + L2) * 0.999)
	var u := to / maxf(dist, 0.0001)
	var ca := clampf((L1 * L1 + d * d - L2 * L2) / (2.0 * L1 * d), -1.0, 1.0)
	var sa := sqrt(1.0 - ca * ca)
	var pole := Vector3(s, -0.7, 0.3)
	var pp := pole - u * pole.dot(u)
	pp = pp.normalized() if pp.length_squared() > 1e-6 else Vector3.DOWN
	var e := sh + u * (L1 * ca) + pp * (L1 * sa)
	var wr := sh + u * d
	arms[i].transform = Transform3D(_basis_y(e - sh, pp), sh)
	forearms[i].transform = Transform3D(_basis_y(wr - e, pp), e)
	var y := fdir
	var z := (back - y * back.dot(y))
	z = z.normalized() if z.length_squared() > 1e-6 else Vector3.BACK
	hands[i].transform = Transform3D(Basis(y.cross(z), y, z), wr)
	return absf(dist - d)
