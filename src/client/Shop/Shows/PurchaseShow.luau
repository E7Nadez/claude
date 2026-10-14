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

local function ease(t: number, style: Enum.EasingStyle?): number
	return TweenService:GetValue(math.clamp(t, 0, 1), style or Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
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
	local frontCam = CFrame.lookAt(cameraPos, center + Vector3.new(0, 2.5, 0))

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
		local tube = view:ToWorld(config.ExitTube)
		local step = view:ToWorld(config.ExitStep)
		controller:Teleport(CFrame.lookAt(tube + Vector3.new(0, 3.2, 0), Vector3.new(step.X, tube.Y + 3.2, step.Z)))
		state.Placed = true
		controller:SetCharacterHidden(false)
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
		CameraDirector.GlideTo(frontCam, timings.CameraGlide, Enum.EasingStyle.Quint, 60)
		if not s:Wait(timings.CameraGlide * 0.8) then
			return
		end

		-- 1) Coins into the slot
		local slot = bay:FindFirstChild("CoinSlot") :: BasePart?
		if slot and result.Price and result.Price > 0 then
			local flight = controller:CoinFlight(result.Currency or "Coins", result.Price, slot.Position, function()
				slot.Color = Color3.new(1, 1, 1)
				TweenService:Create(slot, TweenInfo.new(0.2), { Color = Color3.fromRGB(255, 210, 70) }):Play()
			end)
			if not s:Wait(flight + 0.15) then
				return
			end
			Audio.PlayAt("Clank", slot.Position)
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
			table.insert(arms, {
				Model = model,
				Base = CFrame.new(mount.Position + Vector3.new(0, mount.Size.X / 2, 0)),
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
				arm.Current = arm.Current:Lerp(arm.Target, math.min(dt * 14, 1))
				local base = arm.Base - Vector3.new(0, (1 - arm.Rise) * 5, 0)
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
			local offset = cameraPos - center
			local radius = Vector3.new(offset.X, 0, offset.Z).Magnitude
			local baseAngle = math.atan2(offset.Z, offset.X)
			local orbitStart = os.clock()
			CameraDirector.Follow(function()
				local t = os.clock() - orbitStart
				local angle = baseAngle + math.sin(t * 0.6) * 0.55
				local pos = center + Vector3.new(math.cos(angle) * radius, offset.Y + math.sin(t * 0.8) * 1.2, math.sin(angle) * radius)
				return CFrame.lookAt(pos, center + Vector3.new(0, 2.5, 0))
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
			arm.Target = arm.Base.Position + Vector3.new(0, 3, 0)
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
			local tag = UI.new("BillboardGui", {
				Name = "HeroTag",
				Size = UDim2.fromOffset(420, 110),
				StudsOffset = Vector3.new(0, 6.5, 0),
				AlwaysOnTop = true,
				Adornee = model.PrimaryPart,
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
			UI.Label({
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
			local radius = (cameraPos - center).Magnitude * 0.75
			local startAngle = math.atan2(cameraPos.Z - center.Z, cameraPos.X - center.X)
			local heroStart = os.clock()
			CameraDirector.Follow(function()
				local t = os.clock() - heroStart
				local a = startAngle + TweenService:GetValue(math.min(t / timings.HeroShot, 1), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut) * 1.9
				local pos = center + Vector3.new(math.cos(a) * radius, 3.2 + math.sin(t * 0.8) * 0.6, math.sin(a) * radius)
				return CFrame.lookAt(pos, center + Vector3.new(0, 2.4, 0))
			end)
			local spinStart = model:GetPivot()
			if not animate(s, timings.HeroShot, function(alpha)
				model:PivotTo(spinStart * CFrame.Angles(0, alpha * math.pi * 0.6, 0) + Vector3.new(0, math.sin(alpha * math.pi) * 0.8, 0))
			end) then
				return
			end
			fan.Stop()
			tag:Destroy()
			CameraDirector.StopFollow()
		end

		-- 5) Conveyor to the exit tube
		local beltEnd = view:ToWorld(config.ConveyorEnd)
		local sideCam = view:ToWorld(Vector3.new(14, 9, 94))
		CameraDirector.GlideTo(CFrame.lookAt(sideCam, beltEnd + Vector3.new(0, 1.5, 0)), timings.Conveyor, Enum.EasingStyle.Sine, 60)
		local beltStart = rootCf.Position
		local travelRotation = CFrame.lookAt(beltStart, Vector3.new(beltEnd.X, beltStart.Y, beltEnd.Z)).Rotation
		if not animate(s, timings.Conveyor, function(alpha)
			local p = beltStart:Lerp(Vector3.new(beltEnd.X, beltStart.Y, beltEnd.Z), ease(alpha, Enum.EasingStyle.Sine))
			model:PivotTo(CFrame.new(p) * travelRotation)
		end) then
			return
		end

		-- 6) Into the tube
		local tube = view:ToWorld(config.ExitTube)
		Audio.PlayAt("Tube", tube)
		local startCf = model:GetPivot()
		if not animate(s, 0.6, function(alpha)
			local p = startCf.Position:Lerp(tube + Vector3.new(0, 9, 0), ease(alpha, Enum.EasingStyle.Quad))
			model:PivotTo(CFrame.new(p) * startCf.Rotation * CFrame.Angles(0, alpha * 6, 0))
			for _, part in parts do
				part.Transparency = original[part] + (1 - original[part]) * alpha
			end
		end) then
			return
		end
		Effects.Burst(tube + Vector3.new(0, 10, 0), "Glow", 20, rarity.Color)

		-- 7) The player steps out of the tube
		local finaleCam = view:ToWorld(config.FinaleCamera)
		local root = controller:GetRoot()
		cine:Focus(if root then root else tube)
		CameraDirector.GlideTo(CFrame.lookAt(finaleCam, tube + Vector3.new(0, 3.5, 0)), 0.5, Enum.EasingStyle.Quint, 55)
		stepOut(s)
		s:Wait(timings.Banner)
	end, function(s)
		for _, stop in stops do
			stop()
		end
		cine:End()
		CameraDirector.StopFollow()
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
