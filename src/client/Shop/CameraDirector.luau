-- Owns the camera while the shop needs it: smooth glides, follow functions,
-- shake and FOV punches, then hands control back to the default camera.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local CameraDirector = {}

local camera = workspace.CurrentCamera
local owner: any = nil
local baseFov = 70
local savedType: Enum.CameraType = Enum.CameraType.Custom

local state = {
	From = CFrame.new(),
	To = CFrame.new(),
	Start = 0,
	Duration = 0,
	Style = Enum.EasingStyle.Quint,
	FovFrom = 70,
	FovTo = 70,
	Follow = nil :: ((dt: number) -> CFrame)?,
	ShakeAmp = 0,
	ShakeUntil = 0,
	Punch = 0,
	PunchUntil = 0,
	ReduceMotion = false,
}

local TweenService = game:GetService("TweenService")

local function eased(alpha: number, style: Enum.EasingStyle): number
	return TweenService:GetValue(alpha, style, Enum.EasingDirection.InOut)
end

local function step(dt: number)
	local now = os.clock()
	local cf
	if state.Follow then
		cf = state.Follow(dt)
	else
		local alpha = if state.Duration > 0 then math.clamp((now - state.Start) / state.Duration, 0, 1) else 1
		local e = eased(alpha, state.Style)
		cf = state.From:Lerp(state.To, e)
		camera.FieldOfView = state.FovFrom + (state.FovTo - state.FovFrom) * e
	end
	if state.ShakeUntil > now and not state.ReduceMotion then
		local remaining = (state.ShakeUntil - now)
		local amp = state.ShakeAmp * math.clamp(remaining, 0, 1)
		local t = now * 30
		cf = cf * CFrame.new(math.noise(t, 0.3) * amp, math.noise(0.7, t) * amp, 0) * CFrame.Angles(0, 0, math.noise(t, t * 0.5) * amp * 0.02)
	end
	if state.PunchUntil > now then
		local k = (state.PunchUntil - now) / 0.5
		camera.FieldOfView = state.FovTo + state.Punch * math.sin(k * math.pi)
	end
	camera.CFrame = cf
end

function CameraDirector.IsActive(): boolean
	return owner ~= nil
end

function CameraDirector.Owner(): any
	return owner
end

-- Takes over the camera. Returns false if someone else holds it and force is not set.
function CameraDirector.Acquire(newOwner: any, force: boolean?): boolean
	if owner and owner ~= newOwner and not force then
		return false
	end
	if not owner then
		savedType = camera.CameraType
		baseFov = camera.FieldOfView
		state.From = camera.CFrame
		state.To = camera.CFrame
		state.FovFrom = baseFov
		state.FovTo = baseFov
		state.Duration = 0
		RunService:BindToRenderStep("ShopCamera", Enum.RenderPriority.Camera.Value + 2, step)
	end
	owner = newOwner
	state.Follow = nil
	camera.CameraType = Enum.CameraType.Scriptable
	return true
end

function CameraDirector.Release(releaser: any)
	if owner == nil or (releaser ~= nil and owner ~= releaser) then
		return
	end
	owner = nil
	state.Follow = nil
	state.ShakeUntil = 0
	state.PunchUntil = 0
	RunService:UnbindFromRenderStep("ShopCamera")
	camera.CameraType = if savedType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else savedType
	camera.FieldOfView = baseFov
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

function CameraDirector.GlideTo(cf: CFrame, duration: number, style: Enum.EasingStyle?, fov: number?)
	state.Follow = nil
	state.From = camera.CFrame
	state.To = cf
	state.Start = os.clock()
	state.Duration = duration
	state.Style = style or Enum.EasingStyle.Quint
	state.FovFrom = camera.FieldOfView
	state.FovTo = fov or state.FovTo
end

function CameraDirector.Snap(cf: CFrame, fov: number?)
	state.Follow = nil
	state.From = cf
	state.To = cf
	state.Duration = 0
	state.FovFrom = fov or state.FovTo
	state.FovTo = fov or state.FovTo
	camera.CFrame = cf
	if fov then
		camera.FieldOfView = fov
	end
end

-- Per-frame camera function (e.g. following a rolling capsule).
function CameraDirector.Follow(fn: (dt: number) -> CFrame)
	state.Follow = fn
end

function CameraDirector.StopFollow()
	state.Follow = nil
	state.From = camera.CFrame
	state.To = camera.CFrame
	state.Duration = 0
end

function CameraDirector.Shake(amplitude: number, duration: number)
	if amplitude <= 0 then
		return
	end
	state.ShakeAmp = math.max(amplitude, if state.ShakeUntil > os.clock() then state.ShakeAmp else 0)
	state.ShakeUntil = os.clock() + duration
end

function CameraDirector.Punch(amount: number)
	if amount <= 0 then
		return
	end
	state.Punch = amount
	state.PunchUntil = os.clock() + 0.5
end

function CameraDirector.SetReduceMotion(enabled: boolean)
	state.ReduceMotion = enabled
end

function CameraDirector.BaseFov(): number
	return baseFov
end

-- Camera CFrame looking from `position` at `target`.
function CameraDirector.Look(position: Vector3, target: Vector3): CFrame
	return CFrame.lookAt(position, target)
end

return CameraDirector
