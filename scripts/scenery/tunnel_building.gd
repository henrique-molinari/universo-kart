class_name TunnelBuilding
extends Node3D
## Passagem sob um prédio do campus ("Biblioteca"): a pista atravessa o térreo do prédio.
## Tudo (interior, fachadas, laje, alas e bocas) é gerado por linha seguindo a curva da pista,
## com as mesmas laterais das muretas, então não há frestas nem laje em balanço.

const BUILDING_MAT := preload("res://assets/materials/building.tres")
const CONCRETE_MAT := preload("res://assets/materials/concrete.tres")
const PROPS_MAT := preload("res://assets/materials/painted_props.tres")

const CEILING := 7.0
const UPPER_HEIGHT := 13.0
const SIDE_WING := 16.0

const WALL := Color(1, 0, 0, 1)
const PLAIN := Color(0, 0, 0, 1)
const ACCENT := Color(0, 1, 0, 1)
const ROOF := Color(0, 0, 1, 1)


func build(path: TrackPath, site: SiteMap, brand: BrandArt) -> void:
	var trange := path.get_tunnel_range()
	if trange.x < 0.0:
		return
	var o0 := trange.x
	var o1 := trange.y
	var mid := (path.get_point_at(o0) + path.get_point_at(o1)) * 0.5

	# ---------------- interior que acompanha a pista
	var inner := MeshKit.new()
	var lights := MeshKit.new()
	var conc := Color(0.82, 0.82, 0.84)
	var step := 1.0
	var n := ceili((o1 - o0) / step)
	var rows: Array[Dictionary] = []
	for k in n + 1:
		var o := o0 + float(k) * (o1 - o0) / float(n)
		var p := path.get_point_at(o)
		var r := path.get_right(o)
		var u := path.get_up(o)
		var wl := path.get_wall_lateral(o, -1) + 0.9
		var wr := path.get_wall_lateral(o, 1) + 0.9
		rows.append({"p": p, "r": r, "u": u, "wl": wl, "wr": wr})
	for k in n:
		var a: Dictionary = rows[k]
		var b: Dictionary = rows[k + 1]
		var pa: Vector3 = a["p"]
		var pb: Vector3 = b["p"]
		var ra: Vector3 = a["r"]
		var rb: Vector3 = b["r"]
		var ua: Vector3 = a["u"]
		var ub: Vector3 = b["u"]
		var wla: float = a["wl"]
		var wlb: float = b["wl"]
		var wra: float = a["wr"]
		var wrb: float = b["wr"]
		# Teto.
		var c0 := inner.add_vertex(pa - ra * wla + ua * CEILING, -ua, Vector2.ZERO, conc)
		var c1 := inner.add_vertex(pa + ra * wra + ua * CEILING, -ua, Vector2.ZERO, conc)
		var c2 := inner.add_vertex(pb - rb * wlb + ub * CEILING, -ub, Vector2.ZERO, conc)
		var c3 := inner.add_vertex(pb + rb * wrb + ub * CEILING, -ub, Vector2.ZERO, conc)
		inner.quad(c0, c2, c1, c3)
		# Paredes laterais (do topo do parapeito até o teto), com faixa azul.
		for sd: float in [-1.0, 1.0]:
			var la := wla if sd < 0.0 else wra
			var lb := wlb if sd < 0.0 else wrb
			var nrm_a := -ra * sd
			var nrm_b := -rb * sd
			var w0 := inner.add_vertex(pa + ra * (sd * la) + ua * 0.9, nrm_a, Vector2.ZERO, conc)
			var w1 := inner.add_vertex(pa + ra * (sd * la) + ua * CEILING, nrm_a, Vector2.ZERO, conc)
			var w2 := inner.add_vertex(pb + rb * (sd * lb) + ub * 0.9, nrm_b, Vector2.ZERO, conc)
			var w3 := inner.add_vertex(pb + rb * (sd * lb) + ub * CEILING, nrm_b, Vector2.ZERO, conc)
			inner.quad(w0, w1, w2, w3)
			var s0 := inner.add_vertex(pa + ra * (sd * (la - 0.02)) + ua * 2.6, nrm_a, Vector2.ZERO, Palette.BLUE)
			var s1 := inner.add_vertex(pa + ra * (sd * (la - 0.02)) + ua * 3.1, nrm_a, Vector2.ZERO, Palette.BLUE)
			var s2 := inner.add_vertex(pb + rb * (sd * (lb - 0.02)) + ub * 2.6, nrm_b, Vector2.ZERO, Palette.BLUE)
			var s3 := inner.add_vertex(pb + rb * (sd * (lb - 0.02)) + ub * 3.1, nrm_b, Vector2.ZERO, Palette.BLUE)
			inner.quad(s0, s1, s2, s3)
		# Faixas de luz no teto (a cada 4 m, 3 por linha).
		if k % 4 == 2:
			var fw := (pb - pa).normalized()
			var lb2 := Basis(ra, ua, -fw)
			for lx: float in [-6.0, 0.0, 6.0]:
				lights.box(Transform3D(lb2, pa + ra * lx + ua * (CEILING - 0.08)), Vector3(3.2, 0.12, 0.5), Color.WHITE)
	var imi := MeshInstance3D.new()
	imi.name = "TunelInterior"
	imi.mesh = inner.commit(null, CONCRETE_MAT)
	add_child(imi)
	var light_mat := StandardMaterial3D.new()
	light_mat.albedo_color = Color(1.0, 0.97, 0.9)
	light_mat.emission_enabled = true
	light_mat.emission = Color(1.0, 0.95, 0.85)
	light_mat.emission_energy_multiplier = 4.0
	var lmi := MeshInstance3D.new()
	lmi.name = "TunelLuzes"
	lmi.mesh = lights.commit(null, light_mat)
	lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lmi)
	for k in 4:
		var o := lerpf(o0, o1, (float(k) + 0.5) / 4.0)
		var omni := OmniLight3D.new()
		omni.light_color = Color(1.0, 0.95, 0.86)
		omni.light_energy = 2.2
		omni.omni_range = 15.0
		omni.shadow_enabled = false
		omni.position = path.to_world(o, 0.0, CEILING - 1.2)
		add_child(omni)

	# ---------------- volume do prédio: segue a curva da pista (mesmos offsets/laterais do túnel),
	# então fachadas, laje e alas terminam exatamente no plano das bocas — sem frestas nem balanço.
	var kit := MeshKit.new()
	var ground := minf(site.height_at(mid.x, mid.z), -2.0) - 3.0
	var n_rows := rows.size()
	# Lateral interna (face do túnel) e externa (fachada) de cada ala, por linha.
	var inner_l := PackedFloat32Array()
	var inner_r := PackedFloat32Array()
	var along := PackedFloat32Array()
	var acc := 0.0
	for k in n_rows:
		var row: Dictionary = rows[k]
		inner_l.append(float(row["wl"]))
		inner_r.append(float(row["wr"]))
		if k > 0:
			acc += (row["p"] as Vector3).distance_to(rows[k - 1]["p"])
		along.append(acc)
	var top := -1e9
	for k in n_rows:
		top = maxf(top, (rows[k]["p"] as Vector3).y + CEILING + UPPER_HEIGHT)
	# Fachadas laterais externas (com janelas) + telhado + faces internas das alas acima do teto.
	for sd: float in [-1.0, 1.0]:
		var outer_prev := -1
		for k in n_rows:
			var row: Dictionary = rows[k]
			var pk: Vector3 = row["p"]
			var rk: Vector3 = row["r"]
			var rf := Vector3(rk.x, 0.0, rk.z).normalized()
			var lat := (inner_l[k] if sd < 0.0 else inner_r[k]) + SIDE_WING
			var base := Vector3(pk.x, 0.0, pk.z) + rf * (sd * lat)
			var nrm := rf * sd
			var i0 := kit.add_vertex(Vector3(base.x, ground, base.z), nrm, Vector2(along[k], ground - pk.y), WALL)
			kit.add_vertex(Vector3(base.x, top, base.z), nrm, Vector2(along[k], top - pk.y), WALL)
			if outer_prev >= 0:
				kit.quad(outer_prev, outer_prev + 1, i0, i0 + 1)
			outer_prev = i0
	# Telhado (faixa de uma fachada à outra) e platibanda.
	var roof_prev := -1
	var par_prev := -1
	for k in n_rows:
		var row: Dictionary = rows[k]
		var pk: Vector3 = row["p"]
		var rf := Vector3((row["r"] as Vector3).x, 0.0, (row["r"] as Vector3).z).normalized()
		var lo := Vector3(pk.x, top, pk.z) - rf * (inner_l[k] + SIDE_WING)
		var hi := Vector3(pk.x, top, pk.z) + rf * (inner_r[k] + SIDE_WING)
		var r0 := kit.add_vertex(lo, Vector3.UP, Vector2.ZERO, ROOF)
		kit.add_vertex(hi, Vector3.UP, Vector2.ZERO, ROOF)
		if roof_prev >= 0:
			kit.quad(roof_prev, roof_prev + 1, r0, r0 + 1)
		roof_prev = r0
		# Platibanda colorida (faixa de 1,2 m no topo das fachadas laterais, levemente saliente).
		for sd: float in [-1.0, 1.0]:
			var lat := (inner_l[k] if sd < 0.0 else inner_r[k]) + SIDE_WING + 0.25
			var b := Vector3(pk.x, top - 1.2, pk.z) + rf * (sd * lat)
			var pi0 := kit.add_vertex(b, rf * sd, Vector2.ZERO, ACCENT)
			kit.add_vertex(b + Vector3(0, 1.4, 0), rf * sd, Vector2.ZERO, ACCENT)
			if par_prev >= 0 and k > 0:
				var prev_i := par_prev + (0 if sd < 0.0 else 2)
				kit.quad(prev_i, prev_i + 1, pi0, pi0 + 1)
		par_prev = kit.vertex_count() - 4
	# Fachadas das bocas (entrada e saída), no plano perpendicular à pista naquela linha.
	var portal := MeshKit.new()
	for end: int in [0, 1]:
		var k := 0 if end == 0 else n_rows - 1
		var row: Dictionary = rows[k]
		var pk: Vector3 = row["p"]
		var rf := Vector3((row["r"] as Vector3).x, 0.0, (row["r"] as Vector3).z).normalized()
		var fwd_k := rf.cross(Vector3.UP).normalized() * -1.0
		var out_n := -fwd_k if end == 0 else fwd_k
		var left_in := -inner_l[k]
		var right_in := inner_r[k]
		var left_out := -(inner_l[k] + SIDE_WING)
		var right_out := inner_r[k] + SIDE_WING
		var road_y := pk.y
		var open_top := road_y + CEILING
		var c := Vector3(pk.x, 0.0, pk.z)
		# Três painéis: ala esquerda, ala direita (chão ao topo) e faixa acima da boca.
		var pieces: Array[Rect2] = [
			Rect2(left_out, ground, left_in - left_out, top - ground),
			Rect2(right_in, ground, right_out - right_in, top - ground),
			Rect2(left_in, open_top, right_in - left_in, top - open_top),
		]
		for pc in pieces:
			var x0 := pc.position.x
			var x1 := pc.position.x + pc.size.x
			var y0 := pc.position.y
			var y1 := pc.position.y + pc.size.y
			var a0 := kit.add_vertex(c + rf * x0 + Vector3(0, y0, 0), out_n, Vector2(x0 + 100.0, y0 - road_y), WALL)
			var a1 := kit.add_vertex(c + rf * x1 + Vector3(0, y0, 0), out_n, Vector2(x1 + 100.0, y0 - road_y), WALL)
			var a2 := kit.add_vertex(c + rf * x1 + Vector3(0, y1, 0), out_n, Vector2(x1 + 100.0, y1 - road_y), WALL)
			var a3 := kit.add_vertex(c + rf * x0 + Vector3(0, y1, 0), out_n, Vector2(x0 + 100.0, y1 - road_y), WALL)
			kit.tri(a0, a1, a2)
			kit.tri(a0, a2, a3)
		# Moldura magenta saliente ao redor da boca (pilares até o chão + verga).
		var fz := out_n * 0.3
		# Base destra com +Z para fora da boca (na saída o X inverte, senão o letreiro espelha).
		var fb := Basis(rf if end == 0 else -rf, Vector3.UP, out_n)
		for x: float in [left_in - 0.6, right_in + 0.6]:
			portal.box(Transform3D(fb, c + rf * x + fz + Vector3(0, (road_y - 1.0 + open_top + 1.2) * 0.5, 0)), Vector3(1.2, open_top + 1.2 - (road_y - 1.0), 0.6), Palette.MAGENTA)
		portal.box(Transform3D(fb, c + rf * ((left_in + right_in) * 0.5) + fz + Vector3(0, open_top + 0.6, 0)), Vector3(right_in - left_in + 2.4, 1.2, 0.6), Palette.MAGENTA)
		# Letreiro acima da boca.
		var w := minf(right_in - left_in, 22.0)
		var q := QuadMesh.new()
		q.size = Vector2(w, w * 0.25)
		var qmi := MeshInstance3D.new()
		qmi.mesh = q
		qmi.material_override = brand.get_material(BrandArt.Design.LOGO_ON_BLUE if end == 0 else BrandArt.Design.TITLE_ON_MAGENTA)
		qmi.transform = Transform3D(fb, c + rf * ((left_in + right_in) * 0.5) + out_n * 0.65 + Vector3(0, open_top + 1.6 + q.size.y * 0.5, 0))
		qmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(qmi)
	# Equipamentos na cobertura.
	var mid_row: Dictionary = rows[n_rows >> 1]
	var mp: Vector3 = mid_row["p"]
	var mrf := Vector3((mid_row["r"] as Vector3).x, 0.0, (mid_row["r"] as Vector3).z).normalized()
	var mrot := Basis(mrf, Vector3.UP, mrf.cross(Vector3.UP))
	for k in 4:
		var lx := -12.0 + float(k) * 8.0
		kit.box(Transform3D(mrot, Vector3(mp.x, top + 0.9, mp.z) + mrf * lx), Vector3(4.0, 1.8, 3.0), ROOF)
	var bmi := MeshInstance3D.new()
	bmi.name = "PredioTunel"
	bmi.mesh = kit.commit(null, BUILDING_MAT)
	bmi.set_instance_shader_parameter(&"wall_color", Color(0.97, 0.96, 0.93))
	bmi.set_instance_shader_parameter(&"accent_color", Palette.MAGENTA)
	bmi.set_instance_shader_parameter(&"ground_floor", 0.0)
	add_child(bmi)
	var pmi := MeshInstance3D.new()
	pmi.name = "Porticos"
	pmi.mesh = portal.commit(null, PROPS_MAT)
	add_child(pmi)
	site.add_blocker(Vector2(mid.x, mid.z), (SIDE_WING * 2.0 + 30.0) * 0.6)
