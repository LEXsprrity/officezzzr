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
	treadmillTier = 1, treadmillMult = 2,
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
	robux = Color3.fromRGB(150, 80, 230), -- purple: R$ on trail cards, the gift button
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
	local l = text(b, { Name = "Label", Text = label, Size = UDim2.new(1, -10, 1, -6), Position = UDim2.fromOffset(5, 3) })
	if icon then
		Icons.set(l, icon, label, iconSize or ICON.medium)
	end
	b.Activated:Connect(onClick)
	return b
end

local gui = new("ScreenGui", { Name = "SeedHUD", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
local uiScale = new("UIScale", { Parent = gui })
local function rescale()
	local cam = workspace.CurrentCamera
	local y = if cam then cam.ViewportSize.Y else 900
	uiScale.Scale = math.clamp(y / 900, 0.55, 1.25)
end

----------------------------------------------------------------------------------------------------
-- Toasts (top centre)
----------------------------------------------------------------------------------------------------
local toastHolder = new("Frame", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120),
	Size = UDim2.fromOffset(560, 300), ZIndex = 12, Parent = gui, -- above the shop windows
}, { new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6) }) })

local TOAST_COLORS = { red = COLORS.red, gold = COLORS.gold, green = COLORS.money, blue = COLORS.speed }
local function toast(message: string, color: string?, seconds: number?)
	local frame = new("Frame", {
		Size = UDim2.fromOffset(520, 40), BackgroundColor3 = TOAST_COLORS[color or ""] or Color3.fromRGB(60, 60, 80),
		Parent = toastHolder,
	}, deco(10))
	local label = text(frame, { Text = message, Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4) })
	task.delay(seconds or 3, function()
		local info = TweenInfo.new(0.4)
		TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		task.wait(0.45)
		frame:Destroy()
	end)
	local children = toastHolder:GetChildren()
	if #children > 6 then
		for _, c in children do
			if c:IsA("Frame") then
				c:Destroy()
				break
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Top: zone banner + carry banner
----------------------------------------------------------------------------------------------------
local zoneBanner = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(460, 44),
	BackgroundColor3 = COLORS.money, Visible = false, Parent = gui,
}, deco(12))
local zoneLabel = text(zoneBanner, { Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4) })

local carryBanner = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 58), Size = UDim2.fromOffset(460, 50),
	BackgroundColor3 = COLORS.gold, Visible = false, Parent = gui,
}, deco(12))
local carryLabel = text(carryBanner, { Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), TextColor3 = WHITE })

----------------------------------------------------------------------------------------------------
-- Bottom-left, stacked bottom-up and kept minimal, with no panels behind the numbers:
--   * Speed (with a "+" that opens the Shop's Speed section) in pink, money in green;
--   * the Shop / Index buttons and the Slow Mode switch. (Trails opens from the TRAIL SHOP stall in
--     the plaza, the Free Gift from the gift box by the free chest.)
-- Sizes are design pixels: the screen is 900 tall at UIScale 1, about 680 on a landscape phone (the
-- 0.55 minimum scale). The button column shrinks on its own if it would run into the top of the screen.
----------------------------------------------------------------------------------------------------
local SPEED_PINK = Color3.fromRGB(255, 70, 150)
local MONEY_GREEN = Color3.fromRGB(85, 240, 70)
local STATS_H, LEFT_H = 100, 194 -- LEFT_H: 2 side buttons + Slow Mode
local STATS_BOTTOM = 10
local LEFT_BOTTOM = STATS_BOTTOM + STATS_H + 10

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

-- Speed and money
local statsFrame = new("Frame", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -STATS_BOTTOM),
	Size = UDim2.fromOffset(360, STATS_H), Parent = gui,
})
iconLabel(statsFrame, "Speed", "⚡", { Size = UDim2.fromOffset(48, 48) })
local speedValue = bold(statsFrame, 4, {
	Text = "0", Size = UDim2.new(1, -62, 0, 44), Position = UDim2.fromOffset(62, 2), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = SPEED_PINK,
})
iconLabel(statsFrame, "Money", "💰", { Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(0, 52) })
local moneyValue = bold(statsFrame, 4, {
	Text = "$0", Size = UDim2.new(1, -62, 0, 44), Position = UDim2.fromOffset(62, 54), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = MONEY_GREEN,
})
-- The Speed icon and its yellow "+" badge both open the Shop on the Speed section.
new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromOffset(48, 48), Parent = statsFrame }).Activated:Connect(function()
	openShopAt("Speed")
end)
local plusBadge = new("TextButton", {
	Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(32, 28), BackgroundColor3 = Color3.fromRGB(255, 210, 40), Text = "",
	AutoButtonColor = true, Parent = statsFrame,
}, deco(7, 3))
bold(plusBadge, 3, { Text = "+", Size = UDim2.new(1, -4, 1, -2), Position = UDim2.fromOffset(2, 0) })
plusBadge.Activated:Connect(function()
	openShopAt("Speed")
end)

-- Shop / Index, then the Slow Mode switch, above the Speed and money.
local leftColumn = new("Frame", {
	Name = "LeftColumn", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -LEFT_BOTTOM),
	Size = UDim2.fromOffset(180, LEFT_H), Parent = gui,
}, {
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom }),
})
local leftScale = new("UIScale", { Parent = leftColumn })

local function sideButton(order: number, label: string, icon: string, emoji: string, color: Color3, onClick: () -> ())
	local b = new("TextButton", {
		Name = label, Size = UDim2.fromOffset(92, 74), BackgroundColor3 = color, Text = "", AutoButtonColor = true, LayoutOrder = order, Parent = leftColumn,
	}, deco(14, 4))
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(200, 200, 200)), Parent = b })
	iconLabel(b, icon, emoji, { Size = UDim2.fromOffset(46, 46), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2) })
	bold(b, 3, { Text = label, Size = UDim2.new(1, -6, 0, 26), Position = UDim2.new(0, 3, 1, -28) })
	b.Activated:Connect(onClick)
end

sideButton(1, "Shop", "Shop", "🛒", Color3.fromRGB(70, 210, 70), function()
	openModal("Shop")
end)
sideButton(2, "Index", "Index", "📖", Color3.fromRGB(40, 200, 235), function()
	openModal("Index")
end)

-- Slow Mode: purely local, clamps our own WalkSpeed so we can potter around the base.
local slowMode = false
local slowRow = new("TextButton", { Name = "SlowMode", Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Text = "", LayoutOrder = 3, Parent = leftColumn })
local slowTrack = new("Frame", {
	Size = UDim2.fromOffset(54, 28), Position = UDim2.fromOffset(0, 1), BackgroundColor3 = Color3.fromRGB(80, 80, 92), Parent = slowRow,
}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }), new("UIStroke", { Thickness = 3, Color = INK }) })
local slowKnob = new("Frame", {
	Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(3, 3), BackgroundColor3 = Color3.fromRGB(195, 195, 205), Parent = slowTrack,
}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }), new("UIStroke", { Thickness = 2, Color = INK }) })
bold(slowRow, 3, { Text = "Slow Mode", Size = UDim2.new(1, -62, 0, 24), Position = UDim2.fromOffset(62, 3), TextXAlignment = Enum.TextXAlignment.Left })

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
		BackgroundColor3 = if slowMode then Color3.fromRGB(80, 225, 70) else Color3.fromRGB(195, 195, 205),
	}):Play()
	TweenService:Create(slowTrack, info, { BackgroundColor3 = if slowMode then Color3.fromRGB(40, 110, 45) else Color3.fromRGB(80, 80, 92) }):Play()
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

-- Short screens (phones): shrink the button column so it stays below the top of the screen.
local function fitLeftColumn()
	local height = gui.AbsoluteSize.Y / uiScale.Scale
	leftScale.Scale = math.clamp((height - LEFT_BOTTOM - 8) / LEFT_H, 0.5, 1)
end

----------------------------------------------------------------------------------------------------
-- "LEVEL N!" (centred low, above the hotbar): pops in, holds, fades. Only one at a time: a new level
-- while it shows replaces it (Config.levelUp already picks the highest).
----------------------------------------------------------------------------------------------------
local announceLevel: (level: number) -> ()
do
	local levelUpLabel = bold(gui, 5, {
		Name = "LevelUp", Text = "", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -150), Size = UDim2.fromOffset(420, 76),
		Visible = false, ZIndex = 15,
	})
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 238, 70), Color3.fromRGB(255, 150, 25)), Parent = levelUpLabel })
	local levelUpSub = bold(levelUpLabel, 3, { Text = "", Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 1, 0), ZIndex = 15 })
	local levelUpScale = new("UIScale", { Parent = levelUpLabel })
	local levelUpSound = new("Sound", { SoundId = Config.SOUNDS.LevelUp, Volume = 0.6, Parent = SoundService })
	local levelUpToken = 0
	local levelUpFades: { Tween } = {}

	local function setLevelUpTransparency(t: number, info: TweenInfo?)
		for _, label in { levelUpLabel, levelUpSub } do
			local stroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke
			if info then
				local a = TweenService:Create(label, info, { TextTransparency = t })
				local b = TweenService:Create(stroke, info, { Transparency = t })
				a:Play()
				b:Play()
				table.insert(levelUpFades, a)
				table.insert(levelUpFades, b)
			else
				label.TextTransparency = t
				stroke.Transparency = t
			end
		end
	end

	function announceLevel(level: number)
		levelUpToken += 1
		local token = levelUpToken
		for _, tween in levelUpFades do
			tween:Cancel()
		end
		table.clear(levelUpFades)
		if not levelUpLabel.Visible then
			levelUpSound:Play() -- one ping per pop-up, not per level
		end
		levelUpLabel.Text = `LEVEL {level}!`
		levelUpSub.Text = `x{Config.trailMult(stats.equippedTrail)} Multiplier`
		setLevelUpTransparency(0)
		levelUpLabel.Visible = true
		levelUpScale.Scale = 0.3
		TweenService:Create(levelUpScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(0.3 + 1.2, function()
			if token ~= levelUpToken then
				return
			end
			setLevelUpTransparency(1, TweenInfo.new(0.4))
			task.delay(0.45, function()
				if token == levelUpToken then
					levelUpLabel.Visible = false
				end
			end)
		end)
	end
end

----------------------------------------------------------------------------------------------------
-- Bottom-right: day/night timer
----------------------------------------------------------------------------------------------------
local bottomRight = new("Frame", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14),
	Size = UDim2.fromOffset(260, 200), Parent = gui,
}, { new("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
local dayFrame = new("Frame", { Size = UDim2.fromOffset(240, 40), BackgroundColor3 = COLORS.shop, LayoutOrder = 2, Parent = bottomRight }, deco(10))
local dayLabel = text(dayFrame, { Text = "", Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromOffset(6, 3) })

----------------------------------------------------------------------------------------------------
-- Hotbar (bottom centre): Bat
----------------------------------------------------------------------------------------------------
local hotbar = new("Frame", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.fromOffset(200, 84), Parent = gui,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10) }) })
local batCooldownUntil = 0
local function useBat()
	if os.clock() >= batCooldownUntil then
		RequestUseItem:FireServer("Bat")
	end
end
local batSlot = button(hotbar, "🏏\nBat", Color3.fromRGB(200, 140, 80), UDim2.fromOffset(84, 84), useBat, "Bat")
text(batSlot, { Text = "1", Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(4, 2), TextColor3 = COLORS.gold })
local batShade = new("Frame", {
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 0),
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Parent = batSlot,
}, { new("UICorner", { CornerRadius = UDim.new(0, 10) }) })

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
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -96, 0.45, 0), Size = UDim2.fromOffset(340, 420),
	BackgroundColor3 = COLORS.panel, Visible = false, Parent = gui,
}, deco(14))
local sideTitle = text(sidePanel, { Text = "", Size = UDim2.new(1, -20, 0, 36), Position = UDim2.fromOffset(10, 8), TextColor3 = INK })
sideTitle:FindFirstChildOfClass("UIStroke"):Destroy()
local sideList = new("ScrollingFrame", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 50), Size = UDim2.new(1, -20, 1, -60),
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, BorderSizePixel = 0,
	Parent = sidePanel,
}, { new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

local sideTab: string? = nil
local renderSide: () -> ()

local function card(order: number, color: Color3, height: number?): Frame
	return new("Frame", { Size = UDim2.new(1, -8, 0, height or 54), BackgroundColor3 = color, LayoutOrder = order, Parent = sideList }, deco(10, 2))
end

local function clearSide()
	for _, c in sideList:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

type BagEntry = { key: string, count: number, zone: number, rarity: number, mutation: string? }
local function bagEntries(): { BagEntry }
	local list: { BagEntry } = {}
	for key, count in stats.seedBag or {} do
		local z, r, m = SeedPacks.parseBagKey(key)
		if z and r then
			table.insert(list, { key = key, count = count, zone = z, rarity = r, mutation = m })
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

local function renderSeeds()
	Icons.set(sideTitle, { "Seeds", "Bag" }, `🌱 Seeds · 🎒 {SeedPacks.bagCount(stats.seedBag or {})}/{Config.SEED_BAG_MAX}`)
	local c = stats.carrying
	local top = card(0, if c then COLORS.gold else COLORS.slow, 44)
	text(top, {
		Text = if c then `Carrying: {Config.RARITIES[c.rarity].id} {Config.ZONES[c.zone].seed}` else "Not carrying a seed",
		Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4),
	})

	-- Seed bag (from seed packs): plant at your pad
	local bag = bagEntries()
	local hint = card(1, COLORS.index, 40)
	local hintText = if #bag == 0 then "🎁 Buy seed packs in the 🛒 Shop: their seeds land here!" else "🎒 Your bag: stand on your plot's pad, then Plant."
	Icons.set(text(hint, { Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4) }), { "Bag" }, hintText, ICON.medium)
	for i, e in bag do
		local rarity = Config.RARITIES[e.rarity]
		local mut = Config.mutationById(e.mutation)
		local f = card(1 + i, (if mut then mut.color else rarity.color):Lerp(Color3.new(0, 0, 0), 0.3), 54)
		text(f, {
			Text = `{Config.ZONES[e.zone].icon} {SeedPacks.seedName(e.zone, e.rarity, e.mutation)} x{e.count}`,
			Size = UDim2.new(1, -98, 1, -10), Position = UDim2.fromOffset(6, 5), TextXAlignment = Enum.TextXAlignment.Left,
		})
		button(f, "🌱 Plant", COLORS.money, UDim2.fromOffset(84, 40), function()
			RequestUseItem:FireServer("Seed:" .. e.key)
		end, "Seeds").Position = UDim2.new(1, -90, 0, 7)
	end

	for k, zone in Config.ZONES do
		local ok = stats.speed >= zone.req
		local f = card(100 + k, if ok then zone.ui else COLORS.disabled, 58)
		text(f, { Text = `{zone.icon} {zone.seed} · {zone.name} {Config.ACTIVE_ICONS[zone.active]}`, Size = UDim2.new(1, -12, 0.5, -2), Position = UDim2.fromOffset(6, 3), TextXAlignment = Enum.TextXAlignment.Left })
		local reqLabel = text(f, {
			Size = UDim2.new(1, -12, 0.45, -2), Position = UDim2.new(0, 6, 0.5, 0), TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if ok then Color3.fromRGB(230, 255, 230) else Color3.fromRGB(255, 235, 235),
		})
		Icons.set(reqLabel, { "Lock" }, `{if ok then "✅" else "🔒"} Rec. Speed {Format.short(zone.req)} · {Format.money(Config.seedIncome(k))}/s base`)
	end
end

local function renderPlants()
	local plants = table.clone(stats.plants or {})
	table.sort(plants, function(a, b)
		return a.income > b.income
	end)
	Icons.set(sideTitle, "Plants", `🪴 Plants {#plants}/{stats.slots} · {Format.money(stats.income)}/s`)
	if #plants == 0 then
		local f = card(0, COLORS.slow, 60)
		text(f, { Text = "No plants yet. Steal a seed and plant it on your pad!", Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4) })
	end
	for i, p in plants do
		local rarity = Config.RARITIES[p.rarity]
		local mut = Config.mutationById(p.mutation)
		local f = card(i, (if mut then mut.color else rarity.color):Lerp(Color3.new(0, 0, 0), 0.2), 54)
		text(f, {
			Text = `{if p.mutation then p.mutation .. " " else ""}{rarity.id} {Config.ZONES[p.zone].seed}`,
			Size = UDim2.new(1, -12, 0.5, -2), Position = UDim2.fromOffset(6, 3), TextXAlignment = Enum.TextXAlignment.Left,
		})
		text(f, {
			Text = `{Format.weight(p.weight)} · {Format.money(p.income)}/s`,
			Size = UDim2.new(1, -12, 0.45, -2), Position = UDim2.new(0, 6, 0.5, 0), TextXAlignment = Enum.TextXAlignment.Left,
		})
	end
end

renderSide = function()
	clearSide()
	if sideTab == "Seeds" then
		renderSeeds()
	elseif sideTab == "Plants" then
		renderPlants()
	end
end

for _, tab in { { "Seeds", "🌱" }, { "Plants", "🪴" } } do
	local name = tab[1] -- also the icon key
	button(rightTabs, tab[2], Color3.fromRGB(110, 210, 120), UDim2.fromOffset(70, 70), function()
		if sideTab == name then
			sideTab = nil
			sidePanel.Visible = false
		else
			sideTab = name
			sidePanel.Visible = true
			renderSide()
		end
	end, name)
end

----------------------------------------------------------------------------------------------------
-- Modals: Shop, Trail Shop and Index share one chunky window, like the reference: a coloured title bar
-- (light diagonal stripes, a shine, the big outlined title) with a red square X, over a dark slate body
-- with a faint stud pattern. Each window has its own bar colour (WINDOWS). The body scrolls down (Shop,
-- Index) or sideways (Trail Shop: one row of tall cards, a scrollbar at the bottom, arrows on the sides).
-- Sizes are design pixels; modalScale shrinks the whole window to fit small screens (fitModal).
----------------------------------------------------------------------------------------------------
local MODAL_W, MODAL_H, TITLE_H = 860, 600, 84
local MODAL_PAD = 14 -- the body's inset from the window's edges
local SCROLLBAR = 14
local FRAME_INK = Color3.fromRGB(16, 18, 26)
local BODY_COLOR = Color3.fromRGB(44, 50, 66)
local NOTE_COLOR = Color3.fromRGB(215, 222, 240)
local NUMBER_GREEN = "#5FFF3C" -- the "x2" on the trail cards' Speed pill
local HEADING_GOLD = Color3.fromRGB(255, 214, 50)
local HEADING_GREEN = Color3.fromRGB(120, 245, 70)
local ROBUX_GREEN = Color3.fromRGB(105, 235, 25) -- the Shop's R$ buttons
local GIFT_PINK = Color3.fromRGB(215, 55, 235) -- the gift button beside them
local WINDOWS = {
	Shop = { title = "Shop", icon = "Shop", from = Color3.fromRGB(115, 222, 50), to = Color3.fromRGB(28, 168, 78) },
	Trails = { title = "Trail Shop", icon = "TrailShop", from = Color3.fromRGB(170, 60, 255), to = Color3.fromRGB(250, 80, 205) },
	Index = { title = "Index", icon = "Index", from = Color3.fromRGB(55, 178, 255), to = Color3.fromRGB(45, 92, 235) },
}

-- Paints a frame `color` with a lit top: a WHITE background under a vertical colour gradient.
local function shade(f: GuiObject, color: Color3, light: number?, dark: number?)
	f.BackgroundColor3 = WHITE
	new("UIGradient", {
		Rotation = 90, Color = ColorSequence.new(color:Lerp(WHITE, light or 0.3), color:Lerp(Color3.new(0, 0, 0), dark or 0.15)), Parent = f,
	})
end

-- A soft white shine over the top half of a rounded frame.
local function shine(f: GuiObject, radius: number)
	new("Frame", { Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = f }, {
		new("UICorner", { CornerRadius = UDim.new(0, radius) }),
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.7, 1) }),
	})
end

-- An icon by its Icons key, or its emoji (Icons.TOKENS) while it isn't uploaded.
local function bigIcon(parent: Instance, key: string, props: { [string]: any }): GuiObject
	local tokens = Icons.TOKENS[key]
	return iconLabel(parent, key, if tokens then tokens[1] else "", props)
end

-- A chunky button: lit top, dark outline, outlined caption (with `icon` key(s) in place of emoji/"R$").
local function chunky(parent: Instance, label: string, color: Color3, size: UDim2, onClick: () -> (), icon: (string | { string })?, iconSize: number?): TextButton
	local b = new("TextButton", { Size = size, BackgroundColor3 = color, Text = "", AutoButtonColor = true, Parent = parent }, deco(10, 3))
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(200, 200, 200)), Parent = b })
	local l = bold(b, 3, { Name = "Label", Text = label, Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6) })
	if icon then
		Icons.set(l, icon, label, iconSize or ICON.medium)
	end
	b.Activated:Connect(onClick)
	return b
end

local modal = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(MODAL_W, MODAL_H),
	BackgroundColor3 = BODY_COLOR, Active = true, Visible = false, ZIndex = 10, Parent = gui,
}, {
	new("UICorner", { CornerRadius = UDim.new(0, 18) }),
	new("UIStroke", { Thickness = 6, Color = FRAME_INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(190, 192, 205)) }),
})
local modalScale = new("UIScale", { Parent = modal })

-- Faint studs over the body, like the reference's plate
local studs = new("Frame", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(0, TITLE_H), Size = UDim2.new(1, 0, 1, -TITLE_H), ClipsDescendants = true, Parent = modal,
}, {
	new("UIGridLayout", { CellSize = UDim2.fromOffset(20, 20), CellPadding = UDim2.fromOffset(16, 16) }),
	new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingTop = UDim.new(0, 16) }),
})
for _ = 1, math.ceil(MODAL_W / 36) * math.ceil((MODAL_H - TITLE_H) / 36) do
	new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.955, Parent = studs }, { new("UICorner", { CornerRadius = UDim.new(0, 5) }) })
end

-- Title bar: the window's colours left to right, square bottom corners, stripes and a shine
local titleBar = new("Frame", {
	Size = UDim2.new(1, 0, 0, TITLE_H), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2, Parent = modal,
}, { new("UICorner", { CornerRadius = UDim.new(0, 18) }) })
local titleGradient = new("UIGradient", { Parent = titleBar })
local barBottom = new("Frame", {
	Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 1, Parent = titleBar,
})
local barBottomGradient = new("UIGradient", { Parent = barBottom })
-- Diagonal stripes: a square (so the gradient's 45° is a true 45°) seen through the bar, clipped to it
local stripeClip = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ClipsDescendants = true, ZIndex = 2, Parent = titleBar })
local stripeKeys = { NumberSequenceKeypoint.new(0, 1) }
for _, band in { { 0.53, 0.565 }, { 0.585, 0.6 }, { 0.625, 0.67 } } do
	table.insert(stripeKeys, NumberSequenceKeypoint.new(band[1] - 0.001, 1))
	table.insert(stripeKeys, NumberSequenceKeypoint.new(band[1], 0.8))
	table.insert(stripeKeys, NumberSequenceKeypoint.new(band[2], 0.8))
	table.insert(stripeKeys, NumberSequenceKeypoint.new(band[2] + 0.001, 1))
end
table.insert(stripeKeys, NumberSequenceKeypoint.new(1, 1))
new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(MODAL_W, MODAL_W), BackgroundColor3 = WHITE,
	BorderSizePixel = 0, Parent = stripeClip,
}, { new("UIGradient", { Rotation = 45, Transparency = NumberSequence.new(stripeKeys) }) })
new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2, Parent = titleBar }, {
	new("UICorner", { CornerRadius = UDim.new(0, 18) }),
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 1),
	}) }),
})
-- The dark line between the bar and the body
new("Frame", { Position = UDim2.fromOffset(0, TITLE_H - 3), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = FRAME_INK, BorderSizePixel = 0, ZIndex = 3, Parent = modal })

local modalTitle = bold(titleBar, 5, {
	Text = "", Size = UDim2.new(1, -460, 0, 60), Position = UDim2.fromOffset(22, 10), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
})
-- Right of the title: your money (Shop, Trail Shop) or how much of the Index you've found
local modalSubtitle = bold(titleBar, 3, {
	Text = "", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -94, 0.5, 0), Size = UDim2.fromOffset(340, 34),
	TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = MONEY_GREEN, ZIndex = 3,
})

-- The red square X (the Close icon inside once uploaded, a white outlined X until then)
local modalClose = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, -1), Size = UDim2.fromOffset(64, 64), BackgroundColor3 = WHITE,
	Text = "", AutoButtonColor = true, ZIndex = 3, Parent = titleBar,
}, deco(10, 4))
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 85, 85), Color3.fromRGB(200, 20, 35)), Parent = modalClose })
local closeImage = Icons.image("Close")
if closeImage then
	new("ImageLabel", {
		BackgroundTransparency = 1, Image = closeImage, ScaleType = Enum.ScaleType.Fit, Size = UDim2.new(1, -10, 1, -10), Position = UDim2.fromOffset(5, 5),
		ZIndex = 3, Parent = modalClose,
	})
else
	bold(modalClose, 4, { Text = "X", Size = UDim2.new(1, -16, 1, -14), Position = UDim2.fromOffset(8, 7), ZIndex = 3 })
end

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
	modalScale.Scale = math.clamp(math.min((w - 24) / (MODAL_W + 12), (h - 24) / (MODAL_H + 12)), 0.3, 1)
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
	}, { new("UICorner", { CornerRadius = UDim.new(0, 10) }), new("UIStroke", { Thickness = 3, Color = WHITE, Transparency = 0.35 }) })
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
	titleGradient.Color = ColorSequence.new(window.from, window.to)
	barBottomGradient.Color = titleGradient.Color
	local tokens = Icons.TOKENS[window.icon]
	Icons.set(modalTitle, window.icon, `{if tokens then tokens[1] .. " " else ""}{window.title}`, ICON.big)
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

-- "-- SPEED --": a big outlined section title in gold or green (the icon goes in front once uploaded)
local function section(label: string, order: number, color: Color3, icon: string?): TextLabel
	local h = bold(modalBody, 4, { Text = `-- {label} --`, Size = UDim2.new(1, -12, 0, 48), TextColor3 = color, LayoutOrder = order })
	if icon then
		Icons.set(h, icon, h.Text, ICON.big, 38)
	end
	return h
end

-- Your money in the title bar (Shop, Trail Shop)
local function moneySubtitle()
	modalSubtitle.TextColor3 = MONEY_GREEN
	watchMoney(function()
		Icons.set(modalSubtitle, "Money", `💰 {Format.money(stats.money)}`, ICON.big, 30)
	end)
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
-- from Config is shown.
local robuxPrices: { [number]: number } = {}
local priceFetching: { [number]: boolean } = {}
local priceRerender = false
local function robuxPrice(product: Config.DevProduct): number
	local cached = robuxPrices[product.id]
	if cached then
		return cached
	end
	if product.id ~= 0 and not priceFetching[product.id] then
		priceFetching[product.id] = true
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, product.id, Enum.InfoType.Product)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				robuxPrices[product.id] = info.PriceInRobux
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
					priceFetching[product.id] = nil
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

local function giftButton(parent: Instance, size: UDim2): TextButton
	-- Gifting needs extra work (choosing a player, granting to them): shown, but not live yet.
	return chunky(parent, "🎁", GIFT_PINK, size, function()
		toast("🎁 Gifting is coming soon!", "blue")
	end, "Gift", ICON.big)
end

----------------------------------------------------------------------------------------------------
-- Shop: seed packs (premium cards with loot tables showing the exact server odds), then every other
-- item as a bright card (docs/references: Speed blue, Money green, each section its own colour) with
-- light rays behind a big icon, the amount in big outlined text ("+150K" in green, then "SPEED"), the
-- magenta gift button and a bright green R$ button; the plot and treadmill cards add a $ button.
----------------------------------------------------------------------------------------------------
local packShines: { Frame } = {} -- swept across the premium cards every frame while they're shown
local renderShop: () -> boolean
do
	local SHOP_CARD_W, SHOP_CARD_H = 252, 236 -- three cards a row
	local CARD_COLORS = {
		Speed = Color3.fromRGB(30, 165, 255),
		Money = Color3.fromRGB(70, 205, 30),
		PlotUpgrade = Color3.fromRGB(255, 150, 20),
		Treadmill = Color3.fromRGB(255, 60, 95),
		Pass = Color3.fromRGB(165, 70, 255),
	}

	-- A sunburst behind a card's icon: soft white rays turning around (cx, cy) (scale of the card) over a
	-- glow, fading out toward the card's edges (the card clips them).
	local function sunburst(c: Frame, cx: number, cy: number)
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
				AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(SHOP_CARD_W * 1.5, 26), Rotation = i * 20 + 8, BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.55, BorderSizePixel = 0, Parent = burst,
			}, { new("UIGradient", { Transparency = fade }) })
		end
		for _, glow in { { 190, 0.86 }, { 130, 0.8 }, { 76, 0.72 } } do
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(glow[1], glow[1]), BackgroundColor3 = WHITE, BackgroundTransparency = glow[2],
				BorderSizePixel = 0, Parent = burst,
			}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		end
	end

	-- Loot table: one row per rarity with a bar as wide as its chance.
	local function lootTable(parent: Instance, pack: SeedPacks.Pack, pos: UDim2, size: UDim2)
		local odds = SeedPacks.odds(pack)
		local holder = new("Frame", { BackgroundTransparency = 1, Position = pos, Size = size, Parent = parent },
			{ new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }) })
		local rows = #Config.RARITIES
		for i, rarity in Config.RARITIES do
			local pct = odds.rarities[i]
			local row = new("Frame", {
				Size = UDim2.new(1, 0, 1 / rows, -3), BackgroundColor3 = Color3.fromRGB(28, 24, 46), LayoutOrder = i, Parent = holder,
			}, { new("UICorner", { CornerRadius = UDim.new(0, 6) }) })
			new("Frame", {
				Size = UDim2.new(math.clamp(pct / 100, 0.03, 1), 0, 1, 0), BackgroundColor3 = rarity.color, BackgroundTransparency = 0.45, Parent = row,
			}, { new("UICorner", { CornerRadius = UDim.new(0, 6) }) })
			text(row, { Text = rarity.id, Size = UDim2.new(0.62, -8, 1, -4), Position = UDim2.fromOffset(8, 2), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = rarity.color })
			text(row, { Text = SeedPacks.percent(pct), Size = UDim2.new(0.38, -8, 1, -4), Position = UDim2.new(0.62, 0, 0, 2), TextXAlignment = Enum.TextXAlignment.Right })
		end
	end

	local function mutationLine(pack: SeedPacks.Pack): string
		local parts = {}
		for _, m in SeedPacks.odds(pack).mutations do
			local icon = if m.id == pack.exclusive then "🌟" else "✨"
			table.insert(parts, `{icon} {m.id} {SeedPacks.percent(m.pct)}`) -- each emoji becomes the Star icon once uploaded
		end
		return table.concat(parts, "  ·  ")
	end

	-- One big premium card per pack: zone colours, a gold frame, a sweeping shine, the loot table with
	-- the exact odds and the R$ button. No Speed gate: anyone can buy them.
	local function packCard(parent: Instance, order: number, productName: string, product: Config.DevProduct, bagFull: boolean)
		local pack = SeedPacks.packForProduct(product)
		local zone = Config.ZONES[pack.zone]
		local c = new("Frame", {
			Size = UDim2.new(0.5, -7, 1, 0), BackgroundColor3 = WHITE, ClipsDescendants = true, LayoutOrder = order, Parent = parent,
		}, {
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new(zone.ui:Lerp(WHITE, 0.15), zone.ui:Lerp(Color3.new(0, 0, 0), 0.55)) }),
			new("UICorner", { CornerRadius = UDim.new(0, 16) }),
			new("UIStroke", { Thickness = 4, Color = COLORS.gold, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		})
		table.insert(packShines, new("Frame", { Size = UDim2.new(0, 80, 1, 0), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = c }, {
			new("UIGradient", { Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(1, 1),
			}) }),
		}))
		local band = new("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = COLORS.gold, BorderSizePixel = 0, Parent = c })
		Icons.set(text(band, { Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromOffset(6, 3) }), "SeedPack", "💎 PREMIUM · LATE-GAME SEED")
		text(c, { Text = zone.icon, Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(12, 36) })
		bold(c, 4, { Text = pack.name, Size = UDim2.new(1, -94, 0, 34), Position = UDim2.fromOffset(82, 38), TextXAlignment = Enum.TextXAlignment.Left })
		text(c, {
			Text = `{zone.name} seed · no Speed needed`, Size = UDim2.new(1, -94, 0, 22), Position = UDim2.fromOffset(82, 74),
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 245, 210),
		})
		lootTable(c, pack, UDim2.fromOffset(12, 106), UDim2.new(1, -24, 0, 140))
		Icons.set(text(c, { Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 252), TextColor3 = Color3.fromRGB(255, 240, 180) }),
			{ "Star" }, mutationLine(pack), ICON.small)
		local exclusive = Config.mutationById(pack.exclusive)
		local perks = text(c, {
			Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, 280), TextWrapped = true, TextColor3 = Color3.fromRGB(255, 255, 230),
		})
		Icons.set(perks, { "Money", "Star" }, `💰 {Format.money(Config.seedIncome(pack.zone))}/s per Common sprout`
			.. (if exclusive then ` · 🌟 {exclusive.id} x{exclusive.income} income, only from packs` else ""), ICON.small)
		-- Robux only. With id = 0 the server answers "coming soon"; with a full bag it won't prompt.
		local price = Format.robux(robuxPrice(product))
		chunky(c, if bagFull then `🎒 Bag full · {price}` else price, if bagFull then COLORS.disabled else robuxColor(product.id, ROBUX_GREEN),
			UDim2.new(1, -96, 0, 58), function()
				RequestBuy:FireServer("Product:" .. productName)
			end, { "Robux", "Bag" }, ICON.small).Position = UDim2.new(0, 84, 1, -70)
		giftButton(c, UDim2.fromOffset(62, 58)).Position = UDim2.new(0, 12, 1, -70)
	end

	-- A grid of shop cards (3 per row), auto-sized to its contents.
	local function cardGrid(order: number): Frame
		return new("Frame", {
			BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = modalBody,
		}, {
			new("UIGridLayout", {
				CellSize = UDim2.fromOffset(SHOP_CARD_W, SHOP_CARD_H), CellPadding = UDim2.fromOffset(14, 14), SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			}),
		})
	end

	-- A shop card: a saturated `color` (lighter at the top), light rays behind a big icon, the amount in
	-- big outlined text (rich text: "+150K" can be green) and, only when `sub` isn't "", a short line under
	-- it. The caller adds the buttons (buyRow). Returns the card and its amount label.
	local function shopCard(grid: Instance, order: number, color: Color3, amount: string, sub: string, icon: string): (Frame, TextLabel)
		local c = new("Frame", { LayoutOrder = order, ClipsDescendants = true, Parent = grid }, {
			new("UICorner", { CornerRadius = UDim.new(0, 14) }),
			new("UIStroke", { Thickness = 4, Color = FRAME_INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		})
		shade(c, color, 0.35, 0.12)
		local short = sub ~= ""
		local iconSize = if short then 104 else 124
		sunburst(c, 0.5, (6 + iconSize / 2) / SHOP_CARD_H)
		bigIcon(c, icon, { Size = UDim2.fromOffset(iconSize, iconSize), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), ZIndex = 2 })
		local amountLabel = bold(c, 4, {
			Text = amount, RichText = true, Size = UDim2.new(1, -16, 0, 44), Position = UDim2.fromOffset(8, iconSize + 4), ZIndex = 2,
		})
		if short then
			bold(c, 2, { Text = sub, Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, iconSize + 48), ZIndex = 2 })
		end
		return c, amountLabel
	end

	-- The bottom row of a shop card: the magenta gift button on the left for Robux items, then the buy button.
	local function buyRow(c: Frame, caption: string, color: Color3, onClick: () -> (), icon: (string | { string })?, gift: boolean): TextButton
		local b = chunky(c, caption, color, UDim2.new(1, if gift then -84 else -20, 0, 52), onClick, icon, ICON.small)
		b.Position, b.ZIndex = UDim2.new(0, if gift then 74 else 10, 1, -62), 2
		if gift then
			local g = giftButton(c, UDim2.fromOffset(56, 52))
			g.Position, g.ZIndex = UDim2.new(0, 10, 1, -62), 2
		end
		return b
	end

	-- A Robux card for developer product `name`.
	local function productCard(grid: Instance, order: number, name: string, product: Config.DevProduct, color: Color3, amount: string, icon: string): (Frame, TextLabel)
		local c, amountLabel = shopCard(grid, order, color, amount, "", icon)
		buyRow(c, Format.robux(robuxPrice(product)), robuxColor(product.id, ROBUX_GREEN), function()
			RequestBuy:FireServer("Product:" .. name)
		end, { "Robux" }, true)
		return c, amountLabel
	end

	-- A card with a $ button (gold while affordable) and, while there's a product for it, a green R$ one.
	local function upgradeButtons(c: Frame, price: number?, buy: string, productName: string?, product: Config.DevProduct?)
		local b = buyRow(c, if price then Format.money(price) else "Maxed", COLORS.disabled, function()
			RequestBuy:FireServer(buy)
		end, nil, false)
		watchMoney(function()
			b.BackgroundColor3 = if price and stats.money >= price then COLORS.shop else COLORS.disabled
		end)
		if price and productName and product then
			b.Size = UDim2.new(0.5, -14, 0, 52)
			local r = chunky(c, Format.robux(robuxPrice(product)), robuxColor(product.id, ROBUX_GREEN), UDim2.new(0.5, -14, 0, 52), function()
				RequestBuy:FireServer("Product:" .. productName)
			end, { "Robux" }, ICON.small)
			r.Position, r.ZIndex = UDim2.new(0.5, 4, 1, -62), 2
		end
	end

	-- Returns true when it scrolled to a section (openShopAt), so renderModal doesn't restore the old scroll.
	function renderShop(): boolean
		clearModal(10)
		moneySubtitle()
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end

		-- Seed packs (Robux)
		section("SEED PACKS", nextOrder(), HEADING_GOLD, "SeedPack")
		local bagCount = SeedPacks.bagCount(stats.seedBag or {})
		local bagFull = bagCount >= Config.SEED_BAG_MAX
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 400), LayoutOrder = nextOrder(), Parent = modalBody },
			{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }) })
		for i, entry in Config.products("Pack") do
			packCard(row, i, entry.name, entry.product, bagFull)
		end
		note(`🎒 Seed bag {bagCount}/{Config.SEED_BAG_MAX}{if bagFull then " (full: plant some first!)" else ""} · plant bagged seeds from the 🌱 Seeds menu at your plot's pad`, nextOrder(), { "Bag", "Seeds" })

		-- Plot upgrade: money or Robux (also on the board at your plot's gate). The R$ product is the one
		-- for the plot's current price tier (looked up on every render, so it follows plotLevel); none at
		-- the last level.
		section("PLOT UPGRADE", nextOrder(), HEADING_GREEN, "PlotUpgrade")
		local level = stats.plotLevel or 1
		local price = Config.priceOf("PlotUpgrade", stats :: any)
		local plotCard = shopCard(cardGrid(nextOrder()), 1, CARD_COLORS.PlotUpgrade, if price then `LEVEL {level + 1}` else "MAX LEVEL",
			if price then `+1 slot · cash x{Config.plotMoneyMult(level)} → x{Config.plotMoneyMult(level + 1)}`
				else `{Config.plotSlots(level)} slots · cash x{Config.plotMoneyMult(level)}`, "PlotUpgrade")
		upgradeButtons(plotCard, price, "PlotUpgrade", Config.plotUpgradeProduct(level))

		-- Speed (Robux), blue; the HUD's "+" on the Speed icon opens the Shop here
		local shopSections: { [string]: GuiObject } = {}
		shopSections.Speed = section("SPEED", nextOrder(), HEADING_GOLD, "Speed")
		local grid = cardGrid(nextOrder())
		for i, entry in Config.products("Speed") do
			local amount, rest = string.match(string.upper(entry.product.label), "^(%S+)%s+(.+)$")
			productCard(grid, i, entry.name, entry.product, CARD_COLORS.Speed,
				if amount then `<font color="{NUMBER_GREEN}">{amount}</font> {rest}` else string.upper(entry.product.label), "Speed")
		end

		-- Money (Robux), green: the card shows what you'd get right now (fixed, or minutes of your income)
		section("MONEY", nextOrder(), HEADING_GREEN, "Money")
		grid = cardGrid(nextOrder())
		for i, entry in Config.products("Money") do
			local _, amountLabel = productCard(grid, i, entry.name, entry.product, CARD_COLORS.Money, "", "Money")
			watchMoney(function()
				amountLabel.Text = Format.money(Config.moneyPackAmount(entry.product, stats.income or 0))
			end)
		end

		-- Treadmill: the next tier for money or Robux (also on the prompts at your treadmill), like the plot card
		section("TREADMILL", nextOrder(), HEADING_GOLD, "Treadmill")
		local tier = stats.treadmillTier or 1
		local treadPrice = Config.priceOf("TreadmillUpgrade", stats :: any)
		local treadCard = shopCard(cardGrid(nextOrder()), 1, CARD_COLORS.Treadmill,
			if treadPrice then `x{Config.treadmillMult(tier + 1)} TREADMILL` else "MAX TREADMILL",
			if treadPrice then `Tier {tier + 1}/{Config.TREADMILL_MAX} · now x{Config.treadmillMult(tier)}`
				else `x{Config.treadmillMult(tier)} · stand on it to gain Speed`, "Treadmill")
		upgradeButtons(treadCard, treadPrice, "TreadmillUpgrade", Config.treadmillUpgradeProduct(tier))

		-- Gamepasses (Robux), purple
		section("PASSES", nextOrder(), HEADING_GREEN)
		grid = cardGrid(nextOrder())
		for i, name in { "DoubleMoney", "ExtraSlots" } do
			local pass = Config.GAMEPASSES[name]
			local owned = stats.passes[name] == true
			local c = shopCard(grid, i, CARD_COLORS.Pass, string.upper(pass.label),
				if name == "DoubleMoney" then "Doubles all plant income" else "On top of your plot level's slots", name)
			buyRow(c, if owned then "Owned" else "Buy · R$", if owned then COLORS.disabled else robuxColor(pass.id, ROBUX_GREEN), function()
				RequestBuy:FireServer("Pass:" .. name)
			end, { "Robux" }, true)
		end

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
-- and a purple R$ button, or Equip / Equipped once owned.
----------------------------------------------------------------------------------------------------
-- "+0.5", "+12.3", "+1.2K": the Speed one step (stud) pays right now (Config.speedPerStud)
local renderTrails: () -> ()
do
	local function perStepText(): string
		local x = Config.speedPerStud(stats.speed or 0, stats.equippedTrail)
		return "+" .. (if x < 100 then string.format("%.1f", x) else Format.short(x))
	end

	local function trailCard(parent: Instance, order: number, t: Config.Trail): Frame
		local owned = stats.trails[t.id] == true
		local equipped = stats.equippedTrail == t.id
		local c = new("Frame", { Size = UDim2.fromOffset(TRAIL_W, TRAIL_H), BackgroundColor3 = WHITE, LayoutOrder = order, Parent = parent }, {
			new("UICorner", { CornerRadius = UDim.new(0, 14) }),
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
		shine(c, 14)
		bold(c, 4, { Text = t.name, Size = UDim2.new(1, -16, 0, 42), Position = UDim2.fromOffset(8, 12) })
		bold(c, 3, { Text = t.rarity, Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 54) })

		-- Illustration: a soft glow, the trail streaming out behind, the Trail Shop icon tinted on top
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 196), Size = UDim2.fromOffset(186, 186), BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.78, Parent = c,
		}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, -8, 0, 214), Size = UDim2.new(1, -34, 0, 62), Rotation = -14,
			BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = c,
		}, {
			new("UICorner", { CornerRadius = UDim.new(1, 0) }),
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
		}, { new("UICorner", { CornerRadius = UDim.new(0, 10) }), new("UIStroke", { Thickness = 3, Color = FRAME_INK, Transparency = 0.4 }) })
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
			chunky(c, Format.robux(robuxPrice(product)), robuxColor(product.id, COLORS.robux), UDim2.fromOffset(TRAIL_W - 24 - moneyW - 8, 54), function()
				RequestBuy:FireServer("Product:" .. (t.product :: string))
			end, { "Robux" }, ICON.small).Position = UDim2.fromOffset(12 + moneyW + 8, y)
		end
		return c
	end

	function renderTrails()
		clearModal(TRAIL_GAP, true)
		modalSubtitle.TextColor3 = WHITE
		watchMoney(function() -- the Speed one step pays right now (it grows with your Speed and trail), and your money
			Icons.set(modalSubtitle, { "Speed", "Money" }, `⚡ {perStepText()}/step  💰 {Format.money(stats.money)}`, ICON.big, 26)
		end)
		for i, t in Config.TRAILS do
			table.insert(trailCards, trailCard(modalBody, i, t))
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Index: one row per zone in the zone's colour, a cell per rarity (lit once discovered)
----------------------------------------------------------------------------------------------------
local function renderIndex()
	local total, found = 0, 0
	for k = 1, #Config.ZONES do
		for r = 1, #Config.RARITIES do
			total += 1
			if stats.index[`{k}:{r}`] then
				found += 1
			end
		end
	end
	modalSubtitle.TextColor3 = WHITE
	Icons.set(modalSubtitle, "Star", `✨ {found}/{total} discovered`, ICON.big, 30)
	clearModal(10)
	local rarities = #Config.RARITIES
	for k, zone in Config.ZONES do
		local row = new("Frame", { Size = UDim2.new(1, -12, 0, 112), LayoutOrder = k, Parent = modalBody }, {
			new("UICorner", { CornerRadius = UDim.new(0, 14) }),
			new("UIStroke", { Thickness = 4, Color = FRAME_INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		})
		shade(row, zone.ui, 0.25, 0.3)
		shine(row, 14)
		local mutText = ""
		for _, m in Config.MUTATIONS do
			if stats.index[`{k}:{m.id}`] then
				mutText ..= " " .. m.id
			end
		end
		local rowTitle = bold(row, 3, { Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left })
		Icons.set(rowTitle, { "Star" }, `{zone.icon} {zone.seed}{if mutText ~= "" then " ✨" .. mutText else ""}`)
		local cells = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 46), Size = UDim2.new(1, -24, 0, 56), Parent = row },
			{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
		for r, rarity in Config.RARITIES do
			local got = stats.index[`{k}:{r}`] == true
			local cell = new("Frame", {
				Size = UDim2.new(1 / rarities, -8 * (rarities - 1) / rarities, 1, 0), BackgroundColor3 = Color3.fromRGB(52, 58, 76), LayoutOrder = r, Parent = cells,
			}, deco(10, 3))
			if got then
				shade(cell, rarity.color, 0.3, 0.2)
			end
			bold(cell, if got then 3 else 2, {
				Text = if got then rarity.id else "???", Size = UDim2.new(1, -10, 1, -12), Position = UDim2.fromOffset(5, 6),
				TextColor3 = if got then WHITE else Color3.fromRGB(150, 156, 175),
			})
		end
	end
end

----------------------------------------------------------------------------------------------------
-- SELL window (TODO 9; the SELL stall in the shop plaza opens it). Everything for it is in this block;
-- renderModal and refresh call renderSell / sellChanged. One card per planted plant, cheapest first: the
-- creature in its rarity colour, the mutation, weight, $/s with its ☀️/🌙 tag, the sell price and a Sell
-- button. Above them "Sell all Common" / "Sell all below Rare" (they keep mutated plants). Every sale asks
-- once more inside the window: the card's button turns into "Sure?", a quick sell shows a confirm bar.
-- The server re-checks it all (remote SellPlants: your plants, the slots, standing at the stall).
-- Scoped in a do-block (the HUD's main chunk is near Luau's 200-locals limit); only these two leave it.
----------------------------------------------------------------------------------------------------
local renderSell: () -> ()
local sellChanged: (changed: { [string]: any }) -> ()
do
	local SellPlants = remotes:WaitForChild("SellPlants") :: RemoteEvent
	WINDOWS.Sell = { title = "Sell", icon = "Money", from = Color3.fromRGB(255, 70, 45), to = Color3.fromRGB(255, 150, 30) }
	local SELL_RED = Color3.fromRGB(235, 60, 50)
	local SELL_ORANGE = Color3.fromRGB(255, 140, 30)
	local SELL_DARK = Color3.fromRGB(52, 58, 76)
	local SELL_CARD_W, SELL_CARD_H = 190, 252

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

	type SellPending = { slot: number?, group: number? }
	local sellPending: SellPending? = nil -- the sale waiting for its confirm: one plant's slot, or a quick sell
	local sellUpdaters: { () -> () } = {} -- the open window's prices and $/s, updated in place on payouts
	local sellShown = "" -- which plants the window shows (sellSignature)

	-- Which plants there are (slot and kind), so a payout tick (same plants, new numbers) doesn't rebuild the
	-- window under the player's finger, but a sale or a new plant does.
	local function sellSignature(): string
		local keys = {}
		for _, p in stats.plants or {} do
			table.insert(keys, `{p.slot}:{p.zone}:{p.rarity}:{p.mutation or ""}`)
		end
		table.sort(keys)
		return table.concat(keys, ",")
	end

	local function plantInSlot(slot: number): any
		for _, p in stats.plants or {} do
			if p.slot == slot then
				return p
			end
		end
		return nil
	end

	-- The slots a sale would sell and what it pays right now.
	local function saleOf(pending: SellPending): ({ number }, number)
		local slots, total = {}, 0
		local group = pending.group and SELL_GROUPS[pending.group]
		for _, p in stats.plants or {} do
			if (pending.slot ~= nil and p.slot == pending.slot) or (group ~= nil and p.mutation == nil and p.rarity <= group.max) then
				table.insert(slots, p.slot)
				total += p.sell or 0
			end
		end
		return slots, total
	end

	local function sellNow(pending: SellPending)
		local slots = saleOf(pending)
		sellPending = nil
		if #slots > 0 then
			SellPlants:FireServer(slots)
		end
		renderModal()
	end

	-- "☀️ $1.2K/s 1.5x!" in gold while the plant's phase is on, like its billboard.
	local function sellIncomeText(p: any): (string, Color3)
		local zone = Config.ZONES[p.zone]
		local active = Config.isActiveTime(p.zone, (Config.dayPhase(workspace:GetServerTimeNow())))
		return `{Config.ACTIVE_ICONS[zone.active]} {Format.money(p.income)}/s{if active then string.format(" %gx!", Config.ACTIVE_TIME_MULT) else ""}`,
			if active then HEADING_GOLD else MONEY_GREEN
	end

	local function sellCard(grid: Instance, order: number, p: any)
		local rarity = Config.RARITIES[p.rarity]
		local mut = Config.mutationById(p.mutation)
		local zone = Config.ZONES[p.zone]
		local c = new("Frame", { BackgroundColor3 = SELL_DARK, LayoutOrder = order, Parent = grid }, {
			new("UICorner", { CornerRadius = UDim.new(0, 14) }),
			new("UIStroke", { Thickness = 4, Color = if mut then mut.color else FRAME_INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		})
		-- The rarity band: creature and rarity
		local band = new("Frame", { Size = UDim2.new(1, 0, 0, 70), BorderSizePixel = 0, Parent = c }, { new("UICorner", { CornerRadius = UDim.new(0, 14) }) })
		shade(band, rarity.color, 0.25, 0.25)
		shine(band, 14)
		bold(band, 3, { Text = `{zone.icon} {zone.seed}`, Size = UDim2.new(1, -14, 0, 32), Position = UDim2.fromOffset(7, 6) })
		bold(band, 3, { Text = rarity.id, Size = UDim2.new(1, -14, 0, 24), Position = UDim2.fromOffset(7, 40) })
		-- Mutation, weight, $/s
		local mutLabel = bold(c, 2, {
			Text = if mut then "✨ " .. mut.id else "no mutation", Size = UDim2.new(1, -14, 0, 24), Position = UDim2.fromOffset(7, 78),
			TextColor3 = if mut then mut.color else NOTE_COLOR, TextTransparency = if mut then 0 else 0.35,
		})
		if mut then
			Icons.set(mutLabel, "Star", mutLabel.Text, ICON.small)
		end
		local weightLabel = text(c, { Text = Format.weight(p.weight), Size = UDim2.new(1, -14, 0, 22), Position = UDim2.fromOffset(7, 106) })
		local incomeLabel = bold(c, 2, { Size = UDim2.new(1, -14, 0, 22), Position = UDim2.fromOffset(7, 132) })
		-- What the stall pays, and the button (a second click confirms)
		local priceLabel = bold(c, 3, { Size = UDim2.new(1, -14, 0, 34), Position = UDim2.fromOffset(7, 158), TextColor3 = MONEY_GREEN })
		local sure = sellPending ~= nil and sellPending.slot == p.slot
		chunky(c, if sure then "Sure? Sell" else "Sell", if sure then COLORS.gold else SELL_RED, UDim2.new(1, -16, 0, 48), function()
			if sure then
				sellNow({ slot = p.slot })
			else
				sellPending = { slot = p.slot }
				renderModal()
			end
		end).Position = UDim2.new(0, 8, 1, -56)
		local function update()
			local now = plantInSlot(p.slot) or p
			weightLabel.Text = Format.weight(now.weight)
			incomeLabel.Text, incomeLabel.TextColor3 = sellIncomeText(now)
			Icons.set(priceLabel, "Money", `💰 {Format.money(now.sell or 0)}`, ICON.small)
		end
		update()
		table.insert(sellUpdaters, update)
	end

	renderSell = function()
		clearModal(10)
		moneySubtitle()
		table.clear(sellUpdaters)
		sellShown = sellSignature()
		local plants = table.clone(stats.plants or {})
		table.sort(plants, function(a, b)
			if (a.sell or 0) ~= (b.sell or 0) then
				return (a.sell or 0) < (b.sell or 0)
			end
			return a.slot < b.slot
		end)
		note(`💰 The stall pays {Config.SELL_STALL_SECONDS // 60} min of a plant's income (R on a plant only gives {Config.SELL_SECONDS} s).`, 1, "Money")
		if #plants == 0 then
			note("No plants yet: steal a seed and plant it on your pad!", 2)
			return
		end

		-- Quick sells (they keep mutated plants)
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -12, 0, 60), LayoutOrder = 2, Parent = modalBody }, {
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 14) }),
		})
		for i, group in SELL_GROUPS do
			local count = #(saleOf({ group = i }))
			chunky(row, `{group.label} ({count})`, if count > 0 then SELL_ORANGE else COLORS.disabled, UDim2.fromOffset(330, 56), function()
				if count > 0 then
					sellPending = { group = i }
					renderModal()
				end
			end)
		end
		note("Quick sells keep your mutated plants.", 3, "Star")

		-- The quick sell's confirm bar
		local pending = sellPending
		local group = pending and pending.group and SELL_GROUPS[pending.group]
		if pending and group and #(saleOf(pending)) == 0 then
			sellPending, pending, group = nil, nil, nil -- nothing left to sell
		end
		if pending and group then
			local bar = new("Frame", { Size = UDim2.new(1, -12, 0, 72), BackgroundColor3 = FRAME_INK, BackgroundTransparency = 0.15, LayoutOrder = 4, Parent = modalBody }, deco(12, 3))
			local question = bold(bar, 3, {
				Size = UDim2.new(1, -350, 1, -18), Position = UDim2.fromOffset(16, 9), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = HEADING_GOLD,
			})
			local function update()
				local slots, total = saleOf(pending :: SellPending)
				question.Text = `Sell {#slots} {group.what} plant{if #slots == 1 then "" else "s"} for {Format.money(total)}?`
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
		if changed.plants then
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

	LootEvent.OnClientEvent:Connect(function(kind: string, data: any)
		if kind == "SoldPlants" and type(data) == "table" then
			toast(`💰 +{Format.money(data.amount or 0)} for {data.count} plant{if data.count == 1 then "" else "s"}`, "gold")
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
		task.defer(function() -- again once the layout has sized the new canvas
			if modal.Visible then
				modalBody.CanvasPosition = keep
			end
		end)
	end
	task.defer(updateTrailArrows)
end

----------------------------------------------------------------------------------------------------
-- Pack reveal: a reel of candidate seeds spins, lands on the server's result, then a burst in the
-- result's rarity colour. The result was decided (and bagged) on the server before this plays.
----------------------------------------------------------------------------------------------------
local queueReveal: (data: any) -> ()
do
	local CARD_W, CARD_H, CARD_GAP = 112, 128, 10
	local REEL_W, REEL_H = 640, 168
	local REEL_COUNT, REEL_TARGET = 44, 38
	local STAGE_W = 700

	local tickSound = new("Sound", { SoundId = Config.SOUNDS.Click, Volume = 0.35, Parent = SoundService })
	local landSound = new("Sound", { SoundId = Config.SOUNDS.Pickup, Volume = 0.8, Parent = SoundService })

	local revealGui = new("Frame", {
		Name = "Reveal", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35,
		Visible = false, Active = true, ZIndex = 20, Parent = gui,
	})
	local stage = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(STAGE_W, 500), BackgroundTransparency = 1, Parent = revealGui,
	})
	local revealTitle = text(stage, { Text = "", Size = UDim2.new(1, 0, 0, 44) })
	local burst = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(STAGE_W / 2, 60 + REEL_H / 2), Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1, ZIndex = 1, Parent = stage,
	})
	local reel = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(STAGE_W / 2, 60), Size = UDim2.fromOffset(REEL_W, REEL_H),
		BackgroundColor3 = Color3.fromRGB(30, 26, 48), ClipsDescendants = true, ZIndex = 2, Parent = stage,
	}, deco(14, 4))
	local strip = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(REEL_COUNT * (CARD_W + CARD_GAP), CARD_H), Parent = reel })
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = COLORS.gold, BorderSizePixel = 0, ZIndex = 5, Parent = reel,
	})
	local resultLabel = text(stage, { Text = "", Size = UDim2.new(1, 0, 0, 54), Position = UDim2.fromOffset(0, 60 + REEL_H + 14), ZIndex = 3 })
	local resultScale = new("UIScale", { Parent = resultLabel })
	local resultSub = text(stage, { Text = "", Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 60 + REEL_H + 70), ZIndex = 3 })
	local continueHint = text(stage, { Text = "Click to continue", Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -24), TextColor3 = Color3.fromRGB(220, 220, 235) })
	local closeButton = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 10, Visible = false, Parent = revealGui })

	local function seedCard(parent: Instance, zone: number, rarity: number, mutation: string?, size: UDim2): Frame
		local r = Config.RARITIES[rarity]
		local mut = Config.mutationById(mutation)
		local f = new("Frame", { Size = size, BackgroundColor3 = Color3.new(1, 1, 1), Parent = parent }, deco(12, 3))
		new("UIGradient", { Rotation = 45, Color = ColorSequence.new(r.color, if mut then mut.color else r.color:Lerp(Color3.new(0, 0, 0), 0.35)), Parent = f })
		text(f, { Text = Config.ZONES[zone].icon, Size = UDim2.fromScale(1, 0.46), Position = UDim2.fromScale(0, 0.08) })
		text(f, { Text = r.id, Size = UDim2.new(1, -8, 0.2, 0), Position = UDim2.new(0, 4, 0.56, 0) })
		if mut then
			Icons.set(text(f, { Size = UDim2.new(1, -8, 0.18, 0), Position = UDim2.new(0, 4, 0.78, 0) }), "Star", "✨" .. mut.id)
		end
		return f
	end

	local function burstAt(color: Color3, big: boolean)
		burst:ClearAllChildren()
		for i = 1, 6 do -- rotating rays
			local ray = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(if big then 26 else 16, 600), Rotation = i * 30,
				BackgroundColor3 = color, BackgroundTransparency = 0.3, BorderSizePixel = 0, Parent = burst,
			})
			TweenService:Create(ray, TweenInfo.new(3.5, Enum.EasingStyle.Linear), { Rotation = i * 30 + 75, BackgroundTransparency = 1 }):Play()
		end
		local flash = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = color, BackgroundTransparency = 0.1, Parent = burst,
		}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		TweenService:Create(flash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(640, 640), BackgroundTransparency = 1 }):Play()
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

		revealTitle.Text = `🎁 Opening {data.name}...`
		resultLabel.Visible, resultSub.Visible, continueHint.Visible, closeButton.Visible = false, false, false, false
		burst:ClearAllChildren()
		strip:ClearAllChildren()

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
			local card = seedCard(strip, pack.zone, rarity, mutation, UDim2.fromOffset(CARD_W, CARD_H))
			card.Name = "Card" .. i
			card.Position = UDim2.fromOffset((i - 1) * step, 0)
		end
		local y = (REEL_H - CARD_H) / 2
		strip.Position = UDim2.fromOffset(0, y)
		revealGui.Visible = true

		local finalX = REEL_W / 2 - ((REEL_TARGET - 1) * step + CARD_W / 2) + (math.random() - 0.5) * CARD_W * 0.7
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

		-- Land: pop the winning card, burst in its colour, name it
		local rarity = Config.RARITIES[best.rarity]
		local mut = Config.mutationById(best.mutation)
		local color = if mut then mut.color else rarity.color
		local card = strip:FindFirstChild("Card" .. REEL_TARGET)
		if card then
			local scale = new("UIScale", { Parent = card })
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.16 }):Play()
		end
		burstAt(color, best.rarity >= 4 or mut ~= nil)
		landSound:Play()
		resultLabel.Text = `{if mut then string.upper(mut.id) .. " " else ""}{string.upper(rarity.id)}!`
		resultLabel.TextColor3 = color
		resultLabel.Visible = true
		resultScale.Scale = 0.4
		TweenService:Create(resultScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		local exclusive = best.mutation ~= nil and best.mutation == pack.exclusive
		Icons.set(resultSub, { "Star" }, `{if exclusive then "🌟 PACK EXCLUSIVE! " else ""}{Config.ZONES[best.zone].icon} {SeedPacks.seedName(best.zone, best.rarity, best.mutation)} → your 🌱 Seeds bag`)
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
		end)
	end
end

----------------------------------------------------------------------------------------------------
-- Refresh from stats
----------------------------------------------------------------------------------------------------
local lastUnlocked = -1
local bestLevel: number? = nil -- highest level seen; nil until the server first sends our Speed
local function refresh(changed: { [string]: any })
	speedValue.Text = Format.short(stats.speed)
	moneyValue.Text = Format.money(stats.money)

	if changed.speed ~= nil then
		local announce
		bestLevel, announce = Config.levelUp(bestLevel, (Config.speedLevel(stats.speed)))
		if announce then
			announceLevel(announce)
		end
	end

	local c = stats.carrying
	carryBanner.Visible = c ~= false and c ~= nil
	if c then
		Icons.set(carryLabel, "Seeds", `🌱 {if c.mutation then c.mutation .. " " else ""}{Config.RARITIES[c.rarity].id} {Config.ZONES[c.zone].seed} — run home & plant it!`, ICON.medium)
		carryBanner.BackgroundColor3 = Config.RARITIES[c.rarity].color:Lerp(Color3.new(0, 0, 0), 0.15)
	end

	if not slowMode and changed.walkSpeed then
		applySlow()
	end
	-- Rebuilding lists every money tick is wasteful; only when their data changed.
	local unlocked = 0
	for _, zone in Config.ZONES do
		if stats.speed >= zone.req then
			unlocked += 1
		end
	end
	local unlockChanged = unlocked ~= lastUnlocked
	lastUnlocked = unlocked
	if sidePanel.Visible and (changed.plants or changed.carrying or changed.items or changed.seedBag or sideTab == "Seeds" and unlockChanged) then
		renderSide()
	end
	-- The open window is rebuilt when what it lists changes; money, income and Speed only update it in place.
	if modal.Visible and modalName == "Sell" then
		sellChanged(changed)
	elseif modal.Visible and (changed.index or changed.items or changed.slots or changed.plotLevel or changed.trails or changed.equippedTrail
		or changed.treadmillTier or changed.passes or changed.seedBag) then
		renderModal()
	elseif modal.Visible and (changed.money or changed.income or changed.speed) then
		for _, update in moneyWatchers do
			update()
		end
	end
end

StatsUpdate.OnClientEvent:Connect(function(partial: { [string]: any })
	for k, v in partial do
		stats[k] = v
	end
	refresh(partial)
end)

----------------------------------------------------------------------------------------------------
-- Loot events -> toasts
----------------------------------------------------------------------------------------------------
LootEvent.OnClientEvent:Connect(function(kind: string, data: any)
	data = data or {}
	if kind == "Toast" then
		toast(data.text, data.color)
	elseif kind == "Pickup" then
		toast(`You stole a {data.name}! RUN!`, "gold")
	elseif kind == "GuardWake" then
		toast(`😡 The {data.guard} woke up!`, "red")
	elseif kind == "Caught" then
		toast(`💥 The {data.guard} caught you! The seed went back to its nest.`, "red", 4)
	elseif kind == "Escaped" then
		toast(`😅 You escaped the {data.guard}!`, "green")
	elseif kind == "Planted" then
		toast(`🌱 Planted {data.name} · {Format.weight(data.weight)}`, "green")
		for _, key in data.newIndex or {} do
			-- keys are "zone:rarityIndex" or "zone:MutationId"
			local z, what = string.match(key, "^(%d+):(.+)$")
			local zone = z and Config.ZONES[tonumber(z) :: number]
			if zone then
				local rarity = Config.RARITIES[tonumber(what) or 0]
				toast(`📖 New Index entry: {if rarity then rarity.id else what} {zone.seed}!`, "blue")
			end
		end
	elseif kind == "Sold" then
		toast(`Removed plant: +{Format.money(data.amount)}`, "gold")
	elseif kind == "Bought" then
		toast(`Bought {data.label}!`, "green", 2)
	elseif kind == "Bat" then
		batCooldownUntil = os.clock() + (data.cooldown or Config.BAT_COOLDOWN)
		if data.hit then
			toast("💫 WHACK! Guard stunned!", "gold", 2)
		end
	elseif kind == "Offline" then
		toast(`While you were away ({Format.clock(data.seconds)}): +{Format.money(data.amount)}`, "gold", 6)
	elseif kind == "End" then
		toast("⛩️ YOU REACHED THE END OF THE LINE! ⛩️", "gold", 8)
	elseif kind == "PackRoll" then
		queueReveal(data)
	elseif kind == "DayNight" then
		toast(if data.night then "🌙 Night falls: rarer seeds and Night mutations!" else "☀️ The sun is up.", "blue", 4)
	end
end)

-- Server-wide announcements (Net.announce), e.g. "Alex got a LEGENDARY Starpetal!"
LootEvent.OnClientEvent:Connect(function(kind: string, data: any)
	if kind == "Announce" and data then
		toast(data.text, data.color, 6)
	end
end)

----------------------------------------------------------------------------------------------------
-- Per-frame bits: zone banner, timers, bat cooldown
----------------------------------------------------------------------------------------------------
local lastZone: number? = -1
local lastTimerUpdate = 0
RunService.RenderStepped:Connect(function()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local zone = if root then Config.zoneAtX(root.Position.X) else nil
	if zone ~= lastZone then
		lastZone = zone
		zoneBanner.Visible = zone ~= nil
	end
	if zone then
		local z = Config.ZONES[zone]
		local ok = stats.speed >= z.req
		zoneLabel.Text = `{z.icon} {string.upper(z.name)} · Rec. Speed {Format.short(z.req)}{if ok then " ✅" else " ⚠️"}`
		zoneBanner.BackgroundColor3 = if ok then COLORS.money else COLORS.red
	end

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

	if os.clock() - lastTimerUpdate >= 0.25 then
		lastTimerUpdate = os.clock()
		local now = workspace:GetServerTimeNow()
		local night, remaining = Config.dayPhase(now)
		dayLabel.Text = if night then `🌙 Night · Day in {Format.clock(remaining)}` else `☀️ Day · Night in {Format.clock(remaining)}`
		dayFrame.BackgroundColor3 = if night then Color3.fromRGB(70, 70, 160) else COLORS.shop
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
