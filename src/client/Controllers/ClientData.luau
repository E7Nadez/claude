-- Read-only mirror of the player's profile, pushed by the server. The client
-- never decides anything with it; it only renders states and previews.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Stats = require(Shared.Util.Stats)
local DayNight = require(Shared.Util.DayNight)

local ClientData = {}

ClientData.Changed = Signal.new() -- (data, previous)
ClientData.SettingsChanged = Signal.new() -- (settings)

local current: { [string]: any }? = nil
local localSettings: { [string]: any } = {}

local function detectLowEnd(): boolean
	local ok, quality = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if ok and quality ~= Enum.SavedQualitySetting.Automatic then
		return quality.Value <= 3
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function apply(snapshot: { [string]: any })
	local previous = current
	current = snapshot
	-- Local optimistic settings win until the server confirms them.
	for key, value in localSettings do
		snapshot.Settings[key] = value
	end
	ClientData.Changed:Fire(snapshot, previous)
	ClientData.SettingsChanged:Fire(snapshot.Settings)
end

function ClientData:Init() end

function ClientData:Start()
	Net.Event("DataSync").OnClientEvent:Connect(function(snapshot)
		if type(snapshot) == "table" then
			apply(snapshot)
		end
	end)
	task.delay(4, function()
		if current then
			return
		end
		for _ = 1, 10 do
			local result = Net.Invoke("RequestSync")
			if result.Ok and type(result.Data) == "table" then
				if not current then
					apply(result.Data)
				end
				return
			end
			task.wait(2)
		end
	end)
end

function ClientData:Get(): { [string]: any }?
	return current
end

function ClientData:WaitForData(): { [string]: any }
	while not current do
		ClientData.Changed:Wait()
	end
	return current :: { [string]: any }
end

function ClientData:Currency(id: string): number
	return if current then current.Currencies[id] or 0 else 0
end

function ClientData:Equipped(): string
	return if current then current.Vacuums.Equipped else "vac_dust_buster"
end

function ClientData:Owns(vacuumId: string): boolean
	return current ~= nil and current.Vacuums.Owned[vacuumId] == true
end

function ClientData:UpgradeLevel(id: string): number
	return if current then current.Upgrades[id] or 0 else 0
end

function ClientData:EffectiveStats(vacuumId: string): Stats.Stats
	return Stats.Effective(vacuumId, current and current.Upgrades)
end

function ClientData:Setting(key: string): any
	if localSettings[key] ~= nil then
		return localSettings[key]
	end
	local value = current and current.Settings[key]
	if value == nil and key == "LowGraphics" then
		return detectLowEnd()
	end
	return value
end

function ClientData:LowGraphics(): boolean
	return self:Setting("LowGraphics") == true
end

function ClientData:ReduceMotion(): boolean
	return self:Setting("ReduceMotion") == true
end

function ClientData:SetSetting(key: string, value: any)
	localSettings[key] = value
	if current then
		current.Settings[key] = value
		ClientData.SettingsChanged:Fire(current.Settings)
	end
	task.spawn(function()
		local result = Net.Invoke("SetSetting", key, value)
		if result.Ok then
			localSettings[key] = nil
		end
	end)
end

function ClientData:Now(): number
	return workspace:GetServerTimeNow()
end

function ClientData:IsNight(): boolean
	return DayNight.IsNight()
end

function ClientData:Player(): Player
	return Players.LocalPlayer
end

return ClientData
