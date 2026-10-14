-- Worker robots and assembly arms, built from Parts and posed from code.

local Builder = require(script.Parent.Parent.Util.Builder)

local RobotModel = {}

local DARK = Color3.fromRGB(36, 38, 46)

local function add(model: Model, props: { [string]: any }): BasePart
	local part = Builder.Part(props)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = model
	return part
end

-- Worker robot. Parts are named so the client can pose them:
-- Body, Head, Visor, Antenna, Tip, LegL, LegR, ArmL, ArmR.
-- Every part stores Home (root space). Arms/legs store Pivot (root space).
function RobotModel.Worker(color: Color3, glow: Color3): Model
	local model = Instance.new("Model")
	model.Name = "WorkerBot"
	local root = add(model, { Name = "Root", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(), Transparency = 1 })
	model.PrimaryPart = root

	add(model, { Name = "Body", Size = Vector3.new(2.0, 1.8, 1.3), CFrame = CFrame.new(0, 2.6, 0), Color = color, Material = Enum.Material.Metal })
	add(model, { Name = "Belly", Size = Vector3.new(1.2, 0.5, 0.05), CFrame = CFrame.new(0, 2.5, -0.67), Color = glow, Material = Enum.Material.Neon })
	add(model, { Name = "Head", Size = Vector3.new(1.5, 1.1, 1.2), CFrame = CFrame.new(0, 4.1, 0), Color = color, Material = Enum.Material.Metal })
	add(model, { Name = "Visor", Size = Vector3.new(1.2, 0.4, 0.05), CFrame = CFrame.new(0, 4.15, -0.62), Color = glow, Material = Enum.Material.Neon })
	add(model, { Name = "Antenna", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 0.12, 0.12), CFrame = CFrame.new(0, 5.0, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = DARK })
	add(model, { Name = "Tip", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.3, CFrame = CFrame.new(0, 5.4, 0), Color = glow, Material = Enum.Material.Neon })

	for _, side in { -1, 1 } do
		local leg = add(model, {
			Name = if side < 0 then "LegL" else "LegR",
			Size = Vector3.new(0.55, 1.7, 0.6),
			CFrame = CFrame.new(side * 0.55, 0.85, 0),
			Color = DARK,
		})
		leg:SetAttribute("Pivot", Vector3.new(side * 0.55, 1.7, 0))
		local arm = add(model, {
			Name = if side < 0 then "ArmL" else "ArmR",
			Size = Vector3.new(0.4, 1.5, 0.45),
			CFrame = CFrame.new(side * 1.25, 2.7, 0),
			Color = color:Lerp(DARK, 0.4),
			Material = Enum.Material.Metal,
		})
		arm:SetAttribute("Pivot", Vector3.new(side * 1.25, 3.4, 0))
	end

	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part ~= root then
			part:SetAttribute("Home", part.CFrame)
		end
	end
	return model
end

-- Poses a worker: `walk` is a phase in radians (0 = standing), `cheer` 0..1
-- raises the arms, `bob` lifts the whole body.
function RobotModel.PoseWorker(model: Model, rootCf: CFrame, walk: number, walking: boolean, cheer: number, hop: number)
	local parts = {}
	local cframes = {}
	local swing = if walking then math.sin(walk) * 0.6 else 0
	local lift = if walking then math.abs(math.sin(walk)) * 0.15 else 0
	local base = rootCf * CFrame.new(0, lift + hop, 0)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "Root" then
			local home = part:GetAttribute("Home") :: CFrame
			local cf
			local name = part.Name
			if name == "LegL" or name == "LegR" then
				local pivot = part:GetAttribute("Pivot") :: Vector3
				local s = if name == "LegL" then swing else -swing
				cf = base * CFrame.new(pivot) * CFrame.Angles(s, 0, 0) * CFrame.new(-pivot) * home
				cf = cf * CFrame.new(0, -lift - hop, 0)
			elseif name == "ArmL" or name == "ArmR" then
				local pivot = part:GetAttribute("Pivot") :: Vector3
				local side = if name == "ArmL" then -1 else 1
				local s = if name == "ArmL" then -swing else swing
				local raise = cheer * math.rad(160)
				cf = base * CFrame.new(pivot) * CFrame.Angles(s * (1 - cheer), 0, side * raise) * CFrame.new(-pivot) * home
			else
				cf = base * home
			end
			table.insert(parts, part)
			table.insert(cframes, cf)
		end
	end
	local root = model.PrimaryPart
	if root then
		table.insert(parts, root)
		table.insert(cframes, rootCf)
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Assembly arm: Base, Turret, Lower, Elbow, Upper, ClawA, ClawB, Tip.
RobotModel.ArmLengths = { Shoulder = 1.6, Lower = 3.2, Upper = 2.8 }

function RobotModel.Arm(color: Color3, glow: Color3): Model
	local model = Instance.new("Model")
	model.Name = "AssemblyArm"
	local base = add(model, { Name = "Base", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 1.8, 1.8), CFrame = CFrame.Angles(0, 0, math.pi / 2), Color = DARK, Material = Enum.Material.Metal })
	model.PrimaryPart = base
	add(model, { Name = "Turret", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.0, 1.2, 1.2), Color = color, Material = Enum.Material.Metal })
	add(model, { Name = "Lower", Size = Vector3.new(0.55, 0.55, RobotModel.ArmLengths.Lower), Color = color, Material = Enum.Material.Metal })
	add(model, { Name = "Elbow", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8, Color = DARK, Material = Enum.Material.Metal })
	add(model, { Name = "Upper", Size = Vector3.new(0.45, 0.45, RobotModel.ArmLengths.Upper), Color = color, Material = Enum.Material.Metal })
	add(model, { Name = "ClawA", Size = Vector3.new(0.15, 0.5, 0.6), Color = DARK })
	add(model, { Name = "ClawB", Size = Vector3.new(0.15, 0.5, 0.6), Color = DARK })
	add(model, { Name = "Tip", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.3, Color = glow, Material = Enum.Material.Neon })
	return model
end

local function lookAlong(position: Vector3, direction: Vector3): CFrame
	local up = if math.abs(direction.Unit.Y) > 0.98 then Vector3.zAxis else Vector3.yAxis
	return CFrame.lookAt(position, position + direction, up)
end

-- Two-bone IK: places the arm (based at baseCf, standing on the floor) so the
-- claw tip reaches `target`. `open` 0..1 spreads the claw. Returns tip CFrame.
function RobotModel.ReachArm(arm: Model, baseCf: CFrame, target: Vector3, open: number?): CFrame
	local L = RobotModel.ArmLengths
	local shoulder = baseCf.Position + Vector3.new(0, L.Shoulder, 0)
	local offset = target - shoulder
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local forward = if flat.Magnitude > 0.05 then flat.Unit else baseCf.LookVector
	local horizontal = flat.Magnitude
	local vertical = offset.Y
	local reach = math.clamp(math.sqrt(horizontal * horizontal + vertical * vertical), 0.6, L.Lower + L.Upper - 0.05)
	local aim = math.atan2(vertical, horizontal)
	local cosShoulder = math.clamp((L.Lower ^ 2 + reach ^ 2 - L.Upper ^ 2) / (2 * L.Lower * reach), -1, 1)
	local cosElbow = math.clamp((L.Lower ^ 2 + L.Upper ^ 2 - reach ^ 2) / (2 * L.Lower * L.Upper), -1, 1)
	local pitch1 = aim + math.acos(cosShoulder)
	local pitch2 = pitch1 - (math.pi - math.acos(cosElbow))

	local dir1 = forward * math.cos(pitch1) + Vector3.yAxis * math.sin(pitch1)
	local dir2 = forward * math.cos(pitch2) + Vector3.yAxis * math.sin(pitch2)
	local elbow = shoulder + dir1 * L.Lower
	local tip = elbow + dir2 * L.Upper

	local yaw = CFrame.lookAt(baseCf.Position, baseCf.Position + forward)
	local spread = (open or 0) * 0.35
	local tipCf = lookAlong(tip, dir2)

	local parts = {
		arm:FindFirstChild("Base"),
		arm:FindFirstChild("Turret"),
		arm:FindFirstChild("Lower"),
		arm:FindFirstChild("Elbow"),
		arm:FindFirstChild("Upper"),
		arm:FindFirstChild("ClawA"),
		arm:FindFirstChild("ClawB"),
		arm:FindFirstChild("Tip"),
	}
	local cframes = {
		CFrame.new(baseCf.Position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		CFrame.new(baseCf.Position + Vector3.new(0, 1.1, 0)) * yaw.Rotation * CFrame.Angles(0, 0, math.pi / 2),
		lookAlong((shoulder + elbow) / 2, dir1),
		CFrame.new(elbow),
		lookAlong((elbow + tip) / 2, dir2),
		tipCf * CFrame.new(-0.18 - spread, 0, -0.2) * CFrame.Angles(0, -spread, 0),
		tipCf * CFrame.new(0.18 + spread, 0, -0.2) * CFrame.Angles(0, spread, 0),
		tipCf * CFrame.new(0, 0, -0.45),
	}
	local validParts, validFrames = {}, {}
	for i = 1, #cframes do
		if parts[i] then
			table.insert(validParts, parts[i])
			table.insert(validFrames, cframes[i])
		end
	end
	workspace:BulkMoveTo(validParts, validFrames, Enum.BulkMoveMode.FireCFrameChanged)
	return tipCf * CFrame.new(0, 0, -0.5)
end

return RobotModel
