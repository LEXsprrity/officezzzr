-- The fixed remote contract. Everything else (pickup, planting, removing) goes through ProximityPrompts.
--   client -> server: RequestBuy(itemId), RequestUseItem(itemId)
--     RequestBuy ids: "PlotUpgrade" and "Trail:<id>" (money), "Product:<name>" (developer products,
--       Robux), "Pass:<name>" (gamepasses)
--     RequestUseItem ids: "Bat", "Seed:<bagKey>" (plant from the seed bag), "Equip:<trailId>"
--   client -> server: SellPlants(slots) (a list of plant slots, sold at the SELL stall; PlotService checks)
--   server -> client: StatsUpdate(stats), LootEvent(kind, data), IncomePopup(amount, position)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = folder
	return r
end

local Net = {
	RequestBuy = remote("RequestBuy"),
	RequestUseItem = remote("RequestUseItem"),
	SellPlants = remote("SellPlants"),
	StatsUpdate = remote("StatsUpdate"),
	LootEvent = remote("LootEvent"),
	IncomePopup = remote("IncomePopup"),
}

folder.Parent = ReplicatedStorage

function Net.toast(player: Player, text: string, color: string?)
	Net.LootEvent:FireClient(player, "Toast", { text = text, color = color })
end

return Net
