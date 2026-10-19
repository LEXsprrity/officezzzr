-- The owner's admin panel (owner 2026-10-16: "make a admin panel", to pay players back for bug reports).
-- Only built for admins: the server sets the player attribute IsAdmin (AdminService). An "ADMIN" button in
-- the bottom-right corner (or F2) opens a window: type a player's name (or tap someone in this server), then
-- give them money, Speed or seeds of a zone and rarity, or TAKE seeds back. Amounts read like "50K" or "1.5M" (AdminGrant). The
-- server answers with LootEvent "AdminResult", shown under the buttons. Someone not in this server gets it
-- the next time they join. The EVENTS tab starts live "admin abuse" events in every server (an event, its
-- multiplier or option, minutes, START), lists the running ones with STOP, and SENDs a message to everyone.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local AdminGrant = require(Shared:WaitForChild("AdminGrant"))
local LiveEvents = require(Shared:WaitForChild("LiveEvents"))
local ShopUi = require(Shared:WaitForChild("ShopUi"))
local UiFx = require(Shared:WaitForChild("UiFx"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local AdminRemote = remotes:WaitForChild("Admin") :: RemoteEvent
local AdminEventRemote = remotes:WaitForChild("AdminEvent") :: RemoteEvent
local LootEvent = remotes:WaitForChild("LootEvent") :: RemoteEvent

local player = Players.LocalPlayer
while not player:GetAttribute("IsAdmin") do
	player:GetAttributeChangedSignal("IsAdmin"):Wait()
end
local playerGui = player:WaitForChild("PlayerGui")
local new = ShopUi.new

local INK = ShopUi.INK
local PANEL = Color3.fromRGB(70, 60, 150)
local BLUE = Color3.fromRGB(40, 130, 240)
local GREEN = Color3.fromRGB(50, 190, 70)
local RED = Color3.fromRGB(225, 40, 45)
local W, H = 540, 500

local gui = new("ScreenGui", { Name = "AdminPanel", ResetOnSpawn = false, DisplayOrder = 20, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
local uiScale = new("UIScale", { Parent = gui })
local function rescale()
	local cam = workspace.CurrentCamera
	uiScale.Scale = math.clamp((if cam then cam.ViewportSize.Y else 900) / 900, 0.55, 1.25)
end
rescale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

-- A square studded plate with a thick dark outline and a lighter top half.
local function plate(className: string, color: Color3, props: { [string]: any }): any
	local f = new(className, props)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	new("UIStroke", { Thickness = 4, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f })
	ShopUi.studs(f, color)
	ShopUi.bevel(f)
	return f
end

local function button(parent: Instance, text: string, color: Color3, pos: UDim2, size: UDim2): (TextButton, TextLabel)
	local b = plate("TextButton", color, { Text = "", AutoButtonColor = false, Position = pos, Size = size, ZIndex = 3, Parent = parent })
	local word = UiFx.relief(ShopUi.label(b, 3, { Name = "Word", Text = text, Size = UDim2.new(1, -16, 1, -12), Position = UDim2.fromOffset(8, 6), ZIndex = 5 }), 3, 3)
	UiFx.pop(b)
	return b, word
end

-- A dark see-through typing box.
local function box(parent: Instance, hint: string, pos: UDim2, size: UDim2): TextBox
	local b = new("TextBox", {
		Text = "", PlaceholderText = hint, ClearTextOnFocus = false, Font = ShopUi.FONT, TextSize = 26, TextColor3 = Color3.new(1, 1, 1),
		PlaceholderColor3 = Color3.fromRGB(170, 170, 190), BackgroundColor3 = ShopUi.SLOT_COLOR, BackgroundTransparency = 0.3, BorderSizePixel = 0,
		Position = pos, Size = size, ZIndex = 3, Parent = parent,
	})
	new("UIStroke", { Thickness = 3, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
	return b
end

local function rowName(parent: Instance, text: string, y: number)
	UiFx.relief(ShopUi.label(parent, 3, { Text = text, Size = UDim2.fromOffset(100, 36), Position = UDim2.fromOffset(20, y + 6), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 }), 2, 3)
end

-- The corner button (bottom-right: the Speed and money readout has the bottom-left)
local open = button(gui, "ADMIN", PANEL, UDim2.new(1, -144, 1, -60), UDim2.fromOffset(130, 46))

-- The window
local window = plate("Frame", PANEL, { Name = "Window", Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H), ZIndex = 2, Parent = gui })
UiFx.relief(ShopUi.label(window, 4, { Text = "ADMIN PANEL", Size = UDim2.fromOffset(W - 250, 46), Position = UDim2.fromOffset(20, 10), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 }), 3, 4)
local close = button(window, "X", RED, UDim2.fromOffset(W - 66, 10), UDim2.fromOffset(50, 46))

local INPUT_X, INPUT_W, GIVE_X, GIVE_W = 130, 230, 374, 146

rowName(window, "Player", 70)
local nameBox = box(window, "username", UDim2.fromOffset(INPUT_X, 70), UDim2.fromOffset(W - INPUT_X - 20, 48))

-- People in this server: tap one to fill in the name
local chips = new("ScrollingFrame", {
	BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(INPUT_X, 126), Size = UDim2.fromOffset(W - INPUT_X - 20, 44),
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 4, ZIndex = 3, Parent = window,
})
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.Name, Parent = chips })
new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), Parent = chips })
local function refreshChips()
	for _, c in chips:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	for _, p in Players:GetPlayers() do
		local width = math.clamp(#p.Name * 13 + 24, 70, 220)
		local b = button(chips, p.Name, BLUE, UDim2.new(), UDim2.fromOffset(width, 34))
		b.Name = string.lower(p.Name)
		b.Activated:Connect(function()
			nameBox.Text = p.Name
		end)
	end
end
refreshChips()
Players.PlayerAdded:Connect(refreshChips)
Players.PlayerRemoving:Connect(function()
	task.defer(refreshChips)
end)

local status = ShopUi.label(window, 3, { Text = "", Size = UDim2.fromOffset(W - 40, 32), Position = UDim2.fromOffset(20, H - 50), ZIndex = 4 })
local function say(text: string, ok: boolean)
	status.Text = text
	status.TextColor3 = if ok then Color3.fromRGB(140, 255, 140) else Color3.fromRGB(255, 130, 130)
end

local function send(grant: { [string]: any })
	local target = string.gsub(nameBox.Text, "^%s*(.-)%s*$", "%1")
	if target == "" then
		say("Type a player's name first", false)
		return
	end
	local g, why = AdminGrant.check(grant)
	if not g then
		say(why or "?", false)
		return
	end
	say(`Sending {AdminGrant.describe(g)} to {target}...`, true)
	AdminRemote:FireServer(target, g)
end

-- Money and Speed
for i, kind in { "Money", "Speed" } do
	local y = 126 + 60 * i
	rowName(window, kind, y)
	local amount = box(window, if kind == "Money" then "e.g. 50K, 1.5M" else "e.g. 25K", UDim2.fromOffset(INPUT_X, y), UDim2.fromOffset(INPUT_W, 48))
	local give = button(window, "GIVE", GREEN, UDim2.fromOffset(GIVE_X, y), UDim2.fromOffset(GIVE_W, 48))
	give.Activated:Connect(function()
		send({ kind = kind, amount = AdminGrant.parseAmount(amount.Text) })
	end)
end

-- Seeds: zone and rarity pickers (tap to go to the next), how many, GIVE
local zone, rarity = 1, 1
rowName(window, "Seed", 306)
local zoneButton, zoneWord = button(window, "", BLUE, UDim2.fromOffset(INPUT_X, 306), UDim2.fromOffset(INPUT_W, 48))
local rarityButton, rarityWord = button(window, "", Config.RARITIES[1].color, UDim2.fromOffset(GIVE_X, 306), UDim2.fromOffset(GIVE_W, 48))
local function showPickers()
	zoneWord.Text = Config.ZONES[zone].name
	rarityWord.Text = Config.RARITIES[rarity].id
	rarityButton.BackgroundColor3 = Config.RARITIES[rarity].color
	ShopUi.paintStuds(rarityButton, Config.RARITIES[rarity].color)
end
showPickers()
zoneButton.Activated:Connect(function()
	zone = zone % #Config.ZONES + 1
	showPickers()
end)
rarityButton.Activated:Connect(function()
	rarity = rarity % #Config.RARITIES + 1
	showPickers()
end)
local countBox = box(window, `1-{AdminGrant.MAX_SEEDS}`, UDim2.fromOffset(INPUT_X, 366), UDim2.fromOffset(100, 48))
countBox.Text = "1"
-- TAKE: takes seeds of that zone and rarity back (bag, then inventory, then plot; waiting ones are cancelled)
local takeSeed = button(window, "TAKE", RED, UDim2.fromOffset(INPUT_X + 110, 366), UDim2.fromOffset(INPUT_W - 110, 48))
takeSeed.Activated:Connect(function()
	send({ kind = "TakeSeed", zone = zone, rarity = rarity, count = AdminGrant.parseAmount(countBox.Text) })
end)
local giveSeed = button(window, "GIVE", GREEN, UDim2.fromOffset(GIVE_X, 366), UDim2.fromOffset(GIVE_W, 48))
giveSeed.Activated:Connect(function()
	send({ kind = "Seed", zone = zone, rarity = rarity, count = AdminGrant.parseAmount(countBox.Text) })
end)

----------------------------------------------------------------------------------------------------
-- EVENTS: live "admin abuse" events in every server (Server/LiveEventService checks everything again)
----------------------------------------------------------------------------------------------------
local eventsTab, eventsWord = button(window, "EVENTS", Color3.fromRGB(255, 150, 20), UDim2.fromOffset(W - 216, 10), UDim2.fromOffset(140, 46))
local page = plate("Frame", PANEL, { Name = "Events", Visible = false, Active = true, Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 1, -118), ZIndex = 6, Parent = window })
eventsTab.Activated:Connect(function()
	page.Visible = not page.Visible
	eventsWord.Text = if page.Visible then "GRANTS" else "EVENTS"
end)

local kindIndex, choiceIndex = 1, 1
local function kindNow(): string
	return LiveEvents.KINDS[kindIndex]
end
rowName(page, "Event", 8)
local kindButton, kindWord = button(page, "", BLUE, UDim2.fromOffset(INPUT_X, 8), UDim2.fromOffset(INPUT_W, 48))
local choiceButton, choiceWord = button(page, "", BLUE, UDim2.fromOffset(GIVE_X, 8), UDim2.fromOffset(GIVE_W, 48))
local function showKind()
	local choices = LiveEvents.CHOICES[kindNow()]
	choiceIndex = math.clamp(choiceIndex, 1, #choices)
	kindWord.Text = string.upper(kindNow())
	choiceWord.Text = choices[choiceIndex].label
end
showKind()
kindButton.Activated:Connect(function()
	kindIndex = kindIndex % #LiveEvents.KINDS + 1
	choiceIndex = 1
	showKind()
end)
choiceButton.Activated:Connect(function()
	choiceIndex = choiceIndex % #LiveEvents.CHOICES[kindNow()] + 1
	showKind()
end)

rowName(page, "Minutes", 64)
local minutesBox = box(page, `{LiveEvents.MIN_MINUTES}-{LiveEvents.MAX_MINUTES}`, UDim2.fromOffset(INPUT_X, 64), UDim2.fromOffset(100, 48))
minutesBox.Text = "10"
local startButton = button(page, "START (ALL SERVERS)", GREEN, UDim2.fromOffset(INPUT_X + 110, 64), UDim2.fromOffset(W - INPUT_X - 130, 48))
startButton.Activated:Connect(function()
	local choice = LiveEvents.CHOICES[kindNow()][choiceIndex]
	local req = { op = "start", kind = kindNow(), mult = choice.mult, option = choice.option, minutes = tonumber(minutesBox.Text) }
	local ok, why = LiveEvents.checkStart(req, true)
	if not ok then
		say(why or "?", false)
		return
	end
	say(`Starting {LiveEvents.describe(req :: any)} in all servers...`, true)
	AdminEventRemote:FireServer(req)
end)

rowName(page, "Message", 120)
local messageBox = box(page, `say something to everyone (max {LiveEvents.MAX_TEXT})`, UDim2.fromOffset(INPUT_X, 120), UDim2.fromOffset(INPUT_W, 48))
messageBox.TextSize = 20
local sendButton = button(page, "SEND", BLUE, UDim2.fromOffset(GIVE_X, 120), UDim2.fromOffset(GIVE_W, 48))
sendButton.Activated:Connect(function()
	local text = LiveEvents.cleanText(messageBox.Text)
	if not text then
		say("Type a message first", false)
		return
	end
	say("Sending to all servers...", true)
	AdminEventRemote:FireServer({ op = "announce", text = text })
	messageBox.Text = ""
end)

-- The running events, each with STOP
rowName(page, "Running", 176)
local running = new("ScrollingFrame", {
	BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(INPUT_X, 176), Size = UDim2.new(1, -INPUT_X - 20, 1, -184),
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4, ZIndex = 3, Parent = page,
})
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = running })
local none = UiFx.relief(ShopUi.label(page, 2, { Text = "none", Size = UDim2.fromOffset(200, 30), Position = UDim2.fromOffset(INPUT_X, 184), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 }), 2, 2)
local timers: { [TextLabel]: number } = {}
local function refreshRunning()
	table.clear(timers)
	for _, c in running:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local folder = ReplicatedStorage:FindFirstChild(LiveEvents.FOLDER)
	local count = 0
	for _, c in (if folder then folder:GetChildren() else {}) do
		local endsAt = c:GetAttribute("EndsAt")
		if type(endsAt) == "number" then
			count += 1
			local ev = { kind = c:GetAttribute("Kind") or "?", mult = c:GetAttribute("Mult"), option = c:GetAttribute("Option") }
			local row = new("Frame", { Name = c.Name, BackgroundTransparency = 1, LayoutOrder = math.floor(endsAt), Size = UDim2.new(1, -8, 0, 44), ZIndex = 3, Parent = running })
			local label = ShopUi.label(row, 3, { Text = "", TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -130, 1, -8), Position = UDim2.fromOffset(4, 4), ZIndex = 4 })
			label:SetAttribute("Event", LiveEvents.describe(ev :: any))
			timers[label] = endsAt
			local id = c.Name
			local stop = button(row, "STOP", RED, UDim2.new(1, -116, 0, 2), UDim2.fromOffset(112, 40))
			stop.Activated:Connect(function()
				say(`Stopping {LiveEvents.describe(ev :: any)} in all servers...`, true)
				AdminEventRemote:FireServer({ op = "stop", id = id })
			end)
		end
	end
	none.Visible = count == 0
end
local function showTimers()
	local now = workspace:GetServerTimeNow()
	for label, endsAt in timers do
		label.Text = `{label:GetAttribute("Event")}  {LiveEvents.clock(endsAt - now)}`
	end
end
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild(LiveEvents.FOLDER)
	folder.ChildAdded:Connect(refreshRunning)
	folder.ChildRemoved:Connect(function()
		task.defer(refreshRunning)
	end)
	refreshRunning()
	while true do
		showTimers()
		task.wait(0.5)
	end
end)

LootEvent.OnClientEvent:Connect(function(kind: string, data: any)
	if kind == "AdminResult" and type(data) == "table" then
		say(tostring(data.text), data.ok == true)
	end
end)

local function toggle()
	window.Visible = not window.Visible
end
open.Activated:Connect(toggle)
close.Activated:Connect(function()
	window.Visible = false
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.F2 then
		toggle()
	end
end)

gui.Parent = playerGui
