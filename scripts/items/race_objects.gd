class_name RaceObjects
extends RefCounted
## Fábricas dos objetos de corrida: caixa de item, faixa de turbo, casca de banana e explosão.

const PAD_SHADER := preload("res://assets/shaders/boost_pad.gdshader")


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
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.55, 0.75, 1.0, 0.35)
	m.emission_enabled = true
	m.emission = Color(0.3, 0.5, 1.0)
	m.emission_energy_multiplier = 0.6
	m.rim_enabled = true
	m.roughness = 0.1
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material_override = m
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
	a.set_meta("active", true)
	a.body_entered.connect(func(body: Node3D) -> void:
		if body is Kart and a.get_meta("active"):
			on_pick.call(body, a))
	return a


## Esconde a caixa e reativa após `delay` s.
static func consume_box(a: Area3D, delay: float = 3.0) -> void:
	a.set_meta("active", false)
	for c in a.get_children():
		if c is Node3D:
			(c as Node3D).visible = false
	a.get_tree().create_timer(delay, false, true).timeout.connect(func() -> void:
		if is_instance_valid(a):
			a.set_meta("active", true)
			for c in a.get_children():
				if c is Node3D:
					(c as Node3D).visible = true)


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
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	sm.radial_segments = 6
	sm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = mat
	p.mesh = sm
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
	tw.chain().tween_interval(0.5)
	tw.chain().tween_callback(root.queue_free)
