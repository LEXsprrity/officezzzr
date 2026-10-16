-- Economy, growth, zones and formatting (the shop has its own spec: shop.spec).
local H = require("./harness")

local Config = H.shared("Config")
local Format = H.shared("Format")

H.test("zones: 7 zones with the agreed recommended speeds (the flat-gain scale, v7)", function()
	local want = { 0, 25e3, 500e3, 2.5e6, 7.5e6, 25e6, 75e6 }
	H.eq(#Config.ZONES, 7)
	for k, req in want do
		H.eq(Config.ZONES[k].req, req, Config.ZONES[k].id)
	end
end)

H.test("zones: lengths double from the first zone up to the max, then stay at the max (100, 200, 400 x5)", function()
	H.eq(Config.ZONE_LENGTH_BASE, 100)
	H.eq(Config.ZONE_LENGTH_GROWTH, 2)
	H.eq(Config.ZONE_LENGTH_MAX, 400)
	local want = { 100, 200, 400, 400, 400, 400, 400 }
	for k, zone in Config.ZONES do
		H.eq(zone.length, want[k], zone.id)
		H.eq(zone.length, Config.zoneLength(k), `{zone.id} comes from the formula`)
		if k > 1 then
			local prev = Config.ZONES[k - 1].length
			H.eq(zone.length, math.min(prev * Config.ZONE_LENGTH_GROWTH, Config.ZONE_LENGTH_MAX), `{zone.id}: x2 the previous, capped`)
		end
	end
	H.ok(Config.ZONES[1].length < Config.ZONES[2].length, "the first zone is the smallest")
	-- the max is about two corridor widths deep (the owner's reference)
	H.ok(Config.ZONE_LENGTH_MAX >= 1.5 * Config.CORRIDOR_WIDTH and Config.ZONE_LENGTH_MAX <= 2.5 * Config.CORRIDOR_WIDTH, "max ~2x the width")
end)

H.test("zones: corridor is 2-3k studs and a max-speed run to the end takes 10-20 s", function()
	-- (was 4-6k and 20-40 s before the zones were shortened to the doubling-with-cap lengths)
	local length = Config.END_X - Config.CORRIDOR_START_X
	H.ok(length >= 2000 and length <= 3000, "length " .. length)
	local atEnd = Config.walkSpeedFor(Config.ZONES[#Config.ZONES].req)
	for _, w in { atEnd, Config.MAX_WALKSPEED } do
		local seconds = length / w
		H.ok(seconds >= 10 and seconds <= 20, `run takes {seconds}s at WalkSpeed {w}`)
	end
end)

H.test("zones: every nest and its sleeping guard sit inside their own zone", function()
	for k, zone in Config.ZONES do
		local x0, x1 = Config.zoneStartX(k), Config.zoneStartX(k) + zone.length
		local nest = Config.nestX(k)
		H.ok(nest - 14 > x0, `{zone.id}: the nest's mound is clear of the zone's start`)
		H.ok(nest + Config.GUARD_HOME_OFFSET < x1, `{zone.id}: the guard sleeps inside its zone`)
		H.eq(Config.zoneAtX(nest + Config.GUARD_HOME_OFFSET), k, zone.id)
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

H.test("economy: a full plot of zone-k Commons earns zone k+1's ZONE_CASH (x INCOME_SCALE) in dollars in PAYBACK_SECONDS", function()
	H.eq(Config.ECONOMY_SLOTS, 10, "income is balanced for 10 plants, whatever SLOTS_START is")
	H.eq(#Config.ZONE_CASH, #Config.ZONES, "one money anchor per zone")
	for k = 1, #Config.ZONES - 1 do
		local perSecond = Config.seedIncome(k) * Config.ECONOMY_SLOTS
		H.near(perSecond * Config.PAYBACK_SECONDS, Config.ZONE_CASH[k + 1] * Config.INCOME_SCALE, 1e-3, Config.ZONES[k].id)
		H.ok(Config.ZONE_CASH[k + 1] > Config.ZONE_CASH[k], "deeper zones pay more")
	end
	-- the money anchors are the pre-v7 recommended Speeds: shrinking the Speed scale didn't move the money one
	local ProfileStore = H.server("ProfileStore")
	for k, cash in Config.ZONE_CASH do
		H.eq(cash, ProfileStore.LEGACY_ZONE_REQ[k], Config.ZONES[k].id)
	end
	H.near(Config.seedIncome(1), 10e3 / 3000 * Config.INCOME_SCALE, 1e-9, "the money scale is unchanged by the rework")
	H.eq(Config.INCOME_SCALE, 1.25, "x1.25 makes up for the x1 / x0.8 day-night rates (were x1.5 / x1)")
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

H.test("rarity: 5 rarities, luck and deeper zones shift Common..Epic toward rare, Legendary gets rarer", function()
	H.eq(#Config.RARITIES, 5)
	H.eq(Config.LEGENDARY, 5)
	local function share(k, luck, i)
		local w = Config.rarityWeights(k, luck)
		local total = 0
		for _, x in w do
			total += x
		end
		return w[i] / total
	end
	H.ok(share(7, 1, 4) > share(1, 1, 4), "Epic: deeper is luckier")
	H.ok(share(1, 2, 4) > share(1, 1, 4), "Epic: night is luckier")
	H.ok(share(7, 1, 5) < share(1, 1, 5), "Legendary: deeper is rarer")
	H.ok(share(1, 2, 5) > share(1, 1, 5), "Legendary: night still helps")
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


H.test("day/night plants: every zone is a day or a night plant (Meadow/Desert/Lava/Spirit by day)", function()
	local want = { Meadow = "day", Desert = "day", Jungle = "night", Lava = "day", Snow = "night", Space = "night", Spirit = "day" }
	for _, zone in Config.ZONES do
		H.ok(zone.active == "day" or zone.active == "night", `{zone.id} has active = {zone.active}`)
		H.eq(zone.active, want[zone.id], zone.id)
		H.ok(Config.ACTIVE_ICONS[zone.active] ~= nil, "icon")
	end
end)

H.test("day/night plants: every plant earns x1 by day and at night (owner 2026-10-16)", function()
	H.eq(Config.ACTIVE_TIME_MULT, 1)
	H.eq(Config.OFF_TIME_MULT, 1)
	for k, zone in Config.ZONES do
		H.eq(Config.timeMult(k, false), 1, zone.id .. " by day")
		H.eq(Config.timeMult(k, true), 1, zone.id .. " at night")
		H.eq(Config.averageTimeMult(k), 1, zone.id .. " offline")
	end
end)

H.test("day/night plants: no Day/Night note on any label while both are x1", function()
	for k in Config.ZONES do
		H.eq(Config.bonusLabel(k, false), nil)
		H.eq(Config.bonusLabel(k, true), nil)
	end
	H.ok(typeof(Config.OFF_TIME_COLOR) == "Color3", "a muted colour for the penalty")
	local fs = require("@lune/fs")
	local plot = fs.readFile("src/server/PlotService.luau")
	local hud = fs.readFile("src/client/HUD.client.luau")
	H.ok(string.find(plot, "if bonus then Config.OFF_TIME_COLOR else INCOME_GREEN", 1, true) ~= nil, "billboard: muted while penalised")
	H.ok(string.find(hud, "if bonus then Config.OFF_TIME_COLOR else MONEY_GREEN", 1, true) ~= nil, "Sell cards: muted while penalised")
	H.ok(string.find(hud, "MUTED_INK:ToHex()", 1, true) ~= nil, "Plants panel: muted while penalised")
	H.ok(not string.find(plot, "INCOME_GOLD", 1, true) and not string.find(hud, "GOLD_INK", 1, true), "no gold bonus colour left")
end)

H.test("day/night plants: offline income uses the time-weighted average multiplier", function()
	local D, N = Config.DAY_SECONDS, Config.NIGHT_SECONDS
	for k, zone in Config.ZONES do
		local off = Config.OFF_TIME_MULT
		local want = if zone.active == "day" then (D + N * off) / (D + N) else (D * off + N) / (D + N)
		H.near(Config.averageTimeMult(k), want, 1e-9, zone.id)
		-- matches what the payout loop pays over one full cycle, second by second
		local sum = 0
		for t = 0, D + N - 1 do
			sum += Config.timeMult(k, (Config.dayPhase(t + 0.5)))
		end
		H.near(Config.averageTimeMult(k), sum / (D + N), 1e-9, zone.id .. " integrated")
	end
end)

----------------------------------------------------------------------------------------------------
-- Payouts every second, silently: no "+$X" popups over the plants (owner 2026-10-15)
----------------------------------------------------------------------------------------------------
H.test("payout: every second, one second of the billboard's $/s, with no popup over the plant", function()
	H.eq(Config.PAYOUT_INTERVAL, 1)
	local fs = require("@lune/fs")
	local plot = fs.readFile("src/server/PlotService.luau")
	local a = string.find(plot, "local function payout(", 1, true)
	local b = string.find(plot, "function PlotService.start()", 1, true)
	local body = a and b and string.sub(plot, a, b) or ""
	H.ok(body ~= "", "the payout loop")
	-- the money paid and the label are the same number: earned = perSecond * PAYOUT_INTERVAL (= perSecond)
	H.ok(string.find(body, "local earned = perSecond * Config.PAYOUT_INTERVAL", 1, true) ~= nil, "earned per pass")
	H.ok(string.find(body, "setIncomeLabel(incomeLabel, plant.zone, perSecond, isNight)", 1, true) ~= nil, "label shows perSecond")
	H.ok(not string.find(body, "IncomePopup", 1, true), "plants earn silently: no popup over them")
	-- both go through Format.money: same text for every amount (fractional dollars round the same way)
	for _, perSecond in { 0.4, 3.333, 5.33, 15.99, 109.5, 1234.5, 98765.4, 2.5e6 } do
		H.eq(Format.money(perSecond * Config.PAYOUT_INTERVAL), Format.money(perSecond), `{perSecond}/s`)
	end
	-- money per unit time is unchanged: a minute of payouts is a minute of income
	local paid = 0
	for _ = 1, 60 / Config.PAYOUT_INTERVAL do
		paid += 5.33 * Config.PAYOUT_INTERVAL
	end
	H.near(paid, 5.33 * 60, 1e-9)
	-- popups stay readable: only plants near the camera pop, and at most MAX_POPUPS live at once
	local fx = fs.readFile("src/client/Effects.client.luau")
	H.ok(string.find(fx, "local POPUP_RANGE = 70", 1, true) ~= nil and string.find(fx, "Magnitude > POPUP_RANGE then", 1, true) ~= nil, "near the camera only")
	H.ok(string.find(fx, "local MAX_POPUPS = 40", 1, true) ~= nil, "a cap")
	-- the Plants panel push (the bulkiest) keeps its old 3 s cadence
	H.ok(string.find(body, "if sprouted or payoutPass % PLANTS_PUSH_EVERY == 0 then", 1, true) ~= nil, "Plants view every 3 passes (and when a seedling pops)")
end)

----------------------------------------------------------------------------------------------------
-- Plant info only on hover / tap, and nothing flat on the ground under a plant
----------------------------------------------------------------------------------------------------
H.test("plant info: the billboard is built hidden and PlantHover.client shows it on hover or a tap", function()
	local fs = require("@lune/fs")
	local plot = fs.readFile("src/server/PlotService.luau")
	local a = string.find(plot, "local function buildPlantModel", 1, true)
	local b = string.find(plot, "local function removePlantModel", 1, true)
	local build = a and b and string.sub(plot, a, b) or ""
	H.ok(string.find(build, "gui.Name = \"Info\"\r?\n%s*gui.Enabled = false") ~= nil, "Info billboard disabled by default")
	H.ok(fs.isFile("src/client/PlantHover.client.luau"), "the hover script")
	local hover = fs.readFile("src/client/PlantHover.client.luau")
	for _, needle in {
		"inst.Name ~= \"Info\"",
		"string.match(model.Name, \"^Plant_%d+$\")",
		"UserInputService:GetMouseLocation()",
		"camera:ViewportPointToRay(mouse.X, mouse.Y)",
		"UserInputService.TouchTapInWorld:Connect(",
		"local TAP_SECONDS = 3",
		"local on = gui == hovered or gui == tapped",
		"gui.Enabled = on",
		"model:GetBoundingBox()",
	} do
		H.ok(string.find(hover, needle, 1, true) ~= nil, needle)
	end
	-- the treadmill's "+X/s" and other world texts are untouched
	H.ok(not string.find(hover, "Treadmill", 1, true), "only plant billboards")
end)

H.test("plants: no dug-soil disc or aura ring under a plant", function()
	local fs = require("@lune/fs")
	local plot = fs.readFile("src/server/PlotService.luau")
	H.ok(not string.find(plot, "addSoil", 1, true) and not string.find(plot, "Soil_", 1, true) and not string.find(plot, "SOIL_DUG", 1, true), "no soil disc")
	local creatures = fs.readFile("src/server/CreatureModels.luau")
	H.ok(not string.find(creatures, "\"AuraRing\"", 1, true), "no aura ring")
end)

return nil
