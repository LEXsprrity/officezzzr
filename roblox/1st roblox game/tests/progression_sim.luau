-- A simple free-to-play player, simulated second by second with the real Config formulas (Speed gain,
-- WalkSpeed, trails, plot levels, plant income and growth, day/night). Used by progression.spec and
-- handy for tuning (print Sim.report()).
--
-- Strategy (an active player, no Robux unless `opts` says so):
--   * steal from the furthest zone whose recommended Speed they have, run home and plant it
--     (into a free slot, or replacing the plant worth least once grown, if the new seed beats it);
--   * when the plot is full of plants as good as a fresh seed from that zone, stand on the treadmill;
--   * whenever affordable, buy the cheaper of: the next trail, the next plot level.
local H = require("./harness")
local Config = H.shared("Config")

local Sim = {}

export type Options = {
	treadmillTier: number?, -- 1 = the free x2 (default); 2/3 = the Robux x3/x5
	speedPacks: { number }?, -- Speed bought with Robux at t = 0
	limitHours: number?,
	seed: number?,
}

export type Result = {
	arrivals: { number }, -- seconds until Speed >= ZONES[k].req
	buys: { { t: number, what: string, price: number } },
	finalSpeed: number,
	finalMoney: number,
	income: number, -- $/s at the end
	plotLevel: number,
	trail: string,
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
	local treadmillMult = Config.TREADMILL_TIERS[o.treadmillTier or 1].mult

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
	end

	-- One second: earn money, and Speed at `perStudMult` x WalkSpeed studs (0 when not moving).
	local function second(moving: boolean, mult: number)
		if t - incomeAt >= 10 then
			refreshIncome()
		end
		money += income
		if moving then
			local studs = math.min(Config.walkSpeedFor(speed), Config.GAIN_CAP_STUDS_PER_TICK / Config.TICK)
			speed += studs * Config.gainPerStud(speed) * Config.TRAILS[trailIndex].mult * mult
		end
		t += 1
		noteArrivals()
	end

	local function shop()
		while true do
			local nextTrail = Config.TRAILS[trailIndex + 1]
			local plotPrice = Config.priceOf("PlotUpgrade", { money = money, plotLevel = level, trails = {} })
			local trailPrice = if nextTrail then nextTrail.price else nil
			local pick, price
			if trailPrice and (not plotPrice or trailPrice <= plotPrice) then
				pick, price = "trail", trailPrice
			elseif plotPrice then
				pick, price = "plot", plotPrice
			end
			if not pick or money < price then
				return
			end
			money -= price
			if pick == "trail" then
				trailIndex += 1
				table.insert(buys, { t = t, what = Config.TRAILS[trailIndex].name, price = price })
			else
				level += 1
				table.insert(buys, { t = t, what = `Plot Level {level}`, price = price })
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
	while t < limit and not arrivals[#Config.ZONES] do
		local k = bestZone()
		local slots = Config.plotSlots(level)
		local _, worstValue = worst()
		local fresh = grownValue(k, 1, nil)
		if #plants < slots or worstValue < fresh then
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
				second(true, treadmillMult)
			end
		end
		shop()
	end
	refreshIncome()
	return {
		arrivals = arrivals,
		buys = buys,
		finalSpeed = speed,
		finalMoney = money,
		income = income,
		plotLevel = level,
		trail = Config.TRAILS[trailIndex].id,
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

-- Targets for a free, active player (cumulative play time), from the owner via Pixel.
Sim.TARGETS = { Desert = 5 * 60, Jungle = 30 * 60, Lava = 75 * 60, Snow = 3 * 3600, Space = 6 * 3600, Spirit = 12.5 * 3600 }

-- The free-player timeline and the Robux comparisons, as a Markdown table (for the PR / README).
function Sim.report(): string
	local Format = H.shared("Format")
	local free = Sim.run()
	local tread = Sim.run({ treadmillTier = 3 })
	local packs = Sim.run({ treadmillTier = 3, speedPacks = { 1e6, 10e6 } })
	local lines = { "| Zone | Rec. Speed | Target | Free player | ±50% window | Treadmill x5 (R$) | x5 + 11M Speed packs (R$) |", "|---|---|---|---|---|---|---|" }
	for k, zone in Config.ZONES do
		local target = Sim.TARGETS[zone.id]
		table.insert(lines, string.format("| %s %s | %s | %s | **%s** | %s | %s | %s |", zone.icon, zone.name, Format.short(zone.req),
			if target then Sim.clock(target) else "start", Sim.clock(free.arrivals[k]),
			if target then `{Sim.clock(target * 0.5)} – {Sim.clock(target * 1.5)}` else "—",
			Sim.clock(tread.arrivals[k]), Sim.clock(packs.arrivals[k])))
	end
	local buys = {}
	for _, b in free.buys do
		table.insert(buys, `{Sim.clock(b.t)} {b.what} ({Format.money(b.price)})`)
	end
	table.insert(lines, "")
	table.insert(lines, `Free player at the Spirit Garden: {free.trail} trail, plot level {free.plotLevel}, {Format.money(free.income)}/s, {Format.money(free.finalMoney)} unspent.`)
	table.insert(lines, "Purchases: " .. table.concat(buys, " · "))
	return table.concat(lines, "\n")
end

return Sim
