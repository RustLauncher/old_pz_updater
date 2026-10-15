require "KitsConfig"

KitsClient = KitsClient or {}
KitsClient.Cooldowns = {}
KitsClient.Permissions = {}
KitsClient.IsAdmin = false
KitsClient.TempRoles = {}
KitsClient.OnlinePlayers = {}
KitsClient.AllPlayers = {}
KitsClient.PlayerRole = "user"
KitsClient.PlayerRoleDaysLeft = -1
KitsClient.RoleColors = {}
KitsClient.OnlineRoles = {}

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

    elseif command == "playerRoleInfo" then
        KitsClient.PlayerRole = args.role or "user"
        KitsClient.PlayerRoleDaysLeft = tonumber(args.daysLeft) or -1
        if KitsUI and KitsUI.instance then
            KitsUI.instance:updateRoleBar()
        end

    elseif command == "roleColors" then
        KitsClient.RoleColors = {}
        if args then
            for name, cStr in pairs(args) do
                local r, g, b = cStr:match("([%d%.]+),([%d%.]+),([%d%.]+)")
                if r then
                    KitsClient.RoleColors[name:lower()] = {
                        r = tonumber(r), g = tonumber(g), b = tonumber(b), a = 1,
                    }
                end
            end
        end

    elseif command == "onlineRoles" then
        KitsClient.OnlineRoles = args or {}

    elseif command == "error" then
        local player = getPlayer()
        if player then
            player:Say(tostring(args.msg))
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)

local ROLE_TAG_COLORS = {
    vip       = { r = 1.00, g = 0.85, b = 0.20 },
    ultimate  = { r = 0.90, g = 0.15, b = 0.35 },
    priority  = { r = 1.00, g = 0.85, b = 0.20 },
    gm        = { r = 0.80, g = 0.50, b = 1.00 },
    moderator = { r = 0.30, g = 0.60, b = 1.00 },
    admin     = { r = 1.00, g = 0.30, b = 0.30 },
}

local function renderRoleTags()
    local me = getPlayer()
    if not me then return end
    local onlineRoles = KitsClient.OnlineRoles
    if not onlineRoles then return end
    local players = getOnlinePlayers()
    if not players then return end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        local role = onlineRoles[p:getUsername()]
        if role then
            local sx = isoToScreenX(0, p:getX(), p:getY(), p:getZ())
            local sy = isoToScreenY(0, p:getX(), p:getY(), p:getZ())
            local tag = "[" .. role:upper() .. "]"
            local font = UIFont.Small
            local tw = getTextManager():MeasureStringX(font, tag)
            local tx = sx - tw / 2
            local ty = sy - 110
            local c = ROLE_TAG_COLORS[role:lower()] or { r = 0.8, g = 0.8, b = 0.8 }
            getTextManager():DrawString(font, tx, ty, tag, c.r, c.g, c.b, 1.0)
        end
    end
end

Events.OnPostUIDraw.Add(renderRoleTags)
