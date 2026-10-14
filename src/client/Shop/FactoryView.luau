-- Client-side view of one Mega-Factory model: owns every zone controller of
-- that building and the local-only parts they create.

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Worlds = require(Shared.Definitions.Worlds)
local Factory = require(Shared.Definitions.Factory)
local Trove = require(Shared.Util.Trove)

local Zones = script.Parent:WaitForChild("Zones")

local FactoryView = {}
FactoryView.__index = FactoryView

local ZONE_ORDER = {
	"Ambience",
	"Spectacle",
	"Workers",
	"Showroom",
	"TestChamber",
	"UpgradeLab",
	"CapsuleHall",
	"PaintShop",
	"TrophyVault",
	"Lobby",
}

function FactoryView.new(model: Model, controller)
	local self = setmetatable({}, FactoryView)
	self.Model = model
	self.World = model:GetAttribute("World") :: string
	self.Theme = Worlds.Theme(self.World)
	local origin = model:WaitForChild("Origin") :: BasePart
	self.Origin = origin.CFrame
	self.Controller = controller
	self.Trove = Trove.new()
	self.Near = false
	self.Inside = false

	local localRoot = workspace:FindFirstChild("ShopLocal")
	if not localRoot then
		localRoot = Instance.new("Folder")
		localRoot.Name = "ShopLocal"
		localRoot.Parent = workspace
	end
	local folder = Instance.new("Folder")
	folder.Name = self.World
	folder.Parent = localRoot
	self.LocalFolder = folder
	self.Trove:Add(folder)

	self.Zones = {}
	for _, name in ZONE_ORDER do
		local module = Zones:FindFirstChild(name)
		if module then
			local ok, zone = pcall(function()
				return require(module).new(self)
			end)
			if ok then
				self.Zones[name] = zone
				self.Trove:Add(zone)
			else
				warn("[FactoryView] zone", name, "failed:", zone)
			end
		end
	end
	return self
end

function FactoryView:ToWorld(localPosition: Vector3): Vector3
	return self.Origin:PointToWorldSpace(localPosition)
end

function FactoryView:ToLocal(worldPosition: Vector3): Vector3
	return self.Origin:PointToObjectSpace(worldPosition)
end

function FactoryView:WorldCFrame(localCf: CFrame): CFrame
	return self.Origin * localCf
end

-- Inside the building walls (or the entrance plaza).
function FactoryView:Contains(worldPosition: Vector3): boolean
	local p = self:ToLocal(worldPosition)
	local size = Factory.Size
	return math.abs(p.X) <= size.X / 2 and p.Z >= 0 and p.Z <= size.Z and p.Y > -8 and p.Y < size.Y + 4
end

function FactoryView:DistanceTo(worldPosition: Vector3): number
	local p = self:ToLocal(worldPosition)
	local size = Factory.Size
	local dx = math.max(math.abs(p.X) - size.X / 2, 0)
	local dz = math.max(-p.Z, p.Z - size.Z, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- Room id (key of Factory.Rooms) at a world position.
function FactoryView:RoomAt(worldPosition: Vector3): string?
	local p = self:ToLocal(worldPosition)
	for name, rect in Factory.Rooms do
		if p.X >= rect.Min.X and p.X <= rect.Max.X and p.Z >= rect.Min.Y and p.Z <= rect.Max.Y then
			return name
		end
	end
	return nil
end

function FactoryView:Find(path: string): Instance?
	local current: Instance? = self.Model
	for _, name in string.split(path, "/") do
		if not current then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

function FactoryView:Tagged(tag: string): { Instance }
	local list = {}
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsDescendantOf(self.Model) then
			table.insert(list, instance)
		end
	end
	return list
end

function FactoryView:SetActive(near: boolean, inside: boolean)
	local changed = near ~= self.Near
	self.Near = near
	self.Inside = inside
	if changed then
		for _, zone in self.Zones do
			if zone.SetActive then
				zone:SetActive(near)
			end
		end
	end
end

function FactoryView:Zone(name: string): any
	return self.Zones[name]
end

-- Called by the controller after quality settings changed.
function FactoryView:QualityChanged()
	for _, zone in self.Zones do
		if zone.QualityChanged then
			zone:QualityChanged()
		end
	end
end

function FactoryView:Destroy()
	self.Trove:Clean()
end

return FactoryView
