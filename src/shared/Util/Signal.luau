--!strict
-- Minimal script signal. Handlers run in their own thread so a yielding
-- listener never blocks the caller.

local Signal = {}
Signal.__index = Signal

type Handler = { Fn: (...any) -> (), Connected: boolean }

export type Connection = { Connected: boolean, Disconnect: (any) -> () }
export type Signal = typeof(setmetatable({} :: { _handlers: { Handler } }, Signal))

function Signal.new(): Signal
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal.Connect(self: Signal, fn: (...any) -> ()): Connection
	local handler: Handler = { Fn = fn, Connected = true }
	table.insert(self._handlers, handler)

	local connection = { Connected = true }
	function connection.Disconnect(_: any)
		if not handler.Connected then
			return
		end
		handler.Connected = false
		connection.Connected = false
		local index = table.find(self._handlers, handler)
		if index then
			table.remove(self._handlers, index)
		end
	end
	return connection :: any
end

function Signal.Once(self: Signal, fn: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal.Fire(self: Signal, ...: any)
	for _, handler in table.clone(self._handlers) do
		if handler.Connected then
			task.spawn(handler.Fn, ...)
		end
	end
end

function Signal.Wait(self: Signal): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.Destroy(self: Signal)
	for _, handler in self._handlers do
		handler.Connected = false
	end
	table.clear(self._handlers)
end

return Signal
