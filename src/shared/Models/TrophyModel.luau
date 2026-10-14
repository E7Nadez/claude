-- Boss trophies for the Trophy Vault, built from Parts. Root at the base.
-- Animation hints read by the client:
--   Model attribute  SpinAll (rad/s)        slow turntable spin
--   Part  attribute  Bob (studs)            floats up and down
--   Part  attribute  Pulse = true           glow pulse
--   Part  attribute  Wing = -1 | 1, Hinge   wing flap around Hinge (root space)
--   Part  attribute  Jaw = true, Hinge      jaw chomp around Hinge
--   Attachment "Mouth"                      fire breath origin

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builder = require(script.Parent.Parent.Util.Builder)

local TrophyModel = {}

local GOLD = Color3.fromRGB(255, 200, 50)
local RUST = Color3.fromRGB(150, 70, 40)
local BONE = Color3.fromRGB(236, 228, 210)

local function kit(model: Model)
	local function add(props: { [string]: any }): BasePart
		local part = Builder.Part(props)
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Parent = model
		return part
	end
	local k = {}
	function k.ball(pos: Vector3, d: number, color: Color3, material: Enum.Material?): BasePart
		return add({ Shape = Enum.PartType.Ball, Size = Vector3.one * d, CFrame = CFrame.new(pos), Color = color, Material = material or Enum.Material.SmoothPlastic })
	end
	function k.block(cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): BasePart
		return add({ Size = size, CFrame = cf, Color = color, Material = material or Enum.Material.SmoothPlastic })
	end
	function k.wedge(cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): BasePart
		return add({ ClassName = "WedgePart", Size = size, CFrame = cf, Color = color, Material = material or Enum.Material.SmoothPlastic })
	end
	function k.cyl(cf: CFrame, length: number, d: number, color: Color3, material: Enum.Material?): BasePart
		return add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(length, d, d), CFrame = cf, Color = color, Material = material or Enum.Material.SmoothPlastic })
	end
	function k.pipe(a: Vector3, b: Vector3, r: number, color: Color3, material: Enum.Material?): BasePart
		local part = Builder.Pipe(a, b, r, { Color = color, Material = material or Enum.Material.SmoothPlastic })
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Parent = model
		return part
	end
	function k.ring(cf: CFrame, radius: number, thickness: number, depth: number, segments: number, color: Color3, material: Enum.Material?): { BasePart }
		local parts = Builder.Ring(cf, radius, thickness, depth, segments, { Color = color, Material = material or Enum.Material.Metal })
		for _, part in parts do
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Parent = model
		end
		return parts
	end
	return k
end

local UP = CFrame.Angles(0, 0, math.pi / 2)

local Builders = {}

function Builders.MiniTrashKing(k)
	local bag = k.ball(Vector3.new(0, 1.2, 0), 2.1, Color3.fromRGB(28, 30, 36))
	bag.Material = Enum.Material.Plastic
	k.cyl(CFrame.new(0, 2.3, 0) * UP, 0.3, 0.5, Color3.fromRGB(28, 30, 36))
	for _, x in { -0.4, 0.4 } do
		k.ball(Vector3.new(x, 1.5, -0.95), 0.3, Color3.fromRGB(150, 255, 80), Enum.Material.Neon)
	end
	local crown = {}
	table.insert(crown, k.cyl(CFrame.new(0, 2.55, 0) * UP, 0.3, 1.2, GOLD, Enum.Material.Metal))
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		table.insert(crown, k.wedge(CFrame.new(math.cos(a) * 0.5, 2.95, math.sin(a) * 0.5) * CFrame.Angles(0, -a + math.pi / 2, 0), Vector3.new(0.15, 0.5, 0.35), GOLD, Enum.Material.Metal))
	end
	for _, part in crown do
		part:SetAttribute("Bob", 0.12)
	end
	k.wedge(CFrame.new(0, 1.0, 0.95) * CFrame.Angles(0, math.pi, 0), Vector3.new(1.8, 1.6, 0.4), Color3.fromRGB(170, 30, 40))
	k.pipe(Vector3.new(1.1, 0.2, -0.3), Vector3.new(1.3, 2.4, -0.4), 0.08, Color3.fromRGB(120, 80, 40))
	k.cyl(CFrame.new(1.32, 2.55, -0.4) * UP, 0.4, 0.6, Color3.fromRGB(200, 40, 40))
end

function Builders.GoldenPlunger(k)
	k.cyl(CFrame.new(0, 0.5, 0) * UP, 1.0, 1.4, Color3.fromRGB(40, 40, 50), Enum.Material.Metal)
	k.pipe(Vector3.new(0, 1.0, 0), Vector3.new(0, 3.6, 0), 0.14, GOLD, Enum.Material.Metal)
	k.cyl(CFrame.new(0, 3.75, 0) * UP, 0.5, 1.0, GOLD, Enum.Material.Metal)
	k.cyl(CFrame.new(0, 4.05, 0) * UP, 0.25, 1.3, GOLD, Enum.Material.Metal)
	local gem = k.ball(Vector3.new(0, 4.35, 0), 0.4, Color3.fromRGB(255, 80, 120), Enum.Material.Neon)
	gem:SetAttribute("Pulse", true)
end

function Builders.KingsCrown(k)
	k.block(CFrame.new(0, 0.6, 0), Vector3.new(2.2, 1.0, 2.2), Color3.fromRGB(150, 20, 40), Enum.Material.Fabric)
	local parts = k.ring(CFrame.new(0, 1.55, 0) * CFrame.Angles(math.pi / 2, 0, 0), 0.9, 0.18, 0.6, 16, GOLD, Enum.Material.Metal)
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2
		table.insert(parts, k.wedge(CFrame.new(math.cos(a) * 0.9, 2.15, math.sin(a) * 0.9) * CFrame.Angles(0, -a + math.pi / 2, 0), Vector3.new(0.12, 0.7, 0.4), GOLD, Enum.Material.Metal))
		local gem = k.ball(Vector3.new(math.cos(a) * 0.98, 1.55, math.sin(a) * 0.98), 0.22, Color3.fromHSV(i / 7, 0.8, 1), Enum.Material.Neon)
		gem:SetAttribute("Pulse", true)
		table.insert(parts, gem)
	end
	for _, part in parts do
		part:SetAttribute("Bob", 0.15)
	end
end

function Builders.DragonHeart(k)
	k.cyl(CFrame.new(0, 0.3, 0) * UP, 0.6, 2.2, Color3.fromRGB(60, 50, 44), Enum.Material.Metal)
	local core = k.ball(Vector3.new(0, 1.9, 0), 1.4, Color3.fromRGB(255, 120, 30), Enum.Material.Neon)
	core:SetAttribute("Pulse", true)
	core:SetAttribute("Bob", 0.1)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		k.pipe(Vector3.new(math.cos(a) * 1.0, 0.6, math.sin(a) * 1.0), Vector3.new(math.cos(a) * 1.0, 3.2, math.sin(a) * 1.0), 0.09, RUST, Enum.Material.CorrodedMetal)
	end
	k.ring(CFrame.new(0, 3.2, 0) * CFrame.Angles(math.pi / 2, 0, 0), 1.0, 0.15, 0.15, 12, RUST, Enum.Material.CorrodedMetal)
	k.ring(CFrame.new(0, 0.7, 0) * CFrame.Angles(math.pi / 2, 0, 0), 1.0, 0.15, 0.15, 12, RUST, Enum.Material.CorrodedMetal)
end

function Builders.MiniRustDragon(k, model: Model)
	k.cyl(CFrame.new(0, 0.25, 0) * UP, 0.5, 2.6, Color3.fromRGB(50, 44, 40), Enum.Material.Metal)
	local body = k.ball(Vector3.new(0, 1.5, 0.3), 1.5, RUST, Enum.Material.CorrodedMetal)
	body:SetAttribute("Bob", 0.08)
	k.ball(Vector3.new(0, 1.35, 0.0), 0.8, Color3.fromRGB(255, 130, 40), Enum.Material.Neon):SetAttribute("Pulse", true)
	k.pipe(Vector3.new(0, 1.9, -0.2), Vector3.new(0, 2.5, -0.7), 0.28, RUST, Enum.Material.CorrodedMetal)
	local head = k.block(CFrame.new(0, 2.65, -0.95), Vector3.new(0.75, 0.6, 0.9), RUST, Enum.Material.CorrodedMetal)
	head.Name = "Head"
	local jaw = k.block(CFrame.new(0, 2.3, -1.2), Vector3.new(0.6, 0.18, 0.7), Color3.fromRGB(90, 50, 30), Enum.Material.Metal)
	jaw:SetAttribute("Jaw", true)
	jaw:SetAttribute("Hinge", Vector3.new(0, 2.35, -0.9))
	for _, x in { -0.22, 0.22 } do
		k.ball(Vector3.new(x, 2.8, -1.38), 0.16, Color3.fromRGB(255, 200, 60), Enum.Material.Neon)
		k.wedge(CFrame.new(x, 3.1, -0.7) * CFrame.Angles(math.rad(-40), 0, 0), Vector3.new(0.1, 0.4, 0.35), GOLD, Enum.Material.Metal)
	end
	for _, side in { -1, 1 } do
		local wing = k.wedge(
			CFrame.new(side * 1.05, 2.1, 0.4) * CFrame.Angles(0, 0, side * math.rad(-25)) * CFrame.Angles(0, math.pi, 0),
			Vector3.new(0.1, 1.2, 1.5),
			Color3.fromRGB(200, 120, 60),
			Enum.Material.Metal
		)
		wing.Name = if side < 0 then "WingL" else "WingR"
		wing:SetAttribute("Wing", side)
		wing:SetAttribute("Hinge", Vector3.new(side * 0.5, 1.9, 0.4))
	end
	k.pipe(Vector3.new(0, 1.2, 1.0), Vector3.new(0, 1.0, 1.8), 0.2, RUST, Enum.Material.CorrodedMetal)
	k.pipe(Vector3.new(0, 1.0, 1.8), Vector3.new(0, 1.5, 2.3), 0.14, RUST, Enum.Material.CorrodedMetal)
	for _, x in { -0.45, 0.45 } do
		k.pipe(Vector3.new(x, 1.1, 0.3), Vector3.new(x * 1.2, 0.5, 0.2), 0.12, RUST, Enum.Material.CorrodedMetal)
	end
	local mouth = Instance.new("Attachment")
	mouth.Name = "Mouth"
	mouth.CFrame = CFrame.lookAt(Vector3.new(0, 2.5, -1.45), Vector3.new(0, 2.3, -3))
	mouth.Parent = model.PrimaryPart
end

function Builders.WyrmSkull(k)
	k.block(CFrame.new(0, 0.3, 0), Vector3.new(2.6, 0.6, 2.6), Color3.fromRGB(50, 40, 34), Enum.Material.Slate)
	local skull = k.ball(Vector3.new(0, 1.7, 0.3), 1.8, BONE)
	skull:SetAttribute("Bob", 0.05)
	k.block(CFrame.new(0, 1.65, -0.9), Vector3.new(1.1, 0.7, 1.4), BONE)
	local jaw = k.block(CFrame.new(0, 1.05, -0.8), Vector3.new(1.0, 0.25, 1.3), Color3.fromRGB(210, 200, 180))
	jaw:SetAttribute("Jaw", true)
	jaw:SetAttribute("Hinge", Vector3.new(0, 1.15, -0.2))
	for _, x in { -0.35, 0.35 } do
		k.ball(Vector3.new(x, 1.95, -0.45), 0.35, Color3.fromRGB(255, 110, 30), Enum.Material.Neon):SetAttribute("Pulse", true)
	end
	for _, side in { -1, 1 } do
		k.pipe(Vector3.new(side * 0.6, 2.3, 0.4), Vector3.new(side * 1.3, 2.9, 0.9), 0.16, BONE)
		k.pipe(Vector3.new(side * 1.3, 2.9, 0.9), Vector3.new(side * 1.5, 3.5, 1.6), 0.1, BONE)
	end
	for i = 0, 3 do
		k.wedge(CFrame.new(-0.36 + i * 0.24, 1.25, -1.55) * CFrame.Angles(math.pi, 0, 0), Vector3.new(0.12, 0.25, 0.12), Color3.new(1, 1, 1))
	end
end

TrophyModel.Spin = {
	GoldenPlunger = 0.8,
	KingsCrown = 0.5,
	DragonHeart = 0.4,
}

function TrophyModel.Build(modelName: string): Model
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Trophies")
	local template = folder and folder:FindFirstChild(modelName)
	if template and template:IsA("Model") and template.PrimaryPart then
		return template:Clone()
	end

	local model = Instance.new("Model")
	model.Name = "Trophy_" .. modelName
	local root = Builder.Part({
		Name = "Root",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = CFrame.new(),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = model,
	})
	model.PrimaryPart = root
	local build = Builders[modelName] or Builders.GoldenPlunger
	build(kit(model), model)
	if TrophyModel.Spin[modelName] then
		model:SetAttribute("SpinAll", TrophyModel.Spin[modelName])
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			part:SetAttribute("Home", root.CFrame:ToObjectSpace(part.CFrame))
		end
	end
	return model
end

return TrophyModel
