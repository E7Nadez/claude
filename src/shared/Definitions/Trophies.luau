--!strict
-- Boss shop ("Trophy Vault"). Bought with boss cores, displayed on pedestals.

export type Trophy = {
	Id: string,
	Name: string,
	Boss: string,
	Rarity: string,
	Price: number,
	Currency: string,
	IconAssetId: number,
	Order: number,
	Model: string,
	Description: string,
	Perk: { Stat: string, Bonus: number }?,
}

local Trophies = {}

Trophies.List = {
	{ Id = "tro_mini_trash_king", Name = "Mini Trash King", Boss = "TrashKing", Rarity = "Epic", Price = 3, Currency = "TrashKingCore", IconAssetId = 0, Order = 1, Model = "MiniTrashKing", Description = "He still thinks he rules the dump.", Perk = { Stat = "Coins", Bonus = 0.05 } },
	{ Id = "tro_golden_plunger", Name = "Golden Plunger", Boss = "TrashKing", Rarity = "Legendary", Price = 6, Currency = "TrashKingCore", IconAssetId = 0, Order = 2, Model = "GoldenPlunger", Description = "The royal scepter, freshly polished.", Perk = { Stat = "Speed", Bonus = 0.05 } },
	{ Id = "tro_kings_crown", Name = "Crown of Rubbish", Boss = "TrashKing", Rarity = "Mythic", Price = 12, Currency = "TrashKingCore", IconAssetId = 0, Order = 3, Model = "KingsCrown", Description = "Heavy is the head that wears it.", Perk = { Stat = "Coins", Bonus = 0.15 } },
	{ Id = "tro_dragon_heart", Name = "Furnace Heart", Boss = "RustDragon", Rarity = "Epic", Price = 2, Currency = "RustDragonCore", IconAssetId = 0, Order = 4, Model = "DragonHeart", Description = "Still warm. Still beating.", Perk = { Stat = "Power", Bonus = 0.05 } },
	{ Id = "tro_mini_rust_dragon", Name = "Mini Rust Dragon", Boss = "RustDragon", Rarity = "Legendary", Price = 5, Currency = "RustDragonCore", IconAssetId = 0, Order = 5, Model = "MiniRustDragon", Description = "Breathes tiny fireballs. Mostly harmless.", Perk = { Stat = "Coins", Bonus = 0.1 } },
	{ Id = "tro_wyrm_skull", Name = "Wyrm Skull", Boss = "RustDragon", Rarity = "Mythic", Price = 12, Currency = "RustDragonCore", IconAssetId = 0, Order = 6, Model = "WyrmSkull", Description = "The jaw still clacks at midnight.", Perk = { Stat = "Capacity", Bonus = 0.2 } },
} :: { Trophy }

Trophies.ById = {} :: { [string]: Trophy }
for _, trophy in Trophies.List do
	Trophies.ById[trophy.Id] = trophy
end

function Trophies.Get(id: string): Trophy?
	return Trophies.ById[id]
end

return Trophies
