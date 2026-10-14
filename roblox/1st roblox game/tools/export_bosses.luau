-- Exports the owner's bought rigged pets (models/bosses/Pets.rbxl, Workspace.PetTemplates: one Model per
-- pet, skinned MeshParts + Bones under a "RootPart") into the zone guardians' slots, assets/Guard_<Name>.rbxm,
-- with BossRigs.BY_ZONE picking the pet for each zone. Each asset is a single Model holding only the pet's
-- MeshParts (with their SurfaceAppearances) and its RootPart with the Bones; the kit's
-- AnimationController, saved animations and poses, Motor6Ds and helper parts are dropped (the game
-- poses the Bones by code: BossRigs + GuardAnimator.client). It is:
--   * scaled by the profile's `scale` (part sizes and bone offsets alike), lowered by its `drop`;
--   * placed with the RootPart's ground point at the origin, front = -Z, anchored and non-colliding;
--   * tagged BossRig (the pet), RigScale, Pivot = (0, 0, 0) (Assets.place puts that point, not the
--     bottom centre of its bounds, at the guard's feet), KeepScale = true and Source.
-- The meshes keep the seller's mesh asset ids. Run from the game folder:
--   lune run tools/export_bosses.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local H = require("../tests/harness")
local Config = H.shared("Config")
local BossRigs = H.shared("BossRigs")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local SOURCE = "models/bosses/Pets.rbxl"
local KEEP = { "MeshPart", "Bone", "SurfaceAppearance", "Decal", "Texture" }

local function kept(d: any, host: any): boolean
	if d == host then
		return true
	end
	for _, class in KEEP do
		if d.ClassName == class then
			return true
		end
	end
	return false
end

local function export(zone: any, profile: any, source: any): (any, string)
	local s, drop = profile.scale, (profile.drop or 0) * profile.scale
	local model = roblox.Instance.new("Model")
	model.Name = "Guard_" .. string.gsub(zone.guard, "%s", "")
	for _, child in source:GetChildren() do
		child:Clone().Parent = model
	end
	local host = model:FindFirstChild("RootPart")
	assert(host and host:IsA("BasePart"), `{profile.pet} has no RootPart`)
	local hostCF = host.CFrame
	assert((hostCF.Rotation.LookVector - Vector3.new(0, 0, -1)).Magnitude < 1e-3 and hostCF.UpVector.Y > 0.999, `{profile.pet}: its RootPart is turned`)

	for _, d in model:GetDescendants() do
		if d.Parent ~= nil and not kept(d, host) then
			d:Destroy()
		end
	end

	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	local meshes = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local rel = hostCF:Inverse() * d.CFrame
			d.Size *= s
			d.CFrame = CFrame.new(rel.Position * s - Vector3.new(0, drop, 0)) * rel.Rotation
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			if d.Transparency < 1 then
				meshes += 1
				local c, e = d.CFrame, d.Size / 2
				local r, u, l = c.RightVector, c.UpVector, c.LookVector
				local ext = Vector3.new(
					math.abs(r.X) * e.X + math.abs(u.X) * e.Y + math.abs(l.X) * e.Z,
					math.abs(r.Y) * e.X + math.abs(u.Y) * e.Y + math.abs(l.Y) * e.Z,
					math.abs(r.Z) * e.X + math.abs(u.Z) * e.Y + math.abs(l.Z) * e.Z
				)
				lo, hi = lo:Min(c.Position - ext), hi:Max(c.Position + ext)
			end
		elseif d:IsA("Bone") then
			d.CFrame = CFrame.new(d.CFrame.Position * s) * d.CFrame.Rotation
		end
	end
	host.Transparency = 1
	model.PrimaryPart = host

	model:SetAttribute("BossRig", profile.pet)
	model:SetAttribute("RigScale", s)
	model:SetAttribute("Pivot", Vector3.zero)
	model:SetAttribute("KeepScale", true)
	model:SetAttribute("Source", SOURCE .. ": " .. profile.pet)
	local size = hi - lo
	return model, string.format("%-8s %-22s %-15s scale %.2f  %2d meshes  %.1f wide x %.1f tall x %.1f long (front %.1f, back %.1f)",
		zone.id, model.Name, profile.pet, s, meshes, size.X, hi.Y, size.Z, -lo.Z, hi.Z)
end

local place = roblox.deserializePlace(fs.readFile(SOURCE))
local folder = place:GetService("Workspace"):FindFirstChild("PetTemplates")
assert(folder, `{SOURCE} has no Workspace.PetTemplates`)
for _, zone in Config.ZONES do
	local key = BossRigs.BY_ZONE[zone.id]
	local profile = BossRigs.PROFILES[key]
	assert(profile, `no boss profile for {zone.id}`)
	local source = folder:FindFirstChild(profile.pet)
	assert(source and source:IsA("Model"), `{SOURCE}: no PetTemplates.{profile.pet}`)
	local model, line = export(zone, profile, source)
	fs.writeFile(`assets/{model.Name}.rbxm`, roblox.serializeModel({ model }))
	print(line)
end
