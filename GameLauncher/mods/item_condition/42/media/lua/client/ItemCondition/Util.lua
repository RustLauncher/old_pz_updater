ItemCondition = ItemCondition or {}
ItemCondition.Util = ItemCondition.Util or {}

local Util = ItemCondition.Util
local Config = ItemCondition.Config

local clamp = math.max

local function clamp01(value)
    if type(value) ~= "number" then
        return nil
    end
    if value < 0.0 then
        return 0.0
    end
    if value > 1.0 then
        return 1.0
    end
    return value
end

local function call(object, methodName, ...)
    if not object then
        return nil
    end

    local method = object[methodName]
    if type(method) ~= "function" then
        return nil
    end

    local ok, result = pcall(method, object, ...)
    if ok then
        return result
    end

    return nil
end

local function fullType(item)
    local value = call(item, "getFullType")
    return type(value) == "string" and value or nil
end

Util.TypeCache = Util.TypeCache or {}

function Util:GetItemKind(item)
    if not item then
        return nil
    end

    local typeName = fullType(item)
    if typeName then
        local cached = self.TypeCache[typeName]
        if cached ~= nil then
            return cached == false and nil or cached
        end
    end

    local kind = nil

    if instanceof(item, "HandWeapon") then
        kind = "condition"
    elseif type(item.isWaterSource) == "function" then
        local ok, result = pcall(item.isWaterSource, item)
        if ok and result == true then
            kind = "water"
        end
    end

    if not kind and type(item.getLightDistance) == "function" then
        local ok, distance = pcall(item.getLightDistance, item)
        if ok and type(distance) == "number" and distance ~= 0 then
            kind = "light"
        end
    end

    if typeName then
        self.TypeCache[typeName] = kind or false
    end

    return kind
end

function Util:GetItemCondition(item)
    local kind = self:GetItemKind(item)
    if not kind then
        return nil
    end

    if kind == "condition" then
        local maxCondition = call(item, "getConditionMax")
        local condition = call(item, "getCondition")

        if type(maxCondition) == "number"
            and maxCondition > 0
            and type(condition) == "number" then
            return clamp01(condition / maxCondition)
        end

        return nil
    end

    if kind == "water" then
        local fluidContainer = call(item, "getFluidContainer")

        if fluidContainer then
            local filledRatio = call(fluidContainer, "getFilledRatio")
            if type(filledRatio) == "number" then
                return clamp01(filledRatio)
            end

            local amount = call(fluidContainer, "getAmount")
            local capacity = call(fluidContainer, "getCapacity")
            if type(amount) == "number" and type(capacity) == "number" and capacity > 0 then
                return clamp01(amount / capacity)
            end
        end

        local usedDelta = call(item, "getUsedDelta")
        if type(usedDelta) == "number" then
            return clamp01(usedDelta)
        end

        return nil
    end

    if kind == "light" then
        local uses = call(item, "getCurrentUsesFloat")
        if type(uses) == "number" then
            return clamp01(uses)
        end
    end

    return nil
end

function Util:GetItemConfigType(item)
    return self:GetItemKind(item) == "water" and Config.TypeWater or Config.TypeDefault
end

function Util:GetProgressIndex(progress)
    progress = clamp01(progress)
    if progress == nil then
        return nil
    end

    local index = math.ceil(progress * 10)
    if index < 0 then
        return 0
    elseif index > 10 then
        return 10
    end
    return index
end

function Util:GetProgressColor(colors, progress)
    if not colors then
        return nil
    end

    progress = clamp01(progress)
    if progress == nil then
        return nil
    end

    local bucket = math.floor(progress * 10 + 0.000001)
    if bucket >= 10 then return colors.P100 end
    if bucket == 9 then return colors.P090 end
    if bucket == 8 then return colors.P080 end
    if bucket == 7 then return colors.P070 end
    if bucket == 6 then return colors.P060 end
    if bucket == 5 then return colors.P050 end
    if bucket == 4 then return colors.P040 end
    if bucket == 3 then return colors.P030 end
    if bucket == 2 then return colors.P020 end
    if bucket == 1 then return colors.P010 end
    return colors.P000
end

function Util:GetDisplayData(item, multicolor)
    local condition = self:GetItemCondition(item)
    if condition == nil then
        return nil
    end

    local configType = self:GetItemConfigType(item)
    if not configType or not configType.Colors then
        return nil
    end

    local colors = configType.Colors
    local color = multicolor and self:GetProgressColor(colors, condition) or colors.P100
    local textureIndex = self:GetProgressIndex(condition)

    if not color or textureIndex == nil then
        return nil
    end

    return condition, textureIndex, color
end
