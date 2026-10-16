require "ProjectALife/World/ALifeSafehouseFx"

ProjectALife = ProjectALife or {}

local Client = {}
ProjectALife.SafehouseFxClient = Client

function Client.onServerCommand(module, command, arguments)
    if module ~= "ProjectALife" or command ~= "safehouseFx" then return end
    local fx = ProjectALife.SafehouseFx
    if fx == nil or type(fx.handle) ~= "function" then return end
    fx.handle(arguments)
end

if type(Events) == "table" and Events.OnServerCommand ~= nil and type(Events.OnServerCommand.Add) == "function" then
    Events.OnServerCommand.Add(Client.onServerCommand)
end

return Client
