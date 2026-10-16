ProjectALife = ProjectALife or {}

local DayCycle = {
    settings = {
        enterDark = 0.25,
        leaveDark = 0.35,
    },
    adapters = {},
    dark = false,
}
ProjectALife.DayCycle = DayCycle

function DayCycle.daylight()
    if type(DayCycle.adapters.daylight) == "function" then
        return tonumber(DayCycle.adapters.daylight())
    end
    local value
    pcall(function()
        if type(getClimateManager) ~= "function" then return end
        local climate = getClimateManager()
        if climate == nil or climate.getDayLightStrength == nil then return end
        value = climate:getDayLightStrength()
    end)
    return tonumber(value)
end

function DayCycle.latch(dark, light, s)
    s = s or DayCycle.settings
    if tonumber(light) == nil then return dark == true end
    if dark == true then return light < s.leaveDark end
    return light < s.enterDark
end

function DayCycle.seasonNight()
    local night
    pcall(function()
        if type(getClimateManager) ~= "function" or type(getGameTime) ~= "function" then return end
        local season = getClimateManager():getSeason()
        if season == nil or season.getDawn == nil or season.getDusk == nil then return end
        local time = getGameTime()
        if time == nil or time.getTimeOfDay == nil then return end
        local hour, dawn, dusk = tonumber(time:getTimeOfDay()), tonumber(season:getDawn()), tonumber(season:getDusk())
        if hour == nil or dawn == nil or dusk == nil then return end
        night = hour >= dusk or hour < dawn
    end)
    return night
end

function DayCycle.isNight()
    if type(DayCycle.adapters.isNight) == "function" then
        return DayCycle.adapters.isNight() == true
    end
    local light = DayCycle.daylight()
    if light ~= nil then
        DayCycle.dark = DayCycle.latch(DayCycle.dark, light)
        return DayCycle.dark
    end
    local seasonal = DayCycle.seasonNight()
    if seasonal ~= nil then DayCycle.dark = seasonal end
    return DayCycle.dark == true
end

function DayCycle.dawnPassed()
    return not DayCycle.isNight()
end

function DayCycle.reset()
    DayCycle.dark = false
    DayCycle.adapters = {}
    return true
end

return DayCycle
