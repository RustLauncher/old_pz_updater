CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

---@param player IsoPlayer
---@param n number how much unhappiness and boredom to remove
function CD.relieveMood(player, n)
    if not player or not n or n <= 0 then return end
    local stats = player:getStats()
    stats:remove(CharacterStat.UNHAPPINESS, n)
    stats:remove(CharacterStat.BOREDOM, n)
end

-- Saldo relativo, nunca prazo absoluto contra worldMinutes(): o relogio do client de MP recua 24h
-- todo dia as 7h, ate chegar o SyncClockPacket.
---@param player IsoPlayer|nil
function CD.startRestedBuff(player)
    if not player then return end
    local pd = CD.playerData(player)
    pd.restedLeftMin = CD.restedBuffDurationMin()
    pd.restedUntilMin = nil
end

---@param player IsoPlayer|nil
---@return number minutes left, capped at the configured duration; 0 without the buff
---@nodiscard
function CD.restedBuffLeftMin(player)
    if not player then return 0 end
    local pd = CD.playerData(player)
    local left = pd and pd.restedLeftMin
    if type(left) ~= "number" or left <= 0 then return 0 end
    local max = CD.restedBuffDurationMin()
    return left > max and max or left
end

---Spends elapsedMin of the buff, easing panic, stress, fatigue and mood in proportion.
---@param player IsoPlayer|nil
---@param elapsedMin number|nil game minutes
function CD.applyRestedBuff(player, elapsedMin)
    if not player or not elapsedMin or elapsedMin <= 0 then return end
    local left = CD.restedBuffLeftMin(player)
    local pd = CD.playerData(player)
    if left <= 0 then
        pd.restedLeftMin = nil
        return
    end
    if elapsedMin > left then
        elapsedMin = left
    end
    left = left - elapsedMin
    pd.restedLeftMin = left > 0 and left or nil
    local s = player:getStats()
    s:remove(CharacterStat.PANIC, CD.RESTED_PANIC_PER_MIN * elapsedMin)
    s:remove(CharacterStat.STRESS, CD.RESTED_STRESS_PER_MIN * elapsedMin)
    s:remove(CharacterStat.FATIGUE, CD.RESTED_FATIGUE_PER_MIN * elapsedMin)
    CD.relieveMood(player, CD.RESTED_MOOD_PER_MIN * elapsedMin)
end

local function unhappyDelta(player, amount, subtract)
    local moved = 0
    if player then
        local s = player:getStats()
        local before = s:get(CharacterStat.UNHAPPINESS)
        if subtract then s:remove(CharacterStat.UNHAPPINESS, amount)
        else s:add(CharacterStat.UNHAPPINESS, amount) end
        local after = s:get(CharacterStat.UNHAPPINESS)
        moved = after - before
        if moved < 0 then
            moved = -moved
        end
    end
    return moved
end

---Starts the grief, or extends the running one: the larger shock and the longer duration win.
---@param player IsoPlayer|nil
---@param shock number|nil unhappiness at the start, fading to 0
---@param mins number|nil duration in game minutes
---@param name string|nil name of the dead dog
function CD.startGrief(player, shock, mins, name)
    if not player or not shock or not mins or mins <= 0 then return end
    local pd = CD.playerData(player)
    local g = type(pd.grief) == "table" and pd.grief or nil
    local left = (g and g.left) or 0
    local total = (g and g.total) or 0
    local prevShock = (g and g.shock) or 0
    if shock < prevShock then
        shock = prevShock
    end
    if mins < left then
        mins = left
    end
    if mins < total then
        mins = total
    end
    pd.grief = {
        shock = shock,
        total = mins,
        left = mins,
        applied = (g and g.applied) or 0,
        sinceSync = 0,
        name = name,
    }
    player:transmitModData()
end

---@param player IsoPlayer|nil
---@return number minutes left, capped at the total; 0 without grief
---@nodiscard
function CD.griefLeftMin(player)
    if not player then return 0 end
    local pd = CD.playerData(player)
    local g = pd and pd.grief
    if type(g) ~= "table" then return 0 end
    local left, total = g.left, g.total
    if type(left) ~= "number" or type(total) ~= "number" or left <= 0 or total <= 0 then return 0 end
    return left > total and total or left
end

---@param player IsoPlayer|nil
---@return string|nil name of the dog being mourned
---@nodiscard
function CD.griefName(player)
    local pd = player and CD.playerData(player)
    local g = pd and pd.grief
    return (type(g) == "table" and type(g.name) == "string") and g.name or nil
end

---Takes back the unhappiness the grief added, then clears it.
---@param player IsoPlayer|nil
function CD.endGrief(player)
    if not player then return end
    local pd = CD.playerData(player)
    local g = pd.grief
    if type(g) == "table" then
        local applied = g.applied or 0
        if applied > 0 then
            unhappyDelta(player, applied, true)
        end
    end
    pd.grief = nil
end

---Counts the grief down and moves unhappiness toward its fading target; syncs the server every CD.griefSyncMin() minutes.
---@param player IsoPlayer|nil
---@param elapsedMin number|nil game minutes since the last call
function CD.applyGrief(player, elapsedMin)
    if not player then return end
    local pd = CD.playerData(player)
    local g = pd.grief
    if type(g) ~= "table" then return end
    local total = g.total or 0
    local left = g.left or 0
    if total <= 0 or left <= 0 then
        CD.endGrief(player)
        CD.syncGrief(player, 0, 0)
        return
    end
    if elapsedMin and elapsedMin > 0 then
        left = left - elapsedMin
        if left < 0 then
            left = 0
        end
        g.left = left
        g.sinceSync = (g.sinceSync or 0) + elapsedMin
    end
    local target = (g.shock or 0) * (left / total)
    local applied = g.applied or 0
    if applied < target then
        g.applied = applied + unhappyDelta(player, target - applied, false)
    elseif applied > target then
        g.applied = applied - unhappyDelta(player, applied - target, true)
    end
    if left <= 0 then
        pd.grief = nil
        CD.syncGrief(player, 0, 0)
    elseif (g.sinceSync or 0) >= CD.griefSyncMin() then
        g.sinceSync = 0
        CD.syncGrief(player, left, g.applied)
    end
end

---Sends the grief countdown to the server; left 0 ends the grief there.
---@param player IsoPlayer|nil
---@param left number|nil minutes left
---@param applied number|nil unhappiness applied so far
function CD.syncGrief(player, left, applied)
    if not player then return end
    CD.request("griefsync", nil, { left = left or 0, applied = applied or 0 }, player)
end
