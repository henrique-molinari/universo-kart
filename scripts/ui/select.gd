class_name SelectScreen
extends Control
## Seleção 2P lado a lado: personagem (ET Visitante ou Turista) + cor do kart. Cada jogador usa o PRÓPRIO
## controle/teclado (PlayerInput, mesma atribuição de device da corrida): ▲ ▼ alterna entre as linhas
## PERSONAGEM e COR, ◀ ▶ troca o valor, A/Enter confirma ("PRONTO!", o ET comemora na prévia),
## B cancela o PRONTO (ou volta ao título se não estava pronto). Cores e personagens repetidos são permitidos.
## Prévia 3D do kart + piloto (traje na cor do personagem) girando num pedestal.
## Quando os dois confirmam, personagem e cor vão para GameState.players e a corrida começa.

const RACE_SCENE := "res://scenes/race.tscn"
const TITLE_SCENE := "res://scenes/title.tscn"
const START_DELAY := 0.9
const BG_SHADER := preload("res://assets/shaders/soft_pattern.gdshader")

var sel: Array[int] = [0, 0]
var char_sel: Array[int] = [0, 1]
var row: Array[int] = [0, 0]      ## 0 = personagem, 1 = cor
var _prev_nav_y: Array[int] = [0, 0]
var _char_labels: Array[Label] = []
var ready_flags: Array[bool] = [false, false]
var _prev_nav: Array[int] = [0, 0]
var _prev_ok: Array[bool] = [true, true]
var _prev_back: Array[bool] = [true, true]
var _turntables: Array[Node3D] = []
var _models: Array[KartModel] = []
var _name_labels: Array[Label] = []
var _status_labels: Array[Label] = []
var _device_labels: Array[Label] = []
var _swatches: Array = [[], []]
var _panels: Array[PanelContainer] = []
var _start_timer := -1.0
var _leaving := false
var _t := 0.0


func _ready() -> void:
	SceneRouter.scene_leaving.connect(func(_p: String) -> void:
		for m in _models:
			if is_instance_valid(m):
				m.release())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	PlayerInput.refresh()
	Input.joy_connection_changed.connect(_on_joy_changed)
	AudioManager.play_music(&"title")
	for i in 2:
		sel[i] = clampi(GameState.get_player(i).color_index, 0, Palette.SELECT_COLORS.size() - 1)
		char_sel[i] = clampi(GameState.get_player(i).character, 0, Characters.NAMES.size() - 1)
	# Fundo sóbrio e dessaturado (os karts coloridos se destacam), com padrão sutil.
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bgm := ShaderMaterial.new()
	bgm.shader = BG_SHADER
	bg.material = bgm
	add_child(bg)
	var header := UiKit.label("ESCOLHA SEU PILOTO E A COR DO KART", 56, Palette.UI_TEXT, 10)
	UiKit.anchor(header, Control.PRESET_CENTER_TOP, Rect2(-800, 24, 1600, 90))
	add_child(header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 40)
	UiKit.anchor(row, Control.PRESET_FULL_RECT, Rect2(60, 130, -120, -250))
	add_child(row)
	for i in 2:
		row.add_child(_build_panel(i))
	var foot := UiKit.label("▲ ▼ personagem / cor     ◀ ▶ trocar     A / Enter: PRONTO!     B: voltar", 28, Palette.UI_TEXT.darkened(0.1), 6)
	UiKit.anchor(foot, Control.PRESET_CENTER_BOTTOM, Rect2(-900, -104, 1800, 44))
	add_child(foot)
	var note := UiKit.label("Personagens e cores podem se repetir. A corrida começa quando os dois estiverem PRONTOS.", 22, Palette.UI_MUTED, 4)
	UiKit.anchor(note, Control.PRESET_CENTER_BOTTOM, Rect2(-900, -58, 1800, 36))
	add_child(note)
	for i in 2:
		_refresh(i)


func _on_joy_changed(_device: int, _connected: bool) -> void:
	PlayerInput.refresh()


func _build_panel(i: int) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := UiKit.panel_style(Palette.UI_ACCENT, 20, 22)
	sb.bg_color = Color(1, 1, 1, 0.035)
	sb.shadow_size = 0
	panel.add_theme_stylebox_override(&"panel", sb)
	_panels.append(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	panel.add_child(v)
	var title := UiKit.label("JOGADOR %d" % (i + 1), 48, Palette.UI_TEXT, 8)
	v.add_child(title)
	var dev := UiKit.label("", 22, Palette.UI_MUTED, 4)
	v.add_child(dev)
	_device_labels.append(dev)

	# Prévia 3D (mundo próprio, fundo transparente).
	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cont.custom_minimum_size = Vector2(0, 300)
	v.add_child(cont)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	cont.add_child(vp)
	_build_preview_world(vp)

	var char_l := UiKit.label("", 40, Palette.UI_TEXT, 8)
	v.add_child(char_l)
	_char_labels.append(char_l)
	var name_l := UiKit.label("", 30, Palette.UI_MUTED, 6)
	v.add_child(name_l)
	_name_labels.append(name_l)
	var sw_row := HBoxContainer.new()
	sw_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sw_row.add_theme_constant_override(&"separation", 12)
	v.add_child(sw_row)
	for c in Palette.SELECT_COLORS.size():
		var sw := Panel.new()
		sw.custom_minimum_size = Vector2(70, 70)
		var ssb := StyleBoxFlat.new()
		ssb.bg_color = Palette.SELECT_COLORS[c]
		ssb.set_corner_radius_all(35)
		ssb.set_border_width_all(4)
		ssb.border_color = Color(0, 0, 0, 0.35)
		sw.add_theme_stylebox_override(&"panel", ssb)
		sw.pivot_offset = Vector2(35, 35)
		sw_row.add_child(sw)
		_swatches[i].append(sw)
	var status := UiKit.label("", 42, Palette.UI_MUTED, 8)
	status.custom_minimum_size = Vector2(0, 70)
	v.add_child(status)
	_status_labels.append(status)
	return panel


func _build_preview_world(vp: SubViewport) -> void:
	var root := Node3D.new()
	vp.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.42, 0.46, 0.55)
	psm.sky_horizon_color = Color(0.82, 0.83, 0.86)
	psm.ground_bottom_color = Color(0.1, 0.105, 0.12)
	psm.ground_horizon_color = Color(0.5, 0.52, 0.56)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(35.0), 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(-140.0), 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.8, 0.85, 1.0)
	root.add_child(fill)
	# Luz de contorno (rim light) por trás, destacando a silhueta do personagem.
	var rim := DirectionalLight3D.new()
	rim.basis = Basis.looking_at(Vector3(0.25, -0.55, 1.0).normalized())
	rim.light_energy = 1.8
	rim.light_color = Color(0.9, 0.94, 1.0)
	root.add_child(rim)
	# Pedestal.
	var ped := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.9
	cyl.bottom_radius = 2.0
	cyl.height = 0.16
	cyl.radial_segments = 48
	ped.mesh = cyl
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.16, 0.17, 0.2)
	pm.metallic = 0.4
	pm.roughness = 0.25
	ped.material_override = pm
	ped.position = Vector3(0, -0.08, 0)
	root.add_child(ped)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 1.93
	tor.outer_radius = 2.03
	ring.mesh = tor
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Palette.UI_ACCENT
	rm.emission_enabled = true
	rm.emission = Palette.UI_ACCENT
	rm.emission_energy_multiplier = 0.55
	ring.material_override = rm
	root.add_child(ring)
	var tt := Node3D.new()
	root.add_child(tt)
	_turntables.append(tt)
	_models.append(null)
	var cam := Camera3D.new()
	cam.fov = 36.0
	var eye := Vector3(0, 1.9, 4.5)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.78, 0) - eye), eye)
	root.add_child(cam)
	cam.current = true


## Reconstrói o kart da prévia na cor escolhida (piloto na mesma cor).
func _refresh(i: int) -> void:
	var c := Palette.SELECT_COLORS[sel[i]]
	var cfg := PlayerConfig.new()
	cfg.player_index = i
	cfg.set_color(c)
	cfg.character = char_sel[i]
	if _models[i] != null:
		_models[i].release()
	var m := KartModel.acquire(cfg)
	m.position = Vector3(0, 0, 0.1)
	_turntables[i].add_child(m)
	_models[i] = m
	var on_char := row[i] == 0 and not ready_flags[i]
	var on_col := row[i] == 1 and not ready_flags[i]
	_char_labels[i].text = ("◀  %s  ▶" if on_char else "%s") % Characters.NAMES[char_sel[i]].to_upper()
	_char_labels[i].add_theme_color_override(&"font_color", Palette.UI_ACCENT if on_char else Palette.UI_TEXT)
	_name_labels[i].text = ("◀  KART %s  ▶" if on_col else "KART %s") % Palette.SELECT_COLOR_NAMES[sel[i]].to_upper()
	_name_labels[i].add_theme_color_override(&"font_color", Palette.UI_ACCENT if on_col else Palette.UI_MUTED)
	if ready_flags[i]:
		m.set_pose(AlienDriver.Pose.VICTORY)
	for k in _swatches[i].size():
		var sw: Panel = _swatches[i][k]
		var sb := sw.get_theme_stylebox(&"panel") as StyleBoxFlat
		var on: bool = k == sel[i]
		sb.border_color = Palette.UI_TEXT if on else Color(0, 0, 0, 0.35)
		sb.set_border_width_all(7 if on else 3)
		sw.scale = Vector2.ONE * (1.18 if on else 1.0)
	_update_status(i)


func _update_status(i: int) -> void:
	var sb := _panels[i].get_theme_stylebox(&"panel") as StyleBoxFlat
	if ready_flags[i]:
		_status_labels[i].text = "PRONTO!"
		_status_labels[i].add_theme_color_override(&"font_color", Palette.UI_OK)
		sb.border_color = Palette.UI_OK
	else:
		_status_labels[i].text = "▲ ▼  ◀ ▶"
		_status_labels[i].add_theme_color_override(&"font_color", Palette.UI_MUTED)
		sb.border_color = Palette.UI_LINE


func _confirm_pressed(i: int) -> bool:
	return PlayerInput.confirm(i) or (i == 0 and Input.is_physical_key_pressed(KEY_ENTER))


func _process(delta: float) -> void:
	_t += delta
	for i in 2:
		if i < _turntables.size():
			_turntables[i].rotation.y = _t * (0.9 if not ready_flags[i] else 2.2) + i * 0.35
		if i < _models.size() and _models[i] != null:
			_models[i].animate(0.0, sin(_t * 1.3 + i) * 0.35, delta)
		var dev := PlayerInput.device_of(i)
		_device_labels[i].text = ("Controle %d" % dev) if dev >= 0 else ("Teclado (A/D, Espaço/E, Q)" if i == 0 else "Teclado (setas, Enter num., Backspace)")
	if _leaving:
		return
	for i in 2:
		var nav := PlayerInput.nav_x(i)
		var nav_y := PlayerInput.nav_y(i)
		var ok := _confirm_pressed(i)
		var back := PlayerInput.cancel(i)
		if not ready_flags[i] and nav_y != 0 and nav_y != _prev_nav_y[i]:
			row[i] = clampi(row[i] + nav_y, 0, 1)
			AudioManager.sfx(&"move")
			_refresh(i)
		if not ready_flags[i] and nav != 0 and nav != _prev_nav[i]:
			if row[i] == 0:
				char_sel[i] = wrapi(char_sel[i] + nav, 0, Characters.NAMES.size())
			else:
				sel[i] = wrapi(sel[i] + nav, 0, Palette.SELECT_COLORS.size())
			AudioManager.sfx(&"move")
			_refresh(i)
		if ok and not _prev_ok[i] and not ready_flags[i]:
			ready_flags[i] = true
			AudioManager.sfx(&"confirm")
			_refresh(i)
		if back and not _prev_back[i]:
			if ready_flags[i]:
				ready_flags[i] = false
				_start_timer = -1.0
				AudioManager.sfx(&"back")
				_refresh(i)
			else:
				_leaving = true
				AudioManager.sfx(&"back")
				SceneRouter.goto(TITLE_SCENE)
				return
		_prev_nav[i] = nav
		_prev_nav_y[i] = nav_y
		_prev_ok[i] = ok
		_prev_back[i] = back
	if ready_flags[0] and ready_flags[1]:
		if _start_timer < 0.0:
			_start_timer = START_DELAY
		_start_timer -= delta
		if _start_timer <= 0.0:
			_start_race()
	else:
		_start_timer = -1.0


func _start_race() -> void:
	_leaving = true
	for i in 2:
		var cfg := GameState.get_player(i)
		cfg.color_index = sel[i]
		cfg.set_color(Palette.SELECT_COLORS[sel[i]])
		cfg.character = char_sel[i]
	print("[Select] P1 %s / %s, P2 %s / %s" % [Characters.NAMES[char_sel[0]], Palette.SELECT_COLOR_NAMES[sel[0]], Characters.NAMES[char_sel[1]], Palette.SELECT_COLOR_NAMES[sel[1]]])
	AudioManager.sfx(&"go")
	SceneRouter.goto(RACE_SCENE)
