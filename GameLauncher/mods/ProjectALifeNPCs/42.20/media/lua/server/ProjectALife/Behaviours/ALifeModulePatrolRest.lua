require "ProjectALife/Behaviours/ALifeModuleRegistry"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry

local Rest = {
    id = "patrolRest",
    settings = {
        enabled = true,

        minMinutes = 20,
        maxMinutes = 45,

        everyHours = 3,

        afterFightMs = 45000,

        beatMinimumMs = 7000,
        beatSpreadMs = 8000,

        ring = 1.7,
        spotRadius = 7,

        modes = { patrol = true, roam = true, hunt = true },
    },
    adapters = {},

    groups = {},

    lastRestHours = {},

    restedAfter = {},
    metrics = { rests = 0, beats = 0, ended = 0, refused = 0, gossips = 0 },
}
ProjectALife.ModulePatrolRest = Rest

local function nowMs()
    if type(Rest.adapters.nowMs) == "function" then return Rest.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function worldHours()
    if type(Rest.adapters.worldHours) == "function" then return Rest.adapters.worldHours() end
    local hours = 0
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    return hours
end

local function memoryOf(actor)
    return type(actor) == "table" and type(actor.memory) == "table" and actor.memory or {}
end

local function positionOf(shell)
    local ok, x, y, z = pcall(function() return shell:getX(), shell:getY(), shell:getZ() end)
    if not ok then return nil end
    return { x = x, y = y, z = z }
end

local function seedOf(key)
    local id = tostring(key or "")
    local seed = 0
    for index = 1, #id do
        seed = (seed * 31 + string.byte(id, index)) % 2147483647
    end
    return (seed % 1000) / 1000
end

function Rest.configure(adapters)
    Rest.adapters = adapters or {}
    local s = Rest.settings
    local a = Rest.adapters
    if a.enabled ~= nil then s.enabled = a.enabled ~= false end
    if a.minMinutes ~= nil then s.minMinutes = math.max(5, math.min(180, tonumber(a.minMinutes) or 20)) end
    if a.maxMinutes ~= nil then s.maxMinutes = math.max(s.minMinutes, math.min(240, tonumber(a.maxMinutes) or 45)) end
    if a.everyHours ~= nil then s.everyHours = math.max(0.5, math.min(48, tonumber(a.everyHours) or 3)) end
    return true
end

function Rest.reset()
    Rest.groups = {}
    Rest.lastRestHours = {}
    Rest.restedAfter = {}
    return true
end

function Rest.due(sinceRestHours, sinceContactMs, restedSinceContact, seed, settings)
    settings = settings or Rest.settings
    if settings.enabled == false then return false, "disabled" end
    if sinceRestHours == nil then return false, "no_clock" end
    local after = tonumber(settings.afterFightMs) or 45000
    if sinceContactMs ~= nil and sinceContactMs < after then return false, "fight_fresh" end
    if sinceContactMs ~= nil and not restedSinceContact and sinceContactMs < after * 4 then
        return true, "after_fight"
    end
    local every = (tonumber(settings.everyHours) or 3) * (1 + 0.4 * (tonumber(seed) or 0))
    if sinceRestHours == nil or sinceRestHours >= every then return true, "scheduled" end
    return false, "not_yet"
end

function Rest.lengthHours(seed, settings)
    settings = settings or Rest.settings
    local minimum = tonumber(settings.minMinutes) or 20
    local maximum = math.max(minimum, tonumber(settings.maxMinutes) or 45)
    return (minimum + (maximum - minimum) * (tonumber(seed) or 0)) / 60
end

function Rest.slotFor(index, size, spot, ring)
    local count = math.max(1, math.floor(tonumber(size) or 1))
    local slot = (math.floor(tonumber(index) or 1) - 1) % count
    local angle = slot * (2 * math.pi / count)
    local radius = tonumber(ring) or Rest.settings.ring
    if count == 1 then radius = 0 end
    return {
        x = spot.x + math.cos(angle) * radius,
        y = spot.y + math.sin(angle) * radius,
        z = spot.z or 0,
    }
end

function Rest.activityFor(index, beat)
    local slot = (math.floor(tonumber(index) or 1) - 1) % 4
    if slot == 0 then return "sit_ground" end
    if slot == 1 then return "smoke" end
    return ((math.floor(tonumber(beat) or 0) % 3) == 2) and "eat" or "drink"
end

local RINGS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
                { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }

local function spotUsable(square)
    local ok = false
    pcall(function()
        if square == nil then return end
        if square:isOutside() ~= true then return end
        if square:isFree(false) ~= true then return end
        local road = ProjectALife.Road
        if road ~= nil and type(road.isRoadSquare) == "function" and road.isRoadSquare(square) then return end
        ok = true
    end)
    return ok
end

local function pickSpot(shell)
    if type(Rest.adapters.pickSpot) == "function" then return Rest.adapters.pickSpot(shell) end
    local here = positionOf(shell)
    if here == nil then return nil end
    local ox, oy, oz = math.floor(here.x), math.floor(here.y), math.floor(here.z)
    local cell
    pcall(function() cell = getCell() end)
    if cell == nil then return nil end
    for ring = 2, Rest.settings.spotRadius do
        for _, step in ipairs(RINGS) do
            local square
            pcall(function() square = cell:getGridSquare(ox + step[1] * ring, oy + step[2] * ring, oz) end)
            if spotUsable(square) then
                return { x = ox + step[1] * ring + 0.5, y = oy + step[2] * ring + 0.5, z = oz }
            end
        end
    end
    return nil
end

local function groupKeyOf(actor)
    local memory = memoryOf(actor)
    if type(memory.groupId) == "string" then return memory.groupId end
    return "solo:" .. tostring(actor and actor.uid or "?")
end

local function isLeader(actor)
    local memory = memoryOf(actor)
    if type(memory.groupId) ~= "string" then return true end
    return memory.groupRole == "leader"
end

local function lastContactMs(groupId)
    local at
    pcall(function()
        local tactics = ProjectALife.SquadTactics
        local held = tactics ~= nil and type(tactics.contacts) == "table" and tactics.contacts[groupId] or nil
        if type(held) == "table" then at = tonumber(held.atMs) end
    end)
    return at
end

local function say(shell, event, options)
    pcall(function()
        local voice = ProjectALife.Voice
        if voice ~= nil and type(voice.play) == "function" then voice.play(shell, event, options) end
    end)
end

local function pose(shell, id)
    pcall(function()
        local animations = ProjectALife.Animations
        if animations ~= nil then animations.apply(shell, id) end
    end)
end

local function clearPose(shell)
    pcall(function()
        local animations = ProjectALife.Animations
        if animations ~= nil then animations.clear(shell) end
    end)
end

local function face(shell, spot)
    pcall(function() shell:faceLocationF(spot.x, spot.y) end)
end

local function endRest(groupId, hours, reason)
    local group = Rest.groups[groupId]
    if group == nil then return end
    Rest.groups[groupId] = nil
    Rest.lastRestHours[groupId] = hours
    Rest.metrics.ended = Rest.metrics.ended + 1
    pcall(function()
        local telemetry = ProjectALife.Telemetry
        if telemetry ~= nil then telemetry.emit("patrol_rest_ended", { group = groupId, reason = reason }) end
    end)
end

local function beginRest(actor, shell, groupId, now, hours)
    local cooling = ProjectALife.GroupLife
    if cooling ~= nil and type(cooling.cooling) == "function" and cooling.cooling(groupId, now) then return nil end
    local spot = pickSpot(shell)
    local memory = memoryOf(actor)
    local seed = seedOf(groupId .. ":" .. tostring(math.floor(hours)))
    local group = {
        spot = spot,
        untilHours = hours + Rest.lengthHours(seed),
        startedMs = now,
        startedHours = hours,
        size = math.max(1, math.floor(tonumber(memory.groupSize) or 1)),
        contactAtStart = lastContactMs(groupId),
    }
    local life = ProjectALife.GroupLife
    local sheltered = life ~= nil and type(life.beginRest) == "function"
        and life.beginRest(actor, shell, groupId, now, hours, group) == true
    if spot == nil and not sheltered then
        Rest.metrics.refused = Rest.metrics.refused + 1
        return nil
    end
    Rest.groups[groupId] = group
    Rest.metrics.rests = Rest.metrics.rests + 1
    say(shell, "SQUAD_REST_CALLED")
    pcall(function()
        local telemetry = ProjectALife.Telemetry
        local at = spot or positionOf(shell) or { x = 0, y = 0 }
        if telemetry ~= nil then telemetry.emit("patrol_rest", { group = groupId, x = math.floor(at.x), y = math.floor(at.y) }) end
    end)
    return Rest.groups[groupId]
end

Registry.register({
    id = "patrolRest",
    kind = "upkeep",
    label = "Patrol rest",
    summary = "The squad stops, takes a nearby house or cover and idles with roles: one keeps watch, one sits, two talk, one comments, one stays quiet, others eat or smoke; then the route resumes. With group life off it stands in a circle instead.",
    defaultEnabled = true,
    evaluate = function(actor, shell, context)
        if Rest.settings.enabled == false then return nil end
        if Rest.settings.modes[tostring(context.mode)] ~= true then return nil end
        if not Registry.allows(actor, "patrolRest") then return nil end
        local memory = memoryOf(actor)

        if memory.stance ~= nil and memory.stance ~= "" and memory.stance ~= "route" then return nil end
        local now = tonumber(context.now) or nowMs()
        local hours = worldHours()
        local groupId = groupKeyOf(actor)
        local group = Rest.groups[groupId]
        local leader = isLeader(actor)

        if group == nil then
            if not leader then return nil end
            local last = Rest.lastRestHours[groupId]
            if last == nil then

                Rest.lastRestHours[groupId] = hours
                return nil
            end
            local contactAt = lastContactMs(groupId)
            local sinceContact = contactAt ~= nil and (now - contactAt) or nil
            local restedSince = contactAt ~= nil and Rest.restedAfter[groupId] == contactAt
            local due = Rest.due(hours - last, sinceContact, restedSince, seedOf(groupId), Rest.settings)
            if not due then return nil end
            group = beginRest(actor, shell, groupId, now, hours)
            if group == nil then return nil end
            if contactAt ~= nil then Rest.restedAfter[groupId] = contactAt end
        end

        local contactNow = lastContactMs(groupId)
        local fought = contactNow ~= nil and group.contactAtStart ~= contactNow
        local life = group.life == true and ProjectALife.GroupLife or nil
        if life ~= nil and type(life.restStep) == "function" then
            local handled, state = life.restStep(actor, shell, context, groupId, group, fought)
            if handled then return state end
        end
        if hours >= (tonumber(group.untilHours) or 0) or fought then
            if leader then endRest(groupId, hours, fought and "fight" or "over") end
            if memory.restBeatAtMs ~= nil then
                clearPose(shell)
                context.persistMemory(actor, "restBeatAtMs", nil)
                context.persistMemory(actor, "restBeats", nil)
                say(shell, "REST_END")
            end
            if life ~= nil and type(life.letGo) == "function" then
                local freed = life.letGo(actor, shell, context, now)
                if freed ~= nil then return freed end
            end
            return nil
        end
        if group.life == true then return nil end

        local slot = Rest.slotFor(tonumber(memory.groupIndex) or 1, group.size, group.spot, Rest.settings.ring)
        local here = positionOf(shell)
        if here == nil then return nil end
        local dx, dy = here.x - slot.x, here.y - slot.y
        if dx * dx + dy * dy > 0.9 * 0.9 then
            if memory.restBeatAtMs ~= nil then
                clearPose(shell)
                context.persistMemory(actor, "restBeatAtMs", nil)
            end
            return context.startMovement(actor, shell, slot, "rest", {
                pace = "walk", timeoutMs = 9000, activity = "moving",
            })
        end
        face(shell, group.spot)
        local beatAt = tonumber(memory.restBeatAtMs)
        if beatAt == nil then

            say(shell, "REST_START")
            beatAt = now
        end
        if now >= beatAt then
            local beats = math.floor(tonumber(memory.restBeats) or 0) + 1
            pose(shell, Rest.activityFor(tonumber(memory.groupIndex) or 1, beats))
            Rest.metrics.beats = Rest.metrics.beats + 1
            context.persistMemory(actor, "restBeats", beats)
            context.persistMemory(actor, "restBeatAtMs", now + Rest.settings.beatMinimumMs
                + Rest.settings.beatSpreadMs * seedOf(groupId .. tostring(beats) .. actor.uid))

            if leader then
                pcall(function()
                    local gossip = ProjectALife.Gossip
                    if gossip ~= nil and type(gossip.tryStart) == "function"
                            and type(memory.groupId) == "string" then
                        local ok = gossip.tryStart(shell, { context = "ambient", groupId = memory.groupId, topic = "rest", now = now })
                        if ok then Rest.metrics.gossips = Rest.metrics.gossips + 1 end
                    end
                end)
            elseif beats % 3 == 0 then
                say(shell, (beats % 2 == 0) and "JOKE" or "SAFE_MOMENT")
            end
        end
        context.setActivity(actor, "idle", "patrol_rest")
        return { kind = "idle", intent = "patrol_rest", cooldownUntilMs = now + 2500 }
    end,
})

return Rest
