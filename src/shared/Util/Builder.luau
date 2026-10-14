-- Small helpers to assemble parts from code. Used by the server factory
-- builder and by the client model builders (vacuums, pets, robots ...).
-- Everything here creates regular Parts, never EditableMeshes.

local CollectionService = game:GetService("CollectionService")

local Builder = {}

local SPECIAL = {
	ClassName = true,
	Parent = true,
	Size = true,
	CFrame = true,
	Shape = true,
	Tags = true,
	Attributes = true,
	Children = true,
}

local function applyCommon(instance: Instance, props: { [string]: any })
	for key, value in props do
		if not SPECIAL[key] then
			(instance :: any)[key] = value
		end
	end
	if props.Attributes then
		for key, value in props.Attributes do
			instance:SetAttribute(key, value)
		end
	end
	if props.Tags then
		for _, tag in props.Tags do
			CollectionService:AddTag(instance, tag)
		end
	end
	if props.Children then
		for _, child in props.Children do
			child.Parent = instance
		end
	end
end

-- Builder.Part({ Size = ..., CFrame = ..., Color = ..., Parent = ... })
function Builder.Part(props: { [string]: any }): BasePart
	local part = Instance.new(props.ClassName or "Part") :: BasePart
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	if props.Shape and part:IsA("Part") then
		part.Shape = props.Shape
	end
	if props.Size then
		part.Size = props.Size
	end
	if props.CFrame then
		part.CFrame = props.CFrame
	end
	applyCommon(part, props)
	part.Parent = props.Parent
	return part
end

function Builder.Instance(className: string, props: { [string]: any }?): Instance
	local instance = Instance.new(className)
	if props then
		applyCommon(instance, props)
		instance.Parent = props.Parent
	end
	return instance
end

function Builder.Model(name: string, parent: Instance?): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

function Builder.Folder(name: string, parent: Instance?): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- CFrame whose X axis points from a to b (Roblox cylinders extend along X).
-- Built from an explicit basis so vertical directions are well defined.
function Builder.AxisCFrame(a: Vector3, b: Vector3): CFrame
	local mid = (a + b) / 2
	local dir = b - a
	if dir.Magnitude < 1e-4 then
		return CFrame.new(mid)
	end
	local x = dir.Unit
	local reference = if math.abs(x.Y) > 0.98 then Vector3.zAxis else Vector3.yAxis
	local z = x:Cross(reference).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix(mid, x, y, z)
end

-- Cylinder from point a to point b.
function Builder.Pipe(a: Vector3, b: Vector3, radius: number, props: { [string]: any }): BasePart
	local length = (b - a).Magnitude
	local p = table.clone(props)
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(math.max(length, 0.05), radius * 2, radius * 2)
	p.CFrame = Builder.AxisCFrame(a, b)
	return Builder.Part(p)
end

-- Block beam from a to b (for rails, struts, wires). Z axis runs along a->b.
function Builder.Beam(a: Vector3, b: Vector3, width: number, height: number, props: { [string]: any }): BasePart
	local dir = b - a
	local length = dir.Magnitude
	local p = table.clone(props)
	p.Size = Vector3.new(width, height, math.max(length, 0.05))
	if length < 1e-4 then
		p.CFrame = CFrame.new(a)
	else
		local z = dir.Unit
		local reference = if math.abs(z.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
		local x = reference:Cross(z).Unit
		local y = z:Cross(x).Unit
		p.CFrame = CFrame.fromMatrix((a + b) / 2, x, y, z)
	end
	return Builder.Part(p)
end

-- Ring of segments around cf's Z axis (the ring lies in cf's XY plane).
function Builder.Ring(cf: CFrame, radius: number, thickness: number, depth: number, segments: number, props: { [string]: any }): { BasePart }
	local parts = {}
	local segLength = 2 * math.pi * radius / segments * 1.04
	for i = 1, segments do
		local angle = (i - 1) / segments * math.pi * 2
		local p = table.clone(props)
		p.Size = Vector3.new(segLength, thickness, depth)
		p.CFrame = cf * CFrame.Angles(0, 0, angle) * CFrame.new(0, radius, 0)
		table.insert(parts, Builder.Part(p))
	end
	return parts
end

-- Gear: a disc with teeth. Returns the parts so callers can spin them as one.
function Builder.Gear(cf: CFrame, radius: number, depth: number, teeth: number, props: { [string]: any }): { BasePart }
	local parts = {}
	local disc = table.clone(props)
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(depth, radius * 2, radius * 2)
	disc.CFrame = cf * CFrame.Angles(0, math.pi / 2, 0)
	table.insert(parts, Builder.Part(disc))

	local hub = table.clone(props)
	hub.Shape = Enum.PartType.Cylinder
	hub.Size = Vector3.new(depth * 1.4, radius * 0.5, radius * 0.5)
	hub.CFrame = cf * CFrame.Angles(0, math.pi / 2, 0)
	hub.Color = (props.Color or Color3.new(0.5, 0.5, 0.5)):Lerp(Color3.new(0, 0, 0), 0.35)
	table.insert(parts, Builder.Part(hub))

	local toothWidth = 2 * math.pi * radius / teeth * 0.45
	for i = 1, teeth do
		local angle = (i - 1) / teeth * math.pi * 2
		local tooth = table.clone(props)
		tooth.Size = Vector3.new(toothWidth, radius * 0.28, depth)
		tooth.CFrame = cf * CFrame.Angles(0, 0, angle) * CFrame.new(0, radius + radius * 0.1, 0)
		table.insert(parts, Builder.Part(tooth))
	end
	return parts
end

-- Text sign on one face of a part.
function Builder.Sign(part: BasePart, face: Enum.NormalId, text: string, options: { [string]: any }?): SurfaceGui
	local opts = options or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = opts.Name or "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = opts.PixelsPerStud or 40
	gui.LightInfluence = opts.LightInfluence or 0
	gui.Brightness = opts.Brightness or 1.5
	gui.MaxDistance = opts.MaxDistance or 400
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = opts.Font or Enum.Font.GothamBlack
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = opts.TextColor or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = opts.StrokeTransparency or 0.6
	label.Parent = gui

	local padding = Instance.new("UIPadding")
	local pad = UDim.new(opts.Padding or 0.08, 0)
	padding.PaddingLeft = pad
	padding.PaddingRight = pad
	padding.PaddingTop = pad
	padding.PaddingBottom = pad
	padding.Parent = label
	return gui
end

function Builder.Light(parent: Instance, className: string, props: { [string]: any }): Light
	local p = table.clone(props)
	p.Parent = parent
	return Builder.Instance(className, p) :: Light
end

function Builder.Weld(a: BasePart, b: BasePart): WeldConstraint
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = a
	weld.Part1 = b
	weld.Parent = a
	return weld
end

-- Weld every BasePart of a model to its PrimaryPart and unanchor them.
function Builder.WeldModel(model: Model, anchorRoot: boolean)
	local root = model.PrimaryPart
	assert(root, "WeldModel needs a PrimaryPart")
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			Builder.Weld(root, d)
			d.Anchored = false
		end
	end
	root.Anchored = anchorRoot
end

-- Sets CanCollide / CanQuery / CanTouch / Massless for every part of a model.
function Builder.SetPhysics(model: Instance, collide: boolean, query: boolean?)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = collide
			d.CanQuery = query == true
			d.CanTouch = false
			d.Massless = true
		end
	end
end

return Builder
