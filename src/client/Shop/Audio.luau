-- Local sound playback for the shop (2D UI sounds and 3D world sounds).
-- Sounds are created on the client, so only this player hears them.

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Sounds = require(Shared.Definitions.Sounds)

local Audio = {}

local group = Instance.new("SoundGroup")
group.Name = "ShopSounds"
group.Volume = 1
group.Parent = SoundService

local lastPlayed: { [string]: number } = {}

local function make(name: string, opts: { [string]: any }?): Sound?
	local def = Sounds[name]
	if not def then
		return nil
	end
	local o = opts or {}
	local sound = Instance.new("Sound")
	sound.Name = "Shop_" .. name
	sound.SoundId = def.Id
	sound.Volume = def.Volume * (o.Volume or 1)
	sound.PlaybackSpeed = (def.Speed or 1) * (o.Speed or 1)
	sound.Looped = o.Looped or def.Looped or false
	sound.SoundGroup = group
	return sound
end

-- Plays a 2D sound. Rapid repeats of the same sound are throttled.
function Audio.Play(name: string, opts: { [string]: any }?): Sound?
	local now = os.clock()
	if lastPlayed[name] and now - lastPlayed[name] < 0.03 then
		return nil
	end
	lastPlayed[name] = now
	local sound = make(name, opts)
	if not sound then
		return nil
	end
	sound.Parent = SoundService
	sound:Play()
	if not sound.Looped then
		Debris:AddItem(sound, 6)
	end
	return sound
end

-- Plays a positional sound at a world position.
function Audio.PlayAt(name: string, position: Vector3, opts: { [string]: any }?): Sound?
	local sound = make(name, opts)
	if not sound then
		return nil
	end
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = 140
	sound.Parent = attachment
	sound:Play()
	Debris:AddItem(attachment, 6)
	return sound
end

-- Looping sound the caller must Destroy (optionally positional via parent).
function Audio.Loop(name: string, parent: Instance?, opts: { [string]: any }?): Sound?
	local o = table.clone(opts or {})
	o.Looped = true
	local sound = make(name, o)
	if not sound then
		return nil
	end
	sound.Parent = parent or SoundService
	sound:Play()
	return sound
end

function Audio.SetVolume(volume: number)
	group.Volume = volume
end

return Audio
