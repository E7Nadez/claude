--!strict
-- Permanent upgrades bought in the Upgrade Lab. Each one boosts one vacuum
-- stat for every vacuum and is shown as a machine that physically grows.

export type Upgrade = {
	Id: string,
	Name: string,
	Stat: "Power" | "Capacity" | "Speed" | "Range",
	Machine: "Tank" | "Nozzle" | "Turbine" | "Motor",
	MaxLevel: number,
	BaseCost: number,
	CostGrowth: number,
	BonusPerLevel: number,
	Order: number,
	Rarity: string,
	IconAssetId: number,
	Glyph: string,
	Description: string,
}

local Upgrades = {}

Upgrades.List = {
	{
		Id = "upg_tank",
		Name = "Mega Tank",
		Stat = "Capacity",
		Machine = "Tank",
		MaxLevel = 25,
		BaseCost = 150,
		CostGrowth = 1.62,
		BonusPerLevel = 0.15,
		Order = 1,
		Rarity = "Uncommon",
		IconAssetId = 0,
		Glyph = "🛢",
		Description = "A bigger tank means fewer trips to sell.",
	},
	{
		Id = "upg_nozzle",
		Name = "Wide Nozzle",
		Stat = "Range",
		Machine = "Nozzle",
		MaxLevel = 25,
		BaseCost = 220,
		CostGrowth = 1.6,
		BonusPerLevel = 0.04,
		Order = 2,
		Rarity = "Rare",
		IconAssetId = 0,
		Glyph = "📡",
		Description = "Pull trash in from further away.",
	},
	{
		Id = "upg_turbine",
		Name = "Turbo Turbine",
		Stat = "Power",
		Machine = "Turbine",
		MaxLevel = 25,
		BaseCost = 400,
		CostGrowth = 1.68,
		BonusPerLevel = 0.1,
		Order = 3,
		Rarity = "Epic",
		IconAssetId = 0,
		Glyph = "🌀",
		Description = "More suction power lifts heavier objects.",
	},
	{
		Id = "upg_motor",
		Name = "Hyper Motor",
		Stat = "Speed",
		Machine = "Motor",
		MaxLevel = 25,
		BaseCost = 300,
		CostGrowth = 1.64,
		BonusPerLevel = 0.06,
		Order = 4,
		Rarity = "Legendary",
		IconAssetId = 0,
		Glyph = "⚙",
		Description = "Faster motor, faster pulls.",
	},
} :: { Upgrade }

Upgrades.ById = {} :: { [string]: Upgrade }
for _, upgrade in Upgrades.List do
	Upgrades.ById[upgrade.Id] = upgrade
end

function Upgrades.Get(id: string): Upgrade?
	return Upgrades.ById[id]
end

-- Cost to go from `level` to `level + 1`.
function Upgrades.Cost(id: string, level: number): number
	local upgrade = Upgrades.ById[id]
	if not upgrade then
		return math.huge
	end
	return math.floor(upgrade.BaseCost * upgrade.CostGrowth ^ level + 0.5)
end

function Upgrades.Multiplier(id: string, level: number): number
	local upgrade = Upgrades.ById[id]
	if not upgrade then
		return 1
	end
	return 1 + upgrade.BonusPerLevel * level
end

-- Combined multipliers per stat from a { [upgradeId]: level } table.
function Upgrades.StatMultipliers(levels: { [string]: number }?): { [string]: number }
	local result = { Power = 1, Capacity = 1, Speed = 1, Range = 1 }
	if not levels then
		return result
	end
	for id, level in levels do
		local upgrade = Upgrades.ById[id]
		if upgrade then
			result[upgrade.Stat] *= Upgrades.Multiplier(id, level)
		end
	end
	return result
end

return Upgrades
