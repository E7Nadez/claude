-- Builds vacuum models from regular Parts (no EditableMeshes, so any number
-- can exist at once). If ReplicatedStorage.Assets.Vacuums.<ModelName> exists
-- (an imported mesh model) it is cloned instead.
--
-- Every part gets attributes used by the client animations:
--   Role     Body | Accent | Metal | Dark | Glow | Glass (skins recolor by role)
--   Home     CFrame relative to the Root part (assembled position)
--   Explode  Vector3 offset (Root space) for the exploded view
--   Spin     optional spin speed (rad/s) around SpinAxis through SpinCenter
--
-- The nozzle points along the model's LookVector (-Z of the Root).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Definitions = script.Parent.Parent.Definitions
local Vacuums = require(Definitions.Vacuums)
local Cosmetics = require(Definitions.Cosmetics)
local Builder = require(script.Parent.Parent.Util.Builder)

local VacuumModel = {}

local RARITY_SCALE = {
	Common = 1,
	Uncommon = 1.05,
	Rare = 1.1,
	Epic = 1.15,
	Legendary = 1.2,
	Mythic = 1.3,
}

local DARK = Color3.fromRGB(34, 36, 44)
local METAL = Color3.fromRGB(176, 182, 194)

export type Look = Vacuums.Look

local function roleProps(role: string, look: Look): { [string]: any }
	local bodyMaterial = look.Material or Enum.Material.SmoothPlastic
	if role == "Body" then
		return {
			Color = look.Body,
			Material = bodyMaterial,
			Transparency = if bodyMaterial == Enum.Material.Glass then 0.3 else 0,
			Reflectance = if bodyMaterial == Enum.Material.Metal then 0.12 else 0,
		}
	elseif role == "Accent" then
		return { Color = look.Accent, Material = Enum.Material.SmoothPlastic, Transparency = 0, Reflectance = 0 }
	elseif role == "Metal" then
		return { Color = look.Metal or METAL, Material = Enum.Material.Metal, Transparency = 0, Reflectance = 0.18 }
	elseif role == "Dark" then
		return { Color = DARK, Material = Enum.Material.SmoothPlastic, Transparency = 0, Reflectance = 0 }
	elseif role == "Glow" then
		return { Color = look.Glow, Material = Enum.Material.Neon, Transparency = 0, Reflectance = 0 }
	elseif role == "Glass" then
		return {
			Color = look.Glow:Lerp(Color3.new(1, 1, 1), 0.55),
			Material = Enum.Material.Glass,
			Transparency = 0.55,
			Reflectance = 0.1,
		}
	end
	return {}
end

type Ctx = {
	model: Model,
	root: BasePart,
	look: Look,
	add: (role: string, props: { [string]: any }) -> BasePart,
	pipe: (role: string, a: Vector3, b: Vector3, radius: number) -> BasePart,
	ring: (role: string, cf: CFrame, radius: number, thickness: number, depth: number, segments: number) -> { BasePart },
}

local function newContext(model: Model, root: BasePart, look: Look): Ctx
	local ctx = {} :: Ctx
	ctx.model = model
	ctx.root = root
	ctx.look = look

	local function finish(part: BasePart, role: string)
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part:SetAttribute("Role", role)
		part.Parent = model
	end

	function ctx.add(role: string, props: { [string]: any }): BasePart
		local p = roleProps(role, look)
		for k, v in props do
			p[k] = v
		end
		local part = Builder.Part(p)
		finish(part, role)
		return part
	end

	function ctx.pipe(role: string, a: Vector3, b: Vector3, radius: number): BasePart
		local part = Builder.Pipe(a, b, radius, roleProps(role, look))
		finish(part, role)
		return part
	end

	function ctx.ring(role: string, cf: CFrame, radius: number, thickness: number, depth: number, segments: number): { BasePart }
		local parts = Builder.Ring(cf, radius, thickness, depth, segments, roleProps(role, look))
		for _, part in parts do
			finish(part, role)
		end
		return parts
	end

	return ctx
end

local CYL_Z = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis along Z
local CYL_Y = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis along Y

local function cylZ(ctx: Ctx, role: string, pos: Vector3, length: number, diameter: number, extra: { [string]: any }?): BasePart
	local props: { [string]: any } = {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		CFrame = CFrame.new(pos) * CYL_Z,
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return ctx.add(role, props)
end

local function cylY(ctx: Ctx, role: string, pos: Vector3, length: number, diameter: number, extra: { [string]: any }?): BasePart
	local props: { [string]: any } = {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		CFrame = CFrame.new(pos) * CYL_Y,
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return ctx.add(role, props)
end

local function cylX(ctx: Ctx, role: string, pos: Vector3, length: number, diameter: number): BasePart
	return ctx.add(role, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		CFrame = CFrame.new(pos),
	})
end

local function ball(ctx: Ctx, role: string, pos: Vector3, diameter: number): BasePart
	return ctx.add(role, { Shape = Enum.PartType.Ball, Size = Vector3.one * diameter, CFrame = CFrame.new(pos) })
end

local function block(ctx: Ctx, role: string, pos: Vector3, size: Vector3, rot: CFrame?): BasePart
	return ctx.add(role, { Size = size, CFrame = CFrame.new(pos) * (rot or CFrame.identity) })
end

local function wedge(ctx: Ctx, role: string, cf: CFrame, size: Vector3): BasePart
	return ctx.add(role, { ClassName = "WedgePart", Size = size, CFrame = cf })
end

local function fan(ctx: Ctx, center: Vector3, radius: number, blades: number, speed: number)
	local hub = ball(ctx, "Metal", center, radius * 0.45)
	hub:SetAttribute("Spin", speed)
	hub:SetAttribute("SpinAxis", Vector3.zAxis)
	hub:SetAttribute("SpinCenter", center)
	for i = 1, blades do
		local angle = (i - 1) / blades * math.pi * 2
		local blade = block(
			ctx,
			"Accent",
			center,
			Vector3.new(radius * 0.32, radius * 0.95, 0.08),
			CFrame.Angles(0, 0, angle) * CFrame.new(0, radius * 0.5, 0) * CFrame.Angles(0, math.rad(25), 0)
		)
		blade:SetAttribute("Spin", speed)
		blade:SetAttribute("SpinAxis", Vector3.zAxis)
		blade:SetAttribute("SpinCenter", center)
	end
end

local Shapes = {}

function Shapes.Canister(ctx: Ctx)
	cylZ(ctx, "Body", Vector3.new(0, 1.25, 0.6), 3, 1.9)
	cylZ(ctx, "Accent", Vector3.new(0, 1.25, 2.15), 0.35, 2.0)
	cylZ(ctx, "Metal", Vector3.new(0, 1.25, -0.95), 0.3, 1.7)
	cylZ(ctx, "Glow", Vector3.new(0, 1.25, 0.2), 0.15, 2.04)
	cylX(ctx, "Dark", Vector3.new(1.0, 0.5, 1.4), 0.4, 1.0)
	cylX(ctx, "Dark", Vector3.new(-1.0, 0.5, 1.4), 0.4, 1.0)
	ball(ctx, "Dark", Vector3.new(0, 0.3, -0.5), 0.6)
	block(ctx, "Accent", Vector3.new(0, 2.35, 0.6), Vector3.new(0.3, 0.25, 1.4))
	block(ctx, "Accent", Vector3.new(0, 2.2, 0.0), Vector3.new(0.3, 0.4, 0.25))
	block(ctx, "Accent", Vector3.new(0, 2.2, 1.2), Vector3.new(0.3, 0.4, 0.25))
	ctx.pipe("Dark", Vector3.new(0, 1.3, -1.1), Vector3.new(0, 1.95, -1.7), 0.22)
	ctx.pipe("Dark", Vector3.new(0, 1.95, -1.7), Vector3.new(0, 2.35, -2.3), 0.22)
	ctx.pipe("Metal", Vector3.new(0, 2.35, -2.3), Vector3.new(0, 0.45, -3.6), 0.14)
	block(ctx, "Accent", Vector3.new(0, 0.24, -3.85), Vector3.new(2.2, 0.36, 0.7))
	block(ctx, "Glow", Vector3.new(0, 0.2, -4.22), Vector3.new(2.0, 0.08, 0.06))
end

function Shapes.Upright(ctx: Ctx)
	block(ctx, "Accent", Vector3.new(0, 0.35, -0.5), Vector3.new(2.4, 0.55, 1.4))
	block(ctx, "Glow", Vector3.new(0, 0.18, -1.22), Vector3.new(2.2, 0.1, 0.06))
	cylX(ctx, "Dark", Vector3.new(1.05, 0.35, 0.25), 0.3, 0.7)
	cylX(ctx, "Dark", Vector3.new(-1.05, 0.35, 0.25), 0.3, 0.7)
	block(ctx, "Body", Vector3.new(0, 1.85, 0.35), Vector3.new(1.3, 2.4, 1.0))
	ball(ctx, "Body", Vector3.new(0, 0.9, 0.35), 1.15)
	cylY(ctx, "Glass", Vector3.new(0, 1.95, -0.3), 1.6, 1.0)
	cylY(ctx, "Glow", Vector3.new(0, 1.95, -0.3), 1.2, 0.45)
	cylY(ctx, "Metal", Vector3.new(0, 2.85, -0.3), 0.2, 1.05)
	ctx.pipe("Metal", Vector3.new(0, 3.0, 0.45), Vector3.new(0, 4.8, 0.75), 0.12)
	block(ctx, "Dark", Vector3.new(0, 4.9, 0.78), Vector3.new(0.9, 0.3, 0.3))
	block(ctx, "Glow", Vector3.new(0, 2.6, 0.86), Vector3.new(0.5, 0.5, 0.05))
end

function Shapes.Backpack(ctx: Ctx)
	block(ctx, "Dark", Vector3.new(0, 0.25, 0.6), Vector3.new(2.6, 0.5, 2.6))
	cylY(ctx, "Body", Vector3.new(0, 2.0, 0.6), 3.0, 2.2)
	cylY(ctx, "Glow", Vector3.new(0, 2.3, 0.6), 0.3, 2.28)
	ball(ctx, "Metal", Vector3.new(0, 3.55, 0.6), 2.2)
	cylY(ctx, "Accent", Vector3.new(0, 4.6, 0.6), 0.5, 0.6)
	ctx.pipe("Accent", Vector3.new(1.25, 0.8, 0.6), Vector3.new(1.25, 3.4, 0.6), 0.2)
	ctx.pipe("Accent", Vector3.new(-1.25, 0.8, 0.6), Vector3.new(-1.25, 3.4, 0.6), 0.2)
	cylZ(ctx, "Glow", Vector3.new(0, 2.8, -0.52), 0.1, 0.6)
	ctx.pipe("Dark", Vector3.new(0, 1.5, -0.4), Vector3.new(0, 1.9, -1.4), 0.3)
	cylZ(ctx, "Accent", Vector3.new(0, 1.9, -1.9), 0.8, 0.8)
	cylZ(ctx, "Accent", Vector3.new(0, 1.9, -2.5), 0.6, 1.2)
	cylZ(ctx, "Accent", Vector3.new(0, 1.9, -3.0), 0.5, 1.7)
	cylZ(ctx, "Glow", Vector3.new(0, 1.9, -3.28), 0.08, 1.75)
end

function Shapes.Turbine(ctx: Ctx)
	block(ctx, "Dark", Vector3.new(0, 0.2, 0.3), Vector3.new(2.4, 0.4, 3.0))
	ctx.pipe("Metal", Vector3.new(0.8, 0.4, 0.3), Vector3.new(0.6, 1.4, 0.3), 0.15)
	ctx.pipe("Metal", Vector3.new(-0.8, 0.4, 0.3), Vector3.new(-0.6, 1.4, 0.3), 0.15)
	cylZ(ctx, "Body", Vector3.new(0, 2.1, 0.2), 2.8, 2.6)
	ctx.ring("Accent", CFrame.new(0, 2.1, -1.25), 1.35, 0.3, 0.4, 14)
	ctx.ring("Glow", CFrame.new(0, 2.1, -1.5), 1.25, 0.12, 0.12, 14)
	fan(ctx, Vector3.new(0, 2.1, -1.1), 1.15, 7, 14)
	cylZ(ctx, "Metal", Vector3.new(0, 2.1, 1.9), 1.0, 1.7)
	cylZ(ctx, "Glow", Vector3.new(0, 2.1, 2.42), 0.06, 1.3)
	wedge(ctx, "Accent", CFrame.new(1.45, 2.1, 0.6) * CFrame.Angles(0, math.pi, 0), Vector3.new(0.12, 1.0, 1.6))
	wedge(ctx, "Accent", CFrame.new(-1.45, 2.1, 0.6) * CFrame.Angles(0, math.pi, 0), Vector3.new(0.12, 1.0, 1.6))
	wedge(ctx, "Accent", CFrame.new(0, 3.55, 0.6) * CFrame.Angles(0, math.pi, 0), Vector3.new(0.12, 0.9, 1.6))
end

function Shapes.Cannon(ctx: Ctx)
	block(ctx, "Dark", Vector3.new(0, 0.2, 0.6), Vector3.new(2.8, 0.4, 2.8))
	for _, x in { -1, 1 } do
		ctx.pipe("Metal", Vector3.new(x * 1.1, 0.4, 1.3), Vector3.new(x * 0.5, 1.7, 0.6), 0.16)
	end
	ctx.pipe("Metal", Vector3.new(0, 0.4, -0.4), Vector3.new(0, 1.7, 0.4), 0.16)
	ball(ctx, "Glow", Vector3.new(0, 2.3, 0.6), 1.7)
	ctx.ring("Accent", CFrame.new(0, 2.3, 0.6), 1.25, 0.18, 0.25, 16)
	ctx.ring("Accent", CFrame.new(0, 2.3, 0.6) * CFrame.Angles(0, math.rad(60), 0), 1.35, 0.18, 0.25, 16)
	ctx.ring("Accent", CFrame.new(0, 2.3, 0.6) * CFrame.Angles(0, math.rad(-60), 0), 1.45, 0.18, 0.25, 16)
	cylZ(ctx, "Body", Vector3.new(0, 2.3, -0.9), 0.6, 1.4)
	cylZ(ctx, "Body", Vector3.new(0, 2.3, -1.45), 0.6, 1.9)
	cylZ(ctx, "Body", Vector3.new(0, 2.3, -2.0), 0.6, 2.5)
	cylZ(ctx, "Body", Vector3.new(0, 2.3, -2.55), 0.6, 3.1)
	ctx.ring("Glow", CFrame.new(0, 2.3, -2.9), 1.6, 0.16, 0.16, 18)
	fan(ctx, Vector3.new(0, 2.3, -2.3), 1.1, 5, 18)
	cylZ(ctx, "Body", Vector3.new(0, 2.3, 2.1), 1.4, 1.8)
	cylZ(ctx, "Metal", Vector3.new(0, 2.3, 2.9), 0.3, 1.3)
	cylZ(ctx, "Glow", Vector3.new(0, 2.3, 3.07), 0.05, 0.9)
	for _, x in { -1, 1 } do
		wedge(ctx, "Accent", CFrame.new(x * 1.0, 3.1, 2.1) * CFrame.Angles(0, math.pi, 0), Vector3.new(0.12, 0.8, 1.2))
	end
end

function Shapes.Dragon(ctx: Ctx)
	-- Body and belly glow
	cylZ(ctx, "Body", Vector3.new(0, 2.2, 0.8), 3.5, 2.0)
	cylZ(ctx, "Glow", Vector3.new(0, 1.5, 0.8), 2.6, 0.7)
	ball(ctx, "Body", Vector3.new(0, 2.2, 2.55), 2.0)
	-- Legs
	for _, x in { -0.75, 0.75 } do
		for _, z in { -0.2, 1.9 } do
			ctx.pipe("Dark", Vector3.new(x, 1.5, z), Vector3.new(x * 1.2, 0.3, z), 0.25)
			block(ctx, "Accent", Vector3.new(x * 1.2, 0.15, z - 0.15), Vector3.new(0.5, 0.3, 0.7))
		end
	end
	-- Head with intake mouth
	block(ctx, "Body", Vector3.new(0, 2.45, -1.55), Vector3.new(1.8, 1.25, 1.6))
	wedge(ctx, "Accent", CFrame.new(0, 2.85, -2.95) * CFrame.Angles(0, math.pi, 0), Vector3.new(1.6, 0.55, 1.5))
	wedge(ctx, "Accent", CFrame.new(0, 1.85, -2.85) * CFrame.Angles(math.pi, 0, 0), Vector3.new(1.4, 0.45, 1.4))
	ball(ctx, "Glow", Vector3.new(0, 2.35, -2.55), 0.95)
	ball(ctx, "Glow", Vector3.new(0.6, 2.95, -2.1), 0.32)
	ball(ctx, "Glow", Vector3.new(-0.6, 2.95, -2.1), 0.32)
	for _, x in { -1, 1 } do
		wedge(ctx, "Metal", CFrame.new(x * 0.6, 3.4, -1.1) * CFrame.Angles(math.rad(-35), 0, 0), Vector3.new(0.3, 0.9, 0.9))
	end
	-- Spine spikes
	for i = 0, 4 do
		wedge(ctx, "Accent", CFrame.new(0, 3.35, -0.4 + i * 0.75), Vector3.new(0.15, 0.6 - i * 0.05, 0.6))
	end
	-- Wings
	for _, x in { -1, 1 } do
		wedge(ctx, "Accent", CFrame.new(x * 1.3, 3.0, 0.9) * CFrame.Angles(0, 0, x * math.rad(-30)) * CFrame.Angles(0, math.pi, 0), Vector3.new(0.12, 1.4, 2.0))
	end
	-- Tail
	ctx.pipe("Body", Vector3.new(0, 2.3, 3.2), Vector3.new(0, 2.9, 4.2), 0.42)
	ctx.pipe("Body", Vector3.new(0, 2.9, 4.2), Vector3.new(0, 3.7, 4.7), 0.3)
	wedge(ctx, "Glow", CFrame.new(0, 4.05, 4.9) * CFrame.Angles(math.rad(30), 0, 0), Vector3.new(0.15, 0.6, 0.6))
end

local function computeHomes(model: Model, root: BasePart)
	local rootCf = root.CFrame
	local extents = model:GetExtentsSize()
	local center = rootCf.Position + Vector3.new(0, extents.Y * 0.45, 0)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			local home = rootCf:ToObjectSpace(part.CFrame)
			part:SetAttribute("Home", home)
			if part:GetAttribute("Explode") == nil then
				local offset = part.Position - center
				local dir = if offset.Magnitude > 0.05 then offset.Unit else Vector3.yAxis
				dir = (dir + Vector3.new(0, 0.35, 0)).Unit
				local distance = 1.6 + offset.Magnitude * 0.45
				part:SetAttribute("Explode", rootCf:VectorToObjectSpace(dir * distance))
			end
		end
	end
end

-- Build a fresh model. options: { Skin = cosmeticId?, Scale = number? }
function VacuumModel.Build(vacuumId: string, options: { [string]: any }?): Model
	local vacuum = Vacuums.Get(vacuumId) or Vacuums.Get(Vacuums.StarterId)
	assert(vacuum, "No vacuum definitions")
	local opts = options or {}

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Vacuums")
	local template = folder and vacuum.ModelName and folder:FindFirstChild(vacuum.ModelName)
	local model: Model
	local root: BasePart

	if template and template:IsA("Model") and template.PrimaryPart then
		model = template:Clone()
		root = model.PrimaryPart :: BasePart
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				if d:GetAttribute("Role") == nil then
					d:SetAttribute("Role", "Body")
				end
			end
		end
	else
		model = Instance.new("Model")
		root = Builder.Part({
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
		local ctx = newContext(model, root, vacuum.Look)
		local shape = Shapes[vacuum.Look.Shape] or Shapes.Canister
		shape(ctx)
	end

	model.Name = "Vacuum_" .. vacuum.Id
	model:SetAttribute("VacuumId", vacuum.Id)
	model:SetAttribute("Rarity", vacuum.Rarity)

	local scale = (opts.Scale or 1) * (vacuum.Look.Scale or RARITY_SCALE[vacuum.Rarity] or 1)
	if math.abs(scale - 1) > 0.001 then
		model:ScaleTo(scale)
		for _, part in model:GetDescendants() do
			local center = part:GetAttribute("SpinCenter")
			if typeof(center) == "Vector3" then
				part:SetAttribute("SpinCenter", center * scale)
			end
		end
	end
	model:SetAttribute("Scale", scale)

	computeHomes(model, root)

	if opts.Skin then
		VacuumModel.ApplySkin(model, opts.Skin)
	end
	return model
end

-- Instantly recolor a model with a skin (or back to its own look with nil).
function VacuumModel.ApplySkin(model: Model, skinId: string?)
	local vacuum = Vacuums.Get(model:GetAttribute("VacuumId") :: string?)
	if not vacuum then
		return
	end
	local look = VacuumModel.SkinnedLook(vacuum.Look, skinId)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local role = part:GetAttribute("Role")
			if role then
				local props = roleProps(role, look)
				for k, v in props do
					(part :: any)[k] = v
				end
			end
		end
	end
end

function VacuumModel.SkinnedLook(base: Look, skinId: string?): Look
	local skin = Cosmetics.Get(skinId)
	if not skin or skin.Slot ~= "Skin" then
		return base
	end
	return {
		Shape = base.Shape,
		Body = skin.Body or base.Body,
		Accent = skin.Accent or base.Accent,
		Glow = skin.Glow or base.Glow,
		Metal = base.Metal,
		Material = skin.Material or base.Material,
		Scale = base.Scale,
	}
end

-- Target properties of one part under a look (used by the paint line).
function VacuumModel.RoleProps(role: string, look: Look): { [string]: any }
	return roleProps(role, look)
end

-- Adds a Trail between two attachments at the back of the model.
function VacuumModel.AttachTrail(model: Model, trailId: string?): Trail?
	local existing = model:FindFirstChild("CosmeticTrail", true)
	if existing then
		existing:Destroy()
	end
	for _, name in { "TrailA", "TrailB" } do
		local att = model:FindFirstChild(name, true)
		if att then
			att:Destroy()
		end
	end
	local cosmetic = Cosmetics.Get(trailId)
	if not cosmetic or cosmetic.Slot ~= "Trail" then
		return nil
	end
	local root = model.PrimaryPart
	if not root then
		return nil
	end
	local extents = model:GetExtentsSize()
	local width = cosmetic.Width or 1
	local a = Instance.new("Attachment")
	a.Name = "TrailA"
	a.Position = Vector3.new(0, extents.Y * 0.5 + width * 0.5, extents.Z * 0.45)
	a.Parent = root
	local b = Instance.new("Attachment")
	b.Name = "TrailB"
	b.Position = Vector3.new(0, extents.Y * 0.5 - width * 0.5, extents.Z * 0.45)
	b.Parent = root

	local colors = cosmetic.Colors or { Color3.new(1, 1, 1) }
	local keypoints = {}
	for i, color in colors do
		local t = if #colors == 1 then 0 else (i - 1) / (#colors - 1)
		table.insert(keypoints, ColorSequenceKeypoint.new(t, color))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, colors[1]))
	end

	local trail = Instance.new("Trail")
	trail.Name = "CosmeticTrail"
	trail.Attachment0 = a
	trail.Attachment1 = b
	trail.Color = ColorSequence.new(keypoints)
	trail.Lifetime = cosmetic.Lifetime or 0.6
	trail.LightEmission = 0.6
	trail.FaceCamera = true
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Parent = root
	return trail
end

-- Parts sorted bottom-up (assembly order for the robot arms).
function VacuumModel.AssemblyOrder(model: Model): { BasePart }
	local parts = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= model.PrimaryPart then
			table.insert(parts, part)
		end
	end
	table.sort(parts, function(a, b)
		local ha = (a:GetAttribute("Home") :: CFrame).Position
		local hb = (b:GetAttribute("Home") :: CFrame).Position
		if math.abs(ha.Y - hb.Y) > 0.25 then
			return ha.Y < hb.Y
		end
		return ha.Z > hb.Z
	end)
	return parts
end

return VacuumModel
