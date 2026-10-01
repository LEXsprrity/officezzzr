-- RequestBuy / RequestUseItem handlers. Every request is rate-limited, type-checked and validated
-- against server state; the client only says what it wants. Also seed packs (money) and the Robux
-- ProcessReceipt for pack bundles.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sessions = require(script.Parent:WaitForChild("Sessions"))
local Shop = require(script.Parent:WaitForChild("Shop"))
local SpeedService = require(script.Parent:WaitForChild("SpeedService"))
local GuardService = require(script.Parent:WaitForChild("GuardService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))

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

	if string.sub(itemId, 1, 8) == "Product:" then
		local product = Config.DEVELOPER_PRODUCTS[string.sub(itemId, 9)]
		if not product then
			return
		end
		if product.id == 0 then
			Net.toast(player, `{product.label}: coming soon!`, "red")
		else
			MarketplaceService:PromptProductPurchase(player, product.id)
		end
		return
	end

	if string.sub(itemId, 1, 5) == "Pack:" then
		local now = os.clock()
		if now < (s.cooldowns.Pack or 0) then
			return
		end
		s.cooldowns.Pack = now + Config.PACK_COOLDOWN
		local ok, msg, result, pack = Shop.buyPack(s.profile, itemId, os.time(), roll01)
		if not ok or not result or not pack then
			Net.toast(player, msg, "red")
			return
		end
		Sessions.pushFull(s)
		Net.LootEvent:FireClient(player, "PackRoll", { packId = pack.id, name = pack.name, zone = pack.zone, featured = pack.featured, results = { result } })
		return
	end

	local ok, msg = Shop.buy(s.profile, itemId, s.income * Sessions.moneyMult(s))
	if not ok then
		Net.toast(player, msg, "red")
		return
	end
	if itemId == "Speed25" or itemId == "SpeedMax" then
		SpeedService.refresh(s)
	elseif itemId == "Slot" then
		PlotService.refreshSlots(s)
	end
	Sessions.pushFull(s)
	Net.LootEvent:FireClient(player, "Bought", { itemId = itemId, label = msg })
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

	local count = s.profile.items[itemId] or 0
	if count <= 0 then
		Net.toast(player, "You don't have any of those. Check the Shop!", "red")
		return
	end

	if itemId == "SleepDust" then
		local guard = GuardService.dust(player)
		if not guard then
			Net.toast(player, "Get close to a sleeping guard to use Sleep Dust.", "red")
			return
		end
		s.profile.items.SleepDust = count - 1
		Net.LootEvent:FireClient(player, "Dusted", { guard = guard, seconds = Config.SLEEP_DUST_EXTRA })
	elseif Config.POTIONS[itemId] then
		local def = Config.POTIONS[itemId]
		s.profile.items[itemId] = count - 1
		local t = os.time()
		s.profile.potions[def.stat] = math.max(t, s.profile.potions[def.stat] or 0) + def.seconds
		Net.LootEvent:FireClient(player, "Potion", { itemId = itemId, label = def.label })
	else
		return
	end
	Sessions.pushFull(s)
end

----------------------------------------------------------------------------------------------------
-- Robux: developer products (featured pack bundles)
----------------------------------------------------------------------------------------------------
local function productNameById(productId: number): string?
	for name, product in Config.DEVELOPER_PRODUCTS do
		if product.id ~= 0 and product.id == productId then
			return name
		end
	end
	return nil
end

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
-- Anything else returns NotProcessedYet and Roblox delivers the receipt again later.
local function processReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local name = productNameById(receiptInfo.ProductId)
	if not name then
		warn(`[ShopService] receipt for unknown developer product {receiptInfo.ProductId}`)
	end
	local s = waitForSession(receiptInfo.PlayerId, 15)
	local confirm, status, rolls, pack = Shop.processReceipt(if s then s.profile else nil, name, tostring(receiptInfo.PurchaseId), os.time(), roll01, function()
		local save = ShopService.save
		return s ~= nil and save ~= nil and save(s)
	end)
	if s and status == "granted" and rolls and pack and s.player.Parent then
		Sessions.pushFull(s)
		Net.LootEvent:FireClient(s.player, "PackRoll", { packId = pack.id, name = pack.name, zone = pack.zone, featured = true, results = rolls })
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
	-- Potions expiring changes multipliers; refresh clients once a second when that happens.
	task.spawn(function()
		while true do
			task.wait(1)
			local t = os.time()
			for _, player in Players:GetPlayers() do
				local s = Sessions.get(player)
				if s then
					for stat, expiry in s.profile.potions do
						if expiry <= t then
							s.profile.potions[stat] = nil
							Sessions.pushFull(s)
							Net.toast(player, `Your {stat} potion wore off.`)
						end
					end
				end
			end
		end
	end)
end

return ShopService
