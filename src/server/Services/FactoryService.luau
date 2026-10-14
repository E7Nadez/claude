-- Spawns one Mega-Factory per released world, answers "which factory is this
-- position in?", and (optionally) drives the day/night clock that powers
-- night deals and the neon night look.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Worlds = require(Shared.Definitions.Worlds)
local Factory = require(Shared.Definitions.Factory)

local FactoryBuilder = require(script.Parent.Parent.Factory.FactoryBuilder)

local FactoryService = {}

local factories: { [string]: Model } = {}
local origins: { [string]: CFrame } = {}

-- A Part named FactoryAnchor inside workspace.Worlds.<WorldId> overrides the
-- default origin. Its LookVector must point into the building.
local function resolveOrigin(worldId: string, fallback: CFrame): CFrame
	local worldsFolder = workspace:FindFirstChild("Worlds")
	local worldFolder = worldsFolder and worldsFolder:FindFirstChild(worldId)
	local anchor = worldFolder and worldFolder:FindFirstChild("FactoryAnchor", true)
	if anchor and anchor:IsA("BasePart") then
		anchor.Transparency = 1
		anchor.CanCollide = false
		local look = anchor.CFrame.LookVector * Vector3.new(1, 0, 1)
		local position = anchor.Position - Vector3.new(0, anchor.Size.Y / 2, 0)
		-- Facade faces -Z, so the factory's +Z must point into the building.
		return CFrame.lookAt(position, position - look.Unit)
	end
	return fallback
end

function FactoryService:Init()
	local folder = workspace:FindFirstChild(Factory.FolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Factory.FolderName
		folder.Parent = workspace
	end
	for _, worldDef in Worlds.Released() do
		local origin = resolveOrigin(worldDef.Id, worldDef.FactoryOrigin)
		origins[worldDef.Id] = origin
		local ok, result = pcall(FactoryBuilder.Build, worldDef.Id, origin, folder)
		if ok then
			factories[worldDef.Id] = result
		else
			warn("[FactoryService] failed to build factory for", worldDef.Id, result)
		end
	end
end

function FactoryService:Start()
	local config = Factory.DayNight
	if config.DriveClock then
		Lighting.ClockTime = config.StartClock
		local hoursPerSecond = 24 / (config.CycleMinutes * 60)
		local clock = config.StartClock
		local accumulator = 0
		RunService.Heartbeat:Connect(function(dt)
			clock = (clock + dt * hoursPerSecond) % 24
			accumulator += dt
			-- Replicating every frame is wasteful; four updates a second is smooth.
			if accumulator >= 0.25 then
				accumulator = 0
				Lighting.ClockTime = clock
			end
		end)
	end
end

function FactoryService:GetFactory(worldId: string): Model?
	return factories[worldId]
end

function FactoryService:GetOrigin(worldId: string): CFrame?
	return origins[worldId]
end

-- World id of the factory containing `position`, or nil when outside.
function FactoryService:WorldAt(position: Vector3): string?
	local size = Factory.Size
	for worldId, origin in origins do
		local p = origin:PointToObjectSpace(position)
		if math.abs(p.X) <= size.X / 2 + 2 and p.Z >= -30 and p.Z <= size.Z + 2 and p.Y > -10 and p.Y < size.Y + 30 then
			return worldId
		end
	end
	return nil
end

return FactoryService
