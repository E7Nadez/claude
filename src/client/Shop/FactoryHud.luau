-- Slim, semi-transparent HUD on the screen edges while inside the factory:
-- zone quick-travel (left), contextual item panel (right on desktop, bottom on
-- phones), carousel arrows, back button and input hints.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Factory = require(Shared.Definitions.Factory)
local Rarities = require(Shared.Definitions.Rarities)
local Currencies = require(Shared.Definitions.Currencies)
local Format = require(Shared.Util.Format)
local Trove = require(Shared.Util.Trove)

local Theme = require(script.Parent.UI.Theme)
local UI = require(script.Parent.UI.Components)
local Audio = require(script.Parent.Audio)

local FactoryHud = {}
FactoryHud.__index = FactoryHud

export type ButtonSpec = { Id: string?, Text: string, Glyph: string?, Style: string?, Enabled: boolean?, OnClick: () -> () }
export type PanelSpec = {
	Title: string,
	Kicker: string?,
	Rarity: string?,
	Lines: { string }?,
	Price: { Amount: number, Currency: string, Affordable: boolean }?,
	Status: string?,
	Buttons: { ButtonSpec }?,
	Bars: { { Label: string, Fill: number, Ghost: number?, Value: string, Delta: number? } }?,
}

function FactoryHud.new(deps)
	local self = setmetatable({}, FactoryHud)
	self.Deps = deps -- { OnTravel(zoneId), OnClassic(), OnExit() }
	self.PanelTrove = Trove.new()
	self.Visible = false
	self.Buttons = {}

	local gui = UI.new("ScreenGui", {
		Name = "FactoryHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = Theme.Layers.FactoryHud,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	self.Gui = gui

	-- Zone navigation
	local nav = UI.new("Frame", {
		Name = "Nav",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 20),
		Size = UDim2.fromOffset(64, 520),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { UI.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	UI.AutoScale(nav)
	self.Nav = nav
	self.NavButtons = {}
	local function navButton(id: string, glyph: string, label: string, order: number, style: string?, onClick: () -> ())
		local holder = UI.new("Frame", { Name = id, Size = UDim2.fromOffset(56, 56), BackgroundTransparency = 1, LayoutOrder = order, Parent = nav })
		local button = UI.Button({
			Glyph = glyph,
			Text = "",
			Style = style or "Ghost",
			Size = UDim2.fromScale(1, 1),
			Radius = Theme.Radius.Large,
			TextSize = 26,
			Parent = holder,
			OnClick = onClick,
		})
		button.Label.Position = UDim2.fromOffset(0, -5)
		local caption = UI.Label({
			Text = string.upper(label),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -3),
			Size = UDim2.new(1, 0, 0, 11),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextScaled = true,
			FontFace = Theme.Fonts.Title,
			TextColor3 = Theme.Colors.SubText,
			ZIndex = 6,
			Parent = button.Instance,
		})
		UI.new("UITextSizeConstraint", { MaxTextSize = 10, Parent = caption })
		self.NavButtons[id] = button
		return button
	end
	for i, zone in Factory.Zones do
		navButton(zone.Id, zone.Glyph, zone.Name, i, nil, function()
			deps.OnTravel(zone.Id)
		end)
	end
	navButton("Classic", "🛒", "Quick", 50, "Gold", function()
		deps.OnClassic()
	end)
	navButton("Exit", "🚪", "Exit", 51, "Secondary", function()
		deps.OnExit()
	end)

	-- Back button
	local backHolder = UI.new("Frame", {
		Name = "Back",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(140, 54),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	UI.AutoScale(backHolder)
	self.BackHolder = backHolder
	self.BackButton = UI.Button({
		Text = "Back",
		Glyph = "←",
		Style = "Secondary",
		Size = UDim2.fromScale(1, 1),
		Radius = Theme.Radius.Pill,
		Parent = backHolder,
		OnClick = function()
			if self.OnBack then
				self.OnBack()
			end
		end,
	})

	-- Carousel
	local carousel = UI.new("Frame", {
		Name = "Carousel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(300, 66),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	UI.AutoScale(carousel)
	self.Carousel = carousel
	UI.Glass({ Size = UDim2.fromScale(1, 1), Radius = Theme.Radius.Pill, BackgroundTransparency = 0.3, Parent = carousel })
	self.PrevButton = UI.Button({
		Text = "◀",
		Style = "Primary",
		Size = UDim2.fromOffset(58, 58),
		Position = UDim2.fromOffset(4, 4),
		Radius = Theme.Radius.Pill,
		TextSize = 24,
		Parent = carousel,
		OnClick = function()
			if self.OnPrev then
				self.OnPrev()
			end
		end,
	})
	self.NextButton = UI.Button({
		Text = "▶",
		Style = "Primary",
		Size = UDim2.fromOffset(58, 58),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 4),
		Radius = Theme.Radius.Pill,
		TextSize = 24,
		Parent = carousel,
		OnClick = function()
			if self.OnNext then
				self.OnNext()
			end
		end,
	})
	self.CarouselLabel = UI.Label({
		Text = "1 / 8",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -140, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Theme.Fonts.Numbers,
		TextSize = 22,
		ZIndex = 4,
		Parent = carousel,
	})

	self.Hint = UI.Label({
		Name = "Hint",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -92),
		Size = UDim2.fromOffset(600, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.SubText,
		TextStrokeTransparency = 0.6,
		TextSize = 14,
		Parent = gui,
	})

	-- Context panel container
	self.PanelHolder = UI.new("Frame", {
		Name = "PanelHolder",
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	self.PanelScale = UI.AutoScale(self.PanelHolder)
	return self
end

function FactoryHud:SetVisible(visible: boolean)
	self.Visible = visible
	self.Gui.Enabled = visible
	if visible then
		self.Nav.Position = UDim2.new(0, -80, 0.5, 20)
		UI.Tween(self.Nav, Theme.Tween.Open, { Position = UDim2.new(0, 14, 0.5, 20) })
	end
end

function FactoryHud:SetNavVisible(visible: boolean)
	self.Nav.Visible = visible
end

function FactoryHud:HighlightZone(zoneId: string?)
	for id, button in self.NavButtons do
		if id ~= "Classic" and id ~= "Exit" then
			button:SetStyle(if id == zoneId then "Primary" else "Ghost")
		end
	end
end

function FactoryHud:ShowBack(onBack: () -> ())
	self.OnBack = onBack
	self.BackHolder.Visible = true
	UI.Pop(self.BackButton.Instance, 0.15)
end

function FactoryHud:HideBack()
	self.OnBack = nil
	self.BackHolder.Visible = false
end

function FactoryHud:ShowCarousel(onPrev: () -> (), onNext: () -> ())
	self.OnPrev = onPrev
	self.OnNext = onNext
	self.Carousel.Visible = true
	local compact = UI.IsCompact()
	self.Carousel.Position = if compact then UDim2.new(0.5, 0, 0, 70) else UDim2.new(0.5, 0, 1, -18)
	self.Carousel.AnchorPoint = if compact then Vector2.new(0.5, 0) else Vector2.new(0.5, 1)
end

function FactoryHud:SetCarouselLabel(text: string)
	self.CarouselLabel.Text = text
	UI.Pop(self.CarouselLabel, 0.12)
end

function FactoryHud:HideCarousel()
	self.OnPrev = nil
	self.OnNext = nil
	self.Carousel.Visible = false
end

function FactoryHud:SetHint(text: string?)
	if not text then
		self.Hint.Text = ""
		return
	end
	if UserInputService.GamepadEnabled then
		text = text:gsub("%[Keys%]", "D-Pad"):gsub("%[Confirm%]", "A"):gsub("%[Alt%]", "X"):gsub("%[Back%]", "B")
	elseif UserInputService.KeyboardEnabled then
		text = text:gsub("%[Keys%]", "← →"):gsub("%[Confirm%]", "Enter"):gsub("%[Alt%]", "T"):gsub("%[Back%]", "Backspace")
	else
		text = text:gsub("%[Keys%]", "Swipe"):gsub("%[Confirm%]", "Tap"):gsub("%[Alt%]", "Tap"):gsub("%[Back%]", "Back")
	end
	self.Hint.Text = text
end

-- Context panel --------------------------------------------------------------------------

function FactoryHud:ShowPanel(spec: PanelSpec)
	self.PanelTrove:Clean()
	local holder = self.PanelHolder
	local compact = UI.IsCompact()
	holder.Visible = true
	if compact then
		holder.AnchorPoint = Vector2.new(0.5, 1)
		holder.Position = UDim2.new(0.5, 0, 1, -12)
		holder.Size = UDim2.fromOffset(560, 200)
	else
		holder.AnchorPoint = Vector2.new(1, 0.5)
		holder.Position = UDim2.new(1, -96, 0.55, 0)
		holder.Size = UDim2.fromOffset(320, 440)
	end

	local rarity = Rarities.Get(spec.Rarity)
	local panel = UI.Glass({
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.22,
		StrokeColor = if spec.Rarity then rarity.Color else nil,
		StrokeTransparency = if spec.Rarity then 0.4 else 0.84,
		Parent = holder,
	})
	self.PanelTrove:Add(panel)
	local scale = UI.GetScale(panel)
	scale.Scale = 0.9
	UI.Tween(scale, Theme.Tween.Spring, { Scale = 1 })

	local column = UI.new("Frame", {
		Name = "Column",
		Position = UDim2.fromOffset(18, 16),
		Size = if compact then UDim2.new(0.58, -18, 1, -32) else UDim2.new(1, -36, 1, -32),
		BackgroundTransparency = 1,
		Parent = panel,
	}, { UI.List(Enum.FillDirection.Vertical, 6) })

	if spec.Rarity then
		UI.RarityTag(spec.Rarity, { LayoutOrder = 1, Parent = column })
	elseif spec.Kicker then
		UI.Label({ Text = string.upper(spec.Kicker), Size = UDim2.new(1, 0, 0, 16), TextSize = 13, TextColor3 = Theme.Colors.Accent, FontFace = Theme.Fonts.Title, LayoutOrder = 1, Parent = column })
	end
	local title = UI.Label({ Text = spec.Title, Size = UDim2.new(1, 0, 0, 30), FontFace = Theme.Fonts.Title, TextScaled = true, LayoutOrder = 2, Parent = column })
	UI.new("UITextSizeConstraint", { MaxTextSize = 26, Parent = title })

	if spec.Bars then
		for i, bar in spec.Bars do
			local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = 10 + i, Parent = column })
			UI.Label({ Text = bar.Label, Size = UDim2.new(0.34, 0, 1, 0), TextSize = 14, TextColor3 = Theme.Colors.SubText, Parent = row })
			local track = UI.new("Frame", { Position = UDim2.new(0.34, 0, 0.5, -4), Size = UDim2.new(0.4, 0, 0, 8), BackgroundColor3 = Theme.Colors.PanelLight, Parent = row }, { UI.Corner(Theme.Radius.Pill) })
			if bar.Ghost then
				UI.new("Frame", { Size = UDim2.fromScale(bar.Ghost, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.75, Parent = track }, { UI.Corner(Theme.Radius.Pill) })
			end
			local d = bar.Delta or 0
			local color = if math.abs(d) < 0.005 then Theme.Colors.Accent elseif d > 0 then Theme.Colors.Success else Theme.Colors.Danger
			local fill = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color, Parent = track }, { UI.Corner(Theme.Radius.Pill) })
			UI.Tween(fill, TweenInfo.new(0.5 + i * 0.07, Enum.EasingStyle.Quint), { Size = UDim2.fromScale(bar.Fill, 1) })
			UI.Label({ Text = bar.Value, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.25, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = color, FontFace = Theme.Fonts.Numbers, TextSize = 14, Parent = row })
		end
	end

	if spec.Lines then
		for i, line in spec.Lines do
			local label = UI.Label({
				Text = line,
				RichText = true,
				Size = UDim2.new(1, 0, 0, 18),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
				TextTruncate = Enum.TextTruncate.None,
				TextSize = 15,
				FontFace = Theme.Fonts.Body,
				TextColor3 = Theme.Colors.SubText,
				LayoutOrder = 30 + i,
				Parent = column,
			})
			label.TextYAlignment = Enum.TextYAlignment.Top
		end
	end

	if spec.Status then
		UI.Label({ Text = spec.Status, Size = UDim2.new(1, 0, 0, 20), TextSize = 15, TextColor3 = Theme.Colors.Warning, LayoutOrder = 60, TextWrapped = true, Parent = column })
	end

	-- Price + buttons
	local actions = UI.new("Frame", {
		Name = "Actions",
		AnchorPoint = if compact then Vector2.new(1, 0.5) else Vector2.new(0.5, 1),
		Position = if compact then UDim2.new(1, -16, 0.5, 0) else UDim2.new(0.5, 0, 1, -16),
		Size = if compact then UDim2.new(0.42, -16, 1, -24) else UDim2.new(1, -32, 0, 0),
		AutomaticSize = if compact then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = panel,
	}, { UI.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom) })

	if spec.Price then
		local currency = Currencies.Get(spec.Price.Currency)
		local priceLabel = UI.Label({
			Text = if spec.Price.Currency == "Robux" then "R$ " .. Format.Commas(spec.Price.Amount) else string.format("%s %s", if currency then currency.Glyph else "", Format.Abbreviate(spec.Price.Amount)),
			Size = UDim2.new(1, 0, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Center,
			FontFace = Theme.Fonts.Numbers,
			TextSize = 26,
			TextColor3 = if spec.Price.Affordable then Theme.Colors.Gold else Theme.Colors.Danger,
			LayoutOrder = 1,
			Parent = actions,
		})
		UI.CountTo(priceLabel, 0, spec.Price.Amount, 0.5, function(v)
			return if spec.Price.Currency == "Robux" then "R$ " .. Format.Commas(v) else string.format("%s %s", if currency then currency.Glyph else "", Format.Abbreviate(v))
		end)
	end

	table.clear(self.Buttons)
	if spec.Buttons then
		for i, b in spec.Buttons do
			local button = UI.Button({
				Name = b.Id or ("Action" .. i),
				Text = b.Text,
				Glyph = b.Glyph,
				Style = b.Style or "Primary",
				Enabled = b.Enabled ~= false,
				Size = UDim2.new(1, 0, 0, if compact then 46 else 52),
				TextSize = 19,
				LayoutOrder = 10 + i,
				Parent = actions,
				OnClick = b.OnClick,
			})
			self.PanelTrove:Add(button)
			if b.Id then
				self.Buttons[b.Id] = button
			end
		end
		if UserInputService.GamepadEnabled then
			local first = actions:FindFirstChildWhichIsA("TextButton")
			if first then
				GuiService.SelectedObject = first
			end
		end
	end
	Audio.Play("Tick")
end

function FactoryHud:GetButton(id: string)
	return self.Buttons[id]
end

function FactoryHud:HidePanel()
	self.PanelTrove:Clean()
	self.PanelHolder.Visible = false
	table.clear(self.Buttons)
end

-- Hides everything except the skip button during shows.
function FactoryHud:SetCinematic(enabled: boolean)
	self.Gui.Enabled = self.Visible and not enabled
end

return FactoryHud
