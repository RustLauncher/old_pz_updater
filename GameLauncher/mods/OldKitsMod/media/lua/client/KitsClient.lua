--[[
    KitsClient.lua - Build 42 compatible
    Maneja la comunicacion cliente -> servidor y las respuestas.
]]

require "shared/KitsConfig"

KitsClient = KitsClient or {}
KitsClient.Cooldowns = {}
KitsClient.Permissions = {}
KitsClient.IsAdmin = false

function KitsClient.RequestKit(kitId)
    sendClientCommand("Kits", "requestKit", { kitId = kitId })
end

function KitsClient.RequestCooldowns()
    sendClientCommand("Kits", "requestCooldowns", {})
end

function KitsClient.CheckAdmin()
    sendClientCommand("Kits", "checkAdmin", {})
end

function KitsClient.AdminAddGroup(targetName, group)
    sendClientCommand("Kits", "adminAddGroup", { targetName = targetName, group = group })
end

function KitsClient.AdminRemoveGroup(targetName, group)
    sendClientCommand("Kits", "adminRemoveGroup", { targetName = targetName, group = group })
end

function KitsClient.AdminListGroups(targetName)
    sendClientCommand("Kits", "adminListGroups", { targetName = targetName })
end

function KitsClient.AdminListPlayers()
    sendClientCommand("Kits", "adminListPlayers", {})
end

function KitsClient.HasPermission(kitId)
    if KitsClient.Permissions[kitId] == nil then
        return true
    end
    return KitsClient.Permissions[kitId]
end

local function onServerCommand(module, command, args)
    if module ~= "Kits" then return end

    if command == "cooldowns" then
        KitsClient.Cooldowns = args
        if KitsUI and KitsUI.instance then
            KitsUI.instance:updateCooldowns()
        end

    elseif command == "permissionsUpdate" then
        KitsClient.Permissions = args
        if KitsUI and KitsUI.instance then
            KitsUI.instance:updateCooldowns()
        end

    elseif command == "adminStatus" then
        KitsClient.IsAdmin = args.isAdmin
        if KitsUI and KitsUI.instance then
            KitsUI.instance:updateAdminButton()
        end

    elseif command == "kitGiven" then
        local player = getPlayer()
        if player then
            player:Say("Kit '" .. tostring(args.name) .. "' recibido!")
        end
        if KitsUI and KitsUI.instance then
            KitsUI.instance:updateCooldowns()
        end

    elseif command == "error" then
        local player = getPlayer()
        if player then
            player:Say(tostring(args.msg))
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)
