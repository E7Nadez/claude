--!strict
-- Central list of every remote the shop uses. The server creates them once,
-- clients wait for them. Payload shapes are documented next to each name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.FolderName = "ShopRemotes"

Net.Functions = {
	-- (itemId: string, options: { Quantity: number? }?) -> Result
	"PurchaseItem",
	-- (upgradeId: string) -> Result
	"PurchaseUpgrade",
	-- (vacuumId: string) -> Result
	"EquipVacuum",
	-- (slot: "Skin" | "Trail", cosmeticId: string?) -> Result
	"EquipCosmetic",
	-- (vacuumId: string) -> Result { Lane, EndsAt, Duration }
	"StartTestChamber",
	-- () -> Result { Comparison }
	"StopTestChamber",
	-- (key: string, value: any) -> Result
	"SetSetting",
	-- () -> snapshot (used once on join if the first push was missed)
	"RequestSync",
}

Net.Events = {
	-- server -> owner: full data snapshot
	"DataSync",
	-- server -> all: { UserId, DisplayName, ItemId, ItemName, Rarity, Kind, World, Position }
	"ShopBroadcast",
	-- server -> owner: { Text, Kind = "Info" | "Success" | "Error" }
	"Notify",
	-- server -> owner: { Reason, Comparison }
	"TestChamberEnded",
}

export type Result = {
	Ok: boolean,
	Code: string?,
	Error: string?,
	[string]: any,
}

local folder: Folder? = nil

local function getFolder(): Folder
	local cached = folder
	if cached then
		return cached
	end
	local result: Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(Net.FolderName)
		if existing and existing:IsA("Folder") then
			result = existing
		else
			result = Instance.new("Folder")
			result.Name = Net.FolderName
			result.Parent = ReplicatedStorage
		end
	else
		result = ReplicatedStorage:WaitForChild(Net.FolderName) :: Folder
	end
	folder = result
	return result
end

-- Server only: create every remote up front so clients never wait forever.
function Net.Setup()
	assert(RunService:IsServer(), "Net.Setup is server only")
	local root = getFolder()
	for _, name in Net.Functions do
		if not root:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = root
		end
	end
	for _, name in Net.Events do
		if not root:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = root
		end
	end
end

function Net.Function(name: string): RemoteFunction
	assert(table.find(Net.Functions, name), "Unknown remote function " .. name)
	return getFolder():WaitForChild(name) :: RemoteFunction
end

function Net.Event(name: string): RemoteEvent
	assert(table.find(Net.Events, name), "Unknown remote event " .. name)
	return getFolder():WaitForChild(name) :: RemoteEvent
end

-- Client helper: never throws, always returns a Result table.
function Net.Invoke(name: string, ...: any): Result
	local remote = Net.Function(name)
	local ok, result = pcall(remote.InvokeServer, remote, ...)
	if not ok then
		return { Ok = false, Code = "NETWORK", Error = "Connection problem. Please try again." }
	end
	if type(result) ~= "table" then
		return { Ok = false, Code = "NETWORK", Error = "Unexpected server response." }
	end
	return result
end

return Net
