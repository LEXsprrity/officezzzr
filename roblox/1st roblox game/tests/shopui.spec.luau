-- The owner's 2026-10-15 UI pass: the pack reveal no longer plays over the Shop, the Free Gift window's
-- parts don't overlap, the Shop's look (charcoal body, featured pack cards with 3D reward tiles, wide pass
-- cards, Speed / Money art that grows with the pack, no green cards under green buttons) and buttons that
-- don't pop over their neighbours. Round 2 (the same day): a wider, square Shop (and window frame) like the
-- reference, the reference's button rows (ShopLayout: checked geometrically), drawn sack and chest art, the
-- owner's white Robux icon and the wide Shop / Index buttons.
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

----------------------------------------------------------------------------------------------------
-- Shop round 2 (owner playtest 2026-10-15): a wider window, square everything, the reference's button rows
----------------------------------------------------------------------------------------------------
local ShopLayout = H.shared("ShopLayout")
local ShopUi = H.shared("ShopUi")
local Format = H.shared("Format")
local Icons = H.shared("Icons")
local UiFx = string.gsub(fs.readFile("src/shared/UiFx.luau"), "\r", "")

-- The code between two markers of the HUD (a block), "" when a marker is missing.
local WINDOW_KIT = block(HUD, "-- Modals: Shop, Trail Shop, Index and Sell share one window", "-- Plants panel (right side)")
local SHOP = block(HUD, "-- Shop (owner references 2026-10-15, round 2", "-- Trail Shop: one row of tall cards")
local TRAILS = block(HUD, "local function trailCard(", "function renderTrails()")
local INDEX = block(HUD, "local function renderIndex()", "-- SELL window")
local SELL = block(HUD, "-- SELL window", "end of SELL")

local function inside(r: any, w: number, h: number): boolean
	return r.x >= 0 and r.y >= 0 and r.x + r.w <= w and r.y + r.h <= h
end
local function apart(a: any, b: any): boolean
	return a.x + a.w <= b.x or b.x + b.w <= a.x or a.y + a.h <= b.y or b.y + b.h <= a.y
end

H.test("Shop window: wider than the other windows, still fits a phone (modalScale)", function()
	local w, h = ShopLayout.window("Shop")
	H.ok(w >= 1100 and w <= 1150, `the Shop is ~1120 design px wide ({w})`)
	local tw = ShopLayout.window("Trails")
	H.eq(tw, ShopLayout.DEFAULT_W, "the Trail Shop keeps its width")
	H.eq(ShopLayout.MAX_W, w, "the studs and bands cover the widest window")
	H.ok(string.find(HUD, "local w, h = ShopLayout.window(name) -- the Shop is wider\n\tmodal.Size = UDim2.fromOffset(w, h)\n\tfitModal()", 1, true) ~= nil,
		"openModal sizes the window, then fits it")
	H.ok(string.find(HUD, "local mw, mh = modal.Size.X.Offset, modal.Size.Y.Offset", 1, true) ~= nil, "fitModal fits the open window's size")
	-- fitModal's formula on small landscape screens (the HUD's UIScale bottoms out at 0.55)
	for _, screen in { { 844, 390 }, { 667, 375 }, { 1024, 600 }, { 1920, 1080 } } do
		local ui = math.clamp(screen[2] / 900, 0.55, 1.25)
		local dw, dh = screen[1] / ui, screen[2] / ui
		local s = math.clamp(math.min((dw - 24) / (w + 12), (dh - 24) / (h + 12)), 0.3, 1)
		H.ok(w * s <= dw - 12 and h * s <= dh - 12, `{screen[1]}x{screen[2]}: the window fits the screen`)
	end
	-- the cards fill the wider body
	local content = ShopLayout.CONTENT_W
	H.eq(content, w - 2 * ShopLayout.PAD - ShopLayout.SCROLLBAR - 16, "a full-width row's width")
	H.ok(3 * ShopLayout.CARD_W + 2 * ShopLayout.GAP <= content and 3 * ShopLayout.CARD_W + 2 * ShopLayout.GAP > content - 3, "three cards fill a row")
	H.ok(2 * ShopLayout.WIDE_W + ShopLayout.GAP <= content and 2 * ShopLayout.WIDE_W + ShopLayout.GAP > content - 2, "two passes fill a row")
	H.ok(ShopLayout.CARD_W >= 330, "the three-a-row cards got roomier")
end)

H.test("Shop windows are square: no rounded corners in the window frame, the Shop, Trail Shop, Index and Sell", function()
	for name, source in { ["window frame"] = WINDOW_KIT, Shop = SHOP, ["Trail Shop"] = TRAILS, Index = INDEX, Sell = SELL } do
		H.ok(source ~= "", `{name}: its block`)
		for line in string.gmatch(source, "[^\n]+") do
			if string.find(line, "UICorner", 1, true) then
				H.ok(string.find(line, "-- round:", 1, true) ~= nil, `{name}: a rounded corner: {line}`)
			end
			H.ok(not string.find(line, "deco(", 1, true), `{name}: deco() rounds corners: {line}`)
		end
	end
	local SHOP_UI = string.gsub(fs.readFile("src/shared/ShopUi.luau"), "\r", "")
	H.ok(not string.find(SHOP_UI, "new(\"UICorner\"", 1, true) and not string.find(SHOP_UI, "Instance.new(\"UICorner\")", 1, true),
		"ShopUi's buttons, tags and studs are square (the studs only copy a rounded frame's own corner)")
	local chunky = block(HUD, "local function chunky(", "\nend\n")
	H.ok(string.find(chunky, "{ outline() }", 1, true) and string.find(chunky, "ShopUi.bevel(b)", 1, true), "chunky buttons: square, bevelled")
	H.ok(not string.find(chunky, "UICorner", 1, true) and not string.find(chunky, "deco(", 1, true), "no rounded chunky buttons")
end)

H.test("Shop window frame: flat green bar with studs and three light bands, big relief title, square red X, charcoal studded body, no money", function()
	H.ok(string.find(WINDOW_KIT, "Shop = { title = \"Shop\", bar = Color3.fromRGB(59, 227, 59) }", 1, true) ~= nil, "the Shop's flat bright green bar")
	H.ok(string.find(HUD, "titleBar.BackgroundColor3 = window.bar", 1, true) ~= nil, "one flat colour per window")
	-- one studs style for the bar and the body (owner: the body's studs must match the bar's), the bar's tinted per window
	H.ok(string.find(WINDOW_KIT, "ShopUi.studs(titleBar, nil, nil, 2)", 1, true) ~= nil, "studs over the bar")
	H.ok(string.find(WINDOW_KIT, "ShopUi.studs(studs, WINDOW_BODY, nil, 1)", 1, true) ~= nil, "the same studs over the body, tinted charcoal")
	H.ok(string.find(HUD, "ShopUi.paintStuds(titleBar, window.bar)", 1, true) ~= nil, "the bar's studs take the window's colour")
	local bands = string.match(WINDOW_KIT, "for _, band in (%b{}) do")
	local n = 0
	for a in string.gmatch(bands or "", "{ ([%d%.]+), [%d%.]+ }") do
		n += 1
		H.ok(tonumber(a) >= 0.5, "on the bar's right half")
	end
	H.eq(n, 3, "three diagonal bands")
	H.ok(string.find(WINDOW_KIT, "UiFx.relief(modalTitle, 4, 5)", 1, true) ~= nil, "the title in relief")
	H.ok(string.find(HUD, "modalTitle.Text = window.title -- words only, in relief", 1, true) ~= nil, "words only")
	H.ok(string.find(WINDOW_KIT, "Text = \"X\"", 1, true) and string.find(WINDOW_KIT, "outline(4, Color3.fromRGB(95, 6, 12))", 1, true), "a white X in a dark red border")
	H.ok(not string.find(WINDOW_KIT, "Icons.image(\"Close\")", 1, true), "no round Close icon in the X")
	H.ok(string.find(WINDOW_KIT, "BackgroundColor3 = WINDOW_BODY", 1, true) and string.find(WINDOW_KIT, "local WINDOW_BODY = Color3.fromRGB(48, 50, 58)", 1, true),
		"the charcoal body (every window)")
	H.ok(not string.find(HUD, "moneySubtitle", 1, true) and not string.find(HUD, "Format.money(stats.money)}`, ICON.big", 1, true), "no money counter in a title bar")
	local studs = block(fs.readFile("src/shared/ShopUi.luau"), "function ShopUi.studs(", "\nend")
	H.ok(string.find(studs, "ScaleType = Enum.ScaleType.Tile", 1, true) and string.find(studs, "Icons.image(\"Studs\")", 1, true), "the tiled studs texture once uploaded")
end)

H.test("Shop SEED PACKS: one wide gold-outlined card per pack, a red New! tag, square 3D tiles, buttons straight on the art", function()
	local shop = block(HUD, "-- SEED PACKS: the featured card", "-- The other cards")
	H.ok(shop ~= "", "the pack card block")
	H.ok(string.find(shop, "Size = UDim2.new(1, -8, 0, L.PACK_H)", 1, true) ~= nil, "spans the Shop's width")
	H.ok(string.find(shop, "stroke.Color = COLORS.gold", 1, true) ~= nil, "a gold outline (featured)")
	H.ok(string.find(shop, "ShopUi.tag(c, \"New!\"", 1, true) ~= nil and not string.find(HUD, "PREMIUM", 1, true), "New! instead of PREMIUM")
	H.ok(string.find(shop, "SeedPacks.showcase(pack, stats.catalog)", 1, true) ~= nil, "the tiles from SeedPacks.showcase (the server's odds)")
	H.ok(string.find(shop, "FlowerView.show(f, FlowerView.flower(zone, tile.rarity, tile.flower), {", 1, true) ~= nil, "each tile a ViewportFrame of its flower")
	H.ok(string.find(shop, "new(\"UIGradient\", { Name = \"Rainbow\", Rotation = 35, Color = RAINBOW, Parent = stroke })", 1, true) ~= nil,
		"the featured tile's rainbow frame")
	H.ok(string.find(shop, "outline(if featured then 5 else 2, if featured then WHITE else FRAME_INK)", 1, true) ~= nil, "square tiles, thin dark outlines")
	H.ok(string.find(shop, "TextXAlignment = Enum.TextXAlignment.Right", 1, true) and string.find(shop, "AnchorPoint = Vector2.new(0, 1)", 1, true),
		"the % at the bottom right")
	H.ok(string.find(shop, "buttonRow(c, PACK_W, L.PACK_H, L.bottomY(L.PACK_H, true), { buy })", 1, true) ~= nil, "gift + R$ on the art")
	H.ok(not string.find(HUD, "Name = \"Tray\"", 1, true) and not string.find(HUD, "TRAY_GREY", 1, true), "no grey tray any more")
	H.ok(not string.find(shop, "lootTable", 1, true), "the old loot-table bars are gone")
	-- the Shop re-renders once the 3D previews or the flower catalog arrive
	H.ok(string.find(HUD, "(modalName == \"Index\" or modalName == \"Sell\" or modalName == \"Shop\")", 1, true) ~= nil, "redrawn with the previews")
	H.ok(string.find(HUD, "or changed.catalog) then", 1, true) ~= nil, "and with the catalog")
end)

H.test("Shop look: yellow / cyan relief section titles, vivid square cards with art edge to edge and speckles", function()
	H.ok(string.find(HUD, "UiFx.relief(bold(row, 4, { Text = `-- {label} --`", 1, true) ~= nil, "section titles in relief")
	local renderShop = block(HUD, "function renderShop(): boolean", "\n\tend\nend")
	local colours = {}
	for label, colour in string.gmatch(renderShop, "section%(\"([%u ]+)\", nextOrder%(%), (HEADING_%u+)%)") do
		table.insert(colours, `{label}={colour}`)
	end
	H.eq(table.concat(colours, ","), "SEED PACKS=HEADING_GOLD,PASSES=HEADING_CYAN,SPEED=HEADING_GOLD,MONEY=HEADING_CYAN,UPGRADES=HEADING_GOLD", "alternating")
	H.ok(string.find(renderShop, "banner(nextOrder(), \"DoubleSpeed\", \"SPEED\"", 1, true) ~= nil, "a DOUBLE Your SPEED banner")
	local cardFrame = block(SHOP, "local function cardFrame(", "\n\tend\n")
	H.ok(string.find(cardFrame, "outline(L.CARD_STROKE, color:Lerp(WHITE, 0.6))", 1, true) ~= nil, "a thin bright outline")
	H.ok(string.find(cardFrame, "paint(c, color, rainbow)", 1, true) and string.find(cardFrame, "ShopUi.speckles(c, cardSeed, 12, 1)", 1, true), "painted, speckled")
	H.ok(ShopLayout.CARD_STROKE <= 3, "thin")
	H.ok(string.find(SHOP, "UiFx.relief(amountLabel, 4, 4)", 1, true) ~= nil, "the amounts in big relief")
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

H.test("Shop PASSES: wide cards two a row, a big square badge, the benefit's number in green", function()
	H.ok(string.find(HUD, "PassCards.render(cardGrid(nextOrder(), L.WIDE_W, L.WIDE_H), stats.passes, {", 1, true) ~= nil, "in a wide grid")
	local card = block(HUD, "local function passCard(", "\n\tend\n")
	H.ok(string.find(card, "Name = \"Badge\"", 1, true) and string.find(card, "outline(4)", 1, true), "a square badge for the icon")
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

-- Every button row the Shop draws, built the way the HUD builds it (ShopLayout.row with the same specs),
-- with the real prices: { name, cardW, cardH, specs, y, left, right }.
local function shopRows(): { any }
	local L = ShopLayout
	local rows = {}
	local function add(name: string, w: number, h: number, specs: { any }, y: number, left: number?, right: number?)
		table.insert(rows, { name = name, w = w, h = h, specs = specs, y = y, left = left, right = right })
	end
	local function robux(price: number, caption: string): { any }
		return { { kind = "gift" }, { kind = "buy", text = Format.commas(price), icon = true, caption = caption } }
	end
	for _, entry in Config.products("Pack") do
		add("pack " .. entry.name, L.CONTENT_W, L.PACK_H, robux(entry.product.robux, "Bag full!"), L.bottomY(L.PACK_H, true))
	end
	for _, kind in { "Speed", "Money" } do
		for _, entry in Config.products(kind) do
			add(`{kind} {entry.name}`, L.CARD_W, L.CARD_H, robux(entry.product.robux, "Instant"), L.bottomY(L.CARD_H, true))
		end
	end
	for _, name in Config.passNames() do
		local pass = Config.GAMEPASSES[name]
		add("pass " .. name, L.WIDE_W, L.WIDE_H, robux(pass.robux, "Forever"), L.bottomY(L.WIDE_H, true), 142, L.WIDE_W - L.MARGIN)
		add("owned pass " .. name, L.WIDE_W, L.WIDE_H, { { kind = "buy", text = "Owned" } }, L.bottomY(L.WIDE_H, true), 142, L.WIDE_W - L.MARGIN)
		add("banner " .. name, L.CONTENT_W, L.BANNER_H, robux(pass.robux, "Forever"), math.floor((L.BANNER_H - L.BUTTON_H - L.CAPTION_H) / 2),
			L.CONTENT_W - 420, L.CONTENT_W - 16)
	end
	-- upgrades: every plot level and treadmill tier, its $ price and R$ product side by side
	local function upgrade(name: string, price: number, product: any)
		local specs = { { kind = "buy", text = Format.money(price), caption = "Cash" } }
		if product then
			table.insert(specs, { kind = "buy", text = Format.commas(product.robux), icon = true, caption = "Instant" })
		end
		add(name, L.CARD_W, L.CARD_H, specs, L.bottomY(L.CARD_H, true))
	end
	for level = 1, Config.PLOT_LEVEL_MAX - 1 do
		upgrade(`plot {level}`, Config.plotUpgradePrice(level + 1), select(2, Config.plotUpgradeProduct(level)))
	end
	for tier = 1, Config.TREADMILL_MAX - 1 do
		upgrade(`treadmill {tier}`, Config.TREADMILL_TIERS[tier + 1].price, select(2, Config.treadmillUpgradeProduct(tier)))
	end
	add("bag full", L.CONTENT_W, L.PACK_H, robux(99999, "Bag full!"), L.bottomY(L.PACK_H, true))
	return rows
end

H.test("Shop buttons: rows like the reference, inside their card; a popped button never leaves its card or touches its neighbour", function()
	local L = ShopLayout
	H.eq(L.HOVER, tonumber(string.match(UiFx, "UiFx.HOVER = ([%d%.]+)")), "ShopLayout.HOVER is UiFx.HOVER")
	local rows = shopRows()
	H.ok(#rows > 20, `{#rows} rows`)
	for _, row in rows do
		local placed = L.row(row.specs, row.w, row.h, row.y, row.left, row.right)
		H.eq(#placed, #row.specs, row.name)
		for i, p in placed do
			local what = `{row.name} button {i}`
			H.ok(inside(p, row.w, row.h), `{what}: inside its card at rest`)
			H.ok(p.pop >= 1 and p.pop <= L.HOVER, `{what}: pops {p.pop}`)
			local popped = L.popped(p)
			H.ok(inside(popped, row.w, row.h), `{what}: inside its card when popped ({popped.x}, {popped.y}, {popped.w}, {popped.h})`)
			if p.captionRect then
				H.ok(inside(p.captionRect, row.w, row.h), `{what}: its caption inside the card`)
				H.ok(p.captionRect.y >= p.y + p.h, `{what}: its caption under it`)
			end
			if row.left then
				H.ok(p.x >= row.left and p.x + p.w <= (row.right or row.w), `{what}: in its span`)
			end
			for j = i + 1, #placed do
				H.ok(apart(popped, L.popped(placed[j])), `{what} and button {j}: apart when both pop`)
				H.ok(placed[j].x > p.x + p.w, `{what}: left to right`)
			end
			if p.kind == "gift" then
				H.eq(p.w, p.h, `{what}: a square gift button`)
				H.ok(placed[i + 1] and placed[i + 1].kind == "buy" and placed[i + 1].x - (p.x + p.w) <= 16, `{what}: right before its buy button`)
			end
		end
		-- centred in their span, not a full-width bar
		local first, last = placed[1], placed[#placed]
		local l, r = row.left or 0, row.right or row.w
		H.ok(math.abs((first.x - l) - (r - (last.x + last.w))) <= 1, `{row.name}: centred`)
		H.ok(last.x + last.w - first.x < (r - l) * 0.9 or row.w < 400, `{row.name}: sized to their content, not a full-width bar`)
	end
	-- sized to the price: a short price is a narrower button than a long one (from the minimum up)
	H.ok(L.buyWidth("12,345", true) > L.buyWidth("9", true), "content-sized")
	H.eq(L.buyWidth("9", true), L.MIN_BUY_W, "a minimum width")
	-- the buttons sit under the card's words (the amount label ends at 152 + 8 + 48)
	H.ok(L.bottomY(L.CARD_H, true) >= 152 + 8 + 48, "under the amount")
	H.ok(L.bottomY(L.PACK_H, true) >= 262 + 32 + 20, "under the pack's mutation and income lines")
	H.ok(L.bottomY(L.WIDE_H, true) >= 58 + 60, "under the pass's benefit")
end)

H.test("Shop buttons: the HUD builds every row with ShopLayout / ShopUi; ShopUi.button pops as much as its rect allows", function()
	local row = block(SHOP, "local function buttonRow(", "\n\tend\n")
	H.ok(string.find(row, "L.row(specs, cardW, cardH, y, left, right)", 1, true) ~= nil, "placed by ShopLayout.row")
	H.ok(string.find(row, "ShopUi.giftIcon(g, GIFT_PINK:Lerp(", 1, true) and string.find(row, "g.Activated:Connect(giftSoon)", 1, true), "a purple gift button with a white gift")
	H.ok(string.find(row, "ShopUi.price(b, p.text or \"\", spec.robux)", 1, true) and string.find(row, "ShopUi.caption(c, p, BUTTON_Z)", 1, true), "price and caption")
	for _, needle in {
		"buttonRow(c, L.CARD_W, L.CARD_H, L.bottomY(L.CARD_H, true), { robuxBuy(",
		"buttonRow(c, L.WIDE_W, L.WIDE_H, L.bottomY(L.WIDE_H, true), { buy }, 142, L.WIDE_W - L.MARGIN)",
		"buttonRow(c, PACK_W, L.BANNER_H, math.floor((L.BANNER_H - L.BUTTON_H - L.CAPTION_H) / 2), { buy }, PACK_W - 420, PACK_W - 16)",
		"buttonRow(c, L.CARD_W, L.CARD_H, L.bottomY(L.CARD_H, true), buys)",
	} do
		H.ok(string.find(SHOP, needle, 1, true) ~= nil, needle)
	end
	H.ok(not string.find(HUD, "SIDE_POP", 1, true) and not string.find(HUD, "buyPair", 1, true), "the old full-width pairs are gone")
	-- ShopUi on real instances
	local card = roblox.Instance.new("Frame")
	local placed = ShopLayout.row({ { kind = "gift" }, { kind = "buy", text = "1,600", icon = true, caption = "1 Seed" } }, 344, 300, ShopLayout.bottomY(300, true))
	local gift = ShopUi.button(card, placed[1], roblox.Color3.new(1, 0, 1), 7)
	ShopUi.giftIcon(gift, roblox.Color3.new(0.5, 0, 0.5))
	local buy = ShopUi.button(card, placed[2], roblox.Color3.new(0, 1, 0), 7)
	H.eq(buy:GetAttribute("PopScale"), placed[2].pop, "PopScale from the layout")
	H.ok(placed[2].pop < placed[1].pop, "the wide R$ button pops less than the square gift")
	H.eq(buy.Position, roblox.UDim2.fromOffset(placed[2].x, placed[2].y))
	H.eq(buy.Size, roblox.UDim2.fromOffset(placed[2].w, placed[2].h))
	H.ok(buy:FindFirstChildOfClass("UIStroke") and not buy:FindFirstChildOfClass("UICorner"), "square, outlined")
	H.ok(buy:FindFirstChild("BevelTop") ~= nil, "a lighter top half")
	H.eq(buy:FindFirstChild("BevelEdge"), nil, "no dark bottom band (owner 2026-10-15: studs everywhere now)")
	H.ok(gift:FindFirstChild("GiftIcon") ~= nil, "the drawn white gift")
	H.ok(ShopUi.caption(card, placed[2], 7) ~= nil, "the caption")
	local still = ShopUi.button(card, { kind = "buy", x = 0, y = 0, w = 10, h = 10, pop = 1 } :: any, roblox.Color3.new(), 1)
	H.eq(still:GetAttribute("NoPop"), true, "no room: no pop")
end)

H.test("Robux icon: the owner's white icon (icons/Robux.png), white and bold with a dark outline before the price", function()
	local png = fs.readFile("icons/Robux.png")
	local function u32(at: number): number
		local a, b, c, d = string.byte(png, at, at + 3)
		return ((a * 256 + b) * 256 + c) * 256 + d
	end
	H.eq(string.sub(png, 13, 16), "IHDR")
	H.eq(u32(17), 236, "the owner's robuxicon.png (236 px wide)")
	H.eq(u32(21), 260, "(260 px tall)")
	local saved = Config.ICONS.Robux
	Config.ICONS.Robux = 123
	local b = roblox.Instance.new("TextButton")
	b.Size = roblox.UDim2.fromOffset(160, 52)
	local label = ShopUi.price(b, "1,600", true)
	Config.ICONS.Robux = saved
	local holder = b:FindFirstChild("RobuxIcon")
	H.ok(holder ~= nil, "the icon before the price")
	H.eq(holder:FindFirstChild("Icon").Image, "rbxassetid://123")
	H.eq(holder:FindFirstChild("Icon").ImageColor3, roblox.Color3.new(1, 1, 1), "white")
	H.eq(holder:FindFirstChild("Outline").ImageColor3, ShopUi.INK, "a dark copy behind: the outline")
	H.eq(label.Text, "1,600")
	H.ok(label.Position.X.Offset >= holder.Position.X.Offset + holder.Size.X.Offset, "the number after the icon")
	H.eq(label.TextColor3, roblox.Color3.new(1, 1, 1), "white text")
	H.ok((label:FindFirstChildOfClass("UIStroke") :: any).Thickness >= 3, "bold outline")
	-- not uploaded: the words
	Config.ICONS.Robux = 0
	local b2 = roblox.Instance.new("TextButton")
	b2.Size = roblox.UDim2.fromOffset(160, 52)
	H.eq(ShopUi.price(b2, "1,600", true).Text, "R$ 1,600")
	Config.ICONS.Robux = saved
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
	local hud = block(HUD, "local function productCard(", "\n\tend\n")
	H.ok(string.find(hud, "ShopArt.build(c, level,", 1, true) ~= nil, "the Speed / Money cards draw it")
	H.ok(string.find(HUD, "if level > ShopArt.LEVELS / 2 then YELLOW_NUMBER else NUMBER_GREEN", 1, true) ~= nil, "big packs' amounts in yellow")
end)

H.test("ShopArt: the sack and the chest are drawn properly (outlined, lit, shaded pieces), for Speed and Money", function()
	local function names(box: any): { [string]: number }
		local seen = {}
		for _, d in box:GetDescendants() do
			seen[d.Name] = (seen[d.Name] or 0) + 1
		end
		return seen
	end
	local function lit(box: any): (number, number)
		local outlined, total = 0, 0
		for _, d in box:GetDescendants() do
			if d:IsA("Frame") and d.BackgroundTransparency < 0.5 and d.Name ~= "Fold" and d.Name ~= "Plank" and d.Name ~= "Rivet" and d.Name ~= "Keyhole" then
				total += 1
				outlined += if d:FindFirstChildOfClass("UIStroke") then 1 else 0
			end
		end
		return outlined, total
	end
	for _, key in { "Speed", "Money" } do
		local card = roblox.Instance.new("Frame")
		local sack = ShopArt.build(card, 6, roblox.UDim2.new(0.5, 0, 0, 2), 150, { key = key, sackColor = roblox.Color3.fromRGB(214, 158, 92), zindex = 2 })
		local seen = names(sack)
		for _, part in { "Sack", "Mouth", "Rim", "Neck", "Rope", "Knot", "Loop", "RopeEnd", "Fold", "Highlight", "Shade", "Patch", "Shadow", "Sparkle" } do
			H.ok(seen[part], `{key} sack: {part}`)
		end
		H.eq(seen.Fold, 3, "three folds")
		H.eq(seen.Loop, 2, "a bow: two loops")
		local outlined, total = lit(sack)
		H.ok(outlined >= 8, `{key} sack: {outlined} of {total} solid pieces outlined`)
		local rope = sack:FindFirstChild("Rope") :: any
		H.ok(#rope:FindFirstChildOfClass("UIGradient").Color.Keypoints >= 8, "a twisted rope")
		local chest = ShopArt.build(card, 8, roblox.UDim2.new(0.5, 0, 0, 2), 150, { key = key, sackColor = roblox.Color3.new(0, 0, 1), zindex = 2 })
		seen = names(chest)
		for _, part in { "Lid", "Trim", "Inside", "Chest", "Plank", "Rim", "Base", "Strap", "Rivet", "Lock", "Keyhole", "Sparkle", "Shadow" } do
			H.ok(seen[part], `{key} chest: {part}`)
		end
		H.ok(seen.Strap >= 4, "gold straps on the lid and the box")
		H.eq(seen.Coin ~= nil, key == "Money", "gold coins spill from the Money chest only")
		H.ok(chest:FindFirstChild("Item8") ~= nil, "every item")
		-- the heap sits inside: under the box's front, over the dark inside; the spilled items in front of all
		local inner, front = chest:FindFirstChild("Item1") :: any, chest:FindFirstChild("Item7") :: any
		local box, inside = chest:FindFirstChild("Chest") :: any, chest:FindFirstChild("Inside") :: any
		H.ok(inside.ZIndex < inner.ZIndex and inner.ZIndex < box.ZIndex and box.ZIndex < front.ZIndex, "layered: inside < heap < box < spilled")
	end
end)

H.test("HUD left column: wide Shop / Index buttons (icon left, word right in relief), popping within their gap", function()
	local w, h = string.match(HUD, "local SIDE_W, SIDE_H = (%d+), (%d+)")
	w, h = tonumber(w), tonumber(h)
	H.ok(w and h and w / h >= 2.4 and w / h <= 2.8, "about 2.6:1")
	local side = block(HUD, "local function sideButton(", "\nend\n")
	H.ok(string.find(side, "deco(4, 4)", 1, true) and string.find(side, "ShopUi.bevel(b)", 1, true), "square-ish, thick outline, lit top")
	H.ok(string.find(side, "BackgroundColor3 = color", 1, true) ~= nil and not string.find(side, "UIGradient", 1, true), "a flat vivid colour")
	H.ok(string.find(side, "AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, -1)", 1, true) ~= nil, "the icon on the left")
	H.ok(string.find(side, "UiFx.relief(bold(b, 4, { Text = label", 1, true) and string.find(side, "TextXAlignment = Enum.TextXAlignment.Left", 1, true), "the word on its right, in relief")
	H.ok(string.find(HUD, "sideButton(1, \"Shop\", \"Shop\", \"🛒\", Color3.fromRGB(95, 230, 45)", 1, true) ~= nil, "Shop bright green")
	H.ok(string.find(HUD, "sideButton(2, \"Index\", \"Index\", \"📖\", Color3.fromRGB(35, 195, 255)", 1, true) ~= nil, "Index bright cyan")
	-- the pop (UiFx.HOVER, about its centre, outline 4 included) stays in the column's gap and on screen
	local gap = tonumber(string.match(HUD, "local LEFT_GAP = (%d+)"))
	local grow = (ShopLayout.HOVER - 1) / 2
	if w and h and gap then
		H.ok((h + 8) * grow < gap / 2, "never over the next button")
		H.ok((w + 8) * grow < 14, "never off the screen's left edge (the column is 14 px in)")
	end
	H.ok(string.find(HUD, "UiFx.relief(bold(slowRow, 3, { Text = \"Slow Mode\"", 1, true) ~= nil, "Slow Mode in relief, like them")
end)

H.test("Shop SEED PACKS: the owner's pictures as the pack cards' backgrounds once uploaded (the zone colours until then)", function()
	for _, entry in Config.products("Pack") do
		local key = entry.name .. "Bg"
		H.ok(Config.ICONS[key] ~= nil, `icons/ids.json has {key}`)
		H.ok(fs.isFile(`icons/{key}.png`), `icons/{key}.png (uploaded by tools/upload_icons.luau)`)
		H.eq(Icons.TEXTURES[key], true, `{key} is a picture, not an emoji's icon`)
	end
	local shop = block(HUD, "local function packCard(", "\n\tend\n")
	H.ok(string.find(shop, "local picture = Icons.image(productName .. \"Bg\")", 1, true) ~= nil, "looked up by the pack's product")
	H.ok(string.find(shop, "ScaleType = Enum.ScaleType.Crop, Size = UDim2.fromScale(1, 1)", 1, true) ~= nil, "the whole card, cropped")
	local darken = string.match(shop, "Name = \"Darken\".-NumberSequence.new(%b())")
	H.ok(darken ~= nil, "a dark gradient over it")
	local last = tonumber(darken and string.match(darken, "NumberSequenceKeypoint.new%(1, ([%d%.]+)%)"))
	H.ok(last and last <= 0.3, "darkest at the bottom (the buttons and the %)")
	H.ok(string.find(shop, "else\n\t\t\tsunburst(c, 0.86, 0.42, 560)", 1, true) ~= nil, "the sunbursts while the picture isn't uploaded")
end)

return nil
