-- The HUD: no Speed levels (v7 removed them with the "LEVEL N!" pop-up: the Speed per step is flat), the
-- Shop's small Speed products (+25K / +150K / +750K), granted through the normal receipt path, and the
-- layout: no level bar, only Shop and Index on the left.
local H = require("./harness")
local Config = H.shared("Config")
local Format = H.shared("Format")
local Shop = H.server("Shop")
local ProfileStore = H.server("ProfileStore")

H.test("speed levels are gone: no level table, no level maths, no level-up sound, no compounding gain", function()
	for _, gone in { "SPEED_LEVELS", "speedLevel", "speedLevelThreshold", "levelUp", "gainPerStud", "GAIN_PER_STUD", "GAIN_PIVOT", "GAIN_EXPONENT" } do
		H.eq((Config :: any)[gone], nil, `Config.{gone}`)
	end
	H.eq(Config.SOUNDS.LevelUp, nil, "the level-up ping went with the pop-up")
end)

H.test("Speed packs: Speed25K, Speed150K and Speed750K are id = 0 Speed products, coming soon until set", function()
	local p = ProfileStore.defaultProfile()
	for name, want in { Speed25K = { 25e3, 9 }, Speed150K = { 150e3, 36 }, Speed750K = { 750e3, 76 } } do
		local product = Config.DEVELOPER_PRODUCTS[name]
		H.ok(product ~= nil, name)
		H.eq(product.kind, "Speed", name)
		H.eq(product.amount, want[1], name)
		H.eq(product.robux, want[2], name)
		H.eq(product.id, 0, name .. " ships as a stub")
		local ok, why = Shop.canPrompt(p, name)
		H.eq(ok, nil)
		H.ok(why and string.find(why, "coming soon"), why)
	end
end)

H.test("Speed packs: each grants its Speed exactly once per receipt", function()
	local p = ProfileStore.defaultProfile()
	local function never(): number
		error("Speed packs don't roll")
	end
	local saves = 0
	local function save(): boolean
		saves += 1
		return true
	end
	local total = 0
	for i, c in { { "Speed25K", 25e3 }, { "Speed150K", 150e3 }, { "Speed750K", 750e3 } } do
		total += c[2]
		local confirm, status, grant = Shop.processReceipt(p, c[1], "q" .. i, 0, never, save)
		H.eq(confirm, true)
		H.eq(status, "granted")
		H.eq(grant.label, Config.DEVELOPER_PRODUCTS[c[1]].label)
		H.eq(p.speed, total, c[1])
		local again, dup = Shop.processReceipt(p, c[1], "q" .. i, 0, never, save)
		H.eq(again, true, "a retried receipt is confirmed...")
		H.eq(dup, "duplicate")
		H.eq(p.speed, total, "...but not granted twice")
	end
	H.eq(p.money, 0)
	H.eq(saves, 6)
end)

----------------------------------------------------------------------------------------------------
-- The HUD's layout (from the source: Lune can't run a LocalScript)
----------------------------------------------------------------------------------------------------
local fs = require("@lune/fs")
local HUD = fs.readFile("src/client/HUD.client.luau")
local REWARDS = fs.readFile("src/client/Rewards.client.luau")

H.test("HUD: no level bar and no quick-buy buttons; bottom left is just Speed and money", function()
	for _, gone in { "levelPanel", "levelBar", "levelFill", "QUICK_BUY", "quickRow", "quickPrices", "refreshQuickBuy", "levelMultLabel" } do
		H.ok(not string.find(HUD, gone, 1, true), `"{gone}" is gone from the HUD`)
	end
	H.ok(string.find(HUD, "local speedValue", 1, true) and string.find(HUD, "local moneyValue", 1, true), "the Speed and money readouts stay")
	-- no "LEVEL N!" pop-up either (v7: no Speed levels)
	for _, gone in { "announceLevel", "levelUpLabel", "bestLevel", "speedLevel", "levelUp(", "LEVEL {level}!" } do
		H.ok(not string.find(HUD, gone, 1, true), `"{gone}" is gone from the HUD`)
	end
end)

H.test("HUD: the left column has only Shop and Index (and Slow Mode); Trails opens from its stall", function()
	local buttons = {}
	for name in string.gmatch(HUD, "\nsideButton%(%d+, \"(%w+)\"") do
		table.insert(buttons, name)
	end
	H.eq(table.concat(buttons, ","), "Shop,Index")
	H.ok(string.find(HUD, "Name = \"SlowMode\"", 1, true), "the Slow Mode switch")
	H.ok(string.find(HUD, "opens == \"Trails\"", 1, true), "the TRAIL SHOP stall still opens the Trail Shop")
	H.ok(not string.find(REWARDS, "LeftColumn", 1, true), "Rewards.client adds no Gift button to the column")
	H.ok(string.find(REWARDS, "GetAttribute(\"FreeGift\")", 1, true), "the gift box's prompt opens the Free Gift window")
end)

H.test("Shop: bright cards with light rays, green R$ buttons, no filler text or SOON tags", function()
	H.ok(not string.find(HUD, "Added to your Speed right away", 1, true), "no filler line on the Speed cards")
	H.ok(not string.find(HUD, "\"SOON\"", 1, true) and not string.find(HUD, "soonTag", 1, true), "no SOON tags on the prices")
	H.ok(string.find(HUD, "local function sunburst", 1, true), "the cards' sunburst")
	H.ok(string.find(HUD, "Speed = Color3.fromRGB(30, 165, 255)", 1, true), "Speed cards blue")
	H.ok(string.find(HUD, "Money = Color3.fromRGB(255, 185, 25)", 1, true), "Money cards gold (shopui.spec: no green cards under the green R$ buttons)")
	H.ok(string.find(HUD, "ROBUX_GREEN = Color3.fromRGB(105, 235, 25)", 1, true), "bright green R$ buttons")
	-- every Speed product's label splits into the green number and the word ("+150K" / "SPEED")
	for _, entry in Config.products("Speed") do
		local amount, rest = string.match(string.upper(entry.product.label), "^(%S+)%s+(.+)$")
		H.ok(amount and string.sub(amount, 1, 1) == "+" and rest == "SPEED", entry.product.label)
	end
end)

H.test("HUD: no zone / recommended-Speed banner and no carry banner at the top", function()
	for _, gone in { "zoneBanner", "zoneLabel", "lastZone", "zoneAtX", "carryBanner", "carryLabel", "run home & plant it" } do
		H.ok(not string.find(HUD, gone, 1, true), `"{gone}" is gone from the HUD`)
	end
	H.ok(not string.find(HUD, "string.upper(z.name)", 1, true), "no \"SNOW PEAKS · Rec. Speed\" text")
end)

H.test("HUD toasts: at the top under Roblox's bar, below the zone banner while it shows; essentials only", function()
	local top, under = string.match(HUD, "local TOAST_TOP, TOAST_UNDER_BANNER = (%d+), (%d+)")
	H.ok(top and tonumber(top) <= 10, "just under the top bar")
	local BANNER = fs.readFile("src/client/ZoneBanner.client.luau")
	local bannerTop = tonumber(string.match(BANNER, "local TOP = (%d+)"))
	local stripH = tonumber(string.match(BANNER, "local STRIP_W, STRIP_H = %d+, (%d+)"))
	H.ok(bannerTop and stripH and under and tonumber(under) >= bannerTop + stripH, "moved under the zone banner's strip")
	H.ok(top and bannerTop and tonumber(top) + 36 <= bannerTop, "one toast fits above the banner")
	H.ok(string.find(HUD, "WaitForChild(\"ZoneBanner\"", 1, true) and string.find(HUD, "strip:GetPropertyChangedSignal(\"Visible\")", 1, true), "follows the banner")
	local holder = string.match(HUD, "local toastHolder = new%(\"Frame\", (%b{})")
	H.ok(holder and string.find(holder, "Position = UDim2.new(0.5, 0, 0, TOAST_TOP)", 1, true), "starts at the top")
	-- purely informational toasts are gone (sounds and the world show those)
	for _, gone in { "You stole a", "woke up!", "You escaped", "Planted {data.name}", "New Index entry", "Removed plant:", "Bought {data.label}", "WHACK", "for {data.count} plant" } do
		H.ok(not string.find(HUD, gone, 1, true), `no "{gone}" toast`)
	end
	H.ok(string.find(HUD, "\"The sun is up.\"", 1, true), "day/night still told, in words")
	H.ok(string.find(HUD, "caught you!", 1, true), "getting caught is still told")
end)

H.test("HUD: Shop / Index / Slow Mode are centred on the left edge; Speed and money stay bottom-left", function()
	local column = string.match(HUD, "local leftColumn = new%(\"Frame\", (%b{})")
	H.ok(column and string.find(column, "AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0)", 1, true), "anchored at the middle")
	local layout = string.match(HUD, "local leftColumn = new%(\"Frame\", %b{}, (%b{})")
	H.ok(layout and string.find(layout, "VerticalAlignment.Center", 1, true), "its buttons centred in it")
	local statsFrame = string.match(HUD, "local statsFrame = new%(\"Frame\", (%b{})")
	H.ok(statsFrame and string.find(statsFrame, "AnchorPoint = Vector2.new(0, 1)", 1, true), "Speed and money at the bottom")
	H.ok(string.find(HUD, "height / 2 - STATS_BOTTOM - STATS_H", 1, true), "the column shrinks before it reaches them")
end)

H.test("HUD: one window frame (owner 2026-10-15, round 2): a charcoal body for every window, a flat bar in each window's colour", function()
	for _, gone in { "BODY_COLOR", "SELL_DARK", "Color3.fromRGB(44, 50, 66)", "Color3.fromRGB(52, 58, 76)", "Color3.fromRGB(28, 24, 46)" } do
		H.ok(not string.find(HUD, gone, 1, true), `"{gone}" is gone from the HUD`)
	end
	H.ok(string.find(HUD, "BackgroundColor3 = WINDOW_BODY", 1, true), "the charcoal body")
	H.ok(string.find(HUD, "titleBar.BackgroundColor3 = window.bar", 1, true), "the bar tinted per window")
	for _, name in { "Shop", "Trails", "Index" } do
		local window = string.match(HUD, "	" .. name .. " = (%b{})")
		H.ok(window and string.find(window, "bar = Color3.fromRGB(", 1, true), `{name} has its bar colour`)
	end
	H.ok(string.find(HUD, "WINDOWS.Sell = { title = \"Sell\", bar = ", 1, true), "Sell too")
	H.ok(not string.find(REWARDS, "Color3.fromRGB(44, 50, 66)", 1, true), "the Free Gift window is bright")
end)

H.test("ZoneBanner.client: entering a zone flashes its name and a face for ~1 s (from Config.zoneAtX)", function()
	H.ok(fs.isFile("src/client/ZoneBanner.client.luau"), "the script exists")
	local BANNER = fs.readFile("src/client/ZoneBanner.client.luau")
	H.ok(string.find(BANNER, "Config.zoneAtX(root.Position.X)", 1, true), "zone from Config.zoneAtX")
	H.ok(string.find(BANNER, "local HOLD = 1", 1, true), "holds about one second")
	H.ok(string.find(BANNER, "CanvasGroup", 1, true) and string.find(BANNER, "{ GroupTransparency = 0 }", 1, true), "fades in as one")
	H.ok(string.find(BANNER, "{ GroupTransparency = 1, Position", 1, true), "fades and slides out")
	H.ok(string.find(BANNER, "NumberSequenceKeypoint.new(0, 1)", 1, true) and string.find(BANNER, "NumberSequenceKeypoint.new(1, 1)", 1, true),
		"the strip fades out at both ends")
	H.ok(not string.find(BANNER, "Your Base", 1, true) and not string.find(BANNER, "🏠", 1, true), "walking back into the base shows nothing")
	for _, zone in Config.ZONES do
		H.ok(string.find(BANNER, `%s{zone.id} = \{ color = Color3.fromRGB%(%d+, %d+, %d+%), face = "[^"]+" \}`), `{zone.id} has a colour and a face`)
	end
end)

----------------------------------------------------------------------------------------------------
-- The owner's playtest: plants removed from the Plants panel, roomier left column, plain-text windows
----------------------------------------------------------------------------------------------------
H.test("HUD Plants panel: a card per plant (flower name, rarity, $/s, day/night bonus, no Kg) with a Remove that asks once", function()
	local a = string.find(HUD, "-- Plants panel (right side)", 1, true)
	local b = string.find(HUD, "-- Trail Shop strip scrolling", 1, true)
	local block = a and b and string.sub(HUD, a, b) or ""
	H.ok(block ~= "", "the Plants panel block")
	H.ok(string.find(block, "remotes:WaitForChild(\"RemovePlant\")", 1, true) and string.find(block, "RemovePlant:FireServer(slot)", 1, true), "Remove asks the server")
	H.ok(string.find(block, "local SURE_SECONDS = 2", 1, true) and string.find(block, "\"Sure?\"", 1, true), "\"Sure?\" for 2 s first")
	H.ok(string.find(block, "remove = chunky(f, \"Remove\"", 1, true), "a chunky (Shop-style) button on every card")
	H.ok(string.find(block, "p.name or SeedPacks.seedName", 1, true), "the plant's flower name")
	H.ok(string.find(block, "Config.bonusLabel(", 1, true) and not string.find(block, "Format.weight(", 1, true), "the day/night bonus, and no Kg")
	H.ok(string.find(block, "accent = if mut then mut.color else rarity.color", 1, true), "a rarity (or mutation) accent")
	H.ok(string.find(block, "`🪴 Plants {#plants}/{stats.slots} · {Format.money(stats.income)}/s`", 1, true), "\"Plants 1/5 · $5/s\"")
	H.ok(string.find(block, "if not full and signature == shown then", 1, true), "a payout updates the cards in place (no rebuild under the cursor)")
	H.ok(not string.find(HUD, "R on a plant", 1, true), "no mention of the old R-key remove")
end)

H.test("HUD: more room between Shop, Index and Slow Mode", function()
	local gap = tonumber(string.match(HUD, "local LEFT_GAP = (%d+)"))
	H.ok(gap and gap >= 16, "a gap of 16+ design pixels")
	local column = string.match(HUD, "local leftColumn = new%(\"Frame\", %b{}, (%b{})")
	H.ok(column and string.find(column, "Padding = UDim.new(0, LEFT_GAP)", 1, true), "the column's layout uses it")
	H.ok(string.find(HUD, "LEFT_H = 176, SIDE_H * 2 + 30 + 2 * LEFT_GAP", 1, true), "and the column's height counts it")
end)

H.test("HUD Sell window: mutation only on mutated plants, no \"no mutation\", no emoji; flower names on the cards", function()
	local a = string.find(HUD, "-- SELL window", 1, true)
	local b = string.find(HUD, "end of SELL", 1, true)
	local block = a and b and string.gsub(string.sub(HUD, a, b), "\r", "") or ""
	H.ok(block ~= "", "the Sell block")
	H.ok(not string.find(block, "\"no mutation\"", 1, true), "nothing on a plant without a mutation")
	H.ok(string.find(block, "if mut then\n\t\t\tbold(c, 2, { Text = mut.id", 1, true), "the mutation's name in its colour on a mutated one")
	H.ok(string.find(block, "\"Quick sells skip mutated plants.\"", 1, true), "the short quick-sell note")
	H.ok(string.find(block, "p.name or SeedPacks.seedName", 1, true), "the plant's flower name")
end)

H.test("HUD Index: zone names as row titles (no emoji), a cell per flower from the server's catalog", function()
	local a = string.find(HUD, "local function renderIndex()", 1, true)
	local b = string.find(HUD, "-- SELL window", 1, true)
	local block = a and b and string.sub(HUD, a, b) or ""
	H.ok(string.find(block, "local title = zone.name", 1, true), "the row title is the zone's name")
	H.ok(string.find(block, "stats.catalog", 1, true) and string.find(block, "`{k}:{r}:{model}`", 1, true), "a cell per flower, lit by its Index key")
	H.ok(string.find(block, "Format.plantName(model)", 1, true), "named like the plants")
end)

H.test("Trail Shop: the R$ price button is the Shop's bright green", function()
	local a = string.find(HUD, "local function trailCard", 1, true)
	local b = string.find(HUD, "function renderTrails()", 1, true)
	local block = a and b and string.sub(HUD, a, b) or ""
	H.ok(string.find(block, "robuxColor(product.id, ROBUX_GREEN)", 1, true), "green")
	H.ok(not string.find(HUD, "COLORS.robux", 1, true), "no purple R$ left")
end)

-- Emoji: the owner keeps only the window / panel header icons, the HUD's icon buttons and the lock. Every
-- other emoji in the UI's text is gone (where one meant something, words or colour say it now).
do
	local function isEmoji(c: number): boolean
		return (c >= 0x2300 and c <= 0x23FF) or (c >= 0x2600 and c <= 0x27BF) or (c >= 0x2B00 and c <= 0x2BFF) or (c >= 0x1F000 and c <= 0x1FAFF)
	end
	-- Per file: the code (Lua patterns on the line) where an icon may stand in its emoji.
	local ALLOWED: { [string]: { string } } = {
		["src/client/HUD.client.luau"] = {
			"^%s*iconLabel%(statsFrame", "^sideButton%(", "button%(hotbar", "Icons%.set%(sideTitle", "^for _, tab in", "Icons%.set%(modalSubtitle",
			"chunky%(parent, \"🎁\"", "Text = \"🏃\"", "^button%(rightTabs, \"🪴\"",
		},
		["src/client/Rewards.client.luau"] = { "iconLabel%(" },
		["src/client/ZoneBanner.client.luau"] = { "face = \"" }, -- the zone banner's faces (owner-approved design)
		["src/client/DayTimer.client.luau"] = { "emoji%(" }, -- the timer's phase icon
	}

	H.test("UI text has no decorative emoji (header icons, icon buttons and the lock 🔒 only)", function()
		for file, allowed in ALLOWED do
			local source = string.gsub(fs.readFile(file), "\r", "")
			local n = 0
			for _, line in string.split(source, "\n") do
				n += 1
				if string.match(line, "^%s*%-%-") then
					continue -- a comment
				end
				local code = string.gsub(line, "%s%-%-%s[^\"`]*$", "") -- a trailing comment
				local found = {}
				for _, c in utf8.codes(code) do
					if isEmoji(c) and utf8.char(c) ~= "🔒" then
						table.insert(found, utf8.char(c))
					end
				end
				if #found > 0 then
					local ok = false
					for _, pattern in allowed do
						ok = ok or string.find(code, pattern) ~= nil
					end
					H.ok(ok, `{file}:{n}: emoji {table.concat(found, " ")} in "{string.match(code, "^%s*(.-)%s*$")}"`)
				end
			end
		end
		-- emoji that come from data: the zones' icons and the day/night icons stay out of the UI's text
		for _, file in { "src/client/HUD.client.luau", "src/client/Rewards.client.luau", "src/client/Planting.client.luau" } do
			local source = fs.readFile(file)
			H.ok(not string.find(source, "zone.icon", 1, true) and not string.find(source, ".icon}", 1, true), `{file}: no zone icons in text`)
			H.ok(not string.find(source, "ACTIVE_ICONS", 1, true), `{file}: no day/night icons in text`)
		end
		-- the server's texts (toasts, announcements) show in words too: the toast drops emoji but the lock
		H.ok(string.find(HUD, "return if emoji and ch ~= \"🔒\" then \"\" else nil", 1, true) ~= nil, "toasts drop emoji")
	end)
end

----------------------------------------------------------------------------------------------------
-- The day/night timer (DayTimer.client) and the shared UI juice (Shared/UiFx)
----------------------------------------------------------------------------------------------------
H.test("Format.countdown: \"in 2m 58s\" style", function()
	H.eq(Format.countdown(178), "2m 58s")
	H.eq(Format.countdown(178.9), "2m 58s")
	H.eq(Format.countdown(60), "1m 00s")
	H.eq(Format.countdown(45), "45s")
	H.eq(Format.countdown(0), "0s")
	H.eq(Format.countdown(-3), "0s")
	H.eq(Format.countdown(3725), "1h 2m")
end)

H.test("DayTimer.client: top right, a translucent dark strip, a phase icon and bold italic relief text", function()
	H.ok(fs.isFile("src/client/DayTimer.client.luau"), "the script exists")
	local TIMER = fs.readFile("src/client/DayTimer.client.luau")
	local strip = string.match(TIMER, "local strip = new%(\"Frame\", (%b{})")
	H.ok(strip ~= nil, "the strip")
	H.ok(strip and string.find(strip, "AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -TIMER_RIGHT, 0, TIMER_TOP)", 1, true),
		"anchored at the top-right corner")
	local right, top = string.match(TIMER, "local TIMER_RIGHT, TIMER_TOP = (%d+), (%d+)")
	H.ok(right and tonumber(right) <= 20 and top and tonumber(top) <= 10, "hugging the top-right edge")
	H.ok(string.find(TIMER, "IgnoreGuiInset = true", 1, true), "in the top bar's row, clear of the player list")
	H.ok(strip and string.find(strip, "BackgroundTransparency = 0.4", 1, true), "translucent")
	H.ok(string.find(TIMER, "Enum.FontStyle.Italic", 1, true) and string.find(TIMER, "Enum.FontWeight.Heavy", 1, true), "heavy italic")
	H.ok(string.find(TIMER, "UiFx.relief(timeLabel", 1, true), "the time has relief")
	H.ok(string.find(TIMER, "`in {Format.countdown(remaining)}`", 1, true), "\"in 2m 58s\"")
	H.ok(string.find(TIMER, "\"☀️\"", 1, true) and string.find(TIMER, "\"🌙\"", 1, true) and string.find(TIMER, "\"☁️\"", 1, true), "sun / cloud-moon")
	H.ok(string.find(TIMER, "Config.dayPhase(workspace:GetServerTimeNow())", 1, true), "the shared clock")
	-- the old flat yellow box at the bottom right is gone from the HUD
	for _, gone in { "bottomRight", "dayFrame", "dayLabel", "Night in" } do
		H.ok(not string.find(HUD, gone, 1, true), `"{gone}" is gone from the HUD`)
	end
end)

H.test("HUD: Speed and money readouts have relief", function()
	H.ok(string.find(HUD, "UiFx.relief(speedValue", 1, true), "Speed")
	H.ok(string.find(HUD, "UiFx.relief(moneyValue", 1, true), "money")
end)

H.test("HUD: every button gets the shared hover pop (UiFx.watch on the HUD's ScreenGui, Rewards inside it)", function()
	H.ok(string.find(HUD, "local UiFx = require(Shared:WaitForChild(\"UiFx\"))", 1, true), "HUD requires UiFx")
	local a = string.find(HUD, "local gui = new(\"ScreenGui\"", 1, true)
	local w = string.find(HUD, "UiFx.watch(gui)", 1, true)
	local first = string.find(HUD, "new(\"TextButton\"", (a or 1), true)
	H.ok(a and w and first and a < w and w < first, "watching before the first button is made")
	H.ok(string.find(REWARDS, "WaitForChild(\"SeedHUD\")", 1, true), "the Rewards window lives in the HUD's ScreenGui")
	-- Shop and Index sit centred in a holder so they pop from the middle
	H.ok(string.find(HUD, "local holder = new(\"Frame\", { Name = label", 1, true), "side buttons in holders")
	H.ok(string.find(HUD, "AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1)", 1, true),
		"centred in them")
	H.ok(string.find(HUD, "closeButton:SetAttribute(\"NoPop\", true)", 1, true), "not the full-screen \"Click to continue\"")
	local FX = fs.readFile("src/shared/UiFx.luau")
	for _, event in { "MouseEnter", "MouseLeave", "MouseButton1Down", "MouseButton1Up", "InputBegan", "InputEnded" } do
		H.ok(string.find(FX, `b.{event}:Connect`, 1, true), `UiFx.pop hooks {event}`)
	end
	H.ok(string.find(FX, "Enum.EasingStyle.Back", 1, true) and string.find(FX, "Enum.EasingStyle.Elastic", 1, true), "springy easing")
end)

-- UiFx.pop on fake buttons: the tweens it plays as the mouse / a finger comes and goes.
do
	local luau = require("@lune/luau")
	local roblox = require("@lune/roblox")

	local function signal()
		local s = { handlers = {} }
		function s.Connect(self, f)
			table.insert(self.handlers, f)
			return { Disconnect = function() end }
		end
		function s.Fire(self, ...)
			for _, f in self.handlers do
				f(...)
			end
		end
		return s
	end

	type Fake = any
	local function loadFx(lastInput: string)
		local tweens = {}
		local env = {
			game = {
				GetService = function(_, name)
					if name == "TweenService" then
						return {
							Create = function(_, inst, info, goal)
								local t = { info = info, goal = goal, Completed = signal() }
								function t.Play()
									table.insert(tweens, t)
								end
								function t.Cancel() end
								return t
							end,
						}
					elseif name == "UserInputService" then
						return {
							GetLastInputType = function()
								return (roblox.Enum.UserInputType :: any)[lastInput]
							end,
							IsMouseButtonPressed = function()
								return true
							end,
						}
					end
					return { RenderStepped = signal() }
				end,
			},
			Instance = {
				new = function(class)
					return { ClassName = class, Scale = 1 }
				end,
			},
			TweenInfo = {
				new = function(time, style, direction)
					return { time = time, style = style, direction = direction }
				end,
			},
			Enum = roblox.Enum, Vector2 = roblox.Vector2, UDim2 = roblox.UDim2, Color3 = roblox.Color3,
			ColorSequence = roblox.ColorSequence, ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
			task = { defer = function(f, ...) f(...) end },
			math = math, string = string, table = table, assert = assert, ipairs = ipairs, pairs = pairs,
		}
		local Fx = luau.load(fs.readFile("src/shared/UiFx.luau"), { debugName = "UiFx", environment = env })()
		return Fx, tweens
	end

	local function fakeButton(inLayout: boolean): Fake
		local parent = {
			FindFirstChildWhichIsA = function(_, class)
				return if class == "UIGridStyleLayout" and inLayout then {} else nil
			end,
		}
		local b: Fake = {
			AnchorPoint = roblox.Vector2.new(0, 0), Position = roblox.UDim2.fromOffset(100, 50), Size = roblox.UDim2.fromOffset(80, 40),
			Parent = parent, children = {},
		}
		for _, e in { "MouseEnter", "MouseLeave", "MouseButton1Down", "MouseButton1Up", "InputBegan", "InputEnded" } do
			b[e] = signal()
		end
		function b.GetAttribute()
			return nil
		end
		function b.FindFirstChildWhichIsA(self, class)
			for _, c in self.children do
				if c.ClassName == class then
					return c
				end
			end
			return nil
		end
		return b
	end

	H.test("UiFx.pop: hover inflates to 1.1 (Back), leaving shrinks back, a click squashes then springs", function()
		local Fx, tweens = loadFx("MouseMovement")
		local b = fakeButton(false)
		Fx.pop(b)
		b.MouseEnter:Fire()
		H.eq(#tweens, 1)
		H.eq(tweens[1].goal.Scale, 1.1)
		H.eq(tweens[1].info.style, roblox.Enum.EasingStyle.Back)
		-- scaled about its centre while popped
		H.eq(b.AnchorPoint, roblox.Vector2.new(0.5, 0.5))
		H.eq(b.Position, roblox.UDim2.fromOffset(140, 70))
		b.MouseButton1Down:Fire()
		H.eq(tweens[2].goal.Scale, Fx.PRESS)
		H.ok(Fx.PRESS < 1, "squash")
		b.MouseButton1Up:Fire()
		H.eq(tweens[3].goal.Scale, 1.1)
		H.eq(tweens[3].info.style, roblox.Enum.EasingStyle.Elastic)
		b.MouseLeave:Fire()
		H.eq(tweens[4].goal.Scale, 1)
		tweens[4].Completed:Fire(roblox.Enum.PlaybackState.Completed)
		H.eq(b.AnchorPoint, roblox.Vector2.new(0, 0), "back to its own anchor at rest")
		H.eq(b.Position, roblox.UDim2.fromOffset(100, 50))
	end)

	H.test("UiFx.pop: a button's PopScale attribute replaces the hover size (a long button beside another pops less)", function()
		local Fx, tweens = loadFx("MouseMovement")
		local b = fakeButton(false)
		function b.GetAttribute(_, name)
			return if name == "PopScale" then 1.05 else nil
		end
		Fx.pop(b)
		b.MouseEnter:Fire()
		H.eq(tweens[1].goal.Scale, 1.05)
		b.MouseButton1Down:Fire()
		b.MouseButton1Up:Fire()
		H.eq(tweens[3].goal.Scale, 1.05, "springs back to its own size")
		b.MouseLeave:Fire()
		H.eq(tweens[4].goal.Scale, 1)
	end)

	H.test("UiFx.pop: a finger press inflates, lifting it springs back; taps don't stick as hovers", function()
		local Fx, tweens = loadFx("Touch")
		local b = fakeButton(true)
		Fx.pop(b)
		b.MouseEnter:Fire() -- a tap sends MouseEnter but never MouseLeave
		b.MouseButton1Down:Fire()
		H.eq(#tweens, 0, "no hover and no squash from a tap")
		local touch = { UserInputType = roblox.Enum.UserInputType.Touch }
		b.InputBegan:Fire(touch)
		H.eq(tweens[1].goal.Scale, 1.1)
		H.eq(b.AnchorPoint, roblox.Vector2.new(0, 0), "a layout places it: never re-anchored")
		b.InputEnded:Fire(touch)
		H.eq(tweens[2].goal.Scale, 1)
		H.eq(tweens[2].info.style, roblox.Enum.EasingStyle.Elastic)
	end)
end

H.test("Shop scroll: an unchanged re-sent stat never rebuilds the open window (owner: \"why does the shop money menu go up\")", function()
	local StatsDiff = H.shared("StatsDiff")
	local stats: { [string]: any } = { money = 0, slots = 10, items = { Bat = 1 }, seedBag = {}, passes = {}, trails = { Grey = true } }
	-- the 1 s payout: money only
	local changed = StatsDiff.apply(stats, { money = 25, speed = 0, walkSpeed = 16, income = 25 })
	H.eq(changed.money, 25)
	H.eq(stats.money, 25, "copied into the client's stats")
	-- the plants push every PLANTS_PUSH_EVERY payouts re-sends `slots` (unchanged): that used to rebuild the Shop
	changed = StatsDiff.apply(stats, { plants = {}, inventory = {}, slots = 10 })
	H.eq(changed.slots, nil, "same slots: not a change")
	-- a full push with nothing new
	changed = StatsDiff.apply(stats, { slots = 10, items = { Bat = 1 }, seedBag = {}, passes = {}, trails = { Grey = true } })
	H.eq(next(changed), nil, "nothing changed")
	-- real changes still count, also inside tables and to false
	changed = StatsDiff.apply(stats, { items = { Bat = 2 }, trails = { Grey = true, Red = true }, slots = 11 })
	H.ok(changed.items and changed.trails and changed.slots == 11, "real changes")
	stats.carrying = { zone = 1 }
	changed = StatsDiff.apply(stats, { carrying = false })
	H.ok(changed.carrying == false and stats.carrying == false, "a change to false")
	H.ok(StatsDiff.same({ a = { b = 1 } }, { a = { b = 1 } }) and not StatsDiff.same({ a = 1 }, { a = 1, b = 2 }), "deep equality")
	-- the HUD diffs every StatsUpdate before deciding what to rebuild; money ticks only update in place
	local hud = string.gsub(fs.readFile("src/client/HUD.client.luau"), "\r", "")
	H.ok(string.find(hud, "refresh(StatsDiff.apply(stats, partial))", 1, true) ~= nil, "StatsUpdate goes through StatsDiff")
	local refresh = string.match(hud, "local function refresh%(changed.-\nend\n") or ""
	local rebuild = string.match(refresh, "elseif modal.Visible and %((.-)%) then\n\t\trenderModal%(%)") or ""
	H.ok(#rebuild > 0 and not string.find(rebuild, "changed.money", 1, true) and not string.find(rebuild, "changed.income", 1, true)
		and not string.find(rebuild, "changed.speed", 1, true), "money / income / Speed never rebuild the window")
	H.ok(string.find(refresh, "for _, update in moneyWatchers do", 1, true) ~= nil, "they update the buy buttons in place")
	-- a real rebuild (a purchase) restores the scroll until the new canvas is sized, never past it
	H.ok(string.find(hud, "if modalBody.CanvasPosition.Y < keep.Y then\n\t\t\t\t\tmodalBody.CanvasPosition = keep", 1, true) ~= nil, "a rebuild keeps the scroll")
	-- and the window doesn't move: fitModal places it at one fixed spot
	local fit = string.match(hud, "local function fitModal%(%).-\nend\n") or ""
	H.ok(string.find(fit, "modal.Position = UDim2.new(0.5, 0, 0.5, (TOP - BOTTOM) / 2)", 1, true) ~= nil, "a fixed window spot")
end)

return nil
