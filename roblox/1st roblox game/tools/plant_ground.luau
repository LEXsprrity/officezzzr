-- Sits a plant model on the ground by its base (owner 2026-10-16: the Legendary Aetheris floated). The pack's
-- models carry an invisible base disc named "PrimaryPart" where the plant meets the ground; a few leaves or
-- berries are rotated meshes whose box reaches below it, so grounding by the lowest box left those plants
-- hanging in the air (Aetheris ~2 studs when full-grown). Moves every part down so the base disc's bottom is
-- at y = 0, and gives it a Pivot attribute (its ground point, the origin) so the game stands it on that point
-- instead of the bottom of its box (Assets.fitClone). The swords (Sword attribute) are left alone: their
-- blade is meant to go into the ground.
-- Used by tools/export_plants.luau, and by tools/ground_plants.luau on the exported assets.
local roblox = require("@lune/roblox")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local PlantGround = {}

PlantGround.MIN_GAP = 0.05 -- studs: closer than this is already on the ground

local function bottomOf(p: any): number
	local c, s = p.CFrame, p.Size
	return c.Position.Y - (math.abs(c.RightVector.Y) * s.X / 2 + math.abs(c.UpVector.Y) * s.Y / 2 + math.abs(c.LookVector.Y) * s.Z / 2)
end

-- Returns how far the model was lowered (0 if it already stood on its base, or has none).
function PlantGround.apply(model: any): number
	if model:GetAttribute("Sword") then
		return 0
	end
	local base = model:FindFirstChild("PrimaryPart")
	if not base or not base:IsA("BasePart") or base.Transparency < 1 then
		return 0
	end
	local gap = bottomOf(base)
	local lowered = 0
	if gap > PlantGround.MIN_GAP then
		local down = CFrame.new(0, -gap, 0)
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				p.CFrame = down * p.CFrame
			end
		end
		lowered = gap
	end
	-- a box reaching below the base: stand it on the base, not on that box
	local lowest = math.huge
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			lowest = math.min(lowest, bottomOf(p))
		end
	end
	if lowest < -PlantGround.MIN_GAP then
		model:SetAttribute("Pivot", Vector3.new(0, 0, 0))
	end
	return lowered
end

return PlantGround
