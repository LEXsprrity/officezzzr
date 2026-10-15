--!strict
-- The Shop's Speed and Money card art (client; owner reference 2026-10-15): the picture grows with the
-- pack. Level 1 is one sneaker (one bill stack), then two, a pile of three, bigger piles, a cloth sack
-- full of them, a bigger sack spilling over and, for the biggest pack, a treasure chest overflowing with
-- them. The items are the Speed / Money icons (icons/, Shared/Icons) layered, turned and scaled.
-- The sack and the chest are drawn from frames like a sticker (owner playtest 2026-10-15: "they look
-- bad"): every piece has a thick dark outline, a lit gradient, highlights and shade. The sack: a round
-- cloth body with folds, a pinched neck tied with a twisted rope and a bow, a flared open mouth the items
-- spill out of. The chest: an open domed lid behind the heap, a dark inside, a wooden box with planks,
-- gold rims, straps, rivets and a lock, gold coins (Money) and sparkles around it.
-- `plan` is pure (the tests check that the art only ever grows); `build` puts a plan on a card.
local Icons = require(script.Parent:WaitForChild("Icons"))

local ShopArt = {}

ShopArt.LEVELS = 8
ShopArt.BOX_W, ShopArt.BOX_H = 200, 130 -- the design box the plans are drawn in

-- One icon: its centre `x` (from the box's middle) and `y` (from its top), `size` and `rot` in degrees.
-- `front`: drawn in front of the sack / chest (an item spilling out) instead of inside it.
export type Item = { x: number, y: number, size: number, rot: number, front: boolean? }
export type Plan = { items: { Item }, holder: ("sack" | "chest")?, holderScale: number }

local function item(x: number, y: number, size: number, rot: number, front: boolean?): Item
	return { x = x, y = y, size = size, rot = rot, front = front }
end

local PLANS: { Plan } = {
	{ holderScale = 1, items = { item(0, 64, 112, -8) } },
	{ holderScale = 1, items = { item(-30, 72, 96, -14), item(28, 58, 96, 10) } },
	{ holderScale = 1, items = { item(-40, 80, 86, -16), item(40, 80, 86, 14), item(0, 52, 92, -4) } },
	{ holderScale = 1, items = {
		item(-56, 90, 78, -18), item(0, 94, 80, 6), item(56, 90, 78, 16), item(-26, 60, 80, -8), item(28, 56, 80, 10),
	} },
	{ holderScale = 1, items = {
		item(-60, 98, 76, -18), item(0, 100, 80, 6), item(60, 98, 76, 16), item(-30, 68, 78, -8), item(30, 64, 78, 10),
		item(0, 40, 76, -4), item(-84, 32, 42, -30), item(84, 26, 42, 28),
	} },
	{ holder = "sack", holderScale = 0.9, items = {
		item(-36, 50, 48, -26), item(36, 50, 48, 24), item(-18, 40, 52, -12), item(20, 38, 52, 14), item(0, 26, 54, 4), item(-50, 30, 36, -34), item(52, 26, 36, 30),
	} },
	{ holder = "sack", holderScale = 1, items = {
		item(-38, 46, 50, -26), item(38, 46, 50, 24), item(-20, 34, 54, -12), item(22, 32, 54, 14), item(0, 30, 58, 4), item(-54, 24, 38, -34), item(56, 20, 38, 30),
		item(-78, 108, 40, -30, true), item(80, 104, 40, 26, true),
	} },
	{ holder = "chest", holderScale = 1, items = {
		item(-54, 62, 46, -18), item(54, 62, 46, 18), item(-26, 54, 50, -10), item(28, 52, 50, 12), item(0, 46, 54, 4),
		item(-4, 30, 42, -6), item(-86, 112, 40, -26, true), item(88, 108, 40, 24, true),
	} },
}

-- The art level (1..LEVELS) of pack `i` of `n` (cheapest first): spread over the whole range, so the
-- cheapest is always one item and the dearest always the chest (8 Speed packs: 1..8; 5 Money packs:
-- 1, 3, 5, 6, 8).
function ShopArt.level(i: number, n: number): number
	if n <= 1 then
		return 1
	end
	return math.clamp(math.floor(1 + (i - 1) * (ShopArt.LEVELS - 1) / (n - 1) + 0.5), 1, ShopArt.LEVELS)
end

function ShopArt.plan(level: number): Plan
	return PLANS[math.clamp(level, 1, ShopArt.LEVELS)]
end

----------------------------------------------------------------------------------------------------
-- Building
----------------------------------------------------------------------------------------------------
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local INK = Color3.fromRGB(25, 25, 35)
local GOLD, GOLD_DARK = Color3.fromRGB(255, 214, 60), Color3.fromRGB(214, 128, 18)
local WOOD, WOOD_DARK = Color3.fromRGB(176, 102, 48), Color3.fromRGB(104, 52, 24)
local ROPE = Color3.fromRGB(226, 172, 84)

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

-- A lit vertical (or `rot`) gradient from `top` to `bottom`; the frame's own colour is white under it.
local function lit(top: Color3, bottom: Color3, rot: number?): Instance
	return new("UIGradient", { Rotation = rot or 90, Color = ColorSequence.new(top, bottom) })
end

type Piece = {
	color: Color3?, -- solid colour (white when `grad` paints it)
	grad: Instance?, -- a UIGradient over a white frame
	corner: UDim?, -- UDim.new(0.5, 0): an oval
	stroke: number?, -- outline thickness (design pixels before scaling)
	strokeColor: Color3?,
	transparency: number?,
	rot: number?,
	z: number,
	name: string?,
	clip: boolean?,
}

-- Draws the holders in holder units: x from the box's middle, y up from the box's bottom (negative),
-- scaled by `hk` (pixels per unit). Returns a function placing one piece.
local function painter(box: Frame, hk: number)
	return function(parent: Instance?, x: number, y: number, w: number, h: number, p: Piece): Frame
		local scaled = parent ~= nil -- a child piece: x, y, w, h are scales of its parent
		local f = new("Frame", {
			Name = p.name or "Piece", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = if scaled then UDim2.fromScale(x, y) else UDim2.new(0.5, x * hk, 1, y * hk),
			Size = if scaled then UDim2.fromScale(w, h) else UDim2.fromOffset(w * hk, h * hk),
			BackgroundColor3 = if p.grad then WHITE else p.color or WHITE, BackgroundTransparency = p.transparency or 0,
			BorderSizePixel = 0, Rotation = p.rot or 0, ZIndex = p.z, ClipsDescendants = p.clip == true, Parent = parent or box,
		})
		if p.corner then
			new("UICorner", { CornerRadius = p.corner, Parent = f })
		end
		if p.stroke then
			new("UIStroke", {
				Thickness = math.max(1, p.stroke * hk), Color = p.strokeColor or INK, LineJoinMode = Enum.LineJoinMode.Round,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f,
			})
		end
		if p.grad then
			p.grad.Parent = f
		end
		return f
	end
end

local OVAL = UDim.new(0.5, 0)

-- A 4-point sparkle centred at (x, y) holder units, `s` long.
local function sparkle(draw: any, x: number, y: number, s: number, z: number)
	for _, rot in { 0, 90 } do
		draw(nil, x, y, s * 0.2, s, { color = WHITE, corner = OVAL, rot = rot, z = z, name = "Sparkle" })
	end
	draw(nil, x, y, s * 0.34, s * 0.34, { color = Color3.fromRGB(255, 250, 200), rot = 45, z = z, name = "Sparkle" })
end

-- A gold coin at (x, y), `s` across.
local function coin(draw: any, x: number, y: number, s: number, z: number)
	local c = draw(nil, x, y, s, s, { grad = lit(GOLD:Lerp(WHITE, 0.35), GOLD_DARK), corner = OVAL, stroke = 3, z = z, name = "Coin" })
	draw(c, 0.5, 0.5, 0.58, 0.58, { color = GOLD, corner = OVAL, stroke = 2, strokeColor = GOLD_DARK, z = z, name = "CoinRing" })
end

-- The cloth sack (`color`): its open mouth at about 100 units up, the items (z 3) inside it.
local function sack(box: Frame, hk: number, color: Color3, key: string)
	local draw = painter(box, hk)
	local dark = color:Lerp(BLACK, 0.45)
	-- a soft shadow on the ground
	draw(nil, 0, -4, 146, 16, { color = BLACK, transparency = 0.72, corner = OVAL, z = 1, name = "Shadow" })
	-- the open mouth's dark inside, behind the items
	draw(nil, 0, -90, 112, 28, { color = dark:Lerp(BLACK, 0.35), corner = OVAL, stroke = 4, z = 2, name = "Mouth" })
	-- the body: a round cloth bag, lit from the top left
	local body = draw(nil, 0, -40, 146, 78, {
		grad = lit(color:Lerp(WHITE, 0.45), color:Lerp(BLACK, 0.3), 60), corner = UDim.new(0.46, 0), stroke = 4.5, z = 4, name = "Sack",
	})
	draw(body, 0.72, 0.62, 0.5, 0.62, { color = BLACK, transparency = 0.8, corner = OVAL, rot = 18, z = 4, name = "Shade" })
	draw(body, 0.27, 0.34, 0.3, 0.2, { color = WHITE, transparency = 0.5, corner = OVAL, rot = -28, z = 4, name = "Highlight" })
	draw(body, 0.43, 0.2, 0.07, 0.11, { color = WHITE, transparency = 0.3, corner = OVAL, z = 4, name = "Glint" })
	for _, fold in { { 0.36, -14 }, { 0.64, 14 }, { 0.5, 0 } } do -- folds from the neck down
		draw(body, fold[1], 0.24, 0.025, 0.4, { color = dark, transparency = 0.35, corner = OVAL, rot = fold[2], z = 4, name = "Fold" })
	end
	-- a round patch on the front: "$" (Money) or the sneaker (Speed)
	local patch = draw(body, 0.5, 0.64, 0.3, 0.56, { grad = lit(color:Lerp(WHITE, 0.75), color:Lerp(WHITE, 0.35)), corner = OVAL, stroke = 3, z = 4, name = "Patch" })
	new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = patch })
	local image = Icons.image(key)
	if key == "Money" or not image then
		local mark = new("TextLabel", {
			Name = "Mark", BackgroundTransparency = 1, Size = UDim2.fromScale(0.86, 0.86), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
			Text = if key == "Money" then "$" else "S", TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = dark, ZIndex = 4, Parent = patch,
		})
		new("UIStroke", { Thickness = math.max(1, 2 * hk), Color = WHITE, Parent = mark })
	else
		new("ImageLabel", {
			Name = "Mark", BackgroundTransparency = 1, Size = UDim2.fromScale(0.8, 0.8), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Image = image, ScaleType = Enum.ScaleType.Fit, ZIndex = 4, Parent = patch,
		})
	end
	-- the pinched neck, then the flared lip of the mouth over the items
	draw(nil, 0, -78, 60, 18, { grad = lit(color:Lerp(WHITE, 0.2), color:Lerp(BLACK, 0.25)), corner = UDim.new(0, 8), stroke = 4, z = 5, name = "Neck" })
	local lip = draw(nil, 0, -82, 120, 17, { transparency = 1, clip = true, z = 6, name = "Lip" }) -- shows the lower half of the rim
	draw(lip, 0.5, 0, 0.94, 1.5, { grad = lit(color:Lerp(WHITE, 0.5), color:Lerp(WHITE, 0.1)), corner = OVAL, stroke = 4, z = 6, name = "Rim" })
	-- the twisted rope and its bow
	local twist = {}
	for i = 0, 9 do
		table.insert(twist, ColorSequenceKeypoint.new(i / 9, if i % 2 == 0 then ROPE:Lerp(WHITE, 0.35) else ROPE:Lerp(BLACK, 0.25)))
	end
	draw(nil, 0, -75, 72, 11, { grad = new("UIGradient", { Rotation = 0, Color = ColorSequence.new(twist) }), corner = OVAL, stroke = 3, z = 7, name = "Rope" })
	for _, side in { -1, 1 } do
		draw(nil, side * 12, -81, 20, 12, { grad = lit(ROPE:Lerp(WHITE, 0.3), ROPE:Lerp(BLACK, 0.2)), corner = OVAL, stroke = 3, rot = side * -28, z = 7, name = "Loop" })
		draw(nil, side * 7, -64, 6, 18, { grad = lit(ROPE:Lerp(WHITE, 0.2), ROPE:Lerp(BLACK, 0.25)), corner = OVAL, stroke = 3, rot = side * 16, z = 7, name = "RopeEnd" })
	end
	draw(nil, 0, -76, 12, 12, { grad = lit(ROPE:Lerp(WHITE, 0.4), ROPE:Lerp(BLACK, 0.2)), corner = OVAL, stroke = 3, z = 8, name = "Knot" })
	sparkle(draw, -80, -100, 20, 9)
	sparkle(draw, 82, -62, 14, 9)
end

-- The treasure chest: its open lid behind the heap, the box in front (z 5..), coins (Money) and sparkles.
local function chest(box: Frame, hk: number, key: string)
	local draw = painter(box, hk)
	draw(nil, 0, -4, 196, 18, { color = BLACK, transparency = 0.72, corner = OVAL, z = 1, name = "Shadow" })
	-- the lid, open behind the heap: a wooden dome with planks, gold straps and a gold trim
	local lid = draw(nil, 0, -94, 172, 66, { grad = lit(WOOD:Lerp(WHITE, 0.2), WOOD_DARK), corner = UDim.new(0.5, 0), stroke = 4, z = 2, name = "Lid" })
	draw(lid, 0.5, 0.5, 0.92, 0.82, { transparency = 1, corner = UDim.new(0.5, 0), stroke = 3.5, strokeColor = GOLD, z = 2, name = "Trim" })
	for _, x in { 0.24, 0.76 } do
		draw(lid, x, 0.5, 0.09, 1, { grad = lit(GOLD:Lerp(WHITE, 0.3), GOLD_DARK), stroke = 2.5, z = 2, name = "Strap" })
	end
	-- the dark inside, the items sit in it
	draw(nil, 0, -68, 172, 20, { grad = lit(Color3.fromRGB(40, 20, 12), Color3.fromRGB(90, 46, 22)), corner = UDim.new(0, 6), stroke = 3.5, z = 2, name = "Inside" })
	-- the box: planks, gold rims and straps with rivets, the lock
	local front = draw(nil, 0, -34, 186, 66, { grad = lit(WOOD:Lerp(WHITE, 0.12), WOOD_DARK), corner = UDim.new(0, 6), stroke = 4.5, z = 5, name = "Chest" })
	for _, y in { 0.42, 0.7 } do
		draw(front, 0.5, y, 1, 0.035, { color = WOOD_DARK:Lerp(BLACK, 0.3), transparency = 0.25, z = 5, name = "Plank" })
	end
	draw(front, 0.5, 0.3, 0.96, 0.12, { color = WHITE, transparency = 0.84, corner = OVAL, z = 5, name = "Grain" })
	draw(front, 0.5, 0.09, 1.02, 0.2, { grad = lit(GOLD:Lerp(WHITE, 0.35), GOLD_DARK), corner = UDim.new(0, 4), stroke = 3, z = 6, name = "Rim" })
	draw(front, 0.5, 0.94, 1.02, 0.14, { grad = lit(GOLD, GOLD_DARK), corner = UDim.new(0, 4), stroke = 3, z = 6, name = "Base" })
	for _, x in { 0.17, 0.83 } do
		local strap = draw(front, x, 0.52, 0.1, 1, { grad = lit(GOLD:Lerp(WHITE, 0.3), GOLD_DARK, 0), stroke = 3, z = 7, name = "Strap" })
		for _, y in { 0.36, 0.66 } do
			draw(strap, 0.5, y, 0.42, 0.09, { color = GOLD_DARK:Lerp(BLACK, 0.2), corner = OVAL, z = 7, name = "Rivet" })
		end
	end
	local lock = draw(front, 0.5, 0.42, 0.16, 0.52, { grad = lit(GOLD:Lerp(WHITE, 0.45), GOLD_DARK), corner = UDim.new(0, 5), stroke = 3, z = 8, name = "Lock" })
	draw(lock, 0.5, 0.42, 0.34, 0.24, { color = INK, corner = OVAL, z = 8, name = "Keyhole" })
	draw(lock, 0.5, 0.62, 0.14, 0.3, { color = INK, z = 8, name = "Keyhole" })
	if key == "Money" then
		coin(draw, -96, -10, 20, 10)
		coin(draw, -80, -6, 16, 10)
		coin(draw, 98, -8, 18, 10)
		coin(draw, -30, -72, 18, 4)
		coin(draw, 40, -76, 16, 4)
	end
	sparkle(draw, -92, -100, 24, 10)
	sparkle(draw, 92, -64, 18, 10)
	sparkle(draw, 30, -124, 14, 10)
end

export type Options = {
	key: string, -- the Icons key of the item ("Speed", "Money"; its emoji while the icon isn't uploaded)
	sackColor: Color3,
	zindex: number, -- the art's ZIndex on the card (its pieces are layered inside it)
}

-- Draws plan `level` in a box of `size` at `position` (top centre anchored) on `parent`. Returns the box.
function ShopArt.build(parent: Instance, level: number, position: UDim2, height: number, options: Options): Frame
	local plan = ShopArt.plan(level)
	local k = height / ShopArt.BOX_H
	local box = new("Frame", {
		Name = "Art", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = position,
		Size = UDim2.fromOffset(ShopArt.BOX_W * k, height), ZIndex = options.zindex, Parent = parent,
	})
	box:SetAttribute("Level", level)
	box:SetAttribute("Items", #plan.items)
	box:SetAttribute("Holder", plan.holder)
	local hk = k * plan.holderScale
	if plan.holder == "sack" then
		sack(box, hk, options.sackColor, options.key)
	elseif plan.holder == "chest" then
		chest(box, hk, options.key)
	end
	local image = Icons.image(options.key)
	for i, it in plan.items do
		local props = {
			Name = "Item" .. i, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, it.x * k, 0, it.y * k), Size = UDim2.fromOffset(it.size * k, it.size * k), Rotation = it.rot,
			-- inside a sack / chest: over its mouth / inside, under its front; spilled ones in front of it all
			ZIndex = if it.front then 9 elseif plan.holder then 3 else 1,
			Parent = box,
		}
		if image then
			props.Image, props.ScaleType = image, Enum.ScaleType.Fit
			new("ImageLabel", props)
		else
			props.Text, props.TextScaled, props.Font = (Icons.TOKENS[options.key] or { "?" })[1], true, Enum.Font.FredokaOne
			new("TextLabel", props)
		end
	end
	return box
end

return ShopArt
