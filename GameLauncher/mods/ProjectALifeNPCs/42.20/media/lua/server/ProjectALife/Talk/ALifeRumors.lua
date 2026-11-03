require "ProjectALife/Talk/ALifeDialogueRoles"

ProjectALife = ProjectALife or {}

local Rumors = {
    TAG = "ProjectALife.Rumors.v1",
    settings = {
        maximum = 8,
        reuseRadius = 1500,
        box = 200,
        tries = 6,
        mannedDistance = 90,
        tickMs = 3000,
    },
    robberRegisters = { raider = true, gang = true, club = true, prison = true, crime = true, outlaw = true },
    denRooms = { house = "a house", motel = "the motel", warehouse = "a warehouse", gas = "the gas station",
        food = "a diner", store = "a store", church = "the church", school = "the school" },
    adapters = {},
    state = nil,
    lastTickAtMs = 0,
    metrics = { named = 0, known = 0, generated = 0, manned = 0, refused = 0, none = 0 },
}
ProjectALife.Rumors = Rumors

local function nowMs()
    if type(Rumors.adapters.nowMs) == "function" then return Rumors.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function stable(value)
    local result = 0
    value = tostring(value or "")
    for index = 1, #value do result = (result * 31 + string.byte(value, index)) % 2147483647 end
    return result
end

function Rumors.store()
    if Rumors.state ~= nil then return Rumors.state end
    local value
    if type(Rumors.adapters.getOrCreate) == "function" then
        value = Rumors.adapters.getOrCreate(Rumors.TAG)
    elseif ModData ~= nil and type(ModData.getOrCreate) == "function" then
        local ok, result = pcall(ModData.getOrCreate, Rumors.TAG)
        if ok then value = result end
    end
    if type(value) ~= "table" then return nil end
    if type(value.dens) ~= "table" then value.dens = {} end
    Rumors.state = value
    return value
end

function Rumors.reset()
    Rumors.state = nil
    Rumors.lastTickAtMs = 0
    Rumors.metrics = { named = 0, known = 0, generated = 0, manned = 0, refused = 0, none = 0 }
end

function Rumors.robberFaction(factionId)
    local catalog = ProjectALife.Catalog
    local faction = catalog ~= nil and type(catalog.faction) == "function" and catalog.faction(factionId) or nil
    local bloc = faction and faction.relations and faction.relations.bloc or nil
    if bloc ~= nil then return Rumors.robberRegisters[string.lower(tostring(bloc))] == true end
    local roles = ProjectALife.DialogueRoles
    local role = roles ~= nil and roles.stockFactions[tostring(factionId or "")] or nil
    local definition = role ~= nil and roles.definitions[role] or nil
    return definition ~= nil and Rumors.robberRegisters[definition.register] == true
end

function Rumors.describe(x, y, category, town)
    local noun = Rumors.denRooms[tostring(category or "")] or "a house"
    if town == nil then return noun .. " out past the county road" end
    local cx, cy = (town.minX + town.maxX) / 2, (town.minY + town.maxY) / 2
    local dx, dy = x - cx, y - cy
    local side
    if math.abs(dx) > math.abs(dy) * 1.5 then side = dx > 0 and "east" or "west"
    elseif math.abs(dy) > math.abs(dx) * 1.5 then side = dy > 0 and "south" or "north"
    else side = (dy > 0 and "south" or "north") .. (dx > 0 and "east" or "west") end
    if math.sqrt(dx * dx + dy * dy) < 250 then return noun .. " in the middle of " .. town.label end
    return noun .. " on the " .. side .. " side of " .. town.label
end

local function townAt(x, y)
    local regions = ProjectALife.TownRegions
    if regions == nil or type(regions.distanceToTown) ~= "function" then return nil end
    local _, town = regions.distanceToTown({ x = x, y = y })
    return town
end

function Rumors.discover(state)
    local byId = {}
    for _, den in ipairs(state.dens) do byId[den.id] = den end
    local sites = ProjectALife.OutpostRegistry
    if sites ~= nil and type(sites.list) == "function" then
        for _, site in ipairs(sites.list()) do
            local id = "site:" .. tostring(site.id)
            if byId[id] == nil and #state.dens < Rumors.settings.maximum and site.factionId ~= nil
                    and Rumors.robberFaction(site.factionId) and tostring(site.state) ~= "abandoned" then
                local town = townAt(site.x, site.y)
                local den = { id = id, x = site.x, y = site.y, z = 0, factionId = site.factionId, source = "outpost",
                    where = Rumors.describe(site.x, site.y, "house", town), town = town and town.label or nil, uses = 0, manned = true }
                state.dens[#state.dens + 1] = den
                byId[id] = den
                Rumors.metrics.known = Rumors.metrics.known + 1
            end
        end
    end
    local populate = ProjectALife.PopulateDirector
    local places = populate ~= nil and populate.state ~= nil and populate.state.places or nil
    for _, place in ipairs(type(places) == "table" and places or {}) do
        local id = "place:" .. tostring(place.key)
        if byId[id] == nil and #state.dens < Rumors.settings.maximum and place.manned == true
                and place.factionId ~= nil and Rumors.robberFaction(place.factionId) then
            local town = townAt(place.x, place.y)
            local den = { id = id, x = place.x, y = place.y, z = place.z or 0, factionId = place.factionId, source = "populate",
                where = Rumors.describe(place.x, place.y, place.category, town), town = town and town.label or nil, uses = 0, manned = true }
            state.dens[#state.dens + 1] = den
            byId[id] = den
            Rumors.metrics.known = Rumors.metrics.known + 1
        end
    end
end

function Rumors.pickFaction(seed)
    local catalog = ProjectALife.Catalog and ProjectALife.Catalog.current or nil
    if type(catalog) ~= "table" or type(catalog.factions) ~= "table" then return nil end
    local list = {}
    for id in pairs(catalog.factions) do
        if Rumors.robberFaction(id) then list[#list + 1] = id end
    end
    table.sort(list)
    if #list == 0 then return nil end
    return list[stable(seed) % #list + 1]
end

function Rumors.generate(state, x, y)
    local town = townAt(x, y)
    if town == nil then return nil end
    local populate = ProjectALife.PopulateDirector
    for try = 1, Rumors.settings.tries do
        local seed = town.id .. ":" .. tostring(#state.dens) .. ":" .. tostring(try)
        local spanX = math.max(1, town.maxX - town.minX - Rumors.settings.box)
        local spanY = math.max(1, town.maxY - town.minY - Rumors.settings.box)
        local bx = town.minX + stable(seed .. "x") % spanX
        local by = town.minY + stable(seed .. "y") % spanY
        local found = nil
        pcall(function()
            local rooms = ArrayList.new()
            getWorld():getMetaGrid():getRoomsIntersecting(bx, by, Rumors.settings.box, Rumors.settings.box, rooms)
            for index = 0, math.min(rooms:size(), 400) - 1 do
                local definition = rooms:get(index)
                local name = definition:getName()
                local category = populate ~= nil and type(populate.categoryOf) == "function" and populate.categoryOf(name) or nil
                if definition:getZ() == 0 and Rumors.denRooms[tostring(category)] ~= nil then
                    found = { x = definition:getX() + math.floor(definition:getW() / 2),
                        y = definition:getY() + math.floor(definition:getH() / 2), z = 0, category = category, name = name }
                    return
                end
            end
        end)
        if found ~= nil then
            local factionId = Rumors.pickFaction(seed)
            if factionId == nil then return nil end
            local den = { id = "generated:" .. town.id .. ":" .. tostring(found.x) .. ":" .. tostring(found.y),
                x = found.x, y = found.y, z = 0, category = found.category, factionId = factionId, source = "generated",
                where = Rumors.describe(found.x, found.y, found.category, town), town = town.label, uses = 0, manned = false, refusals = 0 }
            state.dens[#state.dens + 1] = den
            Rumors.metrics.generated = Rumors.metrics.generated + 1
            return den
        end
    end
    return nil
end

function Rumors.den(x, y)
    local state = Rumors.store()
    if state == nil or x == nil or y == nil then return nil end
    Rumors.discover(state)
    local best, bestScore = nil, math.huge
    for _, den in ipairs(state.dens) do
        local distance = math.sqrt((den.x - x) ^ 2 + (den.y - y) ^ 2)
        if distance <= Rumors.settings.reuseRadius then
            local score = (tonumber(den.uses) or 0) * 500 + distance
            if score < bestScore then best, bestScore = den, score end
        end
    end
    if best == nil and #state.dens < Rumors.settings.maximum then best = Rumors.generate(state, x, y) end
    if best == nil then
        for _, den in ipairs(state.dens) do
            if best == nil or (tonumber(den.uses) or 0) < (tonumber(best.uses) or 0) then best = den end
        end
    end
    if best == nil then
        Rumors.metrics.none = Rumors.metrics.none + 1
        return nil
    end
    best.uses = (tonumber(best.uses) or 0) + 1
    Rumors.metrics.named = Rumors.metrics.named + 1
    return best
end

function Rumors.deferred(populate, reason)
    local set = type(populate) == "table" and populate.deferrals or nil
    if type(set) ~= "table" then return reason == "building_unloaded" end
    return set[tostring(reason)] == true
end

function Rumors.tick(now)
    now = now or nowMs()
    if now - Rumors.lastTickAtMs < Rumors.settings.tickMs then return 0 end
    Rumors.lastTickAtMs = now
    local speech = ProjectALife.Speech
    if speech ~= nil and not speech.authoritative() then return 0 end
    local state = Rumors.store()
    if state == nil then return 0 end
    local populate = ProjectALife.PopulateDirector
    local presence = ProjectALife.ModuleTalkPresence
    if populate == nil or type(populate.man) ~= "function" or presence == nil then return 0 end
    local players = presence.players()
    local reach = Rumors.settings.mannedDistance
    for _, den in ipairs(state.dens) do
        if type(den.pendingPlace) == "table" then
            local place = den.pendingPlace
            local pending = populate.pending(place)
            Rumors.metrics.refused = Rumors.metrics.refused
                + math.max(0, (tonumber(place.refusals) or 0) - (tonumber(den.refusals) or 0))
            den.refusals = place.refusals
            if place.manned == true and den.manned ~= true then
                den.manned = true
                Rumors.metrics.manned = Rumors.metrics.manned + 1
            end
            if not pending then den.pendingPlace = nil end
        end
        if den.pendingPlace == nil and den.source == "generated" and den.manned ~= true and (tonumber(den.refusals) or 0) < 5 then
            for _, player in ipairs(players) do
                local ok, px, py = pcall(function() return player:getX(), player:getY() end)
                if ok and px ~= nil and math.sqrt((px - den.x) ^ 2 + (py - den.y) ^ 2) <= reach then
                    local place = { key = den.id, x = den.x, y = den.y, z = den.z or 0, category = den.category,
                        refusals = den.refusals or 0, forceFactionId = den.factionId }
                    local hours = 0
                    pcall(function() hours = getGameTime():getWorldAgeHours() end)
                    local manned, reason, queued = populate.man(place, { player = player, x = px, y = py }, now, hours)
                    if manned and queued == true then
                        den.pendingPlace = place
                    elseif manned then
                        den.manned = true
                        Rumors.metrics.manned = Rumors.metrics.manned + 1
                    elseif not Rumors.deferred(populate, reason) then
                        den.refusals = (tonumber(den.refusals) or 0) + 1
                        Rumors.metrics.refused = Rumors.metrics.refused + 1
                    end
                    if not Rumors.deferred(populate, reason) then return 1 end
                    break
                end
            end
        end
    end
    return 0
end

return Rumors
