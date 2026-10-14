-- Upgrade Lab purchases. Levels live in data.Upgrades[upgradeId].

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Errors = require(Shared.Util.Errors)
local Upgrades = require(Shared.Definitions.Upgrades)
local Shop = require(Shared.Definitions.Shop)

local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local UpgradeService = {}

local DataService
local ShopService
local limiter = RateLimiter.new(6, 3)
local busy: { [Player]: boolean } = {}

function UpgradeService:Init(services)
	DataService = services.DataService
	ShopService = services.ShopService
end

function UpgradeService:Start()
	Net.Function("PurchaseUpgrade").OnServerInvoke = function(player, upgradeId)
		return UpgradeService:Purchase(player, upgradeId)
	end
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
	end)
end

function UpgradeService:Purchase(player: Player, upgradeId: any)
	if typeof(upgradeId) ~= "string" or #upgradeId > 64 then
		return Errors.Result("INVALID")
	end
	if not limiter:Check(player) then
		return Errors.Result("RATE_LIMITED")
	end
	if busy[player] then
		return Errors.Result("BUSY")
	end
	local upgrade = Upgrades.Get(upgradeId)
	if not upgrade then
		return Errors.Result("INVALID_ITEM")
	end
	local data = DataService:GetData(player)
	if not data then
		return Errors.Result("NOT_LOADED")
	end
	local level = data.Upgrades[upgradeId] or 0
	if level >= upgrade.MaxLevel then
		return Errors.Result("MAX_LEVEL")
	end
	local cost = Upgrades.Cost(upgradeId, level)

	busy[player] = true
	local spent = DataService:Spend(player, "Coins", cost)
	if not spent then
		busy[player] = nil
		return Errors.Result("NOT_ENOUGH", "Coins")
	end
	local newLevel = level + 1
	DataService:Update(player, function(d)
		d.Upgrades[upgradeId] = newLevel
		d.Stats.Purchases += 1
	end)
	busy[player] = nil

	local item = Shop.Get(upgradeId)
	if item and ShopService then
		ShopService:Broadcast(player, item, upgrade.Rarity, nil)
	end

	return {
		Ok = true,
		ItemId = upgradeId,
		Kind = "Upgrade",
		Price = cost,
		Currency = "Coins",
		Level = newLevel,
		MaxLevel = upgrade.MaxLevel,
		NextCost = if newLevel < upgrade.MaxLevel then Upgrades.Cost(upgradeId, newLevel) else nil,
		Balance = DataService:GetCurrency(player, "Coins"),
	}
end

-- For the rest of the game: stat multipliers from upgrades.
function UpgradeService:GetMultipliers(player: Player): { [string]: number }
	local data = DataService:GetData(player)
	return Upgrades.StatMultipliers(data and data.Upgrades)
end

return UpgradeService
