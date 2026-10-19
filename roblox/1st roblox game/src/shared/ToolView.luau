-- A held Tool in 3D for the hotbar (client), like a Roblox tool icon: its visible parts cloned, anchored,
-- into a ViewportFrame, the long side laid diagonally (the grip bottom-left, the far end top-right), turned
-- a little toward the camera so it reads as 3D, and fitted to the frame. A still picture: no spin, like the
-- seed slot (Planting.client). The framing math (bounds, pose, distance) is pure, for the tests.
local ToolView = {}

ToolView.FOV = 30
ToolView.SLANT = math.rad(45) -- the long side, from bottom-left to top-right
ToolView.TURN = math.rad(20) -- the far end turned this much toward the camera
ToolView.FILL = 0.9 -- the tool's widest point reaches this share of the frame's half-width
ToolView.AMBIENT = Color3.fromRGB(190, 190, 196) -- bright enough that the shaded side isn't dark
ToolView.LIGHT = Color3.fromRGB(255, 250, 240)
ToolView.LIGHT_DIRECTION = Vector3.new(0.5, -1, -0.8) -- from over the camera's upper-left shoulder

export type Box = { cframe: CFrame, size: Vector3 }

-- The 8 corners of a box.
local function corners(box: Box): { Vector3 }
	local h = box.size / 2
	local out = {}
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				table.insert(out, box.cframe * Vector3.new(h.X * x, h.Y * y, h.Z * z))
			end
		end
	end
	return out
end

-- (min, max) of every corner of `boxes` (cframes in one shared frame, e.g. the Handle's).
function ToolView.bounds(boxes: { Box }): (Vector3, Vector3)
	local lo, hi = Vector3.one * math.huge, Vector3.one * -math.huge
	for _, box in boxes do
		for _, p in corners(box) do
			lo, hi = lo:Min(p), hi:Max(p)
		end
	end
	return lo, hi
end

-- The CFrame that takes the boxes' frame to the picture's: the bounds' centre to the origin, their longest
-- side onto the diagonal, pointing away from `grip` (where the hand holds, in the same frame) so the grip
-- end is bottom-left. The camera looks down -Z from +Z.
function ToolView.pose(lo: Vector3, hi: Vector3, grip: Vector3): CFrame
	local size, centre = hi - lo, (lo + hi) / 2
	local axes = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
	local long = if size.X >= size.Y and size.X >= size.Z then 1 elseif size.Y >= size.Z then 2 else 3
	local along, up = axes[long], axes[long % 3 + 1]
	if (grip - centre):Dot(along) > 0 then
		along = -along -- the grip is at the + end: the far end is the - one
	end
	local from = CFrame.fromMatrix(Vector3.zero, along, up)
	local d = CFrame.Angles(0, -ToolView.TURN, 0) * Vector3.new(math.cos(ToolView.SLANT), math.sin(ToolView.SLANT), 0)
	local facing = (Vector3.zAxis - d * d.Z).Unit -- toward the camera, square to the long side
	local to = CFrame.fromMatrix(Vector3.zero, d, facing:Cross(d))
	return to * from:Inverse() * CFrame.new(-centre)
end

-- How far the camera (looking down -Z at the origin, field of view `fov` degrees, a square frame) stands so
-- every point is in view, the outermost at `fill` of the half-width.
function ToolView.distance(points: { Vector3 }, fov: number, fill: number): number
	local t = math.tan(math.rad(fov) / 2) * fill
	local dist = 0
	for _, p in points do
		dist = math.max(dist, p.Z + math.max(math.abs(p.X), math.abs(p.Y)) / t)
	end
	return dist
end

export type Options = { size: UDim2?, position: UDim2?, zindex: number? }

-- A ViewportFrame named "ToolView" in `parent` showing `tool`, or nil when it has no Handle or nothing
-- visible yet (still replicating).
function ToolView.show(parent: Instance, tool: Tool, options: Options?): ViewportFrame?
	local o: Options = options or {}
	local handle = tool:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then
		return nil
	end
	local boxes, parts = {}, {}
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			table.insert(parts, d)
			table.insert(boxes, { cframe = handle.CFrame:ToObjectSpace(d.CFrame), size = d.Size })
		end
	end
	if #parts == 0 then
		return nil
	end
	local lo, hi = ToolView.bounds(boxes)
	local pose = ToolView.pose(lo, hi, tool.Grip.Position)
	local model = Instance.new("Model")
	model.Name = tool.Name
	local posed: { Box } = {}
	for i, part in parts do
		local copy = part:Clone()
		if not copy then
			continue -- (not Archivable)
		end
		for _, c in copy:GetDescendants() do -- its looks only (mesh, decals, surface): no welds, trails or scripts
			if not (c:IsA("DataModelMesh") or c:IsA("Decal") or c:IsA("SurfaceAppearance")) then
				c:Destroy()
			end
		end
		copy.Anchored = true
		copy.CanCollide, copy.CanTouch, copy.CanQuery, copy.CastShadow = false, false, false, false
		copy.CFrame = pose * boxes[i].cframe
		copy.Parent = model
		table.insert(posed, { cframe = copy.CFrame, size = copy.Size })
	end
	local points = {}
	for _, box in posed do
		for _, p in corners(box) do
			table.insert(points, p)
		end
	end

	local frame = Instance.new("ViewportFrame")
	frame.Name = "ToolView"
	frame.BackgroundTransparency = 1
	frame.Size = o.size or UDim2.fromScale(1, 1)
	frame.Position = o.position or UDim2.new()
	frame.ZIndex = o.zindex or 1
	frame.Ambient = ToolView.AMBIENT
	frame.LightColor = ToolView.LIGHT
	frame.LightDirection = ToolView.LIGHT_DIRECTION
	local camera = Instance.new("Camera")
	camera.FieldOfView = ToolView.FOV
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, ToolView.distance(points, ToolView.FOV, ToolView.FILL)), Vector3.zero)
	camera.Parent = frame
	frame.CurrentCamera = camera
	model.Parent = frame
	frame.Parent = parent
	return frame
end

return ToolView
