--!strict
-- Error codes returned by every shop remote, with player-facing messages.

local Errors = {}

Errors.Messages = {
	INVALID = "Invalid request.",
	INVALID_ITEM = "That item doesn't exist.",
	RATE_LIMITED = "Slow down a little!",
	BUSY = "Still processing your last purchase...",
	NOT_LOADED = "Your data is still loading.",
	NOT_ENOUGH = "Not enough %s.",
	ALREADY_OWNED = "You already own this.",
	LOCKED = "Locked: %s",
	MAX_LEVEL = "Already at max level.",
	NIGHT_ONLY = "This deal is only available at night.",
	DAILY_LIMIT = "Come back tomorrow for a new crate.",
	INVENTORY_FULL = "Your pet inventory is full.",
	UNAVAILABLE = "Not available yet.",
	USE_ROBUX = "This item is bought with Robux.",
	NOT_OWNED = "You don't own that.",
	COOLDOWN = "Test Chamber is cooling down (%s).",
	LANES_BUSY = "All test lanes are busy. Try again in a few seconds.",
	TOO_FAR = "Head into the Mega-Factory to use the Test Chamber.",
	ALREADY_TESTING = "You're already testing a vacuum.",
	NOT_TESTING = "You're not in the Test Chamber.",
	NO_CHARACTER = "Respawn first.",
	NETWORK = "Connection problem. Please try again.",
} :: { [string]: string }

function Errors.Result(code: string, ...: any): { [string]: any }
	local template = Errors.Messages[code] or code
	local ok, message = pcall(string.format, template, ...)
	return { Ok = false, Code = code, Error = if ok then message else template }
end

return Errors
