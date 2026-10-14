--!strict
-- Skins (paint jobs) and trails, applied in the paint shop.

export type Cosmetic = {
	Id: string,
	Name: string,
	Slot: "Skin" | "Trail",
	Rarity: string,
	Price: number,
	Currency: string,
	IconAssetId: number,
	Order: number,
	NightOnly: boolean?,
	Description: string,
	-- Skin
	Body: Color3?,
	Accent: Color3?,
	Glow: Color3?,
	Material: Enum.Material?,
	-- Trail
	Colors: { Color3 }?,
	Width: number?,
	Lifetime: number?,
}

local Cosmetics = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Cosmetics.List = {
	{ Id = "cos_skin_candy", Name = "Candy Coat", Slot = "Skin", Rarity = "Uncommon", Price = 2_000, Currency = "Coins", IconAssetId = 0, Order = 1, Description = "Sweet pink stripes.", Body = rgb(255, 150, 200), Accent = rgb(255, 255, 255), Glow = rgb(255, 210, 240), Material = Enum.Material.SmoothPlastic },
	{ Id = "cos_skin_midnight", Name = "Midnight Chrome", Slot = "Skin", Rarity = "Rare", Price = 7_500, Currency = "Coins", IconAssetId = 0, Order = 2, Description = "Dark chrome with cyan edges.", Body = rgb(26, 30, 48), Accent = rgb(120, 130, 150), Glow = rgb(40, 230, 255), Material = Enum.Material.Metal },
	{ Id = "cos_skin_toxic", Name = "Toxic Spill", Slot = "Skin", Rarity = "Epic", Price = 60_000, Currency = "Coins", IconAssetId = 0, Order = 3, Description = "Glows. Do not lick.", Body = rgb(40, 60, 30), Accent = rgb(120, 255, 60), Glow = rgb(160, 255, 80), Material = Enum.Material.SmoothPlastic },
	{ Id = "cos_skin_gold", Name = "24K Gold", Slot = "Skin", Rarity = "Legendary", Price = 250_000, Currency = "Coins", IconAssetId = 0, Order = 4, Description = "Solid gold. Probably.", Body = rgb(255, 200, 60), Accent = rgb(180, 120, 30), Glow = rgb(255, 250, 200), Material = Enum.Material.Metal },
	{ Id = "cos_skin_rust", Name = "Desert Rust", Slot = "Skin", Rarity = "Rare", Price = 4_000_000, Currency = "Coins", IconAssetId = 0, Order = 5, Description = "Weathered by a thousand sandstorms.", Body = rgb(150, 80, 50), Accent = rgb(90, 60, 40), Glow = rgb(255, 150, 70), Material = Enum.Material.CorrodedMetal },
	{ Id = "cos_skin_galaxy", Name = "Galaxy Glass", Slot = "Skin", Rarity = "Mythic", Price = 25_000_000, Currency = "Coins", IconAssetId = 0, Order = 6, Description = "A tiny universe in every tank.", Body = rgb(70, 40, 140), Accent = rgb(30, 20, 60), Glow = rgb(255, 120, 255), Material = Enum.Material.Glass },
	{ Id = "cos_skin_neon_night", Name = "Neon Night", Slot = "Skin", Rarity = "Epic", Price = 120_000, Currency = "Coins", IconAssetId = 0, Order = 7, NightOnly = true, Description = "Night deal: pure neon outline.", Body = rgb(15, 15, 25), Accent = rgb(255, 60, 200), Glow = rgb(60, 255, 255), Material = Enum.Material.SmoothPlastic },

	{ Id = "cos_trail_dust", Name = "Dust Cloud", Slot = "Trail", Rarity = "Common", Price = 800, Currency = "Coins", IconAssetId = 0, Order = 10, Description = "Leaves a little puff behind.", Colors = { rgb(200, 190, 170), rgb(120, 110, 100) }, Width = 1.2, Lifetime = 0.5 },
	{ Id = "cos_trail_sparkle", Name = "Sparkle Stream", Slot = "Trail", Rarity = "Uncommon", Price = 3_000, Currency = "Coins", IconAssetId = 0, Order = 11, Description = "Shiny!", Colors = { rgb(255, 255, 255), rgb(140, 220, 255) }, Width = 1, Lifetime = 0.7 },
	{ Id = "cos_trail_rainbow", Name = "Rainbow Rush", Slot = "Trail", Rarity = "Epic", Price = 90_000, Currency = "Coins", IconAssetId = 0, Order = 12, Description = "Every color, all at once.", Colors = { rgb(255, 60, 60), rgb(255, 220, 60), rgb(60, 255, 120), rgb(60, 160, 255), rgb(200, 80, 255) }, Width = 1.4, Lifetime = 0.9 },
	{ Id = "cos_trail_fire", Name = "Afterburner", Slot = "Trail", Rarity = "Legendary", Price = 400_000, Currency = "Coins", IconAssetId = 0, Order = 13, Description = "Hot exhaust, hotter style.", Colors = { rgb(255, 240, 120), rgb(255, 120, 30), rgb(160, 20, 10) }, Width = 1.6, Lifetime = 0.6 },
} :: { Cosmetic }

Cosmetics.ById = {} :: { [string]: Cosmetic }
for _, cosmetic in Cosmetics.List do
	Cosmetics.ById[cosmetic.Id] = cosmetic
end

function Cosmetics.Get(id: string?): Cosmetic?
	if id == nil then
		return nil
	end
	return Cosmetics.ById[id]
end

function Cosmetics.BySlot(slot: string): { Cosmetic }
	local list = {}
	for _, cosmetic in Cosmetics.List do
		if cosmetic.Slot == slot then
			table.insert(list, cosmetic)
		end
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

return Cosmetics
