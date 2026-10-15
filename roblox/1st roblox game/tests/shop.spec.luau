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
-- Money buys only trails, plot upgrades and treadmill tiers
----------------------------------------------------------------------------------------------------
H.test("money: only trails, the plot upgrade and the treadmill upgrade have a money price", function()
	local view = { money = 1e30, plotLevel = 1, trails = { Grey = true } }
	H.ok((Config.priceOf("PlotUpgrade", view)) ~= nil)
	H.eq((Config.priceOf("TreadmillUpgrade", view)), Config.TREADMILL_TIERS[2].price, "the next treadmill tier")
	for _, t in Config.TRAILS do
		if t.price > 0 then
			H.eq((Config.priceOf("Trail:" .. t.id, view)), t.price, t.id)
		end
	end
	for _, id in { "Speed25", "SpeedMax", "SpeedMult", "Slot", "Treadmill", "SleepDust", "Product:Speed1M", "Product:Money8M",
		"Product:TreadmillT1", "Product:SleepDust3", "Product:TrailRed", "Product:PackSpace", "Pass:DoubleMoney", "Trail:Hacked", "Trail:", "" } do
		H.eq((Config.priceOf(id, view)), nil, id .. " has no money price")
	end
end)

H.test("money: Robux-only items refuse a money purchase and never charge", function()
	local p = ProfileStore.defaultProfile()
	p.money = 1e30
	local before = serde.encode("json", ProfileStore.serialize(p))
	for _, id in { "Speed25", "SpeedMax", "SpeedMult", "Slot", "Treadmill", "SleepDust", "Product:Speed1M", "Product:Money8M",
		"Product:TreadmillT1", "Product:SleepDust3", "Product:TrailRed", "Product:PackSpace", "Pass:ExtraSlots", "Nonsense" } do
		local ok, msg = Shop.buy(p, id)
		H.eq(ok, false, id)
		H.ok(type(msg) == "string" and #msg > 0, id .. " explains why")
	end
	H.eq(serde.encode("json", ProfileStore.serialize(p)), before, "nothing changed, nothing charged")
end)

H.test("money: the removed money-shop config is gone", function()
	for _, key in { "SPEED_MULT_TIERS", "SPEED_BUY_FRACTION", "SPEED_BUY_MIN", "SLOT_BASE_PRICE", "SLOT_PRICE_GROWTH", "SLEEP_DUST_PRICE",
		"SLEEP_DUST_EXTRA", "SLEEP_DUST_RANGE", "SLEEP_DUST_LASTS",
		"PRICE_PER_SPEED", "POTIONS", "POTION_MIN_PRICE", "POTION_INCOME_SECONDS" } do
		H.eq((Config :: any)[key], nil, "Config." .. key)
	end
	H.eq((Config :: any).speedCost, nil, "Config.speedCost")
end)

----------------------------------------------------------------------------------------------------
-- Trails
----------------------------------------------------------------------------------------------------
H.test("trails: seven tiers with the agreed multipliers, prices and Robux products", function()
	local want = {
		{ "Grey", "Common", 1, 0, nil, nil },
		{ "Green", "Uncommon", 1.25, 5e3, "TrailGreen", 16 },
		{ "Blue", "Rare", 1.5, 75e3, "TrailBlue", 24 },
		{ "Purple", "Epic", 1.75, 1.5e6, "TrailPurple", 40 },
		{ "Golden", "Legendary", 2, 30e6, "TrailGolden", 64 },
		{ "Red", "Mythic", 2.5, 20e9, "TrailRed", 100 },
		{ "Rainbow", "Secret", 3, 1e12, "TrailRainbow", 180 },
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
	H.eq(Config.trailMult("Rainbow"), 3)
	H.eq(Config.trailMult("nope"), 1, "unknown -> the free trail")
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
			SpeedLogic.step(s, Vector3.new(0, 0, 0), DT, { walkSpeed = 80, onTreadmill = false, mult = 1, treadmillTier = 1, trailMult = 1 })
		end
		local to = if onTreadmill then Vector3.new(0, 0, 0) else Vector3.new(80 * DT, 0, 0)
		local g = SpeedLogic.step(s, to, DT, { walkSpeed = 80, onTreadmill = onTreadmill, mult = Config.speedPerStud(trail), treadmillTier = 1, trailMult = Config.trailMult(trail) })
		return g
	end
	for _, onTreadmill in { false, true } do
		local grey = gain("Grey", onTreadmill)
		H.near(grey, if onTreadmill then Config.treadmillRate(1) * DT else 80 * DT * Config.BASE_SPEED_PER_STUD, 1e-9, "Grey x1: the flat base (the treadmill: its fixed rate)")
		for _, t in Config.TRAILS do
			H.near(gain(t.id, onTreadmill), grey * t.mult, 1e-9, t.id)
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
-- Robux: speed, money and treadmill products
----------------------------------------------------------------------------------------------------
H.test("robux: the agreed Speed, Money and Treadmill products, all id = 0 stubs; no Sleep Dust", function()
	local function amounts(kind: string, field: string): string
		local out = {}
		for _, e in Config.products(kind) do
			H.eq(e.product.id, 0, e.name .. " ships as a stub")
			table.insert(out, `{(e.product :: any)[field]}/{e.product.robux}`)
		end
		return table.concat(out, " ")
	end
	H.eq(amounts("Speed", "amount"), "25000/9 150000/36 250000/64 750000/76 3000000/560 10000000/1200 25000000/1600 50000000/2400")
	H.eq(amounts("Money", "amount"), "24000/40 200000/80 800000/200 4000000/400 8000000/640")
	H.eq(amounts("TreadmillUpgrade", "tier"), "1/19 2/39 3/79")
	H.eq(#Config.products("Treadmill"), 0, "the old direct x3/x5 products were replaced by one-tier upgrades")
	H.eq(#Config.products("Dust"), 0, "Sleep Dust was removed")
	H.eq(Config.DEVELOPER_PRODUCTS.SleepDust3, nil)
	for name, product in Config.DEVELOPER_PRODUCTS do
		H.ok(product.kind == "Pack" or product.kind == "Speed" or product.kind == "Money" or product.kind == "TreadmillUpgrade"
			or product.kind == "Trail" or product.kind == "PlotUpgrade" or product.kind == "GrowNow", name .. " has a known kind")
		H.ok(#name <= 24 and string.match(name, "^%a%w*$"), name .. " fits the Product:<name> remote id")
	end
end)

H.test("robux: id = 0 products say coming soon; only the treadmill's own upgrade tier is prompted", function()
	local p = ProfileStore.defaultProfile()
	for name, item in Config.DEVELOPER_PRODUCTS do
		local product, why = Shop.canPrompt(p, name)
		H.eq(product, nil, name)
		H.ok(why and string.find(why, if item.retired then "isn't sold any more" else "coming soon", 1, true), why)
	end
	withIds({ TreadmillT1 = 301, TreadmillT2 = 302, TreadmillT3 = 304, Speed50M = 303 }, function()
		H.ok((Shop.canPrompt(p, "TreadmillT1")), "tier 1 -> T1")
		H.eq((Shop.canPrompt(p, "TreadmillT2")), nil, "not a later tier's product")
		p.treadmillTier = 5
		H.eq((Shop.canPrompt(p, "TreadmillT1")), nil, "a cheap tier can't buy a late upgrade")
		H.ok((Shop.canPrompt(p, "TreadmillT2")), "tier 5 -> T2")
		p.treadmillTier = Config.TREADMILL_MAX
		for _, name in { "TreadmillT1", "TreadmillT2", "TreadmillT3" } do
			local got, why = Shop.canPrompt(p, name)
			H.eq(got, nil, name .. " at the last tier")
			H.ok(why and string.find(why, "fully upgraded"), why)
		end
		H.ok((Shop.canPrompt(p, "Speed50M")), "Speed packs are always open")
	end)
end)

H.test("robux: Speed and treadmill receipts grant exactly once", function()
	local p = ProfileStore.defaultProfile()
	local cases = {
		{ "Speed150K", function()
			return p.speed
		end, 150e3 },
		{ "Speed50M", function()
			return p.speed
		end, 150e3 + 50e6 },
		{ "TreadmillT1", function()
			return p.treadmillTier
		end, 2 },
		{ "TreadmillT1", function() -- a second purchase (new PurchaseId): one more tier
			return p.treadmillTier
		end, 3 },
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
	H.eq(p.treadmillTier, 3)
	H.eq(p.money, 0, "none of these touch money")
end)

H.test("robux: a receipt for an unknown product (e.g. the removed SleepDust3) is not confirmed and changes nothing", function()
	local p = ProfileStore.defaultProfile()
	local before = serde.encode("json", ProfileStore.serialize(p))
	local saved = false
	for _, name in { "SleepDust3", "Nonsense" } do
		local confirm, status, grant = Shop.processReceipt(p, name, "u-" .. name, 0, never, function()
			saved = true
			return true
		end)
		H.eq(confirm, false, name .. " -> NotProcessedYet")
		H.eq(status, "unknown")
		H.eq(grant, nil)
	end
	local confirm, status = Shop.processReceipt(p, nil, "u-nil", 0, never, yes)
	H.eq(confirm, false, "a product id that maps to no name -> NotProcessedYet")
	H.eq(status, "unavailable")
	H.eq(saved, false, "nothing was saved")
	H.eq(serde.encode("json", ProfileStore.serialize(p)), before, "nothing granted, no receipt id remembered")
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

H.test("robux: Money packs pay a fixed amount, whatever you earn (owner 2026-10-15), once", function()
	local want = { Money24K = 24e3, Money200K = 200e3, Money800K = 800e3, Money4M = 4e6, Money8M = 8e6 }
	local labels = { Money24K = "Pocket Cash", Money200K = "Cash Bag", Money800K = "Cash Stack", Money4M = "Cash Crate", Money8M = "Cash Vault" }
	for _, e in Config.products("Money") do
		H.eq(e.product.label, labels[e.name], e.name)
		H.eq((e.product :: any).minutes, nil, `{e.name}: no minutes-of-income share any more`)
		H.eq(Config.moneyPackAmount(e.product), want[e.name], e.name)
	end
	-- a late-game player gets the same fixed amount
	local income = 1e9
	local p = ProfileStore.defaultProfile()
	local _, status, grant = Shop.processReceipt(p, "Money4M", "m-1", income, never, yes)
	H.eq(status, "granted")
	H.eq(grant.compensation, 4e6)
	H.eq(p.money, 4e6)
	Shop.processReceipt(p, "Money4M", "m-1", income, never, yes)
	H.eq(p.money, 4e6, "paid once")
	H.ok(string.find(grant.label, "Cash Crate"), grant.label)
	_, _, grant = Shop.processReceipt(p, "Money24K", "m-2", 1e12, never, yes)
	H.eq(grant.compensation, 24e3, "Pocket Cash is always $24K")
	-- the Shop card shows the fixed amount, set once (no income watcher)
	local hud = string.gsub(require("@lune/fs").readFile("src/client/HUD.client.luau"), "\r", "")
	H.ok(string.find(hud, "+{Format.money(Config.moneyPackAmount(entry.product))}</font> CASH`", 1, true) ~= nil, "the card's amount")
	H.ok(not string.find(hud, "moneyPackAmount(entry.product, stats.income", 1, true), "never scaled by income")
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
		-- compared with the trails' multipliers of the time (v3-v6; v7 shrank every trail)
		local legacy = ProfileStore.LEGACY_TRAIL_MULT
		local mult = legacy[p.equippedTrail]
		H.ok(mult >= math.min(old, 5), `x{old} -> x{mult}`)
		-- nearest at or below: no trail sits between the old multiplier and the one given
		for _, t in Config.TRAILS do
			H.ok(legacy[t.id] ~= nil, `{t.id} has a legacy multiplier`)
			H.ok(not (legacy[t.id] > mult and legacy[t.id] <= old), `{t.id} would have been nearer for x{old}`)
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

H.test("migration: a migrated save is written in the current format and isn't migrated (or refunded) again", function()
	local old = { v = 2, money = 1000, speed = 5, speedMultTier = 6, treadmillTier = 2, slots = 12, plants = {}, index = {}, items = { SleepDust = 1 } }
	local p = ProfileStore.deserialize(serde.decode("json", serde.encode("json", old)))
	local refunded = p.money
	H.eq(refunded, 1000 + 250e6 + 10e9)
	local data = serde.decode("json", serde.encode("json", ProfileStore.serialize(p)))
	H.eq(data.v, ProfileStore.VERSION)
	H.eq(data.speedMultTier, nil, "the legacy field is dropped")
	H.eq(data.slots, nil)
	H.eq(data.plotLevel, 8)
	H.eq(data.trail, "Rainbow")
	local back = ProfileStore.deserialize(data)
	H.eq(back.money, refunded, "no second refund")
	H.eq(back.plotLevel, 8)
	H.eq(back.equippedTrail, "Rainbow")
	H.eq(back.treadmillTier, 5, "the old Robux x3 treadmill became tier 5 (x3 in v5) and keeps it")
	local same, why = H.deepEq(back, p)
	H.ok(same, why)
end)

return nil
