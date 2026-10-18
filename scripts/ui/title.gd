class_name TitleScreen
extends Node
## Título: câmera sobrevoando a pista em loop (ShowcaseCamera) com a imagem 3D DESFOCADA
## (shader de blur sobre a textura da tela), logo "UNIVERSO KART" e "Press enter for start" pulsando.
## Enter (teclado) ou A/Start em qualquer controle -> seleção de cor.

const SELECT_SCENE := "res://scenes/select.tscn"
const BLUR_SHADER := preload("res://assets/shaders/screen_blur.gdshader")

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
	blur.material = bm
	layer.add_child(blur)

	_logo_box = VBoxContainer.new()
	(_logo_box as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	_logo_box.add_theme_constant_override(&"separation", 6)
	UiKit.anchor(_logo_box, Control.PRESET_CENTER, Rect2(-700, -300, 1400, 400))
	layer.add_child(_logo_box)
	var top := UiKit.label("UNIVERSO", 150, Palette.YELLOW, 26)
	top.add_theme_color_override(&"font_outline_color", Color(0.02, 0.04, 0.35))
	top.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.45))
	top.add_theme_constant_override(&"shadow_offset_y", 10)
	_logo_box.add_child(top)
	var kart := UiKit.label("KART", 170, Palette.MAGENTA, 28)
	kart.add_theme_color_override(&"font_outline_color", Palette.WHITE)
	kart.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.45))
	kart.add_theme_constant_override(&"shadow_offset_y", 10)
	_logo_box.add_child(kart)
	_logo_box.resized.connect(func() -> void: _logo_box.pivot_offset = _logo_box.size * 0.5)

	_press = UiKit.label("Press enter for start", 54, Palette.WHITE, 10)
	UiKit.anchor(_press, Control.PRESET_CENTER_BOTTOM, Rect2(-600, -250, 1200, 80))
	layer.add_child(_press)
	var foot := UiKit.label("Raccons Games - UNIFEOB", 24, Color(1, 1, 1, 0.8), 5)
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
