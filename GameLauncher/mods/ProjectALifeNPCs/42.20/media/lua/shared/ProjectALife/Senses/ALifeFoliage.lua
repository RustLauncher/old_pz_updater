ProjectALife = ProjectALife or {}

local Foliage = {
    prefixes = { "vegetation_foliage", "vegetation_ornamental", "vegetation_trees", "f_bushes", "e_" },

    verdicts = {},
}
ProjectALife.Foliage = Foliage

function Foliage.named(name)
    name = tostring(name or "")
    local known = Foliage.verdicts[name]
    if known ~= nil then return known end
    local found = false
    for _, prefix in ipairs(Foliage.prefixes) do
        if string.sub(name, 1, #prefix) == prefix then
            found = true
            break
        end
    end
    Foliage.verdicts[name] = found
    return found
end

Foliage.undergrowth = { "vegetation_groundcover", "vegetation_indoor" }

function Foliage.clearable(name)
    if Foliage.named(name) then return true end
    name = tostring(name or "")
    for _, prefix in ipairs(Foliage.undergrowth) do
        if string.sub(name, 1, #prefix) == prefix then return true end
    end
    return false
end

function Foliage.on(square)
    if square == nil or square.getObjects == nil then return false end
    local objects = square:getObjects()
    if objects == nil or objects.size == nil or objects.get == nil then return false end
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        local sprite = object ~= nil and object.getSprite ~= nil and object:getSprite() or nil
        if sprite ~= nil and sprite.getName ~= nil and Foliage.named(sprite:getName()) then
            return true
        end
    end
    return false
end

return Foliage
