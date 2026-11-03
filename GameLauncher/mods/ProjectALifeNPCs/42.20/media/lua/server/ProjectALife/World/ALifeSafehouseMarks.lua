require "ProjectALife/World/ALifeSafehouseFx"
require "ProjectALife/World/ALifeSafehouseDoor"

ProjectALife = ProjectALife or {}

local Fx = ProjectALife.SafehouseFx
local Marks = {
    settings = { cap = 4, ageDays = 10, reach = 3, debtCap = 32, debtTries = 2 },
}
ProjectALife.SafehouseMarks = Marks

Marks.sprites = {
    paint_x = { prefix = "overlay_graffiti_wall_02_", n = { 4 }, w = { 36 }, tint = { 0.63, 0.10, 0.10, 1.0 } },
    tally = { prefix = "overlay_graffiti_wall_02_", n = { 14 }, w = { 46 } },
    flag = { prefix = "overlay_graffiti_wall_02_", n = { 6 }, w = { 38 } },
    kind = { prefix = "overlay_graffiti_wall_02_", n = { 2 }, w = { 34 } },
    food = { prefix = "overlay_graffiti_wall_02_", n = { 5 }, w = { 37 } },
    armed = { prefix = "overlay_graffiti_wall_02_", n = { 7 }, w = { 39 } },
    blood = { prefix = "overlay_blood_wall_01_", n = { 14, 22, 38, 46 }, w = { 9, 17, 33, 41 } },
}

function Marks.rand(count)
    local director = ProjectALife.SafehouseDirector
    if director ~= nil and type(director.rand) == "function" then return director.rand(count) end
    return 0
end

function Marks.spriteFor(kind, north)
    local entry = Marks.sprites[kind]
    if entry == nil then return nil, nil end
    local list = north and entry.n or entry.w
    return entry.prefix .. tostring(list[1 + Marks.rand(#list)]), entry.tint
end

function Marks.record(house)
    house.wallMarks = type(house.wallMarks) == "table" and house.wallMarks or {}
    return house.wallMarks
end

function Marks.alongEdges(list, sx, sy, ix, iy, z, offsets, base)
    local north = (ix - sx) == 0
    local ax, ay = 0, 1
    if north then ax, ay = 1, 0 end
    for _, step in ipairs(offsets) do
        local edge = { ox = sx + ax * step, oy = sy + ay * step, ix = ix + ax * step, iy = iy + ay * step, z = z or 0,
            north = north }
        local visible = false
        if north then visible = edge.oy > edge.iy else visible = edge.ox > edge.ix end
        edge.visible = visible
        edge.score = base - math.abs(step) * 4 + (visible and 12 or 0)
        list[#list + 1] = edge
    end
end

function Marks.edgesFor(house)
    local list = {}
    local door = type(house.door) == "table" and house.door or nil
    if door == nil then return list end
    if tonumber(door.sx) ~= nil and tonumber(door.sy) ~= nil and tonumber(door.ix) ~= nil and tonumber(door.iy) ~= nil then
        Marks.alongEdges(list, door.sx, door.sy, door.ix, door.iy, door.z, { 1, -1, 2, -2, 3, -3, 4, -4, 5, -5 }, 40)
    end
    local windows = type(door.windows) == "table" and door.windows or {}
    for index = 1, math.min(3, #windows) do
        local item = windows[index]
        if type(item) == "table" and tonumber(item.x) ~= nil and tonumber(item.ix) ~= nil then
            Marks.alongEdges(list, item.x, item.y, item.ix, item.iy, item.z, { 1, -1, 2, -2 }, 30)
        end
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.ox ~= b.ox then return a.ox < b.ox end
        return a.oy < b.oy
    end)
    return list
end

function Marks.owner(edge)
    local door = ProjectALife.SafehouseDoor
    local outsideOwns
    if edge.north then outsideOwns = edge.oy > edge.iy else outsideOwns = edge.ox > edge.ix end
    if outsideOwns then return door.square(edge.ox, edge.oy, edge.z) end
    return door.square(edge.ix, edge.iy, edge.z)
end

function Marks.openingOn(objects, north)
    for _, object in ipairs(objects) do
        local opening = Fx.isKind(object, "IsoWindow") or Fx.isKind(object, "IsoDoor")
            or (Fx.isKind(object, "IsoThumpable") and Fx.ask(object, "isDoor") == true)
        if opening then
            local facing = Fx.ask(object, "getNorth")
            if facing == nil or facing == north then return true end
        end
    end
    return false
end

function Marks.wallObject(square, north, anyOverlay)
    local flag = north and "WallN" or "WallW"
    local objects = Fx.items(Fx.ask(square, "getObjects"), 32)
    if Marks.openingOn(objects, north) and anyOverlay ~= true then return nil, "opening" end
    local found, why = nil, "no_wall"
    for _, object in ipairs(objects) do
        local props = Fx.ask(object, "getProperties")
        if props ~= nil and Fx.ask(props, "has", flag) == true and Fx.ask(object, "isDoor") ~= true then
            if anyOverlay ~= true and Fx.ask(object, "hasOverlaySprite") == true then
                why = "occupied"
            else
                found = object
                break
            end
        end
    end
    return found, why
end

function Marks.keyOf(x, y, z, north)
    return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z) .. (north and "N" or "W")
end

function Marks.taken(house)
    local result = {}
    for _, entry in ipairs(Marks.record(house)) do
        result[Marks.keyOf(entry.x, entry.y, entry.z, entry.north)] = true
    end
    return result
end

function Marks.apply(object, name, tint)
    if type(object.setOverlaySprite) ~= "function" then return false end
    local ok
    if tint ~= nil then
        ok = pcall(object.setOverlaySprite, object, name, tint[1], tint[2], tint[3], tint[4])
    else
        ok = pcall(object.setOverlaySprite, object, name)
    end
    return ok and Fx.ask(object, "hasOverlaySprite") == true
end

function Marks.find(house)
    local edges = Marks.edgesFor(house)
    if #edges == 0 then return nil, "no_entrance" end
    local taken, reasons = Marks.taken(house), {}
    for _, edge in ipairs(edges) do
        local square = Marks.owner(edge)
        if square == nil then
            reasons.unloaded = true
        else
            local x, y = Fx.ask(square, "getX"), Fx.ask(square, "getY")
            if tonumber(x) == nil or tonumber(y) == nil then
                reasons.unloaded = true
            elseif taken[Marks.keyOf(x, y, edge.z, edge.north)] == true then
                reasons.taken = true
            else
                local object, why = Marks.wallObject(square, edge.north, false)
                if object ~= nil then return { object = object, edge = edge, x = x, y = y, z = edge.z, north = edge.north,
                    visible = edge.visible }, nil end
                reasons[why or "no_wall"] = true
            end
        end
    end
    for _, name in ipairs({ "unloaded", "taken", "occupied", "opening" }) do
        if reasons[name] == true then return nil, name end
    end
    return nil, "no_wall"
end

function Marks.dry(house)
    local found, why = Marks.find(house)
    if found == nil then return false, why end
    return true, found
end

function Marks.place(house, kind, now, info)
    if not Fx.optionOn("wallMarks") then
        Fx.refuse("option_off")
        return nil, "option_off"
    end
    if Marks.sprites[kind] == nil then
        Fx.refuse("no_sprite")
        return nil, "no_sprite"
    end
    local found, why = Marks.find(house)
    local list = Marks.record(house)
    if found == nil and #list >= Marks.settings.cap and why ~= "no_entrance" then
        Marks.drop(house, table.remove(list, 1))
        found, why = Marks.find(house)
    end
    if found == nil then
        Fx.refuse(why)
        return nil, why
    end
    local name, tint = Marks.spriteFor(kind, found.north)
    local dedicated = type(isServer) == "function" and isServer() == true
    if type(getTexture) == "function" and not dedicated then
        local readable, texture = pcall(getTexture, name)
        if readable and texture == nil then
            Fx.refuse("no_texture")
            return nil, "no_texture"
        end
    end
    while #list >= Marks.settings.cap do Marks.drop(house, table.remove(list, 1)) end
    if not Marks.apply(found.object, name, tint) then
        Fx.refuse("not_applied")
        return nil, "not_applied"
    end
    local entry = { x = found.x, y = found.y, z = found.z, north = found.north, sprite = name, kind = kind,
        atHours = now, visible = found.visible }
    list[#list + 1] = entry
    Fx.count("marksPlaced")
    Fx.count("scriptedEffects")
    return entry, nil
end

function Marks.remove(entry)
    local door = ProjectALife.SafehouseDoor
    local square = door.square(entry.x, entry.y, entry.z or 0)
    if square == nil then return nil end
    local object = Marks.wallObject(square, entry.north == true, true)
    if object == nil then return false end
    if Fx.ask(object, "hasOverlaySprite") ~= true then return false end
    local sprite = Fx.ask(object, "getOverlaySprite")
    local name = Fx.field(sprite, "name")
    if type(name) == "string" and name ~= entry.sprite then return false end
    if type(object.setOverlaySprite) ~= "function" or not pcall(object.setOverlaySprite, object, "") then return nil end
    Fx.count("marksRemoved")
    return true
end

function Marks.drop(house, entry)
    local result = Marks.remove(entry)
    if result == nil then
        local director = ProjectALife.SafehouseDirector
        local store = director ~= nil and director.store() or nil
        if store ~= nil then
            store.markDebt = type(store.markDebt) == "table" and store.markDebt or {}
            if #store.markDebt < Marks.settings.debtCap then
                store.markDebt[#store.markDebt + 1] = { x = entry.x, y = entry.y, z = entry.z, north = entry.north,
                    sprite = entry.sprite, atHours = entry.atHours }
            end
            if type(director.dirty) == "function" then director.dirty() end
        end
    end
    return result
end

function Marks.clean(house)
    local list = type(house) == "table" and type(house.wallMarks) == "table" and house.wallMarks or {}
    local removed = 0
    for index = #list, 1, -1 do
        if Marks.drop(house, table.remove(list, index)) == true then removed = removed + 1 end
    end
    return removed
end

function Marks.count(house)
    return type(house) == "table" and type(house.wallMarks) == "table" and #house.wallMarks or 0
end

function Marks.tick(now)
    local director = ProjectALife.SafehouseDirector
    if director == nil or director.metrics == nil or director.metrics.ticks % 10 ~= 0 then return 0 end
    local worked = 0
    local limit = Marks.settings.ageDays * 24
    for _, key in ipairs(director.houseList()) do
        local list = director.store().houses[key].wallMarks
        if type(list) == "table" then
            for index = #list, 1, -1 do
                if now - (tonumber(list[index].atHours) or now) > limit then
                    Marks.drop(director.store().houses[key], table.remove(list, index))
                    worked = worked + 1
                end
            end
        end
    end
    local debt = director.store().markDebt
    if type(debt) == "table" then
        local tried = 0
        for index = #debt, 1, -1 do
            if tried >= Marks.settings.debtTries then break end
            tried = tried + 1
            local entry = debt[index]
            if Marks.remove(entry) ~= nil or now - (tonumber(entry.atHours) or now) > limit + 72 then
                table.remove(debt, index)
                worked = worked + 1
            end
        end
    end
    return worked
end

return Marks
