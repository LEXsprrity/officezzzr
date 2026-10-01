-- Economy, growth, zones, shop and formatting.
local H = require("./harness")

local Config = H.shared("Config")
local Format = H.shared("Format")
local Shop = H.server("Shop")
local ProfileStore = H.server("ProfileStore")

H.test("zones: 7 zones with the agreed recommended speeds", function()
	local want = { 0, 10e3, 500e3, 5e6, 50e6, 500e6, 5e9 }
	H.eq(#Config.ZONES, 7)
	for k, req in want do
		H.eq(Config.ZONES[k].req, req, Config.ZONES[k].id)
	end
end)

H.test("zones: corridor is 10-12k studs and a max-speed run to the end takes 60-90 s", function()
	local length = Config.END_X - Config.CORRIDOR_START_X
	H.ok(length >= 10000 and length <= 12000, "length " .. length)
	local atEnd = Config.walkSpeedFor(Config.ZONES[#Config.ZONES].req)
	for _, w in { atEnd, Config.MAX_WALKSPEED } do
		local seconds = length / w
		H.ok(seconds >= 60 and seconds <= 90, `run takes {seconds}s at WalkSpeed {w}`)
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

H.test("economy: a full plot of zone-k seeds pays for zone k+1 in PAYBACK_SECONDS", function()
	H.eq(Config.ECONOMY_SLOTS, 10, "income is balanced for 10 plants, whatever SLOTS_START is")
	for k = 1, #Config.ZONES - 1 do
		local perSecond = Config.seedIncome(k) * Config.ECONOMY_SLOTS
		H.near(perSecond * Config.PAYBACK_SECONDS * Config.PRICE_PER_SPEED, Config.speedCost(Config.ZONES[k + 1].req), 1e-3, Config.ZONES[k].id)
	end
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

H.test("shop: + button buys speed at speedCost, refuses without money", function()
	local p = ProfileStore.defaultProfile()
	local ok = Shop.buy(p, "Speed25", 0)
	H.eq(ok, false)
	p.money = 5000
	ok = Shop.buy(p, "Speed25", 0)
	H.ok(ok)
	H.eq(p.speed, Config.SPEED_BUY_MIN)
	H.eq(p.money, 5000 - Config.speedCost(Config.SPEED_BUY_MIN))
	ok = Shop.buy(p, "SpeedMax", 0)
	H.ok(ok)
	H.eq(p.money, 0)
	H.eq(p.speed, 5000 / Config.PRICE_PER_SPEED)
end)

H.test("shop: tiered upgrades advance, get pricier, and max out", function()
	local p = ProfileStore.defaultProfile()
	p.money = 1e15
	local last = 0
	for tier = 2, #Config.SPEED_MULT_TIERS do
		local price = Config.priceOf("SpeedMult", p)
		H.ok(price > last, "geometric")
		last = price
		H.ok(Shop.buy(p, "SpeedMult", 0))
		H.eq(p.speedMultTier, tier)
	end
	H.eq(Shop.buy(p, "SpeedMult", 0), false, "maxed")
	H.ok(Shop.buy(p, "Treadmill", 0))
	H.ok(Shop.buy(p, "Treadmill", 0))
	H.eq(Config.TREADMILL_TIERS[p.treadmillTier].mult, 5)
	H.eq(Shop.buy(p, "Treadmill", 0), false)
	local s1 = Config.priceOf("Slot", p)
	H.ok(Shop.buy(p, "Slot", 0))
	H.eq(p.slots, Config.SLOTS_START + 1)
	H.ok(Config.priceOf("Slot", p) > s1)
end)

H.test("shop: slots start at 5, slot 6 costs $500 and every slot costs more than the last", function()
	H.eq(Config.SLOTS_START, 5)
	local function priceOfSlot(n: number): number -- price of buying slot n
		return (Config.priceOf("Slot", { money = 0, speed = 0, speedMultTier = 1, treadmillTier = 1, slots = n - 1 }))
	end
	H.eq(priceOfSlot(6), 500)
	H.eq(priceOfSlot(7), 1250)
	H.near(priceOfSlot(10), 19.5e3, 0.1e3)
	H.near(priceOfSlot(15), 1.9e6, 0.01e6)
	H.near(priceOfSlot(30), 1.8e12, 0.03e12)
	local last = 0
	for n = Config.SLOTS_START + 1, Config.SLOTS_MAX do
		local price = priceOfSlot(n)
		H.ok(price > last, `slot {n} costs {price}, slot {n - 1} cost {last}`)
		last = price
	end
	H.eq(Config.priceOf("Slot", { money = 0, speed = 0, speedMultTier = 1, treadmillTier = 1, slots = Config.SLOTS_MAX }), nil, "maxed")
end)

H.test("shop: Sleep Dust and potions are consumables; potion price scales with income", function()
	local p = ProfileStore.defaultProfile()
	p.money = 1e6
	H.ok(Shop.buy(p, "SleepDust", 0))
	H.eq(p.items.SleepDust, 4)
	H.eq(Config.priceOf("PotionMoney", { money = 0, speed = 0, speedMultTier = 1, treadmillTier = 1, slots = 10, income = 0 }), Config.POTION_MIN_PRICE)
	H.eq(Config.priceOf("PotionMoney", { money = 0, speed = 0, speedMultTier = 1, treadmillTier = 1, slots = 10, income = 1e6 }), 1e6 * Config.POTION_INCOME_SECONDS)
	H.eq(Shop.buy(p, "Nonsense", 0), false)
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

return nil
