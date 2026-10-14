-- Robot workers patrolling the factory. Their positions come from the shared
-- server clock, so every player sees them in the same place. They react to
-- purchase broadcasts: rare items make nearby robots stop, turn and cheer.

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

type Path = { Points: { Vector3 }, Lengths: { number }, Total: number, PingPong: boolean }

local function buildPath(view, points: { Vector3 }): Path
	local worldPoints = {}
	for _, p in points do
		table.insert(worldPoints, view:ToWorld(p))
	end
	local pingPong = #worldPoints == 2
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
	if path.PingPong then
		local period = path.Total * 2
		d = d % period
		if d > path.Total then
			local back = period - d
			local a, b = path.Points[1], path.Points[2]
			return a:Lerp(b, back / path.Total), (a - b).Unit
		end
	else
		d = d % path.Total
	end
	for i, length in path.Lengths do
		if d <= length then
			local a, b = path.Points[i], path.Points[i + 1]
			return a:Lerp(b, d / math.max(length, 0.001)), (b - a).Unit
		end
		d -= length
	end
	local n = #path.Points
	return path.Points[n], (path.Points[n] - path.Points[n - 1]).Unit
end

function Workers.new(view)
	local self = setmetatable({}, Workers)
	self.View = view
	self.Trove = Trove.new()
	self.ActiveTrove = Trove.new()
	self.Trove:Add(self.ActiveTrove, "Clean")
	self.Robots = {}
	self.Paths = {}
	for _, points in Factory.Workers.Paths do
		table.insert(self.Paths, buildPath(view, points))
	end
	return self
end

function Workers:SetActive(active: boolean)
	self.ActiveTrove:Clean()
	self.Robots = {}
	if not active then
		return
	end
	local theme = self.View.Theme
	local count = if Effects.IsLow() then Factory.Workers.LowGraphicsCount else Factory.Workers.Count
	for i = 1, count do
		local model = RobotModel.Worker(theme.Metal:Lerp(theme.Trim, (i % 3) / 3), theme.Neon)
		model.Parent = self.View.LocalFolder
		self.ActiveTrove:Add(model)
		local path = self.Paths[(i - 1) % #self.Paths + 1]
		local tip = UI.new("BillboardGui", {
			Name = "Cheer",
			Size = UDim2.fromOffset(60, 40),
			StudsOffset = Vector3.new(0, 6.6, 0),
			AlwaysOnTop = false,
			Enabled = false,
			MaxDistance = 120,
			Adornee = model.PrimaryPart,
			Parent = model,
		})
		UI.Label({ Text = "🎉", Size = UDim2.fromScale(1, 1), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, Parent = tip })
		table.insert(self.Robots, {
			Model = model,
			Path = path,
			Offset = (i * 37.3) % path.Total,
			Cheer = 0,
			CheerUntil = 0,
			Hop = 0,
			Face = nil :: Vector3?,
			Frozen = nil :: number?,
			Tip = tip,
		})
	end

	local accumulator = 0
	self.ActiveTrove:Connect(RunService.Heartbeat, function(dt)
		accumulator += dt
		if accumulator < (if Effects.IsLow() then 1 / 15 else 1 / 30) then
			return
		end
		accumulator = 0
		self:_step()
	end)
end

function Workers:_step()
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	local speed = Factory.Workers.Speed
	for _, robot in self.Robots do
		local cheering = robot.CheerUntil > clock
		local distance
		if cheering then
			robot.Frozen = robot.Frozen or (now * speed + robot.Offset)
			distance = robot.Frozen :: number
		else
			robot.Frozen = nil
			distance = now * speed + robot.Offset
		end
		local position, direction = sample(robot.Path, distance)
		local look = direction
		if cheering and robot.Face then
			local face = robot.Face :: Vector3
			local flat = Vector3.new(face.X - position.X, 0, face.Z - position.Z)
			if flat.Magnitude > 0.1 then
				look = flat.Unit
			end
		end
		local rootCf = CFrame.lookAt(position, position + look)
		local cheer = if cheering then 0.75 + 0.25 * math.sin(clock * 10) else 0
		local hop = if cheering then math.abs(math.sin(clock * 7)) * 0.9 else 0
		robot.Tip.Enabled = cheering
		RobotModel.PoseWorker(robot.Model, rootCf, distance * 1.6, not cheering, cheer, hop)
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
