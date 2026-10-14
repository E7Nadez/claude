--!strict
-- Capsule machines in the Capsule Hall. Drops are weighted; the server rolls.

local Pets = require(script.Parent.Pets)
local Rarities = require(script.Parent.Rarities)

export type Drop = { Pet: string, Weight: number }

export type Capsule = {
	Id: string,
	Name: string,
	World: string,
	Order: number,
	Rarity: string,
	Price: number,
	Currency: string,
	IconAssetId: number,
	NightOnly: boolean?,
	Description: string,
	Color: Color3,
	Drops: { Drop },
}

local Capsules = {}

Capsules.List = {
	{
		Id = "cap_park",
		Name = "Park Capsule",
		World = "Cleanville",
		Order = 1,
		Rarity = "Common",
		Price = 500,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Fresh from the park. Mostly fluffy.",
		Color = Color3.fromRGB(120, 220, 120),
		Drops = {
			{ Pet = "pet_dust_bunny", Weight = 60 },
			{ Pet = "pet_trash_cat", Weight = 28 },
			{ Pet = "pet_mop_pup", Weight = 10 },
			{ Pet = "pet_neon_slime", Weight = 1.8 },
			{ Pet = "pet_robo_raccoon", Weight = 0.2 },
		},
	},
	{
		Id = "cap_neon",
		Name = "Neon Capsule",
		World = "Cleanville",
		Order = 2,
		Rarity = "Epic",
		Price = 15_000,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Downtown glow. Rare bots inside.",
		Color = Color3.fromRGB(200, 90, 255),
		Drops = {
			{ Pet = "pet_trash_cat", Weight = 50 },
			{ Pet = "pet_mop_pup", Weight = 32 },
			{ Pet = "pet_neon_slime", Weight = 14 },
			{ Pet = "pet_robo_raccoon", Weight = 3.6 },
			{ Pet = "pet_golden_hoover_bot", Weight = 0.4 },
		},
	},
	{
		Id = "cap_moonlight",
		Name = "Moonlight Capsule",
		World = "Cleanville",
		Order = 3,
		Rarity = "Legendary",
		Price = 40_000,
		Currency = "Coins",
		IconAssetId = 0,
		NightOnly = true,
		Description = "Only rolls out after dark.",
		Color = Color3.fromRGB(150, 160, 255),
		Drops = {
			{ Pet = "pet_mop_pup", Weight = 45 },
			{ Pet = "pet_moon_moth", Weight = 35 },
			{ Pet = "pet_neon_slime", Weight = 15 },
			{ Pet = "pet_star_slime", Weight = 4.5 },
			{ Pet = "pet_golden_hoover_bot", Weight = 0.5 },
		},
	},
	{
		Id = "cap_dune",
		Name = "Dune Capsule",
		World = "Dustlands",
		Order = 1,
		Rarity = "Common",
		Price = 3_000_000,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Shake the sand off first.",
		Color = Color3.fromRGB(230, 190, 120),
		Drops = {
			{ Pet = "pet_sand_scorpion", Weight = 60 },
			{ Pet = "pet_tumble_ghost", Weight = 28 },
			{ Pet = "pet_cactus_buddy", Weight = 10 },
			{ Pet = "pet_brass_beetle", Weight = 1.8 },
			{ Pet = "pet_bone_drake", Weight = 0.2 },
		},
	},
	{
		Id = "cap_brass",
		Name = "Brass Capsule",
		World = "Dustlands",
		Order = 2,
		Rarity = "Epic",
		Price = 40_000_000,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Riveted shut. Something warm ticks inside.",
		Color = Color3.fromRGB(210, 160, 80),
		Drops = {
			{ Pet = "pet_tumble_ghost", Weight = 50 },
			{ Pet = "pet_cactus_buddy", Weight = 32 },
			{ Pet = "pet_brass_beetle", Weight = 14 },
			{ Pet = "pet_bone_drake", Weight = 3.6 },
			{ Pet = "pet_ember_wyrmling", Weight = 0.4 },
		},
	},
	{
		Id = "cap_eclipse",
		Name = "Eclipse Capsule",
		World = "Dustlands",
		Order = 3,
		Rarity = "Legendary",
		Price = 120_000_000,
		Currency = "Coins",
		IconAssetId = 0,
		NightOnly = true,
		Description = "Desert nights hide the rarest creatures.",
		Color = Color3.fromRGB(255, 120, 80),
		Drops = {
			{ Pet = "pet_cactus_buddy", Weight = 45 },
			{ Pet = "pet_moon_moth", Weight = 35 },
			{ Pet = "pet_brass_beetle", Weight = 15 },
			{ Pet = "pet_star_slime", Weight = 4.5 },
			{ Pet = "pet_ember_wyrmling", Weight = 0.5 },
		},
	},
} :: { Capsule }

Capsules.ById = {} :: { [string]: Capsule }
for _, capsule in Capsules.List do
	for _, drop in capsule.Drops do
		assert(Pets.ById[drop.Pet], "Capsule " .. capsule.Id .. " drops unknown pet " .. drop.Pet)
	end
	Capsules.ById[capsule.Id] = capsule
end

function Capsules.Get(id: string): Capsule?
	return Capsules.ById[id]
end

function Capsules.ForWorld(worldId: string): { Capsule }
	local list = {}
	for _, capsule in Capsules.List do
		if capsule.World == worldId then
			table.insert(list, capsule)
		end
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

-- Weights after the luck multiplier (applies to Epic and above).
function Capsules.EffectiveDrops(id: string, luck: number?): { { Pet: string, Weight: number, Chance: number } }
	local capsule = Capsules.ById[id]
	if not capsule then
		return {}
	end
	local multiplier = luck or 1
	local total = 0
	local list = {}
	for _, drop in capsule.Drops do
		local pet = Pets.ById[drop.Pet]
		local weight = drop.Weight
		if Rarities.AtLeast(pet.Rarity, "Epic") then
			weight *= multiplier
		end
		total += weight
		table.insert(list, { Pet = drop.Pet, Weight = weight, Chance = 0 })
	end
	for _, entry in list do
		entry.Chance = entry.Weight / total
	end
	return list
end

-- Server-side roll. `rng` must be a server Random.
function Capsules.Roll(id: string, rng: Random, luck: number?): string?
	local drops = Capsules.EffectiveDrops(id, luck)
	if #drops == 0 then
		return nil
	end
	local roll = rng:NextNumber()
	local acc = 0
	for _, entry in drops do
		acc += entry.Chance
		if roll <= acc then
			return entry.Pet
		end
	end
	return drops[#drops].Pet
end

return Capsules
