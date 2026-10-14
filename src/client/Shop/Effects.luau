-- Shared visual effects: particles, part confetti, UI coin flights, screen
-- flashes, sky tint, light shows, factory quake. Everything respects the
-- Low Graphics and Reduce Motion settings.

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Builder = require(Shared.Util.Builder)
local Sequences = require(Shared.Definitions.Sequences)

local Theme = require(script.Parent.UI.Theme)
local UI = require(script.Parent.UI.Components)
local Audio = require(script.Parent.Audio)

local Effects = {}

local TEXTURES = {
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
}

local lowGraphics = false
local reduceMotion = false
local layer: ScreenGui? = nil

function Effects.SetLowGraphics(enabled: boolean)
	lowGraphics = enabled
end

function Effects.SetReduceMotion(enabled: boolean)
	reduceMotion = enabled
end

function Effects.IsLow(): boolean
	return lowGraphics
end

function Effects.ReduceMotion(): boolean
	return reduceMotion
end

-- Scales a particle/confetti count for the current quality.
function Effects.Count(n: number, kind: string?): number
	if not lowGraphics then
		return n
	end
	local mult = Sequences.LowGraphics[kind or "Particles"] or 0.35
	return math.max(1, math.floor(n * mult))
end

function Effects.Layer(): ScreenGui
	if layer and layer.Parent then
		return layer
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopEffects"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = Theme.Layers.Effects
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	layer = gui
	return gui
end

-- Particle presets -------------------------------------------------------------

local Presets = {}

function Presets.Sparks(e: ParticleEmitter, color: Color3)
	e.Texture = TEXTURES.Spark
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.25, 0.6)
	e.Speed = NumberRange.new(10, 22)
	e.SpreadAngle = Vector2.new(70, 70)
	e.Acceleration = Vector3.new(0, -40, 0)
	e.Drag = 2
end

function Presets.Glow(e: ParticleEmitter, color: Color3)
	e.Texture = TEXTURES.Spark
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(2, 8)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 3
end

function Presets.Smoke(e: ParticleEmitter, color: Color3)
	e.Texture = TEXTURES.Smoke
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) })
	e.Lifetime = NumberRange.new(1.2, 2.2)
	e.Speed = NumberRange.new(3, 6)
	e.SpreadAngle = Vector2.new(25, 25)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Acceleration = Vector3.new(0, 2, 0)
end

function Presets.Steam(e: ParticleEmitter, color: Color3)
	Presets.Smoke(e, color)
	e.Speed = NumberRange.new(8, 12)
	e.Acceleration = Vector3.new(1.5, 3, 0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 9) })
end

function Presets.Dust(e: ParticleEmitter, color: Color3)
	Presets.Smoke(e, color)
	e.Speed = NumberRange.new(0, 2)
	e.Acceleration = Vector3.new(0, -12, 0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.5) })
	e.Lifetime = NumberRange.new(1.5, 2.5)
end

function Presets.Fire(e: ParticleEmitter, color: Color3)
	e.Texture = TEXTURES.Fire
	e.Color = ColorSequence.new(Color3.fromRGB(255, 240, 160), color)
	e.LightEmission = 0.9
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.2) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.35, 0.6)
	e.Speed = NumberRange.new(12, 18)
	e.SpreadAngle = Vector2.new(12, 12)
end

function Presets.Paint(e: ParticleEmitter, color: Color3)
	e.Texture = TEXTURES.Smoke
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.2
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1.6) })
	e.Lifetime = NumberRange.new(0.3, 0.6)
	e.Speed = NumberRange.new(14, 20)
	e.SpreadAngle = Vector2.new(10, 10)
end

function Presets.Suction(e: ParticleEmitter, color: Color3)
	e.Texture = TEXTURES.Spark
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.6
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.4), NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new(0.25)
	e.Lifetime = NumberRange.new(0.3, 0.5)
	e.Speed = NumberRange.new(-24, -16)
	e.SpreadAngle = Vector2.new(25, 25)
end

function Effects.Emitter(parent: Instance, preset: string, color: Color3?, rate: number?): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Fx_" .. preset
	emitter.Enabled = false
	local apply = Presets[preset] or Presets.Sparks
	apply(emitter, color or Color3.new(1, 1, 1))
	emitter.Rate = Effects.Count(rate or 20)
	emitter.Parent = parent
	return emitter
end

-- One-shot particle burst at a world position.
function Effects.Burst(position: Vector3, preset: string, count: number, color: Color3?, direction: Vector3?)
	local attachment = Instance.new("Attachment")
	if direction then
		attachment.WorldCFrame = CFrame.lookAt(position, position + direction) * CFrame.Angles(-math.pi / 2, 0, 0)
	else
		attachment.WorldPosition = position
	end
	attachment.Parent = workspace.Terrain
	local emitter = Effects.Emitter(attachment, preset, color)
	emitter:Emit(Effects.Count(count))
	Debris:AddItem(attachment, 3)
end

-- Expanding neon sphere (impact / reveal).
function Effects.GlowBall(position: Vector3, color: Color3, size: number, duration: number?)
	local ball = Builder.Part({
		Name = "FxGlow",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.5,
		CFrame = CFrame.new(position),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = workspace,
	})
	TweenService:Create(ball, TweenInfo.new(duration or 0.5, Enum.EasingStyle.Quad), { Size = Vector3.one * size, Transparency = 1 }):Play()
	Debris:AddItem(ball, (duration or 0.5) + 0.1)
end

-- Flat expanding ring on the floor.
function Effects.Shockwave(position: Vector3, color: Color3, radius: number, duration: number?)
	local disc = Builder.Part({
		Name = "FxShock",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 1, 1),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.2,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = workspace,
	})
	TweenService:Create(disc, TweenInfo.new(duration or 0.6, Enum.EasingStyle.Quart), { Size = Vector3.new(0.2, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(disc, (duration or 0.6) + 0.1)
end

-- Physical confetti made of small parts, simulated locally.
local confettiPool: { BasePart } = {}
local activeConfetti: { { Part: BasePart, Velocity: Vector3, Spin: Vector3, Life: number, Age: number, Rot: CFrame, Pos: Vector3 } } = {}
local confettiConnection: RBXScriptConnection? = nil

local function getConfettiPart(): BasePart
	local part = table.remove(confettiPool)
	if part then
		return part
	end
	return Builder.Part({
		Name = "Confetti",
		Size = Vector3.new(0.35, 0.05, 0.22),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
end

local function stepConfetti(dt: number)
	local parts, cframes = {}, {}
	for i = #activeConfetti, 1, -1 do
		local c = activeConfetti[i]
		c.Age += dt
		if c.Age >= c.Life then
			c.Part.Parent = nil
			table.insert(confettiPool, c.Part)
			table.remove(activeConfetti, i)
		else
			c.Velocity = c.Velocity * (1 - math.min(dt * 1.6, 0.5)) + Vector3.new(0, -18 * dt, 0)
			c.Pos += c.Velocity * dt + Vector3.new(math.sin(c.Age * 6 + i) * dt * 1.5, 0, 0)
			c.Rot = c.Rot * CFrame.Angles(c.Spin.X * dt, c.Spin.Y * dt, c.Spin.Z * dt)
			table.insert(parts, c.Part)
			table.insert(cframes, CFrame.new(c.Pos) * c.Rot)
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
	if #activeConfetti == 0 and confettiConnection then
		confettiConnection:Disconnect()
		confettiConnection = nil
	end
end

function Effects.Confetti(position: Vector3, count: number, colors: { Color3 }?, power: number?)
	local palette = colors or { Theme.Colors.Accent, Theme.Colors.AccentAlt, Theme.Colors.Gold, Theme.Colors.Success, Theme.Colors.Danger }
	local n = math.min(Effects.Count(count, "Confetti"), 300 - #activeConfetti)
	local rng = Random.new()
	local strength = power or 1
	for _ = 1, n do
		local part = getConfettiPart()
		part.Color = palette[rng:NextInteger(1, #palette)]
		part.Parent = workspace
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.8, 2.2), rng:NextNumber(-1, 1)).Unit
		table.insert(activeConfetti, {
			Part = part,
			Velocity = dir * rng:NextNumber(14, 30) * strength,
			Spin = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8)),
			Life = rng:NextNumber(2.2, 3.4),
			Age = 0,
			Rot = CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0),
			Pos = position,
		})
	end
	if not confettiConnection then
		confettiConnection = RunService.Heartbeat:Connect(stepConfetti)
	end
end

-- UI effects -------------------------------------------------------------------

-- Coins fly from a screen point to another along curved paths.
function Effects.CoinFlight(from: Vector2, to: Vector2, count: number, glyph: string?, onArrive: ((number) -> ())?)
	local gui = Effects.Layer()
	local n = Effects.Count(count)
	local rng = Random.new()
	for i = 1, n do
		task.delay((i - 1) * 0.045, function()
			local coin = UI.Label({
				Text = glyph or "🪙",
				Size = UDim2.fromOffset(30, 30),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(from.X, from.Y),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextScaled = true,
				ZIndex = 10,
				Parent = gui,
			})
			local control = (from + to) / 2 + Vector2.new(rng:NextNumber(-140, 140), rng:NextNumber(-180, -60))
			local value = Instance.new("NumberValue")
			value.Changed:Connect(function(t)
				local a = from:Lerp(control, t)
				local b = control:Lerp(to, t)
				local p = a:Lerp(b, t)
				coin.Position = UDim2.fromOffset(p.X, p.Y)
				coin.Rotation = t * 540
				coin.Size = UDim2.fromOffset(30 - t * 12, 30 - t * 12)
			end)
			local tween = TweenService:Create(value, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Value = 1 })
			tween.Completed:Connect(function()
				coin:Destroy()
				value:Destroy()
				Audio.Play("Coin", { Speed = 1 + i * 0.03 })
				if onArrive then
					onArrive(i)
				end
			end)
			tween:Play()
		end)
	end
	return n * 0.045 + 0.55
end

function Effects.ScreenFlash(color: Color3, strength: number?, duration: number?)
	local gui = Effects.Layer()
	local flash = UI.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 1 - (strength or 0.5),
		ZIndex = 1,
		Parent = gui,
	})
	local tween = TweenService:Create(flash, TweenInfo.new(duration or 0.5), { BackgroundTransparency = 1 })
	tween.Completed:Connect(function()
		flash:Destroy()
	end)
	tween:Play()
end

-- Falling paper confetti across the screen (for the classic window).
function Effects.UIConfetti(count: number, colors: { Color3 }?)
	local gui = Effects.Layer()
	local palette = colors or { Theme.Colors.Accent, Theme.Colors.AccentAlt, Theme.Colors.Gold, Theme.Colors.Success }
	local rng = Random.new()
	for _ = 1, Effects.Count(count, "Confetti") do
		local piece = UI.new("Frame", {
			Size = UDim2.fromOffset(rng:NextInteger(6, 12), rng:NextInteger(10, 18)),
			Position = UDim2.new(rng:NextNumber(0.1, 0.9), 0, -0.05, 0),
			BackgroundColor3 = palette[rng:NextInteger(1, #palette)],
			Rotation = rng:NextNumber(0, 360),
			ZIndex = 5,
			Parent = gui,
		})
		local duration = rng:NextNumber(1.4, 2.4)
		local tween = TweenService:Create(piece, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			Position = UDim2.new(piece.Position.X.Scale + rng:NextNumber(-0.15, 0.15), 0, 1.05, 0),
			Rotation = piece.Rotation + rng:NextNumber(-540, 540),
			BackgroundTransparency = 0.3,
		})
		tween.Completed:Connect(function()
			piece:Destroy()
		end)
		task.delay(rng:NextNumber(0, 0.4), function()
			tween:Play()
		end)
	end
end

-- Lighting effects ---------------------------------------------------------------

-- Tints the sky/scene and returns a function that restores it.
function Effects.SkyTint(color: Color3, fadeIn: number?): () -> ()
	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "ShopSkyTint"
	correction.TintColor = Color3.new(1, 1, 1)
	correction.Parent = Lighting
	TweenService:Create(correction, TweenInfo.new(fadeIn or 1), {
		TintColor = Color3.new(1, 1, 1):Lerp(color, 0.45),
		Saturation = 0.25,
		Contrast = 0.1,
	}):Play()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local savedColor = atmosphere and atmosphere.Color
	local savedDecay = atmosphere and atmosphere.Decay
	if atmosphere then
		TweenService:Create(atmosphere, TweenInfo.new(fadeIn or 1), { Color = color, Decay = color:Lerp(Color3.new(0, 0, 0), 0.4) }):Play()
	end
	local restored = false
	return function()
		if restored then
			return
		end
		restored = true
		local tween = TweenService:Create(correction, TweenInfo.new(1.2), { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0 })
		tween.Completed:Connect(function()
			correction:Destroy()
		end)
		tween:Play()
		if atmosphere and savedColor and savedDecay then
			TweenService:Create(atmosphere, TweenInfo.new(1.2), { Color = savedColor, Decay = savedDecay }):Play()
		end
	end
end

-- Sweeping colored spotlights around a point. Returns a stop function.
function Effects.LightShow(center: Vector3, count: number, colors: { Color3 }, height: number?): () -> ()
	local n = math.max(1, if lowGraphics then math.floor(count * Sequences.LowGraphics.LightCount) else count)
	local folder = Instance.new("Folder")
	folder.Name = "FxLightShow"
	folder.Parent = workspace
	local rigs = {}
	for i = 1, n do
		local angle = (i - 1) / n * math.pi * 2
		local pos = center + Vector3.new(math.cos(angle) * 12, height or 18, math.sin(angle) * 12)
		local head = Builder.Part({
			Name = "Head",
			Size = Vector3.new(1.2, 1.2, 1.6),
			CFrame = CFrame.lookAt(pos, center),
			Material = Enum.Material.Neon,
			Color = colors[(i - 1) % #colors + 1],
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = folder,
		})
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Angle = 28
		light.Range = 60
		light.Brightness = 6
		light.Color = head.Color
		light.Shadows = false
		light.Parent = head
		local beamA = Instance.new("Attachment")
		beamA.Parent = head
		local beamB = Instance.new("Attachment")
		beamB.Parent = workspace.Terrain
		beamB.WorldPosition = center
		local beam = Instance.new("Beam")
		beam.Attachment0 = beamA
		beam.Attachment1 = beamB
		beam.Color = ColorSequence.new(head.Color)
		beam.LightEmission = 1
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		beam.Width0 = 0.6
		beam.Width1 = 6
		beam.FaceCamera = true
		beam.Parent = head
		table.insert(rigs, { Head = head, Base = pos, Target = beamB, Phase = angle })
	end
	local start = os.clock()
	local connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - start
		for _, rig in rigs do
			local target = center + Vector3.new(math.sin(t * 1.7 + rig.Phase) * 9, 0, math.cos(t * 1.3 + rig.Phase * 2) * 9)
			rig.Head.CFrame = CFrame.lookAt(rig.Base, target)
			rig.Target.WorldPosition = target
		end
	end)
	return function()
		connection:Disconnect()
		for _, rig in rigs do
			rig.Target:Destroy()
		end
		folder:Destroy()
	end
end

-- Factory quake: dust from the ceiling, flickering lamps, rumble.
function Effects.Quake(model: Model, center: Vector3, duration: number): () -> ()
	Audio.PlayAt("Rumble", center)
	local stops = {}
	local dustCount = if lowGraphics then 2 else 6
	local rng = Random.new()
	for _ = 1, dustCount do
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = center + Vector3.new(rng:NextNumber(-25, 25), 36, rng:NextNumber(-25, 25))
		attachment.Parent = workspace.Terrain
		local emitter = Effects.Emitter(attachment, "Dust", Color3.fromRGB(180, 170, 150), 30)
		emitter.Enabled = true
		table.insert(stops, attachment)
	end
	local lamps = {}
	for _, lamp in CollectionService:GetTagged("FactoryLamp") do
		if lamp:IsDescendantOf(model) and lamp:IsA("BasePart") then
			local light = lamp:FindFirstChildOfClass("PointLight")
			table.insert(lamps, { Part = lamp, Light = light, Brightness = light and light.Brightness or 1, Transparency = lamp.Transparency })
		end
	end
	local running = true
	task.spawn(function()
		local endAt = os.clock() + duration
		while running and os.clock() < endAt do
			for _, lamp in lamps do
				local on = rng:NextNumber() > 0.35
				lamp.Part.Transparency = if on then lamp.Transparency else 0.8
				if lamp.Light then
					lamp.Light.Brightness = if on then lamp.Brightness else 0.1
				end
			end
			task.wait(rng:NextNumber(0.05, 0.16))
		end
		for _, lamp in lamps do
			lamp.Part.Transparency = lamp.Transparency
			if lamp.Light then
				lamp.Light.Brightness = lamp.Brightness
			end
		end
	end)
	return function()
		running = false
		for _, attachment in stops do
			local emitter = attachment:FindFirstChildOfClass("ParticleEmitter")
			if emitter then
				emitter.Enabled = false
			end
			Debris:AddItem(attachment, 3)
		end
	end
end

-- Projects a world position onto the effects layer.
function Effects.ToScreen(position: Vector3): (Vector2, boolean)
	local point, visible = workspace.CurrentCamera:WorldToViewportPoint(position)
	return Vector2.new(point.X, point.Y), visible and point.Z > 0
end

-- Absolute center of a GUI object in effects-layer coordinates.
function Effects.GuiCenter(object: GuiObject): Vector2
	local screenGui = object:FindFirstAncestorOfClass("ScreenGui")
	local inset = Vector2.zero
	if screenGui and not screenGui.IgnoreGuiInset then
		inset = game:GetService("GuiService"):GetGuiInset()
	end
	return object.AbsolutePosition + object.AbsoluteSize / 2 + inset
end

return Effects
