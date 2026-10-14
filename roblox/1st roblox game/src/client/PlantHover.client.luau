-- Plant info on demand: each plant's "Info" billboard (name + $/s, built by PlotService with Enabled = false)
-- shows only while the mouse is over that plant, or for TAP_SECONDS after a finger taps it. Local only.
-- Plant parts are CanQuery = false (they never block rays or clicks), so the pick is a ray against each
-- nearby plant's bounding box instead of Mouse.Target.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local PICK_HZ = 15
local PICK_RANGE = 80 -- studs from the camera (the billboard's MaxDistance is 60)
local TAP_SECONDS = 3

-- Info billboard -> its plant model
local infos: { [BillboardGui]: Model } = {}

local function consider(inst: Instance)
	if not inst:IsA("BillboardGui") or inst.Name ~= "Info" then
		return
	end
	local body = inst.Parent
	local model = body and body.Parent
	if model and model:IsA("Model") and string.match(model.Name, "^Plant_%d+$") then
		inst.Enabled = false
		infos[inst] = model
	end
end

for _, d in workspace:GetDescendants() do
	consider(d)
end
workspace.DescendantAdded:Connect(consider)
workspace.DescendantRemoving:Connect(function(inst)
	if inst:IsA("BillboardGui") then
		infos[inst] = nil
	end
end)

-- Distance along the ray to the box (cf, size), or nil if the ray misses it (slab test in box space).
local function hitBox(ray: Ray, cf: CFrame, size: Vector3): number?
	local o = cf:PointToObjectSpace(ray.Origin)
	local d = cf:VectorToObjectSpace(ray.Direction)
	local origin, dir, half = { o.X, o.Y, o.Z }, { d.X, d.Y, d.Z }, { size.X / 2, size.Y / 2, size.Z / 2 }
	local near, far = -math.huge, math.huge
	for i = 1, 3 do
		local oa, da, h = origin[i], dir[i], half[i]
		if math.abs(da) < 1e-6 then
			if oa < -h or oa > h then
				return nil
			end
		else
			local t1, t2 = (-h - oa) / da, (h - oa) / da
			near = math.max(near, math.min(t1, t2))
			far = math.min(far, math.max(t1, t2))
			if near > far then
				return nil
			end
		end
	end
	if far < 0 then
		return nil
	end
	return math.max(near, 0)
end

-- The Info billboard of the nearest plant the ray (from the camera) passes through, if any.
local function pick(camera: Camera, ray: Ray): BillboardGui?
	local eye = camera.CFrame.Position
	local best: BillboardGui?, bestT = nil, math.huge
	for gui, model in infos do
		if (model:GetPivot().Position - eye).Magnitude > PICK_RANGE then
			continue
		end
		local cf, size = model:GetBoundingBox()
		local t = hitBox(ray, cf, size)
		if t and t < bestT then
			best, bestT = gui, t
		end
	end
	return best
end

local hovered: BillboardGui? = nil
local tapped: BillboardGui? = nil
local tappedUntil = 0

local function refresh()
	if tapped and os.clock() > tappedUntil then
		tapped = nil
	end
	for gui in infos do
		local on = gui == hovered or gui == tapped
		if gui.Enabled ~= on then
			gui.Enabled = on
		end
	end
end

local pickWait = 0
RunService.RenderStepped:Connect(function(dt)
	pickWait -= dt
	if pickWait > 0 then
		return
	end
	pickWait = 1 / PICK_HZ
	-- Hover needs a mouse; on a touch-only device the last tap decides.
	local camera = workspace.CurrentCamera
	if camera and UserInputService.MouseEnabled then
		local mouse = UserInputService:GetMouseLocation() -- viewport coordinates (top bar included)
		hovered = pick(camera, camera:ViewportPointToRay(mouse.X, mouse.Y))
	else
		hovered = nil
	end
	refresh()
end)

UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processedByUI: boolean)
	local camera = workspace.CurrentCamera
	if processedByUI or not camera then
		return
	end
	tapped = pick(camera, camera:ScreenPointToRay(position.X, position.Y)) -- screen coordinates (below the top bar)
	tappedUntil = os.clock() + TAP_SECONDS
	refresh()
end)
