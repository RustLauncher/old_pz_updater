ProjectALife = ProjectALife or {}

local Seasons = {
    hotAboveC = 31,
    coldBelowC = 3,
    ttlMs = 4000,
    cache = nil,
}
ProjectALife.Seasons = Seasons

Seasons.wardrobeCfg = {
    edges = { 4, 12, 22 },
    hysteresisC = 1,
    coolSpringAboveC = 8,
    tauHours = 14,
    pushBands = 1,
    wetTauHours = 3,
    stepHours = 0.25,
    wetOn = 0.35,
    wetOff = 0.15,
    windOnKph = 30,
    windOffKph = 22,
    windBelowC = 16,
    groundOn = 0.35,
    groundBelowC = 8,
    nightFrom = 20,
    nightTo = 6,
    storeTag = "ProjectALife.WardrobeSeason.v1",
    names = { "cold", "cool", "mild", "warm" },
}
Seasons.wardrobeCache = nil
Seasons.wardrobeOverride = nil

function Seasons.nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Seasons.clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

function Seasons.ofMonth(month)
    month = tonumber(month)
    if month == nil or month < 0 or month >= 12 then return nil end
    month = math.floor(month)
    if month <= 1 or month == 11 then return "winter" end
    if month <= 4 then return "spring" end
    if month <= 7 then return "summer" end
    return "autumn"
end

function Seasons.current()
    local month = nil
    if type(getGameTime) == "function" then
        local ok, value = pcall(function() return getGameTime():getMonth() end)
        if ok then month = value end
    end
    return Seasons.ofMonth(month) or "summer"
end

function Seasons.weather(now)
    if type(getClimateManager) ~= "function" then
        Seasons.cache = nil
        return nil
    end
    now = tonumber(now) or Seasons.nowMs()
    local cached = Seasons.cache
    if cached ~= nil and now - cached.atMs < Seasons.ttlMs then return cached end
    local ok, climate = pcall(getClimateManager)
    if not ok or climate == nil then return nil end
    local w = cached or {}
    w.atMs, w.climate = now, climate
    local function read(name, fallback)
        if type(climate[name]) ~= "function" then return fallback end
        local okRead, value = pcall(climate[name], climate)
        if okRead and value ~= nil then return value end
        return fallback
    end
    local air = tonumber(read("getTemperature", nil))
    if air ~= nil and (air ~= air or air > 200 or air < -200) then air = nil end
    w.hasAir = air ~= nil
    w.air = air or 15
    w.wind = tonumber(read("getWindspeedKph", 0)) or 0
    w.rain = Seasons.clamp(tonumber(read("getRainIntensity", 0)) or 0, 0, 1)
    w.snowing = read("isSnowing", false) == true
    w.snow = Seasons.clamp(tonumber(read("getSnowIntensity", 0)) or 0, 0, 1)
    w.ground = Seasons.clamp(tonumber(read("getSnowFracNow", 0)) or 0, 0, 1)
    w.fog = Seasons.clamp(tonumber(read("getFogIntensity", 0)) or 0, 0, 1)
    Seasons.cache = w
    return w
end

function Seasons.skyOf(w)
    if w == nil then return "clear" end
    if w.snowing or (w.ground > 0.35 and w.air < 2) then return "snow" end
    if w.rain > 0.55 and w.wind > 25 then return "storm" end
    if w.rain > 0.08 then return "rain" end
    if w.fog > 0.5 then return "fog" end
    if w.air >= Seasons.hotAboveC - 3 then return "hot" end
    if w.air <= Seasons.coldBelowC then return "cold" end
    return "clear"
end

function Seasons.sky(now)
    return Seasons.skyOf(Seasons.weather(now))
end

function Seasons.reset()
    Seasons.cache = nil
end

function Seasons.gameHours()
    if type(getGameTime) ~= "function" then return nil end
    local time = getGameTime()
    if time == nil or type(time.getWorldAgeHours) ~= "function" then return nil end
    local value = tonumber(time:getWorldAgeHours())
    if value == nil or value ~= value then return nil end
    return value
end

function Seasons.isNight()
    local override = Seasons.wardrobeOverride
    if override ~= nil and override.night ~= nil then return override.night == true end
    if type(getGameTime) ~= "function" then return false end
    local time = getGameTime()
    if time == nil or type(time.getHour) ~= "function" then return false end
    local hour = tonumber(time:getHour())
    if hour == nil then return false end
    local cfg = Seasons.wardrobeCfg
    return hour >= cfg.nightFrom or hour < cfg.nightTo
end

function Seasons.bandOf(temp, previous)
    local cfg = Seasons.wardrobeCfg
    local edges, margin = cfg.edges, cfg.hysteresisC
    temp = tonumber(temp) or 15
    previous = tonumber(previous)
    if previous == nil or previous < 1 or previous > 4 then
        if temp <= edges[1] then return 1 end
        if temp < edges[2] then return 2 end
        if temp < edges[3] then return 3 end
        return 4
    end
    local band = math.floor(previous)
    while band < 4 and temp >= edges[band] + margin do band = band + 1 end
    while band > 1 and temp <= edges[band - 1] - margin do band = band - 1 end
    return band
end

function Seasons.warmingHalf(calendar)
    return calendar == "spring" or calendar == "summer"
end

function Seasons.seasonOfBand(band, calendar, temp)
    local cfg = Seasons.wardrobeCfg
    if band <= 1 then return "winter" end
    if band >= 4 then return "summer" end
    local warming = Seasons.warmingHalf(calendar)
    if band == 3 then return warming and "spring" or "autumn" end
    if warming and (tonumber(temp) or 0) >= cfg.coolSpringAboveC then return "spring" end
    return "autumn"
end

function Seasons.wardrobeState()
    local state = Seasons.wardrobeCache
    if state ~= nil then return state end
    if type(ModData) == "table" and type(ModData.getOrCreate) == "function" then
        local ok, data = pcall(ModData.getOrCreate, Seasons.wardrobeCfg.storeTag)
        if ok and type(data) == "table" then state = data end
    end
    state = state or {}
    Seasons.wardrobeCache = state
    return state
end

function Seasons.wardrobeSample()
    local override = Seasons.wardrobeOverride
    if override ~= nil then
        return { temp = override.tempC, wet = override.wet or 0, wind = override.wind or 0,
            ground = override.ground or 0, override = true }
    end
    local w = Seasons.weather()
    if w == nil or w.hasAir ~= true then return nil end
    return { temp = w.air, wet = math.max(w.rain, w.snow), wind = w.wind, ground = w.ground, override = false }
end

function Seasons.setWardrobeOverride(tempC, extra)
    local state = Seasons.wardrobeState()
    state.temp, state.wet, state.wind, state.hours, state.band = nil, nil, nil, nil, nil
    state.wetOn, state.windOn, state.override = nil, nil, nil
    if tonumber(tempC) == nil then
        Seasons.wardrobeOverride = nil
        return nil
    end
    extra = type(extra) == "table" and extra or {}
    Seasons.wardrobeOverride = { tempC = tonumber(tempC), wet = tonumber(extra.wet), wind = tonumber(extra.wind),
        ground = tonumber(extra.ground), night = extra.night }
    return Seasons.wardrobeOverride
end

function Seasons.wardrobeUpdate()
    local cfg = Seasons.wardrobeCfg
    local sample = Seasons.wardrobeSample()
    if sample == nil then return nil end
    local state = Seasons.wardrobeState()
    local hours = Seasons.gameHours()
    local direct = sample.override == true or state.temp == nil or (state.override == true) ~= sample.override
    if not direct and hours ~= nil and state.hours ~= nil then
        direct = hours < state.hours
    end
    if direct then
        state.temp, state.wet, state.wind = sample.temp, sample.wet, sample.wind
        state.hours, state.override = hours, sample.override == true
    elseif hours ~= nil and state.hours ~= nil then
        local elapsed = hours - state.hours
        if elapsed >= cfg.stepHours then
            local alpha = elapsed / (cfg.tauHours + elapsed)
            local wetAlpha = elapsed / (cfg.wetTauHours + elapsed)
            state.temp = state.temp + (sample.temp - state.temp) * alpha
            state.wet = state.wet + (sample.wet - state.wet) * wetAlpha
            state.wind = state.wind + (sample.wind - state.wind) * wetAlpha
            state.hours = hours
        end
    elseif hours ~= nil then
        state.hours = hours
    end
    state.raw, state.ground = sample.temp, sample.ground
    state.band = Seasons.bandOf(state.temp, state.band)
    if state.wet >= cfg.wetOn then state.wetOn = true elseif state.wet <= cfg.wetOff then state.wetOn = false end
    if state.wind >= cfg.windOnKph then state.windOn = true elseif state.wind <= cfg.windOffKph then state.windOn = false end
    return state
end

function Seasons.wardrobePush(state)
    local cfg = Seasons.wardrobeCfg
    local reasons = {}
    if state.wetOn == true then reasons[#reasons + 1] = "wet" end
    if state.windOn == true and state.temp < cfg.windBelowC then reasons[#reasons + 1] = "wind" end
    if (tonumber(state.ground) or 0) >= cfg.groundOn and state.temp < cfg.groundBelowC then
        reasons[#reasons + 1] = "snow"
    end
    return reasons
end

function Seasons.wardrobe(calendar)
    local state = Seasons.wardrobeUpdate()
    if state == nil then return nil end
    calendar = calendar or Seasons.current()
    local band = state.band
    local reasons = Seasons.wardrobePush(state)
    local effective = band
    if #reasons > 0 and band > 1 and band < 4 then effective = math.max(1, band - Seasons.wardrobeCfg.pushBands) end
    local base = Seasons.seasonOfBand(band, calendar, state.temp)
    local season = Seasons.seasonOfBand(effective, calendar, state.temp)
    local night = nil
    if #reasons == 0 and band > 1 and band < 4 then
        night = Seasons.seasonOfBand(band - 1, calendar, state.temp)
        if night == season then night = nil end
    end
    return season, {
        source = state.override == true and "override" or "climate", band = band, bandName = Seasons.wardrobeCfg.names[band],
        effective = effective, temp = state.raw, smoothed = state.temp, push = table.concat(reasons, "+"),
        base = base, nightSeason = night, calendar = calendar, wet = state.wet, wind = state.wind,
    }
end

function Seasons.wardrobeHint(calendar)
    local sample = Seasons.wardrobeSample()
    calendar = calendar or Seasons.current()
    if sample == nil then return calendar, nil, nil end
    local band = Seasons.bandOf(sample.temp, nil)
    return Seasons.seasonOfBand(band, calendar, sample.temp), band, sample.temp
end

return Seasons
