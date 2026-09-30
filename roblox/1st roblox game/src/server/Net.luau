-- The fixed remote contract. Everything else (pickup, planting, selling) goes through ProximityPrompts.
--   client -> server: RequestBuy(itemId), RequestUseItem(itemId)
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
	StatsUpdate = remote("StatsUpdate"),
	LootEvent = remote("LootEvent"),
	IncomePopup = remote("IncomePopup"),
}

folder.Parent = ReplicatedStorage

function Net.toast(player: Player, text: string, color: string?)
	Net.LootEvent:FireClient(player, "Toast", { text = text, color = color })
end

return Net
