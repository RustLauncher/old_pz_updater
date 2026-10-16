TunaWRSlots = TunaWRSlots or {}

-- the schema key is the MODE MARKER: absence of bindings cannot distinguish auto from all-empty
TunaWRSlots.SCHEMA = 1
local PFX = 'TunaWR_'

-- movableData and FLAT SCALARS both forced: copyTable's depth is unverified
function TunaWRSlots.encode(mv, bound, n)
    TunaWRSlots.clear(mv)
    mv[PFX .. 'v'] = TunaWRSlots.SCHEMA
    for i = 1, n do
        local id = bound and bound[i] or nil
        if id ~= nil then mv[PFX .. 's' .. i] = id end
    end
end

-- n is the MODEL's count; the payload is interpreted by it, never allowed to define it
function TunaWRSlots.decode(mv, n)
    if not mv then return nil end
    if mv[PFX .. 'v'] == nil then return nil end
    local bound = {}
    for i = 1, n do
        local id = mv[PFX .. 's' .. i]
        if type(id) == 'number' then bound[i] = id end
    end
    return bound
end

function TunaWRSlots.clear(mv)
    if not mv then return end
    for k in pairs(mv) do
        if type(k) == 'string' and k:sub(1, #PFX) == PFX then mv[k] = nil end
    end
end

-- dx, dy and dz must all match tools\common\WeaponRackSlots.ps1
TunaWRSlots.PIECES = {
    cabinet = {
        { cat = 'LONG_GUN', dx = 0.35, dy = 0.820, dz = 0.164, rx = 0, ry = 90, rz = 180, butt = true },
        { cat = 'LONG_GUN', dx = 0.50, dy = 0.820, dz = 0.164, rx = 0, ry = 90, rz = 180, butt = true },
        { cat = 'LONG_GUN', dx = 0.65, dy = 0.820, dz = 0.164, rx = 0, ry = 90, rz = 180, butt = true },
    },
    handguncase = {
        { cat = 'HANDGUN', dx = 0.758, dy = 0.698, dz = 0.4749, rx = 0, ry = 0, rz = 90 },
        { cat = 'HANDGUN', dx = 0.500, dy = 0.698, dz = 0.4749, rx = 0, ry = 0, rz = 90 },
        { cat = 'HANDGUN', dx = 0.242, dy = 0.698, dz = 0.4749, rx = 0, ry = 0, rz = 90 },
    },

    armory = {
        { cat = 'LONG_GUN', dx = 1.744, dy = 0.78225, dz = 0.2548, rx = 0, ry = 90, rz = 0, butt = true },
        { cat = 'LONG_GUN', dx = 1.572, dy = 0.78225, dz = 0.2548, rx = 0, ry = 90, rz = 0, butt = true },
        { cat = 'LONG_GUN', dx = 1.401, dy = 0.78225, dz = 0.2548, rx = 0, ry = 90, rz = 0, butt = true },
        { cat = 'LONG_GUN', dx = 1.230, dy = 0.78225, dz = 0.2548, rx = 0, ry = 90, rz = 0, butt = true },
        { cat = 'LONG_GUN', dx = 1.059, dy = 0.78225, dz = 0.2548, rx = 0, ry = 90, rz = 0, butt = true },
        { cat = 'LONG_GUN', dx = 0.888, dy = 0.78225, dz = 0.2548, rx = 0, ry = 90, rz = 0, butt = true },
        { cat = 'LONG_GUN', dx = 0.717, dy = 0.78225, dz = 0.2548, rx = 0, ry = 90, rz = 0, butt = true },
        { cat = 'LONG_GUN', dx = 0.546, dy = 0.78225, dz = 0.2548, rx = 0, ry = 90, rz = 0, butt = true },
    },
    pegboard = {
        { cat = 'LONG_GUN', dx = 0.735, dy = 0.320, dz = 0.4801, rx = -90, ry = 0, rz = 0, butt = false },
        { cat = 'LONG_GUN', dx = 0.735, dy = 0.320, dz = 0.6026, rx = -90, ry = 0, rz = 0, butt = false },
        { cat = 'LONG_GUN', dx = 0.735, dy = 0.320, dz = 0.7250, rx = -90, ry = 0, rz = 0, butt = false },
    },
    fieldrack = {
        { cat = 'LONG_GUN', dx = 0.266, dy = 0.167, dz = 0.029875, rx = 0, ry = 90, rz = 90,  butt = true },
        { cat = 'LONG_GUN', dx = 0.266, dy = 0.500, dz = 0.029875, rx = 0, ry = 90, rz = 90,  butt = true },
        { cat = 'LONG_GUN', dx = 0.266, dy = 0.833, dz = 0.029875, rx = 0, ry = 90, rz = 90,  butt = true },
        { cat = 'LONG_GUN', dx = 0.734, dy = 0.167, dz = 0.029875, rx = 0, ry = 90, rz = 270, butt = true },
        { cat = 'LONG_GUN', dx = 0.734, dy = 0.500, dz = 0.029875, rx = 0, ry = 90, rz = 270, butt = true },
        { cat = 'LONG_GUN', dx = 0.734, dy = 0.833, dz = 0.029875, rx = 0, ry = 90, rz = 270, butt = true },
    },
}
-- transcribed measurements, not re-derived: three offsets separate the trial rig from this mod
TunaWRSlots.RESOLVED = {
    pegboard = {
        N = {
            { dx = 0.5359, dy = 0.8426, dz = 0.4926, rx = 90,  ry = 0,  rz = 180 },
            { dx = 0.5359, dy = 0.8426, dz = 0.6151, rx = 90,  ry = 0,  rz = 180 },
            { dx = 0.5359, dy = 0.8426, dz = 0.7375, rx = 90,  ry = 0,  rz = 180 },
        },
        E = {
            { dx = 0.2597, dy = 0.6781, dz = 0.5308, rx = 90,  ry = 90, rz = 180 },
            { dx = 0.2597, dy = 0.6781, dz = 0.6533, rx = 90,  ry = 90, rz = 180 },
            { dx = 0.2597, dy = 0.6781, dz = 0.7757, rx = 90,  ry = 90, rz = 180 },
        },
        S = {
            { dx = 0.6891, dy = 0.3515, dz = 0.5426, rx = 270, ry = 0,  rz = 0 },
            { dx = 0.6891, dy = 0.3515, dz = 0.6651, rx = 270, ry = 0,  rz = 0 },
            { dx = 0.6891, dy = 0.3515, dz = 0.7875, rx = 270, ry = 0,  rz = 0 },
        },
        W = {
            { dx = 0.8554, dy = 0.5469, dz = 0.5058, rx = 90,  ry = 90, rz = 180 },
            { dx = 0.8554, dy = 0.5469, dz = 0.6283, rx = 90,  ry = 90, rz = 180 },
            { dx = 0.8554, dy = 0.5469, dz = 0.7507, rx = 90,  ry = 90, rz = 180 },
        },
    },

    fieldrack = {
        N = {
            { dx = 0.7467, dy = 0.8341, dz = -0.082938, rx = 0, ry = 90, rz = 270 },
            { dx = 0.7467, dy = 0.5011, dz = -0.082938, rx = 0, ry = 90, rz = 270 },
            { dx = 0.7467, dy = 0.1681, dz = -0.082938, rx = 0, ry = 90, rz = 270 },
            { dx = 0.1699, dy = 0.8554, dz = -0.082938, rx = 0, ry = 90, rz = 90 },
            { dx = 0.1699, dy = 0.5224, dz = -0.082938, rx = 0, ry = 90, rz = 90 },
            { dx = 0.1699, dy = 0.1894, dz = -0.082938, rx = 0, ry = 90, rz = 90 },
        },
        E = {
            { dx = 0.8555, dy = 0.2298, dz = -0.082938, rx = 0, ry = 90, rz = 180 },
            { dx = 0.5225, dy = 0.2298, dz = -0.082938, rx = 0, ry = 90, rz = 180 },
            { dx = 0.1895, dy = 0.2298, dz = -0.082938, rx = 0, ry = 90, rz = 180 },
            { dx = 0.8330, dy = 0.7140, dz = -0.082938, rx = 0, ry = 90, rz = 0 },
            { dx = 0.5000, dy = 0.7140, dz = -0.082938, rx = 0, ry = 90, rz = 0 },
            { dx = 0.1670, dy = 0.7140, dz = -0.082938, rx = 0, ry = 90, rz = 0 },
        },
        S = {
            { dx = 0.2108, dy = 0.2084, dz = -0.082938, rx = 0, ry = 90, rz = 90 },
            { dx = 0.2108, dy = 0.5414, dz = -0.082938, rx = 0, ry = 90, rz = 90 },
            { dx = 0.2108, dy = 0.8744, dz = -0.082938, rx = 0, ry = 90, rz = 90 },
            { dx = 0.7329, dy = 0.1481, dz = -0.082938, rx = 0, ry = 90, rz = 270 },
            { dx = 0.7329, dy = 0.4811, dz = -0.082938, rx = 0, ry = 90, rz = 270 },
            { dx = 0.7329, dy = 0.8141, dz = -0.082938, rx = 0, ry = 90, rz = 270 },
        },
        W = {
            { dx = 0.2451, dy = 0.7634, dz = -0.082938, rx = 0, ry = 90, rz = 0 },
            { dx = 0.5781, dy = 0.7634, dz = -0.082938, rx = 0, ry = 90, rz = 0 },
            { dx = 0.9111, dy = 0.7634, dz = -0.082938, rx = 0, ry = 90, rz = 0 },
            { dx = 0.1983, dy = 0.2548, dz = -0.082938, rx = 0, ry = 90, rz = 180 },
            { dx = 0.5313, dy = 0.2548, dz = -0.082938, rx = 0, ry = 90, rz = 180 },
            { dx = 0.8643, dy = 0.2548, dz = -0.082938, rx = 0, ry = 90, rz = 180 },
        },
    },
}

function TunaWRSlots.resolvedFor(piece, facing)
    if piece == nil or facing == nil then return nil end
    local byPiece = TunaWRSlots.RESOLVED[piece]
    return byPiece and byPiece[facing] or nil
end

-- no slot count here, and that is load-bearing: the count is #PIECES[piece]
TunaWRSlots.PIECE_INFO = {
    cabinet     = { title = 'IGUI_TunaWR_Piece_cabinet',     uiOrder = { 3, 2, 1 }, hasAmmoDrawer = true },

    handguncase = {
        title = 'IGUI_TunaWR_Piece_handguncase', hasAmmoDrawer = true,
        uiOrder = { 1, 2, 3 },                       -- S and E, the hero facings
        uiOrderFacing = { N = { 3, 2, 1 }, W = { 3, 2, 1 } },
    },

    armory = {
        title = 'IGUI_TunaWR_Piece_armory', hasAmmoDrawer = true,
        uiOrder = { 1, 2, 3, 4, 5, 6, 7, 8 },                    -- S and E
        uiOrderFacing = {
            N = { 8, 7, 6, 5, 4, 3, 2, 1 },
            W = { 8, 7, 6, 5, 4, 3, 2, 1 },
        },
    },

    pegboard = {
        title = 'IGUI_TunaWR_Piece_pegboard', hasAmmoDrawer = true,
        drawerCapacity = 25,
        uiOrder = { 3, 2, 1 },
    },

    fieldrack = {
        title = 'IGUI_TunaWR_Piece_fieldrack', hasAmmoDrawer = true,
        drawerCapacity = 30,
        buttScale = 1.0,
        uiOrder = { 4, 5, 6, 1, 2, 3 },                          -- N
        uiOrderFacing = {
            E = { 6, 5, 4, 3, 2, 1 },
            S = { 3, 2, 1, 6, 5, 4 },
            W = { 1, 2, 3, 4, 5, 6 },
        },
    },
}

-- a piece NAME with no descriptor and no slot table, or it is adopted as a second rack
TunaWRSlots.SATELLITE = {
    armorysat = 'armory',
}

function TunaWRSlots.masterPieceOf(piece)
    if piece == nil then return nil end
    return TunaWRSlots.SATELLITE[piece]
end

function TunaWRSlots.isSatellitePiece(piece)
    return TunaWRSlots.masterPieceOf(piece) ~= nil
end

-- must agree with the authored SpriteGridPos: the engine reads one, we read the other
TunaWRSlots.PARTNER_OFFSET = {
    N = { 1, 0 }, S = { 1, 0 },
    E = { 0, 1 }, W = { 0, 1 },
}

-- the mirror is ex-dx, not 1-dx: on a 1x2 a tile-wide mirror folds both halves together
TunaWRSlots.EXTENT = {
    armory = { 2, 1 },
}

function TunaWRSlots.extentOf(piece)
    local e = piece and TunaWRSlots.EXTENT[piece]
    if e then return e[1], e[2] end
    return 1, 1
end

-- screen order, and index 2 cannot test it - a gate must use an OFF-CENTRE box
function TunaWRSlots.uiOrderFor(info, facing)
    if not info then return nil end
    local byFacing = info.uiOrderFacing
    if byFacing and facing and byFacing[facing] then return byFacing[facing] end
    return info.uiOrder
end

-- nil rather than a default, so no caller inherits someone else's answer
function TunaWRSlots.infoOf(piece)
    if piece == nil then return nil end
    return TunaWRSlots.PIECE_INFO[piece]
end

-- auto and custom are different algorithms: custom derives NOTHING, so nothing re-derives
function TunaWRSlots.resolve(slots, bound, items)
    local assigned = {}

    if bound ~= nil then
        local byId = {}
        for i = 1, #items do byId[items[i].id] = items[i] end
        local used = {}
        for si = 1, #slots do
            local id = bound[si]
            local it = (id ~= nil) and byId[id] or nil
            if it and it.cat == slots[si].cat and not used[id] then
                assigned[si] = id
                used[id] = true
            end
        end
        return assigned
    end

    local pool = {}
    for i = 1, #items do
        if items[i].cat then pool[#pool + 1] = items[i] end
    end
    table.sort(pool, function(a, b) return a.id < b.id end)

    local taken = {}
    for si = 1, #slots do
        for pi = 1, #pool do
            if not taken[pi] and pool[pi].cat == slots[si].cat then
                assigned[si] = pool[pi].id
                taken[pi] = true
                break
            end
        end
    end
    return assigned
end

-- counts items PRESENT against stations AUTHORED - unbound guns still occupy the furniture
function TunaWRSlots.hasRoomFor(slots, items, cat)
    if cat == nil then return false end
    local stations = 0
    for si = 1, #slots do
        if slots[si].cat == cat then stations = stations + 1 end
    end
    local present = 0
    for i = 1, #items do
        if items[i].cat == cat then present = present + 1 end
    end
    return present < stations
end

-- answers WHERE a gun goes, never WHETHER one fits - that was the wrong question
function TunaWRSlots.firstFree(slots, assigned, cat)
    for si = 1, #slots do
        if assigned[si] == nil and slots[si].cat == cat then return si end
    end
    return nil
end

function TunaWRSlots.unbound(slots, assigned, items)
    local placed = {}
    for si = 1, #slots do
        if assigned[si] ~= nil then placed[assigned[si]] = true end
    end
    local out = {}
    for i = 1, #items do
        local it = items[i]
        if it.cat and not placed[it.id] then out[#out + 1] = it end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- additive only, and it WRITES a binding through the authority rather than deriving one
function TunaWRSlots.reconcile(slots, cur, items)
    local ids = {}
    for i = 1, #slots do ids[i] = cur[i] end

    local free = TunaWRSlots.unbound(slots, cur, items)
    local changed = false
    for k = 1, #free do
        local si = TunaWRSlots.firstFree(slots, ids, free[k].cat)
        if si then
            ids[si] = free[k].id
            changed = true
        end
    end

    if not changed then return nil end
    return ids
end

-- swap, never evict: an evicted gun would sit in the bay bound to nothing, invisible
function TunaWRSlots.place(slots, cur, index, id)
    if not slots[index] then return nil end

    local ids = {}
    local from = nil
    for i = 1, #slots do
        if cur[i] ~= nil then
            ids[i] = cur[i]
            if cur[i] == id then from = i end
        end
    end

    local displaced = ids[index]
    ids[index] = id
    if from and from ~= index then ids[from] = nil end

    if displaced ~= nil and displaced ~= id then
        if from and from ~= index then
            ids[from] = displaced
        else
            local target = nil
            for i = 1, #slots do
                if ids[i] == nil and slots[i].cat == slots[index].cat then target = i; break end
            end
            if not target then return nil end   -- refuse rather than evict
            ids[target] = displaced
        end
    end
    return ids
end

-- the whole concurrency defence, stateless; add a command that MOVES an item and seq returns
function TunaWRSlots.validate(slots, ids, items)
    if type(ids) ~= 'table' then return false, 'badPayload' end

    for k in pairs(ids) do
        if type(k) ~= 'number' or k < 1 or k > #slots or k % 1 ~= 0 then
            return false, 'badSlot'
        end
    end

    local byId = {}
    for i = 1, #items do byId[items[i].id] = items[i] end
    local seen = {}
    for i = 1, #slots do
        local id = ids[i]
        if id ~= nil then
            if type(id) ~= 'number' then return false, 'badId' end
            if seen[id] then return false, 'duplicate' end
            seen[id] = true
            local it = byId[id]
            if not it then return false, 'notInRack' end
            if it.cat ~= slots[i].cat then return false, 'wrongCategory' end
        end
    end
    return true, nil
end
