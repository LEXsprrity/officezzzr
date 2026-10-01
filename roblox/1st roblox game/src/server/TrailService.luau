-- The equipped trail as a visual: a Trail between two Attachments on the HumanoidRootPart, coloured
-- per tier. Made on the server so every player sees it (the character replicates). Main re-applies it
-- on every CharacterAdded (respawn); ShopService re-applies it when the equipped trail changes. The
-- Speed gain multiplier itself is Config.trailMult, applied in SpeedService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local TrailService = {}

local NAMES = { "SeedTrail", "SeedTrailTop", "SeedTrailBottom" }
local HALF_HEIGHT = 1 -- the ribbon spans 2 studs, about the torso; the root part is 2 tall

-- (Re)builds the trail on `char`'s HumanoidRootPart. Returns the Trail, or nil if there is no root yet.
function TrailService.apply(char: Model?, trailId: string): Trail?
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	for _, name in NAMES do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local def = Config.trailById(trailId) or Config.trailById(Config.DEFAULT_TRAIL) :: Config.Trail
	local tier = table.find(Config.TRAILS, def) or 1

	local top = Instance.new("Attachment")
	top.Name = "SeedTrailTop"
	top.Position = Vector3.new(0, HALF_HEIGHT, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "SeedTrailBottom"
	bottom.Position = Vector3.new(0, -HALF_HEIGHT, 0)
	bottom.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = "SeedTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = Config.trailColors(def)
	trail.Lifetime = 0.35 + 0.07 * tier -- better trails stream a little longer
	trail.MinLength = 0.1
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15) })
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	trail.LightEmission = if tier >= 5 then 0.8 else 0.4
	trail.LightInfluence = 0.3
	trail.FaceCamera = true
	trail.Enabled = true
	trail.Parent = root
	return trail
end

return TrailService
