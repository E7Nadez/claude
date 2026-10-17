-- The purchase as a show:
--   coins fly from the HUD into the coin slot -> robot arms rise and assemble
--   the vacuum part by part with sparks -> rarity extras (light show, quake,
--   sky tint, orbit cam) -> conveyor -> exit tube -> the player steps out with
--   a pose and confetti. Data-driven by Definitions/Sequences, skippable,
--   cancelled cleanly on death/leave.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Definitions = Shared.Definitions
local Vacuums = require(Definitions.Vacuums)
local Rarities = require(Definitions.Rarities)
local Sequences = require(Definitions.Sequences)
local Factory = require(Definitions.Factory)
local VacuumModel = require(Shared.Models.VacuumModel)
local RobotModel = require(Shared.Models.RobotModel)

local ShopFolder = script.Parent.Parent
local Sequence = require(ShopFolder.Sequence)
local CameraDirector = require(ShopFolder.CameraDirector)
local Effects = require(ShopFolder.Effects)
local Audio = require(ShopFolder.Audio)
local Cinematics = require(ShopFolder.Cinematics)
local UI = require(ShopFolder.UI.Components)
local UIFx = require(ShopFolder.UI.UIFx)
local Theme = require(ShopFolder.UI.Theme)

local PurchaseShow = {}

-- Showroom podium 5 stands between the front camera and the bay (12 studs in
-- front of it, faded by the Showroom while the show looks through it), podium
-- 4's hologram right beside it: the assembly orbit only drifts towards the coin
-- pillar, and the hero orbit runs closer to the bay than podium 5. To get there
-- it first pushes in over the faded podium, then swings round, which keeps it
-- clear of the hologram (a cut or a straight line would run through one of them).
local ORBIT_SWING = 0.2 -- radians, assembly orbit drifts 0 .. -2x this
local HERO_RADIUS = 10.5
local HERO_HEIGHT = 4.5 -- above the bay center
local HERO_START = 0.45 -- radians gained while swinging in from the front camera
local HERO_SWEEP = 1.9 -- total radians of the hero orbit
local HERO_PUSH = 0.6 -- seconds to push in (radius, height, aim)
local HERO_BLEND = 0.9 -- seconds to swing in (angle)
local HERO_SPIN = 1.2 -- the vacuum turns with the camera: ends on a 3/4 front view
local TAG_SIZE = Vector2.new(7, 1.7) -- hero name tag, studs
local TAG_GAP = 0.3
-- Deeper than a fully stretched arm (shoulder 1.6 + lower 3.2 + upper 2.8 +
-- claws), so a lowered arm is hidden below the deck.
local ARM_SINK = 9

local function ease(t: number, style: Enum.EasingStyle?): number
	return TweenService:GetValue(math.clamp(t, 0, 1), style or Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
end

-- The exit tube is a closed ring of glass panes. These are the panes facing
-- `toward` (from the tube axis): faded locally so the vacuum flies in and the
-- player steps out through an opening instead of through the glass.
local function tubeDoor(bay: Instance, tube: Vector3, toward: Vector3): { BasePart }
	local panes = {}
	local flat = toward * Vector3.new(1, 0, 1)
	if flat.Magnitude < 0.01 then
		return panes
	end
	for _, child in bay:GetChildren() do
		if child:IsA("BasePart") and child.Material == Enum.Material.Glass then
			local offset = (child.Position - tube) * Vector3.new(1, 0, 1)
			local distance = offset.Magnitude
			if distance > 3 and distance < 5 and offset.Unit:Dot(flat.Unit) > 0.75 then
				table.insert(panes, child)
			end
		end
	end
	return panes
end

local function setPanes(panes: { BasePart }, amount: number)
	for _, pane in panes do
		if pane.Parent then
			pane.LocalTransparencyModifier = amount
		end
	end
end

-- Fades panes to `goal` on a short thread of its own: it always finishes, so the
-- door also closes after the show was skipped or cancelled.
local function fadePanes(panes: { BasePart }, goal: number, duration: number, delay: number?)
	if #panes == 0 then
		return
	end
	task.delay(delay or 0, function()
		local from = panes[1].LocalTransparencyModifier
		if from == goal then
			return
		end
		local start = os.clock()
		while true do
			local alpha = math.clamp((os.clock() - start) / duration, 0, 1)
			setPanes(panes, from + (goal - from) * alpha)
			if alpha >= 1 then
				return
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

-- Runs fn(alpha) every frame for `duration`. Returns false if the sequence stopped.
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

function PurchaseShow.Play(view, vacuumId: string, result: { [string]: any })
	local controller = view.Controller
	local vacuum = Vacuums.Get(vacuumId)
	if not vacuum then
		return
	end
	local rarity = Rarities.Get(vacuum.Rarity)
	local profile = table.clone(Sequences.Get(vacuum.Rarity))
	local timings = Sequences.Timings
	local data = controller.ClientData:Get()
	if data and data.Gamepasses.gp_express then
		profile.Duration *= 0.6
	end
	if Effects.IsLow() then
		profile.Shake *= Sequences.LowGraphics.Shake
	end

	local bay = view:Find("Showroom/AssemblyBay")
	if not bay then
		return
	end
	local config = Factory.AssemblyBay
	local center = view:ToWorld(config.Center)
	local cameraPos = view:ToWorld(config.Camera)
	local frontAim = center + Vector3.new(0, 2.5, 0)
	local frontCam = CFrame.lookAt(cameraPos, frontAim)
	-- the front camera in orbit terms (around the bay center): orbits start there
	local frontOffset = cameraPos - center
	local frontRadius = Vector3.new(frontOffset.X, 0, frontOffset.Z).Magnitude
	local frontAngle = math.atan2(frontOffset.Z, frontOffset.X)
	local beltEnd = view:ToWorld(config.ConveyorEnd)
	local tube = view:ToWorld(config.ExitTube)
	local step = view:ToWorld(config.ExitStep)
	local inDoor = tubeDoor(bay, tube, beltEnd - tube)
	local outDoor = tubeDoor(bay, tube, step - tube)
	-- The belt carries the vacuum: its slats run at the vacuum's speed meanwhile.
	local conveyor = bay:FindFirstChild("Conveyor")
	local idleSpeed = conveyor and conveyor:GetAttribute("BeltSpeed")
	local function driveBelt(speed: number?)
		if conveyor and conveyor.Parent and typeof(idleSpeed) == "number" then
			conveyor:SetAttribute("BeltSpeed", if speed then math.max(speed, idleSpeed) else idleSpeed)
		end
	end

	local seq = Sequence.new("Purchase")
	local state = { Placed = false, Banner = false }
	local stops: { () -> () } = {}

	local function banner()
		if state.Banner then
			return
		end
		state.Banner = true
		controller.Hud:Banner({
			Title = vacuum.Name,
			Subtitle = "New vacuum  ·  " .. rarity.Name,
			Rarity = vacuum.Rarity,
			Style = profile.Banner,
		})
	end

	local function stepOut(s)
		controller:Teleport(CFrame.lookAt(tube + Vector3.new(0, 3.2, 0), Vector3.new(step.X, tube.Y + 3.2, step.Z)))
		state.Placed = true
		controller:SetCharacterHidden(false)
		-- open the glass towards the step while the player walks out, then close it
		fadePanes(outDoor, 1, 0.2)
		fadePanes(outDoor, 0, 0.35, 1.2)
		local humanoid = controller:GetHumanoid()
		if humanoid then
			humanoid:MoveTo(step)
		end
		if s then
			s:Wait(0.9)
		end
		controller:PlayCheer()
		local root = controller:GetRoot()
		local at = if root then root.Position else step
		Effects.Confetti(at + Vector3.new(0, 3, 0), profile.Confetti, { rarity.Gradient[1], rarity.Gradient[2], Color3.new(1, 1, 1) })
		Effects.Shockwave(at - Vector3.new(0, 2.8, 0), rarity.Color, 10)
		Audio.Play("Pop")
		banner()
	end

	controller:BeginShow(seq)
	local cine = Cinematics.Begin({ Bloom = 0.55 + rarity.Rank * 0.08 })
	cine:Focus(center + Vector3.new(0, 2, 0))
	seq:Run(function(s)
		-- the player "steps out of the tube" at the end: keep them out of the shots
		-- (stepOut shows them again, CancelAll does on death / leaving)
		controller:SetCharacterHidden(true)
		-- The coin slot stands far left of the bay, outside the assembly framing:
		-- aim between slot and bay so the coins land on screen, then settle.
		local slot = bay:FindFirstChild("CoinSlot") :: BasePart?
		local coinSlot = if slot and result.Price and result.Price > 0 then slot else nil
		local firstShot = if coinSlot then CFrame.lookAt(cameraPos, coinSlot.Position:Lerp(frontAim, 0.55)) else frontCam
		CameraDirector.GlideTo(firstShot, timings.CameraGlide, Enum.EasingStyle.Quint, 60)
		if not s:Wait(timings.CameraGlide * 0.8) then
			return
		end

		-- 1) Coins into the slot
		if coinSlot then
			local slotColor = coinSlot.Color
			local flight = controller:CoinFlight(result.Currency or "Coins", result.Price, coinSlot.Position, function()
				coinSlot.Color = Color3.new(1, 1, 1)
				TweenService:Create(coinSlot, TweenInfo.new(0.2), { Color = slotColor }):Play()
			end)
			if not s:Wait(flight + 0.15) then
				return
			end
			Audio.PlayAt("Clank", coinSlot.Position)
			-- settles while the arms rise, before the assembly orbit takes over
			CameraDirector.GlideTo(frontCam, 0.55, Enum.EasingStyle.Sine, 60)
		end

		-- 2) Robot arms rise
		local mountsFolder = bay:FindFirstChild("Mounts")
		local mounts = {}
		if mountsFolder then
			for _, mount in mountsFolder:GetChildren() do
				if mount:IsA("BasePart") then
					table.insert(mounts, mount)
				end
			end
		end
		table.sort(mounts, function(a, b)
			return (a:GetAttribute("Index") or 0) < (b:GetAttribute("Index") or 0)
		end)
		local arms = {}
		for i = 1, math.min(profile.ArmCount, #mounts) do
			local mount = mounts[i]
			local model = RobotModel.Arm(view.Theme.Metal:Lerp(view.Theme.Trim, 0.4), rarity.Color)
			model.Parent = view.LocalFolder
			s.Trove:Add(model)
			local outward = ((mount.Position - center) * Vector3.new(1, 0, 1)).Unit
			local rest = mount.Position + Vector3.new(0, 6, 0) + outward * 1.5
			local base = CFrame.new(mount.Position + Vector3.new(0, mount.Size.X / 2, 0))
			-- posed below the deck right away: it is built at the world origin
			RobotModel.ReachArm(model, base - Vector3.new(0, ARM_SINK, 0), rest, 1)
			table.insert(arms, {
				Model = model,
				Base = base,
				Outward = outward,
				Target = rest,
				Current = rest,
				Open = 1,
				Rise = 0,
				RiseGoal = 1,
			})
		end
		s.Trove:Connect(RunService.Heartbeat, function(dt)
			for _, arm in arms do
				arm.Rise += (arm.RiseGoal - arm.Rise) * math.min(dt * 5, 1)
				local base = arm.Base - Vector3.new(0, (1 - arm.Rise) * ARM_SINK, 0)
				if arm.RiseGoal == 0 then
					-- lowering: fold down towards the sinking base instead of
					-- stretching up out of the deck
					arm.Target = base.Position + arm.Outward * 2 + Vector3.new(0, 0.6, 0)
				end
				arm.Current = arm.Current:Lerp(arm.Target, math.min(dt * 14, 1))
				RobotModel.ReachArm(arm.Model, base, arm.Current, arm.Open)
			end
		end)
		Audio.Play("Servo", { Speed = 0.8 })
		if not s:Wait(0.6) then
			return
		end

		-- 3) Assembly
		local skin = data and data.Cosmetics.Skin
		local model = VacuumModel.Build(vacuum.Id, { Skin = skin })
		model.Parent = view.LocalFolder
		s.Trove:Add(model)
		local face = Vector3.new(cameraPos.X, center.Y, cameraPos.Z)
		local rootCf = CFrame.lookAt(center + Vector3.new(0, 0.05, 0), face)
		model:PivotTo(rootCf)
		local parts = VacuumModel.AssemblyOrder(model)
		local original = {}
		for _, part in parts do
			original[part] = part.Transparency
			part.Transparency = 1
		end

		if profile.LightShow then
			table.insert(stops, Effects.LightShow(center, profile.LightCount, { rarity.Gradient[1], rarity.Gradient[2], Color3.new(1, 1, 1) }, 16))
		end
		if profile.Quake then
			table.insert(stops, Effects.Quake(view.Model, center, profile.Duration + 1.5))
		end
		if profile.SkyTint then
			table.insert(stops, Effects.SkyTint(profile.SkyTint))
		end
		if profile.Shake > 0 then
			CameraDirector.Shake(profile.Shake, profile.Duration)
		end
		if profile.Lightning then
			table.insert(stops, Effects.Lightning(center + Vector3.new(0, 2.5, 0), rarity.Color, 5, 3))
		end
		if profile.Orbit and not Effects.ReduceMotion() then
			local orbitStart = os.clock()
			CameraDirector.Follow(function()
				local t = os.clock() - orbitStart
				-- starts at the front camera and drifts towards the coin pillar only:
				-- the other way podium 4's hologram swings into the frame, and past
				-- ~0.45 rad podium 5 leaves the faded camera-to-bay corridor
				local angle = frontAngle - ORBIT_SWING + math.cos(t * 0.6) * ORBIT_SWING
				local pos = center + Vector3.new(math.cos(angle) * frontRadius, frontOffset.Y + math.sin(t * 0.8) * 1.2, math.sin(angle) * frontRadius)
				return CFrame.lookAt(pos, frontAim)
			end)
		end

		local armCount = math.max(#arms, 1)
		local rounds = math.ceil(#parts / armCount)
		local perPart = math.max(profile.Duration / math.max(rounds, 1), 0.14)
		local remaining = #parts
		for armIndex = 1, armCount do
			local arm = arms[armIndex]
			s:Spawn(function()
				for i = armIndex, #parts, armCount do
					local part = parts[i]
					local home = part:GetAttribute("Home") :: CFrame
					local goal = rootCf * home
					local pickup = if arm then arm.Base.Position + Vector3.new(0, 4.2, 0) + arm.Outward * 2 else goal.Position + Vector3.new(0, 6, 0)
					if arm then
						arm.Target = pickup
						arm.Open = 1
					end
					if not s:Wait(perPart * 0.22) then
						return
					end
					part.Transparency = original[part]
					if arm then
						arm.Open = 0
					end
					local fromCf = CFrame.new(pickup) * goal.Rotation
					local ok = animate(s, perPart * 0.6, function(alpha)
						local e = ease(alpha, Enum.EasingStyle.Cubic)
						local cf = fromCf:Lerp(goal, e)
						part.CFrame = cf + Vector3.new(0, math.sin(alpha * math.pi) * 1.2, 0)
						if arm then
							arm.Target = part.Position + Vector3.new(0, 0.4, 0)
						end
					end)
					if not ok then
						return
					end
					part.CFrame = goal
					if arm then
						arm.Open = 1
					end
					Effects.Burst(goal.Position, "Sparks", profile.SparkBurst, rarity.Color)
					Effects.FlashLight(goal.Position, Color3.new(1, 1, 1):Lerp(rarity.Color, 0.4), 5, 12, 0.16)
					Audio.PlayAt("Weld", goal.Position, { Speed = 0.9 + math.random() * 0.4 })
					remaining -= 1
					if not s:Wait(perPart * 0.18) then
						return
					end
				end
				if arm then
					arm.Target = arm.Base.Position + Vector3.new(0, 6, 0) + arm.Outward * 1.5
				end
			end)
		end
		if not s:WaitUntil(function()
			return remaining <= 0
		end, profile.Duration + 6) then
			return
		end
		for _, part in parts do
			part.Transparency = original[part]
			part.CFrame = rootCf * (part:GetAttribute("Home") :: CFrame)
		end

		-- 4) Completion burst
		CameraDirector.StopFollow()
		CameraDirector.GlideTo(frontCam, 0.4, Enum.EasingStyle.Quad, 60)
		CameraDirector.Punch(profile.FovPunch)
		cine:Impact(rarity.Color, 0.6 + rarity.Rank * 0.1)
		local heroLight = Instance.new("PointLight")
		heroLight.Color = rarity.Color
		heroLight.Brightness = 0
		heroLight.Range = 18
		heroLight.Shadows = false
		heroLight.Parent = model.PrimaryPart
		TweenService:Create(heroLight, TweenInfo.new(0.4), { Brightness = 3 }):Play()
		Effects.GlowBall(center + Vector3.new(0, 2.5, 0), rarity.Color, 16, 0.6)
		Effects.Shockwave(center + Vector3.new(0, 0.2, 0), rarity.Color, 18)
		Effects.Burst(center + Vector3.new(0, 2.5, 0), "Sparks", profile.SparkBurst * 3, rarity.Color)
		Effects.Burst(center + Vector3.new(0, 2.5, 0), "Glow", 24, rarity.Color)
		Audio.Play("Boom")
		for _, arm in arms do
			arm.RiseGoal = 0
		end
		if not animate(s, 0.9, function(alpha)
			model:PivotTo(rootCf * CFrame.Angles(0, ease(alpha) * math.pi * 2, 0) + Vector3.new(0, math.sin(alpha * math.pi) * 1.5, 0))
		end) then
			return
		end

		-- 4b) Hero shot: orbit the finished vacuum with a fan of light behind it
		if profile.HeroShot and not Effects.ReduceMotion() then
			cine:Tension(0.03)
			local fan = Effects.LightFan(center + Vector3.new(0, 2.4, 0), { rarity.Gradient[1], rarity.Gradient[2], Color3.new(1, 1, 1) }, 12, 16)
			table.insert(stops, fan.Stop)
			-- The tag is sized in studs (scales with the shot instead of covering half
			-- a phone screen) and sits just above the model's real top.
			local boxCf, boxSize = model:GetBoundingBox()
			local halfHeight = (math.abs(boxCf.RightVector.Y) * boxSize.X + math.abs(boxCf.UpVector.Y) * boxSize.Y + math.abs(boxCf.LookVector.Y) * boxSize.Z) / 2
			local top = boxCf.Position.Y + halfHeight
			local bottom = boxCf.Position.Y - halfHeight
			local adornee = model.PrimaryPart
			local anchorY = if adornee then adornee.Position.Y else model:GetPivot().Position.Y
			local tag = UI.new("BillboardGui", {
				Name = "HeroTag",
				Size = UDim2.fromScale(TAG_SIZE.X, TAG_SIZE.Y),
				StudsOffsetWorldSpace = Vector3.new(0, top - anchorY + TAG_GAP + TAG_SIZE.Y / 2, 0),
				AlwaysOnTop = true,
				Adornee = adornee,
				Parent = model,
			})
			local name = UI.Label({
				Text = string.upper(vacuum.Name),
				Size = UDim2.fromScale(1, 0.62),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextScaled = true,
				FontFace = Theme.Fonts.Title,
				TextStrokeTransparency = 0.5,
				Parent = tag,
			})
			UI.Gradient({ Color3.new(1, 1, 1), rarity.Color:Lerp(Color3.new(1, 1, 1), 0.3) }, 90).Parent = name
			local rarityLine = UI.Label({
				Text = rarity.Glyph .. "  " .. string.upper(rarity.Name) .. "  " .. rarity.Glyph,
				Position = UDim2.fromScale(0, 0.64),
				Size = UDim2.fromScale(1, 0.3),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextScaled = true,
				FontFace = Theme.Fonts.Title,
				TextColor3 = rarity.Color,
				TextStrokeTransparency = 0.5,
				Parent = tag,
			})
			UIFx.Typewriter(name, 0.6)
			-- frames the vacuum together with its tag (and the 0.8 stud bob)
			local heroAim = Vector3.new(center.X, (bottom + top + TAG_GAP + TAG_SIZE.Y + 0.8) / 2, center.Z)
			local heroStart = os.clock()
			CameraDirector.Follow(function()
				local t = os.clock() - heroStart
				-- starts exactly at the front camera: push in, swing round, orbit
				local push = ease(t / HERO_PUSH, Enum.EasingStyle.Sine)
				local swing = ease(t / HERO_BLEND, Enum.EasingStyle.Sine)
				local sweep = TweenService:GetValue(math.min(t / timings.HeroShot, 1), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut) * (HERO_SWEEP - HERO_START)
				local a = frontAngle + HERO_START * swing + sweep
				local radius = frontRadius + (HERO_RADIUS - frontRadius) * push
				local height = frontOffset.Y + (HERO_HEIGHT + math.sin(t * 0.8) * 0.5 - frontOffset.Y) * push
				local pos = center + Vector3.new(math.cos(a) * radius, height, math.sin(a) * radius)
				return CFrame.lookAt(pos, frontAim:Lerp(heroAim, push))
			end)
			local spinStart = model:GetPivot()
			if not animate(s, timings.HeroShot, function(alpha)
				-- turns with the camera, so the shot ends on a 3/4 front view with the
				-- nose already towards the belt
				model:PivotTo(spinStart * CFrame.Angles(0, -alpha * HERO_SPIN, 0) + Vector3.new(0, math.sin(alpha * math.pi) * 0.8, 0))
				-- fade the tag out over the last 0.3 s instead of popping it
				local fade = math.clamp((alpha - 1) * timings.HeroShot / 0.3 + 1, 0, 1)
				for _, label in { name, rarityLine } do
					label.TextTransparency = fade
					label.TextStrokeTransparency = 0.5 + 0.5 * fade
				end
			end) then
				return
			end
			fan.Stop()
			tag:Destroy()
			CameraDirector.StopFollow()
		end

		-- 5) Conveyor to the exit tube
		-- Beside the bay, outside the podium ring (podium 4 and its hologram stand
		-- between the front camera and the belt), looking down the belt at the tube.
		local sideCam = view:ToWorld(Vector3.new(12, 9, 106))
		local sideAim = view:ToWorld(Vector3.new(28, 5, 110))
		CameraDirector.GlideTo(CFrame.lookAt(sideCam, sideAim), timings.Conveyor, Enum.EasingStyle.Sine, 60)
		cine:Focus(model.PrimaryPart or beltEnd)
		local beltStart = rootCf.Position
		local beltStop = Vector3.new(beltEnd.X, beltStart.Y, beltEnd.Z)
		local beltLength = (beltStop - beltStart).Magnitude
		local travelRotation = CFrame.lookAt(beltStart, beltStop).Rotation
		local fromRotation = model:GetPivot().Rotation
		if not animate(s, timings.Conveyor, function(alpha)
			local p = beltStart:Lerp(beltStop, ease(alpha, Enum.EasingStyle.Sine))
			-- turns onto the belt instead of snapping to the travel direction
			model:PivotTo(CFrame.new(p) * fromRotation:Lerp(travelRotation, ease(alpha / 0.3, Enum.EasingStyle.Sine)))
			-- speed of the Sine in-out travel, so the vacuum rides the slats
			driveBelt(beltLength * math.pi / 2 * math.sin(alpha * math.pi) / timings.Conveyor)
			-- open the tube's glass towards the belt before the nose reaches it
			setPanes(inDoor, math.clamp((alpha - 0.5) / 0.25, 0, 1))
		end) then
			return
		end
		driveBelt(nil)

		-- 6) Into the tube (through the opened glass)
		Audio.PlayAt("Tube", tube)
		local startCf = model:GetPivot()
		if not animate(s, 0.6, function(alpha)
			local p = startCf.Position:Lerp(tube + Vector3.new(0, 9, 0), ease(alpha, Enum.EasingStyle.Quad))
			-- spins up once inside, so a long body does not sweep through the glass
			model:PivotTo(CFrame.new(p) * startCf.Rotation * CFrame.Angles(0, alpha ^ 3 * 6, 0))
			for _, part in parts do
				part.Transparency = original[part] + (1 - original[part]) * alpha
			end
		end) then
			return
		end
		Effects.Burst(tube + Vector3.new(0, 10, 0), "Glow", 20, rarity.Color)
		fadePanes(inDoor, 0, 0.4)

		-- 7) The player steps out of the tube
		local finaleCam = view:ToWorld(config.FinaleCamera)
		local finaleCf = CFrame.lookAt(finaleCam, tube + Vector3.new(0, 3.5, 0))
		local root = controller:GetRoot()
		cine:Focus(if root then root else tube)
		CameraDirector.GlideTo(finaleCf, 0.5, Enum.EasingStyle.Quint, 55)
		stepOut(s)
		-- ease back to the player's field of view before the camera is handed back
		if s:Wait(math.max(timings.Banner - 0.6, 0)) then
			CameraDirector.GlideTo(finaleCf, 0.6, Enum.EasingStyle.Sine, CameraDirector.BaseFov())
			s:Wait(0.6)
		end
	end, function(s)
		for _, stop in stops do
			stop()
		end
		cine:End()
		CameraDirector.StopFollow()
		driveBelt(nil)
		fadePanes(inDoor, 0, 0.3)
		if not s.Cancelled then
			if not state.Placed then
				stepOut(nil)
			end
			banner()
		end
		controller.Hud:ReleaseCurrency(result.Currency or "Coins")
		controller:ExitMode("Showroom")
		controller:EndShow(seq)
	end)
	return seq
end

return PurchaseShow
