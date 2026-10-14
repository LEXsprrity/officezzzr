-- The treadmill: only your own plot's belt plays the run-in-place animation (Shared/Treadmill, used by
-- Effects.client), the 10 tiers (money price and Robux price tiers TreadmillT1..T3), money purchases and
-- receipts that grant exactly one tier, the owner-only prompt check, and old saves (3 tiers) loading.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local H = require("./harness")

local Config = H.shared("Config")
local Treadmill = H.shared("Treadmill")
local Shop = H.server("Shop")
local ProfileStore = H.server("ProfileStore")
local WorldBuilder = H.server("WorldBuilder")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local function never(): number
	error("a treadmill upgrade must not roll")
end

local function yes(): boolean
	return true
end

local TIER_IDS = { TreadmillT1 = 901, TreadmillT2 = 902, TreadmillT3 = 903 }

local function withIds(fn: () -> ())
	for name, id in TIER_IDS do
		Config.DEVELOPER_PRODUCTS[name].id = id
	end
	local ok, err = pcall(fn)
	for name in TIER_IDS do
		Config.DEVELOPER_PRODUCTS[name].id = 0
	end
	if not ok then
		error(err, 0)
	end
end

local function profileAt(tier: number)
	local p = ProfileStore.defaultProfile()
	p.treadmillTier = tier
	return p
end

-- A belt part like WorldBuilder's (Role, PlotIndex), turned and somewhere in the base.
local function belt(plot: number?, at: Vector3): BasePart
	local part = roblox.Instance.new("Part")
	part.Size = Vector3.new(5.2, 1, 18)
	part.CFrame = CFrame.new(at) * CFrame.Angles(0, math.rad(90), 0)
	part:SetAttribute("Role", "TreadmillBelt")
	if plot then
		part:SetAttribute("PlotIndex", plot)
	end
	part.Parent = H.workspace
	return part
end

local function above(part: BasePart, x: number?, z: number?): Vector3
	return (part.CFrame * CFrame.new(x or 0, part.Size.Y / 2 + 3, z or 0)).Position
end

----------------------------------------------------------------------------------------------------
-- Own-plot-only run animation
----------------------------------------------------------------------------------------------------
H.test("treadmill: the shared belt check is the server's (WorldBuilder.onBelt)", function()
	local b = belt(1, Vector3.new(10, 1, 20))
	for _, x in { -3, -2.5, 0, 2.5, 3 } do
		for _, z in { -10, -8.9, 0, 8.9, 10 } do
			for _, y in { -1, 0.5, 3, 7, 9 } do
				local pos = (b.CFrame * CFrame.new(x, y, z)).Position
				H.eq(Treadmill.onBelt(b.CFrame, b.Size, pos), WorldBuilder.onBelt(b, pos), `({x}, {y}, {z})`)
			end
		end
	end
	b:Destroy()
end)

H.test("treadmill: standing on your own belt is 'own', anyone else's is 'other', off the belts nil", function()
	local mine, theirs = belt(2, Vector3.new(0, 1, 0)), belt(4, Vector3.new(100, 1, 0))
	local belts = { theirs, mine }
	H.eq(Treadmill.standing(belts, above(mine), 2), "own")
	H.eq(Treadmill.standing(belts, above(mine, 0, 8), 2), "own", "near its end (it's turned 90°)")
	H.eq(Treadmill.standing(belts, above(theirs), 2), "other", "plot 4's treadmill")
	H.eq(Treadmill.standing(belts, above(mine), 4), "other", "...and mine for plot 4's owner")
	H.eq(Treadmill.standing(belts, above(mine) + Vector3.new(0, 0, 30), 2), nil, "on the grass")
	H.eq(Treadmill.standing(belts, above(mine), nil), "other", "no plot yet: nothing is yours")
	local _, plot = Treadmill.beltAt(belts, above(theirs))
	H.eq(plot, 4)
	local unmarked = belt(nil, Vector3.new(0, 1, 200))
	H.eq(Treadmill.standing({ unmarked }, above(unmarked), 2), "other", "a belt without PlotIndex is never yours")
	local onTheirs = above(theirs)
	theirs.Parent = nil
	H.eq(Treadmill.standing(belts, onTheirs, 2), nil, "a removed (streamed-out) belt doesn't count")
	theirs:Destroy()
	mine:Destroy()
	unmarked:Destroy()
end)

H.test("treadmill: the run animation plays only on your own belt, alive and standing still", function()
	H.eq(Treadmill.shouldRun("own", true, 0), true, "AFK on your treadmill")
	H.eq(Treadmill.shouldRun("own", true, 0.05), true, "a stick barely touched")
	H.eq(Treadmill.shouldRun("own", true, 1), false, "walking plays the normal run animation")
	H.eq(Treadmill.shouldRun("own", false, 0), false, "dead")
	H.eq(Treadmill.shouldRun("other", true, 0), false, "someone else's treadmill: the playtest bug")
	H.eq(Treadmill.shouldRun(nil, true, 0), false, "not on a belt")
end)

H.test("treadmill: Effects.client decides with Treadmill.shouldRun and knows its own plot", function()
	local source = fs.readFile("src/client/Effects.client.luau")
	H.ok(string.find(source, "Treadmill.shouldRun(", 1, true) ~= nil, "uses the shared rule")
	H.ok(string.find(source, "Treadmill.standing(", 1, true) ~= nil, "with own/other")
	H.ok(string.find(source, "partial.plot", 1, true) ~= nil, "reads its plot from StatsUpdate")
	H.ok(string.find(source, "onAnyBelt", 1, true) == nil, "the any-belt check is gone")
	local speed = fs.readFile("src/server/SpeedService.luau")
	H.ok(string.find(speed, "This isn't your treadmill", 1, true) ~= nil, "the server says why someone else's belt pays nothing")
end)

----------------------------------------------------------------------------------------------------
-- Tiers
----------------------------------------------------------------------------------------------------
H.test("treadmill tiers: 10 tiers from the free x2, multipliers and prices strictly rising", function()
	H.eq(Config.TREADMILL_MAX, 10)
	H.eq(#Config.TREADMILL_TIERS, Config.TREADMILL_MAX)
	H.eq(Config.TREADMILL_TIERS[1].mult, 2, "the free tier is unchanged")
	H.eq(Config.TREADMILL_TIERS[1].price, 0)
	for tier = 2, Config.TREADMILL_MAX do
		local t, prev = Config.TREADMILL_TIERS[tier], Config.TREADMILL_TIERS[tier - 1]
		H.ok(t.mult > prev.mult, `tier {tier} multiplier rises`)
		H.ok(t.price > prev.price, `tier {tier} price rises`)
		H.eq(Config.treadmillMult(tier), t.mult)
	end
	H.ok(Config.TREADMILL_TIERS[Config.TREADMILL_MAX].mult >= 4 * Config.TREADMILL_TIERS[1].mult, "the last tier is a strong AFK rate")
	H.eq(Config.treadmillMult(0), 2, "bad tiers clamp")
	H.eq(Config.treadmillMult(99), Config.TREADMILL_TIERS[Config.TREADMILL_MAX].mult)
	H.eq(Config.treadmillMult(2.7), Config.TREADMILL_TIERS[2].mult)
end)

H.test("treadmill tiers: the money price is the next tier's, nothing at the last", function()
	for tier = 1, Config.TREADMILL_MAX - 1 do
		local price, label = Config.priceOf("TreadmillUpgrade", { money = 0, plotLevel = 1, trails = {}, treadmillTier = tier })
		H.eq(price, Config.TREADMILL_TIERS[tier + 1].price, `tier {tier}`)
		H.eq(label, `Treadmill x{Config.treadmillMult(tier + 1)}`)
	end
	H.eq((Config.priceOf("TreadmillUpgrade", { money = 0, plotLevel = 1, trails = {} })), Config.TREADMILL_TIERS[2].price, "no tier = the free one")
	local price, label = Config.priceOf("TreadmillUpgrade", { money = 0, plotLevel = 1, trails = {}, treadmillTier = Config.TREADMILL_MAX })
	H.eq(price, nil)
	H.eq(label, "Maxed")
end)

H.test("treadmill tiers: three id = 0 Robux products, one per band of upgrades, rising in price", function()
	local list = Config.products("TreadmillUpgrade")
	H.eq(#list, Config.TREADMILL_UPGRADE_TIERS)
	local last = 0
	for i, e in list do
		H.eq(e.name, `TreadmillT{i}`, "cheapest first = tier order")
		H.eq(e.product.tier, i)
		H.eq(e.product.id, 0, e.name .. " ships as a stub")
		H.ok(e.product.robux > last, "rising")
		last = e.product.robux
	end
	-- every upgrade has exactly one product, and its Dashboard name says which multipliers it sells
	local covered = {}
	for tier = 1, Config.TREADMILL_MAX - 1 do
		local name, product = Config.treadmillUpgradeProduct(tier)
		H.ok(name ~= nil and product ~= nil, `tier {tier} has an upgrade`)
		local lo, hi = string.match(product.label, "%(x([%d%.]+)%-x([%d%.]+)%)")
		local nextMult = Config.treadmillMult(tier + 1)
		H.ok(nextMult >= tonumber(lo) and nextMult <= tonumber(hi), `{product.label} sells x{nextMult}`)
		covered[product.tier] = (covered[product.tier] or 0) + 1
	end
	H.eq(table.concat(covered, " "), "3 3 3", "upgrades per band")
	H.eq(Config.treadmillUpgradeProduct(Config.TREADMILL_MAX), nil, "nothing to buy at the last tier")
	H.eq(Config.treadmillUpgradeTier(0), 1, "a bad tier still gets a band")
end)

----------------------------------------------------------------------------------------------------
-- Buying
----------------------------------------------------------------------------------------------------
H.test("treadmill money: buys exactly the next tier, charges its price, refuses when short or maxed", function()
	local p = profileAt(1)
	p.money = Config.TREADMILL_TIERS[2].price + 5
	local ok, msg = Shop.buy(p, "TreadmillUpgrade")
	H.eq(ok, true, msg)
	H.eq(p.treadmillTier, 2)
	H.eq(p.money, 5)
	H.eq(msg, `Treadmill x{Config.treadmillMult(2)}`)
	ok, msg = Shop.buy(p, "TreadmillUpgrade")
	H.eq(ok, false)
	H.eq(msg, "Not enough money")
	H.eq(p.treadmillTier, 2, "unchanged")
	H.eq(p.money, 5, "nothing charged")
	local maxed = profileAt(Config.TREADMILL_MAX)
	maxed.money = 1e30
	ok, msg = Shop.buy(maxed, "TreadmillUpgrade")
	H.eq(ok, false)
	H.eq(msg, "Maxed")
	H.eq(maxed.treadmillTier, Config.TREADMILL_MAX)
	H.eq(maxed.money, 1e30)
	-- a rich player climbs one tier per purchase, to the top and no further
	local rich = profileAt(1)
	rich.money = 1e30
	for tier = 2, Config.TREADMILL_MAX do
		H.eq((Shop.buy(rich, "TreadmillUpgrade")), true)
		H.eq(rich.treadmillTier, tier)
	end
	H.eq((Shop.buy(rich, "TreadmillUpgrade")), false)
end)

H.test("treadmill robux: only the band of the current tier is prompted, never once maxed", function()
	local p = profileAt(4)
	local product, why = Shop.canPrompt(p, "TreadmillT2")
	H.eq(product, nil)
	H.ok(why and string.find(why, "coming soon"), why)
	withIds(function()
		H.eq(Shop.canPrompt(p, "TreadmillT2"), Config.DEVELOPER_PRODUCTS.TreadmillT2, "tier 4 -> T2")
		for _, other in { "TreadmillT1", "TreadmillT3" } do
			H.eq((Shop.canPrompt(p, other)), nil, other)
		end
		local maxed = profileAt(Config.TREADMILL_MAX)
		for name in TIER_IDS do
			local got, reason = Shop.canPrompt(maxed, name)
			H.eq(got, nil, name)
			H.ok(reason and string.find(reason, "fully upgraded"), reason)
		end
	end)
end)

H.test("treadmill receipt: one tier once, from the tier the treadmill has when it arrives; maxed pays money", function()
	local p = profileAt(3)
	local confirm, status, grant = Shop.processReceipt(p, "TreadmillT1", "tm-1", 0, never, yes)
	H.eq(confirm, true)
	H.eq(status, "granted")
	H.eq(p.treadmillTier, 4)
	H.eq(grant.label, `Treadmill x{Config.treadmillMult(4)}`)
	for _ = 1, 3 do
		local again, dup = Shop.processReceipt(p, "TreadmillT1", "tm-1", 0, never, yes)
		H.eq(again, true)
		H.eq(dup, "duplicate")
		H.eq(p.treadmillTier, 4, "a retried receipt never grants twice")
	end
	-- tiers bought with money since the prompt: still exactly one more
	p.treadmillTier = 7
	Shop.processReceipt(p, "TreadmillT1", "tm-2", 0, never, yes)
	H.eq(p.treadmillTier, 8)
	H.eq(p.money, 0)
	-- a failed save isn't confirmed, and the retry doesn't grant again
	local c2, s2 = Shop.processReceipt(p, "TreadmillT3", "tm-3", 0, never, function()
		return false
	end)
	H.eq(c2, false)
	H.eq(s2, "granted")
	H.eq(p.treadmillTier, 9)
	c2, s2 = Shop.processReceipt(p, "TreadmillT3", "tm-3", 0, never, yes)
	H.eq(c2, true)
	H.eq(s2, "duplicate")
	H.eq(p.treadmillTier, 9)
	-- at the top: the last tier's money price instead
	p.treadmillTier = Config.TREADMILL_MAX
	local _, _, maxedGrant = Shop.processReceipt(p, "TreadmillT3", "tm-4", 0, never, yes)
	H.eq(p.treadmillTier, Config.TREADMILL_MAX)
	H.eq(maxedGrant.compensation, Config.treadmillUpgradeMaxedPay())
	H.eq(p.money, Config.TREADMILL_TIERS[Config.TREADMILL_MAX].price)
	H.ok(string.find(maxedGrant.label, "maxed", 1, true) ~= nil, maxedGrant.label)
end)

H.test("treadmill prompts: only the plot's owner, standing near the belt, can buy", function()
	local b = belt(3, Vector3.new(0, 1, 0))
	local near = above(b, 0, 8)
	H.ok(Treadmill.canUpgrade(true, near, b.CFrame.Position, b.Size), "the owner on their belt")
	H.ok(Treadmill.canUpgrade(true, b.CFrame.Position + Vector3.new(Treadmill.promptDistance(b.Size), 0, 0), b.CFrame.Position, b.Size), "at the prompt's range")
	H.ok(not Treadmill.canUpgrade(false, near, b.CFrame.Position, b.Size), "not the owner: rejected")
	H.ok(not Treadmill.canUpgrade(true, b.CFrame.Position + Vector3.new(60, 0, 0), b.CFrame.Position, b.Size), "too far away")
	H.ok(not Treadmill.canUpgrade(true, nil, b.CFrame.Position, b.Size), "no character")
	H.ok(Treadmill.promptDistance(b.Size) >= b.Size.Z / 2, "the prompts reach the ends of a 65% belt")
	H.ok(Treadmill.promptDistance(Vector3.new(8, 1, 40)) >= 20, "...and of a long one")
	b:Destroy()
	-- the server re-checks with it, and the client hides other players' prompts by OwnerUserId
	local plot = fs.readFile("src/server/PlotService.luau")
	H.ok(string.find(plot, "Treadmill.canUpgrade(state.owner == player", 1, true) ~= nil, "PlotService checks the owner")
	H.ok(string.find(plot, "beltPrompt:SetAttribute(\"OwnerUserId\", s.player.UserId)", 1, true) ~= nil, "prompts carry their owner")
end)

----------------------------------------------------------------------------------------------------
-- Saves
----------------------------------------------------------------------------------------------------
H.test("treadmill saves: v1-v4 tiers keep their multiplier (x2, Robux x3, Robux x5); v5 keeps the tier", function()
	H.eq(ProfileStore.VERSION, 5)
	for old, mult in { 2, 3, 5 } do
		for _, v in { 1, 2, 3, 4 } do
			local data = { v = v, money = 1, speed = 2, treadmillTier = old, plotLevel = 1, slots = 5, trails = { "Grey" }, trail = "Grey" }
			local p = ProfileStore.deserialize(serde.decode("json", serde.encode("json", data)))
			H.eq(Config.treadmillMult(p.treadmillTier), mult, `v{v} tier {old}`)
			-- saved again in v5, it loads as the same tier (no second migration)
			local back = ProfileStore.deserialize(serde.decode("json", serde.encode("json", ProfileStore.serialize(p))))
			H.eq(back.treadmillTier, p.treadmillTier, `v{v} tier {old} after a save`)
		end
	end
	H.eq(ProfileStore.deserialize({ v = 4, treadmillTier = 99 }).treadmillTier, ProfileStore.migrateTreadmillTier(3), "clamped to the old x5")
	H.eq(ProfileStore.deserialize({ v = 4, treadmillTier = "fast" }).treadmillTier, 1)
	H.eq(ProfileStore.deserialize({ treadmillTier = 3 }).treadmillTier, ProfileStore.migrateTreadmillTier(3), "no version = an old save")
	for tier = 1, Config.TREADMILL_MAX do
		H.eq(ProfileStore.deserialize({ v = 5, treadmillTier = tier }).treadmillTier, tier, `v5 tier {tier}`)
	end
	H.eq(ProfileStore.deserialize({ v = 5, treadmillTier = 99 }).treadmillTier, Config.TREADMILL_MAX, "clamped")
	H.eq(ProfileStore.deserialize({ v = 5, treadmillTier = -3 }).treadmillTier, 1, "clamped")
	H.eq(ProfileStore.defaultProfile().treadmillTier, 1, "new players start on the free x2")
end)

return nil
