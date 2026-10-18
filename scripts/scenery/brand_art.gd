class_name BrandArt
extends Node
## Gera as artes de marca UNIFEOB / UNIVERSO KART (banners, pórtico, bandeiras) renderizando
## composições 2D em SubViewports uma única vez e convertendo em ImageTexture com mipmaps.
## Os materiais são criados imediatamente (cor de fundo) e recebem a textura quando prontas.

signal baked

enum Design {
	LOGO_ON_BLUE,
	LOGO_ON_WHITE,
	TITLE_ON_MAGENTA,
	LOGO_ON_YELLOW,
	TITLE_ON_DARK,
	GATE,
	SQUARE_LOGO,
	FLAG_BLUE,
	FLAG_MAGENTA,
	FLAG_YELLOW,
}

const LOGO_TEX := preload("res://assets/branding/unifeob_logo.svg")
const TITLE_FONT := preload("res://assets/fonts/title_font.tres")
const TINT_SHADER := preload("res://assets/shaders/logo_tint.gdshader")
const CUTOUT_SHADER := preload("res://assets/shaders/logo_cutout.gdshader")
const CUTOUT_SINGLE_SHADER := preload("res://assets/shaders/logo_cutout_single.gdshader")
const TITLE := "UNIVERSO KART"
## Emissão das artes de marca. Testado 0.05–0.18: qualquer emissão dessatura as cores oficiais
## ao sol (medido: azul #0018FE virou #4046FF com 0.05), então fica desligada.
const BRAND_EMISSION := 0.0

## Designs usados nas placas ao redor da pista (rodízio).
const BANNER_ROTATION: Array[Design] = [
	Design.LOGO_ON_BLUE, Design.TITLE_ON_MAGENTA, Design.LOGO_ON_WHITE,
	Design.LOGO_ON_YELLOW, Design.TITLE_ON_DARK,
]

var textures: Dictionary = {}    # Design -> Texture2D
var materials: Dictionary = {}   # Design -> StandardMaterial3D
var is_baked: bool = false


static func design_size(d: Design) -> Vector2i:
	match d:
		Design.GATE:
			return Vector2i(2640, 200)
		Design.SQUARE_LOGO:
			return Vector2i(512, 512)
		Design.FLAG_BLUE, Design.FLAG_MAGENTA, Design.FLAG_YELLOW:
			return Vector2i(256, 1024)
	return Vector2i(1024, 256)


static func design_bg(d: Design) -> Color:
	match d:
		Design.LOGO_ON_BLUE, Design.GATE, Design.SQUARE_LOGO, Design.FLAG_BLUE:
			return Palette.BLUE
		Design.LOGO_ON_WHITE:
			return Palette.LAVENDER_LIGHT
		Design.TITLE_ON_MAGENTA, Design.FLAG_MAGENTA:
			return Palette.MAGENTA
		Design.LOGO_ON_YELLOW, Design.FLAG_YELLOW:
			return Palette.YELLOW
		Design.TITLE_ON_DARK:
			return Palette.GRAPHITE
	return Palette.WHITE


func _init() -> void:
	name = "BrandArt"
	for d: int in Design.values():
		var m := StandardMaterial3D.new()
		m.albedo_color = design_bg(d as Design)
		m.roughness = 0.8
		m.metallic_specular = 0.12
		# Leve emissão: mantém as cores oficiais legíveis mesmo com luz lateral/sombra.
		m.emission_enabled = BRAND_EMISSION > 0.0
		m.emission = design_bg(d as Design)
		m.emission_energy_multiplier = BRAND_EMISSION
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		materials[d] = m


func get_material(d: Design) -> StandardMaterial3D:
	return materials[d]


## Material do logo recortado (alpha scissor), para letreiros "vazados" em qualquer cor.
func make_logo_cutout_material(color: Color, double_sided: bool = true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CUTOUT_SHADER if double_sided else CUTOUT_SINGLE_SHADER
	m.set_shader_parameter(&"logo", LOGO_TEX)
	m.set_shader_parameter(&"tint", color)
	return m


## Renderiza todas as artes (assíncrono). Em modo headless apenas sinaliza "baked".
func bake() -> void:
	if DisplayServer.get_name() == "headless":
		is_baked = true
		baked.emit()
		return
	var pending: Array[Dictionary] = []
	for d: int in Design.values():
		var vp := SubViewport.new()
		vp.size = design_size(d as Design)
		vp.transparent_bg = false
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		vp.add_child(_compose(d as Design, vp.size))
		add_child(vp)
		pending.append({"design": d, "vp": vp})
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for item in pending:
		var vp: SubViewport = item["vp"]
		var img := vp.get_texture().get_image()
		if img != null and not img.is_empty():
			img.convert(Image.FORMAT_RGBA8)
			img.generate_mipmaps()
			var tex := ImageTexture.create_from_image(img)
			var d: int = item["design"]
			textures[d] = tex
			var m: StandardMaterial3D = materials[d]
			m.albedo_color = Color.WHITE
			m.albedo_texture = tex
			m.emission = Color.WHITE
			m.emission_texture = tex
		vp.queue_free()
	is_baked = true
	baked.emit()


# ------------------------------------------------------------------ composições 2D

func _compose(d: Design, size: Vector2i) -> Control:
	var root := Control.new()
	root.size = Vector2(size)
	var bg := ColorRect.new()
	bg.color = design_bg(d)
	bg.size = Vector2(size)
	root.add_child(bg)
	var w := float(size.x)
	var h := float(size.y)
	match d:
		Design.LOGO_ON_BLUE:
			_stripe(root, Rect2(0, h - 22, w, 22), Palette.YELLOW)
			_stripe(root, Rect2(0, h - 34, w, 8), Palette.MAGENTA)
			_logo(root, Rect2(w * 0.2, h * 0.16, w * 0.6, h * 0.58), Palette.WHITE)
		Design.LOGO_ON_WHITE:
			_stripe(root, Rect2(0, 0, w, 16), Palette.BLUE)
			_stripe(root, Rect2(0, h - 16, w, 16), Palette.BLUE)
			_logo(root, Rect2(w * 0.2, h * 0.2, w * 0.6, h * 0.58), Color.WHITE, true)
		Design.TITLE_ON_MAGENTA:
			_title(root, Rect2(0, 0, w, h), Palette.WHITE, Palette.BLUE, 118)
		Design.LOGO_ON_YELLOW:
			_stripe(root, Rect2(0, 0, 26, h), Palette.BLUE)
			_stripe(root, Rect2(w - 26, 0, 26, h), Palette.BLUE)
			_logo(root, Rect2(w * 0.2, h * 0.2, w * 0.6, h * 0.58), Palette.GRAPHITE)
		Design.TITLE_ON_DARK:
			_stripe(root, Rect2(0, h - 14, w * 0.5, 14), Palette.MAGENTA)
			_stripe(root, Rect2(w * 0.5, h - 14, w * 0.5, 14), Palette.YELLOW)
			_title(root, Rect2(0, 0, w, h - 10), Palette.YELLOW, Palette.MAGENTA, 112)
		Design.GATE:
			var grad := TextureRect.new()
			var gt := GradientTexture2D.new()
			var g := Gradient.new()
			g.set_color(0, Palette.BLUE.darkened(0.25))
			g.set_color(1, Palette.BLUE.lightened(0.1))
			gt.gradient = g
			gt.fill_from = Vector2(0, 1)
			gt.fill_to = Vector2(0, 0)
			grad.texture = gt
			grad.size = Vector2(size)
			grad.stretch_mode = TextureRect.STRETCH_SCALE
			grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			root.add_child(grad)
			_checker(root, Rect2(0, 0, w, 20), 20)
			_checker(root, Rect2(0, h - 20, w, 20), 20)
			_logo(root, Rect2(50, h * 0.26, w * 0.17, h * 0.48), Palette.WHITE)
			_logo(root, Rect2(w - 50 - w * 0.17, h * 0.26, w * 0.17, h * 0.48), Palette.WHITE)
			_title(root, Rect2(w * 0.2, 14, w * 0.6, h - 28), Palette.WHITE, Palette.MAGENTA, 122)
		Design.SQUARE_LOGO:
			_stripe(root, Rect2(0, h - 60, w, 60), Palette.MAGENTA)
			_logo(root, Rect2(w * 0.1, h * 0.3, w * 0.8, h * 0.3), Palette.WHITE)
		Design.FLAG_BLUE, Design.FLAG_MAGENTA, Design.FLAG_YELLOW:
			var fg := Palette.WHITE if d != Design.FLAG_YELLOW else Palette.BLUE
			_stripe(root, Rect2(0, 0, w, 40), fg)
			var holder := Control.new()
			holder.size = Vector2(h, w)
			holder.position = Vector2(w * 0.5 - h * 0.5, h * 0.5 - w * 0.5)
			holder.pivot_offset = holder.size * 0.5
			holder.rotation = -PI * 0.5
			root.add_child(holder)
			_logo(holder, Rect2(h * 0.14, w * 0.25, h * 0.72, w * 0.5), fg)
	return root


func _stripe(parent: Control, r: Rect2, c: Color) -> void:
	var cr := ColorRect.new()
	cr.color = c
	cr.position = r.position
	cr.size = r.size
	parent.add_child(cr)


func _checker(parent: Control, r: Rect2, cell: float) -> void:
	var n := ceili(r.size.x / cell)
	var rows := maxi(1, roundi(r.size.y / (cell * 0.5)))
	var ch := r.size.y / float(rows)
	for row in rows:
		for i in n:
			var c := Palette.WHITE if (i + row) % 2 == 0 else Palette.GRAPHITE
			_stripe(parent, Rect2(r.position.x + i * cell, r.position.y + row * ch, cell, ch), c)


func _logo(parent: Control, r: Rect2, c: Color, keep_original: bool = false) -> void:
	var rect_node := TextureRect.new()
	rect_node.texture = LOGO_TEX
	rect_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect_node.position = r.position
	rect_node.size = r.size
	var sm := ShaderMaterial.new()
	sm.shader = TINT_SHADER
	sm.set_shader_parameter(&"tint", c)
	sm.set_shader_parameter(&"keep_original", keep_original)
	rect_node.material = sm
	rect_node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parent.add_child(rect_node)


func _title(parent: Control, r: Rect2, c: Color, outline: Color, font_size: int) -> void:
	var lbl := Label.new()
	lbl.text = TITLE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.position = r.position
	lbl.size = r.size
	var ls := LabelSettings.new()
	ls.font = TITLE_FONT
	ls.font_size = font_size
	ls.font_color = c
	ls.outline_size = maxi(8, int(font_size * 0.1))
	ls.outline_color = outline
	ls.shadow_size = 0
	ls.shadow_color = Color(0, 0, 0, 0.35)
	ls.shadow_offset = Vector2(6, 6)
	lbl.label_settings = ls
	lbl.clip_text = false
	parent.add_child(lbl)
