-- Details / confirmation popup shown before every purchase (classic window and
-- factory). Shows a live 3D preview for vacuums, stat bars vs. the equipped
-- vacuum, capsule odds, upgrade levels, boost timers, and Confirm / Cancel.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Definitions = Shared.Definitions
local Shop = require(Definitions.Shop)
local Capsules = require(Definitions.Capsules)
local Pets = require(Definitions.Pets)
local Upgrades = require(Definitions.Upgrades)
local Boosts = require(Definitions.Boosts)
local Cosmetics = require(Definitions.Cosmetics)
local Trophies = require(Definitions.Trophies)
local Bosses = require(Definitions.Bosses)
local Worlds = require(Definitions.Worlds)
local Rarities = require(Definitions.Rarities)
local Currencies = require(Definitions.Currencies)
local Stats = require(Shared.Util.Stats)
local Format = require(Shared.Util.Format)
local DayNight = require(Shared.Util.DayNight)
local Trove = require(Shared.Util.Trove)
local VacuumModel = require(Shared.Models.VacuumModel)
local TrophyModel = require(Shared.Models.TrophyModel)

local Theme = require(script.Parent.UI.Theme)
local UI = require(script.Parent.UI.Components)
local UIFx = require(script.Parent.UI.UIFx)
local Audio = require(script.Parent.Audio)
local Effects = require(script.Parent.Effects)
local Builder = require(Shared.Util.Builder)

local ConfirmModal = {}
ConfirmModal.__index = ConfirmModal

export type Deps = {
	ClientData: any,
	Purchase: (item: Shop.ShopItem, source: string) -> { [string]: any },
	Equip: (item: Shop.ShopItem) -> { [string]: any },
}

function ConfirmModal.new(deps: Deps)
	local self = setmetatable({}, ConfirmModal)
	self.Deps = deps
	self.Trove = Trove.new()
	self.Open = false
	self.Gui = UI.new("ScreenGui", {
		Name = "ShopModal",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = Theme.Layers.Modal,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	return self
end

function ConfirmModal:IsOpen(): boolean
	return self.Open
end

-- Section builders ------------------------------------------------------------------

local function statRows(parent: Frame, vacuumId: string, clientData: any)
	local test = clientData:EffectiveStats(vacuumId)
	local equippedId = clientData:Equipped()
	local current = clientData:EffectiveStats(equippedId)
	local delta = Stats.Delta(test, current)
	for i, key in Stats.Order do
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = i, Parent = parent })
		UI.Label({ Text = Stats.Glyphs[key] .. " " .. Stats.Labels[key], Size = UDim2.new(0, 96, 1, 0), TextSize = 15, Parent = row })
		local track = UI.new("Frame", {
			Position = UDim2.fromOffset(100, 8),
			Size = UDim2.new(1, -230, 0, 10),
			BackgroundColor3 = Theme.Colors.PanelLight,
			Parent = row,
		}, { UI.Corner(Theme.Radius.Pill) })
		local ghost = UI.new("Frame", {
			Size = UDim2.fromScale(Stats.BarFill(key, (current :: any)[key]), 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.75,
			Parent = track,
		}, { UI.Corner(Theme.Radius.Pill) })
		ghost.ZIndex = 2
		local d = delta[key]
		local color = if math.abs(d) < 0.005 then Theme.Colors.Accent elseif d > 0 then Theme.Colors.Success else Theme.Colors.Danger
		local fill = UI.new("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = color,
			ZIndex = 3,
			Parent = track,
		}, { UI.Corner(Theme.Radius.Pill) })
		UI.Tween(fill, TweenInfo.new(0.6 + i * 0.08, Enum.EasingStyle.Quint), { Size = UDim2.fromScale(Stats.BarFill(key, (test :: any)[key]), 1) })
		local value = UI.Label({
			Text = "0",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -62, 0, 0),
			Size = UDim2.new(0, 60, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			FontFace = Theme.Fonts.Numbers,
			TextSize = 16,
			Parent = row,
		})
		UI.CountTo(value, 0, (test :: any)[key], 0.7, Format.Stat)
		UI.Label({
			Text = if vacuumId == equippedId then "equipped" elseif math.abs(d) < 0.005 then "=" else Format.Percent(d, true),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0, 58, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = color,
			FontFace = Theme.Fonts.Numbers,
			TextSize = 14,
			Parent = row,
		})
	end
end

local function textRow(parent: Frame, text: string, order: number, color: Color3?)
	UI.Label({
		Text = text,
		RichText = true,
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 16,
		TextColor3 = color or Theme.Colors.Text,
		FontFace = Theme.Fonts.Body,
		LayoutOrder = order,
		Parent = parent,
	})
end

local function oddsRows(parent: Frame, capsuleId: string, data: any)
	local luck = Boosts.ActiveMultiplier(data and data.Boosts, "Luck", workspace:GetServerTimeNow())
	if data and data.Gamepasses.gp_lucky then
		luck *= 1.5
	end
	for i, entry in Capsules.EffectiveDrops(capsuleId, luck) do
		local pet = Pets.Get(entry.Pet)
		if pet then
			local rarity = Rarities.Get(pet.Rarity)
			local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = i, Parent = parent })
			UI.new("Frame", {
				Size = UDim2.fromOffset(10, 10),
				Position = UDim2.fromOffset(0, 6),
				BackgroundColor3 = rarity.Color,
				Parent = row,
			}, { UI.Corner(Theme.Radius.Pill) })
			UI.Label({ Text = pet.Name, Position = UDim2.fromOffset(18, 0), Size = UDim2.new(0.6, 0, 1, 0), TextSize = 15, Parent = row })
			UI.Label({
				Text = string.format("x%s  ·  %s", Format.Stat(pet.Multiplier), Format.Chance(entry.Chance)),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.new(0.4, 0, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = rarity.Color,
				FontFace = Theme.Fonts.Numbers,
				TextSize = 15,
				Parent = row,
			})
		end
	end
	if luck > 1 then
		textRow(parent, string.format("🍀 Luck x%s active", Format.Stat(luck)), 99, Theme.Colors.Success)
	end
end

local function detailsFor(item: Shop.ShopItem, parent: Frame, clientData: any)
	local data = clientData:Get()
	if item.Kind == "Vacuum" then
		statRows(parent, item.RefId, clientData)
		local comparison = Stats.Compare(
			clientData:EffectiveStats(item.RefId),
			clientData:EffectiveStats(clientData:Equipped()),
			(Worlds.Get(item.World or "Cleanville") or Worlds.Info.Cleanville).TrashSet
		)
		if item.RefId ~= clientData:Equipped() then
			textRow(parent, string.format("<b>%s</b> cleaning speed vs. your vacuum", Format.Percent(comparison.Percent, true)), 10, if comparison.Percent >= 0 then Theme.Colors.Success else Theme.Colors.Danger)
		end
	elseif item.Kind == "Capsule" then
		oddsRows(parent, item.RefId, data)
	elseif item.Kind == "Upgrade" then
		local upgrade = Upgrades.Get(item.RefId)
		if upgrade then
			local level = clientData:UpgradeLevel(item.RefId)
			local now = (Upgrades.Multiplier(item.RefId, level) - 1)
			local nextValue = (Upgrades.Multiplier(item.RefId, math.min(level + 1, upgrade.MaxLevel)) - 1)
			textRow(parent, string.format("Level <b>%d</b> → <b>%d</b>  (max %d)", level, math.min(level + 1, upgrade.MaxLevel), upgrade.MaxLevel), 1)
			textRow(parent, string.format("%s %s: <b>%s</b> → <font color=\"#40D68C\"><b>%s</b></font>", Stats.Glyphs[upgrade.Stat], Stats.Labels[upgrade.Stat], Format.Percent(now, true), Format.Percent(nextValue, true)), 2)
		end
	elseif item.Kind == "Boost" then
		local boost = Boosts.Get(item.RefId)
		if boost then
			textRow(parent, string.format("⏱ Duration: <b>%s</b> (stacks up to %s)", Format.Duration(boost.Duration), Format.Duration(boost.MaxDuration)), 1)
			local expires = data and data.Boosts[item.RefId] or 0
			local remaining = expires - workspace:GetServerTimeNow()
			if remaining > 0 then
				textRow(parent, "Active: " .. Format.Clock(remaining) .. " left", 2, Theme.Colors.Success)
			end
		end
	elseif item.Kind == "Cosmetic" then
		local cosmetic = Cosmetics.Get(item.RefId)
		if cosmetic then
			textRow(parent, "Slot: <b>" .. cosmetic.Slot .. "</b>", 1)
			local swatches = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 2, Parent = parent }, { UI.List(Enum.FillDirection.Horizontal, 6) })
			local colors = if cosmetic.Slot == "Skin" then { cosmetic.Body, cosmetic.Accent, cosmetic.Glow } else cosmetic.Colors or {}
			for i, color in colors do
				if color then
					UI.new("Frame", { Size = UDim2.fromOffset(28, 28), BackgroundColor3 = color, LayoutOrder = i, Parent = swatches }, { UI.Corner(Theme.Radius.Small), UI.Stroke(nil, 0.6) })
				end
			end
		end
	elseif item.Kind == "Trophy" then
		local trophy = Trophies.Get(item.RefId)
		if trophy then
			textRow(parent, "Boss: <b>" .. Bosses[trophy.Boss].Name .. "</b>", 1)
			if trophy.Perk then
				textRow(parent, string.format("Perk: <b>+%s %s</b>", Format.Percent(trophy.Perk.Bonus), trophy.Perk.Stat), 2, Theme.Colors.Success)
			end
		end
	elseif item.Kind == "Gamepass" then
		local pass = Shop.GamepassById[item.RefId]
		if pass and pass.Perk then
			textRow(parent, "Permanent perk for this account.", 1, Theme.Colors.SubText)
		end
	elseif item.Kind == "CoinPack" then
		textRow(parent, "You get <b>🪙 " .. Format.Commas(Shop.CoinPackAmount(item.RefId, data)) .. "</b>", 1, Theme.Colors.Gold)
	elseif item.Kind == "DailyCrate" then
		textRow(parent, "Possible rewards:", 1, Theme.Colors.SubText)
		textRow(parent, "🪙 2-6x price in coins  ·  ⚡ boosts  ·  🐾 a pet", 2)
		textRow(parent, "🎨 a cosmetic  ·  👑 a boss core (rare!)", 3)
		local now = workspace:GetServerTimeNow()
		textRow(parent, "New crate in " .. Format.Clock(DayNight.SecondsUntilNextDay(now)), 4, Theme.Colors.SubText)
	end
end

local function confirmText(item: Shop.ShopItem, state: string): string
	local kind: string = item.Kind
	if state == "Owned" and (kind == "Vacuum" or kind == "Cosmetic") then
		return "Equip"
	elseif state == "Equipped" then
		return if kind == "Cosmetic" then "Unequip" else "Equipped"
	elseif item.Currency == "Robux" then
		return "R$ " .. Format.Commas(item.Price)
	elseif item.Kind == "Capsule" or item.Kind == "DailyCrate" then
		return "Open"
	elseif item.Kind == "Upgrade" then
		return "Upgrade"
	end
	return "Buy"
end

-- Preview -----------------------------------------------------------------------------

local function buildPreview(self, item: Shop.ShopItem, holder: Frame)
	local model: Model? = nil
	if item.Kind == "Vacuum" then
		model = VacuumModel.Build(item.RefId)
	elseif item.Kind == "Trophy" then
		local trophy = Trophies.Get(item.RefId)
		if trophy then
			model = TrophyModel.Build(trophy.Model)
		end
	elseif item.Kind == "Cosmetic" then
		local cosmetic = Cosmetics.Get(item.RefId)
		local vacuumId = self.Deps.ClientData:Equipped()
		model = VacuumModel.Build(vacuumId, { Skin = if cosmetic and cosmetic.Slot == "Skin" then cosmetic.Id else nil })
	end
	if not model then
		UI.Icon({ Glyph = item.Glyph, Rarity = item.Rarity, IconAssetId = item.IconAssetId, Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.05), Parent = holder })
		return
	end
	local rarity = Rarities.Get(item.Rarity)
	-- Stage: dark rounded backdrop with a rarity glow and rotating light rays
	local stage = UI.new("Frame", {
		Name = "Stage",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Backdrop,
		BackgroundTransparency = 0.3,
		Parent = holder,
	}, { UI.Corner(Theme.Radius.Large), UI.Stroke(rarity.Color, 0.3, 2) })
	UI.Gradient(Rarities.ColorSequence(rarity.Id), 135, NumberSequence.new(0.78)).Parent = stage
	UIFx.Glow(stage, rarity.Color, 0.95, 0.9)
	UIFx.Rays(stage, rarity.Color, { Count = 8, Speed = 16, Size = 1, Transparency = if rarity.Rank >= 5 then 0.55 else 0.75 })
	local viewport = UI.new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(170, 170, 190),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -1.2, -0.6),
		ZIndex = 3,
		Parent = holder,
	})
	if rarity.Rank >= 5 then
		self.Trove:Add(UIFx.Sparkles(holder, rarity.Color, 6))
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = 38
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	model.Parent = viewport
	local size = model:GetExtentsSize()
	local radius = math.max(size.X, size.Y, size.Z)
	local center = Vector3.new(0, size.Y / 2, 0)
	-- Glowing turntable under the model
	Builder.Part({
		Name = "Turntable",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, radius * 1.15, radius * 1.15),
		CFrame = CFrame.new(0, -0.1, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = rarity.Color:Lerp(Color3.new(0, 0, 0), 0.55),
		Material = Enum.Material.SmoothPlastic,
		Parent = viewport,
	})
	Builder.Part({
		Name = "Rim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, radius * 1.22, radius * 1.22),
		CFrame = CFrame.new(0, -0.14, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = rarity.Color,
		Material = Enum.Material.Neon,
		Parent = viewport,
	})
	local angle = 0
	local t = 0
	self.Trove:Connect(RunService.RenderStepped, function(dt)
		angle += dt * 0.8
		t += dt
		model:PivotTo(CFrame.new(0, 0.05 + math.sin(t * 1.6) * 0.06 * radius, 0) * CFrame.Angles(0, angle, 0))
		local lift = radius * (0.3 + math.sin(t * 0.7) * 0.06)
		camera.CFrame = CFrame.lookAt(center + Vector3.new(math.sin(t * 0.4) * radius * 0.15, lift, radius * 1.7), center)
	end)
end

-- Show ----------------------------------------------------------------------------------

function ConfirmModal:Show(item: Shop.ShopItem, options: { [string]: any }?)
	self:Close(true)
	local opts = options or {}
	local deps = self.Deps
	local clientData = deps.ClientData
	self.Open = true
	self.Item = item
	self.Gui.Enabled = true
	Audio.Play("Open")

	local backdrop = UI.new("TextButton", {
		Name = "Backdrop",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Backdrop,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Selectable = false,
		Parent = self.Gui,
	})
	self.Trove:Add(backdrop)
	UI.Tween(backdrop, Theme.Tween.Medium, { BackgroundTransparency = 0.45 })
	backdrop.Activated:Connect(function()
		self:Close()
	end)

	local holder = UI.new("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 520),
		BackgroundTransparency = 1,
		Parent = backdrop,
	})
	local autoScale = UI.new("UIScale", { Name = "FitScale", Parent = holder })
	local function fit()
		local viewport = workspace.CurrentCamera.ViewportSize
		local max = math.min((viewport.X - 24) / 560, (viewport.Y - 24) / 520)
		autoScale.Scale = math.min(UI.ScaleFor(viewport), max)
	end
	fit()
	self.Trove:Connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), fit)

	local rarity = Rarities.Get(item.Rarity)
	local card = UI.Glass({
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.04,
		StrokeColor = rarity.Color,
		StrokeTransparency = 0.35,
		Active = true,
		Parent = holder,
	})
	self.Card = card
	self.Holder = holder
	local cardStroke = card:FindFirstChild("Stroke") :: UIStroke
	cardStroke.Thickness = 2
	UI.Gradient(Rarities.ColorSequence(rarity.Id), 0).Parent = cardStroke
	if rarity.Rank >= 4 then
		UIFx.Foil(card, rarity.Id, Theme.Radius.Large, 0.1)
	end
	local scale = UI.GetScale(card)
	-- Morph out of the card that was clicked (if any)
	local from = opts.FromGui
	self.FromGui = from
	if typeof(from) == "Instance" and from:IsA("GuiObject") and from.AbsoluteSize.X > 0 then
		local center = Effects.GuiCenter(from)
		holder.Position = UDim2.fromOffset(center.X, center.Y)
		scale.Scale = math.clamp(from.AbsoluteSize.X / (560 * math.max(autoScale.Scale, 0.01)), 0.15, 0.9)
		card.Rotation = -4
		UI.Tween(holder, TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.5) })
		UI.Tween(scale, TweenInfo.new(0.48, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		UI.Tween(card, TweenInfo.new(0.48, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 })
	else
		scale.Scale = 0.82
		UI.Tween(scale, Theme.Tween.Open, { Scale = 1 })
	end

	-- Header: preview + title block
	local preview = UI.new("Frame", { Position = UDim2.fromOffset(24, 24), Size = UDim2.fromOffset(170, 170), BackgroundTransparency = 1, Parent = card })
	buildPreview(self, item, preview)

	local titleBlock = UI.new("Frame", { Position = UDim2.fromOffset(212, 24), Size = UDim2.new(1, -236, 0, 170), BackgroundTransparency = 1, Parent = card }, { UI.List(Enum.FillDirection.Vertical, 6) })
	UI.RarityTag(item.Rarity, { LayoutOrder = 1, Parent = titleBlock })
	local title = UI.Label({ Text = item.Name, Size = UDim2.new(1, 0, 0, 36), FontFace = Theme.Fonts.Title, TextSize = 30, TextScaled = true, LayoutOrder = 2, Parent = titleBlock })
	UI.new("UITextSizeConstraint", { MaxTextSize = 30, Parent = title })
	UI.Gradient({ Color3.new(1, 1, 1), rarity.Color:Lerp(Color3.new(1, 1, 1), 0.45) }, 90).Parent = title
	UIFx.Typewriter(title, 0.45)
	local category = (function()
		for _, c in Shop.Categories do
			if c.Id == item.Category then
				return c.Name
			end
		end
		return item.Category
	end)()
	UI.Label({
		Text = category .. (if item.World then "  ·  " .. item.World else ""),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 14,
		TextColor3 = Theme.Colors.SubText,
		LayoutOrder = 3,
		Parent = titleBlock,
	})
	UI.Label({
		Text = item.Description,
		Size = UDim2.new(1, 0, 0, 64),
		TextSize = 16,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.SubText,
		LayoutOrder = 4,
		Parent = titleBlock,
	})

	-- Details
	local details = UI.new("ScrollingFrame", {
		Name = "Details",
		Position = UDim2.fromOffset(24, 210),
		Size = UDim2.new(1, -48, 0, 170),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Colors.SubText,
		Parent = card,
	}, { UI.List(Enum.FillDirection.Vertical, 6) })
	detailsFor(item, details, clientData)

	-- Footer: state + price + buttons
	local data = clientData:Get()
	local state, reason = Shop.GetState(item, data, workspace:GetServerTimeNow(), DayNight.IsNight())
	local price = Shop.GetPrice(item, data)
	local currency = Currencies.Get(item.Currency)
	local balance = clientData:Currency(item.Currency)
	local affordable = item.Currency == "Robux" or balance >= price

	local footer = UI.new("Frame", { Name = "Footer", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -20), Size = UDim2.new(1, -48, 0, 112), BackgroundTransparency = 1, Parent = card })
	local priceText
	if state == "Owned" or state == "Equipped" then
		priceText = "✔ Owned"
	elseif item.Currency == "Robux" then
		priceText = "R$ " .. Format.Commas(price)
	else
		priceText = string.format("%s %s", if currency then currency.Glyph else "", Format.Commas(price))
	end
	local priceLabel = UI.Label({
		Text = priceText,
		Size = UDim2.new(0.55, 0, 0, 30),
		FontFace = Theme.Fonts.Numbers,
		TextSize = 26,
		TextColor3 = if state == "Owned" or state == "Equipped" then Theme.Colors.Success elseif affordable then Theme.Colors.Gold else Theme.Colors.Danger,
		Parent = footer,
	})
	UI.Pop(priceLabel, 0.1)
	local infoText = ""
	if state == "Locked" or state == "NightOnly" or state == "Unavailable" or state == "MaxLevel" then
		infoText = "🔒 " .. (reason or state)
	elseif state == "Claimed" then
		infoText = "Claimed today · next in " .. Format.Clock(DayNight.SecondsUntilNextDay(workspace:GetServerTimeNow()))
	elseif item.Currency ~= "Robux" and state == "Available" then
		infoText = if affordable then "Balance after: " .. Format.Abbreviate(balance - price) else "You need " .. Format.Abbreviate(price - balance) .. " more"
	end
	UI.Label({
		Name = "Info",
		Text = infoText,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 4),
		Size = UDim2.new(0.45, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = if state == "Available" and affordable then Theme.Colors.SubText else Theme.Colors.Warning,
		TextSize = 15,
		Parent = footer,
	})
	local errorLabel = UI.Label({
		Name = "Error",
		Text = "",
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = Theme.Colors.Danger,
		TextSize = 15,
		Parent = footer,
	})

	local cancel = UI.Button({
		Name = "Cancel",
		Text = "Cancel",
		Style = "Secondary",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(0.38, -6, 0, 54),
		Parent = footer,
		OnClick = function()
			self:Close()
		end,
	})

	local kind: string = item.Kind
	local equipable = kind == "Vacuum" or kind == "Cosmetic"
	local canConfirm = state == "Available" or (state == "Owned" and equipable) or (state == "Equipped" and kind == "Cosmetic")
	local confirm: UI.Button
	confirm = UI.Button({
		Name = "Confirm",
		Text = confirmText(item, state),
		Style = if item.Currency == "Robux" then "Success" elseif state == "Available" then "Gold" else "Primary",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(0.62, -6, 0, 54),
		TextSize = 22,
		Enabled = canConfirm and (affordable or state ~= "Available"),
		Parent = footer,
		OnClick = function()
			confirm:SetLoading(true)
			errorLabel.Text = ""
			local result
			if state == "Available" then
				result = deps.Purchase(item, opts.Source or "Classic")
			else
				result = deps.Equip(item)
			end
			if not self.Open or self.Item ~= item then
				return
			end
			confirm:SetLoading(false)
			if result.Ok then
				if opts.OnResult then
					task.spawn(opts.OnResult, result)
				end
				confirm:SetStyle("Success")
				confirm:SetText("✔")
				UI.Pop(confirm.Instance, 0.2)
				UIFx.Burst(Effects.Layer(), Effects.GuiCenter(confirm.Instance), Theme.Colors.Success, 20, 120)
				if state == "Available" then
					UIFx.Stamp(card, if result.Pending then "CHECKOUT…" else "PURCHASED!", rarity.Color:Lerp(Color3.new(1, 1, 1), 0.25), 0.5)
				end
				task.wait(0.55)
				self:Close()
			else
				errorLabel.Text = result.Error or "Something went wrong."
				UI.Shake(card)
				Audio.Play("Error")
			end
		end,
	})
	if not (affordable or state ~= "Available") then
		errorLabel.Text = "Not enough " .. (if currency then currency.Name else item.Currency) .. "."
	end
	if confirm.Enabled then
		self.Trove:Add(UIFx.Shine(confirm.Instance, 2.6, 0.25))
		self.Trove:Connect(confirm.Instance.Activated, function()
			UIFx.Ripple(confirm.Instance)
		end)
	end

	-- Close button
	UI.Button({
		Text = "✕",
		Style = "Ghost",
		Size = UDim2.fromOffset(40, 40),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Radius = Theme.Radius.Pill,
		Parent = card,
		OnClick = function()
			self:Close()
		end,
	})

	ContextActionService:BindActionAtPriority("ShopModalBack", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			self:Close()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 5, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	self.Trove:Add(function()
		ContextActionService:UnbindAction("ShopModalBack")
	end)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = if confirm.Enabled then confirm.Instance else cancel.Instance
	end
	self.Trove:Add(confirm)
	self.Trove:Add(cancel)
end

function ConfirmModal:Close(immediate: boolean?)
	if not self.Open then
		return
	end
	self.Open = false
	self.Item = nil
	if not immediate then
		Audio.Play("Close")
	end
	local card = self.Card
	local trove = self.Trove
	self.Trove = Trove.new()
	local from = self.FromGui
	self.FromGui = nil
	if card and not immediate then
		if typeof(from) == "Instance" and from.Parent and (from :: GuiObject).AbsoluteSize.X > 0 and self.Holder then
			-- shrink back into the card it came from
			local center = Effects.GuiCenter(from :: GuiObject)
			UI.Tween(self.Holder, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(center.X, center.Y) })
			UI.Tween(UI.GetScale(card), TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.25 })
			UI.Tween(card, TweenInfo.new(0.22), { BackgroundTransparency = 1 })
		else
			UI.Tween(UI.GetScale(card), Theme.Tween.Close, { Scale = 0.85 })
		end
		local backdrop = self.Gui:FindFirstChild("Backdrop")
		if backdrop then
			UI.Tween(backdrop, Theme.Tween.Close, { BackgroundTransparency = 1 })
		end
		task.delay(0.22, function()
			trove:Clean()
			if not self.Open then
				self.Gui.Enabled = false
			end
		end)
	else
		trove:Clean()
		self.Gui.Enabled = false
	end
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.Gui) then
		GuiService.SelectedObject = nil
	end
end

return ConfirmModal
