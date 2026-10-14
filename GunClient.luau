-- GAMEPOINT STRIKE - GunClient
-- Explorer path: StarterPack > Rifle > GunClient (LocalScript)
-- Requires: ReplicatedStorage > GunConfig (ModuleScript)
--           ReplicatedStorage > Remotes > Shoot (RemoteEvent)
--           ReplicatedStorage > Remotes > HitConfirm (RemoteEvent)
--           Tool "Rifle" with a Part named "Handle" inside it.
-- This builds the arms + rifle viewmodel entirely in code. No manual modeling.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local tool: Tool = script.Parent
tool.RequiresHandle = true
tool.CanBeDropped = false

local GunConfig = require(ReplicatedStorage:WaitForChild("GunConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShootRemote: RemoteEvent = Remotes:WaitForChild("Shoot")
local HitConfirmRemote: RemoteEvent = Remotes:WaitForChild("HitConfirm")

-- State
local equipped = false
local mouseDown = false
local reloading = false
local ammo = GunConfig.MagSize
local lastShotTime = 0
local bobTime = 0
local recoil = 0 -- 0..1 spring
local viewmodel: Model? = nil
local parts: { [string]: BasePart } = {}
local renderConn: RBXScriptConnection? = nil
local hitConn: RBXScriptConnection? = nil
local humanoid: Humanoid? = nil
local character: Model? = nil

-- Sounds: created in code so you don't need Toolbox IDs for v1.
-- Replace SoundIds later with your own rifle sounds.
local function getOrCreateSound(parent: Instance, name: string, soundId: string, volume: number): Sound
	local s = parent:FindFirstChild(name)
	if s and s:IsA("Sound") then
		return s
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Volume = volume
	sound.RollOffMaxDistance = 200
	sound.Parent = parent
	return sound
end

local function getSkinColor(): Color3
	if character then
		local head = character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			return head.Color
		end
		local bodyColors = character:FindFirstChildOfClass("BodyColors")
		if bodyColors then
			return bodyColors.HeadColor3
		end
	end
	return Color3.fromRGB(245, 205, 165)
end

local function makePart(name: string, size: Vector3, color: Color3, material: Enum.Material): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function buildViewmodel()
	cleanupViewmodel()
	character = player.Character
	if not character then
		return
	end
	humanoid = character:FindFirstChildOfClass("Humanoid")

	local skin = getSkinColor()
	local vm = Instance.new("Model")
	vm.Name = "RifleViewmodel"

	-- Rifle: body + barrel + grip + sight + muzzle tip
	local body = makePart("GunBody", Vector3.new(0.28, 0.32, 1.1), Color3.fromRGB(35, 37, 40), Enum.Material.SmoothPlastic)
	local barrel = makePart("GunBarrel", Vector3.new(0.14, 0.14, 0.9), Color3.fromRGB(20, 20, 22), Enum.Material.Metal)
	local grip = makePart("GunGrip", Vector3.new(0.22, 0.45, 0.25), Color3.fromRGB(55, 40, 25), Enum.Material.Wood)
	local mag = makePart("GunMag", Vector3.new(0.2, 0.4, 0.22), Color3.fromRGB(25, 25, 28), Enum.Material.SmoothPlastic)
	local sight = makePart("GunSight", Vector3.new(0.1, 0.18, 0.25), Color3.fromRGB(15, 15, 15), Enum.Material.Metal)
	local muzzleTip = makePart("Muzzle", Vector3.new(0.16, 0.16, 0.12), Color3.fromRGB(255, 200, 80), Enum.Material.Neon)
	muzzleTip.Transparency = 1 -- flash only on shoot

	-- Fake arms (right hand on grip, left hand forward)
	local rightArm = makePart("RightArm", Vector3.new(0.32, 0.32, 0.9), skin, Enum.Material.SmoothPlastic)
	local leftArm = makePart("LeftArm", Vector3.new(0.32, 0.32, 0.9), skin, Enum.Material.SmoothPlastic)
	local rightHand = makePart("RightHand", Vector3.new(0.3, 0.28, 0.3), skin, Enum.Material.SmoothPlastic)
	local leftHand = makePart("LeftHand", Vector3.new(0.3, 0.28, 0.3), skin, Enum.Material.SmoothPlastic)

	for _, p in { body, barrel, grip, mag, sight, muzzleTip, rightArm, leftArm, rightHand, leftHand } do
		p.Parent = vm
	end

	parts = {
		GunBody = body,
		GunBarrel = barrel,
		GunGrip = grip,
		GunMag = mag,
		GunSight = sight,
		Muzzle = muzzleTip,
		RightArm = rightArm,
		LeftArm = leftArm,
		RightHand = rightHand,
		LeftHand = leftHand,
	}

	vm.Parent = camera
	viewmodel = vm
	updateHUD()
end

function cleanupViewmodel()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	if viewmodel then
		viewmodel:Destroy()
		viewmodel = nil
	end
	parts = {}
end

-- Per-frame viewmodel positioning: base offset from camera + bob + recoil
local function onRenderStepped(dt: number)
	if not equipped or not viewmodel then
		return
	end
	if not character or not character.Parent then
		return
	end
	humanoid = humanoid or character:FindFirstChildOfClass("Humanoid")

	-- Bob: advance only when moving on ground
	local moving = false
	local airborne = true
	if humanoid then
		moving = humanoid.MoveDirection.Magnitude > 0.1
		airborne = humanoid.FloorMaterial == Enum.Material.Air
	end
	if moving and not airborne then
		bobTime += dt * GunConfig.BobSpeed
	else
		-- ease bob out
		bobTime += dt * 2.0 * (if moving then 1 else 0)
	end

	-- Recoil spring recovery
	recoil = math.max(0, recoil - dt * GunConfig.RecoilRecoverSpeed)

	local bobX = math.sin(bobTime * 1.0) * GunConfig.BobAmplitudeX * (if moving then 1 else 0.2)
	local bobY = math.abs(math.cos(bobTime * 1.0)) * GunConfig.BobAmplitudeY * (if moving then 1 else 0.2)

	-- Base gun position: right hip, slightly down, ~1.2 studs forward
	local base = camera.CFrame
		* CFrame.new(0.55, -0.42 + bobY, -1.15)
		* CFrame.new(bobX, 0, recoil * GunConfig.ViewmodelKickback)
		* CFrame.new(0, recoil * GunConfig.ViewmodelKickUp, 0)

	-- Offsets relative to base root
	local function setPart(name: string, offset: CFrame)
		local p = parts[name]
		if p then
			p.CFrame = base * offset
		end
	end

	setPart("GunBody", CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, 0))
	setPart("GunBarrel", CFrame.new(0, 0.03, -0.9))
	setPart("Muzzle", CFrame.new(0, 0.03, -1.35))
	setPart("GunGrip", CFrame.new(0, -0.32, 0.25) * CFrame.Angles(math.rad(12), 0, 0))
	setPart("GunMag", CFrame.new(0, -0.3, -0.25) * CFrame.Angles(math.rad(-8), 0, 0))
	setPart("GunSight", CFrame.new(0, 0.25, -0.05))
	setPart("RightHand", CFrame.new(0.02, -0.32, 0.25))
	setPart("RightArm", CFrame.new(0.28, -0.35, 0.75) * CFrame.Angles(math.rad(-8), math.rad(-12), 0))
	setPart("LeftHand", CFrame.new(-0.03, -0.08, -0.75))
	setPart("LeftArm", CFrame.new(-0.32, -0.3, -0.15) * CFrame.Angles(math.rad(-12), math.rad(14), 0))
end

function updateHUD()
	local ok, playerGui = pcall(function()
		return player:WaitForChild("PlayerGui")
	end)
	if not ok or not playerGui then
		return
	end
	local hud = playerGui:FindFirstChild("HUD")
	if not hud then
		return
	end
	local ammoLabel = hud:FindFirstChild("AmmoLabel", true)
	if ammoLabel and ammoLabel:IsA("TextLabel") then
		if reloading then
			ammoLabel.Text = "RELOADING..."
		else
			ammoLabel.Text = string.format("%d / %s", ammo, if GunConfig.InfiniteReserve then "∞" else "?")
		end
	end
end

local function createTracer(fromPos: Vector3, toPos: Vector3)
	local dist = (toPos - fromPos).Magnitude
	if dist < 0.5 then
		return
	end
	local tracer = Instance.new("Part")
	tracer.Name = "Tracer"
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = GunConfig.TracerColor
	tracer.Size = Vector3.new(GunConfig.TracerThickness, GunConfig.TracerThickness, dist)
	tracer.CFrame = CFrame.lookAt(fromPos:Lerp(toPos, 0.5), toPos)
	tracer.Parent = workspace
	Debris:AddItem(tracer, GunConfig.TracerLifetime)
end

local function muzzleWorldPos(): Vector3
	local m = parts["Muzzle"]
	if m then
		return m.Position
	end
	return camera.CFrame.Position + camera.CFrame.LookVector * 2
end

local function flashMuzzle()
	local m = parts["Muzzle"]
	if not m then
		return
	end
	m.Transparency = 0
	task.delay(GunConfig.MuzzleFlashTime, function()
		if m and m.Parent then
			m.Transparency = 1
		end
	end)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 100)
	light.Brightness = 2
	light.Range = 12
	light.Parent = m
	Debris:AddItem(light, GunConfig.MuzzleFlashTime)
end

local function currentSpreadDegrees(): number
	local s = GunConfig.BaseSpreadDegrees
	if humanoid then
		if humanoid.MoveDirection.Magnitude > 0.1 then
			s += GunConfig.MoveSpreadBonusDegrees
		end
		if humanoid.FloorMaterial == Enum.Material.Air then
			s += GunConfig.JumpSpreadBonusDegrees
		end
	end
	return s
end

local function canShoot(): boolean
	if not equipped or reloading then
		return false
	end
	if ammo <= 0 then
		return false
	end
	if tick() - lastShotTime < GunConfig.FireRate - 0.001 then
		return false
	end
	if not character or not character.Parent then
		return false
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return false
	end
	return true
end

local function shootOnce()
	if not canShoot() then
		if equipped and ammo <= 0 and not reloading then
			startReload()
		end
		return
	end
	lastShotTime = tick()
	ammo -= 1

	-- Build spread ray from camera center
	local spread = currentSpreadDegrees()
	local rx = math.rad((math.random() * 2 - 1) * spread)
	local ry = math.rad((math.random() * 2 - 1) * spread)
	local origin = camera.CFrame.Position
	local dirCF = CFrame.lookAt(origin, origin + camera.CFrame.LookVector) * CFrame.Angles(rx, ry, 0)
	local direction = dirCF.LookVector * GunConfig.Range

	-- Local visual raycast (for tracer endpoint only; server does real damage)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local filterList: { Instance } = { character }
	if viewmodel then
		table.insert(filterList, viewmodel)
	end
	local localChar = player.Character
	if localChar then
		-- ensure camera-attached parts ignored
		params.FilterDescendantsInstances = filterList
	end
	local result = workspace:Raycast(origin, direction, params)
	local hitPoint = if result then result.Position else origin + direction

	-- FX locally (no waiting on server)
	flashMuzzle()
	createTracer(muzzleWorldPos(), hitPoint)
	recoil = 1.0

	-- Camera kick (feel only; does not change server ray)
	local kick = math.rad(GunConfig.CameraKickDegrees + math.random() * 0.3)
	local yaw = math.rad((math.random() * 2 - 1) * GunConfig.CameraYawVarianceDegrees)
	camera.CFrame = camera.CFrame * CFrame.Angles(-kick, yaw, 0)

	-- Sounds locally
	local handle = tool:FindFirstChild("Handle")
	if handle then
		local shootSound = getOrCreateSound(handle, "Shoot", "rbxasset://sounds/electronicpingshort.wav", 0.8)
		shootSound:Play()
	end

	-- Authoritative damage: server re-raycasts
	ShootRemote:FireServer(origin, direction)
	updateHUD()

	if ammo == 0 then
		task.delay(0.25, function()
			if equipped then
				startReload()
			end
		end)
	end
end

function startReload()
	if reloading or not equipped then
		return
	end
	if ammo >= GunConfig.MagSize then
		return
	end
	reloading = true
	updateHUD()
	local handle = tool:FindFirstChild("Handle")
	if handle then
		local rs = getOrCreateSound(handle, "Reload", "rbxasset://sounds/unsheath.wav", 0.8)
		rs:Play()
	end
	task.delay(GunConfig.ReloadTime, function()
		if equipped then
			ammo = GunConfig.MagSize
			reloading = false
			updateHUD()
		else
			reloading = false
		end
	end)
end

local function fireLoop()
	while mouseDown and equipped do
		shootOnce()
		if not GunConfig.Automatic then
			break
		end
		-- sleep until next allowed shot
		local waitTime = math.max(0.01, GunConfig.FireRate - (tick() - lastShotTime))
		-- small spin so RenderStepped keeps running smoothly
		local t0 = os.clock()
		while os.clock() - t0 < waitTime do
			if not mouseDown or not equipped then
				break
			end
			RunService.Heartbeat:Wait()
		end
	end
end

-- Input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if not equipped then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseDown = true
		task.spawn(fireLoop)
	elseif input.KeyCode == Enum.KeyCode.R then
		startReload()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseDown = false
	end
end)

-- Touch support: tap = shoot, second finger handled by Tool.Activated
tool.Activated:Connect(function()
	if not GunConfig.Automatic then
		shootOnce()
	else
		-- mobile hold fires via Equipped touch; single tap at least shoots once
		if not mouseDown then
			shootOnce()
		end
	end
end)

tool.Equipped:Connect(function()
	character = player.Character
	equipped = true
	mouseDown = false
	reloading = false
	-- keep ammo persistent across respawns? reset to full on equip for v1 simplicity
	if ammo <= 0 then
		ammo = GunConfig.MagSize
	end
	buildViewmodel()
	if renderConn then
		renderConn:Disconnect()
	end
	renderConn = RunService.RenderStepped:Connect(onRenderStepped)
	-- hide default mouse icon, crosshair HUD takes over
	mouse.Icon = "rbxasset://textures/ArrowCursor.png"
	updateHUD()
end)

tool.Unequipped:Connect(function()
	equipped = false
	mouseDown = false
	reloading = false
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	cleanupViewmodel()
end)

player.CharacterAdded:Connect(function(char)
	character = char
	-- viewmodel rebuilt on next Equip; clean stale
	cleanupViewmodel()
	ammo = GunConfig.MagSize
end)

-- Hit feedback from server
hitConn = HitConfirmRemote.OnClientEvent:Connect(function(wasHit: boolean, wasKill: boolean, wasHeadshot: boolean)
	-- HUDClient listens too; this is fallback flash if HUD missing
	if wasHit then
		updateHUD()
	end
end)
