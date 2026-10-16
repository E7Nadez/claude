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
	-- Bumped by every Show: late callbacks (purchase replies, clicks on a card that is still
	-- shrinking away) only act on the modal they belong to.
	self.Session = 0
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

-- Helpers ---------------------------------------------------------------------------

local TEXT_FADE = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" }
local IMAGE_FADE = { "BackgroundTransparency", "ImageTransparency" }
local SCROLL_FADE = { "BackgroundTransparency", "ScrollBarImageTransparency" }
local FRAME_FADE = { "BackgroundTransparency" }
local STROKE_FADE = { "Transparency" }

local function fadePropsOf(object: Instance): { string }?
	if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
		return TEXT_FADE
	elseif object:IsA("ImageLabel") or object:IsA("ImageButton") or object:IsA("ViewportFrame") then
		return IMAGE_FADE
	elseif object:IsA("ScrollingFrame") then
		return SCROLL_FADE
	elseif object:IsA("GuiObject") then
		return FRAME_FADE
	elseif object:IsA("UIStroke") then
		return STROKE_FADE
	end
	return nil
end

-- Fades a whole card in (from hidden to its built look) or out: text, images, the 3D
-- preview and every stroke together. No CanvasGroup, which would clip the glow and stamp
-- and blur the text while the card is zoomed. Fading in skips values that start hidden
-- (sparkles fade themselves in); fading out overrides every running fade-in.
local function fadeSubtree(root: Instance, info: TweenInfo, show: boolean)
	local objects = root:GetDescendants()
	table.insert(objects, root)
	for _, object in objects do
		local props = fadePropsOf(object)
		if props then
			local target = object :: any
			local goal = {}
			local changed = false
			for _, prop in props do
				local value = target[prop]
				if not show then
					goal[prop] = 1
					changed = true
				elseif value < 1 then
					goal[prop] = value
					target[prop] = 1
					changed = true
				end
			end
			if changed then
				UI.Tween(object, info, goal)
			end
		end
	end
end

-- Ends an endless tween (rays, foil) by overriding it with an instant one.
local function stopLoop(instance: Instance?, property: string)
	if instance and instance.Parent then
		UI.Tween(instance, TweenInfo.new(0), { [property] = (instance :: any)[property] })
	end
end

-- Same words as the shop's own celebration (ShopController._celebrate).
local function stampText(item: Shop.ShopItem): string
	if item.Kind == "Capsule" or item.Kind == "DailyCrate" then
		return "OPENED!"
	elseif item.Kind == "Upgrade" then
		return "UPGRADED!"
	end
	return "PURCHASED!"
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
		-- Big jumps (starter -> late-game vacuum) read as a multiplier: "x700", not "+69,900%".
		local deltaLabel = UI.Label({
			Text = if vacuumId == equippedId then "equipped" elseif math.abs(d) < 0.005 then "=" elseif d >= 9.995 then "x" .. Format.Stat(math.floor(1 + d + 0.5)) else Format.Percent(d, true),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0, 58, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = color,
			FontFace = Theme.Fonts.Numbers,
			TextSize = 14,
			TextScaled = true,
			Parent = row,
		})
		UI.new("UITextSizeConstraint", { MaxTextSize = 14, MinTextSize = 9, Parent = deltaLabel })
	end
end

local function textRow(parent: Frame, text: string, order: number, color: Color3?): TextLabel
	return UI.Label({
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

-- `tickers` collects refresh functions for the live countdowns (called once a second).
local function detailsFor(item: Shop.ShopItem, parent: Frame, clientData: any, tickers: { () -> () })
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
			if level >= upgrade.MaxLevel then
				-- Fully upgraded: no "next level" that does not exist.
				textRow(parent, string.format("Level <b>%d</b>  (max level)", level), 1, Theme.Colors.Gold)
				textRow(parent, string.format("%s %s: <b>%s</b>", Stats.Glyphs[upgrade.Stat], Stats.Labels[upgrade.Stat], Format.Percent(now, true)), 2)
			else
				local nextValue = (Upgrades.Multiplier(item.RefId, level + 1) - 1)
				textRow(parent, string.format("Level <b>%d</b> → <b>%d</b>  (max %d)", level, level + 1, upgrade.MaxLevel), 1)
				textRow(parent, string.format("%s %s: <b>%s</b> → <font color=\"#40D68C\"><b>%s</b></font>", Stats.Glyphs[upgrade.Stat], Stats.Labels[upgrade.Stat], Format.Percent(now, true), Format.Percent(nextValue, true)), 2)
			end
		end
	elseif item.Kind == "Boost" then
		local boost = Boosts.Get(item.RefId)
		if boost then
			textRow(parent, string.format("⏱ Duration: <b>%s</b> (stacks up to %s)", Format.Duration(boost.Duration), Format.Duration(boost.MaxDuration)), 1)
			local expires = data and data.Boosts[item.RefId] or 0
			if expires - workspace:GetServerTimeNow() > 0 then
				local active = textRow(parent, "", 2, Theme.Colors.Success)
				local function refresh()
					local remaining = expires - workspace:GetServerTimeNow()
					active.Text = if remaining > 0 then "Active: " .. Format.Clock(remaining) .. " left" else "Expired"
					active.TextColor3 = if remaining > 0 then Theme.Colors.Success else Theme.Colors.SubText
				end
				refresh()
				table.insert(tickers, refresh)
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
		local countdown = textRow(parent, "", 4, Theme.Colors.SubText)
		local function refresh()
			countdown.Text = "New crate in " .. Format.Clock(DayNight.SecondsUntilNextDay(workspace:GetServerTimeNow()))
		end
		refresh()
		table.insert(tickers, refresh)
	end
end

local function confirmText(item: Shop.ShopItem, state: string): string
	local kind: string = item.Kind
	if state == "Owned" and (kind == "Vacuum" or kind == "Cosmetic") then
		return "Equip"
	elseif state == "Equipped" then
		return if kind == "Cosmetic" then "Unequip" else "Equipped"
	elseif state == "Owned" then
		return "Owned"
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

-- ViewportFrames do not draw Trails, so a trail cosmetic gets a glowing ribbon along the
-- path the back of the spinning vacuum just swept, fading out like the real trail. Built
-- in the model's pivot space around the spin axis, so it turns with the model.
local function trailRibbon(model: Model, cosmetic: any, center: Vector3, size: Vector3)
	local colors: { Color3 } = cosmetic.Colors or { Color3.new(1, 1, 1) }
	local segments = if Effects.IsLow() then 6 else 12
	local span = 1.1 + (cosmetic.Lifetime or 0.6)
	-- Never taller than the model, so it cannot dip into the turntable.
	local width = math.min(cosmetic.Width or 1, size.Y * 0.8)
	local radius = size.Z / 2
	local pivot = model:GetPivot()
	local function point(k: number): Vector3
		local a = -span * k / segments
		return center + Vector3.new(math.sin(a) * radius, 0, math.cos(a) * radius)
	end
	for k = 1, segments do
		local a, b = point(k - 1), point(k)
		local f = (k - 0.5) / segments
		local index = f * (#colors - 1)
		local lower = math.floor(index)
		Builder.Part({
			Name = "TrailRibbon",
			Size = Vector3.new(0.08, width * (1 - 0.8 * f), (b - a).Magnitude + 0.04),
			CFrame = pivot * CFrame.lookAt((a + b) / 2, b),
			Color = colors[lower + 1]:Lerp(colors[math.min(lower + 2, #colors)], index - lower),
			Material = Enum.Material.Neon,
			Transparency = 0.1 + 0.85 * f,
			CastShadow = false,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Parent = model,
		})
	end
end

local function buildPreview(self, item: Shop.ShopItem, holder: Frame)
	local calm = Effects.ReduceMotion()
	local model: Model? = nil
	local trail = nil
	if item.Kind == "Vacuum" then
		model = VacuumModel.Build(item.RefId)
	elseif item.Kind == "Trophy" then
		local trophy = Trophies.Get(item.RefId)
		if trophy then
			model = TrophyModel.Build(trophy.Model)
		end
	elseif item.Kind == "Cosmetic" then
		local cosmetic = Cosmetics.Get(item.RefId)
		local clientData = self.Deps.ClientData
		local data = clientData:Get()
		-- On the player's own vacuum: a skin repaints it, a trail keeps the paint it has.
		local equippedSkin = if data and data.Cosmetics then data.Cosmetics.Skin else nil
		model = VacuumModel.Build(clientData:Equipped(), { Skin = if cosmetic and cosmetic.Slot == "Skin" then cosmetic.Id else equippedSkin })
		if cosmetic and cosmetic.Slot == "Trail" then
			trail = cosmetic
		end
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
	local rays = UIFx.Rays(stage, rarity.Color, { Count = 8, Speed = 16, Size = 1, Transparency = if rarity.Rank >= 5 then 0.55 else 0.75 })
	-- Still rays under Reduce Motion; otherwise the endless spin ends with the modal.
	if calm then
		stopLoop(rays, "Rotation")
	else
		self.Trove:Add(function()
			stopLoop(rays, "Rotation")
		end)
	end
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
		local stopSparkles = UIFx.Sparkles(holder, rarity.Color, 6)
		self.Trove:Add(stopSparkles)
		-- No new sparkle pops in while the card fades out.
		self.StopSparkles = stopSparkles
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = 38
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	model.Parent = viewport
	-- Models pivot on their Root, which is neither centred nor always at the bottom: spin
	-- around the middle of the bounding box, with its base resting on the turntable.
	local boxCf, size = model:GetBoundingBox()
	local center = model:GetPivot():PointToObjectSpace(boxCf.Position)
	local base = CFrame.new(-center.X, size.Y / 2 - center.Y, -center.Z)
	if trail then
		trailRibbon(model, trail, center, size)
	end
	local extent = math.max(size.X, size.Y, size.Z)
	-- The plate fits the footprint the model sweeps while it turns.
	local plate = math.max(math.sqrt(size.X ^ 2 + size.Z ^ 2) / 2 * 1.08, extent * 0.3)
	-- The bob only lifts the model off the plate, never into it.
	local bob = if calm then 0 else extent * 0.035
	-- Glowing turntable under the model
	Builder.Part({
		Name = "Turntable",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, plate * 2, plate * 2),
		CFrame = CFrame.new(0, -0.1, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = rarity.Color:Lerp(Color3.new(0, 0, 0), 0.55),
		Material = Enum.Material.SmoothPlastic,
		Parent = viewport,
	})
	Builder.Part({
		Name = "Rim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, plate * 2.12, plate * 2.12),
		CFrame = CFrame.new(0, -0.14, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = rarity.Color,
		Material = Enum.Material.Neon,
		Parent = viewport,
	})
	-- Frame the whole stage (rim and the model at the top of its bob) with its bounding
	-- sphere, so the square viewport never cuts it from any angle of the camera sway.
	local bottom, top = -0.2, 0.04 + bob + size.Y
	local focus = Vector3.new(0, (bottom + top) / 2, 0)
	local sphere = math.sqrt((plate * 1.06) ^ 2 + ((top - bottom) / 2) ^ 2)
	local distance = sphere / math.sin(math.rad(camera.FieldOfView / 2)) * 1.03
	local angle = 0
	local t = 0
	local function step(dt: number)
		angle += dt * 0.8
		t += dt
		model:PivotTo(CFrame.new(0, 0.04 + bob * (0.5 + 0.5 * math.sin(t * 1.6)), 0) * CFrame.Angles(0, angle, 0) * base)
		-- Reduce Motion: a fixed camera (the slow turn stays).
		local sway = if calm then 0 else t
		local direction = Vector3.new(math.sin(sway * 0.4) * 0.09, 0.2 + math.sin(sway * 0.7) * 0.035, 1).Unit
		camera.CFrame = CFrame.lookAt(focus + direction * distance, focus)
	end
	step(0)
	self.Trove:Connect(RunService.RenderStepped, step)
end

-- Show ----------------------------------------------------------------------------------

function ConfirmModal:Show(item: Shop.ShopItem, options: { [string]: any }?)
	self:Close(true)
	local opts = options or {}
	local deps = self.Deps
	local clientData = deps.ClientData
	local calm = Effects.ReduceMotion()
	self.Session += 1
	local session = self.Session
	self.Open = true
	self.Item = item
	self.Gui.Enabled = true
	-- Gamepad: the selection goes back here when the modal closes.
	local selected = GuiService.SelectedObject
	self.PrevSelection = if selected and not selected:IsDescendantOf(self.Gui) then selected else nil
	Audio.Play("Open")

	-- Closing by the player (Cancel, ✕, backdrop, B / Backspace). Ignored while a purchase
	-- request is in flight (it would still go through, unseen) and for clicks on an older
	-- modal that is still shrinking away.
	local busy = false
	local function closeByPlayer()
		if self.Session == session and self.Open and not busy then
			self:Close()
		end
	end

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
	self.Backdrop = backdrop
	UI.Tween(backdrop, Theme.Tween.Medium, { BackgroundTransparency = 0.45 })
	local openedAt = os.clock()
	backdrop.Activated:Connect(function()
		-- The second click of a double-click on a shop card lands here while the card is
		-- still flying to the centre: that is not a request to close.
		if os.clock() - openedAt >= 0.4 then
			closeByPlayer()
		end
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
	-- Centre-anchored, so its zoom (PopScale) stays centred on the holder.
	local card = UI.Glass({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.04,
		StrokeColor = rarity.Color,
		StrokeTransparency = 0.35,
		Active = true,
		-- Gamepad selection cannot wander to the shop grid behind the modal.
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
		Parent = holder,
	})
	self.Card = card
	self.Holder = holder
	local cardStroke = card:FindFirstChild("Stroke") :: UIStroke
	cardStroke.Thickness = 2
	UI.Gradient(Rarities.ColorSequence(rarity.Id), 0).Parent = cardStroke
	if rarity.Rank >= 4 then
		local foil = UIFx.Foil(card, rarity.Id, Theme.Radius.Large, 0.1)
		self.Trove:Add(function()
			stopLoop(foil:FindFirstChildOfClass("UIGradient"), "Offset")
		end)
	end
	local scale = UI.GetScale(card)
	-- Morph out of the card that was clicked (if any). Position and zoom only: a rotated
	-- ancestor would switch off the buttons' clipping (their parked shine bars would show).
	local from = opts.FromGui
	self.FromGui = from
	if not calm and typeof(from) == "Instance" and from:IsA("GuiObject") and from.AbsoluteSize.X > 0 then
		local center = Effects.GuiCenter(from)
		holder.Position = UDim2.fromOffset(center.X, center.Y)
		scale.Scale = math.clamp(from.AbsoluteSize.X / (560 * math.max(autoScale.Scale, 0.01)), 0.15, 0.9)
		UI.Tween(holder, TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.5) })
		UI.Tween(scale, TweenInfo.new(0.48, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	elseif calm then
		-- Reduce Motion: no flight and no overshoot, just a fade with a hint of zoom.
		scale.Scale = 0.96
		UI.Tween(scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
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
	local tickers: { () -> () } = {}
	detailsFor(item, details, clientData, tickers)

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
	elseif state == "MaxLevel" then
		-- Not the price of a level that does not exist.
		priceText = "MAX LEVEL"
	elseif item.Currency == "Robux" then
		priceText = "R$ " .. Format.Commas(price)
	else
		priceText = string.format("%s %s", if currency then currency.Glyph else "", Format.Commas(price))
	end
	local priceLabel = UI.Label({
		Text = priceText,
		Size = UDim2.new(0.5, 0, 0, 30),
		FontFace = Theme.Fonts.Numbers,
		TextSize = 26,
		TextColor3 = if state == "Owned" or state == "Equipped" then Theme.Colors.Success elseif state == "MaxLevel" or affordable then Theme.Colors.Gold else Theme.Colors.Danger,
		Parent = footer,
	})
	UI.Pop(priceLabel, 0.1)
	local function infoText(): string
		if state == "Locked" or state == "NightOnly" or state == "Unavailable" then
			return "🔒 " .. (reason or state)
		elseif state == "Claimed" then
			return "Next crate in " .. Format.Clock(DayNight.SecondsUntilNextDay(workspace:GetServerTimeNow()))
		elseif item.Currency ~= "Robux" and state == "Available" then
			return if affordable then "Balance after: " .. Format.Abbreviate(balance - price) else "You need " .. Format.Abbreviate(price - balance) .. " more"
		end
		return ""
	end
	-- Shrinks long lock reasons to fit instead of cutting them off.
	local info = UI.Label({
		Name = "Info",
		Text = infoText(),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 4),
		Size = UDim2.new(0.5, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = if state == "Available" and affordable then Theme.Colors.SubText else Theme.Colors.Warning,
		TextSize = 15,
		TextScaled = true,
		Parent = footer,
	})
	UI.new("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 10, Parent = info })
	if state == "Claimed" then
		table.insert(tickers, function()
			info.Text = infoText()
		end)
	end
	-- Live countdowns (boost time left, next daily crate)
	if #tickers > 0 then
		self.Trove:Add(task.spawn(function()
			while true do
				task.wait(1)
				for _, refresh in tickers do
					refresh()
				end
			end
		end))
	end
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
		OnClick = closeByPlayer,
	})

	local kind: string = item.Kind
	local equipable = kind == "Vacuum" or kind == "Cosmetic"
	local canConfirm = state == "Available" or (state == "Owned" and equipable) or (state == "Equipped" and kind == "Cosmetic")
	-- One request per modal: a double click must not buy twice (or equip and unequip again).
	local submitted = false
	local shakeReady = 0
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
			-- Also ignores a click that reaches this card while it is closing.
			if submitted or self.Session ~= session or not self.Open then
				return
			end
			submitted = true
			busy = true
			cancel:SetEnabled(false)
			confirm:SetLoading(true)
			errorLabel.Text = ""
			-- A request that never answers must not trap the player in the modal.
			self.Trove:Add(task.delay(6, function()
				if busy then
					busy = false
					cancel:SetEnabled(true)
				end
			end))
			local result
			if state == "Available" then
				result = deps.Purchase(item, opts.Source or "Classic")
			else
				result = deps.Equip(item)
			end
			if self.Session ~= session or not self.Open then
				return
			end
			busy = false
			confirm:SetLoading(false)
			if result.Ok then
				if opts.OnResult then
					task.spawn(opts.OnResult, result)
				end
				-- Extra clicks on the result do nothing (no error shake either).
				confirm.Instance.Interactable = false
				local hold = 0.25
				if result.Pending then
					-- Roblox shows its own purchase prompt now; nothing is bought until the
					-- player confirms it there, so no success effects here.
					confirm:SetText("Checkout…")
					hold = 0.3
				else
					confirm:SetStyle("Success")
					confirm:SetText("✔")
					UI.Pop(confirm.Instance, 0.2)
					UIFx.Burst(Effects.Layer(), Effects.GuiCenter(confirm.Instance), Theme.Colors.Success, 20, 120)
					-- Opened from a shop card, the modal shrinks back into it and that card
					-- celebrates (stamp, reveal); anywhere else the modal shows the stamp.
					local handOff = typeof(from) == "Instance" and from.Parent ~= nil
					if state == "Available" and not handOff and not calm then
						UIFx.Stamp(card, stampText(item), rarity.Color:Lerp(Color3.new(1, 1, 1), 0.25), 0.5)
						hold = 0.45
					end
				end
				-- Short hold: the celebration waits for the modal to get out of the way.
				task.wait(hold)
				if self.Session == session and self.Open then
					self:Close()
				end
			else
				submitted = false
				cancel:SetEnabled(true)
				errorLabel.Text = result.Error or "Something went wrong."
				if calm then
					errorLabel.TextTransparency = 1
					UI.Tween(errorLabel, Theme.Tween.Medium, { TextTransparency = 0 })
				elseif os.clock() >= shakeReady then
					-- One shake at a time (a shake started mid-shake would keep its offset).
					shakeReady = os.clock() + 0.25
					UI.Shake(card)
				end
				Audio.Play("Error")
				if UserInputService.GamepadEnabled and GuiService.SelectedObject == nil then
					GuiService.SelectedObject = confirm.Instance
				end
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
		OnClick = closeByPlayer,
	})

	-- Unbound in Close (not by the delayed cleanup, which would unbind a newer modal's action).
	ContextActionService:BindActionAtPriority("ShopModalBack", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			closeByPlayer()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 5, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = if confirm.Enabled then confirm.Instance else cancel.Instance
	end
	self.Trove:Add(confirm)
	self.Trove:Add(cancel)

	-- The whole card fades in with its zoom: text, 3D preview, strokes and buttons together.
	fadeSubtree(card, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), true)
end

-- Whether the gamepad selection can go back to `object` once the modal is gone.
local function canRestoreSelection(object: GuiObject, modalGui: ScreenGui): boolean
	local screen = object:FindFirstAncestorOfClass("ScreenGui")
	return screen ~= nil
		and screen ~= modalGui
		and screen.Enabled
		and screen:IsDescendantOf(Players.LocalPlayer)
		and object.Visible
		and object.Selectable
end

function ConfirmModal:Close(immediate: boolean?)
	if not self.Open then
		return
	end
	self.Open = false
	self.Item = nil
	ContextActionService:UnbindAction("ShopModalBack")
	if not immediate then
		Audio.Play("Close")
	end
	local card = self.Card
	local holder = self.Holder
	local backdrop = self.Backdrop
	local trove = self.Trove
	local session = self.Session
	self.Trove = Trove.new()
	self.Card = nil
	self.Holder = nil
	self.Backdrop = nil
	local from = self.FromGui
	self.FromGui = nil
	if self.StopSparkles then
		self.StopSparkles()
		self.StopSparkles = nil
	end
	-- Gamepad: back to what was selected before the modal opened (the card's Buy button).
	local previous = self.PrevSelection
	self.PrevSelection = nil
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(self.Gui) then
		GuiService.SelectedObject = if previous and canRestoreSelection(previous, self.Gui) then previous else nil
	end
	if card and holder and backdrop and not immediate then
		local calm = Effects.ReduceMotion()
		if not calm and typeof(from) == "Instance" and from:IsA("GuiObject") and from.Parent and from.AbsoluteSize.X > 0 then
			-- shrink back into the card it came from
			local center = Effects.GuiCenter(from :: GuiObject)
			UI.Tween(holder, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(center.X, center.Y) })
			UI.Tween(UI.GetScale(card), TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.25 })
		else
			UI.Tween(UI.GetScale(card), Theme.Tween.Close, { Scale = if calm then 0.96 else 0.85 })
		end
		-- Everything on the card fades out with it, not just its background.
		fadeSubtree(card, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), false)
		UI.Tween(backdrop, Theme.Tween.Close, { BackgroundTransparency = 1 })
		task.delay(0.22, function()
			trove:Clean()
			-- A modal opened (and maybe closed) meanwhile owns the ScreenGui now.
			if not self.Open and self.Session == session then
				self.Gui.Enabled = false
			end
		end)
	else
		trove:Clean()
		self.Gui.Enabled = false
	end
end

return ConfirmModal
