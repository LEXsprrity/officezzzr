-- The VIP gamepass's badge in the HUD: the gold relief "VIP" with its star (Shared/VipBadge, the badge over
-- a VIP's head), just over the Speed and money in the bottom-left corner, while the server says this player
-- is VIP (the VIP attribute, set only by Server/VipService). Its own script and ScreenGui, scaled like the
-- HUD's (HUD.client's rescale), so the HUD is left alone.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local VipBadge = require(Shared:WaitForChild("VipBadge"))

local player = Players.LocalPlayer

-- HUD.client's bottom-left readout (design pixels): 14 from the left, STATS_BOTTOM 10 from the bottom,
-- STATS_H 100 tall. The badge sits on top of it, over the Speed icon.
local LEFT, ABOVE = 14, 10 + 100 + 4
local HEIGHT = 34

local gui = Instance.new("ScreenGui")
gui.Name = "VipBadge"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local uiScale = Instance.new("UIScale")
uiScale.Parent = gui
local function rescale()
	local cam = workspace.CurrentCamera
	local y = if cam then cam.ViewportSize.Y else 900
	uiScale.Scale = math.clamp(y / 900, 0.55, 1.25)
end

local badge = Instance.new("Frame")
badge.Name = "Badge"
badge.BackgroundTransparency = 1
badge.AnchorPoint = Vector2.new(0, 1)
badge.Position = UDim2.new(0, LEFT, 1, -ABOVE)
badge.Size = UDim2.fromOffset(math.floor(HEIGHT * VipBadge.ASPECT), HEIGHT)
badge.Visible = false
badge.Parent = gui
local pop = Instance.new("UIScale")
pop.Parent = badge
VipBadge.build(badge)

local function refresh()
	local vip = player:GetAttribute("VIP") == true
	if vip and not badge.Visible then
		-- a little springy pop when it shows up (joining as a VIP, or buying it)
		pop.Scale = 0.4
		TweenService:Create(pop, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	badge.Visible = vip
end

player:GetAttributeChangedSignal("VIP"):Connect(refresh)
refresh()
rescale()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end
	rescale()
end)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end
gui.Parent = player:WaitForChild("PlayerGui")
