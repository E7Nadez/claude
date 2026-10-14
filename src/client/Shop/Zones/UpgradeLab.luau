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
	for i = 1, math.floor(level / 5) + 1 do
		part(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, diameter + 0.25, diameter + 0.25), CFrame = base * CFrame.new(0, 0.4 + i * height / (math.floor(level / 5) + 2), 0) * CFrame.Angles(0, 0, math.pi / 2), Color = color, Material = Enum.Material.Neon })
	end
	part(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * diameter, CFrame = base * CFrame.new(0, height + 0.4, 0), Color = theme.Trim, Material = Enum.Material.Metal })
	part(model, { Size = Vector3.new(0.6, 0.6, 2.4), CFrame = base * CFrame.new(diameter / 2 + 0.6, height * 0.5, 0), Color = theme.Metal, Material = Enum.Material.Metal })
end

function Machines.Nozzle(model: Model, base: CFrame, level: number, theme, color: Color3)
	local rings = 3 + math.floor(level / 4)
	local maxRadius = 1.4 + level * 0.13
	part(model, { Size = Vector3.new(2.6, 3, 2.6), CFrame = base * CFrame.new(0, 1.9, 2), Color = theme.Metal, Material = Enum.Material.Metal })
	for i = 1, rings do
		local t = i / rings
		local radius = 0.6 + (maxRadius - 0.6) * t
		part(model, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.9, radius * 2, radius * 2),
			CFrame = base * CFrame.new(0, 3.4, 1.2 - i * 0.8) * CFrame.Angles(0, math.pi / 2, 0),
			Color = theme.Trim:Lerp(color, t * 0.4),
			Material = Enum.Material.Metal,
			Reflectance = 0.15,
		})
	end
	local rim = part(model, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, maxRadius * 2 + 0.3, maxRadius * 2 + 0.3),
		CFrame = base * CFrame.new(0, 3.4, 1.2 - rings * 0.8 - 0.5) * CFrame.Angles(0, math.pi / 2, 0),
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
	local speed = 2 + level * 0.45
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
	part(model, { Size = Vector3.new(width, 2.2 + level * 0.06, 3.2), CFrame = base * CFrame.new(0, 1.5, 0), Color = theme.Metal, Material = Enum.Material.Metal })
	part(model, { Size = Vector3.new(width + 0.2, 0.25, 3.4), CFrame = base * CFrame.new(0, 2.7 + level * 0.06, 0), Color = color, Material = Enum.Material.Neon })
	local speed = 3 + level * 0.35
	for i = 1, pistons do
		local x = -width / 2 + (i - 0.5) * (width / pistons)
		local piston = part(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2, 0.7, 0.7), CFrame = base * CFrame.new(x, 4, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = theme.Trim, Material = Enum.Material.Metal, Reflectance = 0.2 })
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
			}
		end
	end

	self.Trove:Connect(view.Controller.ClientData.Changed, function()
		if view.Near then
			self:_refresh(true)
		end
		if self.Focused then
			self:_showPanel(self.Focused)
		end
	end)
	return self
end

function UpgradeLab:_mountCFrame(machine): CFrame
	local center = self.View:ToWorld(Factory.UpgradeLab.Center)
	local pos = machine.Mount.Position
	return CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z))
end

function UpgradeLab:_build(machine, level: number)
	if machine.Visual then
		machine.Visual:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "Upgrade_" .. machine.Upgrade.Id
	local color = Rarities.Get(machine.Upgrade.Rarity).Color
	local builder = Machines[machine.Upgrade.Machine]
	builder(model, self:_mountCFrame(machine), level, self.View.Theme, color)
	model.Parent = self.View.LocalFolder
	machine.Visual = model
	machine.Parts = {}
	local mountCf = self:_mountCFrame(machine)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(machine.Parts, { Part = p, Home = p.CFrame, Rel = mountCf:ToObjectSpace(p.CFrame), Size = p.Size })
		end
	end
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
	for id, machine in self.Machines do
		local level = clientData:UpgradeLevel(id)
		if level ~= machine.Level then
			local previous = machine.Level
			self:_build(machine, level)
			self:_updateSign(machine, level, animate)
			if animate and previous >= 0 and level > previous then
				self:_celebrate(machine)
			end
			machine.Level = level
		end
	end
end

-- Growth animation + sparks when a machine levels up.
function UpgradeLab:_celebrate(machine)
	local mountCf = self:_mountCFrame(machine)
	local color = Rarities.Get(machine.Upgrade.Rarity).Color
	for _, entry in machine.Parts do
		local p = entry.Part
		p.Size = entry.Size * 0.6
		p.CFrame = mountCf * (CFrame.new(entry.Rel.Position * 0.6) * entry.Rel.Rotation)
		TweenService:Create(p, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = entry.Size, CFrame = entry.Home }):Play()
	end
	Effects.Burst(mountCf.Position + Vector3.new(0, 3, 0), "Sparks", 40, color)
	Effects.Burst(mountCf.Position + Vector3.new(0, 3, 0), "Glow", 16, color)
	Effects.Shockwave(mountCf.Position, color, 9)
	Effects.FlashLight(mountCf.Position + Vector3.new(0, 4, 0), color, 6, 22, 0.6)
	Audio.PlayAt("Weld", mountCf.Position)
	Audio.Play("Success")
	-- "LEVEL UP" label rising out of the machine
	local anchor = Builder.Part({
		Name = "LevelUpAnchor",
		Size = Vector3.one * 0.2,
		CFrame = mountCf * CFrame.new(0, 6, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = self.View.LocalFolder,
	})
	local tag = UI.new("BillboardGui", { Size = UDim2.fromOffset(260, 70), AlwaysOnTop = true, Adornee = anchor, Parent = anchor })
	local label = UI.Label({
		Text = "LEVEL UP!  LV " .. tostring(math.max(machine.Level + 1, 1)),
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true,
		FontFace = Theme.Fonts.Title,
		TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.3),
		TextStrokeTransparency = 0.3,
		Parent = tag,
	})
	TweenService:Create(tag, TweenInfo.new(1.6, Enum.EasingStyle.Quint), { StudsOffset = Vector3.new(0, 5, 0) }):Play()
	task.delay(1, function()
		TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	task.delay(1.7, function()
		anchor:Destroy()
	end)
end

function UpgradeLab:SetActive(active: boolean)
	self.ActiveTrove:Clean()
	for _, machine in self.Machines do
		machine.Visual = nil
		machine.Level = -1
		machine.Parts = {}
	end
	if not active then
		return
	end
	self:_refresh(false)
	local accumulator = 0
	self.ActiveTrove:Connect(RunService.Heartbeat, function(dt)
		accumulator += dt
		if accumulator < (if Effects.IsLow() then 1 / 15 else 1 / 30) then
			return
		end
		accumulator = 0
		local t = os.clock()
		local parts, frames = {}, {}
		for _, machine in self.Machines do
			local visual = machine.Visual
			local spinCenter = visual and visual:GetAttribute("SpinCenter")
			for _, entry in machine.Parts do
				local p = entry.Part
				local spin = p:GetAttribute("Spin")
				local piston = p:GetAttribute("Piston")
				if spin and typeof(spinCenter) == "CFrame" then
					local rel = spinCenter:ToObjectSpace(entry.Home)
					table.insert(parts, p)
					table.insert(frames, spinCenter * CFrame.Angles(0, 0, t * spin) * rel)
				elseif piston then
					table.insert(parts, p)
					table.insert(frames, entry.Home + Vector3.new(0, math.sin(t * piston + (p:GetAttribute("Phase") or 0)) * 0.6, 0))
				elseif p:GetAttribute("Pulse") then
					p.Transparency = 0.35 + 0.25 * math.sin(t * 3)
				end
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

-- Focus mode -------------------------------------------------------------------------------

function UpgradeLab:_showPanel(upgradeId: string)
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
	controller:CoinFlight("Coins", result.Price or 0, machine.Mount.Position + Vector3.new(0, 3, 0))
	controller.Hud:Toast(string.format("%s upgraded to Lv %d!", item.Name, result.Level or 0), "Success")
end

function UpgradeLab:Focus(upgradeId: string)
	local machine = self.Machines[upgradeId]
	local controller = self.View.Controller
	if not machine then
		return
	end
	if not controller:EnterMode("UpgradeLab", function()
		self.Focused = nil
		controller.FactoryHud:HidePanel()
		controller.FactoryHud:HideCarousel()
		controller.FactoryHud:SetHint(nil)
	end) then
		return
	end
	self.Focused = upgradeId
	local mountCf = self:_mountCFrame(machine)
	local camPos = mountCf.Position + mountCf.LookVector * 15 + Vector3.new(0, 8, 0) + mountCf.RightVector * 3
	CameraDirector.GlideTo(CFrame.lookAt(camPos, mountCf.Position + Vector3.new(0, 3.5, 0)), 0.7, Enum.EasingStyle.Quint, 60)
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
