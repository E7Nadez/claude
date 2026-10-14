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

local CapsuleHall = {}
CapsuleHall.__index = CapsuleHall

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
			local offset = Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(-3.2, -1.2), rng:NextNumber(-3, 3))
			b.CFrame = CFrame.new(center + offset) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
			table.insert(machine.Balls, { Part = b, Base = b.CFrame, Phase = i })
			self.ActiveTrove:Add(b)
		end
		local claw = buildClaw(self.View.LocalFolder, color)
		self.ActiveTrove:Add(claw)
		machine.Claw = claw
		machine.ClawTop = center + Vector3.new(0, 4.4, 0)
		machine.ClawPos = center + Vector3.new(0, 2.6, 0)
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
				local drift = Vector3.new(math.sin(t * 0.6 + #id) * 2.2, 2.6, math.cos(t * 0.45 + #id) * 2.2)
				machine.ClawPos = center + drift
				poseClaw(machine.Claw, machine.ClawPos, machine.ClawTop, 0.6 + math.sin(t) * 0.1)
			end
			if machine.Capsule.NightOnly and machine.Panel then
				machine.Panel.Transparency = if night then 0.3 else 0.85
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
	local luck = Boosts.ActiveMultiplier(data.Boosts, "Luck", workspace:GetServerTimeNow()) * (if data.Gamepasses.gp_lucky then 1.5 else 1)
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
					controller.Modal:Show(item, { Source = "Classic" })
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
	CameraDirector.GlideTo(CFrame.lookAt(camPos, center - Vector3.new(0, 1.5, 0)), 0.7, Enum.EasingStyle.Quint, 60)
end

function CapsuleHall:Focus(capsuleId: string)
	local machine = self.Machines[capsuleId]
	local controller = self.View.Controller
	if not machine then
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
	local chance = 0
	for _, entry in Capsules.EffectiveDrops(machine.Capsule.Id, 1) do
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
		owner.Trove:Add(petModel)
		local camera = workspace.CurrentCamera
		local faceTo = Vector3.new(camera.CFrame.Position.X, revealPos.Y, camera.CFrame.Position.Z)
		local baseCf = CFrame.lookAt(revealPos - Vector3.new(0, 1.2, 0), faceTo)
		petModel:PivotTo(baseCf * CFrame.new(0, -2, 0))
		local tag = UI.new("BillboardGui", { Size = UDim2.fromOffset(240, 90), StudsOffset = Vector3.new(0, 4.5, 0), AlwaysOnTop = true, Adornee = petModel.PrimaryPart, Parent = petModel })
		UI.Label({ Text = pet.Name, Size = UDim2.new(1, 0, 0.42, 0), TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = Theme.Fonts.Title, TextStrokeTransparency = 0.3, Parent = tag })
		UI.Label({ Text = string.upper(rarity.Name) .. "  ·  x" .. Format.Stat(pet.Multiplier), Position = UDim2.fromScale(0, 0.44), Size = UDim2.new(1, 0, 0.28, 0), TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, TextColor3 = rarity.Color, FontFace = Theme.Fonts.Title, TextStrokeTransparency = 0.3, Parent = tag })
		UI.Label({ Text = Format.Chance(chance), Position = UDim2.fromScale(0, 0.74), Size = UDim2.new(1, 0, 0.24, 0), TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, TextColor3 = Theme.Colors.SubText, TextStrokeTransparency = 0.3, Parent = tag })
		Effects.GlowBall(revealPos, rarity.Color, 12, 0.6)
		Effects.Shockwave(revealPos - Vector3.new(0, 1.4, 0), rarity.Color, 14)
		Effects.Burst(revealPos, "Sparks", profile.SparkBurst * 2, rarity.Color)
		Effects.Confetti(revealPos + Vector3.new(0, 1, 0), profile.Confetti, { rarity.Gradient[1], rarity.Gradient[2], Color3.new(1, 1, 1) })
		CameraDirector.Punch(profile.FovPunch)
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
	seq:Run(function(s)
		-- coins into the machine
		local console = machine.Model:FindFirstChild("Console") :: BasePart?
		local flight = controller:CoinFlight(result.Currency or "Coins", result.Price or 0, if console then console.Position + Vector3.new(0, 2, 0) else machine.DomeCenter.Position)
		self:_focusCamera(machine)
		if not s:Wait(flight) then
			return
		end
		Audio.PlayAt("Clank", machine.DomeCenter.Position)

		-- claw grabs a capsule
		local target = machine.Balls[math.random(1, math.max(#machine.Balls, 1))]
		local grabbed = ball(machine.Capsule.Color, 1.6, self.View.LocalFolder)
		s.Trove:Add(grabbed)
		local grabPos = if target then target.Part.Position else machine.DomeCenter.Position - Vector3.new(0, 2, 0)
		if target then
			target.Part.Transparency = 1
			s.Trove:Add(function()
				target.Part.Transparency = 0
			end)
		end
		grabbed.CFrame = CFrame.new(grabPos)
		local claw = machine.Claw
		local top = machine.ClawTop :: Vector3
		local startPos = machine.ClawPos :: Vector3
		local above = Vector3.new(grabPos.X, startPos.Y, grabPos.Z)
		Audio.PlayAt("Servo", machine.DomeCenter.Position)
		if claw then
			if not animate(s, 0.45, function(a)
				poseClaw(claw, startPos:Lerp(above, ease(a)), top, 0.8)
			end) then
				return
			end
			if not animate(s, timings.ClawDrop * 0.4, function(a)
				poseClaw(claw, above:Lerp(grabPos + Vector3.new(0, 1.1, 0), ease(a)), top, 0.8)
			end) then
				return
			end
			if not animate(s, 0.2, function(a)
				poseClaw(claw, grabPos + Vector3.new(0, 1.1, 0), top, 0.8 - a * 0.8)
			end) then
				return
			end
			local chuteTop = machine.Chute.Position + Vector3.new(0, 1.6, 0)
			local over = Vector3.new(chuteTop.X, startPos.Y, chuteTop.Z)
			if not animate(s, timings.ClawDrop * 0.6, function(a)
				local p
				if a < 0.4 then
					p = (grabPos + Vector3.new(0, 1.1, 0)):Lerp(Vector3.new(grabPos.X, startPos.Y, grabPos.Z), ease(a / 0.4))
				else
					p = Vector3.new(grabPos.X, startPos.Y, grabPos.Z):Lerp(over, ease((a - 0.4) / 0.6))
				end
				poseClaw(claw, p, top, 0)
				grabbed.CFrame = CFrame.new(p - Vector3.new(0, 1.1, 0))
			end) then
				return
			end
			poseClaw(claw, over, top, 0.9)
		end
		Audio.PlayAt("Pop", grabbed.Position)

		-- marble run with follow camera
		local path = machine.Path
		if #path >= 2 then
			local lengths, total = {}, 0
			for i = 1, #path - 1 do
				lengths[i] = (path[i + 1] - path[i]).Magnitude
				total += lengths[i]
			end
			local duration = total / timings.MarbleRunSpeed
			local camPos = workspace.CurrentCamera.CFrame.Position
			local lastSegment = 0
			local behind = self.View.Origin:VectorToWorldSpace(Vector3.new(0, 0, -14))
			CameraDirector.Follow(function(dt)
				local p = grabbed.Position
				local desired = p + Vector3.new(0, 7, 0) + behind
				camPos = camPos:Lerp(desired, math.min(dt * 4, 1))
				return CFrame.lookAt(camPos, p)
			end)
			if not animate(s, 0.25, function(a)
				grabbed.CFrame = CFrame.new(grabbed.Position:Lerp(path[1], a))
			end) then
				return
			end
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
				local p = path[seg]:Lerp(path[seg + 1], math.clamp(d / math.max(lengths[seg], 0.01), 0, 1))
				grabbed.CFrame = CFrame.new(p) * CFrame.Angles(a * total / 0.8, 0, 0)
			end) then
				return
			end
		end
		CameraDirector.StopFollow()

		-- reveal pad: wobble then burst
		if pad then
			local camPos = self.View:ToWorld(Factory.CapsuleHall.Camera)
			CameraDirector.GlideTo(CFrame.lookAt(camPos, revealPos), 0.5, Enum.EasingStyle.Quint, 55)
			grabbed.CFrame = CFrame.new(revealPos)
		end
		if profile.LightShow then
			table.insert(stops, Effects.LightShow(revealPos, profile.LightCount, { rarity.Gradient[1], rarity.Gradient[2] }, 14))
		end
		if profile.SkyTint then
			table.insert(stops, Effects.SkyTint(profile.SkyTint))
		end
		for i = 1, profile.CapsuleWobble do
			local strength = 0.15 + i * 0.1
			if not animate(s, 0.35, function(a)
				grabbed.CFrame = CFrame.new(revealPos) * CFrame.Angles(0, 0, math.sin(a * math.pi * 4) * strength)
			end) then
				return
			end
			grabbed.Color = machine.Capsule.Color:Lerp(rarity.Color, i / profile.CapsuleWobble)
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
		local topHalf = ball(grabbed.Color, 1.6, self.View.LocalFolder)
		local bottomHalf = ball(grabbed.Color, 1.6, self.View.LocalFolder)
		s.Trove:Add(topHalf)
		s.Trove:Add(bottomHalf)
		topHalf.CFrame = grabbed.CFrame
		bottomHalf.CFrame = grabbed.CFrame
		grabbed.Transparency = 1
		TweenService:Create(topHalf, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { CFrame = grabbed.CFrame + Vector3.new(0, 5, 0), Transparency = 1, Size = Vector3.one * 0.5 }):Play()
		TweenService:Create(bottomHalf, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { CFrame = grabbed.CFrame - Vector3.new(0, 1, 0), Transparency = 1, Size = Vector3.one * 0.5 }):Play()
		reveal(s)
		s:Wait(2.2)
	end, function(s)
		for _, stop in stops do
			stop()
		end
		CameraDirector.StopFollow()
		if not s.Cancelled and not state.Revealed then
			-- Skipped: show the result immediately.
			local quick = Sequence.new("CapsuleQuick")
			reveal(quick)
			task.delay(1.4, function()
				quick.Trove:Clean()
			end)
		end
		if machine.Claw and machine.ClawPos then
			poseClaw(machine.Claw, machine.ClawPos, machine.ClawTop, 0.6)
		end
		self.Opening = false
		self.OpeningId = nil
		controller.Hud:ReleaseCurrency(result.Currency or "Coins")
		controller:EndShow(seq)
		if self.Focused == machine.Capsule.Id and not s.Cancelled then
			self:_focusCamera(machine)
			self:_showPanel(machine.Capsule.Id)
		end
	end)
end

-- Someone else opened a capsule here: small burst at that machine.
function CapsuleHall:RemoteOpened(capsuleId: string, rarity: string)
	local machine = self.Machines[capsuleId]
	if not machine or not self.View.Near then
		return
	end
	Effects.Burst(machine.DomeCenter.Position, "Glow", 14, Rarities.Get(rarity).Color)
	for _, b in machine.Balls do
		TweenService:Create(b.Part, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 1, true), { CFrame = b.Base + Vector3.new(0, 0.6, 0) }):Play()
	end
end

function CapsuleHall:Destroy()
	self.Trove:Clean()
end

return CapsuleHall
