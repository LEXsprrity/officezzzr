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
Config.PLOT_FIRST_X = -6 -- the front plots end 24 studs before the corridor mouth (room for the free gift)
Config.PLOT_OFFSET_Z = 84 -- plots sit at z = +/-84, the walkway runs down z = 0
-- The base's spots fill column by column from the corridor mouth (-X), alternating sides of the walkway: odd
-- spots at +Z, even ones at -Z. The shop plaza takes spot PLAZA_SPOT (the -Z side of the front column, by the
-- corridor mouth: owner request); the plots fill the other spots in order (Config.plotSpot).
Config.PLAZA_SPOT = 2

-- The middle of spot `spot` on the ground: its (x, z).
function Config.spotXZ(spot: number): (number, number)
	local col = (spot - 1) // 2
	local side = if spot % 2 == 1 then 1 else -1
	return Config.PLOT_FIRST_X - col * Config.PLOT_SPACING_X, side * Config.PLOT_OFFSET_Z
end

-- The spot plot `index` stands in: the plots skip the plaza's spot, so plot 1 is nearest the corridor mouth.
function Config.plotSpot(index: number): number
	return if index >= Config.PLAZA_SPOT then index + 1 else index
end
Config.WALKWAY_WIDTH = 36 -- the sand walkway down z = 0; the 24 studs between it and a plot's front fence hold its treadmill
-- Inside a plot (owner's reference): two brown dirt beds, left and right, with a grass path down the middle
-- from the entrance. Players plant anywhere on their own beds (Shared/Planting).
Config.PLOT_PATH_WIDTH = 20 -- the grass path between the beds
Config.BED_FENCE_GAP = 1.5 -- from a bed's outer edges to the fence line
Config.BED_HEIGHT = 0.4 -- the beds' depth: their tops are level with the plot's grass (owner: level ground); plants stand on top
Config.SLOT_SPACING = 8 -- the default planting grid (old saves, auto-placing); creature sizes are budgeted against it
-- Spacing (owner 2026-10-15: "gardens look sparse"): plants may stand right next to each other, their leaves
-- overlapping, but never on top of each other: only their stems / cores (PLANT_CORE_SHARE of their full-grown
-- reach, Planting.coreRadius) may not overlap. The server and the planting preview share the rule (Shared/Planting).
Config.PLANT_CORE_SHARE = 0.45 -- a plant's core: this share of its full-grown reach (Planting.radius)
Config.PLANT_BED_MARGIN = 1 -- a plant's centre stays at least this far inside its bed (its core, if bigger)
Config.PLANT_FENCE_OVERHANG = 2.5 -- a big full-grown plant may reach this far past its bed's fence gap (Planting.bedMargin)
Config.PLANT_YAW_STEP = 15 -- the planting ghost turns this many degrees a wheel notch / button press (Planting.client)
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
-- small multiplier (Config.speedPerStud). A treadmill pays its tier's fixed rate x the trail instead
-- (Config.treadmillPerSecond). Nothing grows with the Speed you already have and there are no levels: a player progresses by running faster (WalkSpeed
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
	wall: Color3, -- side walls (with a lighter checker on their inner face): a darker shade of the zone's ground, unlike any other zone's
	ui: Color3, -- saturated card colour for the HUD
	guard: string,
	guardColor: Color3,
	seed: string, -- creature name
	seedColor: Color3,
	baseWeight: number, -- Kg of a sprouted Common, before growth
	icon: string,
	active: "day" | "night", -- this zone's plants earn ACTIVE_TIME_MULT during that phase
	wakeDelay: number, -- slack (s) on top of the guard's head start before it chases (Config.wakeDelay; see Guards below)
}

Config.ZONES = {
	{ id = "Meadow", name = "Meadow", req = 0, length = Config.zoneLength(1), icon = "🌼", active = "day", wakeDelay = 0,
		floor = Color3.fromRGB(106, 196, 50), wall = Color3.fromRGB(196, 128, 80), ui = Color3.fromRGB(70, 180, 70),
		guard = "Giant Turtle", guardColor = Color3.fromRGB(90, 170, 80),
		seed = "Sproutling", seedColor = Color3.fromRGB(120, 230, 90), baseWeight = 12 },
	{ id = "Desert", name = "Desert", req = 25e3, length = Config.zoneLength(2), icon = "🦂", active = "day", wakeDelay = 0,
		floor = Color3.fromRGB(240, 210, 140), wall = Color3.fromRGB(210, 164, 94), ui = Color3.fromRGB(225, 145, 55),
		guard = "Red Mole", guardColor = Color3.fromRGB(190, 60, 50),
		seed = "Cactopod", seedColor = Color3.fromRGB(60, 170, 90), baseWeight = 340 },
	{ id = "Jungle", name = "Jungle", req = 500e3, length = Config.zoneLength(3), icon = "🦖", active = "night", wakeDelay = 0,
		floor = Color3.fromRGB(58, 168, 72), wall = Color3.fromRGB(60, 108, 60), ui = Color3.fromRGB(35, 140, 75),
		guard = "Giant Snake", guardColor = Color3.fromRGB(70, 150, 70),
		seed = "Fernosaur", seedColor = Color3.fromRGB(40, 200, 120), baseWeight = 9_500 },
	{ id = "Lava", name = "Lava Fields", req = 2.5e6, length = Config.zoneLength(4), icon = "🌋", active = "day", wakeDelay = 0,
		floor = Color3.fromRGB(92, 58, 66), wall = Color3.fromRGB(56, 42, 50), ui = Color3.fromRGB(225, 85, 30),
		guard = "Volcano Gorilla", guardColor = Color3.fromRGB(240, 100, 30),
		seed = "Magmabloom", seedColor = Color3.fromRGB(255, 120, 40), baseWeight = 180_000 },
	{ id = "Snow", name = "Snow Peaks", req = 7.5e6, length = Config.zoneLength(5), icon = "❄️", active = "night", wakeDelay = 0,
		floor = Color3.fromRGB(232, 242, 255), wall = Color3.fromRGB(150, 184, 212), ui = Color3.fromRGB(65, 150, 225),
		guard = "Ice Shark", guardColor = Color3.fromRGB(160, 210, 240),
		seed = "Frostbulb", seedColor = Color3.fromRGB(120, 200, 255), baseWeight = 2_000_000 },
	{ id = "Space", name = "Deep Space", req = 25e6, length = Config.zoneLength(6), icon = "👽", active = "night", wakeDelay = 0,
		floor = Color3.fromRGB(64, 48, 134), wall = Color3.fromRGB(40, 30, 92), ui = Color3.fromRGB(115, 75, 225),
		guard = "Void Dragon", guardColor = Color3.fromRGB(120, 60, 200),
		seed = "Starpetal", seedColor = Color3.fromRGB(200, 120, 255), baseWeight = 45_000_000 },
	{ id = "Spirit", name = "Spirit Garden", req = 75e6, length = Config.zoneLength(7), icon = "⛩️", active = "day", wakeDelay = 0,
		floor = Color3.fromRGB(112, 200, 98), wall = Color3.fromRGB(140, 140, 210), ui = Color3.fromRGB(225, 75, 130),
		guard = "Lumistag", guardColor = Color3.fromRGB(140, 220, 255),
		seed = "Lotus Wyrm", seedColor = Color3.fromRGB(255, 150, 200), baseWeight = 900_000_000 },
} :: { Zone }

-- Where each zone starts along X, the nest (where the boss sleeps by its seed pods), and the end of the line.
Config.NEST_FRACTION = 0.85 -- nest sits this far into its zone...
Config.GUARD_HOME_OFFSET = 24 -- the guard sleeps this many studs past the nest's centre (+X)
Config.NEST_END_CLEARANCE = 12 -- ...but its guard sleeps at least this far before the zone's end (the short Meadow)
-- The nest is ALL the way on the LEFT of a runner coming from the base (-Z; owner request): the boss sleeps
-- with its flank against the left wall. The widest boss reaches ~14.2 studs to each side of its root and
-- GuardAnimator keeps bodies a stud inside the wall's inner face (96), so its root sits at 80. The wall
-- props there make room for it (ZoneThemes.nestKeepOut).
Config.NEST_Z = -80

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

-- The nest's centre on the ground (WorldBuilder builds the nest there; the guard's home is GUARD_HOME_OFFSET
-- further along +X).
function Config.nestCenter(k: number): Vector3
	return Vector3.new(Config.nestX(k), Config.GROUND_Y, Config.NEST_Z)
end

-- How far each zone's sleeping boss reaches from its root (studs; it sleeps facing the base, -X):
--   side:  toward the middle of the corridor (+Z), half its model's width;
--   front: toward the base (-X), its model's front (-Z).
-- Each is its rest bounds (as GuardAnimator measures them: BossRigs halfWidth where its pose differs) or
-- its sleeping bones plus 2.5 studs of body, whichever reaches further (the Giant Snake sleeps curled up,
-- the Volcano Gorilla lies forward). tests/bosses.spec measures both from the Guard assets.
Config.BOSS_REACH = {
	Meadow = { side = 7.1, front = 11.3 },
	Desert = { side = 14.2, front = 16.2 },
	Jungle = { side = 11, front = 17.8 },
	Lava = { side = 14.8, front = 18.2 },
	Snow = { side = 11.9, front = 13.2 },
	Space = { side = 14.3, front = 9.3 },
	Spirit = { side = 7.1, front = 8.1 },
} :: { [string]: { side: number, front: number } }

-- Where seed pod `i` of zone `k` sits, from the nest's centre: RIGHT next to the sleeping boss (owner
-- request and reference, docs/references/11-pods-by-the-boss.png): a loose little cluster at its right,
-- between it and the middle of the corridor (+Z), a few studs off its flank and at about its depth (around
-- its root, not ahead of it toward the base), each resting on the floor, a little different in every
-- zone. There is no head start along the run home any more: the guard's wake-up gives it instead
-- (Config.wakeDelay).
local POD_SCATTER = { { -5.5, 3 }, { -1, 6.5 }, { 3.5, 3 }, { 5.5, 7.5 }, { -4.5, 9.5 }, { 1.5, 11 } } -- { along its body, off its flank }
function Config.podOffset(k: number, i: number): Vector3
	local base = POD_SCATTER[(i - 1) % #POD_SCATTER + 1]
	local jx = ((k * 13 + i * 7) % 5 - 2) * 0.3
	local jz = ((k * 11 + i * 5) % 7 - 3) * 0.2
	local flank = Config.BOSS_REACH[Config.ZONES[k].id].side
	-- (the pod, a 3-stud ball, rests on the floor)
	return Vector3.new(Config.GUARD_HOME_OFFSET + base[1] + jx, 1.5, flank + base[2] + jz)
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
-- the head start alone. The pods lie right by the sleeping guard (10-16 studs from its root), so the head
-- start is its wake-up (the "❗"), and it has to cover the thief NOTICING the steal first: the Pickup
-- reaching their client, a human's reaction, and the server seeing their first steps (their position
-- replicates late). Until then they stand by the pod, within a tick of the guard's reach, so a wake-up
-- shorter than that catches them on its first tick whatever their Speed (owner playtest: 100M in the Spirit
-- Garden, caught "as soon as I take the seed" when it woke after 0.26 s). So it lasts WAKE_REACTION, then
-- as long as a recommended-Speed thief takes to run GUARD_HEAD_START studs, plus the zone's wakeDelay.
-- Slack also lets slower players escape: the shorter the run home, the less a slower thief loses on the
-- way. With the zone lengths above a recommended-Speed thief may start running 0.55-0.75 s after the
-- steal (with 0.1 s of server lag on top), and a quick one (0.2 s) escapes from ~47-70% of the sign
-- (tests/guard.spec, tests/steal_flow; the recommended Speeds are only ~3-4x apart from the Lava Fields
-- on, so a thief can't be far below the sign). The Meadow (req 0) is the tutorial.
Config.GUARD_SPEED_FACTOR = 1 -- chase WalkSpeed = walkSpeedFor(zone.req) * this
Config.GUARD_RETURN_FACTOR = 0.6 -- walking home is slower than chasing
Config.CATCH_DISTANCE = 6 -- horizontal studs, root to root
Config.CHASE_TIMEOUT = 45
Config.GUARD_SCALE = 3 -- body size multiplier ("giant")
Config.KNOCKBACK_STUDS = 30
Config.CATCH_STUN = 1 -- seconds the caught player can't move
Config.GUARD_HEAD_START = 28 -- studs a recommended-Speed thief runs while the guard wakes up (Config.wakeDelay)
Config.WAKE_REACTION = 0.5 -- s of every wake-up for the thief to notice the steal and start running (see above)

function Config.guardChaseSpeed(k: number): number
	return Config.walkSpeedFor(Config.ZONES[k].req) * Config.GUARD_SPEED_FACTOR
end

-- Seconds between a steal and zone k's guard's chase (its "❗" state): WAKE_REACTION, then the time a thief
-- at the recommended Speed takes to run GUARD_HEAD_START studs, plus the zone's wakeDelay slack. At least
-- 0.66 s (the Spirit Garden), about as long as the boss's wake-up hop (BossRigs.WAKE_TIME).
function Config.wakeDelay(k: number): number
	return Config.WAKE_REACTION + Config.GUARD_HEAD_START / Config.guardChaseSpeed(k) + Config.ZONES[k].wakeDelay
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
Config.POD_REFRESH = 180 -- seconds an untouched pod keeps its seed before it re-rolls (each pod on its own clock)
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
Config.NIGHT_LUCK = 1.5 -- pods roll with this luck at night (owner: x1.5)

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

-- "Alex got a LEGENDARY Gold Nebula Rose!" once it is planted (`plantName`: its flower, after its mutation),
-- "Alex got a LEGENDARY Gold Seed!" from a pack (the flower is a surprise until it is planted).
function Config.legendaryAnnouncement(playerName: string, zone: number, mutation: string?, plantName: string?): string
	local prefix = if mutation then mutation .. " " else ""
	return `🌟 {playerName} got a LEGENDARY {plantName or prefix .. "Seed"}!`
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

-- The 2x Luck pass. A pod is one seed everybody sees, rolled with the world's luck (`luck`: night or day,
-- when it grew), so the pass works when its owner steals it: the rarity they get is re-drawn as if the pod
-- had been rolled with `luck * luckMult`, and never lower than what the pod showed. It is a quantile
-- coupling: the pod's rarity `rarity` stands for a slice [F(rarity - 1), F(rarity)) of the world-luck
-- odds' cumulative distribution F; a point u drawn uniformly in that slice is read back on the lucky
-- odds' G instead. G <= F everywhere (more luck only moves weight up, and Legendary gets luckMult x its
-- chance), so the result is never below `rarity`, and over all pods the owner's rarities follow exactly
-- the luckMult-luck odds: a true 2x luck, no bonus re-roll on top. Returns the rarity (the pod's own when
-- luckMult <= 1).
function Config.luckUpgrade(k: number, rarity: number, luck: number, luckMult: number, rng: () -> number): number
	if luckMult <= 1 or rarity >= Config.LEGENDARY then
		return rarity
	end
	local base = Config.rarityWeights(k, luck)
	local lucky = Config.rarityWeights(k, luck * luckMult)
	local lo = 0
	for i = 1, rarity - 1 do
		lo += base[i]
	end
	local u = lo + rng() * base[rarity]
	local out = #lucky
	for i, w in lucky do
		u -= w
		if u < 0 then
			out = i
			break
		end
	end
	return math.max(out, rarity)
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
-- Plant income scale on top of ZONE_CASH: x1.25 since day/night went from x1.5 / x1 to x1 / x0.8, so a
-- plant peaks at 1.25x its old base (was 1.5x) and the zones still come at the agreed pace.
Config.INCOME_SCALE = 1.25
Config.PAYOUT_INTERVAL = 1 -- seconds; each pass pays one second of income, so a plant's popup is its $/s
Config.ZONE_CASH = { 0, 10e3, 500e3, 5e6, 50e6, 500e6, 5e9 } -- per zone, in Config.ZONES order

-- Common, sprout-weight income per plant for zone k ($/s)
function Config.seedIncome(k: number): number
	local nextCash = Config.ZONE_CASH[k + 1] or Config.ZONE_CASH[k] * 10
	return nextCash / (Config.ECONOMY_SLOTS * Config.PAYBACK_SECONDS) * Config.INCOME_SCALE
end

-- Growth (P2): closed form from plantedAt, never simulated per tick.
Config.GROW_TIME = 20 * 60 -- seconds to full size
Config.GROW_MAX_FACTOR = 5 -- full-grown weight / sprout weight

-- Stable per-plant variance in [0.8, 1.2), derived from what we already save.
function Config.plantVariance(plantedAt: number, slot: number): number
	local x = math.sin(plantedAt * 12.9898 + slot * 78.233) * 43758.5453
	return 0.8 + 0.4 * (x - math.floor(x))
end

-- A plant's variance: the one it kept from before (a plant moved to the inventory and planted again keeps
-- its weight), else the stable one from its planting time and id.
function Config.varianceOf(plant: { plantedAt: number, slot: number, variance: number? }): number
	return plant.variance or Config.plantVariance(plant.plantedAt, plant.slot)
end

-- A seed's gene (owner request: the planting ghost shows exactly what will grow): a whole number drawn when
-- the seed is (a pod's roll, a pack, a seed stored in the bag), carried with it and kept in its bag key. It
-- decides the plant the seed grows into, though no label ever says so until it is planted: its flower
-- (gene-th of the zone's plant models of its rarity, wrapping round: SEED_GENES is a multiple of every count
-- up to 16, so each flower is as likely) and its weight variance (geneVariance).
Config.SEED_GENES = 720720
function Config.rollGene(rng: () -> number): number
	return math.clamp(math.floor(rng() * Config.SEED_GENES) + 1, 1, Config.SEED_GENES)
end

-- The weight variance a seed with this gene grows with, in plantVariance's range.
function Config.geneVariance(gene: number): number
	return Config.plantVariance(gene, 0)
end

-- Which of its zone's `count` seed designs (assets/Seed_<ZoneId>) a seed with this gene looks like: drawn
-- from the gene apart from its flower, and whatever its rarity, so a pod, the seed carried from it and the
-- same seed in the bag all look alike. 1 when the gene is unknown (a bag seed from before genes).
function Config.geneDesign(gene: number?, count: number): number
	if not gene or count <= 1 then
		return 1
	end
	local x = math.sin(gene * 39.3467 + 11.135) * 15731.743
	return math.clamp(math.floor((x - math.floor(x)) * count) + 1, 1, count)
end

function Config.sproutWeight(k: number, rarity: number): number
	return Config.ZONES[k].baseWeight * Config.RARITIES[rarity].weight
end

-- How far a plant planted at `plantedAt` has grown at `now`, in seconds of growth: real time x `growMult`
-- (the owner's Fast Grow pass, Config.passGrowMult; 1 when nil). Read from plantedAt like everything else,
-- so time offline counts at the same rate.
function Config.plantAge(plantedAt: number, now: number, growMult: number?): number
	return math.max(now - plantedAt, 0) * (growMult or 1)
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

-- Sprouting: a seed planted from the bag or carried home first stands as a seedling (a dirt mound and a
-- sprout, PlotService) that earns nothing, for sproutTime(zone, rarity) seconds; then it pops into its
-- flower and its growth curve (GROW_TIME, plantAge) starts from there. It is an absolute time (the plant's
-- `sproutUntil`), so it goes on offline. Base time by rarity x a zone factor rising evenly with depth
-- (Meadow x1 .. Spirit Garden x2.5), rounded to SPROUT_ROUND seconds: a Meadow Common 30 s, a Spirit
-- Garden Legendary 50 min (tests/progression_sim: the free timeline still lands ~12 h, README). The owner's
-- Fast Grow pass divides it (Config.passGrowMult), like growth. "Grow now" (the GrowNow products below)
-- skips what is left for Robux.
Config.SPROUT_BASE = { 30, 60, 180, 480, 1200 } -- seconds, Config.RARITIES order (Common .. Legendary)
Config.SPROUT_ZONE_STEP = 0.25 -- the zone factor grows this much per zone: 1, 1.25, 1.5 .. 2.5
Config.SPROUT_ROUND = 5

function Config.sproutZoneFactor(zone: number): number
	return 1 + Config.SPROUT_ZONE_STEP * (zone - 1)
end

-- Seconds a fresh seed of (zone, rarity) sprouts for. `growMult`: the owner's Fast Grow (1 when nil).
function Config.sproutTime(zone: number, rarity: number, growMult: number?): number
	local base = (Config.SPROUT_BASE[rarity] or Config.SPROUT_BASE[1]) * Config.sproutZoneFactor(zone) / math.max(growMult or 1, 1)
	return math.max(Config.SPROUT_ROUND, math.floor(base / Config.SPROUT_ROUND + 0.5) * Config.SPROUT_ROUND)
end
Config.SPROUT_MAX = Config.sproutTime(7, 5) -- the longest sprout (a Spirit Garden Legendary); saves are clamped to it

-- Seconds a plant still sprouts at `now` (0: it is a flower). Plants from before sprouting have no sproutUntil.
function Config.sproutLeft(plant: { sproutUntil: number? }, now: number): number
	local untilAt = plant.sproutUntil
	return if untilAt then math.max(untilAt - now, 0) else 0
end

function Config.isSprouting(plant: { sproutUntil: number? }, now: number): boolean
	return Config.sproutLeft(plant, now) > 0
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
-- The SELL stall in the shop plaza is the only place plants are sold (the Plants panel's Remove puts a
-- plant in the inventory, for no money): 10x its $/s, i.e. 10 s of the plant's base income (no day/night)
-- x the plot level / 2x Money multiplier (owner 2026-10-15: 2 min paid far too much). A plant keeps
-- earning forever, so selling is only worth it to make room.

Config.SELL_STALL_SECONDS = 10
-- Seeds from the seed bag sell at the stall too: SEED_SELL_SECONDS of the income the seed would have right
-- when it sprouts (its sprout weight, mutation included, no variance) x the same money multiplier, at least
-- $1. Planted, the same seed sells for 10 s of at least ~0.9x that income (the lowest weight variance), so a
-- seed is always worth less than its plant.
Config.SEED_SELL_SECONDS = 5

function Config.seedSellPrice(zone: number, rarity: number, mutation: string?, moneyMult: number?): number
	local income = Config.plantIncome(zone, rarity, Config.sproutWeight(zone, rarity), mutation)
	return math.max(1, income * Config.SEED_SELL_SECONDS * (moneyMult or 1))
end
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
-- the trail times the Speed passes (`passMult`: Config.passSpeedMult, 1 when nil), whatever your Speed.
-- The HUD shows it as "+X/step".
function Config.speedPerStud(trailId: string?, passMult: number?): number
	return Config.BASE_SPEED_PER_STUD * Config.trailMult(trailId) * (passMult or 1)
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

-- Everything that multiplies plant income except day/night: the plot level and the money passes (2x Money,
-- VIP: Config.passMoneyMult; `passes` may also be just whether the player has 2x Money). The payout loop,
-- offline income, removal refunds and income-based Robux grants all use it.
function Config.moneyMult(plotLevel: number, passes: { [string]: boolean } | boolean | nil): number
	local owned = if type(passes) == "table" then passes else { DoubleMoney = passes == true }
	return Config.plotMoneyMult(plotLevel) * Config.passMoneyMult(owned)
end

-- Treadmill tiers: standing on your own treadmill pays a FIXED Speed per second for its tier (`perSecond`)
-- times the equipped trail's multiplier (Config.trailMult, x1 .. x3), and nothing else: not your WalkSpeed,
-- not the Speed you already have (owner decision: "level 1 -> X Speed/s always"). AFK works.
-- Tier 1 is free. Each next tier is bought one at a time, at the treadmill itself (its owner-only E/F
-- prompts) or in the Shop: for money (`price`, Config.priceOf "TreadmillUpgrade") or Robux (one tier per
-- TreadmillT1..T3 receipt, Config.treadmillUpgradeProduct). Prices grow x10 a tier: level 1 pays +100/s,
-- each level +100/s more up to +800/s, then +1K and +1.5K/s (x the trail: up to x3 with the Rainbow). A
-- free player buys level 2 after ~11 minutes and level 9 near the Spirit Garden; level 10 is a late-game
-- sink like the last plot levels. Tuned with tests/progression_sim, together with the zones' recommended
-- Speed: a free player who buys these lands every zone near its target, and an AFK farmer (fills the plot
-- once, then only stands on the treadmill) is far slower than a player who keeps running the corridor
-- (README "Progression").
export type TreadmillTier = { perSecond: number, price: number }
Config.TREADMILL_TIERS = {
	{ perSecond = 100, price = 0 },
	{ perSecond = 200, price = 1e6 },
	{ perSecond = 300, price = 10e6 },
	{ perSecond = 400, price = 100e6 },
	{ perSecond = 500, price = 1e9 },
	{ perSecond = 600, price = 10e9 },
	{ perSecond = 700, price = 100e9 },
	{ perSecond = 800, price = 1e12 },
	{ perSecond = 1000, price = 10e12 },
	{ perSecond = 1500, price = 100e12 },
} :: { TreadmillTier }
Config.TREADMILL_MAX = #Config.TREADMILL_TIERS

-- The tier a saved or sent value means (clamped, so a bad tier never errors; anything else is tier 1).
function Config.treadmillTierOf(tier: any): number
	local t = if type(tier) == "number" and tier == tier then tier else 1
	return math.clamp(math.floor(t), 1, Config.TREADMILL_MAX)
end

-- The fixed Speed per second of treadmill tier `tier`, before the trail.
function Config.treadmillRate(tier: number?): number
	return Config.TREADMILL_TIERS[Config.treadmillTierOf(tier)].perSecond
end

-- What a second on a treadmill of tier `tier` pays with trail `trailId` equipped: the tier's fixed rate x
-- the trail x the Speed passes (`passMult`: Config.passSpeedMult, 1 when nil), at any Speed or WalkSpeed.
-- SpeedLogic.treadmillGain pays it a tick at a time; the "+X/s" text over the belt, the popups over the
-- runner, the Upgrade board and the Shop show it (Treadmill.perSecond).
function Config.treadmillPerSecond(tier: number?, trailId: string?, passMult: number?): number
	return Config.treadmillRate(tier) * Config.trailMult(trailId) * (passMult or 1)
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

-- Gamepasses: their ids come from monetization/ids.json (Config.applyMonetizationIds, below the developer
-- products); id = 0 = not set up yet (the Shop says "coming soon"). Ownership is only ever decided on the server (ShopService: UserOwnsGamePassAsync
-- at join, and again when PromptGamePassPurchaseFinished reports a purchase) into Sessions.passes; the
-- client only shows it.
-- `robux` is the placeholder price shown until the real one (Dashboard) is read with GetProductInfo;
-- `about` is the Shop card's benefit line; `icon` its Icons key (2x Money: the cash, on a gold "x2" coin; VIP: the
-- VIP ticket; nil: a gold "VIP" badge); `order` its place.
export type Gamepass = { id: number, label: string, robux: number, about: string, icon: string?, order: number }
Config.GAMEPASSES = {
	DoubleMoney = { label = "2x Money", robux = 0, about = "Doubles all plant income", icon = "Money", order = 1 },
	DoubleSpeed = { label = "2x Speed", robux = 299, about = "Walk + treadmill Speed x2", icon = "Speed", order = 2 },
	DoubleLuck = { label = "2x Luck", robux = 249, about = "Rarer seeds when you steal", icon = "Star", order = 3 },
	VIP = { label = "VIP", robux = 399, about = "Gold tag, x1.25 cash + Speed", icon = "Vip", order = 4 },
	FastGrow = { label = "Fast Grow", robux = 149, about = "Your plants grow 2x faster", icon = "Seeds", order = 5 },
	ExtraSlots = { label = "+10 Plant Slots", robux = 0, about = "On top of your plot level's slots", icon = "ExtraSlots", order = 6 },
} :: { [string]: Gamepass }
Config.PASS_EXTRA_SLOTS = 10 -- the ExtraSlots pass adds this many slots, on top of the plot level's
Config.PASS_SPEED_MULT = 2 -- 2x Speed: every Speed gain (walking and treadmill)
Config.PASS_LUCK_MULT = 2 -- 2x Luck: the luck a stolen seed's rarity is rolled with (Config.luckUpgrade)
Config.PASS_GROW_MULT = 2 -- Fast Grow: plants age this much faster (Config.plantAge), offline too
Config.VIP_MULT = 1.25 -- VIP: money and Speed, multiplied with the other passes

-- The pass names in Shop order.
function Config.passNames(): { string }
	local names = {}
	for name in Config.GAMEPASSES do
		table.insert(names, name)
	end
	table.sort(names, function(a, b)
		return Config.GAMEPASSES[a].order < Config.GAMEPASSES[b].order
	end)
	return names
end

-- What the passes a player owns (`passes`: Sessions.passes, or the client's copy of it; nil = none) do.
-- Everything multiplies: 2x Speed and VIP give x2.5 Speed, 2x Money and VIP x2.5 money.
type Owned = { [string]: boolean }?
function Config.passSpeedMult(passes: Owned): number
	local p = passes or {}
	return (if p.DoubleSpeed then Config.PASS_SPEED_MULT else 1) * (if p.VIP then Config.VIP_MULT else 1)
end
function Config.passMoneyMult(passes: Owned): number
	local p = passes or {}
	return (if p.DoubleMoney then 2 else 1) * (if p.VIP then Config.VIP_MULT else 1)
end
function Config.passLuckMult(passes: Owned): number
	return if passes and passes.DoubleLuck then Config.PASS_LUCK_MULT else 1
end
function Config.passGrowMult(passes: Owned): number
	return if passes and passes.FastGrow then Config.PASS_GROW_MULT else 1
end

----------------------------------------------------------------------------------------------------
-- Seed packs: our "eggs with odds". Two premium, late-game packs, Robux only: each is a developer
-- product, never sold for in-game money, with no Speed gate (a premium shortcut). A pack rolls one
-- seed of its zone into the player's seed bag, which they plant from the Inventory (the Plants panel) on
-- their dirt.
-- Rolls live in Shared/SeedPacks, purchase rules in Server/Shop.
----------------------------------------------------------------------------------------------------
Config.PACK_LUCK = 2 -- packs roll Common..Epic with double luck (night pods are x1.5).
Config.PACK_LEGENDARY_CHANCE = 0.015 -- ...but Legendary stays a rare event (1 in ~67)...
Config.PACK_MUTATION_MULT = 2 -- ...with twice the Gold/Rainbow chances (Night never rolls from packs)...
Config.PACK_EXCLUSIVE = "Celestial" -- ...plus the pack-only mutation, which pods never roll
Config.PACK_EXCLUSIVE_CHANCE = 0.005
Config.SEED_BAG_MAX = 50 -- soft cap: the Shop won't *prompt* a pack purchase once the bag holds this many
Config.SEED_BAG_HARD_MAX = 250 -- paid grants may go past SEED_BAG_MAX up to here; saves are clamped here
-- The plant inventory: a plant taken off the plot (the Plants panel's Remove) waits here, as it was
-- (flower, mutation, growth), to be planted again or sold at the SELL stall. A seed brought home while
-- the plot is full goes to the seed bag instead (up to SEED_BAG_MAX).
Config.INVENTORY_MAX = 50
-- A paid pack whose seed can't fit (bag at SEED_BAG_HARD_MAX) pays this many seconds of the player's
-- income instead (at least this many seconds of a Common plant from the pack's zone), so a paid
-- purchase is never lost.
Config.PACK_FULL_BAG_INCOME_SECONDS = 300
Config.RECEIPT_HISTORY = 100 -- processed Robux PurchaseIds kept per profile, so a grant never repeats

----------------------------------------------------------------------------------------------------
-- Developer products: everything sold for Robux except the gamepasses. Their ids come from
-- monetization/ids.json (Config.applyMonetizationIds); id = 0 means "not set up yet" (the Shop says
-- "coming soon"). `robux`
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
--   GrowNow   finishes sprouting the plant it was prompted for (`upTo`: the most seconds of sprouting
--             left it is sold for, Config.growNowProduct; Shop.grantGrowNow)
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
	upTo: number?, -- GrowNow: the most seconds of sprouting left it is sold for (math.huge: any)
}
Config.DEVELOPER_PRODUCTS = {
	PackSpace = { kind = "Pack", label = "Starpetal Pack", robux = 2000, zone = 6 },
	PackSpirit = { kind = "Pack", label = "Lotus Wyrm Pack", robux = 3000, zone = 7 },

	-- Speed packs: the Shop's blue SPEED cards. Sized against the zones' recommended Speed (v7 scale):
	-- +25K is the Desert, +750K a bit past the Jungle, +3M past the Lava Fields, +10M past the Snow
	-- Peaks, +25M the Deep Space and +50M two thirds of the way to the Spirit Garden (README "Progression").
	Speed25K = { kind = "Speed", label = "+25K Speed", robux = 9, amount = 25e3 },
	Speed150K = { kind = "Speed", label = "+150K Speed", robux = 36, amount = 150e3 },
	Speed250K = { kind = "Speed", label = "+250K Speed", robux = 64, amount = 250e3 },
	Speed750K = { kind = "Speed", label = "+750K Speed", robux = 76, amount = 750e3 },
	Speed3M = { kind = "Speed", label = "+3M Speed", robux = 560, amount = 3e6 },
	Speed10M = { kind = "Speed", label = "+10M Speed", robux = 1200, amount = 10e6 },
	Speed25M = { kind = "Speed", label = "+25M Speed", robux = 1600, amount = 25e6 },
	Speed50M = { kind = "Speed", label = "+50M Speed", robux = 2400, amount = 50e6 },

	Money24K = { kind = "Money", label = "Pocket Cash", robux = 40, amount = 24e3, minutes = 10 },
	Money200K = { kind = "Money", label = "Cash Bag", robux = 80, amount = 200e3, minutes = 30 },
	Money800K = { kind = "Money", label = "Cash Stack", robux = 200, amount = 800e3, minutes = 60 },
	Money4M = { kind = "Money", label = "Cash Crate", robux = 400, amount = 4e6, minutes = 180 },
	Money8M = { kind = "Money", label = "Cash Vault", robux = 640, amount = 8e6, minutes = 360 },

	-- One treadmill tier each: the treadmill's F prompt and the Shop's R$ button. A product's price is
	-- fixed, so the 9 upgrades are split into tiers that cost more as the treadmill grows
	-- (Config.treadmillUpgradeProduct).
	TreadmillT1 = { kind = "TreadmillUpgrade", label = "Treadmill Upgrade (Lv 2-4)", robux = 19, tier = 1 },
	TreadmillT2 = { kind = "TreadmillUpgrade", label = "Treadmill Upgrade (Lv 5-7)", robux = 39, tier = 2 },
	TreadmillT3 = { kind = "TreadmillUpgrade", label = "Treadmill Upgrade (Lv 8-10)", robux = 79, tier = 3 },

	TrailGreen = { kind = "Trail", label = "Green Trail", robux = 16, trail = "Green" },
	TrailBlue = { kind = "Trail", label = "Blue Trail", robux = 24, trail = "Blue" },
	TrailPurple = { kind = "Trail", label = "Purple Trail", robux = 40, trail = "Purple" },
	TrailGolden = { kind = "Trail", label = "Golden Trail", robux = 64, trail = "Golden" },
	TrailRed = { kind = "Trail", label = "Red Trail", robux = 100, trail = "Red" },
	TrailRainbow = { kind = "Trail", label = "Rainbow Trail", robux = 180, trail = "Rainbow" },

	-- One plot level each: the Upgrade board's purple button. A product's price is fixed, so the 25
	-- upgrades are split into tiers that cost more as the plot grows (Config.plotUpgradeProduct).
	PlotUpgradeT1 = { kind = "PlotUpgrade", label = "Plot Upgrade (Lv 2-5)", robux = 25, tier = 1 },
	PlotUpgradeT2 = { kind = "PlotUpgrade", label = "Plot Upgrade (Lv 6-9)", robux = 49, tier = 2 },
	PlotUpgradeT3 = { kind = "PlotUpgrade", label = "Plot Upgrade (Lv 10-13)", robux = 99, tier = 3 },
	PlotUpgradeT4 = { kind = "PlotUpgrade", label = "Plot Upgrade (Lv 14-17)", robux = 199, tier = 4 },
	PlotUpgradeT5 = { kind = "PlotUpgrade", label = "Plot Upgrade (Lv 18-21)", robux = 399, tier = 5 },
	PlotUpgradeT6 = { kind = "PlotUpgrade", label = "Plot Upgrade (Lv 22-26)", robux = 799, tier = 6 },

	-- Grow now: finish a sprouting plant right away (its hover info's and Plants card's button). Priced by
	-- how much sprouting is left when it is prompted (Config.growNowProduct); the top one finishes any
	-- sprout, however long (only deep Legendaries wait over 30 min).
	GrowNow10 = { kind = "GrowNow", label = "Grow Now (10 min)", robux = 9, upTo = 10 * 60 },
	GrowNow30 = { kind = "GrowNow", label = "Grow Now (30+ min)", robux = 29, upTo = math.huge },
} :: { [string]: DevProduct }

-- The gamepass and developer product ids: monetization/ids.json ({ passes = { [key]: id }, products =
-- { [key]: id } }), which Rojo puts next to this module as the MonetizationIds ModuleScript. A key that is
-- missing, or not a whole positive number, is 0. tools/create_monetization.mjs creates the items on Roblox
-- and fills the file (monetization/LEIA-ME.md); never put ids here.
function Config.applyMonetizationIds(ids: any)
	local function section(name: string): { [string]: any }
		local t = if type(ids) == "table" then ids[name] else nil
		return if type(t) == "table" then t else {}
	end
	local function valid(id: any): number
		return if type(id) == "number" and id > 0 and id == math.floor(id) then id else 0
	end
	local passes, products = section("passes"), section("products")
	for name, pass in Config.GAMEPASSES do
		pass.id = valid(passes[name])
	end
	for name, product in Config.DEVELOPER_PRODUCTS do
		product.id = valid(products[name])
	end
end
Config.applyMonetizationIds(require(script.Parent:WaitForChild("MonetizationIds")))

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

-- The Grow Now product for a plant with `left` seconds of sprouting left, as (name, product): the cheapest
-- one whose upTo covers it (owner: up to 10 min 9 R$, anything longer 29 R$, which finishes it however
-- long it is), or nil when it isn't sprouting.
Config.GROW_NOW_PRODUCTS = { "GrowNow10", "GrowNow30" }
function Config.growNowProduct(left: number): (string?, DevProduct?)
	if not (left > 0) then
		return nil, nil
	end
	for _, name in Config.GROW_NOW_PRODUCTS do
		local product = Config.DEVELOPER_PRODUCTS[name]
		if left <= (product.upTo or math.huge) then
			return name, product
		end
	end
	local last = Config.GROW_NOW_PRODUCTS[#Config.GROW_NOW_PRODUCTS]
	return last, Config.DEVELOPER_PRODUCTS[last]
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
		return Config.TREADMILL_TIERS[tier + 1].price, `Treadmill Level {tier + 1}`
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

-- Day and night plants: each zone's plants (Zone.active) earn ACTIVE_TIME_MULT (x1) during their phase and
-- OFF_TIME_MULT (x0.8) during the other one. plantIncome stays the plain base; PlotService applies this on
-- payout.
Config.ACTIVE_TIME_MULT = 1
Config.OFF_TIME_MULT = 0.8
Config.ACTIVE_ICONS = { day = "☀️", night = "🌙" } :: { [string]: string }
-- The muted colour of the "Night x0.8" note while a plant is out of its phase (billboard, Plants panel, Sell).
Config.OFF_TIME_COLOR = Color3.fromRGB(170, 175, 195)

function Config.isActiveTime(k: number, isNight: boolean): boolean
	return (Config.ZONES[k].active == "night") == isNight
end

-- "Night x0.8" / "Day x0.8" while zone `k`'s plants are out of their phase (earning less), else nil: at x1
-- nothing extra is shown (plant labels: words, no emoji).
function Config.bonusLabel(k: number, isNight: boolean): string?
	if Config.isActiveTime(k, isNight) then
		return nil
	end
	return string.format("%s x%g", if isNight then "Night" else "Day", Config.OFF_TIME_MULT)
end

function Config.timeMult(k: number, isNight: boolean): number
	return if Config.isActiveTime(k, isNight) then Config.ACTIVE_TIME_MULT else Config.OFF_TIME_MULT
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
Config.COMMUNITY_GROUP_ID = 48006453 -- LeBandit Games (roblox.com/communities/48006453)
Config.COMMUNITY_NAME = "LeBandit Games" -- what the window tells players to search for
Config.FREE_GIFT_SPEED = 25_000 -- the Desert's recommended Speed
Config.FREE_GIFT_AUTO_OPEN = 20 -- seconds after joining: the window opens by itself, once per account

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
