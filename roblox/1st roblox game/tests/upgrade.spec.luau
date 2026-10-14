-- The Upgrade board at each plot's gate: the Robux price tiers (developer products have fixed prices, so
-- the 25 upgrades are split into PlotUpgradeT1..T6), the prompt gate, receipts that grant exactly one
-- level once (or money at the last level), and what the board shows.
local serde = require("@lune/serde")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Enum = roblox.Enum
local H = require("./harness")
local MapTool = require("../tools/map_tool")

local Config = H.shared("Config")
local Format = H.shared("Format")
local Icons = H.shared("Icons")
local Shop = H.server("Shop")
local ProfileStore = H.server("ProfileStore")
local WorldBuilder = H.server("WorldBuilder")

local function never(): number
	error("a plot upgrade must not roll")
end

local function yes(): boolean
	return true
end

local TIER_IDS = { PlotUpgradeT1 = 801, PlotUpgradeT2 = 802, PlotUpgradeT3 = 803, PlotUpgradeT4 = 804, PlotUpgradeT5 = 805, PlotUpgradeT6 = 806 }

-- Runs fn with the tier products' ids set (as if pasted from the Creator Dashboard), then puts the stubs back.
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

local function profileAt(level: number)
	local p = ProfileStore.defaultProfile()
	p.plotLevel = level
	return p
end

----------------------------------------------------------------------------------------------------
-- Tiers
----------------------------------------------------------------------------------------------------
H.test("upgrade tiers: six id = 0 PlotUpgrade products whose placeholder price rises with the level", function()
	local list = Config.products("PlotUpgrade")
	H.eq(#list, Config.PLOT_UPGRADE_TIERS)
	local prices = {}
	for i, e in list do
		H.eq(e.name, `PlotUpgradeT{i}`, "cheapest first = tier order")
		H.eq(e.product.tier, i)
		H.eq(e.product.id, 0, e.name .. " ships as a stub")
		table.insert(prices, e.product.robux)
	end
	H.eq(table.concat(prices, " "), "25 49 99 199 399 799")
end)

H.test("upgrade tiers: the tier comes from the plot's level, spread over the 25 upgrades", function()
	-- level now -> tier of the next level: 1-4 T1, 5-8 T2, 9-12 T3, 13-16 T4, 17-20 T5, 21-25 T6, 26 none
	local want = { 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6, 6 }
	H.eq(#want, Config.PLOT_LEVEL_MAX - 1, "one entry per upgrade")
	local covered = {}
	for level = 1, Config.PLOT_LEVEL_MAX - 1 do
		local tier = Config.plotUpgradeTier(level)
		H.eq(tier, want[level], `level {level}`)
		local name, product = Config.plotUpgradeProduct(level)
		H.eq(name, `PlotUpgradeT{tier}`)
		H.eq(product, Config.DEVELOPER_PRODUCTS[name])
		-- the Dashboard name says which levels it buys ("Plot Upgrade (Lv 2-5)")
		local lo, hi = string.match(product.label, "Lv (%d+)%-(%d+)")
		H.ok(level + 1 >= tonumber(lo) and level + 1 <= tonumber(hi), `{product.label} sells level {level + 1}`)
		covered[tier] = (covered[tier] or 0) + 1
	end
	H.eq(table.concat(covered, " "), "4 4 4 4 4 5", "upgrades per tier")
	H.eq(Config.plotUpgradeTier(Config.PLOT_LEVEL_MAX), nil, "nothing to buy at the last level")
	H.eq(Config.plotUpgradeProduct(Config.PLOT_LEVEL_MAX), nil)
	H.eq(Config.plotUpgradeTier(0), 1, "a bad level still gets a tier")
end)

----------------------------------------------------------------------------------------------------
-- The Robux prompt
----------------------------------------------------------------------------------------------------
H.test("upgrade prompt: stubs say coming soon; only the plot's own tier is prompted, never once maxed", function()
	local p = profileAt(6)
	local product, why = Shop.canPrompt(p, "PlotUpgradeT2")
	H.eq(product, nil)
	H.ok(why and string.find(why, "coming soon"), why)
	withIds(function()
		H.eq(Shop.canPrompt(p, "PlotUpgradeT2"), Config.DEVELOPER_PRODUCTS.PlotUpgradeT2, "level 6 -> T2")
		for _, other in { "PlotUpgradeT1", "PlotUpgradeT3", "PlotUpgradeT6" } do
			local got, reason = Shop.canPrompt(p, other)
			H.eq(got, nil, other .. " isn't level 6's tier (a cheap tier can't buy a late level)")
			H.ok(reason ~= nil)
		end
		local maxed = profileAt(Config.PLOT_LEVEL_MAX)
		for name in TIER_IDS do
			local got, reason = Shop.canPrompt(maxed, name)
			H.eq(got, nil, name .. " at the last level")
			H.ok(reason and string.find(reason, "fully upgraded"), reason)
		end
	end)
end)

----------------------------------------------------------------------------------------------------
-- Receipts
----------------------------------------------------------------------------------------------------
H.test("upgrade receipt: grants exactly one level once, from the level the plot has when it arrives", function()
	local p = profileAt(6)
	local confirm, status, grant = Shop.processReceipt(p, "PlotUpgradeT2", "pu-1", 0, never, yes)
	H.eq(confirm, true)
	H.eq(status, "granted")
	H.eq(p.plotLevel, 7)
	H.eq(grant.label, "Plot Level 7")
	H.eq(grant.compensation, 0)
	for _ = 1, 3 do -- Roblox retries the same PurchaseId
		local again, dup = Shop.processReceipt(p, "PlotUpgradeT2", "pu-1", 0, never, yes)
		H.eq(again, true, "a retried receipt is confirmed...")
		H.eq(dup, "duplicate")
		H.eq(p.plotLevel, 7, "...but never grants a second level")
	end
	-- The player bought levels with money between the prompt and the receipt: still exactly one more.
	p.plotLevel = 12
	Shop.processReceipt(p, "PlotUpgradeT2", "pu-2", 0, never, yes)
	H.eq(p.plotLevel, 13, "one level from where the plot is now, whatever the tier")
	H.eq(p.money, 0, "a level, not money")
	H.eq(#p.receipts, 2)
end)

H.test("upgrade receipt: a failed save isn't confirmed, and its retry doesn't grant twice", function()
	local p = profileAt(3)
	local confirm, status = Shop.processReceipt(p, "PlotUpgradeT1", "pu-s", 0, never, function()
		return false
	end)
	H.eq(confirm, false, "NotProcessedYet: Roblox delivers it again")
	H.eq(status, "granted")
	H.eq(p.plotLevel, 4)
	confirm, status = Shop.processReceipt(p, "PlotUpgradeT1", "pu-s", 0, never, yes)
	H.eq(confirm, true)
	H.eq(status, "duplicate")
	H.eq(p.plotLevel, 4, "granted once")
	-- If the server died before the save, neither the level nor the id persisted: the next server grants once.
	local fresh = profileAt(3)
	Shop.processReceipt(fresh, "PlotUpgradeT1", "pu-s", 0, never, yes)
	H.eq(fresh.plotLevel, 4)
end)

H.test("upgrade receipt: a plot already at the last level gets the last level's money price instead, once", function()
	H.eq(Config.plotUpgradeMaxedPay(), Config.plotUpgradePrice(Config.PLOT_LEVEL_MAX))
	local p = profileAt(Config.PLOT_LEVEL_MAX)
	local confirm, status, grant = Shop.processReceipt(p, "PlotUpgradeT6", "pu-max", 0, never, yes)
	H.eq(confirm, true)
	H.eq(status, "granted")
	H.eq(p.plotLevel, Config.PLOT_LEVEL_MAX, "never past the last level")
	H.eq(grant.compensation, Config.plotUpgradeMaxedPay())
	H.eq(p.money, Config.plotUpgradeMaxedPay())
	H.ok(string.find(grant.label, Format.money(Config.plotUpgradeMaxedPay()), 1, true), grant.label)
	Shop.processReceipt(p, "PlotUpgradeT6", "pu-max", 0, never, yes)
	H.eq(p.money, Config.plotUpgradeMaxedPay(), "paid once")
	-- the saved profile keeps the level in range
	local saved = ProfileStore.deserialize(serde.decode("json", serde.encode("json", ProfileStore.serialize(p))))
	H.eq(saved.plotLevel, Config.PLOT_LEVEL_MAX)
end)

H.test("upgrade: the money path is unchanged (same prices, the Robux products have no money price)", function()
	local p = profileAt(6)
	p.money = Config.plotUpgradePrice(7)
	H.ok(Shop.buy(p, "PlotUpgrade"))
	H.eq(p.plotLevel, 7)
	H.eq(p.money, 0)
	for name in TIER_IDS do
		H.eq((Config.priceOf("Product:" .. name, p)), nil, name)
		H.eq((Shop.buy(p, "Product:" .. name)), false, name .. " is Robux only")
	end
end)

----------------------------------------------------------------------------------------------------
-- The board
----------------------------------------------------------------------------------------------------
local plots = WorldBuilder.adopt(roblox.deserializeModel(fs.readFile(MapTool.PATH))[1]) -- not in the workspace: other specs own that

-- What a label shows: its text, or with an uploaded icon its IconRow ("[Robux]| 49").
local function shown(label: any): string
	local row = label:FindFirstChild("IconRow")
	if not row then
		return label.Text
	end
	local pieces = {}
	for _, d in row:GetChildren() do
		if d:IsA("ImageLabel") or d:IsA("TextLabel") then
			table.insert(pieces, d)
		end
	end
	table.sort(pieces, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local out = {}
	for _, d in pieces do
		table.insert(out, if d:IsA("ImageLabel") then `[{string.sub(d.Name, 6)}]` else d.Text)
	end
	return table.concat(out, "|")
end

-- What Icons.set shows for `text` with icon `key`: the text itself while the icon isn't uploaded.
local function expect(key: string, text: string): string
	local pieces = Icons.parse(key, text)
	if not pieces then
		return text
	end
	local out = {}
	for _, p in pieces do
		table.insert(out, if p.image then `[{p.key}]` else p.text)
	end
	return table.concat(out, "|")
end

H.test("upgrade board: 'Level X > Level Y', the money price on the red button, the tier's Robux price on the purple one", function()
	local labels = plots[1].upgradeLabels
	WorldBuilder.setUpgradeBoard(labels, 6)
	H.eq(labels.level.Text, "Level 6 > Level 7")
	H.eq(shown(labels.cash), expect("PlotUpgrade", Format.money(Config.plotUpgradePrice(7))))
	H.eq(shown(labels.robux), expect("Robux", "R$ 49"), "T2's placeholder while the product has no id")
	H.eq(labels.buttons.Visible, true)
	WorldBuilder.setUpgradeBoard(labels, 6, 240)
	H.eq(shown(labels.robux), expect("Robux", "R$ 240"), "the Dashboard price once fetched")
	WorldBuilder.setUpgradeBoard(labels, 1)
	H.eq(labels.level.Text, "Level 1 > Level 2")
	H.eq(shown(labels.cash), expect("PlotUpgrade", "$500"))
	H.eq(shown(labels.robux), expect("Robux", "R$ 25"))
	WorldBuilder.setUpgradeBoard(labels, Config.PLOT_LEVEL_MAX - 1)
	H.eq(labels.level.Text, `Level {Config.PLOT_LEVEL_MAX - 1} > Level {Config.PLOT_LEVEL_MAX}`)
	H.eq(shown(labels.cash), expect("PlotUpgrade", Format.money(Config.plotUpgradePrice(Config.PLOT_LEVEL_MAX))))
	H.eq(shown(labels.robux), expect("Robux", "R$ 799"))
end)

H.test("upgrade board: MAX LEVEL and no buttons at the last level; no buttons on an empty plot", function()
	local labels = plots[2].upgradeLabels
	WorldBuilder.setUpgradeBoard(labels, Config.PLOT_LEVEL_MAX)
	H.eq(labels.level.Text, "MAX LEVEL")
	H.eq(labels.buttons.Visible, false)
	H.eq(shown(labels.cash), "")
	H.eq(shown(labels.robux), "")
	WorldBuilder.setUpgradeBoard(labels, nil)
	H.eq(labels.level.Text, "Empty plot")
	H.eq(labels.buttons.Visible, false)
	WorldBuilder.setUpgradeBoard(labels, 3)
	H.eq(labels.buttons.Visible, true, "back on once there is a level to buy")
	-- a hand-made board without a Buttons row still works
	WorldBuilder.setUpgradeBoard({ level = labels.level, cash = labels.cash, robux = labels.robux }, Config.PLOT_LEVEL_MAX)
	H.eq(labels.level.Text, "MAX LEVEL")
	H.eq(shown(labels.cash), "")
end)

H.test("upgrade board: the reference look (dark navy studded sign on a post, red and purple buttons)", function()
	local board = plots[1].upgradeBoard
	local navy = board.Color
	H.ok(navy.R < 0.2 and navy.G < 0.2 and navy.B < 0.3 and navy.B > navy.R, "dark navy panel")
	local sign = board.Parent:FindFirstChild("UpgradeSign")
	H.ok(sign and sign:GetAttribute("AssetSlot") == "UpgradeSign", "frame and post are the UpgradeSign asset slot")
	local studded, post = 0, nil
	for _, d in sign:GetDescendants() do
		if d:IsA("BasePart") then
			if d.FrontSurface == Enum.SurfaceType.Studs then
				studded += 1
			end
			if d.Name == "UpgradePost" then
				post = d
			end
		end
	end
	H.ok(studded >= 8, `studded frame ({studded} pieces)`)
	H.ok(post and post.CFrame.Position.Y - post.Size.Y / 2 <= Config.GROUND_Y + 0.01, "the post stands on the ground")
	local gui = board:FindFirstChildOfClass("SurfaceGui")
	H.eq(gui:FindFirstChild("Title").Text, "Upgrade")
	local red = plots[1].upgradeLabels.cash.Parent
	local purple = plots[1].upgradeLabels.robux.Parent
	H.ok(red.BackgroundColor3.R > 0.7 and red.BackgroundColor3.G < 0.3, "red money button")
	H.ok(purple.BackgroundColor3.R > 0.5 and purple.BackgroundColor3.B > 0.7 and purple.BackgroundColor3.G < 0.3, "purple Robux button")
end)

----------------------------------------------------------------------------------------------------
-- The red $ button turns green when its owner can afford it (owner request)
----------------------------------------------------------------------------------------------------
local BoardButton = H.shared("BoardButton")

local function same(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 1e-6 and math.abs(a.G - b.G) < 1e-6 and math.abs(a.B - b.B) < 1e-6
end

H.test("board $ button: green from money == price, red one below it; red with no money or nothing to buy", function()
	H.ok(BoardButton.GREEN.fill.G > 0.6 and BoardButton.GREEN.fill.R < 0.4, "green")
	H.ok(BoardButton.RED.fill.R > 0.7 and BoardButton.RED.fill.G < 0.3, "red")
	for _, price in { 500, 1e6, Config.plotUpgradePrice(Config.PLOT_LEVEL_MAX), 100e12 } do
		H.eq(BoardButton.cashColors(price, price), BoardButton.GREEN, `exactly {price}: affordable`)
		H.eq(BoardButton.cashColors(price + 1, price), BoardButton.GREEN, `{price} + 1`)
		H.eq(BoardButton.cashColors(price - 1, price), BoardButton.RED, `{price} - 1: not yet`)
		H.eq(BoardButton.cashColors(price * (1 - 1e-9), price), BoardButton.RED, `a hair under {price}`)
	end
	H.eq(BoardButton.cashColors(0, 0), BoardButton.GREEN, "a free price")
	H.eq(BoardButton.cashColors(nil, 500), BoardButton.RED, "not your board (no money known)")
	H.eq(BoardButton.cashColors(1e30, nil), BoardButton.RED, "nothing to buy (maxed / empty plot)")
	H.eq(BoardButton.cashColors(0 / 0, 500), BoardButton.RED, "NaN money")
	H.eq(BoardButton.cashColors(500, 0 / 0), BoardButton.RED, "NaN price")
end)

H.test("board $ button: both boards are built red and carry the price they show, none when there is nothing to buy", function()
	local TreadmillBoard = H.server("TreadmillBoard")
	-- the plot's board
	local labels = plots[3].upgradeLabels
	local red = labels.cash.Parent
	H.eq(red.Name, "CashButton", "the button PlotService's click area paints (Painted)")
	H.ok(same(red.BackgroundColor3, BoardButton.RED.fill) and same(red:FindFirstChildOfClass("UIStroke").Color, BoardButton.RED.edge), "built red")
	WorldBuilder.setUpgradeBoard(labels, 4)
	H.eq(red:GetAttribute(BoardButton.PRICE_ATTRIBUTE), Config.plotUpgradePrice(5), "the price on the button")
	WorldBuilder.setUpgradeBoard(labels, Config.PLOT_LEVEL_MAX)
	H.eq(red:GetAttribute(BoardButton.PRICE_ATTRIBUTE), nil, "maxed: no price")
	WorldBuilder.setUpgradeBoard(labels, nil)
	H.eq(red:GetAttribute(BoardButton.PRICE_ATTRIBUTE), nil, "empty plot: no price")
	-- the treadmill's board
	local plot = plots[3]
	local board = TreadmillBoard.build(plot.model, plot.belt, plot.center)
	local tred = board.labels.cash.Parent
	H.eq(tred.Name, "CashButton")
	H.ok(same(tred.BackgroundColor3, BoardButton.RED.fill) and same(tred:FindFirstChildOfClass("UIStroke").Color, BoardButton.RED.edge), "built red")
	TreadmillBoard.render(board, { tier = 2, cash = Config.TREADMILL_TIERS[3].price, robux = 19, perSecond = 1 })
	H.eq(tred:GetAttribute(BoardButton.PRICE_ATTRIBUTE), Config.TREADMILL_TIERS[3].price)
	TreadmillBoard.render(board, { tier = Config.TREADMILL_MAX, perSecond = 1 })
	H.eq(tred:GetAttribute(BoardButton.PRICE_ATTRIBUTE), nil, "maxed: no price")
	TreadmillBoard.render(board, {})
	H.eq(tred:GetAttribute(BoardButton.PRICE_ATTRIBUTE), nil, "empty plot: no price")
	board.model:Destroy()
end)

H.test("board $ button: Effects.client paints only its own boards' $ buttons, from its money and the price", function()
	local effects = fs.readFile("src/client/Effects.client.luau")
	H.ok(string.find(effects, "BoardButton.cashColors(if mine then myMoney else nil", 1, true) ~= nil, "the shared rule, with money only on your own boards")
	H.ok(string.find(effects, "detector:GetAttribute(\"OwnerUserId\") == player.UserId", 1, true) ~= nil, "mine = the board's owner is me")
	H.ok(string.find(effects, "GetAttributeChangedSignal(BoardButton.PRICE_ATTRIBUTE)", 1, true) ~= nil, "repaints when the price changes")
	H.ok(string.find(effects, "partial.money", 1, true) ~= nil and string.find(effects, "repaintCash()", 1, true) ~= nil, "and when the money changes")
	H.ok(string.find(effects, "watchCash(detector)", 1, true) ~= nil, "for every board button's click area")
	H.ok(string.find(effects, "edge.Color = colors.edge", 1, true) ~= nil, "the outline too")
	-- the server keeps painting both red (the client does the green)
	for _, file in { "src/server/WorldBuilder.luau", "src/server/TreadmillBoard.luau" } do
		H.ok(string.find(fs.readFile(file), "fill = BoardButton.RED.fill, edge = BoardButton.RED.edge", 1, true) ~= nil, file)
	end
end)

return nil
