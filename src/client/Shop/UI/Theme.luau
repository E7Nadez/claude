-- Visual tokens for every shop surface: dark glass, soft strokes, accent
-- gradients. Change these to restyle the whole shop.

local Theme = {}

Theme.Colors = {
	Backdrop = Color3.fromRGB(6, 8, 14),
	Panel = Color3.fromRGB(18, 21, 32),
	PanelLight = Color3.fromRGB(30, 34, 50),
	PanelHover = Color3.fromRGB(40, 45, 66),
	Stroke = Color3.fromRGB(255, 255, 255),
	Text = Color3.fromRGB(240, 244, 255),
	SubText = Color3.fromRGB(150, 160, 188),
	Muted = Color3.fromRGB(96, 104, 128),
	Accent = Color3.fromRGB(88, 140, 255),
	AccentAlt = Color3.fromRGB(160, 96, 255),
	Success = Color3.fromRGB(64, 214, 140),
	Danger = Color3.fromRGB(255, 82, 104),
	Warning = Color3.fromRGB(255, 186, 64),
	Gold = Color3.fromRGB(255, 204, 64),
	Locked = Color3.fromRGB(110, 116, 138),
}

Theme.ButtonStyles = {
	Primary = { Color3.fromRGB(80, 130, 255), Color3.fromRGB(140, 90, 255) },
	Success = { Color3.fromRGB(40, 200, 120), Color3.fromRGB(30, 170, 190) },
	Gold = { Color3.fromRGB(255, 196, 60), Color3.fromRGB(255, 136, 40) },
	Danger = { Color3.fromRGB(255, 80, 100), Color3.fromRGB(220, 50, 120) },
	Secondary = { Color3.fromRGB(52, 58, 82), Color3.fromRGB(40, 44, 64) },
	Ghost = { Color3.fromRGB(30, 34, 50), Color3.fromRGB(24, 27, 40) },
	Disabled = { Color3.fromRGB(60, 64, 78), Color3.fromRGB(46, 50, 62) },
}

Theme.Fonts = {
	Title = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy),
	Bold = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
	Medium = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium),
	Body = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium),
	Numbers = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold),
}

Theme.Radius = {
	Small = UDim.new(0, 8),
	Medium = UDim.new(0, 14),
	Large = UDim.new(0, 20),
	Pill = UDim.new(1, 0),
}

Theme.Tween = {
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Medium = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Spring = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Press = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Open = TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Close = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
}

-- Display orders of the shop ScreenGuis.
Theme.Layers = {
	Hud = 10,
	FactoryHud = 12,
	Classic = 20,
	Banner = 28,
	Modal = 30,
	Effects = 40,
	Fade = 50,
}

return Theme
