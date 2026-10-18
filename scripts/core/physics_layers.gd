class_name PhysicsLayers
extends RefCounted
## Bits das camadas de física (nomeadas em project.godot > layer_names/3d_physics).

const WORLD_ROAD := 1 << 0      # superfície dirigível (asfalto, zebras, acostamento)
const WORLD_WALL := 1 << 1      # muretas/barreiras
const WORLD_TERRAIN := 1 << 2   # terreno fora da pista
const KART := 1 << 3
const ITEM_PICKUP := 1 << 4     # caixas de item
const PROJECTILE := 1 << 5      # foguete, casca
const TRIGGER := 1 << 6         # checkpoints, faixas de turbo, zonas de respawn
const SCENERY := 1 << 7         # colisões simples do cenário

const WORLD_ALL := WORLD_ROAD | WORLD_WALL | WORLD_TERRAIN | SCENERY
