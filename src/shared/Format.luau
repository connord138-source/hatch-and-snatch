--!strict
-- Display formatting helpers.
local Format = {}

local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi" }

-- 1234 -> "1.23K", 5_600_000 -> "5.6M"
function Format.cash(amount: number): string
	local value = math.max(0, amount)
	local tier = 1
	while value >= 1000 and tier < #suffixes do
		value /= 1000
		tier += 1
	end
	if tier == 1 then
		return "$" .. tostring(math.floor(value))
	end
	local text = string.format(if value >= 100 then "%.0f" elseif value >= 10 then "%.1f" else "%.2f", value)
	text = string.gsub(text, "%.?0+$", "")
	return "$" .. text .. suffixes[tier]
end

-- 3725 -> "1h 2m", 95 -> "1m 35s", 7 -> "7s"
function Format.duration(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local hours = s // 3600
	local minutes = (s % 3600) // 60
	local secs = s % 60
	if hours > 0 then
		return `{hours}h {minutes}m`
	elseif minutes > 0 then
		return `{minutes}m {secs}s`
	end
	return `{secs}s`
end

return Format
