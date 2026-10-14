# Plantas (o pacote de flores comprado)

`FlowersByLoxxsy.rbxm` é o arquivo original que o dono comprou (sem scripts): pasta **FlowersByLoxxsy** com **Titanic** (as grandes) e **Normal** (99 modelos).

`lune run tools/export_plants.luau` (na pasta do jogo) gera `assets/Creature_<Semente>.rbxm` para cada zona: uma pasta com uma subpasta por raridade, cada uma com os modelos daquela zona e raridade. Cada planta plantada usa um deles (escolhido pelo número da planta, então vizinhas variam e uma planta nunca troca de visual).

## Regras

- **Pequenas** (a maioria da Normal, 3 a 12 studs) → Common / Uncommon / Rare. As mais leves (menos peças, quase sem partículas) ficam nas raridades comuns: um lote tem até 40 plantas.
- **Grandes** (20+ studs: toda a Titanic e as grandes da Normal) → **Legendary**.
- **Espadas** (katanas): **Cryonix** (gelo) e **Pyronis** (fogo; o mesmo formato e tamanho da Cryonix: cabo com faixas, guarda, lâmina para baixo). Só no **Spirit Garden**, como Legendary. Venomyx, Infernyx e Cybaris **não** são espadas (Infernyx é uma flor grande num caule; Venomyx e Cybaris são largas, sem forma de lâmina).
- **Meme / com efeitos** (Assassino, Bombardiro, Trallalero, Sahur, LaVaca, Ballerina, Patapim, StrawberryElephant, Mafioso, SixSeven...) → **Epic**.

## Zona × raridade

| Zona | Common | Uncommon | Rare | Epic | Legendary |
|---|---|---|---|---|---|
| 🌼 Meadow | Daisy, Tulip, Sunflower, Lily, Cornflower | Rose, Pansy, Dandelion, Iris, Thistle | Hellebore, Orchid, Pinkbells | Mafioso, Ballerina | Sunfloris, Verdantis, Rosaris |
| 🦂 Desert | Cactus, Succulent, Nuzwat | DesertWildFlower, KittyTowerFlower, ZebraFlower | Sunpetal, SolarIris, HaloOrchid, RadianceLily | Sahur, MantisReaper | Helios, Aetheris |
| 🦖 Jungle | BugEater, ZombeeFlower, ShimmeringLichen | SpiderLilly, UnicornPetunia, Beenspector, OceanBloom | Snapdragon, MeanFlower, GlowBerry | Bombardiro, Patapim | Venomyx, Paradoxys |
| 🌋 Lava Fields | EmberSpark, Pomeflower | DarkflareRose, RedStar | DragonFlower, FrostburnRose | StrawberryElephant, CrimsonWidow | Infernyx, Coreflare, Draconyx |
| ❄️ Snow Peaks | IcecapBloom, Snowdrop, HollyBloom, Mistletoe | WinterRose, PolarSpire, Snowpuff, FrostLily | Glacierheart, PoinsettiaBlossom, Gingerbread, Elf, CrystalizedPetal, CrystalDaisy | Santa, Reindeer, Trallalero | Frostwyrm, Aracnid, Lunaris |
| 👽 Deep Space | EclipseBloom, NebulaRose, Lobelia | MeteorFlower, Voidbloom, BorealBell | StarfallFlower, CyberFlower, Starpetal, Gleamblossom | LaVaca, SixSeven, TwilightAmarilis | Stellaris, Cybaris, Jellythys |
| ⛩️ Spirit Garden | Camellia, MoonlaceOrchid, Lightbloom | Bamboo, Whitenight, Crystalflower | BubbleLotus, IvoryIris, Ghostflower, Ghostleaf | Assassino, DualityFlower, DualityRose | **Cryonix** ⚔️, **Pyronis** ⚔️, Noctyra, Velkrya |

Não usadas: **AdminStarpetal** (está na Titanic, mas tem só ~10 studs: não é grande) e **BellFlower** (larga e baixa: ficava com ~2 studs). O **HollyBloom** aparece nas duas pastas; usamos o da Normal.

## Tamanho no jogo

- Cada modelo é redimensionado por igual para caber na largura e na altura da sua raridade (recém-nascida): largura **3,4** (Common, Uncommon, Rare), **4,4** (Epic), **5** (Legendary); altura até ~5 / 5,5 / 6 / 7 / 10 (+0,3 por zona). A largura é o que manda na maioria: flores largas ficam mais baixas.
- A planta cresce com o peso até ~2× (Common) e ~2,6× (Legendary): uma Legendary adulta tem **15 a 31 studs** de altura; uma Common, ~4 a 12.
- Por serem maiores, as Epic e Legendary precisam de mais espaço entre plantas e não podem ficar coladas na cerca (o jogo avisa "Plant on the brown dirt" se for perto demais da borda do canteiro).
- Peças: em média ~13 a 16 por planta (um lote cheio de 40 plantas ≈ 500 a 650 peças). As Legendary têm até 72.
- Partículas, beams e luzes dos modelos ficam (redimensionados junto). O jogo continua pondo o brilho de raridade (anel, halo, faíscas) e as cores das mutações.
- **Malhas**: as MeshParts usam os IDs de malha do vendedor. Elas aparecem no jogo publicado se a conta/grupo do jogo tiver permissão para esses assets.

Para trocar uma planta de zona/raridade: edite a tabela `PLANTS` em `tools/export_plants.luau` e rode o comando de novo (ou mova o modelo entre as subpastas no Studio e salve o arquivo `Creature_...` por cima).
