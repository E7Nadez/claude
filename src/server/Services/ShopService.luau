-- Server-authoritative shop. The client only ever sends an item id; price,
-- currency, ownership, unlock state, night/daily limits and rewards are all
-- decided here from the shared definitions.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Errors = require(Shared.Util.Errors)
local DayNight = require(Shared.Util.DayNight)
local Progress = require(Shared.Util.Progress)
local DataTemplate = require(Shared.DataTemplate)
local Definitions = Shared.Definitions
local Shop = require(Definitions.Shop)
local Vacuums = require(Definitions.Vacuums)
local Capsules = require(Definitions.Capsules)
local Pets = require(Definitions.Pets)
local Boosts = require(Definitions.Boosts)
local Cosmetics = require(Definitions.Cosmetics)
local Bosses = require(Definitions.Bosses)
local Worlds = require(Definitions.Worlds)
local Rarities = require(Definitions.Rarities)
local Sequences = require(Definitions.Sequences)
local Currencies = require(Definitions.Currencies)

local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local ShopService = {}

local DataService
local UpgradeService
local FactoryService

local rng = Random.new()
local purchaseLimiter = RateLimiter.new(6, 2.5)
local equipLimiter = RateLimiter.new(8, 4)
local settingLimiter = RateLimiter.new(10, 2)
local busy: { [Player]: boolean } = {}

local STATE_ERRORS = {
	Owned = "ALREADY_OWNED",
	Equipped = "ALREADY_OWNED",
	Locked = "LOCKED",
	MaxLevel = "MAX_LEVEL",
	NightOnly = "NIGHT_ONLY",
	Claimed = "DAILY_LIMIT",
	Unavailable = "UNAVAILABLE",
}

function ShopService:Init(services)
	DataService = services.DataService
	UpgradeService = services.UpgradeService
	FactoryService = services.FactoryService
end

function ShopService:Start()
	Net.Function("PurchaseItem").OnServerInvoke = function(player, itemId, options)
		return ShopService:Purchase(player, itemId, options)
	end
	Net.Function("EquipVacuum").OnServerInvoke = function(player, vacuumId)
		return ShopService:EquipVacuum(player, vacuumId)
	end
	Net.Function("EquipCosmetic").OnServerInvoke = function(player, slot, cosmeticId)
		return ShopService:EquipCosmetic(player, slot, cosmeticId)
	end
	Net.Function("SetSetting").OnServerInvoke = function(player, key, value)
		return ShopService:SetSetting(player, key, value)
	end
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
	end)
end

-- Helpers --------------------------------------------------------------------

local function luckMultiplier(data: DataTemplate.PlayerData): number
	local luck = Boosts.ActiveMultiplier(data.Boosts, "Luck", os.time())
	if data.Gamepasses.gp_lucky then
		local pass = Shop.GamepassById.gp_lucky
		luck *= 1 + (pass and pass.Perk.Bonus or 0.5)
	end
	return luck
end

local function addPet(data: DataTemplate.PlayerData, petId: string): string
	local uid = HttpService:GenerateGUID(false)
	table.insert(data.Pets, { Uid = uid, Id = petId, Obtained = os.time() })
	return uid
end

local function applyBoost(data: DataTemplate.PlayerData, boostId: string): number
	local boost = Boosts.Get(boostId)
	if not boost then
		return 0
	end
	local now = os.time()
	local current = math.max(data.Boosts[boostId] or 0, now)
	local expires = math.min(current + boost.Duration, now + boost.MaxDuration)
	data.Boosts[boostId] = expires
	return expires
end

local function bestCapsuleFor(data: DataTemplate.PlayerData): string?
	local worldId = Progress.HighestWorld(data)
	local best = nil
	for _, capsule in Capsules.ForWorld(worldId) do
		if not capsule.NightOnly then
			best = capsule.Id
		end
	end
	return best
end

local function bossCoreFor(data: DataTemplate.PlayerData): string
	local worldId = Progress.HighestWorld(data)
	local world = Worlds.Get(worldId)
	local bestCore, bestOrder = "TrashKingCore", 0
	for _, boss in Bosses do
		local bossWorld = Worlds.Get(boss.World)
		if bossWorld and world and bossWorld.Order <= world.Order and bossWorld.Order > bestOrder then
			bestCore, bestOrder = boss.Core, bossWorld.Order
		end
	end
	return bestCore
end

-- Rolls the daily crate. Mutates data, returns a reward description.
local function rollCrate(data: DataTemplate.PlayerData, price: number): { [string]: any }
	local rewards = Shop.DailyCrate.Rewards
	local total = 0
	for _, reward in rewards do
		total += reward.Weight
	end
	local roll = rng:NextNumber() * total
	local chosen = rewards[1]
	for _, reward in rewards do
		roll -= reward.Weight
		if roll <= 0 then
			chosen = reward
			break
		end
	end

	local function coins(): { [string]: any }
		local amount = math.floor(price * rng:NextNumber(rewards[1].MinFactor, rewards[1].MaxFactor))
		data.Currencies.Coins += amount
		local rarity = if amount >= price * 5 then "Legendary" elseif amount >= price * 3.5 then "Epic" else "Rare"
		return { Kind = "Coins", Amount = amount, Currency = "Coins", Rarity = rarity, Name = "Coins" }
	end

	if chosen.Kind == "Coins" then
		return coins()
	elseif chosen.Kind == "Boost" then
		local boost = Boosts.Get(chosen.Boost)
		if boost then
			local expires = applyBoost(data, boost.Id)
			return { Kind = "Boost", BoostId = boost.Id, ExpiresAt = expires, Rarity = boost.Rarity, Name = boost.Name }
		end
	elseif chosen.Kind == "Pet" then
		local capsuleId = bestCapsuleFor(data)
		if capsuleId and #data.Pets < data.PetCapacity then
			local petId = Capsules.Roll(capsuleId, rng, luckMultiplier(data))
			local pet = petId and Pets.Get(petId)
			if pet then
				local uid = addPet(data, pet.Id)
				return { Kind = "Pet", PetId = pet.Id, Uid = uid, Rarity = pet.Rarity, Name = pet.Name }
			end
		end
	elseif chosen.Kind == "Cosmetic" then
		local pool = {}
		for _, cosmetic in Cosmetics.List do
			if not data.Cosmetics.Owned[cosmetic.Id] and not cosmetic.NightOnly and cosmetic.Currency == "Coins" and cosmetic.Price <= price * 40 then
				table.insert(pool, cosmetic)
			end
		end
		if #pool > 0 then
			local cosmetic = pool[rng:NextInteger(1, #pool)]
			data.Cosmetics.Owned[cosmetic.Id] = true
			return { Kind = "Cosmetic", CosmeticId = cosmetic.Id, Rarity = cosmetic.Rarity, Name = cosmetic.Name }
		end
	elseif chosen.Kind == "BossCore" then
		local core = bossCoreFor(data)
		local amount = chosen.Amount or 1
		data.Currencies[core] = (data.Currencies[core] or 0) + amount
		local currency = Currencies.Get(core)
		return { Kind = "BossCore", Currency = core, Amount = amount, Rarity = "Mythic", Name = if currency then currency.Name else core }
	end
	return coins()
end

-- Grants a validated, already-paid item. Must not yield.
local Granters = {}

function Granters.Vacuum(_player: Player, item: Shop.ShopItem, data: DataTemplate.PlayerData)
	data.Vacuums.Owned[item.RefId] = true
	data.Vacuums.Equipped = item.RefId
	return { Equipped = true, Rarity = item.Rarity }
end

function Granters.Capsule(_player: Player, item: Shop.ShopItem, data: DataTemplate.PlayerData)
	local petId = Capsules.Roll(item.RefId, rng, luckMultiplier(data))
	local pet = petId and Pets.Get(petId)
	assert(pet, "Capsule roll failed for " .. item.RefId)
	local uid = addPet(data, pet.Id)
	return { PetId = pet.Id, Uid = uid, Rarity = pet.Rarity, Name = pet.Name, CapsuleId = item.RefId }
end

function Granters.Boost(_player: Player, item: Shop.ShopItem, data: DataTemplate.PlayerData)
	return { ExpiresAt = applyBoost(data, item.RefId), Rarity = item.Rarity }
end

function Granters.Cosmetic(_player: Player, item: Shop.ShopItem, data: DataTemplate.PlayerData)
	local cosmetic = Cosmetics.Get(item.RefId)
	assert(cosmetic, "Unknown cosmetic " .. item.RefId)
	data.Cosmetics.Owned[cosmetic.Id] = true
	data.Cosmetics[cosmetic.Slot] = cosmetic.Id
	return { Slot = cosmetic.Slot, Equipped = true, Rarity = item.Rarity }
end

function Granters.Trophy(_player: Player, item: Shop.ShopItem, data: DataTemplate.PlayerData)
	data.Trophies[item.RefId] = true
	return { Rarity = item.Rarity }
end

function Granters.DailyCrate(_player: Player, item: Shop.ShopItem, data: DataTemplate.PlayerData, price: number)
	data.Daily.CrateDay = DayNight.Day(os.time())
	local reward = rollCrate(data, price)
	return { Reward = reward, Rarity = reward.Rarity or item.Rarity }
end

-- Remotes ------------------------------------------------------------------

function ShopService:Purchase(player: Player, itemId: any, _options: any)
	if typeof(itemId) ~= "string" or #itemId > 64 then
		return Errors.Result("INVALID")
	end
	if not purchaseLimiter:Check(player) then
		return Errors.Result("RATE_LIMITED")
	end
	local item = Shop.Get(itemId)
	if not item then
		return Errors.Result("INVALID_ITEM")
	end
	if item.Kind == "Upgrade" then
		return UpgradeService:Purchase(player, item.RefId)
	end
	if Shop.IsRobux(item) then
		return Errors.Result("USE_ROBUX")
	end
	if busy[player] then
		return Errors.Result("BUSY")
	end
	local data = DataService:GetData(player)
	if not data then
		return Errors.Result("NOT_LOADED")
	end

	local state, reason = Shop.GetState(item, data, os.time(), DayNight.IsNight())
	if state ~= "Available" then
		local code = STATE_ERRORS[state] or "UNAVAILABLE"
		return Errors.Result(code, reason or "")
	end
	if item.Kind == "Capsule" and #data.Pets >= data.PetCapacity then
		return Errors.Result("INVENTORY_FULL")
	end

	local granter = Granters[item.Kind]
	if not granter then
		return Errors.Result("UNAVAILABLE")
	end

	local price = Shop.GetPrice(item, data)
	busy[player] = true
	if not DataService:Spend(player, item.Currency, price) then
		busy[player] = nil
		local currency = Currencies.Get(item.Currency)
		return Errors.Result("NOT_ENOUGH", if currency then currency.Name else item.Currency)
	end

	local result
	local ok, err = pcall(function()
		DataService:Update(player, function(d)
			result = granter(player, item, d, price)
			d.Stats.Purchases += 1
		end)
	end)
	busy[player] = nil

	if not ok or not result then
		-- Never keep the money for something that was not granted.
		warn("[ShopService] grant failed for", player.Name, itemId, err)
		DataService:Give(player, item.Currency, price)
		return Errors.Result("UNAVAILABLE")
	end

	local rarity = result.Rarity or item.Rarity
	local displayName = result.Name or item.Name
	ShopService:Broadcast(player, item, rarity, displayName)

	result.Ok = true
	result.ItemId = item.Id
	result.Kind = item.Kind
	result.Price = price
	result.Currency = item.Currency
	result.Balance = DataService:GetCurrency(player, item.Currency)
	return result
end

function ShopService:EquipVacuum(player: Player, vacuumId: any)
	if typeof(vacuumId) ~= "string" or #vacuumId > 64 then
		return Errors.Result("INVALID")
	end
	if not equipLimiter:Check(player) then
		return Errors.Result("RATE_LIMITED")
	end
	local data = DataService:GetData(player)
	if not data then
		return Errors.Result("NOT_LOADED")
	end
	if not Vacuums.Get(vacuumId) or not data.Vacuums.Owned[vacuumId] then
		return Errors.Result("NOT_OWNED")
	end
	DataService:Update(player, function(d)
		d.Vacuums.Equipped = vacuumId
	end)
	return { Ok = true, Equipped = vacuumId }
end

function ShopService:EquipCosmetic(player: Player, slot: any, cosmeticId: any)
	if slot ~= "Skin" and slot ~= "Trail" then
		return Errors.Result("INVALID")
	end
	if cosmeticId ~= nil and (typeof(cosmeticId) ~= "string" or #cosmeticId > 64) then
		return Errors.Result("INVALID")
	end
	if not equipLimiter:Check(player) then
		return Errors.Result("RATE_LIMITED")
	end
	local data = DataService:GetData(player)
	if not data then
		return Errors.Result("NOT_LOADED")
	end
	if cosmeticId ~= nil then
		local cosmetic = Cosmetics.Get(cosmeticId)
		if not cosmetic or cosmetic.Slot ~= slot or not data.Cosmetics.Owned[cosmeticId] then
			return Errors.Result("NOT_OWNED")
		end
	end
	DataService:Update(player, function(d)
		d.Cosmetics[slot] = cosmeticId
	end)
	return { Ok = true, Slot = slot, Equipped = cosmeticId }
end

function ShopService:SetSetting(player: Player, key: any, value: any)
	if typeof(key) ~= "string" then
		return Errors.Result("INVALID")
	end
	local expected = DataTemplate.ClientSettings[key]
	if not expected or typeof(value) ~= expected then
		return Errors.Result("INVALID")
	end
	if not settingLimiter:Check(player) then
		return Errors.Result("RATE_LIMITED")
	end
	local ok = DataService:Update(player, function(d)
		(d.Settings :: any)[key] = value
	end)
	if not ok then
		return Errors.Result("NOT_LOADED")
	end
	return { Ok = true }
end

-- Called by MonetizationService after Robux was charged. Returns a result.
function ShopService:GrantRobuxItem(player: Player, item: Shop.ShopItem): { [string]: any }?
	local result
	local ok = DataService:Update(player, function(data)
		if item.Kind == "CoinPack" then
			local amount = Shop.CoinPackAmount(item.RefId, data)
			data.Currencies.Coins += amount
			result = { Amount = amount, Rarity = item.Rarity }
		elseif item.Kind == "Boost" then
			result = { ExpiresAt = applyBoost(data, item.RefId), Rarity = item.Rarity }
		elseif item.Kind == "Gamepass" then
			data.Gamepasses[item.RefId] = true
			result = { Rarity = item.Rarity }
		end
		data.Stats.Purchases += 1
	end)
	if not ok or not result then
		return nil
	end
	ShopService:Broadcast(player, item, result.Rarity or item.Rarity, nil)
	return result
end

-- Tells clients about a purchase so the factory can react (toast, confetti
-- on the buyer, cheering robots). Scope comes from the rarity profile.
function ShopService:Broadcast(player: Player, item: Shop.ShopItem, rarity: string, displayName: string?)
	local profile = Sequences.Get(rarity)
	if profile.Broadcast == "None" then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local position = if root and root:IsA("BasePart") then root.Position else nil
	local world = if position and FactoryService then FactoryService:WorldAt(position) else nil
	Net.Event("ShopBroadcast"):FireAllClients({
		UserId = player.UserId,
		DisplayName = player.DisplayName,
		ItemId = item.Id,
		ItemName = displayName or item.Name,
		Kind = item.Kind,
		Rarity = if Rarities.Info[rarity] then rarity else item.Rarity,
		Scope = profile.Broadcast,
		World = world,
		Position = position,
	})
end

function ShopService:Notify(player: Player, text: string, kind: string?)
	Net.Event("Notify"):FireClient(player, { Text = text, Kind = kind or "Info" })
end

return ShopService
