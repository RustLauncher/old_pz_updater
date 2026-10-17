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

local ROLES_FILE = "KitsRoles.ini"
local rolesData = {}

local function getRoleLevel(roleName)
    if not roleName or roleName == "" then return 10 end
    return ROLE_LEVEL[roleName:lower()] or 10
end

local function saveRolesToFile()
    local writer = getFileWriter(ROLES_FILE, true, false)
    for name, entry in pairs(rolesData) do
        if type(entry) == "table" and entry.role and entry.expires then
            writer:writeln(name .. "|" .. entry.role .. "|" .. tostring(entry.expires))
        end
    end
    writer:close()
end

local function loadRolesFromFile()
    rolesData = {}
    local reader = getFileReader(ROLES_FILE, false)
    if not reader then return end
    local line = reader:readLine()
    while line do
        local name, role, expires = line:match("^(.-)|(.-)|(.+)$")
        if name and role and expires then
            rolesData[name] = {
                role = role:lower(),
                expires = tonumber(expires),
                playerName = name,
            }
        end
        line = reader:readLine()
    end
    reader:close()
end

function KitsPermissions.SetTempRole(targetName, roleName, days)
    rolesData[targetName] = {
        role = roleName:lower(),
        expires = os.time() + (days * 86400),
        playerName = targetName,
    }
    saveRolesToFile()
end

function KitsPermissions.RemoveTempRole(targetName)
    if rolesData[targetName] then
        rolesData[targetName] = nil
        saveRolesToFile()
        return true
    end
    return false
end

function KitsPermissions.GetTempRoleInfo(username)
    local entry = rolesData[username]
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
    if KitsPermissions.IsAdmin(player) then
        return "admin"
    end
    local info = KitsPermissions.GetTempRoleInfo(username)
    if info then
        if info.expired then
            return "user"
        end
        return info.role
    end
    return "user"
end

function KitsPermissions.GetPlayerLevel(player)
    return getRoleLevel(KitsPermissions.GetEffectiveRole(player))
end

function KitsPermissions.IsAdmin(player)
    local role = player:getRole()
    if role then
        local name = role:getName()
        if name then
            local lower = name:lower()
            return lower == "admin" or lower == "moderator"
        end
    end
    return false
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
    local now = os.time()
    local result = {}
    for key, entry in pairs(rolesData) do
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
    local now = os.time()
    local changed = false
    local expired = {}
    for key, entry in pairs(rolesData) do
        if type(entry) == "table" and entry.role then
            local expires = tonumber(entry.expires)
            if expires and expires <= now then
                table.insert(expired, { key = key, playerName = entry.playerName or key })
                rolesData[key] = nil
                changed = true
            end
        end
    end
    if changed then
        saveRolesToFile()
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
        end
    end
    return changed
end

function KitsPermissions.LoadRoles()
    loadRolesFromFile()
end
