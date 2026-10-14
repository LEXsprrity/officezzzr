-- The fixed remote contract. Pickup goes through ProximityPrompts.
--   client -> server: RequestBuy(itemId), RequestUseItem(itemId)
--     RequestBuy ids: "PlotUpgrade", "TreadmillUpgrade" and "Trail:<id>" (money), "Product:<name>"
--       (developer products, Robux), "Pass:<name>" (gamepasses)
--     RequestUseItem ids: "Bat", "Seed:<bagKey>" (plant from the seed bag), "Seed:inv:<id>" (plant a plant
--       from the inventory again), "Equip:<trailId>"
--   client -> server: SellPlants(slots, ids?) (plant slots and inventory ids, sold at the SELL stall;
--     PlotService checks)
--   client -> server: RemovePlant(slot) (the HUD Plants panel's Remove button: one of your own plants, from
--     anywhere, into your inventory, for no money; PlotService.removePlant rate-limits it, Inventory.take
--     checks it)
--   server -> client: StatsUpdate "catalog" (catalog[zone][rarity] = the flower model names the Index lists)
--   client -> server: PlantSeed(position, bagKey?) (plant the carried seed, a bagged one or an inventory plant
--     "inv:<id>" on your own dirt bed at `position`, from the planting preview; PlotService.plantAt checks it all)
--   server -> client: LootEvent "PlaceSeed" { key, zone, rarity, name, ghost, scale } (the Inventory's Plant
--     button or the hotbar's seed slot: show the ghost preview for that seed or plant: ReplicatedStorage
--     .PlantGhosts "Ghost_<zone>_<rarity>_<ghost>" at plant scale `scale`, what it will be when planted; a
--     seed's `key` may differ from the one asked for when an old seed got its gene; `name` never names a
--     seed's flower)
--   server -> client: LootEvent "Stored" { zone, rarity, mutation } (a seed brought home into the base went
--     to the seed bag)

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
	RemovePlant = remote("RemovePlant"),
	PlantSeed = remote("PlantSeed"),
	ClaimReward = remote("ClaimReward"),
	StatsUpdate = remote("StatsUpdate"),
	LootEvent = remote("LootEvent"),
	IncomePopup = remote("IncomePopup"),
}

-- Server -> client only. Any client can still fire them at the server: those calls are dropped here
-- (without a listener Roblox would queue every one of them and warn).
for _, r in { Net.StatsUpdate, Net.LootEvent, Net.IncomePopup } do
	r.OnServerEvent:Connect(function() end)
end

folder.Parent = ReplicatedStorage

function Net.toast(player: Player, text: string, color: string?)
	Net.LootEvent:FireClient(player, "Toast", { text = text, color = color })
end

-- A message for the whole server (every client shows it), e.g. a Legendary from the last zones.
function Net.announce(text: string, color: string?)
	Net.LootEvent:FireAllClients("Announce", { text = text, color = color })
end

return Net
