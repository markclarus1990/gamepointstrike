-- GAMEPOINT STRIKE - HUDClient (auto-builds all UI, no manual UI work)
-- Explorer path: StarterPlayer > StarterPlayerScripts > HUDClient (LocalScript)
-- Requires: ReplicatedStorage > Remotes > HitConfirm, KillFeed
-- Creates: PlayerGui > HUD (crosshair, ammo, health, hitmarker, killfeed, banner)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local HitConfirm: RemoteEvent = Remotes:WaitForChild("HitConfirm")
local KillFeed: RemoteEvent = Remotes:WaitForChild("KillFeed")

-- Build HUD
local gui = Instance.new("ScreenGui")
gui.Name = "HUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local function mkFrame(name: string, size: UDim2, pos: UDim2, color: Color3, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = f
	return f
end

-- Crosshair center
local center = Instance.new("Frame")
center.Name = "Center"
center.Size = UDim2.fromOffset(0, 0)
center.Position = UDim2.fromScale(0.5, 0.5)
center.BackgroundTransparency = 1
center.Parent = gui

local crossColor = Color3.fromRGB(255, 255, 255)
local gap = 8
local armLen = 10
local top = mkFrame("Top", UDim2.fromOffset(2, armLen), UDim2.fromOffset(0, -gap - armLen / 2), crossColor, center)
local bottom = mkFrame("Bottom", UDim2.fromOffset(2, armLen), UDim2.fromOffset(0, gap + armLen / 2), crossColor, center)
local left = mkFrame("Left", UDim2.fromOffset(armLen, 2), UDim2.fromOffset(-gap - armLen / 2, 0), crossColor, center)
local right = mkFrame("Right", UDim2.fromOffset(armLen, 2), UDim2.fromOffset(gap + armLen / 2, 0), crossColor, center)
local dot = mkFrame("Dot", UDim2.fromOffset(3, 3), UDim2.fromOffset(0, 0), crossColor, center)

-- Ammo bottom-right
local ammoLabel = Instance.new("TextLabel")
ammoLabel.Name = "AmmoLabel"
ammoLabel.Size = UDim2.fromOffset(220, 50)
ammoLabel.Position = UDim2.new(1, -240, 1, -80)
ammoLabel.BackgroundTransparency = 1
ammoLabel.Font = Enum.Font.GothamBold
ammoLabel.TextSize = 32
ammoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
ammoLabel.TextStrokeTransparency = 0.5
ammoLabel.TextXAlignment = Enum.TextXAlignment.Right
ammoLabel.Text = "30 / ∞"
ammoLabel.Parent = gui

local gunLabel = Instance.new("TextLabel")
gunLabel.Name = "GunLabel"
gunLabel.Size = UDim2.fromOffset(220, 20)
gunLabel.Position = UDim2.new(1, -240, 1, -45)
gunLabel.BackgroundTransparency = 1
gunLabel.Font = Enum.Font.Gotham
gunLabel.TextSize = 14
gunLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
gunLabel.TextXAlignment = Enum.TextXAlignment.Right
gunLabel.Text = "RIFLE  •  R to reload"
gunLabel.Parent = gui

-- Health bottom-left
local healthBg = Instance.new("Frame")
healthBg.Name = "HealthBg"
healthBg.Size = UDim2.fromOffset(220, 14)
healthBg.Position = UDim2.new(0, 20, 1, -50)
healthBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
healthBg.BorderSizePixel = 0
healthBg.Parent = gui
local healthFill = Instance.new("Frame")
healthFill.Name = "HealthFill"
healthFill.Size = UDim2.fromScale(1, 1)
healthFill.BackgroundColor3 = Color3.fromRGB(80, 200, 100)
healthFill.BorderSizePixel = 0
healthFill.Parent = healthBg

local healthLabel = Instance.new("TextLabel")
healthLabel.Size = UDim2.fromOffset(220, 20)
healthLabel.Position = UDim2.new(0, 20, 1, -75)
healthLabel.BackgroundTransparency = 1
healthLabel.Font = Enum.Font.GothamBold
healthLabel.TextSize = 18
healthLabel.TextColor3 = Color3.new(1, 1, 1)
healthLabel.TextXAlignment = Enum.TextXAlignment.Left
healthLabel.Text = "100"
healthLabel.Parent = gui

-- Hitmarker (X)
local hitmarker = Instance.new("TextLabel")
hitmarker.Name = "Hitmarker"
hitmarker.Size = UDim2.fromOffset(100, 100)
hitmarker.Position = UDim2.fromScale(0.5, 0.5)
hitmarker.AnchorPoint = Vector2.new(0.5, 0.5)
hitmarker.BackgroundTransparency = 1
hitmarker.Font = Enum.Font.GothamBlack
hitmarker.TextSize = 42
hitmarker.TextColor3 = Color3.new(1, 1, 1)
hitmarker.TextStrokeTransparency = 0.3
hitmarker.Text = "✕"
hitmarker.Visible = false
hitmarker.Parent = gui

-- Killfeed top-right
local feed = Instance.new("Frame")
feed.Name = "KillFeed"
feed.Size = UDim2.fromOffset(320, 150)
feed.Position = UDim2.new(1, -340, 0, 20)
feed.BackgroundTransparency = 1
feed.Parent = gui
local feedLayout = Instance.new("UIListLayout")
feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
feedLayout.Padding = UDim.new(0, 4)
feedLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
feedLayout.Parent = feed

-- Center banner (win message)
local banner = Instance.new("TextLabel")
banner.Name = "Banner"
banner.Size = UDim2.fromScale(1, 0.1)
banner.Position = UDim2.fromScale(0.5, 0.3)
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.BackgroundTransparency = 1
banner.Font = Enum.Font.GothamBlack
banner.TextSize = 36
banner.TextColor3 = Color3.fromRGB(255, 210, 80)
banner.TextStrokeTransparency = 0.2
banner.Text = ""
banner.Visible = false
banner.Parent = gui

local function flashHitmarker(wasKill: boolean, wasHeadshot: boolean)
	hitmarker.Visible = true
	hitmarker.TextColor3 = if wasKill then Color3.fromRGB(255, 60, 60)
		elseif wasHeadshot then Color3.fromRGB(255, 180, 60)
		else Color3.new(1, 1, 1)
	hitmarker.TextSize = if wasKill then 54 else 42
	task.delay(0.18, function()
		hitmarker.Visible = false
	end)
end

local function addFeed(text: string)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromOffset(310, 22)
	l.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	l.BackgroundTransparency = 0.4
	l.Font = Enum.Font.Gotham
	l.TextSize = 14
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Text = text
	l.Parent = feed
	task.delay(5, function()
		if l and l.Parent then
			l:Destroy()
		end
	end)
	-- keep max 5
	local count = 0
	for _, c in feed:GetChildren() do
		if c:IsA("TextLabel") then
			count += 1
		end
	end
	if count > 5 then
		for _, c in feed:GetChildren() do
			if c:IsA("TextLabel") then
				c:Destroy()
				break
			end
		end
	end
end

HitConfirm.OnClientEvent:Connect(function(wasHit: boolean, wasKill: boolean, wasHeadshot: boolean)
	if wasHit then
		flashHitmarker(wasKill, wasHeadshot)
	end
end)

KillFeed.OnClientEvent:Connect(function(killerName: string, victimName: string, headshot: boolean, isWin: boolean)
	if isWin then
		banner.Text = string.format("%s WINS!", string.upper(killerName))
		banner.Visible = true
		task.delay(5, function()
			banner.Visible = false
		end)
	else
		addFeed(string.format("%s  ✕  %s%s", killerName, victimName, if headshot then "  (HEADSHOT)" else ""))
	end
end)

-- Health + crosshair spread loop
local spreadExtra = 0
RunService.RenderStepped:Connect(function(dt)
	spreadExtra = math.max(0, spreadExtra - dt * 60)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local moveSpread = 0
	if hum and hum.MoveDirection.Magnitude > 0.1 then
		moveSpread = 6
	end
	local g = 8 + moveSpread + spreadExtra
	top.Position = UDim2.fromOffset(0, -g - armLen / 2)
	bottom.Position = UDim2.fromOffset(0, g + armLen / 2)
	left.Position = UDim2.fromOffset(-g - armLen / 2, 0)
	right.Position = UDim2.fromOffset(g + armLen / 2, 0)

	if hum then
		local frac = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
		healthFill.Size = UDim2.fromScale(frac, 1)
		healthFill.BackgroundColor3 = if frac > 0.5 then Color3.fromRGB(80, 200, 100)
			elseif frac > 0.25 then Color3.fromRGB(230, 180, 60)
			else Color3.fromRGB(220, 60, 60)
		healthLabel.Text = tostring(math.ceil(hum.Health))
	end
end)

-- Expand crosshair on click (feedback)
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input, gpe)
	if not gpe and input.UserInputType == Enum.UserInputType.MouseButton1 then
		spreadExtra = 10
	end
end)
