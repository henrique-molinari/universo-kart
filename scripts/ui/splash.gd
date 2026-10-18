class_name SplashScreen
extends Control
## Splash "Raccons Games - UNIFEOB": anima a entrada (fade/escala), assenta num estado estático
## bonito e ENTÃO faz o trabalho pesado (constrói a pista persistente — bloqueia ~2 s — e aquece os
## shaders renderizando a pista atrás da splash); a síntese da música roda em paralelo numa thread.
## Só sai quando tudo terminou e passaram pelo menos MIN_TIME segundos.

const TITLE_SCENE := "res://scenes/title.tscn"
const MIN_TIME := 2.5
const MAX_AUDIO_WAIT := 12.0

var _t := 0.0
var _stage := 0        ## 0 animando, 1 construindo, 2 aquecendo, 3 aguardando, 4 saindo
var _content: Control
var _line: ColorRect
var _status: Label
var _warm_cam: Camera3D
var _warm_frames := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	AudioManager.generate()
	add_child(UiKit.gradient_bg())
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	var box := VBoxContainer.new()
	UiKit.anchor(box, Control.PRESET_CENTER, Rect2(-800, -260, 1600, 460))
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 28)
	_content.add_child(box)
	var logo := UiKit.logo(96.0)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(logo)
	var title := UiKit.label("Raccons Games - UNIFEOB", 72, Palette.WHITE, 12)
	box.add_child(title)
	_line = ColorRect.new()
	_line.color = Palette.MAGENTA
	_line.custom_minimum_size = Vector2(0, 6)
	_line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_line)
	_status = UiKit.label("carregando…", 26, Color(1, 1, 1, 0.0), 4)
	UiKit.anchor(_status, Control.PRESET_CENTER_BOTTOM, Rect2(-200, -100, 400, 44))
	add_child(_status)

	# Entrada: logo sobe com fade, texto encolhe até o lugar, faixa magenta se abre.
	logo.modulate.a = 0.0
	title.modulate.a = 0.0
	title.resized.connect(func() -> void: title.pivot_offset = title.size * 0.5)
	title.scale = Vector2(1.18, 1.18)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(logo, "modulate:a", 1.0, 0.7)
	tw.tween_property(title, "modulate:a", 1.0, 0.8).set_delay(0.3)
	tw.tween_property(title, "scale", Vector2.ONE, 0.9).set_delay(0.3)
	tw.tween_property(_line, "custom_minimum_size:x", 620.0, 0.7).set_delay(0.6)
	tw.tween_property(_status, "modulate:a", 1.0, 0.4).set_delay(1.0)
	_status.modulate.a = 0.0
	_status.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.75))


func _process(delta: float) -> void:
	_t += delta
	match _stage:
		0:
			# Entrada concluída (estado estático): agora pode travar a thread principal.
			if _t >= 1.45:
				_stage = 1
		1:
			var t0 := Time.get_ticks_msec()
			var track := GameState.ensure_track(true)
			print("[Splash] pista pronta em %d ms" % (Time.get_ticks_msec() - t0))
			# Renderiza a pista atrás da splash por alguns quadros para compilar os shaders.
			_warm_cam = Camera3D.new()
			_warm_cam.far = 6000.0
			add_child(_warm_cam)
			var xf := track.track_path.get_transform_at(40.0, 0.0, 6.0)
			_warm_cam.global_transform = xf
			_warm_cam.current = true
			_stage = 2
		2:
			_warm_frames += 1
			if _warm_frames >= 4:
				_warm_cam.queue_free()
				_warm_cam = null
				_stage = 3
		3:
			var audio_ok := AudioManager.is_audio_ready() or _t > MAX_AUDIO_WAIT
			if AudioManager.is_audio_ready():
				AudioManager.play_music(&"title")
			if audio_ok and _t >= MIN_TIME:
				_stage = 4
				var tw := create_tween().set_parallel(true)
				tw.tween_property(_content, "modulate:a", 0.0, 0.45)
				tw.tween_property(_status, "modulate:a", 0.0, 0.3)
				tw.chain().tween_callback(func() -> void: SceneRouter.goto(TITLE_SCENE, 0.3))
