-- GAMEPOINT STRIKE - BotConfig
-- Explorer path: ReplicatedStorage > BotConfig (ModuleScript)
-- Paste this entire file into that ModuleScript.
-- Single source of truth for all bot tuning. BotServer is the only reader.

local BotConfig = {
	-- Population
	BotCount = 3,
	RespawnDelay = 5, -- seconds after a bot dies before replacement spawns
	BotNamePrefix = "BOT",

	-- Body / survivability (matches rifle: 22 dmg body / 44 head)
	MaxHealth = 100, -- 5 body shots or 3 headshots to kill
	WalkSpeed = 12, -- player is 16, bots slightly slower so you can kite
	JumpPower = 50,

	-- Senses / combat
	DetectionRange = 90, -- studs: nearest alive player within this is chased
	AttackRange = 9, -- studs: melee range
	AttackDamage = 10, -- per hit on player
	AttackCooldown = 1.2, -- seconds between bot hits
	LoseTargetRange = 130, -- stop chasing beyond this (prevents cross-map runs)

	-- Performance / movement
	ThinkInterval = 0.5, -- seconds between AI decisions (NOT per-frame)
	UsePathfinding = true,
	PathRecomputeDistance = 30, -- use pathfinding beyond this distance
	MaxWaypoints = 6,
	WaypointTimeout = 2.0,

	-- Spawning
	SpawnFolderName = "BotSpawns", -- Workspace > BotSpawns (Folder)
	BotsFolderName = "Bots", -- Workspace > Bots (auto-created, holds live bots)
	FallbackToSpawnLocations = true, -- if BotSpawns missing, use regular SpawnLocations
	SpawnHeightOffset = 4,

	-- Look (enemies must be obvious)
	BodyColor = Color3.fromRGB(180, 30, 30), -- torso / limbs
	HeadColor = Color3.fromRGB(255, 140, 40),
	TagText = "ENEMY",
	TagColor = Color3.fromRGB(255, 40, 40),
}

return BotConfig
