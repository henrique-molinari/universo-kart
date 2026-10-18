class_name TrackMeshBuilder
extends RefCounted
## Gera a geometria da pista a partir do TrackPath: asfalto, zebras, acostamento (grama, brita,
## canteiro de flores ou calçada na ponte) com AO de contato, muretas por setor (barreira
## arredondada, pneus, cerca à beira do lago, parapeito de concreto), ponte/viaduto em arcos
## (tabuleiro, pilares com sapatas, cabeceiras chanfradas) e as colisões.
## A malha é dividida em blocos (~CHUNK_LENGTH m) para permitir frustum culling.

const CHUNK_LENGTH := 90.0
const RUNOFF_DROP := 0.035
const WALL_BOTTOM := -0.6
const WALL_ARC_STEPS := 8
const WALL_COLLISION_HEIGHT := 3.0
const DECK_BOTTOM := -1.8
const DECK_OVERHANG := 0.45
const TIRE_SPACING := 0.95

const STYLE_BRIDGE := 100  # estilo interno: parapeito de ponte (com corrimão)

var path: TrackPath
var site: SiteMap
var mat_road: Material
var mat_curb: Material
var mat_grass: Material
var mat_wall: Material
var mat_concrete: Material
var mat_props: Material

var _hw: float
var _wall_r: float
var _n: int
var _step: float
# Trilhos por linha (N + 1 linhas; a última fecha o circuito).
var P := PackedVector3Array()
var R := PackedVector3Array()
var U := PackedVector3Array()
var V := PackedFloat32Array()
var BR := PackedFloat32Array()
var CL := PackedFloat32Array()
var CR := PackedFloat32Array()
var WL := PackedFloat32Array()
var WR := PackedFloat32Array()
var _tire_xfs: Array[Transform3D] = []


func _init(p_path: TrackPath, p_site: SiteMap) -> void:
	path = p_path
	site = p_site


func _wall(i: int, side: int) -> float:
	return WL[i] if side < 0 else WR[i]


## Estilo da mureta no segmento i..i+1 de um lado.
func _style(i: int, side: int) -> int:
	if BR[i] > 0.01 or BR[i + 1] > 0.01:
		return STYLE_BRIDGE
	return path.get_wall_style(V[i], side)


func build(parent: Node3D) -> void:
	var lay := path.layout
	_hw = lay.road_width * 0.5
	_wall_r = lay.wall_thickness * 0.5
	_n = path.sample_count
	_step = path.sample_step

	var root := Node3D.new()
	root.name = "TrackGeometry"
	parent.add_child(root)

	for i in _n + 1:
		var off := float(i) * _step
		P.append(path.get_point_at(off))
		R.append(path.get_right(off))
		U.append(path.get_up(off))
		V.append(off)
		BR.append(path.get_bridge(off))
		CL.append(path.get_curb(off, -1))
		CR.append(path.get_curb(off, 1))
		WL.append(path.get_wall_lateral(off, -1))
		WR.append(path.get_wall_lateral(off, 1))

	# Distância acumulada ao longo de cada mureta/zebra (listras sem distorção nas curvas).
	var side_v := {}
	for side: int in [-1, 1]:
		var curb_lat := float(side) * (_hw + lay.curb_width * 0.5)
		var acc := PackedFloat32Array()
		var acc_c := PackedFloat32Array()
		acc.resize(_n + 1)
		acc_c.resize(_n + 1)
		for i in range(1, _n + 1):
			var a := P[i] + R[i] * (float(side) * _wall(i, side))
			var b := P[i - 1] + R[i - 1] * (float(side) * _wall(i - 1, side))
			acc[i] = acc[i - 1] + a.distance_to(b)
			acc_c[i] = acc_c[i - 1] + (P[i] + R[i] * curb_lat).distance_to(P[i - 1] + R[i - 1] * curb_lat)
		side_v[side] = acc
		side_v[side * 10] = acc_c

	var rows_per_chunk := maxi(8, roundi(CHUNK_LENGTH / _step))
	var chunk_count := ceili(float(_n) / float(rows_per_chunk))
	for c in chunk_count:
		var i0 := c * rows_per_chunk
		var i1 := mini(i0 + rows_per_chunk, _n)
		var road := MeshKit.new()
		var curb := MeshKit.new()
		var grass := MeshKit.new()
		var wall := MeshKit.new()
		var concrete := MeshKit.new()
		var props := MeshKit.new()
		_build_road(road, i0, i1)
		_build_runoff(grass, concrete, i0, i1)
		for side: int in [-1, 1]:
			_build_curb(curb, side_v[side * 10], CL if side < 0 else CR, side, i0, i1)
			_build_walls(wall, concrete, props, side_v[side], side, i0, i1)
		_build_deck(concrete, i0, i1)
		var mesh := ArrayMesh.new()
		road.commit(mesh, mat_road)
		curb.commit(mesh, mat_curb)
		grass.commit(mesh, mat_grass)
		wall.commit(mesh, mat_wall)
		concrete.commit(mesh, mat_concrete)
		props.commit(mesh, mat_props)
		var mi := MeshInstance3D.new()
		mi.name = "TrackChunk%02d" % c
		mi.mesh = mesh
		root.add_child(mi)

	_build_tires(root)
	_build_bridge_supports(root)
	_build_collision(root)


# ------------------------------------------------------------------ asfalto

func _build_road(kit: MeshKit, i0: int, i1: int) -> void:
	var base := kit.vertex_count()
	for i in range(i0, i1 + 1):
		kit.add_vertex(P[i] - R[i] * _hw, U[i], Vector2(-_hw, V[i]))
		kit.add_vertex(P[i] + R[i] * _hw, U[i], Vector2(_hw, V[i]))
	for k in i1 - i0:
		var a := base + k * 2
		kit.quad(a, a + 2, a + 1, a + 3)
	# Pequena "borda" lateral do asfalto descendo até o acostamento.
	for side: int in [-1, 1]:
		var b2 := kit.vertex_count()
		for i in range(i0, i1 + 1):
			var e := P[i] + R[i] * (_hw * side)
			var nrm := R[i] * float(side)
			kit.add_vertex(e, nrm, Vector2(_hw * side, V[i]))
			kit.add_vertex(e - U[i] * (RUNOFF_DROP + 0.03), nrm, Vector2(_hw * side, V[i]))
		for k in i1 - i0:
			var a := b2 + k * 2
			kit.quad(a, a + 2, a + 1, a + 3)


# ------------------------------------------------------------------ acostamento

func _surface_color(surf: int, ao: float) -> Color:
	match surf:
		TrackLayout.Surface.GRAVEL:
			return Color(1.0, 0.0, 0.0, ao)
	return Color(0.0, 0.0, 0.0, ao)


func _build_runoff(grass: MeshKit, concrete: MeshKit, i0: int, i1: int) -> void:
	var conc := Color(0.52, 0.54, 0.58)
	var tunnel := path.get_tunnel_range()
	for side: int in [-1, 1]:
		var s := float(side)
		for i in range(i0, i1):
			var j := i + 1
			var in_tunnel := tunnel.x >= 0.0 and V[j] > tunnel.x - 2.0 and V[i] < tunnel.y + 2.0
			var on_bridge := BR[i] > 0.01 or BR[j] > 0.01 or in_tunnel
			var kit := concrete if on_bridge else grass
			var surf := path.get_runoff_surface(V[i], side)
			# Três faixas: asfalto -> meio -> junto à mureta (AO de contato).
			var lats_i: Array[float] = [_hw, maxf(_hw + 0.5, _wall(i, side) - 1.6), _wall(i, side) + 0.1]
			var lats_j: Array[float] = [_hw, maxf(_hw + 0.5, _wall(j, side) - 1.6), _wall(j, side) + 0.1]
			var aos: Array[float] = [1.0, 1.0, 0.5]
			var idx_i: Array[int] = []
			var idx_j: Array[int] = []
			for k in 3:
				var c: Color
				if on_bridge:
					var f := lerpf(0.72, 1.0, aos[k])
					c = Color(conc.r * f, conc.g * f, conc.b * f, 1.0)
				else:
					c = _surface_color(surf, aos[k])
				idx_i.append(kit.add_vertex(P[i] + R[i] * (s * lats_i[k]) - U[i] * RUNOFF_DROP, U[i], Vector2.ZERO, c))
				idx_j.append(kit.add_vertex(P[j] + R[j] * (s * lats_j[k]) - U[j] * RUNOFF_DROP, U[j], Vector2.ZERO, c))
			for k in 2:
				kit.quad(idx_i[k], idx_j[k], idx_i[k + 1], idx_j[k + 1])


# ------------------------------------------------------------------ zebras

func _build_curb(kit: MeshKit, v_along: PackedFloat32Array, C: PackedFloat32Array, side: int, i0: int, i1: int) -> void:
	var cw := path.layout.curb_width
	var prof: Array[Vector2] = [Vector2(0.0, 0.012), Vector2(0.3, 0.06), Vector2(0.75, 0.07), Vector2(1.0, 0.03)]
	var s := float(side)
	var i := i0
	while i < i1:
		if C[i] < 0.02 and C[i + 1] < 0.02:
			i += 1
			continue
		var start := i
		while i < i1 and not (C[i] < 0.02 and C[i + 1] < 0.02):
			i += 1
		var end := i
		var base := kit.vertex_count()
		var np := prof.size() + 1
		for r in range(start, end + 1):
			var w := cw * clampf(C[r], 0.0, 1.0)
			var right := R[r] * s
			for k in prof.size():
				var pr := prof[k]
				var pos := P[r] + right * (_hw + pr.x * w) + U[r] * pr.y
				var nrm := U[r]
				if k == 0:
					nrm = (U[r] - right * 0.35).normalized()
				elif k == prof.size() - 1:
					nrm = (U[r] + right * 0.6).normalized()
				kit.add_vertex(pos, nrm, Vector2(pr.x, v_along[r]))
			kit.add_vertex(P[r] + right * (_hw + w + 0.02) - U[r] * (RUNOFF_DROP + 0.02), (U[r] * 0.3 + right).normalized(), Vector2(1.0, v_along[r]))
		for r in end - start:
			for k in np - 1:
				var a0 := base + r * np + k
				var b0 := a0 + np
				kit.quad(a0, a0 + 1, b0, b0 + 1)


# ------------------------------------------------------------------ muretas por estilo

func _barrier_profile() -> Array:
	var h := path.layout.wall_height
	var r := _wall_r
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	pts.append(Vector2(0.0, WALL_BOTTOM))
	nrm.append(Vector2(-1.0, 0.0))
	for k in WALL_ARC_STEPS + 1:
		var th := PI * float(k) / float(WALL_ARC_STEPS)
		pts.append(Vector2(r - r * cos(th), h - r + r * sin(th)))
		nrm.append(Vector2(-cos(th), sin(th)))
	pts.append(Vector2(2.0 * r, WALL_BOTTOM))
	nrm.append(Vector2(1.0, 0.0))
	return [pts, nrm]


## Perfil com arestas vivas (pontos duplicados por face) a partir de uma polilinha.
func _hard_profile(poly: PackedVector2Array) -> Array:
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	var center := Vector2.ZERO
	for q in poly:
		center += q
	center /= float(poly.size())
	if poly.size() == 2:
		center = (poly[0] + poly[1]) * 0.5 + Vector2(1.0, 0.0)
	for k in poly.size() - 1:
		var a := poly[k]
		var b := poly[k + 1]
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)
		# Normal apontando para fora do perfil.
		if n.dot((a + b) * 0.5 - center) < 0.0:
			n = -n
		pts.append(a)
		nrm.append(n)
		pts.append(b)
		nrm.append(n)
	return [pts, nrm]


func _build_walls(wall_kit: MeshKit, concrete: MeshKit, props: MeshKit, v_along: PackedFloat32Array, side: int, i0: int, i1: int) -> void:
	var i := i0
	while i < i1:
		var style := _style(i, side)
		var start := i
		while i < i1 and _style(i, side) == style:
			i += 1
		var end := i  # linhas start..end
		# Tampas nas trocas de estilo (não nas emendas de bloco).
		var cap_start := start > 0 and _style(start - 1, side) != style
		var cap_end := end < _n and _style(end, side) != style
		match style:
			TrackLayout.WallStyle.BARRIER:
				_extrude_run(wall_kit, _barrier_profile(), start, end, side, 0.0, Color(1.0 if side > 0 else 0.0, 1.0, 1.0), v_along, cap_start, cap_end)
			TrackLayout.WallStyle.TIRES:
				_tire_run(start, end, side)
				_extrude_run(props, _hard_profile(PackedVector2Array([Vector2(0.0, -0.5), Vector2(0.0, 0.05), Vector2(0.9, 0.05), Vector2(0.9, -0.5)])), start, end, side, 0.0, Color(0.3, 0.3, 0.32), v_along, cap_start, cap_end)
			TrackLayout.WallStyle.FENCE:
				_fence_run(concrete, props, start, end, side, v_along, cap_start, cap_end)
			_:
				_parapet_run(concrete, props, start, end, side, v_along, style == STYLE_BRIDGE, cap_start, cap_end)


func _extrude_run(kit: MeshKit, prof: Array, start: int, end: int, side: int, extra_lat: float, c: Color, v_along: PackedFloat32Array, cap_start: bool, cap_end: bool, lift: float = 0.0) -> void:
	var rails := PackedVector3Array()
	var rights := PackedVector3Array()
	var ups := PackedVector3Array()
	var vs := PackedFloat32Array()
	for r in range(start, end + 1):
		var out := R[r] * float(side)
		rails.append(P[r] + out * (_wall(r, side) + extra_lat) + U[r] * lift)
		rights.append(out)
		ups.append(U[r])
		vs.append(v_along[r])
	kit.extrude(rails, rights, ups, prof[0], prof[1], c, vs)
	var pts: PackedVector2Array = prof[0]
	if cap_start:
		kit.cap_profile(rails[0], rights[0], ups[0], pts, -path.get_forward(V[start]), c)
	if cap_end:
		kit.cap_profile(rails[rails.size() - 1], rights[rights.size() - 1], ups[ups.size() - 1], pts, path.get_forward(V[end]), c)


func _parapet_run(concrete: MeshKit, props: MeshKit, start: int, end: int, side: int, v_along: PackedFloat32Array, bridge: bool, cap_start: bool, cap_end: bool) -> void:
	var body := _hard_profile(PackedVector2Array([Vector2(0.0, -0.6), Vector2(0.0, 0.95), Vector2(0.12, 1.1), Vector2(0.78, 1.1), Vector2(0.9, 0.95), Vector2(0.9, -0.6)]))
	_extrude_run(concrete, body, start, end, side, 0.0, Color(0.86, 0.86, 0.88), v_along, cap_start, cap_end)
	# Faixa azul na face interna.
	var stripe := _hard_profile(PackedVector2Array([Vector2(-0.015, 0.55), Vector2(-0.015, 0.8)]))
	_extrude_run(props, stripe, start, end, side, 0.0, Palette.BLUE, v_along, false, false)
	if bridge:
		# Corrimão metálico com postes.
		var tube := _tube_profile(0.055, 6)
		_extrude_run(props, tube, start, end, side, 0.45, Color(0.8, 0.82, 0.86), v_along, false, false, 1.45)
		var acc := 0.0
		for r in range(start, end):
			acc += P[r].distance_to(P[r + 1])
			if acc >= 2.5:
				acc = 0.0
				var base := P[r] + R[r] * (float(side) * (_wall(r, side) + 0.45)) + U[r] * 1.1
				props.cylinder(Transform3D(Basis.IDENTITY, base), 0.04, 0.04, 0.36, 5, Color(0.8, 0.82, 0.86), false)


func _fence_run(concrete: MeshKit, props: MeshKit, start: int, end: int, side: int, v_along: PackedFloat32Array, cap_start: bool, cap_end: bool) -> void:
	var kerb := _hard_profile(PackedVector2Array([Vector2(0.0, -0.5), Vector2(0.0, 0.45), Vector2(0.15, 0.58), Vector2(0.75, 0.58), Vector2(0.9, 0.45), Vector2(0.9, -0.5)]))
	_extrude_run(concrete, kerb, start, end, side, 0.0, Color(0.88, 0.88, 0.9), v_along, cap_start, cap_end)
	var tube := _tube_profile(0.045, 6)
	var rail_col := Color(0.92, 0.93, 0.96)
	for h: float in [1.05, 1.45]:
		_extrude_run(props, tube, start, end, side, 0.45, rail_col, v_along, false, false, h)
	var acc := 0.0
	for r in range(start, end):
		acc += P[r].distance_to(P[r + 1])
		if acc >= 2.4:
			acc = 0.0
			var base := P[r] + R[r] * (float(side) * (_wall(r, side) + 0.45)) + U[r] * 0.5
			props.cylinder(Transform3D(Basis.IDENTITY, base), 0.05, 0.05, 1.05, 6, Palette.BLUE, true)


func _tube_profile(radius: float, segs: int) -> Array:
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	for k in segs + 1:
		var a := TAU * float(k) / float(segs)
		var d := Vector2(cos(a), sin(a))
		pts.append(d * radius)
		nrm.append(d)
	return [pts, nrm]


func _tire_run(start: int, end: int, side: int) -> void:
	var acc := TIRE_SPACING
	for r in range(start, end):
		acc += P[r].distance_to(P[r + 1])
		if acc < TIRE_SPACING:
			continue
		acc = 0.0
		var out := R[r] * float(side)
		var pos := P[r] + out * (_wall(r, side) + 0.46)
		var fwd := path.get_forward(V[r])
		var basis := Basis(fwd.cross(U[r]).normalized(), U[r], -fwd)
		_tire_xfs.append(Transform3D(basis, pos - U[r] * 0.05))


# ------------------------------------------------------------------ pneus (MultiMesh)

func _tire_mesh(variant: int) -> ArrayMesh:
	var kit := MeshKit.new()
	var rubber := Color(0.07, 0.07, 0.08)
	var colors: Array[Color] = [rubber, rubber, rubber]
	match variant:
		1:
			colors[2] = Color(0.92, 0.92, 0.94)
		2:
			colors[1] = Palette.MAGENTA
		3:
			colors[1] = Palette.BLUE
		4:
			colors[2] = Palette.YELLOW
	var prof: Array[Vector2] = [Vector2(0.2, 0.0), Vector2(0.37, 0.0), Vector2(0.43, 0.05), Vector2(0.45, 0.13), Vector2(0.43, 0.21), Vector2(0.37, 0.26), Vector2(0.2, 0.26), Vector2(0.18, 0.13), Vector2(0.2, 0.0)]
	var segs := 12
	for t in 3:
		var y0 := float(t) * 0.27
		var base := kit.vertex_count()
		for s in segs + 1:
			var a := TAU * float(s) / float(segs)
			var d := Vector3(cos(a), 0.0, sin(a))
			for k in prof.size():
				var pr := prof[k]
				var prev := prof[maxi(k - 1, 0)]
				var next := prof[mini(k + 1, prof.size() - 1)]
				var tan2 := (next - prev).normalized()
				var n2 := Vector2(tan2.y, -tan2.x)
				var nrm := (d * n2.x + Vector3.UP * n2.y).normalized()
				kit.add_vertex(d * pr.x + Vector3(0, y0 + pr.y, 0), nrm, Vector2.ZERO, colors[t])
		var np := prof.size()
		for s in segs:
			for k in np - 1:
				var a0 := base + s * np + k
				var b0 := a0 + np
				kit.quad(a0, a0 + 1, b0, b0 + 1)
	return kit.commit(null, mat_props)


func _build_tires(root: Node3D) -> void:
	if _tire_xfs.is_empty():
		return
	var variants := 5
	var buckets: Array = []
	for v in variants:
		buckets.append([])
	for k in _tire_xfs.size():
		var v := 0 if k % 2 == 0 else (1 + (k >> 1) % 4)
		(buckets[v] as Array).append(_tire_xfs[k])
	for v in variants:
		var list: Array = buckets[v]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _tire_mesh(v)
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform(k, list[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Pneus_%d" % v
		mmi.multimesh = mm
		mmi.visibility_range_end = 320.0
		mmi.visibility_range_end_margin = 30.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mmi)


# ------------------------------------------------------------------ ponte / viaduto

func _deck_edge(i: int, side: int) -> float:
	return _wall(i, side) + 2.0 * _wall_r + DECK_OVERHANG


func _build_deck(kit: MeshKit, i0: int, i1: int) -> void:
	var fascia := Palette.BLUE
	var under := Color(0.62, 0.63, 0.66)
	var ledge := Color(0.86, 0.86, 0.88)
	for i in range(i0, i1):
		if BR[i] <= 0.01 and BR[i + 1] <= 0.01:
			continue
		var j := i + 1
		var d0 := U[i] * DECK_BOTTOM
		var d1 := U[j] * DECK_BOTTOM
		var a0 := kit.add_vertex(P[i] - R[i] * _deck_edge(i, -1) + d0, -U[i], Vector2.ZERO, under)
		var b0 := kit.add_vertex(P[i] + R[i] * _deck_edge(i, 1) + d0, -U[i], Vector2.ZERO, under)
		var a1 := kit.add_vertex(P[j] - R[j] * _deck_edge(j, -1) + d1, -U[j], Vector2.ZERO, under)
		var b1 := kit.add_vertex(P[j] + R[j] * _deck_edge(j, 1) + d1, -U[j], Vector2.ZERO, under)
		kit.quad(a0, a1, b0, b1)
		for side: int in [-1, 1]:
			var s := float(side)
			var n0 := R[i] * s
			var n1 := R[j] * s
			var top_y := -0.3
			var e0 := _deck_edge(i, side)
			var e1 := _deck_edge(j, side)
			var f0 := kit.add_vertex(P[i] + n0 * e0 + U[i] * top_y, n0, Vector2.ZERO, fascia)
			var f1 := kit.add_vertex(P[j] + n1 * e1 + U[j] * top_y, n1, Vector2.ZERO, fascia)
			var g0 := kit.add_vertex(P[i] + n0 * e0 + d0, n0, Vector2.ZERO, fascia)
			var g1 := kit.add_vertex(P[j] + n1 * e1 + d1, n1, Vector2.ZERO, fascia)
			kit.quad(f0, f1, g0, g1)
			var l0 := kit.add_vertex(P[i] + n0 * (_wall(i, side) + 2.0 * _wall_r - 0.02) + U[i] * top_y, U[i], Vector2.ZERO, ledge)
			var l1 := kit.add_vertex(P[j] + n1 * (_wall(j, side) + 2.0 * _wall_r - 0.02) + U[j] * top_y, U[j], Vector2.ZERO, ledge)
			var m0 := kit.add_vertex(P[i] + n0 * e0 + U[i] * top_y, U[i], Vector2.ZERO, ledge)
			var m1 := kit.add_vertex(P[j] + n1 * e1 + U[j] * top_y, U[j], Vector2.ZERO, ledge)
			kit.quad(l0, l1, m0, m1)


func _support_top(x: float, z: float) -> float:
	# Topo da sapata: chão natural, ou pouco acima da água se estiver no lago.
	var g := site.height_at(x, z)
	if site.lake_sdf(x, z) < 0.0:
		return site.water_level + 0.35
	return g + 0.25


func _build_bridge_supports(root: Node3D) -> void:
	var spans: Array[Vector2i] = []
	var i := 0
	while i < _n:
		if BR[i] > 0.01:
			var s := i
			while i < _n and BR[i] > 0.01:
				i += 1
			spans.append(Vector2i(s, i - 1))
		else:
			i += 1
	if spans.is_empty():
		return
	var kit := MeshKit.new()
	var accent := MeshKit.new()
	var pillar_col := Color(0.9, 0.9, 0.92)
	var cap_col := Palette.MAGENTA
	var abut_col := Color(0.76, 0.73, 0.68)
	var arch_col := Color(0.95, 0.95, 0.97)
	const ABUT_DEPTH := 8.0
	for span in spans:
		var o_start := float(span.x) * _step
		var o_end := float(span.y) * _step
		var len_m := o_end - o_start
		if len_m < 12.0:
			continue
		var inner_start := o_start + ABUT_DEPTH * 0.5
		var inner_end := o_end - ABUT_DEPTH * 0.5
		var count := maxi(2, roundi((inner_end - inner_start) / 28.0))
		var supports: Array[float] = []
		for k in count + 1:
			supports.append(lerpf(inner_start, inner_end, float(k) / float(count)))
		# Pilares-parede (um por apoio, na largura do tabuleiro) com sapata e mísula no topo.
		const PIER_DEPTH := 2.6
		for k in range(1, count):
			var o := supports[k]
			var p := path.get_point_at(o)
			var fwd := path.get_forward(o)
			var rgt := path.get_right(o)
			var rf := Vector3(rgt.x, 0.0, rgt.z).normalized()
			var rot := Basis.looking_at(Vector3(fwd.x, 0.0, fwd.z).normalized(), Vector3.UP)
			var ll := path.get_wall_lateral(o, -1) + 2.0 * _wall_r + DECK_OVERHANG - 0.6
			var lr := path.get_wall_lateral(o, 1) + 2.0 * _wall_r + DECK_OVERHANG - 0.6
			var cen := p + rf * ((lr - ll) * 0.5)
			var width := ll + lr
			var foot := minf(_support_top(p.x - rf.x * ll, p.z - rf.z * ll), _support_top(p.x + rf.x * lr, p.z + rf.z * lr))
			foot = minf(foot, _support_top(p.x, p.z))
			var top_y := p.y + DECK_BOTTOM
			kit.rounded_prism(Transform3D(rot, Vector3(cen.x, foot - 2.5, cen.z)), width + 1.6, PIER_DEPTH + 2.2, 2.9, 1.0, 4, abut_col, abut_col)
			kit.rounded_prism(Transform3D(rot, Vector3(cen.x, foot + 0.3, cen.z)), width, PIER_DEPTH, top_y - foot - 1.2, 1.1, 5, pillar_col, pillar_col)
			accent.rounded_prism(Transform3D(rot, Vector3(cen.x, top_y - 0.9, cen.z)), width + 0.8, PIER_DEPTH + 0.6, 0.9, 1.3, 5, cap_col, cap_col)
		# Um arco-abóbada por vão, entre apoios consecutivos: nasce na face do pilar/cabeceira
		# (no topo da sapata), segue a tangente local do tabuleiro e não invade o volume dos apoios.
		for k in count:
			var o0 := supports[k] + (PIER_DEPTH * 0.5 if k > 0 else 0.0)
			var o1 := supports[k + 1] - (PIER_DEPTH * 0.5 if k + 1 < count else 0.0)
			var mid_o := (o0 + o1) * 0.5
			var ll := path.get_wall_lateral(mid_o, -1) + 2.0 * _wall_r + DECK_OVERHANG - 0.9
			var lr := path.get_wall_lateral(mid_o, 1) + 2.0 * _wall_r + DECK_OVERHANG - 0.9
			var half := (ll + lr) * 0.5
			var shift := (lr - ll) * 0.5
			var band := _hard_profile(PackedVector2Array([Vector2(-half, -0.5), Vector2(half, -0.5), Vector2(half, 0.5), Vector2(-half, 0.5), Vector2(-half, -0.5)]))
			var pa := path.get_point_at(o0)
			var pb := path.get_point_at(o1)
			var f0 := minf(_support_top(pa.x, pa.z), pa.y + DECK_BOTTOM - 3.0) + 0.8
			var f1 := minf(_support_top(pb.x, pb.z), pb.y + DECK_BOTTOM - 3.0) + 0.8
			var rails := PackedVector3Array()
			var rights := PackedVector3Array()
			var ups := PackedVector3Array()
			var vs := PackedFloat32Array()
			var segs := 22
			for q in segs + 1:
				var t := float(q) / float(segs)
				var o := lerpf(o0, o1, t)
				var c := path.get_point_at(o)
				var r := path.get_right(o)
				var rf := Vector3(r.x, 0.0, r.z).normalized()
				var deck_y := c.y + DECK_BOTTOM - 0.5
				var foot := lerpf(f0, f1, t)
				var y := foot + maxf(deck_y - foot, 0.0) * pow(sin(PI * t), 0.5)
				var pt := c + rf * shift
				rails.append(Vector3(pt.x, y, pt.z))
				rights.append(rf)
				ups.append(Vector3.UP)
				vs.append(t)
			kit.extrude(rails, rights, ups, band[0], band[1], arch_col, vs)
			# Tímpanos: faixa azul nas bordas do arco (leitura do desenho de lado).
			var edge := _hard_profile(PackedVector2Array([Vector2(half, -0.45), Vector2(half + 0.05, -0.45), Vector2(half + 0.05, 0.45), Vector2(half, 0.45), Vector2(half, -0.45)]))
			var edge_l := _hard_profile(PackedVector2Array([Vector2(-half - 0.05, -0.45), Vector2(-half, -0.45), Vector2(-half, 0.45), Vector2(-half - 0.05, 0.45), Vector2(-half - 0.05, -0.45)]))
			accent.extrude(rails, rights, ups, edge[0], edge[1], Palette.BLUE, vs)
			accent.extrude(rails, rights, ups, edge_l[0], edge_l[1], Palette.BLUE, vs)
		# Cabeceiras chanfradas nas duas pontas.
		for end_o: float in [o_start, o_end]:
			var p := path.get_point_at(end_o)
			var fwd := path.get_forward(end_o)
			var rot := Basis.looking_at(Vector3(fwd.x, 0.0, fwd.z).normalized(), Vector3.UP)
			var ground := minf(site.height_at(p.x, p.z), _support_top(p.x, p.z)) - 3.0
			var top := p.y - 0.3
			var width := path.get_wall_lateral(end_o, -1) + path.get_wall_lateral(end_o, 1) + 2.0 * (2.0 * _wall_r + DECK_OVERHANG) + 1.4
			kit.rounded_prism(Transform3D(rot, Vector3(p.x, ground, p.z)), width, ABUT_DEPTH, top - ground, 1.6, 5, abut_col, abut_col)
			# Rodapé mais largo (sapata corrida).
			kit.rounded_prism(Transform3D(rot, Vector3(p.x, ground, p.z)), width + 1.6, ABUT_DEPTH + 1.6, 3.4, 1.8, 5, Color(0.62, 0.6, 0.56), Color(0.62, 0.6, 0.56))
			# Faixa azul no topo da cabeceira.
			accent.rounded_prism(Transform3D(rot, Vector3(p.x, top - 0.9, p.z)), width + 0.2, ABUT_DEPTH + 0.2, 0.5, 1.65, 5, Palette.BLUE, Palette.BLUE)
	var mi := MeshInstance3D.new()
	mi.name = "BridgeSupports"
	mi.mesh = kit.commit(null, mat_concrete)
	accent.commit(mi.mesh as ArrayMesh, mat_props)
	root.add_child(mi)


# ------------------------------------------------------------------ colisões

func _build_collision(root: Node3D) -> void:
	var road := MeshKit.new()
	for i in _n + 1:
		road.add_vertex(P[i] - R[i] * (WL[i] + 0.2) - U[i] * 0.01, U[i])
		road.add_vertex(P[i] + R[i] * (WR[i] + 0.2) - U[i] * 0.01, U[i])
	for k in _n:
		var a := k * 2
		road.quad(a, a + 2, a + 1, a + 3)
	var road_body := StaticBody3D.new()
	road_body.name = "RoadCollision"
	road_body.collision_layer = PhysicsLayers.WORLD_ROAD
	road_body.collision_mask = 0
	var road_shape := ConcavePolygonShape3D.new()
	road_shape.set_faces(road.to_collision_faces())
	road_shape.backface_collision = false
	var cs := CollisionShape3D.new()
	cs.shape = road_shape
	road_body.add_child(cs)
	root.add_child(road_body)

	var wall := MeshKit.new()
	var th := path.layout.wall_thickness
	for side: int in [-1, 1]:
		var s := float(side)
		var base := wall.vertex_count()
		for i in _n + 1:
			var out := R[i] * s
			var inner := P[i] + out * _wall(i, side)
			var outer := P[i] + out * (_wall(i, side) + th)
			wall.add_vertex(inner - U[i] * 1.0, -out)
			wall.add_vertex(inner + U[i] * WALL_COLLISION_HEIGHT, -out)
			wall.add_vertex(outer + U[i] * WALL_COLLISION_HEIGHT, out)
			wall.add_vertex(outer - U[i] * 1.0, out)
		for k in _n:
			var a := base + k * 4
			var b := a + 4
			wall.quad(a, a + 1, b, b + 1)
			wall.quad(a + 2, a + 3, b + 2, b + 3)
		var tb := wall.vertex_count()
		for i in _n + 1:
			var out := R[i] * s
			wall.add_vertex(P[i] + out * _wall(i, side) + U[i] * WALL_COLLISION_HEIGHT, U[i])
			wall.add_vertex(P[i] + out * (_wall(i, side) + th) + U[i] * WALL_COLLISION_HEIGHT, U[i])
		for k in _n:
			var a := tb + k * 2
			wall.quad(a, a + 2, a + 1, a + 3)
	var wall_body := StaticBody3D.new()
	wall_body.name = "WallCollision"
	wall_body.collision_layer = PhysicsLayers.WORLD_WALL
	wall_body.collision_mask = 0
	var wall_shape := ConcavePolygonShape3D.new()
	wall_shape.set_faces(wall.to_collision_faces())
	wall_shape.backface_collision = true
	var ws := CollisionShape3D.new()
	ws.shape = wall_shape
	wall_body.add_child(ws)
	root.add_child(wall_body)
