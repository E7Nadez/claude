--!strict
-- Trash sets used by the Test Chamber conveyor (and the stat comparison).
-- Weight = power needed to lift it. Volume = tank space it uses.

export type TrashItem = {
	Id: string,
	Name: string,
	Weight: number,
	Volume: number,
	Chance: number,
	Shape: "Block" | "Ball" | "Cylinder" | "Wedge",
	Size: Vector3,
	Color: Color3,
	Material: Enum.Material,
}

local Trash = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Trash.Sets = {
	Cleanville = {
		{ Id = "leaf", Name = "Leaf", Weight = 1, Volume = 1, Chance = 30, Shape = "Wedge", Size = Vector3.new(0.9, 0.15, 0.9), Color = rgb(200, 140, 50), Material = Enum.Material.Grass },
		{ Id = "can", Name = "Soda Can", Weight = 2, Volume = 1, Chance = 22, Shape = "Cylinder", Size = Vector3.new(0.9, 0.5, 0.5), Color = rgb(220, 40, 50), Material = Enum.Material.Metal },
		{ Id = "bottle", Name = "Bottle", Weight = 3, Volume = 2, Chance = 16, Shape = "Cylinder", Size = Vector3.new(1.3, 0.55, 0.55), Color = rgb(120, 220, 160), Material = Enum.Material.Glass },
		{ Id = "pizza_box", Name = "Pizza Box", Weight = 5, Volume = 3, Chance = 12, Shape = "Block", Size = Vector3.new(1.6, 0.25, 1.6), Color = rgb(220, 190, 140), Material = Enum.Material.Cardboard },
		{ Id = "tire", Name = "Tire", Weight = 10, Volume = 6, Chance = 8, Shape = "Cylinder", Size = Vector3.new(0.8, 2.2, 2.2), Color = rgb(30, 30, 34), Material = Enum.Material.Rubber },
		{ Id = "bike", Name = "Bicycle", Weight = 18, Volume = 10, Chance = 6, Shape = "Block", Size = Vector3.new(3, 1.8, 0.5), Color = rgb(60, 130, 230), Material = Enum.Material.Metal },
		{ Id = "bin", Name = "Trash Bin", Weight = 30, Volume = 16, Chance = 4, Shape = "Cylinder", Size = Vector3.new(2.6, 1.8, 1.8), Color = rgb(50, 120, 70), Material = Enum.Material.Plastic },
		{ Id = "car", Name = "Car", Weight = 50, Volume = 30, Chance = 2, Shape = "Block", Size = Vector3.new(5, 2.2, 2.6), Color = rgb(230, 60, 60), Material = Enum.Material.SmoothPlastic },
	},
	Dustlands = {
		{ Id = "tumbleweed", Name = "Tumbleweed", Weight = 60, Volume = 20, Chance = 30, Shape = "Ball", Size = Vector3.new(1.8, 1.8, 1.8), Color = rgb(170, 130, 70), Material = Enum.Material.Grass },
		{ Id = "bone", Name = "Bone", Weight = 80, Volume = 24, Chance = 22, Shape = "Cylinder", Size = Vector3.new(2, 0.5, 0.5), Color = rgb(236, 228, 210), Material = Enum.Material.SmoothPlastic },
		{ Id = "cactus", Name = "Cactus", Weight = 100, Volume = 30, Chance = 16, Shape = "Cylinder", Size = Vector3.new(2.4, 0.9, 0.9), Color = rgb(70, 150, 70), Material = Enum.Material.Grass },
		{ Id = "skull", Name = "Cow Skull", Weight = 140, Volume = 40, Chance = 12, Shape = "Ball", Size = Vector3.new(1.4, 1.2, 1.6), Color = rgb(240, 236, 220), Material = Enum.Material.SmoothPlastic },
		{ Id = "wheel", Name = "Wagon Wheel", Weight = 200, Volume = 60, Chance = 8, Shape = "Cylinder", Size = Vector3.new(0.4, 3, 3), Color = rgb(120, 80, 50), Material = Enum.Material.Wood },
		{ Id = "barrel", Name = "Barrel", Weight = 280, Volume = 80, Chance = 6, Shape = "Cylinder", Size = Vector3.new(2.4, 1.8, 1.8), Color = rgb(140, 90, 50), Material = Enum.Material.WoodPlanks },
		{ Id = "wagon", Name = "Wagon", Weight = 400, Volume = 120, Chance = 4, Shape = "Block", Size = Vector3.new(4.5, 2.4, 2.6), Color = rgb(150, 100, 60), Material = Enum.Material.WoodPlanks },
		{ Id = "safe", Name = "Iron Safe", Weight = 600, Volume = 200, Chance = 2, Shape = "Block", Size = Vector3.new(2.4, 2.4, 2.4), Color = rgb(80, 84, 90), Material = Enum.Material.DiamondPlate },
	},
} :: { [string]: { TrashItem } }

function Trash.Get(setId: string): { TrashItem }
	return Trash.Sets[setId] or Trash.Sets.Cleanville
end

-- Liftable items for a given power, with their summed chance.
function Trash.Liftable(setId: string, power: number): ({ TrashItem }, number)
	local list = {}
	local chance = 0
	for _, item in Trash.Get(setId) do
		if item.Weight <= power then
			table.insert(list, item)
			chance += item.Chance
		end
	end
	return list, chance
end

return Trash
