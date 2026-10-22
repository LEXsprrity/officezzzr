-- Community rewards UI (TODO 6, docs/references/06-*.png), kept out of HUD.client (near Luau's 200-locals
-- limit) but drawn in the same window style, inside the HUD's ScreenGui so it shares its scale and the
-- toasts show above it:
--   * the gift box where the free chest used to stand (GiftBox, server): its prompt (attribute FreeGift)
--     opens the window;
--   * the "Free Gift!" window: a cyan title bar, the Speed bag, "~ LIMITED TIME! ~ 10,000 SPEED!", three
--     steps (like, favourite, join the community) and the CLAIM! button. Only the community membership is
--     checked, on the server (RewardService); the like and the favourite are friendly asks.
local AvatarEditorService = game:GetService("AvatarEditorService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Icons = require(Shared:WaitForChild("Icons"))
local GiftLayout = require(Shared:WaitForChild("GiftLayout"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local Premium = require(Shared:WaitForChild("Premium"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local ClaimReward = remotes:WaitForChild("ClaimReward") :: RemoteEvent
local StatsUpdate = remotes:WaitForChild("StatsUpdate") :: RemoteEvent
local LootEvent = remotes:WaitForChild("LootEvent") :: RemoteEvent

local groupReady = Config.COMMUNITY_GROUP_ID > 0
local state = { freeGift = false }

----------------------------------------------------------------------------------------------------
-- The HUD's look (see HUD.client: "Tiny UI kit" and "Modals")
----------------------------------------------------------------------------------------------------
local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(25, 25, 35)
local GREEN = Color3.fromRGB(60, 200, 80)
local GREY = Color3.fromRGB(150, 152, 160)
local W, H, TITLE_H = GiftLayout.W, GiftLayout.H, GiftLayout.TITLE_H
local R = GiftLayout.rects

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

local function gradientText(label: TextLabel, a: Color3, b: Color3, rotation: number)
	new("UIGradient", { Rotation = rotation, Color = ColorSequence.new(a, b), Parent = label })
end

-- A glossy button (Premium.button) with its words in relief.
local function chunky(parent: Instance, label: string, color: Color3, size: UDim2, pos: UDim2, onClick: () -> ()): TextButton
	local b = new("TextButton", { Size = size, Position = pos, Text = "", AutoButtonColor = true, ZIndex = 3, Parent = parent })
	Premium.button(b, color)
	UiFx.relief(bold(b, 3, { Name = "Label", Text = label, Size = UDim2.new(1, -16, 1, -16), Position = UDim2.fromOffset(8, 5), ZIndex = 3 }), 3, 3)
	b.Activated:Connect(onClick)
	return b
end

local hud = player:WaitForChild("PlayerGui"):WaitForChild("SeedHUD")
local hudScale = hud:FindFirstChildOfClass("UIScale")
local clickSound = new("Sound", { SoundId = Config.SOUNDS.Click, Volume = 0.5, Parent = SoundService })
local rewardSound = new("Sound", { SoundId = Config.SOUNDS.Buy, Volume = 0.7, Parent = SoundService })

----------------------------------------------------------------------------------------------------
-- The "Free Gift!" window, in the premium look (Shared/Premium; owner 2026-10-22, the approved mockup)
----------------------------------------------------------------------------------------------------
local window = new("Frame", {
	Name = "FreeGift", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H),
	Active = true, Visible = false, ZIndex = 11, Parent = hud, -- above the HUD's windows, under its toasts
})
Premium.window(window, TITLE_H)
local windowScale = new("UIScale", { Parent = window })

-- The cyan title bar, the title in relief and the red X
local titleBar = Premium.titleBar(window, TITLE_H, Color3.fromRGB(80, 238, 255), Color3.fromRGB(25, 150, 240))
UiFx.relief(bold(titleBar, 5, {
	Text = "Free Gift!", Size = UDim2.new(1, -200, 0, 60), Position = UDim2.fromOffset(22, 10), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13,
}), 4, 5)
local close = Premium.close(titleBar, 62, 13)

-- One line of help under the title bar (what to do next, what happened)
local hint = bold(window, 3, {
	Text = "", Position = UDim2.fromOffset(R.hint.x, R.hint.y), Size = UDim2.fromOffset(R.hint.w, R.hint.h), TextColor3 = Premium.HINT, ZIndex = 3,
})
local function setHint(text: string)
	hint.Text = text
end

-- The Speed bag as it was (owner 2026-10-22: keep it, not the rendered one), like the reference's sack of shoes: light rays, a blue sack with a tied neck, the Speed
-- icon on it and more Speed spilling out of the top.
local art = new("Frame", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(R.art.x, R.art.y), Size = UDim2.fromOffset(R.art.w, R.art.h), ZIndex = 2,
	Parent = window,
})
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
}, {
	new("UICorner", { CornerRadius = UDim.new(0, 14) }),
	new("UIStroke", { Thickness = 4, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
})

-- "~ LIMITED TIME! ~" in red, "25,000 SPEED!" in cyan to green, both in relief
local limited = bold(window, 5, {
	Text = "~ LIMITED TIME! ~", Position = UDim2.fromOffset(R.limited.x, R.limited.y), Size = UDim2.fromOffset(R.limited.w, R.limited.h), ZIndex = 3,
})
gradientText(limited, Color3.fromRGB(255, 130, 130), Color3.fromRGB(230, 20, 45), 90)
UiFx.relief(limited, 4, 5)
local amount = bold(window, 6, {
	Text = `{Format.commas(Config.FREE_GIFT_SPEED)} SPEED!`, Position = UDim2.fromOffset(R.amount.x, R.amount.y), Size = UDim2.fromOffset(R.amount.w, R.amount.h), ZIndex = 3,
})
gradientText(amount, Color3.fromRGB(40, 205, 255), Color3.fromRGB(60, 245, 150), 0)
UiFx.relief(amount, 5, 6)

-- The three steps, in a row under the bag (GiftLayout: nothing overlaps): dark inset cards, the step's title
-- in relief, then its button.
local function step(i: number, title: string): Frame
	local r = R["step" .. i]
	local f = new("Frame", { Name = "Step" .. i, Position = UDim2.fromOffset(r.x, r.y), Size = UDim2.fromOffset(r.w, r.h), ZIndex = 2, Parent = window })
	Premium.card(f)
	local t = GiftLayout.stepTitle
	UiFx.relief(bold(f, 3, { Text = `{i}. {title}`, Position = UDim2.fromOffset(t.x, t.y), Size = UDim2.fromOffset(t.w, t.h), ZIndex = 3 }), 3, 3)
	return f
end
local stepBody = GiftLayout.stepBody
local bodyPos, bodySize = UDim2.fromOffset(stepBody.x, stepBody.y), UDim2.fromOffset(stepBody.w, stepBody.h)

-- 1. Like: can't be checked or prompted in game, so its button says where the Like is.
local like = step(1, "Like the game!")
chunky(like, "Like", Color3.fromRGB(45, 160, 250), bodySize, bodyPos, function()
	clickSound:Play()
	setHint("Tap the Like button on the game page!")
end)

-- 2. Favorite: Roblox's own favourite prompt (the place is an asset). If it can't open, say where it is.
local favorite = step(2, "Favorite the game!")
local function promptFavorite()
	clickSound:Play()
	local ok = pcall(AvatarEditorService.PromptSetFavorite, AvatarEditorService, game.PlaceId, Enum.AvatarItemType.Asset, true)
	if not ok or game.PlaceId == 0 then
		setHint("Tap Favorite on the game page!")
	end
end
chunky(favorite, "Favorite", Color3.fromRGB(150, 80, 240), bodySize, bodyPos, promptFavorite)
pcall(function()
	AvatarEditorService.PromptSetFavoriteCompleted:Connect(function(result: Enum.AvatarPromptResult)
		if result == Enum.AvatarPromptResult.Success then
			setHint("Thanks for the favorite!")
		end
	end)
end)

-- 3. Join the community: a group join can't be prompted in game, so the button says how.
local join = step(3, "Join the community!")
local joinHelp = if groupReady
	then `Join "{Config.COMMUNITY_NAME}": game page → Community → Join, then CLAIM!`
	else "Our community is coming soon!"
chunky(join, "Join Community", Color3.fromRGB(255, 150, 30), bodySize, bodyPos, function()
	clickSound:Play()
	setHint(joinHelp)
end)

-- CLAIM! -> CLAIMED! (grey) once done; COMING SOON while there's no community id.
local claimButton = chunky(window, "CLAIM!", GREEN, UDim2.fromOffset(R.claim.w, R.claim.h), UDim2.fromOffset(R.claim.x, R.claim.y), function()
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
-- The gift box: its prompt opens the window ("Open" until claimed, then "View")
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
			setHint("Enjoy your Speed!")
		elseif data.result == "notMember" then
			setHint(joinHelp)
		elseif data.result == "error" then
			setHint("Couldn't check right now. Try again in a moment.")
		end
	end
end)

-- The gift box's prompt, as it streams in.
local function watch(d: Instance)
	if d:IsA("ProximityPrompt") and d:GetAttribute("FreeGift") then
		if not table.find(giftPrompts, d) then
			table.insert(giftPrompts, d)
		end
		update()
	end
end
workspace.DescendantAdded:Connect(watch)
for _, d in workspace:GetDescendants() do
	watch(d)
end
