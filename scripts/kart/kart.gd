class_name Kart
extends RigidBody3D
## Kart arcade (estilo Mario Kart) sobre Jolt: corpo = esfera deslizante sem rotação (robusta contra
## muretas e quinas), direção/aderência/drift controlados em _integrate_forces, "gravidade" ao longo
## da normal do chão (gruda em rampas, ponte e curvas inclinadas). O visual se alinha à normal.

signal item_changed(item: int)
signal got_hit(kind: String, blocked: bool)

enum Item { NONE, SHIELD, ROCKET, BANANA, TURBO, PULSE }
const ITEM_NAMES: Array[String] = ["", "ESCUDO", "FOGUETE", "BANANA", "TURBO", "PULSO"]
const ITEM_COLORS: Array[Color] = [Color.WHITE, Color(0.3, 0.8, 1.0), Color(1.0, 0.3, 0.2), Color(1.0, 0.9, 0.2), Color(1.0, 0.5, 0.1), Color(0.55, 0.45, 1.0)]
## Pulso UNIFEOB (5º item): quem está à frente fica eletrizado e mais lento por SLOW_TIME s.
const SLOW_TIME := 2.6
const SLOW_FACTOR := 0.6
## Largada com boost: acelerar desde o "3" (tolerância de START_GRACE s) dá turbo ao largar.
const START_GRACE := 0.35
const START_BOOST_TIME := 1.3

const RADIUS := 0.6
const MAX_SPEED := 23.0
const REVERSE_SPEED := 9.0
const ACCEL := 17.0
const BRAKE_DECEL := 32.0
const COAST_DECEL := 5.0
const OFFROAD_FACTOR := 0.5
const BOOST_EXTRA := 12.0
const GRIP := 12.0
const DRIFT_GRIP := 3.5
const GROUND_GRAVITY := 38.0
const AIR_GRAVITY := 28.0
const GROUND_MASK := PhysicsLayers.WORLD_ROAD | PhysicsLayers.WORLD_TERRAIN
## Drift com mini-turbo (estilo Mario Kart): carga -> nível 1 (azul), 2 (laranja), 3 (rosa/roxo).
const DRIFT_MIN_SPEED := 10.0
const DRIFT_LEVEL_CHARGE: Array[float] = [0.0, 0.9, 1.9, 3.0]
const DRIFT_BOOST_TIME: Array[float] = [0.0, 0.7, 1.2, 1.8]
const DRIFT_BOOST_POWER: Array[float] = [0.0, 0.75, 0.9, 1.05]
const DRIFT_COLORS: Array[Color] = [Color(1.0, 0.95, 0.8), Color(0.25, 0.6, 1.0), Color(1.0, 0.55, 0.1), Color(1.0, 0.3, 0.9)]

var player_index: int = 0
var config: PlayerConfig
var tp: TrackPath
var race: Node  ## Race: spawn_rocket(kart), spawn_banana(kart)

var control_enabled: bool = false
var autopilot: bool = false
var autopilot_lateral: float = 0.0
var autopilot_use_items: bool = true
var ai: AIDriver = null        ## NPC: gera as mesmas entradas que o PlayerInput
var top_speed_mul := 1.0       ## NPC: habilidade + rubber-band leve (0,94..1,04)

# Entradas (lidas a cada quadro de física).
var in_steer := 0.0
var in_throttle := 0.0
var in_brake := 0.0
var in_drift := false
var in_item := false
var _prev_item := false

# Estado.
var facing := Vector3.FORWARD
var ground_normal := Vector3.UP
var grounded := false
var speed := 0.0              ## velocidade no sentido da frente (m/s, negativa = ré)
var track_offset := -1.0
var surface: int = TrackPath.Surface.ROAD
var item: int = Item.NONE
var boost_time := 0.0
var boost_power := 1.0
var shield_time := 0.0
var stun_time := 0.0
var spin_time := 0.0
var invuln_time := 0.0
var slow_time := 0.0          ## Pulso: eletrizado e mais lento
var shake := 0.0
var drifting := false
var drift_dir := 0.0
var drift_charge := 0.0
var drift_level := 0          ## 0..3 (nível de mini-turbo carregado)
var finished := false
var autopilot_drift := false  ## testes/captura: o piloto automático faz drift nas curvas

# Estatísticas (testes/HUD).
var stats := {"pickups": 0, "used": [0, 0, 0, 0, 0, 0], "start_boost": 0, "pulsed": 0,"hits": 0, "blocked": 0, "respawns": 0, "pads": 0, "max_speed": 0.0, "drifts": 0, "drift_boosts": [0, 0, 0, 0]}

var model: KartModel
var _shield_mesh: MeshInstance3D
var _flames: Array[CPUParticles3D] = []
var _sparks: Array[CPUParticles3D] = []
var _smoke: Array[CPUParticles3D] = []
var _engine: AudioStreamPlayer
var _engine_3d: AudioStreamPlayer3D   ## NPCs: motor posicional (não soma no mix global)
var _pulse_fx: Node3D
var _pulse_mat: StandardMaterial3D
var _pulse_sparks: CPUParticles3D
var _air_time := 0.0
var _visual_yaw := 0.0
var _stuck_time := 0.0
var _outside_time := 0.0
var _pending_teleport: Variant = null
var _ap_reverse := 0.0
var _pending_velocity_reset := false
var _just_teleported := false
var _dbg_fell := false


func setup(cfg: PlayerConfig, index: int, path: TrackPath, race_node: Node) -> void:
	config = cfg
	player_index = index
	tp = path
	race = race_node
	name = "Kart%d" % (index + 1)
	collision_layer = PhysicsLayers.KART
	collision_mask = PhysicsLayers.WORLD_ROAD | PhysicsLayers.WORLD_WALL | PhysicsLayers.WORLD_TERRAIN | PhysicsLayers.KART
	mass = 120.0
	gravity_scale = 0.0
	lock_rotation = true
	can_sleep = false
	continuous_cd = true
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.0
	pm.bounce = 0.15
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = RADIUS
	cs.shape = sph
	add_child(cs)

	model = KartModel.new()
	model.name = "Model"
	add_child(model)
	model.build(cfg)

	_shield_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.55
	sm.height = 3.1
	_shield_mesh.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.35, 0.85, 1.0, 0.1)
	smat.emission_enabled = true
	smat.emission = Color(0.2, 0.7, 1.0)
	smat.emission_energy_multiplier = 0.25
	smat.rim_enabled = true
	smat.rim = 1.0
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield_mesh.material_override = smat
	_shield_mesh.position = Vector3(0, 0.1, 0)
	_shield_mesh.visible = false
	model.add_child(_shield_mesh)

	# Chama nos escapamentos (turbo), fagulhas e fumaça nas rodas traseiras (drift).
	for pt in model.exhaust_points:
		var f := _make_particles(Color(1.0, 0.45, 0.1), Color(1.0, 0.95, 0.5), 28, 0.22)
		f.position = pt
		f.initial_velocity_min = 2.0
		f.initial_velocity_max = 4.0
		f.spread = 12.0
		model.body_root.add_child(f)
		_flames.append(f)
	for pt in model.rear_wheel_points:
		var sp := _make_particles(Color(1, 1, 1), Color(1, 1, 1), 44, 0.3)
		sp.position = pt
		sp.direction = Vector3(-signf(pt.x) * 0.5, 0.9, 1.0)
		sp.spread = 40.0
		sp.initial_velocity_min = 4.0
		sp.initial_velocity_max = 7.5
		sp.gravity = Vector3(0, -12.0, 0)
		sp.scale_amount_min = 0.6
		sp.scale_amount_max = 1.2
		model.body_root.add_child(sp)
		_sparks.append(sp)
		var smk := _make_particles(Color(0.85, 0.85, 0.88), Color(0.95, 0.95, 0.95, 0.3), 10, 0.6)
		smk.position = pt + Vector3(0, 0.1, 0.1)
		smk.direction = Vector3(0, 1, 0.6)
		smk.initial_velocity_min = 0.6
		smk.initial_velocity_max = 1.4
		smk.scale_amount_min = 1.2
		smk.scale_amount_max = 2.6
		model.body_root.add_child(smk)
		_smoke.append(smk)
	_build_pulse_fx()
	if cfg.is_human:
		_engine = AudioStreamPlayer.new()
		_engine.bus = AudioManager.BUS_SFX
		_engine.volume_db = -17.0
		add_child(_engine)
	else:
		_engine_3d = AudioStreamPlayer3D.new()
		_engine_3d.bus = AudioManager.BUS_SFX
		_engine_3d.volume_db = -8.0
		_engine_3d.unit_size = 6.0
		_engine_3d.max_distance = 70.0
		add_child(_engine_3d)


## Efeito do Pulso: anéis elétricos violeta em volta do kart + faíscas (oculto até ser atingido).
func _build_pulse_fx() -> void:
	_pulse_fx = Node3D.new()
	_pulse_fx.name = "PulseFx"
	_pulse_fx.visible = false
	model.body_root.add_child(_pulse_fx)
	_pulse_mat = StandardMaterial3D.new()
	_pulse_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pulse_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pulse_mat.albedo_color = Color(0.65, 0.55, 1.0, 0.8)
	_pulse_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_pulse_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 2:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 1.05 + i * 0.25
		tm.outer_radius = 1.15 + i * 0.25
		tm.rings = 24
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = _pulse_mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position = Vector3(0, 0.35 + i * 0.45, 0)
		ring.rotation = Vector3(0.25 * (1 - 2 * i), 0.0, 0.2)
		_pulse_fx.add_child(ring)
	_pulse_sparks = _make_particles(Color(0.4, 0.3, 1.0), Color(0.85, 0.9, 1.0), 30, 0.25)
	_pulse_sparks.local_coords = true
	_pulse_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	_pulse_sparks.emission_sphere_radius = 1.0
	_pulse_sparks.direction = Vector3.UP
	_pulse_sparks.spread = 180.0
	_pulse_sparks.initial_velocity_min = 1.5
	_pulse_sparks.initial_velocity_max = 4.0
	_pulse_sparks.position = Vector3(0, 0.6, 0)
	_pulse_fx.add_child(_pulse_sparks)


## Som só dos humanos (os NPCs não enchem o mix global com pulinhos/turbos).
func _sfx(sfx_name: StringName, db: float = 0.0, pitch: float = 1.0) -> void:
	if ai == null:
		AudioManager.sfx(sfx_name, db, pitch)


func _make_particles(c0: Color, c1: Color, amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	var m := SphereMesh.new()
	m.radius = 0.09
	m.height = 0.18
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material = mat
	p.mesh = m
	p.direction = Vector3(0, 0.3, 1)
	p.spread = 25.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var g := Gradient.new()
	g.set_color(0, c1)
	g.set_color(1, Color(c0, 0.0))
	p.color_ramp = g
	return p


## Posiciona no grid/ponto dado (sem velocidade).
func place(xf: Transform3D) -> void:
	facing = -xf.basis.z
	ground_normal = xf.basis.y
	global_transform = Transform3D(Basis.IDENTITY, xf.origin + xf.basis.y * (RADIUS + 0.05))
	linear_velocity = Vector3.ZERO
	speed = 0.0
	track_offset = tp.get_closest_offset(xf.origin)
	_update_visual(0.0)
	reset_physics_interpolation()


# ------------------------------------------------------------------ entradas e efeitos

func _physics_process(delta: float) -> void:
	track_offset = tp.get_closest_offset(global_position, track_offset)
	surface = tp.get_surface_at(global_position, track_offset)
	_read_input(delta)

	boost_time = maxf(boost_time - delta, 0.0)
	shield_time = maxf(shield_time - delta, 0.0)
	stun_time = maxf(stun_time - delta, 0.0)
	spin_time = maxf(spin_time - delta, 0.0)
	invuln_time = maxf(invuln_time - delta, 0.0)
	slow_time = maxf(slow_time - delta, 0.0)
	shake = maxf(shake - delta * 2.5, 0.0)

	var ip := in_item
	if ip and not _prev_item and can_act() and item != Item.NONE:
		use_item()
	_prev_item = ip

	_check_respawn(delta)
	_update_visual(delta)
	_update_engine_sound()
	if _just_teleported:
		_just_teleported = false
		reset_physics_interpolation()
	stats["max_speed"] = maxf(stats["max_speed"], speed)


func can_act() -> bool:
	return can_drive() and not finished


func can_drive() -> bool:
	return control_enabled and stun_time <= 0.0 and spin_time <= 0.0


## Para o kart (comemoração de fim de corrida): sem controle, sem turbo/drift e velocidade zerada.
func halt() -> void:
	control_enabled = false
	autopilot_use_items = false
	boost_time = 0.0
	drifting = false
	drift_charge = 0.0
	drift_level = 0
	_pending_velocity_reset = true


func _read_input(delta: float) -> void:
	if autopilot or finished:
		_autopilot(delta)
		return
	if ai != null:
		ai.drive(delta)
		return
	in_steer = PlayerInput.steer(player_index)
	in_throttle = PlayerInput.throttle(player_index)
	in_brake = PlayerInput.brake(player_index)
	in_drift = PlayerInput.drift(player_index)
	in_item = PlayerInput.item(player_index)


## Piloto automático que segue o TrackPath (testes e karts que já terminaram).
func _autopilot(delta: float) -> void:
	var look := 9.0 + absf(speed) * 0.55
	var target := tp.to_world(track_offset + look, autopilot_lateral)
	var to := target - global_position
	var fwd := _flat_forward()
	var right := fwd.cross(ground_normal)
	var ang := atan2(to.dot(right), to.dot(fwd))
	in_steer = clampf(ang * 2.2, -1.0, 1.0)
	var curv := 0.0
	var s := 5.0
	while s <= 45.0:
		curv = maxf(curv, absf(tp.get_curvature(track_offset + s)))
		s += 5.0
	var vmax := sqrt(24.0 / maxf(curv, 0.0001))
	in_throttle = 1.0 if speed < vmax else 0.0
	in_brake = 0.7 if speed > vmax + 4.0 else 0.0
	in_drift = false
	if autopilot_drift and speed > 12.0:
		var c_near := tp.get_curvature(track_offset + 12.0) + tp.get_curvature(track_offset + 20.0)
		var c_hold := tp.get_curvature(track_offset + 6.0) + tp.get_curvature(track_offset + 14.0)
		in_drift = absf(c_near) > 0.03 or (drifting and absf(c_hold) > 0.01)
	# Destravar: ré curta se ficou parado encostado.
	if can_act() and absf(speed) < 1.0:
		_ap_reverse += delta
	elif _ap_reverse < 1.5:
		_ap_reverse = 0.0
	if _ap_reverse > 1.5:
		in_throttle = 0.0
		in_brake = 1.0
		in_steer = -in_steer
		_ap_reverse += delta
		if _ap_reverse > 2.6:
			_ap_reverse = 0.0
	in_item = autopilot_use_items and item != Item.NONE and not in_item


func give_item(new_item: int) -> void:
	item = new_item
	item_changed.emit(item)
	if new_item != Item.NONE:
		_sfx(&"item")


func use_item() -> void:
	var it := item
	item = Item.NONE
	item_changed.emit(item)
	stats["used"][it] += 1
	match it:
		Item.SHIELD:
			shield_time = 6.0
		Item.TURBO:
			apply_boost(1.5, 1.35)
		Item.ROCKET:
			race.spawn_rocket(self)
		Item.BANANA:
			race.spawn_banana(self)
		Item.PULSE:
			race.spawn_pulse(self)


func apply_boost(duration: float, power: float = 1.0) -> void:
	boost_power = maxf(power, boost_power) if boost_time > 0.0 else power
	boost_time = maxf(boost_time, duration)
	shake = maxf(shake, 0.5)
	_sfx(&"boost")


func is_shielded() -> bool:
	return shield_time > 0.0 or invuln_time > 0.0


## Efeito negativo: "spin" (casca) ou "stun" (foguete). Retorna true se aplicou.
func hit(kind: String) -> bool:
	if is_shielded():
		stats["blocked"] += 1
		got_hit.emit(kind, true)
		return false
	stats["hits"] += 1
	drifting = false
	drift_charge = 0.0
	drift_level = 0
	if kind == "pulse":
		# Não para o kart: corta o turbo e limita a velocidade por SLOW_TIME s.
		stats["pulsed"] += 1
		slow_time = SLOW_TIME
		boost_time = 0.0
		shake = maxf(shake, 0.6)
		_sfx(&"spark", -2.0, 0.6)
		got_hit.emit(kind, false)
		return true
	if kind == "spin":
		_sfx(&"spin")
	boost_time = 0.0
	speed = 0.0
	_pending_velocity_reset = true
	if kind == "stun":
		stun_time = 2.0
		shake = 1.0
	else:
		spin_time = 1.1
		shake = 0.4
	got_hit.emit(kind, false)
	return true


## Largada com boost (chamado no GO para quem acelerou desde o "3"): turbo, chama e fumaça
## no escapamento, tremor de câmera e vibração do controle.
func start_boost() -> void:
	stats["start_boost"] += 1
	apply_boost(START_BOOST_TIME, 1.0)
	shake = maxf(shake, 0.8)
	for f in _flames:
		f.restart()
	if ai == null:
		var dev := PlayerInput.device_of(player_index)
		if dev >= 0:
			Input.start_joy_vibration(dev, 0.35, 0.6, 0.35)


func pad_boost() -> void:
	stats["pads"] += 1
	apply_boost(1.2, 1.0)
	shake = maxf(shake, 0.7)


# ------------------------------------------------------------------ física

func _flat_forward() -> Vector3:
	var f := facing - ground_normal * facing.dot(ground_normal)
	if f.length_squared() < 0.0001:
		f = -global_basis.z
	return f.normalized()


func _integrate_forces(st: PhysicsDirectBodyState3D) -> void:
	var dt := st.step
	if _pending_teleport != null:
		var xf: Transform3D = _pending_teleport
		_pending_teleport = null
		st.transform = Transform3D(Basis.IDENTITY, xf.origin + xf.basis.y * (RADIUS + 0.3))
		st.linear_velocity = Vector3.ZERO
		facing = -xf.basis.z
		ground_normal = xf.basis.y
		speed = 0.0
		_just_teleported = true
		return
	var pos := st.transform.origin
	var q := PhysicsRayQueryParameters3D.create(pos + ground_normal * 0.1, pos - ground_normal * (RADIUS + 0.6), GROUND_MASK, [get_rid()])
	var hit_res := st.get_space_state().intersect_ray(q)
	grounded = not hit_res.is_empty()
	var target_n := Vector3.UP
	if grounded:
		target_n = hit_res["normal"]
		if target_n.dot(Vector3.UP) < 0.5:
			target_n = Vector3.UP
	ground_normal = ground_normal.lerp(target_n.normalized(), 1.0 - exp(-(14.0 if grounded else 3.0) * dt)).normalized()
	var n := ground_normal

	var v := st.linear_velocity
	if _pending_velocity_reset:
		_pending_velocity_reset = false
		v = n * minf(v.dot(n), 0.0)
	var fwd := _flat_forward()
	var right := fwd.cross(n)
	var vn := v.dot(n)
	var vp := v - n * vn
	speed = vp.dot(fwd)
	var lat := vp.dot(right)

	var active := can_drive()
	var thr := in_throttle if active else 0.0
	var brk := in_brake if active else 0.0
	var steer := in_steer if active else 0.0

	# Velocidade máxima conforme superfície e turbo.
	var vmax := MAX_SPEED * top_speed_mul
	if slow_time > 0.0:
		vmax *= SLOW_FACTOR
	if surface == TrackPath.Surface.OFFROAD or surface == TrackPath.Surface.OUTSIDE:
		vmax *= OFFROAD_FACTOR if boost_time <= 0.0 else 0.85
	if boost_time > 0.0 and slow_time <= 0.0:  # eletrizado pelo Pulso: turbos não somam
		vmax += BOOST_EXTRA * boost_power

	if grounded:
		if boost_time > 0.0 and active:
			speed = move_toward(speed, vmax, 45.0 * dt)
		elif thr > 0.01 and speed >= -0.5:
			if speed < vmax * thr:
				speed += ACCEL * (1.0 - 0.62 * clampf(speed / vmax, 0.0, 1.0)) * thr * dt
			else:
				speed = move_toward(speed, vmax * thr, (22.0 if speed > vmax else COAST_DECEL) * dt)
		elif brk > 0.01:
			if speed > 0.5:
				speed = move_toward(speed, 0.0, BRAKE_DECEL * brk * dt)
			else:
				speed = move_toward(speed, -REVERSE_SPEED * brk, 12.0 * dt)
		else:
			speed = move_toward(speed, 0.0, COAST_DECEL * dt)
		if speed > vmax + 0.5 and boost_time <= 0.0:
			speed = move_toward(speed, vmax, 22.0 * dt)
		if spin_time > 0.0 or stun_time > 0.0:
			speed = move_toward(speed, 0.0, 40.0 * dt)
		# Rampa: leve efeito da inclinação.
		speed -= fwd.y * 6.0 * dt

	# Drift com mini-turbo.
	_air_time = 0.0 if grounded else _air_time + dt
	_update_drift(dt, active, steer)

	# Esterço (gira a frente em torno da normal).
	var yaw := 0.0
	if drifting:
		yaw = drift_dir * lerpf(0.75, 2.2, (steer * drift_dir + 1.0) * 0.5)
	else:
		var sp := absf(speed)
		var turn := lerpf(2.4, 1.65, clampf(sp / MAX_SPEED, 0.0, 1.0)) * clampf(sp / 5.0, 0.0, 1.0)
		yaw = steer * turn * (1.0 if speed >= 0.0 else -1.0)
	if spin_time > 0.0:
		yaw = 0.0
	facing = fwd.rotated(n, -yaw * dt)
	fwd = _flat_forward()
	right = fwd.cross(n)

	# Aderência lateral.
	var grip := DRIFT_GRIP if drifting else GRIP
	if not grounded:
		grip = 1.0
	lat *= exp(-grip * dt)

	if grounded:
		vn -= GROUND_GRAVITY * dt
		v = fwd * speed + right * lat + n * vn
	else:
		v = fwd * speed + right * lat + n * vn
		v.y -= AIR_GRAVITY * dt
	st.linear_velocity = v


## Segurar drift numa curva com velocidade: pulinho + derrapagem controlada; a carga sobe mais
## rápido com a direção fechada (para dentro) e mais devagar com ela aberta.
func _update_drift(dt: float, active: bool, steer: float) -> void:
	if drifting:
		if not in_drift or not active or speed < 7.0 or _air_time > 0.35:
			_end_drift(active and not in_drift)
			return
		var align := steer * drift_dir
		drift_charge += dt * (1.35 if align > 0.4 else (0.75 if align < -0.4 else 1.0))
		var lvl := 0
		for i in range(1, DRIFT_LEVEL_CHARGE.size()):
			if drift_charge >= DRIFT_LEVEL_CHARGE[i]:
				lvl = i
		if lvl > drift_level:
			drift_level = lvl
			_sfx(&"spark", -4.0, 0.9 + 0.15 * lvl)
	elif active and in_drift and grounded and absf(steer) > 0.3 and speed > DRIFT_MIN_SPEED:
		drifting = true
		drift_dir = signf(steer)
		drift_charge = 0.0
		drift_level = 0
		stats["drifts"] += 1
		if model:
			model.hop()
		_sfx(&"hop", -6.0)


## Termina o drift; se `award`, dá o turbo do nível atingido (0,7 s / 1,2 s / 1,8 s).
func _end_drift(award: bool) -> void:
	drifting = false
	var lvl := drift_level
	drift_charge = 0.0
	drift_level = 0
	if award and lvl > 0:
		stats["drift_boosts"][lvl] += 1
		apply_boost(DRIFT_BOOST_TIME[lvl], DRIFT_BOOST_POWER[lvl])
		for f in _flames:
			f.restart()


# ------------------------------------------------------------------ respawn e visual

func _check_respawn(delta: float) -> void:
	if _pending_teleport != null or track_offset < 0.0:
		return
	var fell := global_position.y < tp.get_height(track_offset) - 12.0
	_outside_time = _outside_time + delta if surface == TrackPath.Surface.OUTSIDE else 0.0
	if control_enabled and not finished and in_throttle > 0.5 and absf(speed) < 1.0 and not autopilot:
		_stuck_time += delta
	elif control_enabled and (autopilot or ai != null) and absf(speed) < 1.0:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if fell or _outside_time > 1.0 or _stuck_time > 5.0:
		_dbg_fell = fell
		respawn()


func respawn() -> void:
	print("[Kart] P%d respawn em offset %.0f (queda/fora/preso: %s/%s/%s)" % [player_index + 1, track_offset, _dbg_fell, _outside_time > 1.0, _stuck_time > 5.0])
	stats["respawns"] += 1
	var off := tp.wrap_offset(track_offset - 2.0)
	var lat := clampf(tp.get_lateral(global_position, track_offset), -tp.get_half_width() + 2.5, tp.get_half_width() - 2.5)
	_pending_teleport = tp.get_transform_at(off, lat, 0.0)
	_stuck_time = 0.0
	_outside_time = 0.0
	drifting = false
	drift_charge = 0.0
	drift_level = 0
	invuln_time = 1.5


func _update_visual(delta: float) -> void:
	var fwd := _flat_forward()
	var up := ground_normal
	var target_yaw := drift_dir * 0.38 if drifting else 0.0
	if spin_time > 0.0:
		target_yaw = (1.1 - spin_time) / 1.1 * TAU * 2.0
		_visual_yaw = target_yaw
	else:
		_visual_yaw = wrapf(_visual_yaw, -PI, PI)
		_visual_yaw = lerpf(_visual_yaw, target_yaw, 1.0 - exp(-10.0 * delta)) if delta > 0.0 else target_yaw
	var b := Basis.looking_at(fwd, up).rotated(up, -_visual_yaw)
	if stun_time > 0.0:
		b = b.rotated(fwd.cross(up), sin((2.0 - stun_time) * PI) * 0.6)
	model.global_transform = Transform3D(b, global_position - up * RADIUS)
	model.body_root.visible = invuln_time <= 0.0 or int(invuln_time * 12.0) % 2 == 0
	model.animate(speed, in_steer if can_act() else 0.0, delta, drift_dir if drifting else 0.0)
	_shield_mesh.visible = shield_time > 0.0
	for f in _flames:
		f.emitting = boost_time > 0.0
	var c := DRIFT_COLORS[drift_level]
	for sp in _sparks:
		sp.emitting = drifting and drift_charge > 0.25
		sp.color = c
		sp.scale_amount_max = 1.2 + 0.4 * drift_level
	# Largada com boost: fumaça saindo junto com a chama nos primeiros metros.
	var burst: bool = stats["start_boost"] > 0 and boost_time > START_BOOST_TIME - 0.6 and speed < 15.0
	for sm in _smoke:
		sm.emitting = (drifting and grounded) or burst
	_pulse_fx.visible = slow_time > 0.0
	if slow_time > 0.0:
		var t := Time.get_ticks_msec() * 0.001
		_pulse_fx.rotation.y = t * 9.0
		_pulse_mat.albedo_color.a = 0.45 + 0.4 * absf(sin(t * 37.0))
		_pulse_sparks.emitting = true
	elif _pulse_sparks.emitting:
		_pulse_sparks.emitting = false


func _exit_tree() -> void:
	if _engine:
		_engine.stop()
		_engine.stream = null
	if _engine_3d:
		_engine_3d.stop()
		_engine_3d.stream = null


func _update_engine_sound() -> void:
	if _engine_3d:
		if _engine_3d.stream == null:
			_engine_3d.stream = AudioManager.get_sfx(&"engine")
			if _engine_3d.stream == null:
				return
			_engine_3d.play()
		_engine_3d.pitch_scale = 0.75 + clampf(absf(speed) / MAX_SPEED, 0.0, 1.6) * 0.9 + (0.15 if boost_time > 0.0 else 0.0)
		return
	if _engine.stream == null:
		_engine.stream = AudioManager.get_sfx(&"engine")
		if _engine.stream == null:
			return
		_engine.play()
	_engine.pitch_scale = 0.75 + clampf(absf(speed) / MAX_SPEED, 0.0, 1.6) * 0.9 + (0.15 if boost_time > 0.0 else 0.0)
