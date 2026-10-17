-- Slim, semi-transparent HUD on the screen edges while inside the factory:
-- zone quick-travel (left), contextual item panel (right on desktop, bottom on
-- phones), carousel arrows, back button and input hints. The edge elements
-- slide in and out; _layout fits them to the viewport.

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
local Effects = require(script.Parent.Effects)

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

-- Nav cell and gap (before the nav's own scale)
local NAV_CELL = Vector2.new(64, 56)
local NAV_GAP = 8
-- Below this nav scale the captions (10 px, about 9 px for the 8-letter names)
-- would render under 8 px (phones): the icons stand alone there.
local CAPTION_MIN_SCALE = 0.9

-- Rough height of a panel's text column. Body text is 15 px (18 px lines) and
-- wraps at about 7.5 px per character; anything taller scrolls.
local function columnHeight(spec: PanelSpec, width: number): number
	local perLine = math.max(math.floor(width / 7.5), 1)
	local function wrapped(text: string): number
		local plain = string.gsub(text, "<[^>]+>", "")
		return 18 * math.max(math.ceil((utf8.len(plain) or #plain) / perLine), 1)
	end
	local height, count = 30, 1
	if spec.Rarity then
		height += 20
		count += 1
	end
	if spec.Kicker then
		height += 16
		count += 1
	end
	if spec.Bars then
		height += #spec.Bars * 20
		count += #spec.Bars
	end
	if spec.Lines then
		for _, line in spec.Lines do
			height += wrapped(line)
			count += 1
		end
	end
	if spec.Status then
		height += math.max(wrapped(spec.Status), 20)
		count += 1
	end
	return height + (count - 1) * 6
end

function FactoryHud.new(deps)
	local self = setmetatable({}, FactoryHud)
	self.Deps = deps -- { OnTravel(zoneId), OnClassic(), OnExit(), OnNavChanged(visible, inset)? }
	self.PanelTrove = Trove.new()
	self.Visible = false
	self.Buttons = {}
	-- Edge elements: { rest, away } spots from _layout, running moves, slide tokens
	self.Spots = {} :: { [GuiObject]: { UDim2 } }
	self.Moves = {} :: { [GuiObject]: Tween }
	self.SlideTokens = {} :: { [GuiObject]: number }
	self.Hiding = {} :: { [GuiObject]: boolean }
	self.NavShown = true
	self.BackShown = false
	self.CarouselShown = false
	self.PanelShown = false
	self.PanelNeed = 440
	-- the shown panel's spec and layout, to rebuild it when the layout flips
	self.PanelSpec = nil :: PanelSpec?
	self.PanelCompact = false
	self.NavInset = 0
	self.Cinematic = false
	self.CinematicToken = 0
	self.HintFade = nil :: Tween?

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

	-- Zone navigation: one column, or two on short phone screens (_layout fits
	-- it between the top bar and the Back button)
	local nav = UI.new("Frame", {
		Name = "Nav",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 20),
		Size = UDim2.fromOffset(NAV_CELL.X, 520),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	self.NavGrid = UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(NAV_CELL.X, NAV_CELL.Y),
		CellPadding = UDim2.fromOffset(NAV_GAP, NAV_GAP),
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = nav,
	})
	self.NavScale = UI.new("UIScale", { Name = "AutoScale", Parent = nav })
	self.Nav = nav
	self.NavButtons = {}
	self.NavCaptions = {}
	self.NavCount = 0
	local function navButton(id: string, glyph: string, label: string, order: number, style: string?, onClick: () -> ())
		local holder = UI.new("Frame", { Name = id, Size = UDim2.fromOffset(NAV_CELL.X, NAV_CELL.Y), BackgroundTransparency = 1, LayoutOrder = order, Parent = nav })
		-- Icon-only: the icon goes in as Text (Glyph adds a spacer that shrinks and
		-- off-centres it); the centred anchor keeps hover/press scaling in place.
		local button = UI.Button({
			Text = glyph,
			Style = style or "Ghost",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
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
			Size = UDim2.new(1, -8, 0, 12),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextScaled = true,
			FontFace = Theme.Fonts.Title,
			TextColor3 = Theme.Colors.SubText,
			ZIndex = 6,
			Parent = button.Instance,
		})
		UI.new("UITextSizeConstraint", { MaxTextSize = 10, Parent = caption })
		self.NavButtons[id] = button
		self.NavCount += 1
		table.insert(self.NavCaptions, { Caption = caption, Label = button.Label })
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
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
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
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 33, 0.5, 0),
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
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -33, 0.5, 0),
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

	-- (placed above the carousel / panel by _layout)
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
		Visible = false,
		Parent = gui,
	})
	UI.AutoScale(self.Hint)

	-- Context panel container
	self.PanelHolder = UI.new("Frame", {
		Name = "PanelHolder",
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	self.PanelScale = UI.AutoScale(self.PanelHolder)

	self:_layout(true)
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		self:_layout(true)
	end)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
		self:_layout(true)
	end)
	return self
end

-- Layout & motion --------------------------------------------------------------------------

-- Fits the edge elements to the viewport and the current state: the nav between
-- the top bar (this gui ignores its inset) and the Back button; on phones Back,
-- panel and carousel share the bottom edge (the carousel under the right thumb,
-- clear of the toasts at the top); the hint above whatever is under it.
-- snap: the viewport changed, elements jump to their new spots.
function FactoryHud:_layout(snap: boolean?)
	local viewport = workspace.CurrentCamera.ViewportSize
	local scale = UI.ScaleFor(viewport)
	local compact = UI.IsCompact()
	local top = GuiService:GetGuiInset().Y + 8

	-- A panel built for the other layout (window resized across the phone
	-- threshold) is rebuilt for this one
	local spec = self.PanelSpec
	if snap and spec and self.PanelShown and self.PanelCompact ~= compact then
		task.defer(function()
			if self.PanelShown and self.PanelSpec == spec and self.PanelCompact ~= UI.IsCompact() then
				self:ShowPanel(spec)
			end
		end)
	end

	-- Nav: as many rows as fit at the auto scale, balanced over the columns
	local bottom = viewport.Y - (16 + 54 * scale + 10)
	local room = math.max(bottom - top, 1)
	local count = math.max(self.NavCount, 1)
	local rows = math.clamp(math.floor((room / scale + NAV_GAP) / (NAV_CELL.Y + NAV_GAP)), 1, count)
	local columns = math.ceil(count / rows)
	rows = math.ceil(count / columns)
	local width = columns * NAV_CELL.X + (columns - 1) * NAV_GAP
	local height = rows * NAV_CELL.Y + (rows - 1) * NAV_GAP
	local navScale = math.min(scale, room / height)
	local half = height * navScale / 2
	local navY = math.round(math.clamp(viewport.Y / 2 + 20, top + half, math.max(bottom - half, top + half)))
	local navWidth = math.ceil(width * navScale)
	self.NavGrid.FillDirectionMaxCells = rows
	self.Nav.Size = UDim2.fromOffset(width, height)
	self.NavScale.Scale = navScale
	self.NavInset = 14 + navWidth + 12
	self.Spots[self.Nav] = { UDim2.fromOffset(14, navY), UDim2.fromOffset(-navWidth - 16, navY) }
	local captions = navScale >= CAPTION_MIN_SCALE
	for _, entry in self.NavCaptions do
		entry.Caption.Visible = captions
		entry.Label.Position = if captions then UDim2.fromOffset(0, -5) else UDim2.new()
	end

	self.Spots[self.BackHolder] = { UDim2.new(0, 16, 1, -16), UDim2.new(0, -math.ceil(140 * scale) - 16, 1, -16) }

	local holder = self.PanelHolder
	-- (a panel that is sliding out keeps its shape)
	local reshape = not self.Hiding[holder]
	local carouselHeight = 66 * scale
	local carouselAway = math.ceil(carouselHeight) + 8
	local hintX: UDim
	local hintBottom: number
	if compact then
		-- (right of the Back button, and of the nav where it is the wider one)
		local left = math.max(16 + 140 * scale, 14 + navWidth) + 12
		local beside = viewport.X - (16 + 300 * scale + 12)
		local besideFits = beside - left >= 320 * scale
		local right = if self.CarouselShown and besideFits then beside else viewport.X - left
		local x = math.round((left + right) / 2)
		local panelTop = 16 + 200 * scale
		if reshape then
			holder.AnchorPoint = Vector2.new(0.5, 1)
			holder.Size = UDim2.fromOffset(math.clamp((right - left) / scale, 320, 560), 200)
		end
		self.Spots[holder] = { UDim2.new(0, x, 1, -16), UDim2.new(0, x, 1, math.ceil(panelTop)) }
		if besideFits then
			self.Carousel.AnchorPoint = Vector2.new(1, 1)
			self.Spots[self.Carousel] = { UDim2.new(1, -16, 1, -16), UDim2.new(1, -16, 1, carouselAway) }
		else
			-- too narrow for both: stacked above the panel
			self.Carousel.AnchorPoint = Vector2.new(0.5, 1)
			self.Spots[self.Carousel] = { UDim2.new(0, x, 1, -math.ceil(panelTop + 8)), UDim2.new(0, x, 1, carouselAway) }
		end
		hintX = UDim.new(0, x)
		if self.CarouselShown and not besideFits then
			hintBottom = panelTop + 8 + carouselHeight + 6
		elseif self.PanelShown then
			hintBottom = panelTop + 6
		else
			hintBottom = 16 + carouselHeight + 8
		end
	else
		-- right edge, between the top bar and the hint over the carousel; tall
		-- content grows the glass (up to 540) before the column has to scroll
		local lowest = viewport.Y - (18 + carouselHeight + 8 + 18 * scale + 4)
		local panelHeight = math.clamp(self.PanelNeed, 440, math.max(440, math.min(540, (lowest - top) / scale)))
		local halfPanel = panelHeight * scale / 2
		local y = math.round(math.clamp(viewport.Y * 0.55, top + halfPanel, math.max(lowest - halfPanel, top + halfPanel)))
		if reshape then
			holder.AnchorPoint = Vector2.new(1, 0.5)
			holder.Size = UDim2.fromOffset(320, panelHeight)
		end
		self.Spots[holder] = { UDim2.new(1, -96, 0, y), UDim2.new(1, math.ceil(320 * scale) + 16, 0, y) }
		self.Carousel.AnchorPoint = Vector2.new(0.5, 1)
		self.Spots[self.Carousel] = { UDim2.new(0.5, 0, 1, -18), UDim2.new(0.5, 0, 1, carouselAway) }
		hintX = UDim.new(0.5, 0)
		hintBottom = 18 + carouselHeight + 8
	end
	self.Hint.Position = UDim2.new(hintX.Scale, hintX.Offset, 1, -math.ceil(hintBottom))

	for object, isShown in self:_edges() do
		local spot = self.Spots[object]
		if snap then
			if isShown then
				-- (during a show they wait off-screen)
				self:_place(object, if self.Cinematic then spot[2] else spot[1])
			elseif object.Visible then
				-- still sliding out
				self:_place(object, spot[2])
			end
		elseif object == holder and isShown and holder.Visible and not self.Hiding[holder] and not self.Cinematic and holder.Position ~= spot[1] then
			self:_place(holder, spot[1], Theme.Tween.Medium)
		end
	end
	self:_navChanged()
end

-- The edge elements and whether each one belongs on screen.
function FactoryHud:_edges(): { [GuiObject]: boolean }
	return { [self.Nav] = self.NavShown, [self.BackHolder] = self.BackShown, [self.Carousel] = self.CarouselShown, [self.PanelHolder] = self.PanelShown }
end

-- Moves an edge element, replacing any move still running on it.
function FactoryHud:_place(object: GuiObject, position: UDim2, info: TweenInfo?)
	local running = self.Moves[object]
	if running then
		running:Cancel()
		self.Moves[object] = nil
	end
	if info then
		self.Moves[object] = UI.Tween(object, info, { Position = position })
	else
		object.Position = position
	end
end

-- Shows (slides in from off-screen) or hides (slides out, then Visible = false
-- and onHidden) an edge element. Instant while the gui is off or with Reduce
-- Motion. fromAway: restart the entrance even if it is already visible.
function FactoryHud:_slide(object: GuiObject, shown: boolean, animate: boolean, onHidden: (() -> ())?, fromAway: boolean?)
	local spot = self.Spots[object]
	local token = (self.SlideTokens[object] or 0) + 1
	self.SlideTokens[object] = token
	self.Hiding[object] = nil
	local motion = animate and self.Gui.Enabled and not Effects.ReduceMotion()
	if shown and self.Cinematic then
		-- during a show it waits off-screen; SetCinematic(false) brings it in
		self:_place(object, spot[2], if motion and object.Visible then Theme.Tween.Close else nil)
		object.Visible = true
	elseif shown then
		if motion and (fromAway or not object.Visible) then
			self:_place(object, spot[2])
		end
		object.Visible = true
		self:_place(object, spot[1], if motion then Theme.Tween.Open else nil)
	elseif motion and object.Visible then
		self.Hiding[object] = true
		self:_place(object, spot[2], Theme.Tween.Close)
		task.delay(Theme.Tween.Close.Time, function()
			if self.SlideTokens[object] == token then
				self.Hiding[object] = nil
				object.Visible = false
				if onHidden then
					onHidden()
				end
			end
		end)
	else
		self:_place(object, spot[1])
		object.Visible = false
		if onHidden then
			onHidden()
		end
	end
end

-- Tells the HUD where free space starts right of the nav, so it can move its
-- left column (currencies, feed) out from under it.
function FactoryHud:_navChanged()
	local callback = self.Deps and self.Deps.OnNavChanged
	local shown = self.Visible and self.NavShown
	if callback and (shown ~= self.ReportedShown or self.NavInset ~= self.ReportedInset) then
		self.ReportedShown = shown
		self.ReportedInset = self.NavInset
		callback(shown, self.NavInset)
	end
end

-- Public API -------------------------------------------------------------------------------

function FactoryHud:SetVisible(visible: boolean)
	self.Visible = visible
	local was = self.Gui.Enabled
	-- (stays off while a show runs; SetCinematic(false) plays the entrance then)
	self.Gui.Enabled = visible and not self.Cinematic
	if self.Gui.Enabled and not was then
		-- the nav enters from off-screen; the rest return from wherever a show
		-- that ended while the gui was off left them (in place: no move)
		for object, isShown in self:_edges() do
			if isShown then
				self:_slide(object, true, true, nil, object == self.Nav)
			end
		end
	end
	self:_navChanged()
end

function FactoryHud:SetNavVisible(visible: boolean)
	self.NavShown = visible
	self:_slide(self.Nav, visible, true)
	self:_navChanged()
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
	if self.BackShown then
		-- switching modes: already on screen
		UI.Pop(self.BackButton.Instance, 0.15)
	else
		self.BackShown = true
		self:_slide(self.BackHolder, true, true)
	end
end

-- (OnBack is cleared at once, so the sliding button no longer reacts)
function FactoryHud:HideBack()
	self.OnBack = nil
	self.BackShown = false
	self:_slide(self.BackHolder, false, true)
end

function FactoryHud:ShowCarousel(onPrev: () -> (), onNext: () -> ())
	self.OnPrev = onPrev
	self.OnNext = onNext
	self.CarouselShown = true
	self:_layout()
	self:_slide(self.Carousel, true, true)
end

function FactoryHud:SetCarouselLabel(text: string)
	self.CarouselLabel.Text = text
	UI.Pop(self.CarouselLabel, 0.12)
end

function FactoryHud:HideCarousel()
	self.OnPrev = nil
	self.OnNext = nil
	self.CarouselShown = false
	self:_slide(self.Carousel, false, true)
	self:_layout()
end

function FactoryHud:SetHint(text: string?)
	if not text then
		self.Hint.Text = ""
		self.Hint.Visible = false
		return
	end
	if UserInputService.GamepadEnabled then
		text = text:gsub("%[Keys%]", "D-Pad"):gsub("%[Confirm%]", "A"):gsub("%[Alt%]", "X"):gsub("%[Back%]", "B")
	elseif UserInputService.KeyboardEnabled then
		text = text:gsub("%[Keys%]", "← →"):gsub("%[Confirm%]", "Enter"):gsub("%[Alt%]", "T"):gsub("%[Back%]", "Backspace")
	else
		-- Touch: ◀ ▶ and Back are on-screen buttons and there is nothing to swipe
		-- (zones that handle swipes word their own hint). The Back button labels
		-- itself, so "[Back] Back" segments are dropped.
		local parts = {}
		for _, part in string.split(text, "·") do
			local segment = string.match(part, "^%s*(.-)%s*$") or ""
			local back = string.match(segment, "^%[Back%]%s*(.*)$")
			if back then
				if back ~= "" and back ~= "Back" and back ~= "Exit" then
					table.insert(parts, "Tap ← Back to " .. string.lower(back))
				end
			elseif segment ~= "" then
				table.insert(parts, (segment:gsub("%[Keys%]", "◀ ▶"):gsub("%[Confirm%]", "Tap"):gsub("%[Alt%]", "Tap")))
			end
		end
		text = table.concat(parts, "  ·  ")
	end
	self.Hint.Text = text
	self.Hint.Visible = text ~= ""
end

-- Context panel --------------------------------------------------------------------------

function FactoryHud:ShowPanel(spec: PanelSpec)
	self.PanelTrove:Clean()
	local holder = self.PanelHolder
	local compact = UI.IsCompact()
	-- The price/button stack is sized up front: the text column stops above it
	-- (phones: three buttons get shorter so the stack fits the 200 px glass)
	local buttonCount = if spec.Buttons then #spec.Buttons else 0
	local buttonHeight = if not compact then 52 elseif buttonCount >= 3 then 38 else 46
	local stack = buttonCount + (if spec.Price then 1 else 0)
	local actionsHeight = (if spec.Price then 30 else 0) + buttonCount * buttonHeight + math.max(stack - 1, 0) * 8
	self.PanelNeed = 16 + columnHeight(spec, 320 - 36) + 10 + actionsHeight + 16
	self.PanelShown = true
	self.PanelSpec = spec
	self.PanelCompact = compact
	-- (replacing a panel that is still sliding out: it is gone already, the new
	-- one appears in place)
	local appearing = not holder.Visible or self.Hiding[holder]
	self.Hiding[holder] = nil
	self:_layout()
	if appearing then
		self:_slide(holder, true, false)
	end

	local rarity = Rarities.Get(spec.Rarity)
	-- (centred so the pop below scales in place)
	local panel = UI.Glass({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
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

	-- Scrolls when the text is taller than the room left by the actions
	local column = UI.new("ScrollingFrame", {
		Name = "Column",
		Position = UDim2.fromOffset(18, 16),
		Size = if compact then UDim2.new(0.58, -26, 1, -32) else UDim2.new(1, -36, 1, -(42 + actionsHeight)),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Colors.SubText,
		ScrollBarImageTransparency = 0.4,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		Selectable = false,
		Parent = panel,
	}, { UI.List(Enum.FillDirection.Vertical, 6) })

	-- (a kicker goes under the rarity tag, e.g. "TEST RESULT · <vacuum>")
	if spec.Rarity then
		UI.RarityTag(spec.Rarity, { LayoutOrder = 1, Parent = column })
	end
	if spec.Kicker then
		UI.Label({ Text = string.upper(spec.Kicker), Size = UDim2.new(1, 0, 0, 16), TextSize = 13, TextColor3 = Theme.Colors.Accent, FontFace = Theme.Fonts.Title, LayoutOrder = 2, Parent = column })
	end
	local title = UI.Label({ Text = spec.Title, Size = UDim2.new(1, 0, 0, 30), FontFace = Theme.Fonts.Title, TextScaled = true, LayoutOrder = 3, Parent = column })
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
		-- (wraps instead of cutting off long lock requirements)
		UI.Label({
			Text = spec.Status,
			Size = UDim2.new(1, 0, 0, 20),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = 15,
			TextColor3 = Theme.Colors.Warning,
			LayoutOrder = 60,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = column,
		})
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

	local price = spec.Price
	if price then
		local currencyId = price.Currency
		local currency = Currencies.Get(currencyId)
		-- whole amounts only, also mid count-up (no "🪙 212.4")
		local function priceText(amount: number): string
			amount = math.round(amount)
			return if currencyId == "Robux" then "R$ " .. Format.Commas(amount) else string.format("%s %s", if currency then currency.Glyph else "", Format.Abbreviate(amount))
		end
		local priceLabel = UI.Label({
			Text = priceText(price.Amount),
			Size = UDim2.new(1, 0, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Center,
			FontFace = Theme.Fonts.Numbers,
			TextSize = 26,
			TextColor3 = if price.Affordable then Theme.Colors.Gold else Theme.Colors.Danger,
			LayoutOrder = 1,
			Parent = actions,
		})
		UI.CountTo(priceLabel, 0, price.Amount, 0.5, priceText)
	end

	table.clear(self.Buttons)
	if spec.Buttons then
		local first: TextButton? = nil
		local firstEnabled: TextButton? = nil
		for i, b in spec.Buttons do
			-- The list stacks slots; each button is centred in its slot so hover
			-- and press scale it in place.
			local slot = UI.new("Frame", { Name = b.Id or ("Action" .. i), Size = UDim2.new(1, 0, 0, buttonHeight), BackgroundTransparency = 1, LayoutOrder = 10 + i, Parent = actions })
			local button = UI.Button({
				Name = b.Id or ("Action" .. i),
				Text = b.Text,
				Glyph = b.Glyph,
				Style = b.Style or "Primary",
				Enabled = b.Enabled ~= false,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				TextSize = 19,
				Parent = slot,
				OnClick = b.OnClick,
			})
			self.PanelTrove:Add(button)
			if b.Id then
				self.Buttons[b.Id] = button
			end
			first = first or button.Instance
			if b.Enabled ~= false and not firstEnabled then
				firstEnabled = button.Instance
			end
		end
		local selected = firstEnabled or first
		if UserInputService.GamepadEnabled and selected then
			GuiService.SelectedObject = selected
		end
	end
	Audio.Play("Tick")
end

function FactoryHud:GetButton(id: string)
	return self.Buttons[id]
end

function FactoryHud:HidePanel()
	table.clear(self.Buttons)
	self.PanelShown = false
	self.PanelSpec = nil
	-- The leaving panel's buttons stop reacting at once; the glass slides away
	-- and is destroyed after (or right away when a new panel replaces it).
	for _, object in self.PanelHolder:GetDescendants() do
		if object:IsA("GuiButton") then
			object.Interactable = false
		end
	end
	self:_slide(self.PanelHolder, false, true, function()
		self.PanelTrove:Clean()
	end)
	self:_layout()
end

-- Fades the hint out for shows and back in after them.
function FactoryHud:_fadeHint(shown: boolean, info: TweenInfo?)
	if self.HintFade then
		self.HintFade:Cancel()
		self.HintFade = nil
	end
	local goal = { TextTransparency = if shown then 0 else 1, TextStrokeTransparency = if shown then 0.6 else 1 }
	if info then
		self.HintFade = UI.Tween(self.Hint, info, goal)
	else
		self.Hint.TextTransparency = goal.TextTransparency
		self.Hint.TextStrokeTransparency = goal.TextStrokeTransparency
	end
end

-- Hides everything except the skip button during shows: the edge elements
-- slide away and the hint fades before the gui switches off. When it comes
-- back (also after the entry show, which began before the player was inside)
-- the edge elements slide in again.
function FactoryHud:SetCinematic(enabled: boolean)
	self.Cinematic = enabled
	self.CinematicToken += 1
	local token = self.CinematicToken
	local was = self.Gui.Enabled
	if enabled then
		if was and not Effects.ReduceMotion() then
			for object, isShown in self:_edges() do
				if isShown and object.Visible then
					self:_place(object, self.Spots[object][2], Theme.Tween.Close)
				end
			end
			self:_fadeHint(false, Theme.Tween.Close)
			task.delay(Theme.Tween.Close.Time, function()
				if self.CinematicToken == token then
					self.Gui.Enabled = false
				end
			end)
		else
			self.Gui.Enabled = false
			self:_fadeHint(false)
		end
		return
	end
	self.Gui.Enabled = self.Visible
	if self.Gui.Enabled then
		-- (back from where the show sent them; from off-screen if the gui was off)
		for object, isShown in self:_edges() do
			if isShown then
				self:_slide(object, true, true, nil, not was)
			end
		end
	end
	self:_fadeHint(true, if self.Gui.Enabled then Theme.Tween.Medium else nil)
end

return FactoryHud
