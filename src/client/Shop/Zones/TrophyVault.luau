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
-- How far the vault door swings open: into the vault, so the corridor, the
-- console and whoever opened it stay clear of the steel.
local DOOR_OPEN = math.rad(88)

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
	-- trophies being claimed: their unlock waits for the cores to land (see _buy)
	self.Claiming = {} :: { [string]: boolean }

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
	-- hinge on the left edge of the disc's vault-side face: swinging inwards, the
	-- door clears the frame ring and folds back along the vault wall
	local hinge = base * CFrame.new(-radius, 0, 0.8)
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
	-- positive angle swings the door into the vault, away from the corridor
	local swung = hinge * CFrame.Angles(0, -angle, 0)
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
		-- solid while shut, never a moving collider that shoves a player
		disc.CanCollide = math.abs(angle) < 0.05
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
		connection = self.ActiveTrove:Connect(RunService.Heartbeat, function()
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
	local revealed = false
	local connection
	connection = self.ActiveTrove:Connect(RunService.Heartbeat, function()
		local t = os.clock() - start
		local wheel = math.min(t / 1.0, 1) * math.pi * 2
		local bolts = math.clamp((t - 0.6) / 0.4, 0, 1)
		local swing = TweenService:GetValue(math.clamp((t - 1.0) / 1.6, 0, 1), Enum.EasingStyle.Quint, Enum.EasingDirection.InOut) * DOOR_OPEN
		self:_poseDoor(swing, wheel, bolts)
		-- the vault lights up once the door is open far enough to see inside
		if not revealed and swing >= DOOR_OPEN * 0.4 then
			revealed = true
			self:_reveal()
		end
		if t > 2.7 then
			connection:Disconnect()
			self.DoorOpen = true
			self.DoorBusy = false
			self.OpenedAt = os.clock()
			self:_settleDoor()
		end
	end)
end

-- Open and at rest, the door is solid again (nobody walks through the steel),
-- unless the local player stands right where it stopped.
function TrophyVault:_settleDoor()
	local disc = if self.Door then self.Door:FindFirstChild("Disc") :: BasePart? else nil
	if not disc then
		return
	end
	local root = self.View.Controller:GetRoot()
	local clear = true
	if root then
		-- (a cylinder's axis is its X: across the slab; the disc lies in its YZ plane)
		local p = disc.CFrame:PointToObjectSpace(root.Position)
		clear = math.abs(p.X) > disc.Size.X / 2 + 3 or Vector2.new(p.Y, p.Z).Magnitude > disc.Size.Y / 2 + 3
	end
	disc.CanCollide = clear
end

-- Golden light floods out of the opening vault. The glow and the light fan sit
-- deep inside, beyond the door's sweep (19 studs around the hinge), so the
-- swinging steel never cuts through them; the opening uncovers them.
function TrophyVault:_reveal()
	local anchor = self.Anchor
	if not anchor then
		return
	end
	local inward = -anchor.CFrame.LookVector
	local doorway = anchor.Position + inward * 2
	local deep = anchor.Position + inward * 26
	Effects.FlashLight(doorway, Color3.fromRGB(255, 220, 150), 6, 40, 2.5)
	Effects.Burst(doorway, "Glitter", 40, Color3.fromRGB(255, 210, 120))
	Effects.GlowBall(deep, Color3.fromRGB(255, 210, 120), 14, 1)
	local fan = Effects.LightFan(deep, { Color3.fromRGB(255, 214, 120), Color3.fromRGB(255, 245, 210) }, 12, 16)
	self.ActiveTrove:Add(fan.Stop)
	task.delay(2.6, fan.Stop)
	Audio.PlayAt("Fanfare", anchor.Position)
end

function TrophyVault:_close()
	if not self.DoorOpen or self.DoorBusy then
		return
	end
	self.DoorBusy = true
	local start = os.clock()
	local connection
	connection = self.ActiveTrove:Connect(RunService.Heartbeat, function()
		local t = os.clock() - start
		local swing = (1 - TweenService:GetValue(math.clamp(t / 1.4, 0, 1), Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)) * DOOR_OPEN
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

-- Hologram to solid, part by part from the bottom up. Returns how long it takes.
local function materialize(model: Model): number
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
			local tween = TweenService:Create(p, TweenInfo.new(0.35), { Color = p:GetAttribute("OrigColor"), Transparency = p:GetAttribute("OrigTransparency") or 0 })
			-- solid now: the glow pulse may drive its transparency again
			tween.Completed:Connect(function()
				p:SetAttribute("OrigColor", nil)
				p:SetAttribute("OrigMaterial", nil)
				p:SetAttribute("OrigTransparency", nil)
			end)
			tween:Play()
		end)
	end
	return #parts * 0.05 + 0.35
end

-- Places a trophy for time t (turntable spin, bob, wing flap, jaw, glow pulse)
-- and appends its parts to the BulkMoveTo lists.
local function poseTrophy(entry, t: number, parts: { BasePart }, frames: { CFrame })
	local root = entry.Top.CFrame * CFrame.Angles(0, t * entry.Spin, 0)
	for _, p in entry.Parts do
		local part = p.Part
		local cf = root * p.Home
		if p.Bob then
			cf = cf + Vector3.new(0, math.sin(t * 2.2) * p.Bob, 0)
		end
		if p.Wing and p.Hinge then
			cf = root * p.Hinge * CFrame.Angles(0, 0, p.Wing * math.sin(t * 7) * 0.45) * p.HingeInverse * p.Home
		elseif p.Jaw and p.Hinge then
			local open = if entry.Breathing then 0.35 else 0.05 + math.max(math.sin(t * 2), 0) * 0.08
			cf = root * p.Hinge * CFrame.Angles(open, 0, 0) * p.HingeInverse * p.Home
		end
		-- (not while it still materializes: the sweep tweens its transparency)
		if p.Pulse and entry.Owned and part:GetAttribute("OrigColor") == nil then
			part.Transparency = 0.1 + 0.2 * (0.5 + 0.5 * math.sin(t * 4))
		end
		table.insert(parts, part)
		table.insert(frames, cf)
	end
	table.insert(parts, entry.Model.PrimaryPart)
	table.insert(frames, root)
end

function TrophyVault:_buildPedestal(entry, owned: boolean)
	if entry.Model then
		entry.Model:Destroy()
	end
	local model = TrophyModel.Build(entry.Trophy.Model)
	local root = model.PrimaryPart :: BasePart
	entry.Model = model
	if not owned then
		holoize(model)
	end
	entry.Parts = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			-- (an imported asset may come unanchored: the turntable moves every part)
			p.Anchored = true
			if p ~= root then
				local home = p:GetAttribute("Home")
				local hinge = p:GetAttribute("Hinge")
				local hingeCf = if typeof(hinge) == "Vector3" then CFrame.new(hinge) else nil
				table.insert(entry.Parts, {
					Part = p,
					-- an imported asset has no Home attributes: keep its own layout around the root
					Home = if typeof(home) == "CFrame" then home else root.CFrame:ToObjectSpace(p.CFrame),
					Bob = p:GetAttribute("Bob"),
					Wing = p:GetAttribute("Wing"),
					Jaw = p:GetAttribute("Jaw"),
					Pulse = p:GetAttribute("Pulse"),
					Hinge = hingeCf,
					HingeInverse = if hingeCf then hingeCf:Inverse() else nil,
				})
			end
		end
	end
	entry.Spin = model:GetAttribute("SpinAll") or 0.25
	entry.Mouth = model:FindFirstChild("Mouth", true)
	entry.NextBreath = os.clock() + math.random() * 3
	model.Parent = self.View.LocalFolder
	-- posed in the same frame: it was built around the world origin
	if entry.Top then
		local parts, frames = {}, {}
		poseTrophy(entry, os.clock(), parts, frames)
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	self.ActiveTrove:Add(model)
	self:_buildPlate(entry, owned)
end

-- Name and price (or "in your collection") on the pedestal's front plate.
function TrophyVault:_buildPlate(entry, owned: boolean)
	local plate = entry.Plate
	if not plate then
		return
	end
	local existing = plate:FindFirstChild("TrophyPlate")
	if existing then
		existing:Destroy()
	end
	local face = Enum.NormalId[plate:GetAttribute("Face") or "Right"] or Enum.NormalId.Right
	-- (sharp up close: the focus shot and players walking up see it from a few studs)
	local gui = UI.new("SurfaceGui", { Name = "TrophyPlate", Face = face, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 120, LightInfluence = 0, Brightness = 1.6, Parent = plate })
	local rarity = Rarities.Get(entry.Trophy.Rarity)
	local currency = Currencies.Get(entry.Trophy.Currency)
	UI.Label({ Text = entry.Trophy.Name, Position = UDim2.fromScale(0.05, 0.08), Size = UDim2.fromScale(0.9, 0.44), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = Theme.Fonts.Title, TextColor3 = rarity.Color, Parent = gui })
	UI.Label({
		Text = if owned then "✔ IN YOUR COLLECTION" else string.format("%s %d %s", currency and currency.Glyph or "", entry.Trophy.Price, currency and currency.Short or ""),
		Position = UDim2.fromScale(0.05, 0.56),
		Size = UDim2.fromScale(0.9, 0.34),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = if owned then Theme.Colors.Success else Theme.Colors.Gold,
		Parent = gui,
	})
	self.ActiveTrove:Add(gui)
end

-- The hologram turns solid in place: sparks and confetti, the plate updates
-- once the sweep is done, the first fire breath comes from the finished trophy.
function TrophyVault:_unlock(entry)
	local model = entry.Model
	local burst = entry.Top.Position + Vector3.new(0, 2, 0)
	local duration = materialize(model)
	Effects.Burst(burst, "Sparks", 40, Rarities.Get(entry.Trophy.Rarity).Color)
	Effects.Confetti(burst, 80)
	entry.NextBreath = os.clock() + duration + 0.6
	task.delay(duration, function()
		if entry.Model == model then
			self:_buildPlate(entry, true)
		end
	end)
end

function TrophyVault:_refresh(animate: boolean)
	local data = self.View.Controller.ClientData:Get()
	if not data then
		-- (nothing to show before the profile arrives: holograms now would replay
		-- the unlock for every owned trophy once it does)
		return
	end
	for id, entry in self.Pedestals do
		local owned = data.Trophies[id] == true
		if entry.Owned ~= owned then
			local wasHolo = entry.Owned == false
			if wasHolo and owned and self.Claiming[id] then
				-- _buy unlocks it once its cores have landed
				continue
			end
			if animate and wasHolo and owned and entry.Model then
				self:_unlock(entry)
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
		-- Every frame while the vault is seen up close (focus shot, the room, the
		-- corridor): wing flaps step visibly at 30 Hz. Throttled from further away.
		local camera = workspace.CurrentCamera
		local close = self.Focused ~= nil or (camera ~= nil and self.Anchor ~= nil and (camera.CFrame.Position - self.Anchor.Position).Magnitude < 90)
		local interval = if Effects.IsLow() then (if close then 1 / 30 else 1 / 15) else (if close then 0 else 1 / 30)
		if accumulator < interval then
			return
		end
		accumulator = 0
		local t = os.clock()
		local parts, frames = {}, {}
		for _, entry in self.Pedestals do
			if entry.Model and entry.Top then
				poseTrophy(entry, t, parts, frames)
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
		-- Auto close once the local player has left the vault and its corridor
		-- (never behind someone still inside: the room reaches 75 studs deep)
		if self.DoorOpen and not self.DoorBusy and self.Anchor and os.clock() - (self.OpenedAt or 0) > 8 then
			local root = self.View.Controller:GetRoot()
			if not root or ((root.Position - self.Anchor.Position).Magnitude > 70 and self.View:RoomAt(root.Position) ~= "TrophyVault") then
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
	if not item or not entry or self.Buying or self.Claiming[trophyId] then
		return
	end
	self.Buying = true
	self.Claiming[trophyId] = true
	local button = controller.FactoryHud:GetButton("Buy")
	if button then
		button:SetLoading(true)
	end
	local result = controller:RequestPurchase(item)
	self.Buying = false
	if button then
		button:SetLoading(false)
	end
	if not result.Ok then
		self.Claiming[trophyId] = nil
		if self.View.Near then
			self:_refresh(true)
		end
		controller.Hud:Toast(result.Error or "Purchase failed.", "Error")
		return
	end
	-- The cores fly onto the trophy first; it unlocks as they land.
	local flight = controller:CoinFlight(result.Currency, result.Price or 0, entry.Top.Position + Vector3.new(0, 2, 0))
	local rarity = Rarities.Get(item.Rarity)
	self.Trove:Add(task.delay(flight, function()
		self.Claiming[trophyId] = nil
		if self.View.Near then
			self:_refresh(true)
		end
		controller.Hud:Banner({ Title = item.Name, Subtitle = "Trophy unlocked  ·  " .. rarity.Name, Rarity = item.Rarity, Style = "Big" })
		CameraDirector.Punch(6)
	end))
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
	-- (drops the pedestal models too, so late unlock callbacks find nothing to touch)
	self:SetActive(false)
	self.Trove:Clean()
end

return TrophyVault
