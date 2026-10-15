-- The VIP gamepass's badge in the HUD: the gold relief "VIP" with its star (Shared/VipBadge, the badge over
-- a VIP's head) on a studded red plate with a thick dark outline (ShopUi.studs, like every HUD element),
-- just over the Speed and money in the bottom-left corner, while the server says this player is VIP (the
-- VIP attribute, set only by Server/VipService). It sits inside the HUD's readout (SeedHUD.Stats), so it is
-- scaled and fitted with it (HUD.client's rescale and fitLeftColumn, which leaves it ABOVE pixels of room).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local VipBadge = require(Shared:WaitForChild("VipBadge"))
local ShopUi = require(Shared:WaitForChild("ShopUi"))

local player = Players.LocalPlayer

-- (design pixels, like the readout's 84-pixel icons and 80-pixel numbers)
local HEIGHT = 46 -- the gold "VIP" and its star
local PAD = 5 -- the plate around it
local GAP = 8 -- between the plate and the Speed under it (plate + gap = 64, fitLeftColumn's room)
local PLATE = Color3.fromRGB(225, 45, 70) -- the VIP pass card's red (PassCards.COLORS.VIP)

local stats = player:WaitForChild("PlayerGui"):WaitForChild("SeedHUD"):WaitForChild("Stats")

local plate = Instance.new("Frame")
plate.Name = "VipBadge"
plate.AnchorPoint = Vector2.new(0, 1)
plate.Position = UDim2.fromOffset(0, -GAP)
plate.Size = UDim2.fromOffset(math.floor(HEIGHT * VipBadge.ASPECT) + 2 * PAD, HEIGHT + 2 * PAD)
plate.BackgroundColor3 = PLATE
plate.BorderSizePixel = 0
plate.Visible = false
local stroke = Instance.new("UIStroke")
stroke.Thickness = 4
stroke.Color = ShopUi.INK
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = plate
ShopUi.studs(plate, PLATE)
ShopUi.bevel(plate)
local pop = Instance.new("UIScale")
pop.Parent = plate

local badge = Instance.new("Frame")
badge.Name = "Badge"
badge.BackgroundTransparency = 1
badge.Position = UDim2.fromOffset(PAD, PAD - 2)
badge.Size = UDim2.fromOffset(math.floor(HEIGHT * VipBadge.ASPECT), HEIGHT)
badge.ZIndex = 2
badge.Parent = plate
VipBadge.build(badge)

local function refresh()
	local vip = player:GetAttribute("VIP") == true
	if vip and not plate.Visible then
		-- a little springy pop when it shows up (joining as a VIP, or buying it)
		pop.Scale = 0.4
		TweenService:Create(pop, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	plate.Visible = vip
end

player:GetAttributeChangedSignal("VIP"):Connect(refresh)
refresh()
plate.Parent = stats
