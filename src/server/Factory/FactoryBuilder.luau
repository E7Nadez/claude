-- Builds the static Vacuum Mega-Factory for one world from Parts.
-- Everything that is the same for all players lives here (walls, podium
-- bases, lanes, machines, tracks, prompts). Everything per-player or
-- animated (vacuums on podiums, glass locks, holograms, robots, doors,
-- sequences) is created on the client from these anchors.
--
-- Naming contract used by the client (keep names when swapping in meshes):
--   Origin, EntryTrigger, Showroom/Podiums/Podium_i/{Base,Ring,Display,Holo},
--   Showroom/AssemblyBay/{Mounts/Mount_i, CoinSlot, Conveyor, ExitTube, ExitStep},
--   TestChamber/Lanes/Lane_i/{Belt, Pad, Screen, Hatch},
--   UpgradeLab/Machine_<upgradeId>/{Mount, Sign, Console},
--   CapsuleHall/Machine_<capsuleId>/{DomeCenter, Chute, Sign}, CapsuleHall/Runs/Run_<id>,
--   CapsuleHall/RevealPad, PaintShop/{Line, Booth, Nozzles},
--   TrophyVault/{DoorAnchor, Pedestals/Pedestal_<trophyId>/{Top, Plate}},
--   Lobby/{CrateBelt, CrateHatch, CratePad, CrateScreen, NightStand/NightSign},
--   Roof/RoofVacuum/Nozzle, Facade/Gears/Gear_i.

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Builder = require(Shared.Util.Builder)
local Definitions = Shared.Definitions
local Factory = require(Definitions.Factory)
local Worlds = require(Definitions.Worlds)
local Vacuums = require(Definitions.Vacuums)
local Capsules = require(Definitions.Capsules)
local Upgrades = require(Definitions.Upgrades)
local Trophies = require(Definitions.Trophies)
local Cosmetics = require(Definitions.Cosmetics)

local FactoryBuilder = {}

local H = Factory.WallHeight
local WALL_T = 2
-- The origin sits on the ground (FactoryAnchor bottom / fallback y = 0). Lift the
-- build a hair so the floor and plaza tops never z-fight with a flat ground.
local GROUND_CLEARANCE = 0.1
-- Rectangular doorway (width, height) in the wall behind the round vault door.
local VAULT_DOORWAY = Vector2.new(20, 21)

type Ctx = {
	origin: CFrame,
	theme: Worlds.Theme,
	model: Model,
}

-- Local-space helpers ---------------------------------------------------------

local function world(ctx: Ctx, v: Vector3): Vector3
	return ctx.origin:PointToWorldSpace(v)
end

local function worldCf(ctx: Ctx, cf: CFrame): CFrame
	return ctx.origin * cf
end

local function part(ctx: Ctx, parent: Instance, props: { [string]: any }): BasePart
	local p = table.clone(props)
	p.CFrame = worldCf(ctx, props.CFrame or CFrame.identity)
	p.Parent = parent
	if p.Material == nil then
		p.Material = ctx.theme.WallMaterial
	end
	if p.Color == nil then
		p.Color = ctx.theme.Wall
	end
	return Builder.Part(p)
end

local function box(ctx: Ctx, parent: Instance, name: string, center: Vector3, size: Vector3, props: { [string]: any }?): BasePart
	local p = if props then table.clone(props) else {}
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new(center) * (p.Rotation or CFrame.identity)
	p.Rotation = nil
	return part(ctx, parent, p)
end

local function pipe(ctx: Ctx, parent: Instance, a: Vector3, b: Vector3, radius: number, props: { [string]: any }): BasePart
	local p = table.clone(props)
	p.Parent = parent
	if p.Material == nil then
		p.Material = ctx.theme.TrimMaterial
	end
	if p.Color == nil then
		p.Color = ctx.theme.Trim
	end
	return Builder.Pipe(world(ctx, a), world(ctx, b), radius, p)
end

local function beam(ctx: Ctx, parent: Instance, a: Vector3, b: Vector3, w: number, h: number, props: { [string]: any }): BasePart
	local p = table.clone(props)
	p.Parent = parent
	if p.Material == nil then
		p.Material = ctx.theme.TrimMaterial
	end
	if p.Color == nil then
		p.Color = ctx.theme.Trim
	end
	return Builder.Beam(world(ctx, a), world(ctx, b), w, h, p)
end

local function cylY(ctx: Ctx, parent: Instance, name: string, center: Vector3, height: number, diameter: number, props: { [string]: any }?): BasePart
	local p = if props then table.clone(props) else {}
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, diameter, diameter)
	p.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2)
	return part(ctx, parent, p)
end

-- Only theme-coloured neon (no explicit colour) gets the "FactoryNeon" night
-- tint; accents with their own colour (gold, NeonAlt, rarity) keep it at night.
local function neon(ctx: Ctx, color: Color3?): { [string]: any }
	return {
		Material = Enum.Material.Neon,
		Color = color or ctx.theme.Neon,
		CanCollide = false,
		CastShadow = false,
		Tags = if color == nil then { "FactoryNeon" } else nil,
	}
end

local function trim(ctx: Ctx): { [string]: any }
	return {
		Material = ctx.theme.TrimMaterial,
		Color = ctx.theme.Trim,
		Reflectance = ctx.theme.TrimReflectance,
	}
end

local function glass(ctx: Ctx, transparency: number?): { [string]: any }
	return {
		Material = Enum.Material.Glass,
		Color = ctx.theme.Glass,
		Transparency = transparency or 0.6,
		CastShadow = false,
	}
end

local function sign(ctx: Ctx, parent: Instance, name: string, center: Vector3, size: Vector3, rotation: CFrame, text: string, face: Enum.NormalId, textColor: Color3?): BasePart
	local plate = box(ctx, parent, name, center, size, {
		Rotation = rotation,
		Color = ctx.theme.Wall:Lerp(Color3.new(0, 0, 0), 0.5),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	Builder.Sign(plate, face, text, { TextColor = textColor or ctx.theme.Neon, PixelsPerStud = 30 })
	return plate
end

local function prompt(attachTo: BasePart, action: string, target: string?, actionText: string, objectText: string, distance: number?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = "ShopPrompt"
	p.ActionText = actionText
	p.ObjectText = objectText
	p.HoldDuration = 0
	p.MaxActivationDistance = distance or 12
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p:SetAttribute("ShopAction", action)
	if target then
		p:SetAttribute("Target", target)
	end
	p.Parent = attachTo
	return p
end

-- Wall along X (at z) from x0 to x1 with doorway openings { X, Width, Height }.
local function wallX(ctx: Ctx, parent: Instance, z: number, x0: number, x1: number, openings: { { number } }, height: number?)
	local h = height or H
	table.sort(openings, function(a, b)
		return a[1] < b[1]
	end)
	local cursor = x0
	local function solid(a: number, b: number)
		if b - a > 0.05 then
			box(ctx, parent, "Wall", Vector3.new((a + b) / 2, h / 2, z), Vector3.new(b - a, h, WALL_T), { Color = ctx.theme.Wall, Material = ctx.theme.WallMaterial })
			box(ctx, parent, "Baseboard", Vector3.new((a + b) / 2, 0.35, z), Vector3.new(b - a, 0.25, WALL_T + 0.3), neon(ctx))
		end
	end
	for _, opening in openings do
		local cx, w, oh = opening[1], opening[2], opening[3]
		solid(cursor, cx - w / 2)
		box(ctx, parent, "Lintel", Vector3.new(cx, (oh + h) / 2, z), Vector3.new(w, h - oh, WALL_T), { Color = ctx.theme.Wall, Material = ctx.theme.WallMaterial })
		box(ctx, parent, "DoorFrame", Vector3.new(cx, oh + 0.3, z), Vector3.new(w + 1, 0.6, WALL_T + 0.6), trim(ctx))
		box(ctx, parent, "DoorFrame", Vector3.new(cx - w / 2 - 0.3, oh / 2, z), Vector3.new(0.6, oh, WALL_T + 0.6), trim(ctx))
		box(ctx, parent, "DoorFrame", Vector3.new(cx + w / 2 + 0.3, oh / 2, z), Vector3.new(0.6, oh, WALL_T + 0.6), trim(ctx))
		box(ctx, parent, "DoorGlow", Vector3.new(cx, oh + 0.75, z), Vector3.new(w, 0.2, WALL_T + 0.8), neon(ctx, ctx.theme.NeonAlt))
		cursor = cx + w / 2
	end
	solid(cursor, x1)
end

-- Wall along Z (at x) from z0 to z1 with openings { Z, Width, Height }.
local function wallZ(ctx: Ctx, parent: Instance, x: number, z0: number, z1: number, openings: { { number } }, height: number?)
	local h = height or H
	table.sort(openings, function(a, b)
		return a[1] < b[1]
	end)
	local cursor = z0
	local function solid(a: number, b: number)
		if b - a > 0.05 then
			box(ctx, parent, "Wall", Vector3.new(x, h / 2, (a + b) / 2), Vector3.new(WALL_T, h, b - a), { Color = ctx.theme.Wall, Material = ctx.theme.WallMaterial })
			box(ctx, parent, "Baseboard", Vector3.new(x, 0.35, (a + b) / 2), Vector3.new(WALL_T + 0.3, 0.25, b - a), neon(ctx))
		end
	end
	for _, opening in openings do
		local cz, w, oh = opening[1], opening[2], opening[3]
		solid(cursor, cz - w / 2)
		box(ctx, parent, "Lintel", Vector3.new(x, (oh + h) / 2, cz), Vector3.new(WALL_T, h - oh, w), { Color = ctx.theme.Wall, Material = ctx.theme.WallMaterial })
		box(ctx, parent, "DoorFrame", Vector3.new(x, oh + 0.3, cz), Vector3.new(WALL_T + 0.6, 0.6, w + 1), trim(ctx))
		box(ctx, parent, "DoorFrame", Vector3.new(x, oh / 2, cz - w / 2 - 0.3), Vector3.new(WALL_T + 0.6, oh, 0.6), trim(ctx))
		box(ctx, parent, "DoorFrame", Vector3.new(x, oh / 2, cz + w / 2 + 0.3), Vector3.new(WALL_T + 0.6, oh, 0.6), trim(ctx))
		box(ctx, parent, "DoorGlow", Vector3.new(x, oh + 0.75, cz), Vector3.new(WALL_T + 0.8, 0.2, w), neon(ctx, ctx.theme.NeonAlt))
		cursor = cz + w / 2
	end
	solid(cursor, z1)
end

-- Moving slats on top of a belt. Direction is local; the client animates.
local function belt(ctx: Ctx, parent: Instance, name: string, from: Vector3, to: Vector3, width: number, height: number, speed: number): BasePart
	local dir = (to - from)
	local length = dir.Magnitude
	local center = (from + to) / 2 - Vector3.new(0, height / 2, 0)
	local rotation = CFrame.lookAt(Vector3.zero, dir.Unit)
	local base = box(ctx, parent, name, center, Vector3.new(width, height, length), {
		Rotation = rotation,
		Color = Color3.fromRGB(30, 32, 38),
		Material = Enum.Material.SmoothPlastic,
	})
	base:SetAttribute("BeltSpeed", speed)
	base:SetAttribute("BeltDirection", ctx.origin:VectorToWorldSpace(dir.Unit))
	base:SetAttribute("BeltLength", length)
	base:SetAttribute("BeltStart", world(ctx, from))
	local slats = Builder.Folder("Slats", base)
	local spacing = 2.4
	local count = math.floor(length / spacing)
	for i = 0, count - 1 do
		local pos = from + dir.Unit * (i * spacing + spacing / 2)
		local slat = box(ctx, slats, "Slat", pos + Vector3.new(0, 0.06, 0), Vector3.new(width - 0.4, 0.12, spacing * 0.55), {
			Rotation = rotation,
			Color = Color3.fromRGB(58, 60, 70),
			Material = Enum.Material.DiamondPlate,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		slat:SetAttribute("Index", i)
	end
	slats:SetAttribute("Spacing", spacing)
	slats:SetAttribute("Count", count)
	CollectionService:AddTag(base, "ConveyorBelt")
	for _, side in { -1, 1 } do
		local offset = rotation:VectorToWorldSpace(Vector3.new(side * (width / 2 + 0.25), 0, 0))
		beam(ctx, parent, from + offset + Vector3.new(0, 0.3, 0), to + offset + Vector3.new(0, 0.3, 0), 0.5, 0.8, trim(ctx))
	end
	return base
end

-- Sections --------------------------------------------------------------------

local function buildShell(ctx: Ctx)
	local shell = Builder.Model("Shell", ctx.model)
	local size = Factory.Size
	local rooms = Factory.Rooms

	box(ctx, shell, "Floor", Vector3.new(0, -0.5, size.Z / 2), Vector3.new(size.X + 4, 1, size.Z + 4), {
		Color = ctx.theme.Floor,
		Material = ctx.theme.FloorMaterial,
	})
	-- ends where the building floor (z >= -2) begins: no coplanar overlap
	box(ctx, shell, "Plaza", Vector3.new(0, -0.3, -23), Vector3.new(140, 0.6, 42), {
		Color = ctx.theme.Floor:Lerp(Color3.new(1, 1, 1), 0.08),
		Material = ctx.theme.FloorMaterial,
	})
	-- arrows stop short of the entrance ramp (z -20.5)
	for i = 0, 3 do
		box(ctx, shell, "PlazaArrow", Vector3.new(0, 0.02, -43 + i * 7), Vector3.new(6 - i, 0.06, 1.2), neon(ctx, ctx.theme.NeonAlt))
	end

	-- Room floor inlays
	for name, rect in rooms do
		local center = (rect.Min + rect.Max) / 2
		local extent = rect.Max - rect.Min
		box(ctx, shell, "Inlay_" .. name, Vector3.new(center.X, 0.02, center.Y), Vector3.new(extent.X - 6, 0.05, extent.Y - 6), {
			Color = ctx.theme.Floor:Lerp(ctx.theme.Accent, 0.12),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
	end

	-- Outer walls (front wall lives in the facade). Front and back walls run the
	-- full outer width so the corners are closed; the side walls fit between them.
	wallX(ctx, shell, size.Z, -101, 101, {})
	wallZ(ctx, shell, -100, 1, size.Z - 1, {})
	wallZ(ctx, shell, 100, 1, size.Z - 1, {})

	-- Interior walls. The centre portal is tall enough for the glass ride tube
	-- (and the entry camera) to pass through it instead of the lintel.
	wallX(ctx, shell, 40, -100, 100, { { -71, 16, 16 }, { 0, 24, 37 }, { 71, 16, 16 } })
	wallX(ctx, shell, 124, -100, 100, { { -62, 18, 16 }, { 0, 14, 16 }, { 62, 18, 16 } })
	wallZ(ctx, shell, -42, 40, 124, { { 82, 14, 16 } })
	wallZ(ctx, shell, 42, 40, 124, { { 82, 14, 16 } })
	wallZ(ctx, shell, -24, 124, 220, { { 137, 10, 14 } })
	wallZ(ctx, shell, 24, 124, 220, { { 137, 10, 14 } })
	wallX(ctx, shell, 150, -24, 24, { { 0, VAULT_DOORWAY.X, VAULT_DOORWAY.Y } })

	-- Roof: solid strips with skylights between them
	local stripZ = { { 0, 50 }, { 62, 108 }, { 120, 166 }, { 178, 220 } }
	for _, strip in stripZ do
		local z0, z1 = strip[1], strip[2]
		box(ctx, shell, "Roof", Vector3.new(0, H + 1, (z0 + z1) / 2), Vector3.new(size.X + 4, 2, z1 - z0), {
			Color = ctx.theme.Wall:Lerp(Color3.new(0, 0, 0), 0.2),
			Material = ctx.theme.WallMaterial,
		})
	end
	for _, gap in { { 50, 62 }, { 108, 120 }, { 166, 178 } } do
		box(ctx, shell, "Skylight", Vector3.new(0, H + 1, (gap[1] + gap[2]) / 2), Vector3.new(size.X + 4, 0.6, gap[2] - gap[1]), glass(ctx, 0.55))
		for x = -90, 90, 30 do
			box(ctx, shell, "SkylightRib", Vector3.new(x, H + 1, (gap[1] + gap[2]) / 2), Vector3.new(1, 1.2, gap[2] - gap[1]), trim(ctx))
		end
	end
	-- Roof edge neon
	box(ctx, shell, "RoofEdge", Vector3.new(0, H + 2.2, size.Z), Vector3.new(size.X + 4, 0.4, 0.4), neon(ctx))
	box(ctx, shell, "RoofEdge", Vector3.new(-size.X / 2 - 2, H + 2.2, size.Z / 2), Vector3.new(0.4, 0.4, size.Z), neon(ctx))
	box(ctx, shell, "RoofEdge", Vector3.new(size.X / 2 + 2, H + 2.2, size.Z / 2), Vector3.new(0.4, 0.4, size.Z), neon(ctx))

	-- Ceiling lamps
	local lamps = Builder.Folder("Lamps", shell)
	for _, x in { -70, -35, 0, 35, 70 } do
		for _, z in { 20, 82, 145, 196 } do
			local lamp = cylY(ctx, lamps, "Lamp", Vector3.new(x, H - 1, z), 0.5, 5, {
				Material = Enum.Material.Neon,
				Color = ctx.theme.Ambient:Lerp(Color3.new(1, 1, 1), 0.6),
				CanCollide = false,
				Tags = { "FactoryLamp" },
			})
			Builder.Light(lamp, "PointLight", {
				Range = 48,
				Brightness = 1.3,
				Color = ctx.theme.Ambient:Lerp(Color3.new(1, 1, 1), 0.5),
				Shadows = false,
			})
			box(ctx, lamps, "LampHood", Vector3.new(x, H - 0.4, z), Vector3.new(6, 0.6, 6), trim(ctx))
		end
	end
end

local function buildFacade(ctx: Ctx, worldName: string)
	local facade = Builder.Model("Facade", ctx.model)
	wallX(ctx, facade, 0, -101, 101, { { -40, 14, 16 }, { 0, 16, 16 }, { 40, 14, 16 } })

	-- Big sign
	local signPlate = box(ctx, facade, "MainSign", Vector3.new(0, 31, -1.6), Vector3.new(96, 10, 1), {
		Color = Color3.fromRGB(14, 15, 20),
		Material = Enum.Material.SmoothPlastic,
	})
	Builder.Sign(signPlate, Enum.NormalId.Front, "VACUUM MEGA-FACTORY", { TextColor = ctx.theme.Neon, PixelsPerStud = 24, Name = "Title" })
	for _, data in { { 0, 36.2, 98, 0.5 }, { 0, 25.8, 98, 0.5 } } do
		box(ctx, facade, "SignFrame", Vector3.new(data[1], data[2], -2.2), Vector3.new(data[3], data[4], 0.5), neon(ctx))
	end
	for _, x in { -49, 49 } do
		box(ctx, facade, "SignFrame", Vector3.new(x, 31, -2.2), Vector3.new(0.5, 10.9, 0.5), neon(ctx))
	end
	local sub = box(ctx, facade, "SubSign", Vector3.new(0, 23.2, -1.4), Vector3.new(44, 3.6, 0.8), {
		Color = Color3.fromRGB(14, 15, 20),
		Material = Enum.Material.SmoothPlastic,
	})
	Builder.Sign(sub, Enum.NormalId.Front, string.upper(worldName) .. " BRANCH", { TextColor = ctx.theme.NeonAlt, PixelsPerStud = 24 })

	-- Window band
	for _, span in { { -96, -54 }, { 54, 96 } } do
		local cx = (span[1] + span[2]) / 2
		local w = span[2] - span[1]
		box(ctx, facade, "Window", Vector3.new(cx, 22, -1.1), Vector3.new(w, 6, 0.4), {
			Material = Enum.Material.Neon,
			Color = ctx.theme.Glass:Lerp(ctx.theme.Neon, 0.25),
			Transparency = 0.35,
			CanCollide = false,
			Tags = { "FactoryNeon" },
		})
		for x = span[1], span[2], 7 do
			box(ctx, facade, "Mullion", Vector3.new(x, 22, -1.4), Vector3.new(0.6, 6.4, 0.6), trim(ctx))
		end
	end

	-- Pipes with pumping bulbs
	local pumps = Builder.Folder("Pumps", facade)
	for _, x in { -88, -62, 62, 88 } do
		pipe(ctx, facade, Vector3.new(x, 0, -3), Vector3.new(x, H + 2, -3), 1.3, trim(ctx))
		for _, y in { 11, 27 } do
			local bulb = part(ctx, pumps, {
				Name = "Pump",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 4.4,
				CFrame = CFrame.new(x, y, -3),
				Material = Enum.Material.Glass,
				Color = ctx.theme.Neon,
				Transparency = 0.25,
				CanCollide = false,
				Tags = { "FactoryPump" },
			})
			bulb:SetAttribute("BaseSize", 4.4)
			bulb:SetAttribute("Phase", (x + y) * 0.13)
			part(ctx, pumps, {
				Name = "PumpCore",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 2.4,
				CFrame = CFrame.new(x, y, -3),
				Material = Enum.Material.Neon,
				Color = ctx.theme.Neon,
				CanCollide = false,
				Tags = { "FactoryNeon" },
			})
		end
	end
	pipe(ctx, facade, Vector3.new(-88, H + 1, -3), Vector3.new(88, H + 1, -3), 1.1, trim(ctx))

	-- Gears
	local gears = Builder.Folder("Gears", facade)
	local spots = {
		{ -74, 33, 5.5 },
		{ 74, 33, 5.5 },
		{ -54, 36, 3.2 },
		{ 54, 36, 3.2 },
		{ -76, 12, 4.2 },
		{ 76, 12, 4.2 },
		{ -24, 12, 3 },
		{ 24, 12, 3 },
	}
	for i = 1, math.min(ctx.theme.GearCount, #spots) do
		local spot = spots[i]
		local gearModel = Builder.Model("Gear_" .. i, gears)
		local cf = worldCf(ctx, CFrame.new(spot[1], spot[2], -2.6))
		local teeth = math.floor(spot[3] * 3)
		local props = {
			Color = if i % 2 == 0 then ctx.theme.Trim else ctx.theme.Metal,
			Material = ctx.theme.TrimMaterial,
			Reflectance = ctx.theme.TrimReflectance,
			CanCollide = false,
		}
		for _, gp in Builder.Gear(cf, spot[3], 1.2, teeth, props) do
			gp.Parent = gearModel
		end
		gearModel:SetAttribute("Center", cf)
		gearModel:SetAttribute("Speed", (if i % 2 == 0 then -1 else 1) * 1.6 / spot[3])
		CollectionService:AddTag(gearModel, "FactoryGear")
	end

	-- Corner neon pillars
	for _, x in { -100.65, 100.65 } do
		box(ctx, facade, "CornerGlow", Vector3.new(x, H / 2, -1.2), Vector3.new(0.6, H, 0.6), neon(ctx))
	end
	box(ctx, facade, "TopGlow", Vector3.new(0, H + 0.2, -1.2), Vector3.new(201.9, 0.5, 0.6), neon(ctx))
end

local function buildEntrance(ctx: Ctx)
	local entrance = Builder.Model("Entrance", ctx.model)
	local config = Factory.Entrance
	local mouth = config.Mouth
	local radius = config.MouthRadius

	-- Intake tube sticking out of the facade (glass ends at the facade's outer face)
	for _, parts in {
		Builder.Ring(worldCf(ctx, CFrame.new(mouth.X, mouth.Y, -6.5)), radius + 0.6, 1.2, 11, 16, {
			Material = Enum.Material.Glass,
			Color = ctx.theme.Glass,
			Transparency = 0.45,
			CanCollide = false,
			CastShadow = false,
		}),
		Builder.Ring(worldCf(ctx, CFrame.new(mouth.X, mouth.Y, -12.2)), radius + 1.2, 1.4, 1, 16, {
			Material = ctx.theme.TrimMaterial,
			Color = ctx.theme.Trim,
			Reflectance = ctx.theme.TrimReflectance,
		}),
		Builder.Ring(worldCf(ctx, CFrame.new(mouth.X, mouth.Y, -12.9)), radius + 1.2, 0.5, 0.4, 16, neon(ctx, ctx.theme.NeonAlt)),
	} do
		for _, p in parts do
			p.Parent = entrance
		end
	end
	-- The floor top (2.1) sits just above the glass ring's inner bottom (2.0), so
	-- feet never wade through glass and the mouth trim ring is no curb.
	-- A WedgePart rises towards its local +Z: the outer ramp climbs from the
	-- plaza to the tube, the inner step (turned around) drops into the lobby.
	box(ctx, entrance, "TubeFloor", Vector3.new(0, 1.05, -6.75), Vector3.new(10, 2.1, 11.5), trim(ctx))
	part(ctx, entrance, {
		Name = "TubeRamp",
		ClassName = "WedgePart",
		Size = Vector3.new(10, 2.1, 8),
		CFrame = CFrame.new(0, 1.05, -16.5),
		Color = ctx.theme.Trim,
		Material = ctx.theme.TrimMaterial,
	})
	part(ctx, entrance, {
		Name = "TubeStep",
		ClassName = "WedgePart",
		Size = Vector3.new(10, 2.1, 4),
		CFrame = CFrame.new(0, 1.05, 1) * CFrame.Angles(0, math.pi, 0),
		Color = ctx.theme.Trim,
		Material = ctx.theme.TrimMaterial,
	})
	local swirl = box(ctx, entrance, "Swirl", Vector3.new(0, mouth.Y, 1.5), Vector3.new(radius * 2, radius * 2, 0.2), {
		Material = Enum.Material.Neon,
		Color = ctx.theme.Neon,
		Transparency = 0.6,
		CanCollide = false,
		CanQuery = false,
	})
	swirl:SetAttribute("Spin", 1.5)
	CollectionService:AddTag(swirl, "FactorySwirl")

	-- Entry trigger volume (client checks if its character is inside)
	box(ctx, entrance, "EntryTrigger", config.Trigger, Vector3.new(radius * 2 - 2, 9, 4), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})

	-- Glass ride tube through the building into the showroom. It starts at the
	-- inner face of the facade (z = 1), where the intake tube ends, and the
	-- outlet above the landing pad is capped with a neon ring.
	local path = config.TubePath
	local function tubeRing(cf: CFrame)
		for _, p in Builder.Ring(worldCf(ctx, cf), config.TubeRadius + 0.2, 0.35, 0.6, 12, neon(ctx)) do
			p.Parent = entrance
		end
	end
	local span = path[3].Z - path[2].Z
	local first = if span > 0 then path[2]:Lerp(path[3], math.clamp((1 - path[2].Z) / span, 0, 1)) else path[3]
	for i = 2, #path - 1 do
		local a = if i == 2 then first else path[i]
		local b = path[i + 1]
		if (b - a).Magnitude > 0.05 then
			pipe(ctx, entrance, a, b, config.TubeRadius, {
				Material = Enum.Material.Glass,
				Color = ctx.theme.Glass,
				Transparency = 0.72,
				CanCollide = false,
				CastShadow = false,
			})
			tubeRing(CFrame.lookAt(a, b))
		end
	end
	local outlet = path[#path]
	local outletDir = outlet - path[#path - 1]
	if outletDir.Magnitude > 0.05 then
		tubeRing(CFrame.lookAt(outlet, outlet + outletDir))
	end

	-- Landing pad in the showroom. It overlaps the turntable edge (top 0.6), so
	-- it stands a little proud of it; the glow is a rim below the pad's top.
	cylY(ctx, entrance, "LandingPad", Vector3.new(config.Landing.X, 0.4, config.Landing.Z), 0.8, 9, trim(ctx))
	cylY(ctx, entrance, "LandingGlow", Vector3.new(config.Landing.X, 0.36, config.Landing.Z), 0.68, 9.6, neon(ctx, ctx.theme.NeonAlt))
end

local function buildRoof(ctx: Ctx)
	local roof = Builder.Model("Roof", ctx.model)
	local rv = Builder.Model("RoofVacuum", roof)
	local base = Factory.Roof.VacuumBase
	box(ctx, rv, "Base", base + Vector3.new(0, 1.5, 0), Vector3.new(16, 3, 12), trim(ctx))
	local tank = part(ctx, rv, {
		Name = "Tank",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(18, 9, 9),
		CFrame = CFrame.new(base + Vector3.new(0, 7.5, 2)),
		Color = ctx.theme.Accent,
		Material = ctx.theme.TrimMaterial,
		Reflectance = ctx.theme.TrimReflectance,
	})
	tank:SetAttribute("Breathe", true)
	for _, dx in { -6, 0, 6 } do
		part(ctx, rv, {
			Name = "Band",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.8, 9.4, 9.4),
			CFrame = CFrame.new(base + Vector3.new(dx, 7.5, 2)),
			Material = Enum.Material.Neon,
			Color = ctx.theme.Neon,
			CanCollide = false,
			Tags = { "FactoryNeon" },
		})
	end
	local nozzle = Factory.Roof.Nozzle
	local hoseStart = base + Vector3.new(0, 9, -2)
	pipe(ctx, rv, hoseStart, nozzle + Vector3.new(0, -2.5, 3), 1.6, { Color = Color3.fromRGB(40, 40, 46), Material = Enum.Material.SmoothPlastic })
	local dir = (nozzle - (nozzle + Vector3.new(0, -2.5, 3))).Unit
	for i, r in { 2.0, 2.8, 3.6 } do
		local c = nozzle + Vector3.new(0, -2.5, 3) + dir * (i * 1.1)
		pipe(ctx, rv, c - dir * 0.55, c + dir * 0.55, r, trim(ctx))
	end
	local mouth = part(ctx, rv, {
		Name = "Nozzle",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 7, 7),
		CFrame = CFrame.new(nozzle + Vector3.new(0, -2.5, 3) + dir * 4.2) * Builder.AxisCFrame(Vector3.zero, dir).Rotation,
		Material = Enum.Material.Neon,
		Color = ctx.theme.NeonAlt,
		CanCollide = false,
		Tags = { "FactoryNeon" },
	})
	mouth:SetAttribute("Direction", ctx.origin:VectorToWorldSpace(dir))

	local vents = Builder.Folder("Vents", roof)
	for i, v in Factory.Roof.Vents do
		cylY(ctx, vents, "Chimney", v + Vector3.new(0, 5, 0), 10, 5, trim(ctx))
		local top = cylY(ctx, vents, "VentTop", v + Vector3.new(0, 10.3, 0), 0.6, 6, {
			Material = ctx.theme.TrimMaterial,
			Color = ctx.theme.Metal,
			Tags = { "SteamVent" },
		})
		top:SetAttribute("Phase", i * 1.7)
	end
end

local function buildShowroom(ctx: Ctx, worldId: string)
	local showroom = Builder.Model("Showroom", ctx.model)
	local config = Factory.Showroom
	local center = config.Center

	cylY(ctx, showroom, "Turntable", center + Vector3.new(0, 0.3, 0), 0.6, config.TurntableRadius * 2, {
		Color = ctx.theme.Floor:Lerp(ctx.theme.Trim, 0.25),
		Material = ctx.theme.TrimMaterial,
	})
	-- glow rim: wider than the turntable but below its top, so only a ring shows
	cylY(ctx, showroom, "TurntableGlow", center + Vector3.new(0, 0.27, 0), 0.5, config.TurntableRadius * 2 + 1, neon(ctx))
	cylY(ctx, showroom, "InnerDisc", center + Vector3.new(0, 0.35, 0), 0.6, 12, neon(ctx, ctx.theme.NeonAlt))

	-- Center console
	local console = box(ctx, showroom, "Console", center + Vector3.new(0, 2.2, 0), Vector3.new(3.4, 3.8, 3.4), trim(ctx))
	box(ctx, showroom, "ConsoleScreen", center + Vector3.new(0, 4.3, 0), Vector3.new(3.6, 0.3, 3.6), neon(ctx))
	prompt(console, "Browse", nil, "Browse", "Vacuum Showroom", 16)
	for _, p in Builder.Ring(worldCf(ctx, CFrame.new(center + Vector3.new(0, 16, 0)) * CFrame.Angles(math.pi / 2, 0, 0)), 9, 0.4, 0.4, 24, neon(ctx)) do
		p.Parent = showroom
		p:SetAttribute("Spin", 0.25)
		CollectionService:AddTag(p, "HaloRing")
	end

	-- Podiums
	local podiums = Builder.Folder("Podiums", showroom)
	local vacuums = Vacuums.ForWorld(worldId)
	local count = #vacuums
	for i, vacuum in vacuums do
		local angle = (i - 1) / count * math.pi * 2
		local dir = Vector3.new(math.sin(angle), 0, -math.cos(angle))
		local pos = center + dir * config.PodiumRadius
		local podium = Builder.Model("Podium_" .. i, podiums)
		podium:SetAttribute("Index", i)
		podium:SetAttribute("VacuumId", vacuum.Id)
		local height = config.PodiumHeight
		cylY(ctx, podium, "Base", pos + Vector3.new(0, 0.6 + height / 2, 0), height, 7, {
			Color = ctx.theme.Wall:Lerp(Color3.new(0, 0, 0), 0.3),
			Material = ctx.theme.TrimMaterial,
			Reflectance = 0.1,
		})
		-- explicit colour: the client recolours the ring per rarity, so it must not
		-- be part of the night tint (which would overwrite the rarity colour)
		cylY(ctx, podium, "Ring", pos + Vector3.new(0, 0.6 + height + 0.05, 0), 0.3, 7.4, neon(ctx, ctx.theme.Neon))
		local camPos = center + dir * (config.PodiumRadius - config.CameraInset) + Vector3.new(0, config.CameraHeight, 0)
		local top = pos + Vector3.new(0, 0.6 + height + 0.2, 0)
		box(ctx, podium, "Display", top, Vector3.new(0.4, 0.4, 0.4), {
			Rotation = CFrame.lookAt(Vector3.zero, Vector3.new(camPos.X - top.X, 0, camPos.Z - top.Z)).Rotation,
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		})
		local tangent = Vector3.new(-dir.Z, 0, dir.X)
		local holoPos = pos + tangent * config.HoloOffset + Vector3.new(0, 7.5, 0)
		box(ctx, podium, "Holo", holoPos, Vector3.new(7.5, 5.2, 0.1), {
			Rotation = CFrame.lookAt(Vector3.zero, camPos - holoPos).Rotation,
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		})
		local spot = box(ctx, podium, "Spot", pos + Vector3.new(0, H - 3, 0), Vector3.new(1, 1, 1), {
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		})
		Builder.Light(spot, "SpotLight", { Face = Enum.NormalId.Bottom, Angle = 35, Range = 40, Brightness = 2.2, Color = Color3.new(1, 1, 1), Shadows = false })
		local base = podium:FindFirstChild("Base") :: BasePart
		prompt(base, "Podium", vacuum.Id, "Inspect", vacuum.Name, 10)
	end

	-- Assembly bay
	local bayConfig = Factory.AssemblyBay
	local bay = Builder.Model("AssemblyBay", showroom)
	local bayCenter = bayConfig.Center
	box(ctx, bay, "Platform", Vector3.new(bayCenter.X, 0.75, bayCenter.Z), Vector3.new(24, 1.5, 14), trim(ctx))
	box(ctx, bay, "PlatformGlow", Vector3.new(bayCenter.X, 1.52, bayCenter.Z), Vector3.new(10, 0.05, 10), neon(ctx, ctx.theme.NeonAlt))
	local mounts = Builder.Folder("Mounts", bay)
	local mountSpots = {
		Vector3.new(-6, 1.5, 107),
		Vector3.new(6, 1.5, 107),
		Vector3.new(-6.5, 1.5, 113),
		Vector3.new(6.5, 1.5, 113),
		Vector3.new(-2.8, 1.5, 116),
		Vector3.new(2.8, 1.5, 116),
	}
	for i, spot in mountSpots do
		local mount = cylY(ctx, mounts, "Mount_" .. i, spot + Vector3.new(0, 0.15, 0), 0.3, 2.4, {
			Color = Color3.fromRGB(40, 42, 50),
			Material = Enum.Material.DiamondPlate,
		})
		mount:SetAttribute("Index", i)
	end
	local slot = bayConfig.CoinSlot
	box(ctx, bay, "CoinPillar", Vector3.new(slot.X, slot.Y / 2, slot.Z), Vector3.new(2.6, slot.Y, 2.6), trim(ctx))
	-- slot sits on the pillar's front face, below its top edge
	box(ctx, bay, "CoinSlot", slot + Vector3.new(0, -0.6, -1.31), Vector3.new(1.6, 0.35, 0.1), neon(ctx, Color3.fromRGB(255, 210, 70)))
	-- belt top a hair above the platform top (1.5) so the two never z-fight
	local belt0 = bayCenter + Vector3.new(4, 0, 0)
	belt(ctx, bay, "Conveyor", Vector3.new(belt0.X, 1.56, belt0.Z), Vector3.new(bayConfig.ConveyorEnd.X, 1.56, bayConfig.ConveyorEnd.Z), 4, 1.56, 4)
	local tubePos = bayConfig.ExitTube
	for _, p in Builder.Ring(worldCf(ctx, CFrame.new(tubePos + Vector3.new(0, 6, 0)) * CFrame.Angles(math.pi / 2, 0, 0)), 4, 0.4, 12, 14, glass(ctx, 0.55)) do
		p.Parent = bay
		p.CanCollide = false
	end
	cylY(ctx, bay, "ExitTubeCap", tubePos + Vector3.new(0, 12.2, 0), 0.6, 9.4, neon(ctx))
	cylY(ctx, bay, "ExitTube", tubePos + Vector3.new(0, 0.3, 0), 0.6, 9, trim(ctx))
	box(ctx, bay, "ExitStep", bayConfig.ExitStep, Vector3.new(1, 1, 1), { Transparency = 1, CanCollide = false, CanQuery = false })
	sign(ctx, bay, "BaySign", Vector3.new(0, 11, 119.5), Vector3.new(26, 4, 0.6), CFrame.identity, "ASSEMBLY BAY", Enum.NormalId.Front)
	for _, x in { -13.3, 13.3 } do
		box(ctx, bay, "SignPost", Vector3.new(x, 6.7, 119.5), Vector3.new(0.6, 13.4, 0.8), trim(ctx))
	end
end

local function buildTestChamber(ctx: Ctx)
	local chamber = Builder.Model("TestChamber", ctx.model)
	local config = Factory.TestChamber
	local lanes = Builder.Folder("Lanes", chamber)
	sign(ctx, chamber, "Title", Vector3.new(-71, 30, 41.2), Vector3.new(40, 6, 0.6), CFrame.identity, "TEST CHAMBER", Enum.NormalId.Back)

	for i, z in config.Lanes do
		local lane = Builder.Model("Lane_" .. i, lanes)
		lane:SetAttribute("Index", i)
		lane:SetAttribute("Occupant", 0)
		lane:SetAttribute("OccupantName", "")
		lane:SetAttribute("VacuumId", "")
		lane:SetAttribute("Skin", "")
		lane:SetAttribute("EndsAt", 0)
		belt(ctx, lane, "Belt", Vector3.new(config.BeltStartX, config.BeltHeight, z), Vector3.new(config.BeltEndX, config.BeltHeight, z), config.BeltWidth, config.BeltHeight, 5)
		-- hatch housing reaches back to the side wall (inner face x = -99): no gap behind it
		local hatch = box(ctx, lane, "Hatch", Vector3.new(config.BeltStartX - 2, 4, z), Vector3.new(2, 6, config.BeltWidth + 2), {
			Color = Color3.fromRGB(20, 20, 26),
			Material = Enum.Material.SmoothPlastic,
		})
		hatch:SetAttribute("Lane", i)
		box(ctx, lane, "HatchFrame", Vector3.new(config.BeltStartX - 1.7, 7.4, z), Vector3.new(2.6, 0.8, config.BeltWidth + 3), neon(ctx, ctx.theme.NeonAlt))
		local pad = cylY(ctx, lane, "Pad", Vector3.new(config.PadX, 0.2, z), 0.4, 6, trim(ctx))
		pad:SetAttribute("Lane", i)
		cylY(ctx, lane, "PadGlow", Vector3.new(config.PadX, 0.17, z), 0.3, 6.6, neon(ctx))
		local screen = box(ctx, lane, "Screen", Vector3.new(config.ScreenX, 15, z), Vector3.new(0.5, 9, 16), {
			Color = Color3.fromRGB(12, 13, 18),
			Material = Enum.Material.SmoothPlastic,
		})
		Builder.Sign(screen, Enum.NormalId.Right, "LANE " .. i .. "\nFREE", { Name = "Status", TextColor = ctx.theme.Neon, PixelsPerStud = 20 })
		box(ctx, lane, "LaneNumber", Vector3.new(config.PadX + 5, 0.06, z), Vector3.new(2.5, 0.05, 2.5), neon(ctx, ctx.theme.NeonAlt))
	end
	for _, z in { 62, 82, 102 } do
		box(ctx, chamber, "Divider", Vector3.new(-80, 5, z), Vector3.new(38, 10, 0.4), glass(ctx, 0.65))
		box(ctx, chamber, "DividerTop", Vector3.new(-80, 10.1, z), Vector3.new(38, 0.3, 0.6), neon(ctx))
	end
end

local function buildUpgradeLab(ctx: Ctx)
	local lab = Builder.Model("UpgradeLab", ctx.model)
	local config = Factory.UpgradeLab
	sign(ctx, lab, "Title", Vector3.new(71, 30, 41.2), Vector3.new(40, 6, 0.6), CFrame.identity, "UPGRADE LAB", Enum.NormalId.Back)
	for _, upgrade in Upgrades.List do
		local pos = config.Machines[upgrade.Id]
		if not pos then
			continue
		end
		local machine = Builder.Model("Machine_" .. upgrade.Id, lab)
		machine:SetAttribute("UpgradeId", upgrade.Id)
		box(ctx, machine, "Base", pos + Vector3.new(0, 0.6, 0), Vector3.new(12, 1.2, 12), trim(ctx))
		box(ctx, machine, "BaseGlow", pos + Vector3.new(0, 1.1, 0), Vector3.new(12.4, 0.1, 12.4), neon(ctx))
		box(ctx, machine, "Mount", pos + Vector3.new(0, 1.3, 0), Vector3.new(0.5, 0.5, 0.5), {
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		})
		local toCenter = (config.Center - pos) * Vector3.new(1, 0, 1)
		local dir = toCenter.Unit
		local consolePos = pos + dir * 8
		local rotation = CFrame.lookAt(Vector3.zero, -dir).Rotation
		local console = box(ctx, machine, "Console", consolePos + Vector3.new(0, 1.75, 0), Vector3.new(3, 3.5, 1.5), {
			Rotation = rotation,
			Color = ctx.theme.Wall,
			Material = ctx.theme.TrimMaterial,
		})
		prompt(console, "Upgrade", upgrade.Id, "Upgrade", upgrade.Name, 12)
		-- Backdrop behind the machine, facing the lab centre: the focus camera
		-- looks at the machine from that side, so the sign must not stand between.
		local signPos = pos - dir * 6.5 + Vector3.new(0, 11, 0)
		box(ctx, machine, "Sign", signPos, Vector3.new(9, 4.5, 0.4), {
			Rotation = CFrame.lookAt(Vector3.zero, dir).Rotation,
			Color = Color3.fromRGB(12, 13, 18),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
		-- post from the base top up to the sign's bottom edge
		local baseTop = pos.Y + 1.2
		local postHeight = signPos.Y - 2.25 - baseTop
		box(ctx, machine, "SignPost", Vector3.new(signPos.X, baseTop + postHeight / 2, signPos.Z), Vector3.new(0.6, postHeight, 0.6), trim(ctx))
	end
end

local function buildCapsuleHall(ctx: Ctx, worldId: string)
	local hall = Builder.Model("CapsuleHall", ctx.model)
	local config = Factory.CapsuleHall
	sign(ctx, hall, "Title", Vector3.new(-62, 30, 125.2), Vector3.new(40, 6, 0.6), CFrame.identity, "CAPSULE HALL", Enum.NormalId.Back)
	local runs = Builder.Folder("Runs", hall)

	-- Decoration only (capsules ride the WP_ waypoints): planks and supports do
	-- not collide, so players cross the hall freely and the camera never pops.
	local deco = trim(ctx)
	deco.CanCollide = false
	deco.CanQuery = false

	local function track(parent: Instance, points: { Vector3 })
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local down = Vector3.new(0, -1.05, 0)
			beam(ctx, parent, a + down, b + down, 1.8, 0.2, deco)
			local dir = (b - a)
			local side = Vector3.new(-dir.Z, 0, dir.X).Unit
			beam(ctx, parent, a + side * 1.0 + down * 0.6, b + side * 1.0 + down * 0.6, 0.18, 0.5, neon(ctx))
			beam(ctx, parent, a - side * 1.0 + down * 0.6, b - side * 1.0 + down * 0.6, 0.18, 0.5, neon(ctx))
			if b.Y > 2 then
				pipe(ctx, parent, Vector3.new(b.X, 0, b.Z), b + down * 1.2, 0.25, deco)
			end
		end
	end

	-- Marble runs only ever roll downhill: the chutes release at 8.5 / 8.3, so
	-- the funnel and the shared run are clamped to keep dropping from there.
	local funnel = Vector3.new(config.Funnel.X, math.min(config.Funnel.Y, 8), config.Funnel.Z)
	local sharedRun = { funnel }
	for j = 2, #config.SharedRun do
		local p = config.SharedRun[j]
		sharedRun[j] = Vector3.new(p.X, math.min(p.Y, sharedRun[j - 1].Y - 0.3), p.Z)
	end

	local function waypoints(folder: Folder, points: { Vector3 })
		for i, p in points do
			box(ctx, folder, string.format("WP_%02d", i), p, Vector3.new(0.3, 0.3, 0.3), {
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
			})
		end
	end

	local capsules = Capsules.ForWorld(worldId)
	for i, capsule in capsules do
		local x = config.MachineXs[i]
		if not x then
			break
		end
		local z = config.MachineZ
		local machine = Builder.Model("Machine_" .. capsule.Id, hall)
		machine:SetAttribute("CapsuleId", capsule.Id)
		box(ctx, machine, "Cabinet", Vector3.new(x, 3.5, z), Vector3.new(11, 7, 10), {
			Color = ctx.theme.Wall:Lerp(capsule.Color, 0.25),
			Material = Enum.Material.SmoothPlastic,
		})
		box(ctx, machine, "Panel", Vector3.new(x, 3.5, z - 5.05), Vector3.new(9, 4.5, 0.1), {
			Material = Enum.Material.Neon,
			Color = capsule.Color,
			Transparency = 0.3,
			CanCollide = false,
		})
		cylY(ctx, machine, "DomeRing", Vector3.new(x, 7.2, z), 0.5, 10.6, trim(ctx))
		part(ctx, machine, {
			Name = "Dome",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 10,
			CFrame = CFrame.new(x, 9.5, z),
			Material = Enum.Material.Glass,
			Color = capsule.Color:Lerp(Color3.new(1, 1, 1), 0.7),
			Transparency = 0.75,
			CanCollide = false,
			CastShadow = false,
		})
		box(ctx, machine, "DomeCenter", Vector3.new(x, 9.5, z), Vector3.new(0.4, 0.4, 0.4), {
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		})
		box(ctx, machine, "Chute", Vector3.new(x, 8.6, z - 5.6), Vector3.new(2.6, 1.6, 2), {
			Color = Color3.fromRGB(20, 20, 26),
			Material = Enum.Material.SmoothPlastic,
		})
		local signPart = sign(ctx, machine, "Sign", Vector3.new(x, 16.5, z), Vector3.new(11, 2.8, 0.5), CFrame.identity, string.upper(capsule.Name), Enum.NormalId.Front, capsule.Color)
		signPart:SetAttribute("NightOnly", capsule.NightOnly == true)
		local console = box(ctx, machine, "Console", Vector3.new(x, 1.75, z - 8), Vector3.new(4, 3.5, 1.5), {
			Color = ctx.theme.Wall,
			Material = ctx.theme.TrimMaterial,
		})
		prompt(console, "Capsule", capsule.Id, "Open", capsule.Name, 12)

		local run = Builder.Folder("Run_" .. capsule.Id, runs)
		local points = {
			Vector3.new(x, 8.5, z - 6.2),
			Vector3.new(x, 8.3, z - 12),
			funnel,
		}
		for j = 2, #sharedRun do
			table.insert(points, sharedRun[j])
		end
		waypoints(run, points)
		track(run, { points[1], points[2], points[3] })
	end
	local shared = Builder.Folder("SharedTrack", hall)
	track(shared, sharedRun)
	cylY(ctx, hall, "Funnel", funnel + Vector3.new(0, -0.8, 0), 0.6, 4, neon(ctx, ctx.theme.NeonAlt))

	cylY(ctx, hall, "RevealPad", config.RevealPad + Vector3.new(0, 0.4, 0), 0.8, 8, trim(ctx))
	cylY(ctx, hall, "RevealGlow", config.RevealPad + Vector3.new(0, 0.36, 0), 0.68, 8.8, neon(ctx))
end

local function buildPaintShop(ctx: Ctx)
	local shop = Builder.Model("PaintShop", ctx.model)
	local config = Factory.PaintShop
	sign(ctx, shop, "Title", Vector3.new(62, 30, 125.2), Vector3.new(40, 6, 0.6), CFrame.identity, "PAINT SHOP", Enum.NormalId.Back)
	local z = config.LineZ
	local h = config.LineHeight
	belt(ctx, shop, "Line", Vector3.new(config.LineStartX, h, z), Vector3.new(config.LineEndX, h, z), 6, h, 6)

	-- The paint camera looks across the line from the -Z side and tracks the
	-- vacuum, so the booth is open towards it: the pillars stand 8 studs either
	-- side of the spray plane (clear of the camera axis while the vacuum is in
	-- the spray zone), with a glass back panel and the side nozzles on drop pipes.
	local booth = Builder.Model("Booth", shop)
	local bx = config.BoothX
	for _, dx in { -8, 8 } do
		for _, dz in { -5.5, 5.5 } do
			box(ctx, booth, "Pillar", Vector3.new(bx + dx, 7, z + dz), Vector3.new(2, 14, 1), trim(ctx))
		end
	end
	box(ctx, booth, "Curtain", Vector3.new(bx, 8, z + 5.5), Vector3.new(13.9, 10, 0.2), glass(ctx, 0.7))
	box(ctx, booth, "Top", Vector3.new(bx, 14.5, z), Vector3.new(18, 1.5, 12), trim(ctx))
	box(ctx, booth, "TopGlow", Vector3.new(bx, 13.7, z), Vector3.new(18.2, 0.2, 12.2), neon(ctx, ctx.theme.NeonAlt))
	local arm = trim(ctx)
	arm.Name = "NozzleArm"
	-- side nozzles sit high enough to stay above the camera's view of the vacuum
	local sideNozzleY = 10.5
	for _, dz in { -5, 5 } do
		pipe(ctx, booth, Vector3.new(bx, 13.75, z + dz), Vector3.new(bx, sideNozzleY, z + dz), 0.2, arm)
	end
	local nozzles = Builder.Folder("Nozzles", shop)
	local nozzleSpots = {
		{ Vector3.new(bx, sideNozzleY, z - 5), Vector3.new(bx, 4, z) },
		{ Vector3.new(bx, sideNozzleY, z + 5), Vector3.new(bx, 4, z) },
		{ Vector3.new(bx - 1.5, 13.5, z - 2), Vector3.new(bx, 4, z) },
		{ Vector3.new(bx - 1.5, 13.5, z + 2), Vector3.new(bx, 4, z) },
	}
	for i, spot in nozzleSpots do
		local nozzle = pipe(ctx, nozzles, spot[1], spot[1] + (spot[2] - spot[1]).Unit * 1.4, 0.35, { Color = Color3.fromRGB(40, 40, 46), Material = Enum.Material.Metal })
		nozzle.Name = "Nozzle_" .. i
		nozzle:SetAttribute("Aim", world(ctx, spot[2]))
		CollectionService:AddTag(nozzle, "SprayNozzle")
	end

	local console = box(ctx, shop, "Console", config.Console + Vector3.new(0, 1.75, 0), Vector3.new(4, 3.5, 1.5), {
		Color = ctx.theme.Wall,
		Material = ctx.theme.TrimMaterial,
	})
	prompt(console, "Paint", nil, "Customize", "Paint Shop", 12)

	-- Swatch wall
	local swatches = Builder.Folder("Swatches", shop)
	local skins = Cosmetics.BySlot("Skin")
	for i, skin in skins do
		local x = 30 + (i - 1) * (64 / math.max(#skins - 1, 1))
		box(ctx, swatches, "Swatch", Vector3.new(x, 8, 218.6), Vector3.new(5, 5, 0.4), {
			Color = skin.Body or Color3.new(1, 1, 1),
			Material = skin.Material or Enum.Material.SmoothPlastic,
		})
		box(ctx, swatches, "SwatchGlow", Vector3.new(x, 5.2, 218.6), Vector3.new(5, 0.5, 0.5), {
			Color = skin.Glow or Color3.new(1, 1, 1),
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
	end
end

local function buildVault(ctx: Ctx)
	local vault = Builder.Model("TrophyVault", ctx.model)
	local config = Factory.TrophyVault
	local door = config.DoorCenter
	for _, p in Builder.Ring(worldCf(ctx, CFrame.new(door.X, door.Y, door.Z - 1.4)), config.DoorRadius + 1.2, 2.2, 2.2, 24, trim(ctx)) do
		p.Parent = vault
	end
	for _, p in Builder.Ring(worldCf(ctx, CFrame.new(door.X, door.Y, door.Z - 2.6)), config.DoorRadius + 2.6, 0.4, 0.4, 24, neon(ctx, Color3.fromRGB(255, 200, 60))) do
		p.Parent = vault
	end
	-- The round frame sits in a rectangular doorway: wall-coloured fillers inside
	-- the wall close the four corners the frame ring does not reach. Each one is
	-- a box pointing from the door centre at its corner; its inner edge stays
	-- behind the frame ring (radius + 0.8 .. + 2.3), clear of the door opening.
	local frameInner = config.DoorRadius + 0.8
	local frameOuter = config.DoorRadius + 2.3
	for _, corner in { Vector2.new(-1, 0), Vector2.new(1, 0), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		local rel = Vector2.new(corner.X * VAULT_DOORWAY.X / 2 - door.X, corner.Y * VAULT_DOORWAY.Y - door.Y)
		local u = rel.Unit
		local t = Vector2.new(-u.Y, u.X)
		-- where the ring's outer edge meets the doorway's horizontal and vertical edge
		local onRow = Vector2.new(math.sign(rel.X) * math.sqrt(math.max(frameOuter * frameOuter - rel.Y * rel.Y, 0)), rel.Y)
		local onSide = Vector2.new(rel.X, math.sign(rel.Y) * math.sqrt(math.max(frameOuter * frameOuter - rel.X * rel.X, 0)))
		local t0 = math.min(onRow:Dot(t), onSide:Dot(t)) - 0.2
		local t1 = math.max(onRow:Dot(t), onSide:Dot(t)) + 0.2
		local r0, r1 = frameInner, rel.Magnitude + 0.4
		local mid = u * ((r0 + r1) / 2) + t * ((t0 + t1) / 2)
		box(ctx, vault, "DoorFiller", Vector3.new(door.X + mid.X, door.Y + mid.Y, door.Z), Vector3.new(t1 - t0, r1 - r0, WALL_T - 0.1), {
			Rotation = CFrame.Angles(0, 0, math.atan2(-u.X, u.Y)),
			Color = ctx.theme.Wall,
			Material = ctx.theme.WallMaterial,
		})
	end
	box(ctx, vault, "DoorAnchor", Vector3.new(door.X, door.Y, door.Z - 1.4), Vector3.new(0.5, 0.5, 0.5), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})
	local console = box(ctx, vault, "Console", config.PromptSpot + Vector3.new(-12, -2.25, 0), Vector3.new(3, 3.5, 1.5), {
		Color = ctx.theme.Wall,
		Material = ctx.theme.TrimMaterial,
	})
	prompt(console, "Vault", nil, "Open", "Trophy Vault", 14)
	sign(ctx, vault, "Title", Vector3.new(0, 26, 148.6), Vector3.new(30, 5, 0.6), CFrame.identity, "TROPHY VAULT", Enum.NormalId.Front, Color3.fromRGB(255, 210, 80))
	box(ctx, vault, "Carpet", Vector3.new(0, 0.06, 185), Vector3.new(6, 0.1, 68), {
		Color = Color3.fromRGB(150, 24, 40),
		Material = Enum.Material.Fabric,
		CanCollide = false,
	})

	local pedestals = Builder.Folder("Pedestals", vault)
	for i, trophy in Trophies.List do
		local x = config.PedestalXs[(i - 1) % #config.PedestalXs + 1]
		local z = config.PedestalZs[math.ceil(i / #config.PedestalXs)]
		if not z then
			break
		end
		local pedestal = Builder.Model("Pedestal_" .. trophy.Id, pedestals)
		pedestal:SetAttribute("TrophyId", trophy.Id)
		local base = box(ctx, pedestal, "Base", Vector3.new(x, 2, z), Vector3.new(6, 4, 6), {
			Color = Color3.fromRGB(30, 26, 24),
			Material = Enum.Material.Marble,
		})
		box(ctx, pedestal, "Trim", Vector3.new(x, 4.05, z), Vector3.new(6.4, 0.3, 6.4), {
			Color = Color3.fromRGB(255, 200, 60),
			Material = Enum.Material.Metal,
			Reflectance = 0.2,
		})
		-- trophies are rooted here: flush with the gold trim's top (4.2)
		box(ctx, pedestal, "Top", Vector3.new(x, 4.2, z), Vector3.new(0.3, 0.3, 0.3), {
			Rotation = CFrame.lookAt(Vector3.zero, Vector3.new(-x, 0, 0)).Rotation,
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		})
		local facing = if x < 0 then 1 else -1
		box(ctx, pedestal, "Plate", Vector3.new(x + facing * 3.05, 2.2, z), Vector3.new(0.1, 2, 5), {
			Color = Color3.fromRGB(14, 14, 18),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Attributes = { Face = if x < 0 then "Right" else "Left" },
		})
		local spot = box(ctx, pedestal, "Spot", Vector3.new(x, H - 4, z), Vector3.new(1, 1, 1), {
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		})
		Builder.Light(spot, "SpotLight", { Face = Enum.NormalId.Bottom, Angle = 30, Range = 40, Brightness = 3, Color = Color3.fromRGB(255, 230, 180), Shadows = false })
		prompt(base, "Trophy", trophy.Id, "Inspect", trophy.Name, 10)
	end
end

local function buildLobby(ctx: Ctx)
	local lobby = Builder.Model("Lobby", ctx.model)
	local config = Factory.Lobby

	-- Daily crate conveyor
	local hatch = config.CrateHatch
	local pad = config.CratePad
	belt(ctx, lobby, "CrateBelt", Vector3.new(hatch.X + 1, 2, hatch.Z), Vector3.new(pad.X - 3, 2, pad.Z), 6, 2, 5)
	box(ctx, lobby, "CrateHatch", Vector3.new(hatch.X, 4.5, hatch.Z), Vector3.new(0.6, 5, 7), {
		Color = Color3.fromRGB(26, 26, 32),
		Material = Enum.Material.DiamondPlate,
	})
	-- Dark opening on the wall behind the hatch (inside the hatch while it is
	-- shown): when the client hides the hatch, the crate comes out of a hole.
	box(ctx, lobby, "CrateHatchRecess", Vector3.new(hatch.X + 0.05, 4.5, hatch.Z), Vector3.new(0.1, 4.8, 6.8), {
		Color = Color3.fromRGB(6, 6, 8),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	box(ctx, lobby, "CrateHatchFrame", Vector3.new(hatch.X + 0.3, 7.4, hatch.Z), Vector3.new(0.8, 0.6, 8), neon(ctx, ctx.theme.NeonAlt))
	box(ctx, lobby, "CratePad", Vector3.new(pad.X, 1, pad.Z), Vector3.new(6, 2, 6), trim(ctx))
	box(ctx, lobby, "CratePadGlow", Vector3.new(pad.X, 2.02, pad.Z), Vector3.new(5, 0.05, 5), neon(ctx, Color3.fromRGB(255, 200, 70)))
	local console = box(ctx, lobby, "CrateConsole", Vector3.new(pad.X + 1, 1.75, pad.Z + 7), Vector3.new(4, 3.5, 1.5), {
		Color = ctx.theme.Wall,
		Material = ctx.theme.TrimMaterial,
	})
	prompt(console, "DailyCrate", nil, "Mystery Crate", "Daily Deal", 14)
	local screen = box(ctx, lobby, "CrateScreen", Vector3.new(-99, 13, hatch.Z), Vector3.new(0.4, 7, 15), {
		Color = Color3.fromRGB(12, 13, 18),
		Material = Enum.Material.SmoothPlastic,
	})
	screen:SetAttribute("Face", "Right")

	-- Night deals stand
	local stand = Builder.Model("NightStand", lobby)
	local s = config.NightStand
	box(ctx, stand, "Counter", s + Vector3.new(0, 1.75, 2), Vector3.new(14, 3.5, 4), trim(ctx))
	box(ctx, stand, "CounterGlow", s + Vector3.new(0, 3.35, 2), Vector3.new(14.2, 0.15, 4.2), neon(ctx, ctx.theme.NightNeon))
	for _, dx in { -6.5, 6.5 } do
		box(ctx, stand, "Post", s + Vector3.new(dx, 5, 3.5), Vector3.new(0.6, 10, 0.6), trim(ctx))
	end
	box(ctx, stand, "Canopy", s + Vector3.new(0, 10.2, 2.5), Vector3.new(15, 0.6, 6), {
		Color = Color3.fromRGB(30, 26, 60),
		Material = Enum.Material.SmoothPlastic,
	})
	local nightSign = box(ctx, stand, "NightSign", s + Vector3.new(0, 12.2, 1), Vector3.new(14, 3, 0.4), {
		Color = Color3.fromRGB(10, 10, 20),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	Builder.Sign(nightSign, Enum.NormalId.Front, "NIGHT DEALS", { TextColor = ctx.theme.NightNeon })
	prompt(stand:FindFirstChild("Counter") :: BasePart, "NightDeals", nil, "Browse", "Night Deals", 12)

	-- Info board facing the street door, on two posts. The reader faces +Z, so
	-- the Upgrade Lab (+X) is on their left and the Test Lab (-X) on their right.
	local board = box(ctx, lobby, "InfoBoard", config.InfoBoard + Vector3.new(0, 6, 0), Vector3.new(16, 9, 0.6), {
		Color = Color3.fromRGB(12, 13, 18),
		Material = Enum.Material.SmoothPlastic,
	})
	for _, dx in { -8.3, 8.3 } do
		box(ctx, lobby, "InfoPost", config.InfoBoard + Vector3.new(dx, 5.45, 0), Vector3.new(0.6, 10.9, 0.8), trim(ctx))
	end
	Builder.Sign(board, Enum.NormalId.Front, "SHOWROOM ↑\nUPGRADES ←   TEST LAB →\nCAPSULES · PAINT · VAULT ↑↑", {
		TextColor = ctx.theme.Neon,
		PixelsPerStud = 20,
		Font = Enum.Font.GothamBold,
	})
end

-- Public ----------------------------------------------------------------------

function FactoryBuilder.Build(worldId: string, origin: CFrame, parent: Instance): Model
	local worldDef = Worlds.Get(worldId)
	assert(worldDef, "Unknown world " .. worldId)
	local theme = Worlds.Theme(worldId)

	local model = Instance.new("Model")
	model.Name = "MegaFactory_" .. worldId
	model:SetAttribute("World", worldId)
	model:SetAttribute("Theme", theme.Id)
	model:SetAttribute("Size", Factory.Size)

	-- Everything (including the Origin part the client maps from) uses the lifted origin.
	local lifted = origin * CFrame.new(0, GROUND_CLEARANCE, 0)
	local ctx: Ctx = { origin = lifted, theme = theme, model = model }

	Builder.Part({
		Name = "Origin",
		Size = Vector3.new(1, 1, 1),
		CFrame = lifted,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = model,
	})
	model.PrimaryPart = model:FindFirstChild("Origin") :: BasePart

	buildShell(ctx)
	buildFacade(ctx, worldDef.Name)
	buildEntrance(ctx)
	buildRoof(ctx)
	buildShowroom(ctx, worldId)
	buildTestChamber(ctx)
	buildUpgradeLab(ctx)
	buildCapsuleHall(ctx, worldId)
	buildPaintShop(ctx)
	buildVault(ctx)
	buildLobby(ctx)

	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = parent
	return model
end

return FactoryBuilder
