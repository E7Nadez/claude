-- Player profiles: DataStore load with session lock, autosave, release on
-- leave, BindToClose flush, and replication to the owning client.
-- If DataStores are unavailable (Studio without API access) profiles live in
-- memory only and a warning is printed.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local DataTemplate = require(Shared.DataTemplate)
local Currencies = require(Shared.Definitions.Currencies)

local DataService = {}

DataService.Loaded = Signal.new() -- (player, data)
DataService.Changed = Signal.new() -- (player, data)

local STORE_NAME = "VacuumTheWorld_Players_v1"
local AUTOSAVE_INTERVAL = 75
local LOCK_EXPIRE = 6 * 60
local LOAD_ATTEMPTS = 6
local MAX_RECEIPTS = 60

type Profile = {
	Data: DataTemplate.PlayerData,
	Key: string,
	Persistent: boolean,
	Dirty: boolean,
	Saving: boolean,
	Released: boolean,
	SyncQueued: boolean,
}

local profiles: { [Player]: Profile } = {}
local loading: { [Player]: boolean } = {}
local store: DataStore? = nil
local storeWarned = false

local function warnNoStore(reason: string)
	if not storeWarned then
		storeWarned = true
		warn("[DataService] DataStores unavailable, data will NOT be saved:", reason)
	end
end

local function updateAttributes(player: Player, data: DataTemplate.PlayerData)
	for _, currencyId in Currencies.Stored do
		player:SetAttribute(currencyId, data.Currencies[currencyId] or 0)
	end
	player:SetAttribute("EquippedVacuum", data.Vacuums.Equipped)
	player:SetAttribute("Skin", data.Cosmetics.Skin or "")
	player:SetAttribute("Trail", data.Cosmetics.Trail or "")
	player:SetAttribute("ShopDataLoaded", true)
end

local function queueSync(player: Player)
	local profile = profiles[player]
	if not profile or profile.SyncQueued then
		return
	end
	profile.SyncQueued = true
	task.defer(function()
		local current = profiles[player]
		if not current then
			return
		end
		current.SyncQueued = false
		updateAttributes(player, current.Data)
		Net.Event("DataSync"):FireClient(player, DataTemplate.ClientSnapshot(current.Data))
	end)
end

-- Returns "Ok" | "NoStore" | "Failed" and the stored data (if any).
local function loadRecord(key: string): (string, any)
	if not store then
		return "NoStore", nil
	end
	local lockedTries = 0
	for attempt = 1, LOAD_ATTEMPTS do
		local lockedByOther = false
		local ok, result = pcall(function()
			return (store :: DataStore):UpdateAsync(key, function(old)
				local record = if type(old) == "table" then old else {}
				local lock = record.Lock
				if type(lock) == "table" and lock.JobId ~= game.JobId and os.time() - (lock.Time or 0) < LOCK_EXPIRE then
					lockedByOther = true
					return nil
				end
				lockedByOther = false
				record.Lock = { JobId = game.JobId, Time = os.time() }
				return record
			end)
		end)
		if ok and not lockedByOther then
			return "Ok", if type(result) == "table" then result.Data else nil
		end
		if ok then
			lockedTries += 1
			task.wait(6)
		else
			local message = tostring(result)
			warn(string.format("[DataService] load attempt %d for %s failed: %s", attempt, key, message))
			if RunService:IsStudio() and (message:find("403") or message:find("Studio")) then
				warnNoStore(message)
				return "NoStore", nil
			end
			task.wait(2 ^ attempt * 0.5)
		end
	end
	if lockedTries > 0 then
		-- The other server never released the lock (crashed); take it over.
		local ok, result = pcall(function()
			return (store :: DataStore):UpdateAsync(key, function(old)
				local record = if type(old) == "table" then old else {}
				record.Lock = { JobId = game.JobId, Time = os.time() }
				return record
			end)
		end)
		if ok then
			return "Ok", if type(result) == "table" then result.Data else nil
		end
	end
	return "Failed", nil
end

local function saveProfile(profile: Profile, release: boolean): boolean
	if not profile.Persistent or not store then
		return true
	end
	-- Wait for an in-flight save, then save again ourselves: the caller (e.g.
	-- ProcessReceipt's ForceSave) needs a save that includes its own changes.
	while profile.Saving do
		task.wait()
	end
	profile.Saving = true
	local success = false
	for attempt = 1, 3 do
		local lostLock = false
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(profile.Key, function(old)
				local record = if type(old) == "table" then old else {}
				local lock = record.Lock
				if type(lock) == "table" and lock.JobId ~= game.JobId then
					lostLock = true
					return nil
				end
				return {
					Data = profile.Data,
					Lock = if release then nil else { JobId = game.JobId, Time = os.time() },
				}
			end)
		end)
		if ok and not lostLock then
			success = true
			break
		elseif lostLock then
			warn("[DataService] session lock lost for", profile.Key, "- not overwriting")
			break
		else
			warn(string.format("[DataService] save attempt %d for %s failed: %s", attempt, profile.Key, tostring(err)))
			task.wait(attempt)
		end
	end
	if success then
		profile.Dirty = false
	end
	profile.Saving = false
	return success
end

local function onPlayerAdded(player: Player)
	if profiles[player] or loading[player] then
		return
	end
	loading[player] = true
	local key = "Player_" .. player.UserId
	local status, stored = loadRecord(key)
	local persistent = status == "Ok"

	if status == "Failed" then
		loading[player] = nil
		player:Kick("Your save data could not be loaded right now. Please rejoin in a moment.")
		return
	end

	if not player.Parent then
		loading[player] = nil
		if persistent and store then
			-- Left during the load: release the lock we just took.
			pcall(function()
				(store :: DataStore):UpdateAsync(key, function(old)
					if type(old) == "table" and type(old.Lock) == "table" and old.Lock.JobId == game.JobId then
						old.Lock = nil
						return old
					end
					return nil
				end)
			end)
		end
		return
	end

	local data
	if type(stored) == "table" then
		data = stored
		DataTemplate.Reconcile(data)
	else
		data = DataTemplate.New()
	end

	local profile: Profile = {
		Data = data,
		Key = key,
		Persistent = persistent,
		Dirty = false,
		Saving = false,
		Released = false,
		SyncQueued = false,
	}
	profiles[player] = profile
	loading[player] = nil

	updateAttributes(player, data)
	Net.Event("DataSync"):FireClient(player, DataTemplate.ClientSnapshot(data))
	DataService.Loaded:Fire(player, data)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Released = true
	saveProfile(profile, true)
	profiles[player] = nil
end

function DataService:Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warnNoStore(tostring(result))
	end
end

function DataService:Start()
	Net.Function("RequestSync").OnServerInvoke = function(player)
		local profile = profiles[player]
		if not profile then
			return { Ok = false, Code = "NOT_LOADED" }
		end
		return { Ok = true, Data = DataTemplate.ClientSnapshot(profile.Data) }
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, profile in profiles do
				if not profile.Released then
					task.spawn(saveProfile, profile, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player, profile in profiles do
			pending += 1
			task.spawn(function()
				profile.Released = true
				saveProfile(profile, true)
				profiles[player] = nil
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

-- Public API -----------------------------------------------------------------

function DataService:GetData(player: Player): DataTemplate.PlayerData?
	local profile = profiles[player]
	return profile and profile.Data
end

function DataService:IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

function DataService:WaitForData(player: Player, timeout: number?): DataTemplate.PlayerData?
	local deadline = os.clock() + (timeout or 30)
	while player.Parent and not profiles[player] and os.clock() < deadline do
		task.wait(0.1)
	end
	return self:GetData(player)
end

-- Mutate data and replicate. `fn` must not yield.
function DataService:Update(player: Player, fn: (DataTemplate.PlayerData) -> ()): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	fn(profile.Data)
	profile.Dirty = true
	queueSync(player)
	DataService.Changed:Fire(player, profile.Data)
	return true
end

function DataService:GetCurrency(player: Player, currencyId: string): number
	local data = self:GetData(player)
	return if data then data.Currencies[currencyId] or 0 else 0
end

function DataService:Give(player: Player, currencyId: string, amount: number): boolean
	if not Currencies.IsStored(currencyId) or amount ~= amount or amount < 0 or amount == math.huge then
		return false
	end
	return self:Update(player, function(data)
		data.Currencies[currencyId] = (data.Currencies[currencyId] or 0) + math.floor(amount)
	end)
end

-- Atomic check-and-deduct. Returns false if the balance is too low.
function DataService:Spend(player: Player, currencyId: string, amount: number): boolean
	local data = self:GetData(player)
	if not data or not Currencies.IsStored(currencyId) then
		return false
	end
	if amount ~= amount or amount < 0 or amount == math.huge then
		return false
	end
	local balance = data.Currencies[currencyId] or 0
	if balance < amount then
		return false
	end
	return self:Update(player, function(d)
		d.Currencies[currencyId] = balance - amount
		if currencyId == "Coins" then
			d.Stats.CoinsSpent += amount
		end
	end)
end

function DataService:HasReceipt(player: Player, receiptId: string): boolean
	local data = self:GetData(player)
	return data ~= nil and table.find(data.Receipts, receiptId) ~= nil
end

function DataService:AddReceipt(player: Player, receiptId: string)
	self:Update(player, function(data)
		table.insert(data.Receipts, receiptId)
		while #data.Receipts > MAX_RECEIPTS do
			table.remove(data.Receipts, 1)
		end
	end)
end

-- Immediate save (used by ProcessReceipt). Returns true when persisted.
function DataService:ForceSave(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	return saveProfile(profile, false)
end

function DataService:IsPersistent(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.Persistent
end

-- Replace the whole profile with defaults (admin "/resetshop").
function DataService:Reset(player: Player)
	self:Update(player, function(data)
		local receipts = data.Receipts
		local fresh = DataTemplate.New()
		for key in data do
			data[key] = nil
		end
		for key, value in fresh do
			(data :: any)[key] = value
		end
		data.Receipts = receipts
	end)
end

return DataService
