-- The VIP gamepass's looks (its x1.25 money and Speed are in Config.passMoneyMult / passSpeedMult): a gold
-- relief "VIP" badge just over the owner's head (Shared/VipBadge; the HUD has no VIP badge any more, owner
-- 2026-10-15), and the player's VIP attribute, which VipChat.client reads to put a
-- gold [VIP] tag in front of their chat messages. Both are set
-- only here, on the server, from Sessions.passes (ShopService: UserOwnsGamePassAsync /
-- PromptGamePassPurchaseFinished).
-- The owner (Config.OWNER_USER_IDS) gets a red OWNER badge and an [OWNER] chat tag instead (owner 2026-10-16:
-- "make a owner tag for me ... instead of the vip one"), with or without the pass.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local VipBadge = require(Shared:WaitForChild("VipBadge"))

local VipService = {}

VipService.TAG = "VipTag" -- the BillboardGui's name, under the character's Head
VipService.ATTRIBUTE = "VIP" -- on the Player
VipService.OWNER_TAG = "OwnerTag"
VipService.OWNER_ATTRIBUTE = "Owner" -- on the Player
VipService.GOLD = VipBadge.GOLD
-- Sized in studs (the BillboardGui's Size in scale), so it shrinks with distance like the head under it,
-- and only seen up close: owner playtest, "it floats too high and looks huge".
VipService.SIZE = Vector2.new(2.3, 2.3 / VipBadge.ASPECT)
VipService.OFFSET = 1.45 -- studs from the Head's centre: its bottom just clears the top of the head
VipService.MAX_DISTANCE = 60

function VipService.isOwner(player: Player): boolean
	return table.find(Config.OWNER_USER_IDS, player.UserId) ~= nil
end

-- The tag over a head: like a name tag, just above it. The OWNER one is wider (a longer word), as tall.
function VipService.buildTag(head: BasePart, owner: boolean?): BillboardGui
	local style = if owner then VipBadge.OWNER else VipBadge.VIP
	local gui = Instance.new("BillboardGui")
	gui.Name = if owner then VipService.OWNER_TAG else VipService.TAG
	gui.Size = UDim2.fromScale(VipService.SIZE.Y * style.aspect, VipService.SIZE.Y)
	gui.StudsOffset = Vector3.new(0, VipService.OFFSET, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = VipService.MAX_DISTANCE
	gui.ClipsDescendants = false -- (the outline and the dropped copy reach a little past it)
	gui.ResetOnSpawn = false
	gui.Adornee = head
	VipBadge.build(gui, style)
	gui.Parent = head
	return gui
end

-- Puts the right tag on `char`: OWNER for the owner, VIP for a player who owns VIP, else none. Safe to
-- call again.
function VipService.dress(char: Model?, owns: boolean, owner: boolean?)
	local head = char and char:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	for name, want in { [VipService.TAG] = owns and not owner, [VipService.OWNER_TAG] = owner == true } do
		local old = head:FindFirstChild(name)
		if want and not old then
			VipService.buildTag(head, name == VipService.OWNER_TAG)
		elseif not want and old then
			old:Destroy()
		end
	end
end

-- After the server learned what `player` owns (join, or a purchase): the chat attribute and the head tag.
function VipService.apply(player: Player, owns: boolean)
	local owner = VipService.isOwner(player)
	player:SetAttribute(VipService.ATTRIBUTE, if owns then true else nil)
	player:SetAttribute(VipService.OWNER_ATTRIBUTE, if owner then true else nil)
	VipService.dress(player.Character, owns, owner)
end

return VipService
