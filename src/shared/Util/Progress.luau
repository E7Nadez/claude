--!strict
-- Unlock conditions, evaluated identically on server (validation) and client
-- (glass case + lock text). Condition shapes:
--   { Type = "OwnsVacuum", Vacuum = id }
--   { Type = "BossDefeated", Boss = id }
--   { Type = "WorldUnlocked", World = id }
--   { Type = "Mastery", World = id, Level = n }

local Definitions = script.Parent.Parent.Definitions
local Vacuums = require(Definitions.Vacuums)
local Bosses = require(Definitions.Bosses)
local Worlds = require(Definitions.Worlds)

local Progress = {}

function Progress.Describe(condition: { [string]: any }): string
	local kind = condition.Type
	if kind == "OwnsVacuum" then
		local vacuum = Vacuums.Get(condition.Vacuum)
		return "Own the " .. (if vacuum then vacuum.Name else tostring(condition.Vacuum))
	elseif kind == "BossDefeated" then
		local boss = Bosses[condition.Boss]
		return "Defeat the " .. (if boss then boss.Name else tostring(condition.Boss))
	elseif kind == "WorldUnlocked" then
		local world = Worlds.Get(condition.World)
		return "Unlock " .. (if world then world.Name else tostring(condition.World))
	elseif kind == "Mastery" then
		local world = Worlds.Get(condition.World)
		return string.format("Reach %s Mastery %d", if world then world.Name else tostring(condition.World), condition.Level or 1)
	end
	return "Locked"
end

function Progress.Check(data: any, condition: { [string]: any }): boolean
	if type(data) ~= "table" then
		return false
	end
	local kind = condition.Type
	if kind == "OwnsVacuum" then
		return data.Vacuums ~= nil and data.Vacuums.Owned[condition.Vacuum] == true
	elseif kind == "BossDefeated" then
		return data.Progress ~= nil and (data.Progress.Bosses[condition.Boss] or 0) > 0
	elseif kind == "WorldUnlocked" then
		return data.Progress ~= nil and data.Progress.Worlds[condition.World] == true
	elseif kind == "Mastery" then
		return data.Progress ~= nil and (data.Progress.Mastery[condition.World] or 0) >= (condition.Level or 1)
	end
	return false
end

-- Returns true, or false plus the first unmet condition's text.
function Progress.CheckAll(data: any, conditions: { { [string]: any } }?): (boolean, string?)
	if not conditions then
		return true, nil
	end
	for _, condition in conditions do
		if not Progress.Check(data, condition) then
			return false, Progress.Describe(condition)
		end
	end
	return true, nil
end

-- All unmet conditions (for the animated lock text on glass cases).
function Progress.Missing(data: any, conditions: { { [string]: any } }?): { string }
	local missing = {}
	if conditions then
		for _, condition in conditions do
			if not Progress.Check(data, condition) then
				table.insert(missing, Progress.Describe(condition))
			end
		end
	end
	return missing
end

function Progress.HighestWorld(data: any): string
	local best, bestOrder = "Cleanville", 0
	if type(data) == "table" and data.Progress then
		for worldId, unlocked in data.Progress.Worlds do
			local world = Worlds.Get(worldId)
			if unlocked and world and world.Order > bestOrder then
				best, bestOrder = worldId, world.Order
			end
		end
	end
	return best
end

function Progress.EconomyMultiplier(data: any): number
	local world = Worlds.Get(Progress.HighestWorld(data))
	return if world then world.EconomyMultiplier else 1
end

function Progress.WorldUnlocked(data: any, worldId: string): boolean
	return type(data) == "table" and data.Progress ~= nil and data.Progress.Worlds[worldId] == true
end

return Progress
