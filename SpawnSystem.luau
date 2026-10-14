-- GAMEPOINT STRIKE - SpawnSystem
-- Explorer path: ServerScriptService > SpawnSystem (Script)
-- Requires: at least 2 SpawnLocation objects in Workspace.
-- Gives brief spawn protection so arena fights feel fair.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GunConfig = require(ReplicatedStorage:WaitForChild("GunConfig"))

Players.RespawnTime = GunConfig.RespawnTime
Players.CharacterAutoLoads = true

local function getSpawns(): { SpawnLocation }
	local spawns = {}
	for _, desc in workspace:GetDescendants() do
		if desc:IsA("SpawnLocation") and desc.Enabled then
			table.insert(spawns, desc)
		end
	end
	return spawns
end

local function spawnCharacter(player: Player, char: Model)
	-- Wait a frame so character parts exist
	task.wait(0.1)
	local spawns = getSpawns()
	if #spawns == 0 then
		warn("[GAMEPOINT STRIKE] No enabled SpawnLocations found. Add 4-6 SpawnLocations.")
		return
	end
	local spawn = spawns[math.random(1, #spawns)]
	local root = char:WaitForChild("HumanoidRootPart", 5)
	if root and root:IsA("BasePart") then
		root.CFrame = spawn.CFrame + Vector3.new(0, 4, 0)
	end
	-- Spawn protection
	local ff = Instance.new("ForceField")
	ff.Visible = false
	ff.Parent = char
	task.delay(2, function()
		if ff and ff.Parent then
			ff:Destroy()
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		spawnCharacter(player, char)
	end)
	-- First spawn
	if not player.Character or not player.Character.Parent then
		player:LoadCharacter()
	end
end)
