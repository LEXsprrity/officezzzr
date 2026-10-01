# Steal a Seed

A Roblox "steal-and-run" game in Luau, built with [Rojo](https://rojo.space) 7. It replaces Coin Rush.

Players get a fenced plot. From spawn, one long walled corridor runs through seven themed zones. Each zone has a sleeping giant guardian next to a glowing mother plant. Grab a seed pod, the guardian wakes and chases you, and you run home and plant it. It sprouts into a plant-creature with a weight ("2,018,798 Kg") that earns money. Money buys Speed, Speed gets you further down the corridor, and further zones grow better seeds. **The goal is to reach the End of the Line.**

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
| **R** (hold) | Remove one of your plants (refunds 30 s of its income) |
| **1** | Bat: stuns a nearby awake guard for 2 s (4 s cooldown) |
| **2** | Sleep Dust: the nearest sleeping guard stays asleep 5 s longer after the next steal |
| ⚡ **+** | Buy Speed (+25% pack, Max, next Speed Gain multiplier) |
| 🛒 / 📖 | Shop (🎁 Seed Packs / ⚡ Upgrades tabs) / Index (collection book) |
| 🐢 Slow | Slow Mode: clamps your own WalkSpeed to 16 for moving around the base |
| 🌱 🪴 (right) | Seeds (incl. your 🎒 seed bag: **Plant** at your pad) / Plants menus |

## Seed packs
Our version of "eggs with odds". The 🛒 Shop opens on the **🎁 Seed Packs** tab. **Packs are Robux only**: every pack is a developer product, and there is no way to buy one with in-game money.
- **One pack per zone.** Each zone pack is its own developer product (`PackMeadow` … `PackSpirit`). It stays locked in the UI until you reach the zone's recommended Speed, and the server refuses to open the Robux prompt for a locked pack. It rolls like a daytime pod in that zone, and the loot table in the UI comes from the same function the server rolls with (`SeedPacks.odds`). Mutations are Gold 4% and Rainbow 1%. Night never rolls from packs.
- **Featured pack.** It rotates every 3 h on `os.time`, so every server shows the same pack with the same countdown. Zones come in shuffled cycles: each zone once per cycle, never twice in a row. It's sold as 1/3/10-pack bundles (`PackBundle1/3/10`), has no Speed gate, rolls with night luck and doubled mutation chances, and is the only source of the exclusive **🌟 Celestial** mutation (0.5%, ×12 income). The UI shows a NEW! badge, a shine and a live countdown. A click from a stale menu after a rotation is refused. If the pack rotates while the Robux dialog is open, a receipt that arrives within `FEATURED_PROMPT_GRACE` (10 min) still opens the pack you clicked. A receipt replayed later (rejoin, another server) opens the current featured pack.
- **Prices.** The real price is whatever you set on the Creator Dashboard. The Shop fetches it once per product with `MarketplaceService:GetProductInfo` (pcall'd and cached) and shows it as `R$ 80`. Until that works, or while the id is still `0`, it shows the placeholder `robux` from `Config.DEVELOPER_PRODUCTS`: zone packs 25/30/35/45/55/65/75 R$, featured ×1/×3/×10 = 80/200/600 R$.
- **Buying.** Clicking a pack with `id = 0` shows a "coming soon" toast. With a real id, the server checks the gates (`Shop.canPrompt`: Speed for zone packs, the featured slot, bag below `SEED_BAG_MAX`) and calls `PromptProductPurchase`. `ProcessReceipt` grants. A receipt that arrives is **always** granted, even for a pack the player hasn't unlocked, because the player paid.
- **Receipts.** `ProcessReceipt` grants once per `PurchaseId` (the last 100 ids are kept in the profile), saves, and only then returns `PurchaseGranted`. If the save fails it returns `NotProcessedYet`, and a retry in the same session doesn't grant twice. If the server dies before saving, neither the seeds nor the id were saved, so the retry on the next server grants exactly once.
- **Where the seed goes.** Into a persisted **seed bag** (`profile.seedBag`, stacks by `zone:rarity[:Mutation]`). Plant from the 🌱 Seeds menu while standing on your pad. It follows the same rules as a carried seed: your plot, near the pad, a free slot. The pad prompt still plants carried seeds. `SEED_BAG_MAX` (50) is a soft cap: the Shop won't *prompt* past it, but paid grants go past it up to `SEED_BAG_HARD_MAX` (250). A pack whose seed doesn't fit at the hard max pays money instead: `PACK_FULL_BAG_INCOME_SECONDS` (300 s) of your current income, or 300 s of a Common plant from that pack's zone if that's more (so a player with no plants still gets something). A paid pack is never lost, and a toast says what happened.
- **Reveal.** A reel spins through candidate seeds, lands on the server's result and bursts in its rarity colour. Bundles show every result.

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
- Seed packs are developer-product stubs. Create 10 developer products on the Creator Dashboard (7 zone packs + featured ×1/×3/×10) and paste their ids into `Config.DEVELOPER_PRODUCTS`. The price comes from the Dashboard. The place must be published for `PromptProductPurchase`/`GetProductInfo` to work.

### Manual acceptance test (Studio → Test → Local Server, 2 players)
1. Both players spawn on their own plot. The sign shows "🏠 Name's Plot".
2. Each player walks into the corridor, steals a Meadow seed (E), gets chased, gets home and plants it on the pad. `+$` popups appear.
3. Stand on the treadmill: you run in place without being pushed, and Speed climbs even when AFK.
4. Buy Speed with **+**, then try the Desert at about 3K Speed and at 10K Speed. At 3K: caught, seed back at the nest, knocked back. At 10K: the guard wakes at once and chases exactly as fast as you; run straight home and it never closes the gap. In the Spirit Garden (5B), the dragon shows ❗ for half a second first.
5. Both players leave, then rejoin: money, Speed, plants and Index are intact (API access must be on).
6. Shop → 🎁 Seed Packs: with stub ids, clicking a pack says "coming soon" and no money is charged. With real ids, buy a Meadow pack: Studio shows a test purchase dialog (no real Robux). The reel spins and lands, and the seed shows up in 🌱 Seeds → 🎒 bag. Stand on your pad and press Plant. Rejoin: the bag is intact. The Desert pack shows 🔒 below 10K Speed, and clicking it doesn't open the purchase dialog.

## Rules the code enforces
- **Server-authoritative.** Money, Speed, pickup, carry, planting and purchases all live on the server. The client only draws the HUD and VFX and runs Slow Mode. Every prompt and remote re-checks distance, ownership and state, and remotes are rate-limited.
- **Speed stat vs WalkSpeed.** `WalkSpeed = clamp(16 + 16*log10(1+Speed), 16, 180)`. Zones compare the *stat*.
- **Speed from moving** (`SpeedService` + `SpeedLogic`). Every 0.25 s the server measures horizontal HumanoidRootPart movement and grants `distance × gainRate × multipliers`, capped per tick.
- **Movement sanity check.** A tick that moves more than `WalkSpeed × dt × 1.5 + 2` earns nothing. Sustained over-speed that drains a one-second movement budget, or any teleport-sized jump, is rubber-banded to the last valid position. Server-side moves (spawn, knockback) reset the tracker.
- **Treadmill.** The server checks whether the root part is inside the belt's bounds and grants the full walking rate for the tick × the tier (2×, or 3×/5× from the shop). The belt does not move you: you just stand on it (AFK works) and the client loops your run animation in place. It has the same per-tick cap. There is no client remote.
- **Guards** (`GuardService` + `GuardBrain`). A guard wakes its zone's `wakeDelay` (0–0.5 s, showing ❗ meanwhile) after a seed is taken and chases at `walkSpeedFor(zone.req) × GUARD_SPEED_FACTOR` (1.0), exactly a player's WalkSpeed at the recommended Speed. A server loop calls `Humanoid:MoveTo` along the corridor at 10 Hz, with no pathfinding. A catch is horizontal distance < 6 studs from the path the guard walked since its last tick, never `Touched`. A Spirit Garden guard covers 17 studs per tick, so checking only its current position could step right over a thief. The seed goes back to its pod, and the player is knocked 30 studs away and frozen for 1 s. The chase ends when the thief reaches the base, after a catch, or after 45 s, and then the guard walks home and sleeps.
- **Carry.** One seed at a time, a server-made part welded to your back. Dying or leaving returns it to its pod.
- **Growth.** Only `plantedAt` is saved. `weight = sprout × variance × (1 + 4·ease(age/20 min))` grows to 5× and stops. `income = seedIncome(zone) × rarity × mutation × sqrt(weight/sprout)`. A single 3 s payout loop evaluates the formula. There is no per-plant tick.
- **Day and night plants.** Every zone is either ☀️ day (Meadow, Desert, Lava, Spirit) or 🌙 night (Jungle, Snow, Space), set by `Zone.active`. Its plants pay `ACTIVE_TIME_MULT` (1.5×) during their phase and 1× otherwise (`Config.timeMult`, from the shared `dayPhase` clock). The payout loop applies it, and the plant's billboard shows ☀️/🌙 plus a gold "1.5x!" while it is active. `plantIncome`/`incomeOf` stay the plain base, and the 30 s removal refund uses the base too. Offline income uses the cycle average: 300 s day and 150 s night give ×4/3 for day plants and ×7/6 for night plants.
- **Economy** is formulas in `Config`. `speedCost(n) = n × $1`. `seedIncome(k) = req[k+1] / (ECONOMY_SLOTS × 300 s)` with `ECONOMY_SLOTS = 10`, so a 10-plant plot of zone-k Commons pays for zone k+1 in about 5 minutes. New players start with `SLOTS_START = 5` slots (older saves keep theirs). Slot 6 costs $500 and each further slot 2.5× the last (slot 10 ≈ $19.5K, 15 ≈ $1.9M, 30 ≈ $1.8T). Other upgrades are priced geometrically too.
- **Data** (`ProfileStore`, format v2). `UpdateAsync` with retries and exponential backoff, autosave every 90 s, `BindToClose`. If a load fails, that session never saves, so it can't overwrite real data with defaults. Saved fields: money, Speed, multiplier tiers, slots, plants (slot, zone, rarity, mutation, plantedAt), Index, items (Sleep Dust), the seed bag, the last 100 Robux receipt ids and `lastSeen`. v1 saves load with an empty bag and no receipts. Potions were removed: potion timers and potion items in old saves are dropped on load. Offline income is capped at 1 h.
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
- **Mutations**: Gold turns the creature to gold foil. Rainbow cycles its skin on the client and gives the leaves rainbow hues. Night gives it a deep-blue tint. Celestial (exclusive, featured packs only) is the rarest look: a deep-violet body with a starry sheen, white Neon leaves and petals, a halo of white star orbs and slow drifting stars. Every mutation adds sparkles and a light, and the model keeps its `Mutation` attribute.
- **Size**: `CreatureModels.scaleFor` gives about 1× at sprout and about 1.9× full-grown, +7% per rarity step, clamped to `CREATURE_MAX_SCALE`. The largest creature is about 20 studs tall and fits its slot (tested against the slot grid).
- **Idle sway**: `Effects.client` runs one loop that bobs and sways every creature within 160 studs of the camera, using one `BulkMoveTo`. It runs on the client only, so nothing replicates.
- **Uploaded models**: put asset ids in `Config.CREATURE_ASSETS` (zone index → id). They are loaded once, fitted to the footprint, and decorated like the procedural creatures. The procedural creature is the fallback.
- `lune run tests/creature_view.luau [zone] [rarity] [mutation]` prints ASCII front and side views, so you can check silhouettes without Studio. `tests/creatures.spec.luau` checks part budgets, footprint, heights, flair and scaling.

## Layout
| Path | Roblox location | What |
|---|---|---|
| `src/shared/Config.luau` | `ReplicatedStorage.Shared` | All tuning: zones, rarities, mutations, economy/growth formulas, shop prices, day/night |
| `src/shared/Format.luau` | `ReplicatedStorage.Shared` | `1.2K / 3.4M / 5B / 7.5T / 3Qa`, `2,018,798 Kg`, `m:ss` |
| `src/shared/SeedPacks.luau` | 〃 | *Pure*: odds tables, rolls, featured rotation, developer-product lookups, seed-bag keys |
| `src/server/Main.server.luau` | `ServerScriptService.Server` | Bootstrap: collision groups, world, services, join/leave, autosave, BindToClose |
| `src/server/Net.luau` | 〃 | Creates the fixed remotes |
| `src/server/Sessions.luau` | 〃 | Per-player runtime state, multipliers, StatsUpdate + leaderstats |
| `src/server/WorldBuilder.luau` | 〃 | Builds the map from primitives: base, 5 plots + treadmills, zone arches + signs, nests, the End |
| `src/server/ZoneThemes.luau` | 〃 | Per-zone floor, walls, props and particle ambience for the 7 zones |
| `src/server/Props.luau` | 〃 | Primitive kit (blocks, ellipsoids, overlays, lights, emitters) and reusable props |
| `src/server/SpeedLogic.luau` | 〃 | *Pure*: per-tick gain, cap, treadmill, sanity check |
| `src/server/SpeedService.luau` | 〃 | 0.25 s loop: applies SpeedLogic, WalkSpeed, rubber-band, End of the Line |
| `src/server/GuardBrain.luau` | 〃 | *Pure*: guard state machine (sleep/wake/chase/catch/return/stun/dust) |
| `src/server/GuardService.luau` | 〃 | Builds the giants, 10 Hz MoveTo loop, catches, bat, Sleep Dust |
| `src/server/SeedService.luau` | 〃 | Nests, pods, steal prompts, carry weld, return/regrow |
| `src/server/PlotService.luau` | 〃 | Plot assignment, planting, plant-creatures, growth, payouts, offline income |
| `src/server/CreatureModels.luau` | 〃 | Builds the seven plant-creatures from primitives, plus rarity/mutation flair and scale-by-weight |
| `src/server/Shop.luau` | 〃 | *Pure*: purchase rules, seed-pack prompt gates, idempotent Robux receipt grants, full-bag compensation |
| `src/server/ShopService.luau` | 〃 | `RequestBuy` / `RequestUseItem`, gamepass stubs, seed-pack Robux prompts, `ProcessReceipt` |
| `src/server/ProfileStore.luau` | 〃 | Save format, validation, DataStore wrapper |
| `src/server/AmbientService.luau` | 〃 | Day/night lighting, "Fastest here" board |
| `src/client/HUD.client.luau` | `StarterPlayerScripts.Client` | All UI, Slow Mode |
| `src/client/Effects.client.luau` | 〃 | Income popups, sounds, shake, belt scroll, rainbow mutation, creature idle sway, owner-only prompts, per-zone colour grade |
| `tests/` | — | Lune harness + specs (guard, speed, data, economy, world, packs, creatures) |

## Networking
`ReplicatedStorage.Remotes`:
- Client → server: `RequestBuy(itemId)`, `RequestUseItem(itemId)`.
  - `RequestBuy` ids: shop items, `Pass:<name>`, `Product:<name>` (seed packs, Robux only; featured bundles send `Product:<name>:<slot>` with the featured slot the menu showed). The server only opens the Robux prompt; `ProcessReceipt` grants.
  - `RequestUseItem` ids: `Bat`, `SleepDust`, `Seed:<bagKey>` (plant from the seed bag).
- Server → client: `StatsUpdate(partialStats)` (the client merges it), `LootEvent(kind, data)`, `IncomePopup(amount, position)`. Pack openings are `LootEvent("PackRoll", { packId, name, zone, featured, results })`.
- Stealing, planting and removing plants use server-side ProximityPrompts. Day/night is computed from the shared clock (`Config.dayPhase`), so it needs no remote.

## Known limits
- **Not playtested in Studio yet.** The instance code (world, guard humanoids, prompts, UI) compiles and type-checks against the Roblox API definitions. Only the pure logic is covered by tests.
- No DataStore session locking. Rejoining a different server within seconds can load a save that is up to one autosave old.
- The guards are welded primitives that glide, with no walk animation. The world art is built from primitives and built-in `rbxasset://` particle textures, with no uploaded assets.
