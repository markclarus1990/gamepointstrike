-- GAMEPOINT STRIKE - FPSCamera (true first-person, hide head/real arms locally)
-- Explorer path: StarterPlayer > StarterCharacterScripts > FPSCamera (LocalScript)
-- Why: we show a fake viewmodel (see GunClient), so hide the real
-- Head + arms + Tool Handle ONLY on your screen. Others still see you.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
player.CameraMode = Enum.CameraMode.LockFirstPerson
-- Note: script is cloned into Character on spawn, so we always use
-- player.Character in RenderStepped below (no cached reference).

local function hideFirstPersonParts(char: Model)
	for _, desc in char:GetDescendants() do
		if desc:IsA("BasePart") then
			-- R6 names: Head, Left Arm, Right Arm. R15: Head, LeftUpperArm, etc + Hands
			if desc.Name == "Head"
				or desc.Name == "Left Arm"
				or desc.Name == "Right Arm"
				or desc.Name:find("UpperArm")
				or desc.Name:find("LowerArm")
				or desc.Name:find("Hand")
				or desc.Name == "Handle" -- Tool handle: hide locally, viewmodel replaces it
			then
				desc.LocalTransparencyModifier = 1
				-- Hats/face still attach to invisible head, hide those too if on Head
			end
			if desc.Name == "Head" then
				-- Hide face decal locally (keeps others' view intact)
				for _, decal in desc:GetChildren() do
					if decal:IsA("Decal") then
						decal.LocalTransparencyModifier = 1
					end
				end
			end
		elseif desc:IsA("Accessory") then
			local handle = desc:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				-- Only hide hats that sit on head (avoid hiding backpacks others see? local only anyway)
				if desc.Name:lower():find("hat") or desc.Name:lower():find("hair") or desc.Name:lower():find("face") then
					handle.LocalTransparencyModifier = 1
				end
			end
		end
	end
end

-- Re-apply every frame (Tools re-add Handle on equip, R15 parts reset)
RunService.RenderStepped:Connect(function()
	local char = player.Character
	if char and char.Parent then
		hideFirstPersonParts(char)
	end
	-- Lock zoom to first person
	if player.CameraMinZoomDistance ~= 0.5 then
		player.CameraMinZoomDistance = 0.5
	end
	if player.CameraMaxZoomDistance < 0.5 then
		player.CameraMaxZoomDistance = 10
	end
end)
