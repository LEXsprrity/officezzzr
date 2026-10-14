-- The fixed remote contract. Pickup and removing go through ProximityPrompts.
--   client -> server: RequestBuy(itemId), RequestUseItem(itemId)
--     RequestBuy ids: "PlotUpgrade", "TreadmillUpgrade" and "Trail:<id>" (money), "Product:<name>"
--       (developer products, Robux), "Pass:<name>" (gamepasses)
--     RequestUseItem ids: "Bat", "Seed:<bagKey>" (plant from the seed bag), "Equip:<trailId>"
--   client -> server: SellPlants(slots) (a list of plant slots, sold at the SELL stall; PlotService checks)
--   client -> server: PlantSeed(position, bagKey?) (plant the carried seed, or a bagged one, on your own dirt
--     bed at `position`, from the planting preview; PlotService.plantAt checks it all)
--   server -> client: LootEvent "PlaceSeed" { key, zone, rarity, name } (the Seeds menu's Plant button: show the
--     preview for that bagged seed)
--   client -> server: ClaimReward(kind) ("Gift": the Free Gift window's CLAIM button; RewardService checks)
--   server -> client: StatsUpdate(stats), LootEvent(kind, data), IncomePopup(amount, position)
--     LootEvent "Announce" { text, color } goes to every client (Net.announce)
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
	PlantSeed = remote("PlantSeed"),
	ClaimReward = remote("ClaimReward"),
	StatsUpdate = remote("StatsUpdate"),
	LootEvent = remote("LootEvent"),
	IncomePopup = remote("IncomePopup"),
}

folder.Parent = ReplicatedStorage

function Net.toast(player: Player, text: string, color: string?)
	Net.LootEvent:FireClient(player, "Toast", { text = text, color = color })
end

-- A message for the whole server (every client shows it), e.g. a Legendary from the last zones.
function Net.announce(text: string, color: string?)
	Net.LootEvent:FireAllClients("Announce", { text = text, color = color })
end

return Net
