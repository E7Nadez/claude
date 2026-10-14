-- Film look for shows: letterbox bars, depth of field that rack-focuses on
-- the subject, bloom so neon really glows, a subtle color grade, a vignette
-- and "impact frames" for the big moments. Local-only post effects, all
-- restored when the show ends (also when skipped or cancelled).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Effects = require(script.Parent.Effects)
local UIFx = require(script.Parent.UI.UIFx)
local Theme = require(script.Parent.UI.Theme)

local Cinematics = {}
Cinematics.__index = Cinematics

local function play(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	return tween
end

export type Options = {
	Letterbox: boolean?,
	DepthOfField: boolean?,
	Bloom: number?,
	Grade: boolean?,
	Vignette: boolean?,
}

-- Starts the film look. Returns a handle; call handle:End() to restore.
function Cinematics.Begin(options: Options?)
	local opts = options or {}
	local self = setmetatable({}, Cinematics)
	self.Ended = false
	self.Instances = {}
	self.FocusTarget = nil :: (Vector3 | BasePart)?
	local low = Effects.IsLow()

	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopCinematic"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = Theme.Layers.Banner - 1
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.Gui = gui
	table.insert(self.Instances, gui)

	if opts.Letterbox ~= false then
		local bars = {}
		for _, top in { true, false } do
			local bar = Instance.new("Frame")
			bar.Name = if top then "Top" else "Bottom"
			bar.BorderSizePixel = 0
			bar.BackgroundColor3 = Color3.new(0, 0, 0)
			bar.AnchorPoint = Vector2.new(0, if top then 0 else 1)
			bar.Position = UDim2.fromScale(0, if top then 0 else 1)
			bar.Size = UDim2.fromScale(1, 0)
			bar.ZIndex = 3
			bar.Parent = gui
			play(bar, TweenInfo.new(0.6, Enum.EasingStyle.Quint), { Size = UDim2.fromScale(1, 0.085) })
			table.insert(bars, bar)
		end
		self.Bars = bars
	end

	if opts.Vignette ~= false then
		local vignette = UIFx.Vignette(gui, 0.45)
		for _, edge in vignette:GetChildren() do
			if edge:IsA("Frame") then
				edge.BackgroundTransparency = 1
				play(edge, TweenInfo.new(0.8), { BackgroundTransparency = 0 })
			end
		end
		self.Vignette = vignette
	end

	if opts.DepthOfField ~= false and not low then
		local dof = Instance.new("DepthOfFieldEffect")
		dof.Name = "ShopDepthOfField"
		dof.FarIntensity = 0
		dof.NearIntensity = 0
		dof.FocusDistance = 20
		dof.InFocusRadius = 18
		dof.Parent = Lighting
		play(dof, TweenInfo.new(0.8), { FarIntensity = 0.38, NearIntensity = 0.15 })
		self.Dof = dof
		table.insert(self.Instances, dof)
	end

	local bloomStrength = opts.Bloom or 0.7
	if bloomStrength > 0 and not low then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "ShopBloom"
		bloom.Intensity = 0
		bloom.Size = 28
		bloom.Threshold = 0.92
		bloom.Parent = Lighting
		play(bloom, TweenInfo.new(0.8), { Intensity = bloomStrength })
		self.Bloom = bloom
		self.BloomBase = bloomStrength
		table.insert(self.Instances, bloom)
	end

	if opts.Grade ~= false then
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "ShopGrade"
		grade.Parent = Lighting
		play(grade, TweenInfo.new(0.8), { Contrast = 0.12, Saturation = 0.15 })
		self.Grade = grade
		table.insert(self.Instances, grade)
	end

	-- Rack focus on the current subject every frame.
	self.Connection = RunService.RenderStepped:Connect(function()
		local dof = self.Dof
		local target = self.FocusTarget
		if not dof or not target then
			return
		end
		local position = if typeof(target) == "Vector3" then target else (target :: BasePart).Position
		local distance = (workspace.CurrentCamera.CFrame.Position - position).Magnitude
		dof.FocusDistance += (distance - dof.FocusDistance) * 0.18
		dof.InFocusRadius = math.clamp(distance * 0.35, 4, 30)
	end)
	return self
end

function Cinematics:Focus(target: Vector3 | BasePart)
	self.FocusTarget = target
end

-- White flash + bloom spike + exposure kick for the climax of a show.
function Cinematics:Impact(color: Color3?, strength: number?)
	local s = strength or 1
	Effects.ScreenFlash(Color3.new(1, 1, 1):Lerp(color or Color3.new(1, 1, 1), 0.3), 0.55 * s, 0.45)
	if self.Bloom then
		self.Bloom.Intensity = (self.BloomBase or 0.7) + 1.6 * s
		play(self.Bloom, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { Intensity = self.BloomBase or 0.7 })
	end
	if self.Grade then
		self.Grade.Brightness = 0.25 * s
		play(self.Grade, TweenInfo.new(0.5), { Brightness = 0 })
	end
	if self.Bars then
		for _, bar in self.Bars do
			bar.Size = UDim2.fromScale(1, 0.1)
			play(bar, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Size = UDim2.fromScale(1, 0.085) })
		end
	end
end

-- Briefly widens the bars (dramatic beat before a reveal).
function Cinematics:Tension(amount: number?)
	if self.Bars then
		for _, bar in self.Bars do
			play(bar, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Size = UDim2.fromScale(1, 0.085 + (amount or 0.04)) })
		end
	end
end

function Cinematics:End()
	if self.Ended then
		return
	end
	self.Ended = true
	if self.Connection then
		self.Connection:Disconnect()
	end
	local fade = TweenInfo.new(0.6, Enum.EasingStyle.Quint)
	if self.Bars then
		for _, bar in self.Bars do
			play(bar, fade, { Size = UDim2.fromScale(1, 0) })
		end
	end
	if self.Vignette then
		for _, edge in self.Vignette:GetChildren() do
			if edge:IsA("Frame") then
				play(edge, fade, { BackgroundTransparency = 1 })
			end
		end
	end
	if self.Dof then
		play(self.Dof, fade, { FarIntensity = 0, NearIntensity = 0 })
	end
	if self.Bloom then
		play(self.Bloom, fade, { Intensity = 0 })
	end
	if self.Grade then
		play(self.Grade, fade, { Contrast = 0, Saturation = 0, Brightness = 0 })
	end
	local instances = self.Instances
	task.delay(0.65, function()
		for _, instance in instances do
			instance:Destroy()
		end
	end)
end

Cinematics.Destroy = Cinematics.End

return Cinematics
