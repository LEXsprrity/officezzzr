--!strict
-- The owner's live "admin abuse" events (owner 2026-10-19: "ADMIN PANEL WITH ADMIN ABUSE ... LIVE EVENTS WITH
-- LIVE NOTIS ACROSS SERVERS"): what an event is, how a request from the admin panel is checked, how two lists
-- of events merge (from the cross-server messages and from the MemoryStore), and what the running events do to a roll,
-- income, Speed and a sprout. Pure and shared: the panel (AdminPanel.client), the strip (LiveEvents.client) and
-- the server (LiveEventService) read events the same way.
--   { id, kind, mult?, option?, startedAt, endsAt, stopped?, by? }   (endsAt: absolute, server time in seconds)
-- Kinds: Luck, Money, Speed (mult), Mutation (mult, or option = a mutation every stolen seed gets), Grow (mult,
-- or option = "Instant"), Candy (Halloween only). A stopped event stays in the lists as a tombstone
-- (stopped = true) until its endsAt, so a server that merges an older list never brings it back.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local LiveEvents = {}

export type Event = {
	id: string,
	kind: string,
	mult: number?,
	option: string?,
	startedAt: number,
	endsAt: number,
	stopped: boolean?,
	by: string?,
}

LiveEvents.TOPIC = "LiveEvents" -- the cross-server messages' topic
LiveEvents.STORE = "LiveEvents_v1" -- MemoryStore HashMap
LiveEvents.STORE_KEY = "active"
LiveEvents.FOLDER = "LiveEvents" -- ReplicatedStorage.LiveEvents: a Configuration per running event (the clients read it)
LiveEvents.POLL_SECONDS = 30
LiveEvents.MIN_MINUTES, LiveEvents.MAX_MINUTES = 1, 30
LiveEvents.MIN_MULT = 2
LiveEvents.MAX_MULT = 5 -- every multiplier (owner's economy safety: at most 5x luck and money)
LiveEvents.MAX_TEXT = 120 -- an announcement's characters
LiveEvents.MAX_EVENTS = 40 -- events kept in a list (running and tombstones)
LiveEvents.CANDY_BURST = 40 -- candy a Candy rain drops at once
LiveEvents.CANDY_CAP_BONUS = 60 -- more candy may lie on the map during it
LiveEvents.CANDY_EVERY = 3 -- seconds between new candy during it
LiveEvents.FORCED = { "Gold", "Diamond", "Rainbow", "Celestial" } -- a Mutation storm's "every stolen seed is ..."
LiveEvents.STORM_MAX_CHANCE = 0.9 -- a storm's mutation chances together never go past this

LiveEvents.KINDS = { "Luck", "Money", "Speed", "Mutation", "Grow", "Candy" }

-- The admin panel's choices per kind, in order (the server re-checks whatever arrives).
export type Choice = { label: string, mult: number?, option: string? }
LiveEvents.CHOICES = {
	Luck = { { label = "2x", mult = 2 }, { label = "3x", mult = 3 }, { label = "5x", mult = 5 } },
	Money = { { label = "2x", mult = 2 }, { label = "3x", mult = 3 }, { label = "5x", mult = 5 } },
	Speed = { { label = "2x", mult = 2 }, { label = "3x", mult = 3 }, { label = "5x", mult = 5 } },
	Mutation = {
		{ label = "2x", mult = 2 }, { label = "3x", mult = 3 }, { label = "5x", mult = 5 },
		{ label = "All Gold", option = "Gold" }, { label = "All Diamond", option = "Diamond" },
		{ label = "All Rainbow", option = "Rainbow" }, { label = "All Celestial", option = "Celestial" },
	},
	Grow = { { label = "2x", mult = 2 }, { label = "3x", mult = 3 }, { label = "5x", mult = 5 }, { label = "Instant", option = "Instant" } },
	Candy = { { label = "Rain" } },
} :: { [string]: { Choice } }

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function clampMult(v: any): number
	local n = if finite(v) then math.floor(v + 0.5) else LiveEvents.MIN_MULT
	return math.clamp(n, LiveEvents.MIN_MULT, LiveEvents.MAX_MULT)
end

export type Start = { kind: string, mult: number?, option: string?, minutes: number }

-- A clean start request from the admin panel (anything from the client), or nil and why not. Multipliers and
-- minutes are clamped; `halloween`: whether the Halloween event runs (Candy needs it).
function LiveEvents.checkStart(raw: any, halloween: boolean): (Start?, string?)
	if type(raw) ~= "table" or type(raw.kind) ~= "string" or not table.find(LiveEvents.KINDS, raw.kind) then
		return nil, "pick an event"
	end
	if not finite(raw.minutes) then
		return nil, `minutes: {LiveEvents.MIN_MINUTES} to {LiveEvents.MAX_MINUTES}`
	end
	local minutes = math.clamp(math.floor(raw.minutes), LiveEvents.MIN_MINUTES, LiveEvents.MAX_MINUTES)
	local kind = raw.kind
	if kind == "Candy" then
		if not halloween then
			return nil, "Candy rain only works while Halloween runs"
		end
		return { kind = kind, minutes = minutes }
	end
	if kind == "Mutation" and type(raw.option) == "string" then
		if not table.find(LiveEvents.FORCED, raw.option) then
			return nil, "pick a mutation"
		end
		return { kind = kind, option = raw.option, minutes = minutes }
	end
	if kind == "Grow" and raw.option == "Instant" then
		return { kind = kind, option = "Instant", minutes = minutes }
	end
	return { kind = kind, mult = clampMult(raw.mult), minutes = minutes }
end

-- An announcement's text, trimmed, one line, at most MAX_TEXT characters; nil when empty.
function LiveEvents.cleanText(raw: any): string?
	if type(raw) ~= "string" then
		return nil
	end
	local s = string.gsub(raw, "[%c]", " ")
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	if s == "" then
		return nil
	end
	if utf8.len(s) == nil then
		return nil -- not valid UTF-8
	end
	if (utf8.len(s) :: number) > LiveEvents.MAX_TEXT then
		s = string.sub(s, 1, utf8.offset(s, LiveEvents.MAX_TEXT + 1) :: number - 1)
	end
	return s
end

-- A clean copy of an event from anywhere (a message, the store), or nil.
function LiveEvents.checkEvent(raw: any): Event?
	if type(raw) ~= "table" or type(raw.id) ~= "string" or #raw.id < 1 or #raw.id > 64 then
		return nil
	end
	if type(raw.kind) ~= "string" or not table.find(LiveEvents.KINDS, raw.kind) then
		return nil
	end
	if not finite(raw.startedAt) or not finite(raw.endsAt) or raw.endsAt < raw.startedAt then
		return nil
	end
	if raw.endsAt - raw.startedAt > LiveEvents.MAX_MINUTES * 60 + 1 then
		return nil
	end
	local option: string? = nil
	if raw.kind == "Mutation" and type(raw.option) == "string" and table.find(LiveEvents.FORCED, raw.option) then
		option = raw.option
	elseif raw.kind == "Grow" and raw.option == "Instant" then
		option = "Instant"
	end
	local mult: number? = nil
	if raw.kind ~= "Candy" and option == nil then
		mult = clampMult(raw.mult)
	end
	return {
		id = raw.id, kind = raw.kind, mult = mult, option = option, startedAt = raw.startedAt, endsAt = raw.endsAt,
		stopped = if raw.stopped == true then true else nil, by = if type(raw.by) == "string" then string.sub(raw.by, 1, 40) else nil,
	}
end

function LiveEvents.isRunning(ev: Event, now: number): boolean
	return not ev.stopped and ev.endsAt > now
end

-- The running events (not stopped, not over), the soonest to end first.
function LiveEvents.running(events: { [any]: Event }, now: number): { Event }
	local out = {}
	for _, ev in events do
		if LiveEvents.isRunning(ev, now) then
			table.insert(out, ev)
		end
	end
	table.sort(out, function(a, b)
		if a.endsAt ~= b.endsAt then
			return a.endsAt < b.endsAt
		end
		return a.id < b.id
	end)
	return out
end

-- Merges `incoming` (a list from a message or the store) into `into` (id -> event). New events are added
-- (tombstones too), and a stop wins over a running copy. Returns the events that started running here and
-- whether anything changed.
function LiveEvents.merge(into: { [string]: Event }, incoming: any, now: number): ({ Event }, boolean)
	local started = {}
	local changed = false
	if type(incoming) ~= "table" then
		return started, false
	end
	for _, raw in incoming do
		local ev = LiveEvents.checkEvent(raw)
		if ev and ev.endsAt > now then
			local have = into[ev.id]
			if not have then
				into[ev.id] = ev
				changed = true
				if LiveEvents.isRunning(ev, now) then
					table.insert(started, ev)
				end
			elseif ev.stopped and not have.stopped then
				have.stopped = true
				changed = true
			end
		end
	end
	return started, changed
end

-- Drops events that are over (tombstones too). Returns whether any went.
function LiveEvents.prune(events: { [string]: Event }, now: number): boolean
	local gone = false
	for id, ev in events do
		if ev.endsAt <= now then
			events[id] = nil
			gone = true
		end
	end
	return gone
end

-- `events` as a list for the store or a message: unexpired ones, newest last, at most MAX_EVENTS.
function LiveEvents.list(events: { [string]: Event }, now: number): { Event }
	local out = {}
	for _, ev in events do
		if ev.endsAt > now then
			table.insert(out, ev)
		end
	end
	table.sort(out, function(a, b)
		return a.startedAt < b.startedAt
	end)
	while #out > LiveEvents.MAX_EVENTS do
		table.remove(out, 1)
	end
	return out
end

-- The multiplier the running `kind` events give (the biggest one: two 3x Luck events are 3x, not 9x); 1 if none.
function LiveEvents.mult(events: { [any]: Event }, kind: string, now: number): number
	local best = 1
	for _, ev in events do
		if ev.kind == kind and ev.mult and LiveEvents.isRunning(ev, now) then
			best = math.max(best, math.min(ev.mult, LiveEvents.MAX_MULT))
		end
	end
	return best
end

-- Whether a `kind` event with this option (any option when nil) runs.
function LiveEvents.has(events: { [any]: Event }, kind: string, option: string?, now: number): boolean
	for _, ev in events do
		if ev.kind == kind and LiveEvents.isRunning(ev, now) and (option == nil or ev.option == option) then
			return true
		end
	end
	return false
end

-- The mutation a running "every stolen seed is ..." storm forces (the latest started), or nil.
function LiveEvents.forcedMutation(events: { [any]: Event }, now: number): string?
	local best: Event? = nil
	for _, ev in events do
		if ev.kind == "Mutation" and ev.option and LiveEvents.isRunning(ev, now) and (not best or ev.startedAt > best.startedAt) then
			best = ev
		end
	end
	return if best then best.option else nil
end

-- The mutation a stolen seed ends up with. `current`: what its pod rolled; `u`: a uniform [0, 1) draw. A
-- forced storm gives its mutation. An xN storm keeps any mutation the pod had, and a plain seed gets one with
-- the extra chance that makes each mutation's overall chance N x its pod chance (night-only ones only at
-- night; Haunted, chance 0, never), scaled down so they never add up past STORM_MAX_CHANCE.
function LiveEvents.stealMutation(events: { [any]: Event }, current: string?, isNight: boolean, u: number, now: number): string?
	local forced = LiveEvents.forcedMutation(events, now)
	if forced then
		return forced
	end
	local n = LiveEvents.mult(events, "Mutation", now)
	if n <= 1 or current ~= nil then
		return current
	end
	local base = 0
	for _, m in Config.MUTATIONS do
		if not m.nightOnly or isNight then
			base += m.chance
		end
	end
	if base <= 0 or base >= 1 then
		return current
	end
	local scale = math.min(n, LiveEvents.STORM_MAX_CHANCE / base)
	-- P(m | the pod had none) = (scale - 1) * chance(m) / (1 - base)
	local pick = u
	for _, m in Config.MUTATIONS do
		if not m.nightOnly or isNight then
			local extra = (scale - 1) * m.chance / (1 - base)
			if pick < extra then
				return m.id
			end
			pick -= extra
		end
	end
	return nil
end

-- Seconds a seed planted now sprouts for: Config.sproutTime at the owner's Fast Grow x a running Grow event,
-- 0 during an Instant grow (it is a flower at once).
function LiveEvents.sproutSeconds(events: { [any]: Event }, zone: number, rarity: number, growMult: number?, now: number): number
	if LiveEvents.has(events, "Grow", "Instant", now) then
		return 0
	end
	return Config.sproutTime(zone, rarity, (growMult or 1) * LiveEvents.mult(events, "Grow", now))
end

-- "3x LUCK", "ALL GOLD SEEDS", "INSTANT GROW", "CANDY RAIN"
function LiveEvents.describe(ev: { kind: string, mult: number?, option: string? }): string
	local n = `{ev.mult or 1}x`
	if ev.kind == "Luck" then
		return `{n} LUCK`
	elseif ev.kind == "Money" then
		return `{n} MONEY`
	elseif ev.kind == "Speed" then
		return `{n} SPEED`
	elseif ev.kind == "Mutation" then
		return if ev.option then `ALL {string.upper(ev.option)} SEEDS` else `{n} MUTATIONS`
	elseif ev.kind == "Grow" then
		return if ev.option == "Instant" then "INSTANT GROW" else `{n} FAST GROW`
	elseif ev.kind == "Candy" then
		return "CANDY RAIN"
	end
	return string.upper(ev.kind)
end

-- What it does, in a few words for the banner's second line.
function LiveEvents.about(ev: { kind: string, mult: number?, option: string? }): string
	if ev.kind == "Luck" then
		return "Stolen seeds roll rarer!"
	elseif ev.kind == "Money" then
		return "Your plants earn more!"
	elseif ev.kind == "Speed" then
		return "Walk and run the treadmill for more Speed!"
	elseif ev.kind == "Mutation" then
		return if ev.option then `Every stolen seed is {ev.option}!` else "Stolen seeds mutate more!"
	elseif ev.kind == "Grow" then
		return if ev.option == "Instant" then "Seeds you plant grow at once!" else "Seeds you plant sprout faster!"
	elseif ev.kind == "Candy" then
		return "Candy everywhere in the corridor!"
	end
	return ""
end

local function minutesText(seconds: number): string
	local m = math.max(1, math.floor(seconds / 60 + 0.5))
	return `{m} minute{if m == 1 then "" else "s"}`
end

-- "ADMIN ABUSE! 3x LUCK for 10 minutes!"
function LiveEvents.banner(ev: Event): string
	return `ADMIN ABUSE! {LiveEvents.describe(ev)} for {minutesText(ev.endsAt - ev.startedAt)}!`
end

-- "9:41" (or "1:02:03" past an hour)
function LiveEvents.clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h, m, r = s // 3600, (s // 60) % 60, s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, r)
	end
	return string.format("%d:%02d", m, r)
end

return LiveEvents
