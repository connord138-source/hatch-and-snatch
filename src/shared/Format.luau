--!strict
-- Display formatting helpers.
local Format = {}

local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi" }

-- 1234 -> "1.23K", 5_600_000 -> "5.6M", 990_400 -> "990K"
function Format.cash(amount: number): string
	local value = math.max(0, amount)
	if value < 1000 then
		return "$" .. tostring(math.floor(value))
	end
	local tier = 1
	-- Roll over slightly early so 999.6K reads "1M", not "1000K"
	while value >= 999.5 and tier < #suffixes do
		value /= 1000
		tier += 1
	end
	local text = string.format(if value >= 100 then "%.0f" elseif value >= 10 then "%.1f" else "%.2f", value)
	-- Trim trailing zeros after the decimal point only ("1.50" -> "1.5", but "990" stays)
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return "$" .. text .. suffixes[tier]
end

-- 100000 -> "100,000" (whole numbers, for odds like "1 in 10,000")
function Format.count(n: number): string
	local text = tostring(math.round(n))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	return (string.gsub(formatted, "^,", ""))
end

-- 3725 -> "1h 2m", 95 -> "1m 35s", 7 -> "7s"
function Format.duration(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local hours = s // 3600
	local minutes = (s % 3600) // 60
	local secs = s % 60
	if hours >= 24 then
		return `{hours // 24}d {hours % 24}h`
	elseif hours > 0 then
		return `{hours}h {minutes}m`
	elseif minutes > 0 then
		return `{minutes}m {secs}s`
	end
	return `{secs}s`
end

return Format
