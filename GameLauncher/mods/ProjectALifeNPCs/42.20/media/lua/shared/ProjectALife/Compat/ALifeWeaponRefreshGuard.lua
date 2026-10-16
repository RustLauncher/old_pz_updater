ProjectALife = ProjectALife or {}
local Guard = {}
ProjectALife.WeaponRefreshGuard = Guard

function Guard.refresh(player, weapon)
    if player == nil or weapon == nil or not instanceof(player, "IsoPlayer") then return end
    if player:getPrimaryHandItem() ~= weapon and player:getSecondaryHandItem() ~= weapon then return end
    syncHandWeaponFields(player, weapon)
    player:resetEquippedHandsModels()
end

function Guard.install()
    if Guard.installed or type(getLoadedLuaCount) ~= "function"
            or type(getLoadedLua) ~= "function" or type(syncHandWeaponFields) ~= "function" then return false end
    for index = 0, getLoadedLuaCount() - 1 do
        local loaded = tostring(getLoadedLua(index) or ""):gsub("\\", "/")
        if loaded:match("/WeaponSystems/Utils/Animations%.lua$") then
            local api = require "WeaponSystems/Utils/Animations"
            if type(api) ~= "table" or type(api.CallSyncHandWeaponFields) ~= "function" then return false end
            api.CallSyncHandWeaponFields = Guard.refresh
            Guard.installed = true
            return true
        end
    end
    return false
end

if type(Events) == "table" then
    if Events.OnGameStart then Events.OnGameStart.Add(Guard.install) end
    if Events.OnServerStarted then Events.OnServerStarted.Add(Guard.install) end
end
return Guard
