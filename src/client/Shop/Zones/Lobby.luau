-- Lobby: the daily Mystery Crate rolls in on a conveyor every 24 h (with a
-- countdown screen while you wait), and the Night Deals stand lights up in
-- neon after dark.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Definitions = Shared.Definitions
local Shop = require(Definitions.Shop)
local Rarities = require(Definitions.Rarities)
local Sequences = require(Definitions.Sequences)
local Pets = require(Definitions.Pets)
local Boosts = require(Definitions.Boosts)
local Cosmetics = require(Definitions.Cosmetics)
local Currencies = require(Definitions.Currencies)
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

local Lobby = {}
Lobby.__index = Lobby

local CRATE_SIZE = 4

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

function Lobby.new(view)
	local self = setmetatable({}, Lobby)
	self.View = view
	self.Trove = Trove.new()
	self.ActiveTrove = Trove.new()
	self.Trove:Add(self.ActiveTrove, "Clean")
	self.Belt = view:Find("Lobby/CrateBelt") :: BasePart?
	self.Hatch = view:Find("Lobby/CrateHatch") :: BasePart?
	self.Pad = view:Find("Lobby/CratePad") :: BasePart?
	self.Screen = view:Find("Lobby/CrateScreen") :: BasePart?
	self.NightSign = view:Find("Lobby/NightStand/NightSign") :: BasePart?
	self.Crate = nil :: Model?
	self.State = "None"
	self.Item = Shop.Get(Shop.DailyCrate.Id)
	self.Trove:Connect(view.Controller.ClientData.Changed, function()
		if self.Focused and self.State ~= "Opening" then
			self:_showPanel()
		end
	end)
	return self
end

function Lobby:_available(): boolean
	local data = self.View.Controller.ClientData:Get()
	if not data or not self.Item then
		return false
	end
	local state = Shop.GetState(self.Item :: any, data, workspace:GetServerTimeNow())
	return state == "Available"
end

function Lobby:_buildCrate(): Model
	local model = Instance.new("Model")
	model.Name = "MysteryCrate"
	local theme = self.View.Theme
	local wood = if theme.Id == "Brass" then Color3.fromRGB(140, 96, 56) else Color3.fromRGB(40, 44, 60)
	local band = if theme.Id == "Brass" then theme.Trim else theme.Neon
	local function add(props): BasePart
		local p = Builder.Part(props)
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = model
		return p
	end
	local body = add({ Name = "Body", Size = Vector3.new(CRATE_SIZE, CRATE_SIZE * 0.8, CRATE_SIZE), Color = wood, Material = if theme.Id == "Brass" then Enum.Material.WoodPlanks else Enum.Material.Metal })
	model.PrimaryPart = body
	add({ Name = "Lid", Size = Vector3.new(CRATE_SIZE + 0.2, CRATE_SIZE * 0.22, CRATE_SIZE + 0.2), CFrame = CFrame.new(0, CRATE_SIZE * 0.51, 0), Color = wood:Lerp(Color3.new(0, 0, 0), 0.15), Material = body.Material })
	for _, y in { -0.3, 0.25 } do
		add({ Name = "Band", Size = Vector3.new(CRATE_SIZE + 0.15, 0.25, CRATE_SIZE + 0.15), CFrame = CFrame.new(0, y * CRATE_SIZE, 0), Color = band, Material = Enum.Material.Neon })
	end
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		local gui = UI.new("SurfaceGui", { Face = face, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 30, LightInfluence = 0, Brightness = 2, Parent = body })
		UI.Label({ Text = "?", Size = UDim2.fromScale(1, 1), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = Theme.Fonts.Title, TextColor3 = Theme.Colors.Gold, TextStrokeTransparency = 0.4, Parent = gui })
	end
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			p:SetAttribute("Home", body.CFrame:ToObjectSpace(p.CFrame))
		end
	end
	model.Parent = self.View.LocalFolder
	return model
end

function Lobby:_placeCrate(cf: CFrame)
	local crate = self.Crate
	if not crate then
		return
	end
	local body = crate.PrimaryPart :: BasePart
	local parts, frames = {}, {}
	for _, p in crate:GetChildren() do
		if p:IsA("BasePart") then
			table.insert(parts, p)
			table.insert(frames, if p == body then cf else cf * (p:GetAttribute("Home") :: CFrame))
		end
	end
	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

function Lobby:_padCFrame(): CFrame
	local pad = self.Pad :: BasePart
	return CFrame.new(pad.Position + Vector3.new(0, pad.Size.Y / 2 + CRATE_SIZE * 0.4, 0)) * self.View.Origin.Rotation
end

-- The conveyor brings a fresh crate out of the hatch.
function Lobby:_deliver(instant: boolean)
	if not self.Pad or not self.Belt or self.State ~= "None" then
		return
	end
	self.Crate = self:_buildCrate()
	self.ActiveTrove:Add(self.Crate)
	if instant then
		self.State = "Waiting"
		self:_placeCrate(self:_padCFrame())
		return
	end
	self.State = "Delivering"
	local hatch = self.Hatch
	local start = self.Belt:GetAttribute("BeltStart") :: Vector3
	local finish = self:_padCFrame()
	local from = CFrame.new(start + Vector3.new(0, CRATE_SIZE * 0.4, 0)) * self.View.Origin.Rotation
	if hatch then
		hatch.LocalTransparencyModifier = 1
		Audio.PlayAt("Clank", hatch.Position)
	end
	task.spawn(function()
		local t0 = os.clock()
		local duration = 4.5
		while os.clock() - t0 < duration do
			if not self.Crate then
				return
			end
			local a = (os.clock() - t0) / duration
			local p = from.Position:Lerp(finish.Position, a)
			self:_placeCrate(CFrame.new(p) * finish.Rotation * CFrame.Angles(0, 0, math.sin(a * 30) * 0.02))
			RunService.Heartbeat:Wait()
		end
		if not self.Crate then
			return
		end
		if hatch then
			hatch.LocalTransparencyModifier = 0
		end
		self:_placeCrate(finish)
		Effects.Burst(finish.Position, "Glow", 16, Theme.Colors.Gold)
		Audio.PlayAt("Pop", finish.Position)
		self.State = "Waiting"
	end)
end

function Lobby:_updateScreen()
	local screen = self.Screen
	if not screen then
		return
	end
	local gui = screen:FindFirstChild("CrateScreenGui") :: SurfaceGui?
	if not gui then
		local created = UI.new("SurfaceGui", {
			Name = "CrateScreenGui",
			Face = Enum.NormalId[screen:GetAttribute("Face") or "Right"] or Enum.NormalId.Right,
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = 30,
			LightInfluence = 0,
			Brightness = 2,
			Parent = screen,
		})
		local panel = UI.new("Frame", { Name = "Panel", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 10, 16), Parent = created }, { UI.Corner(UDim.new(0, 12)), UI.Stroke(Theme.Colors.Gold, 0.3, 3) })
		UI.Label({ Name = "Title", Text = "📦 MYSTERY CRATE", Position = UDim2.fromScale(0.05, 0.06), Size = UDim2.fromScale(0.9, 0.24), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = Theme.Fonts.Title, TextColor3 = Theme.Colors.Gold, Parent = panel })
		UI.Label({ Name = "Main", Text = "", Position = UDim2.fromScale(0.05, 0.34), Size = UDim2.fromScale(0.9, 0.36), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = Theme.Fonts.Numbers, Parent = panel })
		local track = UI.new("Frame", { Name = "Track", Position = UDim2.fromScale(0.08, 0.8), Size = UDim2.fromScale(0.84, 0.08), BackgroundColor3 = Color3.fromRGB(40, 46, 66), Parent = panel }, { UI.Corner(UDim.new(1, 0)) })
		UI.new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Colors.Gold, Parent = track }, { UI.Corner(UDim.new(1, 0)) })
		self.ActiveTrove:Add(created)
		gui = created
	end
	local panel = (gui :: SurfaceGui):FindFirstChild("Panel") :: Frame
	local main = panel:FindFirstChild("Main") :: TextLabel
	local fill = (panel:FindFirstChild("Track") :: Frame):FindFirstChild("Fill") :: Frame
	local now = workspace:GetServerTimeNow()
	if self:_available() then
		local data = self.View.Controller.ClientData:Get()
		main.Text = "OPEN NOW · 🪙 " .. Format.Abbreviate(Shop.GetPrice(self.Item :: any, data))
		main.TextColor3 = Theme.Colors.Success
		fill.Size = UDim2.fromScale(1, 1)
	else
		local remaining = DayNight.SecondsUntilNextDay(now)
		main.Text = "NEXT IN " .. Format.Clock(remaining)
		main.TextColor3 = Theme.Colors.Text
		fill.Size = UDim2.fromScale(1 - remaining / 86400, 1)
	end
end

function Lobby:_updateNightSign()
	local sign = self.NightSign
	if not sign then
		return
	end
	local label = sign:FindFirstChild("Sign")
	local text = label and label:FindFirstChild("Text") :: TextLabel?
	local night = DayNight.IsNight()
	if text then
		text.Text = if night then "🌙 NIGHT DEALS" else "NIGHT DEALS · AFTER DARK"
		text.TextColor3 = if night then self.View.Theme.NightNeon else Theme.Colors.Muted
		text.TextTransparency = if night then 0 else 0.4
	end
	local gui = label :: SurfaceGui?
	if gui and gui:IsA("SurfaceGui") then
		gui.Brightness = if night then 3 else 0.6
	end
end

function Lobby:SetActive(active: boolean)
	self.ActiveTrove:Clean()
	self.Crate = nil
	self.State = "None"
	if self.Hatch then
		self.Hatch.LocalTransparencyModifier = 0
	end
	if not active then
		return
	end
	if self:_available() then
		self:_deliver(not self.View.Inside)
	end
	self.ActiveTrove:Add(task.spawn(function()
		while true do
			if self.State == "None" and self:_available() then
				self:_deliver(false)
			end
			self:_updateScreen()
			self:_updateNightSign()
			task.wait(0.5)
		end
	end))
	local t0 = os.clock()
	self.ActiveTrove:Connect(RunService.Heartbeat, function()
		if self.State == "Waiting" and self.Crate then
			local t = os.clock() - t0
			self:_placeCrate(self:_padCFrame() * CFrame.new(0, 0.15 + math.sin(t * 2) * 0.12, 0) * CFrame.Angles(0, t * 0.5, 0))
		end
	end)
end

-- Focus + opening --------------------------------------------------------------------------

function Lobby:_showPanel()
	local controller = self.View.Controller
	local data = controller.ClientData:Get()
	local item = self.Item
	if not data or not item then
		return
	end
	local available = self:_available()
	local remaining = DayNight.SecondsUntilNextDay(workspace:GetServerTimeNow())
	controller.FactoryHud:ShowPanel({
		Title = "Mystery Crate",
		Rarity = item.Rarity,
		Lines = {
			Shop.DailyCrate.Description,
			"🪙 2-6x price  ·  ⚡ boosts  ·  🐾 pets  ·  🎨 cosmetics  ·  👑 boss cores",
		},
		Price = if available then { Amount = Shop.GetPrice(item, data), Currency = item.Currency, Affordable = Shop.CanAfford(item, data) } else nil,
		Status = if available then nil else "Next crate in " .. Format.Clock(remaining),
		Buttons = {
			{
				Id = "Open",
				Text = if available then "Open Crate" else "Come back later",
				Glyph = "📦",
				Style = "Gold",
				Enabled = available and Shop.CanAfford(item, data) and self.State == "Waiting",
				OnClick = function()
					self:_open()
				end,
			},
			{
				Text = "Night Deals",
				Glyph = "🌙",
				Style = "Ghost",
				OnClick = function()
					controller:ExitMode("Lobby")
					controller.Classic:Open("Deals")
				end,
			},
		},
	})
end

function Lobby:Focus()
	local controller = self.View.Controller
	if not self.Pad then
		return
	end
	if not controller:EnterMode("Lobby", function()
		self.Focused = false
		controller.FactoryHud:HidePanel()
		controller.FactoryHud:SetHint(nil)
	end) then
		return
	end
	self.Focused = true
	local pad = (self.Pad :: BasePart).Position
	local camPos = pad + self.View.Origin:VectorToWorldSpace(Vector3.new(12, 7, 10))
	CameraDirector.GlideTo(CFrame.lookAt(camPos, pad + Vector3.new(0, 2, 0)), 0.7, Enum.EasingStyle.Quint, 60)
	controller.FactoryHud:SetHint("[Back] Back")
	self:_showPanel()
end

local function rewardText(reward: { [string]: any }): (string, string)
	local kind = reward.Kind
	if kind == "Coins" then
		return "🪙", "+" .. Format.Commas(reward.Amount or 0) .. " Coins"
	elseif kind == "Boost" then
		local boost = Boosts.Get(reward.BoostId)
		return if boost then boost.Glyph else "⚡", (if boost then boost.Name else "Boost") .. " activated"
	elseif kind == "Pet" then
		local pet = Pets.Get(reward.PetId)
		return "🐾", if pet then pet.Name else "Pet"
	elseif kind == "Cosmetic" then
		local cosmetic = Cosmetics.Get(reward.CosmeticId)
		return "🎨", if cosmetic then cosmetic.Name else "Cosmetic"
	elseif kind == "BossCore" then
		local currency = Currencies.Get(reward.Currency)
		return if currency then currency.Glyph else "👑", "+" .. tostring(reward.Amount or 1) .. " " .. (if currency then currency.Name else "Boss Core")
	end
	return "🎁", "Reward"
end

function Lobby:_open()
	local controller = self.View.Controller
	local item = self.Item
	if not item or self.State ~= "Waiting" or controller:IsBusy() then
		return
	end
	self.State = "Opening"
	local button = controller.FactoryHud:GetButton("Open")
	if button then
		button:SetLoading(true)
	end
	local result = controller:RequestPurchase(item)
	if button then
		button:SetLoading(false)
	end
	if not result.Ok or not result.Reward then
		self.State = "Waiting"
		controller.Hud:Toast(result.Error or "Could not open the crate.", "Error")
		return
	end
	local reward = result.Reward
	local rarity = Rarities.Get(reward.Rarity)
	local profile = Sequences.Get(reward.Rarity)
	local glyph, text = rewardText(reward)
	local seq = Sequence.new("Crate")
	local shown = false
	local padCf = self:_padCFrame()

	local function show()
		if shown then
			return
		end
		shown = true
		controller.Hud:Banner({ Title = text, Subtitle = "Mystery Crate  ·  " .. rarity.Name, Rarity = reward.Rarity, Style = profile.Banner })
		Effects.Confetti(padCf.Position + Vector3.new(0, 3, 0), profile.Confetti, { rarity.Gradient[1], rarity.Gradient[2], Theme.Colors.Gold })
		if reward.Kind == "Coins" or reward.Kind == "BossCore" then
			local from = Effects.ToScreen(padCf.Position + Vector3.new(0, 3, 0))
			local anchor = controller.Hud:GetCurrencyAnchor(reward.Currency or "Coins")
			if anchor then
				controller.Hud:HoldCurrency(reward.Currency or "Coins", controller.Hud:ShownCurrency(reward.Currency or "Coins"))
				local duration = Effects.CoinFlight(from, Effects.GuiCenter(anchor), 14, glyph)
				task.delay(duration, function()
					controller.Hud:ReleaseCurrency(reward.Currency or "Coins", 0.8)
				end)
			end
		end
	end

	controller:BeginShow(seq)
	seq:Run(function(s)
		controller:CoinFlight(result.Currency or "Coins", result.Price or 0, padCf.Position + Vector3.new(0, 2, 0))
		if not s:Wait(0.8) then
			return
		end
		-- wobble
		for i = 1, profile.CapsuleWobble do
			if not animate(s, 0.3, function(a)
				self:_placeCrate(padCf * CFrame.Angles(0, 0, math.sin(a * math.pi * 4) * (0.06 + i * 0.03)))
			end) then
				return
			end
			Audio.Play("Tick", { Speed = 1 + i * 0.25 })
		end
		-- lid flies open + light beam
		local crate = self.Crate
		local lid = crate and crate:FindFirstChild("Lid") :: BasePart?
		if lid then
			local hinge = padCf * CFrame.new(0, CRATE_SIZE * 0.5, CRATE_SIZE / 2)
			local rel = hinge:ToObjectSpace(lid.CFrame)
			if not animate(s, 0.35, function(a)
				lid.CFrame = hinge * CFrame.Angles(-a * 2.2, 0, 0) * rel
			end) then
				return
			end
		end
		local beam = Builder.Part({
			Name = "Beam",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 3, 3),
			CFrame = CFrame.new(padCf.Position + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Material = Enum.Material.Neon,
			Color = rarity.Color,
			Transparency = 0.3,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Parent = self.View.LocalFolder,
		})
		s.Trove:Add(beam)
		TweenService:Create(beam, TweenInfo.new(0.6, Enum.EasingStyle.Quint), { Size = Vector3.new(30, 3, 3), CFrame = beam.CFrame + Vector3.new(0, 15, 0), Transparency = 0.6 }):Play()
		Effects.GlowBall(padCf.Position + Vector3.new(0, 3, 0), rarity.Color, 10, 0.6)
		Effects.Burst(padCf.Position + Vector3.new(0, 3, 0), "Sparks", profile.SparkBurst * 2, rarity.Color)
		CameraDirector.Punch(profile.FovPunch)
		Audio.Play("Fanfare")
		if reward.Kind == "Pet" and reward.PetId then
			local petModel = PetModel.Build(reward.PetId)
			petModel.Parent = self.View.LocalFolder
			s.Trove:Add(petModel)
			local start = os.clock()
			s.Trove:Connect(RunService.Heartbeat, function()
				local t = os.clock() - start
				petModel:PivotTo(padCf * CFrame.new(0, 1 + math.min(t, 0.6) * 4, 0) * CFrame.Angles(0, t * 1.4, 0))
			end)
		else
			local tag = UI.new("BillboardGui", { Size = UDim2.fromOffset(260, 70), StudsOffset = Vector3.new(0, 6, 0), AlwaysOnTop = true, Adornee = self.Pad, Parent = self.View.LocalFolder })
			s.Trove:Add(tag)
			UI.Label({ Text = glyph .. "  " .. text, Size = UDim2.fromScale(1, 1), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = Theme.Fonts.Title, TextColor3 = rarity.Color, TextStrokeTransparency = 0.3, Parent = tag })
		end
		show()
		s:Wait(2.4)
		-- crate sinks into the pad
		animate(s, 0.6, function(a)
			self:_placeCrate(padCf * CFrame.new(0, -a * CRATE_SIZE, 0))
		end)
	end, function(s)
		if not s.Cancelled then
			show()
		end
		controller.Hud:ReleaseCurrency(result.Currency or "Coins")
		if self.Crate then
			self.Crate:Destroy()
			self.Crate = nil
		end
		self.State = "None"
		controller:EndShow(seq)
		if self.Focused then
			self:_showPanel()
		end
	end)
end

function Lobby:Destroy()
	self.Trove:Clean()
end

return Lobby
