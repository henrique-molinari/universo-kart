class_name KartModel
extends Node3D
## Modelo procedural do kart (MeshKit): kart de competição moderno (estilo CIK), baixo e aberto.
## Carenagem lisa feita por "lofts" de seções superelípticas: spoiler dianteiro, painel frontal (nassau)
## à frente dos pés, pontões laterais e para-choque traseiro, com pintura em verniz na cor do kart e
## grafismo (faixas brancas, saias escuras). Chassi tubular cromado, banco concha envolvendo o piloto,
## coluna de direção inclinada até o volante de 3 raios, tanque entre as pernas, pedais, motor à direita
## com cabeçote aletado, coletor e silencioso traseiro com 2 ponteiras, disco de freio e coroa no eixo.
## Os volumes da carenagem ficam em `solids` (mesmos parâmetros da malha) para os testes garantirem que
## o piloto não atravessa o kart (inside_body).
## Local: -Z = frente, +X = direita, +Y = cima. Origem no chão, centro do kart.

const FRONT_R := 0.25
const REAR_R := 0.3
const WHEEL_TILT := 0.7   ## inclinação do volante (rad): face voltada para o piloto, eixo = coluna
const SEAT_NORMAL := preload("res://assets/materials/noise_grain_normal.tres")
## Resolução das curvas do kart/piloto (multiplica segmentos e anéis de MeshKit; 1 = padrão).
const DETAIL := 1.0

## Rodas: pivô (posição no eixo + esterço em Y, só dianteiras) -> nó de giro (só X local) -> malha centrada.
var wheels: Array[Node3D] = []          ## nós de giro (rotação só em X local)
var wheel_pivots: Array[Node3D] = []
var wheel_radius: Array[float] = []
var front_wheels: Array[Node3D] = []    ## pivôs que esterçam
var body_root: Node3D                   ## pulinho (tudo que é visível, inclusive rodas e efeitos)
var tilt_root: Node3D                   ## rolagem da carroceria/piloto (as rodas NÃO rolam junto)
var _spin: Array[float] = []
var driver: AlienDriver                 ## piloto articulado (ET ou piloto humano; inclina nas curvas)
var character := 0                      ## Characters
var steering_wheel: Node3D
var paint_color: Color                  ## cor do kart
var suit_color: Color                   ## cor do traje (do personagem, Characters.suit_color)
## Volumes da carenagem (lofts, coordenadas do tilt_root) para teste de interpenetração.
var solids: Array[Dictionary] = []
var pool_key := ""                      ## chave do pool (personagem, cor, número)
var _base_nodes := {}                   ## nós criados pelo build (o resto é removido ao devolver)
## Pool de modelos prontos: montar um kart custa ~0,15 s de CPU; "correr de novo" e a passagem
## seleção -> corrida reaproveitam os modelos já montados (sem tela preta esperando a montagem).
static var _pool := {}
var _steer_s := 0.0
var _accel := 0.0
var _prev_speed := 0.0
## Camada de render só dos karts/pilotos: a luz de contorno (rim light) das telas de seleção,
## introdução e vitória ilumina apenas esta camada (não acende o asfalto atrás).
const RIM_LAYER := 1 << 10
const POOL_MAX := 16
## Pontos (locais ao body_root) para efeitos.
var exhaust_points: Array[Vector3] = [Vector3(-0.2, 0.42, 1.36), Vector3(0.2, 0.42, 1.36)]
var rear_wheel_points: Array[Vector3] = [Vector3(-0.8, 0.06, 1.0), Vector3(0.8, 0.06, 1.0)]

var _hop_t := 1.0
var _roll := 0.0
var _lean := 0.0


static func _mat(rough: float, metal: float = 0.0, clearcoat: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	if clearcoat:
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.06
	return m


## Base com eixo Y apontando para `d`.
static func _basis_y(d: Vector3) -> Basis:
	var y := d.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## Cilindro (ou cone) de `a` até `b`.
static func _seg(k: MeshKit, a: Vector3, b: Vector3, r0: float, r1: float, segs: int, c: Color) -> void:
	k.cylinder(Transform3D(_basis_y(b - a), a), r0, r1, a.distance_to(b), segs, c)


static func _blob(k: MeshKit, center: Vector3, sc: Vector3, c: Color, ao: float = 0.0, rings: int = 12, segs: int = 20) -> void:
	k.sphere(Transform3D(Basis.IDENTITY.scaled(sc), center), 1.0, rings, segs, c, ao)


# ------------------------------------------------------------------ lofts (carenagem)
# Loft = {"w": eixo, "u": lateral da seção, "v": altura da seção, "n": expoente da superelipse,
#         "st": [[t, cu, cv, hu, hv], ...]} — seção em t: centro w*t + u*cu + v*cv, semi-eixos hu/hv.

## Parâmetros [cu, cv, hu, hv] em t (Catmull-Rom entre as estações).
static func _loft_at(st: Array, t: float) -> PackedFloat32Array:
	var n := st.size()
	var i := 0
	while i < n - 2 and t > float(st[i + 1][0]):
		i += 1
	var t0: float = st[i][0]
	var t1: float = st[i + 1][0]
	var f := clampf((t - t0) / maxf(t1 - t0, 0.0001), 0.0, 1.0)
	var out := PackedFloat32Array()
	for k in range(1, 5):
		var p0: float = st[maxi(i - 1, 0)][k]
		var p1: float = st[i][k]
		var p2: float = st[i + 1][k]
		var p3: float = st[mini(i + 2, n - 1)][k]
		var v := 0.5 * (2.0 * p1 + (p2 - p0) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f * f + (3.0 * p1 - p0 - 3.0 * p2 + p3) * f * f * f)
		out.append(maxf(v, 0.004) if k >= 3 else v)
	return out


static func _loft_pt(L: Dictionary, t: float, th: float) -> Vector3:
	var s := _loft_at(L["st"], t)
	var e := 2.0 / float(L["n"])
	var c := cos(th)
	var sn := sin(th)
	var x := signf(c) * pow(absf(c), e)
	var y := signf(sn) * pow(absf(sn), e)
	return L["w"] * t + L["u"] * (s[0] + s[2] * x) + L["v"] * (s[1] + s[3] * y)


## Malha do loft; `paint(f, th, p)` dá a cor (f = 0..1 ao longo do eixo, th = ângulo na seção).
static func _loft(k: MeshKit, L: Dictionary, rings: int, segs: int, paint: Callable) -> void:
	rings = MeshKit.seg_count(rings)
	segs = MeshKit.seg_count(segs)
	var st: Array = L["st"]
	var t0: float = st[0][0]
	var t1: float = st[st.size() - 1][0]
	var w: Vector3 = L["w"]
	var base_i := k.verts.size()
	for r in rings + 1:
		var f := float(r) / float(rings)
		var t := lerpf(t0, t1, f)
		var s := _loft_at(st, t)
		var ctr: Vector3 = w * t + L["u"] * s[0] + L["v"] * s[1]
		var ta := maxf(t - 0.004, t0)
		var tb := minf(t + 0.004, t1)
		for j in segs + 1:
			var th := TAU * float(j) / float(segs)
			var p := _loft_pt(L, t, th)
			var du := _loft_pt(L, t, th + 0.01) - _loft_pt(L, t, th - 0.01)
			var dt := _loft_pt(L, tb, th) - _loft_pt(L, ta, th)
			var nrm := du.cross(dt).normalized()
			if nrm.length_squared() < 0.5 or nrm.dot(p - ctr) < 0.0:
				nrm = -nrm if nrm.length_squared() > 0.5 else (p - ctr).normalized()
			k.add_vertex(p, nrm, Vector2(float(j) / segs, f), paint.call(f, th, p))
	var stride := segs + 1
	for r in rings:
		for j in segs:
			var a0 := base_i + r * stride + j
			k.quad(a0, a0 + 1, a0 + stride, a0 + stride + 1)
	# Tampas nas pontas.
	for end in 2:
		var t := t0 if end == 0 else t1
		var s := _loft_at(st, t)
		var ctr: Vector3 = w * t + L["u"] * s[0] + L["v"] * s[1]
		var nn := -w if end == 0 else w
		var ci := k.add_vertex(ctr, nn, Vector2.ZERO, paint.call(float(end), 0.0, ctr))
		var first := k.verts.size()
		for j in segs:
			var p := _loft_pt(L, t, TAU * float(j) / float(segs))
			k.add_vertex(p, nn, Vector2.ZERO, paint.call(float(end), TAU * float(j) / float(segs), p))
		for j in segs:
			k.tri(ci, first + j, first + (j + 1) % segs)


## Ponto `p` (coordenadas do tilt_root) dentro do loft, com folga `margin` (m, aproximada).
static func _loft_inside(L: Dictionary, p: Vector3, margin: float) -> bool:
	var st: Array = L["st"]
	var t := p.dot(L["w"])
	if t < float(st[0][0]) + margin or t > float(st[st.size() - 1][0]) - margin:
		return false
	var s := _loft_at(st, t)
	var a := absf(p.dot(L["u"]) - s[0]) / maxf(s[2] - margin, 0.001)
	var b := absf(p.dot(L["v"]) - s[1]) / maxf(s[3] - margin, 0.001)
	var n := float(L["n"])
	return pow(a, n) + pow(b, n) < 1.0


## Algum volume da carenagem contém `p`?
func inside_body(p: Vector3, margin: float = 0.005) -> String:
	for L in solids:
		if _loft_inside(L, p, margin):
			return L["name"]
	return ""


# ------------------------------------------------------------------ construção

func build(cfg: PlayerConfig) -> void:
	var prev_detail := MeshKit.detail
	MeshKit.detail = DETAIL
	var kc := cfg.kart_color
	paint_color = kc
	suit_color = cfg.suit_color
	var paint := _mat(0.3, 0.05, true)
	paint.clearcoat = 0.55
	paint.clearcoat_roughness = 0.14
	var plastic := _mat(0.55)
	var rubber := _mat(0.92)
	rubber.metallic_specular = 0.2
	var chrome := _mat(0.18, 1.0)
	var alu := _mat(0.38, 0.85)
	var dark := Color(0.06, 0.06, 0.07)
	var white := Palette.WHITE
	var steel := Color(0.8, 0.82, 0.86)

	body_root = Node3D.new()
	body_root.name = "Body"
	add_child(body_root)
	tilt_root = Node3D.new()
	tilt_root.name = "Tilt"
	body_root.add_child(tilt_root)

	_build_bodywork(kc, paint)
	_build_chassis(steel, dark, chrome, alu)
	_build_seat(dark)
	_build_cockpit(kc, dark, plastic, alu)
	_build_decals(cfg, kc, white, paint)
	_build_driver(cfg)
	_build_wheels(rubber, chrome, kc)
	MeshKit.detail = prev_detail
	for vi: VisualInstance3D in find_children("*", "VisualInstance3D", true, false):
		vi.layers |= RIM_LAYER
	_apply_lod()
	pool_key = key_of(cfg)
	_base_nodes.clear()
	for n in find_children("*", "", true, false):
		_base_nodes[n.get_instance_id()] = true


## Otimização (LOD por distância + sombras): peças pequenas não projetam sombra (o passe de sombra do
## sol é o mais caro no split-screen) e somem quando ficam com poucos pixels na tela. Margem de
## histerese evita piscar na fronteira.
const LOD_SMALL := 32.0     ## mãos, dedos, pedais, placa: invisíveis além disso
const LOD_MEDIUM := 70.0    ## braços, volante, escapamento
const NO_SHADOW := ["Hand", "Index", "Middle", "Pedals", "NumberPlate", "SteeringWheel", "Exhaust", "Forearm", "Arm"]


func _apply_lod() -> void:
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		var path := String(get_path_to(mi))
		for key: String in NO_SHADOW:
			if path.contains(key):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				break
		var far := 0.0
		if path.contains("Hand") or path.contains("Index") or path.contains("Middle") or path.contains("Pedals") or path.contains("NumberPlate"):
			far = LOD_SMALL
		elif path.contains("Arm") or path.contains("SteeringWheel") or path.contains("Exhaust"):
			far = LOD_MEDIUM
		if far > 0.0:
			mi.visibility_range_end = far
			mi.visibility_range_end_margin = 4.0


static func key_of(cfg: PlayerConfig) -> String:
	return "%d|%s|%d" % [cfg.character, cfg.kart_color.to_html(), cfg.player_index]


## Modelo pronto para `cfg`: do pool se houver, senão monta um novo.
static func acquire(cfg: PlayerConfig) -> KartModel:
	var list: Array = _pool.get(key_of(cfg), [])
	while not list.is_empty():
		var m: KartModel = list.pop_back()
		if is_instance_valid(m):
			return m
	var nm := KartModel.new()
	nm.build(cfg)
	return nm


## Devolve ao pool: tira do pai, remove o que foi acrescentado depois do build e zera animações.
func release() -> void:
	if get_parent() != null:
		get_parent().remove_child(self)
	for n in find_children("*", "", true, false):
		if not _base_nodes.has(n.get_instance_id()) and is_instance_valid(n) and n.get_parent() != null:
			n.get_parent().remove_child(n)
			n.queue_free()
	driver.reset_pose()
	_steer_s = 0.0
	_accel = 0.0
	_prev_speed = 0.0
	_hop_t = 1.0
	_roll = 0.0
	_lean = 0.0
	body_root.visible = true
	body_root.position = Vector3.ZERO
	tilt_root.rotation = Vector3.ZERO
	driver.rotation = Vector3.ZERO
	transform = Transform3D.IDENTITY
	var total := 0
	for k in _pool:
		total += (_pool[k] as Array).size()
	if total >= POOL_MAX:
		queue_free()
		return
	if not _pool.has(pool_key):
		_pool[pool_key] = []
	(_pool[pool_key] as Array).append(self)


## Libera todos os modelos guardados (encerramento do jogo).
static func clear_pool() -> void:
	for k in _pool:
		for m in _pool[k]:
			if is_instance_valid(m):
				m.free()
	_pool.clear()


func _build_bodywork(kc: Color, paint: Material) -> void:
	var white := Color(0.96, 0.96, 0.97)
	var black := Color(0.07, 0.07, 0.08)
	var p := MeshKit.new()
	# Faixas duplas brancas contínuas (bico -> painel): |x| entre 0,055 e 0,1 (com vão no meio).
	var stripe := func(x: float) -> bool:
		return absf(x) > 0.055 and absf(x) < 0.1
	# Spoiler dianteiro: baixo e afilado (superelipse mais "quadrada"), metade de baixo em plástico preto.
	var front := {"name": "spoiler", "w": Vector3.RIGHT, "u": Vector3.BACK, "v": Vector3.UP, "n": 4.0, "st": [
		[-0.9, -1.18, 0.12, 0.1, 0.035], [-0.84, -1.18, 0.14, 0.15, 0.06], [-0.6, -1.17, 0.135, 0.17, 0.058],
		[-0.3, -1.14, 0.14, 0.19, 0.065], [0.0, -1.12, 0.15, 0.22, 0.075],
		[0.3, -1.14, 0.14, 0.19, 0.065], [0.6, -1.17, 0.135, 0.17, 0.058], [0.84, -1.18, 0.14, 0.15, 0.06],
		[0.9, -1.18, 0.12, 0.1, 0.035]]}
	_loft(p, front, 56, 32, func(_f: float, th: float, q: Vector3) -> Color:
		var sy := sin(th)
		if sy < -0.15:
			return black
		if sy < 0.05:
			return kc.darkened(0.25)
		if stripe.call(q.x) and sy > 0.3:
			return white
		return kc)
	# Painel frontal (nassau): à frente dos pés, afinando para cima até a coluna de direção.
	var nassau := {"name": "nassau", "w": Vector3.UP, "u": Vector3.RIGHT, "v": Vector3.BACK, "n": 4.0, "st": [
		[0.12, 0.0, -0.9, 0.3, 0.07], [0.3, 0.0, -0.875, 0.27, 0.055], [0.48, 0.0, -0.845, 0.2, 0.045], [0.6, 0.0, -0.825, 0.11, 0.035]]}
	_loft(p, nassau, 16, 32, func(f: float, _th: float, q: Vector3) -> Color:
		if f < 0.12 or f > 0.9:
			return black
		if stripe.call(q.x):
			return white
		return kc)
	# Pontões laterais: mais "quadrados" (n = 4), ombro superior com faixa dupla, saia preta.
	for s: float in [-1.0, 1.0]:
		var pod := {"name": "pod", "w": Vector3.BACK, "u": Vector3.RIGHT, "v": Vector3.UP, "n": 4.0, "st": [
			[-0.42, s * 0.7, 0.19, 0.07, 0.045], [-0.33, s * 0.71, 0.2, 0.15, 0.085], [0.0, s * 0.72, 0.205, 0.17, 0.1],
			[0.33, s * 0.73, 0.205, 0.17, 0.1], [0.47, s * 0.74, 0.19, 0.12, 0.07]]}
		_loft(p, pod, 32, 40, func(_f: float, th: float, _q: Vector3) -> Color:
			var sy := sin(th)
			var cx := cos(th) * s
			if sy < -0.35:
				return black
			if cx > 0.55 and ((sy > 0.1 and sy < 0.2) or (sy > 0.27 and sy < 0.37)):
				return white
			return kc)
		solids.append(pod)
		# Entradas de ar no alto do pontão (3 fendas escuras) e ponteira de borracha preta.
		for j in 3:
			p.rounded_prism(Transform3D(Basis.IDENTITY, Vector3(s * 0.7, 0.296, -0.24 + j * 0.07)), 0.2, 0.028, 0.012, 0.012, 2, black, Color(0.02, 0.02, 0.025), false)
	# Para-choque traseiro (plástico preto com faixa na cor do kart).
	var bumper := {"name": "bumper", "w": Vector3.RIGHT, "u": Vector3.BACK, "v": Vector3.UP, "n": 3.0, "st": [
		[-0.86, 1.2, 0.17, 0.06, 0.045], [-0.78, 1.22, 0.17, 0.1, 0.07], [0.0, 1.24, 0.17, 0.1, 0.07],
		[0.78, 1.22, 0.17, 0.1, 0.07], [0.86, 1.2, 0.17, 0.06, 0.045]]}
	_loft(p, bumper, 32, 24, func(_f: float, th: float, _q: Vector3) -> Color:
		return kc if sin(th) > 0.55 else black)
	solids.append(front)
	solids.append(nassau)
	solids.append(bumper)
	var mi := MeshInstance3D.new()
	mi.name = "Paint"
	mi.mesh = p.commit(null, paint)
	tilt_root.add_child(mi)


func _build_chassis(steel: Color, dark: Color, chrome: Material, alu: Material) -> void:
	var m := MeshKit.new()
	var tube := 0.032
	for s: float in [-1.0, 1.0]:
		var a := Vector3(s * 0.36, 0.11, -0.98)
		var b := Vector3(s * 0.42, 0.11, -0.45)
		var c := Vector3(s * 0.44, 0.11, 1.02)
		_seg(m, a, b, tube, tube, 10, steel)
		_seg(m, b, c, tube, tube, 10, steel)
		m.sphere(Transform3D(Basis.IDENTITY, b), tube, 6, 10, steel)
		_seg(m, a, Vector3(s * 0.52, 0.12, -1.04), 0.022, 0.022, 8, steel)                       # suporte do spoiler
		_seg(m, Vector3(s * 0.42, 0.11, -0.25), Vector3(s * 0.6, 0.13, -0.25), 0.022, 0.022, 8, steel)  # suportes dos pontões
		_seg(m, Vector3(s * 0.43, 0.11, 0.3), Vector3(s * 0.6, 0.13, 0.3), 0.022, 0.022, 8, steel)
		_seg(m, c, Vector3(s * 0.62, 0.15, 1.16), 0.025, 0.025, 8, steel)                         # suporte do para-choque
		# Manga de eixo dianteira (C + pino) e ponta de eixo.
		_seg(m, Vector3(s * 0.4, 0.12, -0.7), Vector3(s * 0.54, 0.13, -0.7), 0.028, 0.028, 8, steel)
		_seg(m, Vector3(s * 0.55, 0.13, -0.72), Vector3(s * 0.57, 0.36, -0.68), 0.022, 0.022, 8, steel)
		_seg(m, Vector3(s * 0.56, FRONT_R, -0.7), Vector3(s * 0.64, FRONT_R, -0.7), 0.02, 0.02, 8, steel)
		# Barra de direção (coluna -> manga).
		_seg(m, Vector3(0, 0.2, -0.7), Vector3(s * 0.55, 0.2, -0.64), 0.012, 0.012, 6, steel)
		# Mancais do eixo traseiro e suportes do banco.
		_seg(m, Vector3(s * 0.44, 0.11, 0.8), Vector3(s * 0.44, REAR_R, 0.8), 0.028, 0.028, 8, steel)
		m.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(s * 0.44 - 0.035, REAR_R, 0.8)), 0.055, 0.055, 0.07, 14, dark)
		_seg(m, Vector3(s * 0.2, 0.11, 0.38), Vector3(s * 0.22, 0.48, 0.56), 0.016, 0.016, 6, steel)
	for z: float in [-0.95, -0.45, 0.22, 1.0]:
		_seg(m, Vector3(-0.44, 0.11, z), Vector3(0.44, 0.11, z), tube, tube, 10, steel)
	_seg(m, Vector3(-0.88, REAR_R, 0.8), Vector3(0.88, REAR_R, 0.8), 0.04, 0.04, 12, steel)       # eixo traseiro
	# Coluna de direção: do apoio no assoalho até o centro do volante (eixo = normal do volante).
	var sw_c := Vector3(0, 0.8, -0.27)
	var col_dir := Basis(Vector3.RIGHT, WHEEL_TILT) * Vector3.UP
	var col_base := sw_c - col_dir * ((sw_c.y - 0.14) / col_dir.y)
	_seg(m, col_base, sw_c - col_dir * 0.03, 0.022, 0.022, 10, steel)
	m.sphere(Transform3D(Basis.IDENTITY, col_base), 0.03, 6, 10, steel)
	var mi := MeshInstance3D.new()
	mi.name = "Chassis"
	mi.mesh = m.commit(null, chrome)
	tilt_root.add_child(mi)
	# Assoalho (fibra escura), tanque, motor, transmissão, freio e escapamento.
	var d := MeshKit.new()
	d.rounded_prism(Transform3D(Basis.IDENTITY, Vector3(0, 0.085, -0.15)), 0.82, 1.56, 0.022, 0.12, 4, Color(0.1, 0.1, 0.11), Color(0.13, 0.13, 0.15), true)
	d.rounded_prism(Transform3D(Basis.IDENTITY, Vector3(0, 0.11, -0.47)), 0.14, 0.26, 0.17, 0.05, 3, Color(0.85, 0.86, 0.82), Color(0.9, 0.9, 0.88), true)  # tanque
	d.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.28, -0.52)), 0.025, 0.025, 0.02, 10, Color(0.15, 0.15, 0.16))     # tampa
	# Motor (lado direito, atrás do banco): bloco, cabeçote aletado, vela, carburador e filtro.
	var eng := Vector3(0.43, 0.14, 0.6)
	d.rounded_prism(Transform3D(Basis.IDENTITY, eng), 0.2, 0.26, 0.24, 0.05, 3, Color(0.42, 0.43, 0.45), Color(0.5, 0.51, 0.53), true)
	for j in 6:
		d.cylinder(Transform3D(Basis.IDENTITY, eng + Vector3(0, 0.24 + 0.022 * j, 0)), 0.1 - 0.006 * j, 0.1 - 0.006 * j, 0.011, 16, Color(0.6, 0.61, 0.63))
	d.cylinder(Transform3D(Basis.IDENTITY, eng + Vector3(0, 0.37, 0)), 0.016, 0.012, 0.05, 8, Color(0.85, 0.85, 0.9))
	d.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), eng + Vector3(-0.08, 0.15, -0.02)), 0.035, 0.035, 0.08, 10, Color(0.3, 0.3, 0.32))
	d.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), eng + Vector3(-0.2, 0.15, -0.02)), 0.065, 0.065, 0.12, 16, Color(0.08, 0.08, 0.09))   # filtro de ar
	# Coroa + corrente (lado direito) e disco de freio com pinça vermelha (lado esquerdo).
	var ax := Basis(Vector3.FORWARD, PI * 0.5)
	d.cylinder(Transform3D(ax, Vector3(0.31, REAR_R, 0.8)), 0.11, 0.11, 0.012, 24, Color(0.25, 0.25, 0.27))
	d.box(Transform3D(_basis_y(Vector3(0, 0.0, 1.0)), Vector3(0.315, REAR_R + 0.1, 0.7)), Vector3(0.01, 0.2, 0.012), Color(0.12, 0.12, 0.13))
	d.box(Transform3D(_basis_y(Vector3(0, 0.0, 1.0)), Vector3(0.315, REAR_R - 0.1, 0.7)), Vector3(0.01, 0.2, 0.012), Color(0.12, 0.12, 0.13))
	d.cylinder(Transform3D(ax, Vector3(-0.31, REAR_R, 0.8)), 0.12, 0.12, 0.014, 24, Color(0.55, 0.56, 0.58))
	d.rounded_prism(Transform3D(Basis.IDENTITY, Vector3(-0.31, REAR_R + 0.09, 0.8)), 0.05, 0.09, 0.06, 0.015, 2, Color(0.85, 0.08, 0.08), Color(0.9, 0.12, 0.1), true)
	var mi2 := MeshInstance3D.new()
	mi2.name = "Mechanics"
	mi2.mesh = d.commit(null, alu)
	tilt_root.add_child(mi2)
	# Escapamento: coletor do cabeçote -> silencioso transversal atrás do banco -> 2 ponteiras.
	var ex := MeshKit.new()
	var ec := Color(0.62, 0.6, 0.58)
	var h0 := eng + Vector3(0.0, 0.3, 0.08)
	var h1 := Vector3(0.43, 0.5, 0.86)
	var h2 := Vector3(0.3, 0.44, 0.99)
	_seg(ex, h0, h1, 0.032, 0.034, 12, ec)
	ex.sphere(Transform3D(Basis.IDENTITY, h1), 0.034, 6, 12, ec)
	_seg(ex, h1, h2, 0.034, 0.038, 12, ec)
	_seg(ex, Vector3(-0.3, 0.42, 1.05), Vector3(0.3, 0.42, 1.05), 0.075, 0.075, 18, Color(0.72, 0.72, 0.74))
	for s: float in [-1.0, 1.0]:
		ex.sphere(Transform3D(Basis.IDENTITY.scaled(Vector3(0.4, 1, 1)), Vector3(s * 0.3, 0.42, 1.05)), 0.075, 8, 14, Color(0.72, 0.72, 0.74))
		_seg(ex, Vector3(s * 0.2, 0.42, 1.1), Vector3(s * 0.2, 0.42, 1.31), 0.03, 0.032, 12, ec)
		_seg(ex, Vector3(s * 0.2, 0.42, 1.31), Vector3(s * 0.2, 0.42, 1.36), 0.038, 0.038, 12, Color(0.05, 0.05, 0.05))
	var mi3 := MeshInstance3D.new()
	mi3.name = "Exhaust"
	mi3.mesh = ex.commit(null, chrome)
	tilt_root.add_child(mi3)


## Banco concha: casca com espessura (face interna e externa + bordas), envolvendo costas e quadril,
## laterais baixando para a frente; assento fino sob o quadril.
func _build_seat(_dark: Color) -> void:
	var seat_mat := _mat(0.8)
	seat_mat.normal_enabled = true
	seat_mat.normal_texture = SEAT_NORMAL
	seat_mat.normal_scale = 0.35
	seat_mat.uv1_triplanar = true
	seat_mat.uv1_scale = Vector3(3, 3, 3)
	var sc := Color(0.07, 0.07, 0.075)
	var k := MeshKit.new()
	var cols := MeshKit.seg_count(24)
	var rows := MeshKit.seg_count(10)
	var th_max := 1.85
	var thick := 0.03
	# [camada][linha][coluna] -> índice de vértice.
	var grid := []
	for layer in 2:
		var lay := []
		for r in rows + 1:
			var row := []
			for c in cols + 1:
				var th := lerpf(-th_max, th_max, float(c) / cols)
				var top := lerpf(0.86, 0.58, pow(absf(th) / th_max, 1.5))
				var y := lerpf(0.36, top, float(r) / rows)
				var rad := Vector3(sin(th) * 0.18, 0.0, cos(th) * 0.25).normalized()
				var p := Vector3(sin(th) * 0.25, y, 0.32 + cos(th) * 0.18 + (y - 0.36) * 0.12)
				var nrm := -rad if layer == 0 else rad
				if layer == 1:
					p += rad * thick
				row.append(k.add_vertex(p, nrm, Vector2(float(c) / cols, y), sc))
			lay.append(row)
		grid.append(lay)
	for layer in 2:
		for r in rows:
			for c in cols:
				k.quad(grid[layer][r][c], grid[layer][r][c + 1], grid[layer][r + 1][c], grid[layer][r + 1][c + 1])
	# Bordas (topo e frentes laterais) unindo as camadas.
	var edge := func(i0: int, i1: int, j0: int, j1: int, n: Vector3) -> void:
		var a := k.add_vertex(k.verts[i0], n, Vector2.ZERO, sc)
		var b := k.add_vertex(k.verts[i1], n, Vector2.ZERO, sc)
		var c2 := k.add_vertex(k.verts[j0], n, Vector2.ZERO, sc)
		var d := k.add_vertex(k.verts[j1], n, Vector2.ZERO, sc)
		k.quad(a, b, c2, d)
	for c in cols:
		edge.call(grid[0][rows][c], grid[0][rows][c + 1], grid[1][rows][c], grid[1][rows][c + 1], Vector3.UP)
	for r in rows:
		for c: int in [0, cols]:
			var th := -th_max if c == 0 else th_max
			edge.call(grid[0][r][c], grid[0][r + 1][c], grid[1][r][c], grid[1][r + 1][c], Vector3(signf(th) * 0.3, 0, -1).normalized())
	# Assento sob o quadril.
	_blob(k, Vector3(0, 0.345, 0.32), Vector3(0.24, 0.035, 0.2), sc)
	var mi := MeshInstance3D.new()
	mi.name = "Seat"
	mi.mesh = k.commit(null, seat_mat)
	tilt_root.add_child(mi)


## Volante de 3 raios (aro emborrachado, cubo com display na cor do kart) e pedais.
func _build_cockpit(kc: Color, dark: Color, plastic: Material, alu: Material) -> void:
	steering_wheel = Node3D.new()
	steering_wheel.name = "SteeringWheel"
	steering_wheel.position = Vector3(0, 0.8, -0.27)
	steering_wheel.basis = Basis(Vector3.RIGHT, WHEEL_TILT)
	tilt_root.add_child(steering_wheel)
	var sw := MeshKit.new()
	var rim_r := 0.13
	var n := MeshKit.seg_count(28)
	for i in n:
		var a0 := TAU * float(i) / n
		var a1 := TAU * float(i + 1) / n
		var p0 := Vector3(cos(a0) * rim_r, 0, sin(a0) * rim_r)
		var p1 := Vector3(cos(a1) * rim_r, 0, sin(a1) * rim_r)
		_seg(sw, p0, p1, 0.017, 0.017, 10, dark)
		sw.sphere(Transform3D(Basis.IDENTITY, p0), 0.017, 5, 10, dark)
	var sw_mi := MeshInstance3D.new()
	sw_mi.mesh = sw.commit(null, _mat(0.85))
	steering_wheel.add_child(sw_mi)
	var hub := MeshKit.new()
	for a: float in [0.0, PI, PI * 1.5]:
		_seg(hub, Vector3.ZERO, Vector3(cos(a), 0, sin(a)) * (rim_r - 0.01), 0.012, 0.01, 8, Color(0.7, 0.72, 0.75))
	hub.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.02, 0)), 0.045, 0.045, 0.035, 18, dark)
	hub.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.017, 0.0)), Vector3(0.07, 0.006, 0.04), kc)
	hub.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.0205, 0.0)), Vector3(0.05, 0.002, 0.025), Color(0.1, 0.9, 0.5))
	sw_mi.mesh = hub.commit(sw_mi.mesh, alu)
	# Pedais à frente das botas.
	var pd := MeshKit.new()
	for s: float in [-1.0, 1.0]:
		var pc := Vector3(s * 0.13, 0.36, -0.77)
		pd.box(Transform3D(Basis(Vector3.RIGHT, -0.35), pc), Vector3(0.07, 0.11, 0.012), Color(0.6, 0.61, 0.63))
		_seg(pd, Vector3(s * 0.13, 0.11, -0.79), pc + Vector3(0, -0.04, -0.01), 0.008, 0.008, 6, Color(0.6, 0.61, 0.63))
	var pd_mi := MeshInstance3D.new()
	pd_mi.name = "Pedals"
	pd_mi.mesh = pd.commit(null, plastic)
	tilt_root.add_child(pd_mi)


## Placa de número no painel frontal (P1 = 1, P2 = 2) e adesivos UNIFEOB nos pontões.
func _build_decals(cfg: PlayerConfig, kc: Color, white: Color, paint: Material) -> void:
	var plate := MeshKit.new()
	var pz := -0.928
	plate.rounded_prism(Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.15), Vector3(0, 0.36, pz + 0.014)), 0.2, 0.17, 0.01, 0.035, 3, Color(0.05, 0.05, 0.06), Color(0.05, 0.05, 0.06), true)
	plate.rounded_prism(Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.15), Vector3(0, 0.36, pz + 0.006)), 0.175, 0.145, 0.01, 0.028, 3, Color(1.0, 0.84, 0.08), Color(1.0, 0.86, 0.1), true)
	var plate_mi := MeshInstance3D.new()
	plate_mi.name = "NumberPlate"
	plate_mi.mesh = plate.commit(null, paint)
	tilt_root.add_child(plate_mi)
	var num := Label3D.new()
	num.name = "Number"
	num.text = str(cfg.player_index + 1) if cfg.player_index >= 0 else ""
	num.font_size = 96   # fonte padrão: o "1" da fonte do título parece um "7"
	num.pixel_size = 0.0017
	num.outline_size = 14
	num.outline_modulate = Color(0.04, 0.04, 0.05)
	num.modulate = Color(0.04, 0.04, 0.05)
	num.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	num.double_sided = false
	num.position = Vector3(0, 0.355, pz - 0.006)
	num.rotation = Vector3(-0.15, PI, 0)
	tilt_root.add_child(num)
	for s: float in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = "UNIFEOB"
		l.font = UiKit.FONT
		l.font_size = 40
		l.pixel_size = 0.0017
		l.outline_size = 8
		l.modulate = white
		l.outline_modulate = Palette.BLUE if kc != Palette.BLUE else Palette.MAGENTA
		l.position = Vector3(s * 0.905, 0.19, 0.12)
		l.rotation = Vector3(0, s * PI * 0.5, 0)
		l.double_sided = false
		tilt_root.add_child(l)


func _build_driver(cfg: PlayerConfig) -> void:
	driver = Characters.make_driver(cfg.character)
	driver.position = AlienDriver.ORIGIN
	tilt_root.add_child(driver)
	driver.build(cfg.character, suit_color)
	character = driver.character


## Pose do piloto (volante, vitória ou derrota).
func set_pose(p: AlienDriver.Pose) -> void:
	driver.set_pose(p)


## Ponto de pega no volante (lado s = -1/+1) no espaço do piloto; acompanha o giro do volante.
func _grip(s: float) -> Vector3:
	var p := steering_wheel.transform * Vector3(s * 0.13, 0.0, 0.0)
	return driver.transform.affine_inverse() * p


## Anel plano (ou arco de a0 a a1) no plano YZ em x, voltado para nx (+1/-1).
static func _annulus(k: MeshKit, x: float, nx: float, r0: float, r1: float, a0: float, a1: float, segs: int, c: Color) -> void:
	segs = MeshKit.seg_count(segs)
	var base_i := k.verts.size()
	for i in segs + 1:
		var a := lerpf(a0, a1, float(i) / segs)
		var d := Vector3(0, cos(a), sin(a))
		k.add_vertex(Vector3(x, 0, 0) + d * r0, Vector3(nx, 0, 0), Vector2.ZERO, c)
		k.add_vertex(Vector3(x, 0, 0) + d * r1, Vector3(nx, 0, 0), Vector2.ZERO, c)
	for i in segs:
		var i0 := base_i + i * 2
		k.quad(i0, i0 + 1, i0 + 2, i0 + 3)


## Pneu slick com ombro arredondado e escrita branca na lateral; roda de liga na cor do kart
## (6 raios, borda polida, fundo escuro, porca central).
func _wheel_mesh(r: float, w: float, rubber: Material, rim_mat: Material, chrome: Material, kc: Color) -> ArrayMesh:
	var tire := MeshKit.new()
	var tc := Color(0.055, 0.055, 0.06)
	var ax := Basis(Vector3.FORWARD, PI * 0.5)  # eixo Y do cilindro -> +X (cresce a partir da origem)
	tire.cylinder(Transform3D(ax, Vector3(-w * 0.5, 0, 0)), r * 0.8, r * 0.8, w, 28, tc)
	tire.cylinder(Transform3D(ax, Vector3(-w * 0.48, 0, 0)), r * 0.92, r * 0.92, w * 0.96, 28, tc, false)
	tire.cylinder(Transform3D(ax, Vector3(-w * 0.43, 0, 0)), r * 0.975, r * 0.975, w * 0.86, 28, tc, false)
	tire.cylinder(Transform3D(ax, Vector3(-w * 0.38, 0, 0)), r, r, w * 0.76, 28, tc, false)
	var mesh := tire.commit(null, rubber)
	var txt := MeshKit.new()
	for s: float in [-1.0, 1.0]:
		var sx := s * (w * 0.48 + 0.0015)
		for arc: Array in [[0.35, 2.4], [3.5, 5.55]]:
			_annulus(txt, sx, s, r * 0.835, r * 0.885, arc[0], arc[1], 20, Color(0.93, 0.93, 0.93))
	txt.commit(mesh, _mat(0.7))
	var rim := MeshKit.new()
	var rc := kc.darkened(0.1)
	var dark := Color(0.1, 0.1, 0.11)
	rim.cylinder(Transform3D(ax, Vector3(-w * 0.5 - 0.004, 0, 0)), r * 0.6, r * 0.6, w + 0.008, 24, dark)
	for s: float in [-1.0, 1.0]:
		var face := s * (w * 0.5 + 0.006)
		_annulus(rim, face, s, r * 0.5, r * 0.6, 0.0, TAU, 32, rc)
		for i in 6:
			var a := TAU * float(i) / 6.0
			var bb := Basis(Vector3.RIGHT, a)
			rim.box(Transform3D(bb, Vector3(face + s * 0.006, 0, 0) + bb * Vector3(0, r * 0.3, 0)), Vector3(0.012, r * 0.42, 0.034), rc)
		rim.cylinder(Transform3D(ax, Vector3(face + (0.0 if s > 0.0 else -0.02), 0, 0)), r * 0.16, r * 0.14, 0.02, 14, rc)
	rim.commit(mesh, rim_mat)
	var lip := MeshKit.new()
	for s: float in [-1.0, 1.0]:
		var face := s * (w * 0.5 + 0.0065)
		_annulus(lip, face, s, r * 0.575, r * 0.605, 0.0, TAU, 32, Color(0.85, 0.86, 0.88))
		lip.cylinder(Transform3D(ax, Vector3(face + (0.012 if s > 0.0 else -0.032), 0, 0)), r * 0.06, r * 0.06, 0.02, 6, Color(0.85, 0.86, 0.88))
	lip.commit(mesh, chrome)
	return mesh


func _build_wheels(rubber: Material, chrome: Material, kc: Color) -> void:
	var rim_mat := _mat(0.32, 0.7)
	var front := _wheel_mesh(FRONT_R, 0.26, rubber, rim_mat, chrome, kc)
	var rear := _wheel_mesh(REAR_R, 0.4, rubber, rim_mat, chrome, kc)
	var wpos: Array[Vector3] = [Vector3(-0.74, FRONT_R, -0.7), Vector3(0.74, FRONT_R, -0.7), Vector3(-0.8, REAR_R, 0.8), Vector3(0.8, REAR_R, 0.8)]
	for i in 4:
		var pivot := Node3D.new()
		pivot.name = "Wheel%d" % i
		pivot.position = wpos[i]
		body_root.add_child(pivot)
		var spin := Node3D.new()
		spin.name = "Spin"
		pivot.add_child(spin)
		var w := MeshInstance3D.new()
		w.mesh = front if i < 2 else rear
		spin.add_child(w)
		wheels.append(spin)
		wheel_pivots.append(pivot)
		_spin.append(0.0)
		wheel_radius.append(FRONT_R if i < 2 else REAR_R)
		if i < 2:
			front_wheels.append(pivot)


## Pulinho curto (início do drift).
func hop() -> void:
	_hop_t = 0.0


## Anima rodas (giro pela velocidade, esterço), volante, rolagem da carroceria, inclinação do piloto e pulinho.
func animate(speed: float, steer: float, delta: float, drift_dir: float = 0.0) -> void:
	for i in wheels.size():
		_spin[i] = fmod(_spin[i] - speed * delta / wheel_radius[i], TAU)
		wheels[i].basis = Basis(Vector3.RIGHT, _spin[i])
	var st := steer
	if drift_dir != 0.0:
		st = clampf(drift_dir * 0.6 + steer * 0.4, -1.0, 1.0)
	# Direção amortecida (volante, rodas e piloto sem "estalos" quando o direcional vira de uma vez).
	var ks := 1.0 - exp(-14.0 * delta) if delta > 0.0 else 1.0
	_steer_s = lerpf(_steer_s, st, ks)
	st = _steer_s
	# Arrancada/freada: o piloto inclina levemente para trás/frente (aceleração suavizada).
	if delta > 0.0:
		_accel = lerpf(_accel, (speed - _prev_speed) / delta, 1.0 - exp(-6.0 * delta))
	_prev_speed = speed
	for p in front_wheels:
		p.rotation.y = -st * 0.45
	steering_wheel.basis = Basis(Vector3.RIGHT, WHEEL_TILT) * Basis(Vector3.UP, -st * 1.0)
	var k := 1.0 - exp(-8.0 * delta) if delta > 0.0 else 1.0
	var fast := clampf(absf(speed) / 12.0, 0.0, 1.0)
	_roll = lerpf(_roll, st * 0.06 * fast, k)
	_lean = lerpf(_lean, -st * 0.2 * fast - drift_dir * 0.07, k)
	var y := 0.0
	if _hop_t < 1.0:
		_hop_t = minf(_hop_t + delta / 0.3, 1.0)
		y = sin(_hop_t * PI) * 0.32
	body_root.position = Vector3(0, y, 0)
	tilt_root.rotation = Vector3(0, 0, _roll)
	driver.rotation = Vector3(clampf(_accel * 0.005, -0.07, 0.07), 0, _lean)
	driver.animate_rig(delta, st, _grip(-1.0), _grip(1.0))
