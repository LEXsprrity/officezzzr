-- The owner's live "admin abuse" events, in every server at once (Shared/LiveEvents has what an event is).
--   client -> server: AdminEvent(request) (the admin panel's EVENTS page; AdminService checks it is an admin
--     and passes it on to LiveEventService.request, which checks again)
--       { op = "start", kind, mult?, option?, minutes } | { op = "stop", id } | { op = "announce", text }
--   server -> client: ReplicatedStorage.LiveEvents (a Configuration per running event, endsAt in server time;
--     LiveEvents.client draws the banner, the strip and "Event ended" from its children coming and going),
--     LootEvent "LiveAnnounce" { text, by } to everyone (an admin's message), "AdminResult" to the admin
-- Cross-server: the server that starts or stops an event applies it at once, writes it into the MemoryStore
-- HashMap (LiveEvents.STORE, key "active": every unexpired event, stopped ones as tombstones) and publishes it
-- on the MessagingService topic LiveEvents.TOPIC. Every server merges what it hears (LiveEvents.merge: by id, a
-- stop wins), reads the store when it starts (events still running) and again every POLL_SECONDS (a message
-- that got lost). Every call is pcall'd with retries; when MessagingService or the store don't work (Studio)
-- the event still runs in this server. Nothing here is ever saved into a profile.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LiveEvents = require(Shared:WaitForChild("LiveEvents"))
local Halloween = require(Shared:WaitForChild("Halloween"))

local LiveEventService = {}

local events: { [string]: LiveEvents.Event } = {}
local seenAnnounce: { [string]: number } = {} -- announcement id -> when (a server hears its own messages too)
local lastAsk: { [number]: number } = {} -- admin user id -> os.clock() of their last start or announcement
local counter = 0
local idRng = Random.new()

LiveEventService.COOLDOWN = 2 -- seconds between one admin's starts / announcements
LiveEventService.RETRIES = 3

-- Server time in seconds (the same clock in every server and on the clients: workspace:GetServerTimeNow()).
LiveEventService.clock = function(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return if ok and type(t) == "number" then t else os.time()
end

-- Who may ask (AdminService sets it to its own list); nobody until then.
LiveEventService.isAdmin = function(_player: Player): boolean
	return false
end

-- The services (init fills them; tests hand in mocks).
local messaging: any = nil
local memory: any = nil -- the HashMap
local textService: any = nil

-- What the clients see (tests replace them): ReplicatedStorage.LiveEvents holds one Configuration per running
-- event, named by its id, with its fields as attributes (Kind, Mult, Option, StartedAt, EndsAt).
local viewFolder: Folder? = nil
LiveEventService.showView = function(running: { LiveEvents.Event })
	local f = viewFolder
	if not f then
		f = Instance.new("Folder")
		f.Name = LiveEvents.FOLDER
		f.Parent = ReplicatedStorage
		viewFolder = f
	end
	local keep: { [string]: boolean } = {}
	for _, ev in running do
		keep[ev.id] = true
		if not f:FindFirstChild(ev.id) then
			local c = Instance.new("Configuration")
			c.Name = ev.id
			c:SetAttribute("Kind", ev.kind)
			c:SetAttribute("Mult", ev.mult)
			c:SetAttribute("Option", ev.option)
			c:SetAttribute("StartedAt", ev.startedAt)
			c:SetAttribute("EndsAt", ev.endsAt)
			c.Parent = f
		end
	end
	for _, c in f:GetChildren() do
		if not keep[c.Name] then
			c:Destroy()
		end
	end
end
LiveEventService.showAnnounce = function(_text: string, _by: string?) end -- init: Net.LootEvent FireAllClients
LiveEventService.reply = function(_admin: Player, _text: string, _ok: boolean) end -- init: Net "AdminResult"

local startHooks: { (LiveEvents.Event) -> () } = {}
-- `fn(event)` runs in this server whenever an event starts running here (also one picked up from the store).
function LiveEventService.onStart(fn: (LiveEvents.Event) -> ())
	table.insert(startHooks, fn)
end

local function try(what: string, fn: (...any) -> ...any, ...): (boolean, any)
	local err: any = nil
	for attempt = 1, LiveEventService.RETRIES do
		local ok, result = pcall(fn, ...)
		if ok then
			return true, result
		end
		err = result
		if attempt < LiveEventService.RETRIES then
			task.wait(attempt * 0.5)
		end
	end
	warn(`[LiveEventService] {what} failed:`, err)
	return false, err
end

-- An id unique across servers: this server's JobId (empty in Studio), a counter and a random number.
local function newId(): string
	counter += 1
	local job = if typeof(game) == "Instance" then string.sub(game.JobId, 1, 36) else ""
	return string.format("%s-%d-%08x", job, counter, idRng:NextInteger(0, 0x7fffffff))
end

local viewKey = ""
local function refreshView()
	local running = LiveEvents.running(events, LiveEventService.clock())
	local ids = {}
	for _, ev in running do
		table.insert(ids, ev.id)
	end
	local key = table.concat(ids, ",")
	if key == viewKey then
		return
	end
	viewKey = key
	LiveEventService.showView(running)
end

-- Merges a list of events (a message, the store, our own start) into this server's.
function LiveEventService.apply(incoming: any)
	local started = LiveEvents.merge(events, incoming, LiveEventService.clock())
	refreshView()
	for _, ev in started do
		for _, fn in startHooks do
			local ok, err = pcall(fn, ev)
			if not ok then
				warn("[LiveEventService] start hook:", err)
			end
		end
	end
end

-- Writes these events into the store (merged with what is there, expired ones dropped).
local function store(list: { LiveEvents.Event })
	local map = memory
	if not map then
		return false
	end
	local now = LiveEventService.clock()
	local longest = 60
	for _, ev in list do
		longest = math.max(longest, ev.endsAt - now)
	end
	return (try("store write", function()
		return map:UpdateAsync(LiveEvents.STORE_KEY, function(old: any)
			local merged: { [string]: LiveEvents.Event } = {}
			LiveEvents.merge(merged, old, now)
			LiveEvents.merge(merged, list, now)
			for _, ev in merged do
				longest = math.max(longest, ev.endsAt - now)
			end
			return LiveEvents.list(merged, now)
		end, math.ceil(longest + 120))
	end))
end

local function publish(data: any): boolean
	local m = messaging
	if not m then
		return false
	end
	return (try("publish", m.PublishAsync, m, LiveEvents.TOPIC, data))
end

-- Reads the store and merges it (on start and every POLL_SECONDS).
function LiveEventService.poll()
	local map = memory
	if map then
		local ok, list = try("store read", map.GetAsync, map, LiveEvents.STORE_KEY)
		if ok then
			LiveEventService.apply(list)
		end
	end
	local now = LiveEventService.clock()
	LiveEvents.prune(events, now)
	for id, at in seenAnnounce do
		if now - at > 600 then
			seenAnnounce[id] = nil
		end
	end
	refreshView()
end

-- One message from the topic (another server, or this one).
function LiveEventService.receive(message: any)
	local data = if type(message) == "table" then message.Data else nil
	if type(data) ~= "table" then
		return
	end
	if data.op == "sync" then
		LiveEventService.apply(data.events)
	elseif data.op == "announce" and type(data.id) == "string" and not seenAnnounce[data.id] then
		local text = LiveEvents.cleanText(data.text) -- (filtered by the server that sent it)
		if text then
			seenAnnounce[data.id] = LiveEventService.clock()
			LiveEventService.showAnnounce(text, if type(data.by) == "string" then string.sub(data.by, 1, 40) else nil)
		end
	end
end

-- Sends events out to every server (the store first, so a server that polls right after the message sees it).
local function spread(list: { LiveEvents.Event })
	task.spawn(function()
		store(list)
		publish({ op = "sync", events = list })
	end)
end

-- Starts an event in every server (it runs here at once). Returns it, or nil and why not.
function LiveEventService.start(req: LiveEvents.Start, by: string?): (LiveEvents.Event?, string?)
	local now = LiveEventService.clock()
	local ev: LiveEvents.Event = {
		id = newId(), kind = req.kind, mult = req.mult, option = req.option, startedAt = now, endsAt = now + req.minutes * 60, by = by,
	}
	LiveEventService.apply({ ev })
	if not events[ev.id] then
		return nil, "it didn't start"
	end
	spread({ ev })
	return ev
end

-- Stops a running event everywhere. Returns whether it was running.
function LiveEventService.stop(id: any): boolean
	local ev = if type(id) == "string" then events[id] else nil
	if not ev or not LiveEvents.isRunning(ev, LiveEventService.clock()) then
		return false
	end
	ev.stopped = true
	refreshView()
	spread({ ev })
	return true
end

-- Filters an admin's text for everyone (Roblox's broadcast filter); nil when it can't.
local function filter(text: string, userId: number): string?
	local svc = textService
	if not svc then
		return nil
	end
	local ok, result = try("filter", function()
		return svc:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat)
	end)
	if not ok then
		return nil
	end
	local okText, shown = try("filter text", function()
		return result:GetNonChatStringForBroadcastAsync()
	end)
	return if okText and type(shown) == "string" then shown else nil
end

-- An admin's message, shown big in every server.
function LiveEventService.announce(text: string, userId: number, by: string?): (boolean, string?)
	local shown = filter(text, userId)
	local okStudio, studio = pcall(function()
		return game:GetService("RunService"):IsStudio()
	end)
	if not shown and okStudio and studio then
		shown = text -- (Studio has no live filter, and nobody else sees it there)
	end
	if not shown then
		return false, "the text filter didn't answer, try again"
	end
	local id = newId()
	seenAnnounce[id] = LiveEventService.clock()
	LiveEventService.showAnnounce(shown, by)
	task.spawn(publish, { op = "announce", id = id, text = shown, by = by })
	return true
end

-- A request from the admin panel. The caller checked the remote's rate; this checks the admin again.
function LiveEventService.request(admin: Player, raw: any)
	if not LiveEventService.isAdmin(admin) then
		return
	end
	if type(raw) ~= "table" then
		return
	end
	if raw.op == "stop" then
		local ev = if type(raw.id) == "string" then events[raw.id] else nil
		if LiveEventService.stop(raw.id) and ev then
			LiveEventService.reply(admin, `Stopped {LiveEvents.describe(ev)} in all servers`, true)
			print(`[LiveEvents] {admin.Name} stopped {LiveEvents.describe(ev)}`)
		else
			LiveEventService.reply(admin, "That event isn't running", false)
		end
		return
	end
	local last = lastAsk[admin.UserId]
	if last and os.clock() - last < LiveEventService.COOLDOWN then
		LiveEventService.reply(admin, "Wait a moment", false)
		return
	end
	if raw.op == "start" then
		local req, why = LiveEvents.checkStart(raw, Halloween.active(os.time()))
		if not req then
			LiveEventService.reply(admin, `Not started: {why}`, false)
			return
		end
		lastAsk[admin.UserId] = os.clock()
		local ev, err = LiveEventService.start(req, admin.Name)
		if ev then
			LiveEventService.reply(admin, `Started {LiveEvents.describe(ev)} for {req.minutes} min in all servers`, true)
			print(`[LiveEvents] {admin.Name} started {LiveEvents.describe(ev)} for {req.minutes} min`)
		else
			LiveEventService.reply(admin, `Not started: {err}`, false)
		end
	elseif raw.op == "announce" then
		local text = LiveEvents.cleanText(raw.text)
		if not text then
			LiveEventService.reply(admin, "Type a message", false)
			return
		end
		lastAsk[admin.UserId] = os.clock()
		local ok, why = LiveEventService.announce(text, admin.UserId, admin.DisplayName)
		LiveEventService.reply(admin, if ok then "Sent to all servers" else `Not sent: {why}`, ok)
		if ok then
			print(`[LiveEvents] {admin.Name} announced: {text}`)
		end
	end
end

-- The multiplier the running `kind` events give right now (1 when none): Luck, Money, Speed, Mutation, Grow.
function LiveEventService.mult(kind: string): number
	return LiveEvents.mult(events, kind, LiveEventService.clock())
end

function LiveEventService.running(kind: string): boolean
	return LiveEvents.has(events, kind, nil, LiveEventService.clock())
end

-- What a stolen seed's mutation becomes (`current`: its pod's; `u`: a uniform draw).
function LiveEventService.stealMutation(current: string?, isNight: boolean, u: number): string?
	return LiveEvents.stealMutation(events, current, isNight, u, LiveEventService.clock())
end

-- Seconds a seed planted now sprouts for (0: at once), `growMult` the owner's Fast Grow.
function LiveEventService.sproutSeconds(zone: number, rarity: number, growMult: number?): number
	return LiveEvents.sproutSeconds(events, zone, rarity, growMult, LiveEventService.clock())
end

function LiveEventService.events(): { [string]: LiveEvents.Event }
	return events
end

-- Clears everything (tests).
function LiveEventService.reset()
	table.clear(events)
	table.clear(seenAnnounce)
	table.clear(lastAsk)
	viewKey = ""
end

-- `opts.services`: { MessagingService, MemoryStoreService, TextService } stand-ins (tests); `opts.loops`: false
-- to skip the clock and poll loops (tests drive LiveEventService.poll).
function LiveEventService.init(opts: { services: { [string]: any }?, loops: boolean? }?)
	local o = opts or {}
	local function service(name: string): any
		if o.services then
			return o.services[name]
		end
		local ok, svc = pcall(game.GetService, game, name)
		return if ok then svc else nil
	end
	messaging = service("MessagingService")
	textService = service("TextService")
	local memoryService = service("MemoryStoreService")
	if memoryService then
		local ok, map = pcall(memoryService.GetHashMap, memoryService, LiveEvents.STORE)
		memory = if ok then map else nil
	end
	if messaging then
		local ok, err = pcall(messaging.SubscribeAsync, messaging, LiveEvents.TOPIC, LiveEventService.receive)
		if not ok then
			warn("[LiveEventService] subscribe failed (events still run in this server):", err)
		end
	end
	LiveEventService.showView({}) -- (the clients' folder exists from the start)
	LiveEventService.poll() -- events still running from before this server started
	if o.loops == false then
		return
	end
	task.spawn(function()
		while true do
			task.wait(LiveEvents.POLL_SECONDS)
			local ok, err = pcall(LiveEventService.poll)
			if not ok then
				warn("[LiveEventService] poll:", err)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			LiveEvents.prune(events, LiveEventService.clock())
			refreshView() -- an event that just ran out goes from the strip
		end
	end)
end

return LiveEventService
