--!strict
-- Vacuum stat math shared by the hologram comparison, the Test Chamber live
-- simulation and the server's comparison result.

local Definitions = script.Parent.Parent.Definitions
local Vacuums = require(Definitions.Vacuums)
local Upgrades = require(Definitions.Upgrades)
local Trash = require(Definitions.Trash)
local Factory = require(Definitions.Factory)

export type Stats = Vacuums.Stats

local Stats = {}

Stats.Order = { "Power", "Capacity", "Speed", "Range" }

Stats.Labels = {
	Power = "Power",
	Capacity = "Tank",
	Speed = "Speed",
	Range = "Range",
}

Stats.Glyphs = {
	Power = "💪",
	Capacity = "🛢",
	Speed = "⚡",
	Range = "📡",
}

function Stats.Effective(vacuumId: string, upgradeLevels: { [string]: number }?): Stats
	local vacuum = Vacuums.Get(vacuumId)
	local base = if vacuum then vacuum.Stats else { Power = 1, Capacity = 10, Speed = 1, Range = 5 }
	local mult = Upgrades.StatMultipliers(upgradeLevels)
	return {
		Power = base.Power * mult.Power,
		Capacity = base.Capacity * mult.Capacity,
		Speed = base.Speed * mult.Speed,
		Range = base.Range * mult.Range,
	}
end

-- Pulls per second. Range helps because more trash is in reach.
function Stats.PullRate(stats: Stats): number
	return stats.Speed * (0.6 + stats.Range / 25)
end

-- Average tank volume of the trash this vacuum can lift.
function Stats.AverageVolume(stats: Stats, trashSet: string): number
	local liftable, totalChance = Trash.Liftable(trashSet, stats.Power)
	if totalChance <= 0 then
		return 0
	end
	local sum = 0
	for _, item in liftable do
		sum += item.Volume * item.Chance
	end
	return sum / totalChance
end

export type TestResult = {
	Items: number,
	Volume: number,
	Dumps: number,
	Score: number, -- cleaned volume per second
}

-- Deterministic expectation of a Test Chamber run.
function Stats.SimulateTest(stats: Stats, trashSet: string, duration: number?): TestResult
	local seconds = duration or Factory.TestChamber.Duration
	local avgVolume = Stats.AverageVolume(stats, trashSet)
	if avgVolume <= 0 then
		return { Items = 0, Volume = 0, Dumps = 0, Score = 0 }
	end
	local rate = Stats.PullRate(stats)
	local dumpTime = Factory.TestChamber.DumpTime
	local itemsPerTank = math.max(1, stats.Capacity / avgVolume)
	local fillTime = itemsPerTank / rate

	local items, dumps
	if fillTime >= seconds then
		items = rate * seconds
		dumps = 0
	else
		local cycle = fillTime + dumpTime
		local fullCycles = math.floor(seconds / cycle)
		local remainder = seconds - fullCycles * cycle
		items = fullCycles * itemsPerTank + math.min(remainder, fillTime) * rate
		dumps = fullCycles
	end
	local volume = items * avgVolume
	return {
		Items = math.floor(items),
		Volume = volume,
		Dumps = dumps,
		Score = volume / seconds,
	}
end

export type Comparison = {
	Percent: number, -- fraction: 3.4 means +340 %
	TestScore: number,
	CurrentScore: number,
	TestItems: number,
	CurrentItems: number,
}

function Stats.Compare(testStats: Stats, currentStats: Stats, trashSet: string): Comparison
	local test = Stats.SimulateTest(testStats, trashSet)
	local current = Stats.SimulateTest(currentStats, trashSet)
	local percent
	if current.Score <= 0 then
		percent = if test.Score > 0 then 99 else 0
	else
		percent = test.Score / current.Score - 1
	end
	return {
		Percent = percent,
		TestScore = test.Score,
		CurrentScore = current.Score,
		TestItems = test.Items,
		CurrentItems = current.Items,
	}
end

-- Relative difference per stat, for hologram bars (+ green / - red).
function Stats.Delta(a: Stats, b: Stats): { [string]: number }
	local result = {}
	for _, key in Stats.Order do
		local av, bv = (a :: any)[key], (b :: any)[key]
		result[key] = if bv > 0 then av / bv - 1 else 0
	end
	return result
end

-- 0..1 bar fill on a log scale so starter and mythic both read well.
function Stats.BarFill(stat: string, value: number): number
	local maxima = { Power = 1200, Capacity = 40_000, Speed = 25, Range = 40 }
	local minima = { Power = 1, Capacity = 15, Speed = 0.8, Range = 5 }
	local lo, hi = minima[stat] or 1, maxima[stat] or 100
	local t = (math.log(math.max(value, lo)) - math.log(lo)) / (math.log(hi) - math.log(lo))
	return math.clamp(t, 0.04, 1)
end

return Stats
