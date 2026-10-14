# Steal a Seed

A Roblox "steal-and-run" game in Luau, built with [Rojo](https://rojo.space) 7. It replaces Coin Rush.

Players get a fenced plot. From spawn, one long walled corridor runs through seven themed zones. Each zone has a sleeping giant guardian in its nest against the left wall of the corridor, its seed pods in a loose little cluster right beside it, at its right. Grab a seed pod, the guardian wakes and chases you, and you run home and plant it. A seed only says its rarity ("Rare Seed"): the flower it grows into is drawn at random when you plant it, a surprise, and its name pops up over it. It sprouts into a plant-creature with a weight ("2,018,798 Kg") that earns money. Money buys **trails** (they multiply the Speed you gain by moving) and **plot upgrades** (more slots, more income); Speed gets you further down the corridor, and further zones grow better seeds. **The goal is to reach the Spirit Garden, the last stage, and grow its seeds.**

| # | Zone | Guardian | Seed | Recommended Speed | Length (studs) |
|---|---|---|---|---|---|
| 1 | 🌼 Meadow | Giant Turtle | Sproutling | 0 | 100 |
| 2 | 🦂 Desert | Red Mole | Cactopod | 25K | 200 |
| 3 | 🦖 Jungle | Giant Snake | Fernosaur | 500K | 400 |
| 4 | 🌋 Lava Fields | Volcano Gorilla | Magmabloom | 2M | 400 |
| 5 | ❄️ Snow Peaks | Ice Shark | Frostbulb | 7.5M | 400 |
| 6 | 👽 Deep Space | Void Dragon | Starpetal | 25M | 400 |
| 7 | ⛩️ Spirit Garden (END) | Lumistag | Lotus Wyrm | 75M | 400 |

Zone lengths come from a formula (`Config.zoneLength`): the first zone is the shortest (`ZONE_LENGTH_BASE` = 100 studs, so a new player grabs a first seed within seconds), each next zone is twice as long (`ZONE_LENGTH_GROWTH` = 2) up to `ZONE_LENGTH_MAX` = 400 (about two corridor widths deep), and every later zone stays at the max. The corridor is 2,300 studs long, so a run to the end takes about 13 s at the Spirit Garden's recommended Speed (WalkSpeed 171) and at max WalkSpeed (180). There are no zone gates, arches or name signs: one zone flows into the next by its floor and wall colours (a banner on the screen names the zone you enter), and a small studded orange plank (6 × 3.5, chest height) on a short post just in front of each sleeping boss (a few studs from its nose, a little to its left) says its recommended Speed ("👟 700K recommended"; the Meadow's says "Start here"), green once your Speed reaches it and red below. Streaming is off and the air is thin, so from spawn you can see down the whole corridor to the Spirit Garden's back wall.

## Controls
| Key / button | What |
|---|---|
| **E** (hold) | Steal a seed pod |
| **Click** / **tap** your plot's brown dirt (gamepad **R2**) | Plant the picked seed (hotbar slot **2**, or a seed or plant from the Inventory after **Plant** in the Plants panel) right there: a translucent 3D ghost of exactly the plant that will grow, at the size it will have when planted, shows where, green if it fits, red if not. **Q**, **2** again or **Cancel** cancels a picked seed (see "Planting") |
| Click / tap the board's buttons, or **E** / **F** at the board by your plot's entrance | Upgrade your plot one level: the red **$** button (or **E**) for money, the purple **R$** button (or **F**) for Robux. Only the owner can use them; no prompt popups, just the sign. The treadmill's board in front of your plot works the same way |
| **E** at the SELL stall | Opens the Sell window: sell your plants for 2 min of their income each (see "Selling plants") |
| **E** at the FREE GIFT box (by the spawn, left of the corridor mouth) | Opens the Free Gift window: 25,000 Speed once for joining the game's community |
| **1** | Bat: stuns a nearby awake guard for 2 s (4 s cooldown) |
| **2** (or tap the hotbar's seed slot) | Pick the seed most recently put in your seed bag (at first the rarest) and start its planting ghost; **2** again or **Q** puts it back. The slot shows that seed as it looks and how many seeds the bag holds |
| Shop / Index (left) | Shop (seed packs, plot upgrade, Speed, money, treadmill, passes) / Index (collection book). The Trail Shop (buy trails for $ or R$, equip one) opens at the TRAIL SHOP stall in the plaza |
| **+** on the Speed icon (bottom left) | Opens the Shop at its Speed section |
| Slow Mode switch (left) | Clamps your own WalkSpeed to 16 for moving around the base |
| 🌱 🪴 (right) | Seeds (incl. your seed bag: **Plant**, then click or tap your dirt) / Plants: a card per plant (its flower's name, rarity, Kg, $/s, the Day/Night bonus while it's on) with a **Remove** button: click it, it turns into **Sure?** for 2 s, click again to remove the plant (refunds 30 s of its income) |

## Seed packs
Our version of "eggs with odds": **two premium, late-game packs, Robux only**. Each pack is a developer product, and there is no way to buy one with in-game money. The 🛒 Shop starts with the **-- SEED PACKS --** section, which shows both packs as big cards in their zone colours, each with its exact odds table and an R$ button.

| Pack | Product | Rolls | Placeholder price | Rarity odds | Mutations |
|---|---|---|---|---|---|
| 👽 Starpetal Pack | `PackSpace` | 1 Deep Space (zone 6) seed | 2,000 R$ | Common 20%, Uncommon 23.3%, Rare 26.1%, Epic 29.2%, **Legendary 1.5%** | 🌟 Celestial 0.5%, Gold 8%, Rainbow 2% |
| ⛩️ Lotus Wyrm Pack | `PackSpirit` | 1 Spirit Garden (zone 7) seed | 3,000 R$ | Common 18.2%, Uncommon 22.4%, Rare 26.5%, Epic 31.4%, **Legendary 1.5%** | 🌟 Celestial 0.5%, Gold 8%, Rainbow 2% |

- **No Speed gate.** Anyone can buy either pack, even at 0 Speed: they're a premium shortcut to late-game seeds.
- **Odds.** A pack rolls Common..Epic like a *night* pod in its zone (`PACK_LUCK = NIGHT_LUCK = 2`), but **Legendary is a fixed 1.5%** (`PACK_LEGENDARY_CHANCE`, about 1 in 67: better than any steal, still a rare event), with doubled Gold/Rainbow chances (`PACK_MUTATION_MULT = 2`). The Night mutation never rolls from packs. The odds in the UI come from the same function the server rolls with (`SeedPacks.odds`).
- **🌟 Celestial** (×12 income) is pack-only: both packs roll it at `PACK_EXCLUSIVE_CHANCE` (0.5%). Pods never roll it: its pod `chance` is 0, and the tests roll pods in every zone, day and night, to check.
- **Prices.** The real price is whatever you set on the Creator Dashboard. The Shop fetches it once per product with `MarketplaceService:GetProductInfo` (pcall'd and cached) and shows it as `R$ 2,000`. Until that works, or while the id is still `0`, it shows the placeholder `robux` from `Config.DEVELOPER_PRODUCTS`.
- **Buying.** Clicking a pack with `id = 0` shows a "coming soon" toast. With a real id, the server checks `Shop.canPrompt` (a known product, bag below `SEED_BAG_MAX`) and calls `PromptProductPurchase`. `ProcessReceipt` grants. A receipt that arrives is **always** granted, because the player paid.
- **Receipts.** `ProcessReceipt` grants once per `PurchaseId` (the last 100 ids are kept in the profile), saves, and only then returns `PurchaseGranted`. If the save fails it returns `NotProcessedYet`, and a retry in the same session doesn't grant twice. If the server dies before saving, neither the seed nor the id were saved, so the retry on the next server grants exactly once.
- **Where the seed goes.** Into a persisted **seed bag** (`profile.seedBag`, stacks by `zone:rarity[:Mutation]`). Press **Plant** on it in the Plants panel's **Inventory** tab, then click or tap your plot's dirt: the same rules as a carried seed (see "Planting"). `SEED_BAG_MAX` (50) is a soft cap: the Shop won't *prompt* past it, but paid grants go past it up to `SEED_BAG_HARD_MAX` (250). A pack whose seed doesn't fit at the hard max pays money instead: `PACK_FULL_BAG_INCOME_SECONDS` (300 s) of your current income, or 300 s of a Common plant from that pack's zone if that's more (so a player with no plants still gets something). A paid pack is never lost, and a toast says what happened.
- **Reveal.** A reel spins through candidate seeds, lands on the server's result and bursts in its rarity colour.

## Planting: anywhere on your dirt
Each plot (owner's reference) is fenced with a chunky studded wooden fence and has **two brown dirt beds**, left and right, with a grass path down the middle from the entrance. You plant **anywhere on your own beds**, not in fixed slots:
- **Preview.** After picking a seed (hotbar slot **2**, or **Plant** on a seed or plant in the Inventory; or while carrying one), `Planting.client` shows a translucent **3D ghost** of exactly the plant that will grow, facing the way plants face, where the mouse points on your dirt (on a phone: where you last tapped; on a gamepad: just in front of you), **ghost-green** if it fits and **red** if not. Every seed has a hidden **gene** from the moment it exists (a pod's roll, a pack; `Config.rollGene`, kept in the carry and in the bag key `zone:rarity[:Mutation]#gene`, save v10): it decides its flower, its weight variance and its seed design, so the ghost is that flower at the size it has right when planted (an inventory plant: its own flower and size). The name stays a surprise: every label still says "Rare Seed" until it is planted, when the flower's name pops up for 2 s. The server builds a ghost per flower the first time a seed needs it (`Server/PlantGhosts.ensure` into `ReplicatedStorage.PlantGhosts`, plain inert parts). A bag seed from before v10 gets its gene when you pick it. A refused click shows why in small relief text near the bottom; there is no hint box. Click / tap / **R2** plants. **Q** or **Cancel** cancels a picked seed.
- **Rules** (`Shared/Planting.check`, the same on the client and the server): the spot is on one of **your own** plot's beds (`Role = "PlantBed"`), with `PLANT_BED_MARGIN` (2 studs) of dirt around it; at least `Planting.minDistance` from every other plant, i.e. both plants' full-grown reaches minus `PLANT_OVERLAP` (1 stud), so a Legendary needs more room than a Common; within `PLANT_REACH` (28 studs, flat) of where you stand; and the plot has a free slot (`Sessions.maxSlots`: plot level + ExtraSlots pass). The server re-checks all of it on every `PlantSeed` (rate-limited, the position must be a real finite Vector3) and toasts the reason when it refuses; a refused seed stays carried or in the bag.
- **Saved spots.** A plant saves where it stands in the plot's own space (origin: the floor's top centre, looking in from the entrance), so it lands in the same place on whatever plot index you get next time. It keeps an id (`slot`, the smallest free number) that the Plants panel's Remove button, the plants view and the SELL stall use. Old saves: see "Old saves".
- **Inventory** (`Server/Inventory`, save v9). The Plants panel has two tabs, **Plants** and **Inventory** (the old Seeds side menu is gone). **Remove** on a plant takes it off the plot into the inventory as it is (its flower, mutation and growth: its age stops, its weight variance is kept), for **no money**; at most `INVENTORY_MAX` (50), and Remove is off while it's full. The Inventory lists the seed bag's seeds ("Rare Seed x2 · Desert") and the removed plants (by flower), each with a **Plant** button that starts the ghost preview; a plant planted again keeps its flower, mutation and weight and grows on. The **SELL stall** lists planted and inventory plants and pays the same price for either.
- **Home with a seed.** A stolen seed goes into the seed bag by itself the moment you cross from the corridor into the base (`SeedService.storeCarried`, checked 5 times a second), free slots or not, so it never stays on your back; its pod regrows. Plant it from hotbar slot **2** or the Inventory. With the bag at `SEED_BAG_MAX` it stays carried, and the Inventory and a relief line near the bottom say so.
- **Seeds look.** Pods and the carried seed are the owner's bought seed models (`assets/Seed_<ZoneId>`, 2 designs per zone, none shared between zones; `tools/export_seeds.luau`), the gene picking the design whatever the rarity (the rarity shows only in the name tag). No Neon, no light. Pod name tags are relief text, always drawn on top, at staggered heights.


## Economy: what money and Robux buy
**In-game money buys only three things: trails, plot upgrades and treadmill tiers.** Everything else in the Shop is Robux (developer products and gamepasses). There is no money path to Speed or extra slots (`Shop.buy` refuses them, and tests check it).

### 🏃 Trails (money or Robux)
A trail is a coloured `Trail` that streams behind your character (two Attachments on the HumanoidRootPart, made by the server so everyone sees it, rebuilt on every respawn and every equip). The equipped trail multiplies the Speed you **gain** from walking and the treadmill: a small multiplier on the flat Speed per step (x1 to x3, see Progression). You own trails (saved) and equip one at a time. Any tier can be bought directly, without the one below it. Buying one equips it.

| Trail | Rarity | Speed gain | Money | Robux product | Placeholder |
|---|---|---|---|---|---|
| Grey | Common | x1 | free: every player owns it and starts with it equipped | — | — |
| Green | Uncommon | x1.25 | $5K | `TrailGreen` | 16 R$ |
| Blue | Rare | x1.5 | $75K | `TrailBlue` | 24 R$ |
| Purple | Epic | x1.75 | $1.5M | `TrailPurple` | 40 R$ |
| Golden | Legendary | x2 | $30M | `TrailGolden` | 64 R$ |
| Red | Mythic | x2.5 | $20B | `TrailRed` | 100 R$ |
| Rainbow | Secret | x3 | $1T | `TrailRainbow` | 180 R$ |

The **Trails** button on the left of the HUD and the 🏃 TRAIL SHOP stall open the Trail Shop: one row of tall cards that scrolls sideways (scrollbar at the bottom, mouse wheel, drag/swipe, and `<` `>` arrows while cards are hidden on that side). Each card is in the trail's colour, with the name and rarity, the Trail Shop icon tinted over a ribbon of the trail's colours, an "**x2** Speed" pill, and a green **$** button plus a bright green **R$** button (the Shop's green), or **Equip** / **Equipped** once owned. The title bar shows the Speed one step pays right now and your money.

The Shop, the Trail Shop, the Index and the Sell window share one window style: a coloured title bar (green Shop, purple-pink Trail Shop, blue Index, red-orange Sell) with light diagonal stripes, a big outlined title and a red square **X**, over a dark body with faint studs. The Shop's sections are big gold/green headings over 4-wide card grids (big icon, the amount in big outlined text, a green R$ button and a purple gift button). On small screens the whole window scales down to fit.

**UI text is words, not emoji.** Only the window and panel header icons (Shop, Index, Sell, Trail Shop, Seeds, Plants, the money / Speed / discovered counts in the title bars), the HUD's icon buttons (Shop, Index, Seeds, Plants, Bat, gift), the day/night timer's icon, the zone banner's faces and the 🔒 on locked zones stay. Where an emoji meant something, words or colour say it now: "Unlocked" in green on the Seeds panel, "Day x0.8" / "Night x0.8" in a muted grey while a plant is out of its phase (plant billboards, Plants panel, Sell cards), the zone's phase as "Day" / "Night". Toasts strip any emoji the server sends (except the lock). `tests/hud.spec.luau` scans the client scripts for emoji outside those places.

**Toasts** sit at the top, just under Roblox's top bar; while a zone banner (ZoneBanner.client) shows they slide down under it. Only what the player must be told is toasted: the server's messages (mostly why something was refused), getting caught, offline earnings, day/night and server-wide announcements. Stealing, planting, selling, removing, buying, the bat and guards waking are seen in the world and heard (Effects.client): no toast, and no banner while you carry a seed. Walking back into the base shows no banner either.

**Plants are named after their flower.** Each plant grows into one of its zone × rarity's flower models (`assets/Creature_<Seed>.rbxm`, picked by its id), and that model's name is what the game calls it: the billboard over it (shown while the mouse is over the plant, or for 3 s after a tap), the Plants panel, the Sell cards ("Daisy", "Gold Desert Wild Flower"; `PlotService.plantName`, `CreatureModels.variantOf`, `Format.plantName`). A seed (carried, in the bag, in a pack reveal) is still named after its zone's seed ("Common Sproutling") until it grows. The **Index** has a row per zone (its name and the mutations found there) and a column per rarity listing that rarity's flowers: lit with the name once you've grown one, "???" until then (`stats.catalog`, sent at join; Index keys `zone:rarity:Model` next to the old `zone:rarity`, so saves stay compatible; flowers already planted in an old save count when it loads).

### ⬆️ Plot upgrades (money or Robux)
Every plot has a level. Level 1 has `SLOTS_START` = 5 slots. Each level adds **one slot** (30 at level 26, the last) and **+6%** to a multiplier on all the plot's plant income (x1.06 at level 2, x2.5 at level 26). The multiplier applies in the payout loop, to offline income and to removal refunds, together with the day/night multiplier and the 2x Money pass (`Config.moneyMult`). The ExtraSlots gamepass still adds +10 slots on top.

Upgrading to level L costs `500 × 3.1^(L−2)`:

| Level | Slots | Income | Price | | Level | Slots | Income | Price |
|---|---|---|---|---|---|---|---|---|
| 2 | 6 | x1.06 | $500 | | 15 | 19 | x1.84 | $1.2B |
| 3 | 7 | x1.12 | $1.6K | | 16 | 20 | x1.9 | $3.8B |
| 4 | 8 | x1.18 | $4.8K | | 17 | 21 | x1.96 | $11.7B |
| 5 | 9 | x1.24 | $14.9K | | 18 | 22 | x2.02 | $36.4B |
| 6 | 10 | x1.3 | $46.2K | | 19 | 23 | x2.08 | $112B |
| 7 | 11 | x1.36 | $143K | | 20 | 24 | x2.14 | $349B |
| 8 | 12 | x1.42 | $443K | | 21 | 25 | x2.2 | $1.1T |
| 9 | 13 | x1.48 | $1.4M | | 22 | 26 | x2.26 | $3.4T |
| 10 | 14 | x1.54 | $4.3M | | 23 | 27 | x2.32 | $10.4T |
| 11 | 15 | x1.6 | $13.2M | | 24 | 28 | x2.38 | $32.3T |
| 12 | 16 | x1.66 | $41M | | 25 | 29 | x2.44 | $100T |
| 13 | 17 | x1.72 | $127M | | **26** | **30** | **x2.5** | **$310T** |
| 14 | 18 | x1.78 | $393M | | | | | |

The last level is meant to be hard. A strong late-game player (a full level-25 plot of full-grown Spirit Garden plants with the average pod rarity and mutation mix, day/night averaged) earns about $9.7B/s, so level 26 takes about **9 h** of income, or about **4.5 h** with the 2x Money pass (tested). Level 2 costs under a minute of a starting plot.

Buy at the **Upgrade** board just outside your plot's entrance, or for money in the Shop's **-- PLOT UPGRADE --** section. The board (like `docs/references/08-upgrade-sign-reference.png`) is a dark navy studded sign on a short post: "Upgrade", "Level X > Level Y" in green, a red button with the money price and a purple button with the Robux price, both rising with the level. At the last level it says **MAX LEVEL** and shows no buttons. The owner clicks or taps the buttons (a ClickDetector over each painted button: mouse and touch), or presses **E** (money) / **F** (Robux prompt): the keys come from ProximityPrompts with `Style = Custom` and no UI, so no black popups cover the sign. Both are owner-only (the client opens them for the owner only; the server re-checks the owner and the distance). On your own boards (this one and the treadmill's) the **$** button turns **green** while you can afford it (money ≥ price) and is red otherwise: the server writes the shown price on the painted button (`Price` attribute) and your client compares it with your money (`Shared/BoardButton.cashColors`, `Effects.client`); everyone else sees your boards red.

**Robux upgrades.** A developer product has one fixed price, so the 25 upgrades are split into six tiers (`PLOT_UPGRADE_TIER_LEVELS` = 4 upgrades each, the last takes 5), each its own product: `Config.plotUpgradeProduct(level)` picks the product for the plot's current level, and the purple button shows its price.

| Plot level now | Buys level | Product | Placeholder |
|---|---|---|---|
| 1-4 | 2-5 | `PlotUpgradeT1` | 25 R$ |
| 5-8 | 6-9 | `PlotUpgradeT2` | 49 R$ |
| 9-12 | 10-13 | `PlotUpgradeT3` | 99 R$ |
| 13-16 | 14-17 | `PlotUpgradeT4` | 199 R$ |
| 17-20 | 18-21 | `PlotUpgradeT5` | 399 R$ |
| 21-25 | 22-26 | `PlotUpgradeT6` | 799 R$ |

- Only the tier of your plot's current level is prompted (`Shop.canPrompt`; a cheap tier can't buy a late level), and nothing once the plot is maxed.
- A receipt grants **exactly one level**, from the level the plot has when the receipt is processed, through the usual idempotent path (once per `PurchaseId`, saved, then confirmed). If you bought levels with money in between, you still get one more.
- If the plot is **already at level 26** when a receipt arrives (e.g. maxed with money while the purchase was pending), the receipt pays the last level's money price instead (`Config.plotUpgradeMaxedPay()`, $310T), so a paid purchase is never lost.
- The purple button shows the placeholder until the product has an id, then the Dashboard price. The **server** fetches it with `GetProductInfo` (once per id, cached, retried after a minute on failure) and redraws every board: the price is the same for everyone who reads the board, so the server-drawn SurfaceGui needs no client code.

### 🏃 Treadmill upgrades (money or Robux)
Standing on **your own** plot's treadmill pays a **fixed Speed per second for its level**, times your equipped trail (x1 Grey … x3 Rainbow), every tick, AFK included. Nothing else changes it: not your WalkSpeed, not the Speed you already have (owner decision: "level 1 → X Speed/s always"). Only your own treadmill pays: someone else's gives nothing, doesn't play the run-in-place animation, and you can't step onto it. There are 10 levels (`Config.TREADMILL_TIERS`, `Config.treadmillPerSecond`), bought one at a time:

| Level | Speed/s (× trail) | Money | Level | Speed/s (× trail) | Money |
|---|---|---|---|---|---|
| 1 | +100/s | free | 6 | +600/s | $10B |
| 2 | +200/s | $1M | 7 | +700/s | $100B |
| 3 | +300/s | $10M | 8 | +800/s | $1T |
| 4 | +400/s | $100M | 9 | +1K/s | $10T |
| 5 | +500/s | $1B | 10 | +1.5K/s | $100T |

- **Where.** The treadmill stands **outside the plot, in front of it** (between the front fence and the walkway, beside the entrance path), sized to a character (belt about 4.5 × 9 studs). Its Upgrade board (`TreadmillBoard`, built at runtime in line past the belt's back end, facing the walkway) has the same buttons as the plot's board: click/tap the red **$** or purple **R$** button, or press **E** / **F**, with no prompt popups. Also the Shop's **-- TREADMILL --** card ($ and R$ buttons, like the plot card: "LEVEL 3 TREADMILL", "+200/s > +300/s · Level 3/10"). The server re-checks the owner and the distance (`Treadmill.canUseBoard`); at the last level the keys switch off.
- **Lock.** Stepping on your own belt holds you at the **centre of the belt** (`Treadmill.lockCFrame`, wherever you stepped on), running in place, until you jump.
- **What it shows.** The board says `Level 2 > Level 3` and under it `+200/s > +300/s` (what a second pays now and at the next level, with your trail; `Treadmill.boardRateText`), or `MAX` and just the rate. The small `+X/s` over the belt and the `+X` popups over the runner show the same number (`Treadmill.perSecond(tier, trail)`, exactly what the server pays a second), refreshed every payout.
- **Robux.** One fixed-price product per band of three upgrades, like the plot's (`Config.treadmillUpgradeProduct(tier)`): `TreadmillT1` (to levels 2–4) 19 R$, `TreadmillT2` (5–7) 39 R$, `TreadmillT3` (8–10) 79 R$. Only your level's band is prompted, a receipt grants **exactly one level** from the level you have when it arrives (idempotent, saved, then confirmed), and a receipt for a treadmill that is already maxed pays $100T instead (`Config.treadmillUpgradeMaxedPay`). All 9 upgrades with Robux cost 3×19 + 3×39 + 3×79 = 411 R$.
- **Balance** (tested in `tests/progression.spec.luau`, see Progression). The free player buys level 2 after ~11 minutes and level 9 near the Spirit Garden; level 10 is a late-game sink. An AFK farmer, who fills the plot once and then only stands on the treadmill buying the same upgrades, is behind the active player at every zone from the Jungle on and takes about 5x as long to reach the Spirit Garden: the corridor's better plants are what pay for the better treadmill.

### 💎 Robux (developer products)
Every developer product ships as an `id = 0` stub with a placeholder price: clicking it says "coming soon". With a real id the server checks `Shop.canPrompt` and opens `PromptProductPurchase`; `ProcessReceipt` grants through the same idempotent path as the seed packs (granted once per `PurchaseId`, saved, then confirmed). The Shop shows the real price from `GetProductInfo` (cached) once the id is set.

| Section | Products | What a receipt grants |
|---|---|---|
| -- SPEED -- | `Speed25K` 9 R$, `Speed150K` 36, `Speed250K` 64, `Speed750K` 76, `Speed3M` 560, `Speed10M` 1,200, `Speed25M` 1,600, `Speed50M` 2,400 | adds to your Speed stat: +25K is the Desert, +750K past the Jungle, +3M past the Lava Fields, +10M past the Snow Peaks, +25M the Deep Space, +50M two thirds of the way to the Spirit Garden (75M) |
| -- MONEY -- | `Money24K` 40 R$, `Money200K` 80, `Money800K` 200, `Money4M` 400, `Money8M` 640 | **max(fixed amount, N minutes of your current income)**: $24K / 10 min, $200K / 30 min, $800K / 60 min, $4M / 180 min, $8M / 360 min. Fixed amounts go worthless late, so late players get the income share. The card shows what you'd get right now. |
| -- TREADMILL -- and the treadmill's F prompt | `TreadmillT1` 19 R$, `T2` 39, `T3` 79 | one treadmill tier (only your tier's band is prompted; a maxed treadmill gets $100T instead; see Treadmill upgrades) |
| trails | `TrailGreen` … `TrailRainbow` | owns and equips the trail (owned trails aren't prompted) |
| the Upgrade board's purple button | `PlotUpgradeT1` 25 R$, `T2` 49, `T3` 99, `T4` 199, `T5` 399, `T6` 799 | one plot level (only your level's tier is prompted; a maxed plot gets $310T instead; see Plot upgrades) |
| -- SEED PACKS -- | `PackSpace`, `PackSpirit` | see Seed packs |
| -- PASSES -- | gamepasses `DoubleMoney`, `ExtraSlots` | unchanged |

Each Robux card also has a purple 🎁 gift button. Gifting isn't built yet: it shows a "coming soon" toast.

### 💰 Selling plants: the SELL stall
The shop plaza's 4th stall (like `docs/references/09-sell-stall-reference.png`) is an open wooden stall with a red-and-white striped awning, a soft green glowing circle on the floor in front of it and a big red outlined **SELL** floating above. Its prompt (`OpensShop = "Sell"`, **E**) opens the **Sell** window: one card per plant, cheapest first, with the plant's name in its rarity colour, its mutation (only on a mutated plant), weight, $/s (with a muted grey "Night x0.8" / "Day x0.8" while it is out of its phase), the sell price and a red **Sell** button. A second click ("Sure? Sell") sells it. **Sell all Common** and **Sell all below Rare** sell those rarities in one go but keep mutated plants; they ask first in a confirm bar inside the window (no system dialogs). The window scrolls, scales down on phones, and updates the prices in place on each payout instead of rebuilding.

- **Price.** `Config.SELL_STALL_SECONDS` = **120 s** of the plant's current base income (it grows with weight; no day/night, like the refund) × the plot level and 2x Money multiplier (`Selling.price`). That is 4× the Remove refund (`SELL_SECONDS` = 30 s, unchanged), so the walk is worth it, but only 2 minutes of what the plant earns by staying: selling never beats keeping a good plant, and steal-plant-sell trips earn far less than a planted plot.
- **Server checks** (`SellPlants(slots)`, rate-limited like the other remotes): a plain list of at most 40 whole numbers, only slots you have a plant in (others are skipped), each slot sold once even if named twice, and you must stand within `SELL_STALL_DISTANCE` (20 studs) of a SELL stall's prompt part (`WorldBuilder.sellPoints`). Selling frees the slots, removes the creatures, refreshes income and the plants view (saved by the autosave, like a removal), and the client gets the cash sound and a +$ popup over the stall.
- The stall is the `ShopStall_Sell` asset slot, with no `ShopStall` fallback: it keeps its own look until it gets its own model. The circle and the SELL text stay from code.

### 🎁 Community rewards: Free Gift, MOST MONEY/s
Like `docs/references/06-free-gift-like-favorite-join.png` and `06-free-chest-and-leaderboard.png`. Rules in `Rewards` (pure, tested), Roblox side in `RewardService`, UI in `Rewards.client` (its own script: `HUD.client` is near Luau's 200-locals limit; same window style, drawn inside the HUD's ScreenGui so it shares its scale and the toasts show over it).

**Free Gift window.** The pink **gift box** opens it. It stands where the free chest used to (owner request: no free chest, only the gift), against the inside of the front wall, left of the corridor mouth, by the spawn: `GiftBox` (server) builds it at runtime on the map's gift spot (an invisible part with Role `GiftSpot`, so moving that part in the map moves the gift), with a pink glowing circle, "FREE GIFT" floating above it and an **E** prompt ("Open", "View" once claimed; attribute `FreeGift`) that `Rewards.client` answers by opening the window. It also opens by itself once per account, `FREE_GIFT_AUTO_OPEN` = 20 s after joining. Cyan title bar "Free Gift!" with the red X, a big Speed bag, "~ LIMITED TIME! ~" in red and "25,000 SPEED!" in cyan-to-green, three step panels and a big **CLAIM!** button (grey **CLAIMED!** once done).
1. **Like the game!** Text only ("Tap 👍 on the game page"): a like can't be prompted or checked in game.
2. **Favorite the game!** A ⭐ Favorite button opens Roblox's own favourite prompt, `AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)` (the place is an asset; pcall'd; if it can't open, e.g. in Studio, the window says where the button is).
3. **Join the community!** A Join Community button. A group join can't be prompted in game, so it says how: game page → Community → Join `Config.COMMUNITY_NAME`.

**What the reward depends on: only the community (group).** CLAIM! sends `ClaimReward("Gift")`. The server checks `Player:IsInGroupAsync(Config.COMMUNITY_GROUP_ID)` (pcall'd; the deprecated `IsInGroup` as a fallback). Roblox can answer that from a per-session cache, so a "no" is re-checked with `GroupService:GetGroupsAsync`, which sees a group joined a minute ago. A "yes" is cached for the session and a "no" for 10 s. It grants `FREE_GIFT_SPEED` = **25,000 Speed** (the Desert's recommended Speed) once per account (the saved `freeGift` flag) and toasts. With `COMMUNITY_GROUP_ID = 0` (the repo default) the button says **COMING SOON** and the window doesn't open by itself.

Why the like and favourite are only asked for:
- **Likes can't be verified.** There is no API for them, so a "reward for liking" would pay everyone who clicks.
- **Paying for an action can break Roblox's rules.** Roblox's Community Rules don't allow prizes or giveaways "in exchange for something". Favourites can't be checked safely server-side either: a client-side check can be faked.
- **Community rewards are the usual, accepted case.** Rewarding a group join is the common way games promote their community, and it is checked on the server.

So a player who never likes or favourites still gets the gift by joining the community, and nobody gets it for a like or favourite alone. This follows the Community Rules and developer-forum consensus, not an official Roblox ruling: if Roblox's policy changes, `Rewards.claimGift` is the one place to change.

**No free chest.** The free chest (and its claim, countdown, sound and asset slot) is gone. Saves keep their `chestAt` field (v4) so old and new saves round-trip, but nothing reads it.

**MOST MONEY/s board.** A tall studded cyan board (frame slot `MoneyBoard`) right of the gift box. Green "MOST MONEY/s" title, then the **top 10 of all servers**, each row with rank, name, a green "Money/s" tag and the value ("$54.8T").
- **Writing:** every 60 s each server writes its players' current $/s to the OrderedDataStore `MostMoneyPerSecond_v1`. A player who never earned isn't written, and one who drops to $0 is written once. Values are stored as log10(1 + $/s) in fixed point, because OrderedDataStore only takes whole numbers and income goes past 2^63. The order is kept and it reads back to about 6 digits.
- **Reading:** each server then reads the top 10 back (`GetSortedAsync`), with every call pcall'd. Players in the server show their live value.
- **Status line:** "All servers · updates every minute".
- **Fallbacks:** until the first update the board says "Loading...". If the DataStore can't be used (Studio without API access, an outage), it shows the last list it read. If there is none, it shows this server's players with "This server · updates every minute".

This is the base's only leaderboard: the old "⚡ FASTEST HERE" board (Speed, this server) was removed.

### Old saves (format v10)
v10 gives every seed a hidden gene (its flower, size and seed design) and keeps it in the seed bag's key (`zone:rarity[:Mutation]#gene`). v9 bag keys load unchanged; such a seed gets its gene when you pick it to plant (or draws its flower at planting, as before).
v9 added the plant **inventory** (`inv`) and a plant's own weight `variance` (kept when it goes to the inventory and is planted again); v8 saves load with an empty inventory, and their plants keep the variance from their planting time and id (`Config.varianceOf`). v8 saves each plant's flower (`variant`, drawn when it is planted); older plants keep the flower their id picks.
v7 made the Speed per step flat and removed the Speed levels, which shrank the Speed scale (the recommended Speeds went from 10K … 5B to 25K … 75M). A v1–v6 save's Speed is moved onto the new scale once, on load (`ProfileStore.migrateSpeed`): between two zones' old recommended Speeds (`ProfileStore.LEGACY_ZONE_REQ`) it lands the same share of the way (on a log scale) between their new ones, so everyone keeps every zone they had reached and nobody overtakes anybody. Below the Desert it scales linearly; past the Spirit Garden it keeps the last stretch's slope. Examples: 3K → 7.5K, 10K → 25K, 100K → ~146K, 1M → ~758K, 10M → ~3M, 50M → 7.5M, 100M → ~10.8M, 1B → ~35M, 5B → 75M, 50B → ~225M. Money, trails (same ids; their multipliers are now x1–x3), plot level and treadmill tier are kept as they are.
v6 replaced the fixed plant slots with free planting: each plant saves where it stands (`px`, `pz` in the plot's own space) and keeps its old slot number as its id (so its weight doesn't change). A v1–v5 plant is put on its old slot's spot moved onto the new dirt beds (`Planting.legacySpot`: the 8-column grid's left half on the left bed, its right half on the right bed, rows unchanged), so an old plot keeps its arrangement. When a player joins, `Planting.settle` moves any plant that is off a bed or too close to another (a bed moved in Studio, a corrupt spot) to a free spot.
v5 grew the treadmill from 3 tiers to 10: a v1–v4 save's treadmill becomes the v5 tier with the same multiplier (`ProfileStore.migrateTreadmillTier`, `ProfileStore.TIER_MULT_V5`): the free x2 → tier 1, the Robux x3 → tier 5 (x3), the Robux x5 → tier 8 (x5). The tiers later became fixed Speed-per-second levels; a save keeps its `treadmillTier` number as it is (nothing to migrate). v4 added the community rewards: v3 saves load with the Free Gift unclaimed, its window not shown yet and the free chest ready.
Saves from before the rework (v1/v2) are migrated on load, once (the next save is the current format):
- **Speed Gain tier → trail**, the nearest multiplier at or below it (the trails' multipliers of the time, `ProfileStore.LEGACY_TRAIL_MULT`), owned and equipped: x1 → Grey (x1.5), x2 → Green (x2), x3 → Purple (x3), x5 → Rainbow (x5). Nobody's multiplier goes down, except that x10 and x25 are above the best trail: those players get Rainbow (x5) **and the money they paid for the x10/x25 tiers back** ($250M, and $250M + $10B).
- **Slots → plot level** = slots − 5 + 1 (clamped to 1–26), so everyone keeps exactly their slots. The plot's income multiplier comes with the level.
- Plants, Index, seed bag and receipts are kept as they are (the treadmill tier is mapped as above). Removed items (potions, Sleep Dust) are dropped from the inventory.

### Progression: a flat Speed per step (v7)
Money can't buy Speed, so Speed comes from moving, your treadmill (a fixed Speed per second per level, +100/s up to +1.5K/s with money or Robux levels) and Robux Speed packs. Every step pays the same **flat** amount, times your trail's small multiplier; nothing grows with the Speed you already have, and there are no Speed levels:

```
Speed per step = BASE_SPEED_PER_STUD (1) × trail (x1 Grey … x3 Rainbow)      (Config.speedPerStud)
walking        = studs walked × Speed per step
treadmill      = level's fixed rate (+100 … +1.5K/s) × trail, per second    (SpeedLogic.treadmillGain)
WalkSpeed      = clamp(16 + 27 × log10(1 + Speed / 100), 16, 180)          (Config.walkSpeedFor)
```

What still grows as you play: your WalkSpeed (more studs per second, so more steps while running: 16 at the start, ~81 at the Desert, ~175 at the Spirit Garden, 180 from ~120M), your trail (x1 → x3) and your treadmill level (+100/s → +1.5K/s). The treadmill doesn't grow with WalkSpeed or Speed: only buying a level or a better trail raises it. The zones' recommended Speeds are on a much smaller scale than before v7 (v6 had a gain that compounded with Speed and reqs from 10K to 5B). The WalkSpeed curve was refitted so each zone's recommended Speed still runs within 10% of its old WalkSpeed (tested), which the guards are tuned for. Players see the gain: the Trail Shop shows **"+X/step"** and the treadmill its **"+X/s"** (`Treadmill.perSecond`, the same number the server pays).

**Tuning: a simulated free player** (`tests/progression_sim.luau`, asserted in `tests/progression.spec.luau`; `print(Sim.report())` prints these tables). The player is active and spends no Robux. They steal from the furthest zone their Speed allows and plant it (filling free slots, then replacing the plant worth least once grown). When the plot is full of good plants, they stand on their treadmill. Whenever affordable, they buy the cheapest of the next trail, the next plot level and the next treadmill level. Each steal trip costs the run there and back plus 10 s. The **AFK farmer** fills the plot once, then never runs the corridor again: only the treadmill, buying the same upgrades. Arrival times (cumulative play):

| Zone | Rec. Speed (was) | Target | Free player | This zone took | ±50% window (tested) | AFK farmer | Treadmill level 10 (R$) | Level 10 + 3.75M Speed packs (R$) |
|---|---|---|---|---|---|---|---|---|
| 🦂 Desert | 25K (10K) | 5 min | **5m 58s** | 6m | 2m 30s – 7m 30s | 5m 43s | 2m 10s | instant |
| 🦖 Jungle | 500K (500K) | 30 min | **32m** | 26m | 15 – 45 min | 1h 03m | 9m | instant |
| 🌋 Lava Fields | 2M (5M) | 1–1.5 h | **1h 11m** | 39m | 37 min – 1h 52m | 3h 49m | 24m | instant |
| ❄️ Snow Peaks | 7.5M (50M) | 3 h | **2h 44m** | 1h 33m | 1h 30m – 4h 30m | 9h 37m | 1h 01m | 29m |
| 👽 Deep Space | 25M (500M) | 6 h | **5h 46m** | 3h 01m | 3h – 9h | 24h 02m | 2h 30m | 1h 59m |
| ⛩️ Spirit Garden | 75M (5B) | 10–14 h | **11h 43m** | 5h 57m | 6h 15m – 18h 45m | 59h 44m | 5h 53m | 5h 21m |

The treadmill levels, and when the free player buys each:

| Level | Speed/s (× trail) | Price | Free player buys it |
|---|---|---|---|
| 1 | +100/s | free | start |
| 2 | +200/s | $1M | 11m 43s |
| 3 | +300/s | $10M | 27m 18s |
| 4 | +400/s | $100M | 48m 26s |
| 5 | +500/s | $1B | 1h 20m |
| 6 | +600/s | $10B | 2h 12m |
| 7 | +700/s | $100B | 3h 29m |
| 8 | +800/s | $1T | 6h 35m |
| 9 | +1K/s | $10T | 11h 05m |
| 10 | +1.5K/s | $100T | after the Spirit Garden |

Each zone takes clearly longer than the one before (tested: at least 1.5x) and the Spirit Garden comes at 10–14 h (tested; 11h 31m – 11h 55m across RNG seeds, with the x1 / x0.8 day/night rates and `INCOME_SCALE` = 1.25). All treadmill levels bought with Robux at the start (9 receipts, 411 R$) roughly halve the times (tested ≤ 70%), and Speed packs help on top (`Speed750K` + `Speed3M`, 636 R$, skip to past the Lava Fields). The AFK farmer is slower than the active player from the Jungle on and takes about 5x as long overall (tested: more than 2x): AFK farming is a way to keep progressing while away, not a better strategy than playing. Without the money treadmill levels the same free player would need ~73 h (tested ≥ 10% later): with a flat gain, the levels are the biggest lever a free player buys.

**Money stays a sink all game.** The money scale didn't change in v7: plant income is anchored to `Config.ZONE_CASH` (the old recommended Speeds, see Economy), so saved money and every money price kept their meaning. The trail prices are unchanged: Green–Golden ($5K / $75K / $1.5M / $30M) are bought in the first 37 minutes, Red ($20B) at ~2h 53m, around Snow, and Rainbow ($1T) at ~6h 04m, after Deep Space. Treadmill levels are bought from ~11 minutes (level 2, $1M) to ~6h 25m (level 8, $1T), and level 9 ($10T) just before the Spirit Garden. Plot levels are bought all along, the last at 7h 55m (level 22). At the Spirit Garden the player still has plot levels 23–26 and treadmill level 10 ahead.

## Build, test, run
You need Rojo 7, Luau (`luau-compile`) and [Lune](https://github.com/lune-org/lune) for the tests.

```sh
lune run tools/apply_assets.luau         # put new models from assets/ into map/World.rbxm (keeps hand edits)
lune run tools/build_map.luau --force    # REGENERATE map/World.rbxm from code (discards hand edits; refuses without --force)
rojo build -o StealASeed.rbxlx          # build a place file (includes the baked map)
rojo serve                              # or live-sync into Studio (Rojo plugin)
luau-compile --null src/**/*.luau       # syntax/compile check
lune run tests/run.luau                 # mocked server tests (run from this folder; Lune 0.10+)
lune run tools/upload_icons.luau --dry-run   # list the UI icons the uploader would send (no key needed)
```
The tests also build the whole map with Lune's Roblox instances. Every property WorldBuilder/ZoneThemes set is checked against the Roblox reflection database, the plot/nest layout contract and the part budget are verified, and the per-zone part counts are printed.

Optional type check with Roblox definitions ([luau-lsp](https://github.com/JohnnyMorganz/luau-lsp)):
```sh
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json src
```

**Studio settings the place file can't carry:**
- Game Settings → Security → **Enable Studio Access to API Services**. Without it saving is off, and the game tells you so in a toast.
- Game Settings → Places → **Max Players = 5**, one plot each. A 6th player is kicked with a "server full" message.
- Gamepasses are stubs. Put real ids in `Config.GAMEPASSES` to turn them on.
- **The Free Gift needs the community's id.** Create the game's Roblox community (group), then set `Config.COMMUNITY_GROUP_ID` to the number in its URL (`roblox.com/communities/<id>/...`) and `Config.COMMUNITY_NAME` to its name. Link the community on the experience page so players can join it from there. While the id is `0`, the Free Gift says "coming soon".
- Everything sold for Robux except the 2 gamepasses is a developer-product stub. Create the **29 developer products** below on the Creator Dashboard (your experience → Monetization → Developer Products) and paste each id into its `Config.DEVELOPER_PRODUCTS` key. The price comes from the Dashboard (the placeholders are only shown until then). The place must be published for `PromptProductPurchase`/`GetProductInfo` to work.

  | ✅ | `Config.DEVELOPER_PRODUCTS` key | Dashboard name | Price (placeholder) | Grants |
  |---|---|---|---|---|
  | ☐ | `PackSpace` | Starpetal Pack | 2,000 R$ | 1 Deep Space (zone 6) seed |
  | ☐ | `PackSpirit` | Lotus Wyrm Pack | 3,000 R$ | 1 Spirit Garden (zone 7) seed |
  | ☐ | `Speed25K` | +25K Speed | 9 R$ | +25,000 Speed |
  | ☐ | `Speed150K` | +150K Speed | 36 R$ | +150,000 Speed |
  | ☐ | `Speed250K` | +250K Speed | 64 R$ | +250,000 Speed |
  | ☐ | `Speed750K` | +750K Speed | 76 R$ | +750,000 Speed |
  | ☐ | `Speed3M` | +3M Speed | 560 R$ | +3,000,000 Speed |
  | ☐ | `Speed10M` | +10M Speed | 1,200 R$ | +10,000,000 Speed |
  | ☐ | `Speed25M` | +25M Speed | 1,600 R$ | +25,000,000 Speed |
  | ☐ | `Speed50M` | +50M Speed | 2,400 R$ | +50,000,000 Speed |
  | ☐ | `Money24K` | Pocket Cash | 40 R$ | max($24K, 10 min of income) |
  | ☐ | `Money200K` | Cash Bag | 80 R$ | max($200K, 30 min of income) |
  | ☐ | `Money800K` | Cash Stack | 200 R$ | max($800K, 60 min of income) |
  | ☐ | `Money4M` | Cash Crate | 400 R$ | max($4M, 180 min of income) |
  | ☐ | `Money8M` | Cash Vault | 640 R$ | max($8M, 360 min of income) |
  | ☐ | `TreadmillT1` | Treadmill Upgrade (Lv 2-4) | 19 R$ | +1 treadmill level (sold at levels 1-3) |
  | ☐ | `TreadmillT2` | Treadmill Upgrade (Lv 5-7) | 39 R$ | +1 treadmill level (levels 4-6) |
  | ☐ | `TreadmillT3` | Treadmill Upgrade (Lv 8-10) | 79 R$ | +1 treadmill level (levels 7-9) |
  | ☐ | `TrailGreen` | Green Trail | 16 R$ | owns + equips the Green trail (x1.25) |
  | ☐ | `TrailBlue` | Blue Trail | 24 R$ | Blue trail (x1.5) |
  | ☐ | `TrailPurple` | Purple Trail | 40 R$ | Purple trail (x1.75) |
  | ☐ | `TrailGolden` | Golden Trail | 64 R$ | Golden trail (x2) |
  | ☐ | `TrailRed` | Red Trail | 100 R$ | Red trail (x2.5) |
  | ☐ | `TrailRainbow` | Rainbow Trail | 180 R$ | Rainbow trail (x3) |
  | ☐ | `PlotUpgradeT1` | Plot Upgrade (Lv 2-5) | 25 R$ | +1 plot level (sold at levels 1-4) |
  | ☐ | `PlotUpgradeT2` | Plot Upgrade (Lv 6-9) | 49 R$ | +1 plot level (levels 5-8) |
  | ☐ | `PlotUpgradeT3` | Plot Upgrade (Lv 10-13) | 99 R$ | +1 plot level (levels 9-12) |
  | ☐ | `PlotUpgradeT4` | Plot Upgrade (Lv 14-17) | 199 R$ | +1 plot level (levels 13-16) |
  | ☐ | `PlotUpgradeT5` | Plot Upgrade (Lv 18-21) | 399 R$ | +1 plot level (levels 17-20) |
  | ☐ | `PlotUpgradeT6` | Plot Upgrade (Lv 22-26) | 799 R$ | +1 plot level (levels 21-25) |

  Gamepasses (`Config.GAMEPASSES`): ☐ `DoubleMoney` (2x Money), ☐ `ExtraSlots` (+10 Plant Slots).

### The map: hand-editable, adopted at server start
`map/World.rbxm` is the **source of truth** for the map. Rojo places it at `Workspace.World`, so the whole map shows in Studio edit mode, and at server start `WorldBuilder.load()` **adopts** it as it is instead of rebuilding it. Edits made in Studio and saved back to the file (right-click **World** → Save to File → overwrite `map/World.rbxm`) stay forever: moved, rotated, deleted or added pieces, other people's models.

- **Gameplay pieces are found by attribute, not by path.** Every piece gameplay needs has a `Role` attribute plus `PlotIndex` or `ZoneIndex`: `Plot`, `PlotFloor`, `PlantBed` (two per plot, `BedIndex` 1 and 2; more added by hand with `BedIndex` 3, 4, ... are used too), `TreadmillBelt`, `TreadmillSign`, `PlotSign`, `UpgradeBoard`, and per zone `Nest` and `NestCore`. The plot origins, spawn points, seed pods, nest centres and guard homes are tagged Attachments (`Origin` (Role `PlotOrigin`: where plants are measured from) and `Spawn` on the plot floor, `Center`, `Pod1..Pod4` and `GuardHome` on the NestCore). `WorldBuilder.adopt()` rebuilds `PlotInfo`/`NestInfo` from them, so the pieces can be moved, rotated, reparented or re-modelled and gameplay follows. For example, the belt check uses the belt's current CFrame and size.
- **Validation and fallback.** Every plot `1..MAX_PLAYERS` and every zone must have all its roles. If one is missing, the server warns which plot or zone and which role, and regenerates the map from code for that session (`WorldBuilder.build()`), so the game never breaks. Duplicated roles are warned about, and the first one wins.
- **Zone boundaries come from `Config`**, not from the map: `zoneAtX`, the guards' chase lines and the corridor's ends don't change if a zone's floor or walls are moved. Only the look does.
- **Regenerating from code is explicit.** `lune run tools/build_map.luau` refuses to overwrite an existing `map/World.rbxm`. `--force` regenerates it from WorldBuilder/ZoneThemes/Props and **discards every hand edit in it** (git keeps the old file). The map tests are contract tests: the committed file loads, validates and gives usable plot and nest info (slot counts, belt check, pods). They don't compare it with the code, because hand edits are expected, with one exception: every Speed plank's text must match `Format.short(zone.req)`, so changing a zone's recommended Speed means regenerating the map (the client also rewrites the plank text at runtime).
- Guardians and plant-creatures are spawned at runtime, so they only appear in Play.

### UI icons (`icons/`)
The HUD and the world signs use the 21 PNG icons in `icons/` (256x256, "Free Icon Pack" by @gvesster). Roblox can only show **uploaded** images (`rbxassetid://<id>`), so each icon has an asset id in **`icons/ids.json`**. Rojo turns that file into the ModuleScript `ReplicatedStorage.Shared.IconIds` (Rojo 7 makes any plain `.json` file a ModuleScript returning its data; mapped in `default.project.json`), and `Config.ICONS` reads it. Updating ids never means editing Lua.

- **`0` = not uploaded yet: the emoji stays.** Every icon stands in for an emoji (or `R$`) in some text (`Icons.TOKENS`). While its id is 0 the text is shown exactly as before, so with every id at 0 (the repo default) the game looks the same as without icons.
- **One helper.** `Icons.image(key)` gives `"rbxassetid://<id>"` or nil. `Icons.set(label, keys, text, size?, textSize?)` writes every icon label: with no uploaded icon it is just `label.Text = text`; with one it empties the label and lays out an `IconRow` inside it: square `ImageLabel`s (`ScaleType.Fit`, `size` x the label height) and the text pieces, styled like the label (font, colour, stroke). The emoji can be in front (`🛒 Shop`), inline (`Buy · R$ 2,000` → Buy · [R$] 2,000), at both ends (`⚡ FASTEST HERE ⚡`), or above the text (`🏏\nBat`). One key whose emoji isn't in the text puts the icon in front (`$1.2K` → [Money] $1.2K, `-- SEED PACKS --`); a list of keys only replaces emoji that are there (so `{ "Lock" }` on "✅ Rec. Speed" adds nothing).
- **Sizes per context** (`ICON` in the HUD, x the label height): shop card titles big (1), HUD buttons, panels and section titles medium (0.85), R$ price buttons and inline lines small (0.7).
- **Where:** Shop/Index buttons, stalls and modal titles; the 🏃 stall and Trail Shop title; the Speed and money icons (bottom left); Speed/Money/Treadmill/pass cards; PLOT UPGRADE (card, gate board); every R$ button (Robux icon before the number); 🎁 gift buttons; 🌱/🪴 tabs and side titles; the hotbar Bat; 🔒 on locked zones; the ✖ close button; the ✨ Index count; the 🏠 plot and 🏃 treadmill signs. (Emoji inside sentences are gone from the UI: see "UI text is words, not emoji".)
- **World signs** are set at runtime, so `map/World.rbxm` is untouched and keeps the emoji: `WorldBuilder.applyIcons` (end of `WorldBuilder.load`) gives the icon to the sign labels whose text is exactly one of `WorldBuilder.SIGN_ICONS` (the 3 stalls, each plot's plot sign and treadmill sign; hand-edited texts are left alone), and `PlotService` writes the plot and treadmill signs and the Upgrade boards (PlotUpgrade icon on the red button, Robux icon on the purple one, `WorldBuilder.setUpgradeBoard`) through `Icons.set`.

**Uploading** (Portuguese step by step: [icons/COMO_SUBIR_ICONES.md](icons/COMO_SUBIR_ICONES.md)):

```powershell
$env:ROBLOX_API_KEY = "<Open Cloud key with Assets read + write>"   # this terminal only, never in a file
$env:ROBLOX_USER_ID = "<your user id>"                              # or $env:ROBLOX_GROUP_ID for a group game
lune run tools/upload_icons.luau --dry-run   # what would be sent (no key, no network)
lune run tools/upload_icons.luau             # upload every icon whose id is still 0, write icons/ids.json
```
`tools/upload_icons.luau` (logic in `tools/icon_uploader.luau`) POSTs each PNG to the Open Cloud Assets API (`https://apis.roblox.com/assets/v1/assets`, multipart `request` JSON + `fileContent`, header `x-api-key`), polls `assets/v1/operations/<id>` until it is done and writes the id to `icons/ids.json` after each icon (a re-run skips icons that already have an id; `--force` and `--only Shop,Index` re-upload). It also keeps `icons/uploads.json` (asset ids and types, no secrets).

- **Image, not Decal.** The [Assets API docs](https://create.roblox.com/docs/cloud/guides/usage-assets) list *Decal* and *Image* as separate upload types (same formats). An Image asset's id is what `ImageLabel.Image` takes, so the uploader uses `"assetType": "Image"`. A **Decal** id is a different asset that wraps the image: put in an ImageLabel it shows nothing in game (Studio's property box silently converts it when you paste, scripts don't). With `--type Decal` (or if Roblox answers with a decal) the uploader resolves the real image id: Open Cloud asset delivery (`GET apis.roblox.com/asset-delivery-api/v1/assetId/<decalId>` → `location`), downloads the decal and reads its `Texture` id. If that fails (e.g. the key lacks permission for asset delivery), ids.json keeps 0, the decal id stays in `icons/uploads.json`, and the guide explains how to get the image id in Studio.
- **The key** comes only from `ROBLOX_API_KEY`. It is never printed or written, and only sent to `apis.roblox.com`.
- **Manual way:** Studio → View → Asset Manager → Bulk Import the PNGs, right-click each → Copy Asset ID, paste into `icons/ids.json` under its file name.
- Uploaded images go through moderation; one that is still pending or rejected shows blank until approved.

### Drop-in models (`assets/`)
`assets/` (Rojo → `ServerStorage.Assets`) holds models made in Blender and saved from Studio (`<Slot>.rbxm`: a Model, or a Folder of variant Models). **For the model maker: [assets/COMO_ADICIONAR_MODELOS.md](assets/COMO_ADICIONAR_MODELOS.md)** (Portuguese, step by step, with the full slot table).

- Every repeated or distinctive map piece is built as a group Model tagged `AssetSlot` (its slot name) and `FitSize` (the space it uses). The groups are trees, bushes, rocks, flowers, lamps, fence posts and sections, each zone's props, the treadmill frame, the upgrade-sign stand and the shop stalls. `Assets.replace` swaps a group for the slot's model at the group's **current pivot**, so hand moves are kept. The model is scaled uniformly (`Model:ScaleTo`) to fit `FitSize` unless it has `KeepScale = true`, its bottom centre is the pivot, and `Yaw` (degrees) turns it. It is anchored, non-colliding for decor (fences and stalls keep their saved collision), stripped of scripts, and gets the built-in piece's lights and particles if it has none. Variants are picked from a stable hash of the position. File names match slots case- and accent-insensitively, with Portuguese aliases (`Arvores` → `Tree`, `Arbustos` → `Bush`, ...; `Assets.ALIASES`).
- **When they apply:** the server replaces every group still built from code at start (`WorldBuilder.load` → `Assets.refresh`). `lune run tools/apply_assets.luau` does the same in `map/World.rbxm`, keeping hand edits, so they show in edit mode; `--all` also re-places groups that already hold an older export. `build_map --force` uses them too.
- **Runtime-spawned models:** `Creature_<Seed>` (e.g. `Creature_LotusWyrm`) replaces a plant-creature, ahead of `Config.CREATURE_ASSETS`, and still gets rarity/mutation flair. `Guard_<Name>` (e.g. `Guard_GiantTurtle`) becomes a guardian's body, welded to the invisible root that `Humanoid:MoveTo` drives. The seven slots hold the owner's rigged pets (see "The zone bosses" below); a model without a `BossRig` attribute is fitted like any other and isn't animated.
- A broken model (no parts, empty folder, an error while fitting) is skipped with one `[Assets]` warning, and the built-in piece stays. Unknown file names are warned about, and `tests/assets.spec.luau` fails on them.
- Owner workflow when new models arrive: `lune run tools/apply_assets.luau`, then `rojo build -o StealASeed.rbxlx`, `lune run tests/run.luau`, commit `assets/` and `map/World.rbxm`. Meshes uploaded by the 3D Importer belong to the uploader's account: the experience's owner needs permission to use them in the published game.

### Manual acceptance test (Studio → Test → Local Server, 2 players)
1. Both players spawn on the grass path of their own plot: a chunky studded wooden fence, two pinkish-brown studded dirt beds left and right, a green path down the middle, an orange tile at the opening. The sign on the front fence beside the opening shows "🏠 Name's Plot". The treadmill and its board stand outside, in front of the plot, beside the entrance path; the plot's Upgrade board is on the other side of the path.
2. Each player walks into the corridor, steals a Meadow seed (E), gets chased and gets home. On your plot a see-through disc follows the mouse over your dirt: green where it fits, red on the edge, next to another plant or out of reach (and the hint says why). Click: the plant grows there, standing straight on the dirt (no disc or ring under it), and a `+$` popup over it every second shows exactly the $/s of its info. Hover a plant with the mouse: its name and $/s appear over it (only that one); move off: they hide. In the device emulator, tap a plant: its info shows for 3 s. The other player's dirt shows no preview (the server refuses it too). In the device emulator (phone), tap your dirt to plant. Fill your slots: the next spot says your plot is full.
3. Stand on your treadmill: you run in place without being pushed, and Speed climbs even when AFK. A grey trail streams behind you (the other player sees it too). The small text over your treadmill and the popups over you say "+100/s" / "+100" with the Grey trail, and it stays exactly that however much Speed you have (it only changes with a new level or a better trail: x1.5 with Blue → "+150/s"). The treadmill's board shows "Level 1 > Level 2" and "+100/s > +200/s". No black prompt popups show on its board; only you can click/tap its red $ and purple R$ buttons (or press E / F). Step on anywhere along the belt: you are snapped to its centre. Step onto the **other** player's treadmill: you can't (an invisible wall), and it pays nothing. Under $1M the board's $ button is red; at $1M it turns green; click it (or press E): the board says "Level 2 > Level 3", "+200/s > +300/s", the $ button goes red again (next price $10M) and Speed climbs at +200/s; F with stub ids says "coming soon". The plot's Upgrade board's $ button does the same (green from $500 at level 1). The other player sees your boards' $ buttons red whatever your money.
4. Earn $5K and buy the Green trail in the 🏃 Trail Shop: it turns green at once (and stays green after a respawn), and Speed climbs faster. Equip Grey again from its card. Walk to the Upgrade board at your plot's entrance: no prompt popups; only you can click/tap its buttons (or press E money, F Robux); click the red button to buy level 2: a 6th slot opens (the Plants menu says 6) and the board shows "Level 2 > Level 3" and the next prices. Press F: with stub ids "coming soon"; with real ids the Robux prompt, and the receipt adds exactly one level (the purple button shows the Dashboard price).
5. Get Speed (treadmill, or a Speed pack once its id is set), then try the Desert at about 5K Speed and at 25K Speed. At 5K: caught, seed back at the nest, knocked back. At 25K: the guard shows ❗ for about a third of a second, then chases exactly as fast as you; run straight home and it never closes the gap.
6. Both players leave, then rejoin: money, Speed, plants, Index, owned/equipped trail and plot level are intact (API access must be on).
7. Shop → -- SEED PACKS --: two cards, Starpetal and Lotus Wyrm. With stub ids, clicking either says "coming soon" and no money is charged. With real ids, buy a Starpetal Pack at 0 Speed: Studio shows a test purchase dialog (no real Robux) and the button shows the Dashboard price. The reel spins and lands, and a "Rare Seed" (or whatever rarity) shows up in the Plants panel → Inventory. Press Plant, then click your dirt. Rejoin: the bag is intact.
8. Shop → every other section (Speed, Money, Treadmill) and the R$ buttons on trail cards: with stub ids, "coming soon" and nothing charged; the 🎁 gift button says "Gifting is coming soon!". With real ids: a Speed pack adds Speed, a Money card pays exactly the amount it showed, a treadmill R$ button adds exactly one tier (the card and the sign move to the next one). No R$ item ever costs in-game money.
9. HUD: bottom left shows only the Speed icon with a yellow **+** and the Speed in pink, the money icon and the money in green: no level bar, no +10K / +100K / +1M buttons (those packs are in the Shop). **+** opens the Shop scrolled to -- SPEED --. Above them, only **Shop** and **Index** and the Slow Mode switch (Trails is the TRAIL SHOP stall; the Free Gift is the gift box by the spawn). A Speed pack just adds its Speed: no "LEVEL N!" pop-up. Open the Shop: bright cards with light rays behind big icons (SPEED blue with "+150K" in green, MONEY green, PLOT UPGRADE orange, TREADMILL red, PASSES purple), the magenta gift button on the left and a bright green R$ button (slightly greyed while the product has no id; clicking says "coming soon"), no "SOON" tags or filler lines. Try a phone in the device emulator: nothing overlaps.
10. Shop windows: Trails opens the purple Trail Shop. Scroll it right with the wheel, the bottom scrollbar, a drag and the `>` arrow, until the Rainbow card shows; the arrows hide at each end. Money ticking up doesn't reset the scroll or swallow a click. Shop (green) scrolls down to -- PASSES -- with nothing cut off; the Speed "+" still lands on -- SPEED --. Index (blue) lists every zone. On a phone (device emulator), each window fits on screen and scrolls by touch.
11. SELL stall: the plaza's 4th stall has the red-and-white awning, the green circle and the red SELL text. Press E: the red-orange Sell window lists your plants. Click Sell on one: it says "Sure? Sell"; click again: the plant disappears from your plot, its soil is free, "+$X" pops up over the stall with the cash sound, and income drops. Try "Sell all Common": a confirm bar asks first; Cancel keeps them, "Yes, sell!" sells every non-mutated Common. Walk away from the stall with the window open and click Sell: "Walk up to the SELL stall" and nothing is sold. Plants have no R / Remove prompt: open the Plants panel, click Remove on a plant ("Sure?" for 2 s), click again: it is gone and 30 s of its income is refunded.
12. Community rewards. With `COMMUNITY_GROUP_ID = 0`, the pink FREE GIFT box by the spawn, where the free chest used to be (E: "Open"; there is no chest any more) opens the cyan "Free Gift!" window with a grey COMING SOON button. With a real id and a new account, the window opens by itself about 20 s after joining (once: rejoin and it doesn't). ⭐ Favorite opens Roblox's favourite prompt (published place). CLAIM! while not in the community says to join first and grants nothing. Join the community on the game page, wait a minute, press CLAIM!: +25,000 Speed, a toast, CLAIMED! in grey, and the box's prompt says "View". Rejoin: still CLAIMED!. Walk to the FREE chest by the corridor mouth and hold E: +$ (at least $1K), "Ready in 14:59" appears under FREE!, and E again says when it's ready. Rejoin: the countdown continues. The MOST MONEY/s board next to it shows "Loading...", then within a minute the top earners (with API access: "All servers"; without: "This server").

## Rules the code enforces
- **Server-authoritative.** Money, Speed, pickup, carry, planting and purchases all live on the server. The client only draws the HUD and VFX and runs Slow Mode. Every prompt and remote re-checks distance, ownership and state, and remotes are rate-limited.
- **Speed stat vs WalkSpeed.** `WalkSpeed = clamp(16 + 27*log10(1 + Speed/100), 16, 180)`. Zones compare the *stat*.
- **Speed from moving** (`SpeedService` + `SpeedLogic`). Every 0.25 s the server measures horizontal HumanoidRootPart movement and grants `distance × Config.speedPerStud(trail)` (the flat `BASE_SPEED_PER_STUD` × the equipped trail, see Progression), capped per tick.
- **Movement sanity check.** A tick that moves more than `WalkSpeed × dt × 1.5 + 2` earns nothing. Sustained over-speed that drains a one-second movement budget, or any teleport-sized jump, is rubber-banded to the last valid position. Server-side moves (spawn, knockback) reset the tracker.
- **Treadmill.** The server checks whether the root part is inside **your own plot's** belt bounds and grants the treadmill level's fixed rate × the trail for the tick (`SpeedLogic.treadmillGain`: +100/s at level 1, up to +1.5K/s at level 10; not WalkSpeed, not Speed). The belt does not move you: you just stand on it (AFK works) and the client loops your run animation in place, only on your own belt (`Shared/Treadmill.shouldRun`; the client knows its plot from StatsUpdate `plot` and the plot model's OwnerUserId). Someone else's belt pays nothing. There is no client remote.
- **Guards** (`GuardService` + `GuardBrain`). A guard wakes `Config.wakeDelay(k)` after a seed is taken (a 28-stud head start at the recommended Speed plus its zone's `wakeDelay` slack: 0.26–0.35 s, the Meadow's 2.25 s, showing ❗ meanwhile) and chases at `walkSpeedFor(zone.req) × GUARD_SPEED_FACTOR` (1.0), exactly a player's WalkSpeed at the recommended Speed. A server loop calls `Humanoid:MoveTo` along the corridor at 10 Hz, with no pathfinding. A catch is horizontal distance < 6 studs from the path the guard walked since its last tick, never `Touched`. A Spirit Garden guard covers 17 studs per tick, so checking only its current position could step right over a thief. The seed goes back to its pod, and the player is knocked 30 studs away and frozen for 1 s. The chase ends when the thief reaches the base, after a catch, or after 45 s, and then the guard walks home and sleeps.
- **Carry.** One seed at a time, a server-made part welded to your back. Dying or leaving returns it to its pod.
- **Rarities** (`Config.rarityWeights`). A pod rolls its rarity when it regrows. Common..Epic use `spawn × tilt^(i-1)` with `tilt = luck × (1 + 0.08·(zone-1))`, so deeper zones and night (`NIGHT_LUCK` = 2) give more Rares and Epics. **Legendary is a trophy**: a fixed chance per zone (`LEGENDARY_CHANCE`, × luck at night) that gets *rarer* down the corridor: 1% → 0.6% by day in zones 1–5, then **1 in 2,000** in Deep Space and **1 in 2,500** in the Spirit Garden (at most 0.1% at night). Epic pays ×10 and Legendary ×15 (Epic went from ×6 to ×10 so late-game income stays close to what it was with common Legendaries: the simulated free player ends about 6% lower, and reaches every zone within a few minutes of before). Planting a Legendary stolen in zones 6–7, or rolling one from a pack, announces it to the whole server (`Config.announcesLegendary`, `Net.announce`: "🌟 Alex got a LEGENDARY Nebula Rose!", or "...a LEGENDARY Seed!" from a pack, whose flower is still a surprise). `lune run tests/rarity_table.luau` prints the full odds table.
- **Growth.** Only `plantedAt` is saved. `weight = sprout × variance × (1 + 4·ease(age/20 min))` grows to 5× and stops. `income = seedIncome(zone) × rarity × mutation × sqrt(weight/sprout)`. A single payout loop evaluates the formula every second (`PAYOUT_INTERVAL` = 1), so each plant's `+$X` popup is exactly the $/s on its billboard; the Plants panel view is pushed every 3rd pass. There is no per-plant tick.
- **Day and night plants.** Every zone is either ☀️ day (Meadow, Desert, Lava, Spirit) or 🌙 night (Jungle, Snow, Space), set by `Zone.active`. Its plants pay `ACTIVE_TIME_MULT` (1×) during their phase and `OFF_TIME_MULT` (0.8×) during the other one (`Config.timeMult`, from the shared `dayPhase` clock). The payout loop applies it; while a plant is penalised its billboard, Plants card and Sell card add "Night x0.8" / "Day x0.8" in a muted grey (`Config.OFF_TIME_COLOR`), and nothing extra at x1. `plantIncome`/`incomeOf` stay the plain base, and the 30 s removal refund and the SELL stall's price use the base too. Offline income uses the cycle average: 300 s day and 150 s night give ×14/15 for day plants and ×13/15 for night plants.
- **Economy** is formulas in `Config` (see "Economy" above). `seedIncome(k) = ZONE_CASH[k+1] / (ECONOMY_SLOTS × 300 s) × INCOME_SCALE` with `ECONOMY_SLOTS = 10` and `INCOME_SCALE = 1.25` (it makes up for the x1 / x0.8 day/night rates): a 10-plant plot of zone-k Commons earns 1.25× zone k+1's `ZONE_CASH` in about 5 minutes. `ZONE_CASH` = 0, 10K, 500K, 5M, 50M, 500M, 5B: the recommended Speeds from before v7, kept so the money scale didn't move when the Speed scale shrank. Money buys trails, plot levels and treadmill tiers (`Config.priceOf`); plot levels cost `500 × 3.1^(L−2)` and multiply income by `1 + 0.06 × (L−1)`.
- **Data** (`ProfileStore`, format v10; v10 keeps each bag seed's gene, v9 adds the plant inventory, v8 each plant's flower, v7 moves older saves' Speed onto the flat-gain scale, v6 saves each plant's spot instead of a fixed slot, v5 maps the old 3 treadmill tiers onto the 10 new ones, v4 added `freeGift`, `giftShown` and `chestAt`, see "Old saves" and "Community rewards"). `UpdateAsync` with retries and exponential backoff, autosave every 90 s, `BindToClose`. If a load fails, that session never saves, so it can't overwrite real data with defaults. Saved fields: money, Speed, owned trails + the equipped one, treadmill tier, plot level, plants (id, zone, rarity, mutation, plantedAt, its spot x/z on the plot, its flower and variance), the inventory (up to 50 plants: zone, rarity, mutation, flower, age, variance), Index, items (none are sold right now; only ids in `Config.START_ITEMS` load), the seed bag, the last 100 Robux receipt ids and `lastSeen`. v1 saves load with an empty bag and no receipts; v1/v2 saves get their Speed Gain tier turned into a trail and their slots into a plot level (see "Old saves" above). Potions and Sleep Dust were removed: potion timers and both items in old saves are dropped on load. Offline income is capped at 1 h.
- **Art.** The map is generated from primitives by `WorldBuilder` (base, plots), `ZoneThemes` (the 7 zones) and the `Props` kit, then hand-edited in `map/World.rbxm`, and any piece can be swapped for a model from `assets/` (see "Drop-in models"). Only floors and walls collide. All props are anchored and non-colliding (no Touched, no raycasts), so they never block runners, guards or the camera. The base is kept plain so the plants are the show (like a simulator base): a studded lawn in big checker tiles of two close greens, a sand walkway and plot paths, plain tan checker walls with a grass top, and chunky studded wooden fences (square plum-brown posts studded on every face, two thick rails) around each plot. Inside a plot: two pinkish-brown studded dirt beds with a light checker, left and right, and a lighter green grass path down the middle from the opening; no trees, bushes, flowers, lamps or rocks outside the corridor (tested). The base is compact: neighbouring plots touch and share one fence line (`PLOT_SPACING_X` = `PLOT_SIZE`; a plot builds its +X side only in the front column or beside the shop plaza, and a corner post is never built twice), the front plots end 24 studs before the corridor mouth (room for the free gift and the MOST MONEY/s board). The shop plaza takes the -Z side of the front column, by the corridor mouth (`Config.PLAZA_SPOT`), and the plots fill the other spots column by column, plot 1 nearest the mouth (`Config.plotSpot`), and each plot has one plain 16-stud opening toward the walkway with an orange-tan tile and the owner's sign on the fence beside it (no gate). The plots sit 24 studs from the walkway (`PLOT_OFFSET_Z` = 84): the treadmill stands in that strip, in front of its plot. Tests check that no two fence rails overlap, no two posts share a spot, no post pokes into a treadmill, board, sign or stall, every plot is fenced all round, and each treadmill (character-sized: belt about 4.5 × 9) stands in front of its plot, within its width, off the entrance path and clear of the walkway. The base area is about 1.5k parts (tested below 1.6k), the corridor about 3.6k and the whole map about 5.1k (tested below 6k/8k). The corridor's zones (`Zones/<Zone>`, on the shared `Zones/Kit`) each have 3-6 big set pieces and small details along the walls, every one built of many offset studded blocks at different heights (the same studded plastic as the floor and walls; owner playtest): the Meadow's lily pond, picket-fenced flower bed, mushrooms and round block trees; the Desert's stepped pyramid with its temple, ruins, palm oasis, giant skull, cacti, dunes and tumbleweeds; the Jungle's waterfall cliff, giant stone head and altar, giant trees with vines, bamboo and leaf plants; the Lava Fields' volcano altar (the owner's reference: lava zig-zagging down its steps, real fire on top), lava fall, lava terraces, vents, basalt columns, dead trees and ragged lava pools; the Snow Peaks' ice cliffs (one with a frozen waterfall), igloo, frozen pond, snowmen, pines and glowing crystals; Deep Space's UFO beaming up a cow, glowing craters, rocket, crystals, asteroids and blocky planets; the Spirit Garden's cherry trees, shrines, stone lanterns, koi pond, bamboo and waterfalls, and a pale back wall with a big waterfall and glowing lanterns so the end of the corridor shows from the spawn. `tests/zones.spec` checks every set piece stands clear of its nest, everything is studded, nothing z-fights (every face of the corridor, at any height) and each zone's parts, emitters and lights stay in budget. Lighting (`Shared/LightingLook`): two fixed looks, nothing moves across the sky: a clear, natural day that doesn't glare (Brightness 2, exposure −0.1, a plain ambient, faint bloom; the sun stands still at ClockTime 14), the default blue sky with clouds, crisp ShadowMap shadows, very thin air with no haze (Atmosphere density 0.05, so the whole corridor is visible from spawn; streaming is off) and lightly saturated colour (ColorCorrection saturation +0.12, contrast +0.04, no extra brightness), and the night is a clear, readable blue with the moon standing still at ClockTime 0 (bright blue ambient, stars, a little more bloom on the neon). At each day/night flip every screen fades to black for about a second (`Client/DayNight`, from the shared server clock), the look switches while black, and it fades back in. `default.project.json` ships the day look (a test keeps the two in step), and the client adds a gentle per-zone tint. Neon only where something glows (tested): lava, glowing crystals and goo, lamps; the only glow on the floor is lava (and the craters' goo) pooling in ragged blobs, never a strip, line or ring. Zones meet at a soft studded strip a shade lighter than the new floor (`ZoneEdge`); each zone's walls are a darker shade of its ground, unlike any other zone's, under a cap in its bright accent colour (tested). Ponds follow the owner's reference and are sunken: the floor is cut around the water, which sits 0.4 studs below the grass on a solid bed (lily pads float on it): flat studded water in a checker of two blues in a soft, slightly irregular shape, round lily pads with a wedge cut out (one with a pink and yellow flower) and a clump of tall reeds.

### Soft gates: how soft they are
A guard runs exactly as fast as a player at the zone's recommended Speed (`GUARD_SPEED_FACTOR = 1`). That player gets home on the head start alone. The seed pods lie right by the sleeping boss (a loose cluster a few studs off its right flank, owner's reference `docs/references/11-pods-by-the-boss.png`), so the head start is the guard's wake-up, its ❗: `Config.wakeDelay(k)` = `GUARD_HEAD_START / guardChaseSpeed(k)` + the zone's `wakeDelay`. `GUARD_HEAD_START` = **28 studs**, the distance the pods used to lie ahead of the boss, the same in every zone: a recommended-Speed thief runs 28 studs while the guard wakes up (0.35 s in the Desert, 0.26 s in the Spirit Garden, 1.75 s in the Meadow), so the balance is the one the old distance gave. The zone's `wakeDelay` adds slack on top. That head start is also the *slack*: how long a player at exactly the recommended Speed can hesitate after the steal (reaction time, lag) and still get home. A slower player keeps the same head start but loses ground every second. WalkSpeed is logarithmic in Speed, so a few WalkSpeed points are a big share of the Speed number:

| Zone | Recommended | Wakes after (head start + `wakeDelay`) | Escapes from Speed | WalkSpeed (player vs guard) | Slack |
|---|---|---|---|---|---|
| Desert | 25K | 0.35 s (0.35 + 0) | ~12K (49%) | 72.5 vs 80.8 | 0.6 s |
| Jungle | 500K | 0.34 s (0.24 + 0.1) | ~250K (50%) | 107.6 vs 115.9 | 0.5 s |
| Lava | 2M | 0.31 s (0.21 + 0.1) | ~1.0M (52%) | 124.3 vs 132.1 | 0.5 s |
| Snow | 7.5M | 0.29 s (0.19 + 0.1) | ~4.9M (65%) | 142.6 vs 147.6 | 0.4 s |
| Deep Space | 25M | 0.27 s (0.17 + 0.1) | ~16M (62%) | 156.2 vs 161.7 | 0.4 s |
| Spirit Garden | 75M | 0.26 s (0.16 + 0.1) | ~51M (68%) | 170.1 vs 174.6 | 0.4 s |

Why the wake-up and not the other knobs: a slower guard (`GUARD_SPEED_FACTOR` < 1) would let a thief below the sign pull away on long runs and break "you need the recommended Speed", and a ramp-up acceleration is a head start too, just harder to read. The wake-up already exists (the ❗ the boss shows) and in studs it is the exact head start that was lost. Each `wakeDelay` trades slack against the threshold: every 0.1 s adds 0.1 s of slack and lowers the threshold, and the shorter the run home, the less a slower thief loses on the way. With the short zones (runs home of 264 studs from the Desert nest to 2,240 from the Spirit Garden's) the thresholds sit at ~50–70% of the sign: a thief can't be far below it. The Meadow (recommended 0) wakes after 2.25 s, and its run home is a tutorial: anyone who runs gets away.

The tests check, by bisection in the chase sim:
- every zone's threshold is at least 45% (the Desert 30%);
- slack is at least 0.3 s everywhere;
- 70% of the recommended WalkSpeed and the previous zone's recommended Speed get caught in zones 2–7.

The sim ticks at 10 Hz, like the guard loop, so delays act in 0.1 s steps. Keep `GUARD_SPEED_FACTOR` at 1 or below, or players at exactly the recommended Speed get caught.

## The zone bosses: the owner's rigged pets, animated by code
The seven guardians are rigged pets the owner bought (`models/bosses/Pets.rbxl`, Workspace.PetTemplates; no scripts): skinned MeshParts deformed by Bones. `lune run tools/export_bosses.luau` exports the chosen pet of each zone (`BossRigs.BY_ZONE`) into its `assets/Guard_<Name>.rbxm`: just the meshes and the RootPart with the Bones (the kit's AnimationController, saved animations, Motor6Ds and helper parts are dropped), scaled by the profile (part sizes and bone offsets), anchored, front = -Z, with `BossRig`, `RigScale`, `KeepScale` and `Pivot = (0,0,0)` (Assets.place puts the pet's own ground point, not its bounds' centre, at the guard's feet).

| Zone | Guardian | Pet | Height × width × length (studs) | Animation |
|---|---|---|---|---|
| 🌼 Meadow | Giant Turtle | Turtle | 10 × 14 × 22 | trot; asleep its head pulls into the shell, legs tucked |
| 🦂 Desert | Red Mole | RedMole | 11 × 28 × 34 | splayed digging paws paddle; whiskers twitch; rears up to bite |
| 🦖 Jungle | Giant Snake | GiantSnake | 14 × 8 × 33 | slithers (a wave down the body and tail, the head held steady); coils its neck down asleep; strikes |
| 🌋 Lava Fields | Volcano Gorilla | GorillaVulcano | 15 × ~27 × 12 | arms brought down from the kit's T-pose; knuckle gallop; chest beat on waking; two-fisted smash |
| ❄️ Snow Peaks | Ice Shark | IceShark | 15 × 24 × 32 | glides over the snow: tail sweeps, fins paddle, body bobs; jaws snap |
| 👽 Deep Space | Void Dragon | VoidDragon | 18 × 29 × 17 | runs on two legs flapping its wings; folds them and crouches asleep; wings flare on a bite |
| ⛩️ Spirit Garden | Lumistag | Lumistag | 18 × 14 × 13 | gallops in bounds; lies down with folded legs; antler ram |

The server still moves the invisible HumanoidRootPart with `Humanoid:MoveTo` (gameplay unchanged) with the pet welded to it, and tags the guard with `Rig`, `BodyMin`/`BodyMax` and, on a catch, `CatchAt`. Every client poses the Bones locally (`src/client/GuardAnimator.client.luau`, only bosses within 150 studs of the camera) from the guard's `State` attribute: sleeping (lying down, slow breathing, floating Zzz), waking (a hop, head flung up, mouth open; the ❗ label stays), chasing (the gait, its stride phase driven by ground speed, with dust and footstep thumps), the catch lunge/bite, a grumpy slower walk home, and a dizzy wobble when stunned, cross-faded over 0.25 s. `src/shared/BossRigs.luau` holds a rig profile per pet (which bones are the legs L/R front/back, spine, neck, head, jaw, tail, wings, fins) and is pure math: a pose turns bones about their own pivots in model axes, and `solve` turns it into `Bone.Transform`. The kits' feet and hands are IK-target bones parented to the root, so they "follow" the end of their leg, feet stay flat, and no foot, toe, hand or finger goes under the ground. Near a side wall the body slides inward a little so it never pokes through (visual only). `tests/bosses.spec.luau` checks each slot holds its pet with no scripts or animation leftovers, every profile bone exists, the sizes, and that every state's pose is finite and stays above the ground.

## Plant-creatures
Each planted seed grows into its zone's creature (`CreatureModels`). The creatures are 20–32 parts (up to 39 with Legendary flair) built from Parts, WedgeParts and built-in Sphere `SpecialMesh`es, so nothing needs uploading. Each one hatches from a seed husk and has a leaf or flower motif. Later zones stand taller and glow more.

| Zone | Creature |
|---|---|
| Meadow | **Sproutling**: round green bulb with a two-leaf sprout and yellow bud, leaf arms, rosy cheeks |
| Desert | **Cactopod**: barrel cactus on four stubby legs, saguaro arms, spines, pink flower crown |
| Jungle | **Fernosaur**: long-necked leaf dino, fern fronds down its back, fiddlehead tail, drifting spores |
| Lava Fields | **Magmabloom**: magma-rock body with Neon lava seams and fists, sunflower head of Neon flame petals, embers |
| Snow Peaks | **Frostbulb**: icy teardrop bulb in a red scarf, Neon ice-crystal crown, falling snow |
| Deep Space | **Starpetal**: floating cyclops star-flower on a Neon stem, five star petals, glowing antennae, two moons |
| Spirit Garden | **Lotus Wyrm**: coral dragon coiling out of a lotus on a lily pad, gold horns/whiskers/fins, spirit pearl, petals |

- **Rarity**: Uncommon recolours the trims in the rarity colour (no aura ring: nothing flat lies on the ground under a plant). Rare makes the trims Neon and adds a light. Epic adds sparkles. Legendary adds a halo of orbs.
- **Mutations**: Gold turns the creature to gold foil. Rainbow cycles its skin on the client and gives the leaves rainbow hues. Night gives it a deep-blue tint. Celestial (exclusive, premium seed packs only) is the rarest look: a deep-violet body with a starry sheen, white Neon leaves and petals, a halo of white star orbs and slow drifting stars. Every mutation adds sparkles and a light, and the model keeps its `Mutation` attribute.
- **Size**: `CreatureModels.scaleFor` gives about 1× at sprout and about 1.9× full-grown, +7% per rarity step, clamped to `CREATURE_MAX_SCALE`. The largest creature is about 20 studs tall and gets room to grow: planting keeps plants apart by their full-grown size (`Planting.radius`, tested against `scaleFor`).
- **Idle sway**: `Effects.client` runs one loop that bobs and sways every creature within 160 studs of the camera, using one `BulkMoveTo`. It runs on the client only, so nothing replicates.
- **Uploaded models**: a `Creature_<Seed>.rbxm` in `assets/` comes first (see "Drop-in models"). Otherwise, asset ids in `Config.CREATURE_ASSETS` (zone index → id) are loaded once. Both are fitted to the footprint and decorated like the procedural creatures, and the procedural creature is the fallback.
- `lune run tests/creature_view.luau [zone] [rarity] [mutation]` prints ASCII front and side views, so you can check silhouettes without Studio. `tests/creatures.spec.luau` checks part budgets, footprint, heights, flair and scaling.

## Layout
| Path | Roblox location | What |
|---|---|---|
| `src/shared/Config.luau` | `ReplicatedStorage.Shared` | All tuning: zones, rarities, mutations, economy/growth formulas, trails, plot levels, developer products, day/night |
| `src/shared/Format.luau` | `ReplicatedStorage.Shared` | `1.2K / 3.4M / 5B / 7.5T / 3Qa`, `2,018,798 Kg`, `m:ss` |
| `src/shared/Treadmill.luau` | 〃 | *Pure*: which belt a position stands on and whether it is yours, what a second on it pays (`perSecond`) and the board's "+X/s > +Y/s", the run-in-place rule (client), the board's range and owner check (server), where the board stands, the lock at the belt's centre |
| `src/shared/Planting.luau` | 〃 | *Pure*: free planting: on your own dirt beds, spacing by full-grown size, reach, the slot limit (server check and client preview), plant ids, old saves' slots → spots, auto-placing |
| `src/shared/SeedPacks.luau` | 〃 | *Pure*: the two packs, odds tables, rolls, seed-bag keys |
| `src/shared/Icons.luau` | 〃 | UI icons: `Icons.image(key)`, `Icons.set(label, keys, text)` (icon or the emoji fallback) |
| `icons/ids.json` | `ReplicatedStorage.Shared.IconIds` | The 21 icons' image asset ids (0 = not uploaded); `icons/*.png` are the source images |
| `src/server/Main.server.luau` | `ServerScriptService.Server` | Bootstrap: collision groups, world, services, join/leave, autosave, BindToClose |
| `src/server/Net.luau` | 〃 | Creates the fixed remotes |
| `src/server/Sessions.luau` | 〃 | Per-player runtime state, multipliers, StatsUpdate + leaderstats |
| `src/server/WorldBuilder.luau` | 〃 | Adopts the hand-edited map by its Role attributes (`load`/`adopt`), or builds it from primitives: base, 5 plots + treadmills, the Upgrade board at each plot entrance (studded navy sign, money and Robux buttons), the shop plaza (walk-up stalls: 🛒 Shop, 🏃 Trail Shop, 📖 Index, SELL), nests with their "👟 recommended" plank (no zone gates or signs; the Spirit Garden's back wall ends the corridor) |
| `src/server/ZoneThemes.luau` | 〃 | Builds the 7 zones (no gates) from `Zones/<Zone>`, keeps each nest's corner clear (`nestKeepOut`) |
| `src/server/Zones/*.luau` | `ServerScriptService.Server.Zones` | One module per zone (its colours, set pieces and particle ambience) on the shared `Kit`: studded blocks, stepped mounds, rocks, ragged pools, fire, crystals, bamboo, trees, the sunken lily pond and waterfalls |
| `src/server/Props.luau` | 〃 | Primitive kit (blocks, ellipsoids, overlays, lights, emitters) and reusable props |
| `src/server/SpeedLogic.luau` | 〃 | *Pure*: per-tick gain, cap, treadmill (fixed rate per level × trail), sanity check |
| `src/shared/BoardButton.luau` | 〃 | *Pure*: the Upgrade boards' $ button colours (green when the owner can afford it, red otherwise) |
| `src/server/SpeedService.luau` | 〃 | 0.25 s loop: applies SpeedLogic, WalkSpeed, rubber-band |
| `src/server/GuardBrain.luau` | 〃 | *Pure*: guard state machine (sleep/wake/chase/catch/return/stun) |
| `src/server/GuardService.luau` | 〃 | Builds the giants, 10 Hz MoveTo loop, catches, bat |
| `src/server/SeedService.luau` | 〃 | Nests, pods (genes, seed designs, name tags), steal prompts, carry weld, return/regrow, the seed bag on reaching the base |
| `src/server/PlotService.luau` | 〃 | Plot assignment, planting, plant-creatures, growth, payouts (x plot level), offline income, plot upgrades (the entrance board) |
| `src/server/CreatureModels.luau` | 〃 | Builds the seven plant-creatures from primitives (or a `Creature_` model), plus rarity/mutation flair and scale-by-weight |
| `src/server/Assets.luau` | 〃 | Drop-in models: slot names and aliases, fitting/placing (`place`), slot groups (`swap`, `replace`, `refresh`) |
| `assets/` | `ServerStorage.Assets` | Models made in Blender, one file per slot (guide: `assets/COMO_ADICIONAR_MODELOS.md`) |
| `map/World.rbxm` | `Workspace.World` | The hand-editable map the server adopts |
| `tools/` | — | `build_map.luau --force` (regenerate the map), `apply_assets.luau` (put assets into the map), `map_tool.luau` (shared), `upload_icons.luau` (upload the UI icons, write `icons/ids.json`) |
| `src/server/Selling.luau` | 〃 | *Pure*: the SELL stall's price and the `SellPlants` request check (distance, slots, inventory ids, duplicates) and sale |
| `src/server/Inventory.luau` | 〃 | *Pure*: the plant inventory (Remove → inventory, planted again as it was, prices) and the full-plot rule for a seed brought home |
| `src/server/PlantGhosts.luau` | 〃 | The planting preview's 3D ghosts (one inert silhouette per flower, built on first use into `ReplicatedStorage.PlantGhosts`) and what a seed's gene grows into |
| `src/server/Shop.luau` | 〃 | *Pure*: money purchases (trails, plot upgrade, treadmill tier), trail equip, Robux prompt gates, idempotent receipt grants for every product kind, full-bag compensation |
| `src/server/ShopService.luau` | 〃 | `RequestBuy` / `RequestUseItem`, gamepass stubs, developer product prompts, `ProcessReceipt` |
| `src/server/TrailService.luau` | 〃 | The equipped trail's `Trail` + 2 Attachments on the HumanoidRootPart, rebuilt on spawn and equip |
| `src/server/ProfileStore.luau` | 〃 | Save format, validation, DataStore wrapper |
| `src/server/AmbientService.luau` | 〃 | Day/night lighting (applies `LightingLook`) |
| `src/shared/LightingLook.luau` | `ReplicatedStorage.Shared` | *Pure*: the fixed day and night looks (Lighting, Atmosphere, ColorCorrection, Bloom, SunRays), their fixed clocks and the fade to black at each flip |
| `src/client/HUD.client.luau` | `StarterPlayerScripts.Client` | All UI, Slow Mode |
| `src/server/Rewards.luau` | `ServerScriptService.Server` | *Pure*: Free Gift claim (group only, once), MOST MONEY/s encoding, merging and formatting |
| `src/server/RewardService.luau` | 〃 | Group check (`IsInGroupAsync` + `GroupService`), `ClaimReward`, the gift box on the map's `GiftSpot`, the OrderedDataStore board loop |
| `src/server/GiftBox.luau` | 〃 | The FREE GIFT box built at runtime on the map's `GiftSpot` (where the free chest stood) (prompt opens the Free Gift window) |
| `src/client/Rewards.client.luau` | `StarterPlayerScripts.Client` | the Free Gift window (opened by the gift box) |
| `src/client/Effects.client.luau` | 〃 | Income popups, sounds, shake, belt scroll, rainbow mutation, creature idle sway, owner-only prompts and board buttons, per-zone colour grade |
| `src/client/Planting.client.luau` | 〃 | The planting preview (green/red disc on your dirt), click / tap / R2 to plant (remote `PlantSeed`), the hint and ✖ for bagged seeds |
| `src/client/DayNight.client.luau` | 〃 | The fade to black at each day/night flip and the local switch of the look (from the server clock) |
| `src/client/SpeedPlanks.client.luau` | 〃 | Writes each nest's "👟 2M recommended" plank from `Config.ZONES[k].req` (`Format.speedPlank`, so a map with older numbers still reads right) and colours it green or red from your Speed |
| `tests/` | — | Lune harness + specs (guard, speed, data, economy, world, lighting, packs, legendary odds + announcements, shop, progression + its free-player simulation, creatures, assets, map, bosses, icons + uploader, SELL stall, community rewards, treadmill tiers + own-belt animation, free planting + save migration) |

## Networking
`ReplicatedStorage.Remotes`:
- Client → server: `RequestBuy(itemId)`, `RequestUseItem(itemId)`.
  - `RequestBuy` ids: `PlotUpgrade` and `Trail:<id>` (money), `Product:<name>` (developer products, Robux only), `Pass:<name>` (gamepasses). For Robux the server only opens the prompt; `ProcessReceipt` grants.
  - `RequestUseItem` ids: `Bat`, `Seed:<bagKey>` (plant from the seed bag), `Equip:<trailId>` (an owned trail).
- Server → client: `StatsUpdate(partialStats)` (the client merges it), `LootEvent(kind, data)`, `IncomePopup(amount, position)`. Pack openings are `LootEvent("PackRoll", { packId, name, zone, result })`.
- Client → server: `SellPlants(slots)`, the Sell window's list of plant ids (see "Selling plants").
- Client → server: `RemovePlant(slot)`, the Plants panel's Remove button, from anywhere: rate-limited (4/s), and `Inventory.take` checks the slot is a whole number naming one of the player's own plants; the plant goes to the **inventory** as it is (flower, mutation, growth), never for money. `StatsUpdate` carries `catalog` (the Index's flowers per zone and rarity) once at join, each plant in `plants` has its `name`, and `inventory` lists the inventory plants (`id`, `name`, `sell`, ...).
- Client → server: `PlantSeed(position, bagKey?)`, from the planting preview: plant the carried seed (or bagged seed `bagKey`, or inventory plant `"inv:<id>"`) at `position` (rate-limited; `PlotService.plantAt` re-checks everything). Server → client: `LootEvent("PlaceSeed", { key, zone, rarity, name, scale })` after the Inventory's Plant button, to show the ghost preview for that seed or plant. `SellPlants(slots, ids?)` sells planted plants and inventory plants at the SELL stall.
- Client → server: `ClaimReward("Gift")`, the Free Gift's CLAIM! button (rate-limited; the server checks the community). Server → client: `LootEvent("OpenFreeGift")` (the once-per-account auto-open), `LootEvent("FreeGift", { result, claimed })`; `StatsUpdate` carries `freeGift`.
- Stealing uses server-side ProximityPrompts (removing a plant is the Plants panel's button, above); the Upgrade boards use ClickDetectors and popup-less prompts. Day/night is computed from the shared clock (`Config.dayPhase`), so it needs no remote.

## Known limits
- **Not playtested in Studio yet.** The instance code (world, guard humanoids, prompts, UI) compiles and type-checks against the Roblox API definitions. Only the pure logic is covered by tests.
- No DataStore session locking. Rejoining a different server within seconds can load a save that is up to one autosave old.
- The guards are welded primitives that glide, with no walk animation. The built-in art is primitives and built-in `rbxasset://` particle textures; drop-in models from `assets/` replace it piece by piece.
- **Drop-in models are checked under Lune only.** Lune has no `Model:ScaleTo`/`PivotTo`, so the baked map places models by moving and resizing their parts, while the server uses `ScaleTo`/`PivotTo`. Both put the bottom centre on the pivot and fit the same box, but the Roblox path has not been run in Studio yet.

## Credits
- Icons by @gvesster (Free Icon Pack). The pack's license allows commercial use with optional credit; it may not be resold or claimed as our own work.
