-- Chat commands for testing the shop (Studio: everyone, live: game owner,
-- group rank >= 254 or user ids in ADMINS). Hook these into your F2 admin
-- panel if you prefer buttons.
--   /coins <amount>          add coins
--   /cores <currency|all> <n> add boss cores
--   /boss <TrashKing|RustDragon>  mark a boss as defeated (+1 core)
--   /world <WorldId>         unlock a world
--   /time <hour>             set the clock (0-24)
--   /crate                   reset today's mystery crate
--   /resetshop               reset your profile to defaults

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Bosses = require(Shared.Definitions.Bosses)
local Worlds = require(Shared.Definitions.Worlds)
local Currencies = require(Shared.Definitions.Currencies)

local AdminService = {}

local ADMINS: { number } = {}

local DataService
local ShopService

function AdminService:Init(services)
	DataService = services.DataService
	ShopService = services.ShopService
end

local function isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(ADMINS, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(function()
		return (player :: any):GetRankInGroup(game.CreatorId)
	end)
	return ok and rank >= 254
end

local Commands = {}

function Commands.coins(player: Player, args: { string })
	local amount = tonumber(args[1]) or 1_000_000
	DataService:Give(player, "Coins", math.clamp(amount, 0, 1e15))
	return "Added coins."
end

function Commands.cores(player: Player, args: { string })
	local which = args[1] or "all"
	local amount = math.clamp(tonumber(args[2]) or 10, 0, 1e6)
	for _, id in Currencies.Stored do
		local currency = Currencies.Get(id)
		if currency and currency.Kind == "BossCore" and (which == "all" or which:lower() == id:lower()) then
			DataService:Give(player, id, amount)
		end
	end
	return "Added boss cores."
end

function Commands.boss(player: Player, args: { string })
	local bossId = args[1]
	for id, boss in Bosses do
		if bossId and id:lower() == bossId:lower() then
			DataService:Update(player, function(data)
				data.Progress.Bosses[id] = (data.Progress.Bosses[id] or 0) + 1
				data.Currencies[boss.Core] = (data.Currencies[boss.Core] or 0) + 1
			end)
			return "Defeated " .. boss.Name .. "."
		end
	end
	return "Unknown boss."
end

function Commands.world(player: Player, args: { string })
	local worldId = args[1]
	for id in Worlds.Info do
		if worldId and id:lower() == worldId:lower() then
			DataService:Update(player, function(data)
				data.Progress.Worlds[id] = true
			end)
			return "Unlocked " .. id .. "."
		end
	end
	return "Unknown world."
end

function Commands.time(_player: Player, args: { string })
	local hour = tonumber(args[1])
	if not hour then
		return "Usage: /time <0-24>"
	end
	Lighting.ClockTime = hour % 24
	return "Clock set."
end

function Commands.crate(player: Player)
	DataService:Update(player, function(data)
		data.Daily.CrateDay = -1
	end)
	return "Crate reset."
end

function Commands.resetshop(player: Player)
	DataService:Reset(player)
	return "Profile reset."
end

local function run(player: Player, text: string)
	if not isAdmin(player) then
		return
	end
	local parts = string.split(text, " ")
	local name = string.lower(string.sub(parts[1] or "", 2))
	local command = Commands[name]
	if not command or not DataService:IsLoaded(player) then
		return
	end
	table.remove(parts, 1)
	local ok, message = pcall(command, player, parts)
	ShopService:Notify(player, if ok then tostring(message) else "Command failed.", if ok then "Info" else "Error")
end

function AdminService:Start()
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		local folder = Instance.new("Folder")
		folder.Name = "ShopAdminCommands"
		folder.Parent = TextChatService
		for name in Commands do
			local command = Instance.new("TextChatCommand")
			command.Name = "Shop_" .. name
			command.PrimaryAlias = "/" .. name
			command.Parent = folder
			command.Triggered:Connect(function(source: TextSource, message: string)
				local player = Players:GetPlayerByUserId(source.UserId)
				if player then
					run(player, message)
				end
			end)
		end
	else
		local function hook(player: Player)
			player.Chatted:Connect(function(message)
				if string.sub(message, 1, 1) == "/" then
					run(player, message)
				end
			end)
		end
		Players.PlayerAdded:Connect(hook)
		for _, player in Players:GetPlayers() do
			hook(player)
		end
	end
end

return AdminService
