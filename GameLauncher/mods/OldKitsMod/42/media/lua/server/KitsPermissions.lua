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
    local id = player:getSteamID()
    if id and id ~= "" and id ~= "0" then
        return tostring(id)
    end
    return player:getUsername()
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

function KitsPermissions.SetTempRole(player, roleName, days)
    local data = getTempRolesData()
    local key = getPlayerKey(player)
    data[key] = {
        role = roleName:lower(),
        expires = os.time() + (days * 86400),
        playerName = player:getUsername(),
    }
    ModData.transmit(TEMP_ROLES_KEY)
    player:setAccessLevel(roleName)
end

function KitsPermissions.SetTempRoleOffline(targetName, roleName, days)
    local data = getTempRolesData()
    data[targetName] = {
        role = roleName:lower(),
        expires = os.time() + (days * 86400),
        playerName = targetName,
        pending = true,
    }
    ModData.transmit(TEMP_ROLES_KEY)
    pcall(function()
        ServerWorldDatabase.instance:setAccessLevel(targetName, roleName)
    end)
end

function KitsPermissions.ApplyPendingRole(player)
    local data = getTempRolesData()
    local username = player:getUsername()
    local entry = data[username]
    if entry and entry.pending then
        local now = os.time()
        if entry.expires > now then
            player:setAccessLevel(entry.role)
            local key = getPlayerKey(player)
            if key ~= username then
                data[key] = entry
                data[username] = nil
            end
            entry.pending = nil
            ModData.transmit(TEMP_ROLES_KEY)
        else
            data[username] = nil
            ModData.transmit(TEMP_ROLES_KEY)
        end
    end
end

function KitsPermissions.RemoveTempRole(player)
    local data = getTempRolesData()
    local key = getPlayerKey(player)
    if data[key] then
        data[key] = nil
        ModData.transmit(TEMP_ROLES_KEY)
        player:setAccessLevel("user")
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
        if entry.playerName == targetName then
            data[key] = nil
            found = true
        end
    end
    if found then
        ModData.transmit(TEMP_ROLES_KEY)
        pcall(function()
            ServerWorldDatabase.instance:setAccessLevel(targetName, "user")
        end)
    end
    return found
end

function KitsPermissions.CheckExpiredRoles(player)
    local data = getTempRolesData()
    local key = getPlayerKey(player)
    local entry = data[key]
    if not entry then return end
    local now = os.time()
    if entry.expires <= now then
        data[key] = nil
        ModData.transmit(TEMP_ROLES_KEY)
        player:setAccessLevel("user")
    end
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

function KitsPermissions.GetPlayerLevel(player)
    local serverRole = getPlayerRoleName(player)
    return getRoleLevel(serverRole)
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

function KitsPermissions.ClearAllTempRoles()
    local data = getTempRolesData()
    for key, _ in pairs(data) do
        data[key] = nil
    end
    ModData.transmit(TEMP_ROLES_KEY)
end
