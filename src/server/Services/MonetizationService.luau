-- Robux purchases: gamepasses (ownership check + purchase prompt result) and
-- developer products (ProcessReceipt with receipt de-duplication and a forced
-- save before the purchase is confirmed to Roblox).
-- NOTE: a game can only have ONE ProcessReceipt callback. If your project
-- already sets one, call MonetizationService:HandleReceipt from it instead.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Shop = require(Shared.Definitions.Shop)
local Boosts = require(Shared.Definitions.Boosts)
local Format = require(Shared.Util.Format)

local MonetizationService = {}

local DataService
local ShopService

local productToItem: { [number]: Shop.ShopItem } = {}
local passToItem: { [number]: Shop.ShopItem } = {}

function MonetizationService:Init(services)
	DataService = services.DataService
	ShopService = services.ShopService

	for _, item in Shop.Items do
		if item.Currency == "Robux" then
			if item.ProductId and item.ProductId ~= 0 then
				productToItem[item.ProductId] = item
			end
			if item.GamePassId and item.GamePassId ~= 0 then
				passToItem[item.GamePassId] = item
			end
		end
	end
	for _, boost in Boosts.List do
		if boost.ProductId and boost.ProductId ~= 0 and not productToItem[boost.ProductId] then
			local item = Shop.Get(boost.Id)
			if item then
				productToItem[boost.ProductId] = item
			end
		end
	end
end

local function refreshGamepasses(player: Player)
	for passId, item in passToItem do
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
		if ok and owns then
			DataService:Update(player, function(data)
				data.Gamepasses[item.RefId] = true
			end)
		end
	end
end

function MonetizationService:Start()
	DataService.Loaded:Connect(function(player)
		refreshGamepasses(player)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local item = passToItem[passId]
		if not item then
			return
		end
		local result = ShopService:GrantRobuxItem(player, item)
		if result then
			ShopService:Notify(player, "Unlocked " .. item.Name .. "!", "Success")
		end
	end)

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return MonetizationService:HandleReceipt(receiptInfo)
	end
end

function MonetizationService:HandleReceipt(receiptInfo): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player or not DataService:IsLoaded(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local item = productToItem[receiptInfo.ProductId]
	if not item then
		-- Not one of ours; let another handler deal with it.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local receiptId = tostring(receiptInfo.PurchaseId)
	if DataService:HasReceipt(player, receiptId) then
		-- Granted earlier but the save may not have gone through yet.
		if DataService:ForceSave(player) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local result = ShopService:GrantRobuxItem(player, item)
	if not result then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	DataService:AddReceipt(player, receiptId)

	if not DataService:ForceSave(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if item.Kind == "CoinPack" then
		ShopService:Notify(player, "+" .. Format.Commas(result.Amount or 0) .. " Coins!", "Success")
	else
		ShopService:Notify(player, item.Name .. " activated!", "Success")
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return MonetizationService
