-- HUD, built in code. Display only: it renders StatsUpdate/LootEvent, sends RequestBuy/RequestUseItem,
-- and owns the local Slow Mode toggle. No game state is decided here.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local SeedPacks = require(Shared:WaitForChild("SeedPacks"))
local Icons = require(Shared:WaitForChild("Icons"))
local Treadmill = require(Shared:WaitForChild("Treadmill"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local ShopLayout = require(Shared:WaitForChild("ShopLayout"))
local ShopUi = require(Shared:WaitForChild("ShopUi"))
local Toast = require(Shared:WaitForChild("Toast"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestBuy = remotes:WaitForChild("RequestBuy") :: RemoteEvent
local RequestUseItem = remotes:WaitForChild("RequestUseItem") :: RemoteEvent
local StatsUpdate = remotes:WaitForChild("StatsUpdate") :: RemoteEvent
local LootEvent = remotes:WaitForChild("LootEvent") :: RemoteEvent

pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)

-- Latest server stats (merged from partial updates)
local stats: { [string]: any } = {
	money = 0, speed = 0, walkSpeed = 16, income = 0, slots = Config.SLOTS_START, plotLevel = 1,
	trails = { [Config.DEFAULT_TRAIL] = true }, equippedTrail = Config.DEFAULT_TRAIL, speedMult = Config.trailMult(Config.DEFAULT_TRAIL),
	treadmillTier = 1,
	items = {}, index = {}, plants = {}, passes = {}, carrying = false, reachedEnd = false, seedBag = {},
}

----------------------------------------------------------------------------------------------------
-- Tiny UI kit
----------------------------------------------------------------------------------------------------
local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(25, 25, 35)
local COLORS = {
	speed = Color3.fromRGB(60, 160, 255),
	money = Color3.fromRGB(70, 200, 90),
	shop = Color3.fromRGB(255, 195, 40),
	index = Color3.fromRGB(170, 100, 255),
	slow = Color3.fromRGB(150, 150, 160),
	panel = Color3.fromRGB(255, 250, 235),
	red = Color3.fromRGB(240, 70, 70),
	gold = Color3.fromRGB(255, 205, 50),
	disabled = Color3.fromRGB(170, 170, 170),
	buy = Color3.fromRGB(60, 200, 80), -- green: money and R$ buy buttons
	equip = Color3.fromRGB(60, 160, 255),
}

-- Icon sizes (x the label's height) per context: shop card titles big, HUD buttons medium, prices small.
-- Icons.set shows the emoji text as it is while an icon isn't uploaded (Config.ICONS id 0).
local ICON = { big = 1, medium = 0.85, small = 0.7 }

local function new(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, c in (children or {}) :: { Instance } do
		c.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function deco(radius: number, stroke: number?): { Instance }
	return {
		new("UICorner", { CornerRadius = UDim.new(0, radius) }),
		new("UIStroke", { Thickness = stroke or 3, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	}
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local label = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		TextScaled = true,
		TextColor3 = WHITE,
		Parent = parent,
	}, { new("UIStroke", { Thickness = 2, Color = INK }) })
	for k, v in props do
		(label :: any)[k] = v
	end
	return label
end

-- `icon`: the icon key(s) that may replace emoji in `label` (see Icons.set), at `iconSize` (default medium).
local function button(parent: Instance, label: string, color: Color3, size: UDim2, onClick: () -> (), icon: (string | { string })?, iconSize: number?): TextButton
	local b = new("TextButton", {
		Size = size,
		BackgroundColor3 = color,
		Text = "",
		AutoButtonColor = true,
		Parent = parent,
	}, deco(10))
	ShopUi.studs(b, color) -- studded plastic, under the words
	local l = text(b, { Name = "Label", Text = label, Size = UDim2.new(1, -10, 1, -6), Position = UDim2.fromOffset(5, 3) })
	if icon then
		Icons.set(l, icon, label, iconSize or ICON.medium)
	end
	b.Activated:Connect(onClick)
	return b
end

local gui = new("ScreenGui", { Name = "SeedHUD", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
local uiScale = new("UIScale", { Parent = gui })
UiFx.watch(gui) -- every button in the HUD (and the Rewards window in it) pops when hovered or pressed
local function rescale()
	local cam = workspace.CurrentCamera
	local y = if cam then cam.ViewportSize.Y else 900
	uiScale.Scale = math.clamp(y / 900, 0.55, 1.25)
end

----------------------------------------------------------------------------------------------------
-- Toasts (top centre, just under Roblox's top bar; while a zone banner shows they move down under it).
-- Only what the player must know: errors, getting caught, offline earnings, day/night, announcements.
----------------------------------------------------------------------------------------------------
local TOAST_TOP, TOAST_UNDER_BANNER = 8, 160 -- design pixels; ZoneBanner.client's strip spans 70..154
local toastHolder = new("Frame", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, TOAST_TOP),
	Size = UDim2.fromOffset(720, 420), ZIndex = 12, Parent = gui, -- above the shop windows
}, { new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 0), SortOrder = Enum.SortOrder.LayoutOrder }) })
task.spawn(function()
	local banner = player:WaitForChild("PlayerGui"):WaitForChild("ZoneBanner", 60)
	local strip = banner and banner:WaitForChild("Strip", 10)
	if strip then
		strip:GetPropertyChangedSignal("Visible"):Connect(function()
			TweenService:Create(toastHolder, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
				Position = UDim2.new(0.5, 0, 0, if strip.Visible then TOAST_UNDER_BANNER else TOAST_TOP),
			}):Play()
		end)
	end
end)

-- Each one in the shared announcement look (Shared/Toast: a studded plate in its colour, an icon, chunky relief
-- words; it pops in and fades out). `icon`: an Icons key, "Sun" / "Moon", or nil for the colour's own;
-- `big`: a server-wide announcement (bigger, a rainbow frame).
local function toast(message: string, color: string?, seconds: number?, icon: string?, big: boolean?)
	-- Words only: server texts (Net.toast, announcements) may still carry emoji. The lock stays.
	local ok, plain = pcall(string.gsub, message, utf8.charpattern, function(ch: string)
		local c = utf8.codepoint(ch)
		local emoji = (c >= 0x2300 and c <= 0x23FF) or (c >= 0x2600 and c <= 0x27BF) or (c >= 0x2B00 and c <= 0x2BFF)
			or (c >= 0x1F000 and c <= 0x1FAFF) or c == 0xFE0F or c == 0x200D
		return if emoji and ch ~= "🔒" then "" else nil
	end)
	if ok then
		message = string.match(string.gsub(plain, "%s+", " "), "^%s*(.-)%s*$") or message
	end
	Toast.show(toastHolder, message, { color = color, seconds = seconds, icon = icon, big = big })
	local children = toastHolder:GetChildren()
	if #children > 5 then
		for _, c in children do
			if c:IsA("Frame") then
				c:Destroy()
				break
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Left side, kept minimal, with no panels behind the numbers:
--   * bottom-left: Speed (with a "+" that opens the Shop's Speed section) in pink, money in green;
--   * middle of the left edge: the Shop / Index buttons and the Slow Mode switch. (Trails opens from
--     the TRAIL SHOP stall in the plaza, the Free Gift from the gift box where the free chest stood.)
-- Sizes are design pixels: the screen is 900 tall at UIScale 1, about 680 on a landscape phone (the
-- 0.55 minimum scale). The button column shrinks on its own if it would run into the Speed and money.
----------------------------------------------------------------------------------------------------
local SPEED_PINK = Color3.fromRGB(255, 70, 150)
local MONEY_GREEN = Color3.fromRGB(85, 240, 70)
local LEFT_GAP = 18 -- between Shop, Index and Slow Mode
local SIDE_W, SIDE_H = 176, 68 -- the Shop / Index buttons (wide, like the reference)
local STATS_H, LEFT_H = 176, SIDE_H * 2 + 30 + 2 * LEFT_GAP -- LEFT_H: 2 side buttons + Slow Mode
local STATS_BOTTOM = 10

local openModal: (name: string) -> ()
local openShopAt: (section: string) -> ()

-- An uploaded icon as an image, or its emoji as text while it isn't uploaded (Config.ICONS id 0).
local function iconLabel(parent: Instance, key: string, emoji: string, props: { [string]: any }): GuiObject
	local image = Icons.image(key)
	local g: GuiObject = if image
		then new("ImageLabel", { BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Fit, Parent = parent })
		else text(parent, { Text = emoji })
	for k, v in props do
		(g :: any)[k] = v
	end
	return g
end

-- Text with a thicker dark outline, for the big numbers and button captions.
local function bold(parent: Instance, thickness: number, props: { [string]: any }): TextLabel
	local label = text(parent, props)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = thickness
	end
	return label
end

-- Speed and money, big like the reference HUD (owner 2026-10-15: "about 2x bigger"): huge chunky italic
-- numbers with a thick dark outline, the icons left of them (no VIP badge over it any more: owner 2026-10-15;
-- the VIP tag over the head stays). Its "Fit" scale keeps it left of the hotbar on narrow screens (fitLeftColumn).
local statsFrame = new("Frame", {
	Name = "Stats", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -STATS_BOTTOM),
	Size = UDim2.fromOffset(470, STATS_H), Parent = gui,
}, { new("UIScale", { Name = "Fit" }) })
iconLabel(statsFrame, "Speed", "⚡", { Size = UDim2.fromOffset(84, 84) })
local speedValue = bold(statsFrame, 6, {
	-- (narrower than the money: its "+" badge rides at its right end, inside the readout)
	Text = "0", Size = UDim2.new(1, -152, 0, 80), Position = UDim2.fromOffset(98, 2), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = SPEED_PINK,
	FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic),
})
iconLabel(statsFrame, "Money", "💰", { Size = UDim2.fromOffset(84, 84), Position = UDim2.fromOffset(0, 92) })
local moneyValue = bold(statsFrame, 6, {
	Text = "$0", Size = UDim2.new(1, -100, 0, 80), Position = UDim2.fromOffset(98, 94), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = MONEY_GREEN,
	FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic),
})
UiFx.relief(speedValue, 6, 6) -- raised, not flat: a dropped dark copy behind, a bevel, a thick outline
UiFx.relief(moneyValue, 6, 6)
-- The Speed icon and its yellow "+" badge both open the Shop on the Speed section. The "+" sits just past the
-- Speed number's right end (owner 2026-10-15: on the sneaker's corner it covered the digits), following it as
-- the number grows; the number is 52 narrower than the money (1, -152) so the badge always fits beside it.
new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromOffset(84, 84), Parent = statsFrame }).Activated:Connect(function()
	openShopAt("Speed")
end)
local plusBadge = new("TextButton", {
	Name = "Plus", Size = UDim2.fromOffset(44, 44), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(98 + 10, 42),
	BackgroundColor3 = Color3.fromRGB(255, 210, 40), Text = "", AutoButtonColor = true, Parent = statsFrame,
}, deco(4, 4))
ShopUi.studs(plusBadge, Color3.fromRGB(255, 210, 40))
UiFx.relief(bold(plusBadge, 4, { Text = "+", Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 1) }), 2, 4)
do
	-- TextBounds are on-screen pixels: back to the readout's design pixels (its "Fit" and the HUD's scale)
	local function placePlus()
		local shown = speedValue.AbsoluteSize.Y
		local wide = if shown > 0 then speedValue.TextBounds.X * 80 / shown else 0
		plusBadge.Position = UDim2.fromOffset(math.min(98 + wide + 10, 470 - 44), 42)
	end
	speedValue:GetPropertyChangedSignal("TextBounds"):Connect(placePlus)
	speedValue:GetPropertyChangedSignal("AbsoluteSize"):Connect(placePlus)
	placePlus()
end
plusBadge.Activated:Connect(function()
	openShopAt("Speed")
end)

-- Shop / Index, then the Slow Mode switch, centred on the left edge (the Speed and money stay bottom-left).
local leftColumn = new("Frame", {
	Name = "LeftColumn", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0),
	Size = UDim2.fromOffset(SIDE_W + 12, LEFT_H), Parent = gui,
}, {
	new("UIListLayout", { Padding = UDim.new(0, LEFT_GAP), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
})
local leftScale = new("UIScale", { Parent = leftColumn })

-- Wide vivid buttons (owner reference 2026-10-15): about 2.6:1, near-square corners, a thick dark outline,
-- a flat colour, studded, with a lighter top (ShopUi.bevel; no dark bottom band), the icon on the left and the
-- word in big white relief on its right.
local function sideButton(order: number, label: string, icon: string, emoji: string, color: Color3, onClick: () -> ())
	-- The column lays out the holder; the button sits centred in it so its hover pop grows from the middle.
	local holder = new("Frame", { Name = label, Size = UDim2.fromOffset(SIDE_W, SIDE_H), BackgroundTransparency = 1, LayoutOrder = order, Parent = leftColumn })
	local b = new("TextButton", {
		Name = "Button", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color, Text = "", AutoButtonColor = true, Parent = holder,
	}, deco(4, 4))
	ShopUi.studs(b, color) -- the reference's studded plastic, under the bevel and the words
	ShopUi.bevel(b)
	iconLabel(b, icon, emoji, { Size = UDim2.fromOffset(54, 54), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, -1) })
	UiFx.relief(bold(b, 4, { Text = label, Size = UDim2.new(1, -78, 0, 42), Position = UDim2.new(0, 68, 0.5, -23), TextXAlignment = Enum.TextXAlignment.Left }), 3, 4)
	b.Activated:Connect(onClick)
end

sideButton(1, "Shop", "Shop", "🛒", Color3.fromRGB(95, 230, 45), function()
	openModal("Shop")
end)
sideButton(2, "Index", "Index", "📖", Color3.fromRGB(35, 195, 255), function()
	openModal("Index")
end)

-- Slow Mode: purely local, clamps our own WalkSpeed so we can potter around the base.
local slowMode = false
-- (styled like the buttons above: a square-ish track with a thick outline, the words in relief)
local slowRow = new("TextButton", { Name = "SlowMode", Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Text = "", LayoutOrder = 3, Parent = leftColumn })
local slowTrack = new("Frame", {
	Size = UDim2.fromOffset(54, 28), Position = UDim2.fromOffset(2, 1), BackgroundColor3 = Color3.fromRGB(150, 165, 215), Parent = slowRow,
}, deco(4, 4))
ShopUi.studs(slowTrack, nil) -- white-tinted: the track's colour changes with the switch
local slowKnob = new("Frame", {
	Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(3, 3), BackgroundColor3 = WHITE, Parent = slowTrack,
}, deco(3, 2))
UiFx.relief(bold(slowRow, 3, { Text = "Slow Mode", Size = UDim2.new(1, -66, 0, 26), Position = UDim2.fromOffset(66, 1), TextXAlignment = Enum.TextXAlignment.Left }), 3, 3)

local function applySlow()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and slowMode and hum.WalkSpeed > Config.SLOW_MODE_WALKSPEED then
		hum.WalkSpeed = Config.SLOW_MODE_WALKSPEED
	elseif hum and not slowMode and stats.walkSpeed and hum.WalkSpeed ~= stats.walkSpeed and hum.WalkSpeed ~= 0 then
		hum.WalkSpeed = stats.walkSpeed
	end
end
slowRow.Activated:Connect(function()
	slowMode = not slowMode
	local info = TweenInfo.new(0.15, Enum.EasingStyle.Quad)
	TweenService:Create(slowKnob, info, {
		Position = UDim2.fromOffset(if slowMode then 29 else 3, 3),
		BackgroundColor3 = if slowMode then Color3.fromRGB(190, 255, 150) else WHITE,
	}):Play()
	TweenService:Create(slowTrack, info, {
		BackgroundColor3 = if slowMode then Color3.fromRGB(70, 205, 60) else Color3.fromRGB(150, 165, 215),
	}):Play()
	applySlow()
end)
local function hookHumanoid(char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if slowMode and hum.WalkSpeed > Config.SLOW_MODE_WALKSPEED then
			hum.WalkSpeed = Config.SLOW_MODE_WALKSPEED
		end
	end)
	applySlow()
end
player.CharacterAdded:Connect(hookHumanoid)
if player.Character then
	task.spawn(hookHumanoid, player.Character)
end

-- Short screens (phones): shrink the centred button column so its bottom stays above the Speed and money.
local function fitLeftColumn()
	local height = gui.AbsoluteSize.Y / uiScale.Scale
	-- the readout first: left of the hotbar (centred, under 200 wide), never over it
	local fit = statsFrame:FindFirstChild("Fit") :: UIScale
	fit.Scale = math.clamp((gui.AbsoluteSize.X / uiScale.Scale / 2 - 110 - 14) / 470, 0.5, 1)
	-- from the middle of the screen down to the readout
	local room = height / 2 - STATS_BOTTOM - STATS_H * fit.Scale - 10
	leftScale.Scale = math.clamp(room / (LEFT_H / 2), 0.5, 1)
end

----------------------------------------------------------------------------------------------------
-- Hotbar (bottom centre): Bat (1); Planting.client adds the seed slot (2) to it. Slots like the reference
-- (ShopUi.slot): small dark see-through squares, the number top-left, the item drawn filling the slot.
----------------------------------------------------------------------------------------------------
local hotbar = new("Frame", {
	Name = "Hotbar", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.fromOffset(2 * ShopUi.SLOT + 8, ShopUi.SLOT), Parent = gui,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }) })
local batCooldownUntil = 0
local function useBat()
	if os.clock() >= batCooldownUntil then
		RequestUseItem:FireServer("Bat")
	end
end
local batSlot = new("TextButton", { Name = "BatSlot", Parent = hotbar })
batSlot.LayoutOrder = 1
ShopUi.slot(batSlot, "1")
batSlot.Activated:Connect(useBat)
do
	-- A wooden baseball bat, drawn from frames, lying diagonally across the slot: a round barrel tapering
	-- into a thin handle with a knob, warm wood with a light side, a thin dark brown outline.
	local WOOD = ColorSequence.new(Color3.fromRGB(236, 172, 100), Color3.fromRGB(160, 92, 42))
	local BARK = Color3.fromRGB(70, 36, 14)
	local bat = new("Frame", {
		Name = "Bat", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.52, 0.52),
		Size = UDim2.fromScale(0.2, 1.02), Rotation = 42, ZIndex = 2, Parent = batSlot,
	})
	-- { width, top, height } as shares of the bat's frame, handle end first so the barrel overlaps it
	for _, part in { { 0.36, 0.52, 0.42 }, { 0.62, 0.9, 0.08 }, { 0.6, 0.38, 0.22 }, { 0.92, 0.02, 0.5 } } do
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, part[2]), Size = UDim2.fromScale(part[1], part[3]),
			BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2, Parent = bat,
		}, {
			new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), -- round wood (art)
			new("UIGradient", { Color = WOOD }),
			new("UIStroke", { Thickness = 1.5, Color = BARK }),
		})
	end
end
local batShade = new("Frame", {
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 0),
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), ZIndex = 3, Parent = batSlot,
})

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.One then
		useBat()
	end
end)

----------------------------------------------------------------------------------------------------
-- Right side: Seeds / Plants menus
----------------------------------------------------------------------------------------------------
local rightTabs = new("Frame", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.45, 0),
	Size = UDim2.fromOffset(70, 150), Parent = gui,
}, { new("UIListLayout", { Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center }) })

local sidePanel = new("Frame", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -96, 0.45, 0), Size = UDim2.fromOffset(380, 440),
	BackgroundColor3 = COLORS.panel, Visible = false, Parent = gui,
}, deco(4, 4))
ShopUi.studs(sidePanel, COLORS.panel) -- studded like every HUD element (under its title, tabs and list)
local sideTitle = text(sidePanel, { Text = "", Size = UDim2.new(1, -20, 0, 36), Position = UDim2.fromOffset(10, 8), TextColor3 = INK })
sideTitle:FindFirstChildOfClass("UIStroke"):Destroy()
local sideList = new("ScrollingFrame", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 50), Size = UDim2.new(1, -20, 1, -60),
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, BorderSizePixel = 0,
	Parent = sidePanel,
}, { new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

local sideTab: string? = nil -- "Plants" or "Inventory" (the Plants panel's tabs)
local renderSide: () -> ()

local function card(order: number, color: Color3, height: number?): Frame
	local f = new("Frame", { Size = UDim2.new(1, -8, 0, height or 54), BackgroundColor3 = color, LayoutOrder = order, Parent = sideList }, deco(4, 2))
	ShopUi.studs(f, color)
	return f
end

local function clearSide()
	for _, c in sideList:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

-- The bag's seeds by label ("Rare Seed" from the Desert): seeds differ by their hidden gene (SeedPacks
-- bagKey) but list as one, so the list never hints at their flowers. `key`: the seed its Plant button plants.
type BagEntry = { key: string, count: number, zone: number, rarity: number, mutation: string? }
local function bagEntries(): { BagEntry }
	local list: { BagEntry } = {}
	local byLabel: { [string]: BagEntry } = {}
	for key, count in stats.seedBag or {} do
		local z, r, m = SeedPacks.parseBagKey(key)
		local entry = byLabel[SeedPacks.labelKey(key)]
		if entry then
			entry.count += count
			entry.key = if key < entry.key then key else entry.key
		elseif z and r then
			entry = { key = key, count = count, zone = z, rarity = r, mutation = m }
			byLabel[SeedPacks.labelKey(key)] = entry
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a, b)
		if a.zone ~= b.zone then
			return a.zone > b.zone
		elseif a.rarity ~= b.rarity then
			return a.rarity > b.rarity
		end
		return (a.mutation or "") > (b.mutation or "")
	end)
	return list
end

-- The Plants list (its block comes after the window kit, whose chunky buttons it uses). `full` rebuilds it;
-- otherwise it only rebuilds when the plants themselves changed, and updates the numbers in place.
local renderPlants: (full: boolean?) -> ()

renderSide = function()
	clearSide()
	if sidePanel.Visible then
		renderPlants(true) -- its Plants or Inventory tab
	end
end

-- The one side button: opens and closes the Plants panel (on the tab it was left on)
button(rightTabs, "🪴", Color3.fromRGB(110, 235, 80), UDim2.fromOffset(70, 70), function()
	sidePanel.Visible = not sidePanel.Visible
	sideTab = sideTab or "Plants"
	renderSide()
end, "Plants")

-- Shop shortcuts (owner reference 2026-10-15): a column of three big icons on the right edge, above the
-- Plants button: Featured (a red price tag with a "%", drawn), Speed (the sneaker), Money (the cash), each
-- with its word in white relief under it, no box; they pop on hover (UiFx.watch) and open the Shop at
-- their section (openShopAt: FEATURED = the seed packs, SPEED, MONEY).
do
	local ICON, WORD, GAP = 66, 24, 4 -- design pixels
	local column = new("Frame", {
		Name = "ShopShortcuts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 0.45, -48),
		Size = UDim2.fromOffset(96, 3 * (ICON + WORD) + 2 * GAP), Parent = gui,
	}, { new("UIListLayout", { Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }) })
	-- The Featured icon: a red tag tilted up, its point on the left with a white hole, a yellow "%" in relief
	local function drawTag(parent: GuiObject)
		local RED, DARK_RED = Color3.fromRGB(235, 45, 55), Color3.fromRGB(150, 15, 30)
		local tag = new("Frame", {
			Name = "Tag", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.56, 0.5), Size = UDim2.fromOffset(44, 34), Rotation = -32,
			BackgroundColor3 = RED, BorderSizePixel = 0, ZIndex = 3, Parent = parent,
		}, {
			new("UIStroke", { Thickness = 3, Color = INK, LineJoinMode = Enum.LineJoinMode.Round }),
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new(RED:Lerp(WHITE, 0.15), RED:Lerp(DARK_RED, 0.5)) }),
		})
		new("Frame", { -- the point: a square turned 45 degrees behind the tag's left end
			Name = "Point", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(24, 24), Rotation = 45,
			BackgroundColor3 = RED, BorderSizePixel = 0, ZIndex = 2, Parent = tag,
		}, {
			new("UIStroke", { Thickness = 3, Color = INK, LineJoinMode = Enum.LineJoinMode.Round }),
			new("UIGradient", { Rotation = 45, Color = ColorSequence.new(RED:Lerp(WHITE, 0.15), RED:Lerp(DARK_RED, 0.5)) }),
		})
		new("Frame", { -- hides the tag's outline where the point joins it
			Name = "Join", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(0, 8, 1, -4),
			BackgroundColor3 = RED, BorderSizePixel = 0, ZIndex = 4, Parent = tag,
		})
		new("Frame", { -- the hole
			Name = "Hole", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, -2, 0.5, 0), Size = UDim2.fromOffset(9, 9),
			BackgroundColor3 = WHITE, ZIndex = 5, Parent = tag,
		}, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), new("UIStroke", { Thickness = 2, Color = INK }) }) -- round: a hole (art)
		UiFx.relief(bold(tag, 3, {
			Name = "Percent", Text = "%", Size = UDim2.new(1, -6, 1, -2), Position = UDim2.fromOffset(6, 0), ZIndex = 6,
			TextColor3 = Color3.fromRGB(255, 225, 60),
		}), 2, 3)
	end
	local function shortcut(order: number, word: string, section: string, draw: (GuiObject) -> ())
		local b = new("TextButton", {
			Name = word, BackgroundTransparency = 1, Text = "", Size = UDim2.fromOffset(96, ICON + WORD), LayoutOrder = order, Parent = column,
		})
		local art = new("Frame", {
			Name = "Art", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(ICON, ICON), Parent = b,
		})
		draw(art)
		UiFx.relief(bold(b, 4, { Name = "Word", Text = word, Size = UDim2.new(1, 0, 0, WORD + 2), Position = UDim2.fromOffset(0, ICON - 4), ZIndex = 6 }), 3, 3)
		b.Activated:Connect(function()
			openShopAt(section)
		end)
	end
	shortcut(1, "Featured", "Featured", drawTag)
	shortcut(2, "Speed", "Speed", function(art: GuiObject)
		iconLabel(art, "Speed", "⚡", { Size = UDim2.fromScale(1, 1), ZIndex = 3 })
	end)
	shortcut(3, "Money", "Money", function(art: GuiObject)
		iconLabel(art, "Money", "💰", { Size = UDim2.fromScale(1, 1), ZIndex = 3 })
	end)
end

----------------------------------------------------------------------------------------------------
-- Modals: Shop, Trail Shop, Index and Sell share one window, like the reference (owner 2026-10-15, round
-- 2: "premium, more squared, no edges"): nothing is rounded. A flat bright title bar in the window's
-- colour with classic studs over it, three light diagonal bands on its right half, the title in big white
-- relief on the left and a square red X on the right; under it a dark charcoal body with faint studs, a
-- thin dark outline around it all. The body scrolls down (Shop, Index, Sell) or sideways (Trail Shop: one
-- row of tall cards, a scrollbar at the bottom, arrows on the sides).
-- Sizes are design pixels (ShopLayout: the Shop is wider than the others); modalScale shrinks the whole
-- window to fit small screens (fitModal).
----------------------------------------------------------------------------------------------------
local MODAL_W, MODAL_H, TITLE_H = ShopLayout.MAX_W, ShopLayout.MAX_H, ShopLayout.TITLE_H
local MODAL_PAD = ShopLayout.PAD -- the body's inset from the window's edges
local SCROLLBAR = ShopLayout.SCROLLBAR
local FRAME_INK = Color3.fromRGB(16, 18, 26)
local NOTE_COLOR = Color3.fromRGB(215, 222, 240)
local NUMBER_GREEN = "#5FFF3C" -- the "x2" on the trail cards' Speed pill
local HEADING_GOLD = Color3.fromRGB(255, 214, 50)
local HEADING_CYAN = Color3.fromRGB(60, 215, 255)
local ROBUX_GREEN = Color3.fromRGB(105, 235, 25) -- the Shop's R$ buttons
local GIFT_PINK = Color3.fromRGB(205, 50, 235) -- the gift button beside them
local WINDOW_BODY = Color3.fromRGB(48, 50, 58) -- every window's dark charcoal body
-- `bar`: the title bar's flat colour.
local WINDOWS: { [string]: any } = {
	Shop = { title = "Shop", bar = Color3.fromRGB(59, 227, 59) },
	Trails = { title = "Trail Shop", bar = Color3.fromRGB(185, 70, 255) },
	Index = { title = "Index", bar = Color3.fromRGB(40, 170, 255) },
}

-- Paints a frame `color` with a lit top: a WHITE background under a vertical colour gradient.
local function shade(f: GuiObject, color: Color3, light: number?, dark: number?)
	f.BackgroundColor3 = WHITE
	new("UIGradient", {
		Rotation = 90, Color = ColorSequence.new(color:Lerp(WHITE, light or 0.3), color:Lerp(Color3.new(0, 0, 0), dark or 0.15)), Parent = f,
	})
end

-- A soft white shine over the top half of a (square) frame.
local function shine(f: GuiObject)
	new("Frame", { Name = "Shine", Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = f }, {
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.7, 1) }),
	})
end

-- A square frame's thick dark outline (the windows' cards, tiles and buttons have no rounded corners).
local function outline(thickness: number?, color: Color3?): Instance
	return new("UIStroke", { Thickness = thickness or 3, Color = color or FRAME_INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

-- An icon by its Icons key, or its emoji (Icons.TOKENS) while it isn't uploaded.
local function bigIcon(parent: Instance, key: string, props: { [string]: any }): GuiObject
	local tokens = Icons.TOKENS[key]
	return iconLabel(parent, key, if tokens then tokens[1] else "", props)
end

-- A chunky button: square, a dark outline, studs, a lighter top (ShopUi.bevel; no dark bottom band), an
-- outlined caption (with `icon` key(s) in place of emoji/"R$").
local function chunky(parent: Instance, label: string, color: Color3, size: UDim2, onClick: () -> (), icon: (string | { string })?, iconSize: number?): TextButton
	local b = new("TextButton", { Size = size, BackgroundColor3 = color, BorderSizePixel = 0, Text = "", AutoButtonColor = true, Parent = parent }, { outline() })
	ShopUi.studs(b, nil) -- white-tinted: these buttons change colour (tabs, Remove / Sure?)
	ShopUi.bevel(b)
	local l = bold(b, 3, { Name = "Label", Text = label, Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6) })
	if icon then
		Icons.set(l, icon, label, iconSize or ICON.medium)
	end
	b.Activated:Connect(onClick)
	return b
end

local modal = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(MODAL_W, MODAL_H),
	BackgroundColor3 = WINDOW_BODY, BorderSizePixel = 0, Active = true, Visible = false, ZIndex = 10, Parent = gui, -- sized per window (openModal)
}, { outline(4) })
local modalScale = new("UIScale", { Parent = modal })

-- Studs over the body, like the reference's plate: the title bar's studs exactly, tinted charcoal
local studs = new("Frame", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(0, TITLE_H), Size = UDim2.new(1, 0, 1, -TITLE_H), ClipsDescendants = true, Parent = modal,
})
ShopUi.studs(studs, WINDOW_BODY, nil, 1) -- the same studs as the title bar (ShopUi.STUD_CELL), tinted charcoal

-- Title bar: one flat colour (openModal), studs, three light diagonal bands on its right half, a shine
local titleBar = new("Frame", {
	Size = UDim2.new(1, 0, 0, TITLE_H), BackgroundColor3 = WHITE, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 2, Parent = modal,
})
ShopUi.studs(titleBar, nil, nil, 2) -- tinted to the window's bar colour by openModal (ShopUi.paintStuds)
-- Diagonal bands: a square (so the gradient's 45° is a true 45°) seen through the bar, clipped to it
local stripeKeys = { NumberSequenceKeypoint.new(0, 1) }
for _, band in { { 0.6, 0.645 }, { 0.665, 0.68 }, { 0.705, 0.76 } } do
	table.insert(stripeKeys, NumberSequenceKeypoint.new(band[1] - 0.001, 1))
	table.insert(stripeKeys, NumberSequenceKeypoint.new(band[1], 0.7))
	table.insert(stripeKeys, NumberSequenceKeypoint.new(band[2], 0.7))
	table.insert(stripeKeys, NumberSequenceKeypoint.new(band[2] + 0.001, 1))
end
table.insert(stripeKeys, NumberSequenceKeypoint.new(1, 1))
new("Frame", {
	Name = "Bands", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(MODAL_W, MODAL_W), BackgroundColor3 = WHITE,
	BorderSizePixel = 0, ZIndex = 2, Parent = titleBar,
}, { new("UIGradient", { Rotation = 45, Transparency = NumberSequence.new(stripeKeys) }) })
new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2, Parent = titleBar }, {
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(0.45, 1), NumberSequenceKeypoint.new(0.8, 1), NumberSequenceKeypoint.new(1, 0.82),
	}), Color = ColorSequence.new(WHITE, Color3.new(0, 0, 0)) }),
})
-- The dark line between the bar and the body
new("Frame", { Position = UDim2.fromOffset(0, TITLE_H - 2), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = FRAME_INK, BorderSizePixel = 0, ZIndex = 3, Parent = modal })

local modalTitle = bold(titleBar, 5, {
	Text = "", Size = UDim2.new(1, -460, 0, 64), Position = UDim2.fromOffset(22, 8), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
})
UiFx.relief(modalTitle, 4, 5)
-- Right of the title: what the window counts (the Index's discoveries, the Trail Shop's Speed a step);
-- no money (the HUD shows it)
local modalSubtitle = bold(titleBar, 3, {
	Text = "", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -94, 0.5, 0), Size = UDim2.fromOffset(340, 34),
	TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = WHITE, ZIndex = 3,
})

-- The square red X: a dark red border, a bevel, a white X in relief
local modalClose = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(62, 62), BackgroundColor3 = WHITE, BorderSizePixel = 0,
	Text = "", AutoButtonColor = true, ZIndex = 3, Parent = titleBar,
}, { outline(4, Color3.fromRGB(95, 6, 12)) })
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 50, 50), Color3.fromRGB(210, 10, 20)), Parent = modalClose })
ShopUi.bevel(modalClose)
UiFx.relief(bold(modalClose, 4, { Name = "X", Text = "X", Size = UDim2.new(1, -18, 1, -16), Position = UDim2.fromOffset(9, 6), ZIndex = 4 }), 3, 4)

local bodyHolder = new("Frame", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(MODAL_PAD, TITLE_H + 10), Size = UDim2.new(1, -2 * MODAL_PAD, 1, -TITLE_H - 10 - MODAL_PAD),
	ZIndex = 2, Parent = modal,
})
local modalBody = new("ScrollingFrame", {
	BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = SCROLLBAR,
	ScrollBarImageColor3 = Color3.fromRGB(205, 210, 228), ScrollBarImageTransparency = 0,
	VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar, HorizontalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	Parent = bodyHolder,
})
local modalName: string? = nil
local renderModal: () -> ()

-- Money-dependent bits of the open window (buy buttons' colours, the money in the title bar, the Money
-- packs' amounts). Money ticks constantly: these update in place instead of rebuilding the window, so
-- a click or a drag in progress is never cut short.
local moneyWatchers: { () -> () } = {}
local function watchMoney(update: () -> ())
	update()
	table.insert(moneyWatchers, update)
end

local function closeModal()
	modal.Visible = false
	modalName = nil
end
modalClose.Activated:Connect(closeModal)

-- Fits the window on small screens (phones): never bigger than design size, never off the screen.
local function fitModal()
	local s = uiScale.Scale
	local w, h = gui.AbsoluteSize.X / s, gui.AbsoluteSize.Y / s
	local mw, mh = modal.Size.X.Offset, modal.Size.Y.Offset -- the open window's size (ShopLayout.window)
	-- Windows sit between Roblox's top bar (TOP) and the hotbar (BOTTOM), never over the Bat / Seeds slots.
	local TOP, BOTTOM = 44, 112
	modal.Position = UDim2.new(0.5, 0, 0.5, (TOP - BOTTOM) / 2)
	modalScale.Scale = math.clamp(math.min((w - 24) / (mw + 12), (h - TOP - BOTTOM - 12) / (mh + 12)), 0.3, 1)
end

----------------------------------------------------------------------------------------------------
-- Plants panel (right side): the one panel there (the Seeds menu is gone), with two tabs at its top.
--   Plants: "Plants 1/5 · $5/s", then one bright card per plant, best first: an accent strip in its rarity
--   (or mutation) colour, the plant's name (the flower it grew into), rarity, mutation and weight, its $/s
--   (with the day/night bonus while it's on) and a Remove button that asks once more ("Sure?" for 2 s).
--   Remove puts the plant in the Inventory, as it is (never money; the server re-checks it: remote
--   RemovePlant, one of your own plants).
--   Inventory: the seeds in the seed bag ("Rare Seed", their flower a surprise) and the removed plants
--   (their flower's name), each with a Plant button that starts the ghost planting preview
--   (Planting.client); the SELL stall sells them too. Full bag or inventory: a relief line says so.
--   Every card shows its flower in 3D (Shared/FlowerView, turning slowly while on screen): a plant its own
--   flower model (`flower` in the plants view), a bag seed its seed design (ReplicatedStorage.SeedLooks).
----------------------------------------------------------------------------------------------------
do
	local FlowerView = require(Shared:WaitForChild("FlowerView"))
	local RemovePlant = remotes:WaitForChild("RemovePlant") :: RemoteEvent
	-- The tabs, over the list
	sideList.Position = UDim2.fromOffset(10, 96)
	sideList.Size = UDim2.new(1, -20, 1, -106)
	local tabRow = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 48), Size = UDim2.new(1, -20, 0, 42), Parent = sidePanel }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10) }),
	})
	local tabButtons: { [string]: TextButton } = {}
	for _, name in { "Plants", "Inventory" } do
		tabButtons[name] = chunky(tabRow, name, COLORS.disabled, UDim2.fromOffset(148, 40), function()
			sideTab = name
			renderSide()
		end)
	end
	local function paintTabs()
		for name, b in tabButtons do
			b.BackgroundColor3 = if sideTab == name then COLORS.money else COLORS.disabled
		end
	end
	-- A line of relief text in the list (a free-placed label in its own row, so its dropped copy can sit
	-- behind it; UiFx.relief)
	local function reliefLine(order: number, words: string, color: Color3)
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 40), LayoutOrder = order, Parent = sideList })
		local label = bold(row, 3, { Text = words, Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 1), TextColor3 = color, TextWrapped = true })
		UiFx.relief(label, 3, 3)
	end
	local inventoryShown = "" -- what the Inventory shows
	local CARD_H = 70
	local VIEW = 62 -- the card's 3D picture, left of its words
	local TEXT_X, TEXT_W = 22 + VIEW + 4, -(118 + VIEW + 4)
	local SURE_SECONDS = 2
	local GREEN_INK, MUTED_INK = Color3.fromRGB(30, 160, 55), Color3.fromRGB(120, 124, 140)
	local shown = "" -- which plants the list shows, in order
	local updaters: { () -> () } = {}
	local sure: { [number]: number } = {} -- slot -> when its Remove was first clicked

	local function plantIn(slot: number): any
		for _, p in stats.plants or {} do
			if p.slot == slot then
				return p
			end
		end
		return nil
	end

	-- Dark text with no outline, for the white cards
	local function ink(parent: Instance, props: { [string]: any }): TextLabel
		local label = text(parent, props)
		label:FindFirstChildOfClass("UIStroke"):Destroy()
		label.TextColor3 = props.TextColor3 or INK
		label.TextXAlignment = Enum.TextXAlignment.Left
		return label
	end

	local function plantCard(order: number, p: any)
		local rarity = Config.RARITIES[p.rarity]
		local mut = Config.mutationById(p.mutation)
		local accent = if mut then mut.color else rarity.color
		local f = new("Frame", { Name = "Plant_" .. p.slot, Size = UDim2.new(1, -8, 0, CARD_H), BackgroundColor3 = WHITE, LayoutOrder = order, Parent = sideList }, {
			new("UICorner", { CornerRadius = UDim.new(0, 4) }),
			new("UIStroke", { Thickness = 2, Color = accent:Lerp(INK, 0.3), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, accent:Lerp(WHITE, 0.8)) }),
		})
		ShopUi.studs(f, accent) -- studded, under the strip, the 3D view and the words
		new("Frame", { Size = UDim2.new(0, 8, 1, -14), Position = UDim2.fromOffset(7, 7), BackgroundColor3 = accent, BorderSizePixel = 0, Parent = f },
			{ new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		FlowerView.show(f, FlowerView.flower(p.zone, p.rarity, p.flower), {
			size = UDim2.fromOffset(VIEW, VIEW), position = UDim2.new(0, 20, 0.5, 0), anchor = Vector2.new(0, 0.5), spin = true,
		})
		ink(f, { Text = p.name or SeedPacks.seedName(p.zone, p.rarity, p.mutation), Size = UDim2.new(1, TEXT_W, 0, 24), Position = UDim2.fromOffset(TEXT_X, 7) })
		local info = ink(f, { RichText = true, Size = UDim2.new(1, TEXT_W, 0, 16), Position = UDim2.fromOffset(TEXT_X, 31), TextColor3 = rarity.color:Lerp(INK, 0.45) })
		local income = ink(f, { RichText = true, Size = UDim2.new(1, TEXT_W, 0, 16), Position = UDim2.fromOffset(TEXT_X, 48), TextColor3 = GREEN_INK })

		local slot = p.slot
		local remove: TextButton
		local full = #(stats.inventory or {}) >= Config.INVENTORY_MAX -- (the list says so above)
		local function look()
			local pending = sure[slot] ~= nil and os.clock() - sure[slot] < SURE_SECONDS
			if not pending then
				sure[slot] = nil
			end
			local label = remove:FindFirstChild("Label") :: TextLabel
			label.Text = if pending then "Sure?" else "Remove"
			remove.BackgroundColor3 = if full then COLORS.disabled elseif pending then COLORS.gold else COLORS.red
		end
		remove = chunky(f, "Remove", COLORS.red, UDim2.fromOffset(88, 42), function()
			if full then
				return
			elseif sure[slot] and os.clock() - sure[slot] < SURE_SECONDS then
				sure[slot] = nil
				RemovePlant:FireServer(slot) -- the list rebuilds when the server's plants view comes back without it
			else
				sure[slot] = os.clock()
				task.delay(SURE_SECONDS, function()
					if remove.Parent then
						look()
					end
				end)
			end
			look()
		end)
		remove.Name = "Remove"
		remove.AnchorPoint = Vector2.new(1, 0.5)
		remove.Position = UDim2.new(1, -8, 0.5, 0)
		look()

		local function update()
			local now = plantIn(slot) or p
			info.Text = `{rarity.id}{if mut then ` · <font color="#{mut.color:ToHex()}">{mut.id}</font>` else ""}`
			local bonus = Config.bonusLabel(now.zone, (Config.dayPhase(workspace:GetServerTimeNow())))
			income.Text = `{Format.money(now.income)}/s{if bonus then ` · <font color="#{MUTED_INK:ToHex()}">{bonus}</font>` else ""}`
		end
		update()
		table.insert(updaters, update)
	end

	-- One Inventory card: a seed from the bag or a removed plant (`look`: its seed design or flower), with its
	-- Plant button.
	local function itemCard(order: number, name: string, sub: string, rarityIndex: number, mutation: string?, key: string, look: Model?)
		local rarity = Config.RARITIES[rarityIndex]
		local mut = Config.mutationById(mutation)
		local accent = if mut then mut.color else rarity.color
		local f = new("Frame", { Name = "Item_" .. key, Size = UDim2.new(1, -8, 0, CARD_H), BackgroundColor3 = WHITE, LayoutOrder = order, Parent = sideList }, {
			new("UICorner", { CornerRadius = UDim.new(0, 4) }),
			new("UIStroke", { Thickness = 2, Color = accent:Lerp(INK, 0.3), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, accent:Lerp(WHITE, 0.8)) }),
		})
		ShopUi.studs(f, accent) -- studded, under the strip, the 3D view and the words
		new("Frame", { Size = UDim2.new(0, 8, 1, -14), Position = UDim2.fromOffset(7, 7), BackgroundColor3 = accent, BorderSizePixel = 0, Parent = f },
			{ new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		FlowerView.show(f, look, { size = UDim2.fromOffset(VIEW, VIEW), position = UDim2.new(0, 20, 0.5, 0), anchor = Vector2.new(0, 0.5), spin = true })
		ink(f, { Text = name, Size = UDim2.new(1, TEXT_W, 0, 24), Position = UDim2.fromOffset(TEXT_X, 7), TextColor3 = accent:Lerp(INK, 0.45) })
		ink(f, { Text = sub, Size = UDim2.new(1, TEXT_W, 0, 16), Position = UDim2.fromOffset(TEXT_X, 35), TextColor3 = MUTED_INK })
		local plant = chunky(f, "Plant", COLORS.money, UDim2.fromOffset(88, 42), function()
			RequestUseItem:FireServer("Seed:" .. key) -- the server answers with the planting preview (PlaceSeed)
		end)
		plant.Name = "Plant"
		plant.AnchorPoint = Vector2.new(1, 0.5)
		plant.Position = UDim2.new(1, -8, 0.5, 0)
	end

	local function renderInventory(full: boolean?)
		local inventory = stats.inventory or {}
		local bag = bagEntries()
		local bagCount = SeedPacks.bagCount(stats.seedBag or {})
		Icons.set(sideTitle, "Plants", `🪴 Inventory {#inventory}/{Config.INVENTORY_MAX} · Seeds {bagCount}/{Config.SEED_BAG_MAX}`)
		local c = stats.carrying
		local stuck = c ~= nil and bagCount >= Config.SEED_BAG_MAX
		local keys = { tostring(stuck) }
		for _, e in bag do
			table.insert(keys, `{e.key}x{e.count}`)
		end
		for _, p in inventory do
			table.insert(keys, `{p.id}:{p.name or ""}`)
		end
		local signature = table.concat(keys, ",")
		if not full and signature == inventoryShown then
			return
		end
		inventoryShown = signature
		clearSide()
		table.clear(updaters)
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		if stuck then -- a seed brought home goes to the bag by itself, unless the bag is full
			reliefLine(nextOrder(), "Seed bag full: plant or sell to make room for your seed!", COLORS.red)
		end
		if #inventory >= Config.INVENTORY_MAX then
			reliefLine(nextOrder(), "Inventory full: plant or sell some plants.", COLORS.red)
		end
		if #bag == 0 and #inventory == 0 then
			reliefLine(nextOrder(), "Removed plants and seeds from packs wait here.", WHITE)
		end
		for _, e in bag do
			local _, _, _, gene = SeedPacks.parseBagKey(e.key)
			itemCard(nextOrder(), SeedPacks.seedName(e.zone, e.rarity, e.mutation), `x{e.count} · {Config.ZONES[e.zone].name}`, e.rarity, e.mutation, e.key,
				FlowerView.seed(e.zone, gene))
		end
		for _, p in inventory do
			local rarity = Config.RARITIES[p.rarity]
			itemCard(nextOrder(), p.name or SeedPacks.seedName(p.zone, p.rarity, p.mutation),
				`{rarity.id}{if p.mutation then " · " .. p.mutation else ""} · {Config.ZONES[p.zone].name}`, p.rarity, p.mutation, `inv:{p.id}`,
				FlowerView.flower(p.zone, p.rarity, p.flower))
		end
	end

	renderPlants = function(full: boolean?)
		paintTabs()
		if sideTab == "Inventory" then
			renderInventory(full)
			return
		end
		local plants = table.clone(stats.plants or {})
		table.sort(plants, function(a, b)
			if a.income ~= b.income then
				return a.income > b.income
			end
			return a.slot < b.slot
		end)
		Icons.set(sideTitle, "Plants", `🪴 Plants {#plants}/{stats.slots} · {Format.money(stats.income)}/s`)
		local keys = {}
		for _, p in plants do
			table.insert(keys, `{p.slot}:{p.zone}:{p.rarity}:{p.mutation or ""}:{p.name or ""}`)
		end
		table.insert(keys, tostring(#(stats.inventory or {}) >= Config.INVENTORY_MAX)) -- (Remove is off while it's full)
		local signature = table.concat(keys, ",")
		if not full and signature == shown then
			for _, update in updaters do

				update()
			end
			return
		end
		shown = signature
		clearSide()
		table.clear(updaters)
		if #(stats.inventory or {}) >= Config.INVENTORY_MAX then
			reliefLine(-1, "Inventory full: plant or sell some plants before removing more.", COLORS.red)
		end
		if #plants == 0 then
			local f = card(0, WHITE, 60)
			ink(f, { Text = "No plants yet. Steal a seed and plant it on your dirt!", Size = UDim2.new(1, -16, 1, -12), Position = UDim2.fromOffset(8, 6), TextWrapped = true })
		end
		for i, p in plants do
			plantCard(i, p)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Trail Shop strip scrolling: the scrollbar, drag and touch are the ScrollingFrame's own; the mouse wheel
-- and the side arrows move it a card at a time.
----------------------------------------------------------------------------------------------------
local TRAIL_W, TRAIL_H, TRAIL_GAP = 250, 452, 14
local trailCards: { GuiObject } = {}

local function scrollTrails(cards: number, smooth: boolean)
	-- Roblox clamps CanvasPosition to the canvas, so going past either end just stops there
	local target = Vector2.new(math.max(0, modalBody.CanvasPosition.X + cards * (TRAIL_W + TRAIL_GAP)), 0)
	if smooth then
		TweenService:Create(modalBody, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CanvasPosition = target }):Play()
	else
		modalBody.CanvasPosition = target
	end
end

local function trailArrow(dir: number): TextButton
	local b = new("TextButton", {
		AnchorPoint = Vector2.new(if dir < 0 then 0 else 1, 0.5), Position = UDim2.new(if dir < 0 then 0 else 1, 6 * dir, 0.5, -SCROLLBAR / 2),
		Size = UDim2.fromOffset(46, 86), BackgroundColor3 = FRAME_INK, BackgroundTransparency = 0.15, Text = "", AutoButtonColor = true,
		Visible = false, ZIndex = 5, Parent = bodyHolder,
	}, { new("UIStroke", { Thickness = 3, Color = WHITE, Transparency = 0.35 }) })
	bold(b, 3, { Text = if dir < 0 then "<" else ">", Size = UDim2.new(1, -8, 0, 52), Position = UDim2.new(0, 4, 0.5, -26), ZIndex = 5 })
	b.Activated:Connect(function()
		scrollTrails(dir, true)
	end)
	return b
end
local arrowLeft, arrowRight = trailArrow(-1), trailArrow(1)

-- Each arrow shows while there are cards hidden on its side (measured on screen, so any UIScale works).
local function updateTrailArrows()
	local first, last = trailCards[1], trailCards[#trailCards]
	local show = modal.Visible and modalName == "Trails" and first ~= nil and first.Parent ~= nil and last.Parent ~= nil
	local left = modalBody.AbsolutePosition.X
	local right = left + modalBody.AbsoluteWindowSize.X
	arrowLeft.Visible = show and first.AbsolutePosition.X < left - 4
	arrowRight.Visible = show and last.AbsolutePosition.X + last.AbsoluteSize.X > right + 4
end
for _, prop in { "CanvasPosition", "AbsoluteCanvasSize", "AbsoluteWindowSize" } do
	modalBody:GetPropertyChangedSignal(prop):Connect(updateTrailArrows)
end

-- The mouse wheel over the strip scrolls it sideways (unless Roblox already did it on its own).
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseWheel or modalName ~= "Trails" or not modal.Visible then
		return
	end
	local p, a, s = input.Position, modalBody.AbsolutePosition, modalBody.AbsoluteSize
	if p.X < a.X or p.X > a.X + s.X or p.Y < a.Y or p.Y > a.Y + s.Y then
		return
	end
	local before = modalBody.CanvasPosition.X
	local notches = -input.Position.Z -- wheel down (Z < 0) goes right
	task.defer(function()
		if modalBody.CanvasPosition.X == before then
			scrollTrails(notches * 0.5, false)
		end
	end)
end)

-- Body layout: a vertical list (Shop, Index) or one horizontal row (Trail Shop).
local function clearModal(padding: number, horizontal: boolean?)
	modalBody:ClearAllChildren()
	modalBody.ScrollingDirection = if horizontal then Enum.ScrollingDirection.X else Enum.ScrollingDirection.Y
	modalBody.AutomaticCanvasSize = if horizontal then Enum.AutomaticSize.X else Enum.AutomaticSize.Y
	modalBody.CanvasSize = UDim2.new()
	new("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = if horizontal then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Center,
		VerticalAlignment = if horizontal then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top,
		Parent = modalBody,
	})
	new("UIPadding", {
		PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = modalBody,
	})
end

openModal = function(name: string)
	if modalName == name then
		closeModal()
		return
	end
	local window = WINDOWS[name]
	modalName = name
	local w, h = ShopLayout.window(name) -- the Shop is wider
	modal.Size = UDim2.fromOffset(w, h)
	fitModal()
	titleBar.BackgroundColor3 = window.bar
	ShopUi.paintStuds(titleBar, window.bar)
	modalTitle.Text = window.title -- words only, in relief
	Icons.set(modalSubtitle, {}, "") -- the window's render may fill it
	modal.Visible = true
	modalBody.CanvasPosition = Vector2.zero
	renderModal()
end

-- Opens the Shop (or re-renders it) scrolled to a section (see renderShop's `shopSections`).
local shopFocus: string? = nil
openShopAt = function(sectionName: string)
	shopFocus = sectionName
	if modalName == "Shop" then
		renderModal()
	else
		openModal("Shop")
	end
end

-- Walk-up stalls in the base's shop plaza: their prompts say which menu to open ("Shop", "Trails" or
-- "Index"; the SELL stall's "Sell" is handled in the SELL window's block). Always opens (never toggles shut).
game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt: ProximityPrompt)
	local opens = prompt:GetAttribute("OpensShop")
	if (opens == "Shop" or opens == "Trails" or opens == "Index") and modalName ~= opens then
		openModal(opens)
	end
end)

-- A light info line in the modal body, with `icon` (key(s), see Icons.set) once uploaded
local function note(label: string, order: number, icon: (string | { string })?)
	local h = text(modalBody, {
		Text = label, Size = UDim2.new(1, -12, 0, 26), TextColor3 = NOTE_COLOR, LayoutOrder = order, TextWrapped = true,
	})
	if icon then
		Icons.set(h, icon, label, ICON.medium)
	end
end

-- "-- SPEED --": a big section title in yellow or cyan relief (words only: the cards carry the icons), in
-- its own row so its dropped shadow (UiFx.relief) sits behind it. Returns the row.
local function section(label: string, order: number, color: Color3): Frame
	local row = new("Frame", { Name = "Section_" .. label, BackgroundTransparency = 1, Size = UDim2.new(1, -12, 0, 56), LayoutOrder = order, Parent = modalBody })
	UiFx.relief(bold(row, 4, { Text = `-- {label} --`, Size = UDim2.new(1, 0, 0, 48), Position = UDim2.fromOffset(0, 2), TextColor3 = color }), 4, 5)
	return row
end

-- Scrolls the modal body so `target` sits at its top, once the layout has placed it. Measured from
-- the target's on-screen position and corrected over a few frames, so it holds under any UIScale.
local function scrollModalTo(target: GuiObject)
	task.spawn(function()
		local ratio = 1 -- on-screen pixels per CanvasPosition pixel, learnt from the first step
		for _ = 1, 4 do
			task.wait()
			if not target.Parent or not modal.Visible then
				return
			end
			local off = target.AbsolutePosition.Y - modalBody.AbsolutePosition.Y
			if math.abs(off) < 2 then
				return
			end
			local before, beforeY = modalBody.CanvasPosition.Y, target.AbsolutePosition.Y
			modalBody.CanvasPosition = Vector2.new(0, math.max(0, before + off / ratio))
			task.wait()
			local moved = beforeY - target.AbsolutePosition.Y
			local applied = modalBody.CanvasPosition.Y - before
			if applied == 0 or moved == 0 then
				return -- at the end of the canvas
			end
			ratio = moved / applied
		end
	end)
end

-- Robux prices. Developer products' real prices are set on the Creator Dashboard, so each is fetched
-- once per id with GetProductInfo (pcall'd, cached). Until then, or with no id yet, the placeholder
-- from Config is shown. Gamepasses (`infoType` GamePass) the same way.
local robuxPrices: { [string]: number } = {}
local priceFetching: { [string]: boolean } = {}
local priceRerender = false
local function robuxPrice(product: { id: number, robux: number }, infoType: Enum.InfoType?): number
	local kind = infoType or Enum.InfoType.Product
	local key = kind.Name .. product.id
	local cached = robuxPrices[key]
	if cached then
		return cached
	end
	if product.id ~= 0 and not priceFetching[key] then
		priceFetching[key] = true
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, product.id, kind)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				robuxPrices[key] = info.PriceInRobux
				if not priceRerender then -- one re-render for a burst of answers
					priceRerender = true
					task.delay(0.3, function()
						priceRerender = false
						if modal.Visible and (modalName == "Shop" or modalName == "Trails") then
							renderModal()
						end
					end)
				end
			else
				task.delay(30, function() -- let a later render try again
					priceFetching[key] = nil
				end)
			end
		end)
	end
	return product.robux
end

-- A Robux button's colour: `color`, a little greyed while the product has no id yet (no tag on it:
-- clicking still asks the server, which answers "coming soon").
local function robuxColor(id: number, color: Color3): Color3
	return if id == 0 then color:Lerp(Color3.fromRGB(150, 160, 150), 0.3) else color
end

-- Gifting needs extra work (choosing a player, granting to them): the gift buttons are shown, not live yet.
local function giftSoon()
	toast("Gifting is coming soon!", "blue", nil, "Gift")
end

----------------------------------------------------------------------------------------------------
-- Shop (owner references 2026-10-15, round 2: "premium, square, lively"): a wide window (ShopLayout),
-- section titles in yellow / cyan relief, then square cards with a thin bright outline and vivid art edge
-- to edge (their paint, a sunburst and its glow, white speckles):
--   * SEED PACKS: one wide featured card per pack in its zone's colours, gold-outlined: a red "New!" tag,
--     the pack's name in gold relief, what it can give as square 3D tiles with the exact odds
--     (SeedPacks.showcase: the zone's flower per rarity, the Legendary big in a rainbow frame at the right);
--   * PASSES: wide cards two a row, each in its pass's vivid colours (a rainbow for Fast Grow): a big square
--     badge with the icon, the name, the benefit with its number in green;
--   * SPEED / MONEY: a full-width "DOUBLE Your ..." banner for the matching pass, then cards three a row on
--     a blue (Speed) or gold (Money) sunburst whose art grows with the pack (Shared/ShopArt: one sneaker
--     ... a sack ... a chest overflowing with them), "+150K SPEED" with the amount in green (yellow for big packs);
--   * UPGRADES: the plot and treadmill cards with a $ and an R$ button.
-- The buttons are like the reference's: a square purple gift button with a white gift, then a green R$
-- button sized to its price (the white Robux icon first), a small caption under it, straight on the card
-- art. ShopLayout places them and decides how much each pops, so a hovered button never grows past its
-- card or into its neighbour. No card is green, so the green R$ button always stands out.
----------------------------------------------------------------------------------------------------
local packShines: { Frame } = {} -- swept across the pack cards every frame while they're shown
local renderShop: () -> boolean
do
	local PassCards = require(Shared:WaitForChild("PassCards"))
	local ShopArt = require(Shared:WaitForChild("ShopArt"))
	local FlowerView = require(Shared:WaitForChild("FlowerView"))
	local L = ShopLayout
	local PACK_W = L.CONTENT_W -- the pack cards and banners span the Shop
	local CARD_COLORS = {
		Speed = Color3.fromRGB(30, 165, 255),
		Money = Color3.fromRGB(255, 185, 25), -- warm gold, never green: the green R$ button must stand out
		PlotUpgrade = Color3.fromRGB(150, 85, 255), -- violet: its gold $ button stands out
		Treadmill = Color3.fromRGB(255, 60, 95),
	}
	local SACKS = { Speed = Color3.fromRGB(214, 158, 92), Money = Color3.fromRGB(60, 170, 70) } -- burlap on the blue cards, green on the gold
	local YELLOW_NUMBER = "#FFE13C" -- the big packs' amounts
	local BUTTON_Z = 7 -- over the card's art
	local RAINBOW = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 170, 40)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 235, 60)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 230, 110)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(60, 170, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 90, 255)),
	})

	-- A sunburst: soft white rays turning around (cx, cy) (scale of the card), `reach` long, over a glow,
	-- fading out toward the card's edges (the card clips them).
	local function sunburst(c: Frame, cx: number, cy: number, reach: number)
		local burst = new("Frame", {
			Name = "Sunburst", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(cx, cy),
			Size = UDim2.fromOffset(1, 1), Parent = c,
		})
		local fade = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(0.7, 0.55), NumberSequenceKeypoint.new(1, 1),
		})
		for i = 0, 8 do -- each bar through the centre is two rays: 18 rays
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(reach * 1.5, 26), Rotation = i * 20 + 8, BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.55, BorderSizePixel = 0, Parent = burst,
			}, { new("UIGradient", { Transparency = fade }) })
		end
		for _, glow in { { 190, 0.86 }, { 130, 0.8 }, { 76, 0.72 } } do
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(glow[1], glow[1]), BackgroundColor3 = WHITE, BackgroundTransparency = glow[2],
				BorderSizePixel = 0, Parent = burst,
			}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) }) -- round: the glow is light, not a frame
		end
	end

	-- A vivid diagonal paint job (light corner, full colour, a darker corner), or a rainbow.
	local function paint(c: GuiObject, color: Color3, rainbow: boolean?)
		c.BackgroundColor3 = WHITE
		new("UIGradient", {
			Rotation = 30,
			Color = if rainbow then RAINBOW else ColorSequence.new({
				ColorSequenceKeypoint.new(0, color:Lerp(WHITE, 0.45)), ColorSequenceKeypoint.new(0.55, color),
				ColorSequenceKeypoint.new(1, color:Lerp(Color3.new(0, 0, 0), 0.25)),
			}),
			Parent = c,
		})
	end

	-- A card: square, a thin bright outline in its colour (gold for the featured packs), clipping its art.
	-- Painted `color` with its sunburst at (cx, cy) and `speckles` white sparkles placed by `seed`.
	local cardSeed = 0
	local function cardFrame(parent: Instance, order: number, color: Color3, props: { [string]: any }?, rainbow: boolean?): Frame
		local c = new("Frame", { LayoutOrder = order, ClipsDescendants = true, BorderSizePixel = 0, Parent = parent }, {
			outline(L.CARD_STROKE, color:Lerp(WHITE, 0.6)),
		})
		for k, v in props or {} do
			(c :: any)[k] = v
		end
		paint(c, color, rainbow)
		ShopUi.studs(c, if rainbow then nil else color, nil, 1) -- fine raised studs over the paint, under the art
		cardSeed += 1
		ShopUi.speckles(c, cardSeed, 12, 1)
		return c
	end

	-- The benefit's number ("x2", "2x", "x1.25", "+10") in green, like the reference's "Get x2 Money!".
	local function emphasize(words: string): string
		for _, pattern in { "x%d[%d%.]*", "%d[%d%.]*x", "%+%d[%d%.,]*%a*", "Doubles", "Rarer" } do
			local a, b = string.find(words, pattern)
			if a and b then
				return `{string.sub(words, 1, a - 1)}<font color="{NUMBER_GREEN}">{string.sub(words, a, b)}</font>{string.sub(words, b + 1)}`
			end
		end
		return words
	end

	-- One buy button of a row: its text, colour, the Robux icon (`robux`), the gift button before it
	-- (`gift`), the caption under it; `still`: no pop (an "Owned" button does nothing).
	type Buy = { text: string, color: Color3, robux: boolean, gift: boolean, caption: string?, onClick: () -> (), still: boolean? }

	-- A row of buttons on card `c` (cardW x cardH) at `y`, centred between `left` and `right` (ShopLayout.row
	-- places them and sets each one's pop). Returns the buy buttons, in order.
	local function buttonRow(c: Frame, cardW: number, cardH: number, y: number, buys: { Buy }, left: number?, right: number?): { TextButton }
		local specs: { ShopLayout.Button } = {}
		for _, b in buys do
			if b.gift then
				table.insert(specs, { kind = "gift" })
			end
			table.insert(specs, { kind = "buy", text = b.text, icon = b.robux and Icons.image("Robux") ~= nil, caption = b.caption })
		end
		local out = {}
		for _, p in L.row(specs, cardW, cardH, y, left, right) do
			if p.kind == "gift" then
				local g = ShopUi.button(c, p, GIFT_PINK, BUTTON_Z)
				ShopUi.giftIcon(g, GIFT_PINK:Lerp(Color3.new(0, 0, 0), 0.35))
				g.Activated:Connect(giftSoon)
			else
				local spec = buys[#out + 1]
				local b = ShopUi.button(c, p, spec.color, BUTTON_Z)
				b.Activated:Connect(spec.onClick)
				if spec.still then
					b:SetAttribute("PopScale", nil)
					b:SetAttribute("NoPop", true)
				end
				ShopUi.price(b, p.text or "", spec.robux)
				ShopUi.caption(c, p, BUTTON_Z)
				table.insert(out, b)
			end
		end
		return out
	end

	-- A Robux buy (gift + green R$ button) at `price` ("Buy" while there is no price), asking the server for `request`.
	local function robuxBuy(price: number, id: number, request: string, caption: string?): Buy
		return {
			text = if price > 0 then Format.commas(price) else "Buy", color = robuxColor(id, ROBUX_GREEN), robux = price > 0, gift = true, caption = caption,
			onClick = function()
				RequestBuy:FireServer(request)
			end,
		}
	end

	----------------------------------------------------------------------------------------------------
	-- SEED PACKS: the featured card
	----------------------------------------------------------------------------------------------------
	local function mutationLine(pack: SeedPacks.Pack): string
		local parts = {}
		for _, m in SeedPacks.odds(pack).mutations do
			local mut = Config.mutationById(m.id)
			table.insert(parts, `<font color="#{(if mut then mut.color else WHITE):ToHex()}">{m.id}</font> {SeedPacks.percent(m.pct)}`)
		end
		return "Mutations: " .. table.concat(parts, "  ·  ")
	end

	-- One reward tile: square, a thin dark outline, the flower in 3D, its rarity, its chance at the bottom
	-- right in white relief. The featured (Legendary) one is big, in a rainbow frame, turning slowly.
	local function rewardTile(c: Frame, zone: number, tile: SeedPacks.Tile, pos: UDim2, w: number, h: number)
		local rarity = Config.RARITIES[tile.rarity]
		local featured = tile.featured
		local f = new("Frame", {
			Name = "Tile_" .. tile.id, Position = pos, Size = UDim2.fromOffset(w, h), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3, Parent = c,
		})
		local stroke = outline(if featured then 5 else 2, if featured then WHITE else FRAME_INK)
		stroke.Parent = f
		if featured then
			f:SetAttribute("Featured", true)
			new("UIGradient", { Name = "Rainbow", Rotation = 35, Color = RAINBOW, Parent = stroke }) -- the rainbow frame
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(150, 80, 255), Color3.fromRGB(40, 20, 110)), Parent = f })
		else
			-- a shade darker than before, so the rarity-coloured name and % read over it
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new(rarity.color:Lerp(FRAME_INK, 0.2), rarity.color:Lerp(FRAME_INK, 0.62)), Parent = f })
			f.BackgroundTransparency = 0.15 -- the card's picture shows a little through
		end
		local top = if featured then 38 else 24
		FlowerView.show(f, FlowerView.flower(zone, tile.rarity, tile.flower), {
			size = UDim2.new(1, -8, 1, -(top + 4)), position = UDim2.fromOffset(4, top), zindex = 4, spin = featured, zoom = 1.25,
		})
		-- the rarity's name and its % in the rarity's colour (owner 2026-10-15), thick dark outline, relief
		local ink = if featured then COLORS.gold else SeedPacks.tileTextColor(tile.rarity)
		local name = bold(f, if featured then 4 else 3, {
			Text = if featured then "LEGENDARY" else rarity.id, Size = UDim2.new(1, -12, 0, top - 6), Position = UDim2.fromOffset(6, 4), ZIndex = 5,
			TextColor3 = ink,
		})
		UiFx.relief(name, 3, if featured then 4 else 3)
		UiFx.relief(bold(f, 3, {
			Text = SeedPacks.percent(tile.pct), Size = UDim2.new(1, -10, 0, if featured then 36 else 28), AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 4, 1, -4), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5,
			TextColor3 = ink,
		}), 3, 3)
	end

	-- One wide card per pack, spanning the Shop. No Speed gate: anyone can buy them.
	local function packCard(order: number, productName: string, product: Config.DevProduct, bagFull: boolean)
		local pack = SeedPacks.packForProduct(product)
		local zone = Config.ZONES[pack.zone]
		local c = cardFrame(modalBody, order, zone.ui, { Name = "Pack_" .. productName, Size = UDim2.new(1, -8, 0, L.PACK_H) })
		local stroke = c:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = COLORS.gold
		-- The owner's picture for the pack once it is uploaded (Icons.TEXTURES "<product>Bg"), cropped to the
		-- card and darkened at the top and the bottom so the title, the % and the buttons stay readable; the
		-- zone's colours and two sunbursts until then.
		local picture = Icons.image(productName .. "Bg")
		if picture then
			new("ImageLabel", {
				Name = "Background", Image = picture, ScaleType = Enum.ScaleType.Crop, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
				ZIndex = 1, Parent = c,
			})
			new("Frame", { Name = "Darken", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 1, Parent = c }, {
				new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.25, 0.85), NumberSequenceKeypoint.new(0.55, 0.8),
					NumberSequenceKeypoint.new(1, 0.15),
				}) }),
			})
			local studLayer = c:FindFirstChild("Studs") :: GuiObject
			studLayer.ZIndex = 2 -- the studs over the picture too
		else
			sunburst(c, 0.86, 0.42, 560)
			sunburst(c, 0.3, 0.55, 560)
		end
		table.insert(packShines, new("Frame", { Size = UDim2.new(0, 90, 1, 0), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2, Parent = c }, {
			new("UIGradient", { Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.7), NumberSequenceKeypoint.new(1, 1),
			}) }),
		}))

		-- The red "New!" tag, the pack's name in gold relief, where its seed comes from
		UiFx.relief(ShopUi.tag(c, "New!", UDim2.fromOffset(18, 16), UDim2.fromOffset(116, 44), 4), 3, 3)
		UiFx.relief(bold(c, 5, {
			Name = "Title", Text = string.upper(pack.name), Size = UDim2.new(1, -184, 0, 54), Position = UDim2.fromOffset(150, 8),
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 220, 50), ZIndex = 4,
		}), 4, 5)
		bold(c, 3, {
			Text = `{zone.name} seed · no Speed needed`, Size = UDim2.new(1, -184, 0, 24), Position = UDim2.fromOffset(152, 62),
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 245, 210), ZIndex = 3,
		})

		-- The rewards: Common..Epic growing a little left to right, the Legendary big at the right
		local tiles = SeedPacks.showcase(pack, stats.catalog)
		local bottom, featuredW, gap = 262, 220, 12
		local small = 0
		for _, tile in tiles do
			small += if tile.featured then 0 else 1
		end
		local smallW = math.floor((PACK_W - 36 - featuredW - 18 - (small - 1) * gap) / math.max(small, 1))
		local x = 18
		local n = 0
		for _, tile in tiles do
			if tile.featured then
				rewardTile(c, pack.zone, tile, UDim2.new(1, -(18 + featuredW), 0, 94), featuredW, bottom - 94) -- at the right edge
			else
				n += 1
				local h = 124 + (n - 1) * 8
				rewardTile(c, pack.zone, tile, UDim2.fromOffset(x, bottom - h), smallW, h)
				x += smallW + gap
			end
		end

		-- Mutations and income, then the gift + R$ buttons straight on the art. Robux only: with id = 0 the
		-- server answers "coming soon"; with a full bag it won't prompt.
		bold(c, 2, { RichText = true, Text = mutationLine(pack), Size = UDim2.new(1, -36, 0, 22), Position = UDim2.fromOffset(18, bottom + 8), ZIndex = 3 })
		local exclusive = Config.mutationById(pack.exclusive)
		bold(c, 2, {
			Text = `{Format.money(Config.seedIncome(pack.zone))}/s per Common sprout`
				.. (if exclusive then ` · {exclusive.id} x{exclusive.income} income, only from packs` else ""),
			Size = UDim2.new(1, -36, 0, 20), Position = UDim2.fromOffset(18, bottom + 32), TextColor3 = Color3.fromRGB(255, 245, 210), ZIndex = 3,
		})
		local buy = robuxBuy(robuxPrice(product), product.id, "Product:" .. productName, if bagFull then "Bag full!" else "1 Seed")
		if bagFull then
			buy.color = COLORS.disabled
		end
		buttonRow(c, PACK_W, L.PACK_H, L.bottomY(L.PACK_H, true), { buy })
	end

	----------------------------------------------------------------------------------------------------
	-- The other cards
	----------------------------------------------------------------------------------------------------
	-- A grid of cards (`w` x `h` cells, three a row by default), auto-sized to its contents.
	local function cardGrid(order: number, w: number?, h: number?): Frame
		return new("Frame", {
			BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = modalBody,
		}, {
			new("UIGridLayout", {
				CellSize = UDim2.fromOffset(w or L.CARD_W, h or L.CARD_H), CellPadding = UDim2.fromOffset(L.GAP, L.GAP), SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			}),
		})
	end

	-- A three-a-row card: `color`, light rays behind a big icon (or `art`), the amount in big relief rich
	-- text ("+150K" can be green) and, only when `sub` isn't "", a short line under it. The caller adds the
	-- buttons (buttonRow). Returns the card and its amount label.
	local function shopCard(grid: Instance, order: number, color: Color3, amount: string, sub: string, icon: string, art: ((c: Frame, size: number) -> ())?): (Frame, TextLabel)
		local c = cardFrame(grid, order, color)
		local short = sub ~= ""
		local artSize = if short then 128 else 152
		sunburst(c, 0.5, (6 + artSize / 2) / L.CARD_H, L.CARD_W)
		if art then
			art(c, artSize)
		elseif icon ~= "" then
			bigIcon(c, icon, { Size = UDim2.fromOffset(artSize, artSize), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), ZIndex = 2 })
		end
		local amountLabel = bold(c, 4, {
			Name = "Amount", Text = amount, RichText = true, Size = UDim2.new(1, -20, 0, 48), Position = UDim2.fromOffset(10, artSize + 8), ZIndex = 5,
		})
		UiFx.relief(amountLabel, 4, 4)
		if short then
			bold(c, 2, { Text = sub, Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, artSize + 56), ZIndex = 5 })
		end
		return c, amountLabel
	end

	-- A Speed or Money pack (developer product `name`): its art grows with the pack (`level`, ShopArt).
	local function productCard(grid: Instance, order: number, name: string, product: Config.DevProduct, color: Color3, amount: string, level: number, key: string): (Frame, TextLabel)
		local c, amountLabel = shopCard(grid, order, color, amount, "", "", function(c: Frame, size: number)
			ShopArt.build(c, level, UDim2.new(0.5, 0, 0, 4), size, { key = key, sackColor = SACKS[key] or color, zindex = 2 })
		end)
		buttonRow(c, L.CARD_W, L.CARD_H, L.bottomY(L.CARD_H, true), { robuxBuy(robuxPrice(product), product.id, "Product:" .. name, "Instant") })
		return c, amountLabel
	end

	-- A card's $ button (gold while affordable) and, while there's a product for it, a green R$ one.
	local function upgradeButtons(c: Frame, price: number?, buy: string, productName: string?, product: Config.DevProduct?)
		local buys: { Buy } = {
			{
				text = if price then Format.money(price) else "Maxed", color = COLORS.disabled, robux = false, gift = false, caption = if price then "Cash" else nil,
				still = price == nil,
				onClick = function()
					RequestBuy:FireServer(buy)
				end,
			},
		}
		if price and productName and product then
			local r = robuxBuy(robuxPrice(product), product.id, "Product:" .. productName, "Instant")
			r.gift = false
			table.insert(buys, r)
		end
		local money = buttonRow(c, L.CARD_W, L.CARD_H, L.bottomY(L.CARD_H, true), buys)[1]
		watchMoney(function()
			money.BackgroundColor3 = if price and stats.money >= price then COLORS.shop else COLORS.disabled
		end)
	end

	-- A pass's wide card: its vivid colours, a big square badge with its icon (VIP: a gold relief "VIP"),
	-- the name, the benefit with its number in green; gold outline once owned.
	local function passCard(g: Instance, i: number, view: PassCards.Card): Frame
		local c = cardFrame(g, i, view.color, nil, view.rainbow)
		sunburst(c, 74 / L.WIDE_W, 0.36, L.WIDE_W)
		shine(c)
		local badge = new("Frame", { Name = "Badge", Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(112, 112), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2, Parent = c }, {
			outline(4),
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE:Lerp(view.color, 0.15), view.color:Lerp(Color3.new(0, 0, 0), 0.2)) }),
		})
		ShopUi.bevel(badge)
		if view.icon and view.coin then -- 2x Money: the cash on a gold coin, an "x2" stamped on it
			local coin = new("Frame", {
				Name = "Coin", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(96, 96),
				BackgroundColor3 = WHITE, ZIndex = 3, Parent = badge,
			}, {
				new("UICorner", { CornerRadius = UDim.new(1, 0) }), -- round: a coin (art)
				new("UIStroke", { Thickness = 4, Color = Color3.fromRGB(150, 85, 0) }),
				new("UIGradient", { Rotation = 45, Color = ColorSequence.new(Color3.fromRGB(255, 236, 120), Color3.fromRGB(235, 150, 10)) }),
			})
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.78, 0.78), BackgroundTransparency = 1, ZIndex = 3,
				Parent = coin,
			}, {
				new("UICorner", { CornerRadius = UDim.new(1, 0) }), -- round: the coin's inner ring (art)
				new("UIStroke", { Thickness = 3, Color = Color3.fromRGB(255, 250, 200), Transparency = 0.3 }),
			})
			bigIcon(coin, view.icon, { Size = UDim2.fromOffset(70, 70), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, -4, 0.5, -6), ZIndex = 4 })
			UiFx.relief(bold(coin, 4, {
				Name = "Stamp", Text = view.coin, TextColor3 = Color3.fromRGB(255, 214, 40), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 6, 1, 4),
				Size = UDim2.fromOffset(58, 40), ZIndex = 5,
			}), 3, 4)
		elseif view.icon then
			bigIcon(badge, view.icon, { Size = UDim2.fromOffset(88, 88), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 3 })
		else -- no icon: a gold relief "VIP" badge where the icon goes
			UiFx.relief(bold(badge, 5, {
				Text = "VIP", TextColor3 = Color3.fromRGB(255, 206, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(96, 58), ZIndex = 3,
			}), 4, 5)
		end
		local pass = Config.GAMEPASSES[view.name]
		UiFx.relief(bold(c, 4, {
			Name = "Title", Text = if pass then pass.label else view.title, Size = UDim2.new(1, -156, 0, 44), Position = UDim2.fromOffset(142, 10), ZIndex = 3,
		}), 3, 4)
		bold(c, 3, {
			Name = "About", RichText = true, Text = emphasize(view.about), TextWrapped = true, Size = UDim2.new(1, -156, 0, 60), Position = UDim2.fromOffset(142, 58),
			ZIndex = 3,
		})
		if view.owned then
			(c:FindFirstChildOfClass("UIStroke") :: UIStroke).Color = COLORS.gold
		end
		return c
	end

	-- "DOUBLE Your SPEED": a full-width banner for the matching pass at the top of its section.
	local function banner(order: number, passName: string, word: string, color: Color3, icon: string)
		local pass = Config.GAMEPASSES[passName]
		if not pass then
			return
		end
		local owned = stats.passes ~= nil and stats.passes[passName] == true
		local c = cardFrame(modalBody, order, color, { Name = "Banner_" .. passName, Size = UDim2.new(1, -8, 0, L.BANNER_H) })
		sunburst(c, 0.08, 0.5, 700)
		shine(c)
		bigIcon(c, icon, { Size = UDim2.fromOffset(104, 104), Position = UDim2.fromOffset(18, 14), Rotation = -8, ZIndex = 3 })
		UiFx.relief(bold(c, 5, {
			RichText = true, Text = `<font color="{NUMBER_GREEN}">DOUBLE</font> Your {word}`, Size = UDim2.new(1, -560, 0, 62), Position = UDim2.fromOffset(136, 12),
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
		}), 4, 5)
		bold(c, 3, {
			RichText = true, Text = emphasize(pass.about), Size = UDim2.new(1, -560, 0, 30), Position = UDim2.fromOffset(138, 80),
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
		})
		local buy = if owned
			then { text = "Owned", color = PassCards.OWNED, robux = false, gift = false, still = true, onClick = function() end } :: Buy
			else robuxBuy(robuxPrice(pass, Enum.InfoType.GamePass), pass.id, "Pass:" .. passName, "Forever")
		buttonRow(c, PACK_W, L.BANNER_H, math.floor((L.BANNER_H - L.BUTTON_H - L.CAPTION_H) / 2), { buy }, PACK_W - 420, PACK_W - 16)
	end

	-- Returns true when it scrolled to a section (openShopAt), so renderModal doesn't restore the old scroll.
	function renderShop(): boolean
		clearModal(12)
		cardSeed = 0
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		local shopSections: { [string]: GuiObject } = {}

		-- Seed packs (Robux)
		-- (the right edge's Featured shortcut opens the Shop here; owner 2026-10-15: "-- FEATURED --")
		shopSections.Featured = section("FEATURED", nextOrder(), HEADING_GOLD)
		local bagCount = SeedPacks.bagCount(stats.seedBag or {})
		local bagFull = bagCount >= Config.SEED_BAG_MAX
		for _, entry in Config.products("Pack") do
			packCard(nextOrder(), entry.name, entry.product, bagFull)
		end
		note(`Seed bag {bagCount}/{Config.SEED_BAG_MAX}{if bagFull then " (full: plant some first!)" else ""} · plant them from the Inventory in the Plants panel`, nextOrder())

		-- Gamepasses (Robux): a wide card per pass (Shared/PassCards decides what's on them), "Owned" once the
		-- server says so
		section("PASSES", nextOrder(), HEADING_CYAN)
		PassCards.render(cardGrid(nextOrder(), L.WIDE_W, L.WIDE_H), stats.passes, {
			card = passCard,
			button = function(c: Frame, view: PassCards.Card, onClick: () -> ()): GuiObject
				local pass = Config.GAMEPASSES[view.name]
				local buy: Buy = {
					text = if view.caption == "Owned" or view.caption == "Buy" then view.caption else Format.commas(robuxPrice(pass, Enum.InfoType.GamePass)),
					color = if view.owned then PassCards.OWNED else robuxColor(pass.id, ROBUX_GREEN), robux = not view.owned and view.caption ~= "Buy",
					gift = not view.owned, caption = if view.owned then nil else "Forever", still = view.owned, onClick = onClick,
				}
				return buttonRow(c, L.WIDE_W, L.WIDE_H, L.bottomY(L.WIDE_H, true), { buy }, 142, L.WIDE_W - L.MARGIN)[1]
			end,
			price = function(pass: Config.Gamepass): number
				return robuxPrice(pass, Enum.InfoType.GamePass)
			end,
			buy = function(name: string)
				RequestBuy:FireServer("Pass:" .. name)
			end,
		})

		-- Speed (Robux), blue; the HUD's "+" by the Speed number and the right edge's Speed shortcut open the Shop here
		shopSections.Speed = section("SPEED", nextOrder(), HEADING_GOLD)
		banner(nextOrder(), "DoubleSpeed", "SPEED", CARD_COLORS.Speed, "Speed")
		local grid = cardGrid(nextOrder())
		local speeds = Config.products("Speed")
		for i, entry in speeds do
			local level = ShopArt.level(i, #speeds)
			local amount, rest = string.match(string.upper(entry.product.label), "^(%S+)%s+(.+)$")
			local number = if level > ShopArt.LEVELS / 2 then YELLOW_NUMBER else NUMBER_GREEN
			productCard(grid, i, entry.name, entry.product, CARD_COLORS.Speed,
				if amount then `<font color="{number}">{amount}</font> {rest}` else string.upper(entry.product.label), level, "Speed")
		end

		-- Money (Robux), gold: each card's fixed amount (owner 2026-10-15: $24K ... $8M, whatever you earn)
		shopSections.Money = section("MONEY", nextOrder(), HEADING_CYAN) -- (the right edge's Money shortcut opens it here)
		banner(nextOrder(), "DoubleMoney", "MONEY", CARD_COLORS.Money, "Money")
		grid = cardGrid(nextOrder())
		local monies = Config.products("Money")
		for i, entry in monies do
			productCard(grid, i, entry.name, entry.product, CARD_COLORS.Money,
				`<font color="{NUMBER_GREEN}">+{Format.money(Config.moneyPackAmount(entry.product))}</font> CASH`, ShopArt.level(i, #monies), "Money")
		end

		-- Upgrades: the plot (also on the board at your plot's gate) and the treadmill's next tier (also on the
		-- prompts at your treadmill), for money or Robux. The R$ product is the one for the current price
		-- tier (looked up on every render); none at the last level.
		section("UPGRADES", nextOrder(), HEADING_GOLD)
		grid = cardGrid(nextOrder())
		local level = stats.plotLevel or 1
		local price = Config.priceOf("PlotUpgrade", stats :: any)
		local plotCard = shopCard(grid, 1, CARD_COLORS.PlotUpgrade, if price then `PLOT LEVEL {level + 1}` else "MAX LEVEL",
			if price then `+1 slot · cash x{Config.plotMoneyMult(level)} → x{Config.plotMoneyMult(level + 1)}`
				else `{Config.plotSlots(level)} slots · cash x{Config.plotMoneyMult(level)}`, "PlotUpgrade")
		upgradeButtons(plotCard, price, "PlotUpgrade", Config.plotUpgradeProduct(level))
		local tier = stats.treadmillTier or 1
		local treadPrice = Config.priceOf("TreadmillUpgrade", stats :: any)
		-- "+60/s": a second on it at that tier with your equipped trail and Speed passes (the "+X/s" over the treadmill)
		local function treadRate(t: number): string
			return Treadmill.rateText(Treadmill.perSecond(t, stats.equippedTrail, Config.passSpeedMult(stats.passes)))
		end
		local treadCard = shopCard(grid, 2, CARD_COLORS.Treadmill,
			if treadPrice then `LEVEL {tier + 1} TREADMILL` else "MAX TREADMILL",
			if treadPrice then `{treadRate(tier)} > {treadRate(tier + 1)} · Level {tier + 1}/{Config.TREADMILL_MAX}`
				else `{treadRate(tier)} · stand on it to gain Speed`, "Treadmill")
		upgradeButtons(treadCard, treadPrice, "TreadmillUpgrade", Config.treadmillUpgradeProduct(tier))

		local focus = shopFocus and shopSections[shopFocus]
		shopFocus = nil
		if focus then
			scrollModalTo(focus)
			return true
		end
		return false
	end
end

----------------------------------------------------------------------------------------------------
-- Trail Shop: one row of tall cards in the trail's colour, scrolling sideways. Name and rarity, the
-- Trail Shop icon tinted over a ribbon of the trail's colours, an "x2 Speed" pill, then a green $ button
-- and a bright green R$ button (like the Shop's), or Equip / Equipped once owned.
----------------------------------------------------------------------------------------------------
-- "+1", "+1.25", "+3": the Speed one step (stud) pays with the equipped trail (Config.speedPerStud)
local renderTrails: () -> ()
do
	local function perStepText(): string
		local x = Config.speedPerStud(stats.equippedTrail, Config.passSpeedMult(stats.passes))
		return "+" .. (if x < 100 then (string.gsub(string.format("%.2f", x), "%.?0+$", "")) else Format.short(x))
	end

	local function trailCard(parent: Instance, order: number, t: Config.Trail): Frame
		local owned = stats.trails[t.id] == true
		local equipped = stats.equippedTrail == t.id
		local c = new("Frame", { Size = UDim2.fromOffset(TRAIL_W, TRAIL_H), BackgroundColor3 = WHITE, LayoutOrder = order, Parent = parent }, {
			new("UIStroke", { Thickness = if equipped then 6 else 4, Color = if equipped then COLORS.gold else FRAME_INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		})
		if t.rainbow then
			new("UIGradient", { Rotation = 25, Color = Config.trailColors(t), Parent = c })
		else
			new("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, t.color:Lerp(WHITE, 0.45)),
					ColorSequenceKeypoint.new(0.5, t.color),
					ColorSequenceKeypoint.new(1, t.color:Lerp(Color3.new(0, 0, 0), 0.2)),
				}),
				Parent = c,
			})
		end
		ShopUi.studs(c, if t.rainbow then nil else t.color)
		shine(c)
		bold(c, 4, { Text = t.name, Size = UDim2.new(1, -16, 0, 42), Position = UDim2.fromOffset(8, 12) })
		bold(c, 3, { Text = t.rarity, Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 54) })

		-- Illustration: a soft glow, the trail streaming out behind, the Trail Shop icon tinted on top
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 196), Size = UDim2.fromOffset(186, 186), BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.78, Parent = c,
		}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) }) -- round: the glow behind the art
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, -8, 0, 214), Size = UDim2.new(1, -34, 0, 62), Rotation = -14,
			BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = c,
		}, {
			new("UICorner", { CornerRadius = UDim.new(1, 0) }), -- round: the trail ribbon (art)
			new("UIGradient", {
				Color = if t.rainbow then Config.trailColors(t) else ColorSequence.new(t.color:Lerp(WHITE, 0.6), t.color:Lerp(Color3.new(0, 0, 0), 0.3)),
				Transparency = NumberSequence.new(0.9, 0),
			}),
		})
		local art = Icons.image("TrailShop")
		if art then
			new("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 22, 0, 192), Size = UDim2.fromOffset(170, 170), BackgroundTransparency = 1,
				Image = art, ScaleType = Enum.ScaleType.Fit, ImageColor3 = if t.rainbow then WHITE else t.color:Lerp(WHITE, 0.45), Parent = c,
			})
		else
			text(c, { Text = "🏃", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 22, 0, 192), Size = UDim2.fromOffset(130, 130) })
		end

		-- "x2 Speed" pill, the number in bright green
		local pill = new("Frame", {
			Position = UDim2.new(0, 12, 1, -126), Size = UDim2.new(1, -24, 0, 50), BackgroundColor3 = Color3.fromRGB(20, 24, 34), BackgroundTransparency = 0.3, Parent = c,
		}, { new("UIStroke", { Thickness = 3, Color = FRAME_INK, Transparency = 0.4 }) })
		bold(pill, 3, { RichText = true, Text = `<font color="{NUMBER_GREEN}">x{t.mult}</font> Speed`, Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4) })

		local y = TRAIL_H - 66
		if owned then
			chunky(c, if equipped then "Equipped" else "Equip", if equipped then COLORS.disabled else COLORS.buy, UDim2.fromOffset(TRAIL_W - 24, 54), function()
				if not equipped then
					RequestUseItem:FireServer("Equip:" .. t.id)
				end
			end).Position = UDim2.fromOffset(12, y)
			return c
		end
		local product = t.product and Config.DEVELOPER_PRODUCTS[t.product]
		local moneyW = if product then 126 else TRAIL_W - 24
		local moneyButton = chunky(c, Format.money(t.price), COLORS.buy, UDim2.fromOffset(moneyW, 54), function()
			RequestBuy:FireServer("Trail:" .. t.id)
		end)
		moneyButton.Position = UDim2.fromOffset(12, y)
		watchMoney(function()
			moneyButton.BackgroundColor3 = if stats.money >= t.price then COLORS.buy else COLORS.disabled
		end)
		if product then
			chunky(c, Format.robux(robuxPrice(product)), robuxColor(product.id, ROBUX_GREEN), UDim2.fromOffset(TRAIL_W - 24 - moneyW - 8, 54), function()
				RequestBuy:FireServer("Product:" .. (t.product :: string))
			end, { "Robux" }, ICON.small).Position = UDim2.fromOffset(12 + moneyW + 8, y)
		end
		return c
	end

	function renderTrails()
		clearModal(TRAIL_GAP, true)
		modalSubtitle.TextColor3 = WHITE
		watchMoney(function() -- the Speed one step pays right now (it grows with your Speed and trail)
			Icons.set(modalSubtitle, "Speed", `⚡ {perStepText()}/step`, ICON.big, 26)
		end)
		for i, t in Config.TRAILS do
			table.insert(trailCards, trailCard(modalBody, i, t))
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Index: one row per zone in the zone's colour (its name, the mutations found there), then a column per
-- rarity listing that rarity's flowers: lit with the flower's name once you've grown it, "???" until then.
-- The flowers come from the server (stats.catalog[zone][rarity], the plant models' names); a zone or
-- rarity without plant models shows one cell for the rarity itself.
-- Each cell shows its flower in 3D over its name (Shared/FlowerView): turning slowly once found, a black
-- silhouette over "???" until then (the shape may show, the name and colours are the surprise).
----------------------------------------------------------------------------------------------------
local function renderIndex()
	local FlowerView = require(Shared:WaitForChild("FlowerView"))
	local catalog = stats.catalog or {}
	-- Each cell: { key = the Index key that lights it, name = what it says once lit, model = its flower model }
	local function cellsOf(k: number, r: number): { { key: string, name: string, model: string? } }
		local out = {}
		for _, model in (catalog[k] and catalog[k][r]) or {} do
			table.insert(out, { key = `{k}:{r}:{model}`, name = Format.plantName(model), model = model })
		end
		if #out == 0 then
			table.insert(out, { key = `{k}:{r}`, name = Config.RARITIES[r].id, model = nil })
		end
		return out
	end
	local total, found = 0, 0
	for k = 1, #Config.ZONES do
		for r = 1, #Config.RARITIES do
			for _, c in cellsOf(k, r) do
				total += 1
				found += if stats.index[c.key] then 1 else 0
			end
		end
	end
	modalSubtitle.TextColor3 = WHITE
	Icons.set(modalSubtitle, "Star", `✨ {found}/{total} discovered`, ICON.big, 30)
	clearModal(10)
	local rarities = #Config.RARITIES
	local CELL_H, CELL_GAP, NAME_H = 104, 5, 24
	for k, zone in Config.ZONES do
		local tallest = 1
		for r = 1, rarities do
			tallest = math.max(tallest, #cellsOf(k, r))
		end
		local row = new("Frame", { Size = UDim2.new(1, -12, 0, 76 + tallest * (CELL_H + CELL_GAP)), LayoutOrder = k, Parent = modalBody }, {
			new("UIStroke", { Thickness = 4, Color = FRAME_INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		})
		shade(row, zone.ui, 0.25, 0.3)
		ShopUi.studs(row, zone.ui)
		shine(row)
		-- The zone's name, then the mutations found there in their colours
		local title = zone.name
		for _, m in Config.MUTATIONS do
			if stats.index[`{k}:{m.id}`] then
				title ..= `  <font color="#{m.color:ToHex()}">{m.id}</font>`
			end
		end
		bold(row, 3, { Text = title, RichText = true, Size = UDim2.new(1, -20, 0, 32), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left })
		local columns = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 42), Size = UDim2.new(1, -24, 1, -50), Parent = row },
			{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
		for r, rarity in Config.RARITIES do
			local column = new("Frame", {
				BackgroundTransparency = 1, Size = UDim2.new(1 / rarities, -8 * (rarities - 1) / rarities, 1, 0), LayoutOrder = r, Parent = columns,
			}, { new("UIListLayout", { Padding = UDim.new(0, CELL_GAP), SortOrder = Enum.SortOrder.LayoutOrder }) })
			bold(column, 2, { Text = rarity.id, Size = UDim2.new(1, 0, 0, 20), TextColor3 = rarity.color:Lerp(WHITE, 0.35), LayoutOrder = 0 })
			for i, c in cellsOf(k, r) do
				local got = stats.index[c.key] == true
				local cell = new("Frame", {
					Size = UDim2.new(1, 0, 0, CELL_H), BackgroundColor3 = zone.ui:Lerp(WHITE, 0.5), LayoutOrder = i, Parent = column,
				}, { outline(2) })
				if got then
					shade(cell, rarity.color, 0.3, 0.2)
				end
				ShopUi.studs(cell, if got then rarity.color else zone.ui)
				FlowerView.show(cell, FlowerView.flower(k, r, c.model), {
					size = UDim2.new(1, -8, 1, -(NAME_H + 8)), position = UDim2.fromOffset(4, 4), spin = got, silhouette = not got,
				})
				bold(cell, 2, {
					Text = if got then c.name else "???", Size = UDim2.new(1, -8, 0, NAME_H), Position = UDim2.new(0, 4, 1, -(NAME_H + 4)),
					TextColor3 = WHITE, TextTransparency = if got then 0 else 0.15,
				})
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- SELL window (TODO 9; the SELL stall in the shop plaza opens it). Everything for it is in this block;
-- renderModal and refresh call renderSell / sellChanged. One card per plant, planted or in the Inventory,
-- cheapest first: the plant's name in its rarity colour, its mutation (only on a mutated plant), weight, $/s
-- (with the day/night bonus while it's on; "In your Inventory" for one there), the sell price and a Sell
-- button. Above them "Sell all Common" / "Sell all below Rare" (they keep mutated plants). Every sale asks
-- once more inside the window: the card's button turns into "Sure?", a quick sell shows a confirm bar.
-- The server re-checks it all (remote SellPlants: your plants and inventory, standing at the stall).
-- Scoped in a do-block (the HUD's main chunk is near Luau's 200-locals limit); only these two leave it.
----------------------------------------------------------------------------------------------------
local renderSell: () -> ()
local sellChanged: (changed: { [string]: any }) -> ()
do
	local FlowerView = require(Shared:WaitForChild("FlowerView"))
	local SellPlants = remotes:WaitForChild("SellPlants") :: RemoteEvent
	WINDOWS.Sell = { title = "Sell", bar = Color3.fromRGB(255, 95, 40) }
	local SELL_RED = Color3.fromRGB(235, 60, 50)
	local SELL_ORANGE = Color3.fromRGB(255, 140, 30)
	local SELL_CARD = Color3.fromRGB(85, 125, 235) -- the cards' body under the rarity band
	local SELL_VIEW = 92 -- the flower in 3D, under the band (Shared/FlowerView)
	local SELL_CARD_W, SELL_CARD_H = 190, 252 + SELL_VIEW

	local function rarityIndex(id: string): number
		for i, r in Config.RARITIES do
			if r.id == id then
				return i
			end
		end
		return 0
	end
	-- The quick sells: every plant up to rarity `max` that has no mutation.
	local SELL_GROUPS = {
		{ label = "Sell all Common", what = "Common", max = rarityIndex("Common") },
		{ label = "Sell all below Rare", what = "below Rare", max = rarityIndex("Rare") - 1 },
	}

	type SellPending = { key: string?, group: number? }
	local sellPending: SellPending? = nil -- the sale waiting for its confirm: one plant's key, or a quick sell
	local sellUpdaters: { () -> () } = {} -- the open window's prices and $/s, updated in place on payouts
	local sellShown = "" -- which plants the window shows (sellSignature)

	-- Every plant the stall can sell: the planted ones ("p<slot>") and those in the Inventory ("i<id>").
	local function sellables(): { any }
		local out = {}
		for _, p in stats.plants or {} do
			local item = table.clone(p)
			item.key = `p{p.slot}`
			table.insert(out, item)
		end
		for _, p in stats.inventory or {} do
			local item = table.clone(p)
			item.key, item.inv = `i{p.id}`, true
			table.insert(out, item)
		end
		return out
	end

	-- Which plants there are (key and kind), so a payout tick (same plants, new numbers) doesn't rebuild the
	-- window under the player's finger, but a sale or a new plant does.
	local function sellSignature(): string
		local keys = {}
		for _, p in sellables() do
			table.insert(keys, `{p.key}:{p.zone}:{p.rarity}:{p.mutation or ""}:{p.flower or ""}`)
		end
		table.sort(keys)
		return table.concat(keys, ",")
	end

	local function itemOf(key: string): any
		for _, p in sellables() do
			if p.key == key then
				return p
			end
		end
		return nil
	end

	-- The slots and inventory ids a sale would sell and what it pays right now.
	local function saleOf(pending: SellPending): ({ number }, { number }, number)
		local slots, ids, total = {}, {}, 0
		local group = pending.group and SELL_GROUPS[pending.group]
		for _, p in sellables() do
			if (pending.key ~= nil and p.key == pending.key) or (group ~= nil and p.mutation == nil and p.rarity <= group.max) then
				table.insert(if p.inv then ids else slots, if p.inv then p.id else p.slot)
				total += p.sell or 0
			end
		end
		return slots, ids, total
	end

	local function saleCount(pending: SellPending): number
		local slots, ids = saleOf(pending)
		return #slots + #ids
	end

	local function sellNow(pending: SellPending)
		local slots, ids = saleOf(pending)
		sellPending = nil
		if #slots + #ids > 0 then
			SellPlants:FireServer(slots, ids)
		end
		renderModal()
	end

	-- "$1.2K/s · Night x0.8" in a muted grey while the plant is out of its phase (earning less), like its billboard.
	local function sellIncomeText(p: any): (string, Color3)
		if p.inv then
			return "In your Inventory", NOTE_COLOR
		end
		local bonus = Config.bonusLabel(p.zone, (Config.dayPhase(workspace:GetServerTimeNow())))
		return `{Format.money(p.income)}/s{if bonus then " · " .. bonus else ""}`, if bonus then Config.OFF_TIME_COLOR else MONEY_GREEN
	end

	local function sellCard(grid: Instance, order: number, p: any)
		local rarity = Config.RARITIES[p.rarity]
		local mut = Config.mutationById(p.mutation)
		local c = new("Frame", { BackgroundColor3 = SELL_CARD, LayoutOrder = order, Parent = grid }, {
			new("UIStroke", { Thickness = 4, Color = if mut then mut.color else FRAME_INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		})
		ShopUi.studs(c, SELL_CARD)
		-- The rarity band: the plant's name and rarity
		local band = new("Frame", { Size = UDim2.new(1, 0, 0, 70), BorderSizePixel = 0, Parent = c })
		shade(band, rarity.color, 0.25, 0.25)
		ShopUi.studs(band, rarity.color)
		shine(band)
		bold(band, 3, { Text = p.name or SeedPacks.seedName(p.zone, p.rarity, p.mutation), Size = UDim2.new(1, -14, 0, 32), Position = UDim2.fromOffset(7, 6) })
		bold(band, 3, { Text = rarity.id, Size = UDim2.new(1, -14, 0, 24), Position = UDim2.fromOffset(7, 40) })
		-- The plant itself, turning slowly
		FlowerView.show(c, FlowerView.flower(p.zone, p.rarity, p.flower), {
			size = UDim2.new(1, -16, 0, SELL_VIEW), position = UDim2.fromOffset(8, 74), spin = true,
		})
		-- Mutation (a plant without one shows nothing there), weight, $/s
		local y = SELL_VIEW
		if mut then
			bold(c, 2, { Text = mut.id, Size = UDim2.new(1, -14, 0, 24), Position = UDim2.fromOffset(7, 78 + y), TextColor3 = mut.color })
		end
		local weightLabel = text(c, { Visible = false, Text = "", Size = UDim2.new(1, -14, 0, 22), Position = UDim2.fromOffset(7, 106 + y) })
		local incomeLabel = bold(c, 2, { Size = UDim2.new(1, -14, 0, 22), Position = UDim2.fromOffset(7, 132 + y) })
		-- What the stall pays, and the button (a second click confirms)
		local priceLabel = bold(c, 3, { Size = UDim2.new(1, -14, 0, 34), Position = UDim2.fromOffset(7, 158 + y), TextColor3 = MONEY_GREEN })
		local sure = sellPending ~= nil and sellPending.key == p.key
		chunky(c, if sure then "Sure? Sell" else "Sell", if sure then COLORS.gold else SELL_RED, UDim2.new(1, -16, 0, 48), function()
			if sure then
				sellNow({ key = p.key })
			else
				sellPending = { key = p.key }
				renderModal()
			end
		end).Position = UDim2.new(0, 8, 1, -56)
		local function update()
			local now = itemOf(p.key) or p
			incomeLabel.Text, incomeLabel.TextColor3 = sellIncomeText(now)
			priceLabel.Text = Format.money(now.sell or 0)
		end
		update()
		table.insert(sellUpdaters, update)
	end

	renderSell = function()
		clearModal(10)
		table.clear(sellUpdaters)
		sellShown = sellSignature()
		local plants = sellables()
		table.sort(plants, function(a, b)
			if (a.sell or 0) ~= (b.sell or 0) then
				return (a.sell or 0) < (b.sell or 0)
			end
			return a.key < b.key
		end)
		note(`The stall pays {Config.SELL_STALL_SECONDS // 60} min of a plant's income. Plants in your Inventory sell here too.`, 1)
		if #plants == 0 then
			note("No plants yet: steal a seed and plant it on your dirt!", 2)
			return
		end

		-- Quick sells (they keep mutated plants)
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -12, 0, 60), LayoutOrder = 2, Parent = modalBody }, {
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 14) }),
		})
		for i, group in SELL_GROUPS do
			local count = saleCount({ group = i })
			chunky(row, `{group.label} ({count})`, if count > 0 then SELL_ORANGE else COLORS.disabled, UDim2.fromOffset(330, 56), function()
				if count > 0 then
					sellPending = { group = i }
					renderModal()
				end
			end)
		end
		note("Quick sells skip mutated plants.", 3)

		-- The quick sell's confirm bar
		local pending = sellPending
		local group = pending and pending.group and SELL_GROUPS[pending.group]
		if pending and group and saleCount(pending) == 0 then
			sellPending, pending, group = nil, nil, nil -- nothing left to sell
		end
		if pending and group then
			local bar = new("Frame", { Size = UDim2.new(1, -12, 0, 72), BackgroundColor3 = FRAME_INK, BackgroundTransparency = 0.15, LayoutOrder = 4, Parent = modalBody }, { outline(3) })
			local question = bold(bar, 3, {
				Size = UDim2.new(1, -350, 1, -18), Position = UDim2.fromOffset(16, 9), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = HEADING_GOLD,
			})
			local function update()
				local _, _, total = saleOf(pending :: SellPending)
				local count = saleCount(pending :: SellPending)
				question.Text = `Sell {count} {group.what} plant{if count == 1 then "" else "s"} for {Format.money(total)}?`
			end
			update()
			table.insert(sellUpdaters, update)
			chunky(bar, "Yes, sell!", COLORS.buy, UDim2.fromOffset(170, 56), function()
				sellNow(pending :: SellPending)
			end).Position = UDim2.new(1, -330, 0, 8)
			chunky(bar, "Cancel", COLORS.disabled, UDim2.fromOffset(140, 56), function()
				sellPending = nil
				renderModal()
			end).Position = UDim2.new(1, -150, 0, 8)
		end

		local grid = new("Frame", {
			BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5, Parent = modalBody,
		}, {
			new("UIGridLayout", {
				CellSize = UDim2.fromOffset(SELL_CARD_W, SELL_CARD_H), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			}),
		})
		for i, p in plants do
			sellCard(grid, i, p)
		end
	end

	-- The plants view arrives with every payout: rebuild only when the plants themselves changed.
	sellChanged = function(changed: { [string]: any })
		if changed.plants or changed.inventory then

			if sellSignature() ~= sellShown then
				renderModal()
			else
				for _, update in sellUpdaters do
					update()
				end
			end
		end
		if changed.money or changed.income then
			for _, update in moneyWatchers do
				update()
			end
		end
	end

	-- The SELL stall's prompt (the plaza's other stalls are handled above). Opens fresh, never toggles shut.
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt:GetAttribute("OpensShop") == "Sell" and modalName ~= "Sell" then
			sellPending = nil
			openModal("Sell")
		end
	end)

	-- The 3D pictures replicate a moment after the server starts: a window or panel opened before then is
	-- drawn again once they are here (FlowerView: an empty frame until then).
	ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
		if child.Name == FlowerView.FOLDER or child.Name == FlowerView.SEEDS then
			renderSide()
			if modal.Visible and (modalName == "Index" or modalName == "Sell" or modalName == "Shop") then
				renderModal()
			end
		end
	end)
end
------------------------------------------------------------------------------------------ end of SELL

-- Rebuilds the open window. The scroll position is kept (a purchase rebuilds it), except when the
-- Shop was asked to jump to a section.
renderModal = function()
	local keep = modalBody.CanvasPosition
	table.clear(packShines) -- renderShop adds the current pack cards' shines back
	table.clear(moneyWatchers)
	table.clear(trailCards)
	local focused = false
	if modalName == "Shop" then
		focused = renderShop()
	elseif modalName == "Trails" then
		renderTrails()
	elseif modalName == "Index" then
		renderIndex()
	elseif modalName == "Sell" then
		renderSell()
	end
	if not focused then
		modalBody.CanvasPosition = keep
		-- again once the layout has sized the new canvas (it can take a frame or two; until then Roblox clamps
		-- the scroll up to the still-short canvas): only ever back down to where it was, never past it
		local shownAs = modalName
		task.spawn(function()
			for _ = 1, 4 do
				task.wait()
				if not modal.Visible or modalName ~= shownAs then
					return
				end
				if modalBody.CanvasPosition.Y < keep.Y then
					modalBody.CanvasPosition = keep
				end
			end
		end)
	end
	task.defer(updateTrailArrows)
end

----------------------------------------------------------------------------------------------------
-- Pack reveal (owner playtest 2026-10-15: it used to play on top of the open Shop): the Shop closes while
-- it plays and opens again where it was afterwards; a dark backdrop covers the screen and everything sits
-- in one framed panel (its own UIScale, so it fits a phone): the title, a reel of seed cards (rarity on one
-- line, a mutation on its own line under it, text scaled inside padding so it always fits) under a gold
-- window with pointers marking the centre, then the result: the seed in 3D (its seed look, Shared/
-- FlowerView), its rarity in big relief, where it went, and "Click to continue" at the bottom. The rays
-- stay inside the panel. The result was decided (and bagged) on the server before this plays.
----------------------------------------------------------------------------------------------------
local queueReveal: (data: any) -> ()
do
	local FlowerView = require(Shared:WaitForChild("FlowerView"))
	local PANEL_W, PANEL_H = 780, 548
	local CARD_W, CARD_H, CARD_GAP = 132, 168, 12
	local REEL_X, REEL_Y, REEL_W, REEL_H = 40, 84, 700, 196
	local REEL_COUNT, REEL_TARGET = 44, 38
	local RESULT_Y = REEL_Y + REEL_H + 24
	local VIEW = 176 -- the seed in 3D

	local tickSound = new("Sound", { SoundId = Config.SOUNDS.Click, Volume = 0.35, Parent = SoundService })
	local landSound = new("Sound", { SoundId = Config.SOUNDS.Pickup, Volume = 0.8, Parent = SoundService })

	-- The backdrop: the whole screen, dark, above every window (the Shop is closed anyway)
	local revealGui = new("Frame", {
		Name = "Reveal", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 8, 16), BackgroundTransparency = 0.2,
		Visible = false, Active = true, ZIndex = 20, Parent = gui,
	})
	local panel = new("Frame", {
		Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(PANEL_W, PANEL_H),
		BackgroundColor3 = WHITE, ClipsDescendants = true, Parent = revealGui,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 4) }),
		new("UIStroke", { Thickness = 6, Color = COLORS.gold, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(75, 40, 140), Color3.fromRGB(22, 16, 46)) }),
	})
	ShopUi.studs(panel, Color3.fromRGB(75, 40, 140), nil, 1)
	local panelScale = new("UIScale", { Parent = panel })
	local burst = new("Frame", { -- the rays and confetti, behind the reel, clipped by the panel
		Name = "Burst", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(PANEL_W / 2, REEL_Y + REEL_H / 2), Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1, ZIndex = 1, Parent = panel,
	})
	local revealTitle = bold(panel, 4, {
		Name = "Title", Text = "", Size = UDim2.new(1, -40, 0, 50), Position = UDim2.fromOffset(20, 18), TextColor3 = Color3.fromRGB(255, 225, 70), ZIndex = 5,
	})
	UiFx.relief(revealTitle, 4, 4)
	local reel = new("Frame", {
		Name = "Reel", Position = UDim2.fromOffset(REEL_X, REEL_Y), Size = UDim2.fromOffset(REEL_W, REEL_H),
		BackgroundColor3 = Color3.fromRGB(16, 14, 30), ClipsDescendants = true, ZIndex = 3, Parent = panel,
	}, deco(14, 4))
	local strip = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(REEL_COUNT * (CARD_W + CARD_GAP), CARD_H), ZIndex = 3, Parent = reel })
	-- The centre: a gold window over the winning slot and a pointer above and below the reel
	new("Frame", {
		Name = "Marker", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(CARD_W + 10, CARD_H + 14),
		BackgroundTransparency = 1, ZIndex = 6, Parent = reel,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 14) }),
		new("UIStroke", { Thickness = 4, Color = COLORS.gold, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	for _, y in { REEL_Y - 4, REEL_Y + REEL_H + 4 } do
		new("Frame", {
			Name = "Pointer", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(REEL_X + REEL_W / 2, y), Size = UDim2.fromOffset(26, 26), Rotation = 45,
			BackgroundColor3 = COLORS.gold, ZIndex = 7, Parent = panel,
		}, { new("UIStroke", { Thickness = 3, Color = INK }) })
	end
	-- The result: the seed in 3D on a glow, its rarity, where it went
	local viewHolder = new("Frame", {
		Name = "Result", Position = UDim2.fromOffset(REEL_X + 20, RESULT_Y), Size = UDim2.fromOffset(VIEW, VIEW), BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.82, ZIndex = 4, Visible = false, Parent = panel,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	local textX = REEL_X + 20 + VIEW + 24
	local resultLabel = bold(panel, 5, {
		Name = "ResultTitle", Text = "", Size = UDim2.new(1, -(textX + 40), 0, 70), Position = UDim2.fromOffset(textX, RESULT_Y + 20),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5,
	})
	UiFx.relief(resultLabel, 4, 5)
	local resultSub = bold(panel, 3, {
		Name = "ResultSub", Text = "", Size = UDim2.new(1, -(textX + 40), 0, 54), Position = UDim2.fromOffset(textX, RESULT_Y + 98),
		TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, ZIndex = 5,
	})
	local continueHint = bold(panel, 3, {
		Name = "Continue", Text = "Click to continue", Size = UDim2.new(1, -40, 0, 30), Position = UDim2.new(0, 20, 1, -42),
		TextColor3 = Color3.fromRGB(220, 220, 235), ZIndex = 5,
	})
	local closeButton = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 30, Visible = false, Parent = revealGui })
	closeButton:SetAttribute("NoPop", true) -- the whole screen: "Click to continue"

	local function fitPanel()
		local s = uiScale.Scale
		local w, h = gui.AbsoluteSize.X / s, gui.AbsoluteSize.Y / s
		panelScale.Scale = math.clamp(math.min((w - 24) / (PANEL_W + 12), (h - 24) / (PANEL_H + 12)), 0.3, 1)
	end

	-- A reel card: a seed icon, the rarity on its own line, the mutation (if any) on a pill under it. All
	-- text is scaled inside the card's padding, so "Uncommon" or "Celestial" always fits.
	local function seedCard(parent: Instance, rarity: number, mutation: string?): Frame
		local r = Config.RARITIES[rarity]
		local mut = Config.mutationById(mutation)
		local f = new("Frame", { Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundColor3 = WHITE, ZIndex = 3, Parent = parent }, deco(12, 3))
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(r.color:Lerp(WHITE, 0.25), r.color:Lerp(Color3.new(0, 0, 0), 0.35)), Parent = f })
		ShopUi.studs(f, r.color, nil, 3)
		local inner = new("Frame", { Name = "Inner", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = f }, {
			new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10) }),
		})
		bigIcon(inner, "Seeds", { Size = UDim2.fromScale(0.5, 0.32), AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0), ZIndex = 3 })
		local name = bold(inner, 3, { Name = "Rarity", Text = r.id, Size = UDim2.fromScale(1, 0.24), Position = UDim2.fromScale(0, 0.38), ZIndex = 4 })
		new("UITextSizeConstraint", { MaxTextSize = 30, Parent = name })
		if mut then
			local pill = new("Frame", {
				Name = "Mutation", Size = UDim2.fromScale(1, 0.26), Position = UDim2.fromScale(0, 0.72), BackgroundColor3 = FRAME_INK, BackgroundTransparency = 0.25,
				ZIndex = 4, Parent = inner,
			}, { new("UICorner", { CornerRadius = UDim.new(0, 8) }) })
			local label = bold(pill, 2, { Text = mut.id, Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 3), TextColor3 = mut.color, ZIndex = 5 })
			new("UITextSizeConstraint", { MaxTextSize = 24, Parent = label })
		end
		return f
	end

	local function burstAt(color: Color3, big: boolean)
		burst:ClearAllChildren()
		for i = 1, 6 do -- rotating rays
			local ray = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(if big then 34 else 22, 900), Rotation = i * 30,
				BackgroundColor3 = color, BackgroundTransparency = 0.55, BorderSizePixel = 0, Parent = burst,
			})
			TweenService:Create(ray, TweenInfo.new(3.5, Enum.EasingStyle.Linear), { Rotation = i * 30 + 75, BackgroundTransparency = 1 }):Play()
		end
		local flash = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = color, BackgroundTransparency = 0.2, Parent = burst,
		}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		TweenService:Create(flash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(700, 700), BackgroundTransparency = 1 }):Play()
		for i = 1, if big then 30 else 16 do -- confetti
			local a = math.random() * math.pi * 2
			local d = 170 + math.random() * 220
			local bit = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(10, 16), Rotation = math.random() * 360, BorderSizePixel = 0,
				BackgroundColor3 = if i % 3 == 0 then COLORS.gold elseif i % 3 == 1 then color else WHITE, Parent = burst,
			})
			TweenService:Create(bit, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(math.cos(a) * d, math.sin(a) * d), Rotation = bit.Rotation + 360, BackgroundTransparency = 1,
			}):Play()
		end
	end

	local function playReveal(data: any, fast: boolean)
		local pack = SeedPacks.lookup(tostring(data.packId))
		local best = data.result
		if not pack or type(best) ~= "table" or not Config.RARITIES[best.rarity] or not Config.ZONES[best.zone] then
			return
		end

		revealTitle.Text = `Opening {data.name}...`
		resultLabel.Visible, resultSub.Visible, continueHint.Visible, closeButton.Visible, viewHolder.Visible = false, false, false, false, false
		burst:ClearAllChildren()
		strip:ClearAllChildren()
		viewHolder:ClearAllChildren()
		new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = viewHolder })

		-- Filler cards come from the same odds, luck-boosted so the reel teases rare seeds.
		local tease = table.clone(pack)
		tease.luck *= 3
		tease.mutationMult *= 3
		tease.exclusiveChance *= 4
		local function rng(): number
			return math.random()
		end
		local step = CARD_W + CARD_GAP
		for i = 1, REEL_COUNT do
			local rarity, mutation = best.rarity, best.mutation
			if i ~= REEL_TARGET then
				rarity, mutation = SeedPacks.roll(tease, rng)
			end
			local card = seedCard(strip, rarity, mutation)
			card.Name = "Card" .. i
			card.Position = UDim2.fromOffset((i - 1) * step, 0)
		end
		local y = (REEL_H - CARD_H) / 2
		strip.Position = UDim2.fromOffset(0, y)
		fitPanel()
		revealGui.Visible = true

		local finalX = REEL_W / 2 - ((REEL_TARGET - 1) * step + CARD_W / 2) + (math.random() - 0.5) * CARD_W * 0.6
		local tween = TweenService:Create(strip, TweenInfo.new(if fast then 1.3 else 3.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(finalX, y),
		})
		local lastIndex = -1
		local lastTick = 0
		local ticker = RunService.RenderStepped:Connect(function()
			local index = math.floor((REEL_W / 2 - strip.Position.X.Offset) / step)
			if index ~= lastIndex and os.clock() - lastTick > 0.035 then
				lastIndex = index
				lastTick = os.clock()
				tickSound:Play()
			end
		end)
		tween:Play()
		tween.Completed:Wait()
		ticker:Disconnect()
		-- settle the winner exactly under the marker
		TweenService:Create(strip, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(REEL_W / 2 - ((REEL_TARGET - 1) * step + CARD_W / 2), y),
		}):Play()

		-- Land: light the winning card, burst in its colour, show the seed and name it
		local rarity = Config.RARITIES[best.rarity]
		local mut = Config.mutationById(best.mutation)
		local color = if mut then mut.color else rarity.color
		local card = strip:FindFirstChild("Card" .. REEL_TARGET)
		local cardStroke = card and card:FindFirstChildOfClass("UIStroke")
		if cardStroke then
			cardStroke.Color, cardStroke.Thickness = COLORS.gold, 5
		end
		burstAt(color, best.rarity >= 4 or mut ~= nil)
		landSound:Play()
		viewHolder.BackgroundColor3 = color
		viewHolder.Visible = true
		FlowerView.show(viewHolder, FlowerView.seed(best.zone, tonumber(best.gene)), { zindex = 5, spin = true, zoom = 1.3 })
		resultLabel.Text = `{if mut then string.upper(mut.id) .. " " else ""}{string.upper(rarity.id)}!`
		resultLabel.TextColor3 = color
		resultLabel.Visible = true
		local exclusive = best.mutation ~= nil and best.mutation == pack.exclusive
		resultSub.Text = `{if exclusive then "PACK EXCLUSIVE! " else ""}{SeedPacks.seedName(best.zone, best.rarity, best.mutation)} → your Inventory`
		resultSub.Visible = true

		continueHint.Visible = true
		closeButton.Visible = true
		local closed = false
		local conn = closeButton.Activated:Connect(function()
			closed = true
		end)
		local deadline = os.clock() + (if fast then 1.6 else 5)
		while not closed and os.clock() < deadline do
			task.wait(0.05)
		end
		conn:Disconnect()
	end

	local revealQueue: { any } = {}
	local revealRunning = false
	function queueReveal(data: any)
		if #revealQueue >= 6 then
			table.remove(revealQueue, 1)
		end
		table.insert(revealQueue, data)
		if revealRunning then
			return
		end
		revealRunning = true
		-- The Shop (or any window) closes while the reveal plays and opens again where it was afterwards.
		local reopen: string? = if modal.Visible then modalName else nil
		local scroll = modalBody.CanvasPosition
		if reopen then
			closeModal()
		end
		task.spawn(function()
			while #revealQueue > 0 do
				local nextData = table.remove(revealQueue, 1)
				local ok, err = pcall(playReveal, nextData, #revealQueue > 0)
				if not ok then
					warn("[HUD] pack reveal failed:", err)
				end
			end
			revealGui.Visible = false
			closeButton.Visible = false
			revealRunning = false
			if reopen and not modal.Visible then
				openModal(reopen)
				task.spawn(function() -- once the layout has sized the canvas again
					for _ = 1, 3 do
						task.wait()
						if modalName == reopen then
							modalBody.CanvasPosition = scroll
						end
					end
				end)
			end
		end)
	end
end

----------------------------------------------------------------------------------------------------
-- Refresh from stats
----------------------------------------------------------------------------------------------------
local function refresh(changed: { [string]: any })
	speedValue.Text = Format.short(stats.speed)
	moneyValue.Text = Format.money(stats.money)

	-- (No banner while carrying a seed: the seed in hand and the planting ghost, Planting.client, say it.)
	if not slowMode and changed.walkSpeed then
		applySlow()
	end
	-- Rebuilding lists every money tick is wasteful; only when their data changed.
	if sidePanel.Visible and (changed.plants or changed.slots or changed.income or changed.inventory or changed.seedBag or changed.carrying) then
		renderPlants() -- rebuilt only when what it lists changed (a payout just updates the numbers)
	end

	-- The open window is rebuilt when what it lists changes; money, income and Speed only update it in place.
	if modal.Visible and modalName == "Sell" then
		sellChanged(changed)
	elseif modal.Visible and (changed.index or changed.items or changed.slots or changed.plotLevel or changed.trails or changed.equippedTrail
		or changed.treadmillTier or changed.passes or changed.seedBag or changed.catalog) then
		renderModal()
	elseif modal.Visible and (changed.money or changed.income or changed.speed) then
		for _, update in moneyWatchers do
			update()
		end
	end
end

do
	-- Only what really changed (Shared/StatsDiff): the server re-sends unchanged values (the plants push's
	-- `slots` every few seconds), which used to rebuild the open Shop and throw its scroll back up.
	local StatsDiff = require(Shared:WaitForChild("StatsDiff"))
	StatsUpdate.OnClientEvent:Connect(function(partial: { [string]: any })
		refresh(StatsDiff.apply(stats, partial))
	end)
end

----------------------------------------------------------------------------------------------------
-- Loot events -> toasts. Only what the player needs told: the server's messages (mostly why something
-- was refused), getting caught, offline earnings and day/night. Stealing, planting, selling, buying, the
-- bat and the guards waking are seen in the world and heard (Effects.client), not toasted.
----------------------------------------------------------------------------------------------------
LootEvent.OnClientEvent:Connect(function(kind: string, data: any)
	data = data or {}
	if kind == "Toast" then
		toast(data.text, data.color, nil, data.icon)
	elseif kind == "Caught" then
		toast(`The {data.guard} caught you! The seed went back to its nest.`, "red", 4)
	elseif kind == "Bat" then
		batCooldownUntil = os.clock() + (data.cooldown or Config.BAT_COOLDOWN)
	elseif kind == "Offline" then
		toast(`While you were away ({Format.clock(data.seconds)}): +{Format.money(data.amount)}`, "gold", 6, "Money")
	elseif kind == "PackRoll" then
		queueReveal(data)
	elseif kind == "DayNight" then
		toast(if data.night then "Night falls: rarer seeds and Night mutations!" else "The sun is up.", if data.night then "purple" else "blue", 4,
			if data.night then "Moon" else "Sun")
	end
end)

-- Server-wide announcements (Net.announce), e.g. "Alex got a LEGENDARY Starpetal!"
LootEvent.OnClientEvent:Connect(function(kind: string, data: any)
	if kind == "Announce" and data then
		toast(data.text, data.color, 6, "Star", true)
	end
end)

----------------------------------------------------------------------------------------------------
-- Per-frame bits: bat cooldown, pack shines (the zone you enter is announced by ZoneBanner.client, the
-- day/night timer is DayTimer.client, top right)
----------------------------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	local left = batCooldownUntil - os.clock()
	batShade.Size = UDim2.fromScale(1, math.clamp(left / Config.BAT_COOLDOWN, 0, 1))

	-- Premium pack cards: a shine sweeping across each, staggered
	if modal.Visible then
		for i, shine in packShines do
			if shine.Parent then
				shine.Position = UDim2.fromScale((os.clock() * 0.4 + i * 0.55) % 1.6 - 0.3, 0)
			end
		end
	end

end)

rescale()
gui.Parent = player:WaitForChild("PlayerGui")
local function fitScreen()
	fitLeftColumn()
	fitModal()
end
fitScreen()
local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		rescale()
		fitScreen()
	end)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitScreen)
