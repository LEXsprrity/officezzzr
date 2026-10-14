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
	-- no toast about somebody else's treadmill (owner playtest): you just can't step on it
	for _, file in { "src/server/SpeedService.luau", "src/server/PlotService.luau", "src/client/Effects.client.luau", "src/client/HUD.client.luau" } do
		local text = fs.readFile(file)
		H.ok(string.find(text, "isn't your treadmill", 1, true) == nil, `{file} has no "isn't your treadmill" toast`)
	end
	H.ok(string.find(source, "Treadmill.blockBox(belt.CFrame, belt.Size)", 1, true) ~= nil and string.find(source, "CanCollide = true", 1, true) ~= nil,
		"Effects.client puts a solid invisible wall over the other belts")
	H.ok(string.find(source, "belt:GetAttribute(\"PlotIndex\") == myPlot", 1, true) ~= nil, "...but not over its own")
	H.ok(string.find(source, "AutoRotate = false", 1, true) ~= nil, "a locked runner isn't turned by the walking keys")
end)

H.test("treadmill wall: someone else's belt is walled off; a runner on it would be inside the wall", function()
	local b = belt(3, Vector3.new(-40, 1.5, 30))
	b.Size = Vector3.new(4.5, 1, 9)
	local cf, size = Treadmill.blockBox(b.CFrame, b.Size)
	local rel = b.CFrame:PointToObjectSpace(cf.Position)
	H.ok(math.abs(rel.X) < 1e-4 and math.abs(rel.Z) < 1e-4, "centred over the belt")
	H.ok(size.X >= b.Size.X and size.Z >= b.Size.Z, "covers its whole footprint")
	local bottom = rel.Y - size.Y / 2
	H.ok(bottom >= b.Size.Y / 2 and bottom <= b.Size.Y / 2 + 0.2, `starts just above the belt ({bottom})`)
	H.ok(size.Y >= 8, "too tall to jump onto")
	-- every spot the belt check counts as on the belt is inside the wall
	for _, x in { -2.2, 0, 2.2 } do
		for _, z in { -4.4, 0, 4.4 } do
			local pos = (b.CFrame * CFrame.new(x, b.Size.Y / 2 + 3, z)).Position
			H.ok(Treadmill.onBelt(b.CFrame, b.Size, pos), "on the belt")
			local p = cf:PointToObjectSpace(pos)
			H.ok(math.abs(p.X) < size.X / 2 and math.abs(p.Y) < size.Y / 2 and math.abs(p.Z) < size.Z / 2, `({x}, {z}) inside the wall`)
		end
	end
	b:Destroy()
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
	-- the server re-checks with it, and the client hides other players' prompts and buttons by OwnerUserId
	local plot = fs.readFile("src/server/PlotService.luau")
	H.ok(string.find(plot, "Treadmill.canUseBoard(state.owner == player", 1, true) ~= nil, "PlotService checks the owner")
	H.ok(string.find(plot, "setButtonsOwner(state, s.player.UserId)", 1, true) ~= nil, "prompts and buttons carry their owner")
	H.ok(string.find(plot, "setButtonsOwner(state, 0)", 1, true) ~= nil, "...and lose it when the owner leaves")
end)

H.test("board buttons: no black prompt popups; the painted $ and R$ buttons are clickable/tappable; E/F still work", function()
	local plot = fs.readFile("src/server/PlotService.luau")
	-- one helper builds both boards' buttons (the plot's Upgrade board and the treadmill's)
	H.ok(string.find(plot, "addBoardButtons(board, ", 1, true) ~= nil, "the plot's Upgrade board")
	H.ok(string.find(plot, "addBoardButtons(panel, state.treadmill.model, TREADMILL_PROMPTS", 1, true) ~= nil, "the treadmill's board")
	H.ok(string.find(plot, "prompt.Style = Enum.ProximityPromptStyle.Custom", 1, true) ~= nil, "prompts show no popup")
	H.ok(string.find(plot, "prompt.KeyboardKeyCode = spec.key", 1, true) ~= nil, "...but keep their E/F key")
	H.ok(string.find(plot, "Instance.new(\"ClickDetector\")", 1, true) ~= nil and string.find(plot, "click.MouseClick:Connect", 1, true) ~= nil,
		"a ClickDetector over each painted button (mouse and touch)")
	local _, uses = string.gsub(plot, "if canUse%(player%) then", "")
	H.eq(uses, 2, "both the prompt and the click are re-checked on the server (owner, distance)")
	H.eq(select(2, string.gsub(plot, "Enum%.ProximityPromptStyle%.Default", "")), 0, "no default-style prompt on the boards")
	-- only the owner's client can click them (others get reach 0), like the owner-only prompts
	local effects = fs.readFile("src/client/Effects.client.luau")
	H.ok(string.find(effects, "watchClick(inst)", 1, true) ~= nil and string.find(effects, "detector.MaxActivationDistance = if owner == player.UserId then reach else 0", 1, true) ~= nil,
		"Effects.client opens the buttons for the owner only")
	-- the hit areas sit over the painted buttons: red (money) on the panel's +X side, purple (Robux) on -X
	H.ok(string.find(plot, "Cash = { x = 0.158", 1, true) ~= nil and string.find(plot, "Robux = { x = -0.233", 1, true) ~= nil, "hit areas over the buttons")
	-- the mouse keeps the normal arrow over them (no pointing hand), and the painted button inflates instead
	H.ok(string.find(plot, "click.CursorIcon = BUTTON_CURSOR", 1, true) ~= nil
		and string.find(plot, "BUTTON_CURSOR = \"rbxasset://textures/Cursors/KeyboardMouse/ArrowFarCursor.png\"", 1, true) ~= nil, "the default arrow cursor")
	H.ok(string.find(plot, "painted.Value = panel:FindFirstChild(spec.object .. \"Button\", true)", 1, true) ~= nil, "each hit area knows its painted button")
	H.ok(string.find(effects, "MouseHoverEnter", 1, true) ~= nil and string.find(effects, "UiFx.worldPop(button, how)", 1, true) ~= nil,
		"Effects.client pops the painted button on hover")
end)

H.test("board buttons: the painted Cash/Robux buttons the hit areas point at exist on both boards", function()
	local TreadmillBoard = H.server("TreadmillBoard")
	local world = H.workspace:FindFirstChild("World")
	local plots = WorldBuilder.adopt(world)
	for i, plot in plots do
		local board = TreadmillBoard.build(plot.model, plot.belt, plot.center, plot.treadmillLabel)
		for _, panel in { board.panel, plot.upgradeBoard } do
			for _, name in { "CashButton", "RobuxButton" } do
				local b = panel:FindFirstChild(name, true)
				H.ok(b ~= nil and b:IsA("Frame"), `plot {i} {panel.Name} has {name}`)
			end
		end
	end
	-- UiFx.worldPop grows a button to the HUD's hover size and back, with the HUD's tweens
	local uiFx = fs.readFile("src/shared/UiFx.luau")
	H.ok(string.find(uiFx, "function UiFx.worldPop(", 1, true) ~= nil and string.find(uiFx, "sized(if how == \"hover\" then UiFx.HOVER else 1)", 1, true) ~= nil,
		"the shared world pop")
end)

H.test("floating titles: no name over the guards/bosses or the mother plants; status texts stay short-range", function()
	local guard = fs.readFile("src/server/GuardService.luau")
	H.ok(string.find(guard, "zone.guard, UDim2", 1, true) == nil, "no guard/boss name billboard (\"Giant Mole\")")
	H.ok(string.find(guard, "Vector3.new(0, statusY, 0), 100)", 1, true) ~= nil, "the Zzz/alert status stays, short-range")
	local builder = fs.readFile("src/server/WorldBuilder.luau")
	H.ok(string.find(builder, "Mother Plant`", 1, true) == nil, "no mother plant title in the code")
	local MapFile = require("../tools/map_tool")
	for _, which in { "built", "map" } do
		-- (loading the map file replaces the built World, so check the built one first)
		local world = if which == "built" then H.workspace:FindFirstChild("World") else MapFile.load(MapFile.PATH)
		for _, d in world:GetDescendants() do
			if d:IsA("TextLabel") then
				H.ok(string.find(d.Text, "Mother Plant", 1, true) == nil, `{d:GetFullName()} still says "{d.Text}"`)
				for _, zone in Config.ZONES do
					H.ok(d.Text ~= zone.guard, `{d:GetFullName()} shows the guard's name`)
				end
			end
		end
	end
	H.ok(string.find(fs.readFile("src/client/GuardAnimator.client.luau"), "gui.MaxDistance = 100", 1, true) ~= nil, "the boss's Zzz is short-range too")
end)

----------------------------------------------------------------------------------------------------
-- The Upgrade board and the "+X/s" text
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

-- Builds every plot's board in `plots` and checks where it stands: in line with its treadmill, in front of
-- its plot (between the front fence and the walkway, within the plot's width), clear of everything.
local function checkBoards(plots: { any }, label: string): { any }
	local boards = {}
	for i, plot in plots do
		local board = TreadmillBoard.build(plot.model, plot.belt, plot.center, plot.treadmillLabel)
		boards[i] = board
		H.ok(board.model.Parent == plot.model, `{label}: plot {i} board in its plot model`)
		local count = 0
		for _, child in plot.model:GetChildren() do
			count += if child.Name == "TreadmillBoard" then 1 else 0
		end
		H.eq(count, 1, `{label}: plot {i} has one treadmill board`)
		local lo, hi = box(board.model)
		local x0, x1, z0, z1 = Layout.frontStrip(plot, 0.5)
		H.ok(lo.X >= x0 and hi.X <= x1 and lo.Z >= z0 and hi.Z <= z1,
			`{label}: plot {i} board {lo}..{hi} in front of its plot, off the walkway and the neighbours' fronts`)
		local c = plot.center
		H.ok(lo.X > c.X + 7 or hi.X < c.X - 7, `{label}: plot {i} board off the entrance path`)
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
		-- nor in the beds, the owner's sign or the plot's own Upgrade board
		for b, bed in plot.beds do
			local dlo, dhi = Assets.bounds(bed)
			H.ok(not overlaps(lo, hi, Vector3.new(dlo.X, -1e9, dlo.Z), Vector3.new(dhi.X, 1e9, dhi.Z), 0), `{label}: plot {i} board clear of bed {b}`)
		end
		local ulo, uhi = Assets.bounds(plot.upgradeBoard)
		H.ok(not overlaps(lo, hi, Vector3.new(ulo.X, -1e9, ulo.Z), Vector3.new(uhi.X, 1e9, uhi.Z), 1), `{label}: plot {i} board clear of the plot's Upgrade board`)
		local slo, shi = Assets.bounds(plot.signLabel:FindFirstAncestorWhichIsA("BasePart"))
		H.ok(not overlaps(lo, hi, Vector3.new(slo.X, -1e9, slo.Z), Vector3.new(shi.X, 1e9, shi.Z), 1), `{label}: plot {i} board clear of the owner's sign`)
		-- it stands on the ground, faces the walkway, and is next to the treadmill
		H.ok(lo.Y >= plot.center.Y - 0.01 and lo.Y <= plot.center.Y + 2, `{label}: plot {i} board post on the ground ({lo.Y})`)
		local toBelt = (board.panel.CFrame.Position - bp)
		H.ok(Vector3.new(toBelt.X, 0, toBelt.Z).Magnitude < 14, `{label}: plot {i} board next to the treadmill`)
		local side = if c.Z > 0 then 1 else -1
		H.ok(board.panel.CFrame.LookVector.Z * -side > 0.99, `{label}: plot {i} board faces the walkway`)
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

H.test("treadmill board: one per plot on the generated map, next to its treadmill in front of the plot, clear of everything", function()
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

H.test("treadmill board: shows the tier, both prices and +X/s (the popups' number); MAX hides the buttons; empty plot shows nothing to buy", function()
	local world = H.workspace:FindFirstChild("World")
	local plots = WorldBuilder.adopt(world)
	local plot = plots[1]
	local board = TreadmillBoard.build(plot.model, plot.belt, plot.center, plot.treadmillLabel)

	TreadmillBoard.render(board, {})
	H.eq(board.labels.level.Text, "Empty plot")
	H.eq(board.labels.buttons.Visible, false, "no buttons on an empty plot")
	H.eq(board.stepGui.Enabled, false, "no step text on an empty plot")

	local p = profileAt(7)
	local perSecond = Treadmill.perSecond(Config.walkSpeedFor(p.speed), p.speed, p.equippedTrail, Config.treadmillMult(7))
	TreadmillBoard.render(board, { tier = 7, cash = Config.priceOf("TreadmillUpgrade", p), robux = 400, perSecond = perSecond })
	H.eq(board.labels.level.Text, "Level 7 > Level 8")
	H.eq(board.labels.buttons.Visible, true)
	H.ok(string.find(shown(board.labels.cash), Format.money(Config.TREADMILL_TIERS[8].price), 1, true) ~= nil, shown(board.labels.cash))
	H.ok(string.find(shown(board.labels.robux), "400", 1, true) ~= nil, shown(board.labels.robux))
	H.eq(board.stepGui.Enabled, true)
	H.eq(board.stepLabel.Text, Treadmill.gainText(perSecond) .. "/s")
	H.ok(board.stepGui.MaxDistance > 0 and board.stepGui.MaxDistance <= 40, `the "+X/s" text only shows up close ({board.stepGui.MaxDistance})`)

	-- a tier bought: the text follows
	TreadmillBoard.render(board, { tier = 8, cash = Config.TREADMILL_TIERS[9].price, robux = 640, perSecond = perSecond * 6 / 5 })
	H.eq(board.labels.level.Text, "Level 8 > Level 9")
	H.ok(string.find(shown(board.labels.cash), Format.money(Config.TREADMILL_TIERS[9].price), 1, true) ~= nil, shown(board.labels.cash))
	H.eq(board.stepLabel.Text, Treadmill.rateText(perSecond * 6 / 5))

	-- the last tier: MAX, no buttons, the step text stays
	TreadmillBoard.render(board, { tier = Config.TREADMILL_MAX, cash = nil, robux = nil, perSecond = perSecond })
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
	H.eq(Treadmill.perStep(0, nil, 2), Config.speedPerStud(nil) * 2)
	H.eq(Treadmill.perStep(5e6, "Blue", 2), Treadmill.perStep(0, "Blue", 2), "the same at any Speed (flat gain)")
	H.eq(Treadmill.perStep(5000, "Grey", 3), Config.speedPerStud("Grey") * 3)
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
	local mult = Config.speedPerStud(nil)
	H.ok(math.abs(SpeedLogic.treadmillGain(walk, 1, mult, 2.5) - Treadmill.perSecond(walk, speed, nil, 2.5)) < 1e-6, "same as the server's gain")
end)

H.test("treadmill sign: the '+X/s' over the treadmill is exactly what a second on it pays (the popups' number)", function()
	local SpeedLogic = H.server("SpeedLogic")
	local TreadmillBoard = H.server("TreadmillBoard")
	local world = H.workspace:FindFirstChild("World")
	local plot = WorldBuilder.adopt(world)[2]
	local board = TreadmillBoard.build(plot.model, plot.belt, plot.center, plot.treadmillLabel)
	local ticks = math.round(1 / Config.TICK)
	for _, speed in { 0, 250, 9e3, 4e5, 7e6, 3e8, 2e10 } do
		for _, trail in { "Grey", "Blue", "Red" } do
			for _, tier in { 1, 4, Config.TREADMILL_MAX } do
				-- the server: SpeedService's tick on the owner's belt, SpeedLogic.treadmillGain every TICK for a second
				local walk = Config.walkSpeedFor(speed)
				local tm = Config.treadmillMult(tier)
				local paid = 0
				for _ = 1, ticks do
					paid += SpeedLogic.treadmillGain(walk, Config.TICK, Config.speedPerStud(trail), tm)
				end
				-- the sign (PlotService) and the popups (Effects.client) both use Treadmill.perSecond with these stats
				local shown = Treadmill.perSecond(walk, speed, trail, tm)
				H.ok(math.abs(shown - paid) <= 1e-9 * math.max(1, paid), `speed {speed} {trail} tier {tier}: sign {shown} vs paid {paid}`)
				TreadmillBoard.render(board, { tier = tier, cash = 1, robux = 1, perSecond = shown })
				H.eq(board.stepLabel.Text, Treadmill.gainText(shown) .. "/s")
			end
		end
	end
	-- the playtest numbers: a "+60.9" popup, so the sign says "+60.9/s" (not the "+0.9/step" it used to)
	H.eq(Treadmill.rateText(60.94), "+60.9/s")
	-- the board and the popups read the same stats: the session's WalkSpeed (sent as walkSpeed), Speed, trail, tier
	local plotService = fs.readFile("src/server/PlotService.luau")
	H.ok(string.find(plotService, "perSecond = Treadmill.perSecond(s.walkSpeed, s.profile.speed, s.profile.equippedTrail, Sessions.treadmillMult(s))", 1, true) ~= nil,
		"PlotService writes the per-second gain")
	local effects = fs.readFile("src/client/Effects.client.luau")
	H.ok(string.find(effects, "Treadmill.perSecond(stats.walkSpeed, stats.speed, stats.equippedTrail, stats.treadmillMult)", 1, true) ~= nil,
		"the popups use the same function")
	local sessions = fs.readFile("src/server/Sessions.luau")
	H.ok(string.find(sessions, "walkSpeed = s.walkSpeed", 1, true) ~= nil, "the client gets the same WalkSpeed")
	H.ok(string.find(fs.readFile("src/server/SpeedService.luau"), "mult = Sessions.speedPerStud(s)", 1, true) ~= nil
		and string.find(sessions, "Config.speedPerStud(s.profile.equippedTrail)", 1, true) ~= nil, "the server pays Speed per stud from the same stats (the trail; flat at any Speed)")
end)

-- The treadmill's model (assets/Treadmill.rbxm) or the built-in frame, the belt, the lock and the board all
-- agree which way it faces: the runner faces the middle walkway, the console at that end.
local function checkFacing(plots: { any }, label: string)
	for i, plot in plots do
		local side = if plot.center.Z > 0 then 1 else -1
		local b = plot.belt
		local front = b.CFrame:VectorToWorldSpace(Vector3.new(0, 0, Treadmill.FRONT))
		H.ok(front.Z * -side > 0.999, `{label}: plot {i} belt's front toward the walkway ({front})`)
		local tm = plot.model:FindFirstChild("Treadmill")
		local head
		for _, d in tm:GetDescendants() do
			if d:IsA("BasePart") and (string.find(d.Name, "Console", 1, true) or d.Name == "TreadmillStop") then
				head = d
			end
		end
		H.ok(head ~= nil, `{label}: plot {i} treadmill has a console (or stop)`)
		local rel = b.CFrame:PointToObjectSpace(head.CFrame.Position)
		H.ok(rel.Z * Treadmill.FRONT > b.Size.Z / 4, `{label}: plot {i} {head.Name} at the front end ({rel})`)
		local held = Treadmill.lockCFrame(b.CFrame, b.Size, (b.CFrame * CFrame.new(1, 3, -2)).Position)
		H.ok(held.LookVector.Z * -side > 0.999, `{label}: plot {i} a locked runner faces the walkway and the console`)
		local board = TreadmillBoard.build(plot.model, b, plot.center, plot.treadmillLabel)
		local toBoard = b.CFrame:PointToObjectSpace(board.panel.CFrame.Position)
		H.ok(math.abs(toBoard.Z) < 1 and math.abs(toBoard.X) > b.Size.X / 2 + 2, `{label}: plot {i} board beside the treadmill ({toBoard})`)
		local fromPath = math.abs(board.panel.CFrame.Position.X - plot.center.X)
		H.ok(fromPath > math.abs(b.CFrame.Position.X - plot.center.X), `{label}: plot {i} board on the side away from the entrance path`)
		H.ok(board.panel.CFrame.LookVector:Dot(front) > 0.999, `{label}: plot {i} board faces the walkway, like the runner`)
	end
end

H.test("treadmill facing: the runner, the console and the board face the middle walkway (built and map/World.rbxm)", function()
	checkFacing(WorldBuilder.adopt(H.workspace:FindFirstChild("World")), "built")
	local world = MapTool.load(MapTool.PATH)
	local plots = WorldBuilder.adopt(world)
	Assets.refresh(world)
	checkFacing(plots, "map")
	-- the models' console is at their +Z end, so each tier's asset carries Yaw = 180 (its front is then -Z, as
	-- Assets expects)
	for tier = 1, Config.TREADMILL_MAX do
		local model = roblox.deserializeModel(fs.readFile(`assets/Treadmill_T{tier}.rbxm`))[1]
		H.eq(model:GetAttribute("Yaw"), 180, `assets/Treadmill_T{tier}.rbxm is turned to put its console at the front`)
	end
end)

----------------------------------------------------------------------------------------------------
-- One model per treadmill tier (assets/Treadmill_T1..T10, made by tools/export_treadmills.luau)
----------------------------------------------------------------------------------------------------
H.test("treadmill tiers: each tier has its model file (one Model, no code, tools or welds, anchored, non-colliding, a Belt and a console)", function()
	for tier = 1, Config.TREADMILL_MAX do
		local slot = Assets.treadmillSlot(tier)
		H.eq(slot, `Treadmill_T{tier}`)
		H.ok(table.find(Assets.SLOTS, slot) ~= nil, `{slot} is a slot`)
		local path = `assets/{slot}.rbxm`
		H.ok(fs.isFile(path), `{path} exists`)
		local roots = roblox.deserializeModel(fs.readFile(path))
		H.eq(#roots, 1, `{path} holds one instance`)
		local model = roots[1]
		H.ok(model:IsA("Model"), `{path} holds a Model`)
		H.eq(model:GetAttribute("KeepScale"), true, `{path} is saved at its game size`)
		H.eq(model:GetAttribute("Tier"), tier)
		local belts, consoles, parts = 0, 0, 0
		for _, d in model:GetDescendants() do
			H.ok(not (d:IsA("LuaSourceContainer") or d:IsA("Tool") or d:IsA("JointInstance") or d:IsA("WeldConstraint")
				or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") or d:IsA("BillboardGui")), `{path}: no {d.ClassName} ({d:GetFullName()})`)
			if d:IsA("BasePart") then
				parts += 1
				H.ok(d.Anchored and not d.CanCollide and not d.CanTouch, `{path}: {d.Name} anchored, no collision`)
				if d.Name == "Belt" then
					belts += 1
					H.eq(d.Transparency, 1, `{path}: the Belt marker is invisible`)
				elseif string.find(d.Name, "Console", 1, true) then
					consoles += 1
				end
			end
		end
		H.ok(parts > 3, `{path} has its parts`)
		H.eq(belts, 1, `{path} marks its running surface with one part named Belt`)
		H.ok(consoles >= 1, `{path} has its console`)
		-- the game (ServerStorage.Assets) loads it as that tier's model
		local template, matched = Assets.get(slot)
		H.ok(template ~= nil and template.Name == slot and matched == slot, `the game uses {path} for tier {tier}`)
	end
	-- the map's treadmill piece (the Studio view, an empty plot) looks like tier 1, and a tier without a model
	-- like the tier below it
	H.eq(select(2, Assets.get("Treadmill")), "Treadmill_T1", "no assets/Treadmill.rbxm: the map shows tier 1")
	local t5 = H.assets:FindFirstChild("Treadmill_T5")
	t5.Parent = nil
	local ok, err = pcall(function()
		H.eq(select(2, Assets.get("Treadmill_T5")), "Treadmill_T4", "a missing tier falls back to the one below")
	end)
	t5.Parent = H.assets
	H.ok(ok, tostring(err))
	H.eq(Assets.treadmillSlot(0), "Treadmill_T1", "a bad tier is clamped")
	H.eq(Assets.treadmillSlot(99), `Treadmill_T{Config.TREADMILL_MAX}`)
end)

H.test("treadmill tiers: the treadmill swaps to each tier in place; belt, lock, +X/s text and board follow every tier", function()
	local world = H.workspace:FindFirstChild("World")
	local plots = WorldBuilder.adopt(world)
	Assets.refresh(world)
	local pivots = {}
	for i, plot in plots do
		local tm = plot.model:FindFirstChild("Treadmill")
		H.eq(tm:GetAttribute("Asset"), "Treadmill_T1", `plot {i} starts on tier 1`)
		pivots[i] = Assets.pivotOf(tm)
	end
	local order = {}
	for tier = 1, Config.TREADMILL_MAX do
		table.insert(order, tier)
	end
	table.insert(order, 1) -- and back to tier 1 (the owner left: an empty plot)
	for step, tier in order do
		local slot = Assets.treadmillSlot(tier)
		for i, plot in plots do
			local board = TreadmillBoard.build(plot.model, plot.belt, plot.center, plot.treadmillLabel)
			H.eq(TreadmillBoard.showTier(board, tier), step > 1, `plot {i} tier {tier}: swapped only when the tier changed`)
			H.eq(TreadmillBoard.showTier(board, tier), false, "the same tier again does nothing")
			local count = 0
			for _, child in plot.model:GetChildren() do
				count += if child.Name == "Treadmill" then 1 else 0
			end
			H.eq(count, 1, `plot {i} tier {tier}: one treadmill`)
			local tm = plot.model:FindFirstChild("Treadmill")
			H.eq(tm:GetAttribute("Asset"), slot, `plot {i} shows tier {tier}`)
			H.eq(tm:GetAttribute("AssetSlot"), "Treadmill", "it stays the map's treadmill piece")
			H.ok((Assets.pivotOf(tm).Position - pivots[i].Position).Magnitude < 1e-3, `plot {i} tier {tier}: in the same spot`)
			-- the hidden belt is the model's Belt: same footprint, its top at the Belt's top
			local b = plot.belt
			local lo, hi = Assets.bounds(tm:FindFirstChild("Belt", true), b.CFrame, true)
			local h = b.Size / 2
			H.ok(math.abs(lo.X + h.X) < 0.01 and math.abs(hi.X - h.X) < 0.01 and math.abs(lo.Z + h.Z) < 0.01 and math.abs(hi.Z - h.Z) < 0.01
				and math.abs(hi.Y - h.Y) < 0.01, `plot {i} tier {tier}: the belt fits under the model's belt ({lo}..{hi}, belt {b.Size})`)
			H.eq(b.Transparency, 1, "the belt is hidden under the model")
			H.ok(math.min(b.Size.X, b.Size.Z) >= 4 and math.min(b.Size.X, b.Size.Z) <= 5 and math.max(b.Size.X, b.Size.Z) >= 6.5
				and math.max(b.Size.X, b.Size.Z) <= 10.5, `plot {i} tier {tier}: a character-sized belt ({b.Size})`)
			H.ok(b.Size.Z >= b.Size.X, "it still runs along its own Z (front end +Z)")
			-- the board and the step text followed the belt
			H.ok((board.panel.CFrame.Position - TreadmillBoard.placement(plot.model, b, plot.center).Position).Magnitude < 1e-3,
				`plot {i} tier {tier}: the board followed`)
			H.ok((board.stepGui.Adornee.Position - Treadmill.stepTextOffset(b.Size)).Magnitude < 1e-3, `plot {i} tier {tier}: the step text followed`)
		end
		-- every tier stands in the treadmill strip, faces the walkway, and leaves room for its board
		Layout.treadmillsFit(plots, `tier {tier}`)
		checkFacing(plots, `tier {tier}`)
		checkBoards(plots, `tier {tier}`)
		Layout.postsClearOfProps(world, plots, `tier {tier}`)
	end
end)

H.test("treadmill tiers: PlotService shows the owner's tier (an empty plot tier 1) whenever it writes the board", function()
	local plot = fs.readFile("src/server/PlotService.luau")
	local render = string.match(plot, "local function renderTreadmillSign.-\nend")
	H.ok(render ~= nil, "renderTreadmillSign")
	H.ok(string.find(render, "TreadmillBoard.showTier(state.treadmill, if s then s.profile.treadmillTier else 1)", 1, true) ~= nil,
		"renderTreadmillSign swaps the model (after an upgrade, a Robux receipt, an owner arriving or leaving)")
	for _, fn in { "function PlotService.upgradeTreadmill", "function PlotService.refreshTreadmill", "function PlotService.assign", "function PlotService.release" } do
		local body = string.match(plot, fn .. ".-\nend")
		H.ok(body ~= nil and string.find(body, "renderTreadmillSign(state)", 1, true) ~= nil, `{fn} re-renders the treadmill`)
	end
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

H.test("treadmill lock: held at the CENTRE of the belt (wherever you stepped on), facing its front; a jump lands just beside it", function()
	local b = belt(1, Vector3.new(40, 1.5, -20))
	b.Size = Vector3.new(4.5, 1, 9) -- the map's character-sized belt
	local walk = Config.walkSpeedFor(0)
	local SpeedLogic = H.server("SpeedLogic")
	local held
	-- stepping on at either end, either edge or the middle: always held at the same spot, the belt's centre
	for _, contact in { Vector3.new(1.8, 3.5, -4.3), Vector3.new(-2.1, 3.5, 4.4), Vector3.new(0, 3.5, 0), Vector3.new(2.2, 3.5, 3.9) } do
		local onIt = (b.CFrame * CFrame.new(contact)).Position
		held = Treadmill.lockCFrame(b.CFrame, b.Size, onIt)
		local rel = b.CFrame:PointToObjectSpace(held.Position)
		H.ok(math.abs(rel.X) < 1e-4 and math.abs(rel.Z) < 1e-4, `centred on the belt from {contact} ({rel})`)
		H.ok(math.abs(rel.Y - 3.5) < 1e-4, "at its own height")
		H.ok(Treadmill.onBelt(b.CFrame, b.Size, held.Position), "still on the belt")
		local front = b.CFrame:VectorToWorldSpace(Vector3.new(0, 0, Treadmill.FRONT))
		H.ok(held.LookVector:Dot(front) > 0.999, "facing the front")
		H.ok((held.Position - onIt).Magnitude <= SpeedLogic.allowedPerTick(walk, Config.TICK), "a small nudge, inside the movement check")
	end
	local rel = b.CFrame:PointToObjectSpace(held.Position)

	local out = Treadmill.exitPosition(b.CFrame, b.Size, held.Position, b.CFrame.Position + b.CFrame.RightVector * -30)
	local orel = b.CFrame:PointToObjectSpace(out)
	H.ok(not Treadmill.onBelt(b.CFrame, b.Size, out), "off the belt")
	H.ok(orel.X < 0 and math.abs(orel.X) >= b.Size.X / 2 + 2, "past the rails, toward the plot's middle")
	H.ok(math.abs(orel.Z - rel.Z) < 1e-4, "beside where it ran")
	H.ok((out - held.Position).Magnitude <= SpeedLogic.allowedPerTick(walk, Config.TICK), "within one tick of the movement check")
	H.ok(Treadmill.exitPosition(b.CFrame, b.Size, held.Position, nil) ~= nil, "no plot centre yet: still leaves")
	-- Effects.client holds the character with this (not where it touched the belt)
	local effects = fs.readFile("src/client/Effects.client.luau")
	H.ok(string.find(effects, "Treadmill.lockCFrame(belt.CFrame, belt.Size, root.Position)", 1, true) ~= nil, "Effects.client uses the shared lock spot")
	b:Destroy()
end)

----------------------------------------------------------------------------------------------------
-- Saves
----------------------------------------------------------------------------------------------------
H.test("treadmill saves: v1-v4 tiers keep their multiplier (x2, Robux x3, Robux x5); v5+ keeps the tier", function()
	H.ok(ProfileStore.VERSION >= 6)
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
