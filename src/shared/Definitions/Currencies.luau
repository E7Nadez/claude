--!strict
-- Every currency the shop can charge. "Robux" is never stored in player data,
-- it only routes the purchase through MarketplaceService.

export type Currency = {
	Id: string,
	Name: string,
	Short: string,
	Kind: "Soft" | "BossCore" | "Robux",
	Color: Color3,
	Glyph: string,
	Boss: string?,
	IconAssetId: number?,
}

local Currencies = {}

Currencies.Info = {
	Coins = {
		Id = "Coins",
		Name = "Coins",
		Short = "Coins",
		Kind = "Soft",
		Color = Color3.fromRGB(255, 204, 64),
		Glyph = "🪙",
		IconAssetId = 0,
	},
	TrashKingCore = {
		Id = "TrashKingCore",
		Name = "Trash King Core",
		Short = "TK Cores",
		Kind = "BossCore",
		Color = Color3.fromRGB(150, 230, 90),
		Glyph = "👑",
		Boss = "TrashKing",
		IconAssetId = 0,
	},
	RustDragonCore = {
		Id = "RustDragonCore",
		Name = "Rust Dragon Core",
		Short = "RD Cores",
		Kind = "BossCore",
		Color = Color3.fromRGB(255, 120, 60),
		Glyph = "🐉",
		Boss = "RustDragon",
		IconAssetId = 0,
	},
	Robux = {
		Id = "Robux",
		Name = "Robux",
		Short = "R$",
		Kind = "Robux",
		Color = Color3.fromRGB(80, 230, 140),
		Glyph = "R$",
		IconAssetId = 0,
	},
} :: { [string]: Currency }

-- Currencies kept in player data (everything except Robux).
Currencies.Stored = { "Coins", "TrashKingCore", "RustDragonCore" }

function Currencies.Get(id: string): Currency?
	return Currencies.Info[id]
end

function Currencies.IsStored(id: string): boolean
	return table.find(Currencies.Stored, id) ~= nil
end

return Currencies
