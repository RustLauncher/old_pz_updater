require "ProjectALife/Core/ALifeTelemetry"

local Telemetry = ProjectALife.Telemetry

local Radio = {
    adapters = {},
    settings = {
        reach = 3,                  
        useReuseHours = 0.5,

        backupDelayHours = 0.04,
        backupDelayRollHours = 0.06,
        secondWaveDelayHours = 0.35,
        secondWaveRollHours = 0.4,

        alarmMs = 90000,
        alarmRefreshMs = 2000,

        cutBackupWaves = 2,
        writeOffHours = 24,         
        barkRadius = 40,
        playerRadius = 90,          
    },
    metrics = { disabled = 0, used = 0, refused = 0, backups = 0, writtenOff = 0 },
}
ProjectALife.OutpostRadio = Radio

local function nowMs()
    if type(Radio.adapters.nowMs) == "function" then return Radio.adapters.nowMs() end
    local ok, value = pcall(getTimestampMs)
    return ok and value or 0
end

local function worldHours()
    if type(Radio.adapters.worldHours) == "function" then return Radio.adapters.worldHours() end
    local hours = 0
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    return hours
end

local function roll()
    if type(Radio.adapters.roll) == "function" then return Radio.adapters.roll() end
    local ok, value = pcall(function() return ZombRand(1000) / 1000 end)
    return ok and value or 0.5
end

local function emit(category, fields)
    if type(Radio.adapters.emit) == "function" then return Radio.adapters.emit(category, fields) end
    if Telemetry ~= nil and type(Telemetry.emit) == "function" then pcall(Telemetry.emit, category, fields) end
end

local function registry()
    return Radio.adapters.registry or ProjectALife.OutpostRegistry
end

local function distance(ax, ay, bx, by)
    local dx, dy = (tonumber(ax) or 0) - (tonumber(bx) or 0), (tonumber(ay) or 0) - (tonumber(by) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

function Radio.configure(adapters)
    Radio.adapters = adapters or {}
    local a = Radio.adapters
    if a.spawnRadius ~= nil then
        Radio.settings.playerRadius = math.max(40, math.min(150, tonumber(a.spawnRadius) or 90))
    end
    return true
end

function Radio.reset()
    Radio.metrics = { disabled = 0, used = 0, refused = 0, backups = 0, writtenOff = 0 }
    return true
end

function Radio.validate(site, verb, px, py, pz, hours)
    if type(site) ~= "table" then return false, "no_site" end
    if type(site.radio) ~= "table" then return false, "no_radio" end
    if site.state ~= "garrisoned" then return false, "site_not_active" end
    local r = site.radio
    if math.floor(tonumber(pz) or 0) ~= math.floor(tonumber(r.z) or 0) then return false, "too_far" end
    if distance(px, py, r.x, r.y) > Radio.settings.reach then return false, "too_far" end
    if verb == "disable" then
        if site.commsDisabled == true then return false, "already_disabled" end
        return true
    elseif verb == "use" then
        if site.commsDisabled == true then return false, "comms_down" end
        if (tonumber(hours) or 0) < (tonumber(site.radioNextUseHour) or -1e9) then return false, "radio_busy" end
        return true
    end
    return false, "unknown_verb"
end

function Radio.backupDue(hours, r, wave)
    local settings = Radio.settings
    local base, spread = settings.backupDelayHours, settings.backupDelayRollHours
    if wave ~= nil and wave >= 2 then
        base = settings.secondWaveDelayHours or base
        spread = settings.secondWaveRollHours or spread
    end
    return (tonumber(hours) or 0) + base
        + spread * math.max(0, math.min(1, tonumber(r) or 0.5))
end

function Radio.killPower(site)
    if type(site) ~= "table" or type(site.bounds) ~= "table" then return 0 end

    if Radio.settings.cutStopsGenerators ~= true then return 0 end
    local stopped = 0
    local b = site.bounds
    pcall(function()
        local cell = getCell()
        if cell == nil then return end
        for x = math.floor(b.x1), math.floor(b.x2) do
            for y = math.floor(b.y1), math.floor(b.y2) do
                local square = cell:getGridSquare(x, y, b.z or 0)
                if square ~= nil then
                    local objects = square:getObjects()
                    for index = 0, (objects and objects:size() or 0) - 1 do
                        local object = objects:get(index)
                        if object ~= nil and instanceof(object, "IsoGenerator")
                                and object:isActivated() then
                            object:setActivated(false)
                            if type(object.transmitCompleteItemToClients) == "function" then
                                object:transmitCompleteItemToClients()
                            end
                            stopped = stopped + 1
                        end
                    end
                end
            end
        end
    end)
    return stopped
end

local function playerPosition(player)
    local px, py, pz, key = 0, 0, 0, nil
    pcall(function() px, py, pz = player:getX(), player:getY(), player:getZ() end)
    pcall(function() key = player:getUsername() end)
    return px, py, pz, key
end

local function bark(site, text)
    pcall(function()
        local actors = Radio.adapters.actors or ProjectALife.ActorRegistry
        local bindings = Radio.adapters.bindings or (ProjectALife.Watchdog and ProjectALife.Watchdog.bindings)
        if actors == nil or bindings == nil or type(actors.list) ~= "function" then return end
        local r, spoken = site.radio, 0
        for _, actor in ipairs(actors.list()) do
            if spoken >= 2 then break end
            if actor.lifecycle == "active" and type(actor.memory) == "table" and actor.memory.outpostId == site.id then
                local binding = bindings[actor.uid]
                if binding ~= nil and binding.shell ~= nil then
                    local sx, sy = 0, 0
                    pcall(function() sx, sy = binding.shell:getX(), binding.shell:getY() end)
                    if distance(sx, sy, r.x, r.y) <= Radio.settings.barkRadius then
                        local speech = ProjectALife.Speech
                        if speech == nil or type(speech.mayVoice) ~= "function" or speech.mayVoice(binding.shell, true) then
                            if speech ~= nil and type(speech.sayLine) == "function" then
                                speech.sayLine(binding.shell, text, "ambient")
                            else
                                pcall(function() binding.shell:Say(text) end)
                            end
                            spoken = spoken + 1
                        end
                    end
                end
            end
        end
    end)
end

Radio.hunters = { squad = true, patrol = true, sit = true, guitar = true, eat = true, drink = true,
    work = true, mechanic = true, farm = true, rest = true }

function Radio.alarm(site, point, now, release)
    if type(site) ~= "table" or type(point) ~= "table" then return 0 end
    local actors = Radio.adapters.actors or ProjectALife.ActorRegistry
    if actors == nil or type(actors.list) ~= "function" then return 0 end
    local told = 0
    local alert = { x = tonumber(point.x) or 0, y = tonumber(point.y) or 0, z = tonumber(point.z) or 0,
        untilMs = (tonumber(now) or nowMs()) + Radio.settings.alarmMs, playerKey = point.playerKey }
    for _, actor in ipairs(actors.list()) do
        local memory = type(actor.memory) == "table" and actor.memory or {}
        if actor.lifecycle == "active" and memory.outpostId == site.id and memory.outpostSquadId == nil then
            local hunter = release == true and Radio.hunters[tostring(memory.stanceRole)] == true
            local write = hunter and actors.update or actors.updateTransient or actors.update
            if type(write) == "function" then
                local ok = pcall(write, actor.uid, actor.revision, function(record)
                    record.memory = record.memory or {}
                    record.memory.outpostAlert = { x = alert.x, y = alert.y, z = alert.z,
                        untilMs = alert.untilMs, playerKey = alert.playerKey }
                    if hunter then record.memory.stance = "" end
                end)
                if ok then told = told + 1 end
            end
        end
    end
    return told
end

local function refuse(reason)
    Radio.metrics.refused = Radio.metrics.refused + 1
    return false, reason
end

function Radio.removeObject(site)
    if type(site) ~= "table" or type(site.radio) ~= "table" then return false end
    local removed = false
    pcall(function()
        if type(getCell) ~= "function" then return end
        local square = getCell():getGridSquare(
            math.floor(tonumber(site.radio.x) or 0),
            math.floor(tonumber(site.radio.y) or 0),
            math.floor(tonumber(site.radio.z) or 0))
        if square == nil then return end
        local objects = square:getObjects()
        for index = (objects and objects:size() or 0) - 1, 0, -1 do
            local object = objects:get(index)
            local mine = false
            pcall(function()
                local data = object ~= nil and object:getModData() or nil
                mine = type(data) == "table"
                    and tostring(data.ProjectALifeRadioSite or "") == tostring(site.id)
            end)
            if mine then

                square:transmitRemoveItemFromSquare(object)
                removed = true
            end
        end
    end)
    if removed then
        Radio.metrics = Radio.metrics or {}
        Radio.metrics.setsRemoved = (Radio.metrics.setsRemoved or 0) + 1
    end
    return removed
end

function Radio.disable(player, siteId, now)
    local reg = registry()
    if reg == nil then return false, "registry_unavailable" end
    local site = reg.read(tostring(siteId or ""))
    local px, py, pz, key = playerPosition(player)
    local hours = worldHours()
    local ok, reason = Radio.validate(site, "disable", px, py, pz, hours)
    if not ok then return refuse(reason) end

    local wasFriendly = site.hostileToPlayers ~= true

    local cap = tonumber(Radio.settings.cutBackupWaves) or 2
    pcall(function()
        local preset = ProjectALife.OutpostPresets.get(site.presetId)
        if type(preset) == "table" and preset.backups ~= nil then
            cap = math.max(cap, math.min(3, math.floor(tonumber(preset.backups) or 1)))
        end
    end)
    local due = Radio.backupDue(hours, roll(), 1)
    local updated = reg.update(site.id, site.revision, function(s)
        s.commsDisabled = true
        s.commsDisabledHours = hours
        s.backupCallHours = hours
        s.backupDueHour = due
        s.backups = tonumber(s.backups) or 0
        s.backupCap = cap
        s.backupContact = { x = px, y = py, playerKey = key }

        s.mapHidden = true
        s.disabled = true

        if key ~= nil then
            s.hostileToPlayerKeys = type(s.hostileToPlayerKeys) == "table"
                and s.hostileToPlayerKeys or {}
            s.hostileToPlayerKeys[key] = true
        end

        s.alarm = { playerKey = key, untilMs = (tonumber(now) or nowMs()) + Radio.settings.alarmMs,
            nextAtMs = (tonumber(now) or nowMs()) + Radio.settings.alarmRefreshMs }
    end)
    if updated == nil then return refuse("site_revision_conflict") end
    local alerted = Radio.alarm(updated, { x = px, y = py, z = pz, playerKey = key }, now, true)

    pcall(function()
        local service = Radio.adapters.service or ProjectALife.DebugService
        if service ~= nil and type(service.broadcastOutpostRadios) == "function" then service.broadcastOutpostRadios() end
    end)
    local stopped = Radio.killPower(updated)

    Radio.removeObject(updated)
    pcall(function()
        local service = Radio.adapters.service or ProjectALife.DebugService
        if service ~= nil and type(service.broadcastOutpostRadios) == "function" then service.broadcastOutpostRadios() end
    end)
    Radio.metrics.disabled = Radio.metrics.disabled + 1

    pcall(function()
        local meta = ProjectALife.MetaEvents
        local name = meta and meta.sounds and meta.sounds.radioOff
        if type(name) ~= "string" or player == nil then return end
        if type(isServer) == "function" and isServer() and type(sendPlaySound) == "function" then
            sendPlaySound(name, false, player)
        else
            player:playSound(name)
        end
    end)
    bark(site, "They cut the radio!")
    emit("outpost_comms_disabled", { site = site.id, reason = tostring(key or "player"),
        count = stopped,
        task = string.format("%d waves, first in %.2f h, %d generators stopped, %d men alerted",
            cap, due - hours, stopped, alerted) })
    return true, "comms_disabled", wasFriendly
end

function Radio.use(player, siteId, now)
    local reg = registry()
    if reg == nil then return false, "registry_unavailable" end
    local site = reg.read(tostring(siteId or ""))
    local px, py, pz, key = playerPosition(player)
    local hours = worldHours()
    now = tonumber(now) or nowMs()
    local ok, reason = Radio.validate(site, "use", px, py, pz, hours)
    if not ok then return refuse(reason) end
    if site.hostileToPlayers ~= true then

        local support = Radio.adapters.support or ProjectALife.Support
        if support == nil or type(support.requestFromOutpost) ~= "function" then return refuse("support_unavailable") end
        local sent, detail = support.requestFromOutpost(site, { x = px, y = py, playerKey = key }, "help", now, hours, player)
        if not sent then return refuse(detail) end
        reg.update(site.id, site.revision, function(s) s.radioNextUseHour = hours + Radio.settings.useReuseHours end)
        Radio.metrics.used = Radio.metrics.used + 1
        emit("outpost_radio_used", { site = site.id, reason = "help", task = tostring(detail) })
        return true, "help_called"
    end

    local due = Radio.backupDue(hours, roll())
    reg.update(site.id, site.revision, function(s)
        s.radioNextUseHour = hours + Radio.settings.useReuseHours
        if s.backupDueHour == nil then
            s.backupDueHour = due
            s.backupCallHours = hours
        end
        s.backupCap = math.max(tonumber(s.backupCap) or 0, 1)
        s.backups = tonumber(s.backups) or 0
        s.backupContact = { x = px, y = py, playerKey = key }
    end)
    Radio.metrics.used = Radio.metrics.used + 1
    emit("outpost_radio_used", { site = site.id, reason = "bait", task = string.format("backup due in %.1f h", due - hours) })
    return true, "bait"
end

function Radio.handle(player, command, args, now)
    local siteId = type(args) == "table" and args.site or nil
    if command == "outpostRadioDisable" then return Radio.disable(player, siteId, now) end
    if command == "outpostRadioUse" then return Radio.use(player, siteId, now) end
    return false, "unknown_verb"
end

local function nearestPlayer(site, list)
    local nearest, picked = math.huge, nil
    for _, p in ipairs(type(list) == "table" and list or {}) do
        local d = distance(site.x, site.y, p.x, p.y)
        if d < nearest then nearest, picked = d, p end
    end
    return nearest, picked
end

function Radio.tick(hours, now, list)
    local reg = registry()
    if reg == nil then return 0 end
    hours = tonumber(hours) or worldHours()
    now = tonumber(now) or nowMs()
    local work = 0
    for _, site in ipairs(reg.list()) do

        local alarm = type(site.alarm) == "table" and site.alarm or nil
        if alarm ~= nil and now < (tonumber(alarm.untilMs) or 0) and now >= (tonumber(alarm.nextAtMs) or 0) then
            for _, p in ipairs(type(list) == "table" and list or {}) do
                local name = p.key
                if name == nil then pcall(function() name = p.player:getUsername() end) end
                if name ~= nil and name == alarm.playerKey then
                    local z = 0
                    pcall(function() z = p.player:getZ() end)
                    Radio.alarm(site, { x = p.x, y = p.y, z = z, playerKey = name }, now, false)
                end
            end
            reg.update(site.id, site.revision, function(s)
                if type(s.alarm) == "table" then s.alarm.nextAtMs = now + Radio.settings.alarmRefreshMs end
            end)
            site = reg.read(site.id) or site
        end
        local due = tonumber(site.backupDueHour)
        if due ~= nil and site.state ~= "expired" then
            if (tonumber(site.backups) or 0) >= math.max(0, tonumber(site.backupCap) or 1) then
                reg.update(site.id, site.revision, function(s) s.backupDueHour = nil end)
                work = work + 1
            elseif hours >= due + Radio.settings.writeOffHours then
                reg.update(site.id, site.revision, function(s) s.backupDueHour = nil end)
                Radio.metrics.writtenOff = Radio.metrics.writtenOff + 1
                emit("outpost_backup_written_off", { site = site.id, reason = "nobody_came" })
                work = work + 1
            elseif hours >= due then
                local nearest, picked = nearestPlayer(site, list)
                if picked ~= nil and nearest <= Radio.settings.playerRadius then
                    local support = Radio.adapters.support or ProjectALife.Support
                    local contact = type(site.backupContact) == "table" and site.backupContact or {}
                    local key = contact.playerKey
                    if key == nil then pcall(function() key = picked.player:getUsername() end) end
                    local sent, detail = false, "support_unavailable"
                    if support ~= nil and type(support.requestFromOutpost) == "function" then
                        sent, detail = support.requestFromOutpost(site,
                            { x = site.x, y = site.y, playerKey = key or picked.key }, "backup", now, hours, picked.player)
                    end
                    if sent then
                        local backups = (tonumber(site.backups) or 0) + 1
                        local cap = tonumber(site.backupCap) or 1
                        local again = backups < cap
                            and Radio.backupDue(hours, roll(), backups + 1) or nil
                        reg.update(site.id, site.revision, function(s)
                            s.backups = backups
                            s.backupDueHour = again
                        end)
                        Radio.metrics.backups = Radio.metrics.backups + 1
                        emit("outpost_backup_dispatched", { site = site.id, task = tostring(detail), count = backups })
                        work = work + 1
                    end
                end
            end
        end
    end
    return work
end

return Radio
