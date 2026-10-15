--!strict
-- Every on-screen announcement (client; owner 2026-10-15: "every announcement must look way better"): the
-- HUD's toast stack (HUD.client toast: errors, getting caught, offline earnings, day/night, the server-wide
-- Legendary announcements) and the "Lucky!" over a thief's head (Effects.client). One look for all:
--   * a square plate with a thick dark outline, in the toast's vivid colour (Toast.STYLES: red, gold, green,
--     blue, purple) with the HUD's studs over it (ShopUi.studs), a lighter top band (ShopUi.bevel) and a soft
--     shine sweeping across;
--   * a small icon on the left that says what it is about, chosen per message (Toast.ICONS: the sneaker for
--     Speed, cash for money, the gift for the Free Gift, the lock for errors, the star for a Legendary, a drawn
--     sun or moon for day and night), never guessed from the colour (owner 2026-10-15: "+25,000 Speed!" showed
--     the cash). Only red (errors: the lock) and purple (luck: the star) bring an icon by default;
--   * the words in big chunky white relief (UiFx.relief, a thick black outline);
--   * Toast.show pops and slides it in, holds, then fades it out (a CanvasGroup fades it all as one).
-- Server-wide announcements are `big`: taller, in gold, with a rainbow frame.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Icons = require(Shared:WaitForChild("Icons"))
local ShopUi = require(Shared:WaitForChild("ShopUi"))
local UiFx = require(Shared:WaitForChild("UiFx"))

local Toast = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local new = ShopUi.new

export type Style = { color: Color3, icon: string? }
-- Per colour name (what the server sends: Net.toast / Net.announce): the plate's colour and its default icon
-- (none for gold, green and blue: a reward or news names its own icon, Toast.ICONS).
Toast.STYLES = {
	red = { color = Color3.fromRGB(235, 50, 60), icon = "Lock" }, -- refusals and errors
	gold = { color = Color3.fromRGB(255, 180, 20), icon = nil }, -- rewards (money, Speed, the gift)
	green = { color = Color3.fromRGB(60, 200, 70), icon = nil },
	blue = { color = Color3.fromRGB(40, 150, 255), icon = nil }, -- news
	purple = { color = Color3.fromRGB(160, 75, 255), icon = "Star" }, -- luck
} :: { [string]: Style }
-- The icon per kind of message (what senders pass as `icon`): Icons keys, or "Sun" / "Moon" (drawn).
Toast.ICONS = {
	speed = "Speed", -- Speed gains (the Free Gift's +Speed, a speed item equipped)
	money = "Money", -- money (offline earnings, a pack paid out in cash)
	gift = "Gift", -- the Free Gift, gifting
	error = "Lock", -- refusals and errors
	legendary = "Star", -- server-wide Legendary announcements, luck
	day = "Sun",
	night = "Moon",
}
Toast.DEFAULT = "blue"
Toast.W, Toast.H = 540, 58 -- design pixels
Toast.BIG_W, Toast.BIG_H = 680, 78 -- server-wide announcements
Toast.RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 170, 40)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 235, 60)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 230, 110)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(60, 170, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 90, 255)),
})

export type Options = {
	color: string?, -- a Toast.STYLES name (default blue)
	icon: string?, -- an Icons key (Toast.ICONS), "Sun" or "Moon" (drawn); default: the style's; "" = none
	big: boolean?, -- a server-wide announcement: bigger, a rainbow frame
	seconds: number?, -- how long it holds (Toast.show; default 3)
}

-- The style for a colour name (an unknown one: the default).
function Toast.style(color: string?): Style
	return Toast.STYLES[color or ""] or Toast.STYLES[Toast.DEFAULT]
end

-- A drawn sun (a yellow disc with rays) or moon (a pale disc with a bite of the plate's colour out of it).
local function drawSky(parent: GuiObject, key: string, plate: Color3)
	if key == "Sun" then
		for i = 0, 3 do
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 0.16), Rotation = i * 45,
				BackgroundColor3 = Color3.fromRGB(255, 200, 30), BorderSizePixel = 0, ZIndex = 4, Parent = parent,
			}, { new("UIStroke", { Thickness = 2, Color = ShopUi.INK }) })
		end
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.62, 0.62),
			BackgroundColor3 = WHITE, ZIndex = 5, Parent = parent,
		}, {
			new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), -- the sun is round (art)
			new("UIStroke", { Thickness = 3, Color = ShopUi.INK }),
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 245, 140), Color3.fromRGB(255, 170, 20)) }),
		})
	else
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.8, 0.8),
			BackgroundColor3 = WHITE, ZIndex = 4, Parent = parent,
		}, {
			new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), -- the moon is round (art)
			new("UIStroke", { Thickness = 3, Color = ShopUi.INK }),
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 252, 215), Color3.fromRGB(230, 210, 120)) }),
		})
		new("Frame", { -- the bite: a disc of the plate's colour over its upper right
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.72, 0.32), Size = UDim2.fromScale(0.62, 0.62),
			BackgroundColor3 = plate:Lerp(WHITE, 0.15), ZIndex = 5, Parent = parent,
		}, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end
end

-- Builds the toast's plate (a Frame named "Toast", sized in design pixels) under `parent`, with `message`.
-- Returns the plate and its words.
function Toast.build(parent: Instance, message: string, options: Options?): (Frame, TextLabel)
	local o: Options = options or {}
	local style = Toast.style(o.color)
	local big = o.big == true
	local color = if big then Toast.STYLES.gold.color else style.color
	local w, h = if big then Toast.BIG_W else Toast.W, if big then Toast.BIG_H else Toast.H
	local stroke = if big then 6 else 4
	local plate = new("Frame", {
		Name = "Toast", Size = UDim2.fromOffset(w, h), BackgroundColor3 = WHITE, BorderSizePixel = 0, ClipsDescendants = true, Parent = parent,
	}, {
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(color:Lerp(WHITE, 0.2), color:Lerp(BLACK, 0.18)) }),
	})
	local outline = new("UIStroke", { Thickness = stroke, Color = ShopUi.INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = plate })
	if big then
		outline.Color = WHITE
		new("UIGradient", { Name = "Rainbow", Rotation = 20, Color = Toast.RAINBOW, Parent = outline }) -- the gold rainbow frame
	end
	ShopUi.studs(plate, color, nil, 1)
	ShopUi.bevel(plate, 1)
	-- a soft shine across it (Toast.show sweeps it)
	new("Frame", {
		Name = "Shine", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.15, 0), Size = UDim2.new(0, h, 1, 0), Rotation = 20,
		BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2, Parent = plate,
	}, { new("UIGradient", { Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(1, 1),
	}) }) })

	-- The icon on the left
	local key = if o.icon == "" then nil else (o.icon or (if big then "Star" else style.icon))
	local iconSize = h - 16
	local left = 14
	if key == "Sun" or key == "Moon" then
		drawSky(new("Frame", {
			Name = "Icon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, left, 0.5, 0),
			Size = UDim2.fromOffset(iconSize, iconSize), ZIndex = 4, Parent = plate,
		}), key, color)
		left += iconSize + 10
	elseif key then
		local image = Icons.image(key)
		if image then
			new("ImageLabel", {
				Name = "Icon", BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, left, 0.5, 0), Size = UDim2.fromOffset(iconSize, iconSize), ZIndex = 4, Parent = plate,
			})
			left += iconSize + 10
		end
	end

	local words = ShopUi.label(plate, if big then 4 else 3, {
		Name = "Words", Text = message, TextWrapped = true, Position = UDim2.fromOffset(left, 6), Size = UDim2.new(1, -(left + 14), 1, -14),
		TextXAlignment = if left > 14 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center, ZIndex = 5,
	})
	UiFx.relief(words, if big then 4 else 3, if big then 4 else 3)
	return plate, words
end

-- Shows a toast in `holder` (a list): it pops and slides in, holds `seconds`, then fades out as one and
-- goes. Returns its slot (the list's item).
function Toast.show(holder: Instance, message: string, options: Options?): Frame
	local o: Options = options or {}
	local big = o.big == true
	local w, h = if big then Toast.BIG_W else Toast.W, if big then Toast.BIG_H else Toast.H
	local slot = new("Frame", { Name = "ToastSlot", BackgroundTransparency = 1, Size = UDim2.fromOffset(w + 16, h + 16), Parent = holder })
	local group = new("CanvasGroup", {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -18), Size = UDim2.fromScale(1, 1),
		GroupTransparency = 1, Parent = slot,
	})
	local plate = Toast.build(group, message, o)
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	local pop = new("UIScale", { Scale = 0.6, Parent = group })
	local inInfo = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(group, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { GroupTransparency = 0 }):Play()
	TweenService:Create(group, inInfo, { Position = UDim2.fromScale(0.5, 0.5) }):Play()
	TweenService:Create(pop, inInfo, { Scale = 1 }):Play()
	local shine = plate:FindFirstChild("Shine") :: GuiObject
	TweenService:Create(shine, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.15), { Position = UDim2.fromScale(1.1, 0) }):Play()
	task.delay(o.seconds or 3, function()
		if not slot.Parent then
			return
		end
		local outInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(group, outInfo, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, -10) }):Play()
		TweenService:Create(pop, outInfo, { Scale = 0.9 }):Play()
		task.wait(0.45)
		slot:Destroy()
	end)
	return slot
end

return Toast
