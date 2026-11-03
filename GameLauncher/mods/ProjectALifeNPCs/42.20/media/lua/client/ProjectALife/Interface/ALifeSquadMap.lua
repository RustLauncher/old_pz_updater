ProjectALife = ProjectALife or {}

require "ProjectALife/Interface/ALifeSquadMapOverlay"

require "ISUI/Maps/ISWorldMap"

local SquadMap = {
    enabled = false,
    playerNum = 0,
    squads = {},
    symbols = {},
    lastRequestAtMs = 0,

    requestIntervalMs = 6000,

    refreshHours = 0.1,
    lastRequestHours = nil,

    checkIntervalMs = 1000,
    lastCheckAtMs = 0,

    receivedAtHours = nil,

    retryAfterMs = 1500,
    retryStamp = nil,
}
ProjectALife.SquadMap = SquadMap

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return 0
end

local function worldHours()
    local hours
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    return hours
end

local function openMap()

    local map = ISWorldMap_instance
    if map == nil and ISWorldMap ~= nil then map = ISWorldMap.instance end
    return map
end

local function mapVisible()
    local visible = false
    pcall(function()
        local map = openMap()
        visible = map ~= nil and map:isVisible() == true
    end)
    return visible
end

local function two(n)
    n = math.floor(tonumber(n) or 0)
    return (n < 10 and "0" or "") .. tostring(n)
end

function SquadMap.caption()
    local text = "A-Life squads: " .. tostring(#SquadMap.squads)

    local total, shown = tonumber(SquadMap.offlineTotal), tonumber(SquadMap.offlineShown)
    if total ~= nil and shown ~= nil and total > shown then
        text = text .. "  |  offline: nearest " .. tostring(shown) .. " of " .. tostring(total)
    end
    local census = SquadMap.census
    if type(census) == "table" then
        text = text .. "  |  census: " .. tostring(census.alive) .. " in the world, " .. tostring(census.living)
            .. " living, " .. tostring(census.dead) .. " killed, " .. tostring(census.arrived) .. " arrived"
    end
    local at = tonumber(SquadMap.receivedAtHours)
    if at ~= nil then
        local dayHour = at % 24
        text = text .. "  |  positions as of " .. two(dayHour) .. ":" .. two((dayHour % 1) * 60) .. " game time"
    end
    text = text .. "  |  refreshes every " .. tostring(math.floor(SquadMap.refreshHours * 60 + 0.5))
        .. " game minutes while the map is open  |  hover a dot, right-click for actions"

    local flash = SquadMap.flash
    if type(flash) == "table" and nowMs() < (tonumber(flash.untilMs) or 0) then
        text = text .. "  |  " .. tostring(flash.text)
    end
    return text
end

local function paint()
    pcall(function()
        local map = openMap()
        local overlay = ProjectALife.SquadMapOverlay
        if map == nil or overlay == nil or not map:isVisible() then return end
        overlay.attach(map, function() return SquadMap.squads end, SquadMap.caption)
    end)
end

pcall(function()
    if ISWorldMap == nil or SquadMap.hooked then return end
    SquadMap.hooked = true
    local vanillaShow = ISWorldMap.ShowWorldMap
    ISWorldMap.ShowWorldMap = function(...)
        local result = vanillaShow(...)
        if SquadMap.enabled then
            SquadMap.lastRequestHours = nil
            paint()
        end
        return result
    end
end)

local function request()
    SquadMap.lastRequestAtMs = nowMs()
    SquadMap.lastRequestHours = worldHours()
    pcall(function()
        local player = getSpecificPlayer(SquadMap.playerNum)
        if player ~= nil and type(sendClientCommand) == "function" then
            sendClientCommand(player, "ProjectALife", "debugSquadMap", {})
        end
    end)
end

function SquadMap.refreshDue(nowMs, hours, mapVisible, state)
    state = state or SquadMap
    if not mapVisible then return false end
    if (tonumber(nowMs) or 0) - (tonumber(state.lastRequestAtMs) or 0) < (tonumber(state.requestIntervalMs) or 0) then
        return false
    end
    if state.lastRequestHours == nil or hours == nil then return true end
    return hours - state.lastRequestHours >= (tonumber(state.refreshHours) or 0.1)
end

function SquadMap.toggle(playerNum)
    SquadMap.playerNum = playerNum or 0
    SquadMap.enabled = not SquadMap.enabled
    local player = getSpecificPlayer(playerNum or 0)
    if SquadMap.enabled then
        request()
        if player ~= nil then player:Say("A-Life: squad map ON (open the world map, hover a dot)") end
    else
        SquadMap.squads = {}
        SquadMap.receivedAtHours = nil
        SquadMap.offlineTotal, SquadMap.offlineShown = nil, nil
        pcall(function()
            local overlay = ProjectALife.SquadMapOverlay
            if overlay ~= nil then overlay.detach() end
        end)
        if player ~= nil then player:Say("A-Life: squad map off") end
    end
end

function SquadMap.hide()
    if not SquadMap.enabled then return false end
    SquadMap.enabled = false
    SquadMap.squads = {}
    SquadMap.receivedAtHours = nil
    SquadMap.offlineTotal, SquadMap.offlineShown = nil, nil
    SquadMap.flash, SquadMap.retryStamp = nil, nil
    local overlay = ProjectALife.SquadMapOverlay
    if overlay ~= nil and type(overlay.detach) == "function" then pcall(overlay.detach) end
    return true
end

function SquadMap.show(playerNum)
    SquadMap.playerNum = playerNum or 0
    SquadMap.enabled = true
    request()
    if ISWorldMap ~= nil and type(ISWorldMap.ShowWorldMap) == "function" then
        ISWorldMap.ShowWorldMap(playerNum or 0)
    end
    paint()
end

SquadMap.actions = {
    delete = { command = "debugSquadDelete", args = function(row) return { groupId = row.groupId } end },
    spawnNow = { command = "debugOutpostSquadNow", args = function(row) return { siteId = row.siteId } end },
    delay = { command = "debugOutpostDelay", args = function(row, value) return { siteId = row.siteId, hours = value } end },
    cap = { command = "debugOutpostSquadCap", args = function(row, value) return { siteId = row.siteId, delta = value } end },
}
SquadMap.actionResults = {
    debugSquadDeleteResult = "squad deleted", debugOutpostSquadNowResult = "squad sent out",
    debugOutpostDelayResult = "next squad delayed", debugOutpostSquadCapResult = "squad cap changed",
}

function SquadMap.act(action, row, value)
    local spec = SquadMap.actions[action]
    if spec == nil or type(row) ~= "table" then return false end
    local sent = false
    pcall(function()
        local player = getSpecificPlayer(SquadMap.playerNum)
        if player ~= nil and type(sendClientCommand) == "function" then
            sendClientCommand(player, "ProjectALife", spec.command, spec.args(row, value))
            sent = true
        end
    end)
    return sent
end

function SquadMap.refusalText(reason)
    local prefs = ProjectALife.MenuPrefs
    if reason ~= "diagnostics_disabled" or prefs == nil
            or type(prefs.diagnosticsRefused) ~= "function" then
        return "A-Life: refused - " .. tostring(reason or "unknown"), nil
    end
    local player = getSpecificPlayer(SquadMap.playerNum)
    local stamp = prefs.diagnosticsRefused(player, nowMs())
    return prefs.refusedText(player), stamp
end

function SquadMap.refused(payload)
    if payload.reason == "rate_limited" then return false end
    local text, stamp = SquadMap.refusalText(payload.reason)
    if stamp ~= nil then
        text = ProjectALife.MenuPrefs.retryText
        if stamp ~= SquadMap.retryStamp then
            SquadMap.retryStamp = stamp
            SquadMap.lastRequestHours = nil
            SquadMap.lastRequestAtMs = nowMs() - SquadMap.requestIntervalMs + SquadMap.retryAfterMs
        end
    end
    SquadMap.flash = { text = tostring(text), untilMs = nowMs() + 8000 }
    return true
end

SquadMap.rosterResults = { debugPurgeActorsResult = true, debugSpawnResult = true, debugSpawnGroupResult = true }

function SquadMap.afterPurge(rows, payload)
    if type(payload) ~= "table" or payload.ok ~= true then return rows end
    local radius, x, y = tonumber(payload.radius), tonumber(payload.x), tonumber(payload.y)
    local kept = {}
    for _, row in ipairs(rows or {}) do
        local live = row.outpost ~= true and row.offline ~= true and row.place ~= true
        local inside = radius == nil or x == nil or y == nil
            or ((tonumber(row.x) or 0) - x) ^ 2 + ((tonumber(row.y) or 0) - y) ^ 2 <= radius * radius
        if not (live and inside) then kept[#kept + 1] = row end
    end
    return kept
end

function SquadMap.rosterChanged(command, payload)
    if not SquadMap.enabled then return false end
    if command == "debugPurgeActorsResult" then SquadMap.squads = SquadMap.afterPurge(SquadMap.squads, payload) end
    SquadMap.lastRequestAtMs = 0
    request()
    SquadMap.lastRequestHours = nil
    SquadMap.lastRequestAtMs = nowMs() - SquadMap.requestIntervalMs + 1500
    paint()
    return true
end

local function onServerCommand(module, command, payload)
    if module ~= "ProjectALife" then return end
    if SquadMap.rosterResults[command] == true then
        SquadMap.rosterChanged(command, payload)
        return
    end
    if SquadMap.actionResults[command] ~= nil then
        if type(payload) ~= "table" then return end
        local text
        if payload.ok == true then
            local extra = ""
            pcall(function()
                if payload.removed ~= nil then extra = " (" .. tostring(payload.removed) .. " removed)"
                elseif command == "debugOutpostDelayResult" and payload.value ~= nil then
                    extra = " (next in " .. ProjectALife.SquadMapOverlay.formatHours(payload.value) .. ")"
                elseif command == "debugOutpostSquadCapResult" and payload.value ~= nil then
                    extra = " (cap " .. tostring(payload.value) .. ")"
                end
            end)
            text = "A-Life: " .. SquadMap.actionResults[command] .. extra
        else
            text = SquadMap.refusalText(payload.reason)
        end
        SquadMap.flash = { text = text, untilMs = nowMs() + 8000 }
        pcall(function()
            local player = getSpecificPlayer(SquadMap.playerNum)
            if player ~= nil then player:Say(text) end
        end)

        if payload.ok == true and command == "debugSquadDeleteResult" and payload.groupId ~= nil then
            local kept = {}
            for _, row in ipairs(SquadMap.squads or {}) do
                if row.groupId ~= payload.groupId then kept[#kept + 1] = row end
            end
            SquadMap.squads = kept
            paint()
        end

        SquadMap.lastRequestAtMs = 0
        if SquadMap.enabled then request() end
        SquadMap.lastRequestHours = nil
        SquadMap.lastRequestAtMs = nowMs() - SquadMap.requestIntervalMs + 1500
        return
    end
    if command ~= "debugSquadMapResult" then return end
    if not SquadMap.enabled then return end

    if type(payload) == "table" and payload.ok == false then
        SquadMap.refused(payload)
        return
    end
    if type(payload) ~= "table" or type(payload.squads) ~= "table" then return end
    SquadMap.squads = payload.squads
    SquadMap.offlineTotal, SquadMap.offlineShown = tonumber(payload.offlineTotal), tonumber(payload.offlineShown)
    SquadMap.census = type(payload.census) == "table" and payload.census or nil
    SquadMap.receivedAtHours = worldHours()
    paint()
end

SquadMap.receive = onServerCommand

local function onTick()
    if not SquadMap.enabled then return end
    local now = nowMs()
    if now - SquadMap.lastCheckAtMs < SquadMap.checkIntervalMs then return end
    SquadMap.lastCheckAtMs = now

    if mapVisible() then paint() end
    if not SquadMap.refreshDue(now, worldHours(), mapVisible()) then return end
    request()
end

if type(Events) == "table" then
    if Events.OnServerCommand ~= nil then Events.OnServerCommand.Add(onServerCommand) end

    if Events.OnPreUIDraw ~= nil then Events.OnPreUIDraw.Add(onTick)
    elseif Events.OnTick ~= nil then Events.OnTick.Add(onTick) end
end

return SquadMap
