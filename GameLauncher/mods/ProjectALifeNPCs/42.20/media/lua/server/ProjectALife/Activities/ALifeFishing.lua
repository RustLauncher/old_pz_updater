require "ProjectALife/Activities/ALifeActivityCatalog"

ProjectALife = ProjectALife or {}
local Catalog = ProjectALife.ActivityCatalog
local Fish = {}
ProjectALife.ActivityFishing = Fish

function Fish.enabled()
    return Catalog.enabled() and Catalog.sandbox("Activities_Fishing") ~= false
end

function Fish.coefficient(name, x, y)
    local utils = type(Fishing) == "table" and Fishing.Utils or nil
    if type(utils) ~= "table" or type(utils[name]) ~= "function" then return 1 end
    local ok, params = pcall(utils[name], x, y)
    local value = ok and type(params) == "table" and tonumber(params.coeff) or nil
    if value == nil or value ~= value or value < 0 or value > 2 then return 1 end
    return value
end

function Fish.yieldScale()
    local percent = tonumber(Catalog.sandbox("Activities_FishYieldPercent")) or 100
    return math.max(0, math.min(300, percent)) / 100
end

function Fish.nearWater(habitat)
    local tiles = type(habitat) == "table" and tonumber(habitat.water) or nil
    return tiles ~= nil and tiles >= 0 and tiles <= 150
end

function Fish.offlineYield(members, elapsed, weather, hour, percent)
    local count = math.max(0, math.min(3, math.floor(tonumber(members) or 0)))
    local hours = math.max(0, math.min(2, tonumber(elapsed) or 0))
    local scale = math.max(0, math.min(300, tonumber(percent) or 100)) / 100
    return math.min(3 * count, 0.5 * count * hours
        * math.max(0, math.min(2, tonumber(weather) or 1))
        * math.max(0, math.min(2, tonumber(hour) or 1))) * scale
end

function Fish.offline(q, task)
    if not Fish.enabled() or task.activityRendered == true or task.activityYielded == true or task.kind ~= "fish" then return 0 end
    local graph = ProjectALife.RoadGraph
    local node = graph ~= nil and type(graph.nodes) == "table" and graph.nodes[q.nodeId] or nil
    if node == nil or q.nodeId ~= task.dest or not Fish.nearWater(node.habitat) then return 0 end
    local completed, assigned = tonumber(task.completedHours), tonumber(task.assignedHours)
    local untilHours = tonumber(task.untilHours)
    if completed == nil or assigned == nil or untilHours == nil or completed < untilHours then return 0 end
    local members = 0
    for _, member in ipairs(q.members or {}) do
        if (tonumber(member.health) or 100) > 0 then members = members + 1 end
    end
    local count = Fish.offlineYield(members, untilHours - assigned,
        Fish.coefficient("getWeatherParams"), Fish.coefficient("getTimeParams"), Fish.yieldScale() * 100)
    task.activityYielded = true
    return count
end

function Fish.ringOffset(index)
    if index == 0 then return 0, 0 end
    local radius = math.ceil((math.sqrt(index + 1) - 1) / 2)
    local offset = index - (2 * radius - 1) ^ 2
    local side, step = math.floor(offset / (2 * radius)), offset % (2 * radius)
    if side == 0 then return -radius + step, -radius end
    if side == 1 then return radius, -radius + step end
    if side == 2 then return radius - step, radius end
    return -radius, radius - step
end

Fish.waterSprites = { "blends_natural_02_0", "blends_natural_02_5", "blends_natural_02_6", "blends_natural_02_7" }
Fish.siteRadii = { 6, 12, 20, 32 }
Fish.siteReads = 3200

function Fish.floorSprite(square)
    if square == nil or type(square.getFloor) ~= "function" then return nil end
    local ok, floor = pcall(square.getFloor, square)
    if not ok or floor == nil or type(floor.getSprite) ~= "function" then return nil end
    local spriteOk, sprite = pcall(floor.getSprite, floor)
    if not spriteOk or sprite == nil or type(sprite.getName) ~= "function" then return nil end
    local nameOk, name = pcall(sprite.getName, sprite)
    if nameOk and type(name) == "string" then return name end
    return nil
end

function Fish.waterName(name)
    if type(name) ~= "string" then return false end
    for _, prefix in ipairs(Fish.waterSprites) do
        if string.sub(name, 1, #prefix) == prefix then return true end
    end
    return false
end

function Fish.spriteWater(square)
    if type(square.getFloor) ~= "function" then return nil end
    local ok, floor = pcall(square.getFloor, square)
    if not ok or floor == nil or type(floor.getSprite) ~= "function" then return nil end
    local spriteOk, sprite = pcall(floor.getSprite, floor)
    if not spriteOk or sprite == nil or type(sprite.getProperties) ~= "function" then return nil end
    local propertiesOk, properties = pcall(sprite.getProperties, sprite)
    if not propertiesOk or properties == nil or type(properties.has) ~= "function" then return nil end
    return properties:has(IsoFlagType.water) == true
end

function Fish.waterSquare(square)
    if square == nil then return nil end
    local known = false
    if type(square.getProperties) == "function" and IsoFlagType ~= nil and IsoFlagType.water ~= nil then
        local ok, properties = pcall(square.getProperties, square)
        if ok and properties ~= nil and type(properties.has) == "function" then
            known = true
            if properties:has(IsoFlagType.water) == true then return true end
            if IsoFlagType.taintedWater ~= nil and properties:has(IsoFlagType.taintedWater) == true then return true end
        end
    end
    if IsoFlagType ~= nil and IsoFlagType.water ~= nil then
        local flagged = Fish.spriteWater(square)
        if flagged ~= nil then
            known = true
            if flagged then return true end
        end
    end
    if type(square.getFloor) == "function" and IsoFlagType ~= nil and IsoFlagType.water ~= nil then
        local ok, floor = pcall(square.getFloor, square)
        if ok and floor ~= nil and type(floor.hasProperty) == "function" then
            known = true
            if floor:hasProperty(IsoFlagType.water) == true then return true end
        end
    end
    local name = Fish.floorSprite(square)
    if name ~= nil then
        known = true
        if Fish.waterName(name) then return true end
    end
    if known then return false end
    return nil
end

function Fish.shoreLand(square)
    return Fish.waterSquare(square) == false and type(square.isFree) == "function"
        and type(square.TreatAsSolidFloor) == "function" and square:isFree(false) == true
        and square:TreatAsSolidFloor() == true
end

function Fish.spaced(posts, x, y, apart)
    local limit = (tonumber(apart) or 4) ^ 2
    for _, point in ipairs(posts) do
        if (point.x - x) ^ 2 + (point.y - y) ^ 2 < limit then return false end
    end
    return true
end

Fish.shoreSides = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }

function Fish.shoreSites(cell, x, y, options)
    options = type(options) == "table" and options or {}
    x, y = tonumber(x), tonumber(y)
    if cell == nil or type(cell.getGridSquare) ~= "function" or x == nil or y == nil or x ~= x or y ~= y
            or math.abs(x) == math.huge or math.abs(y) == math.huge then return {}, 0 end
    local want = math.max(1, math.min(8, math.floor(tonumber(options.count) or 3)))
    local apart = tonumber(options.apart) or 2.5
    local z = math.floor(tonumber(options.z) or 0)
    local fx, fy = tonumber(options.fx), tonumber(options.fy)
    local length = fx ~= nil and fy ~= nil and math.sqrt(fx * fx + fy * fy) or 0
    if length > 0.01 then fx, fy = fx / length, fy / length else fx, fy = nil, nil end
    local budget = math.floor(tonumber(options.reads) or Fish.siteReads)
    local cx, cy = math.floor(x), math.floor(y)
    local found, reads, covered = {}, 0, -1
    for _, radius in ipairs(options.radii or Fish.siteRadii) do
        local first, last = (2 * (covered + 1) - 1) ^ 2, (2 * radius + 1) ^ 2 - 1
        if covered < 0 then first = 0 end
        for index = first, last do
            if reads >= budget then break end
            local dx, dy = Fish.ringOffset(index)
            local wx, wy = cx + dx, cy + dy
            local water = cell:getGridSquare(wx, wy, z)
            reads = reads + 1
            if Fish.waterSquare(water) == true then
                for _, side in ipairs(Fish.shoreSides) do
                    local sx, sy = wx + side[1], wy + side[2]
                    local land = cell:getGridSquare(sx, sy, z)
                    reads = reads + 1
                    if Fish.shoreLand(land) then
                        local px, py = sx + 0.5, sy + 0.5
                        local flat = (px - x) ^ 2 + (py - y) ^ 2
                        local score = flat
                        if fx ~= nil then
                            local ahead = ((px - x) * fx + (py - y) * fy) / math.max(1, math.sqrt(flat))
                            score = flat * (1.2 - 0.4 * ahead)
                        end
                        if side[1] ~= 0 and side[2] ~= 0 then score = score + 2 end
                        found[#found + 1] = { x = px, y = py, z = z, waterX = wx + 0.5, waterY = wy + 0.5, score = score }
                    end
                end
            end
        end
        covered = radius
        if #found >= want * 4 or reads >= budget then break end
    end
    table.sort(found, function(left, right)
        if left.score ~= right.score then return left.score < right.score end
        if left.x ~= right.x then return left.x < right.x end
        return left.y < right.y
    end)
    local posts = {}
    for _, candidate in ipairs(found) do
        if #posts >= want then break end
        if Fish.spaced(posts, candidate.x, candidate.y, apart) then posts[#posts + 1] = candidate end
    end
    return posts, reads
end

function Fish.scanShore(search, point, hours)
    if type(point) ~= "table" then return {}, true, search end
    local x, y = tonumber(point.x), tonumber(point.y)
    hours = tonumber(hours)
    if x == nil or y == nil or x ~= x or y ~= y or math.abs(x) == math.huge or math.abs(y) == math.huge
            or hours == nil or hours ~= hours or math.abs(hours) == math.huge
            or (tonumber(point.z) or 0) ~= 0 then return {}, true, search end
    local bx, by = math.floor(x / 10), math.floor(y / 10)
    if type(search) ~= "table" or search.bx ~= bx or search.by ~= by
            or hours < search.createdHours or hours >= search.createdHours + 0.5 then
        search = { bx = bx, by = by, createdHours = hours, x = math.floor(x), y = math.floor(y), cursor = 0, posts = {} }
    end
    if search.done ~= true then
        if type(getCell) ~= "function" then return {}, false, search end
        local cell = getCell()
        if cell == nil or type(cell.getGridSquare) ~= "function" then return {}, false, search end
        local reads = 0
        while search.cursor < 6561 and reads <= 395 and #search.posts < 3 do
            local dx, dy = Fish.ringOffset(search.cursor)
            search.cursor = search.cursor + 1
            if dx * dx + dy * dy <= 1600 then
                local wx, wy = search.x + dx, search.y + dy
                local water = cell:getGridSquare(wx, wy, 0)
                reads = reads + 1
                if Fish.waterSquare(water) == true then
                    for side = 1, 4 do
                        local sx, sy = wx, wy
                        if side == 1 then sx = wx - 1 elseif side == 2 then sx = wx + 1
                        elseif side == 3 then sy = wy - 1 else sy = wy + 1 end
                        local land = cell:getGridSquare(sx, sy, 0)
                        reads = reads + 1
                        local px, py = sx + 0.5, sy + 0.5
                        if #search.posts < 3 and (px - x) ^ 2 + (py - y) ^ 2 <= 1600
                                and Fish.spaced(search.posts, px, py) and Fish.shoreLand(land) then
                            search.posts[#search.posts + 1] = { x = px, y = py, z = 0, waterX = wx + 0.5, waterY = wy + 0.5 }
                        end
                    end
                end
            end
        end
        search.done = search.cursor >= 6561 or #search.posts >= 3
    end
    local posts = {}
    for _, post in ipairs(search.posts) do
        if (post.x - x) ^ 2 + (post.y - y) ^ 2 <= 1600 then posts[#posts + 1] = post end
    end
    return posts, search.done == true, search
end

Fish.species = {
    { "Base.LargemouthBass", 20 }, { "Base.YellowPerch", 20 },
    { "Base.SmallmouthBass", 15 }, { "Base.ChannelCatfish", 15 },
    { "Base.BlackCrappie", 10 }, { "Base.WhiteCrappie", 10 },
    { "Base.BlueCatfish", 5 }, { "Base.StripedBass", 5 },
}

function Fish.randomUnit()
    if type(ZombRand) ~= "function" then return nil end
    return ZombRand(1000000) / 1000000
end

function Fish.speciesFor(roll)
    local remaining = math.max(0, math.min(0.999999, tonumber(roll) or 0)) * 100
    for _, row in ipairs(Fish.species) do
        if remaining < row[2] then return row[1] end
        remaining = remaining - row[2]
    end
    return Fish.species[#Fish.species][1]
end

function Fish.atPost(record, post)
    local point = type(record) == "table" and record.worldPosition or nil
    if type(point) ~= "table" or type(post) ~= "table" or record.lifecycle ~= "active" then return false end
    local x, y, z = tonumber(point.x), tonumber(point.y), tonumber(point.z) or 0
    return x ~= nil and y ~= nil and x == x and y == y and z == (tonumber(post.z) or 0)
        and (x - post.x) ^ 2 + (y - post.y) ^ 2 <= 0.64
end

function Fish.publish(square, fullType)
    if type(isClient) == "function" and isClient() == true then return false end
    if square == nil or type(square.AddWorldInventoryItem) ~= "function"
            or type(instanceItem) ~= "function" then return false end
    local ok, item = pcall(instanceItem, fullType)
    if not ok or item == nil or type(item.getWorldItem) ~= "function" then return false end
    local existing = item:getWorldItem()
    if existing ~= nil then return false end
    pcall(square.AddWorldInventoryItem, square, item, 0.5, 0.5, 0, false)
    local world = item:getWorldItem()
    if world == nil or type(world.getSquare) ~= "function" or world:getSquare() ~= square then return false end
    if type(world.transmitCompleteItemToClients) == "function" then
        pcall(world.transmitCompleteItemToClients, world)
    end
    return true
end

function Fish.catchTick(work, record, hours, reserve)
    if type(isClient) == "function" and isClient() == true then return 0 end
    if not Fish.enabled() or type(work) ~= "table" or work.watch == true then return 0 end
    hours = tonumber(hours)
    if hours == nil or hours ~= hours or math.abs(hours) == math.huge then return 0 end
    if (tonumber(work.catches) or 0) >= 3 then return 0 end
    if not Fish.atPost(record, work.post) or record.activity == "combat" or record.activity == "attacking"
            or record.activity == "warning" or record.activity == "fleeing" then
        work.nextHours = nil
        return 0
    end
    if type(getCell) ~= "function" then return 0 end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return 0 end
    local post = work.post
    local square = cell:getGridSquare(math.floor(post.x), math.floor(post.y), post.z or 0)
    local water = cell:getGridSquare(math.floor(post.waterX), math.floor(post.waterY), post.z or 0)
    if Fish.waterSquare(square) ~= false or Fish.waterSquare(water) ~= true then
        work.nextHours = nil
        return 0
    end
    local nextHours = tonumber(work.nextHours)
    if nextHours == nil or hours < nextHours - 1 / 15 then
        work.nextHours = hours + 1 / 15
        return 0
    end
    if hours < nextHours then return 0 end
    work.nextHours = hours + 1 / 15
    local roll = Fish.randomUnit()
    if roll == nil or roll >= 0.18 * Fish.coefficient("getWeatherParams")
            * Fish.coefficient("getTimeParams") * Fish.coefficient("getFishNumParams", post.waterX, post.waterY) then return 0 end
    local scale = Fish.yieldScale()
    local count = math.floor(scale)
    local fraction = Fish.randomUnit()
    if fraction ~= nil and fraction < scale - count then count = count + 1 end
    count = math.min(count, 3 - (tonumber(work.catches) or 0))
    local previous = tonumber(work.catches) or 0
    if count > 0 and type(reserve) == "function" then
        work.catches = previous + count
        if reserve() ~= true then
            work.catches = previous
            return 0
        end
    end
    local caught = 0
    for _ = 1, count do
        local species = Fish.randomUnit()
        if species ~= nil and Fish.publish(square, Fish.speciesFor(species)) then
            caught = caught + 1
        end
    end
    if count > 0 then work.catches = previous + caught end
    return caught
end

function Fish.minutes()
    local value = tonumber(Catalog.sandbox("Activities_FishingMinutes")) or 65
    return math.max(10, math.min(240, value))
end

function Fish.sessionHours(roll)
    local spread = 0.6 + math.max(0, math.min(1, tonumber(roll) or 0.5)) * 0.8
    return Fish.minutes() * spread / 60
end

function Fish.deadline(hours, roll)
    if roll == nil and type(ZombRand) == "function" then roll = ZombRand(1000) / 1000 end
    local untilHours = hours + Fish.sessionHours(roll)
    if type(getClimateManager) ~= "function" or type(getGameTime) ~= "function" then return untilHours end
    local climate, time = getClimateManager(), getGameTime()
    if climate == nil or type(climate.getSeason) ~= "function" or time == nil
            or type(time.getTimeOfDay) ~= "function" then return untilHours end
    local season = climate:getSeason()
    if season == nil or type(season.getDusk) ~= "function" then return untilHours end
    local dusk, hour = tonumber(season:getDusk()), tonumber(time:getTimeOfDay())
    if dusk == nil or hour == nil or dusk ~= dusk or hour ~= hour then return untilHours end
    return math.min(untilHours, hours + math.max(0, dusk + 1 - hour))
end

function Fish.watchPost(posts, used)
    if type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return nil end
    for _, post in ipairs(posts) do
        local dx, dy = post.x - post.waterX, post.y - post.waterY
        for distance = 6, 8, 2 do
            for side = -1, 1 do
                local x = post.x + dx * distance - dy * side * 2
                local y = post.y + dy * distance + dx * side * 2
                local key = tostring(x) .. ":" .. tostring(y)
                local square = cell:getGridSquare(math.floor(x), math.floor(y), 0)
                if not used[key] and Fish.shoreLand(square) then
                    used[key] = true
                    return { x = x, y = y, z = 0, waterX = x + dx, waterY = y + dy }
                end
            end
        end
    end
    return nil
end

function Fish.start(members, posts, hours)
    if #posts == 0 then return nil end
    local session = { untilHours = Fish.deadline(hours), work = {} }
    if session.untilHours <= hours then return nil end
    local fishers, used = math.min(3, #posts, #members), {}
    for index = 1, fishers do
        local post = posts[index]
        used[tostring(post.x) .. ":" .. tostring(post.y)] = true
    end
    for index, record in ipairs(members) do
        local post = posts[index]
        local watch = index > fishers
        if watch then post = Fish.watchPost(posts, used) end
        if post == nil then return nil end
        session.work[tostring(record.uid)] = { post = post, watch = watch, catches = 0 }
    end
    return session
end

function Fish.finished(session, members, hours)
    if type(session) ~= "table" or type(session.work) ~= "table" then return true end
    return hours >= (tonumber(session.untilHours) or 0)
end

return Fish
