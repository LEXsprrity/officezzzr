# Lista de tarefas (do dono do jogo)

Pedidos de 14/10/2026. As imagens de referência estão em `docs/references/`.
Marcar com `[x]` quando estiver feito e junto ao jogo.

- [x] **1. Tirar o Sleep Dust.** Remover a mecânica toda (hotbar tecla 2, produto na loja, inventário). Saves antigos que têm Sleep Dust continuam a carregar.

- [x] **2. HUD nova e mais simples, igual à referência.**
  - Canto inferior esquerdo só com o ícone de Speed (o nosso, com um "+") e o valor em rosa, e o ícone de dinheiro com o valor em verde, com texto grande e contorno. Ref: `02-simple-hud-speed-money.png`.
  - Barra de "Level" de Speed (Level X, progresso 0/10) com três botões de compra rápida `+10K`, `+100K`, `+1M` (amarelo, vermelho, arco-íris) com o preço em Robux, e o multiplicador atual ("x3 Multiplier"). Ref: `02-speed-level-bar.png`, `03-level-up-announcement.png`.
  - Botões Shop e Index com o mesmo estilo da referência (verde e azul, ícone e texto grandes, bolinha vermelha de notificação), e Slow Mode como interruptor.

- [x] **3. Anúncio de subir de nível.** Ao subir de nível aparece rápido no ecrã "LEVEL 3!" com o multiplicador por baixo. É curto e não tapa o jogo. Ref: `03-level-up-announcement.png`.

- [x] **4. Lendários muito raros no fim do jogo.** Plantas Legendary têm de ser muito, muito raras, sobretudo nas 2 últimas zonas (Deep Space e Spirit Garden). Têm de parecer exclusivas.

- [x] **5. Lojas bonitas e com scroll para a direita.** As lojas atuais estão feias e não dá para deslizar para a direita. Copiar o estilo da referência na Trail Shop: barra de título colorida com X vermelho, cartões grandes da cor do trail, raridade, "x2 Speed", botão verde de `$` e botão roxo de Robux, e barra de scroll horizontal. Ref: `05-trail-shop-reference.png` (antes: `05-our-trail-shop-before.png`).

- [x] **6. Recompensas para incentivar Like, Favorito e Comunidade.**
  - Janela "Free Gift!": "LIMITED TIME! 10,000 SPEED!" com 3 passos (dar Like, Favoritar, Entrar na comunidade) e botão para resgatar.
  - Presente "FREE GIFT" no mapa (no lugar do antigo baú grátis, que o dono pediu para tirar) e quadro "MOST MONEY/s" (ranking).
  - Ref: `06-free-gift-like-favorite-join.png`, `06-free-chest-and-leaderboard.png`.
  - **Falta o dono:** criar a comunidade (grupo) do jogo no Roblox e pôr o número dela em `Config.COMMUNITY_GROUP_ID` (e o nome em `Config.COMMUNITY_NAME`). Enquanto for `0`, o Free Gift diz "coming soon". A recompensa depende só de estar na comunidade: o Roblox não deixa verificar Likes nem dar prémios em troca de Like/Favorito (ver README, "Community rewards").

- [x] **7. Iluminação e cores mais vivas.** O nosso jogo está escuro e lavado. Queremos um céu azul limpo, sol forte, verde muito saturado e brilho. Ref: `07-lighting-reference.png` (antes: `07-our-lighting-before.png`).

- [x] **8. Placa de upgrade do lote mais bonita.** Placa escura com "Upgrade", "Level 6 > Level 7", um botão vermelho com o preço em `$` e um botão roxo com o preço em Robux, os dois a subir de preço com o nível. Ref: `08-upgrade-sign-reference.png`.

- [x] **9. Barraca de vender (SELL).** Uma barraca com toldo vermelho e branco e o texto "SELL" para vender plantas velhas. Ref: `09-sell-stall-reference.png`.

- [x] **10. Base mais simples, para as plantas serem o destaque.**
  - Chão de grama verde simples, muros lisos, cercas de madeira nos lotes.
  - Sem desenhos nos muros, sem árvores grandes nem arbustos na base.
  - Ref: `10-base-reference.png`, `10-base-reference-top.png` (antes: `10-our-base-before.png`).

- [ ] **11. Boss 1 em forma de planta.** O dono vai pedir o design ao Claude Design (prompt já feito). Animações: dormir, acordar, perseguir, apanhar o jogador e voltar. Sem estado de atordoado: o Bat é para usar em jogadores, não no boss.

- [x] **12. Enfeites das zonas bonitos (arte do mapa).** Cada zona com 3 a 6 cenários grandes e detalhes espalhados, tudo de blocos com studs iguais ao chão e às paredes (Neon só na lava, nos cristais e nas luzes). Lava Fields como a referência: altar-vulcão em degraus com a lava descendo em zigue-zague, poças no chão e fogo de verdade no topo, cachoeira de lava, terraços, respiradouros, colunas de basalto e árvores mortas. As paredes de cada zona são um tom mais escuro do chão, todas diferentes, com a faixa de cima na cor da zona. À noite as zonas do fundo aparecem (noite um pouco mais clara, sem neblina) e a parede do fim do corredor é clara, com cachoeira e lanternas acesas. Os portais torii do Spirit Garden saíram. Ref: `12-zone-art-reference.png` (antes: `12-our-lava-before.png`) e `12-corridor-reference.png`.

## Em andamento
- Ícones do Free Icon Pack (pasta `icons/`, 22 ícones), com um agente a trabalhar neles. Falta o dono enviar os ícones para o Roblox (chave de API ou Bulk Import).
