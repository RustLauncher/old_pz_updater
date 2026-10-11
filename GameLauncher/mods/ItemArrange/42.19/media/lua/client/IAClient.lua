IAClient = IACClient or {}

IAClient.Arrange = function(args)
    local square = getCell():getGridSquare(args.x, args.y, args.z)
    if square then
        IA.ArrangeItems(square)
    end
end

local onServerCommand = function(module, command, args)
    if module == "Commands" and IAClient[command] then
        IAClient[command](args)
    end
end

Events.OnServerCommand.Remove(onServerCommand)
Events.OnServerCommand.Add(onServerCommand)