class_name RaceObjects
extends RefCounted
## Fábricas dos objetos de corrida: caixa de item, faixa de turbo, casca de banana e explosão.

const PAD_SHADER := preload("res://assets/shaders/boost_pad.gdshader")
const ITEM_BOX_SHADER := preload("res://assets/shaders/item_box.gdshader")
static var _box_mat: ShaderMaterial
static var _halo_mat: StandardMaterial3D


static func _unshaded(c: Color, alpha: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b)
	m.emission_energy_multiplier = 1.5
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


# ------------------------------------------------------------------ caixa de item

## Caixa giratória translúcida com "?". Chama on_pick(kart, box) ao ser atropelada.
static func make_item_box(pos: Vector3, up: Vector3, on_pick: Callable) -> Area3D:
	var a := Area3D.new()
	a.name = "ItemBox"
	a.collision_layer = PhysicsLayers.ITEM_PICKUP
	a.collision_mask = PhysicsLayers.KART
	a.monitorable = false
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.2
	cs.shape = sh
	a.add_child(cs)
	a.position = pos + up * 1.0
	var spin := Node3D.new()
	spin.name = "Spin"
	a.add_child(spin)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 1.25
	box.mesh = bm
	if _box_mat == null:
		_box_mat = ShaderMaterial.new()
		_box_mat.shader = ITEM_BOX_SHADER
	box.material_override = _box_mat
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	box.rotation = Vector3(deg_to_rad(35.0), 0.0, deg_to_rad(35.0))
	spin.add_child(box)
	var lbl := Label3D.new()
	lbl.text = "?"
	lbl.font_size = 128
	lbl.pixel_size = 0.006
	lbl.outline_size = 24
	lbl.modulate = Palette.YELLOW
	lbl.outline_modulate = Color(0.1, 0.05, 0.4)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = false
	a.add_child(lbl)
	# Halo suave no chão sob a caixa (aditivo).
	if _halo_mat == null:
		_halo_mat = StandardMaterial3D.new()
		_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_halo_mat.albedo_color = Color(0.35, 0.55, 1.0, 0.55)
		_halo_mat.albedo_texture = Kart._soft_texture()
	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	var hq := QuadMesh.new()
	hq.size = Vector2(3.2, 3.2)
	hq.orientation = PlaneMesh.FACE_Y
	halo.mesh = hq
	halo.material_override = _halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position = Vector3(0, -0.96, 0)
	a.add_child(halo)
	a.set_meta("active", true)
	a.body_entered.connect(func(body: Node3D) -> void:
		if body is Kart and a.get_meta("active"):
			on_pick.call(body, a))
	return a


## Esconde a caixa e reativa após `delay` s.
static func consume_box(a: Area3D, delay: float = 3.0) -> void:
	a.set_meta("active", false)
	_pickup_burst(a)
	for c in a.get_children():
		if c is Node3D:
			(c as Node3D).visible = false
	a.get_tree().create_timer(delay, false, true).timeout.connect(func() -> void:
		if is_instance_valid(a):
			a.set_meta("active", true)
			for c in a.get_children():
				if c is Node3D:
					(c as Node3D).visible = true)


## Estouro de brilhos coloridos ao coletar a caixa (efeito único, some sozinho).
static func _pickup_burst(a: Area3D) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 26
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.5
	p.gravity = Vector3(0, -6.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var q := QuadMesh.new()
	q.size = Vector2(0.32, 0.32)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Kart._soft_texture()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.3, 0.5))
	g.set_color(1, Color(0.3, 0.6, 1.0))
	g.add_point(0.33, Color(1.0, 0.9, 0.2))
	g.add_point(0.66, Color(0.3, 1.0, 0.5))
	p.color_initial_ramp = g
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	a.get_parent().add_child(p)
	p.global_position = a.global_position
	p.emitting = true
	p.finished.connect(p.queue_free)


# ------------------------------------------------------------------ faixa de turbo

static func make_boost_pad(xf: Transform3D, length: float) -> Area3D:
	var a := Area3D.new()
	a.name = "BoostPad"
	a.collision_layer = PhysicsLayers.TRIGGER
	a.collision_mask = PhysicsLayers.KART
	a.monitorable = false
	a.transform = xf
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(5.0, 2.5, length)
	cs.shape = sh
	cs.position = Vector3(0, 1.0, 0)
	a.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(5.0, length)
	mi.mesh = pm
	var sm := ShaderMaterial.new()
	sm.shader = PAD_SHADER
	sm.set_shader_parameter(&"arrows", maxf(length / 3.0, 2.0))
	mi.material_override = sm
	mi.position = Vector3(0, 0.05, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a.add_child(mi)
	a.body_entered.connect(func(body: Node3D) -> void:
		if body is Kart:
			(body as Kart).pad_boost())
	return a


# ------------------------------------------------------------------ banana

static func make_banana(pos: Vector3, up: Vector3, owner_kart: Kart) -> Area3D:
	var a := Area3D.new()
	a.name = "Banana"
	a.collision_layer = PhysicsLayers.PROJECTILE
	a.collision_mask = PhysicsLayers.KART
	a.monitorable = false
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.8
	cs.shape = sh
	cs.position = Vector3(0, 0.5, 0)
	a.add_child(cs)
	var k := MeshKit.new()
	var yel := Color(1.0, 0.85, 0.15)
	for i in 7:
		var t := float(i) / 6.0
		var ang := lerpf(-1.1, 1.1, t)
		var r := 0.2 * (1.0 - absf(t - 0.5) * 0.9)
		k.sphere(Transform3D(Basis.IDENTITY, Vector3(sin(ang) * 0.45, 0.25 + (1.0 - cos(ang)) * 0.45, 0)), r, 6, 10, yel if i > 0 and i < 6 else Color(0.35, 0.25, 0.08))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.4
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(null, mat)
	a.add_child(mi)
	a.position = pos
	a.basis = Basis.looking_at(Vector3.FORWARD.slide(up).normalized() if absf(up.z) < 0.9 else Vector3.RIGHT, up)
	var born := Engine.get_physics_frames()
	a.body_entered.connect(func(body: Node3D) -> void:
		if not (body is Kart) or a.is_queued_for_deletion():
			return
		var kk := body as Kart
		if kk == owner_kart and Engine.get_physics_frames() - born < 40:
			return
		kk.hit("spin")
		a.queue_free())
	return a


# ------------------------------------------------------------------ explosão

static func explode(parent: Node, pos: Vector3, big: bool = true) -> void:
	var root := Node3D.new()
	root.name = "Explosion"
	parent.add_child(root)
	root.global_position = pos
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 48 if big else 16
	p.lifetime = 0.7
	p.local_coords = false
	p.mesh = _sprite(0.55, true)
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1.0))
	shrink.add_point(Vector2(1, 0.3))
	p.scale_amount_curve = shrink
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 6.0 if big else 2.0
	p.initial_velocity_max = 14.0 if big else 5.0
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 3.0
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.5))
	g.add_point(0.4, Color(1.0, 0.45, 0.1))
	g.set_color(g.get_point_count() - 1, Color(0.2, 0.2, 0.2, 0.0))
	p.color_ramp = g
	root.add_child(p)
	p.emitting = true
	# Fumaça escura que sobe e se expande depois do fogo.
	var smoke := CPUParticles3D.new()
	smoke.one_shot = true
	smoke.explosiveness = 0.8
	smoke.amount = 18 if big else 6
	smoke.lifetime = 1.5
	smoke.local_coords = false
	smoke.mesh = _sprite(1.4 if big else 0.8, false)
	smoke.direction = Vector3.UP
	smoke.spread = 60.0
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 3.0
	smoke.gravity = Vector3(0, 0.6, 0)
	smoke.angle_min = -180.0
	smoke.angle_max = 180.0
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.6))
	smoke.scale_amount_curve = grow
	var sg := Gradient.new()
	sg.set_color(0, Color(0.32, 0.3, 0.3, 0.75))
	sg.set_color(1, Color(0.55, 0.55, 0.57, 0.0))
	smoke.color_ramp = sg
	root.add_child(smoke)
	smoke.emitting = true
	# Onda de choque rente ao chão (anel que se expande).
	var ring := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(2.0, 2.0)
	rq.orientation = PlaneMesh.FACE_Y
	ring.mesh = rq
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(1.0, 0.7, 0.35, 0.9)
	rmat.albedo_texture = _ring_texture()
	ring.material_override = rmat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0, -0.4, 0)
	root.add_child(ring)
	# Flash de luz + bola de fogo que expande e some.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 10.0 if big else 4.0
	light.omni_range = 14.0 if big else 6.0
	root.add_child(light)
	var ball := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 1.0
	bm.height = 2.0
	ball.mesh = bm
	var bmat := _unshaded(Color(1.0, 0.7, 0.25, 0.9), true)
	ball.material_override = bmat
	ball.scale = Vector3.ONE * 0.3
	root.add_child(ball)
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * (3.0 if big else 1.2), 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_property(bmat, "albedo_color:a", 0.0, 0.4)
	tw.tween_property(light, "light_energy", 0.0, 0.5)
	tw.tween_property(ring, "scale", Vector3.ONE * (7.0 if big else 3.0), 0.45).set_ease(Tween.EASE_OUT)
	tw.tween_property(rmat, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_interval(1.2)
	tw.chain().tween_callback(root.queue_free)


## Sprite de partícula suave (billboard). additive = fogo/brilho; senão fumaça com borda difusa.
static func _sprite(size: float, additive: bool) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = Kart._soft_texture()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	else:
		m.proximity_fade_enabled = true
		m.proximity_fade_distance = 1.0
	q.material = m
	return q


static var _ring_tex: GradientTexture2D


## Textura de anel (centro e borda transparentes, faixa brilhante perto da borda).
static func _ring_texture() -> GradientTexture2D:
	if _ring_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.62, Color(1, 1, 1, 0.15))
		g.add_point(0.82, Color(1, 1, 1, 1))
		_ring_tex = GradientTexture2D.new()
		_ring_tex.gradient = g
		_ring_tex.fill = GradientTexture2D.FILL_RADIAL
		_ring_tex.fill_from = Vector2(0.5, 0.5)
		_ring_tex.fill_to = Vector2(1.0, 0.5)
		_ring_tex.width = 128
		_ring_tex.height = 128
	return _ring_tex


# ------------------------------------------------------------------ pulso UNIFEOB

## Onda de choque do Pulso: anéis elétricos azul/violeta que se expandem rente ao chão,
## faíscas radiais e um clarão (as cores da UNIFEOB: azul #0018FE e magenta).
static func pulse_wave(parent: Node, pos: Vector3, up: Vector3) -> void:
	var root := Node3D.new()
	root.name = "PulseWave"
	parent.add_child(root)
	root.global_position = pos + up * 0.4
	root.basis = Basis.looking_at(Vector3.FORWARD.slide(up).normalized() if absf(up.z) < 0.9 else Vector3.RIGHT, up)
	var tw := root.create_tween().set_parallel(true)
	var cols: Array[Color] = [Color(0.35, 0.45, 1.0, 0.9), Color(1.0, 0.3, 0.75, 0.8)]
	for i in 2:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.9
		tm.outer_radius = 1.0
		tm.rings = 48
		tm.ring_segments = 6
		ring.mesh = tm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = cols[i]
		ring.material_override = m
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.scale = Vector3(1.0, 1.0 + i * 1.5, 1.0)
		root.add_child(ring)
		var dly := 0.08 * i
		tw.tween_property(ring, "scale", Vector3(26.0, 3.0 + i * 3.0, 26.0), 0.7).set_delay(dly).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(m, "albedo_color:a", 0.0, 0.7).set_delay(dly).set_ease(Tween.EASE_IN)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 40
	p.lifetime = 0.5
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.5
	sm.radial_segments = 4
	sm.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = mat
	p.mesh = sm
	p.particle_flag_align_y = true
	p.direction = Vector3.UP
	p.spread = 90.0
	p.flatness = 0.7
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 22.0
	p.gravity = Vector3.ZERO
	var g := Gradient.new()
	g.set_color(0, Color(0.9, 0.95, 1.0))
	g.set_color(1, Color(0.5, 0.3, 1.0, 0.0))
	p.color_ramp = g
	root.add_child(p)
	p.emitting = true
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.45, 1.0)
	light.light_energy = 8.0
	light.omni_range = 18.0
	root.add_child(light)
	tw.tween_property(light, "light_energy", 0.0, 0.6)
	tw.chain().tween_interval(0.2)
	tw.chain().tween_callback(root.queue_free)
