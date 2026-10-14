--!strict
-- Layout and tuning of the Vacuum Mega-Factory. All positions are local to the
-- factory origin: X = across the facade, Y = up, Z = into the building
-- (the facade sits at Z = 0 and faces -Z, towards the street).
-- The server builder places geometry from these numbers; the client finds
-- everything again by name/attributes, so geometry can later be swapped for
-- imported mesh assets as long as names stay the same.

local Factory = {}

Factory.Size = Vector3.new(200, 40, 220)
Factory.WallHeight = 40

-- Rooms (XZ rectangles: Min, Max)
Factory.Rooms = {
	Lobby = { Min = Vector2.new(-100, 0), Max = Vector2.new(100, 40) },
	TestChamber = { Min = Vector2.new(-100, 40), Max = Vector2.new(-42, 124) },
	Showroom = { Min = Vector2.new(-42, 40), Max = Vector2.new(42, 124) },
	UpgradeLab = { Min = Vector2.new(42, 40), Max = Vector2.new(100, 124) },
	CapsuleHall = { Min = Vector2.new(-100, 124), Max = Vector2.new(-24, 220) },
	VaultCorridor = { Min = Vector2.new(-24, 124), Max = Vector2.new(24, 150) },
	TrophyVault = { Min = Vector2.new(-24, 150), Max = Vector2.new(24, 220) },
	PaintShop = { Min = Vector2.new(24, 124), Max = Vector2.new(100, 220) },
}

-- Zone list for the HUD quick-travel bar (Spot = where the player is placed).
Factory.Zones = {
	{ Id = "Showroom", Name = "Showroom", Glyph = "🌀", Spot = Vector3.new(0, 3, 50), Face = Vector3.new(0, 0, 1) },
	{ Id = "TestChamber", Name = "Test Lab", Glyph = "🧪", Spot = Vector3.new(-47, 3, 82), Face = Vector3.new(-1, 0, 0) },
	{ Id = "UpgradeLab", Name = "Upgrades", Glyph = "⚙", Spot = Vector3.new(71, 3, 82), Face = Vector3.new(1, 0, 0) },
	{ Id = "CapsuleHall", Name = "Capsules", Glyph = "🥚", Spot = Vector3.new(-62, 3, 136), Face = Vector3.new(0, 0, 1) },
	{ Id = "PaintShop", Name = "Paint", Glyph = "🎨", Spot = Vector3.new(62, 3, 142), Face = Vector3.new(0, 0, 1) },
	{ Id = "TrophyVault", Name = "Vault", Glyph = "🏆", Spot = Vector3.new(0, 3, 138), Face = Vector3.new(0, 0, 1) },
	{ Id = "Lobby", Name = "Deals", Glyph = "🌙", Spot = Vector3.new(0, 3, 24), Face = Vector3.new(0, 0, -1) },
}

Factory.Entrance = {
	Mouth = Vector3.new(0, 9, -6), -- center of the intake tube on the facade
	MouthRadius = 7,
	Trigger = Vector3.new(0, 5, -9),
	Outside = Vector3.new(0, 3, -26), -- where you stand after leaving
	-- Camera ride through the tube into the showroom
	TubePath = {
		Vector3.new(0, 9, -22),
		Vector3.new(0, 9, -4),
		Vector3.new(0, 14, 8),
		Vector3.new(0, 30, 16),
		Vector3.new(0, 34, 30),
		Vector3.new(0, 30, 42),
		Vector3.new(0, 16, 47),
		Vector3.new(0, 7, 50),
	},
	Landing = Vector3.new(0, 3, 52),
	LandingFace = Vector3.new(0, 0, 1),
	TubeRadius = 4,
}

Factory.Showroom = {
	Center = Vector3.new(0, 0, 78),
	PodiumRadius = 20,
	PodiumHeight = 3,
	TurntableRadius = 27,
	CameraInset = 11, -- how far from the podium (towards the center) the camera sits
	CameraHeight = 6.5,
	HoloOffset = 6.5, -- sideways offset of the stat hologram
}

Factory.AssemblyBay = {
	Center = Vector3.new(0, 1.5, 110),
	ArmRadius = 7.5,
	MaxArms = 6,
	Camera = Vector3.new(0, 10, 92),
	CoinSlot = Vector3.new(-13, 5.5, 103),
	ConveyorEnd = Vector3.new(26, 1.5, 110),
	ExitTube = Vector3.new(32, 0, 110),
	ExitStep = Vector3.new(32, 3, 102),
	FinaleCamera = Vector3.new(32, 7, 90),
}

Factory.TestChamber = {
	Lanes = { 52, 72, 92, 112 }, -- Z of each lane
	BeltStartX = -96,
	BeltEndX = -62,
	PadX = -56,
	BeltHeight = 2,
	BeltWidth = 8,
	ScreenX = -99,
	Duration = 20,
	Cooldown = 12,
	DumpTime = 1.5,
	MaxStartDistance = 420, -- studs from the factory origin
	SpawnRateMin = 1.5,
}

Factory.UpgradeLab = {
	Machines = {
		upg_tank = Vector3.new(56, 0, 62),
		upg_nozzle = Vector3.new(86, 0, 62),
		upg_turbine = Vector3.new(56, 0, 104),
		upg_motor = Vector3.new(86, 0, 104),
	},
	Center = Vector3.new(71, 0, 83),
}

Factory.CapsuleHall = {
	MachineXs = { -88, -62, -36 },
	MachineZ = 208,
	Funnel = Vector3.new(-62, 10, 190),
	SharedRun = {
		Vector3.new(-62, 10, 190),
		Vector3.new(-90, 8.5, 182),
		Vector3.new(-34, 7, 174),
		Vector3.new(-90, 5.5, 166),
		Vector3.new(-40, 4, 158),
		Vector3.new(-62, 2.5, 152),
		Vector3.new(-62, 2, 146),
	},
	RevealPad = Vector3.new(-62, 0, 146),
	Camera = Vector3.new(-62, 9, 130),
}

Factory.PaintShop = {
	LineZ = 182,
	LineStartX = 30,
	LineEndX = 94,
	LineHeight = 3,
	BoothX = 62,
	Console = Vector3.new(62, 0, 156),
	Camera = Vector3.new(62, 10, 160),
}

Factory.TrophyVault = {
	DoorCenter = Vector3.new(0, 11, 150),
	DoorRadius = 9.5,
	PromptSpot = Vector3.new(0, 4, 145),
	PedestalXs = { -14, 14 },
	PedestalZs = { 168, 186, 204 },
}

Factory.Lobby = {
	CrateHatch = Vector3.new(-99, 3, 20),
	CratePad = Vector3.new(-48, 2, 20),
	CrateScreen = Vector3.new(-72, 14, 14),
	NightStand = Vector3.new(62, 0, 22),
	InfoBoard = Vector3.new(0, 0, 32),
}

Factory.Roof = {
	VacuumBase = Vector3.new(0, 40, 22),
	Nozzle = Vector3.new(0, 60, 6),
	Vents = {
		Vector3.new(-70, 40, 64),
		Vector3.new(70, 40, 64),
		Vector3.new(-44, 40, 186),
		Vector3.new(44, 40, 186),
	},
}

Factory.Workers = {
	Count = 8,
	LowGraphicsCount = 4,
	Speed = 6,
	CheerRadius = 90,
	Paths = {
		{ Vector3.new(-30, 0, 10), Vector3.new(30, 0, 10), Vector3.new(30, 0, 33), Vector3.new(-30, 0, 33) },
		{ Vector3.new(-33, 0, 78), Vector3.new(-23, 0, 99), Vector3.new(0, 0, 103), Vector3.new(23, 0, 99), Vector3.new(33, 0, 78), Vector3.new(23, 0, 57), Vector3.new(0, 0, 48), Vector3.new(-23, 0, 57) },
		{ Vector3.new(71, 0, 46), Vector3.new(71, 0, 120) },
		{ Vector3.new(-47, 0, 46), Vector3.new(-47, 0, 120) },
		{ Vector3.new(-92, 0, 134), Vector3.new(-30, 0, 134) },
		{ Vector3.new(30, 0, 140), Vector3.new(94, 0, 140), Vector3.new(94, 0, 206), Vector3.new(30, 0, 206) },
	},
}

-- Day/night. When DriveClock is true the server advances Lighting.ClockTime;
-- set it to false if your game already has its own day cycle.
Factory.DayNight = {
	DriveClock = true,
	CycleMinutes = 16,
	StartClock = 14,
	NightStart = 18,
	NightEnd = 6,
}

-- Where factories live in Workspace.
Factory.FolderName = "Factories"

return Factory
