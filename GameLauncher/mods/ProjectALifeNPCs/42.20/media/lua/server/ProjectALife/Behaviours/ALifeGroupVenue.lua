require "ProjectALife/Movement/ALifeGroupSpread"
require "ProjectALife/Movement/ALifeEntrances"

ProjectALife = ProjectALife or {}

local Spread = ProjectALife.GroupSpread

local Venue = {
    settings = {
        radius = 30,
        ringStep = 3,
        candidateLimit = 4,
        scanCap = 10,
        minArea = 12,
        maxArea = 700,
        ttlMs = 600000,
        cacheLimit = 24,
        spacing = 1.5,
        openSpacing = 2.0,
        entranceClear = 1.4,
        openingCost = 13,
        bannedMs = 600000,
        coverRays = 16,
        coverReach = { 4, 6, 8, 10, 12 },
        musterRadii = { 2.4, 3.4, 4.4 },
        musterRays = 24,
    },
    rays = {
        { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 },
        { 2, 1 }, { 1, 2 }, { -1, 2 }, { -2, 1 }, { -2, -1 }, { -1, -2 }, { 1, -2 }, { 2, -1 },
    },
    dirs = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } },
    cache = {},
    cacheCount = 0,
    claimed = {},
    banned = {},
    metrics = { scans = 0, analyses = 0, cacheHits = 0, covers = 0, rings = 0, solved = 0, unsolved = 0, tooSmall = 0 },
}
ProjectALife.GroupVenue = Venue

function Venue.nowMs()
    return Spread.nowMs()
end

function Venue.keyOf(x, y)
    return x * 4096 + y
end

function Venue.buildingKey(building)
    local key
    pcall(function() key = tostring(building:getID()) end)
    return key
end

function Venue.bounds(building)
    local x1, y1, x2, y2
    pcall(function()
        local def = building:getDef()
        if def ~= nil then x1, y1, x2, y2 = def:getX(), def:getY(), def:getX2(), def:getY2() end
    end)
    return x1, y1, x2, y2
end

function Venue.refused(building)
    local life = ProjectALife.ModuleIdleLife
    if life ~= nil and type(life.buildingRefused) == "function" then
        return life.buildingRefused(building) == true
    end
    return false
end

function Venue.inBase(x, y)
    local policy = ProjectALife.DoorPolicy
    if policy == nil or type(policy.inPlayerBase) ~= "function" then return false end
    local ok, inside = pcall(policy.inPlayerBase, x, y, true)
    return ok and inside == true
end

function Venue.outside(square)
    if square == nil then return false end
    local ok, value = pcall(square.isOutside, square)
    return ok and value == true
end

function Venue.buildingAt(square)
    if square == nil then return nil end
    local ok, building = pcall(square.getBuilding, square)
    if ok then return building end
    return nil
end

function Venue.ban(key, now)
    if key ~= nil then Venue.banned[key] = (tonumber(now) or Venue.nowMs()) + Venue.settings.bannedMs end
end

function Venue.claim(key, groupId)
    if key ~= nil then Venue.claimed[key] = groupId end
end

function Venue.release(groupId)
    for key, holder in pairs(Venue.claimed) do
        if holder == groupId then Venue.claimed[key] = nil end
    end
end

function Venue.infested(entry, z, now)
    local caution = ProjectALife.Caution
    if caution == nil or type(caution.bodies) ~= "function" then return false end
    local ok, rows = pcall(caution.bodies, now)
    if not ok or type(rows) ~= "table" then return false end
    for index = 1, #rows do
        local row = rows[index]
        if math.abs((tonumber(row.z) or 0) - z) < 1.5 and tonumber(row.x) ~= nil and tonumber(row.y) ~= nil
                and row.x >= entry.x1 - 1 and row.x <= entry.x2 + 2
                and row.y >= entry.y1 - 1 and row.y <= entry.y2 + 2 then
            return true
        end
    end
    return false
end

function Venue.candidates(anchor, groupId, now)
    Venue.metrics.scans = Venue.metrics.scans + 1
    local settings = Venue.settings
    local found, seen = {}, {}
    local ox, oy, oz = math.floor(anchor.x), math.floor(anchor.y), math.floor(anchor.z or 0)
    for distance = 2, settings.radius, settings.ringStep do
        for _, ray in ipairs(Venue.rays) do
            local length = math.sqrt(ray[1] * ray[1] + ray[2] * ray[2])
            local x = ox + math.floor(ray[1] / length * distance + 0.5)
            local y = oy + math.floor(ray[2] / length * distance + 0.5)
            local building = Venue.buildingAt(Spread.squareAt(x, y, oz))
            if building ~= nil then
                local key = Venue.buildingKey(building)
                if key ~= nil and seen[key] == nil then
                    seen[key] = true
                    local x1, y1, x2, y2 = Venue.bounds(building)
                    local held = Venue.claimed[key]
                    local banned = Venue.banned[key]
                    if x1 ~= nil and (held == nil or held == groupId)
                            and (banned == nil or now >= banned) then
                        local area = (x2 - x1 + 1) * (y2 - y1 + 1)
                        if area >= settings.minArea and area <= settings.maxArea
                                and not Venue.refused(building) then
                            found[#found + 1] = { key = key, building = building, distance = distance,
                                x1 = x1, y1 = y1, x2 = x2, y2 = y2, area = area }
                        end
                    end
                end
            end
        end
        if #found >= settings.scanCap then break end
    end
    table.sort(found, function(left, right)
        local a = left.distance + (left.area < 30 and 6 or 0)
        local b = right.distance + (right.area < 30 and 6 or 0)
        if a ~= b then return a < b end
        return left.key < right.key
    end)
    local limited = {}
    for index = 1, math.min(#found, settings.candidateLimit) do limited[index] = found[index] end
    return limited
end

function Venue.neighbourInfo(square, neighbour, building, dir, state)
    local outside = not neighbour or Venue.buildingAt(neighbour) ~= building
    local blocked = outside
    if neighbour and not outside then
        local ok, value = pcall(square.isBlockedTo, square, neighbour)
        blocked = ok and value == true
    end
    if blocked then
        state.walls = state.walls + 1
        state.bx, state.by = state.bx + dir[1], state.by + dir[2]
    end
    if outside and neighbour then
        local okWindow, window = pcall(square.getWindowTo, square, neighbour)
        local okFrame, frame = pcall(square.getWindowFrameTo, square, neighbour)
        if (okWindow and window ~= nil) or (okFrame and frame ~= nil) then
            state.win = { dx = dir[1], dy = dir[2] }
        end
        local okDoor, door = pcall(square.getDoorTo, square, neighbour)
        if okDoor and door ~= nil then state.door = true end
    end
end

function Venue.tableHere(square)
    local objects
    local ok = pcall(function() objects = square:getObjects() end)
    if not ok or objects == nil then return false end
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        local props = object ~= nil and object:getProperties() or nil
        if props ~= nil then
            if type(props.isTable) == "function" and props:isTable() == true then return true end
            if type(props.isTableTop) == "function" and props:isTableTop() == true then return true end
        end
    end
    return false
end

function Venue.stairsHere(square)
    if type(square.HasStairs) ~= "function" then return false end
    local ok, value = pcall(square.HasStairs, square)
    return ok and value == true
end

function Venue.candidateAt(square, x, y, grid, building)
    if Venue.stairsHere(square) then return nil end
    local state = { walls = 0, bx = 0, by = 0, win = nil, door = false }
    for _, dir in ipairs(Venue.dirs) do
        Venue.neighbourInfo(square, grid[Venue.keyOf(x + dir[1], y + dir[2])], building, dir, state)
    end
    return { x = x + 0.5, y = y + 0.5, tx = x, ty = y, key = Venue.keyOf(x, y),
        walls = state.walls, bx = state.bx, by = state.by, win = state.win, door = state.door,
        entrance = false }
end

function Venue.scan(entry, z)
    local building = entry.building
    local grid = {}
    for x = entry.x1 - 1, entry.x2 + 1 do
        for y = entry.y1 - 1, entry.y2 + 1 do
            grid[Venue.keyOf(x, y)] = Spread.squareAt(x, y, z) or false
        end
    end
    local list, byKey, tables, tableList = {}, {}, {}, {}
    for x = entry.x1, entry.x2 do
        for y = entry.y1, entry.y2 do
            local square = grid[Venue.keyOf(x, y)]
            if square and Venue.buildingAt(square) == building then
                local okRoom, room = pcall(square.getRoom, square)
                if okRoom and room ~= nil then
                    if Spread.standable(square) then
                        local candidate = Venue.candidateAt(square, x, y, grid, building)
                        if candidate ~= nil then
                            list[#list + 1] = candidate
                            byKey[candidate.key] = candidate
                        end
                    elseif Venue.tableHere(square) then
                        tables[Venue.keyOf(x, y)] = true
                        tableList[#tableList + 1] = { tx = x, ty = y }
                    end
                end
            end
        end
    end
    return list, byKey, tables, tableList
end

function Venue.openingsOf(entry, z)
    local entrances = ProjectALife.Entrances
    local result = {}
    if entrances == nil or type(entrances.openings) ~= "function" then return result end
    local ok, openings = pcall(entrances.openings, entry.building, (entry.x1 + entry.x2) / 2,
        (entry.y1 + entry.y2) / 2, z, nil, false)
    if not ok or type(openings) ~= "table" then return result end
    for _, opening in ipairs(openings) do
        if (tonumber(opening.cost) or 99) <= Venue.settings.openingCost then result[#result + 1] = opening end
    end
    table.sort(result, function(left, right)
        local a, b = tonumber(left.cost) or 99, tonumber(right.cost) or 99
        if a ~= b then return a < b end
        return tostring(left.key) < tostring(right.key)
    end)
    return result
end

function Venue.analyze(entry, z, now)
    local cacheKey = entry.key .. ":" .. z
    local cached = Venue.cache[cacheKey]
    if cached ~= nil and now - cached.atMs < Venue.settings.ttlMs then
        Venue.metrics.cacheHits = Venue.metrics.cacheHits + 1
        return cached
    end
    Venue.metrics.analyses = Venue.metrics.analyses + 1
    local ok, list, byKey, tables, tableList = pcall(Venue.scan, entry, z)
    if not ok then return nil end
    local openings = Venue.openingsOf(entry, z)
    local zones = {}
    for index = 1, math.min(3, #openings) do
        zones[#zones + 1] = { x = tonumber(openings[index].ix) or openings[index].x,
            y = tonumber(openings[index].iy) or openings[index].y }
    end
    local clear2 = Venue.settings.entranceClear * Venue.settings.entranceClear
    for _, candidate in ipairs(list) do
        for _, zone in ipairs(zones) do
            if (candidate.x - zone.x) ^ 2 + (candidate.y - zone.y) ^ 2 <= clear2 then candidate.entrance = true end
        end
        for _, dir in ipairs(Venue.dirs) do
            if tables[Venue.keyOf(candidate.tx + dir[1], candidate.ty + dir[2])] then
                candidate.tableAdj = { x = candidate.tx + dir[1], y = candidate.ty + dir[2] }
                break
            end
        end
    end
    local analysis = {
        key = entry.key, building = entry.building, z = z, atMs = now,
        x1 = entry.x1, y1 = entry.y1, x2 = entry.x2, y2 = entry.y2,
        centre = { x = (entry.x1 + entry.x2 + 1) / 2, y = (entry.y1 + entry.y2 + 1) / 2 },
        list = list, byKey = byKey, tables = tables, tableList = tableList,
        openings = openings, free = #list,
    }
    local best = openings[1]
    if best ~= nil then
        analysis.entry = { x = best.x, y = best.y, z = best.z or z, ix = tonumber(best.ix), iy = tonumber(best.iy) }
    end
    if Venue.cacheCount >= Venue.settings.cacheLimit then
        Venue.cache, Venue.cacheCount = {}, 0
    end
    if Venue.cache[cacheKey] == nil then Venue.cacheCount = Venue.cacheCount + 1 end
    Venue.cache[cacheKey] = analysis
    return analysis
end

function Venue.usable(analysis, members)
    if analysis == nil or analysis.entry == nil then return false end
    local count = 0
    for _, candidate in ipairs(analysis.list) do
        if not candidate.entrance then count = count + 1 end
    end
    return count >= members + 1
end

function Venue.coverScore(square, x, y, z)
    local state = { walls = 0, bx = 0, by = 0 }
    for _, dir in ipairs(Venue.dirs) do
        local neighbour = Spread.squareAt(x + dir[1], y + dir[2], z)
        local blocked = neighbour == nil or not Spread.standable(neighbour)
        if not blocked then
            local ok, value = pcall(square.isBlockedTo, square, neighbour)
            blocked = ok and value == true
        end
        if blocked then
            state.walls = state.walls + 1
            state.bx, state.by = state.bx + dir[1], state.by + dir[2]
        end
    end
    return state
end

function Venue.cover(anchor, groupId)
    Venue.metrics.covers = Venue.metrics.covers + 1
    local road = ProjectALife.Road
    local oz = math.floor(anchor.z or 0)
    local list, byKey, seen = {}, {}, {}
    local rays = Venue.settings.coverRays
    local phase = Spread.unit(tostring(groupId) .. ":cover") * 0.3
    for _, reach in ipairs(Venue.settings.coverReach) do
        for index = 1, rays do
            local angle = (index - 1) * (math.pi * 2 / rays) + phase
            local x = math.floor(anchor.x + math.cos(angle) * reach)
            local y = math.floor(anchor.y + math.sin(angle) * reach)
            local key = Venue.keyOf(x, y)
            if seen[key] == nil then
                seen[key] = true
                local square = Spread.squareAt(x, y, oz)
                if Spread.standable(square) and Venue.outside(square) and Venue.buildingAt(square) == nil then
                    local paved = false
                    if road ~= nil and type(road.isRoadSquare) == "function" then
                        local ok, value = pcall(road.isRoadSquare, square)
                        paved = ok and value == true
                    end
                    if not paved and not Venue.inBase(x, y) then
                        local state = Venue.coverScore(square, x, y, oz)
                        local candidate = { x = x + 0.5, y = y + 0.5, tx = x, ty = y, key = key,
                            walls = state.walls, bx = state.bx, by = state.by, entrance = false, cover = true }
                        list[#list + 1] = candidate
                        byKey[key] = candidate
                    end
                end
            end
        end
    end
    local centre, top
    for _, candidate in ipairs(list) do
        local value = candidate.walls * 3 - math.sqrt((candidate.x - anchor.x) ^ 2 + (candidate.y - anchor.y) ^ 2) * 0.4
        if top == nil or value > top then centre, top = candidate, value end
    end
    if centre == nil then return nil end
    return { kind = "cover", z = oz, list = list, byKey = byKey, tableList = {}, tables = {},
        centre = { x = centre.x, y = centre.y }, cluster = true }
end

function Venue.ring(anchor, count, groupId)
    Venue.metrics.rings = Venue.metrics.rings + 1
    local oz = math.floor(anchor.z or 0)
    local radius = math.max(2.6, count * 0.9)
    local list, byKey = {}, {}
    local total = count + 3
    local phase = Spread.unit(tostring(groupId) .. ":ring") * math.pi * 2
    for index = 1, total do
        local angle = phase + (index - 1) * (math.pi * 2 / total)
        local x = anchor.x + math.cos(angle) * radius
        local y = anchor.y + math.sin(angle) * radius
        local cx, cy = Spread.clamp(x, y, oz, anchor.x, anchor.y)
        local tx, ty = math.floor(cx), math.floor(cy)
        local key = Venue.keyOf(tx, ty)
        if byKey[key] == nil then
            local candidate = { x = cx, y = cy, tx = tx, ty = ty, key = key, walls = 0, bx = 0, by = 0,
                entrance = false, cover = true }
            list[#list + 1] = candidate
            byKey[key] = candidate
        end
    end
    return { kind = "open", z = oz, list = list, byKey = byKey, tableList = {}, tables = {},
        centre = { x = anchor.x, y = anchor.y }, cluster = true }
end

function Venue.distance(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

function Venue.toward(from, dx, dy, reach)
    return { x = from.x + dx * reach, y = from.y + dy * reach }
end

function Venue.unitVector(from, to)
    local dx, dy = to.x - from.x, to.y - from.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.001 then return 0, 0 end
    return dx / length, dy / length
end

function Venue.attempt(venue, roles, seed, gap)
    local candidates, centre, entry = venue.list, venue.centre, venue.entry
    local taken, assigned = {}, {}
    local gap2 = gap * gap
    local function apart(candidate)
        for index = 1, #taken do
            local other = taken[index]
            if (other.x - candidate.x) ^ 2 + (other.y - candidate.y) ^ 2 < gap2 then return false end
        end
        return true
    end
    local function take(index, candidate)
        if candidate == nil then return false end
        assigned[index] = candidate
        taken[#taken + 1] = candidate
        return true
    end
    local function best(role, score, allowEntrance)
        local winner, top
        for _, candidate in ipairs(candidates) do
            if (allowEntrance or not candidate.entrance) and apart(candidate) then
                local value = score(candidate)
                if value ~= nil then
                    if venue.cluster and centre ~= nil then value = value - Venue.distance(candidate, centre) * 0.4 end
                    value = value + Spread.unit(seed .. ":" .. role .. ":" .. candidate.key) * 0.01
                    if top == nil or value > top then winner, top = candidate, value end
                end
            end
        end
        return winner
    end
    local byRole = {}
    for index, role in ipairs(roles) do
        byRole[role] = byRole[role] or {}
        byRole[role][#byRole[role] + 1] = index
    end
    local function away(candidate)
        if entry == nil then return 0 end
        return Venue.distance(candidate, entry) * 0.2
    end
    for _, index in ipairs(byRole.lookout or {}) do
        local ok = take(index, best("lookout", function(c)
            local value = c.walls * 1.5 - away(c) * 0.75
            if c.win then value = value + 30 end
            if c.door then value = value + 12 end
            return value
        end))
        if not ok then return nil end
    end
    for _, index in ipairs(byRole.sitter or {}) do
        local ok = take(index, best("sitter", function(c)
            return c.walls * 5 + (c.walls >= 2 and 10 or 0) + away(c)
        end))
        if not ok then return nil end
    end
    local talkers = byRole.talker or {}
    local pairIdx
    if #talkers >= 2 then
        pairIdx = { talkers[1], talkers[2] }
    elseif #roles == 2 then
        pairIdx = { 1, 2 }
    end
    if pairIdx ~= nil then
        local a, b = Venue.pair(venue, apart, seed)
        if a ~= nil then
            take(pairIdx[1], a)
            take(pairIdx[2], b)
        end
    end
    for _, index in ipairs(talkers) do
        if assigned[index] == nil then
            local ok = take(index, best("talker", function(c) return -c.walls * 0.5 end))
            if not ok then return nil end
        end
    end
    local mid = centre
    if pairIdx ~= nil and assigned[pairIdx[1]] ~= nil and assigned[pairIdx[2]] ~= nil then
        local a, b = assigned[pairIdx[1]], assigned[pairIdx[2]]
        mid = { x = (a.x + b.x) / 2, y = (a.y + b.y) / 2 }
    end
    for _, index in ipairs(byRole.commenter or {}) do
        local ok = take(index, best("commenter", function(c)
            if mid == nil then return c.walls * 0.3 end
            return -math.abs(Venue.distance(c, mid) - 2.8) + c.walls * 0.3
        end))
        if not ok then return nil end
    end
    for _, index in ipairs(byRole.quiet or {}) do
        local ok = take(index, best("quiet", function(c)
            local nearest = math.huge
            for _, other in ipairs(taken) do
                local d = Venue.distance(c, other)
                if d < nearest then nearest = d end
            end
            if nearest == math.huge then nearest = 0 end
            return nearest + c.walls * 0.8
        end))
        if not ok then return nil end
    end
    for index, role in ipairs(roles) do
        if assigned[index] == nil then
            local ok = take(index, best(role, function(c)
                local value = c.walls * 1.0
                if role == "smoker" and c.win then value = value + 4 end
                return value
            end))
            if not ok then return nil end
        end
    end
    return Venue.finish(venue, roles, assigned, pairIdx)
end

function Venue.pair(venue, apart, seed)
    local byKey = venue.byKey
    local bestA, bestB, top
    for _, spot in ipairs(venue.tableList or {}) do
        for _, axis in ipairs({ { 1, 0 }, { 0, 1 } }) do
            local a = byKey[Venue.keyOf(spot.tx + axis[1], spot.ty + axis[2])]
            local b = byKey[Venue.keyOf(spot.tx - axis[1], spot.ty - axis[2])]
            if a ~= nil and b ~= nil and not a.entrance and not b.entrance and apart(a) and apart(b) then
                local value = 60 + Spread.unit(seed .. ":pair:" .. spot.tx .. ":" .. spot.ty .. ":" .. axis[1])
                if venue.centre ~= nil then value = value - Venue.distance(a, venue.centre) * 0.5 end
                if top == nil or value > top then bestA, bestB, top = a, b, value end
            end
        end
    end
    if bestA ~= nil then return bestA, bestB end
    local pool = {}
    for _, candidate in ipairs(venue.list) do
        if not candidate.entrance then pool[#pool + 1] = candidate end
    end
    local centre = venue.centre
    table.sort(pool, function(left, right)
        local a = centre ~= nil and Venue.distance(left, centre) or 0
        local b = centre ~= nil and Venue.distance(right, centre) or 0
        if a ~= b then return a < b end
        return left.key < right.key
    end)
    for i = 1, math.min(#pool, 24) do
        for j = i + 1, math.min(#pool, 24) do
            local a, b = pool[i], pool[j]
            local d = Venue.distance(a, b)
            if d >= 1.8 and d <= 3.2 and apart(a) and apart(b) then
                local value = -(i + j) + a.walls * 0.2 + b.walls * 0.2
                if top == nil or value > top then bestA, bestB, top = a, b, value end
            end
        end
    end
    return bestA, bestB
end

function Venue.finish(venue, roles, assigned, pairIdx)
    local slots = {}
    for index, role in ipairs(roles) do
        local c = assigned[index]
        slots[index] = { x = c.x, y = c.y, tx = c.tx, ty = c.ty, role = role, cand = c }
    end
    local centre, entry = venue.centre, venue.entry
    local partner = {}
    local mid
    if pairIdx ~= nil then
        partner[pairIdx[1]], partner[pairIdx[2]] = pairIdx[2], pairIdx[1]
        mid = { x = (slots[pairIdx[1]].x + slots[pairIdx[2]].x) / 2, y = (slots[pairIdx[1]].y + slots[pairIdx[2]].y) / 2 }
    end
    for index, slot in ipairs(slots) do
        local c, role = slot.cand, slot.role
        local face
        if partner[index] ~= nil then
            face = { x = slots[partner[index]].x, y = slots[partner[index]].y }
            slot.facingIndex = partner[index]
        elseif role == "lookout" then
            if c.win then
                face = Venue.toward(c, c.win.dx, c.win.dy, 4)
            elseif entry ~= nil then
                face = { x = entry.x, y = entry.y }
            elseif centre ~= nil then
                local dx, dy = Venue.unitVector(centre, c)
                face = Venue.toward(c, dx, dy, 4)
            end
        elseif role == "sitter" and (c.bx ~= 0 or c.by ~= 0) then
            face = Venue.toward(c, -c.bx, -c.by, 3)
        elseif role == "quiet" and (c.bx ~= 0 or c.by ~= 0) then
            face = Venue.toward(c, c.bx, c.by, 2)
        elseif role == "commenter" and mid ~= nil then
            face = mid
        end
        if face == nil and centre ~= nil then face = { x = centre.x, y = centre.y } end
        slot.facing = face
        slot.cand = nil
    end
    return slots
end

function Venue.solve(venue, roles, seed)
    local spacing = Venue.settings.spacing
    local gaps = { spacing }
    if venue.kind ~= "building" then gaps = { Venue.settings.openSpacing, spacing } end
    for _, gap in ipairs(gaps) do
        local slots = Venue.attempt(venue, roles, tostring(seed or ""), gap)
        if slots ~= nil then
            Venue.metrics.solved = Venue.metrics.solved + 1
            return slots, gap
        end
    end
    Venue.metrics.unsolved = Venue.metrics.unsolved + 1
    return nil
end

function Venue.buildingVenue(analysis)
    return { kind = "building", key = analysis.key, z = analysis.z, list = analysis.list, byKey = analysis.byKey,
        tableList = analysis.tableList, tables = analysis.tables, centre = analysis.centre,
        entry = analysis.entry, exit = analysis.entry, cluster = false }
end

function Venue.musterSlots(exit, count, seed, z)
    local result = {}
    if type(exit) ~= "table" then return result end
    local ox, oy = tonumber(exit.x), tonumber(exit.y)
    if ox == nil or oy == nil then return result end
    local phase = Spread.unit(tostring(seed) .. ":muster") * math.pi * 2
    for _, radius in ipairs(Venue.settings.musterRadii) do
        for index = 1, Venue.settings.musterRays do
            if #result >= count then return result end
            local angle = phase + (index - 1) * (math.pi * 2 / Venue.settings.musterRays)
            local x, y = ox + math.cos(angle) * radius, oy + math.sin(angle) * radius
            local square = Spread.squareAt(x, y, z)
            if Spread.standable(square) and Venue.buildingAt(square) == nil then
                local clear = true
                for _, other in ipairs(result) do
                    if (other.x - x) ^ 2 + (other.y - y) ^ 2 < 3.24 then clear = false end
                end
                if clear then result[#result + 1] = { x = x, y = y, z = z } end
            end
        end
    end
    return result
end

function Venue.reset()
    Venue.cache, Venue.cacheCount, Venue.claimed, Venue.banned = {}, 0, {}, {}
end

return Venue
