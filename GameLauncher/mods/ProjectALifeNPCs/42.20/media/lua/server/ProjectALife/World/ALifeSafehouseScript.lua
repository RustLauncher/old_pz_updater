require "ProjectALife/World/ALifeSafehouseFx"
require "ProjectALife/World/ALifeSafehouseEvents"

ProjectALife = ProjectALife or {}

local Fx = ProjectALife.SafehouseFx
local Script = {
    queue = {},
    nextId = 0,
    settings = {
        queueCap = 32,
        perTick = 6,
        firstDelayMs = 700,
        noPowerDelayMs = 2500,
        noPowerText = "The radio has no power.",
        defaultFrequency = 99600,
        radioPlayers = 3,
        soundPlayers = 2,
    },
}
ProjectALife.SafehouseScript = Script

function Script.reset()
    Script.queue = {}
    Script.nextId = 0
    Script.debtPaid = false
end

function Script.debts()
    local director = ProjectALife.SafehouseDirector
    local store = director ~= nil and director.store() or nil
    if store == nil then return nil end
    store.radioDebt = type(store.radioDebt) == "table" and store.radioDebt or {}
    return store.radioDebt
end

function Script.owe(id)
    local state, last, list = Fx.active[id], Fx.last, Script.debts()
    if list == nil or state == nil or state.switched ~= true or last == nil or last.kind ~= "world" or last.x == nil then return false end
    if #list >= 16 then table.remove(list, 1) end
    list[#list + 1] = { id = id, x = math.floor(last.x), y = math.floor(last.y), tries = 0 }
    ProjectALife.SafehouseDirector.dirty()
    return true
end

function Script.forgive(id)
    local list = Script.debts()
    if list == nil then return end
    for index = #list, 1, -1 do
        if list[index].id == id then
            table.remove(list, index)
            ProjectALife.SafehouseDirector.dirty()
        end
    end
end

function Script.payDebts()
    Script.debtPaid = true
    local list = Script.debts()
    if list == nil or #list == 0 then return 0 end
    local devices = Fx.worldDevices() or {}
    local paid = 0
    for index = #list, 1, -1 do
        local entry = list[index]
        local found = Fx.active[entry.id] ~= nil
        for _, device in ipairs(devices) do
            if found then break end
            local x, y = Fx.position(device)
            if Fx.isKind(device, "IsoRadio") and x ~= nil and math.floor(x) == entry.x and math.floor(y) == entry.y then
                local data = Fx.ask(device, "getDeviceData")
                if data ~= nil and Fx.ask(data, "getIsTurnedOn") == true and type(data.setIsTurnedOn) == "function" then
                    pcall(data.setIsTurnedOn, data, false)
                end
                found = true
            end
        end
        entry.tries = (tonumber(entry.tries) or 0) + 1
        if Fx.active[entry.id] == nil and (found or entry.tries >= 5) then
            table.remove(list, index)
            paid = paid + 1
        end
    end
    ProjectALife.SafehouseDirector.dirty()
    return paid
end

function Script.nowMs()
    if type(getTimestampMs) == "function" then return tonumber(getTimestampMs()) or 0 end
    return 0
end

function Script.serverSide()
    return type(isServer) == "function" and isServer() == true
end

function Script.newId()
    Script.nextId = Script.nextId + 1
    return "r" .. tostring(Script.nextId) .. "_" .. tostring(math.floor(Script.nowMs()))
end

function Script.frequency()
    local knox = ProjectALife.KnoxRadio
    if knox ~= nil and type(knox.frequency) == "function" then
        local value = tonumber(knox.frequency())
        if value ~= nil then return math.floor(value) end
    end
    return Script.settings.defaultFrequency
end

function Script.send(player, fx)
    if player == nil or type(fx) ~= "table" then return false end
    if fx.kind == "sound" then Fx.count("soundsPlayed") end
    if Script.serverSide() then
        if type(sendServerCommand) ~= "function" then return false end
        return pcall(sendServerCommand, player, "ProjectALife", "safehouseFx", fx) == true
    end
    return Fx.handle(fx, player) == true
end

function Script.later(player, atMs, fx)
    local queue = Script.queue
    while #queue >= Script.settings.queueCap do table.remove(queue, 1) end
    queue[#queue + 1] = { player = player, atMs = atMs, fx = fx }
end

function Script.tick(nowMs)
    local queue = Script.queue
    local paid = 0
    if not Script.debtPaid and not Script.serverSide() then paid = Script.payDebts() end
    if #queue == 0 then return paid end
    nowMs = tonumber(nowMs) or Script.nowMs()
    local sent, index = paid, 1
    while index <= #queue and sent < Script.settings.perTick do
        if queue[index].atMs <= nowMs then
            local entry = table.remove(queue, index)
            Script.send(entry.player, entry.fx)
            if entry.fx.kind == "radioRestore" then Script.forgive(entry.fx.id) end
            sent = sent + 1
        else
            index = index + 1
        end
    end
    return sent
end

function Script.home(house, present, row, text, now, force)
    if type(row) ~= "table" or type(present) ~= "table" or not Fx.optionOn() then return false, nil end
    if row.fx == "radio" then return Script.radio(house, present, row, text) end
    if row.fx == "sound" then return Script.sound(house, present, row, text) end
    return false, nil
end

function Script.radio(house, present, row, text)
    local director = ProjectALife.SafehouseDirector
    if not Fx.optionOn("radioActivate") then return false, "radio switching is off: text only" end
    local frequency, used, notes = Script.frequency(), {}, {}
    local nowMs = Script.nowMs()
    for index = 1, math.min(#present, Script.settings.radioPlayers) do
        local player = present[index]
        local px, py, pz = Fx.position(player)
        local candidates = Fx.radioCandidates(player, px, py, pz)
        local pick = nil
        for _, candidate in ipairs(candidates) do
            if pick == nil and Fx.radioUsable(candidate) then pick = candidate end
        end
        local name = tostring(director.displayName(player))
        if pick == nil and #candidates == 0 then
            Fx.count("radioNoDevice")
            director.tell(player, text)
            notes[#notes + 1] = name .. ": no radio within " .. Fx.settings.radioRadius .. " tiles, overhead text"
        elseif pick == nil then
            Fx.count("radioNoPower")
            director.tell(player, text)
            Script.later(player, nowMs + Script.settings.noPowerDelayMs, { kind = "text", text = Script.settings.noPowerText })
            notes[#notes + 1] = name .. ": the radio has no power"
        elseif used[pick.device] == true and not Script.serverSide() then
            notes[#notes + 1] = name .. ": shares the radio already switched on"
        else
            used[pick.device] = true
            local id = Script.newId()
            local fx = { kind = "radio", id = id, text = text, frequency = frequency, x = px, y = py, z = pz }
            local sent = Script.send(player, fx)
            if sent then
                Fx.count("radioActivated")
                Fx.count("scriptedEffects")
                if not Script.serverSide() then Script.owe(id) end
                Script.later(player, nowMs + Fx.holdMs(text), { kind = "radioRestore", id = id })
                local where = pick.kind
                if pick.x ~= nil then where = where .. " at " .. math.floor(pick.x) .. "," .. math.floor(pick.y) end
                notes[#notes + 1] = name .. ": " .. where .. " " .. (Script.serverSide() and "told to switch on" or "switched on")
            else
                Fx.count("radioNoPower")
                notes[#notes + 1] = name .. ": the radio did not switch on (" .. tostring(Fx.last and Fx.last.reason) .. ")"
            end
        end
    end
    return true, table.concat(notes, "; ")
end

function Script.radioNews(house, present, text)
    local sent = 0
    local nowMs = Script.nowMs()
    if not Fx.optionOn() then return 0 end
    for index = 1, math.min(#present, Script.settings.radioPlayers) do
        local player = present[index]
        local px, py, pz = Fx.position(player)
        local live = Fx.onlyOn(Fx.radioCandidates(player, px, py, pz))
        if #live > 0 then
            local id = Script.newId()
            local fx = { kind = "radio", id = id, text = text, x = px, y = py, z = pz, onlyOn = true }
            if Script.send(player, fx) then
                sent = sent + 1
                Fx.count("radioNews")
                Script.later(player, nowMs + Fx.holdMs(text), { kind = "radioRestore", id = id })
            end
        end
    end
    return sent
end

function Script.spot(house, rule)
    local director = ProjectALife.SafehouseDirector
    local stand = director.standOf(house) or { x = house.cx or 0, y = house.cy or 0, z = 0 }
    if rule.where == "door" then return stand.x, stand.y, math.floor(tonumber(stand.z) or 0) end
    local far = type(rule.far) == "table" and rule.far or { 30, 60 }
    local distance = director.span(far) or 40
    local angle = math.rad(director.rand(360))
    return (house.cx or stand.x) + math.cos(angle) * distance, (house.cy or stand.y) + math.sin(angle) * distance,
        math.floor(tonumber(stand.z) or 0)
end

function Script.sound(house, present, row, text)
    local director = ProjectALife.SafehouseDirector
    local rule = type(row.sound) == "table" and row.sound or {}
    local names = type(rule.names) == "table" and rule.names or {}
    if #names == 0 then return false, nil end
    local count = tonumber(rule.count)
    if count == nil then count = director.span(rule.count) end
    count = math.max(1, math.floor(tonumber(count) or 1))
    local gap = tonumber(rule.gapMs) or 900
    local nowMs = Script.nowMs()
    local x, y, z = Script.spot(house, rule)
    local cues = ProjectALife.InteractionCues
    local cued = type(rule.cue) == "string" and director.settings.knockSounds == true and cues ~= nil
        and type(cues.pick) == "function"
    local queued = 0
    for index = 1, math.min(#present, Script.settings.soundPlayers) do
        local last = 0
        for shot = 1, count do
            local jitter = 0
            if rule.where ~= "door" then jitter = director.rand(5) - 2 end
            local name, atMs = names[1 + director.rand(#names)], nowMs + Script.settings.firstDelayMs + (shot - 1) * gap + director.rand(250)
            if cued then
                local picked, seconds = cues.pick(rule.cue, tostring(house.key) .. ":" .. tostring(index))
                if picked ~= nil then
                    name = picked
                    atMs = math.max(atMs, last + math.floor((tonumber(seconds) or 0) * 1000) + 250)
                    last = atMs
                end
            end
            Script.later(present[index], atMs, { kind = "sound", name = name, x = x + jitter, y = y - jitter, z = z })
            queued = queued + 1
        end
    end
    if queued > 0 then Fx.count("scriptedEffects") end
    return cued and queued > 0, string.format("%d sound(s) queued around %d,%d", queued, math.floor(x), math.floor(y))
end

function Script.dry(player, row)
    if not Fx.optionOn() then return "scripted effects are off: text only" end
    if row.fx == "sound" then
        local rule = type(row.sound) == "table" and row.sound or {}
        return "plays " .. tostring(rule.names and rule.names[1]) .. " (client side, vanilla sound)"
    end
    if not Fx.optionOn("radioActivate") then return "radio switching is off: text only" end
    local px, py, pz = Fx.position(player)
    local candidates = Fx.radioCandidates(player, px, py, pz)
    if #candidates == 0 then return "no radio within " .. Fx.settings.radioRadius .. " tiles: overhead text" end
    local usable, why = Fx.radioUsable(candidates[1])
    local at = candidates[1].kind
    if candidates[1].x ~= nil then at = at .. " " .. math.floor(candidates[1].x) .. "," .. math.floor(candidates[1].y) end
    if usable then return "nearest radio: " .. at .. " (would switch on)" end
    return "nearest radio: " .. at .. " has no power: overhead text"
end

return Script
