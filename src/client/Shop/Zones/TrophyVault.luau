-- Trophy Vault (boss shop): a round vault door that only opens for players
-- holding boss cores. Inside, pedestals show the boss trophies: owned ones
-- fully animated (the Mini Rust Dragon breathes fire), missing ones as
-- holograms you can buy with cores.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Definitions = Shared.Definitions
local Trophies = require(Definitions.Trophies)
local Bosses = require(Definitions.Bosses)
local Currencies = require(Definitions.Currencies)
local Rarities = require(Definitions.Rarities)
local Factory = require(Definitions.Factory)
local Shop = require(Definitions.Shop)
local Format = require(Shared.Util.Format)
local Builder = require(Shared.Util.Builder)
local Trove = require(Shared.Util.Trove)
local TrophyModel = require(Shared.Models.TrophyModel)

local ShopFolder = script.Parent.Parent
local UI = require(ShopFolder.UI.Components)
local Theme = require(ShopFolder.UI.Theme)
local Audio = require(ShopFolder.Audio)
local Effects = require(ShopFolder.Effects)
local CameraDirector = require(ShopFolder.CameraDirector)

local TrophyVault = {}
TrophyVault.__index = TrophyVault

local HOLO = Color3.fromRGB(90, 200, 255)

function TrophyVault.new(view)
	local self = setmetatable({}, TrophyVault)
	self.View = view
	self.Trove = Trove.new()
	self.ActiveTrove = Trove.new()
	self.Trove:Add(self.ActiveTrove, "Clean")
	self.Pedestals = {}
	self.DoorOpen = false
	self.DoorAngle = 0
	self.Focused = nil :: string?

	local folder = view:Find("TrophyVault/Pedestals")
	if folder then
		for _, pedestal in folder:GetChildren() do
			local id = pedestal:GetAttribute("TrophyId")
			local trophy = id and Trophies.Get(id)
			if trophy then
				self.Pedestals[trophy.Id] = {
					Trophy = trophy,
					Top = pedestal:FindFirstChild("Top") :: BasePart,
					Plate = pedestal:FindFirstChild("Plate") :: BasePart,
					Model = nil :: Model?,
					Owned = nil :: boolean?,
					Parts = {},
				}
			end
		end
	end
	self.Anchor = view:Find("TrophyVault/DoorAnchor") :: BasePart?

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

function TrophyVault:_hasAccess(): boolean
	local data = self.View.Controller.ClientData:Get()
	if not data then
		return false
	end
	for _, id in Currencies.Stored do
		local currency = Currencies.Get(id)
		if currency and currency.Kind == "BossCore" and (data.Currencies[id] or 0) > 0 then
			return true
		end
	end
	for _ in data.Trophies do
		return true
	end
	for _, count in data.Progress.Bosses do
		if count > 0 then
			return true
		end
	end
	return false
end

-- Round vault door with spokes, handle wheel and bolts, hinged on the left.
function TrophyVault:_buildDoor()
	local anchor = self.Anchor
	if not anchor then
		return
	end
	local radius = Factory.TrophyVault.DoorRadius
	local model = Instance.new("Model")
	model.Name = "VaultDoor"
	local base = anchor.CFrame
	local steel = Color3.fromRGB(150, 156, 168)
	local gold = Color3.fromRGB(255, 200, 60)
	local function add(props): BasePart
		local p = Builder.Part(props)
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = model
		return p
	end
	local disc = add({ Name = "Disc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, radius * 2, radius * 2), CFrame = base * CFrame.Angles(0, math.pi / 2, 0), Color = steel, Material = Enum.Material.DiamondPlate, Reflectance = 0.1, CanCollide = true })
	add({ Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.8, radius * 1.4, radius * 1.4), CFrame = base * CFrame.new(0, 0, -0.2) * CFrame.Angles(0, math.pi / 2, 0), Color = steel:Lerp(Color3.new(0, 0, 0), 0.2), Material = Enum.Material.Metal, CanCollide = false })
	local wheelParts = {}
	table.insert(wheelParts, add({ Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 2.4, 2.4), CFrame = base * CFrame.new(0, 0, -1.4) * CFrame.Angles(0, math.pi / 2, 0), Color = gold, Material = Enum.Material.Metal, CanCollide = false }))
	for i = 0, 3 do
		table.insert(wheelParts, add({ Name = "Spoke", Size = Vector3.new(0.5, 7, 0.5), CFrame = base * CFrame.new(0, 0, -1.6) * CFrame.Angles(0, 0, i * math.pi / 4), Color = gold, Material = Enum.Material.Metal, CanCollide = false }))
	end
	local bolts = {}
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		table.insert(bolts, add({ Name = "Bolt", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.4, 1, 1), CFrame = base * CFrame.Angles(0, 0, a) * CFrame.new(radius - 0.6, 0, 0), Color = steel:Lerp(Color3.new(1, 1, 1), 0.3), Material = Enum.Material.Metal, CanCollide = false }))
	end
	model.PrimaryPart = disc
	model.Parent = self.View.LocalFolder
	self.ActiveTrove:Add(model)
	self.Door = model
	self.DoorParts = {}
	local hinge = base * CFrame.new(-radius, 0, 0)
	self.Hinge = hinge
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			table.insert(self.DoorParts, { Part = p, Rel = hinge:ToObjectSpace(p.CFrame) })
		end
	end
	self.WheelParts = wheelParts
	self.Bolts = bolts
	self.DoorAngle = 0
	self.DoorOpen = false
end

function TrophyVault:_poseDoor(angle: number, wheel: number, boltOut: number)
	if not self.Door then
		return
	end
	local hinge = self.Hinge :: CFrame
	-- positive angle swings the door out into the corridor, away from the wall
	local swung = hinge * CFrame.Angles(0, angle, 0)
	local parts, frames = {}, {}
	local base = self.Anchor and self.Anchor.CFrame or hinge
	for _, entry in self.DoorParts do
		local cf = swung * entry.Rel
		if table.find(self.WheelParts, entry.Part) then
			local center = swung * hinge:ToObjectSpace(base * CFrame.new(0, 0, -1.4))
			cf = center * CFrame.Angles(0, 0, wheel) * center:ToObjectSpace(cf)
		elseif table.find(self.Bolts, entry.Part) then
			cf = cf * CFrame.new(-boltOut * 1.2, 0, 0)
		end
		table.insert(parts, entry.Part)
		table.insert(frames, cf)
	end
	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	local disc = self.Door:FindFirstChild("Disc") :: BasePart?
	if disc then
		disc.CanCollide = angle < 0.5
	end
end

function TrophyVault:TryOpen()
	if self.DoorOpen or self.DoorBusy or not self.Door then
		return
	end
	local controller = self.View.Controller
	if not self:_hasAccess() then
		Audio.Play("Denied")
		controller.Hud:Toast("The vault only opens for Boss Core holders. Defeat a boss first!", "Warning")
		local start = os.clock()
		self.DoorBusy = true
		local connection
		connection = RunService.Heartbeat:Connect(function()
			local t = os.clock() - start
			self:_poseDoor(math.sin(t * 40) * 0.01, math.sin(t * 30) * 0.15, 0)
			if t > 0.5 then
				connection:Disconnect()
				self:_poseDoor(0, 0, 0)
				self.DoorBusy = false
			end
		end)
		return
	end
	self.DoorBusy = true
	Audio.PlayAt("Clank", self.Anchor.Position)
	local start = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - start
		local wheel = math.min(t / 1.0, 1) * math.pi * 2
		local bolts = math.clamp((t - 0.6) / 0.4, 0, 1)
		local swing = TweenService:GetValue(math.clamp((t - 1.0) / 1.6, 0, 1), Enum.EasingStyle.Quint, Enum.EasingDirection.InOut) * math.rad(105)
		self:_poseDoor(swing, wheel, bolts)
		if t > 2.7 then
			connection:Disconnect()
			self.DoorOpen = true
			self.DoorBusy = false
			self.OpenedAt = os.clock()
		end
	end)
	task.delay(1.0, function()
		if self.Anchor then
			Effects.GlowBall(self.Anchor.Position + self.Anchor.CFrame.LookVector * -4, Color3.fromRGB(255, 210, 120), 18, 1)
			Audio.PlayAt("Fanfare", self.Anchor.Position)
		end
	end)
end

function TrophyVault:_close()
	if not self.DoorOpen or self.DoorBusy then
		return
	end
	self.DoorBusy = true
	local start = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - start
		local swing = (1 - TweenService:GetValue(math.clamp(t / 1.4, 0, 1), Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)) * math.rad(105)
		self:_poseDoor(swing, 0, if t > 1.4 then 0 else 1)
		if t > 1.5 then
			connection:Disconnect()
			self:_poseDoor(0, 0, 0)
			self.DoorOpen = false
			self.DoorBusy = false
			if self.Anchor then
				Audio.PlayAt("Clank", self.Anchor.Position)
			end
		end
	end)
end

-- Trophies -------------------------------------------------------------------------------

local function holoize(model: Model)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "Root" then
			p:SetAttribute("OrigColor", p.Color)
			p:SetAttribute("OrigMaterial", p.Material.Name)
			p:SetAttribute("OrigTransparency", p.Transparency)
			p.Color = HOLO
			p.Material = Enum.Material.Neon
			p.Transparency = 0.65
		end
	end
end

local function materialize(model: Model)
	local parts = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p:GetAttribute("OrigColor") then
			table.insert(parts, p)
		end
	end
	table.sort(parts, function(a, b)
		return a.Position.Y < b.Position.Y
	end)
	for i, p in parts do
		task.delay(i * 0.05, function()
			if not p.Parent then
				return
			end
			p.Material = Enum.Material[p:GetAttribute("OrigMaterial")] or Enum.Material.SmoothPlastic
			TweenService:Create(p, TweenInfo.new(0.35), { Color = p:GetAttribute("OrigColor"), Transparency = p:GetAttribute("OrigTransparency") or 0 }):Play()
		end)
	end
end

function TrophyVault:_buildPedestal(entry, owned: boolean)
	if entry.Model then
		entry.Model:Destroy()
	end
	local model = TrophyModel.Build(entry.Trophy.Model)
	model.Parent = self.View.LocalFolder
	entry.Model = model
	if not owned then
		holoize(model)
	end
	entry.Parts = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= model.PrimaryPart then
			table.insert(entry.Parts, { Part = p, Home = p:GetAttribute("Home") or CFrame.identity })
		end
	end
	entry.Mouth = model:FindFirstChild("Mouth", true)
	entry.NextBreath = os.clock() + math.random() * 3
	self.ActiveTrove:Add(model)

	-- plate text
	local plate = entry.Plate
	if plate then
		local existing = plate:FindFirstChild("TrophyPlate")
		if existing then
			existing:Destroy()
		end
		local face = Enum.NormalId[plate:GetAttribute("Face") or "Right"] or Enum.NormalId.Right
		local gui = UI.new("SurfaceGui", { Name = "TrophyPlate", Face = face, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 40, LightInfluence = 0, Brightness = 1.6, Parent = plate })
		local rarity = Rarities.Get(entry.Trophy.Rarity)
		local currency = Currencies.Get(entry.Trophy.Currency)
		UI.Label({ Text = entry.Trophy.Name, Size = UDim2.fromScale(1, 0.5), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = Theme.Fonts.Title, TextColor3 = rarity.Color, Parent = gui })
		UI.Label({
			Text = if owned then "✔ IN YOUR COLLECTION" else string.format("%s %d %s", currency and currency.Glyph or "", entry.Trophy.Price, currency and currency.Short or ""),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromScale(1, 0.45),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = if owned then Theme.Colors.Success else Theme.Colors.Gold,
			Parent = gui,
		})
		self.ActiveTrove:Add(gui)
	end
end

function TrophyVault:_refresh(animate: boolean)
	local data = self.View.Controller.ClientData:Get()
	for id, entry in self.Pedestals do
		local owned = data ~= nil and data.Trophies[id] == true
		if entry.Owned ~= owned then
			local wasHolo = entry.Owned == false
			if animate and wasHolo and owned and entry.Model then
				materialize(entry.Model)
				Effects.Burst(entry.Top.Position + Vector3.new(0, 2, 0), "Sparks", 40, Rarities.Get(entry.Trophy.Rarity).Color)
				Effects.Confetti(entry.Top.Position + Vector3.new(0, 2, 0), 80)
				task.delay(1.2, function()
					if self.View.Near then
						self:_buildPedestal(entry, true)
					end
				end)
			else
				self:_buildPedestal(entry, owned)
			end
			entry.Owned = owned
		end
	end
end

function TrophyVault:SetActive(active: boolean)
	self.ActiveTrove:Clean()
	self.Door = nil
	self.DoorOpen = false
	self.DoorBusy = false
	for _, entry in self.Pedestals do
		entry.Model = nil
		entry.Owned = nil
	end
	if not active then
		return
	end
	self:_buildDoor()
	self:_poseDoor(0, 0, 0)
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
		for _, entry in self.Pedestals do
			local model = entry.Model
			if model and entry.Top then
				local spin = model:GetAttribute("SpinAll") or 0.25
				local root = entry.Top.CFrame * CFrame.Angles(0, t * spin, 0)
				for _, p in entry.Parts do
					local part = p.Part
					local cf = root * p.Home
					local bob = part:GetAttribute("Bob")
					if bob then
						cf = cf + Vector3.new(0, math.sin(t * 2.2) * bob, 0)
					end
					local wing = part:GetAttribute("Wing")
					local hinge = part:GetAttribute("Hinge")
					if wing and typeof(hinge) == "Vector3" then
						local h = CFrame.new(hinge)
						cf = root * h * CFrame.Angles(0, 0, wing * math.sin(t * 7) * 0.45) * h:Inverse() * p.Home
					elseif part:GetAttribute("Jaw") and typeof(hinge) == "Vector3" then
						local open = if entry.Breathing then 0.35 else 0.05 + math.max(math.sin(t * 2), 0) * 0.08
						local h = CFrame.new(hinge)
						cf = root * h * CFrame.Angles(open, 0, 0) * h:Inverse() * p.Home
					end
					if part:GetAttribute("Pulse") and entry.Owned then
						part.Transparency = 0.1 + 0.2 * (0.5 + 0.5 * math.sin(t * 4))
					end
					table.insert(parts, part)
					table.insert(frames, cf)
				end
				table.insert(parts, model.PrimaryPart)
				table.insert(frames, root)
				-- Fire breath for trophies with a mouth (owned only)
				if entry.Mouth and entry.Owned and t >= entry.NextBreath then
					entry.NextBreath = t + 3 + math.random() * 2
					entry.Breathing = true
					local emitter = Effects.Emitter(entry.Mouth, "Fire", Color3.fromRGB(255, 90, 20), 70)
					emitter.EmissionDirection = Enum.NormalId.Front
					emitter.Enabled = true
					Audio.PlayAt("Tube", entry.Top.Position, { Volume = 0.25, Speed = 1.6 })
					task.delay(0.8, function()
						emitter.Enabled = false
						entry.Breathing = false
						task.wait(1)
						emitter:Destroy()
					end)
				end
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end
		-- Auto close when nobody (locally) is near the vault
		if self.DoorOpen and not self.DoorBusy and self.Anchor and os.clock() - (self.OpenedAt or 0) > 8 then
			local root = self.View.Controller:GetRoot()
			if not root or (root.Position - self.Anchor.Position).Magnitude > 70 then
				self:_close()
			end
		end
	end)
end

-- Focus + purchase -------------------------------------------------------------------------

function TrophyVault:_showPanel(trophyId: string)
	local controller = self.View.Controller
	local data = controller.ClientData:Get()
	local trophy = Trophies.Get(trophyId)
	local item = Shop.Get(trophyId)
	if not trophy or not item or not data then
		return
	end
	local state, reason = Shop.GetState(item, data, workspace:GetServerTimeNow())
	local lines = {
		trophy.Description,
		"Boss: <b>" .. Bosses[trophy.Boss].Name .. "</b>",
	}
	if trophy.Perk then
		table.insert(lines, string.format("Perk: <font color=\"#40D68C\"><b>+%s %s</b></font>", Format.Percent(trophy.Perk.Bonus), trophy.Perk.Stat))
	end
	controller.FactoryHud:ShowPanel({
		Title = trophy.Name,
		Rarity = trophy.Rarity,
		Lines = lines,
		Price = if state == "Available" or state == "Locked" then { Amount = item.Price, Currency = item.Currency, Affordable = Shop.CanAfford(item, data) } else nil,
		Status = if state == "Owned" then "✔ In your collection" elseif state ~= "Available" then "🔒 " .. (reason or state) else nil,
		Buttons = {
			{
				Id = "Buy",
				Text = if state == "Owned" then "Owned" else "Claim Trophy",
				Glyph = "🏆",
				Style = "Gold",
				Enabled = state == "Available" and Shop.CanAfford(item, data),
				OnClick = function()
					self:_buy(trophyId)
				end,
			},
		},
	})
end

function TrophyVault:_buy(trophyId: string)
	local controller = self.View.Controller
	local item = Shop.Get(trophyId)
	local entry = self.Pedestals[trophyId]
	if not item or not entry or self.Buying then
		return
	end
	self.Buying = true
	local result = controller:RequestPurchase(item)
	self.Buying = false
	if not result.Ok then
		controller.Hud:Toast(result.Error or "Purchase failed.", "Error")
		return
	end
	controller:CoinFlight(result.Currency, result.Price or 0, entry.Top.Position + Vector3.new(0, 2, 0))
	local rarity = Rarities.Get(item.Rarity)
	controller.Hud:Banner({ Title = item.Name, Subtitle = "Trophy unlocked  ·  " .. rarity.Name, Rarity = item.Rarity, Style = "Big" })
	CameraDirector.Punch(6)
end

function TrophyVault:Focus(trophyId: string)
	local controller = self.View.Controller
	local entry = self.Pedestals[trophyId]
	if not entry then
		return
	end
	if not self.DoorOpen then
		self:TryOpen()
		if not self:_hasAccess() then
			return
		end
	end
	if not controller:EnterMode("TrophyVault", function()
		self.Focused = nil
		controller.FactoryHud:HidePanel()
		controller.FactoryHud:SetHint(nil)
	end) then
		return
	end
	self.Focused = trophyId
	local top = entry.Top.Position
	local aisle = self.View:ToWorld(Vector3.new(0, 7, self.View:ToLocal(top).Z - 4))
	CameraDirector.GlideTo(CFrame.lookAt(aisle, top + Vector3.new(0, 1.5, 0)), 0.7, Enum.EasingStyle.Quint, 55)
	controller.FactoryHud:SetHint("[Back] Back")
	self:_showPanel(trophyId)
end

function TrophyVault:Destroy()
	self.Trove:Clean()
end

return TrophyVault
