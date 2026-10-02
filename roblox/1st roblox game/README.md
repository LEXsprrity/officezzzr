# Steal a Seed

A Roblox "steal-and-run" game in Luau, built with [Rojo](https://rojo.space) 7. It replaces Coin Rush.

Players get a fenced plot. From spawn, one long walled corridor runs through seven themed zones. Each zone has a sleeping giant guardian next to a glowing mother plant. Grab a seed pod, the guardian wakes and chases you, and you run home and plant it. It sprouts into a plant-creature with a weight ("2,018,798 Kg") that earns money. Money buys **trails** (they multiply the Speed you gain by moving) and **plot upgrades** (more slots, more income); Speed gets you further down the corridor, and further zones grow better seeds. **The goal is to reach the End of the Line.**

| # | Zone | Guardian | Seed | Recommended Speed | Length (studs) |
|---|---|---|---|---|---|
| 1 | 🌼 Meadow | Giant Mole | Sproutling | 0 | 200 |
| 2 | 🦂 Desert | Giant Scorpion | Cactopod | 10K | 450 |
| 3 | 🦖 Jungle | Giant Dino | Fernosaur | 500K | 600 |
| 4 | 🌋 Lava Fields | Lava Golem | Magmabloom | 5M | 700 |
| 5 | ❄️ Snow Peaks | Giant Yeti | Frostbulb | 50M | 800 |
| 6 | 👽 Deep Space | Big Alien | Starpetal | 500M | 900 |
| 7 | ⛩️ Spirit Garden (END) | Spirit Dragon | Lotus Wyrm | 5B | 1,100 |

The Meadow is deliberately short (200 studs) so a new player grabs a first seed within seconds. The corridor is 4,750 studs long, so a run to the end takes about 28 s at the Spirit Garden's recommended Speed (WalkSpeed 171) and 26 s at max WalkSpeed (180).

## Controls
| Key / button | What |
|---|---|
| **E** (hold) | Steal a seed pod / plant the seed on your plot's pad |
| **E** at your gate's board | ⬆️ Upgrade Plot (next level for money; only the owner sees the prompt) |
| **R** (hold) | Remove one of your plants (refunds 30 s of its income) |
| **1** | Bat: stuns a nearby awake guard for 2 s (4 s cooldown) |
| **2** | Sleep Dust: the nearest sleeping guard stays asleep 5 s longer after the next steal |
| 🏃 (on the Speed panel) | Trail Shop: buy trails for $ or R$, equip one. The panel shows your WalkSpeed and **+X Speed/step** |
| 🛒 / 📖 | Shop (seed packs, plot upgrade, Speed, money, treadmill, items, passes) / Index (collection book) |
| 🐢 Slow | Slow Mode: clamps your own WalkSpeed to 16 for moving around the base |
| 🌱 🪴 (right) | Seeds (incl. your 🎒 seed bag: **Plant** at your pad) / Plants menus |

## Seed packs
Our version of "eggs with odds": **two premium, late-game packs, Robux only**. Each pack is a developer product, and there is no way to buy one with in-game money. The 🛒 Shop starts with the **-- SEED PACKS --** section, which shows both packs as big cards in their zone colours, each with its exact odds table and an R$ button.

| Pack | Product | Rolls | Placeholder price | Rarity odds | Mutations |
|---|---|---|---|---|---|
| 👽 Starpetal Pack | `PackSpace` | 1 Deep Space (zone 6) seed | 2,000 R$ | Common 14.5%, Uncommon 18.1%, Rare 21.7%, Epic 26.1%, Legendary 19.6% | 🌟 Celestial 0.5%, Gold 8%, Rainbow 2% |
| ⛩️ Lotus Wyrm Pack | `PackSpirit` | 1 Spirit Garden (zone 7) seed | 3,000 R$ | Common 12.5%, Uncommon 16.7%, Rare 21.4%, Epic 27.4%, Legendary 21.9% | 🌟 Celestial 0.5%, Gold 8%, Rainbow 2% |

- **No Speed gate.** Anyone can buy either pack, even at 0 Speed: they're a premium shortcut to late-game seeds.
- **Odds.** A pack rolls rarities like a *night* pod in its zone (`PACK_LUCK = NIGHT_LUCK = 2`) with doubled Gold/Rainbow chances (`PACK_MUTATION_MULT = 2`). The Night mutation never rolls from packs. The odds in the UI come from the same function the server rolls with (`SeedPacks.odds`).
- **🌟 Celestial** (×12 income) is pack-only: both packs roll it at `PACK_EXCLUSIVE_CHANCE` (0.5%). Pods never roll it: its pod `chance` is 0, and the tests roll pods in every zone, day and night, to check.
- **Prices.** The real price is whatever you set on the Creator Dashboard. The Shop fetches it once per product with `MarketplaceService:GetProductInfo` (pcall'd and cached) and shows it as `R$ 2,000`. Until that works, or while the id is still `0`, it shows the placeholder `robux` from `Config.DEVELOPER_PRODUCTS`.
- **Buying.** Clicking a pack with `id = 0` shows a "coming soon" toast. With a real id, the server checks `Shop.canPrompt` (a known product, bag below `SEED_BAG_MAX`) and calls `PromptProductPurchase`. `ProcessReceipt` grants. A receipt that arrives is **always** granted, because the player paid.
- **Receipts.** `ProcessReceipt` grants once per `PurchaseId` (the last 100 ids are kept in the profile), saves, and only then returns `PurchaseGranted`. If the save fails it returns `NotProcessedYet`, and a retry in the same session doesn't grant twice. If the server dies before saving, neither the seed nor the id were saved, so the retry on the next server grants exactly once.
- **Where the seed goes.** Into a persisted **seed bag** (`profile.seedBag`, stacks by `zone:rarity[:Mutation]`). Plant from the 🌱 Seeds menu while standing on your pad. It follows the same rules as a carried seed: your plot, near the pad, a free slot. The pad prompt still plants carried seeds. `SEED_BAG_MAX` (50) is a soft cap: the Shop won't *prompt* past it, but paid grants go past it up to `SEED_BAG_HARD_MAX` (250). A pack whose seed doesn't fit at the hard max pays money instead: `PACK_FULL_BAG_INCOME_SECONDS` (300 s) of your current income, or 300 s of a Common plant from that pack's zone if that's more (so a player with no plants still gets something). A paid pack is never lost, and a toast says what happened.
- **Reveal.** A reel spins through candidate seeds, lands on the server's result and bursts in its rarity colour.

## Economy: what money and Robux buy
**In-game money buys only two things: trails and plot upgrades.** Everything else in the Shop is Robux (developer products and gamepasses). There is no money path to Speed, slots, the treadmill or Sleep Dust (`Shop.buy` refuses them, and tests check it).

### 🏃 Trails (money or Robux)
A trail is a coloured `Trail` that streams behind your character (two Attachments on the HumanoidRootPart, made by the server so everyone sees it, rebuilt on every respawn and every equip). The equipped trail multiplies the Speed you **gain** from walking and the treadmill. You own trails (saved) and equip one at a time. Any tier can be bought directly, without the one below it. Buying one equips it.

| Trail | Rarity | Speed gain | Money | Robux product | Placeholder |
|---|---|---|---|---|---|
| Grey | Common | x1.5 | free: every player owns it and starts with it equipped | — | — |
| Green | Uncommon | x2 | $5K | `TrailGreen` | 16 R$ |
| Blue | Rare | x2.5 | $75K | `TrailBlue` | 24 R$ |
| Purple | Epic | x3 | $1.5M | `TrailPurple` | 40 R$ |
| Golden | Legendary | x3.5 | $30M | `TrailGolden` | 64 R$ |
| Red | Mythic | x4 | $20B | `TrailRed` | 100 R$ |
| Rainbow | Secret | x5 | $1T | `TrailRainbow` | 180 R$ |

The 🏃 button on the Speed panel (it replaced the old "+" Speed menu) and the 🏃 TRAIL SHOP stall open the Trail Shop: one card per trail, scrolling sideways, in the trail's colour, with name, rarity, "xN Speed" and a green **$** button plus a purple **R$** button, or **Equip** / **Equipped** once owned.

### ⬆️ Plot upgrades (money only)
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

The last level is meant to be hard. A strong late-game player (a full level-25 plot of full-grown Spirit Garden plants with the average pod rarity and mutation mix, day/night averaged) earns about $10.8B/s, so level 26 takes about **8 h** of income, or about **4 h** with the 2x Money pass (tested). Level 2 costs under a minute of a starting plot.

Buy at the **⬆️ UPGRADE PLOT** board just outside your plot's gate ("Level X → Y", the perk and the price, owner-only prompt) or in the Shop's **-- PLOT UPGRADE --** section.

### 💎 Robux (developer products)
Every developer product ships as an `id = 0` stub with a placeholder price: clicking it says "coming soon". With a real id the server checks `Shop.canPrompt` and opens `PromptProductPurchase`; `ProcessReceipt` grants through the same idempotent path as the seed packs (granted once per `PurchaseId`, saved, then confirmed). The Shop shows the real price from `GetProductInfo` (cached) once the id is set.

| Section | Products | What a receipt grants |
|---|---|---|
| -- SPEED -- | `Speed150K` 64 R$, `Speed1M` 200, `Speed10M` 560, `Speed50M` 1,200, `Speed500M` 1,600, `Speed1B` 2,400 | adds to your Speed stat |
| -- MONEY -- | `Money24K` 40 R$, `Money200K` 80, `Money800K` 200, `Money4M` 400, `Money8M` 640 | **max(fixed amount, N minutes of your current income)**: $24K / 10 min, $200K / 30 min, $800K / 60 min, $4M / 180 min, $8M / 360 min. Fixed amounts go worthless late, so late players get the income share. The card shows what you'd get right now. |
| -- TREADMILL -- | `TreadmillX3` 60 R$, `TreadmillX5` 200 | your treadmill at x3 / x5 (`TREADMILL_TIERS`; x5 can be bought directly; owned tiers aren't prompted) |
| -- ITEMS -- | `SleepDust3` 25 R$ | 3 Sleep Dust |
| trails | `TrailGreen` … `TrailRainbow` | owns and equips the trail (owned trails aren't prompted) |
| -- SEED PACKS -- | `PackSpace`, `PackSpirit` | see Seed packs |
| -- PASSES -- | gamepasses `DoubleMoney`, `ExtraSlots` | unchanged |

Each Robux card also has a purple 🎁 gift button. Gifting isn't built yet: it shows a "coming soon" toast.

### Old saves (format v3)
Saves from before the rework (v1/v2) are migrated on load, once (the next save is v3):
- **Speed Gain tier → trail**, the nearest multiplier at or below it, owned and equipped: x1 → Grey (x1.5), x2 → Green (x2), x3 → Purple (x3), x5 → Rainbow (x5). Nobody's multiplier goes down, except that x10 and x25 are above the best trail: those players get Rainbow (x5) **and the money they paid for the x10/x25 tiers back** ($250M, and $250M + $10B).
- **Slots → plot level** = slots − 5 + 1 (clamped to 1–26), so everyone keeps exactly their slots. The plot's income multiplier comes with the level.
- Treadmill tier, Sleep Dust, plants, Index, seed bag and receipts are kept as they are.

### Progression: Speed per step compounds
Money can't buy Speed, so Speed comes from moving (× the trail), the treadmill (x2, or x3/x5 with Robux) and Robux Speed packs. The zone reqs grow exponentially (10K → 5B) but the studs anyone can walk only grow linearly. So the Speed each stud ("step") pays **grows with your current Speed**:

```
gainPerStud(Speed) = 0.32 × (1 + Speed / 100K) ^ 0.61        (GAIN_PER_STUD, GAIN_PIVOT, GAIN_EXPONENT)
Speed per step     = gainPerStud(Speed) × trail              (Config.speedPerStud)
treadmill          = WalkSpeed × Speed per step × tier, per second
```

With the trail a free player typically has by then: 0.48/step for a new player (Grey), 1.2 at 100K (Blue), 50 at 50M (Golden), 1.2K at 5B (Rainbow). Players see it: the Speed panel shows **"+X Speed/step"**, the Trail Shop repeats it, and the sign over each treadmill shows its owner's **"TREADMILL x2 · +X Speed/s"**, refreshed every payout. The zone reqs, guard speeds and escape thresholds are unchanged.

**Tuning: a simulated free player** (`tests/progression_sim.luau`, asserted in `tests/progression.spec.luau`). The player is active and spends no Robux. They steal from the furthest zone their Speed allows and plant it (filling free slots, then replacing the plant worth least once grown). When the plot is full of good plants, they stand on the free x2 treadmill. Whenever affordable, they buy the cheaper of the next trail and the next plot level. Each steal trip costs the run there and back plus 10 s. Arrival times (cumulative play):

| Zone | Rec. Speed | Target | Free player | ±50% window (tested) | Treadmill x5 (R$) | x5 + 11M Speed packs (R$) |
|---|---|---|---|---|---|---|
| 🦂 Desert | 10K | 5 min | **4m 26s** | 2m 30s – 7m 30s | 3m 10s | instant |
| 🦖 Jungle | 500K | 30 min | **32m** | 15 – 45 min | 18m | instant |
| 🌋 Lava Fields | 5M | 1–1.5 h | **1h 22m** | 37 min – 1h 52m | 44m | instant |
| ❄️ Snow Peaks | 50M | 3 h | **3h 05m** | 1h 30m – 4h 30m | 1h 34m | 41m |
| 👽 Deep Space | 500M | 6 h | **6h 21m** | 3h – 9h | 3h 03m | 2h 10m |
| ⛩️ Spirit Garden | 5B | 10–15 h | **12h 06m** | 6h 15m – 18h 45m | 5h 36m | 4h 43m |

The times hold across RNG seeds (tested). The x5 treadmill roughly halves them (tested ≤ 70%). Speed packs help on top.

**Money stays a sink all game.** The owner's trail prices Green–Golden ($5K / $75K / $1.5M / $30M) are bought in the first 40 minutes. Red ($20B, bought at ~3h, around Snow) and Rainbow ($1T, ~6h 47m, between Deep Space and Spirit) were retuned from $600M / $15B, which the free player bought at 1h 19m and 2h 38m. Plot levels are bought all along, the last at 10h 13m (level 23). At the Spirit Garden the player still has levels 24–26 ahead ($443T in total; level 26 alone is several hours of late-game income).

## Build, test, run
You need Rojo 7, Luau (`luau-compile`) and [Lune](https://github.com/lune-org/lune) for the tests.

```sh
rojo build -o StealASeed.rbxlx          # build a place file
rojo serve                              # or live-sync into Studio (Rojo plugin)
luau-compile --null src/**/*.luau       # syntax/compile check
lune run tests/run.luau                 # mocked server tests (run from this folder; Lune 0.10+)
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
- Everything sold for Robux except the 2 gamepasses is a developer-product stub. Create the **22 developer products** below on the Creator Dashboard (your experience → Monetization → Developer Products) and paste each id into its `Config.DEVELOPER_PRODUCTS` key. The price comes from the Dashboard (the placeholders are only shown until then). The place must be published for `PromptProductPurchase`/`GetProductInfo` to work.

  | ✅ | `Config.DEVELOPER_PRODUCTS` key | Dashboard name | Price (placeholder) | Grants |
  |---|---|---|---|---|
  | ☐ | `PackSpace` | Starpetal Pack | 2,000 R$ | 1 Deep Space (zone 6) seed |
  | ☐ | `PackSpirit` | Lotus Wyrm Pack | 3,000 R$ | 1 Spirit Garden (zone 7) seed |
  | ☐ | `Speed150K` | +150K Speed | 64 R$ | +150,000 Speed |
  | ☐ | `Speed1M` | +1M Speed | 200 R$ | +1,000,000 Speed |
  | ☐ | `Speed10M` | +10M Speed | 560 R$ | +10,000,000 Speed |
  | ☐ | `Speed50M` | +50M Speed | 1,200 R$ | +50,000,000 Speed |
  | ☐ | `Speed500M` | +500M Speed | 1,600 R$ | +500,000,000 Speed |
  | ☐ | `Speed1B` | +1B Speed | 2,400 R$ | +1,000,000,000 Speed |
  | ☐ | `Money24K` | Pocket Cash | 40 R$ | max($24K, 10 min of income) |
  | ☐ | `Money200K` | Cash Bag | 80 R$ | max($200K, 30 min of income) |
  | ☐ | `Money800K` | Cash Stack | 200 R$ | max($800K, 60 min of income) |
  | ☐ | `Money4M` | Cash Crate | 400 R$ | max($4M, 180 min of income) |
  | ☐ | `Money8M` | Cash Vault | 640 R$ | max($8M, 360 min of income) |
  | ☐ | `TreadmillX3` | Treadmill x3 | 60 R$ | treadmill x3 |
  | ☐ | `TreadmillX5` | Treadmill x5 | 200 R$ | treadmill x5 |
  | ☐ | `SleepDust3` | 3 Sleep Dust | 25 R$ | 3 Sleep Dust |
  | ☐ | `TrailGreen` | Green Trail | 16 R$ | owns + equips the Green trail (x2) |
  | ☐ | `TrailBlue` | Blue Trail | 24 R$ | Blue trail (x2.5) |
  | ☐ | `TrailPurple` | Purple Trail | 40 R$ | Purple trail (x3) |
  | ☐ | `TrailGolden` | Golden Trail | 64 R$ | Golden trail (x3.5) |
  | ☐ | `TrailRed` | Red Trail | 100 R$ | Red trail (x4) |
  | ☐ | `TrailRainbow` | Rainbow Trail | 180 R$ | Rainbow trail (x5) |

  Gamepasses (`Config.GAMEPASSES`): ☐ `DoubleMoney` (2x Money), ☐ `ExtraSlots` (+10 Plant Slots).

### Preview the map in Studio (without pressing Play)
The map is generated by code. To see it in edit mode, open View → Command Bar and run:
```lua
require(game.ServerScriptService.Server.WorldBuilder).build()
```
The whole map appears under `Workspace.World`. It is only a preview: edits to it are not kept, and the game replaces it with a fresh build when it starts. Use it to look around and to model new pieces to the right size.

### Manual acceptance test (Studio → Test → Local Server, 2 players)
1. Both players spawn on their own plot. The sign shows "🏠 Name's Plot".
2. Each player walks into the corridor, steals a Meadow seed (E), gets chased, gets home and plants it on the pad. `+$` popups appear.
3. Stand on the treadmill: you run in place without being pushed, and Speed climbs even when AFK. A grey trail streams behind you (the other player sees it too). The sign over your treadmill shows "TREADMILL x2 · +X Speed/s", and the Speed panel shows "+X Speed/step"; both grow as your Speed grows.
4. Earn $5K and buy the Green trail in the 🏃 Trail Shop: it turns green at once (and stays green after a respawn), and Speed climbs faster. Equip Grey again from its card. Walk to the ⬆️ UPGRADE PLOT board at your gate: only you get the prompt; buy level 2, a 6th soil patch appears and the board shows "Level 2 → 3".
5. Get Speed (treadmill, or a Speed pack once its id is set), then try the Desert at about 3K Speed and at 10K Speed. At 3K: caught, seed back at the nest, knocked back. At 10K: the guard wakes at once and chases exactly as fast as you; run straight home and it never closes the gap. In the Spirit Garden (5B), the dragon shows ❗ for half a second first.
6. Both players leave, then rejoin: money, Speed, plants, Index, owned/equipped trail and plot level are intact (API access must be on).
7. Shop → -- SEED PACKS --: two cards, Starpetal and Lotus Wyrm. With stub ids, clicking either says "coming soon" and no money is charged. With real ids, buy a Starpetal Pack at 0 Speed: Studio shows a test purchase dialog (no real Robux) and the button shows the Dashboard price. The reel spins and lands, and a Deep Space seed shows up in 🌱 Seeds → 🎒 bag. Stand on your pad and press Plant. Rejoin: the bag is intact.
8. Shop → every other section (Speed, Money, Treadmill, Items) and the R$ buttons on trail cards: with stub ids, "coming soon" and nothing charged; the 🎁 gift button says "Gifting is coming soon!". With real ids: a Speed pack adds Speed, a Money card pays exactly the amount it showed, Treadmill x5 makes the treadmill x5 and its card says Owned, Sleep Dust adds 3. No R$ item ever costs in-game money.

## Rules the code enforces
- **Server-authoritative.** Money, Speed, pickup, carry, planting and purchases all live on the server. The client only draws the HUD and VFX and runs Slow Mode. Every prompt and remote re-checks distance, ownership and state, and remotes are rate-limited.
- **Speed stat vs WalkSpeed.** `WalkSpeed = clamp(16 + 16*log10(1+Speed), 16, 180)`. Zones compare the *stat*.
- **Speed from moving** (`SpeedService` + `SpeedLogic`). Every 0.25 s the server measures horizontal HumanoidRootPart movement and grants `distance × Config.speedPerStud(Speed, trail)` (the progression curve below × the equipped trail), capped per tick.
- **Movement sanity check.** A tick that moves more than `WalkSpeed × dt × 1.5 + 2` earns nothing. Sustained over-speed that drains a one-second movement budget, or any teleport-sized jump, is rubber-banded to the last valid position. Server-side moves (spawn, knockback) reset the tracker.
- **Treadmill.** The server checks whether the root part is inside the belt's bounds and grants the full walking rate for the tick × the trail × the treadmill tier (2×, or 3×/5× with Robux). The belt does not move you: you just stand on it (AFK works) and the client loops your run animation in place. It has the same per-tick cap. There is no client remote.
- **Guards** (`GuardService` + `GuardBrain`). A guard wakes its zone's `wakeDelay` (0–0.5 s, showing ❗ meanwhile) after a seed is taken and chases at `walkSpeedFor(zone.req) × GUARD_SPEED_FACTOR` (1.0), exactly a player's WalkSpeed at the recommended Speed. A server loop calls `Humanoid:MoveTo` along the corridor at 10 Hz, with no pathfinding. A catch is horizontal distance < 6 studs from the path the guard walked since its last tick, never `Touched`. A Spirit Garden guard covers 17 studs per tick, so checking only its current position could step right over a thief. The seed goes back to its pod, and the player is knocked 30 studs away and frozen for 1 s. The chase ends when the thief reaches the base, after a catch, or after 45 s, and then the guard walks home and sleeps.
- **Carry.** One seed at a time, a server-made part welded to your back. Dying or leaving returns it to its pod.
- **Growth.** Only `plantedAt` is saved. `weight = sprout × variance × (1 + 4·ease(age/20 min))` grows to 5× and stops. `income = seedIncome(zone) × rarity × mutation × sqrt(weight/sprout)`. A single 3 s payout loop evaluates the formula. There is no per-plant tick.
- **Day and night plants.** Every zone is either ☀️ day (Meadow, Desert, Lava, Spirit) or 🌙 night (Jungle, Snow, Space), set by `Zone.active`. Its plants pay `ACTIVE_TIME_MULT` (1.5×) during their phase and 1× otherwise (`Config.timeMult`, from the shared `dayPhase` clock). The payout loop applies it, and the plant's billboard shows ☀️/🌙 plus a gold "1.5x!" while it is active. `plantIncome`/`incomeOf` stay the plain base, and the 30 s removal refund uses the base too. Offline income uses the cycle average: 300 s day and 150 s night give ×4/3 for day plants and ×7/6 for night plants.
- **Economy** is formulas in `Config` (see "Economy" above). `seedIncome(k) = req[k+1] / (ECONOMY_SLOTS × 300 s)` with `ECONOMY_SLOTS = 10`: a 10-plant plot of zone-k Commons earns zone k+1's recommended Speed, in dollars, in about 5 minutes (the same money scale as before the rework). Money buys trails and plot levels (`Config.priceOf`); plot levels cost `500 × 3.1^(L−2)` and multiply income by `1 + 0.06 × (L−1)`.
- **Data** (`ProfileStore`, format v3). `UpdateAsync` with retries and exponential backoff, autosave every 90 s, `BindToClose`. If a load fails, that session never saves, so it can't overwrite real data with defaults. Saved fields: money, Speed, owned trails + the equipped one, treadmill tier, plot level, plants (slot, zone, rarity, mutation, plantedAt), Index, items (Sleep Dust), the seed bag, the last 100 Robux receipt ids and `lastSeen`. v1 saves load with an empty bag and no receipts; v1/v2 saves get their Speed Gain tier turned into a trail and their slots into a plot level (see "Old saves" above). Potions were removed: potion timers and potion items in old saves are dropped on load. Offline income is capped at 1 h.
- **Art.** Everything is built from primitives by `WorldBuilder` (base, plots), `ZoneThemes` (the 7 zones) and the `Props` kit. Only floors, walls and the wall-flush arch pillars collide. All props are anchored and non-colliding (no Touched, no raycasts), so they never block runners, guards or the camera. The corridor is about 2.3k parts and the whole map about 3.7k (tested below 6k/8k). Day/night lighting blends a warm day look into a blue, readable night (`Config.nightBlend`), and the client adds a per-zone colour grade.

### Soft gates: how soft they are
A guard runs exactly as fast as a player at the zone's recommended Speed (`GUARD_SPEED_FACTOR = 1`). That player gets home on the head start alone: the ~28 studs between the nearest pod and the sleeping guard, plus the zone's `wakeDelay`. That head start is also the *slack*: how long a player at exactly the recommended Speed can hesitate after the steal (reaction time, lag) and still get home. A slower player keeps the same head start but loses ground every second. WalkSpeed is logarithmic in Speed, so a few WalkSpeed points are a big share of the Speed number:

| Zone | Recommended | `wakeDelay` | Escapes from Speed | WalkSpeed (player vs guard) | Slack |
|---|---|---|---|---|---|
| Desert | 10K | 0 s | ~5.7K (57%) | 76.1 vs 80.0 | 0.3 s |
| Jungle | 500K | 0.15 s | ~250K (50%) | 102.4 vs 107.2 | 0.5 s |
| Lava | 5M | 0.25 s | ~2.6M (52%) | 118.6 vs 123.2 | 0.5 s |
| Snow | 50M | 0.3 s | ~28M (57%) | 135.2 vs 139.2 | 0.5 s |
| Deep Space | 500M | 0.3 s | ~300M (60%) | 151.6 vs 155.2 | 0.5 s |
| Spirit Garden | 5B | 0.5 s | ~2.6B (52%) | 166.7 vs 171.2 | 0.7 s |

Each delay trades slack against the threshold: every 0.1 s adds 0.1 s of slack and lowers the threshold by about 7–9 points. Longer runs home can afford more delay. The Desert's run home is only ~580 studs, so it can't have both: a 0.1 s delay already drops it to 49.7%. It stays at 0, with 0.3 s of slack. The Meadow (recommended 0) gets 0.5 s.

The tests check, by bisection in the chase sim:
- every zone's threshold is at least 50%;
- slack is at least 0.5 s everywhere except the Desert (0.3 s);
- 70% of the recommended WalkSpeed and the previous zone's recommended Speed get caught everywhere.

The sim ticks at 10 Hz, like the guard loop, so delays act in 0.1 s steps. Keep `GUARD_SPEED_FACTOR` at 1 or below, or players at exactly the recommended Speed get caught.

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

- **Rarity**: Uncommon adds a Neon aura ring and recolours the trims in the rarity colour. Rare makes the trims Neon and adds a light. Epic adds sparkles. Legendary adds a halo of orbs.
- **Mutations**: Gold turns the creature to gold foil. Rainbow cycles its skin on the client and gives the leaves rainbow hues. Night gives it a deep-blue tint. Celestial (exclusive, premium seed packs only) is the rarest look: a deep-violet body with a starry sheen, white Neon leaves and petals, a halo of white star orbs and slow drifting stars. Every mutation adds sparkles and a light, and the model keeps its `Mutation` attribute.
- **Size**: `CreatureModels.scaleFor` gives about 1× at sprout and about 1.9× full-grown, +7% per rarity step, clamped to `CREATURE_MAX_SCALE`. The largest creature is about 20 studs tall and fits its slot (tested against the slot grid).
- **Idle sway**: `Effects.client` runs one loop that bobs and sways every creature within 160 studs of the camera, using one `BulkMoveTo`. It runs on the client only, so nothing replicates.
- **Uploaded models**: put asset ids in `Config.CREATURE_ASSETS` (zone index → id). They are loaded once, fitted to the footprint, and decorated like the procedural creatures. The procedural creature is the fallback.
- `lune run tests/creature_view.luau [zone] [rarity] [mutation]` prints ASCII front and side views, so you can check silhouettes without Studio. `tests/creatures.spec.luau` checks part budgets, footprint, heights, flair and scaling.

## Layout
| Path | Roblox location | What |
|---|---|---|
| `src/shared/Config.luau` | `ReplicatedStorage.Shared` | All tuning: zones, rarities, mutations, economy/growth formulas, trails, plot levels, developer products, day/night |
| `src/shared/Format.luau` | `ReplicatedStorage.Shared` | `1.2K / 3.4M / 5B / 7.5T / 3Qa`, `2,018,798 Kg`, `m:ss` |
| `src/shared/SeedPacks.luau` | 〃 | *Pure*: the two packs, odds tables, rolls, seed-bag keys |
| `src/server/Main.server.luau` | `ServerScriptService.Server` | Bootstrap: collision groups, world, services, join/leave, autosave, BindToClose |
| `src/server/Net.luau` | 〃 | Creates the fixed remotes |
| `src/server/Sessions.luau` | 〃 | Per-player runtime state, multipliers, StatsUpdate + leaderstats |
| `src/server/WorldBuilder.luau` | 〃 | Builds the map from primitives: base, 5 plots + treadmills, the ⬆️ Upgrade Plot board at each gate, the shop plaza (walk-up stalls: 🛒 Shop, 🏃 Trail Shop, 📖 Index), zone arches + signs, nests, the End |
| `src/server/ZoneThemes.luau` | 〃 | Per-zone floor, walls, props and particle ambience for the 7 zones |
| `src/server/Props.luau` | 〃 | Primitive kit (blocks, ellipsoids, overlays, lights, emitters) and reusable props |
| `src/server/SpeedLogic.luau` | 〃 | *Pure*: per-tick gain, cap, treadmill, sanity check |
| `src/server/SpeedService.luau` | 〃 | 0.25 s loop: applies SpeedLogic, WalkSpeed, rubber-band, End of the Line |
| `src/server/GuardBrain.luau` | 〃 | *Pure*: guard state machine (sleep/wake/chase/catch/return/stun/dust) |
| `src/server/GuardService.luau` | 〃 | Builds the giants, 10 Hz MoveTo loop, catches, bat, Sleep Dust |
| `src/server/SeedService.luau` | 〃 | Nests, pods, steal prompts, carry weld, return/regrow |
| `src/server/PlotService.luau` | 〃 | Plot assignment, planting, plant-creatures, growth, payouts (x plot level), offline income, plot upgrades (the gate board) |
| `src/server/CreatureModels.luau` | 〃 | Builds the seven plant-creatures from primitives, plus rarity/mutation flair and scale-by-weight |
| `src/server/Shop.luau` | 〃 | *Pure*: money purchases (trails, plot upgrade), trail equip, Robux prompt gates, idempotent receipt grants for every product kind, full-bag compensation |
| `src/server/ShopService.luau` | 〃 | `RequestBuy` / `RequestUseItem`, gamepass stubs, developer product prompts, `ProcessReceipt` |
| `src/server/TrailService.luau` | 〃 | The equipped trail's `Trail` + 2 Attachments on the HumanoidRootPart, rebuilt on spawn and equip |
| `src/server/ProfileStore.luau` | 〃 | Save format, validation, DataStore wrapper |
| `src/server/AmbientService.luau` | 〃 | Day/night lighting, "Fastest here" board |
| `src/client/HUD.client.luau` | `StarterPlayerScripts.Client` | All UI, Slow Mode |
| `src/client/Effects.client.luau` | 〃 | Income popups, sounds, shake, belt scroll, rainbow mutation, creature idle sway, owner-only prompts, per-zone colour grade |
| `tests/` | — | Lune harness + specs (guard, speed, data, economy, world, packs, shop, progression + its free-player simulation, creatures) |

## Networking
`ReplicatedStorage.Remotes`:
- Client → server: `RequestBuy(itemId)`, `RequestUseItem(itemId)`.
  - `RequestBuy` ids: `PlotUpgrade` and `Trail:<id>` (money), `Product:<name>` (developer products, Robux only), `Pass:<name>` (gamepasses). For Robux the server only opens the prompt; `ProcessReceipt` grants.
  - `RequestUseItem` ids: `Bat`, `SleepDust`, `Seed:<bagKey>` (plant from the seed bag), `Equip:<trailId>` (an owned trail).
- Server → client: `StatsUpdate(partialStats)` (the client merges it), `LootEvent(kind, data)`, `IncomePopup(amount, position)`. Pack openings are `LootEvent("PackRoll", { packId, name, zone, result })`.
- Stealing, planting and removing plants use server-side ProximityPrompts. Day/night is computed from the shared clock (`Config.dayPhase`), so it needs no remote.

## Known limits
- **Not playtested in Studio yet.** The instance code (world, guard humanoids, prompts, UI) compiles and type-checks against the Roblox API definitions. Only the pure logic is covered by tests.
- No DataStore session locking. Rejoining a different server within seconds can load a save that is up to one autosave old.
- The guards are welded primitives that glide, with no walk animation. The world art is built from primitives and built-in `rbxasset://` particle textures, with no uploaded assets.
