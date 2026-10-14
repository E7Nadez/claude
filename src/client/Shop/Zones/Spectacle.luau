-- The "money shot" layer of the factory, all client-side and distance culled:
--   * marquee chase lights around the main sign + flicker power-on
--   * sweeping searchlights at night
--   * twin holograms of the world's mythic vacuum flanking the entrance
--   * delivery drones looping over the roof (synced by server time)
--   * god rays through the skylights + floating dust motes in the showroom
--   * air flow and leaves sucked into the intake tube, chasing plaza arrows
--   * fireworks above the factory for big purchases (anyone's)

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Definitions = Shared.Definitions
local Vacuums = require(Definitions.Vacuums)
local Factory = require(Definitions.Factory)
local Trash = require(Definitions.Trash)
local Worlds = require(Definitions.Worlds)
local DayNight = require(Shared.Util.DayNight)
local Builder = require(Shared.Util.Builder)
local Trove = require(Shared.Util.Trove)
local VacuumModel = require(Shared.Models.VacuumModel)

local ShopFolder = script.Parent.Parent
local Effects = require(ShopFolder.Effects)
local Audio = require(ShopFolder.Audio)

local Spectacle = {}
Spectacle.__index = Spectacle

local function localPart(parent: Instance, props: { [string]: any }): BasePart
	local p = table.clone(props)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return Builder.Part(p)
end

function Spectacle.new(view)
	local self = setmetatable({}, Spectacle)
	self.View = view
	self.Trove = Trove.new()
	self.ActiveTrove = Trove.new()
	self.Trove:Add(self.ActiveTrove, "Clean")
	self.LastFireworks = 0
	return self
end

-- Marquee ---------------------------------------------------------------------------

function Spectacle:_marquee()
	local sign = self.View:Find("Facade/MainSign")
	if not sign or not sign:IsA("BasePart") then
		return
	end
	local theme = self.View.Theme
	local half = sign.Size / 2 + Vector3.new(1.6, 1.6, 0)
	local spacing = if Effects.IsLow() then 4.8 else 2.4
	local points = {}
	local function edge(a: Vector3, b: Vector3)
		local length = (b - a).Magnitude
		local steps = math.max(1, math.floor(length / spacing))
		for i = 0, steps - 1 do
			table.insert(points, a:Lerp(b, i / steps))
		end
	end
	local z = -half.Z - 0.4
	local tl, tr = Vector3.new(-half.X, half.Y, z), Vector3.new(half.X, half.Y, z)
	local br, bl = Vector3.new(half.X, -half.Y, z), Vector3.new(-half.X, -half.Y, z)
	edge(tl, tr)
	edge(tr, br)
	edge(br, bl)
	edge(bl, tl)
	local bulbs = {}
	for _, p in points do
		local bulb = localPart(self.View.LocalFolder, {
			Name = "Bulb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.75,
			CFrame = sign.CFrame * CFrame.new(p),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(40, 36, 30),
		})
		self.ActiveTrove:Add(bulb)
		table.insert(bulbs, bulb)
	end
	self.Bulbs = bulbs
	self.BulbOn = if theme.Id == "Brass" then Color3.fromRGB(255, 214, 140) else Color3.fromRGB(255, 250, 235)
	self.BulbAlt = theme.NeonAlt
	self.BulbOff = Color3.fromRGB(40, 36, 30)
	self.MarqueeReady = false

	-- Power-on: title flickers, bulbs light up in a wave around the sign
	local title = sign:FindFirstChild("Title")
	local label = title and title:FindFirstChild("Text")
	task.spawn(function()
		if label and label:IsA("TextLabel") then
			for _, t in { 1, 0, 1, 0.6, 1, 0.2, 0.8, 0 } do
				label.TextTransparency = t
				task.wait(0.07)
			end
		end
	end)
	task.spawn(function()
		for i, bulb in bulbs do
			if not bulb.Parent then
				return
			end
			bulb.Color = self.BulbOn
			if i % 4 == 0 then
				task.wait()
			end
		end
		self.MarqueeReady = true
	end)
end

function Spectacle:_stepMarquee(t: number)
	if not self.Bulbs or not self.MarqueeReady then
		return
	end
	local phase = math.floor(t * 9)
	if phase == self.MarqueePhase then
		return
	end
	self.MarqueePhase = phase
	-- every 20 s the pattern switches to a two-color sparkle
	local sparkle = math.floor(t / 20) % 2 == 1
	for i, bulb in self.Bulbs do
		local on
		if sparkle then
			on = ((i * 7 + phase * 3) % 5) < 2
			bulb.Color = if on then (if i % 2 == 0 then self.BulbOn else self.BulbAlt) else self.BulbOff
		else
			on = ((i + phase) % 4) < 2
			bulb.Color = if on then self.BulbOn else self.BulbOff
		end
	end
end

-- Searchlights --------------------------------------------------------------------------

function Spectacle:_searchlights()
	local theme = self.View.Theme
	local spots = { Vector3.new(-94, 44, 6), Vector3.new(94, 44, 6), Vector3.new(-94, 44, 214), Vector3.new(94, 44, 214) }
	local count = if Effects.IsLow() then 2 else #spots
	self.Searchlights = {}
	for i = 1, count do
		local pos = self.View:ToWorld(spots[i])
		local base = localPart(self.View.LocalFolder, {
			Name = "SearchlightBase",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.4, 3, 3),
			CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2),
			Material = Enum.Material.Metal,
			Color = theme.Metal,
		})
		local head = localPart(self.View.LocalFolder, {
			Name = "SearchlightHead",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.2, 2.6, 2.6),
			CFrame = CFrame.new(pos + Vector3.new(0, 1.8, 0)),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(60, 60, 70),
		})
		local a0 = Instance.new("Attachment")
		a0.Parent = head
		local a1 = Instance.new("Attachment")
		a1.Parent = workspace.Terrain
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(if i % 2 == 0 then theme.NightNeon else Color3.fromRGB(235, 240, 255))
		beam.LightEmission = 1
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Width0 = 2.4
		beam.Width1 = 26
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
		beam.Enabled = false
		beam.Parent = a0
		self.ActiveTrove:Add(base)
		self.ActiveTrove:Add(head)
		self.ActiveTrove:Add(a1)
		table.insert(self.Searchlights, { Head = head, Tip = a1, Beam = beam, Phase = i * 1.9, Pos = pos + Vector3.new(0, 1.8, 0), Outward = ((pos - self.View:ToWorld(Vector3.new(0, 44, 110))) * Vector3.new(1, 0, 1)).Unit })
	end
end

function Spectacle:_stepSearchlights(t: number, night: number)
	if not self.Searchlights then
		return
	end
	for _, light in self.Searchlights do
		local on = night > 0.05
		light.Beam.Enabled = on
		light.Head.Color = if on then light.Beam.Color.Keypoints[1].Value else Color3.fromRGB(60, 60, 70)
		if on then
			local yaw = math.atan2(light.Outward.Z, light.Outward.X) + math.sin(t * 0.28 + light.Phase) * 1.1
			local pitch = 1.0 + math.sin(t * 0.19 + light.Phase * 2) * 0.28
			local dir = Vector3.new(math.cos(yaw) * math.cos(pitch), math.sin(pitch), math.sin(yaw) * math.cos(pitch))
			light.Tip.WorldPosition = light.Pos + dir * 260
			light.Head.CFrame = CFrame.lookAt(light.Pos, light.Pos + dir) * CFrame.Angles(0, math.pi / 2, 0)
			light.Beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1 - 0.55 * night), NumberSequenceKeypoint.new(1, 1) })
		end
	end
end

-- Holograms ---------------------------------------------------------------------------------

function Spectacle:_holograms()
	local mythic = nil
	for _, vacuum in Vacuums.ForWorld(self.View.World) do
		mythic = vacuum
	end
	if not mythic then
		return
	end
	local theme = self.View.Theme
	self.Holos = {}
	for _, x in { -30, 30 } do
		local basePos = self.View:ToWorld(Vector3.new(x, 0, -30))
		local projector = localPart(self.View.LocalFolder, {
			Name = "HoloProjector",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.2, 6, 6),
			CFrame = CFrame.new(basePos + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Material = Enum.Material.Metal,
			Color = theme.Trim,
		})
		local lens = localPart(self.View.LocalFolder, {
			Name = "HoloLens",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 4, 4),
			CFrame = CFrame.new(basePos + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Material = Enum.Material.Neon,
			Color = theme.Neon,
		})
		self.ActiveTrove:Add(projector)
		self.ActiveTrove:Add(lens)
		local model = VacuumModel.Build(mythic.Id, { Scale = 2.1 })
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part ~= model.PrimaryPart then
				part.Material = Enum.Material.ForceField
				part.Color = theme.Neon:Lerp(Color3.new(1, 1, 1), 0.25)
				part.Transparency = 0
				part.CastShadow = false
			end
		end
		model.Parent = self.View.LocalFolder
		self.ActiveTrove:Add(model)
		local scan = localPart(self.View.LocalFolder, {
			Name = "HoloScan",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, 12, 12),
			CFrame = CFrame.new(basePos) * CFrame.Angles(0, 0, math.pi / 2),
			Material = Enum.Material.Neon,
			Color = theme.Neon,
			Transparency = 0.6,
		})
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0.2, 0, 0)
		a0.Parent = lens
		local a1 = Instance.new("Attachment")
		a1.Parent = workspace.Terrain
		a1.WorldPosition = basePos + Vector3.new(0, 9, 0)
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(theme.Neon)
		beam.LightEmission = 1
		beam.FaceCamera = true
		beam.Width0 = 3
		beam.Width1 = 13
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.95) })
		beam.Parent = a0
		self.ActiveTrove:Add(a1)
		self.ActiveTrove:Add(scan)
		table.insert(self.Holos, { Model = model, Base = basePos, Scan = scan, Phase = x })
	end
end

function Spectacle:_stepHolos(t: number)
	if not self.Holos then
		return
	end
	for _, holo in self.Holos do
		local bob = math.sin(t * 1.3 + holo.Phase) * 0.6
		holo.Model:PivotTo(CFrame.new(holo.Base + Vector3.new(0, 7 + bob, 0)) * CFrame.Angles(0, t * 0.6 + holo.Phase, 0))
		local scanT = ((t + holo.Phase * 0.05) % 2.6) / 2.6
		holo.Scan.CFrame = CFrame.new(holo.Base + Vector3.new(0, 6 + scanT * 12, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		holo.Scan.Transparency = 0.45 + scanT * 0.5
	end
end

-- Drones ----------------------------------------------------------------------------------

local function buildDrone(parent: Instance, theme): (Model, { { Part: BasePart, Rel: CFrame, Rotor: boolean } })
	local model = Instance.new("Model")
	model.Name = "Drone"
	local parts = {}
	local function add(props, rotor: boolean?)
		local p = localPart(model, props)
		table.insert(parts, { Part = p, Rel = props.CFrame, Rotor = rotor == true })
		return p
	end
	add({ Name = "Body", Size = Vector3.new(2.2, 0.7, 2.2), CFrame = CFrame.new(), Material = Enum.Material.Metal, Color = theme.Metal })
	add({ Name = "Dome", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.3, CFrame = CFrame.new(0, 0.4, 0), Material = Enum.Material.Glass, Color = theme.Glass, Transparency = 0.3 })
	add({ Name = "Glow", Size = Vector3.new(1.6, 0.1, 1.6), CFrame = CFrame.new(0, -0.4, 0), Material = Enum.Material.Neon, Color = theme.Neon })
	for i, corner in { Vector3.new(1.6, 0.2, 1.6), Vector3.new(-1.6, 0.2, 1.6), Vector3.new(1.6, 0.2, -1.6), Vector3.new(-1.6, 0.2, -1.6) } do
		add({ Name = "Arm", Size = Vector3.new(0.25, 0.2, 2.3), CFrame = CFrame.lookAt(corner / 2, corner) })
		add({ Name = "Rotor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, 1.9, 1.9), CFrame = CFrame.new(corner) * CFrame.Angles(0, 0, math.pi / 2), Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(30, 30, 36), Transparency = 0.45 }, true)
		add({ Name = if i % 2 == 0 then "NavRed" else "NavGreen", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.3, CFrame = CFrame.new(corner + Vector3.new(0, -0.2, 0)), Material = Enum.Material.Neon, Color = if i <= 2 then Color3.fromRGB(255, 50, 50) else Color3.fromRGB(50, 255, 90) })
	end
	add({ Name = "Cable", Size = Vector3.new(0.08, 2.4, 0.08), CFrame = CFrame.new(0, -1.6, 0), Color = Color3.fromRGB(30, 30, 30) })
	add({ Name = "Cargo", Size = Vector3.new(1.6, 1.4, 1.6), CFrame = CFrame.new(0, -3.4, 0), Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(170, 120, 70) })
	add({ Name = "CargoBand", Size = Vector3.new(1.7, 0.2, 1.7), CFrame = CFrame.new(0, -3.4, 0), Material = Enum.Material.Neon, Color = theme.NeonAlt })
	model.Parent = parent
	return model, parts
end

function Spectacle:_drones()
	local count = if Effects.IsLow() then 1 else 3
	self.Drones = {}
	for i = 1, count do
		local model, parts = buildDrone(self.View.LocalFolder, self.View.Theme)
		self.ActiveTrove:Add(model)
		table.insert(self.Drones, { Parts = parts, Offset = i * 2.1, Last = nil :: Vector3? })
	end
end

function Spectacle:_stepDrones(serverTime: number, t: number, parts: { BasePart }, frames: { CFrame })
	if not self.Drones then
		return
	end
	local center = Vector3.new(0, 64, 110)
	for i, drone in self.Drones do
		local s = serverTime * 0.07 + drone.Offset
		local localPos = center + Vector3.new(math.sin(s) * 84, math.sin(s * 3) * 4 + i * 3, math.sin(s * 2) * 74)
		local ahead = center + Vector3.new(math.sin(s + 0.05) * 84, math.sin((s + 0.05) * 3) * 4 + i * 3, math.sin((s + 0.05) * 2) * 74)
		local pos = self.View:ToWorld(localPos)
		local dir = self.View:ToWorld(ahead) - pos
		local cf = CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z)) * CFrame.Angles(-0.18, 0, math.sin(t * 1.3 + i) * 0.05)
		local blink = math.floor(t * 2 + i) % 2 == 0
		for _, entry in drone.Parts do
			local rel = entry.Rel
			if entry.Rotor then
				rel = CFrame.new(rel.Position) * CFrame.Angles(0, t * 40, 0) * rel.Rotation
			end
			if entry.Part.Name == "NavRed" or entry.Part.Name == "NavGreen" then
				entry.Part.Transparency = if blink then 0 else 0.8
			end
			if entry.Part.Name == "Cable" or entry.Part.Name == "Cargo" or entry.Part.Name == "CargoBand" then
				rel = CFrame.Angles(0.18, 0, 0) * rel * CFrame.Angles(0, t * 0.4, 0)
			end
			table.insert(parts, entry.Part)
			table.insert(frames, cf * rel)
		end
	end
end

-- Showroom atmosphere --------------------------------------------------------------------------

function Spectacle:_godRays()
	local xs = if Effects.IsLow() then { -25, 25 } else { -70, -25, 0, 25, 70 }
	self.Rays = {}
	for _, gapZ in { 56, 114 } do
		for _, x in xs do
			local top = Instance.new("Attachment")
			top.Parent = workspace.Terrain
			top.WorldPosition = self.View:ToWorld(Vector3.new(x, 41, gapZ))
			local bottom = Instance.new("Attachment")
			bottom.Parent = workspace.Terrain
			local beam = Instance.new("Beam")
			beam.Attachment0 = top
			beam.Attachment1 = bottom
			beam.Color = ColorSequence.new(Color3.fromRGB(255, 244, 220))
			beam.LightEmission = 0.7
			beam.FaceCamera = true
			beam.Width0 = 9
			beam.Width1 = 13
			beam.Segments = 1
			beam.Parent = top
			self.ActiveTrove:Add(top)
			self.ActiveTrove:Add(bottom)
			table.insert(self.Rays, { Top = top, Bottom = bottom, Beam = beam })
		end
	end
end

function Spectacle:_updateGodRays(night: number)
	if not self.Rays then
		return
	end
	local sun = Lighting:GetSunDirection()
	local visible = sun.Y > 0.12 and night < 0.5
	for _, ray in self.Rays do
		ray.Beam.Enabled = visible
		if visible then
			local top = ray.Top.WorldPosition
			local drop = top.Y - self.View.Origin.Position.Y
			ray.Bottom.WorldPosition = top - sun * (drop / sun.Y)
			local strength = math.clamp((sun.Y - 0.12) * 2, 0, 1) * (1 - night)
			ray.Beam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1 - 0.18 * strength),
				NumberSequenceKeypoint.new(0.6, 1 - 0.1 * strength),
				NumberSequenceKeypoint.new(1, 1),
			})
		end
	end
end

function Spectacle:_motes()
	if Effects.IsLow() then
		return
	end
	local volume = localPart(self.View.LocalFolder, {
		Name = "MoteVolume",
		Size = Vector3.new(80, 24, 80),
		CFrame = self.View:WorldCFrame(CFrame.new(0, 13, 82)),
		Transparency = 1,
	})
	local emitter = Effects.Emitter(volume, "Mote", Color3.fromRGB(255, 236, 200), 14)
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Enabled = true
	self.ActiveTrove:Add(volume)
end

-- Entrance -----------------------------------------------------------------------------------

function Spectacle:_intake()
	local config = Factory.Entrance
	local mouth = self.View:ToWorld(config.Mouth - Vector3.new(0, 0, 6.5))
	local inward = self.View.Origin.LookVector
	local holder = localPart(self.View.LocalFolder, {
		Name = "IntakeFlow",
		Size = Vector3.new(config.MouthRadius * 2, config.MouthRadius * 2, 0.2),
		CFrame = CFrame.lookAt(mouth, mouth + inward),
		Transparency = 1,
	})
	local flow = Effects.Emitter(holder, "Suction", self.View.Theme.Neon, if Effects.IsLow() then 10 else 28)
	flow.Shape = Enum.ParticleEmitterShape.Disc
	flow.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	flow.EmissionDirection = Enum.NormalId.Back
	flow.Speed = NumberRange.new(-14, -8)
	flow.Lifetime = NumberRange.new(0.6, 1)
	flow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0.05) })
	flow.Enabled = true
	self.ActiveTrove:Add(holder)

	local world = Worlds.Get(self.View.World)
	local set = Trash.Get(if world then world.TrashSet else "Cleanville")
	self.Leaves = {}
	local rng = Random.new()
	for i = 1, if Effects.IsLow() then 3 else 7 do
		local def = set[((i - 1) % 3) + 1]
		local leaf = localPart(self.View.LocalFolder, {
			Name = "IntakeLeaf",
			ClassName = if def.Shape == "Wedge" then "WedgePart" else "Part",
			Size = def.Size * 0.8,
			Color = def.Color,
			Material = def.Material,
		})
		self.ActiveTrove:Add(leaf)
		table.insert(self.Leaves, { Part = leaf, T = rng:NextNumber(0, 1), Speed = rng:NextNumber(0.25, 0.45), Start = Vector3.zero, Spin = rng:NextNumber(2, 6) })
	end
	self.Mouth = self.View:ToWorld(config.Mouth)
	for _, leaf in self.Leaves do
		self:_respawnLeaf(leaf, rng)
	end
	self.Rng = rng

	self.Arrows = {}
	local shell = self.View:Find("Shell")
	if shell then
		for _, child in shell:GetChildren() do
			if child.Name == "PlazaArrow" and child:IsA("BasePart") then
				table.insert(self.Arrows, child)
			end
		end
		table.sort(self.Arrows, function(a, b)
			return self.View:ToLocal(a.Position).Z < self.View:ToLocal(b.Position).Z
		end)
	end
end

function Spectacle:_respawnLeaf(leaf, rng: Random)
	leaf.Start = self.View:ToWorld(Vector3.new(rng:NextNumber(-22, 22), rng:NextNumber(0.5, 3), rng:NextNumber(-42, -24)))
end

function Spectacle:_stepIntake(dt: number, t: number, parts: { BasePart }, frames: { CFrame })
	if self.Leaves and self.Mouth then
		for _, leaf in self.Leaves do
			leaf.T += dt * leaf.Speed
			if leaf.T >= 1 then
				leaf.T = 0
				self:_respawnLeaf(leaf, self.Rng)
			end
			local e = leaf.T * leaf.T
			local rel = leaf.Start - self.Mouth
			local swirl = CFrame.fromAxisAngle(self.View.Origin.LookVector, e * math.pi * 4)
			local p = self.Mouth + swirl:VectorToWorldSpace(rel * (1 - e)) + Vector3.new(0, math.sin(leaf.T * math.pi) * 3, 0)
			table.insert(parts, leaf.Part)
			table.insert(frames, CFrame.new(p) * CFrame.Angles(t * leaf.Spin, t * leaf.Spin * 0.6, 0))
		end
	end
	if self.Arrows and #self.Arrows > 0 then
		local active = math.floor(t * 4) % (#self.Arrows + 2)
		for i, arrow in self.Arrows do
			arrow.Transparency = if i == active or i == active - 1 then 0 else 0.7
		end
	end
end

-- Fireworks ------------------------------------------------------------------------------------

function Spectacle:Fireworks(colors: { Color3 }, count: number)
	if not self.View.Near or count <= 0 then
		return
	end
	local now = os.clock()
	if now - self.LastFireworks < 2 then
		return
	end
	self.LastFireworks = now
	local n = if Effects.IsLow() then math.max(1, math.floor(count / 3)) else count
	local rng = Random.new()
	for i = 1, n do
		task.delay((i - 1) * rng:NextNumber(0.18, 0.35), function()
			local launch = self.View:ToWorld(Vector3.new(rng:NextNumber(-80, 80), 44, rng:NextNumber(10, 200)))
			local apex = launch + Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(42, 66), rng:NextNumber(-12, 12))
			local color = colors[rng:NextInteger(1, #colors)]
			local rocket = Builder.Part({
				Name = "Rocket",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.7,
				CFrame = CFrame.new(launch),
				Material = Enum.Material.Neon,
				Color = color:Lerp(Color3.new(1, 1, 1), 0.5),
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Parent = workspace,
			})
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, 0.3, 0)
			a0.Parent = rocket
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -0.3, 0)
			a1.Parent = rocket
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
			trail.LightEmission = 1
			trail.Lifetime = 0.5
			trail.FaceCamera = true
			trail.WidthScale = NumberSequence.new(1, 0)
			trail.Parent = rocket
			Audio.PlayAt("Tube", launch, { Speed = 2.2, Volume = 0.25 })
			local tween = TweenService:Create(rocket, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(apex) })
			tween:Play()
			tween.Completed:Wait()
			rocket.Transparency = 1
			Debris:AddItem(rocket, 0.6)
			local burst = Instance.new("Attachment")
			burst.WorldPosition = apex
			burst.Parent = workspace.Terrain
			local main = Effects.Emitter(burst, "Firework", color)
			main:Emit(if Effects.IsLow() then 30 else 90)
			Effects.GlowBall(apex, color, 18, 0.5)
			Effects.FlashLight(apex, color, 10, 80, 0.7)
			Audio.PlayAt("Boom", apex, { Volume = 0.45, Speed = rng:NextNumber(0.75, 1.1) })
			task.delay(0.45, function()
				local glitter = Effects.Emitter(burst, "Glitter", Color3.new(1, 1, 1))
				glitter:Emit(if Effects.IsLow() then 12 else 40)
			end)
			Debris:AddItem(burst, 4)
		end)
	end
end

-- Lifecycle -------------------------------------------------------------------------------------

function Spectacle:SetActive(active: boolean)
	self.ActiveTrove:Clean()
	self.Bulbs = nil
	self.Searchlights = nil
	self.Holos = nil
	self.Drones = nil
	self.Rays = nil
	self.Leaves = nil
	self.Arrows = nil
	self.MarqueePhase = nil
	if not active then
		return
	end
	self:_marquee()
	self:_searchlights()
	self:_holograms()
	self:_drones()
	self:_godRays()
	self:_motes()
	self:_intake()

	local accumulator = 0
	local slowTimer = 0
	local start = os.clock()
	local night = DayNight.NightAlpha()
	self:_updateGodRays(night)
	self.ActiveTrove:Connect(RunService.Heartbeat, function(dt)
		accumulator += dt
		slowTimer -= dt
		if accumulator < (if Effects.IsLow() then 1 / 20 else 1 / 40) then
			return
		end
		local elapsed = accumulator
		accumulator = 0
		local t = os.clock() - start
		if slowTimer <= 0 then
			slowTimer = 1.5
			night = DayNight.NightAlpha()
			self:_updateGodRays(night)
		end
		local parts, frames = {}, {}
		self:_stepMarquee(t)
		self:_stepSearchlights(t, night)
		self:_stepHolos(t)
		self:_stepDrones(workspace:GetServerTimeNow(), t, parts, frames)
		self:_stepIntake(elapsed, t, parts, frames)
		if #parts > 0 then
			workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

function Spectacle:QualityChanged()
	if self.View.Near then
		self:SetActive(true)
	end
end

function Spectacle:Destroy()
	self.Trove:Clean()
end

return Spectacle
