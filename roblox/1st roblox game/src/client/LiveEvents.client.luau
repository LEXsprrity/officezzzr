-- The owner's live "admin abuse" events, on screen (Server/LiveEventService runs them in every server).
--   * a BIG banner when one starts ("ADMIN ABUSE!" / "3x LUCK for 10 minutes!" / what it does): a gold studded
--     plate with a spinning rainbow frame that pops in with a chime, holds, and fades; an admin's message
--     (LootEvent "LiveAnnounce") shows the same way; "Event ended" shows smaller, in blue;
--   * a strip of the running events with a live countdown, right under the DayTimer (top right), so it stays
--     clear of the Tutorial banner (top centre) and Roblox's own buttons (top left).
-- The running events are ReplicatedStorage.LiveEvents' children (a Configuration each, EndsAt in server time).
-- Children already there when we join only go in the strip (no banner: they didn't just start).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LiveEvents = require(Shared:WaitForChild("LiveEvents"))
local ShopUi = require(Shared:WaitForChild("ShopUi"))
local Toast = require(Shared:WaitForChild("Toast"))
local UiFx = require(Shared:WaitForChild("UiFx"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local LootEvent = remotes:WaitForChild("LootEvent") :: RemoteEvent
local player = Players.LocalPlayer
local new = ShopUi.new

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local KIND_COLOR = {
	Luck = Color3.fromRGB(160, 75, 255),
	Money = Color3.fromRGB(60, 200, 70),
	Speed = Color3.fromRGB(40, 150, 255),
	Mutation = Color3.fromRGB(255, 80, 200),
	Grow = Color3.fromRGB(120, 210, 40),
	Candy = Color3.fromRGB(255, 140, 30),
}
local GOLD = Toast.STYLES.gold.color
local BLUE = Toast.STYLES.blue.color

local gui = new("ScreenGui", { Name = "LiveEvents", ResetOnSpawn = false, DisplayOrder = 12, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
local uiScale = new("UIScale", { Parent = gui }) -- the HUD's design pixels: 900 tall at scale 1
local function rescale()
	local cam = workspace.CurrentCamera
	uiScale.Scale = math.clamp((if cam then cam.ViewportSize.Y else 900) / 900, 0.55, 1.25)
end
rescale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- A little rising three-note chime (built-in sound, so nothing to upload).
local function chime(big: boolean)
	for i, speed in (if big then { 1, 1.26, 1.5 } else { 1.2, 0.9 }) :: { number } do
		task.delay((i - 1) * 0.12, function()
			local sound = new("Sound", { SoundId = Config.SOUNDS.Pickup, Volume = if big then 0.9 else 0.5, PlaybackSpeed = speed, Parent = SoundService })
			sound:Play()
			task.delay(3, function()
				sound:Destroy()
			end)
		end)
	end
end

----------------------------------------------------------------------------------------------------
-- The big banner (one at a time, queued)
----------------------------------------------------------------------------------------------------
local BANNER_W, BANNER_H = 760, 150
type Banner = { title: string, line: string, about: string?, color: Color3, big: boolean, seconds: number }
local queue: { Banner } = {}
local showing = false

local function drawBanner(b: Banner)
	local h = if b.big then BANNER_H else 96
	local group = new("CanvasGroup", {
		Name = "LiveBanner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(BANNER_W + 24, h + 24),
		BackgroundTransparency = 1, GroupTransparency = 1, Parent = gui,
	})
	local pop = new("UIScale", { Scale = 0.3, Parent = group })
	local plate = new("Frame", {
		Name = "Plate", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(BANNER_W, h),
		BackgroundColor3 = WHITE, BorderSizePixel = 0, ClipsDescendants = true, Parent = group,
	}, {
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(b.color:Lerp(WHITE, 0.2), b.color:Lerp(BLACK, 0.2)) }),
	})
	local outline = new("UIStroke", { Thickness = if b.big then 7 else 5, Color = if b.big then WHITE else ShopUi.INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = plate })
	local rainbow = if b.big then new("UIGradient", { Name = "Rainbow", Rotation = 0, Color = Toast.RAINBOW, Parent = outline }) else nil
	ShopUi.studs(plate, b.color, nil, 1)
	ShopUi.bevel(plate, 1)
	local shine = new("Frame", {
		Name = "Shine", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(-0.1, 0), Size = UDim2.new(0, h, 1, 0), Rotation = 20,
		BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2, Parent = plate,
	}, { new("UIGradient", { Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 1),
	}) }) })

	local titleH = if b.big then 58 else 40
	UiFx.relief(ShopUi.label(plate, 5, {
		Name = "Title", Text = b.title, Position = UDim2.fromOffset(20, 8), Size = UDim2.new(1, -40, 0, titleH), ZIndex = 5,
	}), 5, 5)
	UiFx.relief(ShopUi.label(plate, 4, {
		Name = "Line", Text = b.line, TextColor3 = if b.big then Color3.fromRGB(255, 245, 140) else WHITE,
		Position = UDim2.fromOffset(20, 10 + titleH), Size = UDim2.new(1, -40, 0, if b.big then 44 else 34), ZIndex = 5,
	}), 4, 4)
	if b.about and b.big then
		UiFx.relief(ShopUi.label(plate, 3, {
			Name = "About", Text = b.about, Position = UDim2.fromOffset(30, 14 + titleH + 44), Size = UDim2.new(1, -60, 0, 26), ZIndex = 5,
		}), 3, 3)
	end

	chime(b.big)
	local back = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(group, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { GroupTransparency = 0 }):Play()
	TweenService:Create(pop, back, { Scale = 1 }):Play()
	TweenService:Create(shine, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1, false, 1.2), { Position = UDim2.fromScale(1.15, 0) }):Play()
	if rainbow then
		TweenService:Create(rainbow, TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 }):Play()
	end
	if b.big then -- a little throb while it holds
		task.delay(0.5, function()
			TweenService:Create(pop, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true), { Scale = 1.04 }):Play()
		end)
	end
	task.wait(b.seconds)
	local out = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(group, out, { GroupTransparency = 1, Position = UDim2.fromScale(0.5, 0.26) }):Play()
	TweenService:Create(pop, out, { Scale = 0.85 }):Play()
	task.wait(0.45)
	group:Destroy()
end

local function banner(b: Banner)
	table.insert(queue, b)
	if showing then
		return
	end
	showing = true
	task.spawn(function()
		while #queue > 0 do
			local nextOne = table.remove(queue, 1) :: Banner
			local ok, err = pcall(drawBanner, nextOne)
			if not ok then
				warn("[LiveEvents]", err)
			end
		end
		showing = false
	end)
end

----------------------------------------------------------------------------------------------------
-- The strip of running events (top right, under the DayTimer)
----------------------------------------------------------------------------------------------------
local ROW_W, ROW_H = 236, 40
local strip = new("Frame", {
	Name = "Strip", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 60), Size = UDim2.fromOffset(ROW_W, 0),
	AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = gui,
}, {
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right }),
})


-- While the Tutorial's banner shows (top centre, 134 tall), the strip waits under it: on a narrow screen they'd meet.
task.spawn(function()
	local tutorial = player:WaitForChild("PlayerGui"):WaitForChild("Tutorial", 30)
	if not (tutorial and tutorial:IsA("ScreenGui")) then
		return
	end
	local function place()
		strip.Position = UDim2.new(1, -14, 0, if tutorial.Enabled then 144 else 60)
	end
	tutorial:GetPropertyChangedSignal("Enabled"):Connect(place)
	place()
end)

type Row = { frame: Frame, name: TextLabel, time: TextLabel, endsAt: number }
local rows: { [string]: Row } = {}

local function eventOf(c: Instance): LiveEvents.Event?
	local kind, endsAt, startedAt = c:GetAttribute("Kind"), c:GetAttribute("EndsAt"), c:GetAttribute("StartedAt")
	if type(kind) ~= "string" or type(endsAt) ~= "number" or type(startedAt) ~= "number" then
		return nil
	end
	local mult, option = c:GetAttribute("Mult"), c:GetAttribute("Option")
	return {
		id = c.Name, kind = kind, startedAt = startedAt, endsAt = endsAt,
		mult = if type(mult) == "number" then mult else nil, option = if type(option) == "string" then option else nil,
	}
end

local function addRow(ev: LiveEvents.Event)
	local color = KIND_COLOR[ev.kind] or GOLD
	local f = new("Frame", {
		Name = ev.id, Size = UDim2.fromOffset(ROW_W, ROW_H), BackgroundColor3 = color, BorderSizePixel = 0, LayoutOrder = math.floor(ev.endsAt), Parent = strip,
	})
	new("UIStroke", { Thickness = 3, Color = ShopUi.INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f })
	ShopUi.studs(f, color, nil, 1)
	ShopUi.bevel(f, 1)
	local name = ShopUi.label(f, 3, {
		Name = "Event", Text = LiveEvents.describe(ev), TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(10, 5), Size = UDim2.new(1, -86, 1, -10), ZIndex = 4,
	})
	UiFx.relief(name, 2, 3)
	local time = ShopUi.label(f, 3, {
		Name = "Time", Text = LiveEvents.clock(ev.endsAt - serverNow()), TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -78, 0, 5), Size = UDim2.fromOffset(68, ROW_H - 10), ZIndex = 4,
	})
	UiFx.relief(time, 2, 3)
	rows[ev.id] = { frame = f, name = name, time = time, endsAt = ev.endsAt }
end

local function removeRow(id: string)
	local row = rows[id]
	if row then
		rows[id] = nil
		row.frame:Destroy()
	end
end

local shown: { [string]: LiveEvents.Event } = {} -- what each row was, for its "Event ended"

local function onAdded(c: Instance, fresh: boolean)
	local ev = eventOf(c)
	if not ev or rows[ev.id] or ev.endsAt <= serverNow() then
		return
	end
	shown[ev.id] = ev
	addRow(ev)
	if fresh then
		banner({ title = "ADMIN ABUSE!", line = string.sub(LiveEvents.banner(ev), #"ADMIN ABUSE! " + 1), about = LiveEvents.about(ev),
			color = GOLD, big = true, seconds = 5 })
	end
end

local function onRemoved(c: Instance)
	local ev = shown[c.Name]
	shown[c.Name] = nil
	removeRow(c.Name)
	if ev then
		banner({ title = "Event ended", line = LiveEvents.describe(ev), color = BLUE, big = false, seconds = 2.5 })
	end
end

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild(LiveEvents.FOLDER)
	for _, c in folder:GetChildren() do
		onAdded(c, false)
	end
	folder.ChildAdded:Connect(function(c)
		onAdded(c, true)
	end)
	folder.ChildRemoved:Connect(onRemoved)
end)

-- An admin's message, big, in every server
LootEvent.OnClientEvent:Connect(function(kind: string, data: any)
	if kind == "LiveAnnounce" and type(data) == "table" and type(data.text) == "string" then
		banner({ title = if type(data.by) == "string" then `{data.by} says:` else "ADMIN", line = data.text, color = GOLD, big = true, seconds = 7 })
	end
end)

-- The countdowns (a few times a second is plenty)
local nextTick = 0
RunService.Heartbeat:Connect(function()
	local t = os.clock()
	if t < nextTick then
		return
	end
	nextTick = t + 0.25
	local now = serverNow()
	for _, row in rows do
		local left = row.endsAt - now
		row.time.Text = LiveEvents.clock(left)
		row.frame.Visible = left > 0 -- (the server takes it away a moment later)
	end
end)

gui.Parent = player:WaitForChild("PlayerGui")
