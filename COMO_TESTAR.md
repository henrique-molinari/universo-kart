# UNIVERSO KART — Como testar (versão jogável 2P)

## Abrir e jogar
1. Abra o Godot 4.7.2 (`Godot_v4.7.2-stable_win64.exe`).
2. Clique em **Importar**, selecione o `project.godot` desta pasta e abra o projeto.
   A primeira importação pode levar alguns minutos.
3. Conecte os dois controles de Xbox **antes** de iniciar (dá para plugar com o jogo aberto, mas é mais simples antes).
4. Pressione **F5**, ou clique em ▶ no canto superior direito. O jogo segue este fluxo:
   - **Splash** "Raccons Games - UNIFEOB": fica na tela enquanto a pista e a música carregam (mínimo de 2,5 s).
   - **Título**: sobrevoo desfocado da pista. Pressione **Enter** ou **A** em qualquer controle.
   - **Seleção de cor**: cada jogador usa o próprio controle ou teclado. **◀ ▶** escolhe entre 8 cores, **A/Enter** confirma ("PRONTO!") e **B** cancela ou volta ao título.
     O piloto usa a mesma cor do kart, e os dois podem escolher a mesma cor. A corrida começa quando os dois estiverem prontos.
   - **Corrida** 2P em tela dividida: P1 na metade de cima, P2 na de baixo.
   - **Resultado**: **A** corre de novo e **B** volta à seleção de cor.

## Controles

| Ação | Controle Xbox | Teclado P1 | Teclado P2 |
|---|---|---|---|
| Direção | Analógico esquerdo | A / D | ← / → |
| Acelerar | RT ou A | W | ↑ |
| Frear / ré | LT | S | ↓ |
| Drift (segure na curva → mini-turbo) | B ou RB | Espaço ou Shift esquerdo | Ctrl direito ou Numpad 0 |
| Menus: escolher / confirmar / voltar | ◀ ▶ / A / B | A D / Espaço, E ou Enter / Q | ← → / Enter do numérico / Backspace |
| Usar item | X ou LB | E ou Q | Enter do numérico, Shift direito ou Numpad 1 |
| Resultado: correr de novo / voltar | A / B | Espaço ou E / Q | Enter do numérico / Backspace |

- O 1º controle conectado vira o P1 e o 2º vira o P2.
- Cada jogador lê **apenas o próprio controle**. O canto inferior esquerdo de cada metade mostra qual dispositivo está ligado àquele jogador.
- Sem controle, o jogador cai automaticamente no teclado.

## O que testar
- **Caixas "?"**: atropele uma para ganhar um item aleatório. Elas reaparecem em 3 s. Os itens são:
  - **Escudo**: bolha por 6 s que anula banana e foguete.
  - **Foguete**: voa **reto** na direção em que o kart apontava, colado ao chão e subindo rampas, por 3 s. Ele não persegue ninguém.
    Acerta qualquer kart no caminho, que fica parado por 2 s e perde a velocidade. Também explode ao bater numa mureta.
  - **Banana**: largada atrás do kart. Quem passar por cima rodopia e perde a velocidade.
  - **Turbo**: aceleração forte por 1,5 s.
- **Drift com mini-turbo**: numa curva com velocidade, segure o drift e vire. O kart dá um pulinho e derrapa.
  Fagulhas nas rodas traseiras mostram a carga: **azul → laranja → rosa**. Solte o botão para ganhar um turbo de **0,7 s, 1,2 s ou 1,8 s**, conforme o nível.
  Virar para dentro da curva fecha a derrapagem e carrega mais rápido; virar para fora abre a curva.
- **Faixas de turbo** (setas animadas no chão): dão ganho de velocidade, chama no kart e tremor de câmera.
- **Corrida**: contagem 3-2-1-GO, 3 voltas com checkpoints (cortar caminho não conta a volta), posição 1º/2º, tempo na chegada e tela de resultado.

## Teste automático (sem controle)
Os dois testes abaixo rodam sem controle:
- **Gameplay**: roda uma corrida simulada completa com 44 verificações. Cobre voltas, muretas, os 4 itens, o foguete reto de 3 s (inclusive o impacto na mureta), os níveis de turbo do drift e o fim de corrida.
- **Fluxo de telas**: splash → título → seleção → corrida → resultado, com entrada simulada. Confere também se as cores escolhidas chegam ao kart e ao piloto.
```
"C:\Users\henri\Downloads\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --fixed-fps 60 --path . res://tools/validate/validate_gameplay.tscn
"C:\Users\henri\Downloads\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --fixed-fps 60 --path . res://tools/validate/validate_flow.tscn
```

## Exportar um .exe rápido de teste
1. No Godot, abra **Editor → Gerenciar Modelos de Exportação → Baixar e Instalar** (versão 4.7.2).
2. Abra **Projeto → Exportar → Adicionar… → Windows Desktop**.
3. Clique em **Exportar Projeto**, escolha uma pasta (ex.: `build/UniversoKart.exe`) e confirme.
   Deixe "Embed PCK" marcado para gerar um único arquivo.

## Ainda não incluído nesta versão
NPCs de IA, animação de vitória, menu de opções (volume/qualidade) e o acabamento visual final.
Música e efeitos sonoros já vêm incluídos, gerados por código no carregamento.
