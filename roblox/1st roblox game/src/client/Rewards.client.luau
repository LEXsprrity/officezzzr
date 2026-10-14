-- Community rewards UI (TODO 6, docs/references/06-*.png), kept out of HUD.client (near Luau's 200-locals
-- limit) but drawn in the same window style, inside the HUD's ScreenGui so it shares its scale and the
-- toasts show above it:
--   * the gift box by the free chest (GiftBox, server): its prompt (attribute FreeGift) opens the window;
--   * the "Free Gift!" window: a cyan title bar, the Speed bag, "~ LIMITED TIME! ~ 10,000 SPEED!", three
--     steps (like, favourite, join the community) and the CLAIM! button. Only the community membership is
--     checked, on the server (RewardService); the like and the favourite are friendly asks;
--   * the free chest's countdown and prompt text (the cooldown is per player, so each client writes its
--     own copy of the chest's labels).
local AvatarEditorService = game:GetService("AvatarEditorService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Icons = require(Shared:WaitForChild("Icons"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local ClaimReward = remotes:WaitForChild("ClaimReward") :: RemoteEvent
local StatsUpdate = remotes:WaitForChild("StatsUpdate") :: RemoteEvent
local LootEvent = remotes:WaitForChild("LootEvent") :: RemoteEvent

local groupReady = Config.COMMUNITY_GROUP_ID > 0
local state = { freeGift = false, chestAt = 0 }

----------------------------------------------------------------------------------------------------
-- The HUD's look (see HUD.client: "Tiny UI kit" and "Modals")
----------------------------------------------------------------------------------------------------
local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(25, 25, 35)
local FRAME_INK = Color3.fromRGB(16, 18, 26)
local BODY_COLOR = Color3.fromRGB(100, 210, 250) -- a bright cyan body under the cyan title bar
local NOTE_COLOR = Color3.fromRGB(215, 222, 240)
local GREEN = Color3.fromRGB(60, 200, 80)
local GREY = Color3.fromRGB(150, 152, 160)
local W, H, TITLE_H = 760, 580, 84

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

-- Outlined text (`stroke` thick), like the HUD's `bold`.
local function bold(parent: Instance, stroke: number, props: { [string]: any }): TextLabel
	local label = new("TextLabel", { BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextColor3 = WHITE, Parent = parent }, {
		new("UIStroke", { Thickness = stroke, Color = INK }),
	})
	for k, v in props do
		(label :: any)[k] = v
	end
	return label
end

-- An uploaded icon as an image, or its emoji as text while it isn't uploaded.
local function iconLabel(parent: Instance, key: string, emoji: string, props: { [string]: any }): GuiObject
	local image = Icons.image(key)
	local g: GuiObject = if image
		then new("ImageLabel", { BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Fit, Parent = parent })
		else bold(parent, 2, { Text = emoji })
	for k, v in props do
		(g :: any)[k] = v
	end
	return g
end

local function chunky(parent: Instance, label: string, color: Color3, size: UDim2, pos: UDim2, onClick: () -> ()): TextButton
	local b = new("TextButton", { Size = size, Position = pos, BackgroundColor3 = color, Text = "", AutoButtonColor = true, ZIndex = 3, Parent = parent }, deco(10, 3))
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(200, 200, 200)), Parent = b })
	bold(b, 3, { Name = "Label", Text = label, Size = UDim2.new(1, -12, 1, -10), Position = UDim2.fromOffset(6, 5), ZIndex = 3 })
	b.Activated:Connect(onClick)
	return b
end

local function gradientText(label: TextLabel, a: Color3, b: Color3, rotation: number)
	new("UIGradient", { Rotation = rotation, Color = ColorSequence.new(a, b), Parent = label })
end

local hud = player:WaitForChild("PlayerGui"):WaitForChild("SeedHUD")
local hudScale = hud:FindFirstChildOfClass("UIScale")
local clickSound = new("Sound", { SoundId = Config.SOUNDS.Click, Volume = 0.5, Parent = SoundService })
local rewardSound = new("Sound", { SoundId = Config.SOUNDS.Buy, Volume = 0.7, Parent = SoundService })

----------------------------------------------------------------------------------------------------
-- The "Free Gift!" window
----------------------------------------------------------------------------------------------------
local window = new("Frame", {
	Name = "FreeGift", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H),
	BackgroundColor3 = BODY_COLOR, Active = true, Visible = false, ZIndex = 11, Parent = hud, -- above the HUD's windows, under its toasts
}, {
	new("UICorner", { CornerRadius = UDim.new(0, 18) }),
	new("UIStroke", { Thickness = 6, Color = FRAME_INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(215, 218, 232)) }),
})
local windowScale = new("UIScale", { Parent = window })

-- Faint studs over the body
local studs = new("Frame", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(0, TITLE_H), Size = UDim2.new(1, 0, 1, -TITLE_H), ClipsDescendants = true, Parent = window,
}, {
	new("UIGridLayout", { CellSize = UDim2.fromOffset(20, 20), CellPadding = UDim2.fromOffset(16, 16) }),
	new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingTop = UDim.new(0, 16) }),
})
for _ = 1, math.ceil(W / 36) * math.ceil((H - TITLE_H) / 36) do
	new("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.955, Parent = studs }, { new("UICorner", { CornerRadius = UDim.new(0, 5) }) })
end

-- Cyan title bar: square bottom corners, light diagonal stripes, a shine, the dark line under it
local CYAN_FROM, CYAN_TO = Color3.fromRGB(70, 235, 255), Color3.fromRGB(30, 160, 245)
local titleBar = new("Frame", { Size = UDim2.new(1, 0, 0, TITLE_H), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2, Parent = window }, {
	new("UICorner", { CornerRadius = UDim.new(0, 18) }),
	new("UIGradient", { Color = ColorSequence.new(CYAN_FROM, CYAN_TO) }),
})
new("Frame", { Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 1, Parent = titleBar }, {
	new("UIGradient", { Color = ColorSequence.new(CYAN_FROM, CYAN_TO) }),
})
local stripeKeys = { NumberSequenceKeypoint.new(0, 1) }
for _, band in { { 0.53, 0.565 }, { 0.585, 0.6 }, { 0.625, 0.67 } } do
	table.insert(stripeKeys, NumberSequenceKeypoint.new(band[1] - 0.001, 1))
	table.insert(stripeKeys, NumberSequenceKeypoint.new(band[1], 0.75))
	table.insert(stripeKeys, NumberSequenceKeypoint.new(band[2], 0.75))
	table.insert(stripeKeys, NumberSequenceKeypoint.new(band[2] + 0.001, 1))
end
table.insert(stripeKeys, NumberSequenceKeypoint.new(1, 1))
local stripeClip = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ClipsDescendants = true, ZIndex = 2, Parent = titleBar })
new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(W, W), BackgroundColor3 = WHITE, BorderSizePixel = 0,
	Parent = stripeClip,
}, { new("UIGradient", { Rotation = 45, Transparency = NumberSequence.new(stripeKeys) }) })
new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2, Parent = titleBar }, {
	new("UICorner", { CornerRadius = UDim.new(0, 18) }),
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 1),
	}) }),
})
new("Frame", { Position = UDim2.fromOffset(0, TITLE_H - 3), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = FRAME_INK, BorderSizePixel = 0, ZIndex = 3, Parent = window })
bold(titleBar, 5, { Text = "Free Gift!", Size = UDim2.new(1, -200, 0, 60), Position = UDim2.fromOffset(22, 10), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })

-- The red square X
local close = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, -1), Size = UDim2.fromOffset(64, 64), BackgroundColor3 = WHITE,
	Text = "", AutoButtonColor = true, ZIndex = 3, Parent = titleBar,
}, deco(10, 4))
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 85, 85), Color3.fromRGB(200, 20, 35)), Parent = close })
local closeImage = Icons.image("Close")
if closeImage then
	new("ImageLabel", {
		BackgroundTransparency = 1, Image = closeImage, ScaleType = Enum.ScaleType.Fit, Size = UDim2.new(1, -10, 1, -10), Position = UDim2.fromOffset(5, 5),
		ZIndex = 3, Parent = close,
	})
else
	bold(close, 4, { Text = "X", Size = UDim2.new(1, -16, 1, -14), Position = UDim2.fromOffset(8, 7), ZIndex = 3 })
end

-- One line of help under the title bar (what to do next, what happened)
local hint = bold(window, 2, {
	Text = "", Size = UDim2.new(1, -48, 0, 26), Position = UDim2.fromOffset(24, TITLE_H + 12), TextColor3 = NOTE_COLOR, ZIndex = 3,
})
local function setHint(text: string)
	hint.Text = text
end

-- The Speed bag, like the reference's sack of shoes: light rays, a blue sack with a tied neck, the Speed
-- icon on it and more Speed spilling out of the top.
local art = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(280, 230), Position = UDim2.fromOffset(28, TITLE_H + 44), ZIndex = 2, Parent = window })
for i = 0, 5 do
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.fromOffset(300, 22), Rotation = i * 30,
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.88, BorderSizePixel = 0, ZIndex = 2, Parent = art,
	}, { new("UIGradient", { Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
	}) }) })
end
for i, spill in { { x = 0.33, r = -25 }, { x = 0.5, r = 8 }, { x = 0.67, r = 30 } } do
	iconLabel(art, "Speed", "⚡", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(spill.x, if i == 2 then 0.14 else 0.2), Size = UDim2.fromOffset(70, 70), Rotation = spill.r, ZIndex = 3,
	})
end
local sack = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(200, 150), BackgroundColor3 = WHITE, ZIndex = 4, Parent = art,
}, {
	new("UICorner", { CornerRadius = UDim.new(0, 64) }),
	new("UIStroke", { Thickness = 5, Color = INK }),
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(110, 200, 255), Color3.fromRGB(25, 95, 220)) }),
})
new("Frame", { -- the white swoosh across the sack
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.new(1, -10, 0, 26), Rotation = -8,
	BackgroundColor3 = WHITE, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 4, Parent = sack,
}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
iconLabel(sack, "Speed", "⚡", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56), Size = UDim2.fromOffset(104, 104), ZIndex = 5 })
new("Frame", { -- the tied neck
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -150), Size = UDim2.fromOffset(150, 30), BackgroundColor3 = Color3.fromRGB(30, 80, 190),
	ZIndex = 5, Parent = art,
}, deco(14, 4))

-- "~ LIMITED TIME! ~" in red, "10,000 SPEED!" in cyan to green
local limited = bold(window, 4, {
	Text = "~ LIMITED TIME! ~", Size = UDim2.fromOffset(410, 58), Position = UDim2.fromOffset(326, TITLE_H + 70), ZIndex = 3,
})
gradientText(limited, Color3.fromRGB(255, 120, 120), Color3.fromRGB(225, 25, 40), 90)
local amount = bold(window, 5, {
	Text = `{Format.commas(Config.FREE_GIFT_SPEED)} SPEED!`, Size = UDim2.fromOffset(420, 84), Position = UDim2.fromOffset(320, TITLE_H + 132), ZIndex = 3,
})
gradientText(amount, Color3.fromRGB(40, 200, 255), Color3.fromRGB(40, 245, 150), 0)

-- The three steps
local STEP_W, STEP_H, STEP_GAP = 228, 138, 12
local stepsTop = TITLE_H + 290
local function step(i: number, title: string): Frame
	local f = new("Frame", {
		Size = UDim2.fromOffset(STEP_W, STEP_H), Position = UDim2.fromOffset((W - 3 * STEP_W - 2 * STEP_GAP) / 2 + (i - 1) * (STEP_W + STEP_GAP), stepsTop),
		BackgroundColor3 = FRAME_INK, BackgroundTransparency = 0.5, ZIndex = 2, Parent = window,
	}, { new("UICorner", { CornerRadius = UDim.new(0, 10) }), new("UIStroke", { Thickness = 3, Color = FRAME_INK }) })
	bold(f, 2, { Text = `{i}. {title}`, Size = UDim2.new(1, -12, 0, 30), Position = UDim2.fromOffset(6, 6), ZIndex = 3 })
	local screen = new("Frame", {
		Name = "Screen", Size = UDim2.new(1, -20, 1, -50), Position = UDim2.fromOffset(10, 42), BackgroundColor3 = Color3.fromRGB(30, 32, 42), ZIndex = 3, Parent = f,
	}, { new("UICorner", { CornerRadius = UDim.new(0, 8) }), new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(110, 115, 130) }) })
	return screen
end

-- 1. Like: can't be checked or prompted in game, so it just shows where the button is.
local like = step(1, "Like the game!")
bold(like, 2, { Text = "👍", Size = UDim2.fromOffset(52, 52), Position = UDim2.fromOffset(10, 18), ZIndex = 4 })
bold(like, 2, {
	Text = "Tap 👍 on the game page", Size = UDim2.new(1, -74, 0, 52), Position = UDim2.fromOffset(66, 18), TextWrapped = true, ZIndex = 4, TextColor3 = NOTE_COLOR,
})

-- 2. Favorite: Roblox's own favourite prompt (the place is an asset). If it can't open, say where it is.
local favorite = step(2, "Favorite the game!")
local function promptFavorite()
	clickSound:Play()
	local ok = pcall(AvatarEditorService.PromptSetFavorite, AvatarEditorService, game.PlaceId, Enum.AvatarItemType.Asset, true)
	if not ok or game.PlaceId == 0 then
		setHint("Tap ☆ Favorite on the game page!")
	end
end
chunky(favorite, "⭐ Favorite", Color3.fromRGB(120, 70, 220), UDim2.new(1, -20, 0, 50), UDim2.fromOffset(10, 18), promptFavorite)
pcall(function()
	AvatarEditorService.PromptSetFavoriteCompleted:Connect(function(result: Enum.AvatarPromptResult)
		if result == Enum.AvatarPromptResult.Success then
			setHint("⭐ Thanks for the favorite!")
		end
	end)
end)

-- 3. Join the community: a group join can't be prompted in game, so the button says how.
local join = step(3, "Join the community!")
local joinHelp = if groupReady
	then `Join "{Config.COMMUNITY_NAME}": game page → Community → Join, then CLAIM!`
	else "Our community is coming soon!"
chunky(join, "Join Community", Color3.fromRGB(40, 110, 245), UDim2.new(1, -20, 0, 50), UDim2.fromOffset(10, 18), function()
	clickSound:Play()
	setHint(joinHelp)
end)

-- CLAIM! -> CLAIMED! (grey) once done; COMING SOON while there's no community id.
local claimButton = chunky(window, "CLAIM!", GREEN, UDim2.fromOffset(320, 64), UDim2.new(0.5, -160, 1, -82), function()
	if state.freeGift or not groupReady then
		return
	end
	clickSound:Play()
	setHint("Checking the community...")
	ClaimReward:FireServer("Gift")
end)
local claimLabel = claimButton:FindFirstChild("Label") :: TextLabel

local function render()
	local done = state.freeGift
	claimButton.BackgroundColor3 = if done or not groupReady then GREY else GREEN
	claimButton.AutoButtonColor = not done and groupReady
	claimLabel.Text = if done then "CLAIMED!" elseif groupReady then "CLAIM!" else "COMING SOON"
end

local function fit()
	local s = if hudScale then hudScale.Scale else 1
	local w, h = hud.AbsoluteSize.X / s, hud.AbsoluteSize.Y / s
	windowScale.Scale = math.clamp(math.min((w - 24) / (W + 12), (h - 24) / (H + 12)), 0.3, 1)
end

local function open()
	render()
	setHint(if state.freeGift
		then "You claimed it. Thanks for being in the community!"
		elseif groupReady then `Join our community to get {Format.short(Config.FREE_GIFT_SPEED)} Speed for free!`
		else "The Free Gift is coming soon!")
	fit()
	window.Visible = true
	windowScale.Scale *= 0.9
	TweenService:Create(windowScale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = windowScale.Scale / 0.9 }):Play()
end
close.Activated:Connect(function()
	window.Visible = false
end)
hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

----------------------------------------------------------------------------------------------------
-- The gift box by the free chest: its prompt opens the window ("Open" until claimed, then "View")
----------------------------------------------------------------------------------------------------
local giftPrompts: { ProximityPrompt } = {}
game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt: ProximityPrompt)
	if prompt:GetAttribute("FreeGift") and not window.Visible then
		clickSound:Play()
		open()
	end
end)

local function update()
	for i = #giftPrompts, 1, -1 do
		local prompt = giftPrompts[i]
		if prompt.Parent then
			prompt.ActionText = if state.freeGift then "View" else "Open"
		else
			table.remove(giftPrompts, i) -- streamed out or rebuilt
		end
	end
	if window.Visible then
		render()
	end
end

----------------------------------------------------------------------------------------------------
-- Server updates
----------------------------------------------------------------------------------------------------
StatsUpdate.OnClientEvent:Connect(function(changed: { [string]: any })
	if type(changed) ~= "table" then
		return
	end
	if type(changed.freeGift) == "boolean" then
		state.freeGift = changed.freeGift
	end
	if type(changed.chestAt) == "number" then
		state.chestAt = changed.chestAt
	end
	update()
end)

LootEvent.OnClientEvent:Connect(function(kind: string, data: any)
	if kind == "OpenFreeGift" then
		if not window.Visible then
			open()
		end
	elseif kind == "FreeGift" and type(data) == "table" then
		state.freeGift = data.claimed == true
		update()
		if data.result == "granted" then
			rewardSound:Play()
			setHint("🎉 Enjoy your Speed!")
		elseif data.result == "notMember" then
			setHint(joinHelp)
		elseif data.result == "error" then
			setHint("Couldn't check right now. Try again in a moment.")
		end
	end
end)

----------------------------------------------------------------------------------------------------
-- The free chest: "FREE!" when it's ready for this player, a countdown under it when it isn't
----------------------------------------------------------------------------------------------------
local chestPrompt: ProximityPrompt? = nil
local chestTimer: TextLabel? = nil
local function watch(d: Instance)
	if d:IsA("ProximityPrompt") and d:GetAttribute("FreeGift") then
		if not table.find(giftPrompts, d) then
			table.insert(giftPrompts, d)
		end
		update()
	elseif d:IsA("ProximityPrompt") and d:GetAttribute("FreeChest") then
		chestPrompt = d
	elseif d:IsA("TextLabel") and d.Name == "ChestTimer" then
		chestTimer = d
	end
end
workspace.DescendantAdded:Connect(watch)
for _, d in workspace:GetDescendants() do
	watch(d)
end

task.spawn(function()
	while true do
		local left = 0
		if state.chestAt > 0 then
			left = math.clamp(state.chestAt + Config.FREE_CHEST_COOLDOWN - workspace:GetServerTimeNow(), 0, Config.FREE_CHEST_COOLDOWN)
		end
		local ready = left < 1
		local timer = chestTimer
		if timer and timer.Parent then
			timer.Visible = not ready
			timer.Text = `Ready in {Format.clock(left)}`
		end
		local prompt = chestPrompt
		if prompt and prompt.Parent then
			prompt.ActionText = if ready then "Claim" else Format.clock(left)
		end
		task.wait(0.5)
	end
end)
