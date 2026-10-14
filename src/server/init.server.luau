-- Server bootstrap: create remotes, then Init every service (wiring, no
-- yielding) and Start them (connections, loops).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
Net.Setup()

local Services = script:WaitForChild("Services")

local order = {
	"DataService",
	"FactoryService",
	"ShopService",
	"UpgradeService",
	"MonetizationService",
	"TestChamberService",
	"AdminService",
}

local services = {}
for _, name in order do
	services[name] = require(Services:WaitForChild(name))
end

for _, name in order do
	local service = services[name]
	if service.Init then
		service:Init(services)
	end
end

for _, name in order do
	local service = services[name]
	if service.Start then
		task.spawn(service.Start, service)
	end
end
