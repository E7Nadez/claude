-- Entering the factory: the intake tube sucks you in and shoots you through
-- the glass pipe into the showroom (camera ride on a spline, wind particles,
-- speed lines, FOV kick). First-timers watch it; returning players get a skip
-- button; "Always Skip Intro" turns it into a quick fade.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Factory = require(Shared.Definitions.Factory)
local Sequences = require(Shared.Definitions.Sequences)

local ShopFolder = script.Parent.Parent
local Sequence = require(ShopFolder.Sequence)
local CameraDirector = require(ShopFolder.CameraDirector)
local Effects = require(ShopFolder.Effects)
local Audio = require(ShopFolder.Audio)
local UI = require(ShopFolder.UI.Components)
local Cinematics = require(ShopFolder.Cinematics)
local CollectionService = game:GetService("CollectionService")

local EntryShow = {}

-- Catmull-Rom spline through points, sampled by distance for even speed.
local function buildSpline(points: { Vector3 })
	local padded = { points[1] }
	for _, p in points do
		table.insert(padded, p)
	end
	table.insert(padded, points[#points])
	local lengths, total = {}, 0
	for i = 2, #padded - 2 do
		local length = (padded[i + 1] - padded[i]).Magnitude
		table.insert(lengths, length)
		total += length
	end
	local function point(segment: number, t: number): Vector3
		local p0, p1, p2, p3 = padded[segment], padded[segment + 1], padded[segment + 2], padded[segment + 3]
		local t2, t3 = t * t, t * t * t
		return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
	end
	return function(alpha: number): (Vector3, Vector3)
		local d = math.clamp(alpha, 0, 1) * total
		for i, length in lengths do
			if d <= length or i == #lengths then
				local t = math.clamp(d / math.max(length, 0.001), 0, 1)
				local p = point(i, t)
				local ahead = point(i, math.min(t + 0.05, 1))
				if (ahead - p).Magnitude < 0.01 and i < #lengths then
					ahead = point(i + 1, 0.05)
				end
				local dir = ahead - p
				return p, if dir.Magnitude > 0.001 then dir.Unit else Vector3.zAxis
			end
			d -= length
		end
		return points[#points], Vector3.zAxis
	end
end

local function speedLines(trove)
	local layer = Effects.Layer()
	local holder = UI.new("Frame", { Name = "SpeedLines", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = layer })
	trove:Add(holder)
	local rng = Random.new()
	local count = if Effects.IsLow() then 10 else 26
	trove:Add(task.spawn(function()
		while holder.Parent do
			for _ = 1, 3 do
				local angle = rng:NextNumber(0, math.pi * 2)
				local line = UI.new("Frame", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0.5 + math.cos(angle) * 0.08, 0, 0.5 + math.sin(angle) * 0.14, 0),
					Size = UDim2.new(0, rng:NextInteger(60, 180), 0, 2),
					Rotation = math.deg(angle),
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 0.4,
					Parent = holder,
				})
				local tween = TweenService:Create(line, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.new(0.5 + math.cos(angle) * 0.7, 0, 0.5 + math.sin(angle) * 0.9, 0),
					BackgroundTransparency = 1,
				})
				tween.Completed:Connect(function()
					line:Destroy()
				end)
				tween:Play()
			end
			task.wait(3 * 0.35 / count * 3)
		end
	end))
end

local function landingEffects(view)
	local landing = view:ToWorld(Factory.Entrance.Landing)
	Effects.Shockwave(landing - Vector3.new(0, 2.7, 0), view.Theme.Neon, 9)
	Effects.Burst(landing, "Sparks", 24, view.Theme.Neon)
	Effects.Burst(landing - Vector3.new(0, 2, 0), "Smoke", 10, Color3.fromRGB(220, 220, 230))
	Audio.Play("Pop")
end

local function landingCFrame(view): CFrame
	local landing = view:ToWorld(Factory.Entrance.Landing)
	local face = view.Origin:VectorToWorldSpace(Factory.Entrance.LandingFace)
	return CFrame.lookAt(landing, landing + face)
end

function EntryShow.Play(view)
	local controller = view.Controller
	local clientData = controller.ClientData
	if clientData:Setting("SkipIntro") == true then
		task.spawn(function()
			controller.Hud:Fade(0, 0.18)
			controller:Teleport(landingCFrame(view))
			Audio.Play("Tube", { Volume = 0.5, Speed = 1.4 })
			task.wait(0.1)
			controller.Hud:Fade(1, 0.3)
			landingEffects(view)
		end)
		return nil
	end

	local seen = clientData:Setting("SeenIntro") == true
	local points = {}
	for _, p in Factory.Entrance.TubePath do
		table.insert(points, view:ToWorld(p))
	end
	local spline = buildSpline(points)
	local duration = Sequences.Timings.EntryRide
	local seq = Sequence.new("Entry")
	local placed = false

	controller:BeginShow(seq, { Skippable = seen })
	local cine = Cinematics.Begin({ DepthOfField = false, Bloom = 0.9 })
	-- neon rings along the glass tube flash as the camera rushes past
	local rings = {}
	local entrance = view:Find("Entrance")
	if entrance then
		for _, part in entrance:GetDescendants() do
			if part:IsA("BasePart") and CollectionService:HasTag(part, "FactoryNeon") then
				table.insert(rings, { Part = part, Color = part.Color, Flashed = false })
			end
		end
	end
	seq:Run(function(s)
		controller:SetCharacterHidden(true)
		Audio.Play("Tube")
		speedLines(s.Trove)
		local windAttachment = Instance.new("Attachment")
		windAttachment.Parent = workspace.Terrain
		s.Trove:Add(windAttachment)
		local wind = Effects.Emitter(windAttachment, "Suction", view.Theme.Neon, 40)
		wind.Enabled = true
		local start = os.clock()
		local baseFov = CameraDirector.BaseFov()
		CameraDirector.Follow(function()
			local alpha = math.clamp((os.clock() - start) / duration, 0, 1)
			local e = TweenService:GetValue(alpha, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			local pos, dir = spline(e)
			local camera = workspace.CurrentCamera
			camera.FieldOfView = baseFov + 28 * math.sin(alpha * math.pi)
			windAttachment.WorldCFrame = CFrame.lookAt(pos + dir * 6, pos) * CFrame.Angles(-math.pi / 2, 0, 0)
			local roll = if Effects.ReduceMotion() then 0 else math.sin(alpha * math.pi * 3) * 0.08
			for _, ring in rings do
				if not ring.Flashed and (ring.Part.Position - pos).Magnitude < 7 then
					ring.Flashed = true
					ring.Part.Color = Color3.new(1, 1, 1)
					TweenService:Create(ring.Part, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Color = ring.Color }):Play()
				end
			end
			return CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, 0, roll)
		end)
		s:WaitUntil(function()
			local alpha = (os.clock() - start) / duration
			if alpha > 0.6 and not placed then
				placed = true
				controller:Teleport(landingCFrame(view))
			end
			return alpha >= 1
		end)
		if s.Stopped then
			return
		end
		CameraDirector.StopFollow()
		local landing = landingCFrame(view)
		CameraDirector.GlideTo(CFrame.lookAt(landing.Position - landing.LookVector * 12 + Vector3.new(0, 6, 0), landing.Position + Vector3.new(0, 1, 0)), 0.45, Enum.EasingStyle.Quad, baseFov)
		controller:SetCharacterHidden(false)
		landingEffects(view)
		cine:Impact(view.Theme.Neon, 0.7)
		local humanoid = controller:GetHumanoid()
		if humanoid then
			humanoid.Jump = true
		end
		s:Wait(0.5)
	end, function(s)
		CameraDirector.StopFollow()
		cine:End()
		for _, ring in rings do
			ring.Part.Color = ring.Color
		end
		if not s.Cancelled then
			if not placed then
				controller:Teleport(landingCFrame(view))
				landingEffects(view)
			end
			if not seen then
				clientData:SetSetting("SeenIntro", true)
			end
		end
		controller:SetCharacterHidden(false)
		controller:EndShow(seq)
		RunService.Heartbeat:Wait()
		controller.FactoryHud:SetHint("Tip: walk to a podium or press 🌀 to browse vacuums")
		task.delay(5, function()
			if not controller:CurrentMode() then
				controller.FactoryHud:SetHint(nil)
			end
		end)
	end)
	return seq
end

-- Leaving: quick whoosh back outside.
function EntryShow.Exit(view)
	local controller = view.Controller
	task.spawn(function()
		controller:ExitMode()
		Audio.Play("Tube", { Speed = 1.3, Volume = 0.45 })
		controller.Hud:Fade(0, 0.25)
		local outside = view:ToWorld(Factory.Entrance.Outside)
		local away = view.Origin:VectorToWorldSpace(Vector3.new(0, 0, -1))
		controller:Teleport(CFrame.lookAt(outside, outside + away))
		task.wait(0.15)
		controller.Hud:Fade(1, 0.35)
	end)
end

return EntryShow
