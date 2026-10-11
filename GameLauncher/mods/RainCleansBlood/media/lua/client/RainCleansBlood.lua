RainCleansBlood = {
    options = {
        tilesPerTick = 8,
        weatherIntensityThreshold = 0.25,
    },
    state = {
    },
}

local modOptions = {
    options = {
        enabled = true,
        alsoCleanAsh = true,
        alwaysCleanEverything = false,
    },
    names = {
        enabled = "Enabled",
        alsoCleanAsh = "Also clean ash (default: on)",
        alwaysCleanEverything = "Also clean inside and when not raining (default: off)",
    },
    mod_id = "RainCleansBlood",
    mod_shortname = "Rain Cleans Blood",
}

if ModOptions and ModOptions.getInstance then
    ModOptions:getInstance(modOptions)
end


-- -------------------------------------------------------------------------- --
--                                   Update                                   --
-- -------------------------------------------------------------------------- --
function RainCleansBlood:onTick()
    if not self:shouldClean() then
        return
    end

    for _ = 1, self.options.tilesPerTick do
        local tile = self:getRandomOutdoorTile()

        if tile then
            if tile:haveBlood() then
                tile:removeBlood(false, false)
            end

            if modOptions.options.alsoCleanAsh then
                local objects = tile:getObjects()

                -- Iterate backwards: removing shrinks the list.
                for i = objects:size() - 1, 0, -1 do
                    local object = objects:get(i)

                    if object and object:getName() == "burnedCorpse" then
                        tile:transmitRemoveItemFromSquare(object)
                    end
                end
            end
        end
    end
end

-- -------------------------------------------------------------------------- --
--                                   Helpers                                  --
-- -------------------------------------------------------------------------- --
function RainCleansBlood:getWeatherIntensity()
    local climateManager = getClimateManager()

    return math.max(
        climateManager:getRainIntensity(),
        climateManager:getSnowIntensity()
    );
end

function RainCleansBlood:isWeatherIntensityAboveThreshold()
    return self:getWeatherIntensity() > self.options.weatherIntensityThreshold;
end

function RainCleansBlood:shouldClean()
    if not modOptions.options.enabled then
        return false
    end

    if modOptions.options.alwaysCleanEverything then
        return true
    end

    if not self:isWeatherIntensityAboveThreshold() then
        return false
    end

    return true
end

function RainCleansBlood:getRandomOutdoorTile()
    local cell = getCell()
    local minX = cell:getMinX()
    local minY = cell:getMinY()
    local maxX = cell:getMaxX()
    local maxY = cell:getMaxY()

    for _ = 1, 10 do
        local x = ZombRand(minX, maxX)
        local y = ZombRand(minY, maxY)
        local tile = cell:getGridSquare(x, y, 0)

        if tile and (tile:isOutside() or modOptions.options.alwaysCleanEverything) then
            return tile
        end
    end

    return nil
end

-- -------------------------------------------------------------------------- --
--                                 Hook events                                --
-- -------------------------------------------------------------------------- --
Events.OnTick.Add(function() RainCleansBlood:onTick() end);
