class_name TitleScreen
extends Node
## Título: câmera sobrevoando a pista em loop (ShowcaseCamera) com a imagem 3D DESFOCADA
## (shader de blur sobre a textura da tela), logo "UNIVERSO KART" e "PRESSIONE ENTER OU A PARA COMEÇAR" pulsando.
## Enter (teclado) ou A/Start em qualquer controle -> seleção de cor.

const SELECT_SCENE := "res://scenes/select.tscn"
const BLUR_SHADER := preload("res://assets/shaders/screen_blur.gdshader")
const LOGO_TITLE := preload("res://assets/branding/universo_kart_logo.png")

var _press: Label
var _logo_box: Control
var _t := 0.0
var _leaving := false


func _ready() -> void:
	var track := GameState.ensure_track(true)
	RenderQuality.apply_to_environment(track.world_environment.environment, GameState.quality, false)
	var cam := ShowcaseCamera.new()
	cam.track = track
	cam.speed = 16.0
	cam.height = 9.0
	cam.look_ahead = 34.0
	cam.fov = 62.0
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	cam.current = true
	AudioManager.play_music(&"title")

	var layer := CanvasLayer.new()
	add_child(layer)
	var blur := ColorRect.new()
	blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bm := ShaderMaterial.new()
	bm.shader = BLUR_SHADER
	bm.set_shader_parameter(&"tint", Color(0.03, 0.035, 0.05, 0.42))
	bm.set_shader_parameter(&"vignette", 0.55)
	blur.material = bm
	layer.add_child(blur)

	_logo_box = VBoxContainer.new()
	(_logo_box as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	_logo_box.add_theme_constant_override(&"separation", 6)
	UiKit.anchor(_logo_box, Control.PRESET_CENTER, Rect2(-600, -350, 1200, 520))
	layer.add_child(_logo_box)
	var title_logo := TextureRect.new()
	title_logo.texture = LOGO_TITLE
	title_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_logo.custom_minimum_size = Vector2(1060, 506)
	title_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo_box.add_child(title_logo)
	_logo_box.resized.connect(func() -> void: _logo_box.pivot_offset = _logo_box.size * 0.5)

	_press = UiKit.label("PRESSIONE  ENTER  OU  A  PARA COMEÇAR", 42, Palette.UI_TEXT, 8)
	UiKit.anchor(_press, Control.PRESET_CENTER_BOTTOM, Rect2(-600, -250, 1200, 80))
	layer.add_child(_press)
	var foot := UiKit.label("Racoons Games - UNIFEOB", 24, Palette.UI_MUTED, 5)
	UiKit.anchor(foot, Control.PRESET_CENTER_BOTTOM, Rect2(-400, -70, 800, 40))
	layer.add_child(foot)
	var logo := UiKit.logo(40.0)
	UiKit.anchor(logo, Control.PRESET_TOP_RIGHT, Rect2(-230, 28, 200, 40))
	layer.add_child(logo)

	_logo_box.modulate.a = 0.0
	_logo_box.scale = Vector2(0.85, 0.85)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_logo_box, "modulate:a", 1.0, 0.5)
	tw.tween_property(_logo_box, "scale", Vector2.ONE, 0.7)


func _process(delta: float) -> void:
	_t += delta
	# "Press enter for start" pulsando; logo "respirando".
	_press.modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(_t * 4.2))
	var s := 1.0 + 0.04 * sin(_t * 4.2)
	_press.pivot_offset = _press.size * 0.5
	_press.scale = Vector2(s, s)
	if not _leaving and _t > 0.8:
		_logo_box.rotation = sin(_t * 1.3) * 0.015
		# Logo pulsando (cresce e diminui), começando do tamanho normal ao fim da entrada.
		var ls := 1.0 + 0.06 * sin((_t - 0.8) * 2.6)
		_logo_box.scale = Vector2(ls, ls)


func _input(event: InputEvent) -> void:
	if _leaving or _t < 0.3:
		return
	var go := false
	if event is InputEventKey:
		var ke := event as InputEventKey
		go = ke.pressed and not ke.echo and (ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER \
			or ke.physical_keycode == KEY_ENTER or ke.physical_keycode == KEY_KP_ENTER)
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		go = jb.pressed and (jb.button_index == JOY_BUTTON_A or jb.button_index == JOY_BUTTON_START)
	if go:
		_leaving = true
		get_viewport().set_input_as_handled()
		AudioManager.sfx(&"confirm")
		SceneRouter.goto(SELECT_SCENE)
