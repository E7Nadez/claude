--!strict
-- Trove: collects connections, instances, tweens, threads and callbacks so a
-- feature can be torn down in one call (skip, death, leaving the factory ...).

local Trove = {}
Trove.__index = Trove

export type Trove = typeof(setmetatable({} :: { _items: { { any } }, _cleaning: boolean }, Trove))

function Trove.new(): Trove
	return setmetatable({ _items = {}, _cleaning = false }, Trove)
end

function Trove.Add(self: Trove, item: any, method: any?): any
	table.insert(self._items, { item, method })
	return item
end

function Trove.Connect(self: Trove, signal: any, fn: (...any) -> ()): any
	return self:Add(signal:Connect(fn))
end

function Trove.Extend(self: Trove): Trove
	local child = Trove.new()
	self:Add(child, "Clean")
	return child
end

function Trove.Remove(self: Trove, item: any)
	for i, entry in self._items do
		if entry[1] == item then
			table.remove(self._items, i)
			return
		end
	end
end

local function cleanItem(item: any, method: any)
	if method ~= nil then
		if type(method) == "function" then
			method(item)
		else
			item[method](item)
		end
		return
	end

	local kind = typeof(item)
	if kind == "Instance" then
		if item:IsA("Tween") then
			item:Cancel()
		end
		item:Destroy()
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		if coroutine.status(item) ~= "dead" and item ~= coroutine.running() then
			pcall(task.cancel, item)
		end
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.Clean) == "function" then
			item:Clean()
		end
	end
end

function Trove.Clean(self: Trove)
	if self._cleaning then
		return
	end
	self._cleaning = true
	-- Items added while cleaning are cleaned in the same pass.
	while #self._items > 0 do
		local items = self._items
		self._items = {}
		for i = #items, 1, -1 do
			local entry = items[i]
			xpcall(cleanItem, function(err)
				warn("[Trove] cleanup error:", err, debug.traceback())
			end, entry[1], entry[2])
		end
	end
	self._cleaning = false
end

Trove.Destroy = Trove.Clean

return Trove
