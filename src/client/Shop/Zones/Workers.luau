-- Robot workers patrolling the factory. Their positions come from the shared
-- server clock, so every player sees them in the same place. They react to
-- purchase broadcasts: rare items make nearby robots stop, turn and cheer.
-- Robots right at the camera, or in front of the subject of a show / focus
-- shot, fade out instead of filling the screen.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Factory = require(Shared.Definitions.Factory)
local Rarities = require(Shared.Definitions.Rarities)
local Trove = require(Shared.Util.Trove)
local RobotModel = require(Shared.Models.RobotModel)

local Effects = require(script.Parent.Parent.Effects)
local UI = require(script.Parent.Parent.UI.Components)

local Workers = {}
Workers.__index = Workers

local CATCH_UP = 0.5 -- extra pace (x Speed) while a robot makes up the time it spent cheering
local TURN_RATE = 8 -- rad/s: corners, path ends and turning to the buyer
local CHEER_BLEND = 0.25 -- seconds to raise / lower the arms
local FADE_NEAR, FADE_FAR = 3, 6 -- studs from the camera to the body's axis: hidden / starts to fade
local FADE_RATE = 6 -- per second
local SHOT_DEPTH, SHOT_WIDTH = 15, 7 -- scripted shots: robots in front of the subject are hidden
local TIP_IN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TIP_FADE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TIP_OUT = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

type Path = { Points: { Vector3 }, Lengths: { number }, Total: number, PingPong: boolean }

-- Two-point paths, and paths listed in Factory.Workers.OpenPaths, are walked
-- back and forth; every other path is a closed loop.
local function buildPath(view, points: { Vector3 }, open: boolean?): Path
	local worldPoints = {}
	for _, p in points do
		table.insert(worldPoints, view:ToWorld(p))
	end
	local pingPong = #worldPoints == 2 or open == true
	local loop = table.clone(worldPoints)
	if not pingPong then
		table.insert(loop, worldPoints[1])
	end
	local lengths, total = {}, 0
	for i = 1, #loop - 1 do
		local length = (loop[i + 1] - loop[i]).Magnitude
		lengths[i] = length
		total += length
	end
	return { Points = loop, Lengths = lengths, Total = total, PingPong = pingPong }
end

local function sample(path: Path, distance: number): (Vector3, Vector3)
	local d = distance
	local back = false
	if path.PingPong then
		local period = path.Total * 2
		d = d % period
		if d > path.Total then
			d = period - d
			back = true
		end
	else
		d = d % path.Total
	end
	for i, length in path.Lengths do
		if d <= length then
			local a, b = path.Points[i], path.Points[i + 1]
			return a:Lerp(b, d / math.max(length, 0.001)), if back then (a - b).Unit else (b - a).Unit
		end
		d -= length
	end
	local n = #path.Points
	return path.Points[n], if back then (path.Points[n - 1] - path.Points[n]).Unit else (path.Points[n] - path.Points[n - 1]).Unit
end

-- One robot per path first. Extra robots only share closed loops: two robots
-- walking one path back and forth would meet and pass through each other.
local function pathFor(paths: { Path }, index: number): Path
	if index <= #paths then
		return paths[index]
	end
	local loops = {}
	for _, path in paths do
		if not path.PingPong then
			table.insert(loops, path)
		end
	end
	if #loops == 0 then
		return paths[(index - 1) % #paths + 1]
	end
	return loops[(index - #paths - 1) % #loops + 1]
end

local function approach(value: number, target: number, step: number): number
	if value < target then
		return math.min(value + step, target)
	end
	return math.max(value - step, target)
end

-- Pops the 🎉 in over a cheering robot and fades it out afterwards.
local function setTip(robot, on: boolean)
	for _, tween in robot.TipTweens do
		tween:Cancel()
	end
	table.clear(robot.TipTweens)
	local tip, label, scale = robot.Tip, robot.TipLabel, robot.TipScale
	local still = Effects.ReduceMotion()
	if on then
		if still then
			scale.Scale = 1
		elseif not tip.Enabled then
			scale.Scale = 0.3
		end
		tip.Enabled = true
		table.insert(robot.TipTweens, UI.Tween(label, TIP_FADE, { TextTransparency = 0 }))
		if not still then
			table.insert(robot.TipTweens, UI.Tween(scale, TIP_IN, { Scale = 1 }))
		end
	else
		local fade = UI.Tween(label, TIP_OUT, { TextTransparency = 1 })
		table.insert(robot.TipTweens, fade)
		if not still then
			table.insert(robot.TipTweens, UI.Tween(scale, TIP_OUT, { Scale = 0.6 }))
		end
		fade.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and not robot.TipOn then
				tip.Enabled = false
			end
		end)
	end
end

function Workers.new(view)
	local self = setmetatable({}, Workers)
	self.View = view
	self.Trove = Trove.new()
	self.ActiveTrove = Trove.new()
	self.Trove:Add(self.ActiveTrove, "Clean")
	self.Robots = {}
	self.Paths = {}
	local open = (Factory.Workers :: any).OpenPaths or {}
	for i, points in Factory.Workers.Paths do
		table.insert(self.Paths, buildPath(view, points, open[i] == true))
	end
	return self
end

function Workers:SetActive(active: boolean)
	self.ActiveTrove:Clean()
	self.Robots = {}
	self.LastStep = nil
	if not active then
		return
	end
	local theme = self.View.Theme
	local count = if Effects.IsLow() then Factory.Workers.LowGraphicsCount else Factory.Workers.Count
	local robots = {}
	for i = 1, count do
		local model = RobotModel.Worker(theme.Metal:Lerp(theme.Trim, (i % 3) / 3), theme.Neon)
		model.Parent = self.View.LocalFolder
		self.ActiveTrove:Add(model)
		local path = pathFor(self.Paths, i)
		-- Sized in studs, so it shrinks with distance like the robot under it.
		local tip = UI.new("BillboardGui", {
			Name = "Cheer",
			Size = UDim2.fromScale(2.2, 1.5),
			StudsOffset = Vector3.new(0, 6.6, 0),
			AlwaysOnTop = false,
			ClipsDescendants = false,
			Enabled = false,
			MaxDistance = 90,
			Adornee = model.PrimaryPart,
			Parent = model,
		})
		local label = UI.Label({
			Text = "🎉",
			Size = UDim2.fromScale(1, 1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTransparency = 1,
			Parent = tip,
		})
		local parts = {}
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") and part ~= model.PrimaryPart then
				table.insert(parts, part)
			end
		end
		table.insert(robots, {
			Model = model,
			Parts = parts,
			Path = path,
			Offset = (i * 37.3) % path.Total,
			CheerUntil = 0,
			Face = nil :: Vector3?,
			Frozen = nil :: number?,
			Lag = 0,
			Distance = nil :: number?,
			Phase = 0,
			Yaw = 0,
			Blend = 0,
			Fade = 0,
			Shown = 0,
			Tip = tip,
			TipLabel = label,
			TipScale = UI.GetScale(label),
			TipOn = false,
			TipTweens = {} :: { Tween },
		})
	end
	self.Robots = robots
	self.ActiveTrove:Add(function()
		for _, robot in robots do
			for _, tween in robot.TipTweens do
				tween:Cancel()
			end
		end
	end)

	local accumulator = 0
	self.ActiveTrove:Connect(RunService.Heartbeat, function(dt)
		-- Every frame on full graphics (a 30 Hz cadence judders against the
		-- camera); an even 15 Hz on low graphics, carrying the remainder over.
		if Effects.IsLow() then
			accumulator += dt
			if accumulator < 1 / 15 then
				return
			end
			accumulator = math.min(accumulator - 1 / 15, 1 / 15)
		end
		self:_step()
	end)
	-- The robots are built at the world origin: place them before they are drawn.
	self:_step()
end

function Workers:_step()
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	local dt = math.clamp(clock - (self.LastStep or clock), 0, 0.25)
	self.LastStep = clock
	local speed = Factory.Workers.Speed
	local camera = workspace.CurrentCamera
	local camCf = if camera then camera.CFrame else nil
	-- A show or focus mode frames its subject in the middle of the screen.
	local controller = self.View.Controller
	local framed = controller ~= nil and (controller:IsBusy() or controller:CurrentMode() ~= nil)
	for _, robot in self.Robots do
		local path = robot.Path
		local cheering = robot.CheerUntil > clock
		local synced = now * speed + robot.Offset
		local distance
		if cheering then
			robot.Frozen = robot.Frozen or (synced - robot.Lag)
			distance = robot.Frozen :: number
		else
			-- Resume where the cheer stopped, then catch up with the shared clock
			-- by walking a little faster (no jump along the path).
			if robot.Frozen then
				local period = if path.PingPong then path.Total * 2 else path.Total
				robot.Lag = (synced - robot.Frozen :: number) % period
				robot.Frozen = nil
			end
			robot.Lag = math.max(robot.Lag - dt * speed * CATCH_UP, 0)
			distance = synced - robot.Lag
		end
		local position, direction = sample(path, distance)
		local look = direction
		if cheering and robot.Face then
			local face = robot.Face :: Vector3
			local flat = Vector3.new(face.X - position.X, 0, face.Z - position.Z)
			if flat.Magnitude > 0.1 then
				look = flat.Unit
			end
		end
		local yaw = math.atan2(-look.X, -look.Z)
		local blend = if cheering then 1 else 0

		local fade = 0
		if camCf then
			local camPos = camCf.Position
			local rel = camPos - position
			-- distance from the camera to the robot's body (feet to antenna)
			local gap = Vector3.new(rel.X, rel.Y - math.clamp(rel.Y, 0.5, 5.2), rel.Z).Magnitude
			fade = math.clamp((FADE_FAR - gap) / (FADE_FAR - FADE_NEAR), 0, 1)
			if framed and fade < 1 then
				local offset = position + Vector3.new(0, 2.8, 0) - camPos
				local depth = camCf.LookVector:Dot(offset)
				if depth > 0 and depth < SHOT_DEPTH and (offset - camCf.LookVector * depth).Magnitude < SHOT_WIDTH then
					fade = 1
				end
			end
		end

		if robot.Distance == nil then
			robot.Phase = distance * 1.6
			robot.Yaw = yaw
			robot.Blend = blend
			robot.Fade = fade
		else
			-- legs follow the distance walked and settle to a standing pose while cheering
			if cheering then
				robot.Phase = approach(robot.Phase, math.floor(robot.Phase / math.pi + 0.5) * math.pi, dt * 8)
			else
				robot.Phase += math.clamp(distance - robot.Distance :: number, 0, speed) * 1.6
			end
			-- turn at a capped rate instead of snapping at corners and path ends
			local delta = (yaw - robot.Yaw + math.pi) % (2 * math.pi) - math.pi
			robot.Yaw = (robot.Yaw + math.clamp(delta, -TURN_RATE * dt, TURN_RATE * dt) + math.pi) % (2 * math.pi) - math.pi
			robot.Blend = approach(robot.Blend, blend, dt / CHEER_BLEND)
			robot.Fade = approach(robot.Fade, fade, dt * FADE_RATE)
		end
		robot.Distance = distance

		local shown = math.floor(robot.Fade * 20 + 0.5) / 20
		if shown ~= robot.Shown then
			robot.Shown = shown
			for _, part in robot.Parts do
				part.LocalTransparencyModifier = shown
			end
		end
		local tipOn = cheering and robot.Fade < 0.5
		if tipOn ~= robot.TipOn then
			robot.TipOn = tipOn
			setTip(robot, tipOn)
		end

		local eased = robot.Blend * robot.Blend * (3 - 2 * robot.Blend)
		local cheer = eased * (0.75 + 0.25 * math.sin(clock * 10))
		local hop = eased * math.abs(math.sin(clock * 7)) * 0.9
		local rootCf = CFrame.new(position) * CFrame.Angles(0, robot.Yaw, 0)
		-- The whole robot hops (feet included), so the body never floats off its legs.
		RobotModel.PoseWorker(robot.Model, rootCf * CFrame.new(0, hop, 0), robot.Phase, true, cheer, 0)
	end
end

-- Purchase broadcast reaction. `position` may be nil (buyer outside).
function Workers:React(position: Vector3?, rarity: string, isLocalPlayer: boolean)
	if #self.Robots == 0 then
		return
	end
	local strong = Rarities.AtLeast(rarity, "Rare")
	local radius = if strong then Factory.Workers.CheerRadius else 30
	local clock = os.clock()
	local reacted = 0
	for _, robot in self.Robots do
		local root = robot.Model.PrimaryPart
		if root then
			local near = position == nil or (root.Position - position).Magnitude <= radius
			if near and (strong or reacted == 0) then
				robot.CheerUntil = clock + (if strong then 2.8 else 1.2)
				robot.Face = position or (Players.LocalPlayer.Character and Players.LocalPlayer.Character:GetPivot().Position)
				reacted += 1
			end
		end
	end
	if isLocalPlayer and strong and position then
		Effects.Burst(position + Vector3.new(0, 3, 0), "Glow", 20, Rarities.Get(rarity).Color)
	end
end

function Workers:QualityChanged()
	if self.View.Near then
		self:SetActive(true)
	end
end

function Workers:Destroy()
	self.Trove:Clean()
end

return Workers
