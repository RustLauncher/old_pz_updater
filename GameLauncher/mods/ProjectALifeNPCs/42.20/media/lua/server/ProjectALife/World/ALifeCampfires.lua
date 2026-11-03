ProjectALife = ProjectALife or {}

require "ProjectALife/Core/ALifeDayCycle"
require "ProjectALife/Senses/ALifeAwareness"
require "ProjectALife/Outposts/ALifePlanks"

local Campfires = {
    settings = {

        fuelMinutes = 540,
        maxActive = 12,

        senderRadius = 60,
        perSenderMs = 1000,
    },

    active = {},
    metrics = { lit = 0, doused = 0, refused = 0, relayed = 0, remote = 0, remoteRejected = 0 },
    adapters = {},
    senderAtMs = {},
    protected = setmetatable({}, { __mode = "k" }),
    nearby = setmetatable({}, { __mode = "k" }),
    nearbyCount = 0,
}
ProjectALife.Campfires = Campfires

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Campfires.bindStore()
    if Campfires.storeBound then return Campfires.active end
    local store
    if type(Campfires.adapters.getOrCreate) == "function" then
        store = Campfires.adapters.getOrCreate("ProjectALife.Campfires.v1")
    elseif ModData ~= nil and type(ModData.getOrCreate) == "function" then
        pcall(function() store = ModData.getOrCreate("ProjectALife.Campfires.v1") end)
    end
    if type(store) == "table" then
        for key, entry in pairs(Campfires.active) do store[key] = store[key] or entry end
        Campfires.active = store
        Campfires.storeBound = true
    end
    return Campfires.active
end

local function clientOnly()
    if type(Campfires.adapters.clientOnly) == "function" then return Campfires.adapters.clientOnly() == true end
    local client = type(isClient) == "function" and isClient() == true
    local server = type(isServer) == "function" and isServer() == true
    return client and not server
end

local function system()
    if Campfires.adapters.system ~= nil then return Campfires.adapters.system end
    if type(SCampfireSystem) == "table" then return SCampfireSystem.instance end
    return nil
end

local function relay(message)
    local executor = ProjectALife.Executor
    if type(Campfires.adapters.send) == "function" then
        Campfires.adapters.send("executorCampfire", message)
    elseif executor ~= nil and type(executor.relayCampfire) == "function" then

        if executor.relayCampfire(message) ~= true then return false end
    else
        return false
    end
    Campfires.metrics.relayed = Campfires.metrics.relayed + 1
    return true
end

local function refuse(reason)
    Campfires.metrics.refused = Campfires.metrics.refused + 1
    return false, reason
end

function Campfires.count()
    local n = 0
    for _ in pairs(Campfires.active) do n = n + 1 end
    return n
end

function Campfires.clearSegment(from, target, fire, radius)
    local dx, dy = target.x - from.x, target.y - from.y
    local length = dx * dx + dy * dy
    local t = length > 0 and ((fire.x - from.x) * dx + (fire.y - from.y) * dy) / length or 0
    t = math.max(0, math.min(1, t))
    local x, y = from.x + t * dx - fire.x, from.y + t * dy - fire.y
    return x * x + y * y >= radius * radius
end

function Campfires.litSquare(square)
    if square == nil or square.getObjects == nil then return false end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if object.getName ~= nil and object:getName() == "Campfire"
                and object:getModData().isLit == true then return true end
    end
    return false
end

function Campfires.protect(shell)
    if shell == nil or shell.getFireKillRate == nil or shell.getCurrentSquare == nil then return end
    local held = Campfires.protected[shell]
    local square = shell:getCurrentSquare()
    local lit = Campfires.litSquare(square)
    if held then
        if shell:isOnFire() then shell:StopBurning() end
        if lit then return end
        Campfires.releaseProtection(shell)
    elseif lit and not shell:isOnFire() then
        Campfires.protected[shell] = { kill = shell:getFireKillRate(), spread = shell:getFireSpreadProbability() }
        shell:setFireKillRate(0)
        shell:setFireSpreadProbability(0)
    end
end

function Campfires.releaseProtection(shell)
    local held = Campfires.protected[shell]
    if held == nil then return end
    shell:setFireKillRate(held.kill)
    shell:setFireSpreadProbability(held.spread)
    Campfires.protected[shell] = nil
end

function Campfires.finishTick()
    for shell in pairs(Campfires.protected) do
        if shell:isOnFire() then shell:StopBurning() end
    end
end

function Campfires.pruneNearby(now)
    local stale, kept = {}, 0
    for square, entry in pairs(Campfires.nearby) do
        if type(entry) ~= "table" or now - (tonumber(entry.at) or 0) > 750 then
            stale[#stale + 1] = square
        else
            kept = kept + 1
        end
    end
    for index = 1, #stale do Campfires.nearby[stale[index]] = nil end
    Campfires.nearbyCount = kept
    return #stale
end

function Campfires.blockingFire(from, target)
    if type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil then return nil end
    local x, y, z = math.floor(from.x), math.floor(from.y), math.floor(from.z or 0)
    local square = cell:getGridSquare(x, y, z)
    if square == nil then return nil end
    local now, cached = nowMs(), Campfires.nearby[square]
    if cached == nil or now - cached.at > 750 then
        cached = { at = now, fires = {} }
        for dx = -2, 2 do
            for dy = -2, 2 do
                if Campfires.litSquare(cell:getGridSquare(x + dx, y + dy, z)) then
                    cached.fires[#cached.fires + 1] = { x = x + dx + 0.5, y = y + dy + 0.5, z = z }
                end
            end
        end
        Campfires.nearby[square] = cached
        Campfires.nearbyCount = (tonumber(Campfires.nearbyCount) or 0) + 1
        if Campfires.nearbyCount > 512 then Campfires.pruneNearby(now) end
    end
    for _, fire in ipairs(cached.fires) do
        if not Campfires.clearSegment(from, target, fire, 1.65) then return fire end
    end
    return nil
end

function Campfires.safeStep(actor, from, target)
    local memory = actor and actor.memory or {}
    local fire = memory.nightCamp == true and memory.stanceAnchor or nil
    if type(from) ~= "table" or type(target) ~= "table"
            or tonumber(from.x) == nil or tonumber(from.y) == nil
            or tonumber(target.x) == nil or tonumber(target.y) == nil then return target end
    if type(fire) ~= "table" or tonumber(fire.x) == nil or tonumber(fire.y) == nil
            or math.floor(from.z or 0) ~= math.floor(fire.z or 0)
            or Campfires.clearSegment(from, target, fire, 1.65) then
        fire = Campfires.blockingFire(from, target)
    end
    if fire == nil then return target end
    if Campfires.clearSegment(from, target, fire, 1.65) then return target end
    local dx, dy = from.x - fire.x, from.y - fire.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.01 then dx, dy, length = 1, 0, 1 end
    dx, dy = dx / length, dy / length
    local best, score
    for _, side in ipairs({ 0, 1, -1 }) do
        local cosine, sine = side == 0 and 1 or 0.5, side * 0.8660254
        local point = { x = fire.x + (dx * cosine - dy * sine) * 3.5,
            y = fire.y + (dy * cosine + dx * sine) * 3.5, z = fire.z or 0 }
        local clear = length < 1.65 or Campfires.clearSegment(from, point, fire, 1.65)
        if clear and type(getCell) == "function" then
            local ok, valid = pcall(function()
                local cell = getCell()
                local square = cell and cell:getGridSquare(math.floor(point.x), math.floor(point.y), point.z)
                return square ~= nil and square:isFree(false) and square:TreatAsSolidFloor()
            end)
            clear = ok and valid == true
        end
        if clear and (point.x - from.x)^2 + (point.y - from.y)^2 > 0.5 then
            local distance = (point.x - target.x)^2 + (point.y - target.y)^2
            if score == nil or distance < score then best, score = point, distance end
        end
    end

    return best or { x = from.x, y = from.y, z = from.z or 0 }
end

function Campfires.requestShelter(shell, kind, at, planks)
    if not clientOnly() or shell == nil or type(at) ~= "table" then return false end
    local identity = shell:getModData()
    if type(identity.ProjectALifeUID) ~= "string" or tonumber(identity.ProjectALifeGeneration) == nil then return false end
    return relay({ op = "shelter", uid = identity.ProjectALifeUID,
        generation = identity.ProjectALifeGeneration, kind = kind,
        x = at.x, y = at.y, z = at.z or 0, planks = planks })
end

function Campfires.boardPacks(shell, uid)
    local life, registry = ProjectALife.ModuleIdleLife, ProjectALife.ActorRegistry
    if type(uid) ~= "string" or life == nil or type(life.squadShells) ~= "function"
            or registry == nil or type(registry.read) ~= "function" then return { shell } end
    local actor = registry.read(uid)
    if actor == nil then return { shell } end
    local ok, shells = pcall(life.squadShells, actor, shell)
    if not ok or type(shells) ~= "table" or shells[1] ~= shell then return { shell } end
    return shells
end

function Campfires.applyShelter(shell, message)
    if clientOnly() or shell == nil or type(message) ~= "table"
            or (message.kind ~= "board" and message.kind ~= "sheets" and message.kind ~= "leave") then return false end
    for _, name in ipairs({ "x", "y", "z" }) do
        local value = message[name]
        if type(value) ~= "number" or value ~= value or math.abs(value) > 1000000 then return false end
    end
    if message.planks ~= nil and (type(message.planks) ~= "number"
            or message.planks ~= message.planks or math.abs(message.planks) == math.huge) then return false end
    if shell:isDead() or math.abs(shell:getZ() - message.z) > 0.5
            or (shell:getX() - message.x)^2 + (shell:getY() - message.y)^2 > 6.25 then return false end
    if message.kind == "leave" then
        local registry = ProjectALife.ActorRegistry
        local actor = registry and message.uid and registry.read(message.uid)
        local memory = actor and actor.memory or {}
        if memory.stance ~= "shelter" or memory.shelterManagedByLife ~= true then return false end
        local untilHours = tonumber(memory.shelterUntilHours)
        local time = getGameTime()
        if untilHours ~= nil then
            if time:getWorldAgeHours() < untilHours then return false end
        elseif ProjectALife.DayCycle ~= nil and ProjectALife.DayCycle.isNight() then return false end
        for _, record in ipairs(registry.list()) do
            if record.memory and record.memory.stance == "shelter" and record.memory.shelterManagedByLife == true and (record.uid == actor.uid
                    or (memory.groupId and record.memory.groupId == memory.groupId)) then
                registry.update(record.uid, record.revision, function(fresh)
                    fresh.memory.stance = ""
                    fresh.memory.stanceAnchor, fresh.memory.stancePost, fresh.memory.stancePhase = nil, nil, nil
                    fresh.memory.stanceAwareness, fresh.memory.shelterBuildingId, fresh.memory.shelterUntilHours = nil, nil, nil
                    fresh.memory.shelterManagedByLife = nil
                end)
            end
        end
        return true
    end
    local square = shell:getCurrentSquare()
    local building = square and square:getBuilding()
    if building == nil then return false end
    if SafeHouse and type(SafeHouse.isSafeHouse) == "function"
            and SafeHouse.isSafeHouse(square, nil, true) ~= nil then return false end
    local locator = ProjectALife.PlayerLocator
    if locator and type(locator.list) == "function" then
        for _, player in ipairs(locator.list()) do
            if type(player.getBuilding) == "function" and player:getBuilding() == building then return false end
        end
    end
    local builder = ProjectALife.OutpostBuilder
    local probe = builder and builder.probeBuilding(building)
    if probe == nil then return false end
    local changed = 0

    local openings = probe.windows()
    if message.kind == "board" and type(probe.doors) == "function" then
        openings = {}
        for _, list in ipairs({ probe.windows(), probe.doors() }) do
            for _, opening in ipairs(list) do openings[#openings + 1] = opening end
        end
    end
    local mx, my, mz = math.floor(message.x), math.floor(message.y), math.floor(message.z)
    for _, opening in ipairs(openings) do
        if message.kind == "sheets" then
            if changed >= 16 then break end

            local life = ProjectALife.ModuleIdleLife
            local cover = life == nil or type(life.coverable) ~= "function"
                or life.coverable(life.outsideFacts(opening, nil, nil))
            if cover then
                local ready, done = builder.closeSheet(opening.object)
                if ready and done then changed = changed + 1 end
            end
        elseif opening.z == mz and opening.object ~= nil
                and ((opening.x == mx and opening.y == my) or (opening.objectX == mx and opening.objectY == my)) then
            if opening.object:isBarricaded() then return true end
            if IsoBarricade == nil or type(IsoBarricade.AddBarricadeToObject) ~= "function" then return false end

            local planks = ProjectALife.Planks
            local packs = Campfires.boardPacks(shell, message.uid)
            if planks == nil or planks.held(packs) <= 0 then return false end
            local barricade = IsoBarricade.AddBarricadeToObject(opening.object, shell)
            if barricade == nil then return false end
            local heat = ProjectALife.BaseHeat
            if heat ~= nil and type(heat.stampNpcBarricade) == "function" then heat.stampNpcBarricade(barricade) end
            local wanted = math.max(1, math.min(planks.perOpeningMax, math.floor(tonumber(message.planks) or 1)))
            for _ = 1, planks.take(packs, wanted) do barricade:addPlank(nil, nil) end
            barricade:transmitCompleteItemToClients()
            return true
        end
    end
    if message.kind == "sheets" then
        local registry = ProjectALife.ActorRegistry
        local actor = registry and message.uid and registry.read(message.uid)
        if actor and type(registry.list) == "function" then
            local group = actor.memory and actor.memory.groupId
            local sentry = Campfires.sentryOf(registry, actor)
            for _, record in ipairs(registry.list()) do
                if record.lifecycle ~= "dead" and (record.uid == actor.uid
                        or (group and record.memory and record.memory.groupId == group)) then
                    registry.update(record.uid, record.revision, function(fresh)
                        local m, task = fresh.memory, actor.memory.offlineTask or {}
                        m.stance = "shelter"
                        m.stanceAnchor = { x = shell:getX(), y = shell:getY(), z = shell:getZ() }
                        m.stanceSentry = record.uid == sentry
                        m.stanceAwareness = ProjectALife.Awareness.forRole("houseNight", m)
                        m.shelterBuildingId = tostring(building:getID())
                        m.shelterManagedByLife = true
                        m.shelterUntilHours = task.kind == "fortify" and task.untilHours or nil
                    end)
                end
            end
        end
        return true
    end
    return false
end

function Campfires.light(key, x, y, z, minutes, actor)
    if type(key) ~= "string" or key == "" then return refuse("no_key") end
    x, y, z = math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0), math.floor(tonumber(z) or 0)
    minutes = math.max(10, math.floor(tonumber(minutes) or Campfires.settings.fuelMinutes))
    if clientOnly() then
        if relay({ op = "light", key = key, x = x, y = y, z = z, minutes = minutes,
                uid = actor and actor.uid, generation = actor and actor.generation }) then return true, "relayed" end
        return refuse("relay_unavailable")
    end
    Campfires.bindStore()
    if Campfires.active[key] ~= nil then return true, "already_lit" end
    if Campfires.count() >= Campfires.settings.maxActive then return refuse("too_many") end
    local fires = system()
    if fires == nil then return refuse("no_system") end
    local square
    pcall(function() square = getCell():getGridSquare(x, y, z) end)
    if square == nil then return refuse("square_unloaded") end
    if (type(square.isOutside) == "function" and square:isOutside() ~= true)
            or (type(square.getBuilding) == "function" and square:getBuilding() ~= nil)
            or (type(square.isFree) == "function" and square:isFree(true) ~= true) then return refuse("unsafe_square") end
    local fire
    local ok = pcall(function()
        fire = fires:addCampfire(square)
        if fire == nil and type(fires.getLuaObjectOnSquare) == "function" then
            fire = fires:getLuaObjectOnSquare(square)
        end
    end)
    if not ok or fire == nil then return refuse("no_campfire") end
    local lit = pcall(function()
        fire:addFuel(minutes)
        fire:lightFire()
        if type(fire.saveData) == "function" then fire:saveData() end
    end)
    if not lit then return refuse("light_failed") end
    Campfires.active[key] = { x = x, y = y, z = z, litAtMs = nowMs() }
    Campfires.metrics.lit = Campfires.metrics.lit + 1
    return true, "lit"
end

function Campfires.douse(key, actor)
    if type(key) ~= "string" then return refuse("no_key") end
    if clientOnly() then
        if relay({ op = "douse", key = key, uid = actor and actor.uid,
                generation = actor and actor.generation }) then return true, "relayed" end
        return refuse("relay_unavailable")
    end
    Campfires.bindStore()
    local entry = Campfires.active[key]
    if entry == nil then return false, "not_lit" end
    Campfires.active[key] = nil
    local fires = system()
    if fires == nil then return refuse("no_system") end
    pcall(function()
        local fire = fires:getLuaObjectAt(entry.x, entry.y, entry.z)
        if fire == nil then return end
        pcall(function() fire:putOut() end)

        fires:removeCampfire(fire)
    end)
    Campfires.metrics.doused = Campfires.metrics.doused + 1
    return true, "doused"
end

function Campfires.senderNear(player, x, y, radius)
    if player == nil or tonumber(x) == nil or tonumber(y) == nil then return false end
    local near = false
    pcall(function()
        local dx, dy = player:getX() - tonumber(x), player:getY() - tonumber(y)
        near = dx * dx + dy * dy <= radius * radius
    end)
    return near
end

local function remoteRefuse(reason)
    Campfires.metrics.remoteRejected = Campfires.metrics.remoteRejected + 1
    return false, reason
end

function Campfires.actorFor(player, message)
    if type(Campfires.adapters.actorFor) == "function" then return Campfires.adapters.actorFor(player, message) end
    if type(message.uid) ~= "string" or type(message.generation) ~= "number" then return nil end
    local registry, watchdog = ProjectALife.ActorRegistry, ProjectALife.Watchdog
    local record = registry and registry.read(message.uid)
    local binding = watchdog and watchdog.bindings and watchdog.bindings[message.uid]
    if record == nil or record.lifecycle ~= "active" or record.generation ~= message.generation
            or binding == nil or binding.generation ~= message.generation or binding.shell == nil then return nil end
    local shell = binding.shell
    if type(shell.getOwnerPlayer) ~= "function" or shell:getOwnerPlayer() ~= player or shell:isDead() then return nil end
    local key = "camp:" .. tostring(record.memory and record.memory.groupId or record.uid)
    if message.key ~= key then return nil end
    return record, shell
end

function Campfires.sentryOf(registry, actor)
    local group = actor.memory and actor.memory.groupId
    local members = {}
    for _, record in ipairs(registry.list()) do
        local memory = record.memory or {}
        if record.uid == actor.uid or (group and memory.groupId == group) then
            members[#members + 1] = { uid = record.uid, groupIndex = memory.groupIndex, dead = record.lifecycle == "dead" }
        end
    end
    local awareness = ProjectALife.Awareness
    return awareness and awareness.sentryOf(members) or nil
end

function Campfires.setGroupCamp(actor, anchor, key, camping)
    local registry = ProjectALife.ActorRegistry
    if not registry or type(registry.list) ~= "function" or actor == nil then return end
    local group = actor.memory and actor.memory.groupId
    local sentry = camping and Campfires.sentryOf(registry, actor) or nil
    for _, record in ipairs(registry.list()) do
        local memory = record.memory or {}
        if record.lifecycle ~= "dead" and (record.uid == actor.uid or (group and memory.groupId == group)) then
            registry.update(record.uid, record.revision, function(fresh)
                local m = fresh.memory
                if camping then
                    if m.nightCamp ~= true then
                        m.nightCampRestore = { stance = m.stance, stanceAnchor = m.stanceAnchor,
                            stanceAwareness = m.stanceAwareness, stancePost = m.stancePost, stancePhase = m.stancePhase,
                            stanceSentry = m.stanceSentry }
                    end
                    m.stanceSentry = record.uid == sentry
                    m.stance, m.stanceAnchor, m.stanceAwareness = "camp", anchor, ProjectALife.Awareness.forRole("asleep", m)
                    m.stancePost, m.stancePhase = nil, nil
                    m.nightCamp, m.nightCampKey = true, key
                elseif m.nightCampKey == key then
                    local old = m.nightCampRestore or {}
                    m.stance, m.stanceAnchor, m.stanceAwareness = old.stance or "", old.stanceAnchor, old.stanceAwareness
                    m.stanceSentry = old.stanceSentry
                    m.stancePost, m.stancePhase = old.stancePost, old.stancePhase
                    m.nightCamp, m.nightCampKey, m.nightCampRestore = nil, nil, nil
                end
            end)
        end
    end
end

function Campfires.onCommand(player, message)
    if type(message) ~= "table" or type(message.key) ~= "string" then return false, "invalid" end
    if message.op == "light" then
        for _, name in ipairs({ "x", "y", "z" }) do
            local value = message[name]
            if type(value) ~= "number" or value ~= value or math.abs(value) > 1000000 then return remoteRefuse("invalid_position") end
        end
        if message.minutes ~= nil and (type(message.minutes) ~= "number"
                or message.minutes ~= message.minutes or math.abs(message.minutes) == math.huge) then return remoteRefuse("invalid_fuel") end
    end

    if string.match(message.key, "^camp:[%w_%-:%.]+$") == nil then return remoteRefuse("bad_key") end
    local who = "?"
    pcall(function() who = tostring(player:getUsername() or player:getOnlineID()) end)
    local now, last = nowMs(), Campfires.senderAtMs[who]
    if last ~= nil and now - last < Campfires.settings.perSenderMs then return remoteRefuse("rate_limited") end
    Campfires.senderAtMs[who] = now
    local radius = Campfires.settings.senderRadius
    if message.op == "light" then
        if not Campfires.senderNear(player, message.x, message.y, radius) then return remoteRefuse("sender_far") end
    elseif message.op == "douse" then
        Campfires.bindStore()
        local entry = Campfires.active[message.key]
        if entry ~= nil and not Campfires.senderNear(player, entry.x, entry.y, radius) then
            return remoteRefuse("sender_far")
        end
    end
    local actor, shell = Campfires.actorFor(player, message)
    if actor == nil then return remoteRefuse("not_owner") end
    if message.op == "light" and shell ~= nil then
        if type(message.z) ~= "number" or math.abs(shell:getZ() - message.z) > 0.5
                or (shell:getX() - message.x)^2 + (shell:getY() - message.y)^2 > 100 then
            return remoteRefuse("actor_far")
        end
    end
    Campfires.metrics.remote = Campfires.metrics.remote + 1
    if message.op == "light" then

        local ok, reason = Campfires.light(message.key, message.x, message.y, message.z,
            math.min(Campfires.settings.fuelMinutes * 2, tonumber(message.minutes) or Campfires.settings.fuelMinutes))
        if ok then
            local held = Campfires.active[message.key]
            if held then Campfires.setGroupCamp(actor, { x = held.x + 0.5, y = held.y + 0.5, z = held.z }, message.key, true) end
        end
        return ok, reason
    elseif message.op == "douse" then
        local ok, reason = Campfires.douse(message.key)
        Campfires.setGroupCamp(actor, nil, message.key, false)
        return ok, reason
    end
    return false, "unknown_op"
end

function Campfires.reset()
    for shell in pairs(Campfires.protected) do Campfires.releaseProtection(shell) end
    Campfires.protected = setmetatable({}, { __mode = "k" })
    Campfires.nearby = setmetatable({}, { __mode = "k" })
    Campfires.nearbyCount = 0
    Campfires.active = {}
    Campfires.storeBound = false
    Campfires.senderAtMs = {}
    Campfires.metrics = { lit = 0, doused = 0, refused = 0, relayed = 0, remote = 0, remoteRejected = 0 }
    return true
end

if Events ~= nil and Events.OnTick ~= nil then Events.OnTick.Add(Campfires.finishTick) end

return Campfires
