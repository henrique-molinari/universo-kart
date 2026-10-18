class_name Track
extends Node3D
## Raiz de uma pista: constrói (em tempo de carregamento) a geometria da pista, o terreno,
## o lago/ponte e o cenário do campus a partir do TrackPath + SiteMap.
## Outros sistemas (corrida, IA, itens) usam `track_path` e aguardam `track_ready`.

signal track_ready

const MAT_ROAD := preload("res://assets/materials/road.tres")
const MAT_CURB := preload("res://assets/materials/curb.tres")
const MAT_BARRIER := preload("res://assets/materials/barrier.tres")
const MAT_TERRAIN := preload("res://assets/materials/terrain.tres")
const MAT_WATER := preload("res://assets/materials/water.tres")
const MAT_CONCRETE := preload("res://assets/materials/concrete.tres")
const MAT_PROPS := preload("res://assets/materials/painted_props.tres")

## Desligue para testes rápidos (só pista + terreno).
@export var build_scenery: bool = true

@onready var track_path: TrackPath = $TrackPath
@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var sky_controller: SkyController = $SkyController

var site: SiteMap
var scenery: CampusScenery
var is_ready: bool = false
var build_time_ms: int = 0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	track_path.build()
	site = SiteMap.new()
	_configure_site(site)
	site.build(track_path)
	_configure_materials()

	var tb := TrackMeshBuilder.new(track_path, site)
	tb.mat_road = MAT_ROAD
	tb.mat_curb = MAT_CURB
	tb.mat_grass = MAT_TERRAIN
	tb.mat_wall = MAT_BARRIER
	tb.mat_concrete = MAT_CONCRETE
	tb.mat_props = MAT_PROPS
	tb.build(self)

	var terrain := TerrainBuilder.new(site)
	terrain.material = MAT_TERRAIN
	terrain.water_material = MAT_WATER
	terrain.build(self)

	if build_scenery:
		scenery = CampusScenery.new()
		scenery.name = "Scenery"
		add_child(scenery)
		scenery.build(self)

	RenderQuality.apply_to_environment(world_environment.environment, GameState.quality, GameState.is_split_screen())
	build_time_ms = Time.get_ticks_msec() - t0
	print("[Track] '%s' construída em %d ms (volta = %.0f m)" % [name, build_time_ms, track_path.length])
	is_ready = true
	track_ready.emit()


## Elementos do sítio específicos deste circuito (lago, áreas planas do campus).
func _configure_site(s: SiteMap) -> void:
	# Lago no vale a oeste do morro: a ponte desce sobre ele e a pista margeia o braço sul.
	s.lakes = [
		Vector4(-205.0, -292.0, 54.0, 40.0),
		Vector4(-268.0, -262.0, 36.0, 26.0),
		Vector4(-334.0, -190.0, 34.0, 84.0),
		Vector4(-250.0, -330.0, 60.0, 30.0),
	]
	# Morro onde fica a subida até a crista (~18 m).
	s.hills = [Vector4(-110.0, -285.0, 130.0, 18.0), Vector4(395.0, -10.0, 120.0, 26.0)]
	s.flat_zones = [
		Vector4(0.0, 150.0, 230.0, 110.0),     # campus sul (atrás da arquibancada)
		Vector4(100.0, -82.0, 55.0, 45.0),     # miolo da curva 1 (planetário)
		Vector4(-150.0, -135.0, 55.0, 55.0),   # miolo do laço oeste (campo esportivo)
		Vector4(-20.0, -62.0, 70.0, 28.0),     # miolo junto à reta (boxes)
	]


func _configure_materials() -> void:
	var road := MAT_ROAD as ShaderMaterial
	var lay := track_path.layout
	road.set_shader_parameter(&"half_width", lay.road_width * 0.5)
	road.set_shader_parameter(&"track_length", track_path.length)
	road.set_shader_parameter(&"grid_first_row", lay.grid_first_row_distance)
	road.set_shader_parameter(&"grid_row_spacing", lay.grid_row_spacing)
	road.set_shader_parameter(&"grid_lateral", lay.grid_column_lateral)
	road.set_shader_parameter(&"grid_stagger", lay.grid_column_stagger)
	var pole := track_path.get_grid_transform(0)
	var pole_lat := track_path.get_lateral(pole.origin, track_path.wrap_offset(-lay.grid_first_row_distance))
	road.set_shader_parameter(&"pole_side", signf(pole_lat))
	road.set_shader_parameter(&"grid_slots", 8)


## Ponto de vista útil para câmeras de apresentação.
func get_bounds() -> AABB:
	var pts := track_path.get_sample_positions()
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	return box
