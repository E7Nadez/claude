-- "Try Before You Buy". The server owns the session: which lane, which
-- vacuum, when it ends. Clients only render. Lane state is replicated through
-- attributes on the lane model so every player sees who is testing what.
--
-- Anti-exploit: type checks, rate limit, cooldown, one session per player,
-- distance check to the factory, unlock check, hard server-side timeout.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Errors = require(Shared.Util.Errors)
local Format = require(Shared.Util.Format)
local Stats = require(Shared.Util.Stats)
local Progress = require(Shared.Util.Progress)
local Vacuums = require(Shared.Definitions.Vacuums)
local Worlds = require(Shared.Definitions.Worlds)
local Factory = require(Shared.Definitions.Factory)

local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local TestChamberService = {}

local DataService
local FactoryService

type Session = {
	Lane: Model,
	World: string,
	VacuumId: string,
	EndsAt: number,
	Timer: thread?,
	Connections: { RBXScriptConnection },
}

local sessions: { [Player]: Session } = {}
local cooldownUntil: { [Player]: number } = {}
local limiter = RateLimiter.new(4, 1)

function TestChamberService:Init(services)
	DataService = services.DataService
	FactoryService = services.FactoryService
end

function TestChamberService:Start()
	Net.Function("StartTestChamber").OnServerInvoke = function(player, vacuumId)
		return TestChamberService:StartSession(player, vacuumId)
	end
	Net.Function("StopTestChamber").OnServerInvoke = function(player)
		if not limiter:Check(player) then
			return Errors.Result("RATE_LIMITED")
		end
		if not sessions[player] then
			return Errors.Result("NOT_TESTING")
		end
		local comparison = TestChamberService:EndSession(player, "Stopped")
		return { Ok = true, Comparison = comparison }
	end
	Players.PlayerRemoving:Connect(function(player)
		TestChamberService:EndSession(player, "Left")
		cooldownUntil[player] = nil
	end)
end

local function hasExpress(player: Player): boolean
	local data = DataService:GetData(player)
	return data ~= nil and data.Gamepasses.gp_express == true
end

local function clearLane(lane: Model)
	lane:SetAttribute("Occupant", 0)
	lane:SetAttribute("OccupantName", "")
	lane:SetAttribute("VacuumId", "")
	lane:SetAttribute("Skin", "")
	lane:SetAttribute("EndsAt", 0)
end

function TestChamberService:StartSession(player: Player, vacuumId: any)
	if typeof(vacuumId) ~= "string" or #vacuumId > 64 then
		return Errors.Result("INVALID")
	end
	if not limiter:Check(player) then
		return Errors.Result("RATE_LIMITED")
	end
	if sessions[player] then
		return Errors.Result("ALREADY_TESTING")
	end
	local data = DataService:GetData(player)
	if not data then
		return Errors.Result("NOT_LOADED")
	end
	local vacuum = Vacuums.Get(vacuumId)
	if not vacuum then
		return Errors.Result("INVALID_ITEM")
	end

	local now = os.clock()
	local cooldown = cooldownUntil[player]
	if cooldown and cooldown > now and not hasExpress(player) then
		return Errors.Result("COOLDOWN", Format.Duration(math.ceil(cooldown - now)))
	end

	if not data.Vacuums.Owned[vacuumId] then
		local ok, reason = Progress.CheckAll(data, vacuum.Unlock)
		if not ok then
			return Errors.Result("LOCKED", reason or "")
		end
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return Errors.Result("NO_CHARACTER")
	end

	local factory = FactoryService:GetFactory(vacuum.World)
	if not factory then
		return Errors.Result("UNAVAILABLE")
	end
	local origin = FactoryService:GetOrigin(vacuum.World) :: CFrame
	if (root.Position - origin.Position).Magnitude > Factory.TestChamber.MaxStartDistance then
		return Errors.Result("TOO_FAR")
	end

	local lanesFolder = factory:FindFirstChild("TestChamber") and factory.TestChamber:FindFirstChild("Lanes")
	local freeLane: Model? = nil
	if lanesFolder then
		for index = 1, #Factory.TestChamber.Lanes do
			local lane = lanesFolder:FindFirstChild("Lane_" .. index)
			if lane and lane:IsA("Model") and (lane:GetAttribute("Occupant") or 0) == 0 then
				freeLane = lane
				break
			end
		end
	end
	if not freeLane then
		return Errors.Result("LANES_BUSY")
	end
	local lane = freeLane :: Model

	local duration = Factory.TestChamber.Duration
	local endsAt = workspace:GetServerTimeNow() + duration
	lane:SetAttribute("Occupant", player.UserId)
	lane:SetAttribute("OccupantName", player.DisplayName)
	lane:SetAttribute("VacuumId", vacuumId)
	lane:SetAttribute("Skin", data.Cosmetics.Skin or "")
	lane:SetAttribute("EndsAt", endsAt)

	local pad = lane:FindFirstChild("Pad") :: BasePart?
	local belt = lane:FindFirstChild("Belt") :: BasePart?
	if pad and belt then
		local standAt = pad.Position + Vector3.new(0, 3.2, 0)
		local lookAt = Vector3.new(belt.Position.X, standAt.Y, belt.Position.Z)
		character:PivotTo(CFrame.lookAt(standAt, lookAt))
	end

	local session: Session = {
		Lane = lane,
		World = vacuum.World,
		VacuumId = vacuumId,
		EndsAt = endsAt,
		Timer = nil,
		Connections = {},
	}
	sessions[player] = session
	session.Timer = task.delay(duration + 0.75, function()
		session.Timer = nil
		TestChamberService:EndSession(player, "Timeout")
	end)
	table.insert(session.Connections, humanoid.Died:Connect(function()
		TestChamberService:EndSession(player, "Died")
	end))
	table.insert(session.Connections, player.CharacterRemoving:Connect(function()
		TestChamberService:EndSession(player, "Respawned")
	end))

	DataService:Update(player, function(d)
		d.Stats.TestRuns += 1
	end)

	return {
		Ok = true,
		Lane = lane.Name,
		World = vacuum.World,
		VacuumId = vacuumId,
		EndsAt = endsAt,
		Duration = duration,
	}
end

-- Ends a running session and returns the comparison for the result board.
function TestChamberService:EndSession(player: Player, reason: string): Stats.Comparison?
	local session = sessions[player]
	if not session then
		return nil
	end
	sessions[player] = nil
	if session.Timer and coroutine.status(session.Timer) ~= "dead" and session.Timer ~= coroutine.running() then
		task.cancel(session.Timer)
	end
	for _, connection in session.Connections do
		connection:Disconnect()
	end
	clearLane(session.Lane)
	cooldownUntil[player] = os.clock() + Factory.TestChamber.Cooldown

	local comparison = nil
	local data = DataService:GetData(player)
	if data then
		local world = Worlds.Get(session.World)
		local trashSet = if world then world.TrashSet else "Cleanville"
		comparison = Stats.Compare(
			Stats.Effective(session.VacuumId, data.Upgrades),
			Stats.Effective(data.Vacuums.Equipped, data.Upgrades),
			trashSet
		)
	end

	if reason ~= "Stopped" and player.Parent then
		Net.Event("TestChamberEnded"):FireClient(player, {
			Reason = reason,
			VacuumId = session.VacuumId,
			Comparison = comparison,
		})
	end
	return comparison
end

function TestChamberService:IsTesting(player: Player): boolean
	return sessions[player] ~= nil
end

return TestChamberService
