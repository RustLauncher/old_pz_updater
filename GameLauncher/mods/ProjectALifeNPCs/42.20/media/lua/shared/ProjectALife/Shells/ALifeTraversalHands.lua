ProjectALife = ProjectALife or {}
local Hands = { entries = setmetatable({}, { __mode = "k" }) }
ProjectALife.TraversalHands = Hands

local function matches(shell, entry)
    local data = shell:getModData()
    return entry.uid == data.ProjectALifeUID and entry.generation == data.ProjectALifeGeneration
end

local function assign(shell, setter, item)
    return pcall(function() shell[setter](shell, item) end)
end

function Hands.held(shell)
    local entry = Hands.entries[shell]
    if entry == nil then return false end
    local guard = ProjectALife.AIFence
    if not matches(shell, entry) or shell:isDead() or not guard or not guard.authorityFor(shell) then
        Hands.entries[shell] = nil
        return false
    end
    return entry.held == true
end

function Hands.prepare(shell, force)
    if not (type(isClient) == "function" and isClient()) then return false end
    if type(instanceof) == "function" and instanceof(shell, "IsoPlayer") then return false end
    local data = shell:getModData()
    local guard = ProjectALife.AIFence
    if data.ProjectALifeActor ~= true or not guard or not guard.authorityFor(shell) then
        Hands.entries[shell] = nil
        return false
    end
    if shell:isDead() then Hands.entries[shell] = nil; return false end
    local entry = Hands.entries[shell]
    if entry ~= nil and not matches(shell, entry) then
        Hands.entries[shell] = nil
        entry = nil
    end
    if not force and data.ProjectALifePathActive ~= true and (entry == nil or not entry.held) then return false end
    local now = getTimestampMs()
    local climbing = string.find(string.lower(tostring(shell:getActionStateName() or "")), "climb", 1, true) ~= nil
    local moving = data.ProjectALifePathActive == true
    local needed = force == true or (entry ~= nil and entry.held and (climbing or now < (entry.untilMs or 0)))
    if moving and not climbing then
        local square = shell:getCurrentSquare()
        if square ~= nil and square.getAdjacentSquare ~= nil and IsoDirections ~= nil then
            entry = entry or { uid = data.ProjectALifeUID, generation = data.ProjectALifeGeneration }

            if entry.square ~= square or now >= (entry.checkAtMs or 0) then
                entry.square, entry.checkAtMs, entry.nearWindow = square, now + 200, false
                for _, direction in ipairs({ IsoDirections.N, IsoDirections.E, IsoDirections.S, IsoDirections.W }) do
                    local other = square:getAdjacentSquare(direction)
                    if other ~= nil and (square:getWindowTo(other) ~= nil
                            or square:getWindowFrameTo(other) ~= nil
                            or square:getWindowThumpableTo(other) ~= nil) then
                        entry.nearWindow = true
                        break
                    end
                end
            end
            needed = needed or entry.nearWindow
            Hands.entries[shell] = entry
        end
    end
    if needed then
        entry = entry or { uid = data.ProjectALifeUID, generation = data.ProjectALifeGeneration }
        Hands.entries[shell] = entry
        if force then entry.untilMs = now + 1200 end
        if not entry.held then
            entry.primary, entry.secondary = shell:getPrimaryHandItem(), shell:getSecondaryHandItem()
            entry.held = true
        end
        if shell:getPrimaryHandItem() ~= nil then assign(shell, "setPrimaryHandItem", nil) end
        if shell:getSecondaryHandItem() ~= nil then assign(shell, "setSecondaryHandItem", nil) end
        return true
    end
    if entry ~= nil and entry.held then
        local inventory = shell:getInventory()

        if shell:getPrimaryHandItem() == nil and entry.primary ~= nil and inventory:contains(entry.primary) then
            assign(shell, "setPrimaryHandItem", entry.primary)
        end
        if shell:getSecondaryHandItem() == nil and entry.secondary ~= nil
                and shell:getPrimaryHandItem() == entry.primary and inventory:contains(entry.secondary) then
            assign(shell, "setSecondaryHandItem", entry.secondary)
        end
        entry.held, entry.primary, entry.secondary = false, nil, nil
    end
    return false
end

return Hands
