class_name Rocket
extends Node3D
## Foguete em LINHA RETA: voa na direção em que o kart apontava no disparo, colado ao chão
## (acompanha rampas/altura do terreno por raycast, sem virar para buscar alvo), por 3 s e explode.
## Atinge qualquer kart que tocar (exceto o dono logo após o disparo); bate em mureta -> explode.
## No impacto: explosão; o alvo fica parado 2 s e perde toda a velocidade (o escudo bloqueia).

signal exploded(reason: String, age: float)

const SPEED := 48.0
const LIFETIME := 3.0
const HIT_RADIUS := 1.9
const HOVER := 0.8
const OWNER_GRACE := 0.6
const GROUND_MASK := PhysicsLayers.WORLD_ROAD | PhysicsLayers.WORLD_TERRAIN
const WALL_MASK := PhysicsLayers.WORLD_WALL | PhysicsLayers.SCENERY

var shooter: Kart
var karts: Array[Kart] = []
var direction := Vector3.FORWARD   ## horizontal, fixa desde o disparo
var age := 0.0
var max_turn := 0.0                ## maior desvio angular (rad) da direção inicial (testes)
var _up := Vector3.UP
var _done := false


## `origin`/`dir`: ponto e direção do disparo (a corrida passa os do kart).
func setup(from: Kart, all_karts: Array[Kart], origin: Vector3, dir: Vector3) -> void:
	shooter = from
	karts = all_karts
	var flat := Vector3(dir.x, 0.0, dir.z)
	direction = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	name = "Rocket"
	position = origin
	_build_visual()


func _build_visual() -> void:
	var vis := Node3D.new()
	vis.name = "Visual"
	add_child(vis)
	var k := MeshKit.new()
	var red := Color(0.9, 0.12, 0.1)
	var body := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, 0.6))
	k.cylinder(body, 0.18, 0.18, 1.0, 12, Palette.WHITE)
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -0.4)), 0.18, 0.0, 0.45, 12, red)
	for i in 4:
		var b := Basis(Vector3.BACK, i * PI * 0.5)
		k.box(Transform3D(b, b * Vector3(0, 0.25, 0.45)), Vector3(0.04, 0.3, 0.3), red)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.3
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(null, mat)
	vis.add_child(mi)
	var trail := CPUParticles3D.new()
	trail.amount = 50
	trail.lifetime = 0.45
	trail.local_coords = false
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	sm.radial_segments = 6
	sm.rings = 3
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = pm
	trail.mesh = sm
	trail.direction = Vector3(0, 0, 1)
	trail.spread = 10.0
	trail.initial_velocity_min = 1.0
	trail.initial_velocity_max = 2.0
	trail.gravity = Vector3(0, 1.0, 0)
	trail.scale_amount_min = 1.0
	trail.scale_amount_max = 2.5
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.4))
	g.set_color(1, Color(0.4, 0.4, 0.4, 0.0))
	trail.color_ramp = g
	trail.position = Vector3(0, 0, 1.1)
	vis.add_child(trail)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.2)
	light.light_energy = 2.0
	light.omni_range = 5.0
	light.position = Vector3(0, 0, 1.2)
	vis.add_child(light)
	# Animação de disparo: cresce a partir do kart.
	vis.scale = Vector3.ONE * 0.2
	vis.create_tween().tween_property(vis, "scale", Vector3.ONE, 0.18).set_ease(Tween.EASE_OUT)


func _physics_process(delta: float) -> void:
	if _done:
		return
	age += delta
	var space := get_world_3d().direct_space_state
	var from := global_position
	var step := direction * SPEED * delta
	var nxt := from + step
	# Mureta/obstáculo entre a posição atual e a próxima.
	var wq := PhysicsRayQueryParameters3D.create(from, nxt + direction * 0.4, WALL_MASK)
	if not space.intersect_ray(wq).is_empty():
		_explode("wall")
		return
	# Altura do chão (acompanha rampas e o relevo, sem mudar a direção horizontal).
	var gq := PhysicsRayQueryParameters3D.create(nxt + Vector3.UP * 2.0, nxt - Vector3.UP * 10.0, GROUND_MASK)
	var g := space.intersect_ray(gq)
	if not g.is_empty():
		var gp: Vector3 = g["position"]
		nxt.y = lerpf(nxt.y, gp.y + HOVER, 1.0 - exp(-25.0 * delta))
		_up = _up.lerp(g["normal"], 1.0 - exp(-12.0 * delta)).normalized()
	else:
		nxt.y -= 6.0 * delta
	var fwd := (nxt - from).normalized() if nxt.distance_squared_to(from) > 0.000001 else direction
	global_transform = Transform3D(Basis.looking_at(fwd, _up if absf(fwd.dot(_up)) < 0.95 else Vector3.RIGHT), nxt)
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	max_turn = maxf(max_turn, flat.angle_to(direction))
	for k in karts:
		if not is_instance_valid(k):
			continue
		if k == shooter and age < OWNER_GRACE:
			continue
		if k.global_position.distance_to(global_position) < HIT_RADIUS:
			k.hit("stun")
			_explode("kart")
			return
	if age >= LIFETIME:
		_explode("timeout")


func _explode(reason: String) -> void:
	_done = true
	exploded.emit(reason, age)
	RaceObjects.explode(get_parent(), global_position, true)
	AudioManager.sfx(&"explosion")
	queue_free()
