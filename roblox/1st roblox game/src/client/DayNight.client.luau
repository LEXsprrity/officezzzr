-- The day/night switch on this screen: at every phase flip the screen fades to black for about a second,
-- the fixed day or night look (Shared/LightingLook) switches while it is black, and it fades back in.
-- Everything comes from Config.dayPhase(server time), so every player's fade and switch happen together;
-- the local Lighting write is instant here, and the server's own write (AmbientService) only repeats it.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LightingLook = require(Shared:WaitForChild("LightingLook"))

local gui = Instance.new("ScreenGui")
gui.Name = "DayNightFade"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000 -- over the whole HUD
local black = Instance.new("Frame")
black.Name = "Black"
black.Size = UDim2.fromScale(1, 1)
black.BackgroundColor3 = Color3.new(0, 0, 0)
black.BorderSizePixel = 0
black.BackgroundTransparency = 1
black.Visible = false
black.Parent = gui
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local shownNight: boolean? = nil
RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()
	local alpha = LightingLook.fadeAlpha(now)
	black.Visible = alpha > 0
	black.BackgroundTransparency = 1 - alpha
	local night = Config.dayPhase(now)
	if night ~= shownNight then -- the flip (or the first frame): switch the look, behind the black
		LightingLook.applyPhase(Lighting, LightingLook.findEffects(Lighting), night)
		shownNight = night
	end
end)
