-- Paint shop: your equipped vacuum rides the paint line through the spray
-- booth; skins are sprayed on live part by part, trails are attached on the
-- way through. Browse cosmetics with the carousel, buy or equip from the panel.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Definitions = Shared.Definitions
local Cosmetics = require(Definitions.Cosmetics)
local Vacuums = require(Definitions.Vacuums)
local Rarities = require(Definitions.Rarities)
local Factory = require(Definitions.Factory)
local Shop = require(Definitions.Shop)
local DayNight = require(Shared.Util.DayNight)
local Trove = require(Shared.Util.Trove)
local VacuumModel = require(Shared.Models.VacuumModel)

local ShopFolder = script.Parent.Parent
local Audio = require(ShopFolder.Audio)
local Effects = require(ShopFolder.Effects)
local CameraDirector = require(ShopFolder.CameraDirector)

local PaintShop = {}
PaintShop.__index = PaintShop

local DURATION = 5 -- seconds on the line
local RETURN_GLIDE = 1 -- camera back to the line start before the next run
local BLEND = 0.5 -- camera eases from wherever it is into the tracking shot
local LINGER = 0.7 -- the last mist dies out before a run's emitters go

local function lookKey(vacuumId: string?, skin: string?, trail: string?): string
	return string.format("%s|%s|%s", vacuumId or "", skin or "", trail or "")
end

-- Share of the line covered (0..1) over the run time (0..1): eases off the start,
-- slows to about belt speed through the spray booth at the middle of the line
-- and eases into the end (speed ~ 0.3 (1 - cos 2πa) + 0.7 (1 - cos 4πa)).
local function travel(alpha: number): number
	return alpha - 0.3 * math.sin(2 * math.pi * alpha) / (2 * math.pi) - 0.7 * math.sin(4 * math.pi * alpha) / (4 * math.pi)
end

function PaintShop.new(view)
	local self = setmetatable({}, PaintShop)
	self.View = view
	self.Trove = Trove.new()
	self.ModeTrove = Trove.new()
	self.Trove:Add(self.ModeTrove, "Clean")
	self.Line = view:Find("PaintShop/Line") :: BasePart?
	self.Nozzles = {}
	for _, nozzle in view:Tagged("SprayNozzle") do
		if nozzle:IsA("BasePart") then
			table.insert(self.Nozzles, nozzle)
		end
	end
	self.List = {}
	for _, cosmetic in Cosmetics.BySlot("Skin") do
		table.insert(self.List, cosmetic)
	end
	for _, cosmetic in Cosmetics.BySlot("Trail") do
		table.insert(self.List, cosmetic)
	end
	self.Index = 1
	self.Active = false
	self.Trove:Connect(view.Controller.ClientData.Changed, function()
		if self.Active and not self.Running then
			self:_showPanel()
			self:_refreshDisplay()
		end
	end)
	return self
end

function PaintShop:_lineEnds(): (Vector3, Vector3)
	local config = Factory.PaintShop
	local y = config.LineHeight
	return self.View:ToWorld(Vector3.new(config.LineStartX + 3, y, config.LineZ)), self.View:ToWorld(Vector3.new(config.LineEndX - 3, y, config.LineZ))
end

-- Paint-line camera for a vehicle at `position`: it slides along the line (in
-- the factory's own axes, so rotated factories track too) half as far as the
-- vehicle and looks at it.
function PaintShop:_shot(position: Vector3): CFrame
	local startPos, endPos = self:_lineEnds()
	local axis = (endPos - startPos).Unit
	local camera = self.View:ToWorld(Factory.PaintShop.Camera)
	return CFrame.lookAt(camera + axis * ((position - camera):Dot(axis) * 0.5), position + Vector3.new(0, 1.5, 0))
end

function PaintShop:_spawnDisplay(skinId: string?, trailId: string?, pivot: CFrame?)
	if self.Display then
		self.ModeTrove:Remove(self.Display)
		self.Display:Destroy()
	end
	local controller = self.View.Controller
	local vacuumId = controller.ClientData:Equipped()
	local model = VacuumModel.Build(vacuumId, { Skin = skinId })
	local startPos, endPos = self:_lineEnds()
	-- (placed before the trail goes on, so it draws no streak from the origin)
	model:PivotTo(pivot or CFrame.lookAt(startPos, endPos) * CFrame.Angles(0, math.pi / 2, 0))
	VacuumModel.AttachTrail(model, trailId)
	model.Parent = self.View.LocalFolder
	self.Display = model
	self.DisplayVacuum = vacuumId
	self.DisplaySkin = skinId
	self.DisplayTrail = trailId
	self.ModeTrove:Add(model)
	return model
end

-- Equip / Unequip (any change of the equipped look): the vehicle on the line
-- takes it on where it stands, under a puff of glitter. Other data changes and a
-- previewed paint job still on the line are left alone.
function PaintShop:_refreshDisplay()
	local controller = self.View.Controller
	local data = controller.ClientData:Get()
	local model = self.Display
	if not data or not model or not model.Parent or self.Running or self.Buying then
		return
	end
	local vacuumId = controller.ClientData:Equipped()
	local skin, trail = data.Cosmetics.Skin, data.Cosmetics.Trail
	local key = lookKey(vacuumId, skin, trail)
	if key == self.Seen then
		return
	end
	self.Seen = key
	if key == lookKey(self.DisplayVacuum, self.DisplaySkin, self.DisplayTrail) then
		return
	end
	local pivot = model:GetPivot()
	if self.DisplayVacuum ~= vacuumId then
		self:_spawnDisplay(skin, trail, pivot)
	else
		if self.DisplaySkin ~= skin then
			VacuumModel.ApplySkin(model, skin)
			self.DisplaySkin = skin
		end
		if self.DisplayTrail ~= trail then
			VacuumModel.AttachTrail(model, trail)
			self.DisplayTrail = trail
		end
	end
	local look = Cosmetics.Get(skin)
	Effects.Burst(pivot.Position + Vector3.new(0, 1.5, 0), "Glitter", 24, look and (look.Glow or look.Body) or Color3.new(1, 1, 1))
end

-- Preview and the carousel grey out while a run plays (they would do nothing).
function PaintShop:_lockControls(locked: boolean)
	local hud = self.View.Controller.FactoryHud
	local preview = hud:GetButton("Preview")
	if preview then
		preview:SetEnabled(not locked)
	end
	if hud.PrevButton then
		hud.PrevButton:SetEnabled(not locked)
	end
	if hud.NextButton then
		hud.NextButton:SetEnabled(not locked)
	end
end

-- Drives the model through the booth; parts recolor as they pass the spray plane.
-- `from` is the look the vehicle starts with (default: the equipped one).
function PaintShop:_run(cosmetic: Cosmetics.Cosmetic, from: { Skin: string?, Trail: string? }?)
	if self.Running or not self.Active then
		return
	end
	self.Running = true
	local controller = self.View.Controller
	local current = controller.ClientData:Get()
	local fromSkin = if from then from.Skin else current and current.Cosmetics.Skin
	local fromTrail = if from then from.Trail else current and current.Cosmetics.Trail
	local runTrove = self.ModeTrove:Extend()
	local startPos, endPos = self:_lineEnds()

	-- After a run the painted vehicle waits at the line end: the next one is set
	-- on the line start (out of shot) while the camera glides back, and the
	-- painted one goes once it is out of shot. A vehicle already waiting at the
	-- start is reused, so the run begins without a pop.
	local old: Model? = nil
	local startDelay = 0
	if self.Parked or not (self.Display and self.Display.Parent) then
		old = self.Display
		self.Display = nil
		self:_spawnDisplay(fromSkin, fromTrail)
		if self.Parked then
			local shot = self:_shot(startPos)
			if Effects.ReduceMotion() then
				CameraDirector.Snap(shot, 62)
			else
				CameraDirector.GlideTo(shot, RETURN_GLIDE, Enum.EasingStyle.Sine, 62)
				startDelay = RETURN_GLIDE
			end
		end
	else
		if self.DisplaySkin ~= fromSkin then
			VacuumModel.ApplySkin(self.Display, fromSkin)
			self.DisplaySkin = fromSkin
		end
		if self.DisplayTrail ~= fromTrail then
			VacuumModel.AttachTrail(self.Display, fromTrail)
			self.DisplayTrail = fromTrail
		end
	end
	self.Parked = false
	local model = self.Display :: Model
	local vacuum = Vacuums.Get(model:GetAttribute("VacuumId"))
	local targetLook = if vacuum and cosmetic.Slot == "Skin" then VacuumModel.SkinnedLook(vacuum.Look, cosmetic.Id) else nil
	local rotation = CFrame.lookAt(startPos, endPos).Rotation * CFrame.Angles(0, math.pi / 2, 0)
	local boothX = self.View:ToWorld(Vector3.new(Factory.PaintShop.BoothX, 0, Factory.PaintShop.LineZ))
	local axis = (endPos - startPos).Unit
	local boothAlong = (boothX - startPos):Dot(axis)
	local painted = {}
	local trailDone = false
	local emitters = {}
	local color = if cosmetic.Slot == "Skin" then (cosmetic.Glow or cosmetic.Body or Color3.new(1, 1, 1)) else (cosmetic.Colors and cosmetic.Colors[1] or Color3.new(1, 1, 1))
	-- the mist is the paint going on: body colour, thinning towards the glow
	local mist = if cosmetic.Slot == "Skin" then ColorSequence.new(cosmetic.Body or color, cosmetic.Glow or cosmetic.Body or color) else ColorSequence.new(color)
	for _, nozzle in self.Nozzles do
		local attachment = Instance.new("Attachment")
		local aim = nozzle:GetAttribute("Aim")
		attachment.WorldCFrame = CFrame.lookAt(nozzle.Position, if typeof(aim) == "Vector3" then aim else nozzle.Position - Vector3.yAxis) * CFrame.Angles(-math.pi / 2, 0, 0)
		attachment.Parent = workspace.Terrain
		local emitter = Effects.Emitter(attachment, "Paint", color, 60)
		emitter.Color = mist
		table.insert(emitters, emitter)
		runTrove:Add(attachment)
	end
	local spray = Audio.Loop("Spray", self.Nozzles[1])
	local sprayVolume = 0
	if spray then
		runTrove:Add(spray)
		sprayVolume = spray.Volume
		spray.Volume = 0
	end

	-- The line's slats run with the vehicle meanwhile (BeltSpeed is what the
	-- belt animation reads); Preview and the carousel are locked.
	local line = self.Line
	local idleSpeed = line and line:GetAttribute("BeltSpeed")
	local function driveBelt(speed: number?)
		if line and line.Parent and typeof(idleSpeed) == "number" then
			line:SetAttribute("BeltSpeed", if speed then math.max(speed, idleSpeed) else idleSpeed)
		end
	end
	local locked = true
	self:_lockControls(true)
	local function release()
		if locked then
			locked = false
			self:_lockControls(false)
			driveBelt(nil)
		end
	end
	runTrove:Add(release)

	local camera = workspace.CurrentCamera
	local begin = os.clock() + startDelay
	local length = (endPos - startPos).Magnitude
	local blendFrom: CFrame? = nil
	local fovFrom = 62
	local lastAlong = 0
	local finished = false
	local function stop()
		self.ModeTrove:Remove(runTrove)
		runTrove:Clean()
	end
	runTrove:Connect(RunService.Heartbeat, function(dt: number)
		if not self.Active or not model.Parent then
			-- (mode left or vehicle replaced: nothing of this run stays behind)
			if not finished then
				self.Running = false
			end
			stop()
			return
		end
		local t = os.clock() - begin
		if t < 0 then
			return
		end
		if old then
			self.ModeTrove:Remove(old)
			old:Destroy()
			old = nil
		end
		if finished then
			if spray then
				spray.Volume *= math.max(1 - dt * 10, 0)
			end
			if t >= DURATION + LINGER then
				stop()
			end
			return
		end
		local alpha = math.clamp(t / DURATION, 0, 1)
		local along = travel(alpha) * length
		local cf = CFrame.new(startPos + axis * along) * rotation
		model:PivotTo(cf)
		-- (eases out of wherever the camera is, e.g. a running Enter glide)
		if not blendFrom then
			blendFrom = camera.CFrame
			fovFrom = camera.FieldOfView
		end
		local blend = TweenService:GetValue(math.clamp(t / BLEND, 0, 1), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		CameraDirector.Snap((blendFrom :: CFrame):Lerp(self:_shot(cf.Position), blend), fovFrom + (62 - fovFrom) * blend)
		local near = math.abs(along - boothAlong) < 6
		for _, emitter in emitters do
			emitter.Enabled = near
		end
		if spray then
			-- (fades with the spray instead of cutting on and off)
			spray.Volume += ((if near then sprayVolume else 0) - spray.Volume) * math.min(dt * 12, 1)
		end
		driveBelt((along - lastAlong) / math.max(dt, 1 / 240))
		lastAlong = along
		if targetLook then
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and not painted[part] and part:GetAttribute("Role") then
					if (part.Position - startPos):Dot(axis) >= boothAlong then
						painted[part] = true
						local props = VacuumModel.RoleProps(part:GetAttribute("Role"), targetLook)
						part.Material = props.Material or part.Material
						TweenService:Create(part, TweenInfo.new(0.35), { Color = props.Color, Transparency = props.Transparency, Reflectance = props.Reflectance }):Play()
					end
				end
			end
		elseif cosmetic.Slot == "Trail" and not trailDone and along >= boothAlong then
			trailDone = true
			VacuumModel.AttachTrail(model, cosmetic.Id)
			Effects.Burst(cf.Position + Vector3.new(0, 2, 0), "Glow", 16, color)
		end
		if alpha >= 1 then
			finished = true
			for _, emitter in emitters do
				emitter.Enabled = false
			end
			Effects.Burst(cf.Position + Vector3.new(0, 2, 0), "Sparks", 30, color)
			Audio.Play("Success")
			self.Running = false
			-- the painted vehicle waits at the line end (in shot) until the next run
			if self.Display == model then
				self.Parked = true
				if targetLook then
					self.DisplaySkin = cosmetic.Id
				elseif trailDone then
					self.DisplayTrail = cosmetic.Id
				end
			end
			release()
			self:_showPanel()
			self:_refreshDisplay()
		end
	end)
end

function PaintShop:_selected(): Cosmetics.Cosmetic
	return self.List[self.Index]
end

function PaintShop:_showPanel()
	local controller = self.View.Controller
	local data = controller.ClientData:Get()
	local cosmetic = self:_selected()
	local item = cosmetic and Shop.Get(cosmetic.Id)
	if not cosmetic or not item or not data then
		return
	end
	local state, reason = Shop.GetState(item, data, workspace:GetServerTimeNow(), DayNight.IsNight())
	local buttons = {
		{
			Id = "Preview",
			Text = "Preview",
			Glyph = "🎨",
			Style = "Primary",
			Enabled = not self.Running,
			OnClick = function()
				self:_run(cosmetic)
			end,
		},
	}
	if state == "Available" then
		table.insert(buttons, 1, {
			Id = "Buy",
			Text = "Buy",
			Glyph = "🛒",
			Style = "Gold",
			Enabled = Shop.CanAfford(item, data),
			OnClick = function()
				self:_buy(cosmetic)
			end,
		})
	elseif state == "Owned" or state == "Equipped" then
		table.insert(buttons, 1, {
			Id = "Equip",
			Text = if state == "Equipped" then "Unequip" else "Equip",
			Style = if state == "Equipped" then "Secondary" else "Primary",
			OnClick = function()
				controller:Equip(item)
			end,
		})
	end
	controller.FactoryHud:ShowPanel({
		Title = cosmetic.Name,
		Rarity = cosmetic.Rarity,
		Lines = { cosmetic.Description, (if cosmetic.Slot == "Skin" then "🎨 Skin" else "✨ Trail") .. "  ·  applies to every vacuum" },
		Price = if state == "Available" or state == "NightOnly" then { Amount = item.Price, Currency = item.Currency, Affordable = Shop.CanAfford(item, data) } else nil,
		Status = if state == "Owned" then "✔ Owned" elseif state == "Equipped" then "● Equipped" elseif state ~= "Available" then "🔒 " .. (reason or state) else nil,
		Buttons = buttons,
	})
	controller.FactoryHud:SetCarouselLabel(string.format("%d / %d", self.Index, #self.List))
end

function PaintShop:_buy(cosmetic: Cosmetics.Cosmetic)
	local controller = self.View.Controller
	local item = Shop.Get(cosmetic.Id)
	if not item or self.Buying then
		return
	end
	-- The paint pass starts from the look before the purchase (the server equips
	-- the new cosmetic, and its data sync can arrive before the reply).
	local data = controller.ClientData:Get()
	local from = { Skin = data and data.Cosmetics.Skin, Trail = data and data.Cosmetics.Trail }
	self.Buying = true
	local result = controller:RequestPurchase(item)
	self.Buying = false
	if not result.Ok then
		controller.Hud:Toast(result.Error or "Purchase failed.", "Error")
		return
	end
	local booth = self.View:ToWorld(Vector3.new(Factory.PaintShop.BoothX, 10, Factory.PaintShop.LineZ))
	-- (the coins fly to the screen centre once the paint shop was left meanwhile)
	controller:CoinFlight(result.Currency or "Coins", result.Price or 0, if self.Active then booth else nil)
	local rarity = Rarities.Get(cosmetic.Rarity)
	Effects.Confetti(booth, 60, { rarity.Gradient[1], rarity.Gradient[2], Color3.new(1, 1, 1) })
	controller.Hud:Banner({ Title = cosmetic.Name, Subtitle = "Equipped  ·  " .. rarity.Name, Rarity = cosmetic.Rarity, Style = "Small" })
	-- No paint pass once the mode was left during the round trip (the camera is
	-- not ours any more); a preview of this cosmetic still running already shows
	-- it going on.
	if self.Active and not self.Running then
		self:_run(cosmetic, from)
	end
end

function PaintShop:Enter()
	local controller = self.View.Controller
	if not controller:EnterMode("PaintShop", function()
		self.Active = false
		self.Running = false
		self.Parked = false
		self.ModeTrove:Clean()
		self.Display = nil
		controller.FactoryHud:HidePanel()
		controller.FactoryHud:HideCarousel()
		controller.FactoryHud:SetHint(nil)
	end) then
		return
	end
	self.Active = true
	self.Parked = false
	local data = controller.ClientData:Get()
	local skin = data and data.Cosmetics.Skin
	local trail = data and data.Cosmetics.Trail
	self.Seen = lookKey(controller.ClientData:Equipped(), skin, trail)
	self:_spawnDisplay(skin, trail)
	-- Frames the vehicle waiting at the line start: the shot a run starts from.
	local startPos = self:_lineEnds()
	CameraDirector.GlideTo(self:_shot(startPos), 0.8, Enum.EasingStyle.Quint, 62)
	controller.FactoryHud:ShowCarousel(function()
		if not self.Running then
			self.Index = (self.Index - 2) % #self.List + 1
			self:_showPanel()
		end
	end, function()
		if not self.Running then
			self.Index = self.Index % #self.List + 1
			self:_showPanel()
		end
	end)
	controller.FactoryHud:SetHint("[Keys] Browse paint jobs  ·  [Back] Back")
	self:_showPanel()
end

function PaintShop:Destroy()
	self.Trove:Clean()
end

return PaintShop
