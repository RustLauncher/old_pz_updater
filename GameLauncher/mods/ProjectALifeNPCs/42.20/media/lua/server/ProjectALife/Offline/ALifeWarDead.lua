require "ProjectALife/Compat/ALifeFeatureGate"
require "ProjectALife/Shells/ALifeCorpseDresser"

ProjectALife = ProjectALife or {}

local Gate = ProjectALife.FeatureGate

local WarDead = {
    id = "war_dead",
    KEY = "ProjectALife.WarDead",
    playerClear = 40, loadedRadius = 110, scatter = 5, maxPending = 60, forgetHours = 24 * 14,
    ready = false, store = nil,
    metrics = { died = 0, placed = 0, forgotten = 0, skippedBase = 0 },
}
ProjectALife.WarDead = WarDead

function WarDead.active()
    return WarDead.ready and Gate.authority() and Gate.on(WarDead.id, "WarDead_Enabled", true)
end

function WarDead.data()
    if WarDead.store ~= nil then return WarDead.store end
    if ModData == nil or type(ModData.getOrCreate) ~= "function" then return nil end
    local data = ModData.getOrCreate(WarDead.KEY)
    data.pending = type(data.pending) == "table" and data.pending or {}
    data.sequence = tonumber(data.sequence) or 0
    WarDead.store = data
    return data
end

function WarDead.onInit()
    WarDead.ready = true
    WarDead.store = nil
end

function WarDead.record(squad, lost, x, y, hours)
    if type(squad) ~= "table" or type(lost) ~= "table" or #lost == 0 or not WarDead.active() then return 0 end
    local data = WarDead.data()
    if data == nil then return 0 end
    local cx, cy = tonumber(x) or tonumber(squad.x) or 0, tonumber(y) or tonumber(squad.y) or 0
    for _, member in ipairs(lost) do
        data.sequence = data.sequence + 1
        local key = tostring(squad.id) .. ":" .. data.sequence
        local angle, reach = Gate.hash01(key .. ":a") * math.pi * 2, 1 + Gate.hash01(key .. ":r") * WarDead.scatter
        data.pending[#data.pending + 1] = {
            x = math.floor(cx + math.cos(angle) * reach), y = math.floor(cy + math.sin(angle) * reach),
            factionId = squad.factionId, profileId = type(member) == "table" and member.profileId or nil,
            identitySeed = type(member) == "table" and member.identitySeed or key, hours = tonumber(hours) or Gate.worldHours(),
        }
        WarDead.metrics.died = WarDead.metrics.died + 1
    end
    while #data.pending > WarDead.maxPending do
        table.remove(data.pending, 1)
        WarDead.metrics.forgotten = WarDead.metrics.forgotten + 1
    end
    return #lost
end

function WarDead.inBase(x, y)
    local policy = ProjectALife.SpawnPolicy
    if policy == nil or type(policy.inPlayerBase) ~= "function" then return false end
    local ok, yes = pcall(policy.inPlayerBase, { x = x, y = y, z = 0 })
    return ok and yes == true
end

function WarDead.groundNear(x, y)
    local cell = getCell()
    if cell == nil then return nil end
    for ring = 0, 3 do
        for dx = -ring, ring do
            for dy = -ring, ring do
                if math.max(math.abs(dx), math.abs(dy)) == ring then
                    local square = cell:getGridSquare(x + dx, y + dy, 0)
                    if square ~= nil and square:isFree(false) then return square end
                end
            end
        end
    end
    return nil
end

function WarDead.place(dead)
    if WarDead.inBase(dead.x, dead.y) then
        WarDead.metrics.skippedBase = WarDead.metrics.skippedBase + 1
        return true
    end
    local square = WarDead.groundNear(dead.x, dead.y)
    local dresser = ProjectALife.CorpseDresser
    if square == nil or dresser == nil then return false end
    local body = dresser.plain(square, 8)
    if body == nil then return false end
    dresser.dress(body, dead.factionId, dead.identitySeed, dead.profileId)
    dresser.blood(square, 6)
    WarDead.metrics.placed = WarDead.metrics.placed + 1
    return true
end

function WarDead.tick(hours)
    if not WarDead.active() then return 0 end
    local data = WarDead.data()
    if data == nil or #data.pending == 0 then return 0 end
    hours = tonumber(hours) or Gate.worldHours()
    local points = Gate.playerPoints()
    local keep, placed = {}, 0
    for _, dead in ipairs(data.pending) do
        local done = false
        if hours - (tonumber(dead.hours) or hours) > WarDead.forgetHours then
            done = true
            WarDead.metrics.forgotten = WarDead.metrics.forgotten + 1
        else
            local d = Gate.nearestPlayer(dead.x, dead.y, points)
            if d >= WarDead.playerClear and d <= WarDead.loadedRadius then
                local ok, result = pcall(WarDead.place, dead)
                done = ok and result == true
                if done then placed = placed + 1 end
            end
        end
        if not done then keep[#keep + 1] = dead end
    end
    data.pending = keep
    return placed
end

if type(Events) == "table" then
    if Events.OnInitGlobalModData ~= nil then Events.OnInitGlobalModData.Add(WarDead.onInit) end
    if Events.EveryTenMinutes ~= nil then
        Events.EveryTenMinutes.Add(function() pcall(WarDead.tick, Gate.worldHours()) end)
    end
end

return WarDead
