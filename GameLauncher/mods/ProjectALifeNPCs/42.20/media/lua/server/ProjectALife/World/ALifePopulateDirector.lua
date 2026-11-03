require "ProjectALife/World/ALifePOI"
require "ProjectALife/World/ALifeTownRegions"
require "ProjectALife/Records/ALifeFactionSpawnRules"
require "ProjectALife/World/ALifeEncounters"
require "ProjectALife/Records/ALifeCatalog"
require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/World/ALifeSpawnPolicy"
require "ProjectALife/World/ALifeWorldPressure"
require "ProjectALife/Offline/ALifeSquadLedger"

ProjectALife = ProjectALife or {}

local Populate = {
    TAG = "ProjectALife.Populate.v1",
    settings = {
        endHours = 96,
        mode = "off",            
        maximum = 30,
        minimumPerTown = 2,
        percent = { rare = 10, uncommon = 20, common = 35 },

        box = 200,
        roomsPerBox = 400,

        cell = 24,

        spacing = 60,
        spacingSteps = { 1, 0.5, 0.25, 0 },

        spawnDistance = 90,

        minimumDistance = 40,

        closeKeepOut = 9,

        maximumRefusals = 5,

        slowRetryMs = 5000,

        scanBudgetMs = 4,
        scanBoxCap = 40,

        auditMs = 30000,

        whyEveryMs = 60000,
        whyMinMs = 10000,
    },
    adapters = {},
    metrics = { boxes = 0, rooms = 0, places = 0, chosen = 0, manned = 0, refused = 0, given_up = 0,
        reopened = 0, cleared = 0 },
    state = nil,
    auditedAtMs = nil,
    hoursSeen = nil,

    why = {},
    waits = {},
    nearest = nil,
    nearestDistance = nil,

    categoryMemo = {},
    categoryMemoSize = 0,
    categoryRooms = nil,
    scoreRolls = {},
    pickRolls = {},
    rollMemoSize = 0,
}
ProjectALife.PopulateDirector = Populate

Populate.rooms = {
    { "police", "police" }, { "prison", "police" }, { "detective", "police" },
    { "fire", "fire" },
    { "hospital", "medical" }, { "medical", "medical" }, { "pharmac", "medical" },
    { "dentist", "medical" }, { "morgue", "medical" }, { "laborator", "medical" },
    { "gunstore", "guns" }, { "armysurplus", "guns" }, { "hunting", "guns" }, { "armystorage", "guns" },
    { "warehouse", "warehouse" }, { "factory", "warehouse" }, { "storageunit", "warehouse" },
    { "gasstation", "gas" }, { "gasstore", "gas" }, { "mechanic", "gas" }, { "carrepair", "gas" },
    { "motel", "motel" }, { "hotel", "motel" },
    { "restaurant", "food" }, { "diner", "food" }, { "cafe", "food" }, { "pizza", "food" },
    { "burger", "food" }, { "fastfood", "food" }, { "grocery", "food" }, { "bar", "food" },
    { "church", "church" },
    { "classroom", "school" }, { "school", "school" }, { "library", "school" },
    { "hardware", "store" }, { "clothesstore", "store" }, { "generalstore", "store" },
    { "gigamart", "store" }, { "liquor", "store" }, { "electronics", "store" }, { "bookstore", "store" },
    { "livingroom", "house" }, { "bedroom", "house" },
}

Populate.notRooms = { "barn" }

Populate.weights = { police = 1.0, fire = 1.0, medical = 1.0, guns = 0.8, warehouse = 0.5,
    gas = 0.7, motel = 0.6, food = 0.5, church = 0.7, school = 0.7, store = 0.4, house = 0.12 }

Populate.factionsFor = {
    police = { "_pd", "sheriff", "ksp_post", "county_jail", "corrections", "louisville_police", "jefferson_police", "trooper", "county_law", "alife_police" },
    fire = { "vfd", "slaughter", "alife_fire" },
    medical = { "hospital", "county_ems", "pharmacy", "paramedics", "ward_survivors", "dabney", "prison_infirmary", "lone_nurse" },
    guns = { "gunclub", "preppers" },
    warehouse = { "warehouse_nightshift", "rail_workers", "distillery", "utility_survivors", "whitaker", "crume", "kettle", "lineworkers" },
    gas = { "mercer", "lone_mechanic", "truckstop", "chopshop", "highway_maintenance", "lineworkers" },
    motel = { "price_family", "traveller_pair", "married_pair" },
    food = { "diner_survivors", "ortiz", "coworker_pair", "bell_family" },
    church = { "prather", "church_volunteers" },
    school = { "schoolhouse" },
    store = { "sutter", "nguyen", "coyle", "postal", "coworker_pair", "riverside", "renfro" },
    house = { "_family", "apartment_watch", "trailer_neighbors", "lone_retiree", "married_pair", "sibling_pair", "napier", "kessinger", "bauer", "turner", "vittitoe" },
}
Populate.fallbackBlocs = { family = true, civilian = true, worker = true, rescue = true, law = true }

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function emit(category, fields)
    local telemetry = ProjectALife.Telemetry
    if telemetry ~= nil and type(telemetry.emit) == "function" then
        pcall(telemetry.emit, category, fields)
    end
end

function Populate.configure(adapters)
    Populate.adapters = adapters or {}
    local mode = tostring(Populate.adapters.mode or Populate.settings.mode)
    if mode ~= "rare" and mode ~= "uncommon" and mode ~= "common" then mode = "off" end
    Populate.settings.mode = mode
    Populate.settings.maximum = math.max(1, math.min(200, math.floor(tonumber(Populate.adapters.maximum) or Populate.settings.maximum)))
    if tonumber(Populate.adapters.spawnDistance) ~= nil then
        Populate.settings.spawnDistance = math.max(30, math.min(200, tonumber(Populate.adapters.spawnDistance)))
    end
end

function Populate.reset()
    Populate.state = nil
    Populate.auditedAtMs = nil
    Populate.hoursSeen = nil
    Populate.metrics = { boxes = 0, rooms = 0, places = 0, chosen = 0, manned = 0, refused = 0, given_up = 0,
        reopened = 0, cleared = 0 }
    Populate.categoryMemo, Populate.categoryMemoSize, Populate.categoryRooms = {}, 0, nil
    Populate.clearRolls()
    Populate.why, Populate.waits, Populate.nearest, Populate.nearestDistance = {}, {}, nil, nil
end

function Populate.clearRolls()
    Populate.scoreRolls, Populate.pickRolls, Populate.rollMemoSize = {}, {}, 0
end

local function store()
    if Populate.state ~= nil then return Populate.state end
    local value
    if type(Populate.adapters.getOrCreate) == "function" then
        value = Populate.adapters.getOrCreate(Populate.TAG)
    elseif ModData ~= nil and type(ModData.getOrCreate) == "function" then
        local ok, result = pcall(ModData.getOrCreate, Populate.TAG)
        if ok then value = result end
    end
    if type(value) ~= "table" then return nil end
    if value.version == nil then
        value.version = 1
        value.scanned = false
        value.places = {}
        value.seen = {}
        value.cursor = { town = 1, bx = nil, by = nil }
        value.candidates = {}
    end
    Populate.state = value
    return value
end

function Populate.categoryOf(name)
    if type(name) ~= "string" then return Populate.categoryFor(name) end
    if Populate.categoryRooms ~= Populate.rooms or Populate.categoryMemoSize >= 4096 then
        Populate.categoryMemo, Populate.categoryMemoSize, Populate.categoryRooms = {}, 0, Populate.rooms
    end
    local known = Populate.categoryMemo[name]
    if known == nil then
        known = Populate.categoryFor(name) or false
        Populate.categoryMemo[name] = known
        Populate.categoryMemoSize = Populate.categoryMemoSize + 1
    end
    return known or nil
end

function Populate.categoryFor(name)
    name = string.lower(tostring(name or ""))
    if name == "" then return nil end
    for _, needle in ipairs(Populate.notRooms) do
        if string.find(name, needle, 1, true) then return nil end
    end
    for _, pair in ipairs(Populate.rooms) do
        if string.find(name, pair[1], 1, true) then return pair[2] end
    end
    return nil
end

function Populate.roll(key)
    local value = 7
    key = tostring(key or "")
    for index = 1, #key do value = (value * 131 + string.byte(key, index)) % 2147483647 end
    return (value % 10000) / 10000
end

function Populate.noteRolls(key)
    if Populate.scoreRolls[key] ~= nil then return end
    if Populate.rollMemoSize >= 16384 then Populate.clearRolls() end
    Populate.scoreRolls[key] = Populate.roll(key .. "|score")
    Populate.pickRolls[key] = Populate.roll(key)
    Populate.rollMemoSize = Populate.rollMemoSize + 1
end

function Populate.fits(factionId, category)
    local wanted = Populate.factionsFor[category]
    if type(wanted) ~= "table" then return false end
    factionId = tostring(factionId or "")
    for _, needle in ipairs(wanted) do
        if string.find(factionId, needle, 1, true) then return true end
    end
    return false
end

function Populate.higherScore(a, b) return a.score > b.score end

function Populate.placeBefore(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.key < b.key
end

function Populate.firstPlaces(chosen, count)
    local n = #chosen
    local k = math.floor(tonumber(count) or 0)
    if not (k >= 1) or k >= n or k > 64 then
        table.sort(chosen, Populate.placeBefore)
        return chosen
    end
    local seen = {}
    for index = 1, n do
        local place = chosen[index]
        local score, key = place.score, place.key
        if type(key) ~= "string" or type(score) ~= "number" or score ~= score or seen[key] then
            table.sort(chosen, Populate.placeBefore)
            return chosen
        end
        seen[key] = true
    end
    local top, size = {}, 0
    for index = 1, n do
        local place = chosen[index]
        if size < k or Populate.placeBefore(place, top[size]) then
            local at = size < k and size + 1 or size
            while at > 1 and Populate.placeBefore(place, top[at - 1]) do
                top[at] = top[at - 1]
                at = at - 1
            end
            top[at] = place
            if size < k then size = size + 1 end
        end
    end
    return top
end

function Populate.spacingDepth(count)
    local k = math.max(0, math.floor(tonumber(count) or 0))
    return math.max(k, math.min(64, k * 4)), math.min(64, math.max(16, k * 4))
end

function Populate.spaced(place, accepted, reach)
    if not (reach > 0) then return true end
    local x, y, limit = tonumber(place.x) or 0, tonumber(place.y) or 0, reach * reach
    for index = 1, #accepted do
        local other = accepted[index]
        local dx, dy = (tonumber(other.x) or 0) - x, (tonumber(other.y) or 0) - y
        if dx * dx + dy * dy < limit then return false end
    end
    return true
end

function Populate.spread(candidates, chosen, picked, count)
    local k = math.floor(tonumber(count) or 0)
    local spacing = tonumber(Populate.settings.spacing) or 0
    if not (spacing > 0) or k < 1 then return Populate.firstPlaces(chosen, count) end
    local deepChosen, deepOthers = Populate.spacingDepth(k)
    local others = {}
    for _, place in ipairs(candidates) do
        if not picked[place.key] then others[#others + 1] = place end
    end
    local lists = { Populate.firstPlaces(chosen, deepChosen), Populate.firstPlaces(others, deepOthers) }
    local depths = { deepChosen, deepOthers }
    local accepted, taken = {}, {}
    local steps = type(Populate.settings.spacingSteps) == "table" and Populate.settings.spacingSteps or {}
    for step = 1, #steps + 1 do
        local reach = step <= #steps and spacing * (tonumber(steps[step]) or 0) or 0
        for tier = 1, reach > 0 and 2 or 1 do
            local list = lists[tier]
            for index = 1, math.min(#list, depths[tier]) do
                if #accepted >= k then break end
                local place = list[index]
                if not taken[place] and Populate.spaced(place, accepted, reach) then
                    taken[place] = true
                    accepted[#accepted + 1] = place
                end
            end
        end
        if #accepted >= k then break end
    end
    return accepted
end

function Populate.choose(candidates, mode, maximum, minimumPerTown)
    local percent = Populate.settings.percent[mode] or 0
    if percent <= 0 or type(candidates) ~= "table" then return {} end
    local chosen, byTown = {}, {}
    local scoreRolls, pickRolls = Populate.scoreRolls or {}, Populate.pickRolls or {}
    for _, place in ipairs(candidates) do
        local weight = Populate.weights[place.category] or 0.3
        local scoreRoll = scoreRolls[place.key]
        if scoreRoll == nil then scoreRoll = Populate.roll(place.key .. "|score") end
        place.score = weight * (1 - scoreRoll)
        byTown[place.town] = byTown[place.town] or {}
        table.insert(byTown[place.town], place)
        local pickRoll = pickRolls[place.key]
        if pickRoll == nil then pickRoll = Populate.roll(place.key) end
        if pickRoll < weight * percent / 100 then chosen[#chosen + 1] = place end
    end

    local picked = {}
    for _, place in ipairs(chosen) do picked[place.key] = true end
    for _, list in pairs(byTown) do
        local have = 0
        for _, place in ipairs(list) do if picked[place.key] then have = have + 1 end end
        if have < (minimumPerTown or 0) then
            table.sort(list, Populate.higherScore)
            for _, place in ipairs(list) do
                if have >= (minimumPerTown or 0) then break end
                if not picked[place.key] then picked[place.key] = true; chosen[#chosen + 1] = place; have = have + 1 end
            end
        end
    end
    local result = {}
    local count = math.min(#chosen, maximum or #chosen)
    chosen = Populate.spread(candidates, chosen, picked, count)
    for index = 1, count do
        local place = chosen[index]
        result[#result + 1] = { key = place.key, x = place.x, y = place.y, z = place.z or 0,
            category = place.category, town = place.town, manned = false, refusals = 0 }
    end
    return result
end

function Populate.queryRooms(bx, by, box)
    local rooms = ArrayList.new()
    getWorld():getMetaGrid():getRoomsIntersecting(bx, by, box, box, rooms)
    return rooms
end

function Populate.roomOf(definition)
    if definition.getName == nil or definition.getX == nil or definition.getY == nil
            or definition.getZ == nil or definition.getW == nil or definition.getH == nil then
        return nil
    end
    return definition:getName(), definition:getX(), definition:getY(), definition:getZ(),
        definition:getW(), definition:getH()
end

function Populate.insidePoint(definition, rx, ry, w, h)
    local cx, cy = rx + math.floor((tonumber(w) or 2) / 2), ry + math.floor((tonumber(h) or 2) / 2)
    if definition.getRects == nil then return cx, cy end
    local rects = definition:getRects()
    if rects == nil or rects.size == nil or rects.get == nil or rects:size() <= 1 then return cx, cy end
    local area, bx, by = -1, cx, cy
    for index = 0, rects:size() - 1 do
        local rect = rects:get(index)
        if rect ~= nil and rect.getX ~= nil and rect.getY ~= nil and rect.getW ~= nil and rect.getH ~= nil then
            local x, y, rw, rh = rect:getX(), rect:getY(), rect:getW(), rect:getH()
            if cx >= x and cx < x + rw and cy >= y and cy < y + rh then return cx, cy end
            if rw * rh > area then area, bx, by = rw * rh, x + math.floor(rw / 2), y + math.floor(rh / 2) end
        end
    end
    return bx, by
end

local function scanBox(state, town, bx, by)
    local box = Populate.settings.box
    local ok, rooms = pcall(Populate.queryRooms, bx, by, box)
    Populate.metrics.boxes = Populate.metrics.boxes + 1
    if not ok or rooms == nil then return end
    local count = math.min(rooms:size(), Populate.settings.roomsPerBox)
    for index = 0, count - 1 do
        local definition = rooms:get(index)
        if definition ~= nil then
            Populate.metrics.rooms = Populate.metrics.rooms + 1
            local name, rx, ry, rz, w, h = Populate.roomOf(definition)
            local category = Populate.categoryOf(name)
            if category ~= nil and rx ~= nil and (tonumber(rz) or 0) == 0 then
                local cell = Populate.settings.cell
                local key = category .. ":" .. math.floor(rx / cell) .. ":" .. math.floor(ry / cell)
                if state.seen[key] == nil then
                    state.seen[key] = true
                    local px, py = Populate.insidePoint(definition, rx, ry, w, h)
                    state.candidates[#state.candidates + 1] = {
                        key = key, category = category, town = town.id, x = px, y = py, z = 0,
                    }
                    Populate.noteRolls(key)
                    Populate.metrics.places = Populate.metrics.places + 1
                end
            end
        end
    end
end

function Populate.townOrder(towns, points)
    local order = {}
    for index = 1, #towns do order[#order + 1] = index end
    if type(points) ~= "table" or #points == 0 then return order end
    local function distance(town)
        local cx, cy = (town.minX + town.maxX) / 2, (town.minY + town.maxY) / 2
        local best = math.huge
        for _, p in ipairs(points) do
            local dx, dy = (tonumber(p.x) or 0) - cx, (tonumber(p.y) or 0) - cy
            best = math.min(best, dx * dx + dy * dy)
        end
        return best
    end
    table.sort(order, function(a, b) return distance(towns[a]) < distance(towns[b]) end)
    return order
end

local function scan(state)
    local towns = ProjectALife.TownRegions.definitions
    local cursor = state.cursor
    if type(state.order) ~= "table" or #state.order ~= #towns then
        state.order = Populate.townOrder(towns, Populate.playerPoints())
    end
    local started, boxes = nowMs(), 0
    local settings = Populate.settings
    while true do
        local town = towns[state.order[cursor.town] or 0]
        if town == nil then
            state.candidates, state.seen = {}, {}
            state.scanned = true
            state.mode = settings.mode
            Populate.metrics.chosen = #state.places
            emit("populate_scanned", { count = #state.places, mode = settings.mode })
            return true
        end
        if cursor.bx == nil then cursor.bx, cursor.by = town.minX, town.minY end
        scanBox(state, town, cursor.bx, cursor.by)
        boxes = boxes + 1
        cursor.bx = cursor.bx + settings.box
        if cursor.bx > town.maxX then
            cursor.bx = town.minX
            cursor.by = cursor.by + settings.box
            if cursor.by > town.maxY then
                local share = math.max(settings.minimumPerTown, math.ceil(settings.maximum / math.max(1, #towns)))
                for _, place in ipairs(Populate.choose(state.candidates, settings.mode, share, settings.minimumPerTown)) do
                    state.places[#state.places + 1] = place
                end
                state.candidates = {}
                Populate.clearRolls()
                emit("populate_town_scanned", { town = town.id, places = #state.places })
                cursor.town = cursor.town + 1
                cursor.bx, cursor.by = nil, nil
            end
        end

        if boxes >= settings.scanBoxCap or nowMs() - started >= settings.scanBudgetMs then
            return true
        end
    end
end

function Populate.scanTick()
    if Populate.settings.mode == "off" then return 0 end
    local state = store()
    if state == nil or state.scanned == true then return 0 end
    scan(state)
    return 1
end

local function players()
    if type(Populate.adapters.players) == "function" then return Populate.adapters.players() or {} end
    local result = {}
    pcall(function()
        local locator = ProjectALife.PlayerLocator
        if locator == nil then return end
        for _, player in ipairs(locator.list()) do
            local position = locator.position(player)
            if position ~= nil then
                position.player = player
                result[#result + 1] = position
            end
        end
    end)
    return result
end

function Populate.playerPoints() return players() end

function Populate.factionFor(place, day, hour, roll)
    local rules, catalog = ProjectALife.FactionSpawnRules, ProjectALife.Catalog and ProjectALife.Catalog.current
    if rules == nil or catalog == nil then return nil end
    local point = { x = place.x, y = place.y, z = place.z or 0 }
    local fitted = rules.pick(catalog, point, "outpost", roll, nil, day, hour, nil,
        function(faction) return Populate.fits(faction.id, place.category) end)
    if fitted ~= nil then return fitted end
    local settled = rules.pick(catalog, point, "outpost", roll, nil, day, hour, nil,
        function(faction)
            local bloc = faction.relations and faction.relations.bloc
            return bloc ~= nil and Populate.fallbackBlocs[bloc] == true
        end)
    if settled ~= nil then return settled end
    return rules.pick(catalog, point, "outpost", roll, nil, day, hour, nil, function(faction)
        return not rules.hostile(faction)
    end)
end

function Populate.keepOut()
    local policy = ProjectALife.SpawnPolicy
    local ring = policy ~= nil and tonumber(policy.playerKeepOut) or nil
    return ring or tonumber(Populate.settings.minimumDistance) or 40
end

function Populate.settle(place, outcome, distance)
    local pressure = ProjectALife.WorldPressure
    local ticket = { id = place.pendingRequestId }
    if (tonumber(outcome.active) or 0) > 0 then pressure.commit(ticket, pressure.hours(0), place.pendingGroupId)
    else pressure.release(ticket, pressure.hours(0)) end
    local groupId = place.pendingGroupId
    place.pendingRequestId, place.pendingGroupId = nil, nil
    if (tonumber(outcome.active) or 0) > 0 then
        if place.manned ~= true then Populate.metrics.manned = Populate.metrics.manned + 1 end
        place.manned = true

        place.groupId = groupId or place.groupId
        place.cleared = nil
        emit("populate_manned", { key = place.key, faction = place.factionId,
            x = place.x, y = place.y, category = place.category, distance = distance })
    else
        place.refusals = (tonumber(place.refusals) or 0) + 1
        Populate.metrics.refused = Populate.metrics.refused + 1
        if place.refusals >= Populate.settings.maximumRefusals then
            Populate.metrics.given_up = Populate.metrics.given_up + 1
            emit("populate_given_up", { key = place.key, reason = outcome.reason, category = place.category })
        end
    end
end

function Populate.pending(place)
    if type(place.pendingRequestId) ~= "string" then return false end
    local service = Populate.adapters.service or ProjectALife.DebugService
    if service == nil or type(service.groupStatus) ~= "function" then return true end
    local status = service.groupStatus(place.pendingRequestId)
    if type(status) == "table" then
        if status.completed ~= true then return true end
        Populate.settle(place, status)
        return false
    end
    local registry, arrived = ProjectALife.ActorRegistry, false
    if registry == nil or type(registry.each) ~= "function" then return true end
    registry.each(function(record)
        if record.lifecycle ~= "dead" and record.memory and record.memory.groupId == place.pendingGroupId then
            arrived = true
            return true
        end
    end)
    if arrived then Populate.settle(place, { active = 1 })
    else Populate.settle(place, { active = 0, reason = "pending_lost" }) end
    return false
end

function Populate.groupIds()
    local state = Populate.state
    if state == nil then
        if type(Populate.adapters.getOrCreate) == "function" then
            state = store()
        elseif ModData ~= nil and type(ModData.exists) == "function" and type(ModData.get) == "function" then
            local ok, exists = pcall(ModData.exists, Populate.TAG)
            if ok and exists == true then
                local read, value = pcall(ModData.get, Populate.TAG)
                if read then state = value end
            end
        end
    end
    local result = {}
    for _, place in ipairs(type(state) == "table" and type(state.places) == "table" and state.places or {}) do
        if place.groupId ~= nil then result[place.groupId] = true end
        if place.pendingGroupId ~= nil then result[place.pendingGroupId] = true end
    end
    return result
end

function Populate.clearedUntil(hours)
    local census = ProjectALife.WorldPressure
    if type(census.censusClearedHours) == "function" then return hours + census.censusClearedHours() end
    return hours + census.settings.siteQuietHours
end

function Populate.resettles(place, hours)
    local census = ProjectALife.WorldPressure
    if type(census.censusSettle) ~= "function" then return true end
    return census.censusSettle("populate:" .. tostring(place.key), hours, place.x, place.y) == true
end

function Populate.audit(state, now, hours)
    now = tonumber(now) or nowMs()
    hours = tonumber(hours) or ProjectALife.WorldPressure.hours(0)
    local first = Populate.auditedAtMs == nil
    if not first and now - Populate.auditedAtMs < Populate.settings.auditMs then return 0 end
    Populate.auditedAtMs = now
    local watched, groups = {}, {}
    for _, place in ipairs(state.places or {}) do
        if place.manned == true and place.groupId ~= nil then watched[place.groupId] = true end
    end
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.each) ~= "function" then return 0 end
    registry.each(function(record)
        local id = type(record.memory) == "table" and record.memory.groupId or nil
        if id ~= nil and watched[id] then
            local row = groups[id]
            if row == nil then
                row = { alive = 0 }
                groups[id] = row
            end
            if record.lifecycle ~= "dead" then row.alive = row.alive + 1 end
        end
    end)
    local changed = 0
    for _, place in ipairs(state.places or {}) do
        if place.manned == true and place.pendingRequestId == nil then
            local reason
            if place.groupId ~= nil then
                local row = groups[place.groupId]
                if row == nil then
                    local ledger = ProjectALife.SquadLedger
                    local persistent = ledger ~= nil and type(ledger.read) == "function" and ledger.read(place.groupId) or nil
                    if persistent ~= nil and persistent.state ~= "wiped" then place.lostSinceHours = nil
                    elseif persistent ~= nil and persistent.state == "wiped" then
                        place.groupId, place.cleared = nil, true
                        place.clearedUntilHours = Populate.clearedUntil(hours)
                        place.lostSinceHours = nil
                        Populate.metrics.cleared = (Populate.metrics.cleared or 0) + 1
                        emit("populate_cleared", { key = place.key, town = place.town })
                        changed = changed + 1
                    else
                        local since = tonumber(place.lostSinceHours)
                        if since == nil or since > hours then place.lostSinceHours = hours
                        elseif hours - since >= ProjectALife.WorldPressure.settings.siteQuietHours then reason = "lost" end
                    end
                elseif row.alive == 0 then
                    place.groupId, place.cleared = nil, true
                    place.clearedUntilHours = Populate.clearedUntil(hours)
                    place.lostSinceHours = nil
                    Populate.metrics.cleared = (Populate.metrics.cleared or 0) + 1
                    emit("populate_cleared", { key = place.key, town = place.town })
                    changed = changed + 1
                else place.lostSinceHours = nil end
            elseif place.cleared == true then
                if place.clearedUntilHours == nil then
                    place.clearedUntilHours = Populate.clearedUntil(hours)
                elseif hours >= place.clearedUntilHours and Populate.resettles(place, hours) then
                    reason = "cleared_cooldown"
                end
            elseif first and place.cleared ~= true then
                reason = "unsaved"
            end
            if reason ~= nil then
                place.manned, place.groupId, place.factionId = false, nil, nil
                place.lostSinceHours, place.cleared, place.clearedUntilHours = nil, nil, nil
                Populate.metrics.reopened = (Populate.metrics.reopened or 0) + 1
                emit("populate_reopened", { key = place.key, town = place.town, reason = reason })
                changed = changed + 1
            end
        end
    end
    return changed
end

Populate.placeNames = { police = "Police station", fire = "Fire house", medical = "Clinic", guns = "Gun store",
    warehouse = "Warehouse", gas = "Gas station", motel = "Motel", food = "Diner", church = "Church",
    school = "School", store = "Store", house = "House" }

function Populate.spawning(place)
    return place.manned == true or type(place.pendingRequestId) == "string"
end

function Populate.open(place)
    if Populate.spawning(place) then return true end
    if (tonumber(place.refusals) or 0) >= Populate.settings.maximumRefusals then return false end
    return not ((tonumber(Populate.hoursSeen) or 0) >= Populate.settings.endHours)
end

function Populate.mapPlaces()
    local result = {}
    if Populate.settings.mode == "off" then return result end
    local state = Populate.state
    local now = nowMs()
    for _, place in ipairs(type(state) == "table" and type(state.places) == "table" and state.places or {}) do
        if Populate.open(place) then
            local seen = Populate.why[place.key]
            if seen ~= nil and now - (tonumber(seen.atMs) or 0) > Populate.settings.whyEveryMs then seen = nil end
            result[#result + 1] = { x = place.x, y = place.y, z = place.z or 0,
                name = Populate.placeNames[place.category] or tostring(place.category or "Place"),
                town = place.town, manned = Populate.spawning(place),
                waiting = seen and seen.why or nil, distance = seen and seen.distance or nil }
        end
    end
    return result
end

Populate.deferrals = { building_unloaded = true, window_rim = true, player_close = true }
for _, why in ipairs({ "player_hidden", "in_player_sight", "player_below_ground", "player_high_up", "floor_mismatch",
        "census_exhausted", "census_short", "census_cleared", "inside_player_base", "no_capacity",
        "pressure_quiet", "pressure_pending", "pressure_crowded", "pressure_history_full",
        "region_cooldown", "region_regrowing" }) do
    Populate.deferrals[why] = true
end

Populate.slowWaits = { inside_player_base = true, no_capacity = true, pressure_quiet = true, pressure_crowded = true,
    pressure_history_full = true, region_cooldown = true, region_regrowing = true,
    census_exhausted = true, census_short = true, census_cleared = true }

function Populate.resting(place, now)
    local seen = place.key ~= nil and Populate.why[place.key] or nil
    if seen == nil or Populate.slowWaits[tostring(seen.why)] ~= true then return false end
    local since = (tonumber(now) or 0) - (tonumber(seen.atMs) or 0)
    return since >= 0 and since < Populate.settings.slowRetryMs
end

Populate.unloadedWhy = { place_unloaded = "building_unloaded:place", window_edge = "building_unloaded:edge",
    window_incomplete = "building_unloaded:window", probe_failed = "building_unloaded:probe" }

function Populate.whyUnloaded(place)
    local policy = ProjectALife.SpawnPolicy
    local detail = policy ~= nil and policy.claimDetail or nil
    if detail == "cached" then
        local seen = Populate.why[place.key]
        return seen ~= nil and seen.why or "building_unloaded"
    end
    return Populate.unloadedWhy[tostring(detail)] or "building_unloaded"
end

function Populate.note(place, why, distance, now)
    if place.key == nil then return end
    local seen = Populate.why[place.key]
    if seen == nil then
        seen = {}
        Populate.why[place.key] = seen
    end
    seen.why, seen.distance, seen.atMs = why, math.floor(tonumber(distance) or 0), now
    Populate.waits[why] = (Populate.waits[why] or 0) + 1
    local since = now - (tonumber(seen.printedAtMs) or -1e12)
    if since >= Populate.settings.whyEveryMs or (seen.printedWhy ~= why and since >= Populate.settings.whyMinMs) then
        seen.printedWhy, seen.printedAtMs = why, now
        emit("populate_waiting", { key = place.key, town = place.town, distance = seen.distance, reason = why })
    end
end

function Populate.hiddenSquare(place)
    local policy = ProjectALife.SpawnPolicy
    if policy == nil or type(policy.find) ~= "function" or type(policy.hidden) ~= "function" then return false end
    local square = policy.find({ x = place.x, y = place.y, z = place.z or 0 }, {
        allowProtected = true, adminPlaced = true, searchRadius = 8, stationed = true, occluded = true,
        playerKeepOut = Populate.settings.closeKeepOut, validator = policy.hidden })
    return square ~= nil
end

function Populate.man(place, near, now, hours, close)
    local policy = ProjectALife.SpawnPolicy

    if policy ~= nil and type(policy.clearOfRim) == "function"
            and not policy.clearOfRim({ x = place.x, y = place.y, z = place.z or 0 }) then
        return false, "window_rim"
    end
    if policy ~= nil and type(policy.claimBuilding) == "function" then
        local claimed, claimReason = policy.claimBuilding({ x = place.x, y = place.y, z = place.z or 0 })
        if claimed ~= true then return false, claimReason end
    end
    if close == true and not Populate.hiddenSquare(place) then return false, "player_close" end
    local service = Populate.adapters.service or ProjectALife.DebugService
    local director = ProjectALife.EncounterDirector
    local definition = ProjectALife.Encounters.get("outpost")
    if service == nil or type(service.spawnEncounter) ~= "function" or definition == nil then
        return false, "service_unavailable"
    end
    local day, hour = (tonumber(hours) or 0) / 24, tonumber(hours) ~= nil and math.floor((tonumber(hours) + 7) % 24) or 12
    local unit = Populate.roll(place.key .. "|faction|" .. tostring(place.refusals or 0))

    local faction = nil
    if place.forceFactionId ~= nil and ProjectALife.Catalog ~= nil and type(ProjectALife.Catalog.faction) == "function" then
        faction = ProjectALife.Catalog.faction(place.forceFactionId)
    end
    faction = faction or Populate.factionFor(place, day, hour, unit)
    if faction == nil then return false, "no_faction" end
    local wanted = director ~= nil and type(director.partySize) == "function"
        and director.partySize(faction, definition, Populate.roll(place.key .. "|size")) or 3
    if director ~= nil and type(director.capacityLeft) == "function" then
        wanted = math.min(wanted, director.capacityLeft())
    end
    if wanted <= 0 then return false, "no_capacity" end
    local profiles = service.hostileProfileIds(wanted, math.floor(tonumber(now) or 0), faction.id, true)
    if type(profiles) ~= "table" or #profiles == 0 then return false, "no_profiles" end
    local ok, reason, result = ProjectALife.WorldPressure.spawn(service, near and near.player or nil, {
        requestId = "populate:" .. place.key .. ":" .. tostring(place.refusals or 0),
        origin = "director",
        count = #profiles,
        profileIds = profiles,
        factionId = faction.id,
        x = place.x, y = place.y, z = place.z or 0,
        distance = 0, separation = 1, radius = 6,
        mode = definition.mode or "guard",
        profile = definition.profile,
        conducts = definition.conducts,
        animation = "normal",
        encounterId = definition.id,

        encounterPersistent = definition.persistent == true,
        stance = definition.stance,
        playerKeepOut = close == true and Populate.settings.closeKeepOut or 0,
        hidden = close == true or nil,
    }, tonumber(hours) or 0, { site = "populate:" .. place.key })
    if not ok then return false, tostring(reason or (type(result) == "table" and result.reason) or result or "spawn_refused") end
    if type(result) == "table" and type(result.requestId) == "string"
            and type(result.groupId) == "string" and type(service.watchGroup) == "function" then
        place.pendingRequestId, place.pendingGroupId = result.requestId, result.groupId
        place.factionId = faction.id
        service.watchGroup(result.requestId, function(outcome)
            if place.pendingRequestId ~= result.requestId then return end
            local distance = near and math.floor(math.sqrt((place.x - near.x) ^ 2 + (place.y - near.y) ^ 2)) or nil
            Populate.settle(place, outcome, distance)
        end)
        return true, faction.id, true
    end
    return true, faction.id
end

function Populate.tick(now, hours)
    if Populate.settings.mode == "off" then return 0 end
    Populate.hoursSeen = tonumber(hours) or 0
    if (tonumber(hours) or 0) >= Populate.settings.endHours then return 0 end
    local state = store()
    if state == nil then return 0 end
    now = tonumber(now) or nowMs()

    if state.scanned ~= true then scan(state) end
    Populate.audit(state, now, hours)
    local list = players()
    Populate.nearest, Populate.nearestDistance = nil, nil
    if #list == 0 then return 0 end
    local reach = Populate.settings.spawnDistance
    local floor = Populate.keepOut()
    local locks = ProjectALife.RegionLocks
    local nearest = math.huge
    for _, place in ipairs(state.places or {}) do
        local pending = Populate.pending(place)
        if not pending and place.manned ~= true and (tonumber(place.refusals) or 0) < Populate.settings.maximumRefusals then
            local near, best = nil, math.huge
            for _, p in ipairs(list) do
                local dx, dy = (tonumber(p.x) or 0) - place.x, (tonumber(p.y) or 0) - place.y
                local d = math.sqrt(dx * dx + dy * dy)
                if d < best then near, best = p, d end
            end
            if best < nearest then
                nearest = best
                Populate.nearest, Populate.nearestDistance = place, best
            end

            if near ~= nil and best <= reach then
                local locked = false
                if locks ~= nil and type(locks.locked) == "function" then
                    local asked, answer = pcall(locks.locked, place.x, place.y)
                    locked = asked and answer == true
                end
                if locked then Populate.note(place, "region_locked", best, now) end
                if not locked and not Populate.resting(place, now) then
                    local ok, detail, queued = Populate.man(place, near, now, hours, best < floor)
                    if ok then
                        if place.key ~= nil then Populate.why[place.key] = nil end
                    elseif detail == "building_unloaded" then
                        Populate.note(place, Populate.whyUnloaded(place), best, now)
                    else
                        Populate.note(place, tostring(detail), best, now)
                    end
                    if ok then
                        if queued ~= true then
                            place.manned = true
                            place.factionId = detail
                            Populate.metrics.manned = Populate.metrics.manned + 1

                            emit("populate_manned", { key = place.key, faction = detail, x = place.x, y = place.y, category = place.category, distance = math.floor(best) })
                        end
                    elseif Populate.deferrals[tostring(detail)] ~= true then
                        Populate.settle(place, { active = 0, reason = detail })
                    end
                    if Populate.deferrals[tostring(detail)] ~= true then return 1 end
                end
            end
        end
    end
    return 0
end

function Populate.summary()
    local state = Populate.state
    local pending = 0
    local towns, names = {}, {}
    for _, place in ipairs(state and state.places or {}) do
        if place.manned ~= true then pending = pending + 1 end
        local key = tostring(place.town or "?")
        local row = towns[key]
        if row == nil then
            row = { places = 0, manned = 0 }
            towns[key] = row
            names[#names + 1] = key
        end
        row.places = row.places + 1
        if place.manned == true then row.manned = row.manned + 1 end
    end
    table.sort(names)
    local parts = {}
    for _, key in ipairs(names) do parts[#parts + 1] = key .. ":" .. towns[key].places .. "/" .. towns[key].manned end
    return string.format("PopulateDirector: mode=%s scanned=%s places=%d manned=%d pending=%d refused=%d given_up=%d reopened=%d cleared=%d boxes=%d rooms=%d towns=%s",
        tostring(Populate.settings.mode), tostring(state and state.scanned), state and #(state.places or {}) or 0,
        Populate.metrics.manned, pending, Populate.metrics.refused, Populate.metrics.given_up,
        Populate.metrics.reopened or 0, Populate.metrics.cleared or 0,
        Populate.metrics.boxes, Populate.metrics.rooms, #parts > 0 and table.concat(parts, ",") or "-") .. Populate.whyText()
end

function Populate.whyText()
    local near, nearText = Populate.nearest, "-"
    if type(near) == "table" then
        local distance = math.floor(tonumber(Populate.nearestDistance) or 0)
        local seen = near.key ~= nil and Populate.why[near.key] or nil
        local why = distance > (tonumber(Populate.settings.spawnDistance) or 90) and "beyond_reach"
            or (seen ~= nil and seen.why) or "-"
        nearText = tostring(near.key) .. "(" .. tostring(near.town) .. ")@" .. distance .. ":" .. tostring(why)
    end
    local parts = {}
    for why, count in pairs(Populate.waits) do parts[#parts + 1] = tostring(why) .. ":" .. tostring(count) end
    table.sort(parts)
    return " near=" .. nearText .. " waits=" .. (#parts == 0 and "-" or table.concat(parts, ";"))
end

return Populate
