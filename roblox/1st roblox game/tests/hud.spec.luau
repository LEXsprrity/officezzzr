-- The HUD: Speed levels (for the "LEVEL N!" pop-up), the Shop's small Speed products (+10K / +100K / +1M),
-- granted through the normal receipt path, and the layout: no level bar, only Shop and Index on the left.
local H = require("./harness")
local Config = H.shared("Config")
local Format = H.shared("Format")
local Shop = H.server("Shop")
local ProfileStore = H.server("ProfileStore")
local Sim = require("./progression_sim")

local NICE = { [1] = true, [1.5] = true, [2] = true, [2.5] = true, [3] = true, [4] = true, [5] = true, [7.5] = true }

local function mantissa(x: number): number
	local m = x / 10 ^ math.floor(math.log10(x))
	return math.round(m * 1000) / 1000
end

H.test("speed levels: level 1 at 0, strictly increasing, nice round thresholds", function()
	H.eq(Config.SPEED_LEVELS[1], 0)
	local level, start, nextAt = Config.speedLevel(0)
	H.eq(level, 1)
	H.eq(start, 0)
	H.eq(nextAt, Config.SPEED_LEVELS[2])
	for n = 2, #Config.SPEED_LEVELS + 12 do
		local t = Config.speedLevelThreshold(n)
		H.ok(t > Config.speedLevelThreshold(n - 1), `level {n} above level {n - 1}`)
		H.ok(NICE[mantissa(t)], `level {n} at {Format.short(t)} is a nice number`)
		H.ok(not string.find(Format.short(t), "%.%d%d"), `"{Format.short(t)}" reads short`)
	end
	-- past the table: 10B, 20B, 50B, 100B
	local n = #Config.SPEED_LEVELS
	H.eq(Config.speedLevelThreshold(n + 1), 10e9)
	H.eq(Config.speedLevelThreshold(n + 2), 20e9)
	H.eq(Config.speedLevelThreshold(n + 3), 50e9)
	H.eq(Config.speedLevelThreshold(n + 4), 100e9)
end)

H.test("speed levels: every zone's recommended Speed is a level; 25-30 levels to the Spirit Garden", function()
	for k, zone in Config.ZONES do
		local level, start = Config.speedLevel(zone.req)
		H.eq(start, zone.req, `{zone.name} starts a level`)
		if k > 1 then
			H.ok(Config.speedLevel(zone.req - 1) == level - 1, `{zone.name}: one Speed short is the level below`)
		end
	end
	local spirit = Config.speedLevel(Config.ZONES[#Config.ZONES].req)
	H.ok(spirit >= 25 and spirit <= 30, `level {spirit} at 5B`)
end)

H.test("speed levels: speedLevel is monotonic and consistent with its thresholds", function()
	local last = 0
	local speed = 0
	while speed < 1e15 do
		local level, start, nextAt = Config.speedLevel(speed)
		H.ok(level >= last, `monotonic at {speed}`)
		H.ok(start <= speed and speed < nextAt, `{speed} in [{start}, {nextAt})`)
		H.eq(start, Config.speedLevelThreshold(level))
		H.eq(nextAt, Config.speedLevelThreshold(level + 1))
		last = level
		speed = speed * 1.07 + 13
	end
	-- exactly on and just under each threshold
	for n = 2, #Config.SPEED_LEVELS + 9 do
		local t = Config.speedLevelThreshold(n)
		H.eq((Config.speedLevel(t)), n, `on {Format.short(t)}`)
		H.eq((Config.speedLevel(t * 0.999)), n - 1, `under {Format.short(t)}`)
	end
	-- garbage in, sane level out
	H.eq((Config.speedLevel(-5)), 1)
	H.eq((Config.speedLevel(0 / 0)), 1)
	local huge, hs, hn = Config.speedLevel(math.huge)
	H.ok(huge > 100 and hs < hn and hn < math.huge, "infinite Speed is clamped")
end)

H.test("speed levels: a free player levels up every few minutes early and keeps levelling up all game", function()
	local free = Sim.run()
	local spirit = Config.speedLevel(Config.ZONES[#Config.ZONES].req)
	H.ok(#free.levels >= spirit, "the free player reaches the Spirit Garden's level")
	H.ok(free.levels[2] <= 2 * 60, `level 2 at {Sim.clock(free.levels[2])}`)
	local gaps = {}
	for n = 2, spirit do
		local gap = free.levels[n] - free.levels[n - 1]
		table.insert(gaps, Sim.clock(gap))
		if free.levels[n] <= 30 * 60 then
			H.ok(gap <= 10 * 60, `level {n} came {Sim.clock(gap)} after the last (first half hour)`)
		end
		H.ok(gap <= 75 * 60, `level {n} came {Sim.clock(gap)} after the last`)
	end
	print("        free player's level gaps: " .. table.concat(gaps, ", "))
end)

H.test("level up: no pop-up on the first stats, one per new level, the highest when several at once", function()
	local best, show = Config.levelUp(nil, 12)
	H.eq(best, 12)
	H.eq(show, nil, "joining at level 12 isn't a level-up")
	best, show = Config.levelUp(best, 12)
	H.eq(show, nil, "same level")
	best, show = Config.levelUp(best, 13)
	H.eq(show, 13)
	best, show = Config.levelUp(best, 18) -- a Speed pack jumps five levels
	H.eq(show, 18, "only the highest")
	H.eq(best, 18)
	best, show = Config.levelUp(best, 17)
	H.eq(show, nil, "never announces going down")
	H.eq(best, 18, "keeps the best")
	best, show = Config.levelUp(best, 18)
	H.eq(show, nil, "nor coming back to a level already announced")
end)

H.test("Speed packs: Speed10K, Speed100K and Speed1M are id = 0 Speed products, coming soon until set", function()
	local p = ProfileStore.defaultProfile()
	for name, want in { Speed10K = { 10e3, 9 }, Speed100K = { 100e3, 36 }, Speed1M = { 1e6, 76 } } do
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
	for i, c in { { "Speed10K", 10e3 }, { "Speed100K", 100e3 }, { "Speed1M", 1e6 } } do
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
	H.ok(string.find(HUD, "announceLevel(announce)", 1, true), `"LEVEL N!" still pops up`)
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
	H.ok(string.find(HUD, "Money = Color3.fromRGB(70, 205, 30)", 1, true), "Money cards green")
	H.ok(string.find(HUD, "ROBUX_GREEN = Color3.fromRGB(105, 235, 25)", 1, true), "bright green R$ buttons")
	-- every Speed product's label splits into the green number and the word ("+150K" / "SPEED")
	for _, entry in Config.products("Speed") do
		local amount, rest = string.match(string.upper(entry.product.label), "^(%S+)%s+(.+)$")
		H.ok(amount and string.sub(amount, 1, 1) == "+" and rest == "SPEED", entry.product.label)
	end
end)

return nil
