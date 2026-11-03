ProjectALife = ProjectALife or {}

local StatusStore = {
    value = nil,
    reputation = nil,
    listeners = {},
}
ProjectALife.StatusStore = StatusStore

function StatusStore.subscribe(listener)
    if type(listener) ~= "function" then return false end
    StatusStore.listeners[#StatusStore.listeners + 1] = listener
    return true
end

function StatusStore.request(player)
    if player == nil then return false end
    if type(isClient) == "function" and isClient()
            and type(sendClientCommand) == "function" then
        sendClientCommand(player, "ProjectALife", "requestStatus", {})
        return true
    end
    local service = ProjectALife.StatusService
    if service ~= nil and type(service.handle) == "function" then

        service.handle("ProjectALife", "requestStatus", player)
        return true
    end
    if type(sendClientCommand) ~= "function" then return false end
    sendClientCommand(player, "ProjectALife", "requestStatus", {})
    return true
end

local function onPlayerDeath(player)
    if player ~= nil and type(sendClientCommand) == "function" then
        sendClientCommand(player, "ProjectALife", "playerDied", {})
    end
end

local function onServerCommand(module, command, arguments)
    if module ~= "ProjectALife" or type(arguments) ~= "table" then return end
    if command == "reputationSync" then
        StatusStore.reputation = arguments
        local notify = ProjectALife.RepNotify
        if notify ~= nil and type(notify.observe) == "function" then pcall(notify.observe, arguments.personal) end
        return
    end
    if command ~= "status" then return end
    StatusStore.value = arguments
    for _, listener in ipairs(StatusStore.listeners) do listener(arguments) end
end

StatusStore.receive = onServerCommand

if type(Events) == "table" and Events.OnServerCommand ~= nil then
    Events.OnServerCommand.Add(onServerCommand)
end
if type(Events) == "table" and Events.OnPlayerDeath ~= nil then
    Events.OnPlayerDeath.Add(onPlayerDeath)
end

return StatusStore
