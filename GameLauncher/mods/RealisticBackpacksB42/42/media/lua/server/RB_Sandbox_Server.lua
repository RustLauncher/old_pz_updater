require "RB_Sandbox"

local function onClientCommand(module, command, player, _)
    if module ~= RB_Sandbox.COMMAND_MODULE then
        return
    end
    if command ~= RB_Sandbox.COMMAND_REFRESH then
        return
    end
    if not player then
        return
    end

    local values = RB_Sandbox.getConfiguredValues()
    RB_Sandbox.applyToScriptItems(values)
    local updated = RB_Sandbox.updatePlayer(player, values)
    print("[RealisticBackpacksB42] Server refreshed " .. tostring(updated) .. " backpack(s) for a joining player.")
    local response = RB_Sandbox.getCommandArguments(values)
    response.updated = updated
    response.customizableContainers = RB_CustomizableContainers.isActive()
    if response.customizableContainers then
        response.ccSettings = RB_CustomizableContainers.getServerSettings()
    end
    sendServerCommand(
        player,
        RB_Sandbox.COMMAND_MODULE,
        RB_Sandbox.COMMAND_REFRESH_COMPLETE,
        response
    )
end

Events.OnClientCommand.Add(onClientCommand)

local function initialiseServerTemplates()
    local values = RB_Sandbox.getConfiguredValues()
    RB_Sandbox.applyToScriptItems(values)
    print("[RealisticBackpacksB42] Applied authoritative sandbox values to server backpack templates.")
end

Events.OnServerStarted.Add(initialiseServerTemplates)
