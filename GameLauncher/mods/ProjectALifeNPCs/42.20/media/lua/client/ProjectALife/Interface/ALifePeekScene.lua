require "ProjectALife/Interface/ALifePeekDoorData"
require "ProjectALife/Interface/ALifePeekSceneData"

ProjectALife = ProjectALife or {}

local Data = ProjectALife.PeekData
local SD = ProjectALife.PeekSceneData
local Scene = {
    textures = {}, classes = {}, blockers = {}, opaque = {}, shapes = {}, texCount = 0,
    metrics = { builds = 0, sprites = 0, missing = 0, hidden = 0, faults = 0, unloaded = 0 },
}
ProjectALife.PeekScene = Scene

function Scene.ask(object, name, argument)
    local kind = type(object)
    if object == nil or kind == "number" or kind == "string" or kind == "boolean" then return nil end
    local method = object[name]
    if type(method) ~= "function" then return nil end
    local ok, value
    if argument == nil then
        ok, value = pcall(method, object)
    else
        ok, value = pcall(method, object, argument)
    end
    if ok then return value end
    return nil
end

function Scene.tileScale()
    if type(Core) == "table" and type(Core.getTileScale) == "function" then
        local ok, value = pcall(Core.getTileScale)
        if ok and type(value) == "number" and value >= 1 then return value end
    end
    return 2
end

function Scene.squareAt(x, y, z)
    local cell = type(getCell) == "function" and getCell() or nil
    if cell == nil or type(cell.getGridSquare) ~= "function" then return nil end
    return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z))
end

function Scene.texture(name)
    if type(name) ~= "string" or name == "" then return nil end
    local cached = Scene.textures[name]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    if type(getTexture) ~= "function" then return nil end
    if Scene.texCount >= SD.textureCap then
        Scene.textures, Scene.texCount = {}, 0
    end
    Scene.texCount = Scene.texCount + 1
    local ok, texture = pcall(getTexture, name)
    if ok and texture ~= nil then
        Scene.textures[name] = texture
        return texture
    end
    Scene.textures[name] = false
    return nil
end

function Scene.dims(texture, name)
    local shape = Scene.shapes[name]
    if shape == nil then
        local wo, ho, l, t, r, b = SD.trim(Scene.ask(texture, "getWidthOrig"), Scene.ask(texture, "getHeightOrig"),
            Scene.ask(texture, "getWidth"), Scene.ask(texture, "getHeight"), Scene.ask(texture, "getOffsetX"),
            Scene.ask(texture, "getOffsetY"))
        shape = false
        if wo ~= nil then shape = { wo, ho, l, t, r, b } end
        Scene.shapes[name] = shape
    end
    if shape == false then return nil end
    return shape[1], shape[2], shape[3], shape[4], shape[5], shape[6]
end

function Scene.nameOf(object)
    local name = Scene.ask(object, "getTextureName")
    if type(name) == "string" and name ~= "" then return name end
    name = Scene.ask(object, "getSpriteName")
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

function Scene.propsOf(object)
    return Scene.ask(Scene.ask(object, "getSprite"), "getProperties")
end

function Scene.classOf(object, name)
    local cached = Scene.classes[name]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local props = Scene.propsOf(object)
    local kind = SD.classify(props, IsoFlagType)
    Scene.classes[name] = kind or false
    Scene.blockers[name] = kind ~= nil and SD.has(props, "blocksight", IsoFlagType)
    Scene.opaque[name] = kind ~= nil and SD.anyFlag(props, SD.opaqueFlags, IsoFlagType)
    return kind
end

function Scene.skipObject(object)
    if type(instanceof) ~= "function" then return false end
    return instanceof(object, "IsoWorldInventoryObject") == true or instanceof(object, "IsoDeadBody") == true
end

function Scene.take(scene)
    local used = scene.used + 1
    local entry = scene.pool[used]
    if entry == nil then
        entry = { q = {} }
        scene.pool[used] = entry
    end
    scene.used = used
    entry.tex, entry.front = nil, false
    return entry
end

function Scene.give(scene)
    scene.used = scene.used - 1
end

function Scene.open(window)
    local geo, view, cells = window.geo, window.view, window.cells
    local scene = { tiles = {}, order = {}, pool = {}, used = 0, orderCount = 0, occ = {}, occCount = 0, builtAt = 0 }
    scene.scale = Scene.tileScale()
    scene.ppuH, scene.ppuV = SD.units(scene.scale)
    for index = 1, #cells do
        local spec = cells[index]
        local tile = { kind = "tile", rank = 1, wx = spec[1], wy = spec[2], k = spec[3], c = spec[4], n = index, q = {}, a = 1,
            key = SD.tileKey(spec[3]), span = math.abs(spec[4]), r = 0.5, g = 0.5, b = 0.5 }
        tile.geometry = SD.floorQuad(view, geo, tile.wx, tile.wy, tile.q) and SD.bounds(tile.q, view)
        scene.tiles[index] = tile
    end
    scene.hazes = {}
    local depth = window.depth or Data.liveDepth
    for j = 1, depth - 1 do
        local y = math.min(view.h, math.max(0, math.ceil(SD.groundY(view, j))))
        scene.hazes[j] = { kind = "haze", rank = 0, key = SD.hazeKey(j), span = 0, n = 1000 + j, y = y, r = 0.5, g = 0.5, b = 0.5, a = 0 }
    end
    window.scene = scene
    window.sceneNext = 0
    return scene
end

function Scene.edgeCull(depthA, depthB)
    return math.min(depthA, depthB) + Data.eyeBack < 0.35
end

function Scene.addObject(window, scene, tile, object, name, tr, tg, tb)
    if name == nil or Scene.skipObject(object) then return nil end
    local kind = Scene.classOf(object, name)
    if kind == nil then return nil end
    local texture = Scene.texture(name)
    if texture == nil then
        Scene.metrics.missing = Scene.metrics.missing + 1
        return nil
    end
    local wo, ho, l, t, r, b = Scene.dims(texture, name)
    if wo == nil then return nil end
    local geo, view = window.geo, window.view
    local entry = Scene.take(scene)
    local q = entry.q
    local wx, wy = tile.wx, tile.wy
    local ok = false
    local rank, key = 3, tile.key
    if kind == "floor2" then
        ok = SD.floorQuad(view, geo, wx, wy, q, wo, ho, l, t, r, b)
        rank, key = 2, tile.key - 0.01
    elseif kind == "edgeN" or kind == "edgeW" then
        local west = kind == "edgeW"
        local ex, ey = wx + 1, wy
        if west then ex, ey = wx, wy + 1 end
        local depthA, lateralA = Data.coords(geo, wx, wy)
        local depthB, lateralB = Data.coords(geo, ex, ey)
        if Scene.edgeCull(depthA, depthB) then
            Scene.give(scene)
            return nil
        end
        ok = SD.edgeQuad(view, geo, wx, wy, west, q, wo, ho, l, t, r, b, scene.ppuV)
        key = (depthA + depthB) / 2
        entry.edgeA, entry.edgeB, entry.lateralA, entry.lateralB = depthA, depthB, lateralA, lateralB
    elseif kind == "cornerNW" then
        ok = SD.billQuad(view, geo, wx, wy, q, wo / 2, ho - wo / 2, scene.ppuH, scene.ppuV, l, t, r, b)
        key = (Data.coords(geo, wx, wy))
    elseif kind == "cornerSE" then
        ok = SD.billQuad(view, geo, wx + 1, wy + 1, q, wo / 2, ho, scene.ppuH, scene.ppuV, l, t, r, b)
        key = (Data.coords(geo, wx + 1, wy + 1))
    else
        ok = SD.billQuad(view, geo, wx + 0.5, wy + 0.5, q, wo / 2, ho - wo / 4, scene.ppuH, scene.ppuV, l, t, r, b)
        rank = 4
    end
    if not ok or not SD.bounds(q, view) then
        Scene.give(scene)
        return nil
    end
    entry.kind, entry.rank, entry.key, entry.span, entry.n = kind, rank, key, tile.span, 100 + scene.used
    entry.tex, entry.r, entry.g, entry.b, entry.a = texture, tr, tg, tb, 1
    entry.perpendicular = (kind == "edgeN" or kind == "edgeW") and Scene.opaque[name] == true
    return entry
end

function Scene.sampleTile(window, scene, tile, tr, tg, tb)
    local square = Scene.squareAt(tile.wx, tile.wy, window.geo.z)
    tile.loaded = square ~= nil
    tile.draw, tile.tex = false, nil
    if square == nil then
        Scene.metrics.unloaded = Scene.metrics.unloaded + 1
        return nil
    end
    local depth, lateral = tile.k + 0.5, tile.c
    if SD.shadowed(scene.occ, scene.occCount, depth, lateral) then
        scene.hidden = scene.hidden + 1
        return nil
    end
    local ownBlock, blocker = false, false
    local first = scene.used + 1
    local objects = Scene.ask(square, "getObjects")
    local size = tonumber(Scene.ask(objects, "size")) or 0
    local limit = math.min(size - 1, SD.perSquare)
    for slot = 1, limit do
        if scene.used >= SD.maxSprites then break end
        local object = Scene.ask(objects, "get", slot)
        if object ~= nil then
            local name = Scene.nameOf(object)
            local entry = Scene.addObject(window, scene, tile, object, name, tr, tg, tb)
            if entry ~= nil and entry.perpendicular == true then
                if math.abs(entry.edgeA - entry.edgeB) <= 0.05 and entry.edgeA <= tile.k + 0.05 then ownBlock = true end
            end
            if name ~= nil and Scene.blockers[name] == true then blocker = true end
        end
    end
    if ownBlock then
        for index = scene.used, first, -1 do
            local entry = scene.pool[index]
            if entry.kind ~= "edgeN" and entry.kind ~= "edgeW" then
                entry.tex, entry.dead = nil, true
            end
        end
        scene.hidden = scene.hidden + 1
    end
    for index = first, scene.used do
        local entry = scene.pool[index]
        if entry.dead == true then
            entry.dead = nil
        elseif entry.perpendicular == true then
            scene.occCount = SD.edgeOccluder(scene.occ, scene.occCount, entry.edgeA, entry.lateralA, entry.edgeB, entry.lateralB)
        end
    end
    if blocker then scene.occCount = SD.cellOccluder(scene.occ, scene.occCount, tile.k, tile.c) end
    if not ownBlock then
        local floor = Scene.ask(square, "getFloor")
        local name = Scene.nameOf(floor)
        local texture = Scene.texture(name)
        tile.tex, tile.name = texture, name
        if texture ~= nil then
            tile.r, tile.g, tile.b = tr, tg, tb
        else
            tile.r, tile.g, tile.b = Data.groundColor(Data.floorKind(name), tile.k + 0.5, window.light, window.overcast)
            if window.lens == true and window.grade ~= nil then
                tile.r, tile.g, tile.b = tile.r * tr, tile.g * tg, tile.b * tb
            end
        end
        tile.draw = tile.geometry == true
    end
    return true
end

function Scene.build(window, now)
    local scene = window.scene
    if scene == nil then return false end
    scene.used, scene.occCount, scene.hidden = 0, 0, 0
    local tr, tg, tb = SD.tint(window.light or 0.6, window.overcast or 0, window.ar, window.ag, window.ab)
    local grade = nil
    if window.lens == true then grade = window.grade end
    if grade ~= nil then tr, tg, tb = grade.tr, grade.tg, grade.tb end
    local tiles = scene.tiles
    for index = 1, #tiles do
        Scene.sampleTile(window, scene, tiles[index], tr, tg, tb)
    end
    local order, count = scene.order, 0
    for index = 1, #tiles do
        if tiles[index].draw == true then
            count = count + 1
            order[count] = tiles[index]
        end
    end
    for index = 1, scene.used do
        local entry = scene.pool[index]
        if entry.tex ~= nil then
            count = count + 1
            order[count] = entry
        end
    end
    local hr, hg, hb = Data.skyColor(1, window.light or 0.6, window.overcast or 0)
    if grade ~= nil then hr, hg, hb = grade.fr, grade.fg, grade.fb end
    local alpha = SD.hazeAlpha(window.overcast or 0)
    for j = 1, #scene.hazes do
        local haze = scene.hazes[j]
        haze.r, haze.g, haze.b, haze.a = hr, hg, hb, alpha
        count = count + 1
        order[count] = haze
    end
    for index = #order, count + 1, -1 do order[index] = nil end
    table.sort(order, SD.paint)
    scene.orderCount, scene.builtAt = count, now or 0
    Scene.metrics.builds = Scene.metrics.builds + 1
    Scene.metrics.sprites = scene.used
    Scene.metrics.hidden = scene.hidden
    Scene.layers(window, window.figs)
    return true
end

function Scene.tick(window, now)
    if window.live ~= true or window.scene == nil then return false end
    if now < (window.sceneNext or 0) then return false end
    window.sceneNext = now + SD.sceneMs
    return Scene.build(window, now)
end

function Scene.hidden(window, depth, lateral)
    local scene = window.scene
    if window.live ~= true or scene == nil then return false end
    return SD.shadowed(scene.occ, scene.occCount, depth, lateral)
end

function Scene.layers(window, figs)
    local scene = window.scene
    if scene == nil or type(figs) ~= "table" then return 0 end
    local order, count, moved = scene.order, scene.orderCount, 0
    for index = 1, count do
        local entry = order[index]
        entry.front = false
        if entry.kind ~= "tile" and entry.kind ~= "haze" then
            for slot = 1, #figs do
                local fig = figs[slot]
                local e = fig.entry
                if fig.slot ~= nil and e ~= nil and fig.depth > entry.key
                        and SD.overlaps(entry.q, e.x - e.w / 2, e.y - e.h, e.w, e.h) then
                    entry.front = true
                    moved = moved + 1
                    break
                end
            end
        end
    end
    return moved
end

function Scene.figureDue(fig, front)
    if fig.slot ~= nil then return false end
    if front then return fig.layer == "top" end
    return fig.layer ~= "top"
end

function Scene.entryDue(entry, front)
    if front then return entry.front == true end
    return entry.front ~= true
end

function Scene.drawEntry(window, entry)
    if entry.kind == "haze" then
        window:drawRect(0, 0, window.view.w, entry.y, entry.a, entry.r, entry.g, entry.b)
        return
    end
    local q = entry.q
    if entry.tex ~= nil then
        window:drawTextureAllPoint(entry.tex, q[1], q[2], q[3], q[4], q[5], q[6], q[7], q[8], entry.r, entry.g, entry.b, entry.a)
    else
        window:drawPolygon(nil, q[1], q[2], q[3], q[4], q[5], q[6], q[7], q[8], entry.r, entry.g, entry.b, entry.a)
    end
end

function Scene.base(window)
    local view = window.view
    local top = math.floor(view.horizon)
    local r, g, b = Data.groundColor("paved", Data.liveDepth, window.light or 0.6, window.overcast or 0)
    window:drawRect(0, top, view.w, view.h - top, 1, r, g, b)
end

function Scene.draw(window, front)
    local scene = window.scene
    if scene == nil then return false end
    if not front and window.lens ~= true then Scene.base(window) end
    local order, total = scene.order, scene.orderCount
    local figs = window.figs
    local count = #figs
    local peek = ProjectALife.PeekDoor
    local i, j = 1, 1
    while i <= total or j <= count do
        local entry, fig = order[i], figs[j]
        if i <= total and not Scene.entryDue(entry, front) then
            i = i + 1
        elseif j <= count and not Scene.figureDue(fig, front) then
            j = j + 1
        elseif i <= total and (j > count or entry.key >= fig.depth) then
            Scene.drawEntry(window, entry)
            i = i + 1
        else
            peek.drawFigure(window, fig)
            j = j + 1
        end
    end
    return true
end

function Scene.rain(window, now)
    local rain = window.rain or 0
    if rain < SD.rainMin then return 0 end
    local view = window.view
    local drops = window.drops
    local ox, oy, rw, rh = 0, 0, view.w, view.h
    if view.full == true then ox, oy, rw, rh = view.sx, view.sy, view.sw, view.sh end
    if drops == nil then
        drops = {}
        for index = 1, SD.rainDrops do
            drops[index] = { x = ox + (index * 37 + 11) % math.max(1, math.floor(rw)), y = (index * 53) % math.max(1, math.floor(rh)),
                speed = 0.25 + (index % 5) * 0.06 }
        end
        window.drops = drops
    end
    local shown = math.min(#drops, math.max(4, math.floor(#drops * rain)))
    local cr, cg, cb = 0.72, 0.78, 0.88
    local grade = nil
    if window.lens == true then grade = window.grade end
    if grade ~= nil then cr, cg, cb = grade.hr, grade.hg, grade.hb end
    for index = 1, shown do
        local x, y = SD.rainAt(drops[index], now, rh)
        window:drawRect(math.floor(x), math.floor(y + oy), 1, 10, 0.35, cr, cg, cb)
    end
    return shown
end

return Scene
