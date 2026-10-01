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
-- Zones. The corridor is the concatenation of zone lengths (4,750 studs). The Meadow is short so a first seed is a quick grab.
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
	active: "day" | "night", -- this zone's plants earn ACTIVE_TIME_MULT during that phase
	wakeDelay: number, -- seconds between a steal and the guard's chase (its "❗" state); see Guards below
}

Config.ZONES = {
	{ id = "Meadow", name = "Meadow", req = 0, length = 200, icon = "🌼", active = "day", wakeDelay = 0.5,
		floor = Color3.fromRGB(104, 214, 70), wall = Color3.fromRGB(56, 152, 58), material = "Grass", ui = Color3.fromRGB(70, 180, 70),
		guard = "Giant Mole", guardColor = Color3.fromRGB(110, 80, 60),
		seed = "Sproutling", seedColor = Color3.fromRGB(120, 230, 90), baseWeight = 12 },
	{ id = "Desert", name = "Desert", req = 10e3, length = 450, icon = "🦂", active = "day", wakeDelay = 0,
		floor = Color3.fromRGB(240, 204, 124), wall = Color3.fromRGB(226, 164, 98), material = "Sand", ui = Color3.fromRGB(225, 145, 55),
		guard = "Giant Scorpion", guardColor = Color3.fromRGB(190, 90, 40),
		seed = "Cactopod", seedColor = Color3.fromRGB(60, 170, 90), baseWeight = 340 },
	{ id = "Jungle", name = "Jungle", req = 500e3, length = 600, icon = "🦖", active = "night", wakeDelay = 0.15,
		floor = Color3.fromRGB(66, 162, 60), wall = Color3.fromRGB(98, 126, 88), material = "LeafyGrass", ui = Color3.fromRGB(35, 140, 75),
		guard = "Giant Dino", guardColor = Color3.fromRGB(70, 150, 70),
		seed = "Fernosaur", seedColor = Color3.fromRGB(40, 200, 120), baseWeight = 9_500 },
	{ id = "Lava", name = "Lava Fields", req = 5e6, length = 700, icon = "🌋", active = "day", wakeDelay = 0.25,
		floor = Color3.fromRGB(58, 44, 48), wall = Color3.fromRGB(80, 44, 40), material = "Basalt", ui = Color3.fromRGB(225, 85, 30),
		guard = "Lava Golem", guardColor = Color3.fromRGB(240, 100, 30),
		seed = "Magmabloom", seedColor = Color3.fromRGB(255, 120, 40), baseWeight = 180_000 },
	{ id = "Snow", name = "Snow Peaks", req = 50e6, length = 800, icon = "❄️", active = "night", wakeDelay = 0.3,
		floor = Color3.fromRGB(238, 246, 255), wall = Color3.fromRGB(160, 206, 242), material = "Snow", ui = Color3.fromRGB(65, 150, 225),
		guard = "Giant Yeti", guardColor = Color3.fromRGB(220, 230, 245),
		seed = "Frostbulb", seedColor = Color3.fromRGB(120, 200, 255), baseWeight = 2_000_000 },
	{ id = "Space", name = "Deep Space", req = 500e6, length = 900, icon = "👽", active = "night", wakeDelay = 0.3,
		floor = Color3.fromRGB(30, 24, 70), wall = Color3.fromRGB(46, 36, 100), material = "Glass", ui = Color3.fromRGB(115, 75, 225),
		guard = "Big Alien", guardColor = Color3.fromRGB(120, 255, 120),
		seed = "Starpetal", seedColor = Color3.fromRGB(200, 120, 255), baseWeight = 45_000_000 },
	{ id = "Spirit", name = "Spirit Garden", req = 5e9, length = 1100, icon = "⛩️", active = "day", wakeDelay = 0.5,
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
-- The guard runs exactly as fast as a player at the zone's recommended Speed, so that player escapes on
-- the head start alone: the ~28 studs between the pods and the sleeping guard (GUARD_HOME_OFFSET), plus
-- the zone's wakeDelay. The delay is slack for reaction time and lag, but it also lets slower players
-- escape. Each zone's delay keeps the lowest escaping Speed >= 50% of the sign (tests/guard.spec) with
-- about 0.5 s of slack. Longer runs home (later zones) can afford more. The Desert's short run can't
-- have both, so it gets 0 (0.3 s of slack).
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

-- Deeper zones and luck (night) tilt the odds toward the rare end.
Config.ZONE_RARITY_BONUS = 0.1
Config.NIGHT_LUCK = 2 -- pods roll with this luck at night; premium packs always do (PACK_LUCK)

function Config.rarityWeights(k: number, luck: number): { number }
	local tilt = luck * (1 + Config.ZONE_RARITY_BONUS * (k - 1))
	local out = {}
	for i, r in Config.RARITIES do
		out[i] = r.spawn * tilt ^ (i - 1)
	end
	return out
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
-- In-game money buys only two things: trails (Speed gain, see Shop below) and plot upgrades. Speed is
-- earned by moving, or bought with Robux. Plant income is anchored to the zones' recommended Speed: a
-- full plot (ECONOMY_SLOTS) of zone-k Commons earns zone k+1's recommended Speed, in dollars, in
-- PAYBACK_SECONDS. That keeps the money scale of older saves unchanged.
Config.SLOTS_START = 5 -- plant slots at plot level 1
Config.SLOTS_MAX = 30 -- plant slots at the last plot level (the ExtraSlots gamepass adds on top)
Config.ECONOMY_SLOTS = 10 -- the plot size income is balanced for; independent of SLOTS_START
Config.PAYBACK_SECONDS = 300
Config.PAYOUT_INTERVAL = 3

-- Common, sprout-weight income per plant for zone k ($/s)
function Config.seedIncome(k: number): number
	local nextZone = Config.ZONES[k + 1]
	local nextReq = if nextZone then nextZone.req else Config.ZONES[k].req * 10
	return nextReq / (Config.ECONOMY_SLOTS * Config.PAYBACK_SECONDS)
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
-- Shop. In-game money buys only two things: TRAILS and PLOT UPGRADES (Config.priceOf). Everything else
-- is Robux: developer products (DEVELOPER_PRODUCTS below) and gamepasses. Rules live in Server/Shop.
----------------------------------------------------------------------------------------------------
-- Trails: a coloured Trail behind the player (Server/TrailService) that multiplies the Speed gained from
-- walking and the treadmill. Players own trails (saved) and equip one at a time. Grey is free: everyone
-- owns it and starts with it equipped. Any other tier can be bought directly, for money (`price`) or
-- Robux (the `product` developer product); there is no need to own the tier below.
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
	{ id = "Grey", name = "Grey Trail", rarity = "Common", mult = 1.5, price = 0, color = Color3.fromRGB(175, 178, 190) },
	{ id = "Green", name = "Green Trail", rarity = "Uncommon", mult = 2, price = 5e3, product = "TrailGreen", color = Color3.fromRGB(70, 215, 90) },
	{ id = "Blue", name = "Blue Trail", rarity = "Rare", mult = 2.5, price = 75e3, product = "TrailBlue", color = Color3.fromRGB(55, 145, 255) },
	{ id = "Purple", name = "Purple Trail", rarity = "Epic", mult = 3, price = 1.5e6, product = "TrailPurple", color = Color3.fromRGB(165, 75, 255) },
	{ id = "Golden", name = "Golden Trail", rarity = "Legendary", mult = 3.5, price = 30e6, product = "TrailGolden", color = Color3.fromRGB(255, 195, 35) },
	{ id = "Red", name = "Red Trail", rarity = "Mythic", mult = 4, price = 600e6, product = "TrailRed", color = Color3.fromRGB(235, 45, 55) },
	{ id = "Rainbow", name = "Rainbow Trail", rarity = "Secret", mult = 5, price = 15e9, product = "TrailRainbow", color = Color3.fromRGB(255, 90, 200), rainbow = true },
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

-- Plot upgrades (money only). Level 1 has SLOTS_START slots. Each level adds one slot (SLOTS_MAX at
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

-- Treadmill tiers. Tier 1 is free; the others are Robux (`product`). A tier can be bought directly.
Config.TREADMILL_TIERS = {
	{ mult = 2 },
	{ mult = 3, product = "TreadmillX3" },
	{ mult = 5, product = "TreadmillX5" },
} :: { { mult: number, product: string? } }
Config.SLEEP_DUST_EXTRA = 5 -- guard stays asleep this much longer
Config.SLEEP_DUST_RANGE = 60
Config.SLEEP_DUST_LASTS = 60 -- a dusted nest stays dusted this long
Config.START_ITEMS = { SleepDust = 3 } :: { [string]: number }

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
Config.PACK_LUCK = Config.NIGHT_LUCK -- packs roll rarities like a night pod in their zone...
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
--   Treadmill the treadmill at TREADMILL_TIERS[`tier`]
--   Dust      `count` Sleep Dust
--   Trail     owns and equips Config.TRAILS[`trail`]
----------------------------------------------------------------------------------------------------
export type DevProduct = {
	id: number,
	kind: string,
	label: string,
	robux: number,
	zone: number?,
	amount: number?,
	minutes: number?,
	tier: number?,
	count: number?,
	trail: string?,
}
Config.DEVELOPER_PRODUCTS = {
	PackSpace = { id = 0, kind = "Pack", label = "Starpetal Pack", robux = 2000, zone = 6 },
	PackSpirit = { id = 0, kind = "Pack", label = "Lotus Wyrm Pack", robux = 3000, zone = 7 },

	Speed150K = { id = 0, kind = "Speed", label = "+150K Speed", robux = 64, amount = 150e3 },
	Speed1M = { id = 0, kind = "Speed", label = "+1M Speed", robux = 200, amount = 1e6 },
	Speed10M = { id = 0, kind = "Speed", label = "+10M Speed", robux = 560, amount = 10e6 },
	Speed50M = { id = 0, kind = "Speed", label = "+50M Speed", robux = 1200, amount = 50e6 },
	Speed500M = { id = 0, kind = "Speed", label = "+500M Speed", robux = 1600, amount = 500e6 },
	Speed1B = { id = 0, kind = "Speed", label = "+1B Speed", robux = 2400, amount = 1e9 },

	Money24K = { id = 0, kind = "Money", label = "Pocket Cash", robux = 40, amount = 24e3, minutes = 10 },
	Money200K = { id = 0, kind = "Money", label = "Cash Bag", robux = 80, amount = 200e3, minutes = 30 },
	Money800K = { id = 0, kind = "Money", label = "Cash Stack", robux = 200, amount = 800e3, minutes = 60 },
	Money4M = { id = 0, kind = "Money", label = "Cash Crate", robux = 400, amount = 4e6, minutes = 180 },
	Money8M = { id = 0, kind = "Money", label = "Cash Vault", robux = 640, amount = 8e6, minutes = 360 },

	TreadmillX3 = { id = 0, kind = "Treadmill", label = "Treadmill x3", robux = 60, tier = 2 },
	TreadmillX5 = { id = 0, kind = "Treadmill", label = "Treadmill x5", robux = 200, tier = 3 },

	SleepDust3 = { id = 0, kind = "Dust", label = "3 Sleep Dust", robux = 25, count = 3 },

	TrailGreen = { id = 0, kind = "Trail", label = "Green Trail", robux = 16, trail = "Green" },
	TrailBlue = { id = 0, kind = "Trail", label = "Blue Trail", robux = 24, trail = "Blue" },
	TrailPurple = { id = 0, kind = "Trail", label = "Purple Trail", robux = 40, trail = "Purple" },
	TrailGolden = { id = 0, kind = "Trail", label = "Golden Trail", robux = 64, trail = "Golden" },
	TrailRed = { id = 0, kind = "Trail", label = "Red Trail", robux = 100, trail = "Red" },
	TrailRainbow = { id = 0, kind = "Trail", label = "Rainbow Trail", robux = 180, trail = "Rainbow" },
} :: { [string]: DevProduct }

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
}

-- The money price and a short label of a money item ("PlotUpgrade" or "Trail:<id>"), or nil (with
-- "Maxed"/"Owned", or nothing for anything that isn't sold for money).
function Config.priceOf(itemId: string, v: ShopView): (number?, string?)
	if itemId == "PlotUpgrade" then
		if v.plotLevel >= Config.PLOT_LEVEL_MAX then
			return nil, "Maxed"
		end
		return Config.plotUpgradePrice(v.plotLevel + 1), `Plot Level {v.plotLevel + 1}`
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
