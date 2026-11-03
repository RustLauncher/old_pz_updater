require "ProjectALife/Core/ALifePersistence"

ProjectALife = ProjectALife or {}

local BaseHeat = {
    settings = {
        scanEveryGameMinutes = 10,

        scanBudget = 40,
        vehicleRadius = 30,
        metalBarricade = 3,
        plankBarricade = 1,
        hotwiredVehicle = 4,
        builtWall = 2,
        decayPerDay = 0.10,
        anchorThreshold = 30,
        postRaidGraceDays = 3,
        anchorCap = 6,
        hintCap = 6,
        presenceCap = 32,
        presenceKeepDays = 30,
        anchorExpireDays = 21,
        dwellMinutes = 45,
        dwellDays = 2,
        promoteBarricades = 3,
        promoteBuilds = 6,
        evidenceMargin = 20,
        evidenceEveryHours = 6,
        evidenceAfterMinutes = 5,
        outdoorEvidenceMinutes = 15,
        anchorPad = 2,
        anchorMaxSide = 96,
        outdoorCell = 16,
        flag = { on = true, dedicated = false, threshold = 100, minFactors = 2, night = 20, nightsCap = 60,
            day = 10, daysCap = 40, build = 2, buildsCap = 40, board = 3, boardsCap = 30, generator = 20,
            claim = 30, homeMargin = 4, cacheMs = 5000, yardEveryHours = 24, yardBudget = 1500, yardReach = 40 },
        occupancy = { on = true, hours = 12, dwellMs = 30000, everyMs = 1000, limit = 24 },
    },
    adapters = {},
    scans = {},
    evidenceScans = {},
    occupancySince = {},
    cursor = 0,
    fallbackStore = { players = {} },
    metrics = { players = 0, squares = 0, passes = 0, raids = 0, promoted = 0, evidence = 0, expired = 0,
        flagged = 0 },
    npcBoardKey = "ProjectALifeNpcBoards",
    homesVersion = 0,
    flagCache = nil,
}
ProjectALife.BaseHeat = BaseHeat

local function worldHours()
    if type(BaseHeat.adapters.worldHours) == "function" then
        return tonumber(BaseHeat.adapters.worldHours()) or 0
    end
    local value = 0
    pcall(function() value = getGameTime():getWorldAgeHours() end)
    return tonumber(value) or 0
end

local function playerKey(player)
    if type(BaseHeat.adapters.playerKey) == "function" then
        return tostring(BaseHeat.adapters.playerKey(player))
    end
    local value
    pcall(function() value = player:getUsername() end)
    return value ~= nil and tostring(value) or tostring(player)
end

local function store()
    if type(BaseHeat.adapters.store) == "function" then
        local supplied = BaseHeat.adapters.store()
        if type(supplied) == "table" then
            supplied.players = type(supplied.players) == "table" and supplied.players or {}
            return supplied
        end
    end
    local persistence = ProjectALife.Persistence
    if persistence ~= nil and type(persistence.bucket) == "function" then
        local value = persistence.bucket("baseHeat", { players = {} })
        if type(value) == "table" then
            value.players = type(value.players) == "table" and value.players or {}
            return value
        end
    end
    return BaseHeat.fallbackStore
end

local function dirty()
    if type(BaseHeat.adapters.dirty) == "function" then
        BaseHeat.adapters.dirty()
        return
    end
    local persistence = ProjectALife.Persistence
    if persistence ~= nil and type(persistence.touch) == "function" then
        persistence.touch()
    end
end

function BaseHeat.dropPolicyCache()
    local policy = ProjectALife.DoorPolicy
    if policy ~= nil and type(policy.dropCache) == "function" then policy.dropCache() end
end

function BaseHeat.configure(adapters)
    BaseHeat.dropPolicyCache()
    BaseHeat.adapters = type(adapters) == "table" and adapters or {}
    BaseHeat.scans = {}
    BaseHeat.evidenceScans = {}
    BaseHeat.occupancySince, BaseHeat.occupancyAtMs = {}, nil
    BaseHeat.cursor = 0
    BaseHeat.flagCache = nil
    return true
end

function BaseHeat.reset()
    BaseHeat.dropPolicyCache()
    BaseHeat.adapters = {}
    BaseHeat.scans = {}
    BaseHeat.evidenceScans = {}
    BaseHeat.occupancySince, BaseHeat.occupancyAtMs = {}, nil
    BaseHeat.cursor = 0
    BaseHeat.fallbackStore = { players = {} }
    BaseHeat.homesVersion, BaseHeat.flagCache = 0, nil
    BaseHeat.metrics = { players = 0, squares = 0, passes = 0, raids = 0, promoted = 0, evidence = 0, expired = 0,
        flagged = 0 }
end

function BaseHeat.anchorsChanged()
    BaseHeat.homesVersion = BaseHeat.homesVersion + 1
    BaseHeat.dropPolicyCache()
    dirty()
end

function BaseHeat.score(parts)
    parts = type(parts) == "table" and parts or {}
    local settings = BaseHeat.settings
    return math.max(0,
        math.max(0, tonumber(parts.metalBarricades) or 0) * settings.metalBarricade
        + math.max(0, tonumber(parts.plankBarricades) or 0) * settings.plankBarricade
        + math.max(0, tonumber(parts.hotwiredVehicles) or 0) * settings.hotwiredVehicle
        + math.max(0, tonumber(parts.builtWalls) or 0) * settings.builtWall)
end

function BaseHeat.decayed(previous, elapsedDays, visibleNow)
    local old = math.max(0, tonumber(previous) or 0)
    local days = math.max(0, tonumber(elapsedDays) or 0)
    local floorNow = math.max(0, tonumber(visibleNow) or 0)
    local cooled = old * ((1 - BaseHeat.settings.decayPerDay) ^ days)
    return math.max(floorNow, cooled)
end

function BaseHeat.multiplier(score)
    return 1 + math.max(0, tonumber(score) or 0) / 25
end

function BaseHeat.targetRecord(entry, liveX, liveY, hours)
    entry = type(entry) == "table" and entry or {}
    local score = math.max(0, tonumber(entry.score) or 0)
    local lastRaid = tonumber(entry.lastRaidHour) or -1e9
    local grace = BaseHeat.settings.postRaidGraceDays * 24
    local cooling = (tonumber(hours) or 0) < lastRaid + grace
    local base = type(entry.base) == "table" and entry.base or nil
    local anchored = not cooling and score >= BaseHeat.settings.anchorThreshold
        and base ~= nil and tonumber(base.x) ~= nil and tonumber(base.y) ~= nil
    return {
        x = anchored and tonumber(base.x) or tonumber(liveX) or 0,
        y = anchored and tonumber(base.y) or tonumber(liveY) or 0,
        z = anchored and (tonumber(base.z) or 0) or 0,
        score = score,
        mult = cooling and 1 or BaseHeat.multiplier(score),
        anchor = anchored,
        cooling = cooling,
    }
end

local function buildingBounds(building)
    if building == nil then return nil end
    if type(BaseHeat.adapters.buildingBounds) == "function" then
        return BaseHeat.adapters.buildingBounds(building)
    end
    local bounds
    pcall(function()
        local definition = building:getDef()
        if definition == nil then return end
        bounds = {
            x1 = math.floor(definition:getX()),
            y1 = math.floor(definition:getY()),
            x2 = math.floor(definition:getX2()),
            y2 = math.floor(definition:getY2()),
            z = 0,
        }
    end)
    return bounds
end

local function baseKey(bounds)
    if type(bounds) ~= "table" then return nil end
    return table.concat({ bounds.x1, bounds.y1, bounds.x2, bounds.y2 }, ":")
end

local function currentBuilding(player)
    if type(BaseHeat.adapters.currentBuilding) == "function" then
        return BaseHeat.adapters.currentBuilding(player)
    end
    local building
    pcall(function() building = player:getBuilding() end)
    return building
end

local function safehouseClaimed(player)
    if type(BaseHeat.adapters.safehouseClaimed) == "function" then
        return BaseHeat.adapters.safehouseClaimed(player) == true
    end
    if player == nil or type(player.getSquare) ~= "function" or SafeHouse == nil
            or type(SafeHouse.isSafeHouse) ~= "function" then return false end
    local claimed = false
    pcall(function()
        local square = player:getSquare()
        claimed = square ~= nil and SafeHouse.isSafeHouse(square, nil, true) ~= nil
    end)
    return claimed
end

function BaseHeat.asleep(player)
    if type(BaseHeat.adapters.asleep) == "function" then
        return BaseHeat.adapters.asleep(player) == true
    end
    local kind = type(player)
    if (kind ~= "userdata" and kind ~= "table") or player.isAsleep == nil then return false end
    return player:isAsleep() == true
end

function BaseHeat.positionOf(player)
    local kind = type(player)
    if (kind ~= "userdata" and kind ~= "table") or player.getX == nil or player.getY == nil then return nil end
    local x, y = tonumber(player:getX()), tonumber(player:getY())
    if x == nil or y == nil then return nil end
    local z = player.getZ ~= nil and tonumber(player:getZ()) or 0
    return x, y, math.floor(z or 0)
end

function BaseHeat.placeOf(player)
    local building = currentBuilding(player)
    if building ~= nil then
        local bounds = buildingBounds(building)
        if bounds == nil then return nil end
        return { key = baseKey(bounds), x1 = bounds.x1, y1 = bounds.y1, x2 = bounds.x2, y2 = bounds.y2,
            z = bounds.z or 0, indoor = true }
    end
    local x, y, z = BaseHeat.positionOf(player)
    if x == nil then return nil end
    local size = BaseHeat.settings.outdoorCell
    local cx, cy = math.floor(x / size), math.floor(y / size)
    return { key = "cell:" .. cx .. ":" .. cy, x1 = cx * size, y1 = cy * size,
        x2 = cx * size + size - 1, y2 = cy * size + size - 1, z = z or 0, indoor = false }
end

function BaseHeat.overlaps(a, b, pad)
    pad = tonumber(pad) or 0
    return type(a) == "table" and type(b) == "table"
        and tonumber(a.x1) ~= nil and tonumber(b.x1) ~= nil
        and a.x1 - pad <= b.x2 and b.x1 <= a.x2 + pad
        and a.y1 - pad <= b.y2 and b.y1 <= a.y2 + pad
end

function BaseHeat.anchorsOf(entry)
    if type(entry.anchors) ~= "table" then entry.anchors = {} end
    return entry.anchors
end

function BaseHeat.anchorAt(entry, place)
    if type(entry.anchors) ~= "table" or type(place) ~= "table" then return nil end
    for _, anchor in ipairs(entry.anchors) do
        if type(anchor) == "table" and (anchor.key == place.key or BaseHeat.overlaps(anchor, place)) then
            return anchor
        end
    end
    return nil
end

function BaseHeat.baseOf(anchor)
    local x1 = tonumber(anchor.cx1) or anchor.x1
    local y1 = tonumber(anchor.cy1) or anchor.y1
    local x2 = tonumber(anchor.cx2) or anchor.x2
    local y2 = tonumber(anchor.cy2) or anchor.y2
    return { key = anchor.key, x1 = x1, y1 = y1, x2 = x2, y2 = y2, z = anchor.z or 0,
        x = (x1 + x2) / 2, y = (y1 + y2) / 2 }
end

function BaseHeat.migrate(entry, hours)
    if type(entry.anchors) ~= "table" then
        entry.anchors = {}
        local base = entry.base
        if type(base) == "table" and tonumber(base.x1) ~= nil and tonumber(base.y2) ~= nil then
            entry.anchors[1] = { key = base.key or baseKey(base), x1 = base.x1, y1 = base.y1,
                x2 = base.x2, y2 = base.y2, z = base.z or 0, why = "legacy",
                promotedHour = hours, lastSeenHour = hours }
        end
        if type(entry.presence) == "table" then
            for key, row in pairs(entry.presence) do
                if type(row) ~= "table" or type(row.days) ~= "table" then entry.presence[key] = nil end
            end
        end
    end
end

function BaseHeat.prunePresence(entry, hours)
    local keep = BaseHeat.settings.presenceKeepDays * 24
    local count, oldestKey, oldestHour = 0, nil, math.huge
    for key, row in pairs(entry.presence) do
        local last = type(row) == "table" and tonumber(row.lastHour) or nil
        if last == nil or hours - last > keep then
            entry.presence[key] = nil
        else
            count = count + 1
            if last < oldestHour then oldestKey, oldestHour = key, last end
        end
    end
    if count > BaseHeat.settings.presenceCap and oldestKey ~= nil then entry.presence[oldestKey] = nil end
end

function BaseHeat.notePresence(entry, place, hours)
    if type(entry.presence) ~= "table" then entry.presence = {} end
    local row = entry.presence[place.key]
    if type(row) ~= "table" then
        row = { lastHour = hours, days = {} }
        entry.presence[place.key] = row
        BaseHeat.prunePresence(entry, hours)
    end
    if type(row.days) ~= "table" then row.days = {} end
    local credit = 0
    if entry.lastKey == place.key then
        credit = math.min(BaseHeat.settings.scanEveryGameMinutes,
            math.max(0, (hours - (tonumber(row.lastHour) or hours)) * 60))
    end
    local day = tostring(math.floor(hours / 24))
    if row.days[day] == nil then
        local oldest = math.floor(hours / 24) - BaseHeat.settings.presenceKeepDays
        for key, minutes in pairs(row.days) do
            if (tonumber(minutes) or 0) < BaseHeat.settings.dwellMinutes or (tonumber(key) or 0) < oldest then
                row.days[key] = nil
            end
        end
    end
    row.days[day] = (tonumber(row.days[day]) or 0) + credit
    row.lastHour = hours
    entry.lastKey = place.key
    return row
end

function BaseHeat.dwellDays(row)
    local count = 0
    for _, minutes in pairs(type(row) == "table" and type(row.days) == "table" and row.days or {}) do
        if (tonumber(minutes) or 0) >= BaseHeat.settings.dwellMinutes then count = count + 1 end
    end
    return count
end

function BaseHeat.minutesToday(row, hours)
    if type(row) ~= "table" or type(row.days) ~= "table" then return 0 end
    return tonumber(row.days[tostring(math.floor(hours / 24))]) or 0
end

function BaseHeat.promote(entry, region, why, hours, keepBase)
    local anchors = BaseHeat.anchorsOf(entry)
    local anchor = BaseHeat.anchorAt(entry, region)
    local changed = false
    if anchor == nil then
        if #anchors >= BaseHeat.settings.anchorCap then
            table.remove(anchors, BaseHeat.evictable(entry, anchors))
        end
        anchor = { key = region.key, x1 = region.x1, y1 = region.y1, x2 = region.x2, y2 = region.y2,
            z = region.z or 0, cx1 = region.cx1, cy1 = region.cy1, cx2 = region.cx2, cy2 = region.cy2,
            why = why, promotedHour = hours }
        anchors[#anchors + 1] = anchor
        BaseHeat.metrics.promoted = BaseHeat.metrics.promoted + 1
        BaseHeat.dropHints(entry, anchor)
        changed = true
    elseif region.x1 < anchor.x1 or region.y1 < anchor.y1 or region.x2 > anchor.x2 or region.y2 > anchor.y2 then
        BaseHeat.grow(anchor, region)
        changed = true
    end
    anchor.lastSeenHour = hours
    local base = entry.base
    if type(base) == "table" and base.key == anchor.key then
        if changed then entry.base = BaseHeat.baseOf(anchor) end
    elseif type(base) ~= "table" or keepBase ~= true then
        entry.base = BaseHeat.baseOf(anchor)
        changed = true
    end
    if changed then BaseHeat.anchorsChanged() end
    return anchor
end

function BaseHeat.kept(anchor)
    local why = anchor.why
    return anchor.flagged == true or anchor.claimed == true or anchor.dwelt == true or anchor.evidence == true
        or (tonumber(anchor.nights) or 0) >= 2
        or why == "safehouse" or why == "dwell" or why == "legacy"
        or why == "barricades" or why == "builds" or why == "generator"
end

function BaseHeat.evictable(entry, anchors)
    local raid = type(entry.base) == "table" and entry.base.key or nil
    local pick, pickKept, pickHour = nil, true, math.huge
    for index, candidate in ipairs(anchors) do
        if candidate.key ~= raid then
            local kept = BaseHeat.kept(candidate)
            local seen = tonumber(candidate.lastSeenHour) or -math.huge
            if pick == nil or (pickKept and not kept) or (kept == pickKept and seen < pickHour) then
                pick, pickKept, pickHour = index, kept, seen
            end
        end
    end
    return pick or 1
end

function BaseHeat.noteLived(anchor, why, hours)
    if why == "safehouse" then
        anchor.claimed = true
    elseif why == "dwell" then
        anchor.dwelt = true
    elseif why == "sleep" then
        local night = math.floor((hours - 12) / 24)
        if anchor.night ~= night then
            anchor.night = night
            anchor.nights = (tonumber(anchor.nights) or 0) + 1
        end
    end
end

function BaseHeat.grow(anchor, region)
    anchor.x1, anchor.y1 = math.min(anchor.x1, region.x1), math.min(anchor.y1, region.y1)
    anchor.x2, anchor.y2 = math.max(anchor.x2, region.x2), math.max(anchor.y2, region.y2)
    BaseHeat.cap(anchor)
end

function BaseHeat.cap(box)
    local side = BaseHeat.settings.anchorMaxSide
    box.x1, box.x2 = BaseHeat.capAxis(box.x1, box.x2, tonumber(box.cx1), tonumber(box.cx2), side)
    box.y1, box.y2 = BaseHeat.capAxis(box.y1, box.y2, tonumber(box.cy1), tonumber(box.cy2), side)
    return box
end

function BaseHeat.capAxis(a1, a2, c1, c2, side)
    if a2 - a1 + 1 <= side then return a1, a2 end
    local b1 = math.floor((a1 + a2) / 2) - math.floor(side / 2)
    if c1 ~= nil and c2 ~= nil and c2 - c1 + 1 <= side then
        if c1 < b1 then b1 = c1 end
        if c2 > b1 + side - 1 then b1 = c2 - side + 1 end
    end
    return b1, b1 + side - 1
end

function BaseHeat.hint(entry, region, hours)
    if type(entry.hints) ~= "table" then entry.hints = {} end
    local hints = entry.hints
    for _, hint in ipairs(hints) do
        if hint.key == region.key or BaseHeat.overlaps(hint, region) then
            BaseHeat.grow(hint, region)
            hint.lastSeenHour = hours
            return hint
        end
    end
    local keep = BaseHeat.settings.presenceKeepDays * 24
    for index = #hints, 1, -1 do
        if hours - (tonumber(hints[index].lastSeenHour) or hours) > keep then table.remove(hints, index) end
    end
    if #hints >= BaseHeat.settings.hintCap then table.remove(hints, 1) end
    local hint = { key = region.key, x1 = region.x1, y1 = region.y1, x2 = region.x2, y2 = region.y2,
        z = region.z or 0, lastSeenHour = hours, hint = true }
    hints[#hints + 1] = hint
    dirty()
    return hint
end

function BaseHeat.dropHints(entry, anchor)
    if type(entry.hints) ~= "table" then return end
    for index = #entry.hints, 1, -1 do
        if BaseHeat.overlaps(entry.hints[index], anchor) then table.remove(entry.hints, index) end
    end
end

function BaseHeat.notePlayer(player, entry, hours)
    local place = BaseHeat.placeOf(player)
    if place == nil then return nil end
    local row = BaseHeat.notePresence(entry, place, hours)
    local anchor = BaseHeat.anchorAt(entry, place)
    if anchor ~= nil then anchor.lastSeenHour = hours end
    local why
    if safehouseClaimed(player) then
        why = "safehouse"
    elseif BaseHeat.asleep(player) then
        why = "sleep"
    elseif BaseHeat.dwellDays(row) >= BaseHeat.settings.dwellDays then
        why = "dwell"
    end
    if why ~= nil and anchor ~= nil then
        BaseHeat.confirm(entry, anchor)
    elseif why ~= nil then
        anchor = BaseHeat.promote(entry, { key = place.key, x1 = place.x1, y1 = place.y1, x2 = place.x2,
            y2 = place.y2, z = place.z, cx1 = place.x1, cy1 = place.y1, cx2 = place.x2, cy2 = place.y2 }, why, hours)
    end
    if why ~= nil then BaseHeat.noteLived(anchor, why, hours) end
    if anchor ~= nil then BaseHeat.noteDays(anchor, row, hours) end
    return place, row
end

function BaseHeat.confirm(entry, anchor)
    local base = entry.base
    if type(base) == "table" and base.key == anchor.key then return false end
    entry.base = BaseHeat.baseOf(anchor)
    dirty()
    return true
end

local function squareAt(x, y, z)
    if type(BaseHeat.adapters.squareAt) == "function" then
        return BaseHeat.adapters.squareAt(x, y, z)
    end
    local square
    pcall(function() square = getCell():getGridSquare(x, y, z) end)
    return square
end

local function objectsOf(square)
    local result, seen = {}, {}
    local function append(collection)
        if collection == nil or type(collection.size) ~= "function" then return end
        for index = 0, collection:size() - 1 do
            local object = collection:get(index)
            if object ~= nil and not seen[object] then
                seen[object] = true
                result[#result + 1] = object
            end
        end
    end
    pcall(function() append(square:getObjects()) end)
    pcall(function() append(square:getSpecialObjects()) end)
    return result
end

function BaseHeat.stampNpcBarricade(barricade)
    local kind = type(barricade)
    if (kind ~= "userdata" and kind ~= "table") or barricade.getModData == nil then return false end
    local data = barricade:getModData()
    if data == nil then return false end
    data[BaseHeat.npcBoardKey] = true
    return true
end

function BaseHeat.npcBarricade(barricade)
    local kind = type(barricade)
    if (kind ~= "userdata" and kind ~= "table") or barricade.getModData == nil then return false end
    if barricade.hasModData ~= nil and barricade:hasModData() ~= true then return false end
    local data = barricade:getModData()
    return data ~= nil and data[BaseHeat.npcBoardKey] == true
end

local function countBarricade(barricade, seen, parts)
    if barricade == nil or seen[barricade] then return end
    seen[barricade] = true
    if BaseHeat.npcBarricade(barricade) then return end
    local metal, planked = false, false
    pcall(function()
        metal = barricade:isMetal() == true or barricade:isMetalBar() == true
        planked = barricade:getNumPlanks() > 0
    end)
    if metal then parts.metalBarricades = parts.metalBarricades + 1
    elseif planked then parts.plankBarricades = parts.plankBarricades + 1 end
end

local function builtWall(object)
    local result = false
    pcall(function()
        if type(instanceof) ~= "function" or not instanceof(object, "IsoThumpable")
                or object:isDoor() then return end
        local name = string.lower(tostring(object:getName() or ""))
        if string.find(name, "wall", 1, true) or string.find(name, "fence", 1, true)
                or string.find(name, "barbed", 1, true) then
            result = true
            return
        end
        local properties = object:getSprite():getProperties()
        if properties ~= nil and IsoPropertyType ~= nil then
            result = properties:has(IsoPropertyType.WALL_N)
                or properties:has(IsoPropertyType.WALL_W)
                or properties:has(IsoPropertyType.WALL_N_TRANS)
                or properties:has(IsoPropertyType.WALL_W_TRANS)
        end
    end)
    return result
end

function BaseHeat.barricadable(object)
    return type(instanceof) == "function" and (
        instanceof(object, "IsoDoor") or instanceof(object, "IsoWindow")
        or instanceof(object, "IsoWindowFrame")
        or (instanceof(object, "IsoThumpable") and object:getCanBarricade()))
end

local function scanSquare(scan, x, y, z, perimeter)
    local square = squareAt(x, y, z)
    if square == nil then return end
    for _, object in ipairs(objectsOf(square)) do
        local barricadable = type(instanceof) == "function" and (
            instanceof(object, "IsoDoor") or instanceof(object, "IsoWindow")
            or instanceof(object, "IsoWindowFrame")
            or (instanceof(object, "IsoThumpable") and object:getCanBarricade()))
        if barricadable then
            countBarricade(object:getBarricadeOnSameSquare(), scan.seenBarricades, scan.parts)
            countBarricade(object:getBarricadeOnOppositeSquare(), scan.seenBarricades, scan.parts)
        end
        if perimeter and not scan.seenWalls[object] and builtWall(object) then
            scan.seenWalls[object] = true
            scan.parts.builtWalls = scan.parts.builtWalls + 1
        end
    end
end

local function hotwiredNear(base)
    if type(BaseHeat.adapters.hotwiredNear) == "function" then
        return math.max(0, tonumber(BaseHeat.adapters.hotwiredNear(base,
            BaseHeat.settings.vehicleRadius)) or 0)
    end
    local count, radius = 0, BaseHeat.settings.vehicleRadius
    pcall(function()
        local vehicles = getCell():getVehicles()
        if vehicles == nil or vehicles.toArray == nil then return end
        for _, vehicle in pairs(vehicles:toArray()) do
            local dx, dy = vehicle:getX() - base.x, vehicle:getY() - base.y
            if dx * dx + dy * dy <= radius * radius
                    and vehicle:isHotwired() == true then count = count + 1 end
        end
    end)
    return count
end

local function finishScan(key, entry, scan, hours)
    scan.parts.hotwiredVehicles = hotwiredNear(scan.base)
    local visible = BaseHeat.score(scan.parts)
    local last = tonumber(entry.scoredAtHour) or hours
    entry.score = BaseHeat.decayed(entry.score, math.max(0, hours - last) / 24, visible)
    entry.visibleScore = visible
    entry.scoredAtHour = hours
    entry.nextScanHour = hours + BaseHeat.settings.scanEveryGameMinutes / 60
    BaseHeat.scans[key] = nil
    BaseHeat.metrics.passes = BaseHeat.metrics.passes + 1
    dirty()
end

function BaseHeat.heatStep(key, entry, hours)
    local base = entry.base
    if type(base) ~= "table" or tonumber(base.x1) == nil then return 0 end
    local scan = BaseHeat.scans[key]
    if scan == nil then
        if hours < (tonumber(entry.nextScanHour) or -1e9) then return 0 end
        scan = {
            base = base, cursor = 0,
            parts = { metalBarricades = 0, plankBarricades = 0,
                hotwiredVehicles = 0, builtWalls = 0 },
            seenBarricades = {}, seenWalls = {},
        }
        BaseHeat.scans[key] = scan
    end
    local width = math.max(1, scan.base.x2 - scan.base.x1 + 1)
    local height = math.max(1, scan.base.y2 - scan.base.y1 + 1)
    local total = width * height
    local processed = 0
    while processed < BaseHeat.settings.scanBudget and scan.cursor < total do
        local at = scan.cursor
        local x = scan.base.x1 + (at % width)
        local y = scan.base.y1 + math.floor(at / width)
        local perimeter = x == scan.base.x1 or x == scan.base.x2
            or y == scan.base.y1 or y == scan.base.y2
        scanSquare(scan, x, y, scan.base.z or 0, perimeter)
        scan.cursor = scan.cursor + 1
        processed = processed + 1
    end
    BaseHeat.metrics.squares = BaseHeat.metrics.squares + processed
    if scan.cursor >= total then finishScan(key, entry, scan, hours) end
    return processed
end

function BaseHeat.evidenceTarget(entry, place, row, hours)
    local settings = BaseHeat.settings
    if place ~= nil then
        local anchor = BaseHeat.anchorAt(entry, place)
        if anchor ~= nil then
            if hours >= (tonumber(anchor.evidenceHour) or -1e9) + settings.evidenceEveryHours then
                anchor.evidenceHour = hours
                return { key = anchor.key, x1 = anchor.x1, y1 = anchor.y1, x2 = anchor.x2, y2 = anchor.y2,
                    z = anchor.z or 0, anchorKey = anchor.key }
            end
        elseif type(row) == "table"
                and BaseHeat.minutesToday(row, hours) >= (place.indoor and settings.evidenceAfterMinutes
                    or settings.outdoorEvidenceMinutes)
                and hours >= (tonumber(row.evidenceHour) or -1e9) + settings.evidenceEveryHours then
            row.evidenceHour = hours
            return { key = place.key, x1 = place.x1, y1 = place.y1, x2 = place.x2, y2 = place.y2,
                z = place.z or 0, indoor = place.indoor }
        end
    end
    local absent = settings.anchorExpireDays * 24
    for _, anchor in ipairs(type(entry.anchors) == "table" and entry.anchors or {}) do
        if hours - (tonumber(anchor.lastSeenHour) or hours) > absent
                and hours >= (tonumber(anchor.evidenceHour) or -1e9) + settings.evidenceEveryHours
                and squareAt(math.floor((anchor.x1 + anchor.x2) / 2), math.floor((anchor.y1 + anchor.y2) / 2),
                    anchor.z or 0) ~= nil then
            anchor.evidenceHour = hours
            return { key = anchor.key, x1 = anchor.x1, y1 = anchor.y1, x2 = anchor.x2, y2 = anchor.y2,
                z = anchor.z or 0, anchorKey = anchor.key, expiring = true }
        end
    end
    return nil
end

function BaseHeat.newEvidenceScan(target)
    local margin = BaseHeat.settings.evidenceMargin
    local area = BaseHeat.cap({ x1 = target.x1 - margin, y1 = target.y1 - margin,
        x2 = target.x2 + margin, y2 = target.y2 + margin })
    return { target = target, x1 = area.x1, y1 = area.y1, x2 = area.x2, y2 = area.y2, z = target.z or 0,
        cursor = 0, unloaded = 0, seen = {}, defs = {}, defCount = 0,
        parts = { playerBarricades = 0, builds = 0, generators = 0 } }
end

function BaseHeat.notePlayerBarricade(scan, barricade)
    if barricade == nil or scan.seen[barricade] then return end
    scan.seen[barricade] = true
    if not BaseHeat.npcBarricade(barricade) then
        scan.parts.playerBarricades = scan.parts.playerBarricades + 1
    end
end

function BaseHeat.evidenceSquare(scan, x, y, z)
    local square = squareAt(x, y, z)
    if square == nil then
        scan.unloaded = scan.unloaded + 1
        return
    end
    local target = scan.target
    local own = x >= target.x1 - 1 and x <= target.x2 + 1 and y >= target.y1 - 1 and y <= target.y2 + 1
    local objects = objectsOf(square)
    for _, object in ipairs(objects) do
        if own and BaseHeat.barricadable(object) then
            BaseHeat.notePlayerBarricade(scan, object:getBarricadeOnSameSquare())
            BaseHeat.notePlayerBarricade(scan, object:getBarricadeOnOppositeSquare())
        end
        local built = type(instanceof) == "function" and instanceof(object, "IsoThumpable")
            and object.isDismantable ~= nil and object:isDismantable() == true
        local powered = not built and type(instanceof) == "function" and instanceof(object, "IsoGenerator")
            and object.isActivated ~= nil and object:isActivated() == true
        if built or powered then
            if built then scan.parts.builds = scan.parts.builds + 1 end
            if powered then scan.parts.generators = scan.parts.generators + 1 end
            local cluster = scan.cluster
            if cluster == nil then
                scan.cluster = { x1 = x, y1 = y, x2 = x, y2 = y }
            else
                cluster.x1, cluster.y1 = math.min(cluster.x1, x), math.min(cluster.y1, y)
                cluster.x2, cluster.y2 = math.max(cluster.x2, x), math.max(cluster.y2, y)
            end
        end
    end
    if #objects > 0 and square.getBuilding ~= nil and scan.defCount < 16 then
        local building = square:getBuilding()
        if building ~= nil and building ~= scan.lastBuilding then
            scan.lastBuilding = building
            local bounds = buildingBounds(building)
            local key = bounds ~= nil and baseKey(bounds) or nil
            if key ~= nil and scan.defs[key] == nil then
                scan.defs[key] = bounds
                scan.defCount = scan.defCount + 1
            end
        end
    end
end

function BaseHeat.regionOf(scan)
    local target = scan.target
    local region = { key = target.key, x1 = target.x1, y1 = target.y1, x2 = target.x2, y2 = target.y2,
        z = target.z or 0, cx1 = target.x1, cy1 = target.y1, cx2 = target.x2, cy2 = target.y2 }
    local cluster = scan.cluster
    if cluster ~= nil then
        local pad = BaseHeat.settings.anchorPad
        region.x1, region.y1 = math.min(region.x1, cluster.x1 - pad), math.min(region.y1, cluster.y1 - pad)
        region.x2, region.y2 = math.max(region.x2, cluster.x2 + pad), math.max(region.y2, cluster.y2 + pad)
        for _, bounds in pairs(scan.defs) do
            if BaseHeat.overlaps(bounds, region) then
                region.x1, region.y1 = math.min(region.x1, bounds.x1), math.min(region.y1, bounds.y1)
                region.x2, region.y2 = math.max(region.x2, bounds.x2), math.max(region.y2, bounds.y2)
            end
        end
    end
    return BaseHeat.cap(region)
end

function BaseHeat.finishEvidence(entry, scan, hours)
    local parts, settings = scan.parts, BaseHeat.settings
    local found = parts.playerBarricades + parts.builds + parts.generators > 0
    BaseHeat.metrics.evidence = BaseHeat.metrics.evidence + 1
    local anchor
    if scan.target.anchorKey ~= nil then
        for index, candidate in ipairs(BaseHeat.anchorsOf(entry)) do
            if candidate.key == scan.target.anchorKey then
                anchor = candidate
                if scan.target.expiring and not found and scan.unloaded == 0 then
                    table.remove(entry.anchors, index)
                    if type(entry.base) == "table" and entry.base.key == candidate.key then entry.base = nil end
                    BaseHeat.metrics.expired = BaseHeat.metrics.expired + 1
                    BaseHeat.anchorsChanged()
                    return nil
                end
                break
            end
        end
    end
    if scan.target.expiring then return anchor end
    if anchor ~= nil then
        if found then
            anchor.evidence = true
            BaseHeat.grow(anchor, BaseHeat.regionOf(scan))
            BaseHeat.anchorsChanged()
        end
        BaseHeat.noteEvidence(anchor, parts, hours)
        return anchor
    end
    local fresh = BaseHeat.freshBoards(entry, scan, hours)
    local why
    if parts.playerBarricades >= settings.promoteBarricades and fresh then
        why = "barricades"
    elseif parts.builds >= settings.promoteBuilds then why = "builds"
    elseif parts.generators > 0 then why = "generator" end
    if why ~= nil then
        local promoted = BaseHeat.promote(entry, BaseHeat.regionOf(scan), why, hours, true)
        BaseHeat.noteEvidence(promoted, parts, hours)
        return promoted
    end
    if found then BaseHeat.hint(entry, BaseHeat.regionOf(scan), hours) end
    return nil
end

function BaseHeat.freshBoards(entry, scan, hours)
    local row = type(entry.presence) == "table" and entry.presence[scan.target.key] or nil
    if type(row) ~= "table" then return false end
    local boards, day = scan.parts.playerBarricades, math.floor(hours / 24)
    local before, firstDay = tonumber(row.boards), tonumber(row.boardsDay)
    row.boards = boards
    if before == nil or firstDay == nil then
        row.boardsDay = day
        return false
    end
    return boards > before or day ~= firstDay
end

function BaseHeat.evidenceStep(key, entry, place, row, hours)
    local scan = BaseHeat.evidenceScans[key]
    if scan == nil then
        local target = BaseHeat.evidenceTarget(entry, place, row, hours)
        if target == nil then return 0 end
        scan = BaseHeat.newEvidenceScan(target)
        BaseHeat.evidenceScans[key] = scan
    end
    local width = scan.x2 - scan.x1 + 1
    local total = width * (scan.y2 - scan.y1 + 1)
    local processed = 0
    while processed < BaseHeat.settings.scanBudget and scan.cursor < total do
        local at = scan.cursor
        BaseHeat.evidenceSquare(scan, scan.x1 + (at % width), scan.y1 + math.floor(at / width), scan.z)
        scan.cursor = at + 1
        processed = processed + 1
    end
    BaseHeat.metrics.squares = BaseHeat.metrics.squares + processed
    if scan.cursor >= total then
        BaseHeat.evidenceScans[key] = nil
        BaseHeat.finishEvidence(entry, scan, hours)
    end
    return processed
end

local function scanPlayer(player, hours)
    local key = playerKey(player)
    local values = store()
    local entry = values.players[key]
    if type(entry) ~= "table" then entry = {}; values.players[key] = entry end
    BaseHeat.migrate(entry, hours)
    local place, row = BaseHeat.notePlayer(player, entry, hours)
    local processed = BaseHeat.heatStep(key, entry, hours)
    if processed == 0 then processed = BaseHeat.evidenceStep(key, entry, place, row, hours) end
    if processed == 0 then processed = BaseHeat.yardStep(entry, hours) end
    if processed > 0 then BaseHeat.metrics.players = BaseHeat.metrics.players + 1 end
    return processed
end

local function players()
    if type(BaseHeat.adapters.players) == "function" then
        return BaseHeat.adapters.players()
    end
    local result = {}
    pcall(function()
        local online = getOnlinePlayers and getOnlinePlayers() or nil
        if online ~= nil then
            for index = 0, online:size() - 1 do result[#result + 1] = online:get(index) end
        end
    end)
    if #result == 0 then
        pcall(function()
            local solo = getSpecificPlayer and getSpecificPlayer(0) or nil
            if solo ~= nil then result[1] = solo end
        end)
    end
    return result
end

function BaseHeat.occupancyLedger()
    local values = store()
    if type(values.occupied) ~= "table" then values.occupied = {} end
    return values.occupied
end

function BaseHeat.occupancyListed(record, hours)
    if type(record) ~= "table" then return false end
    if record.inside == true then return true end
    return record.dwelt == true and hours - (tonumber(record.lastHour) or -1e9) <= BaseHeat.settings.occupancy.hours
end

function BaseHeat.occupancyPrune(ledger, hours)
    local count, oldestId, oldestHour = 0, nil, math.huge
    for id, record in pairs(ledger) do
        if not BaseHeat.occupancyListed(record, hours) then
            ledger[id] = nil
        else
            count = count + 1
            local last = tonumber(record.lastHour) or 0
            if record.inside ~= true and last < oldestHour then oldestId, oldestHour = id, last end
        end
    end
    if count > BaseHeat.settings.occupancy.limit and oldestId ~= nil then ledger[oldestId] = nil end
    return count
end

function BaseHeat.occupancyStep(roster)
    local settings = BaseHeat.settings.occupancy
    if settings.on ~= true or type(roster) ~= "table" then return 0 end
    local now = BaseHeat.nowMs()
    local last = BaseHeat.occupancyAtMs
    if last ~= nil and now >= last and now - last < settings.everyMs then return 0 end
    BaseHeat.occupancyAtMs = now
    local hours, ledger = worldHours(), BaseHeat.occupancyLedger()
    for _, record in pairs(ledger) do record.inside = nil end
    local touched = 0
    for _, player in ipairs(roster) do
        local alive = true
        if type(player) == "table" or type(player) == "userdata" then
            if player.isDead ~= nil and player:isDead() == true then alive = false end
        end
        local building = alive and currentBuilding(player) or nil
        local bounds = building ~= nil and buildingBounds(building) or nil
        local owner = playerKey(player)
        if bounds == nil then
            BaseHeat.occupancySince[owner] = nil
        else
            local bkey = baseKey(bounds)
            local id = bkey .. "|" .. owner
            local record = ledger[id]
            if record == nil then
                record = { key = bkey, owner = owner, x1 = bounds.x1, y1 = bounds.y1, x2 = bounds.x2, y2 = bounds.y2,
                    firstHour = hours, inside = true, lastHour = hours }
                ledger[id] = record
                dirty()
            end
            local since = BaseHeat.occupancySince[owner]
            if type(since) ~= "table" or since.key ~= bkey then
                since = { key = bkey, atMs = now }
                BaseHeat.occupancySince[owner] = since
            end
            if record.dwelt ~= true and now - since.atMs >= settings.dwellMs then record.dwelt = true end
            record.inside, record.lastHour = true, hours
            touched = touched + 1
        end
    end
    BaseHeat.occupancyPrune(ledger, hours)
    BaseHeat.metrics.occupied = touched
    return touched
end

function BaseHeat.occupiedBases()
    local result, hours = {}, worldHours()
    local ids = {}
    for id, record in pairs(BaseHeat.occupancyLedger()) do
        if BaseHeat.occupancyListed(record, hours) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local ledger = BaseHeat.occupancyLedger()
    for index = 1, #ids do
        local record = ledger[ids[index]]
        local x1, y1, x2, y2 = tonumber(record.x1), tonumber(record.y1), tonumber(record.x2), tonumber(record.y2)
        if x1 ~= nil and y1 ~= nil and x2 ~= nil and y2 ~= nil then
            result[#result + 1] = { key = record.key, x1 = x1, y1 = y1, x2 = x2, y2 = y2, z = 0,
                x = (x1 + x2) / 2, y = (y1 + y2) / 2, owner = tostring(record.owner), flagged = false,
                occupied = true, inside = record.inside == true }
        end
    end
    return result
end

function BaseHeat.homes()
    local result = BaseHeat.bases()
    local occupied = BaseHeat.occupiedBases()
    for index = 1, #occupied do result[#result + 1] = occupied[index] end
    return result
end

function BaseHeat.tick()
    if type(isClient) == "function" and isClient() then return 0 end
    local roster = players()
    if #roster == 0 then return 0 end
    BaseHeat.occupancyStep(roster)
    BaseHeat.cursor = (BaseHeat.cursor % #roster) + 1
    local player = roster[BaseHeat.cursor]
    return scanPlayer(player, worldHours())
end

function BaseHeat.nowMs()
    if type(BaseHeat.adapters.nowMs) == "function" then return tonumber(BaseHeat.adapters.nowMs()) or 0 end
    if type(getTimestampMs) == "function" then return tonumber(getTimestampMs()) or 0 end
    return 0
end

function BaseHeat.target(player)
    if player == nil then return nil end
    local x, y, z = 0, 0, 0
    local ok = pcall(function() x, y, z = player:getX(), player:getY(), player:getZ() end)
    if not ok then return nil end
    local entry = store().players[playerKey(player)]
    local result = BaseHeat.targetRecord(entry, x, y, worldHours())
    if not result.anchor then result.z = z end
    return result
end

function BaseHeat.markRaid(player, suppliedHours)
    if player == nil then return false end
    local values = store()
    local key = playerKey(player)
    local entry = values.players[key]
    if type(entry) ~= "table" then entry = {}; values.players[key] = entry end
    entry.lastRaidHour = tonumber(suppliedHours) or worldHours()
    BaseHeat.metrics.raids = BaseHeat.metrics.raids + 1
    dirty()
    return true
end

function BaseHeat.flagScore(anchor)
    local flag = BaseHeat.settings.flag
    local parts = {
        math.min(flag.nightsCap, (tonumber(anchor.nights) or 0) * flag.night),
        math.min(flag.daysCap, (tonumber(anchor.days) or 0) * flag.day),
        math.min(flag.buildsCap, (tonumber(anchor.builds) or 0) * flag.build),
        math.min(flag.boardsCap, (tonumber(anchor.boards) or 0) * flag.board),
        (tonumber(anchor.generators) or 0) > 0 and flag.generator or 0,
        anchor.claimed == true and flag.claim or 0,
    }
    local score, kinds = 0, 0
    for index = 1, #parts do
        if parts[index] > 0 then score, kinds = score + parts[index], kinds + 1 end
    end
    return score, kinds
end

function BaseHeat.reflag(anchor, hours)
    if type(anchor) ~= "table" or anchor.flagged == true then return false end
    local flag = BaseHeat.settings.flag
    local score, kinds = BaseHeat.flagScore(anchor)
    if score < flag.threshold or kinds < flag.minFactors then return false end
    anchor.flagged, anchor.flaggedHour = true, hours
    BaseHeat.metrics.flagged = BaseHeat.metrics.flagged + 1
    BaseHeat.anchorsChanged()
    return true
end

function BaseHeat.noteDays(anchor, row, hours)
    local days = BaseHeat.dwellDays(row)
    if days > (tonumber(anchor.days) or 0) then anchor.days = days end
    return BaseHeat.reflag(anchor, hours)
end

function BaseHeat.noteEvidence(anchor, parts, hours)
    if type(anchor) ~= "table" then return false end
    local boards = tonumber(parts.playerBarricades) or 0
    if tonumber(anchor.boardsBase) == nil then anchor.boardsBase = boards end
    anchor.boards = math.max(0, boards - anchor.boardsBase)
    anchor.builds, anchor.generators = tonumber(parts.builds) or 0, tonumber(parts.generators) or 0
    return BaseHeat.reflag(anchor, hours)
end

function BaseHeat.flagActive()
    if type(BaseHeat.adapters.round2) == "boolean" then return BaseHeat.adapters.round2 end
    local flag = BaseHeat.settings.flag
    if flag.on ~= true then return false end
    if not (type(isServer) == "function" and isServer() == true) then return true end
    local now = BaseHeat.nowMs()
    local cache = BaseHeat.flagCache
    if cache ~= nil and now >= cache.atMs and now - cache.atMs < flag.cacheMs then return cache.value end
    local value = flag.dedicated == true
    local director = ProjectALife.SafehouseDirector
    if not value and director ~= nil and type(director.worldKind) == "function" then
        local ok, kind = pcall(director.worldKind)
        value = ok and kind == "coop"
    end
    BaseHeat.flagCache = { atMs = now, value = value }
    return value
end

function BaseHeat.flagConfigure(values)
    if type(values) ~= "table" then return false end
    local flag = BaseHeat.settings.flag
    if type(values.baseFlag) == "boolean" then flag.on = values.baseFlag end
    if type(values.dedicated) == "boolean" then flag.dedicated = values.dedicated end
    if tonumber(values.baseScore) ~= nil then flag.threshold = tonumber(values.baseScore) end
    BaseHeat.flagCache = nil
    return true
end

function BaseHeat.isFlagged(anchor)
    return anchor.flagged == true or anchor.why == "legacy"
end

function BaseHeat.yardSeed(anchor)
    local spawn = ProjectALife.SpawnPolicy
    local z = math.floor(tonumber(anchor.z) or 0)
    local mx, my = math.floor((anchor.x1 + anchor.x2) / 2), math.floor((anchor.y1 + anchor.y2) / 2)
    for _, point in ipairs({ { mx, anchor.y2 + 1 }, { mx, anchor.y1 - 1 }, { anchor.x1 - 1, my }, { anchor.x2 + 1, my } }) do
        local square = spawn.squareXY(point[1], point[2], z)
        if square ~= nil and spawn.floodable(square) and square.isOutside ~= nil and square:isOutside() == true then
            return point[1], point[2], z
        end
    end
    return nil
end

function BaseHeat.yardStep(entry, hours)
    local spawn, flag = ProjectALife.SpawnPolicy, BaseHeat.settings.flag
    if BaseHeat.flagActive() ~= true or spawn == nil or type(spawn.flood) ~= "function"
            or type(spawn.squareXY) ~= "function" or type(spawn.floodable) ~= "function" then return 0 end
    for _, anchor in ipairs(type(entry.anchors) == "table" and entry.anchors or {}) do
        if type(anchor) == "table" and anchor.flagged == true and hours >= (tonumber(anchor.yardAt) or -1e9) + flag.yardEveryHours then
            anchor.yardAt = hours
            local x, y, z = BaseHeat.yardSeed(anchor)
            if x ~= nil then
                local reach = flag.yardReach
                local box = { x1 = anchor.x1 - reach, y1 = anchor.y1 - reach, x2 = anchor.x2 + reach, y2 = anchor.y2 + reach }
                local facts = {}
                local result = spawn.flood(x, y, z, box, flag.yardBudget, nil, facts)
                if result == "exhausted" and type(facts.qx) == "table" then
                    local yard = { x1 = anchor.x1, y1 = anchor.y1, x2 = anchor.x2, y2 = anchor.y2 }
                    for index = 1, facts.count do
                        local qx, qy = facts.qx[index], facts.qy[index]
                        yard.x1, yard.y1 = math.min(yard.x1, qx), math.min(yard.y1, qy)
                        yard.x2, yard.y2 = math.max(yard.x2, qx), math.max(yard.y2, qy)
                    end
                    anchor.yard = yard
                    BaseHeat.anchorsChanged()
                elseif anchor.yard ~= nil and result ~= "budget" then
                    anchor.yard = nil
                    BaseHeat.anchorsChanged()
                end
            end
            return 1
        end
    end
    return 0
end

function BaseHeat.listed(anchor, owner, legacy)
    local x1, y1, x2, y2 = anchor.x1, anchor.y1, anchor.x2, anchor.y2
    local yard = type(anchor.yard) == "table" and anchor.yard or nil
    if yard ~= nil then
        x1, y1 = math.min(x1, tonumber(yard.x1) or x1), math.min(y1, tonumber(yard.y1) or y1)
        x2, y2 = math.max(x2, tonumber(yard.x2) or x2), math.max(y2, tonumber(yard.y2) or y2)
    end
    legacy = legacy == true or anchor.why == "legacy"
    local cx1, cy1 = tonumber(anchor.cx1) or x1, tonumber(anchor.cy1) or y1
    local cx2, cy2 = tonumber(anchor.cx2) or x2, tonumber(anchor.cy2) or y2
    return { key = anchor.key, x1 = x1, y1 = y1, x2 = x2, y2 = y2, z = anchor.z or 0,
        x = tonumber(anchor.x) or (cx1 + cx2) / 2, y = tonumber(anchor.y) or (cy1 + cy2) / 2,
        owner = tostring(owner), flagged = legacy or anchor.flagged == true, legacy = legacy,
        nights = tonumber(anchor.nights) or 0, days = tonumber(anchor.days) or 0, why = anchor.why,
        generators = tonumber(anchor.generators) or 0 }
end

function BaseHeat.collect(strict)
    local result = {}
    for key, entry in pairs(store().players) do
        if type(entry) == "table" then
            local listed
            for _, anchor in ipairs(type(entry.anchors) == "table" and entry.anchors or {}) do
                if type(anchor) == "table" and tonumber(anchor.x1) ~= nil
                        and (strict ~= true or BaseHeat.isFlagged(anchor)) then
                    result[#result + 1] = BaseHeat.listed(anchor, key)
                    if type(entry.base) == "table" and entry.base.key == anchor.key then listed = true end
                end
            end
            local base = entry.base
            local legacy = type(entry.anchors) ~= "table"
            if (strict ~= true or legacy) and not listed and type(base) == "table" and tonumber(base.x1) ~= nil then
                result[#result + 1] = BaseHeat.listed(base, key, legacy)
            end
        end
    end
    return result
end

function BaseHeat.bases()
    return BaseHeat.collect(BaseHeat.flagActive())
end

function BaseHeat.keyOf(player)
    if player == nil then return nil end
    return playerKey(player)
end

function BaseHeat.zones()
    local result = BaseHeat.collect(false)
    for _, entry in pairs(store().players) do
        if type(entry) == "table" and type(entry.hints) == "table" then
            for _, hint in ipairs(entry.hints) do
                if type(hint) == "table" and tonumber(hint.x1) ~= nil then result[#result + 1] = hint end
            end
        end
    end
    return result
end

function BaseHeat.clientBases()
    local transport = ProjectALife.MirrorTransport
    if transport == nil or type(transport.clientBases) ~= "function" then return {} end
    local ok, bases = pcall(transport.clientBases)
    if not ok or type(bases) ~= "table" then return {} end
    return bases
end

function BaseHeat.anchorOverlaps(x1, y1, x2, y2)
    local box = { x1 = tonumber(x1), y1 = tonumber(y1), x2 = tonumber(x2), y2 = tonumber(y2) }
    if box.x1 == nil or box.y1 == nil or box.x2 == nil or box.y2 == nil then return false end
    local homes
    if type(isClient) == "function" and isClient() == true then
        homes = BaseHeat.clientBases()
    else
        homes = BaseHeat.bases()
    end
    local margin = BaseHeat.settings.flag.homeMargin
    for _, base in ipairs(homes) do
        if BaseHeat.overlaps(base, box, margin) then return true end
    end
    return false
end

return BaseHeat
