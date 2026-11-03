require "ProjectALife/Interface/Creator/ALifeCreatorCore"

local Creator = ProjectALife.CreatorScreen

function Creator.buildCombatPage(window, formW, compact)
    local px = Creator.px
    local combat = window.profilePages.combat
    local combatColumns = formW >= px(520) and 2 or 1
    local combatGap = px(18)
    local combatColumnW = math.floor((formW - px(40) - combatGap * (combatColumns - 1)) / combatColumns)
    local stats = {
        { "Health (HP)", "healthHP" }, { "Strength", "strength" },
        { "Endurance", "endurance" }, { "Awareness", "awareness" },
        { "Aiming", "aiming" },

        { "Accuracy vs players (%)", "aimPlayerPercent" },
        { "Accuracy vs zombies (%)", "aimZombiePercent" },
    }
    local statsH = px(42) + math.ceil(#stats / combatColumns) * px(58)
    local statsCard = Creator.addSectionCard(combat, px(4), 0, formW - px(8), statsH, "VITALITY & SKILLS", "")
    window.statEntries = {}
    for index, spec in ipairs(stats) do
        local x = px(12) + ((index - 1) % combatColumns) * (combatColumnW + combatGap)
        local y = px(32) + math.floor((index - 1) / combatColumns) * px(58)
        Creator.addLabel(statsCard, x, y, spec[1], Creator.palette.MUTED)
        window.statEntries[spec[2]] = Creator.addRatingSlider(statsCard, x, y + px(18),
            combatColumnW, Creator.statValue({}, spec[2]), Creator.statRanges[spec[2]][2], Creator.statRanges[spec[2]][1])
    end
    Creator.addTooltip(window.statEntries.healthHP, "Base HP, 0-200. Zero uses the standard NPC HP. The NPC health option and the world health multiplier scale it on spawn, like stock NPCs; the summary shows the result. Default: "
        .. tostring(Creator.healthHP({})) .. " HP. Other skills use 1-10 ratings.")

    local dropOptions = { { "None", 0 }, { "Very Low", 5 }, { "Low", 20 },
        { "Moderate", 50 }, { "High", 75 }, { "Very High", 90 }, { "Always", 100 } }

    local conditionOptions = ProjectALife.DropPolicy.conditions
    local function combatChoices(card, index, title, options, suffix)
        local x = px(12) + ((index - 1) % combatColumns) * (combatColumnW + combatGap)
        local y = px(32) + math.floor((index - 1) / combatColumns) * px(58)
        Creator.addLabel(card, x, y, title, Creator.palette.MUTED)
        return Creator.addNumberChoices(card, x, y + px(19), combatColumnW, options, suffix)
    end
    local damageY, damageH = statsH + px(12), px(42) + math.ceil(2 / combatColumns) * px(58)
    local damageCard = Creator.addSectionCard(combat, px(4), damageY, formW - px(8), damageH, "DAMAGE", "")
    for index, spec in ipairs({ { "Weapon damage dealt (%)", "damageOutput", 100 },
            { "Incoming damage blocked (%)", "damageReduction", 0 } }) do
        local x = px(12) + ((index - 1) % combatColumns) * (combatColumnW + combatGap)
        local y = px(32) + math.floor((index - 1) / combatColumns) * px(58)
        Creator.addLabel(damageCard, x, y, spec[1], Creator.palette.MUTED)
        window[spec[2]] = Creator.addEntry(damageCard, x, y + px(19), combatColumnW, spec[3], true)
    end
    Creator.addTooltip(window.damageOutput, "Multiplies the weapon's damage: 25% = one quarter, 100% = normal, 200% = double.")
    Creator.addTooltip(window.damageReduction, "Reduces incoming damage. At 25%, the NPC takes 75% of the hit. Maximum reduction: 90%.")

    local lootY, lootH = damageY + damageH + px(12), px(42) + math.ceil(4 / combatColumns) * px(58)
    local loot = Creator.addSectionCard(combat, px(4), lootY, formW - px(8), lootH, "LOOT", "")
    Creator.addLabel(loot, px(12), px(32), "Weapon drop chance", Creator.palette.MUTED)
    window.dropWeaponChance = Creator.addCombo(loot, px(12), px(51), combatColumnW, ProjectALife.DropPolicy.presets)
    window.dropArmorChance = combatChoices(loot, 2, "Armor drop chance", dropOptions, "%")
    window.dropWeaponCondition = combatChoices(loot, 3, "Weapon condition", conditionOptions, "/10")
    window.armorCondition = combatChoices(loot, 4, "Armor condition", conditionOptions, "/10")
    Creator.addTooltip(window.dropWeaponChance,
        "Loot after death, not the chance to spawn armed. Choose weapons in Loadout. Each NPC gets a stable chance within the range. Always (100%) keeps issued weapons; Off removes them. Does not create missing weapons or control magazine drops.")
    for _, combo in ipairs({ window.dropArmorChance }) do
        Creator.addTooltip(combo, "None 0% / Very Low 5% / Low 20% / Moderate 50% / High 75% / Very High 90% / Always 100%. Existing custom percentages are preserved.")
    end

    local supportY = lootY + lootH + px(12)
    local support = Creator.addSectionCard(combat, px(4), supportY, formW - px(8), px(262), "COMBAT SUPPORT", "")
    Creator.addLabel(support, px(12), px(34), "Calling permission", Creator.palette.MUTED)
    window.supportPolicy = Creator.addCombo(support, px(12), px(57), formW - px(40), {
        { "Use faction setting", "inherit" }, { "Everyone / allow this NPC", "any" },
        { "Radio operator", "radio" }, { "Disabled", "disabled" },
    })
    Creator.addLabel(support, px(12), px(95), "Delivery", Creator.palette.MUTED)
    window.supportType = Creator.addCombo(support, px(12), px(118), formW - px(40), {
        { "Use faction delivery", "inherit" }, { "Ground vehicle", "ground" },
        { "Helicopter", "heli" }, { "Ground / helicopter", "both" },
    })
    Creator.addLabel(support, px(12), px(156), "Helicopter role", Creator.palette.MUTED)
    window.supportHeli = Creator.addCombo(support, px(12), px(179), formW - px(40), {
        { "Use faction role", "inherit" }, { "No helicopter", "none" },
        { "Squad insertion", "support" }, { "Spotlight", "spotlight" },
    })
    Creator.addTooltip(window.supportPolicy, "Use faction + assigned role preserves the faction policy. Yes gives this member radio-calling ability without replacing its combat specialist. Admin spawn overrides still take precedence.")
    Creator.addTooltip(window.supportHeli, "Spotlight needs Helicopter or Ground / helicopter delivery. The combined setting brings a ground squad and the light; Helicopter alone brings only the light. With Squad insertion, the combined setting chooses either delivery per call.")
    local supportHint = Creator.addLabel(support, px(12), px(222), "", Creator.palette.MUTED)
    window.syncProfileSupport = function()
        local policy = Creator.selectedData(window.supportPolicy)
        window.supportType:setEnabled(true); window.supportHeli:setEnabled(true)
        supportHint:setName(Creator.fitText(policy == "inherit" and "Defaults: Faction settings > Support"
            or policy == "disabled" and "This NPC cannot request backup."
            or "Squad size and backup faction use faction settings.", UIFont.Small, formW - px(40)))
    end
    window.supportPolicy.onChange = window.syncProfileSupport
    window.syncProfileSupport()

    Creator.scrollPage(combat, supportY + px(276))
end

return Creator
