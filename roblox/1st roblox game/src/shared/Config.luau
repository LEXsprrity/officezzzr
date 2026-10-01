--!strict
-- Steal a Seed: all tuning lives here, as data or as formulas. Server and client both read it.
local Config = {}

----------------------------------------------------------------------------------------------------
-- Server / world
----------------------------------------------------------------------------------------------------
Config.MAX_PLAYERS = 8 -- one plot each; also set Max Players = 8 in Game Settings
Config.TICK = 0.25 -- speed tracker tick (s)
Config.GUARD_HZ = 10 -- guard chase loop rate

-- Layout (studs). Base area is at -X, the corridor runs along +X.
Config.GROUND_Y = 0
Config.CORRIDOR_START_X = 60 -- anything with X below this is the safe base area
Config.CORRIDOR_WIDTH = 64
Config.WALL_HEIGHT = 44
Config.PLOT_SIZE = 84
Config.PLOT_SPACING_X = 100
Config.PLOT_FIRST_X = -70
Config.PLOT_OFFSET_Z = 80 -- plots sit at z = +/-80, the walkway runs down z = 0
Config.SLOT_SPACING = 8 -- creature sizes (CREATURE_* below) are budgeted against this
Config.SLOT_COLUMNS = 8
Config.SOIL_HEIGHT = 0.4 -- soil patch under each slot; creatures stand on top of it

----------------------------------------------------------------------------------------------------
-- Speed stat -> WalkSpeed
----------------------------------------------------------------------------------------------------
Config.BASE_WALKSPEED = 16
Config.MAX_WALKSPEED = 180
Config.WALKSPEED_LOG_SCALE = 16 -- "a" in 16 + a*log10(1 + Speed)
Config.SLOW_MODE_WALKSPEED = 16

function Config.walkSpeedFor(speed: number): number
	local w = Config.BASE_WALKSPEED + Config.WALKSPEED_LOG_SCALE * math.log10(1 + math.max(0, speed))
	return math.clamp(w, Config.BASE_WALKSPEED, Config.MAX_WALKSPEED)
end

-- Speed from moving
Config.GAIN_PER_STUD = 1 -- Speed stat per stud walked, before multipliers
Config.GAIN_CAP_STUDS_PER_TICK = Config.MAX_WALKSPEED * Config.TICK -- most studs one tick can pay for
Config.MOVE_SLACK = 1.5 -- per-tick distance allowed = WalkSpeed * dt * slack + epsilon
Config.MOVE_EPSILON = 2
Config.MOVE_BUCKET_SECONDS = 1 -- sustained over-speed beyond this much budget -> rubber-band

----------------------------------------------------------------------------------------------------
-- Zones. The corridor is the concatenation of zone lengths (10,900 studs). The Meadow is short so a first seed is a quick grab.
----------------------------------------------------------------------------------------------------
export type Zone = {
	id: string,
	name: string,
	req: number, -- recommended Speed stat
	length: number,
	floor: Color3, -- corridor floor (WorldBuilder/ZoneThemes)
	wall: Color3,
	ui: Color3, -- saturated card colour for the HUD
	material: string, -- Enum.Material name
	guard: string,
	guardColor: Color3,
	seed: string, -- creature name
	seedColor: Color3,
	baseWeight: number, -- Kg of a sprouted Common, before growth
	icon: string,
}

Config.ZONES = {
	{ id = "Meadow", name = "Meadow", req = 0, length = 200, icon = "🌼",
		floor = Color3.fromRGB(104, 214, 70), wall = Color3.fromRGB(56, 152, 58), material = "Grass", ui = Color3.fromRGB(70, 180, 70),
		guard = "Giant Mole", guardColor = Color3.fromRGB(110, 80, 60),
		seed = "Sproutling", seedColor = Color3.fromRGB(120, 230, 90), baseWeight = 12 },
	{ id = "Desert", name = "Desert", req = 10e3, length = 1000, icon = "🦂",
		floor = Color3.fromRGB(240, 204, 124), wall = Color3.fromRGB(226, 164, 98), material = "Sand", ui = Color3.fromRGB(225, 145, 55),
		guard = "Giant Scorpion", guardColor = Color3.fromRGB(190, 90, 40),
		seed = "Cactopod", seedColor = Color3.fromRGB(60, 170, 90), baseWeight = 340 },
	{ id = "Jungle", name = "Jungle", req = 500e3, length = 1400, icon = "🦖",
		floor = Color3.fromRGB(66, 162, 60), wall = Color3.fromRGB(98, 126, 88), material = "LeafyGrass", ui = Color3.fromRGB(35, 140, 75),
		guard = "Giant Dino", guardColor = Color3.fromRGB(70, 150, 70),
		seed = "Fernosaur", seedColor = Color3.fromRGB(40, 200, 120), baseWeight = 9_500 },
	{ id = "Lava", name = "Lava Fields", req = 5e6, length = 1600, icon = "🌋",
		floor = Color3.fromRGB(58, 44, 48), wall = Color3.fromRGB(80, 44, 40), material = "Basalt", ui = Color3.fromRGB(225, 85, 30),
		guard = "Lava Golem", guardColor = Color3.fromRGB(240, 100, 30),
		seed = "Magmabloom", seedColor = Color3.fromRGB(255, 120, 40), baseWeight = 180_000 },
	{ id = "Snow", name = "Snow Peaks", req = 50e6, length = 1800, icon = "❄️",
		floor = Color3.fromRGB(238, 246, 255), wall = Color3.fromRGB(160, 206, 242), material = "Snow", ui = Color3.fromRGB(65, 150, 225),
		guard = "Giant Yeti", guardColor = Color3.fromRGB(220, 230, 245),
		seed = "Frostbulb", seedColor = Color3.fromRGB(120, 200, 255), baseWeight = 2_000_000 },
	{ id = "Space", name = "Deep Space", req = 500e6, length = 2100, icon = "👽",
		floor = Color3.fromRGB(30, 24, 70), wall = Color3.fromRGB(46, 36, 100), material = "Glass", ui = Color3.fromRGB(115, 75, 225),
		guard = "Big Alien", guardColor = Color3.fromRGB(120, 255, 120),
		seed = "Starpetal", seedColor = Color3.fromRGB(200, 120, 255), baseWeight = 45_000_000 },
	{ id = "Spirit", name = "Spirit Garden", req = 5e9, length = 2800, icon = "⛩️",
		floor = Color3.fromRGB(238, 232, 220), wall = Color3.fromRGB(250, 240, 224), material = "Pebble", ui = Color3.fromRGB(225, 75, 130),
		guard = "Spirit Dragon", guardColor = Color3.fromRGB(230, 50, 60),
		seed = "Lotus Wyrm", seedColor = Color3.fromRGB(255, 150, 200), baseWeight = 900_000_000 },
} :: { Zone }

-- Where each zone starts along X, the nest (mother plant) position, and the end of the line.
Config.NEST_FRACTION = 0.85 -- nest sits this far into its zone
Config.GUARD_HOME_OFFSET = 24 -- the guard sleeps this many studs past the mother plant (+X)

function Config.zoneStartX(k: number): number
	local x = Config.CORRIDOR_START_X
	for i = 1, k - 1 do
		x += Config.ZONES[i].length
	end
	return x
end

function Config.nestX(k: number): number
	return Config.zoneStartX(k) + Config.ZONES[k].length * Config.NEST_FRACTION
end

Config.END_X = Config.zoneStartX(#Config.ZONES + 1) -- far end of the corridor

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
Config.GUARD_SPEED_FACTOR = 0.9 -- chase WalkSpeed = walkSpeedFor(zone.req) * this
Config.GUARD_RETURN_FACTOR = 0.6 -- walking home is slower than chasing
Config.CATCH_DISTANCE = 6 -- horizontal studs, root to root
Config.CHASE_TIMEOUT = 45
Config.GUARD_SCALE = 3 -- body size multiplier ("giant")
Config.KNOCKBACK_STUDS = 30
Config.CATCH_STUN = 1 -- seconds the caught player can't move

function Config.guardChaseSpeed(k: number): number
	return Config.walkSpeedFor(Config.ZONES[k].req) * Config.GUARD_SPEED_FACTOR
end

----------------------------------------------------------------------------------------------------
-- Seeds, rarities, mutations
----------------------------------------------------------------------------------------------------
Config.PODS_PER_NEST = 4
Config.POD_REGROW = 8
Config.PICKUP_DISTANCE = 12
Config.PLANT_DISTANCE = 16

export type Rarity = { id: string, color: Color3, income: number, weight: number, spawn: number }
Config.RARITIES = {
	{ id = "Common", color = Color3.fromRGB(200, 200, 200), income = 1, weight = 1, spawn = 60 },
	{ id = "Uncommon", color = Color3.fromRGB(90, 220, 90), income = 1.6, weight = 1.5, spawn = 25 },
	{ id = "Rare", color = Color3.fromRGB(70, 150, 255), income = 3, weight = 2.5, spawn = 10 },
	{ id = "Epic", color = Color3.fromRGB(190, 80, 255), income = 6, weight = 4, spawn = 4 },
	{ id = "Legendary", color = Color3.fromRGB(255, 190, 30), income = 15, weight = 8, spawn = 1 },
} :: { Rarity }

-- Deeper zones and luck (night, potions) tilt the odds toward the rare end.
Config.ZONE_RARITY_BONUS = 0.1

function Config.rarityWeights(k: number, luck: number): { number }
	local tilt = luck * (1 + Config.ZONE_RARITY_BONUS * (k - 1))
	local out = {}
	for i, r in Config.RARITIES do
		out[i] = r.spawn * tilt ^ (i - 1)
	end
	return out
end

-- `exclusive` mutations never roll from pods (chance 0); only the featured seed pack can give them.
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
Config.PRICE_PER_SPEED = 1 -- $ per point of Speed
Config.SLOTS_START = 10
Config.SLOTS_MAX = 30
Config.PAYBACK_SECONDS = 300 -- a full plot of zone-k plants pays for zone k+1 in about this long
Config.PAYOUT_INTERVAL = 3

function Config.speedCost(amount: number): number
	return amount * Config.PRICE_PER_SPEED
end

-- Common, sprout-weight income per plant for zone k ($/s)
function Config.seedIncome(k: number): number
	local nextZone = Config.ZONES[k + 1]
	local nextReq = if nextZone then nextZone.req else Config.ZONES[k].req * 10
	return nextReq * Config.PRICE_PER_SPEED / (Config.SLOTS_START * Config.PAYBACK_SECONDS)
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
-- by weight. CREATURE_FOOTPRINT * CREATURE_MAX_SCALE (8.8) keeps the biggest within about one slot spacing,
-- and the back row (46 + 4 * SLOT_SPACING = 78 studs in) still clears the 84-stud plot's back fence.
Config.CREATURE_FOOTPRINT = 3.4 -- widest a creature (incl. its aura ring) may be at scale 1
Config.CREATURE_GROWTH_EXPONENT = 0.4 -- scale ~ (weight / sprout weight) ^ this: sprout ~1x, full-grown ~1.9x
Config.CREATURE_RARITY_SCALE = 0.07 -- +7% size per rarity step
Config.CREATURE_MIN_SCALE = 0.85
Config.CREATURE_MAX_SCALE = 2.6
-- Optional uploaded models: zone index -> asset id (0 or missing = procedural). Loaded once through
-- InsertService, so the asset must be owned by the game's creator. Rarity/mutation flair still applies.
Config.CREATURE_ASSETS = {} :: { [number]: number }

Config.OFFLINE_CAP_SECONDS = 3600
Config.SELL_SECONDS = 30 -- removing a plant refunds this many seconds of its income

----------------------------------------------------------------------------------------------------
-- Shop
----------------------------------------------------------------------------------------------------
-- Speed multiplier tiers (applies to Speed gained from moving and the treadmill)
Config.SPEED_MULT_TIERS = {
	{ mult = 1, price = 0 },
	{ mult = 2, price = 15e3 },
	{ mult = 3, price = 400e3 },
	{ mult = 5, price = 8e6 },
	{ mult = 10, price = 250e6 },
	{ mult = 25, price = 10e9 },
}
Config.TREADMILL_TIERS = {
	{ mult = 2, price = 0 },
	{ mult = 3, price = 150e3 },
	{ mult = 5, price = 60e6 },
}
Config.SPEED_BUY_FRACTION = 0.25 -- the "+" button's small pack: +25% of current Speed...
Config.SPEED_BUY_MIN = 1000 -- ...but at least this much
Config.SLOT_BASE_PRICE = 25e3
Config.SLOT_PRICE_GROWTH = 2.2
Config.SLEEP_DUST_PRICE = 5e3
Config.SLEEP_DUST_EXTRA = 5 -- guard stays asleep this much longer
Config.SLEEP_DUST_RANGE = 60
Config.SLEEP_DUST_LASTS = 60 -- a dusted nest stays dusted this long
Config.START_ITEMS = { SleepDust = 3 } :: { [string]: number }

Config.BAT_RANGE = 14
Config.BAT_STUN = 2
Config.BAT_COOLDOWN = 4

-- Potions (P3)
export type Potion = { stat: string, mult: number, seconds: number, label: string, icon: string }
Config.POTIONS = {
	PotionSpeed = { stat = "Speed", mult = 2, seconds = 300, label = "Speed Potion", icon = "⚡" },
	PotionMoney = { stat = "Money", mult = 2, seconds = 300, label = "Money Potion", icon = "💰" },
	PotionLuck = { stat = "Luck", mult = 2, seconds = 300, label = "Luck Potion", icon = "🍀" },
} :: { [string]: Potion }
Config.POTION_MIN_PRICE = 5e3
Config.POTION_INCOME_SECONDS = 90 -- a potion costs this many seconds of your income

-- Gamepass stubs: set real ids to enable. 0 = not configured.
export type Gamepass = { id: number, label: string }
Config.GAMEPASSES = {
	DoubleMoney = { id = 0, label = "2x Money" },
	ExtraSlots = { id = 0, label = "+10 Plant Slots" },
} :: { [string]: Gamepass }
Config.PASS_EXTRA_SLOTS = 10 -- the ExtraSlots pass adds this many slots

----------------------------------------------------------------------------------------------------
-- Seed packs: our "eggs with odds". Bought with money, each rolls one seed into the player's seed
-- bag, which they plant from the Seeds menu at their pad. Logic lives in Shared/SeedPacks.
----------------------------------------------------------------------------------------------------
Config.PACK_INCOME_SECONDS = 240 -- a zone-k pack costs this many seconds of a Common zone-k plant's income
Config.PACK_LUCK = 1 -- packs roll rarities like a daytime pod in their zone...
Config.PACK_MUTATION_MULT = 1 -- ...with the same Gold/Rainbow chances (Night never rolls from packs)
Config.PACK_COOLDOWN = 0.6 -- seconds between pack purchases per player
Config.SEED_BAG_MAX = 50 -- buying packs with money stops at this many bagged seeds
Config.SEED_BAG_HARD_MAX = 250 -- Robux grants may go past SEED_BAG_MAX; saves are clamped here
Config.RECEIPT_HISTORY = 100 -- processed Robux PurchaseIds kept per profile, so a grant never repeats

-- The featured pack rotates on a clock every server shares (os.time), so all servers agree.
Config.FEATURED_ROTATION_SECONDS = 3 * 3600
Config.FEATURED_SEED = 7331 -- salts the rotation order
Config.FEATURED_PRICE_MULT = 1.5
Config.FEATURED_LUCK = 2 -- rolls like a night pod
Config.FEATURED_MUTATION_MULT = 2
Config.FEATURED_EXCLUSIVE = "Celestial"
Config.FEATURED_EXCLUSIVE_CHANCE = 0.005

-- Robux bundles of featured packs. Stubs: set real developer product ids to enable. 0 = not configured.
export type DevProduct = { id: number, label: string, packs: number }
Config.DEVELOPER_PRODUCTS = {
	PackBundle1 = { id = 0, label = "1 Featured Pack", packs = 1 },
	PackBundle3 = { id = 0, label = "3 Featured Packs", packs = 3 },
	PackBundle10 = { id = 0, label = "10 Featured Packs", packs = 10 },
} :: { [string]: DevProduct }

-- What the shop needs to know about a player (profile or client stats snapshot).
export type ShopView = {
	money: number,
	speed: number,
	speedMultTier: number,
	treadmillTier: number,
	slots: number,
	income: number?,
}

-- Returns price and a short label, or nil if the item is sold out / unknown.
function Config.priceOf(itemId: string, v: ShopView): (number?, string?)
	if itemId == "Speed25" then
		local amount = math.max(Config.SPEED_BUY_MIN, math.floor(v.speed * Config.SPEED_BUY_FRACTION))
		return Config.speedCost(amount), `+{amount} Speed`
	elseif itemId == "SpeedMax" then
		local amount = math.floor(v.money / Config.PRICE_PER_SPEED)
		return Config.speedCost(amount), `+{amount} Speed`
	elseif itemId == "SpeedMult" then
		local nextTier = Config.SPEED_MULT_TIERS[v.speedMultTier + 1]
		if not nextTier then
			return nil, "Maxed"
		end
		return nextTier.price, `x{nextTier.mult} Speed Gain`
	elseif itemId == "Treadmill" then
		local nextTier = Config.TREADMILL_TIERS[v.treadmillTier + 1]
		if not nextTier then
			return nil, "Maxed"
		end
		return nextTier.price, `Treadmill x{nextTier.mult}`
	elseif itemId == "Slot" then
		if v.slots >= Config.SLOTS_MAX then
			return nil, "Maxed"
		end
		return math.floor(Config.SLOT_BASE_PRICE * Config.SLOT_PRICE_GROWTH ^ (v.slots - Config.SLOTS_START)), "+1 Plant Slot"
	elseif itemId == "SleepDust" then
		return Config.SLEEP_DUST_PRICE, "Sleep Dust"
	elseif Config.POTIONS[itemId] then
		local income = v.income or 0
		return math.max(Config.POTION_MIN_PRICE, math.floor(income * Config.POTION_INCOME_SECONDS)), Config.POTIONS[itemId].label
	end
	return nil, nil
end

----------------------------------------------------------------------------------------------------
-- Day / night (P3): derived from the clock, so server and client agree with no remote.
----------------------------------------------------------------------------------------------------
Config.DAY_SECONDS = 300
Config.NIGHT_SECONDS = 150
Config.NIGHT_LUCK = 2

function Config.dayPhase(now: number): (boolean, number)
	local cycle = Config.DAY_SECONDS + Config.NIGHT_SECONDS
	local t = now % cycle
	if t < Config.DAY_SECONDS then
		return false, Config.DAY_SECONDS - t -- isNight, seconds until it flips
	end
	return true, cycle - t
end

-- How "night" the lighting is, 0..1: eases in over the first NIGHT_FADE_SECONDS of the night and back
-- out over its last ones, so dusk and dawn are gradual. AmbientService blends day/night looks by it.
Config.NIGHT_FADE_SECONDS = 20

function Config.nightBlend(now: number): number
	local night, left = Config.dayPhase(now)
	if not night then
		return 0
	end
	local elapsed = Config.NIGHT_SECONDS - left
	local t = math.clamp(math.min(elapsed, left) / Config.NIGHT_FADE_SECONDS, 0, 1)
	return t * t * (3 - 2 * t)
end

----------------------------------------------------------------------------------------------------
-- Data
----------------------------------------------------------------------------------------------------
Config.DATASTORE_NAME = "StealASeed_v1"
Config.AUTOSAVE_INTERVAL = 90
Config.SAVE_RETRIES = 4

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
