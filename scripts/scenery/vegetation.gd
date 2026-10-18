class_name Vegetation
extends Node3D
## Vegetação em massa: árvores (redondas, pinheiros, ciprestes), arbustos, tufos de grama,
## flores e pedras. Tudo em MultiMeshInstance3D por blocos espaciais, com LOD por
## visibility_range (malha detalhada perto, malha simples longe).

const FOLIAGE_MAT := preload("res://assets/materials/foliage.tres")
const CHUNK := 128.0
const FAR_CHUNK := 480.0

const TRUNK := Color(0.42, 0.28, 0.17, 0.0)
const TREE_TINTS: Array[Color] = [
	Color(0.36, 0.68, 0.20), Color(0.30, 0.60, 0.16), Color(0.46, 0.73, 0.22),
	Color(0.27, 0.54, 0.17), Color(0.52, 0.76, 0.26),
]
const PINE_TINTS: Array[Color] = [Color(0.16, 0.42, 0.22), Color(0.2, 0.48, 0.24), Color(0.13, 0.36, 0.2)]
const BLOSSOM := Color(1.0, 0.56, 0.74)
const AUTUMN := Color(0.98, 0.72, 0.24)
const FLOWER_TINTS: Array[Color] = [
	Color(1.0, 0.094, 0.388), Color(0.957, 0.906, 0.153), Color(0.98, 0.98, 1.0),
	Color(0.62, 0.5, 1.0), Color(1.0, 0.55, 0.2),
]

## Tipo -> {near: Mesh, far: Mesh|null, near_end: float, far_end: float, shadow: bool}
var _types: Dictionary = {}
## Tipo -> {Vector2i: Array[[Transform3D, Color]]}
var _instances: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _site: SiteMap
var _mat_tree: ShaderMaterial
var _mat_low: ShaderMaterial
var _clump := FastNoiseLite.new()
var total_instances: int = 0


func build(site: SiteMap, path: TrackPath) -> void:
	_site = site
	_rng.seed = 20260927
	_clump.seed = 77
	_clump.frequency = 0.012
	_mat_tree = FOLIAGE_MAT
	_mat_low = FOLIAGE_MAT.duplicate() as ShaderMaterial
	_mat_low.set_shader_parameter(&"sway_start", 0.0)
	_mat_low.set_shader_parameter(&"wind_strength", 0.12)
	_mat_low.set_shader_parameter(&"wind_speed", 2.1)
	_make_meshes()
	_scatter_trees()
	_scatter_trackside(path)
	_scatter_ground_cover(path)
	_scatter_far_forest()
	_create_multimeshes()


# ------------------------------------------------------------------ malhas

func _make_meshes() -> void:
	# Árvore redonda (copa em "nuvem" de esferas).
	var near := MeshKit.new()
	near.cylinder(Transform3D(Basis.IDENTITY, Vector3.ZERO), 0.36, 0.22, 3.6, 8, TRUNK, false)
	var leaf := Color(1, 1, 1, 1)
	near.sphere(Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.88, 1)), Vector3(0, 4.9, 0)), 2.7, 7, 11, leaf, 0.5, 1.0)
	near.sphere(Transform3D(Basis.IDENTITY, Vector3(1.55, 4.3, 0.5)), 1.9, 6, 10, leaf, 0.5, 1.0)
	near.sphere(Transform3D(Basis.IDENTITY, Vector3(-1.3, 4.5, -0.9)), 1.85, 6, 10, leaf, 0.5, 1.0)
	near.sphere(Transform3D(Basis.IDENTITY, Vector3(-0.4, 4.2, 1.5)), 1.6, 6, 9, leaf, 0.5, 1.0)
	near.sphere(Transform3D(Basis.IDENTITY, Vector3(0.3, 6.5, 0.2)), 1.7, 6, 9, leaf, 0.35, 1.0)
	var far := MeshKit.new()
	far.cylinder(Transform3D(Basis.IDENTITY, Vector3.ZERO), 0.36, 0.22, 3.4, 5, TRUNK, false)
	far.sphere(Transform3D(Basis.IDENTITY.scaled(Vector3(1.25, 1.1, 1.25)), Vector3(0, 5.0, 0)), 2.7, 5, 7, leaf, 0.5, 1.0)
	_register("tree_round", near.commit(null, _mat_tree), far.commit(null, _mat_tree), 170.0, 1500.0, true)

	# Pinheiro (cones empilhados).
	var pn := MeshKit.new()
	pn.cylinder(Transform3D(Basis.IDENTITY, Vector3.ZERO), 0.3, 0.2, 2.2, 7, TRUNK, false)
	pn.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0)), 2.6, 0.0, 3.6, 12, Color(0.8, 0.8, 0.8, 1.0), true, Color(0.5, 0.5, 0.5, 1.0))
	pn.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 3.6, 0)), 2.1, 0.0, 3.3, 12, Color(0.92, 0.92, 0.92, 1.0), true, Color(0.55, 0.55, 0.55, 1.0))
	pn.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 5.5, 0)), 1.5, 0.0, 3.0, 10, Color(1, 1, 1, 1.0), true, Color(0.6, 0.6, 0.6, 1.0))
	var pf := MeshKit.new()
	pf.cylinder(Transform3D(Basis.IDENTITY, Vector3.ZERO), 0.3, 0.2, 2.0, 4, TRUNK, false)
	pf.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0)), 2.6, 0.0, 6.9, 6, Color(0.9, 0.9, 0.9, 1.0), true, Color(0.5, 0.5, 0.5, 1.0))
	_register("tree_pine", pn.commit(null, _mat_tree), pf.commit(null, _mat_tree), 170.0, 1500.0, true)

	# Cipreste/álamo (elipsoide alto).
	var cy := MeshKit.new()
	cy.cylinder(Transform3D(Basis.IDENTITY, Vector3.ZERO), 0.25, 0.18, 1.6, 6, TRUNK, false)
	cy.sphere(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 2.6, 1.0)), Vector3(0, 4.6, 0)), 1.35, 8, 10, leaf, 0.45, 1.0)
	var cf := MeshKit.new()
	cf.sphere(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 2.6, 1.0)), Vector3(0, 4.6, 0)), 1.35, 5, 6, leaf, 0.45, 1.0)
	_register("tree_cypress", cy.commit(null, _mat_tree), cf.commit(null, _mat_tree), 170.0, 1200.0, true)

	# Arbusto.
	var bu := MeshKit.new()
	bu.sphere(Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.8, 1)), Vector3(0, 0.55, 0)), 1.0, 6, 9, leaf, 0.55, 1.0)
	bu.sphere(Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.8, 1)), Vector3(0.85, 0.4, 0.2)), 0.75, 5, 8, leaf, 0.55, 1.0)
	bu.sphere(Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.8, 1)), Vector3(-0.7, 0.42, -0.35)), 0.72, 5, 8, leaf, 0.55, 1.0)
	_register("bush", bu.commit(null, _mat_tree), null, 150.0, 0.0, true)

	# Tufo de grama (lâminas triangulares).
	var gr := MeshKit.new()
	for k in 7:
		var a := TAU * float(k) / 7.0 + 0.3 * float(k % 2)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-dir.z, 0.0, dir.x) * 0.07
		var tip := dir * 0.22 + Vector3(0, 0.42 + 0.12 * float(k % 3), 0)
		var nrm := (Vector3.UP * 0.8 + dir * 0.4).normalized()
		var base_c := Color(0.42, 0.42, 0.42, 1.0)
		var i0 := gr.add_vertex(dir * 0.05 - side, nrm, Vector2.ZERO, base_c)
		var i1 := gr.add_vertex(dir * 0.05 + side, nrm, Vector2.ZERO, base_c)
		var i2 := gr.add_vertex(tip, nrm, Vector2.ZERO, Color(0.95, 0.95, 0.85, 1.0))
		gr.tri(i0, i1, i2)
		# Face de trás (grama visível dos dois lados sem desligar o culling).
		var j0 := gr.add_vertex(dir * 0.05 - side, -nrm, Vector2.ZERO, base_c)
		var j1 := gr.add_vertex(dir * 0.05 + side, -nrm, Vector2.ZERO, base_c)
		var j2 := gr.add_vertex(tip, -nrm, Vector2.ZERO, Color(0.95, 0.95, 0.85, 1.0))
		gr.tri(j0, j1, j2)
	_register("grass", gr.commit(null, _mat_low), null, 60.0, 0.0, false)

	# Flores (hastes + corolas coloridas pela instância).
	var fl := MeshKit.new()
	var stem := Color(0.25, 0.5, 0.15, 0.0)
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.4
		var off := Vector3(cos(a), 0.0, sin(a)) * (0.18 + 0.05 * float(k))
		var h := 0.32 + 0.08 * float(k % 2)
		fl.cylinder(Transform3D(Basis.IDENTITY, off), 0.018, 0.014, h, 4, stem, false)
		fl.sphere(Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.55, 1)), off + Vector3(0, h, 0)), 0.09, 3, 6, Color(1, 1, 1, 1), 0.0, 1.0)
	_register("flower", fl.commit(null, _mat_low), null, 70.0, 0.0, false)

	# Pedra (esfera achatada e irregular).
	var rk := MeshKit.new()
	rk.sphere(Transform3D(Basis.IDENTITY.scaled(Vector3(1.3, 0.7, 1.0)), Vector3(0, 0.2, 0)), 1.0, 5, 7, Color(0.62, 0.6, 0.58, 0.0), 0.35, 0.0)
	var noise := FastNoiseLite.new()
	noise.frequency = 1.3
	for i in rk.verts.size():
		var v := rk.verts[i]
		rk.verts[i] = v + rk.norms[i] * noise.get_noise_3dv(v * 2.0) * 0.28
	var rock_mat := StandardMaterial3D.new()
	rock_mat.vertex_color_use_as_albedo = true
	rock_mat.vertex_color_is_srgb = true
	rock_mat.roughness = 0.92
	rock_mat.metallic_specular = 0.2
	_register("rock", rk.commit(null, rock_mat), null, 400.0, 0.0, true)
	# Floresta distante: só malhas simples, sem sombra.
	for base_name: String in ["tree_round", "tree_pine"]:
		var t: Dictionary = _types[base_name]
		_register("far_" + base_name, t["far"], null, 2600.0, 0.0, false)


func _register(type_name: String, near: Mesh, far: Mesh, near_end: float, far_end: float, shadow: bool) -> void:
	_types[type_name] = {"near": near, "far": far, "near_end": near_end, "far_end": far_end, "shadow": shadow}
	_instances[type_name] = {}


func _add(type_name: String, pos: Vector3, size: float, custom: Color, chunk_size: float = CHUNK, tilt: float = 0.06) -> void:
	var b := Basis(Vector3.UP, _rng.randf() * TAU)
	if tilt > 0.0:
		b = Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.0, tilt)) * b
	b = b.scaled(Vector3.ONE * size)
	var key := Vector2i(floori(pos.x / chunk_size), floori(pos.z / chunk_size))
	var chunks: Dictionary = _instances[type_name]
	if not chunks.has(key):
		chunks[key] = []
	(chunks[key] as Array).append([Transform3D(b, pos), custom])
	total_instances += 1


# ------------------------------------------------------------------ distribuição

func _tree_custom(pine: bool) -> Color:
	var c: Color
	if pine:
		c = PINE_TINTS[_rng.randi() % PINE_TINTS.size()]
	else:
		var r := _rng.randf()
		if r < 0.045:
			c = BLOSSOM
		elif r < 0.075:
			c = AUTUMN
		else:
			c = TREE_TINTS[_rng.randi() % TREE_TINTS.size()]
	var v := _rng.randf_range(0.92, 1.08)
	return Color(c.r * v, c.g * v, c.b * v, _rng.randf())


func _scatter_trees() -> void:
	var spacing := 7.0
	var o := _site.origin
	var extent := _site.cells * SiteMap.CELL
	var n := floori(extent / spacing)
	for iz in n:
		for ix in n:
			_try_tree(o.x + (float(ix) + _rng.randf()) * spacing, o.y + (float(iz) + _rng.randf()) * spacing)


## Densidade de árvores: manchas de floresta densas com clareiras (ruído), mais fortes nas colinas.
func _tree_density(x: float, z: float) -> float:
	var r := _rim(x, z)
	var clump := _clump.get_noise_2d(x, z)
	var patch := smoothstep(-0.02, 0.22, clump)          # 0 = clareira, 1 = mata
	var detail := _clump.get_noise_2d(x * 3.1 + 71.0, z * 3.1)
	var rim_f := smoothstep(210.0, 330.0, r)
	var forest := lerpf(0.05, 0.95, patch) * (0.85 + detail * 0.3)
	var campus := 0.02 + 0.3 * patch
	return lerpf(campus, forest, rim_f)


func _try_tree(x: float, z: float) -> void:
	if _rng.randf() > _tree_density(x, z):
		return
	if not _site.is_free(x, z, 4.5, 1.5):
		return
	var h := _site.height_at(x, z)
	var nrm := _site.normal_at(x, z)
	if nrm.y < 0.78:
		return
	var r := _rim(x, z)
	var pos := Vector3(x, h - 0.15, z)
	var pine_chance := smoothstep(200.0, 420.0, r) * 0.6 + 0.08 + (0.25 if h > 10.0 else 0.0)
	var pick := _rng.randf()
	if pick < pine_chance:
		_add("tree_pine", pos, _rng.randf_range(0.9, 1.5), _tree_custom(true))
	elif pick < pine_chance + 0.12 and r < 300.0:
		_add("tree_cypress", pos, _rng.randf_range(0.85, 1.25), _tree_custom(false), CHUNK, 0.02)
	else:
		_add("tree_round", pos, _rng.randf_range(0.8, 1.4), _tree_custom(false))
	# Sub-bosque: arbustos ao pé das árvores.
	if _rng.randf() < 0.3:
		var a := _rng.randf() * TAU
		var bx := x + cos(a) * 3.5
		var bz := z + sin(a) * 3.5
		if _site.is_free(bx, bz, 1.5, 0.5):
			_add("bush", Vector3(bx, _site.height_at(bx, bz) - 0.1, bz), _rng.randf_range(0.8, 1.4), _bush_custom())


func _bush_custom() -> Color:
	var c := TREE_TINTS[_rng.randi() % TREE_TINTS.size()].darkened(0.1)
	if _rng.randf() < 0.12:
		c = FLOWER_TINTS[_rng.randi() % 2]
	return Color(c.r, c.g, c.b, _rng.randf())


func _grass_custom() -> Color:
	var g := Color(0.28, 0.54, 0.13).lerp(Color(0.46, 0.66, 0.2), _rng.randf())
	if _rng.randf() < 0.2:
		g = g.lerp(Color(0.62, 0.66, 0.28), 0.5)
	return Color(g.r, g.g, g.b, _rng.randf())


## Moldura da pista: arbustos atrás das muretas, tufos de grama junto à base das muretas
## (dentro do acostamento) e faixas de flores nos setores de canteiro.
func _scatter_trackside(path: TrackPath) -> void:
	var off := 0.0
	var tunnel := path.get_tunnel_range()
	while off < path.length:
		var in_tunnel := tunnel.x >= 0.0 and off > tunnel.x - 5.0 and off < tunnel.y + 5.0
		var bridge := path.get_bridge(off) > 0.01
		for side: int in [-1, 1]:
			var wl := path.get_wall_lateral(off, side)
			if not bridge and not in_tunnel:
				if _rng.randf() < 0.6:
					var p := path.to_world(off, float(side) * (wl + _rng.randf_range(3.0, 7.0)))
					if _site.is_free(p.x, p.z, 1.5, 1.0):
						_add("bush", Vector3(p.x, _site.height_at(p.x, p.z) - 0.1, p.z), _rng.randf_range(0.9, 1.6), _bush_custom())
				var surf := path.get_runoff_surface(off, side)
				if surf == TrackLayout.Surface.GRASS or surf == TrackLayout.Surface.FLOWERS:
					# Tufos na base da mureta (lado de dentro).
					for k in 3:
						var o2 := off + _rng.randf_range(-1.5, 1.5)
						var q := path.to_world(o2, float(side) * (path.get_wall_lateral(o2, side) - _rng.randf_range(0.25, 1.3)), -0.04)
						_add("grass", q, _rng.randf_range(0.9, 1.7), _grass_custom(), 64.0, 0.15)
				if surf == TrackLayout.Surface.FLOWERS:
					# Canteiro: flores densas no acostamento e atrás da mureta.
					for k in 10:
						var o3 := off + _rng.randf_range(-1.5, 1.5)
						var inside := _rng.randf() < 0.55
						var lat := path.get_wall_lateral(o3, side) + (-_rng.randf_range(0.3, 2.4) if inside else _rng.randf_range(1.2, 3.5))
						var q2 := path.to_world(o3, float(side) * lat, -0.03)
						if not inside:
							q2.y = _site.height_at(q2.x, q2.z) - 0.03
						var fc := FLOWER_TINTS[_rng.randi() % FLOWER_TINTS.size()]
						_add("flower", q2, _rng.randf_range(1.0, 1.6), Color(fc.r, fc.g, fc.b, _rng.randf()), 64.0, 0.1)
		off += 3.0


func _scatter_ground_cover(_path: TrackPath) -> void:
	var o := _site.origin
	var extent := _site.cells * SiteMap.CELL
	# Grama: amostragem densa só perto da pista e do campus (visível de perto).
	var spacing := 3.2
	var n := floori(extent / spacing)
	for iz in n:
		for ix in n:
			var x := o.x + (float(ix) + _rng.randf()) * spacing
			var z := o.y + (float(iz) + _rng.randf()) * spacing
			var d := _site.track_distance_at(x, z)
			if d > 70.0 and _rim(x, z) > 170.0:
				continue
			if _rng.randf() > 0.55:
				continue
			if not _site.is_free(x, z, 0.3, 0.0):
				continue
			var h := _site.height_at(x, z)
			_add("grass", Vector3(x, h - 0.03, z), _rng.randf_range(0.8, 1.6), _grass_custom(), 64.0, 0.15)
	# Flores em canteiros (manchas de ruído).
	var flower_noise := FastNoiseLite.new()
	flower_noise.seed = 9
	flower_noise.frequency = 0.03
	var fs := 2.6
	var fn := floori(extent / fs)
	for iz in fn:
		for ix in fn:
			var x := o.x + (float(ix) + _rng.randf()) * fs
			var z := o.y + (float(iz) + _rng.randf()) * fs
			if flower_noise.get_noise_2d(x, z) < 0.42:
				continue
			var d := _site.track_distance_at(x, z)
			if d > 110.0 and _rim(x, z) > 200.0:
				continue
			if not _site.is_free(x, z, 1.0, 0.0):
				continue
			var c := FLOWER_TINTS[_rng.randi() % FLOWER_TINTS.size()]
			_add("flower", Vector3(x, _site.height_at(x, z) - 0.02, z), _rng.randf_range(0.9, 1.5), Color(c.r, c.g, c.b, _rng.randf()), 64.0, 0.1)
	# Pedras na margem do lago e nas encostas.
	for i in 520:
		var x := o.x + _rng.randf() * extent
		var z := o.y + _rng.randf() * extent
		var ls := _site.lake_sdf(x, z)
		var near_lake := ls > 1.0 and ls < 12.0
		var steep := _site.normal_at(x, z).y < 0.85
		if not near_lake and not steep and _rim(x, z) < 300.0:
			continue
		if _site.beyond_wall_at(x, z) < 2.0:
			continue
		if _site.is_blocked(x, z, 0.0):
			continue
		_add("rock", Vector3(x, _site.height_at(x, z) - 0.2, z), _rng.randf_range(0.6, 2.4), Color(1, 1, 1, 0), CHUNK, 0.3)


## Floresta esparsa sobre o anel de colinas/montanhas (só malha distante).
func _scatter_far_forest() -> void:
	var c := _site.site_center
	var spacing := 20.0
	var extent := 1600.0
	var n := floori(extent * 2.0 / spacing)
	for iz in n:
		for ix in n:
			var x := c.x - extent + (float(ix) + _rng.randf()) * spacing
			var z := c.y - extent + (float(iz) + _rng.randf()) * spacing
			if _site.in_bounds(x, z):
				continue
			var r := _rim(x, z)
			if r > extent:
				continue
			var clump := _clump.get_noise_2d(x * 0.5, z * 0.5)
			if _rng.randf() > smoothstep(-0.1, 0.2, clump) * 0.9:
				continue
			var h := _site.far_height(x, z)
			var pos := Vector3(x, h - 0.3, z)
			var pine := _rng.randf() < 0.55
			var t := "tree_pine" if pine else "tree_round"
			_add("far_" + t, pos, _rng.randf_range(1.4, 2.4), _tree_custom(pine), FAR_CHUNK, 0.05)


func _rim(x: float, z: float) -> float:
	var dx := absf(x - _site.site_center.x)
	var dz := absf(z - _site.site_center.y)
	return pow(pow(dx, 4.0) + pow(dz, 4.0), 0.25)


# ------------------------------------------------------------------ MultiMesh

func _create_multimeshes() -> void:
	for type_name: String in _instances:
		var t: Dictionary = _types[type_name]
		var chunks: Dictionary = _instances[type_name]
		for key: Vector2i in chunks:
			var items: Array = chunks[key]
			if items.is_empty():
				continue
			var near_end: float = t["near_end"]
			var far_mesh: Mesh = t["far"]
			_make_mmi("%s_%d_%d" % [type_name, key.x, key.y], t["near"], items, 0.0, near_end, t["shadow"])
			if far_mesh != null:
				var far_end: float = t["far_end"]
				_make_mmi("%s_far_%d_%d" % [type_name, key.x, key.y], far_mesh, items, near_end - 25.0, far_end, false)


func _make_mmi(node_name: String, mesh: Mesh, items: Array, range_begin: float, range_end: float, shadow: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		var it: Array = items[i]
		mm.set_instance_transform(i, it[0])
		mm.set_instance_custom_data(i, it[1])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_begin = range_begin
	mmi.visibility_range_end = range_end
	mmi.visibility_range_begin_margin = 25.0 if range_begin > 0.0 else 0.0
	mmi.visibility_range_end_margin = 25.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)
