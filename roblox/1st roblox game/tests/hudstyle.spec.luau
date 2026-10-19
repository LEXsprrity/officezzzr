-- The owner's 2026-10-15 HUD style pass (round 3): every HUD element in the classic Roblox studded plastic
-- (one shared helper, ShopUi.studs: the uploaded Studs texture, one stud size everywhere, the window body's
-- studs the same as its title bar's), the hotbar's dark see-through slots with a drawn bat, the shared
-- announcement look (Shared/Toast), the bigger Speed / money readout (no VIP badge any more), the plot
-- signs without their icon and the owner's Robux icon as the only Robux icon.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local H = require("./harness")

local Config = H.shared("Config")
local ShopUi = H.shared("ShopUi")

local function read(path: string): string
	return (string.gsub(fs.readFile(path), "\r", ""))
end
local HUD = read("src/client/HUD.client.luau")
local REWARDS = read("src/client/Rewards.client.luau")
local PLANTING = read("src/client/Planting.client.luau")
local SHOP_UI = read("src/shared/ShopUi.luau")

local function block(source: string, from: string, to: string): string
	local a = string.find(source, from, 1, true)
	local b = a and string.find(source, to, a + #from, true)
	return if a and b then string.sub(source, a, b) else ""
end

-- Runs fn with Config.ICONS.Studs = id, then puts it back.
local function withStuds(id: number, fn: () -> ())
	local saved = Config.ICONS.Studs
	Config.ICONS.Studs = id
	local ok, err = pcall(fn)
	Config.ICONS.Studs = saved
	if not ok then
		error(err, 0)
	end
end

----------------------------------------------------------------------------------------------------
-- The studs helper
----------------------------------------------------------------------------------------------------
H.test("studs: the uploaded Studs texture, tiled at one size everywhere, tinted to the frame's colour", function()
	local ids = serde.decode("json", fs.readFile("icons/ids.json"))
	H.ok(type(ids.Studs) == "number" and ids.Studs > 0, "the Studs texture is uploaded")
	H.ok(ShopUi.STUD_CELL >= 14 and ShopUi.STUD_CELL <= 32, "a fine stud")
	withStuds(ids.Studs, function()
		local f = roblox.Instance.new("Frame")
		f.Size = roblox.UDim2.fromOffset(200, 80)
		local corner = roblox.Instance.new("UICorner")
		corner.CornerRadius = roblox.UDim.new(0, 6)
		corner.Parent = f
		local green = roblox.Color3.fromRGB(95, 230, 45)
		local layer = ShopUi.studs(f, green)
		H.eq(layer.ClassName, "ImageLabel")
		H.eq(layer.Name, "Studs")
		H.eq(layer.Parent, f)
		H.eq(layer.Image, `rbxassetid://{ids.Studs}`, "the uploaded texture, not the drawn fallback")
		H.eq(layer.ScaleType, roblox.Enum.ScaleType.Tile)
		H.eq(layer.TileSize, roblox.UDim2.fromOffset(ShopUi.STUD_CELL, ShopUi.STUD_CELL), "one stud size")
		H.near(layer.ImageTransparency, ShopUi.STUD_FADE, 1e-5, "subtle, behind the words")
		H.eq(layer.ImageColor3, ShopUi.studTint(green), "tinted to the frame's colour")
		H.eq(layer.ImageColor3, green:Lerp(roblox.Color3.new(1, 1, 1), ShopUi.STUD_TINT))
		local copied = layer:FindFirstChildOfClass("UICorner")
		H.ok(copied ~= nil and copied.CornerRadius == corner.CornerRadius, "a rounded frame's studs follow its corners")
		H.eq(layer.ZIndex, f.ZIndex, "under the frame's words (made first)")
		ShopUi.paintStuds(f, roblox.Color3.fromRGB(35, 195, 255))
		H.eq(layer.ImageColor3, ShopUi.studTint(roblox.Color3.fromRGB(35, 195, 255)), "re-tinted when the frame's colour changes")
		local square = roblox.Instance.new("Frame")
		H.eq(ShopUi.studs(square, nil, nil, 3):FindFirstChildOfClass("UICorner"), nil, "a square frame's studs are square")
		H.eq(square:FindFirstChild("Studs").ZIndex, 3)
		H.eq(square:FindFirstChild("Studs").ImageColor3, roblox.Color3.new(1, 1, 1), "no colour: white")
	end)
	withStuds(0, function()
		local f = roblox.Instance.new("Frame")
		f.Size = roblox.UDim2.fromOffset(180, 54)
		local layer = ShopUi.studs(f, roblox.Color3.new(1, 0, 0))
		H.eq(layer.ClassName, "Frame", "id 0: the drawn studs")
		H.ok(layer:FindFirstChildOfClass("UIGridLayout") ~= nil, "a grid of small squares")
		H.eq(layer:FindFirstChildOfClass("UIGridLayout").CellPadding, roblox.UDim2.fromOffset(ShopUi.STUD_CELL / 2, ShopUi.STUD_CELL / 2), "the same stud size")
		local squares = 0
		for _, c in layer:GetChildren() do
			squares += if c:IsA("Frame") then 1 else 0
		end
		H.ok(squares >= math.ceil(180 / ShopUi.STUD_CELL) * math.ceil(54 / ShopUi.STUD_CELL), `enough squares to cover it ({squares})`)
	end)
	-- one style: no caller picks its own stud size or texture
	local studs = block(SHOP_UI, "function ShopUi.studs(", "\nend")
	H.ok(string.find(studs, "Icons.image(\"Studs\")", 1, true) and string.find(studs, "TileSize = UDim2.fromOffset(cell, cell)", 1, true)
		and string.find(studs, "local cell = ShopUi.STUD_CELL", 1, true), "the texture at ShopUi.STUD_CELL")
	for _, dir in { "src/client", "src/shared" } do
		for _, entry in fs.readDir(dir) do
			local source = read(dir .. "/" .. entry)
			for args in string.gmatch(source, "ShopUi%.studs(%b())") do
				H.ok(not string.match(args, "^%([^,]+, %d"), `{entry}: ShopUi.studs{args} sets no size of its own`)
			end
			if entry ~= "ShopUi.luau" then
				H.ok(not string.find(source, "TileSize", 1, true), `{entry}: no studs of its own`)
			end
		end
	end
end)

H.test("studs: on every HUD element (left column, Plants panel, readout, windows, cards, timer, banner, VIP, toasts)", function()
	local function has(source: string, from: string, to: string, needle: string, what: string)
		local b = block(source, from, to)
		H.ok(b ~= "", `{what}: its block`)
		H.ok(string.find(b, needle, 1, true) ~= nil, `{what}: {needle}`)
	end
	-- the left column and the Speed readout's "+"
	has(HUD, "local function sideButton(", "\nend\n", "ShopUi.studs(b, color)", "Shop / Index buttons")
	H.ok(string.find(HUD, "ShopUi.studs(track, nil)", 1, true) ~= nil, "Slow Mode switch")
	H.ok(string.find(HUD, "ShopUi.studs(plusBadge,", 1, true) ~= nil, "the Speed's + badge")
	-- the Plants panel: its side button (button()), the panel, its tabs (chunky), its cards
	has(HUD, "local function button(", "\nend\n", "ShopUi.studs(b, color)", "the Plants side button")
	H.ok(string.find(HUD, "ShopUi.studs(sidePanel, COLORS.panel)", 1, true) ~= nil, "the Plants panel")
	has(HUD, "local function chunky(", "\nend\n", "ShopUi.studs(b, nil)", "chunky buttons (tabs, Remove, Plant, Sell, Equip)")
	has(HUD, "local function card(", "\nend\n", "ShopUi.studs(f, color)", "the Plants list's cards")
	has(HUD, "local function plantCard(", "\n\tend\n", "ShopUi.studs(f, accent)", "plant cards")
	has(HUD, "local function itemCard(", "\n\tend\n", "ShopUi.studs(f, accent)", "Inventory cards")
	-- the windows: frame, Shop cards (packs, passes, banners, Speed / Money / upgrades), Trail, Index, Sell, reveal
	has(HUD, "local function cardFrame(", "\n\tend\n", "ShopUi.studs(c, if rainbow then nil else color, nil, 1)", "every Shop card")
	H.ok(string.find(HUD, "studLayer.ZIndex = 2 -- the studs over the picture too", 1, true) ~= nil, "pack cards with a picture")
	has(HUD, "local function trailCard(", "\n\tend\n", "ShopUi.studs(c, if t.rainbow then nil else t.color)", "Trail cards")
	has(HUD, "local function renderIndex()", "\nend\n", "ShopUi.studs(row, zone.ui)", "Index rows")
	has(HUD, "local function renderIndex()", "\nend\n", "ShopUi.studs(cell, if got then rarity.color else zone.ui)", "Index cells")
	has(HUD, "local function cardBase(", "\n\tend\n", "ShopUi.studs(c, body)", "Sell cards (their rarity's colour)")
	has(HUD, "local function cardBase(", "\n\tend\n", "ShopUi.studs(band, rarity.color)", "Sell cards' bands")
	H.ok(string.find(HUD, "ShopUi.studs(panel, Color3.fromRGB(75, 40, 140), nil, 1)", 1, true) ~= nil, "the pack reveal's panel")
	H.ok(string.find(HUD, "ShopUi.studs(f, r.color, nil, 3)", 1, true) ~= nil, "the reveal's seed cards")
	-- the Free Gift window: body and title bar in the same studs, its buttons too
	H.ok(string.find(REWARDS, "ShopUi.studs(studs, BODY_COLOR, nil, 1)", 1, true) and string.find(REWARDS, "ShopUi.studs(titleBar, CYAN_TO, nil, 2)", 1, true),
		"Free Gift body and title bar")
	H.ok(string.find(REWARDS, "ShopUi.studs(b, nil, nil, 3)", 1, true) ~= nil, "Free Gift buttons")
	H.ok(not string.find(REWARDS, "BackgroundTransparency = 0.955", 1, true), "its own drawn studs are gone")
	-- the day/night timer, the zone banner, the VIP badge, the toasts
	H.ok(string.find(read("src/client/DayTimer.client.luau"), "ShopUi.studs(strip,", 1, true) ~= nil, "day/night timer strip")
	H.ok(string.find(read("src/client/ZoneBanner.client.luau"), "ShopUi.studs(dark,", 1, true) ~= nil, "zone banner strip")
	H.ok(string.find(read("src/shared/Toast.luau"), "ShopUi.studs(plate, color, nil, 1)", 1, true) ~= nil, "toasts")
	-- the hotbar's slots are the owner's dark see-through squares instead (their own request overrides studs there)
	H.ok(not string.find(block(HUD, "local batSlot", "local batShade"), "ShopUi.studs", 1, true), "no studs on the Bat slot")
end)

----------------------------------------------------------------------------------------------------
-- Hotbar
----------------------------------------------------------------------------------------------------
H.test("hotbar: small dark see-through slots, the number top-left, a drawn bat and the seed, white outline when picked", function()
	local b = roblox.Instance.new("TextButton")
	local key = ShopUi.slot(b, "2")
	H.eq(b.Size, roblox.UDim2.fromOffset(ShopUi.SLOT, ShopUi.SLOT), "square")
	H.ok(b.BackgroundTransparency >= 0.3 and b.BackgroundTransparency <= 0.5, "dark, about 40% see-through")
	local h, s, v = b.BackgroundColor3:ToHSV()
	H.ok(v < 0.2, `dark ({h}, {s}, {v})`)
	H.eq(b.Text, "")
	H.eq(b:FindFirstChildOfClass("UICorner"), nil, "square")
	local stroke = b:FindFirstChild("Outline")
	H.ok(stroke and stroke.Thickness <= 2, "a thin darker outline")
	H.eq(key.Text, "2")
	H.ok(key.Position.X.Offset < 10 and key.Position.Y.Offset < 10 and key.Size.Y.Offset <= 20, "small, top-left")
	H.eq(key.TextColor3, roblox.Color3.new(1, 1, 1), "white")
	ShopUi.selectSlot(b, true)
	H.eq(stroke.Color, roblox.Color3.new(1, 1, 1), "picked: a white outline")
	ShopUi.selectSlot(b, false)
	H.ok(stroke.Color ~= roblox.Color3.new(1, 1, 1), "not picked: dark")

	local bat = block(HUD, "local batSlot", "local batShade")
	H.ok(string.find(bat, "ShopUi.slot(batSlot, \"1\")", 1, true) ~= nil, "slot 1 in the hotbar's look")
	H.ok(string.find(bat, "Name = \"Bat\"", 1, true) and string.find(bat, "Rotation = 42", 1, true), "a bat drawn diagonally (the stand-in)")
	-- the bat itself in 3D (owner 2026-10-19), from the Tool in the Backpack or the hand; the drawn one until then
	H.ok(string.find(HUD, "local ToolView = require(Shared:WaitForChild(\"ToolView\"))", 1, true) ~= nil, "uses Shared/ToolView")
	H.ok(string.find(bat, "ToolView.show(batSlot, tool, { size = UDim2.new(1, -4, 1, -4), position = UDim2.fromOffset(2, 2), zindex = 2 })", 1, true) ~= nil,
		"the 3D bat fills the slot like the seed, under the number and the cooldown shade")
	H.ok(string.find(bat, "batArt.Visible = false", 1, true) ~= nil, "the drawn bat hides once the 3D one shows")
	H.ok(string.find(bat, "if batView or not (tool and tool:IsA(\"Tool\")) then", 1, true) ~= nil, "built once, from a Tool")
	H.ok(string.find(bat, "child:IsA(\"Backpack\")", 1, true) and string.find(bat, "me.CharacterAdded:Connect(watchFor)", 1, true),
		"found in the Backpack (each respawn) or in hand")
	H.ok(string.find(bat, "tool.ChildAdded:Once(", 1, true) ~= nil, "retried while its parts replicate")
	H.ok(not string.find(bat, "Icons.set", 1, true), "no 2D icon")
	H.ok(not string.find(bat, "\"Bat\")", 1, true) and not string.find(bat, "Bat\\n", 1, true) and not string.find(HUD, "\"🏏\\nBat\"", 1, true),
		"no Bat name, no hammer icon")
	H.ok(not string.find(bat, "Color3.fromRGB(200, 140, 80)", 1, true), "no brown slot background")
	H.ok(string.find(PLANTING, "ShopUi.slot(seedSlot, \"2\")", 1, true) ~= nil, "slot 2 in the same look")
	H.ok(string.find(PLANTING, "ShopUi.selectSlot(seedSlot, picked)", 1, true) ~= nil, "picked: white outline")
	H.ok(not string.find(PLANTING, "SEED_GREEN", 1, true), "no green slot background")
	H.ok(not string.find(PLANTING, "\"🌱\\nSeeds\"", 1, true), "no Seeds name under the icon")
	H.ok(string.find(PLANTING, "slotView.Size = UDim2.new(1, -4, 1, -4) -- the seed fills the slot", 1, true) ~= nil, "the seed's 3D fills the slot")
	H.ok(string.find(PLANTING, "slotCount.Text = `x{count}`", 1, true) and string.find(PLANTING, "UiFx.relief(slotCount, 2, 2)", 1, true), "x3 in white relief")
end)

----------------------------------------------------------------------------------------------------
-- Announcements
----------------------------------------------------------------------------------------------------
H.test("toasts: one announcement look (studded plate, bevel, icon, chunky relief words, pop in, fade out)", function()
	-- UiFx needs these services to load; relief needs property signals Lune lacks (it's checked elsewhere)
	local saved = { RunService = H.services.RunService, TweenService = H.services.TweenService, UserInputService = H.services.UserInputService }
	local played = 0
	H.services.RunService = { RenderStepped = { Connect = function() end }, Heartbeat = { Connect = function() end } }
	H.services.TweenService = { Create = function() return { Play = function() played += 1 end } end }
	H.services.UserInputService = { GetLastInputType = function() return nil end }
	local UiFx = H.shared("UiFx")
	local relief = UiFx.relief
	local reliefs = 0
	UiFx.relief = function(l: any)
		reliefs += 1
		return l
	end
	local ok, err = pcall(function()
		local Toast = H.shared("Toast")
		local savedIds = table.clone(Config.ICONS)
		Config.ICONS.Lock, Config.ICONS.Star, Config.ICONS.Studs = 11, 22, 33
		local holder = roblox.Instance.new("Frame")
		local plate, words = Toast.build(holder, "Not enough money!", { color = "red" })
		H.eq(plate.Name, "Toast")
		H.eq(plate:FindFirstChildOfClass("UICorner"), nil, "square")
		local stroke = plate:FindFirstChildOfClass("UIStroke")
		H.ok(stroke and stroke.Thickness >= 4 and stroke.Color == ShopUi.INK, "a thick dark outline")
		H.ok(plate:FindFirstChild("Studs") and plate:FindFirstChild("Studs").Image == "rbxassetid://33", "studded")
		H.ok(plate:FindFirstChild("BevelTop") ~= nil, "a lighter top band")
		H.ok(plate:FindFirstChild("Shine") ~= nil, "a shine")
		H.eq(plate:FindFirstChild("Icon").Image, "rbxassetid://11", "errors: the lock")
		H.eq(words.Text, "Not enough money!")
		H.ok(words.TextScaled and words.Font == roblox.Enum.Font.FredokaOne, "big chunky words")
		H.ok(words:FindFirstChildOfClass("UIStroke").Thickness >= 3, "a thick outline")
		H.eq(reliefs, 1, "in relief")
		local _, w2 = Toast.build(holder, "The sun is up.", { color = "blue", icon = "Sun" })
		H.ok(w2.Parent:FindFirstChild("Icon"):IsA("Frame"), "day and night: a drawn sun / moon")
		local big = Toast.build(holder, "Alex got a LEGENDARY Starpetal!", { color = "gold", big = true })
		H.ok(big.Size.Y.Offset > plate.Size.Y.Offset and big.Size.X.Offset > plate.Size.X.Offset, "announcements are bigger")
		H.ok(big:FindFirstChildOfClass("UIStroke"):FindFirstChild("Rainbow") ~= nil, "...with a rainbow frame")
		H.eq(big:FindFirstChild("Icon").Image, "rbxassetid://22", "...and the star")
		-- the icon is chosen per message, never by the colour (owner 2026-10-15: "+25,000 Speed!" showed the cash)
		Config.ICONS.Speed, Config.ICONS.Money, Config.ICONS.Gift = 44, 55, 66
		local speed = Toast.build(holder, "+25,000 Speed! Thanks for joining the community!", { color = "gold", icon = Toast.ICONS.speed })
		H.eq(speed:FindFirstChild("Icon").Image, "rbxassetid://44", "a Speed gain: the sneaker")
		H.eq(Toast.build(holder, "+$5", { color = "gold", icon = Toast.ICONS.money }):FindFirstChild("Icon").Image, "rbxassetid://55", "money: the cash")
		H.eq(Toast.build(holder, "Gifting is coming soon!", { color = "blue", icon = Toast.ICONS.gift }):FindFirstChild("Icon").Image, "rbxassetid://66", "the gift")
		H.eq(Toast.build(holder, "Something good", { color = "gold" }):FindFirstChild("Icon"), nil, "gold alone guesses no icon (no cash)")
		H.eq(Toast.build(holder, "Something", { color = "green" }):FindFirstChild("Icon"), nil, "neither does green")
		H.eq(Toast.STYLES.red.icon, Toast.ICONS.error, "errors: the lock")
		H.eq(Toast.ICONS.legendary, "Star")
		H.eq(Toast.ICONS.day, "Sun")
		H.eq(Toast.ICONS.night, "Moon")
		local slot = Toast.show(holder, "Hi", { color = "green", seconds = 2 })
		H.ok(slot:FindFirstChildOfClass("CanvasGroup") ~= nil and played >= 3, "it pops and slides in (and fades out as one)")
		local colours = {}
		for name, style in Toast.STYLES do
			colours[name] = style.color
		end
		H.ok(colours.red and colours.gold and colours.green and colours.blue and colours.purple, "a vivid colour per kind")
		table.clear(Config.ICONS)
		for k, v in savedIds do
			Config.ICONS[k] = v
		end
	end)
	UiFx.relief = relief
	for k, v in saved do
		H.services[k] = v
	end
	if not ok then
		error(err, 0)
	end
	-- every announcement uses it: the HUD's toasts, the day/night ones with the sun / moon, the server-wide
	-- ones big, the "Lucky!" over a thief's head
	H.ok(string.find(HUD, "Toast.show(toastHolder, message, { color = color, seconds = seconds, icon = icon, big = big })", 1, true) ~= nil, "HUD toasts")
	H.ok(string.find(HUD, "if data.night then \"Moon\" else \"Sun\")", 1, true) ~= nil, "day / night icons")
	H.ok(string.find(HUD, "toast(data.text, data.color, 6, \"Star\", true)", 1, true) ~= nil, "server-wide announcements: big, the star")
	H.ok(not string.find(HUD, "TOAST_COLORS", 1, true) and not string.find(block(HUD, "local function toast(", "\nend\n"), "deco(", 1, true),
		"the flat rounded bar is gone")
	local effects = read("src/client/Effects.client.luau")
	H.ok(string.find(effects, "Toast.build(gui, `Lucky! {from.id} > {to.id}`, { color = \"purple\", icon = \"Star\" })", 1, true) ~= nil, "Lucky!")
end)

H.test("toasts: each message names its icon (the Free Gift's +Speed shows the sneaker, not the cash)", function()
	local Rewards = H.server("Rewards")
	local text, color, icon = Rewards.giftMessage("granted")
	H.ok(string.find(text, "Speed!", 1, true) ~= nil and color == "gold", text)
	H.eq(icon, "Speed", "the claimed Free Gift: the sneaker")
	H.eq(select(3, Rewards.giftMessage("soon")), "Gift")
	H.eq(select(3, Rewards.giftMessage("claimed")), "Gift")
	H.eq(select(3, Rewards.giftMessage("notMember")), nil, "refusals: red's lock")
	-- the server sends the icon and the client shows it
	local net = read("src/server/Net.luau")
	H.ok(string.find(net, "function Net.toast(player: Player, text: string, color: string?, icon: string?)", 1, true)
		and string.find(net, "{ text = text, color = color, icon = icon }", 1, true), "Net.toast carries the icon")
	H.ok(string.find(read("src/server/RewardService.luau"), "local text, color, icon = Rewards.giftMessage(result)\n\tNet.toast(player, text, color, icon)", 1, true) ~= nil,
		"the gift claim passes it")
	H.ok(string.find(HUD, "toast(data.text, data.color, nil, data.icon)", 1, true) ~= nil, "the HUD shows the server's icon")
	H.ok(string.find(HUD, "toast(\"Gifting is coming soon!\", \"blue\", nil, \"Gift\")", 1, true) ~= nil, "gifting: the gift")
	H.ok(string.find(HUD, "\"gold\", 7, \"Money\", true)", 1, true) ~= nil, "offline earnings: the cash, as a big welcome-back plate")
	-- every gold / green toast the server sends names its icon (red brings the lock, blue news may go bare)
	for _, file in fs.readDir("src/server") do
		if string.sub(file, -5) == ".luau" then
			for line in string.gmatch(read("src/server/" .. file), "[^\n]+") do
				if string.find(line, "Net.toast(", 1, true) and (string.find(line, "\"gold\"", 1, true) or string.find(line, "\"green\"", 1, true)) then
					H.ok(string.find(line, "\"gold\", \"%u") ~= nil or string.find(line, "\"green\", \"%u") ~= nil, `{file}: {line}`)
				end
			end
		end
	end
	H.ok(string.find(read("src/server/ShopService.luau"), "Speed gain`, \"blue\", \"Speed\")", 1, true) ~= nil, "a trail equipped: the sneaker")
end)

----------------------------------------------------------------------------------------------------
-- Readout, VIP badge, pass Owned, plot sign, Robux
----------------------------------------------------------------------------------------------------
H.test("readout: Speed and money about 2x bigger in chunky italic, no VIP badge, the + clear of the digits, clear of the column and the hotbar", function()
	local stats = block(HUD, "local statsFrame = new(\"Frame\", {", "plusBadge.Activated")
	H.ok(string.find(stats, "Name = \"Stats\"", 1, true) and string.find(stats, "Size = UDim2.fromOffset(470, STATS_H)", 1, true), "a wider readout")
	H.eq(tonumber(string.match(HUD, "local STATS_H, LEFT_H = (%d+),")), 176, "about twice as tall (was 100)")
	H.ok(select(2, string.gsub(stats, "Size = UDim2.fromOffset%(84, 84%)", "")) >= 2, "big icons (84, was 48)")
	H.ok(string.find(stats, "Text = \"0\", Size = UDim2.new(1, -152, 0, 80), Position = UDim2.fromOffset(98, 2)", 1, true)
		and string.find(stats, "Text = \"$0\", Size = UDim2.new(1, -100, 0, 80), Position = UDim2.fromOffset(98, 94)", 1, true), "huge numbers (80 tall, was 44)")
	-- the yellow "+" (owner 2026-10-15: it sat over the Speed number): just past the number's right end, on its row
	H.ok(string.find(stats, "Name = \"Plus\", Size = UDim2.fromOffset(44, 44), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(98 + 10, 42)", 1, true) ~= nil,
		"the + starts right of where the number starts")
	H.ok(string.find(stats, "plusBadge.Position = UDim2.fromOffset(math.min(98 + wide + 10, 470 - 44), 42)", 1, true)
		and string.find(stats, "speedValue:GetPropertyChangedSignal(\"TextBounds\"):Connect(placePlus)", 1, true), "...and follows its right end")
	local numberEnd = 98 + (470 - 152)
	H.ok(numberEnd + 10 <= 470 - 44, "the widest Speed number still leaves the + its room inside the readout")
	H.ok(98 + 10 > 84, "never over the sneaker either")
	H.ok(42 - 22 >= 2 and 42 + 22 <= 94, "on the Speed row, clear of the money")
	H.ok(not string.find(stats, "Position = UDim2.fromOffset(54, 50)", 1, true), "the old corner spot is gone")
	H.ok(select(2, string.gsub(stats, "Enum.FontStyle.Italic", "")) == 2, "italic")
	H.ok(string.find(stats, "UiFx.relief(speedValue, 6, 6)", 1, true) and string.find(stats, "UiFx.relief(moneyValue, 6, 6)", 1, true), "thick dark outlines")
	local fit = block(HUD, "local function fitLeftColumn()", "\nend\n")
	H.ok(string.find(fit, "fit.Scale = math.clamp((gui.AbsoluteSize.X / uiScale.Scale / 2 - 110 - 14) / 470, 0.5, 1)", 1, true) ~= nil,
		"shrinks on narrow screens so it never reaches the hotbar")
	H.ok(string.find(fit, "height / 2 - STATS_BOTTOM - STATS_H * fit.Scale - 10", 1, true) ~= nil,
		"the left column stops above the readout")
	H.ok(ShopUi.SLOT * 2 + 8 <= 2 * 110, "the hotbar fits in the room left for it")
	-- no VIP badge in the HUD any more (owner 2026-10-15; the tag over the head stays)
	H.ok(not fs.isFile("src/client/VipHudBadge.client.luau"), "VipHudBadge.client is gone")
	H.ok(not string.find(HUD, "VipHudBadge", 1, true) and not string.find(HUD, "64 * fit.Scale", 1, true), "and no room kept for it")
end)

H.test("passes: Owned is a bright gold button; plot signs show only the name; the owner's Robux icon is the only one", function()
	local PassCards = H.shared("PassCards")
	local r, g, b = PassCards.OWNED.R * 255, PassCards.OWNED.G * 255, PassCards.OWNED.B * 255
	H.ok(r > 230 and g > 160 and b < 90, "Owned: bright gold")
	H.ok(not string.find(HUD, "text = \"Owned\", color = COLORS.disabled", 1, true), "no grey Owned")
	-- plot owner signs: no Home icon
	local plot = read("src/server/PlotService.luau")
	H.ok(string.find(plot, "Icons.set(state.info.signLabel, {}, `{s.player.DisplayName}'s Plot`)", 1, true) ~= nil, "an owned plot: the name")
	H.ok(string.find(plot, "Icons.set(state.info.signLabel, {}, WorldBuilder.EMPTY_PLOT)", 1, true) ~= nil, "a free plot: Empty Plot")
	H.ok(not string.find(plot, "\"Home\"", 1, true), "no Home icon on them")
	-- Robux: only Icons "Robux" (icons/Robux.png, the owner's icon), drawn white / as is, never another image or glyph
	local ids = serde.decode("json", fs.readFile("icons/ids.json"))
	H.eq(ids.Robux, 136761121783815, "the owner's uploaded Robux icon")
	local robuxPng = fs.readFile("icons/Robux.png")
	H.eq(string.sub(robuxPng, 2, 4), "PNG")
	for _, dir in { "src/client", "src/shared", "src/server", "src/server/Zones" } do
		for _, entry in fs.readDir(dir) do
			if string.match(entry, "%.luau$") then
				local source = read(dir .. "/" .. entry)
				H.ok(not string.find(source, "rbxassetid://%d"), `{entry}: no hard-coded image id (Robux or other)`)
				H.ok(not string.find(source, "\u{E002}", 1, true), `{entry}: no Roblox Robux glyph`)
				H.ok(not string.find(string.lower(source), "hexagon", 1, true), `{entry}: no drawn Robux hexagon`)
				for line in string.gmatch(source, "[^\n]+") do
					if string.find(line, "Icons.image(\"Robux\")", 1, true) or string.find(line, "\"Robux\" }", 1, true) then
						H.ok(not string.find(line, "ImageColor3 = ROBUX_GREEN", 1, true) and not string.find(line, "ImageColor3 = COLORS", 1, true),
							`{entry}: the Robux icon is never tinted: {line}`)
					end
				end
			end
		end
	end
	H.ok(string.find(SHOP_UI, "Name = \"Icon\", BackgroundTransparency = 1, Image = image, ImageColor3 = WHITE", 1, true) ~= nil,
		"the buy buttons' Robux icon: white, as is")
	for key, id in ids do
		H.ok(key == "Robux" or id ~= ids.Robux, `{key}: not the Robux image`)
	end
end)


H.test("seed packs: each reward tile's rarity name and % in its rarity's colour, thick dark outline", function()
	local SeedPacks = H.shared("SeedPacks")
	for r, rarity in Config.RARITIES do
		local c = SeedPacks.tileTextColor(r)
		local want = rarity.color:Lerp(roblox.Color3.new(1, 1, 1), SeedPacks.TEXT_LIFT)
		H.ok(math.abs(c.R - want.R) + math.abs(c.G - want.G) + math.abs(c.B - want.B) < 1e-6, `{rarity.id}: its colour, brightened`)
		H.ok(c.R + c.G + c.B >= rarity.color.R + rarity.color.G + rarity.color.B, `{rarity.id}: no darker than the rarity`)
	end
	H.ok(SeedPacks.TEXT_LIFT > 0 and SeedPacks.TEXT_LIFT <= 0.4, "brightened a little, still its colour")
	local tile = block(HUD, "local function rewardTile(", "\n\tend\n")
	H.ok(string.find(tile, "local ink = if featured then COLORS.gold else SeedPacks.tileTextColor(tile.rarity)", 1, true) ~= nil, "the tile's ink")
	local _, uses = string.gsub(tile, "TextColor3 = ink,", "")
	H.eq(uses, 2, "the name and the %")
	H.ok(string.find(tile, "UiFx.relief(name, 3, if featured then 4 else 3)", 1, true) ~= nil, "the name in relief too")
	H.ok(not string.find(tile, "else WHITE", 1, true), "no white name / % any more")
end)

-- Whether two rects { x, y, w, h } don't overlap
local function apart(a: any, b: any): boolean
	return a.x + a.w <= b.x or b.x + b.w <= a.x or a.y + a.h <= b.y or b.y + b.h <= a.y
end

H.test("Shop tabs: Featured / Speed / Money belong to the Shop window (outside its right edge), only while it is open", function()
	local ShopLayout = H.shared("ShopLayout")
	local L = ShopLayout
	local column = block(HUD, "local shopTabs: Frame\n", "\n-- Money-dependent bits of the open window")
	H.ok(column ~= "", "the tabs' block")
	-- a child of the modal: modalScale scales them, they move with it; hidden until the Shop opens
	H.ok(string.find(column, "Name = \"ShopShortcuts\", BackgroundTransparency = 1, Position = UDim2.new(1, L.TAB_GAP, 0, L.TAB_TOP)", 1, true) ~= nil,
		"just outside the window's right edge, from its top")
	H.ok(string.find(column, "Size = UDim2.fromOffset(L.TAB_W, L.TAB_H), Visible = false, Parent = modal,", 1, true) ~= nil, "a child of the modal, hidden")
	H.ok(not string.find(HUD, "Position = UDim2.new(1, -10, 0.45, -48)", 1, true), "no longer on the screen's right edge by the Plants button")
	H.ok(string.find(HUD, "local modal = new(", 1, true) < string.find(HUD, "local shopTabs: Frame", 1, true), "(built after the modal)")
	local openModal = block(HUD, "openModal = function(name: string)", "\nend\n")
	H.ok(string.find(openModal, "modalName = name\n\tshopTabs.Visible = name == \"Shop\"", 1, true) ~= nil, "shown only on the Shop")
	H.ok(string.find(openModal, "markShopTab(shopFocus or \"Featured\")", 1, true) ~= nil, "opens with FEATURED lit (or the section it opens at)")
	local closeModal = block(HUD, "local function closeModal()", "\nend\n")
	H.ok(string.find(closeModal, "shopTabs.Visible = false", 1, true) ~= nil, "hidden when the window closes")
	-- fitModal places them: outside, or tucked inside the wider window's right margin (the body keeps its width)
	local fit = block(HUD, "local function fitModal()", "\nend\n")
	H.ok(string.find(fit, "local mw, mh, scale, tabs = ShopLayout.fit(modalName, w, h - TOP - BOTTOM)", 1, true) ~= nil, "ShopLayout.fit")
	H.ok(string.find(fit, "bodyHolder.Size = UDim2.new(1, -2 * MODAL_PAD - tucked, 1, -TITLE_H - 10 - MODAL_PAD)", 1, true) ~= nil, "the body narrows by the tucked tabs")
	H.ok(string.find(fit, "shopTabs.Position = if tabs == \"inside\" then UDim2.new(1, -ShopLayout.TAB_W - MODAL_PAD / 2, 0, TITLE_H + 10)", 1, true) ~= nil
		and string.find(fit, "else UDim2.new(1, ShopLayout.TAB_GAP, 0, ShopLayout.TAB_TOP)", 1, true) ~= nil, "inside under the title bar, or outside")
	local bodyHolder = string.match(HUD, "local bodyHolder = new%(\"Frame\", {.-}%)") or ""
	H.ok(string.find(bodyHolder, "Size = UDim2.new(1, -2 * MODAL_PAD, 1, -TITLE_H - 10 - MODAL_PAD)", 1, true) ~= nil, "fitModal's body size matches the built one")
	H.eq(L.TAB_H, 3 * (L.TAB_ICON + L.TAB_WORD) + 2 * L.TAB_PAD, "three tabs")
	H.ok(L.TAB_ICON >= 60 and L.TAB_ICON * L.TAB_ACTIVE <= L.TAB_W, "big icons; a lit one still inside the column")

	-- The geometry on phones, tablets and desktops: never over the window, never off the screen
	local TOP, BOTTOM = 44, 112 -- fitModal's
	local ws = ShopLayout.window("Shop")
	local outside, inside = 0, 0
	for _, screen in { { 844, 390 }, { 667, 375 }, { 932, 430 }, { 1024, 600 }, { 1280, 720 }, { 1366, 768 }, { 1920, 1080 }, { 2560, 1440 },
		{ 390, 844 }, { 375, 667 }, { 768, 1024 }, { 600, 960 } } do
		local ui = math.clamp(screen[2] / 900, 0.55, 1.25)
		local dw, dh = screen[1] / ui, screen[2] / ui
		local fw, fh, s, tabs = ShopLayout.fit("Shop", dw, dh - TOP - BOTTOM)
		local name = `{screen[1]}x{screen[2]}`
		local x0, y0 = dw / 2 - fw * s / 2, dh / 2 + (TOP - BOTTOM) / 2 - fh * s / 2
		local win = { x = x0, y = y0, w = fw * s, h = fh * s }
		H.ok(win.x >= 0 and win.x + win.w <= dw and win.y >= 0 and win.y + win.h <= dh, `{name}: the window on the screen`)
		local col
		if tabs == "outside" then
			outside += 1
			H.eq(fw, ws, `{name}: the window keeps its width`)
			col = { x = x0 + (fw + L.TAB_GAP) * s, y = y0 + L.TAB_TOP * s, w = L.TAB_W * s, h = L.TAB_H * s }
			H.ok(apart(col, win), `{name}: beside the window, not over it`)
			-- a hovered tab pops 1.1 (UiFx.HOVER) and still stays on the screen
			H.ok(col.x + col.w + (L.TAB_W * 0.05) * s <= dw, `{name}: on the screen`)
		else
			inside += 1
			H.eq(tabs, "inside", `{name}: tucked`)
			H.eq(fw, ws + L.TAB_W, `{name}: the window grows by the tabs`)
			H.eq(fw - 2 * ShopLayout.PAD - L.TAB_W, ws - 2 * ShopLayout.PAD, `{name}: the body keeps its width (the cards fit)`)
			col = { x = x0 + (fw - L.TAB_W - ShopLayout.PAD / 2) * s, y = y0 + (ShopLayout.TITLE_H + 10) * s, w = L.TAB_W * s, h = L.TAB_H * s }
			local body = { x = x0 + ShopLayout.PAD * s, y = y0 + (ShopLayout.TITLE_H + 10) * s, w = (fw - 2 * ShopLayout.PAD - L.TAB_W) * s,
				h = (fh - ShopLayout.TITLE_H - 10 - ShopLayout.PAD) * s }
			H.ok(apart(col, body), `{name}: not over the cards`)
			H.ok(col.x + col.w <= win.x + win.w and col.y + col.h <= win.y + win.h, `{name}: inside the window`)
		end
		H.ok(col.y >= win.y and col.y + col.h <= win.y + win.h, `{name}: along the window's height`)
		H.ok(col.y >= 0 and col.y + col.h <= dh, `{name}: on the screen`)
	end
	H.ok(outside >= 6 and inside >= 3, `landscape screens outside ({outside}), portrait phones tucked ({inside})`)
	H.eq(select(4, ShopLayout.fit("Trails", 1600, 744)), nil, "only the Shop has tabs")
	H.eq(select(4, ShopLayout.fit("Index", 400, 744)), nil, "(even on a narrow screen)")
	H.eq(select(1, ShopLayout.fit("Trails", 400, 744)), ShopLayout.DEFAULT_W, "the other windows keep their width")
end)

H.test("Shop tabs: a click scrolls the open Shop to its section; the lit tab follows the scroll", function()
	local ShopLayout = H.shared("ShopLayout")
	local column = block(HUD, "local shopTabs: Frame\n", "\n-- Money-dependent bits of the open window")
	for _, s in { { "Featured", "Featured", "drawTag" }, { "Speed", "Speed", "function" }, { "Money", "Money", "function" } } do
		H.ok(string.find(column, `shortcut%(%d, "{s[1]}", "{s[2]}", {s[3]}`) ~= nil, `{s[1]} goes to {s[2]}`)
		H.ok(table.find(ShopLayout.TAB_SECTIONS, s[2]) ~= nil, `{s[2]} is a tab section`)
	end
	H.ok(string.find(column, "b.Activated:Connect(function()\n\t\t\topenShopAt(section)", 1, true) ~= nil, "a click: openShopAt")
	H.ok(string.find(column, "iconLabel(art, \"Speed\", \"⚡\"", 1, true) and string.find(column, "iconLabel(art, \"Money\", \"💰\"", 1, true), "the sneaker and the cash")
	H.ok(string.find(column, "Name = word, BackgroundTransparency = 1", 1, true) ~= nil, "no box behind them")
	H.ok(string.find(column, "local label = bold(b, 4, { Name = \"Word\", Text = word", 1, true) and string.find(column, "UiFx.relief(label, 3, 3)", 1, true),
		"the word in white relief under the icon")
	H.ok(string.find(column, "Name = \"Tag\"", 1, true) and string.find(column, "Name = \"Point\"", 1, true) and string.find(column, "Text = \"%\"", 1, true), "a red tag with a %")
	-- openShopAt: an open Shop scrolls to the section's title row (nothing rebuilt); a closed one opens there
	local open = block(HUD, "openShopAt = function(sectionName: string)", "\nend\n")
	H.ok(string.find(open, "markShopTab(sectionName)", 1, true) ~= nil, "lights the clicked tab")
	H.ok(string.find(open, "modal.Visible and modalName == \"Shop\" and modalBody:FindFirstChild(\"Section_\" .. string.upper(sectionName))", 1, true)
		and string.find(open, "scrollModalTo(row :: GuiObject)\n\t\treturn", 1, true), "the open Shop scrolls there")
	H.ok(string.find(open, "shopFocus = sectionName", 1, true) and string.find(open, "openModal(\"Shop\")", 1, true), "a closed Shop opens there")
	H.ok(string.find(HUD, "local function scrollModalTo(target: GuiObject)", 1, true) < string.find(HUD, "openShopAt = function(", 1, true), "(scrollModalTo in scope)")
	-- the title rows are named after the tabs' sections
	H.ok(string.find(HUD, "local row = new(\"Frame\", { Name = \"Section_\" .. label", 1, true) ~= nil, "section rows are named")
	local renderShop = block(HUD, "function renderShop(): boolean", "\n\tend\nend")
	H.ok(string.find(renderShop, "shopSections.Featured = section(\"FEATURED\"", 1, true) ~= nil, "-- FEATURED -- (the seed packs)")
	H.ok(string.find(renderShop, "shopSections.Speed = section(\"SPEED\"", 1, true) ~= nil, "-- SPEED --")
	H.ok(string.find(renderShop, "shopSections.Money = section(\"MONEY\"", 1, true) ~= nil, "-- MONEY --")
	H.ok(not string.find(renderShop, "\"SEED PACKS\"", 1, true), "the old SEED PACKS title is renamed")
	-- the lit tab follows the scroll: markShopTab on every scroll, ShopLayout.litTab decides
	H.ok(string.find(column, "for _, prop in { \"CanvasPosition\", \"AbsoluteCanvasSize\", \"AbsoluteWindowSize\" } do\n\t\tmodalBody:GetPropertyChangedSignal(prop):Connect(function()\n\t\t\tmarkShopTab()", 1, true) ~= nil,
		"re-checked on every scroll")
	H.ok(string.find(column, "local found = L.litTab(tops, modalBody.AbsolutePosition.Y, modalBody.AbsoluteWindowSize.Y)", 1, true) ~= nil, "ShopLayout.litTab")
	H.ok(string.find(column, "{ Scale = if on then L.TAB_ACTIVE else 1 }", 1, true) and string.find(column, "t.glow.Visible = on", 1, true)
		and string.find(column, "t.word.TextColor3 = if on then LIT_GOLD else WHITE", 1, true), "lit: bigger, a glow, a gold word")
	-- litTab: a body at y 100, 500 tall (its line at 300); the titles 1000 px apart as the canvas scrolls
	local function at(scroll: number): string?
		return ShopLayout.litTab({ Featured = 104 - scroll, Speed = 1904 - scroll, Money = 2904 - scroll }, 100, 500)
	end
	H.eq(at(0), "Featured", "at the top")
	H.eq(at(1000), "Featured", "in the PASSES")
	H.eq(at(1550), "Featured", "SPEED's title still low in the body")
	H.eq(at(1604), "Speed", "SPEED's title up past 40%")
	H.eq(at(1804), "Speed", "SPEED at the top")
	H.eq(at(2700), "Money", "MONEY")
	H.eq(at(3600), "Money", "UPGRADES keep MONEY lit")
	H.eq(at(1700), "Speed", "scrolling back up")
	H.eq(at(200), "Featured", "and back to the top")
	H.eq(ShopLayout.litTab({}, 100, 500), nil, "nothing laid out: unchanged")
	H.eq(ShopLayout.litTab({ Money = 120 }, 100, 500), "Money", "only the laid-out titles count")
end)

H.test("hotbar bat in 3D: laid diagonally, grip bottom-left, fitted to the slot, brightly lit", function()
	local ToolView = H.shared("ToolView")
	local V, CF = roblox.Vector3, roblox.CFrame
	-- BatTool's plain bat: a 4 x 0.5 x 0.5 handle, the hand at x = -1.6
	local function check(boxes: { any }, grip: any, label: string)
		local lo, hi = ToolView.bounds(boxes)
		local pose = ToolView.pose(lo, hi, grip)
		local g = pose * grip
		H.ok(g.X < 0 and g.Y < 0, `{label}: the grip end bottom-left ({g})`)
		local points = {}
		for _, b in boxes do
			local cf = pose * b.cframe
			local h = b.size / 2
			for _, s in { V.new(-1, -1, -1), V.new(1, 1, 1), V.new(-1, 1, -1), V.new(1, -1, 1), V.new(-1, -1, 1), V.new(1, 1, -1), V.new(-1, 1, 1), V.new(1, -1, -1) } do
				table.insert(points, cf * (h * s))
			end
		end
		-- the far end (furthest from the grip) is top-right
		local far = points[1]
		for _, p in points do
			if (p - g).Magnitude > (far - g).Magnitude then
				far = p
			end
		end
		H.ok(far.X > 0 and far.Y > 0, `{label}: the far end top-right ({far})`)
		H.ok(far.Z > 0, `{label}: turned a little toward the camera`)
		local dist = ToolView.distance(points, ToolView.FOV, ToolView.FILL)
		local t = math.tan(math.rad(ToolView.FOV) / 2)
		local widest = 0
		for _, p in points do
			local depth = dist - p.Z
			H.ok(depth > 0, `{label}: in front of the camera`)
			widest = math.max(widest, math.abs(p.X) / depth / t, math.abs(p.Y) / depth / t)
		end
		H.ok(math.abs(widest - ToolView.FILL) < 1e-6, `{label}: the widest point at FILL of the half-width ({widest})`)
	end
	check({ { cframe = CF.new(), size = V.new(4, 0.5, 0.5) } }, V.new(-1.6, 0, 0), "along X")
	check({ { cframe = CF.new(), size = V.new(4, 0.5, 0.5) } }, V.new(1.6, 0, 0), "grip at the + end")
	check({ { cframe = CF.new(), size = V.new(0.4, 0.4, 3) }, { cframe = CF.new(0, 0, -1.8), size = V.new(0.7, 0.7, 1.2) } },
		V.new(0, 0, 1.2), "along Z, two parts")
	check({ { cframe = CF.Angles(0.3, 0.2, 0.1), size = V.new(0.5, 4, 0.5) } }, V.new(0, -1.5, 0), "along Y, tilted")
	H.ok(ToolView.AMBIENT.R > 0.6 and ToolView.AMBIENT.G > 0.6, "bright ambient: not a dark picture")
	H.ok(ToolView.LIGHT_DIRECTION.Z < 0, "lit from the camera's side")
	H.eq(string.find(read("src/shared/ToolView.luau"), "RenderStepped", 1, true), nil, "a still picture, like the seed slot")
end)

return nil
