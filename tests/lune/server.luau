-- Usage: rojo build default.project.json -o build.rbxlx && lune run tests/lune/server.luau build.rbxlx
-- Lune harness: loads the Rojo build, emulates `require` for ModuleScripts and
-- runs the server-side factory builder + shop validation against real
-- Roblox instance/property semantics (rbx_dom based).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local task = require("@lune/task")
local process = require("@lune/process")

local placePath = process.args[1]
local game = roblox.deserializePlace(fs.readFile(placePath))
local Instance = roblox.Instance

-- simple signal mock
local function signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		table.insert(self.handlers, fn)
		return { Disconnect = function() end, Connected = true }
	end
	function s:Fire(...)
		for _, h in self.handlers do
			h(...)
		end
	end
	function s:Wait() end
	return s
end

local tagged = {}
local mocks = {
	CollectionService = {
		AddTag = function(_, inst, tag)
			inst:AddTag(tag)
			tagged[tag] = tagged[tag] or {}
			table.insert(tagged[tag], inst)
		end,
		GetTagged = function(_, tag)
			return tagged[tag] or {}
		end,
	},
	RunService = {
		IsServer = function()
			return true
		end,
		IsClient = function()
			return false
		end,
		IsStudio = function()
			return true
		end,
		Heartbeat = signal(),
	},
	HttpService = {
		GenerateGUID = function()
			return tostring(math.random(1, 1e9))
		end,
	},
	Players = {
		PlayerRemoving = signal(),
		PlayerAdded = signal(),
		GetPlayers = function()
			return {}
		end,
	},
}

local gameProxy = setmetatable({
	GetService = function(_, name)
		if mocks[name] then
			return mocks[name]
		end
		return game:GetService(name)
	end,
	JobId = "harness",
}, {
	__index = function(_, key)
		return game[key]
	end,
})

local RandomPolyfill = {}
function RandomPolyfill.new(seed)
	local r = {}
	function r:NextNumber(a, b)
		a = a or 0
		b = b or 1
		return a + math.random() * (b - a)
	end
	function r:NextInteger(a, b)
		return math.random(a, b)
	end
	return r
end

local TweenInfoPolyfill = {
	new = function(...)
		return { ... }
	end,
}

local cache = {}
local customRequire

local function transform(source: string): string
	source = source:gsub(":WaitForChild%(", ":FindFirstChild(")
	return source
end

local function makeEnv(scriptInstance)
	local env = {
		script = scriptInstance,
		game = gameProxy,
		workspace = game:GetService("Workspace"),
		require = function(m)
			return customRequire(m)
		end,
		Instance = Instance,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		Font = roblox.Font,
		Random = RandomPolyfill,
		TweenInfo = TweenInfoPolyfill,
		task = task,
		math = math,
		string = string,
		table = table,
		os = os,
		coroutine = coroutine,
		utf8 = utf8,
		bit32 = bit32,
		buffer = buffer,
		debug = debug,
		print = print,
		warn = function(...)
			print("[warn]", ...)
		end,
		error = error,
		assert = assert,
		pcall = pcall,
		xpcall = xpcall,
		select = select,
		type = type,
		typeof = typeof,
		tostring = tostring,
		tonumber = tonumber,
		ipairs = ipairs,
		pairs = pairs,
		next = next,
		rawget = rawget,
		rawset = rawset,
		rawequal = rawequal,
		rawlen = rawlen,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		unpack = table.unpack,
	}
	return env
end

customRequire = function(module)
	assert(typeof(module) == "Instance", "require expects an Instance, got " .. typeof(module))
	local key = module:GetFullName()
	if cache[key] ~= nil then
		return cache[key]
	end
	local source = transform(module.Source)
	local fn = luau.load(source, { debugName = key, environment = makeEnv(module) })
	local result = fn()
	cache[key] = result
	return result
end

local failures = 0
local function check(cond, message)
	if cond then
		print("  ok   " .. message)
	else
		failures += 1
		print("  FAIL " .. message)
	end
end

local Server = game:GetService("ServerScriptService"):FindFirstChild("Server")
local Shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")

------------------------------------------------------------------------------------
print("== Factory builder")
local Worlds = customRequire(Shared.Definitions.Worlds)
local Vacuums = customRequire(Shared.Definitions.Vacuums)
local Capsules = customRequire(Shared.Definitions.Capsules)
local Upgrades = customRequire(Shared.Definitions.Upgrades)
local Trophies = customRequire(Shared.Definitions.Trophies)
local FactoryBuilder = customRequire(Server.Factory.FactoryBuilder)
local folder = Instance.new("Folder")
folder.Name = "Factories"
folder.Parent = game:GetService("Workspace")

local function find(root, path)
	local current = root
	for _, name in string.split(path, "/") do
		if not current then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

for _, world in Worlds.Released() do
	local ok, model = pcall(FactoryBuilder.Build, world.Id, world.FactoryOrigin, folder)
	check(ok, "build " .. world.Id .. (if ok then "" else ": " .. tostring(model)))
	if ok then
		local parts, prompts, guis = 0, 0, 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			elseif d:IsA("ProximityPrompt") then
				prompts += 1
			elseif d:IsA("SurfaceGui") then
				guis += 1
			end
		end
		print(string.format("  %s: %d parts, %d prompts, %d surface guis", world.Id, parts, prompts, guis))
		check(parts < 2500, "part budget under 2500")
		local required = {
			"Origin",
			"Entrance/EntryTrigger",
			"Roof/RoofVacuum/Nozzle",
			"Showroom/AssemblyBay/Mounts/Mount_6",
			"Showroom/AssemblyBay/CoinSlot",
			"Showroom/AssemblyBay/Conveyor/Slats",
			"Showroom/AssemblyBay/ExitStep",
			"TestChamber/Lanes/Lane_1/Belt",
			"TestChamber/Lanes/Lane_4/Pad",
			"TestChamber/Lanes/Lane_2/Screen/Status/Text",
			"PaintShop/Line/Slats",
			"PaintShop/Console/ShopPrompt",
			"TrophyVault/DoorAnchor",
			"TrophyVault/Console/ShopPrompt",
			"Lobby/CrateBelt",
			"Lobby/CrateHatch",
			"Lobby/CratePad",
			"Lobby/CrateScreen",
			"Lobby/NightStand/NightSign/Sign/Text",
			"Lobby/NightStand/Counter/ShopPrompt",
			"Lobby/CrateConsole/ShopPrompt",
			"Showroom/Console/ShopPrompt",
		}
		for _, path in required do
			check(find(model, path) ~= nil, world.Id .. " has " .. path)
		end
		for i, vacuum in Vacuums.ForWorld(world.Id) do
			local podium = find(model, "Showroom/Podiums/Podium_" .. i)
			check(podium ~= nil and podium:GetAttribute("VacuumId") == vacuum.Id and find(podium, "Display") and find(podium, "Holo") and find(podium, "Ring"), world.Id .. " podium " .. i .. " = " .. vacuum.Id)
		end
		for _, upgrade in Upgrades.List do
			local machine = find(model, "UpgradeLab/Machine_" .. upgrade.Id)
			check(machine and find(machine, "Mount") and find(machine, "Sign") and find(machine, "Console/ShopPrompt"), world.Id .. " lab machine " .. upgrade.Id)
		end
		for _, capsule in Capsules.ForWorld(world.Id) do
			local machine = find(model, "CapsuleHall/Machine_" .. capsule.Id)
			local run = find(model, "CapsuleHall/Runs/Run_" .. capsule.Id)
			local wps = 0
			if run then
				for _, c in run:GetChildren() do
					if c.Name:sub(1, 3) == "WP_" then
						wps += 1
					end
				end
			end
			check(machine and find(machine, "DomeCenter") and find(machine, "Chute") and find(machine, "Panel") and wps >= 5, world.Id .. " capsule machine " .. capsule.Id .. " (" .. wps .. " waypoints)")
		end
		for _, trophy in Trophies.List do
			local pedestal = find(model, "TrophyVault/Pedestals/Pedestal_" .. trophy.Id)
			check(pedestal and find(pedestal, "Top") and find(pedestal, "Plate") and find(pedestal, "Base/ShopPrompt"), world.Id .. " pedestal " .. trophy.Id)
		end
		local belt = find(model, "TestChamber/Lanes/Lane_1/Belt")
		check(belt and typeof(belt:GetAttribute("BeltStart")) == "Vector3" and typeof(belt:GetAttribute("BeltDirection")) == "Vector3", "belt attributes")
		local gear = find(model, "Facade/Gears/Gear_1")
		check(gear and typeof(gear:GetAttribute("Center")) == "CFrame", "gear center attribute")
		-- prompts all carry an action
		local badPrompt = false
		for _, d in model:GetDescendants() do
			if d:IsA("ProximityPrompt") and type(d:GetAttribute("ShopAction")) ~= "string" then
				badPrompt = true
			end
		end
		check(not badPrompt, "every prompt has ShopAction")
	end
end

------------------------------------------------------------------------------------
print("== Shared logic")
local Shop = customRequire(Shared.Definitions.Shop)
local Stats = customRequire(Shared.Util.Stats)
local Format = customRequire(Shared.Util.Format)
local DataTemplate = customRequire(Shared.DataTemplate)
local Progress = customRequire(Shared.Util.Progress)

check(#Shop.Items > 50, "shop has " .. #Shop.Items .. " items")
for _, category in Shop.Categories do
	check(#Shop.ItemsInCategory(category.Id) > 0, "category " .. category.Id .. " not empty (" .. #Shop.ItemsInCategory(category.Id) .. ")")
end
for _, item in Shop.Items do
	assert(item.Id and item.Name and item.Price and item.Currency and item.Rarity and item.Category and item.IconAssetId ~= nil, "item fields " .. tostring(item.Id))
end
check(true, "every item has Id/Name/Price/Currency/IconAssetId/Rarity/Category")
check(Format.Abbreviate(1500) == "1.5K", "Format 1500 -> " .. Format.Abbreviate(1500))
check(Format.Abbreviate(2_000_000_000) == "2B", "Format 2e9 -> " .. Format.Abbreviate(2_000_000_000))
check(Format.Abbreviate(999) == "999", "Format 999 -> " .. Format.Abbreviate(999))
check(Format.Abbreviate(12_345) == "12.3K", "Format 12345 -> " .. Format.Abbreviate(12_345))
check(Format.Percent(3.4, true) == "+340%", "Percent -> " .. Format.Percent(3.4, true))
check(Format.Clock(3725) == "1:02:05", "Clock -> " .. Format.Clock(3725))
check(Format.Chance(0.004) == "1 in 250", "Chance -> " .. Format.Chance(0.004))

local cmp = Stats.Compare(Stats.Effective("vac_chrome_cyclone", nil), Stats.Effective("vac_dust_buster", nil), "Cleanville")
print(string.format("  chrome cyclone vs dust buster: %s (items %d vs %d)", Format.Percent(cmp.Percent, true), cmp.TestItems, cmp.CurrentItems))
check(cmp.Percent > 1, "stronger vacuum compares positive")
local cmp2 = Stats.Compare(Stats.Effective("vac_dust_buster", nil), Stats.Effective("vac_leaf_gobbler", nil), "Cleanville")
check(cmp2.Percent < 0, "weaker vacuum compares negative: " .. Format.Percent(cmp2.Percent, true))
for _, v in Vacuums.List do
	local r = Stats.SimulateTest(Stats.Effective(v.Id, nil), v.World == "Cleanville" and "Cleanville" or "Dustlands")
	assert(r.Items > 0, "vacuum " .. v.Id .. " collects nothing in its own world")
end
check(true, "every vacuum can clean trash in its own world")

local fresh = DataTemplate.New()
local old = { Currencies = { Coins = 5 }, Vacuums = { Owned = { vac_dust_buster = true }, Equipped = "vac_dust_buster" } }
DataTemplate.Reconcile(old)
check(old.Currencies.Coins == 5 and old.Currencies.TrashKingCore == 0 and old.Daily and old.Settings.SeenIntro == false, "reconcile keeps values and fills defaults")
check(Progress.CheckAll(fresh, Vacuums.Get("vac_leaf_gobbler").Unlock) == true, "leaf gobbler unlocked for new player")
check(Progress.CheckAll(fresh, Vacuums.Get("vac_can_crusher").Unlock) == false, "can crusher locked for new player")

------------------------------------------------------------------------------------
print("== Server purchase validation")
local Net = customRequire(Shared.Net)
Net.Setup()
local ShopService = customRequire(Server.Services.ShopService)
local UpgradeService = customRequire(Server.Services.UpgradeService)
local broadcasts = {}
ShopService.Broadcast = function(_, _player, item, rarity)
	table.insert(broadcasts, item.Id .. ":" .. rarity)
end

local data = DataTemplate.New()
local player = { UserId = 1, Name = "Tester", DisplayName = "Tester", Character = nil }
local FakeData = {}
function FakeData:GetData()
	return data
end
function FakeData:IsLoaded()
	return true
end
function FakeData:Update(_, fn)
	fn(data)
	return true
end
function FakeData:GetCurrency(_, id)
	return data.Currencies[id] or 0
end
function FakeData:Give(_, id, amount)
	data.Currencies[id] = (data.Currencies[id] or 0) + amount
	return true
end
function FakeData:Spend(_, id, amount)
	if (data.Currencies[id] or 0) < amount then
		return false
	end
	data.Currencies[id] -= amount
	return true
end
local FakeFactory = {
	WorldAt = function()
		return "Cleanville"
	end,
}
local services = { DataService = FakeData, ShopService = ShopService, UpgradeService = UpgradeService, FactoryService = FakeFactory }
ShopService:Init(services)
UpgradeService:Init(services)

local Lighting = game:GetService("Lighting")
Lighting.ClockTime = 12

local function buy(id)
	task.wait(0.45) -- stay under the rate limit
	return ShopService:Purchase(player, id)
end

local r = buy("vac_leaf_gobbler")
check(not r.Ok and r.Code == "NOT_ENOUGH", "no coins -> NOT_ENOUGH (" .. tostring(r.Code) .. ")")
data.Currencies.Coins = 10_000_000
r = buy("vac_can_crusher")
check(not r.Ok and r.Code == "LOCKED", "skip chain -> LOCKED (" .. tostring(r.Error) .. ")")
r = buy("vac_leaf_gobbler")
check(r.Ok and data.Vacuums.Owned.vac_leaf_gobbler and data.Vacuums.Equipped == "vac_leaf_gobbler", "buy leaf gobbler, auto-equipped")
check(data.Currencies.Coins == 10_000_000 - 250, "price deducted exactly")
r = buy("vac_leaf_gobbler")
check(not r.Ok and r.Code == "ALREADY_OWNED", "buy twice -> ALREADY_OWNED")
r = buy("nope")
check(not r.Ok and r.Code == "INVALID_ITEM", "unknown id -> INVALID_ITEM")
r = ShopService:Purchase(player, { "table" })
check(not r.Ok and r.Code == "INVALID", "non-string id -> INVALID")
r = buy("cap_park")
check(r.Ok and r.PetId and #data.Pets == 1, "capsule rolls a pet: " .. tostring(r.PetId))
r = buy("cap_moonlight")
check(not r.Ok and r.Code == "NIGHT_ONLY", "night capsule at noon -> NIGHT_ONLY")
Lighting.ClockTime = 22
r = buy("cap_moonlight")
check(r.Ok, "night capsule at 22:00 -> ok")
Lighting.ClockTime = 12
r = buy("deal_mystery_crate")
check(r.Ok and r.Reward and r.Reward.Kind, "mystery crate reward: " .. tostring(r.Reward and r.Reward.Kind))
r = buy("deal_mystery_crate")
check(not r.Ok and r.Code == "DAILY_LIMIT", "second crate same day -> DAILY_LIMIT")
r = buy("boost_coins_2x")
check(r.Ok and r.ExpiresAt and r.ExpiresAt > os.time(), "boost activated")
r = buy("boost_mega")
check(not r.Ok and r.Code == "USE_ROBUX", "robux boost via remote -> USE_ROBUX")
r = buy("gp_vip")
check(not r.Ok and r.Code == "USE_ROBUX", "gamepass via remote -> USE_ROBUX")
local before = data.Currencies.Coins
r = buy("upg_tank")
check(r.Ok and data.Upgrades.upg_tank == 1 and before - data.Currencies.Coins == Upgrades.Cost("upg_tank", 0), "upgrade level 1, exact cost")
r = buy("tro_mini_trash_king")
check(not r.Ok and r.Code == "LOCKED", "trophy without boss -> LOCKED")
data.Currencies.TrashKingCore = 3
r = buy("tro_mini_trash_king")
check(r.Ok and data.Trophies.tro_mini_trash_king and data.Currencies.TrashKingCore == 0, "trophy with 3 cores -> ok, cores spent")
r = buy("vac_sandsifter")
check(not r.Ok and r.Code == "LOCKED", "dustlands vacuum before world unlock -> LOCKED")
r = buy("cos_skin_candy")
check(r.Ok and data.Cosmetics.Skin == "cos_skin_candy", "skin bought and equipped")
r = ShopService:EquipCosmetic(player, "Skin", nil)
check(r.Ok and data.Cosmetics.Skin == nil, "skin unequipped")
task.wait(0.3)
r = ShopService:EquipCosmetic(player, "Trail", "cos_skin_candy")
check(not r.Ok, "skin in trail slot rejected")
task.wait(0.3)
r = ShopService:EquipVacuum(player, "vac_chrome_cyclone")
check(not r.Ok and r.Code == "NOT_OWNED", "equip unowned vacuum -> NOT_OWNED")
task.wait(0.3)
r = ShopService:SetSetting(player, "LowGraphics", true)
check(r.Ok and data.Settings.LowGraphics == true, "setting saved")
task.wait(0.3)
r = ShopService:SetSetting(player, "Coins", 999)
check(not r.Ok, "arbitrary data key via SetSetting rejected")
-- rate limit
local limited = false
for _ = 1, 12 do
	local res = ShopService:Purchase(player, "cap_park")
	if res.Code == "RATE_LIMITED" then
		limited = true
	end
end
check(limited, "spamming purchases gets RATE_LIMITED")
-- pet inventory cap
data.Pets = {}
for i = 1, data.PetCapacity do
	table.insert(data.Pets, { Uid = tostring(i), Id = "pet_dust_bunny", Obtained = 0 })
end
task.wait(3)
r = ShopService:Purchase(player, "cap_park")
check(not r.Ok and r.Code == "INVENTORY_FULL", "full inventory -> INVENTORY_FULL")
print("  broadcasts sent: " .. #broadcasts)

print(if failures == 0 then "ALL CHECKS PASSED" else failures .. " CHECK(S) FAILED")
process.exit(if failures == 0 then 0 else 1)
