-- The day/night timer, top right in the top bar's row (under it the player list would cover it): a
-- translucent dark square strip studded like every HUD element (ShopUi.studs), a chunky icon of what comes
-- next (a cloud and moon by day, the sun by night) and the time left in big bold italic white with a thick
-- dark outline, a dropped shadow and a bevel ("in 2m 58s"). When the phase flips the strip pops and the icon swaps. Display only: the phase comes from
-- Config.dayPhase(server time), like the server's. Kept out of HUD.client (near Luau's 200-locals limit).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local ShopUi = require(Shared:WaitForChild("ShopUi"))

local player = Players.LocalPlayer

local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(16, 18, 26)
local TIME_FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local ICON_FONT = Enum.Font.FredokaOne
local TIMER_W, TIMER_H = 236, 46
local TIMER_RIGHT, TIMER_TOP = 14, 6 -- inside the 58-pixel top bar, right of Roblox's own buttons

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

local gui = new("ScreenGui", {
	Name = "DayTimer", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
-- The HUD's design-pixel scale (900 tall at 1), but never bigger than the top bar it sits in
local uiScale = new("UIScale", { Parent = gui })
local function rescale()
	local cam = workspace.CurrentCamera
	uiScale.Scale = math.clamp((if cam then cam.ViewportSize.Y else 900) / 900, 0.7, 1)
end

local strip = new("Frame", {
	Name = "Strip", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -TIMER_RIGHT, 0, TIMER_TOP),
	Size = UDim2.fromOffset(TIMER_W, TIMER_H), BackgroundColor3 = Color3.fromRGB(12, 14, 24), BackgroundTransparency = 0.42, Parent = gui,
}, {
	new("UIStroke", { Thickness = 3, Color = INK, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	-- a touch lighter at the top, like glass
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0, 0.25) }),
})
ShopUi.studs(strip, Color3.fromRGB(60, 66, 90)) -- under the icon and the time
local stripScale = new("UIScale", { Parent = strip })

-- Chunky emoji icons: big, with a dark outline. Night: a crescent moon with a cloud in front of it.
local function emoji(parent: Instance, glyph: string, props: { [string]: any }): TextLabel
	local label = new("TextLabel", {
		BackgroundTransparency = 1, Font = ICON_FONT, Text = glyph, TextScaled = true, TextColor3 = WHITE, Parent = parent,
	}, { new("UIStroke", { Thickness = 2.5, Color = INK, LineJoinMode = Enum.LineJoinMode.Round }) })
	for k, v in props do
		(label :: any)[k] = v
	end
	return label
end
local iconBox = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 2), Size = UDim2.fromOffset(TIMER_H - 4, TIMER_H - 4), Parent = strip })
local sunIcon = emoji(iconBox, "☀️", { Name = "Sun", Size = UDim2.fromScale(1, 1) })
local nightIcon = new("Frame", { Name = "CloudMoon", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = iconBox })
emoji(nightIcon, "🌙", { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.24, 0) })
emoji(nightIcon, "☁️", { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0, 0.32), ZIndex = 2 })

local timeLabel = new("TextLabel", {
	Name = "Time", BackgroundTransparency = 1, FontFace = TIME_FONT, Text = "", TextScaled = true, TextColor3 = WHITE,
	TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(TIMER_H + 8, 5), Size = UDim2.new(1, -TIMER_H - 18, 1, -12),
	Parent = strip,
}, { new("UIStroke", { Thickness = 3, Color = INK }) })
UiFx.relief(timeLabel, 3)

local lastNight: boolean? = nil
local lastUpdate = 0
local function update()
	local night, remaining = Config.dayPhase(workspace:GetServerTimeNow())
	timeLabel.Text = `in {Format.countdown(remaining)}`
	if night ~= lastNight then
		-- what comes next: night by day, the sun by night
		nightIcon.Visible = not night
		sunIcon.Visible = night
		if lastNight ~= nil then
			stripScale.Scale = 1.15
			TweenService:Create(stripScale, TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		lastNight = night
	end
end

rescale()
gui.Parent = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end
RunService.RenderStepped:Connect(function() -- the first frame fills it in
	if os.clock() - lastUpdate >= 0.25 then
		lastUpdate = os.clock()
		update()
	end
end)
