-- GAMEPOINT STRIKE - Leaderboard (kills, deaths, win)
-- Explorer path: ServerScriptService > Leaderboard (Script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GunConfig = require(ReplicatedStorage:WaitForChild("GunConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local KillFeedRemote: RemoteEvent = Remotes:WaitForChild("KillFeed")

local resetting = false

local function onCharacterDied(player: Player, humanoid: Humanoid)
	local deaths = player.leaderstats and player.leaderstats:FindFirstChild("Deaths")
	if deaths and deaths:IsA("IntValue") then
		deaths.Value += 1
	end

	local killerUserId = humanoid:GetAttribute("LastHitBy")
	if typeof(killerUserId) ~= "number" then
		return
	end
	-- Ignore stale tags (>5s old, e.g. fall damage after fight)
	local hitTime = humanoid:GetAttribute("LastHitTime")
	if typeof(hitTime) == "number" and os.clock() - hitTime > 5 then
		return
	end
	local killer = Players:GetPlayerByUserId(killerUserId)
	if not killer or killer == player then
		return
	end
	local killerKills = killer.leaderstats and killer.leaderstats:FindFirstChild("Kills")
	if killerKills and killerKills:IsA("IntValue") then
		killerKills.Value += 1
		local headshot = humanoid:GetAttribute("LastHitHeadshot") == true
		KillFeedRemote:FireAllClients(killer.DisplayName, player.DisplayName, headshot, false)

		-- Win check
		if killerKills.Value >= GunConfig.KillsToWin and not resetting then
			resetting = true
			KillFeedRemote:FireAllClients(killer.DisplayName, "", false, true)
			task.delay(6, function()
				for _, p in Players:GetPlayers() do
					local ls = p:FindFirstChild("leaderstats")
					if ls then
						local k = ls:FindFirstChild("Kills")
						local d = ls:FindFirstChild("Deaths")
						if k and k:IsA("IntValue") then
							k.Value = 0
						end
						if d and d:IsA("IntValue") then
							d.Value = 0
						end
					end
					p:LoadCharacter()
				end
				resetting = false
			end)
		end
	end
end

local function setupPlayer(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local kills = Instance.new("IntValue")
	kills.Name = "Kills"
	kills.Value = 0
	kills.Parent = ls
	local deaths = Instance.new("IntValue")
	deaths.Name = "Deaths"
	deaths.Value = 0
	deaths.Parent = ls
	ls.Parent = player

	player.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid", 10)
		if hum and hum:IsA("Humanoid") then
			hum.Died:Connect(function()
				onCharacterDied(player, hum)
			end)
		end
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, p in Players:GetPlayers() do
	task.spawn(setupPlayer, p)
end
