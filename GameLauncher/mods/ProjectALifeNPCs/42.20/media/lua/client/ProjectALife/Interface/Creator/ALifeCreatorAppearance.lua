require "ProjectALife/Interface/Creator/ALifeCreatorCore"

local Creator = ProjectALife.CreatorScreen

function Creator.seasonHint()
    local seasons, Text = ProjectALife.Seasons, ProjectALife.Text
    if seasons == nil or type(seasons.wardrobeHint) ~= "function" or Text == nil then return "" end
    local season, band, temp = seasons.wardrobeHint()
    local name = string.upper(string.sub(tostring(season), 1, 1)) .. string.sub(tostring(season), 2)
    if band == nil or temp == nil then
        return Text.ui("Outfit season now: {season} (no temperature reading here, the date decides)", { season = name })
    end
    return Text.ui("Outfit season now: {season} ({temp} C, {band} band)", {
        season = name, temp = string.format("%.0f", temp), band = seasons.wardrobeCfg.names[band] })
end

function Creator.buildAppearancePage(window, formW)
    local px = Creator.px
    local appearance = window.profilePages.appearance
    Creator.addLabel(appearance, px(12), 0, "CHARACTER APPEARANCE", Creator.palette.TEXT, UIFont.Medium)
    Creator.addLabel(appearance, px(12), px(31), "Skin tone", Creator.palette.MUTED)
    window.profileSkin = Creator.addEntry(appearance, 0, 0, 1, "0", true)
    window.profileSkin:setVisible(false)
    window.profileSkinButtons = {}
    for index, color in ipairs(Creator.skinColors) do
        local skinIndex, swatch = index - 1, color
        local button = Creator.addButton(appearance, px(126) + (index - 1) * px(42), px(26), px(36), "", function()
            Creator.setProfileSkin(window, skinIndex)
        end)
        button.backgroundColor = { r = swatch.r, g = swatch.g, b = swatch.b, a = 1 }
        window.profileSkinButtons[index] = button
    end
    window.profileHair = Creator.addCombo(appearance, 0, 0, 1, Creator.hairChoices)
    window.profileHair:setVisible(false)
    window.profileBeard = Creator.addCombo(appearance, 0, 0, 1, Creator.beardChoices)
    window.profileBeard:setVisible(false)
    Creator.addLabel(appearance, px(12), px(70), "Hair", Creator.palette.MUTED)
    window.profileHairColorButton = Creator.addButton(appearance, formW - px(48), px(64), px(36), "", function(_, button)
        Creator.openAppearanceColorPicker(window, "hair", button)
    end)
    window.profileHairValueLabel = Creator.addLabel(appearance, px(74), px(70), "Bald / no hair", Creator.palette.TEXT)
    window.profileHairBrowse = Creator.addButton(appearance, formW - px(174), px(63),
        px(114), "CHOOSE HAIR", function() Creator.openAppearancePicker(window, "hair") end, true)
    Creator.addLabel(appearance, px(12), px(106), "Beard", Creator.palette.MUTED)
    window.profileBeardColorButton = Creator.addButton(appearance, formW - px(48), px(100), px(36), "", function(_, button)
        Creator.openAppearanceColorPicker(window, "beard", button)
    end)
    window.profileBeardValueLabel = Creator.addLabel(appearance, px(74), px(106), "Clean shaven", Creator.palette.TEXT)
    window.profileBeardBrowse = Creator.addButton(appearance, formW - px(174), px(99),
        px(114), "CHOOSE BEARD", function() Creator.openAppearancePicker(window, "beard") end, true)

    local outfitsY = Creator.buildAppearanceMakeup(window, appearance, formW, px(142))
    Creator.addLabel(appearance, px(12), outfitsY, "OUTFIT SETS", Creator.palette.ROSE)
    window.outfitButtons = {}
    local outfitButtonW = math.max(px(34), math.floor((formW - px(34)) / #Creator.outfitIds))
    for index, id in ipairs(Creator.outfitIds) do
        local outfitId = id
        window.outfitButtons[id] = Creator.addButton(appearance,
            px(12) + (index - 1) * (outfitButtonW + px(2)), outfitsY + px(20), outfitButtonW,
            id, function() Creator.showOutfit(window, outfitId) end, id == "A")
    end
    if Creator.outfitHealth ~= nil then Creator.outfitHealth.install(window, appearance, formW, outfitsY) end
    window.outfitEnabled = ISTickBox:new(px(12), outfitsY + px(54), px(230), px(22), "", window,
        function(target, _, enabled) Creator.setOutfitEnabled(target, enabled) end)
    window.outfitEnabled:initialise()
    window.outfitEnabled:addOption("Enable this set for spawning")
    appearance:addChild(window.outfitEnabled)
    window.multipleClothing = Creator.addTick(appearance, formW >= px(520) and px(254) or px(12),
        outfitsY + (formW >= px(520) and px(54) or px(80)), px(245), "Enable multiple options")
    Creator.addTooltip(window.multipleClothing, "Keep up to four random spawn options per clothing slot. Off: the next click replaces the slot.")
    window.outfitPreviewStatus = Creator.addLabel(appearance, px(12), outfitsY + px(134), "", Creator.palette.MUTED)

    local seasonW = math.max(px(110), math.min(px(190), math.floor((formW - px(32)) / 2)))
    window.outfitSeasonCombo = Creator.addCombo(appearance, px(12), outfitsY + px(102), seasonW, Creator.outfitSeasonChoices)
    window.outfitSeasonCombo.onChange = function()
        Creator.setOutfitSeason(window, Creator.selectedData(window.outfitSeasonCombo))
    end
    Creator.addTooltip(window.outfitSeasonCombo,
        "Any season: this set can spawn all year. A season: it only spawns then, and in that season it replaces the any-season sets. The season follows the outdoor temperature, checked when the NPC is dressed and again while it lives: winter set at 4 C or colder, summer set at 22 C or warmer, spring or autumn in between (the date only picks which). Rain, wind and snow count as one step colder. Without a climate reading the date decides: winter Dec-Feb, spring Mar-May, summer Jun-Aug, autumn Sep-Nov.")
    window.previewOutfitButton = Creator.addButton(appearance, px(20) + seasonW, outfitsY + px(102), formW - px(32) - seasonW,
        "PREVIEW VARIATION", function() Creator.previewNextEnabledOutfit(window) end, true)
    Creator.addTooltip(window.previewOutfitButton,
        "Cycles only through outfit sets marked Enable this set for spawning. A random pool choice is shown each time.")
    Creator.addLabel(appearance, px(12), outfitsY + px(142), "BODY SLOTS", Creator.palette.ROSE)
    window.clothingCombos = {}
    window.appearanceTiles = {}
    local clothingColumns = formW >= px(480) and 3 or 2
    local tileGap, tileH = px(8), px(64)
    local columnW = math.floor((formW - px(24) - tileGap * (clothingColumns - 1)) /
        clothingColumns)
    local appearanceSlots = {}
    for _, slot in ipairs(Creator.clothingOrder) do
        if slot ~= "Faces" then appearanceSlots[#appearanceSlots + 1] = slot end
    end

    window.appearanceSlotOrder = appearanceSlots
    for index, slot in ipairs(appearanceSlots) do
        local clothingSlot = slot
        local column = (index - 1) % clothingColumns
        local row = math.floor((index - 1) / clothingColumns)
        local x, cy = px(12) + column * (columnW + tileGap), outfitsY + px(166) + row * (tileH + px(8))
        window.clothingCombos[slot] = Creator.addCombo(appearance, 0, 0, 1,
            Creator.clothingChoices[slot])
        window.clothingCombos[slot]:setVisible(false)
        local tile = Creator.addPickerTile(appearance, x, cy, columnW, tileH,
            string.upper(clothingSlot:gsub("(%l)(%u)", "%1 %2")), window.clothingCombos[clothingSlot], function()
            window.selectedClothingSlot = clothingSlot
            if window.outfitTintStatus then
                local tint = Creator.currentOutfitTints(window)[clothingSlot]
                window.outfitTintStatus:setName(string.upper(clothingSlot) .. " COLOR: " ..
                    (tint and "CUSTOM" or "NATIVE ITEM COLOR"))
            end
            Creator.openItemPicker(window, "clothing", clothingSlot,
                window.clothingCombos[clothingSlot], clothingSlot .. " choices")
        end, "Open the icon catalog for " .. clothingSlot .. ". Select up to four spawn choices.")
        Creator.setPickerTileClear(tile, function() return Creator.clearClothingSlot(window, clothingSlot) end)
        Creator.addTooltip(tile.openButton, "Click to choose clothing. Right-click to remove all choices from this slot.")
        window.appearanceTiles[#window.appearanceTiles + 1] = tile
    end

    local clothingRows = math.ceil(#appearanceSlots / clothingColumns)
    local tintY = outfitsY + px(166) + clothingRows * (tileH + px(8)) + px(2)
    window.selectedClothingSlot = "Top"
    window.outfitTintStatus = Creator.addLabel(appearance, px(12), tintY,
        "TOP COLOR: NATIVE ITEM COLOR", Creator.palette.ROSE)
    local nativeTint = Creator.addButton(appearance, px(12), tintY + px(24), px(76), "NATIVE", function()
        Creator.setOutfitTint(window, "native")
    end, true)
    Creator.addTooltip(nativeTint, "Keep the authored color of the selected clothing item. It stays stable across preview refreshes.")
    local tintPalette = {
        { r = 0.88, g = 0.87, b = 0.82 }, { r = 0.12, g = 0.15, b = 0.17 },
        { r = 0.45, g = 0.19, b = 0.12 }, { r = 0.15, g = 0.28, b = 0.43 },
        { r = 0.20, g = 0.35, b = 0.25 }, { r = 0.49, g = 0.39, b = 0.22 },
    }
    for index, color in ipairs(tintPalette) do
        local chosen = color
        local swatch = Creator.addButton(appearance, px(96) + (index - 1) * px(35),
            tintY + px(24), px(29), "", function() Creator.setOutfitTint(window, chosen) end)
        swatch.backgroundColor = { r = color.r, g = color.g, b = color.b, a = 1 }
        Creator.addTooltip(swatch, "Apply this exact color to the selected clothing slot.")
    end
    local customTintX = math.min(formW - px(128), px(318))
    Creator.addTooltip(Creator.addButton(appearance, customTintX, tintY + px(24),
        math.max(px(116), formW - customTintX - px(12)), "CUSTOM COLOR", function(_, button)
            Creator.openOutfitColorPicker(window, button)
        end), "Open the full color picker for the selected clothing slot.")
    Creator.scrollPage(appearance, tintY + px(70))
    Creator.installClothingFilters(window, appearance, formW, tintY, outfitsY + px(202))
end

function Creator.buildAppearanceMakeup(window, appearance, formW, top)
    local px = Creator.px
    local rowH = px(Creator.makeupRowHeight)
    window.profileMakeupLabels = {}
    window.profileMakeupBrowse = {}
    window.profileMakeupSwatches = {}
    for index, row in ipairs(Creator.makeupRows) do
        local slot, y = row[1], top + (index - 1) * rowH
        Creator.addLabel(appearance, px(12), y, row[2], Creator.palette.MUTED, nil, px(58))
        window.profileMakeupLabels[slot] = Creator.addLabel(appearance, px(74), y, "None", Creator.palette.TEXT)

        local swatch = ISPanel:new(formW - px(206), y - px(4), px(24), px(24))
        swatch:initialise()
        swatch.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        swatch.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        swatch.window, swatch.slot = window, slot
        swatch.prerender = function(self)
            ISPanel.prerender(self)
            local combo = self.window.clothingCombos
                and self.window.clothingCombos[self.slot]
            if not Creator.drawMakeupSwatch(self,
                    Creator.firstPoolChoice(Creator.selectedData(combo)), 0, 0, self.width) then
                self:drawRectBorder(0, 0, self.width, self.height, 0.8,
                    Creator.palette.CONTROL_BORDER.r, Creator.palette.CONTROL_BORDER.g, Creator.palette.CONTROL_BORDER.b)
            end
        end
        appearance:addChild(swatch)
        window.profileMakeupSwatches[slot] = swatch
        window.profileMakeupBrowse[slot] = Creator.addButton(appearance, formW - px(174), y - px(7),
            px(114), "CHOOSE", function()
                Creator.openItemPicker(window, "clothing", slot,
                    window.clothingCombos and window.clothingCombos[slot],
                    row[2] .. " makeup")
            end, true)
        Creator.installRightClickClear(window.profileMakeupBrowse[slot], function() return Creator.clearClothingSlot(window, slot) end)
        Creator.addTooltip(window.profileMakeupBrowse[slot],
            "Makeup for the outfit set selected below. The swatch is the shade itself: the game ships every lipstick and eyeshadow colour as its own item, and the face paints as textures, so there is no tint to pick. A beard is a model and makeup is a skin texture: the game always draws the beard over it.")
    end
    Creator.syncAppearanceMakeup(window)
    return top + #Creator.makeupRows * rowH + px(4)
end

function Creator.syncAppearanceMakeup(window)
    for _, row in ipairs(Creator.makeupRows) do
        local label = window.profileMakeupLabels and window.profileMakeupLabels[row[1]]
        if label then
            local browse = window.profileMakeupBrowse and window.profileMakeupBrowse[row[1]]
            local combo = window.clothingCombos and window.clothingCombos[row[1]]
            local name, _, count = Creator.poolVisual(Creator.selectedData(combo))
            if count == 0 then name = "None"
            elseif count > 1 then name = name .. " (+" .. tostring(count - 1) .. ")" end
            label:setName(Creator.fitText(name, UIFont.Small,
                math.max(Creator.px(30), (browse and browse.x or Creator.px(310)) - Creator.px(84))))
        end
    end
end

function Creator.installClothingFilters(window, appearance, formW, originalTintY, gridY)

    local px = Creator.px
    gridY = gridY or px(348)
    local armor = { LeftArm=true, RightArm=true, LeftForearm=true, RightForearm=true,
        LeftHand=true, RightHand=true, LeftShin=true, RightShin=true, LeftGaiter=true, RightGaiter=true,
        ShoulderPads=true, Gorget=true, Cuirass=true, Codpiece=true, LeftGreave=true, RightGreave=true,
        LeftKnee=true, RightKnee=true, LeftThigh=true, RightThigh=true, LeftShoulder=true, RightShoulder=true,
        LeftElbow=true, RightElbow=true, Webbing=true, BreathingGear=true }
    local layers = { UnderwearTop=true, UnderwearBottom=true, LongJohnsTop=true, LongJohnsBottom=true,
        TankTop=true, Tshirt=true, Sweater=true, Apron=true, FullSuit=true, FullRobe=true }
    local colors = {}
    for _, child in pairs(appearance.children or {}) do
        if child.y and child.y >= originalTintY then colors[#colors+1] = { child, child.y-originalTintY } end
    end
    local columns = formW >= px(480) and 3 or 2
    local tileW = math.floor((formW-px(24)-px(8)*(columns-1))/columns)
    local filters = { {"OUTFIT","core"}, {"ARMOR","armor"}, {"LAYERS","layers"},
        {"EXTRAS","extras"}, {"MAKEUP","makeup"}, {"ALL","all"} }
    local buttons = {}
    window.filterClothingSlots = function(selected)
        window.clothingFilter = selected
        local shown = 0
        for index, tile in ipairs(window.appearanceTiles) do

            local slot = (window.appearanceSlotOrder or Creator.clothingOrder)[index]
            local category = index <= 18 and "core"
                or string.sub(slot or "", 1, 6) == "MakeUp" and "makeup"
                or armor[slot] and "armor" or layers[slot] and "layers" or "extras"
            local visible = (selected == "all" or selected == category)
                and not (Creator.slotIsDead ~= nil and Creator.slotIsDead(slot))
            tile:setVisible(visible)
            if visible then
                tile:setX(px(12)+(shown%columns)*(tileW+px(8))); tile:setY(gridY+math.floor(shown/columns)*px(72))
                shown=shown+1
            end
        end
        local tintY = gridY+math.ceil(shown/columns)*px(72)+px(2)
        for _, entry in ipairs(colors) do entry[1]:setY(tintY+entry[2]) end
        for id, button in pairs(buttons) do Creator.styleButton(button,id==selected) end
        appearance:setYScroll(0)
        appearance:setScrollHeight(math.max(appearance.height,tintY+px(70)))
    end

    local buttonW = math.floor((formW-px(24)-5*px(4))/6)
    for index, spec in ipairs(filters) do
        local id=spec[2]
        buttons[id]=Creator.addButton(appearance,px(12)+(index-1)*(buttonW+px(4)),gridY-px(36),buttonW,spec[1],function()
            window.filterClothingSlots(id)
        end)
    end
    window.filterClothingSlots(window.clothingFilter or "core")
end

Creator.previewItemPrefixes = { "ProjectALife.PALPreview_", "ProjectALife.PALDevOverlay_" }

function Creator.isPreviewItem(fullType)
    if type(fullType) ~= "string" then return false end
    for _, prefix in ipairs(Creator.previewItemPrefixes) do
        if string.sub(fullType, 1, #prefix) == prefix then return true end
    end
    return false
end

function Creator.filterBodyLocationItems(location)
    local items = Creator.bodyLocationItemsOriginal(location)
    if type(items) ~= "table" then return items end
    local kept = {}
    for _, fullType in ipairs(items) do
        if not Creator.isPreviewItem(fullType) then kept[#kept + 1] = fullType end
    end
    return kept
end

function Creator.installBodyLocationFilter()
    if Creator.bodyLocationItemsOriginal ~= nil then return false end
    if type(getAllItemsForBodyLocation) ~= "function" then return false end
    Creator.bodyLocationItemsOriginal = getAllItemsForBodyLocation
    getAllItemsForBodyLocation = Creator.filterBodyLocationItems
    return true
end

Creator.installBodyLocationFilter()

return Creator
