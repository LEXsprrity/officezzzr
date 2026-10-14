-- A simple free-to-play player, simulated second by second with the real Config formulas (Speed gain,
-- WalkSpeed, trails, plot levels, plant income and growth, day/night). Used by progression.spec and
-- handy for tuning (print Sim.report()).
--
-- Strategy (an active player, no Robux unless `opts` says so):
--   * steal from the furthest zone whose recommended Speed they have, run home and plant it
--     (into a free slot, or replacing the plant worth least once grown, if the new seed beats it);
--   * when the plot is full of plants as good as a fresh seed from that zone, stand on the treadmill;
--   * whenever affordable, buy the cheapest of: the next trail, the next plot level, the next treadmill tier.
-- With `afk`, the player is an AFK farmer instead: they fill the plot once, then never run the corridor
-- again (only the treadmill, buying the same upgrades from their plants' income).
local H = require("./harness")
local Config = H.shared("Config")

local Sim = {}

export type Options = {
	treadmillTier: number?, -- the treadmill tier at t = 0 (default 1, the free x2; 6 = x5, bought with Robux)
	speedPacks: { number }?, -- Speed bought with Robux at t = 0
	noTreadmillUpgrades: boolean?, -- never buy treadmill tiers with money (the economy before they existed)
	afk: boolean?, -- an AFK farmer (see above)
	limitHours: number?,
	seed: number?,
}

export type Result = {
	arrivals: { number }, -- seconds until Speed >= ZONES[k].req
	track: { number }, -- Speed at the end of each minute (for tuning)
	buys: { { t: number, what: string, price: number } },
	finalSpeed: number,
	finalMoney: number,
	income: number, -- $/s at the end
	plotLevel: number,
	trail: string,
	treadmillTier: number,
}

local TRIP_OVERHEAD = 10 -- seconds per steal trip beyond running: grabbing, dodging, planting, menus
local IDLE_CHUNK = 30 -- seconds on the treadmill between checks
local HOME_X = Config.PLOT_FIRST_X -- the nearest plot
local WALKWAY = 40 -- studs from the plot's pad to the corridor line, each way

type Plant = { zone: number, rarity: number, mutation: string?, plantedAt: number }

local function grownValue(zone: number, rarity: number, mutation: string?): number
	return Config.plantIncome(zone, rarity, Config.sproutWeight(zone, rarity) * Config.GROW_MAX_FACTOR, mutation)
end

function Sim.run(opts: Options?): Result
	local o: Options = opts or {}
	local rand = H.Random.new(o.seed or 7)
	local function rng(): number
		return rand:NextNumber()
	end
	local limit = (o.limitHours or 40) * 3600
	local treadmillTier = o.treadmillTier or 1

	local t = 0
	local speed = 0
	for _, amount in o.speedPacks or {} do
		speed += amount
	end
	local money = 0
	local level = 1
	local trailIndex = 1
	local plants: { Plant } = {}
	local arrivals: { number } = {}
	local track: { number } = {}
	local buys = {}
	local income = 0
	local incomeAt = -math.huge

	local function refreshIncome()
		local total = 0
		for _, p in plants do
			local w = Config.plantWeight(p.zone, p.rarity, t - p.plantedAt, 1)
			total += Config.plantIncome(p.zone, p.rarity, w, p.mutation) * Config.averageTimeMult(p.zone)
		end
		income = total * Config.plotMoneyMult(level)
		incomeAt = t
	end

	local function noteArrivals()
		for k, zone in Config.ZONES do
			if not arrivals[k] and speed >= zone.req then
				arrivals[k] = t
			end
		end
		if t % 60 == 0 then
			track[t // 60] = speed
		end
	end

	-- One second: earn money, and Speed at `mult` (the treadmill's, or 1) x WalkSpeed studs (0 when not moving).
	local function second(moving: boolean, mult: number)
		if t - incomeAt >= 10 then
			refreshIncome()
		end
		money += income
		if moving then
			local studs = math.min(Config.walkSpeedFor(speed), Config.GAIN_CAP_STUDS_PER_TICK / Config.TICK)
			speed += studs * Config.speedPerStud(Config.TRAILS[trailIndex].id) * mult
		end
		t += 1
		noteArrivals()
	end

	local function shop()
		while true do
			local nextTrail = Config.TRAILS[trailIndex + 1]
			local view = { money = money, plotLevel = level, trails = {}, treadmillTier = treadmillTier }
			local options = {
				{ pick = "trail", price = if nextTrail then nextTrail.price else nil },
				{ pick = "plot", price = Config.priceOf("PlotUpgrade", view) },
				{ pick = "treadmill", price = if o.noTreadmillUpgrades then nil else Config.priceOf("TreadmillUpgrade", view) },
			}
			local pick, price = nil, math.huge
			for _, option in options do
				if option.price and option.price < price then
					pick, price = option.pick, option.price
				end
			end
			if not pick or money < price then
				return
			end
			money -= price
			if pick == "trail" then
				trailIndex += 1
				table.insert(buys, { t = t, what = Config.TRAILS[trailIndex].name, price = price })
			elseif pick == "plot" then
				level += 1
				table.insert(buys, { t = t, what = `Plot Level {level}`, price = price })
			else
				treadmillTier += 1
				table.insert(buys, { t = t, what = `Treadmill x{Config.treadmillMult(treadmillTier)}`, price = price })
			end
			refreshIncome()
		end
	end

	local function bestZone(): number
		local best = 1
		for k, zone in Config.ZONES do
			if speed >= zone.req then
				best = k
			end
		end
		return best
	end

	-- The plant worth least once grown, and its index.
	local function worst(): (number, number)
		local idx, value = 0, math.huge
		for i, p in plants do
			local v = grownValue(p.zone, p.rarity, p.mutation)
			if v < value then
				idx, value = i, v
			end
		end
		return idx, value
	end

	noteArrivals()
	local filled = false -- the plot was full once (an AFK farmer stops running then)
	while t < limit and not arrivals[#Config.ZONES] do
		local k = bestZone()
		local slots = Config.plotSlots(level)
		local _, worstValue = worst()
		local fresh = grownValue(k, 1, nil)
		filled = filled or #plants >= slots
		if (#plants < slots or worstValue < fresh) and not (o.afk and filled) then
			-- steal trip: run to zone k's nest and back, then plant
			local distance = 2 * (Config.nestX(k) - HOME_X + WALKWAY)
			while distance > 0 do
				distance -= Config.walkSpeedFor(speed)
				second(true, 1)
			end
			for _ = 1, TRIP_OVERHEAD do
				second(false, 1)
			end
			local isNight = Config.dayPhase(t)
			local rarity, mutation = Config.rollSeed(k, if isNight then Config.NIGHT_LUCK else 1, isNight, rng)
			local plant = { zone = k, rarity = rarity, mutation = mutation, plantedAt = t }
			if #plants < slots then
				table.insert(plants, plant)
			else
				local i, v = worst()
				if v < grownValue(k, rarity, mutation) then
					plants[i] = plant
				end
			end
			refreshIncome()
		else
			for _ = 1, IDLE_CHUNK do
				second(true, Config.treadmillMult(treadmillTier))
			end
		end
		shop()
	end
	refreshIncome()
	return {
		arrivals = arrivals,
		track = track,
		buys = buys,
		finalSpeed = speed,
		finalMoney = money,
		income = income,
		plotLevel = level,
		trail = Config.TRAILS[trailIndex].id,
		treadmillTier = treadmillTier,
	}
end

-- "1:23" / "12h 05m"
function Sim.clock(seconds: number?): string
	if not seconds then
		return "never"
	end
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	end
	return string.format("%dm %02ds", m, seconds % 60)
end

-- The Speed packs the Robux comparisons buy at t = 0: about what the old +1M and +10M cost (76 + 560 R$).
Sim.PACKS = { Config.DEVELOPER_PRODUCTS.Speed750K.amount :: number, Config.DEVELOPER_PRODUCTS.Speed3M.amount :: number }

-- Targets for a free, active player (cumulative play time), from the owner via Pixel.
Sim.TARGETS = { Desert = 5 * 60, Jungle = 30 * 60, Lava = 75 * 60, Snow = 3 * 3600, Space = 6 * 3600, Spirit = 12.5 * 3600 }

-- The free-player timeline and the Robux comparisons, as a Markdown table (for the PR / README).
function Sim.report(): string
	local Format = H.shared("Format")
	local free = Sim.run()
	local top = Config.TREADMILL_MAX
	local tread = Sim.run({ treadmillTier = top })
	local packs = Sim.run({ treadmillTier = top, speedPacks = Sim.PACKS })
	local packTotal = 0
	for _, amount in Sim.PACKS do
		packTotal += amount
	end
	local afk = Sim.run({ afk = true, limitHours = 80 })
	local x = `x{Config.treadmillMult(top)}`
	local lines = { `| Zone | Rec. Speed | Target | Free player | ±50% window | AFK farmer | Treadmill {x} (R$) | {x} + {Format.short(packTotal)} Speed packs (R$) |`, "|---|---|---|---|---|---|---|---|" }
	for k, zone in Config.ZONES do
		local target = Sim.TARGETS[zone.id]
		table.insert(lines, string.format("| %s %s | %s | %s | **%s** | %s | %s | %s | %s |", zone.icon, zone.name, Format.short(zone.req),
			if target then Sim.clock(target) else "start", Sim.clock(free.arrivals[k]),
			if target then `{Sim.clock(target * 0.5)} – {Sim.clock(target * 1.5)}` else "—",
			Sim.clock(afk.arrivals[k]), Sim.clock(tread.arrivals[k]), Sim.clock(packs.arrivals[k])))
	end
	local buys = {}
	for _, b in free.buys do
		table.insert(buys, `{Sim.clock(b.t)} {b.what} ({Format.money(b.price)})`)
	end
	table.insert(lines, "")
	table.insert(lines, `Free player at the Spirit Garden: {free.trail} trail, plot level {free.plotLevel}, treadmill x{Config.treadmillMult(free.treadmillTier)}, {Format.money(free.income)}/s, {Format.money(free.finalMoney)} unspent.`)
	table.insert(lines, "Purchases: " .. table.concat(buys, " · "))
	return table.concat(lines, "\n")
end

return Sim
