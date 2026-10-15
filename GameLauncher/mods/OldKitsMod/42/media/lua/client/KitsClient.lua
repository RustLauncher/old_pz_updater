require "KitsConfig"

KitsClient = KitsClient or {}
KitsClient.Cooldowns = {}
KitsClient.Permissions = {}
KitsClient.IsAdmin = false
KitsClient.TempRoles = {}
KitsClient.OnlinePlayers = {}
KitsClient.AllPlayers = {}

function KitsClient.RequestKit(kitId)
    sendClientCommand("Kits", "requestKit", { kitId = kitId })
end

function KitsClient.RequestCooldowns()
    sendClientCommand("Kits", "requestCooldowns", {})
end

function KitsClient.CheckAdmin()
    sendClientCommand("Kits", "checkAdmin", {})
end

function KitsClient.HasPermission(kitId)
    local v = KitsClient.Permissions[kitId]
    if v == nil then
        return false
    end
    return v == "yes"
end

function KitsClient.AdminSetTempRole(targetName, roleName, days)
    sendClientCommand("Kits", "adminSetTempRole", {
        targetName = targetName,
        roleName = roleName,
        days = days,
    })
end

function KitsClient.AdminRemoveTempRole(targetName)
    sendClientCommand("Kits", "adminRemoveTempRole", { targetName = targetName })
end

function KitsClient.AdminListTempRoles()
    sendClientCommand("Kits", "adminListTempRoles", {})
end

function KitsClient.AdminListOnline()
    sendClientCommand("Kits", "adminListOnline", {})
end

function KitsClient.AdminListAllPlayers()
    sendClientCommand("Kits", "adminListAllPlayers", {})
end

function KitsClient.AdminGetKits()
    sendClientCommand("Kits", "adminGetKits", {})
end

function KitsClient.AdminSaveKit(kitId, name, icon, cooldown, permission, itemsStr)
    sendClientCommand("Kits", "adminSaveKit", {
        kitId = kitId,
        name = name,
        icon = icon,
        cooldown = tostring(cooldown),
        permission = permission,
        items = itemsStr,
    })
end

local function refreshInventoryUI()
    local player = getPlayer()
    if not player then return end
    local inv = player:getInventory()
    if inv then
        inv:setDrawDirty(true)
    end
    if ISInventoryPage and ISInventoryPage.dirtySlice ~= nil then
        ISInventoryPage.dirtySlice = true
    end
    local pInv = getPlayerInventory(0)
    if pInv then
        pInv:refreshBackpacks()
    end
    local pLoot = getPlayerLoot(0)
    if pLoot then
        pLoot:refreshBackpacks()
    end
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
        refreshInventoryUI()
        if KitsUI and KitsUI.instance then
            KitsUI.instance:updateCooldowns()
        end

    elseif command == "tempRolesList" then
        KitsClient.TempRoles = args.roles or {}
        if KitsUI and KitsUI.instance then
            KitsUI.instance:updateTempRolesList()
        end

    elseif command == "onlineList" then
        KitsClient.OnlinePlayers = args.players or {}
        if KitsUI and KitsUI.instance then
            KitsUI.instance:updateOnlineList()
        end

    elseif command == "allPlayersList" then
        KitsClient.AllPlayers = args.players or {}
        if KitsUI and KitsUI.instance then
            KitsUI.instance:updatePlayerList()
        end

    elseif command == "kitsList" then
        local kits = args.kits or {}
        KitsConfig.Kits = {}
        for _, kd in ipairs(kits) do
            table.insert(KitsConfig.Kits, {
                id = kd.id,
                name = kd.name,
                icon = kd.icon,
                cooldown = tonumber(kd.cooldown) or 360,
                permission = kd.permission or "all",
                items = KitsConfig.DeserializeItems(kd.items),
            })
        end
        if KitsUI and KitsUI.instance then
            KitsUI.instance:rebuildKitsPanel()
        end

    elseif command == "error" then
        local player = getPlayer()
        if player then
            player:Say(tostring(args.msg))
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)
