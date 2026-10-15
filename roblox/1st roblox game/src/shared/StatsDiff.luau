--!strict
-- What a StatsUpdate really changed (client; HUD.client). The server re-sends values that haven't changed
-- (the Plants panel push every few seconds carries `slots`; a full push carries every table), and the HUD
-- rebuilds the open window when some of them change. Owner bug 2026-10-15 ("why does the shop money menu
-- go up"): every plants push rebuilt the Shop, which threw its scroll back up. Only keys whose value
-- differs from what the client already has count as changed.
local StatsDiff = {}

-- Deep equality for the plain data the server sends (numbers, strings, booleans, tables of them).
function StatsDiff.same(a: any, b: any, depth: number?): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	local d = depth or 0
	if d > 8 then
		return false -- too deep to bother: call it changed
	end
	for k, v in a do
		if not StatsDiff.same(v, b[k], d + 1) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

-- Copies `partial` into `stats` and returns what actually changed (key -> new value).
function StatsDiff.apply(stats: { [string]: any }, partial: { [string]: any }): { [string]: any }
	local changed = {}
	for k, v in partial do
		if not StatsDiff.same(stats[k], v) then
			changed[k] = v
		end
		stats[k] = v
	end
	return changed
end

return StatsDiff
