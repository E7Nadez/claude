-- Interruptible, skippable sequence runner. Every show (tube ride, assembly,
-- capsule reveal ...) runs its body through one of these:
--   seq:Wait(t)         yields; returns false once skipped/cancelled
--   seq:Tween(...)      tracked tween; snaps to its goal when skipped
--   seq.Trove           everything created during the show
--   seq:Skip()          stops the body, then the finale runs
--   seq:Cancel()        stops the body, finale runs with cancelled = true
-- The finale always runs exactly once, so state is restored no matter how the
-- sequence ends (finished, skipped, died, left the factory).

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Trove = require(Shared.Util.Trove)

local Sequence = {}
Sequence.__index = Sequence

export type Sequence = typeof(setmetatable({} :: {
	Name: string,
	Trove: any,
	Stopped: boolean,
	Skipped: boolean,
	Cancelled: boolean,
	Finished: boolean,
	_tweens: { { Tween: Tween, Instance: Instance, Goal: { [string]: any } } },
	_done: BindableEvent,
}, Sequence))

function Sequence.new(name: string): Sequence
	local self = setmetatable({
		Name = name,
		Trove = Trove.new(),
		Stopped = false,
		Skipped = false,
		Cancelled = false,
		Finished = false,
		_tweens = {},
		_done = Instance.new("BindableEvent"),
	}, Sequence)
	return self
end

function Sequence.Wait(self: Sequence, seconds: number): boolean
	local start = os.clock()
	while os.clock() - start < seconds do
		if self.Stopped then
			return false
		end
		task.wait()
	end
	return not self.Stopped
end

-- Waits until fn() is true (or stopped). Returns false if stopped.
function Sequence.WaitUntil(self: Sequence, fn: () -> boolean, timeout: number?): boolean
	local start = os.clock()
	while not fn() do
		if self.Stopped then
			return false
		end
		if timeout and os.clock() - start > timeout then
			return true
		end
		task.wait()
	end
	return not self.Stopped
end

function Sequence.Tween(self: Sequence, instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, goal)
	table.insert(self._tweens, { Tween = tween, Instance = instance, Goal = goal })
	if self.Stopped then
		for key, value in goal do
			(instance :: any)[key] = value
		end
	else
		tween:Play()
	end
	return tween
end

-- Spawns a parallel branch that stops with the sequence.
function Sequence.Spawn(self: Sequence, fn: (...any) -> (), ...: any)
	local thread = task.spawn(fn, ...)
	self.Trove:Add(thread)
	return thread
end

function Sequence.Every(self: Sequence, interval: number, fn: () -> ()): thread
	return self:Spawn(function()
		while not self.Stopped do
			fn()
			task.wait(interval)
		end
	end)
end

local function stopTweens(self: Sequence)
	for _, entry in self._tweens do
		if entry.Tween.PlaybackState == Enum.PlaybackState.Playing then
			entry.Tween:Cancel()
			if entry.Instance.Parent then
				for key, value in entry.Goal do
					pcall(function()
						(entry.Instance :: any)[key] = value
					end)
				end
			end
		end
	end
	table.clear(self._tweens)
end

function Sequence.Skip(self: Sequence)
	if self.Stopped then
		return
	end
	self.Skipped = true
	self.Stopped = true
	stopTweens(self)
end

function Sequence.Cancel(self: Sequence)
	if self.Stopped then
		return
	end
	self.Cancelled = true
	self.Stopped = true
	stopTweens(self)
end

-- Runs body(seq) then finale(seq). Returns immediately; use :Await().
function Sequence.Run(self: Sequence, body: (Sequence) -> (), finale: ((Sequence) -> ())?)
	task.spawn(function()
		local ok, err = pcall(body, self)
		if not ok then
			warn("[Sequence:" .. self.Name .. "]", err)
		end
		self.Stopped = true
		if finale then
			local okF, errF = pcall(finale, self)
			if not okF then
				warn("[Sequence:" .. self.Name .. "] finale:", errF)
			end
		end
		self.Trove:Clean()
		self.Finished = true
		self._done:Fire()
	end)
end

function Sequence.Await(self: Sequence)
	if not self.Finished then
		self._done.Event:Wait()
	end
end

function Sequence.Destroy(self: Sequence)
	self:Cancel()
end

return Sequence
