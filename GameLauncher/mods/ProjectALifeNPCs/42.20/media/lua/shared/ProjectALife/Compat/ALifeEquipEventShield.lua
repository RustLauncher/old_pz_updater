ProjectALife = ProjectALife or {}

local Shield = ProjectALife.EquipEventShield or {
    events = { "OnEquipPrimary", "OnEquipSecondary" },
    installed = {},
    wrappers = {},
    metrics = { wrapped = 0, filtered = 0, removed = 0, checkFaults = 0 },
}
Shield.cleaning = Shield.cleaning or setmetatable({}, { __mode = "k" })
ProjectALife.EquipEventShield = Shield

function Shield.withCleanup(character, callback, ...)
    if character == nil then return callback(character, ...) end
    local previous = Shield.cleaning[character]
    Shield.cleaning[character] = true
    local ok, result, reason = pcall(callback, character, ...)
    Shield.cleaning[character] = previous
    if not ok then error(result, 0) end
    return result, reason
end

function Shield.isOurs(character)
    if character == nil then return false end
    local zombie = false
    pcall(function() zombie = character:isZombie() == true end)
    if not zombie then return false end
    if Shield.cleaning[character] then return true end
    local ours = false
    pcall(function()
        local data = character:getModData()
        ours = type(data) == "table"
            and (data.ProjectALifeOwned == true or data.ProjectALifeActor == true
                or data.ProjectALifeCorpseOf ~= nil)
    end)
    if ours then return true end

    pcall(function()
        ours = tostring(character:GetVariable("ALifeActor")) == "true"
    end)
    return ours
end

function Shield.wrap(listener)
    if type(listener) ~= "function" then return listener end
    local existing = Shield.wrappers[listener]
    if existing ~= nil then return existing end
    local wrapper = function(character, ...)
        local ours = false
        local ok = pcall(function() ours = Shield.isOurs(character) end)
        if not ok then

            Shield.metrics.checkFaults = Shield.metrics.checkFaults + 1
        elseif ours then
            Shield.metrics.filtered = Shield.metrics.filtered + 1
            return nil
        end
        return listener(character, ...)
    end
    Shield.wrappers[listener] = wrapper
    return wrapper
end

function Shield.installOn(name)
    if type(Events) ~= "table" then return false end
    local event = Events[name]
    if type(event) ~= "table" or event.Add == nil or event.Remove == nil then return false end

    local rawAdd = rawget(event, "ALifeRawAdd") or event.Add
    local rawRemove = rawget(event, "ALifeRawRemove") or event.Remove
    rawset(event, "ALifeRawAdd", rawAdd)
    rawset(event, "ALifeRawRemove", rawRemove)

    local wrappers = rawget(event, "ALifeWrappers")
    if type(wrappers) ~= "table" then
        wrappers = Shield.wrappers
        rawset(event, "ALifeWrappers", wrappers)
    end
    Shield.wrappers = wrappers
    event.Add = function(first, second)

        local listener = first
        if first == event then listener = second end
        Shield.metrics.wrapped = Shield.metrics.wrapped + 1
        return rawAdd(Shield.wrap(listener))
    end
    event.Remove = function(first, second)
        local listener = first
        if first == event then listener = second end
        Shield.metrics.removed = Shield.metrics.removed + 1
        return rawRemove(Shield.wrappers[listener] or listener)
    end
    Shield.installed[name] = true
    return true
end

function Shield.install()
    local names = {}
    for _, name in ipairs(Shield.events) do
        if Shield.installOn(name) then names[#names + 1] = name end
    end
    if #names > 0 then
        print("[A-Life] compat: equip-event shield on " .. table.concat(names, ", ")
            .. " -- protects later registrations; earlier equip hooks may still receive A-Life NPCs")
    end
    return #names
end

function Shield.guardFishing()
    local handler = type(Fishing) == "table" and Fishing.Handler or nil
    if type(handler) ~= "table" or type(handler.handleFishing) ~= "function" or handler.alifeGuarded == true then return false end
    local original = handler.handleFishing
    handler.handleFishing = function(character, ...)
        local zombie = false
        pcall(function() zombie = character ~= nil and character:isZombie() == true end)
        if zombie then
            Shield.metrics.filtered = Shield.metrics.filtered + 1
            return nil
        end
        return original(character, ...)
    end
    handler.alifeGuarded = true
    return true
end

Shield.install()
Shield.guardFishing()
if type(Events) == "table" then
    for _, name in ipairs({ "OnGameBoot", "OnGameStart", "OnNewGame" }) do
        if Events[name] ~= nil and type(Events[name].Add) == "function" then Events[name].Add(Shield.guardFishing) end
    end
end

return Shield
