local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")
local HttpService        = game:GetService("HttpService")
local VirtualUser        = game:GetService("VirtualUser")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G

local MEKI_CONFIG = {
    AUTO_EXEC_SCRIPT_URL = "https://raw.githubusercontent.com/mekinjir/Gumanba/main/meki.lua",
}

if env.MekiHub_Cleanup then
	pcall(env.MekiHub_Cleanup)
end

local isCleaningUp = false
local cleanupConns = {}
local function addCleanup(conn)
	table.insert(cleanupConns, conn)
	return conn
end

local T = {
	Bg         = Color3.fromRGB(18, 18, 24),
	Topbar     = Color3.fromRGB(24, 24, 32),
	Sidebar    = Color3.fromRGB(21, 21, 28),
	Panel      = Color3.fromRGB(30, 30, 40),
	PanelHover = Color3.fromRGB(38, 38, 52),
	PanelLite  = Color3.fromRGB(40, 40, 56),
	Track      = Color3.fromRGB(14, 14, 20),
	Stroke     = Color3.fromRGB(55, 55, 75),
	Accent     = Color3.fromRGB(0, 210, 255),
	AccentDark = Color3.fromRGB(0, 147, 178),
	Text       = Color3.fromRGB(255, 255, 255),
	SubText    = Color3.fromRGB(155, 165, 188),
	Danger     = Color3.fromRGB(255, 75, 75),
	Success    = Color3.fromRGB(70, 220, 140),
}
local FONT  = Enum.Font.GothamMedium
local FONTB = Enum.Font.GothamBold

local THEMES = {
	{"Cyan",   Color3.fromRGB(0, 210, 255)},
	{"Ungu",   Color3.fromRGB(160, 110, 255)},
	{"Hijau",  Color3.fromRGB(70, 220, 140)},
	{"Pink",   Color3.fromRGB(255, 100, 180)},
	{"Orange", Color3.fromRGB(255, 150, 60)},
}
local THEME_FILE = "meki_hub_theme.txt"

local function darken(c, f)
	return Color3.new(c.R * f, c.G * f, c.B * f)
end

local function hasFileAPI()
	return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
end

local currentThemeName = "Cyan"
pcall(function()
	if hasFileAPI() and isfile(THEME_FILE) then
		local name = readfile(THEME_FILE):gsub("%s+", "")
		for _, th in ipairs(THEMES) do
			if th[1] == name then
				currentThemeName = name
				T.Accent = th[2]
				T.AccentDark = darken(th[2], 0.7)
			end
		end
	end
end)

local WIN_W, WIN_H, SIDEBAR_W = 540, 380, 132
local AUTO_INTERVAL = 1.0

local accentReg = {}
local gradReg = {}
local themeCallbacks = {}
local pruneReg

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		o[k] = v
		if typeof(v) == "Color3" then
			if v == T.Accent then
				table.insert(accentReg, {o, k, "Accent"})
			elseif v == T.AccentDark then
				table.insert(accentReg, {o, k, "AccentDark"})
			end
		end
	end
	if parent then o.Parent = parent end
	return o
end

local function seqFor(kind)
	local h, s, v = T.Accent:ToHSV()
	local b = Color3.fromHSV((h + 0.09) % 1, s, v)
	if kind == "loop" then
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, T.Accent),
			ColorSequenceKeypoint.new(0.5, b),
			ColorSequenceKeypoint.new(1, T.Accent),
		})
	elseif kind == "topbar" then
		return ColorSequence.new(T.Topbar:Lerp(T.Accent, 0.12), T.Topbar)
	elseif kind == "card" then
		return ColorSequence.new(T.Panel:Lerp(T.Accent, 0.2), T.Panel)
	end
	return ColorSequence.new(T.Accent, b)
end

local function gradient(parent, kind, rotation)
	local g = new("UIGradient", {Color = seqFor(kind), Rotation = rotation or 0}, parent)
	table.insert(gradReg, {g, kind})
	return g
end

local function round(o, r)
	return new("UICorner", {CornerRadius = UDim.new(0, r or 8)}, o)
end

local function outline(o, color, thick, trans)
	return new("UIStroke", {
		Color = color or T.Stroke,
		Thickness = thick or 1,
		Transparency = trans or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, o)
end

local function tween(o, t, props)
	TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function safe(fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then warn("[MekiHub] " .. tostring(a)) return nil end
	return a, b
end

local function parentGui()
	local ok, hui = pcall(function() return gethui() end)
	if ok and hui then return hui end
	return player:WaitForChild("PlayerGui")
end

local function getHRP()
	local ch = player.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function resetHumanoidState()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		hum:ChangeState(Enum.HumanoidStateType.Running)
	end
end

local function setupDrag(targetFrame, dragArea)
	local dragging, dragInput, dragStart, startPos
	local isMoving = false

	dragArea.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			isMoving = false
			dragStart = input.Position
			startPos = targetFrame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					task.delay(0.1, function() isMoving = false end)
				end
			end)
		end
	end)
	dragArea.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)
	addCleanup(UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			local delta = input.Position - dragStart
			if delta.Magnitude > 5 then isMoving = true end
			targetFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end))
	return function() return isMoving end
end

pcall(function()
	local old = parentGui():FindFirstChild("MekiHub_UI")
	if old then old:Destroy() end
end)

local gui = new("ScreenGui", {
	Name = "MekiHub_UI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 999,
})
gui.Parent = parentGui()

task.spawn(function()
	while not isCleaningUp do
		task.wait(1)
		if not isCleaningUp and not gui.Parent then
			pcall(function() gui.Parent = parentGui() end)
		end
	end
end)

pruneReg = function()
	local keep = {}
	for _, e in ipairs(accentReg) do
		if e[1]:IsDescendantOf(gui) then table.insert(keep, e) end
	end
	accentReg = keep
	local keepG = {}
	for _, e in ipairs(gradReg) do
		if e[1]:IsDescendantOf(gui) then table.insert(keepG, e) end
	end
	gradReg = keepG
end

local function applyTheme(name, color)
	currentThemeName = name
	T.Accent = color
	T.AccentDark = darken(color, 0.7)
	pruneReg()
	for _, e in ipairs(accentReg) do
		pcall(function() e[1][e[2]] = T[e[3]] end)
	end
	for _, e in ipairs(gradReg) do
		pcall(function() e[1].Color = seqFor(e[2]) end)
	end
	for _, cb in ipairs(themeCallbacks) do pcall(cb) end
	if hasFileAPI() then pcall(function() writefile(THEME_FILE, name) end) end
end

local function makeIcon(kind, parent)
	if not kind then return nil end
	local holder = new("Frame", {
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.new(0, 10, 0.5, -9),
		BackgroundTransparency = 1,
	}, parent)
	local fills, strokes = {}, {}
	local function box(x, y, w, h, r, rot)
		local f = new("Frame", {
			Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = T.SubText, BorderSizePixel = 0, Rotation = rot or 0,
		}, holder)
		if r then round(f, r) end
		table.insert(fills, f)
		return f
	end
	if kind == "home" then
		box(5, 1, 8, 8, 0, 45)
		box(3, 9, 12, 8, 2)
	elseif kind == "pin" then
		box(4, 1, 10, 10, 5)
		box(6, 8, 6, 6, 0, 45)
	elseif kind == "user" then
		box(5, 1, 8, 8, 4)
		box(2, 11, 14, 7, 5)
	elseif kind == "users" then
		box(2, 2, 6, 6, 3)
		box(0, 10, 10, 7, 4)
		box(11, 4, 5, 5, 3)
		box(9, 11, 9, 6, 3)
	elseif kind == "gamepad" then
		local body = new("Frame", {
			Position = UDim2.fromOffset(1, 4), Size = UDim2.fromOffset(16, 11),
			BackgroundColor3 = T.SubText, BorderSizePixel = 0, Rotation = 0,
		}, holder)
		round(body, 5)
		table.insert(fills, body)
		local d1 = box(4, 7, 2, 6, 1)
		local d2 = box(2, 9, 6, 2, 1)
		local b1 = box(11, 7, 2, 2, 1)
		local b2 = box(14, 9, 2, 2, 1)
		d1.BackgroundColor3 = T.Bg; d2.BackgroundColor3 = T.Bg
		b1.BackgroundColor3 = T.Bg; b2.BackgroundColor3 = T.Bg
	elseif kind == "eye" then
		local ring = new("Frame", {
			Position = UDim2.fromOffset(3, 5), Size = UDim2.fromOffset(12, 8),
			BackgroundTransparency = 1, BorderSizePixel = 0,
		}, holder)
		round(ring, 4)
		local st = new("UIStroke", {
			Color = T.SubText, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, ring)
		table.insert(strokes, st)
		box(6, 6, 6, 6, 3)
	elseif kind == "discord" then
        local body = box(1, 3, 16, 12, 6)
        local left = box(4, 8, 3, 3, 2)
        local right = box(11, 8, 3, 3, 2)
        left.BackgroundColor3 = T.Bg
        right.BackgroundColor3 = T.Bg
        box(2, 13, 4, 3, 2, -25)
        box(12, 13, 4, 3, 2, 25)
    elseif kind == "misc" then
		box(1, 7, 4, 4, 2)
		box(7, 7, 4, 4, 2)
		box(13, 7, 4, 4, 2)
	elseif kind == "flag" then
		box(4, 1, 2, 16)
		box(6, 2, 9, 7, 1)
	elseif kind == "record" then
		local outer = new("Frame", {
			Position = UDim2.fromOffset(1, 1), Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1, BorderSizePixel = 0,
		}, holder)
		round(outer, 9)
		local st = new("UIStroke", { Color = T.SubText, Thickness = 2 }, outer)
		table.insert(strokes, st)
		box(6, 6, 6, 6, 4)
	elseif kind == "route" then
		box(2, 2, 5, 5, 3)
		box(11, 11, 5, 5, 3)
		box(7, 4, 7, 2, 1, 45)
		box(5, 10, 7, 2, 1, 45)
	elseif kind == "gear" then
		local ring = new("Frame", {
			Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(10, 10),
			BackgroundTransparency = 1, BorderSizePixel = 0,
		}, holder)
		round(ring, 5)
		local st = new("UIStroke", {
			Color = T.SubText, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, ring)
		table.insert(strokes, st)
		box(8, 0, 2, 3)
		box(8, 15, 2, 3)
		box(0, 8, 3, 2)
		box(15, 8, 3, 2)
	end
	local obj = {}
	function obj.setColor(c)
		for _, f in ipairs(fills) do f.BackgroundColor3 = c end
		for _, s in ipairs(strokes) do s.Color = c end
	end
	return obj
end

local Lib = {}

function Lib:CreateWindow(cfg)
	local Window = {}
	local toggles = {}
	local tabs = {}
	Window.SpinBorder = true
	local flags = {}
	Window.Flags = flags

	local root = new("Frame", {
		Name = "Root",
		Size = UDim2.fromOffset(WIN_W, WIN_H),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	local uiScale = new("UIScale", {}, root)
	local baseScale, animating = 1, false
	local function updScale()
		local cam = workspace.CurrentCamera
		if not cam then return end
		local vp = cam.ViewportSize
		baseScale = math.clamp(math.min((vp.X - 24) / WIN_W, (vp.Y - 24) / WIN_H), 0.5, 1)
		if not animating then uiScale.Scale = baseScale end
	end
	updScale()
	pcall(function()
		addCleanup(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updScale))
	end)
	Window.Root = root

	function Window:IsVisible() return root.Visible end
	function Window:SetVisible(v)
		if animating or v == root.Visible then return end
		animating = true
		if v then
			uiScale.Scale = baseScale * 0.9
			root.Visible = true
			tween(uiScale, 0.22, {Scale = baseScale})
			task.delay(0.25, function()
				animating = false
				uiScale.Scale = baseScale
			end)
		else
			tween(uiScale, 0.15, {Scale = baseScale * 0.9})
			task.delay(0.17, function()
				root.Visible = false
				animating = false
				uiScale.Scale = baseScale
			end)
		end
	end
	function Window:Toggle() Window:SetVisible(not root.Visible) end

	new("ImageLabel", {
		Name = "Shadow",
		BackgroundTransparency = 1,
		Image = "rbxassetid://6014261993",
		ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 0.45,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(49, 49, 450, 450),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 50, 1, 50),
	}, root)

	local main = new("Frame", {
		Name = "Main",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.Bg,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, root)
	round(main, 14)

	local borderStroke = outline(main, Color3.new(1, 1, 1), 1.5, 0.2)
	local borderGrad = gradient(borderStroke, "loop", 0)
	addCleanup(RunService.Heartbeat:Connect(function(dt)
		if Window.SpinBorder and root.Visible then
			borderGrad.Rotation = (borderGrad.Rotation + dt * 40) % 360
		end
	end))

	local topbar = new("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, main)
	gradient(topbar, "topbar", 0)
	new("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -1),
		BackgroundColor3 = T.Stroke,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
	}, topbar)
	local titleX = 16
	new("TextLabel", {
		Text = cfg.Title or "MEKI HUB",
		Font = FONTB, TextSize = 16, TextColor3 = T.Text,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(titleX, 0), Size = UDim2.fromOffset(96, 46),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, topbar)

	local badge = new("Frame", {
		Size = UDim2.fromOffset(94, 18),
		Position = UDim2.new(0, titleX + 100, 0.5, -9),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, topbar)
	round(badge, 9)
	gradient(badge, "seq", 0)
	new("TextLabel", {
		Text = cfg.Badge or "V3",
		Font = FONTB, TextSize = 9, TextColor3 = T.Bg,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
	}, badge)

	local statsLabel = new("TextLabel", {
		Text = "-- FPS  |  -- ms",
		Font = FONTB, TextSize = 11, TextColor3 = T.SubText,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -84, 0.5, 0), Size = UDim2.fromOffset(130, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
	}, topbar)
	Window.StatsLabel = statsLabel

	local function topBtn(text, size, xOff, hoverColor)
		local b = new("TextButton", {
			Text = text, Font = FONTB, TextSize = size, TextColor3 = T.SubText,
			BackgroundColor3 = T.PanelLite, BackgroundTransparency = 1,
			AutoButtonColor = false,
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.new(1, xOff, 0.5, -14),
		}, topbar)
		round(b, 8)
		b.MouseEnter:Connect(function()
			tween(b, 0.15, {BackgroundTransparency = 0, BackgroundColor3 = hoverColor, TextColor3 = T.Text})
		end)
		b.MouseLeave:Connect(function()
			tween(b, 0.15, {BackgroundTransparency = 1, TextColor3 = T.SubText})
		end)
		return b
	end
	local closeBtn = topBtn("X", 12, -40, T.Danger)
	local minBtn   = topBtn("-", 20, -74, T.PanelLite)

	minBtn.MouseButton1Click:Connect(function() Window:SetVisible(false) end)
	closeBtn.MouseButton1Click:Connect(function()
		local ok = pcall(function()
			if env.MekiHub_Cleanup then env.MekiHub_Cleanup() else gui:Destroy() end
		end)
		if not ok then pcall(function() gui:Destroy() end) end
	end)

	local sidebar = new("Frame", {
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(0, SIDEBAR_W, 1, -46),
		BackgroundColor3 = T.Sidebar,
		BorderSizePixel = 0,
	}, main)
	new("Frame", {
		Size = UDim2.new(0, 1, 1, 0),
		Position = UDim2.new(1, -1, 0, 0),
		BackgroundColor3 = T.Stroke,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
	}, sidebar)

	-- Sidebar dibuat scrollable supaya semua tab (termasuk Config) selalu bisa diakses.
	local tabHolder = new("ScrollingFrame", {
		Name = "TabScroller",
		Size = UDim2.new(1, 0, 1, -56),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = T.Accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ClipsDescendants = true,
	}, sidebar)
	new("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}, tabHolder)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
	}, tabHolder)

	local profile = new("Frame", {
		Position = UDim2.new(0, 0, 1, -52),
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundTransparency = 1,
	}, sidebar)
	new("Frame", {
		Size = UDim2.new(1, -20, 0, 1),
		Position = UDim2.fromOffset(10, 0),
		BackgroundColor3 = T.Stroke,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
	}, profile)
	local avatar = new("ImageLabel", {
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.fromOffset(10, 11),
		BackgroundColor3 = T.PanelLite,
		BorderSizePixel = 0,
	}, profile)
	round(avatar, 15)
	local avStroke = outline(avatar, Color3.new(1, 1, 1), 1.5, 0)
	gradient(avStroke, "seq", 45)
	task.spawn(function()
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok and avatar.Parent then avatar.Image = img end
	end)
	new("TextLabel", {
		Text = player.DisplayName,
		Font = FONTB, TextSize = 12, TextColor3 = T.Text,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -54, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, profile)

	local pages = new("Frame", {
		Position = UDim2.fromOffset(SIDEBAR_W, 46),
		Size = UDim2.new(1, -SIDEBAR_W, 1, -46),
		BackgroundTransparency = 1,
	}, main)

	local notifHolder = new("Frame", {
		Size = UDim2.fromOffset(260, 400),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		BackgroundTransparency = 1,
		ZIndex = 200,
	}, gui)
	new("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	}, notifHolder)

	local notifCount = 0
	function Window:Notify(title, text, dur, kind)
		if isCleaningUp then return end
		notifCount = notifCount + 1
		local color = (kind == "error" and T.Danger) or (kind == "success" and T.Success) or T.Accent
		local holder = new("Frame", {
			Size = UDim2.new(1, 0, 0, 54),
			BackgroundTransparency = 1,
			LayoutOrder = notifCount,
		}, notifHolder)
		local toast = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(290, 0),
			BackgroundColor3 = T.Panel,
			BorderSizePixel = 0,
		}, holder)
		round(toast, 10)
		outline(toast, color, 1, 0.55)
		local bar = new("Frame", {
			Size = UDim2.new(0, 3, 1, -16), Position = UDim2.fromOffset(8, 8),
			BackgroundColor3 = color, BorderSizePixel = 0,
		}, toast)
		round(bar, 2)
		new("TextLabel", {
			Text = title, Font = FONTB, TextSize = 13, TextColor3 = T.Text,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(20, 9), Size = UDim2.new(1, -28, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, toast)
		new("TextLabel", {
			Text = text or "", Font = FONT, TextSize = 11, TextColor3 = T.SubText,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(20, 27), Size = UDim2.new(1, -28, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, toast)
		tween(toast, 0.3, {Position = UDim2.fromOffset(0, 0)})
		task.delay(dur or 2, function()
			if toast.Parent then
				tween(toast, 0.3, {Position = UDim2.fromOffset(290, 0)})
				task.wait(0.35)
			end
			pcall(function() holder:Destroy() end)
		end)
	end

	function Window:Prompt(titleText, default, cb, placeholder)
		local overlay = new("TextButton", {
			Text = "", AutoButtonColor = false,
			BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1), ZIndex = 60,
		}, gui)
		tween(overlay, 0.2, {BackgroundTransparency = 0.45})

		local dlg = new("Frame", {
			Size = UDim2.fromOffset(280, 150),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = T.Panel,
			BorderSizePixel = 0,
		}, overlay)
		round(dlg, 14)
		outline(dlg, T.Accent, 1, 0.5)

		new("TextLabel", {
			Text = titleText, Font = FONTB, TextSize = 14, TextColor3 = T.Text,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, dlg)

		local box = new("TextBox", {
			Text = default or "", Font = FONT, TextSize = 13, TextColor3 = T.Text,
			PlaceholderText = placeholder or "Nama waypoint...", PlaceholderColor3 = T.SubText,
			BackgroundColor3 = T.Track, BorderSizePixel = 0, ClearTextOnFocus = false,
			Position = UDim2.fromOffset(16, 44), Size = UDim2.new(1, -32, 0, 36),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, dlg)
		round(box, 8)
		outline(box, T.Stroke, 1, 0.3)
		new("UIPadding", {PaddingLeft = UDim.new(0, 10)}, box)

		local function dlgBtn(text, w, xOff, bg, fg)
			local b = new("TextButton", {
				Text = text, Font = FONTB, TextSize = 12, TextColor3 = fg,
				BackgroundColor3 = bg, AutoButtonColor = false,
				Size = UDim2.fromOffset(w, 32), Position = UDim2.new(1, xOff, 1, -46),
			}, dlg)
			round(b, 8)
			return b
		end
		local okBtn = dlgBtn("Simpan", 96, -112, T.Accent, T.Bg)
		local cancelBtn = dlgBtn("Batal", 80, -200, T.PanelLite, T.SubText)

		local function close()
			tween(overlay, 0.15, {BackgroundTransparency = 1})
			task.delay(0.15, function() pcall(function() overlay:Destroy() end) end)
		end
		cancelBtn.MouseButton1Click:Connect(close)
		okBtn.MouseButton1Click:Connect(function()
			if box.Text:match("%S") then safe(cb, box.Text) end
			close()
		end)
		task.defer(function() if box:IsDescendantOf(game) then box:CaptureFocus() end end)
	end

	function Window:ResetToggles()
		for _, t in ipairs(toggles) do t:Set(false, true) end
	end

	local function selectTab(target)
		for _, t in ipairs(tabs) do t._setActive(t == target) end
	end

	function Window:CreateTab(name, icon)
		local Tab = {}
		local order = 0
		local function nextOrder()
			order = order + 1
			return order
		end

		local btn = new("TextButton", {
			Text = "", AutoButtonColor = false,
			BackgroundColor3 = T.PanelLite, BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 30), BorderSizePixel = 0,
			LayoutOrder = #tabs + 1,
		}, tabHolder)
		round(btn, 8)
		local iconObj = makeIcon(icon, btn)
		local lbl = new("TextLabel", {
			Text = name, Font = FONTB, TextSize = 13, TextColor3 = T.SubText,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(36, 0), Size = UDim2.new(1, -36, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, btn)
		local bar = new("Frame", {
			Size = UDim2.fromOffset(3, 16), Position = UDim2.new(0, 0, 0.5, -8),
			BackgroundColor3 = T.Accent, BorderSizePixel = 0, Visible = false,
		}, btn)
		round(bar, 2)

		local page = new("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1, BorderSizePixel = 0,
			ScrollBarThickness = 3, ScrollBarImageColor3 = T.Accent,
			CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false,
		}, pages)
		new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, page)
		new("UIPadding", {
			PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14),
		}, page)

		Tab.Page = page

		Tab._setActive = function(on)
			page.Visible = on
			bar.Visible = on
			tween(btn, 0.15, {BackgroundTransparency = on and 0 or 1})
			tween(lbl, 0.15, {TextColor3 = on and T.Text or T.SubText})
			if iconObj then iconObj.setColor(on and T.Accent or T.SubText) end
		end
		table.insert(themeCallbacks, function()
			if page.Visible and iconObj then iconObj.setColor(T.Accent) end
		end)
		btn.MouseEnter:Connect(function()
			if not page.Visible then tween(btn, 0.15, {BackgroundTransparency = 0.6}) end
		end)
		btn.MouseLeave:Connect(function()
			if not page.Visible then tween(btn, 0.15, {BackgroundTransparency = 1}) end
		end)
		btn.MouseButton1Click:Connect(function() selectTab(Tab) end)

		table.insert(tabs, Tab)
		if #tabs == 1 then selectTab(Tab) end

		function Tab:NextOrder() return nextOrder() end

		function Tab:CreateSection(text)
			local l = new("TextLabel", {
				Text = string.upper(text), Font = FONTB, TextSize = 11, TextColor3 = T.Accent,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 22),
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = nextOrder(),
			}, page)
			new("UIPadding", {PaddingLeft = UDim.new(0, 4), PaddingTop = UDim.new(0, 6)}, l)
			return l
		end

		function Tab:CreateLabel(text)
			local l = new("TextLabel", {
				Text = text, Font = FONT, TextSize = 11, TextColor3 = T.SubText,
				TextWrapped = true,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 30),
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = nextOrder(),
			}, page)
			new("UIPadding", {PaddingLeft = UDim.new(0, 4)}, l)
			return l
		end

		function Tab:CreateButton(o)
			local baseC, hoverC, pressC
			if o.Accent then
				baseC, hoverC, pressC = Color3.new(1, 1, 1), Color3.new(0.88, 0.88, 0.88), Color3.new(0.7, 0.7, 0.7)
			elseif o.Danger then
				baseC, hoverC, pressC = T.Danger, darken(T.Danger, 0.85), darken(T.Danger, 0.7)
			else
				baseC, hoverC, pressC = T.Panel, T.PanelHover, T.PanelLite
			end
			local holder = new("Frame", {
				Size = UDim2.new(1, 0, 0, 38),
				BackgroundColor3 = baseC, BorderSizePixel = 0,
				LayoutOrder = nextOrder(),
			}, page)
			round(holder, 8)
			if o.Accent then
				gradient(holder, "seq", 0)
			elseif not o.Danger then
				outline(holder, T.Stroke, 1, 0.5)
			end
			local b = new("TextButton", {
				Text = o.Name, Font = FONTB, TextSize = 13,
				TextColor3 = o.Accent and T.Bg or T.Text,
				BackgroundTransparency = 1, AutoButtonColor = false,
				Size = UDim2.fromScale(1, 1),
			}, holder)
			b.MouseEnter:Connect(function() tween(holder, 0.15, {BackgroundColor3 = hoverC}) end)
			b.MouseLeave:Connect(function() tween(holder, 0.15, {BackgroundColor3 = baseC}) end)
			b.MouseButton1Down:Connect(function() tween(holder, 0.08, {BackgroundColor3 = pressC}) end)
			b.MouseButton1Up:Connect(function() tween(holder, 0.12, {BackgroundColor3 = hoverC}) end)
			b.MouseButton1Click:Connect(function()
				if o.Callback then safe(o.Callback) end
			end)
			return b
		end

		function Tab:CreateActionRow(o)
			local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = nextOrder() }, page)
			local layout = new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
			local buttons = {}
			for i, item in ipairs(o or {}) do
				local bg = item.Danger and T.Danger or T.Panel
				local btn = new("TextButton", { Size = UDim2.new(1 / #o, -((#o - 1) * 6 / #o), 1, 0), BackgroundColor3 = bg, BorderSizePixel = 0, Text = item.Text or "Aksi", TextColor3 = T.Text, Font = FONTB, TextSize = 11, AutoButtonColor = true, LayoutOrder = i }, holder)
				round(btn, 7)
				if not item.Danger then outline(btn, T.Stroke, 1, 0.5) end
				btn.MouseButton1Click:Connect(function() if item.Callback then safe(item.Callback) end end)
				table.insert(buttons, btn)
			end
			return holder, buttons
		end

		function Tab:CreateToggle(o)
			local state = false
			local f = new("Frame", {
				Size = UDim2.new(1, 0, 0, 40),
				BackgroundColor3 = T.Panel, BorderSizePixel = 0,
				LayoutOrder = nextOrder(),
			}, page)
			round(f, 8)
			outline(f, T.Stroke, 1, 0.5)
			new("TextLabel", {
				Text = o.Name, Font = FONT, TextSize = 13, TextColor3 = T.Text,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -70, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, f)
			local track = new("Frame", {
				Size = UDim2.fromOffset(38, 20), Position = UDim2.new(1, -50, 0.5, -10),
				BackgroundColor3 = T.Track, BorderSizePixel = 0,
			}, f)
			round(track, 10)
			local knob = new("Frame", {
				Size = UDim2.fromOffset(14, 14), Position = UDim2.new(0, 3, 0.5, -7),
				BackgroundColor3 = T.SubText, BorderSizePixel = 0,
			}, track)
			round(knob, 7)
			local click = new("TextButton", {
				Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
			}, f)

			local function visual(s)
				if s then
					tween(track, 0.2, {BackgroundColor3 = T.Accent})
					tween(knob, 0.2, {Position = UDim2.new(1, -17, 0.5, -7), BackgroundColor3 = T.Bg})
				else
					tween(track, 0.2, {BackgroundColor3 = T.Track})
					tween(knob, 0.2, {Position = UDim2.new(0, 3, 0.5, -7), BackgroundColor3 = T.SubText})
				end
			end
			table.insert(themeCallbacks, function()
				if state then track.BackgroundColor3 = T.Accent end
			end)

			local obj = {}
			function obj:Get() return state end
			function obj:Set(s, silent, quiet)
				state = s
				visual(s)
				if silent then return end
				local failed, msg = false, nil
				if o.Callback then
					local ok, res, m = pcall(o.Callback, s)
					if not ok then
						warn("[MekiHub] " .. tostring(res))
						failed, msg = true, "Terjadi error (cek console)"
					elseif res == false then
						failed, msg = true, m
					end
				end
				if failed then
					state = false
					visual(false)
					if not quiet then Window:Notify(o.Name, msg or "Gagal diaktifkan", 2, "error") end
				elseif not o.Silent and not quiet then
					Window:Notify(o.Name, s and "Aktif" or "Nonaktif", 1.5, s and "success" or nil)
				end
			end

			f.MouseEnter:Connect(function() tween(f, 0.15, {BackgroundColor3 = T.PanelHover}) end)
			f.MouseLeave:Connect(function() tween(f, 0.15, {BackgroundColor3 = T.Panel}) end)
			click.MouseButton1Click:Connect(function() obj:Set(not state) end)

			if o.ResetOnRespawn then table.insert(toggles, obj) end
			if o.Flag then
				flags[o.Flag] = {
					kind = "toggle",
					get = function() return state end,
					set = function(v)
						v = v and true or false
						if state ~= v then obj:Set(v, false, true) end
					end,
				}
			end
			if o.Default then
				state = true
				visual(true)
				if o.Callback then safe(o.Callback, true) end
			end
			return obj
		end

		function Tab:CreateSlider(o)
			local min, max, step = o.Min or 0, o.Max or 100, o.Step or 1
			local value = math.clamp(o.Default or min, min, max)
			local f = new("Frame", {
				Size = UDim2.new(1, 0, 0, 54),
				BackgroundColor3 = T.Panel, BorderSizePixel = 0,
				LayoutOrder = nextOrder(),
			}, page)
			round(f, 8)
			outline(f, T.Stroke, 1, 0.5)
			new("TextLabel", {
				Text = o.Name, Font = FONT, TextSize = 13, TextColor3 = T.Text,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -90, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Left,
			}, f)
			local valLbl = new("TextLabel", {
				Font = FONTB, TextSize = 12, TextColor3 = T.Accent,
				BackgroundTransparency = 1,
				Position = UDim2.new(1, -82, 0, 8), Size = UDim2.fromOffset(70, 18),
				TextXAlignment = Enum.TextXAlignment.Right,
			}, f)
			local track = new("Frame", {
				Size = UDim2.new(1, -24, 0, 6), Position = UDim2.new(0, 12, 0, 38),
				BackgroundColor3 = T.Track, BorderSizePixel = 0,
			}, f)
			round(track, 3)
			local fill = new("Frame", {
				Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
			}, track)
			round(fill, 3)
			gradient(fill, "seq", 0)
			local knob = new("Frame", {
				Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = T.Text, BorderSizePixel = 0,
			}, track)
			round(knob, 7)
			local hit = new("TextButton", {
				Text = "", BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 28),
			}, f)

			local function render()
				local pct = (value - min) / (max - min)
				fill.Size = UDim2.fromScale(pct, 1)
				knob.Position = UDim2.fromScale(pct, 0.5)
				valLbl.Text = tostring(value) .. (o.Suffix or "")
			end
			render()

			local function setFromX(x)
				local pct = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
				local v = min + (max - min) * pct
				v = math.floor((v - min) / step + 0.5) * step + min
				v = math.clamp(v, min, max)
				v = tonumber(string.format("%.3f", v))
				if v ~= value then
					value = v
					render()
					if o.Callback then safe(o.Callback, value) end
				end
			end

			local dragging = false
			hit.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragging = true
					page.ScrollingEnabled = false
					setFromX(input.Position.X)
				end
			end)
			addCleanup(UserInputService.InputChanged:Connect(function(input)
				if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
					setFromX(input.Position.X)
				end
			end))
			addCleanup(UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					if dragging then
						dragging = false
						page.ScrollingEnabled = true
					end
				end
			end))

			if o.Callback then safe(o.Callback, value) end
			local obj = {}
			function obj:Get() return value end
			function obj:Set(v)
				value = math.clamp(tonumber(v) or value, min, max)
				render()
				if o.Callback then safe(o.Callback, value) end
			end
			if o.Flag then
				flags[o.Flag] = { kind = "slider", get = function() return value end, set = function(v) obj:Set(v) end }
			end
			return obj
		end

		function Tab:CreateDropdown(o)
			local selected = o.Default
			local open = false
			local card = new("Frame", {
				Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = T.Panel, BorderSizePixel = 0,
				ClipsDescendants = true,
				LayoutOrder = nextOrder(),
			}, page)
			round(card, 8)
			outline(card, T.Stroke, 1, 0.5)
			new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, card)

			local header = new("TextButton", {
				Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 0,
			}, card)
			local valueLbl = new("TextLabel", {
				Text = selected or o.Placeholder or "Pilih...", Font = FONTB, TextSize = 13,
				TextColor3 = selected and T.Text or T.SubText,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -50, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
			}, header)
			local arrow = new("TextLabel", {
				Text = ">", Font = FONTB, TextSize = 16, TextColor3 = T.SubText,
				BackgroundTransparency = 1, Rotation = 90,
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -22, 0.5, 0),
				Size = UDim2.fromOffset(20, 20),
			}, header)

			local list = new("Frame", {
				Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1, Visible = false, LayoutOrder = 1,
			}, card)
			new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)
			new("UIPadding", {
				PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 8),
				PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
			}, list)

			local items = {}
			local function refresh()
				valueLbl.Text = selected or o.Placeholder or "Pilih..."
				valueLbl.TextColor3 = selected and T.Text or T.SubText
				for name, it in pairs(items) do
					local on = (name == selected)
					it.dot.BackgroundColor3 = on and T.Accent or T.Track
					it.lbl.TextColor3 = on and T.Text or T.SubText
					it.btn.BackgroundColor3 = on and T.PanelLite or T.Panel
				end
			end
			table.insert(themeCallbacks, refresh)

			local function setOpen(v)
				open = v
				list.Visible = v
				tween(arrow, 0.15, { Rotation = v and -90 or 90 })
			end
			header.MouseButton1Click:Connect(function() setOpen(not open) end)

			local function choose(name)
				selected = name
				refresh()
				setOpen(false)
				if o.Callback then safe(o.Callback, name) end
			end

			for i, name in ipairs(o.Options) do
				local locked = o.DisabledOptions and o.DisabledOptions[name] == true
				local btn = new("TextButton", {
					Text = "", AutoButtonColor = false, BorderSizePixel = 0,
					BackgroundColor3 = T.Panel,
					Size = UDim2.new(1, 0, 0, 34), LayoutOrder = i,
				}, list)
				round(btn, 6)
				local dot = new("Frame", {
					Size = UDim2.fromOffset(10, 10), Position = UDim2.new(0, 10, 0.5, -5),
					BackgroundColor3 = locked and T.Stroke or T.Track, BorderSizePixel = 0,
				}, btn)
				round(dot, 5)
				local lbl = new("TextLabel", {
					Text = (locked and "🔒 " or "") .. name, Font = FONTB, TextSize = 13,
					TextColor3 = locked and T.SubText or T.Text,
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(30, 0), Size = UDim2.new(1, -36, 1, 0),
					TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
				}, btn)
				items[name] = { btn = btn, dot = dot, lbl = lbl }
				btn.MouseButton1Click:Connect(function()
					if locked then
						if Window and Window.Notify then Window:Notify("Auto Summit", "🔒 Map ini terkunci — bukan map yang sedang dimainkan", 2, "error") end
						return
					end
					choose(name)
				end)
			end
			refresh()

			local obj = {}
			function obj:Get() return selected end
			function obj:Set(name)
				if items[name] then choose(name) end
			end
			if o.Flag then
				flags[o.Flag] = { kind = "select", get = function() return selected end, set = function(v) obj:Set(v) end }
			end
			return obj
		end

		function Tab:CreateInput(o)
			local f = new("Frame", {
				Size = UDim2.new(1, 0, 0, 40),
				BackgroundColor3 = T.Panel, BorderSizePixel = 0,
				LayoutOrder = nextOrder(),
			}, page)
			round(f, 8)
			outline(f, T.Stroke, 1, 0.5)
			local box = new("TextBox", {
				Text = "", PlaceholderText = o.Placeholder or "", PlaceholderColor3 = T.SubText,
				Font = FONT, TextSize = 13, TextColor3 = T.Text,
				BackgroundTransparency = 1, ClearTextOnFocus = false,
				Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
			}, f)
			box:GetPropertyChangedSignal("Text"):Connect(function()
				if o.Callback then safe(o.Callback, box.Text) end
			end)
			return box
		end

		function Tab:CreateColorRow(o)
			local selected = o.Default
			local card = new("Frame", {
				Size = UDim2.new(1, 0, 0, 78),
				BackgroundColor3 = T.Panel, BorderSizePixel = 0,
				LayoutOrder = nextOrder(),
			}, page)
			round(card, 8)
			outline(card, T.Stroke, 1, 0.5)
			new("TextLabel", {
				Text = o.Name, Font = FONT, TextSize = 13, TextColor3 = T.Text,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Left,
			}, card)
			local row = new("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, 36), Size = UDim2.new(1, -24, 0, 32),
			}, card)
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 10),
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}, row)
			local rings = {}
			local function refresh()
				for name, ring in pairs(rings) do
					ring.Transparency = (name == selected) and 0 or 1
				end
			end
			local function choose(name, color)
				selected = name
				refresh()
				if o.Callback then safe(o.Callback, name, color) end
			end
			for _, c in ipairs(o.Colors) do
				local b = new("TextButton", {
					Text = "", AutoButtonColor = false, BorderSizePixel = 0,
					Size = UDim2.fromOffset(28, 28),
				}, row)
				b.BackgroundColor3 = c[2]
				round(b, 14)
				rings[c[1]] = new("UIStroke", {
					Color = Color3.new(1, 1, 1), Thickness = 2,
					Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}, b)
				b.MouseButton1Click:Connect(function() choose(c[1], c[2]) end)
			end
			refresh()
			local obj = {}
			function obj:Get() return selected end
			function obj:Set(name)
				for _, c in ipairs(o.Colors) do
					if c[1] == name then choose(c[1], c[2]) return end
				end
			end
			if o.Flag then
				flags[o.Flag] = { kind = "color", get = function() return selected end, set = function(v) obj:Set(v) end }
			end
			return obj
		end

		return Tab
	end

	local drag = {active = false}
	local function beginWindowDrag(input, scrollPage)
		if drag.active then return end
		local ut = input.UserInputType
		if ut ~= Enum.UserInputType.MouseButton1 and ut ~= Enum.UserInputType.Touch then return end
		drag.active = true
		drag.input = input
		drag.start = input.Position
		drag.startPos = root.Position
		drag.scrollPage = scrollPage

		drag.decided = not (ut == Enum.UserInputType.Touch and scrollPage ~= nil)
	end

	addCleanup(UserInputService.InputChanged:Connect(function(input)
		if not drag.active then return end
		local isMouseMove = input.UserInputType == Enum.UserInputType.MouseMovement
		local isTouchMove = input.UserInputType == Enum.UserInputType.Touch and input == drag.input
		if not (isMouseMove or isTouchMove) then return end
		local delta = input.Position - drag.start
		if not drag.decided then
			if delta.Magnitude < 8 then return end
			if math.abs(delta.Y) > math.abs(delta.X) then
				drag.active = false
				return
			end
			drag.decided = true
			if drag.scrollPage then drag.scrollPage.ScrollingEnabled = false end
		end
		root.Position = UDim2.new(
			drag.startPos.X.Scale, drag.startPos.X.Offset + delta.X,
			drag.startPos.Y.Scale, drag.startPos.Y.Offset + delta.Y
		)
	end))

	addCleanup(UserInputService.InputEnded:Connect(function(input)
		if not drag.active then return end
		local ut = input.UserInputType
		if ut == Enum.UserInputType.MouseButton1 or (ut == Enum.UserInputType.Touch and input == drag.input) then
			drag.active = false
			if drag.scrollPage then drag.scrollPage.ScrollingEnabled = true end
		end
	end))

	local function hookDrag(d)
		if not d.Parent then return end
		if not d:IsA("GuiObject") then return end
		if d:IsA("GuiButton") or d:IsA("TextBox") then return end
		if d.Name == "Shadow" then return end
		if d:FindFirstAncestorWhichIsA("GuiButton") then return end
		local sf = d:IsA("ScrollingFrame") and d or d:FindFirstAncestorWhichIsA("ScrollingFrame")
		d.InputBegan:Connect(function(input) beginWindowDrag(input, sf) end)
	end
	for _, d in ipairs(root:GetDescendants()) do hookDrag(d) end
	root.DescendantAdded:Connect(function(d) task.defer(hookDrag, d) end)

	return Window
end

local KEY_RAW_URL = "https://raw.githubusercontent.com/mekinjir/keymekihub/refs/heads/main/key-meki-hub.text"
local LINKVERTISE_URL = "https://discord.gg/j8FeNBVkP"
local KEY_FILE = "meki_hub_key.dat"

-- Ambil key terbaru dari GitHub Raw. Tidak ada key tetap yang ditanam di script.
local function fetchRemoteKey()
    local ok, body = pcall(function()
        if type(game.HttpGet) == "function" then
            return game:HttpGet(KEY_RAW_URL)
        end
        local req = (syn and syn.request) or http_request or request
        if type(req) == "function" then
            local response = req({Url = KEY_RAW_URL, Method = "GET"})
            if response and (response.StatusCode == 200 or response.Status == 200) then
                return response.Body or response.body
            end
        end
        error("HTTP request tidak tersedia")
    end)
    if not ok or type(body) ~= "string" then return nil end
    body = body:gsub("^%s+", ""):gsub("%s+$", "")
    if body == "" then return nil end
    return body
end

local function keySaved()
    if type(readfile) ~= "function" or type(isfile) ~= "function" then return false end
    local remoteKey = fetchRemoteKey()
    if not remoteKey then return false end
    local ok, value = pcall(function() if isfile(KEY_FILE) then return readfile(KEY_FILE) end end)
    return ok and type(value) == "string" and value:gsub("^%s+", ""):gsub("%s+$", "") == remoteKey
end
local function saveKey(value)
    if type(writefile) == "function" then pcall(writefile, KEY_FILE, value) end
end

local loadingScreen, loadBox, loadSpin
do
loadingScreen = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = T.Bg, BackgroundTransparency = 0.1,
	ZIndex = 100,
}, gui)

loadBox = new("Frame", {
	Size = UDim2.fromOffset(300, 220),
	Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = T.Panel, BackgroundTransparency = 0.2,
}, loadingScreen)
round(loadBox, 16)
local loadStroke = outline(loadBox, Color3.new(1, 1, 1), 1.5, 0.3)
local loadStrokeGrad = gradient(loadStroke, "loop", 0)
loadSpin = RunService.Heartbeat:Connect(function(dt)
	loadStrokeGrad.Rotation = (loadStrokeGrad.Rotation + dt * 120) % 360
end)
addCleanup(loadSpin)

local loadAvatar = new("ImageLabel", {
	Size = UDim2.fromOffset(70, 70),
	Position = UDim2.fromScale(0.5, 0.25), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = T.Bg,
}, loadBox)
round(loadAvatar, 35)
local loadAvStroke = outline(loadAvatar, Color3.new(1, 1, 1), 2, 0)
gradient(loadAvStroke, "seq", 45)

task.spawn(function()
	local ok, img = pcall(function()
		return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
	end)
	if ok and loadAvatar.Parent then loadAvatar.Image = img end
end)

new("TextLabel", {
	Text = "MEKI HUB", Font = FONTB, TextSize = 20, TextColor3 = T.Text,
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0.4, 0),
}, loadBox)
new("TextLabel", {
	Text = "Welcome back, " .. player.DisplayName, Font = FONT, TextSize = 13, TextColor3 = T.SubText,
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0.55, 0),
}, loadBox)
local statusLbl = new("TextLabel", {
	Text = "Loading...", Font = FONT, TextSize = 11, TextColor3 = T.Accent,
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0.7, 0),
}, loadBox)

local barBg = new("Frame", {
	Size = UDim2.new(0.8, 0, 0, 6),
	Position = UDim2.new(0.5, 0, 0.85, 0), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = T.PanelLite,
}, loadBox)
round(barBg, 3)
local barFill = new("Frame", {
	Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1),
}, barBg)
round(barFill, 3)
gradient(barFill, "seq", 0)
TweenService:Create(barFill, TweenInfo.new(3, Enum.EasingStyle.Linear), {Size = UDim2.new(1, 0, 1, 0)}):Play()

task.spawn(function()
	local steps = {"Memuat modul...", "Menyiapkan UI...", "Hampir selesai..."}
	for _, s in ipairs(steps) do
		task.wait(0.9)
		if isCleaningUp or not statusLbl.Parent then return end
		statusLbl.Text = s
	end
end)

end
local Window = Lib:CreateWindow({
	Title = "MEKI HUB",
	Badge = "V3 FREEMIUM",
})

local toggleCircle = new("Frame", {
	Size = UDim2.fromOffset(52, 52),
	Position = UDim2.new(0, 20, 0.5, -26),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0, Visible = false,
}, gui)
round(toggleCircle, 14)
outline(toggleCircle, Color3.new(1, 1, 1), 1.5, 0.35)

local TOGGLE_IMAGE_ID = "99762767463256"
local togglePhoto = new("ImageLabel", {
	Name = "TogglePhoto", Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1, BorderSizePixel = 0,
	Image = "rbxassetid://" .. TOGGLE_IMAGE_ID, ScaleType = Enum.ScaleType.Crop,
}, toggleCircle)
round(togglePhoto, 14)
local toggleHit = new("TextButton", {
	Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Active = true,
}, toggleCircle)
local isDraggingCircle = setupDrag(toggleCircle, toggleHit)
toggleHit.MouseButton1Click:Connect(function()
	if not isDraggingCircle() then Window:Toggle() end
end)

addCleanup(UserInputService.InputBegan:Connect(function(input, gp)
	if gp or isCleaningUp then return end
	if input.KeyCode == Enum.KeyCode.RightShift and toggleCircle.Visible then
		Window:Toggle()
	end
end))

task.spawn(function()
	task.wait(3)
	if isCleaningUp then return end
	local info = TweenInfo.new(0.5)
	TweenService:Create(loadingScreen, info, {BackgroundTransparency = 1}):Play()
	TweenService:Create(loadBox, info, {BackgroundTransparency = 1}):Play()
	for _, v in pairs(loadBox:GetDescendants()) do
		if v:IsA("UIStroke") then
			TweenService:Create(v, info, {Transparency = 1}):Play()
		elseif v:IsA("Frame") then
			TweenService:Create(v, info, {BackgroundTransparency = 1}):Play()
		elseif v:IsA("TextLabel") then
			TweenService:Create(v, info, {BackgroundTransparency = 1, TextTransparency = 1}):Play()
		elseif v:IsA("ImageLabel") then
			TweenService:Create(v, info, {BackgroundTransparency = 1, ImageTransparency = 1}):Play()
		end
	end
	task.wait(0.6)
	if isCleaningUp then return end
	pcall(function() loadSpin:Disconnect() end)
	loadingScreen:Destroy()

    if not keySaved() then
        local gate = new("Frame", {Size=UDim2.fromScale(1,1), BackgroundColor3=T.Bg, BackgroundTransparency=0.04, ZIndex=300}, gui)

        local glowTop = new("Frame", {Size=UDim2.fromOffset(230,230), Position=UDim2.new(0, -90, 0, -95), BackgroundColor3=T.Accent, BackgroundTransparency=0.88, ZIndex=300}, gate)
        round(glowTop,115)
        local glowBottom = new("Frame", {Size=UDim2.fromOffset(190,190), Position=UDim2.new(1, -80, 1, -75), BackgroundColor3=T.Accent2 or T.Accent, BackgroundTransparency=0.9, ZIndex=300}, gate)
        round(glowBottom,95)

        local card = new("Frame", {Size=UDim2.fromOffset(360,246), Position=UDim2.fromScale(0.5,0.5), AnchorPoint=Vector2.new(0.5,0.5), BackgroundColor3=T.Panel, ZIndex=301}, gate)
        round(card,16); outline(card,T.Accent,1.2,0.2)

        local side = new("Frame", {Size=UDim2.new(0,96,1,0), BackgroundColor3=T.Bg, BorderSizePixel=0, ZIndex=302}, card)
        round(side,15)
        local sideCover = new("Frame", {Size=UDim2.new(0,18,1,0), Position=UDim2.new(1,-18,0,0), BackgroundColor3=T.Bg, BorderSizePixel=0, ZIndex=302}, side)
        gradient(side,"seq",45)
        local keyLogo = new("ImageLabel", {Name="KeyScreenLogo", Image="rbxassetid://99762767463256", ScaleType=Enum.ScaleType.Crop, BackgroundColor3=T.Accent, BorderSizePixel=0, Position=UDim2.fromOffset(21,35), Size=UDim2.fromOffset(54,54), ZIndex=303}, side)
        round(keyLogo, 0)
        new("TextLabel", {Text="MEKI", Font=FONTB, TextSize=15, TextColor3=T.Text, BackgroundTransparency=1, Position=UDim2.fromOffset(8,103), Size=UDim2.new(1,-16,0,22), TextXAlignment=Enum.TextXAlignment.Center, ZIndex=303}, side)
        new("TextLabel", {Text="HUB V3", Font=FONT, TextSize=10, TextColor3=T.SubText, BackgroundTransparency=1, Position=UDim2.fromOffset(8,125), Size=UDim2.new(1,-16,0,18), TextXAlignment=Enum.TextXAlignment.Center, ZIndex=303}, side)
        local sideLine = new("Frame", {Size=UDim2.fromOffset(38,2), Position=UDim2.new(0.5,-19,0,157), BackgroundColor3=T.Accent, BorderSizePixel=0, ZIndex=303}, side)
        new("TextLabel", {Text="ACCESS\nPROTECTED", Font=FONTB, TextSize=8, TextColor3=T.SubText, BackgroundTransparency=1, Position=UDim2.fromOffset(5,169), Size=UDim2.new(1,-10,0,30), TextXAlignment=Enum.TextXAlignment.Center, ZIndex=303}, side)

        new("TextLabel", {Text="WELCOME BACK", Font=FONTB, TextSize=9, TextColor3=T.Accent, BackgroundTransparency=1, Position=UDim2.fromOffset(112,20), Size=UDim2.new(1,-126,0,16), TextXAlignment=Enum.TextXAlignment.Left, ZIndex=303}, card)
        new("TextLabel", {Text="MEKI HUB ACCESS", Font=FONTB, TextSize=17, TextColor3=T.Text, BackgroundTransparency=1, Position=UDim2.fromOffset(112,38), Size=UDim2.new(1,-126,0,26), TextXAlignment=Enum.TextXAlignment.Left, ZIndex=303}, card)
        new("TextLabel", {Text="Masukkan access key untuk lanjut.", Font=FONT, TextSize=10, TextColor3=T.SubText, BackgroundTransparency=1, Position=UDim2.fromOffset(112,65), Size=UDim2.new(1,-126,0,18), TextXAlignment=Enum.TextXAlignment.Left, ZIndex=303}, card)
        local box = new("TextBox", {Text="", PlaceholderText="ENTER YOUR KEY", ClearTextOnFocus=false, Font=FONTB, TextSize=12, TextColor3=T.Text, PlaceholderColor3=T.SubText, BackgroundColor3=T.Track, BorderSizePixel=0, Position=UDim2.fromOffset(112,91), Size=UDim2.new(1,-128,0,36), ZIndex=303}, card)
        round(box,8); outline(box,T.Stroke,1,0.2); new("UIPadding",{PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10)},box)

        box:GetPropertyChangedSignal("Text"):Connect(function()
            local upperText = string.upper(box.Text)
            if box.Text ~= upperText then
                local cursor = box.CursorPosition
                box.Text = upperText
                box.CursorPosition = cursor
            end
        end)
        local status = new("TextLabel", {Text="●  WAITING FOR KEY", Font=FONTB, TextSize=9, TextColor3=T.SubText, BackgroundTransparency=1, Position=UDim2.fromOffset(112,132), Size=UDim2.new(1,-126,0,17), TextXAlignment=Enum.TextXAlignment.Left, ZIndex=303}, card)
        local submit = new("TextButton", {Text="SUMMIT KEY", Font=FONTB, TextSize=10, TextColor3=T.Bg, BackgroundColor3=T.Accent, BorderSizePixel=0, Position=UDim2.fromOffset(112,160), Size=UDim2.new(1,-128,0,32), ZIndex=303}, card)
        round(submit,8); gradient(submit,"seq",0)
        local get = new("TextButton", {Text="GET KEY  ↗", Font=FONTB, TextSize=10, TextColor3=T.Text, BackgroundColor3=T.PanelLite, BorderSizePixel=0, Position=UDim2.fromOffset(112,199), Size=UDim2.new(1,-128,0,29), ZIndex=303}, card)
        round(get,8); outline(get,T.Stroke,1,0.35)

        local function openLink()
            pcall(function() if setclipboard then setclipboard(LINKVERTISE_URL) end end)
            pcall(function() game:GetService("GuiService"):OpenBrowserWindow(LINKVERTISE_URL) end)
            status.Text = "●  LINK COPIED / OPENING..."
            status.TextColor3 = T.Success
        end
        get.MouseButton1Click:Connect(openLink)
        submit.MouseButton1Click:Connect(function()
            status.Text = "●  CHECKING GITHUB KEY..."
            status.TextColor3 = T.Accent
            local remoteKey = fetchRemoteKey()
            if not remoteKey then
                status.Text = "●  GITHUB KEY UNAVAILABLE. TRY AGAIN."
                status.TextColor3 = T.Danger
                return
            end
            if box.Text:gsub("^%s+", ""):gsub("%s+$", "") == remoteKey then
                saveKey(remoteKey)
                status.Text = "●  KEY VERIFIED. LOADING HUB..."
                status.TextColor3 = T.Success
                task.wait(0.35)
                if gate.Parent then gate:Destroy() end
                Window:SetVisible(true); toggleCircle.Visible = true
                Window:Notify("Meki Hub", "Key berhasil diverifikasi", 3, "success")
            else
                status.Text = "●  INVALID KEY. TRY AGAIN."
                status.TextColor3 = T.Danger
                box.Text = ""
            end
        end)
    else
        Window:SetVisible(true)
        toggleCircle.Visible = true
        Window:Notify("Meki Hub", "Key tersimpan, selamat datang " .. player.DisplayName, 3, "success")
    end
end)

local flySpeed = 150
local walkSpeed = 50
local speedEnabled = false
local defaultWalkSpeed = 16
local isFlying = false
local flyBV, flyBG, flyConn
local isNoclip = false
local noclipConn
local isInfJump = false
local freezeTrack = nil

local function getMoveVector()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.MoveDirection.Magnitude == 0 then return Vector3.new(0, 0, 0) end
	local rel = workspace.CurrentCamera.CFrame:VectorToObjectSpace(hum.MoveDirection)
	local v = Vector3.new(rel.X, 0, rel.Z)
	return v.Magnitude > 0 and v.Unit or v
end

local function stopFly()
	if not isFlying then return end
	isFlying = false
	if flyBV then flyBV:Destroy() flyBV = nil end
	if flyBG then flyBG:Destroy() flyBG = nil end
	if flyConn then flyConn:Disconnect() flyConn = nil end

	local char = player.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = speedEnabled and walkSpeed or defaultWalkSpeed end
		local animate = char:FindFirstChild("Animate")
		if animate then animate.Disabled = false end
	end
	if freezeTrack then
		pcall(function() freezeTrack:Stop() end)
		freezeTrack = nil
	end
end

local function toggleFly(state)
	if not state then stopFly(); return end

	local char = player.Character
	local hrp = getHRP()
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return false, "Karakter belum siap" end

	isFlying = true
	if not speedEnabled then defaultWalkSpeed = hum.WalkSpeed end
	hum.WalkSpeed = 0

	flyBV = Instance.new("BodyVelocity")
	flyBV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	flyBV.Velocity = Vector3.new(0, 0, 0)
	flyBV.Parent = hrp

	flyBG = Instance.new("BodyGyro")
	flyBG.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
	flyBG.P = 10000
	flyBG.D = 100
	flyBG.Parent = hrp

	local animate = char:FindFirstChild("Animate")
	if animate then animate.Disabled = true end
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
			pcall(function() t:Stop(0) end)
		end
		pcall(function()
			local id
			local idle = animate and animate:FindFirstChild("idle")
			local a1 = idle and idle:FindFirstChild("Animation1")
			if a1 then id = a1.AnimationId end
			id = id or (hum.RigType == Enum.HumanoidRigType.R15 and "rbxassetid://507766666" or "rbxassetid://180435571")
			local freezeAnim = Instance.new("Animation")
			freezeAnim.AnimationId = id
			freezeTrack = animator:LoadAnimation(freezeAnim)
			freezeTrack.Priority = Enum.AnimationPriority.Action4
			freezeTrack:Play(0)
			freezeTrack:AdjustSpeed(0)
		end)
	end

	if flyConn then flyConn:Disconnect() end
	flyConn = RunService.RenderStepped:Connect(function()
		if not isFlying or not hrp.Parent then return end
		local cam = workspace.CurrentCamera
		local moveVec = getMoveVector()

		flyBV.Velocity = (cam.CFrame.LookVector * -moveVec.Z * flySpeed) + (cam.CFrame.RightVector * moveVec.X * flySpeed)

		local _, camYaw, _ = cam.CFrame:ToEulerAnglesYXZ()
		flyBG.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, camYaw, 0)
	end)
end

local function toggleNoclip(state)
	isNoclip = state
	if noclipConn then noclipConn:Disconnect() noclipConn = nil end
	if isNoclip then
		noclipConn = RunService.Stepped:Connect(function()
			if player.Character then
				for _, v in pairs(player.Character:GetDescendants()) do
					if v:IsA("BasePart") and v.CanCollide then v.CanCollide = false end
				end
			end
		end)
	else
		if player.Character then
			for _, v in pairs(player.Character:GetDescendants()) do
				if v:IsA("BasePart") then v.CanCollide = true end
			end
		end
	end
end

addCleanup(RunService.Heartbeat:Connect(function()
	if not isInfJump then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = getHRP()
	if not hum or not hrp then return end

	local holding = hum.Jump
	if not UserInputService:GetFocusedTextBox() and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		holding = true
	end

	if holding then
		local v = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(v.X, 50, v.Z)
	end
end))

local antiAfkConn
local function setAntiAfk(on)
	if antiAfkConn then antiAfkConn:Disconnect() antiAfkConn = nil end
	if on then
		antiAfkConn = player.Idled:Connect(function()
			pcall(function()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new())
			end)
		end)
	end
end

-- Tidak memaksa Humanoid ke GettingUp setiap frame saat script dimuat.
-- Pemaksaan state tersebut dapat mengganggu physics/landing karakter.

addCleanup(RunService.Heartbeat:Connect(function()
	if not speedEnabled or isFlying then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.WalkSpeed ~= walkSpeed then hum.WalkSpeed = walkSpeed end
end))

do
local DT = Window:CreateTab("Discord", "discord")
DT:CreateSection("MEKI COMMUNITY")
DT:CreateLabel("Join komunitas resmi MEKI HUB untuk mendapatkan informasi update, berbagi pengalaman, dan ngobrol bareng pengguna lainnya.")
DT:CreateLabel("Tekan tombol di bawah untuk menyalin undangan Discord. Link tidak ditampilkan di menu.")
local discordStatus = DT:CreateLabel("Invite siap disalin.")
DT:CreateButton({
    Name = "COPY DISCORD INVITE",
    Accent = true,
    Callback = function()
        local copied = false
        if type(setclipboard) == "function" then
            copied = pcall(setclipboard, "https://discord.gg/j8FeNBVkP")
        elseif type(toclipboard) == "function" then
            copied = pcall(toclipboard, "https://discord.gg/j8FeNBVkP")
        end
        discordStatus.Text = copied and "Invite Discord berhasil disalin!" or "Clipboard tidak didukung executor ini."
    end,
})
end

do -- Home: profil, map/server tersusun rapi, dan waktu berjalan
local HM = Window:CreateTab("Home", "home")
local homeStartedAt = os.clock()

-- Kartu profil: username dan ID dirapatkan dalam dua baris; umur akun tepat di bawah kartu.
local profileCard = new("Frame", {
    Size = UDim2.new(1, 0, 0, 96),
    BackgroundColor3 = T.Panel, BorderSizePixel = 0,
    LayoutOrder = HM:NextOrder(),
}, HM.Page)
round(profileCard, 12)
gradient(profileCard, "card", 20)
outline(profileCard, T.Stroke, 1, 0.4)

local homeAvatar = new("ImageLabel", {
    Size = UDim2.fromOffset(62, 62), Position = UDim2.fromOffset(13, 13),
    BackgroundColor3 = T.PanelLite, BorderSizePixel = 0,
    ScaleType = Enum.ScaleType.Crop,
}, profileCard)
round(homeAvatar, 31)
local homeAvStroke = outline(homeAvatar, T.Accent, 2, 0)
task.spawn(function()
    local ok, img = pcall(function()
        return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
    end)
    if ok and homeAvatar.Parent then homeAvatar.Image = img end
end)

new("TextLabel", {
    Text = player.DisplayName, Font = FONTB, TextSize = 16, TextColor3 = T.Text,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(88, 15), Size = UDim2.new(1, -102, 0, 23),
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
}, profileCard)
new("TextLabel", {
    Text = "@" .. player.Name, Font = FONT, TextSize = 10, TextColor3 = T.SubText,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(88, 42), Size = UDim2.new(1, -102, 0, 17),
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.None,
}, profileCard)
new("TextLabel", {
    Text = "ID: " .. tostring(player.UserId), Font = FONTB, TextSize = 10, TextColor3 = T.Accent,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(88, 62), Size = UDim2.new(1, -102, 0, 17),
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.None,
}, profileCard)

HM:CreateLabel("Umur Akun: " .. tostring(player.AccountAge) .. " hari")

HM:CreateSection("INFORMASI MAP & SERVER")
local function homeInfoRow(key, initialValue)
    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, 46),
        BackgroundColor3 = T.Panel, BorderSizePixel = 0,
        LayoutOrder = HM:NextOrder(),
    }, HM.Page)
    round(card, 9)
    outline(card, T.Stroke, 1, 0.65)
    new("TextLabel", {
        Text = key, Font = FONTB, TextSize = 10, TextColor3 = T.SubText,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12, 5), Size = UDim2.new(1, -24, 0, 13),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
    return new("TextLabel", {
        Text = initialValue or "-", Font = FONTB, TextSize = 12, TextColor3 = T.Text,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12, 20), Size = UDim2.new(1, -24, 0, 19),
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    }, card)
end

-- Urutan informasi Home mengikuti susunan yang diminta.
local mapNameLabel = homeInfoRow("NAMA MAP :", "Memuat nama map...")
local mapIdLabel = homeInfoRow("ID MAP :", tostring(game.PlaceId))
local serverPlayersLabel = homeInfoRow("PEMAIN DI SERVER :", tostring(#Players:GetPlayers()) .. "/" .. tostring(Players.MaxPlayers))
local serverIdLabel = homeInfoRow("ID SERVER :", game.JobId ~= "" and game.JobId or "Studio / Tidak tersedia")
local runTimeLabel = homeInfoRow("SCRIPT BERJALAN :", "00:00:00")

task.spawn(function()
    local ok, product = pcall(function()
        return MarketplaceService:GetProductInfo(game.PlaceId)
    end)
    if ok and product and product.Name then
        mapNameLabel.Text = tostring(product.Name)
    else
        mapNameLabel.Text = "Nama map tidak tersedia"
    end
end)

local function formatHomeDuration(seconds)
    seconds = math.max(0, math.floor(seconds))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

task.spawn(function()
    while not isCleaningUp and runTimeLabel.Parent do
        runTimeLabel.Text = formatHomeDuration(os.clock() - homeStartedAt)
        serverPlayersLabel.Text = tostring(#Players:GetPlayers()) .. "/" .. tostring(Players.MaxPlayers)
        task.wait(1)
    end
end)
end -- Home

local MAIN
if game.PlaceId == 131312206945521 or game.PlaceId == 118517641508250 then
    MAIN = Window:CreateTab("Main", "gamepad")
end

do -- Blok fitur Main/Fishing untuk menjaga batas local Luau.
if game.PlaceId == 131312206945521 then
MAIN:CreateSection("Teleport Lokasi Mount Rehat")
local rehatSpots = {
    { name = "Jual Ikan", cf = { -6466.6591796875,1280.5760498046876,-9710.328125 } },
    { name = "Toko Perlengkapan", cf = { -6469.138671875,1280.5760498046876,-9653.7138671875 } },
    { name = "NPC Tukar Core", cf = { -6817.2890625,1283.597900390625,-9337.4443359375 } },
    { name = "Upgrade Rod", cf = { -7152.75146484375,1283.597900390625,-9353.412109375 } },
}
for _, spot in ipairs(rehatSpots) do spot.cframe = CFrame.new(spot.cf[1], spot.cf[2], spot.cf[3]) end
local selectedRehatSpot = rehatSpots[1]
MAIN:CreateDropdown({
    Options = { "Jual Ikan", "Toko Perlengkapan", "NPC Tukar Core", "Upgrade Rod" },
    Placeholder = "Pilih lokasi Mount Rehat...",
    Callback = function(name)
        for _, spot in ipairs(rehatSpots) do if spot.name == name then selectedRehatSpot = spot break end end
    end,
})
MAIN:CreateButton({ Name = "Teleport ke Lokasi Rehat", Accent = true, Callback = function()
    if game.PlaceId ~= 131312206945521 then
        Window:Notify("Teleport", "Fitur ini khusus Mount Rehat", 2, "error")
        return
    end
    local char = player.Character
    if char and selectedRehatSpot then
        char:PivotTo(selectedRehatSpot.cframe)
        local root = char:FindFirstChild("HumanoidRootPart")
        if root then root.AssemblyLinearVelocity = Vector3.zero end
        resetHumanoidState()
        Window:Notify("Teleport", "Menuju " .. selectedRehatSpot.name, 1.5, "success")
    end
end })
end -- Mount Rehat: teleport section

if game.PlaceId == 118517641508250 then
MAIN:CreateSection("Teleport Lokasi Soreya")
local soreyaSpots = {
    { name = "Spot Core", cf = { -9098.5166015625,1247.6292724609376,-6603.39892578125,0.1252012848854065,-5.0581160593310418e-8,0.9921313524246216,-1.0390964177986462e-7,1,6.409512565141995e-8,-0.9921313524246216,-1.1111680464637175e-7,0.1252012848854065 } },
    { name = "Spot Mancing", cf = { -8189.32861328125,1231.3775634765626,-6330.47412109375,-0.9817370772361755,-2.8695961162839014e-9,0.19024276733398438,3.735683318240035e-9,1,3.436164774939243e-8,-0.19024276733398438,3.44447919076174e-8,-0.9817370772361755 } },
    { name = "Toko Rod", cf = { -7089.5048828125, 1313.410400390625, -9694.5419921875, -0.10040967911481857, -8.173643095688021e-8, 0.9949461817741394, 5.4793833470512257e-8, 1, 8.76813857075831e-8, -0.9949461817741394, 6.33209751299546e-8, -0.10040967911481857 } },
    { name = "Jual Ikan", cf = { -7067.990234375, 1313.410400390625, -9581.337890625, -0.9992715716362, -1.5962214661158215e-8, 0.03816171735525131, -1.1940919364406e-8, 1, 1.056030214385828e-7, -0.03816171735525131, 1.0507041281471175e-7, -0.9992715716362 } },
    { name = "Base Camp", cf = { 469.4512939453125,444.6799621582031,-8628.8466796875,-0.9995255470275879,-1.6204634079031167e-8,0.030799703672528268,-1.6316988649123233e-8,1,-3.3965226187149257e-9,-0.030799703672528268,-3.8974694582805113e-9,-0.9995255470275879 } },
}
for _, spot in ipairs(soreyaSpots) do spot.cframe = CFrame.new(unpack(spot.cf)) end
local selectedSoreyaSpot = soreyaSpots[1]
MAIN:CreateDropdown({
    Options = { "Spot Core", "Spot Mancing", "Toko Rod", "Jual Ikan", "Base Camp" },
    Placeholder = "Pilih lokasi teleport...",
    Callback = function(name)
        for _, spot in ipairs(soreyaSpots) do
            if spot.name == name then selectedSoreyaSpot = spot break end
        end
    end,
})
MAIN:CreateButton({ Name = "Teleport ke Lokasi", Accent = true, Callback = function()
    if game.PlaceId ~= 118517641508250 then
        Window:Notify("Teleport", "Fitur lokasi ini khusus Mount Soreya", 2, "error")
        return
    end
    local char = player.Character
    if char and selectedSoreyaSpot then
        char:PivotTo(selectedSoreyaSpot.cframe)
        local root = char:FindFirstChild("HumanoidRootPart")
        if root then root.AssemblyLinearVelocity = Vector3.zero end
        resetHumanoidState()
        Window:Notify("Teleport", "Menuju " .. selectedSoreyaSpot.name, 1.5, "success")
    end
end })
end -- Mount Soreya: teleport section

if game.PlaceId == 118517641508250 then
MAIN:CreateSection("MEKI HUB FISHING")
local FishingConfig = { Running = false, Power = 100, BiteTimeout = 30, CollectInterval = 2, TapMaxDuration = 15 }
local FishingStatus = { phase = "idle", message = "Idle" }
local fishingBusy, fishingSince, lastCollect, tappingRod, miniStartTime = false, 0, 0, nil, 0
local hookedFishingRods = {}
local FishingMiniGameHandler
local FishingRS = game:GetService("ReplicatedStorage")
local FishingVIM = game:GetService("VirtualInputManager")
local FishingLP = player
local function fishingGetCastWait() return 2.15 end
local function fishingIsRod(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local mechanics = tool:FindFirstChild("Mechanics")
    local remotes = mechanics and mechanics:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("CastEvent") ~= nil
end
local function fishingFindRod()
    local char = FishingLP.Character
    if char then for _, item in ipairs(char:GetChildren()) do if fishingIsRod(item) then return item, true end end end
    local bp = FishingLP:FindFirstChildOfClass("Backpack")
    if bp then for _, item in ipairs(bp:GetChildren()) do if fishingIsRod(item) then return item, false end end end
    return nil, false
end
local function fishingRemotes(rod)
    local mechanics = rod and rod:FindFirstChild("Mechanics")
    local remotes = mechanics and mechanics:FindFirstChild("Remotes")
    if not remotes then return nil end
    return { Cast = remotes:FindFirstChild("CastEvent"), Notif = remotes:FindFirstChild("NotifyClient") }
end
local function fishingStatus(rod)
    local mechanics = rod and rod:FindFirstChild("Mechanics")
    return mechanics and mechanics:FindFirstChild("Status")
end
local function fishingDirection()
    local char = FishingLP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return Vector3.new(0,0,-1) end
    local look = root.CFrame.LookVector
    local flat = Vector3.new(look.X,0,look.Z)
    return flat.Magnitude < 0.1 and Vector3.new(0,0,-1) or flat.Unit
end
local function fishingEquipRod()
    local rod, equipped = fishingFindRod()
    if rod and not equipped then
        local char = FishingLP.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then pcall(function() hum:EquipTool(rod) end) end
    end
end
local function fishingCollectAll()
    local remote = FishingRS:FindFirstChild("Remote")
    local inv = remote and remote:FindFirstChild("Inventaris")
    local collect = inv and inv:FindFirstChild("AmbilSemua")
    if collect then pcall(function() collect:InvokeServer() end) end
end
local function fishingTap()
    if FishingMiniGameHandler and typeof(FishingMiniGameHandler.MobileTap) == "function" then
        pcall(function() FishingMiniGameHandler.MobileTap() end)
    elseif typeof(mouse1click) == "function" then
        pcall(mouse1click)
    elseif FishingVIM then
        local cam = workspace.CurrentCamera
        if cam then
            local vp = cam.ViewportSize
            pcall(function()
                FishingVIM:SendMouseButtonEvent(vp.X/2,vp.Y/2,0,true,game,1)
                FishingVIM:SendMouseButtonEvent(vp.X/2,vp.Y/2,0,false,game,1)
            end)
        end
    end
end
local function fishingHookRod(rod)
    if hookedFishingRods[rod] then return end
    local remotes = fishingRemotes(rod)
    if not remotes or not remotes.Notif then return end
    hookedFishingRods[rod] = true
    remotes.Notif.OnClientEvent:Connect(function(action, data)
        if action == "Bite" then
            FishingStatus.phase, FishingStatus.message = "bite", "Ikan narik!"
        elseif action == "CastFailed" then
            local reason = type(data) == "table" and data.reason or tostring(data)
            FishingStatus.phase, FishingStatus.message = "error", "Cast failed: " .. tostring(reason)
        elseif action == "NoFishingZone" then
            FishingStatus.phase, FishingStatus.message = "error", "Bukan zona mancing!"
        elseif action == "GotFish" then
            local name = type(data) == "table" and (data.baseName or data.originalName) or "ikan"
            FishingStatus.phase, FishingStatus.message = "got", "Dapet: " .. tostring(name)
        elseif action == "FishingCanceled" then
            FishingStatus.phase, FishingStatus.message = "idle", "Server cancel"
        end
    end)
end
local function fishingFireCast(value, power)
    local rod = fishingFindRod()
    local remotes = rod and fishingRemotes(rod)
    if remotes and remotes.Cast then
        if value == "start" then pcall(function() remotes.Cast:FireServer(true) end)
        elseif value == "release" then pcall(function() remotes.Cast:FireServer(false, power or FishingConfig.Power, fishingDirection()) end)
        else pcall(function() remotes.Cast:FireServer(false, 0) end) end
    end
end
local function fishingDoCast()
    if fishingBusy then return end
    fishingBusy = true
    FishingStatus.phase, FishingStatus.message = "charging", "Charging..."
    fishingFireCast("start")
    task.wait(fishingGetCastWait())
    if not FishingConfig.Running or isCleaningUp then fishingBusy = false return end
    FishingStatus.phase, FishingStatus.message = "casting", "Reeling out..."
    fishingFireCast("release")
    fishingSince = os.clock()
    FishingStatus.phase, FishingStatus.message = "waiting", "Nunggu ikan narik..."
    fishingBusy = false
end

task.spawn(function()
    local modules = FishingRS:WaitForChild("Modules", 10)
    local fishing = modules and modules:WaitForChild("Fishing", 10)
    local handler = fishing and fishing:WaitForChild("MiniGameHandler", 10)
    if handler then local ok, result = pcall(require, handler); if ok then FishingMiniGameHandler = result end end
end)
task.spawn(function()
    -- Tap berjalan secepat satu frame; tanpa jeda tetap 0.04 detik.
    while not isCleaningUp do
        if FishingConfig.Running and tappingRod then
            local status = fishingStatus(tappingRod)
            local mini = status and status:FindFirstChild("MiniGameActive")
            if not (mini and mini.Value) or os.clock() - miniStartTime > FishingConfig.TapMaxDuration then
                tappingRod = nil
            else
                fishingTap()
                task.wait() -- tap setiap frame agar responsif tanpa jeda buatan
            end
        else
            task.wait()
        end
    end
end)
task.spawn(function()
    while not isCleaningUp do
        task.wait() -- polling setiap frame; recast segera setelah status ikan selesai
        if not FishingConfig.Running then
            FishingStatus.phase, FishingStatus.message = "idle", "Idle"
            tappingRod = nil
            continue
        end
        local rod, equipped = fishingFindRod()
        if not rod then FishingStatus.phase, FishingStatus.message = "error", "Rod gak ada"; continue end
        if not equipped then FishingStatus.message = "Auto-equip..."; fishingEquipRod(); continue end
        fishingHookRod(rod)
        local status = fishingStatus(rod)
        if not status then continue end
        local active = status:FindFirstChild("FishingActive")
        local mini = status:FindFirstChild("MiniGameActive")
        local isFishing = active and active.Value or false
        local isMini = mini and mini.Value or false
        if isMini then
            FishingStatus.phase, FishingStatus.message = "minigame", "Minigame — auto tap!"
            if not tappingRod then tappingRod = rod; miniStartTime = os.clock() end
            fishingSince = 0
            continue
        end
        tappingRod = nil
        if isFishing then
            FishingStatus.phase = "waiting"
            if fishingSince == 0 then fishingSince = os.clock() end
            if os.clock() - fishingSince > FishingConfig.BiteTimeout then
                FishingStatus.message = "Timeout — recast"
                fishingFireCast("cancel")
                fishingSince = 0
                task.wait(0.5)
            end
            continue
        end
        fishingSince = 0
        if not fishingBusy then task.spawn(fishingDoCast) end
    end
end)
task.spawn(function()
    while not isCleaningUp do
        task.wait(1)
        if FishingConfig.Running and os.clock() - lastCollect >= FishingConfig.CollectInterval then
            lastCollect = os.clock()
            fishingCollectAll()
        end
    end
end)
local fishingToggle
fishingToggle = MAIN:CreateToggle({ Name = "Auto Fishing Soreya", Flag = "autoFishing", Callback = function(enabled)
    if enabled and game.PlaceId ~= 118517641508250 then return false, "Auto Fishing khusus Mount Soreya" end
    FishingConfig.Running = enabled
    if not enabled then fishingFireCast("cancel"); fishingSince = 0; fishingBusy = false; tappingRod = nil end
end })
end -- Mount Soreya: Auto Fishing

if game.PlaceId == 131312206945521 then
-- MEKI FISHING khusus Mount Rehat (FishingFoundation)
local MekiFish = { running = false, attempt = 0, session = nil, pending = nil, caught = 0, lastRodKey = nil }
local MF_SAVE = "mekifishing_data.json"
local MF_Http = game:GetService("HttpService")
local function mfSave()
    if type(writefile) ~= "function" then return end
    pcall(function() writefile(MF_SAVE, MF_Http:JSONEncode({caught = MekiFish.caught})) end)
end
pcall(function()
    if type(isfile) == "function" and type(readfile) == "function" and isfile(MF_SAVE) then
        local data = MF_Http:JSONDecode(readfile(MF_SAVE))
        MekiFish.caught = math.max(0, tonumber(data.caught) or 0)
    end
end)
local mfCounterLabel
local mfRemotes
local mfStart, mfCancel, mfEvent, mfBackpack
local mfFishingConn
local function mfInitRemotes()
    local fs = game:GetService("ReplicatedStorage"):FindFirstChild("FishingSystem")
    local rem = fs and fs:FindFirstChild("Remotes")
    if not rem then return false end
    mfStart, mfCancel = rem:FindFirstChild("StartFishing"), rem:FindFirstChild("CancelFishing")
    mfEvent, mfBackpack = rem:FindFirstChild("FishingEvent"), rem:FindFirstChild("BackpackEvent")
    return mfStart and mfCancel and mfEvent and mfBackpack
end
local function mfGetRod()
    local char = player.Character
    if not char then return nil end
    for _, tool in ipairs(char:GetChildren()) do
        if tool:IsA("Tool") and typeof(tool:GetAttribute("RodId")) == "string" and tool:GetAttribute("InventoryCategory") ~= "Fish" then return tool end
    end
end
local function mfEquipRod()
    if mfGetRod() then return true end
    local selected = player:GetAttribute("SelectedRodId")
    local keys = {}
    if typeof(selected) == "string" and selected ~= "" then table.insert(keys, selected); table.insert(keys, "rod:" .. selected) end
    if MekiFish.lastRodKey then table.insert(keys, MekiFish.lastRodKey) end
    local bp, char = player:FindFirstChildOfClass("Backpack"), player.Character
    for _, container in ipairs({char, bp}) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                local id = tool:GetAttribute("RodId")
                if typeof(id) == "string" then table.insert(keys, id); table.insert(keys, "rod:" .. id) end
            end
        end
    end
    local seen = {}
    for _, key in ipairs(keys) do
        if not seen[key] then
            seen[key] = true
            pcall(function() mfBackpack:FireServer({Action = "ToggleTool", Key = key}) end)
            task.wait(0.35)
            if mfGetRod() then MekiFish.lastRodKey = key; return true end
        end
    end
    return false
end
local function mfTarget()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local origin = root.Position + root.CFrame.LookVector * 12 + Vector3.new(0, 8, 0)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {char}
    local hit = workspace:Raycast(origin, Vector3.new(0, -60, 0), params)
    return hit and hit.Position or (root.Position + root.CFrame.LookVector * 15 - Vector3.new(0, 3, 0))
end
local function mfCast()
    if not MekiFish.running or MekiFish.pending or MekiFish.session then return end
    local target = mfTarget()
    if not target then return end
    MekiFish.attempt += 1
    MekiFish.pending = MekiFish.attempt
    mfStart:FireServer(MekiFish.attempt, target)
end
local function mfStop()
    MekiFish.running = false
    if MekiFish.session and mfCancel then pcall(function() mfCancel:FireServer(MekiFish.session) end) end
    MekiFish.session, MekiFish.pending = nil, nil
end
if mfInitRemotes() then
    mfFishingConn = mfEvent.OnClientEvent:Connect(function(payload)
        if typeof(payload) ~= "table" then return end
        if payload.Kind == "StartResult" then
            if MekiFish.pending == payload.AttemptId then
                MekiFish.pending = nil
                if payload.Accepted and typeof(payload.SessionId) == "string" then MekiFish.session = payload.SessionId
                elseif MekiFish.running then task.delay(0.15, mfCast) end
            end
        elseif payload.Kind == "Terminal" and payload.SessionId == MekiFish.session then
            MekiFish.session = nil
            if payload.State == "Caught" then
                MekiFish.caught += 1
                mfSave()
                mfCounterLabel.Text = "Total Caught: " .. tostring(MekiFish.caught)
                if MekiFish.running then
                    if not mfGetRod() then mfEquipRod() end
                    mfCast()
                end
            elseif payload.State == "Failed" and MekiFish.running then
                task.delay(0.2, mfCast)
            end
        end
    end)
else
    -- Remotes akan dicek ulang saat toggle diaktifkan.
end
local mfToggle = MAIN:CreateToggle({ Name = "MEKI FISHING", Flag = "mekiFishingRehat", Callback = function(enabled)
    if enabled and game.PlaceId ~= 131312206945521 then return false, "MEKI FISHING khusus Mount Rehat" end
    if enabled and not mfInitRemotes() then return false, "FishingSystem Remotes tidak ditemukan" end
    MekiFish.running = enabled
    if enabled then
        task.spawn(function()
            while MekiFish.running and not isCleaningUp do
                if not mfGetRod() then mfEquipRod() end
                if mfGetRod() and not MekiFish.pending and not MekiFish.session then mfCast() end
                task.wait(0.25)
            end
        end)
    else
        mfStop()
    end
end })
-- Counter sengaja berada tepat di bawah toggle MEKI FISHING pada menu Main.
mfCounterLabel = MAIN:CreateLabel("Total Caught: " .. tostring(MekiFish.caught))
if mfFishingConn then addCleanup(mfFishingConn) end
addCleanup({ Disconnect = function() mfStop() end })
end -- Mount Rehat: MEKI FISHING
end -- tutup blok fitur Main/Fishing

local frames, acc = 0, 0
addCleanup(RunService.RenderStepped:Connect(function(dt)
	frames = frames + 1
	acc = acc + dt
end))

local function getPing()
	local ok, v = pcall(function()
		return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	return ok and math.floor(v) or 0
end

task.spawn(function()
	while not isCleaningUp do
		task.wait(0.5)
		if isCleaningUp then break end
		local fps = (acc > 0) and math.floor(frames / acc + 0.5) or 0
		frames, acc = 0, 0
		local ping = getPing()

		Window.StatsLabel.Text = fps .. " FPS  |  " .. ping .. " ms"
	end
end)

local waypoints = {}
local autoTarget, autoRun, autoState = 1, 0, false
local summitState = false
local FILE = "meki_hub_" .. tostring(game.PlaceId) .. ".json"

local function saveData()
	if not hasFileAPI() then return end
	local data = {}
	for i, wp in ipairs(waypoints) do data[i] = { name = wp.name, cf = { wp.cframe:GetComponents() } } end
	pcall(function() writefile(FILE, HttpService:JSONEncode(data)) end)
end

local function loadData()
	if not hasFileAPI() or not isfile(FILE) then return end
	local ok, raw = pcall(readfile, FILE)
	if not ok or not raw then return end
	local ok2, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok2 or type(decoded) ~= "table" then return end
	for _, wp in ipairs(decoded) do
		if type(wp.name) == "string" and type(wp.cf) == "table" and #wp.cf == 12 then
			table.insert(waypoints, { name = wp.name, cframe = CFrame.new(unpack(wp.cf)) })
		end
	end
end

local WP = Window:CreateTab("Waypoints", "pin")
local renderLists
local autoToggle

local function saveCurrent()
	local char = player.Character
	if not char then
		Window:Notify("Waypoint", "Karakter belum siap", 2, "error")
		return
	end
	table.insert(waypoints, { name = "Lokasi " .. (#waypoints + 1), cframe = char:GetPivot() })
	saveData()
	renderLists()
	Window:Notify("Waypoint", "Lokasi " .. #waypoints .. " tersimpan", 1.5, "success")
end

WP:CreateSection("Auto Teleport")
autoToggle = WP:CreateToggle({
	Name = "Auto TP", Flag = "autoTP",
	Callback = function(s)
		if not s then
			autoState = false
			return
		end
		if #waypoints == 0 then return false, "Belum ada waypoint tersimpan" end
		if summitState then return false, "Matikan Auto Summit dulu" end

		autoState = true
		autoTarget = 1
		autoRun = autoRun + 1
		local myRun = autoRun
		task.spawn(function()
			while autoState and myRun == autoRun and not isCleaningUp do
				if #waypoints == 0 then
					autoToggle:Set(false)
					break
				end
				if autoTarget > #waypoints then autoTarget = 1 end
				local wp = waypoints[autoTarget]
				local char = player.Character
				if char and wp then
					pcall(function()
						char:PivotTo(wp.cframe)
						local hrp = char:FindFirstChild("HumanoidRootPart")
						if hrp then hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end
						resetHumanoidState()
					end)
				end
				task.wait(AUTO_INTERVAL)
				if autoState and myRun == autoRun and #waypoints > 0 then
					autoTarget = (autoTarget % #waypoints) + 1
				end
			end
		end)
	end,
})
WP:CreateSlider({
	Name = "Jeda Auto TP", Flag = "autoInterval", Min = 0.1, Max = 5, Default = AUTO_INTERVAL, Step = 0.1, Suffix = " dtk",
	Callback = function(v) AUTO_INTERVAL = v end,
})

WP:CreateSection("Lokasi")
WP:CreateButton({ Name = "+  Simpan Lokasi Sekarang", Accent = true, Callback = saveCurrent })
WP:CreateSection("Daftar Waypoint")

local function buildRow(page, i, wp)
	local row = new("Frame", {
		Name = "WPRow",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = T.Panel, BorderSizePixel = 0,
		LayoutOrder = 1000 + i,
	}, page)
	round(row, 8)
	outline(row, T.Stroke, 1, 0.5)

	new("TextLabel", {
		Text = i .. ". " .. wp.name, Font = FONT, TextSize = 13, TextColor3 = T.Text,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -(34 + 150), 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)

	local actBtn = new("TextButton", {
		Text = "TP", Font = FONTB, TextSize = 11, TextColor3 = T.Bg,
		BackgroundColor3 = T.Accent, AutoButtonColor = false,
		Size = UDim2.fromOffset(34, 26), Position = UDim2.new(1, -(34 + 138), 0.5, -13),
	}, row)
	round(actBtn, 6)
	actBtn.MouseButton1Click:Connect(function()
		local char = player.Character
		if char then
			char:PivotTo(wp.cframe)
			resetHumanoidState()
			Window:Notify("Teleport", "Ke " .. wp.name, 1.5)
		end
	end)

	local upBtn = new("TextButton", {
		Text = "", BackgroundColor3 = T.PanelLite, AutoButtonColor = false,
		Size = UDim2.fromOffset(24, 26), Position = UDim2.new(1, -112, 0.5, -13),
	}, row)
	round(upBtn, 6)
	local upArrow = new("TextLabel", {
		Text = ">", Font = FONTB, TextSize = 14, TextColor3 = T.SubText,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Rotation = -90,
	}, upBtn)
	if i > 1 then
		upBtn.MouseButton1Click:Connect(function()
			waypoints[i], waypoints[i - 1] = waypoints[i - 1], waypoints[i]
			saveData()
			renderLists()
		end)
	else
		upArrow.TextColor3 = T.Track
	end

	local downBtn = new("TextButton", {
		Text = "", BackgroundColor3 = T.PanelLite, AutoButtonColor = false,
		Size = UDim2.fromOffset(24, 26), Position = UDim2.new(1, -86, 0.5, -13),
	}, row)
	round(downBtn, 6)
	local downArrow = new("TextLabel", {
		Text = ">", Font = FONTB, TextSize = 14, TextColor3 = T.SubText,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Rotation = 90,
	}, downBtn)
	if i < #waypoints then
		downBtn.MouseButton1Click:Connect(function()
			waypoints[i], waypoints[i + 1] = waypoints[i + 1], waypoints[i]
			saveData()
			renderLists()
		end)
	else
		downArrow.TextColor3 = T.Track
	end

	local editBtn = new("TextButton", {
		Text = "", BackgroundColor3 = T.PanelLite, AutoButtonColor = false,
		Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -60, 0.5, -13),
	}, row)
	round(editBtn, 6)

	new("Frame", {
		Size = UDim2.fromOffset(4, 12), Position = UDim2.new(0.5, -2, 0.5, -7),
		BackgroundColor3 = T.SubText, BorderSizePixel = 0, Rotation = 45,
	}, editBtn)
	new("Frame", {
		Size = UDim2.fromOffset(10, 2), Position = UDim2.new(0.5, -5, 0.5, 5),
		BackgroundColor3 = T.SubText, BorderSizePixel = 0,
	}, editBtn)
	editBtn.MouseButton1Click:Connect(function()
		Window:Prompt("Ganti Nama Waypoint", wp.name, function(newName)
			wp.name = newName
			saveData()
			renderLists()
		end)
	end)

	local delBtn = new("TextButton", {
		Text = "X", Font = FONTB, TextSize = 11, TextColor3 = T.Text,
		BackgroundColor3 = T.Danger, AutoButtonColor = false,
		Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -34, 0.5, -13),
	}, row)
	round(delBtn, 6)
	delBtn.MouseButton1Click:Connect(function()
		table.remove(waypoints, i)
		if autoTarget > #waypoints then autoTarget = math.max(1, #waypoints) end
		saveData()
		renderLists()
	end)
end

renderLists = function()
	pruneReg()
	for _, c in ipairs(WP.Page:GetChildren()) do
		if c.Name == "WPRow" then c:Destroy() end
	end
	if #waypoints == 0 then
		new("TextLabel", {
			Name = "WPRow",
			Text = "Belum ada waypoint. Tekan tombol simpan di atas.",
			Font = FONT, TextSize = 12, TextColor3 = T.SubText,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = 1000,
		}, WP.Page)
	else
		for i, wp in ipairs(waypoints) do
			buildRow(WP.Page, i, wp)
		end
	end
end

local stopSummitAnim -- forward declare, dipakai MekiHub_Cleanup
local REC, AW -- tab Record & Auto Walk dipakai lagi di luar blok teleport/summit
do -- blok teleport/summit (kurangi local di level atas)
-- Auto Summit map validation uses Roblox PlaceId (game.PlaceId), not UniverseId.
-- Supported PlaceIds supplied by the user:
-- Mount Soreya  : 118517641508250
-- Mount Funkot  : 78842106567506
-- Mount Senoria : 134551551665645
-- Mount Sorry   : 139142243919159
local TELEPORT_MAPS = {
	{
		name = "MOUNT FUNKOT",
		placeIds = { 78842106567506 }, -- Place ID Mount Funkot

		points = {
			{ name = "cp 1", cf = { -8.677769660949707, 4.69999885559082, 836.5045166015625, -0.9564000964164734, 6.390950346712998e-8, 0.2920597791671753, 5.421065907285083e-8, 1, -4.130121666889863e-8, -0.2920597791671753, -2.3667734438959088e-8, -0.9564000964164734 } },
			{ name = "summit", cf = { -4221.38037109375, 2980.21435546875, 21684.75, -0.9715039730072022, 2.5034383455135868e-9, 0.23702339828014375, 4.351584426132149e-9, 1, 7.274146618385657e-9, -0.23702339828014375, 8.098289150382243e-9, -0.9715039730072022 } },
			{ name = "bc", cf = { -4335.751953125, 2996.500732421875, 21742.18359375, 0.6425053477287293, 3.436352002950116e-8, 0.7662811875343323, 9.230559072648248e-8, 1, -1.2224019485529426e-7, -0.7662811875343323, 1.4927201164027793e-7, 0.6425053477287293 } },
		},
	},
	{
		name = "MOUNT SORRY",
		placeIds = { 139142243919159 }, -- Place ID Mount Sorry


		finishRemote = { "LavaSummitKit", "Remotes", "ResetCheckpoint" },
		points = {
			{ name = "Lokasi 1", cf = { -1453.88037109375, 1315.7882080078125, -4514.326171875, -0.9949424862861633, 0, 0.10044623166322708, 0, 1, 0, -0.10044623166322708, 0, -0.9949424862861633 } },
			{ name = "Lokasi 2", cf = { -1463.992431640625, 1344.937255859375, -3112.145751953125, -0.19555272161960602, 0, -0.9806931614875793, 0, 1, 0, 0.9806931614875793, 0, -0.19555272161960602 } },
			{ name = "Lokasi 3", cf = { -1359.891845703125, 1224.937255859375, -2229.94482421875, -0.8999244570732117, 0, 0.4360458552837372, 0, 1, 0, -0.4360458552837372, 0, -0.8999244570732117 } },
			{ name = "Lokasi 4", cf = { -1427.7603759765625, 1268.937255859375, -1403.12646484375, -0.9967790842056274, 0, -0.08019640296697617, 0, 1, 0, 0.08019640296697617, 0, -0.9967790842056274 } },
			{ name = "Lokasi 5", cf = { -1486.658935546875, 1268.9364013671875, -376.5919494628906, -0.7110816240310669, 1.26657337395919e-10, -0.7031094431877136, 7.516268851759378e-08, 1, -7.583477668049454e-08, 0.7031094431877136, -1.067723118808317e-07, -0.7110816240310669 } },
			{ name = "Lokasi 6", cf = { -1389.287109375, 1551.3262939453125, 1168.878662109375, -0.9993882775306702, -1.7158875209588587e-08, 0.034972574561834335, -1.4129022396502933e-08, 1, 8.6882224081819e-08, -0.034972574561834335, 8.63349427504545e-08, -0.9993882775306702 } },
			{ name = "Lokasi 7", cf = { -765.2026977539062, 1824.7886962890625, 1864.849365234375, -0.9976733326911926, 0, -0.06817574799060822, 0, 1, 0, 0.06817574799060822, 0, -0.9976733326911926 } },
			{ name = "Lokasi 8", cf = { -18.991838455200195, 2007.67919921875, 1680.8494873046875, -0.2137427031993866, 0, -0.976889967918396, 0, 1, 0, 0.976889967918396, 0, -0.2137427031993866 } },
			{ name = "Lokasi 9", cf = { 1204.2799072265625, 1772.002685546875, 1815.01513671875, -0.0269776564091444, 0, -0.9996360540390015, 0, 1, 0, 0.9996360540390015, 0, -0.0269776564091444 } },
			{ name = "Lokasi 10", cf = { 2614.21728515625, 2083.699462890625, 2101.213623046875, -0.38138851523399353, 0, -0.9244148135185242, 0, 1, 0, 0.9244148135185242, 0, -0.38138851523399353 } },
			{ name = "Lokasi 11", cf = { 2813.47607421875, 2164.113037109375, 2803.460693359375, -0.5829921960830688, 0, -0.8124777674674988, 0, 1, 0, 0.8124777674674988, 0, -0.5829921960830688 } },
			{ name = "Lokasi 12", cf = { 4301.3623046875, 2560.86962890625, 3979.83642578125, 0.0029296278953552246, 0, -0.9999957084655762, 0, 1, 0, 0.9999957084655762, 0, 0.0029296278953552246 } },
			{ name = "Lokasi 13", cf = { 7168.435546875, 3983.90478515625, 8614.44140625, -0.7129423022270203, 0, 0.7012227177619934, 0, 1, 0, -0.7012227177619934, 0, -0.7129423022270203 } },
			{ name = "Lokasi 14", cf = { 6703.90478515625, 3995.328857421875, 9495.5830078125, -0.9019111394882202, 0, 0.43192169070243835, 0, 1, 0, -0.43192169070243835, 0, -0.9019111394882202 } },
			{ name = "Lokasi 15", cf = { 6187.06591796875, 4154.01513671875, 10926.09375, -0.9945721626281738, 0, 0.10404905676841736, 0, 1, 0, -0.10404905676841736, 0, -0.9945721626281738 } },
			{ name = "Lokasi 16", cf = { 5569.26806640625, 4272.75830078125, 12535.923828125, -0.08799827098846436, -1.074441087212108e-07, 0.9961206316947937, 1.573736696514061e-08, 1, 1.0925280236051549e-07, -0.9961206316947937, 2.5290374239261837e-08, -0.08799827098846436 } },
		},
	},
	{
		name = "MOUNT SENORIA",
		placeIds = { 134551551665645 }, -- Place ID Mount Senoria

		finishRemote = { "ValuableRecallSystem", "RequestRecall" },
		recallAfterFinish = true,
		points = {
			{ name = "Lokasi 1", cf = { 24160.71875, 6075.7080078125, -4183.01904296875, -0.25375229120254519, -5.912591749535068e-9, -0.967269241809845, -1.4352496080505262e-8, 1, -2.347446681483234e-9, 0.967269241809845, 1.3287058564515064e-8, -0.25375229120254519 } },
			{ name = "Lokasi 2", cf = { 25231.6171875, 6124.00537109375, -4347.8388671875, 0.17101892828941346, 3.5061908931766087e-8, -0.9852677583694458, 1.1857723691832689e-8, 1, 3.764439426845456e-8, 0.9852677583694458, -1.8120935862953048e-8, 0.17101892828941346 } },
		},
	},
	{
		name = "MOUNT SOREYA",
		placeIds = { 118517641508250 }, -- Place ID Mount Soreya


		cycleDelay = 2,
		points = {
			{ name = "Lokasi 1", cf = { 465.2262268066406, 451.2574768066406, -8944.884765625, 0.999977171421051, 8.956568109397267e-08, 0.006753375753760338, -8.9959584670396e-08, 1.0, 5.8022937565738175e-08, -0.006753375753760338, -5.862914420617926e-08, 0.999977171421051 } },
			{ name = "Lokasi 2", cf = { 450.9278259277344, 495.3647766113281, -9566.4169921875, 0.999938428401947, 2.1953468376523233e-08, 0.011094803921878338, -2.1072025901958114e-08, 1.0, -7.956339231895981e-08, -0.011094803921878338, 7.932469969773592e-08, 0.999938428401947 } },
			{ name = "Lokasi 3", cf = { 393.07696533203125, 640.940185546875, -10113.5068359375, 0.9980251789093018, -4.107807072273317e-08, 0.06281533092260361, 3.780193580382729e-08, 1.0, 5.334344166385563e-08, -0.06281533092260361, -5.086355514549723e-08, 0.9980251789093018 } },
			{ name = "Lokasi 4", cf = { 485.3341979980469, 643.888671875, -10684.146484375, -0.07656729221343994, -2.4567038181544377e-08, -0.9970644116401672, -7.60073781691517e-09, 1, -2.4055687219970424e-08, 0.9970644116401672, 5.736546793144726e-09, -0.07656729221343994 } },
			{ name = "Lokasi 5", cf = { 1086.5220947265625, 726.9559936523438, -11154.77734375, 0.9997825622558594, 2.2816186717733444e-09, 0.02085362933576107, -1.6146723957888298e-09, 1.0, -3.1999100258417457e-08, -0.02085362933576107, 3.1958471424786694e-08, 0.9997825622558594 } },
			{ name = "Lokasi 6", cf = { 974.2940063476562, 743.998779296875, -11815.5986328125, 0.1057509109377861, 2.3553035077839013e-09, 0.9943926334381104, -8.511861770976736e-10, 1.0, -2.2780635156038898e-09, -0.9943926334381104, -6.055059786902461e-10, 0.1057509109377861 } },
			{ name = "Lokasi 7", cf = { 392.1001281738281, 890.9053955078125, -11832.73046875, -0.18582166731357574, 2.5191166427157574e-15, 0.9825834631919861, 3.247671491747573e-15, 1.0, -1.9495837592014642e-15, -0.9825834631919861, 2.828833392846345e-15, -0.18582166731357574 } },
			{ name = "Lokasi 8", cf = { -324.4762268066406, 860.4766845703125, -11735.4833984375, 0.026753392070531845, 6.167360730186672e-14, 0.9996420741081238, -2.043649774961017e-14, 1.0, -6.114875180643006e-14, -0.9996420741081238, -1.8793245361607355e-14, 0.026753392070531845 } },
			{ name = "Lokasi 9", cf = { -868.4699096679688, 863.384033203125, -11736.3291015625, -0.041036177426576614, -2.5201552844578146e-08, 0.9991576671600342, 2.332847692798623e-09, 1.0, 2.5318611207580943e-08, -0.9991576671600342, 3.3698615009569725e-09, -0.041036177426576614 } },
			{ name = "Lokasi 10", cf = { -1281.6817626953125, 867.7041015625, -12093.5009765625, 0.9985512495040894, 4.440159415001251e-16, -0.05380885675549507, -4.511506588335257e-16, 1.0, -1.2044682778503043e-16, 0.05380885675549507, 1.4454822385686548e-16, 0.9985512495040894 } },
			{ name = "Lokasi 11", cf = { -1310.7728271484375, 901.794921875, -12835.283203125, 0.11296887695789337, 7.115592600001e-15, 0.9935985207557678, 4.583738275824433e-15, 1.0, -7.682592219728293e-15, -0.9935985207557678, 5.422289458661403e-15, 0.11296887695789337 } },
			{ name = "Lokasi 12", cf = { -2316.08544921875, 926.2474365234375, -12674.1875, -0.9344789385795593, -3.49352795581126e-08, -0.35601842403411865, -3.041247609303355e-08, 1.0, -1.8300907456136883e-08, 0.35601842403411865, -6.274411656903567e-09, -0.9344789385795593 } },
			{ name = "Lokasi 13", cf = { -2307.584716796875, 922.5309448242188, -11857.6875, -0.7694045901298523, 6.084164994035746e-08, 0.6387616991996765, 5.314154449820308e-08, 1.0, -3.123903269397488e-08, -0.6387616991996765, 9.909330245250203e-09, -0.7694045901298523 } },
			{ name = "Lokasi 14", cf = { -2443.790771484375, 966.5309448242188, -11056.515625, 0.08942752331495285, 9.244352128234823e-08, 0.9959933161735535, 9.511425957953179e-08, 1.0, -1.0135545380762778e-07, -0.9959933161735535, 1.0379713444308436e-07, 0.08942752331495285 } },
			{ name = "Lokasi 15", cf = { -3480.800537109375, 985.4891967773438, -11026.193359375, 0.7330354452133179, -3.2478031375404726e-09, 0.68019038438797, -1.2725646314493133e-08, 1.0, 1.8489165753976522e-08, -0.68019038438797, -2.2209077243928732e-08, 0.7330354452133179 } },
			{ name = "Lokasi 16", cf = { -4225.501953125, 1006.4288330078125, -11014.1689453125, -0.00672221090644598, -9.357729879866383e-08, 0.9999774098396301, 4.997040647936046e-08, 1.0, 9.391533239977434e-08, -0.9999774098396301, 5.060059748984713e-08, -0.00672221090644598 } },
			{ name = "Lokasi 17", cf = { -4650.3271484375, 1085.0804443359375, -11668.5595703125, -0.06734001636505127, 2.496225626202886e-08, 0.9977300763130188, 9.458340599621806e-08, 1.0, -1.863531018386766e-08, -0.9977300763130188, 9.311381177212752e-08, -0.06734001636505127 } },
			{ name = "Lokasi 18", cf = { -5543.0146484375, 1106.4356689453125, -11651.4296875, 0.044536292552948, -9.074737405967426e-09, 0.9990077614784241, 7.253122902284304e-08, 1.0, 5.850270046181549e-09, -0.9990077614784241, 7.219870923336202e-08, 0.044536292552948 } },
			{ name = "Lokasi 19", cf = { -6761.7568359375, 1100.008056640625, -11506.435546875, -0.9987558722496033, -3.922038516179782e-08, -0.04986699298024178, -3.7384129569772995e-08, 1.0, -3.775574342057553e-08, 0.04986699298024178, -3.584453267535537e-08, -0.9987558722496033 } },
			{ name = "Lokasi 20", cf = { -6760.42529296875, 1105.5643310546875, -10800.583984375, -0.979160726070404, 4.907910522433667e-08, 0.2030867487192154, 6.756027204346537e-08, 1.0, 8.406881590872217e-08, -0.2030867487192154, 9.60374819669596e-08, -0.979160726070404 } },
			{ name = "Lokasi 21", cf = { -6768.21337890625, 1318.4285888671875, -10082.080078125, -0.9984205365180969, 1.9393437966641613e-08, -0.05618179962038994, 1.2905613466784871e-08, 1.0, 1.1584192805003113e-07, 0.05618179928064346, 1.1493390417172122e-07, -0.9984205365180969 } },
			{ name = "Lokasi 22", cf = { -6825.57666015625, 1314.0919189453126, -9846.6337890625, -0.20223522186279298, -1.1170214975209092e-7, 0.9793369770050049, 4.752374493932621e-9, 1, 1.1504032926268337e-7, -0.9793369770050049, 2.7919382361574209e-8, -0.20223522186279298 } },
		},
	},
	{
		name = "MOUNT REHAT",
		placeIds = { 131312206945521 },
		pointDelay = 1,
		cycleDelay = 1.5,
		points = {
			{ name = "Lokasi 1", cf = { -388.3008117675781, 8.691120147705078, -3.2621066570281982 } },
			{ name = "Lokasi 2", cf = { -877.2549438476562, 5.319299697875977, -6.70767068862915 } },
			{ name = "Lokasi 3", cf = { -1542.96337890625, 142.95399475097656, -310.6284484863281 } },
			{ name = "Lokasi 4", cf = { -1563.9771728515625, 155.72531127929688, -1207.4986572265625 } },
			{ name = "Lokasi 5", cf = { -1445.624267578125, 148.39451599121094, -1764.6435546875 } },
			{ name = "Lokasi 6", cf = { -951.7771606445312, 180.0862274169922, -1736.6490478515625 } },
			{ name = "Lokasi 7", cf = { -297.0986633300781, 186.35919189453125, -1758.9884033203125 } },
			{ name = "Lokasi 8", cf = { 325.3539733886719, 247.1675262451172, -2419.932373046875 } },
			{ name = "Lokasi 9", cf = { 338.1124267578125, 379.0063781738281, -2952.79052734375 } },
			{ name = "Lokasi 10", cf = { 315.5015563964844, 647.9893798828125, -3558.233154296875 } },
			{ name = "Lokasi 11", cf = { 364.93048095703125, 820.7899169921875, -4332.64208984375 } },
			{ name = "Lokasi 12", cf = { 353.52581787109375, 819.874755859375, -4972.57080078125 } },
			{ name = "Lokasi 13", cf = { 359.41888427734375, 842.5299072265625, -5723.859375 } },
			{ name = "Lokasi 14", cf = { 202.59669494628906, 905.3602905273438, -6360.126953125 } },
			{ name = "Lokasi 15", cf = { -498.1544189453125, 908.4854736328125, -6371.77392578125 } },
			{ name = "Lokasi 16", cf = { -1234.9259033203125, 921.9412841796875, -6389.34912109375 } },
			{ name = "Lokasi 17", cf = { -1939.95654296875, 936.5109252929688, -6390.69482421875 } },
			{ name = "Lokasi 18", cf = { -2516.052001953125, 943.6419067382812, -6381.66259765625 } },
			{ name = "Lokasi 19", cf = { -3047.99609375, 942.0059814453125, -6611.61279296875 } },
			{ name = "Lokasi 20", cf = { -3053.19921875, 938.4998168945312, -7381.38916015625 } },
			{ name = "Lokasi 21", cf = { -3071.845703125, 1024.689697265625, -8043.45703125 } },
			{ name = "Lokasi 22", cf = { -3015.7998046875, 1010.8510131835938, -8768.51953125 } },
			{ name = "Lokasi 23", cf = { -3021.20458984375, 1059.072998046875, -9546.8447265625 } },
			{ name = "Lokasi 24", cf = { -3470.828857421875, 894.5008544921875, -9789.0986328125 } },
			{ name = "Lokasi 25", cf = { -4389.35888671875, 925.5013427734375, -9797.1767578125 } },
			{ name = "Lokasi 26", cf = { -6361.53564453125, 1286.3048095703125, -9691.3349609375 } },
			{ name = "Lokasi 27", cf = { -6467.95654296875, 1281.8985595703125, -9740.8837890625 } },
		},
	},
}
for _, m in ipairs(TELEPORT_MAPS) do
	for _, pt in ipairs(m.points) do
		pt.cframe = CFrame.new(unpack(pt.cf))
	end
end

local TPT = Window:CreateTab("Teleports", "flag")
-- Record dan Auto Walk ditempatkan tepat di bawah Teleports.
REC = Window:CreateTab("Record", "record")
AW = Window:CreateTab("Auto Walk", "route")
local selectedMap
local summitRun = 0
local summitToggle

local function findMap(name)
	for _, m in ipairs(TELEPORT_MAPS) do
		if m.name == name then return m end
	end
end

local detectedMap = nil
local function detectSupportedMap()
	local currentPlaceId = tonumber(game.PlaceId)
	for _, map in ipairs(TELEPORT_MAPS) do
		for _, placeId in ipairs(map.placeIds or {}) do
			if tonumber(placeId) == currentPlaceId then
				return map
			end
		end
	end
	return nil
end

detectedMap = detectSupportedMap()
selectedMap = detectedMap

local function tpTo(pt)
	local char = player.Character
	if not char then return false end
	pcall(function()
		char:PivotTo(pt.cframe)
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end
		resetHumanoidState()
	end)
	return true
end

local summitAnim
function stopSummitAnim()
    if summitAnim then
        pcall(function() summitAnim:Stop(0.15) end)
        summitAnim = nil
    end
end

local function startSummitAnim()
    stopSummitAnim()
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        pcall(function()
            animator = Instance.new("Animator")
            animator.Parent = hum
        end)
    end
    if not animator then return end

    pcall(function()
        local animId
        local animate = char:FindFirstChild("Animate")
        local runFolder = animate and animate:FindFirstChild("run")
        local runAnim = runFolder and runFolder:FindFirstChild("RunAnim")
        if runAnim and runAnim:IsA("Animation") and runAnim.AnimationId ~= "" then
            animId = runAnim.AnimationId
        end
        animId = animId or (hum.RigType == Enum.HumanoidRigType.R15
            and "rbxassetid://507767714" or "rbxassetid://180426354")
        local animation = Instance.new("Animation")
        animation.AnimationId = animId
        summitAnim = animator:LoadAnimation(animation)
        summitAnim.Looped = true
        summitAnim.Priority = Enum.AnimationPriority.Movement
        summitAnim:Play(0.15)
    end)
end


local function reachSummitPoint(point)
    if not summitState or isCleaningUp then return false end
    tpTo(point)
    local activeMap = selectedMap or detectedMap
    task.wait(activeMap and activeMap.pointDelay or 0.8)
    return summitState and not isCleaningUp
end

local function fireFinishRemote(map)
	local path = map.finishRemote
	if not path then return end
	local char = player.Character
	if char and char:GetAttribute("Carried") == true then return end
	local obj = game:GetService("ReplicatedStorage")
	for _, name in ipairs(path) do
		obj = obj and obj:FindFirstChild(name)
	end
	if obj and obj:IsA("RemoteEvent") then
		local ok, err = pcall(function() obj:FireServer() end)
		if not ok then warn("[MekiHub] ResetCheckpoint gagal: " .. tostring(err)) end
	else
		warn("[MekiHub] Remote ResetCheckpoint tidak ditemukan")
	end
end

-- Dropdown menampilkan semua map; hanya map yang cocok dengan PlaceId saat ini yang bisa dipilih.
selectedMap = detectedMap
TPT:CreateSection("AUTO SUMMIT")
local summitMapOptions = {}
local summitMapLocks = {}
for _, map in ipairs(TELEPORT_MAPS) do
	table.insert(summitMapOptions, map.name)
	summitMapLocks[map.name] = (map ~= detectedMap)
end
local summitMapDropdown = TPT:CreateDropdown({
	Options = summitMapOptions,
	Default = detectedMap and detectedMap.name or nil,
	Placeholder = "Pilih map...",
	DisabledOptions = summitMapLocks,
	Callback = function(name)
		if not detectedMap or name ~= detectedMap.name then
			return
		end
		selectedMap = detectedMap
	end,
})
if not detectedMap then
	TPT:CreateLabel("🔒 Pilihan map terkunci — PlaceId tidak cocok")
end
TPT:CreateLabel("NOTE : JIKA CP KE-SKIP, MATIKAN AUTO SUMMIT LALU NYALAKAN ULANG")
summitToggle = TPT:CreateToggle({
	Name = detectedMap and "Auto Summit" or "🔒 Auto Summit (Terkunci)",
	Flag = "autoSummit",
	Callback = function(s)
		if not s then
			summitState = false
			stopSummitAnim()
			return
		end
		if not detectedMap or tonumber(game.PlaceId) == nil
			or not table.find(detectedMap.placeIds or {}, tonumber(game.PlaceId)) then
			Window:Notify("Auto Summit", "🔒 Map ini tidak cocok / belum didukung", 3, "error")
			return false, "Auto Summit terkunci: PlaceId tidak cocok"
		end
		selectedMap = detectedMap
		if autoState then return false, "Matikan Auto TP (Waypoints) dulu" end

		summitState = true
		summitRun = summitRun + 1
		local myRun = summitRun
		task.spawn(function()
			local idx, last = 1, nil
			while summitState and myRun == summitRun and not isCleaningUp do
				local map = selectedMap
				if not map or #map.points == 0 then
					summitToggle:Set(false)
					break
				end
				if map ~= last then
					idx = 1
					last = map
				end
				if idx > #map.points then idx = 1 end

                if not summitAnim or not summitAnim.IsPlaying then
                    startSummitAnim()
                end
                local checkpointReached = reachSummitPoint(map.points[idx])
                if not checkpointReached then break end

				if idx == #map.points then
					if map.finishRemote then
						task.wait(0.25)
						fireFinishRemote(map)
						-- Khusus map yang memakai remote reset/recall: beri jeda 1 detik
						-- setelah BC, lalu langsung mulai lagi dari Posisi 1.
						for _ = 1, 10 do
							if not summitState or myRun ~= summitRun or isCleaningUp then break end
							task.wait(0.1)
						end
						if summitState and myRun == summitRun and not isCleaningUp then
							idx = 1
							last = map
							continue
						end
					end
					task.wait(map.cycleDelay or 0)
				end
				idx = idx + 1
			end
		end)
	end,
})
end -- [fix] tutup blok teleport/summit

local ESP = {
	enabled = false, box = true, name = true, dist = true, health = true,
	tracer = false, maxDist = 1000,
	color = Color3.fromRGB(255, 70, 90),
}
local espFolder = Instance.new("Folder")
espFolder.Name = "MekiESP"
espFolder.Parent = parentGui()
local tracerLayer = new("Frame", {
	Name = "Tracers", Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 0,
}, gui)
local espObjs = {}
local espConn

local function espClear(p)
	local o = espObjs[p]
	if not o then return end
	pcall(function() o.hl:Destroy() end)
	pcall(function() o.bb:Destroy() end)
	pcall(function() o.line:Destroy() end)
	espObjs[p] = nil
end

local function espCreate(p)
	local hl = Instance.new("Highlight")
	hl.FillTransparency = 0.75
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Enabled = false
	hl.Parent = espFolder

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(180, 46)
	bb.StudsOffset = Vector3.new(0, 3.4, 0)
	bb.AlwaysOnTop = true
	bb.Enabled = false
	bb.Parent = espFolder

	local lbl = new("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32),
		Font = FONTB, TextSize = 13, TextColor3 = ESP.color,
		TextStrokeTransparency = 0.3, Text = "",
		TextYAlignment = Enum.TextYAlignment.Bottom,
	}, bb)
	local barBack = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 36),
		Size = UDim2.fromOffset(80, 5),
		BackgroundColor3 = Color3.fromRGB(20, 20, 20), BorderSizePixel = 0,
	}, bb)
	round(barBack, 2)
	local barFill = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(70, 220, 140), BorderSizePixel = 0,
	}, barBack)
	round(barFill, 2)

	local line = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(0, 2),
		BackgroundColor3 = ESP.color, BorderSizePixel = 0, Visible = false,
	}, tracerLayer)

	local o = {hl = hl, bb = bb, lbl = lbl, barBack = barBack, barFill = barFill, line = line}
	espObjs[p] = o
	return o
end

local function espHide(o)
	o.hl.Enabled = false
	o.bb.Enabled = false
	o.line.Visible = false
end

local function espUpdate()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	local myHRP = getHRP()
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			local char = p.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local show = hrp ~= nil and hum ~= nil and hum.Health > 0
			local dist = 0
			if show and myHRP then
				dist = (myHRP.Position - hrp.Position).Magnitude
				if dist > ESP.maxDist then show = false end
			end

			local o = espObjs[p]
			if not show then
				if o then espHide(o) end
			else
				if not o then o = espCreate(p) end

				o.hl.Adornee = char
				o.hl.FillColor = ESP.color
				o.hl.OutlineColor = ESP.color
				o.hl.Enabled = ESP.box

				local showText = ESP.name or ESP.dist
				local txt = ""
				if ESP.name then txt = p.DisplayName end
				if ESP.dist then txt = txt .. ((txt ~= "") and "\n" or "") .. math.floor(dist) .. " m" end
				o.bb.Adornee = hrp
				o.bb.Enabled = showText or ESP.health
				o.lbl.Visible = showText
				o.lbl.Text = txt
				o.lbl.TextColor3 = ESP.color
				o.barBack.Visible = ESP.health
				if ESP.health then
					local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
					o.barFill.Size = UDim2.fromScale(frac, 1)
					o.barFill.BackgroundColor3 = Color3.fromRGB(255, 70, 70):Lerp(Color3.fromRGB(70, 220, 140), frac)
				end

				if ESP.tracer then
					local v, onScreen = cam:WorldToViewportPoint(hrp.Position)
					if onScreen then
						local a = Vector2.new(vp.X / 2, vp.Y)
						local b = Vector2.new(v.X, v.Y)
						local d = b - a
						local mid = a + d / 2
						o.line.Size = UDim2.fromOffset(d.Magnitude, 2)
						o.line.Position = UDim2.fromOffset(mid.X, mid.Y)
						o.line.Rotation = math.deg(math.atan2(d.Y, d.X))
						o.line.BackgroundColor3 = ESP.color
						o.line.Visible = true
					else
						o.line.Visible = false
					end
				else
					o.line.Visible = false
				end
			end
		end
	end
end

local function espStop()
	if espConn then espConn:Disconnect() espConn = nil end
	for p in pairs(espObjs) do espClear(p) end
end

local function espStart()
	if espConn then return end
	espConn = RunService.RenderStepped:Connect(function() pcall(espUpdate) end)
end

addCleanup(Players.PlayerRemoving:Connect(function(p) espClear(p) end))

local Lighting = game:GetService("Lighting")
local fbSaved
local function setFullbright(on)
	if on then
		if not fbSaved then
			fbSaved = {
				Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
				FogEnd = Lighting.FogEnd, GlobalShadows = Lighting.GlobalShadows,
				Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
			}
		end
		Lighting.Brightness = 2
		Lighting.ClockTime = 14
		Lighting.FogEnd = 1000000
		Lighting.GlobalShadows = false
		Lighting.Ambient = Color3.fromRGB(178, 178, 178)
		Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
	elseif fbSaved then
		for k, v in pairs(fbSaved) do Lighting[k] = v end
		fbSaved = nil
	end
end

local AL = { on = false, extreme = false }
local alSaved = setmetatable({}, { __mode = "k" })
local alConn
local alToken = 0
local alQuality

local function alRecord(inst, prop)
	local s = alSaved[inst]
	if not s then
		s = {}
		alSaved[inst] = s
	end
	if s[prop] == nil then s[prop] = inst[prop] end
end

local function alProcess(inst)
	if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
		or inst:IsA("Smoke") or inst:IsA("Fire") or inst:IsA("Sparkles") then
		alRecord(inst, "Enabled")
		inst.Enabled = false
	elseif inst:IsA("PostEffect") then
		alRecord(inst, "Enabled")
		inst.Enabled = false
	elseif inst:IsA("BasePart") and not inst:IsA("Terrain") then
		alRecord(inst, "Material")
		alRecord(inst, "Reflectance")
		inst.Material = Enum.Material.SmoothPlastic
		inst.Reflectance = 0
		if AL.extreme then
			alRecord(inst, "CastShadow")
			inst.CastShadow = false
		end
	elseif AL.extreme and (inst:IsA("Decal") or inst:IsA("Texture")) then
		alRecord(inst, "Transparency")
		inst.Transparency = 1
	elseif AL.extreme and inst:IsA("Light") then
		alRecord(inst, "Enabled")
		inst.Enabled = false
	end
end

local function alRestore()
	alToken = alToken + 1
	if alConn then alConn:Disconnect() alConn = nil end
	for inst, props in pairs(alSaved) do
		pcall(function()
			for prop, val in pairs(props) do inst[prop] = val end
		end)
	end
	alSaved = setmetatable({}, { __mode = "k" })
	if alQuality then
		pcall(function() settings().Rendering.QualityLevel = alQuality end)
		alQuality = nil
	end
end

local function alStart()
	alRestore()
	if not AL.on then return end
	local my = alToken

	pcall(function()
		alRecord(Lighting, "GlobalShadows")
		Lighting.GlobalShadows = false
	end)
	pcall(function()
		local terr = workspace.Terrain
		alRecord(terr, "WaterWaveSize")
		alRecord(terr, "WaterWaveSpeed")
		alRecord(terr, "WaterReflectance")
		terr.WaterWaveSize = 0
		terr.WaterWaveSpeed = 0
		terr.WaterReflectance = 0
	end)
	if AL.extreme then
		pcall(function()
			alQuality = settings().Rendering.QualityLevel
			settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
		end)
	end

	alConn = workspace.DescendantAdded:Connect(function(d) pcall(alProcess, d) end)

	task.spawn(function()
		for _, d in ipairs(Lighting:GetDescendants()) do pcall(alProcess, d) end
		local list = workspace:GetDescendants()
		for i, d in ipairs(list) do
			if alToken ~= my or isCleaningUp then return end
			pcall(alProcess, d)
			if i % 300 == 0 then task.wait() end
		end
	end)
end

local MV = Window:CreateTab("Movement", "user")

MV:CreateSection("Terbang")
MV:CreateToggle({ Name = "Fly", Flag = "fly", ResetOnRespawn = true, Callback = toggleFly })
MV:CreateSlider({
	Name = "Kecepatan Fly", Flag = "flySpeed", Min = 10, Max = 1000, Default = 150, Step = 5,
	Callback = function(v) flySpeed = v end,
})

MV:CreateSection("Lari")
MV:CreateToggle({
	Name = "Speed Hack", Flag = "speedHack", ResetOnRespawn = true,
	Callback = function(s)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if s then
			if not hum then return false, "Karakter belum siap" end
			if not isFlying then defaultWalkSpeed = hum.WalkSpeed end
			speedEnabled = true
			if not isFlying then hum.WalkSpeed = walkSpeed end
		else
			speedEnabled = false
			if hum and not isFlying then hum.WalkSpeed = defaultWalkSpeed end
		end
	end,
})
MV:CreateSlider({
	Name = "Kecepatan Jalan", Flag = "walkSpeed", Min = 16, Max = 300, Default = 50, Step = 1,
	Callback = function(v) walkSpeed = v end,
})

MV:CreateSection("Lainnya")
MV:CreateToggle({ Name = "No Clip", Flag = "noclip", ResetOnRespawn = true, Callback = toggleNoclip })
MV:CreateToggle({
	Name = "Infinite Jump", Flag = "infJump", ResetOnRespawn = true,
	Callback = function(s) isInfJump = s end,
})

local EP = Window:CreateTab("ESP", "eye")

EP:CreateSection("Utama")
EP:CreateToggle({
	Name = "Aktifkan ESP", Flag = "esp",
	Callback = function(s)
		ESP.enabled = s
		if s then espStart() else espStop() end
	end,
})

EP:CreateSection("Tampilan")
EP:CreateToggle({ Name = "Outline Highlight", Flag = "espBox", Default = true, Silent = true, Callback = function(s) ESP.box = s end })
EP:CreateToggle({ Name = "Nama", Flag = "espName", Default = true, Silent = true, Callback = function(s) ESP.name = s end })
EP:CreateToggle({ Name = "Jarak", Flag = "espDist", Default = true, Silent = true, Callback = function(s) ESP.dist = s end })
EP:CreateToggle({ Name = "Bar HP", Flag = "espHealth", Default = true, Silent = true, Callback = function(s) ESP.health = s end })
EP:CreateToggle({ Name = "Tracer (garis ke pemain)", Flag = "espTracer", Silent = true, Callback = function(s) ESP.tracer = s end })

EP:CreateSection("Filter")
EP:CreateSlider({
	Name = "Jarak Maksimal", Flag = "espMax", Min = 50, Max = 3000, Default = 1000, Step = 50, Suffix = " m",
	Callback = function(v) ESP.maxDist = v end,
})
EP:CreateColorRow({
	Name = "Warna ESP", Flag = "espColor", Default = "Merah",
	Colors = {
		{"Merah",  Color3.fromRGB(255, 70, 90)},
		{"Kuning", Color3.fromRGB(255, 220, 70)},
		{"Putih",  Color3.fromRGB(255, 255, 255)},
		{"Cyan",   Color3.fromRGB(0, 210, 255)},
		{"Hijau",  Color3.fromRGB(70, 220, 140)},
	},
	Callback = function(_, color) ESP.color = color end,
})

local MS = Window:CreateTab("Misc", "misc")

MS:CreateSection("Performa")
MS:CreateToggle({ Name = "Anti AFK", Flag = "antiAfk", Default = true, Callback = setAntiAfk })
MS:CreateToggle({
	Name = "Anti Lag (FPS Booster)", Flag = "antiLag",
	Callback = function(s)
		AL.on = s
		alStart()
	end,
})
MS:CreateToggle({
	Name = "Anti Lag Ekstrem (hapus texture & bayangan)", Flag = "antiLagExtreme", Silent = true,
	Callback = function(s)
		AL.extreme = s
		if AL.on then alStart() end
	end,
})

MS:CreateSection("Visual")
MS:CreateToggle({ Name = "Fullbright", Flag = "fullbright", Callback = setFullbright })

MS:CreateSection("Karakter")
MS:CreateButton({
	Name = "Reset Karakter",
	Callback = function()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then hum.Health = 0 end
	end,
})


addCleanup(player.CharacterAdded:Connect(function(character)
	stopFly()
	if isNoclip then toggleNoclip(false) end
	isInfJump = false
	speedEnabled = false
	Window:ResetToggles()

	task.wait(0.5)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then defaultWalkSpeed = hum.WalkSpeed end
end))

do -- Scope terpisah untuk Config agar tidak melewati batas 200 local Luau.
local TeleportService = game:GetService("TeleportService")
local CFG_FILE = "meki_hub_configs.json"
local cfgData = { configs = {}, last = nil, autoload = false, autoexec = false }

local function cfgRead()
	if not hasFileAPI() or not isfile(CFG_FILE) then return end
	local ok, raw = pcall(readfile, CFG_FILE)
	if not ok or not raw then return end
	local ok2, dec = pcall(HttpService.JSONDecode, HttpService, raw)
	if ok2 and type(dec) == "table" then
		cfgData.configs = type(dec.configs) == "table" and dec.configs or {}
		cfgData.last = type(dec.last) == "string" and dec.last or nil
		cfgData.autoload = (dec.autoload == true)
		cfgData.autoexec = (dec.autoexec == true)
	end
end

local function cfgWrite()
	if not hasFileAPI() then return false end
	return (pcall(function() writefile(CFG_FILE, HttpService:JSONEncode(cfgData)) end))
end

local function cfgSnapshot()
	local out = {}
	for id, f in pairs(Window.Flags) do
		local ok, v = pcall(f.get)
		if ok then out[id] = v end
	end
	return out
end

local function cfgApply(vals)

	for id, f in pairs(Window.Flags) do
		if vals[id] ~= nil and f.kind ~= "toggle" then pcall(f.set, vals[id]) end
	end
	for id, f in pairs(Window.Flags) do
		if vals[id] ~= nil and f.kind == "toggle" then pcall(f.set, vals[id]) end
	end
end

cfgRead()

local TOTAL_EXEC_FILE = "MekiHubV3_total_exec.txt"
local function loadAndIncrementTotalExec()
    local current = tonumber(env.MekiHub_TotalExec) or 0
    local readOk, saved = pcall(function()
        if env.isfile and env.isfile(TOTAL_EXEC_FILE) and env.readfile then
            return env.readfile(TOTAL_EXEC_FILE)
        end
        if isfile and readfile and isfile(TOTAL_EXEC_FILE) then
            return readfile(TOTAL_EXEC_FILE)
        end
        return nil
    end)
    if readOk and saved then current = math.max(current, tonumber(saved) or 0) end
    current = current + 1
    env.MekiHub_TotalExec = current
    pcall(function()
        local writer = env.writefile or writefile
        if writer then writer(TOTAL_EXEC_FILE, tostring(current)) end
    end)
    return current
end
loadAndIncrementTotalExec()

local function queueMekiOnTeleport()
    local url = tostring(MEKI_CONFIG.AUTO_EXEC_SCRIPT_URL or "")
    if url == "" then return false, "AUTO_EXEC_SCRIPT_URL belum diisi di MEKI_CONFIG" end
    local queueFn = env.queue_on_teleport
        or env.queueonteleport
        or (env.syn and env.syn.queue_on_teleport)
    if type(queueFn) ~= "function" then
        return false, "Executor tidak mendukung queue_on_teleport"
    end
    local queuedSource = "task.wait(2); local ok, src = pcall(function() return game:HttpGet(" .. string.format("%q", url) .. ") end); if ok and type(src) == 'string' then local fn, err = loadstring(src); if fn then pcall(fn) else warn('[MEKI HUB AUTO-EXEC] '..tostring(err)) end else warn('[MEKI HUB AUTO-EXEC] Gagal mengambil script') end"
    local ok, err = pcall(queueFn, queuedSource)
    if not ok then return false, tostring(err) end
    return true
end

local function syncAutoExecQueue()
    if not cfgData.autoexec then return end
    local ok, err = queueMekiOnTeleport()
    if not ok then
        Window:Notify("Auto Execute", err, 3, "error")
    end
end

local renderCfgList

local function cfgLoad(name)
	local vals = cfgData.configs[name]
	if type(vals) ~= "table" then
		Window:Notify("Config", "Config tidak ditemukan", 2, "error")
		return
	end
	cfgApply(vals)
	cfgData.last = name
	cfgWrite()
	Window:Notify("Config", "'" .. name .. "' dimuat", 2, "success")
end

local function cfgSave(name)
	name = tostring(name):match("^%s*(.-)%s*$")
	if #name == 0 then
		Window:Notify("Config", "Nama tidak boleh kosong", 2, "error")
		return
	end
	if #name > 24 then name = name:sub(1, 24) end
	local existed = cfgData.configs[name] ~= nil
	cfgData.configs[name] = cfgSnapshot()
	cfgData.last = name
	if cfgWrite() then
		Window:Notify("Config", "'" .. name .. (existed and "' diperbarui" or "' tersimpan"), 2, "success")
	else
		Window:Notify("Config", "Gagal menyimpan (executor tidak support file)", 3, "error")
	end
	renderCfgList()
end

local function cfgDelete(name)
	cfgData.configs[name] = nil
	if cfgData.last == name then cfgData.last = nil end
	cfgWrite()
	renderCfgList()
	Window:Notify("Config", "'" .. name .. "' dihapus", 1.5)
end

local function rejoinServer()
	Window:Notify("Rejoin", "Masuk ulang ke server...", 2)
	pcall(function()
		if #Players:GetPlayers() <= 1 then
			TeleportService:Teleport(game.PlaceId, player)
		else
			TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
		end
	end)
end

local hopping = false
local function serverHop()
	if hopping then return end
	hopping = true
	Window:Notify("Server Hop", "Mencari server lain...", 2)
	task.spawn(function()
		local ok, err = pcall(function()
			local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
			local raw
			local okGet, res = pcall(function() return game:HttpGet(url) end)
			if okGet and res then
				raw = res
			else
				local req = (env.syn and env.syn.request) or env.http_request or env.request
				if req then
					local r = req({ Url = url, Method = "GET" })
					raw = r and r.Body
				end
			end
			assert(raw, "tidak bisa mengambil daftar server")
			local data = HttpService:JSONDecode(raw)
			local candidates = {}
			for _, s in ipairs(data.data or {}) do
				if s.id ~= game.JobId and s.playing and s.maxPlayers and s.playing < s.maxPlayers - 1 then
					table.insert(candidates, s.id)
				end
			end
			assert(#candidates > 0, "tidak ada server lain yang tersedia")
			local pick = candidates[math.random(1, math.min(#candidates, 10))]
			TeleportService:TeleportToPlaceInstance(game.PlaceId, pick, player)
		end)
		if not ok then
			local msg = tostring(err):gsub("^.-:%d+: ", "")
			Window:Notify("Server Hop", msg, 3, "error")
		end
		task.delay(4, function() hopping = false end)
	end)
end

-- ===== MEKI HUB: WALK RECORDER + AUTO WALK (MOUNT CYMORA) =====
local featureBuildOk, featureBuildError = pcall(function()
	local RECORD_FOLDER = "MekiHubRecordings"
	local AUTO_WALK_URL = "https://raw.githubusercontent.com/mekinjir/auto-walk/refs/heads/main/cymoraa.json"
	local CURRENT_MAP_ID = tostring(game.PlaceId)
	local canRecordFiles = type(writefile) == "function" and type(readfile) == "function"
		and type(isfile) == "function" and type(listfiles) == "function"
		and type(makefolder) == "function" and type(isfolder) == "function"
	local function ensureRecordFolder()
		if canRecordFiles and not isfolder(RECORD_FOLDER) then
			pcall(makefolder, RECORD_FOLDER)
		end
	end
	ensureRecordFolder()

	local recordStatusLabel, recordListLabel
	local refreshRecordNames
	local recordFrames = {}
	local recording, recordPaused = false, false
	local recordStart, recordPausedTotal, recordPauseAt, lastSample = 0, 0, 0, 0
	local playbackFrames = {}
	local playing, playPaused, playStopped = false, false, false
	local playStart, playPausedTotal, playPauseAt = 0, 0, 0
	local playConnection, walkTrack
	local recordPlaybackSpeed = 1
	local autoWalkSpeed = 1
	local autoWalkLoop = false

	local function recorderStatus(text)
		if recordStatusLabel then recordStatusLabel.Text = text end
	end
	local function currentCharacter()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		return char, hrp, hum
	end
	local activeAnimState = "idle"
    local walkTracks = {}
    local function stopWalkAnim()
        for _, tr in pairs(walkTracks) do pcall(function() tr:Stop(0.12); tr:Destroy() end) end
        table.clear(walkTracks)
        activeAnimState = "idle"
    end
    local function getAnimTrack(kind)
        local _, _, hum = currentCharacter()
        if not hum then return nil end
        local char = player.Character
        local animate = char and char:FindFirstChild("Animate")
        local folderName = ({run="run", walk="walk", jump="jump", fall="fall"})[kind] or "walk"
        local folder = animate and animate:FindFirstChild(folderName)
        local animObj = folder and folder:FindFirstChildOfClass("Animation")
        local fallback = ({run="rbxassetid://507767714", walk="rbxassetid://507777826", jump="rbxassetid://507765000", fall="rbxassetid://507767968"})[kind]
        local id = animObj and animObj.AnimationId or fallback
        if not id then return nil end
        local anim = Instance.new("Animation"); anim.AnimationId = id
        local tr = hum:LoadAnimation(anim)
        tr.Looped = (kind == "walk" or kind == "run" or kind == "fall")
        tr.Priority = (kind == "jump" or kind == "fall") and Enum.AnimationPriority.Action or Enum.AnimationPriority.Movement
        return tr
    end
    local function setPlaybackAnim(state)
        state = state or "idle"
        if state == activeAnimState then return end
        -- Stop semua track sebelumnya sebelum memainkan state baru agar jump tidak bertumpuk dengan walk/run.
        stopWalkAnim()
        if state == "walk" or state == "run" or state == "jump" or state == "fall" then
            local tr = getAnimTrack(state)
            if tr then
                tr:Play(state == "jump" and 0.04 or 0.10)
                walkTracks[state] = tr
                activeAnimState = state
            end
        end
    end
    local function getRecordedMotionState(hum, hrp)
        if not hum or not hrp then return "idle" end
        local hs = hum:GetState()
        if hs == Enum.HumanoidStateType.Jumping then return "jump" end
        if hs == Enum.HumanoidStateType.Freefall then return "fall" end
        if hs == Enum.HumanoidStateType.Climbing then return "climb" end
        if hs == Enum.HumanoidStateType.Swimming then return "swim" end
        local moving = hum.MoveDirection.Magnitude
        if moving <= 0.05 then return "idle" end
        return hum.WalkSpeed >= 20 and "run" or "walk"
    end
	local function sanitizeName(name)
		name = tostring(name or ""):gsub("[^%w_%- ]", ""):gsub("^%s+", ""):gsub("%s+$", "")
		return name:sub(1, 48)
	end
	local function listRecordNames()
		local names = {}
		if not canRecordFiles then return names end
		local ok, files = pcall(listfiles, RECORD_FOLDER)
		if not ok or type(files) ~= "table" then return names end
		for _, path in ipairs(files) do
			local name = tostring(path):match("([^/\\]+)%.json$")
			if name then
				local valid = false
				pcall(function()
					local data = HttpService:JSONDecode(readfile(path))
					valid = type(data) == "table" and tostring(data.mapId or "") == CURRENT_MAP_ID
				end)
				if valid then table.insert(names, name) end
			end
		end
		table.sort(names)
		return names
	end
	local function startRecording()
		if not canRecordFiles then
			Window:Notify("Walk Recorder", "Executor tidak mendukung file I/O", 3, "error")
			return
		end
		local _, hrp = currentCharacter()
		if not hrp then Window:Notify("Walk Recorder", "Karakter belum siap", 2, "error"); return end
		if playing then Window:Notify("Walk Recorder", "Hentikan playback dulu", 2, "error"); return end
		recordFrames = {}
		recordStart = tick()
		recordPausedTotal = 0
		recordPauseAt = 0
		lastSample = 0
		recording, recordPaused = true, false
		recorderStatus("Status: MEREKAM")
		Window:Notify("Walk Recorder", "Perekaman dimulai", 1.5, "success")
	end
	local function toggleRecordPause()
		if not recording then
			Window:Notify("Walk Recorder", "Belum ada rekaman aktif", 2, "error")
			return
		end
		if not recordPaused then
			recordPaused = true
			recordPauseAt = tick()
			recorderStatus("Status: PAUSE REKAM")
		else
			recordPausedTotal = recordPausedTotal + (tick() - recordPauseAt)
			recordPaused = false
			recorderStatus("Status: MEREKAM")
		end
	end
	local function nextRecordingName()
		local index = 1
		while index < 100000 do
			local candidate = "meki_hub_" .. index
			if not isfile(RECORD_FOLDER .. "/" .. candidate .. ".json") then return candidate end
			index = index + 1
		end
		return "meki_hub_" .. tostring(math.floor(tick()))
	end
	local function saveRecording()
		if not recording then Window:Notify("Walk Recorder", "Tidak ada rekaman untuk disimpan", 2, "error"); return end
		recording, recordPaused = false, false
		if #recordFrames < 5 then
			recorderStatus("Status: Rekaman terlalu pendek")
			Window:Notify("Walk Recorder", "Rekaman minimal 5 frame", 2, "error")
			return
		end
		local name = nextRecordingName()
		local payload = { mapId = CURRENT_MAP_ID, frames = {} }
		for i, frame in ipairs(recordFrames) do
			payload.frames[i] = { t = frame.t, cf = { frame.cf:GetComponents() }, state = frame.state or "idle", speed = frame.speed or 0 }
		end
		local ok, err = pcall(function()
			writefile(RECORD_FOLDER .. "/" .. name .. ".json", HttpService:JSONEncode(payload))
		end)
		if ok then
			recorderStatus("Status: Tersimpan - " .. name)
			Window:Notify("Walk Recorder", "Rekaman tersimpan: " .. name, 2, "success")
			refreshRecordNames()
		else
			recorderStatus("Status: Gagal menyimpan")
			Window:Notify("Walk Recorder", tostring(err), 3, "error")
		end
		recordFrames = {}
	end
	local function stopPlayback()
		playing, playPaused, playStopped = false, false, true
		if playConnection then playConnection:Disconnect(); playConnection = nil end
		stopWalkAnim()
	end
	local function nearestFrameIndex(frames)
		local _, hrp = currentCharacter()
		if not hrp or type(frames) ~= "table" or #frames == 0 then return 1 end
		local bestIndex, bestDistance = 1, math.huge
		for i, frame in ipairs(frames) do
			local distance = (hrp.Position - frame.cf.Position).Magnitude
			if distance < bestDistance then bestDistance, bestIndex = distance, i end
		end
		return bestIndex
	end
	local function loadPlayback(name)
		if not canRecordFiles then return false, "File I/O tidak didukung" end
		name = sanitizeName(name)
		if name == "" then return false, "Masukkan nama file rekaman" end
		local path = RECORD_FOLDER .. "/" .. name .. ".json"
		if not isfile(path) then return false, "File rekaman tidak ditemukan" end
		local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
		if not ok or type(data) ~= "table" or type(data.frames) ~= "table" then return false, "Format rekaman rusak" end
		if tostring(data.mapId or "") ~= CURRENT_MAP_ID then return false, "Rekaman hanya bisa dipakai di map asal" end
		local frames = {}
		for _, frame in ipairs(data.frames) do
			if type(frame) == "table" and type(frame.cf or frame.cframe) == "table" and #(frame.cf or frame.cframe) >= 12 and tonumber(frame.t or frame.time) then
				local okCF, cf = pcall(function() return CFrame.new(unpack(frame.cf or frame.cframe)) end)
				if okCF then table.insert(frames, { t = tonumber(frame.t or frame.time), cf = cf, state = frame.state or "idle", speed = tonumber(frame.speed) or 0 }) end
			end
		end
		if #frames < 2 then return false, "Frame rekaman tidak cukup" end
		table.sort(frames, function(a, b) return a.t < b.t end)
		return true, frames
	end
	local function startPlayback(name, continueFromNearest)
		if recording then return false, "Simpan atau hentikan rekaman dulu" end
		local ok, result = loadPlayback(name)
		if not ok then return false, result end
		stopPlayback()
		playbackFrames = result
		local startIndex = continueFromNearest and nearestFrameIndex(playbackFrames) or 1
		playStart, playPausedTotal = tick() - (playbackFrames[startIndex].t / recordPlaybackSpeed), 0
		playing, playPaused, playStopped = true, false, false
		setPlaybackAnim(playbackFrames[startIndex].state)
		playConnection = RunService.Heartbeat:Connect(function()
			if not playing or playPaused or isCleaningUp then return end
			local _, hrp = currentCharacter()
			if not hrp then stopPlayback(); return end
			local elapsed = (tick() - playStart - playPausedTotal) * recordPlaybackSpeed
			local last = playbackFrames[#playbackFrames]
			if elapsed >= last.t then
				hrp.CFrame = last.cf
				stopPlayback()
				recorderStatus("Status: Playback selesai")
				return
			end
			local idx = 1
			while idx < #playbackFrames and playbackFrames[idx + 1].t < elapsed do idx = idx + 1 end
			local a = playbackFrames[idx]
            setPlaybackAnim(a.state)
			local b = playbackFrames[math.min(idx + 1, #playbackFrames)]
			local alpha = (b.t > a.t) and math.clamp((elapsed - a.t) / (b.t - a.t), 0, 1) or 1
			hrp.CFrame = a.cf:Lerp(b.cf, alpha)
		end)
		recorderStatus(continueFromNearest and "Status: LANJUT DARI POSISI TERDEKAT" or ("Status: PLAYBACK - " .. sanitizeName(name)))
		return true
	end
	local function togglePlaybackPause()
		if not playing then return false, "Playback belum berjalan" end
		if not playPaused then
			playPaused = true
			playPauseAt = tick()
			stopWalkAnim()
			recorderStatus("Status: PLAYBACK DIJEDA")
		else
			playPausedTotal = playPausedTotal + (tick() - playPauseAt)
			playPaused = false
			setPlaybackAnim(playbackFrames[nearestFrameIndex(playbackFrames)].state)
			recorderStatus("Status: PLAYBACK")
		end
		return true
	end

	REC:CreateSection("WALK RECORDER")
	recordStatusLabel = REC:CreateLabel("Status: Siap")
	REC:CreateSlider({ Name = "Kecepatan Playback Rekaman", Flag = "recordPlaybackSpeed", Min = 0.25, Max = 3, Default = 1, Step = 0.25, Suffix = "x", Callback = function(v) recordPlaybackSpeed = v end })
	REC:CreateButton({ Name = "● MULAI REKAM", Accent = true, Callback = startRecording })
	REC:CreateButton({ Name = "Ⅱ PAUSE / RESUME REKAM", Callback = toggleRecordPause })
	REC:CreateButton({ Name = "■ STOP & SIMPAN OTOMATIS", Danger = true, Callback = function() saveRecording() end })
	REC:CreateSection("HASIL REKAMAN • MAP INI")
	local recordCards = {}
    local function openRenamePopup(oldName)
        local overlay = new("Frame", {Name="RenameOverlay", Size=UDim2.fromScale(1,1), BackgroundColor3=Color3.new(0,0,0), BackgroundTransparency=0.35, ZIndex=500}, gui)
        local card = new("Frame", {Size=UDim2.fromOffset(310,160), AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5), BackgroundColor3=T.Panel, BorderSizePixel=0, ZIndex=501}, overlay); round(card,10); outline(card,T.Stroke,1,0.2)
        new("TextLabel", {Text="RENAME REKAMAN", Font=FONTB, TextSize=15, TextColor3=T.Text, BackgroundTransparency=1, Position=UDim2.fromOffset(14,10), Size=UDim2.new(1,-28,0,25), TextXAlignment=Enum.TextXAlignment.Left, ZIndex=502}, card)
        local box = new("TextBox", {Text=oldName, PlaceholderText="Nama baru", Font=FONT, TextSize=13, TextColor3=T.Text, PlaceholderColor3=T.SubText, BackgroundColor3=T.Track, BorderSizePixel=0, ClearTextOnFocus=false, Position=UDim2.fromOffset(14,45), Size=UDim2.new(1,-28,0,38), ZIndex=502}, card); round(box,7)
        local cancel = new("TextButton", {Text="BATAL", Font=FONTB, TextSize=13, TextColor3=T.Text, BackgroundColor3=T.PanelLite, BorderSizePixel=0, Position=UDim2.fromOffset(14,100), Size=UDim2.new(0.46,-5,0,40), ZIndex=502}, card); round(cancel,7)
        local save = new("TextButton", {Text="SIMPAN", Font=FONTB, TextSize=13, TextColor3=Color3.new(1,1,1), BackgroundColor3=T.AccentDark, BorderSizePixel=0, Position=UDim2.new(0.54,0,0,100), Size=UDim2.new(0.46,-14,0,40), ZIndex=502}, card); round(save,7)
        cancel.MouseButton1Click:Connect(function() overlay:Destroy() end)
        save.MouseButton1Click:Connect(function()
            local newName = sanitizeName(box.Text)
            if newName == "" then Window:Notify("Rename", "Nama tidak boleh kosong", 2, "error"); return end
            local oldPath, newPath = RECORD_FOLDER .. "/" .. oldName .. ".json", RECORD_FOLDER .. "/" .. newName .. ".json"
            if oldName ~= newName and isfile(newPath) then Window:Notify("Rename", "Nama tersebut sudah dipakai", 2, "error"); return end
            local ok, err = pcall(function() if oldName ~= newName then writefile(newPath, readfile(oldPath)); delfile(oldPath) end end)
            if ok then overlay:Destroy(); Window:Notify("Rename", "Berhasil rename", 2, "success"); refreshRecordNames() else Window:Notify("Rename", tostring(err), 3, "error") end
        end)
    end
	refreshRecordNames = function()
		for _, card in ipairs(recordCards) do pcall(function() card:Destroy() end) end
		table.clear(recordCards)
		local names = listRecordNames()
		if #names == 0 then
			table.insert(recordCards, REC:CreateLabel("Belum ada rekaman untuk map ini."))
			return names
		end
		for _, name in ipairs(names) do
			local title = REC:CreateLabel("▰  " .. name)
			table.insert(recordCards, title)
			local row = REC:CreateActionRow({
				{ Text = "▶ PLAY", Callback = function()
					local ok, err = startPlayback(name, false)
					if not ok then Window:Notify("Playback", err, 3, "error") end
				end },
				{ Text = "■ STOP", Danger = true, Callback = function()
					if playing then stopPlayback(); recorderStatus("Status: Playback dihentikan — siap dilanjutkan") end
				end },
				{ Text = "↻ LANJUT", Callback = function()
					local ok, err = startPlayback(name, true)
					if not ok then Window:Notify("Playback", err, 3, "error") end
				end },
			})
			table.insert(recordCards, row)
			local manageRow = REC:CreateActionRow({
				{ Text = "✎ RENAME", Callback = function() openRenamePopup(name) end },
				{ Text = "🗑 HAPUS", Danger = true, Callback = function()
					local path = RECORD_FOLDER .. "/" .. name .. ".json"
					if type(delfile) ~= "function" then Window:Notify("Hapus", "Executor tidak mendukung delfile", 2, "error"); return end
					local ok = pcall(delfile, path)
					Window:Notify("Hapus", ok and "Rekaman dihapus" or "Gagal menghapus", 2, ok and "success" or "error")
					refreshRecordNames()
				end },
			})
			table.insert(recordCards, manageRow)
		end
	end
	refreshRecordNames()

	addCleanup(RunService.Heartbeat:Connect(function()
		if not recording or recordPaused or isCleaningUp then return end
		local _, hrp = currentCharacter()
		if not hrp then return end
		local now = tick()
		if now - lastSample < (1 / 30) then return end
		lastSample = now
		local elapsed = now - recordStart - recordPausedTotal
		local _, _, hum = currentCharacter()
        local moveSpeed = hum and hum.MoveDirection.Magnitude * hum.WalkSpeed or 0
        local state = getRecordedMotionState(hum, hrp)
        table.insert(recordFrames, { t = elapsed, cf = hrp.CFrame, state = state, speed = moveSpeed })
	end))

	-- Fetch sekali dari GitHub; PlaceId yang ada di JSON menjadi sumber kunci map Cymora.
	local cymoraData, cymoraMapId, cymoraFetchError
	local function fetchCymoraData()
		local ok, raw = pcall(function()
			return game:HttpGet(AUTO_WALK_URL)
		end)
		if not ok or type(raw) ~= "string" then
			local requestFn = (syn and syn.request) or http_request or request
			if type(requestFn) == "function" then
				local reqOk, response = pcall(requestFn, { Url = AUTO_WALK_URL, Method = "GET" })
				if reqOk and type(response) == "table" and (response.StatusCode == 200 or response.StatusCode == 0) then
					raw = response.Body
				end
			end
		end
		if type(raw) ~= "string" then return nil, nil, "Gagal mengambil file GitHub" end
		local decodedOk, data = pcall(function() return HttpService:JSONDecode(raw) end)
		if not decodedOk or type(data) ~= "table" then return nil, nil, "JSON cymoraa.json tidak valid" end
		local mapId = data.mapId or data.mapID or data.idMap or data.idmap or data.map_id or data.mapPlaceId or data.placeId or data.PlaceId or data.placeID or data.place_id or data.gamePlaceId or data.gameId or data.id
		if not mapId and type(data.info) == "table" then
			mapId = data.info.mapId or data.info.mapID or data.info.idMap or data.info.map_id or data.info.placeId or data.info.PlaceId or data.info.place_id or data.info.id
		end
		local frames = data.frames or data.recording or data.recordedFrames or data.path or data.points
		if type(frames) ~= "table" then return data, tonumber(mapId), "Data frames tidak ditemukan" end
		return { mapId = tonumber(mapId), frames = frames }, tonumber(mapId), nil
	end
	cymoraData, cymoraMapId, cymoraFetchError = fetchCymoraData()
	local cymoraUnlocked = cymoraData ~= nil and cymoraFetchError == nil and cymoraMapId ~= nil
		and tonumber(game.PlaceId) == cymoraMapId

	AW:CreateSection("MOUNT CYMORA")
	local cymoraMapDropdown = AW:CreateDropdown({
		Options = { "MOUNT CYMORA" },
		Default = cymoraUnlocked and "MOUNT CYMORA" or nil,
		Placeholder = cymoraUnlocked and "Pilih map" or "🔒 MOUNT CYMORA (terkunci)",
		DisabledOptions = { ["MOUNT CYMORA"] = not cymoraUnlocked },
		Callback = function(name)
			if name ~= "MOUNT CYMORA" or not cymoraUnlocked then
				Window:Notify("Auto Walk", "🔒 Map ini terkunci — PlaceId tidak cocok", 2.5, "error")
			end
		end,
	})
	local autoWalkToggle
	local autoWalkResume = false
	AW:CreateSlider({ Name = "Kecepatan Auto Walk", Flag = "autoWalkSpeed", Min = 0.25, Max = 3, Default = 1, Step = 0.25, Suffix = "x", Callback = function(v) autoWalkSpeed = v end })
	AW:CreateToggle({ Name = "Auto Loop", Flag = "autoWalkLoop", Callback = function(v) autoWalkLoop = v end })
	local autoWalkActionButton
	autoWalkToggle = AW:CreateToggle({
		Name = cymoraUnlocked and "Auto Walk Mount Cymora" or "🔒 Auto Walk (Terkunci)",
		Flag = "autoWalkCymora",
		Callback = function(enabled)
			if not enabled then stopPlayback(); return true end
			if not cymoraUnlocked or tonumber(game.PlaceId) ~= cymoraMapId then
				return false, "🔒 Auto Walk hanya untuk Mount Cymora (PlaceId tidak cocok)"
			end
			if recording then return false, "Simpan atau hentikan rekaman dulu" end
			local frames = {}
			for _, frame in ipairs(cymoraData.frames) do
				if type(frame) == "table" and type(frame.cf or frame.cframe) == "table" and #(frame.cf or frame.cframe) >= 12 and tonumber(frame.t or frame.time) then
					local okCF, cf = pcall(function() return CFrame.new(unpack(frame.cf or frame.cframe)) end)
					if okCF then table.insert(frames, { t = tonumber(frame.t or frame.time), cf = cf, state = frame.state or "idle", speed = tonumber(frame.speed) or 0 }) end
				end
			end
			if #frames < 2 then return false, "Data jalur Cymora kosong / format tidak cocok" end
			table.sort(frames, function(a, b) return a.t < b.t end)
			stopPlayback()
			playbackFrames = frames
			local startIndex = autoWalkResume and nearestFrameIndex(playbackFrames) or 1
			playStart, playPausedTotal = tick() - (playbackFrames[startIndex].t / autoWalkSpeed), 0
			playing, playPaused, playStopped = true, false, false
			autoWalkResume = false
			setPlaybackAnim(playbackFrames[startIndex].state or "walk")
			playConnection = RunService.Heartbeat:Connect(function()
				if not playing or playPaused or isCleaningUp then return end
				local _, hrp = currentCharacter()
				if not hrp then stopPlayback(); if autoWalkToggle then autoWalkToggle:Set(false, true) end; return end
				local elapsed = (tick() - playStart - playPausedTotal) * autoWalkSpeed
				local last = playbackFrames[#playbackFrames]
				if elapsed >= last.t then
					hrp.CFrame = last.cf
					if autoWalkLoop then
						hrp.CFrame = last.cf
						playStart, playPausedTotal = tick() - (playbackFrames[1].t / autoWalkSpeed), 0
						return
					end
					hrp.CFrame = last.cf
					stopPlayback()
					if autoWalkToggle then autoWalkToggle:Set(false, true) end
					autoWalkResume = false
					autoWalkActionButton.Text = "■ STOP AUTO WALK"
					Window:Notify("Auto Walk", "Rute Mount Cymora selesai", 2, "success")
					return
				end
				local idx = 1
				while idx < #playbackFrames and playbackFrames[idx + 1].t < elapsed do idx = idx + 1 end
				local a, b = playbackFrames[idx], playbackFrames[math.min(idx + 1, #playbackFrames)]
                local desiredState = a.state or "walk"
                local segmentDt = math.max(0.001, b.t - a.t)
                local delta = b.cf.Position - a.cf.Position
                local segmentSpeed = delta.Magnitude / segmentDt
                -- Jalur Auto Walk yang tidak menyimpan state tetap dapat mengenali fase loncat dari lintasan vertikal.
                if desiredState == "idle" or desiredState == "walk" or desiredState == "run" then
                    if delta.Y > 2.5 and (delta.Y / segmentDt) > 3 then
                        desiredState = "jump"
                    elseif delta.Y < -2.5 and (delta.Y / segmentDt) < -3 then
                        desiredState = "fall"
                    elseif desiredState == "idle" then
                        desiredState = segmentSpeed < 0.5 and "idle" or (segmentSpeed >= 16 and "run" or "walk")
                    end
                end
                setPlaybackAnim(desiredState)
				local alpha = (b.t > a.t) and math.clamp((elapsed - a.t) / (b.t - a.t), 0, 1) or 1
				hrp.CFrame = a.cf:Lerp(b.cf, alpha)
			end)
			return true
		end,
	})
	autoWalkActionButton = AW:CreateButton({ Name = "■ STOP AUTO WALK", Danger = true, Callback = function()
		if playing then
			stopPlayback()
			autoWalkResume = true
			autoWalkActionButton.Text = "↻ LANJUTKAN WALK"
			autoWalkActionButton.Parent.BackgroundColor3 = T.Panel
			Window:Notify("Auto Walk", "Berhenti sementara — tekan lanjutkan untuk meneruskan dari titik terdekat", 2.5)
		else
			if not autoWalkResume then
				Window:Notify("Auto Walk", "Tidak ada jalur yang dihentikan", 1.5, "error")
				return
			end
			if autoWalkToggle then autoWalkToggle:Set(true) end
			autoWalkActionButton.Text = "■ STOP AUTO WALK"
		end
	end })

	env.MekiHub_WalkCleanup = function()
		recording, recordPaused = false, false
		stopPlayback()
	end
end)



if not featureBuildOk then
    local message = tostring(featureBuildError):gsub("^.-:%d+: ", "")
    pcall(function()
        REC:CreateSection("RECORD - ERROR")
        REC:CreateLabel("UI gagal dimuat: " .. message)
        REC:CreateButton({ Name = "COBA MUAT ULANG RECORD", Callback = function()
            Window:Notify("Record", "Jalankan ulang MEKI HUB untuk memuat ulang fitur.", 3, "error")
        end })
        AW:CreateSection("AUTO WALK - ERROR")
        AW:CreateLabel("UI gagal dimuat: " .. message)
    end)
end


local CF = Window:CreateTab("Config", "gear")

CF:CreateSection("Simpan Pengaturan")
CF:CreateButton({
	Name = "+  Simpan Pengaturan Sekarang", Accent = true,
	Callback = function()
		Window:Prompt("Nama Config", "", cfgSave, "Contoh: Farming")
	end,
})

CF:CreateSection("Config Tersimpan")
local cfgList = new("Frame", {
	Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	LayoutOrder = CF:NextOrder(),
}, CF.Page)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, cfgList)

CF:CreateToggle({
	Name = "Auto Load config terakhir saat dijalankan", Default = cfgData.autoload, Silent = true,
	Callback = function(s)
		if cfgData.autoload ~= s then
			cfgData.autoload = s
			cfgWrite()
		end
	end,
})


CF:CreateSection("Auto Execute / Rejoin")
CF:CreateToggle({
    Name = "Auto Execute setelah Teleport / Rejoin", Default = cfgData.autoexec, Silent = true,
    Callback = function(state)
        cfgData.autoexec = state
        cfgWrite()
        if state then
            local ok, err = queueMekiOnTeleport()
            Window:Notify("Auto Execute", ok and "Aktif. Script akan dijalankan lagi setelah teleport." or err, 3, ok and "success" or "error")
        else
            Window:Notify("Auto Execute", "Dimatikan. Antrean teleport yang sudah dibuat mungkin tetap berjalan sekali.", 3)
        end
    end,
})

renderCfgList = function()
	pruneReg()
	for _, c in ipairs(cfgList:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	local names = {}
	for n in pairs(cfgData.configs) do table.insert(names, n) end
	table.sort(names)

	if #names == 0 then
		new("TextLabel", {
			Text = "Belum ada config tersimpan.", Font = FONT, TextSize = 12, TextColor3 = T.SubText,
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32),
		}, cfgList)
		return
	end

	for i, n in ipairs(names) do
		local row = new("Frame", {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundColor3 = T.Panel, BorderSizePixel = 0,
			LayoutOrder = i,
		}, cfgList)
		round(row, 8)
		outline(row, T.Stroke, 1, 0.5)
		new("TextLabel", {
			Text = n, Font = FONT, TextSize = 13, TextColor3 = T.Text,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -110, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, row)
		local loadBtn = new("TextButton", {
			Text = "Load", Font = FONTB, TextSize = 11, TextColor3 = T.Bg,
			BackgroundColor3 = T.Accent, AutoButtonColor = false,
			Size = UDim2.fromOffset(50, 26), Position = UDim2.new(1, -90, 0.5, -13),
		}, row)
		round(loadBtn, 6)
		loadBtn.MouseButton1Click:Connect(function() cfgLoad(n) end)
		local delBtn = new("TextButton", {
			Text = "X", Font = FONTB, TextSize = 11, TextColor3 = T.Text,
			BackgroundColor3 = T.Danger, AutoButtonColor = false,
			Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -34, 0.5, -13),
		}, row)
		round(delBtn, 6)
		delBtn.MouseButton1Click:Connect(function() cfgDelete(n) end)
	end
end
renderCfgList()

CF:CreateSection("Server")
CF:CreateButton({ Name = "Rejoin Server", Callback = rejoinServer })
CF:CreateButton({ Name = "Server Hop (pindah server lain)", Callback = serverHop })

CF:CreateSection("Tampilan")
CF:CreateColorRow({
	Name = "Warna Aksen", Flag = "theme", Colors = THEMES, Default = currentThemeName,
	Callback = function(name, color)
		applyTheme(name, color)
		Window:Notify("Tema", "Warna " .. name .. " dipakai", 1.5, "success")
	end,
})
CF:CreateToggle({
	Name = "FPS & Ping di topbar", Flag = "showStats", Default = true, Silent = true,
	Callback = function(s) Window.StatsLabel.Visible = s end,
})
CF:CreateToggle({
	Name = "Border berputar", Flag = "spinBorder", Default = true, Silent = true,
	Callback = function(s) Window.SpinBorder = s end,
})

CF:CreateSection("Lainnya")
CF:CreateButton({
	Name = "Hapus UI (Unload)", Danger = true,
	Callback = function()
		if env.MekiHub_Cleanup then pcall(env.MekiHub_Cleanup) end
	end,
})

if cfgData.autoload and cfgData.last and cfgData.configs[cfgData.last] then
	task.spawn(function()
		task.wait(3.8)
		if isCleaningUp then return end
		cfgLoad(cfgData.last)
	end)
end
if cfgData.autoexec then
    task.delay(2, function()
        if not isCleaningUp then syncAutoExecQueue() end
    end)
end

end -- akhir scope Config

env.MekiHub_Cleanup = function()
	isCleaningUp = true
	pcall(function() if env.MekiHub_WalkCleanup then env.MekiHub_WalkCleanup() end end)
	autoState = false
	summitState = false
	isInfJump = false
	pcall(stopFly)
	pcall(toggleNoclip, false)
	pcall(espStop)
	pcall(stopSummitAnim)
	pcall(setAntiAfk, false)
	pcall(alRestore)
	pcall(setFullbright, false)
	pcall(function() espFolder:Destroy() end)
	for _, c in ipairs(cleanupConns) do pcall(function() c:Disconnect() end) end
	pcall(function() gui:Destroy() end)
end

loadData()
renderLists()
