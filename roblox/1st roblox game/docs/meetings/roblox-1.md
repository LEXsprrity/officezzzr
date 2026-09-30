# Meeting: roblox-1, making a Roblox game

**Outcome:** "Coin Rush", a small round-based coin-collecting game written in Luau as a Rojo 7 project. It builds cleanly. The server logic passes a mocked test run, but no one has played it in Roblox Studio yet.

## The game
- Waiting (until `MIN_PLAYERS`), then Intermission (10s), then Round (60s), then back again.
- During a round, neon coins spawn at random on a 256×256 baseplate, up to 40 at a time. A normal coin gives +1 and a gold coin (10%) gives +5.
- The top scorer gets +1 `Wins`, and the round's `Coins` reset. All scoring happens on the server; the client only draws the HUD and effects.

## Who did what
| Who | Files | What |
|---|---|---|
| Lead | the plan, this doc | Split the work around a shared contract: Rojo mapping, `Config` keys, 3 server→client RemoteEvents, leaderstats, the `workspace.Coins` folder. Merged, reviewed and tested the result. |
| Engineer 1 | `default.project.json`, `src/shared/Config.luau`, `src/server/Main.server.luau`, `src/server/CoinSpawner.luau`, `src/server/RoundManager.luau` | Project and world (Baseplate, SpawnLocation, lighting). Main creates the Remotes, leaderstats, the Coins folder and runs the state loop. The spawner has start/stop/clear, a per-coin debounce and checks for a living player's character. RoundManager picks the winner, awards Wins and resets scores. |
| Engineer 2 | `src/client/HUD.client.luau`, `src/client/Effects.client.luau`, `README.md` | The HUD is built in code: a state/timer label, a coin counter bound to `leaderstats.Coins`, and a 4s winner banner. Effects: a "+N" billboard popup (tweened) and a local spin/bob for coins. README: build steps and layout. |

## Integration review (Lead)
- The contract was honoured on both sides: remote names and argument order, the `Coin` Part with its `Value` attribute, and `leaderstats.Coins/Wins`.
- The two engineers' requests of each other were already met:
  - Coins are `Anchored = true`, as the client spin/bob needs.
  - `workspace.Coins` is created at server startup.
  - `RoundManager.luau` exists, so the README row for it is correct.
- Additions by Engineer 1, both fine:
  - Late joiners get the current state immediately.
  - Waiting fires once with `timeLeft = 0`.
- **No code changes were needed at merge.**

## How it was checked
No Roblox tooling was installed, so the Lead downloaded the release binaries (Rojo 7.7.0, Luau) into a temporary folder outside the repo.
- `rojo build -o CoinRush.rbxlx` succeeded. The built tree is correct:
  - `ReplicatedStorage.Shared.Config` is a ModuleScript.
  - `ServerScriptService.Server` has `Main` as a Script, with `CoinSpawner` and `RoundManager` as ModuleScripts.
  - `StarterPlayerScripts.Client` has `HUD` and `Effects` as LocalScripts.
  - Workspace has the Baseplate and SpawnLocation.
- `luau-compile` compiled all 6 `.luau` files with no errors.
- **Behaviour test, 20/20 passing.** `CoinSpawner` and `RoundManager` were run under `luau.exe` with mocked Roblox APIs. It covers:
  - Config values match the contract, and the table is frozen.
  - Spawning is capped at MAX_COINS, and the coin shape (name, Value, anchored) is right.
  - A touch gives +1, fires `CoinCollected` to that player and destroys the coin. The debounce stops a second player collecting the same coin.
  - Touches by non-characters and dead players are ignored.
  - A gold coin gives +5.
  - After stop there are no spawns and no pickups, and clear empties the folder.
  - The winner gets +1 Wins and `RoundEnded(name, score)` fires to all. When every score is 0 there is no winner. Scores reset.
- **Not checked:**
  - A real Studio play test.
  - The client scripts' behaviour (compile-checked only).
  - `luau-analyze` strict type checking, which needs Roblox type definitions.

## Follow-ups (optional)
- Play test in Studio with 2 players (Studio > Test > Local Server).
- Set `PICKUP_SOUND_ID` in `Effects.client.luau` to enable the pickup sound.
- Add `selene`/`luau-lsp` and a `DataStore` so Wins persist between sessions.
- Nothing was committed, as instructed. The new files are untracked.
