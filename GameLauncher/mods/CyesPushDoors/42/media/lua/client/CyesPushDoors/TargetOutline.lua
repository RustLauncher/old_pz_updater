require "CyesPushDoors/Core"
require "CyesPushDoors/Settings"

if isServer and isServer() and not (isClient and isClient()) then
    return CyesPushDoors
end

CyesPushDoors = CyesPushDoors or {}
local CPD = CyesPushDoors
local S = CPD.Settings

CPD._impactTargetOutlineByPlayer = CPD._impactTargetOutlineByPlayer or {}
CPD._forcedOpeningOutlineDoors = CPD._forcedOpeningOutlineDoors or {}

local function safeCall(object, methodName, ...)
    if not object then return nil end
    local okLookup, method = pcall(function() return object[methodName] end)
    if not okLookup or type(method) ~= "function" then return nil end
    local ok, result = pcall(method, object, ...)
    if ok then return result end
    return nil
end

local function safeInvoke(object, methodName, ...)
    if not object then return false end
    local okLookup, method = pcall(function() return object[methodName] end)
    if not okLookup or type(method) ~= "function" then return false end
    return pcall(method, object, ...)
end

local function clamp01(value, fallback)
    local number = tonumber(value)
    if number == nil then number = fallback end
    if number > 1.0 and number <= 255.0 then number = number / 255.0 end
    if number < 0.0 then return 0.0 end
    if number > 1.0 then return 1.0 end
    return number
end

local function colorComponent(color, field, getters, fallback)
    if not color then return fallback end
    local ok, value = pcall(function() return color[field] end)
    if ok and value ~= nil then return clamp01(value, fallback) end
    for i = 1, #getters do
        value = safeCall(color, getters[i])
        if value ~= nil then return clamp01(value, fallback) end
    end
    return fallback
end

local function getConfiguredOutlineColor()
    local color = nil
    if S and type(S.impactTargetOutlineColor) == "function" then
        local ok, value = pcall(S.impactTargetOutlineColor)
        if ok then color = value end
    end
    return {
        r = colorComponent(color, "r", { "getR", "getRedFloat", "getRed" }, 0.45),
        g = colorComponent(color, "g", { "getG", "getGreenFloat", "getGreen" }, 1.00),
        b = colorComponent(color, "b", { "getB", "getBlueFloat", "getBlue" }, 0.45),
        a = colorComponent(color, "a", { "getA", "getAlphaFloat", "getAlpha" }, 1.00),
    }
end

local function getColorKey(color)
    return string.format(
        "%.5f:%.5f:%.5f:%.5f",
        color.r,
        color.g,
        color.b,
        color.a
    )
end

local function getPlayerIndex(player)
    local index = tonumber(safeCall(player, "getIndex"))
    if index == nil then index = tonumber(safeCall(player, "getPlayerNum")) end
    if index == nil or index < 0 then return nil end
    return math.floor(index)
end

local function isAlreadyHighlighted(zombie, playerIndex)
    return safeCall(zombie, "isOutlineHighlight", playerIndex) == true
end

local function applyOutlineColor(zombie, playerIndex, color)
    if not zombie or playerIndex == nil then return false end
    return safeInvoke(
        zombie,
        "setOutlineHighlightCol",
        playerIndex,
        color.r,
        color.g,
        color.b,
        color.a
    )
end

local function applyOwnedOutline(zombie, playerIndex, color)
    if not zombie or playerIndex == nil then return false end
    applyOutlineColor(zombie, playerIndex, color)
    safeInvoke(zombie, "setOutlineHlBlink", playerIndex, false)
    return safeInvoke(zombie, "setOutlineHighlight", playerIndex, true)
end

local function clearOwnedOutline(zombie, playerIndex, record)
    if record and record.owned == true then
        safeInvoke(zombie, "setOutlineHighlight", playerIndex, false)
    end
end

local function clearPlayerState(playerIndex)
    local state = CPD._impactTargetOutlineByPlayer[playerIndex]
    if not state then return end
    for zombie, record in pairs(state.targets or {}) do
        clearOwnedOutline(zombie, playerIndex, record)
    end
    CPD._impactTargetOutlineByPlayer[playerIndex] = nil
end

function CPD.clearImpactTargetOutlines(player)
    if player then
        local playerIndex = getPlayerIndex(player)
        if playerIndex ~= nil then clearPlayerState(playerIndex) end
        CPD._forcedOpeningOutlineDoors[player] = nil
        return
    end
    for playerIndex in pairs(CPD._impactTargetOutlineByPlayer) do
        clearPlayerState(playerIndex)
    end
    CPD._forcedOpeningOutlineDoors = {}
end

function CPD.setForcedOpeningTargetOutline(player, door)
    if not player or not door then return false end
    CPD._forcedOpeningOutlineDoors[player] = door
    return true
end

function CPD.clearForcedOpeningTargetOutline(player, door)
    if not player then return false end
    local current = CPD._forcedOpeningOutlineDoors[player]
    if door ~= nil and current ~= nil and current ~= door then return false end
    CPD._forcedOpeningOutlineDoors[player] = nil
    local playerIndex = getPlayerIndex(player)
    if playerIndex ~= nil then clearPlayerState(playerIndex) end
    return current ~= nil
end

local function playerCanPreview(player)
    if not player or safeCall(player, "isAlive") ~= true then return false end
    if safeCall(player, "getVehicle") ~= nil then return false end
    if safeCall(player, "isAsleep") == true then return false end
    if safeCall(player, "isAiming") == true then return false end
    if safeCall(player, "isSitOnGround") == true then return false end
    if safeCall(player, "isSeated") == true then return false end
    if safeCall(player, "isFalling") == true then return false end
    if safeCall(player, "isKnockedDown") == true then return false end
    if safeCall(player, "isOnFloor") == true then return false end
    if safeCall(player, "isClimbing") == true then return false end
    return safeCall(player, "getCurrentSquare") ~= nil
end

local function getPreviewPlan(player)
    local forcedDoor = CPD._forcedOpeningOutlineDoors[player]
    if forcedDoor then
        local plan = CPD.getDoorImpactPreviewState(player, forcedDoor, "open", true)
        if plan then return plan end
        CPD._forcedOpeningOutlineDoors[player] = nil
    end

    if type(CPD.findLocalInteractionCandidate) ~= "function" then return nil end
    local candidate = CPD.findLocalInteractionCandidate(player)
    if not candidate or candidate.impactEligible ~= true or not candidate.door then return nil end
    return CPD.getDoorImpactPreviewState(
        player,
        candidate.door,
        candidate.transition,
        false
    )
end

local function updatePlayerOutline(player)
    local playerIndex = getPlayerIndex(player)
    if playerIndex == nil then return nil end
    if not playerCanPreview(player) then
        clearPlayerState(playerIndex)
        return playerIndex
    end

    local plan = getPreviewPlan(player)
    local desired = {}
    if plan and plan.zombies then
        for i = 1, #plan.zombies do
            local zombie = plan.zombies[i]
            if zombie and CPD.isEligibleZombieTarget(zombie) then
                desired[zombie] = true
            end
        end
    end

    local state = CPD._impactTargetOutlineByPlayer[playerIndex]
    if not state then state = { player = player, targets = {} } end
    local previous = state.targets or {}
    local nextTargets = {}
    local color = getConfiguredOutlineColor()
    local colorKey = getColorKey(color)

    for zombie in pairs(desired) do
        local record = previous[zombie]
        if record and record.owned == true then
            if record.colorKey ~= colorKey then
                if applyOutlineColor(zombie, playerIndex, color) then
                    record.colorKey = colorKey
                end
            end
        elseif record then
            if not isAlreadyHighlighted(zombie, playerIndex) then
                local owned = applyOwnedOutline(zombie, playerIndex, color)
                record = {
                    owned = owned,
                    colorKey = owned and colorKey or nil,
                }
            end
        elseif isAlreadyHighlighted(zombie, playerIndex) then
            record = { owned = false, colorKey = nil }
        else
            local owned = applyOwnedOutline(zombie, playerIndex, color)
            record = {
                owned = owned,
                colorKey = owned and colorKey or nil,
            }
        end
        nextTargets[zombie] = record
    end

    for zombie, record in pairs(previous) do
        if not desired[zombie] then
            clearOwnedOutline(zombie, playerIndex, record)
        end
    end

    state.player = player
    state.targets = nextTargets
    state.plan = plan
    CPD._impactTargetOutlineByPlayer[playerIndex] = state
    return playerIndex
end

local function visitLocalPlayers(visitor)
    local visited = {}
    local found = false
    if getNumActivePlayers and getSpecificPlayer then
        local okCount, count = pcall(getNumActivePlayers)
        count = okCount and math.max(0, tonumber(count) or 0) or 0
        for i = 0, count - 1 do
            local okPlayer, player = pcall(getSpecificPlayer, i)
            if okPlayer and player then
                found = true
                local index = visitor(player)
                if index ~= nil then visited[index] = true end
            end
        end
    end
    if not found and getPlayer then
        local okPlayer, player = pcall(getPlayer)
        if okPlayer and player then
            local index = visitor(player)
            if index ~= nil then visited[index] = true end
        end
    end
    return visited
end

function CPD.maintainImpactTargetOutlines()
    if not S.impactTargetOutlineEnabled() then
        CPD.clearImpactTargetOutlines()
        return
    end

    local invalidPlayers = {}
    for playerIndex, state in pairs(CPD._impactTargetOutlineByPlayer) do
        if not state or not playerCanPreview(state.player) then
            invalidPlayers[#invalidPlayers + 1] = playerIndex
        else
            for zombie, record in pairs(state.targets or {}) do
                if zombie and record and record.owned == true then
                    safeInvoke(zombie, "setOutlineHighlight", playerIndex, true)
                end
            end
        end
    end

    for i = 1, #invalidPlayers do
        clearPlayerState(invalidPlayers[i])
    end
end

function CPD.updateImpactTargetOutline()
    if not S.impactTargetOutlineEnabled() then
        CPD.clearImpactTargetOutlines()
        return
    end

    local visited = visitLocalPlayers(updatePlayerOutline)
    for playerIndex in pairs(CPD._impactTargetOutlineByPlayer) do
        if not visited[playerIndex] then clearPlayerState(playerIndex) end
    end
end

local function onPlayerDeath(player)
    CPD.clearImpactTargetOutlines(player)
end

local function onGameStart()
    CPD.clearImpactTargetOutlines()
end

local function onMainMenuEnter()
    CPD.clearImpactTargetOutlines()
end

local function replaceEvent(event, key, callback)
    if not event then return end
    local previous = CPD[key]
    if previous and event.Remove then pcall(event.Remove, previous) end
    if event.Add then event.Add(callback) end
    CPD[key] = callback
end

replaceEvent(Events and Events.OnPlayerDeath, "_impactOutlineDeathEvent", onPlayerDeath)
replaceEvent(Events and Events.OnGameStart, "_impactOutlineGameStartEvent", onGameStart)
replaceEvent(Events and Events.OnMainMenuEnter, "_impactOutlineMenuEvent", onMainMenuEnter)

CPD.mpDebug("TARGET_OUTLINE_LOAD", "state-driven persistent outline preview v3 active")

return CyesPushDoors
