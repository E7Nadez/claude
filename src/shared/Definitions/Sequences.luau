--!strict
-- Data-driven show profiles. Rarity -> how long and how loud a purchase,
-- capsule reveal or crate opening is. Client sequences read only this table.
--
--   Duration     seconds of the assembly / reveal phase (before the finale)
--   ArmCount     robot arms in the assembly bay
--   SparkBurst   particles per weld (scaled down in Low Graphics)
--   LightShow    sweeping colored spotlights
--   LightCount   number of spotlights in the light show
--   Shake        camera shake amplitude (studs)
--   Quake        factory rumble: dust from the ceiling, flickering lamps
--   SkyTint      Color3 the sky/color-correction tints to (nil = none)
--   Confetti     confetti pieces in the finale
--   NpcCheer     worker robots stop and cheer
--   Broadcast    "None" | "Factory" (players in that factory) | "Server" (everyone)
--   FovPunch     extra field-of-view kick on the reveal
--   Orbit        camera orbits the bay during assembly
--   Banner       "Small" | "Big" | "Epic"
--   CapsuleWobble   capsule shakes before it opens (reveal sequence)

export type Profile = {
	Duration: number,
	ArmCount: number,
	SparkBurst: number,
	LightShow: boolean,
	LightCount: number,
	Shake: number,
	Quake: boolean,
	SkyTint: Color3?,
	Confetti: number,
	NpcCheer: boolean,
	Broadcast: "None" | "Factory" | "Server",
	FovPunch: number,
	Orbit: boolean,
	Banner: "Small" | "Big" | "Epic",
	CapsuleWobble: number,
}

local Sequences = {}

Sequences.ByRarity = {
	Common = { Duration = 2.2, ArmCount = 2, SparkBurst = 8, LightShow = false, LightCount = 0, Shake = 0, Quake = false, SkyTint = nil, Confetti = 30, NpcCheer = false, Broadcast = "Factory", FovPunch = 0, Orbit = false, Banner = "Small", CapsuleWobble = 1 },
	Uncommon = { Duration = 2.8, ArmCount = 2, SparkBurst = 12, LightShow = false, LightCount = 0, Shake = 0, Quake = false, SkyTint = nil, Confetti = 45, NpcCheer = false, Broadcast = "Factory", FovPunch = 2, Orbit = false, Banner = "Small", CapsuleWobble = 2 },
	Rare = { Duration = 3.6, ArmCount = 3, SparkBurst = 18, LightShow = false, LightCount = 0, Shake = 0.05, Quake = false, SkyTint = nil, Confetti = 70, NpcCheer = true, Broadcast = "Factory", FovPunch = 4, Orbit = false, Banner = "Big", CapsuleWobble = 2 },
	Epic = { Duration = 4.6, ArmCount = 4, SparkBurst = 26, LightShow = false, LightCount = 0, Shake = 0.12, Quake = false, SkyTint = nil, Confetti = 110, NpcCheer = true, Broadcast = "Factory", FovPunch = 6, Orbit = true, Banner = "Big", CapsuleWobble = 3 },
	Legendary = { Duration = 6.2, ArmCount = 4, SparkBurst = 36, LightShow = true, LightCount = 6, Shake = 0.2, Quake = false, SkyTint = nil, Confetti = 170, NpcCheer = true, Broadcast = "Server", FovPunch = 8, Orbit = true, Banner = "Epic", CapsuleWobble = 4 },
	Mythic = { Duration = 8, ArmCount = 6, SparkBurst = 48, LightShow = true, LightCount = 10, Shake = 0.6, Quake = true, SkyTint = Color3.fromRGB(255, 70, 150), Confetti = 260, NpcCheer = true, Broadcast = "Server", FovPunch = 12, Orbit = true, Banner = "Epic", CapsuleWobble = 5 },
} :: { [string]: Profile }

-- Multipliers applied when the player enabled Low Graphics.
Sequences.LowGraphics = {
	Particles = 0.35,
	Confetti = 0.4,
	LightCount = 0.5,
	Shake = 0.5,
}

-- Fixed timings that do not depend on rarity.
Sequences.Timings = {
	CoinFlight = 0.7,
	CameraGlide = 0.6,
	Conveyor = 1.4,
	TubeExit = 1.2,
	Banner = 2.4,
	EntryRide = 3.4,
	ExitRide = 1.4,
	ClawDrop = 1.2,
	MarbleRunSpeed = 26, -- studs per second
}

function Sequences.Get(rarity: string?): Profile
	return Sequences.ByRarity[rarity or "Common"] or Sequences.ByRarity.Common
end

return Sequences
