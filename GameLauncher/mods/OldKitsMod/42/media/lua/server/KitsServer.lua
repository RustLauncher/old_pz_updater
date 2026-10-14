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

local function getRealTimeMs()
    return Calendar.getInstance():getTimeInMillis()
end

local function getCooldownRemaining(player, kitId, cooldownMinutes)
    local cooldowns = getPlayerCooldowns(player)
    local lastUsed = cooldowns[kitId]
    if not lastUsed then
        return 0
    end
    local now = getRealTimeMs()
    local cooldownMs = cooldownMinutes * 60 * 1000
    local elapsed = now - lastUsed
    if elapsed >= cooldownMs then
        return 0
    end
    return cooldownMs - elapsed
end

local function setCooldown(player, kitId)
    local cooldowns = getPlayerCooldowns(player)
    cooldowns[kitId] = getRealTimeMs()
end

local function giveKit(player, kit)
    local inv = player:getInventory()
    local given = {}
    for _, entry in ipairs(kit.items) do
        for i = 1, entry.count do
            local item = inv:AddItem(entry.type)
            if item then
                table.insert(given, entry.type)
            end
        end
    end
    inv:setDrawDirty(true)
    player:getInventory():setDrawDirty(true)
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
    end
end

Events.OnClientCommand.Add(onClientCommand)
