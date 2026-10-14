-- Entering a zone flashes its name near the top of the screen for about two seconds: a translucent dark
-- strip that fades out at both ends, the zone's name in big outlined letters in the zone's colour and a
-- face that says how scary it is ("Desert 😮", "Lava Fields 😰"). It slides and fades in, holds, then
-- fades out. Walking back into the base shows nothing. Display only: the
-- zone comes from Config.zoneAtX(root X), like the server's. (The recommended Speed is on the zone gates'
-- planks in the world, not in the HUD.)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer

-- Per zone (by Config.ZONES id): the name's colour and the face. A zone missing here falls back to its
-- Config icon and UI colour.
local LOOK: { [string]: { color: Color3, face: string } } = {
	Meadow = { color = Color3.fromRGB(125, 235, 70), face = "😄" },
	Desert = { color = Color3.fromRGB(255, 195, 45), face = "😮" },
	Jungle = { color = Color3.fromRGB(60, 225, 110), face = "😬" },
	Lava = { color = Color3.fromRGB(255, 75, 45), face = "😰" },
	Snow = { color = Color3.fromRGB(120, 215, 255), face = "🥶" },
	Space = { color = Color3.fromRGB(180, 120, 255), face = "😱" },
	Spirit = { color = Color3.fromRGB(255, 120, 205), face = "🤩" },
}
local INK = Color3.fromRGB(16, 18, 26)
local WHITE = Color3.new(1, 1, 1)
local FONT = Enum.Font.FredokaOne

local TOP = 70 -- design pixels from the top (the HUD's toasts move down under it while it shows)
local STRIP_W, STRIP_H = 1100, 84
local HOLD = 1 -- seconds on screen, between the fade in and the fade out
local SETTLE = 0.2 -- a new zone must hold this long first, so standing on a border doesn't flicker

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

local gui = new("ScreenGui", { Name = "ZoneBanner", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
-- Same design-pixel scale as the HUD: 900 tall at scale 1
local uiScale = new("UIScale", { Parent = gui })
local function rescale()
	local cam = workspace.CurrentCamera
	uiScale.Scale = math.clamp((if cam then cam.ViewportSize.Y else 900) / 900, 0.55, 1.25)
end

-- The whole banner fades as one (GroupTransparency) and slides a few pixels down as it comes in.
local group = new("CanvasGroup", {
	Name = "Strip", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, TOP - 16), Size = UDim2.fromOffset(STRIP_W, STRIP_H),
	BackgroundTransparency = 1, GroupTransparency = 1, Visible = false, Parent = gui,
})
-- The dark strip: see-through, and fully clear at both ends
new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BorderSizePixel = 0, Parent = group }, {
	new("UIGradient", { Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.28, 0.5),
		NumberSequenceKeypoint.new(0.72, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	}) }),
})
-- The name and the face side by side, centred
local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = group }, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
local pop = new("UIScale", { Parent = row })
local nameLabel = new("TextLabel", {
	BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 70), Font = FONT, TextSize = 64,
	TextColor3 = WHITE, Text = "", LayoutOrder = 1, Parent = row,
}, { new("UIStroke", { Thickness = 5, Color = INK }) })
-- A light top on the letters, in the zone's colour underneath
local nameGradient = new("UIGradient", { Rotation = 90, Parent = nameLabel })
local faceLabel = new("TextLabel", {
	BackgroundTransparency = 1, Size = UDim2.fromOffset(70, 70), Font = FONT, TextScaled = true, Text = "", LayoutOrder = 2, Parent = row,
})

local shown = 0 -- bumped per banner, so an older banner's fade-out leaves a newer one alone

local function show(title: string, face: string, color: Color3, big: boolean)
	shown += 1
	local mine = shown
	nameLabel.Text = title
	nameLabel.TextSize = if big then 64 else 44
	faceLabel.Text = face
	faceLabel.Size = UDim2.fromOffset(if big then 70 else 48, if big then 70 else 48)
	nameGradient.Color = ColorSequence.new(color:Lerp(WHITE, 0.45), color)
	group.Visible = true
	group.GroupTransparency = 1
	group.Position = UDim2.new(0.5, 0, 0, TOP - 16)
	pop.Scale = 1.15
	local slideIn = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(group, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { GroupTransparency = 0 }):Play()
	TweenService:Create(group, slideIn, { Position = UDim2.new(0.5, 0, 0, TOP) }):Play()
	TweenService:Create(pop, slideIn, { Scale = 1 }):Play()
	task.delay(0.35 + HOLD, function()
		if shown ~= mine then
			return
		end
		local outInfo = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(group, outInfo, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 0, TOP - 10) }):Play()
		task.delay(0.5, function()
			if shown == mine then
				group.Visible = false
			end
		end)
	end)
end

-- Only the corridor's zones are announced: walking back into the base shows nothing.
local function announce(zone: number?)
	if zone then
		local z = Config.ZONES[zone]
		local look = LOOK[z.id]
		show(z.name, if look then look.face else z.icon, if look then look.color else z.ui, true)
	end
end

-- Zone tracking: the zone under the character, announced once it has held for SETTLE seconds. The first
-- reading after spawning is taken as is (spawning at the base says nothing).
local current: number? = nil
local known = false
local candidate: number? = nil
local candidateSince = 0
RunService.Heartbeat:Connect(function()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		known = false
		return
	end
	local zone = Config.zoneAtX(root.Position.X)
	if not known then
		known, current, candidate = true, zone, zone
		return
	end
	if zone ~= candidate then
		candidate, candidateSince = zone, os.clock()
	end
	if candidate ~= current and os.clock() - candidateSince >= SETTLE then
		current = candidate
		announce(current)
	end
end)

rescale()
gui.Parent = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end
