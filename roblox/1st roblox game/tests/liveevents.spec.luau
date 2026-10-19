-- The owner's live "admin abuse" events (owner 2026-10-19): Shared/LiveEvents' checks, merge and multiplier
-- math, and Server/LiveEventService's cross-server sync over a mocked MessagingService and MemoryStore.
local fs = require("@lune/fs")
local H = require("./harness")
local Config = H.shared("Config")
local LiveEvents = H.shared("LiveEvents")
local SpeedLogic = H.server("SpeedLogic")

----------------------------------------------------------------------------------------------------
-- Mocked MessagingService and MemoryStoreService (one topic bus and one HashMap, shared like the real ones)
----------------------------------------------------------------------------------------------------
local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = copy(x)
	end
	return out
end

local Messaging = { subscribers = {} :: { [string]: { (any) -> () } }, sent = {} :: { any }, failing = false }
function Messaging.PublishAsync(self, topic: string, data: any)
	if self.failing then
		error("MessagingService is not available in Studio")
	end
	table.insert(self.sent, { topic = topic, data = copy(data) })
	for _, fn in self.subscribers[topic] or {} do
		fn({ Data = copy(data), Sent = os.time() })
	end
end
function Messaging.SubscribeAsync(self, topic: string, fn: (any) -> ())
	self.subscribers[topic] = self.subscribers[topic] or {}
	table.insert(self.subscribers[topic], fn)
	return { Disconnect = function() end }
end

local Memory = { maps = {} :: { [string]: any }, failing = false, writes = 0 }
function Memory.GetHashMap(self, name: string)
	local map = self.maps[name]
	if not map then
		map = { data = {} :: { [string]: any } }
		function map.GetAsync(m, key: string)
			if Memory.failing then
				error("MemoryStore is busy")
			end
			return copy(m.data[key])
		end
		function map.UpdateAsync(m, key: string, fn: (any) -> any, expiration: number)
			if Memory.failing then
				error("MemoryStore is busy")
			end
			assert(type(expiration) == "number" and expiration > 0, "an expiration")
			local v = fn(copy(m.data[key]))
			if v ~= nil then
				m.data[key] = copy(v)
				Memory.writes += 1
			end
			return v
		end
		self.maps[name] = map
	end
	return map
end

local Text = { failing = false }
function Text.FilterStringAsync(self, text: string, _userId: number, _context: any)
	if self.failing then
		error("filter down")
	end
	return { GetNonChatStringForBroadcastAsync = function()
		return (string.gsub(text, "badword", "#######"))
	end }
end

H.services.MessagingService = Messaging
H.services.MemoryStoreService = Memory
H.services.TextService = Text

local LiveEventService = H.server("LiveEventService")
local T = 1_800_000_000
LiveEventService.clock = function()
	return T
end
local views: { { any } } = {}
LiveEventService.showView = function(running)
	table.insert(views, running)
end
local announced: { string } = {}
LiveEventService.showAnnounce = function(text: string)
	table.insert(announced, text)
end
local replies: { { text: string, ok: boolean } } = {}
LiveEventService.reply = function(_admin, text: string, ok: boolean)
	table.insert(replies, { text = text, ok = ok })
end
local adminPlayer = { UserId = 9301943082, Name = "LEXsprrity", DisplayName = "LEX" }
local otherPlayer = { UserId = 42, Name = "Kid", DisplayName = "Kid" }
LiveEventService.isAdmin = function(p)
	return p == adminPlayer
end
LiveEventService.COOLDOWN = 0 -- (os.clock barely moves in a test)
LiveEventService.init({ loops = false })

local function fresh()
	LiveEventService.reset()
	Memory:GetHashMap(LiveEvents.STORE).data = {}
	table.clear(Messaging.sent)
	Messaging.failing, Memory.failing, Text.failing = false, false, false
	table.clear(views)
	table.clear(announced)
	table.clear(replies)
	T = 1_800_000_000
end

local function storeList(): { any }
	return Memory:GetHashMap(LiveEvents.STORE).data[LiveEvents.STORE_KEY] or {}
end

----------------------------------------------------------------------------------------------------
-- Validation and clamping
----------------------------------------------------------------------------------------------------
H.test("live events: a start request is checked and clamped (at most 5x, 1 to 30 minutes)", function()
	local req = LiveEvents.checkStart({ kind = "Luck", mult = 3, minutes = 10 }, false) :: any
	H.eq(req.kind, "Luck")
	H.eq(req.mult, 3)
	H.eq(req.minutes, 10)
	H.eq((LiveEvents.checkStart({ kind = "Money", mult = 1000, minutes = 10 }, false) :: any).mult, 5, "clamped to 5x")
	H.eq((LiveEvents.checkStart({ kind = "Money", mult = -3, minutes = 10 }, false) :: any).mult, 2, "at least 2x")
	H.eq((LiveEvents.checkStart({ kind = "Speed", mult = 0 / 0, minutes = 10 }, false) :: any).mult, 2, "NaN: 2x")
	H.eq((LiveEvents.checkStart({ kind = "Luck", mult = 3, minutes = 999 }, false) :: any).minutes, 30)
	H.eq((LiveEvents.checkStart({ kind = "Luck", mult = 3, minutes = 0 }, false) :: any).minutes, 1)
	H.eq((LiveEvents.checkStart({ kind = "Luck", mult = 3, minutes = 7.9 }, false) :: any).minutes, 7)
	for i, bad in { { kind = "Luck", mult = 2 }, { kind = "Luck", mult = 2, minutes = math.huge }, { kind = "Robux", mult = 2, minutes = 5 },
		{ kind = "Mutation", option = "Haunted", minutes = 5 }, { kind = "Candy", minutes = 5 }, "Luck", nil } do
		H.eq(LiveEvents.checkStart(bad, false), nil, `bad request {i}`)
	end
	-- options
	H.eq((LiveEvents.checkStart({ kind = "Mutation", option = "Celestial", minutes = 5 }, false) :: any).option, "Celestial")
	H.eq((LiveEvents.checkStart({ kind = "Grow", option = "Instant", minutes = 5 }, false) :: any).option, "Instant")
	H.ok(LiveEvents.checkStart({ kind = "Candy", minutes = 5 }, true), "Candy rain while Halloween runs")
	-- the copy has only its own fields
	H.eq((LiveEvents.checkStart({ kind = "Luck", mult = 2, minutes = 5, evil = true }, false) :: any).evil, nil)
	-- every panel choice passes the server's check unchanged
	for kind, choices in LiveEvents.CHOICES do
		for _, c in choices do
			local r = LiveEvents.checkStart({ kind = kind, mult = c.mult, option = c.option, minutes = 10 }, true) :: any
			H.ok(r, `{kind} {c.label}`)
			H.eq(r.mult, c.mult, `{kind} {c.label}`)
			H.eq(r.option, c.option, `{kind} {c.label}`)
		end
	end
end)

H.test("live events: announcements are trimmed, one line, at most 120 characters", function()
	H.eq(LiveEvents.cleanText("  hi all \n"), "hi all")
	H.eq(LiveEvents.cleanText("a\nb"), "a b")
	H.eq(LiveEvents.cleanText("   "), nil)
	H.eq(LiveEvents.cleanText(5), nil)
	H.eq(#(LiveEvents.cleanText(string.rep("x", 500)) :: string), LiveEvents.MAX_TEXT)
	H.eq(utf8.len(LiveEvents.cleanText(string.rep("é", 500)) :: string), LiveEvents.MAX_TEXT, "cut on a character")
end)

H.test("live events: events from messages and the store are checked (junk dropped, values clamped)", function()
	H.ok(LiveEvents.checkEvent({ id = "a", kind = "Luck", mult = 3, startedAt = 0, endsAt = 600 }))
	H.eq((LiveEvents.checkEvent({ id = "a", kind = "Luck", mult = 50, startedAt = 0, endsAt = 600 }) :: any).mult, 5)
	for i, bad in {
		{ id = "a", kind = "Nope", startedAt = 0, endsAt = 60 }, { kind = "Luck", startedAt = 0, endsAt = 60 },
		{ id = "a", kind = "Luck", startedAt = 60, endsAt = 0 }, { id = "a", kind = "Luck", startedAt = 0, endsAt = 31 * 60 + 5 },
		{ id = string.rep("x", 65), kind = "Luck", startedAt = 0, endsAt = 60 }, { id = "a", kind = "Luck", startedAt = 0 / 0, endsAt = 60 }, 7,
	} do
		H.eq(LiveEvents.checkEvent(bad), nil, `bad event {i}`)
	end
end)

H.test("live events: names and banner text", function()
	local ev = { id = "a", kind = "Luck", mult = 3, startedAt = 0, endsAt = 600 }
	H.eq(LiveEvents.banner(ev), "ADMIN ABUSE! 3x LUCK for 10 minutes!")
	H.eq(LiveEvents.describe({ kind = "Mutation", option = "Gold" }), "ALL GOLD SEEDS")
	H.eq(LiveEvents.describe({ kind = "Grow", option = "Instant" }), "INSTANT GROW")
	H.eq(LiveEvents.describe({ kind = "Candy" }), "CANDY RAIN")
	H.eq(LiveEvents.banner({ id = "b", kind = "Money", mult = 2, startedAt = 0, endsAt = 60 }), "ADMIN ABUSE! 2x MONEY for 1 minute!")
	H.eq(LiveEvents.clock(581), "9:41")
	H.eq(LiveEvents.clock(-5), "0:00")
	for _, kind in LiveEvents.KINDS do
		H.ok(LiveEvents.about({ kind = kind }) ~= "", kind)
	end
end)

----------------------------------------------------------------------------------------------------
-- Expiry, merge, stop
----------------------------------------------------------------------------------------------------
H.test("live events: they end at their absolute endsAt, whoever's clock", function()
	local events = { a = { id = "a", kind = "Luck", mult = 3, startedAt = 1000, endsAt = 1600 } }
	H.eq(LiveEvents.mult(events, "Luck", 1599), 3)
	H.eq(LiveEvents.mult(events, "Luck", 1600), 1, "over at endsAt")
	H.eq(#LiveEvents.running(events, 1600), 0)
	H.eq(LiveEvents.prune(events, 1599), false)
	H.eq(LiveEvents.prune(events, 1600), true)
	H.eq(events.a, nil)
	-- an expired event from a message or the store never starts
	local into = {}
	local started = LiveEvents.merge(into, { { id = "old", kind = "Luck", mult = 2, startedAt = 0, endsAt = 60 } }, 61)
	H.eq(#started, 0)
	H.eq(into.old, nil)
end)

H.test("live events: lists merge by id, a stop wins, an older list never brings a stopped event back", function()
	local now = 100
	local ev = { id = "e1", kind = "Money", mult = 2, startedAt = 90, endsAt = 690 }
	local into = {}
	local started, changed = LiveEvents.merge(into, { ev }, now)
	H.eq(#started, 1)
	H.ok(changed)
	-- the same event again (the store after the message, or our own message): nothing new
	started, changed = LiveEvents.merge(into, { ev, ev }, now)
	H.eq(#started, 0)
	H.eq(changed, false)
	-- the stop arrives
	local stopped = table.clone(ev)
	stopped.stopped = true
	started, changed = LiveEvents.merge(into, { stopped }, now)
	H.ok(changed)
	H.eq(LiveEvents.mult(into, "Money", now), 1, "stopped")
	-- then an older copy (a store read from before the stop): it stays stopped
	started, changed = LiveEvents.merge(into, { ev }, now)
	H.eq(changed, false)
	H.eq(LiveEvents.mult(into, "Money", now), 1)
	-- a server that only ever hears the tombstone never runs it
	local other = {}
	started = LiveEvents.merge(other, { stopped }, now)
	H.eq(#started, 0)
	H.eq(#LiveEvents.running(other, now), 0)
	-- junk in a list is skipped, the rest kept
	local mixed = {}
	started = LiveEvents.merge(mixed, { "junk", { id = "x" }, { id = "e2", kind = "Speed", mult = 3, startedAt = 90, endsAt = 400 } }, now)
	H.eq(#started, 1)
	H.eq(LiveEvents.merge({}, "not a list", now)[1], nil)
end)

----------------------------------------------------------------------------------------------------
-- The service: admin-only, cross-server sync, new servers, stop, Studio
----------------------------------------------------------------------------------------------------
H.test("live events: only admins can start, stop or announce (the server checks again)", function()
	fresh()
	LiveEventService.request(otherPlayer :: any, { op = "start", kind = "Luck", mult = 5, minutes = 30 })
	LiveEventService.request(otherPlayer :: any, { op = "announce", text = "free robux" })
	H.eq(#Messaging.sent, 0, "nothing published")
	H.eq(next(LiveEventService.events()), nil, "nothing runs")
	H.eq(#announced, 0)
	H.eq(#replies, 0, "not even an answer")
	LiveEventService.request(adminPlayer :: any, { op = "start", kind = "Luck", mult = 3, minutes = 10 })
	H.eq(LiveEventService.mult("Luck"), 3)
	local id = next(LiveEventService.events())
	LiveEventService.request(otherPlayer :: any, { op = "stop", id = id })
	H.eq(LiveEventService.mult("Luck"), 3, "a non-admin can't stop it")
	-- the wiring: AdminService ignores non-admins on the AdminEvent remote and rate-limits it
	local admin = fs.readFile("src/server/AdminService.luau")
	local handler = string.match(admin, "local function onAdminEvent%(.-\nend") or ""
	H.ok(string.find(handler, "if not admins[admin] then", 1, true), "non-admins are ignored")
	H.ok(string.find(handler, "Sessions.allowRequest(s, 2)", 1, true), "rate-limited")
	H.ok(string.find(admin, "Net.AdminEvent.OnServerEvent:Connect(onAdminEvent)", 1, true))
	H.ok(string.find(fs.readFile("src/server/Net.luau"), 'AdminEvent = remote("AdminEvent")', 1, true))
	local main = fs.readFile("src/server/Main.server.luau")
	H.ok(string.find(main, 'task.spawn(require(Server:WaitForChild("LiveEventService")).init)', 1, true))
end)

H.test("live events: a start runs here at once, goes into the store and out to every server", function()
	fresh()
	LiveEventService.request(adminPlayer :: any, { op = "start", kind = "Money", mult = 2, minutes = 10 })
	H.eq(LiveEventService.mult("Money"), 2)
	H.ok(replies[1].ok, replies[1].text)
	H.eq(#Messaging.sent, 1)
	H.eq(Messaging.sent[1].topic, LiveEvents.TOPIC)
	H.eq(Messaging.sent[1].data.op, "sync")
	local list = storeList()
	H.eq(#list, 1)
	H.eq(list[1].kind, "Money")
	H.eq(list[1].endsAt, T + 600, "absolute end time")
	H.eq(#views[#views], 1, "the clients see it")
	-- a bad request is refused and says why
	LiveEventService.request(adminPlayer :: any, { op = "start", kind = "Nope", minutes = 5 })
	H.eq(replies[#replies].ok, false)
end)

H.test("live events: a message from another server applies here; a stop from there stops it", function()
	fresh()
	local ev = { id = "far-1", kind = "Speed", mult = 5, startedAt = T - 10, endsAt = T + 290 }
	local starts = 0
	LiveEventService.onStart(function(e)
		if e.id == "far-1" then
			starts += 1
		end
	end)
	Messaging:PublishAsync(LiveEvents.TOPIC, { op = "sync", events = { ev } })
	H.eq(LiveEventService.mult("Speed"), 5)
	H.eq(starts, 1, "its start hook ran (Candy rain uses it)")
	Messaging:PublishAsync(LiveEvents.TOPIC, { op = "sync", events = { ev } })
	H.eq(starts, 1, "once")
	local stop = table.clone(ev) :: any
	stop.stopped = true
	Messaging:PublishAsync(LiveEvents.TOPIC, { op = "sync", events = { stop } })
	H.eq(LiveEventService.mult("Speed"), 1)
	H.eq(#views[#views], 0, "gone from the strip")
end)

H.test("live events: a new server picks up running events from the store; a lost message is caught by the poll", function()
	fresh()
	LiveEventService.request(adminPlayer :: any, { op = "start", kind = "Luck", mult = 5, minutes = 30 })
	LiveEventService.reset() -- this server restarts (or another one starts): it knows nothing
	H.eq(LiveEventService.mult("Luck"), 1)
	LiveEventService.poll()
	H.eq(LiveEventService.mult("Luck"), 5, "picked up from the store")
	-- another server's event whose message never came: the poll finds it
	local list = storeList()
	table.insert(list, { id = "lost", kind = "Grow", option = "Instant", startedAt = T, endsAt = T + 60 })
	Memory:GetHashMap(LiveEvents.STORE).data[LiveEvents.STORE_KEY] = list
	LiveEventService.poll()
	H.eq(LiveEventService.sproutSeconds(1, 1, 1), 0, "Instant grow from the store")
	-- and after its end time nobody runs it
	T += 61
	LiveEventService.poll()
	H.ok(LiveEventService.sproutSeconds(1, 1, 1) > 0)
	H.eq(LiveEventService.events().lost, nil, "pruned")
end)

H.test("live events: STOP ends it everywhere (a tombstone in the store, a message out)", function()
	fresh()
	LiveEventService.request(adminPlayer :: any, { op = "start", kind = "Luck", mult = 3, minutes = 10 })
	local id = next(LiveEventService.events())
	LiveEventService.request(adminPlayer :: any, { op = "stop", id = id })
	H.eq(LiveEventService.mult("Luck"), 1)
	H.ok(replies[#replies].ok, replies[#replies].text)
	H.eq(Messaging.sent[#Messaging.sent].data.events[1].stopped, true)
	H.eq(storeList()[1].stopped, true, "the store keeps it stopped")
	-- a new server reading the store doesn't run it
	LiveEventService.reset()
	LiveEventService.poll()
	H.eq(LiveEventService.mult("Luck"), 1)
	-- stopping twice, or junk: refused
	LiveEventService.request(adminPlayer :: any, { op = "stop", id = id })
	H.eq(replies[#replies].ok, false)
	LiveEventService.request(adminPlayer :: any, { op = "stop", id = 5 })
	H.eq(replies[#replies].ok, false)
end)

H.test("live events: without MessagingService or the store (Studio) the event still runs in this server", function()
	fresh()
	Messaging.failing, Memory.failing = true, true
	local before = #H.warnings
	LiveEventService.request(adminPlayer :: any, { op = "start", kind = "Money", mult = 3, minutes = 5 })
	H.eq(LiveEventService.mult("Money"), 3)
	H.ok(#H.warnings > before, "warned, never errored")
	LiveEventService.poll() -- (a failing read keeps what we have)
	H.eq(LiveEventService.mult("Money"), 3)
end)

H.test("live events: announcements are filtered for everyone, sent once to every server", function()
	fresh()
	LiveEventService.request(adminPlayer :: any, { op = "announce", text = "  hello badword everyone  " })
	H.eq(announced[1], "hello ####### everyone", "the filtered text is what's shown")
	local msg = Messaging.sent[1].data
	H.eq(msg.op, "announce")
	H.eq(msg.text, "hello ####### everyone", "only filtered text leaves this server")
	H.eq(#announced, 1, "our own message, heard back, isn't shown twice")
	Messaging:PublishAsync(LiveEvents.TOPIC, { op = "announce", id = "other-1", text = "from far away" })
	H.eq(announced[2], "from far away")
	-- no filter, no message
	Text.failing = true
	LiveEventService.request(adminPlayer :: any, { op = "announce", text = "hi" })
	H.eq(#announced, 2)
	H.eq(replies[#replies].ok, false)
	LiveEventService.request(adminPlayer :: any, { op = "announce", text = "   " })
	H.eq(replies[#replies].ok, false)
end)

----------------------------------------------------------------------------------------------------
-- What the events do (the pure helpers the game calls)
----------------------------------------------------------------------------------------------------
H.test("live events: two of a kind take the bigger, never the product; capped at 5x", function()
	local now = 10
	local events = {
		{ id = "a", kind = "Luck", mult = 3, startedAt = 0, endsAt = 100 }, { id = "b", kind = "Luck", mult = 2, startedAt = 0, endsAt = 100 },
		{ id = "c", kind = "Money", mult = 99, startedAt = 0, endsAt = 100 },
	}
	H.eq(LiveEvents.mult(events, "Luck", now), 3)
	H.eq(LiveEvents.mult(events, "Money", now), 5)
	H.eq(LiveEvents.mult(events, "Speed", now), 1)
end)

H.test("live events: Luck xN rolls stolen seeds rarer, the Legendary chance N times too", function()
	for zone = 1, #Config.ZONES do
		local base = Config.rarityWeights(zone, 1)
		local lucky = Config.rarityWeights(zone, 1 * 2 * 5) -- (2x Luck pass x a 5x event)
		H.near(lucky[Config.LEGENDARY], base[Config.LEGENDARY] * 10, 1e-12, `zone {zone}: Legendary x10`)
		H.ok(lucky[Config.LEGENDARY] < 0.5, "still a valid chance")
	end
	-- a pod's rarity re-drawn with 3x the luck is never lower, and higher on average
	local sumBase, sumLucky = 0, 0
	for i = 1, 2000 do
		local u = (i - 0.5) / 2000
		local rarity = 1
		local acc = 0
		for r, w in Config.rarityWeights(3, 1) do
			acc += w
			if u < acc then
				rarity = r
				break
			end
		end
		local up = Config.luckUpgrade(3, rarity, 1, 3, function()
			return (i * 0.618) % 1
		end)
		H.ok(up >= rarity)
		sumBase += rarity
		sumLucky += up
	end
	H.ok(sumLucky > sumBase * 1.1, `rarer: {sumLucky} vs {sumBase}`)
	local seed = fs.readFile("src/server/SeedService.luau")
	H.ok(string.find(seed, 'Sessions.luckMult(s) * LiveEventService.mult("Luck")', 1, true), "the steal uses it")
end)

H.test("live events: a Mutation storm: All Gold, or each mutation N times as likely", function()
	local now = 10
	local forced = { { id = "f", kind = "Mutation", option = "Rainbow", startedAt = 0, endsAt = 100 } }
	H.eq(LiveEvents.stealMutation(forced, nil, false, 0.5, now), "Rainbow")
	H.eq(LiveEvents.stealMutation(forced, "Gold", false, 0.5, now), "Rainbow")
	H.eq(LiveEvents.stealMutation({}, "Gold", false, 0.5, now), "Gold", "no storm: the pod's")
	H.eq(LiveEvents.stealMutation({}, nil, false, 0.01, now), nil)
	local storm = { { id = "s", kind = "Mutation", mult = 3, startedAt = 0, endsAt = 100 } }
	H.eq(LiveEvents.stealMutation(storm, "Diamond", false, 0.0, now), "Diamond", "keeps the pod's mutation")
	-- overall: P(m) = pod chance + (1 - base) x extra = 3 x chance
	local N = 20000
	local count: { [string]: number } = {}
	for i = 1, N do
		local u = (i - 0.5) / N
		local podMutation = nil
		local acc = 0
		for _, m in Config.MUTATIONS do
			if not m.nightOnly then
				if u < acc + m.chance then
					podMutation = m.id
					break
				end
				acc += m.chance
			end
		end
		local v = ((i * 7919) % N + 0.5) / N
		local got = LiveEvents.stealMutation(storm, podMutation, false, v, now)
		if got then
			count[got] = (count[got] or 0) + 1
		end
	end
	for _, m in Config.MUTATIONS do
		if not m.nightOnly and m.chance > 0 then
			H.near((count[m.id] or 0) / N, 3 * m.chance, 0.006, m.id)
		end
	end
	H.eq(count.Haunted, nil, "never Haunted")
	H.eq(count.Night, nil, "no Night by day")
	-- 5x at night stays under STORM_MAX_CHANCE in all
	local big = { { id = "s", kind = "Mutation", mult = 5, startedAt = 0, endsAt = 100 } }
	local hits = 0
	for i = 1, 1000 do
		if LiveEvents.stealMutation(big, nil, true, (i - 0.5) / 1000, now) then
			hits += 1
		end
	end
	H.ok(hits < 1000, "some stolen seeds stay plain")
	local seed = fs.readFile("src/server/SeedService.luau")
	H.ok(string.find(seed, "carry.podMutation = pod.mutation", 1, true), "a returned seed goes back to its pod as it was")
end)

H.test("live events: Money xN multiplies plant income in the payout only (offline and saves unaffected)", function()
	local plot = fs.readFile("src/server/PlotService.luau")
	H.ok(string.find(plot, 'local mult = Sessions.moneyMult(s) * LiveEventService.mult("Money")', 1, true), "the payout")
	local offline = string.match(plot, "PlotService.offlineEarnings%(s.profile[^\n]+") or ""
	H.ok(offline ~= "" and not string.find(offline, "LiveEvent", 1, true), "offline pay: no event")
	H.ok(not string.find(fs.readFile("src/server/Sessions.luau"), "LiveEvent", 1, true), "Sessions.moneyMult (sell, offline) untouched")
	for _, file in { "src/server/ProfileStore.luau", "src/server/Selling.luau", "src/server/Shop.luau" } do
		H.ok(not string.find(fs.readFile(file), "LiveEvent", 1, true), `{file}: never saved or sold with it`)
	end
	-- the payout's per-second income: base x plot/passes x event
	local base = Config.plantIncome(3, 2, 10, nil)
	local events = { { id = "m", kind = "Money", mult = 3, startedAt = 0, endsAt = 100 } }
	H.near(base * Config.moneyMult(4, nil) * LiveEvents.mult(events, "Money", 10), base * Config.moneyMult(4, nil) * 3, 1e-9)
end)

H.test("live events: Speed xN multiplies walking and treadmill gains", function()
	local events = { { id = "s", kind = "Speed", mult = 3, startedAt = 0, endsAt = 100 } }
	local live = LiveEvents.mult(events, "Speed", 10)
	local trail = Config.trailMult("Green")
	H.near(SpeedLogic.treadmillGain(5, trail * live), SpeedLogic.treadmillGain(5, trail) * 3, 1e-9, "treadmill")
	H.near(Config.speedPerStud("Green") * live, Config.speedPerStud("Green") * 3, 1e-12, "walking")
	local speed = fs.readFile("src/server/SpeedService.luau")
	H.ok(string.find(speed, "mult = Sessions.speedPerStud(s) * live,", 1, true) and string.find(speed, "trailMult = Sessions.speedMult(s) * live,", 1, true))
end)

H.test("live events: Grow fast divides the sprout time, Instant skips it", function()
	local now = 10
	H.eq(LiveEvents.sproutSeconds({}, 7, Config.LEGENDARY, 1, now), Config.sproutTime(7, Config.LEGENDARY))
	local fast = { { id = "g", kind = "Grow", mult = 5, startedAt = 0, endsAt = 100 } }
	H.eq(LiveEvents.sproutSeconds(fast, 7, Config.LEGENDARY, 1, now), 60, "5:00 / 5")
	H.eq(LiveEvents.sproutSeconds(fast, 7, Config.LEGENDARY, 2, now), 30, "with Fast Grow too")
	H.eq(LiveEvents.sproutSeconds(fast, 1, 1, 1, now), Config.SPROUT_ROUND, "never under the rounding")
	local instant = { { id = "i", kind = "Grow", option = "Instant", startedAt = 0, endsAt = 100 } }
	H.eq(LiveEvents.sproutSeconds(instant, 7, Config.LEGENDARY, 1, now), 0)
	H.eq(LiveEvents.sproutSeconds(instant, 7, Config.LEGENDARY, 1, 100), Config.sproutTime(7, Config.LEGENDARY), "over")
end)

H.test("live events: Candy rain raises the cap and drops a burst (only while Halloween runs)", function()
	local candy = fs.readFile("src/server/CandyService.luau")
	H.ok(string.find(candy, "LiveEventService.onStart(function(ev)", 1, true), "the burst")
	H.ok(string.find(candy, 'if ev.kind ~= "Candy" or not Halloween.active(os.time()) then', 1, true))
	H.ok(LiveEvents.CANDY_BURST > 0 and LiveEvents.CANDY_CAP_BONUS >= LiveEvents.CANDY_BURST)
	H.eq(LiveEvents.checkStart({ kind = "Candy", minutes = 5 }, false), nil, "refused outside Halloween")
end)

H.test("live events: the client strip stays clear of the Tutorial banner and the DayTimer", function()
	local client = fs.readFile("src/client/LiveEvents.client.luau")
	H.ok(string.find(client, 'Position = UDim2.new(1, -14, 0, 60)', 1, true), "top right, under the DayTimer (6 + 46 tall)")
	H.ok(string.find(client, "UiFx.relief", 1, true) and string.find(client, "ShopUi.studs", 1, true), "the HUD style")
	H.ok(string.find(client, 'ReplicatedStorage:WaitForChild(LiveEvents.FOLDER)', 1, true))
	local panel = fs.readFile("src/client/AdminPanel.client.luau")
	for _, needle in { '"START (ALL SERVERS)"', '"STOP"', '"SEND"', 'op = "announce"', 'op = "stop"' } do
		H.ok(string.find(panel, needle, 1, true), needle)
	end
end)
