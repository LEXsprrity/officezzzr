# Decision: Roblox game prompt ("Steal a Seed")

Meeting 7fad5600: Chair, Pragmatist, Skeptic. 3 rounds.

## Decided
- **Theme: "Steal a Seed".** The vote was 2–1 (Chair and Skeptic; the Pragmatist voted for Relic).
  - Seeds hatch into a plant-creature that has a weight. That gives the "hatch into something alive" payoff the user liked in Steal an Egg, and the grow hook from Grow a Garden / grow-your-tongue.
  - **Condition, from the Skeptic:** growth is computed from a `plantedAt` timestamp and never simulated tick by tick.
  - **Compromise, from the Pragmatist:** in P1 a plant sprouts at a fixed weight. Growth over time comes in P2.
- **Build on this repo.** Replace Coin Rush but keep its Rojo 7 layout (`src/server|client|shared`). All tuning goes in `Config.luau` and the map is generated in code.
- **Hard rules** (all three agreed):
  - Everything is server-authoritative.
  - The displayed Speed stat is separate from WalkSpeed.
  - Gates are soft and are enforced by guard speed.
  - Guards chase with MoveTo along the corridor axis and catch with a distance check.
  - The server detects the treadmill from where the player stands. The client never claims it.
- **Treadmill, Slow Mode and buying speed are all in P1.** The user asked for them explicitly and they are cheap.
- **Deferred:** PvP stealing from other bases (P3+ at the earliest) and anything monetization beyond P3 stubs.

## Options that lost
- **"Heist Line" / "Steal a Relic"** (Pragmatist; Skeptic's first idea). A statue loot is simpler and the fiction fits, but it's static: no hatch/grow payoff, and it's more generic. **It's the fallback** if growth turns out to cost too much.
- **Growth in P1** (Chair's first plan). It would double the size of the slice, so it moved to P2.
- **PathfindingService for guards.** The corridor is straight, so it's slow for no benefit.
- **`Touched` for catches.** It misses contacts at high speed.
- **A client `ToggleTreadmill` remote.** Players could exploit it.
- **7 rarities + 3 mutations up front.** Scope creep: 5 rarities come in P2, mutations in P3.
- **Hard walls on the zone gates.** The reference game says "recommended", so the gates are soft.

## Still open
- The economy constants below are starting points. They need a balance pass once P2 plays.
- Night-time faster guards: only if escape stays possible at the recommended speed. Decide in P3.
- PvP base stealing: revisit after P3.
- Nobody can playtest in Studio here. The user has to run the 2-player Local Server test by hand.

---

## THE PROMPT (paste this to the engineers)

> Build a Roblox game, **"Steal a Seed"**, in Luau on top of this repo. Keep its Rojo 7 structure (`src/server`, `src/client`, `src/shared`, `default.project.json`). It replaces the Coin Rush game. It's in the same genre as "Steal an Egg" and the "grow your tongue" games, but it is not a copy.
>
> **Pitch.** Players have fenced base plots (house-icon billboard, max 8 players per server = 8 plots). From spawn, one long walled corridor runs through themed zones. Each zone has a **sleeping giant guardian** next to a glowing mother-plant with seed pods. You grab a seed, the guardian wakes and chases you, and you run back and plant it on your plot. It sprouts into a **plant-creature** with a weight ("2,018,798 Kg") that earns money ("+$1.2M" popups). Money buys speed, speed reaches further zones, better zones give better seeds. **The goal is to reach the end of the line.**
>
> **Zones** (a sign in each shows the recommended Speed): Meadow 0 → Desert/scorpion 10K → Jungle/dino 500K → Lava/golem 5M → Snow/yeti 50M → Deep Space/alien 500M → Spirit Garden torii/dragon 5B (END). Corridor about 10–12k studs, so a run to the end at max WalkSpeed takes 60–90 s. Turn on `StreamingEnabled` with a large enough radius.
>
> **Rules (non-negotiable)**
> - **Server-authoritative:** money, speed, pickup, carry, planting and purchases all live on the server. The client does only HUD, VFX and Slow Mode. The server re-checks distance and state on every request, and no client-claimed state is trusted.
> - **Speed stat vs WalkSpeed:** Speed is a big number (a double, formatted K/M/B/T/Qa). WalkSpeed = `clamp(16 + a*log10(1+Speed), 16, ~180)`. Zones compare the *stat*.
> - **Speed from moving:** each tick (for example every 0.25 s) the server measures HumanoidRootPart distance moved and grants `distance × gainRate × multipliers`, capped per tick.
> - **Movement sanity check:** if distance per tick is greater than WalkSpeed × dt × slack, ignore the gain or rubber-band the player. This stops speed hacks from skipping gates.
> - **Treadmill at base:** the server detects that the root part is inside the treadmill's bounds and grants the walking rate × the tier (**2×** at start; 3×/5× in the shop). The belt moves the player in place. AFK use is allowed but capped per tick. There is no client remote for it.
> - **Soft gates, enforced by the guard:**
>   - guard chase speed = `WalkSpeedFor(zoneRecommended) × 0.9`
>   - At or above the recommended speed you escape. Below it you get caught.
>   - The guard wakes the moment a seed is taken and chases however slowly you move.
>   - Chase = a server loop calling `Humanoid:MoveTo` along the corridor axis at about 10 Hz. **No PathfindingService.**
>   - **Catch = distance < ~6 studs** (not `Touched`). A catch drops the seed back at the nest and knocks the player back; they don't die.
>   - The guard goes back to sleep after the chase ends or times out.
> - **Carry:** one seed at a time, welded to the back, server-owned. Picking up and planting happen via server-side ProximityPrompts.
> - **Plot cap:** 10 plant slots to start, more buyable in the shop.
> - **Growth (P2):** store `plantedAt`. `weight = f(now − plantedAt, rarity)` up to a cap. Income = f(rarity, weight). Never loop a tick per plant, and save only the timestamp.
> - **Slow Mode toggle** (local): clamps your WalkSpeed to 16 so you can move around your base.
> - **Economy lives in Config as formulas**, for example:
>   - `speedCost(amount) = amount × pricePerSpeed`
>   - `seedIncome(zone k) ≈ zoneReq[k+1] × pricePerSpeed / (slots × 300 s)`, so a plot full of zone-k plants pays for the next zone in about 5 minutes
>   - speed multipliers and treadmill tiers priced geometrically
> - **Data:** DataStore with `UpdateAsync`, retries, autosave every 60–120 s, `BindToClose`. Save money, speed, multipliers, treadmill tier, slots, plants (id, rarity, `plantedAt`) and the index.
> - **Art:** placeholder primitives (colored parts, BillboardGui names, glow for rare items). No free models with scripts.
>
> **UI:**
> - Bottom-left: Speed with a + button, and money.
> - Shop and Index buttons.
> - Slow Mode toggle.
> - Right side: seeds, plants and potion menus.
> - Bottom-right: potion timer and day/night timer.
> - Hotbar: a bat and a consumable (x3).
> - Bright, blocky style.
>
> **Remotes** (fix them up front):
> - Client→server: `RequestBuy(itemId)`, `RequestUseItem(itemId)`.
> - Server→client: `StatsUpdate(stats)`, `LootEvent(kind, data)`, `IncomePopup(amount, position)`.
> - Pickup and planting use ProximityPrompts.
>
> **Phases (finish and verify each before starting the next)**
> 1. **P1 slice (~1–1.5k lines):**
>    - 8 plots
>    - corridor with the first 3 zones, 1 guard and 1 seed type each
>    - steal → chase → carry → plant (sprouts at a fixed weight) → $/s
>    - speed from moving, treadmill 2×, + button to buy speed
>    - Slow Mode
>    - save/load
>    - No offline earnings.
> 2. **P2:**
>    - all 7 zones + signs
>    - 5 rarities with spawn weights per zone
>    - timestamp-based growth
>    - Shop (speed, multipliers, treadmill 3×/5×, slots, "Sleep Dust" = guard stays asleep 5 s longer)
>    - Index (collection book)
>    - capped offline income (max 1 h)
>    - the bat stuns a guard for 2 s
> 3. **P3:**
>    - day/night cycle with timer (night = rarer seeds / Night mutation)
>    - potion boosts with timer
>    - mutations (Gold/Rainbow) with glow VFX
>    - sounds, leaderboard, gamepass stubs (2× money, extra slots)
>
> **Done means:**
> - `rojo build` succeeds, `luau-compile` passes, and the mocked server tests pass. The tests cover:
>   - a player at the recommended speed escapes the guard; one below it gets caught
>   - the treadmill gives exactly 2× the walking gain
>   - speed gain is capped per tick
>   - save and load round-trip correctly
> - Then the user runs a **2-player Local Server test** in Studio: both players steal, both get chased, both plant, both leave and rejoin with their progress intact.
