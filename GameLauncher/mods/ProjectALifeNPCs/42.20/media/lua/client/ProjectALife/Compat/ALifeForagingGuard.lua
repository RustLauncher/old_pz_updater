ProjectALife = ProjectALife or {}

local Guard = {
    installed = false,
    metrics = { repaired = 0, faults = 0 },
}
ProjectALife.ForagingGuard = Guard

function Guard.reset()
    Guard.metrics = { repaired = 0, faults = 0 }
end

function Guard.repairIcon(icon)
    if type(icon) ~= "table" or icon.itemList ~= nil then return false end
    if icon.itemDef == nil or type(icon.getItemList) ~= "function" then return false end
    local ok = pcall(function()
        if type(icon.initItem) == "function" then icon:initItem() end
        if type(icon.initItemCount) == "function" then icon:initItemCount() end
        icon:getItemList()
    end)
    if not ok or icon.itemList == nil then
        Guard.metrics.faults = Guard.metrics.faults + 1
        return false
    end
    Guard.metrics.repaired = Guard.metrics.repaired + 1
    return true
end

function Guard.installIcons()
    local done = false
    if type(ISBaseIcon) == "table" and type(ISBaseIcon.spotIcon) == "function"
            and rawget(ISBaseIcon, "alifeSpotWrapped") ~= true then
        local original = ISBaseIcon.spotIcon
        ISBaseIcon.spotIcon = function(icon, ...)
            local ok, result = pcall(original, icon, ...)
            Guard.repairIcon(icon)

            if not ok then error(result, 0) end
            return result
        end
        rawset(ISBaseIcon, "alifeSpotWrapped", true)
        done = true
    end
    if type(ISForageIcon) == "table" and type(ISForageIcon.doForage) == "function"
            and rawget(ISForageIcon, "alifeForageWrapped") ~= true then
        local original = ISForageIcon.doForage
        ISForageIcon.doForage = function(icon, ...)
            Guard.repairIcon(icon)
            if type(icon) == "table" and icon.itemList == nil then return false end
            return original(icon, ...)
        end
        rawset(ISForageIcon, "alifeForageWrapped", true)
        done = true
    end
    return done
end

function Guard.install()
    if Guard.installIcons() then Guard.installed = true end
    return Guard.installed
end

if type(Events) == "table" and Events.OnGameStart ~= nil
        and type(Events.OnGameStart.Add) == "function" then
    Events.OnGameStart.Add(Guard.install)
end
Guard.install()

return Guard
