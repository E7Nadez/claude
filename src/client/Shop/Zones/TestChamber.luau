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

function TestChamber.new(view)
	local self = setmetatable({}, TestChamber)
	self.View = view
	self.Trove = Trove.new()
	self.ActiveTrove = Trove.new()
	self.Trove:Add(self.ActiveTrove, "Clean")
	self.Lanes = {}
	self.Session = nil
	self.Remote = {}

	local folder = view:Find("TestChamber/Lanes")
	if folder then
		for _, lane in folder:GetChildren() do
			if lane:IsA("Model") then
				local belt = lane:FindFirstChild("Belt") :: BasePart
				local screen = lane:FindFirstChild("Screen") :: BasePart
				local status = screen and screen:FindFirstChild("Status")
				local entry = {
					Name = lane.Name,
					Index = lane:GetAttribute("Index"),
					Model = lane,
					Belt = belt,
					Pad = lane:FindFirstChild("Pad") :: BasePart,
					Screen = screen,
					StatusLabel = status and status:FindFirstChild("Text") :: TextLabel?,
					Start = belt:GetAttribute("BeltStart") :: Vector3,
					Direction = belt:GetAttribute("BeltDirection") :: Vector3,
					Length = belt:GetAttribute("BeltLength") :: number,
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
	if self.Remote[entry.Name] and (occupant == 0 or occupant == LOCAL_PLAYER.UserId) then
		self.Remote[entry.Name]:Clean()
		self.Remote[entry.Name] = nil
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
	local world = Worlds.Get(vacuum.World)
	local set = Trash.Get(if world then world.TrashSet else "Cleanville")
	local rng = Random.new(userId)
	local items = {}
	local spawnTimer = 0
	local up = Vector3.yAxis
	trove:Connect(RunService.Heartbeat, function(dt)
		local player = Players:GetPlayerByUserId(userId)
		local character = player and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local holdCf = if root then CFrame.lookAt(root.Position - Vector3.new(0, 1, 0) - entry.Direction * 2.5, root.Position - Vector3.new(0, 1, 0) - entry.Direction * 10) else CFrame.lookAt(entry.Pad.Position + Vector3.new(0, 1.2, 0) - entry.Direction * 2.5, entry.Start + up * 1.2)
		model:PivotTo(holdCf * CFrame.new(0, -0.3, 0))
		spawnTimer += dt
		if spawnTimer > 0.6 and #items < (if Effects.IsLow() then 4 else 10) then
			spawnTimer = 0
			local def = pickTrash(set, rng)
			local part = trashPart(def, self.View.LocalFolder)
			trove:Add(part)
			table.insert(items, { Part = part, Along = 0, Lateral = rng:NextNumber(-2.2, 2.2), Lift = def.Size.Y / 2, Size = def.Size })
		end
		local side = entry.Direction:Cross(up)
		for i = #items, 1, -1 do
			local item = items[i]
			item.Along += dt * 6
			local p = entry.Start + entry.Direction * item.Along + side * item.Lateral + up * item.Lift
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
			item.Part.CFrame = CFrame.new(p) * CFrame.Angles(item.Along * 0.3, 0, 0)
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
		Dumping = 0,
		Finished = false,
		Stopping = false,
	}
	self.Session = session
	controller:EnterMode("TestChamber", function()
		self:_stopFromExit()
	end)
	controller.FactoryHud:SetHint("[Back] End test")

	local data = controller.ClientData:Get()
	local stats = controller.ClientData:EffectiveStats(vacuum.Id)
	local world = Worlds.Get(vacuum.World)
	local trashSet = if world then world.TrashSet else "Cleanville"
	local set = Trash.Get(trashSet)
	local rarity = Rarities.Get(vacuum.Rarity)
	local rate = Stats.PullRate(stats)
	local beltSpeed = math.max(5, rate * 1.25)
	local spawnInterval = 1 / math.max(rate * 1.5, Factory.TestChamber.SpawnRateMin)
	local currentScore = Stats.SimulateTest(controller.ClientData:EffectiveStats(controller.ClientData:Equipped()), trashSet).Score

	-- Vacuum held in front of the player
	local skin = data and data.Cosmetics.Skin
	local model = VacuumModel.Build(vacuum.Id, { Skin = skin })
	model.Parent = self.View.LocalFolder
	trove:Add(model)
	local extents = model:GetExtentsSize()
	local nozzleAttachment = Instance.new("Attachment")
	nozzleAttachment.Name = "Nozzle"
	nozzleAttachment.Parent = model.PrimaryPart
	nozzleAttachment.Position = Vector3.new(0, extents.Y * 0.35, -extents.Z * 0.5)
	local suction = Effects.Emitter(nozzleAttachment, "Suction", rarity.Color, 50)
	suction.EmissionDirection = Enum.NormalId.Front
	suction.Enabled = true
	local suctionSound = Audio.Loop("Suction", nozzleAttachment, { Speed = 0.8 + math.min(rate / 20, 1) })
	if suctionSound then
		trove:Add(suctionSound)
	end

	-- Camera behind the player looking down the belt
	local up = Vector3.yAxis
	local side = lane.Direction:Cross(up)
	local padPos = lane.Pad.Position
	local camPos = padPos + lane.Direction * 9 + up * 8 + side * 3.5
	local lookAt = lane.Start + lane.Direction * (lane.Length * 0.55) + up * 1
	CameraDirector.GlideTo(CFrame.lookAt(camPos, lookAt), 0.7, Enum.EasingStyle.Quint, 64)

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
	UI.AutoScale(top)
	local card = UI.Glass({ Size = UDim2.fromScale(1, 1), StrokeColor = rarity.Color, StrokeTransparency = 0.3, Parent = top })
	UI.Label({ Text = "TEST CHAMBER  ·  " .. string.upper(vacuum.Name), Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -36, 0, 20), TextSize = 15, TextColor3 = rarity.Color, FontFace = Theme.Fonts.Title, Parent = card })
	local timer = UI.Label({ Text = "0:20", Position = UDim2.fromOffset(18, 34), Size = UDim2.fromOffset(120, 44), FontFace = Theme.Fonts.Numbers, TextSize = 40, Parent = card })
	local counter = UI.Label({ Text = "🧹 0", Position = UDim2.fromOffset(150, 34), Size = UDim2.fromOffset(150, 44), FontFace = Theme.Fonts.Numbers, TextSize = 34, Parent = card })
	local live = UI.Label({ Text = "", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 36), Size = UDim2.fromOffset(200, 40), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Theme.Fonts.Numbers, TextSize = 26, TextColor3 = Theme.Colors.Success, Parent = card })
	local tankTrack = UI.new("Frame", { Position = UDim2.fromOffset(18, 90), Size = UDim2.new(1, -36, 0, 14), BackgroundColor3 = Theme.Colors.PanelLight, Parent = card }, { UI.Corner(Theme.Radius.Pill) })
	local tankFill = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = rarity.Color, Parent = tankTrack }, { UI.Corner(Theme.Radius.Pill) })
	local tankLabel = UI.Label({ Text = "TANK", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1.6), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 11, FontFace = Theme.Fonts.Title, Parent = tankTrack })
	local endHolder = UI.new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.fromOffset(170, 56), BackgroundTransparency = 1, Parent = gui })
	UI.AutoScale(endHolder)
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
	local spawnTimer = spawnInterval
	local pull = 0
	local liveTimer = 0
	local function nozzlePos(): Vector3
		return nozzleAttachment.WorldPosition
	end

	trove:Connect(RunService.Heartbeat, function(dt)
		local root = controller:GetRoot()
		local holdOrigin = if root then root.Position - Vector3.new(0, 1.4, 0) else padPos + up * 1.5
		local holdCf = CFrame.lookAt(holdOrigin - lane.Direction * 2.6, holdOrigin - lane.Direction * 12)
		model:PivotTo(holdCf * CFrame.new(0, -0.6 + math.sin(os.clock() * 18) * 0.03, 0))

		local remaining = session.EndsAt - workspace:GetServerTimeNow()
		timer.Text = Format.Clock(math.ceil(math.max(remaining, 0)))
		timer.TextColor3 = if remaining < 5 then Theme.Colors.Danger else Theme.Colors.Text
		if remaining <= 0 then
			if not session.Stopping then
				session.Stopping = true
				suction.Enabled = false
				live.Text = "TIME!"
				UI.Pop(live, 0.3)
				task.delay(2.5, function()
					if self.Session == session and not session.Finished then
						self:_requestStop()
					end
				end)
			end
			return
		end

		-- spawn
		spawnTimer += dt
		while spawnTimer >= spawnInterval do
			spawnTimer -= spawnInterval
			local def = pickTrash(set, rng)
			local part = trashPart(def, self.View.LocalFolder)
			trove:Add(part)
			table.insert(items, {
				Part = part,
				Def = def,
				Along = 0,
				Lateral = rng:NextNumber(-2.4, 2.4),
				State = "Belt",
				T = 0,
				Heavy = def.Weight > stats.Power,
				Warned = false,
				From = Vector3.zero,
				Spin = rng:NextNumber(-3, 3),
			})
		end

		-- pull trash in range
		if session.Dumping > 0 then
			session.Dumping -= dt
			if session.Dumping <= 0 then
				suction.Enabled = true
				tankLabel.Text = "TANK"
			end
		else
			pull = math.min(pull + rate * dt, 2)
			while pull >= 1 do
				local best, bestAlong = nil, -1
				for _, item in items do
					if item.State == "Belt" and not item.Heavy and lane.Length - item.Along <= stats.Range and item.Along > bestAlong then
						best, bestAlong = item, item.Along
					end
				end
				if not best then
					break
				end
				pull -= 1
				best.State = "Sucked"
				best.T = 0
				best.From = best.Part.Position
				session.Items += 1
				session.Volume += best.Def.Volume
				session.Tank += best.Def.Volume
				counter.Text = "🧹 " .. Format.Commas(session.Items)
				if session.Items % 3 == 0 then
					UI.Pop(counter, 0.06)
				end
				if session.Tank >= stats.Capacity then
					session.Tank = 0
					session.Dumping = Factory.TestChamber.DumpTime
					suction.Enabled = false
					tankLabel.Text = "TANK FULL · AUTO-SELL"
					Audio.Play("Coin", { Speed = 1.2 })
					Effects.Burst(nozzlePos() + up * 2, "Glow", 12, Theme.Colors.Gold)
				end
			end
		end
		tankFill.Size = UDim2.fromScale(math.clamp(session.Tank / stats.Capacity, 0, 1), 1)

		-- move trash
		local nozzle = nozzlePos()
		for i = #items, 1, -1 do
			local item = items[i]
			local part = item.Part
			if item.State == "Belt" then
				item.Along += beltSpeed * dt
				local p = lane.Start + lane.Direction * item.Along + side * item.Lateral + up * (item.Def.Size.Y / 2 + 0.05)
				if item.Heavy and not item.Warned and lane.Length - item.Along <= stats.Range then
					item.Warned = true
					local tag = UI.new("BillboardGui", { Size = UDim2.fromOffset(110, 26), StudsOffset = Vector3.new(0, 2.2, 0), AlwaysOnTop = true, Adornee = part, Parent = part })
					UI.Label({ Text = "TOO HEAVY", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, TextColor3 = Theme.Colors.Danger, TextStrokeTransparency = 0.3, Parent = tag })
				end
				local wobble = if item.Warned then CFrame.Angles(0, 0, math.sin(os.clock() * 25) * 0.15) else CFrame.Angles(item.Along * 0.15, 0, 0)
				if item.Along >= lane.Length then
					item.State = "Falling"
					item.T = 0
					item.From = p
				end
				part.CFrame = CFrame.lookAt(p, p + lane.Direction) * wobble
			elseif item.State == "Sucked" then
				item.T += dt / 0.32
				local t = math.min(item.T, 1)
				local p = item.From:Lerp(nozzle, t * t)
				part.CFrame = CFrame.new(p) * CFrame.Angles(t * 8, t * 6 * item.Spin, 0)
				part.Size = item.Def.Size * (1 - t * 0.85)
				if t >= 1 then
					part:Destroy()
					table.remove(items, i)
				end
			elseif item.State == "Falling" then
				item.T += dt
				local p = item.From + lane.Direction * item.T * 3 - up * item.T * item.T * 18
				part.CFrame = CFrame.new(p) * CFrame.Angles(item.T * 4, 0, 0)
				part.Transparency = math.min(item.T * 2, 1)
				if item.T >= 0.6 then
					part:Destroy()
					table.remove(items, i)
				end
			end
		end

		liveTimer += dt
		if liveTimer > 0.4 then
			liveTimer = 0
			local elapsed = Factory.TestChamber.Duration - remaining
			if elapsed > 1 and currentScore > 0 then
				local score = session.Volume / elapsed
				local pct = score / currentScore - 1
				live.Text = Format.Percent(pct, true)
				live.TextColor3 = if pct >= 0 then Theme.Colors.Success else Theme.Colors.Danger
			end
		end
	end)
	session.Model = model
end

function TestChamber:_requestStop()
	local session = self.Session
	if not session or session.Finished or session.Requested then
		return
	end
	session.Requested = true
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
	session.Trove:Clean()
	self.Session = nil
	local controller = self.View.Controller
	if reason == "Died" or reason == "Respawned" or reason == "Left" or not comparison then
		controller:ExitMode("TestChamber")
		return
	end
	local vacuum = Vacuums.Get(session.VacuumId)
	if not vacuum then
		controller:ExitMode("TestChamber")
		return
	end
	local pct = comparison.Percent or 0
	local positive = pct >= 0
	local color = if positive then Theme.Colors.Success else Theme.Colors.Danger

	-- Result board on the lane screen (local)
	local board = UI.new("SurfaceGui", {
		Name = "ResultBoard",
		Face = Enum.NormalId.Right,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 24,
		LightInfluence = 0,
		Brightness = 2,
		Parent = session.Lane.Screen,
	})
	local panel = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 10, 16), Parent = board })
	local big = UI.Label({ Text = "+0%", Position = UDim2.fromScale(0.05, 0.12), Size = UDim2.fromScale(0.9, 0.45), TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = Theme.Fonts.Numbers, TextColor3 = color, Parent = panel })
	UI.Label({
		Text = if positive then "FASTER THAN YOUR CURRENT VACUUM" else "SLOWER THAN YOUR CURRENT VACUUM",
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
	UI.CountTo(big, 0, pct, 1.4, function(v)
		return Format.Percent(v, true)
	end, true)
	task.delay(10, function()
		board:Destroy()
	end)
	if positive and pct > 0.5 then
		Effects.Confetti(session.Lane.Screen.Position, 50, { color, Color3.new(1, 1, 1), Theme.Colors.Gold })
	end
	Audio.Play(if positive then "Success" else "Denied")

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
		Title = Format.Percent(pct, true) .. (if positive then " faster" else " slower"),
		Kicker = "Test result · " .. vacuum.Name,
		Rarity = vacuum.Rarity,
		Lines = {
			string.format("You cleaned <b>%s</b> items in %ds.", Format.Commas(session.Items), Factory.TestChamber.Duration),
			string.format("Expected with this vacuum: <b>%s</b>  ·  yours: <b>%s</b>", Format.Commas(comparison.TestItems or 0), Format.Commas(comparison.CurrentItems or 0)),
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
	self.Trove:Clean()
end

return TestChamber
