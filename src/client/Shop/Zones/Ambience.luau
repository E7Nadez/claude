-- The building "breathes": gears turn, pumps pulse, the intake vortex
-- spins, the roof vacuum pulls trash out of the sky, chimneys steam, belts
-- run and the neon switches to its night look. Client only, distance culled.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Builder = require(Shared.Util.Builder)
local DayNight = require(Shared.Util.DayNight)
local Trove = require(Shared.Util.Trove)
local Trash = require(Shared.Definitions.Trash)
local Worlds = require(Shared.Definitions.Worlds)

local Effects = require(script.Parent.Parent.Effects)

local Ambience = {}
Ambience.__index = Ambience

type Spinner = { Parts: { BasePart }, Offsets: { CFrame }, Center: CFrame, Speed: number, Angle: number, Axis: string }
type Belt = { Slats: { BasePart }, Rotation: CFrame, Start: Vector3, Direction: Vector3, Spacing: number, Speed: number, Y: number }

function Ambience.new(view)
	local self = setmetatable({}, Ambience)
	self.View = view
	self.Trove = Trove.new()
	self.ActiveTrove = Trove.new()
	self.Trove:Add(self.ActiveTrove, "Clean")
	self.Spinners = {} :: { Spinner }
	self.Pumps = {} :: { { Part: BasePart, Base: number, Phase: number } }
	self.Belts = {} :: { Belt }
	self.Neon = {} :: { { Part: BasePart, Day: Color3 } }
	self.Bits = {}
	self.ActiveSpinners = {} :: { Spinner }
	self.Time = 0
	self:_collect()
	return self
end

local function captureSpinner(parts: { BasePart }, center: CFrame, speed: number, axis: string): Spinner
	local offsets = {}
	for i, part in parts do
		offsets[i] = center:ToObjectSpace(part.CFrame)
	end
	return { Parts = parts, Offsets = offsets, Center = center, Speed = speed, Angle = 0, Axis = axis }
end

function Ambience:_collect()
	local view = self.View
	for _, gear in view:Tagged("FactoryGear") do
		local center = gear:GetAttribute("Center")
		local parts = {}
		for _, d in gear:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
		if typeof(center) == "CFrame" and #parts > 0 then
			table.insert(self.Spinners, captureSpinner(parts, center, gear:GetAttribute("Speed") or 1, "Z"))
		end
	end

	-- Halo rings above the showroom spin as one group
	local halo = {}
	for _, part in view:Tagged("HaloRing") do
		if part:IsA("BasePart") then
			table.insert(halo, part)
		end
	end
	if #halo > 0 then
		local sum = Vector3.zero
		for _, p in halo do
			sum += p.Position
		end
		local center = CFrame.new(sum / #halo) * view.Origin.Rotation
		table.insert(self.Spinners, captureSpinner(halo, center, 0.3, "Y"))
	end

	for _, pump in view:Tagged("FactoryPump") do
		if pump:IsA("BasePart") then
			table.insert(self.Pumps, { Part = pump, Base = pump:GetAttribute("BaseSize") or pump.Size.X, Phase = pump:GetAttribute("Phase") or 0 })
		end
	end

	for _, belt in view:Tagged("ConveyorBelt") do
		local slatsFolder = belt:FindFirstChild("Slats")
		local start = belt:GetAttribute("BeltStart")
		local direction = belt:GetAttribute("BeltDirection")
		if slatsFolder and typeof(start) == "Vector3" and typeof(direction) == "Vector3" then
			local slats = {}
			for _, slat in slatsFolder:GetChildren() do
				if slat:IsA("BasePart") then
					table.insert(slats, slat)
				end
			end
			table.sort(slats, function(a, b)
				return (a:GetAttribute("Index") or 0) < (b:GetAttribute("Index") or 0)
			end)
			if #slats > 0 then
				table.insert(self.Belts, {
					Slats = slats,
					Rotation = slats[1].CFrame.Rotation,
					Start = start,
					Direction = direction,
					Spacing = slatsFolder:GetAttribute("Spacing") or 2.4,
					Speed = belt:GetAttribute("BeltSpeed") or 4,
					Y = slats[1].Position.Y,
				})
			end
		end
	end

	for _, part in view:Tagged("FactoryNeon") do
		if part:IsA("BasePart") then
			table.insert(self.Neon, { Part = part, Day = part.Color })
		end
	end

	-- Hide the flat server swirl; a real vortex is built locally.
	for _, swirl in view:Tagged("FactorySwirl") do
		if swirl:IsA("BasePart") then
			swirl.LocalTransparencyModifier = 1
			swirl.Transparency = 1
			self.SwirlCFrame = swirl.CFrame
			self.SwirlSize = swirl.Size.X
		end
	end
end

function Ambience:_buildVortex()
	if not self.SwirlCFrame then
		return
	end
	local theme = self.View.Theme
	local parts = {}
	local arms = 3
	local steps = if Effects.IsLow() then 5 else 9
	for arm = 1, arms do
		for i = 1, steps do
			local t = i / steps
			local radius = (self.SwirlSize / 2) * (1 - t * 0.85)
			local angle = (arm / arms) * math.pi * 2 + t * math.pi * 1.6
			local part = Builder.Part({
				Name = "Vortex",
				Size = Vector3.new(1.6 * (1 - t * 0.6), 0.5, 0.2),
				CFrame = self.SwirlCFrame * CFrame.new(math.cos(angle) * radius, math.sin(angle) * radius, -0.2 + t * 0.6) * CFrame.Angles(0, 0, angle + math.pi / 2),
				Material = Enum.Material.Neon,
				Color = theme.Neon:Lerp(theme.NeonAlt, t),
				Transparency = 0.15 + t * 0.4,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Parent = self.View.LocalFolder,
			})
			table.insert(parts, part)
		end
	end
	self.ActiveTrove:Add(function()
		for _, p in parts do
			p:Destroy()
		end
	end)
	table.insert(self.ActiveSpinners, captureSpinner(parts, self.SwirlCFrame, -2.4, "Z"))
end

function Ambience:_buildRoofTrash()
	local nozzle = self.View:Find("Roof/RoofVacuum/Nozzle")
	if not nozzle or not nozzle:IsA("BasePart") then
		return
	end
	self.Nozzle = nozzle
	local world = Worlds.Get(self.View.World)
	local set = Trash.Get(if world then world.TrashSet else "Cleanville")
	local count = if Effects.IsLow() then 6 else 18
	local rng = Random.new()
	for i = 1, count do
		local def = set[rng:NextInteger(1, math.min(#set, 5))]
		local shape = if def.Shape == "Ball" then Enum.PartType.Ball elseif def.Shape == "Cylinder" then Enum.PartType.Cylinder else Enum.PartType.Block
		local part = Builder.Part({
			Name = "SkyTrash",
			Shape = shape,
			Size = def.Size * 0.9,
			Color = def.Color,
			Material = def.Material,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = self.View.LocalFolder,
		})
		self.ActiveTrove:Add(part)
		table.insert(self.Bits, { Part = part, T = rng:NextNumber(0, 1), Speed = rng:NextNumber(0.25, 0.45), Start = Vector3.zero, Spin = rng:NextNumber(-4, 4), Seed = i })
	end
	for _, bit in self.Bits do
		self:_respawnBit(bit, rng)
	end
end

function Ambience:_respawnBit(bit, rng: Random)
	local nozzle = self.Nozzle :: BasePart
	local dir = nozzle:GetAttribute("Direction") or Vector3.yAxis
	local spread = Vector3.new(rng:NextNumber(-40, 40), rng:NextNumber(-6, 26), rng:NextNumber(-40, 40))
	bit.Start = nozzle.Position + dir * 36 + spread
end

function Ambience:SetActive(active: boolean)
	self.ActiveTrove:Clean()
	self.Bits = {}
	self.ActiveSpinners = {}
	if not active then
		for _, pump in self.Pumps do
			pump.Part.Size = Vector3.one * pump.Base
		end
		return
	end
	self:_buildVortex()
	self:_buildRoofTrash()

	-- Steam from chimneys (dusty brass worlds only)
	if self.View.Theme.Steam then
		for _, vent in self.View:Tagged("SteamVent") do
			if vent:IsA("BasePart") then
				local attachment = Instance.new("Attachment")
				attachment.Position = Vector3.new(vent.Size.X / 2, 0, 0)
				attachment.Orientation = Vector3.new(0, 0, -90)
				attachment.Parent = vent
				local emitter = Effects.Emitter(attachment, "Steam", Color3.fromRGB(235, 230, 220), if Effects.IsLow() then 3 else 9)
				emitter.EmissionDirection = Enum.NormalId.Top
				emitter.Enabled = true
				self.ActiveTrove:Add(attachment)
			end
		end
	end

	local rng = Random.new()
	local accumulator = 0
	local nightTimer = 0
	self.ActiveTrove:Connect(RunService.Heartbeat, function(dt)
		self.Time += dt
		accumulator += dt
		nightTimer -= dt
		local step = if Effects.IsLow() then 1 / 20 else 1 / 45
		if accumulator < step then
			return
		end
		local elapsed = accumulator
		accumulator = 0
		self:_step(elapsed, rng)
		if nightTimer <= 0 then
			nightTimer = 1
			self:_updateNight()
		end
	end)
	self:_updateNight()
end

local function spin(spinner: Spinner, dt: number, parts: { BasePart }, frames: { CFrame })
	spinner.Angle = (spinner.Angle + spinner.Speed * dt) % (math.pi * 2)
	local rotation = if spinner.Axis == "Y" then CFrame.Angles(0, spinner.Angle, 0) else CFrame.Angles(0, 0, spinner.Angle)
	local base = spinner.Center * rotation
	for i, part in spinner.Parts do
		table.insert(parts, part)
		table.insert(frames, base * spinner.Offsets[i])
	end
end

function Ambience:_step(dt: number, rng: Random)
	local parts, frames = {}, {}
	for _, spinner in self.Spinners do
		spin(spinner, dt, parts, frames)
	end
	for _, spinner in self.ActiveSpinners do
		spin(spinner, dt, parts, frames)
	end

	for _, belt in self.Belts do
		local offset = (self.Time * belt.Speed) % belt.Spacing
		for i, slat in belt.Slats do
			local along = (i - 1) * belt.Spacing + belt.Spacing / 2 + offset
			local p = belt.Start + belt.Direction * along
			table.insert(parts, slat)
			table.insert(frames, CFrame.new(p.X, belt.Y, p.Z) * belt.Rotation)
		end
	end

	local nozzle = self.Nozzle
	if nozzle then
		local target = nozzle.Position
		for _, bit in self.Bits do
			bit.T += dt * bit.Speed
			if bit.T >= 1 then
				bit.T = 0
				self:_respawnBit(bit, rng)
			end
			local t = bit.T
			local e = t * t
			local swirl = CFrame.fromAxisAngle(Vector3.yAxis, e * math.pi * 3)
			local rel = swirl:VectorToWorldSpace(bit.Start - target) * (1 - e)
			table.insert(parts, bit.Part)
			table.insert(frames, CFrame.new(target + rel) * CFrame.Angles(self.Time * bit.Spin, self.Time * bit.Spin * 0.7, 0))
		end
	end

	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end

	for _, pump in self.Pumps do
		local s = pump.Base * (1 + 0.09 * math.sin(self.Time * 3.2 + pump.Phase))
		pump.Part.Size = Vector3.one * s
	end
end

function Ambience:_updateNight()
	local alpha = DayNight.NightAlpha()
	if self.LastNightAlpha and math.abs(self.LastNightAlpha - alpha) < 0.02 then
		return
	end
	self.LastNightAlpha = alpha
	local nightColor = self.View.Theme.NightNeon
	for _, entry in self.Neon do
		entry.Part.Color = entry.Day:Lerp(nightColor, alpha * 0.55)
	end
end

function Ambience:QualityChanged()
	if self.View.Near then
		self:SetActive(true)
	end
end

function Ambience:Destroy()
	self.Trove:Clean()
end

return Ambience
