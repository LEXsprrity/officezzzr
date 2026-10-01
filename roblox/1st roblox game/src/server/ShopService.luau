-- RequestBuy / RequestUseItem handlers. Every request is rate-limited, type-checked and validated
-- against server state; the client only says what it wants. Money buys trails and plot upgrades;
-- everything else is Robux: the developer product prompt (gated) and ProcessReceipt (always grants what
-- was paid for), plus the gamepasses.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sessions = require(script.Parent:WaitForChild("Sessions"))
local Shop = require(script.Parent:WaitForChild("Shop"))
local SpeedService = require(script.Parent:WaitForChild("SpeedService"))
local GuardService = require(script.Parent:WaitForChild("GuardService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local TrailService = require(script.Parent:WaitForChild("TrailService"))

local ShopService = {}

local REQUESTS_PER_SECOND = 8
local rng = Random.new()
local function roll01(): number
	return rng:NextNumber()
end

-- Set by Main: persists a session now, returning whether it reached the DataStore.
ShopService.save = nil :: ((s: Sessions.Session) -> boolean)?

local function validId(itemId: any): boolean
	return type(itemId) == "string" and #itemId > 0 and #itemId <= 32
end

local function passByName(name: string)
	return (Config.GAMEPASSES :: any)[name]
end

local function grantPass(s: Sessions.Session, name: string)
	if s.passes[name] then
		return
	end
	s.passes[name] = true
	if name == "ExtraSlots" then
		PlotService.refreshSlots(s)
	end
	Sessions.pushFull(s)
end

function ShopService.checkPasses(s: Sessions.Session)
	for name, pass in Config.GAMEPASSES do
		if pass.id ~= 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, s.player.UserId, pass.id)
			if ok and owns then
				s.passes[name] = true
			end
		end
	end
end

-- The equipped trail changed: rebuild the visual and tell the client.
local function trailChanged(s: Sessions.Session)
	TrailService.apply(s.player.Character, s.profile.equippedTrail)
	Sessions.pushFull(s)
end

local function onBuy(player: Player, itemId: any)
	local s = Sessions.get(player)
	if not s or not validId(itemId) or not Sessions.allowRequest(s, REQUESTS_PER_SECOND) then
		return
	end

	if string.sub(itemId, 1, 5) == "Pass:" then
		local pass = passByName(string.sub(itemId, 6))
		if not pass then
			return
		end
		if pass.id == 0 then
			Net.toast(player, `{pass.label}: gamepass not set up yet (stub)`, "red")
		else
			MarketplaceService:PromptGamePassPurchase(player, pass.id)
		end
		return
	end

	-- Robux: "Product:<name>". We only open the Robux prompt here; ProcessReceipt grants.
	if string.sub(itemId, 1, 8) == "Product:" then
		local name = string.match(itemId, "^Product:(%a%w*)$")
		if not name then
			return
		end
		local product, why = Shop.canPrompt(s.profile, name)
		if not product then
			Net.toast(player, why or "Unknown product", "red")
			return
		end
		MarketplaceService:PromptProductPurchase(player, product.id)
		return
	end

	-- Money: the plot upgrade and "Trail:<id>". Anything else is refused by Shop.buy (Robux only).
	if itemId == "PlotUpgrade" then
		PlotService.upgrade(player)
		return
	end
	local ok, msg = Shop.buy(s.profile, itemId)
	if not ok then
		Net.toast(player, msg, "red")
		return
	end
	trailChanged(s) -- a trail is the only other money item; buying one equips it
	Net.LootEvent:FireClient(player, "Bought", { itemId = itemId, label = `{msg} (x{Sessions.speedMult(s)} Speed gain)` })
end

local function onUse(player: Player, itemId: any)
	local s = Sessions.get(player)
	if not s or not validId(itemId) or not Sessions.allowRequest(s, REQUESTS_PER_SECOND) then
		return
	end
	local now = os.clock()

	if itemId == "Bat" then
		if now < (s.cooldowns.Bat or 0) then
			return
		end
		s.cooldowns.Bat = now + Config.BAT_COOLDOWN
		local hit = GuardService.batHit(player)
		Net.LootEvent:FireClient(player, "Bat", { hit = hit, cooldown = Config.BAT_COOLDOWN })
		return
	end

	if string.sub(itemId, 1, 5) == "Seed:" then -- plant a seed from the bag (PlotService validates)
		PlotService.plantFromBag(player, string.sub(itemId, 6))
		return
	end

	if string.sub(itemId, 1, 6) == "Equip:" then -- equip an owned trail
		local ok, msg = Shop.equipTrail(s.profile, string.sub(itemId, 7))
		if not ok then
			Net.toast(player, msg, "red")
			return
		end
		trailChanged(s)
		Net.toast(player, `🏃 {msg} equipped: x{Sessions.speedMult(s)} Speed gain`, "blue")
		return
	end

	if itemId ~= "SleepDust" then -- the only consumable
		return
	end
	local count = s.profile.items.SleepDust or 0
	if count <= 0 then
		Net.toast(player, "You don't have any of those. Check the Shop!", "red")
		return
	end
	local guard = GuardService.dust(player)
	if not guard then
		Net.toast(player, "Get close to a sleeping guard to use Sleep Dust.", "red")
		return
	end
	s.profile.items.SleepDust = count - 1
	Net.LootEvent:FireClient(player, "Dusted", { guard = guard, seconds = Config.SLEEP_DUST_EXTRA })
	Sessions.pushFull(s)
end

----------------------------------------------------------------------------------------------------
-- Robux: developer products (Config.DEVELOPER_PRODUCTS)
----------------------------------------------------------------------------------------------------
-- Pending receipts are delivered as the player joins, often before their profile has loaded.
local function waitForSession(userId: number, seconds: number): Sessions.Session?
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			return nil
		end
		local s = Sessions.get(player)
		if s then
			return s
		end
		task.wait(0.5)
	end
	return nil
end

-- Grant once per PurchaseId (the id is stored in the profile), save, and only then confirm.
-- Anything else returns NotProcessedYet and Roblox delivers the receipt again later. A receipt that
-- arrives is always granted (even past the bag's soft cap): the player paid.
local function processReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local name = Config.productById(receiptInfo.ProductId)
	if not name then
		warn(`[ShopService] receipt for unknown developer product {receiptInfo.ProductId}`)
	end
	local s = waitForSession(receiptInfo.PlayerId, 15)
	-- The income the HUD shows (live, with day/night, plot level and 2x Money): Money products pay
	-- minutes of it, and a pack that can't fit the bag pays seconds of it.
	local income = if s then s.income * Sessions.moneyMult(s) else 0
	local confirm, status, grant = Shop.processReceipt(if s then s.profile else nil, name, tostring(receiptInfo.PurchaseId), income, roll01, function()
		local save = ShopService.save
		return s ~= nil and save ~= nil and save(s)
	end)
	if s and status == "granted" and grant and s.player.Parent then
		local kind = grant.product.kind
		if kind == "Speed" then
			SpeedService.refresh(s)
		elseif kind == "Trail" then
			TrailService.apply(s.player.Character, s.profile.equippedTrail)
		end
		Sessions.pushFull(s)
		local pack = grant.pack
		if pack and grant.roll then
			Net.LootEvent:FireClient(s.player, "PackRoll", { packId = pack.id, name = pack.name, zone = pack.zone, result = grant.roll })
		elseif pack then
			Net.toast(s.player, `🎒 Your seed bag is full, so your {pack.name} paid {Format.money(grant.compensation)} instead.`, "gold")
		else
			Net.LootEvent:FireClient(s.player, "Bought", { itemId = "Product:" .. grant.name, label = grant.label })
		end
	end
	return if confirm then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
end

function ShopService.init()
	Net.RequestBuy.OnServerEvent:Connect(onBuy)
	Net.RequestUseItem.OnServerEvent:Connect(onUse)
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		if not purchased then
			return
		end
		local s = Sessions.get(player)
		if not s then
			return
		end
		for name, pass in Config.GAMEPASSES do
			if pass.id == passId then
				grantPass(s, name)
			end
		end
	end)
end

return ShopService
