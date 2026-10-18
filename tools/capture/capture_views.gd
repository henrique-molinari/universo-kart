class_name CaptureViews
extends RefCounted
## Pontos de vista nomeados para a ferramenta de captura.
## Cada vista devolve {pos: Vector3, target: Vector3, fov: float} calculado a partir da API da pista,
## então continuam válidas se o traçado mudar.
##
## Vistas paramétricas (NN = porcentagem da volta, 0..99):
##   lapNN  -> altura do kart olhando para a frente     revNN -> olhando para trás (vê o verso das coisas)
##   outNN  -> olhando para fora do circuito (direita)  inNN  -> olhando para dentro (esquerda)

const VIEWS: Array[String] = [
	"overview", "top", "world_edge", "world_edge2",
	"start_line", "start_gate", "gate_back", "grid", "pits_close", "grandstand", "stand_back", "banners",
	"track_curve", "banked", "s_curve", "tires", "climb", "crest", "bridge", "bridge_drive", "under_bridge",
	"hill", "lakeside", "chicane", "tunnel", "tunnel_inside", "tunnel_exit", "final_curve",
	"campus", "planetarium", "hill_sign", "hill_sign_back", "horizon", "lake", "barrier_close", "sky",
]

const DESCRIPTIONS := {
	"overview": "Vista aérea oblíqua do circuito inteiro",
	"top": "Vista de cima (planta) do sítio",
	"world_edge": "Muito alto e longe: borda do mundo (sul)",
	"world_edge2": "Muito alto e longe: borda do mundo (noroeste)",
	"start_line": "Altura do kart, atrás do grid, olhando o pórtico",
	"start_gate": "Pórtico de largada/chegada de perto (frente)",
	"gate_back": "Pórtico visto por trás (depois da linha)",
	"grid": "Vista elevada do grid, boxes e arquibancada",
	"pits_close": "Fachada dos boxes de perto",
	"grandstand": "Arquibancada e público",
	"stand_back": "Arquibancada vista por trás (lado do campus)",
	"banners": "Placas ao longo da reta principal",
	"track_curve": "Entrada da curva 1 (inclinada) à altura do kart",
	"banked": "Curva 1 inclinada vista de fora (caixa de brita)",
	"s_curve": "Curva em S com muro de pneus e canteiros",
	"tires": "Muro de pneus e flores de perto",
	"climb": "Subida do morro com pórtico de banners",
	"crest": "Crista do morro (ponto mais alto) antes da ponte",
	"bridge": "Ponte em arcos sobre o lago vista da margem",
	"bridge_drive": "Na ponte, descendo em direção ao lago",
	"under_bridge": "Sob a ponte, rente à água",
	"hill": "Descida após a ponte",
	"lakeside": "Trecho à beira do lago (cerca baixa)",
	"chicane": "Chicane com pneus",
	"tunnel": "Entrada da passagem sob o prédio",
	"tunnel_inside": "Dentro da passagem sob o prédio",
	"tunnel_exit": "Prédio do túnel visto após a saída (verso)",
	"final_curve": "Última curva inclinada com pórtico de banners",
	"campus": "Prédios do campus vistos da pista",
	"planetarium": "Planetário 'Universo' no miolo da curva 1",
	"hill_sign": "Letreiro UNIFEOB na encosta visto da reta principal",
	"hill_sign_back": "Letreiro UNIFEOB visto por trás",
	"horizon": "Olhando para fora do circuito (colinas/montanhas)",
	"lake": "Lago, praia e ponte vistos da margem",
	"barrier_close": "Mureta de perto (costuras, logo)",
	"sky": "Céu na direção do sol (halo + nuvens)",
}


static func has_view(view_name: String) -> bool:
	return VIEWS.has(view_name) or _is_parametric(view_name)


static func _is_parametric(n: String) -> bool:
	for pre: String in ["lap", "rev", "out", "in"]:
		if n.begins_with(pre) and n.substr(pre.length()).is_valid_int():
			return true
	return false


static func get_view(view_name: String, track: Track) -> Dictionary:
	var tp := track.track_path
	var L := tp.length
	if _is_parametric(view_name):
		for pre: String in ["lap", "rev", "out", "in"]:
			if view_name.begins_with(pre):
				var off := float(view_name.substr(pre.length())) / 100.0 * L
				var p := tp.to_world(off, 0.0, 1.8)
				match pre:
					"lap":
						return {"pos": p, "target": tp.to_world(off + 30.0, 0.0, 1.3), "fov": 75.0}
					"rev":
						return {"pos": p, "target": tp.to_world(off - 30.0, 0.0, 1.3), "fov": 75.0}
					"out":
						return {"pos": p, "target": p + tp.get_right(off) * 200.0 + Vector3(0, 10, 0), "fov": 70.0}
					_:
						return {"pos": p, "target": p - tp.get_right(off) * 200.0 + Vector3(0, 10, 0), "fov": 70.0}
	var b := track.get_bounds()
	var c := b.get_center()
	var bridge_mid := _bridge_mid(tp)
	match view_name:
		"overview":
			return {"pos": c + Vector3(150.0, 250.0, 390.0), "target": c + Vector3(-5.0, -20.0, -25.0), "fov": 55.0}
		"top":
			return {"pos": c + Vector3(0.0, 720.0, 1.0), "target": c, "fov": 55.0}
		"world_edge":
			return {"pos": Vector3(0, 900, 2200), "target": Vector3(0, 0, 0), "fov": 60.0}
		"world_edge2":
			return {"pos": Vector3(-1500, 500, -1500), "target": Vector3(0, 0, -100), "fov": 60.0}
		"start_line":
			return {"pos": tp.to_world(-34.0, -3.0, 1.9), "target": tp.to_world(10.0, 0.5, 4.2), "fov": 70.0}
		"start_gate":
			return {"pos": tp.to_world(-16.0, 5.0, 3.0), "target": tp.to_world(0.0, -1.0, 7.0), "fov": 65.0}
		"gate_back":
			return {"pos": tp.to_world(30.0, 3.0, 3.0), "target": tp.to_world(0.0, 0.0, 6.0), "fov": 65.0}
		"grid":
			return {"pos": tp.to_world(-70.0, 12.0, 14.0), "target": tp.to_world(-15.0, 0.0, 0.0), "fov": 60.0}
		"pits_close":
			return {"pos": tp.to_world(-40.0, -8.0, 1.8), "target": Vector3(-20, 4, -44), "fov": 65.0}
		"grandstand":
			return {"pos": tp.to_world(-10.0, -8.0, 3.0), "target": Vector3(-25.0, 6.0, 32.0), "fov": 65.0}
		"stand_back":
			return {"pos": Vector3(-25, 8, 80), "target": Vector3(-25, 8, 0), "fov": 65.0}
		"banners":
			return {"pos": tp.to_world(-80.0, 5.0, 1.8), "target": tp.to_world(-30.0, 11.0, 2.0), "fov": 70.0}
		"track_curve":
			return {"pos": tp.to_world(0.1 * L, 2.0, 1.9), "target": tp.to_world(0.1 * L + 45.0, -2.0, 1.0), "fov": 72.0}
		"banked":
			var ob := 0.17 * L
			var pb := tp.to_world(ob, tp.get_wall_lateral(ob, 1) + 22.0, 7.0)
			return {"pos": pb, "target": tp.to_world(ob + 5.0, 0.0, 0.0), "fov": 70.0}
		"s_curve":
			return {"pos": tp.to_world(0.27 * L, 2.0, 2.0), "target": tp.to_world(0.27 * L + 45.0, 0.0, 1.0), "fov": 70.0}
		"tires":
			var ot := 0.32 * L
			return {"pos": tp.to_world(ot, -4.0, 1.6), "target": tp.to_world(ot + 14.0, -tp.get_wall_lateral(ot + 14.0, -1), 0.6), "fov": 65.0}
		"climb":
			return {"pos": tp.to_world(0.40 * L, 2.0, 2.0), "target": tp.to_world(0.40 * L + 50.0, 0.0, 3.0), "fov": 72.0}
		"crest":
			return {"pos": tp.to_world(0.515 * L, 0.0, 2.0), "target": tp.to_world(0.515 * L + 40.0, 0.0, -1.0), "fov": 72.0}
		"bridge":
			var right := tp.get_right(bridge_mid)
			var p := tp.get_point_at(bridge_mid)
			return {"pos": p + right * 80.0 + tp.get_forward(bridge_mid) * 30.0 + Vector3(0.0, -4.0, 0.0), "target": p + Vector3(0.0, -6.0, 0.0), "fov": 62.0}
		"bridge_drive":
			return {"pos": tp.to_world(bridge_mid - 40.0, -2.0, 2.0), "target": tp.to_world(bridge_mid + 10.0, 0.0, -1.0), "fov": 72.0}
		"under_bridge":
			var pu := tp.get_point_at(bridge_mid)
			var ru := tp.get_right(bridge_mid)
			var wpos := pu + ru * 45.0
			wpos.y = track.site.water_level + 1.2
			return {"pos": wpos, "target": pu + Vector3(0, -4.0, 0), "fov": 70.0}
		"hill":
			return {"pos": tp.to_world(0.64 * L, 2.0, 2.2), "target": tp.to_world(0.64 * L + 50.0, 0.0, -1.5), "fov": 70.0}
		"lakeside":
			return {"pos": tp.to_world(0.69 * L, -3.0, 2.0), "target": tp.to_world(0.69 * L + 30.0, 12.0, 0.5), "fov": 72.0}
		"chicane":
			return {"pos": tp.to_world(0.735 * L, 0.0, 2.0), "target": tp.to_world(0.735 * L + 40.0, 0.0, 1.0), "fov": 72.0}
		"tunnel":
			var trange := tp.get_tunnel_range()
			return {"pos": tp.to_world(trange.x - 45.0, 2.0, 2.2), "target": tp.to_world(trange.x, 0.0, 3.5), "fov": 70.0}
		"tunnel_inside":
			var tr2 := tp.get_tunnel_range()
			return {"pos": tp.to_world(tr2.x + 6.0, -3.0, 1.8), "target": tp.to_world(tr2.y + 20.0, 0.0, 1.5), "fov": 72.0}
		"tunnel_exit":
			var tr3 := tp.get_tunnel_range()
			return {"pos": tp.to_world(tr3.y + 40.0, 2.0, 2.5), "target": tp.to_world(tr3.y, 0.0, 5.0), "fov": 70.0}
		"final_curve":
			return {"pos": tp.to_world(0.87 * L, -2.0, 2.0), "target": tp.to_world(0.87 * L + 50.0, 0.0, 2.0), "fov": 72.0}
		"campus":
			return {"pos": tp.to_world(55.0, 6.0, 4.0), "target": Vector3(-10.0, 14.0, 150.0), "fov": 65.0}
		"planetarium":
			return {"pos": tp.to_world(45.0, -4.0, 2.2), "target": Vector3(100.0, 12.0, -82.0), "fov": 65.0}
		"hill_sign":
			return {"pos": tp.to_world(35.0, 0.0, 1.8), "target": Vector3(350.0, 34.0, -18.0), "fov": 55.0}
		"hill_sign_back":
			return {"pos": Vector3(420.0, 55.0, -70.0), "target": Vector3(350.0, 32.0, -18.0), "fov": 60.0}
		"horizon":
			var off := 0.72 * L
			var p2 := tp.to_world(off, 0.0, 2.2)
			var outward := tp.get_right(off)
			return {"pos": p2, "target": p2 + outward * 200.0 + tp.get_forward(off) * 60.0 + Vector3(0.0, 12.0, 0.0), "fov": 70.0}
		"lake":
			return {"pos": Vector3(-300.0, 3.0, -330.0), "target": Vector3(-190.0, 6.0, -300.0), "fov": 65.0}
		"barrier_close":
			return {"pos": tp.to_world(60.0, 11.0, 1.2), "target": tp.to_world(66.0, 13.5, 0.3), "fov": 60.0}
		"sky":
			var p3 := tp.to_world(-40.0, 0.0, 2.0)
			var to_sun := track.sun.global_transform.basis.z
			var flat := Vector3(to_sun.x, 0.0, to_sun.z).normalized()
			return {"pos": p3, "target": p3 + flat * 100.0 + Vector3(0.0, 38.0, 0.0), "fov": 75.0}
	return {}


static func _bridge_mid(tp: TrackPath) -> float:
	# Meio do trecho de ponte mais longo.
	var best_len := 0.0
	var best_mid := tp.length * 0.59
	var o := 0.0
	var start := -1.0
	while o <= tp.length:
		var on := o < tp.length and tp.get_bridge(o) > 0.5
		if on and start < 0.0:
			start = o
		elif not on and start >= 0.0:
			if o - start > best_len:
				best_len = o - start
				best_mid = (start + o) * 0.5
			start = -1.0
		o += 2.0
	return best_mid
