require "ISUI/ISInventoryPane"
require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISStudySpecialtyBags"

local function studyBag(item, character)
    if BolsasEspecialidades.studyBlockReason(character, item) then return end
    ISTimedActionQueue.add(ISStudySpecialtyBags:new(character, item))
end

local function addStudyOption(playerNum, context, selected)
    local character = getSpecificPlayer(playerNum)
    if not character then return end
    local items = ISInventoryPane.getActualItems(selected)
    for _, item in ipairs(items) do
        if BolsasEspecialidades.isStudyBag(item) then
            local option = context:addOption(getText("ContextMenu_BE_Study"), item, studyBag, character)
            option.itemForTexture = item
            local reason = BolsasEspecialidades.studyBlockReason(character, item)
            local tip = ISInventoryPaneContextMenu.addToolTip()
            tip.description = getText(reason or "ContextMenu_BE_StudyHint")
            option.toolTip = tip
            option.notAvailable = reason ~= nil
            return
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(addStudyOption)
