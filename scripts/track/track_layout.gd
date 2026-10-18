class_name TrackLayout
extends Resource
## Descrição de dados de um circuito: pontos de controle + dimensões + zonas por setor + pontos estratégicos.
## A MESMA curva alimenta malhas, colisão, IA, checkpoints, turbos e caixas de item.
## Zonas usam t = fração da volta (0..1) e são suavizadas nas transições (zone_blend).

enum WallStyle { BARRIER, TIRES, FENCE, PARAPET }
enum Surface { GRASS, GRAVEL, FLOWERS }

## Pontos de controle (x, altura, z) em ordem de corrida. O circuito é fechado automaticamente.
@export var control_points: PackedVector3Array = PackedVector3Array()
## Fator dos "handles" Bézier (0.33 ~ Catmull-Rom). Maior = curvas mais cheias.
@export_range(0.1, 0.6) var handle_scale: float = 0.38

@export_group("Dimensões (m)")
@export var road_width: float = 18.0
@export var curb_width: float = 1.4
## Faixa padrão fora do asfalto (grama/acostamento) antes da mureta, de cada lado.
@export var runoff_width: float = 5.0
@export var wall_thickness: float = 0.9
@export var wall_height: float = 1.1
## Curvatura (1/raio) a partir da qual há zebras no lado interno.
@export var curb_inner_curvature: float = 1.0 / 130.0
## Curvatura a partir da qual há zebras também no lado externo.
@export var curb_outer_curvature: float = 1.0 / 75.0

@export_group("Zonas por setor")
## Comprimento (m) das transições entre zonas.
@export var zone_blend: float = 20.0
## Curvas inclinadas: (t_início, t_fim, inclinação máxima em graus).
@export var bank_zones: PackedVector3Array = PackedVector3Array()
## Recuo das muretas: (t_início, t_fim, acostamento esquerdo m, acostamento direito m). Valor < 0 = padrão.
@export var runoff_zones: PackedVector4Array = PackedVector4Array()
## Tipo de mureta: (t_início, t_fim, lado -1/0/+1 (0 = ambos), WallStyle).
@export var wall_style_zones: PackedVector4Array = PackedVector4Array()
## Tipo de acostamento: (t_início, t_fim, lado -1/0/+1, Surface).
@export var surface_zones: PackedVector4Array = PackedVector4Array()
## Setor do túnel (passagem sob prédio): (t_centro, comprimento m).
@export var tunnel: Vector2 = Vector2(-1.0, 0.0)
## Pórticos de banner sobre a pista (t de cada um).
@export var overhead_arches: PackedFloat32Array = PackedFloat32Array()

@export_group("Pontos estratégicos (t = fração da volta 0..1)")
## Faixas de turbo: x = t, y = deslocamento lateral (m), z = comprimento (m).
@export var boost_pads: PackedVector3Array = PackedVector3Array()
## Fileiras de caixas de item (t de cada fileira).
@export var item_rows: PackedFloat32Array = PackedFloat32Array()
@export var item_boxes_per_row: int = 4
@export var checkpoint_count: int = 16

@export_group("Grid de largada")
@export var grid_first_row_distance: float = 9.0
@export var grid_row_spacing: float = 6.5
@export var grid_column_lateral: float = 4.5
@export var grid_column_stagger: float = 3.0
