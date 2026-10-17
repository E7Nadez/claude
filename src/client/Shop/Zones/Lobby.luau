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
local Cinematics = require(ShopFolder.Cinematics)

local Lobby = {}
Lobby.__index = Lobby

local CRATE_SIZE = 4
local QUARTER = math.pi / 2 -- the square crate looks the same after a quarter turn
local WAIT_GLYPH = "⏳"

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
	self.BobStart = os.clock()
	self.NightOn = nil :: boolean?
	self.FlickerUntil = 0
	self.PanelKey = nil :: string?
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

function Lobby:_placeCrate(cf: CFrame, target: Model?)
	local crate = target or self.Crate
	if not crate or not crate.Parent then
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

-- Sinks the crate into the pad. Every part moves down by the same offset, so an
-- opened lid stays open instead of snapping shut; an open lid overhangs the
-- pad, so it fades out on the way down. Returns false if interrupted.
function Lobby:_sinkCrate(crate: Model, seq, fadeLid: boolean): boolean
	local parts, starts = {}, {}
	for _, p in crate:GetChildren() do
		if p:IsA("BasePart") then
			table.insert(parts, p)
			table.insert(starts, p.CFrame)
		end
	end
	local lid = if fadeLid then crate:FindFirstChild("Lid") :: BasePart? else nil
	local frames = {}
	return animate(seq, 0.6, function(a)
		if not crate.Parent then
			return
		end
		-- deep enough that the bobbing lid's top ends below the pad surface
		local offset = Vector3.new(0, -CRATE_SIZE * 1.25 * a * a, 0)
		for i, cf in starts do
			frames[i] = cf + offset
		end
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		if lid then
			lid.LocalTransparencyModifier = math.min(a / 0.7, 1)
		end
	end)
end

function Lobby:_padCFrame(): CFrame
	local pad = self.Pad :: BasePart
	return CFrame.new(pad.Position + Vector3.new(0, pad.Size.Y / 2 + CRATE_SIZE * 0.4, 0)) * self.View.Origin.Rotation
end

-- The conveyor brings a fresh crate out of the hatch: it rides the belt at the
-- slats' speed, glides off the end onto the pad and rocks to a stop.
function Lobby:_deliver(instant: boolean)
	if not self.Pad or not self.Belt or self.State ~= "None" then
		return
	end
	local crate = self:_buildCrate()
	self.Crate = crate
	self.ActiveTrove:Add(crate)
	local belt = self.Belt :: BasePart
	local finish = self:_padCFrame()
	local beltStart = belt:GetAttribute("BeltStart")
	if instant or typeof(beltStart) ~= "Vector3" then
		self.State = "Waiting"
		self.BobStart = os.clock()
		self:_placeCrate(finish, crate)
		return
	end
	self.State = "Delivering"
	local hatch = self.Hatch
	local start = beltStart + Vector3.new(0, CRATE_SIZE * 0.4, 0)
	local path = finish.Position - start
	local length = path.Magnitude
	local dir = path.Unit
	local speed = math.max(belt:GetAttribute("BeltSpeed") or 5, 0.5)
	local beltLength = math.clamp(belt:GetAttribute("BeltLength") or (length - 3), 0, length)
	-- Starts behind the dark recess in the wall, so it comes out of the opening.
	local back = CRATE_SIZE / 2 + 1.25
	local ride = back + beltLength -- carried by the slats
	local glide = length - beltLength -- off the belt end onto the pad
	local rideTime = ride / speed
	local glideTime = math.max(2 * glide / speed, 0.01) -- Quad Out, starting at belt speed
	local opening = if hatch then 0.3 else 0
	-- Path distance of the crate centre once its back has cleared the hatch.
	local clear = if hatch then (hatch.Position - start):Dot(dir) + hatch.Size.X / 2 + CRATE_SIZE / 2 + 0.3 else 0
	-- The stop: tips forward onto its front bottom edge and drops back.
	local localDir = finish:VectorToObjectSpace(dir)
	local edge = CFrame.new(localDir * (CRATE_SIZE / 2) - Vector3.new(0, CRATE_SIZE * 0.4, 0))
	local tiltAxis = Vector3.yAxis:Cross(localDir).Unit
	self:_placeCrate(CFrame.new(start - dir * back) * finish.Rotation, crate)
	if hatch then
		Audio.PlayAt("Clank", hatch.Position)
	end
	self.ActiveTrove:Add(task.spawn(function()
		local t0 = os.clock()
		local clearedAt: number? = nil
		while true do
			if self.Crate ~= crate then
				return
			end
			local elapsed = os.clock() - t0
			local t = elapsed - opening
			local d = 0
			if t >= rideTime then
				local g = math.min((t - rideTime) / glideTime, 1)
				d = ride + glide * (1 - (1 - g) * (1 - g))
			elseif t > 0 then
				d = t * speed
			end
			if hatch then
				-- fades open before the crate moves, closes again once it is through
				if not clearedAt and d - back >= clear then
					clearedAt = elapsed
					Audio.PlayAt("Clank", hatch.Position, { Volume = 0.5 })
				end
				hatch.LocalTransparencyModifier = if clearedAt then 1 - math.min((elapsed - clearedAt) / 0.3, 1) else math.min(elapsed / opening, 1)
			end
			local rattle = if t > 0 and t < rideTime then math.sin(t * 6.5) * 0.02 else 0
			self:_placeCrate(CFrame.new(start + dir * (d - back)) * finish.Rotation * CFrame.Angles(0, 0, rattle), crate)
			if t >= rideTime + glideTime then
				break
			end
			RunService.Heartbeat:Wait()
		end
		if hatch then
			hatch.LocalTransparencyModifier = 0
		end
		Effects.Burst(finish:PointToWorldSpace(Vector3.new(0, CRATE_SIZE * 0.65, 0)), "Glow", 16, Theme.Colors.Gold)
		Audio.PlayAt("Pop", finish.Position)
		local s0 = os.clock()
		while true do
			if self.Crate ~= crate then
				return
			end
			local a = math.min((os.clock() - s0) / 0.35, 1)
			self:_placeCrate(finish * edge * CFrame.fromAxisAngle(tiltAxis, math.sin(a * math.pi) * 0.05) * edge:Inverse(), crate)
			if a >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
		self.State = "Waiting"
		self.BobStart = os.clock()
		self:_refreshPanel()
	end))
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
	local switchedOn = night and self.NightOn == false
	self.NightOn = night
	if text then
		text.Text = if night then "🌙 NIGHT DEALS" else "NIGHT DEALS · AFTER DARK"
		-- By day an unlit but readable tube.
		text.TextColor3 = if night then self.View.Theme.NightNeon else Theme.Colors.SubText
		text.TextTransparency = if night then 0 else 0.15
	end
	local gui = label :: SurfaceGui?
	if gui and gui:IsA("SurfaceGui") then
		if switchedOn and not Effects.ReduceMotion() then
			-- the neon flickers on at dusk
			self.FlickerUntil = os.clock() + 0.6
			self.ActiveTrove:Add(task.spawn(function()
				for _, brightness in { 0.4, 2.6, 0.7, 3, 1.4, 3 } do
					gui.Brightness = brightness
					task.wait(0.06 + math.random() * 0.04)
				end
			end))
		elseif os.clock() >= self.FlickerUntil then
			gui.Brightness = if night then 3 else 1.2
		end
	end
end

-- Today's crate was opened elsewhere (the classic Deals tab): it sinks into
-- the pad instead of waiting there until tomorrow.
function Lobby:_retire()
	local crate = self.Crate
	if not crate then
		self.State = "None"
		return
	end
	self.State = "Leaving"
	self:_sinkCrate(crate, { Stopped = false }, false)
	if self.Crate == crate then
		crate:Destroy()
		self.Crate = nil
		self.State = "None"
	end
end

function Lobby:SetActive(active: boolean)
	self.ActiveTrove:Clean()
	self.Crate = nil
	self.State = "None"
	self.NightOn = nil
	self.FlickerUntil = 0
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
			local available = self:_available()
			if self.State == "None" and available then
				-- (only animated where it can be seen: the crate starts inside the wall)
				self:_deliver(not self.View.Inside)
			elseif self.State == "Waiting" and not available then
				self:_retire()
			end
			self:_updateScreen()
			self:_updateNightSign()
			self:_refreshPanel()
			task.wait(0.5)
		end
	end))
	self.ActiveTrove:Connect(RunService.Heartbeat, function()
		if self.State == "Waiting" and self.Crate then
			-- Eases into the bob from the resting pose (no height / yaw jump).
			local t = os.clock() - self.BobStart
			local k = math.min(t / 0.8, 1)
			k = k * k * (3 - 2 * k)
			self:_placeCrate(self:_padCFrame() * CFrame.new(0, k * (0.15 + math.sin(t * 2) * 0.12), 0) * CFrame.Angles(0, t * 0.5 * k, 0))
		end
	end)
end

-- Focus + opening --------------------------------------------------------------------------

local function nextCrateText(): string
	return "Next crate in " .. Format.Clock(DayNight.SecondsUntilNextDay(workspace:GetServerTimeNow()))
end

-- What the panel shows. It is rebuilt only when this changes.
function Lobby:_panelKey(available: boolean): string
	local data = self.View.Controller.ClientData:Get()
	local affordable = data ~= nil and self.Item ~= nil and Shop.CanAfford(self.Item :: any, data)
	return tostring(available) .. "/" .. tostring(affordable) .. "/" .. tostring(self.State == "Waiting")
end

-- Keeps an open panel current: rebuilt when the crate lands or the day
-- rolls over, the countdown on the button ticks in place.
function Lobby:_refreshPanel()
	if not self.Focused or self.State == "Opening" then
		return
	end
	local available = self:_available()
	if self:_panelKey(available) ~= self.PanelKey then
		self:_showPanel()
	elseif not available then
		local button = self.View.Controller.FactoryHud:GetButton("Open")
		if button then
			button:SetText(WAIT_GLYPH .. "  " .. nextCrateText())
		end
	end
end

-- Camera shot on the crate pad. Without a duration it glides for as long as
-- the distance needs (the camera may be far away).
function Lobby:_focusCamera(duration: number?)
	local pad = (self.Pad :: BasePart).Position
	local camPos = pad + self.View.Origin:VectorToWorldSpace(Vector3.new(12, 7, 10))
	local glide = duration or math.clamp((workspace.CurrentCamera.CFrame.Position - camPos).Magnitude / 45, 0.7, 1.6)
	CameraDirector.GlideTo(CFrame.lookAt(camPos, pad + Vector3.new(0, 2, 0)), glide, if glide > 0.75 then Enum.EasingStyle.Sine else Enum.EasingStyle.Quint, 60)
end

function Lobby:_showPanel()
	local controller = self.View.Controller
	local data = controller.ClientData:Get()
	local item = self.Item
	if not data or not item then
		return
	end
	local available = self:_available()
	local ready = self.State == "Waiting"
	self.PanelKey = self:_panelKey(available)
	controller.FactoryHud:ShowPanel({
		Title = "Mystery Crate",
		Rarity = item.Rarity,
		Lines = {
			Shop.DailyCrate.Description,
			"🪙 2-6x price  ·  ⚡ boosts  ·  🐾 pets  ·  🎨 cosmetics  ·  👑 boss cores",
		},
		Price = if available then { Amount = Shop.GetPrice(item, data), Currency = item.Currency, Affordable = Shop.CanAfford(item, data) } else nil,
		Status = if available then nil else "Today's crate has been opened.",
		Buttons = {
			{
				Id = "Open",
				-- (the countdown ticks in place, see _refreshPanel)
				Text = if not available then nextCrateText() elseif ready then "Open Crate" else "Arriving…",
				Glyph = if available then "📦" else WAIT_GLYPH,
				Style = "Gold",
				Enabled = available and Shop.CanAfford(item, data) and ready,
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
	self:_focusCamera(0.7)
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
	local hud = controller.Hud
	local item = self.Item
	local crate = self.Crate
	if not item or not crate or self.State ~= "Waiting" or controller:IsBusy() then
		return
	end
	self.State = "Opening"
	local frozenAt = os.clock()
	local button = controller.FactoryHud:GetButton("Open")
	if button then
		button:SetLoading(true)
	end
	-- The synced balance already contains the reward. RequestPurchase freezes
	-- the price counter; a boss core can be the reward too, so those counters
	-- stay frozen as well until the lid has opened.
	local shownBefore = hud:ShownCurrency(item.Currency)
	local held = {}
	for _, id in Currencies.Stored do
		if id ~= item.Currency then
			hud:HoldCurrency(id, hud:ShownCurrency(id))
			table.insert(held, id)
		end
	end
	local result = controller:RequestPurchase(item)
	if button then
		button:SetLoading(false)
	end
	local reward = if result.Ok then result.Reward else nil
	local rewardCurrency: string? = if reward and (reward.Kind == "Coins" or reward.Kind == "BossCore") then reward.Currency or "Coins" else nil
	for _, id in held do
		if id ~= rewardCurrency then
			hud:ReleaseCurrency(id)
		end
	end
	if not reward then
		if result.Ok then
			-- No show will release the counter RequestPurchase held.
			hud:ReleaseCurrency(item.Currency)
		end
		-- (unless the zone was reset while the request was in flight)
		if (self.State :: string) == "Opening" then
			self.State = "Waiting"
			self.BobStart += os.clock() - frozenAt -- the bob resumes where it froze
		end
		hud:Toast(result.Error or "Could not open the crate.", "Error")
		return
	end
	local rarity = Rarities.Get(reward.Rarity)
	local profile = Sequences.Get(reward.Rarity)
	local glyph, text = rewardText(reward)
	local currency = result.Currency or item.Currency
	local seq = Sequence.new("Crate")
	local shown = false
	local pendingRelease: string? = nil
	local padCf = self:_padCFrame()

	local function show()
		if shown then
			return
		end
		shown = true
		hud:Banner({ Title = text, Subtitle = "Mystery Crate  ·  " .. rarity.Name, Rarity = reward.Rarity, Style = profile.Banner })
		Effects.Confetti(padCf.Position + Vector3.new(0, 3, 0), profile.Confetti, { rarity.Gradient[1], rarity.Gradient[2], Theme.Colors.Gold })
		if rewardCurrency then
			local from = Effects.ToScreen(padCf.Position + Vector3.new(0, 3, 0))
			local anchor = hud:GetCurrencyAnchor(rewardCurrency)
			if anchor then
				hud:HoldCurrency(rewardCurrency, hud:ShownCurrency(rewardCurrency))
				local duration = Effects.CoinFlight(from, Effects.GuiCenter(anchor), 14, glyph)
				pendingRelease = rewardCurrency
				task.delay(duration, function()
					hud:ReleaseCurrency(rewardCurrency, 0.8)
				end)
			end
		end
	end

	-- Coins fly from the HUD into the crate. The counter only counts the price
	-- off (a coin reward is counted up by show() when its coins land).
	local function pay()
		local price = result.Price or 0
		local anchor = hud:GetCurrencyAnchor(currency)
		local duration = 0
		if anchor and price > 0 then
			local info = Currencies.Get(currency)
			local to = Effects.ToScreen(padCf.Position + Vector3.new(0, 2, 0))
			duration = Effects.CoinFlight(Effects.GuiCenter(anchor), to, math.clamp(math.floor(math.log10(price + 1) * 2.5), 4, 16), info and info.Glyph)
		end
		hud:ReleaseCurrency(currency, duration, shownBefore - price)
	end

	controller:BeginShow(seq)
	local cine = Cinematics.Begin({ Bloom = 0.6 + rarity.Rank * 0.06 })
	cine:Focus(padCf.Position + Vector3.new(0, 2, 0))
	if not self.Focused then
		-- Focus mode was left while the request was in flight (Back, travel):
		-- bring the camera back to the crate for the show.
		self:_focusCamera()
	end
	seq:Run(function(s)
		pay()
		-- the idle bob settles back onto the pad (nearest quarter turn)
		local settled = padCf
		local body = crate.PrimaryPart
		if body then
			local from = body.CFrame
			local _, yaw = padCf:ToObjectSpace(from):ToEulerAnglesYXZ()
			settled = padCf * CFrame.Angles(0, math.round(yaw / QUARTER) * QUARTER, 0)
			if not animate(s, 0.5, function(a)
				self:_placeCrate(from:Lerp(settled, TweenService:GetValue(a, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)), crate)
			end) then
				return
			end
		end
		if not s:Wait(0.3) then
			return
		end
		-- wobble
		for i = 1, profile.CapsuleWobble do
			if not animate(s, 0.3, function(a)
				self:_placeCrate(settled * CFrame.Angles(0, 0, math.sin(a * math.pi * 4) * (0.06 + i * 0.03)), crate)
			end) then
				return
			end
			Audio.Play("Tick", { Speed = 1 + i * 0.25 })
		end
		-- lid flies open, hinged on the far edge (it swings up and away from the
		-- camera) + light pillar
		local lid = crate:FindFirstChild("Lid") :: BasePart?
		if lid then
			local hinge = padCf * CFrame.new(0, CRATE_SIZE * 0.4, -(CRATE_SIZE + 0.2) / 2)
			local rel = hinge:ToObjectSpace(lid.CFrame)
			if not animate(s, 0.4, function(a)
				lid.CFrame = hinge * CFrame.Angles(-TweenService:GetValue(a, Enum.EasingStyle.Back, Enum.EasingDirection.Out) * 2.2, 0, 0) * rel
			end) then
				return
			end
		end
		local pillar = CFrame.new(padCf.Position + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		local beam = Builder.Part({
			Name = "Beam",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 3, 3),
			CFrame = pillar,
			Material = Enum.Material.Neon,
			Color = rarity.Color,
			Transparency = 0.3,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = self.View.LocalFolder,
		})
		s.Trove:Add(beam)
		-- opaque neon core: keeps the pillar glowing inside the translucent shell
		local core = Builder.Part({
			Name = "BeamCore",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 0.7, 0.7),
			CFrame = pillar,
			Material = Enum.Material.Neon,
			Color = rarity.Color:Lerp(Color3.new(1, 1, 1), 0.5),
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = self.View.LocalFolder,
		})
		s.Trove:Add(core)
		local rise = TweenInfo.new(0.6, Enum.EasingStyle.Quint)
		s:Tween(beam, rise, { Size = Vector3.new(30, 3, 3), CFrame = pillar + Vector3.new(0, 15, 0), Transparency = 0.6 })
		s:Tween(core, rise, { Size = Vector3.new(30, 0.7, 0.7), CFrame = pillar + Vector3.new(0, 15, 0) })
		Effects.GlowBall(padCf.Position + Vector3.new(0, 3, 0), rarity.Color, 10, 0.6)
		Effects.Burst(padCf.Position + Vector3.new(0, 3, 0), "Sparks", profile.SparkBurst * 2, rarity.Color)
		Effects.FlashLight(padCf.Position + Vector3.new(0, 4, 0), rarity.Color, 7, 26, 0.9)
		if not Effects.ReduceMotion() then
			CameraDirector.Punch(profile.FovPunch)
		end
		cine:Impact(rarity.Color, 0.5 + rarity.Rank * 0.08)
		local fan = Effects.LightFan(padCf.Position + Vector3.new(0, 3.5, 0), { rarity.Gradient[1], rarity.Gradient[2], Theme.Colors.Gold }, 10, 11)
		s.Trove:Add(fan.Stop)
		Audio.Play("Fanfare")
		local tag: BillboardGui? = nil
		local tagLabel: TextLabel? = nil
		local petOut: number? = nil
		if reward.Kind == "Pet" and reward.PetId then
			local petModel = PetModel.Build(reward.PetId)
			petModel.Parent = self.View.LocalFolder
			s.Trove:Add(petModel)
			local scale = petModel:GetScale()
			local fading = {}
			for _, d in petModel:GetDescendants() do
				if d:IsA("BasePart") or d:IsA("Decal") then
					table.insert(fading, d)
				end
			end
			local start = os.clock()
			local lastK = 0
			s.Trove:Connect(RunService.Heartbeat, function()
				local t = os.clock() - start
				local k = if petOut then math.min((os.clock() - petOut) / 0.35, 1) else 0
				if k ~= lastK then
					-- outro: shrinks and fades instead of blinking out with the show
					lastK = k
					petModel:ScaleTo(scale * (1 - 0.6 * k))
					for _, d in fading do
						(d :: any).LocalTransparencyModifier = k
					end
				end
				petModel:PivotTo(padCf * CFrame.new(0, 1 + math.min(t, 0.6) * 4, 0) * CFrame.Angles(0, t * 1.4, 0))
			end)
		else
			tag = UI.new("BillboardGui", { Size = UDim2.fromOffset(260, 70), StudsOffset = Vector3.new(0, 6, 0), AlwaysOnTop = true, Adornee = self.Pad, Parent = self.View.LocalFolder })
			s.Trove:Add(tag)
			tagLabel = UI.Label({ Text = glyph .. "  " .. text, Size = UDim2.fromScale(1, 1), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = Theme.Fonts.Title, TextColor3 = rarity.Color, TextStrokeTransparency = 0.3, Parent = tag })
		end
		show()
		if not s:Wait(2.4) then
			return
		end
		-- outro: pillar, tag and pet fade out while the crate sinks into the pad
		fan.Stop()
		local out = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		s:Tween(beam, out, { Size = Vector3.new(30, 0.2, 0.2), Transparency = 1 })
		s:Tween(core, out, { Size = Vector3.new(30, 0.05, 0.05), Transparency = 1 })
		if tag and tagLabel then
			s:Tween(tagLabel, out, { TextTransparency = 1, TextStrokeTransparency = 1 })
			s:Tween(tag, out, { StudsOffset = Vector3.new(0, 7.5, 0) })
		end
		petOut = os.clock()
		self:_sinkCrate(crate, s, lid ~= nil)
	end, function(s)
		cine:End()
		if not s.Cancelled then
			show()
		end
		-- (show() releases the counter it holds once the reward coins land)
		if pendingRelease ~= currency then
			hud:ReleaseCurrency(currency)
		end
		if rewardCurrency and rewardCurrency ~= currency and rewardCurrency ~= pendingRelease then
			hud:ReleaseCurrency(rewardCurrency)
		end
		if self.Crate == crate then
			crate:Destroy()
			self.Crate = nil
		end
		if (self.State :: string) == "Opening" then
			self.State = "None"
		end
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
