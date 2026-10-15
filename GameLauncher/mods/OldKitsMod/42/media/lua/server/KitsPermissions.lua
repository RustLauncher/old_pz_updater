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

local function getPlayerRoleName(player)
    local role = player:getRole()
    if role then
        local name = role:getName()
        if name and name ~= "" and name:lower() ~= "none" then
            return name:lower()
        end
    end
    return "user"
end

local function getRoleLevel(roleName)
    if not roleName or roleName == "" then return 10 end
    return ROLE_LEVEL[roleName:lower()] or 10
end

local function sendExecSetRole(adminPlayer, targetName, roleName)
    sendServerCommand(adminPlayer, "Kits", "execSetRole", {
        targetName = targetName,
        roleName = roleName,
    })
end

local function findAnyAdmin()
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        local role = getPlayerRoleName(p)
        if role == "admin" or role == "moderator" then
            return p
        end
    end
    return nil
end

local function getEffectiveRole(player)
    local username = player:getUsername()
    local data = getTempRolesData()
    local entry = data[username]
    if entry and type(entry) == "table" and entry.expires then
        local expires = tonumber(entry.expires)
        if expires and expires <= os.time() then
            return "user"
        end
    end
    return getPlayerRoleName(player)
end

function KitsPermissions.SetTempRole(adminPlayer, target, roleName, days)
    local data = getTempRolesData()
    local targetName = target:getUsername()
    data[targetName] = {
        role = roleName:lower(),
        expires = os.time() + (days * 86400),
        playerName = targetName,
    }
    ModData.transmit(TEMP_ROLES_KEY)
    sendExecSetRole(adminPlayer, targetName, roleName)
end

function KitsPermissions.SetTempRoleOffline(targetName, roleName, days)
    local data = getTempRolesData()
    data[targetName] = {
        role = roleName:lower(),
        expires = os.time() + (days * 86400),
        playerName = targetName,
    }
    ModData.transmit(TEMP_ROLES_KEY)
end

function KitsPermissions.RemoveTempRole(adminPlayer, target)
    local data = getTempRolesData()
    local targetName = target:getUsername()
    if data[targetName] then
        data[targetName] = nil
        ModData.transmit(TEMP_ROLES_KEY)
        sendExecSetRole(adminPlayer, targetName, "user")
        return true
    end
    return false
end

function KitsPermissions.RemoveTempRoleOffline(targetName)
    local data = getTempRolesData()
    local found = false
    if data[targetName] then
        data[targetName] = nil
        found = true
    end
    for key, entry in pairs(data) do
        if type(entry) == "table" and entry.playerName == targetName then
            data[key] = nil
            found = true
        end
    end
    if found then
        ModData.transmit(TEMP_ROLES_KEY)
    end
    return found
end

function KitsPermissions.SweepExpiredRoles(adminPlayer)
    local data = getTempRolesData()
    local now = os.time()
    local swept = false
    for key, entry in pairs(data) do
        if type(entry) == "table" then
            local expires = tonumber(entry.expires)
            if expires and expires <= now then
                local targetName = entry.playerName or key
                sendExecSetRole(adminPlayer, targetName, "user")
                data[key] = nil
                swept = true
            end
        end
    end
    if swept then
        ModData.transmit(TEMP_ROLES_KEY)
    end
end

function KitsPermissions.GetTempRoleInfo(username)
    local data = getTempRolesData()
    local entry = data[username]
    if not entry or type(entry) ~= "table" then return nil end
    local expires = tonumber(entry.expires)
    if not expires or not entry.role then return nil end
    local remaining = expires - os.time()
    if remaining <= 0 then
        return { role = entry.role, daysLeft = 0, expired = true }
    end
    return {
        role = entry.role,
        daysLeft = math.ceil(remaining / 86400),
    }
end

function KitsPermissions.GetAllTempRoles()
    local data = getTempRolesData()
    local now = os.time()
    local result = {}
    for key, entry in pairs(data) do
        if type(entry) == "table" and entry.role then
            local expires = tonumber(entry.expires)
            if expires and expires > now then
                local remaining = expires - now
                table.insert(result, {
                    playerName = entry.playerName or key,
                    role = entry.role,
                    daysLeft = math.ceil(remaining / 86400),
                })
            end
        end
    end
    return result
end

function KitsPermissions.GetPlayerLevel(player)
    local role = getEffectiveRole(player)
    return getRoleLevel(role)
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
    local playerLevel = KitsPermissions.GetPlayerLevel(player)
    local requiredLevel = ROLE_LEVEL[perm] or 0
    return playerLevel >= requiredLevel
end

function KitsPermissions.GetPlayerPermissionsMap(player)
    local result = {}
    local playerLevel = KitsPermissions.GetPlayerLevel(player)
    for _, kit in ipairs(KitsConfig.Kits) do
        local perm = kit.permission or "all"
        if perm == "all" then
            result[kit.id] = "yes"
        else
            local requiredLevel = ROLE_LEVEL[perm] or 0
            if playerLevel >= requiredLevel then
                result[kit.id] = "yes"
            else
                result[kit.id] = "no"
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

function KitsPermissions.CleanCorruptEntries()
    local data = getTempRolesData()
    local toRemove = {}
    for key, entry in pairs(data) do
        if type(entry) ~= "table" or not entry.role or not entry.expires then
            table.insert(toRemove, key)
        end
    end
    for _, key in ipairs(toRemove) do
        print("[KitsPerms] Removing corrupt entry: " .. tostring(key))
        data[key] = nil
    end
    if #toRemove > 0 then
        ModData.transmit(TEMP_ROLES_KEY)
    end
end
