class_name UiKit
extends RefCounted
## Utilitários das telas (splash, título, seleção): fundo em gradiente, rótulos e logo UNIFEOB nítido.

const FONT := preload("res://assets/fonts/title_font.tres")
const LOGO_PATH := "res://assets/branding/unifeob_logo.svg"
const TINT_SHADER := preload("res://assets/shaders/logo_tint.gdshader")


## Fundo em gradiente radial (azul UNIFEOB no centro -> azul-marinho nas bordas).
static func gradient_bg(center: Color = Color(0.0, 0.11, 0.85), edge: Color = Color(0.0, 0.02, 0.16)) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, center)
	g.set_color(1, edge)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.45)
	gt.fill_to = Vector2(1.15, 1.05)
	gt.width = 256
	gt.height = 256
	var rect := TextureRect.new()
	rect.texture = gt
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func label(text: String, size_px: int, c: Color = Palette.UI_TEXT, outline: int = -1) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override(&"font", FONT)
	l.add_theme_font_size_override(&"font_size", size_px)
	l.add_theme_color_override(&"font_color", c)
	l.add_theme_color_override(&"font_outline_color", Palette.UI_OUTLINE)
	l.add_theme_constant_override(&"outline_size", outline if outline >= 0 else maxi(int(size_px / 7.0), 3))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Painel padrão dos menus: grafite translúcido, borda fina neutra e faixa de acento no topo.
static func panel_style(accent: Color = Palette.UI_ACCENT, radius: int = 18, margin: int = 40) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.UI_PANEL
	sb.border_color = accent.darkened(0.15)
	sb.set_border_width_all(2)
	sb.border_width_top = 5
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 28
	sb.shadow_offset = Vector2(0, 10)
	return sb


## Logo UNIFEOB rasterizado do SVG em alta resolução, recolorido (padrão: branco).
static func logo(height_px: float, tint: Color = Palette.WHITE) -> TextureRect:
	var tex: Texture2D = null
	var svg := FileAccess.get_file_as_string(LOGO_PATH)
	if svg != "":
		var img := Image.new()
		if img.load_svg_from_string(svg, height_px / 32.0) == OK:
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		tex = load(LOGO_PATH) as Texture2D
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(height_px * 141.0 / 32.0, height_px)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = TINT_SHADER
	sm.set_shader_parameter(&"tint", tint)
	rect.material = sm
	return rect


## Ancora `c` com o preset e aplica offsets (retângulo relativo ao ponto de âncora).
static func anchor(c: Control, preset: Control.LayoutPreset, r: Rect2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.position.x + r.size.x
	c.offset_bottom = r.position.y + r.size.y
