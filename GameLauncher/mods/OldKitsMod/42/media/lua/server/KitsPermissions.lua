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

function KitsPermissions.SetTempRole(player, roleName, days)
    local data = getTempRolesData()
    local name = player:getUsername()
    data[name] = {
        role = roleName:lower(),
        expires = os.time() + (days * 86400),
        playerName = name,
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
        pending = "yes",
    }
    ModData.transmit(TEMP_ROLES_KEY)
end

function KitsPermissions.ApplyPendingRole(player)
    local data = getTempRolesData()
    local name = player:getUsername()
    local entry = data[name]
    if not entry or type(entry) ~= "table" then return end
    if entry.pending ~= "yes" then return end
    local expires = tonumber(entry.expires)
    if not expires or not entry.role then
        data[name] = nil
        ModData.transmit(TEMP_ROLES_KEY)
        return
    end
    if expires <= os.time() then
        data[name] = nil
        ModData.transmit(TEMP_ROLES_KEY)
        return
    end
    player:setAccessLevel(entry.role)
    entry.pending = nil
    ModData.transmit(TEMP_ROLES_KEY)
end

function KitsPermissions.RemoveTempRole(player)
    local data = getTempRolesData()
    local name = player:getUsername()
    if data[name] then
        data[name] = nil
        ModData.transmit(TEMP_ROLES_KEY)
        player:setAccessLevel("")
        return true
    end
    return false
end

function KitsPermissions.RemoveTempRoleOffline(targetName)
    local data = getTempRolesData()
    if data[targetName] then
        data[targetName] = nil
        ModData.transmit(TEMP_ROLES_KEY)
        return true
    end
    return false
end

function KitsPermissions.CheckExpiredRoles(player)
    local data = getTempRolesData()
    local name = player:getUsername()
    local entry = data[name]
    if not entry or type(entry) ~= "table" then return end
    local expires = tonumber(entry.expires)
    if not expires or not entry.role then
        data[name] = nil
        ModData.transmit(TEMP_ROLES_KEY)
        return
    end
    if expires <= os.time() then
        data[name] = nil
        ModData.transmit(TEMP_ROLES_KEY)
        player:setAccessLevel("")
    end
end

function KitsPermissions.GetTempRoleInfo(username)
    local data = getTempRolesData()
    local entry = data[username]
    if not entry or type(entry) ~= "table" then return nil end
    local expires = tonumber(entry.expires)
    if not expires or not entry.role then return nil end
    local remaining = expires - os.time()
    if remaining <= 0 then return nil end
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
                table.insert(result, {
                    playerName = entry.playerName or key,
                    role = entry.role,
                    daysLeft = math.ceil((expires - now) / 86400),
                })
            end
        end
    end
    return result
end

function KitsPermissions.GetPlayerLevel(player)
    return getRoleLevel(getPlayerRoleName(player))
end

function KitsPermissions.IsAdmin(player)
    local roleName = getPlayerRoleName(player)
    return roleName == "admin" or roleName == "moderator"
end

function KitsPermissions.CanUseKit(player, kit)
    local perm = kit.permission or "all"
    if perm == "all" then return true end
    return KitsPermissions.GetPlayerLevel(player) >= (ROLE_LEVEL[perm] or 0)
end

function KitsPermissions.GetPlayerPermissionsMap(player)
    local result = {}
    local playerLevel = KitsPermissions.GetPlayerLevel(player)
    for _, kit in ipairs(KitsConfig.Kits) do
        local perm = kit.permission or "all"
        if perm == "all" then
            result[kit.id] = "yes"
        elseif playerLevel >= (ROLE_LEVEL[perm] or 0) then
            result[kit.id] = "yes"
        else
            result[kit.id] = "no"
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
        data[key] = nil
    end
    if #toRemove > 0 then
        ModData.transmit(TEMP_ROLES_KEY)
    end
end
