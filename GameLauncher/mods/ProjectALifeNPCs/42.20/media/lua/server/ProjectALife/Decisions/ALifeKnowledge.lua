ProjectALife = ProjectALife or {}

local Knowledge = {
    defaults = {
        fixBlurTiles = 12,
        huntBlurTiles = 24,
        searchMs = 90000,
        lostSightMs = 6000,
    },
    arriveTiles = 4,
    nearBuildingTiles = 10,
    huntSightTiles = 50,
    leadMs = 30000,
    giveUpSearches = 2,
    giveUpMs = 1200000,
    sightEveryMs = 400,
    roomCheckMs = 2000,
    planLimit = 64,
    cacheMs = 5000,
    fixes = {},
    gaveUpCrews = {},
    searches = {},
    searched = {},
    lastSeen = {},
    adapters = {},
    metrics = { fixes = 0, leads = 0, refusedBlind = 0, lost = 0, searches = 0, callouts = 0, posts = 0,
        entries = 0, cleared = 0, timedOut = 0, gaveUp = 0, roomsCalled = 0 },
}
ProjectALife.Knowledge = Knowledge

function Knowledge.configure(adapters)
    Knowledge.adapters = type(adapters) == "table" and adapters or {}
    Knowledge.cached = nil
end

function Knowledge.reset()
    Knowledge.fixes, Knowledge.searches, Knowledge.searched, Knowledge.lastSeen = {}, {}, {}, {}
    Knowledge.gaveUpCrews = {}
    Knowledge.cached = nil
    Knowledge.metrics = { fixes = 0, leads = 0, refusedBlind = 0, lost = 0, searches = 0, callouts = 0, posts = 0,
        entries = 0, cleared = 0, timedOut = 0, gaveUp = 0, roomsCalled = 0 }
end

function Knowledge.count(name)
    Knowledge.metrics[name] = (Knowledge.metrics[name] or 0) + 1
end

function Knowledge.now()
    if type(Knowledge.adapters.nowMs) == "function" then return Knowledge.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Knowledge.roll(maximum)
    maximum = math.max(1, math.floor(tonumber(maximum) or 1))
    if type(Knowledge.adapters.roll) == "function" then return Knowledge.adapters.roll(maximum) end
    if type(ZombRand) == "function" then return ZombRand(maximum) end
    return 0
end

function Knowledge.settings(now)
    now = now or Knowledge.now()
    local cached = Knowledge.cached
    if cached ~= nil and now >= cached.atMs and now - cached.atMs < Knowledge.cacheMs then return cached end
    local d = Knowledge.defaults
    local value = { atMs = now, fixBlurTiles = d.fixBlurTiles, huntBlurTiles = d.huntBlurTiles,
        searchMs = d.searchMs, lostSightMs = d.lostSightMs }
    local settings = ProjectALife.Settings
    if type(settings) == "table" and type(settings.read) == "function" then
        local ok, current = pcall(settings.read, nil, true)
        if ok and type(current) == "table" then
            local blur = tonumber(current.encounterFixBlurTiles)
            if blur ~= nil then
                value.fixBlurTiles = blur
                value.huntBlurTiles = blur * 2
            end
            local search = tonumber(current.encounterSearchSeconds)
            if search ~= nil then value.searchMs = math.floor(search * 1000) end
            local lost = tonumber(current.encounterLostSightSeconds)
            if lost ~= nil then value.lostSightMs = math.floor(lost * 1000) end
        end
    end
    Knowledge.cached = value
    return value
end

function Knowledge.memoryOf(actor)
    if type(actor) ~= "table" then return {} end
    if type(actor.memory) ~= "table" then actor.memory = {} end
    return actor.memory
end

function Knowledge.crewKey(actor)
    local memory = Knowledge.memoryOf(actor)
    if memory.groupId ~= nil then return tostring(memory.groupId) end
    if memory.outpostId ~= nil then return "outpost:" .. tostring(memory.outpostId) end
    return "solo:" .. tostring(type(actor) == "table" and actor.uid or "?")
end

function Knowledge.keyOf(player)
    if player == nil then return nil end
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.playerKey) == "function" then return speech.playerKey(player) end
    local reputation = ProjectALife.Reputation
    if reputation ~= nil and type(reputation.playerKey) == "function" then return reputation.playerKey(player) end
    return nil
end

function Knowledge.persist(actor, key, value)
    local memory = Knowledge.memoryOf(actor)
    memory[key] = value
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(actor) ~= "table" or actor.uid == nil
            or type(registry.peek) ~= "function" or type(registry.updateTransient) ~= "function" then
        return false
    end
    local current = registry.peek(actor.uid)
    if current == nil then return false end
    return registry.updateTransient(current.uid, current.revision, function(record)
        record.memory = type(record.memory) == "table" and record.memory or {}
        record.memory[key] = value
    end, true) == true
end

function Knowledge.xyz(body)
    if body == nil then return nil end
    if type(body) == "table" and tonumber(body.x) ~= nil and type(body.getX) ~= "function" then
        return tonumber(body.x), tonumber(body.y), tonumber(body.z) or 0
    end
    if type(body.getX) ~= "function" then return nil end
    local ok, x, y, z = pcall(function() return body:getX(), body:getY(), body:getZ() end)
    if not ok or x == nil then return nil end
    return x, y, z or 0
end

function Knowledge.distance(a, b)
    local ax, ay = Knowledge.xyz(a)
    local bx, by = Knowledge.xyz(b)
    if ax == nil or bx == nil then return math.huge end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

function Knowledge.near(shell, point, tiles)
    return Knowledge.distance(shell, point) <= (tonumber(tiles) or Knowledge.arriveTiles)
end

function Knowledge.squareAt(x, y, z)
    if type(Knowledge.adapters.squareAt) == "function" then return Knowledge.adapters.squareAt(x, y, z) end
    if type(getCell) ~= "function" or x == nil or y == nil then return nil end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return nil end
    return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(tonumber(z) or 0))
end

function Knowledge.buildingAt(x, y, z)
    local square = Knowledge.squareAt(x, y, z)
    if square == nil or type(square.getBuilding) ~= "function" then return nil end
    return square:getBuilding()
end

function Knowledge.buildingKey(building)
    if building == nil then return nil end
    if type(building.getID) == "function" then
        local ok, id = pcall(building.getID, building)
        if ok and id ~= nil then return "b:" .. tostring(id) end
    end
    return "b:" .. tostring(building)
end

function Knowledge.shellBuilding(shell)
    if shell == nil or type(shell.getCurrentSquare) ~= "function" then return nil end
    local square = shell:getCurrentSquare()
    if square == nil or type(square.getBuilding) ~= "function" then return nil end
    return square:getBuilding()
end

Knowledge.ring = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }
function Knowledge.buildingNear(x, y, z, reach)
    local here = Knowledge.buildingAt(x, y, z)
    if here ~= nil then return here, x, y end
    for ring = 2, math.max(2, math.floor(tonumber(reach) or Knowledge.nearBuildingTiles)), 2 do
        for _, step in ipairs(Knowledge.ring) do
            local px, py = x + step[1] * ring, y + step[2] * ring
            local found = Knowledge.buildingAt(px, py, z)
            if found ~= nil then return found, px, py end
        end
    end
    return nil
end

function Knowledge.blur(x, y, tiles)
    tiles = math.max(0, math.floor(tonumber(tiles) or 0))
    if tiles <= 0 then return x, y end
    local angle = Knowledge.roll(360) * math.pi / 180
    local reach = Knowledge.roll(tiles + 1)
    return x + math.cos(angle) * reach, y + math.sin(angle) * reach
end

function Knowledge.sees(actor, shell, target)
    if shell == nil or target == nil then return false end
    if Knowledge.distance(shell, target) > Knowledge.huntSightTiles then return false end
    local perception = ProjectALife.Perception
    if perception == nil or type(perception.visible) ~= "function" then return false end
    return perception.visible(shell, target) == true
end

function Knowledge.crewSighting(actor, target, now)
    local tactics = ProjectALife.SquadTactics
    local memory = Knowledge.memoryOf(actor)
    local contacts = tactics ~= nil and type(tactics.contacts) == "table" and tactics.contacts or nil
    local contact = contacts ~= nil and memory.groupId ~= nil and contacts[memory.groupId] or nil
    if type(contact) ~= "table" or contact.target ~= target or type(contact.position) ~= "table" then return nil end
    local age = now - (tonumber(contact.atMs) or -1e12)
    if age < 0 or age > Knowledge.leadMs then return nil end
    return { x = contact.position.x, y = contact.position.y, z = contact.position.z or 0, source = "report",
        atMs = contact.atMs }
end

function Knowledge.gaveUp(actor, key, now)
    local memory = Knowledge.memoryOf(actor)
    local mark = memory.knowledgeGaveUp
    local crewMark = Knowledge.gaveUpCrews[Knowledge.crewKey(actor)]
    if (type(mark) ~= "table" or mark.key ~= key) and type(crewMark) == "table" and crewMark.key == key then
        mark = crewMark
        Knowledge.persist(actor, "knowledgeGaveUp", { key = key, atMs = crewMark.atMs })
    end
    if type(mark) ~= "table" or mark.key ~= key then return false end
    if now - (tonumber(mark.atMs) or -1e12) <= Knowledge.giveUpMs and now >= (tonumber(mark.atMs) or 0) then return true end
    Knowledge.persist(actor, "knowledgeGaveUp", nil)
    return false
end

function Knowledge.giveUp(actor, shell, key, now, player)
    Knowledge.count("gaveUp")
    Knowledge.persist(actor, "knowledgeGaveUp", { key = key, atMs = now })
    Knowledge.persist(actor, "knowledgeFix", nil)
    Knowledge.fixes[Knowledge.crewKey(actor)] = nil
    Knowledge.gaveUpCrews[Knowledge.crewKey(actor)] = { key = key, atMs = now }
    local perception = ProjectALife.Perception
    if perception ~= nil and type(perception.clearLastKnown) == "function" then perception.clearLastKnown(actor) end
    Knowledge.call(actor, shell, player, "ENC_GIVE_UP")
end

function Knowledge.fixFor(actor, shell, target, targetPosition, mode, now)
    local key = Knowledge.keyOf(target)
    local memory = Knowledge.memoryOf(actor)
    local fix = memory.knowledgeFix
    local crew = Knowledge.crewKey(actor)
    local shared = Knowledge.fixes[crew]
    if type(shared) == "table" and shared.key == key then
        if fix ~= shared then Knowledge.persist(actor, "knowledgeFix", shared) end
        return shared
    end
    if type(fix) == "table" and (fix.key == nil or fix.key == key) and tonumber(fix.x) ~= nil and tonumber(fix.y) ~= nil then
        if fix.key == nil then fix.key = key end
        Knowledge.fixes[crew] = fix
        return fix
    end
    if type(targetPosition) ~= "table" or tonumber(targetPosition.x) == nil then return nil end
    local s = Knowledge.settings(now)
    local named = type(memory.targetUsername) == "string" and memory.targetUsername ~= ""
    local blur = (named or mode == "manhunt") and s.fixBlurTiles or s.huntBlurTiles
    local x, y = Knowledge.blur(targetPosition.x, targetPosition.y, blur)
    fix = { key = key, x = x, y = y, z = tonumber(targetPosition.z) or 0, atMs = now, source = "dispatch", searches = 0 }
    Knowledge.fixes[crew] = fix
    Knowledge.persist(actor, "knowledgeFix", fix)
    Knowledge.count("fixes")
    return fix
end

function Knowledge.pursuitLead(actor, shell, target, targetPosition, mode, now)
    now = tonumber(now) or Knowledge.now()
    local key = Knowledge.keyOf(target)
    if Knowledge.gaveUp(actor, key, now) then return nil end
    local perception = ProjectALife.Perception
    local own = perception ~= nil and type(perception.lastKnownFor) == "function" and perception.lastKnownFor(actor, now) or nil
    local lead
    if own ~= nil and own.target == target then
        lead = { x = own.x, y = own.y, z = own.z or 0, source = "last" }
    else
        lead = Knowledge.crewSighting(actor, target, now)
    end
    local fix = Knowledge.fixFor(actor, shell, target, targetPosition, mode, now)
    if lead == nil then lead = fix end
    if lead == nil then return nil end
    Knowledge.count("leads")
    if Knowledge.near(shell, lead, Knowledge.arriveTiles) then
        Knowledge.arrive(actor, shell, lead, now, target)
    end
    return { x = lead.x, y = lead.y, z = lead.z or 0, source = lead.source or "dispatch" }
end

function Knowledge.pursuitThreat(actor, shell, target)
    if target == nil then return nil end
    if Knowledge.sees(actor, shell, target) then return target end
    Knowledge.count("refusedBlind")
    return nil
end

function Knowledge.arrive(actor, shell, lead, now, target)
    local crew = Knowledge.crewKey(actor)
    if Knowledge.searches[crew] ~= nil then return Knowledge.searches[crew] end
    local building, bx, by = Knowledge.buildingNear(lead.x, lead.y, lead.z, Knowledge.nearBuildingTiles)
    local key = Knowledge.keyOf(target)
    if building == nil or Knowledge.wasSearched(crew, building, now) then
        return Knowledge.areaSearched(actor, shell, key, now, target)
    end
    local standoff = ProjectALife.Standoff
    if standoff ~= nil and type(standoff.wantsCallout) == "function"
            and standoff.wantsCallout(actor, shell, { x = bx, y = by, z = lead.z or 0 }, building, now) then
        if standoff.requestCallout(actor, shell, target, { x = bx, y = by, z = lead.z or 0 }, building, now) then
            Knowledge.count("callouts")
            Knowledge.markSearched(crew, building, now)
            return nil
        end
    end
    return Knowledge.beginSearch(actor, shell, { x = bx, y = by, z = lead.z or 0, key = key }, now, target)
end

function Knowledge.areaSearched(actor, shell, key, now, target)
    local memory = Knowledge.memoryOf(actor)
    local fix = Knowledge.fixes[Knowledge.crewKey(actor)]
    if type(fix) ~= "table" then fix = memory.knowledgeFix end
    if type(fix) ~= "table" then return nil end
    local searches = (tonumber(fix.searches) or 0) + 1
    if searches >= Knowledge.giveUpSearches then
        Knowledge.giveUp(actor, shell, key, now, target)
        return nil
    end
    local x, y = Knowledge.blur(tonumber(fix.x), tonumber(fix.y), Knowledge.nearBuildingTiles * 2)
    local moved = { key = fix.key, x = x, y = y, z = fix.z, atMs = fix.atMs, source = fix.source, searches = searches }
    Knowledge.fixes[Knowledge.crewKey(actor)] = moved
    Knowledge.persist(actor, "knowledgeFix", moved)
    return nil
end

function Knowledge.wasSearched(crew, building, now)
    local list = Knowledge.searched[crew]
    local at = type(list) == "table" and list[Knowledge.buildingKey(building)] or nil
    return at ~= nil and now - at < Knowledge.giveUpMs and now >= at
end

function Knowledge.markSearched(crew, building, now)
    local list = Knowledge.searched[crew]
    if list == nil then
        local size = 0
        for key in pairs(Knowledge.searched) do size = size + 1 end
        if size >= Knowledge.planLimit then Knowledge.searched = {} end
        list = {}
        Knowledge.searched[crew] = list
    end
    list[Knowledge.buildingKey(building)] = now
end

function Knowledge.beginSearch(actor, shell, point, now, target)
    local crew = Knowledge.crewKey(actor)
    local building = Knowledge.buildingNear(point.x, point.y, point.z, Knowledge.nearBuildingTiles)
    if building == nil then return nil end
    local policy = ProjectALife.DoorPolicy
    if policy ~= nil and type(policy.pathRefusal) == "function"
            and policy.pathRefusal(actor, shell, point, "search") ~= nil then
        return nil
    end
    local count = 0
    for key, held in pairs(Knowledge.searches) do
        if type(held) == "table" and now >= (tonumber(held.untilMs) or 0) then
            Knowledge.searches[key] = nil
        else
            count = count + 1
        end
    end
    if count >= Knowledge.planLimit then return nil end
    local sx, sy, sz = Knowledge.xyz(shell)
    local door
    local breach = ProjectALife.ModuleBreach
    if breach ~= nil and type(breach.findDoor) == "function" and sx ~= nil then
        local ok, found = pcall(breach.findDoor, building, sx, sy, sz, nil, now)
        if ok then door = found end
    end
    local s = Knowledge.settings(now)
    local plan = { crew = crew, building = building, buildingKey = Knowledge.buildingKey(building),
        point = { x = point.x, y = point.y, z = point.z or 0 }, door = door, startedAtMs = now,
        untilMs = now + s.searchMs, roles = {}, done = {}, called = {}, target = target,
        playerKey = point.key or Knowledge.keyOf(target) }
    Knowledge.searches[crew] = plan
    Knowledge.markSearched(crew, building, now)
    Knowledge.count("searches")
    Knowledge.call(actor, shell, target, "ENC_SEARCH_START")
    return plan
end

function Knowledge.cancelSearch(crew)
    Knowledge.searches[crew] = nil
end

function Knowledge.crewSize(actor, shell)
    local memory = Knowledge.memoryOf(actor)
    local tactics = ProjectALife.SquadTactics
    if memory.groupId == nil or tactics == nil or type(tactics.livingMembers) ~= "function" then return 1 end
    local x, y = Knowledge.xyz(shell)
    local count = tactics.livingMembers(memory.groupId, actor.uid, x or 0, y or 0, 40)
    return 1 + (tonumber(count) or 0)
end

function Knowledge.call(actor, shell, player, event)
    if type(Knowledge.adapters.call) == "function" then return Knowledge.adapters.call(actor, shell, player, event) end
    local voice = ProjectALife.Voice
    local audio = Knowledge.audio[event]
    if audio ~= nil and voice ~= nil and type(voice.play) == "function" then
        pcall(voice.play, shell, audio, { textEnabled = false })
    end
    local fair = ProjectALife.Fairness
    if player ~= nil and fair ~= nil and type(fair.shout) == "function" then
        local ok, said = pcall(fair.shout, actor, shell, player, event)
        return ok and said == true
    end
    return false
end

Knowledge.audio = { ENC_SEARCH_START = "SEARCH_START", ENC_SEARCH_POST = "SEARCH_SPLIT",
    ENC_ROOM_CLEAR = "ROOM_CLEAR", ENC_SEARCH_DONE = "AREA_CLEAR", ENC_GIVE_UP = "SEARCH_COMPLETE" }

function Knowledge.decide(actor, shell, context)
    local now = tonumber(context and context.now) or Knowledge.now()
    local standoff = ProjectALife.Standoff
    if standoff ~= nil and type(standoff.memberStep) == "function" then
        local held = standoff.memberStep(actor, shell, context, now)
        if held ~= nil then return held end
    end
    local orders = ProjectALife.TalkOrders
    if orders ~= nil and type(orders.memberStep) == "function" then
        local ordered = orders.memberStep(actor, shell, context, now)
        if ordered ~= nil then return ordered end
    end
    return Knowledge.searchStep(actor, shell, context, now)
end

function Knowledge.searchStep(actor, shell, context, now)
    local crew = Knowledge.crewKey(actor)
    local plan = Knowledge.searches[crew]
    local memory = Knowledge.memoryOf(actor)
    if plan == nil then
        local order = memory.searchOrder
        if type(order) == "table" and now < (tonumber(order.untilMs) or 0) and tonumber(order.x) ~= nil then
            Knowledge.persist(actor, "searchOrder", nil)
            plan = Knowledge.beginSearch(actor, shell, order, now, nil)
        else
            local perception = ProjectALife.Perception
            local lead = perception ~= nil and type(perception.lastKnownFor) == "function"
                and perception.lastKnownFor(actor, now) or nil
            if lead ~= nil and lead.kind == "player" and lead.shared ~= true
                    and Knowledge.near(shell, lead, Knowledge.nearBuildingTiles)
                    and Knowledge.buildingAt(lead.x, lead.y, lead.z) ~= nil then
                plan = Knowledge.arrive(actor, shell, lead, now, lead.target)
            end
        end
        if plan == nil then return nil end
    end
    return Knowledge.planStep(actor, shell, context, plan, now)
end

function Knowledge.outcomeSince(actor, plan)
    local memory = Knowledge.memoryOf(actor)
    local outcomes = memory.standoffOutcomes
    local seen = type(outcomes) == "table" and plan.playerKey ~= nil and outcomes[plan.playerKey] or nil
    return type(seen) == "table" and (tonumber(seen.ms) or -1e12) >= plan.startedAtMs
end

function Knowledge.planStep(actor, shell, context, plan, now)
    if now >= plan.untilMs then
        Knowledge.count("timedOut")
        return Knowledge.finishSearch(actor, shell, plan, now)
    end
    if Knowledge.outcomeSince(actor, plan) then
        Knowledge.searches[plan.crew] = nil
        return nil
    end
    local role = plan.roles[actor.uid]
    if role == nil then
        if plan.door ~= nil and plan.postUid == nil and Knowledge.crewSize(actor, shell) >= 2 then
            role = "post"
            plan.postUid = actor.uid
            Knowledge.count("posts")
            Knowledge.call(actor, shell, plan.target, "ENC_SEARCH_POST")
        else
            role = "sweep"
        end
        plan.roles[actor.uid] = role
    end
    if role == "post" then return Knowledge.postStep(actor, shell, context, plan, now) end
    return Knowledge.sweepStep(actor, shell, context, plan, now)
end

function Knowledge.postStep(actor, shell, context, plan, now)
    local door = plan.door
    local spot = { x = door.ox, y = door.oy, z = door.oz or 0 }
    if Knowledge.distance(shell, spot) > 1.2 and type(context.startMovement) == "function" then
        local state = context.startMovement(actor, shell, spot, "search_post", { pace = "walk", timeoutMs = 9000 })
        if state ~= nil then return state end
    end
    pcall(function()
        local guard = ProjectALife.AIFence
        if guard ~= nil and type(guard.faceAimPoint) == "function" then guard.faceAimPoint(shell, door.ix, door.iy, now) end
    end)
    if Knowledge.sweepersDone(plan) then return Knowledge.finishSearch(actor, shell, plan, now) end
    if type(context.setActivity) == "function" then context.setActivity(actor, "idle", "search_post") end
    return { kind = "idle", intent = "search_post", cooldownUntilMs = now + 1000 }
end

function Knowledge.sweepersDone(plan)
    local any = false
    for uid, role in pairs(plan.roles) do
        if role == "sweep" then
            any = true
            if plan.done[uid] ~= true then return false end
        end
    end
    return any
end

function Knowledge.entryPoint(plan)
    if plan.door ~= nil then return { x = plan.door.ix, y = plan.door.iy, z = plan.door.oz or 0 } end
    return plan.point
end

function Knowledge.sweepStep(actor, shell, context, plan, now)
    if plan.done[actor.uid] == true then
        if Knowledge.sweepersDone(plan) then return Knowledge.finishSearch(actor, shell, plan, now) end
        return nil
    end
    local inside = Knowledge.shellBuilding(shell)
    if inside == nil or Knowledge.buildingKey(inside) ~= plan.buildingKey then
        local entry = Knowledge.entryPoint(plan)
        pcall(function()
            local traversal = ProjectALife.ObstacleTraversal
            if traversal ~= nil and type(traversal.openDoorAhead) == "function" then traversal.openDoorAhead(shell, entry) end
        end)
        if type(context.startMovement) == "function" then
            Knowledge.count("entries")
            local state = context.startMovement(actor, shell, entry, "search_enter", { pace = "walk", timeoutMs = 12000 })
            if state ~= nil then return state end
        end
        plan.done[actor.uid] = true
        return nil
    end
    local checkedAt = plan.called[actor.uid] or -1e12
    if now - checkedAt >= Knowledge.roomCheckMs then
        plan.called[actor.uid] = now
        local left, cleared = Knowledge.roomsLeft(actor, shell, now)
        local before = plan.cleared and plan.cleared[actor.uid] or 0
        plan.cleared = plan.cleared or {}
        if cleared > before then
            plan.cleared[actor.uid] = cleared
            Knowledge.count("roomsCalled")
            Knowledge.call(actor, shell, plan.target, "ENC_ROOM_CLEAR")
        end
        if left == 0 then
            plan.done[actor.uid] = true
            if Knowledge.sweepersDone(plan) then return Knowledge.finishSearch(actor, shell, plan, now) end
        end
    end
    return nil
end

function Knowledge.roomsLeft(actor, shell, now)
    if type(Knowledge.adapters.roomsLeft) == "function" then return Knowledge.adapters.roomsLeft(actor, shell, now) end
    local breach = ProjectALife.ModuleBreach
    local memory = Knowledge.memoryOf(actor)
    local cleared = 0
    if type(memory.cqbCleared) == "table" then for _ in pairs(memory.cqbCleared) do cleared = cleared + 1 end end
    if breach == nil or type(breach.readRooms) ~= "function" or type(breach.openRooms) ~= "function" then return 0, cleared end
    local ok, left = pcall(function()
        local rooms, hereKey = breach.readRooms(shell)
        local x, y, z = Knowledge.xyz(shell)
        local here = { x = x, y = y, z = z, roomKey = hereKey }
        local group = breach.groupCleared[memory.groupId or actor.uid]
        local open = breach.openRooms(rooms, here, memory.cqbCleared, group, now, breach.settings)
        if type(memory.cqbPlan) == "table" then return #open + 1 end
        return #open
    end)
    if not ok then return 0, cleared end
    return tonumber(left) or 0, cleared
end

function Knowledge.finishSearch(actor, shell, plan, now)
    if Knowledge.searches[plan.crew] == plan then Knowledge.searches[plan.crew] = nil end
    if plan.finished == true then return nil end
    plan.finished = true
    Knowledge.count("cleared")
    Knowledge.call(actor, shell, plan.target, "ENC_SEARCH_DONE")
    local perception = ProjectALife.Perception
    if perception ~= nil and type(perception.clearLastKnown) == "function" then perception.clearLastKnown(actor) end
    Knowledge.areaSearched(actor, shell, plan.playerKey, now, plan.target)
    return nil
end

function Knowledge.lostTarget(actor, shell, state, now)
    if type(state) ~= "table" or state.threatKind ~= "player" or state.selfDefence == true then return false end
    local target = state.threat
    if target == nil or shell == nil or type(actor) ~= "table" then return false end
    local uid = actor.uid
    local entry = Knowledge.lastSeen[uid]
    if entry == nil or entry.target ~= target then
        local x, y, z = Knowledge.xyz(target)
        entry = { target = target, seenAtMs = now, checkedAtMs = -1e12, x = x, y = y, z = z }
        Knowledge.lastSeen[uid] = entry
    end
    if now - entry.checkedAtMs < Knowledge.sightEveryMs and now >= entry.checkedAtMs then return false end
    entry.checkedAtMs = now
    local perception = ProjectALife.Perception
    local seen = Knowledge.distance(shell, target) <= 1.6
    if not seen and perception ~= nil and type(perception.visible) == "function" then
        seen = perception.visible(shell, target) == true
    end
    if seen then
        local x, y, z = Knowledge.xyz(target)
        local dt = (now - entry.seenAtMs) / 1000
        if x ~= nil and entry.x ~= nil and dt > 0 and dt <= 2 and z == entry.z then
            entry.vx, entry.vy = (x - entry.x) / dt, (y - entry.y) / dt
            if entry.vx * entry.vx + entry.vy * entry.vy > 36 then entry.vx, entry.vy = 0, 0 end
        else
            entry.vx, entry.vy = 0, 0
        end
        entry.seenAtMs = now
        entry.x, entry.y, entry.z = x, y, z
        return false
    end
    if now - entry.seenAtMs < Knowledge.settings(now).lostSightMs then return false end
    Knowledge.lastSeen[uid] = nil
    Knowledge.count("lost")
    if perception ~= nil and type(perception.lastKnown) == "table" and entry.x ~= nil then
        local x, y = entry.x, entry.y
        local vx, vy = tonumber(entry.vx) or 0, tonumber(entry.vy) or 0
        local speed = math.sqrt(vx * vx + vy * vy)
        if speed > 0 then
            local seconds = math.min(2, 4 / speed)
            local px, py = x + vx * seconds, y + vy * seconds
            local square = Knowledge.squareAt(px, py, entry.z)
            local okay = false
            if square ~= nil and type(square.isFree) == "function" and type(square.TreatAsSolidFloor) == "function" then
                okay = square:isFree(false) == true and square:TreatAsSolidFloor() == true
            end
            if okay then x, y = px, py end
        end
        perception.lastKnown[uid] = { x = x, y = y, z = entry.z, kind = "player", target = target,
            atMs = now, source = (x ~= entry.x or y ~= entry.y) and "dead_reckoning" or "last_seen" }
        if type(perception.engagements) == "table" then perception.engagements[uid] = nil end
    end
    return true
end

function Knowledge.forget(uid)
    Knowledge.lastSeen[uid] = nil
end

return Knowledge
