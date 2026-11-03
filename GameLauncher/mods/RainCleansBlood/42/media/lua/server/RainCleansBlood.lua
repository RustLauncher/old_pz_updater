-- Server-authoritative in MP. Clients also load server/ scripts, so bail out
-- there to avoid every client running its own (unsynced) cleaning pass.
if isClient() then
    return
end

RainCleansBlood = RainCleansBlood or { id = "RainCleansBlood" }

-- How far from each player (in tiles) we look for things to clean.
RainCleansBlood.radius = 50

-- -------------------------------------------------------------------------- --
--                                  Handlers                                  --
-- -------------------------------------------------------------------------- --
function RainCleansBlood:onEveryOneMinute()
    if not self:shouldClean() then
        return
    end

    local cell = getCell()
    if not cell then
        return
    end

    local players = self:getPlayers()
    local tilesPerPlayer = SandboxVars.RainCleansBlood.TilesPerMinuteNearPlayer or 300

    for _, player in ipairs(players) do
        for _ = 1, tilesPerPlayer do
            local tile, wallOnly = self:getNextTile(cell, player)

            if tile then
                self:cleanTile(tile, wallOnly)
            end
        end
    end

    if SandboxVars.RainCleansBlood.AlsoCleanVehicles then
        self:cleanNearbyVehicles(cell)
    end

    if SandboxVars.RainCleansBlood.AlsoCleanClothes then
        for _, player in ipairs(players) do
            local square = player:getCurrentSquare()
            if square and (square:isOutside() or SandboxVars.RainCleansBlood.AlsoCleanInside) then
                self:cleanAndSyncPlayer(player)
            end
        end
    end
end


-- -------------------------------------------------------------------------- --
--                                   Methods                                  --
-- -------------------------------------------------------------------------- --
function RainCleansBlood:cleanTile(tile, wallOnly)
    if tile:haveBlood() then
        tile:removeBlood(false, wallOnly)
    end

    if wallOnly then
        return
    end

    if SandboxVars.RainCleansBlood.AlsoCleanAsh ~= false then
        self:cleanAsh(tile)
    end

    if SandboxVars.RainCleansBlood.AlsoCleanDroppings ~= false then
        self:cleanDung(tile)
    end
end

function RainCleansBlood:cleanAsh(tile)
    local objects = tile:getObjects()

    -- Iterate backwards: removing shrinks the list.
    for i = objects:size() - 1, 0, -1 do
        local object = objects:get(i)

        if object and object:getName() == "burnedCorpse" then
            -- Removes the object and, on a server, tells clients about it.
            tile:transmitRemoveItemFromSquare(object)
        end
    end
end

function RainCleansBlood:cleanDung(tile)
    local worldObjects = tile:getWorldObjects()

    for i = worldObjects:size() - 1, 0, -1 do
        local worldObject = worldObjects:get(i)
        local item = worldObject and worldObject:getItem()
        local itemType = item and item:getType()

        if itemType and string.sub(itemType, 1, 4) == "Dung" then
            tile:transmitRemoveItemFromSquare(worldObject)
            tile:getWorldObjects():remove(worldObject)
            tile:getObjects():remove(worldObject)
            item:setWorldItem(nil)
        end
    end

    -- Fallback for any dung we didn't recognise by type.
    if tile.checkHaveDung and tile:checkHaveDung() then
        tile:removeAllDung()
    end
end

function RainCleansBlood:cleanNearbyVehicles(cell)
    local vehicles = cell:getVehicles()
    local speed = (SandboxVars.RainCleansBlood.VehicleCleanSpeed or 0.1) / 1000

    -- getVehicles() is a Set in B42 (no get(i)), so walk it with an iterator.
    local iterator = vehicles:iterator()
    while iterator:hasNext() do
        local vehicle = iterator:next()
        local square = vehicle and vehicle:getSquare()

        if square and (square:isOutside() or SandboxVars.RainCleansBlood.AlsoCleanInside) then
            local changed = false

            for _, side in ipairs({ "Front", "Rear", "Left", "Right" }) do
                local blood = vehicle:getBloodIntensity(side) or 0
                if blood > 0 then
                    vehicle:setBloodIntensity(side, math.max(0, blood - speed))
                    changed = true
                end
            end

            if changed and isServer() then
                vehicle:transmitBlood()
            end
        end
    end
end

function RainCleansBlood:cleanAndSyncPlayer(player)
    local changes = {}
    local speed = (SandboxVars.RainCleansBlood.ClothesCleanSpeed or 1.0) / 100
    local wornItems = player:getWornItems()

    -- Worn clothing: fade each body part individually so blood on one sleeve
    -- doesn't get smeared across the whole garment.
    for i = 0, wornItems:size() - 1 do
        local item = wornItems:get(i):getItem()

        if item and instanceof(item, "Clothing") then
            local coveredParts = BloodClothingType.getCoveredParts(item:getBloodClothingType())
            local parts = {}

            if coveredParts then
                for k = 0, coveredParts:size() - 1 do
                    local part = coveredParts:get(k)
                    local blood = item:getBlood(part) or 0
                    local dirt  = item:getDirt(part) or 0

                    if blood > 0 or dirt > 0 then
                        local newBlood = math.max(0, blood - speed)
                        local newDirt  = math.max(0, dirt - speed)
                        item:setBlood(part, newBlood)
                        item:setDirt(part, newDirt)
                        table.insert(parts, { part = part:index(), blood = newBlood, dirt = newDirt })
                    end
                end
            end

            if #parts > 0 then
                table.insert(changes, { id = item:getID(), parts = parts })
            end
        end
    end

    -- Weapons in hand (blood level is 0..1).
    local primary = player:getPrimaryHandItem()
    local secondary = player:getSecondaryHandItem()
    local handItems = { primary }
    if secondary and secondary ~= primary then
        table.insert(handItems, secondary)
    end

    for _, item in ipairs(handItems) do
        if item and instanceof(item, "HandWeapon") then
            local blood = tonumber(item:getBloodLevel())
            if blood and blood > 0 then
                local newBlood = math.max(0, blood - speed)
                item:setBloodLevel(newBlood)
                table.insert(changes, { id = item:getID(), blood = newBlood })
            end
        end
    end

    -- The character's skin.
    local visualChanged = false
    local humanVisual = player:getHumanVisual()
    if humanVisual then
        for i = 0, BloodBodyPartType.MAX:index() - 1 do
            local part = BloodBodyPartType.FromIndex(i)
            local blood = humanVisual:getBlood(part)
            local dirt  = humanVisual:getDirt(part)

            if blood and blood > 0 then
                humanVisual:setBlood(part, math.max(0, blood - speed))
                visualChanged = true
            end

            if dirt and dirt > 0 then
                humanVisual:setDirt(part, math.max(0, dirt - speed))
                visualChanged = true
            end
        end
    end

    if not visualChanged and #changes == 0 then
        return
    end

    player:resetModelNextFrame()

    if isServer() then
        syncVisuals(player)

        if #changes > 0 then
            sendServerCommand(player, self.id, "applyClean", { changes = changes })
        end
    end
end


-- -------------------------------------------------------------------------- --
--                                   Helpers                                  --
-- -------------------------------------------------------------------------- --
function RainCleansBlood:shouldClean()
    if SandboxVars.RainCleansBlood.AlwaysClean then
        return true
    end

    local climateManager = getClimateManager()
    if not climateManager then
        return false
    end

    local intensity = math.max(
        climateManager:getRainIntensity(),
        climateManager:getSnowIntensity()
    )

    return intensity > (SandboxVars.RainCleansBlood.WeatherThreshold or 0.25)
end

function RainCleansBlood:getPlayers()
    local result = {}

    if isServer() then
        local players = getOnlinePlayers()
        if players then
            for i = 0, players:size() - 1 do
                local player = players:get(i)
                if player and not player:isDead() then
                    table.insert(result, player)
                end
            end
        end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local player = getSpecificPlayer(i)
            if player and not player:isDead() then
                table.insert(result, player)
            end
        end
    end

    return result
end

-- Picks a random loaded tile near the player. Returns the tile and whether
-- only its wall blood should be cleaned (an indoor tile whose north/west wall
-- faces the outside).
function RainCleansBlood:getNextTile(cell, player)
    local radius = self.radius
    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local cleanInside = SandboxVars.RainCleansBlood.AlsoCleanInside

    for _ = 1, 10 do
        local x = px + ZombRand(-radius, radius + 1)
        local y = py + ZombRand(-radius, radius + 1)
        local tile = cell:getGridSquare(x, y, 0)

        if tile then
            if cleanInside or tile:isOutside() then
                return tile, false
            end

            local north = cell:getGridSquare(x, y - 1, 0)
            local west  = cell:getGridSquare(x - 1, y, 0)
            if (north and north:isOutside()) or (west and west:isOutside()) then
                return tile, true
            end
        end
    end

    return nil
end


-- -------------------------------------------------------------------------- --
--                                 Hook events                                --
-- -------------------------------------------------------------------------- --
Events.EveryOneMinute.Add(function() RainCleansBlood:onEveryOneMinute() end)
