class_name CampusScenery
extends Node3D
## Cenário do campus: artes de marca, prédios, arquibancada, pórtico, placas/props e vegetação.
## A ordem importa: tudo que ocupa espaço registra "bloqueios" no SiteMap antes da vegetação.

var brand: BrandArt
var buildings: CampusBuildings
var grandstand: Grandstand
var start_gate: StartGate
var props: TracksideProps
var tunnel: TunnelBuilding
var vegetation: Vegetation


func build(track: Track) -> void:
	var path := track.track_path
	var site := track.site

	brand = BrandArt.new()
	add_child(brand)
	brand.bake.call_deferred()   # assíncrono: materiais recebem as texturas em ~2 quadros

	buildings = CampusBuildings.new()
	buildings.name = "Campus"
	add_child(buildings)
	buildings.build(site, path, brand)

	grandstand = Grandstand.new()
	grandstand.name = "Arquibancada"
	add_child(grandstand)
	var center_off := path.wrap_offset(-25.0)
	var gxf := path.get_transform_at(center_off, path.get_wall_lateral() + 4.2)
	# Base local da arquibancada: X ao longo da pista, +Z para longe da pista (lado direito).
	var fwd := path.get_forward(center_off)
	var right := path.get_right(center_off)
	var gy := site.height_at(gxf.origin.x, gxf.origin.z)
	grandstand.build(Transform3D(Basis(fwd, Vector3.UP, right), Vector3(gxf.origin.x, gy, gxf.origin.z)), brand, site)

	start_gate = StartGate.new()
	start_gate.name = "PorticoLargada"
	add_child(start_gate)
	start_gate.build(path, brand)

	tunnel = TunnelBuilding.new()
	tunnel.name = "PredioTunel"
	add_child(tunnel)
	tunnel.build(path, site, brand)

	props = TracksideProps.new()
	props.name = "Props"
	add_child(props)
	props.build(path, site, brand)

	vegetation = Vegetation.new()
	vegetation.name = "Vegetacao"
	add_child(vegetation)
	vegetation.build(site, path)
	print("[Scenery] vegetação: %d instâncias, placas: %d, público: %d" % [vegetation.total_instances, props.board_count, grandstand.crowd_count])
