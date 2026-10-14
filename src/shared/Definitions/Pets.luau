--!strict
-- Pets that can drop from capsules. Look.Type selects the procedural body in
-- Models/PetModel until real meshes are added.

export type Pet = {
	Id: string,
	Name: string,
	Rarity: string,
	Multiplier: number,
	IconAssetId: number,
	Look: { Type: string, Color: Color3, Accent: Color3, Glow: Color3? },
}

local Pets = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Pets.List = {
	-- Cleanville
	{ Id = "pet_dust_bunny", Name = "Dust Bunny", Rarity = "Common", Multiplier = 1.1, IconAssetId = 0, Look = { Type = "Bunny", Color = rgb(200, 196, 190), Accent = rgb(255, 170, 190) } },
	{ Id = "pet_trash_cat", Name = "Trash Cat", Rarity = "Uncommon", Multiplier = 1.25, IconAssetId = 0, Look = { Type = "Cat", Color = rgb(110, 120, 130), Accent = rgb(240, 200, 80) } },
	{ Id = "pet_mop_pup", Name = "Mop Pup", Rarity = "Rare", Multiplier = 1.5, IconAssetId = 0, Look = { Type = "Bunny", Color = rgb(240, 230, 210), Accent = rgb(80, 150, 255) } },
	{ Id = "pet_neon_slime", Name = "Neon Slime", Rarity = "Epic", Multiplier = 2, IconAssetId = 0, Look = { Type = "Blob", Color = rgb(80, 255, 170), Accent = rgb(30, 120, 80), Glow = rgb(120, 255, 200) } },
	{ Id = "pet_robo_raccoon", Name = "Robo Raccoon", Rarity = "Legendary", Multiplier = 3, IconAssetId = 0, Look = { Type = "Bot", Color = rgb(90, 96, 110), Accent = rgb(40, 220, 255), Glow = rgb(40, 220, 255) } },
	{ Id = "pet_golden_hoover_bot", Name = "Golden Hoover Bot", Rarity = "Mythic", Multiplier = 5, IconAssetId = 0, Look = { Type = "Bot", Color = rgb(255, 200, 60), Accent = rgb(255, 255, 255), Glow = rgb(255, 230, 120) } },
	-- Dustlands
	{ Id = "pet_sand_scorpion", Name = "Sand Scorpion", Rarity = "Common", Multiplier = 6, IconAssetId = 0, Look = { Type = "Scorpion", Color = rgb(214, 170, 100), Accent = rgb(120, 70, 40) } },
	{ Id = "pet_tumble_ghost", Name = "Tumble Ghost", Rarity = "Uncommon", Multiplier = 7.5, IconAssetId = 0, Look = { Type = "Ghost", Color = rgb(240, 236, 220), Accent = rgb(120, 200, 255) } },
	{ Id = "pet_cactus_buddy", Name = "Cactus Buddy", Rarity = "Rare", Multiplier = 9, IconAssetId = 0, Look = { Type = "Cactus", Color = rgb(80, 160, 80), Accent = rgb(255, 120, 170) } },
	{ Id = "pet_brass_beetle", Name = "Brass Beetle", Rarity = "Epic", Multiplier = 12, IconAssetId = 0, Look = { Type = "Bot", Color = rgb(196, 150, 72), Accent = rgb(110, 60, 30), Glow = rgb(255, 170, 60) } },
	{ Id = "pet_bone_drake", Name = "Bone Drake", Rarity = "Legendary", Multiplier = 18, IconAssetId = 0, Look = { Type = "Dragon", Color = rgb(236, 228, 210), Accent = rgb(80, 70, 60), Glow = rgb(120, 255, 200) } },
	{ Id = "pet_ember_wyrmling", Name = "Ember Wyrmling", Rarity = "Mythic", Multiplier = 30, IconAssetId = 0, Look = { Type = "Dragon", Color = rgb(170, 70, 40), Accent = rgb(255, 190, 80), Glow = rgb(255, 110, 30) } },
	-- Night exclusives
	{ Id = "pet_moon_moth", Name = "Moon Moth", Rarity = "Epic", Multiplier = 2.4, IconAssetId = 0, Look = { Type = "Ghost", Color = rgb(170, 180, 255), Accent = rgb(255, 255, 200), Glow = rgb(200, 210, 255) } },
	{ Id = "pet_star_slime", Name = "Star Slime", Rarity = "Legendary", Multiplier = 4, IconAssetId = 0, Look = { Type = "Blob", Color = rgb(60, 50, 140), Accent = rgb(255, 240, 120), Glow = rgb(140, 120, 255) } },
} :: { Pet }

Pets.ById = {} :: { [string]: Pet }
for _, pet in Pets.List do
	Pets.ById[pet.Id] = pet
end

function Pets.Get(id: string): Pet?
	return Pets.ById[id]
end

return Pets
