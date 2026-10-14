--!strict
-- Token bucket per player. Used on every remote to stop spam / exploit loops.

local Players = game:GetService("Players")

local RateLimiter = {}
RateLimiter.__index = RateLimiter

type Bucket = { Tokens: number, Updated: number }

export type RateLimiter = typeof(setmetatable({} :: {
	_capacity: number,
	_refill: number,
	_buckets: { [Player]: Bucket },
}, RateLimiter))

-- capacity: burst size, refillPerSecond: sustained rate
function RateLimiter.new(capacity: number, refillPerSecond: number): RateLimiter
	local self = setmetatable({
		_capacity = capacity,
		_refill = refillPerSecond,
		_buckets = {},
	}, RateLimiter)
	Players.PlayerRemoving:Connect(function(player)
		self._buckets[player] = nil
	end)
	return self
end

function RateLimiter.Check(self: RateLimiter, player: Player): boolean
	local now = os.clock()
	local bucket = self._buckets[player]
	if not bucket then
		bucket = { Tokens = self._capacity, Updated = now }
		self._buckets[player] = bucket
	end
	bucket.Tokens = math.min(self._capacity, bucket.Tokens + (now - bucket.Updated) * self._refill)
	bucket.Updated = now
	if bucket.Tokens < 1 then
		return false
	end
	bucket.Tokens -= 1
	return true
end

return RateLimiter
