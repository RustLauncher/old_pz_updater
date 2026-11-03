require "ProjectALife/Admin/ALifeCleanup"

ProjectALife = ProjectALife or {}

local Cleanup = ProjectALife.Cleanup

local World = {
    siteTags = { "ProjectALifeSiteId", "ProjectALifeOutpostSite", "ProjectALifeRadioSite" },
    nonObject = { site_survey = true, site_clearance = true, mark_entrance = true, lock_door = true, blood = true },
    itemTags = { "ProjectALifeSiteId", "ProjectALifeIssuedCondition", "ALifeLetter" },
    listCap = 256,
}
Cleanup.World = World

function World.guard(job, where, fn, a, b, c, d)
    local ok, first, second, third = pcall(fn, a, b, c, d)
    if not ok then
        Cleanup.fail(job, where, first)
        return nil
    end
    return first, second, third
end

function World.cell()
    if type(Cleanup.adapters.cell) == "function" then return Cleanup.adapters.cell() end
    if type(getCell) ~= "function" then return nil end
    local ok, cell = pcall(getCell)
    if ok then return cell end
    return nil
end

function World.square(x, y, z)
    local cell = World.cell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return nil end
    local ok, square = pcall(cell.getGridSquare, cell, math.floor(x), math.floor(y), math.floor(z or 0))
    if ok then return square end
    return nil
end

function World.loaded(x, y)
    local builder = ProjectALife.OutpostBuilder
    if builder ~= nil and type(builder.groundLoaded) == "function" then
        local ok, value = pcall(builder.groundLoaded, x, y)
        return ok and value == true
    end
    return World.square(x, y, 0) ~= nil
end

function World.items(list, cap)
    local result = {}
    if list == nil or type(list.size) ~= "function" or type(list.get) ~= "function" then return result end
    local ok, count = pcall(list.size, list)
    if not ok or type(count) ~= "number" then return result end
    cap = cap or World.listCap
    for index = 0, math.min(count, cap) - 1 do
        local fine, value = pcall(list.get, list, index)
        if fine and value ~= nil then result[#result + 1] = value end
    end
    return result
end

function World.objectsOf(square)
    if square == nil or type(square.getObjects) ~= "function" then return {}, false end
    local ok, list = pcall(square.getObjects, square)
    if not ok or list == nil then return {}, false end
    if type(list.size) ~= "function" or not pcall(list.size, list) then return {}, false end
    return World.items(list), true
end

function World.dataOf(object)
    if object == nil or type(object.getModData) ~= "function" then return nil end
    if type(object.hasModData) == "function" then
        local ok, has = pcall(object.hasModData, object)
        if not ok or has ~= true then return nil end
    end
    local ok, data = pcall(object.getModData, object)
    if ok and type(data) == "table" then return data end
    return nil
end

function World.isA(object, class)
    if object == nil or type(instanceof) ~= "function" then return false end
    local ok, value = pcall(instanceof, object, class)
    return ok and value == true
end

function World.spriteName(object)
    if object == nil or type(object.getSprite) ~= "function" then return nil end
    local ok, sprite = pcall(object.getSprite, object)
    if not ok or sprite == nil or type(sprite.getName) ~= "function" then return nil end
    local named, name = pcall(sprite.getName, sprite)
    if named and type(name) == "string" then return name end
    return nil
end

function World.siteTag(object)
    local data = World.dataOf(object)
    if data == nil then return nil end
    for _, key in ipairs(World.siteTags) do
        local value = data[key]
        if value ~= nil then return tostring(value), key end
    end
    return nil
end

function World.playerBuilt(object)
    if not World.isA(object, "IsoThumpable") then return false end
    if type(object.isDismantable) ~= "function" then return false end
    local ok, value = pcall(object.isDismantable, object)
    return ok and value == true
end

function World.safehouses(job)
    if job.safehouseList ~= nil then return job.safehouseList end
    local list = {}
    if type(Cleanup.adapters.safehouses) == "function" then
        local ok, rows = pcall(Cleanup.adapters.safehouses)
        if ok and type(rows) == "table" then list = rows end
    elseif type(SafeHouse) == "table" and type(SafeHouse.getSafehouseList) == "function" then
        local ok, houses = pcall(SafeHouse.getSafehouseList)
        if ok and houses ~= nil then
            for _, house in ipairs(World.items(houses, 512)) do
                local fine, x, y, w, h = pcall(function()
                    return house:getX(), house:getY(), house:getW(), house:getH()
                end)
                if fine and tonumber(x) ~= nil then
                    list[#list + 1] = { x1 = x, y1 = y, x2 = x + (tonumber(w) or 0), y2 = y + (tonumber(h) or 0) }
                end
            end
        end
    end
    job.safehouseList = list
    return list
end

function World.inSafehouse(job, x, y)
    for _, rect in ipairs(World.safehouses(job)) do
        if x >= rect.x1 and x < rect.x2 and y >= rect.y1 and y < rect.y2 then return true end
    end
    return false
end

function World.overridden(job, siteId, flag)
    if not job.run then return false end
    if flag == "safehouse" and job.scopes.safehouses == true then return true end
    local row = siteId ~= nil and job.overrides[siteId] or nil
    return type(row) == "table" and row[flag] == true
end

function World.stacked(spriteName)
    local director = ProjectALife.OutpostDirector
    if director ~= nil and type(director.stackedSprite) == "function" then
        local ok, value = pcall(director.stackedSprite, spriteName)
        if ok then return value end
    end
    return nil
end

function World.openingFits(object, spriteName)
    local director = ProjectALife.OutpostDirector
    if director == nil or type(director.openingMatches) ~= "function" then return false end
    local ok, value = pcall(director.openingMatches, object, spriteName)
    return ok and value == true
end

function World.fits(row, object, name)
    if row.sprite ~= nil then
        if name == row.sprite then return true end
        if row.op == "container" then
            local stacked = World.stacked(row.sprite)
            if stacked ~= nil and name == stacked then return true end
        end
        return World.openingFits(object, row.sprite)
    end
    if row.class ~= nil then return World.isA(object, row.class) end
    return false
end

function World.heldCount(object)
    if object == nil or type(object.getContainer) ~= "function" then return 0 end
    local ok, container = pcall(object.getContainer, object)
    if not ok or container == nil or type(container.getItems) ~= "function" then return 0 end
    local got, items = pcall(container.getItems, container)
    if not got or items == nil or type(items.size) ~= "function" then return 0 end
    local counted, count = pcall(items.size, items)
    if counted and type(count) == "number" then return count end
    return 0
end

function World.expectedHeld(site, row)
    for _, entry in ipairs(type(site.containers) == "table" and site.containers or {}) do
        if type(entry) == "table" and tonumber(entry.x) == tonumber(row.x) and tonumber(entry.y) == tonumber(row.y)
                and (tonumber(entry.z) or 0) == (tonumber(row.z) or 0) then
            return tonumber(entry.expected) or 0
        end
    end
    return nil
end

function World.dropObject(square, object)
    local director = ProjectALife.OutpostDirector
    if director ~= nil and type(director.dropObject) == "function" then
        local ok, gone = pcall(director.dropObject, square, object)
        return ok and gone == true
    end
    if type(square.transmitRemoveItemFromSquare) == "function" then
        pcall(square.transmitRemoveItemFromSquare, square, object)
    end
    return true
end

function World.inspectGeneric(job, site, row, square)
    local tagged, plain, foreign = {}, {}, 0
    local objects, readable = World.objectsOf(square)
    if not readable then return { state = "unreadable" } end
    for _, object in ipairs(objects) do
        local name = World.spriteName(object)
        local tag = World.siteTag(object)
        local fits = World.fits(row, object, name)
        if tag ~= nil and tag == tostring(site.id) then
            if fits then tagged[#tagged + 1] = object end
        elseif fits then
            if tag ~= nil then foreign = foreign + 1 else plain[#plain + 1] = object end
        end
    end
    if #tagged > 0 then return { state = "ours", how = "tag", objects = tagged, square = square } end
    if #plain == 0 then
        if foreign > 0 then return { state = "foreign", why = "other_site_object" } end
        return { state = "gone" }
    end
    if row.sid == true then return { state = "unverified", why = "replaced_after_build", objects = plain, square = square } end
    local built = 0
    for _, object in ipairs(plain) do
        if World.playerBuilt(object) then built = built + 1 end
    end
    if built > 0 then return { state = "unverified", why = "player_built", objects = plain, square = square } end
    if #plain >= 2 then return { state = "unverified", why = "ambiguous_stack", objects = plain, square = square } end
    return { state = "ours", how = "journal", objects = plain, square = square }
end

function World.inspectBarricade(job, site, row, square)
    local found = {}
    local steps = { { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    local class = row.op == "barricade_window" and "IsoWindow" or "IsoDoor"
    local plain = 0
    for _, step in ipairs(steps) do
        local near = World.square(row.x + step[1], row.y + step[2], row.z or 0)
        if near ~= nil then
            for _, object in ipairs(World.objectsOf(near)) do
                local fits = World.isA(object, class)
                if fits and row.north ~= nil and type(object.getNorth) == "function" then
                    local ok, north = pcall(object.getNorth, object)
                    fits = ok and (north == true) == (row.north == true)
                end
                if fits then
                    for _, getter in ipairs({ "getBarricadeOnSameSquare", "getBarricadeOnOppositeSquare" }) do
                        if type(object[getter]) == "function" then
                            local ok, barricade = pcall(object[getter], object)
                            if ok and barricade ~= nil then
                                local tag = World.siteTag(barricade)
                                if tag == tostring(site.id) then
                                    found[#found + 1] = { barricade = barricade, square = near }
                                else
                                    plain = plain + 1
                                end
                            end
                        end
                    end
                end
            end
        end
        if #found > 0 or (row.north ~= nil and step[1] == 0 and step[2] == 0) then break end
    end
    if #found > 0 then return { state = "ours", how = "tag", barricades = found, square = square } end
    if plain > 0 then return { state = "unverified", why = "barricade_untagged", square = square } end
    return { state = "gone" }
end

function World.inspectVehicle(job, site, row, square)
    if type(square.getVehicleContainer) ~= "function" then return { state = "gone" } end
    local ok, vehicle = pcall(square.getVehicleContainer, square)
    if not ok or vehicle == nil then return { state = "gone" } end
    local data = World.dataOf(vehicle)
    local tag = data ~= nil and (data.ProjectALifeOutpostVehicleSite or data.ProjectALifeSiteId) or nil
    if tag == nil or tostring(tag) ~= tostring(site.id) then return { state = "foreign", why = "vehicle_not_tagged" } end
    if not World.untouched(vehicle) then return { state = "unverified", why = "vehicle_used", vehicle = vehicle, square = square } end
    return { state = "ours", how = "tag", vehicle = vehicle, square = square }
end

function World.untouched(vehicle)
    local scene = ProjectALife.SceneKit
    if scene ~= nil and type(scene.untouched) == "function" then return scene.untouched(vehicle) == true end
    local ok, value = pcall(function()
        return vehicle:isPreviouslyEntered() == false and vehicle:isPreviouslyMoved() == false
    end)
    return ok and value == true
end

function World.inspectItems(job, site, row, square)
    if type(square.getWorldObjects) ~= "function" then return { state = "gone" } end
    local ok, list = pcall(square.getWorldObjects, square)
    if not ok then return { state = "gone" } end
    local found, plain = {}, 0
    for _, world in ipairs(World.items(list)) do
        local item = nil
        if type(world.getItem) == "function" then
            local fine, held = pcall(world.getItem, world)
            if fine then item = held end
        end
        local data = World.dataOf(item)
        if data ~= nil and tostring(data.ProjectALifeSiteId or "") == tostring(site.id) then
            found[#found + 1] = world
        elseif row.item ~= nil and item ~= nil and type(item.getFullType) == "function" then
            local named, full = pcall(item.getFullType, item)
            if named and full == row.item then plain = plain + 1 end
        end
    end
    if #found > 0 then return { state = "ours", how = "tag", worldItems = found, square = square } end
    if plain > 0 then return { state = "unverified", why = "ground_item_untagged", square = square } end
    if row.item == nil and #World.items(list) > 0 then return { state = "unverified", why = "ground_item_unidentified", square = square } end
    return { state = "gone" }
end

function World.inspectRow(job, site, row)
    local x, y = tonumber(row.x), tonumber(row.y)
    if x == nil or y == nil then return { state = "gone", why = "no_position" } end
    local z = math.floor(tonumber(row.z) or 0)
    local op = row.op
    if World.nonObject[op] then return { state = "gone", why = "not_an_object" } end
    if row.reuse == true then return { state = "foreign", why = "pre_existing_door" } end
    if not World.loaded(x, y) then return { state = "unloaded" } end
    local square = World.square(x, y, z)
    if square == nil then
        if z == 0 then return { state = "unloaded" } end
        return { state = "gone", why = "no_square" }
    end
    local verdict
    if op == "barricade_door" or op == "barricade_window" then
        verdict = World.inspectBarricade(job, site, row, square)
    elseif row.class == "BaseVehicle" then
        verdict = World.inspectVehicle(job, site, row, square)
    elseif row.class == "IsoAnimal" then
        verdict = { state = "gone", why = "animal_sweep" }
    elseif op == "items" then
        verdict = World.inspectItems(job, site, row, square)
    else
        verdict = World.inspectGeneric(job, site, row, square)
        if verdict.state == "ours" and op == "container" then
            local expected = World.expectedHeld(site, row)
            local held = World.heldCount(verdict.objects[1])
            if expected ~= nil and held > expected then
                verdict = { state = "unverified", why = "container_holds_more_than_issued",
                    objects = verdict.objects, square = square }
            end
        end
    end
    if row.recon == true and row.op == "door" and verdict.state == "ours" and verdict.how ~= "tag" then
        verdict = { state = "unverified", why = "door_may_be_original", objects = verdict.objects, square = square }
    end
    verdict.x, verdict.y, verdict.z = x, y, z
    if (verdict.state == "ours" or verdict.state == "unverified") and World.inSafehouse(job, x, y)
            and not World.overridden(job, site.id, "safehouse") then
        return { state = "protected", why = "safehouse", x = x, y = y, z = z }
    end
    return verdict
end

function World.allowed(job, site, verdict)
    if verdict.state == "ours" then return true end
    if verdict.state ~= "unverified" then return false end
    local why = verdict.why
    if why == "player_built" then return World.overridden(job, site.id, "playerBuilt") end
    if why == "container_holds_more_than_issued" or why == "ambiguous_stack" or why == "replaced_after_build"
            or why == "vehicle_used" or why == "barricade_untagged" or why == "ground_item_untagged" then
        return job.scopes.unverified == true or World.overridden(job, site.id, "unverified")
    end
    return false
end

function World.removeObjects(job, verdict, row)
    local removed, cost = 0, 0
    local square = verdict.square
    if verdict.vehicle ~= nil then
        local vehicle = verdict.vehicle
        if type(vehicle.permanentlyRemove) == "function" then
            local ok = pcall(vehicle.permanentlyRemove, vehicle)
            if ok then removed = removed + 1 else Cleanup.fail(job, "vehicle", "permanentlyRemove") end
        end
        return removed, 1
    end
    for _, entry in ipairs(verdict.barricades or {}) do
        local target = entry.barricade
        local home = entry.square
        local ok = pcall(function()
            home:transmitRemoveItemFromSquare(target)
            if type(home.RemoveTileObject) == "function" then home:RemoveTileObject(target) end
        end)
        if ok then removed = removed + 1 else Cleanup.fail(job, "barricade", "remove") end
        cost = cost + 1
    end
    for _, world in ipairs(verdict.worldItems or {}) do
        local ok = pcall(function() square:transmitRemoveItemFromSquare(world) end)
        if ok then removed = removed + 1 else Cleanup.fail(job, "ground_item", "remove") end
        cost = cost + 1
    end
    local objects = verdict.objects or {}
    if verdict.why == "ambiguous_stack" and #objects > 1 then objects = { objects[1] } end
    for _, object in ipairs(objects) do
        if row ~= nil and row.op == "campfire" then
            local director = ProjectALife.OutpostDirector
            if director ~= nil and type(director.drainCampfire) == "function" then
                pcall(director.drainCampfire, square, row)
            end
        end
        if World.dropObject(square, object) then removed = removed + 1
        else Cleanup.fail(job, "object", "remove_failed") end
        cost = cost + 1
    end
    if row ~= nil and row.op == "floor" and removed > 0 and type(row.restore) == "string"
            and math.floor(tonumber(row.z) or 0) == 0 and type(square.addFloor) == "function" then
        local current = nil
        if type(square.getFloor) == "function" then
            local ok, floor = pcall(square.getFloor, square)
            if ok then current = floor end
        end
        if current == nil then
            local ok = pcall(square.addFloor, square, row.restore)
            if ok then Cleanup.count(job, "bases.floors_restored") end
            cost = cost + 1
        end
    end
    return removed, cost
end

function World.describe(row, verdict)
    return { x = verdict.x or row.x, y = verdict.y or row.y, z = verdict.z or row.z,
        what = tostring(row.sprite or row.class or row.op), why = verdict.why }
end

return World
