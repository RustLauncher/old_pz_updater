require "ProjectALife/Interface/Creator/ALifeCreatorCore"
require "ProjectALife/Interface/Creator/ALifeCreatorModuleRules"

local Creator = ProjectALife.CreatorScreen

function Creator.buildModulesPage(window, formW)
    local px = Creator.px
    local modules = window.profilePages.modules
    Creator.addLabel(modules, px(12), 0, "NPC ABILITIES", Creator.palette.TEXT, UIFont.Medium)
    Creator.addLabel(modules, px(154), px(3),
        "Hover a setting or its info icon for a plain-language explanation.", Creator.palette.MUTED)
    window.profileModuleOverrides = {}
    modules.applyModuleGroup = function(groupId)
        Creator.applyModuleGroupToFaction(window, groupId)
    end
    local moduleBottom = Creator.buildModuleOverrideCards(modules, px(4), px(34),
        math.max(px(210), formW - px(8)), window.profileModuleOverrides)
    window.profileModuleEntries = {}
    Creator.addLabel(modules, px(12), moduleBottom,
        "INHERIT = USE FACTION SETTING | ON/OFF = THIS NPC ONLY", Creator.palette.TEXT)
    Creator.addButton(modules, px(12), moduleBottom + px(28), px(196), "RESET ALL TO INHERIT", function()
        for _, spec in ipairs(Creator.memberModules) do
            Creator.selectData(window.profileModuleOverrides[spec[2]], "inherit")
        end
    end)
    Creator.addButton(modules, px(216), moduleBottom + px(28), px(216), "APPLY ABILITIES TO FACTION", function()
        Creator.applyProfileDomainToFaction(window, "behavior")
    end, true)

    Creator.scrollPage(modules, moduleBottom + px(70))
end

return Creator
