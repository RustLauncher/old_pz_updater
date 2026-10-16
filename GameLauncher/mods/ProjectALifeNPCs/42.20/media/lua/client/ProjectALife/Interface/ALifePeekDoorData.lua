require "ProjectALife/Core/ALifeText"

ProjectALife = ProjectALife or {}

local Text = ProjectALife.Text
local Data = {}
ProjectALife.PeekData = Data

Data.maxDepth = 8
Data.liveDepth = 14
Data.rowHalf = { 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7 }
Data.fovTan = 0.5
Data.eyeBack = 0.8
Data.bodyTiles = 0.8
Data.eyeRatio = 0.9
Data.horizon = 0.4
Data.identifyRange = 3
Data.labelRange = 6
Data.modelRange = 6
Data.maxModels = 4
Data.maxFigures = 14
Data.maxObjects = 60
Data.refreshMs = 280
Data.leanMs = 1200
Data.noticeGapMs = 5000
Data.noticeRange = 2
Data.noticeDefault = 5
Data.reach = 2.5
Data.visitReach = 8
Data.moveLimit = 0.9
Data.contactRange = 1.4
Data.damageDrop = 0.5
Data.smooth = 0.35
Data.modelZoom = -3
Data.modelYOffset = 0
Data.modelKinds = { npc = true, player = true, zombie = true }
Data.modelRank = { npc = 1, player = 1, zombie = 2 }
Data.liveBody = 1.8
Data.liveCam = 1.55

Data.stanceRank = { friendly = 0, allied = 0, neutral = 1, careful = 2, hostile = 3 }
Data.stanceTone = { [0] = "good", [1] = "neutral", [2] = "careful", [3] = "bad" }
Data.tones = {
    title = { 0.92, 0.92, 0.86 }, dim = { 0.62, 0.66, 0.60 }, warn = { 1.0, 0.62, 0.25 },
    bad = { 0.95, 0.38, 0.32 }, good = { 0.55, 0.85, 0.50 }, neutral = { 0.82, 0.82, 0.72 },
    careful = { 0.92, 0.70, 0.32 },
}
Data.ground = {
    road = { 0.20, 0.20, 0.22 }, grass = { 0.16, 0.28, 0.12 }, dirt = { 0.28, 0.22, 0.15 },
    sand = { 0.42, 0.38, 0.27 }, paved = { 0.32, 0.32, 0.31 }, indoor = { 0.25, 0.19, 0.14 },
}
Data.sky = {
    nightTop = { 0.015, 0.02, 0.05 }, nightLow = { 0.05, 0.06, 0.10 },
    clearTop = { 0.22, 0.36, 0.56 }, clearLow = { 0.55, 0.66, 0.78 },
    grayTop = { 0.28, 0.30, 0.33 }, grayLow = { 0.50, 0.52, 0.54 },
}

function Data.clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

function Data.lerp(a, b, t)
    return a + (b - a) * t
end

function Data.enabled(pref, sandbox)
    return pref ~= false and sandbox ~= false
end

function Data.tone(name)
    local row = Data.tones[name] or Data.tones.title
    return row[1], row[2], row[3]
end

function Data.edgeOther(x, y, north)
    if north then return x, y - 1 end
    return x - 1, y
end

function Data.chooseFar(ownOutside, otherOutside, ownDistance, otherDistance)
    if ownOutside == true and otherOutside == true then return nil end
    if ownOutside ~= otherOutside then return ownOutside == true end
    return ownDistance > otherDistance
end

function Data.geometry(x, y, north, farIsOwn)
    local step = -1
    if farIsOwn then step = 1 end
    local ox, oy = 0, 0
    local cx, cy = x, y + 0.5
    if north then
        oy = step
        cx, cy = x + 0.5, y
    else
        ox = step
    end
    local otherX, otherY = Data.edgeOther(x, y, north)
    local geo = { x = x, y = y, north = north == true, ox = ox, oy = oy, rx = 0 - oy, ry = ox, cx = cx, cy = cy }
    if farIsOwn then
        geo.farX, geo.farY, geo.nearX, geo.nearY = x, y, otherX, otherY
    else
        geo.farX, geo.farY, geo.nearX, geo.nearY = otherX, otherY, x, y
    end
    return geo
end

function Data.coords(geo, px, py)
    local dx, dy = px - geo.cx, py - geo.cy
    return dx * geo.ox + dy * geo.oy, dx * geo.rx + dy * geo.ry
end

function Data.halfWidth(depth)
    return Data.fovTan * (math.max(depth, 0) + Data.eyeBack)
end

function Data.inCone(depth, lateral, limit)
    if depth < 0 or depth > (limit or Data.maxDepth) then return false end
    return math.abs(lateral) <= Data.halfWidth(depth)
end

function Data.cells(geo, depth)
    local list = {}
    for k = 0, (depth or Data.maxDepth) - 1 do
        local half = Data.rowHalf[k + 1]
        for c = 0 - half, half do
            list[#list + 1] = { geo.farX + k * geo.ox + c * geo.rx, geo.farY + k * geo.oy + c * geo.ry, k, c }
        end
    end
    return list
end

function Data.view(width, height)
    return { w = width, h = height, cx = width / 2, cy = height / 2, rx = width / 2, ry = height / 2,
        horizon = height * Data.horizon, focal = width / (2 * Data.fovTan) }
end

function Data.barrel(u, radius)
    local limit = radius * 1.5
    local v = Data.clamp(u, 0 - limit, limit)
    local r = v / radius
    return v / (1 + 0.18 * r * r)
end

function Data.project(depth, lateral, view)
    local d = math.max(depth, 0) + Data.eyeBack
    local scale = view.focal / d
    local h = math.min(Data.bodyTiles * scale, view.h * 0.9)
    local feet = view.horizon + Data.eyeRatio * h
    local limit = view.h - 2
    if feet > limit then feet = limit end
    return { x = view.cx + Data.barrel(lateral * scale, view.rx), feet = feet, w = h * 0.5, h = h, scale = scale, d = d }
end

function Data.projectLive(depth, lateral, view)
    local d = math.max(depth, 0) + Data.eyeBack
    local scale = view.focal / d
    local h = math.min(Data.liveBody * scale, view.capH or view.h * 0.9)
    local feet = view.horizon + Data.liveCam * scale
    local limit = view.footY or view.h - 2
    if feet > limit then feet = limit end
    return { x = view.cx + Data.barrel(lateral * scale, view.rx), feet = feet, w = h * 0.5, h = h, scale = scale, d = d }
end

function Data.fitX(view, x, feet, w, h)
    local ratio = (feet - h / 2 - view.cy) / view.ry
    local half = 0
    if ratio > -0.98 and ratio < 0.98 then half = view.rx * math.sqrt(1 - ratio * ratio) - 6 end
    local low, high = view.cx - half + w / 2, view.cx + half - w / 2
    if low > high then return view.cx end
    return Data.clamp(x, low, high)
end

function Data.labelBox(view, e, plateW, plateH)
    local x = Data.clamp(e.x - plateW / 2, 2, view.w - plateW - 2)
    local below = e.y + 4
    if below + plateH <= view.h - 2 then return x, below end
    local above = e.y - e.h - plateH - 4
    if above >= 2 then return x, above end
    local middle = Data.clamp(e.y - e.h / 2 - plateH / 2, 2, view.h - plateH - 2)
    local right = e.x + e.w / 2 + 6
    if right + plateW <= view.w - 2 then return right, middle end
    local left = e.x - e.w / 2 - 6 - plateW
    if left >= 2 then return left, middle end
    return x, Data.clamp(below, 2, view.h - plateH - 2)
end

function Data.groundY(depth, view)
    return view.horizon + Data.eyeRatio * Data.bodyTiles * view.focal / (math.max(depth, 0) + Data.eyeBack)
end

function Data.farFirst(a, b)
    if a.depth ~= b.depth then return a.depth > b.depth end
    if a.lateral ~= b.lateral then return a.lateral < b.lateral end
    return a.id < b.id
end

function Data.sortFigures(list)
    table.sort(list, Data.farFirst)
    return list
end

function Data.nearFirst(a, b)
    if a.depth ~= b.depth then return a.depth < b.depth end
    if a.lateral ~= b.lateral then return a.lateral < b.lateral end
    return a.id < b.id
end

function Data.modelFirst(a, b)
    local ra, rb = Data.modelRank[a.kind] or 9, Data.modelRank[b.kind] or 9
    if ra ~= rb then return ra < rb end
    return Data.nearFirst(a, b)
end

function Data.floorKind(name)
    if type(name) ~= "string" then return "paved" end
    local lowered = string.lower(name)
    if string.find(lowered, "interior", 1, true) ~= nil then return "indoor" end
    if string.find(lowered, "street", 1, true) ~= nil or string.find(lowered, "asphalt", 1, true) ~= nil then return "road" end
    if string.find(lowered, "natural", 1, true) ~= nil or string.find(lowered, "grass", 1, true) ~= nil then return "grass" end
    if string.find(lowered, "dirt", 1, true) ~= nil or string.find(lowered, "gravel", 1, true) ~= nil then return "dirt" end
    if string.find(lowered, "sand_", 1, true) ~= nil or string.find(lowered, "_sand", 1, true) ~= nil then return "sand" end
    return "paved"
end

function Data.weather(daylight, cloud, rain, fog)
    local light = Data.clamp(tonumber(daylight) or 0.6, 0, 1)
    local overcast = Data.clamp(math.max(tonumber(cloud) or 0, tonumber(rain) or 0, (tonumber(fog) or 0) * 0.8), 0, 1)
    return light, overcast, Data.clamp(tonumber(rain) or 0, 0, 1)
end

function Data.nightAlpha(light)
    return Data.clamp(0.38 * (1 - light), 0, 0.38)
end

function Data.skyChannel(index, t, light, overcast)
    local sky = Data.sky
    local top = Data.lerp(sky.nightTop[index], Data.lerp(sky.clearTop[index], sky.grayTop[index], overcast), light)
    local low = Data.lerp(sky.nightLow[index], Data.lerp(sky.clearLow[index], sky.grayLow[index], overcast), light)
    return Data.lerp(top, low, t)
end

function Data.skyColor(t, light, overcast)
    local warm = 4 * light * (1 - light) * (1 - overcast * 0.6) * t * t
    local r = Data.skyChannel(1, t, light, overcast) + 0.30 * warm
    local g = Data.skyChannel(2, t, light, overcast) + 0.10 * warm
    local b = Data.skyChannel(3, t, light, overcast)
    return Data.clamp(r, 0, 1), Data.clamp(g, 0, 1), Data.clamp(b, 0, 1)
end

function Data.groundColor(kind, depth, light, overcast)
    local base = Data.ground[kind] or Data.ground.paved
    local shade = 0.22 + 0.78 * light
    local haze = Data.clamp(depth / 10, 0, 1) * 0.6
    local hr, hg, hb = Data.skyColor(1, light, overcast)
    return Data.lerp(base[1] * shade, hr, haze), Data.lerp(base[2] * shade, hg, haze), Data.lerp(base[3] * shade, hb, haze)
end

function Data.stanceOf(relation, posture)
    local rank = 1
    if relation ~= nil and Data.stanceRank[relation] ~= nil then rank = Data.stanceRank[relation] end
    if rank == 0 or rank == 3 then return rank end
    if type(posture) == "table" then
        if posture.danger == "threat" or posture.danger == "alert" or posture.aim == true or posture.held == true then
            rank = math.max(rank, 2)
        end
    end
    return rank
end

function Data.stanceWord(rank)
    if rank == 0 then return Text.ui("Friendly") end
    if rank == 2 then return Text.ui("Wary") end
    if rank == 3 then return Text.ui("Hostile") end
    return Text.ui("Neutral")
end

function Data.isHuman(kind)
    return kind == "npc" or kind == "player"
end

function Data.detail(fig, reveal)
    local word = nil
    if fig.kind == "npc" and fig.known == true then word = Data.stanceWord(fig.stance or 1) end
    local role = nil
    if fig.kind == "npc" and fig.roleShown == true and fig.known == true and type(fig.role) == "string" and fig.role ~= "" then role = fig.role end
    if word == nil and role == nil then return nil end
    local text = word
    if word == nil then text = role elseif role ~= nil then text = role .. " - " .. word end
    return { text = text, tone = Data.stanceTone[fig.stance or 1] or "neutral" }
end

function Data.labelFor(fig, reveal)
    local dist = fig.dist or 0
    local label = { lines = {}, warn = fig.raised == true, bleeding = fig.bleeding == true }
    local kind = fig.kind
    if kind == "zombie" then return label end
    if dist > Data.labelRange then return label end
    local lines = label.lines
    if kind == "animal" then
        lines[1] = { text = Text.ui("Animal"), tone = "dim" }
        return label
    end
    if kind == "vehicle" then
        lines[1] = { text = Text.ui("Vehicle"), tone = "dim" }
        return label
    end
    local name = Text.ui("Stranger")
    local close = dist <= Data.identifyRange
    if close and fig.known == true and type(fig.name) == "string" and fig.name ~= "" then name = fig.name end
    if close and kind == "player" and type(fig.name) == "string" and fig.name ~= "" then name = fig.name end
    lines[1] = { text = name, tone = "title" }
    if not close then return label end
    local detail = Data.detail(fig, reveal)
    if detail ~= nil then lines[#lines + 1] = detail end
    if type(fig.hold) == "string" and fig.hold ~= "" then
        if fig.raised == true then
            lines[#lines + 1] = { text = Text.ui("Weapon raised: {item}", { item = fig.hold }), tone = "warn" }
        else
            lines[#lines + 1] = { text = Text.ui("Holding {item}", { item = fig.hold }), tone = "dim" }
        end
    elseif fig.raised == true then
        lines[#lines + 1] = { text = Text.ui("Weapon raised"), tone = "warn" }
    end
    if fig.bleeding == true then lines[#lines + 1] = { text = Text.ui("Bleeding"), tone = "bad" } end
    return label
end

function Data.distanceText(dist)
    local tiles = math.max(1, math.floor(dist + 0.5))
    if tiles == 1 then return Text.ui("1 tile") end
    return Text.ui("{n} tiles", { n = tiles })
end

function Data.counts(figures)
    local counts = { people = 0, zombies = 0, animals = 0, vehicles = 0, armed = 0, nearest = nil }
    for index = 1, #figures do
        local fig = figures[index]
        local kind = fig.kind
        if kind == "npc" or kind == "player" then
            counts.people = counts.people + 1
            if fig.raised == true then counts.armed = counts.armed + 1 end
        elseif kind == "zombie" then
            counts.zombies = counts.zombies + 1
        elseif kind == "animal" then
            counts.animals = counts.animals + 1
        elseif kind == "vehicle" then
            counts.vehicles = counts.vehicles + 1
        end
        local dist = fig.dist
        if dist ~= nil and (counts.nearest == nil or dist < counts.nearest) then counts.nearest = dist end
    end
    return counts
end

function Data.statusLines(counts)
    local lines = {}
    if counts.people == 0 and counts.zombies == 0 and counts.animals == 0 and counts.vehicles == 0 then
        lines[1] = { text = Text.ui("Nobody there"), tone = "dim" }
    end
    return lines
end

function Data.noticeNeeded(percent, roll)
    local chance = Data.clamp(tonumber(percent) or 0, 0, 100)
    if chance <= 0 then return false end
    return roll < chance
end

function Data.span(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

function Data.closeReason(state)
    if state.failed ~= nil then return "failed" end
    if state.gone == true then return "gone" end
    if state.doorGone == true then return "door_gone" end
    if state.doorOpen == true then return "door_open" end
    if state.floor ~= nil and state.startFloor ~= nil and state.floor ~= state.startFloor then return "floor" end
    if state.moved ~= nil and state.moved > Data.moveLimit then return "moved" end
    if state.damage ~= nil and state.damage >= Data.damageDrop then return "damage" end
    if state.contact == true then return "contact" end
    return nil
end

function Data.maskRows(view)
    local rows = {}
    local y = 0
    while y < view.h do
        local edge = math.abs((y + 0.5 - view.cy) / view.ry)
        local step = 4
        if edge > 0.88 then
            step = 1
        elseif edge > 0.6 then
            step = 2
        end
        if y + step > view.h then step = view.h - y end
        local ratio = (y + step / 2 - view.cy) / view.ry
        local half = 0
        if ratio > -1 and ratio < 1 then half = view.rx * math.sqrt(1 - ratio * ratio) end
        rows[#rows + 1] = { y, step, math.max(0, math.floor(view.cx - half)), math.min(view.w, math.ceil(view.cx + half)), step == 4 }
        y = y + step
    end
    return rows
end

function Data.wallColor(t, light)
    local shade = 0.35 + 0.65 * Data.clamp(light, 0, 1)
    return Data.lerp(0.10, 0.20, t) * shade, Data.lerp(0.085, 0.17, t) * shade, Data.lerp(0.075, 0.14, t) * shade
end

return Data
