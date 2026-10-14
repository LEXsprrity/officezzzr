-- The Free Gift's box in the world, next to the free chest ("like the treasure"): a pink present with a
-- gold ribbon and bow on a glowing pink circle, "FREE GIFT" floating above it and a ProximityPrompt
-- (attribute FreeGift) that opens the Free Gift window on the client (Rewards.client). Built at runtime
-- by RewardService beside the chest the map has, so it follows the chest wherever the map puts it.
-- Opening the window decides nothing: the window's CLAIM! button asks the server (ClaimReward "Gift").
local GiftBox = {}

GiftBox.OFFSET = 11 -- studs from the chest, along the chest's right (away from the MOST MONEY/s board)
GiftBox.CIRCLE = 9 -- the glowing circle's diameter (the chest's is 11: they don't touch)
GiftBox.LABEL = "FREE GIFT"

local PINK = Color3.fromRGB(240, 70, 175)
local LID_PINK = Color3.fromRGB(255, 105, 195)
local RIBBON = Color3.fromRGB(255, 205, 50)
local GLOW = Color3.fromRGB(255, 120, 215)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = collide == true
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A flat disc lying on the ground at `cf` (a cylinder's axis is its X: turned upright).
local function disc(parent: Instance, name: string, diameter: number, cf: CFrame, color: Color3, transparency: number, material: Enum.Material): Part
	local p = part(parent, name, Vector3.new(0.15, diameter, diameter), cf * CFrame.Angles(0, 0, math.pi / 2), color)
	p.Shape = Enum.PartType.Cylinder
	p.Material = material
	p.Transparency = transparency
	p.CastShadow = false
	return p
end

-- The ground point beside `chest` (the Role "FreeChest" prompt part: 5 tall, its bottom 0.6 above the
-- ground), facing the way the chest faces.
function GiftBox.groundCFrame(chest: BasePart): CFrame
	return chest.CFrame * CFrame.new(GiftBox.OFFSET, -(chest.Size.Y / 2 + 0.6), 0)
end

-- Builds the box beside `chest`, in the chest's parent. Returns the model and its prompt.
function GiftBox.build(chest: BasePart): (Model, ProximityPrompt)
	local model = Instance.new("Model")
	model.Name = "GiftBox"
	local ground = GiftBox.groundCFrame(chest)
	local function at(x: number, y: number, z: number): CFrame
		return ground * CFrame.new(x, y, z)
	end

	disc(model, "GiftCircle", GiftBox.CIRCLE, at(0, 0.08, 0), GLOW, 0.25, Enum.Material.Neon)
	disc(model, "GiftCircleFill", GiftBox.CIRCLE - 1.8, at(0, 0.12, 0), Color3.fromRGB(255, 200, 235), 0.45, Enum.Material.SmoothPlastic)
	local body = part(model, "GiftBody", Vector3.new(4.2, 3.4, 4.2), at(0, 2, 0), PINK, true)
	part(model, "GiftLid", Vector3.new(4.7, 1, 4.7), at(0, 4.2, 0), LID_PINK)
	part(model, "RibbonX", Vector3.new(0.9, 3.45, 4.3), at(0, 2, 0), RIBBON)
	part(model, "RibbonZ", Vector3.new(4.3, 3.45, 0.9), at(0, 2, 0), RIBBON)
	part(model, "LidRibbonX", Vector3.new(0.9, 1.05, 4.8), at(0, 4.2, 0), RIBBON)
	part(model, "LidRibbonZ", Vector3.new(4.8, 1.05, 0.9), at(0, 4.2, 0), RIBBON)
	for _, side in { -1, 1 } do -- the bow: two loops leaning out of a knot
		part(model, "BowLoop", Vector3.new(1.7, 1.1, 0.6), at(side * 0.85, 5.1, 0) * CFrame.Angles(0, 0, side * math.rad(35)), RIBBON)
	end
	part(model, "BowKnot", Vector3.new(0.8, 0.8, 0.8), at(0, 5.05, 0), Color3.fromRGB(255, 180, 30))
	body:SetAttribute("Role", "FreeGiftBox")
	model.PrimaryPart = body

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = "Free Gift"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("FreeGift", true)
	prompt.Parent = body

	-- "FREE GIFT" above it, pink like the box (the chest's "FREE!" is green)
	local gui = Instance.new("BillboardGui")
	gui.Name = "GiftSign"
	gui.Size = UDim2.fromScale(10, 3.2)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5.4, 0)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	gui.Adornee = body
	gui.Parent = body
	local label = Instance.new("TextLabel")
	label.Name = "GiftFree"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = GiftBox.LABEL
	label.TextColor3 = Color3.fromRGB(255, 120, 220)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 5
	stroke.Color = Color3.fromRGB(80, 10, 60)
	stroke.Parent = label
	label.Parent = gui

	model.Parent = chest.Parent
	return model, prompt
end

return GiftBox
