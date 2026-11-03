ProjectALife = ProjectALife or {}
if ProjectALife.StashRoom then return ProjectALife.StashRoom end

local Room = {
    metrics = { checked = 0, stashFullRefused = 0, groundFallback = 0, apiMissing = 0 },
}
ProjectALife.StashRoom = Room

function Room.reset()
    Room.metrics = { checked = 0, stashFullRefused = 0, groundFallback = 0, apiMissing = 0 }
end

function Room.fits(container, item, owner)
    if container == nil or item == nil then return false end
    local metrics = Room.metrics
    metrics.checked = metrics.checked + 1
    if type(container.hasRoomFor) ~= "function" then
        metrics.apiMissing = metrics.apiMissing + 1
        return true
    end
    local ok, room = pcall(container.hasRoomFor, container, owner, item)
    if ok and room == false then
        metrics.stashFullRefused = metrics.stashFullRefused + 1
        return false
    end
    return true
end

function Room.place(container, item, owner)
    if not Room.fits(container, item, owner) then return false, "full" end
    local ok = pcall(container.AddItem, container, item)
    if not ok then return false, "add_failed" end
    if type(sendAddItemToContainer) == "function" then pcall(sendAddItemToContainer, container, item) end
    return true
end

return Room
