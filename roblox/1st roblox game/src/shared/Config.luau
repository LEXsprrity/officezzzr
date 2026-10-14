--!strict
-- Steal a Seed: all tuning lives here, as data or as formulas. Server and client both read it.
local Config = {}

----------------------------------------------------------------------------------------------------
-- Server / world
----------------------------------------------------------------------------------------------------
Config.MAX_PLAYERS = 5 -- one plot each; also set Max Players = 5 in Game Settings
Config.PLOT_COLUMNS = math.ceil((Config.MAX_PLAYERS + 1) / 2) -- plots alternate sides of the walkway; +1 spot for the shop plaza
Config.TICK = 0.25 -- speed tracker tick (s)
Config.GUARD_HZ = 10 -- guard chase loop rate

-- Layout (studs). Base area is at -X, the corridor runs along +X.
Config.GROUND_Y = 0
Config.CORRIDOR_START_X = 60 -- anything with X below this is the safe base area
Config.CORRIDOR_WIDTH = 192 -- wide and open: a big flat field between two tall walls
Config.WALL_HEIGHT = 52
Config.PLOT_SIZE = 84
Config.PLOT_SPACING_X = 84 -- = PLOT_SIZE: neighbouring plots touch and share the fence between them
Config.PLOT_FIRST_X = -6 -- the front plots end 24 studs before the corridor mouth (room for the free chest)
Config.PLOT_OFFSET_Z = 84 -- plots sit at z = +/-84, the walkway runs down z = 0
Config.WALKWAY_WIDTH = 36 -- the sand walkway down z = 0; the 24 studs between it and a plot's front fence hold its treadmill
-- Inside a plot (owner's reference): two brown dirt beds, left and right, with a grass path down the middle
-- from the entrance. Players plant anywhere on their own beds (Shared/Planting).
Config.PLOT_PATH_WIDTH = 20 -- the grass path between the beds
Config.BED_FENCE_GAP = 1.5 -- from a bed's outer edges to the fence line
Config.BED_HEIGHT = 0.4 -- the beds stand this far above the plot's grass; plants stand on top
Config.SLOT_SPACING = 8 -- the default planting grid (old saves, auto-placing); creature sizes are budgeted against it
Config.PLANT_BED_MARGIN = 2 -- a plant's centre stays at least this far inside its bed
Config.PLANT_OVERLAP = 1 -- two full-grown neighbours may overlap this much (studs)
Config.PLANT_FENCE_OVERHANG = 1 -- a big full-grown plant may reach this far past its bed's fence gap (Planting.bedMargin)
Config.PLANT_REACH = 28 -- you plant within this many studs (flat) of where you stand

----------------------------------------------------------------------------------------------------
-- Speed stat -> WalkSpeed
----------------------------------------------------------------------------------------------------
Config.BASE_WALKSPEED = 16
Config.MAX_WALKSPEED = 180
-- WalkSpeed = 16 + a * log10(1 + Speed / pivot), clamped to [16, 180]. Moving faster as Speed grows is
-- the only thing Speed itself does for you: more studs per second, so more steps. Tuned so every zone's
-- recommended Speed runs about as fast as it did before the flat-gain rework (Desert ~80 up to the
-- Spirit Garden ~170), which the guards' head starts are balanced for (tests/guard.spec).
Config.WALKSPEED_LOG_SCALE = 27 -- "a"
Config.WALKSPEED_PIVOT = 100 -- the Speed where the log curve takes off
Config.SLOW_MODE_WALKSPEED = 16

function Config.walkSpeedFor(speed: number): number
	local s = if speed == speed then math.max(0, speed) else 0
	local w = Config.BASE_WALKSPEED + Config.WALKSPEED_LOG_SCALE * math.log10(1 + s / Config.WALKSPEED_PIVOT)
	return math.clamp(w, Config.BASE_WALKSPEED, Config.MAX_WALKSPEED)
end

-- Speed from moving: a flat BASE_SPEED_PER_STUD per stud walked ("per step"), times the equipped trail's
-- small multiplier (Config.speedPerStud), and on a treadmill times its tier too. Nothing grows with the
-- Speed you already have and there are no levels: a player progresses by running faster (WalkSpeed
-- above), better trails and treadmill tiers. Tuned with the free-player simulation in tests/progression_sim
-- (README "Progression").
Config.BASE_SPEED_PER_STUD = 1

Config.GAIN_CAP_STUDS_PER_TICK = Config.MAX_WALKSPEED * Config.TICK -- most studs one tick can pay for
Config.MOVE_SLACK = 1.5 -- per-tick distance allowed = WalkSpeed * dt * slack + epsilon
Config.MOVE_EPSILON = 2
Config.MOVE_BUCKET_SECONDS = 1 -- sustained over-speed beyond this much budget -> rubber-band

----------------------------------------------------------------------------------------------------
-- Zones. The corridor is the concatenation of zone lengths (2,300 studs). The first zone is the shortest so
-- a first seed is a quick grab; each next zone is ZONE_LENGTH_GROWTH times longer than the one before, up
-- to ZONE_LENGTH_MAX (about two corridor widths deep), and every later zone stays at the max:
-- 100, 200, 400, 400, 400, 400, 400.
----------------------------------------------------------------------------------------------------
Config.ZONE_LENGTH_BASE = 100
Config.ZONE_LENGTH_GROWTH = 2
Config.ZONE_LENGTH_MAX = 400

function Config.zoneLength(k: number): number
	return math.min(Config.ZONE_LENGTH_BASE * Config.ZONE_LENGTH_GROWTH ^ (k - 1), Config.ZONE_LENGTH_MAX)
end

export type Zone = {
	id: string,
	name: string,
	req: number, -- recommended Speed stat
	length: number,
	floor: Color3, -- corridor floor (ZoneThemes: flat studded plastic with a lighter checker over it)
	wall: Color3, -- side walls (with a lighter checker on their inner face)
	ui: Color3, -- saturated card colour for the HUD
	guard: string,
	guardColor: Color3,
	seed: string, -- creature name
	seedColor: Color3,
	baseWeight: number, -- Kg of a sprouted Common, before growth
	icon: string,
	active: "day" | "night", -- this zone's plants earn ACTIVE_TIME_MULT during that phase
	wakeDelay: number, -- seconds between a steal and the guard's chase (its "❗" state); see Guards below
}

Config.ZONES = {
	{ id = "Meadow", name = "Meadow", req = 0, length = Config.zoneLength(1), icon = "🌼", active = "day", wakeDelay = 0.5,
		floor = Color3.fromRGB(106, 196, 50), wall = Color3.fromRGB(196, 128, 80), ui = Color3.fromRGB(70, 180, 70),
		guard = "Giant Mole", guardColor = Color3.fromRGB(110, 80, 60),
		seed = "Sproutling", seedColor = Color3.fromRGB(120, 230, 90), baseWeight = 12 },
	{ id = "Desert", name = "Desert", req = 25e3, length = Config.zoneLength(2), icon = "🦂", active = "day", wakeDelay = 0,
		floor = Color3.fromRGB(240, 210, 140), wall = Color3.fromRGB(226, 178, 92), ui = Color3.fromRGB(225, 145, 55),
		guard = "Giant Scorpion", guardColor = Color3.fromRGB(190, 90, 40),
		seed = "Cactopod", seedColor = Color3.fromRGB(60, 170, 90), baseWeight = 340 },
	{ id = "Jungle", name = "Jungle", req = 500e3, length = Config.zoneLength(3), icon = "🦖", active = "night", wakeDelay = 0.1,
		floor = Color3.fromRGB(58, 168, 72), wall = Color3.fromRGB(72, 140, 74), ui = Color3.fromRGB(35, 140, 75),
		guard = "Giant Dino", guardColor = Color3.fromRGB(70, 150, 70),
		seed = "Fernosaur", seedColor = Color3.fromRGB(40, 200, 120), baseWeight = 9_500 },
	{ id = "Lava", name = "Lava Fields", req = 2e6, length = Config.zoneLength(4), icon = "🌋", active = "day", wakeDelay = 0.1,
		floor = Color3.fromRGB(92, 58, 66), wall = Color3.fromRGB(74, 48, 56), ui = Color3.fromRGB(225, 85, 30),
		guard = "Lava Golem", guardColor = Color3.fromRGB(240, 100, 30),
		seed = "Magmabloom", seedColor = Color3.fromRGB(255, 120, 40), baseWeight = 180_000 },
	{ id = "Snow", name = "Snow Peaks", req = 7.5e6, length = Config.zoneLength(5), icon = "❄️", active = "night", wakeDelay = 0.1,
		floor = Color3.fromRGB(232, 242, 255), wall = Color3.fromRGB(160, 208, 246), ui = Color3.fromRGB(65, 150, 225),
		guard = "Giant Yeti", guardColor = Color3.fromRGB(220, 230, 245),
		seed = "Frostbulb", seedColor = Color3.fromRGB(120, 200, 255), baseWeight = 2_000_000 },
	{ id = "Space", name = "Deep Space", req = 25e6, length = Config.zoneLength(6), icon = "👽", active = "night", wakeDelay = 0.1,
		floor = Color3.fromRGB(64, 48, 134), wall = Color3.fromRGB(48, 38, 104), ui = Color3.fromRGB(115, 75, 225),
		guard = "Big Alien", guardColor = Color3.fromRGB(120, 255, 120),
		seed = "Starpetal", seedColor = Color3.fromRGB(200, 120, 255), baseWeight = 45_000_000 },
	{ id = "Spirit", name = "Spirit Garden", req = 75e6, length = Config.zoneLength(7), icon = "⛩️", active = "day", wakeDelay = 0.1,
		floor = Color3.fromRGB(112, 200, 98), wall = Color3.fromRGB(140, 140, 210), ui = Color3.fromRGB(225, 75, 130),
		guard = "Spirit Dragon", guardColor = Color3.fromRGB(230, 50, 60),
		seed = "Lotus Wyrm", seedColor = Color3.fromRGB(255, 150, 200), baseWeight = 900_000_000 },
} :: { Zone }

-- Where each zone starts along X, the nest (mother plant) position, and the end of the line.
Config.NEST_FRACTION = 0.85 -- nest sits this far into its zone...
Config.GUARD_HOME_OFFSET = 24 -- the guard sleeps this many studs past the mother plant (+X)
Config.NEST_END_CLEARANCE = 12 -- ...but its guard sleeps at least this far before the zone's end (the short Meadow)

function Config.zoneStartX(k: number): number
	local x = Config.CORRIDOR_START_X
	for i = 1, k - 1 do
		x += Config.ZONES[i].length
	end
	return x
end

function Config.nestX(k: number): number
	local len = Config.ZONES[k].length
	return Config.zoneStartX(k) + math.min(len * Config.NEST_FRACTION, len - Config.GUARD_HOME_OFFSET - Config.NEST_END_CLEARANCE)
end

Config.END_X = Config.zoneStartX(#Config.ZONES + 1) -- far end of the corridor: the Spirit Garden's back wall (no finish line)

function Config.zoneAtX(x: number): number?
	if x < Config.CORRIDOR_START_X then
		return nil
	end
	for k = 1, #Config.ZONES do
		if x < Config.zoneStartX(k + 1) then
			return k
		end
	end
	return #Config.ZONES
end

----------------------------------------------------------------------------------------------------
-- Guards (soft gates)
----------------------------------------------------------------------------------------------------
-- The guard runs exactly as fast as a player at the zone's recommended Speed, so that player escapes on
-- the head start alone: the ~28 studs between the pods and the sleeping guard (GUARD_HOME_OFFSET), plus
-- the zone's wakeDelay. The delay is slack for reaction time and lag, but it also lets slower players
-- escape, and both trade against the run home: the shorter it is, the less a slower thief loses on the way.
-- With the zone lengths above, every zone gets about 0.3 s of slack (from the smallest delay that
-- gives it), and the lowest escaping Speed lands at ~50-70% of the sign (tests/guard.spec prints the
-- table; the recommended Speeds are only ~3-4x apart from the Lava Fields on, so a thief can't be far
-- below the sign). The Meadow (req 0) is the tutorial.
Config.GUARD_SPEED_FACTOR = 1 -- chase WalkSpeed = walkSpeedFor(zone.req) * this
Config.GUARD_RETURN_FACTOR = 0.6 -- walking home is slower than chasing
Config.CATCH_DISTANCE = 6 -- horizontal studs, root to root
Config.CHASE_TIMEOUT = 45
Config.GUARD_SCALE = 3 -- body size multiplier ("giant")
Config.KNOCKBACK_STUDS = 30
Config.CATCH_STUN = 1 -- seconds the caught player can't move

function Config.guardChaseSpeed(k: number): number
	return Config.walkSpeedFor(Config.ZONES[k].req) * Config.GUARD_SPEED_FACTOR
end

-- The "👟 700M recommended" plank by each nest (WorldBuilder) reads GREEN when your Speed reaches the
-- zone's recommended Speed and RED below it; Client/SpeedPlanks recolours it for each player.
Config.PLANK_GREEN = Color3.fromRGB(90, 240, 60)
Config.PLANK_RED = Color3.fromRGB(255, 48, 48)

function Config.speedPlankColor(speed: number, k: number): Color3
	return if speed >= Config.ZONES[k].req then Config.PLANK_GREEN else Config.PLANK_RED
end

----------------------------------------------------------------------------------------------------
-- Seeds, rarities, mutations
----------------------------------------------------------------------------------------------------
Config.PODS_PER_NEST = 4
Config.POD_REGROW = 8
Config.PICKUP_DISTANCE = 12

export type Rarity = { id: string, color: Color3, income: number, weight: number, spawn: number }
Config.RARITIES = {
	{ id = "Common", color = Color3.fromRGB(200, 200, 200), income = 1, weight = 1, spawn = 60 },
	{ id = "Uncommon", color = Color3.fromRGB(90, 220, 90), income = 1.6, weight = 1.5, spawn = 25 },
	{ id = "Rare", color = Color3.fromRGB(70, 150, 255), income = 3, weight = 2.5, spawn = 10 },
	{ id = "Epic", color = Color3.fromRGB(190, 80, 255), income = 10, weight = 4, spawn = 4 },
	-- the top rarity has no `spawn`: its chance is LEGENDARY_CHANCE, never tilted (see rarityWeights)
	{ id = "Legendary", color = Color3.fromRGB(255, 190, 30), income = 15, weight = 8, spawn = 0 },
} :: { Rarity }
Config.LEGENDARY = #Config.RARITIES -- rarity index of Legendary

-- Deeper zones and luck (night) tilt Common..Epic toward the rare end.
Config.ZONE_RARITY_BONUS = 0.08
Config.NIGHT_LUCK = 2 -- pods roll with this luck at night

-- Legendary is a trophy: a fixed chance per pod roll by zone (day), times the luck (x2 at night).
-- Unlike the other rarities it gets RARER further down the corridor, and is extremely rare in the last
-- two zones (Deep Space 1 in 2,000, Spirit Garden 1 in 2,500 by day). Premium packs use
-- PACK_LEGENDARY_CHANCE instead.
Config.LEGENDARY_CHANCE = { 0.01, 0.009, 0.008, 0.007, 0.006, 0.0005, 0.0004 }

function Config.legendaryChance(k: number, luck: number): number
	return Config.LEGENDARY_CHANCE[k] * luck
end

-- Rarity weights for zone k (they sum to 1). `legendary` overrides the Legendary chance (packs).
function Config.rarityWeights(k: number, luck: number, legendary: number?): { number }
	local tilt = luck * (1 + Config.ZONE_RARITY_BONUS * (k - 1))
	local out = {}
	local total = 0
	for i = 1, Config.LEGENDARY - 1 do
		out[i] = Config.RARITIES[i].spawn * tilt ^ (i - 1)
		total += out[i]
	end
	local top = legendary or Config.legendaryChance(k, luck)
	for i = 1, Config.LEGENDARY - 1 do
		out[i] = out[i] / total * (1 - top)
	end
	out[Config.LEGENDARY] = top
	return out
end

-- A Legendary worth telling the whole server about: one from the last two zones, or from a premium
-- pack. `fromPack` is true for pack seeds.
Config.ANNOUNCE_LEGENDARY_FROM_ZONE = 6
Config.PACK_ANNOUNCE_DELAY = 4 -- seconds: a pack Legendary is announced once the buyer's reveal reel has landed
function Config.announcesLegendary(zone: number, rarity: number, fromPack: boolean): boolean
	return rarity == Config.LEGENDARY and (fromPack or zone >= Config.ANNOUNCE_LEGENDARY_FROM_ZONE)
end

-- "Alex got a LEGENDARY Gold Starpetal!"
function Config.legendaryAnnouncement(playerName: string, zone: number, mutation: string?): string
	local prefix = if mutation then mutation .. " " else ""
	return `🌟 {playerName} got a LEGENDARY {prefix}{Config.ZONES[zone].seed}!`
end

-- `exclusive` mutations never roll from pods (chance 0); only the premium seed packs can give them
-- (PACK_EXCLUSIVE).
export type Mutation = { id: string, color: Color3, income: number, chance: number, nightOnly: boolean, exclusive: boolean? }
Config.MUTATIONS = {
	{ id = "Gold", color = Color3.fromRGB(255, 215, 0), income = 3, chance = 0.04, nightOnly = false },
	{ id = "Rainbow", color = Color3.fromRGB(255, 80, 200), income = 8, chance = 0.01, nightOnly = false },
	{ id = "Night", color = Color3.fromRGB(90, 90, 255), income = 2, chance = 0.12, nightOnly = true },
	{ id = "Celestial", color = Color3.fromRGB(120, 240, 255), income = 12, chance = 0, nightOnly = false, exclusive = true },
} :: { Mutation }

function Config.mutationById(id: string?): Mutation?
	if id == nil then
		return nil
	end
	for _, m in Config.MUTATIONS do
		if m.id == id then
			return m
		end
	end
	return nil
end

-- Roll (rarity index, mutation id?) with an injectable rng: rng() -> [0, 1)
function Config.rollSeed(k: number, luck: number, isNight: boolean, rng: () -> number): (number, string?)
	local weights = Config.rarityWeights(k, luck)
	local total = 0
	for _, w in weights do
		total += w
	end
	local pick = rng() * total
	local rarity = #weights
	for i, w in weights do
		pick -= w
		if pick < 0 then
			rarity = i
			break
		end
	end
	local mutation: string? = nil
	local m = rng()
	for _, mut in Config.MUTATIONS do
		if not mut.nightOnly or isNight then
			if m < mut.chance then
				mutation = mut.id
				break
			end
			m -= mut.chance
		end
	end
	return rarity, mutation
end

----------------------------------------------------------------------------------------------------
-- Economy (formulas)
----------------------------------------------------------------------------------------------------
-- In-game money buys only three things: trails, plot upgrades and treadmill tiers (see Shop below).
-- Speed is earned by moving, or bought with Robux. Plant income is anchored to a money scale per zone,
-- ZONE_CASH: a full plot (ECONOMY_SLOTS) of zone-k Commons earns zone k+1's ZONE_CASH, in dollars, in
-- PAYBACK_SECONDS. ZONE_CASH is the zones' recommended Speed from before the flat-gain rework (v7), kept
-- as plain numbers when the Speed scale shrank, so the money scale (saved money, every money price)
-- didn't move.
Config.SLOTS_START = 5 -- plant slots at plot level 1
Config.SLOTS_MAX = 30 -- plant slots at the last plot level (the ExtraSlots gamepass adds on top)
Config.ECONOMY_SLOTS = 10 -- the plot size income is balanced for; independent of SLOTS_START
Config.PAYBACK_SECONDS = 300
Config.PAYOUT_INTERVAL = 3
Config.ZONE_CASH = { 0, 10e3, 500e3, 5e6, 50e6, 500e6, 5e9 } -- per zone, in Config.ZONES order

-- Common, sprout-weight income per plant for zone k ($/s)
function Config.seedIncome(k: number): number
	local nextCash = Config.ZONE_CASH[k + 1] or Config.ZONE_CASH[k] * 10
	return nextCash / (Config.ECONOMY_SLOTS * Config.PAYBACK_SECONDS)
end

-- Growth (P2): closed form from plantedAt, never simulated per tick.
Config.GROW_TIME = 20 * 60 -- seconds to full size
Config.GROW_MAX_FACTOR = 5 -- full-grown weight / sprout weight

-- Stable per-plant variance in [0.8, 1.2), derived from what we already save.
function Config.plantVariance(plantedAt: number, slot: number): number
	local x = math.sin(plantedAt * 12.9898 + slot * 78.233) * 43758.5453
	return 0.8 + 0.4 * (x - math.floor(x))
end

function Config.sproutWeight(k: number, rarity: number): number
	return Config.ZONES[k].baseWeight * Config.RARITIES[rarity].weight
end

function Config.plantWeight(k: number, rarity: number, age: number, variance: number): number
	local t = math.clamp(age / Config.GROW_TIME, 0, 1)
	local ease = 1 - (1 - t) * (1 - t)
	return Config.sproutWeight(k, rarity) * variance * (1 + (Config.GROW_MAX_FACTOR - 1) * ease)
end

function Config.plantIncome(k: number, rarity: number, weight: number, mutation: string?): number
	local mut = Config.mutationById(mutation)
	local base = Config.seedIncome(k) * Config.RARITIES[rarity].income * (if mut then mut.income else 1)
	return base * math.sqrt(weight / Config.sproutWeight(k, rarity))
end

-- Plant-creature models (CreatureModels). Sizes are studs at scale 1, and PlotService scales each creature
-- by weight. CREATURE_FOOTPRINT * CREATURE_MAX_SCALE (8.8) keeps a Common..Rare within about one
-- SLOT_SPACING, and Shared/Planting spaces plants by their full-grown size.
Config.CREATURE_FOOTPRINT = 3.4 -- widest a creature (incl. its aura ring) may be at scale 1
-- ...per rarity: Epics are wider, and Legendaries are the big plants (the pack's 20+ stud ones), so they
-- take more room on the bed (Planting spaces them by it and keeps them off the fence).
Config.CREATURE_FOOTPRINTS = { 3.4, 3.4, 3.4, 4.4, 5 }
-- The tallest a plant model may be at scale 1, per rarity (a later zone adds CREATURE_ZONE_HEIGHT per zone).
-- Models are scaled to fit both this and the footprint (tools/export_plants.luau).
Config.CREATURE_HEIGHTS = { 5, 5.5, 6, 7, 10 }
Config.CREATURE_ZONE_HEIGHT = 0.3

function Config.creatureFootprint(rarity: number): number
	return Config.CREATURE_FOOTPRINTS[rarity] or Config.CREATURE_FOOTPRINT
end

function Config.creatureHeight(zone: number, rarity: number): number
	return (Config.CREATURE_HEIGHTS[rarity] or 5) + Config.CREATURE_ZONE_HEIGHT * (zone - 1)
end

Config.CREATURE_GROWTH_EXPONENT = 0.4 -- scale ~ (weight / sprout weight) ^ this: sprout ~1x, full-grown ~1.9x
Config.CREATURE_RARITY_SCALE = 0.07 -- +7% size per rarity step
Config.CREATURE_MIN_SCALE = 0.85
Config.CREATURE_MAX_SCALE = 2.6
-- Optional uploaded models: zone index -> asset id (0 or missing = procedural). Loaded once through
-- InsertService, so the asset must be owned by the game's creator. Rarity/mutation flair still applies.
Config.CREATURE_ASSETS = {} :: { [number]: number }

Config.OFFLINE_CAP_SECONDS = 3600
Config.SELL_SECONDS = 30 -- removing a plant refunds this many seconds of its income
-- The SELL stall in the shop plaza pays more than the R-key refund, so walking there is worth it: 120 s
-- of the plant's base income (no day/night, like the refund) x the plot level / 2x Money multiplier. A
-- plant keeps earning forever, so even 4x the refund is only ~2 min of what it would make by staying.
Config.SELL_STALL_SECONDS = 120
Config.SELL_STALL_DISTANCE = 20 -- studs from the stall's prompt part the player must stand within

----------------------------------------------------------------------------------------------------
-- Shop. In-game money buys only three things: TRAILS, PLOT UPGRADES and TREADMILL TIERS (Config.priceOf). Everything else
-- is Robux: developer products (DEVELOPER_PRODUCTS below) and gamepasses. Rules live in Server/Shop.
----------------------------------------------------------------------------------------------------
-- Trails: a coloured Trail behind the player (Server/TrailService) that multiplies the Speed gained from
-- walking and the treadmill. Players own trails (saved) and equip one at a time. Grey is free: everyone
-- owns it and starts with it equipped. Any other tier can be bought directly, for money (`price`) or
-- Robux (the `product` developer product); there is no need to own the tier below. A trail is a small
-- multiplier on the flat Speed per step: x1 (Grey) up to x3 (Rainbow). The money prices are where the
-- free player's income reaches them (tests/progression_sim): Green-Golden in the first 35 minutes, Red
-- around the Snow Peaks, Rainbow after the Deep Space.
export type Trail = {
	id: string,
	name: string,
	rarity: string,
	mult: number, -- Speed gain multiplier while equipped
	price: number, -- $; 0 = free, owned by everyone
	product: string?, -- DEVELOPER_PRODUCTS key of its Robux price
	color: Color3,
	rainbow: boolean?, -- drawn (and shown on its card) as a rainbow gradient
}
Config.TRAILS = {
	{ id = "Grey", name = "Grey Trail", rarity = "Common", mult = 1, price = 0, color = Color3.fromRGB(175, 178, 190) },
	{ id = "Green", name = "Green Trail", rarity = "Uncommon", mult = 1.25, price = 5e3, product = "TrailGreen", color = Color3.fromRGB(70, 215, 90) },
	{ id = "Blue", name = "Blue Trail", rarity = "Rare", mult = 1.5, price = 75e3, product = "TrailBlue", color = Color3.fromRGB(55, 145, 255) },
	{ id = "Purple", name = "Purple Trail", rarity = "Epic", mult = 1.75, price = 1.5e6, product = "TrailPurple", color = Color3.fromRGB(165, 75, 255) },
	{ id = "Golden", name = "Golden Trail", rarity = "Legendary", mult = 2, price = 30e6, product = "TrailGolden", color = Color3.fromRGB(255, 195, 35) },
	{ id = "Red", name = "Red Trail", rarity = "Mythic", mult = 2.5, price = 20e9, product = "TrailRed", color = Color3.fromRGB(235, 45, 55) },
	{ id = "Rainbow", name = "Rainbow Trail", rarity = "Secret", mult = 3, price = 1e12, product = "TrailRainbow", color = Color3.fromRGB(255, 90, 200), rainbow = true },
} :: { Trail }
Config.DEFAULT_TRAIL = "Grey"

function Config.trailById(id: any): Trail?
	for _, t in Config.TRAILS do
		if t.id == id then
			return t
		end
	end
	return nil
end

-- The Speed gain multiplier of an equipped trail id (the free trail's for anything unknown).
function Config.trailMult(id: string?): number
	local t = Config.trailById(id) or Config.trailById(Config.DEFAULT_TRAIL) :: Trail
	return t.mult
end

-- Speed gained per stud walked (or per stud of treadmill belt) with trail `trailId`: the flat base times
-- the trail, whatever your Speed. The HUD shows it as "+X/step"; the treadmill multiplies it by its tier.
function Config.speedPerStud(trailId: string?): number
	return Config.BASE_SPEED_PER_STUD * Config.trailMult(trailId)
end

-- The colours a trail draws with: its colour fading to white, or a rainbow.
function Config.trailColors(t: Trail): ColorSequence
	if t.rainbow then
		local keys = {}
		for i = 0, 6 do
			table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 7, 0.85, 1)))
		end
		return ColorSequence.new(keys)
	end
	return ColorSequence.new(t.color, t.color:Lerp(Color3.new(1, 1, 1), 0.45))
end

-- Plot upgrades (money, or Robux: PlotUpgradeT1..T6 below). Level 1 has SLOTS_START slots. Each level adds one slot (SLOTS_MAX at
-- PLOT_LEVEL_MAX) and PLOT_MONEY_PER_LEVEL to the multiplier on all of the plot's plant income: x1.06 at
-- level 2, x2.5 at the last level (26). Upgrading to level L costs
-- PLOT_UPGRADE_BASE_PRICE * PLOT_UPGRADE_GROWTH ^ (L - 2): $500 for level 2, ~$40K for 6, ~$9.8M for 11,
-- ~$2.4B for 16, ~$581B for 21 and ~$141T for 26, about 4 h of a strong late-game income (README).
Config.PLOT_LEVEL_MAX = Config.SLOTS_MAX - Config.SLOTS_START + 1
Config.PLOT_MONEY_PER_LEVEL = 0.06
Config.PLOT_UPGRADE_BASE_PRICE = 500
Config.PLOT_UPGRADE_GROWTH = 3.1

function Config.plotSlots(level: number): number
	return Config.SLOTS_START + level - 1
end

-- Rounded to 0.01 so it reads "x1.42", not "x1.4200000000000002".
function Config.plotMoneyMult(level: number): number
	return math.round((1 + Config.PLOT_MONEY_PER_LEVEL * (level - 1)) * 100) / 100
end

-- Price of upgrading a plot to `toLevel` (2..PLOT_LEVEL_MAX).
function Config.plotUpgradePrice(toLevel: number): number
	return math.floor(Config.PLOT_UPGRADE_BASE_PRICE * Config.PLOT_UPGRADE_GROWTH ^ (toLevel - 2))
end

-- Everything that multiplies plant income except day/night: the plot level and the 2x Money pass. The
-- payout loop, offline income, removal refunds and income-based Robux grants all use it.
function Config.moneyMult(plotLevel: number, doubleMoney: boolean): number
	return Config.plotMoneyMult(plotLevel) * (if doubleMoney then 2 else 1)
end

-- Treadmill tiers: standing on your own treadmill pays the walking Speed gain x `mult` (AFK works).
-- Tier 1 is free. Each next tier is bought one at a time, at the treadmill itself (its owner-only E/F
-- prompts) or in the Shop: for money (`price`, Config.priceOf "TreadmillUpgrade") or Robux (one tier per
-- TreadmillT1..T3 receipt, Config.treadmillUpgradeProduct). Prices grow x10 a tier: a free player buys
-- x2.25 after ~10 minutes and has x5 ($1T) by the Spirit Garden; x6 and x8 are late-game sinks like the
-- last plot levels. Tuned with tests/progression_sim, together with the zones' recommended Speed: a
-- free player who buys these lands every zone near its target, and an AFK farmer (fills the plot once,
-- then only stands on the treadmill) is far slower than a player who keeps running the corridor. Saves
-- before v5 had 3 tiers (x2, Robux x3, Robux x5): ProfileStore maps them to the tiers with the same
-- multiplier.
export type TreadmillTier = { mult: number, price: number }
Config.TREADMILL_TIERS = {
	{ mult = 2, price = 0 },
	{ mult = 2.25, price = 1e6 },
	{ mult = 2.5, price = 10e6 },
	{ mult = 2.75, price = 100e6 },
	{ mult = 3, price = 1e9 },
	{ mult = 3.5, price = 10e9 },
	{ mult = 4, price = 100e9 },
	{ mult = 5, price = 1e12 },
	{ mult = 6, price = 10e12 },
	{ mult = 8, price = 100e12 },
} :: { TreadmillTier }
Config.TREADMILL_MAX = #Config.TREADMILL_TIERS

-- The multiplier of treadmill tier `tier` (clamped, so a bad tier never errors).
function Config.treadmillMult(tier: number): number
	return Config.TREADMILL_TIERS[math.clamp(math.floor(tier), 1, Config.TREADMILL_MAX)].mult
end

-- Treadmill upgrades for Robux: like the plot's, the next tier is sold by the product of its price tier.
-- Each covers TREADMILL_UPGRADE_TIER_LEVELS upgrades (to tiers 2-4, 5-7 and 8-10).
Config.TREADMILL_UPGRADE_TIERS = 3
Config.TREADMILL_UPGRADE_TIER_LEVELS = 3

-- The Robux price tier for upgrading a treadmill that is at `tier` now, or nil at the last tier.
function Config.treadmillUpgradeTier(tier: number): number?
	if tier >= Config.TREADMILL_MAX then
		return nil
	end
	return math.clamp((math.max(tier, 1) - 1) // Config.TREADMILL_UPGRADE_TIER_LEVELS + 1, 1, Config.TREADMILL_UPGRADE_TIERS)
end

-- Every item the inventory can hold, with how many a new player starts with (an item that starts at 0
-- is listed as 0). There are none right now; saved items not listed here are dropped on load.
Config.START_ITEMS = {} :: { [string]: number }

Config.BAT_RANGE = 14
Config.BAT_STUN = 2
Config.BAT_COOLDOWN = 4

-- Gamepass stubs: set real ids to enable. 0 = not configured.
export type Gamepass = { id: number, label: string }
Config.GAMEPASSES = {
	DoubleMoney = { id = 0, label = "2x Money" },
	ExtraSlots = { id = 0, label = "+10 Plant Slots" },
} :: { [string]: Gamepass }
Config.PASS_EXTRA_SLOTS = 10 -- the ExtraSlots pass adds this many slots, on top of the plot level's

----------------------------------------------------------------------------------------------------
-- Seed packs: our "eggs with odds". Two premium, late-game packs, Robux only: each is a developer
-- product, never sold for in-game money, with no Speed gate (a premium shortcut). A pack rolls one
-- seed of its zone into the player's seed bag, which they plant from the Seeds menu at their pad.
-- Rolls live in Shared/SeedPacks, purchase rules in Server/Shop.
----------------------------------------------------------------------------------------------------
Config.PACK_LUCK = Config.NIGHT_LUCK -- packs roll Common..Epic like a night pod in their zone...
Config.PACK_LEGENDARY_CHANCE = 0.015 -- ...but Legendary stays a rare event (1 in ~67)...
Config.PACK_MUTATION_MULT = 2 -- ...with twice the Gold/Rainbow chances (Night never rolls from packs)...
Config.PACK_EXCLUSIVE = "Celestial" -- ...plus the pack-only mutation, which pods never roll
Config.PACK_EXCLUSIVE_CHANCE = 0.005
Config.SEED_BAG_MAX = 50 -- soft cap: the Shop won't *prompt* a pack purchase once the bag holds this many
Config.SEED_BAG_HARD_MAX = 250 -- paid grants may go past SEED_BAG_MAX up to here; saves are clamped here
-- A paid pack whose seed can't fit (bag at SEED_BAG_HARD_MAX) pays this many seconds of the player's
-- income instead (at least this many seconds of a Common plant from the pack's zone), so a paid
-- purchase is never lost.
Config.PACK_FULL_BAG_INCOME_SECONDS = 300
Config.RECEIPT_HISTORY = 100 -- processed Robux PurchaseIds kept per profile, so a grant never repeats

----------------------------------------------------------------------------------------------------
-- Developer products: everything sold for Robux except the gamepasses. Create each one on the Creator
-- Dashboard and paste its id here; id = 0 means "not set up yet" (the Shop says "coming soon"). `robux`
-- is only the placeholder shown while the real price can't be fetched: the real price is set on the
-- Dashboard and read with MarketplaceService:GetProductInfo. `kind` says what a receipt grants:
--   Pack      one seed of `zone` into the seed bag
--   Speed     + `amount` Speed
--   Money     max(`amount`, `minutes` of the buyer's current income), so late-game packs stay useful
--   TreadmillUpgrade  one treadmill tier, from the tier the player has when the receipt arrives (`tier`:
--             the range of tiers it is sold for, Config.treadmillUpgradeProduct); a maxed treadmill gets
--             money instead
--   Trail     owns and equips Config.TRAILS[`trail`]
--   PlotUpgrade  one plot level, from the level the player has when the receipt arrives (`tier`: the
--             range of levels it is sold for, Config.plotUpgradeProduct); a maxed plot gets money instead
----------------------------------------------------------------------------------------------------
export type DevProduct = {
	id: number,
	kind: string,
	label: string,
	robux: number,
	zone: number?,
	amount: number?,
	minutes: number?,
	tier: number?, -- PlotUpgrade / TreadmillUpgrade: its price tier
	trail: string?,
}
Config.DEVELOPER_PRODUCTS = {
	PackSpace = { id = 0, kind = "Pack", label = "Starpetal Pack", robux = 2000, zone = 6 },
	PackSpirit = { id = 0, kind = "Pack", label = "Lotus Wyrm Pack", robux = 3000, zone = 7 },

	-- Speed packs: the Shop's blue SPEED cards. Sized against the zones' recommended Speed (v7 scale):
	-- +25K is the Desert, +750K a bit past the Jungle, +3M past the Lava Fields, +10M past the Snow
	-- Peaks, +25M the Deep Space and +50M two thirds of the way to the Spirit Garden (README "Progression").
	Speed25K = { id = 0, kind = "Speed", label = "+25K Speed", robux = 9, amount = 25e3 },
	Speed150K = { id = 0, kind = "Speed", label = "+150K Speed", robux = 36, amount = 150e3 },
	Speed250K = { id = 0, kind = "Speed", label = "+250K Speed", robux = 64, amount = 250e3 },
	Speed750K = { id = 0, kind = "Speed", label = "+750K Speed", robux = 76, amount = 750e3 },
	Speed3M = { id = 0, kind = "Speed", label = "+3M Speed", robux = 560, amount = 3e6 },
	Speed10M = { id = 0, kind = "Speed", label = "+10M Speed", robux = 1200, amount = 10e6 },
	Speed25M = { id = 0, kind = "Speed", label = "+25M Speed", robux = 1600, amount = 25e6 },
	Speed50M = { id = 0, kind = "Speed", label = "+50M Speed", robux = 2400, amount = 50e6 },

	Money24K = { id = 0, kind = "Money", label = "Pocket Cash", robux = 40, amount = 24e3, minutes = 10 },
	Money200K = { id = 0, kind = "Money", label = "Cash Bag", robux = 80, amount = 200e3, minutes = 30 },
	Money800K = { id = 0, kind = "Money", label = "Cash Stack", robux = 200, amount = 800e3, minutes = 60 },
	Money4M = { id = 0, kind = "Money", label = "Cash Crate", robux = 400, amount = 4e6, minutes = 180 },
	Money8M = { id = 0, kind = "Money", label = "Cash Vault", robux = 640, amount = 8e6, minutes = 360 },

	-- One treadmill tier each: the treadmill's F prompt and the Shop's R$ button. A product's price is
	-- fixed, so the 9 upgrades are split into tiers that cost more as the treadmill grows
	-- (Config.treadmillUpgradeProduct).
	TreadmillT1 = { id = 0, kind = "TreadmillUpgrade", label = "Treadmill Upgrade (x2.25-x2.75)", robux = 19, tier = 1 },
	TreadmillT2 = { id = 0, kind = "TreadmillUpgrade", label = "Treadmill Upgrade (x3-x4)", robux = 39, tier = 2 },
	TreadmillT3 = { id = 0, kind = "TreadmillUpgrade", label = "Treadmill Upgrade (x5-x8)", robux = 79, tier = 3 },

	TrailGreen = { id = 0, kind = "Trail", label = "Green Trail", robux = 16, trail = "Green" },
	TrailBlue = { id = 0, kind = "Trail", label = "Blue Trail", robux = 24, trail = "Blue" },
	TrailPurple = { id = 0, kind = "Trail", label = "Purple Trail", robux = 40, trail = "Purple" },
	TrailGolden = { id = 0, kind = "Trail", label = "Golden Trail", robux = 64, trail = "Golden" },
	TrailRed = { id = 0, kind = "Trail", label = "Red Trail", robux = 100, trail = "Red" },
	TrailRainbow = { id = 0, kind = "Trail", label = "Rainbow Trail", robux = 180, trail = "Rainbow" },

	-- One plot level each: the Upgrade board's purple button. A product's price is fixed, so the 25
	-- upgrades are split into tiers that cost more as the plot grows (Config.plotUpgradeProduct).
	PlotUpgradeT1 = { id = 0, kind = "PlotUpgrade", label = "Plot Upgrade (Lv 2-5)", robux = 25, tier = 1 },
	PlotUpgradeT2 = { id = 0, kind = "PlotUpgrade", label = "Plot Upgrade (Lv 6-9)", robux = 49, tier = 2 },
	PlotUpgradeT3 = { id = 0, kind = "PlotUpgrade", label = "Plot Upgrade (Lv 10-13)", robux = 99, tier = 3 },
	PlotUpgradeT4 = { id = 0, kind = "PlotUpgrade", label = "Plot Upgrade (Lv 14-17)", robux = 199, tier = 4 },
	PlotUpgradeT5 = { id = 0, kind = "PlotUpgrade", label = "Plot Upgrade (Lv 18-21)", robux = 399, tier = 5 },
	PlotUpgradeT6 = { id = 0, kind = "PlotUpgrade", label = "Plot Upgrade (Lv 22-26)", robux = 799, tier = 6 },
} :: { [string]: DevProduct }

-- Plot upgrades for Robux: the next level of a plot is sold by the product of its tier. Each tier covers
-- PLOT_UPGRADE_TIER_LEVELS upgrades and the last one takes the rest (levels 22-26).
Config.PLOT_UPGRADE_TIERS = 6
Config.PLOT_UPGRADE_TIER_LEVELS = 4

-- The Robux price tier for upgrading a plot that is at `level` now, or nil at the last level.
function Config.plotUpgradeTier(level: number): number?
	if level >= Config.PLOT_LEVEL_MAX then
		return nil
	end
	return math.clamp((math.max(level, 1) - 1) // Config.PLOT_UPGRADE_TIER_LEVELS + 1, 1, Config.PLOT_UPGRADE_TIERS)
end

-- The developer product that sells the next level of a plot at `level`, as (name, product), or nil at the
-- last level. The board's purple button uses it, and so can the Shop ("Product:" .. name).
function Config.plotUpgradeProduct(level: number): (string?, DevProduct?)
	local tier = Config.plotUpgradeTier(level)
	if not tier then
		return nil, nil
	end
	local name = `PlotUpgradeT{tier}`
	return name, Config.DEVELOPER_PRODUCTS[name]
end

-- What a plot-upgrade receipt pays instead of a level when the plot is already at the last one (it can
-- arrive after the player maxed the plot with money): the last level's money price.
function Config.plotUpgradeMaxedPay(): number
	return Config.plotUpgradePrice(Config.PLOT_LEVEL_MAX)
end

-- The developer product that sells the next tier of a treadmill at `tier`, as (name, product), or nil at
-- the last tier. The treadmill's F prompt uses it, and so does the Shop ("Product:" .. name).
function Config.treadmillUpgradeProduct(tier: number): (string?, DevProduct?)
	local priceTier = Config.treadmillUpgradeTier(tier)
	if not priceTier then
		return nil, nil
	end
	local name = `TreadmillT{priceTier}`
	return name, Config.DEVELOPER_PRODUCTS[name]
end

-- What a treadmill-upgrade receipt pays instead of a tier when the treadmill is already at the last one:
-- the last tier's money price.
function Config.treadmillUpgradeMaxedPay(): number
	return Config.TREADMILL_TIERS[Config.TREADMILL_MAX].price
end

-- The products of one kind, cheapest first (the Shop's card order).
function Config.products(kind: string): { { name: string, product: DevProduct } }
	local list = {}
	for name, product in Config.DEVELOPER_PRODUCTS do
		if product.kind == kind then
			table.insert(list, { name = name, product = product })
		end
	end
	table.sort(list, function(a, b)
		if a.product.robux ~= b.product.robux then
			return a.product.robux < b.product.robux
		end
		return a.name < b.name
	end)
	return list
end

-- The product with this (non-zero) developer product id, as (name, product).
function Config.productById(productId: number): (string?, DevProduct?)
	if productId == 0 then
		return nil, nil
	end
	for name, product in Config.DEVELOPER_PRODUCTS do
		if product.id == productId then
			return name, product
		end
	end
	return nil, nil
end

-- What a Money product pays a player earning `income` $/s (with all multipliers): its fixed amount, or
-- `minutes` of that income if more. The Shop card shows the same number.
function Config.moneyPackAmount(product: DevProduct, income: number): number
	return math.floor(math.max(product.amount or 0, math.max(0, income) * (product.minutes or 0) * 60))
end

-- What the shop needs to know about a player (profile or client stats snapshot).
export type ShopView = {
	money: number,
	plotLevel: number,
	trails: { [string]: boolean },
	treadmillTier: number?, -- nil = the free tier
}

-- The money price and a short label of a money item ("PlotUpgrade", "TreadmillUpgrade" or "Trail:<id>"),
-- or nil (with "Maxed"/"Owned", or nothing for anything that isn't sold for money).
function Config.priceOf(itemId: string, v: ShopView): (number?, string?)
	if itemId == "PlotUpgrade" then
		if v.plotLevel >= Config.PLOT_LEVEL_MAX then
			return nil, "Maxed"
		end
		return Config.plotUpgradePrice(v.plotLevel + 1), `Plot Level {v.plotLevel + 1}`
	elseif itemId == "TreadmillUpgrade" then
		local tier = v.treadmillTier or 1
		if tier >= Config.TREADMILL_MAX then
			return nil, "Maxed"
		end
		return Config.TREADMILL_TIERS[tier + 1].price, `Treadmill x{Config.treadmillMult(tier + 1)}`
	end
	local trail = Config.trailById(string.match(itemId, "^Trail:(%a+)$"))
	if trail then
		if trail.price <= 0 or v.trails[trail.id] then
			return nil, "Owned"
		end
		return trail.price, trail.name
	end
	return nil, nil
end

----------------------------------------------------------------------------------------------------
-- Day / night (P3): derived from the clock, so server and client agree with no remote.
----------------------------------------------------------------------------------------------------
Config.DAY_SECONDS = 300
Config.NIGHT_SECONDS = 150

function Config.dayPhase(now: number): (boolean, number)
	local cycle = Config.DAY_SECONDS + Config.NIGHT_SECONDS
	local t = now % cycle
	if t < Config.DAY_SECONDS then
		return false, Config.DAY_SECONDS - t -- isNight, seconds until it flips
	end
	return true, cycle - t
end

-- Day and night plants: each zone's plants (Zone.active) earn ACTIVE_TIME_MULT during their phase, 1x
-- otherwise. plantIncome stays the plain base; PlotService applies this on payout.
Config.ACTIVE_TIME_MULT = 1.5
Config.ACTIVE_ICONS = { day = "☀️", night = "🌙" } :: { [string]: string }

function Config.isActiveTime(k: number, isNight: boolean): boolean
	return (Config.ZONES[k].active == "night") == isNight
end

function Config.timeMult(k: number, isNight: boolean): number
	return if Config.isActiveTime(k, isNight) then Config.ACTIVE_TIME_MULT else 1
end

-- Time-weighted mean of timeMult over a full day/night cycle (offline income).
function Config.averageTimeMult(k: number): number
	local day, night = Config.DAY_SECONDS, Config.NIGHT_SECONDS
	return (day * Config.timeMult(k, false) + night * Config.timeMult(k, true)) / (day + night)
end

----------------------------------------------------------------------------------------------------
-- Community rewards (Server/Rewards, Server/RewardService, Client/Rewards)
----------------------------------------------------------------------------------------------------
-- The Free Gift: FREE_GIFT_SPEED Speed, once per account, for members of the owner's Roblox community
-- (group). Likes can't be checked in game, and rewarding likes or favourites goes against Roblox's
-- Community Rules (no prizes in exchange for something), so the window only *asks* for a like and a
-- favourite: the reward depends on the group membership alone (Player:IsInGroupAsync). 0 = no community yet:
-- the window says "coming soon" and never opens by itself. PUT THE GROUP ID HERE (the number in the
-- community's URL: roblox.com/communities/<id>/...).
Config.COMMUNITY_GROUP_ID = 0
Config.COMMUNITY_NAME = "Steal a Seed Community" -- what the window tells players to search for
Config.FREE_GIFT_SPEED = 25_000 -- the Desert's recommended Speed
Config.FREE_GIFT_AUTO_OPEN = 20 -- seconds after joining: the window opens by itself, once per account

-- The free chest in the base: money worth FREE_CHEST_MINUTES of the player's income ($/s with every
-- multiplier, what the HUD shows), at least FREE_CHEST_MIN, every FREE_CHEST_COOLDOWN seconds per player
-- (saved, so rejoining doesn't reset it).
Config.FREE_CHEST_COOLDOWN = 15 * 60
Config.FREE_CHEST_MINUTES = 5
Config.FREE_CHEST_MIN = 1_000
Config.FREE_CHEST_DISTANCE = 14 -- studs from the chest the player must stand within

function Config.freeChestAmount(income: number): number
	if type(income) ~= "number" or income ~= income or income < 0 then
		income = 0
	end
	return math.floor(math.max(Config.FREE_CHEST_MIN, income * Config.FREE_CHEST_MINUTES * 60))
end

-- The "MOST MONEY/s" board: the global top players by current income (an OrderedDataStore), written
-- and read every minute by each server.
Config.MONEY_BOARD_STORE = "MostMoneyPerSecond_v1"
Config.MONEY_BOARD_ROWS = 10
Config.MONEY_BOARD_INTERVAL = 60

----------------------------------------------------------------------------------------------------
-- Data
----------------------------------------------------------------------------------------------------
Config.DATASTORE_NAME = "StealASeed_v1"
Config.AUTOSAVE_INTERVAL = 90
Config.SAVE_RETRIES = 4

-- UI icons (icons/*.png): their image asset ids, from icons/ids.json, which Rojo puts next to this module
-- as the IconIds ModuleScript. 0 = not uploaded yet: the UI keeps the emoji (Shared/Icons). Fill the file
-- with tools/upload_icons.luau or by hand (icons/COMO_SUBIR_ICONES.md), never here.
Config.ICONS = {} :: { [string]: number }
for key, id in require(script.Parent:WaitForChild("IconIds")) :: any do
	Config.ICONS[key] = if type(id) == "number" then id else 0
end

-- Sounds (P3). Built-in client sounds so nothing needs uploading; swap for asset ids freely.
Config.SOUNDS = {
	Pickup = "rbxasset://sounds/electronicpingshort.wav",
	Plant = "rbxasset://sounds/snap.mp3",
	Caught = "rbxasset://sounds/uuhhh.mp3",
	Wake = "rbxasset://sounds/swordlunge.wav",
	Bat = "rbxasset://sounds/swordslash.wav",
	Buy = "rbxasset://sounds/electronicpingshort.wav",
	Click = "rbxasset://sounds/button.wav",
}

return Config
