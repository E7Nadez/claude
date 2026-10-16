-- "Classic Mode": the fast 2D shop window. Dark glassmorphism, category tabs
-- with a liquid indicator, responsive grid of item cards with rarity colors,
-- animated buy buttons, details/confirm modal, open/close choreography.
-- Premium touches: drifting bokeh, shimmering border, vignette, soft card
-- shadows, parallax tilt, holo foil / sparkles / light rays on rare cards,
-- click ripples, call-to-action glints, purchase stamps and card-flip reveals.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Shop = require(Shared.Definitions.Shop)
local Rarities = require(Shared.Definitions.Rarities)
local Currencies = require(Shared.Definitions.Currencies)
local Upgrades = require(Shared.Definitions.Upgrades)
local Boosts = require(Shared.Definitions.Boosts)
local Capsules = require(Shared.Definitions.Capsules)
local Format = require(Shared.Util.Format)
local DayNight = require(Shared.Util.DayNight)
local Trove = require(Shared.Util.Trove)

local Theme = require(script.Parent.UI.Theme)
local UI = require(script.Parent.UI.Components)
local UIFx = require(script.Parent.UI.UIFx)
local Audio = require(script.Parent.Audio)
local Effects = require(script.Parent.Effects)
local Sequences = require(Shared.Definitions.Sequences)

local ClassicShop = {}
ClassicShop.__index = ClassicShop

local STATE_BADGES = {
	Owned = { "OWNED", Theme.Colors.Success },
	Equipped = { "EQUIPPED", Theme.Colors.Accent },
	Locked = { "🔒", Theme.Colors.Locked },
	NightOnly = { "🌙 NIGHT", Color3.fromRGB(140, 150, 255) },
	MaxLevel = { "MAX", Theme.Colors.Gold },
	Claimed = { "CLAIMED", Theme.Colors.Locked },
	Unavailable = { "SOON", Theme.Colors.Locked },
}

local FADE_MARGIN = 24 -- room around the window inside the fade group (border stroke, zoom overshoot)
local CONTENT_PAD_TOP = 14 -- hovered top-row cards lift 6 px; keep their border and halo inside the clip
local CONTENT_PAD_BOTTOM = 8
local CONTENT_PAD_SIDE = 8
local MIN_CARD_HEIGHT = 176 -- shorter cards push the subtitle into the Buy button
local NARROW_CARD = 190 -- below this width a state badge would overlap the rarity tag

-- Card bodies are centre-anchored so every UIScale (cascade, press, pops) pivots on the middle.
local function bodyPosition(x: number, y: number): UDim2
	return UDim2.new(0.5, x, 0.5, y)
end

-- UIFx.Foil / UIFx.Rays start endless tweens without returning them. Playing another tween
-- on the same property cancels the running one, so this stops (or freezes) such a loop.
local function stopLoop(instance: Instance?, property: string)
	if instance and instance.Parent then
		TweenService:Create(instance, TweenInfo.new(0), { [property] = (instance :: any)[property] }):Play()
	end
end

-- Fades a whole subtree out together (short-lived overlays; no CanvasGroup needed).
local function fadeOut(root: Instance, info: TweenInfo)
	for _, object in root:GetDescendants() do
		if object:IsA("TextLabel") or object:IsA("TextButton") then
			UI.Tween(object, info, { TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1 })
		elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then
			UI.Tween(object, info, { ImageTransparency = 1, BackgroundTransparency = 1 })
		elseif object:IsA("GuiObject") then
			UI.Tween(object, info, { BackgroundTransparency = 1 })
		elseif object:IsA("UIStroke") then
			UI.Tween(object, info, { Transparency = 1 })
		end
	end
end

-- Periodic glint across the letters of a title (a gradient band on a copy of the text,
-- so it never shows on the empty part of the label box). Returns a stop function.
local function titleGlint(label: TextLabel): () -> ()
	local glint = UI.Label({
		Name = "Glint",
		Text = label.Text,
		Size = UDim2.fromOffset(0, label.Size.Y.Offset),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = label.FontFace,
		TextSize = label.TextSize,
		TextTruncate = Enum.TextTruncate.None,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = label.ZIndex + 1,
		Parent = label,
	})
	local gradient = UI.Gradient({ Color3.new(1, 1, 1) }, 20, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 1),
		NumberSequenceKeypoint.new(0.5, 0.15),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 1),
	}))
	gradient.Offset = Vector2.new(-1, 0)
	gradient.Parent = glint
	local running = true
	task.spawn(function()
		task.wait(0.9)
		while running and glint.Parent do
			gradient.Offset = Vector2.new(-1, 0)
			UI.Tween(gradient, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Offset = Vector2.new(1, 0) })
			task.wait(5 + math.random() * 1.5)
		end
	end)
	return function()
		running = false
		glint:Destroy()
	end
end

function ClassicShop.new(deps)
	local self = setmetatable({}, ClassicShop)
	self.Deps = deps -- { ClientData, Modal, Hud }
	self.IsOpen = false
	self.Category = Shop.Categories[1].Id
	self.Cards = {}
	self.Trove = Trove.new()
	self.CardTrove = Trove.new()
	self.VisibilityToken = 0
	self.IndicatorTweens = {} :: { Tween }
	self.FadeTween = nil :: Tween?
	self.TabScrollTween = nil :: Tween?
	self.ActiveReveal = nil :: { Cancel: (boolean) -> () }?
	self.NarrowCards = false
	self:_build()
	deps.ClientData.Changed:Connect(function()
		if self.IsOpen then
			self:_refreshCards()
			self:_refreshHeader()
		end
	end)
	return self
end

function ClassicShop:_build()
	local gui = UI.new("ScreenGui", {
		Name = "ClassicShop",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = Theme.Layers.Classic,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	self.Gui = gui

	self.Backdrop = UI.new("TextButton", {
		Name = "Backdrop",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Backdrop,
		BackgroundTransparency = 1,
		Selectable = false,
		Parent = gui,
	})
	self.Backdrop.Activated:Connect(function()
		self:Close()
	end)
	self.VignetteFrame = UIFx.Vignette(self.Backdrop, 0.6)

	local holder = UI.new("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.86, 0.84),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(1120, 720), MinSize = Vector2.new(320, 280), Parent = holder })
	self.Holder = holder
	self.HolderRest = UDim2.fromScale(0.5, 0.52)

	-- The window lives in this group only while it fades in or out, so all of its content
	-- fades together; at rest it renders directly (sharp text, no group texture).
	self.Fader = UI.new("CanvasGroup", {
		Name = "Fader",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, FADE_MARGIN * 2, 1, FADE_MARGIN * 2),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
		Parent = holder,
	})

	local window = UI.Glass({
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.08,
		Active = true,
		Parent = holder,
	})
	self.Window = window

	-- Slowly rotating gradient on the border = shimmering glass edge
	local windowStroke = window:FindFirstChild("Stroke") :: UIStroke
	windowStroke.Transparency = 0.55
	windowStroke.Thickness = 1.6
	local borderGradient = UI.Gradient(ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Colors.Accent),
		ColorSequenceKeypoint.new(0.35, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.5, Theme.Colors.AccentAlt),
		ColorSequenceKeypoint.new(0.75, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Theme.Colors.Accent),
	}), 0)
	borderGradient.Parent = windowStroke
	-- Paused while the shop is hidden (see Close).
	self.BorderTween = TweenService:Create(borderGradient, TweenInfo.new(8, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 })

	-- Drifting bokeh behind everything inside the window
	self.BokehLayer = UI.new("Frame", {
		Name = "BokehLayer",
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 1, -16),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 0,
		Parent = window,
	})

	-- Animated accent line along the top edge
	local accent = UI.new("Frame", {
		Name = "Accent",
		Size = UDim2.new(1, -40, 0, 3),
		Position = UDim2.fromOffset(20, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = window,
	}, { UI.Corner(Theme.Radius.Pill) })
	self.Accent = accent
	local accentGradient = UI.Gradient({ Theme.Colors.Accent, Theme.Colors.AccentAlt }, 0)
	accentGradient.Parent = accent
	self.AccentTween = TweenService:Create(accentGradient, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Offset = Vector2.new(0.4, 0) })

	-- Header
	local header = UI.new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 70), BackgroundTransparency = 1, Parent = window })
	-- Sized to the word so the title glint only crosses the letters.
	self.Title = UI.Label({
		Text = "SHOP",
		Position = UDim2.fromOffset(24, 12),
		Size = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = Theme.Fonts.Title,
		TextSize = 30,
		TextTruncate = Enum.TextTruncate.None,
		Parent = header,
	})
	UI.Gradient({ Color3.new(1, 1, 1), Color3.fromRGB(190, 200, 255) }, 90).Parent = self.Title
	self.Header = header
	self.Subtitle = UI.Label({
		Text = "Classic Mode",
		Position = UDim2.fromOffset(24, 44),
		Size = UDim2.fromOffset(320, 18),
		TextSize = 14,
		TextColor3 = Theme.Colors.SubText,
		Parent = header,
	})
	-- Right-centre anchor: the entrance zoom grows the pills out of the close-button side.
	local balance = UI.new("Frame", {
		Name = "Balance",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -74, 0, 35),
		Size = UDim2.fromOffset(420, 38),
		BackgroundTransparency = 1,
		Parent = header,
	}, { UI.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
	self.Balance = balance
	self.BalanceLabels = {}
	for i, id in Currencies.Stored do
		local currency = Currencies.Get(id)
		local pill = UI.new("Frame", {
			Name = id,
			Size = UDim2.fromOffset(0, 34),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Theme.Colors.PanelLight,
			BackgroundTransparency = 0.2,
			LayoutOrder = i,
			Visible = id == "Coins",
			Parent = balance,
		}, { UI.Corner(Theme.Radius.Pill), UI.Padding(0, 12), UI.List(Enum.FillDirection.Horizontal, 6, nil, Enum.VerticalAlignment.Center) })
		UI.Label({ Text = currency and currency.Glyph or "", Size = UDim2.fromOffset(22, 22), TextScaled = true, LayoutOrder = 1, Parent = pill })
		local label = UI.Label({
			Text = "0",
			Size = UDim2.fromOffset(0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			FontFace = Theme.Fonts.Numbers,
			TextSize = 20,
			TextColor3 = currency and currency.Color:Lerp(Color3.new(1, 1, 1), 0.3) or Theme.Colors.Text,
			LayoutOrder = 2,
			Parent = pill,
		})
		label.TextTruncate = Enum.TextTruncate.None
		self.BalanceLabels[id] = { Pill = pill, Label = label, Shown = -1, Color = label.TextColor3 }
	end
	-- Centre-anchored so its open zoom and hover pop scale in place.
	local close = UI.Button({
		Name = "Close",
		Text = "✕",
		Style = "Ghost",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -38, 0, 36),
		Size = UDim2.fromOffset(44, 44),
		Radius = Theme.Radius.Pill,
		TextSize = 20,
		Parent = header,
		OnClick = function()
			self:Close()
		end,
	})
	self.CloseButton = close
	-- Its hover sweep is cut by a square clip, which shows in the corners of the round button.
	local closeShine = close.Instance:FindFirstChild("Shine")
	if closeShine and closeShine:IsA("GuiObject") then
		closeShine.Visible = false
	end
	-- Spin the glyph, not the button: a rotated button stops clipping its children.
	close.Instance.MouseEnter:Connect(function()
		if not Effects.ReduceMotion() then
			UI.Tween(close.Label, Theme.Tween.Spring, { Rotation = 90 })
		end
	end)
	close.Instance.MouseLeave:Connect(function()
		UI.Tween(close.Label, Theme.Tween.Medium, { Rotation = 0 })
	end)

	-- Tabs: the strip scrolls sideways. The indicator lives in the same canvas, so it
	-- scrolls and clips with the tabs instead of floating outside the strip.
	local tabs = UI.new("ScrollingFrame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(16, 74),
		Size = UDim2.new(1, -32, 0, 50),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		Parent = window,
	})
	self.TabScroller = tabs
	local strip = UI.new("Frame", {
		Name = "Strip",
		Size = UDim2.fromOffset(0, 50),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = tabs,
	}, { UI.List(Enum.FillDirection.Horizontal, 8, nil, Enum.VerticalAlignment.Center), UI.Padding(4, 4) })
	self.TabStrip = strip
	self.Tabs = {}
	self.TabIndicator = UI.new("Frame", {
		Name = "Indicator",
		Size = UDim2.fromOffset(100, 3),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 4,
		Parent = tabs,
	}, { UI.Corner(Theme.Radius.Pill), UI.Gradient({ Theme.Colors.Accent, Theme.Colors.AccentAlt }, 0) })
	for i, category in Shop.Categories do
		-- No UIScale on tabs: they are list items, and scaling them shifts the row and
		-- throws off the indicator measurement. Hover/entrance use colour and fades.
		-- Each tab sits in a slot with a clip layer for its click ripple. A ripple parented to
		-- the auto-sized, padded tab itself would widen it (shifting the row), land 16 px off
		-- the cursor and flood the neighbouring tabs.
		local slot = UI.new("Frame", {
			Name = category.Id,
			Size = UDim2.fromOffset(0, 40),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Parent = strip,
		})
		local tab = UI.new("TextButton", {
			Name = "Button",
			Text = "",
			Size = UDim2.fromOffset(0, 40),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Theme.Colors.PanelLight,
			BackgroundTransparency = 0.4,
			Parent = slot,
		}, { UI.Corner(Theme.Radius.Pill), UI.Padding(0, 16) })
		local stroke = UI.Stroke(nil, 0.9)
		stroke.Parent = tab
		local text = UI.Label({
			Name = "Text",
			Text = category.Glyph .. "  " .. category.Name,
			Size = UDim2.fromOffset(0, 40),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = 16,
			TextTruncate = Enum.TextTruncate.None,
			TextColor3 = Theme.Colors.SubText,
			Parent = tab,
		})
		local rippleClip = UI.new("Frame", {
			Name = "RippleClip",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 2,
			Parent = slot,
		})
		tab.MouseEnter:Connect(function()
			if self.Category ~= category.Id then
				UI.Tween(tab, Theme.Tween.Fast, { BackgroundTransparency = 0.15 })
				UI.Tween(text, Theme.Tween.Fast, { TextColor3 = Theme.Colors.Text })
			end
		end)
		tab.MouseLeave:Connect(function()
			if self.Category ~= category.Id then
				UI.Tween(tab, Theme.Tween.Medium, { BackgroundTransparency = 0.4 })
				UI.Tween(text, Theme.Tween.Medium, { TextColor3 = Theme.Colors.SubText })
			end
		end)
		tab.Activated:Connect(function()
			UIFx.Ripple(rippleClip, Theme.Colors.Accent)
			self:SelectCategory(category.Id)
		end)
		self.Tabs[category.Id] = tab
	end

	-- Soft edge fades show that the strip scrolls when the tabs do not fit.
	local function edgeFade(right: boolean): Frame
		local fade = UI.new("Frame", {
			Name = if right then "FadeRight" else "FadeLeft",
			AnchorPoint = Vector2.new(if right then 1 else 0, 0),
			Position = if right then UDim2.new(1, -16, 0, 74) else UDim2.fromOffset(16, 74),
			Size = UDim2.fromOffset(40, 50),
			BackgroundColor3 = Theme.Colors.Panel,
			BackgroundTransparency = 1,
			ZIndex = 3,
			Parent = window,
		})
		UI.Gradient({ Color3.new(1, 1, 1) }, if right then 180 else 0, NumberSequence.new(0.05, 1)).Parent = fade
		return fade
	end
	self.TabFades = { Left = edgeFade(false), Right = edgeFade(true) }
	local fadeShown: { [Frame]: boolean } = {}
	local function showFade(fade: Frame, shown: boolean)
		if fadeShown[fade] ~= shown then
			fadeShown[fade] = shown
			UI.Tween(fade, Theme.Tween.Fast, { BackgroundTransparency = if shown then 0 else 1 })
		end
	end
	local function updateFades()
		local x = tabs.CanvasPosition.X
		showFade(self.TabFades.Left, x > 2)
		showFade(self.TabFades.Right, x < tabs.MaxCanvasPosition.X - 2)
	end
	for _, property in { "CanvasPosition", "MaxCanvasPosition", "AbsoluteCanvasSize", "AbsoluteWindowSize" } do
		tabs:GetPropertyChangedSignal(property):Connect(updateFades)
	end

	-- Grid
	local content = UI.new("ScrollingFrame", {
		Name = "Content",
		Position = UDim2.fromOffset(16, 132),
		Size = UDim2.new(1, -32, 1, -170),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.Colors.SubText,
		ScrollBarImageTransparency = 0.4,
		Parent = window,
	})
	UI.new("UIPadding", {
		PaddingTop = UDim.new(0, CONTENT_PAD_TOP),
		PaddingBottom = UDim.new(0, CONTENT_PAD_BOTTOM),
		PaddingLeft = UDim.new(0, CONTENT_PAD_SIDE),
		PaddingRight = UDim.new(0, CONTENT_PAD_SIDE),
		Parent = content,
	})
	self.Grid = UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(180, 240),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Parent = content,
	})
	self.Content = content
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_layoutGrid()
	end)
	self.Empty = UI.Label({
		Text = "Nothing here yet.",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(300, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.SubText,
		Visible = false,
		Parent = window,
	})

	self.Hint = UI.Label({
		Name = "Hint",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -40, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 13,
		TextColor3 = Theme.Colors.Muted,
		Parent = window,
	})

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if self.IsOpen then
				self:_applyLayout()
				self.Holder.Position = self.HolderRest
			end
		end)
	end
end

-- Positions the window and its sections for the current screen. This gui ignores the
-- top-bar inset (for the full-screen backdrop), so on phones the window keeps itself
-- clear of Roblox's top bar and uses a tighter header to leave room for a full card row.
function ClassicShop:_applyLayout()
	local compact = UI.IsCompact()
	if compact then
		local topLeft, bottomRight = GuiService:GetGuiInset()
		local side = math.max(topLeft.X, bottomRight.X)
		local top = topLeft.Y + 6
		local bottom = bottomRight.Y + 8
		self.HolderRest = UDim2.new(0.5, 0, 0.5, (top - bottom) / 2)
		self.Holder.Size = UDim2.new(0.96, -side * 2, 1, -(top + bottom))
	else
		self.HolderRest = UDim2.fromScale(0.5, 0.52)
		self.Holder.Size = UDim2.fromScale(0.86, 0.84)
	end
	local tabsY = if compact then 56 else 74
	local contentY = if compact then 108 else 132
	local bottom = if self.Hint.Text == "" then 12 else 38
	self.Subtitle.Visible = not compact
	self.TabScroller.Position = UDim2.fromOffset(16, tabsY)
	self.TabFades.Left.Position = UDim2.fromOffset(16, tabsY)
	self.TabFades.Right.Position = UDim2.new(1, -16, 0, tabsY)
	self.Content.Position = UDim2.fromOffset(16, contentY)
	self.Content.Size = UDim2.new(1, -32, 1, -(contentY + bottom))
end

-- Absolute sizes include the window's open/close zoom; divide it out to get layout units.
function ClassicShop:_uiScale(): number
	return math.max(UI.GetScale(self.Window).Scale, 0.01)
end

function ClassicShop:_layoutGrid()
	-- Unscaled size, so the grid does not reflow on every frame of the open/close zoom.
	local size = self.Content.AbsoluteSize / self:_uiScale()
	local width = size.X - CONTENT_PAD_SIDE * 2 - 6
	if width <= 0 or size.Y <= 0 then
		return
	end
	local minCell = if UI.IsCompact() then 150 else 176
	local columns = math.max(2, math.floor((width + 12) / (minCell + 12)))
	local cellWidth = math.floor((width - (columns - 1) * 12) / columns)
	local cellHeight = math.floor(cellWidth * 1.36)
	-- Short windows (phones in landscape): squash the card a little and add columns until
	-- a whole row, Buy button included, fits in view.
	local viewHeight = math.floor(size.Y - CONTENT_PAD_TOP - CONTENT_PAD_BOTTOM)
	if cellHeight > viewHeight then
		local fitHeight = math.max(viewHeight, MIN_CARD_HEIGHT)
		while math.floor(cellWidth * 1.24) > fitHeight and columns < 8 do
			columns += 1
			cellWidth = math.floor((width - (columns - 1) * 12) / columns)
		end
		cellHeight = math.clamp(fitHeight, math.floor(cellWidth * 1.24), math.floor(cellWidth * 1.36))
	end
	local cellSize = UDim2.fromOffset(cellWidth, cellHeight)
	if self.Grid.CellSize ~= cellSize then
		self.Grid.CellSize = cellSize
	end
	local narrow = cellWidth < NARROW_CARD
	if narrow ~= self.NarrowCards then
		self.NarrowCards = narrow
		for _, entry in self.Cards do
			entry.UpdateTag()
		end
	end
end

function ClassicShop:_moveIndicator(animate: boolean)
	local tab = self.Tabs[self.Category]
	if not tab then
		return
	end
	-- A direct set must not be overwritten by a stretch/settle tween that is still running.
	for _, tween in self.IndicatorTweens do
		tween:Cancel()
	end
	table.clear(self.IndicatorTweens)
	-- Measured in the strip's canvas, which is where the indicator lives.
	local scale = self:_uiScale()
	local pos = (tab.AbsolutePosition - self.TabStrip.AbsolutePosition) / scale
	local size = tab.AbsoluteSize / scale
	local x0 = pos.X + 14
	local width = math.max(size.X - 28, 10)
	local y = pos.Y + size.Y + 1
	local indicator = self.TabIndicator
	local previous = self.IndicatorRect
	self.IndicatorRect = Vector2.new(x0, width)
	if animate and previous then
		-- Liquid stretch: first span old + new tab, then snap onto the new one.
		local left = math.min(previous.X, x0)
		local right = math.max(previous.X + previous.Y, x0 + width)
		local stretch = TweenService:Create(indicator, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(left, y - 1),
			Size = UDim2.fromOffset(right - left, 5),
		})
		stretch.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				table.insert(self.IndicatorTweens, UI.Tween(indicator, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = UDim2.fromOffset(x0, y),
					Size = UDim2.fromOffset(width, 3),
				}))
			end
		end)
		table.insert(self.IndicatorTweens, stretch)
		stretch:Play()
	else
		indicator.Position = UDim2.fromOffset(x0, y)
		indicator.Size = UDim2.fromOffset(width, 3)
	end
end

-- Scrolls the tab strip so the given tab (e.g. picked with Q/E or LB/RB) is fully visible.
function ClassicShop:_scrollTabIntoView(tab: GuiObject)
	local scroller = self.TabScroller
	local scale = self:_uiScale()
	local left = (tab.AbsolutePosition.X - self.TabStrip.AbsolutePosition.X) / scale
	local right = left + tab.AbsoluteSize.X / scale
	local view = scroller.AbsoluteWindowSize.X / scale
	local current = scroller.CanvasPosition.X
	local target = current
	if left - 24 < current then
		target = left - 24
	elseif right + 24 > current + view then
		target = right + 24 - view
	end
	target = math.clamp(target, 0, math.max(scroller.MaxCanvasPosition.X, 0))
	if math.abs(target - current) >= 1 then
		if self.TabScrollTween then
			self.TabScrollTween:Cancel()
		end
		self.TabScrollTween = UI.Tween(scroller, Theme.Tween.Slow, { CanvasPosition = Vector2.new(target, scroller.CanvasPosition.Y) })
	end
end

-- The window sits in the fade group only during open/close transitions.
function ClassicShop:_setFading(fading: boolean)
	local window = self.Window
	local selected = GuiService.SelectedObject
	if fading then
		if window.Parent == self.Fader then
			return
		end
		self.Fader.Visible = true
		window.Size = UDim2.new(1, -FADE_MARGIN * 2, 1, -FADE_MARGIN * 2)
		window.Parent = self.Fader
	else
		if window.Parent == self.Holder then
			return
		end
		window.Size = UDim2.fromScale(1, 1)
		window.Parent = self.Holder
		self.Fader.Visible = false
	end
	-- Keep the gamepad selection across the reparent.
	if selected and GuiService.SelectedObject ~= selected and selected:IsDescendantOf(window) then
		GuiService.SelectedObject = selected
	end
end

function ClassicShop:_refreshHeader()
	local data = self.Deps.ClientData:Get()
	if not data then
		return
	end
	for id, entry in self.BalanceLabels do
		local value = data.Currencies[id] or 0
		entry.Pill.Visible = id == "Coins" or value > 0
		if entry.Shown ~= value then
			if entry.Shown < 0 then
				entry.Label.Text = Format.Abbreviate(value)
			else
				local delta = value - entry.Shown
				UI.CountTo(entry.Label, entry.Shown, value, 0.6)
				-- Flash the amount green/red; a scale pop would shift the right-aligned pill row.
				entry.Label.TextColor3 = entry.Color:Lerp(if delta > 0 then Theme.Colors.Success else Theme.Colors.Danger, 0.75)
				UI.Tween(entry.Label, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = entry.Color })
				if entry.Pill.Visible then
					UIFx.FloatText(Effects.Layer(), Effects.GuiCenter(entry.Pill) + Vector2.new(0, 24), (if delta > 0 then "+" else "-") .. Format.Abbreviate(math.abs(delta)), if delta > 0 then Theme.Colors.Success else Theme.Colors.Danger, 22)
				end
			end
			entry.Shown = value
		end
	end
	local night = DayNight.IsNight()
	self.Subtitle.Text = "Classic Mode" .. (if night then "  ·  🌙 Night deals are live!" else "")
end

-- Card --------------------------------------------------------------------------------

local function subtitleFor(item: Shop.ShopItem, data: any, clientData: any): string
	if item.Kind == "Vacuum" then
		local stats = clientData:EffectiveStats(item.RefId)
		return string.format("💪 %s  ⚡ %s", Format.Stat(stats.Power), Format.Stat(stats.Speed))
	elseif item.Kind == "Upgrade" then
		local upgrade = Upgrades.Get(item.RefId)
		local level = clientData:UpgradeLevel(item.RefId)
		return string.format("Lv %d / %d", level, if upgrade then upgrade.MaxLevel else 0)
	elseif item.Kind == "Boost" then
		local boost = Boosts.Get(item.RefId)
		local expires = data and data.Boosts[item.RefId] or 0
		local remaining = expires - workspace:GetServerTimeNow()
		if remaining > 0 then
			return "Active · " .. Format.Clock(remaining)
		end
		return if boost then "x" .. Format.Stat(boost.Multiplier) .. " · " .. Format.Duration(boost.Duration) else ""
	elseif item.Kind == "Capsule" then
		local capsule = Capsules.Get(item.RefId)
		if capsule then
			local best = capsule.Drops[#capsule.Drops]
			return "Best: " .. Format.Chance(best.Weight / 100)
		end
	elseif item.Kind == "CoinPack" then
		return "🪙 " .. Format.Abbreviate(Shop.CoinPackAmount(item.RefId, data))
	elseif item.Kind == "Trophy" then
		return "Boss Shop"
	elseif item.Kind == "Cosmetic" then
		return if item.Glyph == "🎨" then "Skin" else "Trail"
	elseif item.Kind == "DailyCrate" then
		return "1 per day"
	elseif item.Kind == "Gamepass" then
		local pass = Shop.GamepassById[item.RefId]
		local perk = pass and pass.Perk
		if perk and perk.Stat == "Express" then
			return "Skip cooldowns"
		elseif perk and perk.Bonus >= 1 then
			return string.format("%gx %s", 1 + perk.Bonus, perk.Stat)
		elseif perk then
			return string.format("+%d%% %s", math.round(perk.Bonus * 100), perk.Stat)
		end
		return "Permanent perk"
	end
	return item.Category
end

local function buttonTextFor(item: Shop.ShopItem, state: string, price: number): string
	if state == "Owned" then
		return if item.Kind == "Vacuum" or item.Kind == "Cosmetic" then "Equip" else "Owned"
	elseif state == "Equipped" then
		return "Equipped"
	elseif state == "Locked" then
		return "Locked"
	elseif state == "NightOnly" then
		return "At Night"
	elseif state == "MaxLevel" then
		return "Maxed"
	elseif state == "Claimed" then
		return "Tomorrow"
	elseif state == "Unavailable" then
		return "Soon"
	end
	return UI.CurrencyText(price, item.Currency)
end

function ClassicShop:_createCard(item: Shop.ShopItem, order: number)
	local deps = self.Deps
	local rarity = Rarities.Get(item.Rarity)
	local rank = rarity.Rank
	local trove = self.CardTrove
	local reduceMotion = Effects.ReduceMotion()
	local card = UI.new("TextButton", {
		Name = item.Id,
		Text = "",
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Selectable = false,
		Parent = self.Content,
	})
	local shadow = UIFx.Shadow(card, Theme.Radius.Medium, 6)
	local body = UI.Glass({
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = bodyPosition(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.PanelLight,
		BackgroundTransparency = 0.25,
		StrokeColor = rarity.Color,
		StrokeTransparency = 0.55,
		Radius = Theme.Radius.Medium,
		ZIndex = 1,
		Parent = card,
	})
	local tint = UI.new("Frame", {
		Name = "Tint",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		Parent = body,
	}, { UI.Corner(Theme.Radius.Medium) })
	UI.Gradient(Rarities.ColorSequence(rarity.Id), 135, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.82 - rank * 0.015),
		NumberSequenceKeypoint.new(1, 0.95),
	})).Parent = tint

	-- Icon with a soft rarity halo (and rotating rays for Legendary+)
	local iconHolder = UI.new("Frame", {
		Name = "IconHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 22),
		Size = UDim2.fromScale(0.48, 0.48),
		BackgroundTransparency = 1,
		Parent = body,
	})
	UI.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = iconHolder })
	local halo = UIFx.Glow(iconHolder, rarity.Color, 1.5, 0.6 + rank * 0.08)
	if rank >= 5 then
		local rays = UIFx.Rays(iconHolder, rarity.Color, { Count = 6, Speed = 10, Size = 1.9, Transparency = 0.72 })
		if reduceMotion then
			stopLoop(rays, "Rotation")
		else
			trove:Add(function()
				stopLoop(rays, "Rotation")
			end)
		end
	end
	local icon = UI.Icon({
		Glyph = item.Glyph,
		Rarity = item.Rarity,
		IconAssetId = item.IconAssetId,
		Size = UDim2.fromScale(1, 1),
		Parent = iconHolder,
	})
	local rarityTag = UI.RarityTag(item.Rarity, { Position = UDim2.fromOffset(8, 8), Size = UDim2.new(0.5, 0, 0, 16), Parent = body })
	local badge = UI.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Colors.Success,
		Visible = false,
		Parent = body,
	}, { UI.Corner(Theme.Radius.Pill), UI.Padding(0, 7) })
	local badgeLabel = UI.Label({ Text = "", Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, TextSize = 11, FontFace = Theme.Fonts.Title, Parent = badge })
	badgeLabel.TextTruncate = Enum.TextTruncate.None

	local name = UI.Label({
		Name = "Name",
		Text = item.Name,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.6, -4),
		Size = UDim2.new(1, -16, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Theme.Fonts.Title,
		TextScaled = true,
		Parent = body,
	})
	UI.new("UITextSizeConstraint", { MaxTextSize = 18, MinTextSize = 11, Parent = name })
	if rank >= 5 then
		UI.Gradient({ Color3.new(1, 1, 1), rarity.Color:Lerp(Color3.new(1, 1, 1), 0.35) }, 90).Parent = name
	end
	local sub = UI.Label({
		Name = "Sub",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.6, 18),
		Size = UDim2.new(1, -16, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 13,
		TextColor3 = Theme.Colors.SubText,
		FontFace = Theme.Fonts.Body,
		Parent = body,
	})

	-- Centre-anchored so its hover/press scale stays in place.
	local buy: UI.Button
	buy = UI.Button({
		Name = "Buy",
		Text = "",
		Style = "Gold",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.925, -10),
		Size = UDim2.new(1, -20, 0.15, 0),
		TextSize = 17,
		Parent = body,
		OnClick = function()
			if not reduceMotion then
				UI.Wiggle(icon, 12)
			end
			self:_showModal(item, body, buy.Instance)
		end,
	})
	trove:Add(buy)
	trove:Connect(buy.Instance.Activated, function()
		UIFx.Ripple(buy.Instance)
	end)
	-- Card click ripples clip to the card. The body itself must not clip: the hover halo
	-- and the purchase stamp are meant to overflow it.
	local rippleClip = UI.new("Frame", {
		Name = "RippleClip",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 5,
		Parent = body,
	})

	-- Rarity flourishes
	local stroke = body:FindFirstChild("Stroke") :: UIStroke
	if rank >= 4 then
		local foil = UIFx.Foil(body, item.Rarity, Theme.Radius.Medium, if rank >= 6 then 0.5 elseif rank == 5 then 0.38 else 0.26)
		local foilGradient = foil:FindFirstChildOfClass("UIGradient")
		trove:Add(function()
			stopLoop(foilGradient, "Offset")
		end)
	end
	local stopBreathe: (() -> ())? = nil
	local function breathe()
		if stopBreathe then
			stopBreathe()
		end
		stopBreathe = UIFx.Breathe(stroke, 0.15, 0.6, if rank >= 6 then 0.9 else 1.4)
	end
	if rank >= 5 then
		trove:Add(UIFx.Sparkles(body, rarity.Color, if rank >= 6 then 7 else 4))
		breathe()
	end
	if rank >= 6 and not reduceMotion then
		trove:Add(UIFx.Float(icon, 5, 1.4))
	end

	local entry = {
		Item = item,
		Card = card,
		Body = body,
		Shadow = shadow,
		Tint = tint,
		Badge = badge,
		BadgeLabel = badgeLabel,
		Sub = sub,
		Buy = buy,
		Icon = icon,
		IconHolder = iconHolder,
		LastState = nil,
		StopGlint = nil :: (() -> ())?,
		BodyTransparency = nil :: number?,
		Hovered = false,
		Celebrating = 0,
	}

	-- Hovered and celebrating cards draw above their neighbours (lift, pop, stamp).
	function entry.UpdateLayer()
		card.ZIndex = if entry.Celebrating > 0 then 3 elseif entry.Hovered then 2 else 1
	end

	-- On narrow cards a state badge would overlap the rarity tag; the badge wins.
	function entry.UpdateTag()
		rarityTag.Visible = not (badge.Visible and self.NarrowCards)
	end

	-- Hover: lift with a deeper shadow, brighter stroke, parallax (mouse only)
	local strokeRest = if rank >= 5 then 0.15 else 0.55
	local alive = true
	if not reduceMotion and UserInputService.MouseEnabled then
		-- maxRotation 0: a rotated card stops the Buy button from clipping its shine and ripple.
		trove:Add(UIFx.Tilt(card, { { iconHolder, 10 }, { name, 4 }, { sub, 3 } }, 0))
	end
	local pressed = false
	local releaseConnection: RBXScriptConnection? = nil
	local function release()
		if releaseConnection then
			releaseConnection:Disconnect()
			releaseConnection = nil
		end
		if pressed then
			pressed = false
			UI.Tween(UI.GetScale(body), Theme.Tween.Spring, { Scale = 1 })
		end
	end
	trove:Add(function()
		alive = false
		if releaseConnection then
			releaseConnection:Disconnect()
			releaseConnection = nil
		end
		if stopBreathe then
			stopBreathe()
			stopBreathe = nil
		end
	end)
	card.MouseEnter:Connect(function()
		-- Taps emulate MouseEnter without a reliable MouseLeave, so hover is mouse-only.
		if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then
			return
		end
		entry.Hovered = true
		entry.UpdateLayer()
		Audio.Play("Hover")
		UI.Tween(body, Theme.Tween.Fast, { Position = bodyPosition(0, -6) })
		UI.Tween(shadow, Theme.Tween.Fast, { Position = UDim2.new(0.5, 0, 0.5, 14), Size = UDim2.new(1, 6, 1, 6) })
		-- Pause the rare-card breathing; a competing tween would cancel it for good.
		if stopBreathe then
			stopBreathe()
			stopBreathe = nil
		end
		UI.Tween(stroke, Theme.Tween.Fast, { Transparency = 0.05 })
		UI.Tween(halo, Theme.Tween.Fast, { Size = UDim2.fromScale(1.85, 1.85) })
		if not reduceMotion then
			UI.Wiggle(icon, 8)
		end
	end)
	card.MouseLeave:Connect(function()
		release()
		if not entry.Hovered then
			return
		end
		entry.Hovered = false
		entry.UpdateLayer()
		UI.Tween(body, Theme.Tween.Medium, { Position = bodyPosition(0, 0) })
		UI.Tween(shadow, Theme.Tween.Medium, { Position = UDim2.new(0.5, 0, 0.5, 6), Size = UDim2.fromScale(1, 1) })
		local settle = UI.Tween(stroke, Theme.Tween.Medium, { Transparency = strokeRest })
		if rank >= 5 then
			settle.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed and alive and not entry.Hovered then
					breathe()
				end
			end)
		end
		UI.Tween(halo, Theme.Tween.Medium, { Size = UDim2.fromScale(1.5, 1.5) })
	end)
	-- Press squish, released wherever the press ends (off the card, or a drag-scroll).
	card.MouseButton1Down:Connect(function()
		pressed = true
		UI.Tween(UI.GetScale(body), Theme.Tween.Press, { Scale = 0.97 })
		if not releaseConnection then
			releaseConnection = UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					release()
				end
			end)
		end
	end)
	card.MouseButton1Up:Connect(release)
	card.Activated:Connect(function()
		Audio.Play("Click")
		UIFx.Ripple(rippleClip, rarity.Color)
		self:_showModal(item, body, buy.Instance)
	end)

	function entry.Refresh()
		local data = deps.ClientData:Get()
		local state = Shop.GetState(item, data, workspace:GetServerTimeNow(), DayNight.IsNight())
		local price = Shop.GetPrice(item, data)
		local affordable = Shop.CanAfford(item, data)
		buy:SetText(buttonTextFor(item, state, price))
		local style = "Gold"
		if item.Currency == "Robux" then
			style = "Success"
		elseif state == "Owned" then
			style = if item.Kind == "Vacuum" or item.Kind == "Cosmetic" then "Primary" else "Secondary"
		elseif state ~= "Available" then
			style = "Secondary"
		elseif not affordable then
			style = "Danger"
		end
		buy:SetStyle(style)
		local kind: string = item.Kind
		local equipable = kind == "Vacuum" or kind == "Cosmetic"
		buy:SetEnabled(state == "Available" or (state == "Owned" and equipable) or (state == "Equipped" and kind == "Cosmetic"))
		sub.Text = subtitleFor(item, data, deps.ClientData)
		local badgeInfo = STATE_BADGES[state]
		badge.Visible = badgeInfo ~= nil
		if badgeInfo then
			badgeLabel.Text = badgeInfo[1]
			badge.BackgroundColor3 = badgeInfo[2]
		end
		entry.UpdateTag()
		-- Tween state changes; the cascade entrance fades the glass in to this value.
		local bodyTransparency = if state == "Locked" or state == "Unavailable" then 0.45 else 0.25
		if entry.BodyTransparency ~= bodyTransparency then
			entry.BodyTransparency = bodyTransparency
			if entry.LastState then
				UI.Tween(body, Theme.Tween.Medium, { BackgroundTransparency = bodyTransparency })
			else
				body.BackgroundTransparency = bodyTransparency
			end
		end
		if entry.LastState and entry.LastState ~= state and (state == "Owned" or state == "Equipped") then
			UI.Pop(body, 0.12)
		end
		-- Call-to-action glint on items you can buy right now
		local wantsGlint = state == "Available" and affordable and item.Currency ~= "Robux"
		if wantsGlint and not entry.StopGlint then
			entry.StopGlint = UIFx.Shine(buy.Instance, 3.2 + order % 3 * 0.7, 0.22)
		elseif not wantsGlint and entry.StopGlint then
			entry.StopGlint()
			entry.StopGlint = nil
		end
		entry.LastState = state
	end
	trove:Add(function()
		if entry.StopGlint then
			entry.StopGlint()
		end
	end)

	entry.Refresh()
	return entry
end

function ClassicShop:_refreshCards()
	for _, entry in self.Cards do
		entry.Refresh()
	end
end

function ClassicShop:_clearCards()
	self.CardTrove:Clean()
	for _, entry in self.Cards do
		entry.Card:Destroy()
	end
	table.clear(self.Cards)
end

-- Gives the gamepad selection back to the grid (preferring `preferred`).
function ClassicShop:_restoreSelection(preferred: GuiObject?)
	if preferred and preferred.Selectable and preferred:IsDescendantOf(self.Gui) then
		GuiService.SelectedObject = preferred
		return
	end
	for _, entry in self.Cards do
		if entry.Buy.Instance.Selectable then
			GuiService.SelectedObject = entry.Buy.Instance
			return
		end
	end
end

function ClassicShop:_showModal(item: Shop.ShopItem, body: GuiObject, buy: GuiObject)
	local modal = self.Deps.Modal
	modal:Show(item, { Source = "Classic", FromGui = body })
	if not UserInputService.GamepadEnabled then
		return
	end
	-- ConfirmModal clears the gamepad selection when it closes; hand it back to this card.
	self.Trove:Add(task.spawn(function()
		while self.IsOpen and modal:IsOpen() do
			task.wait(0.1)
		end
		if self.IsOpen and GuiService.SelectedObject == nil then
			self:_restoreSelection(buy)
		end
	end))
end

function ClassicShop:SelectCategory(categoryId: string, silent: boolean?, entranceDelay: number?)
	local previousIndex, newIndex = 1, 1
	for i, category in Shop.Categories do
		if category.Id == self.Category then
			previousIndex = i
		end
		if category.Id == categoryId then
			newIndex = i
		end
	end
	local changed = self.Category ~= categoryId
	local direction = if newIndex >= previousIndex then 1 else -1
	local reduceMotion = Effects.ReduceMotion()
	self.Category = categoryId
	if not silent then
		Audio.Play("Tab")
	end
	for id, tab in self.Tabs do
		local active = id == categoryId
		UI.Tween(tab, Theme.Tween.Medium, {
			BackgroundTransparency = if active then 0 else 0.4,
			BackgroundColor3 = if active then Theme.Colors.PanelHover else Theme.Colors.PanelLight,
		})
		local text = tab:FindFirstChild("Text") :: TextLabel
		UI.Tween(text, Theme.Tween.Medium, { TextColor3 = if active then Theme.Colors.Text else Theme.Colors.SubText })
		if active and changed and not reduceMotion then
			UI.Wiggle(text, 6)
		end
	end
	task.defer(function()
		local tab = self.Tabs[categoryId]
		if tab and self.Category == categoryId then
			self:_moveIndicator(true)
			self:_scrollTabIntoView(tab)
		end
	end)

	self:_clearCards()
	self.Content.CanvasPosition = Vector2.zero

	local items = Shop.ItemsInCategory(categoryId)
	self.Empty.Visible = #items == 0
	local delayBase = entranceDelay or 0
	local slide = if reduceMotion then Vector2.new(0, 10) else Vector2.new(direction * 36, 26)
	for i, item in items do
		local entry = self:_createCard(item, i)
		table.insert(self.Cards, entry)
		-- Cascade in from the direction of travel. Each card stays hidden until its turn,
		-- then glass, content and shadow move in together.
		local body, shadow = entry.Body, entry.Shadow
		local bodyScale = UI.GetScale(body)
		local shadowScale = UI.GetScale(shadow)
		bodyScale.Scale = 0.88
		shadowScale.Scale = 0.88
		body.Visible = false
		body.Position = bodyPosition(slide.X, slide.Y)
		body.BackgroundTransparency = 1
		shadow.Visible = false
		shadow.Position = UDim2.new(0.5, slide.X, 0.5, 6 + slide.Y)
		task.delay(delayBase + math.min(i, 16) * 0.03, function()
			if not body.Parent then
				return
			end
			body.Visible = true
			shadow.Visible = true
			-- A card hovered before its turn keeps its lift.
			local move = TweenInfo.new(0.45, Enum.EasingStyle.Quint)
			UI.Tween(bodyScale, Theme.Tween.Spring, { Scale = 1 })
			UI.Tween(shadowScale, Theme.Tween.Spring, { Scale = 1 })
			UI.Tween(body, move, { Position = bodyPosition(0, if entry.Hovered then -6 else 0) })
			UI.Tween(shadow, move, { Position = UDim2.new(0.5, 0, 0.5, if entry.Hovered then 14 else 6) })
			UI.Tween(body, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = entry.BodyTransparency or 0.25 })
			-- Select once visible (hidden objects cannot hold the gamepad selection).
			if i == 1 and UserInputService.GamepadEnabled and self.IsOpen and not self.Deps.Modal:IsOpen() then
				GuiService.SelectedObject = entry.Buy.Instance
			end
		end)
	end
	self:_layoutGrid()
end

function ClassicShop:_cycleTab(direction: number)
	local index = 1
	for i, category in Shop.Categories do
		if category.Id == self.Category then
			index = i
		end
	end
	index = (index - 1 + direction) % #Shop.Categories + 1
	self:SelectCategory(Shop.Categories[index].Id)
end

function ClassicShop:Open(categoryId: string?)
	if self.IsOpen then
		if categoryId and categoryId ~= self.Category then
			self:SelectCategory(categoryId)
		end
		return
	end
	self.IsOpen = true
	self.VisibilityToken += 1
	local token = self.VisibilityToken
	-- Still enabled = a close is still fading out; continue from its current state.
	local resumed = self.Gui.Enabled
	self.Gui.Enabled = true
	Audio.Play("Open")
	local reduceMotion = Effects.ReduceMotion()

	local blur = Lighting:FindFirstChild("ShopBlur") :: BlurEffect?
	if not blur then
		local created = Instance.new("BlurEffect")
		created.Name = "ShopBlur"
		created.Size = 0
		created.Parent = Lighting
		blur = created
	end
	UI.Tween(blur :: BlurEffect, Theme.Tween.Slow, { Size = 14 })

	self.Backdrop.BackgroundTransparency = 1
	UI.Tween(self.Backdrop, Theme.Tween.Medium, { BackgroundTransparency = 0.5 })
	for _, edge in self.VignetteFrame:GetChildren() do
		if edge:IsA("Frame") then
			edge.BackgroundTransparency = 1
			UI.Tween(edge, Theme.Tween.Slow, { BackgroundTransparency = 0 })
		end
	end
	self.Hint.Text = if UserInputService.GamepadEnabled then "LB / RB  switch tabs  ·  B  close" elseif UserInputService.KeyboardEnabled then "Q / E  switch tabs  ·  Backspace  close" else ""
	self:_applyLayout()

	-- Window: zoom + fade as one group. Centre-anchored, so the zoom stays centred.
	local scale = UI.GetScale(self.Window)
	self:_setFading(true)
	if self.FadeTween then
		self.FadeTween:Cancel()
	end
	if not resumed then
		self.Fader.GroupTransparency = 1
		scale.Scale = 0.86
		self.Holder.Position = self.HolderRest + UDim2.fromScale(0, 0.04)
	end
	local fade = UI.Tween(self.Fader, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 0 })
	self.FadeTween = fade
	fade.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and self.FadeTween == fade then
			self.FadeTween = nil
			self:_setFading(false)
		end
	end)
	UI.Tween(scale, Theme.Tween.Open, { Scale = 1 })
	UI.Tween(self.Holder, Theme.Tween.Open, { Position = self.HolderRest })
	self.BorderTween:Play()
	self.AccentTween:Play()

	-- Choreography: accent line draws, header slides in, tabs fade in as a wave
	self.Accent.Size = UDim2.new(0, 0, 0, 3)
	UI.Tween(self.Accent, TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, 0.1), { Size = UDim2.new(1, -40, 0, 3) })
	self.Title.Position = UDim2.fromOffset(-10, 12)
	self.Title.TextTransparency = 1
	UI.Tween(self.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, 0.12), { Position = UDim2.fromOffset(24, 12), TextTransparency = 0 })
	self.Subtitle.TextTransparency = 1
	UI.Tween(self.Subtitle, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, 0.2), { TextTransparency = 0 })
	local closeScale = UI.GetScale(self.CloseButton.Instance)
	closeScale.Scale = 0
	self.CloseButton.Label.Rotation = if reduceMotion then 0 else -180
	UI.Tween(closeScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.25), { Scale = 1 })
	UI.Tween(self.CloseButton.Label, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.25), { Rotation = 0 })
	-- One zoom for the whole balance row (pills are list items; scaling each shifts the row).
	local balanceScale = UI.GetScale(self.Balance)
	balanceScale.Scale = 0.6
	UI.Tween(balanceScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.25), { Scale = 1 })
	if not reduceMotion then
		self.Trove:Add(UIFx.Bokeh(self.BokehLayer, { Theme.Colors.Accent, Theme.Colors.AccentAlt, Theme.Colors.Gold }, 8))
	end
	if not Effects.IsLow() then
		self.Trove:Add(titleGlint(self.Title))
	end

	-- Balances changed while the shop was closed snap silently; only live changes animate.
	for _, entry in self.BalanceLabels do
		entry.Shown = -1
	end
	self:_refreshHeader()
	self.IndicatorRect = nil
	self:SelectCategory(categoryId or self.Category, true, 0.28)
	-- After SelectCategory, so these staggered tweens win over its instant ones.
	for i, category in Shop.Categories do
		local tab = self.Tabs[category.Id]
		local active = category.Id == self.Category
		local text = tab:FindFirstChild("Text") :: TextLabel
		local tabStroke = tab:FindFirstChildOfClass("UIStroke")
		local info = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, 0.15 + i * 0.035)
		tab.BackgroundColor3 = if active then Theme.Colors.PanelHover else Theme.Colors.PanelLight
		tab.BackgroundTransparency = 1
		UI.Tween(tab, info, { BackgroundTransparency = if active then 0 else 0.4 })
		text.TextColor3 = if active then Theme.Colors.Text else Theme.Colors.SubText
		text.TextTransparency = 1
		text.Position = UDim2.fromOffset(0, if reduceMotion then 0 else 10)
		UI.Tween(text, info, { TextTransparency = 0, Position = UDim2.fromOffset(0, 0) })
		if tabStroke then
			tabStroke.Transparency = 1
			UI.Tween(tabStroke, info, { Transparency = 0.9 })
		end
	end
	-- Re-measure once the window zoom has settled (and the first layout surely exists).
	task.delay(0.45, function()
		local tab = self.Tabs[self.Category]
		if self.IsOpen and self.VisibilityToken == token and tab then
			self:_moveIndicator(false)
			self:_scrollTabIntoView(tab)
		end
	end)

	ContextActionService:BindActionAtPriority("ClassicShopNav", function(action, inputState, input)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if self.Deps.Modal:IsOpen() then
			return Enum.ContextActionResult.Pass
		end
		if input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Backspace then
			self:Close()
		elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonL1 then
			self:_cycleTab(-1)
		elseif input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonR1 then
			self:_cycleTab(1)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace, Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)

	-- live timers (boosts, crate countdown, night switch)
	self.Trove:Add(task.spawn(function()
		while self.IsOpen do
			task.wait(1)
			self:_refreshCards()
			self:_refreshHeader()
		end
	end))
end

function ClassicShop:Close()
	if not self.IsOpen then
		return
	end
	self.IsOpen = false
	self.VisibilityToken += 1
	local token = self.VisibilityToken
	self.Deps.Modal:Close(true)
	Audio.Play("Close")
	ContextActionService:UnbindAction("ClassicShopNav")
	-- A reveal that has not flipped yet still tells the player what they got.
	self:_cancelReveal(true)
	-- Bokeh, title glint and timers go out with the window, not before it.
	local trove = self.Trove
	self.Trove = Trove.new()
	local blur = Lighting:FindFirstChild("ShopBlur")
	if blur then
		UI.Tween(blur, Theme.Tween.Close, { Size = 0 })
	end
	self:_setFading(true)
	if self.FadeTween then
		self.FadeTween:Cancel()
	end
	self.FadeTween = UI.Tween(self.Fader, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 1 })
	UI.Tween(UI.GetScale(self.Window), Theme.Tween.Close, { Scale = 0.9 })
	UI.Tween(self.Backdrop, Theme.Tween.Close, { BackgroundTransparency = 1 })
	for _, edge in self.VignetteFrame:GetChildren() do
		if edge:IsA("Frame") then
			UI.Tween(edge, Theme.Tween.Close, { BackgroundTransparency = 1 })
		end
	end
	UI.Tween(self.Holder, Theme.Tween.Close, { Position = self.HolderRest + UDim2.fromScale(0, 0.04) })
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.Gui) then
		GuiService.SelectedObject = nil
	end
	task.delay(0.22, function()
		trove:Clean()
		if self.VisibilityToken ~= token then
			return
		end
		self.Gui.Enabled = false
		-- Nothing keeps animating while the shop is hidden; Open rebuilds the grid.
		self:_clearCards()
		self.BorderTween:Pause()
		self.AccentTween:Pause()
	end)
end

function ClassicShop:Toggle(categoryId: string?)
	if self.IsOpen then
		self:Close()
	else
		self:Open(categoryId)
	end
end

-- Waits (at most `timeout` s) until the confirm modal has closed and shrunk away.
function ClassicShop:_waitForModal(timeout: number)
	local modal = self.Deps.Modal
	if not modal:IsOpen() then
		return
	end
	local deadline = os.clock() + timeout
	while modal:IsOpen() and os.clock() < deadline do
		task.wait()
	end
	task.wait(0.22) -- ConfirmModal's shrink back into the card
end

-- Success effects on the purchased card: pop, flash, burst and a stamp.
-- Returns the buy button (coin flight target) when the card is visible. The effects wait
-- until the confirm modal (drawn above this window) no longer covers the card.
function ClassicShop:CelebrateFrom(itemId: string, stampText: string?, rarityId: string?)
	for _, entry in self.Cards do
		if entry.Item.Id == itemId then
			local rarity = Rarities.Get(rarityId or entry.Item.Rarity)
			task.spawn(function()
				self:_waitForModal(3)
				if self.IsOpen and entry.Body.Parent then
					self:_celebrateCard(entry, rarity, stampText)
				end
			end)
			return entry.Buy.Instance
		end
	end
	return nil
end

function ClassicShop:_celebrateCard(entry: any, rarity: any, stampText: string?)
	-- Above the neighbouring cards while the pop and the stamp overflow the card.
	entry.Celebrating += 1
	entry.UpdateLayer()
	task.delay(1.6, function()
		entry.Celebrating -= 1
		if entry.Card.Parent then
			entry.UpdateLayer()
		end
	end)
	UI.Pop(entry.Body, 0.15)
	if not Effects.ReduceMotion() then
		UI.Wiggle(entry.Icon, 16)
	end
	-- Rarity flash over the card. (Recolouring the tint does nothing visible: its gradient
	-- multiplies the base colour, which only darkens it.)
	local flash = UI.new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = rarity.Color:Lerp(Color3.new(1, 1, 1), 0.35),
		BackgroundTransparency = 0.35,
		ZIndex = 5,
		Parent = entry.Body,
	}, { UI.Corner(Theme.Radius.Medium) })
	local fade = UI.Tween(flash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
	fade.Completed:Connect(function()
		flash:Destroy()
	end)
	-- A capsule/crate reveal brings its own burst in the middle of the window.
	if not self.ActiveReveal then
		UIFx.Burst(Effects.Layer(), Effects.GuiCenter(entry.IconHolder), rarity.Color, 18, 110)
	end
	UIFx.Stamp(entry.Body, stampText or "PURCHASED!", rarity.Color:Lerp(Color3.new(1, 1, 1), 0.2))
end

-- Card-flip reveal in the middle of the window (capsule pets, crate loot).
-- spec = { Title, Subtitle, Glyph, Rarity, BackColor }
function ClassicShop:Reveal(spec: { [string]: any })
	if not self.IsOpen then
		return
	end
	-- One reveal at a time: a newer one replaces the previous.
	self:_cancelReveal(false)
	local rarity = Rarities.Get(spec.Rarity)
	local profile = Sequences.Get(spec.Rarity)
	local reduceMotion = Effects.ReduceMotion()
	local flipped = false
	local dismiss: () -> () = function() end
	local thread: thread? = nil
	local reveal = { Cancel = function(_: boolean) end }
	self.ActiveReveal = reveal

	-- Closing the shop (or a newer reveal) stops the sequence, so no flash, confetti or
	-- fanfare fires over the world. If the card had not flipped yet, a banner shows the result.
	reveal.Cancel = function(showResult: boolean)
		if thread and thread ~= coroutine.running() and coroutine.status(thread) ~= "dead" then
			pcall(task.cancel, thread)
		end
		dismiss()
		if showResult and not flipped and self.Deps.Hud then
			self.Deps.Hud:Banner({ Title = spec.Title or "Reward", Subtitle = spec.Subtitle, Rarity = spec.Rarity, Style = profile.Banner })
		end
	end

	thread = task.spawn(function()
		-- Let the confirm modal shrink away first so the whole reveal is on screen.
		self:_waitForModal(3)
		if self.ActiveReveal ~= reveal or not self.IsOpen then
			return
		end
		local overlay = UI.new("TextButton", {
			Name = "Reveal",
			Text = "",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.Colors.Backdrop,
			BackgroundTransparency = 1,
			ZIndex = 50,
			Parent = self.Window,
		}, { UI.Corner(Theme.Radius.Large) })
		UI.Tween(overlay, Theme.Tween.Medium, { BackgroundTransparency = 0.35 })
		local holder = UI.new("Frame", {
			Name = "CardHolder",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(230, 310),
			BackgroundTransparency = 1,
			ZIndex = 51,
			Parent = overlay,
		})
		local rays = UIFx.Rays(holder, rarity.Color, { Count = 10, Speed = 9, Size = 2.6, ZIndex = 51, Transparency = 0.6 })
		rays.Visible = false
		if reduceMotion then
			stopLoop(rays, "Rotation")
		end
		-- Centre-anchored: the zoom in/out and the wobble stay centred.
		local card = UI.Glass({
			Name = "Card",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = spec.BackColor or Theme.Colors.PanelLight,
			BackgroundTransparency = 0.05,
			StrokeColor = Color3.new(1, 1, 1),
			StrokeTransparency = 0.3,
			ZIndex = 52,
			Parent = holder,
		})
		local backLabel = UI.Label({
			Text = "?",
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextScaled = true,
			FontFace = Theme.Fonts.Title,
			TextColor3 = Color3.new(1, 1, 1),
			ZIndex = 53,
			Parent = card,
		})
		UI.Padding(70, 60).Parent = backLabel
		local scale = UI.GetScale(card)
		scale.Scale = 0.2
		UI.Tween(scale, Theme.Tween.Open, { Scale = 1 })
		Audio.Play("Open")

		local done = false
		local stopSparkles: (() -> ())? = nil
		local foilGradient: Instance? = nil
		-- Card, rays, text and sparkles fade and shrink out together; then the overlay goes.
		dismiss = function()
			if done then
				return
			end
			done = true
			if self.ActiveReveal == reveal then
				self.ActiveReveal = nil
			end
			if stopSparkles then
				stopSparkles()
			end
			UI.Tween(scale, Theme.Tween.Close, { Scale = 0.6 })
			UI.Tween(rays, Theme.Tween.Close, { Size = UDim2.fromScale(1.4, 1.4) })
			fadeOut(holder, Theme.Tween.Close)
			local fade = UI.Tween(overlay, Theme.Tween.Close, { BackgroundTransparency = 1 })
			fade.Completed:Connect(function()
				stopLoop(rays, "Rotation")
				stopLoop(foilGradient, "Offset")
				overlay:Destroy()
			end)
		end
		overlay.Activated:Connect(function()
			if flipped then
				dismiss()
			end
		end)

		task.wait(0.45)
		for i = 1, profile.CapsuleWobble do
			if reduceMotion then
				task.wait(0.18)
			else
				for _, angle in { 6 + i * 2, -(6 + i * 2), 0 } do
					UI.Tween(card, TweenInfo.new(0.06), { Rotation = angle })
					task.wait(0.06)
				end
			end
			card.BackgroundColor3 = (spec.BackColor or Theme.Colors.PanelLight):Lerp(rarity.Color, i / profile.CapsuleWobble)
			Audio.Play("Tick", { Speed = 1 + i * 0.25 })
			task.wait(0.12)
		end
		-- flip: squash to an edge, swap faces, unfold
		local squash = TweenService:Create(holder, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromOffset(4, 310) })
		squash:Play()
		squash.Completed:Wait()
		flipped = true
		backLabel:Destroy()
		card.Rotation = 0
		card.BackgroundColor3 = Theme.Colors.Panel
		local stroke = card:FindFirstChild("Stroke") :: UIStroke
		-- White base: the rarity gradient multiplies the stroke colour.
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Thickness = 3
		stroke.Transparency = 0
		UI.Gradient(Rarities.ColorSequence(rarity.Id), 45).Parent = stroke
		UI.Gradient(Rarities.ColorSequence(rarity.Id), 135, NumberSequence.new(0.7)).Parent = UI.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 52,
			Parent = card,
		}, { UI.Corner(Theme.Radius.Large) })
		-- The face content has a fixed size; it appears once the card has nearly unfolded
		-- instead of sitting on top of a 4 px sliver.
		local face = UI.new("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 54, Parent = card })
		local icon = UI.Icon({ Glyph = spec.Glyph or "✦", Rarity = spec.Rarity, Size = UDim2.fromOffset(120, 120), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 94), ZIndex = 54, Parent = face })
		UI.RarityTag(spec.Rarity, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 166), Size = UDim2.fromOffset(110, 20), ZIndex = 54, Parent = face })
		local title = UI.Label({ Text = spec.Title, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 196), Size = UDim2.fromOffset(206, 36), TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = Theme.Fonts.Title, ZIndex = 54, Parent = face })
		UI.Label({ Text = spec.Subtitle or "", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 236), Size = UDim2.fromOffset(206, 40), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextSize = 15, TextColor3 = Theme.Colors.SubText, FontFace = Theme.Fonts.Body, ZIndex = 54, Parent = face })
		if rarity.Rank >= 4 then
			foilGradient = UIFx.Foil(card, rarity.Id, Theme.Radius.Large, 0.4):FindFirstChildOfClass("UIGradient")
		end
		stopSparkles = UIFx.Sparkles(card, rarity.Color, 8)
		UI.Tween(holder, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(230, 310) })
		rays.Visible = true
		task.delay(0.1, function()
			if done then
				return
			end
			face.Visible = true
			UIFx.Typewriter(title, 0.5)
			if not reduceMotion then
				UI.Wiggle(icon, 14)
			end
		end)
		UIFx.Burst(Effects.Layer(), Effects.GuiCenter(holder), rarity.Color, 28, 180)
		Effects.UIConfetti(math.floor(profile.Confetti / 2), { rarity.Gradient[1], rarity.Gradient[2], Color3.new(1, 1, 1) })
		-- Reduce Motion: a much gentler full-screen flash.
		Effects.ScreenFlash(rarity.Color, (0.2 + rarity.Rank * 0.04) * (if reduceMotion then 0.35 else 1), 0.5)
		Audio.Play("Fanfare")
		task.wait(2.8)
		dismiss()
	end)
end

function ClassicShop:_cancelReveal(showResult: boolean)
	local reveal = self.ActiveReveal
	self.ActiveReveal = nil
	if reveal then
		reveal.Cancel(showResult)
	end
end

return ClassicShop
