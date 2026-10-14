-- Premium UI effects: click ripples, holographic foil, sparkles, particle
-- bursts, light rays, floating numbers, stamps, glints, parallax tilt, soft
-- shadows, drifting bokeh and typewriter text. Everything is cheap GUI work
-- (no textures needed) and scales down with Low Graphics.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Rarities = require(Shared.Definitions.Rarities)

local UIFx = {}

local lowGraphics = false

function UIFx.SetLowGraphics(enabled: boolean)
	lowGraphics = enabled
end

local function new(className: string, props: { [string]: any }, children: { Instance }?): any
	local instance = Instance.new(className)
	if instance:IsA("GuiObject") then
		instance.BorderSizePixel = 0
	end
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	instance.Parent = props.Parent
	return instance
end

local function corner(radius: UDim?): UICorner
	return new("UICorner", { CornerRadius = radius or UDim.new(1, 0) })
end

local function play(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	return tween
end

-- Material-style click ripple from the cursor (or the center on touch).
function UIFx.Ripple(button: GuiObject, color: Color3?)
	local size = button.AbsoluteSize
	local mouse = UserInputService:GetMouseLocation()
	local rel = mouse - button.AbsolutePosition
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled or rel.X < 0 or rel.Y < 0 or rel.X > size.X or rel.Y > size.Y then
		rel = size / 2
	end
	local diameter = math.max(size.X, size.Y) * 2.4
	local ripple = new("Frame", {
		Name = "Ripple",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(rel.X, rel.Y),
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = color or Color3.new(1, 1, 1),
		BackgroundTransparency = 0.55,
		ZIndex = button.ZIndex + 4,
		Parent = button,
	}, { corner() })
	local tween = play(ripple, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(diameter, diameter),
		BackgroundTransparency = 1,
	})
	tween.Completed:Connect(function()
		ripple:Destroy()
	end)
end

-- Animated holographic foil over a card (Epic+). Returns the overlay.
function UIFx.Foil(target: GuiObject, rarityId: string, radius: UDim?, strength: number?): Frame
	local rarity = Rarities.Get(rarityId)
	local overlay = new("Frame", {
		Name = "Foil",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1 - (strength or 0.35),
		ZIndex = target.ZIndex + 3,
		Active = false,
		Parent = target,
	}, { corner(radius or UDim.new(0, 14)) })
	local colors = {
		ColorSequenceKeypoint.new(0, rarity.Gradient[1]),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(120, 255, 240)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 140, 255)),
		ColorSequenceKeypoint.new(1, rarity.Gradient[2]),
	}
	local gradient = new("UIGradient", {
		Color = ColorSequence.new(colors),
		Rotation = 32,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.38, 1),
			NumberSequenceKeypoint.new(0.47, 0.35),
			NumberSequenceKeypoint.new(0.5, 0.1),
			NumberSequenceKeypoint.new(0.53, 0.35),
			NumberSequenceKeypoint.new(0.62, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1, 0),
		Parent = overlay,
	})
	play(gradient, TweenInfo.new(if rarityId == "Mythic" then 2.2 else 3.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 0.6), { Offset = Vector2.new(1, 0) })
	return overlay
end

-- Twinkling stars appearing inside a frame. Returns a stop function.
function UIFx.Sparkles(parent: GuiObject, color: Color3, maxActive: number?, glyph: string?): () -> ()
	local running = true
	local limit = if lowGraphics then math.max(1, math.floor((maxActive or 6) / 3)) else (maxActive or 6)
	local active = 0
	local rng = Random.new()
	task.spawn(function()
		while running and parent.Parent do
			if active < limit then
				active += 1
				local size = rng:NextInteger(9, 18)
				local star = new("TextLabel", {
					Name = "Sparkle",
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(rng:NextNumber(0.06, 0.94), rng:NextNumber(0.06, 0.94)),
					Size = UDim2.fromOffset(size, size),
					Text = glyph or "✦",
					TextScaled = true,
					TextColor3 = color:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0.2, 0.7)),
					TextTransparency = 1,
					Rotation = rng:NextNumber(-30, 30),
					ZIndex = parent.ZIndex + 5,
					Parent = parent,
				})
				local scale = new("UIScale", { Scale = 0.2, Parent = star })
				play(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 })
				play(star, TweenInfo.new(0.35), { TextTransparency = 0, Rotation = star.Rotation + 45 })
				task.delay(rng:NextNumber(0.5, 0.9), function()
					play(scale, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
					play(star, TweenInfo.new(0.4), { TextTransparency = 1, Rotation = star.Rotation + 45 })
					task.wait(0.42)
					star:Destroy()
					active -= 1
				end)
			end
			task.wait(rng:NextNumber(0.15, 0.45))
		end
	end)
	return function()
		running = false
	end
end

-- Radial burst of small streaks around an absolute screen point.
function UIFx.Burst(layer: Instance, center: Vector2, color: Color3, count: number?, distance: number?)
	local rng = Random.new()
	local n = if lowGraphics then math.floor((count or 16) / 2) else (count or 16)
	for i = 1, n do
		local angle = (i / n) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local dir = Vector2.new(math.cos(angle), math.sin(angle))
		local length = rng:NextInteger(8, 18)
		local streak = new("Frame", {
			Name = "Streak",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X, center.Y),
			Size = UDim2.fromOffset(length, 3),
			Rotation = math.deg(angle),
			BackgroundColor3 = if i % 3 == 0 then Color3.new(1, 1, 1) else color,
			ZIndex = 20,
			Parent = layer,
		}, { corner() })
		local far = center + dir * (distance or 90) * rng:NextNumber(0.6, 1.2)
		local tween = play(streak, TweenInfo.new(rng:NextNumber(0.4, 0.65), Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(far.X, far.Y),
			Size = UDim2.fromOffset(2, 2),
			BackgroundTransparency = 1,
		})
		tween.Completed:Connect(function()
			streak:Destroy()
		end)
	end
	-- expanding ring
	local ring = new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1,
		ZIndex = 19,
		Parent = layer,
	}, { corner() })
	local stroke = new("UIStroke", { Color = color, Thickness = 3, Transparency = 0.1, Parent = ring })
	local d = (distance or 90) * 1.6
	play(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quart), { Size = UDim2.fromOffset(d, d) })
	local fade = play(stroke, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Transparency = 1, Thickness = 0.5 })
	fade.Completed:Connect(function()
		ring:Destroy()
	end)
end

-- Rotating light rays behind something (banners, reveals). Returns the holder.
function UIFx.Rays(parent: GuiObject, color: Color3, options: { Count: number?, Speed: number?, Size: number?, ZIndex: number?, Transparency: number? }?): Frame
	local opts = options or {}
	local holder = new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(opts.Size or 2.4, opts.Size or 2.4),
		BackgroundTransparency = 1,
		ZIndex = opts.ZIndex or 0,
		Parent = parent,
	})
	new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = holder })
	local count = if lowGraphics then 5 else (opts.Count or 9)
	local base = opts.Transparency or 0.55
	for i = 1, count do
		local ray = new("Frame", {
			Name = "Ray",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.11, 0, 1, 0),
			Rotation = (i - 1) * 180 / count,
			BackgroundColor3 = color,
			ZIndex = opts.ZIndex or 0,
			Parent = holder,
		})
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.42, base),
				NumberSequenceKeypoint.new(0.5, 1),
				NumberSequenceKeypoint.new(0.58, base),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = ray,
		})
	end
	play(holder, TweenInfo.new(opts.Speed or 14, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 })
	return holder
end

-- "+1.2K" floating up from a point.
function UIFx.FloatText(layer: Instance, position: Vector2, text: string, color: Color3, size: number?)
	local label = new("TextLabel", {
		Name = "FloatText",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(position.X, position.Y),
		Size = UDim2.fromOffset(160, size or 28),
		Text = text,
		TextScaled = true,
		FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold),
		TextColor3 = color,
		TextStrokeTransparency = 0.4,
		ZIndex = 25,
		Parent = layer,
	})
	local scale = new("UIScale", { Scale = 0.4, Parent = label })
	play(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 })
	local tween = play(label, TweenInfo.new(1.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(position.X, position.Y - 56),
	})
	task.delay(0.6, function()
		play(label, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	tween.Completed:Connect(function()
		task.wait(0.05)
		label:Destroy()
	end)
end

-- Rubber-stamp slam ("PURCHASED!").
function UIFx.Stamp(parent: GuiObject, text: string, color: Color3, duration: number?)
	local label = new("TextLabel", {
		Name = "Stamp",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.9, 0.22),
		Text = text,
		TextScaled = true,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy),
		TextColor3 = color,
		TextTransparency = 1,
		Rotation = -14,
		ZIndex = parent.ZIndex + 10,
		Parent = parent,
	})
	new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 3, Transparency = 0.3, Parent = label })
	local scale = new("UIScale", { Scale = 3, Parent = label })
	play(scale, TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { Scale = 1 })
	play(label, TweenInfo.new(0.2), { TextTransparency = 0 })
	task.delay(duration or 1.1, function()
		play(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Scale = 1.3 })
		local fade = play(label, TweenInfo.new(0.25), { TextTransparency = 1 })
		fade.Completed:Connect(function()
			label:Destroy()
		end)
	end)
end

-- Periodic diagonal glint across a frame. Returns a stop function.
function UIFx.Shine(target: GuiObject, interval: number?, width: number?): () -> ()
	local running = true
	local glint = new("Frame", {
		Name = "Glint",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.6,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(width or 0.18, 0, 2.2, 0),
		Position = UDim2.fromScale(-0.4, 0.5),
		Rotation = 22,
		ZIndex = target.ZIndex + 6,
		Parent = target,
	}, {
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.15),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	local previousClip = target.ClipsDescendants
	target.ClipsDescendants = true
	task.spawn(function()
		while running and glint.Parent do
			glint.Position = UDim2.fromScale(-0.4, 0.5)
			play(glint, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Position = UDim2.fromScale(1.4, 0.5) })
			task.wait((interval or 3.5) + math.random() * 1.5)
		end
	end)
	return function()
		running = false
		glint:Destroy()
		target.ClipsDescendants = previousClip
	end
end

-- Parallax tilt while hovered: layers move with the cursor, the container
-- leans a little. layers = { { Object, Strength } }. Returns a cleanup.
function UIFx.Tilt(container: GuiObject, layers: { { any } }, maxRotation: number?): () -> ()
	local bases = {}
	for i, layer in layers do
		bases[i] = (layer[1] :: GuiObject).Position
	end
	local hovered = false
	local connection: RBXScriptConnection? = nil
	local function reset()
		for i, layer in layers do
			play(layer[1], TweenInfo.new(0.35, Enum.EasingStyle.Quint), { Position = bases[i] })
		end
		play(container, TweenInfo.new(0.35, Enum.EasingStyle.Quint), { Rotation = 0 })
	end
	local enter = container.MouseEnter:Connect(function()
		if lowGraphics or hovered then
			return
		end
		hovered = true
		connection = RunService.RenderStepped:Connect(function()
			local size = container.AbsoluteSize
			if size.X <= 0 then
				return
			end
			local mouse = UserInputService:GetMouseLocation()
			local m = (mouse - (container.AbsolutePosition + size / 2)) / size
			m = Vector2.new(math.clamp(m.X, -0.5, 0.5), math.clamp(m.Y, -0.5, 0.5))
			for i, layer in layers do
				local strength = layer[2]
				layer[1].Position = bases[i] + UDim2.fromOffset(m.X * strength, m.Y * strength)
			end
			container.Rotation = m.X * (maxRotation or 3)
		end)
	end)
	local leave = container.MouseLeave:Connect(function()
		hovered = false
		if connection then
			connection:Disconnect()
			connection = nil
		end
		reset()
	end)
	return function()
		enter:Disconnect()
		leave:Disconnect()
		if connection then
			connection:Disconnect()
		end
	end
end

-- Soft layered drop shadow behind `target` (inserted into `holder`).
-- Returns the shadow frame so callers can animate Offset/Transparency.
function UIFx.Shadow(holder: GuiObject, radius: UDim?, depth: number?): Frame
	local shadow = new("Frame", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, depth or 6),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 0,
		Parent = holder,
	})
	local layers = if lowGraphics then 2 else 4
	for i = 1, layers do
		new("Frame", {
			Name = "Layer",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, i * 6, 1, i * 6),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.82 + i * 0.035,
			ZIndex = 0,
			Parent = shadow,
		}, { corner(if radius then UDim.new(radius.Scale, radius.Offset + i * 3) else UDim.new(0, 14 + i * 3)) })
	end
	return shadow
end

-- Soft out-of-focus circles drifting behind content. Returns a stop function.
function UIFx.Bokeh(parent: GuiObject, colors: { Color3 }, count: number?): () -> ()
	local running = true
	local n = if lowGraphics then 3 else (count or 9)
	local rng = Random.new()
	local blobs = {}
	for i = 1, n do
		local size = rng:NextInteger(80, 220)
		local blob = new("Frame", {
			Name = "Bokeh",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(rng:NextNumber(0, 1), rng:NextNumber(0, 1)),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = colors[(i - 1) % #colors + 1],
			BackgroundTransparency = 0.9,
			ZIndex = 0,
			Parent = parent,
		}, { corner() })
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.6),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 0.6),
			}),
			Parent = blob,
		})
		table.insert(blobs, blob)
	end
	task.spawn(function()
		while running and parent.Parent do
			for _, blob in blobs do
				play(blob, TweenInfo.new(6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					Position = UDim2.fromScale(rng:NextNumber(0, 1), rng:NextNumber(0, 1)),
					BackgroundTransparency = rng:NextNumber(0.86, 0.94),
				})
			end
			task.wait(6)
		end
	end)
	return function()
		running = false
		for _, blob in blobs do
			blob:Destroy()
		end
	end
end

-- Dark screen-edge vignette (4 gradient edges).
function UIFx.Vignette(parent: Instance, strength: number?): Frame
	local holder = new("Frame", { Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1, Parent = parent })
	local s = strength or 0.55
	local edges = {
		{ UDim2.new(1, 0, 0.35, 0), UDim2.fromScale(0, 0), 90 },
		{ UDim2.new(1, 0, 0.35, 0), UDim2.fromScale(0, 0.65), 270 },
		{ UDim2.new(0.25, 0, 1, 0), UDim2.fromScale(0, 0), 0 },
		{ UDim2.new(0.25, 0, 1, 0), UDim2.fromScale(0.75, 0), 180 },
	}
	for _, edge in edges do
		local frame = new("Frame", { Size = edge[1], Position = edge[2], BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 1, Parent = holder })
		new("UIGradient", {
			Rotation = edge[3],
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1 - s), NumberSequenceKeypoint.new(1, 1) }),
			Parent = frame,
		})
	end
	return holder
end

-- Reveals a label's text grapheme by grapheme.
function UIFx.Typewriter(label: TextLabel, duration: number?)
	local total = utf8.len(label.ContentText or label.Text) or #label.Text
	label.MaxVisibleGraphemes = 0
	local value = Instance.new("NumberValue")
	value.Changed:Connect(function(v)
		label.MaxVisibleGraphemes = math.floor(v)
	end)
	local tween = play(value, TweenInfo.new(duration or 0.6, Enum.EasingStyle.Linear), { Value = total })
	tween.Completed:Connect(function()
		label.MaxVisibleGraphemes = -1
		value:Destroy()
	end)
end

-- Soft radial glow made of concentric circles (no textures needed).
function UIFx.Glow(parent: GuiObject, color: Color3, scale: number?, intensity: number?): Frame
	local holder = new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(scale or 1.5, scale or 1.5),
		BackgroundTransparency = 1,
		ZIndex = parent.ZIndex,
		Parent = parent,
	})
	local strength = intensity or 1
	for i, ring in { { 1, 0.9 }, { 0.78, 0.84 }, { 0.56, 0.78 }, { 0.36, 0.72 } } do
		new("Frame", {
			Name = "Ring" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(ring[1], ring[1]),
			BackgroundColor3 = color,
			BackgroundTransparency = 1 - (1 - ring[2]) * strength,
			ZIndex = parent.ZIndex,
			Parent = holder,
		}, { corner() })
	end
	return holder
end

-- Gentle idle float (icons on special cards). Returns a stop function.
function UIFx.Float(target: GuiObject, amplitude: number?, period: number?): () -> ()
	local base = target.Position
	local tween = play(target, TweenInfo.new(period or 1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Position = base - UDim2.fromOffset(0, amplitude or 4),
	})
	return function()
		tween:Cancel()
		target.Position = base
	end
end

-- Stroke glow that breathes. Returns a stop function.
function UIFx.Breathe(stroke: UIStroke, from: number, to: number, period: number?): () -> ()
	stroke.Transparency = from
	local tween = play(stroke, TweenInfo.new(period or 1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = to })
	return function()
		tween:Cancel()
	end
end

return UIFx
