require "RB_Sandbox"

local JOIN_UPDATE_DELAY = 120
local JOIN_UPDATE_TIMEOUT = 1800
local pendingPlayers = {}
local pendingPlayerCount = 0
local playerUpdateInstalled = false
local onPendingPlayerUpdate

local function finishPendingPlayer(player)
    if pendingPlayers[player] == nil then
        return
    end

    pendingPlayers[player] = nil
    pendingPlayerCount = pendingPlayerCount - 1

    if pendingPlayerCount <= 0 then
        pendingPlayerCount = 0
        Events.OnPlayerUpdate.Remove(onPendingPlayerUpdate)
        playerUpdateInstalled = false
    end
end

onPendingPlayerUpdate = function(player)
    local updateCount = pendingPlayers[player]
    if updateCount == nil then
        return
    end

    updateCount = updateCount + 1
    pendingPlayers[player] = updateCount

    local onlineID = player:getOnlineID()
    if updateCount >= JOIN_UPDATE_TIMEOUT and (onlineID == nil or onlineID < 0) then
        print("[RealisticBackpacksB42] Cancelled server inventory refresh because the player connection did not complete in time.")
        finishPendingPlayer(player)
        return
    end

    if updateCount < JOIN_UPDATE_DELAY or onlineID == nil or onlineID < 0 then
        return
    end

    sendClientCommand(player, RB_Sandbox.COMMAND_MODULE, RB_Sandbox.COMMAND_REFRESH, {})
    print("[RealisticBackpacksB42] Sent server inventory refresh after player connection completed.")
    finishPendingPlayer(player)
end

local function onCreatePlayer(_, player)
    if not player then
        return
    end

    if not isClient() then
        local values = RB_Sandbox.getConfiguredValues()
        RB_Sandbox.applyToScriptItems(values)
        local updated = RB_Sandbox.updatePlayer(player, values)
        print("[RealisticBackpacksB42] Refreshed " .. tostring(updated) .. " backpack(s) while loading the singleplayer character.")
        return
    end

    if pendingPlayers[player] == nil then
        pendingPlayers[player] = 0
        pendingPlayerCount = pendingPlayerCount + 1
    end
    if not playerUpdateInstalled then
        Events.OnPlayerUpdate.Add(onPendingPlayerUpdate)
        playerUpdateInstalled = true
    end
end

local function onServerCommand(module, command, args)
    if module ~= RB_Sandbox.COMMAND_MODULE then
        return
    end
    if command ~= RB_Sandbox.COMMAND_REFRESH_COMPLETE then
        return
    end

    if type(args) ~= "table" then
        return
    end
    local ccActive = RB_CustomizableContainers.isActive()
    if (args.customizableContainers == true) ~= ccActive then
        print("[RealisticBackpacksB42] Settings not applied: Customizable Containers activation differs between server and client.")
        return
    end
    if ccActive and not RB_CustomizableContainers.receiveServerSettings(args.ccSettings) then
        print("[RealisticBackpacksB42] Settings not applied: incomplete Customizable Containers server response.")
        return
    end
    local values = RB_Sandbox.getCommandValues(args)
    RB_Sandbox.applyToScriptItems(values)

    local player = getPlayer()
    local clientUpdated = RB_Sandbox.updatePlayer(player, values)
    local serverUpdated = args and args.updated or 0
    print("[RealisticBackpacksB42] Applied authoritative server settings: server=" .. tostring(serverUpdated) .. ", client=" .. tostring(clientUpdated) .. " backpack(s) updated.")
end

Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnServerCommand.Add(onServerCommand)
