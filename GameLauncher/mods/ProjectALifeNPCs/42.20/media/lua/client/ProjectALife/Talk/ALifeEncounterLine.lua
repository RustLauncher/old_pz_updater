ProjectALife = ProjectALife or {}

local Line = { metrics = { received = 0 } }
ProjectALife.EncounterLine = Line

function Line.onServerCommand(module, command, arguments)
    if module ~= "ProjectALife" or command ~= "encounterLine" or type(arguments) ~= "table" then return end
    if type(arguments.text) ~= "string" or arguments.text == "" then return end
    local receive = ProjectALife.TalkClientReceive
    if type(receive) ~= "function" then return end
    Line.metrics.received = Line.metrics.received + 1
    pcall(receive, "ProjectALife", "speech", { uid = arguments.uid, text = arguments.text })
end

if type(Events) == "table" and Events.OnServerCommand ~= nil and type(Events.OnServerCommand.Add) == "function" then
    Events.OnServerCommand.Add(Line.onServerCommand)
end

return Line
