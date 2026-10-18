# Ferramenta de captura de telas (UNIVERSO KART)

Gera screenshots **reais** (renderizadas pela GPU) de pontos de vista pré-definidos e encerra sozinha.
Usada pelo QA visual a cada etapa.

> **Não use `--headless`**: em modo headless nada é renderizado (a ferramenta avisa e sai com código 2).
> Use o executável **console** para ver os logs no terminal.

## Uso

```bash
Godot_v4.7.2-stable_win64_console.exe --path <projeto> res://tools/capture/capture.tscn -- --shot=all --out=<pasta>
```

Exemplo (Windows, Git Bash):

```bash
"C:/Users/henri/Downloads/Godot/Godot_v4.7.2-stable_win64_console.exe" \
  --path "C:/Users/henri/OneDrive/Desktop/UNIVERSO-KART/universo-kart" \
  res://tools/capture/capture.tscn -- --shot=overview,start_line,lap25,rev40 --out="C:/temp/shots"
```

Cada vista gera `<pasta>/<nome>.png` (1920x1080 por padrão, independente do tamanho da janela).
O código de saída é `0` em caso de sucesso e `1` se alguma vista falhar/for desconhecida.

## Opções (sempre depois de `--`)

| Opção | Padrão | Descrição |
|---|---|---|
| `--shot=a,b,c` ou `--shot=all` | `overview` | Vistas a capturar (lista separada por vírgula). `all` = todas as vistas nomeadas. |
| `--out=<pasta>` | `user://captures` | Pasta de saída (criada se não existir). |
| `--scene=<res://...>` | pista do campus | Cena a carregar (ver "Outras cenas"). |
| `--size=LxA` | `1920x1080` | Resolução da imagem. |
| `--frames=N` | `40` | Quadros de espera por vista (sombras, SSAO, nuvens assentarem). |
| `--warmup=N` | `120` | Quadros extras antes da 1ª vista (texturas de ruído, artes de marca, radiância do céu). |
| `--quality=low\|medium\|high\|ultra` | `high` | Preset de qualidade gráfica (`RenderQuality`). |
| `--bench` | — | Mede o tempo médio de quadro em cada vista (90 quadros, vsync desligado). |
| `--list` | — | Lista as vistas nomeadas e sai (funciona também com `--headless`). |

## Vistas nomeadas

**Visão geral / borda do mundo**

| Nome | O que mostra |
|---|---|
| `overview` | Vista aérea oblíqua do circuito inteiro, campus, lago e colinas |
| `top` | Planta (de cima) do sítio inteiro |
| `world_edge`, `world_edge2` | Muito alto e longe: horizonte, anel de montanhas, borda do mundo |

**Largada, boxes e arquibancada**

| Nome | O que mostra |
|---|---|
| `start_line` | Altura do kart, atrás do grid, olhando o pórtico |
| `start_gate` | Pórtico de largada/chegada de perto (frente, semáforo) |
| `gate_back` | Pórtico visto por trás (letreiro legível dos dois lados) |
| `grid` | Vista elevada do grid, boxes e arquibancada |
| `pits_close` | Fachada dos boxes (garagens, marquise, brises) |
| `grandstand` | Arquibancada e público |
| `stand_back` | Arquibancada vista por trás (praça, portões, canteiros) |
| `banners` | Placas ao longo da reta principal |

**Setores da volta**

| Nome | O que mostra |
|---|---|
| `track_curve` | Entrada da curva 1 (inclinada) à altura do kart |
| `banked` | Curva 1 inclinada vista de fora (caixa de brita) |
| `s_curve` | Curva em S com muro de pneus e canteiros de flores |
| `tires` | Muro de pneus e flores de perto |
| `climb` | Subida do morro com pórtico de banners |
| `crest` | Crista do morro (ponto mais alto, ~17,7 m) |
| `bridge` | Ponte em arcos sobre o lago vista da margem |
| `bridge_drive` | Na ponte, descendo em direção ao lago |
| `under_bridge` | Sob a ponte, rente à água (pilares, sapatas, arcos) |
| `hill` | Descida após a ponte |
| `lakeside` | Trecho à beira do lago (cerca baixa) |
| `chicane` | Chicane com pneus |
| `tunnel` | Entrada da passagem sob o prédio |
| `tunnel_inside` | Dentro da passagem sob o prédio |
| `tunnel_exit` | Prédio do túnel visto após a saída (verso) |
| `final_curve` | Última curva inclinada com pórtico de banners |

**Cenário e marca**

| Nome | O que mostra |
|---|---|
| `campus` | Prédios do campus vistos da pista |
| `planetarium` | Planetário "Universo" no miolo da curva 1 |
| `hill_sign` | Letreiro UNIFEOB na encosta visto da reta principal |
| `hill_sign_back` | Letreiro UNIFEOB visto por trás |
| `horizon` | Olhando para fora do circuito (lago, colinas) |
| `lake` | Lago, praia e ponte vistos da margem |
| `barrier_close` | Mureta de perto (lona, costuras, logo) |
| `sky` | Céu na direção do sol (halo + nuvens) |

## Vistas paramétricas (qualquer ponto da volta)

`NN` = porcentagem da volta (0–99), a partir da linha de largada. Não entram em `--shot=all`.

| Padrão | O que mostra |
|---|---|
| `lapNN` | Altura do kart, olhando para a frente (sentido da corrida) |
| `revNN` | Altura do kart, olhando para trás (verso de placas/pórticos) |
| `outNN` | Olhando para fora do circuito (lado direito) |
| `inNN` | Olhando para dentro do circuito (lado esquerdo) |

Exemplo de volta completa: `--shot=lap05,lap15,lap25,lap35,lap45,lap55,lap65,lap75,lap85,lap95`.

As vistas são calculadas a partir da API do `TrackPath` (offset/lateral), então continuam válidas se o
traçado mudar. Estão definidas em `capture_views.gd`.

## Outras cenas

- **Cena de verificação de cores:** `--scene=res://tools/validate/color_check.tscn --shot=colors`.
  Coloca amostras das cores oficiais voltadas para o sol e imprime `[swatch] nome x y #hex` (posição em
  pixels de cada amostra) para medir o erro de cor na imagem final.
- **Cenas futuras (corrida, split-screen, menus):** se a cena raiz implementar
  `get_capture_view(nome: String) -> Dictionary` (`{pos, target, fov}`), essas vistas têm prioridade.
  Cenas de corrida poderão usar `--frames` maiores para simular N segundos antes de capturar.

## Ferramentas relacionadas

- **Validação automática da pista** (colisões contínuas, API do TrackPath, pontos estratégicos, desnível e inclinação):
  ```bash
  Godot_console.exe --headless --path <projeto> res://tools/validate/validate_track.tscn
  ```
  Imprime `[validate] N verificações, 0 falhas` e sai com código 0 quando tudo está correto.
- **Warnings como erros:** copie `tools/strict_warnings.cfg` para a raiz do projeto como `override.cfg`,
  rode o jogo/ferramentas e **apague o `override.cfg` depois** (está no `.gitignore`).
- **Input Map:** `tools/setup_input_map.gd` regenera as ações dos 2 jogadores em `project.godot`
  (`--headless -s res://tools/setup_input_map.gd`).
