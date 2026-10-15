--!strict
-- The VIP gamepass's gold badge: a star and a chunky gold "VIP" in relief (a gold gradient, a thick dark
-- outline and a dark copy dropped behind it). One look for the tag over a VIP's head (Server/VipService) and
-- the badge by the local VIP's Speed and money (VipHudBadge.client).
-- Everything is sized in scale, the outline too (eight dark copies nudged around the text, not a UIStroke,
-- whose thickness is in pixels): the tag over a head is sized in studs, so far away it shrinks and keeps
-- its shape instead of turning into a blob of outline.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Icons = require(Shared:WaitForChild("Icons"))

local VipBadge = {}

VipBadge.TEXT = "VIP"
VipBadge.GOLD = Color3.fromRGB(255, 206, 40)
VipBadge.INK = Color3.fromRGB(70, 38, 0) -- the outline and the dropped copy: a deep brown, so the gold glows
VipBadge.ASPECT = 2.5 -- width / height of the space build() fills
local OUTLINE = 0.075 -- the outline's thickness, as a share of the badge's height
local DROP = 0.13 -- how far the dark copy drops, as a share of the badge's height
local STAR = 0.36 -- the star's share of the width (it is square: 0.36 x 2.5 = 0.9 of the height)

local function label(parent: Instance, name: string, color: Color3, x: number, y: number, z: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Position = UDim2.fromScale(x, y)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.Text = VipBadge.TEXT
	l.TextColor3 = color
	l.ZIndex = z
	l.Parent = parent
	return l
end

-- Fills `parent` (a GuiObject or a BillboardGui about ASPECT times as wide as it is tall) with the badge.
-- Returns the gold text label (named "Label"; its dropped copy is "Shadow").
function VipBadge.build(parent: Instance): TextLabel
	local image = Icons.image("Star")
	local textLeft = if image then STAR * 0.82 else 0 -- the text tucks in a little behind the star's tips
	local textBox = Instance.new("Frame")
	textBox.Name = "Text"
	textBox.BackgroundTransparency = 1
	textBox.Position = UDim2.fromScale(textLeft, 0)
	textBox.Size = UDim2.fromScale(1 - textLeft, 1)
	textBox.Parent = parent
	-- (offsets are in the text box's scale: x by its width, y by its height)
	local aspect = VipBadge.ASPECT * (1 - textLeft)
	local ox, oy = OUTLINE / aspect, OUTLINE
	label(textBox, "Shadow", VipBadge.INK, ox * 0.6, DROP, 1)
	for i = 0, 7 do
		local a = i * math.pi / 4
		label(textBox, "Outline", VipBadge.INK, math.cos(a) * ox, math.sin(a) * oy, 2)
	end
	-- white text, coloured by its gradient (a gradient multiplies the text colour, so only white lets its
	-- top be lighter than the gold): pale gold on top, GOLD in the middle, deep amber at the foot
	local main = label(textBox, "Label", Color3.new(1, 1, 1), 0, 0, 3)
	local bevel = Instance.new("UIGradient")
	bevel.Name = "Gold"
	bevel.Rotation = 90
	bevel.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 244, 150)),
		ColorSequenceKeypoint.new(0.5, VipBadge.GOLD),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(228, 128, 18)),
	})
	bevel.Parent = main

	if image then
		local star = Instance.new("ImageLabel")
		star.Name = "Star"
		star.BackgroundTransparency = 1
		star.Image = image
		star.ScaleType = Enum.ScaleType.Fit
		star.AnchorPoint = Vector2.new(0, 0.5)
		star.Position = UDim2.fromScale(0, 0.5)
		star.Size = UDim2.fromScale(STAR, 1.05)
		star.Rotation = -12
		star.ZIndex = 4
		star.Parent = parent
	end
	return main
end

return VipBadge
