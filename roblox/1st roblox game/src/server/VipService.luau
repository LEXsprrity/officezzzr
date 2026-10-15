-- The VIP gamepass's looks (its x1.25 money and Speed are in Config.passMoneyMult / passSpeedMult): a gold
-- relief "VIP" badge just over the owner's head (Shared/VipBadge, the same badge the owner sees by their
-- Speed and money: VipHudBadge.client), and the player's VIP attribute, which VipChat.client reads to put a
-- gold [VIP] tag in front of their chat messages and VipHudBadge.client to show the HUD badge. Both are set
-- only here, on the server, from Sessions.passes (ShopService: UserOwnsGamePassAsync /
-- PromptGamePassPurchaseFinished).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local VipBadge = require(Shared:WaitForChild("VipBadge"))

local VipService = {}

VipService.TAG = "VipTag" -- the BillboardGui's name, under the character's Head
VipService.ATTRIBUTE = "VIP" -- on the Player
VipService.GOLD = VipBadge.GOLD
-- Sized in studs (the BillboardGui's Size in scale), so it shrinks with distance like the head under it,
-- and only seen up close: owner playtest, "it floats too high and looks huge".
VipService.SIZE = Vector2.new(2.3, 2.3 / VipBadge.ASPECT)
VipService.OFFSET = 1.45 -- studs from the Head's centre: its bottom just clears the top of the head
VipService.MAX_DISTANCE = 60

-- The tag over a head: like a name tag, just above it.
function VipService.buildTag(head: BasePart): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = VipService.TAG
	gui.Size = UDim2.fromScale(VipService.SIZE.X, VipService.SIZE.Y)
	gui.StudsOffset = Vector3.new(0, VipService.OFFSET, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = VipService.MAX_DISTANCE
	gui.ClipsDescendants = false -- (the outline and the dropped copy reach a little past it)
	gui.ResetOnSpawn = false
	gui.Adornee = head
	VipBadge.build(gui)
	gui.Parent = head
	return gui
end

-- Puts the tag on `char` (or takes it off) for a player who owns VIP (or not). Safe to call again.
function VipService.dress(char: Model?, owns: boolean)
	local head = char and char:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local old = head:FindFirstChild(VipService.TAG)
	if owns and not old then
		VipService.buildTag(head)
	elseif not owns and old then
		old:Destroy()
	end
end

-- After the server learned what `player` owns (join, or a purchase): the chat attribute and the head tag.
function VipService.apply(player: Player, owns: boolean)
	player:SetAttribute(VipService.ATTRIBUTE, if owns then true else nil)
	VipService.dress(player.Character, owns)
end

return VipService
