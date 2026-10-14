-- Usage: rojo build default.project.json -o build.rbxlx && lune run tests/lune/models.luau build.rbxlx
-- Note: Lune cannot read BasePart.Position or call Model:ScaleTo/PivotTo, so the
-- loader rewrites those calls to small polyfills. Lune's CFrame.lookAt is not
-- Roblox-accurate, so only use this to catch runtime errors, not to judge looks.
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
	source = source:gsub("([%w_%.]+):GetExtentsSize%(%)", "__extents(%1)")
	source = source:gsub("([%w_%.]+):ScaleTo%(", "__scaleTo(%1, ")
	source = source:gsub("([%w_%.]+):PivotTo%(", "__pivotTo(%1, ")
	source = source:gsub("([%w_%.]+):GetPivot%(%)", "__getPivot(%1)")
	source = source:gsub("workspace:BulkMoveTo%(", "__bulk(")
	-- Lune cannot read/write the derived Position property of parts/attachments
	source = source:gsub("([%w_%.]+)%.Position%s*=%s*([^=\n][^\n]*)", "__setpos(%1, %2)")
	source = source:gsub("([%w_%.]+)%.Position", "__pos(%1)")
	return source
end

local function parts(model)
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end
local function extents(model)
	local min, max = roblox.Vector3.new(math.huge, math.huge, math.huge), roblox.Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, p in parts(model) do
		local h = p.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local c = p.CFrame * roblox.Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)
					min = roblox.Vector3.new(math.min(min.X, c.X), math.min(min.Y, c.Y), math.min(min.Z, c.Z))
					max = roblox.Vector3.new(math.max(max.X, c.X), math.max(max.Y, c.Y), math.max(max.Z, c.Z))
				end
			end
		end
	end
	return max - min
end
local function posOf(x)
	if typeof(x) == "Instance" and (x:IsA("BasePart") or x:IsA("Attachment")) then
		return x.CFrame.Position
	end
	return x.Position
end
local function setPos(x, v)
	if typeof(x) == "Instance" and (x:IsA("BasePart") or x:IsA("Attachment")) then
		x.CFrame = roblox.CFrame.new(v) * x.CFrame.Rotation
	else
		x.Position = v
	end
end
local function getPivot(model)
	return if model.PrimaryPart then model.PrimaryPart.CFrame else roblox.CFrame.new()
end
local function scaleTo(model, s)
	local pivot = getPivot(model)
	for _, p in parts(model) do
		local rel = pivot:ToObjectSpace(p.CFrame)
		p.Size = p.Size * s
		p.CFrame = pivot * (roblox.CFrame.new(rel.Position * s) * rel.Rotation)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("Attachment") then
			setPos(d, posOf(d) * s)
		end
	end
end
local function pivotTo(model, cf)
	local pivot = getPivot(model)
	for _, p in parts(model) do
		p.CFrame = cf * pivot:ToObjectSpace(p.CFrame)
	end
end
local function bulk(list, cframes)
	assert(#list == #cframes, "BulkMoveTo size mismatch")
	for i, p in list do
		assert(p ~= nil, "nil part in BulkMoveTo")
		local cf = cframes[i]
		assert(cf.Position.X == cf.Position.X, "NaN CFrame in BulkMoveTo for " .. p.Name)
		p.CFrame = cf
	end
end

local function makeEnv(scriptInstance)
	local env = {
		script = scriptInstance,
		game = gameProxy,
		workspace = game:GetService("Workspace"),
		__extents = extents,
		__scaleTo = scaleTo,
		__pivotTo = pivotTo,
		__getPivot = getPivot,
		__bulk = bulk,
		__pos = posOf,
		__setpos = setPos,
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


local Shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
local Vacuums = customRequire(Shared.Definitions.Vacuums)
local Pets = customRequire(Shared.Definitions.Pets)
local Trophies = customRequire(Shared.Definitions.Trophies)
local Cosmetics = customRequire(Shared.Definitions.Cosmetics)
local VacuumModel = customRequire(Shared.Models.VacuumModel)
local PetModel = customRequire(Shared.Models.PetModel)
local TrophyModel = customRequire(Shared.Models.TrophyModel)
local RobotModel = customRequire(Shared.Models.RobotModel)

local function nanFree(model)
	for _, p in parts(model) do
		local pos = p.CFrame.Position
		if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then
			return false, p.Name
		end
	end
	return true
end

print("== Vacuum models")
for _, v in Vacuums.List do
	local ok, model = pcall(VacuumModel.Build, v.Id)
	if not ok then
		check(false, v.Id .. " build: " .. tostring(model))
		continue
	end
	local count, missing = 0, 0
	for _, p in parts(model) do
		if p ~= model.PrimaryPart then
			count += 1
			if typeof(p:GetAttribute("Home")) ~= "CFrame" or typeof(p:GetAttribute("Explode")) ~= "Vector3" or type(p:GetAttribute("Role")) ~= "string" then
				missing += 1
			end
		end
	end
	local size = extents(model)
	local nan = nanFree(model)
	check(count >= 10 and missing == 0 and nan, string.format("%s (%s): %d parts, size %.1f x %.1f x %.1f", v.Id, v.Look.Shape, count, size.X, size.Y, size.Z))
	local order = VacuumModel.AssemblyOrder(model)
	check(#order == count, v.Id .. " assembly order covers all parts")
end
for _, c in Cosmetics.List do
	local ok, err = pcall(function()
		local model = VacuumModel.Build("vac_chrome_cyclone", { Skin = if c.Slot == "Skin" then c.Id else nil })
		if c.Slot == "Trail" then
			local trail = VacuumModel.AttachTrail(model, c.Id)
			assert(trail and trail.Attachment0 and trail.Attachment1, "trail not attached")
		end
		VacuumModel.ApplySkin(model, nil)
	end)
	check(ok, "cosmetic " .. c.Id .. (if ok then "" else ": " .. tostring(err)))
end

print("== Pets / trophies / robots")
for _, pet in Pets.List do
	local ok, model = pcall(PetModel.Build, pet.Id)
	check(ok and #parts(model) >= 5 and nanFree(model), "pet " .. pet.Id .. (if ok then " (" .. #parts(model) .. " parts)" else ": " .. tostring(model)))
end
for _, trophy in Trophies.List do
	local ok, model = pcall(TrophyModel.Build, trophy.Model)
	check(ok and #parts(model) >= 4 and nanFree(model), "trophy " .. trophy.Model .. (if ok then " (" .. #parts(model) .. " parts)" else ": " .. tostring(model)))
	if ok and trophy.Model == "MiniRustDragon" then
		check(model:FindFirstChild("Mouth", true) ~= nil, "mini rust dragon has a Mouth for fire")
	end
end
local worker = RobotModel.Worker(roblox.Color3.new(0.5, 0.5, 0.5), roblox.Color3.new(0, 1, 1))
local okPose, errPose = pcall(RobotModel.PoseWorker, worker, roblox.CFrame.new(10, 0, 5), 1.3, true, 0.5, 0.4)
check(okPose and nanFree(worker), "worker pose " .. tostring(errPose or ""))
local arm = RobotModel.Arm(roblox.Color3.new(0.5, 0.5, 0.5), roblox.Color3.new(1, 0, 0))
local maxErr = 0
for _, target in { roblox.Vector3.new(3, 4, 2), roblox.Vector3.new(-2, 6, 3), roblox.Vector3.new(0, 2.5, 5), roblox.Vector3.new(4, 7, -1) } do
	local tip = RobotModel.ReachArm(arm, roblox.CFrame.new(0, 0, 0), target, 0.5)
	local tipPart = arm:FindFirstChild("Tip")
	maxErr = math.max(maxErr, (tipPart.CFrame.Position - target).Magnitude)
end
check(nanFree(arm), "arm IK produces valid CFrames")
print(string.format("  arm IK max tip error for reachable targets: %.2f studs", maxErr))
check(maxErr < 1.2, "arm reaches its targets")
local far = RobotModel.ReachArm(arm, roblox.CFrame.new(0, 0, 0), roblox.Vector3.new(0, 30, 0), 0)
check(nanFree(arm), "arm IK stays valid for unreachable/vertical target")

print(if failures == 0 then "ALL MODEL CHECKS PASSED" else failures .. " CHECK(S) FAILED")
process.exit(if failures == 0 then 0 else 1)
