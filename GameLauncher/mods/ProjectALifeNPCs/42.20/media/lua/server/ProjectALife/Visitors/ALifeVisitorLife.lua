require "ProjectALife/Visitors/ALifeVisitorSchema"
require "ProjectALife/Visitors/ALifeVisitorPeople"
require "ProjectALife/Visitors/ALifeVisitorInstance"

ProjectALife = ProjectALife or {}

local Schema = ProjectALife.VisitorSchema
local People = ProjectALife.VisitorPeople
local Instance = ProjectALife.VisitorInstance

local Life = {
    adapters = {},
    caches = setmetatable({}, { __mode = "k" }),
    jobs = setmetatable({}, { __mode = "k" }),
    claims = {},
    state = {},
    memo = {},
    nextAtMs = 0,
    cursor = 0,
    scanCursor = 0,
    settings = {
        sliceSquares = 32, clockEvery = 8, budgetMs = 2, rescanHours = 1 / 6, passMs = 500,
        stepMinMs = 4000, stepSpreadMs = 4000, settleMs = 10000, walkGiveUpMs = 90000, holdGiveUpMs = 25000,
        badMs = 300000, maxVisitors = 6, perHouse = 3, maxPois = 240, maxRooms = 48, followGap = 4,
        privacyTiles = 3, residentRange = 14, tvReach = 5, witnessRange = 12, claimSlackHours = 0.05,
        leaveLeadHours = 0.07, switchMinHours = 0.05, stuckMs = 90000, stuckMove = 0.35, nearPlayer = 2,
        awayHours = 0.4, stareMs = 6000, routineBonus = 6, lieDown = false,
    },
    metrics = { scans = 0, scanSteps = 0, scanMs = 0, rooms = 0, pois = 0, decisions = 0, intents = 0, refused = 0,
        finished = 0, stuck = 0, washed = 0, claimsDenied = 0, speech = 0, lastWhy = "-", plain = 0, kicks = 0,
        stairs = 0, farewells = 0, stareCut = 0, kinds = {} },
}
ProjectALife.VisitorLife = Life

Life.ROOMS = { bathroom = true, bedroom = true, livingroom = true, kitchen = true, hall = true, closet = true,
    diningroom = true, laundry = true, kidsbedroom = true, office = true }

Life.INTENTS = {
    stand = { act = "stand", pois = {}, dwell = { 1, 3 }, gap = 0, ms = { 7000, 15000 } },
    walk = { act = "walk", pois = { "room" }, dwell = { 1, 2 }, gap = 0.02, ms = { 5000, 12000 } },
    follow = { act = "approach", pois = { "player" }, dwell = { 5, 15 }, gap = 0.1 },
    sit = { act = "sit", pois = { "seat" }, dwell = { 5, 30 }, gap = 0.1 },
    read = { act = "read", pois = { "seat", "shelf" }, dwell = { 10, 40 }, gap = 0.3 },
    look = { act = "look", pois = { "window_view" }, dwell = { 2, 10 }, gap = 0.2, ms = { 30000, 90000 } },
    tv = { act = "tv", pois = { "tv" }, dwell = { 5, 20 }, gap = 0.3 },
    radio = { act = "tv", pois = { "radio" }, dwell = { 5, 15 }, gap = 0.3 },
    wash = { act = "wash", pois = { "sink" }, dwell = { 3, 4 }, gap = 0.5 },
    bath = { act = "wash", pois = { "bath" }, dwell = { 4, 6 }, gap = 3, adult = true },
    bathroom = { act = "privacy", pois = { "room" }, dwell = { 1, 2 }, gap = 0.6, room = "bathroom" },
    rest = { act = "rest", pois = { "seat", "bed" }, dwell = { 30, 120 }, gap = 1 },
    warm = { act = "warm", pois = { "stove" }, dwell = { 5, 15 }, gap = 0.3, ms = { 20000, 60000 } },
    change = { act = "change", pois = { "room" }, dwell = { 1, 1.5 }, gap = 6, adult = true, option = "changeClothes" },
    drink = { act = "stand", pois = { "counter" }, dwell = { 1, 3 }, gap = 0.3, ms = { 10000, 25000 } },
    eat = { act = "stand", pois = { "counter" }, dwell = { 1, 3 }, gap = 0.6, ms = { 20000, 50000 } },
    floor = { act = "walk", pois = { "room" }, dwell = { 1, 3 }, gap = 0.2, ms = { 7000, 15000 } },
    pace = { act = "walk", pois = { "room" }, dwell = { 1, 2 }, gap = 0.1, ms = { 5000, 12000 } },
    farewell = { act = "approach", pois = { "exit" }, dwell = { 1, 3 }, gap = 0 },
    cook = { act = "stand", pois = { "stove" }, dwell = { 1, 2 }, gap = 0.25, ms = { 20000, 60000 } },
    warm_can = { act = "stand", pois = { "stove" }, dwell = { 1, 2 }, gap = 0.5, ms = { 25000, 50000 } },
    make_coffee = { act = "stand", pois = { "coffee", "counter" }, dwell = { 1, 2 }, gap = 0.5, ms = { 20000, 45000 } },
    check_fridge = { act = "stand", pois = { "fridge" }, dwell = { 1, 2 }, gap = 0.3, ms = { 8000, 20000 } },
    rinse_cup = { act = "stand", pois = { "sink" }, dwell = { 1, 2 }, gap = 0.3, ms = { 10000, 20000 } },
    tidy = { act = "stand", pois = { "counter", "shelf" }, dwell = { 1, 2 }, gap = 0.6, ms = { 12000, 30000 } },
    around = { act = "look", pois = {}, dwell = { 1, 2 }, gap = 0.1, ms = { 6000, 12000 } },
}
Life.KIND_ORDER = { "stand", "walk", "follow", "sit", "read", "look", "tv", "radio", "wash", "bath", "bathroom", "rest",
    "warm", "change", "drink", "eat", "floor", "pace", "farewell", "cook", "warm_can", "make_coffee", "check_fridge",
    "rinse_cup", "tidy", "around" }
Life.PLAIN_REFUSED = { change = true, bath = true }
Life.SEATED = { sit = true, rest = true, tv = true, read = true }
Life.IDLERS = { stand = true, walk = true, pace = true, floor = true }
Life.KITCHEN = { cook = true, warm_can = true, make_coffee = true, check_fridge = true, rinse_cup = true, eat = true,
    drink = true, tidy = true }
Life.AFTER = { check_fridge = { cook = 4, warm_can = 3, make_coffee = 2 }, cook = { eat = 5, wash = 6 },
    warm_can = { eat = 3, sit = 3, wash = 4 }, make_coffee = { sit = 4, rinse_cup = 5 }, eat = { wash = 6, rinse_cup = 3 },
    drink = { rinse_cup = 3 }, bathroom = { wash = 7 } }
Life.WORDS = { stove = "cook", oven = "cook", cook = "cook", cooks = "cook", cooking = "cook", kitchen = "cook", pot = "cook",
    fridge = "check_fridge", pantry = "check_fridge", coffee = "make_coffee", tea = "make_coffee", kettle = "make_coffee",
    counter = "tidy", tidies = "tidy", dishes = "rinse_cup", cup = "rinse_cup", sink = "wash", wash = "wash", washes = "wash",
    shower = "wash", bathroom = "bathroom", toilet = "bathroom", couch = "sit", sofa = "sit", chair = "sit", table = "sit",
    bench = "sit", sits = "sit", sitting = "sit", shelf = "read", shelves = "read", book = "read", books = "read",
    reads = "read", reading = "read", window = "look", windows = "look", tv = "tv", television = "tv", radio = "radio",
    stairs = "floor", upstairs = "floor", downstairs = "floor", door = "pace", paces = "pace", pacing = "pace", pace = "pace",
    bed = "rest", sleeps = "rest", sleep = "rest", eats = "eat", eat = "eat", breakfast = "eat", lunch = "eat", dinner = "eat",
    fire = "warm", fireplace = "warm", warms = "warm" }
Life.FAREWELLS = { "Thanks for the roof, I mean it", "I'll get my things, thank you again", "Appreciate it, really, take care",
    "Thank you for putting me up, stay safe out there", "I won't forget this, thank you" }

Life.byName = { Sink = "sink", Bath = "bath", Shower = "bath", Toilet = "toilet", Shelves = "shelf", Shelf = "shelf",
    ["Magazine Shelf"] = "shelf", Fridge = "fridge", Freezer = "fridge", Mirror = "mirror", Oven = "stove", Fireplace = "stove",
    Deluxe = "coffee",
    Television = "tv", Radio = "radio", Counter = "counter", Bed = "bed", Beds = "bed", Mattress = "bed" }
Life.vector = { N = { 0, -1 }, S = { 0, 1 }, E = { 1, 0 }, W = { -1, 0 } }

function Life.nowMs()
    if type(Life.adapters.nowMs) == "function" then return Life.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return nil
end

function Life.rand(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 1 then return 0 end
    if type(Life.adapters.rand) == "function" then return math.floor(tonumber(Life.adapters.rand(n)) or 0) end
    if type(ZombRand) == "function" then return math.floor(tonumber(ZombRand(n)) or 0) end
    return 0
end

function Life.hours()
    if type(Life.adapters.hours) == "function" then return tonumber(Life.adapters.hours()) or 0 end
    local visitors = ProjectALife.VisitorDirector
    if visitors ~= nil and type(visitors.hours) == "function" then return tonumber(visitors.hours()) or 0 end
    return 0
end

function Life.hourOfDay()
    if type(Life.adapters.hour) == "function" then return tonumber(Life.adapters.hour()) end
    local visitors = ProjectALife.VisitorDirector
    if visitors ~= nil and type(visitors.hourOfDay) == "function" then return visitors.hourOfDay() end
    return nil
end

function Life.options()
    if type(Life.adapters.options) == "function" then return Life.adapters.options() end
    local visitors = ProjectALife.VisitorDirector
    if visitors ~= nil and type(visitors.options) == "function" then return visitors.options() end
    return Schema.options(nil)
end

function Life.ask(object, name, ...)
    if object == nil then return nil end
    local method = object[name]
    if type(method) ~= "function" then return nil end
    return method(object, ...)
end

function Life.isA(object, className)
    return type(instanceof) == "function" and instanceof(object, className) == true
end

function Life.squareAt(x, y, z)
    if type(Life.adapters.squareAt) == "function" then return Life.adapters.squareAt(x, y, z) end
    if type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return nil end
    return cell:getGridSquare(x, y, z)
end

function Life.keyOf(kind, x, y, z)
    return kind .. ":" .. math.floor(x) .. ":" .. math.floor(y) .. ":" .. math.floor(z)
end

function Life.prop(props, key)
    if props == nil or type(props.has) ~= "function" or props:has(key) ~= true then return nil end
    if type(props.get) ~= "function" then return nil end
    return props:get(key)
end

function Life.flag(props, name)
    if props == nil or type(props.has) ~= "function" or IsoFlagType == nil or IsoFlagType[name] == nil then return false end
    return props:has(IsoFlagType[name]) == true
end

function Life.spriteName(object)
    local sprite = Life.ask(object, "getSprite")
    if sprite == nil then return nil end
    local name = Life.ask(sprite, "getName")
    if type(name) ~= "string" then return nil end
    return name
end

function Life.build(object)
    local props = Life.ask(object, "getProperties")
    local row = { kind = false, facing = false, sub = false, piped = false }
    local custom = Life.prop(props, "CustomName")
    local seats = ProjectALife.SeatApi
    local facing = nil
    if seats ~= nil and type(seats.objectFacing) == "function" then facing = seats.objectFacing(object) end
    if facing ~= nil then
        row.kind, row.facing, row.sub = "seat", facing, (type(custom) == "string" and custom or "seat")
        return row
    end
    local kind = type(custom) == "string" and Life.byName[custom] or nil
    if kind == nil and custom == nil then
        local sprite = Life.spriteName(object)
        if sprite ~= nil and string.sub(sprite, 1, 28) == "appliances_refrigeration_01_" then kind = "fridge" end
    end
    if kind == nil then return row end
    row.piped = Life.flag(props, "waterPiped")
    if kind == "coffee" and Life.prop(props, "GroupName") ~= "Espresso" then return row end
    if kind == "bed" then
        if not Life.flag(props, "bed") then return row end
        row.facing = Life.prop(props, "Facing") or false
        row.sub = Life.prop(props, "BedType") or false
    elseif kind == "sink" or kind == "bath" then
        if not row.piped then return row end
    end
    row.kind = kind
    return row
end

function Life.describe(object)
    local name = Life.spriteName(object)
    if name == nil then return nil end
    local row = Life.memo[name]
    if row == nil then
        row = Life.build(object)
        Life.memo[name] = row
    end
    return row, name
end

function Life.poiOf(kind, square, name, idx, room, facing, sub)
    local x, y, z = square:getX(), square:getY(), square:getZ()
    return { kind = kind, x = x, y = y, z = z, facing = facing or nil, room = room, key = Life.keyOf(kind, x, y, z),
        sprite = name, idx = idx, sub = sub or nil }
end

function Life.addPoi(job, poi)
    if poi == nil or job.seen[poi.key] or job.count >= Life.settings.maxPois then return false end
    job.seen[poi.key] = true
    job.count = job.count + 1
    local room = job.room
    room.pois[#room.pois + 1] = poi
    return true
end

function Life.windowFacing(object, square, indoor)
    local north = Life.ask(object, "getNorth") == true
    local own = indoor == square or (indoor:getX() == square:getX() and indoor:getY() == square:getY())
    local dx, dy
    if north then
        dx, dy = 0, own and -1 or 1
    else
        dx, dy = own and -1 or 1, 0
    end
    if dy == -1 then return "N", dx, dy end
    if dy == 1 then return "S", dx, dy end
    if dx == 1 then return "E", dx, dy end
    return "W", dx, dy
end

function Life.scanWindow(job, object, square, name, idx)
    local indoor = Life.ask(object, "getIndoorSquare")
    if indoor == nil or Life.ask(object, "isExterior") == false or Life.ask(object, "isBarricaded") == true then return end
    local facing, dx, dy = Life.windowFacing(object, square, indoor)
    local outer = Life.squareAt(indoor:getX() + dx, indoor:getY() + dy, indoor:getZ())
    if outer == nil or Life.ask(outer, "isOutside") ~= true then return end
    Life.addPoi(job, Life.poiOf("window_view", indoor, name, idx, job.room.name, facing))
end

function Life.scanDoor(job, object, square, name, idx)
    if Life.ask(object, "isExterior") == true then return end
    local policy = ProjectALife.DoorPolicy
    if policy ~= nil and type(policy.blockKind) == "function" and policy.blockKind(object, nil) ~= nil then
        job.room.locked = true
    end
    local room = job.room
    if room.door == nil then
        room.door = { x = square:getX(), y = square:getY(), z = square:getZ(),
            north = Life.ask(object, "getNorth") == true, idx = idx, sprite = name }
    end
end

function Life.scanObject(job, square, object, idx)
    local row, name = Life.describe(object)
    if row == nil then return end
    local room = job.room.name
    if row.kind ~= false then
        local facing = row.facing or nil
        Life.addPoi(job, Life.poiOf(row.kind, square, name, idx, room, facing, row.sub))
        return
    end
    if type(object.getDeviceData) == "function" then
        if Life.isA(object, "IsoTelevision") then
            Life.addPoi(job, Life.poiOf("tv", square, name, idx, room))
        elseif Life.isA(object, "IsoRadio") then
            Life.addPoi(job, Life.poiOf("radio", square, name, idx, room))
        end
    elseif type(object.getIndoorSquare) == "function" and Life.isA(object, "IsoWindow") then
        Life.scanWindow(job, object, square, name, idx)
    elseif type(object.IsOpen) == "function" and type(object.isLocked) == "function" and Life.isA(object, "IsoDoor") then
        Life.scanDoor(job, object, square, name, idx)
    end
end

function Life.scanSquare(job)
    local room = job.room
    local square = room.list:get(room.cursor)
    room.cursor = room.cursor + 1
    if square ~= nil then
        room.n = room.n + 1
        room.sx, room.sy = room.sx + square:getX(), room.sy + square:getY()
        if #room.free < 40 and (type(square.isFree) ~= "function" or square:isFree(false) == true) then
            room.free[#room.free + 1] = square
        end
        job.sq[square:getX() .. "," .. square:getY() .. "," .. square:getZ()] = job.roomIndex
        local objects = Life.ask(square, "getObjects")
        if objects ~= nil and type(objects.size) == "function" then
            for index = 0, objects:size() - 1 do Life.scanObject(job, square, objects:get(index), index) end
        end
    end
    if room.cursor >= room.size then job.stage = "close" end
end

function Life.closeRoom(job)
    local room = job.room
    job.rooms[job.roomIndex] = { name = room.name, z = room.z, n = room.n, locked = room.locked, door = room.door,
        cx = room.n > 0 and room.sx / room.n or nil, cy = room.n > 0 and room.sy / room.n or nil }
    if room.locked then
        job.lockedRooms = job.lockedRooms + 1
    else
        for position = 1, #room.pois do job.pois[#job.pois + 1] = room.pois[position] end
        if room.n > 0 and #room.free > 0 then
            local best, bestDistance = nil, math.huge
            for position = 1, #room.free do
                local candidate = room.free[position]
                local dx, dy = candidate:getX() - room.sx / room.n, candidate:getY() - room.sy / room.n
                if dx * dx + dy * dy < bestDistance then best, bestDistance = candidate, dx * dx + dy * dy end
            end
            local poi = Life.poiOf("room", best, nil, nil, room.name)
            poi.n = room.n
            job.pois[#job.pois + 1] = poi
        end
        if room.door ~= nil then
            local square = Life.squareAt(room.door.x, room.door.y, room.door.z)
            if square ~= nil then
                local poi = Life.poiOf("door", square, room.door.sprite, room.door.idx, room.name, room.door.north and "N" or "W")
                job.pois[#job.pois + 1] = poi
            end
        end
    end
    job.room = nil
    job.stage = "room"
end

function Life.openRoom(job)
    local definition = table.remove(job.queue, 1)
    if definition == nil then
        job.stage = "done"
        return
    end
    local iso = Life.ask(definition, "getIsoRoom")
    local list = iso ~= nil and Life.ask(iso, "getSquares") or nil
    if list == nil or type(list.size) ~= "function" or list:size() == 0 then
        job.unloaded = job.unloaded + 1
        return
    end
    job.roomIndex = job.roomIndex + 1
    job.room = { name = tostring(Life.ask(definition, "getName") or "room"), z = tonumber(Life.ask(definition, "getZ")) or 0,
        list = list, size = list:size(), cursor = 0, n = 0, sx = 0, sy = 0, free = {}, pois = {}, locked = false }
    job.stage = "squares"
end

function Life.initJob(job)
    local buildings
    if type(Life.adapters.buildings) == "function" then
        buildings = Life.adapters.buildings(job.house)
    else
        local doors = ProjectALife.SafehouseDoor
        local found = doors ~= nil and type(doors.buildingOf) == "function" and doors.buildingOf(job.house) or nil
        buildings = found ~= nil and { found } or {}
    end
    for _, building in ipairs(type(buildings) == "table" and buildings or {}) do
        local definition = Life.ask(building, "getDef")
        local rooms = definition ~= nil and Life.ask(definition, "getRooms") or nil
        if rooms ~= nil and type(rooms.size) == "function" then
            for index = 0, rooms:size() - 1 do
                local room = rooms:get(index)
                local name = room ~= nil and Life.ask(room, "getName") or nil
                if Life.ROOMS[name] == true and Life.ask(room, "isEmptyOutside") ~= true
                        and #job.queue < Life.settings.maxRooms then
                    job.queue[#job.queue + 1] = room
                end
            end
        end
    end
    if #job.queue == 0 then job.why = "no_rooms" end
    job.stage = "room"
end

function Life.advance(job)
    local stage = job.stage
    if stage == "init" then return Life.initJob(job) end
    if stage == "room" then return Life.openRoom(job) end
    if stage == "squares" then return Life.scanSquare(job) end
    if stage == "close" then return Life.closeRoom(job) end
    job.done = true
end

function Life.index(job)
    local cache = { done = true, list = job.pois, rooms = job.rooms, sq = job.sq, by = {}, byKey = {}, why = job.why,
        locked = job.lockedRooms, unloaded = job.unloaded }
    for position = 1, #job.pois do
        local poi = job.pois[position]
        local bucket = cache.by[poi.kind]
        if bucket == nil then
            bucket = {}
            cache.by[poi.kind] = bucket
        end
        bucket[#bucket + 1] = poi
        cache.byKey[poi.key] = poi
    end
    return cache
end

function Life.newJob(house)
    return { house = house, stage = "init", queue = {}, pois = {}, rooms = {}, sq = {}, seen = {}, count = 0,
        roomIndex = 0, lockedRooms = 0, unloaded = 0, done = false }
end

function Life.stale(cache, hours)
    return cache == nil or cache.done ~= true or hours - (tonumber(cache.atHours) or -math.huge) >= Life.settings.rescanHours
end

function Life.warm()
    for _, key in ipairs({ "washDone", "washDoneBath", "washNoWater" }) do
        if Schema.POOLS[key] ~= nil and type(People.pool) == "function" then People.pool(Schema.POOLS[key]) end
    end
end

function Life.scan(house, budgetMs)
    if type(house) ~= "table" then return true, nil end
    local hours = Life.hours()
    local cache = Life.caches[house]
    if not Life.stale(cache, hours) then return true, cache.list end
    local job = Life.jobs[house]
    if job == nil then
        job = Life.newJob(house)
        Life.jobs[house] = job
        Life.warm()
    end
    local settings = Life.settings
    local started = Life.nowMs()
    local steps = 0
    budgetMs = tonumber(budgetMs) or settings.budgetMs
    while not job.done and steps < settings.sliceSquares do
        Life.advance(job)
        steps = steps + 1
        if steps % settings.clockEvery == 0 then
            local now = Life.nowMs()
            if started ~= nil and now ~= nil and now - started >= budgetMs then break end
        end
    end
    local finished = Life.nowMs()
    Life.metrics.scanSteps = Life.metrics.scanSteps + steps
    if started ~= nil and finished ~= nil then Life.metrics.scanMs = Life.metrics.scanMs + (finished - started) end
    if not job.done then return false, cache ~= nil and cache.list or nil end
    cache = Life.index(job)
    cache.atHours = hours
    Life.caches[house] = cache
    Life.jobs[house] = nil
    Life.metrics.scans = Life.metrics.scans + 1
    Life.metrics.rooms = #cache.rooms
    Life.metrics.pois = #cache.list
    return true, cache.list
end

function Life.pois(house)
    local cache = type(house) == "table" and Life.caches[house] or nil
    if cache == nil or cache.done ~= true then return nil end
    return cache.list
end

function Life.cacheOf(house)
    return type(house) == "table" and Life.caches[house] or nil
end

function Life.invalidate(house)
    if type(house) == "table" then
        Life.caches[house] = nil
        Life.jobs[house] = nil
    end
end

function Life.houseOf(record)
    local memory = type(record) == "table" and record.memory or nil
    local guest = type(memory) == "table" and memory.guest or nil
    local director = ProjectALife.SafehouseDirector
    if type(guest) ~= "table" or director == nil or type(director.store) ~= "function" then return nil end
    return director.store().houses[guest.house]
end

Life.kindAliases = { window = "window_view", seat = "seat", sink = "sink", bath = "bath", tv = "tv", radio = "radio",
    bed = "bed", toilet = "toilet", shelf = "shelf", stove = "stove", fridge = "fridge", mirror = "mirror",
    counter = "counter", coffee = "coffee", room = "room", door = "door", window_view = "window_view" }

function Life.hasPoi(record, kind)
    local house = Life.houseOf(record)
    local cache = house ~= nil and Life.caches[house] or nil
    if cache == nil or cache.done ~= true or type(kind) ~= "string" then return false end
    local alias = Life.kindAliases[kind]
    if alias ~= nil then return cache.by[alias] ~= nil end
    for position = 1, #cache.rooms do
        if cache.rooms[position].name == kind and not cache.rooms[position].locked then return true end
    end
    return false
end

function Life.objectOf(poi)
    if type(poi) ~= "table" or poi.sprite == nil then return nil end
    local square = Life.squareAt(poi.x, poi.y, poi.z)
    local objects = square ~= nil and Life.ask(square, "getObjects") or nil
    if objects == nil or type(objects.size) ~= "function" then return nil end
    local direct = poi.idx ~= nil and objects:size() > poi.idx and objects:get(poi.idx) or nil
    if direct ~= nil and Life.spriteName(direct) == poi.sprite then return direct end
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if Life.spriteName(object) == poi.sprite then return object end
    end
    return nil
end

function Life.deviceOn(poi)
    local object = Life.objectOf(poi)
    local data = object ~= nil and Life.ask(object, "getDeviceData") or nil
    return data ~= nil and Life.ask(data, "getIsTurnedOn") == true
end

function Life.stoveLit(poi)
    local object = Life.objectOf(poi)
    if object == nil then return false end
    if type(object.Activated) == "function" then return object:Activated() == true end
    if type(object.isLit) == "function" then return object:isLit() == true end
    return true
end

function Life.person(record)
    local memory = type(record) == "table" and record.memory or nil
    return type(memory) == "table" and type(memory.person) == "table" and memory.person or nil
end

function Life.guestStamp(record)
    local memory = type(record) == "table" and record.memory or nil
    local guest = type(memory) == "table" and memory.guest or nil
    if type(guest) ~= "table" or record.lifecycle ~= "active" then return nil end
    return guest
end

function Life.hashOf(text)
    local hash = 7
    text = tostring(text)
    for position = 1, #text do hash = (hash * 31 + string.byte(text, position)) % 2147483629 end
    return hash
end

function Life.seedPick(seed, salt, low, high)
    return low + (math.floor(seed / (salt * 7 + 3)) + salt * 11) % (high - low + 1)
end

function Life.persona(v, mem)
    if mem.persona ~= nil then return mem.persona end
    local seed = Life.hashOf(tostring(v.uid) .. "|" .. tostring(v.pending ~= nil and v.pending.id or "-"))
    local visit = ProjectALife.SafehouseVisit
    local shell = visit ~= nil and type(visit.shell) == "function" and visit.shell(v.uid) or nil
    local female = nil
    if shell ~= nil and type(shell.isFemale) == "function" then female = shell:isFemale() == true end
    mem.persona = { plain = true, ad = 1, seed = seed, female = female, reads = Life.seedPick(seed, 5, 0, 2) > 0,
        t = { social = Life.seedPick(seed, 1, 1, 5), anx = Life.seedPick(seed, 2, 1, 4), curious = Life.seedPick(seed, 3, 1, 5),
            tidy = Life.seedPick(seed, 4, 2, 5) } }
    return mem.persona
end

function Life.plainNeeds(persona, v, mem, hours, hour)
    local since = tonumber(v.pending ~= nil and v.pending.insideAt) or tonumber(mem.firstHours) or hours
    local inside = math.max(0, hours - since)
    local night = hour ~= nil and (hour >= 22 or hour < 6)
    local fed = math.max(0, hours - math.max(since, tonumber(mem.ateAt) or since))
    local drank = math.max(0, hours - math.max(since, tonumber(mem.drankAt) or since))
    local washed = tonumber(mem.washedAt)
    local event = v.pending ~= nil and v.pending.event or nil
    local hurt = event == "wounded" or event == "medical_visit"
    return { hunger = math.min(5, math.floor(fed * 0.8) + persona.seed % 2), thirst = math.min(5, math.floor(drank * 1.2) + 1),
        fatigue = math.min(5, math.floor(inside / 2.5) + (night and 3 or 0)),
        cold = (hour ~= nil and (hour >= 19 or hour < 8)) and 3 or 0, fear = 0,
        dirty = ((washed ~= nil and hours - washed < 6) or hurt) and 0 or 4, sick = 0, pain = hurt and 3 or 0 }
end

function Life.position(record)
    local at = type(record) == "table" and record.worldPosition or nil
    if type(at) ~= "table" or tonumber(at.x) == nil or tonumber(at.y) == nil then return nil end
    return { x = at.x, y = at.y, z = tonumber(at.z) or 0 }
end

function Life.residents(house)
    local list = {}
    local director = ProjectALife.SafehouseDirector
    local visit = ProjectALife.SafehouseVisit
    if director == nil or type(director.onlineResidents) ~= "function" then return list end
    for _, player in ipairs(director.onlineResidents(house)) do
        local at = nil
        if visit ~= nil and type(visit.position) == "function" then at = visit.position(player) end
        if at ~= nil then list[#list + 1] = { x = at.x, y = at.y, z = at.z, player = player } end
    end
    return list
end

function Life.nearest(list, x, y, z)
    local best, bestDistance = nil, math.huge
    for position = 1, #list do
        local row = list[position]
        local dx, dy = row.x - x, row.y - y
        local distance = dx * dx + dy * dy + (math.abs((row.z or 0) - (z or 0)) > 0.5 and 400 or 0)
        if distance < bestDistance then best, bestDistance = row, distance end
    end
    return best, bestDistance
end

function Life.stateOf(uid, nowMs)
    local row = Life.state[uid]
    if row == nil then
        row = { firstMs = nowMs, firstHours = Life.hours(), nextMs = nowMs, bad = {}, cd = {}, seq = nil, last = nil,
            switchHours = nil, plainSeen = nil }
        Life.state[uid] = row
    end
    return row
end

function Life.claimOwner(key, hours)
    local claim = Life.claims[key]
    if claim == nil then return nil end
    if hours >= claim.untilHours + Life.settings.claimSlackHours then
        Life.claims[key] = nil
        return nil
    end
    return claim.uid
end

function Life.claim(key, uid, untilHours, hours)
    local owner = Life.claimOwner(key, hours)
    if owner ~= nil and owner ~= uid then
        Life.metrics.claimsDenied = Life.metrics.claimsDenied + 1
        return false
    end
    Life.claims[key] = { uid = uid, untilHours = untilHours }
    return true
end

function Life.release(uid)
    for key, claim in pairs(Life.claims) do
        if claim.uid == uid then Life.claims[key] = nil end
    end
end

function Life.clean(poi)
    if type(poi) ~= "table" then return nil end
    return { kind = poi.kind, x = poi.x, y = poi.y, z = poi.z, facing = poi.facing, room = poi.room, key = poi.key,
        sprite = poi.sprite, idx = poi.idx, sub = poi.sub }
end

function Life.dwellHours(def)
    local low, high = def.dwell[1], def.dwell[2]
    local span = math.max(0, math.floor((high - low) * 10))
    return (low + Life.rand(span + 1) / 10) / 60
end

function Life.intent(uid, kind, poi, untilHours, act)
    local def = Life.INTENTS[kind]
    local registry = ProjectALife.ActorRegistry
    if def == nil then return false, "kind_invalid" end
    if registry == nil or type(registry.peek) ~= "function" then return false, "registry_unavailable" end
    local record = registry.peek(uid)
    local person = Life.person(record)
    if record == nil or record.lifecycle ~= "active" then return false, "not_a_visitor" end
    if person == nil then
        if Life.guestStamp(record) == nil or Life.options().guestLife == false then return false, "not_a_visitor" end
        if Life.PLAIN_REFUSED[kind] then
            Life.metrics.refused = Life.metrics.refused + 1
            return false, "plain_refused"
        end
    end
    if def.adult == true and person ~= nil and person.ad ~= 1 then
        Life.metrics.refused = Life.metrics.refused + 1
        return false, "adult_only"
    end
    if def.option ~= nil and Life.options()[def.option] == false then return false, "option_off" end
    if #def.pois > 0 and type(poi) ~= "table" then return false, "poi_required" end
    if type(poi) == "table" and (tonumber(poi.x) == nil or tonumber(poi.y) == nil or type(poi.key) ~= "string") then
        return false, "poi_invalid"
    end
    local hours = Life.hours()
    local dwell = Life.dwellHours(def)
    local finish = tonumber(untilHours) or (hours + dwell + 0.04)
    if type(poi) == "table" and poi.kind ~= "player" and poi.kind ~= "room" and poi.kind ~= "window_view"
            and poi.kind ~= "exit" and not Life.claim(poi.key, uid, finish, hours) then
        return false, "poi_claimed"
    end
    local old = type(record.memory.life) == "table" and record.memory.life or nil
    local mem = Life.state[uid]
    local seq = math.max(old ~= nil and tonumber(old.seq) or 0, mem ~= nil and mem.counter or 0) + 1
    local row = { k = kind, poi = Life.clean(poi), seq = seq, at = hours, untilHours = finish, dwell = dwell,
        act = type(act) == "table" and act or nil }
    local ok, why = Instance.write(uid, function(memory)
        memory.life = row
        if type(memory.person) == "table" then memory.person.act = def.act end
    end)
    if not ok then
        Life.release(uid)
        Life.metrics.lastWhy = tostring(why)
        return false, why
    end
    if mem ~= nil then
        mem.prev = mem.last
        mem.seq, mem.counter, mem.arrived, mem.holdMs, mem.startMs, mem.last = seq, seq, nil, nil, Life.nowMs(), kind
        mem.switchHours, mem.why, mem.dwellMs, mem.nextBonus = hours, mem.pickWhy, nil, nil
        if kind == "floor" then Life.metrics.stairs = Life.metrics.stairs + 1 end
        if kind == "farewell" then Life.metrics.farewells = Life.metrics.farewells + 1 end
        if kind == "walk" or kind == "floor" then mem.wander = nil end
    end
    local kinds = Life.metrics.kinds
    kinds[kind] = (kinds[kind] or 0) + 1
    Life.metrics.intents = Life.metrics.intents + 1
    return true
end

function Life.clear(uid)
    local ok = Instance.write(uid, function(memory)
        memory.life = nil
        if type(memory.person) == "table" then memory.person.act = "stand" end
    end)
    Life.release(uid)
    return ok
end

function Life.eligible(record, pending)
    if type(record) ~= "table" or record.lifecycle ~= "active" then return false end
    local memory = record.memory
    if type(memory) ~= "table" or type(memory.guest) ~= "table" then return false end
    if type(memory.person) ~= "table" and Life.options().guestLife == false then return false end
    return memory.guest.pendingId == pending.id
end

function Life.owns(record)
    local guest = Life.guestStamp(record)
    local director = ProjectALife.SafehouseDirector
    if guest == nil or director == nil or type(director.store) ~= "function" then return false end
    if Life.options().life == false then return false end
    if type(record.memory.person) ~= "table" and Life.options().guestLife == false then return false end
    local house = director.store().houses[guest.house]
    for _, pending in ipairs(house ~= nil and type(house.pending) == "table" and house.pending or {}) do
        if pending.id == guest.pendingId then return pending.state == "inside" and pending.resolved ~= true end
    end
    return false
end

function Life.visitors()
    local list = {}
    local director = ProjectALife.SafehouseDirector
    local registry = ProjectALife.ActorRegistry
    if director == nil or registry == nil or type(director.store) ~= "function" or type(registry.peek) ~= "function" then
        return list
    end
    for _, house in pairs(director.store().houses or {}) do
        local inHouse = 0
        for _, pending in ipairs(type(house.pending) == "table" and house.pending or {}) do
            if pending.lane == "visit" and pending.resolved ~= true and pending.state == "inside" then
                for _, uid in ipairs(type(pending.uids) == "table" and pending.uids or {}) do
                    local record = registry.peek(uid)
                    if inHouse < Life.settings.perHouse and Life.eligible(record, pending) then
                        inHouse = inHouse + 1
                        list[#list + 1] = { uid = uid, record = record, house = house, pending = pending }
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.uid < b.uid end)
    while #list > Life.settings.maxVisitors do table.remove(list) end
    return list
end

function Life.busy(record)
    local activity, intent = record.activity, record.intent
    if activity == "combat" then return true end
    if type(intent) == "string" and (intent == "flee" or intent == "avoid_zombies" or intent == "retreat") then return true end
    return false
end

function Life.floors(ctx)
    local floors = { [math.floor(ctx.here.z)] = true }
    if ctx.resident ~= nil then floors[math.floor(ctx.resident.z or 0)] = true end
    return floors
end

function Life.usable(ctx, poi)
    if type(poi) ~= "table" then return false end
    if not ctx.floors[math.floor(poi.z)] then return false end
    if (ctx.mem.bad[poi.key] or 0) > ctx.nowMs then return false end
    local owner = Life.claimOwner(poi.key, ctx.hours)
    if owner ~= nil and owner ~= ctx.uid then return false end
    if ctx.busy ~= nil and poi.kind ~= "player" then
        local room = ctx.cache.sq[math.floor(poi.x) .. "," .. math.floor(poi.y) .. "," .. math.floor(poi.z)]
        if room ~= nil and ctx.busy[room] then return false end
    end
    return true
end

Life.PRIVATE = { bathroom = true, bedroom = true, kidsbedroom = true }

function Life.busyRooms(ctx)
    local busy, any = {}, false
    for _, resident in ipairs(ctx.residents) do
        local room = ctx.cache.sq[math.floor(resident.x) .. "," .. math.floor(resident.y) .. "," .. math.floor(resident.z)]
        local row = room ~= nil and ctx.cache.rooms[room] or nil
        if row ~= nil and Life.PRIVATE[row.name] then
            busy[room], any = true, true
        end
    end
    if any then return busy end
    return nil
end

function Life.otherFloors(ctx)
    local floors, here, any = {}, math.floor(ctx.here.z), false
    for _, row in ipairs(ctx.cache.rooms) do
        local z = math.floor(tonumber(row.z) or 0)
        if z ~= here and math.abs(z - here) <= 1 and not row.locked then floors[z], any = true, true end
    end
    return floors, any
end

function Life.rank(ctx, list, near)
    local rows = {}
    for position = 1, #list do
        local poi = list[position]
        if Life.usable(ctx, poi) then
            local distance = 0
            if ctx.resident ~= nil then
                local dx, dy = poi.x - ctx.resident.x, poi.y - ctx.resident.y
                distance = dx * dx + dy * dy
            end
            rows[#rows + 1] = { poi = poi, distance = distance }
        end
    end
    if #rows == 0 then return nil end
    table.sort(rows, function(a, b)
        if a.distance ~= b.distance then
            if near then return a.distance < b.distance end
            return a.distance > b.distance
        end
        return a.poi.key < b.poi.key
    end)
    local span = math.min(3, #rows)
    return rows[1 + Life.rand(span)].poi
end

function Life.nearSeat(ctx, tv)
    local best, bestScore = nil, -math.huge
    for _, poi in ipairs(ctx.index.seat or {}) do
        if Life.usable(ctx, poi) then
            local dx, dy = tv.x - poi.x, tv.y - poi.y
            local distance = math.sqrt(dx * dx + dy * dy)
            local vector = Life.vector[poi.facing or ""]
            local dot = 0
            if vector ~= nil and distance > 0 then dot = (vector[1] * dx + vector[2] * dy) / distance end
            if distance <= Life.settings.tvReach and dot > 0.2 and distance - dot * 2 < -bestScore then
                best, bestScore = poi, -(distance - dot * 2)
            end
        end
    end
    return best
end

Life.PACE = { { 3, 0 }, { -3, 0 }, { 0, 3 }, { 0, -3 }, { 2, 2 }, { -2, -2 }, { 2, -2 }, { -2, 2 } }

function Life.pickPace(ctx)
    local x, y, z = math.floor(ctx.here.x), math.floor(ctx.here.y), math.floor(ctx.here.z)
    local room = ctx.cache.sq[x .. "," .. y .. "," .. z]
    if room == nil then return false end
    local start = Life.rand(#Life.PACE)
    for offset = 1, #Life.PACE do
        local step = Life.PACE[(start + offset - 1) % #Life.PACE + 1]
        local sx, sy = x + step[1], y + step[2]
        if ctx.cache.sq[sx .. "," .. sy .. "," .. z] == room and (ctx.busy == nil or not ctx.busy[room]) then
            local square = Life.squareAt(sx, sy, z)
            if square ~= nil and (type(square.isFree) ~= "function" or square:isFree(false) == true) then
                return true, { kind = "room", x = sx, y = sy, z = z, room = ctx.cache.rooms[room].name,
                    key = "pace:" .. sx .. ":" .. sy .. ":" .. z }
            end
        end
    end
    return false
end

function Life.exitSpot(house)
    local visit = ProjectALife.SafehouseVisit
    local door = type(house) == "table" and type(house.door) == "table" and house.door or nil
    if door == nil or tonumber(door.ix) == nil or tonumber(door.iy) == nil then return nil end
    if visit ~= nil and type(visit.guestSpot) == "function" then
        local spot = visit.guestSpot(house)
        if type(spot) == "table" and tonumber(spot.x) ~= nil and tonumber(spot.y) ~= nil then
            return { x = math.floor(spot.x), y = math.floor(spot.y), z = tonumber(spot.z) or tonumber(door.z) or 0 }
        end
    end
    return { x = math.floor(door.ix), y = math.floor(door.iy), z = tonumber(door.z) or 0 }
end

function Life.pickExit(ctx)
    local spot = Life.exitSpot(ctx.house)
    if spot == nil then return false end
    return true, { kind = "exit", x = spot.x, y = spot.y, z = spot.z, room = "door", key = "exit" }
end

function Life.pickFloor(ctx)
    local pool = {}
    for _, poi in ipairs(ctx.index.room or {}) do
        pool[#pool + 1] = poi
    end
    local alt = setmetatable({ floors = Life.otherFloors(ctx) }, { __index = ctx })
    local poi = Life.rank(alt, pool, ctx.social)
    if poi == nil then return false end
    return true, poi
end

function Life.bedFree(ctx, poi)
    local beds = ctx.pending ~= nil and ctx.house ~= nil and ctx.house.playerBeds or nil
    if type(beds) == "table" and beds[poi.key] ~= nil then return false end
    for _, resident in ipairs(ctx.residents) do
        local dx, dy = resident.x - poi.x, resident.y - poi.y
        if dx * dx + dy * dy <= 16 and math.abs((resident.z or 0) - poi.z) < 1.5 then return false end
    end
    return true
end

function Life.pickPoi(ctx, kind)
    local def = Life.INTENTS[kind]
    if #def.pois == 0 then return true, nil end
    local near = ctx.social
    if kind == "floor" then return Life.pickFloor(ctx) end
    if kind == "pace" then return Life.pickPace(ctx) end
    if kind == "farewell" then return Life.pickExit(ctx) end
    if kind == "follow" then
        if ctx.resident == nil then return false end
        return true, { kind = "player", x = ctx.resident.x, y = ctx.resident.y, z = ctx.resident.z, key = "player" }
    end
    if kind == "tv" then
        local lit = {}
        for _, set in ipairs(ctx.index.tv or {}) do
            if Life.deviceOn(set) then lit[#lit + 1] = set end
        end
        local tv = Life.rank(ctx, lit, true)
        if tv == nil then return false end
        local seat = Life.nearSeat(ctx, tv)
        if seat ~= nil then return true, seat end
        return true, tv
    end
    local pool = {}
    for _, source in ipairs(def.pois) do
        for _, poi in ipairs(ctx.index[source] or {}) do
            local fits = true
            if def.room ~= nil and poi.room ~= def.room then fits = false end
            if kind == "rest" and poi.kind == "seat" and poi.sub ~= "Couch" then fits = false end
            if kind == "rest" and poi.kind == "bed" and (not ctx.bedPose or not Life.bedFree(ctx, poi)) then fits = false end
            if kind == "read" and poi.kind == "shelf" and Life.rand(4) > 0 then fits = false end
            if kind == "warm" and not Life.stoveLit(poi) then fits = false end
            if kind == "radio" and not Life.deviceOn(poi) then fits = false end
            if kind == "walk" and (poi.x - ctx.here.x) ^ 2 + (poi.y - ctx.here.y) ^ 2 < 9 then fits = false end
            if kind == "walk" and ctx.hereRoom ~= nil
                    and ctx.cache.sq[math.floor(poi.x) .. "," .. math.floor(poi.y) .. "," .. math.floor(poi.z)] == ctx.hereRoom then
                fits = false
            end
            if fits then pool[#pool + 1] = poi end
        end
    end
    if kind == "walk" and #pool == 0 then
        for _, poi in ipairs(ctx.index.room or {}) do
            if (poi.x - ctx.here.x) ^ 2 + (poi.y - ctx.here.y) ^ 2 >= 9 then pool[#pool + 1] = poi end
        end
    end
    if kind == "make_coffee" then
        local coffee = {}
        for _, poi in ipairs(pool) do
            if poi.kind == "coffee" then coffee[#coffee + 1] = poi end
        end
        if #coffee > 0 then pool = coffee end
    end
    if kind == "rest" then
        local couches = {}
        for _, poi in ipairs(pool) do
            if poi.kind == "seat" and Life.usable(ctx, poi) then couches[#couches + 1] = poi end
        end
        if #couches > 0 then pool = couches end
    end
    local poi = Life.rank(ctx, pool, near)
    if poi == nil then return false end
    return true, poi
end

function Life.bonus(ctx, kind)
    local extra = 0
    if ctx.routine ~= nil and ctx.routine[kind] == true then extra = extra + Life.settings.routineBonus end
    local after = ctx.mem.nextBonus
    if type(after) == "table" and after[kind] ~= nil then extra = extra + after[kind] end
    if kind == "walk" and ctx.mem.wander == true then extra = extra + 5 end
    return extra
end

function Life.addRow(ctx, rows, kind, weight)
    weight = weight + Life.bonus(ctx, kind)
    if weight <= 0 then return end
    local def = Life.INTENTS[kind]
    if def.adult == true and not ctx.adult then return end
    if def.option ~= nil and ctx.options[def.option] == false then return end
    if ctx.mem.cd[kind] ~= nil and ctx.mem.cd[kind] > ctx.hours then return end
    if kind == ctx.last then return end
    if kind == ctx.prev then weight = math.max(1, math.floor(weight / 3)) end
    if #def.pois > 0 then
        local any = kind == "follow" and ctx.resident ~= nil
        for _, source in ipairs(def.pois) do
            if source ~= "player" and ctx.index[source] ~= nil then any = true end
        end
        if not any then return end
    end
    rows[#rows + 1] = { kind = kind, weight = weight }
    ctx.total = ctx.total + weight
end

function Life.hourIn(hour, from, to)
    if hour == nil or from == nil or to == nil then return false end
    if from <= to then return hour >= from and hour <= to end
    return hour >= from or hour <= to
end

function Life.routineKinds(card, hour)
    local list = card ~= nil and card.routines or nil
    if type(list) ~= "table" or hour == nil then return nil end
    local found = nil
    local now = math.floor(hour)
    for position = 1, #list do
        local row = list[position]
        if Life.hourIn(now, row.from, row.to) then
            for _, text in ipairs({ row.where or "", row.does or "" }) do
                text = string.lower(text)
                local cursor = 1
                while cursor <= #text do
                    local first, last = string.find(text, "%a+", cursor)
                    if first == nil then break end
                    local kind = Life.WORDS[string.sub(text, first, last)]
                    if kind ~= nil then
                        found = found or {}
                        found[kind] = true
                    end
                    cursor = last + 1
                end
            end
        end
    end
    return found
end

function Life.weights(ctx)
    local rows = {}
    local need, t = ctx.need, ctx.t
    local hr = ctx.hour ~= nil and math.floor(ctx.hour) or nil
    local evening = hr ~= nil and hr >= 18 and hr < 23
    local morning = hr ~= nil and hr >= 5 and hr < 10
    local meal = hr ~= nil and ((hr >= 6 and hr < 9) or (hr >= 11 and hr < 14) or (hr >= 17 and hr < 21))
    local night = ctx.night
    local mem = ctx.mem
    Life.addRow(ctx, rows, "stand", 1)
    Life.addRow(ctx, rows, "walk", 3 + (t.curious >= 3 and 2 or 0))
    local follow = 0
    if t.social >= 3 then follow = follow + 4 end
    if t.anx >= 3 or need.fear >= 3 then follow = follow + 3 end
    Life.addRow(ctx, rows, "follow", follow)
    local sit = 4
    if need.fatigue >= 3 then sit = sit + 3 end
    if need.pain + need.sick >= 3 then sit = sit + 2 end
    if evening then sit = sit + 1 end
    Life.addRow(ctx, rows, "sit", sit)
    local read = 0
    if ctx.options.books ~= false and ctx.card ~= nil and ctx.card.books ~= nil
            and (ctx.card.books.current ~= nil or #ctx.card.books.taste > 0) then
        read = 3 + (evening and 2 or 0) + (t.social <= 2 and 1 or 0)
    end
    if ctx.plain and ctx.options.books ~= false and ctx.person.reads then read = 2 + (evening and 2 or 0) end
    Life.addRow(ctx, rows, "read", read)
    Life.addRow(ctx, rows, "look", 2 + (need.fear >= 3 and 3 or 0) + (night and 1 or 0) + (t.anx >= 3 and 1 or 0) + (morning and 1 or 0))
    local hooks = ctx.card ~= nil and ctx.card.hooks or {}
    Life.addRow(ctx, rows, "tv", (hooks.tv ~= nil and 4 or 2) + (evening and 1 or 0))
    Life.addRow(ctx, rows, "radio", hooks.radio ~= nil and 3 or 1)
    local wash = 0
    if need.dirty >= 4 then wash = 5 + (t.tidy >= 3 and 3 or 0) end
    local washedAt = tonumber(mem.washedAt)
    local sleepy = hr ~= nil and (hr >= 20 or hr < 2) and need.fatigue >= 2
    if sleepy and (washedAt == nil or ctx.hours - washedAt > 4) then wash = math.max(wash, 6) end
    if mem.wantWash == true then wash = math.max(wash, 8) end
    Life.addRow(ctx, rows, "wash", wash)
    local bathAt = tonumber(mem.bathAt)
    Life.addRow(ctx, rows, "bathroom", 1 + (need.thirst >= 2 and 1 or 0) + ((bathAt == nil or ctx.hours - bathAt > 1.5) and 1 or 0))
    local rest = 0
    if (night and need.fatigue >= 3) or need.fatigue >= 5 then rest = 5 end
    if ctx.plain and night and ctx.pending ~= nil and ctx.pending.event == "sleep_one_night" and hr ~= nil
            and (hr >= 23 or hr < 6) then
        rest = 16
    end
    Life.addRow(ctx, rows, "rest", rest)
    Life.addRow(ctx, rows, "warm", need.cold >= 3 and 6 or 0)
    Life.addRow(ctx, rows, "drink", (need.thirst >= 3 or need.hunger >= 3) and 3 or 1)
    Life.addRow(ctx, rows, "eat", need.hunger >= 3 and 4 or ((meal and need.hunger >= 2) and 2 or 0))
    local cook = 0
    if not night or need.hunger >= 4 then cook = 1 + (meal and 3 or 0) + (need.hunger >= 2 and 3 or 0) end
    Life.addRow(ctx, rows, "cook", cook)
    Life.addRow(ctx, rows, "warm_can", night and (need.hunger >= 3 and 3 or 0) or ((need.hunger >= 3 and 4 or 1) + (need.cold >= 3 and 2 or 0)))
    Life.addRow(ctx, rows, "make_coffee", night and 0 or ((morning and 5 or 1) + (t.social <= 2 and 1 or 0)))
    Life.addRow(ctx, rows, "check_fridge", 2 + (need.hunger >= 2 and 3 or 0) + (need.thirst >= 3 and 2 or 0) + (t.curious >= 3 and 1 or 0))
    Life.addRow(ctx, rows, "rinse_cup", mem.wantRinse == true and 6 or 1)
    Life.addRow(ctx, rows, "tidy", t.tidy >= 4 and 3 or 1)
    local apart = ctx.resident ~= nil and math.abs((ctx.resident.z or 0) - ctx.here.z) > 0.5 and t.social >= 3
    Life.addRow(ctx, rows, "floor", ctx.otherFloor and (2 + (t.curious >= 3 and 2 or 0) + (apart and 3 or 0)) or 0)
    Life.addRow(ctx, rows, "pace", 1 + (t.anx >= 3 and 2 or 0) + (need.fear >= 2 and 1 or 0))
    Life.addRow(ctx, rows, "around", 1 + (t.anx >= 3 and 2 or 0) + (t.curious >= 3 and 1 or 0))
    return rows
end

function Life.context(v, mem, nowMs, options, cache)
    local real = Life.person(v.record)
    local person = real or Life.persona(v, mem)
    local hour = Life.hourOfDay()
    local hours = Life.hours()
    local card = nil
    if real ~= nil and People ~= nil and type(People.card) == "function" then card = People.card(real.id) end
    local traits = {}
    for position = 1, #Schema.TRAITS do
        local axis = Schema.TRAITS[position]
        traits[axis] = card ~= nil and card.traits[axis] or (real == nil and person.t[axis]) or 2
    end
    local need = {}
    if real == nil then
        need = Life.plainNeeds(person, v, mem, hours, hour)
    else
        for position = 1, #Schema.NEEDS do
            local name = Schema.NEEDS[position].name
            need[name] = Instance.need(real, name)
        end
    end
    local here = Life.position(v.record) or { x = v.house.cx or 0, y = v.house.cy or 0, z = tonumber(v.house.z) or 0 }
    local residents = Life.residents(v.house)
    local resident = Life.nearest(residents, here.x, here.y, here.z)
    local life = v.record.memory.life
    local animations = ProjectALife.Animations
    local ctx = { uid = v.uid, record = v.record, person = person, plain = real == nil, card = card, t = traits, need = need,
        here = here, resident = resident, residents = residents, hour = hour, hours = hours, nowMs = nowMs, options = options,
        index = cache.by, cache = cache, mem = mem, adult = person.ad == 1, total = 0, pending = v.pending, house = v.house,
        night = hour ~= nil and (hour >= 22 or hour < 6),
        social = traits.social >= 3 or traits.anx >= 3 or mem.firstIntent ~= true,
        last = type(life) == "table" and life.k or mem.last, prev = mem.prev,
        routine = Life.routineKinds(card, hour),
        hereRoom = cache.sq[math.floor(here.x) .. "," .. math.floor(here.y) .. "," .. math.floor(here.z)],
        bedPose = Life.settings.lieDown == true and animations ~= nil and type(animations.supports) == "function" and animations.supports("bed_asleep") == true }
    ctx.floors = Life.floors(ctx)
    ctx.busy = Life.busyRooms(ctx)
    local _, other = Life.otherFloors(ctx)
    ctx.otherFloor = other
    return ctx
end

function Life.choose(ctx)
    local rows = Life.weights(ctx)
    local guard = 0
    while #rows > 0 and guard < 6 do
        guard = guard + 1
        local total = 0
        for position = 1, #rows do total = total + rows[position].weight end
        local roll = Life.rand(total)
        local picked = #rows
        for position = 1, #rows do
            roll = roll - rows[position].weight
            if roll < 0 then
                picked = position
                break
            end
        end
        local kind = rows[picked].kind
        local ok, poi = Life.pickPoi(ctx, kind)
        if ok then
            ctx.mem.pickWhy = kind .. " w=" .. rows[picked].weight .. "/" .. total .. " hour=" .. tostring(ctx.hour)
                .. " fat=" .. tostring(ctx.need.fatigue) .. " hun=" .. tostring(ctx.need.hunger)
            return kind, poi
        end
        table.remove(rows, picked)
    end
    ctx.mem.pickWhy = "fallback_stand"
    return "stand", nil
end

function Life.begin(v, mem, options, nowMs)
    local cache = Life.caches[v.house]
    if cache == nil or cache.done ~= true then
        Life.metrics.lastWhy = "scan_pending"
        return 0
    end
    local ctx = Life.context(v, mem, nowMs, options, cache)
    local kind, poi = Life.choose(ctx)
    local ok, why = Life.intent(v.uid, kind, poi, nil, nil)
    if not ok and kind ~= "stand" then ok, why = Life.intent(v.uid, "stand", nil, nil, nil) end
    mem.firstIntent = true
    Life.metrics.decisions = Life.metrics.decisions + 1
    if not ok then Life.metrics.lastWhy = tostring(why) end
    return 1
end

function Life.speak(uid, poolKey, record)
    local pool = Schema.POOLS[poolKey]
    local speech = ProjectALife.Speech
    local visit = ProjectALife.SafehouseVisit
    if pool == nil or speech == nil or type(speech.say) ~= "function" or visit == nil or type(visit.shell) ~= "function" then
        return false
    end
    local shell = visit.shell(uid)
    if shell == nil then return false end
    local line = People.pickLine(pool, { rand = Life.rand, seed = Life.rand(2147483647) })
    if type(line) ~= "string" then return false end
    return Life.say(uid, shell, line)
end

function Life.say(uid, shell, line)
    local speech = ProjectALife.Speech
    local visit = ProjectALife.SafehouseVisit
    if speech == nil or type(speech.say) ~= "function" or visit == nil then return false end
    local text = line
    if type(speech.render) == "function" then text = speech.render(line, {}, shell, nil) end
    if text == nil then return false end
    local said = speech.say(shell, text, { scope = "visitor", near = function(listener)
        return type(visit.nearUid) == "function" and visit.nearUid(uid, listener) == true
    end })
    if said then Life.metrics.speech = Life.metrics.speech + 1 end
    return said == true
end

function Life.thank(v, mem)
    if mem.thanked == true then return false end
    mem.thanked = true
    local visit = ProjectALife.SafehouseVisit
    local shell = visit ~= nil and type(visit.shell) == "function" and visit.shell(v.uid) or nil
    if shell == nil then return false end
    local seed = mem.persona ~= nil and mem.persona.seed or Life.hashOf(v.uid)
    return Life.say(v.uid, shell, Life.FAREWELLS[seed % #Life.FAREWELLS + 1])
end

function Life.witness(uid, house, record, id)
    local talk = ProjectALife.VisitorTalk
    local director = ProjectALife.SafehouseDirector
    if talk == nil or type(talk.witness) ~= "function" or director == nil then return 0 end
    local at = Life.position(record)
    if at == nil then return 0 end
    local seen = 0
    for _, resident in ipairs(Life.residents(house)) do
        local dx, dy = resident.x - at.x, resident.y - at.y
        local range = Life.settings.witnessRange
        if dx * dx + dy * dy <= range * range and math.abs(resident.z - at.z) < 1.5 then
            local key = director.playerKey(resident.player)
            if key ~= nil and talk.witness(uid, "wit", id, key) then seen = seen + 1 end
        end
    end
    return seen
end

function Life.markWashed(v, life, hours)
    local ok = Instance.write(v.uid, function(memory)
        if type(memory.person) == "table" then Instance.markWashed(memory.person, hours, 0) end
    end)
    if ok then Life.metrics.washed = Life.metrics.washed + 1 end
    return ok
end

function Life.privacyBroken(v, life)
    local cache = Life.caches[v.house]
    local poi = life.poi
    if cache == nil or type(poi) ~= "table" then return false end
    local room = cache.sq[math.floor(poi.x) .. "," .. math.floor(poi.y) .. "," .. math.floor(poi.z)]
    local door = room ~= nil and cache.rooms[room].door or nil
    for _, resident in ipairs(Life.residents(v.house)) do
        local square = math.floor(resident.x) .. "," .. math.floor(resident.y) .. "," .. math.floor(resident.z)
        if room ~= nil and cache.sq[square] == room then return true, resident end
        if door ~= nil and math.abs(resident.z - door.z) < 1.5 then
            local dx, dy = resident.x - (door.x + 0.5), resident.y - (door.y + 0.5)
            if dx * dx + dy * dy <= 4 then return true, resident end
        end
    end
    return false
end

function Life.startChange(v, mem, life)
    mem.changeStarted = life.seq
    local wardrobe = ProjectALife.VisitorWardrobe
    if wardrobe ~= nil and type(wardrobe.change) == "function" then
        local ok = wardrobe.change(v.uid, mem.change or {})
        if ok then return true end
    end
    Instance.write(v.uid, function(memory)
        if type(memory.person) == "table" then Instance.setDressState(memory.person, "changing") end
    end)
    mem.stateOwned = true
    return true
end

function Life.endChange(v, mem)
    if mem.stateOwned == true then
        Instance.write(v.uid, function(memory)
            if type(memory.person) == "table" then Instance.setDressState(memory.person, "dressed") end
        end)
    end
    mem.stateOwned, mem.changeStarted, mem.change = nil, nil, nil
end

function Life.beginChange(uid, spec)
    local registry = ProjectALife.ActorRegistry
    local record = registry ~= nil and registry.peek(uid) or nil
    local person = Life.person(record)
    if person == nil then return false, "not_a_visitor" end
    if person.ad ~= 1 then return false, "adult_only" end
    if Life.options().changeClothes == false then return false, "option_off" end
    local house = Life.houseOf(record)
    local cache = house ~= nil and Life.caches[house] or nil
    if cache == nil or cache.done ~= true then return false, "scan_pending" end
    local strict = Life.options().privacyStrict ~= false
    local residents = Life.residents(house)
    local best, bestScore = nil, -math.huge
    for _, poi in ipairs(cache.by.room or {}) do
        if poi.room == "bathroom" or poi.room == "bedroom" then
            local row = cache.rooms[cache.sq[math.floor(poi.x) .. "," .. math.floor(poi.y) .. "," .. math.floor(poi.z)] or 0]
            if row ~= nil and row.door ~= nil and not row.locked then
                local blocked = false
                for _, resident in ipairs(residents) do
                    local square = math.floor(resident.x) .. "," .. math.floor(resident.y) .. "," .. math.floor(resident.z)
                    local dx, dy = resident.x - (row.door.x + 0.5), resident.y - (row.door.y + 0.5)
                    local range = Life.settings.privacyTiles
                    if cache.sq[square] ~= nil and cache.rooms[cache.sq[square]] == row then blocked = true end
                    if strict and dx * dx + dy * dy <= range * range and math.abs(resident.z - row.door.z) < 1.5 then
                        blocked = true
                    end
                end
                local score = (poi.room == "bathroom" and 2 or 1) + (blocked and -10 or 0)
                if score > bestScore then best, bestScore = poi, score end
            end
        end
    end
    if best == nil or bestScore < 0 then return false, "no_private_room" end
    local ok, why = Life.intent(uid, "change", best, nil, nil)
    if not ok then return false, why end
    local mem = Life.stateOf(uid, Life.nowMs() or 0)
    mem.change = type(spec) == "table" and spec or {}
    return true
end

function Life.finish(v, mem, life, reason, hours, nowMs)
    local poi = type(life.poi) == "table" and life.poi or nil
    local def = Life.INTENTS[life.k]
    Life.release(v.uid)
    Life.metrics.finished = Life.metrics.finished + 1
    if reason == "stuck" or reason == "gone" or reason == "dry" then
        if poi ~= nil then mem.bad[poi.key] = nowMs + Life.settings.badMs end
        if reason ~= "dry" then Life.metrics.stuck = Life.metrics.stuck + 1 end
    end
    if reason == "washed" then
        Life.markWashed(v, life, hours)
        Life.witness(v.uid, v.house, v.record, "washed")
        Life.speak(v.uid, life.k == "bath" and "washDoneBath" or "washDone", v.record)
        mem.washedAt, mem.wantWash = hours, nil
    elseif reason == "dry" then
        Life.speak(v.uid, "washNoWater", v.record)
        mem.wantWash = nil
    end
    if reason ~= "stuck" and reason ~= "gone" then
        if life.k == "eat" or life.k == "warm_can" then mem.ateAt = hours end
        if life.k == "drink" or life.k == "eat" or life.k == "make_coffee" then mem.drankAt = hours end
        if life.k == "bathroom" then
            mem.wantWash, mem.bathAt = true, hours
        elseif life.k == "eat" or life.k == "cook" then
            mem.wantWash = true
        elseif life.k == "drink" or life.k == "make_coffee" then
            mem.wantRinse = true
        elseif life.k == "rinse_cup" then
            mem.wantRinse = nil
        end
        mem.nextBonus = Life.AFTER[life.k]
        mem.wander = Life.KITCHEN[life.k] == true and Life.rand(10) < 4 or nil
    end
    if reason == "stare" then Life.metrics.stareCut = Life.metrics.stareCut + 1 end
    if life.k == "farewell" and (reason == "stuck" or reason == "gone") then mem.noFarewell = true end
    if life.k == "change" then Life.endChange(v, mem) end
    if def ~= nil then mem.cd[life.k] = hours + def.gap end
    mem.last = life.k
end

function Life.follow(v, mem, life, nowMs)
    local poi = life.poi
    if type(poi) ~= "table" or poi.kind ~= "player" then return end
    local residents = Life.residents(v.house)
    local resident = Life.nearest(residents, poi.x, poi.y, poi.z)
    if resident == nil then return end
    local dx, dy = resident.x - poi.x, resident.y - poi.y
    local gap = Life.settings.followGap
    if dx * dx + dy * dy < gap * gap and math.abs(resident.z - poi.z) < 1 then return end
    Instance.write(v.uid, function(memory)
        if type(memory.life) == "table" and memory.life.seq == life.seq and type(memory.life.poi) == "table" then
            memory.life.poi.x, memory.life.poi.y, memory.life.poi.z = resident.x, resident.y, resident.z
        end
    end)
end

function Life.progress(v, mem, life, hours, nowMs)
    local record = v.record
    local intent = record.intent
    if mem.seq ~= life.seq then
        mem.seq, mem.startMs, mem.arrived, mem.holdMs, mem.dwellMs = life.seq, nowMs, nil, nil, nil
    end
    local def = Life.INTENTS[life.k]
    if intent == "visitor_gone" then return "gone" end
    if intent == "visitor_wash_done" then return "washed" end
    if intent == "visitor_wash_dry" then return "dry" end
    if life.k == "change" then
        local broken = Life.privacyBroken(v, life)
        if broken then return "caught" end
    end
    if intent == "visitor_hold" then
        mem.holdMs = mem.holdMs or nowMs
        if nowMs - mem.holdMs > Life.settings.holdGiveUpMs then return "stuck" end
    else
        mem.holdMs = nil
    end
    if intent == "visitor_" .. life.k and record.activity == "idle" then
        if mem.arrived == nil then
            mem.arrived = nowMs
            if life.k == "farewell" then Life.thank(v, mem) end
            if life.arr ~= 1 and life.k ~= "farewell" then
                local stamp = hours + (tonumber(life.dwell) or 0.05)
                if def ~= nil and def.ms ~= nil then
                    mem.dwellMs = def.ms[1] + Life.rand(def.ms[2] - def.ms[1] + 1)
                    stamp = hours + 0.5
                end
                Instance.write(v.uid, function(memory)
                    if type(memory.life) == "table" and memory.life.seq == life.seq then
                        memory.life.untilHours, memory.life.arr = stamp, 1
                    end
                end)
                life.untilHours = stamp
                local claim = type(life.poi) == "table" and Life.claims[life.poi.key] or nil
                if claim ~= nil and claim.uid == v.uid then claim.untilHours = stamp end
            end
            if life.k == "change" and mem.changeStarted ~= life.seq then Life.startChange(v, mem, life) end
        end
    elseif mem.arrived == nil and nowMs - (mem.startMs or nowMs) > Life.settings.walkGiveUpMs then
        return "stuck"
    end
    if def ~= nil and def.ms ~= nil and mem.arrived ~= nil and nowMs - mem.arrived >= (mem.dwellMs or def.ms[2]) then
        return "expired"
    end
    if hours >= (tonumber(life.untilHours) or 0) then
        if mem.arrived == nil and mem.holdMs ~= nil then return "stuck" end
        local capped = mem.switchHours ~= nil and hours - mem.switchHours < Life.settings.switchMinHours
        if capped and life.k ~= "farewell" and mem.arrived ~= nil then return "running" end
        return "expired"
    end
    if life.k == "follow" then Life.follow(v, mem, life, nowMs) end
    return "running"
end

Life.POSED = { sit = true, rest = true, tv = true, read = true, wash = true, bath = true, warm = true, eat = true,
    drink = true, look = true, bathroom = true, change = true, farewell = true, cook = true, warm_can = true,
    make_coffee = true, check_fridge = true, rinse_cup = true, tidy = true, around = true }

function Life.talking(record, nowMs)
    local memory = type(record) == "table" and record.memory or nil
    if type(memory) ~= "table" or memory.talkHoldPlayerKey == nil then return false end
    return (tonumber(memory.talkHoldUntilMs) or 0) > nowMs
end

function Life.staring(v, life, nowMs)
    if type(life) ~= "table" or Life.IDLERS[life.k] ~= true or Life.talking(v.record, nowMs) then return false end
    local module = ProjectALife.ModuleVisitorLife
    if module == nil or type(module.stareMs) ~= "function" then return false end
    local stare = module.stareMs(v.uid, nowMs)
    return stare ~= nil and stare >= Life.settings.stareMs
end

function Life.watch(v, mem, life, nowMs)
    local at = Life.position(v.record)
    if at == nil then return false end
    local last = mem.pos
    local moved = last == nil or math.abs(at.z - last.z) > 0.5
        or (at.x - last.x) ^ 2 + (at.y - last.y) ^ 2 > Life.settings.stuckMove ^ 2
    if moved then
        mem.pos = { x = at.x, y = at.y, z = at.z, ms = nowMs }
        return false
    end
    if nowMs - last.ms < Life.settings.stuckMs then return false end
    last.ms = nowMs
    if type(life) == "table" and Life.POSED[life.k] and mem.arrived ~= nil then return false end
    Life.metrics.kicks = Life.metrics.kicks + 1
    return true
end

function Life.leaveDue(v, hours)
    local untilHours = tonumber(v.pending ~= nil and v.pending.untilHours)
    return untilHours ~= nil and untilHours - hours <= Life.settings.leaveLeadHours
end

function Life.farewell(v, mem, nowMs)
    if mem.noFarewell == true then return false end
    local spot = Life.exitSpot(v.house)
    if spot == nil then return false end
    local poi = { kind = "exit", x = spot.x, y = spot.y, z = spot.z, room = "door", key = "exit" }
    mem.pickWhy = "leave_due"
    local ok = Life.intent(v.uid, "farewell", poi, tonumber(v.pending.untilHours), nil)
    return ok == true
end

function Life.advanceTo(v, mem, options, nowMs)
    v.record = ProjectALife.ActorRegistry.peek(v.uid) or v.record
    local began = Life.begin(v, mem, options, nowMs)
    if began == 0 then Life.clear(v.uid) end
    return 1 + began
end

function Life.step(v, nowMs, options)
    local mem = Life.stateOf(v.uid, nowMs)
    mem.nextMs = nowMs + Life.settings.stepMinMs + Life.rand(Life.settings.stepSpreadMs)
    if Life.busy(v.record) then
        mem.nextMs = nowMs + 2000
        return 0
    end
    local life = v.record.memory.life
    local hours = Life.hours()
    local due = Life.leaveDue(v, hours)
    local farewell = type(life) == "table" and life.k == "farewell"
    if due and not farewell and nowMs - mem.firstMs >= Life.settings.settleMs then
        if type(life) == "table" then Life.finish(v, mem, life, "expired", hours, nowMs) end
        if Life.farewell(v, mem, nowMs) then return 2 end
        return Life.advanceTo(v, mem, options, nowMs)
    end
    if farewell and not due then
        Life.finish(v, mem, life, "expired", hours, nowMs)
        return Life.advanceTo(v, mem, options, nowMs)
    end
    if type(life) ~= "table" then
        if nowMs - mem.firstMs < Life.settings.settleMs then return 0 end
        Life.watch(v, mem, nil, nowMs)
        return Life.begin(v, mem, options, nowMs)
    end
    local verdict = Life.progress(v, mem, life, hours, nowMs)
    if verdict == "running" and Life.watch(v, mem, life, nowMs) then verdict = "stuck" end
    if verdict == "running" and Life.staring(v, life, nowMs) then verdict = "stare" end
    if verdict == "running" then return 1 end
    Life.finish(v, mem, life, verdict, hours, nowMs)
    if verdict == "caught" then
        local wardrobe = ProjectALife.VisitorWardrobe
        if wardrobe ~= nil and type(wardrobe.caught) == "function" then wardrobe.caught(v.uid) end
    end
    return Life.advanceTo(v, mem, options, nowMs)
end

function Life.due(list, nowMs)
    local count = #list
    for offset = 1, count do
        local position = (Life.cursor + offset - 1) % count + 1
        local mem = Life.state[list[position].uid]
        if mem == nil or mem.nextMs <= nowMs then
            Life.cursor = position
            return list[position]
        end
    end
    return nil
end

function Life.scanOne(list)
    local houses, seen = {}, {}
    for position = 1, #list do
        local house = list[position].house
        if not seen[house] then
            seen[house] = true
            houses[#houses + 1] = house
        end
    end
    local hours = Life.hours()
    for offset = 1, #houses do
        local position = (Life.scanCursor + offset - 1) % #houses + 1
        local house = houses[position]
        if Life.jobs[house] ~= nil or Life.stale(Life.caches[house], hours) then
            Life.scanCursor = position
            Life.scan(house, Life.settings.budgetMs)
            return 1
        end
    end
    return 0
end

function Life.sweep(list)
    local live = {}
    for position = 1, #list do live[list[position].uid] = true end
    local module = ProjectALife.ModuleVisitorLife
    for uid in pairs(Life.state) do
        if not live[uid] then
            Life.state[uid] = nil
            Life.release(uid)
            if module ~= nil and type(module.forget) == "function" then module.forget(uid) end
        end
    end
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.peek) ~= "function" then return end
    for key, claim in pairs(Life.claims) do
        if not live[claim.uid] then Life.claims[key] = nil end
    end
end

function Life.disable(list)
    local count = 0
    for position = 1, #list do
        local record = list[position].record
        if type(record.memory.life) == "table" then
            Life.clear(list[position].uid)
            count = count + 1
        end
    end
    return count
end

function Life.tick(nowMs)
    nowMs = tonumber(nowMs) or Life.nowMs()
    if nowMs == nil or nowMs < Life.nextAtMs then return 0 end
    Life.nextAtMs = nowMs + Life.settings.passMs
    local options = Life.options()
    local list = Life.visitors()
    if options.life == false then return Life.disable(list) end
    if #list == 0 then
        Life.sweep(list)
        return 0
    end
    local work = Life.scanOne(list)
    local picked = Life.due(list, nowMs)
    if picked ~= nil then work = work + Life.step(picked, nowMs, options) end
    Life.sweep(list)
    return work
end

function Life.reset()
    Life.caches = setmetatable({}, { __mode = "k" })
    Life.jobs = setmetatable({}, { __mode = "k" })
    Life.claims, Life.state, Life.memo = {}, {}, {}
    Life.nextAtMs, Life.cursor, Life.scanCursor = 0, 0, 0
    for key in pairs(Life.metrics) do Life.metrics[key] = type(Life.metrics[key]) == "number" and 0 or "-" end
    Life.metrics.kinds = {}
end

function Life.guestQaLine()
    local m = Life.metrics
    local registry = ProjectALife.ActorRegistry
    local counts, guests, plain = {}, 0, 0
    for uid, mem in pairs(Life.state) do
        guests = guests + 1
        if mem.persona ~= nil then plain = plain + 1 end
        local record = registry ~= nil and type(registry.peek) == "function" and registry.peek(uid) or nil
        local life = record ~= nil and type(record.memory) == "table" and record.memory.life or nil
        local kind = type(life) == "table" and life.k or "none"
        counts[kind] = (counts[kind] or 0) + 1
    end
    local names = {}
    for kind in pairs(counts) do names[#names + 1] = kind end
    table.sort(names)
    local parts = {}
    for position = 1, #names do parts[position] = names[position] .. ":" .. counts[names[position]] end
    local seats = 0
    for key in pairs(Life.claims) do
        if string.sub(key, 1, 5) == "seat:" or string.sub(key, 1, 4) == "bed:" then seats = seats + 1 end
    end
    local k = m.kinds
    local others = {}
    for kind, count in pairs(k) do
        if kind ~= "cook" and kind ~= "check_fridge" and kind ~= "wash" and kind ~= "sit" and kind ~= "walk" then
            others[#others + 1] = kind .. ":" .. count
        end
    end
    table.sort(others)
    return "[ALIFE-QA] GuestLife: guests=" .. guests .. " plain=" .. plain .. " active=" .. (#parts > 0 and table.concat(parts, ",") or "-")
        .. " seats=" .. seats .. " stairs=" .. tostring(m.stairs) .. " farewells=" .. tostring(m.farewells)
        .. " stuck=" .. tostring(m.kicks) .. " giveUps=" .. tostring(m.stuck)
        .. " cook=" .. tostring(k.cook or 0) .. " fridge=" .. tostring(k.check_fridge or 0) .. " wash=" .. tostring(k.wash or 0)
        .. " sit=" .. tostring(k.sit or 0) .. " walk=" .. tostring(k.walk or 0) .. " stare_cut=" .. tostring(m.stareCut)
        .. " more=" .. (#others > 0 and table.concat(others, ",") or "-")
end

function Life.explain(uid)
    local registry = ProjectALife.ActorRegistry
    local record = registry ~= nil and type(registry.peek) == "function" and registry.peek(uid) or nil
    local life = record ~= nil and type(record.memory) == "table" and record.memory.life or nil
    local mem = Life.state[uid]
    if type(life) ~= "table" then
        return "life=none why=" .. tostring(mem ~= nil and mem.pickWhy or "no_state") .. " owns=" .. tostring(record ~= nil and Life.owns(record))
    end
    local poi = type(life.poi) == "table" and life.poi or {}
    local def = Life.INTENTS[life.k]
    local module = ProjectALife.ModuleVisitorLife
    local stare = module ~= nil and type(module.stareMs) == "function" and module.stareMs(uid, Life.nowMs() or 0) or nil
    return "life=" .. tostring(life.k) .. " kitchen=" .. tostring(Life.KITCHEN[life.k] == true)
        .. " dwellMs=" .. tostring(mem ~= nil and mem.dwellMs or (def ~= nil and def.ms ~= nil and "pending" or "hours"))
        .. " prev=" .. tostring(mem ~= nil and mem.prev or "-") .. " stareMs=" .. tostring(stare or "-")
        .. " poi=" .. tostring(poi.key) .. " seq=" .. tostring(life.seq)
        .. " untilHours=" .. tostring(life.untilHours) .. " arrived=" .. tostring(mem ~= nil and mem.arrived ~= nil)
        .. " persona=" .. tostring(mem ~= nil and mem.persona ~= nil and "plain" or "card")
        .. " why=" .. tostring(mem ~= nil and mem.why or "-") .. " intent=" .. tostring(record.intent)
end

ProjectALife.GuestLife = { qaLine = Life.guestQaLine, explain = Life.explain }

function Life.qaLine()
    local m = Life.metrics
    return "[ALIFE-QA] VisitorLife scans=" .. tostring(m.scans) .. " pois=" .. tostring(m.pois)
        .. " rooms=" .. tostring(m.rooms) .. " intents=" .. tostring(m.intents) .. " refused=" .. tostring(m.refused)
        .. " finished=" .. tostring(m.finished) .. " stuck=" .. tostring(m.stuck) .. " washed=" .. tostring(m.washed)
        .. " claimsDenied=" .. tostring(m.claimsDenied) .. " scanMs=" .. tostring(m.scanMs) .. " why=" .. tostring(m.lastWhy)
end

return Life
