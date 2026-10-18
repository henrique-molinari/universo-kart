class_name SplashScreen
extends Control
## Abertura em tela branca: logo da UNIFEOB (fade de entrada) e depois logo da Racoons Games.
## Enquanto a logo da UNIFEOB está parada, faz o trabalho pesado: constrói a pista persistente
## (bloqueia alguns segundos) e aquece os shaders renderizando atrás da abertura a pista, um kart
## com ET, um kart com piloto, partículas, caixa de item e explosão — assim nada compila (e trava)
## no meio da corrida. A síntese da música roda em paralelo numa thread.

const TITLE_SCENE := "res://scenes/title.tscn"
const LOGO_UNIFEOB := preload("res://assets/branding/logo unifeob.png")
const LOGO_RACOONS := preload("res://assets/branding/Racoons Games.png")
const MIN_UNIFEOB := 2.0     ## tempo mínimo com a logo da UNIFEOB (s)
const RACOONS_HOLD := 2.2    ## tempo da logo da Racoons Games na tela (s)
const MAX_AUDIO_WAIT := 12.0

var _t := 0.0
var _stage := 0        ## 0 entrada, 1 construindo, 2 aquecendo, 3 aguardando, 4 Racoons, 5 saindo
var _unifeob: TextureRect
var _racoons: TextureRect
var _status: Label
var _warm_cam: Camera3D
var _warm_root: Node3D
var _warm_icon: ItemIcon
var _warm_frames := 0
var _racoons_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	AudioManager.generate()
	var bg := ColorRect.new()
	bg.color = Color.WHITE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_unifeob = _logo(LOGO_UNIFEOB, 0.62)
	_racoons = _logo(LOGO_RACOONS, 0.95)
	_status = UiKit.label("carregando…", 24, Color(0.35, 0.36, 0.4), 0)
	UiKit.anchor(_status, Control.PRESET_CENTER_BOTTOM, Rect2(-200, -90, 400, 40))
	_status.modulate.a = 0.0
	add_child(_status)
	_unifeob.modulate.a = 0.0
	_unifeob.scale = Vector2.ONE * 0.94
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_unifeob, "modulate:a", 1.0, 0.7)
	tw.tween_property(_unifeob, "scale", Vector2.ONE, 0.9)
	tw.tween_property(_status, "modulate:a", 1.0, 0.4).set_delay(0.8)


## Logo centralizada ocupando `w_frac` da largura (mantém a proporção da imagem).
func _logo(tex: Texture2D, w_frac: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.anchor_left = 0.5 - w_frac * 0.5
	r.anchor_right = 0.5 + w_frac * 0.5
	r.anchor_top = 0.08
	r.anchor_bottom = 0.92
	r.offset_left = 0
	r.offset_right = 0
	r.offset_top = 0
	r.offset_bottom = 0
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.modulate.a = 0.0
	r.resized.connect(func() -> void: r.pivot_offset = r.size * 0.5)
	add_child(r)
	return r


func _process(delta: float) -> void:
	_t += delta
	match _stage:
		0:
			# Entrada concluída (logo parada): agora pode travar a thread principal.
			if _t >= 1.0:
				_stage = 1
		1:
			var t0 := Time.get_ticks_msec()
			var track := GameState.ensure_track(true)
			print("[Splash] pista pronta em %d ms" % (Time.get_ticks_msec() - t0))
			_build_warmup(track)
			_stage = 2
		2:
			_warm_frames += 1
			if _warm_frames >= 6:
				_warm_root.queue_free()
				_warm_cam.queue_free()
				_warm_icon.queue_free()
				_warm_root = null
				_warm_cam = null
				_stage = 3
		3:
			var audio_ok := AudioManager.is_audio_ready() or _t > MAX_AUDIO_WAIT
			if audio_ok and _t >= MIN_UNIFEOB:
				if AudioManager.is_audio_ready():
					AudioManager.play_music(&"title")
				_stage = 4
				_racoons.scale = Vector2.ONE * 0.94
				var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				tw.tween_property(_unifeob, "modulate:a", 0.0, 0.45)
				tw.parallel().tween_property(_status, "modulate:a", 0.0, 0.3)
				tw.tween_property(_racoons, "modulate:a", 1.0, 0.6)
				tw.parallel().tween_property(_racoons, "scale", Vector2.ONE, 0.8)
		4:
			_racoons_t += delta
			if _racoons_t >= RACOONS_HOLD:
				_stage = 5
				var tw := create_tween()
				tw.tween_property(_racoons, "modulate:a", 0.0, 0.45)
				tw.tween_callback(func() -> void: SceneRouter.goto(TITLE_SCENE, 0.3))


## Monta, na frente de uma câmera atrás da abertura, tudo o que tem shader próprio na corrida,
## para os shaders compilarem agora (e não no meio da partida).
func _build_warmup(track: Track) -> void:
	_warm_cam = Camera3D.new()
	_warm_cam.far = 6000.0
	add_child(_warm_cam)
	var xf := track.track_path.get_transform_at(40.0, 0.0, 6.0)
	_warm_cam.global_transform = xf
	_warm_cam.current = true
	_warm_root = Node3D.new()
	add_child(_warm_root)
	_warm_root.global_transform = Transform3D(xf.basis, xf.origin - xf.basis.z * 6.0 - xf.basis.y * 1.0)
	# Todos os personagens: gera os modelos procedurais e compila seus shaders.
	var chars: Array[int] = []
	for c in Characters.count():
		chars.append(c)
	for j in chars.size():
		var cfg := PlayerConfig.new()
		cfg.character = chars[j]
		cfg.player_index = -1
		cfg.set_color(Palette.KART_COLORS[j])
		var m := KartModel.new()
		m.build(cfg)
		m.position = Vector3(-1.5 * (chars.size() - 1) + 3.0 * j, 0, 0)
		_warm_root.add_child(m)
		m.set_pose(AlienDriver.Pose.VICTORY)   # cria os efeitos de comemoração
	# Partículas do kart (aditivas e com fumaça) e efeitos dos itens.
	var probe := Kart.new()
	for additive: bool in [true, false]:
		var p := probe._make_particles(Color.ORANGE, Color.WHITE, 4, 0.5, additive, 0.3)
		_warm_root.add_child(p)
		p.emitting = true
	probe.free()
	var box := RaceObjects.make_item_box(Vector3(0, 0, -2.0), Vector3.UP, func(_k: Kart, _b: Area3D) -> void: pass)
	_warm_root.add_child(box)
	RaceObjects.explode(_warm_root, _warm_root.global_position + Vector3(0, 1, 0), true)
	RaceObjects.pulse_wave(_warm_root, _warm_root.global_position, Vector3.UP)
	ItemIcons3D.ensure()  # ícones 3D dos itens: renderizados uma vez, já na abertura
	_warm_icon = ItemIcon.new()  # shader de brilho do ícone da HUD
	_warm_icon.size = Vector2(64, 64)
	_warm_icon.modulate.a = 0.02
	add_child(_warm_icon)
	_warm_icon.item = Kart.Item.ROCKET
