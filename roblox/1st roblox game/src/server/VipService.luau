-- The VIP gamepass's looks (its x1.25 money and Speed are in Config.passMoneyMult / passSpeedMult): a gold
-- relief "VIP" tag over the owner's head, and the player's VIP attribute, which VipChat.client reads to put
-- a gold [VIP] tag in front of their chat messages. Both are set only here, on the server, from
-- Sessions.passes (ShopService: UserOwnsGamePassAsync / PromptGamePassPurchaseFinished).
local VipService = {}

VipService.TAG = "VipTag" -- the BillboardGui's name, under the character's Head
VipService.ATTRIBUTE = "VIP" -- on the Player
VipService.GOLD = Color3.fromRGB(255, 206, 40)
local INK = Color3.fromRGB(70, 38, 0) -- the outline and the dropped copy: a deep brown, so the gold glows

-- A relief label: a thick round outline, a bevel (light top, darker gold foot) and a dark copy dropped
-- behind it, like the world's other signs.
local function reliefLabel(parent: Instance, text: string): TextLabel
	local function label(name: string, color: Color3, offset: UDim2, z: number): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Position = offset
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = text
		l.TextColor3 = color
		l.ZIndex = z
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Color = INK
		stroke.Parent = l
		l.Parent = parent
		return l
	end
	label("Shadow", INK, UDim2.fromOffset(2, 4), 1)
	local main = label("Label", VipService.GOLD, UDim2.new(), 2)
	local bevel = Instance.new("UIGradient")
	bevel.Rotation = 90
	bevel.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(215, 140, 20)),
	})
	bevel.Parent = main
	return main
end

-- The tag over a head: sized in studs (it shrinks with distance like the head), above the Roblox name.
function VipService.buildTag(head: BasePart): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = VipService.TAG
	gui.Size = UDim2.fromScale(3.6, 1.3)
	gui.StudsOffset = Vector3.new(0, 3.1, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.ResetOnSpawn = false
	gui.Adornee = head
	reliefLabel(gui, "VIP")
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
