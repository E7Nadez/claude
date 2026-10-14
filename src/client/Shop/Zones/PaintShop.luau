-- Paint shop: your equipped vacuum rides the paint line through the spray
-- booth; skins are sprayed on live part by part, trails are attached on the
-- way through. Browse cosmetics with the carousel, buy or equip from the panel.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Definitions = Shared.Definitions
local Cosmetics = require(Definitions.Cosmetics)
local Vacuums = require(Definitions.Vacuums)
local Rarities = require(Definitions.Rarities)
local Factory = require(Definitions.Factory)
local Shop = require(Definitions.Shop)
local DayNight = require(Shared.Util.DayNight)
local Trove = require(Shared.Util.Trove)
local VacuumModel = require(Shared.Models.VacuumModel)

local ShopFolder = script.Parent.Parent
local Audio = require(ShopFolder.Audio)
local Effects = require(ShopFolder.Effects)
local CameraDirector = require(ShopFolder.CameraDirector)

local PaintShop = {}
PaintShop.__index = PaintShop

function PaintShop.new(view)
	local self = setmetatable({}, PaintShop)
	self.View = view
	self.Trove = Trove.new()
	self.ModeTrove = Trove.new()
	self.Trove:Add(self.ModeTrove, "Clean")
	self.Line = view:Find("PaintShop/Line") :: BasePart?
	self.Nozzles = {}
	for _, nozzle in view:Tagged("SprayNozzle") do
		if nozzle:IsA("BasePart") then
			table.insert(self.Nozzles, nozzle)
		end
	end
	self.List = {}
	for _, cosmetic in Cosmetics.BySlot("Skin") do
		table.insert(self.List, cosmetic)
	end
	for _, cosmetic in Cosmetics.BySlot("Trail") do
		table.insert(self.List, cosmetic)
	end
	self.Index = 1
	self.Active = false
	self.Trove:Connect(view.Controller.ClientData.Changed, function()
		if self.Active and not self.Running then
			self:_showPanel()
		end
	end)
	return self
end

function PaintShop:_lineEnds(): (Vector3, Vector3)
	local config = Factory.PaintShop
	local y = config.LineHeight
	return self.View:ToWorld(Vector3.new(config.LineStartX + 3, y, config.LineZ)), self.View:ToWorld(Vector3.new(config.LineEndX - 3, y, config.LineZ))
end

function PaintShop:_spawnDisplay(skinId: string?)
	if self.Display then
		self.Display:Destroy()
	end
	local controller = self.View.Controller
	local vacuumId = controller.ClientData:Equipped()
	local model = VacuumModel.Build(vacuumId, { Skin = skinId })
	model.Parent = self.View.LocalFolder
	self.Display = model
	self.ModeTrove:Add(model)
	local startPos, endPos = self:_lineEnds()
	model:PivotTo(CFrame.lookAt(startPos, endPos) * CFrame.Angles(0, math.pi / 2, 0))
	return model
end

-- Drives the model through the booth; parts recolor as they pass the spray plane.
function PaintShop:_run(cosmetic: Cosmetics.Cosmetic)
	if self.Running then
		return
	end
	self.Running = true
	local controller = self.View.Controller
	local current = controller.ClientData:Get()
	local currentSkin = current and current.Cosmetics.Skin
	local model = self:_spawnDisplay(currentSkin)
	local vacuum = Vacuums.Get(model:GetAttribute("VacuumId"))
	local targetLook = if vacuum and cosmetic.Slot == "Skin" then VacuumModel.SkinnedLook(vacuum.Look, cosmetic.Id) else nil
	local startPos, endPos = self:_lineEnds()
	local rotation = CFrame.lookAt(startPos, endPos).Rotation * CFrame.Angles(0, math.pi / 2, 0)
	local boothX = self.View:ToWorld(Vector3.new(Factory.PaintShop.BoothX, 0, Factory.PaintShop.LineZ))
	local axis = (endPos - startPos).Unit
	local boothAlong = (boothX - startPos):Dot(axis)
	local painted = {}
	local trail = nil
	local emitters = {}
	local color = if cosmetic.Slot == "Skin" then (cosmetic.Glow or cosmetic.Body or Color3.new(1, 1, 1)) else (cosmetic.Colors and cosmetic.Colors[1] or Color3.new(1, 1, 1))
	for _, nozzle in self.Nozzles do
		local attachment = Instance.new("Attachment")
		local aim = nozzle:GetAttribute("Aim")
		attachment.WorldCFrame = CFrame.lookAt(nozzle.Position, if typeof(aim) == "Vector3" then aim else nozzle.Position - Vector3.yAxis) * CFrame.Angles(-math.pi / 2, 0, 0)
		attachment.Parent = workspace.Terrain
		local emitter = Effects.Emitter(attachment, "Paint", color, 60)
		table.insert(emitters, emitter)
		self.ModeTrove:Add(attachment)
	end
	local spray = Audio.Loop("Spray", self.Nozzles[1])
	if spray then
		self.ModeTrove:Add(spray)
		spray.Volume = 0
	end
	local camera = self.View:ToWorld(Factory.PaintShop.Camera)
	local duration = 4.2
	local start = os.clock()
	local length = (endPos - startPos).Magnitude
	local finished = false
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not model.Parent then
			connection:Disconnect()
			return
		end
		local alpha = math.clamp((os.clock() - start) / duration, 0, 1)
		local along = alpha * length
		local cf = CFrame.new(startPos + axis * along) * rotation
		model:PivotTo(cf)
		CameraDirector.Snap(CFrame.lookAt(camera:Lerp(Vector3.new(cf.Position.X, camera.Y, camera.Z), 0.5), cf.Position + Vector3.new(0, 1.5, 0)))
		local near = math.abs(along - boothAlong) < 6
		for _, emitter in emitters do
			emitter.Enabled = near
		end
		if spray then
			spray.Volume = if near then 0.25 else 0
		end
		if targetLook then
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and not painted[part] and part:GetAttribute("Role") then
					if (part.Position - startPos):Dot(axis) >= boothAlong then
						painted[part] = true
						local props = VacuumModel.RoleProps(part:GetAttribute("Role"), targetLook)
						part.Material = props.Material or part.Material
						TweenService:Create(part, TweenInfo.new(0.35), { Color = props.Color, Transparency = props.Transparency, Reflectance = props.Reflectance }):Play()
					end
				end
			end
		elseif cosmetic.Slot == "Trail" and not trail and along >= boothAlong then
			trail = VacuumModel.AttachTrail(model, cosmetic.Id)
			Effects.Burst(cf.Position + Vector3.new(0, 2, 0), "Glow", 16, color)
		end
		if alpha >= 1 and not finished then
			finished = true
			connection:Disconnect()
			for _, emitter in emitters do
				emitter.Enabled = false
			end
			Effects.Burst(cf.Position + Vector3.new(0, 2, 0), "Sparks", 30, color)
			Audio.Play("Success")
			self.Running = false
			if self.Active then
				self:_showPanel()
			end
		end
	end)
	self.ModeTrove:Add(connection)
end

function PaintShop:_selected(): Cosmetics.Cosmetic
	return self.List[self.Index]
end

function PaintShop:_showPanel()
	local controller = self.View.Controller
	local data = controller.ClientData:Get()
	local cosmetic = self:_selected()
	local item = cosmetic and Shop.Get(cosmetic.Id)
	if not cosmetic or not item or not data then
		return
	end
	local state, reason = Shop.GetState(item, data, workspace:GetServerTimeNow(), DayNight.IsNight())
	local buttons = {
		{
			Id = "Preview",
			Text = "Preview",
			Glyph = "🎨",
			Style = "Primary",
			Enabled = not self.Running,
			OnClick = function()
				self:_run(cosmetic)
			end,
		},
	}
	if state == "Available" then
		table.insert(buttons, 1, {
			Id = "Buy",
			Text = "Buy",
			Glyph = "🛒",
			Style = "Gold",
			Enabled = Shop.CanAfford(item, data),
			OnClick = function()
				self:_buy(cosmetic)
			end,
		})
	elseif state == "Owned" or state == "Equipped" then
		table.insert(buttons, 1, {
			Id = "Equip",
			Text = if state == "Equipped" then "Unequip" else "Equip",
			Style = if state == "Equipped" then "Secondary" else "Primary",
			OnClick = function()
				controller:Equip(item)
			end,
		})
	end
	controller.FactoryHud:ShowPanel({
		Title = cosmetic.Name,
		Rarity = cosmetic.Rarity,
		Lines = { cosmetic.Description, (if cosmetic.Slot == "Skin" then "🎨 Skin" else "✨ Trail") .. "  ·  applies to every vacuum" },
		Price = if state == "Available" or state == "NightOnly" then { Amount = item.Price, Currency = item.Currency, Affordable = Shop.CanAfford(item, data) } else nil,
		Status = if state == "Owned" then "✔ Owned" elseif state == "Equipped" then "● Equipped" elseif state ~= "Available" then "🔒 " .. (reason or state) else nil,
		Buttons = buttons,
	})
	controller.FactoryHud:SetCarouselLabel(string.format("%d / %d", self.Index, #self.List))
end

function PaintShop:_buy(cosmetic: Cosmetics.Cosmetic)
	local controller = self.View.Controller
	local item = Shop.Get(cosmetic.Id)
	if not item or self.Buying then
		return
	end
	self.Buying = true
	local result = controller:RequestPurchase(item)
	self.Buying = false
	if not result.Ok then
		controller.Hud:Toast(result.Error or "Purchase failed.", "Error")
		return
	end
	local booth = self.View:ToWorld(Vector3.new(Factory.PaintShop.BoothX, 10, Factory.PaintShop.LineZ))
	controller:CoinFlight(result.Currency or "Coins", result.Price or 0, booth)
	local rarity = Rarities.Get(cosmetic.Rarity)
	Effects.Confetti(booth, 60, { rarity.Gradient[1], rarity.Gradient[2], Color3.new(1, 1, 1) })
	controller.Hud:Banner({ Title = cosmetic.Name, Subtitle = "Equipped  ·  " .. rarity.Name, Rarity = cosmetic.Rarity, Style = "Small" })
	self:_run(cosmetic)
end

function PaintShop:Enter()
	local controller = self.View.Controller
	if not controller:EnterMode("PaintShop", function()
		self.Active = false
		self.Running = false
		self.ModeTrove:Clean()
		self.Display = nil
		controller.FactoryHud:HidePanel()
		controller.FactoryHud:HideCarousel()
		controller.FactoryHud:SetHint(nil)
	end) then
		return
	end
	self.Active = true
	local data = controller.ClientData:Get()
	self:_spawnDisplay(data and data.Cosmetics.Skin)
	local startPos, endPos = self:_lineEnds()
	local camera = self.View:ToWorld(Factory.PaintShop.Camera)
	CameraDirector.GlideTo(CFrame.lookAt(camera, (startPos + endPos) / 2 + Vector3.new(0, 1.5, 0)), 0.8, Enum.EasingStyle.Quint, 62)
	controller.FactoryHud:ShowCarousel(function()
		if not self.Running then
			self.Index = (self.Index - 2) % #self.List + 1
			self:_showPanel()
		end
	end, function()
		if not self.Running then
			self.Index = self.Index % #self.List + 1
			self:_showPanel()
		end
	end)
	controller.FactoryHud:SetHint("[Keys] Browse paint jobs  ·  [Back] Back")
	self:_showPanel()
end

function PaintShop:Destroy()
	self.Trove:Clean()
end

return PaintShop
