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
	slowOn = Color3.fromRGB(255, 120, 60),
	panel = Color3.fromRGB(255, 250, 235),
	red = Color3.fromRGB(240, 70, 70),
	gold = Color3.fromRGB(255, 205, 50),
	disabled = Color3.fromRGB(170, 170, 170),
	buy = Color3.fromRGB(60, 200, 80), -- green: money and R$ buy buttons
	robux = Color3.fromRGB(150, 80, 230), -- purple: R$ on trail cards, the gift button
	equip = Color3.fromRGB(60, 160, 255),
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

-- The 🏃 button opens the Trail Shop (trails multiply the Speed you gain; money can't buy Speed itself)
local openModal: (name: string) -> ()
button(speedPanel, "🏃", COLORS.index, UDim2.fromOffset(52, 52), function()
	openModal("Trails")
end).Position = UDim2.new(1, -57, 0, 5)

-- Shop / Index / Slow Mode row, above the speed panel
local rowButtons = new("Frame", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -134), Size = UDim2.fromOffset(330, 48),
	BackgroundTransparency = 1, Parent = bottomLeft,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }) })

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
-- Bottom-right: day/night timer
----------------------------------------------------------------------------------------------------
local bottomRight = new("Frame", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14),
	Size = UDim2.fromOffset(260, 200), Parent = gui,
}, { new("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
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
	sideTitle.Text = `🌱 Seeds · 🎒 {SeedPacks.bagCount(stats.seedBag or {})}/{Config.SEED_BAG_MAX}`
	local c = stats.carrying
	local top = card(0, if c then COLORS.gold else COLORS.slow, 44)
	text(top, {
		Text = if c then `Carrying: {Config.RARITIES[c.rarity].id} {Config.ZONES[c.zone].seed}` else "Not carrying a seed",
		Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4),
	})

	-- Seed bag (from seed packs): plant at your pad
	local bag = bagEntries()
	local hint = card(1, COLORS.index, 40)
	text(hint, {
		Text = if #bag == 0 then "🎁 Buy seed packs in the 🛒 Shop: their seeds land here!" else "🎒 Your bag: stand on your plot's pad, then Plant.",
		Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4),
	})
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
		end).Position = UDim2.new(1, -90, 0, 7)
	end

	for k, zone in Config.ZONES do
		local ok = stats.speed >= zone.req
		local f = card(100 + k, if ok then zone.ui else COLORS.disabled, 58)
		text(f, { Text = `{zone.icon} {zone.seed} · {zone.name} {Config.ACTIVE_ICONS[zone.active]}`, Size = UDim2.new(1, -12, 0.5, -2), Position = UDim2.fromOffset(6, 3), TextXAlignment = Enum.TextXAlignment.Left })
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

renderSide = function()
	clearSide()
	if sideTab == "Seeds" then
		renderSeeds()
	elseif sideTab == "Plants" then
		renderPlants()
	end
end

for _, tab in { { "Seeds", "🌱" }, { "Plants", "🪴" } } do
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
-- Modals: Shop, Trail Shop and Index
----------------------------------------------------------------------------------------------------
local modal = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(780, 560),
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
local trailScrollX = 0 -- the Trail Shop strip's scroll: money ticks re-render the modal, the strip stays put
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
	modalBody.CanvasPosition = Vector2.zero
	trailScrollX = 0
	renderModal()
end

-- Walk-up stalls in the base's shop plaza: their prompts say which menu to open ("Shop", "Trails" or
-- "Index"). Always opens (never toggles shut).
game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt: ProximityPrompt)
	local opens = prompt:GetAttribute("OpensShop")
	if (opens == "Shop" or opens == "Trails" or opens == "Index") and modalName ~= opens then
		openModal(opens)
	end
end)

-- A vertical list in the modal body.
local function clearModal(padding: number?)
	modalBody:ClearAllChildren()
	new("UIListLayout", {
		Padding = UDim.new(0, padding or 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = modalBody,
	})
end

-- Dark text line inside the modal body
local function heading(label: string, order: number, centered: boolean?, height: number?)
	local h = text(modalBody, {
		Text = label, Size = UDim2.new(1, -12, 0, height or 30), TextColor3 = INK, LayoutOrder = order, TextWrapped = true,
		TextXAlignment = if centered then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
	})
	local stroke = h:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke:Destroy()
	end
end

-- "-- SPEED --" style section title
local function section(label: string, order: number)
	heading(`-- {label} --`, order, true, 36)
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

-- "R$ 64", or "R$ 64 soon" while the product has no id yet (the server answers "coming soon").
local function robuxCaption(product: Config.DevProduct): string
	if product.id == 0 then
		return `{Format.robux(product.robux)} soon`
	end
	return Format.robux(robuxPrice(product))
end

local function giftButton(parent: Instance): TextButton
	-- Gifting needs extra work (choosing a player, granting to them): shown, but not live yet.
	return button(parent, "🎁", COLORS.robux, UDim2.fromOffset(46, 44), function()
		toast("🎁 Gifting is coming soon!", "blue")
	end)
end

----------------------------------------------------------------------------------------------------
-- Shop: seed packs (premium cards with loot tables showing the exact server odds), then every other
-- Robux item as a card with a green R$ button, plus the money plot upgrade
----------------------------------------------------------------------------------------------------
local packShines: { Frame } = {} -- swept across the premium cards every frame while they're shown

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
		table.insert(parts, `{icon} {m.id} {SeedPacks.percent(m.pct)}`)
	end
	return table.concat(parts, "  ·  ")
end

-- One big premium card per pack: zone colours, a gold frame, a sweeping shine, the loot table with
-- the exact odds and the R$ button. No Speed gate: anyone can buy them.
local function packCard(parent: Instance, order: number, productName: string, product: Config.DevProduct, bagFull: boolean)
	local pack = SeedPacks.packForProduct(product)
	local zone = Config.ZONES[pack.zone]
	local c = new("Frame", {
		Size = UDim2.new(0.5, -6, 1, 0), BackgroundColor3 = WHITE, ClipsDescendants = true, LayoutOrder = order, Parent = parent,
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
	text(band, { Text = "💎 PREMIUM · LATE-GAME SEED", Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromOffset(6, 3) })
	text(c, { Text = zone.icon, Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(12, 36) })
	text(c, { Text = pack.name, Size = UDim2.new(1, -94, 0, 34), Position = UDim2.fromOffset(82, 38), TextXAlignment = Enum.TextXAlignment.Left })
	text(c, {
		Text = `{zone.name} seed · no Speed needed`, Size = UDim2.new(1, -94, 0, 22), Position = UDim2.fromOffset(82, 74),
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 245, 210),
	})
	lootTable(c, pack, UDim2.fromOffset(12, 106), UDim2.new(1, -24, 0, 140))
	text(c, { Text = mutationLine(pack), Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 252), TextColor3 = Color3.fromRGB(255, 240, 180) })
	local exclusive = Config.mutationById(pack.exclusive)
	text(c, {
		Text = `💰 {Format.money(Config.seedIncome(pack.zone))}/s per Common sprout`
			.. (if exclusive then ` · 🌟 {exclusive.id} x{exclusive.income} income, only from packs` else ""),
		Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, 280), TextWrapped = true, TextColor3 = Color3.fromRGB(255, 255, 230),
	})
	-- Robux only. With id = 0 the server answers "coming soon"; with a full bag it won't prompt.
	local live = product.id ~= 0
	local price = robuxCaption(product)
	local caption = if not live then `Coming soon · {Format.robux(product.robux)}` elseif bagFull then `🎒 Bag full · {price}` else `Buy · {price}`
	button(c, caption, if live and not bagFull then COLORS.buy else COLORS.disabled, UDim2.new(1, -82, 0, 58), function()
		RequestBuy:FireServer("Product:" .. productName)
	end).Position = UDim2.new(0, 12, 1, -70)
	local gift = giftButton(c)
	gift.Size = UDim2.fromOffset(58, 58)
	gift.Position = UDim2.new(1, -70, 1, -70)
end

-- A grid of shop cards (4 per row), auto-sized to its contents.
local function cardGrid(order: number): Frame
	return new("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -12, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = modalBody,
	}, {
		new("UIGridLayout", {
			CellSize = UDim2.fromOffset(176, 168), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	})
end

-- A shop card: big title, a smaller line, and the buy button (+ the gift button for Robux items).
local function shopCard(grid: Instance, order: number, color: Color3, title: string, sub: string): Frame
	local c = new("Frame", { BackgroundColor3 = color, LayoutOrder = order, Parent = grid }, deco(12))
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(190, 190, 190)), Parent = c })
	text(c, { Text = title, Size = UDim2.new(1, -12, 0, 46), Position = UDim2.fromOffset(6, 8) })
	text(c, { Text = sub, Size = UDim2.new(1, -12, 0, 44), Position = UDim2.fromOffset(6, 58), TextColor3 = Color3.fromRGB(255, 255, 225), TextWrapped = true })
	return c
end

-- A Robux card for developer product `name`; `owned` replaces the price (e.g. a treadmill tier you have).
local function productCard(grid: Instance, order: number, name: string, product: Config.DevProduct, color: Color3, title: string, sub: string, owned: string?)
	local c = shopCard(grid, order, color, title, sub)
	button(c, owned or robuxCaption(product), if owned or product.id == 0 then COLORS.disabled else COLORS.buy, UDim2.new(1, -66, 0, 44), function()
		RequestBuy:FireServer("Product:" .. name)
	end).Position = UDim2.new(0, 8, 1, -52)
	giftButton(c).Position = UDim2.new(1, -54, 1, -52)
end

local function renderShop()
	modalTitle.Text = "🛒 Shop"
	clearModal(8)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- Seed packs (Robux)
	section("SEED PACKS", nextOrder())
	local bagCount = SeedPacks.bagCount(stats.seedBag or {})
	local bagFull = bagCount >= Config.SEED_BAG_MAX
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -12, 0, 400), LayoutOrder = nextOrder(), Parent = modalBody },
		{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }) })
	for i, entry in Config.products("Pack") do
		packCard(row, i, entry.name, entry.product, bagFull)
	end
	heading(`🎒 Seed bag {bagCount}/{Config.SEED_BAG_MAX}{if bagFull then " (full: plant some first!)" else ""} · plant bagged seeds from the 🌱 Seeds menu at your plot's pad`, nextOrder())

	-- Plot upgrade (money; also on the board at your plot's gate)
	section("PLOT UPGRADE", nextOrder())
	local plotGrid = cardGrid(nextOrder())
	local level = stats.plotLevel or 1
	local price = Config.priceOf("PlotUpgrade", stats :: any)
	local plotCard = shopCard(plotGrid, 1, Color3.fromRGB(90, 190, 90),
		if price then `🏡 Level {level} → {level + 1}` else `🏡 Level {level} · MAX`,
		if price then `+1 slot · cash x{Config.plotMoneyMult(level)} → x{Config.plotMoneyMult(level + 1)}` else `{Config.plotSlots(level)} slots · cash x{Config.plotMoneyMult(level)}`)
	button(plotCard, if price then Format.money(price) else "Maxed", if price and stats.money >= price then COLORS.buy else COLORS.disabled,
		UDim2.new(1, -16, 0, 44), function()
			RequestBuy:FireServer("PlotUpgrade")
		end).Position = UDim2.new(0, 8, 1, -52)

	-- Speed (Robux)
	section("SPEED", nextOrder())
	local grid = cardGrid(nextOrder())
	for i, entry in Config.products("Speed") do
		productCard(grid, i, entry.name, entry.product, COLORS.speed, `⚡ {entry.product.label}`, "Added to your Speed right away")
	end

	-- Money (Robux): the card shows what you'd get right now (fixed, or minutes of your income)
	section("MONEY", nextOrder())
	grid = cardGrid(nextOrder())
	for i, entry in Config.products("Money") do
		local amount = Config.moneyPackAmount(entry.product, stats.income or 0)
		productCard(grid, i, entry.name, entry.product, COLORS.money, `💰 {Format.money(amount)}`,
			`{entry.product.label} · at least {entry.product.minutes} min of income`)
	end

	-- Treadmill (Robux)
	section("TREADMILL", nextOrder())
	grid = cardGrid(nextOrder())
	for i, entry in Config.products("Treadmill") do
		local tier = entry.product.tier :: number
		local owned = (stats.treadmillTier or 1) >= tier
		productCard(grid, i, entry.name, entry.product, Color3.fromRGB(240, 90, 90), `🏃 Treadmill x{Config.TREADMILL_TIERS[tier].mult}`,
			`Your treadmill: x{Config.TREADMILL_TIERS[stats.treadmillTier or 1].mult}`, if owned then "Owned" else nil)
	end

	-- Items (Robux)
	section("ITEMS", nextOrder())
	grid = cardGrid(nextOrder())
	for i, entry in Config.products("Dust") do
		productCard(grid, i, entry.name, entry.product, Color3.fromRGB(120, 130, 255), `💤 {entry.product.label}`,
			`You have {(stats.items or {}).SleepDust or 0} · press 2 near a sleeping guard`)
	end

	-- Gamepasses (Robux)
	section("PASSES", nextOrder())
	grid = cardGrid(nextOrder())
	for i, name in { "DoubleMoney", "ExtraSlots" } do
		local pass = Config.GAMEPASSES[name]
		local owned = stats.passes[name] == true
		local c = shopCard(grid, i, Color3.fromRGB(0, 180, 200), `💎 {pass.label}`, if name == "DoubleMoney" then "Doubles all plant income" else "On top of your plot level's slots")
		button(c, if owned then "Owned" else "Buy · R$", if owned or pass.id == 0 then COLORS.disabled else COLORS.buy, UDim2.new(1, -66, 0, 44), function()
			RequestBuy:FireServer("Pass:" .. name)
		end).Position = UDim2.new(0, 8, 1, -52)
		giftButton(c).Position = UDim2.new(1, -54, 1, -52)
	end
end

----------------------------------------------------------------------------------------------------
-- Trail Shop: one card per trail, scrolling sideways, in the trail's colour. Money ($) or Robux (R$),
-- or Equip / Equipped once owned.
----------------------------------------------------------------------------------------------------
local function trailFill(f: GuiObject, t: Config.Trail)
	if t.rainbow then
		f.BackgroundColor3 = WHITE
		new("UIGradient", { Rotation = 25, Color = Config.trailColors(t), Parent = f })
	else
		f.BackgroundColor3 = t.color
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(150, 150, 150)), Parent = f })
	end
end

local function trailCard(parent: Instance, order: number, t: Config.Trail)
	local owned = stats.trails[t.id] == true
	local equipped = stats.equippedTrail == t.id
	local c = new("Frame", { Size = UDim2.fromOffset(200, 360), LayoutOrder = order, Parent = parent }, deco(16, if equipped then 5 else 3))
	trailFill(c, t)
	if equipped then
		local stroke = c:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = COLORS.gold
		end
	end
	text(c, { Text = string.upper(t.rarity), Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 10), TextColor3 = Color3.fromRGB(255, 250, 220) })
	text(c, { Text = t.name, Size = UDim2.new(1, -16, 0, 44), Position = UDim2.fromOffset(8, 38) })
	-- A ribbon preview: the trail's colours fading out
	local ribbon = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96), Size = UDim2.new(1, -36, 0, 34), BackgroundColor3 = WHITE,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }), new("UIStroke", { Thickness = 2, Color = INK }) })
	new("UIGradient", {
		Color = Config.trailColors(t),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.7) }),
		Parent = ribbon,
	})
	ribbon.Parent = c
	text(c, { Text = `x{t.mult} Speed`, Size = UDim2.new(1, -16, 0, 50), Position = UDim2.fromOffset(8, 146), TextColor3 = COLORS.gold })
	text(c, { Text = "on Speed you gain walking and on the treadmill", Size = UDim2.new(1, -16, 0, 36), Position = UDim2.fromOffset(8, 198), TextWrapped = true })

	if owned then
		local b = button(c, if equipped then "Equipped" else "Equip", if equipped then COLORS.disabled else COLORS.equip, UDim2.new(1, -20, 0, 50), function()
			if not equipped then
				RequestUseItem:FireServer("Equip:" .. t.id)
			end
		end)
		b.Position = UDim2.new(0, 10, 1, -64)
		return
	end
	local affordable = stats.money >= t.price
	button(c, Format.money(t.price), if affordable then COLORS.buy else COLORS.disabled, UDim2.new(1, -20, 0, 50), function()
		RequestBuy:FireServer("Trail:" .. t.id)
	end).Position = UDim2.new(0, 10, 1, -120)
	local product = t.product and Config.DEVELOPER_PRODUCTS[t.product]
	if product then
		button(c, robuxCaption(product), if product.id == 0 then COLORS.disabled else COLORS.robux, UDim2.new(1, -20, 0, 50), function()
			RequestBuy:FireServer("Product:" .. (t.product :: string))
		end).Position = UDim2.new(0, 10, 1, -64)
	end
end

local function renderTrails()
	local current = Config.trailById(stats.equippedTrail) or Config.TRAILS[1]
	modalTitle.Text = "🏃 Trail Shop"
	clearModal(10)
	heading(`Trails multiply the Speed you gain. Equipped: {current.name} (x{current.mult}). Any trail can be bought directly.`, 1, false, 44)
	local strip = new("ScrollingFrame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -12, 0, 390), LayoutOrder = 2, BorderSizePixel = 0,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 8, Parent = modalBody,
	}, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
		new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	})
	for i, t in Config.TRAILS do
		trailCard(strip, i, t)
	end
	task.defer(function() -- once the layout has sized the canvas
		strip.CanvasPosition = Vector2.new(trailScrollX, 0)
		strip:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			trailScrollX = strip.CanvasPosition.X
		end)
	end)
	heading("Your trail streams behind you for everyone to see. Money can't buy Speed itself: walk, run the treadmill, or grab a Speed pack in the 🛒 Shop.", 3, false, 44)
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
		local row = new("Frame", { Size = UDim2.new(1, -8, 0, 96), BackgroundColor3 = zone.ui, LayoutOrder = k, Parent = modalBody }, deco(12))
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
	table.clear(packShines) -- renderShop adds the current pack cards' shines back
	if modalName == "Shop" then
		renderShop()
	elseif modalName == "Trails" then
		renderTrails()
	elseif modalName == "Index" then
		renderIndex()
	end
end

----------------------------------------------------------------------------------------------------
-- Pack reveal: a reel of candidate seeds spins, lands on the server's result, then a burst in the
-- result's rarity colour. The result was decided (and bagged) on the server before this plays.
----------------------------------------------------------------------------------------------------
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
		text(f, { Text = "✨" .. mut.id, Size = UDim2.new(1, -8, 0.18, 0), Position = UDim2.new(0, 4, 0.78, 0) })
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
	resultSub.Text = `{if exclusive then "🌟 PACK EXCLUSIVE! " else ""}{Config.ZONES[best.zone].icon} {SeedPacks.seedName(best.zone, best.rarity, best.mutation)} → your 🌱 Seeds bag`
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
local function queueReveal(data: any)
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

----------------------------------------------------------------------------------------------------
-- Refresh from stats
----------------------------------------------------------------------------------------------------
local lastUnlocked = -1
local function refresh(changed: { [string]: any })
	moneyLabel.Text = Format.money(stats.money)
	incomeLabel.Text = "+" .. Format.money(stats.income) .. "/s"
	speedLabel.Text = "⚡ " .. Format.short(stats.speed)
	walkLabel.Text = `WalkSpeed {math.floor(stats.walkSpeed)}`
	local trail = Config.trailById(stats.equippedTrail)
	multLabel.Text = `x{stats.speedMult or 1}`
	multLabel.TextColor3 = if trail and not trail.rainbow then trail.color:Lerp(WHITE, 0.3) else COLORS.gold

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
	if sidePanel.Visible and (changed.plants or changed.carrying or changed.items or changed.seedBag or sideTab == "Seeds" and unlockChanged) then
		renderSide()
	end
	if modal.Visible and (changed.index or changed.items or changed.slots or changed.plotLevel or changed.trails or changed.equippedTrail
		or changed.treadmillTier or changed.passes or changed.money or changed.seedBag) then
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
local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end
