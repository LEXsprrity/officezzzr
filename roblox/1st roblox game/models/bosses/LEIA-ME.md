# Guardiões: os pets com rig que o dono comprou

`Pets.rbxl` é o arquivo original ("Ultra-Detailed Pets Rig & Animation Ready", sem scripts). No Workspace há a pasta **PetTemplates** com 30 Models com rig (MeshParts com skinning em Bones, todos os Bones dentro da peça `RootPart`). A pasta **Rigless** (cópias sem rig) não é usada.

`lune run tools/export_bosses.luau` (na pasta do jogo) gera um `assets/Guard_<Nome>.rbxm` por zona:

| Zona | Guardião | Pet | Escala | No jogo (altura × largura × comprimento) |
|---|---|---|---|---|
| 🌼 Meadow | Giant Turtle | Turtle | 4,6 | 10 × 14 × 22 |
| 🦂 Desert | Red Mole | RedMole | 5,2 | 11 × 28 × 34 |
| 🦖 Jungle | Giant Snake | GiantSnake | 2,0 | 14 × 8 × 33 |
| 🌋 Lava Fields | Volcano Gorilla | GorillaVulcano | 2,4 | 15 × ~27 × 12 (braços para baixo) |
| ❄️ Snow Peaks | Ice Shark | IceShark | 4,1 | 15 × 24 × 32 (rebaixado para deslizar rente à neve) |
| 👽 Deep Space | Void Dragon | VoidDragon | 1,85 | 18 × 29 × 17 (asas abertas) |
| ⛩️ Spirit Garden | Lumistag | Lumistag | 1,8 | 18 × 14 × 13 |

- **O que vai para o jogo**: só as MeshParts (com as SurfaceAppearances) e a `RootPart` com os Bones. O AnimationController, as animações salvas (`AnimSaves`, `InitialPoses`, os IDs de animação nos atributos), os Motor6Ds e as peças auxiliares ficam de fora. Os IDs de animação do vendedor não são usados: **toda a animação é por código** (`src/shared/BossRigs.luau` + `src/client/GuardAnimator.client.luau`), em cada cliente, mexendo nos Bones.
- **Escala e posição**: cada pet é aumentado pela `scale` do seu perfil (tamanho das peças e posição dos Bones juntos), com o ponto do chão embaixo da `RootPart` na origem e a frente para -Z. Atributos: `BossRig` (o pet), `RigScale`, `KeepScale` = true e `Pivot` = (0, 0, 0) (o jogo põe esse ponto nos pés do guardião).
- **Perfis de rig** (`BossRigs.PROFILES`): para cada pet, quais Bones são as pernas (esquerda/direita, da frente/de trás), coluna, pescoço, cabeça, mandíbula, cauda, asas e nadadeiras, e o tamanho de cada movimento. Os pés e as mãos do kit são Bones "IK target" presos na raiz: o código os faz seguir a ponta da perna, e nada (pé, dedo, mão) entra no chão.
- **Malhas**: as MeshParts usam os IDs de malha do vendedor (sem mudança). Elas aparecem no jogo se a conta/grupo do jogo tiver permissão para esses assets.
- **Trocar um pet ou mudar o tamanho**: edite `BossRigs.BY_ZONE` / a `scale` do perfil em `src/shared/BossRigs.luau`, rode `lune run tools/export_bosses.luau` e depois `lune run tests/run.luau`. Um pet novo precisa de um perfil novo (os nomes dos Bones de cada kit são diferentes; `tests/bosses.spec.luau` confere que todos existem).
