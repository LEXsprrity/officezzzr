--!strict
-- Pure purchase rules: validate against the profile, charge, apply. Prices come from Config.priceOf,
-- the same function the client uses to label buttons.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Shop = {}

type Profile = {
	money: number,
	speed: number,
	speedMultTier: number,
	treadmillTier: number,
	slots: number,
	items: { [string]: number },
}

-- Returns (ok, message). `income` is the player's current $/s (potion prices scale with it).
function Shop.buy(p: Profile, itemId: string, income: number): (boolean, string)
	local view = {
		money = p.money,
		speed = p.speed,
		speedMultTier = p.speedMultTier,
		treadmillTier = p.treadmillTier,
		slots = p.slots,
		income = income,
	}
	local price, label = Config.priceOf(itemId, view)
	if price == nil then
		return false, if label then `{label}` else "Unknown item"
	end
	if price <= 0 and itemId == "SpeedMax" then
		return false, "Not enough money"
	end
	if p.money < price then
		return false, "Not enough money"
	end

	p.money -= price
	if itemId == "Speed25" or itemId == "SpeedMax" then
		p.speed += price / Config.PRICE_PER_SPEED
	elseif itemId == "SpeedMult" then
		p.speedMultTier += 1
	elseif itemId == "Treadmill" then
		p.treadmillTier += 1
	elseif itemId == "Slot" then
		p.slots += 1
	else -- consumables: Sleep Dust and potions
		p.items[itemId] = (p.items[itemId] or 0) + 1
	end
	return true, label or itemId
end

return Shop
