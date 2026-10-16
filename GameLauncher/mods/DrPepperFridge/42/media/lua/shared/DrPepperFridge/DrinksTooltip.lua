-- Client presentation only; old description keys are the only metadata migrated.
if isServer and isServer() then return end
require "DrPepperFridge/Drinks"

local M = DrPepperDrinks
local order = { "Thirst", "Hunger", "Fatigue", "Stress", "Unhappiness", "Boredom" }

local function number(value)
    return tostring(math.floor(value * 100 + 0.5) / 100)
end

local function label(name)
    return getText("Tooltip_food_" .. name):gsub("[:%s]+$", "")
end

local function ownCan(item)
    local id = item and item.getFullType and item:getFullType()
    return id == "DrPepper.CanRegular" or id == "DrPepper.CanDiet"
end

function M.refreshCanTooltip(item)
    if not ownCan(item) or not item.getTooltip then return end
    local key = item:getTooltip()
    if key == "Tooltip_DrPepperCanRegular" or key == "Tooltip_DrPepperCanDiet" then
        -- Item.InstanceItem used setTooltip in 1.0.0, which stored the old key
        -- in modData. Clearing only our keys also fixes already saved cans.
        item:setTooltip(nil)
    end
end

-- Native portions are fractions of the drink still inside, not a full can.
function M.tooltipEffects(container, portion)
    local regular, diet = M.amounts(container)
    local fraction = math.max(0, math.min(1, tonumber(portion) or 1))
    return M.effectsForVolumes(regular * fraction, diet * fraction)
end

local function isMixture(container)
    local regular, diet = M.amounts(container)
    return (regular > 0.0000001 and diet > 0.0000001)
        or container:getAmount() - regular - diet > 0.0000001
end

local function heading(container, portion)
    if isMixture(container) then return getText("Tooltip_DrPepperDrinkContribution") end
    return getText(portion and portion < 1 and "Tooltip_DrPepperDrinkPortion" or "Tooltip_DrPepperDrinkRemaining")
end

local function effectLines(container, portion)
    local lines = { heading(container, portion) }
    local effects = M.tooltipEffects(container, portion)
    for _, name in ipairs(order) do
        if effects[name] >= 0.005 then
            lines[#lines + 1] = label(name) .. ": -" .. number(effects[name])
        end
    end
    if #lines == 1 then lines[2] = getText("Tooltip_DrPepperDrinkNoEffects") end
    return lines
end

local function annotateOption(option, container, portion)
    local tooltip = option.toolTip or ISInventoryPaneContextMenu.addToolTip()
    -- Preserve native sealed/too-full reasons and replace only our own suffix.
    local old = tooltip.description or ""
    local previous = option.drPepperTooltipSuffix
    if previous and old:sub(-#previous) == previous then old = old:sub(1, #old - #previous) end
    local suffix = (old ~= "" and " <LINE> " or "") .. table.concat(effectLines(container, portion), " <LINE> ")
    tooltip.description = old .. suffix
    option.drPepperTooltipSuffix = suffix
    option.toolTip = tooltip
end

local function annotate(player, context)
    if not context or not context.options or not ISInventoryPaneContextMenu then return end
    for _, option in ipairs(context.options) do
        local item = option.itemForTexture
        local container = item and item.getFluidContainer and item:getFluidContainer()
        local regular, diet = M.amounts(container)
        if regular + diet > 0 then
            local submenu = option.subOption and context.getSubMenu and context:getSubMenu(option.subOption)
            if submenu and submenu.options then
                -- Attach to the actual All/Half/Quarter selection, avoiding a
                -- large tooltip covering the parent Drink menu.
                for _, choice in ipairs(submenu.options) do
                    if choice.onSelect == ISInventoryPaneContextMenu.onDrinkFluid then
                        annotateOption(choice, container, choice.param1)
                    end
                end
            elseif option.name == getText("ContextMenu_Drink") or option.name == getText("ContextMenu_OpenAndDrink")
                or (item.getCustomMenuOption and item:getCustomMenuOption() and option.name == item:getCustomMenuOption()) then
                annotateOption(option, container, 1)
            end
        end
    end
end
Events.OnFillInventoryObjectContextMenu.Add(annotate)

-- Native raw fluid Properties exist only in debug mode and are neutral by
-- design. A plain undamaged can gets a compact card with real benefits.
-- Any special state retains the complete native details and safety warnings.
function M.useCompactTooltip(item, container)
    if not ownCan(item) or not container then return false end
    if item.getTooltip and item:getTooltip() then return false end
    if item.isWet and item:isWet() then return false end
    if item.getItemHeat and math.abs(item:getItemHeat() - 1) > 0.0000001 then return false end
    if item.isCooked and item:isCooked() then return false end
    if item.isBurnt and item:isBurnt() then return false end
    if item.getCondition and item.getConditionMax and item:getCondition() < item:getConditionMax() then return false end
    if container.isPoisonous and container:isPoisonous() then return false end
    if container.isTainted and container:isTainted() then return false end
    if container:isEmpty() then return true end
    local regular, diet = M.amounts(container)
    return regular + diet > 0 and not isMixture(container)
end

local function row(layout, text, value, good)
    local entry = layout:addItem()
    entry:setLabel(text, 1, 1, 0.8, 1)
    if value then
        local color = good and getCore():getGoodHighlitedColor()
        entry:setValue(value, color and color:getR() or 1, color and color:getG() or 1, color and color:getB() or 1, 1)
    end
end

local function effectRows(layout, container)
    row(layout, heading(container, 1))
    local effects = M.tooltipEffects(container, 1)
    local shown = false
    for _, name in ipairs(order) do
        if effects[name] >= 0.005 then
            row(layout, label(name) .. ":", "-" .. number(effects[name]), true)
            shown = true
        end
    end
    if not shown then row(layout, getText("Tooltip_DrPepperDrinkNoEffects")) end
end

function M.drawDrinkTooltip(item, tooltip)
    M.refreshCanTooltip(item)
    local container = item:getFluidContainer()
    local compact = M.useCompactTooltip(item, container)
    local regular, diet = M.amounts(container)
    if not compact then
        item:DoTooltip(tooltip)
        if regular + diet <= 0 then return end
    end
    local layout = tooltip:beginLayout()
    local top = compact and 10 or tooltip:getHeight()
    if compact then
        local title = item:getName(tooltip:getCharacter())
        tooltip:DrawText(tooltip:getFont(), title, 10, top, 1, 1, 0.8, 1)
        tooltip:adjustWidth(10, title)
        top = top + tooltip:getLineSpacing() + 5
        row(layout, getText("Tooltip_item_Weight") .. ":", number(item:getUnequippedWeight()))
        if tooltip:getWeightOfStack() > 0 then
            row(layout, getText("Tooltip_item_StackWeight") .. ":", number(tooltip:getWeightOfStack()))
        end
        row(layout, getText("Fluid_Amount") .. ":", FluidUtil.getFractionFormatted(container:getAmount(), container:getCapacity()))
    end
    if regular + diet > 0 then
        effectRows(layout, container)
        if compact then
            row(layout, getText("Fluid_Prop_Calories") .. ":", number(container:getProperties():getCalories()))
            if regular <= 0.0000001 then
                row(layout, getText("Tooltip_DrPepperCanDiet"))
            elseif diet <= 0.0000001 then
                row(layout, getText("Tooltip_DrPepperCanRegular"))
            end
        end
    elseif compact then
        row(layout, getText("Tooltip_DrPepperCanEmpty"))
    end
    local bottom = layout:render(10, top, tooltip)
    tooltip:endLayout(layout)
    tooltip:setHeight(bottom + 10)
    if tooltip:getWidth() < 150 then tooltip:setWidth(150) end
end

-- Same placement/measurement as vanilla. All unrelated items delegate to the
-- prior renderer; no temporary Java proxies or global debug-setting changes.
function M.installTooltipRenderer()
    -- Shared Lua loads before client files are available to require. Install
    -- once the real UI class exists; a failed early require must not abort us.
    if not ISToolTipInv or type(ISToolTipInv.render) ~= "function" then return false end
    if M.tooltipRendererClass == ISToolTipInv then return true end
    local previousRender = ISToolTipInv.render
    M.drinkTooltipRender = function(self)
        local item = self.item
        M.refreshCanTooltip(item)
        local container = item and item.getFluidContainer and item:getFluidContainer()
        local regular, diet = M.amounts(container)
        if not M.useCompactTooltip(item, container) and regular + diet <= 0 then return previousRender(self) end
        if ISContextMenu and ISContextMenu.instance and ISContextMenu.instance.visibleCheck then return end
        local mx, my = getMouseX() + 24, getMouseY() + 24
        if not self.followMouse then
            mx, my = self:getX(), self:getY()
            if self.anchorBottomLeft then mx, my = self.anchorBottomLeft.x, self.anchorBottomLeft.y end
        end
        local tooltip = self.tooltip
        tooltip:setX(mx)
        tooltip:setY(my)
        tooltip:setWidth(50)
        tooltip:setMeasureOnly(true)
        M.drawDrinkTooltip(item, tooltip)
        tooltip:setMeasureOnly(false)
        local maxX, maxY = getCore():getScreenWidth(), getCore():getScreenHeight()
        local tw, th = tooltip:getWidth(), tooltip:getHeight()
        tooltip:setX(math.max(0, math.min(mx, maxX - tw - 1)))
        tooltip:setY(math.max(0, math.min(not self.followMouse and self.anchorBottomLeft and my - th or my, maxY - th - 1)))
        if self.contextMenu and self.contextMenu.joyfocus then
            tooltip:setX(getPlayerScreenLeft(self.contextMenu.player) + 60)
            tooltip:setY(getPlayerScreenTop(self.contextMenu.player) + 60)
        elseif self.contextMenu and self.contextMenu.currentOptionRect then
            if self.contextMenu.currentOptionRect.height > 32 then self:setY(my + self.contextMenu.currentOptionRect.height) end
            self:adjustPositionToAvoidOverlap(self.contextMenu.currentOptionRect)
        end
        self:setX(tooltip:getX())
        self:setY(tooltip:getY())
        self:setWidth(tw)
        self:setHeight(th)
        if self.followMouse and not self.contextMenu then
            self:adjustPositionToAvoidOverlap({ x = mx - 48, y = my - 48, width = 48, height = 48 })
        end
        self:drawRect(0, 0, self.width, self.height, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b)
        self:drawRectBorder(0, 0, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)
        M.drawDrinkTooltip(item, tooltip)
    end
    ISToolTipInv.render = M.drinkTooltipRender
    M.tooltipRendererClass = ISToolTipInv
    return true
end

M.installTooltipRenderer()
Events.OnGameBoot.Add(M.installTooltipRenderer)
Events.OnGameStart.Add(M.installTooltipRenderer)
