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

local TEMP_ROLES_KEY = "KitsTempRoles"

local function getTempRolesData()
    return ModData.getOrCreate(TEMP_ROLES_KEY)
end

local function getPlayerKey(player)
    local steamId = player:getSteamID()
    if not steamId or steamId == "" then
        steamId = player:getUsername()
    end
    return tostring(steamId)
end

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

function KitsPermissions.GetTempRole(player)
    local data = getTempRolesData()
    local key = getPlayerKey(player)
    local entry = data[key]
    if not entry then return nil end
    local now = os.time()
    if entry.expires <= now then
        data[key] = nil
        ModData.transmit(TEMP_ROLES_KEY)
        return nil
    end
    return entry
end

function KitsPermissions.SetTempRole(player, roleName, days)
    local data = getTempRolesData()
    local key = getPlayerKey(player)
    data[key] = {
        role = roleName:lower(),
        expires = os.time() + (days * 86400),
        playerName = player:getUsername(),
    }
    ModData.transmit(TEMP_ROLES_KEY)
end

function KitsPermissions.RemoveTempRole(player)
    local data = getTempRolesData()
    local key = getPlayerKey(player)
    if data[key] then
        data[key] = nil
        ModData.transmit(TEMP_ROLES_KEY)
        return true
    end
    return false
end

function KitsPermissions.GetAllTempRoles()
    local data = getTempRolesData()
    local now = os.time()
    local result = {}
    local expired = {}
    for key, entry in pairs(data) do
        if entry.expires and entry.expires > now then
            local remaining = entry.expires - now
            local daysLeft = math.ceil(remaining / 86400)
            table.insert(result, {
                playerName = entry.playerName or key,
                role = entry.role,
                daysLeft = daysLeft,
            })
        else
            table.insert(expired, key)
        end
    end
    for _, key in ipairs(expired) do
        data[key] = nil
    end
    if #expired > 0 then
        ModData.transmit(TEMP_ROLES_KEY)
    end
    return result
end

function KitsPermissions.GetEffectiveLevel(player)
    local serverRole = getPlayerRoleName(player)
    local serverLevel = getRoleLevel(serverRole)
    local tempEntry = KitsPermissions.GetTempRole(player)
    if tempEntry then
        local tempLevel = getRoleLevel(tempEntry.role)
        if tempLevel > serverLevel then
            return tempLevel
        end
    end
    return serverLevel
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
    local playerLevel = KitsPermissions.GetEffectiveLevel(player)
    local requiredLevel = ROLE_LEVEL[perm] or 0
    return playerLevel >= requiredLevel
end

function KitsPermissions.GetPlayerPermissionsMap(player)
    local result = {}
    local playerLevel = KitsPermissions.GetEffectiveLevel(player)
    for _, kit in ipairs(KitsConfig.Kits) do
        local perm = kit.permission or "all"
        if perm == "all" then
            result[kit.id] = 1
        else
            local requiredLevel = ROLE_LEVEL[perm] or 0
            if playerLevel >= requiredLevel then
                result[kit.id] = 1
            else
                result[kit.id] = 0
            end
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
