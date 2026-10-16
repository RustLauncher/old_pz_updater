require "ProjectALife/Interface/ALifePeekDoorData"

ProjectALife = ProjectALife or {}

local Data = ProjectALife.PeekData
local SD = {}
ProjectALife.PeekSceneData = SD

SD.camHeight = 1.55
SD.minD = 0.3
SD.perSquare = 6
SD.maxSprites = 150
SD.sceneMs = 500
SD.textureCap = 700
SD.diamond = 64
SD.hazeStep = 0.04
SD.hazeBase = 0.03
SD.maxQuad = 12
SD.rainMin = 0.08
SD.rainDrops = 28
SD.floorWidth = 128
SD.floorHeight = 64

SD.edgeFlags = {
    n = { "WallN", "WallNTrans", "WindowN", "windowN", "doorN", "DoorWallN", "HoppableN", "TallHoppableN" },
    w = { "WallW", "WallWTrans", "WindowW", "windowW", "doorW", "DoorWallW", "HoppableW", "TallHoppableW" },
}
SD.skipFlags = { "invisible", "WallOverlay", "attachedN", "attachedW", "attachedS", "attachedE", "attachedNW",
    "attachedSE", "attachedCeiling", "attachedSurface", "sheetCurtains" }
SD.floorFlags = { "FloorOverlay", "diamondFloor" }
SD.opaqueFlags = { "WallN", "WallW", "WallNW", "WallSE", "doorN", "doorW", "DoorWallN", "DoorWallW" }

function SD.units(scale)
    local s = tonumber(scale) or 2
    if s < 1 then s = 1 end
    return SD.diamond * s / 1.4142135623731, SD.diamond * 0.5 * s
end

function SD.project(view, depth, lateral, z)
    local d = depth + Data.eyeBack
    if d < SD.minD then return nil, nil end
    local scale = view.focal / d
    return view.cx + Data.barrel(lateral * scale, view.rx), view.horizon + (SD.camHeight - z) * scale
end

function SD.groundY(view, depth)
    return view.horizon + SD.camHeight * view.focal / math.max(depth + Data.eyeBack, SD.minD)
end

function SD.corner(q, index, x, y)
    if x == nil or y == nil then return false end
    q[index * 2 - 1], q[index * 2] = x, y
    return true
end

function SD.floorPoint(view, geo, wx, wy, wo, oy, u, v)
    local dx, dy = u - wo / 2, v - oy
    local depth, lateral = Data.coords(geo, wx + (dx + 2 * dy) / wo, wy + (2 * dy - dx) / wo)
    return SD.project(view, depth, lateral, 0)
end

function SD.floorQuad(view, geo, wx, wy, q, wo, ho, l, t, r, b)
    wo, ho = wo or SD.floorWidth, ho or SD.floorHeight
    l, t, r, b = l or 0, t or 0, r or wo, b or ho
    local oy = ho - wo / 2
    return SD.corner(q, 1, SD.floorPoint(view, geo, wx, wy, wo, oy, l, t))
        and SD.corner(q, 2, SD.floorPoint(view, geo, wx, wy, wo, oy, r, t))
        and SD.corner(q, 3, SD.floorPoint(view, geo, wx, wy, wo, oy, r, b))
        and SD.corner(q, 4, SD.floorPoint(view, geo, wx, wy, wo, oy, l, b))
end

function SD.edgePoint(view, geo, wx, wy, west, wo, oy, ppuV, u, v)
    local half = wo / 2
    local s = (u - half) / half
    if west then s = (half - u) / half end
    local z = (oy + s * wo / 4 - v) / ppuV
    local px, py = wx + s, wy
    if west then px, py = wx, wy + s end
    local depth, lateral = Data.coords(geo, px, py)
    return SD.project(view, depth, lateral, z)
end

function SD.edgeQuad(view, geo, wx, wy, west, q, wo, ho, l, t, r, b, ppuV)
    local oy = ho - wo / 2
    return SD.corner(q, 1, SD.edgePoint(view, geo, wx, wy, west, wo, oy, ppuV, l, t))
        and SD.corner(q, 2, SD.edgePoint(view, geo, wx, wy, west, wo, oy, ppuV, r, t))
        and SD.corner(q, 3, SD.edgePoint(view, geo, wx, wy, west, wo, oy, ppuV, r, b))
        and SD.corner(q, 4, SD.edgePoint(view, geo, wx, wy, west, wo, oy, ppuV, l, b))
end

function SD.billPoint(view, depth, lateral, ax, ay, ppuH, ppuV, u, v)
    return SD.project(view, depth, lateral + (u - ax) / ppuH, (ay - v) / ppuV)
end

function SD.billQuad(view, geo, wx, wy, q, ax, ay, ppuH, ppuV, l, t, r, b)
    local depth, lateral = Data.coords(geo, wx, wy)
    return SD.corner(q, 1, SD.billPoint(view, depth, lateral, ax, ay, ppuH, ppuV, l, t))
        and SD.corner(q, 2, SD.billPoint(view, depth, lateral, ax, ay, ppuH, ppuV, r, t))
        and SD.corner(q, 3, SD.billPoint(view, depth, lateral, ax, ay, ppuH, ppuV, r, b))
        and SD.corner(q, 4, SD.billPoint(view, depth, lateral, ax, ay, ppuH, ppuV, l, b))
end

function SD.bounds(q, view)
    local x0, y0, x1, y1 = q[1], q[2], q[1], q[2]
    for index = 3, 7, 2 do
        local x, y = q[index], q[index + 1]
        if x < x0 then x0 = x end
        if x > x1 then x1 = x end
        if y < y0 then y0 = y end
        if y > y1 then y1 = y end
    end
    q.bx0, q.by0, q.bx1, q.by1 = x0, y0, x1, y1
    local lx, ly, lw, lh = 0, 0, view.w, view.h
    if view.full == true then lx, ly, lw, lh = view.sx, view.sy, view.sw, view.sh end
    if x1 < lx or x0 > lx + lw or y1 < ly or y0 > ly + lh then return false end
    if x1 - x0 > lw * SD.maxQuad or y1 - y0 > lh * SD.maxQuad then return false end
    return x1 - x0 >= 0.75 and y1 - y0 >= 0.75
end

function SD.trim(wo, ho, w, h, ox, oy)
    wo, ho = tonumber(wo), tonumber(ho)
    w, h = tonumber(w) or wo, tonumber(h) or ho
    if wo == nil or ho == nil or wo <= 0 or ho <= 0 or w == nil or h == nil or w <= 0 or h <= 0 then return nil end
    local left, top = 0, 0
    if w < wo or h < ho then left, top = tonumber(ox) or 0, tonumber(oy) or 0 end
    if left < 0 or top < 0 or left + w > wo + 0.5 or top + h > ho + 0.5 then left, top = 0, 0 end
    return wo, ho, left, top, left + w, top + h
end

function SD.has(props, name, flags)
    local flag = type(flags) == "table" and flags[name] or nil
    if flag == nil or props == nil or type(props.has) ~= "function" then return false end
    local ok, value = pcall(props.has, props, flag)
    return ok and value == true
end

function SD.anyFlag(props, list, flags)
    for index = 1, #list do
        if SD.has(props, list[index], flags) then return true end
    end
    return false
end

function SD.classify(props, flags)
    if props == nil then return "bill" end
    if SD.anyFlag(props, SD.skipFlags, flags) then return nil end
    if SD.anyFlag(props, SD.floorFlags, flags) then return "floor2" end
    if SD.has(props, "WallNW", flags) then return "cornerNW" end
    if SD.has(props, "WallSE", flags) then return "cornerSE" end
    if SD.anyFlag(props, SD.edgeFlags.n, flags) then return "edgeN" end
    if SD.anyFlag(props, SD.edgeFlags.w, flags) then return "edgeW" end
    return "bill"
end

function SD.occlude(list, count, depth, low, high)
    local at = count * 3
    list[at + 1], list[at + 2], list[at + 3] = depth, low, high
    return count + 1
end

function SD.edgeOccluder(list, count, depthA, lateralA, depthB, lateralB)
    if math.abs(depthA - depthB) > 0.05 or depthA < 0.3 then return count end
    local d = depthA + Data.eyeBack
    return SD.occlude(list, count, depthA, math.min(lateralA, lateralB) / d, math.max(lateralA, lateralB) / d)
end

function SD.cellOccluder(list, count, depth, lateral)
    local near, far = depth + Data.eyeBack, depth + 1 + Data.eyeBack
    local low = math.min((lateral - 0.5) / near, (lateral - 0.5) / far)
    local high = math.max((lateral + 0.5) / near, (lateral + 0.5) / far)
    return SD.occlude(list, count, depth, low, high)
end

function SD.shadowed(list, count, depth, lateral)
    local ratio = lateral / (depth + Data.eyeBack)
    for index = 0, count - 1 do
        local at = index * 3
        if depth > list[at + 1] and ratio >= list[at + 2] and ratio <= list[at + 3] then return true end
    end
    return false
end

function SD.tint(light, overcast, er, eg, eb)
    if type(er) == "number" and type(eg) == "number" and type(eb) == "number" and er + eg + eb > 0.3 then
        return Data.clamp(er, 0.12, 1), Data.clamp(eg, 0.12, 1), Data.clamp(eb, 0.12, 1)
    end
    local day = Data.clamp(light, 0, 1)
    local shade = (0.16 + 0.84 * day) * (1 - 0.18 * Data.clamp(overcast, 0, 1))
    local night = 1 - day
    return shade * (1 - 0.1 * night), shade, math.min(1, shade + 0.12 * night)
end

function SD.hazeAlpha(overcast)
    return SD.hazeBase + SD.hazeStep * Data.clamp(overcast, 0, 1)
end

function SD.paint(a, b)
    if a.key ~= b.key then return a.key > b.key end
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.span ~= b.span then return a.span > b.span end
    return a.n < b.n
end

function SD.tileKey(k)
    return k + 0.5
end

function SD.hazeKey(j)
    return j + 0.0005
end

function SD.overlaps(q, x, y, w, h)
    return q.bx0 < x + w and q.bx1 > x and q.by0 < y + h and q.by1 > y
end

function SD.rainAt(drop, now, height)
    local span = height + 24
    local y = (drop.y + now * drop.speed) % span
    return drop.x, y - 12
end

return SD
