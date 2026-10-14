-- GAMEPOINT STRIKE - DamageServer (server-authoritative)
-- Explorer path: ServerScriptService > DamageServer (Script, NOT LocalScript)
-- Requires: ReplicatedStorage > GunConfig, ReplicatedStorage > Remotes (Folder)
--           with RemoteEvents: Shoot, HitConfirm, KillFeed
-- Create those Remotes manually BEFORE Play (see setup steps).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local GunConfig = require(ReplicatedStorage:WaitForChild("GunConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShootRemote: RemoteEvent = Remotes:WaitForChild("Shoot")
local HitConfirmRemote: RemoteEvent = Remotes:WaitForChild("HitConfirm")

-- Per-player rate limit
local lastShot: { [Player]: number } = {}

local function getOrCreateSound(parent: Instance, name: string): Sound
	local s = parent:FindFirstChild(name)
	if s and s:IsA("Sound") then
		return s
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	-- Placeholder that always exists. Replace with your rifle ID later.
	sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	sound.Volume = 0.6
	sound.RollOffMaxDistance = 180
	sound.Parent = parent
	return sound
end

local function serverTracer(fromPos: Vector3, toPos: Vector3)
	local dist = (toPos - fromPos).Magnitude
	if dist < 1 or dist > GunConfig.Range + 10 then
		return
	end
	local p = Instance.new("Part")
	p.Name = "ServerTracer"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = GunConfig.TracerColor
	p.Size = Vector3.new(GunConfig.TracerThickness, GunConfig.TracerThickness, dist)
	p.CFrame = CFrame.lookAt(fromPos:Lerp(toPos, 0.5), toPos)
	p.Parent = workspace
	Debris:AddItem(p, 0.09)
end

ShootRemote.OnServerEvent:Connect(function(shooter: Player, origin: any, direction: any)
	-- 1. Type validation (exploit guard)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	local dirLen = direction.Magnitude
	if dirLen < GunConfig.MinDirectionLength or dirLen > GunConfig.MaxDirectionLength then
		return
	end

	-- 2. Character validation
	local character = shooter.Character
	if not character or not character.Parent then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local head = character:FindFirstChild("Head")
	if not humanoid or not head or humanoid.Health <= 0 then
		return
	end
	if not head:IsA("BasePart") then
		return
	end

	-- Must have Rifle equipped (Tool moves to Character on equip)
	local hasRifle = character:FindFirstChild("Rifle") ~= nil
	if not hasRifle then
		return
	end

	-- 3. Origin must be near Head (prevents shooting from across map)
	local headPos: Vector3 = (head :: BasePart).Position
	if (origin - headPos).Magnitude > GunConfig.MaxOriginOffsetFromHead then
		return
	end

	-- 4. Rate limit (server-authoritative fire rate)
	local now = os.clock()
	local last = lastShot[shooter] or 0
	if now - last < GunConfig.FireRate - GunConfig.RateTolerance then
		return
	end
	lastShot[shooter] = now

	-- 5. Re-raycast on server. Force origin to Head so wall-hacks fail.
	local unitDir = direction.Unit
	local serverOrigin = headPos + unitDir * 1.5 -- start slightly in front to avoid self-hit
	local serverDir = unitDir * GunConfig.Range

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = { character }

	local result = workspace:Raycast(serverOrigin, serverDir, params)
	local hitPoint = if result then result.Position else serverOrigin + serverDir

	-- Replicate FX for OTHER players (shooter already did local FX)
	serverTracer(serverOrigin, hitPoint)
	local headSound = getOrCreateSound(head, "ServerShoot")
	headSound:Play()

	if not result then
		return
	end

	local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
	if not hitModel then
		return
	end
	local hitHumanoid = hitModel:FindFirstChildOfClass("Humanoid")
	if not hitHumanoid or hitHumanoid.Health <= 0 then
		return
	end

	-- No self-damage
	local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
	if hitPlayer and hitPlayer == shooter then
		return
	end

	-- Spawn protection: skip damage if victim has ForceField
	if hitModel:FindFirstChildOfClass("ForceField") then
		HitConfirmRemote:FireClient(shooter, false, false, false)
		return
	end

	-- 6. Damage
	local isHeadshot = result.Instance.Name == "Head"
	local dmg = GunConfig.Damage * (if isHeadshot then GunConfig.HeadshotMultiplier else 1.0)

	-- Tag killer for Leaderboard (works even with delayed death)
	hitHumanoid:SetAttribute("LastHitBy", shooter.UserId)
	hitHumanoid:SetAttribute("LastHitHeadshot", isHeadshot)
	hitHumanoid:SetAttribute("LastHitTime", os.clock())

	hitHumanoid:TakeDamage(dmg)

	local killed = hitHumanoid.Health <= 0
	HitConfirmRemote:FireClient(shooter, true, killed, isHeadshot)
end)

Players.PlayerRemoving:Connect(function(p)
	lastShot[p] = nil
end)
