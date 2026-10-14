-- Procedural pet bodies for capsule reveals (Parts only). Root at the feet,
-- facing -Z. Drop a mesh model into ReplicatedStorage.Assets.Pets.<PetId>
-- to override.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Definitions = script.Parent.Parent.Definitions
local Pets = require(Definitions.Pets)
local Builder = require(script.Parent.Parent.Util.Builder)

local PetModel = {}

local BLACK = Color3.fromRGB(20, 20, 26)
local WHITE = Color3.new(1, 1, 1)

local function kit(model: Model)
	local function add(props: { [string]: any }): BasePart
		local part = Builder.Part(props)
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.Parent = model
		return part
	end
	local function ball(pos: Vector3, d: number, color: Color3, material: Enum.Material?, transparency: number?): BasePart
		return add({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * d,
			CFrame = CFrame.new(pos),
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			Transparency = transparency or 0,
		})
	end
	local function block(pos: Vector3, size: Vector3, color: Color3, rot: CFrame?, material: Enum.Material?): BasePart
		return add({
			Size = size,
			CFrame = CFrame.new(pos) * (rot or CFrame.identity),
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
		})
	end
	local function wedge(cf: CFrame, size: Vector3, color: Color3): BasePart
		return add({ ClassName = "WedgePart", Size = size, CFrame = cf, Color = color })
	end
	local function pipe(a: Vector3, b: Vector3, r: number, color: Color3, material: Enum.Material?): BasePart
		local part = Builder.Pipe(a, b, r, { Color = color, Material = material or Enum.Material.SmoothPlastic })
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.Parent = model
		return part
	end
	local function eyes(y: number, z: number, spread: number, size: number?)
		local d = size or 0.26
		for _, x in { -spread, spread } do
			ball(Vector3.new(x, y, z), d, BLACK)
			ball(Vector3.new(x + d * 0.15, y + d * 0.2, z - d * 0.35), d * 0.35, WHITE, Enum.Material.Neon)
		end
	end
	return { add = add, ball = ball, block = block, wedge = wedge, pipe = pipe, eyes = eyes }
end

local Bodies = {}

function Bodies.Bunny(k, look)
	k.ball(Vector3.new(0, 0.85, 0.15), 1.6, look.Color)
	k.ball(Vector3.new(0, 1.75, -0.35), 1.25, look.Color)
	for _, x in { -0.3, 0.3 } do
		k.block(Vector3.new(x, 2.65, -0.25), Vector3.new(0.32, 1.0, 0.18), look.Color, CFrame.Angles(0, 0, x * -0.4))
		k.block(Vector3.new(x, 2.65, -0.34), Vector3.new(0.18, 0.75, 0.05), look.Accent, CFrame.Angles(0, 0, x * -0.4))
	end
	k.ball(Vector3.new(0, 1.6, -0.98), 0.22, look.Accent)
	k.ball(Vector3.new(0, 0.95, 1.0), 0.5, WHITE)
	for _, x in { -0.45, 0.45 } do
		k.ball(Vector3.new(x, 0.18, -0.35), 0.45, look.Color)
	end
	k.eyes(1.9, -0.92, 0.27)
end

function Bodies.Cat(k, look)
	k.ball(Vector3.new(0, 0.8, 0.2), 1.5, look.Color)
	k.ball(Vector3.new(0, 1.7, -0.3), 1.3, look.Color)
	for _, x in { -0.38, 0.38 } do
		k.wedge(CFrame.new(x, 2.45, -0.3) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(0.2, 0.55, 0.45), look.Color)
	end
	k.pipe(Vector3.new(0, 0.9, 0.9), Vector3.new(0, 1.9, 1.35), 0.14, look.Accent)
	k.ball(Vector3.new(0, 1.55, -0.96), 0.18, look.Accent)
	k.eyes(1.85, -0.9, 0.3)
	for _, x in { -0.4, 0.4 } do
		k.ball(Vector3.new(x, 0.15, -0.3), 0.4, look.Color)
	end
end

function Bodies.Blob(k, look)
	k.ball(Vector3.new(0, 0.95, 0), 1.9, look.Color, Enum.Material.Glass, 0.25)
	k.ball(Vector3.new(0, 0.95, 0), 1.0, look.Glow or look.Accent, Enum.Material.Neon)
	k.ball(Vector3.new(0, 1.95, 0.1), 0.7, look.Color, Enum.Material.Glass, 0.25)
	k.ball(Vector3.new(0.75, 0.3, -0.3), 0.6, look.Color, Enum.Material.Glass, 0.25)
	k.ball(Vector3.new(-0.75, 0.3, -0.3), 0.6, look.Color, Enum.Material.Glass, 0.25)
	k.eyes(1.25, -0.88, 0.32, 0.3)
end

function Bodies.Bot(k, look)
	k.block(Vector3.new(0, 0.95, 0), Vector3.new(1.4, 1.2, 1.2), look.Color, nil, Enum.Material.Metal)
	k.block(Vector3.new(0, 1.95, -0.05), Vector3.new(1.2, 0.85, 1.0), look.Color, nil, Enum.Material.Metal)
	k.block(Vector3.new(0, 1.98, -0.56), Vector3.new(0.95, 0.32, 0.05), look.Glow or look.Accent, nil, Enum.Material.Neon)
	k.pipe(Vector3.new(0, 2.35, 0), Vector3.new(0, 2.9, 0.1), 0.05, look.Accent)
	k.ball(Vector3.new(0, 2.95, 0.12), 0.22, look.Glow or look.Accent, Enum.Material.Neon)
	k.block(Vector3.new(0, 0.95, -0.61), Vector3.new(0.6, 0.4, 0.05), look.Accent, nil, Enum.Material.Neon)
	for _, x in { -0.55, 0.55 } do
		k.add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.6, 0.6), CFrame = CFrame.new(x, 0.3, 0), Color = BLACK })
		k.block(Vector3.new(x * 1.45, 1.05, 0), Vector3.new(0.22, 0.8, 0.3), look.Accent, CFrame.Angles(0, 0, x * 0.3))
	end
end

function Bodies.Scorpion(k, look)
	for i = 0, 2 do
		k.ball(Vector3.new(0, 0.55, -0.4 + i * 0.6), 0.95 - i * 0.1, look.Color)
	end
	k.pipe(Vector3.new(0, 0.7, 1.1), Vector3.new(0, 1.5, 1.4), 0.18, look.Color)
	k.pipe(Vector3.new(0, 1.5, 1.4), Vector3.new(0, 2.1, 1.0), 0.16, look.Color)
	k.ball(Vector3.new(0, 2.1, 0.8), 0.3, look.Accent, Enum.Material.Neon)
	for _, x in { -1, 1 } do
		k.pipe(Vector3.new(x * 0.35, 0.55, -0.7), Vector3.new(x * 0.7, 0.6, -1.2), 0.1, look.Color)
		k.block(Vector3.new(x * 0.75, 0.6, -1.4), Vector3.new(0.35, 0.25, 0.45), look.Accent)
		for j = 0, 2 do
			k.pipe(Vector3.new(x * 0.35, 0.5, -0.2 + j * 0.45), Vector3.new(x * 0.85, 0.1, -0.3 + j * 0.45), 0.06, look.Accent)
		end
	end
	k.eyes(0.85, -0.82, 0.18, 0.18)
end

function Bodies.Ghost(k, look)
	k.ball(Vector3.new(0, 1.55, 0), 1.7, look.Color, Enum.Material.SmoothPlastic, 0.15)
	k.add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.0, 1.7, 1.7), CFrame = CFrame.new(0, 0.95, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = look.Color, Transparency = 0.15 })
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2
		k.ball(Vector3.new(math.cos(a) * 0.55, 0.4, math.sin(a) * 0.55), 0.6, look.Color, Enum.Material.SmoothPlastic, 0.15)
	end
	k.ball(Vector3.new(0, 1.2, -0.82), 0.35, BLACK)
	k.eyes(1.75, -0.78, 0.3, 0.3)
	k.ball(Vector3.new(0, 1.55, 0), 0.7, look.Glow or look.Accent, Enum.Material.Neon, 0.6)
end

function Bodies.Cactus(k, look)
	k.add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.9, 1.15, 1.15), CFrame = CFrame.new(0, 1.0, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = look.Color, Material = Enum.Material.Grass })
	k.ball(Vector3.new(0, 1.95, 0), 1.15, look.Color, Enum.Material.Grass)
	for _, x in { -1, 1 } do
		k.pipe(Vector3.new(x * 0.5, 1.1, 0), Vector3.new(x * 1.0, 1.1, 0), 0.22, look.Color, Enum.Material.Grass)
		k.pipe(Vector3.new(x * 1.0, 1.0, 0), Vector3.new(x * 1.0, 1.65, 0), 0.22, look.Color, Enum.Material.Grass)
	end
	k.ball(Vector3.new(0.2, 2.55, 0), 0.45, look.Accent)
	k.block(Vector3.new(0, 0.12, 0), Vector3.new(1.4, 0.25, 1.4), Color3.fromRGB(190, 110, 70))
	k.eyes(1.75, -0.56, 0.22, 0.22)
end

function Bodies.Dragon(k, look)
	k.ball(Vector3.new(0, 0.95, 0.2), 1.5, look.Color)
	k.ball(Vector3.new(0, 0.85, -0.2), 0.9, look.Glow or look.Accent, Enum.Material.Neon, 0.2)
	k.ball(Vector3.new(0, 1.85, -0.45), 1.05, look.Color)
	k.block(Vector3.new(0, 1.7, -1.05), Vector3.new(0.65, 0.45, 0.6), look.Color)
	for _, x in { -0.28, 0.28 } do
		k.wedge(CFrame.new(x, 2.45, -0.3) * CFrame.Angles(math.rad(-30), 0, 0), Vector3.new(0.18, 0.5, 0.45), look.Accent)
	end
	local wl = k.wedge(CFrame.new(-0.95, 1.5, 0.3) * CFrame.Angles(0, 0, math.rad(30)) * CFrame.Angles(0, math.pi, 0), Vector3.new(0.1, 0.9, 1.2), look.Accent)
	wl.Name = "WingL"
	local wr = k.wedge(CFrame.new(0.95, 1.5, 0.3) * CFrame.Angles(0, 0, math.rad(-30)) * CFrame.Angles(0, math.pi, 0), Vector3.new(0.1, 0.9, 1.2), look.Accent)
	wr.Name = "WingR"
	k.pipe(Vector3.new(0, 0.7, 0.9), Vector3.new(0, 0.9, 1.6), 0.2, look.Color)
	k.wedge(CFrame.new(0, 1.05, 1.85) * CFrame.Angles(math.rad(20), 0, 0), Vector3.new(0.1, 0.4, 0.4), look.Glow or look.Accent)
	k.eyes(2.0, -0.92, 0.25, 0.22)
	for _, x in { -0.4, 0.4 } do
		k.ball(Vector3.new(x, 0.18, -0.2), 0.42, look.Color)
	end
end

function PetModel.Build(petId: string): Model
	local pet = Pets.Get(petId)
	assert(pet, "Unknown pet " .. tostring(petId))

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Pets")
	local template = folder and folder:FindFirstChild(pet.Id)
	if template and template:IsA("Model") and template.PrimaryPart then
		local clone = template:Clone()
		clone:SetAttribute("PetId", pet.Id)
		return clone
	end

	local model = Instance.new("Model")
	model.Name = "Pet_" .. pet.Id
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
	local body = Bodies[pet.Look.Type] or Bodies.Blob
	body(kit(model), pet.Look)
	model:SetAttribute("PetId", pet.Id)
	return model
end

return PetModel
