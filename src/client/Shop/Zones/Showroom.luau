-- 3D showroom: vacuums on podiums in a carousel. Each podium has a stat
-- hologram that compares live with the equipped vacuum. The selected model
-- spins, explodes into its parts and reassembles. Locked vacuums sit behind
-- glass with a padlock and an animated unlock condition.
-- Browse with swipe / arrow keys / gamepad; the camera glides between podiums.

local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Definitions = Shared.Definitions
local Vacuums = require(Definitions.Vacuums)
local Rarities = require(Definitions.Rarities)
local Factory = require(Definitions.Factory)
local Shop = require(Definitions.Shop)
local Worlds = require(Definitions.Worlds)
local Stats = require(Shared.Util.Stats)
local Progress = require(Shared.Util.Progress)
local Format = require(Shared.Util.Format)
local Builder = require(Shared.Util.Builder)
local Trove = require(Shared.Util.Trove)
local VacuumModel = require(Shared.Models.VacuumModel)

local ShopFolder = script.Parent.Parent
local UI = require(ShopFolder.UI.Components)
local Theme = require(ShopFolder.UI.Theme)
local Audio = require(ShopFolder.Audio)
local Effects = require(ShopFolder.Effects)
local CameraDirector = require(ShopFolder.CameraDirector)

local Showroom = {}
Showroom.__index = Showroom

local EXPLODE_PERIOD = 7.5
-- Showroom copies are fitted so they spin inside the glass case (radius 3.6) and
-- clear of the hologram, whose near edge is ~3.8 studs from the podium axis.
local FIT_RADIUS = 3.3
local FIT_HEIGHT = 6
local EXPLODE_RADIUS = 3.6
-- Legendary / Mythic orbs circle above the case, clear of padlock, label and hologram.
local ORB_HEIGHT = 8
-- Browse camera: further back than the builder's camera spot and aimed towards the
-- hologram, so vacuum, case and hologram stay left of the HUD panel docked right.
local CAMERA_PULLBACK = 4
local CAMERA_RISE = 1
local CAMERA_AIM = 0.9

local function easeInOut(t: number): number
	return TweenService:GetValue(math.clamp(t, 0, 1), Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
end

-- 0 = assembled, 1 = fully exploded, for a time inside the cycle.
local function explodeAmount(t: number): number
	local c = t % EXPLODE_PERIOD
	if c < 1.6 then
		return 0
	elseif c < 2.4 then
		return easeInOut((c - 1.6) / 0.8)
	elseif c < 5.0 then
		return 1
	elseif c < 5.8 then
		return 1 - easeInOut((c - 5.0) / 0.8)
	end
	return 0
end

function Showroom.new(view)
	local self = setmetatable({}, Showroom)
	self.View = view
	self.Trove = Trove.new()
	self.ActiveTrove = Trove.new()
	self.Trove:Add(self.ActiveTrove, "Clean")
	self.BrowseTrove = Trove.new()
	self.Trove:Add(self.BrowseTrove, "Clean")
	self.Podiums = {}
	self.Selected = nil :: number?
	self.Browsing = false
	self.SelectedAt = os.clock()
	self.GlideUntil = 0
	self.MainAction = nil :: (() -> ())?
	self.PanelKey = nil :: string?
	self.PanelStale = false

	local folder = view:Find("Showroom/Podiums")
	if folder then
		for _, podium in folder:GetChildren() do
			if podium:IsA("Model") then
				local index = podium:GetAttribute("Index") :: number
				self.Podiums[index] = {
					Index = index,
					VacuumId = podium:GetAttribute("VacuumId") :: string,
					Podium = podium,
					Display = podium:FindFirstChild("Display") :: BasePart,
					Holo = podium:FindFirstChild("Holo") :: BasePart,
					Ring = podium:FindFirstChild("Ring") :: BasePart,
					Spot = podium:FindFirstChild("Spot") :: BasePart,
					Angle = index * 1.3,
					Center = Vector3.zero,
					ExplodeAmt = 0,
					Fade = 0,
					Model = nil :: Model?,
					Case = nil :: Model?,
					Locked = nil :: boolean?,
					Holder = nil :: any,
				}
			end
		end
	end

	self.Trove:Connect(view.Controller.ClientData.Changed, function()
		if view.Near then
			self:_refreshStates(true)
			if self.Browsing and self.Selected then
				if view.Controller:IsBusy() then
					-- the HUD is hidden during the purchase show: refresh once it ends
					self.PanelStale = true
				else
					self:_showPanel(self.Podiums[self.Selected], true)
				end
			end
		end
	end)
	return self
end

-- Camera framing for a podium: from inside the carousel looking outwards so
-- vacuum, glass case and hologram are all in view, clear of the HUD panel.
function Showroom:CameraFor(entry): CFrame
	local config = Factory.Showroom
	local center = self.View:ToWorld(config.Center)
	local display = entry.Display.Position
	local flat = (display - center) * Vector3.new(1, 0, 1)
	local dir = flat.Unit
	local camPos = center + dir * (config.PodiumRadius - config.CameraInset - CAMERA_PULLBACK) + Vector3.new(0, config.CameraHeight + CAMERA_RISE, 0)
	local tangent = Vector3.new(-dir.Z, 0, dir.X)
	local target = display + Vector3.new(0, 2.6, 0) + tangent * (config.HoloOffset * CAMERA_AIM)
	return CFrame.lookAt(camPos, target)
end

-- Holograms -----------------------------------------------------------------------------

local function buildHolo(entry, vacuum: Vacuums.Vacuum)
	local rarity = Rarities.Get(vacuum.Rarity)
	local gui = UI.new("SurfaceGui", {
		Name = "ShopHolo",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 50,
		LightInfluence = 0,
		Brightness = 1.6,
		MaxDistance = 160,
		AlwaysOnTop = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = entry.Holo,
	})
	-- Inset from the canvas edges so the outer rarity stroke, the select glitch and
	-- the equip pop are not clipped by the SurfaceGui. White base: the gradient
	-- below multiplies it and carries the actual rarity tint.
	local panel = UI.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -20, 1, -16),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.35,
		ClipsDescendants = true,
		Parent = gui,
	}, { UI.Corner(UDim.new(0, 18)) })
	local stroke = UI.Stroke(rarity.Color, 0.15, 3)
	stroke.Parent = panel
	UI.Gradient(Rarities.ColorSequence(rarity.Id), 0).Parent = stroke
	UI.Gradient({ rarity.Color:Lerp(Color3.new(0, 0, 0), 0.6), Color3.fromRGB(8, 10, 18) }, 90, NumberSequence.new(0.2)).Parent = panel
	local scan = UI.new("Frame", {
		Name = "Scan",
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromScale(0, -0.2),
		BackgroundColor3 = rarity.Color,
		BackgroundTransparency = 0.82,
		ZIndex = 5,
		Parent = panel,
	}, { UI.Gradient({ Color3.new(1, 1, 1), Color3.new(1, 1, 1) }, 90, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})) })
	UI.Label({ Name = "Name", Text = vacuum.Name, Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -36, 0, 34), FontFace = Theme.Fonts.Title, TextScaled = true, Parent = panel })
	UI.Label({
		Name = "Rarity",
		Text = string.upper(rarity.Name) .. "  ·  " .. string.upper(vacuum.World),
		Position = UDim2.fromOffset(18, 44),
		Size = UDim2.new(1, -36, 0, 18),
		TextSize = 16,
		TextColor3 = rarity.Color,
		FontFace = Theme.Fonts.Title,
		Parent = panel,
	})
	local rows = {}
	for i, key in Stats.Order do
		local y = 70 + (i - 1) * 34
		UI.Label({ Text = Stats.Glyphs[key] .. " " .. Stats.Labels[key], Position = UDim2.fromOffset(18, y), Size = UDim2.fromOffset(96, 26), TextSize = 18, Parent = panel })
		local track = UI.new("Frame", { Position = UDim2.fromOffset(116, y + 8), Size = UDim2.new(1, -280, 0, 10), BackgroundColor3 = Color3.fromRGB(40, 46, 66), Parent = panel }, { UI.Corner(UDim.new(1, 0)) })
		local ghost = UI.new("Frame", { Name = "Ghost", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.7, Parent = track }, { UI.Corner(UDim.new(1, 0)) })
		local fill = UI.new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Colors.Accent, Parent = track }, { UI.Corner(UDim.new(1, 0)) })
		-- value / delta shrink to fit instead of truncating ("+109,900%")
		local value = UI.Label({ Text = "0", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -100, 0, y), Size = UDim2.fromOffset(60, 26), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Theme.Fonts.Numbers, TextScaled = true, Parent = panel })
		UI.new("UITextSizeConstraint", { MaxTextSize = 20, Parent = value })
		local delta = UI.Label({ Text = "", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, y), Size = UDim2.fromOffset(84, 26), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Theme.Fonts.Numbers, TextScaled = true, Parent = panel })
		UI.new("UITextSizeConstraint", { MaxTextSize = 15, Parent = delta })
		rows[key] = { Fill = fill, Ghost = ghost, Value = value, Delta = delta, Shown = 0 }
	end
	local footer = UI.Label({
		Name = "Footer",
		Text = "",
		RichText = true,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -10),
		Size = UDim2.new(1, -36, 0, 26),
		TextSize = 20,
		FontFace = Theme.Fonts.Numbers,
		Parent = panel,
	})
	return { Gui = gui, Panel = panel, Scan = scan, Rows = rows, Footer = footer }
end

function Showroom:_updateHolo(entry, animate: boolean)
	local holo = entry.HoloUi
	if not holo then
		return
	end
	local clientData = self.View.Controller.ClientData
	local data = clientData:Get()
	local test = clientData:EffectiveStats(entry.VacuumId)
	local equippedId = clientData:Equipped()
	local current = clientData:EffectiveStats(equippedId)
	local delta = Stats.Delta(test, current)
	for i, key in Stats.Order do
		local row = holo.Rows[key]
		local d = delta[key]
		local color = if entry.VacuumId == equippedId or math.abs(d) < 0.005 then Theme.Colors.Accent elseif d > 0 then Theme.Colors.Success else Theme.Colors.Danger
		local fill = Stats.BarFill(key, (test :: any)[key])
		local ghost = Stats.BarFill(key, (current :: any)[key])
		row.Fill.BackgroundColor3 = color
		row.Delta.TextColor3 = color
		row.Delta.Text = if entry.VacuumId == equippedId then "" elseif math.abs(d) < 0.005 then "=" else Format.Percent(d, true)
		local value = (test :: any)[key]
		if animate then
			row.Fill.Size = UDim2.fromScale(0, 1)
			UI.Tween(row.Fill, TweenInfo.new(0.55 + i * 0.08, Enum.EasingStyle.Quint), { Size = UDim2.fromScale(fill, 1) })
			UI.Tween(row.Ghost, TweenInfo.new(0.5), { Size = UDim2.fromScale(ghost, 1) })
			UI.CountTo(row.Value, 0, value, 0.6 + i * 0.08, Format.Stat)
		else
			row.Fill.Size = UDim2.fromScale(fill, 1)
			row.Ghost.Size = UDim2.fromScale(ghost, 1)
			row.Value.Text = Format.Stat(value)
		end
	end
	local item = Shop.Get(entry.VacuumId)
	local footer
	if not data then
		footer = ""
	elseif data.Vacuums.Owned[entry.VacuumId] then
		footer = if equippedId == entry.VacuumId then "<font color=\"#5A8CFF\">● EQUIPPED</font>" else "<font color=\"#40D68C\">✔ OWNED</font>"
	elseif entry.Locked then
		footer = "<font color=\"#9AA0B8\">🔒 LOCKED</font>"
	elseif item then
		local price = Shop.GetPrice(item, data)
		local can = Shop.CanAfford(item, data)
		footer = string.format("<font color=\"%s\">🪙 %s</font>", if can then "#FFCC40" else "#FF5268", Format.Abbreviate(price))
	else
		footer = "STARTER"
	end
	holo.Footer.Text = footer
end

local function clearCase(entry)
	if entry.Case then
		entry.Case:Destroy()
	end
	entry.Case = nil
	entry.CaseText = nil
	entry.CaseLines = nil
	entry.LockBody = nil
	entry.LockParts = nil
	entry.Glass = nil
	entry.PendingUnlock = nil
end

-- Fades a podium's local dressing (model, case, orbs, hologram, beam, sparkles)
-- while it stands in front of a show camera. 0 = visible, 1 = hidden.
local function setFade(entry, fade: number)
	local visible = fade < 0.5
	local low = Effects.IsLow()
	for _, container in { entry.Model, entry.Case } do
		for _, d in container:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = fade
			elseif d:IsA("SurfaceGui") then
				d.Enabled = visible
			end
		end
	end
	for _, orb in entry.Orbs or {} do
		orb.Part.LocalTransparencyModifier = fade
		orb.Trail.Enabled = visible and not low
	end
	if entry.HoloUi then
		entry.HoloUi.Gui.Enabled = visible
	end
	if entry.Cone then
		entry.Cone.Enabled = visible
	end
	if entry.Rise then
		entry.Rise.Enabled = visible and not low
	end
end

-- Glass case + padlock + animated condition text for locked vacuums.
local function buildCase(self, entry, missing: { string })
	local view = self.View
	local model = Instance.new("Model")
	model.Name = "Case"
	local base = entry.Display.CFrame * CFrame.new(0, 3.4, 0)
	local glass = Builder.Part({
		Name = "Glass",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(7, 7.2, 7.2),
		CFrame = base * CFrame.Angles(0, 0, math.pi / 2),
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(170, 210, 255),
		Transparency = 0.6,
		Reflectance = 0.15,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = model,
	})
	Builder.Part({
		Name = "Cap",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 7.6, 7.6),
		CFrame = base * CFrame.new(0, 3.6, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Material = Enum.Material.Metal,
		Color = view.Theme.Trim,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = model,
	})
	-- Padlock in front of the glass, facing the camera. The shackle (arc + two legs
	-- reaching into the body) is stored relative to the body and sways with it.
	local lockCf = entry.Display.CFrame * CFrame.new(0, 2.2, -3.75)
	local lockBody = Builder.Part({
		Name = "LockBody",
		Size = Vector3.new(1.5, 1.3, 0.5),
		CFrame = lockCf,
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(255, 196, 60),
		Reflectance = 0.2,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = model,
	})
	local lockParts = { { Part = lockBody, Offset = CFrame.identity } }
	local shackle = { Material = Enum.Material.Metal, Color = Color3.fromRGB(200, 205, 215), CanCollide = false, CanQuery = false, CanTouch = false }
	local arcCf = lockCf * CFrame.new(0, 0.95, 0)
	for _, p in Builder.Ring(arcCf, 0.45, 0.18, 0.18, 10, shackle) do
		if arcCf:PointToObjectSpace(p.Position).Y < -0.05 then
			p:Destroy()
		else
			p.Parent = model
			table.insert(lockParts, { Part = p, Offset = lockCf:ToObjectSpace(p.CFrame) })
		end
	end
	for _, x in { -0.45, 0.45 } do
		local props = table.clone(shackle)
		props.Size = Vector3.new(0.18, 0.5, 0.18)
		props.CFrame = lockCf * CFrame.new(x, 0.72, 0)
		props.Parent = model
		local leg = Builder.Part(props)
		table.insert(lockParts, { Part = leg, Offset = lockCf:ToObjectSpace(leg.CFrame) })
	end
	local label = Builder.Part({
		Name = "Label",
		Size = Vector3.new(5, 1.6, 0.05),
		CFrame = entry.Display.CFrame * CFrame.new(0, 5.9, -3.65),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = model,
	})
	local gui = UI.new("SurfaceGui", {
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 50,
		LightInfluence = 0,
		Brightness = 2,
		MaxDistance = 120,
		Parent = label,
	})
	local text = UI.Label({
		Text = "",
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true,
		FontFace = Theme.Fonts.Title,
		TextColor3 = Color3.fromRGB(255, 220, 120),
		TextStrokeTransparency = 0.4,
		Parent = gui,
	})
	model.Parent = view.LocalFolder
	entry.Case = model
	entry.CaseText = text
	entry.CaseLines = missing
	entry.LockBody = lockBody
	entry.LockCf = lockCf
	entry.LockParts = lockParts
	entry.Glass = glass
	entry.PendingUnlock = nil
	if entry.Fade > 0 then
		setFade(entry, entry.Fade)
	end
end

local function shatterCase(entry)
	local case = entry.Case
	if not case then
		return
	end
	local glass = case:FindFirstChild("Glass") :: BasePart?
	local center = if glass then glass.Position else entry.Display.Position
	clearCase(entry)
	Audio.PlayAt("Glass", center)
	Effects.Burst(center, "Sparks", 40, Color3.fromRGB(180, 220, 255))
	local rng = Random.new()
	for _ = 1, Effects.Count(18) do
		local shard = Builder.Part({
			Name = "Shard",
			Size = Vector3.new(rng:NextNumber(0.4, 1.2), rng:NextNumber(0.4, 1.4), 0.08),
			CFrame = CFrame.new(center + Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(-3, 3), rng:NextNumber(-3, 3))) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0),
			Material = Enum.Material.Glass,
			Color = Color3.fromRGB(180, 220, 255),
			Transparency = 0.4,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Parent = workspace,
		})
		local out = (shard.Position - center).Unit * rng:NextNumber(4, 9)
		TweenService:Create(shard, TweenInfo.new(0.9, Enum.EasingStyle.Quad), {
			CFrame = shard.CFrame + out - Vector3.new(0, 4, 0),
			Transparency = 1,
		}):Play()
		task.delay(1, function()
			shard:Destroy()
		end)
	end
end

-- Activation ------------------------------------------------------------------------------

-- Root-space bounds (centre, half size) of an animated part; spinning parts sweep
-- a disc around their spin centre.
local function partBounds(p): (Vector3, Vector3)
	local cf: CFrame = p.Home
	local size = p.Part.Size
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local half = Vector3.new(
		math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z,
		math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z,
		math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z
	) / 2
	if p.Spin and p.SpinAxis and p.SpinCenter then
		local n = p.SpinAxis.Unit
		local reach = (cf.Position - p.SpinCenter).Magnitude + size.Magnitude / 2
		local disc = Vector3.new(math.sqrt(math.max(1 - n.X * n.X, 0)), math.sqrt(math.max(1 - n.Y * n.Y, 0)), math.sqrt(math.max(1 - n.Z * n.Z, 0))) * reach
		return p.SpinCenter, half:Max(disc)
	end
	return cf.Position, half
end

-- Showroom copies spin inside a fixed glass case next to the hologram: shrink
-- oversized models (Dragon, Cannon, Canister nozzle), spin them around their own
-- footprint centre and keep the exploded view above the podium and inside
-- EXPLODE_RADIUS.
local function fitModel(entry, model: Model, root: BasePart)
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in entry.Parts do
		local c, h = partBounds(p)
		low = low:Min(c - h)
		high = high:Max(c + h)
	end
	if low.X > high.X then
		return
	end
	local center = Vector3.new((low.X + high.X) / 2, 0, (low.Z + high.Z) / 2)
	local radius = 0
	for _, p in entry.Parts do
		local c, h = partBounds(p)
		radius = math.max(radius, Vector2.new(math.abs(c.X - center.X) + h.X, math.abs(c.Z - center.Z) + h.Z).Magnitude)
	end
	local k = math.min(1, FIT_RADIUS / math.max(radius, 0.01), FIT_HEIGHT / math.max(high.Y, 0.01))
	if k < 0.999 then
		model:ScaleTo(model:GetScale() * k)
		for _, p in entry.Parts do
			p.Home = root.CFrame:ToObjectSpace(p.Part.CFrame)
			p.Explode *= k
			if p.SpinCenter then
				p.SpinCenter *= k
			end
		end
		center *= k
	end
	entry.Center = center
	for _, p in entry.Parts do
		local c, h = partBounds(p)
		local e = p.Explode
		local push = Vector3.new(e.X, 0, e.Z)
		local flat = Vector3.new(c.X - center.X, 0, c.Z - center.Z)
		-- outwards at most to EXPLODE_RADIUS (parts already further out only rise)
		local limit = math.max(EXPLODE_RADIUS - Vector2.new(h.X, h.Z).Magnitude, flat.Magnitude)
		if (flat + push).Magnitude > limit then
			local a = push:Dot(push)
			local b = 2 * flat:Dot(push)
			local q = flat:Dot(flat) - limit * limit
			local s = if a > 1e-6 then (-b + math.sqrt(math.max(b * b - 4 * a * q, 0))) / (2 * a) else 0
			push *= math.clamp(s, 0, 1)
		end
		-- never sink into the podium
		p.Explode = Vector3.new(push.X, math.max(e.Y, h.Y - c.Y + 0.05), push.Z)
	end
end

function Showroom:_buildEntry(entry)
	local vacuum = Vacuums.Get(entry.VacuumId)
	if not vacuum then
		return
	end
	local model = VacuumModel.Build(vacuum.Id)
	entry.Parts = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= model.PrimaryPart then
			table.insert(entry.Parts, {
				Part = part,
				Home = part:GetAttribute("Home") :: CFrame,
				Explode = part:GetAttribute("Explode") :: Vector3,
				Spin = part:GetAttribute("Spin") :: number?,
				SpinAxis = part:GetAttribute("SpinAxis") :: Vector3?,
				SpinCenter = part:GetAttribute("SpinCenter") :: Vector3?,
			})
		end
	end
	entry.Center = Vector3.zero
	entry.ExplodeAmt = 0
	if model.PrimaryPart then
		fitModel(entry, model, model.PrimaryPart)
	end
	-- parented once fitted; SetActive places it before the next frame renders
	model.Parent = self.View.LocalFolder
	entry.Model = model
	local rarity = Rarities.Get(vacuum.Rarity)
	entry.Ring.Color = rarity.Color
	local light = entry.Spot and entry.Spot:FindFirstChildOfClass("SpotLight")
	if light then
		light.Color = Color3.new(1, 1, 1):Lerp(rarity.Color, 0.45)
	end
	entry.HoloUi = buildHolo(entry, vacuum)
	self.ActiveTrove:Add(model)
	self.ActiveTrove:Add(entry.HoloUi.Gui)

	-- Projection cone from the podium ring up to the hologram
	local ringTop = Instance.new("Attachment")
	ringTop.Name = "ConeBase"
	ringTop.Position = Vector3.new(0.2, 0, 0)
	ringTop.Parent = entry.Ring
	local holoCenter = Instance.new("Attachment")
	holoCenter.Name = "ConeTop"
	holoCenter.Parent = entry.Holo
	local cone = Instance.new("Beam")
	cone.Attachment0 = ringTop
	cone.Attachment1 = holoCenter
	cone.Color = ColorSequence.new(rarity.Color)
	cone.LightEmission = 1
	cone.FaceCamera = true
	cone.Width0 = 1.2
	cone.Width1 = 7
	cone.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.92) })
	cone.Parent = ringTop
	entry.Cone = cone
	self.ActiveTrove:Add(ringTop)
	self.ActiveTrove:Add(holoCenter)

	-- Rising sparkles around Epic+ podiums (off on Low Graphics, see QualityChanged)
	entry.Rise = nil
	if rarity.Rank >= 4 then
		local rate = if rarity.Rank >= 6 then 10 elseif rarity.Rank == 5 then 6 else 3
		local rise = Effects.Emitter(entry.Ring, "Rise", rarity.Color, rate)
		rise.Shape = Enum.ParticleEmitterShape.Cylinder
		rise.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		rise.EmissionDirection = Enum.NormalId.Right
		-- the rim emits sideways along its normal: keep that push small and let them float up
		rise.Speed = NumberRange.new(0.2, 0.6)
		rise.Acceleration = Vector3.new(0, 3.5, 0)
		rise.Enabled = not Effects.IsLow()
		entry.Rise = rise
		entry.RiseRate = rate
		self.ActiveTrove:Add(rise)
	end

	-- Light orbs with trails circling above the case for Legendary / Mythic
	entry.Orbs = {}
	if rarity.Rank >= 5 then
		local crown = entry.Display.Position + Vector3.new(0, ORB_HEIGHT, 0)
		for k = 1, if rarity.Rank >= 6 then 3 else 2 do
			local orb = Builder.Part({
				Name = "Orb",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.45,
				CFrame = CFrame.new(crown),
				Material = Enum.Material.Neon,
				Color = if k % 2 == 0 then rarity.Gradient[2] else rarity.Gradient[1],
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Parent = self.View.LocalFolder,
			})
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, 0.18, 0)
			a0.Parent = orb
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -0.18, 0)
			a1.Parent = orb
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Color = ColorSequence.new(orb.Color)
			trail.LightEmission = 1
			trail.Lifetime = 0.45
			trail.FaceCamera = true
			trail.Transparency = NumberSequence.new(0.2, 1)
			trail.Enabled = not Effects.IsLow()
			trail.Parent = orb
			self.ActiveTrove:Add(orb)
			-- nearly flat rings at different radii: never through the cap, label,
			-- hologram or each other; alternate directions
			table.insert(entry.Orbs, {
				Part = orb,
				Trail = trail,
				Tilt = CFrame.Angles(0, k * 2.1, 0) * CFrame.Angles(0.08, 0, 0),
				Radius = 3 + k * 0.45,
				Speed = (1.6 + k * 0.35) * (if k % 2 == 0 then -1 else 1),
				Angle = k * 2.1,
			})
		end
	end
end

function Showroom:_refreshStates(animateUnlock: boolean)
	local data = self.View.Controller.ClientData:Get()
	if not data then
		-- No profile yet: don't show glass cases that would "unlock" on load.
		return
	end
	for _, entry in self.Podiums do
		local vacuum = Vacuums.Get(entry.VacuumId)
		if vacuum and entry.Model then
			local owned = data and data.Vacuums.Owned[vacuum.Id]
			local missing = if owned then {} else Progress.Missing(data, vacuum.Unlock)
			local locked = #missing > 0
			if locked and not entry.Case then
				buildCase(self, entry, missing)
			elseif locked and entry.Case then
				entry.CaseLines = missing
				entry.PendingUnlock = nil
			elseif not locked and entry.Case and not entry.PendingUnlock then
				if animateUnlock and entry.Locked then
					-- The unlock usually lands mid purchase show (or behind the shop
					-- window): keep the case until the player sees it break (_step).
					entry.PendingUnlock = true
					entry.CaseLines = {}
					if entry.CaseText then
						entry.CaseText.Text = "🔓 UNLOCKED"
						entry.CaseText.MaxVisibleGraphemes = -1
					end
				else
					clearCase(entry)
				end
			end
			entry.Locked = locked
			self:_updateHolo(entry, false)
		end
	end
end

function Showroom:SetActive(active: boolean)
	self.ActiveTrove:Clean()
	for _, entry in self.Podiums do
		clearCase(entry)
		entry.Model = nil
		entry.HoloUi = nil
		entry.Locked = nil
		entry.Orbs = nil
		entry.Cone = nil
		entry.Rise = nil
		entry.Fade = 0
		entry.ExplodeAmt = 0
		entry.Scanning = false
	end
	if not active then
		return
	end
	for _, entry in self.Podiums do
		self:_buildEntry(entry)
	end
	self:_refreshStates(false)
	-- place models, locks and orbs before the next frame renders: they are built
	-- at the world origin and the orb trails would streak from there
	self:_step(0, 0)

	-- The selected podium (and any model still reassembling) and the orbs move
	-- every frame, in step with the camera; the rest updates at 20-40 Hz.
	local accumulator = 0
	self.ActiveTrove:Connect(RunService.Heartbeat, function(dt)
		accumulator += dt
		local slow: number? = nil
		if accumulator >= (if Effects.IsLow() then 1 / 20 else 1 / 40) then
			slow = accumulator
			accumulator = 0
		end
		self:_step(dt, slow)
	end)
end

-- The case breaks once the player can actually see it: never mid-show or behind
-- the shop window; while browsing, when the podium is selected and the camera
-- has arrived; otherwise when it is in the middle of the view in the showroom.
function Showroom:_revealReady(entry, index: number): boolean
	local controller = self.View.Controller
	if controller:IsBusy() or controller.Modal:IsOpen() or (controller.Classic and controller.Classic.IsOpen) then
		return false
	end
	if self.Browsing then
		return index == self.Selected and os.clock() >= self.GlideUntil
	end
	local root = controller:GetRoot()
	if not root or self.View:RoomAt(root.Position) ~= "Showroom" then
		return false
	end
	local camera = workspace.CurrentCamera
	local point, onScreen = camera:WorldToViewportPoint(entry.Display.Position + Vector3.new(0, 3, 0))
	if not onScreen or point.Z > 60 then
		return false
	end
	local size = camera.ViewportSize
	return math.abs(point.X / size.X - 0.5) < 0.35 and math.abs(point.Y / size.Y - 0.5) < 0.4
end

-- The purchase show looks from the showroom at the assembly bay (podium 5 sits
-- right on that line, the side cameras pass through podiums 4 / 5): fade out
-- every podium between the camera and the bay while the show runs.
function Showroom:_updateBlocker(entry, blockSegment: { Vector3 }?, dt: number)
	local blocking = false
	if blockSegment then
		local a, b = blockSegment[1], blockSegment[2]
		local p = entry.Display.Position * Vector3.new(1, 0, 1)
		local ab = b - a
		local t = if ab:Dot(ab) > 1e-6 then math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1) else 0
		blocking = (p - (a + ab * t)).Magnitude < 5.5
	end
	local goal = if blocking then 1 else 0
	if entry.Fade ~= goal then
		entry.Fade = if dt > 0 then math.clamp(entry.Fade + (if blocking then dt else -dt) * 5, 0, 1) else goal
		setFade(entry, entry.Fade)
	end
end

function Showroom:_step(dt: number, slowDt: number?)
	local now = os.clock()
	local controller = self.View.Controller
	local busy = controller:IsBusy()
	local reduceMotion = Effects.ReduceMotion()
	-- only the purchase show runs while browsing
	local blockSegment: { Vector3 }? = nil
	if busy and self.Browsing then
		local flat = Vector3.new(1, 0, 1)
		blockSegment = { workspace.CurrentCamera.CFrame.Position * flat, self.View:ToWorld(Factory.AssemblyBay.Center) * flat }
	end
	local parts, frames = {}, {}
	for index, entry in self.Podiums do
		local selected = index == self.Selected
		self:_updateBlocker(entry, blockSegment, dt)
		local step = if selected or entry.ExplodeAmt > 0 then dt else slowDt
		if step then
			self:_stepPodium(entry, index, selected, step, now, reduceMotion, parts, frames)
		end
		if entry.Orbs and #entry.Orbs > 0 then
			local crown = entry.Display.Position + Vector3.new(0, ORB_HEIGHT, 0)
			for k, orb in entry.Orbs do
				orb.Angle += dt * orb.Speed * (if reduceMotion then 0.3 else 1)
				local offset = orb.Tilt:VectorToWorldSpace(Vector3.new(math.cos(orb.Angle) * orb.Radius, 0, math.sin(orb.Angle) * orb.Radius))
				table.insert(parts, orb.Part)
				table.insert(frames, CFrame.new(crown + offset + Vector3.new(0, math.sin(now * 1.3 + k) * 0.12, 0)))
			end
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	if self.PanelStale and not busy and self.Browsing and self.Selected then
		self.PanelStale = false
		self:_showPanel(self.Podiums[self.Selected], true)
	end
end

function Showroom:_stepPodium(entry, index: number, selected: boolean, dt: number, now: number, reduceMotion: boolean, parts: { BasePart }, frames: { CFrame })
	if entry.PendingUnlock and self:_revealReady(entry, index) then
		shatterCase(entry)
	end
	local model = entry.Model
	if model and model.PrimaryPart then
		entry.Angle += dt * (if selected then 0.9 else 0.35)
		local lift = math.sin(now * 1.6 + index) * 0.15 + 0.35
		local rootCf = entry.Display.CFrame * CFrame.new(0, lift, 0) * CFrame.Angles(0, entry.Angle, 0) * CFrame.new(-entry.Center)
		-- Exploded view only for the selected vacuum outside a glass case. Eased, so a
		-- deselected model reassembles instead of snapping together in one frame.
		local target = if selected and not entry.Case and not reduceMotion then explodeAmount(now - self.SelectedAt) else 0
		local amount = entry.ExplodeAmt + (target - entry.ExplodeAmt) * math.min(dt * 6, 1)
		if target == 0 and amount < 0.002 then
			amount = 0
		end
		entry.ExplodeAmt = amount
		table.insert(parts, model.PrimaryPart)
		table.insert(frames, rootCf)
		for _, p in entry.Parts do
			local home = p.Home
			if p.Spin and p.SpinAxis and p.SpinCenter then
				local center = p.SpinCenter
				home = CFrame.new(center) * CFrame.fromAxisAngle(p.SpinAxis, now * p.Spin) * CFrame.new(-center) * home
			end
			local offset = if amount > 0 then CFrame.new(p.Explode * amount) else CFrame.identity
			table.insert(parts, p.Part)
			table.insert(frames, rootCf * offset * home)
		end
	end
	-- Animated condition text on locked glass cases: the whole line is laid out
	-- once (TextScaled) and revealed by grapheme, so its size never jumps.
	local text = entry.CaseText
	if text and entry.CaseLines and #entry.CaseLines > 0 then
		local lineIndex = math.floor(now / 3.2) % #entry.CaseLines + 1
		local line = "🔒 " .. entry.CaseLines[lineIndex]
		if text.Text ~= line then
			text.Text = line
		end
		local count = utf8.len(line) or #line
		text.MaxVisibleGraphemes = math.clamp(math.floor(((now % 3.2) / 1.2) * count), 1, count)
		text.TextTransparency = 0.1 + 0.25 * (0.5 + 0.5 * math.sin(now * 4))
	end
	if entry.LockParts then
		local sway = if reduceMotion then 0 else 0.08
		local lockCf = entry.LockCf * CFrame.new(0, math.sin(now * 2 + index) * sway, 0) * CFrame.Angles(0, 0, math.sin(now * 3 + index) * sway)
		for _, lock in entry.LockParts do
			table.insert(parts, lock.Part)
			table.insert(frames, lockCf * lock.Offset)
		end
	end
	local holo = entry.HoloUi
	if holo then
		if selected then
			holo.Scan.Position = UDim2.fromScale(0, ((now % 2.4) / 2.4) * 1.4 - 0.2)
			entry.Scanning = true
		elseif entry.Scanning then
			-- park the scan bar above the panel instead of freezing it across the stats
			entry.Scanning = false
			holo.Scan.Position = UDim2.fromScale(0, -0.2)
		end
	end
	if entry.Cone then
		local pulse = if selected then 0.45 + math.sin(now * 5) * 0.08 else 0.68
		entry.Cone.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, pulse), NumberSequenceKeypoint.new(1, 0.93) })
	end
end

-- Browsing ---------------------------------------------------------------------------------

function Showroom:IndexOf(vacuumId: string): number?
	for index, entry in self.Podiums do
		if entry.VacuumId == vacuumId then
			return index
		end
	end
	return nil
end

function Showroom:NearestIndex(position: Vector3): number
	local best, bestDistance = 1, math.huge
	for index, entry in self.Podiums do
		local d = (entry.Display.Position - position).Magnitude
		if d < bestDistance then
			best, bestDistance = index, d
		end
	end
	return best
end

-- Input hint for the current podium; the confirm action follows the Main button.
function Showroom:_setHint(mainText: string?, canTry: boolean)
	local hud = self.View.Controller.FactoryHud
	if not UserInputService.KeyboardEnabled and not UserInputService.GamepadEnabled then
		-- touch: the panel buttons are on screen, only swiping needs explaining
		hud:SetHint("Swipe to browse")
		return
	end
	local hint = { "[Keys] Browse" }
	if mainText then
		table.insert(hint, "[Confirm] " .. mainText)
	end
	if canTry then
		table.insert(hint, "[Alt] Try")
	end
	table.insert(hint, "[Back] Exit")
	hud:SetHint(table.concat(hint, "  ·  "))
end

-- refresh = data changed: rebuild only when something shown actually differs, so
-- coin updates don't re-pop the panel (and its tick sound) while browsing.
function Showroom:_showPanel(entry, refresh: boolean?)
	if not entry then
		return
	end
	local controller = self.View.Controller
	local clientData = controller.ClientData
	local data = clientData:Get()
	local vacuum = Vacuums.Get(entry.VacuumId)
	if not vacuum or not data then
		return
	end
	local item = Shop.Get(vacuum.Id)
	local test = clientData:EffectiveStats(vacuum.Id)
	local equippedId = clientData:Equipped()
	local current = clientData:EffectiveStats(equippedId)
	local delta = Stats.Delta(test, current)
	local bars = {}
	for _, key in Stats.Order do
		table.insert(bars, {
			Label = Stats.Glyphs[key] .. " " .. Stats.Labels[key],
			Fill = Stats.BarFill(key, (test :: any)[key]),
			Ghost = Stats.BarFill(key, (current :: any)[key]),
			Value = Format.Stat((test :: any)[key]),
			Delta = if vacuum.Id == equippedId then 0 else delta[key],
		})
	end
	local world = Worlds.Get(self.View.World)
	local comparison = Stats.Compare(test, current, if world then world.TrashSet else "Cleanville")
	local lines = { vacuum.Description }
	if vacuum.Id ~= equippedId then
		table.insert(lines, string.format("<font color=\"%s\"><b>%s</b></font> cleaning vs. yours", if comparison.Percent >= 0 then "#40D68C" else "#FF5268", Format.Percent(comparison.Percent, true)))
	end

	local owned = data.Vacuums.Owned[vacuum.Id] == true
	local state = if item then Shop.GetState(item, data, workspace:GetServerTimeNow()) elseif owned then "Owned" else "Available"
	if owned then
		state = if equippedId == vacuum.Id then "Equipped" else "Owned"
	end
	local missing = if owned then {} else Progress.Missing(data, vacuum.Unlock)
	local affordable = item ~= nil and Shop.CanAfford(item, data)
	local price = if item and not owned then Shop.GetPrice(item, data) else nil
	local signature = { vacuum.Id, state, tostring(price), tostring(affordable), table.concat(missing, "|"), table.concat(lines, "|") }
	for _, bar in bars do
		table.insert(signature, bar.Value .. "/" .. string.format("%.3f", bar.Delta or 0))
	end
	local key = table.concat(signature, ";")
	if refresh and key == self.PanelKey then
		return
	end
	self.PanelKey = key

	-- The Main action is shared by the button and the confirm key (Enter / A).
	local mainText: string? = nil
	local mainAction: (() -> ())? = nil
	local buttons = {}
	if state == "Equipped" then
		table.insert(buttons, { Id = "Main", Text = "Equipped", Glyph = "●", Style = "Secondary", Enabled = false, OnClick = function() end })
	elseif state == "Owned" then
		mainText = "Equip"
		mainAction = function()
			-- EquipVacuum plays the success sound; the zone may deactivate meanwhile
			local result = controller:EquipVacuum(vacuum.Id)
			local holo = entry.HoloUi
			if result.Ok and holo then
				UI.Pop(holo.Panel, 0.04)
			end
		end
		table.insert(buttons, { Id = "Main", Text = "Equip", Glyph = "✔", Style = "Primary", OnClick = mainAction })
	elseif #missing > 0 then
		table.insert(buttons, { Id = "Main", Text = "Locked", Glyph = "🔒", Style = "Secondary", Enabled = false, OnClick = function() end })
	elseif item then
		mainText = if affordable then "Buy" else nil
		mainAction = function()
			controller.Modal:Show(item, { Source = "Factory" })
		end
		table.insert(buttons, { Id = "Main", Text = "Buy", Glyph = "🛒", Style = "Gold", Enabled = affordable, OnClick = mainAction })
	end
	self.MainAction = mainAction
	table.insert(buttons, {
		Id = "Try",
		Text = "Try It (20s)",
		Glyph = "🧪",
		Style = "Primary",
		Enabled = #missing == 0,
		OnClick = function()
			local chamber = self.View:Zone("TestChamber")
			if chamber then
				chamber:Start(vacuum.Id)
			end
		end,
	})
	if item then
		table.insert(buttons, {
			Id = "Details",
			Text = "Details",
			Style = "Ghost",
			OnClick = function()
				controller.Modal:Show(item, { Source = "Factory" })
			end,
		})
	end
	controller.FactoryHud:ShowPanel({
		Title = vacuum.Name,
		Rarity = vacuum.Rarity,
		Bars = bars,
		Lines = lines,
		Price = if item and price then { Amount = price, Currency = item.Currency, Affordable = affordable } else nil,
		Status = if #missing > 0 then "🔒 " .. table.concat(missing, " · ") else nil,
		Buttons = buttons,
	})
	self:_setHint(mainText, #missing == 0)
end

-- Glides the camera to a podium and returns the glide's duration. The first glide
-- can start outside the podium ring (Inspect prompt, arriving from the Test Lab):
-- the straight line would fly through a glass case and vacuum, so it cranes up
-- over the ring instead.
function Showroom:_glide(goal: CFrame, duration: number, firstGlide: boolean): number
	local camera = workspace.CurrentCamera
	local from = camera.CFrame
	local config = Factory.Showroom
	local center = self.View:ToWorld(config.Center)
	if not firstGlide or ((from.Position - center) * Vector3.new(1, 0, 1)).Magnitude < config.PodiumRadius - 5 then
		CameraDirector.GlideTo(goal, duration, Enum.EasingStyle.Quint, 62)
		return duration
	end
	duration *= 1.25
	-- quadratic curve whose middle passes ~13.5 studs above the floor (cases end at ~11)
	local mid = (from.Position + goal.Position) / 2
	local control = Vector3.new(mid.X, math.max(2 * (center.Y + 13.5) - mid.Y, mid.Y), mid.Z)
	local start = os.clock()
	local fovFrom = camera.FieldOfView
	CameraDirector.Follow(function()
		local e = easeInOut((os.clock() - start) / duration)
		camera.FieldOfView = fovFrom + (62 - fovFrom) * e
		local position = from.Position:Lerp(control, e):Lerp(control:Lerp(goal.Position, e), e)
		return CFrame.new(position) * from.Rotation:Lerp(goal.Rotation, e)
	end)
	return duration
end

function Showroom:Select(index: number, firstGlide: boolean?)
	local count = #self.Podiums
	if count == 0 then
		return
	end
	index = (index - 1) % count + 1
	local entry = self.Podiums[index]
	local previous = self.Selected
	self.Selected = index
	self.SelectedAt = os.clock()
	self.GlideUntil = os.clock() + self:_glide(self:CameraFor(entry), if firstGlide then 0.9 else 0.55, firstGlide == true)
	if previous ~= index then
		Audio.Play("Servo")
	end
	local controller = self.View.Controller
	controller.FactoryHud:SetCarouselLabel(string.format("%d / %d", index, count))
	self:_updateHolo(entry, true)
	if entry.HoloUi then
		local panel = entry.HoloUi.Panel
		if Effects.ReduceMotion() then
			panel.BackgroundTransparency = 1
			UI.Tween(panel, TweenInfo.new(0.2), { BackgroundTransparency = 0.35 })
		else
			-- glitch the hologram in
			task.spawn(function()
				for _, t in { 0.9, 0.3, 0.8, 0.45, 0.7, 0.35 } do
					panel.BackgroundTransparency = t
					panel.Position = UDim2.new(0.5, math.random(-4, 4), 0.5, 0)
					task.wait(0.04)
				end
				panel.Position = UDim2.fromScale(0.5, 0.5)
			end)
		end
	end
	-- floor pulse rings rolling out around the podium base while selected
	self.PulseToken = (self.PulseToken or 0) + 1
	local token = self.PulseToken
	local rarity = Rarities.Get((Vacuums.Get(entry.VacuumId) or { Rarity = "Common" }).Rarity)
	local floor = entry.Display.Position - Vector3.new(0, Factory.Showroom.PodiumHeight + 0.07, 0)
	task.spawn(function()
		while self.Selected == index and self.PulseToken == token do
			if not Effects.ReduceMotion() and not controller:IsBusy() then
				Effects.Shockwave(floor, rarity.Color, 7, 0.9)
			end
			task.wait(1.6)
		end
	end)
	Effects.Burst(entry.Display.Position + Vector3.new(0, 2, 0), "Glitter", 18, rarity.Color)
	self:_showPanel(entry)
end

function Showroom:Browse(index: number?)
	local controller = self.View.Controller
	local root = controller:GetRoot()
	local start = index or (if root then self:NearestIndex(root.Position) else 1)
	if not controller:EnterMode("Showroom", function()
		self:_endBrowse()
	end) then
		return
	end
	self.Browsing = true
	self.PanelKey = nil
	local hud = controller.FactoryHud
	-- The classic window can open over browse mode (HUD shop button, ButtonY):
	-- the showroom must not react to input meant for it.
	local function blocked(): boolean
		return controller.Modal:IsOpen() or controller:IsBusy() or (controller.Classic ~= nil and controller.Classic.IsOpen)
	end
	hud:ShowCarousel(function()
		if not blocked() then
			self:Select((self.Selected or 1) - 1)
		end
	end, function()
		if not blocked() then
			self:Select((self.Selected or 1) + 1)
		end
	end)
	self:_setHint(nil, false)

	local lastStick = 0
	ContextActionService:BindActionAtPriority("ShowroomNav", function(_, inputState, input)
		if blocked() then
			return Enum.ContextActionResult.Pass
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Thumbstick1 then
			local x = input.Position.X
			if math.abs(x) > 0.65 and os.clock() - lastStick > 0.35 then
				lastStick = os.clock()
				self:Select((self.Selected or 1) + (if x > 0 then 1 else -1))
			end
			return Enum.ContextActionResult.Sink
		end
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		if key == Enum.KeyCode.Left or key == Enum.KeyCode.A or key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.ButtonL1 then
			self:Select((self.Selected or 1) - 1)
		elseif key == Enum.KeyCode.Right or key == Enum.KeyCode.D or key == Enum.KeyCode.DPadRight or key == Enum.KeyCode.ButtonR1 then
			self:Select((self.Selected or 1) + 1)
		elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.ButtonA then
			-- same path as clicking the Main button (also equips the starter)
			local button = hud:GetButton("Main")
			local action = self.MainAction
			if button and button.Enabled and action then
				task.spawn(action)
			end
		elseif key == Enum.KeyCode.T or key == Enum.KeyCode.ButtonX then
			local entry = self.Podiums[self.Selected or 1]
			local chamber = self.View:Zone("TestChamber")
			if entry and chamber and not entry.Locked then
				chamber:Start(entry.VacuumId)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.A, Enum.KeyCode.D, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1, Enum.KeyCode.Return, Enum.KeyCode.ButtonA, Enum.KeyCode.T, Enum.KeyCode.ButtonX, Enum.KeyCode.Thumbstick1)
	self.BrowseTrove:Add(function()
		ContextActionService:UnbindAction("ShowroomNav")
	end)
	self.BrowseTrove:Connect(UserInputService.TouchSwipe, function(direction, _touches, processed)
		if processed or blocked() then
			return
		end
		if direction == Enum.SwipeDirection.Left then
			self:Select((self.Selected or 1) + 1)
		elseif direction == Enum.SwipeDirection.Right then
			self:Select((self.Selected or 1) - 1)
		end
	end)
	self:Select(start, true)
end

function Showroom:_endBrowse()
	self.BrowseTrove:Clean()
	self.Browsing = false
	self.Selected = nil
	self.MainAction = nil
	self.PanelKey = nil
	self.PanelStale = false
	local hud = self.View.Controller.FactoryHud
	hud:HideCarousel()
	hud:HidePanel()
	hud:SetHint(nil)
end

function Showroom:IsBrowsing(): boolean
	return self.Browsing
end

-- Low Graphics toggled while near the factory: switch the sparkle emitters and
-- orb trails in place instead of rebuilding every podium.
function Showroom:QualityChanged()
	local low = Effects.IsLow()
	for _, entry in self.Podiums do
		local visible = entry.Fade < 0.5
		if entry.Rise then
			entry.Rise.Rate = Effects.Count(entry.RiseRate or 3)
			entry.Rise.Enabled = visible and not low
		end
		for _, orb in entry.Orbs or {} do
			orb.Trail.Enabled = visible and not low
		end
	end
end

function Showroom:Destroy()
	if self.Browsing then
		self.View.Controller:ExitMode("Showroom")
	end
	self.Trove:Clean()
end

return Showroom
