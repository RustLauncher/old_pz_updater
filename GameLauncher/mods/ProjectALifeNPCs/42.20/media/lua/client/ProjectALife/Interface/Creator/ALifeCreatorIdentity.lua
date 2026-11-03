require "ProjectALife/Interface/Creator/ALifeCreatorCore"
require "ProjectALife/Core/ALifeText"
require "ProjectALife/Records/ALifeNames"

local Creator = ProjectALife.CreatorScreen

Creator.nameModes = {
    { "Random name (matches gender)", "auto" }, { "Random male name", "male" },
    { "Random female name", "female" }, { "Set name", "fixed" },
}

Creator.npcClasses = {
    { "Same as faction", "" }, { "Civilian", "civilian" }, { "Worker", "worker" },
    { "Rescue", "rescue" }, { "Police", "police" }, { "Military", "military" }, { "Criminal", "criminal" },
}

function Creator.buildIdentityPage(window, formW)
    local px = Creator.px
    local identity = window.profilePages.identity
    window.profileFaction = Creator.addLabel(identity, px(12), 0, "Faction: -", Creator.palette.MUTED)
    local identityW = math.max(px(210), formW - px(8))
    local wideIdentity = identityW >= px(620)
    local whoH, roleY, roleH, notesY = wideIdentity and px(154) or px(178),
        wideIdentity and px(188) or px(212), wideIdentity and px(104) or px(208),
        wideIdentity and px(302) or px(430)
    local whoCard = Creator.addSectionCard(identity, px(4), px(24), identityW, whoH,
        "WHO IS THIS NPC?", "Readable identity first; internal IDs stay out of the way.")
    local roleCard = Creator.addSectionCard(identity, px(4), roleY, identityW, roleH + px(42),
        "TAG, CLASS & SPAWN", "Tag describes the member's job. Class sets how the member behaves under threat. Spawn Weight In Group controls how often this preset is selected.")
    local notesCard = Creator.addSectionCard(identity, px(4), notesY + px(42), identityW, px(150),
        "DISCOVERY & ADMIN NOTES", "Tags improve filtering. Notes are private creator metadata.")
    if wideIdentity then
        local gap = px(14)
        local half = math.floor((identityW - px(24) - gap * 2) / 3)
        Creator.addLabel(whoCard, px(12), px(53), "Display name", Creator.palette.MUTED, nil, px(94))
        window.profileName = Creator.addEntry(whoCard, px(110), px(50), identityW - px(122), "")
        Creator.addLabel(whoCard, px(12), px(87), "Gender", Creator.palette.MUTED, nil, px(94))
        window.profileGender = Creator.addCombo(whoCard, px(110), px(84), identityW - px(122), Creator.genders)
        Creator.buildNameMode(window, whoCard, px(121), px(110), identityW - px(122), px(94))
        Creator.addCenteredLabel(roleCard, px(12), px(45), half, "Tag", Creator.palette.MUTED)
        window.profileRole = Creator.addCombo(roleCard, px(12), px(70), half, Creator.roleChoices)
        Creator.addCenteredLabel(roleCard, px(12) + half + gap, px(45), half, "Class", Creator.palette.MUTED)
        window.profileNpcClass = Creator.addCombo(roleCard, px(12) + half + gap, px(70), half, Creator.npcClasses)
        Creator.addCenteredLabel(roleCard, px(12) + (half + gap) * 2, px(45), half,
            "Spawn Weight In Group", Creator.palette.MUTED)
        window.profileSpawnWeight = Creator.addNumberChoices(roleCard, px(12) + (half + gap) * 2, px(70),
            half, Creator.spawnWeightChoices, " weight")
    else
        local labelW, entryW = px(100), math.max(px(90), identityW - px(124))
        Creator.addLabel(whoCard, px(12), px(53), "Display name", Creator.palette.MUTED, nil, labelW - px(6))
        window.profileName = Creator.addEntry(whoCard, labelW + px(12), px(50), entryW, "")
        Creator.addLabel(whoCard, px(12), px(89), "Gender", Creator.palette.MUTED, nil, labelW - px(6))
        window.profileGender = Creator.addCombo(whoCard, labelW + px(12), px(86), entryW, Creator.genders)
        Creator.buildNameMode(window, whoCard, px(125), labelW + px(12), entryW, labelW - px(6))
        Creator.addCenteredLabel(roleCard, px(12), px(45), identityW - px(24), "Tag", Creator.palette.MUTED)
        window.profileRole = Creator.addCombo(roleCard, px(12), px(70), identityW - px(24), Creator.roleChoices)
        Creator.addCenteredLabel(roleCard, px(12), px(98), identityW - px(24),
            "Spawn Weight In Group", Creator.palette.MUTED)
        window.profileSpawnWeight = Creator.addNumberChoices(roleCard, px(12), px(123),
            identityW - px(24), Creator.spawnWeightChoices, " weight")
        Creator.addCenteredLabel(roleCard, px(12), px(151), identityW - px(24), "Class", Creator.palette.MUTED)
        window.profileNpcClass = Creator.addCombo(roleCard, px(12), px(176), identityW - px(24), Creator.npcClasses)
    end
    Creator.buildMemberTags(window, roleCard, identityW, roleH)
    Creator.scrollPage(identity, notesY + px(210))
    Creator.addTooltip(window.profileNpcClass,
        "How this member behaves under threat. Civilians and workers are fearful, soldiers, police and criminals stay steady. Same as faction follows the faction's class.")
    Creator.addTooltip(window.profileSpawnWeight,
        "How often this preset is selected within its faction. Common is the normal rate; Rare and Very Rare keep specialists from taking over a squad.")
    Creator.addLabel(notesCard, px(12), px(52), "Filter tags", Creator.palette.MUTED, nil, px(88))
    window.profileTags = Creator.addEntry(notesCard, px(104), px(49), identityW - px(116), "")
    window.profileTags:setPlaceholderText("outdoor, rifle, medic, trader")
    Creator.addLabel(notesCard, px(12), px(96), "Notes", Creator.palette.MUTED)
    window.profileNotes = Creator.addEntry(notesCard, px(104), px(93), identityW - px(116), "")
end

function Creator.loadNpcClass(window, profile)
    if window == nil or window.profileNpcClass == nil or type(profile) ~= "table" then return end
    local general = type(profile.general) == "table" and profile.general or {}
    local value = type(general.npcClass) == "string" and general.npcClass or ""
    Creator.selectData(window.profileNpcClass, value, "")
end

function Creator.saveNpcClass(window, profile)
    if window == nil or window.profileNpcClass == nil or type(profile) ~= "table" then return end
    profile.general = type(profile.general) == "table" and profile.general or {}
    local value = Creator.selectedData(window.profileNpcClass) or ""
    if value == "" then profile.general.npcClass = nil else profile.general.npcClass = value end
end

function Creator.buildNameMode(window, card, y, x, width, labelRoom)
    local px = Creator.px
    local comboW = math.max(px(90), math.floor((width - px(6)) / 2))
    Creator.addLabel(card, px(12), y + px(3), "NPC name", Creator.palette.MUTED, nil, labelRoom)
    window.profileNameMode = Creator.addCombo(card, x, y, comboW, Creator.nameModes)
    window.profileFixedName = Creator.addEntry(card, x + comboW + px(6), y, math.max(px(60), width - comboW - px(6)), "")
    if type(window.profileFixedName.setPlaceholderText) == "function" and ProjectALife.Text ~= nil then
        window.profileFixedName:setPlaceholderText(ProjectALife.Text.ui("Name for every NPC of this preset"))
    end
    Creator.addTooltip(window.profileNameMode,
        "Each NPC spawned from this preset gets its own name, never repeated in the world. Pick Set name to give every NPC of this preset the same name.")
    window.profileNameMode.onChange = function() Creator.syncNameMode(window) end
    Creator.syncNameMode(window)
end

function Creator.syncNameMode(window)
    local entry = window and window.profileFixedName
    if entry == nil then return end
    local fixed = Creator.selectedData(window.profileNameMode) == "fixed"
    if type(entry.setEditable) == "function" then entry:setEditable(fixed) end
    if type(entry.setVisible) == "function" then entry:setVisible(fixed) end
end

function Creator.loadNameMode(window, profile)
    if window == nil or window.profileNameMode == nil or type(profile) ~= "table" then return end
    local general = type(profile.general) == "table" and profile.general or {}
    local mode = type(general.nameMode) == "string" and general.nameMode or "auto"
    Creator.selectData(window.profileNameMode, mode, "auto")
    if window.profileFixedName ~= nil then
        window.profileFixedName:setText(general.fixedName ~= nil and tostring(general.fixedName) or "")
    end
    Creator.syncNameMode(window)
end

function Creator.saveNameMode(window, profile)
    if window == nil or window.profileNameMode == nil or type(profile) ~= "table" then return end
    profile.general = type(profile.general) == "table" and profile.general or {}
    local mode = Creator.selectedData(window.profileNameMode) or "auto"
    local fixed, names = "", ProjectALife.Names
    if window.profileFixedName ~= nil then
        local text = window.profileFixedName:getText()
        if names ~= nil and type(names.clean) == "function" then fixed = names.clean(text)
        else fixed = string.match(tostring(text or ""), "^%s*(.-)%s*$") or "" end
    end
    if mode == "fixed" and fixed == "" then mode = "auto" end
    if mode == "auto" then profile.general.nameMode = nil else profile.general.nameMode = mode end
    if mode == "fixed" then profile.general.fixedName = fixed else profile.general.fixedName = nil end
end

function Creator.memberTags(faction)
    local tags = {}
    local encoded = faction and faction.general and faction.general.memberTags or ""
    for name, red, green, blue in string.gmatch(tostring(encoded), "([^|=]+)=([%d.]+),([%d.]+),([%d.]+)") do
        tags[name] = { r = math.max(0, math.min(1, tonumber(red) or 0)),
            g = math.max(0, math.min(1, tonumber(green) or 0)),
            b = math.max(0, math.min(1, tonumber(blue) or 0)), a = 1 }
    end
    return tags
end

function Creator.encodeMemberTags(tags)
    local names, result = {}, {}
    for name in pairs(tags) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local color = tags[name]
        result[#result + 1] = name .. "=" .. string.format("%.3f,%.3f,%.3f", color.r, color.g, color.b)
    end
    return table.concat(result, "|")
end

function Creator.memberTagColor(faction, name)
    return Creator.memberTags(faction)[name]
end

function Creator.syncMemberTag(window)
    local color = Creator.memberTagColor(window.currentFaction, Creator.selectedData(window.profileRole))
    color = color or Creator.palette.TEXT
    window.profileRole.textColor = { r = color.r, g = color.g, b = color.b, a = color.a or 1 }
    if window.profileTagDelete then
        window.profileTagDelete:setEnable(Creator.memberTagColor(window.currentFaction, Creator.selectedData(window.profileRole)) ~= nil)
    end
end

function Creator.drawMemberTagText(popup, text, x, y, red, green, blue, alpha, font)
    local window = popup.parentCombo and popup.parentCombo.memberTagWindow
    if window then
        local custom = Creator.memberTagColor(window.currentFaction, text)
        local color = custom or Creator.palette.TEXT
        red, green, blue, alpha = color.r, color.g, color.b, color.a or 1
        if custom then
            local edge = Creator.memberTagDeleteEdge(popup)
            popup.memberTagDrawText(popup, "X", edge - Creator.px(18), y, red, green, blue, alpha, font)
            text = Creator.fitText(text, font, math.max(1, edge - x - Creator.px(32)))
        end
    end
    return popup.memberTagDrawText(popup, text, x, y, red, green, blue, alpha, font)
end

function Creator.memberTagDeleteEdge(popup)
    return popup.width - (popup:isVScrollBarVisible() and 13 or 0)
end

function Creator.memberTagPopupMouseUp(popup, x, y)
    local combo = popup.parentCombo
    local window = combo and combo.memberTagWindow
    if window and not combo.disabled and popup:isMouseOver() then
        local edge = Creator.memberTagDeleteEdge(popup)
        local item = popup.items[popup:rowAt(x, y)]
        if item and x >= edge - Creator.px(28) and x < edge
                and Creator.memberTagColor(window.currentFaction, item.text) then
            if Creator.removeMemberTag(window, item.text) then
                combo.expanded = false
                combo:hidePopup()
            end
            return true
        end
    end
    return popup.memberTagMouseUp(popup, x, y)
end

function Creator.showMemberTagPopup(combo)
    ISComboBox.showPopup(combo)
    if combo.popup and not combo.popup.memberTagDrawText then
        combo.popup.memberTagDrawText = combo.popup.drawText
        combo.popup.drawText = Creator.drawMemberTagText
        combo.popup.memberTagMouseUp = combo.popup.onMouseUp
        combo.popup.onMouseUp = Creator.memberTagPopupMouseUp
    end
end

function Creator.loadMemberTags(window, selected)
    if not window.profileRole then return end
    local combo, names = window.profileRole, {}
    combo:clear()
    for _, row in ipairs(Creator.roleChoices) do combo:addOptionWithData(row[1], row[2]) end
    for name in pairs(Creator.memberTags(window.currentFaction)) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do combo:addOptionWithData(name, name) end
    Creator.selectData(combo, selected or "Scout")
    Creator.syncMemberTag(window)
end

function Creator.addMemberTag(window, name, color)
    if not window.currentFaction then return false end
    name = string.match(tostring(name or ""):gsub("[%c|=]", " "), "^%s*(.-)%s*$") or ""
    if name == "" or #name > 48 then
        Creator.paintSaveStatus(window.saveStateLabel, "TAG NAME: 1 TO 48 CHARACTERS", "error")
        return false
    end
    local tags = Creator.memberTags(window.currentFaction)
    for _, row in ipairs(Creator.roleChoices) do
        if string.lower(row[1]) == string.lower(name) or string.lower(row[2]) == string.lower(name) then return false end
    end
    for existing in pairs(tags) do if string.lower(existing) == string.lower(name) then return false end end
    local previous = window.currentFaction.general.memberTags
    color = color or Creator.palette.ROSE
    tags[name] = { r = math.max(0, math.min(1, tonumber(color.r) or 0)),
        g = math.max(0, math.min(1, tonumber(color.g) or 0)),
        b = math.max(0, math.min(1, tonumber(color.b) or 0)) }
    window.currentFaction.general.memberTags = Creator.encodeMemberTags(tags)
    if not Creator.saveFaction(window) then window.currentFaction.general.memberTags = previous; return false end
    Creator.loadMemberTags(window, name)
    if window.profileTagName then window.profileTagName:setText("") end
    return true
end

function Creator.pickMemberTagColor(window, color)
    if not window or not color then return end
    window.profileTagColorValue = { r = color.r, g = color.g, b = color.b }
    Creator.paintColorSwatch(window.profileTagColor, color)
end

function Creator.openMemberTagColor(window, button)
    local color = window.profileTagColorValue or Creator.palette.ROSE
    local picker = ISColorPickerHSB:new(0, 0, ColorInfo.new(color.r, color.g, color.b, 1))
    picker:initialise()
    picker.keepOnScreen, picker.pickedTarget = true, window
    picker:setPickedFunc(Creator.pickMemberTagColor)
    picker:setInitialColor(ColorInfo.new(color.r, color.g, color.b, 1))
    picker:setX(math.max(0, math.min(getCore():getScreenWidth() - picker.width, button:getAbsoluteX())))
    picker:setY(math.max(0, math.min(getCore():getScreenHeight() - picker.height, button:getAbsoluteY() + button.height)))
    picker:addToUIManager()
    picker:setAlwaysOnTop(true)
    picker:bringToTop()
end

function Creator.buildMemberTags(window, card, width, top)
    local px, combo = Creator.px, window.profileRole
    combo:setWidth(combo.width - px(30))
    window.profileTagDelete = Creator.addButton(card, combo.x + combo.width + px(4), combo.y,
        px(26), "X", function() Creator.removeMemberTag(window, Creator.selectedData(combo)) end)
    Creator.addTooltip(window.profileTagDelete, "Delete this custom tag from this faction. Its members return to Scout.")
    window.profileTagDelete:setEnable(false)
    combo.onChange = function() Creator.syncMemberTag(window) end
    combo.memberTagWindow, combo.showPopup = window, Creator.showMemberTagPopup
    window.profileTagName = Creator.addEntry(card, px(12), top + px(4), width - px(162), "")
    window.profileTagName:setPlaceholderText("New tag name")
    window.profileTagColor = Creator.addButton(card, width - px(144), top + px(4), px(30), "", function(_, button)
        Creator.openMemberTagColor(window, button)
    end)
    Creator.addTooltip(window.profileTagColor, "Choose a color for the new tag.")
    Creator.pickMemberTagColor(window, Creator.palette.ROSE)
    Creator.addButton(card, width - px(108), top + px(4), px(96), "ADD TAG", function()
        Creator.addMemberTag(window, window.profileTagName:getText(), window.profileTagColorValue)
    end, true)
end

return Creator
