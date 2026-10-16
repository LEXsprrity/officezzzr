-- The Bat as a real Tool in the player's Backpack (owner 2026-10-16): pressing 1 (or the hotbar's Bat slot)
-- only equips or puts it away; with it in hand a left click (a tap on mobile) swings it (BatSwing.client:
-- the strike animation, then RequestUseItem "Bat"). The server only lets an equipped bat hit
-- (BatTool.equipped). The model is assets/Bat.rbxm (the "Bat" slot, a Tool with a Handle); without
-- it a plain wooden bat is built here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Assets = require(script.Parent:WaitForChild("Assets"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sessions = require(script.Parent:WaitForChild("Sessions"))
local SpeedService = require(script.Parent:WaitForChild("SpeedService"))
local SeedService = require(script.Parent:WaitForChild("SeedService"))

local BatTool = {}

BatTool.NAME = "Bat"

-- A plain wooden bat (no assets/Bat.rbxm): a brown cylinder held at its thin end.
local function plainBat(): Tool
	local tool = Instance.new("Tool")
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Shape = Enum.PartType.Cylinder
	handle.Size = Vector3.new(4, 0.5, 0.5)
	handle.Color = Color3.fromRGB(176, 112, 58)
	handle.Material = Enum.Material.Wood
	handle.Parent = tool
	tool.Grip = CFrame.new(0, 0, -1.6) * CFrame.Angles(0, math.rad(90), 0)
	return tool
end

-- The template: the asset's Tool (the file's root, or the first Tool inside it), else a plain bat.
local function template(): Tool
	local ok, asset = pcall(Assets.get, "Bat")
	if ok and asset then
		local tool = if asset:IsA("Tool") then asset else asset:FindFirstChildWhichIsA("Tool", true)
		if tool and tool:FindFirstChild("Handle") then
			return tool :: Tool
		end
	end
	return plainBat()
end

-- A fresh bat for one character: can't be dropped, weightless and solid to nothing, so it never changes
-- how the player moves (SpeedService watches that) and touches nothing; only BatSwing.client's own
-- scripts drive it (any script that came with the model is removed).
function BatTool.make(): Tool
	local tool = template():Clone()
	tool.Name = BatTool.NAME
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = false
	tool.ToolTip = ""
	for _, d in tool:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		elseif d:IsA("Trail") then
			d.Enabled = false -- BatSwing.client shows it during a swing
		end
	end
	return tool
end

-- Each new character gets one in its Backpack (the Backpack empties on respawn).
function BatTool.give(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 10)
	local char = player.Character
	if not backpack or (backpack:FindFirstChild(BatTool.NAME)) or (char and char:FindFirstChild(BatTool.NAME)) then
		return
	end
	BatTool.make().Parent = backpack
end

-- Whether the player holds the bat right now (an equipped Tool sits in the character).
function BatTool.equipped(player: Player): boolean
	local char = player.Character
	local tool = char and char:FindFirstChild(BatTool.NAME)
	return tool ~= nil and tool:IsA("Tool")
end

-- A swing at players: the nearest other player within BAT_PLAYER_RANGE of where the hitter could have
-- walked to (SpeedService.trustedRoot / seenPosition) is knocked away from them, stunned for a moment and
-- drops a carried seed back to its pod. Returns the player hit, if any.
function BatTool.hitPlayer(hitter: Player): Player?
	local root = SpeedService.trustedRoot(hitter)
	if not root then
		return nil
	end
	local from = root.CFrame.Position
	local best: Player?, bestDist = nil, Config.BAT_PLAYER_RANGE
	for other in Sessions.all() do
		if other ~= hitter then
			local pos = SpeedService.seenPosition(other)
			local d = pos and Vector3.new(pos.X - from.X, 0, pos.Z - from.Z).Magnitude
			if d and d <= bestDist then
				best, bestDist = other, d
			end
		end
	end
	local victim = best
	if not victim then
		return nil
	end
	local s = Sessions.get(victim)
	local vroot = SpeedService.rootOf(victim)
	local carried = s ~= nil and s.carry ~= nil
	SeedService.returnCarry(victim)
	if s and vroot then
		local away = Vector3.new(vroot.CFrame.Position.X - from.X, 0, vroot.CFrame.Position.Z - from.Z)
		local dir = if away.Magnitude > 0.1 then away.Unit else root.CFrame.LookVector * Vector3.new(1, 0, 1)
		dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.xAxis
		SpeedService.knock(victim, dir)
		s.stunnedUntil = math.max(s.stunnedUntil, os.clock() + Config.BAT_PLAYER_STUN)
		if carried then
			Net.toast(victim, `{hitter.DisplayName} hit you with a bat! Your seed went back.`, "red")
		end
	end
	return victim
end

return BatTool
