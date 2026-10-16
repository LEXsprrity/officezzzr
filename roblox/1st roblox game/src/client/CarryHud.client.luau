-- While you carry a stolen seed (owner 2026-10-16, reference screenshot): the rest of the UI goes away, a
-- big red "RUN!!" plate pulses at the top of the screen and a red "Drop" button sits at the bottom. Drop
-- gives the seed back to its pod (RequestUseItem "Drop" -> SeedService.returnCarry), like getting caught.
-- What you carry comes from StatsUpdate `carrying` (a table, or false). Every other ScreenGui we own is
-- disabled while carrying and turned back on after (the zone banner stays). Bat still works on its key.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopUi = require(Shared:WaitForChild("ShopUi"))
local UiFx = require(Shared:WaitForChild("UiFx"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local StatsUpdate = remotes:WaitForChild("StatsUpdate") :: RemoteEvent
local RequestUseItem = remotes:WaitForChild("RequestUseItem") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local new = ShopUi.new

local RED = Color3.fromRGB(225, 25, 35)
local INK = ShopUi.INK
local KEEP = { CarryHud = true, ZoneBanner = true } -- shown while running

local gui = new("ScreenGui", { Name = "CarryHud", ResetOnSpawn = false, Enabled = false, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
-- Same design-pixel scale as the HUD: 900 tall at scale 1
local uiScale = new("UIScale", { Parent = gui })
local function rescale()
	local cam = workspace.CurrentCamera
	uiScale.Scale = math.clamp((if cam then cam.ViewportSize.Y else 900) / 900, 0.55, 1.25)
end
rescale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

-- A square red studded plate with a thick dark outline and a lighter top half.
local function plate(className: string, props: { [string]: any }): any
	local f = new(className, props)
	f.BackgroundColor3 = RED
	f.BorderSizePixel = 0
	new("UIStroke", { Thickness = 5, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f })
	ShopUi.studs(f, RED)
	ShopUi.bevel(f)
	return f
end

-- RUN!! at the top (above the zone banner, which sits 70 px down)
local run = plate("Frame", {
	Name = "Run", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(380, 64), ZIndex = 2, Parent = gui,
})
local runScale = new("UIScale", { Parent = run })
UiFx.relief(ShopUi.label(run, 4, { Name = "Word", Text = "RUN!!", Size = UDim2.new(1, -24, 1, -10), Position = UDim2.fromOffset(12, 5), ZIndex = 4 }), 4, 4)

-- Drop at the bottom
local drop = plate("TextButton", {
	Name = "Drop", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40),
	Size = UDim2.fromOffset(250, 72), ZIndex = 2, Parent = gui,
})
UiFx.relief(ShopUi.label(drop, 4, { Name = "Word", Text = "Drop", Size = UDim2.new(1, -24, 1, -14), Position = UDim2.fromOffset(12, 7), ZIndex = 4 }), 4, 4)
UiFx.pop(drop)
drop.Activated:Connect(function()
	RequestUseItem:FireServer("Drop")
end)

gui.Parent = playerGui

-- The RUN!! plate throbs while it shows
local pulse = TweenService:Create(runScale, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.08 })

local hidden: { ScreenGui } = {}
local carrying = false
local function setCarrying(on: boolean)
	if on == carrying then
		return
	end
	carrying = on
	gui.Enabled = on
	if on then
		pulse:Play()
		for _, g in playerGui:GetChildren() do
			if g:IsA("ScreenGui") and g.Enabled and not KEEP[g.Name] then
				g.Enabled = false
				table.insert(hidden, g)
			end
		end
	else
		pulse:Cancel()
		runScale.Scale = 1
		for _, g in hidden do
			if g.Parent then
				g.Enabled = true
			end
		end
		hidden = {}
	end
end

StatsUpdate.OnClientEvent:Connect(function(partial: { [string]: any })
	if type(partial) == "table" and partial.carrying ~= nil then
		setCarrying(partial.carrying ~= false)
	end
end)
-- A new character never carries (the server returns the seed when you die)
player.CharacterAdded:Connect(function()
	setCarrying(false)
end)
