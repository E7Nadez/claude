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
local TweenService = game:GetService("TweenService")

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
local UIFx = require(ShopFolder.UI.UIFx)
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
-- Bumped by CancelAll (death, respawn): a waiting presentation must not start afterwards.
local lifeToken = 0

-- Handing the camera back: a short glide to where the follow camera picks up, then the
-- release. Any acquire / release in between invalidates the pending one.
local GLIDE_OUT = 0.4
local releaseToken = 0
local glidingOut = false
-- The follow camera's zoom, pitch (look Y) and focus height before the shop took it.
local followPose = { Zoom = 12.5, Pitch = -0.35, Height = 1.5 }

-- The local player's own purchase is broadcast before its request returns, seconds before
-- the show / reveal that presents the result: the world reaction (worker cheer, glow,
-- fireworks) is held back until then.
local reactionHolds = 0
local heldReaction: { View: any, Rarity: string, Position: Vector3? }? = nil

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
	-- A glide back to the player would now chase them across the factory: hand the
	-- camera back at once (teleports happen under a black screen).
	if glidingOut then
		releaseToken += 1
		glidingOut = false
		CameraDirector.Release("Shop")
	end
	character:PivotTo(cf)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

-- Turns the default follow camera to look along `direction` (behind the character) at
-- its zoom and pitch. After a teleport, under the black screen: the follow camera keeps
-- its old yaw otherwise, and the player arrives looking at a wall.
function ShopController:AimFollowCamera(direction: Vector3)
	local root = self:GetRoot()
	local flat = direction * Vector3.new(1, 0, 1)
	if CameraDirector.IsActive() or not root or flat.Magnitude < 0.01 then
		return
	end
	local camera = workspace.CurrentCamera
	local zoom = math.clamp((camera.CFrame.Position - camera.Focus.Position).Magnitude, 0.5, 128)
	local y = math.clamp(camera.CFrame.LookVector.Y, -0.75, 0.1)
	local look = flat.Unit * math.sqrt(1 - y * y) + Vector3.new(0, y, 0)
	local focus = root.Position + Vector3.new(0, math.clamp(followPose.Height, 0, 4), 0)
	-- The follow camera takes its look direction from the current CFrame.
	camera.CFrame = CFrame.lookAt(focus - look * zoom, focus)
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

-- Camera hand-over ----------------------------------------------------------------------

-- Takes the camera for a mode / show. Remembers how the follow camera framed the player,
-- so releaseCamera can glide back to exactly that framing.
local function acquireCamera()
	releaseToken += 1
	local wasGliding = glidingOut
	glidingOut = false
	local camera = workspace.CurrentCamera
	if not CameraDirector.IsActive() then
		local root = ShopController:GetRoot()
		local focus = camera.Focus.Position
		followPose.Zoom = (camera.CFrame.Position - focus).Magnitude
		followPose.Pitch = camera.CFrame.LookVector.Y
		followPose.Height = if root then focus.Y - root.Position.Y else 1.5
	end
	CameraDirector.Acquire("Shop", true)
	if wasGliding then
		-- Stopped mid-glide: hold this frame (not the previous owner's last shot) until the
		-- new mode / show moves the camera.
		CameraDirector.Snap(camera.CFrame, camera.FieldOfView)
	end
end

-- How far behind `focus` the follow camera can sit before something solid is in the way
-- (roughly its own occlusion check: see-through and non-colliding parts do not count).
local function clearDistance(focus: Vector3, look: Vector3, zoom: number, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local list = table.clone(ignore)
	for _ = 1, 4 do
		params.FilterDescendantsInstances = list
		local hit = workspace:Raycast(focus, -look * zoom, params)
		if not hit then
			return zoom
		end
		if hit.Instance.Transparency < 0.25 then
			return math.max(hit.Distance - 0.5, 0.5)
		end
		table.insert(list, hit.Instance)
	end
	return zoom
end

-- Hands the camera back to the follow camera without a jump cut: glides to where that
-- camera will pick up (along the current view towards the player, at the zoom and pitch
-- it had before), then releases. First person, no character or far away: released at once.
local function releaseCamera(self)
	releaseToken += 1
	glidingOut = false
	if not CameraDirector.IsActive() then
		return
	end
	local camera = workspace.CurrentCamera
	local character = LOCAL_PLAYER.Character
	local root = self:GetRoot()
	local zoom = math.min(followPose.Zoom, 128)
	if not character or not root or zoom < 2 then
		CameraDirector.Release("Shop")
		return
	end
	local flat = (root.Position - camera.CFrame.Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude < 1 then
		flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	if flat.Magnitude < 0.01 then
		CameraDirector.Release("Shop")
		return
	end
	local y = math.clamp(followPose.Pitch, -0.75, 0.1)
	local look = flat.Unit * math.sqrt(1 - y * y) + Vector3.new(0, y, 0)
	local height = math.clamp(followPose.Height, 0, 4)
	local ignore = { character :: Instance }
	local function pose(): CFrame
		-- follows the player, who can walk again during the glide
		local current = self:GetRoot() or root
		local focus = current.Position + Vector3.new(0, height, 0)
		return CFrame.lookAt(focus - look * clearDistance(focus, look, zoom, ignore), focus)
	end
	local from = camera.CFrame
	local offset = pose().Position - from.Position
	local distance = offset.Magnitude
	-- A long way or through a wall (e.g. a skipped tube ride): a cut is cleaner than a swoop.
	if distance > 60 or (distance > 0.5 and clearDistance(from.Position, -offset.Unit, distance, ignore) < distance) then
		CameraDirector.Release("Shop")
		return
	end
	local fovFrom = camera.FieldOfView
	local fovTo = CameraDirector.BaseFov()
	local start = os.clock()
	CameraDirector.Follow(function()
		local alpha = math.clamp((os.clock() - start) / GLIDE_OUT, 0, 1)
		local e = TweenService:GetValue(alpha, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		camera.FieldOfView = fovFrom + (fovTo - fovFrom) * e
		return from:Lerp(pose(), e)
	end)
	glidingOut = true
	local token = releaseToken
	task.delay(GLIDE_OUT + 0.05, function()
		if releaseToken == token then
			glidingOut = false
			CameraDirector.Release("Shop")
		end
	end)
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
	-- (the settings card would sit over the focus shot and its panel)
	self.Hud:CloseSettings()
	mode = { Name = name, OnExit = onExit }
	acquireCamera()
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
		releaseCamera(self)
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
	-- (shrinks away under the letterbox instead of blinking out)
	self.Modal:Close()
	if self.Classic.IsOpen then
		self.Classic:Close()
	end
	acquireCamera()
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
		releaseCamera(self)
		lockControls(false)
	end
	-- (fallback for a show that did not play its purchase's world reaction itself)
	if reactionHolds == 0 then
		self:PlayPurchaseReactions()
	end
end

function ShopController:CancelAll()
	lifeToken += 1
	heldReaction = nil
	if activeShow then
		activeShow:Cancel()
	end
	self:ExitMode()
	self.Modal:Close(true)
	-- No glide here: the camera goes back at once.
	releaseToken += 1
	glidingOut = false
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
		self:AimFollowCamera(face)
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

-- Holds the local player's own purchase reaction back until its result is presented.
-- Returns the release; a hold also lets go by itself (a request or reveal that hangs).
local function holdReactions(self): () -> ()
	reactionHolds += 1
	local released = false
	local function release()
		if released then
			return
		end
		released = true
		reactionHolds -= 1
		if reactionHolds == 0 and not activeShow then
			self:PlayPurchaseReactions()
		end
	end
	task.delay(12, release)
	return release
end

-- Waits until the confirm modal has closed and shrunk away (it stamps its success first).
local function waitForModal(self, timeout: number)
	local modal = self.Modal
	if not modal:IsOpen() then
		return
	end
	local deadline = os.clock() + timeout
	while modal:IsOpen() and os.clock() < deadline do
		task.wait()
	end
	task.wait(0.22) -- ConfirmModal's close animation
end

-- Sends the request. The server validates price, balance, unlocks, limits.
function ShopController:RequestPurchase(item: Shop.ShopItem): { [string]: any }
	if item.Currency == "Robux" then
		return promptRobux(item)
	end
	self.Hud:HoldCurrency(item.Currency, self.Hud:ShownCurrency(item.Currency))
	-- The server broadcasts the purchase before it answers. Released once the caller has
	-- started its show (callers do that right after this returns, before yielding).
	local release = holdReactions(self)
	local result
	if item.Kind == "Upgrade" then
		result = Net.Invoke("PurchaseUpgrade", item.RefId)
	else
		result = Net.Invoke("PurchaseItem", item.Id)
	end
	task.defer(release)
	if not result.Ok then
		self.Hud:ReleaseCurrency(item.Currency)
		Audio.Play("Error")
	end
	return result
end

-- Coins fly from the HUD to a world position / screen point / GUI object. The held
-- counter counts down to the live balance, or to `shownTarget` (a reward of the same
-- currency still to be revealed; the counter then stays held until that reveal).
function ShopController:CoinFlight(currencyId: string, amount: number, target: any, onCoin: ((number) -> ())?, shownTarget: number?): number
	local anchor = self.Hud:GetCurrencyAnchor(currencyId)
	if not anchor or amount <= 0 then
		self.Hud:ReleaseCurrency(currencyId, nil, shownTarget)
		return 0
	end
	-- The pill itself, not its position now: as a show starts the HUD column slides down
	-- below the letterbox, and the later coins leave from where it is then.
	local from = anchor
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
	self.Hud:ReleaseCurrency(currencyId, duration, shownTarget)
	return duration
end

-- Effects for purchases outside of a factory show (classic window etc.).
function ShopController:_celebrate(item: Shop.ShopItem, result: { [string]: any }, source: string)
	local view = currentView
	if source == "Factory" and view and item.Kind == "Vacuum" and item.World == view.World then
		-- The confirm modal stamps its success and shrinks away first: the show (letterbox,
		-- camera) starts once it is gone instead of cutting the modal off mid-spinner.
		local release = holdReactions(self)
		local life = lifeToken
		waitForModal(self, 3)
		local seq = if life == lifeToken and views[view.Model] == view and not activeShow then PurchaseShow.Play(view, item.RefId, result) else nil
		if not seq then
			-- No show will release the coin counter RequestPurchase held.
			self.Hud:ReleaseCurrency(item.Currency)
		end
		release()
		return
	end
	local rarityId = result.Rarity or item.Rarity
	local rarity = Rarities.Get(rarityId)
	local profile = Sequences.Get(rarityId)
	local stamp = if item.Kind == "Capsule" or item.Kind == "DailyCrate" then "OPENED!" elseif item.Kind == "Upgrade" then "UPGRADED!" else "PURCHASED!"
	local button = self.Classic.IsOpen and self.Classic:CelebrateFrom(item.Id, stamp, rarityId)
	-- A Mystery Crate paying out coins of the currency it cost: the counter only counts the
	-- price off here, and counts the reward up once its coins fly in from the reveal.
	local reward = if type(result.Reward) == "table" then result.Reward else {}
	local price = result.Price or 0
	local payout = item.Kind == "DailyCrate" and reward.Kind == "Coins" and (reward.Currency or "Coins") == item.Currency and (reward.Amount or 0) > 0
	local paid = self:CoinFlight(item.Currency, price, button or nil, nil, if payout then self.Hud:ShownCurrency(item.Currency) - price else nil)
	Audio.Play("Success")
	local classicOpen = self.Classic.IsOpen
	if item.Kind == "Vacuum" then
		self.Hud:Banner({ Title = item.Name, Subtitle = "New vacuum  ·  " .. rarity.Name, Rarity = rarityId, Style = profile.Banner })
		Effects.ScreenFlash(rarity.Color, 0.25, 0.6)
		Effects.UIConfetti(math.floor(profile.Confetti / 2), { rarity.Gradient[1], rarity.Gradient[2], Color3.new(1, 1, 1) })
	elseif item.Kind == "Capsule" then
		local pet = Pets.Get(result.PetId)
		if classicOpen then
			self.Classic:Reveal({
				Title = if pet then pet.Name else "New pet",
				Subtitle = if pet then string.format("x%s coin multiplier", Format.Stat(pet.Multiplier)) else nil,
				Glyph = "🐾",
				Rarity = rarityId,
				BackColor = Rarities.Get(item.Rarity).Color:Lerp(Color3.new(0, 0, 0), 0.4),
			})
		else
			self.Hud:Banner({ Title = if pet then pet.Name else "New pet", Subtitle = "You hatched  ·  " .. rarity.Name, Rarity = rarityId, Style = profile.Banner })
		end
	elseif item.Kind == "DailyCrate" then
		local text = reward.Name or "Reward"
		if reward.Kind == "Coins" then
			text = "+" .. Format.Abbreviate(reward.Amount or 0) .. " Coins"
		end
		if classicOpen then
			self.Classic:Reveal({ Title = text, Subtitle = "From today's Mystery Crate", Glyph = "📦", Rarity = rarityId, BackColor = Color3.fromRGB(90, 64, 30) })
		else
			self.Hud:Banner({ Title = text, Subtitle = "Mystery Crate  ·  " .. rarity.Name, Rarity = rarityId, Style = profile.Banner })
			Effects.UIConfetti(40)
		end
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

	-- The classic window's reveal flips its card once the modal is gone and the card has
	-- wobbled (ClassicShop:Reveal): the world reaction and a coin payout wait for that.
	local flipping = classicOpen and (item.Kind == "Capsule" or item.Kind == "DailyCrate")
	if not flipping and not payout then
		return
	end
	local start = os.clock()
	if flipping then
		local release = holdReactions(self)
		waitForModal(self, 3)
		-- zoom-in, 0.3 s per wobble, the flip (+ a few frames of slack)
		task.wait(0.45 + profile.CapsuleWobble * 0.3 + 0.25)
		release()
	end
	if payout then
		-- (after the price has been counted off)
		local remaining = paid + 0.15 - (os.clock() - start)
		if remaining > 0 then
			task.wait(remaining)
		end
		local currencyId = item.Currency
		local anchor = self.Hud:GetCurrencyAnchor(currencyId)
		local duration = 0
		if anchor then
			local window = self.Classic.Window
			local from = if flipping and self.Classic.IsOpen and window then Effects.GuiCenter(window) else workspace.CurrentCamera.ViewportSize * Vector2.new(0.5, 0.24)
			local currency = Currencies.Get(currencyId)
			self.Hud:HoldCurrency(currencyId)
			duration = Effects.CoinFlight(from, anchor, 14, currency and currency.Glyph)
		end
		task.wait(duration)
		self.Hud:ReleaseCurrency(currencyId, 0.8)
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

-- The factory reacts to a purchase: worker robots cheer (and burst a glow on the local
-- buyer), Epic+ launch fireworks.
local function reactWorld(view: any, rarityId: string, position: Vector3?, isMe: boolean)
	local rarity = Rarities.Get(rarityId)
	local workers = view.Zones.Workers
	if workers then
		workers:React(position, rarityId, isMe)
	end
	local fireworks = Sequences.Get(rarityId).Fireworks
	if fireworks > 0 and view.Zones.Spectacle then
		view.Zones.Spectacle:Fireworks({ rarity.Gradient[1], rarity.Gradient[2], Color3.new(1, 1, 1), view.Theme.Neon }, fireworks)
	end
end

function ShopController:_onBroadcast(payload: any)
	if type(payload) ~= "table" or type(payload.ItemName) ~= "string" or type(payload.UserId) ~= "number" then
		return
	end
	local isMe = payload.UserId == LOCAL_PLAYER.UserId
	local rarityId = if Rarities.Info[payload.Rarity] then payload.Rarity else "Common"
	local rarity = Rarities.Get(rarityId)
	local position = if typeof(payload.Position) == "Vector3" then payload.Position else nil
	local sameFactory = currentView ~= nil and payload.World == currentView.World

	local item = if type(payload.ItemId) == "string" then Shop.Get(payload.ItemId) else nil

	if not isMe and (payload.Scope == "Server" or (payload.Scope == "Factory" and sameFactory)) then
		local verb = VERBS[payload.Kind] or "got"
		self.Hud:Feed(string.format("<b>%s</b> %s <font color=\"#%s\">%s</font>!", escapeRich(tostring(payload.DisplayName or "?")), verb, rarity.Color:ToHex(), escapeRich(payload.ItemName)), rarityId)
		if rarityId == "Mythic" then
			Effects.ScreenFlash(rarity.Color, 0.2, 0.8)
		end
	end
	if isMe and item and Shop.IsRobux(item) then
		task.spawn(self._celebrateRobux, self, item, rarityId)
	end

	for _, view in views do
		if view.Near and payload.World == view.World then
			if isMe then
				local capsules = view.Zones.CapsuleHall
				if payload.Kind == "Capsule" and item and capsules and capsules:DeferPurchaseReactions(item.RefId) then
					-- (the capsule show plays it at its reveal)
				elseif reactionHolds > 0 or activeShow then
					-- the show / reveal presenting this purchase plays it (PlayPurchaseReactions)
					if not heldReaction or rarity.Rank >= Rarities.Get(heldReaction.Rarity).Rank then
						heldReaction = { View = view, Rarity = rarityId, Position = position }
					end
				else
					reactWorld(view, rarityId, position, true)
				end
			else
				reactWorld(view, rarityId, position, false)
				if position then
					Effects.Confetti(position + Vector3.new(0, 3, 0), 8 * rarity.Rank, { rarity.Gradient[1], rarity.Gradient[2] }, 0.6)
					Effects.Burst(position, "Glow", 6 * rarity.Rank, rarity.Color)
				end
				if payload.Kind == "Capsule" and item and view.Zones.CapsuleHall then
					view.Zones.CapsuleHall:RemoteOpened(item.RefId, rarityId)
				end
			end
		end
	end
end

-- Plays the held world reaction to the local player's own purchase: the worker robots
-- cheer, a rarity glow bursts at `position` (default: the player) and Epic+ fire rockets.
-- Shows call this at their reveal; EndShow does it as a fallback.
function ShopController:PlayPurchaseReactions(position: Vector3?)
	local held = heldReaction
	heldReaction = nil
	if not held or views[held.View.Model] ~= held.View or not held.View.Near then
		return
	end
	local root = self:GetRoot()
	reactWorld(held.View, held.Rarity, position or (if root then root.Position else held.Position), true)
end

-- Robux purchases finish in Roblox's own prompt; the server's broadcast of the grant is
-- the moment to celebrate them (the confirm modal only said "Checkout…").
function ShopController:_celebrateRobux(item: Shop.ShopItem, rarityId: string)
	local rarity = Rarities.Get(rarityId)
	local profile = Sequences.Get(rarityId)
	local subtitle = "Unlocked forever  ·  " .. rarity.Name
	if item.Kind == "CoinPack" then
		local data = self.ClientData:Get()
		local amount = if data then Shop.CoinPackAmount(item.RefId, data) else 0
		subtitle = if amount > 0 then "+" .. Format.Abbreviate(amount) .. " Coins  ·  " .. rarity.Name else "Coins added  ·  " .. rarity.Name
	elseif item.Kind == "Boost" then
		local boost = Boosts.Get(item.RefId)
		subtitle = "Boost active  ·  " .. Format.Duration(boost and boost.Duration or 0)
	end
	if self.Classic.IsOpen then
		self.Classic:CelebrateFrom(item.Id, if item.Kind == "Gamepass" then "UNLOCKED!" else "PURCHASED!", rarityId)
	end
	Audio.Play("Success")
	self.Hud:Banner({ Title = item.Name, Subtitle = subtitle, Rarity = rarityId, Style = if profile.Banner == "Small" then "Big" else profile.Banner })
	Effects.ScreenFlash(rarity.Color, 0.25, 0.6)
	Effects.UIConfetti(math.floor(profile.Confetti / 2), { rarity.Gradient[1], rarity.Gradient[2], Color3.new(1, 1, 1) })
	if item.Kind == "CoinPack" then
		-- the coins pour from the banner into the pill (which counts them up on the sync)
		local anchor = self.Hud:GetCurrencyAnchor("Coins")
		if anchor then
			local currency = Currencies.Get("Coins")
			Effects.CoinFlight(workspace.CurrentCamera.ViewportSize * Vector2.new(0.5, 0.24), anchor, 16, currency and currency.Glyph)
		end
	end
end

-- Lifecycle -------------------------------------------------------------------------------

local function applySettings(self)
	local low = self.ClientData:LowGraphics()
	local reduce = self.ClientData:ReduceMotion()
	Effects.SetLowGraphics(low)
	UIFx.SetLowGraphics(low)
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
					-- Back out of the doorway under a quick fade like every other teleport,
					-- then the window opens.
					task.spawn(function()
						self.Hud:Fade(0, 0.15)
						if not activeShow and not mode then
							local back = view:ToWorld(Vector3.new(0, 3, -22))
							local away = view.Origin:VectorToWorldSpace(Vector3.new(0, 0, -1))
							self:Teleport(CFrame.lookAt(back, back + away))
							self:AimFollowCamera(away)
							self.Classic:Open()
						end
						self.Hud:Fade(1, 0.25)
					end)
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
