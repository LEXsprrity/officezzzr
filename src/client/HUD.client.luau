-- HUD, built in code. Display only: it renders StatsUpdate/LootEvent, sends RequestBuy/RequestUseItem,
-- and owns the local Slow Mode toggle. No game state is decided here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestBuy = remotes:WaitForChild("RequestBuy") :: RemoteEvent
local RequestUseItem = remotes:WaitForChild("RequestUseItem") :: RemoteEvent
local StatsUpdate = remotes:WaitForChild("StatsUpdate") :: RemoteEvent
local LootEvent = remotes:WaitForChild("LootEvent") :: RemoteEvent

pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)

-- Latest server stats (merged from partial updates)
local stats: { [string]: any } = {
	money = 0, speed = 0, walkSpeed = 16, income = 0, slots = Config.SLOTS_START, baseSlots = Config.SLOTS_START,
	speedMultTier = 1, treadmillTier = 1, speedMult = 1, treadmillMult = 2,
	items = {}, potions = {}, index = {}, plants = {}, passes = {}, carrying = false, reachedEnd = false,
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
	slowOn = Color3.fromRGB(255, 120, 60),
	panel = Color3.fromRGB(255, 250, 235),
	red = Color3.fromRGB(240, 70, 70),
	gold = Color3.fromRGB(255, 205, 50),
	disabled = Color3.fromRGB(170, 170, 170),
}

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

local function button(parent: Instance, label: string, color: Color3, size: UDim2, onClick: () -> ()): TextButton
	local b = new("TextButton", {
		Size = size,
		BackgroundColor3 = color,
		Text = "",
		AutoButtonColor = true,
		Parent = parent,
	}, deco(10))
	text(b, { Name = "Label", Text = label, Size = UDim2.new(1, -10, 1, -6), Position = UDim2.fromOffset(5, 3) })
	b.Activated:Connect(onClick)
	return b
end

local function setLabel(b: GuiObject, value: string)
	local label = b:FindFirstChild("Label") :: TextLabel?
	if label then
		label.Text = value
	end
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
	Size = UDim2.fromOffset(560, 300), Parent = gui,
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
-- Bottom-left: buttons, speed (+), money
----------------------------------------------------------------------------------------------------
local bottomLeft = new("Frame", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14),
	Size = UDim2.fromOffset(330, 240), Parent = gui,
})

local moneyPanel = new("Frame", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.fromOffset(330, 62),
	BackgroundColor3 = COLORS.money, Parent = bottomLeft,
}, deco(12))
local moneyLabel = text(moneyPanel, { Text = "$0", Size = UDim2.new(0.62, -10, 1, -10), Position = UDim2.fromOffset(10, 5), TextXAlignment = Enum.TextXAlignment.Left })
local incomeLabel = text(moneyPanel, { Text = "+$0/s", Size = UDim2.new(0.38, -10, 0.6, 0), Position = UDim2.new(0.62, 0, 0.2, 0),
	TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(220, 255, 210) })

local speedPanel = new("Frame", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -72), Size = UDim2.fromOffset(330, 62),
	BackgroundColor3 = COLORS.speed, Parent = bottomLeft,
}, deco(12))
local speedLabel = text(speedPanel, { Text = "⚡ 0", Size = UDim2.new(0.6, -10, 0.72, 0), Position = UDim2.fromOffset(10, 4), TextXAlignment = Enum.TextXAlignment.Left })
local walkLabel = text(speedPanel, { Text = "WalkSpeed 16", Size = UDim2.new(0.6, -10, 0.26, 0), Position = UDim2.new(0, 10, 0.72, -3),
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(215, 235, 255) })
local multLabel = text(speedPanel, { Text = "x1", Size = UDim2.new(0.18, 0, 0.5, 0), Position = UDim2.new(0.6, 0, 0.25, 0), TextColor3 = COLORS.gold })

-- "+" opens a small buy menu above the panel
local buyMenu = new("Frame", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -190), Size = UDim2.fromOffset(330, 150),
	BackgroundColor3 = COLORS.panel, Visible = false, Parent = bottomLeft,
}, {
	new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center }),
	table.unpack(deco(12)),
})
local buySmall = button(buyMenu, "", COLORS.speed, UDim2.fromOffset(310, 40), function()
	RequestBuy:FireServer("Speed25")
end)
local buyMax = button(buyMenu, "", COLORS.speed, UDim2.fromOffset(310, 40), function()
	RequestBuy:FireServer("SpeedMax")
end)
local buyMult = button(buyMenu, "", COLORS.index, UDim2.fromOffset(310, 40), function()
	RequestBuy:FireServer("SpeedMult")
end)
button(speedPanel, "+", COLORS.gold, UDim2.fromOffset(52, 52), function()
	buyMenu.Visible = not buyMenu.Visible
end).Position = UDim2.new(1, -57, 0, 5)

-- Shop / Index / Slow Mode row, between the speed panel and the buy menu
local rowButtons = new("Frame", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -134), Size = UDim2.fromOffset(330, 48),
	BackgroundTransparency = 1, Parent = bottomLeft,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }) })

local openModal: (name: string) -> ()
button(rowButtons, "🛒 Shop", COLORS.shop, UDim2.fromOffset(100, 48), function()
	openModal("Shop")
end)
button(rowButtons, "📖 Index", COLORS.index, UDim2.fromOffset(100, 48), function()
	openModal("Index")
end)

-- Slow Mode: purely local, clamps our own WalkSpeed so we can potter around the base.
local slowMode = false
local slowButton: TextButton
local function applySlow()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and slowMode and hum.WalkSpeed > Config.SLOW_MODE_WALKSPEED then
		hum.WalkSpeed = Config.SLOW_MODE_WALKSPEED
	elseif hum and not slowMode and stats.walkSpeed and hum.WalkSpeed ~= stats.walkSpeed and hum.WalkSpeed ~= 0 then
		hum.WalkSpeed = stats.walkSpeed
	end
end
slowButton = button(rowButtons, "🐢 Slow: OFF", COLORS.slow, UDim2.fromOffset(114, 48), function()
	slowMode = not slowMode
	setLabel(slowButton, if slowMode then "🐢 Slow: ON" else "🐢 Slow: OFF")
	slowButton.BackgroundColor3 = if slowMode then COLORS.slowOn else COLORS.slow
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

----------------------------------------------------------------------------------------------------
-- Bottom-right: potion timers + day/night timer
----------------------------------------------------------------------------------------------------
local bottomRight = new("Frame", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14),
	Size = UDim2.fromOffset(260, 200), Parent = gui,
}, { new("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
local potionTimers: { [string]: Frame } = {}
for _, id in { "PotionSpeed", "PotionMoney", "PotionLuck" } do
	local def = Config.POTIONS[id]
	local f = new("Frame", { Size = UDim2.fromOffset(240, 36), BackgroundColor3 = COLORS.index, Visible = false, LayoutOrder = 1, Parent = bottomRight }, deco(10))
	text(f, { Name = "Label", Text = "", Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromOffset(6, 3) })
	potionTimers[def.stat] = f
end
local dayFrame = new("Frame", { Size = UDim2.fromOffset(240, 40), BackgroundColor3 = COLORS.shop, LayoutOrder = 2, Parent = bottomRight }, deco(10))
local dayLabel = text(dayFrame, { Text = "", Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromOffset(6, 3) })

----------------------------------------------------------------------------------------------------
-- Hotbar (bottom centre): Bat + Sleep Dust
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
local function useDust()
	RequestUseItem:FireServer("SleepDust")
end
local batSlot = button(hotbar, "🏏\nBat", Color3.fromRGB(200, 140, 80), UDim2.fromOffset(84, 84), useBat)
local dustSlot = button(hotbar, "💤\nDust x0", Color3.fromRGB(120, 130, 255), UDim2.fromOffset(84, 84), useDust)
for i, slot in { batSlot, dustSlot } do
	text(slot, { Text = tostring(i), Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(4, 2), TextColor3 = COLORS.gold })
end
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
	elseif input.KeyCode == Enum.KeyCode.Two then
		useDust()
	end
end)

----------------------------------------------------------------------------------------------------
-- Right side: Seeds / Plants / Potions menus
----------------------------------------------------------------------------------------------------
local rightTabs = new("Frame", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.45, 0),
	Size = UDim2.fromOffset(70, 230), Parent = gui,
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

local function renderSeeds()
	sideTitle.Text = "🌱 Seeds"
	local c = stats.carrying
	local top = card(0, if c then COLORS.gold else COLORS.slow, 44)
	text(top, {
		Text = if c then `Carrying: {Config.RARITIES[c.rarity].id} {Config.ZONES[c.zone].seed}` else "Not carrying a seed",
		Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4),
	})
	for k, zone in Config.ZONES do
		local ok = stats.speed >= zone.req
		local f = card(k, if ok then zone.floor:Lerp(Color3.new(0, 0, 0), 0.25) else COLORS.disabled, 58)
		text(f, { Text = `{zone.icon} {zone.seed} · {zone.name}`, Size = UDim2.new(1, -12, 0.5, -2), Position = UDim2.fromOffset(6, 3), TextXAlignment = Enum.TextXAlignment.Left })
		text(f, {
			Text = `{if ok then "✅" else "🔒"} Rec. Speed {Format.short(zone.req)} · {Format.money(Config.seedIncome(k))}/s base`,
			Size = UDim2.new(1, -12, 0.45, -2), Position = UDim2.new(0, 6, 0.5, 0), TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if ok then Color3.fromRGB(230, 255, 230) else Color3.fromRGB(255, 235, 235),
		})
	end
end

local function renderPlants()
	local plants = table.clone(stats.plants or {})
	table.sort(plants, function(a, b)
		return a.income > b.income
	end)
	sideTitle.Text = `🪴 Plants {#plants}/{stats.slots} · {Format.money(stats.income)}/s`
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

local function renderPotions()
	sideTitle.Text = "🧪 Potions"
	local now = workspace:GetServerTimeNow()
	local order = 0
	for id, def in Config.POTIONS do
		order += 1
		local f = card(order, COLORS.index, 96)
		local owned = (stats.items or {})[id] or 0
		local expiry = (stats.potions or {})[def.stat]
		local active = if expiry and expiry > now then ` · active {Format.clock(expiry - now)}` else ""
		text(f, { Text = `{def.icon} {def.label} (x{def.mult} {def.stat}) — own {owned}{active}`, Size = UDim2.new(1, -12, 0, 30), Position = UDim2.fromOffset(6, 4),
			TextXAlignment = Enum.TextXAlignment.Left })
		local use = button(f, "Use", if owned > 0 then COLORS.money else COLORS.disabled, UDim2.new(0.45, -8, 0, 44), function()
			RequestUseItem:FireServer(id)
		end)
		use.Position = UDim2.new(0, 6, 0, 42)
		local price = Config.priceOf(id, stats :: any)
		local buy = button(f, `Buy {Format.money(price or 0)}`, if price and stats.money >= price then COLORS.shop else COLORS.disabled,
			UDim2.new(0.55, -8, 0, 44), function()
				RequestBuy:FireServer(id)
			end)
		buy.Position = UDim2.new(0.45, 2, 0, 42)
	end
end

renderSide = function()
	clearSide()
	if sideTab == "Seeds" then
		renderSeeds()
	elseif sideTab == "Plants" then
		renderPlants()
	elseif sideTab == "Potions" then
		renderPotions()
	end
end

for _, tab in { { "Seeds", "🌱" }, { "Plants", "🪴" }, { "Potions", "🧪" } } do
	local name = tab[1]
	button(rightTabs, tab[2], Color3.fromRGB(110, 210, 120), UDim2.fromOffset(70, 70), function()
		if sideTab == name then
			sideTab = nil
			sidePanel.Visible = false
		else
			sideTab = name
			sidePanel.Visible = true
			renderSide()
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Modals: Shop and Index
----------------------------------------------------------------------------------------------------
local modal = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(720, 500),
	BackgroundColor3 = COLORS.panel, Visible = false, Parent = gui,
}, deco(16, 4))
local modalTitle = text(modal, { Text = "", Size = UDim2.new(1, -120, 0, 44), Position = UDim2.fromOffset(16, 10), TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left })
modalTitle:FindFirstChildOfClass("UIStroke"):Destroy()
local modalBody = new("ScrollingFrame", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 64), Size = UDim2.new(1, -32, 1, -80),
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, BorderSizePixel = 0, Parent = modal,
})
local modalName: string? = nil
local renderModal: () -> ()
button(modal, "✖", COLORS.red, UDim2.fromOffset(44, 44), function()
	modal.Visible = false
	modalName = nil
end).Position = UDim2.new(1, -56, 0, 10)

openModal = function(name: string)
	if modalName == name then
		modal.Visible = false
		modalName = nil
		return
	end
	modalName = name
	modal.Visible = true
	renderModal()
end

local function clearModal(): UIGridLayout
	modalBody:ClearAllChildren()
	return new("UIGridLayout", { CellSize = UDim2.fromOffset(160, 150), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = modalBody })
end

local SHOP_ITEMS = {
	{ id = "Speed25", title = "⚡ Speed Pack", color = COLORS.speed },
	{ id = "SpeedMax", title = "⚡ Max Speed", color = COLORS.speed },
	{ id = "SpeedMult", title = "🚀 Speed Gain", color = COLORS.index },
	{ id = "Treadmill", title = "🏃 Treadmill", color = Color3.fromRGB(240, 90, 90) },
	{ id = "Slot", title = "🪴 Plant Slot", color = COLORS.money },
	{ id = "SleepDust", title = "💤 Sleep Dust", color = Color3.fromRGB(120, 130, 255) },
	{ id = "PotionSpeed", title = "⚡ Speed Potion", color = COLORS.index },
	{ id = "PotionMoney", title = "💰 Money Potion", color = COLORS.index },
	{ id = "PotionLuck", title = "🍀 Luck Potion", color = COLORS.index },
	{ id = "Pass:DoubleMoney", title = "💎 2x Money", color = Color3.fromRGB(0, 180, 200) },
	{ id = "Pass:ExtraSlots", title = "💎 +10 Slots", color = Color3.fromRGB(0, 180, 200) },
}

local function renderShop()
	modalTitle.Text = "🛒 Shop"
	clearModal()
	for i, item in SHOP_ITEMS do
		local f = new("Frame", { BackgroundColor3 = item.color, LayoutOrder = i, Parent = modalBody }, deco(12))
		text(f, { Text = item.title, Size = UDim2.new(1, -12, 0, 32), Position = UDim2.fromOffset(6, 6) })
		local price, label
		local owned = false
		if string.sub(item.id, 1, 5) == "Pass:" then
			local pass = (Config.GAMEPASSES :: any)[string.sub(item.id, 6)]
			label = pass.label
			owned = stats.passes[string.sub(item.id, 6)] == true
		else
			price, label = Config.priceOf(item.id, stats :: any)
		end
		local extra = ""
		if item.id == "SleepDust" then
			extra = ` (own {(stats.items or {}).SleepDust or 0})`
		elseif item.id == "Slot" then
			extra = ` ({stats.slots} now)`
		end
		text(f, { Text = (label or "") .. extra, Size = UDim2.new(1, -12, 0, 44), Position = UDim2.fromOffset(6, 40), TextColor3 = Color3.fromRGB(255, 255, 220) })
		local affordable = price ~= nil and stats.money >= price
		local caption = if owned then "Owned" elseif string.sub(item.id, 1, 5) == "Pass:" then "Robux" elseif price then Format.money(price) else "Maxed"
		local b = button(f, caption, if affordable or (string.sub(item.id, 1, 5) == "Pass:" and not owned) then COLORS.gold else COLORS.disabled,
			UDim2.new(1, -16, 0, 44), function()
				RequestBuy:FireServer(item.id)
			end)
		b.Position = UDim2.new(0, 8, 1, -52)
	end
end

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
	modalTitle.Text = `📖 Index · {found}/{total} discovered`
	modalBody:ClearAllChildren()
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = modalBody })
	for k, zone in Config.ZONES do
		local row = new("Frame", { Size = UDim2.new(1, -8, 0, 96), BackgroundColor3 = zone.floor:Lerp(Color3.new(0, 0, 0), 0.3), LayoutOrder = k, Parent = modalBody }, deco(12))
		local mutText = ""
		for _, m in Config.MUTATIONS do
			if stats.index[`{k}:{m.id}`] then
				mutText ..= " " .. m.id
			end
		end
		text(row, { Text = `{zone.icon} {zone.seed}{if mutText ~= "" then " ✨" .. mutText else ""}`, Size = UDim2.new(1, -12, 0, 28), Position = UDim2.fromOffset(6, 4), TextXAlignment = Enum.TextXAlignment.Left })
		local cells = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 36), Size = UDim2.new(1, -12, 0, 52), Parent = row },
			{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })
		for r, rarity in Config.RARITIES do
			local got = stats.index[`{k}:{r}`] == true
			local cell = new("Frame", { Size = UDim2.new(0.2, -6, 1, 0), BackgroundColor3 = if got then rarity.color else Color3.fromRGB(70, 70, 80), LayoutOrder = r, Parent = cells }, deco(8, 2))
			text(cell, { Text = if got then rarity.id else "???", Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3) })
		end
	end
end

renderModal = function()
	if modalName == "Shop" then
		renderShop()
	elseif modalName == "Index" then
		renderIndex()
	end
end

----------------------------------------------------------------------------------------------------
-- Refresh from stats
----------------------------------------------------------------------------------------------------
local lastUnlocked = -1
local function refresh(changed: { [string]: any })
	moneyLabel.Text = Format.money(stats.money)
	incomeLabel.Text = "+" .. Format.money(stats.income) .. "/s"
	speedLabel.Text = "⚡ " .. Format.short(stats.speed)
	walkLabel.Text = `WalkSpeed {math.floor(stats.walkSpeed)}`
	multLabel.Text = `x{stats.speedMult or 1}`

	local p1, l1 = Config.priceOf("Speed25", stats :: any)
	setLabel(buySmall, `{l1} · {Format.money(p1 or 0)}`)
	local amount = math.floor(stats.money / Config.PRICE_PER_SPEED)
	setLabel(buyMax, `Max: +{Format.short(amount)} Speed · {Format.money(amount * Config.PRICE_PER_SPEED)}`)
	local p3, l3 = Config.priceOf("SpeedMult", stats :: any)
	setLabel(buyMult, if p3 then `{l3} · {Format.money(p3)}` else "Speed Gain maxed!")
	buySmall.BackgroundColor3 = if p1 and stats.money >= p1 then COLORS.speed else COLORS.disabled
	buyMax.BackgroundColor3 = if amount >= 1 then COLORS.speed else COLORS.disabled
	buyMult.BackgroundColor3 = if p3 and stats.money >= p3 then COLORS.index else COLORS.disabled

	setLabel(dustSlot, `💤\nDust x{(stats.items or {}).SleepDust or 0}`)

	local c = stats.carrying
	carryBanner.Visible = c ~= false and c ~= nil
	if c then
		carryLabel.Text = `🌱 {if c.mutation then c.mutation .. " " else ""}{Config.RARITIES[c.rarity].id} {Config.ZONES[c.zone].seed} — run home & plant it!`
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
	if sidePanel.Visible and (changed.plants or changed.carrying or changed.items or changed.potions or sideTab == "Seeds" and unlockChanged) then
		renderSide()
	end
	if modal.Visible and (changed.index or changed.items or changed.slots or changed.speedMultTier or changed.treadmillTier or changed.passes or changed.money) then
		renderModal()
	end
end

local lastModalRender = 0
StatsUpdate.OnClientEvent:Connect(function(partial: { [string]: any })
	for k, v in partial do
		stats[k] = v
	end
	-- Money ticks constantly; throttle modal re-renders to twice a second.
	if partial.money and modal.Visible and os.clock() - lastModalRender < 0.5 then
		partial.money = nil
	elseif modal.Visible then
		lastModalRender = os.clock()
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
	elseif kind == "Dusted" then
		toast(`💤 The {data.guard} will sleep {data.seconds}s longer on the next steal.`, "blue")
	elseif kind == "Potion" then
		toast(`🧪 {data.label} active!`, "blue")
	elseif kind == "Offline" then
		toast(`While you were away ({Format.clock(data.seconds)}): +{Format.money(data.amount)}`, "gold", 6)
	elseif kind == "End" then
		toast("⛩️ YOU REACHED THE END OF THE LINE! ⛩️", "gold", 8)
	elseif kind == "DayNight" then
		toast(if data.night then "🌙 Night falls: rarer seeds and Night mutations!" else "☀️ The sun is up.", "blue", 4)
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

	if os.clock() - lastTimerUpdate >= 0.25 then
		lastTimerUpdate = os.clock()
		local now = workspace:GetServerTimeNow()
		local night, remaining = Config.dayPhase(now)
		dayLabel.Text = if night then `🌙 Night · Day in {Format.clock(remaining)}` else `☀️ Day · Night in {Format.clock(remaining)}`
		dayFrame.BackgroundColor3 = if night then Color3.fromRGB(70, 70, 160) else COLORS.shop
		for _, def in Config.POTIONS do
			local f = potionTimers[def.stat]
			local expiry = (stats.potions or {})[def.stat]
			local active = expiry ~= nil and expiry > now
			f.Visible = active
			if active then
				setLabel(f, `{def.icon} {def.stat} x{def.mult} · {Format.clock(expiry - now)}`)
			end
		end
	end
end)

rescale()
gui.Parent = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end
