--!strict
-- All vacuums. The Mega-Factory showroom of a world shows the vacuums whose
-- World matches. Look drives the procedural model (Models/VacuumModel) until a
-- real mesh asset is dropped into ReplicatedStorage.Assets.Vacuums.<ModelName>.

export type Stats = {
	Power: number, -- heaviest trash weight it can lift
	Capacity: number, -- tank volume before it has to dump
	Speed: number, -- pulls per second
	Range: number, -- studs
}

export type Condition = { [string]: any }

export type Look = {
	Shape: "Canister" | "Upright" | "Backpack" | "Turbine" | "Cannon" | "Dragon",
	Body: Color3,
	Accent: Color3,
	Glow: Color3,
	Metal: Color3?,
	Material: Enum.Material?,
	Scale: number?,
}

export type Vacuum = {
	Id: string,
	Name: string,
	World: string,
	Order: number,
	Rarity: string,
	Price: number,
	Currency: string,
	IconAssetId: number,
	ModelName: string?,
	Description: string,
	Stats: Stats,
	Unlock: { Condition },
	Look: Look,
	Starter: boolean?,
}

local Vacuums = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Vacuums.List = {
	-- Cleanville ---------------------------------------------------------
	{
		Id = "vac_dust_buster",
		Name = "Dust Buster",
		World = "Cleanville",
		Order = 1,
		Rarity = "Common",
		Price = 0,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Every legend starts somewhere. Handles leaves and dust.",
		Stats = { Power = 1, Capacity = 20, Speed = 1.0, Range = 6 },
		Unlock = {},
		Look = { Shape = "Canister", Body = rgb(210, 70, 60), Accent = rgb(60, 60, 70), Glow = rgb(255, 200, 120) },
		Starter = true,
	},
	{
		Id = "vac_leaf_gobbler",
		Name = "Leaf Gobbler",
		World = "Cleanville",
		Order = 2,
		Rarity = "Common",
		Price = 250,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Wide mouth, big appetite. Parks fear it.",
		Stats = { Power = 2, Capacity = 40, Speed = 1.3, Range = 7 },
		Unlock = { { Type = "OwnsVacuum", Vacuum = "vac_dust_buster" } },
		Look = { Shape = "Canister", Body = rgb(90, 180, 70), Accent = rgb(50, 70, 40), Glow = rgb(200, 255, 120) },
	},
	{
		Id = "vac_can_crusher",
		Name = "Can Crusher 3000",
		World = "Cleanville",
		Order = 3,
		Rarity = "Uncommon",
		Price = 1_200,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Compresses cans mid-flight. Very satisfying.",
		Stats = { Power = 4, Capacity = 80, Speed = 1.7, Range = 8 },
		Unlock = { { Type = "OwnsVacuum", Vacuum = "vac_leaf_gobbler" } },
		Look = { Shape = "Upright", Body = rgb(230, 160, 40), Accent = rgb(40, 40, 48), Glow = rgb(255, 240, 160) },
	},
	{
		Id = "vac_turbo_twister",
		Name = "Turbo Twister",
		World = "Cleanville",
		Order = 4,
		Rarity = "Uncommon",
		Price = 5_000,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "A cyclone in a can. Neighborhood approved.",
		Stats = { Power = 7, Capacity = 150, Speed = 2.2, Range = 9 },
		Unlock = { { Type = "OwnsVacuum", Vacuum = "vac_can_crusher" } },
		Look = { Shape = "Upright", Body = rgb(60, 200, 210), Accent = rgb(30, 50, 70), Glow = rgb(140, 255, 255) },
	},
	{
		Id = "vac_hydro_hoover",
		Name = "Hydro Hoover",
		World = "Cleanville",
		Order = 5,
		Rarity = "Rare",
		Price = 20_000,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Water-cooled turbine for nonstop downtown cleanup.",
		Stats = { Power = 12, Capacity = 280, Speed = 2.8, Range = 10 },
		Unlock = { { Type = "OwnsVacuum", Vacuum = "vac_turbo_twister" } },
		Look = { Shape = "Backpack", Body = rgb(40, 110, 230), Accent = rgb(220, 230, 240), Glow = rgb(90, 200, 255) },
	},
	{
		Id = "vac_neon_nebula",
		Name = "Neon Nebula",
		World = "Cleanville",
		Order = 6,
		Rarity = "Epic",
		Price = 85_000,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Glows brighter the more it eats. Bikes included.",
		Stats = { Power = 20, Capacity = 500, Speed = 3.6, Range = 12 },
		Unlock = { { Type = "OwnsVacuum", Vacuum = "vac_hydro_hoover" } },
		Look = {
			Shape = "Turbine",
			Body = rgb(40, 20, 70),
			Accent = rgb(180, 80, 255),
			Glow = rgb(255, 80, 230),
			Material = Enum.Material.Glass,
		},
	},
	{
		Id = "vac_chrome_cyclone",
		Name = "Chrome Cyclone",
		World = "Cleanville",
		Order = 7,
		Rarity = "Legendary",
		Price = 350_000,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Polished to a mirror finish. Swallows car doors whole.",
		Stats = { Power = 35, Capacity = 900, Speed = 4.6, Range = 14 },
		Unlock = { { Type = "OwnsVacuum", Vacuum = "vac_neon_nebula" } },
		Look = {
			Shape = "Cannon",
			Body = rgb(220, 226, 236),
			Accent = rgb(255, 190, 60),
			Glow = rgb(120, 230, 255),
			Material = Enum.Material.Metal,
			Scale = 1.15,
		},
	},
	{
		Id = "vac_trash_kings_maw",
		Name = "Trash King's Maw",
		World = "Cleanville",
		Order = 8,
		Rarity = "Mythic",
		Price = 1_500_000,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Forged from the Trash King's crown. Eats whole cars.",
		Stats = { Power = 60, Capacity = 1_600, Speed = 6.0, Range = 16 },
		Unlock = {
			{ Type = "OwnsVacuum", Vacuum = "vac_chrome_cyclone" },
			{ Type = "BossDefeated", Boss = "TrashKing" },
		},
		Look = {
			Shape = "Dragon",
			Body = rgb(60, 50, 40),
			Accent = rgb(255, 200, 40),
			Glow = rgb(150, 255, 80),
			Material = Enum.Material.Metal,
			Scale = 1.3,
		},
	},

	-- Dustlands ----------------------------------------------------------
	{
		Id = "vac_sandsifter",
		Name = "Sandsifter",
		World = "Dustlands",
		Order = 1,
		Rarity = "Common",
		Price = 2_500_000,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Filters the desert one dune at a time.",
		Stats = { Power = 80, Capacity = 2_200, Speed = 6.8, Range = 16 },
		Unlock = { { Type = "WorldUnlocked", World = "Dustlands" } },
		Look = { Shape = "Canister", Body = rgb(214, 180, 120), Accent = rgb(120, 80, 50), Glow = rgb(255, 220, 140) },
	},
	{
		Id = "vac_cactus_clipper",
		Name = "Cactus Clipper",
		World = "Dustlands",
		Order = 2,
		Rarity = "Uncommon",
		Price = 6_000_000,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Spines? Never heard of them.",
		Stats = { Power = 110, Capacity = 3_000, Speed = 7.6, Range = 17 },
		Unlock = { { Type = "OwnsVacuum", Vacuum = "vac_sandsifter" } },
		Look = { Shape = "Upright", Body = rgb(80, 150, 70), Accent = rgb(196, 150, 72), Glow = rgb(220, 255, 120) },
	},
	{
		Id = "vac_dune_devourer",
		Name = "Dune Devourer",
		World = "Dustlands",
		Order = 3,
		Rarity = "Rare",
		Price = 15_000_000,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Brass intake, endless hunger.",
		Stats = { Power = 150, Capacity = 4_200, Speed = 8.5, Range = 18 },
		Unlock = { { Type = "OwnsVacuum", Vacuum = "vac_cactus_clipper" } },
		Look = { Shape = "Backpack", Body = rgb(196, 150, 72), Accent = rgb(90, 60, 40), Glow = rgb(255, 170, 60) },
	},
	{
		Id = "vac_bone_grinder",
		Name = "Bone Grinder",
		World = "Dustlands",
		Order = 4,
		Rarity = "Rare",
		Price = 35_000_000,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Bone Canyon's least favorite visitor.",
		Stats = { Power = 200, Capacity = 5_800, Speed = 9.6, Range = 19 },
		Unlock = { { Type = "OwnsVacuum", Vacuum = "vac_dune_devourer" } },
		Look = { Shape = "Backpack", Body = rgb(236, 226, 200), Accent = rgb(60, 50, 44), Glow = rgb(255, 120, 80) },
	},
	{
		Id = "vac_mirage_vortex",
		Name = "Mirage Vortex",
		World = "Dustlands",
		Order = 5,
		Rarity = "Epic",
		Price = 90_000_000,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Is it really there? The trash certainly isn't.",
		Stats = { Power = 270, Capacity = 8_000, Speed = 11, Range = 21 },
		Unlock = { { Type = "OwnsVacuum", Vacuum = "vac_bone_grinder" } },
		Look = {
			Shape = "Turbine",
			Body = rgb(255, 200, 120),
			Accent = rgb(80, 200, 220),
			Glow = rgb(255, 240, 200),
			Material = Enum.Material.Glass,
		},
	},
	{
		Id = "vac_ghost_town_gale",
		Name = "Ghost Town Gale",
		World = "Dustlands",
		Order = 6,
		Rarity = "Epic",
		Price = 220_000_000,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Howls like the wind through empty saloons.",
		Stats = { Power = 360, Capacity = 11_000, Speed = 12.5, Range = 23 },
		Unlock = { { Type = "OwnsVacuum", Vacuum = "vac_mirage_vortex" } },
		Look = { Shape = "Turbine", Body = rgb(60, 70, 80), Accent = rgb(170, 220, 255), Glow = rgb(170, 255, 230) },
	},
	{
		Id = "vac_brass_behemoth",
		Name = "Brass Behemoth",
		World = "Dustlands",
		Order = 7,
		Rarity = "Legendary",
		Price = 600_000_000,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Steam-powered, gear-driven, unstoppable.",
		Stats = { Power = 480, Capacity = 15_000, Speed = 14.5, Range = 25 },
		Unlock = { { Type = "OwnsVacuum", Vacuum = "vac_ghost_town_gale" } },
		Look = {
			Shape = "Cannon",
			Body = rgb(196, 150, 72),
			Accent = rgb(110, 60, 30),
			Glow = rgb(255, 160, 60),
			Material = Enum.Material.Metal,
			Scale = 1.2,
		},
	},
	{
		Id = "vac_wyrmfire_devourer",
		Name = "Wyrmfire Devourer",
		World = "Dustlands",
		Order = 8,
		Rarity = "Mythic",
		Price = 2_000_000_000,
		Currency = "Coins",
		IconAssetId = 0,
		Description = "Built around the Rust Dragon's furnace heart.",
		Stats = { Power = 700, Capacity = 22_000, Speed = 17, Range = 28 },
		Unlock = {
			{ Type = "OwnsVacuum", Vacuum = "vac_brass_behemoth" },
			{ Type = "BossDefeated", Boss = "RustDragon" },
		},
		Look = {
			Shape = "Dragon",
			Body = rgb(140, 60, 36),
			Accent = rgb(230, 170, 70),
			Glow = rgb(255, 110, 30),
			Material = Enum.Material.CorrodedMetal,
			Scale = 1.35,
		},
	},
} :: { Vacuum }

Vacuums.ById = {} :: { [string]: Vacuum }
for _, vacuum in Vacuums.List do
	assert(Vacuums.ById[vacuum.Id] == nil, "Duplicate vacuum id " .. vacuum.Id)
	Vacuums.ById[vacuum.Id] = vacuum
end

Vacuums.StarterId = "vac_dust_buster"

function Vacuums.Get(id: string?): Vacuum?
	if id == nil then
		return nil
	end
	return Vacuums.ById[id]
end

function Vacuums.ForWorld(worldId: string): { Vacuum }
	local list = {}
	for _, vacuum in Vacuums.List do
		if vacuum.World == worldId then
			table.insert(list, vacuum)
		end
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

return Vacuums
