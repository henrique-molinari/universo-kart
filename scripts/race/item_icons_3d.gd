class_name ItemIcons3D
extends RefCounted
## Ícones 3D dos itens (escudo, foguete, banana, turbo, pulso): modelos "de brinquedo" (MeshKit) com
## materiais PBR (metal, verniz, vidro, emissivos) e iluminação de estúdio (luz principal quente,
## contorno frio e preenchimento). Os 5 são renderizados UMA vez numa faixa (SubViewport com câmera
## ortográfica, UPDATE_ONCE) que fica viva na raiz da árvore: custo zero por quadro na corrida.
## A HUD (ItemIcon) desenha a região do item: AtlasTexture sobre a ViewportTexture.

const CELL := 256        ## pixels por ícone
const SPAN := 1.85       ## unidades de mundo por célula
## Ordem das células = Kart.Item (sem NONE).
const ORDER: Array[int] = [Kart.Item.SHIELD, Kart.Item.ROCKET, Kart.Item.BANANA, Kart.Item.TURBO, Kart.Item.PULSE]

static var _vp: SubViewport
static var _atlas := {}

const GLASS_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
uniform vec3 tint : source_color = vec3(0.45, 0.85, 1.0);
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	ALBEDO = tint;
	EMISSION = tint * f * 0.9;
	ROUGHNESS = 0.03;
	SPECULAR = 0.9;
	ALPHA = mix(0.1, 0.85, f);
}
"""


## Cria (uma vez) o viewport dos ícones na raiz da árvore. Idempotente.
static func ensure() -> void:
	if is_instance_valid(_vp):
		return
	var root := (Engine.get_main_loop() as SceneTree).root
	_vp = SubViewport.new()
	_vp.name = "ItemIcons3D"
	_vp.size = Vector2i(CELL * ORDER.size(), CELL)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_8X
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_build_world(_vp)
	root.add_child.call_deferred(_vp)
	_atlas.clear()


## Textura do ícone do item (null se ainda não existir).
static func texture(item: int) -> Texture2D:
	var i := ORDER.find(item)
	if i < 0 or not is_instance_valid(_vp) or not _vp.is_inside_tree():
		return null
	if not _atlas.has(item):
		var at := AtlasTexture.new()
		at.atlas = _vp.get_texture()
		at.region = Rect2(i * CELL, 0, CELL, CELL)
		_atlas[item] = at
	return _atlas[item]


static func _build_world(vp: SubViewport) -> void:
	var root := Node3D.new()
	vp.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.55, 0.62, 0.78)
	psm.sky_horizon_color = Color(0.95, 0.94, 0.92)
	psm.ground_bottom_color = Color(0.12, 0.12, 0.14)
	psm.ground_horizon_color = Color(0.6, 0.6, 0.62)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	for l: Array in [[Vector3(-0.5, -0.7, -0.6), 1.5, Color(1.0, 0.95, 0.88)], [Vector3(0.3, -0.25, 1.0), 2.2, Color(0.8, 0.9, 1.0)], [Vector3(0.8, -0.2, -0.4), 0.4, Color(0.85, 0.88, 1.0)]]:
		var dl := DirectionalLight3D.new()
		dl.basis = Basis.looking_at((l[0] as Vector3).normalized())
		dl.light_energy = l[1]
		dl.light_color = l[2]
		root.add_child(dl)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = SPAN
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.position = Vector3(0, 0, 10)
	root.add_child(cam)
	cam.current = true
	for i in ORDER.size():
		var n := _model(ORDER[i])
		n.position = Vector3((float(i) - (ORDER.size() - 1) * 0.5) * SPAN, 0, 0)
		root.add_child(n)


static func _mat(rough: float, metal: float = 0.0, coat: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	if coat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = coat
		m.clearcoat_roughness = 0.05
	return m


## Partes acesas (chamas, anéis de energia): cor por vértice sem sombreamento.
static func _glow() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _mi(k: MeshKit, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(null, mat)
	return mi


## Polígono 2D (plano XY) extrudado em Z com espessura `depth`: frente, verso e laterais lisas.
static func _extrude(k: MeshKit, pts: PackedVector2Array, depth: float, c_face: Color, c_side: Color, z0: float = 0.0) -> void:
	if Geometry2D.is_polygon_clockwise(pts):
		pts.reverse()
	var tris := Geometry2D.triangulate_polygon(pts)
	var hz := depth * 0.5
	for side: float in [1.0, -1.0]:
		var base := k.verts.size()
		for p in pts:
			k.add_vertex(Vector3(p.x, p.y, z0 + hz * side), Vector3(0, 0, side), Vector2.ZERO, c_face)
		for t in range(0, tris.size(), 3):
			if side > 0.0:
				k.tri(base + tris[t], base + tris[t + 1], base + tris[t + 2])
			else:
				k.tri(base + tris[t], base + tris[t + 2], base + tris[t + 1])
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var e := (b - a).normalized()
		var n := Vector3(e.y, -e.x, 0.0)
		k.flat_quad(Vector3(a.x, a.y, z0 - hz), Vector3(b.x, b.y, z0 - hz), Vector3(b.x, b.y, z0 + hz), Vector3(a.x, a.y, z0 + hz), n, c_side)


## Contorno 2D deslocado (moldura/bisel) — expande o polígono `d` unidades.
static func _offset(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var r := Geometry2D.offset_polygon(pts, d, Geometry2D.JOIN_ROUND)
	return r[0] if r.size() > 0 else pts


static func _model(item: int) -> Node3D:
	var n := Node3D.new()
	match item:
		Kart.Item.SHIELD:
			# Brasão azul metálico com moldura prateada e estrela, dentro de uma bolha de vidro.
			var crest := PackedVector2Array([Vector2(0, 0.62), Vector2(0.5, 0.45), Vector2(0.46, -0.1), Vector2(0, -0.66), Vector2(-0.46, -0.1), Vector2(-0.5, 0.45)])
			var k := MeshKit.new()
			_extrude(k, _offset(crest, 0.07), 0.16, Color(0.86, 0.88, 0.92), Color(0.7, 0.72, 0.76))
			n.add_child(_mi(k, _mat(0.22, 0.9, 0.5)))
			var k2 := MeshKit.new()
			_extrude(k2, crest, 0.24, Color(0.1, 0.32, 1.0), Color(0.06, 0.2, 0.7))
			n.add_child(_mi(k2, _mat(0.18, 0.5, 1.0)))
			var star := PackedVector2Array()
			for j in 10:
				var a := PI * 0.5 + TAU * float(j) / 10.0
				var r := 0.27 if j % 2 == 0 else 0.11
				star.append(Vector2(cos(a) * r, sin(a) * r + 0.02))
			var k3 := MeshKit.new()
			_extrude(k3, star, 0.08, Color(0.98, 0.98, 1.0), Color(0.8, 0.82, 0.86), 0.13)
			n.add_child(_mi(k3, _mat(0.3, 0.2, 0.6)))
			var bubble := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.98
			sm.height = 1.96
			sm.radial_segments = 48
			sm.rings = 24
			bubble.mesh = sm
			var gm := ShaderMaterial.new()
			var sh := Shader.new()
			sh.code = GLASS_CODE
			gm.shader = sh
			bubble.material_override = gm
			n.add_child(bubble)
			n.rotation = Vector3(0.15, -0.45, 0.0)
			n.scale = Vector3.ONE * 0.9
		Kart.Item.ROCKET:
			var k := MeshKit.new()
			var red := Color(0.88, 0.1, 0.09)
			k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.42, 0)), 0.22, 0.22, 0.78, 32, Color(0.95, 0.95, 0.97))
			k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.36, 0)), 0.22, 0.0, 0.42, 32, red, false)
			k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.06, 0)), 0.225, 0.225, 0.06, 32, red)
			for j in 3:
				var fb := Basis(Vector3.UP, TAU * float(j) / 3.0 + 0.4)
				var fin := MeshKit.new()
				_extrude(fin, PackedVector2Array([Vector2(0.15, -0.1), Vector2(0.46, -0.52), Vector2(0.46, -0.66), Vector2(0.15, -0.46)]), 0.05, red, red.darkened(0.25))
				k.append_kit(fin, Transform3D(fb, Vector3.ZERO))
			n.add_child(_mi(k, _mat(0.25, 0.1, 1.0)))
			var win := MeshKit.new()
			win.sphere(Transform3D(Basis.from_scale(Vector3(1, 1, 0.4)), Vector3(0, 0.08, 0.2)), 0.1, 10, 16, Color(0.2, 0.55, 1.0))
			win.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.08, 0.2)), 0.12, 0.12, 0.03, 24, Color(0.75, 0.77, 0.8))
			win.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.5, 0)), 0.16, 0.12, 0.1, 24, Color(0.3, 0.31, 0.34))
			n.add_child(_mi(win, _mat(0.1, 0.7, 1.0)))
			var fl := MeshKit.new()
			fl.cylinder(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, -0.54, 0)), 0.13, 0.0, 0.5, 20, Color(1.0, 0.45, 0.05), false)
			fl.cylinder(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, -0.53, 0)), 0.08, 0.0, 0.32, 16, Color(1.0, 0.92, 0.45), false)
			n.add_child(_mi(fl, _glow()))
			n.rotation = Vector3(0.35, 0.5, -0.75)
			n.scale = Vector3.ONE * 1.12
		Kart.Item.BANANA:
			# Casca em arco: tubo de esferas encadeadas (afinando nas pontas), pontas marrons.
			var k := MeshKit.new()
			var steps := 26
			for j in steps + 1:
				var t := float(j) / steps
				var ang := lerpf(-1.15, 1.15, t)
				var r := 0.2 * pow(sin(PI * clampf(t * 0.92 + 0.04, 0.0, 1.0)), 0.6)
				var p := Vector3(sin(ang) * 0.6, -0.3 + (1.0 - cos(ang)) * 0.6, 0)
				var c := Color(1.0, 0.84, 0.14).lerp(Color(0.95, 0.72, 0.08), absf(t - 0.5))
				if t < 0.07 or t > 0.93:
					c = Color(0.36, 0.24, 0.08)
				k.sphere(Transform3D(Basis.IDENTITY, p), maxf(r, 0.05), 10, 16, c)
			k.cylinder(Transform3D(Basis(Vector3.BACK, -1.0), Vector3(-0.56, 0.11, 0)), 0.045, 0.035, 0.16, 12, Color(0.4, 0.5, 0.12))
			n.add_child(_mi(k, _mat(0.38, 0.0, 0.4)))
			n.rotation = Vector3(0.3, 0.35, -0.28)
			n.scale = Vector3.ONE * 1.05
		Kart.Item.TURBO:
			# Cilindro de nitro vermelho com faixa branca, válvula cromada e jatos de fogo.
			var k := MeshKit.new()
			var red := Color(0.86, 0.1, 0.1)
			k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.4, 0)), 0.3, 0.3, 0.8, 36, red, false)
			k.sphere(Transform3D(Basis.from_scale(Vector3(1, 0.45, 1)), Vector3(0, 0.4, 0)), 0.3, 12, 36, red)
			k.sphere(Transform3D(Basis.from_scale(Vector3(1, 0.45, 1)), Vector3(0, -0.4, 0)), 0.3, 12, 36, red)
			k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.08, 0)), 0.305, 0.305, 0.2, 36, Color(0.96, 0.96, 0.97), false)
			n.add_child(_mi(k, _mat(0.2, 0.2, 1.0)))
			var v := MeshKit.new()
			v.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), 0.09, 0.09, 0.14, 20, Color(0.8, 0.82, 0.85))
			v.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.62, 0)), 0.14, 0.14, 0.05, 20, Color(0.8, 0.82, 0.85))
			v.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.6, 0)), 0.17, 0.12, 0.1, 20, Color(0.3, 0.31, 0.34))
			n.add_child(_mi(v, _mat(0.12, 1.0)))
			var fl := MeshKit.new()
			for dx: float in [-0.1, 0.1]:
				fl.cylinder(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(dx, -0.64, 0)), 0.09, 0.0, 0.42, 16, Color(1.0, 0.45, 0.05), false)
				fl.cylinder(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(dx, -0.63, 0)), 0.05, 0.0, 0.26, 12, Color(1.0, 0.92, 0.45), false)
			n.add_child(_mi(fl, _glow()))
			n.rotation = Vector3(0.3, 0.4, -0.45)
		Kart.Item.PULSE:
			# Disco UNIFEOB azul metálico com anéis magenta acesos e raio amarelo em relevo.
			var k := MeshKit.new()
			k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.09)), 0.72, 0.72, 0.18, 48, Color(0.02, 0.12, 0.85))
			k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.11)), 0.78, 0.78, 0.14, 48, Color(0.8, 0.82, 0.86))
			n.add_child(_mi(k, _mat(0.2, 0.75, 1.0)))
			var rings := MeshKit.new()
			for rr: float in [0.6, 0.46]:
				var ring := PackedVector2Array()
				var hole := PackedVector2Array()
				for j in 48:
					var a := TAU * float(j) / 48.0
					ring.append(Vector2(cos(a), sin(a)) * rr)
					hole.append(Vector2(cos(a), sin(a)) * (rr - 0.045))
				# Anel = faixa entre dois círculos (dois semicírculos para triangular sem furo).
				for half in 2:
					var poly := PackedVector2Array()
					for j in 25:
						poly.append(ring[(half * 24 + j) % 48])
					for j in 25:
						poly.append(hole[(half * 24 + 24 - j) % 48])
					_extrude(rings, poly, 0.03, Color(1.0, 0.1, 0.39), Color(1.0, 0.1, 0.39), 0.1)
			n.add_child(_mi(rings, _glow()))
			var bolt := PackedVector2Array([Vector2(0.1, 0.62), Vector2(-0.3, -0.02), Vector2(-0.04, -0.02), Vector2(-0.16, -0.62), Vector2(0.32, 0.12), Vector2(0.05, 0.12), Vector2(0.24, 0.62)])
			var bk := MeshKit.new()
			_extrude(bk, bolt, 0.14, Color(1.0, 0.88, 0.15), Color(0.9, 0.62, 0.05), 0.07)
			n.add_child(_mi(bk, _mat(0.25, 0.3, 1.0)))
			n.rotation = Vector3(-0.2, -0.5, 0.1)
	return n
