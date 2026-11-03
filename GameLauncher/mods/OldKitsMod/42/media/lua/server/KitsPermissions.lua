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

function KitsPermissions.GetPlayerKey(player)
    local steamId = player:getSteamID()
    if steamId and steamId ~= "" and steamId ~= "0" then
        return tostring(steamId)
    end
    return player:getUsername()
end

local function getPlayerKey(player)
    return KitsPermissions.GetPlayerKey(player)
end

-- Format: steamId|role|expires|displayName
local function saveRolesToFile()
    local writer = getFileWriter(ROLES_FILE, true, false)
    for key, entry in pairs(rolesData) do
        if type(entry) == "table" and entry.role and entry.expires then
            local displayName = entry.displayName or key
            writer:writeln(key .. "|" .. entry.role .. "|" .. tostring(entry.expires) .. "|" .. displayName)
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
        local key, role, expires, displayName = line:match("^(.-)|(.-)|([^|]+)|?(.*)$")
        if key and role and expires then
            if not displayName or displayName == "" then
                displayName = key
            end
            rolesData[key] = {
                role = role:lower(),
                expires = tonumber(expires),
                displayName = displayName,
            }
        end
        line = reader:readLine()
    end
    reader:close()
end

local function findKeyByPlayerName(name)
    local lowerName = name:lower()
    for key, entry in pairs(rolesData) do
        if type(entry) == "table" and entry.displayName and entry.displayName:lower() == lowerName then
            return key
        end
    end
    return nil
end

function KitsPermissions.SetTempRole(player, roleName, days)
    local key = getPlayerKey(player)
    local displayName = player:getUsername()
    rolesData[key] = {
        role = roleName:lower(),
        expires = os.time() + (days * 86400),
        displayName = displayName,
    }
    saveRolesToFile()
end

function KitsPermissions.SetTempRoleByName(targetName, roleName, days)
    local target = KitsPermissions.FindPlayerByName(targetName)
    if not target then return false end
    KitsPermissions.SetTempRole(target, roleName, days)
    return true
end

function KitsPermissions.RemoveTempRole(targetName)
    local target = KitsPermissions.FindPlayerByName(targetName)
    if target then
        local key = getPlayerKey(target)
        if rolesData[key] then
            rolesData[key] = nil
            saveRolesToFile()
            return true
        end
    end
    local key = findKeyByPlayerName(targetName)
    if key and rolesData[key] then
        rolesData[key] = nil
        saveRolesToFile()
        return true
    end
    return false
end

function KitsPermissions.GetTempRoleInfo(player)
    local key
    if type(player) == "string" then
        local p = KitsPermissions.FindPlayerByName(player)
        if p then
            key = getPlayerKey(p)
        else
            key = findKeyByPlayerName(player)
        end
    else
        key = getPlayerKey(player)
    end
    if not key then return nil end
    local entry = rolesData[key]
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
    if KitsPermissions.IsAdmin(player) then
        return "admin"
    end
    local key = getPlayerKey(player)
    local entry = rolesData[key]
    if entry and type(entry) == "table" and entry.role then
        local expires = tonumber(entry.expires)
        if expires and expires > os.time() then
            return entry.role
        end
    end
    return "user"
end

function KitsPermissions.GetPlayerLevel(player)
    return getRoleLevel(KitsPermissions.GetEffectiveRole(player))
end

function KitsPermissions.IsAdmin(player)
    local level = player:getAccessLevel()
    if not level or level == "" then return false end
    local lower = level:lower()
    return lower == "admin" or lower == "moderator"
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
                    playerName = entry.displayName or key,
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
    local expired = {}
    for key, entry in pairs(rolesData) do
        if type(entry) == "table" and entry.role then
            local expires = tonumber(entry.expires)
            if expires and expires <= now then
                table.insert(expired, { key = key, displayName = entry.displayName or key })
            end
        end
    end
    if #expired == 0 then return false end
    for _, exp in ipairs(expired) do
        rolesData[exp.key] = nil
    end
    saveRolesToFile()
    for _, exp in ipairs(expired) do
        local target = KitsPermissions.FindPlayerByName(exp.displayName)
        if target then
            sendServerCommand(target, "Kits", "playerRoleInfo", {
                role = "user",
                daysLeft = "0",
            })
            local perms = KitsPermissions.GetPlayerPermissionsMap(target)
            sendServerCommand(target, "Kits", "permissionsUpdate", perms)
        end
    end
    return true
end

function KitsPermissions.LoadRoles()
    loadRolesFromFile()
end

function KitsPermissions.UpdateDisplayName(player)
    local key = getPlayerKey(player)
    local entry = rolesData[key]
    if entry and type(entry) == "table" then
        local currentName = player:getUsername()
        if entry.displayName ~= currentName then
            entry.displayName = currentName
            saveRolesToFile()
        end
    end
end
