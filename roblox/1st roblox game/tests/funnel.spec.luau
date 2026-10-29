-- The onboarding funnel (Server/Funnel): new players' first steps go to Roblox's Funnels, in order, once each;
-- veterans aren't followed; the hooks sit where each step happens.
local fs = require("@lune/fs")
local H = require("./harness")

local Config = H.shared("Config")
local Funnel = H.server("Funnel")

local sent = {}
Funnel.send = function(_, step, name)
	table.insert(sent, `{step}:{name}`)
end

H.test("funnel: seven steps in order, each sent once, only for new players", function()
	H.ok(H.deepEq(Funnel.STEPS, { "Joined", "Stole a seed", "Brought it home", "Planted", "Finished tutorial", "First sale", "Zone 2 Speed" }))
	local newbie, veteran = {} :: any, {} :: any
	table.clear(sent)
	Funnel.start(veteran, false)
	Funnel.mark(veteran, "Planted")
	H.ok(#sent == 0 and not Funnel.following(veteran), "a veteran isn't followed")
	Funnel.start(newbie, true)
	Funnel.mark(newbie, "Stole a seed")
	Funnel.mark(newbie, "Stole a seed")
	Funnel.mark(newbie, "Nope")
	H.ok(H.deepEq(sent, { "1:Joined", "2:Stole a seed" }), table.concat(sent, ", "))
	Funnel.stop(newbie)
	Funnel.mark(newbie, "First sale")
	H.ok(#sent == 2, "nothing after they leave")
end)

H.test("funnel: every step is hooked where it happens", function()
	local function src(f: string): string
		return (string.gsub(fs.readFile(f), "\r\n", "\n"))
	end
	local seeds, plots = src("src/server/SeedService.luau"), src("src/server/PlotService.luau")
	local main, tut = src("src/server/Main.server.luau"), src("src/server/TutorialService.luau")
	H.ok(string.find(seeds, "s.carry = carry\n\tSessions.pushCarry(s)\n\tFunnel.mark(player, \"Stole a seed\")", 1, true) ~= nil, "steal")
	H.ok(string.find(seeds, "\"Stored\"", 1, true) and string.find(seeds, "Funnel.mark(player, \"Brought it home\")", 1, true), "home")
	H.ok(string.find(plots, "Funnel.mark(player, \"Planted\")", 1, true) and string.find(plots, "Funnel.mark(player, \"First sale\")", 1, true), "plant, sell")
	H.ok(string.find(tut, "Funnel.mark(s.player, \"Finished tutorial\")", 1, true) ~= nil, "tutorial")
	H.ok(string.find(main, "Funnel.start(player, not profile.tutorialDone)", 1, true) and string.find(main, "Funnel.stop(player)", 1, true)
		and string.find(main, "Funnel.init()", 1, true), "join, leave, the Speed check")
	H.ok(Config.ZONES[2].req > 0, "the second zone's Speed")
end)
