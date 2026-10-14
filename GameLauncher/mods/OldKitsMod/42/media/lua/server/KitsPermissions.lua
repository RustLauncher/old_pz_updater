--[[
    KitsPermissions.lua (server) - Build 42 compatible
    Gestiona los grupos de permisos de cada jugador.

    Los permisos se guardan en GlobalModData para persistir entre sesiones.
    Cada jugador puede tener multiples grupos (ej: "vip", "donor").
    Los admins del servidor siempre tienen acceso a todo.

    Los comandos de admin se envian via OnClientCommand (no chat),
    gestionados desde KitsServer.lua.
]]

require "KitsConfig"

KitsPermissions = KitsPermissions or {}

local MODDATA_KEY = "KitsPlayerGroups"

local GROUP_HIERARCHY = {
    ultimate = { "vip" },
}

local function getGroupsData()
    local data = ModData.getOrCreate(MODDATA_KEY)
    return data
end

local function getPlayerSteamId(player)
    local steamId = player:getSteamID()
    if not steamId or steamId == "" then
        steamId = player:getUsername()
    end
    return tostring(steamId)
end

function KitsPermissions.GetPlayerGroups(player)
    local data = getGroupsData()
    local steamId = getPlayerSteamId(player)
    if not data[steamId] then
        data[steamId] = {}
    end
    return data[steamId]
end

function KitsPermissions.AddGroup(player, group)
    local groups = KitsPermissions.GetPlayerGroups(player)
    for _, g in ipairs(groups) do
        if g == group then return false end
    end
    table.insert(groups, group)
    ModData.transmit(MODDATA_KEY)
    return true
end

function KitsPermissions.RemoveGroup(player, group)
    local groups = KitsPermissions.GetPlayerGroups(player)
    for i, g in ipairs(groups) do
        if g == group then
            table.remove(groups, i)
            ModData.transmit(MODDATA_KEY)
            return true
        end
    end
    return false
end

function KitsPermissions.HasGroup(player, group)
    local groups = KitsPermissions.GetPlayerGroups(player)
    for _, g in ipairs(groups) do
        if g == group then return true end
    end
    return false
end

function KitsPermissions.IsAdmin(player)
    local level = player:getAccessLevel()
    return level == "admin" or level == "moderator"
end

function KitsPermissions.CanUseKit(player, kit)
    local perm = kit.permission or "all"
    if perm == "all" then
        return true
    end
    if KitsPermissions.IsAdmin(player) then
        return true
    end
    if perm == "admin" then
        return false
    end
    if KitsPermissions.HasGroup(player, perm) then
        return true
    end
    local groups = KitsPermissions.GetPlayerGroups(player)
    for _, g in ipairs(groups) do
        local includes = GROUP_HIERARCHY[g]
        if includes then
            for _, inc in ipairs(includes) do
                if inc == perm then return true end
            end
        end
    end
    return false
end

function KitsPermissions.GetPlayerPermissionsMap(player)
    local result = {}
    local isAdmin = KitsPermissions.IsAdmin(player)
    for _, kit in ipairs(KitsConfig.Kits) do
        if kit.permission == "all" or isAdmin then
            result[kit.id] = true
        elseif kit.permission == "admin" then
            result[kit.id] = false
        else
            if KitsPermissions.HasGroup(player, kit.permission) then
                result[kit.id] = true
            else
                local granted = false
                local groups = KitsPermissions.GetPlayerGroups(player)
                for _, g in ipairs(groups) do
                    local includes = GROUP_HIERARCHY[g]
                    if includes then
                        for _, inc in ipairs(includes) do
                            if inc == kit.permission then granted = true end
                        end
                    end
                end
                result[kit.id] = granted
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
