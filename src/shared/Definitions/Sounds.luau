--!strict
-- Every sound the shop plays. The rbxasset:// files ship with the Roblox
-- client and always load. Replace them with your own uploaded audio ids
-- ("rbxassetid://123") for a more polished mix.

export type SoundDef = {
	Id: string,
	Volume: number,
	Speed: number?,
	Looped: boolean?,
}

local Sounds = {
	Hover = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.12, Speed = 1.8 },
	Click = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.45, Speed = 1.1 },
	Tab = { Id = "rbxasset://sounds/button.wav", Volume = 0.35, Speed = 1.2 },
	Open = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.4, Speed = 1.15 },
	Close = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.3, Speed = 0.85 },
	Success = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Speed = 1 },
	Error = { Id = "rbxasset://sounds/button.wav", Volume = 0.5, Speed = 0.55 },
	Coin = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.22, Speed = 1.9 },
	Tick = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.15, Speed = 2.4 },
	Weld = { Id = "rbxasset://sounds/snap.wav", Volume = 0.35, Speed = 1.3 },
	Servo = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.18, Speed = 1.8 },
	Boom = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.5, Speed = 1 },
	Rumble = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.6, Speed = 0.35 },
	Tube = { Id = "rbxasset://sounds/Rocket whoosh 01.wav", Volume = 0.55, Speed = 1 },
	Suction = { Id = "rbxasset://sounds/Rocket whoosh 01.wav", Volume = 0.35, Speed = 0.6, Looped = true },
	Pop = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 0.5, Speed = 1.2 },
	Glass = { Id = "rbxasset://sounds/glassbreak.wav", Volume = 0.35, Speed = 1.2 },
	Clank = { Id = "rbxasset://sounds/collide.wav", Volume = 0.6, Speed = 0.6 },
	Fanfare = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7, Speed = 0.75 },
	Denied = { Id = "rbxasset://sounds/button.wav", Volume = 0.6, Speed = 0.4 },
	Spray = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.25, Speed = 0.5, Looped = true },
} :: { [string]: SoundDef }

return Sounds
