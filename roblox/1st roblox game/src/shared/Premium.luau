--!strict
-- The premium look (owner 2026-10-22: "make the UI more premium ... it looks AI made"; the approved Free Gift
-- mockup): deep navy window bodies with faint studs, so the bright words and buttons stand out; rounded
-- corners with a thick dark outline; glossy buttons (a lit top half, a darker lip along the bottom); dark
-- inset cards; real rendered pictures (tools/blender) on a soft glow with rays instead of art drawn from
-- frames. Client only; every window builds from these:
--   * Premium.window(f): the navy body;
--   * Premium.titleBar(window, height, from, to): the glossy coloured bar across a window's top;
--   * Premium.button(b, color): a glossy button (its colour may change later: the shading multiplies it);
--   * Premium.card(f): a dark inset card;
--   * Premium.close(parent): the red X;
--   * Premium.glow(parent, props): the glow with rays behind a picture (Icons.TEXTURES GlowRays).
local Icons = require(script.Parent:WaitForChild("Icons"))
local ShopUi = require(script.Parent:WaitForChild("ShopUi"))
local UiFx = require(script.Parent:WaitForChild("UiFx"))

local Premium = {}

local WHITE = Color3.new(1, 1, 1)
local new = ShopUi.new

Premium.INK = Color3.fromRGB(11, 14, 28)
Premium.BODY = Color3.fromRGB(34, 34, 40) -- the windows' dark charcoal (Steal an Egg's, owner 2026-10-23)
Premium.CARD = Color3.fromRGB(50, 60, 112)
Premium.HINT = Color3.fromRGB(205, 225, 255) -- small words on the body
Premium.RED = Color3.fromRGB(240, 45, 55)
Premium.RADIUS = 18
Premium.BUTTON_RADIUS = 4
Premium.OUTLINE = 6 -- a window's outline
Premium.BUTTON_OUTLINE = 2
Premium.STUD_FADE = 0.88 -- the body's studs: only just there

local function corner(f: Instance, r: number)
	local c = f:FindFirstChildOfClass("UICorner") or new("UICorner", { Parent = f })
	c.CornerRadius = UDim.new(0, r)
end

local function outline(f: Instance, thickness: number, color: Color3?)
	local s = f:FindFirstChildOfClass("UIStroke") or new("UIStroke", { Parent = f })
	s.Thickness = thickness
	s.Color = color or Premium.INK
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
end

-- A grey ramp that multiplies the frame's own colour (so it can be recoloured later): full at the top,
-- `low` at the bottom, and with `lip` a darker band along the bottom edge (a button's 3D edge).
local function shading(f: Instance, low: number, lip: boolean?)
	local g = f:FindFirstChildOfClass("UIGradient") or new("UIGradient", { Parent = f })
	g.Rotation = 90
	local function grey(v: number): Color3
		return Color3.new(v, v, v)
	end
	g.Color = if lip
		then ColorSequence.new({
			ColorSequenceKeypoint.new(0, WHITE),
			ColorSequenceKeypoint.new(0.5, grey(0.94)),
			ColorSequenceKeypoint.new(0.76, grey(low)),
			ColorSequenceKeypoint.new(0.77, grey(low * 0.72)),
			ColorSequenceKeypoint.new(1, grey(low * 0.72)),
		})
		else ColorSequence.new(WHITE, grey(low))
end

-- The navy body of a window `f` (any size), rounded, outlined, with faint studs under its title bar
-- (`titleH` px tall: no studs there).
function Premium.window(f: GuiObject, titleH: number?)
	f.BackgroundColor3 = Premium.BODY
	f.BackgroundTransparency = 0
	f.BorderSizePixel = 0
	corner(f, Premium.RADIUS)
	outline(f, Premium.OUTLINE)
	shading(f, 0.62)
	local top = titleH or 0
	local studs = new("Frame", {
		Name = "BodyStuds", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 1, -top),
		ClipsDescendants = true, ZIndex = f.ZIndex, Parent = f,
	})
	ShopUi.studs(studs, Premium.BODY, Premium.STUD_FADE, f.ZIndex)
end

-- The glossy bar across the top of `window` (`h` px), a gradient from `from` (left) to `to` (right): the
-- window's rounded top corners, square at the bottom, three light diagonal bands on its right, a gloss on
-- its top half and the dark line under it. Returns the bar (its title goes in it).
function Premium.titleBar(window: GuiObject, h: number, from: Color3, to: Color3): Frame
	local z = window.ZIndex + 1
	local colors = ColorSequence.new(from, to)
	local bar = new("Frame", {
		Name = "TitleBar", Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = WHITE, BorderSizePixel = 0, ClipsDescendants = false, ZIndex = z,
		Parent = window,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, Premium.RADIUS - 4) }),
		new("UIGradient", { Color = colors }),
	})
	new("Frame", { -- square bottom corners
		Name = "Square", Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = WHITE, BorderSizePixel = 0,
		ZIndex = z, Parent = bar,
	}, { new("UIGradient", { Color = colors }) })
	-- the diagonal bands: a square seen through the bar (a true 45°), clipped to it
	local keys = { NumberSequenceKeypoint.new(0, 1) }
	for _, band in { { 0.56, 0.6 }, { 0.62, 0.635 }, { 0.66, 0.71 } } do
		table.insert(keys, NumberSequenceKeypoint.new(band[1] - 0.001, 1))
		table.insert(keys, NumberSequenceKeypoint.new(band[1], 0.74))
		table.insert(keys, NumberSequenceKeypoint.new(band[2], 0.74))
		table.insert(keys, NumberSequenceKeypoint.new(band[2] + 0.001, 1))
	end
	table.insert(keys, NumberSequenceKeypoint.new(1, 1))
	local clip = new("Frame", { Name = "Bands", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ClipsDescendants = true, ZIndex = z, Parent = bar })
	new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(1400, 1400), BackgroundColor3 = WHITE,
		BorderSizePixel = 0, ZIndex = z, Parent = clip,
	}, { new("UIGradient", { Rotation = 45, Transparency = NumberSequence.new(keys) }) })
	new("Frame", { -- the gloss on its top half
		Name = "Gloss", Size = UDim2.fromScale(1, 0.48), BackgroundColor3 = WHITE, BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = z,
		Parent = bar,
	}, { new("UICorner", { CornerRadius = UDim.new(0, Premium.RADIUS - 4) }) })
	new("Frame", { -- the dark line under it
		Name = "Line", Position = UDim2.new(0, 0, 1, -3), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = Premium.INK, BorderSizePixel = 0,
		ZIndex = z + 1, Parent = bar,
	})
	return bar
end

-- A button like Steal an Egg's (owner 2026-10-23): a flat vivid colour going a little darker toward the
-- bottom, a thin dark outline, barely rounded. Colour it with BackgroundColor3 (now or later). The caller adds
-- its words (ShopUi.label) and connects it.
function Premium.button(b: GuiObject, color: Color3?, radius: number?)
	if color then
		b.BackgroundColor3 = color
	end
	b.BorderSizePixel = 0
	corner(b, radius or Premium.BUTTON_RADIUS)
	outline(b, Premium.BUTTON_OUTLINE)
	shading(b, 0.8)
end

-- A dark inset card on the body (the Free Gift's steps, a shop item).
function Premium.card(f: GuiObject, color: Color3?)
	f.BackgroundColor3 = color or Premium.CARD
	f.BackgroundTransparency = 0
	f.BorderSizePixel = 0
	corner(f, 16)
	outline(f, 5)
	shading(f, 0.7)
	new("Frame", { -- a thin light rim along its top
		Name = "Rim", Position = UDim2.fromOffset(10, 3), Size = UDim2.new(1, -20, 0, 2), BackgroundColor3 = WHITE, BackgroundTransparency = 0.82,
		BorderSizePixel = 0, ZIndex = f.ZIndex, Parent = f,
	})
end

-- The red X that closes a window: a square glossy button `size` px with a white X in relief.
function Premium.close(parent: Instance, size: number, z: number): TextButton
	local b = new("TextButton", {
		Name = "Close", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(size, size),
		Text = "", AutoButtonColor = true, ZIndex = z, Parent = parent,
	})
	Premium.button(b, Premium.RED, 12)
	UiFx.relief(ShopUi.label(b, 4, { Name = "X", Text = "X", Size = UDim2.new(1, -18, 1, -18), Position = UDim2.fromOffset(9, 6), ZIndex = z }), 3, 4)
	return b
end

-- The glow with rays behind a picture: the GlowRays texture tinted `color`, or (until it is uploaded) six
-- soft bands crossing at the centre.
function Premium.glow(parent: Instance, color: Color3, props: { [string]: any }): GuiObject
	local image = Icons.image("GlowRays")
	local g: GuiObject
	if image then
		g = new("ImageLabel", { Name = "Glow", BackgroundTransparency = 1, Image = image, ImageColor3 = color, ImageTransparency = 0.15, Parent = parent })
	else
		g = new("Frame", { Name = "Glow", BackgroundTransparency = 1, Parent = parent })
		for i = 0, 5 do
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 22), Rotation = i * 30,
				BackgroundColor3 = color, BackgroundTransparency = 0.8, BorderSizePixel = 0, Parent = g,
			}, { new("UIGradient", { Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
			}) }) })
		end
	end
	for k, v in props do
		(g :: any)[k] = v
	end
	return g
end

return Premium
