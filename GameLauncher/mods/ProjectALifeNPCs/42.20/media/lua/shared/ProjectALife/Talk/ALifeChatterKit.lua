ProjectALife = ProjectALife or {}

require "ProjectALife/Compat/ALifeFeatureGate"
require "ProjectALife/Talk/ALifeSpeech"
require "ProjectALife/Audio/ALifeGossip"

local Gate = ProjectALife.FeatureGate

local Kit = {
    spacing = 2.0,
    span = 2.6,
    maxRing = 5,
    sceneScan = 50,
    sceneSamples = 4,
    strides = { 1009, 1013, 1019, 1021 },
    partitions = setmetatable({}, { __mode = "k" }),
    planPercent = 60,
    panicPercent = 55,
    shelterPercent = 75,
    stayRoles = { sitter = true, eater = true, smoker = true, lookout = true },
    greetRules = {
        friendly = { chance = 85, minutes = 6, gesture = "wave", gestureChance = 60 },
        neutral = { chance = 65, minutes = 10, gesture = "yes", gestureChance = 35 },
        careful = { chance = 15, minutes = 20 },
    },
}
ProjectALife.ChatterKit = Kit

function Kit.enabled()
    return Gate.flag("Chatter_Enabled", true)
end

function Kit.frequency()
    return Gate.number("Chatter_Frequency", 100, 10, 400)
end

function Kit.passingPercent()
    return Gate.number("Chatter_PassingGreetPercent", 70, 0, 100)
end

function Kit.maxConcurrent()
    return math.floor(Gate.number("Chatter_MaxConcurrent", 3, 1, 8))
end

function Kit.roll(count)
    if type(ZombRand) == "function" then return ZombRand(count) end
    return 0
end

function Kit.hash(text)
    local value = 0
    text = tostring(text or "")
    for index = 1, #text do value = (value * 33 + string.byte(text, index)) % 2147483647 end
    return value
end

function Kit.turnMs(text)
    local seconds = 1.2 + #tostring(text or "") * 0.055
    if seconds < 2.2 then seconds = 2.2 end
    if seconds > 9 then seconds = 9 end
    return math.floor(seconds * 1000)
end

function Kit.readXYZ(object)
    return object:getX(), object:getY(), object:getZ()
end

function Kit.position(object)
    if object == nil or type(object.getX) ~= "function" or type(object.getY) ~= "function"
            or type(object.getZ) ~= "function" then return nil end
    local ok, x, y, z = pcall(Kit.readXYZ, object)
    if not ok or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return x, y, tonumber(z) or 0
end

function Kit.arc(cx, cy, count, ux, uy, seed, spacing)
    spacing = spacing or Kit.spacing
    local points = {}
    if count < 2 then
        points[1] = { x = cx, y = cy }
        return points, cx, cy
    end
    if count == 2 then
        local ax, ay = -uy, ux
        local half = spacing / 2
        points[1] = { x = cx - ax * half, y = cy - ay * half }
        points[2] = { x = cx + ax * half, y = cy + ay * half }
        return points, cx, cy
    end
    local step = Kit.span / (count - 1)
    local radius = spacing / (2 * math.sin(step / 2))
    if radius > 3.6 then radius = 3.6 end
    if radius < 1.2 then radius = 1.2 end
    local sx, sy = 0, 0
    for index = 1, count do
        local angle = -Kit.span / 2 + (index - 1) * step
        local cosine, sine = math.cos(angle), math.sin(angle)
        local dx = -ux * cosine + uy * sine
        local dy = -uy * cosine - ux * sine
        local jitter = ((Kit.hash(tostring(seed) .. ":" .. index) % 100) / 100 - 0.5) * 0.5
        points[index] = { x = cx + dx * (radius + jitter), y = cy + dy * (radius + jitter) }
        sx, sy = sx + points[index].x, sy + points[index].y
    end
    local shiftX, shiftY = cx - sx / count, cy - sy / count
    for index = 1, count do
        points[index].x, points[index].y = points[index].x + shiftX, points[index].y + shiftY
    end
    return points, cx + shiftX, cy + shiftY
end

function Kit.assign(points, members, ux, uy)
    local tx, ty = -uy, ux
    local order, slots = {}, {}
    for index = 1, #members do order[index] = index end
    for index = 1, #points do slots[index] = index end
    table.sort(order, function(a, b)
        local pa = members[a].x * tx + members[a].y * ty
        local pb = members[b].x * tx + members[b].y * ty
        if pa ~= pb then return pa < pb end
        return a < b
    end)
    table.sort(slots, function(a, b)
        local pa = points[a].x * tx + points[a].y * ty
        local pb = points[b].x * tx + points[b].y * ty
        if pa ~= pb then return pa < pb end
        return a < b
    end)
    local result = {}
    for rank = 1, #order do
        if slots[rank] ~= nil then result[order[rank]] = points[slots[rank]] end
    end
    return result
end

function Kit.placeKey(square)
    if square == nil then return nil end
    if type(square.isOutside) == "function" and square:isOutside() then return "out" end
    local building = type(square.getBuilding) == "function" and square:getBuilding() or nil
    if building ~= nil and type(building.getID) == "function" then return "b" .. tostring(building:getID()) end
    return "in"
end

function Kit.freeSquare(x, y, z, referenceKey)
    if type(getCell) ~= "function" then return false end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return false end
    local square = cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z))
    if square == nil or type(square.isFree) ~= "function" or not square:isFree(false) then return false end
    return referenceKey == nil or Kit.placeKey(square) == referenceKey
end

function Kit.topicChain(situation)
    local chain = {}
    local function add(topic)
        for index = 1, #chain do if chain[index] == topic then return end end
        chain[#chain + 1] = topic
    end
    if situation.fishing then add("fishing"); return chain end
    if situation.requested ~= nil then add(situation.requested) end
    if situation.fight then add("after_fight") end
    if situation.plan ~= nil and Kit.roll(100) < Kit.planPercent then add("plan") end
    if situation.panic and Kit.roll(100) < Kit.panicPercent then add("panic_days") end
    if situation.moving then
        add("walk")
    elseif situation.shelter and Kit.roll(100) < Kit.shelterPercent then
        add("shelter")
    end
    if situation.scavenging then add("scavenge") end
    add("any")
    return chain
end

function Kit.roles(members, rolesMap, seed)
    local map = type(rolesMap) == "table" and rolesMap or {}
    local result = { speakers = {}, listeners = {}, ring = {}, commenter = nil, silent = nil }
    local pool = {}
    for index = 1, #members do
        local member = members[index]
        member.role = map[member.uid]
        if member.role == "lookout" or #pool >= Kit.maxRing then
            result.listeners[#result.listeners + 1] = member
        else
            pool[#pool + 1] = member
        end
    end
    local function lowest(skip, label)
        local best, bestValue = nil, nil
        for index = 1, #pool do
            local member = pool[index]
            if member ~= skip and member.role ~= "talker" then
                local value = Kit.hash(tostring(seed) .. ":" .. label .. ":" .. tostring(member.uid))
                if bestValue == nil or value < bestValue then best, bestValue = member, value end
            end
        end
        return best
    end
    local silent, commenter
    for index = 1, #pool do
        local member = pool[index]
        if member.role == "quiet" and silent == nil then silent = member end
        if member.role == "commenter" and commenter == nil and member ~= silent then commenter = member end
    end
    local total = #pool
    if total == 3 and silent == nil and commenter == nil then
        if Kit.hash(tostring(seed) .. ":kind") % 2 == 0 then
            commenter = lowest(nil, "commenter")
        else
            silent = lowest(nil, "silent")
        end
    elseif total >= 4 then
        if silent == nil then silent = lowest(commenter, "silent") end
        if commenter == nil then commenter = lowest(silent, "commenter") end
    end
    if total - (silent and 1 or 0) - (commenter and 1 or 0) < 2 then
        if commenter ~= nil then commenter = nil else silent = nil end
    end
    for index = 1, #pool do
        local member = pool[index]
        result.ring[#result.ring + 1] = member
        if member == silent then
            result.silent = member
        elseif member == commenter then
            result.commenter = member
        else
            result.speakers[#result.speakers + 1] = member
        end
    end
    return result
end

function Kit.playedBy(uid, id)
    local gossip = ProjectALife.Gossip
    local entry = gossip ~= nil and type(gossip.playedByUid) == "table" and gossip.playedByUid[uid] or nil
    return entry ~= nil and entry.set[id] == true
end

function Kit.allowed(source, contexts, cache, index)
    local gate = source.g
    local row = cache[gate]
    if row == nil then
        row = {}
        cache[gate] = row
    end
    local value = row[index]
    if value == nil then
        value = ProjectALife.DialogueData.allows(gate, contexts[index]) == true
        row[index] = value
    end
    return value
end

function Kit.assignSlots(source, id, speakers, contexts, slot, used, result, cache)
    if slot > source.min then return true end
    local gossip, gate = ProjectALife.Gossip, source.g
    local slotted = gate.r1 ~= nil or gate.r2 ~= nil or gate.r3 ~= nil or gate.x1 ~= nil or gate.x2 ~= nil or gate.x3 ~= nil
    for index = 1, #speakers do
        if not used[index] and Kit.allowed(source, contexts, cache, index)
                and (not slotted or gossip.meetSlotAllows(source, slot, contexts[index]))
                and not Kit.playedBy(speakers[index].uid, id) then
            used[index], result[slot] = true, speakers[index]
            if Kit.assignSlots(source, id, speakers, contexts, slot + 1, used, result, cache) then return true end
            used[index], result[slot] = nil, nil
        end
    end
    return false
end

function Kit.partition(pool)
    local part = Kit.partitions[pool]
    if part == nil then
        part = { size = 0, lists = {} }
        Kit.partitions[pool] = part
    end
    local size = #pool
    for index = part.size + 1, size do
        local minimum = pool[index].min
        local list = part.lists[minimum]
        if list == nil then
            list = {}
            part.lists[minimum] = list
        end
        list[#list + 1] = pool[index]
    end
    part.size = size
    return part
end

function Kit.stride(size)
    for index = 1, #Kit.strides do
        if size % Kit.strides[index] ~= 0 then return Kit.strides[index] end
    end
    return 1
end

function Kit.scanList(list, speakers, contexts, excluded, token, limit, wanted, cache)
    local matches, fitted = {}, 0
    local size = #list
    if size == 0 then return matches, fitted end
    local start, stride = Kit.hash(token) % size, Kit.stride(size)
    local used, result = {}, {}
    for step = 0, math.min(size, limit) - 1 do
        local source = list[(start + step * stride) % size + 1]
        local id = "corpus:" .. tostring(source.id)
        if not excluded[id] then
            fitted = fitted + 1
            if Kit.assignSlots(source, id, speakers, contexts, 1, used, result, cache) then
                local slots = {}
                for slot = 1, source.min do
                    slots[slot] = result[slot]
                    result[slot] = nil
                end
                for index = 1, #speakers do used[index] = nil end
                matches[#matches + 1] = { source = source, id = id, slots = slots }
                if #matches >= wanted then break end
            end
        end
    end
    return matches, fitted
end

function Kit.pickScene(topic, speakers, token, options)
    local data, speech = ProjectALife.DialogueData, ProjectALife.Speech
    if data == nil or speech == nil or type(ProjectALife.Gossip) ~= "table" then return nil, "data_missing" end
    options = type(options) == "table" and options or {}
    data.load()
    local pool = data.scenesByTopic[topic]
    if type(pool) ~= "table" or #pool == 0 then return nil, "pool_empty" end
    local contexts = {}
    for index = 1, #speakers do
        local ok, context = pcall(speech.contextFor, speakers[index].actor, nil)
        if not ok or type(context) ~= "table" then return nil, "context_missing" end
        contexts[index] = context
    end
    local excluded = type(options.exclude) == "table" and options.exclude or {}
    local prefer = tonumber(options.prefer)
    local part = Kit.partition(pool)
    local seed, fitted, cache = tostring(token) .. ":scene", 0, {}
    if prefer ~= nil then
        for minimum = prefer, #speakers do
            local list = part.lists[minimum]
            if list ~= nil then
                local matches, seen = Kit.scanList(list, speakers, contexts, excluded, seed .. minimum,
                    Kit.sceneScan, Kit.sceneSamples, cache)
                fitted = fitted + seen
                if #matches > 0 then return matches[Kit.roll(#matches) + 1] end
            end
        end
    end
    local list = part.lists[2]
    if list ~= nil then
        local matches, seen = Kit.scanList(list, speakers, contexts, excluded, seed .. "2",
            Kit.sceneScan, Kit.sceneSamples, cache)
        fitted = fitted + seen
        if #matches > 0 then return matches[Kit.roll(#matches) + 1] end
    end
    if fitted == 0 then return nil, "no_fit" end
    return nil, "gate"
end

function Kit.gesture(register, armed, text, speaking, roll)
    local gossip = ProjectALife.Gossip
    if gossip == nil or type(gossip.gesturePreset) ~= "function" then return nil end
    return gossip.gesturePreset(register, armed, text, speaking, roll)
end

function Kit.greetRule(stance)
    return Kit.greetRules[stance == "allied" and "friendly" or stance]
end

return Kit
