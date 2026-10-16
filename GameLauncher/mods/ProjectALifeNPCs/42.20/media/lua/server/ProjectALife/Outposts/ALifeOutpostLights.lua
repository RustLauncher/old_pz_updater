require "ProjectALife/Outposts/ALifeOutpostRegistry"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.OutpostRegistry

local Lights = {
    version = 1,
    settings = {
        enabled = true,
        fuelMinutes = 1440,
        refuelBelow = 360,
        keepGenerators = true,
        generatorShare = 0.5,
        generatorCondition = 60,
        batteryPower = 1,
        maxPerSite = 64,
        sliceSize = 16,
        scanSquares = 300,
        relightGapHours = 1,
        passGapMs = 2000,
        retryGapMs = 15000,
        idleGapMs = 30000,
    },
    bulbItem = "Base.LightBulb",
    fireSprites = { camping_01_4 = true, camping_01_5 = true, camping_01_6 = true },
    adapters = {},
    sites = {},
    scenes = { stats = nil, nextAtMs = 0, litAt = {} },
    metrics = { passes = 0, slices = 0, relit = 0, capped = 0, scanned = 0, forced = 0 },
}
ProjectALife.OutpostLights = Lights

Lights.lampApi = { "getCanBeModified", "setCanBeModified", "getUseBattery", "setUseBatteryDirect", "getHasBattery",
    "setHasBattery", "getPower", "setPower", "setDelta", "hasLightBulb", "setBulbItemRaw", "isActivated", "setActive" }
Lights.generatorApi = { "getFuel", "setFuel", "getMaxFuel", "getCondition", "setCondition", "isActivated",
    "setActivated", "isConnected", "setConnected" }

function Lights.configure(adapters)
    Lights.adapters = type(adapters) == "table" and adapters or {}
    local a = Lights.adapters
    Lights.settings.enabled = a.lightsOn ~= false
    return true
end

function Lights.reset()
    Lights.sites = {}
    Lights.scenes = { stats = nil, nextAtMs = 0, litAt = {} }
    Lights.metrics = { passes = 0, slices = 0, relit = 0, capped = 0, scanned = 0, forced = 0 }
    return true
end

function Lights.enabled()
    return Lights.settings.enabled == true
end

function Lights.authoritative()
    if type(Lights.adapters.authoritative) == "function" then return Lights.adapters.authoritative() == true end
    if type(isClient) == "function" and isClient() == true then return false end
    return true
end

function Lights.hours()
    if type(Lights.adapters.hours) == "function" then return Lights.adapters.hours() end
    local value = 0
    if type(getGameTime) == "function" then
        local time = getGameTime()
        if time ~= nil and type(time.getWorldAgeHours) == "function" then value = time:getWorldAgeHours() end
    end
    return tonumber(value) or 0
end

function Lights.onServer()
    if type(Lights.adapters.onServer) == "function" then return Lights.adapters.onServer() == true end
    return type(isServer) == "function" and isServer() == true
end

function Lights.square(x, y, z)
    if type(Lights.adapters.square) == "function" then return Lights.adapters.square(x, y, z) end
    if type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil then return nil end
    return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
end

function Lights.isA(object, class)
    return object ~= nil and type(instanceof) == "function" and instanceof(object, class) == true
end

function Lights.has(object, names)
    for _, name in ipairs(names) do
        if type(object[name]) ~= "function" then return false, name end
    end
    return true
end

function Lights.objectsOn(square)
    local result = {}
    if square == nil or type(square.getObjects) ~= "function" then return result end
    local list = square:getObjects()
    if list == nil then return result end
    for index = 0, list:size() - 1 do
        local object = list:get(index)
        if object ~= nil then result[#result + 1] = object end
    end
    return result
end

function Lights.spriteName(object)
    if object == nil or type(object.getSprite) ~= "function" then return nil end
    local sprite = object:getSprite()
    if sprite == nil or type(sprite.getName) ~= "function" then return nil end
    return sprite:getName()
end

function Lights.tagged(object, siteId, field)
    if object == nil or siteId == nil or type(object.getModData) ~= "function" then return false end
    if type(object.hasModData) == "function" and object:hasModData() ~= true then return false end
    local data = object:getModData()
    return type(data) == "table" and tostring(data[field] or "") == tostring(siteId)
end

function Lights.dropObject(square, object)
    pcall(function() square:transmitRemoveItemFromSquare(object) end)
    local still = false
    pcall(function() still = square:getObjects():contains(object) == true end)
    if still then pcall(function() square:RemoveTileObject(object) end) end
    return true
end


function Lights.fireSystem()
    if Lights.adapters.campfireSystem ~= nil then return Lights.adapters.campfireSystem end
    if type(SCampfireSystem) == "table" then return SCampfireSystem.instance end
    return nil
end

function Lights.luaFire(system, square)
    if system == nil or type(system.getLuaObjectOnSquare) ~= "function" then return nil end
    local ok, fire = pcall(system.getLuaObjectOnSquare, system, square)
    if ok then return fire end
    return nil
end

function Lights.isEngineFire(object)
    return object ~= nil and type(object.getName) == "function" and object:getName() == "Campfire"
end

function Lights.dropPlain(square)
    local dropped = 0
    for _, object in ipairs(Lights.objectsOn(square)) do
        local name = Lights.spriteName(object)
        if name ~= nil and Lights.fireSprites[name] == true and not Lights.isEngineFire(object) then
            Lights.dropObject(square, object)
            dropped = dropped + 1
        end
    end
    return dropped
end

function Lights.flammableFloor(square)
    if square == nil or type(square.getFloor) ~= "function" then return false end
    local name = Lights.spriteName(square:getFloor())
    if type(name) ~= "string" then return false end
    if string.sub(name, 1, 22) == "floors_interior_carpet" or string.sub(name, 1, 6) == "carpet" then return true end
    if string.sub(name, 1, 28) == "floors_interior_tilesandwood" then
        local index = tonumber(string.match(name, "_(%d+)$"))
        return index ~= nil and index >= 40
    end
    return false
end

function Lights.indoorRisk(square)
    if type(square.isOutside) ~= "function" or square:isOutside() == true then return nil end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    for _, step in ipairs({ { -1, 0 }, { 0, -1 }, { -1, -1 } }) do
        if Lights.flammableFloor(Lights.square(x + step[1], y + step[2], z)) then return "indoor_flammable_floor" end
    end
    return nil
end

function Lights.inSafehouse(square)
    if type(SafeHouse) ~= "table" or type(SafeHouse.isSafeHouse) ~= "function" then return false end
    local ok, found = pcall(SafeHouse.isSafeHouse, square, nil, true)
    return ok and found ~= nil and found ~= false
end

function Lights.tagFire(fire, siteId)
    if siteId == nil or type(fire.getIsoObject) ~= "function" then return end
    local iso = fire:getIsoObject()
    if iso ~= nil and type(iso.getModData) == "function" then
        local data = iso:getModData()
        if type(data) == "table" and data.ProjectALifeSiteId == nil then data.ProjectALifeSiteId = tostring(siteId) end
    end
end

function Lights.isoOf(fire)
    if fire ~= nil and type(fire.getIsoObject) == "function" then return fire:getIsoObject() end
    return nil
end

function Lights.campfireAt(square, siteId, hours, entry)
    local system = Lights.fireSystem()
    if system == nil then return "failed", "no_campfire_system" end
    if Lights.inSafehouse(square) then return "failed", "safehouse" end
    local risk = Lights.indoorRisk(square)
    local fire = Lights.luaFire(system, square)
    if fire == nil then
        Lights.dropPlain(square)
        local iso = type(system.getIsoObjectOnSquare) == "function" and system:getIsoObjectOnSquare(square) or nil
        if iso ~= nil and type(system.loadIsoObject) == "function" then
            pcall(system.loadIsoObject, system, iso)
        elseif type(system.addCampfire) == "function" then
            pcall(system.addCampfire, system, square)
        end
        fire = Lights.luaFire(system, square)
        if fire == nil then return "failed", "add_failed" end
    end
    Lights.tagFire(fire, siteId)
    local iso = Lights.isoOf(fire)
    if risk ~= nil then return "failed", risk, iso end
    local settings = Lights.settings
    local fuel = tonumber(fire.fuelAmt) or 0
    if fire.isLit == true and fuel >= settings.refuelBelow then return "kept", nil, iso end
    if entry ~= nil and entry.litAt ~= nil and hours - entry.litAt < settings.relightGapHours then
        Lights.metrics.capped = Lights.metrics.capped + 1
        return "capped", "relight_cap", iso
    end
    if fuel < settings.refuelBelow then
        if type(fire.setFuel) == "function" then fire:setFuel(settings.fuelMinutes)
        elseif type(fire.addFuel) == "function" then fire:addFuel(settings.fuelMinutes - fuel) end
    end
    if fire.isLit ~= true and type(fire.lightFire) == "function" then fire:lightFire() end
    if fire.isLit ~= true then return "failed", "light_refused", iso end
    if entry ~= nil then
        if entry.litAt ~= nil then Lights.metrics.relit = Lights.metrics.relit + 1 end
        entry.litAt = hours
    end
    return "lit", nil, iso
end

function Lights.removeCampfire(square)
    local system = Lights.fireSystem()
    local fire = Lights.luaFire(system, square)
    if fire == nil or type(system.removeCampfire) ~= "function" then return false end
    return pcall(system.removeCampfire, system, fire)
end


function Lights.lampPowered(object)
    return object:getCanBeModified() == true and object:getUseBattery() == true
        and object:getHasBattery() == true and (tonumber(object:getPower()) or 0) > 0
        and object:hasLightBulb() == true
end

function Lights.powerLamp(object)
    local complete = Lights.has(object, Lights.lampApi)
    if not complete then return false end
    object:setCanBeModified(true)
    object:setUseBatteryDirect(true)
    object:setHasBattery(true)
    object:setPower(Lights.settings.batteryPower)
    object:setDelta(0)
    if object:hasLightBulb() ~= true then object:setBulbItemRaw(Lights.bulbItem) end
    return true
end

function Lights.lightCount(object)
    if type(object.getLights) ~= "function" then return 0 end
    local list = object:getLights()
    if list == nil or type(list.size) ~= "function" then return 0 end
    return list:size()
end

function Lights.switchOn(object)
    if object:isActivated() ~= true then object:setActive(true, false, true) end
    return object:isActivated() == true
end

function Lights.syncLamp(object)
    if Lights.onServer() and type(object.syncCustomizedSettings) == "function" then
        object:syncCustomizedSettings(nil)
    end
end

function Lights.markFill(object, siteId, quiet)
    if type(object.getModData) ~= "function" then return false end
    local data = object:getModData()
    if type(data) ~= "table" then return false end
    if data.ProjectALifeFill == nil then
        data.ProjectALifeFill = 1
        if data.ProjectALifeSiteId == nil and siteId ~= nil then data.ProjectALifeSiteId = tostring(siteId) end
        if quiet ~= true and Lights.onServer() and type(object.transmitModData) == "function" then
            object:transmitModData()
        end
    end
    return true
end

function Lights.streetLight(object)
    return type(object.couldBePoweredByGenerator) == "function" and object:couldBePoweredByGenerator() ~= true
end

function Lights.fieldOn(object)
    if type(object.setActivated) ~= "function" or type(object.switchLight) ~= "function" then return false end
    if object:isActivated() == true then return false end
    object:setActivated(true)
    object:switchLight(true)
    if Lights.onServer() and type(object.syncIsoObject) == "function" then object:syncIsoObject(false, 1, nil) end
    return true
end

function Lights.placed(object, siteId)
    object:setActive(true, true, true)
    object:switchLight(true)
    if Lights.streetLight(object) then Lights.markFill(object, siteId, true) end
end

function Lights.fixtureOne(object, siteId)
    if type(object.isActivated) ~= "function" or type(object.setActive) ~= "function" then return "failed", "api_missing" end
    if Lights.streetLight(object) then
        Lights.markFill(object, siteId)
        Lights.fieldOn(object)
        return "fill", "street_light"
    end
    if object:isActivated() == true then return "kept" end
    object:setActive(true, false, true)
    if object:isActivated() == true then return "on" end
    return "failed", "fixture_locked"
end

function Lights.lampOne(object, entry, siteId)
    if entry.kind == "fixture" then return Lights.fixtureOne(object, siteId) end
    local complete = Lights.has(object, Lights.lampApi)
    if not complete then return "failed", "api_missing" end
    if Lights.streetLight(object) then
        Lights.markFill(object, siteId)
        Lights.fieldOn(object)
        return "fill", "street_light"
    end
    if Lights.lightCount(object) == 0 then return "failed", "no_light_source" end
    local changed = false
    if not Lights.lampPowered(object) then
        Lights.powerLamp(object)
        changed = true
    end
    if object:isActivated() ~= true then
        Lights.switchOn(object)
        changed = true
    end
    if object:isActivated() ~= true then return "failed", "switch_refused" end
    if changed then
        Lights.syncLamp(object)
        return "on"
    end
    return "kept"
end


function Lights.generatorOne(object, siteId)
    local complete = Lights.has(object, Lights.generatorApi)
    if not complete then return "failed", "api_missing" end
    if not Lights.tagged(object, siteId, "ProjectALifeOutpostSite") then return "skipped", "foreign_generator" end
    local settings = Lights.settings
    local changed = false
    if object:isConnected() ~= true then object:setConnected(true) changed = true end
    local tank = tonumber(object:getMaxFuel()) or 10
    if (tonumber(object:getFuel()) or 0) < tank * settings.generatorShare then
        object:setFuel(tank)
        changed = true
    end
    if (tonumber(object:getCondition()) or 0) < settings.generatorCondition then
        object:setCondition(settings.generatorCondition)
        changed = true
    end
    if object:isActivated() ~= true then
        object:setActivated(true)
        changed = true
    end
    if object:isActivated() ~= true then return "failed", "generator_refused" end
    if changed then
        if Lights.onServer() and type(object.sync) == "function" then object:sync() end
        return "on"
    end
    return "kept"
end

function Lights.process(entry, siteId, hours)
    local square = Lights.square(entry.x, entry.y, entry.z)
    if square == nil then return "pending" end
    if entry.kind == "campfire" then
        local status, reason = Lights.campfireAt(square, siteId, hours, entry)
        return status, reason
    end
    if entry.kind == "generator" and Lights.settings.keepGenerators ~= true then return "skipped", "generators_off" end
    local class = entry.kind == "generator" and "IsoGenerator" or "IsoLightSwitch"
    local found
    for _, object in ipairs(Lights.objectsOn(square)) do
        if Lights.isA(object, class)
                and (entry.kind ~= "lamp" or entry.sprite == nil or Lights.spriteName(object) == entry.sprite) then
            found = object
            break
        end
    end
    if found == nil then return "failed", "missing" end
    if entry.kind == "generator" then return Lights.generatorOne(found, siteId) end
    return Lights.lampOne(found, entry, siteId)
end


Lights.rowKinds = { campfire = "campfire", generator = "generator", light = "lamp" }
Lights.kindOrder = { campfire = 1, generator = 2, lamp = 3, fixture = 4 }

function Lights.key(kind, x, y, z)
    return tostring(kind == "fixture" and "lamp" or kind) .. ":" .. tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

function Lights.rowEntries(site)
    local rows = {}
    if Registry ~= nil and type(Registry.propsOf) == "function" then rows = Registry.propsOf(site.id) end
    local entries, seen = {}, {}
    for _, row in ipairs(rows) do
        local kind = Lights.rowKinds[row.op]
        local x, y = tonumber(row.x), tonumber(row.y)
        if kind ~= nil and x ~= nil and y ~= nil then
            local z = math.floor(tonumber(row.z) or 0)
            local key = Lights.key(kind, x, y, z)
            if not seen[key] then
                seen[key] = true
                entries[#entries + 1] = { kind = kind, x = x, y = y, z = z, sprite = row.sprite, key = key }
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.kind ~= b.kind then return Lights.kindOrder[a.kind] < Lights.kindOrder[b.kind] end
        if a.y ~= b.y then return a.y < b.y end
        return a.x < b.x
    end)
    return entries, seen
end

function Lights.scanSquare(site, info, square, x, y, z)
    for _, object in ipairs(Lights.objectsOn(square)) do
        if Lights.isA(object, "IsoLightSwitch") then
            local owned = Lights.tagged(object, site.id, "ProjectALifeSiteId")
            local locked = type(object.getCanBeModified) == "function" and object:getCanBeModified() ~= true
            local kind = owned and "lamp" or (locked and "fixture" or nil)
            if kind ~= nil then
                local key = Lights.key(kind, x, y, z)
                if not info.seen[key] and #info.found < Lights.settings.maxPerSite then
                    info.seen[key] = true
                    info.found[#info.found + 1] = { kind = kind, x = x, y = y, z = z,
                        sprite = Lights.spriteName(object), key = key }
                end
            end
        end
    end
end

function Lights.scanStep(site, info)
    local b = site.bounds
    local scan = info.scan
    if scan == nil then
        if type(b) ~= "table" then info.scanDone = true return 0 end
        local x1, y1 = math.floor(tonumber(b.x1) or tonumber(site.x) or 0), math.floor(tonumber(b.y1) or tonumber(site.y) or 0)
        local x2, y2 = math.floor(tonumber(b.x2) or x1), math.floor(tonumber(b.y2) or y1)
        scan = { x1 = x1, y1 = y1, w = math.max(1, x2 - x1 + 1), h = math.max(1, y2 - y1 + 1),
            z1 = math.floor(tonumber(b.z) or 0), levels = 2, n = 0, unloaded = 0 }
        scan.total = scan.w * scan.h * scan.levels
        info.scan = scan
    end
    local budget, layer, visited = Lights.settings.scanSquares, scan.w * scan.h, 0
    while budget > 0 and scan.n < scan.total do
        local n = scan.n
        local rest = n % layer
        local x, y, z = scan.x1 + rest % scan.w, scan.y1 + math.floor(rest / scan.w), scan.z1 + math.floor(n / layer)
        scan.n = n + 1
        budget = budget - 1
        visited = visited + 1
        local square = Lights.square(x, y, z)
        if square == nil then scan.unloaded = scan.unloaded + 1
        else Lights.scanSquare(site, info, square, x, y, z) end
    end
    Lights.metrics.scanned = Lights.metrics.scanned + visited
    if scan.n >= scan.total then info.scanDone = true end
    return visited
end


function Lights.stats(entries, pending)
    local s = { campfires = 0, lit = 0, lamps = 0, on = 0, fills = 0, fixtures = 0, fixturesOn = 0, generators = 0,
        generatorsOn = 0, failed = 0, pending = pending or 0, reasons = {} }
    for _, entry in ipairs(entries) do
        local good = entry.state == "lit" or entry.state == "kept" or entry.state == "on"
        if entry.kind == "campfire" then
            s.campfires = s.campfires + 1
            if good then s.lit = s.lit + 1 end
        elseif entry.kind == "lamp" then
            s.lamps = s.lamps + 1
            if good then s.on = s.on + 1 end
            if entry.state == "fill" then s.fills = s.fills + 1 end
        elseif entry.kind == "fixture" then
            s.fixtures = s.fixtures + 1
            if good then s.fixturesOn = s.fixturesOn + 1 end
        elseif entry.kind == "generator" then
            s.generators = s.generators + 1
            if good then s.generatorsOn = s.generatorsOn + 1 end
        end
        if entry.state == "failed" then
            s.failed = s.failed + 1
            local why = tostring(entry.reason or "unknown")
            s.reasons[why] = (s.reasons[why] or 0) + 1
        end
    end
    return s
end

function Lights.copyEntry(entry)
    return { kind = entry.kind, x = entry.x, y = entry.y, z = entry.z, sprite = entry.sprite, key = entry.key }
end

function Lights.freshEntries(site, info)
    if info.rowBase == nil or info.rowCount ~= site.propCount then
        info.rowBase, info.rowCount = Lights.rowEntries(site), site.propCount
    end
    local entries = {}
    for index, entry in ipairs(info.rowBase) do entries[index] = Lights.copyEntry(entry) end
    return entries
end

function Lights.beginPass(site, info, hours)
    local entries = Lights.freshEntries(site, info)
    local seen = {}
    for _, entry in ipairs(entries) do seen[entry.key] = true end
    local previous = info.entries
    if type(previous) == "table" then
        local memory = {}
        for _, entry in ipairs(previous) do memory[entry.key] = entry end
        for _, entry in ipairs(entries) do
            local old = memory[entry.key]
            if old ~= nil then entry.litAt = old.litAt end
        end
    end
    local keepScan = info.scanDone == true and info.scan ~= nil and info.scan.unloaded == 0
    local found = {}
    if keepScan then
        for _, entry in ipairs(info.found) do
            if not seen[entry.key] then
                seen[entry.key] = true
                entries[#entries + 1] = entry
            end
        end
        found = info.found
    else
        info.scan, info.scanDone = nil, false
    end
    if #entries > Lights.settings.maxPerSite then
        for index = #entries, Lights.settings.maxPerSite + 1, -1 do entries[index] = nil end
    end
    info.entries, info.found, info.seen = entries, found, seen
    info.cursor, info.pending, info.hoursAt = 1, 0, hours
    info.pass = true
    Lights.metrics.passes = Lights.metrics.passes + 1
end

function Lights.finishPass(site, info, now, hours)
    info.pass = nil
    info.force = false
    info.stats = Lights.stats(info.entries, info.pending)
    if info.pending > 0 then
        info.nextAtMs = now + Lights.settings.retryGapMs
        return
    end
    info.nextAtMs = now + Lights.settings.idleGapMs
    if Registry == nil then return end
    local fresh = Registry.read(site.id)
    if fresh == nil then return end
    Registry.update(fresh.id, fresh.revision, function(record)
        record.lightsVersion = Lights.version
        record.lightsHours = hours
    end)
end

function Lights.runSlice(site, info, now, hours)
    local entries, budget, worked = info.entries, Lights.settings.sliceSize, 0
    Lights.metrics.slices = Lights.metrics.slices + 1
    while budget > 0 and info.cursor <= #entries do
        local entry = entries[info.cursor]
        local ok, status, reason = pcall(Lights.process, entry, site.id, hours)
        if not ok then status, reason = "failed", "error" end
        entry.state, entry.reason = status, reason
        if status == "pending" then info.pending = info.pending + 1 end
        info.cursor = info.cursor + 1
        budget = budget - 1
        worked = worked + 1
    end
    if info.cursor > #entries then
        if info.scanDone ~= true then
            Lights.scanStep(site, info)
            if info.scanDone == true then
                for _, entry in ipairs(info.found) do
                    if #entries < Lights.settings.maxPerSite then entries[#entries + 1] = entry end
                end
            end
            info.nextAtMs = now + Lights.settings.passGapMs
            return true
        end
        Lights.finishPass(site, info, now, hours)
        return true
    end
    info.nextAtMs = now + Lights.settings.passGapMs
    return worked > 0
end

function Lights.siteInfo(siteId)
    local info = Lights.sites[siteId]
    if info == nil then
        info = { nextAtMs = 0 }
        Lights.sites[siteId] = info
    end
    return info
end

function Lights.due(site, info, hours)
    if info.force == true or site.lightsVersion ~= Lights.version then return true end
    return hours - (tonumber(site.lightsHours) or -1e9) >= Lights.settings.relightGapHours
end

function Lights.tick(site, now, hours)
    if not Lights.enabled() or not Lights.authoritative() or type(site) ~= "table" then return false end
    if site.state ~= "built" and site.state ~= "garrisoned" then return false end
    now = tonumber(now) or 0
    hours = tonumber(hours) or Lights.hours()
    local info = Lights.siteInfo(site.id)
    if now < info.nextAtMs then return false end
    if info.pass == nil then
        if not Lights.due(site, info, hours) then
            info.nextAtMs = now + Lights.settings.idleGapMs
            return false
        end
        Lights.beginPass(site, info, hours)
    end
    return Lights.runSlice(site, info, now, hours)
end

function Lights.relight(site, now)
    if type(site) ~= "table" then return false, "no_site" end
    if not Lights.enabled() then return false, "lights_off" end
    local info = Lights.siteInfo(site.id)
    info.force, info.pass, info.nextAtMs, info.scanDone, info.scan = true, nil, 0, false, nil
    Lights.metrics.forced = Lights.metrics.forced + 1
    Lights.tick(site, tonumber(now) or 0, Lights.hours())
    return true, info.stats
end

function Lights.tickScenes(records, now, hours)
    if not Lights.enabled() or not Lights.authoritative() or type(records) ~= "table" then return 0 end
    now = tonumber(now) or 0
    if now < Lights.scenes.nextAtMs then return 0 end
    Lights.scenes.nextAtMs = now + Lights.settings.idleGapMs
    hours = tonumber(hours) or Lights.hours()
    local entries, handled = {}, 0
    for key, record in pairs(records) do
        if type(record) == "table" and record.kind == "camp" and record.state ~= "draining"
                and record.state ~= "released" then
            for _, row in ipairs(type(record.squares) == "table" and record.squares or {}) do
                if Lights.fireSprites[tostring(row.sprite)] == true then
                    local held = Lights.scenes.litAt[key]
                    local entry = { kind = "campfire", x = row.x, y = row.y, z = row.z, litAt = held }
                    local ok, status, reason = pcall(Lights.process, entry, nil, hours)
                    if not ok then status, reason = "failed", "error" end
                    entry.state, entry.reason = status, reason
                    Lights.scenes.litAt[key] = entry.litAt
                    entries[#entries + 1] = entry
                    handled = handled + 1
                end
            end
        end
    end
    Lights.scenes.stats = Lights.stats(entries, 0)
    return handled
end


function Lights.totals()
    local t = { sites = 0, campfires = 0, lit = 0, lamps = 0, on = 0, fills = 0, fixtures = 0, fixturesOn = 0,
        generators = 0, generatorsOn = 0, failed = 0, pending = 0, reasons = {} }
    local function add(stats)
        t.campfires, t.lit = t.campfires + stats.campfires, t.lit + stats.lit
        t.lamps, t.on = t.lamps + stats.lamps, t.on + stats.on
        t.fills = t.fills + stats.fills
        t.fixtures, t.fixturesOn = t.fixtures + stats.fixtures, t.fixturesOn + stats.fixturesOn
        t.generators, t.generatorsOn = t.generators + stats.generators, t.generatorsOn + stats.generatorsOn
        t.failed, t.pending = t.failed + stats.failed, t.pending + stats.pending
        for reason, count in pairs(stats.reasons) do t.reasons[reason] = (t.reasons[reason] or 0) + count end
    end
    for _, info in pairs(Lights.sites) do
        if info.stats ~= nil then
            t.sites = t.sites + 1
            add(info.stats)
        end
    end
    if Lights.scenes.stats ~= nil then add(Lights.scenes.stats) end
    return t
end

function Lights.reasonText(reasons)
    local names = {}
    for reason in pairs(reasons) do names[#names + 1] = reason end
    table.sort(names)
    local parts = {}
    for _, name in ipairs(names) do parts[#parts + 1] = name .. "=" .. tostring(reasons[name]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

function Lights.qaLine()
    local t = Lights.totals()
    return "[ALIFE-QA] SiteLights: sites=" .. tostring(t.sites) .. " campfires=" .. tostring(t.campfires)
        .. " lit=" .. tostring(t.lit) .. " lamps=" .. tostring(t.lamps) .. " on=" .. tostring(t.on)
        .. " failed=" .. tostring(t.failed) .. " reasons=" .. Lights.reasonText(t.reasons)
        .. " fills=" .. tostring(t.fills) .. " fixtures=" .. tostring(t.fixtures) .. " fixturesOn=" .. tostring(t.fixturesOn)
        .. " generators=" .. tostring(t.generators) .. " generatorsOn=" .. tostring(t.generatorsOn)
        .. " pending=" .. tostring(t.pending) .. " enabled=" .. tostring(Lights.enabled())
        .. " passes=" .. tostring(Lights.metrics.passes) .. " relit=" .. tostring(Lights.metrics.relit)
end

return Lights
