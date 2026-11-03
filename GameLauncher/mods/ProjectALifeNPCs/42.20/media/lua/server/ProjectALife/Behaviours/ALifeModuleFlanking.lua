require "ProjectALife/Behaviours/ALifeModuleRegistry"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry

local Flanking = {
    enabled = true,

    distance = 1.75,

    minimumRange = 5,

    lanes = { 0, -1, 1, -1.5, 1.5, -2, 2 },

    contactBand = 2.5,

    wingScale = 2.0,
}
ProjectALife.ModuleFlanking = Flanking

function Flanking.configure(options)
    options = type(options) == "table" and options or {}
    if options.enabled ~= nil then Flanking.enabled = options.enabled == true end
    local distance = tonumber(options.distance)
    if distance ~= nil and distance > 0 then Flanking.distance = distance end
    local minimum = tonumber(options.minimumRange)
    if minimum ~= nil then Flanking.minimumRange = math.max(2, minimum) end
    return true
end

function Flanking.active(actor)
    return Flanking.enabled and Registry.allows(actor, "flanking")
end

local function laneIndex(actor)
    local index = tonumber(actor.memory and actor.memory.groupIndex)

    if index ~= nil then return math.max(0, math.floor(index) - 1) end
    local seed, uid = 0, tostring(actor.uid or "")
    for position = 1, #uid do
        seed = (seed * 31 + string.byte(uid, position)) % 4093
    end
    return seed
end

Flanking.laneIndex = laneIndex

Flanking.wings = {}
function Flanking.wingFor(actor)
    local held = Flanking.wings[actor.uid]
    if held ~= nil then return held end

    local lanes = Flanking.lanes
    local lane = (lanes[(laneIndex(actor) % #lanes) + 1] or 0) * Flanking.distance
    local wing = lane * Flanking.wingScale
    Flanking.wings[actor.uid] = wing
    return wing
end

function Flanking.clearWing(actorUid)
    Flanking.wings[actorUid] = nil
end

function Flanking.offset(actor, distance)
    if type(actor) ~= "table" or not Flanking.active(actor) then return 0 end
    distance = tonumber(distance) or 0

    if distance <= Flanking.contactBand then return 0 end

    if distance > 12 then
        local wing = Flanking.wingFor(actor)
        local blend = math.min(1, (distance - 12) / 4)
        local lane = (Flanking.lanes[(laneIndex(actor) % #Flanking.lanes) + 1]
            or 0) * Flanking.distance
        return lane + (wing - lane) * blend
    end
    local lanes = Flanking.lanes
    local lane = lanes[(laneIndex(actor) % #lanes) + 1] or 0
    if lane == 0 then return 0 end

    local span = math.max(0.1, Flanking.minimumRange - Flanking.contactBand)
    local taper = math.max(0, math.min(1,
        (distance - Flanking.contactBand) / span))
    return lane * Flanking.distance * taper
end

Registry.register({
    id = "flanking",
    kind = "craft",
    label = "Ranged flanking",
    summary = "Gives ranged actors stable approach lanes and wider wings at long range.",
    defaultEnabled = true,
    evaluate = function() return nil end,
})

return Flanking
