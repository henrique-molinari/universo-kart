class_name ChaseCamera
extends Camera3D
## Câmera de perseguição suave (uma por SubViewport). Lê a pose interpolada do modelo do kart.

## FOV vertical: cada metade da tela é bem larga (32:9), então o FOV vertical é menor.
const BASE_FOV := 50.0

var kart: Kart
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _fwd := Vector3.FORWARD
var _init_done := false


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fov = BASE_FOV
	near = 0.1
	far = 3000.0


func snap() -> void:
	_init_done = false


func _process(delta: float) -> void:
	if kart == null or kart.model == null:
		return
	var xf := kart.model.get_global_transform_interpolated()
	var up := xf.basis.y.lerp(Vector3.UP, 0.6).normalized()
	var kfwd := kart._flat_forward()
	if not _init_done:
		_fwd = kfwd
	_fwd = _fwd.slerp(kfwd, 1.0 - exp(-6.0 * delta)).normalized()
	var base := xf.origin
	var boost := clampf(kart.boost_time, 0.0, 1.0)
	var dist := 4.6 + boost * 1.0
	var want_pos := base - _fwd * dist + up * 1.9
	var want_look := base + _fwd * 5.0 + up * 0.8
	var right := _fwd.cross(up).normalized()
	# Drift: a câmera abre um pouco para fora da curva (mais dinâmica).
	if kart.drifting:
		want_pos -= right * kart.drift_dir * 0.7
	# Introdução durante a contagem: começa de frente (3/4, mostrando o piloto) e gira em arco
	# até ficar atrás do kart exatamente no "GO" (o tempo da largada não muda).
	var r := kart.race as Race
	if r != null and r.state == Race.State.COUNTDOWN:
		var k := smoothstep(0.0, 1.0, clampf(r.countdown / Race.COUNTDOWN_TIME, 0.0, 1.0))
		if k > 0.0:
			var a := k * 2.6
			var orbit := (-_fwd * cos(a) + right * sin(a)) * lerpf(dist, 3.4, k) + up * lerpf(1.9, 1.25, k)
			want_pos = base + orbit
			want_look = want_look.lerp(base + up * 0.95, k)
	if not _init_done:
		_pos = want_pos
		_look = want_look
		_init_done = true
	_pos = _pos.lerp(want_pos, 1.0 - exp(-16.0 * delta))
	_look = _look.lerp(want_look, 1.0 - exp(-14.0 * delta))
	var p := _pos
	if kart.shake > 0.0:
		var a := kart.shake * 0.12
		var t := Time.get_ticks_msec() * 0.05
		p += Vector3(sin(t * 1.7), sin(t * 2.3), cos(t * 1.3)) * a
	global_transform = Transform3D(Basis.looking_at(_look - p, up), p)
	var target_fov := BASE_FOV + clampf(kart.speed / Kart.MAX_SPEED, 0.0, 1.5) * 5.0 + boost * 5.0
	fov = lerpf(fov, target_fov, 1.0 - exp(-4.0 * delta))
