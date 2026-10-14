-- Always-on shop HUD: currency pills with count-up, boost timers, Shop and
-- Settings buttons, toasts, purchase feed, reveal banner, skip button and a
-- fade overlay used by teleports.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Format = require(Shared.Util.Format)
local Currencies = require(Shared.Definitions.Currencies)
local Boosts = require(Shared.Definitions.Boosts)
local Rarities = require(Shared.Definitions.Rarities)

local ShopFolder = script.Parent.Parent:WaitForChild("Shop")
local Theme = require(ShopFolder.UI.Theme)
local UI = require(ShopFolder.UI.Components)
local Audio = require(ShopFolder.Audio)
local Effects = require(ShopFolder.Effects)
local UIFx = require(ShopFolder.UI.UIFx)
local DayNight = require(Shared.Util.DayNight)

local HudController = {}

HudController.ShopRequested = Signal.new()

local ClientData
local gui: ScreenGui
local root: Frame
local currencyList: Frame
local boostList: Frame
local toastList: Frame
local feedList: Frame
local bannerGui: ScreenGui
local fadeFrame: Frame
local skipButton: UI.Button
local settingsPanel: Frame? = nil

local pills: { [string]: { Frame: Frame, Label: TextLabel, Shown: number, Held: boolean } } = {}
local skipCallback: (() -> ())? = nil
local shopBadge: Frame? = nil

local TOAST_COLORS = {
	Info = Theme.Colors.Accent,
	Success = Theme.Colors.Success,
	Error = Theme.Colors.Danger,
	Warning = Theme.Colors.Warning,
}

local function makePill(currencyId: string, order: number)
	local currency = Currencies.Get(currencyId)
	if not currency then
		return
	end
	local pill = UI.Glass({
		Name = currencyId,
		Size = UDim2.fromOffset(170, 44),
		LayoutOrder = order,
		Radius = Theme.Radius.Pill,
		Visible = currencyId == "Coins",
		Parent = currencyList,
	})
	UI.Label({
		Name = "Glyph",
		Text = currency.Glyph,
		Size = UDim2.fromOffset(32, 32),
		Position = UDim2.fromOffset(8, 6),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
		Parent = pill,
	})
	local label = UI.Label({
		Name = "Amount",
		Text = "0",
		Size = UDim2.new(1, -52, 1, 0),
		Position = UDim2.fromOffset(46, 0),
		FontFace = Theme.Fonts.Numbers,
		TextSize = 22,
		TextColor3 = currency.Color:Lerp(Color3.new(1, 1, 1), 0.35),
		ZIndex = 3,
		Parent = pill,
	})
	pills[currencyId] = { Frame = pill, Label = label, Shown = 0, Held = false }
end

-- Floating "+X" / "-X", spinning glyph and glow ring on a currency pill.
local function currencyFeedback(pill, delta: number)
	if delta == 0 or not pill.Frame.Visible then
		return
	end
	local positive = delta > 0
	local center = Effects.GuiCenter(pill.Frame)
	UIFx.FloatText(Effects.Layer(), center + Vector2.new(pill.Frame.AbsoluteSize.X * 0.15, 30), (if positive then "+" else "-") .. Format.Abbreviate(math.abs(delta)), if positive then Theme.Colors.Success else Theme.Colors.Danger, 24)
	local glyph = pill.Frame:FindFirstChild("Glyph")
	if glyph and glyph:IsA("GuiObject") then
		glyph.Rotation = 0
		UI.Tween(glyph, TweenInfo.new(0.6, Enum.EasingStyle.Back), { Rotation = if positive then 360 else -360 })
		task.delay(0.62, function()
			glyph.Rotation = 0
		end)
	end
	local stroke = pill.Frame:FindFirstChild("Stroke")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color = if positive then Theme.Colors.Success else Theme.Colors.Danger
		stroke.Transparency = 0
		UI.Tween(stroke, TweenInfo.new(0.9), { Transparency = 0.84, Color = Color3.new(1, 1, 1) })
	end
	if positive then
		UIFx.Burst(Effects.Layer(), center - Vector2.new(pill.Frame.AbsoluteSize.X * 0.35, 0), Theme.Colors.Gold, 10, 50)
	end
end

local function refreshCurrencies(data: { [string]: any }, animate: boolean)
	for id, pill in pills do
		local value = data.Currencies[id] or 0
		pill.Frame.Visible = id == "Coins" or value > 0
		if not pill.Held and value ~= pill.Shown then
			if animate then
				UI.CountTo(pill.Label, pill.Shown, value, 0.7)
				UI.Pop(pill.Frame, if value > pill.Shown then 0.1 else 0.05)
				currencyFeedback(pill, value - pill.Shown)
			else
				pill.Label.Text = Format.Abbreviate(value)
			end
			pill.Shown = value
		end
	end
end

local boostRows: { [string]: Frame } = {}

local function refreshBoosts(data: { [string]: any })
	local now = workspace:GetServerTimeNow()
	for id, expires in data.Boosts do
		local boost = Boosts.Get(id)
		if boost and expires > now and not boostRows[id] then
			local row = UI.Glass({
				Name = id,
				Size = UDim2.fromOffset(120, 30),
				Radius = Theme.Radius.Pill,
				LayoutOrder = boost.Order,
				Parent = boostList,
			})
			UI.Label({
				Name = "Text",
				Text = boost.Glyph .. " --:--",
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				FontFace = Theme.Fonts.Numbers,
				TextSize = 16,
				ZIndex = 3,
				Parent = row,
			})
			boostRows[id] = row
			UI.Pop(row, 0.2)
		end
	end
end

local function tickBoosts()
	local data = ClientData:Get()
	if not data then
		return
	end
	local now = workspace:GetServerTimeNow()
	for id, row in boostRows do
		local expires = data.Boosts[id] or 0
		local boost = Boosts.Get(id)
		if expires <= now or not boost then
			row:Destroy()
			boostRows[id] = nil
		else
			local label = row:FindFirstChild("Text") :: TextLabel
			label.Text = boost.Glyph .. " " .. Format.Clock(expires - now)
		end
	end
end

local function buildSideButtons()
	local side = UI.new("Frame", {
		Name = "Side",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.42, 0),
		Size = UDim2.fromOffset(72, 160),
		BackgroundTransparency = 1,
		Parent = root,
	}, { UI.List(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Right) })
	UI.AutoScale(side)

	local shopHolder = UI.new("Frame", { Name = "ShopHolder", Size = UDim2.fromOffset(64, 64), BackgroundTransparency = 1, LayoutOrder = 1, Parent = side })
	local shop = UI.Button({
		Name = "ShopButton",
		Glyph = "🛒",
		Text = "",
		Style = "Gold",
		Size = UDim2.fromScale(1, 1),
		Radius = Theme.Radius.Large,
		TextSize = 30,
		Parent = shopHolder,
		OnClick = function()
			HudController.ShopRequested:Fire()
		end,
	})
	UI.Label({
		Text = "SHOP",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 12,
		FontFace = Theme.Fonts.Title,
		ZIndex = 5,
		Parent = shop.Instance,
	})
	shop.Label.Position = UDim2.fromOffset(0, -6)
	UIFx.Shine(shop.Instance, 6, 0.3)
	local badge = UI.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = Theme.Colors.Danger,
		Visible = false,
		ZIndex = 8,
		Parent = shop.Instance.Parent,
	}, { UI.Corner(Theme.Radius.Pill), UI.Stroke(Color3.new(1, 1, 1), 0.2, 2) })
	UI.Label({ Text = "!", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = Theme.Fonts.Title, ZIndex = 9, Parent = badge })
	local badgeScale = UI.GetScale(badge)
	TweenService:Create(badgeScale, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.18 }):Play()
	shopBadge = badge

	UI.Button({
		Name = "SettingsButton",
		Glyph = "⚙",
		Text = "",
		Style = "Secondary",
		Size = UDim2.fromOffset(52, 52),
		Radius = Theme.Radius.Large,
		TextSize = 24,
		LayoutOrder = 2,
		Parent = side,
		OnClick = function()
			HudController:ToggleSettings()
		end,
	})
end

function HudController:Init(controllers)
	ClientData = controllers.ClientData
end

function HudController:Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	gui = UI.new("ScreenGui", {
		Name = "ShopHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = Theme.Layers.Hud,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	root = UI.new("Frame", { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })

	currencyList = UI.new("Frame", {
		Name = "Currencies",
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.fromOffset(180, 200),
		BackgroundTransparency = 1,
		Parent = root,
	}, { UI.List(Enum.FillDirection.Vertical, 8) })
	UI.AutoScale(currencyList)
	for i, id in Currencies.Stored do
		makePill(id, i)
	end
	boostList = UI.new("Frame", {
		Name = "Boosts",
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(130, 0),
		BackgroundTransparency = 1,
		LayoutOrder = 99,
		Parent = currencyList,
	}, { UI.List(Enum.FillDirection.Vertical, 6) })

	toastList = UI.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(420, 300),
		BackgroundTransparency = 1,
		Parent = root,
	}, { UI.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center) })

	feedList = UI.new("Frame", {
		Name = "Feed",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 0.62, 0),
		Size = UDim2.fromOffset(360, 180),
		BackgroundTransparency = 1,
		Parent = root,
	}, { UI.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom) })
	UI.AutoScale(feedList)

	buildSideButtons()

	bannerGui = UI.new("ScreenGui", {
		Name = "ShopBanner",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = Theme.Layers.Banner,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})

	local skipHolder = UI.new("Frame", {
		Name = "SkipHolder",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 64),
		Size = UDim2.fromOffset(150, 52),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = bannerGui,
	})
	UI.AutoScale(skipHolder)
	skipButton = UI.Button({
		Name = "Skip",
		Text = "SKIP",
		Glyph = "⏭",
		Style = "Secondary",
		Size = UDim2.fromScale(1, 1),
		Radius = Theme.Radius.Pill,
		Parent = skipHolder,
		OnClick = function()
			HudController:TriggerSkip()
		end,
	})

	local fadeGui = UI.new("ScreenGui", {
		Name = "ShopFade",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = Theme.Layers.Fade,
		Parent = playerGui,
	})
	fadeFrame = UI.new("Frame", {
		Name = "Fade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Active = false,
		Parent = fadeGui,
	})

	ClientData.Changed:Connect(function(data, previous)
		refreshCurrencies(data, previous ~= nil)
		refreshBoosts(data)
	end)
	-- "!" on the shop button while today's Mystery Crate is waiting
	task.spawn(function()
		while true do
			local data = ClientData:Get()
			local badge = shopBadge
			if data and badge then
				local available = data.Daily.CrateDay ~= DayNight.Day(workspace:GetServerTimeNow())
				if available ~= badge.Visible then
					badge.Visible = available
					if available then
						UI.Pop(badge, 0.4)
					end
				end
			end
			task.wait(2)
		end
	end)
	local data = ClientData:Get()
	if data then
		refreshCurrencies(data, false)
		refreshBoosts(data)
	end

	Net.Event("Notify").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.Text) == "string" then
			HudController:Toast(payload.Text, payload.Kind)
		end
	end)

	task.spawn(function()
		while true do
			tickBoosts()
			task.wait(1)
		end
	end)
end

-- Currency display control (coin flights) ------------------------------------

function HudController:GetCurrencyAnchor(currencyId: string): GuiObject?
	local pill = pills[currencyId]
	return if pill then pill.Frame:FindFirstChild("Glyph") :: GuiObject else nil
end

-- Freeze the displayed value (the coin flight will count it down).
function HudController:HoldCurrency(currencyId: string, shownValue: number?)
	local pill = pills[currencyId]
	if not pill then
		return
	end
	pill.Held = true
	if shownValue then
		pill.Shown = shownValue
		pill.Label.Text = Format.Abbreviate(shownValue)
	end
end

function HudController:ReleaseCurrency(currencyId: string, duration: number?)
	local pill = pills[currencyId]
	if not pill then
		return
	end
	pill.Held = false
	local value = ClientData:Currency(currencyId)
	if value ~= pill.Shown then
		UI.CountTo(pill.Label, pill.Shown, value, duration or 0.6, nil, true)
		currencyFeedback(pill, value - pill.Shown)
		pill.Shown = value
	end
end

function HudController:ShownCurrency(currencyId: string): number
	local pill = pills[currencyId]
	return if pill then pill.Shown else 0
end

-- Toasts & feed -----------------------------------------------------------------

function HudController:Toast(text: string, kind: string?)
	local color = TOAST_COLORS[kind or "Info"] or Theme.Colors.Accent
	local toast = UI.Glass({
		Name = "Toast",
		Size = UDim2.fromOffset(380, 46),
		BackgroundTransparency = 0.08,
		Radius = Theme.Radius.Pill,
		StrokeColor = color,
		StrokeTransparency = 0.3,
		Parent = toastList,
	})
	UI.new("Frame", {
		Size = UDim2.fromOffset(8, 8),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 18, 0.5, 0),
		BackgroundColor3 = color,
		ZIndex = 3,
		Parent = toast,
	}, { UI.Corner(Theme.Radius.Pill) })
	UI.Label({
		Text = text,
		Size = UDim2.new(1, -48, 1, 0),
		Position = UDim2.fromOffset(36, 0),
		TextSize = 17,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextScaled = true,
		ZIndex = 3,
		Parent = toast,
	})
	local scale = UI.GetScale(toast)
	scale.Scale = 0.6
	UI.Tween(scale, Theme.Tween.Spring, { Scale = 1 })
	local timerBar = UI.new("Frame", {
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -40, 0, 2),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.3,
		ZIndex = 4,
		Parent = toast,
	}, { UI.Corner(Theme.Radius.Pill) })
	UI.Tween(timerBar, TweenInfo.new(3.2, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) })
	UIFx.Shine(toast, 10, 0.2)
	if kind == "Error" then
		Audio.Play("Error")
	end
	task.delay(3.2, function()
		if toast.Parent then
			UI.Tween(scale, Theme.Tween.Close, { Scale = 0.6 })
			UI.Tween(toast, Theme.Tween.Close, { BackgroundTransparency = 1 })
			task.wait(0.2)
			toast:Destroy()
		end
	end)
	local toasts = {}
	for _, child in toastList:GetChildren() do
		if child.Name == "Toast" then
			table.insert(toasts, child)
		end
	end
	if #toasts > 3 then
		toasts[1]:Destroy()
	end
end

function HudController:Feed(text: string, rarityId: string?)
	local rarity = Rarities.Get(rarityId)
	local line = UI.Glass({
		Name = "FeedLine",
		Size = UDim2.fromOffset(340, 34),
		Radius = Theme.Radius.Pill,
		BackgroundTransparency = 0.3,
		StrokeColor = rarity.Color,
		StrokeTransparency = 0.4,
		Parent = feedList,
	})
	UI.Label({
		Text = text,
		RichText = true,
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextSize = 15,
		TextScaled = true,
		FontFace = Theme.Fonts.Bold,
		ZIndex = 3,
		Parent = line,
	})
	UI.Pop(line, 0.12)
	local lines = {}
	for _, child in feedList:GetChildren() do
		if child.Name == "FeedLine" then
			table.insert(lines, child)
		end
	end
	if #lines > 4 then
		lines[1]:Destroy()
	end
	task.delay(7, function()
		if line.Parent then
			UI.Tween(line, Theme.Tween.Slow, { BackgroundTransparency = 1 })
			for _, d in line:GetDescendants() do
				if d:IsA("TextLabel") then
					UI.Tween(d, Theme.Tween.Slow, { TextTransparency = 1 })
				elseif d:IsA("UIStroke") then
					UI.Tween(d, Theme.Tween.Slow, { Transparency = 1 })
				end
			end
			task.wait(0.5)
			line:Destroy()
		end
	end)
end

-- Big reveal banner ("NEW VACUUM!").
function HudController:Banner(spec: { Title: string, Subtitle: string?, Rarity: string?, Style: string?, Duration: number? })
	local rarity = Rarities.Get(spec.Rarity)
	local big = spec.Style ~= "Small"
	local holder = UI.new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.24),
		Size = UDim2.fromOffset(if big then 560 else 420, if big then 130 else 96),
		BackgroundTransparency = 1,
		Parent = bannerGui,
	})
	UI.AutoScale(holder)
	local card = UI.Glass({
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		StrokeColor = rarity.Color,
		StrokeTransparency = 0.1,
		BackgroundTransparency = 0.05,
		Parent = holder,
	})
	local stroke = card:FindFirstChild("Stroke") :: UIStroke
	stroke.Thickness = 3
	local strokeGradient = UI.Gradient(Rarities.ColorSequence(rarity.Id), 0)
	strokeGradient.Parent = stroke
	UI.Label({
		Name = "Kicker",
		Text = string.upper(spec.Subtitle or rarity.Name),
		Position = UDim2.new(0, 0, 0, 12),
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = rarity.Color,
		FontFace = Theme.Fonts.Title,
		TextSize = 18,
		ZIndex = 3,
		Parent = card,
	})
	local title = UI.Label({
		Name = "Title",
		Text = spec.Title,
		Position = UDim2.new(0, 16, 0, 36),
		Size = UDim2.new(1, -32, 1, -48),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Theme.Fonts.Title,
		TextScaled = true,
		ZIndex = 3,
		Parent = card,
	})
	UI.new("UITextSizeConstraint", { MaxTextSize = if big then 54 else 38, Parent = title })
	UI.Gradient({ Color3.new(1, 1, 1), rarity.Color:Lerp(Color3.new(1, 1, 1), 0.4) }, 90).Parent = title

	-- Light rays fan out behind the card (bigger for rarer drops)
	local rays = nil
	if big then
		rays = UIFx.Rays(holder, rarity.Color, { Count = if spec.Style == "Epic" then 12 else 8, Speed = 10, Size = if spec.Style == "Epic" then 3.4 else 2.4, ZIndex = 0, Transparency = if spec.Style == "Epic" then 0.45 else 0.62 })
		rays.Size = UDim2.fromScale(0, 0)
		UI.Tween(rays, TweenInfo.new(0.6, Enum.EasingStyle.Back), { Size = UDim2.fromScale(if spec.Style == "Epic" then 3.4 else 2.4, if spec.Style == "Epic" then 3.4 else 2.4) })
	end
	local underline = UI.new("Frame", {
		Name = "Underline",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 36),
		Size = UDim2.fromOffset(0, 2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
		Parent = card,
	}, { UI.Corner(Theme.Radius.Pill), UI.Gradient(Rarities.ColorSequence(rarity.Id), 0) })
	UI.Tween(underline, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, 0.15), { Size = UDim2.fromOffset(if big then 180 else 120, 2) })
	title.Position = UDim2.new(0, 16, 0, 40)
	UIFx.Typewriter(title, if big then 0.55 else 0.35)
	local stopSparkles = if rarity.Rank >= 4 then UIFx.Sparkles(card, rarity.Color, if rarity.Rank >= 6 then 8 else 5) else nil
	local stopShine = UIFx.Shine(card, 1.6, 0.25)
	if rarity.Rank >= 4 then
		UIFx.Foil(card, rarity.Id, Theme.Radius.Large, 0.18)
	end

	local scale = UI.GetScale(card)
	scale.Scale = 0.3
	card.Rotation = -6
	UI.Tween(scale, Theme.Tween.Spring, { Scale = 1 })
	UI.Tween(card, Theme.Tween.Spring, { Rotation = 0 })
	local spin = TweenService:Create(strokeGradient, TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 })
	spin:Play()
	UIFx.Burst(Effects.Layer(), Effects.GuiCenter(holder), rarity.Color, if big then 26 else 14, if big then 260 else 160)
	if spec.Style == "Epic" then
		Effects.UIConfetti(60, { rarity.Gradient[1], rarity.Gradient[2], Color3.new(1, 1, 1) })
	end
	Audio.Play("Fanfare")
	task.delay(spec.Duration or 2.4, function()
		UI.Tween(scale, Theme.Tween.Close, { Scale = 0.7 })
		UI.Tween(card, Theme.Tween.Close, { BackgroundTransparency = 1 })
		if rays then
			UI.Tween(rays, Theme.Tween.Close, { Size = UDim2.fromScale(0, 0) })
		end
		task.wait(0.22)
		spin:Cancel()
		stopShine()
		if stopSparkles then
			stopSparkles()
		end
		holder:Destroy()
	end)
end

-- Skip button ---------------------------------------------------------------------

function HudController:ShowSkip(callback: () -> ())
	skipCallback = callback
	local holder = skipButton.Instance.Parent :: Frame
	holder.Visible = true
	UI.Pop(skipButton.Instance, 0.2)
	ContextActionService:BindActionAtPriority("ShopSkip", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			HudController:TriggerSkip()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 10, Enum.KeyCode.Space, Enum.KeyCode.ButtonB, Enum.KeyCode.Return)
end

function HudController:HideSkip()
	skipCallback = nil
	local holder = skipButton.Instance.Parent :: Frame
	holder.Visible = false
	ContextActionService:UnbindAction("ShopSkip")
end

function HudController:TriggerSkip()
	local callback = skipCallback
	if callback then
		HudController:HideSkip()
		callback()
	end
end

-- Fade overlay (yields for the duration).
function HudController:Fade(transparency: number, duration: number)
	fadeFrame.Active = transparency < 0.5
	local tween = TweenService:Create(fadeFrame, TweenInfo.new(duration, Enum.EasingStyle.Quad), { BackgroundTransparency = transparency })
	tween:Play()
	tween.Completed:Wait()
end

function HudController:SetSideVisible(visible: boolean)
	local side = root:FindFirstChild("Side")
	if side and side:IsA("GuiObject") then
		side.Visible = visible
	end
	feedList.Visible = visible
end

-- Settings ---------------------------------------------------------------------------

function HudController:ToggleSettings()
	if settingsPanel then
		local holder = settingsPanel
		settingsPanel = nil
		local panel = holder:FindFirstChild("Panel") :: Frame
		UI.Tween(UI.GetScale(panel), Theme.Tween.Close, { Scale = 0.8 })
		task.delay(0.18, function()
			holder:Destroy()
		end)
		Audio.Play("Close")
		return
	end
	Audio.Play("Open")
	local holder = UI.new("Frame", {
		Name = "Settings",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(400, 330),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = bannerGui,
	})
	UI.AutoScale(holder)
	settingsPanel = holder
	local panel = UI.Glass({
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Parent = holder,
	})
	UI.Label({
		Text = "SETTINGS",
		Position = UDim2.fromOffset(24, 18),
		Size = UDim2.new(1, -90, 0, 30),
		FontFace = Theme.Fonts.Title,
		TextSize = 24,
		ZIndex = 21,
		Parent = panel,
	})
	UI.Button({
		Text = "✕",
		Style = "Ghost",
		Size = UDim2.fromOffset(40, 40),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Radius = Theme.Radius.Pill,
		ZIndex = 21,
		Parent = panel,
		OnClick = function()
			HudController:ToggleSettings()
		end,
	})
	local rows = UI.new("Frame", {
		Position = UDim2.fromOffset(24, 70),
		Size = UDim2.new(1, -48, 1, -90),
		BackgroundTransparency = 1,
		ZIndex = 21,
		Parent = panel,
	}, { UI.List(Enum.FillDirection.Vertical, 14) })
	local options = {
		{ Key = "LowGraphics", Text = "Low Graphics", Hint = "Fewer particles and effects" },
		{ Key = "ReduceMotion", Text = "Reduce Motion", Hint = "No camera shake" },
		{ Key = "SkipIntro", Text = "Always Skip Intro", Hint = "Skip the tube ride" },
		{ Key = "ClassicShop", Text = "Prefer Classic Shop", Hint = "Factory door opens the quick shop" },
	}
	for i, option in options do
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 21, Parent = rows })
		UI.Label({ Text = option.Text, Size = UDim2.new(1, -70, 0, 22), TextSize = 18, ZIndex = 21, Parent = row })
		UI.Label({
			Text = option.Hint,
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.new(1, -70, 0, 18),
			TextSize = 14,
			TextColor3 = Theme.Colors.SubText,
			FontFace = Theme.Fonts.Body,
			ZIndex = 21,
			Parent = row,
		})
		local toggle = UI.Toggle({
			Value = ClientData:Setting(option.Key) == true,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Parent = row,
			OnChanged = function(value)
				ClientData:SetSetting(option.Key, value)
			end,
		})
		toggle.Instance.ZIndex = 22
	end
	local scale = UI.GetScale(panel)
	scale.Scale = 0.7
	UI.Tween(scale, Theme.Tween.Open, { Scale = 1 })
end

return HudController
