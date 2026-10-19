--!strict
-- The Halloween event (owner 2026-10-19: "evento de halloween sim", the map stays as it is). While it runs:
--   * CANDY lies all over the map (Server/CandyService): candy corn spread along the corridor and the base's
--     walkway; walking over one picks it up (no click), CANDY_VALUE candy, and another appears somewhere
--     else a little later (owner 2026-10-19: "people walk over them ... you dont need to click");
--   * the Shop's HALLOWEEN card sells Haunted seeds for candy: PULL_PRICE for one, TEN_PRICE for ten (owner:
--     "50 candys for 1 single pull and 500 for 10 pulls"), of the deepest zone the player's Speed reaches,
--     always with the Haunted mutation (x5 income, a spooky look), which pods never roll (SeedPacks.hauntedPack);
--   * the HUD shows a Candy button with the player's candy.
-- After END the candy is gone, nobody earns or spends any more and the card and the button are gone; Haunted
-- plants stay forever (a rare trophy of the event). Pure and shared: the server runs by it, the client shows
-- the same numbers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Halloween = {}

Halloween.START = 1792368000 -- 2026-10-19 00:00 UTC
Halloween.END = 1793577600 -- 2026-11-02 00:00 UTC
Halloween.MUTATION = "Haunted"
Halloween.CANDY_MAX = 1e9 -- a save never holds more
Halloween.PULL_PRICE = 50 -- one Haunted seed
Halloween.TEN_PRICE = 500 -- ten of them
Halloween.PULLS = { 1, 10 } -- the card's two buttons
-- The Haunted seed's Legendary chance: this many times its zone's pod chance (Config.LEGENDARY_CHANCE).
Halloween.LEGENDARY_MULT = 2

-- The candy on the map (Server/CandyService): CANDY_CORRIDOR pieces along the corridor (spread evenly over
-- its length, so the longer zones hold more) and CANDY_BASE on the base's walkway, each worth CANDY_VALUE.
-- One picked up comes back somewhere else after CANDY_RESPAWN seconds. A player picks up the candy within
-- CANDY_RADIUS studs (flat) of where the server trusts them to be.
Halloween.CANDY_CORRIDOR = 80
Halloween.CANDY_BASE = 10
Halloween.CANDY_VALUE = 1
Halloween.CANDY_RESPAWN = 20
Halloween.CANDY_RADIUS = 5
Halloween.CANDY_SIZE = Vector3.new(2.4, 3, 2.4) -- what a piece fits in (studs)
Halloween.NEST_CLEARANCE = 36 -- no candy this close to a sleeping boss (flat studs from its nest's centre)

function Halloween.active(now: number): boolean
	return now >= Halloween.START and now < Halloween.END
end

-- The candy price of `count` Haunted seeds (1 or 10), or nil for any other count.
function Halloween.price(count: number): number?
	if count == 1 then
		return Halloween.PULL_PRICE
	elseif count == 10 then
		return Halloween.TEN_PRICE
	end
	return nil
end

-- The zone whose Haunted seed the player may buy: the deepest one their Speed reaches (its recommended Speed).
function Halloween.bestZone(speed: number): number
	local best = 1
	for k, zone in Config.ZONES do
		if speed >= zone.req then
			best = k
		end
	end
	return best
end

-- Where the base's walkway runs (x from its far end to the corridor mouth, |z| within it).
function Halloween.baseRange(): (number, number, number)
	local lastCol = (Config.MAX_PLAYERS + 1 - 1) // 2 -- the plots' and the plaza's spots, column by column
	local far = Config.PLOT_FIRST_X - lastCol * Config.PLOT_SPACING_X - Config.PLOT_SIZE / 2
	return far + 8, Config.CORRIDOR_START_X - 4, Config.WALKWAY_WIDTH / 2 - 4
end

-- A candidate spot (x, z on the ground) for a piece of candy, drawn with `rng` (() -> [0, 1)): in the base
-- (`inBase`) somewhere on the walkway, else anywhere in the corridor away from its walls and the nests.
-- CandyService still checks the ground there is clear (no prop on it) and draws again if not.
function Halloween.spot(inBase: boolean, rng: () -> number): Vector3
	if inBase then
		local x0, x1, half = Halloween.baseRange()
		return Vector3.new(x0 + rng() * (x1 - x0), Config.GROUND_Y, (rng() * 2 - 1) * half)
	end
	local half = Config.CORRIDOR_WIDTH / 2 - 12
	for _ = 1, 20 do
		local x = Config.CORRIDOR_START_X + 8 + rng() * (Config.END_X - Config.CORRIDOR_START_X - 16)
		local p = Vector3.new(x, Config.GROUND_Y, (rng() * 2 - 1) * half)
		if not Halloween.nearNest(p) then
			return p
		end
	end
	return Vector3.new(Config.CORRIDOR_START_X + 20, Config.GROUND_Y, 0)
end

-- Whether `p` is within NEST_CLEARANCE (flat) of a zone's nest, where its boss sleeps.
function Halloween.nearNest(p: Vector3): boolean
	for k = 1, #Config.ZONES do
		local c = Config.nestCenter(k)
		local home = c + Vector3.new(Config.GUARD_HOME_OFFSET, 0, 0)
		for _, q in { c, home } do
			if Vector3.new(p.X - q.X, 0, p.Z - q.Z).Magnitude < Halloween.NEST_CLEARANCE then
				return true
			end
		end
	end
	return false
end

-- "2 days left", "5 h left", "20 min left": how long the event still runs.
function Halloween.timeLeft(now: number): string
	local left = math.max(Halloween.END - now, 0)
	if left >= 2 * 86400 then
		return `{math.floor(left / 86400)} days left`
	elseif left >= 3600 then
		return `{math.floor(left / 3600)} h left`
	end
	return `{math.max(math.ceil(left / 60), 1)} min left`
end

return Halloween
