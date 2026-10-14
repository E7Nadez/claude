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
				self:_showPanel(self.Podiums[self.Selected])
			end
		end
	end)
	return self
end

-- Camera framing for a podium: from the carousel center looking outwards so
-- vacuum and hologram are both in view.
function Showroom:CameraFor(entry): CFrame
	local config = Factory.Showroom
	local center = self.View:ToWorld(config.Center)
	local display = entry.Display.Position
	local flat = (display - center) * Vector3.new(1, 0, 1)
	local dir = flat.Unit
	local camPos = center + dir * (config.PodiumRadius - config.CameraInset) + Vector3.new(0, config.CameraHeight, 0)
	local tangent = Vector3.new(-dir.Z, 0, dir.X)
	local target = display + Vector3.new(0, 2.2, 0) + tangent * (config.HoloOffset * 0.38)
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
	local panel = UI.new("Frame", {
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(10, 14, 24),
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
		UI.Label({ Text = Stats.Glyphs[key] .. " " .. Stats.Labels[key], Position = UDim2.fromOffset(18, y), Size = UDim2.fromOffset(110, 26), TextSize = 18, Parent = panel })
		local track = UI.new("Frame", { Position = UDim2.fromOffset(130, y + 8), Size = UDim2.new(1, -270, 0, 10), BackgroundColor3 = Color3.fromRGB(40, 46, 66), Parent = panel }, { UI.Corner(UDim.new(1, 0)) })
		local ghost = UI.new("Frame", { Name = "Ghost", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.7, Parent = track }, { UI.Corner(UDim.new(1, 0)) })
		local fill = UI.new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Colors.Accent, Parent = track }, { UI.Corner(UDim.new(1, 0)) })
		local value = UI.Label({ Text = "0", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -70, 0, y), Size = UDim2.fromOffset(66, 26), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Theme.Fonts.Numbers, TextSize = 20, Parent = panel })
		local delta = UI.Label({ Text = "", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, y), Size = UDim2.fromOffset(56, 26), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Theme.Fonts.Numbers, TextSize = 15, Parent = panel })
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
	-- Padlock in front of the glass, facing the camera
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
	for _, p in Builder.Ring(lockCf * CFrame.new(0, 0.9, 0), 0.5, 0.18, 0.18, 10, { Material = Enum.Material.Metal, Color = Color3.fromRGB(200, 205, 215), CanCollide = false, CanQuery = false, CanTouch = false }) do
		p.Parent = model
		local rel = (lockCf * CFrame.new(0, 0.9, 0)):PointToObjectSpace(p.Position)
		if rel.Y < -0.1 then
			p:Destroy()
		end
	end
	local label = Builder.Part({
		Name = "Label",
		Size = Vector3.new(6.4, 1.6, 0.05),
		CFrame = entry.Display.CFrame * CFrame.new(0, 5.6, -3.65),
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
	entry.Glass = glass
end

local function shatterCase(entry)
	local case = entry.Case
	if not case then
		return
	end
	entry.Case = nil
	entry.CaseText = nil
	local glass = case:FindFirstChild("Glass") :: BasePart?
	local center = if glass then glass.Position else entry.Display.Position
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
	case:Destroy()
end

-- Activation ------------------------------------------------------------------------------

function Showroom:_buildEntry(entry)
	local vacuum = Vacuums.Get(entry.VacuumId)
	if not vacuum then
		return
	end
	local model = VacuumModel.Build(vacuum.Id)
	model.Parent = self.View.LocalFolder
	entry.Model = model
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
	local rarity = Rarities.Get(vacuum.Rarity)
	entry.Ring.Color = rarity.Color
	local light = entry.Spot and entry.Spot:FindFirstChildOfClass("SpotLight")
	if light then
		light.Color = Color3.new(1, 1, 1):Lerp(rarity.Color, 0.45)
	end
	entry.HoloUi = buildHolo(entry, vacuum)
	self.ActiveTrove:Add(model)
	self.ActiveTrove:Add(entry.HoloUi.Gui)
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
			elseif not locked and entry.Case then
				if animateUnlock and entry.Locked then
					shatterCase(entry)
				else
					entry.Case:Destroy()
					entry.Case = nil
					entry.CaseText = nil
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
		if entry.Case then
			entry.Case:Destroy()
			entry.Case = nil
		end
		entry.Model = nil
		entry.HoloUi = nil
		entry.Locked = nil
	end
	if not active then
		return
	end
	for _, entry in self.Podiums do
		self:_buildEntry(entry)
	end
	self:_refreshStates(false)

	local accumulator = 0
	self.ActiveTrove:Connect(RunService.Heartbeat, function(dt)
		accumulator += dt
		local low = Effects.IsLow()
		if accumulator < (if low then 1 / 20 else 1 / 40) then
			return
		end
		local elapsed = accumulator
		accumulator = 0
		self:_step(elapsed)
	end)
end

function Showroom:_step(dt: number)
	local now = os.clock()
	local parts, frames = {}, {}
	for index, entry in self.Podiums do
		local model = entry.Model
		if model and model.PrimaryPart then
			local selected = index == self.Selected
			entry.Angle += dt * (if selected then 0.9 else 0.35)
			local lift = math.sin(now * 1.6 + index) * 0.15 + 0.35
			local rootCf = entry.Display.CFrame * CFrame.new(0, lift, 0) * CFrame.Angles(0, entry.Angle, 0)
			local amount = if selected and not Effects.ReduceMotion() then explodeAmount(now - self.SelectedAt) else 0
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
		-- animated condition text on locked glass cases
		if entry.CaseText and entry.CaseLines and #entry.CaseLines > 0 then
			local lineIndex = math.floor(now / 3.2) % #entry.CaseLines + 1
			local line = "🔒 " .. entry.CaseLines[lineIndex]
			local typed = math.clamp(math.floor(((now % 3.2) / 1.2) * #line), 1, #line)
			entry.CaseText.Text = string.sub(line, 1, typed)
			entry.CaseText.TextTransparency = 0.1 + 0.25 * (0.5 + 0.5 * math.sin(now * 4))
			if entry.LockBody then
				entry.LockBody.CFrame = entry.Display.CFrame * CFrame.new(0, 2.2 + math.sin(now * 2 + index) * 0.08, -3.75) * CFrame.Angles(0, 0, math.sin(now * 3 + index) * 0.08)
			end
		end
		if index == self.Selected and entry.HoloUi then
			local scanT = (now % 2.4) / 2.4
			entry.HoloUi.Scan.Position = UDim2.fromScale(0, scanT * 1.4 - 0.2)
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
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

function Showroom:_showPanel(entry)
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
	local buttons = {}
	if state == "Equipped" then
		table.insert(buttons, { Id = "Main", Text = "Equipped", Glyph = "●", Style = "Secondary", Enabled = false, OnClick = function() end })
	elseif state == "Owned" then
		table.insert(buttons, {
			Id = "Main",
			Text = "Equip",
			Glyph = "✔",
			Style = "Primary",
			OnClick = function()
				if item then
					local result = controller:Equip(item)
					if result.Ok then
						Audio.Play("Success")
						UI.Pop(entry.HoloUi.Panel, 0.1)
					end
				else
					controller:EquipVacuum(vacuum.Id)
				end
			end,
		})
	elseif #missing > 0 then
		table.insert(buttons, { Id = "Main", Text = "Locked", Glyph = "🔒", Style = "Secondary", Enabled = false, OnClick = function() end })
	elseif item then
		table.insert(buttons, {
			Id = "Main",
			Text = "Buy",
			Glyph = "🛒",
			Style = "Gold",
			Enabled = Shop.CanAfford(item, data),
			OnClick = function()
				controller.Modal:Show(item, { Source = "Factory" })
			end,
		})
	end
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
		Price = if item and not owned then { Amount = Shop.GetPrice(item, data), Currency = item.Currency, Affordable = Shop.CanAfford(item, data) } else nil,
		Status = if #missing > 0 then "🔒 " .. table.concat(missing, " · ") else nil,
		Buttons = buttons,
	})
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
	CameraDirector.GlideTo(self:CameraFor(entry), if firstGlide then 0.9 else 0.55, Enum.EasingStyle.Quint, 62)
	if previous ~= index then
		Audio.Play("Servo")
	end
	local controller = self.View.Controller
	controller.FactoryHud:SetCarouselLabel(string.format("%d / %d", index, count))
	self:_updateHolo(entry, true)
	if entry.HoloUi then
		UI.Pop(entry.HoloUi.Panel, 0.06)
	end
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
	local hud = controller.FactoryHud
	hud:ShowCarousel(function()
		self:Select((self.Selected or 1) - 1)
	end, function()
		self:Select((self.Selected or 1) + 1)
	end)
	hud:SetHint("[Keys] Browse  ·  [Confirm] Buy  ·  [Alt] Try  ·  [Back] Back")

	local lastStick = 0
	ContextActionService:BindActionAtPriority("ShowroomNav", function(_, inputState, input)
		if controller.Modal:IsOpen() or controller:IsBusy() then
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
			local button = hud:GetButton("Main")
			if button and button.Enabled then
				local entry = self.Podiums[self.Selected or 1]
				local item = entry and Shop.Get(entry.VacuumId)
				local data = controller.ClientData:Get()
				if item and data and data.Vacuums.Owned[item.RefId] then
					controller:Equip(item)
				elseif item then
					controller.Modal:Show(item, { Source = "Factory" })
				end
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
		if processed or controller.Modal:IsOpen() or controller:IsBusy() then
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
	local hud = self.View.Controller.FactoryHud
	hud:HideCarousel()
	hud:HidePanel()
	hud:SetHint(nil)
end

function Showroom:IsBrowsing(): boolean
	return self.Browsing
end

function Showroom:Destroy()
	if self.Browsing then
		self.View.Controller:ExitMode("Showroom")
	end
	self.Trove:Clean()
end

return Showroom
