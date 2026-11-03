ItemCondition = ItemCondition or {}
ItemCondition.UI = ItemCondition.UI or {}

local UI = ItemCondition.UI
UI.Textures = UI.Textures or {
    Vertical = {},
    Horizontal = {}
}

local TEXTURE_ROOT = "media/ui/qdx/item_condition/"

local function loadTextures()
    for i = 0, 10 do
        UI.Textures.Vertical[i] = getTexture(TEXTURE_ROOT .. "circle_v_" .. tostring(i) .. ".png")
        UI.Textures.Horizontal[i] = getTexture(TEXTURE_ROOT .. "circle_h_" .. tostring(i) .. ".png")
    end
end

loadTextures()

local function clamp01(value)
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

function UI:GetTexture(horizontal, index)
    return (horizontal and UI.Textures.Horizontal or UI.Textures.Vertical)[index]
end

function UI:DrawRect(ui, x, y, width, height, alpha, color)
    if not ui or not color or width <= 0 or height <= 0 or alpha <= 0 then
        return
    end

    ui:drawRect(x, y, width, height, alpha, color.r, color.g, color.b)
end

function UI:DrawVerticalProgress(ui, progress, x, y, width, height, padding, alpha, color)
    if not ui or not color or alpha <= 0 then return end

    progress = clamp01(progress)
    padding = math.max(0, padding or 0)

    local innerWidth = math.max(0, width - padding * 2)
    local innerHeight = math.max(0, height - padding * 2)
    if innerWidth <= 0 or innerHeight <= 0 then return end

    local filledHeight = math.floor(innerHeight * progress)
    if progress > 0 and filledHeight < 1 then
        filledHeight = 1
    end
    if filledHeight <= 0 then return end

    self:DrawRect(
        ui,
        x + padding,
        y + padding + innerHeight - filledHeight,
        innerWidth,
        filledHeight,
        alpha,
        color
    )
end

function UI:DrawHorizontalProgress(ui, progress, x, y, width, height, padding, alpha, color)
    if not ui or not color or alpha <= 0 then return end

    progress = clamp01(progress)
    padding = math.max(0, padding or 0)

    local innerWidth = math.max(0, width - padding * 2)
    local innerHeight = math.max(0, height - padding * 2)
    if innerWidth <= 0 or innerHeight <= 0 then return end

    local filledWidth = math.floor(innerWidth * progress)
    if progress > 0 and filledWidth < 1 then
        filledWidth = 1
    end
    if filledWidth <= 0 then return end

    self:DrawRect(
        ui,
        x + padding,
        y + padding,
        filledWidth,
        innerHeight,
        alpha,
        color
    )
end

function UI:DrawCircle(ui, texture, x, y, width, height, alpha, color)
    if not ui or not texture or not color or alpha <= 0 then
        return
    end

    ui:drawTextureScaled(
        texture, x, y, width, height,
        alpha, color.r, color.g, color.b
    )
end

function UI:DrawItemProgress(ui, item, mode, opacity, x, y, width, height, padding)
    if not ui or not item or mode == nil or mode <= 1 or opacity <= 0 then
        return
    end

    local multicolor = mode == 3 or mode == 5
    local horizontal = mode >= 4

    local condition, _, color =
        ItemCondition.Util:GetDisplayData(item, multicolor)

    if condition == nil or not color then
        return
    end

    if horizontal then
        self:DrawHorizontalProgress(ui, condition, x, y, width, height, padding, opacity, color)
    else
        self:DrawVerticalProgress(ui, condition, x, y, width, height, padding, opacity, color)
    end
end

function UI:DrawEquippedItemProgress(ui, item, mode, opacity, x, y, width, height)
    if not ui or not item or mode == nil or mode <= 1 or opacity <= 0 then
        return
    end

    local multicolor = mode == 3 or mode == 5
    local horizontal = mode >= 4

    local _, textureIndex, color =
        ItemCondition.Util:GetDisplayData(item, multicolor)

    if textureIndex == nil or not color then
        return
    end

    local texture = self:GetTexture(horizontal, textureIndex)
    if texture then
        self:DrawCircle(ui, texture, x, y, width, height, opacity, color)
    end
end
