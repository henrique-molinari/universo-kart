extends Node
## Ferramenta de captura de telas REAIS (renderizadas; não use --headless).
## Uso (ver README.md nesta pasta):
##   Godot_console.exe --path <projeto> res://tools/capture/capture.tscn -- --shot=all --out=<pasta>
##
## Opções (depois de "--"):
##   --shot=a,b,c | all    vistas a capturar (padrão: overview)
##   --out=<pasta>         pasta de saída (padrão: user://captures)
##   --scene=<res://...>   cena a carregar (padrão: pista do campus)
##   --size=1920x1080      resolução da imagem
##   --frames=40           quadros de espera por vista (sombras/SSAO/nuvens assentarem)
##   --warmup=120          quadros de espera extra antes da 1ª vista
##   --quality=high        low|medium|high|ultra
##   --bench               mede FPS médio em cada vista (vsync desligado)
##   --list                lista as vistas e sai

const DEFAULT_SCENE := "res://scenes/tracks/campus_circuit.tscn"
const QUALITY_NAMES := {"low": 0, "medium": 1, "high": 2, "ultra": 3}

var _opts: Dictionary = {}
var _viewport: SubViewport
var _camera: Camera3D
var _scene: Node


func _ready() -> void:
	_opts = _parse_args(OS.get_cmdline_user_args())
	if _opts.has("list"):
		for v in CaptureViews.VIEWS:
			print("%-14s %s" % [v, CaptureViews.DESCRIPTIONS.get(v, "")])
		get_tree().quit()
		return
	if DisplayServer.get_name() == "headless":
		printerr("[capture] Rodando em modo headless: nada é renderizado. Rode sem --headless.")
		get_tree().quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	var size := _parse_size(str(_opts.get("size", "1920x1080")))
	var out_dir := str(_opts.get("out", "user://captures"))
	if out_dir.begins_with("user://") or out_dir.begins_with("res://"):
		out_dir = ProjectSettings.globalize_path(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var quality: int = QUALITY_NAMES.get(str(_opts.get("quality", "high")), 2)
	GameState.set_quality(quality as RenderQuality.Preset)
	var bench := _opts.has("bench")
	if bench:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	_viewport = SubViewport.new()
	_viewport.size = size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.audio_listener_enable_3d = true
	RenderQuality.apply_to_viewport(_viewport, GameState.quality)
	add_child(_viewport)

	# Pré-visualização na janela (a imagem salva vem da SubViewport, sempre no tamanho pedido).
	var preview := TextureRect.new()
	preview.texture = _viewport.get_texture()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(preview)

	var scene_path := str(_opts.get("scene", DEFAULT_SCENE))
	var packed := load(scene_path) as PackedScene
	if packed == null:
		printerr("[capture] Cena não encontrada: ", scene_path)
		get_tree().quit(1)
		return
	_scene = packed.instantiate()
	_viewport.add_child(_scene)
	if _scene is Track and not (_scene as Track).is_ready:
		await (_scene as Track).track_ready

	_camera = Camera3D.new()
	_camera.far = 6000.0
	_camera.near = 0.1
	_viewport.add_child(_camera)
	_camera.make_current()

	var shots: PackedStringArray = str(_opts.get("shot", "overview")).split(",", false)
	if shots.size() == 1 and shots[0] == "all":
		shots = PackedStringArray(CaptureViews.VIEWS)
	var frames := int(_opts.get("frames", "40"))
	var warmup := int(_opts.get("warmup", "120"))
	var first := true
	var failures := 0
	for shot in shots:
		var view := _get_view(shot)
		if view.is_empty():
			printerr("[capture] Vista desconhecida: ", shot)
			failures += 1
			continue
		_camera.fov = float(view.get("fov", 70.0))
		var pos: Vector3 = view["pos"]
		var target: Vector3 = view["target"]
		_camera.look_at_from_position(pos, target, Vector3.UP)
		await _wait_frames(frames + (warmup if first else 0))
		first = false
		if bench:
			var t0 := Time.get_ticks_usec()
			await _wait_frames(90)
			var dt := float(Time.get_ticks_usec() - t0) / 90.0
			print("[capture] %-14s %.2f ms/quadro (%.0f FPS)" % [shot, dt / 1000.0, 1000000.0 / dt])
		await RenderingServer.frame_post_draw
		var img := _viewport.get_texture().get_image()
		if img == null or img.is_empty():
			printerr("[capture] Falha ao ler a imagem da vista ", shot)
			failures += 1
			continue
		var file := out_dir.path_join(shot + ".png")
		var err := img.save_png(file)
		if err != OK:
			printerr("[capture] Erro ao salvar ", file, ": ", error_string(err))
			failures += 1
		else:
			print("[capture] salvo: ", file)
	get_tree().quit(1 if failures > 0 else 0)


func _get_view(shot: String) -> Dictionary:
	# Cenas podem definir vistas próprias (ex.: corrida em andamento, menus).
	if _scene.has_method("get_capture_view"):
		var v: Dictionary = _scene.call("get_capture_view", shot)
		if not v.is_empty():
			return v
	if _scene is Track:
		return CaptureViews.get_view(shot, _scene as Track)
	return {}


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _parse_args(args: PackedStringArray) -> Dictionary:
	var d := {}
	for a in args:
		var s := a.trim_prefix("--")
		var eq := s.find("=")
		if eq >= 0:
			d[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			d[s] = "true"
	return d


func _parse_size(s: String) -> Vector2i:
	var parts := s.to_lower().split("x")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return Vector2i(maxi(64, parts[0].to_int()), maxi(64, parts[1].to_int()))
	return Vector2i(1920, 1080)
