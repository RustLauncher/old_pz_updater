require "KitsConfig"
require "KitsPermissions"

KitsServer = KitsServer or {}

local function getPlayerCooldowns(player)
    local modData = player:getModData()
    if not modData.KitsCooldowns then
        modData.KitsCooldowns = {}
    end
    return modData.KitsCooldowns
end

local function getCooldownRemaining(player, kitId, cooldownMinutes)
    local cooldowns = getPlayerCooldowns(player)
    local lastUsed = cooldowns[kitId]
    if not lastUsed then
        return 0
    end
    if lastUsed > 4000000000 then
        cooldowns[kitId] = nil
        return 0
    end
    local now = os.time()
    local cooldownSecs = cooldownMinutes * 60
    local elapsed = now - lastUsed
    if elapsed >= cooldownSecs then
        return 0
    end
    return (cooldownSecs - elapsed) * 1000
end

local function setCooldown(player, kitId)
    local cooldowns = getPlayerCooldowns(player)
    cooldowns[kitId] = os.time()
end

local function giveKit(player, kit)
    local inv = player:getInventory()
    local given = {}
    for _, entry in ipairs(kit.items) do
        for i = 1, entry.count do
            local item = inv:AddItem(entry.type)
            if item then
                sendAddItemToContainer(inv, item)
                table.insert(given, entry.type)
            end
        end
    end
    return given
end

local function sendAllCooldowns(player)
    local data = {}
    for _, kit in ipairs(KitsConfig.Kits) do
        data[kit.id] = getCooldownRemaining(player, kit.id, kit.cooldown)
    end
    sendServerCommand(player, "Kits", "cooldowns", data)
end

local function sendPermissions(player)
    local perms = KitsPermissions.GetPlayerPermissionsMap(player)
    sendServerCommand(player, "Kits", "permissionsUpdate", perms)
end

local function sendMsg(player, msg)
    sendServerCommand(player, "Kits", "error", { msg = msg })
end

local function sendTempRolesList(player)
    local roles = KitsPermissions.GetAllTempRoles()
    sendServerCommand(player, "Kits", "tempRolesList", { roles = roles })
end

local function onClientCommand(module, command, player, args)
    if module ~= "Kits" then return end

    if command == "requestKit" then
        local kitId = args.kitId
        local kit = KitsConfig.GetKitById(kitId)
        if not kit then
            sendMsg(player, "Kit no encontrado.")
            return
        end

        if not KitsPermissions.CanUseKit(player, kit) then
            sendMsg(player, "No tienes permiso para usar este kit.")
            return
        end

        local remaining = getCooldownRemaining(player, kitId, kit.cooldown)
        if remaining > 0 then
            local seconds = math.ceil(remaining / 1000)
            sendMsg(player, "Kit en cooldown. Espera " .. seconds .. " segundos.")
            sendAllCooldowns(player)
            return
        end

        local given = giveKit(player, kit)
        setCooldown(player, kitId)
        sendServerCommand(player, "Kits", "kitGiven", {
            kitId = kitId,
            name = kit.name,
            count = #given,
        })
        sendAllCooldowns(player)

    elseif command == "requestCooldowns" then
        sendAllCooldowns(player)
        sendPermissions(player)

    elseif command == "checkAdmin" then
        local isAdmin = KitsPermissions.IsAdmin(player)
        sendServerCommand(player, "Kits", "adminStatus", { isAdmin = isAdmin })

    elseif command == "adminSetTempRole" then
        if not KitsPermissions.IsAdmin(player) then
            sendMsg(player, "No tienes permisos de admin.")
            return
        end
        local targetName = args.targetName
        local roleName = args.roleName
        local days = tonumber(args.days)
        if not targetName or not roleName or not days or days <= 0 then
            sendMsg(player, "Parametros invalidos.")
            return
        end
        local target = KitsPermissions.FindPlayerByName(targetName)
        if not target then
            sendMsg(player, "Jugador '" .. targetName .. "' no encontrado online.")
            return
        end
        KitsPermissions.SetTempRole(target, roleName, days)
        sendMsg(player, "Rol '" .. roleName .. "' dado a " .. targetName .. " por " .. days .. " dias.")
        sendPermissions(target)
        sendTempRolesList(player)

    elseif command == "adminRemoveTempRole" then
        if not KitsPermissions.IsAdmin(player) then
            sendMsg(player, "No tienes permisos de admin.")
            return
        end
        local targetName = args.targetName
        if not targetName then
            sendMsg(player, "Falta el nombre del jugador.")
            return
        end
        local target = KitsPermissions.FindPlayerByName(targetName)
        if not target then
            sendMsg(player, "Jugador '" .. targetName .. "' no encontrado online.")
            return
        end
        local removed = KitsPermissions.RemoveTempRole(target)
        if removed then
            sendMsg(player, "Rol temporal quitado de " .. targetName)
            sendPermissions(target)
        else
            sendMsg(player, targetName .. " no tiene rol temporal.")
        end
        sendTempRolesList(player)

    elseif command == "adminListTempRoles" then
        if not KitsPermissions.IsAdmin(player) then
            sendMsg(player, "No tienes permisos de admin.")
            return
        end
        sendTempRolesList(player)

    elseif command == "adminListOnline" then
        if not KitsPermissions.IsAdmin(player) then
            sendMsg(player, "No tienes permisos de admin.")
            return
        end
        local names = {}
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do
            table.insert(names, players:get(i):getUsername())
        end
        sendServerCommand(player, "Kits", "onlineList", { players = names })
    end
end

Events.OnClientCommand.Add(onClientCommand)
