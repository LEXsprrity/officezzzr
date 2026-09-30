# Steal a Seed

A Roblox "steal-and-run" game in Luau, built with [Rojo](https://rojo.space) 7. It replaces Coin Rush.

Players get a fenced plot. From spawn, one long walled corridor runs through seven themed zones. Each zone has a sleeping giant guardian next to a glowing mother plant. Grab a seed pod, the guardian wakes and chases you, and you run home and plant it. It sprouts into a plant-creature with a weight ("2,018,798 Kg") that earns money. Money buys Speed, Speed gets you further down the corridor, and further zones grow better seeds. **The goal is to reach the End of the Line.**

| # | Zone | Guardian | Seed | Recommended Speed |
|---|---|---|---|---|
| 1 | 🌼 Meadow | Giant Mole | Sproutling | 0 |
| 2 | 🦂 Desert | Giant Scorpion | Cactopod | 10K |
| 3 | 🦖 Jungle | Giant Dino | Fernosaur | 500K |
| 4 | 🌋 Lava Fields | Lava Golem | Magmabloom | 5M |
| 5 | ❄️ Snow Peaks | Giant Yeti | Frostbulb | 50M |
| 6 | 👽 Deep Space | Big Alien | Starpetal | 500M |
| 7 | ⛩️ Spirit Garden (END) | Spirit Dragon | Lotus Wyrm | 5B |

The corridor is 10,900 studs long, so a run to the end takes about 64 s at the Spirit Garden's recommended Speed (WalkSpeed 172).

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
| 🌱 🪴 🧪 (right) | Seeds (incl. your 🎒 seed bag: **Plant** at your pad) / Plants / Potions menus |

## Seed packs
Our version of "eggs with odds". The 🛒 Shop opens on the **🎁 Seed Packs** tab:
- **One pack per zone.** It costs `PACK_INCOME_SECONDS` (240 s) of a Common zone-k plant's income, so $800 for Meadow, then $40K, $400K, $4M, $40M, $400M and $4B. A zone's pack unlocks at the zone's recommended Speed. It rolls like a daytime pod in that zone, and the loot table in the UI comes from the same function the server rolls with (`SeedPacks.odds`). Mutations are Gold 4% and Rainbow 1%. Night never rolls from packs.
- **Featured pack.** It rotates every 3 h on `os.time`, so every server shows the same pack with the same countdown. Zones come in shuffled cycles: each zone once per cycle, never twice in a row. It costs 1.5× its zone pack, has no Speed gate, rolls with night luck and doubled mutation chances, and is the only source of the exclusive **🌟 Celestial** mutation (0.5%, ×12 income). The UI shows a NEW! badge, a shine and a live countdown. Buying with a stale menu after a rotation is refused.
- **Where the seed goes.** Into a persisted **seed bag** (`profile.seedBag`, stacks by `zone:rarity[:Mutation]`, at most `SEED_BAG_MAX` = 50 from money). Plant from the 🌱 Seeds menu while standing on your pad. It follows the same rules as a carried seed: your plot, near the pad, a free slot. The pad prompt still plants carried seeds.
- **Reveal.** A reel spins through candidate seeds, lands on the server's result and bursts in its rarity colour. Bundles show every result.
- **Robux.** `Config.DEVELOPER_PRODUCTS` holds 1/3/10 featured-pack bundles as stubs (`id = 0`, shown greyed out as "Coming soon"). Put real developer product ids in to enable them. `ProcessReceipt` grants once per `PurchaseId` (ids are kept in the profile), saves, and only then returns `PurchaseGranted`. If the save fails it returns `NotProcessedYet`, and a retry in the same session doesn't grant twice. Robux grants may pass the 50-seed cap up to `SEED_BAG_HARD_MAX`. Past that, a pack refunds its money price.

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
- Game Settings → Places → **Max Players = 8**, one plot each. A 9th player is kicked with a "server full" message.
- Gamepasses are stubs. Put real ids in `Config.GAMEPASSES` to turn them on.
- Seed-pack bundles are developer-product stubs. Create 3 developer products and put their ids in `Config.DEVELOPER_PRODUCTS`.

### Manual acceptance test (Studio → Test → Local Server, 2 players)
1. Both players spawn on their own plot. The sign shows "🏠 Name's Plot".
2. Each player walks into the corridor, steals a Meadow seed (E), gets chased, gets home and plants it on the pad. `+$` popups appear.
3. Stand on the treadmill: Speed climbs even when AFK.
4. Buy Speed with **+**, then try the Desert both below and above 10K Speed. Below: caught, seed back at the nest, knocked back. Above: you escape.
5. Both players leave, then rejoin: money, Speed, plants and Index are intact (API access must be on).
6. Shop → 🎁 Seed Packs: buy a Meadow pack. The reel spins and lands, and the seed shows up in 🌱 Seeds → 🎒 bag. Stand on your pad and press Plant. Rejoin: the bag is intact.

## Rules the code enforces
- **Server-authoritative.** Money, Speed, pickup, carry, planting and purchases all live on the server. The client only draws the HUD and VFX and runs Slow Mode. Every prompt and remote re-checks distance, ownership and state, and remotes are rate-limited.
- **Speed stat vs WalkSpeed.** `WalkSpeed = clamp(16 + 16*log10(1+Speed), 16, 180)`. Zones compare the *stat*.
- **Speed from moving** (`SpeedService` + `SpeedLogic`). Every 0.25 s the server measures horizontal HumanoidRootPart movement and grants `distance × gainRate × multipliers`, capped per tick.
- **Movement sanity check.** A tick that moves more than `WalkSpeed × dt × 1.5 + 2` earns nothing. Sustained over-speed that drains a one-second movement budget, or any teleport-sized jump, is rubber-banded to the last valid position. Server-side moves (spawn, knockback) reset the tracker.
- **Treadmill.** The server checks whether the root part is inside the belt's bounds and grants the full walking rate for the tick × the tier (2×, or 3×/5× from the shop). The belt is a conveyor that pushes you against a stop rail, so AFK works. It has the same per-tick cap. There is no client remote.
- **Guards** (`GuardService` + `GuardBrain`). A guard wakes the moment a seed is taken and chases at `walkSpeedFor(zone.req) × 0.9`. A server loop calls `Humanoid:MoveTo` along the corridor at 10 Hz, with no pathfinding. A catch is horizontal distance < 6 studs, never `Touched`. The seed goes back to its pod, and the player is knocked 30 studs away and frozen for 1 s. The chase ends when the thief reaches the base, after a catch, or after 45 s, and then the guard walks home and sleeps.
- **Carry.** One seed at a time, a server-made part welded to your back. Dying or leaving returns it to its pod.
- **Growth.** Only `plantedAt` is saved. `weight = sprout × variance × (1 + 4·ease(age/20 min))` grows to 5× and stops. `income = seedIncome(zone) × rarity × mutation × sqrt(weight/sprout)`. A single 3 s payout loop evaluates the formula. There is no per-plant tick.
- **Economy** is formulas in `Config`. `speedCost(n) = n × $1`. `seedIncome(k) = req[k+1] / (10 slots × 300 s)`, so a full plot of zone-k Commons pays for zone k+1 in about 5 minutes. Upgrades are priced geometrically.
- **Data** (`ProfileStore`, format v2). `UpdateAsync` with retries and exponential backoff, autosave every 90 s, `BindToClose`. If a load fails, that session never saves, so it can't overwrite real data with defaults. Saved fields: money, Speed, multiplier tiers, slots, plants (slot, zone, rarity, mutation, plantedAt), Index, items, potion expiries, the seed bag, the last 100 Robux receipt ids and `lastSeen`. v1 saves load with an empty bag and no receipts. Offline income is capped at 1 h.
- **Art.** Everything is built from primitives by `WorldBuilder` (base, plots), `ZoneThemes` (the 7 zones) and the `Props` kit. Only floors, walls and the wall-flush arch pillars collide. All props are anchored and non-colliding (no Touched, no raycasts), so they never block runners, guards or the camera. The corridor is about 3.5k parts and the whole map about 4.9k (tested below 6k/8k). Day/night lighting blends a warm day look into a blue, readable night (`Config.nightBlend`), and the client adds a per-zone colour grade.

### Soft gates: how soft they are
The 0.9 factor applies to *WalkSpeed*, which is logarithmic in Speed, so the Speed you actually need to outrun a guard is well below the sign's number:

| Zone | Recommended | Outruns the guard from |
|---|---|---|
| Desert | 10K | ~3.2K (32%) |
| Jungle | 500K | ~107K (21%) |
| Lava | 5M | ~850K (17%) |
| Snow | 50M | ~6.8M (13%) |
| Deep Space | 500M | ~54M (11%) |
| Spirit Garden | 5B | ~430M (9%) |

At the top end, the previous zone's recommended Speed is already (almost) enough. The tests print this table. For tighter gates, raise `Config.GUARD_SPEED_FACTOR`. At 0.95 you need about 56% of the sign in the Desert and 32% in the Spirit Garden. Keep it below 1, or players at exactly the recommended Speed get caught.

## Layout
| Path | Roblox location | What |
|---|---|---|
| `src/shared/Config.luau` | `ReplicatedStorage.Shared` | All tuning: zones, rarities, mutations, economy/growth formulas, shop prices, day/night |
| `src/shared/Format.luau` | `ReplicatedStorage.Shared` | `1.2K / 3.4M / 5B / 7.5T / 3Qa`, `2,018,798 Kg`, `m:ss` |
| `src/shared/SeedPacks.luau` | 〃 | *Pure*: pack prices, odds tables, rolls, featured rotation, seed-bag keys |
| `src/server/Main.server.luau` | `ServerScriptService.Server` | Bootstrap: collision groups, world, services, join/leave, autosave, BindToClose |
| `src/server/Net.luau` | 〃 | Creates the fixed remotes |
| `src/server/Sessions.luau` | 〃 | Per-player runtime state, multipliers, StatsUpdate + leaderstats |
| `src/server/WorldBuilder.luau` | 〃 | Builds the map from primitives: base, 8 plots + treadmills, zone arches + signs, nests, the End |
| `src/server/ZoneThemes.luau` | 〃 | Per-zone floor, walls, props and particle ambience for the 7 zones |
| `src/server/Props.luau` | 〃 | Primitive kit (blocks, ellipsoids, overlays, lights, emitters) and reusable props |
| `src/server/SpeedLogic.luau` | 〃 | *Pure*: per-tick gain, cap, treadmill, sanity check |
| `src/server/SpeedService.luau` | 〃 | 0.25 s loop: applies SpeedLogic, WalkSpeed, rubber-band, End of the Line |
| `src/server/GuardBrain.luau` | 〃 | *Pure*: guard state machine (sleep/wake/chase/catch/return/stun/dust) |
| `src/server/GuardService.luau` | 〃 | Builds the giants, 10 Hz MoveTo loop, catches, bat, Sleep Dust |
| `src/server/SeedService.luau` | 〃 | Nests, pods, steal prompts, carry weld, return/regrow |
| `src/server/PlotService.luau` | 〃 | Plot assignment, planting, plant-creatures, growth, payouts, offline income |
| `src/server/Shop.luau` | 〃 | *Pure*: purchase rules, seed-pack purchases, idempotent Robux receipt grants |
| `src/server/ShopService.luau` | 〃 | `RequestBuy` / `RequestUseItem`, potions, seed packs, gamepass + developer-product stubs, `ProcessReceipt` |
| `src/server/ProfileStore.luau` | 〃 | Save format, validation, DataStore wrapper |
| `src/server/AmbientService.luau` | 〃 | Day/night lighting, "Fastest here" board |
| `src/client/HUD.client.luau` | `StarterPlayerScripts.Client` | All UI, Slow Mode |
| `src/client/Effects.client.luau` | 〃 | Income popups, sounds, shake, belt scroll, rainbow mutation, owner-only prompts, per-zone colour grade |
| `tests/` | — | Lune harness + specs (guard, speed, data, economy, world, packs) |

## Networking
`ReplicatedStorage.Remotes`:
- Client → server: `RequestBuy(itemId)`, `RequestUseItem(itemId)`.
  - `RequestBuy` ids: shop items, `Pass:<name>`, `Pack:<zoneId>`, `Pack:Featured:<slot>`, `Product:<name>`. Pack buys also have a 0.6 s per-player cooldown.
  - `RequestUseItem` ids: `Bat`, `SleepDust`, potions, `Seed:<bagKey>` (plant from the seed bag).
- Server → client: `StatsUpdate(partialStats)` (the client merges it), `LootEvent(kind, data)`, `IncomePopup(amount, position)`. Pack openings are `LootEvent("PackRoll", { packId, name, zone, featured, results })`.
- Stealing, planting and removing plants use server-side ProximityPrompts. Day/night is computed from the shared clock (`Config.dayPhase`), so it needs no remote.

## Known limits
- **Not playtested in Studio yet.** The instance code (world, guard humanoids, prompts, UI) compiles and type-checks against the Roblox API definitions. Only the pure logic is covered by tests.
- No DataStore session locking. Rejoining a different server within seconds can load a save that is up to one autosave old.
- The guards are welded primitives that glide, with no walk animation. The world art is built from primitives and built-in `rbxasset://` particle textures, with no uploaded assets.
