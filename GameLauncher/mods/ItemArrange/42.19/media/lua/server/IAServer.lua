IAServer = IAServer or {}

IAServer.DropItem = function(player, args)
    local item = args.item

    if item and args.x and args.y and args.z then
        local dropSquare = getCell():getGridSquare(args.x, args.y, args.z)
        if dropSquare then
            dropSquare:AddWorldInventoryItem(item, 0.5, 0.5, 0.0)
            player:getInventory():DoRemoveItem(item)
            sendServerCommand('Commands', 'Arrange', {x = args.x, y = args.y, z = args.z})
        end
    else
        print ("IAServer.DropItem: missing item or coordinates")
    end
end

local onClientCommand = function(module, command, player, args)
    if module == "Commands" and IAServer[command] then
        IAServer[command](player, args)
    end
end

Events.OnClientCommand.Remove(onClientCommand)
Events.OnClientCommand.Add(onClientCommand)