--!strict
-- The Halloween event (owner 2026-10-19: "evento de halloween sim", the map stays as it is). While it runs:
--   * CANDY lies in the corridor (Server/CandyService): candy corn appearing here and there, never in the
--     base; walking over one picks it up (no click), CANDY_VALUE candy (owner 2026-10-19: "people walk over
--     them ... you dont need to click", then "none spawning in base", "only 25 per 5 minutes");
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
-- The Haunted seed's Legendary chance, the same in every zone (owner 2026-10-19: 2x the zone's pod chance left
-- the Spirit Garden at 0.08%, "just crazy"; make it 2%).
Halloween.LEGENDARY_CHANCE = 0.02

-- The candy on the map (Server/CandyService), only in the corridor (spread evenly over its length, so the
-- longer zones hold more): CANDY_START pieces when the server starts, then one more every CANDY_EVERY
-- seconds (25 per 5 minutes, owner 2026-10-19) while fewer than CANDY_ON_MAP lie there; picked-up pieces
-- don't come back by themselves. Each is worth CANDY_VALUE. A player picks up the candy within CANDY_RADIUS
-- studs (flat) of where the server trusts them to be.
Halloween.CANDY_START = 20
Halloween.CANDY_EVERY = 12
Halloween.CANDY_ON_MAP = 50 -- (owner 2026-10-19: "50 candys max spread around map instead of 25")
Halloween.CANDY_VALUE = 1
Halloween.CANDY_RADIUS = 5
-- The owner's candy corn (Creator Store "Candy corn", in their inventory): loaded with InsertService when
-- assets/Candy.rbxm isn't there; the built-in candy corn when neither works.
Halloween.CANDY_ASSET = 72225906081888
Halloween.CANDY_SIZE = Vector3.new(2.4, 3, 2.4) -- what a piece fits in (studs)
Halloween.NEST_CLEARANCE = 36 -- no candy this close to a sleeping boss (flat studs from its nest's centre)

-- The HAUNTED SET (owner 2026-10-19: "do what u did to pyronis in like 6 other legendarys, 10 epics, 10 rares,
-- 10 uncommons, 10 commons"): the plant models (assets/Creature_<Seed>.rbxm, by zone and rarity) a Haunted
-- seed grows into, the most detailed ones (particles, glow, beams) with a spooky bent. A Haunted seed's gene
-- picks among its zone and rarity's list here (flowerOf), never among the other models; every zone has at
-- least TWO of every rarity (owner 2026-10-19: the Shop card turns through them, 5 s each; but the Desert has
-- one Legendary, Helios: its other, Aetheris, turns to mush), 3 Spirit Epics
-- (both Duality plants): 14 Commons, Uncommons and Rares, 15 Epics, 13 Legendaries (first 10/10/10/10/7: new ones
-- were added at the end of each list, so seeds already in bags mostly keep their flower);
-- tests/halloween.spec checks the counts and that every name exists.
-- The order is the gene's: don't reorder a list (planted plants keep their flower by name, but a seed in a
-- bag would grow into another one).
Halloween.SET = {
	[1] = { -- Meadow
		Common = { "Daisy", "Tulip" },
		Uncommon = { "Pansy", "Rose" },
		Rare = { "Hellebore", "Orchid", "Mafioso", "Sunfloris" },
		Epic = { "Ballerina" }, -- (the Meadow's only Epic)
		Legendary = { "Verdantis" }, -- (its only Legendary)
	},
	[2] = { -- Desert
		Common = { "Cactus", "Nuzwat" },
		Uncommon = { "DesertWildFlower", "ZebraFlower" },
		Rare = { "HaloOrchid", "RadianceLily" },
		Epic = { "MantisReaper", "Sahur" },
		Legendary = { "Helios" }, -- (its only other Legendary, Aetheris, turns all orange and green: mush)
	},
	[3] = { -- Jungle
		Common = { "BugEater", "ZombeeFlower" },
		Uncommon = { "Beenspector", "UnicornPetunia" },
		Rare = { "SpiderLilly", "OceanBloom" },
		Epic = { "GlowBerry", "Snapdragon", "Bombardiro", "Patapim" },
		Legendary = { "Paradoxys", "Venomyx" },
	},
	[4] = { -- Lava Fields
		Common = { "EmberSpark" }, -- (its only Common, Uncommon and Rare)
		Uncommon = { "Pomeflower" },
		Rare = { "Draconyx" },
		Epic = { "DarkflareRose", "RedStar", "FrostburnRose", "DragonFlower", "CrimsonWidow", "StrawberryElephant" },
		Legendary = { "Infernyx", "Coreflare" },
	},
	[5] = { -- Snow Peaks
		Common = { "HollyBloom", "IcecapBloom" },
		Uncommon = { "FrostLily", "WinterRose" },
		Rare = { "Glacierheart" }, -- (its only Rare)
		Epic = { "Mistletoe", "Snowpuff", "CrystalDaisy", "Trallalero", "Reindeer" },
		Legendary = { "Aracnid", "Frostwyrm" },
	},
	[6] = { -- Deep Space
		Common = { "NebulaRose", "EclipseBloom" },
		Uncommon = { "Voidbloom", "BorealBell" },
		Rare = { "Jellythys" }, -- (its only Rare)
		Epic = { "MeteorFlower", "Gleamblossom", "StarfallFlower", "TwilightAmarilis", "LaVaca" },
		Legendary = { "Stellaris", "Cybaris" },
	},
	[7] = { -- Spirit Garden
		Common = { "MoonlaceOrchid", "Camellia" },
		Uncommon = { "Crystalflower", "Whitenight" },
		Rare = { "BubbleLotus", "IvoryIris" },
		Epic = { "Ghostflower", "Ghostleaf", "Assassino", "DualityFlower", "DualityRose" },
		Legendary = { "Pyronis", "Cryonix" },
	},
} :: { [number]: { [string]: { string } } }

-- The Haunted set's models of (zone, rarity), in gene order (empty for an unknown zone or rarity).
function Halloween.setFlowers(zone: number, rarity: number): { string }
	local byRarity = Halloween.SET[zone]
	local r = Config.RARITIES[rarity]
	return if byRarity and r and byRarity[r.id] then byRarity[r.id] else {}
end

-- The flower a Haunted seed of (zone, rarity) with this gene grows into, picked like every seed's
-- (CreatureModels.variantOf: the gene wraps round the list) but among the set's models only; nil when the set
-- has none there. The server (CreatureModels.seedVariant) and the reveal reel (HUD) both pick by this.
function Halloween.flowerOf(zone: number, rarity: number, gene: number): string?
	local names = Halloween.setFlowers(zone, rarity)
	return if #names > 0 then names[(math.floor(gene) - 1) % #names + 1] else nil
end

-- The Haunted look of a plant model (the Pyronis thumbnail's recipe, owner 2026-10-19: "do what u did to
-- pyronis"): Neon parts glow toxic green, bright parts (red over 0.7) turn pumpkin orange, everything else
-- deep purple, and its particles and beams become orange-to-purple wisps. A model with too little bright
-- (under ORANGE_SHARE of its surface orange) would be a purple blob, so its brightest colours (by red, a whole
-- colour at a time, never past ORANGE_MAX of the surface) turn orange too; the Pyronis has enough and keeps
-- the plain recipe. Deterministic (by colour, whatever the parts' order), so the server's plant
-- (CreatureModels) and the HUD's 3D picture of it (FlowerView) match.
Halloween.ORANGE = Color3.fromRGB(255, 125, 20)
Halloween.PURPLE = Color3.fromRGB(95, 35, 150)
Halloween.GREEN = Color3.fromRGB(140, 255, 60)
Halloween.WISPS = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Halloween.ORANGE),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(190, 90, 255)),
	ColorSequenceKeypoint.new(1, Halloween.PURPLE),
})
Halloween.BRIGHT = 0.7 -- red above this: orange
Halloween.TO_ORANGE = 0.7 -- how far a bright part goes to orange
Halloween.TO_PURPLE = 0.75 -- ...and the rest to purple
Halloween.ORANGE_SHARE = 0.15
Halloween.ORANGE_MAX = 0.5

local function surface(p: BasePart): number
	local s = p.Size
	return if p.Transparency >= 0.95 then 0 else s.X * s.Y + s.Y * s.Z + s.X * s.Z
end

-- The colours (Color3:ToHex) of `parts` that turn orange.
function Halloween.orangeColors(parts: { BasePart }): { [string]: boolean }
	type Group = { color: Color3, hex: string, area: number }
	local groups: { Group } = {}
	local byHex: { [string]: Group } = {}
	local total, orange = 0, 0
	local out: { [string]: boolean } = {}
	for _, p in parts do
		local area = surface(p)
		total += area
		if p.Material == Enum.Material.Neon then
			continue
		end
		local hex = p.Color:ToHex()
		local g = byHex[hex]
		if not g then
			g = { color = p.Color, hex = hex, area = 0 }
			byHex[hex] = g
			table.insert(groups, g)
		end
		g.area += area
		if p.Color.R > Halloween.BRIGHT then
			out[hex] = true
			orange += area
		end
	end
	if orange >= Halloween.ORANGE_SHARE * total then
		return out
	end
	table.sort(groups, function(a, b)
		if a.color.R ~= b.color.R then
			return a.color.R > b.color.R
		end
		return a.hex > b.hex
	end)
	for _, g in groups do
		if orange >= Halloween.ORANGE_SHARE * total then
			break
		end
		if not out[g.hex] and orange + g.area <= Halloween.ORANGE_MAX * total then
			out[g.hex] = true
			orange += g.area
		end
	end
	return out
end

-- The attribute on the parts CreatureModels adds to a plant (its rarity halo, the jack-o'-lantern): not the
-- plant's own, so hauntify leaves them as they are (a preview of a plant has them too).
Halloween.FLAIR = "Flair"

-- Gives every part, particle emitter and beam under `root` the Haunted look (see above).
function Halloween.hauntify(root: Instance)
	local parts: { BasePart } = {}
	for _, d in root:GetDescendants() do
		if d:GetAttribute(Halloween.FLAIR) then
			continue
		elseif d:IsA("BasePart") then
			table.insert(parts, d)
		elseif d:IsA("ParticleEmitter") or d:IsA("Beam") then
			d.Color = Halloween.WISPS
		end
	end
	local orange = Halloween.orangeColors(parts)
	for _, p in parts do
		if p.Material == Enum.Material.Neon then
			p.Color = Halloween.GREEN
		elseif orange[p.Color:ToHex()] then
			p.Color = p.Color:Lerp(Halloween.ORANGE, Halloween.TO_ORANGE)
		else
			p.Color = p.Color:Lerp(Halloween.PURPLE, Halloween.TO_PURPLE)
		end
	end
end

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

-- A candidate spot (x, z on the ground) for a piece of candy, drawn with `rng` (() -> [0, 1)): anywhere in
-- the corridor (never the base) away from its walls and the nests. CandyService still checks the ground
-- there is clear (no prop on it) and draws again if not.
function Halloween.spot(rng: () -> number): Vector3
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
