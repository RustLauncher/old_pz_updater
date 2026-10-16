require "ProjectALife/Compat/ALifeModCompat"

ProjectALife = ProjectALife or {}
if ProjectALife.CompatRegistry ~= nil then return ProjectALife.CompatRegistry end

local Registry = { entries = {}, order = {}, started = false, depth = 0,
    metrics = { applied = 0, absent = 0, disabled = 0, failed = 0, callbackFailed = 0, undoFailed = 0,
        readFailed = 0, forwardFailed = 0, partnerFailed = 0 } }
ProjectALife.CompatRegistry = Registry

function Registry.register(spec)
    if Registry.started then return false, "started" end
    if type(spec) ~= "table" or type(spec.id) ~= "string" or not string.match(spec.id, "^[%w_]+$")
            or type(spec.mods) ~= "table" or type(spec.detect) ~= "function" or type(spec.apply) ~= "function"
            or (spec.undo ~= nil and type(spec.undo) ~= "function") then return false, "invalid" end
    if spec.phase ~= "gameStart" and spec.phase ~= "server" and spec.phase ~= "client" then return false, "phase" end
    if Registry.entries[spec.id] ~= nil then return false, "duplicate" end
    local saved = { id = spec.id, mods = {}, phase = spec.phase, detect = spec.detect, apply = spec.apply,
        undo = spec.undo, option = spec.option or ("Compat_" .. spec.id) }
    for _, id in ipairs(spec.mods) do
        if type(id) ~= "string" or id == "" then return false, "mod_id" end
        saved.mods[#saved.mods + 1] = id
    end
    Registry.entries[spec.id] = { spec = saved, state = "pending" }
    Registry.order[#Registry.order + 1] = spec.id
    return true
end

function Registry.status(id)
    local entry = Registry.entries[id]
    if entry == nil then return "absent", "realm" end
    return entry.state, entry.reason
end

function Registry.note(entry)
    print("[A-Life] compat adapter " .. entry.spec.id .. "=" .. entry.state
        .. (entry.reason ~= nil and (" (" .. entry.reason .. ")") or "")
        .. (entry.state == "failed" and entry.error ~= nil and (": " .. string.sub(entry.error, 1, 300)) or ""))
end

function Registry.partnerError(id, failure)
    local entry = Registry.entries[id]
    if entry == nil then return end
    Registry.metrics.partnerFailed = Registry.metrics.partnerFailed + 1
    entry.partnerErrors = (entry.partnerErrors or 0) + 1
    if entry.partnerErrors > 1 then return end
    entry.partnerError = tostring(failure)
    print("[A-Life] compat adapter " .. id .. " partner mod raised an error, adapter stays on: "
        .. string.sub(entry.partnerError, 1, 300))
end

function Registry.fail(id, stage, failure)
    local entry = Registry.entries[id]
    if entry == nil or entry.state == "failed" then return false end
    entry.state, entry.reason, entry.error = "failed", stage, tostring(failure)
    Registry.metrics.failed = Registry.metrics.failed + 1
    if stage == "callback" then Registry.metrics.callbackFailed = Registry.metrics.callbackFailed + 1 end
    if entry.attempted and type(entry.spec.undo) == "function" then
        local ok = pcall(entry.spec.undo)
        if not ok then Registry.metrics.undoFailed = Registry.metrics.undoFailed + 1 end
    end
    if entry.logged then Registry.note(entry) end
    local compat = ProjectALife.ModCompat
    if compat ~= nil then compat.reported = false end
    return false
end

function Registry.pack(...)
    return { n = select("#", ...), ... }
end

function Registry.leave(...)
    Registry.depth = Registry.depth - 1
    return ...
end

function Registry.guard(original)
    return function(...)
        Registry.depth = Registry.depth + 1
        return Registry.leave(original(...))
    end
end

function Registry.settle(id, depth, ok, ...)
    if ok then return ... end
    local failure = (...)
    if Registry.depth > depth then
        Registry.depth = depth
        Registry.partnerError(id, failure)
        error(failure, 0)
    end
    Registry.fail(id, "callback", failure)
    return nil
end

function Registry.call(id, callback, ...)
    local entry = Registry.entries[id]
    if entry == nil or entry.state ~= "applied" then return nil end
    if type(callback) ~= "function" then Registry.fail(id, "callback", "missing function"); return nil end
    local depth = Registry.depth
    return Registry.settle(id, depth, pcall(callback, ...))
end

function Registry.forward(callback, ...)
    return callback(...)
end

function Registry.wrap(id, owner, key, callback)
    local entry = Registry.entries[id]
    if entry == nil or type(owner) ~= "table" or type(owner[key]) ~= "function"
            or type(callback) ~= "function" then return false end
    local original = owner[key]
    local guarded = Registry.guard(original)
    local wrapper = function(...)
        if entry.state ~= "applied" then return original(...) end
        return Registry.call(id, callback, guarded, ...)
    end
    entry.patches = entry.patches or {}
    entry.patches[#entry.patches + 1] = { owner = owner, key = key, original = original, wrapper = wrapper }
    owner[key] = wrapper
    return true
end

function Registry.restore(id)
    local entry = Registry.entries[id]
    for index = #(entry and entry.patches or {}), 1, -1 do
        local patch = entry.patches[index]
        if patch.owner[patch.key] == patch.wrapper then patch.owner[patch.key] = patch.original end
    end
end

function Registry.ask(object, method, ...)
    if (type(object) ~= "table" and type(object) ~= "userdata") or type(object[method]) ~= "function" then return nil end
    local ok, result = pcall(object[method], object, ...)
    if not ok then Registry.metrics.readFailed = Registry.metrics.readFailed + 1; return nil end
    return result
end

function Registry.uidOf(character)
    if Registry.ask(character, "hasModData") ~= false then
        local data = Registry.ask(character, "getModData")
        if type(data) == "table" and (data.ProjectALifeOwned == true or data.ProjectALifeActor == true) then
            return data.ProjectALifeUID or true
        end
    end
    local uid = Registry.ask(character, "GetVariable", "ALifeUID")
    if uid ~= nil and uid ~= "" then return uid end
    return nil
end

function Registry.isOurs(character)
    return Registry.uidOf(character) ~= nil
end

function Registry.each(list, callback, stoppable)
    if list == nil then return end
    if type(list.size) == "function" and type(list.get) == "function" then
        for index = 0, (tonumber(Registry.ask(list, "size")) or 0) - 1 do
            if callback(Registry.ask(list, "get", index)) == true and stoppable == true then return end
        end
    else
        local array = Registry.ask(list, "toArray")
        if type(array) == "table" then
            for _, value in pairs(array) do
                if callback(value) == true and stoppable == true then return end
            end
        end
    end
end

function Registry.run(entry, active)
    local spec = entry.spec
    local client = type(isClient) == "function" and isClient() == true
    local server = type(isServer) == "function" and isServer() == true
    local values = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(values) == "table" and values[spec.option] == false then
        entry.state, entry.reason = "disabled", "option"
    elseif (spec.phase == "server" and client) or (spec.phase == "client" and server) then
        entry.state, entry.reason = "disabled", "realm"
    else
        local present = #spec.mods == 0
        for _, id in ipairs(spec.mods) do
            if active[id] == true or active[string.lower(id)] == true then present = true end
        end
        if not present then
            entry.state, entry.reason = "absent", "mod"
        else
            local ok, found = pcall(spec.detect)
            if not ok then
                Registry.fail(spec.id, "detect", found)
            elseif not found then
                entry.state, entry.reason = "absent", "hook"
            else
                entry.attempted = true
                local applied, result = pcall(spec.apply)
                if not applied or result == false then
                    Registry.fail(spec.id, "apply", result)
                else
                    entry.state = "applied"
                end
            end
        end
    end
    if entry.state ~= "failed" then Registry.metrics[entry.state] = Registry.metrics[entry.state] + 1 end
    Registry.note(entry)
    entry.logged = true
end

function Registry.start()
    if Registry.started then return false end
    Registry.started = true
    local compat = ProjectALife.ModCompat
    compat.refreshActiveSet()
    local active = compat.activeSet()
    table.sort(Registry.order)
    for _, id in ipairs(Registry.order) do Registry.run(Registry.entries[id], active) end
    return true
end

function Registry.qaLine()
    local parts = {}
    for _, id in ipairs(Registry.order) do parts[#parts + 1] = id .. "=" .. Registry.entries[id].state end
    parts[#parts + 1] = "callbackFailed=" .. tostring(Registry.metrics.callbackFailed)
    parts[#parts + 1] = "partnerFailed=" .. tostring(Registry.metrics.partnerFailed)
    parts[#parts + 1] = "undoFailed=" .. tostring(Registry.metrics.undoFailed)
    return "[ALIFE-QA] Compat: " .. table.concat(parts, " ")
end

if type(Events) == "table" then
    for _, name in ipairs({ "OnGameStart", "OnServerStarted" }) do
        local event = Events[name]
        if event ~= nil and type(event.Add) == "function" then event.Add(Registry.start) end
    end
end

return Registry
