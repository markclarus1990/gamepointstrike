-- GAMEPOINT STRIKE - BotServer (server-authoritative enemy bots)
-- Explorer path: ServerScriptService > BotServer (Script, NOT LocalScript)
-- Requires:
--   ReplicatedStorage > BotConfig (ModuleScript)
--   ReplicatedStorage > GunConfig (ModuleScript, for KillsToWin)
--   ReplicatedStorage > Remotes > KillFeed (RemoteEvent) -- capital R "Remotes"
-- No changes needed to DamageServer: it already raycasts any Humanoid,
-- tags LastHitBy, and fires HitConfirm, so rifle hits + hitmarkers work on bots.
-- This script awards bot kills to the SAME leaderstats Kills + KillFeed HUD.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local BotConfig = require(ReplicatedStorage:WaitForChild("BotConfig"))
local GunConfig = require(ReplicatedStorage:WaitForChild("GunConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local KillFeedRemote: RemoteEvent = Remotes:WaitForChild("KillFeed")

-- Folders
local BotsFolder = workspace:FindFirstChild(BotConfig.BotsFolderName)
if not BotsFolder then
	BotsFolder = Instance.new("Folder")
	BotsFolder.Name = BotConfig.BotsFolderName
	BotsFolder.Parent = workspace
end

local nextBotId = 1
local activeBots: { [Model]: any } = {}
local winResetting = false

--------------------------------------------------------------------------------
-- Spawns
--------------------------------------------------------------------------------

local function getBotSpawnParts(): { BasePart }
	local folder = workspace:FindFirstChild(BotConfig.SpawnFolderName)
	local out = {}
	if folder and folder:IsA("Folder") then
		for _, d in folder:GetChildren() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
	end
	return out
end

local function getFallbackSpawns(): { SpawnLocation }
	local out = {}
	if BotConfig.FallbackToSpawnLocations then
		for _, d in workspace:GetDescendants() do
			if d:IsA("SpawnLocation") and d.Enabled then
				table.insert(out, d)
			end
		end
	end
	return out
end

local function pickSpawnCFrame(): CFrame?
	local parts = getBotSpawnParts()
	if #parts > 0 then
		local p = parts[math.random(1, #parts)]
		return p.CFrame + Vector3.new(0, BotConfig.SpawnHeightOffset, 0)
	end
	local falls = getFallbackSpawns()
	if #falls > 0 then
		local s = falls[math.random(1, #falls)]
		return s.CFrame + Vector3.new(math.random(-8, 8), BotConfig.SpawnHeightOffset, math.random(-8, 8))
	end
	warn("[GAMEPOINT STRIKE/Bots] No bot spawns found. Create Workspace > "
		.. BotConfig.SpawnFolderName
		.. " (Folder) with 2-4 anchored Parts inside, OR enable SpawnLocations.")
	return nil
end

--------------------------------------------------------------------------------
-- Targeting helpers (server-side, no client trust)
--------------------------------------------------------------------------------

local function findNearestPlayer(fromPos: Vector3): (Model?, Humanoid?, BasePart?, number?)
	local bestChar: Model? = nil
	local bestHum: Humanoid? = nil
	local bestRoot: BasePart? = nil
	local bestDist: number? = nil
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		if char and char.Parent then
			local hum = char:FindFirstChildOfClass("Humanoid")
			local root = char:FindFirstChild("HumanoidRootPart")
			if hum and root and root:IsA("BasePart") and hum.Health > 0 then
				local d = (root.Position - fromPos).Magnitude
				if d <= BotConfig.DetectionRange and (bestDist == nil or d < bestDist) then
					bestChar, bestHum, bestRoot, bestDist = char, hum, root, d
				end
			end
		end
	end
	return bestChar, bestHum, bestRoot, bestDist
end

-- True if no WALL between bot head and target. Other bots don't block.
local function hasLOS(fromPos: Vector3, targetChar: Model, botModel: Model): boolean
	local head = targetChar:FindFirstChild("Head")
	local root = targetChar:FindFirstChild("HumanoidRootPart")
	local toPos: Vector3? = nil
	if head and head:IsA("BasePart") then
		toPos = head.Position
	elseif root and root:IsA("BasePart") then
		toPos = root.Position
	end
	if not toPos then
		return false
	end
	local dir = toPos - fromPos
	if dir.Magnitude < 1 then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = { botModel }
	local res = workspace:Raycast(fromPos, dir, params)
	if not res then
		return true -- open air
	end
	-- Hit the target itself -> clear
	if res.Instance:IsDescendantOf(targetChar) then
		return true
	end
	-- Hit another bot -> don't count as a wall
	local hitModel = res.Instance:FindFirstAncestorOfClass("Model")
	if hitModel and hitModel:GetAttribute("IsBot") == true then
		return true
	end
	return false -- wall / cover / baseplate
end

local function getOrCreateSound(parent: Instance, name: string): Sound
	local s = parent:FindFirstChild(name)
	if s and s:IsA("Sound") then
		return s
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxasset://sounds/swordslash.wav" -- placeholder melee thud
	sound.Volume = 0.6
	sound.RollOffMaxDistance = 120
	sound.Parent = parent
	return sound
end

--------------------------------------------------------------------------------
-- Kill awards (server-authoritative, no client kill events)
--------------------------------------------------------------------------------

local function checkWin(killer: Player)
	local ls = killer:FindFirstChild("leaderstats")
	local k = ls and ls:FindFirstChild("Kills")
	if not (k and k:IsA("IntValue")) then
		return
	end
	if k.Value >= GunConfig.KillsToWin and not winResetting then
		winResetting = true
		KillFeedRemote:FireAllClients(killer.DisplayName, "", false, true)
		task.delay(6, function()
			for _, p in Players:GetPlayers() do
				local pls = p:FindFirstChild("leaderstats")
				if pls then
					local kk = pls:FindFirstChild("Kills")
					local dd = pls:FindFirstChild("Deaths")
					if kk and kk:IsA("IntValue") then
						kk.Value = 0
					end
					if dd and dd:IsA("IntValue") then
						dd.Value = 0
					end
				end
				p:LoadCharacter()
			end
			winResetting = false
		end)
	end
end

local function awardBotKill(humanoid: Humanoid, botName: string)
	local killerId = humanoid:GetAttribute("LastHitBy")
	if typeof(killerId) ~= "number" then
		return -- died without rifle tag (fell, bot stuck): no award, no dupe
	end
	local hitTime = humanoid:GetAttribute("LastHitTime")
	if typeof(hitTime) == "number" and os.clock() - hitTime > 5 then
		return -- stale tag, don't award
	end
	local killer = Players:GetPlayerByUserId(killerId)
	if not killer or not killer.Parent then
		return
	end
	local ls = killer:FindFirstChild("leaderstats")
	local kills = ls and ls:FindFirstChild("Kills")
	if kills and kills:IsA("IntValue") then
		kills.Value += 1
		local headshot = humanoid:GetAttribute("LastHitHeadshot") == true
		-- Same KillFeed signature HUDClient already handles: white feed line.
		-- Bot kills show as "Player  ✕  BOT-1". Red banner only on win.
		KillFeedRemote:FireAllClients(killer.DisplayName, botName, headshot, false)
		checkWin(killer)
	end
end

--------------------------------------------------------------------------------
-- Bot construction (full R15 rig = real Head for headshots, real Humanoid)
--------------------------------------------------------------------------------

local function addEnemyTag(model: Model, label: string)
	local head = model:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "EnemyTag"
	gui.Size = UDim2.fromOffset(120, 36)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = true
	gui.Parent = head
	local bg = Instance.new("TextLabel")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(20, 0, 0)
	bg.BackgroundTransparency = 0.3
	bg.Font = Enum.Font.GothamBlack
	bg.TextSize = 15
	bg.TextColor3 = BotConfig.TagColor
	bg.TextStrokeTransparency = 0.4
	bg.Text = BotConfig.TagText .. " " .. label
	bg.Parent = gui
end

local function buildBotModel(botName: string): (Model?, Humanoid?, BasePart?)
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = BotConfig.HeadColor
	desc.TorsoColor = BotConfig.BodyColor
	desc.LeftArmColor = BotConfig.BodyColor
	desc.RightArmColor = BotConfig.BodyColor
	desc.LeftLegColor = Color3.fromRGB(40, 40, 45)
	desc.RightLegColor = Color3.fromRGB(40, 40, 45)

	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[GAMEPOINT STRIKE/Bots] Failed to create rig for " .. botName)
		return nil, nil, nil
	end
	model.Name = botName
	model:SetAttribute("IsBot", true)

	local humanoid = model:WaitForChild("Humanoid", 5)
	local root = model:WaitForChild("HumanoidRootPart", 5)
	if not (humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
		warn("[GAMEPOINT STRIKE/Bots] Rig missing Humanoid/Root for " .. botName)
		model:Destroy()
		return nil, nil, nil
	end

	humanoid.MaxHealth = BotConfig.MaxHealth
	humanoid.Health = BotConfig.MaxHealth
	humanoid.WalkSpeed = BotConfig.WalkSpeed
	humanoid.JumpPower = BotConfig.JumpPower
	humanoid.DisplayName = botName

	-- Don't let bots collide-push players or get stuck on each other.
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
		end
	end

	addEnemyTag(model, botName)
	return model, humanoid, root
end

--------------------------------------------------------------------------------
-- Movement
--------------------------------------------------------------------------------

local function followPath(humanoid: Humanoid, root: BasePart, targetPos: Vector3): boolean
	if not BotConfig.UsePathfinding then
		humanoid:MoveTo(targetPos)
		return true
	end
	local path: Path
	local ok = pcall(function()
		path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,
			AgentCanClimb = false,
		})
		path:ComputeAsync(root.Position, targetPos)
	end)
	if not ok or not path or path.Status ~= Enum.PathStatus.Success then
		humanoid:MoveTo(targetPos) -- fallback: straight line
		return false
	end
	local waypoints = path:GetWaypoints()
	local count = math.min(#waypoints, BotConfig.MaxWaypoints + 1)
	if count < 2 then
		humanoid:MoveTo(targetPos)
		return true
	end
	for i = 2, count do
		if humanoid.Health <= 0 or not root.Parent then
			return false
		end
		local wp = waypoints[i]
		humanoid:MoveTo(wp.Position)
		if wp.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		local t0 = os.clock()
		while os.clock() - t0 < BotConfig.WaypointTimeout do
			if humanoid.Health <= 0 or not root.Parent then
				return false
			end
			if (root.Position - wp.Position).Magnitude < 4 then
				break
			end
			task.wait(0.15)
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- AI loop (one lightweight thread per bot, 0.5s think, no per-frame work)
--------------------------------------------------------------------------------

local function runAI(entry: any, model: Model, humanoid: Humanoid, root: BasePart)
	local idleSince = os.clock()
	while entry.Alive and model.Parent and humanoid.Health > 0 do
		local targetChar, targetHum, targetRoot, dist = findNearestPlayer(root.Position)

		if not targetChar or not targetHum or not targetRoot or not dist or dist > BotConfig.LoseTargetRange then
			-- Idle: small wander so bots don't stack, then re-think
			if os.clock() - idleSince > 3 then
				idleSince = os.clock()
				local wander = root.Position + Vector3.new(math.random(-14, 14), 0, math.random(-14, 14))
				humanoid:MoveTo(wander)
			end
			task.wait(BotConfig.ThinkInterval)
			continue
		end
		idleSince = os.clock()

		-- Out-of-world safety
		if root.Position.Y < -60 then
			humanoid.Health = 0
			break
		end

		if dist <= BotConfig.AttackRange then
			local head = model:FindFirstChild("Head")
			local fromPos = if head and head:IsA("BasePart") then head.Position else root.Position
			if hasLOS(fromPos, targetChar, model) then
				-- Attack with cooldown, respect spawn protection
				if targetChar:FindFirstChildOfClass("ForceField") == nil and targetHum.Health > 0 then
					if os.clock() - entry.LastAttack >= BotConfig.AttackCooldown then
						entry.LastAttack = os.clock()
						targetHum:TakeDamage(BotConfig.AttackDamage)
						local h = model:FindFirstChild("Head")
						if h then
							getOrCreateSound(h, "BotHit"):Play()
						end
					end
				end
				-- Face the player while brawling
				humanoid:MoveTo(targetRoot.Position)
				task.wait(BotConfig.AttackCooldown * 0.5)
			else
				-- In range but behind wall: push through doorway via pathfind
				followPath(humanoid, root, targetRoot.Position)
			end
		elseif dist > BotConfig.PathRecomputeDistance then
			followPath(humanoid, root, targetRoot.Position)
		else
			humanoid:MoveTo(targetRoot.Position)
			task.wait(BotConfig.ThinkInterval)
		end
	end
end

--------------------------------------------------------------------------------
-- Spawn / death / respawn (keeps BotCount consistent)
--------------------------------------------------------------------------------

local function spawnBot()
	local botName = string.format("%s-%d", BotConfig.BotNamePrefix, nextBotId)
	nextBotId += 1

	local spawnCF = pickSpawnCFrame()
	if not spawnCF then
		task.delay(BotConfig.RespawnDelay, spawnBot) -- retry later, keep trying
		return
	end

	local model, humanoid, root = buildBotModel(botName)
	if not (model and humanoid and root) then
		task.delay(BotConfig.RespawnDelay, spawnBot)
		return
	end

	model:PivotTo(spawnCF)
	model.Parent = BotsFolder

	local entry = {
		Name = botName,
		Humanoid = humanoid,
		Root = root,
		Alive = true,
		Awarded = false,
		LastAttack = 0,
		SpawnCF = spawnCF,
	}
	activeBots[model] = entry

	-- Death: award once, clean up, respawn replacement
	local diedConn: RBXScriptConnection
	diedConn = humanoid.Died:Connect(function()
		if entry.Awarded then
			return
		end
		entry.Awarded = true
		entry.Alive = false
		activeBots[model] = nil
		-- DamageServer set these attributes on the killing shot
		pcall(awardBotKill, humanoid, botName)
		Debris:AddItem(model, 4) -- leave corpse briefly, then auto-clean
		if diedConn then
			task.delay(5, function()
				pcall(function()
					diedConn:Disconnect()
				end)
			end)
		end
		task.delay(BotConfig.RespawnDelay, spawnBot) -- keep count consistent
	end)

	-- Safety: if model removed without Died (cleanup/reset), respawn
	model.Destroying:Connect(function()
		if not entry.Awarded then
			entry.Awarded = true
			entry.Alive = false
			activeBots[model] = nil
			task.delay(BotConfig.RespawnDelay, spawnBot)
		end
	end)

	task.spawn(runAI, entry, model, humanoid, root)
end

-- Boot with stagger so pathfinding doesn't spike
for i = 1, BotConfig.BotCount do
	task.delay((i - 1) * 0.5, spawnBot)
end

print(string.format("[GAMEPOINT STRIKE/Bots] BotServer started, target %d bots.", BotConfig.BotCount))
