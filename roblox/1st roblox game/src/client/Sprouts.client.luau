-- Seedlings (plants still sprouting, Config.sproutTime): a countdown ("2:31", relief text) over the seedling
-- while its hover info shows (PlantHover.client turns the server's "Info" billboard on under the mouse or
-- for a few seconds after a tap), and on your own seedlings a "Grow now" button (Shared/GrowNowUi) above
-- it. Billboards in the world don't take clicks, so this one lives in PlayerGui, adorned to the seedling's
-- InfoAnchor, and stays up a moment after the mouse leaves the seedling so it can reach the button. When
-- a seedling pops into its flower (LootEvent "Sprouted") its owner hears it and sees "Grown!" rise there.
-- Local only: the server sets SproutUntil / OwnerUserId on the seedling's model (PlotService).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ShopUi = require(Shared:WaitForChild("ShopUi"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local GrowNowUi = require(Shared:WaitForChild("GrowNowUi"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local LootEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LootEvent") :: RemoteEvent

local INFO_H = 66 -- the server's Info billboard (name + "Sprouting"), right under our part
local COUNT_H, BUTTON_H, GAP = 34, 44, 4
local WIDTH = 176
local LINGER = 0.7 -- seconds it stays up after the hover info went off (time to reach the button)
local TICK = 0.2

type Shown = { gui: BillboardGui, model: Model, count: TextLabel, update: ((number) -> ())?, over: boolean, seen: number }
local shown: { [Model]: Shown } = {}

local function slotOf(model: Model): number?
	return tonumber(string.match(model.Name, "^Plant_(%d+)$"))
end

local function build(model: Model): Shown?
	local slot = slotOf(model)
	local body = model.PrimaryPart
	local anchor = body and body:FindFirstChild("InfoAnchor")
	if not slot or not anchor then
		return nil
	end
	local mine = model:GetAttribute("OwnerUserId") == player.UserId
	local height = INFO_H + COUNT_H + (if mine then BUTTON_H + GAP else 0)
	local gui = ShopUi.new("BillboardGui", {
		Name = "Sprout_" .. slot, Adornee = anchor, Size = UDim2.fromOffset(WIDTH, height), SizeOffset = Vector2.new(0, 0.5),
		MaxDistance = 60, LightInfluence = 0, Active = true, ResetOnSpawn = false, Enabled = false, Parent = playerGui,
	})
	local count = ShopUi.label(gui, 3, {
		Name = "Countdown", Text = "", TextColor3 = GrowNowUi.COUNTDOWN,
		Position = UDim2.new(0, 8, 0, height - INFO_H - COUNT_H), Size = UDim2.new(1, -16, 0, COUNT_H - 2),
	})
	UiFx.relief(count, 3, 3)
	local entry: Shown = { gui = gui, model = model, count = count, update = nil, over = false, seen = 0 }
	if mine then
		local button, update = GrowNowUi.button(gui, slot, UDim2.fromOffset(WIDTH - 12, BUTTON_H))
		button.Position = UDim2.fromOffset(6, 0)
		UiFx.pop(button)
		button.MouseEnter:Connect(function()
			entry.over = true
		end)
		button.MouseLeave:Connect(function()
			entry.over = false
		end)
		entry.update = update
	end
	return entry
end

local function drop(model: Model)
	local entry = shown[model]
	if entry then
		entry.gui:Destroy()
		shown[model] = nil
	end
end

local function consider(inst: Instance)
	if inst:IsA("Model") and inst:GetAttribute("SproutUntil") ~= nil and slotOf(inst) and not shown[inst] then
		local entry = build(inst)
		if entry then
			shown[inst] = entry
		else
			task.delay(0.5, function() -- its parts are still on the way
				if inst.Parent and not shown[inst] then
					local again = build(inst)
					if again then
						shown[inst] = again
					end
				end
			end)
		end
	end
end

for _, d in workspace:GetDescendants() do
	consider(d)
end
workspace.DescendantAdded:Connect(consider)
workspace.DescendantRemoving:Connect(function(inst)
	if inst:IsA("Model") then
		drop(inst)
	end
end)

local pause = 0
RunService.Heartbeat:Connect(function(dt)
	pause -= dt
	if pause > 0 then
		return
	end
	pause = TICK
	local clock = os.clock()
	for model, entry in shown do
		if not model.Parent then
			drop(model)
			continue
		end
		local left = GrowNowUi.left(model:GetAttribute("SproutUntil"))
		local info = model:FindFirstChild("Info", true) :: BillboardGui?
		if (info and info.Enabled) or entry.over then
			entry.seen = clock
		end
		local on = clock - entry.seen < LINGER
		if entry.gui.Enabled ~= on then
			entry.gui.Enabled = on
		end
		if on then
			entry.count.Text = GrowNowUi.clock(left)
			if entry.update then
				entry.update(left)
			end
		end
	end
end)

-- A seedling of yours popped into its flower: the planting sound there and "Grown!" rising in relief.
LootEvent.OnClientEvent:Connect(function(kind: string, data: any)
	if kind ~= "Sprouted" or type(data) ~= "table" or typeof(data.pos) ~= "Vector3" then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = data.pos
	attachment.Parent = workspace.Terrain
	local sound = Instance.new("Sound")
	sound.SoundId = Config.SOUNDS.Plant
	sound.Parent = attachment
	sound:Play()
	local gui = ShopUi.new("BillboardGui", {
		Adornee = attachment, Size = UDim2.fromOffset(160, 44), SizeOffset = Vector2.new(0, 0.5), LightInfluence = 0, AlwaysOnTop = true,
		ResetOnSpawn = false, Parent = playerGui,
	})
	local label = ShopUi.label(gui, 3, { Text = "Grown!", TextColor3 = GrowNowUi.COUNTDOWN, Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 1) })
	UiFx.relief(label, 3, 3)
	local rise = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, rise, { StudsOffset = Vector3.new(0, 3, 0) }):Play()
	task.delay(1.6, function()
		gui:Destroy()
		attachment:Destroy()
	end)
end)
