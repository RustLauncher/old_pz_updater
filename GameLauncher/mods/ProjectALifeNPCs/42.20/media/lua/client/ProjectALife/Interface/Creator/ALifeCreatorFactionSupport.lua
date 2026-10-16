require "ProjectALife/Interface/Creator/ALifeCreatorCore"

local Creator = ProjectALife.CreatorScreen

function Creator.fillFactionSupport(window, support)
    if not window.factionSupportPolicy then return end
    Creator.selectData(window.factionSupportPolicy, support.policy or "disabled")
    Creator.selectData(window.factionSupportType, support.type or "ground")
    Creator.selectData(window.factionSupportHeli, support.heli or "none")
    Creator.selectData(window.factionSupportVehicle, support.vehicle or "")
    window.factionSupportSize:setText(tostring(support.size or 4))
    window.factionSupportCalls:setText(tostring(support.maxCalls or 1))
    local answerers = support.answerers
    if type(answerers) ~= "table" then
        answerers = {}
        for id in tostring(support.answerers or "same"):gmatch("[^|,]+") do
            answerers[#answerers + 1] = id:match("^%s*(.-)%s*$")
        end
    end
    for index, combo in ipairs(window.factionSupportAnswerers) do
        combo.options = {}
        combo:addOptionWithData("Same faction", "same")
        for _, record in ipairs(window.catalog and window.catalog.factionOrder or {}) do
            if not window.currentFaction or record.id ~= window.currentFaction.id then
                combo:addOptionWithData(record.general and record.general.name or record.id, record.id)
            end
        end
        Creator.selectData(combo, answerers[index] or "same")
    end
    window.syncFactionSupport()
end

function Creator.harvestFactionSupport(window, faction)
    if not window.factionSupportPolicy then return end
    faction.support = faction.support or {}
    local support = faction.support
    support.policy = Creator.selectedData(window.factionSupportPolicy) or "disabled"
    support.type = Creator.selectedData(window.factionSupportType) or "ground"
    support.heli = Creator.selectedData(window.factionSupportHeli) or "none"
    support.vehicle = Creator.selectedData(window.factionSupportVehicle) or ""
    support.size = math.max(1, math.min(8, math.floor(tonumber(window.factionSupportSize:getText()) or 4)))
    support.maxCalls = math.max(0, math.min(10, math.floor(tonumber(window.factionSupportCalls:getText()) or 1)))
    local answerers = {}
    for index, combo in ipairs(window.factionSupportAnswerers) do answerers[index] = Creator.selectedData(combo) or "same" end
    support.answerers = table.concat(answerers, "|")
end

function Creator.buildFactionSupportSettings(window, page)
    local px = Creator.px
    local width = page.width - px(24)
    local card = Creator.addSectionCard(page, 0, px(8), width, px(408), "SUPPORT DEFAULTS", "Who calls, how they arrive, and whether a night helicopter also searches the contact.")
    local function field(y, title, options, key)
        Creator.addLabel(card, px(14), px(y), title, Creator.palette.MUTED)
        window[key] = Creator.addCombo(card, px(14), px(y + 24), width - px(28), options)
        return window[key]
    end
    field(36, "Who can call backup?", {
        { "Radio operator", "radio" }, { "Disabled", "disabled" }, { "Everyone", "any" },
    }, "factionSupportPolicy")
    Creator.addTooltip(window.factionSupportPolicy, "Radio operator: only the squad's radio operator can call. Everyone: any member may call. Disabled: no faction calls. The shared squad cooldown and call limit prevent repeated calls; NPC overrides still apply.")
    field(106, "How does support arrive?", {
        { "Car pull-up (sound + squad)", "ground" }, { "Helicopter", "heli" },
        { "Ground / helicopter", "both" },
    }, "factionSupportType")
    field(176, "Helicopter role", {
        { "None", "none" }, { "Support - rappel troops", "support" },
        { "Spotlight - night / outdoors", "spotlight" },
        { "Helicopter + spotlight + troops", "support_spotlight" },
    }, "factionSupportHeli")
    field(246, "Pull-up sound (no vehicle is spawned)", {
        { "Automatic", "" }, { "Pickup truck", "pickup" }, { "Camo pickup", "truck" },
        { "Step van", "workvan" }, { "Station wagon", "wagon" }, { "Off-roader", "offroad" },
        { "Police car", "police" },
    }, "factionSupportVehicle")
    local half = math.floor((width - px(42)) / 2)
    Creator.addLabel(card, px(14), px(321), "NPCs per call (1-8)", Creator.palette.MUTED)
    window.factionSupportSize = Creator.addEntry(card, px(14), px(345), half, "4", true)
    Creator.addLabel(card, px(28) + half, px(321), "Calls per squad (0-10)", Creator.palette.MUTED)
    window.factionSupportCalls = Creator.addEntry(card, px(28) + half, px(345), half, "1", true)
    Creator.addTooltip(window.factionSupportCalls, "Maximum lifetime calls for the calling squad; zero disables requests. The world's call cap, cooldown and active-NPC budget may reduce this number. Reinforcements cannot call more reinforcements.")
    local callers = Creator.addSectionCard(page, 0, px(430), width, px(312), "BACKUP FACTIONS", "")
    window.factionSupportAnswerers = {}
    for index = 1, 3 do
        local y = px(37) + (index - 1) * px(70)
        Creator.addLabel(callers, px(14), y, "Call " .. tostring(index), Creator.palette.MUTED)
        window.factionSupportAnswerers[index] = Creator.addCombo(callers, px(14), y + px(24), width - px(28), {{ "Same faction", "same" }})
        Creator.addTooltip(window.factionSupportAnswerers[index], "Uses this faction for this call, not a random pool. Another faction must be friendly or allied in at least one direction; otherwise backup uses the caller's own faction. Calls after the third use the same faction.")
    end
    Creator.addLabel(callers, px(14), px(258), Creator.fitText("Add backup choices: set factions Friendly / Allied in Relations.", UIFont.Small, width - px(28)), Creator.palette.MUTED)
    window.factionSupportSummary = Creator.addLabel(page, 0, px(756), "", Creator.palette.MUTED)
    window.syncFactionSupport = function()
        local enabled = Creator.selectedData(window.factionSupportPolicy) ~= "disabled"
        for _, control in ipairs({window.factionSupportType, window.factionSupportHeli,
                window.factionSupportVehicle}) do
            control:setEnabled(true)
        end
        window.factionSupportSize:setEditable(true)
        window.factionSupportCalls:setEditable(true)
        for _, combo in ipairs(window.factionSupportAnswerers) do combo:setEnabled(true) end
        local delivery, heli = Creator.selectedData(window.factionSupportType), Creator.selectedData(window.factionSupportHeli)
        local hint = not enabled and "Disabled by default; NPC overrides may allow calls."
            or delivery == "ground" and "Car sound + distant squad; radio position updates for five seconds."
            or heli == "none" and "No helicopter role: backup falls back to ground."
            or heli == "spotlight" and (delivery == "both" and "Ground squad + night/outdoor searchlight." or "Night/outdoor searchlight reports to the calling squad; no troops.")
            or heli == "support_spotlight" and "Helicopter insertion plus a spotlight on the same identified outdoor target at night."
            or delivery == "both" and "Ground or helicopter squad, chosen per call."
            or "Helicopter squad insertion; world limits still apply."
        window.factionSupportSummary:setName(Creator.fitText(hint, UIFont.Small, width))
    end
    for _, combo in ipairs({window.factionSupportPolicy, window.factionSupportType, window.factionSupportHeli}) do
        combo.onChange = window.syncFactionSupport
    end
    Creator.scrollPage(page, px(790))
    window.syncFactionSupport()
end

return Creator
