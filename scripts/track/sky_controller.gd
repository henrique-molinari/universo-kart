class_name SkyController
extends Node
## Anima as nuvens do céu (uniform `cloud_time`) e orienta o sol.
## Usar um uniform (em vez de TIME) mantém o Sky em modo INCREMENTAL (radiância barata).

@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D
@export var cloud_speed: float = 1.0
## Elevação do sol acima do horizonte (graus).
@export_range(5.0, 89.0) var sun_elevation_deg: float = 52.0
## Azimute DE ONDE vem o sol (graus; 0 = norte/-Z, 90 = leste/+X, 180 = sul/+Z).
@export_range(0.0, 360.0) var sun_azimuth_deg: float = 205.0
## Taxa de atualização das nuvens (Hz) — nuvens andam devagar, 20 Hz é suficiente.
@export var update_rate: float = 20.0

var _mat: ShaderMaterial
var _time: float = 0.0
var _accum: float = 0.0


func _ready() -> void:
	if world_environment and world_environment.environment and world_environment.environment.sky:
		_mat = world_environment.environment.sky.sky_material as ShaderMaterial
	apply_sun()


func apply_sun() -> void:
	if sun == null:
		return
	var el := deg_to_rad(sun_elevation_deg)
	var az := deg_to_rad(sun_azimuth_deg)
	# Vetor que aponta PARA o sol.
	var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	sun.global_transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD), Vector3.ZERO)


func set_cloud_time(t: float) -> void:
	_time = t
	if _mat:
		_mat.set_shader_parameter(&"cloud_time", _time)


func _process(delta: float) -> void:
	if _mat == null:
		return
	_time += delta * cloud_speed
	_accum += delta
	if _accum >= 1.0 / update_rate:
		_accum = 0.0
		_mat.set_shader_parameter(&"cloud_time", _time)
