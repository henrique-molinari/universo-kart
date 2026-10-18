class_name TrackPath
extends Node3D
## Linha central do circuito e API de consulta usada por malhas, IA, corrida e itens.
##
## Convenções:
##  - "offset" = distância (m) ao longo da linha central a partir da linha de largada (0..length).
##  - "lateral" = deslocamento (m) para a DIREITA do sentido de corrida (negativo = esquerda).
##  - O nó deve ficar na origem sem rotação/escala (posições locais == globais).

signal built

enum Surface { ROAD, CURB, OFFROAD, OUTSIDE }

const SAMPLE_STEP := 1.0
const GRID_CELL := 24.0

@export var layout: TrackLayout

var curve: Curve3D
var length: float = 0.0
var sample_count: int = 0
var sample_step: float = SAMPLE_STEP
var is_built: bool = false

var _pos := PackedVector3Array()
var _fwd := PackedVector3Array()
var _right := PackedVector3Array()
var _up := PackedVector3Array()
var _curv := PackedFloat32Array()        # curvatura com sinal (+ = curva à esquerda)
var _curb_left := PackedFloat32Array()   # 0..1 (largura relativa da zebra)
var _curb_right := PackedFloat32Array()
var _bridge := PackedFloat32Array()      # 0..1, preenchido pela pista (ponte/viaduto)
var _bank := PackedFloat32Array()        # inclinação lateral (rad), + = lado direito mais alto
var _wall_l := PackedFloat32Array()      # lateral (m) da face interna da mureta esquerda
var _wall_r := PackedFloat32Array()      # idem, direita
var _style_l := PackedByteArray()        # TrackLayout.WallStyle por amostra
var _style_r := PackedByteArray()
var _surf_l := PackedByteArray()         # TrackLayout.Surface por amostra
var _surf_r := PackedByteArray()
var _max_wall: float = 0.0
var _grid: Dictionary = {}               # Vector2i -> PackedInt32Array


# ---------------------------------------------------------------- construção

func build() -> void:
	if is_built:
		return
	assert(layout != null and layout.control_points.size() >= 4, "TrackPath precisa de um TrackLayout válido")
	_build_curve()
	_build_samples()
	_build_curvature()
	_build_zones()
	_apply_bank()
	_build_curbs()
	_build_grid()
	is_built = true
	built.emit()


func _build_curve() -> void:
	curve = Curve3D.new()
	curve.bake_interval = 0.25
	var pts := layout.control_points
	var n := pts.size()
	for i in n + 1:
		var p := pts[i % n]
		var prev := pts[(i - 1 + n) % n]
		var next := pts[(i + 1) % n]
		var tangent := (next - prev).normalized()
		var d_in := p.distance_to(prev)
		var d_out := p.distance_to(next)
		curve.add_point(p, -tangent * d_in * layout.handle_scale, tangent * d_out * layout.handle_scale)
	length = curve.get_baked_length()


func _build_samples() -> void:
	sample_count = maxi(8, roundi(length / SAMPLE_STEP))
	sample_step = length / float(sample_count)
	_pos.resize(sample_count)
	_fwd.resize(sample_count)
	_right.resize(sample_count)
	_up.resize(sample_count)
	_bridge.resize(sample_count)
	_bridge.fill(0.0)
	for i in sample_count:
		_pos[i] = curve.sample_baked(i * sample_step, true)
	for i in sample_count:
		var a := _pos[(i - 1 + sample_count) % sample_count]
		var b := _pos[(i + 1) % sample_count]
		var f := (b - a).normalized()
		var r := f.cross(Vector3.UP).normalized()
		_fwd[i] = f
		_right[i] = r
		_up[i] = r.cross(f).normalized()


func _build_curvature() -> void:
	_curv.resize(sample_count)
	var raw := PackedFloat32Array()
	raw.resize(sample_count)
	var span := 3
	for i in sample_count:
		var f0 := _fwd[(i - span + sample_count) % sample_count]
		var f1 := _fwd[(i + span) % sample_count]
		var ang := atan2(f0.cross(f1).y, f0.dot(f1))
		raw[i] = ang / (2.0 * span * sample_step)
	_curv = _smooth(raw, 6)


## Valor de uma zona (t_início, t_fim) para cada amostra: 1 dentro, 0 fora (antes da suavização).
func _zone_mask(t0: float, t1: float) -> PackedFloat32Array:
	var m := PackedFloat32Array()
	m.resize(sample_count)
	for i in sample_count:
		var t := float(i) / float(sample_count)
		var inside := (t >= t0 and t <= t1) if t0 <= t1 else (t >= t0 or t <= t1)
		m[i] = 1.0 if inside else 0.0
	return m


func _build_zones() -> void:
	var blend := maxi(1, roundi(layout.zone_blend * 0.5 / sample_step))
	var hw := layout.road_width * 0.5
	# Recuos (acostamentos) por lado.
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(sample_count)
	right.resize(sample_count)
	left.fill(layout.runoff_width)
	right.fill(layout.runoff_width)
	for z in layout.runoff_zones:
		var m := _zone_mask(z.x, z.y)
		for i in sample_count:
			if m[i] > 0.5:
				if z.z >= 0.0:
					left[i] = z.z
				if z.w >= 0.0:
					right[i] = z.w
	left = _smooth(left, blend)
	right = _smooth(right, blend)
	_wall_l.resize(sample_count)
	_wall_r.resize(sample_count)
	_max_wall = 0.0
	for i in sample_count:
		_wall_l[i] = hw + left[i]
		_wall_r[i] = hw + right[i]
		_max_wall = maxf(_max_wall, maxf(_wall_l[i], _wall_r[i]))
	# Estilos de mureta e superfícies (valores discretos, sem suavização).
	_style_l.resize(sample_count)
	_style_r.resize(sample_count)
	_surf_l.resize(sample_count)
	_surf_r.resize(sample_count)
	_style_l.fill(TrackLayout.WallStyle.BARRIER)
	_style_r.fill(TrackLayout.WallStyle.BARRIER)
	_surf_l.fill(TrackLayout.Surface.GRASS)
	_surf_r.fill(TrackLayout.Surface.GRASS)
	for z in layout.wall_style_zones:
		var m := _zone_mask(z.x, z.y)
		for i in sample_count:
			if m[i] > 0.5:
				if z.z <= 0.0:
					_style_l[i] = int(z.w)
				if z.z >= 0.0:
					_style_r[i] = int(z.w)
	for z in layout.surface_zones:
		var m := _zone_mask(z.x, z.y)
		for i in sample_count:
			if m[i] > 0.5:
				if z.z <= 0.0:
					_surf_l[i] = int(z.w)
				if z.z >= 0.0:
					_surf_r[i] = int(z.w)
	# Inclinação (banking) proporcional à curvatura dentro das zonas.
	var bank := PackedFloat32Array()
	bank.resize(sample_count)
	bank.fill(0.0)
	for z in layout.bank_zones:
		var m := _smooth(_zone_mask(z.x, z.y), blend * 2)
		var max_rad := deg_to_rad(z.z)
		for i in sample_count:
			var k := _curv[i]
			bank[i] += signf(k) * minf(absf(k) * 70.0, 1.0) * max_rad * m[i]
	_bank = _smooth(bank, blend)


## Gira os frames (direita/cima) em torno da frente conforme a inclinação.
func _apply_bank() -> void:
	for i in sample_count:
		var a := _bank[i]
		if absf(a) < 0.0001:
			continue
		var r := _right[i]
		var u := _up[i]
		_right[i] = (r * cos(a) + u * sin(a)).normalized()
		_up[i] = (u * cos(a) - r * sin(a)).normalized()


func _build_curbs() -> void:
	var left_raw := PackedFloat32Array()
	var right_raw := PackedFloat32Array()
	left_raw.resize(sample_count)
	right_raw.resize(sample_count)
	for i in sample_count:
		var k := _curv[i]
		var ak := absf(k)
		var inner := 1.0 if ak > layout.curb_inner_curvature else 0.0
		var outer := 1.0 if ak > layout.curb_outer_curvature else 0.0
		# Curva à esquerda (k > 0): lado interno = esquerda.
		left_raw[i] = inner if k > 0.0 else outer
		right_raw[i] = outer if k > 0.0 else inner
	# Dilata para cobrir entrada/saída da curva e suaviza as pontas.
	_curb_left = _smooth(_dilate(left_raw, 14), 3)
	_curb_right = _smooth(_dilate(right_raw, 14), 3)


func _build_grid() -> void:
	_grid.clear()
	for i in sample_count:
		var c := _cell_of(_pos[i])
		if not _grid.has(c):
			_grid[c] = PackedInt32Array()
		var arr: PackedInt32Array = _grid[c]
		arr.append(i)
		_grid[c] = arr


func _smooth(src: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var n := src.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var inv := 1.0 / float(radius * 2 + 1)
	for i in n:
		var acc := 0.0
		for k in range(-radius, radius + 1):
			acc += src[(i + k + n) % n]
		out[i] = acc * inv
	return out


func _dilate(src: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var n := src.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var m := 0.0
		for k in range(-radius, radius + 1):
			m = maxf(m, src[(i + k + n) % n])
		out[i] = m
	return out


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / GRID_CELL), floori(p.z / GRID_CELL))


# ---------------------------------------------------------------- dimensões

func get_half_width() -> float:
	return layout.road_width * 0.5


## Distância lateral (da linha central) da face interna das muretas.
## Sem argumentos: valor nominal. Com offset: lado -1 (esquerda), +1 (direita) ou 0 (o maior dos dois).
func get_wall_lateral(offset: float = -1.0, side: int = 0) -> float:
	if offset < 0.0 or not is_built:
		return layout.road_width * 0.5 + layout.runoff_width
	var it := _index_and_t(offset)
	var i := int(it.x)
	var j := (i + 1) % sample_count
	var l := lerpf(_wall_l[i], _wall_l[j], it.y)
	var r := lerpf(_wall_r[i], _wall_r[j], it.y)
	if side < 0:
		return l
	if side > 0:
		return r
	return maxf(l, r)


## Maior recuo de mureta de toda a volta.
func get_max_wall_lateral() -> float:
	return _max_wall


## Inclinação lateral (rad) no offset. Positivo = lado direito mais alto.
func get_bank(offset: float) -> float:
	var it := _index_and_t(offset)
	var i := int(it.x)
	return lerpf(_bank[i], _bank[(i + 1) % sample_count], it.y)


func get_wall_style(offset: float, side: int) -> int:
	var i := int(_index_and_t(offset + sample_step * 0.5).x)
	return _style_l[i] if side < 0 else _style_r[i]


func get_runoff_surface(offset: float, side: int) -> int:
	var i := int(_index_and_t(offset + sample_step * 0.5).x)
	return _surf_l[i] if side < 0 else _surf_r[i]


## Faixa [t_início, t_fim] (em offsets) do túnel, ou Vector2(-1, -1) se não houver.
func get_tunnel_range() -> Vector2:
	if layout.tunnel.x < 0.0:
		return Vector2(-1.0, -1.0)
	var c := layout.tunnel.x * length
	return Vector2(c - layout.tunnel.y * 0.5, c + layout.tunnel.y * 0.5)


# ---------------------------------------------------------------- amostragem por offset

func wrap_offset(offset: float) -> float:
	return fposmod(offset, length)


## Diferença com sinal mais curta de a até b (considera a volta).
func delta_offset(from_offset: float, to_offset: float) -> float:
	var d := fposmod(to_offset - from_offset, length)
	if d > length * 0.5:
		d -= length
	return d


func _index_and_t(offset: float) -> Vector2:
	var o := fposmod(offset, length) / sample_step
	var i := floori(o)
	return Vector2(i % sample_count, o - float(i))


func get_point_at(offset: float) -> Vector3:
	var it := _index_and_t(offset)
	var i := int(it.x)
	return _pos[i].lerp(_pos[(i + 1) % sample_count], it.y)


func get_forward(offset: float) -> Vector3:
	var it := _index_and_t(offset)
	var i := int(it.x)
	return _fwd[i].lerp(_fwd[(i + 1) % sample_count], it.y).normalized()


func get_right(offset: float) -> Vector3:
	var it := _index_and_t(offset)
	var i := int(it.x)
	return _right[i].lerp(_right[(i + 1) % sample_count], it.y).normalized()


func get_up(offset: float) -> Vector3:
	var it := _index_and_t(offset)
	var i := int(it.x)
	return _up[i].lerp(_up[(i + 1) % sample_count], it.y).normalized()


## Curvatura com sinal (1/raio). Positivo = curva à esquerda.
func get_curvature(offset: float) -> float:
	var it := _index_and_t(offset)
	var i := int(it.x)
	return lerpf(_curv[i], _curv[(i + 1) % sample_count], it.y)


func get_height(offset: float) -> float:
	return get_point_at(offset).y


## Transform orientado no sentido da corrida (-Z = frente, +X = direita, +Y = cima).
func get_transform_at(offset: float, lateral: float = 0.0, height: float = 0.0) -> Transform3D:
	var f := get_forward(offset)
	var r := get_right(offset)
	var u := r.cross(f).normalized()
	var origin := get_point_at(offset) + r * lateral + u * height
	return Transform3D(Basis(r, u, -f), origin)


## Posição no mundo a partir de (offset, lateral).
func to_world(offset: float, lateral: float, height: float = 0.0) -> Vector3:
	return get_point_at(offset) + get_right(offset) * lateral + get_up(offset) * height


## Intensidade (0..1) da zebra em um lado (-1 = esquerda, +1 = direita).
func get_curb(offset: float, side: int) -> float:
	var it := _index_and_t(offset)
	var i := int(it.x)
	var arr := _curb_left if side < 0 else _curb_right
	return lerpf(arr[i], arr[(i + 1) % sample_count], it.y)


func get_bridge(offset: float) -> float:
	var it := _index_and_t(offset)
	var i := int(it.x)
	return lerpf(_bridge[i], _bridge[(i + 1) % sample_count], it.y)


## Define a máscara de ponte por amostra (usada pelo construtor da pista).
func set_bridge_mask(mask: PackedFloat32Array) -> void:
	if mask.size() == sample_count:
		_bridge = mask


# ---------------------------------------------------------------- consultas por posição

## Offset do ponto mais próximo da linha central. `hint` (offset anterior) acelera a busca
## e evita saltos; sem hint, usa o hash espacial.
func get_closest_offset(pos: Vector3, hint: float = -1.0, window: float = 60.0) -> float:
	var best_i := -1
	var best_d := INF
	if hint >= 0.0:
		var center := roundi(fposmod(hint, length) / sample_step)
		var w := ceili(window / sample_step)
		for k in range(-w, w + 1):
			var i := (center + k + sample_count) % sample_count
			var d := _pos[i].distance_squared_to(pos)
			if d < best_d:
				best_d = d
				best_i = i
		if best_d > 45.0 * 45.0:
			best_i = -1  # muito longe do esperado (teleporte): busca global
	if best_i < 0:
		best_d = INF
		var c := _cell_of(pos)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var key := Vector2i(c.x + dx, c.y + dz)
				if not _grid.has(key):
					continue
				var arr: PackedInt32Array = _grid[key]
				for i in arr:
					var d := _pos[i].distance_squared_to(pos)
					if d < best_d:
						best_d = d
						best_i = i
	if best_i < 0:
		for i in sample_count:
			var d := _pos[i].distance_squared_to(pos)
			if d < best_d:
				best_d = d
				best_i = i
	# Refina projetando nos dois segmentos vizinhos.
	var best_off := best_i * sample_step
	var best_seg_d := INF
	for s: int in [-1, 0]:
		var i0 := (best_i + s + sample_count) % sample_count
		var i1 := (i0 + 1) % sample_count
		var a := _pos[i0]
		var ab := _pos[i1] - a
		var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := (a + ab * t).distance_squared_to(pos)
		if d < best_seg_d:
			best_seg_d = d
			best_off = (i0 + t) * sample_step
	return fposmod(best_off, length)


## Progresso normalizado na volta (0..1).
func get_progress(pos: Vector3, hint: float = -1.0) -> float:
	return get_closest_offset(pos, hint) / length


## Deslocamento lateral com sinal de `pos` em relação à linha central no offset dado.
func get_lateral(pos: Vector3, offset: float) -> float:
	return (pos - get_point_at(offset)).dot(get_right(offset))


func get_surface_at(pos: Vector3, hint: float = -1.0) -> Surface:
	var off := get_closest_offset(pos, hint)
	var lat := get_lateral(pos, off)
	var al := absf(lat)
	var hw := get_half_width()
	if al <= hw:
		return Surface.ROAD
	if al <= hw + layout.curb_width and get_curb(off, -1 if lat < 0.0 else 1) > 0.5:
		return Surface.CURB
	if al <= get_wall_lateral(off, -1 if lat < 0.0 else 1):
		return Surface.OFFROAD
	return Surface.OUTSIDE


# ---------------------------------------------------------------- pontos estratégicos

## Transform de largada do slot `slot` (0 = pole position). Grid 2 colunas escalonado.
func get_grid_transform(slot: int) -> Transform3D:
	var row := floori(slot / 2.0)
	var col := slot % 2
	var back := layout.grid_first_row_distance + row * layout.grid_row_spacing + col * layout.grid_column_stagger
	# Pole no lado interno da 1ª curva.
	var first_turn_left := _first_turn_sign() > 0.0
	var lat := layout.grid_column_lateral * (-1.0 if (col == 0) == first_turn_left else 1.0)
	return get_transform_at(-back, lat, 0.0)


func _first_turn_sign() -> float:
	var acc := 0.0
	var i := 0
	while i < sample_count and absf(acc) < 0.5:
		acc += _curv[i] * sample_step
		i += 1
	return signf(acc)


## Offsets dos checkpoints, uniformemente espaçados (o índice 0 é a linha de chegada).
func get_checkpoint_offsets() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := maxi(layout.checkpoint_count, 4)
	for i in n:
		out.append(length * float(i) / float(n))
	return out


## Faixas de turbo: Array de Dictionary {offset, lateral, length, transform}.
func get_boost_pads() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in layout.boost_pads:
		var off := wrap_offset(p.x * length)
		out.append({
			"offset": off,
			"lateral": p.y,
			"length": p.z,
			"transform": get_transform_at(off, p.y, 0.0),
		})
	return out


## Fileiras de caixas de item: Array de Dictionary {offset, positions: PackedVector3Array}.
func get_item_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := maxi(layout.item_boxes_per_row, 1)
	var usable := layout.road_width - 4.0
	for t in layout.item_rows:
		var off := wrap_offset(t * length)
		var positions := PackedVector3Array()
		for k in n:
			var lat := -usable * 0.5 + usable * (float(k) + 0.5) / float(n)
			positions.append(to_world(off, lat, 0.0))
		out.append({"offset": off, "positions": positions})
	return out


## Posições amostradas (cópia) — útil para a IA montar a linha de corrida.
func get_sample_positions() -> PackedVector3Array:
	return _pos.duplicate()
