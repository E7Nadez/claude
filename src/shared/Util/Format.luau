--!strict
-- Number / time formatting shared by every UI surface.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Format.Abbreviate(value: number): string
	local negative = value < 0
	local n = math.abs(value)
	if n < 1000 then
		local text = if n % 1 == 0 then tostring(n) else string.format("%.1f", n)
		return (if negative then "-" else "") .. text
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / 10 ^ (tier * 3)
	local text
	if scaled >= 100 then
		text = string.format("%d", math.floor(scaled))
	elseif scaled >= 10 then
		text = string.format("%.1f", math.floor(scaled * 10) / 10)
	else
		text = string.format("%.2f", math.floor(scaled * 100) / 100)
	end
	text = string.gsub(text, "%.?0+$", "")
	return (if negative then "-" else "") .. text .. SUFFIXES[tier + 1]
end

function Format.Commas(value: number): string
	local text = tostring(math.floor(math.abs(value)))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	formatted = formatted:gsub("^,", "")
	return (if value < 0 then "-" else "") .. formatted
end

-- 75 -> "1:15", 3700 -> "1:01:40"
function Format.Clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- 900 -> "15m", 5400 -> "1h 30m"
function Format.Duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		local h = seconds // 3600
		local m = (seconds % 3600) // 60
		return if m > 0 then string.format("%dh %dm", h, m) else string.format("%dh", h)
	elseif seconds >= 60 then
		local m = seconds // 60
		local s = seconds % 60
		return if s > 0 then string.format("%dm %ds", m, s) else string.format("%dm", m)
	end
	return string.format("%ds", seconds)
end

function Format.Percent(fraction: number, signed: boolean?): string
	local pct = math.floor(fraction * 100 + 0.5)
	if signed and pct > 0 then
		return "+" .. Format.Commas(pct) .. "%"
	end
	return Format.Commas(pct) .. "%"
end

function Format.Chance(probability: number): string
	if probability >= 0.1 then
		return string.format("%.0f%%", probability * 100)
	elseif probability >= 0.01 then
		return string.format("%.1f%%", probability * 100)
	end
	return string.format("1 in %s", Format.Commas(math.floor(1 / probability + 0.5)))
end

function Format.Stat(value: number): string
	if value >= 1000 then
		return Format.Abbreviate(value)
	elseif value % 1 == 0 then
		return tostring(value)
	end
	return string.format("%.1f", value)
end

return Format
