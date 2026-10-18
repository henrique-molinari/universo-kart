class_name Palette
extends RefCounted
## Paleta oficial UNIFEOB + cores derivadas usadas em todo o jogo.

const BLUE := Color(0.0, 0.0941, 0.9961)          # #0018FE (primária)
const MAGENTA := Color(1.0, 0.0941, 0.3882)       # #FF1863 (secundária)
const YELLOW := Color(0.9569, 0.9059, 0.1529)     # #F4E727 (destaque)
const GRAPHITE := Color(0.1059, 0.1059, 0.1059)   # #1B1B1B (texto/logo)
const LAVENDER := Color(0.8392, 0.8549, 1.0)      # #D6DAFF
const LAVENDER_LIGHT := Color(0.9608, 0.9647, 1.0) # #F5F6FF
const WHITE := Color(1.0, 1.0, 1.0)

## Interface (menus/telas): neutros grafite com UM acento quente (o amarelo UNIFEOB, dessaturado)
## para seleção/destaque e o azul da marca só em detalhes finos. Cores saturadas ficam para os karts.
const UI_INK := Color(0.045, 0.05, 0.062)           # fundo profundo
const UI_PANEL := Color(0.075, 0.082, 0.098, 0.93)  # painéis
const UI_LINE := Color(1.0, 1.0, 1.0, 0.13)         # bordas discretas
const UI_TEXT := Color(0.93, 0.94, 0.95)            # texto principal
const UI_MUTED := Color(0.58, 0.61, 0.67)           # texto secundário/dicas
const UI_ACCENT := Color(0.95, 0.83, 0.38)          # acento (amarelo UNIFEOB suavizado)
const UI_BRAND := Color(0.42, 0.5, 0.98)            # azul UNIFEOB clareado (detalhes)
const UI_OK := Color(0.56, 0.84, 0.63)              # "pronto"
const UI_OUTLINE := Color(0.02, 0.022, 0.03)        # contorno do texto

## Cores selecionáveis para o kart (a UNIFEOB primeiro).
const KART_COLORS: Array[Color] = [
	Color(0.0, 0.0941, 0.9961),
	Color(1.0, 0.0941, 0.3882),
	Color(0.9569, 0.9059, 0.1529),
	Color(0.1059, 0.1059, 0.1059),
	Color(0.96, 0.96, 0.98),
	Color(0.05, 0.75, 0.35),
	Color(1.0, 0.45, 0.05),
	Color(0.55, 0.2, 0.95),
	Color(0.0, 0.78, 0.92),
	Color(0.85, 0.08, 0.1),
]

const KART_COLOR_NAMES: Array[String] = [
	"Azul UNIFEOB", "Magenta", "Amarelo", "Grafite", "Branco",
	"Verde", "Laranja", "Roxo", "Ciano", "Vermelho",
]


## Paleta da tela de seleção de cor (8 cores vibrantes, UNIFEOB primeiro).
const SELECT_COLORS: Array[Color] = [
	Color(0.0, 0.0941, 0.9961),   # Azul UNIFEOB #0018FE
	Color(1.0, 0.0941, 0.3882),   # Magenta UNIFEOB #FF1863
	Color(0.9569, 0.9059, 0.1529),
	Color(0.05, 0.75, 0.35),
	Color(1.0, 0.45, 0.05),
	Color(0.55, 0.2, 0.95),
	Color(0.0, 0.78, 0.92),
	Color(0.85, 0.08, 0.1),
]
const SELECT_COLOR_NAMES: Array[String] = [
	"Azul UNIFEOB", "Magenta UNIFEOB", "Amarelo", "Verde", "Laranja", "Roxo", "Ciano", "Vermelho",
]


static func hex(c: Color) -> String:
	return "#" + c.to_html(false)
