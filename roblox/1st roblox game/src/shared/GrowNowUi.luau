-- The "Grow now" button (client): on a seedling's hover info (Client/Sprouts) and on its Plants panel card
-- (HUD). A square studded green button in the HUD's chunky style: "Grow now" in relief on the left, the
-- Robux icon and the price of the Grow Now product its time left calls for (Config.growNowProduct) on the
-- right. Pressing it asks the server for the prompt (RequestBuy "GrowNow:<plant id>"); the server picks
-- the product and checks the plant again (PlotService.promptGrowNow).
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(script.Parent:WaitForChild("Config"))
local Format = require(script.Parent:WaitForChild("Format"))
local ShopUi = require(script.Parent:WaitForChild("ShopUi"))
local UiFx = require(script.Parent:WaitForChild("UiFx"))

local GrowNowUi = {}

GrowNowUi.GREEN = Color3.fromRGB(105, 235, 25) -- the Shop's R$ green
GrowNowUi.COUNTDOWN = Color3.fromRGB(200, 255, 150)

-- Seconds a seedling ending at `sproutUntil` (server unix time) still has, by the synced server clock.
function GrowNowUi.left(sproutUntil: number?): number
	if type(sproutUntil) ~= "number" then
		return 0
	end
	return math.max(sproutUntil - workspace:GetServerTimeNow(), 0)
end

-- "2:31" (and "1:02:05" past an hour)
function GrowNowUi.clock(seconds: number): string
	local s = math.ceil(math.max(seconds, 0))
	if s >= 3600 then
		return string.format("%d:%02d:%02d", s // 3600, s % 3600 // 60, s % 60)
	end
	return Format.clock(s)
end

-- The product's price: its placeholder until the Dashboard price arrives (fetched once per id, pcall'd).
local prices: { [number]: number } = {}
local fetching: { [number]: boolean } = {}
function GrowNowUi.price(product: Config.DevProduct): number
	if product.id == 0 then
		return product.robux
	end
	if prices[product.id] then
		return prices[product.id]
	end
	if not fetching[product.id] then
		fetching[product.id] = true
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, product.id, Enum.InfoType.Product)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				prices[product.id] = info.PriceInRobux
			else
				fetching[product.id] = nil
			end
		end)
	end
	return product.robux
end

local requestBuy: RemoteEvent? = nil
function GrowNowUi.request(slot: number)
	requestBuy = requestBuy or ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestBuy") :: RemoteEvent
	;(requestBuy :: RemoteEvent):FireServer(`GrowNow:{slot}`)
end

-- A Grow now button for plant `slot`, `size` (offsets), on `parent`. Returns it and its update (call with
-- the seconds left: the price follows the product the time left calls for).
function GrowNowUi.button(parent: Instance, slot: number, size: UDim2, z: number?): (TextButton, (left: number) -> ())
	local zi = z or 1
	local b = ShopUi.new("TextButton", {
		Name = "GrowNow", Size = size, BackgroundColor3 = GrowNowUi.GREEN, BorderSizePixel = 0, Text = "", AutoButtonColor = true, ZIndex = zi, Parent = parent,
	}, { ShopUi.new("UIStroke", { Thickness = 3, Color = ShopUi.INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) })
	ShopUi.studs(b, GrowNowUi.GREEN, nil, zi)
	ShopUi.bevel(b, zi)
	local words = ShopUi.label(b, 3, {
		Name = "Words", Text = "Grow now", Position = UDim2.new(0, 8, 0, 6), Size = UDim2.new(0.56, -10, 1, -14),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = zi + 1,
	})
	UiFx.relief(words, 2, 3)
	local priceBox = ShopUi.new("Frame", {
		Name = "Price", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 0, 0),
		Size = UDim2.fromOffset(math.floor(size.X.Offset * 0.44), size.Y.Offset), ZIndex = zi + 1, Parent = b,
	})
	local priceLabel = ShopUi.price(priceBox, "", true)
	local prefix = if priceBox:FindFirstChild("RobuxIcon") then "" else "R$ " -- (in words until the icon is uploaded)
	b.Activated:Connect(function()
		GrowNowUi.request(slot)
	end)
	local function update(left: number)
		local _, product = Config.growNowProduct(left)
		b.Visible = product ~= nil
		if product then
			priceLabel.Text = prefix .. Format.commas(GrowNowUi.price(product))
		end
	end
	return b, update
end

return GrowNowUi
