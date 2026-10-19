--!strict
-- The Halloween event (owner 2026-10-19: "evento de halloween sim", the map stays as it is). While it runs:
--   * players earn CANDY: CANDY_PER_MINUTE for every minute in the game, and the zone's number for every
--     stolen seed brought home (a Meadow seed 1, a Spirit Garden seed 7);
--   * the Shop's HALLOWEEN card sells a Haunted seed for candy (SeedPacks.hauntedPack): a seed of the
--     deepest zone the player's Speed reaches, always with the Haunted mutation (x5 income, a spooky look),
--     which pods never roll (Config.MUTATIONS: exclusive);
--   * the HUD shows a Candy button with the player's candy.
-- After END nobody earns or spends candy and the card and the button are gone; Haunted plants stay forever
-- (a rare trophy of the event). Pure and shared: the server grants by it, the client shows the same numbers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Halloween = {}

Halloween.START = 1792368000 -- 2026-10-19 00:00 UTC
Halloween.END = 1793577600 -- 2026-11-02 00:00 UTC
Halloween.MUTATION = "Haunted"
Halloween.CANDY_PER_MINUTE = 1
Halloween.CANDY_MAX = 1e9 -- a save never holds more
-- What a Haunted seed costs in candy, by zone (Config.ZONES order). A new player's first one (the Meadow)
-- comes after about 7 minutes of play and a few Meadow steals.
Halloween.PRICES = { 10, 15, 20, 30, 40, 50, 60 }
-- The Haunted seed's Legendary chance: this many times its zone's pod chance (Config.LEGENDARY_CHANCE).
Halloween.LEGENDARY_MULT = 2

function Halloween.active(now: number): boolean
	return now >= Halloween.START and now < Halloween.END
end

-- Candy for bringing a stolen seed of zone `zone` home.
function Halloween.stealCandy(zone: number): number
	return math.clamp(math.floor(zone), 1, #Config.ZONES)
end

-- The candy price of zone `zone`'s Haunted seed.
function Halloween.price(zone: number): number
	return Halloween.PRICES[zone] or Halloween.PRICES[#Halloween.PRICES]
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
