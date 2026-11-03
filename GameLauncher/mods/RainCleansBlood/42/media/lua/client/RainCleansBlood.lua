RainCleansBlood = RainCleansBlood or { id = "RainCleansBlood" }

-- -------------------------------------------------------------------------- --
--                                 Hook events                                --
-- -------------------------------------------------------------------------- --
-- Mirrors the server's clothing/weapon changes onto the client's copy of the
-- items so the player sees them fade.
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= RainCleansBlood.id or command ~= "applyClean" then
        return
    end

    local player = getPlayer()
    if not player or not args or not args.changes then
        return
    end

    local inventory = player:getInventory()

    for _, change in pairs(args.changes) do
        local item = inventory:getItemWithID(tonumber(change.id))

        if item then
            if change.parts then
                for _, p in pairs(change.parts) do
                    local part = BloodBodyPartType.FromIndex(tonumber(p.part))
                    item:setBlood(part, p.blood or 0)
                    item:setDirt(part, p.dirt or 0)
                end
            end

            if change.blood ~= nil then
                item:setBloodLevel(change.blood)
            end
        end
    end

    player:resetModelNextFrame()
end)
