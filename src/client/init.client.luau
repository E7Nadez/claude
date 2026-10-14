-- Client bootstrap: Init every controller (wiring), then Start them.

local Controllers = script:WaitForChild("Controllers")
script:WaitForChild("Shop")

local order = {
	"ClientData",
	"HudController",
	"ShopController",
}

local controllers = {}
for _, name in order do
	controllers[name] = require(Controllers:WaitForChild(name))
end

for _, name in order do
	local controller = controllers[name]
	if controller.Init then
		controller:Init(controllers)
	end
end

for _, name in order do
	local controller = controllers[name]
	if controller.Start then
		local ok, err = pcall(controller.Start, controller)
		if not ok then
			warn("[Client] " .. name .. " failed to start:", err)
		end
	end
end
