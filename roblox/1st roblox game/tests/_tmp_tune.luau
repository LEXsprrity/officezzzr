local Sim = require("./progression_sim")
local H = require("./harness")
local Config = H.shared("Config")
local function try(label, mults, prices)
	for i, m in mults do
		Config.TREADMILL_TIERS[i] = { mult = m, price = prices[i] }
	end
	local parts = {}
	local r = Sim.run()
	local a = Sim.run({ afk = true, limitHours = 80 })
	for k = 2, #Config.ZONES do
		table.insert(parts, `{Config.ZONES[k].id} {Sim.clock(r.arrivals[k])}/{Sim.clock(a.arrivals[k])}`)
	end
	local worst = math.huge
	for _, seed in { 1, 2, 3, 99, 1234 } do
		local s = Sim.run({ seed = seed })
		for k, zone in Config.ZONES do
			local target = Sim.TARGETS[zone.id]
			if target then worst = math.min(worst, s.arrivals[k] / target) end
		end
	end
	local x5 = Sim.run({ treadmillTier = 10 })
	print(label, table.concat(parts, ", "), "tier", r.treadmillTier, a.treadmillTier, "minratio", string.format("%.2f", worst), "x5spirit", Sim.clock(x5.arrivals[7]))
end
-- try("A", { 2, 2.25, 2.5, 2.75, 3, 3.5, 4, 4.5, 5, 6 }, { 0, 250e3, 2.5e6, 25e6, 250e6, 2.5e9, 25e9, 250e9, 2.5e12, 25e12 })
-- try("B", { 2, 2.25, 2.5, 2.75, 3, 3.5, 4, 4.5, 5, 6 }, { 0, 1e6, 10e6, 100e6, 1e9, 10e9, 100e9, 1e12, 10e12, 100e12 })
-- try("C", { 2, 2.25, 2.5, 2.75, 3, 3.5, 4, 5, 6, 8 }, { 0, 1e6, 10e6, 100e6, 1e9, 10e9, 100e9, 1e12, 10e12, 100e12 })
-- try("D", { 2, 2.2, 2.4, 2.6, 2.8, 3, 3.5, 4, 5, 6 }, { 0, 100e3, 1e6, 10e6, 100e6, 1e9, 10e9, 100e9, 1e12, 10e12 })
-- try("E", { 2, 2.25, 2.5, 2.75, 3, 3.5, 4, 5, 6, 8 }, { 0, 500e3, 5e6, 50e6, 500e6, 5e9, 50e9, 500e9, 5e12, 50e12 })
for _, gps in { 0.28, 0.26 } do
	for _, ge in { 0.555, 0.545 } do
		Config.GAIN_PER_STUD, Config.GAIN_EXPONENT = gps, ge
		try(`B gps={gps} ge={ge}`, { 2, 2.25, 2.5, 2.75, 3, 3.5, 4, 4.5, 5, 6 }, { 0, 1e6, 10e6, 100e6, 1e9, 10e9, 100e9, 1e12, 10e12, 100e12 })
		try(`D gps={gps} ge={ge}`, { 2, 2.25, 2.5, 2.75, 3, 3.5, 4, 5, 6, 8 }, { 0, 1e6, 10e6, 100e6, 1e9, 10e9, 100e9, 1e12, 10e12, 100e12 })
	end
end
