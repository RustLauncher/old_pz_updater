require "ProjectALife/Core/ALifeOrphanGuard"

ProjectALife = ProjectALife or {}

local RecycledClothing = { metrics = { cleared = 0 } }
ProjectALife.RecycledClothing = RecycledClothing

local function onServer()
    return type(isServer) == "function" and isServer() == true
end

function RecycledClothing.undressed(zombie)
    if zombie == nil or not onServer() then return false end
    local ok, undressed = pcall(function()
        return zombie:isPersistentOutfitInit() == false and zombie:isDead() == false
            and zombie:isUsingWornItems() == false
    end)
    if not ok or undressed ~= true then return false end
    local markedOk, marked = pcall(ProjectALife.OrphanGuard.marked, zombie)
    return markedOk and marked == false
end

function RecycledClothing.clearOnCreate(zombie)
    if not RecycledClothing.undressed(zombie) then return false end
    local ok, cleared = pcall(function()
        local visuals = zombie:getItemVisuals()
        if visuals == nil or visuals:size() == 0 then return false end
        visuals:clear()
        return true
    end)
    if not ok or cleared ~= true then return false end
    RecycledClothing.metrics.cleared = RecycledClothing.metrics.cleared + 1
    return true
end

if type(Events) == "table" and Events.OnZombieCreate ~= nil then
    Events.OnZombieCreate.Add(RecycledClothing.clearOnCreate)
end

return RecycledClothing
