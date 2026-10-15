require "KitsConfig"
require "KitsPermissions"

KitsServer = KitsServer or {}

local KITS_OVERRIDES_KEY = "KitsOverrides"
local KITS_KNOWN_PLAYERS_KEY = "KitsKnownPlayers"

local ELEVATED_ROLES = {
    admin = true, moderator = true, gm = true, observer = true,
    priority = true, ultimate = true, vip = true,
}

local function registerKnownPlayer(player)
    local data = ModData.getOrCreate(KITS_KNOWN_PLAYERS_KEY)
    local name = player:getUsername()
    if not data[name] then
        data[name] = tostring(os.time())
        ModData.transmit(KITS_KNOWN_PLAYERS_KEY)
    elseif type(data[name]) == "table" then
        data[name] = data[name].joined or tostring(os.time())
        ModData.transmit(KITS_KNOWN_PLAYERS_KEY)
    end
end

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

local function sendPlayerRoleInfo(player)
    local roleObj = player:getRole()
    local roleName = "user"
    if roleObj then
        local rn = roleObj:getName()
        if rn and rn ~= "" and rn:lower() ~= "none" then
            roleName = rn:lower()
        end
    end
    local username = player:getUsername()
    local tempInfo = KitsPermissions.GetTempRoleInfo(username)
    local daysLeft = "-1"
    if tempInfo then
        daysLeft = tostring(tempInfo.daysLeft)
    end
    sendServerCommand(player, "Kits", "playerRoleInfo", {
        role = roleName,
        daysLeft = daysLeft,
    })
end

local function sendMsg(player, msg)
    sendServerCommand(player, "Kits", "error", { msg = msg })
end

local function sendTempRolesList(player)
    local roles = KitsPermissions.GetAllTempRoles()
    local listed = {}
    for _, r in ipairs(roles) do
        listed[r.playerName] = true
    end
    local onlinePlayers = getOnlinePlayers()
    for i = 0, onlinePlayers:size() - 1 do
        local p = onlinePlayers:get(i)
        local pName = p:getUsername()
        if not listed[pName] then
            local roleObj = p:getRole()
            local roleName = ""
            if roleObj then
                local rn = roleObj:getName()
                if rn then roleName = rn:lower() end
            end
            if roleName ~= "" and roleName ~= "none" and ELEVATED_ROLES[roleName] then
                table.insert(roles, {
                    playerName = pName,
                    role = roleName,
                    daysLeft = -1,
                    isNative = true,
                })
            end
        end
    end
    sendServerCommand(player, "Kits", "tempRolesList", { roles = roles })
end

local function loadKitOverrides()
    local data = ModData.getOrCreate(KITS_OVERRIDES_KEY)
    for _, defKit in ipairs(KitsConfig.DefaultKits) do
        local ov = data[defKit.id]
        if ov then
            local kit = KitsConfig.GetKitById(defKit.id)
            if kit then
                if ov.name and ov.name ~= "" then kit.name = ov.name end
                if ov.cooldown then kit.cooldown = tonumber(ov.cooldown) or kit.cooldown end
                if ov.permission and ov.permission ~= "" then kit.permission = ov.permission end
                if ov.icon and ov.icon ~= "" then kit.icon = ov.icon end
                if ov.items and ov.items ~= "" then
                    kit.items = KitsConfig.DeserializeItems(ov.items)
                end
            end
        end
    end
end

local function saveKitOverride(kitId)
    local data = ModData.getOrCreate(KITS_OVERRIDES_KEY)
    local kit = KitsConfig.GetKitById(kitId)
    if not kit then return end
    data[kitId] = {
        name = kit.name,
        cooldown = tostring(kit.cooldown),
        permission = kit.permission,
        icon = kit.icon,
        items = KitsConfig.SerializeItems(kit.items),
    }
    ModData.transmit(KITS_OVERRIDES_KEY)
end

local function sendKitsToPlayer(player)
    local kitsList = {}
    for _, kit in ipairs(KitsConfig.Kits) do
        table.insert(kitsList, {
            id = kit.id,
            name = kit.name,
            icon = kit.icon,
            cooldown = tostring(kit.cooldown),
            permission = kit.permission,
            items = KitsConfig.SerializeItems(kit.items),
        })
    end
    sendServerCommand(player, "Kits", "kitsList", { kits = kitsList })
end

local function broadcastKitsUpdate()
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        sendKitsToPlayer(p)
        sendPermissions(p)
    end
end

local function sendAllPlayersList(player)
    local known = ModData.getOrCreate(KITS_KNOWN_PLAYERS_KEY)
    local onlinePlayers = getOnlinePlayers()
    local onlineSet = {}
    for i = 0, onlinePlayers:size() - 1 do
        local p = onlinePlayers:get(i)
        onlineSet[p:getUsername()] = true
        if not known[p:getUsername()] then
            known[p:getUsername()] = tostring(os.time())
            ModData.transmit(KITS_KNOWN_PLAYERS_KEY)
        end
    end
    local list = {}
    for name, _ in pairs(known) do
        table.insert(list, {
            name = name,
            online = onlineSet[name] and true or false,
        })
    end
    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.name:lower() < b.name:lower()
    end)
    sendServerCommand(player, "Kits", "allPlayersList", { players = list })
end

local function onClientCommand(module, command, player, args)
    if module ~= "Kits" then return end

    registerKnownPlayer(player)
    KitsPermissions.CheckExpiredRoles(player)

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
        sendPlayerRoleInfo(player)
        sendKitsToPlayer(player)

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
        if target then
            KitsPermissions.SetTempRole(player, target, roleName, days)
            sendPermissions(target)
            sendPlayerRoleInfo(target)
        else
            KitsPermissions.SetTempRoleOffline(targetName, roleName, days)
            sendServerCommand(player, "Kits", "execSetRole", { targetName = targetName, roleName = roleName })
        end
        sendMsg(player, "Rol '" .. roleName .. "' dado a " .. targetName .. " por " .. days .. " dias.")
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
        if target then
            local removed = KitsPermissions.RemoveTempRole(player, target)
            if removed then
                sendMsg(player, "Rol temporal quitado de " .. targetName)
                sendPermissions(target)
                sendPlayerRoleInfo(target)
            else
                sendMsg(player, targetName .. " no tiene rol temporal.")
            end
        else
            local removed = KitsPermissions.RemoveTempRoleOffline(targetName)
            if removed then
                sendServerCommand(player, "Kits", "execSetRole", { targetName = targetName, roleName = "user" })
                sendMsg(player, "Rol temporal quitado de " .. targetName)
            else
                sendMsg(player, targetName .. " no tiene rol temporal.")
            end
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

    elseif command == "adminListAllPlayers" then
        if not KitsPermissions.IsAdmin(player) then
            sendMsg(player, "No tienes permisos de admin.")
            return
        end
        sendAllPlayersList(player)

    elseif command == "adminGetKits" then
        if not KitsPermissions.IsAdmin(player) then
            sendMsg(player, "No tienes permisos de admin.")
            return
        end
        sendKitsToPlayer(player)

    elseif command == "adminSaveKit" then
        if not KitsPermissions.IsAdmin(player) then
            sendMsg(player, "No tienes permisos de admin.")
            return
        end
        local kitId = args.kitId
        local kit = KitsConfig.GetKitById(kitId)
        if not kit then
            sendMsg(player, "Kit '" .. tostring(kitId) .. "' no encontrado.")
            return
        end
        if args.name and args.name ~= "" then kit.name = args.name end
        if args.cooldown then
            local cd = tonumber(args.cooldown)
            if cd and cd > 0 then kit.cooldown = cd end
        end
        if args.permission and args.permission ~= "" then kit.permission = args.permission end
        if args.icon and args.icon ~= "" then kit.icon = args.icon end
        if args.items then
            kit.items = KitsConfig.DeserializeItems(args.items)
        end
        saveKitOverride(kitId)
        broadcastKitsUpdate()
        sendMsg(player, "Kit '" .. kit.name .. "' guardado.")
    end
end

Events.OnClientCommand.Add(onClientCommand)

local function onServerStarted()
    loadKitOverrides()
    KitsPermissions.CleanCorruptEntries()
end

Events.OnServerStarted.Add(onServerStarted)
