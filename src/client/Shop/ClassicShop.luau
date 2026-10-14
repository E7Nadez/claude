-- "Classic Mode": the fast 2D shop window. Dark glassmorphism, category tabs
-- with a sliding indicator, responsive grid of item cards with rarity colors,
-- animated buy buttons, details/confirm modal, open/close scale+fade tweens.

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
local Audio = require(script.Parent.Audio)

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

function ClassicShop.new(deps)
	local self = setmetatable({}, ClassicShop)
	self.Deps = deps -- { ClientData, Modal, Hud }
	self.IsOpen = false
	self.Category = Shop.Categories[1].Id
	self.Cards = {}
	self.Trove = Trove.new()
	self.CardTrove = Trove.new()
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

	local window = UI.Glass({
		Name = "Window",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.08,
		Active = true,
		Parent = holder,
	})
	self.Window = window

	-- Animated accent line along the top edge
	local accent = UI.new("Frame", {
		Name = "Accent",
		Size = UDim2.new(1, -40, 0, 3),
		Position = UDim2.fromOffset(20, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = window,
	}, { UI.Corner(Theme.Radius.Pill) })
	local accentGradient = UI.Gradient({ Theme.Colors.Accent, Theme.Colors.AccentAlt }, 0)
	accentGradient.Parent = accent
	TweenService:Create(accentGradient, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Offset = Vector2.new(0.4, 0) }):Play()

	-- Header
	local header = UI.new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 70), BackgroundTransparency = 1, Parent = window })
	UI.Label({ Text = "SHOP", Position = UDim2.fromOffset(24, 12), Size = UDim2.fromOffset(200, 32), FontFace = Theme.Fonts.Title, TextSize = 30, Parent = header })
	self.Subtitle = UI.Label({
		Text = "Classic Mode",
		Position = UDim2.fromOffset(24, 44),
		Size = UDim2.fromOffset(320, 18),
		TextSize = 14,
		TextColor3 = Theme.Colors.SubText,
		Parent = header,
	})
	local balance = UI.new("Frame", {
		Name = "Balance",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -74, 0, 16),
		Size = UDim2.fromOffset(420, 38),
		BackgroundTransparency = 1,
		Parent = header,
	}, { UI.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
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
		self.BalanceLabels[id] = { Pill = pill, Label = label, Shown = -1 }
	end
	local close = UI.Button({
		Name = "Close",
		Text = "✕",
		Style = "Ghost",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(44, 44),
		Radius = Theme.Radius.Pill,
		TextSize = 20,
		Parent = header,
		OnClick = function()
			self:Close()
		end,
	})
	close.Instance.MouseEnter:Connect(function()
		UI.Tween(close.Instance, Theme.Tween.Spring, { Rotation = 90 })
	end)
	close.Instance.MouseLeave:Connect(function()
		UI.Tween(close.Instance, Theme.Tween.Medium, { Rotation = 0 })
	end)

	-- Tabs
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
	UI.List(Enum.FillDirection.Horizontal, 8, nil, Enum.VerticalAlignment.Center).Parent = tabs
	UI.Padding(4, 4).Parent = tabs
	self.Tabs = {}
	self.TabIndicator = UI.new("Frame", {
		Name = "Indicator",
		Size = UDim2.fromOffset(100, 3),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 4,
		Parent = window,
	}, { UI.Corner(Theme.Radius.Pill), UI.Gradient({ Theme.Colors.Accent, Theme.Colors.AccentAlt }, 0) })
	for i, category in Shop.Categories do
		local tab = UI.new("TextButton", {
			Name = category.Id,
			Text = "",
			Size = UDim2.fromOffset(0, 40),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Theme.Colors.PanelLight,
			BackgroundTransparency = 0.4,
			LayoutOrder = i,
			Parent = tabs,
		}, { UI.Corner(Theme.Radius.Pill), UI.Padding(0, 16) })
		local stroke = UI.Stroke(nil, 0.9)
		stroke.Parent = tab
		UI.Label({
			Name = "Text",
			Text = category.Glyph .. "  " .. category.Name,
			Size = UDim2.fromOffset(0, 40),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = 16,
			TextTruncate = Enum.TextTruncate.None,
			TextColor3 = Theme.Colors.SubText,
			Parent = tab,
		})
		local scale = UI.GetScale(tab)
		tab.MouseEnter:Connect(function()
			if self.Category ~= category.Id then
				UI.Tween(scale, Theme.Tween.Fast, { Scale = 1.05 })
				UI.Tween(tab, Theme.Tween.Fast, { BackgroundTransparency = 0.15 })
			end
		end)
		tab.MouseLeave:Connect(function()
			UI.Tween(scale, Theme.Tween.Medium, { Scale = 1 })
			if self.Category ~= category.Id then
				UI.Tween(tab, Theme.Tween.Medium, { BackgroundTransparency = 0.4 })
			end
		end)
		tab.Activated:Connect(function()
			self:SelectCategory(category.Id)
		end)
		self.Tabs[category.Id] = tab
	end
	tabs:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:_moveIndicator(false)
	end)

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
	UI.Padding(6, 6).Parent = content
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
end

function ClassicShop:_layoutGrid()
	local width = self.Content.AbsoluteSize.X - 18
	if width <= 0 then
		return
	end
	local minCell = if UI.IsCompact() then 150 else 176
	local columns = math.max(2, math.floor((width + 12) / (minCell + 12)))
	local cellWidth = math.floor((width - (columns - 1) * 12) / columns)
	self.Grid.CellSize = UDim2.fromOffset(cellWidth, math.floor(cellWidth * 1.36))
end

function ClassicShop:_moveIndicator(animate: boolean)
	local tab = self.Tabs[self.Category]
	if not tab then
		return
	end
	-- Absolute sizes include the window's open/close UIScale; undo it.
	local scale = math.max(UI.GetScale(self.Window).Scale, 0.01)
	local windowPos = self.Window.AbsolutePosition
	local pos = (tab.AbsolutePosition - windowPos) / scale
	local size = tab.AbsoluteSize / scale
	local goal = {
		Position = UDim2.fromOffset(pos.X + 14, pos.Y + size.Y + 1),
		Size = UDim2.fromOffset(math.max(size.X - 28, 10), 3),
	}
	if animate then
		UI.Tween(self.TabIndicator, Theme.Tween.Spring, goal)
	else
		self.TabIndicator.Position = goal.Position
		self.TabIndicator.Size = goal.Size
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
				UI.CountTo(entry.Label, entry.Shown, value, 0.6)
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
	local card = UI.new("TextButton", {
		Name = item.Id,
		Text = "",
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Selectable = false,
		Parent = self.Content,
	})
	local body = UI.Glass({
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.PanelLight,
		BackgroundTransparency = 0.25,
		StrokeColor = rarity.Color,
		StrokeTransparency = 0.55,
		Radius = Theme.Radius.Medium,
		Parent = card,
	})
	UI.Gradient(Rarities.ColorSequence(rarity.Id), 135, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.82),
		NumberSequenceKeypoint.new(1, 0.95),
	})).Parent = UI.new("Frame", {
		Name = "Tint",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		Parent = body,
	}, { UI.Corner(Theme.Radius.Medium) })

	local icon = UI.Icon({
		Glyph = item.Glyph,
		Rarity = item.Rarity,
		IconAssetId = item.IconAssetId,
		Size = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 22),
		Parent = body,
	})
	icon.Size = UDim2.new(0.48, 0, 0.48, 0)
	UI.RarityTag(item.Rarity, { Position = UDim2.fromOffset(8, 8), Size = UDim2.new(0.5, 0, 0, 16), Parent = body })
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

	local buy = UI.Button({
		Name = "Buy",
		Text = "",
		Style = "Gold",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -20, 0.15, 0),
		TextSize = 17,
		Parent = body,
		OnClick = function()
			UI.Wiggle(icon, 12)
			deps.Modal:Show(item, { Source = "Classic" })
		end,
	})
	self.CardTrove:Add(buy)

	-- Card hover: lift + stroke + icon wiggle; click opens details
	local stroke = body:FindFirstChild("Stroke") :: UIStroke
	card.MouseEnter:Connect(function()
		Audio.Play("Hover")
		UI.Tween(body, Theme.Tween.Fast, { Position = UDim2.fromOffset(0, -5) })
		UI.Tween(stroke, Theme.Tween.Fast, { Transparency = 0.1 })
		UI.Wiggle(icon, 8)
	end)
	card.MouseLeave:Connect(function()
		UI.Tween(body, Theme.Tween.Medium, { Position = UDim2.fromOffset(0, 0) })
		UI.Tween(stroke, Theme.Tween.Medium, { Transparency = 0.55 })
	end)
	card.Activated:Connect(function()
		Audio.Play("Click")
		deps.Modal:Show(item, { Source = "Classic" })
	end)

	local entry = {
		Item = item,
		Card = card,
		Body = body,
		Badge = badge,
		BadgeLabel = badgeLabel,
		Sub = sub,
		Buy = buy,
		Icon = icon,
		LastState = nil,
	}

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
		body.BackgroundTransparency = if state == "Locked" or state == "Unavailable" then 0.45 else 0.25
		if entry.LastState and entry.LastState ~= state and (state == "Owned" or state == "Equipped") then
			UI.Pop(body, 0.12)
		end
		entry.LastState = state
	end

	entry.Refresh()
	return entry
end

function ClassicShop:_refreshCards()
	for _, entry in self.Cards do
		entry.Refresh()
	end
end

function ClassicShop:SelectCategory(categoryId: string, silent: boolean?)
	local changed = self.Category ~= categoryId
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
		if active and changed then
			UI.Pop(tab, 0.08)
		end
	end
	task.defer(function()
		self:_moveIndicator(true)
	end)

	self.CardTrove:Clean()
	for _, entry in self.Cards do
		entry.Card:Destroy()
	end
	table.clear(self.Cards)
	self.Content.CanvasPosition = Vector2.zero

	local items = Shop.ItemsInCategory(categoryId)
	self.Empty.Visible = #items == 0
	for i, item in items do
		local entry = self:_createCard(item, i)
		table.insert(self.Cards, entry)
		-- staggered pop-in
		local scale = UI.GetScale(entry.Body)
		scale.Scale = 0.85
		entry.Body.BackgroundTransparency = 1
		task.delay(math.min(i, 14) * 0.025, function()
			if entry.Body.Parent then
				UI.Tween(scale, Theme.Tween.Spring, { Scale = 1 })
				entry.Refresh()
			end
		end)
	end
	self:_layoutGrid()
	if UserInputService.GamepadEnabled and self.Cards[1] then
		GuiService.SelectedObject = self.Cards[1].Buy.Instance
	end
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
	self.Gui.Enabled = true
	Audio.Play("Open")

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
	local compact = UI.IsCompact()
	self.Holder.Size = if compact then UDim2.fromScale(0.96, 0.9) else UDim2.fromScale(0.86, 0.84)
	local scale = UI.GetScale(self.Window)
	scale.Scale = 0.86
	self.Window.BackgroundTransparency = 1
	self.Holder.Position = UDim2.fromScale(0.5, 0.56)
	UI.Tween(scale, Theme.Tween.Open, { Scale = 1 })
	task.delay(0.42, function()
		if self.IsOpen then
			self:_moveIndicator(false)
		end
	end)
	UI.Tween(self.Window, Theme.Tween.Medium, { BackgroundTransparency = 0.08 })
	UI.Tween(self.Holder, Theme.Tween.Open, { Position = UDim2.fromScale(0.5, 0.52) })

	self.Hint.Text = if UserInputService.GamepadEnabled then "LB / RB  switch tabs  ·  B  close" elseif UserInputService.KeyboardEnabled then "Q / E  switch tabs  ·  Backspace  close" else ""
	self:_refreshHeader()
	self:SelectCategory(categoryId or self.Category, true)

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
	self.Deps.Modal:Close(true)
	Audio.Play("Close")
	ContextActionService:UnbindAction("ClassicShopNav")
	self.Trove:Clean()
	local blur = Lighting:FindFirstChild("ShopBlur")
	if blur then
		UI.Tween(blur, Theme.Tween.Close, { Size = 0 })
	end
	UI.Tween(UI.GetScale(self.Window), Theme.Tween.Close, { Scale = 0.9 })
	UI.Tween(self.Window, Theme.Tween.Close, { BackgroundTransparency = 1 })
	UI.Tween(self.Backdrop, Theme.Tween.Close, { BackgroundTransparency = 1 })
	UI.Tween(self.Holder, Theme.Tween.Close, { Position = UDim2.fromScale(0.5, 0.56) })
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.Gui) then
		GuiService.SelectedObject = nil
	end
	task.delay(0.21, function()
		if not self.IsOpen then
			self.Gui.Enabled = false
		end
	end)
end

function ClassicShop:Toggle(categoryId: string?)
	if self.IsOpen then
		self:Close()
	else
		self:Open(categoryId)
	end
end

-- Lightweight success effects for purchases made in this window.
function ClassicShop:CelebrateFrom(itemId: string)
	for _, entry in self.Cards do
		if entry.Item.Id == itemId then
			UI.Pop(entry.Body, 0.15)
			UI.Wiggle(entry.Icon, 16)
			return entry.Buy.Instance
		end
	end
	return nil
end

return ClassicShop
