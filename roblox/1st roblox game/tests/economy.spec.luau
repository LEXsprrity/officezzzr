-- Economy, growth, zones and formatting (the shop has its own spec: shop.spec).
local H = require("./harness")

local Config = H.shared("Config")
local Format = H.shared("Format")

H.test("zones: 7 zones with the agreed recommended speeds", function()
	local want = { 0, 10e3, 500e3, 5e6, 50e6, 500e6, 5e9 }
	H.eq(#Config.ZONES, 7)
	for k, req in want do
		H.eq(Config.ZONES[k].req, req, Config.ZONES[k].id)
	end
end)

H.test("zones: corridor is 4-6k studs and a max-speed run to the end takes 20-40 s", function()
	local length = Config.END_X - Config.CORRIDOR_START_X
	H.ok(length >= 4000 and length <= 6000, "length " .. length)
	local atEnd = Config.walkSpeedFor(Config.ZONES[#Config.ZONES].req)
	for _, w in { atEnd, Config.MAX_WALKSPEED } do
		local seconds = length / w
		H.ok(seconds >= 20 and seconds <= 40, `run takes {seconds}s at WalkSpeed {w}`)
	end
end)

H.test("zones: zoneAtX maps corridor positions to zones, base to nil", function()
	H.eq(Config.zoneAtX(0), nil)
	H.eq(Config.zoneAtX(Config.CORRIDOR_START_X + 1), 1)
	for k = 1, #Config.ZONES do
		H.eq(Config.zoneAtX(Config.nestX(k)), k)
	end
	H.eq(Config.zoneAtX(Config.END_X - 1), #Config.ZONES)
end)

H.test("economy: a full plot of zone-k Commons earns zone k+1's recommended Speed in dollars in PAYBACK_SECONDS", function()
	H.eq(Config.ECONOMY_SLOTS, 10, "income is balanced for 10 plants, whatever SLOTS_START is")
	for k = 1, #Config.ZONES - 1 do
		local perSecond = Config.seedIncome(k) * Config.ECONOMY_SLOTS
		H.near(perSecond * Config.PAYBACK_SECONDS, Config.ZONES[k + 1].req, 1e-3, Config.ZONES[k].id)
	end
	H.near(Config.seedIncome(1), 10e3 / 3000, 1e-9, "the money scale is unchanged by the rework")
end)

H.test("growth: weight grows from sprout to GROW_MAX_FACTOR x and then stops (closed form)", function()
	local k, r, v = 5, 2, 1
	local sprout = Config.plantWeight(k, r, 0, v)
	H.near(sprout, Config.sproutWeight(k, r), 1e-6)
	local mid = Config.plantWeight(k, r, Config.GROW_TIME / 2, v)
	local full = Config.plantWeight(k, r, Config.GROW_TIME, v)
	local later = Config.plantWeight(k, r, Config.GROW_TIME * 50, v)
	H.ok(sprout < mid and mid < full, "grows")
	H.near(full, sprout * Config.GROW_MAX_FACTOR, 1e-6, "capped")
	H.eq(later, full, "no growth past the cap")
end)

H.test("growth: income depends on rarity and weight, and mutations multiply it", function()
	local k = 3
	local w1 = Config.plantWeight(k, 1, 0, 1)
	local base = Config.plantIncome(k, 1, w1, nil)
	H.near(base, Config.seedIncome(k), 1e-9, "sprouted common = base income")
	H.ok(Config.plantIncome(k, 5, Config.plantWeight(k, 5, 0, 1), nil) > base * 10, "legendary pays much more")
	H.ok(Config.plantIncome(k, 1, Config.plantWeight(k, 1, Config.GROW_TIME, 1), nil) > base, "grown pays more")
	H.near(Config.plantIncome(k, 1, w1, "Gold"), base * 3, 1e-9)
end)

H.test("growth: per-plant variance is stable and within [0.8, 1.2)", function()
	for i = 1, 500 do
		local v = Config.plantVariance(1790000000 + i * 37, i % 40 + 1)
		H.ok(v >= 0.8 and v < 1.2, tostring(v))
		H.eq(v, Config.plantVariance(1790000000 + i * 37, i % 40 + 1))
	end
end)

H.test("rarity: 5 rarities, luck and deeper zones shift odds toward rare", function()
	H.eq(#Config.RARITIES, 5)
	local function legendaryShare(k, luck)
		local w = Config.rarityWeights(k, luck)
		local total = 0
		for _, x in w do
			total += x
		end
		return w[5] / total
	end
	H.ok(legendaryShare(7, 1) > legendaryShare(1, 1))
	H.ok(legendaryShare(1, 2) > legendaryShare(1, 1))
	-- rollSeed respects the rng
	local rarity = Config.rollSeed(1, 1, false, function()
		return 0
	end)
	H.eq(rarity, 1)
	local top = Config.rollSeed(1, 1, false, function()
		return 0.999999
	end)
	H.eq(top, 5)
	local _, nightMut = Config.rollSeed(1, 1, true, function()
		return Config.MUTATIONS[1].chance + Config.MUTATIONS[2].chance + 0.01
	end)
	H.eq(nightMut, "Night", "Night mutation only rolls at night")
	local _, dayMut = Config.rollSeed(1, 1, false, function()
		return Config.MUTATIONS[1].chance + Config.MUTATIONS[2].chance + 0.01
	end)
	H.eq(dayMut, nil)
end)

H.test("format: K/M/B/T/Qa and comma weights", function()
	H.eq(Format.short(999), "999")
	H.eq(Format.short(1234), "1.2K")
	H.eq(Format.short(10e3), "10K")
	H.eq(Format.short(123456), "123K")
	H.eq(Format.short(1.2e6), "1.2M")
	H.eq(Format.short(5e9), "5B")
	H.eq(Format.short(7.5e12), "7.5T")
	H.eq(Format.short(3e15), "3Qa")
	H.eq(Format.short(999999), "1M")
	H.eq(Format.money(1.2e6), "$1.2M")
	H.eq(Format.weight(2018798.4), "2,018,798 Kg")
	H.eq(Format.clock(75), "1:15")
end)

H.test("day/night: phase is derived from the clock", function()
	local night, left = Config.dayPhase(0)
	H.eq(night, false)
	H.eq(left, Config.DAY_SECONDS)
	night = Config.dayPhase(Config.DAY_SECONDS + 1)
	H.eq(night, true)
end)

H.test("day/night: lighting blend fades in at dusk, holds, fades out at dawn", function()
	local D, N, F = Config.DAY_SECONDS, Config.NIGHT_SECONDS, Config.NIGHT_FADE_SECONDS
	H.eq(Config.nightBlend(D / 2), 0, "midday")
	H.near(Config.nightBlend(D + 0.001), 0, 1e-3, "dusk starts dark-free")
	local mid = Config.nightBlend(D + F / 2)
	H.ok(mid > 0.3 and mid < 0.7, "halfway through the fade " .. mid)
	H.eq(Config.nightBlend(D + N / 2), 1, "midnight")
	H.near(Config.nightBlend(D + N - 0.001), 0, 1e-3, "dawn")
	local last = -1
	for t = D, D + F, 1 do -- monotonic fade-in
		local b = Config.nightBlend(t)
		H.ok(b >= last, "fade-in is monotonic")
		last = b
	end
end)

H.test("day/night plants: every zone is a day or a night plant (Meadow/Desert/Lava/Spirit by day)", function()
	local want = { Meadow = "day", Desert = "day", Jungle = "night", Lava = "day", Snow = "night", Space = "night", Spirit = "day" }
	for _, zone in Config.ZONES do
		H.ok(zone.active == "day" or zone.active == "night", `{zone.id} has active = {zone.active}`)
		H.eq(zone.active, want[zone.id], zone.id)
		H.ok(Config.ACTIVE_ICONS[zone.active] ~= nil, "icon")
	end
end)

H.test("day/night plants: timeMult is 1.5 during the plant's phase and 1 otherwise", function()
	H.eq(Config.ACTIVE_TIME_MULT, 1.5)
	for k, zone in Config.ZONES do
		local day, night = Config.timeMult(k, false), Config.timeMult(k, true)
		if zone.active == "day" then
			H.eq(day, 1.5, zone.id .. " by day")
			H.eq(night, 1, zone.id .. " at night")
		else
			H.eq(day, 1, zone.id .. " by day")
			H.eq(night, 1.5, zone.id .. " at night")
		end
	end
	-- driven by the shared clock
	local meadow, jungle = 1, 3
	H.eq(Config.timeMult(meadow, (Config.dayPhase(10))), 1.5)
	H.eq(Config.timeMult(jungle, (Config.dayPhase(10))), 1)
	H.eq(Config.timeMult(jungle, (Config.dayPhase(Config.DAY_SECONDS + 10))), 1.5)
end)

H.test("day/night plants: offline income uses the time-weighted average multiplier", function()
	local D, N = Config.DAY_SECONDS, Config.NIGHT_SECONDS
	for k, zone in Config.ZONES do
		local want = if zone.active == "day" then (D * 1.5 + N) / (D + N) else (D + N * 1.5) / (D + N)
		H.near(Config.averageTimeMult(k), want, 1e-9, zone.id)
		-- matches what the payout loop pays over one full cycle, second by second
		local sum = 0
		for t = 0, D + N - 1 do
			sum += Config.timeMult(k, (Config.dayPhase(t + 0.5)))
		end
		H.near(Config.averageTimeMult(k), sum / (D + N), 1e-9, zone.id .. " integrated")
	end
	H.near(Config.averageTimeMult(1), 4 / 3, 1e-9, "day plants: 300 s x1.5 + 150 s x1")
	H.near(Config.averageTimeMult(3), 7 / 6, 1e-9, "night plants: 300 s x1 + 150 s x1.5")
end)

return nil
