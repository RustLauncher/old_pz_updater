ProjectALife = ProjectALife or {}

local Fx = {
    settings = {
        radioRadius = 25,
        houseRadius = 12,
        holdMin = 12000,
        holdMax = 40000,
        holdPerChar = 80,
        volume = 0.6,
        listMax = 200,
        scanMax = 600,
    },
    active = {},
    nextId = 0,
}
ProjectALife.SafehouseFx = Fx

function Fx.freshMetrics()
    return { radioActivated = 0, radioNoDevice = 0, radioNoPower = 0, radioFar = 0, radioRestored = 0,
        marksPlaced = 0, marksRefused = {}, marksRemoved = 0, scriptedEffects = 0, soundsPlayed = 0 }
end
Fx.metrics = Fx.freshMetrics()

function Fx.reset()
    Fx.metrics = Fx.freshMetrics()
    Fx.active = {}
    Fx.nextId = 0
end

function Fx.count(name, amount)
    Fx.metrics[name] = (tonumber(Fx.metrics[name]) or 0) + (tonumber(amount) or 1)
end

function Fx.refuse(reason)
    local list = Fx.metrics.marksRefused
    list[reason] = (tonumber(list[reason]) or 0) + 1
end

function Fx.ask(object, name, a, b)
    if object == nil then return nil end
    local method = object[name]
    if type(method) ~= "function" then return nil end
    local ok, value
    if b ~= nil then
        ok, value = pcall(method, object, a, b)
    elseif a ~= nil then
        ok, value = pcall(method, object, a)
    else
        ok, value = pcall(method, object)
    end
    if not ok then return nil end
    return value
end

function Fx.field(object, key)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

function Fx.items(list, cap)
    local result = {}
    if list == nil then return result end
    cap = tonumber(cap) or Fx.settings.listMax
    local size = tonumber(Fx.ask(list, "size")) or 0
    local getter = list.get
    if type(getter) == "function" then
        for index = 0, math.min(size, cap) - 1 do
            local ok, item = pcall(getter, list, index)
            if ok and item ~= nil then result[#result + 1] = item end
        end
        return result
    end
    local array = Fx.ask(list, "toArray")
    if type(array) == "table" then
        for _, item in pairs(array) do
            if item ~= nil and #result < cap then result[#result + 1] = item end
        end
    end
    return result
end

function Fx.isKind(object, name)
    return object ~= nil and type(instanceof) == "function" and instanceof(object, name) == true
end

function Fx.optionOn(name)
    local director = ProjectALife.SafehouseDirector
    local settings = director ~= nil and director.settings or nil
    if type(settings) ~= "table" then return true end
    if settings.scriptedEffects == false then return false end
    if name == nil or name == "scriptedEffects" then return true end
    return settings[name] ~= false
end

function Fx.position(object)
    local x, y, z = Fx.ask(object, "getX"), Fx.ask(object, "getY"), Fx.ask(object, "getZ")
    if tonumber(x) == nil or tonumber(y) == nil then return nil end
    return tonumber(x), tonumber(y), tonumber(z) or 0
end

function Fx.addCandidate(found, seen, device, kind, rank, px, py, pz, radius)
    if device == nil or seen[device] == true then return end
    local data = Fx.ask(device, "getDeviceData")
    if data == nil then return end
    if Fx.ask(data, "getIsTelevision") == true or Fx.ask(data, "isTelevision") == true then return end
    local dist = 0
    local x, y, z = nil, nil, nil
    if kind == "world" then
        x, y, z = Fx.position(device)
        if x == nil then return end
        dist = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
        if dist > radius or math.abs(z - pz) > 3 then return end
    end
    seen[device] = true
    found[#found + 1] = { device = device, data = data, kind = kind, rank = rank, dist = dist, x = x, y = y, z = z }
end

function Fx.carried(player, found, seen)
    local px, py, pz = Fx.position(player)
    px, py, pz = px or 0, py or 0, pz or 0
    local radius = Fx.settings.radioRadius
    for _, getter in ipairs({ "getPrimaryHandItem", "getSecondaryHandItem", "getEquipedRadio" }) do
        local item = Fx.ask(player, getter)
        if Fx.isKind(item, "Radio") then Fx.addCandidate(found, seen, item, "held", 1, px, py, pz, radius) end
    end
    local inventory = Fx.ask(player, "getInventory")
    local top = Fx.items(Fx.ask(inventory, "getItems"))
    for _, item in ipairs(top) do
        if Fx.isKind(item, "Radio") then
            Fx.addCandidate(found, seen, item, "inventory", 2, px, py, pz, radius)
        elseif Fx.isKind(item, "InventoryContainer") then
            local inner = Fx.items(Fx.ask(Fx.ask(item, "getInventory"), "getItems"))
            for _, held in ipairs(inner) do
                if Fx.isKind(held, "Radio") then Fx.addCandidate(found, seen, held, "inventory", 2, px, py, pz, radius) end
            end
        end
    end
end

function Fx.worldDevices()
    local manager = type(getZomboidRadio) == "function" and getZomboidRadio() or nil
    if manager == nil then return nil end
    local list = Fx.ask(manager, "getDevices")
    if list == nil then return nil end
    return Fx.items(list, 400)
end

function Fx.scanSquares(px, py, pz, radius)
    local result = {}
    if type(getCell) ~= "function" then return result end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return result end
    local budget, reach = Fx.settings.scanMax, math.min(radius, 12)
    for dx = -reach, reach do
        for dy = -reach, reach do
            budget = budget - 1
            if budget < 0 then return result end
            local ok, square = pcall(cell.getGridSquare, cell, math.floor(px) + dx, math.floor(py) + dy, math.floor(pz))
            if ok and square ~= nil then
                for _, object in ipairs(Fx.items(Fx.ask(square, "getObjects"), 24)) do
                    if Fx.isKind(object, "IsoRadio") then result[#result + 1] = object end
                end
            end
        end
    end
    return result
end

function Fx.radioCandidates(player, x, y, z, radius)
    local found, seen = {}, {}
    radius = tonumber(radius) or Fx.settings.radioRadius
    if player ~= nil then Fx.carried(player, found, seen) end
    local px, py, pz = tonumber(x), tonumber(y), tonumber(z) or 0
    if px == nil and player ~= nil then px, py, pz = Fx.position(player) end
    if px ~= nil then
        local devices = Fx.worldDevices()
        local pool = {}
        if devices ~= nil then
            for _, device in ipairs(devices) do
                if Fx.isKind(device, "IsoRadio") then pool[#pool + 1] = device end
            end
        else
            pool = Fx.scanSquares(px, py, pz, radius)
        end
        for _, device in ipairs(pool) do Fx.addCandidate(found, seen, device, "world", 3, px, py, pz, radius) end
    end
    table.sort(found, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.dist < b.dist
    end)
    return found
end

function Fx.radioUsable(candidate)
    local data = candidate.data
    if Fx.ask(data, "getIsTurnedOn") == true then return true, nil end
    if Fx.ask(data, "getIsBatteryPowered") == true then
        local power = tonumber(Fx.ask(data, "getPower")) or 0
        if power <= 0 then return false, "no_power" end
        return true, nil
    end
    if Fx.ask(data, "canBePoweredHere") ~= true then return false, "no_power" end
    return true, nil
end

function Fx.holdMs(text)
    local s = Fx.settings
    local length = type(text) == "string" and #text or 0
    return math.max(s.holdMin, math.min(s.holdMax, s.holdMin + length * s.holdPerChar))
end

function Fx.speak(candidate, text)
    local device = candidate.device
    if candidate.kind == "world" and type(device.Say) == "function" then
        return pcall(device.Say, device, text)
    end
    if type(device.AddDeviceText) == "function" then
        return pcall(device.AddDeviceText, device, text, 0.85, 0.9, 0.8, nil, nil, -1)
    end
    if type(device.Say) == "function" then return pcall(device.Say, device, text) end
    return false
end

function Fx.radioPlay(candidate, text, frequency)
    local data = candidate.data
    local state = { device = candidate.device, data = data, kind = candidate.kind, wasOn = Fx.ask(data, "getIsTurnedOn") == true,
        channel = tonumber(Fx.ask(data, "getChannel")), volume = tonumber(Fx.ask(data, "getDeviceVolume")) or 0 }
    if not state.wasOn then
        local usable, why = Fx.radioUsable(candidate)
        if not usable then return nil, why end
        if type(data.setIsTurnedOn) ~= "function" or not pcall(data.setIsTurnedOn, data, true) then return nil, "no_switch" end
        if Fx.ask(data, "getIsTurnedOn") ~= true then return nil, "no_power" end
        state.switched = true
        local low, high = tonumber(Fx.ask(data, "getMinChannelRange")), tonumber(Fx.ask(data, "getMaxChannelRange"))
        local wanted = tonumber(frequency)
        if wanted ~= nil and low ~= nil and high ~= nil and wanted >= low and wanted <= high and wanted ~= state.channel
                and type(data.setChannel) == "function" and pcall(data.setChannel, data, wanted) then
            state.tuned = wanted
        end
    end
    if state.volume <= 0 and type(data.setDeviceVolume) == "function" and pcall(data.setDeviceVolume, data, Fx.settings.volume) then
        state.raised = Fx.settings.volume
    end
    local spoke = Fx.speak(candidate, text)
    if spoke ~= true then
        Fx.radioRestore(state)
        return nil, "no_speaker"
    end
    state.holdMs = Fx.holdMs(text)
    return state, nil
end

function Fx.radioRestore(state)
    if type(state) ~= "table" then return false end
    local data = state.data
    if data == nil then return false end
    if state.tuned ~= nil and tonumber(Fx.ask(data, "getChannel")) == state.tuned and state.channel ~= nil
            and type(data.setChannel) == "function" then
        pcall(data.setChannel, data, state.channel)
    end
    if state.raised ~= nil and type(data.setDeviceVolume) == "function"
            and tonumber(Fx.ask(data, "getDeviceVolume")) == state.raised then
        pcall(data.setDeviceVolume, data, state.volume)
    end
    if state.switched == true and Fx.ask(data, "getIsTurnedOn") == true and type(data.setIsTurnedOn) == "function" then
        pcall(data.setIsTurnedOn, data, false)
        Fx.count("radioRestored")
    end
    return true
end

function Fx.audible(data)
    local base = tonumber(Fx.ask(data, "getBaseVolumeRange")) or 10
    local volume = math.max(tonumber(Fx.ask(data, "getDeviceVolume")) or 0, Fx.settings.volume)
    return 0.6 * (5 + base * volume)
end

function Fx.radioIsOn(candidate)
    return candidate ~= nil and Fx.ask(candidate.data, "getIsTurnedOn") == true
end

function Fx.onlyOn(candidates)
    local kept = {}
    for _, candidate in ipairs(candidates) do
        if Fx.radioIsOn(candidate) then kept[#kept + 1] = candidate end
    end
    return kept
end

function Fx.insideHouse(house, x, y)
    return type(house) == "table" and x ~= nil and y ~= nil and tonumber(house.x1) ~= nil and x >= house.x1 and x < house.x2
        and y >= house.y1 and y < house.y2
end

function Fx.houseRadio(player, house, stand)
    if player == nil or type(house) ~= "table" then return nil end
    local sx = stand ~= nil and tonumber(stand.x) or tonumber(house.cx)
    local sy = stand ~= nil and tonumber(stand.y) or tonumber(house.cy)
    local sz = stand ~= nil and tonumber(stand.z) or 0
    if sx == nil or sy == nil then return nil end
    local near = Fx.settings.houseRadius
    for _, candidate in ipairs(Fx.onlyOn(Fx.radioCandidates(player, sx, sy, sz, Fx.settings.radioRadius))) do
        if candidate.kind ~= "world" or candidate.dist <= near or Fx.insideHouse(house, candidate.x, candidate.y) then
            return candidate
        end
    end
    return nil
end

function Fx.radioRun(player, text, options)
    options = type(options) == "table" and options or {}
    local candidates = Fx.radioCandidates(player, options.x, options.y, options.z, options.radius)
    if options.onlyOn == true then candidates = Fx.onlyOn(candidates) end
    if #candidates == 0 then return nil, "no_device", nil end
    local reason, first = "no_power", nil
    for _, candidate in ipairs(candidates) do
        local state, why = Fx.radioPlay(candidate, text, options.frequency)
        if state ~= nil then
            if candidate.kind == "world" and candidate.dist > Fx.audible(candidate.data) then
                state.far = true
                Fx.count("radioFar")
                Fx.halo(player, text)
            end
            return state, nil, candidate
        end
        first = first or candidate
        if why ~= "no_power" then reason = why end
    end
    return nil, reason, first
end

function Fx.halo(player, text)
    if player == nil or type(text) ~= "string" then return false end
    if HaloTextHelper ~= nil and type(HaloTextHelper.addText) == "function" then
        return pcall(HaloTextHelper.addText, player, text)
    end
    return false
end

function Fx.playSound(name, x, y, z)
    if type(name) ~= "string" or tonumber(x) == nil or tonumber(y) == nil then return false end
    if type(getSoundManager) ~= "function" then return false end
    local manager = getSoundManager()
    if manager == nil or type(manager.PlayWorldSoundImpl) ~= "function" then return false end
    local ok = pcall(manager.PlayWorldSoundImpl, manager, name, false, math.floor(x), math.floor(y),
        math.floor(tonumber(z) or 0), 0, 20, 1, false)
    return ok
end

function Fx.handle(args, player)
    if type(args) ~= "table" then return false end
    if type(isServer) == "function" and isServer() == true and not (type(isClient) == "function" and isClient() == true) then
        return false
    end
    if player == nil and type(getSpecificPlayer) == "function" then player = getSpecificPlayer(0) end
    if args.kind == "sound" then return Fx.playSound(args.name, args.x, args.y, args.z) end
    if args.kind == "radio" then
        local id = tostring(args.id)
        local state, reason, candidate = Fx.radioRun(player, tostring(args.text or ""), args)
        Fx.last = { id = id, ok = state ~= nil, reason = reason, kind = candidate ~= nil and candidate.kind or nil,
            x = candidate ~= nil and candidate.x or nil, y = candidate ~= nil and candidate.y or nil }
        if state == nil then
            Fx.halo(player, tostring(args.text or ""))
            return false
        end
        Fx.active[id] = state
        return true
    end
    if args.kind == "radioRestore" then
        local id = tostring(args.id)
        local state = Fx.active[id]
        Fx.active[id] = nil
        return Fx.radioRestore(state)
    end
    if args.kind == "text" then return Fx.halo(player, tostring(args.text or "")) end
    return false
end

return Fx
