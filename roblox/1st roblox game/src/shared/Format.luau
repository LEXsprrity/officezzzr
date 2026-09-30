--!strict
-- Number formatting shared by HUD, billboards and popups.
local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 999 -> "999", 1234 -> "1.2K", 56789 -> "56.8K", 123456 -> "123K", 2e9 -> "2B"
function Format.short(n: number): string
	if n ~= n then
		return "0"
	end
	local sign = if n < 0 then "-" else ""
	n = math.abs(n)
	if n < 1000 then
		return sign .. tostring(math.floor(n))
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / 10 ^ (tier * 3)
	-- Rounding can push 999.95K up to "1000K"; move to the next suffix instead.
	if scaled >= 999.95 and tier < #SUFFIXES - 1 then
		tier += 1
		scaled = n / 10 ^ (tier * 3)
	end
	local text
	if scaled >= 100 then
		text = string.format("%d", math.floor(scaled))
	else
		text = string.format("%.1f", scaled)
		text = string.gsub(text, "%.0$", "")
	end
	return sign .. text .. SUFFIXES[tier + 1]
end

function Format.money(n: number): string
	return "$" .. Format.short(n)
end

-- 2018798.4 -> "2,018,798"
function Format.commas(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	if math.abs(n) >= 1e15 then
		return Format.short(n)
	end
	local out = s
	while true do
		local replaced, count = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		out = replaced
		if count == 0 then
			break
		end
	end
	return (if n < 0 then "-" else "") .. out
end

function Format.weight(kg: number): string
	return Format.commas(kg) .. " Kg"
end

-- 75 -> "1:15"
function Format.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return Format
