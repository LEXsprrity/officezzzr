-- A guard's body, built on its invisible HumanoidRootPart: the zone's model from the assets folder (the
-- owner's rigged pets, Guard_<Name>) or, without one, the blocky giant. Everything is welded to the root so
-- it moves with the chase. GuardService builds the rest (Humanoid, status label) around it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Assets = require(script.Parent:WaitForChild("Assets"))

local GuardBody = {}

function GuardBody.weldPart(model: Model, root: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Shape = shape or Enum.PartType.Block
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.Massless = true
	p.CFrame = root.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
	p.Parent = model
	return p
end
local weldPart = GuardBody.weldPart

-- The blocky giant's body, welded to the root, with a few zone-specific bits. Returns its eyes.
function GuardBody.procedural(model: Model, root: BasePart, zone: Config.Zone, hip: number): { BasePart }
	local S = Config.GUARD_SCALE
	local c = zone.guardColor
	local dark = c:Lerp(Color3.new(0, 0, 0), 0.35)
	weldPart(model, root, "Body", Vector3.new(4, 4, 3) * S, CFrame.new(0, 0.5 * S, 0), c)
	weldPart(model, root, "Head", Vector3.new(3, 2.5, 2.5) * S, CFrame.new(0, 3.5 * S, -0.3 * S), c)
	local eyes: { BasePart } = {}
	for _, x in { -0.7, 0.7 } do
		table.insert(eyes, weldPart(model, root, "Eye", Vector3.new(0.7, 0.15, 0.2) * S, CFrame.new(x * S, 3.8 * S, -1.6 * S), Color3.new(0, 0, 0)))
	end
	for _, x in { -1, 1 } do
		weldPart(model, root, "Leg", Vector3.new(1.4 * S, hip, 1.4 * S), CFrame.new(x * S, -S - hip / 2, 0), dark)
		weldPart(model, root, "Arm", Vector3.new(1.2, 3.5, 1.2) * S, CFrame.new(x * 2.6 * S, 0.3 * S, 0), dark)
	end

	if zone.id == "Desert" then
		weldPart(model, root, "Tail", Vector3.new(1, 1, 4) * S, CFrame.new(0, 2.5 * S, 2.5 * S) * CFrame.Angles(math.rad(-40), 0, 0), dark)
		weldPart(model, root, "Stinger", Vector3.one * S, CFrame.new(0, 4.5 * S, 3.5 * S), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
	elseif zone.id == "Jungle" or zone.id == "Spirit" then
		weldPart(model, root, "Snout", Vector3.new(2, 1.2, 2) * S, CFrame.new(0, 3.1 * S, -2.4 * S), c)
		weldPart(model, root, "Tail", Vector3.new(1.2, 1.2, 5) * S, CFrame.new(0, 0, 3.5 * S), dark)
		if zone.id == "Spirit" then
			for _, x in { -1, 1 } do
				weldPart(model, root, "Horn", Vector3.new(0.4, 1.6, 0.4) * S, CFrame.new(x * 0.9 * S, 5.2 * S, 0), Color3.fromRGB(255, 215, 0), Enum.Material.Neon)
			end
		end
	elseif zone.id == "Lava" then
		for i = 1, 4 do
			weldPart(model, root, "Magma", Vector3.one * 0.9 * S, CFrame.new((i - 2.5) * 0.9 * S, 1.2 * S, -1.55 * S), Color3.fromRGB(255, 140, 20), Enum.Material.Neon)
		end
	elseif zone.id == "Snow" then
		weldPart(model, root, "Fur", Vector3.new(4.4, 1.2, 3.4) * S, CFrame.new(0, 2.5 * S, 0), Color3.new(1, 1, 1), Enum.Material.Fabric)
	elseif zone.id == "Space" then
		weldPart(model, root, "Antenna", Vector3.new(0.2, 2, 0.2) * S, CFrame.new(0, 5.5 * S, 0), c)
		weldPart(model, root, "AntennaTip", Vector3.one * 0.6 * S, CFrame.new(0, 6.5 * S, 0), Color3.fromRGB(255, 255, 120), Enum.Material.Neon, Enum.PartType.Ball)
	end
	return eyes
end

-- Whether `part` already hangs off another part of `body` by a joint of its own (a rigged pet's MeshParts
-- by their Motor6Ds to the bone host).
local function heldByJoint(part: BasePart, body: Instance): boolean
	for _, j in part:GetChildren() do
		if j:IsA("JointInstance") and j.Enabled and j.Part1 == part and j.Part0 and j.Part0 ~= part and j.Part0:IsDescendantOf(body) then
			return true
		end
	end
	return false
end

-- Unanchors `body` (a placed model) and joins it to `root`: each part that isn't already held by a joint
-- of the model gets a WeldConstraint to the root. A rigged pet keeps its own Motor6Ds (bone host ->
-- MeshPart), so only its bone host is welded: its skinned meshes bind to the host's Bones through those
-- Motor6Ds, inside the pet's Model. (A WeldConstraint, or a path through a part of another Model like the
-- guard's root, doesn't bind skinning: the meshes would stay in their bind pose however the Bones move.)
function GuardBody.attach(body: Instance, root: BasePart)
	local loose = {}
	for _, d in body:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			if not heldByJoint(d, body) then
				table.insert(loose, d)
			end
		end
	end
	for _, d in loose do
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = d
		w.Parent = d
	end
	for _, d in body:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
end

-- A body from the assets folder (slot Guard_<Name>, e.g. Guard_GiantTurtle), if there is one, on the
-- ground under the invisible root, facing the root's front. The zone bosses are the owner's rigged pets
-- (tools/export_bosses.luau): they keep their exported size and stand on their own ground point (Pivot),
-- and every client poses their Bones by code (BossRigs + GuardAnimator.client), from the guard's "Rig"
-- attribute and the body's rest bounds (BodyMin/BodyMax, root-ground space). Any other model is fitted to
-- about the blocky giant's size and stays in its saved pose. Either way it is joined to the root (attach)
-- so it moves with the chase, and an invisible "Head" at its top carries the state label. Returns whether
-- there was a usable model, and the rig's name.
function GuardBody.fromAsset(model: Model, root: BasePart, zone: Config.Zone, hip: number): (boolean, string?)
	local slot = "Guard_" .. string.gsub(zone.guard, "%s", "")
	if not Assets.get(slot) then
		return false
	end
	local S = Config.GUARD_SCALE
	local ground = root.CFrame * CFrame.new(0, -(hip + root.Size.Y / 2), 0)
	local body = Assets.place(slot, model, ground, Vector3.new(10, 7.75, 10) * S)
	if not body then
		return false
	end
	local lo, hi = Assets.bounds(body, ground)
	local top = if hi then hi.Y else 7.75 * S
	local rig = body:GetAttribute("BossRig")
	if type(rig) == "string" and lo and hi then
		model:SetAttribute("Rig", rig)
		model:SetAttribute("BodyMin", lo)
		model:SetAttribute("BodyMax", hi)
	else
		rig = nil
	end
	GuardBody.attach(body, root)
	local head = weldPart(model, root, "Head", Vector3.new(3, 2.5, 2.5) * S, root.CFrame:ToObjectSpace(ground * CFrame.new(0, top - 1.25 * S, 0)), zone.guardColor)
	head.Transparency = 1
	return true, rig :: string?
end

return GuardBody
