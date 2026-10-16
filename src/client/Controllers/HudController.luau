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
local settingsGui: ScreenGui
local fadeFrame: Frame
local skipButton: UI.Button
local settingsPanel: Frame? = nil

local pills: { [string]: { Frame: Frame, Label: TextLabel, Shown: number, Held: boolean, Token: number } } = {}
local skipCallback: (() -> ())? = nil
local shopBadge: Frame? = nil
local shopBadgePulse: Tween? = nil
local currentBanner: ((boolean?) -> ())? = nil
local cinematic = false
local factoryLayout = false
local layoutToken = 0
local fadeToken = 0
local fadeTarget = 1

-- A spend counted to an explicit target keeps the pill held until the reward
-- lands; if nobody releases it, it settles on the live value after this long.
local HOLD_SETTLE = 6
local FAST_CLOSE = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local TOAST_COLORS = {
	Info = Theme.Colors.Accent,
	Success = Theme.Colors.Success,
	Error = Theme.Colors.Danger,
	Warning = Theme.Colors.Warning,
}

-- Counters only ever show whole amounts (no "523.4" mid count-up).
local function wholeNumber(value: number): string
	return Format.Abbreviate(math.round(value))
end

-- Centre of `object` in `layer` coordinates. Both AbsolutePositions live in
-- the same space, so this holds whatever IgnoreGuiInset either gui uses.
local function centerIn(object: GuiObject, layer: ScreenGui): Vector2
	return object.AbsolutePosition + object.AbsoluteSize / 2 - layer.AbsolutePosition
end

-- Viewport-following UIScale for short-lived panels. Unlike UI.AutoScale it
-- lets go of the camera signal when the panel is destroyed.
local function scaleWithViewport(object: GuiObject): UIScale
	local camera = workspace.CurrentCamera
	local scale = UI.new("UIScale", { Name = "AutoScale", Scale = UI.ScaleFor(camera.ViewportSize), Parent = object })
	local connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		scale.Scale = UI.ScaleFor(camera.ViewportSize)
	end)
	object.Destroying:Connect(function()
		connection:Disconnect()
	end)
	return scale
end

-- Fades a whole subtree (backgrounds, text, images, strokes) to invisible.
local function fadeOut(object: GuiObject, info: TweenInfo)
	local objects = object:GetDescendants()
	table.insert(objects, object)
	for _, child in objects do
		if child:IsA("GuiObject") and child.BackgroundTransparency < 1 then
			UI.Tween(child, info, { BackgroundTransparency = 1 })
		end
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			UI.Tween(child, info, { TextTransparency = 1, TextStrokeTransparency = 1 })
		elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
			UI.Tween(child, info, { ImageTransparency = 1 })
		elseif child:IsA("UIStroke") then
			UI.Tween(child, info, { Transparency = 1 })
		end
	end
end

-- Fades a list item out and collapses its height so the list closes up
-- smoothly, then destroys it. Safe to call more than once.
local function dismiss(item: GuiObject, info: TweenInfo, shrink: number?)
	if item.Name == "Closing" or not item.Parent then
		return
	end
	item.Name = "Closing"
	fadeOut(item, info)
	if shrink then
		UI.Tween(UI.GetScale(item), info, { Scale = shrink })
	end
	UI.Tween(item, info, { Size = UDim2.new(item.Size.X, UDim.new(0, 0)) })
	task.delay(info.Time, function()
		item:Destroy()
	end)
end

-- Hides an emptied pill once its count-down has finished.
local function hideWhenEmpty(id: string, pill, delay: number)
	task.delay(delay, function()
		if id ~= "Coins" and not pill.Held and pill.Shown <= 0 and ClientData:Currency(id) <= 0 then
			pill.Frame.Visible = false
		end
	end)
end

local function closeSettings(playSound: boolean)
	local holder = settingsPanel
	if not holder then
		return
	end
	settingsPanel = nil
	local panel = holder:FindFirstChild("Panel") :: Frame
	UI.Tween(UI.GetScale(panel), Theme.Tween.Close, { Scale = 0.8 })
	fadeOut(holder, Theme.Tween.Close)
	task.delay(Theme.Tween.Close.Time, function()
		holder:Destroy()
	end)
	if playSound then
		Audio.Play("Close")
	end
end

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
	pills[currencyId] = { Frame = pill, Label = label, Shown = 0, Held = false, Token = 0 }
end

-- Floating "+X" / "-X", spinning glyph and glow ring on a currency pill.
-- The floaters live on the HUD layer so they stay with the pill (and are
-- dimmed with it when a shop window covers the HUD).
local function currencyFeedback(pill, delta: number)
	if delta == 0 or not pill.Frame.Visible then
		return
	end
	local positive = delta > 0
	local center = centerIn(pill.Frame, gui)
	UIFx.FloatText(gui, center + Vector2.new(pill.Frame.AbsoluteSize.X * 0.15, 30), (if positive then "+" else "-") .. Format.Abbreviate(math.abs(delta)), if positive then Theme.Colors.Success else Theme.Colors.Danger, 24)
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
		UIFx.Burst(gui, center - Vector2.new(pill.Frame.AbsoluteSize.X * 0.35, 0), Theme.Colors.Gold, 10, 50)
	end
end

-- Feedback for a pill that may have just become visible: the list layout
-- places it on the next frame, so measure it after that.
local function pillFeedback(pill, delta: number, wasVisible: boolean)
	if wasVisible then
		currencyFeedback(pill, delta)
	else
		task.delay(0.05, currencyFeedback, pill, delta)
	end
end

local function refreshCurrencies(data: { [string]: any }, animate: boolean)
	for id, pill in pills do
		local value = data.Currencies[id] or 0
		local wasVisible = pill.Frame.Visible
		-- A pill still showing a balance stays up while held / counting down
		-- (coins fly from it); hideWhenEmpty hides it once the count is done.
		if value > 0 or pill.Shown > 0 then
			pill.Frame.Visible = true
		end
		if not pill.Held and value ~= pill.Shown then
			if animate then
				UI.CountTo(pill.Label, pill.Shown, value, 0.7, wholeNumber)
				UI.Pop(pill.Frame, if value > pill.Shown then 0.1 else 0.05)
				pillFeedback(pill, value - pill.Shown, wasVisible)
			else
				pill.Label.Text = Format.Abbreviate(value)
			end
			pill.Shown = value
			if value <= 0 then
				hideWhenEmpty(id, pill, if animate then 1 else 0)
			end
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
				Text = boost.Glyph .. " " .. Format.Clock(expires - now),
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
			boostRows[id] = nil
			dismiss(row, Theme.Tween.Close, 0.6)
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
	-- Icon-only buttons pass the icon as Text (Glyph adds a spacer that
	-- shrinks and off-centres it); centred anchors keep hover/press scaling
	-- around the middle.
	local shop = UI.Button({
		Name = "ShopButton",
		Text = "🛒",
		Style = "Gold",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Radius = Theme.Radius.Large,
		TextSize = 30,
		Parent = shopHolder,
		OnClick = function()
			closeSettings(false)
			HudController.ShopRequested:Fire()
		end,
	})
	UI.Label({
		Text = "SHOP",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 14,
		TextColor3 = Color3.fromRGB(70, 40, 0),
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
	local pulse = TweenService:Create(badgeScale, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.18 })
	pulse:Play()
	shopBadge = badge
	shopBadgePulse = pulse

	local settingsHolder = UI.new("Frame", { Name = "SettingsHolder", Size = UDim2.fromOffset(52, 52), BackgroundTransparency = 1, LayoutOrder = 2, Parent = side })
	UI.Button({
		Name = "SettingsButton",
		Text = "⚙",
		Style = "Secondary",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Radius = Theme.Radius.Large,
		TextSize = 24,
		Parent = settingsHolder,
		OnClick = function()
			HudController:ToggleSettings()
		end,
	})
end

-- Left column and toasts sit right of the FactoryHud nav while it is up and
-- below the letterbox bars during shows; side buttons and feed slide away
-- for shows.
local function applyLayout(animate: boolean)
	if not currencyList then
		return
	end
	local viewport = workspace.CurrentCamera.ViewportSize
	-- FactoryHud nav: 14 px margin + 64 px auto-scaled column
	local left = if factoryLayout then 26 + math.ceil(64 * UI.ScaleFor(viewport)) else 16
	-- Letterbox bars reach about 12% of the screen height at their widest
	local top = if cinematic then math.max(64, math.ceil(viewport.Y * 0.12) + 10) else 64
	local side = root:FindFirstChild("Side") :: Frame?
	local goals: { [GuiObject]: UDim2 } = {
		[currencyList] = UDim2.fromOffset(left, top),
		[toastList] = UDim2.new(0.5, 0, 0, top),
		[feedList] = if cinematic then UDim2.new(0, -500, 0.62, 0) else UDim2.new(0, left, 0.62, 0),
	}
	if side then
		goals[side] = if cinematic then UDim2.new(1, 140, 0.42, 0) else UDim2.new(1, -14, 0.42, 0)
	end
	local info = if animate then Theme.Tween.Slow else TweenInfo.new(0)
	for object, position in goals do
		UI.Tween(object, info, { Position = position })
	end
	layoutToken += 1
	local token = layoutToken
	if cinematic then
		task.delay(info.Time, function()
			if layoutToken == token then
				feedList.Visible = false
				if side then
					side.Visible = false
				end
			end
		end)
	else
		feedList.Visible = true
		if side then
			side.Visible = true
		end
	end
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

	-- Toasts get their own layer above the shop window and the modal, so
	-- feedback raised while they are open is never hidden or dimmed.
	local toastGui = UI.new("ScreenGui", {
		Name = "ShopToasts",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = Theme.Layers.Modal + 3,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	toastList = UI.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(420, 300),
		BackgroundTransparency = 1,
		Parent = toastGui,
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

	-- Reveals play above the confirm modal, which is still closing when a
	-- purchase banner slams in (and below the effects layer).
	bannerGui = UI.new("ScreenGui", {
		Name = "ShopBanner",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = Theme.Layers.Modal + 2,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	-- Settings: above the factory HUD, below the shop window and the modal.
	settingsGui = UI.new("ScreenGui", {
		Name = "ShopSettings",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = Theme.Layers.Classic - 1,
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
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
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
						-- The pop takes over the shared UIScale (cancelling the
						-- pulse); restart the pulse once it has landed.
						UI.Pop(badge, 0.4)
						local pulse = shopBadgePulse
						task.delay(Theme.Tween.Spring.Time + 0.03, function()
							if pulse and badge.Visible then
								pulse:Play()
							end
						end)
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
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		applyLayout(false)
	end)

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
	pill.Token += 1
	if shownValue then
		pill.Shown = shownValue
		pill.Label.Text = Format.Abbreviate(shownValue)
	end
end

-- Counts the pill to the live value, or to `target` (e.g. "shown - price" for
-- a spend whose reward is revealed later); in that case the pill stays held
-- until the next release (or settles on its own after HOLD_SETTLE).
function HudController:ReleaseCurrency(currencyId: string, duration: number?, target: number?)
	local pill = pills[currencyId]
	if not pill then
		return
	end
	local live = ClientData:Currency(currencyId)
	local value = target or live
	local count = duration or 0.6
	pill.Held = value ~= live
	pill.Token += 1
	if value ~= pill.Shown then
		local wasVisible = pill.Frame.Visible
		pill.Frame.Visible = true
		UI.CountTo(pill.Label, pill.Shown, value, count, wholeNumber, true)
		pillFeedback(pill, value - pill.Shown, wasVisible)
		pill.Shown = value
	end
	if pill.Held then
		local token = pill.Token
		task.delay(HOLD_SETTLE, function()
			if pill.Held and pill.Token == token then
				HudController:ReleaseCurrency(currencyId)
			end
		end)
	elseif value <= 0 then
		hideWhenEmpty(currencyId, pill, count + 0.3)
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
	local label = UI.Label({
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
	-- TextScaled ignores TextSize: cap it so short and long toasts match
	UI.new("UITextSizeConstraint", { MaxTextSize = 17, MinTextSize = 12, Parent = label })
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
		dismiss(toast, Theme.Tween.Close, 0.6)
	end)
	local toasts = {}
	for _, child in toastList:GetChildren() do
		if child.Name == "Toast" then
			table.insert(toasts, child)
		end
	end
	if #toasts > 3 then
		dismiss(toasts[1], FAST_CLOSE, 0.6)
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
	local label = UI.Label({
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
	UI.new("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 11, Parent = label })
	UI.Pop(line, 0.12)
	local lines = {}
	for _, child in feedList:GetChildren() do
		if child.Name == "FeedLine" then
			table.insert(lines, child)
		end
	end
	if #lines > 4 then
		dismiss(lines[1], FAST_CLOSE)
	end
	task.delay(7, function()
		dismiss(line, Theme.Tween.Slow)
	end)
end

-- Big reveal banner ("NEW VACUUM!").
function HudController:Banner(spec: { Title: string, Subtitle: string?, Rarity: string?, Style: string?, Duration: number? })
	-- One banner at a time: a new reveal quickly retires the previous one
	local previous = currentBanner
	if previous then
		previous(true)
	end
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
	scaleWithViewport(holder)
	-- Centred anchor: the pop-in scale and tilt pivot on the rays / burst
	local card = UI.Glass({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		StrokeColor = rarity.Color,
		StrokeTransparency = 0.1,
		BackgroundTransparency = 0.05,
		Parent = holder,
	})
	local stroke = card:FindFirstChild("Stroke") :: UIStroke
	stroke.Thickness = 3
	-- UIGradient multiplies the stroke colour: a white base keeps it bright
	stroke.Color = Color3.new(1, 1, 1)
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
	local layer = Effects.Layer()
	UIFx.Burst(layer, centerIn(holder, layer), rarity.Color, if big then 26 else 14, if big then 260 else 160)
	if spec.Style == "Epic" then
		Effects.UIConfetti(60, { rarity.Gradient[1], rarity.Gradient[2], Color3.new(1, 1, 1) })
	end
	Audio.Play("Fanfare")

	local closed = false
	local stopShine: (() -> ())? = nil
	-- ClipsDescendants is ignored while the card is rotated, so the glint
	-- only starts sweeping once the tilt-in has landed.
	task.delay(Theme.Tween.Spring.Time + 0.03, function()
		if not closed then
			stopShine = UIFx.Shine(card, 1.6, 0.25)
		end
	end)
	local function close(fast: boolean?)
		if closed then
			return
		end
		closed = true
		if currentBanner == close then
			currentBanner = nil
		end
		if stopSparkles then
			stopSparkles()
		end
		local info = if fast then FAST_CLOSE else Theme.Tween.Close
		UI.Tween(scale, info, { Scale = 0.7 })
		fadeOut(holder, info)
		if rays then
			UI.Tween(rays, info, { Size = UDim2.fromScale(0, 0) })
		end
		task.delay(info.Time + 0.02, function()
			spin:Cancel()
			if stopShine then
				stopShine()
			end
			holder:Destroy()
		end)
	end
	currentBanner = close
	task.delay(spec.Duration or 2.4, close)
end

-- Skip button ---------------------------------------------------------------------

function HudController:ShowSkip(callback: () -> ())
	skipCallback = callback
	local holder = skipButton.Instance.Parent :: Frame
	holder.Visible = true
	UI.Pop(skipButton.Instance, 0.15)
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

-- Fade overlay (yields for the duration). When a newer fade towards the same
-- target takes over, this one still waits until the screen is (almost)
-- there, so its caller never teleports in view. Returns false when a newer
-- fade took over.
function HudController:Fade(transparency: number, duration: number): boolean
	fadeToken += 1
	local token = fadeToken
	fadeTarget = transparency
	fadeFrame.Active = transparency < 0.5
	local tween = TweenService:Create(fadeFrame, TweenInfo.new(duration, Enum.EasingStyle.Quad), { BackgroundTransparency = transparency })
	tween:Play()
	tween.Completed:Wait()
	while token ~= fadeToken and fadeTarget == transparency and math.abs(fadeFrame.BackgroundTransparency - transparency) > 0.02 do
		task.wait()
	end
	return token == fadeToken
end

-- false while a show runs: side buttons and feed slide away, the currency
-- column and toasts drop below the letterbox bars, settings close.
function HudController:SetSideVisible(visible: boolean)
	cinematic = not visible
	if cinematic then
		closeSettings(false)
	end
	applyLayout(true)
end

-- true while the FactoryHud nav column is on screen: the left column moves
-- out from under it.
function HudController:SetFactoryLayout(enabled: boolean)
	if factoryLayout ~= enabled then
		factoryLayout = enabled
		applyLayout(true)
	end
end

-- Settings ---------------------------------------------------------------------------

-- Closes the settings panel if it is open (e.g. when a shop window opens).
function HudController:CloseSettings()
	closeSettings(false)
end

function HudController:ToggleSettings()
	if settingsPanel then
		closeSettings(true)
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
		Parent = settingsGui,
	})
	scaleWithViewport(holder)
	settingsPanel = holder
	local panel = UI.Glass({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
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
			closeSettings(true)
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
