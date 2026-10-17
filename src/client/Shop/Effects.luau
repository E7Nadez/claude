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
	-- Offsets in this layer are raw viewport pixels (what ToScreen returns),
	-- also on devices with notches / cutouts. Decoration only, nothing to tap.
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ClipToDeviceSafeArea = false
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

function Presets.Firework(e: ParticleEmitter, color: Color3)
	e.Texture = TEXTURES.Spark
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.15, color),
		ColorSequenceKeypoint.new(1, color:Lerp(Color3.new(0, 0, 0), 0.4)),
	})
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(0.7, 0.6), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(1.4, 2.2)
	e.Speed = NumberRange.new(26, 36)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -9, 0)
	e.Drag = 2.2
end

function Presets.Glitter(e: ParticleEmitter, color: Color3)
	e.Texture = TEXTURES.Spark
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.4, 0.9)
	e.Speed = NumberRange.new(2, 9)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -4, 0)
	e.Drag = 1
end

function Presets.Mote(e: ParticleEmitter, color: Color3)
	e.Texture = TEXTURES.Spark
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.14), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(6, 10)
	e.Speed = NumberRange.new(0.1, 0.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 0.05, 0)
	e.RotSpeed = NumberRange.new(-20, 20)
end

function Presets.Rise(e: ParticleEmitter, color: Color3)
	e.Texture = TEXTURES.Spark
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(1.4, 2.4)
	e.Speed = NumberRange.new(2, 4)
	e.SpreadAngle = Vector2.new(12, 12)
	e.Drag = 0.5
end

-- Negative speed: particles travel against EmissionDirection. Emit from a sheet
-- or disc in front of the intake (emission side facing away from it), or
-- override Speed with a positive range aimed at the mouth. On an Attachment at
-- the mouth itself it would blow particles out backwards.
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

-- Flat expanding ring on the floor: a glowing outline (stroke on a round
-- frame) on an invisible plate, with a faint flash filling it at the start.
function Effects.Shockwave(position: Vector3, color: Color3, radius: number, duration: number?)
	local time = duration or 0.6
	-- 1 stud margin around the final ring, so its outer stroke is never cut off
	local span = radius * 2 + 2
	local pixels = math.min(16, 1024 / span)
	local plate = Builder.Part({
		Name = "FxShock",
		Size = Vector3.new(span, 0.2, span),
		CFrame = CFrame.new(position),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = workspace,
	})
	local surface = UI.new("SurfaceGui", {
		Face = Enum.NormalId.Top,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = pixels,
		LightInfluence = 0,
		Brightness = 2,
		Parent = plate,
	})
	local ring = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.04, 0.04),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.5,
		Parent = surface,
	}, { UI.Corner(UDim.new(0.5, 0)) })
	local stroke = UI.Stroke(color, 0, 0.7 * pixels)
	stroke.Parent = ring
	local final = radius * 2 / span
	TweenService:Create(ring, TweenInfo.new(time, Enum.EasingStyle.Quart), { Size = UDim2.fromScale(final, final) }):Play()
	TweenService:Create(ring, TweenInfo.new(time * 0.35, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(stroke, TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Transparency = 1, Thickness = 0.12 * pixels }):Play()
	Debris:AddItem(plate, time + 0.1)
end

-- Physical confetti made of small parts, simulated locally: paper-like drag and
-- flutter, settles flat on the floor below it and fades out at the end.
local confettiPool: { BasePart } = {}
local activeConfetti: { { Part: BasePart, Velocity: Vector3, Spin: Vector3, Life: number, Age: number, Rot: CFrame, Pos: Vector3, Phase: number, Ground: number?, Landed: boolean } } = {}
local confettiConnection: RBXScriptConnection? = nil
local CONFETTI_FADE = 0.5
-- ground probes per frame (one per piece, when it starts to fall)
local CONFETTI_PROBES = 30
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

local function getConfettiPart(): BasePart
	local part = table.remove(confettiPool)
	if part then
		part.Transparency = 0
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
	local probes = 0
	for i = #activeConfetti, 1, -1 do
		local c = activeConfetti[i]
		c.Age += dt
		if c.Age >= c.Life then
			c.Part.Parent = nil
			table.insert(confettiPool, c.Part)
			table.remove(activeConfetti, i)
		else
			if c.Age > c.Life - CONFETTI_FADE then
				c.Part.Transparency = (c.Age - (c.Life - CONFETTI_FADE)) / CONFETTI_FADE
			end
			if not c.Landed then
				-- terminal speed ~5 studs/s: drifts down like paper, not gravel
				c.Velocity = c.Velocity * (1 - math.min(dt * 2.4, 0.5)) + Vector3.new(0, -12 * dt, 0)
				local flutter = Vector3.new(math.sin(c.Age * 5 + c.Phase), 0, math.cos(c.Age * 4 + c.Phase)) * 1.6
				c.Pos += (c.Velocity + flutter) * dt
				c.Rot = c.Rot * CFrame.Angles(c.Spin.X * dt, c.Spin.Y * dt, c.Spin.Z * dt)
				-- probed once the fall has picked up, when little sideways drift is left
				if c.Ground == nil and c.Velocity.Y < -3 and probes < CONFETTI_PROBES then
					probes += 1
					local hit = workspace:Raycast(c.Pos + Vector3.new(0, 0.5, 0), Vector3.new(0, -60, 0), groundParams)
					c.Ground = if hit then hit.Position.Y + 0.03 else -math.huge
				end
				local ground = c.Ground
				if ground and c.Pos.Y <= ground then
					-- settle flat on the floor instead of sinking through it
					c.Landed = true
					c.Pos = Vector3.new(c.Pos.X, ground, c.Pos.Z)
					local _, yaw = c.Rot:ToEulerAnglesYXZ()
					c.Rot = CFrame.Angles(0, yaw, 0)
				end
				table.insert(parts, c.Part)
				table.insert(cframes, CFrame.new(c.Pos) * c.Rot)
			end
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
	local spin = if reduceMotion then 3 else 8
	-- characters are not floors (the local one is often right under the burst)
	local characters = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end
	groundParams.FilterDescendantsInstances = characters
	for _ = 1, n do
		local part = getConfettiPart()
		local rot = CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
		part.Color = palette[rng:NextInteger(1, #palette)]
		-- placed before it shows: a pooled piece still sits where it last landed
		part.CFrame = CFrame.new(position) * rot
		part.Parent = workspace
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.8, 2.2), rng:NextNumber(-1, 1)).Unit
		table.insert(activeConfetti, {
			Part = part,
			Velocity = dir * rng:NextNumber(14, 30) * strength,
			Spin = Vector3.new(rng:NextNumber(-spin, spin), rng:NextNumber(-spin, spin), rng:NextNumber(-spin, spin)),
			Life = rng:NextNumber(2.6, 3.8),
			Age = 0,
			Rot = rot,
			Pos = position,
			Phase = rng:NextNumber(0, math.pi * 2),
			Ground = nil,
			Landed = false,
		})
	end
	if not confettiConnection then
		confettiConnection = RunService.Heartbeat:Connect(stepConfetti)
	end
end

-- UI effects -------------------------------------------------------------------

-- A coin flight end: a point on the effects layer, a GUI object or a world
-- position. The last two are tracked while the coins fly (the HUD column
-- slides under the letterbox as a show starts, the camera moves).
export type CoinPoint = Vector2 | GuiObject | Vector3

local function coinPoint(target: CoinPoint, last: Vector2?): Vector2
	if typeof(target) == "Vector2" then
		return target :: Vector2
	elseif typeof(target) == "Vector3" then
		return (Effects.ToScreen(target :: Vector3))
	end
	local object = target :: GuiObject
	if last and not object.Parent then
		return last
	end
	return Effects.GuiCenter(object)
end

-- Coins fly from a screen point to another along curved paths. Returns the
-- duration and a cancel function (skip / cancel: no more coins, no onArrive).
function Effects.CoinFlight(from: CoinPoint, to: CoinPoint, count: number, glyph: string?, onArrive: ((number) -> ())?): (number, () -> ())
	local gui = Effects.Layer()
	local n = Effects.Count(count)
	local rng = Random.new()
	local calm = reduceMotion
	local cancelled = false
	local flying: { [Instance]: Tween } = {}
	for i = 1, n do
		task.delay((i - 1) * 0.045, function()
			if cancelled then
				return
			end
			local start = coinPoint(from)
			local goal = coinPoint(to)
			local coin = UI.Label({
				Text = glyph or "🪙",
				Size = UDim2.fromOffset(0, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(start.X, start.Y),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextScaled = true,
				ZIndex = 10,
				Parent = gui,
			})
			local bend = Vector2.new(rng:NextNumber(-140, 140), rng:NextNumber(-180, -60))
			local value = Instance.new("NumberValue")
			-- goes with the coin when a cancel destroys it
			value.Parent = coin
			value.Changed:Connect(function(t)
				goal = coinPoint(to, goal)
				local control = (start + goal) / 2 + bend
				local a = start:Lerp(control, t)
				local b = control:Lerp(goal, t)
				local p = a:Lerp(b, t)
				coin.Position = UDim2.fromOffset(p.X, p.Y)
				coin.Rotation = if calm then 0 else t * 540
				-- grows out of the source instead of popping in at full size
				local size = (30 - t * 12) * math.min(t / 0.1, 1)
				coin.Size = UDim2.fromOffset(size, size)
			end)
			local tween = TweenService:Create(value, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Value = 1 })
			flying[coin] = tween
			tween.Completed:Connect(function()
				flying[coin] = nil
				coin:Destroy()
				value:Destroy()
				if cancelled then
					return
				end
				Audio.Play("Coin", { Speed = 1 + i * 0.03 })
				if onArrive then
					onArrive(i)
				end
			end)
			tween:Play()
		end)
	end
	return n * 0.045 + 0.55, function()
		if cancelled then
			return
		end
		cancelled = true
		for coin, tween in flying do
			flying[coin] = nil
			tween:Cancel()
			coin:Destroy()
		end
	end
end

function Effects.ScreenFlash(color: Color3, strength: number?, duration: number?)
	local gui = Effects.Layer()
	local amount = strength or 0.5
	local time = duration or 0.5
	if reduceMotion then
		-- a soft glow instead of a flash; capped, not scaled, because some
		-- callers already tone it down for Reduce Motion themselves
		amount = math.min(amount, 0.2)
		time = math.max(time, 0.8)
	end
	local flash = UI.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 1 - amount,
		ZIndex = 1,
		Parent = gui,
	})
	local tween = TweenService:Create(flash, TweenInfo.new(time), { BackgroundTransparency = 1 })
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
	local turn = if reduceMotion then 90 else 540
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
			Rotation = piece.Rotation + rng:NextNumber(-turn, turn),
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

-- Sweeping colored spotlights around a point. They fade in, and the returned
-- stop function fades them out before removing them.
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
			Transparency = 1,
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
		light.Brightness = 0
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
		beam.Width0 = 0
		beam.Width1 = 0
		beam.FaceCamera = true
		beam.Parent = head
		table.insert(rigs, { Head = head, Light = light, Beam = beam, Base = pos, Target = beamB, Phase = angle })
	end
	local start = os.clock()
	-- Reduce Motion: a slow drift instead of a sweep
	local speed = if reduceMotion then 0.4 else 1
	local fade, shown = 0, -1
	local stopping = false
	local connection = RunService.Heartbeat:Connect(function(dt)
		fade = if stopping then math.max(fade - dt / 0.5, 0) else math.min(fade + dt / 0.4, 1)
		local t = (os.clock() - start) * speed
		for _, rig in rigs do
			local target = center + Vector3.new(math.sin(t * 1.7 + rig.Phase) * 9, 0, math.cos(t * 1.3 + rig.Phase * 2) * 9)
			rig.Head.CFrame = CFrame.lookAt(rig.Base, target)
			rig.Target.WorldPosition = target
			if fade ~= shown then
				rig.Head.Transparency = 1 - fade
				rig.Light.Brightness = 6 * fade
				rig.Beam.Width0 = 0.6 * fade
				rig.Beam.Width1 = 6 * fade
			end
		end
		shown = fade
	end)
	local stopped = false
	return function()
		if stopped then
			return
		end
		stopped = true
		stopping = true
		task.delay(0.55, function()
			connection:Disconnect()
			for _, rig in rigs do
				rig.Target:Destroy()
			end
			folder:Destroy()
		end)
	end
end

-- Factory quake: dust from the ceiling, flickering lamps, rumble. Ends by itself
-- after `duration`; the returned stop function ends it early (skip / cancel).
function Effects.Quake(model: Model, center: Vector3, duration: number): () -> ()
	local calm = reduceMotion
	-- Owned rather than fire-and-forget, so it fades out with the quake (also on
	-- a skip) instead of rumbling on or being cut off. Plays once.
	local rumbleHolder = Instance.new("Attachment")
	rumbleHolder.WorldPosition = center
	rumbleHolder.Parent = workspace.Terrain
	local rumble = Audio.Loop("Rumble", rumbleHolder)
	if rumble then
		rumble.Looped = false
		rumble.RollOffMinDistance = 10
		rumble.RollOffMaxDistance = 140
		rumble.Ended:Once(function()
			rumbleHolder:Destroy()
		end)
	end
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
	local finished = false
	-- Dust, lamps and rumble end together: when the time is up or on stop.
	local function finish()
		if finished then
			return
		end
		finished = true
		running = false
		for _, attachment in stops do
			local emitter = attachment:FindFirstChildOfClass("ParticleEmitter")
			if emitter then
				emitter.Enabled = false
			end
			Debris:AddItem(attachment, 3)
		end
		if rumble and rumble.Parent then
			TweenService:Create(rumble, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { Volume = 0 }):Play()
		end
		Debris:AddItem(rumbleHolder, 0.9)
		for _, lamp in lamps do
			if calm then
				if lamp.Part.Parent then
					TweenService:Create(lamp.Part, TweenInfo.new(0.6, Enum.EasingStyle.Sine), { Transparency = lamp.Transparency }):Play()
					if lamp.Light then
						TweenService:Create(lamp.Light, TweenInfo.new(0.6, Enum.EasingStyle.Sine), { Brightness = lamp.Brightness }):Play()
					end
				end
			else
				lamp.Part.Transparency = lamp.Transparency
				if lamp.Light then
					lamp.Light.Brightness = lamp.Brightness
				end
			end
		end
	end
	task.spawn(function()
		local endAt = os.clock() + duration
		if calm then
			-- Reduce Motion: the lamps dim once instead of strobing
			for _, lamp in lamps do
				local dim = TweenInfo.new(0.4, Enum.EasingStyle.Sine)
				TweenService:Create(lamp.Part, dim, { Transparency = math.max(lamp.Transparency, lamp.Transparency + (0.8 - lamp.Transparency) * 0.4) }):Play()
				if lamp.Light then
					TweenService:Create(lamp.Light, dim, { Brightness = lamp.Brightness * 0.5 }):Play()
				end
			end
		end
		while running and os.clock() < endAt do
			if calm then
				task.wait(0.1)
			else
				for _, lamp in lamps do
					local on = rng:NextNumber() > 0.35
					lamp.Part.Transparency = if on then lamp.Transparency else 0.8
					if lamp.Light then
						lamp.Light.Brightness = if on then lamp.Brightness else 0.1
					end
				end
				task.wait(rng:NextNumber(0.05, 0.16))
			end
		end
		finish()
	end)
	return finish
end

-- Short bright light at a point (welds, impacts).
function Effects.FlashLight(position: Vector3, color: Color3, brightness: number?, range: number?, duration: number?)
	local holder = Builder.Part({
		Name = "FxLight",
		Size = Vector3.one * 0.2,
		CFrame = CFrame.new(position),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = workspace,
	})
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness or 6
	light.Range = range or 12
	light.Shadows = false
	light.Parent = holder
	TweenService:Create(light, TweenInfo.new(duration or 0.2, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
	Debris:AddItem(holder, (duration or 0.2) + 0.1)
end

-- Fan of light beams radiating from a point, kept facing the camera so it
-- always reads as a halo behind the subject. Returns { Stop = fn }.
function Effects.LightFan(center: Vector3 | BasePart, colors: { Color3 }, count: number?, radius: number?): { Stop: () -> () }
	local n = if lowGraphics then 5 else (count or 10)
	local r = radius or 14
	local origin = Instance.new("Attachment")
	origin.Parent = workspace.Terrain
	local ends = {}
	local beams = {}
	for i = 1, n do
		local tip = Instance.new("Attachment")
		tip.Parent = workspace.Terrain
		local beam = Instance.new("Beam")
		beam.Attachment0 = origin
		beam.Attachment1 = tip
		beam.Color = ColorSequence.new(colors[(i - 1) % #colors + 1])
		beam.LightEmission = 1
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		beam.Width0 = 0.4
		beam.Width1 = r * 0.28
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Parent = origin
		table.insert(ends, tip)
		table.insert(beams, beam)
	end
	local start = os.clock()
	local fade = 0
	local connection = RunService.RenderStepped:Connect(function(dt)
		fade = math.min(fade + dt * 2.5, 1)
		local position = if typeof(center) == "Vector3" then center else (center :: BasePart).Position
		local camera = workspace.CurrentCamera.CFrame
		origin.WorldPosition = position
		local t = os.clock() - start
		for i, tip in ends do
			local a = t * 0.45 + (i - 1) / n * math.pi * 2
			local length = r * fade * (0.75 + 0.25 * math.sin(t * 2 + i))
			tip.WorldPosition = position + (camera.RightVector * math.cos(a) + camera.UpVector * math.sin(a)) * length - camera.LookVector * 2
		end
	end)
	local stopped = false
	return {
		Stop = function()
			if stopped then
				return
			end
			stopped = true
			for _, beam in beams do
				TweenService:Create(beam, TweenInfo.new(0.4), { Width1 = 0, Width0 = 0 }):Play()
			end
			task.delay(0.45, function()
				connection:Disconnect()
				origin:Destroy()
				for _, tip in ends do
					tip:Destroy()
				end
			end)
		end,
	}
end

-- Crackling electric arcs around a point: each arc is a jagged chain of short
-- straight beams, re-randomised every tick. Returns a stop function.
function Effects.Lightning(center: Vector3, color: Color3, radius: number?, arcs: number?): () -> ()
	local n = if lowGraphics then 1 else (arcs or 3)
	local r = radius or 4
	local calm = reduceMotion
	local rng = Random.new()
	local segments = 6
	local rigs = {}
	for _ = 1, n do
		local points = {}
		for _ = 0, segments do
			local point = Instance.new("Attachment")
			point.Parent = workspace.Terrain
			table.insert(points, point)
		end
		local beams = {}
		for k = 1, segments do
			local f0, f1 = (k - 1) / segments, k / segments
			local beam = Instance.new("Beam")
			beam.Attachment0 = points[k]
			beam.Attachment1 = points[k + 1]
			beam.Color = ColorSequence.new(Color3.new(1, 1, 1):Lerp(color, f0), Color3.new(1, 1, 1):Lerp(color, f1))
			beam.LightEmission = 1
			beam.Width0 = 0.25 - 0.13 * f0
			beam.Width1 = 0.25 - 0.13 * f1
			beam.Segments = 1
			beam.FaceCamera = true
			beam.Transparency = NumberSequence.new(0)
			beam.Parent = points[k]
			table.insert(beams, beam)
		end
		table.insert(rigs, { Points = points, Beams = beams })
	end
	local running = true
	task.spawn(function()
		while running do
			for _, rig in rigs do
				local p0 = center + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 1), rng:NextNumber(-1, 1)).Unit * r
				local p1 = center + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 1), rng:NextNumber(-1, 1)).Unit * r
				local axis = p1 - p0
				local length = axis.Magnitude
				local side = axis:Cross(Vector3.yAxis)
				if side.Magnitude < 1e-3 then
					side = axis:Cross(Vector3.xAxis)
				end
				side = if side.Magnitude > 1e-3 then side.Unit else Vector3.xAxis
				local up = if length > 1e-3 then axis:Cross(side).Unit else Vector3.yAxis
				local bow = rng:NextNumber(-0.3, 0.3) * length
				local jag = length * 0.12
				for k, point in rig.Points do
					local f = (k - 1) / segments
					local p = p0 + axis * f
					if k > 1 and k <= segments then
						p += side * (math.sin(f * math.pi) * bow + rng:NextNumber(-jag, jag)) + up * rng:NextNumber(-jag, jag)
					end
					point.WorldPosition = p
				end
				-- Reduce Motion: no on/off flicker, and a slower crackle below
				local visible = calm or rng:NextNumber() > 0.25
				for _, beam in rig.Beams do
					beam.Enabled = visible
				end
			end
			task.wait(if calm then 0.25 else 0.06)
		end
		for _, rig in rigs do
			for _, point in rig.Points do
				point:Destroy()
			end
		end
	end)
	return function()
		if not running then
			return
		end
		running = false
		-- gone at once, not on the next tick
		for _, rig in rigs do
			for _, beam in rig.Beams do
				beam.Enabled = false
			end
		end
	end
end

-- Projects a world position onto the effects layer.
function Effects.ToScreen(position: Vector3): (Vector2, boolean)
	local point, visible = workspace.CurrentCamera:WorldToViewportPoint(position)
	return Vector2.new(point.X, point.Y), visible and point.Z > 0
end

-- Center of a GUI object in effects-layer coordinates (or in `relativeTo`'s,
-- e.g. another full-screen gui). Every AbsolutePosition is measured from the
-- same origin (below the top bar, whatever IgnoreGuiInset says), so taking
-- the layer's own AbsolutePosition off maps it exactly.
function Effects.GuiCenter(object: GuiObject, relativeTo: GuiBase2d?): Vector2
	local space: GuiBase2d = relativeTo or Effects.Layer()
	return object.AbsolutePosition + object.AbsoluteSize / 2 - space.AbsolutePosition
end

return Effects
