require "ProjectALife/Outposts/ALifeOutpostPresets"
require "ProjectALife/Outposts/ALifeOutpostRegistry"
require "ProjectALife/Core/ALifeTelemetry"
ProjectALife = ProjectALife or {}

local Registry = ProjectALife.OutpostRegistry
local Presets = ProjectALife.OutpostPresets

local Outbreak = {
    settings = {
        presetId = "bridge_checkpoint",

        lifetimeHours = 72,

        factionId = "alife_cordon",

        search = { x1 = 10600, y1 = 4900, x2 = 12900, y2 = 7100 },

        deckMinimum = 20,

        riverReach = 220,
        riverBand = 8,

        approach = -17,

        anchor = { x = 12316, y = 6712 },

        minHours = 2,

        retryHours = 1,
        retryMs = 60000,
    },

    siteId = nil,
    founded = false,

    postAt = nil,
    retryAtHours = nil,
    retryAtMs = nil,
    lastRefusal = nil,
    metrics = { searched = 0, found = 0, refused = 0, anchored = 0, retryWaits = 0 },
}
ProjectALife.RealisticOutbreak = Outbreak

Outbreak.adapters = {}

local function emit(category, fields)
    local telemetry = ProjectALife.Telemetry
    if telemetry ~= nil and type(telemetry.emit) == "function" then
        pcall(telemetry.emit, category, fields)
    end
end

function Outbreak.enabled()
    if type(Outbreak.adapters.enabled) == "function" then
        return Outbreak.adapters.enabled() == true
    end

    local settings = ProjectALife.Settings
    return settings ~= nil and settings.current ~= nil
        and settings.current.realisticOutbreak == true
end

function Outbreak.zonesIn(x, y, w, h)
    if type(Outbreak.adapters.zones) == "function" then
        return Outbreak.adapters.zones(x, y, w, h) or {}
    end
    local result = {}
    pcall(function()
        local zones = getWorld():getMetaGrid():getZonesIntersecting(x, y, 0, w, h)
        if zones == nil then return end
        for index = 0, zones:size() - 1 do
            local zone = zones:get(index)
            result[#result + 1] = { type = tostring(zone:getType() or ""),
                x = zone:getX(), y = zone:getY(), w = zone:getWidth(), h = zone:getHeight() }
        end
    end)
    return result
end

local function overlap(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w
        and a.y < b.y + b.h and b.y < a.y + a.h
end

function Outbreak.crossing(zones)
    local roads, water = {}, {}
    for _, zone in ipairs(zones or {}) do
        local kind = tostring(zone.type or "")
        if kind == "Nav" or kind == "Road" then roads[#roads + 1] = zone
        elseif kind == "WaterFlow" or kind == "WaterZone" then water[#water + 1] = zone end
    end
    local s = Outbreak.settings
    local best
    for _, road in ipairs(roads) do

        if (tonumber(road.h) or 0) >= s.deckMinimum then
            local cx = road.x + road.w / 2
            for _, wet in ipairs(water) do
                local wy = wet.y + (wet.h or 1) / 2
                if wy >= road.y and wy <= road.y + road.h
                        and math.abs(wet.x - cx) <= s.riverReach then

                    local opposite = false
                    for _, other in ipairs(water) do
                        local oy = other.y + (other.h or 1) / 2
                        if math.abs(oy - wy) <= s.riverBand
                                and (other.x - cx) * (wet.x - cx) < 0
                                and math.abs(other.x - cx) <= s.riverReach then
                            opposite = true
                            break
                        end
                    end
                    if opposite then
                        local point = { x = math.floor(cx), y = math.floor(wy),
                            width = road.w }

                        if best == nil or point.y > best.y then best = point end
                    end
                end
            end
        end
    end
    return best
end

function Outbreak.post()
    local s = Outbreak.settings
    Outbreak.metrics.searched = Outbreak.metrics.searched + 1
    local preset = Presets.get(s.presetId)
    local blueprints = ProjectALife.Blueprints
    local home = preset ~= nil and type(preset.blueprint) == "table" and blueprints ~= nil
        and blueprints.anchorOf(preset.blueprint.id) or nil
    if home ~= nil then
        Outbreak.metrics.anchored = (Outbreak.metrics.anchored or 0) + 1
        return { x = home.x, y = home.y, z = 0 }
    end
    local zones = Outbreak.zonesIn(s.search.x1, s.search.y1,
        s.search.x2 - s.search.x1, s.search.y2 - s.search.y1)
    local point = Outbreak.crossing(zones)
    if point ~= nil then
        Outbreak.metrics.found = Outbreak.metrics.found + 1
        return { x = point.x, y = point.y + s.approach, z = 0 }
    end

    local anchor = s.anchor
    if type(anchor) ~= "table" or tonumber(anchor.x) == nil or tonumber(anchor.y) == nil then
        Outbreak.metrics.refused = Outbreak.metrics.refused + 1
        return nil, "no_crossing"
    end
    Outbreak.metrics.anchored = (Outbreak.metrics.anchored or 0) + 1
    return { x = math.floor(anchor.x), y = math.floor(anchor.y), z = 0 }
end

function Outbreak.nowMs()
    if type(Outbreak.adapters.nowMs) == "function" then return Outbreak.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Outbreak.backoff(hours, why)
    Outbreak.retryAtHours = hours + Outbreak.settings.retryHours
    Outbreak.retryAtMs = Outbreak.nowMs() + Outbreak.settings.retryMs
    why = tostring(why or "refused")
    if Outbreak.lastRefusal ~= why then
        Outbreak.lastRefusal = why
        emit("outpost_outbreak_refused", { site = "checkpoint", reason = why })
    end
end

function Outbreak.tick(hours)
    if Outbreak.founded then return false, "already_founded" end
    if not Outbreak.enabled() then return false, "disabled" end
    hours = tonumber(hours) or 0
    if hours < Outbreak.settings.minHours then return false, "too_early" end
    if Outbreak.retryAtHours ~= nil and hours < Outbreak.retryAtHours
            and Outbreak.nowMs() < (tonumber(Outbreak.retryAtMs) or 0) then
        Outbreak.metrics.retryWaits = (Outbreak.metrics.retryWaits or 0) + 1
        return false, "retry_later"
    end
    local preset = Presets.get(Outbreak.settings.presetId)
    if preset == nil then return false, "no_preset" end
    local at, why = Outbreak.postAt, nil
    if at == nil then
        local found = Outbreak.metrics.found
        at, why = Outbreak.post()
        if at ~= nil and Outbreak.metrics.found > found then Outbreak.postAt = at end
    end
    if at == nil then
        Outbreak.backoff(hours, why)
        return false, why
    end
    local director = ProjectALife.OutpostDirector
    if director == nil or type(director.foundFixed) ~= "function" then return false, "no_director" end
    local site, refusal = director.foundFixed(Outbreak.settings.presetId, at.x, at.y, hours,
        Outbreak.settings.factionId, Outbreak.settings.lifetimeHours)
    if site == nil then
        Outbreak.backoff(hours, refusal)
        return false, "refused"
    end
    Outbreak.retryAtHours, Outbreak.retryAtMs, Outbreak.lastRefusal = nil, nil, nil
    Outbreak.founded = true
    Outbreak.siteId = site.id
    emit("outbreak_checkpoint", { site = site.id, x = at.x, y = at.y,
        hours = Outbreak.settings.lifetimeHours })
    return true, site
end

function Outbreak.resume()
    Outbreak.siteId = Registry.fixedSiteId(Outbreak.settings.presetId)
    Outbreak.founded = Outbreak.siteId ~= nil
    return Outbreak.founded
end

function Outbreak.reset()
    Outbreak.founded = false
    Outbreak.siteId = nil
    Outbreak.postAt, Outbreak.retryAtHours, Outbreak.retryAtMs, Outbreak.lastRefusal = nil, nil, nil, nil
    Outbreak.metrics = { searched = 0, found = 0, refused = 0, anchored = 0, retryWaits = 0 }
end
