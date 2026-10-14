--!strict
-- The shop catalog. Every purchasable thing (vacuums, capsules, upgrades,
-- boosts, cosmetics, trophies, deals, gamepasses, coin packs) is flattened
-- into one item list with the same fields:
--   Id, Name, Category, Kind, RefId, Price, Currency, IconAssetId, Rarity, ...
-- Prices that depend on the player (upgrade levels, world scaling) are
-- resolved with Shop.GetPrice so client display and server validation agree.

local Definitions = script.Parent
local Vacuums = require(Definitions.Vacuums)
local Capsules = require(Definitions.Capsules)
local Upgrades = require(Definitions.Upgrades)
local Boosts = require(Definitions.Boosts)
local Cosmetics = require(Definitions.Cosmetics)
local Trophies = require(Definitions.Trophies)
local Bosses = require(Definitions.Bosses)
local Progress = require(Definitions.Parent.Util.Progress)
local DayNight = require(Definitions.Parent.Util.DayNight)

export type Kind = "Vacuum" | "Capsule" | "Upgrade" | "Boost" | "Cosmetic" | "Trophy" | "Gamepass" | "CoinPack" | "DailyCrate"

export type ShopItem = {
	Id: string,
	Name: string,
	Category: string,
	Kind: Kind,
	RefId: string,
	Price: number,
	Currency: string,
	IconAssetId: number,
	Rarity: string,
	Description: string,
	Glyph: string,
	Order: number,
	World: string?,
	NightOnly: boolean,
	OneTime: boolean,
	ProductId: number?,
	GamePassId: number?,
}

export type ItemState = "Available" | "Owned" | "Equipped" | "Locked" | "MaxLevel" | "NightOnly" | "Claimed" | "Unavailable"

local Shop = {}

Shop.Categories = {
	{ Id = "Vacuums", Name = "Vacuums", Glyph = "🌀" },
	{ Id = "Capsules", Name = "Capsules", Glyph = "🥚" },
	{ Id = "Upgrades", Name = "Upgrades", Glyph = "⚙" },
	{ Id = "Boosts", Name = "Boosts", Glyph = "⚡" },
	{ Id = "Cosmetics", Name = "Cosmetics", Glyph = "🎨" },
	{ Id = "Trophies", Name = "Boss Shop", Glyph = "🏆" },
	{ Id = "Deals", Name = "Deals", Glyph = "🌙" },
	{ Id = "Gamepasses", Name = "Gamepasses", Glyph = "🎟" },
	{ Id = "Coins", Name = "Coins", Glyph = "🪙" },
}

-- Replace GamePassId / ProductId with your real ids. 0 = shown as "Soon".
Shop.Gamepasses = {
	{ Id = "gp_vip", Name = "VIP", GamePassId = 0, Price = 299, Rarity = "Legendary", Glyph = "👑", Order = 1, Description = "+10% coins, a golden name tag and VIP chat tag.", Perk = { Stat = "Coins", Bonus = 0.1 } },
	{ Id = "gp_double_coins", Name = "2x Coins Forever", GamePassId = 0, Price = 399, Rarity = "Mythic", Glyph = "💰", Order = 2, Description = "Permanently double every coin you earn.", Perk = { Stat = "Coins", Bonus = 1 } },
	{ Id = "gp_lucky", Name = "Lucky Hands", GamePassId = 0, Price = 249, Rarity = "Epic", Glyph = "🍀", Order = 3, Description = "+50% chance for Epic+ pets in every capsule.", Perk = { Stat = "Luck", Bonus = 0.5 } },
	{ Id = "gp_big_tank", Name = "Bottomless Tank", GamePassId = 0, Price = 199, Rarity = "Rare", Glyph = "🛢", Order = 4, Description = "Double tank capacity on every vacuum.", Perk = { Stat = "Capacity", Bonus = 1 } },
	{ Id = "gp_express", Name = "Express Factory", GamePassId = 0, Price = 149, Rarity = "Rare", Glyph = "⏩", Order = 5, Description = "No Test Chamber cooldown and shorter shows.", Perk = { Stat = "Express", Bonus = 1 } },
}

Shop.CoinPacks = {
	{ Id = "coins_pouch", Name = "Pouch of Coins", ProductId = 0, Price = 29, Amount = 5_000, Rarity = "Common", Order = 1 },
	{ Id = "coins_bag", Name = "Bag of Coins", ProductId = 0, Price = 79, Amount = 17_500, Rarity = "Rare", Order = 2 },
	{ Id = "coins_chest", Name = "Chest of Coins", ProductId = 0, Price = 199, Amount = 60_000, Rarity = "Epic", Order = 3 },
	{ Id = "coins_vault", Name = "Vault of Coins", ProductId = 0, Price = 499, Amount = 200_000, Rarity = "Legendary", Order = 4 },
	{ Id = "coins_mega", Name = "Mega Vault", ProductId = 0, Price = 999, Amount = 500_000, Rarity = "Mythic", Order = 5 },
}

-- Daily "Mystery Crate" offer, rolled into the lobby by a conveyor every 24 h.
Shop.DailyCrate = {
	Id = "deal_mystery_crate",
	Name = "Mystery Crate",
	BasePrice = 2_500,
	Rarity = "Epic",
	Description = "One per day. Could be coins, a boost, a pet, a cosmetic... or a boss core.",
	Rewards = {
		{ Kind = "Coins", Weight = 46, MinFactor = 2, MaxFactor = 6 },
		{ Kind = "Boost", Boost = "boost_coins_2x", Weight = 18 },
		{ Kind = "Boost", Boost = "boost_luck", Weight = 12 },
		{ Kind = "Pet", Weight = 14 },
		{ Kind = "Cosmetic", Weight = 8 },
		{ Kind = "BossCore", Weight = 2, Amount = 1 },
	} :: { { [string]: any } },
}

Shop.Items = {} :: { ShopItem }
Shop.ById = {} :: { [string]: ShopItem }

local function add(item: ShopItem)
	assert(Shop.ById[item.Id] == nil, "Duplicate shop item id " .. item.Id)
	Shop.ById[item.Id] = item
	table.insert(Shop.Items, item)
end

for _, vacuum in Vacuums.List do
	if vacuum.Starter then
		continue
	end
	add({
		Id = vacuum.Id,
		Name = vacuum.Name,
		Category = "Vacuums",
		Kind = "Vacuum",
		RefId = vacuum.Id,
		Price = vacuum.Price,
		Currency = vacuum.Currency,
		IconAssetId = vacuum.IconAssetId,
		Rarity = vacuum.Rarity,
		Description = vacuum.Description,
		Glyph = "🌀",
		Order = vacuum.Order + (if vacuum.World == "Cleanville" then 0 else 100),
		World = vacuum.World,
		NightOnly = false,
		OneTime = true,
	})
end

for _, capsule in Capsules.List do
	add({
		Id = capsule.Id,
		Name = capsule.Name,
		Category = "Capsules",
		Kind = "Capsule",
		RefId = capsule.Id,
		Price = capsule.Price,
		Currency = capsule.Currency,
		IconAssetId = capsule.IconAssetId,
		Rarity = capsule.Rarity,
		Description = capsule.Description,
		Glyph = "🥚",
		Order = capsule.Order + (if capsule.World == "Cleanville" then 0 else 100),
		World = capsule.World,
		NightOnly = capsule.NightOnly == true,
		OneTime = false,
	})
end

for _, upgrade in Upgrades.List do
	add({
		Id = upgrade.Id,
		Name = upgrade.Name,
		Category = "Upgrades",
		Kind = "Upgrade",
		RefId = upgrade.Id,
		Price = upgrade.BaseCost,
		Currency = "Coins",
		IconAssetId = upgrade.IconAssetId,
		Rarity = upgrade.Rarity,
		Description = upgrade.Description,
		Glyph = upgrade.Glyph,
		Order = upgrade.Order,
		NightOnly = false,
		OneTime = false,
	})
end

for _, boost in Boosts.List do
	add({
		Id = boost.Id,
		Name = boost.Name,
		Category = "Boosts",
		Kind = "Boost",
		RefId = boost.Id,
		Price = boost.Price,
		Currency = boost.Currency,
		IconAssetId = boost.IconAssetId,
		Rarity = boost.Rarity,
		Description = boost.Description,
		Glyph = boost.Glyph,
		Order = boost.Order,
		NightOnly = boost.NightOnly == true,
		OneTime = false,
		ProductId = boost.ProductId,
	})
end

for _, cosmetic in Cosmetics.List do
	add({
		Id = cosmetic.Id,
		Name = cosmetic.Name,
		Category = "Cosmetics",
		Kind = "Cosmetic",
		RefId = cosmetic.Id,
		Price = cosmetic.Price,
		Currency = cosmetic.Currency,
		IconAssetId = cosmetic.IconAssetId,
		Rarity = cosmetic.Rarity,
		Description = cosmetic.Description,
		Glyph = if cosmetic.Slot == "Skin" then "🎨" else "✨",
		Order = cosmetic.Order,
		NightOnly = cosmetic.NightOnly == true,
		OneTime = true,
	})
end

for _, trophy in Trophies.List do
	add({
		Id = trophy.Id,
		Name = trophy.Name,
		Category = "Trophies",
		Kind = "Trophy",
		RefId = trophy.Id,
		Price = trophy.Price,
		Currency = trophy.Currency,
		IconAssetId = trophy.IconAssetId,
		Rarity = trophy.Rarity,
		Description = trophy.Description,
		Glyph = "🏆",
		Order = trophy.Order,
		World = Bosses[trophy.Boss].World,
		NightOnly = false,
		OneTime = true,
	})
end

for _, pass in Shop.Gamepasses do
	add({
		Id = pass.Id,
		Name = pass.Name,
		Category = "Gamepasses",
		Kind = "Gamepass",
		RefId = pass.Id,
		Price = pass.Price,
		Currency = "Robux",
		IconAssetId = 0,
		Rarity = pass.Rarity,
		Description = pass.Description,
		Glyph = pass.Glyph,
		Order = pass.Order,
		NightOnly = false,
		OneTime = true,
		GamePassId = pass.GamePassId,
	})
end

for _, pack in Shop.CoinPacks do
	add({
		Id = pack.Id,
		Name = pack.Name,
		Category = "Coins",
		Kind = "CoinPack",
		RefId = pack.Id,
		Price = pack.Price,
		Currency = "Robux",
		IconAssetId = 0,
		Rarity = pack.Rarity,
		Description = "Instantly adds coins. Scales with your best world.",
		Glyph = "🪙",
		Order = pack.Order,
		NightOnly = false,
		OneTime = false,
		ProductId = pack.ProductId,
	})
end

add({
	Id = Shop.DailyCrate.Id,
	Name = Shop.DailyCrate.Name,
	Category = "Deals",
	Kind = "DailyCrate",
	RefId = Shop.DailyCrate.Id,
	Price = Shop.DailyCrate.BasePrice,
	Currency = "Coins",
	IconAssetId = 0,
	Rarity = Shop.DailyCrate.Rarity,
	Description = Shop.DailyCrate.Description,
	Glyph = "📦",
	Order = 0,
	NightOnly = false,
	OneTime = false,
})

Shop.GamepassById = {} :: { [string]: any }
for _, pass in Shop.Gamepasses do
	Shop.GamepassById[pass.Id] = pass
end

Shop.CoinPackById = {} :: { [string]: any }
for _, pack in Shop.CoinPacks do
	Shop.CoinPackById[pack.Id] = pack
end

function Shop.Get(id: string): ShopItem?
	return Shop.ById[id]
end

-- Items shown under a tab. "Deals" collects the daily crate and every
-- night-only offer.
function Shop.ItemsInCategory(categoryId: string): { ShopItem }
	local list = {}
	for _, item in Shop.Items do
		if item.Category == categoryId or (categoryId == "Deals" and item.NightOnly) then
			table.insert(list, item)
		end
	end
	table.sort(list, function(a, b)
		if a.Order ~= b.Order then
			return a.Order < b.Order
		end
		return a.Id < b.Id
	end)
	return list
end

function Shop.GetPrice(item: ShopItem, data: any): number
	if item.Kind == "Upgrade" then
		local level = if data and data.Upgrades then data.Upgrades[item.RefId] or 0 else 0
		return Upgrades.Cost(item.RefId, level)
	elseif item.Kind == "Boost" then
		local boost = Boosts.Get(item.RefId)
		if boost and boost.PriceScales then
			return math.floor(boost.Price * Progress.EconomyMultiplier(data))
		end
	elseif item.Kind == "DailyCrate" then
		return math.floor(Shop.DailyCrate.BasePrice * Progress.EconomyMultiplier(data))
	end
	return item.Price
end

function Shop.CoinPackAmount(packId: string, data: any): number
	local pack = Shop.CoinPackById[packId]
	if not pack then
		return 0
	end
	return math.floor(pack.Amount * Progress.EconomyMultiplier(data))
end

function Shop.IsRobux(item: ShopItem): boolean
	return item.Currency == "Robux"
end

-- Display / validation state of an item for one player.
-- `now` is unix time (server: os.time(), client: workspace:GetServerTimeNow()).
function Shop.GetState(item: ShopItem, data: any, now: number, isNight: boolean?): (ItemState, string?)
	if type(data) ~= "table" then
		return "Unavailable", "Loading..."
	end
	local night = if isNight == nil then DayNight.IsNight() else isNight

	if item.NightOnly and not night then
		return "NightOnly", "Available at night"
	end

	if item.Kind == "Vacuum" then
		if data.Vacuums.Owned[item.RefId] then
			return if data.Vacuums.Equipped == item.RefId then "Equipped" else "Owned", nil
		end
		local vacuum = Vacuums.Get(item.RefId)
		local ok, reason = Progress.CheckAll(data, vacuum and vacuum.Unlock)
		if not ok then
			return "Locked", reason
		end
	elseif item.Kind == "Capsule" then
		if item.World and not Progress.WorldUnlocked(data, item.World) then
			return "Locked", "Unlock " .. item.World
		end
	elseif item.Kind == "Upgrade" then
		local upgrade = Upgrades.Get(item.RefId)
		local level = data.Upgrades[item.RefId] or 0
		if upgrade and level >= upgrade.MaxLevel then
			return "MaxLevel", "Max level"
		end
	elseif item.Kind == "Boost" then
		if item.Currency == "Robux" and (item.ProductId or 0) == 0 then
			return "Unavailable", "Coming soon"
		end
	elseif item.Kind == "Cosmetic" then
		if data.Cosmetics.Owned[item.RefId] then
			local cosmetic = Cosmetics.Get(item.RefId)
			local slot = if cosmetic then cosmetic.Slot else "Skin"
			return if data.Cosmetics[slot] == item.RefId then "Equipped" else "Owned", nil
		end
	elseif item.Kind == "Trophy" then
		if data.Trophies[item.RefId] then
			return "Owned", nil
		end
		local trophy = Trophies.Get(item.RefId)
		if trophy and (data.Progress.Bosses[trophy.Boss] or 0) <= 0 and (data.Currencies[trophy.Currency] or 0) <= 0 then
			return "Locked", "Defeat the " .. Bosses[trophy.Boss].Name
		end
	elseif item.Kind == "Gamepass" then
		if data.Gamepasses[item.RefId] then
			return "Owned", nil
		end
		if (item.GamePassId or 0) == 0 then
			return "Unavailable", "Coming soon"
		end
	elseif item.Kind == "CoinPack" then
		if (item.ProductId or 0) == 0 then
			return "Unavailable", "Coming soon"
		end
	elseif item.Kind == "DailyCrate" then
		if data.Daily.CrateDay == DayNight.Day(now) then
			return "Claimed", "Next crate in"
		end
	end
	return "Available", nil
end

function Shop.CanAfford(item: ShopItem, data: any): boolean
	if Shop.IsRobux(item) then
		return true
	end
	local balance = if data and data.Currencies then data.Currencies[item.Currency] or 0 else 0
	return balance >= Shop.GetPrice(item, data)
end

return Shop
