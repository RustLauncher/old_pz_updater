require "ProjectALife/Interface/Creator/ALifeCreatorCore"

local Creator = ProjectALife.CreatorScreen

function Creator.buildFactionModulesPage(window)
    local px = Creator.px
    local groupModules = window.factionEditorPages.group_modules
    Creator.addLabel(groupModules, px(10), px(4), "BEHAVIOR DEFAULTS", Creator.palette.TEXT, UIFont.Medium)
    Creator.addLabel(groupModules, px(10), px(30),
        Creator.fitText("NPC overrides win; world switches still apply.", UIFont.Small, groupModules.width - px(30)), Creator.palette.MUTED)
    window.memberModuleCombos = {}
    Creator.addButton(groupModules, px(10), px(63), math.min(px(240), groupModules.width - px(30)), "USE EACH NPC'S PROFILE DEFAULTS", function()
        for _, combo in pairs(window.memberModuleCombos) do Creator.selectData(combo, "inherit") end
    end)
    local factionModulesBottom = Creator.buildModuleOverrideCards(groupModules, px(4), px(104),
        groupModules.width - px(28), window.memberModuleCombos, "faction")
    Creator.scrollPage(groupModules, factionModulesBottom + px(20))
end

return Creator
