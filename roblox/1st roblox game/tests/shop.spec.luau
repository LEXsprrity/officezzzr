-- The shop after the economy rework: money buys only trails and plot upgrades; everything else is
-- Robux (developer products with idempotent receipts). Trails (ownership, equip, Speed gain, the
-- visual), plot levels (price curve, slots, money multiplier), Robux grants, and the v1/v2 -> v3
-- save migrations.
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local H = require("./harness")
local Vector3 = H.Vector3

local Config = H.shared("Config")
local Shop = H.server("Shop")
local SpeedLogic = H.server("SpeedLogic")
local ProfileStore = H.server("ProfileStore")
local TrailService = H.server("TrailService")

local function never(): number
	error("this grant must not roll")
end

local function yes(): boolean
	return true
end

-- Runs fn with some developer product ids set (as if pasted from the Creator Dashboard), then puts
-- the stubs back, even if fn fails.
local function withIds(ids: { [string]: number }, fn: () -> ())
	local old = {}
	for name, id in ids do
		old[name] = Config.DEVELOPER_PRODUCTS[name].id
		Config.DEVELOPER_PRODUCTS[name].id = id
	end
	local ok, err = pcall(fn)
	for name, id in old do
		Config.DEVELOPER_PRODUCTS[name].id = id
	end
	if not ok then
		error(err, 0)
	end
end

----------------------------------------------------------------------------------------------------
-- Money buys only trails and plot upgrades
----------------------------------------------------------------------------------------------------
H.test("money: only trails and the plot upgrade have a money price", function()
	local view = { money = 1e30, plotLevel = 1, trails = { Grey = true } }
	H.ok((Config.priceOf("PlotUpgrade", view)) ~= nil)
	for _, t in Config.TRAILS do
		if t.price > 0 then
			H.eq((Config.priceOf("Trail:" .. t.id, view)), t.price, t.id)
		end
	end
	for _, id in { "Speed25", "SpeedMax", "SpeedMult", "Slot", "Treadmill", "SleepDust", "Product:Speed1M", "Product:Money8M",
		"Product:TreadmillX5", "Product:SleepDust3", "Product:TrailRed", "Product:PackSpace", "Pass:DoubleMoney", "Trail:Hacked", "Trail:", "" } do
		H.eq((Config.priceOf(id, view)), nil, id .. " has no money price")
	end
end)

H.test("money: Robux-only items refuse a money purchase and never charge", function()
	local p = ProfileStore.defaultProfile()
	p.money = 1e30
	local before = serde.encode("json", ProfileStore.serialize(p))
	for _, id in { "Speed25", "SpeedMax", "SpeedMult", "Slot", "Treadmill", "SleepDust", "Product:Speed1M", "Product:Money8M",
		"Product:TreadmillX5", "Product:SleepDust3", "Product:TrailRed", "Product:PackSpace", "Pass:ExtraSlots", "Nonsense" } do
		local ok, msg = Shop.buy(p, id)
		H.eq(ok, false, id)
		H.ok(type(msg) == "string" and #msg > 0, id .. " explains why")
	end
	H.eq(serde.encode("json", ProfileStore.serialize(p)), before, "nothing changed, nothing charged")
end)

H.test("money: the removed money-shop config is gone", function()
	for _, key in { "SPEED_MULT_TIERS", "SPEED_BUY_FRACTION", "SPEED_BUY_MIN", "SLOT_BASE_PRICE", "SLOT_PRICE_GROWTH", "SLEEP_DUST_PRICE",
		"PRICE_PER_SPEED", "POTIONS", "POTION_MIN_PRICE", "POTION_INCOME_SECONDS" } do
		H.eq((Config :: any)[key], nil, "Config." .. key)
	end
	H.eq((Config :: any).speedCost, nil, "Config.speedCost")
	for _, tier in Config.TREADMILL_TIERS do
		H.eq((tier :: any).price, nil, "treadmill tiers have no money price")
	end
end)

----------------------------------------------------------------------------------------------------
-- Trails
----------------------------------------------------------------------------------------------------
H.test("trails: seven tiers with the agreed multipliers, prices and Robux products", function()
	local want = {
		{ "Grey", "Common", 1.5, 0, nil, nil },
		{ "Green", "Uncommon", 2, 5e3, "TrailGreen", 16 },
		{ "Blue", "Rare", 2.5, 75e3, "TrailBlue", 24 },
		{ "Purple", "Epic", 3, 1.5e6, "TrailPurple", 40 },
		{ "Golden", "Legendary", 3.5, 30e6, "TrailGolden", 64 },
		{ "Red", "Mythic", 4, 600e6, "TrailRed", 100 },
		{ "Rainbow", "Secret", 5, 15e9, "TrailRainbow", 180 },
	}
	H.eq(#Config.TRAILS, #want)
	for i, w in want do
		local t = Config.TRAILS[i]
		H.eq(t.id, w[1])
		H.eq(t.rarity, w[2], t.id)
		H.eq(t.mult, w[3], t.id)
		H.eq(t.price, w[4], t.id)
		H.eq(t.product, w[5], t.id)
		if w[5] then
			local product = Config.DEVELOPER_PRODUCTS[w[5]]
			H.eq(product.kind, "Trail")
			H.eq(product.trail, t.id)
			H.eq(product.robux, w[6], t.id .. " R$")
			H.eq(product.id, 0, "ships as a stub")
		end
	end
	H.eq(Config.DEFAULT_TRAIL, "Grey")
	H.eq(Config.trailMult("Rainbow"), 5)
	H.eq(Config.trailMult("nope"), 1.5, "unknown -> the free trail")
end)

H.test("trails: every player owns and wears the free Grey trail from the start", function()
	local p = ProfileStore.defaultProfile()
	H.ok(p.trails.Grey)
	H.eq(p.equippedTrail, "Grey")
	H.eq((Config.priceOf("Trail:Grey", p)), nil, "Grey isn't for sale")
	H.eq((Shop.buy(p, "Trail:Grey")), false)
end)

H.test("trails: any tier can be bought directly with money; buying equips it and charges once", function()
	local p = ProfileStore.defaultProfile()
	p.money = 1e6
	local ok, msg = Shop.buy(p, "Trail:Blue") -- skipping Green
	H.ok(ok, msg)
	H.eq(p.money, 1e6 - 75e3)
	H.ok(p.trails.Blue)
	H.eq(p.trails.Green, nil, "lower tiers aren't granted")
	H.eq(p.equippedTrail, "Blue")
	local again = Shop.buy(p, "Trail:Blue")
	H.eq(again, false, "can't buy an owned trail twice")
	H.eq(p.money, 1e6 - 75e3)
	local poor = Shop.buy(p, "Trail:Purple")
	H.eq(poor, false, "Not enough money")
	H.eq(p.trails.Purple, nil)
	H.eq(p.money, 1e6 - 75e3)
end)

H.test("trails: only owned trails can be equipped", function()
	local p = ProfileStore.defaultProfile()
	p.money = 5e3
	H.ok(Shop.buy(p, "Trail:Green"))
	H.ok(Shop.equipTrail(p, "Grey"))
	H.eq(p.equippedTrail, "Grey")
	H.ok(Shop.equipTrail(p, "Green"))
	H.eq(p.equippedTrail, "Green")
	H.eq((Shop.equipTrail(p, "Rainbow")), false, "not owned")
	H.eq((Shop.equipTrail(p, "Hacked")), false, "unknown")
	H.eq(p.equippedTrail, "Green")
end)

H.test("trails: the equipped trail multiplies Speed gained walking and on the treadmill", function()
	local DT = Config.TICK
	local function gain(trail: string, onTreadmill: boolean): number
		local s = SpeedLogic.newState()
		for _ = 1, 5 do
			SpeedLogic.step(s, Vector3.new(0, 0, 0), DT, { walkSpeed = 80, onTreadmill = false, mult = 1, treadmillMult = 2 })
		end
		local to = if onTreadmill then Vector3.new(0, 0, 0) else Vector3.new(80 * DT, 0, 0)
		local g = SpeedLogic.step(s, to, DT, { walkSpeed = 80, onTreadmill = onTreadmill, mult = Config.trailMult(trail), treadmillMult = 2 })
		return g
	end
	for _, onTreadmill in { false, true } do
		local grey = gain("Grey", onTreadmill)
		H.near(grey, 80 * DT * Config.GAIN_PER_STUD * 1.5 * (if onTreadmill then 2 else 1), 1e-9, "Grey x1.5")
		for _, t in Config.TRAILS do
			H.near(gain(t.id, onTreadmill), grey / 1.5 * t.mult, 1e-9, t.id)
		end
	end
end)

H.test("trails: Robux receipts own and equip the trail, once per PurchaseId", function()
	local p = ProfileStore.defaultProfile()
	local money = p.money
	local confirm, status, grant = Shop.processReceipt(p, "TrailRed", "t-1", 0, never, yes)
	H.eq(confirm, true)
	H.eq(status, "granted")
	H.eq(grant.label, "Red Trail")
	H.ok(p.trails.Red)
	H.eq(p.equippedTrail, "Red")
	H.eq(p.money, money, "Robux trails never touch money")
	H.ok(Shop.equipTrail(p, "Grey"))
	local _, again = Shop.processReceipt(p, "TrailRed", "t-1", 0, never, yes)
	H.eq(again, "duplicate")
	H.eq(p.equippedTrail, "Grey", "a duplicate receipt doesn't re-equip")
end)

H.test("trails: an owned trail is never prompted for Robux again", function()
	withIds({ TrailBlue = 501, TrailGolden = 502 }, function()
		local p = ProfileStore.defaultProfile()
		p.trails.Blue = true
		local product, why = Shop.canPrompt(p, "TrailBlue")
		H.eq(product, nil)
		H.ok(why and string.find(why, "already own"), why)
		H.eq(Shop.canPrompt(p, "TrailGolden"), Config.DEVELOPER_PRODUCTS.TrailGolden)
	end)
end)

H.test("trails: TrailService builds a coloured Trail between two root attachments, and rebuilds on change", function()
	local char = roblox.Instance.new("Model")
	char.Name = "Character"
	H.eq(TrailService.apply(char, "Green"), nil, "no root part yet: nothing to do")
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = char
	local trail = TrailService.apply(char, "Green")
	H.ok(trail ~= nil and trail:IsA("Trail"))
	H.eq(trail.Parent, root)
	H.ok(trail.Attachment0 ~= nil and trail.Attachment1 ~= nil and trail.Attachment0 ~= trail.Attachment1, "two attachments")
	H.eq(trail.Attachment0.Parent, root)
	H.eq(trail.Attachment1.Parent, root)
	H.ok(trail.Attachment0.Position.Y > trail.Attachment1.Position.Y, "a vertical ribbon")
	H.ok(trail.Lifetime > 0 and trail.Enabled)
	local green = Config.trailById("Green").color
	local c0 = trail.Color.Keypoints[1].Value
	H.near(c0.R, green.R, 1e-3)
	H.near(c0.G, green.G, 1e-3)
	local greenLifetime = trail.Lifetime
	-- equipping another trail (or respawning) replaces it: one trail, two attachments
	local rainbow = TrailService.apply(char, "Rainbow")
	local trails, attachments = 0, 0
	for _, d in root:GetChildren() do
		if d:IsA("Trail") then
			trails += 1
		elseif d:IsA("Attachment") then
			attachments += 1
		end
	end
	H.eq(trails, 1)
	H.eq(attachments, 2)
	H.ok(#rainbow.Color.Keypoints >= 6, "Rainbow is a rainbow")
	H.ok(rainbow.Lifetime > greenLifetime, "better trails stream longer")
	H.eq(trail.Parent, nil, "the old trail is gone")
	H.ok(TrailService.apply(char, "Hacked"):IsA("Trail"), "an unknown id falls back to Grey")
end)

----------------------------------------------------------------------------------------------------
-- Plot upgrades
----------------------------------------------------------------------------------------------------
H.test("plot: level 1 = 5 slots, +1 slot per level up to SLOTS_MAX at the last level", function()
	H.eq(Config.plotSlots(1), Config.SLOTS_START)
	H.eq(Config.plotSlots(1), 5)
	H.eq(Config.PLOT_LEVEL_MAX, Config.SLOTS_MAX - Config.SLOTS_START + 1)
	H.eq(Config.plotSlots(Config.PLOT_LEVEL_MAX), Config.SLOTS_MAX)
	for L = 2, Config.PLOT_LEVEL_MAX do
		H.eq(Config.plotSlots(L), Config.plotSlots(L - 1) + 1)
	end
end)

H.test("plot: each level adds a small money multiplier (+6%), x2.5 at the last level", function()
	H.eq(Config.plotMoneyMult(1), 1)
	H.eq(Config.plotMoneyMult(2), 1.06)
	H.near(Config.plotMoneyMult(Config.PLOT_LEVEL_MAX), 2.5, 1e-9)
	for L = 2, Config.PLOT_LEVEL_MAX do
		H.near(Config.plotMoneyMult(L) - Config.plotMoneyMult(L - 1), 0.06, 1e-9, `level {L}`)
		H.eq(tostring(Config.plotMoneyMult(L)), string.format("%g", Config.plotMoneyMult(L)), "reads cleanly on signs")
	end
	-- combined with the 2x Money pass (the payout loop and offline income use Config.moneyMult)
	H.eq(Config.moneyMult(1, false), 1)
	H.eq(Config.moneyMult(1, true), 2)
	H.near(Config.moneyMult(Config.PLOT_LEVEL_MAX, true), 5, 1e-9)
end)

H.test("plot: prices start at $500 and climb steeply and strictly", function()
	H.eq(Config.plotUpgradePrice(2), 500)
	local last = 0
	for L = 2, Config.PLOT_LEVEL_MAX do
		local price = Config.plotUpgradePrice(L)
		H.ok(price > last, `level {L} costs {price}, level {L - 1} cost {last}`)
		if L > 2 then
			H.ok(price >= last * 2.5, "steep: each level at least 2.5x the last")
		end
		last = price
	end
end)

H.test("plot: the last level costs several hours of a strong late-game income", function()
	-- A strong late-game player: a full level-25 plot of full-grown Spirit Garden plants with the
	-- average pod rarity/mutation mix, day/night averaged, plus the 2x Money pass.
	local k = #Config.ZONES
	local w = Config.rarityWeights(k, 1)
	local total, avgRarity = 0, 0
	for _, x in w do
		total += x
	end
	for i, x in w do
		avgRarity += x / total * Config.RARITIES[i].income
	end
	local avgMutation = 1
	for _, m in Config.MUTATIONS do
		if not m.nightOnly and m.chance > 0 then
			avgMutation += m.chance * (m.income - 1)
		end
	end
	local level = Config.PLOT_LEVEL_MAX - 1
	local perPlant = Config.seedIncome(k) * math.sqrt(Config.GROW_MAX_FACTOR) * avgRarity * avgMutation * Config.averageTimeMult(k)
	local income = Config.plotSlots(level) * perPlant * Config.moneyMult(level, true)
	local hours = Config.plotUpgradePrice(Config.PLOT_LEVEL_MAX) / income / 3600
	print(string.format("        last plot level: $%.3g, %.1f h of $%.3g/s (2x Money pass; %.1f h without)", Config.plotUpgradePrice(Config.PLOT_LEVEL_MAX), hours, income, hours * 2))
	H.ok(hours >= 3, `only {hours} h`)
	H.ok(hours <= 12, `{hours} h is out of reach`)
	-- while level 2 stays cheap: under a minute of a starting plot (five Meadow sprouts)
	H.ok(Config.plotUpgradePrice(2) <= 5 * Config.seedIncome(1) * 60, "level 2 within a minute of a starting plot")
end)

H.test("plot: upgrading charges money, adds a level, and stops at the max", function()
	local p = ProfileStore.defaultProfile()
	H.eq((Shop.buy(p, "PlotUpgrade")), false, "no money")
	H.eq(p.plotLevel, 1)
	p.money = 1e30
	for L = 2, Config.PLOT_LEVEL_MAX do
		local before = p.money
		local price, label = Config.priceOf("PlotUpgrade", p)
		H.eq(price, Config.plotUpgradePrice(L))
		H.eq(label, `Plot Level {L}`)
		H.ok(Shop.buy(p, "PlotUpgrade"))
		H.eq(p.plotLevel, L)
		H.eq(p.money, before - price)
	end
	local price, label = Config.priceOf("PlotUpgrade", p)
	H.eq(price, nil)
	H.eq(label, "Maxed")
	local money = p.money
	H.eq((Shop.buy(p, "PlotUpgrade")), false)
	H.eq(p.plotLevel, Config.PLOT_LEVEL_MAX)
	H.eq(p.money, money)
end)

----------------------------------------------------------------------------------------------------
-- Robux: speed, money, treadmill and Sleep Dust products
----------------------------------------------------------------------------------------------------
H.test("robux: the agreed Speed, Money, Treadmill and Sleep Dust products, all id = 0 stubs", function()
	local function amounts(kind: string, field: string): string
		local out = {}
		for _, e in Config.products(kind) do
			H.eq(e.product.id, 0, e.name .. " ships as a stub")
			table.insert(out, `{(e.product :: any)[field]}/{e.product.robux}`)
		end
		return table.concat(out, " ")
	end
	H.eq(amounts("Speed", "amount"), "150000/64 1000000/200 10000000/560 50000000/1200 500000000/1600 1000000000/2400")
	H.eq(amounts("Money", "amount"), "24000/40 200000/80 800000/200 4000000/400 8000000/640")
	H.eq(amounts("Money", "minutes"), "10/40 30/80 60/200 180/400 360/640")
	H.eq(amounts("Treadmill", "tier"), "2/60 3/200")
	H.eq(amounts("Dust", "count"), "3/25")
	for name, product in Config.DEVELOPER_PRODUCTS do
		H.ok(product.kind == "Pack" or product.kind == "Speed" or product.kind == "Money" or product.kind == "Treadmill"
			or product.kind == "Dust" or product.kind == "Trail", name .. " has a known kind")
		H.ok(#name <= 24 and string.match(name, "^%a%w*$"), name .. " fits the Product:<name> remote id")
	end
end)

H.test("robux: id = 0 products say coming soon; owned treadmill tiers aren't prompted", function()
	local p = ProfileStore.defaultProfile()
	for name in Config.DEVELOPER_PRODUCTS do
		local product, why = Shop.canPrompt(p, name)
		H.eq(product, nil, name)
		H.ok(why and string.find(why, "coming soon"), why)
	end
	withIds({ TreadmillX3 = 301, TreadmillX5 = 302, Speed1B = 303 }, function()
		H.ok((Shop.canPrompt(p, "TreadmillX5")), "x5 directly from x2")
		p.treadmillTier = 3
		H.eq((Shop.canPrompt(p, "TreadmillX3")), nil, "already faster")
		H.eq((Shop.canPrompt(p, "TreadmillX5")), nil, "already owned")
		H.ok((Shop.canPrompt(p, "Speed1B")), "Speed packs are always open")
	end)
end)

H.test("robux: Speed, treadmill and Sleep Dust receipts grant exactly once", function()
	local p = ProfileStore.defaultProfile()
	local cases = {
		{ "Speed150K", function()
			return p.speed
		end, 150e3 },
		{ "Speed1B", function()
			return p.speed
		end, 150e3 + 1e9 },
		{ "TreadmillX5", function()
			return p.treadmillTier
		end, 3 },
		{ "TreadmillX3", function() -- arriving late (a raced prompt) never lowers the tier
			return p.treadmillTier
		end, 3 },
		{ "SleepDust3", function()
			return p.items.SleepDust
		end, Config.START_ITEMS.SleepDust + 3 },
	}
	for i, c in cases do
		local name, read, want = c[1], c[2], c[3]
		local confirm, status, grant = Shop.processReceipt(p, name, "r" .. i, 0, never, yes)
		H.eq(confirm, true, name)
		H.eq(status, "granted")
		H.eq(grant.name, name)
		H.eq(read(), want, name)
		for _ = 1, 2 do
			local again, dup = Shop.processReceipt(p, name, "r" .. i, 0, never, yes)
			H.eq(again, true, "duplicates are confirmed")
			H.eq(dup, "duplicate")
			H.eq(read(), want, name .. " granted once")
		end
	end
	H.eq(Config.TREADMILL_TIERS[p.treadmillTier].mult, 5)
	H.eq(p.money, 0, "none of these touch money")
end)

H.test("robux: a failed save isn't confirmed and its retry doesn't grant twice", function()
	local p = ProfileStore.defaultProfile()
	local confirm, status = Shop.processReceipt(p, "Speed10M", "s-1", 0, never, function()
		return false
	end)
	H.eq(confirm, false)
	H.eq(status, "granted")
	confirm, status = Shop.processReceipt(p, "Speed10M", "s-1", 0, never, yes)
	H.eq(confirm, true)
	H.eq(status, "duplicate")
	H.eq(p.speed, 10e6)
end)

H.test("robux: Money packs pay max(fixed amount, N minutes of current income), once", function()
	local P = Config.DEVELOPER_PRODUCTS
	-- a new player gets the fixed amounts
	for _, e in Config.products("Money") do
		H.eq(Config.moneyPackAmount(e.product, 0), e.product.amount, e.name)
		H.eq(Config.moneyPackAmount(e.product, -5), e.product.amount, "negative income is ignored")
	end
	-- a late-game player gets minutes of income instead
	local income = 1e9
	H.eq(Config.moneyPackAmount(P.Money24K, income), 10 * 60 * income)
	H.eq(Config.moneyPackAmount(P.Money8M, income), 360 * 60 * income)
	-- the crossover: exactly where N minutes of income beat the fixed amount
	local cross = P.Money200K.amount / (P.Money200K.minutes * 60)
	H.eq(Config.moneyPackAmount(P.Money200K, cross * 0.5), 200e3)
	H.eq(Config.moneyPackAmount(P.Money200K, cross * 2), 400e3)
	-- bigger packs are always worth more
	for _, inc in { 0, 10, 1e4, 1e8, 1e12 } do
		local last = 0
		for _, e in Config.products("Money") do
			local amount = Config.moneyPackAmount(e.product, inc)
			H.ok(amount > last, `{e.name} at income {inc}`)
			last = amount
		end
	end
	-- the receipt pays what the card showed (the same income), once
	local p = ProfileStore.defaultProfile()
	local _, status, grant = Shop.processReceipt(p, "Money4M", "m-1", income, never, yes)
	H.eq(status, "granted")
	H.eq(grant.compensation, 180 * 60 * income)
	H.eq(p.money, 180 * 60 * income)
	Shop.processReceipt(p, "Money4M", "m-1", income, never, yes)
	H.eq(p.money, 180 * 60 * income, "paid once")
	H.ok(string.find(grant.label, "Cash Crate"), grant.label)
end)

----------------------------------------------------------------------------------------------------
-- Save migrations (v1/v2 -> v3)
----------------------------------------------------------------------------------------------------
H.test("migration: old Speed Gain tiers become the nearest trail at or below (never a lower multiplier)", function()
	-- old tier: x1, x2, x3, x5, x10, x25
	local want = { "Grey", "Green", "Purple", "Rainbow", "Rainbow", "Rainbow" }
	for tier, id in want do
		local old = ProfileStore.LEGACY_SPEED_MULT[tier].mult
		local p = ProfileStore.deserialize({ v = 2, money = 100, speedMultTier = tier })
		H.eq(p.equippedTrail, id, `x{old}`)
		H.ok(p.trails[id] and p.trails.Grey, "owned, plus the free one")
		local mult = Config.trailMult(p.equippedTrail)
		H.ok(mult >= math.min(old, 5), `x{old} -> x{mult}`)
		-- nearest at or below: no trail sits between the old multiplier and the one given
		for _, t in Config.TRAILS do
			H.ok(not (t.mult > mult and t.mult <= old), `{t.id} would have been nearer for x{old}`)
		end
	end
end)

H.test("migration: tiers above the best trail (x10, x25) are refunded what they cost", function()
	local L = ProfileStore.LEGACY_SPEED_MULT
	H.eq(ProfileStore.deserialize({ v = 2, money = 100, speedMultTier = 4 }).money, 100, "x5 -> Rainbow x5, nothing lost")
	H.eq(ProfileStore.deserialize({ v = 2, money = 100, speedMultTier = 5 }).money, 100 + L[5].price)
	H.eq(ProfileStore.deserialize({ v = 2, money = 100, speedMultTier = 6 }).money, 100 + L[5].price + L[6].price)
	H.eq(ProfileStore.deserialize({ v = 1, speedMultTier = 1 }).money, 0)
end)

H.test("migration: bought slots become the plot level with the same slots", function()
	for slots = Config.SLOTS_START, Config.SLOTS_MAX do
		local p = ProfileStore.deserialize({ v = 2, slots = slots })
		H.eq(p.plotLevel, slots - Config.SLOTS_START + 1)
		H.eq(Config.plotSlots(p.plotLevel), slots, `{slots} slots kept`)
	end
	H.eq(ProfileStore.deserialize({ v = 2, slots = 999 }).plotLevel, Config.PLOT_LEVEL_MAX, "clamped")
	H.eq(ProfileStore.deserialize({ v = 2, slots = 2 }).plotLevel, 1, "clamped")
	H.eq(ProfileStore.levelForSlots(12), 8)
end)

H.test("migration: a migrated save is written as v3 and isn't migrated (or refunded) again", function()
	local old = { v = 2, money = 1000, speed = 5, speedMultTier = 6, treadmillTier = 2, slots = 12, plants = {}, index = {}, items = { SleepDust = 1 } }
	local p = ProfileStore.deserialize(serde.decode("json", serde.encode("json", old)))
	local refunded = p.money
	H.eq(refunded, 1000 + 250e6 + 10e9)
	local data = serde.decode("json", serde.encode("json", ProfileStore.serialize(p)))
	H.eq(data.v, 3)
	H.eq(data.speedMultTier, nil, "the legacy field is dropped")
	H.eq(data.slots, nil)
	H.eq(data.plotLevel, 8)
	H.eq(data.trail, "Rainbow")
	local back = ProfileStore.deserialize(data)
	H.eq(back.money, refunded, "no second refund")
	H.eq(back.plotLevel, 8)
	H.eq(back.equippedTrail, "Rainbow")
	H.eq(back.treadmillTier, 2, "treadmill tier kept")
	local same, why = H.deepEq(back, p)
	H.ok(same, why)
end)

return nil
