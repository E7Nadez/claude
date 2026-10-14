-- ShopController: the single client entry point for the shop.
-- Owns the classic window, confirm modal and factory HUD, creates a
-- FactoryView per Mega-Factory, routes proximity prompts, runs purchase
-- requests (the server decides everything), coordinates camera / controls for
-- focus modes and shows, reacts to other players' purchases, and cancels every
-- sequence cleanly on death or when the player leaves the factory.

local ContextActionService = game:GetService("ContextActionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Definitions = Shared.Definitions
local Factory = require(Definitions.Factory)
local Rarities = require(Definitions.Rarities)
local Currencies = require(Definitions.Currencies)
local Sequences = require(Definitions.Sequences)
local Pets = require(Definitions.Pets)
local Boosts = require(Definitions.Boosts)
local Cosmetics = require(Definitions.Cosmetics)
local Shop = require(Definitions.Shop)
local Format = require(Shared.Util.Format)

local ShopFolder = script.Parent.Parent:WaitForChild("Shop")
local ConfirmModal = require(ShopFolder.ConfirmModal)
local ClassicShop = require(ShopFolder.ClassicShop)
local FactoryHud = require(ShopFolder.FactoryHud)
local FactoryView = require(ShopFolder.FactoryView)
local CameraDirector = require(ShopFolder.CameraDirector)
local Effects = require(ShopFolder.Effects)
local Audio = require(ShopFolder.Audio)
local PurchaseShow = require(ShopFolder.Shows.PurchaseShow)
local EntryShow = require(ShopFolder.Shows.EntryShow)

local ShopController = {}

local LOCAL_PLAYER = Players.LocalPlayer
local CHEER_ANIMATION = "rbxassetid://507770677" -- default R15 "cheer" emote

local ROOM_TO_ZONE = {
	Lobby = "Lobby",
	TestChamber = "TestChamber",
	Showroom = "Showroom",
	UpgradeLab = "UpgradeLab",
	CapsuleHall = "CapsuleHall",
	PaintShop = "PaintShop",
	VaultCorridor = "TrophyVault",
	TrophyVault = "TrophyVault",
}

local views: { [Instance]: any } = {}
local currentView: any = nil
local mode: { Name: string, OnExit: () -> () }? = nil
local activeShow: any = nil
local entryCooldown = 0
local controlsLocked = false
local lastLowGraphics: boolean? = nil

-- Character helpers -------------------------------------------------------------------

function ShopController:GetRoot(): BasePart?
	local character = LOCAL_PLAYER.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function ShopController:GetHumanoid(): Humanoid?
	local character = LOCAL_PLAYER.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function ShopController:Teleport(cf: CFrame)
	local character = LOCAL_PLAYER.Character
	local root = self:GetRoot()
	if not character or not root then
		return
	end
	character:PivotTo(cf)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

function ShopController:SetCharacterHidden(hidden: boolean)
	local character = LOCAL_PLAYER.Character
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

function ShopController:PlayCheer()
	local humanoid = self:GetHumanoid()
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = CHEER_ANIMATION
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track:Play(0.1)
		task.delay(2.4, function()
			track:Stop(0.3)
			track:Destroy()
		end)
	end
end

local playerModule = nil
local function setControls(enabled: boolean)
	if not playerModule then
		local ok, module = pcall(function()
			return require(LOCAL_PLAYER:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any
		end)
		if ok then
			playerModule = module
		end
	end
	if playerModule then
		local controls = playerModule:GetControls()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end
end

local function lockControls(locked: boolean)
	if controlsLocked == locked then
		return
	end
	controlsLocked = locked
	setControls(not locked)
	ProximityPromptService.Enabled = not locked
end

-- Modes & shows --------------------------------------------------------------------------

local function bindModeKeys(self)
	ContextActionService:BindActionAtPriority("ShopModeBack", function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin or self.Modal:IsOpen() or activeShow then
			return Enum.ContextActionResult.Pass
		end
		self:ExitMode()
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.Medium.Value, Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB)
	ContextActionService:BindActionAtPriority("ShopModeNav", function(_, inputState, input)
		if inputState ~= Enum.UserInputState.Begin or self.Modal:IsOpen() or activeShow then
			return Enum.ContextActionResult.Pass
		end
		local hud = self.FactoryHud
		if not hud.Carousel.Visible then
			return Enum.ContextActionResult.Pass
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Left or key == Enum.KeyCode.A or key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.ButtonL1 then
			if hud.OnPrev then
				hud.OnPrev()
			end
		elseif hud.OnNext then
			hud.OnNext()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.Medium.Value, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.A, Enum.KeyCode.D, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
end

local function unbindModeKeys()
	ContextActionService:UnbindAction("ShopModeBack")
	ContextActionService:UnbindAction("ShopModeNav")
end

-- Enters a focus mode (camera + panel). Leaving the previous mode first.
function ShopController:EnterMode(name: string, onExit: () -> ()): boolean
	if activeShow then
		return false
	end
	if mode and mode.Name == name then
		mode.OnExit = onExit
		return true
	end
	if mode then
		local previous = mode
		mode = nil
		local ok, err = pcall(previous.OnExit)
		if not ok then
			warn("[ShopController] mode exit failed:", err)
		end
		self.FactoryHud:HidePanel()
		self.FactoryHud:HideCarousel()
	end
	if self.Classic.IsOpen then
		self.Classic:Close()
	end
	mode = { Name = name, OnExit = onExit }
	CameraDirector.Acquire("Shop", true)
	lockControls(true)
	bindModeKeys(self)
	self.FactoryHud:ShowBack(function()
		self:ExitMode(name)
	end)
	return true
end

function ShopController:ExitMode(name: string?)
	if not mode or (name and mode.Name ~= name) then
		return
	end
	local previous = mode
	mode = nil
	local ok, err = pcall(previous.OnExit)
	if not ok then
		warn("[ShopController] mode exit failed:", err)
	end
	unbindModeKeys()
	self.FactoryHud:HideBack()
	self.FactoryHud:HidePanel()
	self.FactoryHud:HideCarousel()
	self.FactoryHud:SetHint(nil)
	if not activeShow then
		CameraDirector.Release("Shop")
		lockControls(false)
	end
end

function ShopController:CurrentMode(): string?
	return mode and mode.Name
end

function ShopController:IsBusy(): boolean
	return activeShow ~= nil
end

function ShopController:BeginShow(seq, options: { Skippable: boolean? }?)
	if activeShow and activeShow ~= seq then
		activeShow:Cancel()
	end
	activeShow = seq
	self.Modal:Close(true)
	if self.Classic.IsOpen then
		self.Classic:Close()
	end
	CameraDirector.Acquire("Shop", true)
	lockControls(true)
	self.FactoryHud:SetCinematic(true)
	self.Hud:SetSideVisible(false)
	if not options or options.Skippable ~= false then
		self.Hud:ShowSkip(function()
			seq:Skip()
		end)
	end
end

function ShopController:EndShow(seq)
	if activeShow ~= seq then
		return
	end
	activeShow = nil
	self.Hud:HideSkip()
	self.FactoryHud:SetCinematic(false)
	self.Hud:SetSideVisible(true)
	if not mode then
		CameraDirector.Release("Shop")
		lockControls(false)
	end
end

function ShopController:CancelAll()
	if activeShow then
		activeShow:Cancel()
	end
	self:ExitMode()
	self.Modal:Close(true)
	CameraDirector.Release()
	lockControls(false)
	self:SetCharacterHidden(false)
	self.Hud:HideSkip()
end

-- Travel ---------------------------------------------------------------------------------

function ShopController:ViewFor(worldId: string): any
	for _, view in views do
		if view.World == worldId then
			return view
		end
	end
	return nil
end

function ShopController:TravelTo(view: any, zoneId: string, after: (() -> ())?)
	if not view or activeShow then
		return
	end
	local zone
	for _, z in Factory.Zones do
		if z.Id == zoneId then
			zone = z
		end
	end
	if not zone then
		return
	end
	task.spawn(function()
		self:ExitMode()
		self.Hud:Fade(0, 0.18)
		local spot = view:ToWorld(zone.Spot)
		local face = view.Origin:VectorToWorldSpace(zone.Face)
		self:Teleport(CFrame.lookAt(spot, spot + face))
		Audio.Play("Tube", { Speed = 1.6, Volume = 0.3 })
		task.wait(0.12)
		self.Hud:Fade(1, 0.3)
		if after then
			after()
		end
	end)
end

-- Purchases ------------------------------------------------------------------------------

local function promptRobux(item: Shop.ShopItem): { [string]: any }
	if item.Kind == "Gamepass" then
		if (item.GamePassId or 0) == 0 then
			return { Ok = false, Code = "UNAVAILABLE", Error = "This gamepass is not set up yet." }
		end
		MarketplaceService:PromptGamePassPurchase(LOCAL_PLAYER, item.GamePassId :: number)
	else
		if (item.ProductId or 0) == 0 then
			return { Ok = false, Code = "UNAVAILABLE", Error = "This product is not set up yet." }
		end
		MarketplaceService:PromptProductPurchase(LOCAL_PLAYER, item.ProductId :: number)
	end
	return { Ok = true, Pending = true }
end

-- Sends the request. The server validates price, balance, unlocks, limits.
function ShopController:RequestPurchase(item: Shop.ShopItem): { [string]: any }
	if item.Currency == "Robux" then
		return promptRobux(item)
	end
	self.Hud:HoldCurrency(item.Currency, self.Hud:ShownCurrency(item.Currency))
	local result
	if item.Kind == "Upgrade" then
		result = Net.Invoke("PurchaseUpgrade", item.RefId)
	else
		result = Net.Invoke("PurchaseItem", item.Id)
	end
	if not result.Ok then
		self.Hud:ReleaseCurrency(item.Currency)
		Audio.Play("Error")
	end
	return result
end

-- Coins fly from the HUD to a world position / screen point / GUI object.
function ShopController:CoinFlight(currencyId: string, amount: number, target: any, onCoin: ((number) -> ())?): number
	local anchor = self.Hud:GetCurrencyAnchor(currencyId)
	if not anchor or amount <= 0 then
		self.Hud:ReleaseCurrency(currencyId)
		return 0
	end
	local from = Effects.GuiCenter(anchor)
	local to: Vector2
	if typeof(target) == "Vector3" then
		to = Effects.ToScreen(target)
	elseif typeof(target) == "Vector2" then
		to = target
	elseif typeof(target) == "Instance" and target:IsA("GuiObject") then
		to = Effects.GuiCenter(target)
	else
		local size = workspace.CurrentCamera.ViewportSize
		to = size / 2
	end
	local currency = Currencies.Get(currencyId)
	local count = math.clamp(math.floor(math.log10(amount + 1) * 2.5), 4, 16)
	local duration = Effects.CoinFlight(from, to, count, currency and currency.Glyph, onCoin)
	self.Hud:ReleaseCurrency(currencyId, duration)
	return duration
end

-- Effects for purchases outside of a factory show (classic window etc.).
function ShopController:_celebrate(item: Shop.ShopItem, result: { [string]: any }, source: string)
	local view = currentView
	if source == "Factory" and view and item.Kind == "Vacuum" and item.World == view.World then
		PurchaseShow.Play(view, item.RefId, result)
		return
	end
	local button = self.Classic.IsOpen and self.Classic:CelebrateFrom(item.Id)
	self:CoinFlight(item.Currency, result.Price or 0, button or nil)
	Audio.Play("Success")
	local rarityId = result.Rarity or item.Rarity
	local rarity = Rarities.Get(rarityId)
	local profile = Sequences.Get(rarityId)
	if item.Kind == "Vacuum" then
		self.Hud:Banner({ Title = item.Name, Subtitle = "New vacuum  ·  " .. rarity.Name, Rarity = rarityId, Style = profile.Banner })
		Effects.ScreenFlash(rarity.Color, 0.25, 0.6)
		Effects.UIConfetti(math.floor(profile.Confetti / 2), { rarity.Gradient[1], rarity.Gradient[2], Color3.new(1, 1, 1) })
	elseif item.Kind == "Capsule" then
		local pet = Pets.Get(result.PetId)
		self.Hud:Banner({ Title = if pet then pet.Name else "New pet", Subtitle = "You hatched  ·  " .. rarity.Name, Rarity = rarityId, Style = profile.Banner })
		if Rarities.AtLeast(rarityId, "Rare") then
			Effects.UIConfetti(math.floor(profile.Confetti / 2), { rarity.Gradient[1], rarity.Gradient[2] })
		end
	elseif item.Kind == "DailyCrate" then
		local reward = result.Reward or {}
		local text = reward.Name or "Reward"
		if reward.Kind == "Coins" then
			text = "+" .. Format.Abbreviate(reward.Amount or 0) .. " Coins"
		end
		self.Hud:Banner({ Title = text, Subtitle = "Mystery Crate  ·  " .. rarity.Name, Rarity = rarityId, Style = profile.Banner })
		Effects.UIConfetti(40)
	elseif item.Kind == "Upgrade" then
		self.Hud:Toast(string.format("%s upgraded to Lv %d!", item.Name, result.Level or 0), "Success")
	elseif item.Kind == "Boost" then
		local boost = Boosts.Get(item.RefId)
		self.Hud:Banner({ Title = item.Name, Subtitle = "Boost active  ·  " .. Format.Duration(boost and boost.Duration or 0), Rarity = rarityId, Style = "Small" })
	elseif item.Kind == "Cosmetic" then
		self.Hud:Banner({ Title = item.Name, Subtitle = "Equipped  ·  " .. rarity.Name, Rarity = rarityId, Style = "Small" })
	elseif item.Kind == "Trophy" then
		self.Hud:Banner({ Title = item.Name, Subtitle = "Trophy unlocked  ·  " .. rarity.Name, Rarity = rarityId, Style = "Big" })
		Effects.UIConfetti(60)
	end
end

-- Used by the confirm modal: request + presentation.
function ShopController:Purchase(item: Shop.ShopItem, source: string): { [string]: any }
	local result = self:RequestPurchase(item)
	if result.Ok and not result.Pending then
		task.spawn(function()
			self:_celebrate(item, result, source)
		end)
	end
	return result
end

function ShopController:EquipVacuum(vacuumId: string): { [string]: any }
	local result = Net.Invoke("EquipVacuum", vacuumId)
	if result.Ok then
		Audio.Play("Success")
	else
		self.Hud:Toast(result.Error or "Could not equip.", "Error")
	end
	return result
end

function ShopController:Equip(item: Shop.ShopItem): { [string]: any }
	if item.Kind == "Vacuum" then
		return self:EquipVacuum(item.RefId)
	elseif item.Kind == "Cosmetic" then
		local cosmetic = Cosmetics.Get(item.RefId)
		local data = self.ClientData:Get()
		if not cosmetic or not data then
			return { Ok = false, Error = "Not available." }
		end
		local equipped = data.Cosmetics[cosmetic.Slot] == cosmetic.Id
		local result = Net.Invoke("EquipCosmetic", cosmetic.Slot, if equipped then nil else cosmetic.Id)
		if result.Ok then
			Audio.Play("Success")
			self.Hud:Toast(if equipped then cosmetic.Name .. " removed." else cosmetic.Name .. " equipped!", "Success")
		else
			self.Hud:Toast(result.Error or "Could not equip.", "Error")
		end
		return result
	end
	return { Ok = false, Error = "Nothing to equip." }
end

-- Prompts / broadcasts -------------------------------------------------------------------

local function viewForInstance(instance: Instance): any
	for model, view in views do
		if instance:IsDescendantOf(model) then
			return view
		end
	end
	return nil
end

function ShopController:_onPrompt(prompt: ProximityPrompt, player: Player)
	if player ~= LOCAL_PLAYER or activeShow then
		return
	end
	local action = prompt:GetAttribute("ShopAction")
	if not action then
		return
	end
	local view = viewForInstance(prompt)
	if not view then
		return
	end
	local target = prompt:GetAttribute("Target")
	local zones = view.Zones
	if action == "Browse" and zones.Showroom then
		zones.Showroom:Browse()
	elseif action == "Podium" and zones.Showroom then
		zones.Showroom:Browse(zones.Showroom:IndexOf(target))
	elseif action == "Upgrade" and zones.UpgradeLab then
		zones.UpgradeLab:Focus(target)
	elseif action == "Capsule" and zones.CapsuleHall then
		zones.CapsuleHall:Focus(target)
	elseif action == "Paint" and zones.PaintShop then
		zones.PaintShop:Enter()
	elseif action == "Vault" and zones.TrophyVault then
		zones.TrophyVault:TryOpen()
	elseif action == "Trophy" and zones.TrophyVault then
		zones.TrophyVault:Focus(target)
	elseif action == "DailyCrate" and zones.Lobby then
		zones.Lobby:Focus()
	elseif action == "NightDeals" then
		self.Classic:Open("Deals")
	end
end

local function escapeRich(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local VERBS = {
	Vacuum = "bought the",
	Capsule = "hatched a",
	Upgrade = "upgraded",
	Boost = "activated",
	Cosmetic = "unlocked",
	Trophy = "claimed the",
	DailyCrate = "found",
	Gamepass = "unlocked",
	CoinPack = "bought",
}

function ShopController:_onBroadcast(payload: any)
	if type(payload) ~= "table" or type(payload.ItemName) ~= "string" or type(payload.UserId) ~= "number" then
		return
	end
	local isMe = payload.UserId == LOCAL_PLAYER.UserId
	local rarityId = if Rarities.Info[payload.Rarity] then payload.Rarity else "Common"
	local rarity = Rarities.Get(rarityId)
	local position = if typeof(payload.Position) == "Vector3" then payload.Position else nil
	local sameFactory = currentView ~= nil and payload.World == currentView.World

	if not isMe and (payload.Scope == "Server" or (payload.Scope == "Factory" and sameFactory)) then
		local verb = VERBS[payload.Kind] or "got"
		self.Hud:Feed(string.format("<b>%s</b> %s <font color=\"#%s\">%s</font>!", escapeRich(tostring(payload.DisplayName or "?")), verb, rarity.Color:ToHex(), escapeRich(payload.ItemName)), rarityId)
		if rarityId == "Mythic" then
			Effects.ScreenFlash(rarity.Color, 0.2, 0.8)
		end
	end

	for _, view in views do
		if view.Near and payload.World == view.World then
			local workers = view.Zones.Workers
			if workers then
				workers:React(position, rarityId, isMe)
			end
			if not isMe and position then
				Effects.Confetti(position + Vector3.new(0, 3, 0), 8 * rarity.Rank, { rarity.Gradient[1], rarity.Gradient[2] }, 0.6)
				Effects.Burst(position, "Glow", 6 * rarity.Rank, rarity.Color)
			end
			if not isMe and payload.Kind == "Capsule" and view.Zones.CapsuleHall then
				local item = Shop.Get(payload.ItemId)
				if item then
					view.Zones.CapsuleHall:RemoteOpened(item.RefId, rarityId)
				end
			end
		end
	end
end

-- Lifecycle -------------------------------------------------------------------------------

local function applySettings(self)
	local low = self.ClientData:LowGraphics()
	local reduce = self.ClientData:ReduceMotion()
	Effects.SetLowGraphics(low)
	Effects.SetReduceMotion(reduce)
	CameraDirector.SetReduceMotion(reduce)
	if lastLowGraphics ~= nil and lastLowGraphics ~= low then
		for _, view in views do
			view:QualityChanged()
		end
	end
	lastLowGraphics = low
end

local function addFactory(self, model: Instance)
	if not model:IsA("Model") or views[model] then
		return
	end
	if not model:WaitForChild("Origin", 30) then
		return
	end
	local ok, view = pcall(FactoryView.new, model, self)
	if ok then
		views[model] = view
	else
		warn("[ShopController] factory view failed:", view)
	end
end

local function removeFactory(model: Instance)
	local view = views[model]
	if view then
		if currentView == view then
			currentView = nil
		end
		views[model] = nil
		view:Destroy()
	end
end

local function inTrigger(part: BasePart, position: Vector3): boolean
	local p = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y + 3 and math.abs(p.Z) <= half.Z
end

function ShopController:_tick()
	local root = self:GetRoot()
	local position = root and root.Position
	local inside = nil
	for _, view in views do
		local near = position ~= nil and view:DistanceTo(position) < 280
		local isInside = position ~= nil and view:Contains(position)
		view:SetActive(near, isInside)
		if isInside then
			inside = view
		end
		if position and near and not activeShow and not mode and os.clock() > entryCooldown then
			local trigger = view:Find("Entrance/EntryTrigger")
			if trigger and trigger:IsA("BasePart") and inTrigger(trigger, position) then
				entryCooldown = os.clock() + 4
				if self.ClientData:Setting("ClassicShop") == true then
					local back = view:ToWorld(Vector3.new(0, 3, -22))
					self:Teleport(CFrame.lookAt(back, back + view.Origin:VectorToWorldSpace(Vector3.new(0, 0, -1))))
					self.Classic:Open()
				else
					EntryShow.Play(view)
				end
			end
		end
	end
	if inside ~= currentView then
		currentView = inside
		if not inside and mode and mode.Name ~= "TestChamber" then
			self:ExitMode()
		end
	end
	local showHud = currentView ~= nil
	if self.FactoryHud.Visible ~= showHud then
		self.FactoryHud:SetVisible(showHud)
		if activeShow then
			self.FactoryHud:SetCinematic(true)
		end
	end
	if currentView and position then
		local room = currentView:RoomAt(position)
		self.FactoryHud:HighlightZone(room and ROOM_TO_ZONE[room])
	end
end

function ShopController:Init(controllers)
	self.ClientData = controllers.ClientData
	self.Hud = controllers.HudController
end

function ShopController:Start()
	self.Modal = ConfirmModal.new({
		ClientData = self.ClientData,
		Purchase = function(item, source)
			return self:Purchase(item, source)
		end,
		Equip = function(item)
			return self:Equip(item)
		end,
	})
	self.Classic = ClassicShop.new({ ClientData = self.ClientData, Modal = self.Modal, Hud = self.Hud })
	self.FactoryHud = FactoryHud.new({
		OnTravel = function(zoneId)
			self:TravelTo(currentView, zoneId)
		end,
		OnClassic = function()
			self:ExitMode()
			self.Classic:Open()
		end,
		OnExit = function()
			if currentView and not activeShow then
				EntryShow.Exit(currentView)
			end
		end,
	})

	self.Hud.ShopRequested:Connect(function()
		if not activeShow then
			self.Classic:Toggle()
		end
	end)
	ContextActionService:BindAction("ShopToggle", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and not activeShow and not self.Modal:IsOpen() then
			self.Classic:Toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonY)

	self.ClientData.SettingsChanged:Connect(function()
		applySettings(self)
	end)
	applySettings(self)

	local folder = workspace:WaitForChild(Factory.FolderName)
	folder.ChildAdded:Connect(function(child)
		addFactory(self, child)
	end)
	folder.ChildRemoved:Connect(removeFactory)
	for _, child in folder:GetChildren() do
		task.spawn(addFactory, self, child)
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		self:_onPrompt(prompt, player)
	end)
	Net.Event("ShopBroadcast").OnClientEvent:Connect(function(payload)
		self:_onBroadcast(payload)
	end)

	local function onCharacter(character: Model)
		self:CancelAll()
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.Died:Connect(function()
				self:CancelAll()
			end)
		end
	end
	LOCAL_PLAYER.CharacterAdded:Connect(onCharacter)
	if LOCAL_PLAYER.Character then
		task.spawn(onCharacter, LOCAL_PLAYER.Character)
	end
	LOCAL_PLAYER.CharacterRemoving:Connect(function()
		self:CancelAll()
	end)

	task.spawn(function()
		while true do
			local ok, err = pcall(self._tick, self)
			if not ok then
				warn("[ShopController] tick:", err)
			end
			task.wait(0.1)
		end
	end)
end

return ShopController
