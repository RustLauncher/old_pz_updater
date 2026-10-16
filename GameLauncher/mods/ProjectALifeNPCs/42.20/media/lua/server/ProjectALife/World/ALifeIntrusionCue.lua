require "ProjectALife/Audio/ALifeInteractionCues"

ProjectALife = ProjectALife or {}
local Intrusion = { quietMs = 600000, cap = 32, rooms = {}, adapters = {} }
Intrusion.metrics = { opened = 0, played = 0, quiet = 0, notInterior = 0, notNpc = 0, notHostile = 0, unheard = 0, off = 0 }
ProjectALife.IntrusionCue = Intrusion

function Intrusion.reset()
    Intrusion.rooms = {}
    Intrusion.metrics = { opened = 0, played = 0, quiet = 0, notInterior = 0, notNpc = 0, notHostile = 0, unheard = 0, off = 0 }
end

function Intrusion.millis()
    if type(Intrusion.adapters.nowMs) == "function" then return Intrusion.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return nil
end

function Intrusion.enabled()
    local director = ProjectALife.SafehouseDirector
    if director == nil or type(director.settings) ~= "table" then return true end
    return director.settings.knockSounds == true
end

function Intrusion.sides(object)
    if object == nil or type(object.getSquare) ~= "function" or type(object.getOppositeSquare) ~= "function" then return nil end
    local here, there = object:getSquare(), object:getOppositeSquare()
    if here == nil or there == nil or type(here.getBuilding) ~= "function" or type(there.getBuilding) ~= "function" then return nil end
    local inside, other = here:getBuilding(), there:getBuilding()
    if inside == nil or inside ~= other then return nil end
    return inside, here
end

function Intrusion.target(actor, door, building)
    local fair, relations = ProjectALife.Fairness, ProjectALife.Relations
    if fair == nil or type(fair.playersNear) ~= "function" or relations == nil or type(relations.hostileToPlayer) ~= "function" then
        return nil
    end
    local x, y, z = door:getX(), door:getY(), door:getZ()
    for _, seen in ipairs(fair.playersNear(x, y, z, building)) do
        if relations.hostileToPlayer(actor, seen.player) == true then return seen.player end
    end
    return nil
end

function Intrusion.prune(now)
    local count = 0
    for key, row in pairs(Intrusion.rooms) do
        if now - row.lastMs >= Intrusion.quietMs then Intrusion.rooms[key] = nil else count = count + 1 end
    end
    if count >= Intrusion.cap then Intrusion.rooms = {} end
end

function Intrusion.doorOpened(shell, object, square)
    local metrics = Intrusion.metrics
    metrics.opened = metrics.opened + 1
    if not Intrusion.enabled() then metrics.off = metrics.off + 1; return false, "off" end
    local building, door = Intrusion.sides(object)
    if building == nil then metrics.notInterior = metrics.notInterior + 1; return false, "not_interior" end
    local fair, cues = ProjectALife.Fairness, ProjectALife.InteractionCues
    if fair == nil or type(fair.actorOfShell) ~= "function" or cues == nil or type(cues.pick) ~= "function"
            or type(cues.playAt) ~= "function" then return false, "unavailable" end
    local actor = fair.actorOfShell(shell)
    if actor == nil then metrics.notNpc = metrics.notNpc + 1; return false, "not_npc" end
    local inside = shell ~= nil and type(shell.getCurrentSquare) == "function" and shell:getCurrentSquare() or square
    if inside == nil or type(inside.getBuilding) ~= "function" or inside:getBuilding() ~= building then
        metrics.notInterior = metrics.notInterior + 1
        return false, "not_inside"
    end
    if Intrusion.target(actor, door, building) == nil then metrics.notHostile = metrics.notHostile + 1; return false, "not_hostile" end
    local now = Intrusion.millis()
    if now == nil then return false, "clock_unavailable" end
    local key = tostring(building)
    local row = Intrusion.rooms[key]
    if row ~= nil and now - row.lastMs < Intrusion.quietMs then
        row.lastMs = now
        metrics.quiet = metrics.quiet + 1
        return false, "same_intrusion"
    end
    local id = cues.pick("door_opened", actor.uid)
    if id == nil then return false, "no_cue" end
    local played = cues.playAt(door, id)
    if played ~= true then metrics.unheard = metrics.unheard + 1; return false, "unheard" end
    Intrusion.prune(now)
    Intrusion.rooms[key] = { lastMs = now }
    metrics.played = metrics.played + 1
    return true, id
end

return Intrusion
