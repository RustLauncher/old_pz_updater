require "KitsConfig"

KitsPermissions = KitsPermissions or {}

local ROLE_LEVEL = {
    admin     = 100,
    moderator = 90,
    gm        = 80,
    observer  = 70,
    priority  = 60,
    ultimate  = 50,
    vip       = 40,
    user      = 10,
    banned    = 0,
}

local function getPlayerRoleName(player)
    local role = player:getRole()
    if role then
        local name = role:getName()
        if name and name ~= "" then
            return name:lower()
        end
    end
    return "user"
end

local function getRoleLevel(roleName)
    if not roleName or roleName == "" then return 10 end
    return ROLE_LEVEL[roleName:lower()] or 10
end

function KitsPermissions.IsAdmin(player)
    local roleName = getPlayerRoleName(player)
    return roleName == "admin" or roleName == "moderator"
end

function KitsPermissions.CanUseKit(player, kit)
    local perm = kit.permission or "all"
    if perm == "all" then
        return true
    end
    local roleName = getPlayerRoleName(player)
    local playerLevel = getRoleLevel(roleName)
    local requiredLevel = ROLE_LEVEL[perm] or 0
    return playerLevel >= requiredLevel
end

function KitsPermissions.GetPlayerPermissionsMap(player)
    local result = {}
    local roleName = getPlayerRoleName(player)
    local playerLevel = getRoleLevel(roleName)
    for _, kit in ipairs(KitsConfig.Kits) do
        local perm = kit.permission or "all"
        if perm == "all" then
            result[kit.id] = true
        else
            local requiredLevel = ROLE_LEVEL[perm] or 0
            result[kit.id] = playerLevel >= requiredLevel
        end
    end
    return result
end

function KitsPermissions.FindPlayerByName(name)
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:getUsername():lower() == name:lower() then
            return p
        end
    end
    return nil
end
