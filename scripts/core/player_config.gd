class_name PlayerConfig
extends Resource
## Configuração de um corredor (humano ou IA).
## O traje do piloto vem do personagem (Characters.suit_color), não da cor do kart.

@export var display_name: String = "Jogador"
@export var is_human: bool = true
@export var player_index: int = 0          ## 0 = P1, 1 = P2 (apenas humanos)
@export var kart_color: Color = Palette.MAGENTA
@export var color_index: int = 0           ## índice em Palette.SELECT_COLORS
@export var character: int = 0             ## Characters (0..1 ETs, 2.. pilotos)
var suit_color: Color:                     ## cor do traje (do personagem)
	get:
		return Characters.suit_color(character)


## Cor do kart.
func set_color(c: Color) -> void:
	kart_color = c


func duplicate_config() -> PlayerConfig:
	return duplicate() as PlayerConfig
