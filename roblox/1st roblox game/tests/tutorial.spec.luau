-- The first-time tutorial (Shared/Tutorial, Server/TutorialService, Client/Tutorial): the steps and how each
-- advances, where a returning player picks up, the veteran check on old saves, skip, the save round-trip and
-- the red arrow trail's path math. The arrows and labels themselves are client visuals (not run here).
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local H = require("./harness")

local Vector3 = H.Vector3
local Config = H.shared("Config")
local Tutorial = H.shared("Tutorial")
local ProfileStore = H.server("ProfileStore")
local Net = H.stubServer("Net", { StatsUpdate = { FireClient = function() end }, LootEvent = { FireClient = function() end }, toast = function() end })
local Sessions = H.server("Sessions")
local TutorialService = H.server("TutorialService")

local function ids(): { string }
	local out = {}
	for _, s in Tutorial.STEPS do
		table.insert(out, s.id)
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- Steps
----------------------------------------------------------------------------------------------------
H.test("tutorial: the steps in order, each with an instruction and words over its target, no emoji", function()
	H.ok(H.deepEq(ids(), { "run", "steal", "home", "plant", "grow", "earn", "speed", "ready" }))
	for _, s in Tutorial.STEPS do
		H.ok(#s.banner > 10, `{s.id}: an instruction`)
		H.ok(#s.label > 3 and string.upper(s.label) == s.label, `{s.id}: big words over the target`)
		for _, text in { s.banner, s.label } do
			H.ok(not string.find(text, "[\240-\244]"), `{s.id}: no emoji in "{text}"`)
		end
	end
	H.eq(Tutorial.step("run").label, "STEAL A SEED", "the owner's words over the seed")
	H.eq(Tutorial.step("steal").label, "STEAL A SEED")
	H.eq(Tutorial.step("home").label, "RUN HOME!")
	H.eq(Tutorial.step("plant").label, "PLANT IT HERE")
	H.eq(Tutorial.step("grow").label, "WAITING FOR IT TO GROW")
	H.ok(string.find(Tutorial.step("ready").banner, Config.ZONES[2].name, 1, true) ~= nil, "the last step names the next zone")
	H.ok(string.find(Tutorial.step("ready").banner, "25K", 1, true) ~= nil, "...and the Speed its sign asks for")
end)

H.test("tutorial: a new player walks through every step by doing the thing, then it's done", function()
	local id = "run"
	local path = { id }
	for _, event in { "near", "pickup", "stored", "planted", "sprouted", "earned", "faster", "near" } do
		id = Tutorial.advance(id, event)
		table.insert(path, id)
	end
	H.ok(H.deepEq(path, { "run", "steal", "home", "plant", "grow", "earn", "speed", "ready", "done" }))
	H.eq(Tutorial.advance("ready", "finish"), "done", "or the Let's go! button")
end)

H.test("tutorial: events out of turn don't advance it, a lost seed goes back to stealing, done stays done", function()
	H.eq(Tutorial.advance("run", "sprouted"), "run")
	H.eq(Tutorial.advance("plant", "pickup"), "plant", "never backwards")
	H.eq(Tutorial.advance("grow", "stored"), "grow")
	H.eq(Tutorial.advance("earn", "faster"), "earn")
	H.eq(Tutorial.advance("steal", "near"), "steal")
	H.eq(Tutorial.advance("speed", "finish"), "speed", "Let's go! is only the last step's")
	H.eq(Tutorial.advance("home", "lost"), "steal", "caught or dropped on the way home: steal again")
	H.eq(Tutorial.advance("plant", "lost"), "plant")
	H.eq(Tutorial.advance("run", "pickup"), "home", "stole before reaching the trail's end: on to running home")
	H.eq(Tutorial.advance("run", "stored"), "plant")
	H.eq(Tutorial.advance("home", "planted"), "grow", "planted a seed already in the bag")
	H.eq(Tutorial.advance("done", "near"), "done")
	H.eq(Tutorial.advance("nope", "near"), "nope")
end)

H.test("tutorial: skip ends it from any step", function()
	for _, id in ids() do
		H.eq(Tutorial.advance(id, "skip"), "done", id)
	end
end)

H.test("tutorial: earning and getting faster need the real thing", function()
	H.ok(not Tutorial.earned(100, 100, 30), "money hasn't moved")
	H.ok(not Tutorial.earned(100, 150, Tutorial.EARN_MIN - 1), "shown long enough to read first")
	H.ok(Tutorial.earned(100, 101, Tutorial.EARN_MIN))
	H.ok(not Tutorial.faster(1000, 1000 + Tutorial.SPEED_GOAL - 1))
	H.ok(Tutorial.faster(1000, 1000 + Tutorial.SPEED_GOAL))
	H.ok(Tutorial.SPEED_GOAL <= Config.treadmillPerStep(1, Config.DEFAULT_TRAIL) * 4, "a second on the free treadmill does it")
end)

H.test("tutorial: a returning player picks up where their stats say", function()
	H.eq(Tutorial.startStep({}), "run", "a new player")
	H.eq(Tutorial.startStep({ carrying = false, plants = {}, seedBag = {} }), "run")
	H.eq(Tutorial.startStep({ carrying = { zone = 1, rarity = 1 } }), "home")
	H.eq(Tutorial.startStep({ seedBag = { ["1:1#5"] = 1 } }), "plant")
	H.eq(Tutorial.startStep({ seedBag = { ["1:1#5"] = 0 } }), "run")
	H.eq(Tutorial.startStep({ plants = { { slot = 1, sproutUntil = 1e9 } }, seedBag = { ["1:1"] = 1 } }), "grow")
	H.eq(Tutorial.startStep({ plants = { { slot = 1 } } }), "earn")
end)

----------------------------------------------------------------------------------------------------
-- The save
----------------------------------------------------------------------------------------------------
H.test("tutorial save: new profiles start it; old saves are done only for players who clearly played", function()
	H.eq(ProfileStore.defaultProfile().tutorialDone, false)
	H.eq(ProfileStore.deserialize(nil).tutorialDone, false, "no save at all: a new player")
	-- old saves (no tutorialDone field)
	H.eq(ProfileStore.deserialize({ v = 12 }).tutorialDone, false, "an empty old save: never really played")
	H.eq(ProfileStore.deserialize({ v = 12, money = 0, speed = 120 }).tutorialDone, false, "walked a few studs")
	H.eq(ProfileStore.deserialize({ v = 12, money = 5 }).tutorialDone, true, "money")
	H.eq(ProfileStore.deserialize({ v = 12, speed = 50e3 }).tutorialDone, true, "Speed")
	H.eq(ProfileStore.deserialize({ v = 12, plants = { { s = 1, z = 1, r = 1, t = 1790000000 } } }).tutorialDone, true, "a plant")
	H.eq(ProfileStore.deserialize({ v = 12, bag = { ["1:1"] = 1 } }).tutorialDone, true, "a seed in the bag")
	H.eq(ProfileStore.deserialize({ v = 12, inv = { { i = 1, z = 1, r = 1, va = 1 } } }).tutorialDone, true, "an inventory plant")
	H.eq(ProfileStore.deserialize({ v = 12, index = { "1:1" } }).tutorialDone, true, "an Index entry")
	H.eq(ProfileStore.deserialize({ v = 3, slots = 6, money = 1e6 }).tutorialDone, true, "a v1-v11 veteran too")
	-- saves that have it keep it, whatever else they hold
	H.eq(ProfileStore.deserialize({ v = 12, money = 1e9, tutorialDone = false }).tutorialDone, false)
	H.eq(ProfileStore.deserialize({ v = 12, tutorialDone = true }).tutorialDone, true)
	H.eq(ProfileStore.deserialize({ v = 12, money = 1e9, tutorialDone = "yes" }).tutorialDone, true, "junk: by the veteran check")
end)

H.test("tutorial save: tutorialDone round-trips through JSON and the DataStore", function()
	for _, done in { false, true } do
		local p = ProfileStore.defaultProfile()
		p.tutorialDone = done
		local data = serde.decode("json", serde.encode("json", ProfileStore.serialize(p)))
		H.eq(data.tutorialDone, done)
		H.eq(ProfileStore.deserialize(data).tutorialDone, done)
	end
	local store = { data = {} :: { [string]: string } }
	function store.UpdateAsync(self, key: string, transform: (any) -> any)
		local old = if self.data[key] then serde.decode("json", self.data[key]) else nil
		local new = transform(old)
		if new ~= nil then
			self.data[key] = serde.encode("json", new)
		end
		return new
	end
	local ps = ProfileStore.new(store, 1, 0, "job")
	local profile, ok = ps:load(7)
	H.ok(ok)
	H.eq(profile.tutorialDone, false, "a brand new player")
	profile.tutorialDone = true
	H.ok((ps:save(7, profile, true)))
	local again = ps:load(7)
	H.eq(again.tutorialDone, true, "finished once, never again")
end)

H.test("tutorial service: done or skip sets the flag once and tells the client; junk is ignored", function()
	local pushed = {}
	local saved = Net.StatsUpdate.FireClient
	Net.StatsUpdate.FireClient = function(_, _, partial)
		table.insert(pushed, partial)
	end
	local ok, err = pcall(function()
		for _, kind in { "done", "skip" } do
			local s = Sessions.create({ Name = "Kid", UserId = 99 } :: any, ProfileStore.defaultProfile(), true)
			H.ok(not TutorialService.finish(s, "nope"), "junk")
			H.ok(not TutorialService.finish(s, 5))
			H.eq(s.profile.tutorialDone, false)
			H.ok(TutorialService.finish(s, kind), kind)
			H.eq(s.profile.tutorialDone, true)
			H.eq(pushed[#pushed].tutorialDone, true, "the client stops")
			H.ok(not TutorialService.finish(s, kind), "only once")
			Sessions.remove(s.player)
		end
	end)
	Net.StatsUpdate.FireClient = saved
	if not ok then
		error(err, 0)
	end
end)

H.test("tutorial: the full StatsUpdate carries the flag (the client starts or stays away by it)", function()
	local sessions = fs.readFile("src/server/Sessions.luau")
	H.ok(string.find(sessions, "tutorialDone = p.tutorialDone", 1, true) ~= nil)
	local main = fs.readFile("src/server/Main.server.luau")
	H.ok(string.find(main, "TutorialService\")).init()", 1, true) ~= nil, "the remote is listened to")
end)

----------------------------------------------------------------------------------------------------
-- The red arrow trail
----------------------------------------------------------------------------------------------------
local plot = { center = Vector3.new(-6, 0, 84), entrance = Vector3.new(-6, 0, 84 - 46), half = 42 }
local pod = Config.nestCenter(1) + Config.podOffset(1, 1)

H.test("trail route: out of the plot by its entrance, through the corridor mouth, to the pod (and back)", function()
	local spawn = Vector3.new(-6, 3, 100)
	local out = Tutorial.route(spawn, pod, plot)
	H.eq(#out, 4)
	H.eq(out[1], Vector3.new(-6, 0, 100), "from the player, on the ground")
	H.eq(out[2], plot.entrance, "out by the plot's entrance, not through its fence")
	H.eq(out[3], Tutorial.MOUTH, "into the corridor at its mouth")
	H.eq(out[4], Vector3.new(pod.X, 0, pod.Z))
	local back = Tutorial.route(pod, plot.center, plot)
	H.ok(H.deepEq({ back[2], back[3] }, { Tutorial.MOUTH, plot.entrance }), "home: the mouth, then in by the entrance")
	H.eq(#Tutorial.route(Vector3.new(-6, 0, 30), plot.center, plot), 3, "from the walkway: in by the entrance only")
	H.eq(#Tutorial.route(Vector3.new(150, 0, 0), pod, plot), 2, "inside the corridor: straight there")
	H.eq(#Tutorial.route(plot.center, plot.center + Vector3.new(5, 0, 5), plot), 2, "inside the plot: straight there")
	H.eq(#Tutorial.route(pod, pod, plot), 1, "already there")
	H.eq(#Tutorial.route(spawn, pod, nil), 3, "no plot known yet: still through the mouth")
end)

H.test("trail arrows: evenly spaced along the route, pointing toward the target, faded in and out at the ends", function()
	local route = Tutorial.route(Vector3.new(-6, 0, 100), pod, plot)
	local total = Tutorial.length(route)
	local arrows = Tutorial.arrows(route, 0)
	H.ok(#arrows > 10, `{#arrows} arrows`)
	H.ok(#arrows <= Tutorial.MAX_ARROWS)
	local along = 0
	for i, a in arrows do
		H.ok(a.alpha >= 0 and a.alpha <= 1, "alpha in 0..1")
		H.near(a.direction.Magnitude, 1, 1e-4, "a unit direction")
		H.eq(a.position.Y, 0, "on the ground")
		if i > 1 then
			-- spacing measured along the route (a corner shortens the straight line, never lengthens it)
			H.ok((a.position - arrows[i - 1].position).Magnitude <= Tutorial.SPACING + 1e-3)
		end
		along = i
	end
	H.ok(arrows[1].alpha < 0.5, "the first arrow by the player fades in (at its feet: invisible)")
	H.ok(arrows[#arrows].alpha < 1, "the last fades out before the target")
	H.ok(arrows[math.floor(#arrows / 2)].alpha == 1, "full in the middle")
	H.ok((arrows[#arrows].position - Vector3.new(pod.X, 0, pod.Z)).Magnitude >= Tutorial.STOP_SHORT - 1e-3, "stops short of the target")
	H.ok(along * Tutorial.SPACING <= total + Tutorial.SPACING, "no arrow past the end")
	-- the first leg heads from the player to the plot entrance
	H.near(arrows[3].direction.Z, -1, 1e-6, "toward the entrance")
end)

H.test("trail arrows: they flow smoothly toward the target, and loop without a jump", function()
	local route = { Vector3.new(0, 0, 0), Vector3.new(100, 0, 0) }
	local a0 = Tutorial.arrows(route, 0)
	local dt = 1 / 60
	local a1 = Tutorial.arrows(route, dt)
	-- the arrow in the middle moved forward by FLOW x dt
	local m = math.floor(#a0 / 2)
	H.near(a1[m].position.X - a0[m].position.X, Tutorial.FLOW * dt, 1e-3, "moves toward the target")
	-- one SPACING later every arrow has moved to where the next one was: the trail looks the same (seamless loop)
	local period = Tutorial.SPACING / Tutorial.FLOW
	local later = Tutorial.arrows(route, period - 1e-9)
	H.near(later[m].position.X, a0[m + 1].position.X, 1e-4)
	-- a slow-moving phase changes each alpha only a little per frame (no popping)
	for t = 0, 2, dt do
		local before, after = Tutorial.arrows(route, t), Tutorial.arrows(route, t + dt)
		local maxStep = 0
		for _, a in after do
			-- the alpha an arrow at this position had a frame ago (the nearest one behind it)
			for _, b in before do
				if math.abs(b.position.X - (a.position.X - Tutorial.FLOW * dt)) < 1e-3 then
					maxStep = math.max(maxStep, math.abs(a.alpha - b.alpha))
				end
			end
		end
		H.ok(maxStep < 0.05, `t={t}: alpha jumps by {maxStep} in a frame`)
	end
end)

H.test("trail arrows: a long route shows at most MAX_ARROWS, fading out at its far end", function()
	local route = { Vector3.new(0, 0, 0), Vector3.new(2000, 0, 0) }
	local arrows = Tutorial.arrows(route, 0.3)
	H.ok(#arrows <= Tutorial.MAX_ARROWS)
	H.ok(arrows[#arrows].alpha < 1, "fades out instead of stopping dead")
	H.eq(#Tutorial.arrows({ Vector3.new(0, 0, 0), Vector3.new(2, 0, 0) }, 0), 0, "standing on the target: no arrows")
	H.eq(#Tutorial.arrows({ Vector3.new(0, 0, 0) }, 0), 0)
end)

H.test("trail start: eases after the player, frame-rate independent", function()
	local from, to = Vector3.new(0, 0, 0), Vector3.new(10, 0, 0)
	local one = Tutorial.follow(from, to, 1 / 30)
	local two = Tutorial.follow(Tutorial.follow(from, to, 1 / 60), to, 1 / 60)
	H.near(one.X, two.X, 1e-6, "two half frames = one frame")
	H.ok(one.X > 0 and one.X < 10, "part of the way, never a jump")
	H.near(Tutorial.follow(from, to, 5).X, 10, 1e-3, "catches up")
end)

H.test("tutorial client: a skip button, words not emoji, the arrows glow red, the banner keeps showing while carrying", function()
	local client = fs.readFile("src/client/Tutorial.client.luau")
	H.ok(string.find(client, "\"Skip\", \"Skip\"", 1, true) ~= nil, "a Skip button")
	H.ok(string.find(client, "TutorialRemote:FireServer(kind)", 1, true) ~= nil, "skip and done are saved")
	H.ok(string.find(client, "Enum.Material.Neon", 1, true) ~= nil, "glowing arrows (day and night)")
	H.ok(string.find(client, "UiFx.relief", 1, true) ~= nil, "relief words")
	H.ok(not string.find(client, "[\240-\244]"), "no emoji")
	H.ok(not string.find(client, "Toast", 1, true), "no info toasts: one banner per step")
	local carry = fs.readFile("src/client/CarryHud.client.luau")
	H.ok(string.find(carry, "Tutorial = true", 1, true) ~= nil, "the RUN!! screen keeps the tutorial's banner")
end)
