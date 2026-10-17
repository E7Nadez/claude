-- UI kit for the shop: glass panels, animated buttons, count-up numbers,
-- icon placeholders, rarity tags, toggles. All built in code.

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Rarities = require(Shared.Definitions.Rarities)
local Currencies = require(Shared.Definitions.Currencies)
local Format = require(Shared.Util.Format)

local Theme = require(script.Parent.Theme)
local Audio = require(script.Parent.Parent.Audio)

local UI = {}

local GUI_DEFAULTS = {
	Frame = { BorderSizePixel = 0 },
	TextLabel = { BorderSizePixel = 0, BackgroundTransparency = 1 },
	TextButton = { BorderSizePixel = 0, AutoButtonColor = false },
	ImageLabel = { BorderSizePixel = 0, BackgroundTransparency = 1 },
	ImageButton = { BorderSizePixel = 0, AutoButtonColor = false },
	ScrollingFrame = { BorderSizePixel = 0 },
	CanvasGroup = { BorderSizePixel = 0 },
	ViewportFrame = { BorderSizePixel = 0, BackgroundTransparency = 1 },
	TextBox = { BorderSizePixel = 0 },
}

function UI.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local defaults = GUI_DEFAULTS[className]
	if defaults then
		for key, value in defaults do
			(instance :: any)[key] = value
		end
	end
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

-- Relative luminance (WCAG) of a colour, to pick legible text on it.
local function luminance(color: Color3): number
	local function linear(c: number): number
		return if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * linear(color.R) + 0.7152 * linear(color.G) + 0.0722 * linear(color.B)
end

-- Light two-colour fills (gold, mint, silver) wash out white text.
local function isLightFill(colors: { Color3 }): boolean
	return luminance(colors[1]:Lerp(colors[2] or colors[1], 0.5)) > 0.3
end

function UI.Corner(radius: UDim?): UICorner
	return UI.new("UICorner", { CornerRadius = radius or Theme.Radius.Medium })
end

function UI.Stroke(color: Color3?, transparency: number?, thickness: number?): UIStroke
	return UI.new("UIStroke", {
		Color = color or Theme.Colors.Stroke,
		Transparency = transparency or 0.86,
		Thickness = thickness or 1.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UI.Gradient(colors: ColorSequence | { Color3 }, rotation: number?, transparency: NumberSequence?): UIGradient
	local sequence: ColorSequence
	if typeof(colors) == "ColorSequence" then
		sequence = colors
	else
		local list = colors :: { Color3 }
		sequence = ColorSequence.new(list[1], list[2] or list[1])
	end
	return UI.new("UIGradient", {
		Color = sequence,
		Rotation = rotation or 90,
		Transparency = transparency or NumberSequence.new(0),
	})
end

function UI.Padding(all: number, horizontal: number?): UIPadding
	local h = horizontal or all
	return UI.new("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
	})
end

function UI.List(direction: Enum.FillDirection?, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return UI.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function UI.Label(props: { [string]: any }): TextLabel
	local p = {
		FontFace = Theme.Fonts.Bold,
		TextColor3 = Theme.Colors.Text,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for k, v in props do
		p[k] = v
	end
	return UI.new("TextLabel", p)
end

-- Dark frosted glass panel with subtle gradient, stroke and sheen.
function UI.Glass(props: { [string]: any }, children: { Instance }?): Frame
	local p = {
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.12,
	}
	for k, v in props do
		if k ~= "Radius" and k ~= "StrokeColor" and k ~= "StrokeTransparency" and k ~= "ClassName" then
			p[k] = v
		end
	end
	local frame = UI.new(props.ClassName or "Frame", p, children)
	UI.Corner(props.Radius or Theme.Radius.Large).Parent = frame
	local stroke = UI.Stroke(props.StrokeColor, props.StrokeTransparency or 0.84, 1.4)
	stroke.Name = "Stroke"
	stroke.Parent = frame
	UI.Gradient(
		{ Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 206, 230) },
		90,
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.08) })
	).Parent = frame
	local sheen = UI.new("Frame", {
		Name = "Sheen",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.94,
		Size = UDim2.fromScale(1, 0.45),
		ZIndex = (p.ZIndex or 1),
		Parent = frame,
	}, {
		UI.Corner(props.Radius or Theme.Radius.Large),
		UI.Gradient({ Color3.new(1, 1, 1), Color3.new(1, 1, 1) }, 90, NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})),
	})
	sheen.Active = false
	return frame
end

-- Tween helper that also returns the tween.
function UI.Tween(instance: Instance, info: TweenInfo, props: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

local function getScale(object: GuiObject): UIScale
	local scale = object:FindFirstChild("PopScale")
	if scale and scale:IsA("UIScale") then
		return scale
	end
	local created = Instance.new("UIScale")
	created.Name = "PopScale"
	created.Parent = object
	return created
end

UI.GetScale = getScale

-- Quick "pop" (scale up then spring back).
function UI.Pop(object: GuiObject, amount: number?)
	local scale = getScale(object)
	scale.Scale = 1 + (amount or 0.15)
	UI.Tween(scale, Theme.Tween.Spring, { Scale = 1 })
end

-- Icon wiggle.
function UI.Wiggle(object: GuiObject, degrees: number?)
	local d = degrees or 10
	task.spawn(function()
		for _, r in { d, -d * 0.8, d * 0.5, -d * 0.3, 0 } do
			UI.Tween(object, TweenInfo.new(0.07, Enum.EasingStyle.Sine), { Rotation = r })
			task.wait(0.07)
		end
	end)
end

-- Resting position and latest shake per object: a shake started mid-shake must
-- not take the shifted position as its origin (repeated taps would drift it).
local shakeOrigins: { [Instance]: UDim2 } = setmetatable({}, { __mode = "k" }) :: any
local shakeTokens: { [Instance]: {} } = setmetatable({}, { __mode = "k" }) :: any

-- Horizontal error shake.
function UI.Shake(object: GuiObject)
	local origin = shakeOrigins[object] or object.Position
	shakeOrigins[object] = origin
	local token = {}
	shakeTokens[object] = token
	task.spawn(function()
		for _, x in { 10, -8, 6, -4, 2, 0 } do
			if shakeTokens[object] ~= token then
				return
			end
			object.Position = origin + UDim2.fromOffset(x, 0)
			task.wait(0.035)
		end
		if shakeTokens[object] == token then
			object.Position = origin
			shakeOrigins[object] = nil
			shakeTokens[object] = nil
		end
	end)
end

-- Count a TextLabel from one number to another.
local counters: { [Instance]: { Value: NumberValue, Tween: Tween } } = setmetatable({}, { __mode = "k" }) :: any

function UI.CountTo(label: TextLabel, from: number, to: number, duration: number?, format: ((number) -> string)?, tick: boolean?)
	local fmt = format or Format.Abbreviate
	-- A newer count replaces a running one, which must not write its old target when it ends.
	local previous = counters[label]
	counters[label] = nil
	if previous then
		previous.Tween:Cancel()
		previous.Value:Destroy()
	end
	local value = Instance.new("NumberValue")
	value.Value = from
	local tween = TweenService:Create(value, TweenInfo.new(duration or 0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Value = to })
	local entry = { Value = value, Tween = tween }
	counters[label] = entry
	local lastText = ""
	local lastTick = 0
	value.Changed:Connect(function(v)
		local text = fmt(v)
		if text ~= lastText then
			lastText = text
			label.Text = text
			if tick and os.clock() - lastTick > 0.05 then
				lastTick = os.clock()
				Audio.Play("Tick")
			end
		end
	end)
	label.Text = fmt(from)
	tween.Completed:Connect(function()
		if counters[label] == entry then
			counters[label] = nil
			label.Text = fmt(to)
		end
		value:Destroy()
	end)
	tween:Play()
end

export type Button = {
	Instance: TextButton,
	Label: TextLabel,
	SetText: (Button, string) -> (),
	SetEnabled: (Button, boolean) -> (),
	SetStyle: (Button, string) -> (),
	SetLoading: (Button, boolean) -> (),
	Destroy: (Button) -> (),
	Enabled: boolean,
}

local SHINE_LEAN = math.tan(math.rad(20))

-- Animated button: hover lift + shine, press squish, spring release.
function UI.Button(props: { [string]: any }): Button
	local style = props.Style or "Primary"
	local colors = Theme.ButtonStyles[style] or Theme.ButtonStyles.Primary
	-- Hover, press and pop scale about the AnchorPoint: anchor the same rectangle at
	-- its centre so the button grows in place, not over its neighbours (a layout
	-- places its children itself, so those keep the caller's anchor).
	local size = props.Size or UDim2.fromOffset(160, 48)
	local position = props.Position or UDim2.new()
	local anchor = props.AnchorPoint or Vector2.zero
	local center = Vector2.new(0.5, 0.5)
	if anchor ~= center and not (props.Parent and props.Parent:FindFirstChildWhichIsA("UIGridStyleLayout")) then
		local dx, dy = center.X - anchor.X, center.Y - anchor.Y
		position += UDim2.new(size.X.Scale * dx, math.round(size.X.Offset * dx), size.Y.Scale * dy, math.round(size.Y.Offset * dy))
		anchor = center
	end
	local instance = UI.new("TextButton", {
		Name = props.Name or "Button",
		Text = "",
		Size = size,
		Position = position,
		AnchorPoint = anchor,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = if style == "Ghost" then 0.3 else 0,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Selectable = true,
		ClipsDescendants = true,
		Parent = props.Parent,
	})
	UI.Corner(props.Radius or Theme.Radius.Medium).Parent = instance
	local stroke = UI.Stroke(Color3.new(1, 1, 1), 0.75, 1.4)
	stroke.Parent = instance
	local gradient = UI.Gradient(colors, props.GradientRotation or 20)
	gradient.Parent = instance
	local scale = getScale(instance)

	-- Hover sweep: a gradient band on a full-size overlay with the button's corners.
	-- It stays inside the rounded shape (ClipsDescendants clips square and is
	-- ignored under rotated ancestors) and is fully transparent at rest.
	local shine = UI.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.75,
		Size = UDim2.fromScale(1, 1),
		ZIndex = (props.ZIndex or 1) + 1,
		Parent = instance,
	}, { UI.Corner(props.Radius or Theme.Radius.Medium) })
	local shineGradient = UI.Gradient({ Color3.new(1, 1, 1) }, 20, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.375, 1),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(0.625, 1),
		NumberSequenceKeypoint.new(1, 1),
	}))
	shineGradient.Offset = Vector2.new(-1, 0)
	shineGradient.Parent = shine

	local label = UI.Label({
		Name = "Label",
		Text = (if props.Glyph then props.Glyph .. "  " else "") .. (props.Text or ""),
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = props.TextSize or 18,
		FontFace = Theme.Fonts.Title,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = props.TextScaled or false,
		ZIndex = (props.ZIndex or 1) + 2,
		Parent = instance,
	})
	UI.new("UITextSizeConstraint", { MaxTextSize = props.TextSize or 18, MinTextSize = 10, Parent = label })
	label.TextScaled = true
	UI.Padding(4, 10).Parent = label
	-- Outlines the letters on light fills (see refreshLook).
	local textStroke = UI.new("UIStroke", {
		Name = "TextStroke",
		Thickness = 1.5,
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = label,
	})

	-- Loading spinner: a bright arc over a faint track, a square sized from the
	-- button height. The arc's gradient turns, so no GuiObject is rotated.
	local spinner = UI.new("Frame", {
		Name = "Spinner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.4, 0.4),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = (props.ZIndex or 1) + 3,
		Parent = instance,
	}, { UI.Corner(Theme.Radius.Pill), UI.Stroke(Color3.new(1, 1, 1), 0.78, 3) })
	local arcStroke = UI.Stroke(Color3.new(1, 1, 1), 0, 3)
	local arcGradient = UI.Gradient({ Color3.new(1, 1, 1) }, 0, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.12, 0),
		NumberSequenceKeypoint.new(0.3, 1),
		NumberSequenceKeypoint.new(1, 1),
	}))
	arcGradient.Parent = arcStroke
	UI.new("Frame", {
		Name = "Arc",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = (props.ZIndex or 1) + 3,
		Parent = spinner,
	}, { UI.Corner(Theme.Radius.Pill), arcStroke })

	local button = {} :: Button
	button.Instance = instance
	button.Label = label
	button.Enabled = props.Enabled ~= false
	local loading = false
	local hovered = false
	local spinConnection: RBXScriptConnection? = nil

	local function refreshLook()
		local active = button.Enabled and not loading
		local fill = if active then Theme.ButtonStyles[style] or colors else Theme.ButtonStyles.Disabled
		gradient.Color = ColorSequence.new(table.unpack(fill))
		label.TextTransparency = if active then 0 else 0.35
		-- White text on gold or mint needs a dark outline to stay readable.
		textStroke.Color = fill[#fill]:Lerp(Color3.new(0, 0, 0), 0.7)
		textStroke.Transparency = if isLightFill(fill) then 0.35 else 1
		instance.Selectable = active
	end

	local function hoverIn()
		if not button.Enabled or loading or hovered then
			return
		end
		hovered = true
		Audio.Play("Hover")
		UI.Tween(scale, Theme.Tween.Fast, { Scale = props.HoverScale or 1.05 })
		UI.Tween(stroke, Theme.Tween.Fast, { Transparency = 0.35 })
		-- The gradient stretches with the button: correct its angle so the band
		-- leans 20° on screen whatever the aspect ratio.
		local absolute = instance.AbsoluteSize
		if absolute.X > 0 and absolute.Y > 0 then
			shineGradient.Rotation = math.deg(math.atan(SHINE_LEAN * absolute.Y / absolute.X))
		end
		shineGradient.Offset = Vector2.new(-1, 0)
		UI.Tween(shineGradient, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Offset = Vector2.new(1, 0) })
	end

	local function hoverOut()
		if not hovered then
			return
		end
		hovered = false
		UI.Tween(scale, Theme.Tween.Medium, { Scale = 1 })
		UI.Tween(stroke, Theme.Tween.Medium, { Transparency = 0.75 })
	end

	instance.MouseEnter:Connect(hoverIn)
	instance.MouseLeave:Connect(hoverOut)
	instance.SelectionGained:Connect(hoverIn)
	instance.SelectionLost:Connect(hoverOut)
	instance.MouseButton1Down:Connect(function()
		if button.Enabled and not loading then
			UI.Tween(scale, Theme.Tween.Press, { Scale = 0.92 })
		end
	end)
	instance.MouseButton1Up:Connect(function()
		UI.Tween(scale, Theme.Tween.Spring, { Scale = if hovered then 1.05 else 1 })
	end)
	instance.Activated:Connect(function()
		if not button.Enabled or loading then
			Audio.Play("Error", { Volume = 0.4 })
			UI.Shake(instance)
			return
		end
		Audio.Play("Click")
		scale.Scale = 0.92
		UI.Tween(scale, Theme.Tween.Spring, { Scale = if hovered then 1.05 else 1 })
		if props.OnClick then
			task.spawn(props.OnClick)
		end
	end)

	function button.SetText(_: Button, text: string)
		label.Text = text
	end

	function button.SetEnabled(_: Button, enabled: boolean)
		button.Enabled = enabled
		refreshLook()
	end

	function button.SetStyle(_: Button, newStyle: string)
		style = newStyle
		refreshLook()
	end

	function button.SetLoading(_: Button, isLoading: boolean)
		loading = isLoading
		label.Visible = not isLoading
		spinner.Visible = isLoading
		if spinConnection then
			spinConnection:Disconnect()
			spinConnection = nil
		end
		if isLoading then
			spinConnection = RunService.RenderStepped:Connect(function(dt)
				arcGradient.Rotation = (arcGradient.Rotation + dt * 360) % 360
			end)
		else
			arcGradient.Rotation = 0
		end
		refreshLook()
	end

	local function stopSpin()
		if spinConnection then
			spinConnection:Disconnect()
			spinConnection = nil
		end
	end
	-- The button can be destroyed with its window while it is still loading.
	instance.Destroying:Connect(stopSpin)

	function button.Destroy(_: Button)
		stopSpin()
		instance:Destroy()
	end

	refreshLook()
	return button
end

-- Round icon placeholder: rarity gradient disc + glyph, or the real image.
function UI.Icon(props: { Glyph: string?, Rarity: string?, IconAssetId: number?, Size: UDim2?, Parent: Instance?, LayoutOrder: number?, Position: UDim2?, AnchorPoint: Vector2?, ZIndex: number? }): Frame
	local rarity = Rarities.Get(props.Rarity)
	local holder = UI.new("Frame", {
		Name = "Icon",
		Size = props.Size or UDim2.fromOffset(72, 72),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	UI.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = holder })
	local disc = UI.new("Frame", {
		Name = "Disc",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = props.ZIndex or 1,
		Parent = holder,
	}, {
		UI.Corner(UDim.new(0.5, 0)),
		UI.Gradient(Rarities.ColorSequence(rarity.Id), 135),
	})
	local stroke = UI.Stroke(rarity.Color, 0.2, 2)
	stroke.Parent = disc
	UI.new("Frame", {
		Name = "Inner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.82, 0.82),
		BackgroundColor3 = Color3.fromRGB(14, 16, 24),
		BackgroundTransparency = 0.25,
		ZIndex = (props.ZIndex or 1) + 1,
		Parent = disc,
	}, { UI.Corner(UDim.new(0.5, 0)) })
	if props.IconAssetId and props.IconAssetId ~= 0 then
		UI.new("ImageLabel", {
			Name = "Image",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.78, 0.78),
			Image = "rbxassetid://" .. props.IconAssetId,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = (props.ZIndex or 1) + 2,
			Parent = disc,
		})
	else
		UI.Label({
			Name = "Glyph",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.6, 0.6),
			Text = props.Glyph or rarity.Glyph,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Color3.new(1, 1, 1),
			ZIndex = (props.ZIndex or 1) + 2,
			Parent = disc,
		})
	end
	return holder
end

function UI.RarityTag(rarityId: string, props: { [string]: any }?): Frame
	local rarity = Rarities.Get(rarityId)
	local p = props or {}
	local tag = UI.new("Frame", {
		Name = "RarityTag",
		Size = p.Size or UDim2.fromOffset(84, 20),
		Position = p.Position or UDim2.new(),
		AnchorPoint = p.AnchorPoint or Vector2.zero,
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = p.LayoutOrder or 0,
		ZIndex = p.ZIndex or 1,
		Parent = p.Parent,
	}, {
		UI.Corner(Theme.Radius.Pill),
		UI.Gradient(Rarities.ColorSequence(rarity.Id), 0),
	})
	-- Light tiers (silver, green, gold) get dark ink tinted with the tier colour:
	-- small white text on them is unreadable.
	UI.Label({
		Text = string.upper(rarity.Name),
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 12,
		TextScaled = true,
		FontFace = Theme.Fonts.Title,
		TextColor3 = if isLightFill(rarity.Gradient) then rarity.Gradient[1]:Lerp(Color3.new(0, 0, 0), 0.78) else Theme.Colors.Text,
		ZIndex = (p.ZIndex or 1) + 1,
		Parent = tag,
	})
	local label = tag:FindFirstChildOfClass("TextLabel") :: TextLabel
	UI.new("UITextSizeConstraint", { MaxTextSize = 12, Parent = label })
	UI.Padding(2, 8).Parent = label
	return tag
end

function UI.CurrencyText(amount: number, currencyId: string): string
	local currency = Currencies.Get(currencyId)
	if currencyId == "Robux" then
		return "R$ " .. Format.Commas(amount)
	end
	return (if currency then currency.Glyph .. " " else "") .. Format.Abbreviate(amount)
end

-- On/off switch for settings.
function UI.Toggle(props: { Value: boolean, OnChanged: (boolean) -> (), Parent: Instance?, Position: UDim2?, AnchorPoint: Vector2?, LayoutOrder: number? }): { Instance: TextButton, Set: (boolean) -> () }
	local value = props.Value
	local track = UI.new("TextButton", {
		Name = "Toggle",
		Text = "",
		Size = UDim2.fromOffset(52, 28),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = if value then Theme.Colors.Success else Theme.Colors.PanelLight,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	}, { UI.Corner(Theme.Radius.Pill), UI.Stroke(nil, 0.8) })
	local knob = UI.new("Frame", {
		Name = "Knob",
		Size = UDim2.fromOffset(22, 22),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = if value then UDim2.new(1, -25, 0.5, 0) else UDim2.new(0, 3, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = track,
	}, { UI.Corner(Theme.Radius.Pill) })

	local function set(v: boolean)
		value = v
		UI.Tween(knob, Theme.Tween.Spring, { Position = if v then UDim2.new(1, -25, 0.5, 0) else UDim2.new(0, 3, 0.5, 0) })
		UI.Tween(track, Theme.Tween.Medium, { BackgroundColor3 = if v then Theme.Colors.Success else Theme.Colors.PanelLight })
	end

	track.Activated:Connect(function()
		Audio.Play("Click")
		set(not value)
		props.OnChanged(value)
	end)
	return { Instance = track, Set = set }
end

-- Viewport sizes the UI scales against (phones get a bigger relative size).
function UI.ScaleFor(viewport: Vector2): number
	local short = math.min(viewport.X, viewport.Y)
	return math.clamp(short / 760, 0.72, 1.25)
end

-- Attaches a UIScale that follows the viewport size.
function UI.AutoScale(gui: Instance): UIScale
	local camera = workspace.CurrentCamera
	local scale = Instance.new("UIScale")
	scale.Name = "AutoScale"
	scale.Parent = gui
	local function update()
		scale.Scale = UI.ScaleFor(camera.ViewportSize)
	end
	local connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	-- Lets go of the camera when the scale (or the gui holding it) is destroyed.
	scale.Destroying:Connect(function()
		connection:Disconnect()
	end)
	update()
	return scale
end

function UI.IsCompact(): boolean
	local size = workspace.CurrentCamera.ViewportSize
	return size.X < 900 or size.Y < 500
end

return UI
