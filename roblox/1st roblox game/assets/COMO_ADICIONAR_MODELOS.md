# Como colocar seus modelos no Steal a Seed

Este guia é para quem faz os modelos (Blender + Studio). Tem duas formas de mudar o visual do jogo, e as duas são **permanentes**: nada do que você fizer seguindo este guia é apagado quando o dono recria o jogo.

| Quero... | Use |
|---|---|
| mexer no mapa: mover, girar ou apagar uma árvore ou placa, colocar um modelo meu num lugar específico | **A. Editar o mapa à mão** |
| trocar **todas** as árvores (ou arbustos, pedras, postes...) de uma vez, ou fazer as criaturas e os guardiões | **B. Modelos na pasta `assets`** |

Pode usar as duas ao mesmo tempo.

---

## A. Editar o mapa à mão

O mapa fica salvo no arquivo `roblox/1st roblox game/map/World.rbxm`. No Studio, ele é a pasta **Workspace → World**. O jogo usa esse arquivo do jeito que ele está: o que você muda e salva nele fica para sempre.

### Passo a passo

1. Abra o `StealASeed.rbxlx` no Studio (o dono te passa a versão mais nova, ou você gera com `rojo build`).
2. No **modo de edição** (sem apertar Play), mexa em qualquer coisa dentro de **Workspace → World**:
   - mover, girar ou redimensionar peças;
   - apagar decoração (árvores, flores, pedras, placas, cercas...);
   - arrastar seus próprios modelos para dentro do `World` (por exemplo, para dentro de `World → Base → Props`).
3. Clique com o botão direito em **World** → **Save to File...** → salve **por cima** de `roblox/1st roblox game/map/World.rbxm`.
4. Avise o dono. Ele confere, faz o commit e recria o jogo. Seu trabalho continua lá, porque o mapa agora vem do `map/World.rbxm`.

> ⚠️ **Nunca salve o `World` durante o Play (Play / Run).** Durante o jogo, o servidor coloca no `World` coisas temporárias (sementes nos ninhos, plantas, placa de recordes). Salve sempre no modo de edição.
>
> ⚠️ Salvar o lugar com Ctrl+S **não basta**: o `StealASeed.rbxlx` é recriado pelo dono. O que vale é o `map/World.rbxm` (passo 3).

### O que você NÃO pode apagar

Algumas peças fazem o jogo funcionar. Elas têm um **atributo `Role`** (veja em Properties → Attributes). **Pode mover, girar e trocar de pasta à vontade: o jogo acompanha.** Só não apague essas peças nem mude os atributos delas (`Role`, `PlotIndex`, `ZoneIndex`, `SlotIndex`, `PodIndex`).

| `Role` | O que é | Onde fica |
|---|---|---|
| `Plot` | o modelo do lote (Plot1 ... Plot5) | `World → PlotN` |
| `PlotFloor` | o chão do lote. Dentro dele ficam os pontos `Slot1`...`Slot40` (onde as plantas nascem) e `Spawn` (onde o jogador aparece) | `PlotN → Floor` |
| `PlantPad` | o quadrado de terra onde se planta | `PlotN → PlantPad` |
| `TreadmillBelt` | a esteira (o jogador ganha Speed em cima dela) | `PlotN → TreadmillBelt` |
| `TreadmillSign` | a plaquinha invisível com o texto da esteira | `PlotN → TreadmillSign` |
| `PlotSign` | a plaquinha invisível com o nome do dono | `PlotN → SignPost` |
| `UpgradeBoard` | a placa "⬆️ UPGRADE PLOT" (com os textos Level / Perk / Price) | `PlotN → UpgradeBoard` |
| `Slot`, `Spawn` | pontos (Attachments) dentro do chão do lote | `PlotN → Floor` |
| `Nest` | o modelo do ninho de cada zona | `World → Corridor → N_Zona → Nest_Zona` |
| `NestCore` | a peça invisível no centro do ninho, com os pontos `Center`, `Pod1`...`Pod4` (as sementes) e `GuardHome` (onde o guardião dorme) | `Nest_Zona → NestCore` |

- Mover o **chão de um lote** leva junto os pontos das plantas e o ponto de spawn. Mover o **NestCore** leva junto as sementes e a casa do guardião.
- Se faltar alguma dessas peças, o jogo **não quebra**: ele avisa no Output qual lote/zona e qual `Role` está faltando e gera o mapa de novo pelo código só naquela partida. Corrija o arquivo e salve de novo.
- Todo o resto é decoração: pode apagar, mover e adicionar o que quiser.
- **As zonas não mudam de lugar.** Os limites das zonas (onde cada guardião persegue, qual zona é qual) vêm do código, não do chão. Mover o chão ou as paredes de uma zona muda só o visual.

---

## B. Modelos na pasta `assets`

Cada arquivo nesta pasta (`roblox/1st roblox game/assets/`) troca **um tipo de peça** do jogo: todas as árvores, todos os postes, a criatura da Meadow, o guardião do Deserto... O nome do arquivo diz qual peça é (tabela no fim). O jogo encaixa o modelo sozinho no espaço da peça original.

### 1. No Blender

- **Aplique as transformações** antes de exportar: selecione tudo → `Ctrl+A` → **All Transforms**.
- Deixe o modelo **em pé sobre o chão**, com o centro da base perto da origem. O jogo recalcula isso, mas fica mais fácil de conferir.
- **Tamanho não importa**: o jogo redimensiona sozinho (veja o item 4).
- **Polígonos**: o Roblox aceita até ~20 mil triângulos por peça (MeshPart). Para o jogo rodar bem:
  - flores, pedras, arbustos, postes: **até ~1.000** triângulos;
  - árvores, cactos, lanternas: **até ~3.000**;
  - arcos, ninhos, barracas, criaturas: **até ~8.000**;
  - guardiões: **até ~15.000**.
- **Poucas peças**: 1 a 5 MeshParts por modelo (por exemplo, tronco + copa). Árvores e flores aparecem centenas de vezes no mapa.
- **Materiais e texturas**: o mais leve é usar só a cor + material do Roblox (Wood, Grass, Slate...) depois de importar, como na `arvore_variant3`. Se usar textura, uma imagem por malha, PNG até 1024×1024, embutida no FBX.
- Exporte em **FBX**: File → Export → FBX, marque **Selected Objects**, **Apply Scalings: FBX All**, **Forward: -Z**, **Up: Y**, **Apply Transform**, e em *Geometry* **Apply Modifiers**. Se tiver textura: **Path Mode: Copy** + o botão de **Embed Textures**.

### 2. No Studio (no seu próprio arquivo, não no do jogo)

1. Abra um lugar **seu** (por exemplo, `MeusModelos.rbxl`), não o `StealASeed.rbxlx`.
2. **Avatar → Import 3D** (3D Importer) → escolha o FBX → importe **como Model** (sem rig, a não ser que seja um guardião ou uma criatura e você saiba o que está fazendo).
3. Renomeie o Model com o **nome exato da peça** (tabela no fim). Exemplo: `Lamp`.
4. Botão direito no Model → **Save to File...** → salve em `roblox/1st roblox game/assets/` (formato `.rbxm`).
5. Avise o dono. Ele roda `lune run tools/apply_assets.luau` (coloca seus modelos no mapa, **sem perder as edições à mão**) e recria o jogo.

#### Exemplo: várias árvores diferentes (variantes)

Um arquivo pode ter uma **pasta com várias versões** do mesmo modelo. O jogo escolhe uma para cada lugar, sempre a mesma para o mesmo lugar.

```
Workspace
└── Arvores            (Folder)
    ├── arvore_variant1   (Model: madeira1 + topo1)
    ├── arvore_variant2   (Model: madeira2 + topo2)
    └── arvore_variant3   (Model: arvore3 + topo3)
```

Botão direito na pasta **Arvores** → **Save to File...** → `assets/Arvores.rbxm`. Pronto: todas as árvores redondas do jogo viram as suas, misturando as três versões. Do mesmo jeito: a pasta **Arbustos** → `assets/Arbustos.rbxm`.

#### Nomes

- Maiúsculas, acentos, espaços e `_` não importam: `arvores`, `Árvores` e `ARVORES` funcionam igual; `desert cactus` = `Desert_Cactus`.
- Apelidos em português: `Arvores` = `Tree`, `Arbustos` = `Bush`, `Pedras` = `Rock`, `Flores` = `Flower`, `Postes` = `Lamp`, `Cercas` = `FenceSection`, `Esteira` = `Treadmill`, `Portao` = `PlotGate`, `Barracas` = `ShopStall`, `Cactos` = `Desert_Cactus`, `Pinheiros` = `Snow_Pine`, `Boneco de Neve` = `Snow_Snowman`, `Cerejeiras` = `Spirit_CherryTree`.
- Um arquivo com nome errado é ignorado, e o jogo avisa no Output: `assets/X matches no slot`.
- Um arquivo por peça. Não salve duas coisas soltas no mesmo arquivo: use uma pasta.

### 3. Frente e ponto de apoio

- **Ponto de apoio = centro da base.** O jogo calcula sozinho: o fundo do modelo fica no chão e o meio dele fica no lugar da peça original.
- **Frente = o lado -Z** (para onde a peça "olha"). Para saber qual lado é esse no Studio: insira uma Part, coloque um **Decal** nela com `Face = Front`. O lado onde o Decal aparece é a frente. Gire seu modelo para olhar para o mesmo lado antes de salvar.
- A frente importa nas placas, arcos, barracas, portão, esteira, boneco de neve, guardiões e criaturas. Árvores, pedras e flores ganham um giro aleatório.
- Ficou virado errado no jogo? Não precisa exportar de novo: no Model, adicione o atributo **`Yaw`** (número, em graus: `90`, `180` ou `-90`) e salve o arquivo de novo.

### 4. Tamanho

- O jogo **aumenta ou diminui o modelo inteiro por igual** (sem achatar) até caber no espaço da peça original. Na tabela, "altura" é a altura final típica. A largura pode ir até o valor indicado.
- Quer o tamanho exato que você fez? Adicione ao Model o atributo **`KeepScale`** (Boolean) = `true`. Aí 1 unidade do Studio = 1 stud no jogo.

### 5. O que o jogo faz com seu modelo

- Prende tudo no lugar (**Anchored**). A decoração **não colide**: os jogadores e os guardiões passam através dela, então ela nunca atrapalha a corrida. Exceções: cercas (`FencePost`, `FenceSection`) e barracas (`ShopStall...`) mantêm a colisão que você salvou.
- Remove scripts que vierem dentro do modelo.
- Mantém materiais, cores e texturas.
- Luzes e partículas: se a peça original tinha luz (postes, lanternas, vulcões, ninhos), seu modelo ganha a mesma luz no mesmo ponto. Se o seu modelo já tiver um `PointLight` ou um `ParticleEmitter`, vale o seu.
- Criaturas: o jogo continua colocando o brilho de raridade (aura, halo, partículas) e as cores das mutações. Malhas com textura não mudam de cor nas mutações (Gold, Night...), mas ganham as partículas e a luz.
- Guardiões: seu modelo vira o corpo do gigante e desliza junto com ele na perseguição. **Animação ainda não funciona**: um modelo com rig fica parado na pose em que foi salvo.

### 6. Como conferir

1. Depois que o dono rodar `lune run tools/apply_assets.luau` e recriar o `StealASeed.rbxlx`, abra o arquivo: o modelo aparece no mapa **sem apertar Play** (árvores, cercas, arcos...).
2. Aperte **Play**: ele aparece no jogo também. As criaturas aparecem quando você planta uma semente, e os guardiões ficam nos ninhos.
3. Se aparecer a peça antiga, veja o **Output**: avisos com `[Assets]` dizem o que deu errado (nome que não bate, modelo sem peças, pasta vazia).
4. Modelo **cinza** ou **invisível** só no jogo publicado: os meshes que o 3D Importer enviou estão na **sua** conta. O dono precisa ter permissão para usá-los (Creator Hub → o asset → Permissions, ou envie os meshes para o grupo do jogo).

---

## Tabela de peças

"Altura" é a altura final típica (em studs; o jogador tem uns 5). A largura pode ir até "largura máx.".

### Peças repetidas (todo o mapa)

| Nome | O que é | Onde aparece | Altura | Largura máx. |
|---|---|---|---|---|
| `Tree` | árvore redonda (tronco + copa) | base, lotes | 18 a 25 | ~16 a 27 |
| `BlossomTree` | árvore florida (rosa) | praça do spawn | ~21 | ~20 |
| `Bush` | arbusto | base, lotes, Meadow | 3,5 a 6 | 7 a 15 |
| `Rock` | pedra | base, Meadow, lagos do Spirit Garden | 1,3 a 3 | 4 a 9 |
| `Flower` | flor (cabo + flor) | base, lotes, Jungle (e Meadow se não houver `Meadow_Flower`) | 2 a 4 | ~3 |
| `Lamp` | poste de luz | base, praça das lojas | ~10,5 | ~5 |
| `FencePost` | um poste da cerca | em volta dos lotes | ~5,6 | ~2 |
| `FenceSection` | as tábuas da cerca **entre dois postes** (sem os postes), comprimento ao longo do X | em volta dos lotes | ~6 | 7 a 8 de comprimento |

### Zonas do corredor

| Nome | O que é | Onde aparece | Altura | Largura máx. |
|---|---|---|---|---|
| `Meadow_Flower` | flor da Meadow | 🌼 Meadow | 2 a 3 | ~3 |
| `Meadow_Mushroom` | cogumelo vermelho | 🌼 Meadow | 2,5 a 4 | 5 a 6 |
| `Desert_Cactus` | cacto saguaro | 🦂 Desert | 9 a 15 | 4 a 10 |
| `Desert_Skull` | esqueleto gigante deitado (crânio olhando para +X) | 🦂 Desert | ~6 | ~13 × 45 de comprimento |
| `Desert_Bone` | osso solto no chão | 🦂 Desert | ~1 | ~2 × 6 |
| `Desert_Mesa` | rocha em degraus (mesa) | 🦂 Desert | 11 a 14 | 14 a 27 |
| `Jungle_Tree` | árvore alta com copa sobre o caminho (frente = caminho) | 🦖 Jungle | 31 a 42 | ~36 × 51 |
| `Jungle_Fern` | samambaia | 🦖 Jungle | ~3,3 | 15 a 19 |
| `Jungle_Log` | tronco caído (comprimento ao longo do X) | 🦖 Jungle | ~3 | ~18 |
| `Lava_Volcano` | vulcão encostado na parede (frente = caminho) | 🌋 Lava Fields | ~21 | ~24 |
| `Lava_Rock` | rocha de basalto (com magma) | 🌋 Lava Fields | 2,4 a 4,3 | 6 a 13 |
| `Lava_Obsidian` | espeto de obsidiana | 🌋 Lava Fields | 5 a 11 | 5 a 13 |
| `Snow_Pine` | pinheiro com neve | ❄️ Snow Peaks | 13 a 21 | 19 a 37 |
| `Snow_Snowman` | boneco de neve (frente = -X, olhando para quem chega) | ❄️ Snow Peaks | ~13 | ~9 |
| `Snow_Crystal` | grupo de cristais de gelo | ❄️ Snow Peaks | 4 a 9 | 6 a 14 |
| `Space_Planet` | planeta no céu (o apoio é o ponto mais baixo da esfera) | 👽 Deep Space | 22 a 38 | 30 a 95 |
| `Space_Crystal` | grupo de cristais neon | 👽 Deep Space | 7 a 13 | 9 a 20 |
| `Space_Asteroid` | asteroide flutuando | 👽 Deep Space | 4 a 10 | 5 a 13 |
| `Space_Mushroom` | cogumelo alienígena neon | 👽 Deep Space | 4 a 8 | 6 a 8 |
| `Space_UFO` | disco voador (o feixe de luz embaixo continua) | 👽 Deep Space | ~16 | ~29 |
| `Spirit_Torii` | portal torii vermelho atravessando o corredor (também o dourado do fim) | ⛩️ Spirit Garden, Fim | 43 a 52 | ~68 |
| `Spirit_Lantern` | lanterna de pedra (frente = caminho) | ⛩️ Spirit Garden | ~7 | ~6 |
| `Spirit_CherryTree` | cerejeira inclinada sobre o caminho (frente = caminho) | ⛩️ Spirit Garden | 18 a 22 | ~27 a 37 |

### Arcos e ninhos (um por zona)

O **arco** é a entrada da zona: pilares + viga + enfeite. A placa com o nome da zona e a linha brilhante no chão continuam do jogo. Ele atravessa o corredor inteiro (frente = -X, para quem chega). Altura ~60 a 90, largura ~74.

O **ninho** é a planta-mãe com o monte de terra, as pedras e a flor brilhante. As 4 sementes ficam num meio-círculo de 8 studs em volta do centro, a 2,5 de altura: deixe esse espaço livre. O texto "Mother Plant", a luz e as partículas continuam. Altura até ~40, largura ~28.

| Arco | Ninho | Zona |
|---|---|---|
| `Arch_Meadow` | `Nest_Meadow` | 🌼 Meadow |
| `Arch_Desert` | `Nest_Desert` | 🦂 Desert |
| `Arch_Jungle` | `Nest_Jungle` | 🦖 Jungle |
| `Arch_Lava` | `Nest_Lava` | 🌋 Lava Fields |
| `Arch_Snow` | `Nest_Snow` | ❄️ Snow Peaks |
| `Arch_Space` | `Nest_Space` | 👽 Deep Space |
| `Arch_Spirit` | `Nest_Spirit` | ⛩️ Spirit Garden |

### Base, lotes e lojas

| Nome | O que é | Onde aparece | Altura | Largura máx. |
|---|---|---|---|---|
| `Treadmill` | a estrutura da esteira (moldura, corrimãos, painel). A faixa preta onde se corre continua do jogo, a 1 stud do chão do lote. Frente = lado do painel, virado para o portão | cada lote | até ~24 | 12 × 32 |
| `UpgradeSign` | o suporte da placa "UPGRADE PLOT" (postes, moldura, telhadinho). A placa com o texto continua do jogo | na frente de cada lote | ~8 | ~8 |
| `PlotGate` | o portão do lote (dois pilares + arco), 20 studs de abertura. Não colide | entrada de cada lote | até ~16 | ~23 |
| `ShopStall` | barraca da praça das lojas (balcão, fundo, toldo). Frente = calçada. Vale para as três barracas | praça das lojas | ~21 | 18 × 21 |
| `ShopStall_Shop` | só a barraca 🛒 SHOP (se existir, vale mais que `ShopStall`) | praça das lojas | ~21 | 18 × 21 |
| `ShopStall_Trails` | só a barraca 🏃 TRAIL SHOP | praça das lojas | ~21 | 18 × 21 |
| `ShopStall_Index` | só a barraca 📖 INDEX | praça das lojas | ~21 | 18 × 21 |
| `SpawnSign` | a placa grande "🌱 STEAL A SEED 🌱" que flutua na entrada do corredor. O apoio é a borda de baixo da placa. **O texto tem que estar no seu modelo** (textura ou letras 3D) | entrada do corredor | ~12 | ~44 |

### Criaturas (aparecem quando uma semente é plantada)

Em pé, frente = -Z. O jogo cresce a criatura conforme o peso da planta, até ~2,6× o tamanho da tabela.

| Nome | Criatura | Zona | Altura (recém-nascida) | Largura máx. |
|---|---|---|---|---|
| `Creature_Sproutling` | Sproutling | 🌼 Meadow | ~5 | 3,4 |
| `Creature_Cactopod` | Cactopod | 🦂 Desert | ~5,5 | 3,4 |
| `Creature_Fernosaur` | Fernosaur | 🦖 Jungle | ~6 | 3,4 |
| `Creature_Magmabloom` | Magmabloom | 🌋 Lava Fields | ~6,5 | 3,4 |
| `Creature_Frostbulb` | Frostbulb | ❄️ Snow Peaks | ~7 | 3,4 |
| `Creature_Starpetal` | Starpetal | 👽 Deep Space | ~7,5 | 3,4 |
| `Creature_LotusWyrm` | Lotus Wyrm | ⛩️ Spirit Garden | ~8 | 3,4 |

### Guardiões (dormem ao lado do ninho e perseguem quem rouba)

Em pé, frente = -Z. Os nomes e os ícones de estado (💤 ❗ 😡) ficam em cima da cabeça.

| Nome | Guardião | Zona | Altura | Largura máx. |
|---|---|---|---|---|
| `Guard_GiantMole` | Giant Mole | 🌼 Meadow | ~23 | ~30 |
| `Guard_GiantScorpion` | Giant Scorpion | 🦂 Desert | ~23 | ~30 |
| `Guard_GiantDino` | Giant Dino | 🦖 Jungle | ~23 | ~30 |
| `Guard_LavaGolem` | Lava Golem | 🌋 Lava Fields | ~23 | ~30 |
| `Guard_GiantYeti` | Giant Yeti | ❄️ Snow Peaks | ~23 | ~30 |
| `Guard_BigAlien` | Big Alien | 👽 Deep Space | ~23 | ~30 |
| `Guard_SpiritDragon` | Spirit Dragon | ⛩️ Spirit Garden | ~23 | ~30 |
