--!strict
-- The windows' building blocks (client; owner references 2026-10-15, round 2: "premium, square, no
-- edges"). Everything is square (no rounded corners), with a thick dark outline:
--   * ShopUi.bevel: a button's 3D look: a lighter top half and a darker bottom edge;
--   * ShopUi.button: a square bevelled button at a ShopLayout rect, popping only as much as its rect allows;
--   * ShopUi.giftIcon / ShopUi.price: what goes on the gift and R$ buttons (a white gift drawn from frames;
--     the white Robux icon with a dark outline before the price, bold white text);
--   * ShopUi.caption: the small line under a buy button ("1 Seed", "Forever");
--   * ShopUi.tag: the red "New!" tag;
--   * ShopUi.speckles: little white sparkles scattered over a card's art;
--   * ShopUi.studs: the classic Roblox studs over a frame (the uploaded Studs texture, tiled; small
--     square studs drawn from frames until it is uploaded).
local Icons = require(script.Parent:WaitForChild("Icons"))
local ShopLayout = require(script.Parent:WaitForChild("ShopLayout"))

local ShopUi = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
ShopUi.INK = Color3.fromRGB(16, 18, 26)
ShopUi.FONT = Enum.Font.FredokaOne

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
	inst.Parent = props.Parent
	return inst
end
ShopUi.new = new

-- Bold white text with a dark outline `stroke` thick.
function ShopUi.label(parent: Instance, stroke: number, props: { [string]: any }): TextLabel
	local l = new("TextLabel", { BackgroundTransparency = 1, Font = ShopUi.FONT, TextScaled = true, TextColor3 = WHITE, Parent = parent })
	new("UIStroke", { Thickness = stroke, Color = ShopUi.INK, LineJoinMode = Enum.LineJoinMode.Round, Parent = l })
	for k, v in props do
		(l :: any)[k] = v
	end
	return l
end

-- The 3D look over a square button (or any frame): its top half lighter, a darker strip along its bottom,
-- a thin light line at its very top. Overlays only, so the button's colour may change later (disabled, ...).
function ShopUi.bevel(f: GuiObject, z: number?)
	local zi = z or f.ZIndex
	new("Frame", { Name = "BevelTop", Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = WHITE, BackgroundTransparency = 0.74, BorderSizePixel = 0, ZIndex = zi, Parent = f })
	new("Frame", { Name = "BevelLine", Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = WHITE, BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = zi, Parent = f })
	new("Frame", {
		Name = "BevelEdge", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0.16, 0),
		BackgroundColor3 = BLACK, BackgroundTransparency = 0.62, BorderSizePixel = 0, ZIndex = zi, Parent = f,
	})
end

-- A square bevelled button at `p` (a ShopLayout rect) on `parent`. It pops on hover as much as `p.pop`. The
-- caller connects its Activated.
function ShopUi.button(parent: Instance, p: ShopLayout.Placed, color: Color3, z: number): TextButton
	local b = new("TextButton", {
		Name = if p.kind == "gift" then "Gift" else "Buy", Position = UDim2.fromOffset(p.x, p.y), Size = UDim2.fromOffset(p.w, p.h),
		BackgroundColor3 = color, BorderSizePixel = 0, Text = "", AutoButtonColor = true, ZIndex = z, Parent = parent,
	})
	new("UIStroke", { Thickness = ShopLayout.BUTTON_STROKE, Color = ShopUi.INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
	ShopUi.bevel(b)
	if p.pop > 1 then
		b:SetAttribute("PopScale", p.pop)
	else
		b:SetAttribute("NoPop", true)
	end
	return b
end

-- A white gift drawn on `b` (lid, box, a ribbon in the button's colour, a bow), outlined.
function ShopUi.giftIcon(b: GuiObject, ribbon: Color3)
	local z = b.ZIndex
	local icon = new("Frame", {
		Name = "GiftIcon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.66, 0.66), ZIndex = z, Parent = b,
	})
	local function piece(x: number, y: number, w: number, h: number, color: Color3, rot: number?, stroke: boolean?)
		local f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h), Rotation = rot or 0,
			BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z, Parent = icon,
		})
		if stroke ~= false then
			new("UIStroke", { Thickness = 2, Color = ShopUi.INK, LineJoinMode = Enum.LineJoinMode.Round, Parent = f })
		end
	end
	piece(0.33, 0.14, 0.26, 0.2, WHITE, 40) -- the bow
	piece(0.67, 0.14, 0.26, 0.2, WHITE, -40)
	piece(0.5, 0.68, 0.78, 0.52, WHITE) -- the box
	piece(0.5, 0.34, 0.96, 0.22, WHITE) -- the lid
	piece(0.5, 0.68, 0.16, 0.52, ribbon, 0, false) -- the ribbon over them
	piece(0.5, 0.34, 0.16, 0.22, ribbon, 0, false)
end

-- What a buy button says: with `robux`, the white Robux icon (a dark copy behind it for an outline) and
-- then the price; "R$ 1,600" in words while the icon isn't uploaded. Returns the text label.
function ShopUi.price(b: GuiObject, text: string, robux: boolean): TextLabel
	local z = b.ZIndex
	local h = b.Size.Y.Offset
	local image = if robux then Icons.image("Robux") else nil
	local left = 12
	if image then
		local s = math.floor(h * 0.62)
		local holder = new("Frame", {
			Name = "RobuxIcon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, -1),
			Size = UDim2.fromOffset(s, s), ZIndex = z, Parent = b,
		})
		new("ImageLabel", { -- the outline: a dark copy, a little bigger, behind
			Name = "Outline", BackgroundTransparency = 1, Image = image, ImageColor3 = ShopUi.INK, ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 1), Size = UDim2.new(1, 6, 1, 6), ZIndex = z, Parent = holder,
		})
		new("ImageLabel", {
			Name = "Icon", BackgroundTransparency = 1, Image = image, ImageColor3 = WHITE, ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = holder,
		})
		left = 14 + s + 6
	elseif robux then
		text = "R$ " .. text
	end
	return ShopUi.label(b, 3, {
		Name = "Label", Text = text, Position = UDim2.new(0, left, 0, 7), Size = UDim2.new(1, -(left + 12), 1, -16), ZIndex = z,
	})
end

-- The small caption under a placed buy button.
function ShopUi.caption(parent: Instance, p: ShopLayout.Placed, z: number): TextLabel?
	local r = p.captionRect
	if not r or not p.caption then
		return nil
	end
	return ShopUi.label(parent, 2, {
		Name = "Caption", Text = p.caption, Position = UDim2.fromOffset(r.x, r.y), Size = UDim2.fromOffset(r.w, r.h), ZIndex = z,
	})
end

-- The red "New!" tag (square, a thick dark red border, bold white words). Returns its words (for relief).
function ShopUi.tag(parent: Instance, text: string, position: UDim2, size: UDim2, z: number): TextLabel
	local tag = new("Frame", {
		Name = "Tag", Position = position, Size = size, BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = z, Parent = parent,
	}, {
		new("UIStroke", { Thickness = 4, Color = Color3.fromRGB(90, 6, 10), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 40, 40), Color3.fromRGB(205, 0, 12)) }),
	})
	new("Frame", { Name = "Shine", Size = UDim2.fromScale(1, 0.45), BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = z, Parent = tag })
	return ShopUi.label(tag, 3, { Name = "Words", Text = text, Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 1, -10), ZIndex = z + 1 })
end

-- `count` little sparkles over a card (a cross of two thin bars and a dot), placed by `seed` so a card
-- looks the same on every render. Kept to the card's upper part, away from its buttons.
function ShopUi.speckles(card: GuiObject, seed: number, count: number, z: number)
	local rng = Random.new(seed)
	for i = 1, count do
		local s = rng:NextInteger(6, 16)
		local x, y = rng:NextNumber(0.04, 0.96), rng:NextNumber(0.05, 0.6)
		local t = rng:NextNumber(0.2, 0.55)
		local holder = new("Frame", {
			Name = "Speck", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y),
			Size = UDim2.fromOffset(s, s), Rotation = if i % 2 == 0 then 45 else 0, ZIndex = z, Parent = card,
		})
		for _, size in { UDim2.new(1, 0, 0, 2), UDim2.new(0, 2, 1, 0) } do
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = size, BackgroundColor3 = WHITE,
				BackgroundTransparency = t, BorderSizePixel = 0, ZIndex = z, Parent = holder,
			})
		end
	end
end

-- Studs over `f`: the classic Roblox studded plastic every HUD element wears (owner 2026-10-15: "one
-- consistent stud size everywhere"). One style for all: the uploaded Studs texture (Config.ICONS.Studs: one
-- grey stud with a light rim and a dark lower edge on a clear tile) tiled STUD_CELL px apart at STUD_FADE,
-- tinted a light shade of `color` (the frame's own colour; white when it changes later, see paintStuds) so
-- the studs read as raised bumps of the same plastic. While the texture's id is 0, small square studs drawn
-- from frames instead. The studs take `f`'s rounded corners (a UICorner of the same radius) and sit at `z`
-- (default `f`'s ZIndex): make them before the frame's words so they stay under them. `fade` (default
-- STUD_FADE): fainter, only behind small words that need it.
ShopUi.STUD_CELL = 18 -- px between studs (the windows' title bar size), everywhere
ShopUi.STUD_FADE = 0.62 -- the texture's transparency
ShopUi.STUD_TINT = 0.55 -- how far the studs' tint is lightened from the frame's colour toward white

function ShopUi.studTint(color: Color3?): Color3
	return if color then color:Lerp(WHITE, ShopUi.STUD_TINT) else WHITE
end

function ShopUi.studs(f: GuiObject, color: Color3?, fade: number?, z: number?): GuiObject
	local cell = ShopUi.STUD_CELL
	local transparency = fade or ShopUi.STUD_FADE
	local zi = z or f.ZIndex
	local tint = ShopUi.studTint(color)
	local corner = f:FindFirstChildOfClass("UICorner")
	local image = Icons.image("Studs")
	local layer: GuiObject
	if image then
		layer = new("ImageLabel", {
			Name = "Studs", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = image, ImageTransparency = transparency,
			ImageColor3 = tint, ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(cell, cell), ZIndex = zi, Parent = f,
		})
	else
		-- enough squares for the frame's design size: its offsets, or (sized by scale) its size on screen
		-- once it has one, else the biggest window's
		local ok, abs = pcall(function()
			return f.AbsoluteSize
		end)
		local w = math.max(f.Size.X.Offset, if ok then abs.X else 0, if f.Size.X.Scale > 0 then ShopLayout.MAX_W else 0, cell)
		local h = math.max(f.Size.Y.Offset, if ok then abs.Y else 0, if f.Size.Y.Scale > 0 then ShopLayout.MAX_H else 0, cell)
		layer = new("Frame", { Name = "Studs", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ClipsDescendants = true, ZIndex = zi, Parent = f }, {
			new("UIGridLayout", { CellSize = UDim2.fromOffset(cell * 0.5, cell * 0.5), CellPadding = UDim2.fromOffset(cell * 0.5, cell * 0.5) }),
			new("UIPadding", { PaddingLeft = UDim.new(0, cell * 0.25), PaddingTop = UDim.new(0, cell * 0.25) }),
		})
		for _ = 1, math.min(math.ceil(w / cell) * math.ceil(h / cell), 2500) do
			new("Frame", { BackgroundColor3 = tint, BackgroundTransparency = 1 - (1 - transparency) * 0.45, BorderSizePixel = 0, ZIndex = zi, Parent = layer })
		end
	end
	if corner then
		corner:Clone().Parent = layer -- the frame's own rounding (ShopUi itself makes nothing round)
	end
	return layer
end

-- The hotbar's slots (owner reference 2026-10-15): small square dark see-through slots with a thin darker
-- outline, the slot's number small and white in the top-left corner, the item drawn as a clean picture
-- filling the slot (no name, no coloured background); the selected slot gets a white outline. The HUD's
-- Bat (slot 1) and Planting.client's seed slot (2) both use it. Returns the number label.
ShopUi.SLOT = 72 -- px, square
ShopUi.SLOT_COLOR = Color3.fromRGB(18, 20, 28)
ShopUi.SLOT_FADE = 0.4

function ShopUi.slot(b: GuiButton, number: string): TextLabel
	b.Size = UDim2.fromOffset(ShopUi.SLOT, ShopUi.SLOT)
	b.BackgroundColor3 = ShopUi.SLOT_COLOR
	b.BackgroundTransparency = ShopUi.SLOT_FADE
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	if b:IsA("TextButton") then
		b.Text = ""
	end
	new("UIStroke", { Name = "Outline", Thickness = 2, Color = BLACK, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
	return ShopUi.label(b, 2, { Name = "Key", Text = number, Size = UDim2.fromOffset(16, 18), Position = UDim2.fromOffset(5, 3), ZIndex = 4 })
end

-- Paints slot `b` (ShopUi.slot) selected (a white outline) or not.
function ShopUi.selectSlot(b: GuiObject, selected: boolean)
	local stroke = b:FindFirstChild("Outline") :: UIStroke?
	if stroke then
		stroke.Color = if selected then WHITE else BLACK
		stroke.Thickness = if selected then 3 else 2
		stroke.Transparency = if selected then 0 else 0.3
	end
end

-- Re-tints `f`'s studs (ShopUi.studs) when the frame's colour changes (the windows' title bar, a toggle).
function ShopUi.paintStuds(f: GuiObject, color: Color3?)
	local layer = f:FindFirstChild("Studs")
	if layer and layer:IsA("ImageLabel") then
		layer.ImageColor3 = ShopUi.studTint(color)
	elseif layer then
		for _, s in layer:GetChildren() do
			if s:IsA("Frame") then
				s.BackgroundColor3 = ShopUi.studTint(color)
			end
		end
	end
end

return ShopUi
