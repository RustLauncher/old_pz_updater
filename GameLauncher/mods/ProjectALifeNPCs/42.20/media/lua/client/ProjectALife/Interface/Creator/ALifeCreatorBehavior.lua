require "ProjectALife/Interface/Creator/ALifeCreatorCore"

local Creator = ProjectALife.CreatorScreen

function Creator.buildBehaviorPage(window, formW)
    local px = Creator.px
    local behavior = window.profilePages.behavior
    local fieldW = math.max(px(100), formW - px(162))
    Creator.addLabel(behavior, px(12), 0, "BEHAVIOR & VOICE", Creator.palette.ROSE)
    Creator.addLabel(behavior, px(12), px(35), "Behavior profile", Creator.palette.MUTED)
    window.profileBehaviorProfile = Creator.addCombo(behavior, px(150), px(32),
        fieldW, Creator.behaviorProfileChoices)
    Creator.addTooltip(window.profileBehaviorProfile,
        "Selects the complete baseline behavior package: priorities, engagement style and allowed abilities.")
    Creator.addLabel(behavior, px(12), px(69), "Primary doctrine", Creator.palette.MUTED)
    window.profilePrimaryBehavior = Creator.addCombo(behavior, px(150), px(66),
        fieldW, Creator.primaryBehaviorChoices)
    Creator.addTooltip(window.profilePrimaryBehavior,
        "Assigns one specialist doctrine. Use Modules for smaller per-NPC exceptions.")
    Creator.addLabel(behavior, px(12), px(103), "Combat ready", Creator.palette.MUTED)
    window.profileCombatReady = Creator.addCombo(behavior, px(150), px(100),
        fieldW, Creator.combatReadyChoices)
    Creator.addTooltip(window.profileCombatReady,
        "Controls whether the NPC initially appears armed and prepared. Mixed follows the authored loadout pool.")
    window.behaviorSummaryLabel = Creator.addLabel(behavior, px(12), px(137),
        "Select a behavior profile to see exactly what it does.", Creator.palette.TEXT)
    Creator.addLabel(behavior, px(12), px(176), "VOICE PROFILE", Creator.palette.ROSE)
    Creator.addLabel(behavior, px(12), px(206), "Profile", Creator.palette.MUTED)
    window.profileVoice = Creator.addCombo(behavior, px(150), px(203),
        fieldW, Creator.voiceChoices)
    Creator.addTooltip(window.profileVoice,
        "Chooses the voice pack used for warnings, combat reactions and death sounds.")
    Creator.addLabel(behavior, px(12), px(240), "Reaction", Creator.palette.MUTED)
    window.profileVoiceEvent = Creator.addCombo(behavior, px(150), px(237),
        fieldW, Creator.voiceEventChoices)
    Creator.addTooltip(window.profileVoiceEvent,
        "Select the reaction category used by Play voice preview. It does not change combat behavior.")
    Creator.addButton(behavior, px(150), px(274), px(132), "PLAYTEST VOICE", function()
        Creator.previewVoice(window)
    end, true)
    window.voicePreviewStatus = Creator.addLabel(behavior, px(12), px(311),
        "Select a voice and reaction to preview.", Creator.palette.MUTED)
end

return Creator
