ProjectALife = ProjectALife or {}

local Fill = {
    fills = setmetatable({}, { __mode = "k" }),
    tick = 0,
    settings = { everyTicks = 90, radius = 20, maxFills = 32, nightFrom = 0.5, scale = 0.9 },
    metrics = { passes = 0, added = 0, removed = 0, night = false },
}
ProjectALife.SiteLightsClient = Fill

function Fill.enabled()
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(vars) == "table" and vars.Outposts_LightsOn ~= nil then return vars.Outposts_LightsOn == true end
    return true
end

function Fill.isNight()
    if type(getGameTime) ~= "function" then return false end
    local time = getGameTime()
    if time == nil or type(time.getNight) ~= "function" then return false end
    return (tonumber(time:getNight()) or 0) >= Fill.settings.nightFrom
end

function Fill.marked(switch)
    if switch == nil or type(switch.couldBePoweredByGenerator) ~= "function" or switch:couldBePoweredByGenerator() ~= false then
        return false
    end
    if type(switch.hasModData) ~= "function" or switch:hasModData() ~= true then return false end
    local data = switch:getModData()
    return type(data) == "table" and data.ProjectALifeFill ~= nil
end

function Fill.switchOf(light)
    if type(light.getSwitches) ~= "function" then return nil end
    local list = light:getSwitches()
    if list == nil or list:size() == 0 then return nil end
    return list:get(0)
end

function Fill.add(cell, light, switch)
    local settings = Fill.settings
    local scale = settings.scale
    local fill = IsoLightSource.new(light:getX(), light:getY(), light:getZ(),
        (tonumber(switch:getPrimaryR()) or 1) * scale, (tonumber(switch:getPrimaryG()) or 1) * scale,
        (tonumber(switch:getPrimaryB()) or 1) * scale, settings.radius)
    cell:getLamppostPositions():add(fill)
    Fill.fills[light] = fill
    Fill.metrics.added = Fill.metrics.added + 1
    if Fill.metrics.added <= 6 then
        print("[A-Life] site fill light " .. tostring(Fill.metrics.added) .. " at " .. tostring(light:getX()) .. ","
            .. tostring(light:getY()) .. "," .. tostring(light:getZ()))
    end
    return fill
end

function Fill.release(cell, fill)
    if type(cell.removeLamppost) == "function" then cell:removeLamppost(fill) end
    Fill.metrics.removed = Fill.metrics.removed + 1
end

function Fill.pass()
    if IsoLightSource == nil or type(getCell) ~= "function" then return 0 end
    local cell = getCell()
    if cell == nil or type(cell.getLamppostPositions) ~= "function" then return 0 end
    local positions = cell:getLamppostPositions()
    if positions == nil then return 0 end
    local night, live, changes = Fill.isNight(), 0, 0
    Fill.metrics.passes, Fill.metrics.night = Fill.metrics.passes + 1, night
    for index = 0, positions:size() - 1 do
        local light = positions:get(index)
        local switch = light ~= nil and Fill.switchOf(light) or nil
        if switch ~= nil and Fill.marked(switch) then
            live = live + 1
            local fill = Fill.fills[light]
            if fill == nil and live <= Fill.settings.maxFills then
                fill = Fill.add(cell, light, switch)
                changes = changes + 1
            end
            if fill ~= nil and fill:isActive() ~= night then
                fill:setActive(night)
                changes = changes + 1
            end
        end
    end
    return changes
end

function Fill.clear()
    if type(getCell) ~= "function" then return end
    local cell = getCell()
    for light, fill in pairs(Fill.fills) do
        if cell ~= nil then Fill.release(cell, fill) end
        Fill.fills[light] = nil
    end
end

function Fill.onTick()
    Fill.tick = Fill.tick + 1
    if Fill.tick % Fill.settings.everyTicks ~= 0 then return end
    if not Fill.enabled() then
        Fill.clear()
        return
    end
    Fill.pass()
end

if Events ~= nil and Events.OnTick ~= nil then Events.OnTick.Add(Fill.onTick) end

return Fill
