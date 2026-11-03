ProjectALife = ProjectALife or {}

local Architect = {
    metrics = { compounds = 0, conflicts = 0, buildings = 0, towers = 0 },
}
ProjectALife.OutpostArchitect = Architect

Architect.family = {

    wood = { w = "walls_exterior_wooden_01_28", n = "walls_exterior_wooden_01_29",
        nw = "walls_exterior_wooden_01_30", se = "walls_exterior_wooden_01_31",
        doorN = "walls_exterior_wooden_01_39", doorW = "walls_exterior_wooden_01_38",
        windowN = "walls_exterior_wooden_01_37", windowW = "walls_exterior_wooden_01_36" },

    palisade = { w = "walls_logs_0", n = "walls_logs_1",
        nw = "walls_logs_2", se = "walls_logs_3" },

    fence = { w = "fencing_01_11", n = "fencing_01_8",
        nw = "fencing_01_12", se = "fencing_01_13" },

    block = { w = "walls_commercial_01_48", n = "walls_commercial_01_49",
        nw = "walls_commercial_01_50", se = "walls_commercial_01_51",
        doorN = "walls_commercial_01_59", doorW = "walls_commercial_01_58",
        windowN = "walls_commercial_01_57", windowW = "walls_commercial_01_56" },

    parapet = { w = "walls_exterior_house_low_01_28", n = "walls_exterior_house_low_01_29",
        nw = "walls_exterior_house_low_01_30", se = "walls_exterior_house_low_01_31" },

    railing = { w = "fixtures_railings_01_24", n = "fixtures_railings_01_25",
        nw = "fixtures_railings_01_26", se = "fixtures_railings_01_27" },
    garage = { w = "walls_garage_01_36", n = "walls_garage_01_37",
        nw = "walls_garage_01_38", se = "walls_garage_01_39" },
}

Architect.piece = {
    frameN = "fixtures_doors_frames_01_1", frameW = "fixtures_doors_frames_01_0",
    doorN = "fixtures_doors_01_1", doorW = "fixtures_doors_01_0",
    windowN = "fixtures_windows_01_9", windowW = "fixtures_windows_01_8",

    gateN = { "fixtures_doors_fences_01_50", "fixtures_doors_fences_01_51" },

    bigGateN = { "fixtures_doors_fences_01_50", "fixtures_doors_fences_01_51",
        "fixtures_doors_fences_01_58", "fixtures_doors_fences_01_59" },

    metalDoorN = "fixtures_doors_02_53", metalDoorW = "fixtures_doors_02_52",

    farmGateN = "fixtures_doors_fences_01_9",

    wicketN = "fixtures_doors_fences_01_13",

    garageDoorN = { "walls_garage_01_3", "walls_garage_01_4", "walls_garage_01_5" },
    floor = "floors_interior_tilesandwood_01_41",
    concrete = "floors_exterior_street_01_17",

    roof = "roofs_02_22",
    stairsW = { "fixtures_stairs_01_16", "fixtures_stairs_01_17", "fixtures_stairs_01_18" },

    stairRail = { "fixtures_railings_01_101", "fixtures_railings_01_100", "fixtures_railings_01_99" },
    wellRailN = "fixtures_railings_01_89", wellRailW = "fixtures_railings_01_88",
    wellPost = "fixtures_railings_01_91",

    dirt = { "blends_natural_01_69", "blends_natural_01_70", "blends_natural_01_71" },
    crops = { "vegetation_farm_01_32", "vegetation_farm_01_33", "vegetation_farm_01_34",
        "vegetation_farm_01_35", "vegetation_farm_01_36", "vegetation_farm_01_38" },

    lampN = "lighting_outdoor_01_24", lampW = "lighting_outdoor_01_25",

    flood = { S = "lighting_outdoor_01_49", W = "lighting_outdoor_01_50" },
    campfire = "camping_01_4",

    barrier = "fencing_01_100",
    hamRadio = "appliances_com_01_0",
    tableLamp = "lighting_indoor_02_16",
}

Architect.set = {

    bed = { { "furniture_bedding_01_85", 0, 0 }, { "furniture_bedding_01_84", 0, 1 } },
    sickbed = { { "location_community_medical_01_73", 0, 0 }, { "location_community_medical_01_72", 0, 1 } },
    wardrobe = { { "furniture_storage_01_25", 0, 0 }, { "furniture_storage_01_24", 0, 1 } },
    couch = { { "furniture_seating_indoor_01_0", 0, 0 }, { "furniture_seating_indoor_01_1", 1, 0 } },
    benchFacingS = { { "furniture_seating_outdoor_01_0", 0, 0 }, { "furniture_seating_outdoor_01_1", 1, 0 } },
    benchFacingN = { { "furniture_seating_outdoor_01_4", 0, 0 }, { "furniture_seating_outdoor_01_5", 1, 0 } },
    benchFacingE = { { "furniture_seating_outdoor_01_3", 0, 0 }, { "furniture_seating_outdoor_01_2", 0, 1 } },
    benchFacingW = { { "furniture_seating_outdoor_01_7", 0, 0 }, { "furniture_seating_outdoor_01_6", 0, 1 } },

    tent = { { "camping_01_2", 0, 0 }, { "camping_01_3", 1, 0 } },
}

function Architect.newPlan(seed)
    local state = math.floor(tonumber(seed) or 1) % 2147483647
    if state == 0 then state = 1 end
    return { ops = {}, posts = {}, solid = {}, free = {}, floor = {}, hole = {},
        edgeN = {}, edgeW = {}, wallN = {}, wallW = {}, conflicts = 0, refusals = {},
        roll = function()
            state = (state * 48271) % 2147483647
            return state / 2147483647
        end }
end

function Architect.key(x, y, z) return x .. ":" .. y .. ":" .. (z or 0) end

function Architect.emit(plan, op) plan.ops[#plan.ops + 1] = op end

function Architect.tile(plan, x, y, z, sprite)
    Architect.emit(plan, { op = "tile", x = x, y = y, z = z, sprite = sprite })
end

function Architect.keepFree(plan, x, y, z) plan.free[Architect.key(x, y, z)] = true end

function Architect.refuse(plan, what, x, y, z)
    plan.conflicts = plan.conflicts + 1
    Architect.metrics.conflicts = Architect.metrics.conflicts + 1
    plan.refusals[#plan.refusals + 1] = tostring(what) .. " at " .. Architect.key(x, y, z)
    return false
end

function Architect.floorAt(plan, x, y, z, sprite)
    local k = Architect.key(x, y, z)
    if plan.hole[k] then return false end
    plan.floor[k] = true
    Architect.emit(plan, { op = "floor", x = x, y = y, z = z, sprite = sprite })
    return true
end

function Architect.standable(plan, x, y, z)
    local k = Architect.key(x, y, z)
    if plan.solid[k] or plan.free[k] or plan.hole[k] then return false end
    if (z or 0) > 0 and not plan.floor[k] then return false end
    return true
end

function Architect.furnish(plan, x, y, z, what, op)
    local pieces = Architect.set[what] or { { what, 0, 0 } }
    for _, piece in ipairs(pieces) do
        if not Architect.standable(plan, x + piece[2], y + piece[3], z) then
            return Architect.refuse(plan, what, x + piece[2], y + piece[3], z)
        end
    end
    for _, piece in ipairs(pieces) do
        plan.solid[Architect.key(x + piece[2], y + piece[3], z)] = true
        Architect.emit(plan, { op = op or "object", x = x + piece[2], y = y + piece[3], z = z,
            sprite = piece[1] })
    end
    return true
end

function Architect.onTop(plan, x, y, z, sprite, op)
    if not plan.solid[Architect.key(x, y, z)] then
        return Architect.refuse(plan, sprite .. " (nothing to stand on)", x, y, z)
    end
    Architect.emit(plan, { op = op or "object", x = x, y = y, z = z, sprite = sprite })
    return true
end

function Architect.post(plan, x, y, z, role, conduct, face)
    plan.posts[#plan.posts + 1] = { x = x + 0.5, y = y + 0.5, z = z or 0,
        role = role, conduct = conduct,
        face = type(face) == "table" and { x = face.x, y = face.y } or nil }
    Architect.keepFree(plan, x, y, z)
end

local function markN(plan, x, y, z) plan.edgeN[Architect.key(x, y, z)] = true end
local function markW(plan, x, y, z) plan.edgeW[Architect.key(x, y, z)] = true end

local function openingsFor(side, openings, fam)
    local result = {}
    local north = side == "N" or side == "S"
    for _, o in ipairs(openings or {}) do
        if o.side == side then
            local at = o.at
            if o.kind == "door" then
                result[at] = { north and fam.doorN or fam.doorW,
                    north and Architect.piece.frameN or Architect.piece.frameW,
                    north and Architect.piece.doorN or Architect.piece.doorW, door = true }
            elseif o.kind == "window" then
                result[at] = { north and fam.windowN or fam.windowW,
                    north and Architect.piece.windowN or Architect.piece.windowW }
            elseif o.kind == "frame" then
                result[at] = { north and fam.windowN or fam.windowW }
            elseif o.kind == "metaldoor" then
                result[at] = { north and fam.doorN or fam.doorW,
                    north and Architect.piece.frameN or Architect.piece.frameW,
                    north and Architect.piece.metalDoorN or Architect.piece.metalDoorW, door = true }
            elseif o.kind == "gate" then
                result[at] = { Architect.piece.gateN[1], door = true }
                result[at + 1] = { Architect.piece.gateN[2], door = true }
            elseif o.kind == "bigGate" then
                for index = 1, 4 do
                    result[at + index - 1] = { Architect.piece.bigGateN[index], door = true }
                end
            elseif o.kind == "farmgate" then
                result[at] = { Architect.piece.farmGateN, door = true }
            elseif o.kind == "wicket" then
                result[at] = { Architect.piece.wicketN, door = true }
            elseif o.kind == "garage" then
                for index = 1, 3 do
                    result[at + index - 1] = { Architect.piece.garageDoorN[index], door = true }
                end
            elseif o.kind == "gap" then
                result[at] = { gap = true }
            elseif o.kind == "junction" then

                result[at] = { fam.nw, corner = true }
            end
        end
    end
    return result
end

local function openingPieces(plan, x, y, z, pieces, north)
    if pieces.gap then return end
    for _, sprite in ipairs(pieces) do Architect.tile(plan, x, y, z, sprite) end
    if pieces.corner then
        markN(plan, x, y, z)
        markW(plan, x, y, z)
        plan.wallN[Architect.key(x, y, z)] = true
        plan.wallW[Architect.key(x, y, z)] = true
        return
    end
    if north then markN(plan, x, y, z) else markW(plan, x, y, z) end
    if pieces.door then
        Architect.keepFree(plan, x, y, z)
        if north then Architect.keepFree(plan, x, y - 1, z) else Architect.keepFree(plan, x - 1, y, z) end
    end
end

function Architect.runN(plan, x1, x2, y, z, fam, openings, side)
    local holes = openingsFor(side or "N", openings, fam)
    for px = x1, x2 do
        if holes[px] then
            openingPieces(plan, px, y, z, holes[px], true)
        else
            Architect.tile(plan, px, y, z, fam.n)
            markN(plan, px, y, z)
            plan.wallN[Architect.key(px, y, z)] = true
        end
    end
end

function Architect.runW(plan, x, y1, y2, z, fam, openings, side)
    local holes = openingsFor(side or "W", openings, fam)
    for py = y1, y2 do
        if holes[py] then
            openingPieces(plan, x, py, z, holes[py], false)
        else
            Architect.tile(plan, x, py, z, fam.w)
            markW(plan, x, py, z)
            plan.wallW[Architect.key(x, py, z)] = true
        end
    end
end

function Architect.box(plan, x, y, x2, y2, z, fam, openings)
    Architect.tile(plan, x, y, z, fam.nw)
    markN(plan, x, y, z)
    markW(plan, x, y, z)
    Architect.runN(plan, x + 1, x2, y, z, fam, openings, "N")
    Architect.runW(plan, x, y + 1, y2, z, fam, openings, "W")
    Architect.runW(plan, x2 + 1, y, y2, z, fam, openings, "E")
    Architect.runN(plan, x, x2, y2 + 1, z, fam, openings, "S")
    Architect.tile(plan, x2 + 1, y2 + 1, z, fam.se)
end

function Architect.flight(plan, bx, by, z)
    local piece = Architect.piece
    for level = 0, 2 do
        local sx = bx - level
        Architect.emit(plan, { op = "stairs", x = sx, y = by, z = z,
            sprite = piece.stairsW[level + 1], north = false, level = level })
        plan.solid[Architect.key(sx, by, z)] = true
        plan.hole[Architect.key(sx, by, z + 1)] = true

        Architect.tile(plan, sx, by, z, piece.stairRail[level + 1])
        Architect.tile(plan, sx, by + 1, z, piece.stairRail[level + 1])
        Architect.tile(plan, sx, by, z + 1, piece.wellRailN)
        Architect.tile(plan, sx, by + 1, z + 1, piece.wellRailN)
    end

    Architect.tile(plan, bx + 1, by, z + 1, piece.wellRailW)
    Architect.tile(plan, bx + 1, by + 1, z + 1, piece.wellPost)
    Architect.keepFree(plan, bx + 1, by, z)
    Architect.keepFree(plan, bx - 3, by, z + 1)
end

function Architect.wallLamp(plan, x, y, z, side)

    local k = Architect.key(x, y, z)
    if side == "N" and plan.wallN[k] then
        Architect.emit(plan, { op = "light", x = x, y = y, z = z, sprite = Architect.piece.lampN })
        return true
    elseif side == "W" and plan.wallW[k] then
        Architect.emit(plan, { op = "light", x = x, y = y, z = z, sprite = Architect.piece.lampW })
        return true
    end
    return Architect.refuse(plan, "wall lamp " .. tostring(side) .. " (no wall)", x, y, z)
end

function Architect.flood(plan, x, y, z, facing)
    if not Architect.standable(plan, x, y, z) then
        return Architect.refuse(plan, "floodlight", x, y, z)
    end
    plan.solid[Architect.key(x, y, z)] = true
    local back = facing == "N" or facing == "W"
    Architect.emit(plan, { op = "light", x = x, y = y, z = z,
        sprite = back and Architect.piece.flood.W or Architect.piece.flood.S })
    return true
end

Architect.rooms = {
    barracks = {
        ground = { { "bed", 1, 1 }, { "bed", 2, 1 }, { "bed", 3, 1 }, { "bed", 4, 1 },
            { "bed", 5, 1 }, { "location_military_generic_01_12", 1, 3 }, { "location_military_generic_01_12", 3, 3 },
            { "location_military_generic_01_12", 5, 3 }, { "wardrobe", 1, 4 } },
        upper = { { "bed", 1, 3 }, { "bed", 2, 3 }, { "bed", 3, 3 }, { "bed", 4, 3 },
            { "furniture_storage_02_13", 1, 1 }, { "furniture_storage_02_13", 2, 1 } },
        posts = { { 6, 3, 0, "rest" }, { 6, 4, 0, "rest" }, { 5, 2, 1, "rest" } },
    },
    mess = {
        ground = { { "appliances_cooking_01_20", 1, 1 }, { "furniture_shelving_01_16", 2, 1 },
            { "furniture_tables_high_01_21", 2, 3 }, { "furniture_tables_high_01_21", 4, 3 },
            { "furniture_tables_high_01_21", 6, 3 }, { "benchFacingN", 2, 4 }, { "benchFacingN", 5, 4 },
            { "location_shop_greenes_01_35", 1, 4 } },
        upper = { { "location_shop_greenes_01_35", 1, 1 }, { "location_military_generic_01_0", 1, 3 },
            { "location_military_generic_01_5", 2, 3 }, { "furniture_shelving_01_16", 3, 3 } },
        posts = { { 3, 2, 0, "eat" }, { 5, 2, 0, "eat" }, { 7, 2, 0, "drink" } },
    },
    armoury = {
        ground = { { "location_military_generic_01_0", 1, 1 }, { "location_military_generic_01_5", 2, 1 },
            { "location_military_generic_01_2", 1, 3 }, { "location_military_generic_01_3", 2, 3 },
            { "furniture_tables_high_01_16", 3, 3 }, { "furniture_shelving_01_16", 1, 4 } },
        upper = { { "location_military_generic_01_8", 1, 1 }, { "location_military_generic_01_9", 1, 3 },
            { "bed", 2, 3 } },
        posts = { { 4, 2, 0, "work" } },
    },
    medical = {
        ground = { { "sickbed", 1, 1 }, { "sickbed", 3, 1 }, { "furniture_shelving_01_16", 1, 4 },
            { "furniture_tables_high_01_16", 3, 4 }, { "furniture_storage_02_18", 2, 4 } },
        upper = { { "sickbed", 1, 3 }, { "sickbed", 3, 3 }, { "location_community_medical_01_37", 1, 1 } },
        posts = { { 2, 3, 0, "work" } },
    },
    command = {
        ground = { { "furniture_tables_high_01_16", 1, 1 }, { "furniture_seating_outdoor_01_17", 1, 2 },
            { "furniture_tables_high_01_16", 3, 3 }, { "wardrobe", 1, 4 },
            { "furniture_shelving_01_16", 3, 1 } },
        upper = { { "bed", 1, 3 }, { "furniture_storage_02_13", 1, 1 }, { "furniture_tables_high_01_16", 3, 3 } },
        radio = { 1, 1 },
        posts = { { 2, 2, 0, "radio" }, { 4, 2, 0, "rest" } },
    },
    workshop = {
        ground = { { "furniture_tables_high_01_16", 1, 1 }, { "furniture_tables_high_01_16", 2, 1 },
            { "furniture_shelving_01_16", 1, 3 }, { "location_military_generic_01_10", 2, 3 },
            { "location_military_generic_01_11", 1, 4 } },
        upper = { { "location_business_machinery_01_33", 1, 1 }, { "location_military_generic_01_8", 1, 3 } },
        posts = { { 1, 2, 0, "work" }, { 3, 2, 0, "work" } },
    },
    storage = {
        ground = { { "location_military_generic_01_0", 1, 1 }, { "location_military_generic_01_5", 2, 1 },
            { "location_military_generic_01_8", 3, 1 }, { "location_military_generic_01_9", 1, 3 },
            { "location_military_generic_01_10", 2, 3 }, { "furniture_shelving_01_16", 3, 3 },
            { "furniture_storage_02_18", 1, 4 } },
        upper = { { "location_military_generic_01_2", 1, 1 }, { "location_military_generic_01_3", 1, 3 } },
        posts = {},
    },
}

Architect.stores = {
    armoury = { { "location_military_generic_01_4", "munitions", 6 }, { "location_military_generic_01_13", "munitions", 5 } },
    medical = { { "location_community_medical_01_37", "medicine", 5 } },
    mess = { { "location_shop_greenes_01_35", "rations", 6 } },
    workshop = { { "location_business_machinery_01_33", "hardware", 4 } },
    storage = { { "location_shop_greenes_01_35", "rations", 5 }, { "location_business_machinery_01_33", "hardware", 3 } },
}

function Architect.building(plan, x, y, w, h, z, kind)

    local armoured = kind == "armoury"
    local fam = armoured and Architect.family.block or Architect.family.wood
    w = math.max(9, math.floor(w))
    h = math.max(7, math.floor(h))
    local x2, y2 = x + w - 1, y + h - 1
    local doorX = x + math.floor(w / 2)
    local first, roof = z + 1, z + 2

    Architect.flight(plan, x2 - 1, y + 1, z)
    Architect.flight(plan, x2 - 1, y2 - 1, first)

    for py = y, y2 do Architect.keepFree(plan, x2, py, z) end
    for px = x, x2 do Architect.keepFree(plan, px, y2, z) end
    for px = x2 - 4, x2 do Architect.keepFree(plan, px, y + 2, first) end
    for py = y + 2, y2 do Architect.keepFree(plan, x2, py, first) end

    for px = x, x2 do
        for py = y, y2 do
            Architect.floorAt(plan, px, py, z, Architect.piece.floor)
            Architect.floorAt(plan, px, py, first, Architect.piece.floor)
            Architect.floorAt(plan, px, py, roof, Architect.piece.roof)
        end
    end

    local ground = { { side = "S", at = doorX, kind = armoured and "metaldoor" or "door" } }
    for px = x + 2, x2 - 1, 3 do
        if armoured then break end
        if px ~= doorX then ground[#ground + 1] = { side = "N", at = px, kind = "window" } end
        if math.abs(px - doorX) > 1 then ground[#ground + 1] = { side = "S", at = px, kind = "window" } end
    end
    if not armoured then ground[#ground + 1] = { side = "W", at = y + 3, kind = "window" } end
    Architect.box(plan, x, y, x2, y2, z, fam, ground)

    local upper = {}
    for px = x + 2, x2 - 1, 2 do
        upper[#upper + 1] = { side = "N", at = px, kind = "frame" }
        upper[#upper + 1] = { side = "S", at = px, kind = "frame" }
    end
    for py = y + 2, y2 - 1, 2 do
        upper[#upper + 1] = { side = "W", at = py, kind = "frame" }
        upper[#upper + 1] = { side = "E", at = py, kind = "frame" }
    end
    Architect.box(plan, x, y, x2, y2, first, fam, upper)

    Architect.box(plan, x, y, x2, y2, roof, Architect.family.parapet, {})

    Architect.wallLamp(plan, x + 1, y, z, "N")
    for px = x2 - 4, x + 3, -1 do
        if plan.wallN[Architect.key(px, y, z)] then
            Architect.wallLamp(plan, px, y, z, "N")
            break
        end
    end
    Architect.wallLamp(plan, x + 1, y, first, "N")

    local room = Architect.rooms[kind] or Architect.rooms.storage
    for _, item in ipairs(room.ground or {}) do
        Architect.furnish(plan, x + item[2] - 1, y + item[3] - 1, z, item[1])
    end
    for _, item in ipairs(room.upper or {}) do
        Architect.furnish(plan, x + item[2] - 1, y + item[3] - 1, first, item[1])
    end
    if room.radio ~= nil then
        Architect.onTop(plan, x + room.radio[1] - 1, y + room.radio[2] - 1, z,
            Architect.piece.hamRadio, "radio")
    end
    for _, store in ipairs(Architect.stores[kind] or {}) do
        for py = y + 1, y2 - 1 do
            local placed = false
            for px = x + 1, x2 - 2 do
                if Architect.standable(plan, px, py, z) then
                    plan.solid[Architect.key(px, py, z)] = true
                    Architect.emit(plan, { op = "container", x = px, y = py, z = z,
                        sprite = store[1], loot = store[2], draws = store[3] })
                    placed = true
                    break
                end
            end
            if placed then break end
        end
    end

    for _, p in ipairs(room.posts or {}) do
        local px, py, pz = x + p[1] - 1, y + p[2] - 1, z + p[3]
        if Architect.standable(plan, px, py, pz) then Architect.post(plan, px, py, pz, p[4]) end
    end
    Architect.post(plan, x + 2, y2, first, "window")
    Architect.post(plan, x + 1, y2, roof, "roof")
    Architect.metrics.buildings = Architect.metrics.buildings + 1
    return { x = x, y = y, x2 = x2, y2 = y2, doorX = doorX, doorY = y2 + 1 }
end

function Architect.tower(plan, x, y, z, doorSide, lookFacing)
    local fam = Architect.family.wood
    local x2, y2 = x + 4, y + 2
    local top = z + 1
    Architect.flight(plan, x + 3, y + 1, z)
    for px = x, x2 do
        for py = y, y2 do
            Architect.floorAt(plan, px, py, z, Architect.piece.floor)
            Architect.floorAt(plan, px, py, top, Architect.piece.floor)
        end
    end
    local doorY = doorSide == "N" and y or y2
    Architect.keepFree(plan, x2, doorY, z)
    Architect.keepFree(plan, x2, y + 1, z)
    Architect.box(plan, x, y, x2, y2, z, fam,
        { { side = doorSide == "N" and "N" or "S", at = x2, kind = "door" },
          { side = "W", at = y + 1, kind = "window" } })
    Architect.box(plan, x, y, x2, y2, top, Architect.family.parapet, {})
    Architect.post(plan, x + 1, y, top, "sniper", "sniper")
    Architect.post(plan, x + 3, y2, top, "sniper", "sniper")
    Architect.flood(plan, x, y2, top, lookFacing or "S")
    Architect.metrics.towers = Architect.metrics.towers + 1
end

function Architect.garage(plan, x, y, w, h, z)
    local fam = Architect.family.garage
    local x2, y2 = x + w - 1, y + h - 1
    local doorX = x + math.floor((w - 3) / 2)
    for px = x, x2 do
        for py = y, y2 do
            Architect.floorAt(plan, px, py, z, Architect.piece.concrete)
            Architect.floorAt(plan, px, py, z + 1, Architect.piece.roof)
        end
    end

    for px = doorX, doorX + 2 do
        for py = y + 1, y2 do Architect.keepFree(plan, px, py, z) end
    end
    Architect.box(plan, x, y, x2, y2, z, fam, { { side = "S", at = doorX, kind = "garage" } })
    Architect.furnish(plan, x, y, z, "furniture_shelving_01_16")
    Architect.furnish(plan, x2, y, z, "location_military_generic_01_0")
    Architect.furnish(plan, x2, y + 2, z, "furniture_tables_high_01_16")

    Architect.emit(plan, { op = "vehicle", x = doorX + 1, y = y + math.floor(h / 2), z = z,
        script = plan.roll() < 0.5 and "Base.Van" or "Base.CarNormal", facing = "S", fuel = 0 })
    Architect.post(plan, x2 - 1, y + 1, z, "mechanic")
    return { x = x, y = y, x2 = x2, y2 = y2, doorX = doorX + 1, doorY = y2 + 1 }
end

function Architect.pen(plan, x, y, w, h, z, animals)
    local x2, y2 = x + w - 1, y + h - 1
    local gateX = x + math.floor(w / 2)
    Architect.box(plan, x, y, x2, y2, z, Architect.family.railing,
        { { side = "S", at = gateX, kind = "farmgate" } })
    Architect.emit(plan, { op = "items", x = x + 1, y = y2, z = z,
        item = "Base.AnimalFeedBag", quantity = 1 })
    Architect.emit(plan, { op = "items", x = x2 - 1, y = y2, z = z,
        item = "Base.HayTuft", quantity = 4 })
    local spots = { { x + 1, y + 1 }, { x2 - 1, y + 1 }, { x + 2, y2 - 1 }, { x2 - 2, y2 - 1 } }
    for index, animal in ipairs(animals or {}) do
        local spot = spots[((index - 1) % #spots) + 1]
        Architect.emit(plan, { op = "animal", x = spot[1], y = spot[2], z = z, animal = animal })
    end
    Architect.post(plan, gateX, y2 + 2, z, "farm")
    return { x = x, y = y, x2 = x2, y2 = y2, doorX = gateX, doorY = y2 + 1 }
end

function Architect.square(plan, cx, cy, z)
    Architect.emit(plan, { op = "campfire", x = cx, y = cy, z = z, sprite = Architect.piece.campfire })
    plan.solid[Architect.key(cx, cy, z)] = true
    Architect.furnish(plan, cx - 1, cy - 3, z, "benchFacingS")
    Architect.furnish(plan, cx - 1, cy + 3, z, "benchFacingN")
    Architect.furnish(plan, cx - 3, cy - 1, z, "benchFacingE")
    Architect.furnish(plan, cx + 3, cy - 1, z, "benchFacingW")

    for _, spot in ipairs({ { 0, -2 }, { 0, 2 }, { -2, 0 }, { 2, 0 }, { -2, -2 }, { 2, 2 }, { -2, 2 } }) do
        Architect.post(plan, cx + spot[1], cy + spot[2], z, "sit", nil, { x = cx + 0.5, y = cy + 0.5 })
    end
    Architect.post(plan, cx + 2, cy - 2, z, "guitar", nil, { x = cx + 0.5, y = cy + 0.5 })
    Architect.flood(plan, cx + 5, cy + 5, z, "N")
    Architect.flood(plan, cx - 5, cy + 5, z, "N")
end

function Architect.farm(plan, x, y, w, h, z)
    local piece = Architect.piece
    for py = y, y + h - 1 do
        local furrow = (py - y) % 3 == 1
        for px = x, x + w - 1 do
            Architect.emit(plan, { op = "floor", x = px, y = py, z = z,
                sprite = piece.dirt[(math.abs(px * 7 + py * 3) % #piece.dirt) + 1] })
            if furrow then
                Architect.keepFree(plan, px, py, z)
            elseif Architect.standable(plan, px, py, z) then
                plan.solid[Architect.key(px, py, z)] = true
                Architect.tile(plan, px, py, z, piece.crops[(math.abs(px * 5 + py * 11) % #piece.crops) + 1])
            end
        end
    end
    local spots = { x + 2, x + math.floor(w / 2), x + w - 3 }
    for index, fx in ipairs(spots) do
        Architect.post(plan, fx, y + 1 + ((index + 1) % 2) * 3, z, "farm")
    end
end

function Architect.parking(plan, x, y, w, h, z, driveX, driveY)
    for px = x, x + w - 1 do
        for py = y, y + h - 1 do
            Architect.emit(plan, { op = "floor", x = px, y = py, z = z, sprite = Architect.piece.concrete })
        end
    end
    for px = driveX - 1, driveX + 1 do
        for py = driveY, y - 1 do
            Architect.emit(plan, { op = "floor", x = px, y = py, z = z, sprite = Architect.piece.concrete })
        end
    end
    if plan.roll() < 0.5 then
        Architect.emit(plan, { op = "vehicle", x = x + math.floor(w / 2), y = y + math.floor(h / 2), z = z,
            script = "Base.PickUpTruck", facing = "E", fuel = 0 })
    end
    for px = x, x + w - 1 do
        for py = y, y + h - 1 do Architect.keepFree(plan, px, py, z) end
    end
end

function Architect.track(plan, x1, y1, x2, y2, z, width)
    Architect.emit(plan, { op = "track", x = x1, y = y1, x2 = x2, y2 = y2, z = z, width = width })
end

Architect.checkpointPieces = { sandbagN = "carpentry_02_13", metalN = "constructedobjects_01_49" }

function Architect.checkpoint(cx, cy, z, seed)

    local plan = Architect.newPlan(seed)
    local sand = Architect.checkpointPieces.sandbagN
    local function row(fromX, toX, y)
        for dx = fromX, toX do
            Architect.tile(plan, cx + dx, cy + y, z, sand)
            markN(plan, cx + dx, cy + y, z)
            plan.wallN[Architect.key(cx + dx, cy + y, z)] = true
        end
    end

    local metal = Architect.checkpointPieces.metalN
    local function wall(fromX, toX, y)
        for dx = fromX, toX do
            Architect.tile(plan, cx + dx, cy + y, z, metal)
            markN(plan, cx + dx, cy + y, z)
            plan.wallN[Architect.key(cx + dx, cy + y, z)] = true
        end
    end
    wall(-24, -19, 4)

    local bridge = { x = cx + 0.5, y = cy + 24.5 }

    row(-7, 6, -10)
    for _, dx in ipairs({ -6, -3, 0, 3, 6 }) do
        Architect.post(plan, cx + dx, cy - 11, z, "guard", nil, { x = cx + dx + 0.5, y = cy + 24.5 })
    end

    row(-17, -10, 0)
    Architect.post(plan, cx - 13, cy - 1, z, "guard", "gunner", bridge)
    Architect.post(plan, cx - 15, cy - 1, z, "guard", nil, bridge)
    Architect.post(plan, cx - 11, cy - 1, z, "guard", nil, bridge)

    row(10, 18, 0)
    for _, dx in ipairs({ 11, 14, 17 }) do
        Architect.post(plan, cx + dx, cy - 1, z, "sniper", "sniper", bridge)
    end

    local fx, fy = cx - 14, cy - 18
    Architect.emit(plan, { op = "campfire", x = fx, y = fy, z = z, sprite = Architect.piece.campfire })
    plan.solid[Architect.key(fx, fy, z)] = true
    local fire = { x = fx + 0.5, y = fy + 0.5 }
    for _, spot in ipairs({ { 0, -2 }, { -2, -1 }, { 2, -1 }, { -2, 1 }, { 2, 1 }, { 0, 2 } }) do
        Architect.post(plan, fx + spot[1], fy + spot[2], z, "sit", nil, fire)
    end

    Architect.post(plan, cx - 18, cy - 18, z, "radio", nil, { x = cx - 18.5, y = cy - 17.5 })

    for _, spot in ipairs({ { -19, -22 }, { -11, -22 }, { -19, -14 }, { -11, -14 } }) do
        Architect.furnish(plan, cx + spot[1], cy + spot[2], z, "tent")
    end

    for _, spot in ipairs({ { -8, -12 }, { 8, -12 }, { -10, -3 }, { 9, -3 } }) do
        Architect.flood(plan, cx + spot[1], cy + spot[2], z, "S")
    end

    local order = { guard = 1, sniper = 2, radio = 3, sit = 4 }
    table.sort(plan.posts, function(a, b)
        local ra, rb = order[a.role] or 9, order[b.role] or 9
        if ra ~= rb then return ra < rb end
        if (a.conduct == "gunner") ~= (b.conduct == "gunner") then return a.conduct == "gunner" end
        if a.y ~= b.y then return a.y < b.y end
        return a.x < b.x
    end)
    return plan
end

function Architect.compound(cx, cy, z, half, seed)
    local plan = Architect.newPlan(seed)
    local x1, y1, x2, y2 = cx - half, cy - half, cx + half, cy + half

    local gateX = cx - 2
    local gateEast = gateX + 4
    local wall = Architect.family.palisade

    local doors = {}
    local function lot(kind, lx, ly, w, h)
        local b = Architect.building(plan, cx + lx, cy + ly, w, h, z, kind)
        doors[#doors + 1] = b
        return b
    end

    lot("barracks", -24, -25, 11, 7)
    lot("mess", -8, -25, 13, 7)
    lot("barracks", 10, -25, 11, 7)

    local armoury = lot("armoury", -24, -12, 9, 7)
    lot("workshop", -13, -12, 9, 7)
    lot("medical", 6, -12, 9, 7)
    lot("command", 16, -12, 10, 7)

    local garage = Architect.garage(plan, cx - 24, cy + 9, 8, 7, z)
    doors[#doors + 1] = garage
    lot("storage", -13, 9, 9, 7)
    local pen = Architect.pen(plan, cx + 7, cy + 9, 9, 6, z, { "hen", "hen", "cow" })
    doors[#doors + 1] = pen
    lot("barracks", 18, 9, 9, 7)

    for px = cx - 4, cx + 4 do
        for py = cy - 4, cy + 4 do
            Architect.emit(plan, { op = "floor", x = px, y = py, z = z,
                sprite = ((px + py) % 3 == 0) and "blends_natural_01_70" or "blends_natural_01_69" })
        end
    end
    Architect.square(plan, cx, cy, z)

    local innerY = cy + 6
    Architect.box(plan, x1, y1, x2, y2, z, wall,
        { { side = "S", at = gateX, kind = "bigGate" }, { side = "W", at = innerY, kind = "junction" } })

    local ax1, ax2, ay1 = gateX - 4, gateEast + 3, y2 - 5
    Architect.tile(plan, ax1, ay1, z, wall.nw)
    markN(plan, ax1, ay1, z)
    markW(plan, ax1, ay1, z)
    Architect.runN(plan, ax1 + 1, ax2, ay1, z, wall, { { side = "N", at = gateX, kind = "bigGate" } }, "N")
    Architect.runW(plan, ax1, ay1 + 1, y2, z, wall, {}, "W")
    Architect.runW(plan, ax2 + 1, ay1, y2, z, wall, {}, "E")

    Architect.runN(plan, x1 + 1, x2, innerY, z, wall, { { side = "N", at = gateX, kind = "bigGate" } }, "N")

    Architect.tower(plan, x1 + 1, y1 + 1, z, "S", "N")
    Architect.tower(plan, x2 - 5, y1 + 1, z, "S", "N")
    Architect.tower(plan, x1 + 1, y2 - 3, z, "N", "S")
    Architect.tower(plan, x2 - 5, y2 - 3, z, "N", "S")

    for _, side in ipairs({ -1, 1 }) do
        local near = side < 0 and gateX - 2 or gateEast + 1
        local far = near + side
        Architect.furnish(plan, near, y2 + 3, z, Architect.piece.barrier)
        Architect.furnish(plan, far, y2 + 3, z, Architect.piece.barrier)
        Architect.post(plan, near, y2 + 2, z, "guard")
        Architect.post(plan, far, y2 + 2, z, "guard")
        Architect.post(plan, near, y2 - 1, z, "guard")
        Architect.post(plan, near, ay1 - 1, z, "guard")
        Architect.post(plan, near, innerY - 1, z, "guard")
    end
    Architect.flood(plan, gateX - 3, y2 - 2, z, "S")
    Architect.flood(plan, gateEast + 2, y2 - 2, z, "S")

    for _, dx in ipairs({ -2, -1, 1, 2 }) do
        Architect.post(plan, armoury.doorX + dx, armoury.doorY + 3, z, "squad")
    end

    Architect.track(plan, gateX + 1, y2 + 14, gateX + 1, cy + 5, z, 4)
    Architect.track(plan, x1 + 2, cy - 17, x2 - 2, cy - 17, z, 2)
    Architect.track(plan, cx - 1, cy - 4, cx - 1, cy - 17, z, 2)
    Architect.track(plan, x1 + 2, cy - 4, x2 - 2, cy - 4, z, 1)
    Architect.track(plan, x1 + 2, cy + 17, x2 - 2, cy + 17, z, 2)
    for _, d in ipairs(doors) do
        local street = d.doorY <= cy - 17 and cy - 17 or d.doorY <= cy - 4 and cy - 4 or cy + 17
        if d.doorY < street then
            Architect.track(plan, d.doorX, d.doorY, d.doorX, street, z, 1)
        else
            Architect.track(plan, d.doorX, street, d.doorX, d.doorY, z, 1)
        end
    end

    Architect.parking(plan, cx - 24, cy + 20, 13, 5, z, garage.doorX, garage.doorY)
    Architect.farm(plan, cx + 8, cy + 20, 15, 6, z)

    Architect.post(plan, cx - 20, cy - 17, z, "patrol")
    Architect.post(plan, cx + 20, cy - 17, z, "patrol")
    Architect.post(plan, cx - 20, cy + 17, z, "patrol")
    Architect.post(plan, cx + 20, cy + 17, z, "patrol")

    Architect.metrics.compounds = Architect.metrics.compounds + 1

    local order = { guard = 1, sniper = 2, sit = 3, guitar = 3, roof = 4, squad = 9,
        farm = 5, patrol = 6, window = 10, mechanic = 7, radio = 11, work = 8,
        eat = 12, drink = 12, rest = 13 }

    local limits = { guard = 8, sit = 3,
        roof = 2, farm = 2, patrol = 2, mechanic = 1, work = 1 }
    local used, rank = {}, {}
    for _, post in ipairs(plan.posts) do
        used[post.role] = (used[post.role] or 0) + 1
        rank[post] = (order[post.role] or 99)
            + ((limits[post.role] and used[post.role] > limits[post.role]) and 20 or 0)
    end
    table.sort(plan.posts, function(a, b)
        local ra, rb = rank[a], rank[b]
        if ra ~= rb then return ra < rb end

        if a.role == "guard" and a.y ~= b.y then return a.y > b.y end
        if a.y ~= b.y then return a.y < b.y end
        return a.x < b.x
    end)
    return plan
end

return Architect
