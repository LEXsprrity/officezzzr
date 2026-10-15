# Esteiras por nível (os 10 modelos comprados)

`Treadmills.rbxl` é o arquivo original que o dono comprou (sem scripts). No Workspace há a pasta **Treadmills** com 10 `Tool`s; de cada uma o jogo usa só a pasta **Model** (o visual). `Root`, `SpeedPerSecond`, `BoundingBoxPart`, as WeldConstraints e os botões invisíveis `SwapLeft`/`SwapRight` são do kit do vendedor e ficam de fora.

`lune run tools/export_treadmills.luau` (na pasta do jogo) gera `assets/Treadmill_T1.rbxm` ... `assets/Treadmill_T10.rbxm`:

| Nível | Mult. | Modelo (Tool) | Tamanho no jogo (largura × altura × comprimento) | Faixa (largura × comprimento, altura) |
|---|---|---|---|---|
| 1 | x2 | Treadmill (branca/cinza, a mais simples) | 5,8 × 8,7 × 11,7 | 4,5 × 8,1, 0,95 |
| 2 | x2.25 | Lucky BlockTreadmill (blocos "?") | 11,3 × 7,1 × 13,0 | 4,5 × 9,1, 0,41 |
| 3 | x2.5 | HackerTreadmill (verde neon, portal) | 8,6 × 7,2 × 12,1 | 4,5 × 9,1, 0,29 |
| 4 | x2.75 | Sci-FiTreadmill (ciano neon, plataforma alta, tela translúcida) | 6,5 × 9,8 × 11,1 | 4,4 × 6,9, 2,84 |
| 5 | x3 | The FreezeTreadmill (azul, gelo) | 8,0 × 7,9 × 14,0 | 4,5 × 9,3, 0,79 |
| 6 | x3.5 | FlameTreadmill (branca com neon ciano) | 9,0 × 7,8 × 14,3 | 4,5 × 9,1, 0,79 |
| 7 | x4 | GoldenTreadmill (dourada) | 6,4 × 7,1 × 10,2 | 4,5 × 7,0, 1,30 |
| 8 | x5 | CelebrityTreadmill (dourada e azul) | 10,4 × 9,0 × 13,9 | 4,5 × 8,5, 1,47 |
| 9 | x6 | DemonicTreadmill (vermelha, espinhos, correntes) | 9,7 × 7,2 × 14,4 | 4,5 × 9,9, 0,31 |
| 10 | x8 | AngelicTreadmill (branca e dourada, asas) | 11,2 × 8,9 × 13,8 | 4,5 × 9,3, 0,38 |

- **Escala**: cada modelo é redimensionado para a faixa ter 4,5 studs de largura (a da esteira antiga), sem passar de 12 × 9,8 × 14,5 (por isso a Sci-Fi fica com 4,4: ela é alta).
- **Faixa** (`Belt`): uma peça invisível que marca onde se corre: a largura da peça da faixa do modelo, do fundo até o painel, na altura do Beam que o vendedor desenhou em cima da faixa. A esteira do jogo (invisível, `TreadmillBelt`) copia essa peça, então o Speed, a trava no meio, o "+X/s" e a placa Upgrade seguem cada nível.
- **Fim da faixa**: a faixa termina no painel, ou antes, onde termina a textura da esteira (o Beam do vendedor) se ela acaba antes. Na Sci-Fi a textura para 0,85 stud antes da tela e a peça da faixa continua por baixo do console: a trava ficava esse tanto mais perto da tela.
- **Tela translúcida** (`glass` na tabela `TIERS`): todas as telas do kit ficam na ponta do console, na frente de quem corre, da canela até acima da cabeça, e o console fica virado para o corredor; dali se vê o fundo da tela. Na Sci-Fi o fundo é um bloco neon ciano opaco e a faixa é alta: só aparecia um punho ao lado de um bloco de luz. Com `glass = 0.75` a tela e o painel atrás dela ficam translúcidos e o corredor vê quem corre.
- **Frente**: nos modelos o painel fica no lado +Z, então todos têm `Yaw` = 180.
- **Malhas**: as MeshParts usam os IDs de malha do vendedor (sem mudança). Elas aparecem no jogo se a conta/grupo do jogo tiver permissão para esses assets; senão ficam invisíveis/cinza no jogo publicado.
- **Materiais**: o jogo troca materiais realistas por plástico (por exemplo o `Glacier` da Freeze vira `SmoothPlastic` da mesma cor, ainda translúcido). Beams, partículas, luzes e os decals dos blocos "?" ficam.
- Para mudar a ordem ou ajustar a altura/área de uma faixa: edite a tabela `TIERS` em `tools/export_treadmills.luau`, rode o comando de novo, depois `lune run tools/apply_assets.luau --all`.
