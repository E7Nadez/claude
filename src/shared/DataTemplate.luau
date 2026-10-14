--!strict
-- Shape of the saved player profile. The server reconciles every loaded
-- profile against this template; clients receive the same shape (minus
-- server-only fields) through the DataSync remote.

export type PetEntry = { Uid: string, Id: string, Obtained: number }

export type PlayerData = {
	Version: number,
	Currencies: { [string]: number },
	Vacuums: { Owned: { [string]: boolean }, Equipped: string },
	Upgrades: { [string]: number },
	Pets: { PetEntry },
	PetCapacity: number,
	Cosmetics: { Owned: { [string]: boolean }, Skin: string?, Trail: string? },
	Trophies: { [string]: boolean },
	Boosts: { [string]: number },
	Gamepasses: { [string]: boolean },
	Progress: {
		Worlds: { [string]: boolean },
		Bosses: { [string]: number },
		Mastery: { [string]: number },
	},
	Daily: { CrateDay: number },
	Settings: {
		LowGraphics: boolean?,
		SkipIntro: boolean,
		ClassicShop: boolean,
		ReduceMotion: boolean,
		SeenIntro: boolean,
	},
	Stats: {
		Purchases: number,
		FactoryVisits: number,
		TestRuns: number,
		CoinsSpent: number,
	},
	Receipts: { string },
}

local DataTemplate = {}

DataTemplate.Version = 1

DataTemplate.Default = {
	Version = DataTemplate.Version,
	Currencies = { Coins = 0, TrashKingCore = 0, RustDragonCore = 0 },
	Vacuums = { Owned = { vac_dust_buster = true }, Equipped = "vac_dust_buster" },
	Upgrades = { upg_tank = 0, upg_nozzle = 0, upg_turbine = 0, upg_motor = 0 },
	Pets = {},
	PetCapacity = 200,
	Cosmetics = { Owned = {} },
	Trophies = {},
	Boosts = {},
	Gamepasses = {},
	Progress = {
		Worlds = { Cleanville = true },
		Bosses = {},
		Mastery = {},
	},
	Daily = { CrateDay = -1 },
	Settings = {
		SkipIntro = false,
		ClassicShop = false,
		ReduceMotion = false,
		SeenIntro = false,
	},
	Stats = { Purchases = 0, FactoryVisits = 0, TestRuns = 0, CoinsSpent = 0 },
	Receipts = {},
} :: PlayerData

-- Fields that never leave the server.
DataTemplate.ServerOnly = { "Receipts" }

-- Settings a client may change through SetSetting, with their value type.
DataTemplate.ClientSettings = {
	LowGraphics = "boolean",
	SkipIntro = "boolean",
	ClassicShop = "boolean",
	ReduceMotion = "boolean",
	SeenIntro = "boolean",
}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

DataTemplate.DeepCopy = deepCopy

-- Fills missing keys from the template without touching existing values.
function DataTemplate.Reconcile(data: { [any]: any }, template: { [any]: any }?)
	local source = template or (DataTemplate.Default :: any)
	for key, value in source do
		if data[key] == nil then
			data[key] = deepCopy(value)
		elseif type(value) == "table" and type(data[key]) == "table" and next(value) ~= nil and value[1] == nil then
			DataTemplate.Reconcile(data[key], value)
		end
	end
end

function DataTemplate.New(): PlayerData
	return deepCopy(DataTemplate.Default)
end

-- Copy safe to send to the owning client.
function DataTemplate.ClientSnapshot(data: PlayerData): { [string]: any }
	local snapshot = deepCopy(data)
	for _, key in DataTemplate.ServerOnly do
		snapshot[key] = nil
	end
	return snapshot
end

return DataTemplate
