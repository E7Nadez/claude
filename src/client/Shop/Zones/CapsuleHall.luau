-- Capsule Hall: giant claw machines. Opening a capsule is a show: coins into
-- the machine, the claw grabs a capsule, it drops into the marble run, rolls
-- down while the camera follows, wobbles on the reveal pad and bursts open
-- (intensity by the pet's rarity). Skippable at any time.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Definitions = Shared.Definitions
local Capsules = require(Definitions.Capsules)
local Pets = require(Definitions.Pets)
local Rarities = require(Definitions.Rarities)
local Sequences = require(Definitions.Sequences)
local Factory = require(Definitions.Factory)
local Shop = require(Definitions.Shop)
local Boosts = require(Definitions.Boosts)
local Format = require(Shared.Util.Format)
local DayNight = require(Shared.Util.DayNight)
local Builder = require(Shared.Util.Builder)
local Trove = require(Shared.Util.Trove)
local PetModel = require(Shared.Models.PetModel)

local ShopFolder = script.Parent.Parent
local UI = require(ShopFolder.UI.Components)
local Theme = require(ShopFolder.UI.Theme)
local Audio = require(ShopFolder.Audio)
local Effects = require(ShopFolder.Effects)
local CameraDirector = require(ShopFolder.CameraDirector)
local Sequence = require(ShopFolder.Sequence)
local Cinematics = require(ShopFolder.Cinematics)

local CapsuleHall = {}
CapsuleHall.__index = CapsuleHall

-- Claw rig inside the Ø10 glass dome, relative to DomeCenter. The cable top,
-- the idle drift (radius <= 3.1), the balls it grabs (<= CLAW_REACH off the
-- axis) and the release point on the chute side all stay inside the glass.
local CLAW_TOP = 3.8
local CLAW_HEIGHT = 2.2
local CLAW_REACH = 2.6
local CLAW_RELEASE = 2.6 -- release point, towards the chute
local HOLD = 1.2 -- capsule centre below the claw head while carried
local GRIP = 0.3 -- prong opening while holding (tips rest on the capsule)

local function ease(t: number, style: Enum.EasingStyle?): number
	return TweenService:GetValue(math.clamp(t, 0, 1), style or Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
end

local function animate(seq, duration: number, fn: (number) -> ()): boolean
	local start = os.clock()
	while true do
		if seq.Stopped then
			return false
		end
		local alpha = math.clamp((os.clock() - start) / math.max(duration, 0.001), 0, 1)
		fn(alpha)
		if alpha >= 1 then
			return true
		end
		RunService.Heartbeat:Wait()
	end
end

local function ball(color: Color3, size: number, parent: Instance): BasePart
	return Builder.Part({
		Name = "Capsule",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * size,
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = parent,
	})
end

-- Offset of a pile ball from DomeCenter that keeps the Ø1.5 ball inside the glass.
local function pileOffset(rng: Random): Vector3
	local offset = Vector3.zero
	for _ = 1, 10 do
		offset = Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(-3.2, -1.2), rng:NextNumber(-3, 3))
		if offset.Magnitude <= 4.1 then
			break
		end
	end
	return offset
end

-- Horizontal unit vector from the dome towards the chute (the machine's front).
local function frontOf(machine): Vector3
	local front = (machine.Chute.Position - machine.DomeCenter.Position) * Vector3.new(1, 0, 1)
	return if front.Magnitude > 0.01 then front.Unit else Vector3.new(0, 0, -1)
end

-- Same luck as the server roll and the odds panel (boosts x Lucky Hands).
local function luckFor(data: any): number
	if not data then
		return 1
	end
	return Boosts.ActiveMultiplier(data.Boosts, "Luck", workspace:GetServerTimeNow()) * (if data.Gamepasses.gp_lucky then 1.5 else 1)
end

-- Removes a show part with a short fade (at once when the show was cancelled).
local function fadeAway(part: BasePart, instant: boolean)
	if instant or not part.Parent then
		part:Destroy()
		return
	end
	TweenService:Create(part, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Transparency = 1 }):Play()
	task.delay(0.3, function()
		part:Destroy()
	end)
end

-- Shrinks and fades a revealed pet (and its plate) away, then destroys it, so it
-- does not blink out while the camera is still on it.
local function dissolve(model: Model, duration: number)
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			table.insert(parts, { Part = d, From = d.Transparency })
		elseif d:IsA("TextLabel") then
			TweenService:Create(d, TweenInfo.new(duration * 0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end
	local scale = model:GetScale()
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local alpha = math.min((os.clock() - start) / duration, 1)
		if alpha >= 1 or not model.Parent then
			connection:Disconnect()
			model:Destroy()
			return
		end
		local e = ease(alpha)
		for _, entry in parts do
			entry.Part.Transparency = entry.From + (1 - entry.From) * e
		end
		model:ScaleTo(scale * (1 - 0.5 * e))
	end)
end

function CapsuleHall.new(view)
	local self = setmetatable({}, CapsuleHall)
	self.View = view
	self.Trove = Trove.new()
	self.ActiveTrove = Trove.new()
	self.Trove:Add(self.ActiveTrove, "Clean")
	self.Machines = {}
	self.Focused = nil :: string?
	self.Opening = false

	for _, capsule in Capsules.ForWorld(view.World) do
		local model = view:Find("CapsuleHall/Machine_" .. capsule.Id)
		local run = view:Find("CapsuleHall/Runs/Run_" .. capsule.Id)
		if model then
			local points = {}
			if run then
				local wps = {}
				for _, wp in run:GetChildren() do
					if wp:IsA("BasePart") and string.sub(wp.Name, 1, 3) == "WP_" then
						table.insert(wps, wp)
					end
				end
				table.sort(wps, function(a, b)
					return a.Name < b.Name
				end)
				for _, wp in wps do
					table.insert(points, wp.Position)
				end
			end
			self.Machines[capsule.Id] = {
				Capsule = capsule,
				Model = model,
				DomeCenter = model:FindFirstChild("DomeCenter") :: BasePart,
				Chute = model:FindFirstChild("Chute") :: BasePart,
				Sign = model:FindFirstChild("Sign") :: BasePart,
				Panel = model:FindFirstChild("Panel") :: BasePart,
				Path = points,
				Balls = {},
				Claw = nil,
				ClawHome = nil :: CFrame?,
				ClawPos = nil :: Vector3?,
			}
		end
	end
	self.RevealPad = view:Find("CapsuleHall/RevealPad") :: BasePart?

	self.Trove:Connect(view.Controller.ClientData.Changed, function()
		if self.Focused and not self.Opening then
			self:_showPanel(self.Focused)
		end
	end)
	return self
end

-- Claw made of parts: cable + head + three prongs.
local function buildClaw(parent: Instance, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "Claw"
	local head = Builder.Part({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.1, Color = Color3.fromRGB(200, 205, 215), Material = Enum.Material.Metal, CanCollide = false, CanQuery = false, CanTouch = false, Parent = model })
	model.PrimaryPart = head
	Builder.Part({ Name = "Cable", Size = Vector3.new(0.12, 1, 0.12), Color = Color3.fromRGB(40, 40, 46), CanCollide = false, CanQuery = false, CanTouch = false, Parent = model })
	for i = 1, 3 do
		local prong = Builder.Part({ Name = "Prong" .. i, Size = Vector3.new(0.18, 1.1, 0.25), Color = color, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CanTouch = false, Parent = model })
		prong:SetAttribute("Angle", (i - 1) / 3 * math.pi * 2)
	end
	model.Parent = parent
	return model
end

-- Places the claw head at `position`, cable up to `top`, prongs open 0..1.
local function poseClaw(claw: Model, position: Vector3, top: Vector3, open: number)
	local head = claw:FindFirstChild("Head") :: BasePart
	local cable = claw:FindFirstChild("Cable") :: BasePart
	head.CFrame = CFrame.new(position)
	local length = math.max(top.Y - position.Y, 0.1)
	cable.Size = Vector3.new(0.12, length, 0.12)
	cable.CFrame = CFrame.new(position.X, position.Y + length / 2, position.Z)
	for i = 1, 3 do
		local prong = claw:FindFirstChild("Prong" .. i) :: BasePart
		local angle = prong:GetAttribute("Angle") :: number
		prong.CFrame = CFrame.new(position) * CFrame.Angles(0, angle, 0) * CFrame.new(0, -0.6, 0.35) * CFrame.Angles(-0.35 - open * 0.6, 0, 0)
	end
end

function CapsuleHall:SetActive(active: boolean)
	self.ActiveTrove:Clean()
	for _, machine in self.Machines do
		machine.Balls = {}
		machine.Claw = nil
	end
	if not active then
		return
	end
	local rng = Random.new()
	for _, machine in self.Machines do
		local center = machine.DomeCenter.Position
		local color = machine.Capsule.Color
		local count = if Effects.IsLow() then 8 else 18
		for i = 1, count do
			local tint = color:Lerp(Color3.fromHSV(rng:NextNumber(), 0.6, 1), 0.35)
			local b = ball(tint, 1.5, self.View.LocalFolder)
			b.CFrame = CFrame.new(center + pileOffset(rng)) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
			table.insert(machine.Balls, { Part = b, Base = b.CFrame, Phase = i })
			self.ActiveTrove:Add(b)
		end
		local claw = buildClaw(self.View.LocalFolder, color)
		self.ActiveTrove:Add(claw)
		machine.Claw = claw
		machine.ClawTop = center + Vector3.new(0, CLAW_TOP, 0)
		machine.ClawPos = center + Vector3.new(0, CLAW_HEIGHT, 0)
		poseClaw(claw, machine.ClawPos, machine.ClawTop, 0.6)
	end

	local accumulator = 0
	self.ActiveTrove:Connect(RunService.Heartbeat, function(dt)
		accumulator += dt
		if accumulator < 1 / 20 then
			return
		end
		accumulator = 0
		local t = os.clock()
		local night = DayNight.IsNight()
		for id, machine in self.Machines do
			if machine.Claw and not (self.Opening and self.OpeningId == id) then
				local center = machine.DomeCenter.Position
				local drift = Vector3.new(math.sin(t * 0.6 + #id) * 2.2, CLAW_HEIGHT, math.cos(t * 0.45 + #id) * 2.2)
				-- Eases back into the drift after a show instead of jumping there.
				local current = machine.ClawPos
				machine.ClawPos = if current then current:Lerp(center + drift, 0.25) else center + drift
				poseClaw(machine.Claw, machine.ClawPos, machine.ClawTop, 0.6 + math.sin(t) * 0.1)
			end
			if machine.Capsule.NightOnly and machine.Panel then
				machine.Panel.Transparency = if night then 0.3 else 0.85
			end
		end
		-- Night-only capsules open and close at dusk / dawn: refresh the panel.
		if night ~= self.LastNight then
			self.LastNight = night
			local focused = if self.Focused then Capsules.Get(self.Focused) else nil
			if focused and focused.NightOnly and not self.Opening then
				self:_showPanel(focused.Id)
			end
		end
	end)
end

-- Focus + panel ------------------------------------------------------------------------------

function CapsuleHall:_showPanel(capsuleId: string)
	local controller = self.View.Controller
	local data = controller.ClientData:Get()
	local capsule = Capsules.Get(capsuleId)
	local item = Shop.Get(capsuleId)
	if not capsule or not item or not data then
		return
	end
	local state, reason = Shop.GetState(item, data, workspace:GetServerTimeNow())
	local luck = luckFor(data)
	local lines = { capsule.Description }
	for _, entry in Capsules.EffectiveDrops(capsuleId, luck) do
		local pet = Pets.Get(entry.Pet)
		if pet then
			local rarity = Rarities.Get(pet.Rarity)
			table.insert(lines, string.format("<font color=\"#%s\">●</font> %s  <b>%s</b>", rarity.Color:ToHex(), pet.Name, Format.Chance(entry.Chance)))
		end
	end
	local canOpen = state == "Available" and Shop.CanAfford(item, data) and #data.Pets < data.PetCapacity
	controller.FactoryHud:ShowPanel({
		Title = capsule.Name,
		Rarity = capsule.Rarity,
		Lines = lines,
		Price = { Amount = Shop.GetPrice(item, data), Currency = item.Currency, Affordable = Shop.CanAfford(item, data) },
		Status = if state ~= "Available" then "🔒 " .. (reason or state) elseif #data.Pets >= data.PetCapacity then "Pet inventory full" else (if luck > 1 then "🍀 Luck x" .. Format.Stat(luck) else nil),
		Buttons = {
			{
				Id = "Open",
				Text = "Open Capsule",
				Glyph = "🥚",
				Style = "Gold",
				Enabled = canOpen,
				OnClick = function()
					self:Open(capsuleId)
				end,
			},
			{
				Text = "Odds & Details",
				Style = "Ghost",
				OnClick = function()
					-- OnConfirm: opening from the details goes through the claw machine show.
					controller.Modal:Show(item, {
						Source = "Classic",
						OnConfirm = function()
							self:Open(capsuleId)
						end,
					})
				end,
			},
		},
	})
end

function CapsuleHall:_focusCamera(machine)
	local center = machine.DomeCenter.Position
	local chute = machine.Chute.Position
	local front = (chute - center) * Vector3.new(1, 0, 1)
	local camPos = center + front.Unit * 18 + Vector3.new(0, 1, 0)
	-- Long returns (from the reveal pad) take longer and ease evenly instead of whipping across the hall.
	local duration = math.clamp((workspace.CurrentCamera.CFrame.Position - camPos).Magnitude / 45, 0.7, 1.6)
	CameraDirector.GlideTo(CFrame.lookAt(camPos, center - Vector3.new(0, 1.5, 0)), duration, if duration > 0.75 then Enum.EasingStyle.Sine else Enum.EasingStyle.Quint, 60)
end

function CapsuleHall:Focus(capsuleId: string)
	local machine = self.Machines[capsuleId]
	local controller = self.View.Controller
	-- Not while a capsule is being opened (also during the purchase round trip,
	-- before the show starts): the show and its refocus belong to that machine.
	if not machine or self.Opening then
		return
	end
	if not controller:EnterMode("CapsuleHall", function()
		self.Focused = nil
		controller.FactoryHud:HidePanel()
		controller.FactoryHud:HideCarousel()
		controller.FactoryHud:SetHint(nil)
	end) then
		return
	end
	self.Focused = capsuleId
	self:_focusCamera(machine)
	local order = {}
	for _, capsule in Capsules.ForWorld(self.View.World) do
		if self.Machines[capsule.Id] then
			table.insert(order, capsule.Id)
		end
	end
	controller.FactoryHud:ShowCarousel(function()
		local i = table.find(order, self.Focused or capsuleId) or 1
		self:Focus(order[(i - 2) % #order + 1])
	end, function()
		local i = table.find(order, self.Focused or capsuleId) or 1
		self:Focus(order[i % #order + 1])
	end)
	controller.FactoryHud:SetCarouselLabel(string.format("%d / %d", table.find(order, capsuleId) or 1, #order))
	controller.FactoryHud:SetHint("[Keys] Next machine  ·  [Back] Back")
	self:_showPanel(capsuleId)
end

-- Opening show ---------------------------------------------------------------------------------

function CapsuleHall:Open(capsuleId: string)
	local controller = self.View.Controller
	local machine = self.Machines[capsuleId]
	local item = Shop.Get(capsuleId)
	if not machine or not item or self.Opening or controller:IsBusy() then
		return
	end
	self.Opening = true
	self.OpeningId = capsuleId
	self.ReactionsDeferred = false
	local button = controller.FactoryHud:GetButton("Open")
	if button then
		button:SetLoading(true)
	end
	local result = controller:RequestPurchase(item)
	if button then
		button:SetLoading(false)
	end
	if not result.Ok then
		self.Opening = false
		controller.Hud:Toast(result.Error or "Could not open capsule.", "Error")
		return
	end
	local pet = Pets.Get(result.PetId)
	if not pet then
		self.Opening = false
		return
	end
	self:_play(machine, pet, result)
end

function CapsuleHall:_play(machine, pet: Pets.Pet, result: { [string]: any })
	local controller = self.View.Controller
	local rarity = Rarities.Get(pet.Rarity)
	local profile = Sequences.Get(pet.Rarity)
	local timings = Sequences.Timings
	local pad = self.RevealPad
	local seq = Sequence.new("Capsule")
	local state = { Revealed = false }
	local stops: { () -> () } = {}
	local revealPos = if pad then pad.Position + Vector3.new(0, 1.6, 0) else machine.DomeCenter.Position
	local revealShot = if pad then CFrame.lookAt(self.View:ToWorld(Factory.CapsuleHall.Camera), revealPos) else nil
	local chance = 0
	for _, entry in Capsules.EffectiveDrops(machine.Capsule.Id, luckFor(controller.ClientData:Get())) do
		if entry.Pet == pet.Id then
			chance = entry.Chance
		end
	end

	local function reveal(owner)
		if state.Revealed then
			return
		end
		state.Revealed = true
		local petModel = PetModel.Build(pet.Id)
		petModel.Parent = self.View.LocalFolder
		-- Dissolves when the show is cleaned up; vanishes at once when it was cancelled.
		owner.Trove:Add(function()
			if owner.Cancelled then
				petModel:Destroy()
			else
				dissolve(petModel, 0.4)
			end
		end)
		local camera = workspace.CurrentCamera
		local faceTo = Vector3.new(camera.CFrame.Position.X, revealPos.Y, camera.CFrame.Position.Z)
		local baseCf = CFrame.lookAt(revealPos - Vector3.new(0, 1.2, 0), faceTo)
		petModel:PivotTo(baseCf * CFrame.new(0, -2, 0))
		-- Info plate under the pet's feet: the HUD banner above already shows name and
		-- rarity, so the plate never sits under it. Fades in once the pet has risen.
		local tag = UI.new("BillboardGui", { Size = UDim2.fromOffset(240, 58), StudsOffset = Vector3.new(0, -1.1, 0), AlwaysOnTop = true, Adornee = petModel.PrimaryPart, Parent = petModel })
		local plate = {
			UI.Label({ Text = string.upper(rarity.Name) .. "  ·  x" .. Format.Stat(pet.Multiplier), Size = UDim2.new(1, 0, 0.56, 0), TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, TextColor3 = rarity.Color, FontFace = Theme.Fonts.Title, Parent = tag }),
			UI.Label({ Text = Format.Chance(chance), Position = UDim2.fromScale(0, 0.6), Size = UDim2.new(1, 0, 0.4, 0), TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, TextColor3 = Theme.Colors.SubText, Parent = tag }),
		}
		for _, label in plate do
			label.TextTransparency = 1
			label.TextStrokeTransparency = 1
			UI.Tween(label, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.4), { TextTransparency = 0, TextStrokeTransparency = 0.3 })
		end
		Effects.GlowBall(revealPos, rarity.Color, 12, 0.6)
		Effects.Shockwave(revealPos - Vector3.new(0, 1.4, 0), rarity.Color, 14)
		Effects.FlashLight(revealPos, rarity.Color, 8, 30, 0.8)
		if profile.Pillar then
			local pillar = Builder.Part({
				Name = "LightPillar",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.5, 5, 5),
				CFrame = CFrame.new(revealPos - Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
				Material = Enum.Material.Neon,
				Color = rarity.Color,
				Transparency = 0.35,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Parent = self.View.LocalFolder,
			})
			local retired = false
			owner.Trove:Add(function()
				retired = true
				fadeAway(pillar, owner.Cancelled)
			end)
			local rise = TweenService:Create(pillar, TweenInfo.new(0.45, Enum.EasingStyle.Quint), {
				Size = Vector3.new(60, 4, 4),
				CFrame = CFrame.new(revealPos + Vector3.new(0, 28.5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			})
			-- Chained: a delayed tween on Size, played right away, would cancel the rise.
			rise.Completed:Once(function(playbackState)
				if playbackState == Enum.PlaybackState.Completed and not retired and pillar.Parent then
					TweenService:Create(pillar, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = Vector3.new(60, 0.5, 0.5) }):Play()
				end
			end)
			rise:Play()
		end
		if Rarities.AtLeast(pet.Rarity, "Epic") then
			local fan = Effects.LightFan(revealPos, { rarity.Gradient[1], rarity.Gradient[2], Color3.new(1, 1, 1) }, 10, 12)
			owner.Trove:Add(fan.Stop)
		end
		if owner.Cine then
			owner.Cine:Impact(rarity.Color, 0.5 + rarity.Rank * 0.1)
			owner.Cine:Focus(revealPos)
		end
		Effects.Burst(revealPos, "Sparks", profile.SparkBurst * 2, rarity.Color)
		Effects.Confetti(revealPos + Vector3.new(0, 1, 0), profile.Confetti, { rarity.Gradient[1], rarity.Gradient[2], Color3.new(1, 1, 1) })
		if not Effects.ReduceMotion() then
			CameraDirector.Punch(profile.FovPunch)
		end
		-- The purchase broadcast's worker cheer and fireworks, held back by
		-- DeferPurchaseReactions so they do not give the rarity away early.
		if self.ReactionsDeferred then
			self.ReactionsDeferred = false
			local zones = self.View.Zones
			if zones.Workers then
				zones.Workers:React(revealPos, pet.Rarity, true)
			end
			if profile.Fireworks > 0 and zones.Spectacle then
				zones.Spectacle:Fireworks({ rarity.Gradient[1], rarity.Gradient[2], Color3.new(1, 1, 1), self.View.Theme.Neon }, profile.Fireworks)
			end
		end
		Audio.Play("Glass")
		Audio.Play("Fanfare")
		controller.Hud:Banner({ Title = pet.Name, Subtitle = "You hatched  ·  " .. rarity.Name, Rarity = pet.Rarity, Style = profile.Banner })
		local start = os.clock()
		owner.Trove:Connect(RunService.Heartbeat, function()
			local t = os.clock() - start
			local rise = math.min(t / 0.5, 1)
			petModel:PivotTo(baseCf * CFrame.new(0, -2 + ease(rise, Enum.EasingStyle.Back) * 2 + math.sin(t * 3) * 0.15, 0) * CFrame.Angles(0, t * 1.2, 0))
		end)
	end

	controller:BeginShow(seq)
	local cine = Cinematics.Begin({ Bloom = 0.5 + Rarities.Get(pet.Rarity).Rank * 0.05 })
	seq.Cine = cine
	cine:Focus(machine.DomeCenter)
	seq:Run(function(s)
		-- coins into the machine
		local console = machine.Model:FindFirstChild("Console") :: BasePart?
		local flight = controller:CoinFlight(result.Currency or "Coins", result.Price or 0, if console then console.Position + Vector3.new(0, 2, 0) else machine.DomeCenter.Position)
		self:_focusCamera(machine)
		if not s:Wait(flight) then
			return
		end
		Audio.PlayAt("Clank", machine.DomeCenter.Position)

		-- claw grabs a capsule: a ball on top of the pile, close enough to the axis
		-- that claw, cable and capsule stay inside the glass dome
		local center = machine.DomeCenter.Position
		local target = nil
		local reachable = {}
		for _, b in machine.Balls do
			local offset = b.Base.Position - center
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= CLAW_REACH then
				if offset.Y >= -2.2 then
					table.insert(reachable, b)
				end
				if not target or offset.Y > target.Base.Position.Y - center.Y then
					target = b
				end
			end
		end
		if #reachable > 0 then
			target = reachable[math.random(1, #reachable)]
		end
		local grabPos = if target then target.Base.Position else center - Vector3.new(0, 2, 0)
		-- Stand-in with the ball's own look, swapped in when the prongs close.
		local grabbed = ball(if target then target.Part.Color else machine.Capsule.Color, if target then target.Part.Size.X else 1.6, self.View.LocalFolder)
		s.Trove:Add(grabbed)
		grabbed.CFrame = CFrame.new(grabPos)
		grabbed.Transparency = 1
		local function swapIn()
			grabbed.Transparency = 0
			if target then
				target.Part.Transparency = 1
			end
		end
		if target then
			s.Trove:Add(function()
				target.Part.Transparency = 0
			end)
		end
		cine:Focus(grabbed)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.5, 0)
		a0.Parent = grabbed
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.5, 0)
		a1.Parent = grabbed
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), machine.Capsule.Color)
		trail.LightEmission = 1
		trail.Lifetime = 0.35
		trail.FaceCamera = true
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.Parent = grabbed
		local claw = machine.Claw
		local top = machine.ClawTop :: Vector3
		local travel = center.Y + CLAW_HEIGHT
		local startPos = machine.ClawPos or Vector3.new(center.X, travel, center.Z)
		local hold = Vector3.new(0, HOLD, 0)
		local above = Vector3.new(grabPos.X, travel, grabPos.Z)
		-- Releases over the chute side of the dome, still inside the glass; the
		-- capsule then drops into the cabinet (behind the chute from the camera).
		local over = Vector3.new(center.X, travel, center.Z) + frontOf(machine) * CLAW_RELEASE
		-- Poses the claw and remembers where it is, so the idle drift resumes from there.
		local function pose(position: Vector3, open: number)
			if claw and claw.Parent then
				machine.ClawPos = position
				poseClaw(claw, position, top, open)
			end
		end
		Audio.PlayAt("Servo", center)
		if claw then
			if not animate(s, 0.45, function(a)
				pose(startPos:Lerp(above, ease(a)), 0.8)
			end) then
				return
			end
			if not animate(s, timings.ClawDrop * 0.4, function(a)
				pose(above:Lerp(grabPos + hold, ease(a)), 0.8)
			end) then
				return
			end
			if not animate(s, 0.2, function(a)
				pose(grabPos + hold, 0.8 - a * (0.8 - GRIP))
			end) then
				return
			end
			swapIn()
			if not animate(s, timings.ClawDrop * 0.6, function(a)
				local p
				if a < 0.4 then
					p = (grabPos + hold):Lerp(above, ease(a / 0.4))
				else
					p = above:Lerp(over, ease((a - 0.4) / 0.6))
				end
				pose(p, GRIP)
				grabbed.CFrame = CFrame.new(p - hold)
			end) then
				return
			end
			local dropFrom = over - hold
			local dropTo = Vector3.new(over.X, center.Y - 3.4, over.Z)
			if not animate(s, 0.3, function(a)
				pose(over, GRIP + (0.9 - GRIP) * math.min(a * 3, 1))
				grabbed.CFrame = CFrame.new(dropFrom:Lerp(dropTo, a * a))
			end) then
				return
			end
		else
			swapIn()
		end

		-- marble run with follow camera
		local path = machine.Path
		if #path >= 2 then
			local lengths, total = {}, 0
			for i = 1, #path - 1 do
				lengths[i] = (path[i + 1] - path[i]).Magnitude
				total += lengths[i]
			end
			local duration = total / timings.MarbleRunSpeed
			local lastSegment = 0
			if Effects.ReduceMotion() then
				-- One calm wide shot over the hall (a cut) instead of the swinging chase camera.
				local wide = self.View:ToWorld(Factory.CapsuleHall.Camera + Vector3.new(0, 8, 0))
				CameraDirector.Snap(CFrame.lookAt(wide, self.View:ToWorld(Factory.CapsuleHall.RevealPad:Lerp(Factory.CapsuleHall.Funnel, 0.4))), 60)
			else
				local camPos = workspace.CurrentCamera.CFrame.Position
				local behind = self.View.Origin:VectorToWorldSpace(Vector3.new(0, 0, -14))
				CameraDirector.Follow(function(dt)
					local p = grabbed.Position
					local desired = p + Vector3.new(0, 7, 0) + behind
					camPos = camPos:Lerp(desired, math.min(dt * 4, 1))
					return CFrame.lookAt(camPos, p)
				end)
			end
			if claw then
				-- a beat inside the machine, then it pops out of the chute mouth
				if not s:Wait(0.25) then
					return
				end
				grabbed.CFrame = CFrame.new(path[1])
				trail:Clear()
			elseif not animate(s, 0.25, function(a)
				grabbed.CFrame = CFrame.new(grabbed.Position:Lerp(path[1], a))
			end) then
				return
			end
			Audio.PlayAt("Pop", path[1])
			if not animate(s, duration, function(a)
				local d = a * total
				local seg = 1
				while seg < #lengths and d > lengths[seg] do
					d -= lengths[seg]
					seg += 1
				end
				if seg ~= lastSegment then
					lastSegment = seg
					Audio.PlayAt("Tick", path[seg], { Volume = 2 })
				end
				-- Same average speed on every segment, but the capsule slows into each
				-- corner and picks up speed again on the straight (continuous at corners).
				local u = math.clamp(d / math.max(lengths[seg], 0.01), 0, 1)
				u += (ease(u, Enum.EasingStyle.Sine) - u) * 0.5
				local p = path[seg]:Lerp(path[seg + 1], u)
				grabbed.CFrame = CFrame.new(p) * CFrame.Angles((a * total - d + u * lengths[seg]) / 0.8, 0, 0)
			end) then
				return
			end
		else
			Audio.PlayAt("Pop", grabbed.Position)
		end
		CameraDirector.StopFollow()

		-- reveal pad: wobble then burst
		if revealShot then
			CameraDirector.GlideTo(revealShot, 0.5, Enum.EasingStyle.Quint, 55)
			if (grabbed.Position - revealPos).Magnitude > 0.5 then
				-- No run rolled it here: place it without a trail streak across the hall.
				grabbed.CFrame = CFrame.new(revealPos)
				trail:Clear()
			end
		end
		if profile.LightShow then
			table.insert(stops, Effects.LightShow(revealPos, profile.LightCount, { rarity.Gradient[1], rarity.Gradient[2] }, 14))
		end
		if profile.SkyTint then
			table.insert(stops, Effects.SkyTint(profile.SkyTint))
		end
		local baseColor = grabbed.Color
		for i = 1, profile.CapsuleWobble do
			local strength = 0.15 + i * 0.1
			if not animate(s, 0.35, function(a)
				grabbed.CFrame = CFrame.new(revealPos) * CFrame.Angles(0, 0, math.sin(a * math.pi * 4) * strength)
			end) then
				return
			end
			grabbed.Color = baseColor:Lerp(rarity.Color, i / profile.CapsuleWobble)
			if i == profile.CapsuleWobble and Rarities.AtLeast(pet.Rarity, "Epic") then
				grabbed.Material = Enum.Material.Neon
			end
			Audio.Play("Tick", { Speed = 1 + i * 0.2 })
			if not s:Wait(0.12) then
				return
			end
		end
		if profile.Shake > 0 then
			CameraDirector.Shake(profile.Shake, 0.8)
		end
		-- the two halves fly apart
		local topHalf = ball(grabbed.Color, grabbed.Size.X, self.View.LocalFolder)
		local bottomHalf = ball(grabbed.Color, grabbed.Size.X, self.View.LocalFolder)
		s.Trove:Add(topHalf)
		s.Trove:Add(bottomHalf)
		topHalf.CFrame = grabbed.CFrame
		bottomHalf.CFrame = grabbed.CFrame
		grabbed.Transparency = 1
		TweenService:Create(topHalf, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { CFrame = grabbed.CFrame + Vector3.new(0, 5, 0), Transparency = 1, Size = Vector3.one * 0.5 }):Play()
		TweenService:Create(bottomHalf, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { CFrame = grabbed.CFrame - Vector3.new(0, 1, 0), Transparency = 1, Size = Vector3.one * 0.5 }):Play()
		reveal(s)
		if not Effects.ReduceMotion() then
			local orbitStart = os.clock()
			local camFrom = workspace.CurrentCamera.CFrame.Position
			local offset = camFrom - revealPos
			local r0 = Vector3.new(offset.X, 0, offset.Z).Magnitude
			local h0 = offset.Y
			local base = math.atan2(offset.Z, offset.X)
			-- Starts exactly at the current shot and eases into the closer, lower
			-- orbit (no jump cut on the burst).
			CameraDirector.Follow(function()
				local t = os.clock() - orbitStart
				local e = TweenService:GetValue(math.min(t / 2.4, 1), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				local a = base + e * 1.2
				local radius = r0 + (r0 * 0.7 - r0) * e
				local height = h0 + (3 + t * 0.4 - h0) * e
				return CFrame.lookAt(revealPos + Vector3.new(math.cos(a) * radius, height, math.sin(a) * radius), revealPos + Vector3.new(0, 0.8 * e, 0))
			end)
		end
		s:Wait(2.4)
		CameraDirector.StopFollow()
	end, function(s)
		for _, stop in stops do
			stop()
		end
		cine:End()
		CameraDirector.StopFollow()
		if machine.Claw and machine.ClawPos then
			poseClaw(machine.Claw, machine.ClawPos, machine.ClawTop, 0.6)
		end
		controller.Hud:ReleaseCurrency(result.Currency or "Coins")
		local function finish()
			self.Opening = false
			self.OpeningId = nil
			self.ReactionsDeferred = false
			controller:EndShow(seq)
			-- Focus cannot change mid-show, so this is the machine the show ran on
			-- (nil when the player backed out during the purchase round trip).
			local focused = if self.Focused then self.Machines[self.Focused] else nil
			if focused and not s.Cancelled and not self.Destroyed and not controller:IsBusy() then
				self:_focusCamera(focused)
				self:_showPanel(focused.Capsule.Id)
			end
		end
		if not s.Cancelled and not state.Revealed then
			-- Skipped: cut to the reveal pad and show the result there (the show stays
			-- active meanwhile), then glide back to the machine.
			controller.Hud:HideSkip()
			if revealShot then
				CameraDirector.Snap(revealShot, 55)
			end
			local quick = Sequence.new("CapsuleQuick")
			reveal(quick)
			task.delay(1.6, function()
				quick.Trove:Clean()
				finish()
			end)
			return
		end
		if s.Cancelled and not state.Revealed then
			-- Died / reset mid-show: the pet is already in the inventory, so at least say what it is.
			controller.Hud:Banner({ Title = pet.Name, Subtitle = "You hatched  ·  " .. rarity.Name, Rarity = pet.Rarity, Style = profile.Banner })
		end
		finish()
	end)
end

-- ShopController asks this when the local player's own capsule purchase is
-- broadcast. While that capsule's show runs, the worker cheer and fireworks are
-- held back for the reveal instead of giving the rarity away during the coin
-- flight. Returns true when the reveal will play them.
function CapsuleHall:DeferPurchaseReactions(capsuleId: string?): boolean
	if not self.Opening or (capsuleId ~= nil and capsuleId ~= self.OpeningId) then
		return false
	end
	self.ReactionsDeferred = true
	return true
end

-- Someone else opened a capsule here: small burst at that machine.
function CapsuleHall:RemoteOpened(capsuleId: string, rarity: string)
	local machine = self.Machines[capsuleId]
	if not machine or not self.View.Near then
		return
	end
	Effects.Burst(machine.DomeCenter.Position, "Glow", 14, Rarities.Get(rarity).Color)
	for _, b in machine.Balls do
		-- A reversing tween returns to where it started: start from rest, so an
		-- overlapping bounce cannot leave the ball hovering.
		b.Part.CFrame = b.Base
		TweenService:Create(b.Part, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 1, true), { CFrame = b.Base + Vector3.new(0, 0.6, 0) }):Play()
	end
end

function CapsuleHall:Destroy()
	self.Destroyed = true
	self.Trove:Clean()
end

return CapsuleHall
