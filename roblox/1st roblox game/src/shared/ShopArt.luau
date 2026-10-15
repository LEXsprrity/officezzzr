--!strict
-- The Shop's Speed and Money card art (client; owner reference 2026-10-15): the picture grows with the
-- pack. Level 1 is one sneaker (one bill stack), then two, a pile of three, bigger piles, a sack full of
-- them, a bigger sack spilling over and, for the biggest pack, a gold treasure chest overflowing with them.
-- The items are the Speed / Money icons (icons/, Shared/Icons) layered, turned and scaled; the sack and
-- the chest are drawn from frames. `plan` is pure (the tests check that the art only ever grows); `build`
-- puts a plan on a card.
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
	{ holder = "sack", holderScale = 0.92, items = {
		item(-30, 52, 64, -22), item(0, 40, 70, 4), item(30, 52, 64, 22), item(-14, 32, 54, -10), item(18, 30, 54, 14),
	} },
	{ holder = "sack", holderScale = 1.05, items = {
		item(-36, 48, 62, -24), item(0, 36, 70, 4), item(36, 48, 62, 22), item(-14, 28, 54, -10), item(18, 26, 54, 14),
		item(-86, 104, 44, -30, true), item(86, 100, 44, 26, true),
	} },
	{ holder = "chest", holderScale = 1.05, items = {
		item(-50, 54, 60, -18), item(0, 46, 66, 4), item(50, 54, 60, 18), item(-24, 36, 54, -10), item(26, 34, 54, 12),
		item(0, 26, 46, -4), item(-88, 108, 42, -26, true), item(88, 104, 42, 24, true),
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
local INK = Color3.fromRGB(25, 25, 35)

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

local function outline(thickness: number): Instance
	return new("UIStroke", { Thickness = thickness, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

-- A sack (sackColor) whose open top is at `top` (box pixels): a round body, a white swoosh, a tied rim.
local function sack(box: Frame, k: number, top: number, color: Color3, z: number)
	local body = new("Frame", {
		Name = "Sack", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(150 * k, (ShopArt.BOX_H - top) * k + 8),
		BackgroundColor3 = WHITE, ZIndex = z + 1, Parent = box,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0.4, 0) }),
		outline(4),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(color:Lerp(WHITE, 0.4), color:Lerp(Color3.new(0, 0, 0), 0.25)) }),
	})
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.new(1, -16, 0, 16 * k), Rotation = -10,
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = z + 1, Parent = body,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	new("Frame", { -- the rim
		Name = "Rim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -((ShopArt.BOX_H - top) * k + 8)), Size = UDim2.fromOffset(160 * k, 22 * k),
		BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.35), ZIndex = z + 2, Parent = box,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }), outline(3) })
end

-- A gold treasure chest: the open lid behind the heap, the box (blue panels, gold bands, a lock) in front.
local GOLD, GOLD_DARK, CHEST_BLUE = Color3.fromRGB(255, 205, 50), Color3.fromRGB(205, 130, 20), Color3.fromRGB(40, 90, 210)
local function chest(box: Frame, k: number, z: number)
	local w, h = 176 * k, 70 * k
	new("Frame", { -- the lid, open behind the heap
		Name = "Lid", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -h + 6), Size = UDim2.fromOffset(w - 10, 52 * k),
		BackgroundColor3 = WHITE, ZIndex = z - 1, Parent = box,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 18) }),
		outline(4),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(CHEST_BLUE:Lerp(WHITE, 0.25), CHEST_BLUE:Lerp(Color3.new(0, 0, 0), 0.3)) }),
	})
	local front = new("Frame", {
		Name = "Chest", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = WHITE, ZIndex = z + 1, Parent = box,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 10) }),
		outline(4),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(GOLD:Lerp(WHITE, 0.3), GOLD_DARK) }),
	})
	for _, x in { 0.27, 0.73 } do -- blue panels between the gold bands
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.55), Size = UDim2.new(0.36, 0, 0.62, 0),
			BackgroundColor3 = CHEST_BLUE, ZIndex = z + 1, Parent = front,
		}, { new("UICorner", { CornerRadius = UDim.new(0, 6) }), outline(2) })
	end
	new("Frame", { -- the lock
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(22 * k, 26 * k),
		BackgroundColor3 = GOLD, ZIndex = z + 2, Parent = front,
	}, { new("UICorner", { CornerRadius = UDim.new(0, 5) }), outline(2) })
end

export type Options = {
	key: string, -- the Icons key of the item ("Speed", "Money"; its emoji while the icon isn't uploaded)
	sackColor: Color3,
	zindex: number, -- the art's lowest ZIndex (it uses zindex .. zindex + 3)
}

-- Draws plan `level` in a box of `size` at `position` (top centre anchored) on `parent`. Returns the box.
function ShopArt.build(parent: Instance, level: number, position: UDim2, height: number, options: Options): Frame
	local plan = ShopArt.plan(level)
	local k = height / ShopArt.BOX_H
	local z = options.zindex
	local box = new("Frame", {
		Name = "Art", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = position,
		Size = UDim2.fromOffset(ShopArt.BOX_W * k, height), ZIndex = z, Parent = parent,
	})
	box:SetAttribute("Level", level)
	box:SetAttribute("Items", #plan.items)
	box:SetAttribute("Holder", plan.holder)
	local hk = k * plan.holderScale
	if plan.holder == "sack" then
		sack(box, hk, 56, options.sackColor, z)
	elseif plan.holder == "chest" then
		chest(box, hk, z + 1)
	end
	local image = Icons.image(options.key)
	for i, it in plan.items do
		local props = {
			Name = "Item" .. i, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, it.x * k, 0, it.y * k), Size = UDim2.fromOffset(it.size * k, it.size * k), Rotation = it.rot,
			-- inside a sack / chest: behind its front, in front of the chest's lid; spilled ones in front of all
			ZIndex = if it.front then z + 3 elseif plan.holder then z + (if plan.holder == "chest" then 1 else 0) else z + 1,
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
