--!strict
-- Rarity tiers. Colors drive UI accents, podium lights and sequence effects.

export type Rarity = {
	Id: string,
	Name: string,
	Rank: number,
	Color: Color3,
	Gradient: { Color3 },
	Glyph: string,
}

local Rarities = {}

Rarities.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

Rarities.Info = {
	Common = {
		Id = "Common",
		Name = "Common",
		Rank = 1,
		Color = Color3.fromRGB(176, 188, 204),
		Gradient = { Color3.fromRGB(120, 132, 150), Color3.fromRGB(196, 206, 220) },
		Glyph = "●",
	},
	Uncommon = {
		Id = "Uncommon",
		Name = "Uncommon",
		Rank = 2,
		Color = Color3.fromRGB(88, 220, 128),
		Gradient = { Color3.fromRGB(34, 150, 88), Color3.fromRGB(120, 240, 150) },
		Glyph = "◆",
	},
	Rare = {
		Id = "Rare",
		Name = "Rare",
		Rank = 3,
		Color = Color3.fromRGB(70, 160, 255),
		Gradient = { Color3.fromRGB(30, 92, 220), Color3.fromRGB(96, 196, 255) },
		Glyph = "★",
	},
	Epic = {
		Id = "Epic",
		Name = "Epic",
		Rank = 4,
		Color = Color3.fromRGB(182, 96, 255),
		Gradient = { Color3.fromRGB(110, 40, 220), Color3.fromRGB(214, 140, 255) },
		Glyph = "✦",
	},
	Legendary = {
		Id = "Legendary",
		Name = "Legendary",
		Rank = 5,
		Color = Color3.fromRGB(255, 186, 52),
		Gradient = { Color3.fromRGB(255, 132, 20), Color3.fromRGB(255, 226, 110) },
		Glyph = "♛",
	},
	Mythic = {
		Id = "Mythic",
		Name = "Mythic",
		Rank = 6,
		Color = Color3.fromRGB(255, 70, 140),
		Gradient = { Color3.fromRGB(255, 40, 90), Color3.fromRGB(140, 80, 255) },
		Glyph = "✺",
	},
} :: { [string]: Rarity }

function Rarities.Get(id: string?): Rarity
	return Rarities.Info[id or "Common"] or Rarities.Info.Common
end

function Rarities.Rank(id: string?): number
	return Rarities.Get(id).Rank
end

function Rarities.AtLeast(id: string?, minimum: string): boolean
	return Rarities.Rank(id) >= Rarities.Rank(minimum)
end

function Rarities.ColorSequence(id: string?): ColorSequence
	local info = Rarities.Get(id)
	return ColorSequence.new(info.Gradient[1], info.Gradient[2])
end

return Rarities
