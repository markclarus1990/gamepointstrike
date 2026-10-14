-- GAMEPOINT STRIKE - GunConfig
-- Explorer path: ReplicatedStorage > GunConfig (ModuleScript)
-- Paste this entire file into that ModuleScript.
-- Single source of truth for client + server. Do NOT duplicate values elsewhere.

local GunConfig = {
	-- Identity
	GunName = "Rifle",

	-- Damage (server-authoritative)
	Damage = 22,
	HeadshotMultiplier = 2.0, -- 44 on head
	Range = 500, -- studs max ray distance

	-- Fire control
	FireRate = 0.12, -- seconds between shots (500 RPM)
	Automatic = true,
	MagSize = 30,
	ReloadTime = 2.2,
	InfiniteReserve = true,

	-- Accuracy (degrees of random cone)
	BaseSpreadDegrees = 0.7,
	MoveSpreadBonusDegrees = 1.3, -- added when moving
	JumpSpreadBonusDegrees = 2.0, -- added when airborne

	-- Feel
	CameraKickDegrees = 0.85, -- camera pitches up per shot
	CameraYawVarianceDegrees = 0.25, -- random horizontal kick
	ViewmodelKickback = 0.22, -- studs gun pushes back
	ViewmodelKickUp = 0.07, -- studs gun pushes up
	RecoilRecoverSpeed = 7.0, -- higher = snappier return
	BobAmplitudeX = 0.035,
	BobAmplitudeY = 0.05,
	BobSpeed = 9.0,

	-- FX
	TracerColor = Color3.fromRGB(255, 220, 130),
	TracerThickness = 0.07,
	TracerLifetime = 0.07,
	MuzzleFlashTime = 0.05,

	-- Server validation (anti-exploit)
	-- Client sends Origin + Direction. Server re-raycasts from Head.
	MaxOriginOffsetFromHead = 15, -- studs, rejects teleport-aim
	RateTolerance = 0.06, -- allows FireRate - tolerance for ping jitter
	MinDirectionLength = 1,
	MaxDirectionLength = 600,

	-- Game rules
	KillsToWin = 20,
	RespawnTime = 3,
}

return GunConfig
