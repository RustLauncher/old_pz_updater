require "ProjectALife/Interface/Creator/ALifeCreatorCore"

local Creator = ProjectALife.CreatorScreen

function Creator.fillSpawnHours(window, spawn)
    local key = tostring(spawn.hourStart or 0) .. "|" .. tostring(spawn.hourEnd or 24)
    local combo = window.factionHours
    local found = false
    for i = 1, combo:getOptionCount() do if combo:getOptionData(i) == key then found = true end end
    if not found then
        combo:addOptionWithData(string.format("%02d:00 - %02d:00 (saved schedule)",
            tonumber(spawn.hourStart) or 0, tonumber(spawn.hourEnd) or 24), key)
    end
    Creator.selectData(combo, key)
end

Creator.visitorLockedEntries = { "factionChance", "factionDayStart", "factionDayEnd", "factionLoneMin",
    "factionLoneMax", "factionGroupMin", "factionGroupMax", "factionLoneWeight", "factionPartyGroupWeight" }
Creator.visitorLockedCombos = { "factionHours", "factionPartyMode", "factionLocationMode" }
Creator.visitorLockedTicks = { "factionEnabled", "factionIncludeWilderness", "factionAllTowns" }

function Creator.lockSpawnControls(window, locked)
    local enabled = not locked
    for _, key in ipairs(Creator.visitorLockedEntries) do
        local control = window[key]
        if control ~= nil then control:setEditable(enabled) end
    end
    for _, key in ipairs(Creator.visitorLockedCombos) do
        local control = window[key]
        if control ~= nil then control:setEnabled(enabled) end
    end
    local ticks = {}
    for _, key in ipairs(Creator.visitorLockedTicks) do ticks[#ticks + 1] = window[key] end
    for _, card in ipairs(window.scenarioTicks and window.scenarioTicks.cards or {}) do ticks[#ticks + 1] = card.tick end
    for _, tick in ipairs(ticks) do
        tick.enable = enabled
        if type(tick.setEnabled) == "function" then tick:setEnabled(enabled) end
    end
    for _, grid in ipairs({ window.townTicks, window.specificPlaceTicks }) do
        for _, button in ipairs(grid and grid.buttons or {}) do button:setEnable(enabled) end
    end
    if window.factionVisitorNotice ~= nil then window.factionVisitorNotice:setVisible(locked) end
end

function Creator.syncVisitorOnly(window)
    local tick = window.factionVisitorOnly
    if tick == nil or window.factionEnabled == nil or window.factionChance == nil then return false end
    local on = tick:isSelected(1) == true
    local was = window.visitorOnlyShown == true
    window.visitorOnlyShown = on
    if on then
        window.factionEnabled:setSelected(1, false)
        window.factionChance:setText("0")
    elseif was then
        local blank = ProjectALife.CustomFactions.blankSpawn()
        window.factionEnabled:setSelected(1, blank.enabled ~= false)
        window.factionChance:setText(tostring(ProjectALife.PartyPolicy.weight(blank.odds)))
    end
    Creator.lockSpawnControls(window, on)
    return on
end

function Creator.buildFactionSpawnSettings(window, page)

    local px = Creator.px
    local outer = page
    page = ISPanel:new(0, px(36), outer.width, outer.height - px(36))
    page:initialise()
    page.backgroundColor = { r=0, g=0, b=0, a=0 }
    page.borderColor = { r=0, g=0, b=0, a=0 }
    outer:addChild(page)
    outer:setScrollHeight(outer.height)
    window.factionSpawnContent = page
    local width = page.width - px(28)
    local wide = width >= px(1100)
    local gap, leftW = px(20), wide and px(410) or width
    local rightX = wide and leftW + gap or 0
    local rightW = wide and width - rightX or width
    page:setScrollChildren(true)
    page:addScrollBars()
    page.prerender = function(self)
        ISPanel.prerender(self)
        self:setStencilRect(0, 0, self.width, self.height)
    end
    page.render = function(self) self:clearStencilRect() end
    page.onMouseWheel = function(self, delta)
        self:setYScroll(self:getYScroll() - delta * px(48))
        return true
    end
    local function heading(panel, y, title)
        Creator.addLabel(panel, px(14), y, title, Creator.palette.TEXT, UIFont.Medium)
    end
    local function row(panel, y, label, value, key)
        Creator.addLabel(panel, px(14), y + px(2), label, Creator.palette.MUTED)
        window[key] = Creator.addEntry(panel, px(162), y, px(92), value, true)
        return window[key]
    end
    local function range(panel, y, label, low, high, lowKey, highKey)
        row(panel, y, label, low, lowKey)
        Creator.addLabel(panel, px(263), y + px(2), "to", Creator.palette.MUTED)
        window[highKey] = Creator.addEntry(panel, px(287), y, px(92), high, true)
    end
    local settings = Creator.createFramedPanel(page, 0, px(8), leftW, px(604))
    heading(settings, px(12), "SPAWN POLICY")
    window.factionVisitorNotice = Creator.addLabel(settings, px(190), px(16),
        Creator.fitText("Visitor-only factions never spawn on their own", UIFont.Small, leftW - px(204)),
        Creator.palette.ROSE)
    window.factionVisitorNotice:setVisible(false)
    window.factionEnabled = Creator.addTick(settings, px(14), px(46), leftW - px(28), "Enable natural spawning")
    Creator.addLabel(settings, px(14), px(83), "Player disposition", Creator.palette.MUTED)
    window.factionPlayerRelation = Creator.addCombo(settings, px(162), px(80), leftW - px(178), Creator.relationChoices)
    Creator.addTooltip(window.factionPlayerRelation, "Friendly and neutral factions can appear naturally. Scouts, ambushes and raids require a hostile faction.")
    row(settings, px(120), "Spawn weight",
        tostring(ProjectALife.PartyPolicy.bounds.newFactionWeight), "factionChance")
    Creator.addTooltip(window.factionChance, "Relative faction selection weight, 0 to "
        .. tostring(ProjectALife.PartyPolicy.bounds.weightCeiling)
        .. ", not a percentage. Zero disables natural spawning. Sandbox settings control overall encounter frequency.")
    heading(settings, px(169), "WHEN")
    range(settings, px(207), "Game day", "", "", "factionDayStart", "factionDayEnd")
    window.factionDayStart:setPlaceholderText("Day 0")
    window.factionDayEnd:setPlaceholderText("No end")
    Creator.addTooltip(window.factionDayEnd, "Inclusive first and last day; day 0 is the first. Leave either blank to keep that end open.")
    Creator.addLabel(settings, px(14), px(249), "Active hours", Creator.palette.MUTED)
    window.factionHours = Creator.addCombo(settings, px(162), px(246), leftW - px(178), {
        {"All day (00:00 - 24:00)", "0|24"}, {"Dawn (05:00 - 08:00)", "5|8"},
        {"Morning (08:00 - 12:00)", "8|12"}, {"Midday (12:00 - 14:00)", "12|14"},
        {"Afternoon (14:00 - 18:00)", "14|18"}, {"Evening (18:00 - 22:00)", "18|22"},
        {"Night (22:00 - 05:00)", "22|5"}, {"Daytime (06:00 - 18:00)", "6|18"},
        {"Nighttime (18:00 - 06:00)", "18|6"},
    })
    Creator.addTooltip(window.factionHours, "When new encounters may begin. Existing squads finish their tasks; they do not disappear at the end of this window.")
    heading(settings, px(326), "PARTY SIZE")
    window.factionPartyMode = Creator.addCombo(settings, px(14), px(365), leftW - px(28), {
        { "Lone survivors + groups", "both" }, { "Lone survivors only", "lone" },
        { "Groups only", "group" },
    })
    local sizes = ProjectALife.PartyPolicy.config(nil)
    range(settings, px(409), "Lone size (1-" .. tostring(ProjectALife.PartyPolicy.bounds.loneCeiling) .. ")",
        tostring(sizes.loneMin), tostring(sizes.loneMax), "factionLoneMin", "factionLoneMax")
    range(settings, px(450), "Group size (" .. tostring(ProjectALife.PartyPolicy.groupFloor()) .. "-"
        .. tostring(ProjectALife.PartyPolicy.groupCeiling()) .. ")",
        tostring(sizes.groupMin), tostring(sizes.groupMax), "factionGroupMin", "factionGroupMax")
    row(settings, px(491), "Lone weight", "", "factionLoneWeight")
    row(settings, px(530), "Group weight", "", "factionPartyGroupWeight")
    for _, entry in ipairs({window.factionLoneWeight, window.factionPartyGroupWeight}) do
        Creator.addTooltip(entry, "Relative weight. Blank uses sandbox defaults; zero disables this party type.")
    end
    Creator.addLabel(settings, px(14), px(573), "Placement distance is managed by A-Life.", Creator.palette.MUTED)

    local encountersY = wide and px(8) or px(632)
    local columns = math.max(1, math.min(3, math.floor(rightW / px(235))))
    local cardW = math.floor((rightW - px(28) - (columns - 1) * px(10)) / columns)

    local rows = math.ceil((#Creator.scenarioChoices + #Creator.outpostSeats) / columns)
    local encounterH = px(125) + rows * px(74)
    local encounters = Creator.createFramedPanel(page, rightX, encountersY, rightW, encounterH)
    heading(encounters, px(12), "ALLOWED ENCOUNTERS")
    window.factionEncounterCount = Creator.addLabel(encounters, px(14), px(44), "", Creator.palette.MUTED)
    local ticks = { cards = {} }
    function ticks:isSelected(index) return self.cards[index].tick:isSelected(1) end
    function ticks:setSelected(index, value) self.cards[index].tick:setSelected(1, value) end
    window.scenarioTicks = ticks
    local presets = {
        { "ROAMING", { roamer=true, patrol=true, town_patrol=true, scavenger_crew=true } },
        { "RESIDENTS", { camp=true, outpost=true, poi_defenders=true } },
        { "ALL", true }, { "NONE", false },
    }
    local presetW = math.floor((rightW - px(46)) / 4)
    for index, preset in ipairs(presets) do
        local choices = preset[2]
        Creator.addButton(encounters, px(14) + (index - 1) * (presetW + px(6)), px(73), presetW, preset[1], function()
            for i, spec in ipairs(window.encounterRows or Creator.scenarioChoices) do
                ticks:setSelected(i, choices == true or type(choices) == "table" and choices[spec[2]] == true)
            end
        end)
    end
    local ENCOUNTER_ROWS = {}
    for _, spec in ipairs(Creator.scenarioChoices) do ENCOUNTER_ROWS[#ENCOUNTER_ROWS + 1] = spec end
    for _, spec in ipairs(Creator.outpostSeats) do ENCOUNTER_ROWS[#ENCOUNTER_ROWS + 1] = spec end
    window.encounterRows = ENCOUNTER_ROWS
    for index, spec in ipairs(ENCOUNTER_ROWS) do
        local x = px(14) + ((index - 1) % columns) * (cardW + px(10))
        local y = px(112) + math.floor((index - 1) / columns) * px(74)
        local card = Creator.createFramedPanel(encounters, x, y, cardW, px(64))
        card.encounterId = spec[2]
        if type(getTexture) == "function" then
            card.icon = getTexture("media/textures/ProjectALife/encounters_white_v2/" .. spec[2] .. ".png")

            if card.icon == nil and Creator.partyIcons[spec[2]] ~= nil then
                card.icon = getTexture("media/textures/ProjectALife/encounters_white_v2/" .. Creator.partyIcons[spec[2]] .. ".png")
            end
            if card.icon == nil then
                card.icon = getTexture("media/textures/ProjectALife/encounters_white_v2/outpost.png")
            end
        end
        card.tick = Creator.addTick(card, px(64), px(8), cardW - px(72), spec[1])
        Creator.addTooltip(card.tick, spec[3])
        Creator.addLabel(card, px(65), px(36), Creator.fitText(spec[3], UIFont.Small, cardW - px(77)), Creator.palette.MUTED)
        card.prerender = function(self)
            ISPanel.prerender(self)
            if self.tick:isSelected(1) then
                self:drawRect(0, 0, px(3), self.height, 1, Creator.palette.ROSE.r, Creator.palette.ROSE.g, Creator.palette.ROSE.b)
            end
            self:drawRect(px(8), px(8), px(48), px(48), 1, 0, 0, 0)
            if self.icon then self:drawTextureScaledAspect2(self.icon, px(8), px(8), px(48), px(48), 1, 1, 1, 1) end
        end

        card.onMouseUp = function(self, x)
            if x < px(64) then self.tick:setSelected(1, not self.tick:isSelected(1)) end
            return true
        end
        ticks.cards[index] = card
    end
    encounters.prerender = function(self)
        ISPanel.prerender(self)
        local count = 0
        for index in ipairs(Creator.scenarioChoices) do if ticks:isSelected(index) then count = count + 1 end end

        local seats = 0
        for index in ipairs(Creator.outpostSeats) do
            if ticks:isSelected(#Creator.scenarioChoices + index) then seats = seats + 1 end
        end
        local kinds = seats == 0 and "any kind of outpost"
            or (tostring(seats) .. " of " .. tostring(#Creator.outpostSeats) .. " outpost kinds")
        window.factionEncounterCount:setName(count == 0 and "None selected - no natural encounters"
            or (tostring(count) .. " selected  /  " .. kinds
                .. "  /  events still follow sandbox triggers"))
    end

    local locationY = math.max(px(612), encountersY + encounterH) + px(20)
    local jumps = { { "POLICY", 0 }, { "ENCOUNTERS", encountersY - px(8) }, { "LOCATION", locationY - px(8) } }
    local jumpW = math.floor((width - px(12)) / 3)
    for index, jump in ipairs(jumps) do
        local destination = jump[2]
        Creator.addButton(outer, (index - 1) * (jumpW + px(6)), 0, jumpW, jump[1], function()
            page:setYScroll(-math.min(destination, math.max(0, page:getScrollHeight() - page.height)))
        end)
    end
    local location = Creator.createFramedPanel(page, 0, locationY, width, px(340))
    heading(location, px(12), "WHERE")
    window.factionLocationMode = Creator.addCombo(location, px(14), px(52), math.min(px(350), width - px(28)), {
        { "Anywhere", "anywhere" }, { "Selected towns", "towns" },
        { "Wilderness only", "wilderness" }, { "Roads & highways", "highways" },
        { "Specific building types", "specific" },
    })
    window.factionIncludeWilderness = Creator.addTick(location, px(14), px(90), width - px(28),
        "Include wilderness with selected towns")
    local townOptions = {}
    for _, town in ipairs(ProjectALife.SpawnRegions.definitions) do townOptions[#townOptions + 1] = { town.label, town.id } end
    window.factionAllTowns = Creator.addTick(location, px(14), px(129), width - px(28), "All towns")
    Creator.addTooltip(window.factionAllTowns, "All registered towns, including towns added later. Untick to choose individual towns below.")
    window.townTicks = Creator.addChoiceGrid(location, px(14), px(169), width - px(28), townOptions,
        math.max(1, math.min(4, math.floor(width / px(210)))), px(32))
    window.syncAllTowns = function()
        local all = window.factionAllTowns:isSelected(1)
        for _, button in ipairs(window.townTicks.buttons) do button:setEnable(not all) end
    end
    window.factionAllTowns.onclick = window.syncAllTowns
    local placeY = px(102)
    window.specificPlaceTicks = Creator.addChoiceGrid(location, px(14), placeY, width - px(28), Creator.specificPlaceChoices,
        math.max(1, math.min(3, math.floor(width / px(250)))), px(32))
    local function syncLocation()
        local mode = Creator.selectedData(window.factionLocationMode)
        window.factionIncludeWilderness:setVisible(mode == "towns")
        window.factionAllTowns:setVisible(mode == "towns")
        for _, button in ipairs(window.townTicks.buttons) do button:setVisible(mode == "towns") end
        for _, button in ipairs(window.specificPlaceTicks.buttons) do button:setVisible(mode == "specific") end
        local locationH = mode == "towns" and (px(193) + window.townTicks.height)
            or mode == "specific" and (placeY + window.specificPlaceTicks.height + px(24)) or px(96)
        location:setHeight(locationH)
        page:setScrollHeight(math.max(page.height, locationY + locationH + px(20)))
    end
    window.factionLocationMode.alifeSync = syncLocation
    window.factionLocationMode.onChange = syncLocation
    syncLocation()
end

return Creator
