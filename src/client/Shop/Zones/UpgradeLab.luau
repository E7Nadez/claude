-- Upgrade Lab: every upgrade is a machine that physically grows with its
-- level (bigger tank, wider nozzle, more turbine blades, more pistons).
-- Levels are per player, so machines are built locally from ClientData.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Definitions = Shared.Definitions
local Upgrades = require(Definitions.Upgrades)
local Factory = require(Definitions.Factory)
local Rarities = require(Definitions.Rarities)
local Shop = require(Definitions.Shop)
local Stats = require(Shared.Util.Stats)
local Format = require(Shared.Util.Format)
local Builder = require(Shared.Util.Builder)
local Trove = require(Shared.Util.Trove)

local ShopFolder = script.Parent.Parent
local UI = require(ShopFolder.UI.Components)
local Theme = require(ShopFolder.UI.Theme)
local Audio = require(ShopFolder.Audio)
local Effects = require(ShopFolder.Effects)
local CameraDirector = require(ShopFolder.CameraDirector)

local UpgradeLab = {}
UpgradeLab.__index = UpgradeLab

local GROW_TIME = 0.7
-- The builders stand every machine 0.4 above its `base` frame; that frame sits
-- this far under the top of the base plate, so the machines stand on the plate
-- (0.05 into it) instead of hovering half a stud above it.
local PLATE_SINK = 0.45

local function part(model: Model, props: { [string]: any }): BasePart
	local p = Builder.Part(props)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = model
	return p
end

-- Machine builders. `base` is the mount CFrame (top of the machine base,
-- LookVector towards the lab center). Parts that animate get attributes.
local Machines = {}

function Machines.Tank(model: Model, base: CFrame, level: number, theme, color: Color3)
	local height = 3 + level * 0.32
	local diameter = 3.2 + level * 0.12
	part(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, diameter, diameter), CFrame = base * CFrame.new(0, height / 2 + 0.4, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = theme.Trim, Material = Enum.Material.Metal, Reflectance = 0.15 })
	local liquid = part(model, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height * 0.92, diameter * 1.02, diameter * 1.02),
		CFrame = base * CFrame.new(0, height / 2 + 0.4, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = Enum.Material.Glass,
		Transparency = 0.55,
	})
	liquid:SetAttribute("Pulse", true)
	local bands = math.floor(level / 5) + 1
	for i = 1, bands do
		part(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, diameter + 0.25, diameter + 0.25), CFrame = base * CFrame.new(0, 0.4 + i * height / (bands + 1), 0) * CFrame.Angles(0, 0, math.pi / 2), Color = color, Material = Enum.Material.Neon })
	end
	part(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * diameter, CFrame = base * CFrame.new(0, height + 0.4, 0), Color = theme.Trim, Material = Enum.Material.Metal })
	-- feed pipe: out of the tank wall (below the first band), elbow, down into the plate
	local wall = diameter * 0.51
	local pipeY = 0.4 + height / (bands + 1) / 2
	part(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.3, 0.55, 0.55), CFrame = base * CFrame.new(wall + 0.45, pipeY, 0), Color = theme.Metal, Material = Enum.Material.Metal })
	part(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.75, CFrame = base * CFrame.new(wall + 1.1, pipeY, 0), Color = theme.Metal, Material = Enum.Material.Metal })
	part(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(pipeY - 0.3, 0.55, 0.55), CFrame = base * CFrame.new(wall + 1.1, (pipeY + 0.3) / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = theme.Metal, Material = Enum.Material.Metal })
end

function Machines.Nozzle(model: Model, base: CFrame, level: number, theme, color: Color3)
	local rings = 3 + math.floor(level / 4)
	local maxRadius = 1.4 + level * 0.13
	-- The horn's axis (and the body under it) rises with the mouth, so the widest
	-- rings and the rim stay above the base plate instead of cutting into it.
	local axisY = math.max(3.4, maxRadius + 0.85)
	part(model, { Size = Vector3.new(2.6, axisY - 0.4, 2.6), CFrame = base * CFrame.new(0, (axisY + 0.4) / 2, 2), Color = theme.Metal, Material = Enum.Material.Metal })
	for i = 1, rings do
		local t = i / rings
		local radius = 0.6 + (maxRadius - 0.6) * t
		part(model, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.9, radius * 2, radius * 2),
			CFrame = base * CFrame.new(0, axisY, 1.2 - i * 0.8) * CFrame.Angles(0, math.pi / 2, 0),
			Color = theme.Trim:Lerp(color, t * 0.4),
			Material = Enum.Material.Metal,
			Reflectance = 0.15,
		})
	end
	local rim = part(model, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, maxRadius * 2 + 0.3, maxRadius * 2 + 0.3),
		CFrame = base * CFrame.new(0, axisY, 1.2 - rings * 0.8 - 0.5) * CFrame.Angles(0, math.pi / 2, 0),
		Color = color,
		Material = Enum.Material.Neon,
	})
	rim:SetAttribute("Pulse", true)
end

function Machines.Turbine(model: Model, base: CFrame, level: number, theme, color: Color3)
	local radius = 2 + level * 0.09
	local blades = math.min(3 + math.floor(level / 4), 10)
	local center = base * CFrame.new(0, radius + 1, 0)
	for _, p in Builder.Ring(center, radius + 0.3, 0.5, 1.4, 18, { Color = theme.Trim, Material = Enum.Material.Metal, CanCollide = false }) do
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = model
	end
	part(model, { Size = Vector3.new(1, radius + 1, 1), CFrame = base * CFrame.new(0, (radius + 1) / 2, 0.9), Color = theme.Metal, Material = Enum.Material.Metal })
	-- Capped so a 30 Hz update (Low Graphics, slow devices) turns the rotor by at
	-- most 40 % of the blade spacing: faster reads as strobing or spinning backwards.
	local speed = math.min(2 + level * 0.45, 24 * math.pi / blades)
	local hub = part(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * 1.2, CFrame = center, Color = color, Material = Enum.Material.Neon })
	hub:SetAttribute("Spin", speed)
	for i = 1, blades do
		local a = (i - 1) / blades * math.pi * 2
		local blade = part(model, {
			Size = Vector3.new(radius * 0.4, radius * 0.95, 0.12),
			CFrame = center * CFrame.Angles(0, 0, a) * CFrame.new(0, radius * 0.5, 0) * CFrame.Angles(0, math.rad(28), 0),
			Color = theme.Trim:Lerp(color, 0.3),
			Material = Enum.Material.Metal,
		})
		blade:SetAttribute("Spin", speed)
	end
	model:SetAttribute("SpinCenter", center)
end

function Machines.Motor(model: Model, base: CFrame, level: number, theme, color: Color3)
	local pistons = math.min(1 + math.floor(level / 4), 7)
	local width = 2.6 + pistons * 0.9
	-- the block grows upwards from the plate; the neon strip and the pistons ride on its top
	local blockHeight = 2.2 + level * 0.06
	part(model, { Size = Vector3.new(width, blockHeight, 3.2), CFrame = base * CFrame.new(0, 0.4 + blockHeight / 2, 0), Color = theme.Metal, Material = Enum.Material.Metal })
	part(model, { Size = Vector3.new(width + 0.2, 0.25, 3.4), CFrame = base * CFrame.new(0, 0.5 + blockHeight, 0), Color = color, Material = Enum.Material.Neon })
	local speed = 3 + level * 0.35
	for i = 1, pistons do
		local x = -width / 2 + (i - 0.5) * (width / pistons)
		local piston = part(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2, 0.7, 0.7), CFrame = base * CFrame.new(x, 1.8 + blockHeight, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = theme.Trim, Material = Enum.Material.Metal, Reflectance = 0.2 })
		piston:SetAttribute("Piston", speed)
		piston:SetAttribute("Phase", i * 1.3)
	end
end

function UpgradeLab.new(view)
	local self = setmetatable({}, UpgradeLab)
	self.View = view
	self.Trove = Trove.new()
	self.ActiveTrove = Trove.new()
	self.Trove:Add(self.ActiveTrove, "Clean")
	self.Machines = {}
	self.Focused = nil :: string?
	self.PanelKey = nil :: string?

	for _, upgrade in Upgrades.List do
		local model = view:Find("UpgradeLab/Machine_" .. upgrade.Id)
		if model then
			self.Machines[upgrade.Id] = {
				Upgrade = upgrade,
				Server = model,
				Mount = model:FindFirstChild("Mount") :: BasePart,
				Sign = model:FindFirstChild("Sign") :: BasePart,
				Visual = nil :: Model?,
				Level = -1,
				Parts = {},
				Plate = nil :: CFrame?,
				SpinCenter = nil :: CFrame?,
				Top = 0,
				Reach = 0,
				GrowStart = nil :: number?,
				LevelTag = nil :: BasePart?,
			}
		end
	end

	self.Trove:Connect(view.Controller.ClientData.Changed, function(_, previous)
		if view.Near then
			-- (the first snapshot after joining is no level-up: machines built before
			-- the profile arrived stood at level 0)
			self:_refresh(previous ~= nil)
		end
		if self.Focused then
			self:_showPanel(self.Focused, true)
		end
	end)
	return self
end

function UpgradeLab:_mountCFrame(machine): CFrame
	local center = self.View:ToWorld(Factory.UpgradeLab.Center)
	local pos = machine.Mount.Position
	return CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z))
end

-- Top of the machine's base plate (the Mount marker floats 0.1 above it), facing
-- the lab centre: machines stand and grow on it.
function UpgradeLab:_plateCFrame(machine): CFrame
	local mountCf = self:_mountCFrame(machine)
	local plate = machine.Server:FindFirstChild("Base")
	local top = if plate and plate:IsA("BasePart") then plate.Position.Y + plate.Size.Y / 2 else mountCf.Y - 0.1
	return mountCf + Vector3.new(0, top - mountCf.Y, 0)
end

function UpgradeLab:_build(machine, level: number)
	if machine.Visual then
		self.ActiveTrove:Remove(machine.Visual)
		machine.Visual:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "Upgrade_" .. machine.Upgrade.Id
	local color = Rarities.Get(machine.Upgrade.Rarity).Color
	local builder = Machines[machine.Upgrade.Machine]
	local plate = self:_plateCFrame(machine)
	builder(model, plate * CFrame.new(0, -PLATE_SINK, 0), level, self.View.Theme, color)
	model.Parent = self.View.LocalFolder
	machine.Visual = model
	machine.Plate = plate
	machine.GrowStart = nil
	machine.Parts = {}
	-- Animation data is read once here, not every frame. Top / Reach (height over
	-- the plate, reach towards the lab centre) frame the camera and the level tag.
	local spinCenter = model:GetAttribute("SpinCenter")
	local top, reach = 0, 0
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local rel = plate:ToObjectSpace(p.CFrame)
			local size = p.Size
			local halfY = (math.abs(rel.XVector.Y) * size.X + math.abs(rel.YVector.Y) * size.Y + math.abs(rel.ZVector.Y) * size.Z) / 2
			local halfZ = (math.abs(rel.XVector.Z) * size.X + math.abs(rel.YVector.Z) * size.Y + math.abs(rel.ZVector.Z) * size.Z) / 2
			local piston = p:GetAttribute("Piston")
			top = math.max(top, rel.Y + halfY + (if piston then 0.6 else 0))
			reach = math.max(reach, halfZ - rel.Z)
			local spin = p:GetAttribute("Spin")
			table.insert(machine.Parts, {
				Part = p,
				Home = p.CFrame,
				Size = size,
				Spin = if typeof(spin) == "number" and typeof(spinCenter) == "CFrame" then spin else nil,
				SpinRel = if typeof(spinCenter) == "CFrame" then spinCenter:ToObjectSpace(p.CFrame) else nil,
				Piston = if typeof(piston) == "number" then piston else nil,
				Phase = p:GetAttribute("Phase") or 0,
				Pulse = p:GetAttribute("Pulse") == true,
			})
		end
	end
	machine.SpinCenter = if typeof(spinCenter) == "CFrame" then spinCenter else nil
	machine.Top = top
	machine.Reach = reach
	self.ActiveTrove:Add(model)
end

function UpgradeLab:_updateSign(machine, level: number, animate: boolean)
	local sign = machine.Sign
	if not sign then
		return
	end
	local gui = sign:FindFirstChild("LabSign") :: SurfaceGui?
	if not gui then
		gui = UI.new("SurfaceGui", {
			Name = "LabSign",
			Face = Enum.NormalId.Front,
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = 40,
			LightInfluence = 0,
			Brightness = 1.8,
			MaxDistance = 140,
			Parent = sign,
		})
		local rarity = Rarities.Get(machine.Upgrade.Rarity)
		local panel = UI.new("Frame", { Name = "Panel", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 12, 20), Parent = gui }, { UI.Corner(UDim.new(0, 14)), UI.Stroke(rarity.Color, 0.2, 3) })
		UI.Label({ Name = "Title", Text = machine.Upgrade.Glyph .. " " .. string.upper(machine.Upgrade.Name), Position = UDim2.fromScale(0.05, 0.06), Size = UDim2.fromScale(0.9, 0.24), TextScaled = true, FontFace = Theme.Fonts.Title, TextXAlignment = Enum.TextXAlignment.Center, Parent = panel })
		UI.Label({ Name = "Level", Text = "", Position = UDim2.fromScale(0.05, 0.32), Size = UDim2.fromScale(0.9, 0.3), TextScaled = true, FontFace = Theme.Fonts.Numbers, TextColor3 = rarity.Color, TextXAlignment = Enum.TextXAlignment.Center, Parent = panel })
		local track = UI.new("Frame", { Name = "Track", Position = UDim2.fromScale(0.08, 0.66), Size = UDim2.fromScale(0.84, 0.08), BackgroundColor3 = Color3.fromRGB(40, 46, 66), Parent = panel }, { UI.Corner(UDim.new(1, 0)) })
		UI.new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = rarity.Color, Parent = track }, { UI.Corner(UDim.new(1, 0)) })
		UI.Label({ Name = "Bonus", Text = "", Position = UDim2.fromScale(0.05, 0.78), Size = UDim2.fromScale(0.9, 0.16), TextScaled = true, TextColor3 = Theme.Colors.SubText, TextXAlignment = Enum.TextXAlignment.Center, Parent = panel })
		self.ActiveTrove:Add(gui)
	end
	local panel = (gui :: SurfaceGui):FindFirstChild("Panel") :: Frame
	local levelLabel = panel:FindFirstChild("Level") :: TextLabel
	local fill = (panel:FindFirstChild("Track") :: Frame):FindFirstChild("Fill") :: Frame
	local bonus = panel:FindFirstChild("Bonus") :: TextLabel
	local upgrade = machine.Upgrade
	local fmt = function(v: number)
		return string.format("LV %d / %d", math.floor(v + 0.5), upgrade.MaxLevel)
	end
	if animate and machine.Level >= 0 then
		UI.CountTo(levelLabel, machine.Level, level, 0.8, fmt)
	else
		levelLabel.Text = fmt(level)
	end
	UI.Tween(fill, Theme.Tween.Slow, { Size = UDim2.fromScale(level / upgrade.MaxLevel, 1) })
	bonus.Text = string.format("%s %s %s", Stats.Glyphs[upgrade.Stat], Stats.Labels[upgrade.Stat], Format.Percent(Upgrades.Multiplier(upgrade.Id, level) - 1, true))
end

function UpgradeLab:_refresh(animate: boolean)
	local clientData = self.View.Controller.ClientData
	local celebrate = animate and self:_inView()
	for id, machine in self.Machines do
		local level = clientData:UpgradeLevel(id)
		if level ~= machine.Level then
			local previous = machine.Level
			self:_build(machine, level)
			self:_updateSign(machine, level, animate)
			machine.Level = level
			if celebrate and previous >= 0 and level > previous then
				self:_celebrate(machine, level)
				if self.Focused == id then
					-- the camera eases back to frame the bigger machine
					self:_frame(machine, 0.9)
				end
			end
		end
	end
end

-- The level-up show only plays where the player can see it: focused on a machine
-- or walking in the lab, and not behind the shop window. Elsewhere (an upgrade
-- bought from the window in the lobby) the machine is just rebuilt.
function UpgradeLab:_inView(): boolean
	local controller = self.View.Controller
	if controller.Classic and controller.Classic.IsOpen then
		return false
	end
	if self.Focused then
		return true
	end
	local root = controller:GetRoot()
	return root ~= nil and self.View:RoomAt(root.Position) == "UpgradeLab"
end

-- Poses one machine for this frame: blades spin, pistons pump and, after a level
-- up, every part grows from 60 % out of the base plate (in this loop, so the
-- growth composes with the spin instead of a tween fighting it). The glass / rim
-- pulse is written only when `pulse` is set.
function UpgradeLab:_stepMachine(machine, t: number, pulse: boolean, parts: { BasePart }, frames: { CFrame })
	local plate = machine.Plate
	if not machine.Visual or not plate then
		return
	end
	local grow: number? = nil
	if machine.GrowStart then
		local alpha = (t - machine.GrowStart) / GROW_TIME
		if alpha < 1 then
			local style = if Effects.ReduceMotion() then Enum.EasingStyle.Quad else Enum.EasingStyle.Back
			grow = 0.6 + 0.4 * TweenService:GetValue(math.max(alpha, 0), style, Enum.EasingDirection.Out)
		else
			-- (this last growth frame puts every part back to its full size)
			machine.GrowStart = nil
			grow = 1
		end
	end
	local spinCenter = machine.SpinCenter
	for _, entry in machine.Parts do
		local p = entry.Part
		local cf: CFrame? = nil
		if entry.Spin and spinCenter then
			cf = spinCenter * CFrame.Angles(0, 0, t * entry.Spin) * entry.SpinRel
		elseif entry.Piston then
			cf = entry.Home + Vector3.new(0, math.sin(t * entry.Piston + entry.Phase) * 0.6, 0)
		elseif pulse and entry.Pulse then
			p.Transparency = 0.35 + 0.25 * math.sin(t * 3)
		end
		if grow then
			local rel = plate:ToObjectSpace(cf or entry.Home)
			cf = plate * (CFrame.new(rel.Position * grow) * rel.Rotation)
			p.Size = entry.Size * grow
		end
		if cf then
			table.insert(parts, p)
			table.insert(frames, cf)
		end
	end
end

-- Growth animation + sparks when a machine levels up.
function UpgradeLab:_celebrate(machine, level: number)
	local plate = machine.Plate
	if not plate then
		return
	end
	local color = Rarities.Get(machine.Upgrade.Rarity).Color
	local top = machine.Top
	machine.GrowStart = os.clock()
	-- the shrunken start pose shows at once, not one full-size frame first
	local parts, frames = {}, {}
	self:_stepMachine(machine, machine.GrowStart, false, parts, frames)
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	local middle = plate.Position + Vector3.new(0, math.max(top * 0.5, 2), 0)
	Effects.Burst(middle, "Sparks", 40, color)
	Effects.Burst(middle, "Glow", 16, color)
	Effects.Shockwave(plate.Position + Vector3.new(0, 0.1, 0), color, 6.5)
	Effects.FlashLight(middle + Vector3.new(0, 1, 0), color, 6, 22, 0.6)
	-- (positional only: the purchase itself already played the "Success" chime)
	Audio.PlayAt("Weld", middle)
	-- "LEVEL UP" tag rising from just above the machine; a new level replaces the
	-- last tag instead of stacking on it
	if machine.LevelTag then
		machine.LevelTag:Destroy()
	end
	local anchor = Builder.Part({
		Name = "LevelUpAnchor",
		Size = Vector3.one * 0.2,
		CFrame = plate * CFrame.new(0, top + 1.4, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = self.View.LocalFolder,
	})
	machine.LevelTag = anchor
	self.ActiveTrove:Add(anchor)
	-- (studs + pixels: scales with the shot, stays readable on a phone)
	local tag = UI.new("BillboardGui", { Name = "LevelUpTag", Size = UDim2.new(4, 110, 1.1, 30), AlwaysOnTop = true, MaxDistance = 120, Adornee = anchor, Parent = anchor })
	local label = UI.Label({
		Text = "LEVEL UP!  LV " .. tostring(level),
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true,
		FontFace = Theme.Fonts.Title,
		TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.3),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Parent = tag,
	})
	UI.Tween(label, Theme.Tween.Fast, { TextTransparency = 0, TextStrokeTransparency = 0.3 })
	if not Effects.ReduceMotion() then
		local scale = UI.GetScale(label)
		scale.Scale = 0.6
		UI.Tween(scale, Theme.Tween.Spring, { Scale = 1 })
		-- (a short rise: it ends just under the level sign behind the machine)
		UI.Tween(tag, TweenInfo.new(1.6, Enum.EasingStyle.Quint), { StudsOffset = Vector3.new(0, 1.6, 0) })
	end
	task.delay(1, function()
		if label.Parent then
			UI.Tween(label, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
	end)
	task.delay(1.7, function()
		self.ActiveTrove:Remove(anchor)
		anchor:Destroy()
		if machine.LevelTag == anchor then
			machine.LevelTag = nil
		end
	end)
end

function UpgradeLab:SetActive(active: boolean)
	self.ActiveTrove:Clean()
	for _, machine in self.Machines do
		machine.Visual = nil
		machine.Level = -1
		machine.Parts = {}
		machine.GrowStart = nil
		machine.LevelTag = nil
	end
	if not active then
		return
	end
	self:_refresh(false)
	-- Blades, pistons and growth move every frame while the camera is near the lab
	-- (Low Graphics or far away: an even 30 Hz), so fast rotors never strobe; the
	-- pulse is written at 30 Hz (15 Hz).
	local center = self.View:ToWorld(Factory.UpgradeLab.Center)
	local accumulator, pulseAccumulator = 0, 0
	self.ActiveTrove:Connect(RunService.Heartbeat, function(dt)
		local low = Effects.IsLow()
		local near = (workspace.CurrentCamera.CFrame.Position - center).Magnitude < 110
		local interval = if low or not near then 1 / 30 else 0
		accumulator += dt
		pulseAccumulator += dt
		if accumulator < interval then
			return
		end
		accumulator = if interval > 0 then math.min(accumulator - interval, interval) else 0
		local pulseInterval = if low then 1 / 15 else 1 / 30
		local pulse = pulseAccumulator >= pulseInterval
		if pulse then
			pulseAccumulator = math.min(pulseAccumulator - pulseInterval, pulseInterval)
		end
		local t = os.clock()
		local parts, frames = {}, {}
		for _, machine in self.Machines do
			self:_stepMachine(machine, t, pulse, parts, frames)
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

-- Focus mode -------------------------------------------------------------------------------

-- onlyIfChanged: data updates rebuild the panel (pop + tick) only when what it
-- shows changed, not on every unrelated snapshot.
function UpgradeLab:_showPanel(upgradeId: string, onlyIfChanged: boolean?)
	local controller = self.View.Controller
	local clientData = controller.ClientData
	local data = clientData:Get()
	local upgrade = Upgrades.Get(upgradeId)
	local item = Shop.Get(upgradeId)
	if not upgrade or not item or not data then
		return
	end
	local level = clientData:UpgradeLevel(upgradeId)
	local maxed = level >= upgrade.MaxLevel
	local price = Shop.GetPrice(item, data)
	local key = string.format("%s|%d|%s|%s", upgradeId, level, tostring(price), tostring(Shop.CanAfford(item, data)))
	if onlyIfChanged and key == self.PanelKey then
		return
	end
	self.PanelKey = key
	local now = Upgrades.Multiplier(upgradeId, level) - 1
	local nextValue = Upgrades.Multiplier(upgradeId, math.min(level + 1, upgrade.MaxLevel)) - 1
	controller.FactoryHud:ShowPanel({
		Title = upgrade.Name,
		Rarity = upgrade.Rarity,
		Lines = {
			upgrade.Description,
			string.format("Level <b>%d</b> / %d", level, upgrade.MaxLevel),
			if maxed then "<font color=\"#FFCC40\"><b>MAXED OUT</b></font>" else string.format("%s %s: <b>%s</b> → <font color=\"#40D68C\"><b>%s</b></font>", Stats.Glyphs[upgrade.Stat], Stats.Labels[upgrade.Stat], Format.Percent(now, true), Format.Percent(nextValue, true)),
		},
		Price = if maxed then nil else { Amount = price, Currency = "Coins", Affordable = Shop.CanAfford(item, data) },
		Buttons = {
			{
				Id = "Upgrade",
				Text = if maxed then "Maxed" else "Upgrade",
				Glyph = "⬆",
				Style = "Gold",
				Enabled = not maxed and Shop.CanAfford(item, data),
				OnClick = function()
					self:_buy(upgradeId)
				end,
			},
			{
				Text = "Details",
				Style = "Ghost",
				OnClick = function()
					controller.Modal:Show(item, { Source = "Factory" })
				end,
			},
		},
	})
end

function UpgradeLab:_buy(upgradeId: string)
	local controller = self.View.Controller
	local item = Shop.Get(upgradeId)
	local machine = self.Machines[upgradeId]
	if not item or not machine or self.Buying then
		return
	end
	self.Buying = true
	local button = controller.FactoryHud:GetButton("Upgrade")
	if button then
		button:SetLoading(true)
	end
	local result = controller:RequestPurchase(item)
	self.Buying = false
	if button then
		button:SetLoading(false)
	end
	if not result.Ok then
		controller.Hud:Toast(result.Error or "Upgrade failed.", "Error")
		return
	end
	-- (the only chime: the machine's level-up show adds positional sound only)
	Audio.Play("Success")
	controller:CoinFlight("Coins", result.Price or 0, machine.Mount.Position + Vector3.new(0, 3, 0))
	controller.Hud:Toast(string.format("%s upgraded to Lv %d!", item.Name, result.Level or 0), "Success")
end

-- Frames the whole machine as it stands now (a level 25 tank is three times as
-- tall as a new one, the wide nozzle reaches out towards the camera) from the
-- lab side, a little to the right. The level sign stands behind the machine; the
-- aim never drops below 3.6 so it stays inside the shot of a small machine.
-- Without a duration the glide takes as long as the distance needs.
function UpgradeLab:_frame(machine, duration: number?)
	local plate = machine.Plate or self:_plateCFrame(machine)
	local top = if machine.Visual then machine.Top else 6
	local reach = if machine.Visual then machine.Reach else 2
	local aim = plate.Position + Vector3.new(0, math.max(top / 2, 3.6), 0) + plate.LookVector * (reach * 0.4)
	local distance = math.max(15, math.max(top, 4) * 1.6 + reach * 0.8)
	local side = (plate.LookVector * 15 + plate.RightVector * 3).Unit
	local camPos = aim + side * distance + Vector3.new(0, distance * 0.3, 0)
	local glide = duration or math.clamp((workspace.CurrentCamera.CFrame.Position - camPos).Magnitude / 45, 0.7, 1.6)
	CameraDirector.GlideTo(CFrame.lookAt(camPos, aim), glide, if glide > 0.75 then Enum.EasingStyle.Sine else Enum.EasingStyle.Quint, 60)
end

function UpgradeLab:Focus(upgradeId: string)
	local machine = self.Machines[upgradeId]
	local controller = self.View.Controller
	if not machine then
		return
	end
	if not controller:EnterMode("UpgradeLab", function()
		self.Focused = nil
		self.PanelKey = nil
		controller:SetCharacterHidden(false)
		controller.FactoryHud:HidePanel()
		controller.FactoryHud:HideCarousel()
		controller.FactoryHud:SetHint(nil)
	end) then
		return
	end
	self.Focused = upgradeId
	-- (the player stands at the console, right between this camera and the machine)
	controller:SetCharacterHidden(true)
	self:_frame(machine)
	local order = {}
	for _, upgrade in Upgrades.List do
		table.insert(order, upgrade.Id)
	end
	local function cycle(direction: number)
		local index = table.find(order, self.Focused or upgradeId) or 1
		local nextId = order[(index - 1 + direction) % #order + 1]
		self:Focus(nextId)
	end
	controller.FactoryHud:ShowCarousel(function()
		cycle(-1)
	end, function()
		cycle(1)
	end)
	controller.FactoryHud:SetCarouselLabel(string.format("%d / %d", table.find(order, upgradeId) or 1, #order))
	controller.FactoryHud:SetHint("[Keys] Next machine  ·  [Back] Back")
	self:_showPanel(upgradeId)
end

function UpgradeLab:Destroy()
	self.Trove:Clean()
end

return UpgradeLab
