-- "Try Before You Buy": 20 seconds with any unlocked vacuum at a trash
-- conveyor. The server owns the session (lane, timer, cooldown); the client
-- runs the live simulation from the shared stat formulas: counter, tank,
-- suction effect and sound, "too heavy" trash, auto-dump when the tank is full.
-- At the end a board shows "+340 % faster than your current vacuum".
-- Other players' sessions are mirrored from lane attributes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Definitions = Shared.Definitions
local Vacuums = require(Definitions.Vacuums)
local Rarities = require(Definitions.Rarities)
local Factory = require(Definitions.Factory)
local Trash = require(Definitions.Trash)
local Worlds = require(Definitions.Worlds)
local Shop = require(Definitions.Shop)
local Net = require(Shared.Net)
local Stats = require(Shared.Util.Stats)
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

local TestChamber = {}
TestChamber.__index = TestChamber

local LOCAL_PLAYER = Players.LocalPlayer

local BELT_CLEARANCE = 0.14 -- trash sits on top of the moving slats (0.12 studs tall)
local ROLL_PER_STUD = 0.15 -- round trash rolls slowly, flat trash rides flat
local SPAWN_CAP = 10 -- trash parts per second; above it one part stands for several items
local SPAWN_CAP_LOW = 4
local MAX_TAGS = 4 -- "TOO HEAVY" labels on screen at once
local FALL_TIME = 0.32 -- heavy trash drops off the belt end and is gone before the floor
local FADE_TIME = 0.35 -- vacuum and trash fade out when a test (or a mirrored one) ends

local function trashPart(def: Trash.TrashItem, parent: Instance): BasePart
	local props: { [string]: any } = {
		Name = "Trash_" .. def.Id,
		Size = def.Size,
		Color = def.Color,
		Material = def.Material,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = parent,
	}
	if def.Shape == "Ball" then
		props.Shape = Enum.PartType.Ball
	elseif def.Shape == "Cylinder" then
		props.Shape = Enum.PartType.Cylinder
	elseif def.Shape == "Wedge" then
		props.ClassName = "WedgePart"
	end
	return Builder.Part(props)
end

local function pickTrash(set: { Trash.TrashItem }, rng: Random): Trash.TrashItem
	local total = 0
	for _, item in set do
		total += item.Chance
	end
	local roll = rng:NextNumber() * total
	for _, item in set do
		roll -= item.Chance
		if roll <= 0 then
			return item
		end
	end
	return set[1]
end

local function isRound(def: Trash.TrashItem): boolean
	return def.Shape == "Ball" or def.Shape == "Cylinder"
end

-- Rotation on the belt (after facing along it): round trash rolls about its
-- cross axis, flat trash rides flat with a little yaw, so nothing digs into
-- the slats or floats above them.
local function beltRotation(def: Trash.TrashItem, along: number, yaw: number): CFrame
	if isRound(def) then
		return CFrame.Angles(-along * ROLL_PER_STUD, 0, 0)
	end
	return CFrame.Angles(0, yaw, 0)
end

-- Sideways offset that keeps the whole item on the slats.
local function laneOffset(def: Trash.TrashItem, rng: Random): number
	return rng:NextNumber(-1, 1) * math.max(Factory.TestChamber.BeltWidth / 2 - 0.6 - def.Size.X / 2, 0)
end

-- Along-belt start just behind the hatch, so trash slides out of it.
local function hatchStart(lane, def: Trash.TrashItem): number
	return lane.HatchAlong - math.max(def.Size.X, def.Size.Z) / 2 - 0.1
end

-- Where a held vacuum sits: its root goes `reach` studs in front of the
-- character so the body (any shape, any rarity scale) stays clear of the
-- legs. Also returns how far the model extends forward and below its root.
local function holdFit(model: Model): (number, number, number)
	local root = model.PrimaryPart
	if not root then
		return 2.6, 0, 0
	end
	local boxCf, boxSize = model:GetBoundingBox()
	local center = root.CFrame:PointToObjectSpace(boxCf.Position)
	local reach = math.clamp(center.Z + boxSize.Z / 2 + 0.9, 1.6, 8)
	return reach, boxSize.Z / 2 - center.Z, center.Y - boxSize.Y / 2
end

local function partsOf(model: Model): { BasePart }
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

-- UI.AutoScale never disconnects its ViewportSize listener; the test HUD is
-- rebuilt for every session, so this listener lives in the session trove.
local function autoScale(gui: GuiObject, trove: Trove.Trove): UIScale
	local camera = workspace.CurrentCamera
	local scale = UI.new("UIScale", { Name = "AutoScale", Scale = UI.ScaleFor(camera.ViewportSize), Parent = gui })
	trove:Connect(camera:GetPropertyChangedSignal("ViewportSize"), function()
		scale.Scale = UI.ScaleFor(camera.ViewportSize)
	end)
	return scale
end

-- "faster" / "slower" / "same" for a comparison fraction (what rounds to 0 % is the same).
local function verdictOf(pct: number): string
	if pct > 0.005 then
		return "faster"
	elseif pct < -0.005 then
		return "slower"
	end
	return "same"
end

function TestChamber.new(view)
	local self = setmetatable({}, TestChamber)
	self.View = view
	self.Trove = Trove.new()
	self.ActiveTrove = Trove.new()
	self.Trove:Add(self.ActiveTrove, "Clean")
	self.Lanes = {}
	self.Session = nil
	self.Remote = {}
	self.Boards = {}

	local folder = view:Find("TestChamber/Lanes")
	if folder then
		for _, lane in folder:GetChildren() do
			if lane:IsA("Model") then
				local belt = lane:FindFirstChild("Belt") :: BasePart
				local screen = lane:FindFirstChild("Screen") :: BasePart
				local hatch = lane:FindFirstChild("Hatch") :: BasePart?
				local status = screen and screen:FindFirstChild("Status")
				local start = belt:GetAttribute("BeltStart") :: Vector3
				local direction = belt:GetAttribute("BeltDirection") :: Vector3
				local entry = {
					Name = lane.Name,
					Index = lane:GetAttribute("Index"),
					Model = lane,
					Belt = belt,
					Pad = lane:FindFirstChild("Pad") :: BasePart,
					Screen = screen,
					StatusGui = status :: SurfaceGui?,
					StatusLabel = status and status:FindFirstChild("Text") :: TextLabel?,
					Start = start,
					Direction = direction,
					Length = belt:GetAttribute("BeltLength") :: number,
					-- along-belt position of the hatch's front face
					HatchAlong = if hatch then math.min((hatch.Position - start):Dot(direction) + hatch.Size.X / 2, 0) else 0,
				}
				self.Lanes[lane.Name] = entry
				self.Trove:Connect(lane.AttributeChanged, function()
					self:_laneChanged(entry)
				end)
			end
		end
	end

	self.Trove:Connect(Net.Event("TestChamberEnded").OnClientEvent, function(payload)
		local session = self.Session
		if session and type(payload) == "table" and payload.VacuumId == session.VacuumId then
			self:_finish(payload.Comparison, payload.Reason)
		end
	end)
	return self
end

-- Status screens + mirrored sessions --------------------------------------------------

function TestChamber:_laneChanged(entry)
	local occupant = entry.Model:GetAttribute("Occupant") or 0
	local remote = self.Remote[entry.Name]
	if remote and (occupant == 0 or occupant == LOCAL_PLAYER.UserId) then
		-- Unlisted, the mirror fades itself out on its Heartbeat (see _mirror)
		self.Remote[entry.Name] = nil
		task.delay(FADE_TIME + 0.05, function()
			remote:Clean()
		end)
	end
	if occupant ~= 0 then
		-- A new test on this lane: the old result board makes way for the live status
		self:_clearBoard(entry, true)
	end
	if occupant ~= 0 and occupant ~= LOCAL_PLAYER.UserId and self.View.Near and not self.Remote[entry.Name] then
		self:_mirror(entry, occupant)
	end
	self:_updateStatus(entry)
end

function TestChamber:_updateStatus(entry)
	local label = entry.StatusLabel
	if not label then
		return
	end
	local occupant = entry.Model:GetAttribute("Occupant") or 0
	if occupant == 0 then
		label.Text = string.format("LANE %d\nFREE", entry.Index or 0)
		label.TextColor3 = self.View.Theme.Neon
	else
		local vacuum = Vacuums.Get(entry.Model:GetAttribute("VacuumId"))
		local remaining = math.max(0, (entry.Model:GetAttribute("EndsAt") or 0) - workspace:GetServerTimeNow())
		label.Text = string.format("%s\n%s · %s", string.upper(entry.Model:GetAttribute("OccupantName") or "?"), if vacuum then vacuum.Name else "?", Format.Clock(remaining))
		label.TextColor3 = if vacuum then Rarities.Get(vacuum.Rarity).Color else Color3.new(1, 1, 1)
	end
end

-- Removes the local result board from a lane screen and shows the status sign
-- again (crossfading when `fade` is set).
function TestChamber:_clearBoard(entry, fade: boolean?)
	local board = self.Boards[entry.Name]
	if not board then
		return
	end
	self.Boards[entry.Name] = nil
	if entry.StatusGui then
		entry.StatusGui.Enabled = true
	end
	if not fade or not board.Parent then
		board:Destroy()
		return
	end
	local info = TweenInfo.new(0.4, Enum.EasingStyle.Quad)
	for _, d in board:GetDescendants() do
		if d:IsA("TextLabel") then
			UI.Tween(d, info, { TextTransparency = 1, TextStrokeTransparency = 1 })
		elseif d:IsA("Frame") then
			UI.Tween(d, info, { BackgroundTransparency = 1 })
		end
	end
	task.delay(0.45, function()
		board:Destroy()
	end)
end

-- Lightweight replay of someone else's test so the room feels alive.
function TestChamber:_mirror(entry, userId: number)
	local trove = Trove.new()
	self.Remote[entry.Name] = trove
	local vacuumId = entry.Model:GetAttribute("VacuumId")
	local vacuum = Vacuums.Get(vacuumId)
	if not vacuum then
		return
	end
	local skin = entry.Model:GetAttribute("Skin")
	local model = VacuumModel.Build(vacuum.Id, { Skin = if skin ~= "" then skin else nil })
	model.Parent = self.View.LocalFolder
	trove:Add(model)
	local reach = holdFit(model)
	local parts = partsOf(model)
	local world = Worlds.Get(vacuum.World)
	local set = Trash.Get(if world then world.TrashSet else "Cleanville")
	local rng = Random.new(userId)
	local items = {}
	local spawnTimer = 0
	local fadeStart: number? = nil
	local beltSpeed = math.max(entry.Belt:GetAttribute("BeltSpeed") or 5, 1)
	local up = Vector3.yAxis
	local side = entry.Direction:Cross(up)
	local function holdCFrame(): CFrame
		local player = Players:GetPlayerByUserId(userId)
		local character = player and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		return if root then CFrame.lookAt(root.Position - Vector3.new(0, 1, 0) - entry.Direction * reach, root.Position - Vector3.new(0, 1, 0) - entry.Direction * 10) else CFrame.lookAt(entry.Pad.Position + Vector3.new(0, 1.2, 0) - entry.Direction * reach, entry.Start + up * 1.2)
	end
	model:PivotTo(holdCFrame() * CFrame.new(0, -0.3, 0))
	trove:Connect(RunService.Heartbeat, function(dt)
		if not model.Parent then
			return
		end
		-- Unlisted by _laneChanged: fade out instead of vanishing in one frame
		local fade = 0
		if self.Remote[entry.Name] ~= trove then
			fadeStart = fadeStart or os.clock()
			fade = math.min((os.clock() - (fadeStart :: number)) / FADE_TIME, 1)
			for _, part in parts do
				part.LocalTransparencyModifier = fade
			end
		end
		local holdCf = holdCFrame()
		model:PivotTo(holdCf * CFrame.new(0, -0.3, 0))
		spawnTimer += dt
		if fade == 0 and spawnTimer > 0.6 and #items < (if Effects.IsLow() then 4 else 10) then
			spawnTimer = 0
			local def = pickTrash(set, rng)
			local part = trashPart(def, self.View.LocalFolder)
			trove:Add(part)
			table.insert(items, {
				Part = part,
				Def = def,
				Along = hatchStart(entry, def),
				Lateral = laneOffset(def, rng),
				Lift = part.Size.Y / 2 + BELT_CLEARANCE,
				Yaw = rng:NextNumber(-0.25, 0.25),
				Size = part.Size,
			})
		end
		for i = #items, 1, -1 do
			local item = items[i]
			item.Along += dt * beltSpeed
			local p = entry.Start + entry.Direction * item.Along + side * item.Lateral + up * item.Lift
			local rotation = CFrame.lookAt(p, p + entry.Direction).Rotation * beltRotation(item.Def, item.Along, item.Yaw)
			if item.Along > entry.Length - 4 then
				local alpha = math.clamp((item.Along - (entry.Length - 4)) / 4, 0, 1)
				p = p:Lerp(holdCf.Position + holdCf.LookVector * 2, alpha)
				item.Part.Size = item.Size * (1 - alpha * 0.8)
				if alpha >= 1 then
					item.Part:Destroy()
					table.remove(items, i)
					continue
				end
			end
			item.Part.CFrame = rotation + p
			if fade > 0 then
				item.Part.LocalTransparencyModifier = fade
			end
		end
	end)
end

function TestChamber:SetActive(active: boolean)
	self.ActiveTrove:Clean()
	for name, trove in self.Remote do
		trove:Clean()
		self.Remote[name] = nil
	end
	if not active then
		return
	end
	for _, entry in self.Lanes do
		self:_laneChanged(entry)
	end
	self.ActiveTrove:Add(task.spawn(function()
		while true do
			for _, entry in self.Lanes do
				self:_updateStatus(entry)
			end
			task.wait(0.5)
		end
	end))
end

-- Local session ---------------------------------------------------------------------------

function TestChamber:Start(vacuumId: string)
	local controller = self.View.Controller
	if self.Session or controller:IsBusy() or self.Starting then
		return
	end
	self.Starting = true
	local result = Net.Invoke("StartTestChamber", vacuumId)
	self.Starting = false
	if not result.Ok then
		controller.Hud:Toast(result.Error or "Could not start the test.", "Error")
		return
	end
	local target = controller:ViewFor(result.World) or self.View
	local zone = target:Zone("TestChamber")
	if zone then
		zone:_begin(result)
	end
end

function TestChamber:_begin(result)
	local controller = self.View.Controller
	local lane = self.Lanes[result.Lane]
	local vacuum = Vacuums.Get(result.VacuumId)
	if not lane or not vacuum then
		return
	end
	local trove = Trove.new()
	local session = {
		VacuumId = vacuum.Id,
		Lane = lane,
		EndsAt = result.EndsAt :: number,
		Trove = trove,
		Items = 0,
		Volume = 0,
		Tank = 0,
		DumpFrom = 0,
		Dumping = 0,
		Finished = false,
		Stopping = false,
		FadeStart = nil :: number?,
	}
	self.Session = session
	controller:EnterMode("TestChamber", function()
		self:_stopFromExit()
	end)
	-- Back cancels without a result; the End Test button shows the result
	controller.FactoryHud:SetHint("[Back] Cancel test")
	self:_clearBoard(lane)

	local data = controller.ClientData:Get()
	local stats = controller.ClientData:EffectiveStats(vacuum.Id)
	local currentStats = controller.ClientData:EffectiveStats(controller.ClientData:Equipped())
	local world = Worlds.Get(vacuum.World)
	local trashSet = if world then world.TrashSet else "Cleanville"
	local set = Trash.Get(trashSet)
	local rarity = Rarities.Get(vacuum.Rarity)
	local rate = Stats.PullRate(stats)
	-- Trash rides the belt at the speed its slats animate. Enough liftable trash
	-- arrives to keep the vacuum pulling at its full rate (as the server's
	-- SimulateTest assumes); above the spawn cap one part stands for several items.
	local beltSpeed = math.max(lane.Belt:GetAttribute("BeltSpeed") or 5, 1)
	local totalChance = 0
	for _, def in set do
		totalChance += def.Chance
	end
	local _, liftChance = Trash.Liftable(trashSet, stats.Power)
	local spawnRate = if liftChance > 0 then math.max(rate * 1.2 * totalChance / liftChance, Factory.TestChamber.SpawnRateMin) else Factory.TestChamber.SpawnRateMin
	local perPart = math.max(1, math.ceil(spawnRate / (if Effects.IsLow() then SPAWN_CAP_LOW else SPAWN_CAP)))
	local spawnInterval = perPart / spawnRate

	local up = Vector3.yAxis
	local side = lane.Direction:Cross(up)
	local padPos = lane.Pad.Position

	-- Vacuum held in front of the player
	local skin = data and data.Cosmetics.Skin
	local model = VacuumModel.Build(vacuum.Id, { Skin = skin })
	model.Parent = self.View.LocalFolder
	trove:Add(model)
	local extents = model:GetExtentsSize()
	local reach, front, bottom = holdFit(model)
	-- Long vacuums reach over the belt end: they are held above the slats there
	local overBelt = reach + front > (padPos - (lane.Start + lane.Direction * lane.Length)):Dot(lane.Direction)
	local minRootY = lane.Start.Y + BELT_CLEARANCE - bottom
	local modelRoot = model.PrimaryPart :: BasePart
	local nozzleAttachment = Instance.new("Attachment")
	nozzleAttachment.Name = "Nozzle"
	nozzleAttachment.Parent = modelRoot
	nozzleAttachment.Position = Vector3.new(0, extents.Y * 0.35, -front)
	-- Suction stream: particles start on an invisible sheet in front of the
	-- nozzle and fly into it (an Attachment emitter would spray from the nozzle).
	local intakeDistance = 4
	local intakeWidth = math.clamp(extents.X * 0.7, 1.2, 2.6)
	local nozzleLocal = nozzleAttachment.Position
	local intake = Builder.Part({
		Name = "SuctionIntake",
		Size = Vector3.new(intakeWidth, 0.6, 0.2),
		CFrame = modelRoot.CFrame * CFrame.lookAt(nozzleLocal - Vector3.new(0, 0, intakeDistance), nozzleLocal),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = model,
	})
	local suction = Effects.Emitter(intake, "Suction", rarity.Color, 60)
	suction.EmissionDirection = Enum.NormalId.Front
	suction.Speed = NumberRange.new(14)
	suction.Lifetime = NumberRange.new(intakeDistance / 14)
	suction.SpreadAngle = Vector2.new(6, 6)
	suction.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.06) })
	suction.Enabled = true
	local suctionSound = Audio.Loop("Suction", nozzleAttachment, { Speed = 0.8 + math.min(rate / 20, 1) })
	if suctionSound then
		trove:Add(suctionSound)
	end
	local suctionVolume = if suctionSound then suctionSound.Volume else 0
	local suctionPitch = if suctionSound then suctionSound.PlaybackSpeed else 1
	-- Particles and motor sound stop and start together (tank dump, time up, result)
	local function setSuction(on: boolean)
		suction.Enabled = on
		if suctionSound then
			UI.Tween(suctionSound, TweenInfo.new(if on then 0.2 else 0.35, Enum.EasingStyle.Quad), {
				Volume = if on then suctionVolume else 0,
				PlaybackSpeed = if on then suctionPitch else suctionPitch * 0.6,
			})
		end
	end
	local parts = partsOf(model)
	local function holdCFrame(): CFrame
		local playerRoot = controller:GetRoot()
		local origin = (if playerRoot then playerRoot.Position - Vector3.new(0, 1.4, 0) else padPos + up * 1.5) - lane.Direction * reach
		local y = origin.Y - 0.6
		if overBelt then
			y = math.max(y, minRootY)
		end
		local p = Vector3.new(origin.X, y, origin.Z)
		return CFrame.lookAt(p, p - lane.Direction)
	end
	model:PivotTo(holdCFrame())

	-- Camera behind the player looking down the belt. The server has just
	-- teleported the character here, so cut behind a quick fade instead of
	-- gliding from the Showroom through the Test Lab wall.
	local camPos = padPos + lane.Direction * 9 + up * 8 + side * 3.5
	local lookAt = lane.Start + lane.Direction * (lane.Length * 0.55) + up * 1
	local shot = CFrame.lookAt(camPos, lookAt)
	task.spawn(function()
		local faded = controller.Hud:Fade(0, 0.15)
		if self.Session == session then
			CameraDirector.Snap(shot, 64)
		end
		if faded then
			controller.Hud:Fade(1, 0.3)
		end
	end)

	-- Test HUD
	local gui = UI.new("ScreenGui", {
		Name = "TestChamberHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = Theme.Layers.FactoryHud + 1,
		Parent = LOCAL_PLAYER:WaitForChild("PlayerGui"),
	})
	trove:Add(gui)
	local top = UI.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.fromOffset(520, 120), BackgroundTransparency = 1, Parent = gui })
	autoScale(top, trove)
	local card = UI.Glass({ Size = UDim2.fromScale(1, 1), StrokeColor = rarity.Color, StrokeTransparency = 0.3, Parent = top })
	UI.Label({ Text = "TEST CHAMBER  ·  " .. string.upper(vacuum.Name), Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -36, 0, 20), TextSize = 15, TextColor3 = rarity.Color, FontFace = Theme.Fonts.Title, Parent = card })
	local timer = UI.Label({ Text = "0:20", Position = UDim2.fromOffset(18, 34), Size = UDim2.fromOffset(120, 44), FontFace = Theme.Fonts.Numbers, TextSize = 40, Parent = card })
	local counter = UI.Label({ Text = "🧹 0", Position = UDim2.fromOffset(150, 34), Size = UDim2.fromOffset(150, 44), FontFace = Theme.Fonts.Numbers, TextSize = 34, Parent = card })
	local live = UI.Label({ Text = "", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 36), Size = UDim2.fromOffset(200, 40), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Theme.Fonts.Numbers, TextSize = 26, TextColor3 = Theme.Colors.Success, Parent = card })
	local tankTrack = UI.new("Frame", { Position = UDim2.fromOffset(18, 87), Size = UDim2.new(1, -36, 0, 18), BackgroundColor3 = Theme.Colors.PanelLight, Parent = card }, { UI.Corner(Theme.Radius.Pill) })
	local tankFill = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = rarity.Color, Parent = tankTrack }, { UI.Corner(Theme.Radius.Pill) })
	-- 14 px (about 10 px on phones) with a dark outline, readable over any rarity fill
	local tankLabel = UI.Label({ Text = "TANK", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1.6), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 14, TextStrokeTransparency = 0.35, FontFace = Theme.Fonts.Title, Parent = tankTrack })
	local endHolder = UI.new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.fromOffset(170, 56), BackgroundTransparency = 1, Parent = gui })
	autoScale(endHolder, trove)
	local endButton = UI.Button({
		Text = "End Test",
		Glyph = "⏹",
		Style = "Danger",
		Size = UDim2.fromScale(1, 1),
		Radius = Theme.Radius.Pill,
		Parent = endHolder,
		OnClick = function()
			self:_requestStop()
		end,
	})
	trove:Add(endButton)
	session.Gui = gui
	UI.Pop(card, 0.2)

	-- Simulation
	local rng = Random.new()
	local items = {}
	local tags = 0
	local spawnTimer = 0
	local pull = 0
	local liveTimer = 0
	local lastPop = 0
	local function nozzlePos(): Vector3
		return nozzleAttachment.WorldPosition
	end
	local function beltCFrame(item): CFrame
		local p = lane.Start + lane.Direction * item.Along + side * item.Lateral + up * item.Lift
		local rotation = beltRotation(item.Def, item.Along, item.Yaw)
		if item.Warned then
			-- rocks on its bottom edge: the vacuum tugs at it but cannot lift it
			local rock = math.sin(os.clock() * 25 + item.Spin) * 0.12 * math.min(item.WarnT / 0.25, 1)
			p += up * (item.Def.Size.X / 2 * math.abs(math.sin(rock)))
			rotation = CFrame.Angles(0, 0, rock) * rotation
		end
		return CFrame.lookAt(p, p + lane.Direction) * rotation
	end
	-- `age`: seconds the item has already ridden (pre-fill, catch-up after a hitch)
	local function spawnTrash(age: number)
		local def = pickTrash(set, rng)
		local part = trashPart(def, self.View.LocalFolder)
		trove:Add(part)
		local item = {
			Part = part,
			Def = def,
			Along = hatchStart(lane, def) + beltSpeed * age,
			Lateral = laneOffset(def, rng),
			Lift = part.Size.Y / 2 + BELT_CLEARANCE,
			Yaw = rng:NextNumber(-0.25, 0.25),
			State = "Belt",
			T = 0,
			Heavy = def.Weight > stats.Power,
			Warned = false,
			WarnT = 0,
			From = Vector3.zero,
			Rot = CFrame.identity,
			Spin = rng:NextNumber(-3, 3),
		}
		part.CFrame = beltCFrame(item)
		table.insert(items, item)
	end
	-- Start with a loaded belt so the vacuum pulls from the first second
	for age = spawnInterval, (lane.Length - lane.HatchAlong) / beltSpeed, spawnInterval do
		spawnTrash(age)
	end

	trove:Connect(RunService.Heartbeat, function(dt)
		if not model.Parent then
			return
		end
		local fade = if session.FadeStart then math.min((os.clock() - session.FadeStart) / FADE_TIME, 1) else 0
		model:PivotTo(holdCFrame() * CFrame.new(0, math.sin(os.clock() * 18) * 0.03, 0))
		if fade > 0 then
			for _, part in parts do
				part.LocalTransparencyModifier = fade
			end
		end

		local remaining = session.EndsAt - workspace:GetServerTimeNow()
		timer.Text = Format.Clock(math.ceil(math.max(remaining, 0)))
		timer.TextColor3 = if remaining < 5 then Theme.Colors.Danger else Theme.Colors.Text
		if remaining <= 0 and not session.Stopping then
			-- Time is up: suction stops, the trash keeps moving until the result arrives
			session.Stopping = true
			setSuction(false)
			live.Text = "TIME!"
			UI.Pop(live, 0.3)
			task.delay(2.5, function()
				if self.Session == session and not session.Finished then
					self:_requestStop()
				end
			end)
		end
		local active = not session.Stopping and not session.Finished

		-- spawn (catch-up spawns after a frame hitch are spread along the belt)
		if active then
			spawnTimer = math.min(spawnTimer + dt, spawnInterval * 3)
			while spawnTimer >= spawnInterval do
				spawnTimer -= spawnInterval
				spawnTrash(spawnTimer)
			end
		end

		-- pull trash in range
		if session.Dumping > 0 then
			session.Dumping = math.max(session.Dumping - dt, 0)
			if session.Dumping == 0 then
				tankLabel.Text = "TANK"
				if active then
					setSuction(true)
				end
			end
		elseif active then
			pull = math.min(pull + rate * dt, perPart + 1)
			while pull >= perPart do
				local best, bestAlong = nil, -math.huge
				for _, item in items do
					if item.State == "Belt" and not item.Heavy and lane.Length - item.Along <= stats.Range and item.Along > bestAlong then
						best, bestAlong = item, item.Along
					end
				end
				if not best then
					break
				end
				pull -= perPart
				best.State = "Sucked"
				best.T = 0
				best.From = best.Part.Position
				best.Rot = best.Part.CFrame.Rotation
				session.Items += perPart
				session.Volume += best.Def.Volume * perPart
				session.Tank += best.Def.Volume * perPart
				counter.Text = "🧹 " .. Format.Commas(session.Items)
				if os.clock() - lastPop > 0.3 and not Effects.ReduceMotion() then
					lastPop = os.clock()
					UI.Pop(counter, 0.06)
				end
				if session.Tank >= stats.Capacity then
					session.DumpFrom = math.min(session.Tank, stats.Capacity)
					session.Tank = 0
					session.Dumping = Factory.TestChamber.DumpTime
					setSuction(false)
					tankLabel.Text = "TANK FULL · AUTO-SELL"
					Audio.Play("Coin", { Speed = 1.2 })
					Effects.Burst(nozzlePos() + up * 2, "Glow", 12, Theme.Colors.Gold)
					break
				end
			end
		end
		-- a full tank drains visibly while it is sold
		local shown = if session.Dumping > 0 then session.DumpFrom * session.Dumping / Factory.TestChamber.DumpTime else session.Tank
		tankFill.Size = UDim2.fromScale(math.clamp(shown / stats.Capacity, 0, 1), 1)

		-- move trash (orientation carries over between states, nothing snaps)
		local nozzle = nozzlePos()
		for i = #items, 1, -1 do
			local item = items[i]
			local part = item.Part
			if item.State == "Belt" then
				item.Along += beltSpeed * dt
				if item.Heavy and not item.Warned and lane.Length - item.Along <= stats.Range then
					item.Warned = true
					if tags < MAX_TAGS then
						tags += 1
						local tag = UI.new("BillboardGui", { Size = UDim2.fromOffset(110, 26), StudsOffset = Vector3.new(0, 2.2, 0), AlwaysOnTop = true, Adornee = part, Parent = part })
						item.Tag = UI.Label({ Text = "TOO HEAVY", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, TextColor3 = Theme.Colors.Danger, TextStrokeTransparency = 0.3, Parent = tag })
					end
				end
				if item.Warned then
					item.WarnT += dt
				end
				local cf = beltCFrame(item)
				part.CFrame = cf
				if item.Along >= lane.Length then
					item.State = "Falling"
					item.T = 0
					item.From = cf.Position
					item.Rot = cf.Rotation
				end
			elseif item.State == "Sucked" then
				item.T += dt / 0.32
				local t = math.min(item.T, 1)
				local p = item.From:Lerp(nozzle, t * t)
				part.CFrame = CFrame.new(p) * item.Rot * CFrame.Angles(t * 8, t * 6 * item.Spin, 0)
				part.Size = item.Def.Size * (1 - t * 0.85)
				if t >= 1 then
					part:Destroy()
					table.remove(items, i)
					continue
				end
			elseif item.State == "Falling" then
				-- tips over the belt end and is faded out before it reaches the floor
				item.T += dt
				local p = item.From + lane.Direction * (item.T * beltSpeed) - up * (item.T * item.T * 18)
				part.CFrame = CFrame.new(p) * item.Rot * CFrame.Angles(-item.T * 4, 0, 0)
				part.Transparency = math.min(item.T / FALL_TIME, 1)
				if item.T >= FALL_TIME then
					if item.Tag then
						tags -= 1
					end
					part:Destroy()
					table.remove(items, i)
					continue
				end
			end
			if item.Tag then
				-- the label leaves with its item instead of sliding through the floor
				local hide = math.max(fade, if item.State == "Falling" then math.min(item.T / 0.12, 1) else 0)
				if hide > 0 then
					item.Tag.TextTransparency = hide
					item.Tag.TextStrokeTransparency = 0.3 + 0.7 * hide
				end
			end
			if fade > 0 then
				part.LocalTransparencyModifier = fade
			end
		end

		liveTimer += dt
		if active and liveTimer > 0.4 then
			liveTimer = 0
			local elapsed = Factory.TestChamber.Duration - remaining
			if elapsed > 1 then
				-- Same formula as the server's result, so the live number ends where the result starts
				local current = Stats.SimulateTest(currentStats, trashSet, elapsed)
				if current.Score > 0 then
					local pct = Stats.SimulateTest(stats, trashSet, elapsed).Score / current.Score - 1
					local verdict = verdictOf(pct)
					live.Text = if verdict == "same" then "±0%" else Format.Percent(pct, true)
					live.TextColor3 = if verdict == "faster" then Theme.Colors.Success elseif verdict == "slower" then Theme.Colors.Danger else Theme.Colors.Text
				end
			end
		end
	end)
	session.Model = model

	-- Result shown: the HUD slides away and the vacuum and the remaining trash
	-- fade out while the belt keeps moving, then everything is cleaned up.
	session.Retire = function()
		setSuction(false)
		session.FadeStart = os.clock()
		if Effects.ReduceMotion() then
			gui.Enabled = false
		else
			local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			trove:Add(UI.Tween(top, info, { Position = UDim2.new(0.5, 0, 0, -220) }))
			trove:Add(UI.Tween(endHolder, info, { Position = UDim2.new(1, -16, 1, 120) }))
		end
		task.delay(FADE_TIME + 0.05, function()
			trove:Clean()
		end)
	end
end

function TestChamber:_requestStop()
	local session = self.Session
	if not session or session.Finished or session.Requested then
		return
	end
	session.Requested = true
	session.StopAt = workspace:GetServerTimeNow()
	task.spawn(function()
		local result = Net.Invoke("StopTestChamber")
		if self.Session ~= session or session.Finished then
			return
		end
		if result.Ok then
			self:_finish(result.Comparison, "Stopped")
		else
			self:_finish(nil, "Error")
		end
	end)
end

-- Leaving the mode (Back button, travel, another mode) ends the test too.
function TestChamber:_stopFromExit()
	local session = self.Session
	if not session or session.Finished then
		return
	end
	session.Finished = true
	session.Trove:Clean()
	self.Session = nil
	if not session.Requested then
		task.spawn(Net.Invoke, "StopTestChamber")
	end
end

function TestChamber:_finish(comparison: { [string]: any }?, reason: string?)
	local session = self.Session
	if not session or session.Finished then
		return
	end
	session.Finished = true
	self.Session = nil
	local controller = self.View.Controller
	local vacuum = Vacuums.Get(session.VacuumId)
	if reason == "Died" or reason == "Respawned" or reason == "Left" or not comparison or not vacuum then
		session.Trove:Clean()
		controller:ExitMode("TestChamber")
		return
	end
	-- The test scene fades out behind the result instead of vanishing in one frame
	if session.Retire then
		session.Retire()
	else
		session.Trove:Clean()
	end
	local lane = session.Lane
	local pct = comparison.Percent or 0
	local verdict = verdictOf(pct)
	local color = if verdict == "faster" then Theme.Colors.Success elseif verdict == "slower" then Theme.Colors.Danger else Theme.Colors.Text
	-- Seconds actually tested (End Test can stop early)
	local endedAt = session.StopAt or workspace:GetServerTimeNow()
	local seconds = math.clamp(Factory.TestChamber.Duration - (session.EndsAt - endedAt), 1, Factory.TestChamber.Duration)

	-- Result board on the lane screen (local), layered above the status sign
	self:_clearBoard(lane)
	if lane.StatusGui then
		lane.StatusGui.Enabled = false
	end
	local board = UI.new("SurfaceGui", {
		Name = "ResultBoard",
		Face = Enum.NormalId.Right,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 24,
		LightInfluence = 0,
		Brightness = 2,
		ZOffset = 1,
		Parent = lane.Screen,
	})
	self.Boards[lane.Name] = board
	local panel = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 10, 16), Parent = board })
	local big = UI.Label({ Text = if verdict == "same" then "±0%" else "0%", Position = UDim2.fromScale(0.05, 0.12), Size = UDim2.fromScale(0.9, 0.45), TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = Theme.Fonts.Numbers, TextColor3 = color, Parent = panel })
	UI.Label({
		Text = if verdict == "faster" then "FASTER THAN YOUR CURRENT VACUUM" elseif verdict == "slower" then "SLOWER THAN YOUR CURRENT VACUUM" else "SAME AS YOUR CURRENT VACUUM",
		Position = UDim2.fromScale(0.05, 0.6),
		Size = UDim2.fromScale(0.9, 0.14),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true,
		FontFace = Theme.Fonts.Title,
		Parent = panel,
	})
	UI.Label({
		Text = string.format("%s: %s items  ·  yours: %s items", vacuum.Name, Format.Commas(comparison.TestItems or session.Items), Format.Commas(comparison.CurrentItems or 0)),
		Position = UDim2.fromScale(0.05, 0.78),
		Size = UDim2.fromScale(0.9, 0.1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true,
		TextColor3 = Theme.Colors.SubText,
		Parent = panel,
	})
	if verdict ~= "same" then
		-- magnitude only: "SLOWER" already says which way
		UI.CountTo(big, 0, math.abs(pct), 1.4, function(v)
			return Format.Percent(v, verdict == "faster")
		end, true)
	end
	task.delay(10, function()
		if self.Boards[lane.Name] == board then
			self:_clearBoard(lane, true)
		end
	end)
	if verdict == "faster" and pct > 0.5 then
		-- in front of the player, close to the lane camera (the screen is on the far wall)
		Effects.Confetti(lane.Pad.Position - lane.Direction * 4 + Vector3.yAxis * 5, 50, { color, Color3.new(1, 1, 1), Theme.Colors.Gold })
	end
	Audio.Play(if verdict == "faster" then "Success" elseif verdict == "slower" then "Denied" else "Tick")

	-- Result panel with follow-up actions
	local item = Shop.Get(vacuum.Id)
	local data = controller.ClientData:Get()
	local owned = data and data.Vacuums.Owned[vacuum.Id]
	local buttons = {}
	if item and not owned then
		table.insert(buttons, {
			Text = "Buy " .. vacuum.Name,
			Glyph = "🛒",
			Style = "Gold",
			Enabled = Shop.CanAfford(item, data),
			OnClick = function()
				controller.Modal:Show(item, { Source = "Classic" })
			end,
		})
	end
	table.insert(buttons, {
		Text = "Back to Showroom",
		Glyph = "🌀",
		Style = "Primary",
		OnClick = function()
			controller:ExitMode("TestChamber")
			controller:TravelTo(self.View, "Showroom", function()
				local showroom = self.View:Zone("Showroom")
				if showroom then
					showroom:Browse(showroom:IndexOf(vacuum.Id))
				end
			end)
		end,
	})
	table.insert(buttons, {
		Text = "Close",
		Style = "Ghost",
		OnClick = function()
			controller:ExitMode("TestChamber")
		end,
	})
	controller.FactoryHud:ShowPanel({
		Title = if verdict == "same" then "Same speed" else Format.Percent(math.abs(pct)) .. " " .. verdict,
		Kicker = "Test result · " .. vacuum.Name,
		Rarity = vacuum.Rarity,
		Lines = {
			-- the panel shows the rarity tag instead of the kicker, so the name goes here
			string.format("With <b>%s</b> you cleaned <b>%s</b> items in %ds.", vacuum.Name, Format.Commas(session.Items), math.floor(seconds + 0.5)),
			string.format("Expected in %ds with this vacuum: <b>%s</b>  ·  yours: <b>%s</b>", Factory.TestChamber.Duration, Format.Commas(comparison.TestItems or 0), Format.Commas(comparison.CurrentItems or 0)),
		},
		Buttons = buttons,
	})
	controller.FactoryHud:SetHint("[Back] Close")
end

function TestChamber:Destroy()
	if self.Session then
		self:_stopFromExit()
	end
	for _, trove in self.Remote do
		trove:Clean()
	end
	for _, entry in self.Lanes do
		self:_clearBoard(entry)
	end
	self.Trove:Clean()
end

return TestChamber
