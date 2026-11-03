ProjectALife = ProjectALife or {}

local Cues = { adapters = {}, last = {}, lastCount = {}, memoryMax = 48, metrics = { played = 0, refused = 0 } }
ProjectALife.InteractionCues = Cues

Cues.sounds = {
    PALFrisk1 = { seconds = 7.36, kind = "frisk", world = true },
    PALFrisk2 = { seconds = 10.95, kind = "frisk", world = true },
    PALFrisk3 = { seconds = 3.49, kind = "frisk", world = true },
    PALKnockSoft1 = { seconds = 1.12, kind = "knock_soft", world = true },
    PALKnockSoft2 = { seconds = 1.31, kind = "knock_soft", world = true },
    PALKnockSoft3 = { seconds = 0.95, kind = "knock_soft", world = true },
    PALKnockSoft4 = { seconds = 1.35, kind = "knock_soft", world = true },
    PALKnockSeries = { seconds = 6.71, kind = "knock_series", world = true },
    PALKnockAggressive1 = { seconds = 1.17, kind = "knock_aggressive", world = true },
    PALKnockAggressive2 = { seconds = 7.68, kind = "knock_aggressive", world = true },
    PALKnockPanic = { seconds = 5.21, kind = "knock_panic", world = true },
    PALDoorOpened = { seconds = 2.19, kind = "door_opened", world = true },
    PALGarageDoorTry = { seconds = 5.27, kind = "garage_try", world = true },
    PALRepUp = { seconds = 2.65, kind = "rep_up", world = false },
    PALRepDown = { seconds = 4.94, kind = "rep_down", world = false },
    PALUINotification = { seconds = 0.41, kind = "ui_notification", world = false },
}

Cues.kinds = {
    frisk = { "PALFrisk1", "PALFrisk2", "PALFrisk3" },
    knock_soft = { "PALKnockSoft1", "PALKnockSoft2", "PALKnockSoft3", "PALKnockSoft4" },
    knock_series = { "PALKnockSeries" },
    knock_aggressive = { "PALKnockAggressive1", "PALKnockAggressive2" },
    knock_panic = { "PALKnockPanic" },
    door_opened = { "PALDoorOpened" },
    garage_try = { "PALGarageDoorTry" },
    rep_up = { "PALRepUp" },
    rep_down = { "PALRepDown" },
    ui_notification = { "PALUINotification" },
}

function Cues.exists(id)
    return type(id) == "string" and Cues.sounds[id] ~= nil
end

function Cues.seconds(id)
    local row = type(id) == "string" and Cues.sounds[id] or nil
    return row ~= nil and row.seconds or 0
end

local function roll(count)
    if type(Cues.adapters.roll) == "function" then return Cues.adapters.roll(count) end
    if type(ZombRand) == "function" then return ZombRand(count) end
    return math.random(0, count - 1)
end

function Cues.pick(kind, key)
    local pool = Cues.kinds[kind]
    if type(pool) ~= "table" or #pool == 0 then return nil end
    local memory = Cues.last[kind]
    if memory == nil then memory = {}; Cues.last[kind] = memory; Cues.lastCount[kind] = 0 end
    local slot = key ~= nil and tostring(key) or "any"
    local previous = memory[slot]
    if previous == nil then
        if (Cues.lastCount[kind] or 0) >= Cues.memoryMax then
            memory = {}
            Cues.last[kind] = memory
            Cues.lastCount[kind] = 0
        end
        Cues.lastCount[kind] = (Cues.lastCount[kind] or 0) + 1
    end
    local index = roll(#pool) + 1
    if #pool > 1 and pool[index] == previous then index = index % #pool + 1 end
    memory[slot] = pool[index]
    return pool[index], Cues.seconds(pool[index])
end

function Cues.play(source, id)
    if not Cues.exists(id) or source == nil or Cues.sounds[id].world ~= true then
        Cues.metrics.refused = Cues.metrics.refused + 1
        return false
    end
    local ok = false
    if type(Cues.adapters.play) == "function" then
        ok = pcall(Cues.adapters.play, source, id) == true
    elseif type(isServer) == "function" and isServer() and type(sendPlaySound) == "function" then
        ok = pcall(sendPlaySound, id, false, source) == true
    elseif type(source.playSound) == "function" then
        ok = pcall(function() source:playSound(id) end) == true
    end
    if ok then Cues.metrics.played = Cues.metrics.played + 1 else Cues.metrics.refused = Cues.metrics.refused + 1 end
    return ok
end

Cues.metrics.sent, Cues.metrics.heard, Cues.metrics.far = 0, 0, 0

Cues.reach = { frisk = 25, knock_soft = 45, knock_series = 45, knock_aggressive = 55, knock_panic = 55,
    door_opened = 40, garage_try = 50 }

function Cues.hearTiles(id)
    local row = type(id) == "string" and Cues.sounds[id] or nil
    if row == nil or row.world ~= true then return 0 end
    return Cues.reach[row.kind] or 25
end

function Cues.pointOf(object)
    if object == nil or type(object.getX) ~= "function" or type(object.getY) ~= "function" then return nil end
    local ok, x, y, z = pcall(function()
        return object:getX(), object:getY(), type(object.getZ) == "function" and object:getZ() or 0
    end)
    if not ok or type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return nil end
    return x, y, type(z) == "number" and z or 0
end

function Cues.listeners()
    if type(Cues.adapters.players) == "function" then return Cues.adapters.players() or {} end
    local list = {}
    if type(isServer) == "function" and isServer() == true then
        if type(getOnlinePlayers) ~= "function" then return list end
        local ok, online = pcall(getOnlinePlayers)
        if ok and online ~= nil and type(online.size) == "function" and type(online.get) == "function" then
            for index = 0, math.min(tonumber(online:size()) or 0, 64) - 1 do
                local player = online:get(index)
                if player ~= nil then list[#list + 1] = player end
            end
        end
        return list
    end
    if type(getSpecificPlayer) == "function" then
        for index = 0, 3 do
            local ok, player = pcall(getSpecificPlayer, index)
            if ok and player ~= nil then list[#list + 1] = player end
        end
    end
    return list
end

function Cues.audience(x, y, z, id)
    local result, reach = {}, Cues.hearTiles(id)
    if reach <= 0 then return result end
    local limit = reach * reach
    for _, player in ipairs(Cues.listeners()) do
        local px, py, pz = Cues.pointOf(player)
        if px ~= nil and (px - x) ^ 2 + (py - y) ^ 2 <= limit and math.abs(pz - z) <= 4 then
            result[#result + 1] = player
        end
    end
    return result
end

function Cues.playLocal(id, x, y, z)
    if not Cues.exists(id) or Cues.sounds[id].world ~= true then return false end
    if type(Cues.adapters.playLocal) == "function" then
        local called, result = pcall(Cues.adapters.playLocal, id, x, y, z)
        return called and result ~= false
    end
    if type(getSoundManager) ~= "function" then return false end
    local manager = getSoundManager()
    if manager == nil or type(manager.PlayWorldSoundImpl) ~= "function" then return false end
    return pcall(manager.PlayWorldSoundImpl, manager, id, false, math.floor(x), math.floor(y), math.floor(z), 0, 20, 1, false) == true
end

function Cues.sendTo(listeners, id, x, y, z)
    if type(sendServerCommand) ~= "function" then return 0 end
    local sent = 0
    for _, player in ipairs(listeners) do
        if pcall(sendServerCommand, player, "ProjectALife", "interactionCue", { id = id, x = x, y = y, z = z }) == true then
            sent = sent + 1
        end
    end
    Cues.metrics.sent = Cues.metrics.sent + sent
    return sent
end

function Cues.playAt(square, id)
    local x, y, z = Cues.pointOf(square)
    if x == nil or not Cues.exists(id) or Cues.sounds[id].world ~= true then
        Cues.metrics.refused = Cues.metrics.refused + 1
        return false, "invalid"
    end
    x, y = x + 0.5, y + 0.5
    local listeners = Cues.audience(x, y, z, id)
    if #listeners == 0 then
        Cues.metrics.far = Cues.metrics.far + 1
        return false, "far"
    end
    local ok = false
    if type(Cues.adapters.playAt) == "function" then
        local called, result = pcall(Cues.adapters.playAt, square, id, x, y, z, listeners)
        ok = called and result ~= false
    elseif type(isServer) == "function" and isServer() == true then
        ok = Cues.sendTo(listeners, id, x, y, z) > 0
    else
        ok = Cues.playLocal(id, x, y, z)
    end
    if ok then Cues.metrics.played = Cues.metrics.played + 1 else Cues.metrics.refused = Cues.metrics.refused + 1 end
    return ok, ok and "played" or "refused", #listeners
end

function Cues.onServerCommand(module, command, arguments)
    if module ~= "ProjectALife" or command ~= "interactionCue" or type(arguments) ~= "table" then return false end
    local x, y, z = tonumber(arguments.x), tonumber(arguments.y), tonumber(arguments.z)
    if x == nil or y == nil or z == nil or x ~= x or y ~= y or z ~= z or math.abs(x) > 1000000
            or math.abs(y) > 1000000 or math.abs(z) > 64 or not Cues.exists(arguments.id) then return false end
    if #Cues.audience(x, y, z, arguments.id) == 0 then
        Cues.metrics.far = Cues.metrics.far + 1
        return false
    end
    local ok = Cues.playLocal(arguments.id, x, y, z)
    if ok then Cues.metrics.heard = Cues.metrics.heard + 1 end
    return ok
end

if type(Events) == "table" and Events.OnServerCommand ~= nil and type(Events.OnServerCommand.Add) == "function"
        and type(isClient) == "function" and isClient() == true then
    local previous = rawget(ProjectALife, "InteractionCuesHandler")
    if previous ~= nil and type(Events.OnServerCommand.Remove) == "function" then pcall(Events.OnServerCommand.Remove, previous) end
    ProjectALife.InteractionCuesHandler = Cues.onServerCommand
    Events.OnServerCommand.Add(Cues.onServerCommand)
end

function Cues.playUI(id)
    if not Cues.exists(id) or Cues.sounds[id].world then return false end
    if type(Cues.adapters.playUI) == "function" then
        local ok, handle = pcall(Cues.adapters.playUI, id)
        return ok == true, handle
    end
    if type(getSoundManager) ~= "function" then return false end
    local handle
    local ok = pcall(function() handle = getSoundManager():playUISound(id) end)
    return ok == true, handle
end

function Cues.stopUI(handle)
    if handle == nil then return false end
    if type(Cues.adapters.stopUI) == "function" then return pcall(Cues.adapters.stopUI, handle) == true end
    if type(getSoundManager) ~= "function" then return false end
    return pcall(function() getSoundManager():stopUISound(handle) end) == true
end

return Cues
