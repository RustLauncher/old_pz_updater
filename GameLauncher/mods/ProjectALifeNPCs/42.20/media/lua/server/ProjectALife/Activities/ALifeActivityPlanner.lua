require "ProjectALife/Activities/ALifeActivityCatalog"
require "ProjectALife/Activities/ALifeFishing"
require "ProjectALife/Activities/ALifeHunting"

ProjectALife = ProjectALife or {}

local Catalog = ProjectALife.ActivityCatalog
local Fish = ProjectALife.ActivityFishing
local Hunt = ProjectALife.ActivityHunting

local Planner = {
    settings = {
        urgencyBelow = 40,
        criticalBelow = 15,
        needScale = 10,
        dwellHours = 0.5,
        switchMargin = 3,
        jitter = 2,

        nightActivePenalty = 3,
        rainAt = 0.3, snowAt = 0.3, fogAt = 0.4, windAt = 0.5,
        stormExpedition = -4, stormShelter = 4,
        crowdPenalty = 4,
        lowHealth = 60, lowHealthExpedition = 3, lowHealthRest = 4,
        tilesPerHour = 150,

        repeatPenalty = 1.5,

        drain = { food = 0.25, water = 0.40, ammo = 0, meds = 0 },

        scavengeCredit = 12,
        otherShare = 0.5,
    },
    metrics = { decisions = 0, held = 0, arrivals = 0 },
}
ProjectALife.ActivityPlanner = Planner

function Planner.enabled()
    return Catalog.enabled()
end

function Planner.hashStep(value, text)
    for index = 1, #text do value = (value * 131 + string.byte(text, index)) % 2147483647 end
    return value
end

function Planner.fraction(value)
    return (value - math.floor(value / 10000) * 10000) / 10000
end

function Planner.stableRoll(key)
    return Planner.fraction(Planner.hashStep(7, tostring(key or "")))
end

function Planner.jitter(ctx, id)
    local prefix = ctx.seedHash
    if prefix == nil or ctx.seedHashOf ~= ctx.seed then
        prefix = Planner.hashStep(7, tostring(ctx.seed or "") .. ":")
        ctx.seedHash, ctx.seedHashOf = prefix, ctx.seed
    end
    return Planner.fraction(Planner.hashStep(prefix, id .. ":" .. tostring(ctx.day or 0)))
end

function Planner.urgency(value)
    local below = Planner.settings.urgencyBelow
    local x = tonumber(value) or 0
    if x >= below then return 0 end
    local share = (below - x) / below
    return share * share
end

function Planner.clampNeeds(needs)
    local out = {}
    for _, need in ipairs(Catalog.NEEDS) do
        local value = type(needs) == "table" and tonumber(needs[need]) or nil
        out[need] = math.max(0, math.min(100, value or 0))
    end
    return out
end

function Planner.needsOf(record)
    if type(record) == "table" and type(record.needs) == "table" then return Planner.clampNeeds(record.needs) end
    local supplies = 35
    if type(record) == "table" and tonumber(record.supplies) ~= nil then supplies = tonumber(record.supplies) end
    return Planner.clampNeeds({ food = supplies, water = math.min(100, supplies + 20), ammo = 60, meds = 40 })
end

function Planner.writeSupplies(q)
    local needs = Planner.needsOf(q)
    q.needs = needs
    q.supplies = math.min(needs.food, needs.water)
    return q.supplies
end

function Planner.drainPercent()
    local value = tonumber(Catalog.setting("NeedsDrainPercent", 100)) or 100
    return math.max(25, math.min(400, value))
end

function Planner.drain(needs, members, hours, percent)
    local out = Planner.clampNeeds(needs)
    local scale = math.max(0, tonumber(members) or 0) * math.max(0, tonumber(hours) or 0)
        * (tonumber(percent) or 100) / 100
    for _, need in ipairs(Catalog.NEEDS) do
        local rate = tonumber(Planner.settings.drain[need]) or 0
        out[need] = math.max(0, out[need] - rate * scale)
    end
    return out
end

function Planner.lowest(needs)
    local best, value = nil, math.huge
    for _, need in ipairs(Catalog.NEEDS) do
        local x = type(needs) == "table" and tonumber(needs[need]) or nil
        if x ~= nil and x < value then best, value = need, x end
    end
    return best
end

function Planner.critical(needs)
    for _, need in ipairs(Catalog.NEEDS) do
        local x = type(needs) == "table" and tonumber(needs[need]) or nil
        if x ~= nil and x < Planner.settings.criticalBelow then return need end
    end
    return nil
end

function Planner.serviceNeeds(q, members, elapsed)
    if type(q.needs) ~= "table" then
        Planner.writeSupplies(q)
        return true
    end
    q.needs = Planner.drain(q.needs, members, elapsed, Planner.drainPercent())
    Planner.writeSupplies(q)
    return true
end

function Planner.arrive(q, task, fraction, hour)
    if type(task) ~= "table" then return false end
    local needs = Planner.needsOf(q)
    if task.kind == "scavenge" then
        local amount = Planner.settings.scavengeCredit * (1 + math.max(0, math.min(1, tonumber(fraction) or 0)))
        local wanted = task.wanted
        if wanted == nil or needs[wanted] == nil then wanted = Planner.lowest(needs) end
        for _, need in ipairs(Catalog.NEEDS) do
            local share = Planner.settings.otherShare
            if need == wanted then share = 1 end
            needs[need] = needs[need] + amount * share
        end
    elseif task.kind == "hunt" then
        local food, ammo = Hunt.offline(q, task, hour)
        needs.food = needs.food + food
        needs.ammo = needs.ammo - ammo
        if type(q.activity) == "table" then
            q.activity.yields = q.activity.yields or {}
            q.activity.yields.food = (tonumber(q.activity.yields.food) or 0) + food
            q.activity.yields.ammo = (tonumber(q.activity.yields.ammo) or 0) - ammo
        end
    elseif task.kind == "fish" then
        local count = Fish.offline(q, task)
        needs.food = needs.food + count * 5
        if type(q.activity) == "table" then
            q.activity.yields = q.activity.yields or {}
            q.activity.yields.food = (tonumber(q.activity.yields.food) or 0) + count * 5
        end
    end
    q.needs = Planner.clampNeeds(needs)
    Planner.writeSupplies(q)
    if type(q.activity) == "table" then q.activity.progress = 1 end
    Planner.metrics.arrivals = Planner.metrics.arrivals + 1
    return true
end

function Planner.stampTask(q, task, hours)
    local previous = type(q.activity) == "table" and q.activity or {}
    local seq = (tonumber(previous.seq) or 0) + 1
    q.activity = {
        id = task.activityId, phase = "work", seq = seq,
        startedHours = hours, untilHours = task.untilHours,
        target = { nodeId = task.dest }, progress = 0,
        yields = { food = 0, water = 0, ammo = 0, meds = 0 },
        from = previous.id, reason = "planner", depot = previous.depot,
    }
    if type(q.needs) ~= "table" then Planner.writeSupplies(q) end
    return q.activity
end

function Planner.dayPart(hour)
    local h = tonumber(hour) or 12
    if h >= 5 and h < 8 then return "dawn" end
    if h >= 17 and h < 20 then return "dusk" end
    return "day"
end

function Planner.permitted(row, allowed)
    if type(row.requires) ~= "table" or type(allowed) ~= "table" then return true end
    for _, key in ipairs(row.requires) do
        if allowed[key] then return true end
    end
    return false
end

function Planner.eligible(id, ctx)
    local row = Catalog.activities[id]
    if type(row) ~= "table" or row.entry == true or row.built ~= true then return false end
    if id == "fish" and (not Fish.enabled() or not Fish.nearWater(ctx.habitat)) then return false end
    if id == "fish" and ctx.loaded == true and (type(ctx.shore) ~= "table" or #ctx.shore == 0) then return false end
    if (id == "return_base" or id == "haven_idle") and ctx.havenId == nil then return false end
    if id == "return_base" and ctx.atHome == true then return false end
    if id == "haven_idle" and ctx.atHome ~= true then return false end
    if id == "hunt" and ctx.loaded == true and not Hunt.liveEnabled() then return false end
    if id == "hunt" and (not Hunt.enabled() or Hunt.habitatScale(ctx.huntHabitat or ctx.habitat) == 0
            or (tonumber(ctx.hunters) or 0) < 1 or Hunt.hourScale(ctx.hour) == 0) then return false end
    if type(ctx.off) == "table" and ctx.off[id] == true then return false end
    if ctx.loaded == true then
        if row.loaded ~= true then return false end
        if row.night == true and ctx.night ~= true and row.always ~= true then return false end
    elseif row.offline ~= true then
        return false
    end
    if ctx.night == true and row.night ~= true and ctx.nightActive ~= true then return false end
    if not Planner.permitted(row, ctx.allowed) then return false end
    if row.minSupplies ~= nil and (tonumber(ctx.supplies) or 0) < row.minSupplies then return false end
    if row.noRepeat == true and ctx.event == "done" and ctx.current == id then return false end
    return true
end

function Planner.weatherTerm(row, weather)
    if type(weather) ~= "table" then return 0 end
    local s = Planner.settings
    local terms = type(row.weather) == "table" and row.weather or {}
    local value = 0
    if (tonumber(weather.rain) or 0) > s.rainAt then value = value + (tonumber(terms.rain) or 0) end
    if (tonumber(weather.fog) or 0) >= s.fogAt then value = value + (tonumber(terms.fog) or 0) end
    if (tonumber(weather.wind) or 0) >= s.windAt then value = value + (tonumber(terms.wind) or 0) end
    if (tonumber(weather.snow) or 0) > s.snowAt or weather.storm == true then
        if row.expedition == true then value = value + s.stormExpedition end
        if row.shelter == true then value = value + s.stormShelter end
    end
    return value
end

function Planner.homeTerm(id, ctx)
    if id ~= "return_base" then return 0 end
    local value = 0
    if (tonumber(ctx.away) or 0) >= (tonumber(ctx.returnHours) or math.huge) then value = value + 8 end
    if ctx.homeCovers == true then value = value + 10 end
    return value
end

function Planner.score(id, ctx)
    if not Planner.eligible(id, ctx) then return nil end
    local row, s = Catalog.activities[id], Planner.settings
    local needs = type(ctx.needs) == "table" and ctx.needs or {}
    local serves = type(row.serves) == "table" and row.serves or {}
    local value = 0
    for _, need in ipairs(Catalog.NEEDS) do
        local share = tonumber(serves[need])
        if share ~= nil then value = value + share * s.needScale * Planner.urgency(needs[need]) end
    end
    value = value + (tonumber(row.base) or 0)
    if row.dawnDusk ~= nil and Planner.dayPart(ctx.hour) ~= "day" then value = value + row.dawnDusk end
    value = value + Planner.weatherTerm(row, ctx.weather) + Planner.homeTerm(id, ctx)
    if type(ctx.bias) == "table" then value = value + (tonumber(ctx.bias[id]) or 0) end
    if ctx.night == true and row.night ~= true then value = value - s.nightActivePenalty end
    if row.expedition == true and ctx.crowded == true then value = value - s.crowdPenalty end
    if (tonumber(ctx.health) or 100) < s.lowHealth then
        if row.expedition == true then value = value - s.lowHealthExpedition end
        if row.rest == true then value = value + s.lowHealthRest end
    end
    local tiles = type(ctx.routeTiles) == "table" and tonumber(ctx.routeTiles[id]) or nil
    if tiles ~= nil then value = value - tiles / s.tilesPerHour end
    if ctx.event == "done" and ctx.current == id then value = value - s.repeatPenalty end
    return value + Planner.jitter(ctx, id) * s.jitter
end

function Planner.choose(ctx)
    local best, bestValue = nil, nil
    for _, id in ipairs(Catalog.order) do
        local value = Planner.score(id, ctx)
        if value ~= nil and (bestValue == nil or value > bestValue) then best, bestValue = id, value end
    end
    return best, bestValue
end

function Planner.decide(ctx)
    Planner.metrics.decisions = Planner.metrics.decisions + 1
    local best, bestValue = Planner.choose(ctx)
    if best == nil then return nil end
    local current = ctx.current
    if current == nil or ctx.event ~= nil then return best end
    if best == current then return nil end
    local currentValue = Planner.score(current, ctx)
    if currentValue == nil then return best end
    local since = tonumber(ctx.currentSince)
    local dwelt = since ~= nil and (tonumber(ctx.hours) or 0) - since >= Planner.settings.dwellHours
    if dwelt and bestValue >= currentValue + Planner.settings.switchMargin then return best end
    Planner.metrics.held = Planner.metrics.held + 1
    return nil
end

function Planner.averageHealth(members)
    local total, count = 0, 0
    for _, member in ipairs(type(members) == "table" and members or {}) do
        total, count = total + (tonumber(member.health) or 100), count + 1
    end
    if count == 0 then return 100 end
    return total / count
end

function Planner.offlineContext(squad, hours, hour, allowed, nightActive)
    local activity = type(squad.activity) == "table" and squad.activity or {}
    local permitted = allowed
    if squad.adoptedFrom ~= nil and type(allowed) == "table" then
        permitted = {}
        for key, value in pairs(allowed) do permitted[key] = value end
        permitted.scavenger_crew = true
    end
    local h = tonumber(hour) or 12
    return {
        needs = Planner.needsOf(squad), hour = h, night = h >= 22 or h < 6,
        nightActive = nightActive == true, weather = Planner.weather(),
        health = Planner.averageHealth(squad.members), allowed = permitted,
        hunters = Hunt.enabled() and Hunt.hunters(squad.members, squad.id) or 0,
        supplies = tonumber(squad.supplies) or 35, current = activity.id,
        currentSince = activity.startedHours, hours = hours, event = "done",
        day = math.floor((tonumber(hours) or 0) / 24), seed = squad.id, routeTiles = {},
    }
end

function Planner.weather()
    local weather = { rain = 0, snow = 0, fog = 0, wind = 0, storm = false }
    if type(Planner.adapterWeather) == "function" then return Planner.adapterWeather() or weather end
    if type(getClimateManager) ~= "function" then return weather end
    local climate = getClimateManager()
    if climate == nil then return weather end
    if type(climate.getPrecipitationIntensity) == "function" then
        weather.rain = tonumber(climate:getPrecipitationIntensity()) or 0
    end
    if type(climate.getSnowStrength) == "function" then weather.snow = tonumber(climate:getSnowStrength()) or 0 end
    if type(climate.getFogIntensity) == "function" then weather.fog = tonumber(climate:getFogIntensity()) or 0 end
    if type(climate.getWindPower) == "function" then weather.wind = tonumber(climate:getWindPower()) or 0 end
    if type(climate.getIsThunderStorming) == "function" then weather.storm = climate:getIsThunderStorming() == true end
    return weather
end

function Planner.hourOfDay()
    if type(Planner.adapterHour) == "function" then return Planner.adapterHour() end
    if type(getGameTime) ~= "function" then return 12 end
    local time = getGameTime()
    if time == nil or type(time.getHour) ~= "function" then return 12 end
    return tonumber(time:getHour()) or 12
end

function Planner.reset()
    Planner.metrics = { decisions = 0, held = 0, arrivals = 0 }
    return true
end

return Planner
