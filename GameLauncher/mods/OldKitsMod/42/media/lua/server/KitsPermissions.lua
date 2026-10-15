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

function KitsPermissions.SetTempRole(targetName, roleName, days)
    local data = getTempRolesData()
    data[targetName] = {
        role = roleName:lower(),
        expires = os.time() + (days * 86400),
        playerName = targetName,
    }
    ModData.transmit(TEMP_ROLES_KEY)
end

function KitsPermissions.RemoveTempRole(targetName)
    local data = getTempRolesData()
    if data[targetName] then
        data[targetName] = nil
        ModData.transmit(TEMP_ROLES_KEY)
        return true
    end
    return false
end

function KitsPermissions.GetTempRoleInfo(username)
    local data = getTempRolesData()
    local entry = data[username]
    if not entry or type(entry) ~= "table" then return nil end
    local expires = tonumber(entry.expires)
    if not expires or not entry.role then return nil end
    local remaining = expires - os.time()
    if remaining <= 0 then
        return { role = "user", daysLeft = 0, expired = true }
    end
    return {
        role = entry.role,
        daysLeft = math.ceil(remaining / 86400),
    }
end

function KitsPermissions.GetEffectiveRole(player)
    local username = player:getUsername()
    local info = KitsPermissions.GetTempRoleInfo(username)
    if info then
        if info.expired then
            return "user"
        end
        return info.role
    end
    return getPlayerRoleName(player)
end

function KitsPermissions.GetPlayerLevel(player)
    return getRoleLevel(KitsPermissions.GetEffectiveRole(player))
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

function KitsPermissions.CheckExpiredRoles()
    local data = getTempRolesData()
    local now = os.time()
    local changed = false
    local expired = {}
    for key, entry in pairs(data) do
        if type(entry) == "table" and entry.role then
            local expires = tonumber(entry.expires)
            if expires and expires <= now then
                table.insert(expired, { key = key, playerName = entry.playerName or key })
                data[key] = nil
                changed = true
            end
        end
    end
    if changed then
        ModData.transmit(TEMP_ROLES_KEY)
        for _, exp in ipairs(expired) do
            local target = KitsPermissions.FindPlayerByName(exp.playerName)
            if target then
                sendServerCommand(target, "Kits", "playerRoleInfo", {
                    role = "user",
                    daysLeft = "0",
                })
                local perms = KitsPermissions.GetPlayerPermissionsMap(target)
                sendServerCommand(target, "Kits", "permissionsUpdate", perms)
            end
            KitsPermissions.BroadcastExecSetRole(exp.playerName, "")
        end
    end
end

function KitsPermissions.BroadcastExecSetRole(targetName, roleName)
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        local pRole = p:getRole()
        if pRole then
            local rn = pRole:getName()
            if rn and (rn:lower() == "admin" or rn:lower() == "moderator") then
                sendServerCommand(p, "Kits", "execSetRole", {
                    targetName = targetName,
                    roleName = roleName,
                })
                return
            end
        end
    end
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

function KitsPermissions.ReapplyAllTempRoles()
    local players = getOnlinePlayers()
    local adminPlayer = nil
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        local pRole = p:getRole()
        if pRole then
            local rn = pRole:getName()
            if rn and (rn:lower() == "admin" or rn:lower() == "moderator") then
                adminPlayer = p
                break
            end
        end
    end
    if not adminPlayer then return end
    local data = getTempRolesData()
    local now = os.time()
    for key, entry in pairs(data) do
        if type(entry) == "table" and entry.role then
            local expires = tonumber(entry.expires)
            if expires and expires > now then
                sendServerCommand(adminPlayer, "Kits", "execSetRole", {
                    targetName = entry.playerName or key,
                    roleName = entry.role,
                })
            end
        end
    end
end
