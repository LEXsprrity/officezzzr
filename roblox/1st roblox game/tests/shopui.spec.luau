-- The owner's 2026-10-15 UI pass: the pack reveal no longer plays over the Shop, the Free Gift window's
-- parts don't overlap, the Shop's look (charcoal body, featured pack cards with 3D reward tiles, wide pass
-- cards, Speed / Money art that grows with the pack, no green cards under green buttons) and buttons that
-- don't pop over their neighbours.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local H = require("./harness")

local Config = H.shared("Config")
local SeedPacks = H.shared("SeedPacks")
local ShopArt = H.shared("ShopArt")
local GiftLayout = H.shared("GiftLayout")
local PassCards = H.shared("PassCards")

local HUD = string.gsub(fs.readFile("src/client/HUD.client.luau"), "\r", "")
local REWARDS = string.gsub(fs.readFile("src/client/Rewards.client.luau"), "\r", "")

local function block(source: string, from: string, to: string): string
	local a = string.find(source, from, 1, true)
	local b = a and string.find(source, to, a + #from, true)
	return if a and b then string.sub(source, a, b) else ""
end

-- "Color3.fromRGB(r, g, b)" after `name = ` in `source`
local function rgb(source: string, name: string): (number?, number?, number?)
	local r, g, b = string.match(source, name .. " = Color3%.fromRGB%((%d+), (%d+), (%d+)%)")
	return tonumber(r), tonumber(g), tonumber(b)
end

-- Green enough to clash with the green R$ button: green clearly above both red and blue.
local function greenish(r: number, g: number, b: number): boolean
	return g > r + 40 and g > b + 40
end

----------------------------------------------------------------------------------------------------
-- Pack reveal
----------------------------------------------------------------------------------------------------
local REVEAL = block(HUD, "-- Pack reveal", "-- Refresh from stats")

H.test("pack reveal: the Shop closes while it plays and opens again where it was", function()
	H.ok(REVEAL ~= "", "the reveal block")
	local queue = block(REVEAL, "function queueReveal(", "\n\tend\nend")
	H.ok(string.find(queue, "local reopen: string? = if modal.Visible then modalName else nil", 1, true) ~= nil, "remembers the open window")
	H.ok(string.find(queue, "local scroll = modalBody.CanvasPosition", 1, true) ~= nil, "and its scroll")
	local close = string.find(queue, "closeModal()", 1, true)
	local spawn = string.find(queue, "task.spawn(function()", 1, true)
	H.ok(close and spawn and close < spawn, "closes it before the reel plays")
	H.ok(string.find(queue, "openModal(reopen)", 1, true) ~= nil and string.find(queue, "modalBody.CanvasPosition = scroll", 1, true) ~= nil,
		"reopens it where it was after Continue")
end)

H.test("pack reveal: a dark full-screen backdrop above every window, one clipped panel that fits phones", function()
	local backdrop = string.match(REVEAL, "local revealGui = new%(\"Frame\", (%b{})")
	H.ok(backdrop ~= nil, "the backdrop")
	local transparency = tonumber(backdrop and string.match(backdrop, "BackgroundTransparency = ([%d%.]+)"))
	H.ok(transparency and transparency <= 0.25, "dark enough to hide what's behind")
	H.ok(backdrop and string.find(backdrop, "Size = UDim2.fromScale(1, 1)", 1, true) and string.find(backdrop, "Active = true", 1, true), "the whole screen, sinking clicks")
	local revealZ = tonumber(backdrop and string.match(backdrop, "ZIndex = (%d+)"))
	local modalZ = tonumber(string.match(string.match(HUD, "local modal = new%(\"Frame\", (%b{})") or "", "ZIndex = (%d+)"))
	local giftZ = tonumber(string.match(string.match(REWARDS, "local window = new%(\"Frame\", (%b{})") or "", "ZIndex = (%d+)"))
	H.ok(revealZ and modalZ and giftZ and revealZ > modalZ and revealZ > giftZ, "above the Shop and the Free Gift windows")
	local panel = string.match(REVEAL, "local panel = new%(\"Frame\", (%b{})")
	H.ok(panel and string.find(panel, "ClipsDescendants = true", 1, true), "the rays stay inside the panel")
	H.ok(string.find(REVEAL, "panelScale.Scale = math.clamp(math.min((w - 24) / (PANEL_W + 12), (h - 24) / (PANEL_H + 12)), 0.3, 1)", 1, true) ~= nil,
		"the panel shrinks to fit small screens")
	H.ok(string.find(REVEAL, "fitPanel()", 1, true) ~= nil, "fitted before each reveal")
end)

H.test("pack reveal: cards fit their text, a clear centre marker, the result and Continue don't overlap the reel", function()
	local card = block(REVEAL, "local function seedCard(", "\n\tend\n")
	H.ok(string.find(card, "UIPadding", 1, true) ~= nil, "text inside padding")
	H.ok(string.find(card, "UITextSizeConstraint", 1, true) ~= nil, "scaled text with a cap")
	H.ok(string.find(card, "Name = \"Mutation\"", 1, true) ~= nil, "the mutation on its own line")
	H.ok(not string.find(REVEAL, "Scale = 1.16", 1, true), "the winner isn't scaled over its neighbours any more")
	H.ok(string.find(REVEAL, "Name = \"Marker\"", 1, true) ~= nil and string.find(REVEAL, "Name = \"Pointer\"", 1, true) ~= nil, "a gold window and pointers")
	-- the layout's numbers: title above the reel, the result under it, Continue at the bottom
	local panelH = tonumber(string.match(REVEAL, "local PANEL_W, PANEL_H = %d+, (%d+)"))
	local reelY, reelH = string.match(REVEAL, "local REEL_X, REEL_Y, REEL_W, REEL_H = %d+, (%d+), %d+, (%d+)")
	local resultGap = tonumber(string.match(REVEAL, "local RESULT_Y = REEL_Y %+ REEL_H %+ (%d+)"))
	local view = tonumber(string.match(REVEAL, "local VIEW = (%d+)"))
	reelY, reelH = tonumber(reelY), tonumber(reelH)
	H.ok(panelH and reelY and reelH and resultGap and view, "the layout constants")
	if panelH and reelY and reelH and resultGap and view then
		H.ok(reelY >= 18 + 50, "the title (18..68) sits above the reel")
		local resultTop = reelY + reelH + resultGap
		H.ok(resultTop > reelY + reelH + 4 + 13, "the result starts under the reel and its bottom pointer")
		H.ok(resultTop + view <= panelH - 42, "the 3D result ends above \"Click to continue\"")
		H.ok(resultTop + 98 + 54 <= panelH - 42, "the result's words end above it too")
	end
	H.ok(string.find(REVEAL, "Text = \"Click to continue\", Size = UDim2.new(1, -40, 0, 30), Position = UDim2.new(0, 20, 1, -42)", 1, true) ~= nil,
		"Click to continue at the bottom")
	H.ok(string.find(REVEAL, "FlowerView.show(viewHolder, FlowerView.seed(best.zone, tonumber(best.gene))", 1, true) ~= nil, "the won seed in 3D")
	local shop = fs.readFile("src/server/Shop.luau")
	H.ok(string.find(shop, "gene = gene }", 1, true) ~= nil, "the server sends the seed's gene (its look; the bag key has it too)")
end)

----------------------------------------------------------------------------------------------------
-- Free Gift window
----------------------------------------------------------------------------------------------------
H.test("Free Gift: no two parts of the window overlap, all inside it under the title bar", function()
	local names = {}
	for name in GiftLayout.rects do
		table.insert(names, name)
	end
	table.sort(names)
	H.eq(#names, 8, "hint, art, limited, amount, 3 steps, claim")
	for i, a in names do
		local r = GiftLayout.rects[a]
		H.ok(r.x >= 0 and r.y >= GiftLayout.TITLE_H and r.x + r.w <= GiftLayout.W and r.y + r.h <= GiftLayout.H - 8, `{a} inside the window`)
		for j = i + 1, #names do
			local b = names[j]
			H.ok(not GiftLayout.overlaps(r, GiftLayout.rects[b]), `{a} and {b} don't overlap`)
		end
	end
	local R = GiftLayout.rects
	H.ok(R.claim.y >= R.step1.y + R.step1.h + 12, "CLAIM! under the steps, with room")
	H.ok(R.step1.y == R.step2.y and R.step2.y == R.step3.y and R.step1.x < R.step2.x and R.step2.x < R.step3.x, "the three steps in a row")
	H.ok(R.art.x + R.art.w <= R.limited.x and R.art.x + R.art.w <= R.amount.x, "the bag on the left, the words on the right")
	H.ok(R.limited.y + R.limited.h <= R.amount.y, "LIMITED TIME above the amount")
	H.ok(R.art.y + R.art.h <= R.step1.y, "the steps under the bag")
	-- inside a step: the title over the button, both inside it
	local t, body = GiftLayout.stepTitle, GiftLayout.stepBody
	H.ok(not GiftLayout.overlaps(t, body), "a step's title and button don't overlap")
	H.ok(body.y + body.h <= GiftLayout.STEP_H and body.x + body.w <= GiftLayout.STEP_W, "the button inside its step")
	H.ok(GiftLayout.overlaps({ x = 0, y = 0, w = 10, h = 10 }, { x = 5, y = 5, w = 10, h = 10 }), "overlaps() sees an overlap")
	H.ok(not GiftLayout.overlaps({ x = 0, y = 0, w = 10, h = 10 }, { x = 10, y = 0, w = 10, h = 10 }), "touching edges don't count")
end)

H.test("Free Gift: Rewards.client places everything from GiftLayout; no flat dark boxes; relief words", function()
	for _, needle in {
		"local GiftLayout = require(Shared:WaitForChild(\"GiftLayout\"))",
		"Position = UDim2.fromOffset(R.hint.x, R.hint.y)",
		"Position = UDim2.fromOffset(R.art.x, R.art.y)",
		"Position = UDim2.fromOffset(R.limited.x, R.limited.y)",
		"Position = UDim2.fromOffset(R.amount.x, R.amount.y)",
		"local r = R[\"step\" .. i]",
		"UDim2.fromOffset(R.claim.w, R.claim.h), UDim2.fromOffset(R.claim.x, R.claim.y)",
		"UiFx.relief(bold(like, 3, {",
	} do
		H.ok(string.find(REWARDS, needle, 1, true) ~= nil, needle)
	end
	for _, gone in { "Name = \"Screen\"", "Color3.fromRGB(30, 32, 42)", "BackgroundColor3 = FRAME_INK, BackgroundTransparency = 0.5", "UDim2.new(0.5, -160, 1, -82)" } do
		H.ok(not string.find(REWARDS, gone, 1, true), `"{gone}" is gone`)
	end
end)

----------------------------------------------------------------------------------------------------
-- Shop: seed packs
----------------------------------------------------------------------------------------------------
H.test("SeedPacks.showcase: a tile per rarity with the exact odds, the zone's flower, the Legendary featured", function()
	for _, entry in Config.products("Pack") do
		local pack = SeedPacks.packForProduct(entry.product)
		local odds = SeedPacks.odds(pack)
		local catalog = { [pack.zone] = { { "Daisy", "Tulip" }, {}, { "Rose" } } }
		local tiles = SeedPacks.showcase(pack, catalog)
		H.eq(#tiles, #Config.RARITIES, entry.name)
		local sum = 0
		for i, tile in tiles do
			H.eq(tile.rarity, i)
			H.eq(tile.id, Config.RARITIES[i].id)
			H.eq(tile.pct, odds.rarities[i], `{tile.id}: the very odds the server rolls with`)
			H.eq(tile.featured, i == Config.LEGENDARY)
			sum += tile.pct
		end
		H.near(sum, 100, 1e-9)
		H.eq(tiles[1].flower, "Daisy", "the rarity's first flower")
		H.eq(tiles[2].flower, nil, "none listed: FlowerView's fallback")
		H.eq(tiles[3].flower, "Rose")
		H.eq(tiles[#tiles].featured, true, "the Legendary comes last (the big tile at the right)")
		H.eq(#SeedPacks.showcase(pack, nil), #Config.RARITIES, "before the catalog arrives too")
	end
end)

H.test("Shop SEED PACKS: one wide card per pack with 3D reward tiles, the Legendary in a rainbow frame, a grey button tray", function()
	local shop = block(HUD, "-- SEED PACKS: the featured card", "-- The other cards")
	H.ok(shop ~= "", "the pack card block")
	H.ok(string.find(shop, "Size = UDim2.new(1, -8, 0, PACK_H)", 1, true) ~= nil, "spans the Shop's width")
	H.ok(string.find(shop, "SeedPacks.showcase(pack, stats.catalog)", 1, true) ~= nil, "the tiles from SeedPacks.showcase (the server's odds)")
	H.ok(string.find(shop, "FlowerView.show(f, FlowerView.flower(zone, tile.rarity, tile.flower), {", 1, true) ~= nil, "each tile a ViewportFrame of its flower")
	H.ok(string.find(shop, "new(\"UIGradient\", { Name = \"Rainbow\", Rotation = 35, Color = RAINBOW, Parent = stroke })", 1, true) ~= nil,
		"the featured tile's rainbow frame")
	H.ok(string.find(shop, "spin = featured", 1, true) ~= nil, "the Legendary turns")
	H.ok(string.find(shop, "rewardTile(c, pack.zone, tile, UDim2.new(1, -(16 + featuredW), 0, 88), featuredW, bottom - 88)", 1, true) ~= nil,
		"big, at the right edge")
	H.ok(string.find(shop, "UiFx.relief(bold(c, 5, {", 1, true) ~= nil, "the pack's name in relief")
	H.ok(string.find(shop, "Name = \"Tray\"", 1, true) ~= nil and string.find(shop, "TRAY_GREY", 1, true) ~= nil, "a grey strip under the buttons")
	H.ok(string.find(shop, "buyPair(tray,", 1, true) ~= nil, "gift + R$ on it")
	H.ok(not string.find(shop, "lootTable", 1, true), "the old loot-table bars are gone")
	local r, g, b = rgb(HUD, "local TRAY_GREY")
	H.ok(r and g and b and math.abs(r - g) < 20 and math.abs(g - b) < 20 and r < 110, "greyish and dark")
	-- the Shop re-renders once the 3D previews or the flower catalog arrive
	H.ok(string.find(HUD, "(modalName == \"Index\" or modalName == \"Sell\" or modalName == \"Shop\")", 1, true) ~= nil, "redrawn with the previews")
	H.ok(string.find(HUD, "or changed.catalog) then", 1, true) ~= nil, "and with the catalog")
end)

----------------------------------------------------------------------------------------------------
-- Shop: the look and the other cards
----------------------------------------------------------------------------------------------------
H.test("Shop look: charcoal studded body, bright green bar, plain \"Shop\" title, yellow / cyan relief section titles", function()
	local shopWindow = string.match(HUD, "\tShop = (%b{})")
	H.ok(shopWindow and string.find(shopWindow, "body = Color3.fromRGB(48, 50, 58)", 1, true) and string.find(shopWindow, "plain = true", 1, true), "the Shop's window")
	H.ok(string.find(HUD, "modal.BackgroundColor3 = window.body or window.from:Lerp(window.to, 0.5):Lerp(WHITE, 0.25)", 1, true) ~= nil,
		"its own body colour (others keep the bar's colours)")
	H.ok(string.find(HUD, "Icons.set(modalTitle, {}, window.title, ICON.big)", 1, true) ~= nil, "no icon in its title")
	H.ok(string.find(HUD, "UiFx.relief(bold(row, 4, { Text = `-- {label} --`", 1, true) ~= nil, "section titles in relief")
	local renderShop = block(HUD, "function renderShop(): boolean", "\n\tend\nend")
	local colours = {}
	for label, colour in string.gmatch(renderShop, "section%(\"([%u ]+)\", nextOrder%(%), (HEADING_%u+)%)") do
		table.insert(colours, `{label}={colour}`)
	end
	H.eq(table.concat(colours, ","), "SEED PACKS=HEADING_GOLD,PASSES=HEADING_CYAN,SPEED=HEADING_GOLD,MONEY=HEADING_CYAN,UPGRADES=HEADING_GOLD", "alternating")
	H.ok(string.find(renderShop, "banner(nextOrder(), \"DoubleSpeed\", \"SPEED\"", 1, true) ~= nil, "a DOUBLE Your SPEED banner")
end)

H.test("Shop colours: no card is green (Money cards gold), so the green R$ button always stands out", function()
	local cardColors = string.match(HUD, "local CARD_COLORS = (%b{})") or ""
	for _, name in { "Speed", "Money", "PlotUpgrade", "Treadmill" } do
		local r, g, b = rgb(cardColors, name)
		H.ok(r ~= nil, `{name} card colour`)
		if r and g and b then
			H.ok(not greenish(r, g, b), `{name} cards aren't green ({r}, {g}, {b})`)
		end
	end
	local r, g, b = rgb(cardColors, "Money")
	H.ok(r and g and b and r > 200 and g > 150 and b < 90, "Money: warm gold")
	local gr, gg, gb = rgb(HUD, "local ROBUX_GREEN")
	H.ok(gr and gg and gb and greenish(gr, gg, gb), "the R$ button is green")
	for name, color in PassCards.COLORS do
		local c = color :: any
		H.ok(not greenish(c.R * 255, c.G * 255, c.B * 255), `pass {name} isn't green`)
	end
	H.eq(PassCards.view("FastGrow", nil, 0).rainbow, true, "Fast Grow: a rainbow card")
	H.eq(PassCards.view("DoubleMoney", nil, 0).rainbow, false)
end)

H.test("Shop PASSES: wide cards two a row, a big round icon, the benefit's number in green", function()
	H.ok(string.find(HUD, "local WIDE_W, WIDE_H = 392, 200", 1, true) ~= nil, "two a row in the Shop's ~802 px")
	H.ok(2 * 392 + 14 <= 802, "they fit")
	H.ok(string.find(HUD, "PassCards.render(cardGrid(nextOrder(), WIDE_W, WIDE_H), stats.passes, {", 1, true) ~= nil, "in a wide grid")
	local card = block(HUD, "local function passCard(", "\n\tend\n")
	H.ok(string.find(card, "Name = \"Badge\"", 1, true) and string.find(card, "CornerRadius = UDim.new(1, 0)", 1, true), "a round badge for the icon")
	H.ok(string.find(card, "Text = emphasize(view.about)", 1, true) ~= nil, "the benefit with its number coloured")
	-- emphasize() picks the number out of every pass's benefit
	for name, pass in Config.GAMEPASSES do
		local words = pass.about
		local found = false
		for _, pattern in { "x%d[%d%.]*", "%d[%d%.]*x", "%+%d[%d%.,]*%a*", "Doubles", "Rarer" } do
			found = found or string.find(words, pattern) ~= nil
		end
		if name ~= "ExtraSlots" then
			H.ok(found, `{name}: "{words}" has a word to colour`)
		end
	end
end)

H.test("ShopArt: the Speed / Money art grows with the pack, from one item to a chest", function()
	H.eq(ShopArt.LEVELS, 8)
	local speeds, monies = #Config.products("Speed"), #Config.products("Money")
	H.eq(speeds, 8)
	local levels = {}
	for i = 1, speeds do
		table.insert(levels, ShopArt.level(i, speeds))
	end
	H.eq(table.concat(levels, ","), "1,2,3,4,5,6,7,8", "8 Speed packs: every level")
	levels = {}
	for i = 1, monies do
		table.insert(levels, ShopArt.level(i, monies))
	end
	H.eq(table.concat(levels, ","), "1,3,5,6,8", "5 Money packs: one stack ... a chest")
	H.eq(ShopArt.level(1, 1), 1)
	local RANK = { none = 0, sack = 1, chest = 2 }
	local last = ShopArt.plan(1)
	H.eq(#last.items, 1, "the smallest: one item")
	H.eq(last.holder, nil)
	for level = 2, ShopArt.LEVELS do
		local plan = ShopArt.plan(level)
		local a, b = RANK[last.holder or "none"], RANK[plan.holder or "none"]
		H.ok(b >= a, `level {level}: the holder never shrinks`)
		if a == b then
			H.ok(#plan.items >= #last.items, `level {level}: at least as many items`)
		end
		last = plan
	end
	H.eq(ShopArt.plan(ShopArt.LEVELS).holder, "chest", "the biggest: a treasure chest")
	H.eq(ShopArt.plan(6).holder, "sack", "then a sack")
	-- every item stays in the design box (a little off the bottom is fine: the amount sits over it)
	for level = 1, ShopArt.LEVELS do
		for i, it in ShopArt.plan(level).items do
			H.ok(it.y - it.size / 2 >= -2 and math.abs(it.x) + it.size / 2 <= ShopArt.BOX_W / 2 + 12, `level {level} item {i} on the card`)
		end
	end
	-- and builds onto a card
	local card = roblox.Instance.new("Frame")
	local box = ShopArt.build(card, 8, roblox.UDim2.new(0.5, 0, 0, 2), 128, { key = "Speed", sackColor = roblox.Color3.new(0, 0, 1), zindex = 2 })
	H.eq(box.Parent, card)
	H.eq(box:GetAttribute("Holder"), "chest")
	H.ok(box:FindFirstChild("Chest") ~= nil and box:FindFirstChild("Lid") ~= nil, "the chest's box and lid")
	H.ok(box:FindFirstChild("Item8") ~= nil, "every item")
	local hud = block(HUD, "local function productCard(", "\n\tend\n")
	H.ok(string.find(hud, "ShopArt.build(c, level,", 1, true) ~= nil, "the Speed / Money cards draw it")
	H.ok(string.find(HUD, "if level > ShopArt.LEVELS / 2 then YELLOW_NUMBER else NUMBER_GREEN", 1, true) ~= nil, "big packs' amounts in yellow")
end)

H.test("Shop buttons side by side pop less (PopScale), so a hovered button never grows over its neighbour", function()
	local pop = tonumber(string.match(HUD, "local SIDE_POP = ([%d%.]+)"))
	H.ok(pop and pop > 1 and pop <= 1.06, "a small pop")
	H.ok(string.find(HUD, "b:SetAttribute(\"PopScale\", SIDE_POP)", 1, true) ~= nil, "on the buy button beside the gift button")
	H.ok(string.find(HUD, "r:SetAttribute(\"PopScale\", SIDE_POP)", 1, true) ~= nil, "on the R$ button beside the $ button")
	-- the worst case: the narrowest card's buttons, popped at once, stay apart (gap 10 between gift and buy)
	local cardW, gift = 252 - 20, math.floor(52 * 1.15)
	local buyW = cardW - gift - 10
	local grow = (buyW * (pop or 1.1) - buyW) / 2 + (gift * 1.1 - gift) / 2
	H.ok(grow < 10, `they grow {grow} px into a 10 px gap`)
	local halves = (252 - 28) / 2 -- the $ and R$ halves of an upgrade card, 8 px apart
	H.ok(halves * ((pop or 1.1) - 1) < 8, "the $ / R$ halves too")
	local FX = fs.readFile("src/shared/UiFx.luau")
	H.ok(string.find(FX, "b:GetAttribute(\"PopScale\")", 1, true) ~= nil, "UiFx.pop reads it")
end)

return nil
