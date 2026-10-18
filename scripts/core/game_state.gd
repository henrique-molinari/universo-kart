extends Node
## Autoload "GameState": configurações globais (jogadores, corrida, qualidade).
## Mantido entre cenas; menus escrevem aqui e a corrida lê daqui.

signal settings_changed

const MAX_LOCAL_PLAYERS := 2
const DEFAULT_TRACK := "res://scenes/tracks/campus_circuit.tscn"

## Nomes dos NPCs (IA).
const AI_NAMES: Array[String] = ["Turbo", "Faísca", "Cometa", "Nebulosa", "Órbita", "Quasar", "Pulsar"]

var num_local_players: int = 1
var num_ai: int = 5
var laps: int = 3
var track_scene: String = DEFAULT_TRACK
var quality: RenderQuality.Preset = RenderQuality.Preset.HIGH
var players: Array[PlayerConfig] = []

## Pista construída uma única vez (na splash) e reaproveitada por título e corrida.
## Fica sob este autoload (viewport raiz), então sobrevive às trocas de cena.
var track_node: Track = null

# Captura genérica de tela (splash/título/seleção): `-- --shot=<png> --shot-time=<s>`.
# A cena de corrida trata o próprio --shot (tempo de corrida).
var _shot_path := ""
var _shot_time := 3.0
var _shot_clock := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset_players()
	RenderQuality.apply_global(quality)
	RenderQuality.apply_to_viewport(get_viewport(), quality)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--shot-time="):
			_shot_time = a.substr(12).to_float()


func _process(delta: float) -> void:
	if _shot_path == "":
		return
	var cs := get_tree().current_scene
	if cs != null and cs is Race:
		return
	_shot_clock += delta
	if _shot_clock >= _shot_time:
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("[GameState] captura salva: %s" % _shot_path)
		_shot_path = ""
		AudioManager.quit_clean(0)


## Devolve a pista persistente (constrói se preciso). A construção bloqueia a thread principal
## por ~2 s: a splash chama isto enquanto está num estado estático.
func ensure_track(scenery: bool = true) -> Track:
	if track_node != null and is_instance_valid(track_node) and track_node.build_scenery == scenery:
		return track_node
	if track_node != null and is_instance_valid(track_node):
		track_node.queue_free()
	var packed := load(track_scene) as PackedScene
	track_node = packed.instantiate() as Track
	track_node.build_scenery = scenery
	add_child(track_node)
	return track_node


func has_track() -> bool:
	return track_node != null and is_instance_valid(track_node) and track_node.is_ready


func reset_players() -> void:
	players.clear()
	for i in MAX_LOCAL_PLAYERS:
		var cfg := PlayerConfig.new()
		cfg.player_index = i
		cfg.is_human = true
		cfg.display_name = "Jogador %d" % (i + 1)
		# Padrão: P1 magenta, P2 amarelo (piloto sempre da cor do kart).
		cfg.color_index = 1 if i == 0 else 2
		cfg.set_color(Palette.SELECT_COLORS[cfg.color_index])
		players.append(cfg)


func get_player(index: int) -> PlayerConfig:
	return players[clampi(index, 0, players.size() - 1)]


func is_split_screen() -> bool:
	return num_local_players >= 2


func set_quality(preset: RenderQuality.Preset) -> void:
	quality = preset
	RenderQuality.apply_global(quality)
	RenderQuality.apply_to_viewport(get_viewport(), quality)
	settings_changed.emit()


## Gera configurações de IA com cores distintas das dos humanos.
func build_ai_configs(count: int) -> Array[PlayerConfig]:
	var used: Array[Color] = []
	for i in num_local_players:
		used.append(players[i].kart_color)
	var result: Array[PlayerConfig] = []
	var color_idx := 0
	for i in count:
		var cfg := PlayerConfig.new()
		cfg.is_human = false
		cfg.player_index = -1
		cfg.display_name = AI_NAMES[i % AI_NAMES.size()]
		var guard := 0
		while used.has(Palette.KART_COLORS[color_idx % Palette.KART_COLORS.size()]) and guard < 20:
			color_idx += 1
			guard += 1
		cfg.set_color(Palette.KART_COLORS[color_idx % Palette.KART_COLORS.size()])
		color_idx += 1
		result.append(cfg)
	return result
