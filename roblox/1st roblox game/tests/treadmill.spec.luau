-- The treadmill: only your own plot's belt plays the run-in-place animation (Shared/Treadmill, used by
-- Effects.client), the 10 tiers (money price and Robux price tiers TreadmillT1..T3), money purchases and
-- receipts that grant exactly one tier, the owner-only prompt check, and old saves (3 tiers) loading.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local H = require("./harness")

local Config = H.shared("Config")
local Treadmill = H.shared("Treadmill")
local Format = H.shared("Format")
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

H.test("treadmill: the run animation plays only on your own belt, alive", function()
	H.eq(Treadmill.shouldRun("own", true), true, "locked on your treadmill")
	H.eq(Treadmill.shouldRun("own", false), false, "dead")
	H.eq(Treadmill.shouldRun("other", true), false, "someone else's treadmill: the playtest bug")
	H.eq(Treadmill.shouldRun(nil, true), false, "not on a belt")
	H.ok(Treadmill.RUN_ANIM_SPEED >= 2.5 and Treadmill.RUN_ANIM_SPEED <= 3, "a sprint, not a jog")
end)

H.test("treadmill: Effects.client locks, sprints and pops Speed with the shared rules, on its own plot", function()
	local source = fs.readFile("src/client/Effects.client.luau")
	H.ok(string.find(source, "Treadmill.shouldRun(", 1, true) ~= nil, "uses the shared rule")
	H.ok(string.find(source, "Treadmill.beltAt(", 1, true) ~= nil and string.find(source, "plot == myPlot", 1, true) ~= nil, "only its own plot's belt")
	H.ok(string.find(source, "Treadmill.stepLock(", 1, true) ~= nil, "the shared lock")
	H.ok(string.find(source, "JumpRequest", 1, true) ~= nil, "jumping (Space or the mobile button) leaves")
	H.ok(string.find(source, "AdjustSpeed(Treadmill.RUN_ANIM_SPEED)", 1, true) ~= nil, "the sprint")
	H.ok(string.find(source, "Treadmill.perSecond(", 1, true) ~= nil and string.find(source, "Icons.set(label, \"Speed\"", 1, true) ~= nil,
		"the Speed popups, with the Speed icon")
	H.ok(string.find(source, "CharacterAdded", 1, true) ~= nil, "a respawn resets the lock")
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

H.test("treadmill prompts: only the plot's owner, standing near the board, can buy", function()
	local board = Vector3.new(10, 4, 20)
	local near = board + Vector3.new(0, -1, Treadmill.BOARD_PROMPT_DISTANCE)
	H.ok(Treadmill.canUseBoard(true, near, board), "the owner at the prompt's range")
	H.ok(not Treadmill.canUseBoard(false, near, board), "not the owner: rejected")
	H.ok(not Treadmill.canUseBoard(true, board + Vector3.new(60, 0, 0), board), "too far away")
	H.ok(not Treadmill.canUseBoard(true, nil, board), "no character")
	-- the server re-checks with it, and the client hides other players' prompts by OwnerUserId
	local plot = fs.readFile("src/server/PlotService.luau")
	H.ok(string.find(plot, "Treadmill.canUseBoard(state.owner == player", 1, true) ~= nil, "PlotService checks the owner")
	H.ok(string.find(plot, "beltPrompt:SetAttribute(\"OwnerUserId\", s.player.UserId)", 1, true) ~= nil, "prompts carry their owner")
end)

----------------------------------------------------------------------------------------------------
-- The Upgrade board and the "+X/step" text
----------------------------------------------------------------------------------------------------
local TreadmillBoard = H.server("TreadmillBoard")
local Assets = H.server("Assets")
local Layout = require("./plot_layout")
local MapTool = require("../tools/map_tool")

-- The footprint of `root` (BaseParts with Transparency < 1) as an axis-aligned box.
local function box(root: any): (any, any)
	return Assets.bounds(root)
end

local function overlaps(alo: any, ahi: any, blo: any, bhi: any, pad: number): boolean
	return alo.X < bhi.X + pad and ahi.X > blo.X - pad and alo.Z < bhi.Z + pad and ahi.Z > blo.Z - pad
		and alo.Y < bhi.Y and ahi.Y > blo.Y
end

-- Builds every plot's board in `plots` and checks where it stands.
local function checkBoards(plots: { any }, label: string): { any }
	local half = Config.PLOT_SIZE / 2
	local boards = {}
	for i, plot in plots do
		local board = TreadmillBoard.build(plot.model, plot.belt, plot.center, plot.treadmillLabel)
		boards[i] = board
		H.ok(board.model.Parent == plot.model, `{label}: plot {i} board in its plot`)
		local count = 0
		for _, child in plot.model:GetChildren() do
			count += if child.Name == "TreadmillBoard" then 1 else 0
		end
		H.eq(count, 1, `{label}: plot {i} has one treadmill board`)
		local lo, hi = box(board.model)
		local c = plot.center
		H.ok(lo.X >= c.X - half + 1 and hi.X <= c.X + half - 1 and lo.Z >= c.Z - half + 1 and hi.Z <= c.Z + half - 1,
			`{label}: plot {i} board {lo}..{hi} inside its plot, clear of the fence`)
		-- not on the belt, nor in the treadmill (its model or frame)
		local bp, bh = plot.belt.CFrame.Position, plot.belt.Size / 2
		local blo, bhi = Assets.bounds(plot.belt)
		if not blo then -- the belt is see-through under a Treadmill model: its own box
			local cf, h = plot.belt.CFrame, plot.belt.Size / 2
			local ex = math.abs(cf.RightVector.X) * h.X + math.abs(cf.LookVector.X) * h.Z
			local ez = math.abs(cf.RightVector.Z) * h.X + math.abs(cf.LookVector.Z) * h.Z
			blo, bhi = bp - Vector3.new(ex, h.Y, ez), bp + Vector3.new(ex, h.Y, ez)
		end
		H.ok(not overlaps(lo, hi, Vector3.new(blo.X, -1e9, blo.Z), Vector3.new(bhi.X, 1e9, bhi.Z), 0.5), `{label}: plot {i} board clear of the belt`)
		local tm = plot.model:FindFirstChild("Treadmill")
		if tm then
			local tlo, thi = Assets.bounds(tm)
			H.ok(not overlaps(lo, hi, Vector3.new(tlo.X, -1e9, tlo.Z), Vector3.new(thi.X, 1e9, thi.Z), 0.2), `{label}: plot {i} board clear of the treadmill model {tlo}..{thi}`)
		end
		-- nor in the plant rows, the pad or the plot's own Upgrade board
		for s, cf in plot.slotCFrames do
			local p = cf.Position
			local reach = Config.SLOT_SPACING / 2
			H.ok(not overlaps(lo, hi, p - Vector3.new(reach, 1e9, reach), p + Vector3.new(reach, 1e9, reach), 0), `{label}: plot {i} board clear of slot {s}`)
		end
		local plo, phi = Assets.bounds(plot.pad)
		H.ok(not overlaps(lo, hi, Vector3.new(plo.X, -1e9, plo.Z), Vector3.new(phi.X, 1e9, phi.Z), 1), `{label}: plot {i} board clear of the pad`)
		local ulo, uhi = Assets.bounds(plot.upgradeBoard)
		H.ok(not overlaps(lo, hi, Vector3.new(ulo.X, -1e9, ulo.Z), Vector3.new(uhi.X, 1e9, uhi.Z), 1), `{label}: plot {i} board clear of the plot's Upgrade board`)
		-- it stands on the ground, faces the plot's middle side, and is close enough to the belt to read
		H.ok(lo.Y >= plot.center.Y and lo.Y <= plot.center.Y + 2, `{label}: plot {i} board post on the ground ({lo.Y})`)
		local toBelt = (board.panel.CFrame.Position - bp)
		H.ok(Vector3.new(toBelt.X, 0, toBelt.Z).Magnitude < 14, `{label}: plot {i} board beside the treadmill`)
		local toMiddle = Vector3.new(plot.center.X - board.panel.CFrame.Position.X, 0, plot.center.Z - board.panel.CFrame.Position.Z)
		H.ok(board.panel.CFrame.LookVector:Dot(toMiddle) > 0, `{label}: plot {i} board faces into the plot`)
		-- the old "TREADMILL" billboard is off; the step text floats over the belt's front end
		local old = plot.treadmillLabel:FindFirstAncestorWhichIsA("BillboardGui")
		H.ok(old == nil or old.Enabled == false, `{label}: plot {i} "TREADMILL" billboard hidden`)
		local anchor = board.stepGui.Adornee
		H.ok(anchor.Parent == plot.belt, `{label}: plot {i} step text rides on the belt`)
		local rel = anchor.Position
		H.ok(rel.Z * Treadmill.FRONT > plot.belt.Size.Z / 2 - 3 and math.abs(rel.X) < 0.01 and rel.Y > plot.belt.Size.Y / 2 + 3,
			`{label}: plot {i} step text over the front end ({rel})`)
		H.ok(board.panel:FindFirstChildWhichIsA("SurfaceGui") ~= nil, `{label}: plot {i} board has its SurfaceGui`)
	end
	return boards
end

H.test("treadmill board: one per plot on the generated map, beside the treadmill and clear of everything", function()
	local world = H.workspace:FindFirstChild("World")
	H.ok(world ~= nil, "world.spec built the map")
	local plots = WorldBuilder.adopt(world)
	H.ok(plots ~= nil, "the built map adopts")
	checkBoards(plots, "built")
end)

H.test("treadmill board: one per plot on map/World.rbxm too", function()
	local world = MapTool.load(MapTool.PATH)
	local plots, _, problems = WorldBuilder.adopt(world)
	H.ok(plots ~= nil, table.concat(problems or {}, "; "))
	Assets.refresh(world)
	checkBoards(plots, "map")
	Layout.postsClearOfProps(world, plots, "map with boards")
end)

H.test("treadmill board: follows the belt when the map moves it", function()
	local world = H.workspace:FindFirstChild("World")
	local plots = WorldBuilder.adopt(world)
	local plot = plots[3]
	local board = TreadmillBoard.build(plot.model, plot.belt, plot.center, plot.treadmillLabel)
	local before = board.panel.CFrame.Position
	plot.belt.CFrame = plot.belt.CFrame * CFrame.new(-4, 0, 0)
	TreadmillBoard.follow(board) -- PlotService calls it when the belt's CFrame or Size changes
	local after = board.panel.CFrame.Position
	H.ok((after - before).Magnitude > 1, "the board moved with the belt")
	H.ok((after - TreadmillBoard.placement(plot.model, plot.belt, plot.center).Position).Magnitude < 1e-3, "to its new place")
	plot.belt.CFrame = plot.belt.CFrame * CFrame.new(4, 0, 0)
	TreadmillBoard.follow(board)
	H.ok((board.panel.CFrame.Position - before).Magnitude < 1e-3, "and back")
end)

-- The texts a board shows, skipping the IconRow pieces Icons.set may add (no icon is uploaded in tests' ids
-- unless icons/ids.json has them, so read the label or its IconRow's text).
local function shown(label: any): string
	local row = label:FindFirstChild("IconRow")
	if not row then
		return label.Text
	end
	local parts = {}
	for _, d in row:GetChildren() do
		if d:IsA("TextLabel") then
			table.insert(parts, d.Text)
		end
	end
	return table.concat(parts, " ")
end

H.test("treadmill board: shows the tier, both prices and +X/step; MAX hides the buttons; empty plot shows nothing to buy", function()
	local world = H.workspace:FindFirstChild("World")
	local plots = WorldBuilder.adopt(world)
	local plot = plots[1]
	local board = TreadmillBoard.build(plot.model, plot.belt, plot.center, plot.treadmillLabel)

	TreadmillBoard.render(board, {})
	H.eq(board.labels.level.Text, "Empty plot")
	H.eq(board.labels.buttons.Visible, false, "no buttons on an empty plot")
	H.eq(board.stepGui.Enabled, false, "no step text on an empty plot")

	local p = profileAt(7)
	local perStep = Treadmill.perStep(p.speed, p.equippedTrail, Config.treadmillMult(7))
	TreadmillBoard.render(board, { tier = 7, cash = Config.priceOf("TreadmillUpgrade", p), robux = 400, perStep = perStep })
	H.eq(board.labels.level.Text, "Level 7 > Level 8")
	H.eq(board.labels.buttons.Visible, true)
	H.ok(string.find(shown(board.labels.cash), Format.money(Config.TREADMILL_TIERS[8].price), 1, true) ~= nil, shown(board.labels.cash))
	H.ok(string.find(shown(board.labels.robux), "400", 1, true) ~= nil, shown(board.labels.robux))
	H.eq(board.stepGui.Enabled, true)
	H.eq(board.stepLabel.Text, Treadmill.gainText(perStep) .. "/step")

	-- a tier bought: the text follows
	TreadmillBoard.render(board, { tier = 8, cash = Config.TREADMILL_TIERS[9].price, robux = 640, perStep = perStep * 6 / 5 })
	H.eq(board.labels.level.Text, "Level 8 > Level 9")
	H.ok(string.find(shown(board.labels.cash), Format.money(Config.TREADMILL_TIERS[9].price), 1, true) ~= nil, shown(board.labels.cash))
	H.eq(board.stepLabel.Text, Treadmill.gainText(perStep * 6 / 5) .. "/step")

	-- the last tier: MAX, no buttons, the step text stays
	TreadmillBoard.render(board, { tier = Config.TREADMILL_MAX, cash = nil, robux = nil, perStep = perStep })
	H.eq(board.labels.level.Text, "MAX")
	H.eq(board.labels.buttons.Visible, false, "no buttons at the last tier")
	H.eq(shown(board.labels.cash), "")
	H.eq(board.stepGui.Enabled, true)

	-- nothing on the board or over the belt says "TREADMILL" in big letters any more
	for _, d in plot.model:GetDescendants() do
		if d:IsA("TextLabel") and string.find(string.upper(d.Text), "TREADMILL", 1, true) then
			local gui = d:FindFirstAncestorWhichIsA("LayerCollector")
			H.ok(gui ~= nil and gui.Enabled == false, `{d:GetFullName()} still shows "{d.Text}"`)
		end
	end
end)

H.test("treadmill board: PlotService builds it per plot, writes it and puts the prompts on it", function()
	local plot = fs.readFile("src/server/PlotService.luau")
	H.ok(string.find(plot, "TreadmillBoard.build(info.model, info.belt, info.center, info.treadmillLabel)", 1, true) ~= nil, "built per plot")
	H.ok(string.find(plot, "TreadmillBoard.render(state.treadmill", 1, true) ~= nil, "written")
	H.ok(string.find(plot, "state.treadmill.panel", 1, true) ~= nil, "the prompts are on the board")
	H.ok(string.find(plot, "Icons.set(state.info.treadmillLabel", 1, true) == nil, "the old sign isn't written any more")
end)

H.test("treadmill step: what one step pays, as text", function()
	H.eq(Treadmill.perStep(0, nil, 2), Config.speedPerStud(0, nil) * 2)
	H.eq(Treadmill.perStep(5000, "Grey", 3), Config.speedPerStud(5000, "Grey") * 3)
	H.eq(Treadmill.perSecond(20, 5000, nil, 3), 20 * Treadmill.perStep(5000, nil, 3))
	H.eq(Treadmill.perSecond(1e6, 5000, nil, 3), Config.GAIN_CAP_STUDS_PER_TICK / Config.TICK * Treadmill.perStep(5000, nil, 3), "capped like SpeedLogic")
	H.eq(Treadmill.gainText(0.5), "+0.5")
	H.eq(Treadmill.gainText(12.34), "+12.3")
	H.eq(Treadmill.gainText(200), "+200")
	H.eq(Treadmill.gainText(1600), "+1.6K")
	-- the text floats near the front end, above head height
	local off = Treadmill.stepTextOffset(Vector3.new(5.2, 1, 18))
	H.ok(off.Z * Treadmill.FRONT >= 6 and off.Y >= 6, `{off}`)
	local wide = Treadmill.stepTextOffset(Vector3.new(18, 1, 5.2))
	H.ok(wide.X * Treadmill.FRONT >= 6 and wide.Z == 0, `a belt turned in its own axes: {wide}`)
	-- the front is where WorldBuilder puts the stop
	local world = H.workspace:FindFirstChild("World")
	local plots = WorldBuilder.adopt(world)
	for i, plot in plots do
		local stop
		for _, d in plot.model:GetDescendants() do
			if d.Name == "TreadmillStop" then
				stop = d
			end
		end
		if stop then
			local rel = plot.belt.CFrame:PointToObjectSpace(stop.CFrame.Position)
			H.ok(rel.Z * Treadmill.FRONT > 0, `plot {i}: the stop is at the front end ({rel})`)
		end
	end
	-- and the treadmill sums match SpeedLogic's treadmill gain for a whole second
	local SpeedLogic = H.server("SpeedLogic")
	local walk, speed = 24, 1e5
	local mult = Config.speedPerStud(speed, nil)
	H.ok(math.abs(SpeedLogic.treadmillGain(walk, 1, mult, 2.5) - Treadmill.perSecond(walk, speed, nil, 2.5)) < 1e-6, "same as the server's gain")
end)

----------------------------------------------------------------------------------------------------
-- The lock: on your own belt you stay on it until you jump
----------------------------------------------------------------------------------------------------
local function lockInput(now: number, onOwnBelt: boolean, alive: boolean?, jumped: boolean?): any
	return { now = now, onOwnBelt = onOwnBelt, alive = alive ~= false, jumped = jumped == true }
end

H.test("treadmill lock: stepping on your own belt locks; only a jump leaves, then a cooldown", function()
	local s = Treadmill.newLock()
	H.eq(s.mode, "free")
	H.eq(Treadmill.stepLock(s, lockInput(0, false)), nil, "off the belt: nothing")
	H.eq(Treadmill.stepLock(s, lockInput(0, false, true, true)), nil, "jumping off the belt: nothing")
	H.eq(Treadmill.stepLock(s, lockInput(1, true)), "lock", "stepped on")
	H.eq(s.mode, "locked")
	for t = 1, 20 do
		H.eq(Treadmill.stepLock(s, lockInput(1 + t, true)), nil, "stays locked (walking keys do nothing)")
	end
	H.eq(Treadmill.stepLock(s, lockInput(30, true, true, true)), "exit", "a jump leaves")
	H.eq(s.mode, "cooldown")
	-- still standing on it (the push failed) or walking straight back: no re-lock during the cooldown
	H.eq(Treadmill.stepLock(s, lockInput(30.1, true)), nil)
	H.eq(Treadmill.stepLock(s, lockInput(30 + Treadmill.LOCK_COOLDOWN - 0.01, true)), nil, "still cooling down")
	H.eq(s.mode, "cooldown")
	H.eq(Treadmill.stepLock(s, lockInput(30 + Treadmill.LOCK_COOLDOWN, true)), "lock", "after the cooldown it locks again")
	-- after a cooldown spent off the belt: free, and nothing to do
	Treadmill.stepLock(s, lockInput(40, true, true, true))
	H.eq(Treadmill.stepLock(s, lockInput(40 + Treadmill.LOCK_COOLDOWN + 1, false)), nil)
	H.eq(s.mode, "free")
	H.ok(Treadmill.LOCK_COOLDOWN >= 0.5 and Treadmill.LOCK_COOLDOWN <= 3, "a short cooldown")
end)

H.test("treadmill lock: death, a respawn or a teleport off the belt just unlocks (no cooldown)", function()
	local s = Treadmill.newLock()
	Treadmill.stepLock(s, lockInput(0, true))
	H.eq(Treadmill.stepLock(s, lockInput(1, true, false)), "unlock", "died")
	H.eq(s.mode, "free")
	H.eq(Treadmill.stepLock(s, lockInput(1.1, true, false)), nil, "dead: never locks")
	Treadmill.stepLock(s, lockInput(2, true))
	H.eq(Treadmill.stepLock(s, lockInput(3, false)), "unlock", "the server moved us off the belt")
	H.eq(Treadmill.stepLock(s, lockInput(3.1, true)), "lock", "no cooldown after a plain unlock")
	H.eq(Treadmill.stepLock(s, lockInput(4, false, false, true)), "unlock", "dying wins over a jump")
	-- a respawn starts over (Effects makes a new lock on CharacterAdded)
	H.eq(Treadmill.newLock().mode, "free")
end)

H.test("treadmill lock: held centred on the belt facing its front; a jump lands just beside it", function()
	local b = belt(1, Vector3.new(40, 1.5, -20))
	local onIt = (b.CFrame * CFrame.new(1.8, 3.5, -8.5)).Position
	local held = Treadmill.lockCFrame(b.CFrame, b.Size, onIt)
	local rel = b.CFrame:PointToObjectSpace(held.Position)
	H.ok(math.abs(rel.X) < 1e-4, "centred across the belt")
	H.ok(math.abs(rel.Y - 3.5) < 1e-4, "at its own height")
	H.ok(math.abs(rel.Z) <= b.Size.Z / 2 - 2.4, "kept off the end")
	H.ok(Treadmill.onBelt(b.CFrame, b.Size, held.Position), "still on the belt")
	local front = b.CFrame:VectorToWorldSpace(Vector3.new(0, 0, Treadmill.FRONT))
	H.ok(held.LookVector:Dot(front) > 0.999, "facing the front")
	H.ok((held.Position - onIt).Magnitude <= Config.MOVE_EPSILON + 2, "a small nudge, well inside the movement check")

	local out = Treadmill.exitPosition(b.CFrame, b.Size, held.Position, b.CFrame.Position + b.CFrame.RightVector * -30)
	local orel = b.CFrame:PointToObjectSpace(out)
	H.ok(not Treadmill.onBelt(b.CFrame, b.Size, out), "off the belt")
	H.ok(orel.X < 0 and math.abs(orel.X) >= b.Size.X / 2 + 2, "past the rails, toward the plot's middle")
	H.ok(math.abs(orel.Z - rel.Z) < 1e-4, "beside where it ran")
	local walk = Config.walkSpeedFor(0)
	H.ok((out - held.Position).Magnitude <= H.server("SpeedLogic").allowedPerTick(walk, Config.TICK), "within one tick of the movement check")
	H.ok(Treadmill.exitPosition(b.CFrame, b.Size, held.Position, nil) ~= nil, "no plot centre yet: still leaves")
	b:Destroy()
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
