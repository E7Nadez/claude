--!strict
-- Worlds and the look of the Mega-Factory inside each one.
-- FactoryOrigin is only a fallback: place a Part named "FactoryAnchor" inside
-- workspace.Worlds.<WorldId> (front-center of the building, facing the street,
-- LookVector pointing INTO the factory) and the factory snaps to it.

export type Theme = {
	Id: string,
	Wall: Color3,
	WallMaterial: Enum.Material,
	Floor: Color3,
	FloorMaterial: Enum.Material,
	Trim: Color3,
	TrimMaterial: Enum.Material,
	TrimReflectance: number,
	Metal: Color3,
	Glass: Color3,
	Neon: Color3,
	NeonAlt: Color3,
	NightNeon: Color3,
	Accent: Color3,
	Steam: boolean,
	GearCount: number,
	Ambient: Color3,
}

export type World = {
	Id: string,
	Order: number,
	Name: string,
	Released: boolean,
	FactoryOrigin: CFrame,
	FactoryTheme: string,
	EconomyMultiplier: number, -- scales boost / crate prices and coin packs
	TrashSet: string,
}

local Worlds = {}

Worlds.Themes = {
	Chrome = {
		Id = "Chrome",
		Wall = Color3.fromRGB(34, 38, 50),
		WallMaterial = Enum.Material.Metal,
		Floor = Color3.fromRGB(24, 26, 34),
		FloorMaterial = Enum.Material.DiamondPlate,
		Trim = Color3.fromRGB(214, 222, 236),
		TrimMaterial = Enum.Material.Metal,
		TrimReflectance = 0.35,
		Metal = Color3.fromRGB(150, 160, 178),
		Glass = Color3.fromRGB(150, 220, 255),
		Neon = Color3.fromRGB(40, 220, 255),
		NeonAlt = Color3.fromRGB(255, 70, 200),
		NightNeon = Color3.fromRGB(120, 255, 255),
		Accent = Color3.fromRGB(64, 120, 255),
		Steam = false,
		GearCount = 4,
		Ambient = Color3.fromRGB(110, 140, 190),
	},
	Brass = {
		Id = "Brass",
		Wall = Color3.fromRGB(74, 52, 38),
		WallMaterial = Enum.Material.Brick,
		Floor = Color3.fromRGB(58, 44, 34),
		FloorMaterial = Enum.Material.WoodPlanks,
		Trim = Color3.fromRGB(196, 150, 72),
		TrimMaterial = Enum.Material.Metal,
		TrimReflectance = 0.2,
		Metal = Color3.fromRGB(120, 96, 70),
		Glass = Color3.fromRGB(255, 214, 150),
		Neon = Color3.fromRGB(255, 150, 50),
		NeonAlt = Color3.fromRGB(255, 220, 120),
		NightNeon = Color3.fromRGB(255, 120, 40),
		Accent = Color3.fromRGB(170, 70, 40),
		Steam = true,
		GearCount = 8,
		Ambient = Color3.fromRGB(200, 150, 100),
	},
} :: { [string]: Theme }

Worlds.Info = {
	Cleanville = {
		Id = "Cleanville",
		Order = 1,
		Name = "Cleanville",
		Released = true,
		FactoryOrigin = CFrame.new(0, 0, 260),
		FactoryTheme = "Chrome",
		EconomyMultiplier = 1,
		TrashSet = "Cleanville",
	},
	Dustlands = {
		Id = "Dustlands",
		Order = 2,
		Name = "Dustlands",
		Released = true,
		FactoryOrigin = CFrame.new(1400, 0, 260),
		FactoryTheme = "Brass",
		EconomyMultiplier = 1_500,
		TrashSet = "Dustlands",
	},
	FrostKingdom = {
		Id = "FrostKingdom",
		Order = 3,
		Name = "Frost Kingdom",
		Released = false,
		FactoryOrigin = CFrame.new(2800, 0, 260),
		FactoryTheme = "Chrome",
		EconomyMultiplier = 400_000,
		TrashSet = "Cleanville",
	},
} :: { [string]: World }

function Worlds.Get(id: string): World?
	return Worlds.Info[id]
end

function Worlds.Released(): { World }
	local list = {}
	for _, world in Worlds.Info do
		if world.Released then
			table.insert(list, world)
		end
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

function Worlds.Theme(worldId: string): Theme
	local world = Worlds.Info[worldId]
	return Worlds.Themes[world and world.FactoryTheme or "Chrome"]
end

return Worlds
