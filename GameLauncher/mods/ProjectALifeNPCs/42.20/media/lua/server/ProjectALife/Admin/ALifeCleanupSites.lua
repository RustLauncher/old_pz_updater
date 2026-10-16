require "ProjectALife/Admin/ALifeCleanup"
require "ProjectALife/Admin/ALifeCleanupWorld"

ProjectALife = ProjectALife or {}

local Cleanup = ProjectALife.Cleanup
local World = Cleanup.World

local Sites = { id = "sites", scopes = { "bases" } }
Cleanup.Sites = Sites

function Sites.state()
    local registry = ProjectALife.OutpostRegistry
    if registry == nil or type(registry.storageForProps) ~= "function" then return nil end
    local ok, state = pcall(registry.storageForProps)
    if ok and type(state) == "table" and type(state.sites) == "table" then return state end
    return nil
end

function Sites.rowsLeft(site)
    local count = 0
    if type(site) ~= "table" or type(site.props) ~= "table" then return 0 end
    for _, row in ipairs(site.props) do
        if type(row) == "table" and row.cs == nil then count = count + 1 end
    end
    return count
end

function Sites.begin(job)
    local state = Sites.state()
    job.siteIds = {}
    job.siteRows = {}
    job.cursor.site = 1
    job.cursor.row = nil
    job.cursor.rowsSite = nil
    if state == nil then return end
    for _, id in ipairs(state.order or {}) do
        local site = state.sites[id]
        if type(site) == "table" and (type(site.props) == "table" and #site.props > 0 or site.state ~= "expired") then
            job.siteIds[#job.siteIds + 1] = id
        end
    end
end

function Sites.describe(job, site)
    local tagged = 0
    local rows = type(site.props) == "table" and #site.props or 0
    for _, row in ipairs(site.props or {}) do
        if type(row) == "table" and row.sid == true then tagged = tagged + 1 end
    end
    if (job.passes or 1) <= 1 then
        Cleanup.count(job, "bases.sites")
        if tagged > 0 then Cleanup.count(job, "bases.sites_tagged") else Cleanup.count(job, "bases.sites_legacy") end
        Cleanup.count(job, "bases.rows", rows)
    end
    local bounds = type(site.bounds) == "table" and site.bounds or {}
    local list = job.siteRows
    if #list < Cleanup.settings.siteCap then
        list[#list + 1] = { id = site.id, preset = site.presetId, state = site.state, x = site.x, y = site.y,
            z = tonumber(bounds.z) or 0, rows = rows, tagged = tagged }
    end
end

function Sites.anyLoaded(job, site)
    local registry = ProjectALife.OutpostRegistry
    local ok, x1, y1, x2, y2 = pcall(registry.propsBox, site.id)
    if not ok or x1 == nil then return true end
    local sx = x1
    while sx <= x2 + 15 do
        local sy = y1
        while sy <= y2 + 15 do
            if World.loaded(math.min(sx, x2), math.min(sy, y2)) then return true end
            sy = sy + 16
        end
        sx = sx + 16
    end
    sx = x1
    while sx <= x2 + 7 do
        local sy = y1
        while sy <= y2 + 7 do
            Cleanup.watch(job, math.min(sx, x2), math.min(sy, y2))
            sy = sy + 8
        end
        sx = sx + 8
    end
    return false
end

function Sites.entry(site, row, verdict)
    local entry = World.describe(row, verdict)
    entry.site = site.id
    return entry
end

function Sites.inspect(job, site, row)
    local verdict = World.inspectRow(job, site, row)
    local state = verdict.state
    if state == "unloaded" then
        Cleanup.count(job, "bases.unloaded")
        Cleanup.watch(job, tonumber(row.x), tonumber(row.y))
    elseif state == "gone" then Cleanup.count(job, "bases.absent")
    elseif state == "foreign" then Cleanup.count(job, "bases.foreign")
    elseif state == "unreadable" then Cleanup.count(job, "bases.unreadable")
    elseif state == "ours" then
        Cleanup.count(job, "bases.found")
        Cleanup.count(job, "bases.ours_" .. tostring(verdict.how))
    else
        Cleanup.count(job, "bases." .. state)
        Cleanup.count(job, "bases." .. state .. "." .. tostring(verdict.why))
        local key = state == "protected" and "protectedRows" or "unverifiedRows"
        local list = job[key]
        if list == nil then
            list = {}
            job[key] = list
        end
        if #list < Cleanup.settings.skipCap then list[#list + 1] = Sites.entry(site, row, verdict) end
    end
end

function Sites.scanRows(job, site)
    local rows = site.props
    local index = job.cursor.row or 1
    local calls = 0
    while index <= #rows and calls < Cleanup.settings.rowsPerCall and Cleanup.open(job) do
        local row = rows[index]
        if type(row) == "table" then
            local ok, reason = pcall(Sites.inspect, job, site, row)
            if not ok then Cleanup.fail(job, "scan_row", reason) end
        end
        Cleanup.spend(job, 0.2)
        index = index + 1
        calls = calls + 1
    end
    job.cursor.row = index
    return index > #rows
end

function Sites.visit(job, site, row)
    local verdict = World.inspectRow(job, site, row)
    local state = verdict.state
    if state == "unloaded" then
        Cleanup.watch(job, tonumber(row.x), tonumber(row.y))
        return "keep", 0, 0
    end
    if state == "gone" then
        Cleanup.count(job, "bases.absent")
        return "gone", 0, 0
    end
    if state == "unreadable" then
        row.cf = (tonumber(row.cf) or 0) + 1
        Cleanup.fail(job, "unreadable_square", tostring(row.x) .. "," .. tostring(row.y))
        if row.cf >= 3 and row.cs ~= "unreadable" then
            row.cs = "unreadable"
            Cleanup.count(job, "bases.unreadable")
            Cleanup.skip(job, "bases", Sites.entry(site, row, { why = "unreadable" }))
        end
        return "keep", 0, 0
    end
    if state == "foreign" then
        Cleanup.count(job, "bases.foreign")
        return "gone", 0, 0
    end
    if not World.allowed(job, site, verdict) then
        if row.cs ~= verdict.why then
            row.cs = verdict.why
            Cleanup.count(job, "bases." .. state)
            Cleanup.skip(job, "bases", Sites.entry(site, row, verdict))
        end
        return "keep", 0, 0
    end
    local removed, cost = World.removeObjects(job, verdict, row)
    if removed == 0 then
        row.cf = (tonumber(row.cf) or 0) + 1
        if row.cf >= 3 and row.cs ~= "remove_failed" then
            row.cs = "remove_failed"
            Cleanup.skip(job, "bases", Sites.entry(site, row, { why = "remove_failed" }))
        end
        return "keep", 0, 0
    end
    row.cs = nil
    Cleanup.count(job, "bases.removed", removed)
    return "gone", removed, math.max(1, cost)
end

function Sites.close(job, site)
    local registry = ProjectALife.OutpostRegistry
    if Sites.rowsLeft(site) > 0 then return false end
    if #site.props > 0 then
        site.cleanup = "partial"
        return false
    end
    if site.state == "expired" then return true end
    local hours = Cleanup.hours()
    local pressure = ProjectALife.WorldPressure
    if pressure ~= nil and type(pressure.release) == "function" and site.pressureTicket ~= nil then
        pcall(pressure.release, site.pressureTicket, hours)
    end
    local ok = pcall(registry.expire, site.id, site.revision, hours, "cleanup")
    if ok then Cleanup.count(job, "bases.sites_closed") end
    return ok
end

Sites.reconOps = { tile = true, thumpable = true, floor = true, object = true, container = true, door = true,
    campfire = true, litter = true, light = true, radio = true, stairs = true, generator = true, items = true }

function Sites.needsRecon(site)
    if type(site.props) == "table" and #site.props > 0 then return false end
    if site.cleanupRecon == true then return false end
    local state = site.state
    if state ~= "built" and state ~= "garrisoned" and state ~= "build_failed" then return false end
    local presets = ProjectALife.OutpostPresets
    local preset = presets ~= nil and type(presets.get) == "function" and presets.get(site.presetId) or nil
    if type(preset) ~= "table" or preset.class == "building" then return false end
    return true
end

function Sites.reconRows(site)
    local cache = Cleanup.volatile.recon
    if cache == nil then
        cache = {}
        Cleanup.volatile.recon = cache
    end
    if cache[site.id] ~= nil then return cache[site.id] end
    local rows = {}
    local builder = ProjectALife.OutpostBuilder
    local preset = ProjectALife.OutpostPresets.get(site.presetId)
    if builder ~= nil and type(builder.resolve) == "function" then
        local ok, sheet = pcall(builder.resolve, preset, site, site.x * 31 + site.y, {})
        if ok and type(sheet) == "table" and type(sheet.ops) == "table" then
            for _, op in ipairs(sheet.ops) do
                if Sites.reconOps[op.op] and op.keep ~= true and tonumber(op.x) ~= nil and tonumber(op.y) ~= nil then
                    local class = nil
                    if op.op == "generator" then class = "IsoGenerator" elseif op.op == "light" then class = "IsoLightSwitch" end
                    rows[#rows + 1] = { op = op.op, x = op.x, y = op.y, z = op.z or 0, sprite = op.sprite, class = class,
                        item = op.item, recon = true }
                end
            end
        end
    end
    cache[site.id] = rows
    return rows
end

function Sites.recon(job, site)
    local rows = Sites.reconRows(site)
    job.recon = job.recon or {}
    local index = job.recon[site.id] or 1
    if index == 1 and job.run then
        local waiting = false
        for _, row in ipairs(rows) do
            if not World.loaded(row.x, row.y) then
                waiting = true
                Cleanup.watch(job, row.x, row.y)
            end
        end
        if waiting then return true end
    end
    while index <= #rows and Cleanup.open(job) do
        local row = rows[index]
        if job.run then
            local ok, verdict, removed, cost = pcall(Sites.visit, job, site, row)
            if not ok then Cleanup.fail(job, "recon_row", verdict)
            elseif verdict == "gone" and (tonumber(removed) or 0) > 0 then Cleanup.spend(job, cost or 1) end
        else
            local ok, reason = pcall(Sites.inspect, job, site, row)
            if not ok then Cleanup.fail(job, "recon_row", reason) end
        end
        Cleanup.count(job, "bases.recon_rows")
        index = index + 1
        Cleanup.spend(job, 0.2)
    end
    job.recon[site.id] = index
    if index <= #rows then return false end
    if job.run then
        site.cleanupRecon = true
        Sites.close(job, site)
    end
    return true
end

function Sites.work(job, id)
    local state = Sites.state()
    local site = state ~= nil and state.sites[id] or nil
    if site == nil or type(site.props) ~= "table" then return true end
    if job.cursor.rowsSite ~= id then
        job.cursor.rowsSite = id
        job.cursor.row = nil
        Sites.describe(job, site)
    end
    if Sites.needsRecon(site) then
        if job.cursor.rowsSite == id and job.cursor.reconSite ~= id then
            job.cursor.reconSite = id
            Cleanup.count(job, "bases.recon_sites")
        end
        return Sites.recon(job, site)
    end
    if not job.run then return Sites.scanRows(job, site) end
    if #site.props == 0 then
        Sites.close(job, site)
        return true
    end
    if not Sites.anyLoaded(job, site) then return true end
    local registry = ProjectALife.OutpostRegistry
    local before = job.budget.units
    local limits = { rows = Cleanup.settings.rowsPerCall, units = before, deadline = job.budget.deadline,
        now = Cleanup.now }
    local function visitor(row)
        return Sites.visit(job, site, row)
    end
    local ok, gone, removed, left, abandoned = pcall(registry.drainProps, id, visitor, limits)
    if not ok then
        Cleanup.fail(job, "drain", gone)
        return true
    end
    Cleanup.spend(job, math.max(0, before - limits.units))
    for _, entry in ipairs(abandoned or {}) do
        Cleanup.fail(job, "drain_row", tostring(entry.error))
        Cleanup.count(job, "bases.abandoned")
    end
    if site.drainCursor ~= nil then return false end
    Sites.close(job, site)
    return true
end

function Sites.step(job)
    while Cleanup.open(job) do
        local id = job.siteIds[job.cursor.site]
        if id == nil then return true end
        if Sites.work(job, id) then
            job.cursor.site = job.cursor.site + 1
            job.cursor.row = nil
            job.cursor.rowsSite = nil
        else
            return false
        end
    end
    return false
end

function Sites.pending(job)
    local state = Sites.state()
    if state == nil then return 0 end
    local total = 0
    for _, id in ipairs(job.siteIds or {}) do
        local site = state.sites[id]
        total = total + Sites.rowsLeft(site)
        if site ~= nil and Sites.needsRecon(site) then total = total + math.max(1, #Sites.reconRows(site)) end
    end
    return total
end

function Sites.pendingList(job, limit)
    local state = Sites.state()
    local list = {}
    if state == nil then return list end
    for _, id in ipairs(job.siteIds or {}) do
        local site = state.sites[id]
        local left = Sites.rowsLeft(site)
        if site ~= nil and Sites.needsRecon(site) then left = left + math.max(1, #Sites.reconRows(site)) end
        if left > 0 and #list < limit then
            local bounds = type(site.bounds) == "table" and site.bounds or {}
            list[#list + 1] = { kind = "site", id = id, x = site.x, y = site.y, z = tonumber(bounds.z) or 0, left = left }
        end
    end
    return list
end

Cleanup.add(Sites)

local Scenes = { id = "scenes", scopes = { "bases" } }
Cleanup.Scenes = Scenes

function Scenes.kit()
    local kit = ProjectALife.SceneKit
    if kit == nil or type(kit.placed) ~= "table" then return nil end
    return kit
end

function Scenes.begin(job)
    job.sceneKeys = {}
    job.cursor.scene = 1
    local kit = Scenes.kit()
    if kit == nil then return end
    for key, record in pairs(kit.placed) do
        if type(record) == "table" then job.sceneKeys[#job.sceneKeys + 1] = tostring(key) end
    end
    table.sort(job.sceneKeys)
end

function Scenes.places(record)
    local places = {}
    if type(record.origin) == "table" then places[#places + 1] = record.origin end
    for _, list in ipairs({ record.squares, record.vehicles }) do
        for _, row in ipairs(type(list) == "table" and list or {}) do
            if type(row) == "table" then places[#places + 1] = row end
        end
    end
    return places
end

function Scenes.work(job, key)
    local kit = Scenes.kit()
    local record = kit ~= nil and kit.placed[key] or nil
    if type(record) ~= "table" then return end
    local ready, guarded = true, false
    for _, place in ipairs(Scenes.places(record)) do
        local x, y = tonumber(place.x), tonumber(place.y)
        if x ~= nil and y ~= nil then
            if not World.loaded(x, y) then
                ready = false
                Cleanup.watch(job, x, y)
            elseif World.inSafehouse(job, x, y) and not World.overridden(job, nil, "safehouse") then
                guarded = true
            end
        end
    end
    Cleanup.count(job, "bases.scenes")
    local cars = type(record.vehicles) == "table" and #record.vehicles or 0
    if cars > 0 then Cleanup.count(job, "bases.scene_vehicles", cars) end
    if guarded then
        if not job.run then
            Cleanup.count(job, "bases.protected")
        elseif record.cleanupSkip ~= "safehouse" then
            record.cleanupSkip = "safehouse"
            Cleanup.count(job, "bases.protected")
            local origin = type(record.origin) == "table" and record.origin or {}
            Cleanup.skip(job, "bases", { site = key, x = origin.x, y = origin.y, z = origin.z,
                what = "scene", why = "safehouse" })
        end
        return
    end
    if not ready then
        if not job.run then Cleanup.count(job, "bases.unloaded") end
        return
    end
    if not job.run then
        Cleanup.count(job, "bases.found")
        return
    end
    local removed = kit.removeScene(key, record)
    Cleanup.count(job, "bases.removed", tonumber(removed) or 0)
    Cleanup.count(job, "bases.scenes_removed")
    Cleanup.spend(job, math.max(1, tonumber(removed) or 1))
end

function Scenes.step(job)
    while Cleanup.open(job) do
        local key = job.sceneKeys[job.cursor.scene]
        if key == nil then return true end
        local ok, reason = pcall(Scenes.work, job, key)
        if not ok then Cleanup.fail(job, "scene", reason) end
        job.cursor.scene = job.cursor.scene + 1
        Cleanup.spend(job, 0.5)
    end
    return false
end

function Scenes.pending(job)
    local kit = Scenes.kit()
    if kit == nil then return 0 end
    local count = 0
    for key, record in pairs(kit.placed) do
        if type(record) == "table" and record.cleanupSkip == nil then count = count + 1 end
    end
    return count
end

function Scenes.pendingList(job, limit)
    local kit = Scenes.kit()
    local list = {}
    if kit == nil then return list end
    local keys = {}
    for key, record in pairs(kit.placed) do
        if type(record) == "table" and record.cleanupSkip == nil then keys[#keys + 1] = tostring(key) end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        if #list >= limit then break end
        local origin = kit.placed[key].origin or {}
        list[#list + 1] = { kind = "scene", id = key, x = origin.x, y = origin.y, z = origin.z, left = 1 }
    end
    return list
end

Cleanup.add(Scenes)

local Vehicles = { id = "vehicles", scopes = { "vehicles", "bases" } }
Cleanup.Vehicles = Vehicles

function Vehicles.tagged(vehicle)
    local data = World.dataOf(vehicle)
    if data == nil then return false end
    return data.ProjectALifeOutpostVehicle == true or data.ProjectALife_Setpiece == true
        or data.ProjectALifeSiteId ~= nil
end

function Vehicles.released(vehicle)
    local data = World.dataOf(vehicle)
    local kit = ProjectALife.SceneKit
    if data == nil or data.ProjectALifeSceneKey == nil or kit == nil or type(kit.placed) ~= "table" then return false end
    local record = kit.placed[tostring(data.ProjectALifeSceneKey)]
    return type(record) == "table" and record.state == "released"
end

function Vehicles.begin(job)
    local list = {}
    local cell = World.cell()
    if cell ~= nil and type(cell.getVehicles) == "function" then
        local ok, vehicles = pcall(cell.getVehicles, cell)
        if ok then list = World.items(vehicles, 4096) end
    end
    Cleanup.volatile.vehicles = list
    job.cursor.vehicle = 1
end

function Vehicles.position(vehicle)
    local ok, x, y = pcall(function() return vehicle:getX(), vehicle:getY() end)
    if ok then return tonumber(x), tonumber(y) end
    return nil, nil
end

function Vehicles.work(job, vehicle)
    if not Vehicles.tagged(vehicle) then return end
    local x, y = Vehicles.position(vehicle)
    Cleanup.count(job, "vehicles.found")
    local why
    if x ~= nil and y ~= nil and World.inSafehouse(job, x, y) and not World.overridden(job, nil, "safehouse") then
        why = "safehouse"
    elseif Vehicles.released(vehicle) then why = "released_to_player"
    elseif not World.untouched(vehicle) then why = "vehicle_used" end
    if why ~= nil then
        Cleanup.count(job, "vehicles." .. why)
        local allowed = job.run and why ~= "safehouse" and (job.scopes.unverified == true)
        if not allowed then
            if job.run then
                Cleanup.skip(job, "vehicles", { x = x, y = y, z = 0, what = "vehicle", why = why })
            end
            return
        end
    end
    if not job.run then return end
    local verdict = { vehicle = vehicle }
    local removed, cost = World.removeObjects(job, verdict, nil)
    Cleanup.count(job, "vehicles.removed", removed)
    Cleanup.spend(job, math.max(1, cost))
end

function Vehicles.step(job)
    local list = Cleanup.volatile.vehicles or {}
    while Cleanup.open(job) do
        local vehicle = list[job.cursor.vehicle]
        if vehicle == nil then return true end
        local ok, reason = pcall(Vehicles.work, job, vehicle)
        if not ok then Cleanup.fail(job, "vehicle", reason) end
        job.cursor.vehicle = job.cursor.vehicle + 1
        Cleanup.spend(job, 0.1)
    end
    return false
end

Cleanup.add(Vehicles)

local Area = { id = "area", scopes = { "bases", "corpsesAndLoot" } }
Cleanup.Area = Area

function Area.centers(options)
    local list = {}
    local adapters = Cleanup.adapters
    if type(adapters.players) == "function" then
        local ok, players = pcall(adapters.players)
        if ok and type(players) == "table" then
            for _, p in ipairs(players) do
                local x, y = tonumber(p.x), tonumber(p.y)
                if x ~= nil and y ~= nil then list[#list + 1] = { x = math.floor(x), y = math.floor(y) } end
            end
        end
        return list
    end
    local locator = ProjectALife.PlayerLocator
    if locator ~= nil and type(locator.list) == "function" then
        local ok, players = pcall(locator.list)
        if ok and type(players) == "table" then
            for _, p in ipairs(players) do
                local fine, x, y = pcall(function() return p:getX(), p:getY() end)
                if fine and tonumber(x) ~= nil then list[#list + 1] = { x = math.floor(x), y = math.floor(y) } end
            end
        end
    end
    return list
end

function Area.begin(job)
    job.areaCenters = Area.centers()
    job.cursor.area = 0
    job.areaRadius = tonumber(job.areaRadius) or Cleanup.settings.areaRadius
    job.areaLevels = tonumber(job.areaLevels) or Cleanup.settings.areaLevels
end

function Area.locate(job, index)
    local radius, levels = job.areaRadius, job.areaLevels
    local side = radius * 2 + 1
    local per = side * side * levels
    local center = math.floor(index / per) + 1
    local rest = index % per
    local z = rest % levels
    rest = math.floor(rest / levels)
    local ix = rest % side
    local iy = math.floor(rest / side)
    local c = job.areaCenters[center]
    if c == nil then return nil end
    return c.x - radius + ix, c.y - radius + iy, z
end

function Area.known(object, tag)
    if tag ~= nil then
        local state = Sites.state()
        return state ~= nil and state.sites[tag] ~= nil
    end
    local data = World.dataOf(object)
    local kit = ProjectALife.SceneKit
    local scene = data ~= nil and data.ProjectALifeSceneKey or nil
    return scene ~= nil and kit ~= nil and type(kit.placed) == "table" and kit.placed[tostring(scene)] ~= nil
end

function Area.tagObject(job, square, object, x, y, z)
    local tag, key = World.siteTag(object)
    local data = World.dataOf(object)
    local setpiece = data ~= nil and data.ProjectALife_Setpiece == true
    if tag == nil and not setpiece then return end
    if not job.scopes.bases then return end
    if World.isA(object, "IsoWorldInventoryObject") then return end
    if Area.known(object, tag) then
        Cleanup.count(job, "bases.area_known")
        return
    end
    Cleanup.count(job, "bases.area_found")
    if World.playerBuilt(object) then
        Cleanup.count(job, "bases.area_player_built")
        return
    end
    if World.inSafehouse(job, x, y) and not World.overridden(job, nil, "safehouse") then
        Cleanup.count(job, "bases.area_protected")
        return
    end
    if not job.run then return end
    if World.dropObject(square, object) then
        Cleanup.count(job, "bases.removed")
        Cleanup.count(job, "bases.area_removed")
    else
        Cleanup.fail(job, "area_object", key or "setpiece")
    end
    Cleanup.spend(job, 1)
end

function Area.corpses(job, square, x, y)
    if not job.scopes.corpsesAndLoot or type(square.getDeadBodys) ~= "function" then return end
    local ok, list = pcall(square.getDeadBodys, square)
    if not ok then return end
    for _, body in ipairs(World.items(list, 64)) do
        local data = World.dataOf(body)
        local ours = false
        if data ~= nil then
            for key in pairs(data) do
                if type(key) == "string" and string.sub(key, 1, 11) == "ProjectALif" then ours = true break end
            end
        end
        if ours then
            Cleanup.count(job, "loot.corpses")
            if World.inSafehouse(job, x, y) and not World.overridden(job, nil, "safehouse") then
                Cleanup.count(job, "loot.protected")
            elseif job.run and type(square.removeCorpse) == "function" then
                local fine = pcall(square.removeCorpse, square, body, false)
                if fine then Cleanup.count(job, "loot.removed") else Cleanup.fail(job, "corpse", "removeCorpse") end
                Cleanup.spend(job, 1)
            end
        end
    end
end

function Area.items(job, square, x, y)
    if type(square.getWorldObjects) ~= "function" then return end
    local ok, list = pcall(square.getWorldObjects, square)
    if not ok then return end
    for _, world in ipairs(World.items(list, 64)) do
        local item = nil
        if type(world.getItem) == "function" then
            local fine, held = pcall(world.getItem, world)
            if fine then item = held end
        end
        local data = World.dataOf(item)
        if data ~= nil then
            local site = data.ProjectALifeSiteId ~= nil
            local loot = data.ProjectALifeIssuedCondition ~= nil or data.ALifeLetter ~= nil
            if (site and job.scopes.bases) or (loot and job.scopes.corpsesAndLoot) then
                local prefix = site and "bases" or "loot"
                Cleanup.count(job, prefix .. ".area_items")
                if World.inSafehouse(job, x, y) and not World.overridden(job, nil, "safehouse") then
                    Cleanup.count(job, prefix .. ".protected")
                elseif job.run then
                    local removed = pcall(square.transmitRemoveItemFromSquare, square, world)
                    if removed then Cleanup.count(job, prefix .. ".removed") else Cleanup.fail(job, "ground_item", "remove") end
                    Cleanup.spend(job, 1)
                end
            end
        end
    end
end

function Area.square(job, x, y, z)
    local square = World.square(x, y, z)
    if square == nil then return end
    Cleanup.count(job, "area.squares")
    for _, object in ipairs(World.objectsOf(square)) do
        Area.tagObject(job, square, object, x, y, z)
    end
    Area.corpses(job, square, x, y)
    Area.items(job, square, x, y)
end

function Area.step(job)
    local radius, levels = job.areaRadius, job.areaLevels
    local per = (radius * 2 + 1) * (radius * 2 + 1) * levels
    local total = per * #job.areaCenters
    local done = 0
    while Cleanup.open(job) and done < Cleanup.settings.squaresPerCall do
        local index = job.cursor.area
        if index >= total then return true end
        local x, y, z = Area.locate(job, index)
        if x ~= nil then
            local ok, reason = pcall(Area.square, job, x, y, z)
            if not ok then Cleanup.fail(job, "area", reason) end
        end
        job.cursor.area = index + 1
        done = done + 1
        Cleanup.spend(job, 0.02)
    end
    return job.cursor.area >= total
end

Cleanup.add(Area)

return Sites
