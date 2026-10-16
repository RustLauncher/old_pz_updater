require "ProjectALife/Interface/Creator/ALifeCreatorCore"

local Creator = ProjectALife.CreatorScreen

function Creator.buildLoadoutPage(window, formW)
    local px = Creator.px
    local loadout = window.profilePages.loadout
    Creator.addLabel(loadout, px(12), 0, "LOADOUT", Creator.palette.TEXT, UIFont.Medium)
    window.multipleWeapons = Creator.addTick(loadout, px(110), 0, math.max(px(240), formW - px(122)),
        "Enable multiple options")
    Creator.addTooltip(window.multipleWeapons, "Keep up to four random spawn options per weapon slot. Off: the next click replaces the slot.")
    window.primaryCombo = Creator.addCombo(loadout, 0, 0, 1, Creator.primaryWeaponChoices)
    window.secondaryCombo = Creator.addCombo(loadout, 0, 0, 1, Creator.primaryWeaponChoices)
    window.meleeCombo = Creator.addCombo(loadout, 0, 0, 1, Creator.meleeWeaponChoices)
    window.primaryCombo:setVisible(false)
    window.secondaryCombo:setVisible(false)
    window.meleeCombo:setVisible(false)
    window.weaponTiles = {}
    local weaponColumns = formW >= px(500) and 3 or 1
    local weaponGap, weaponTileH = px(8), px(76)
    local weaponTileW = math.floor((formW - px(24) - weaponGap * (weaponColumns - 1)) /
        weaponColumns)
    local weaponSpecs = {
        { "PRIMARY", "firearm", "primary", window.primaryCombo,
            "Main weapon carried in hand." },
        { "SIDEARM", "firearm", "secondary", window.secondaryCombo,
            "Backup firearm available when the primary is unsuitable." },
        { "MELEE / BELT", "melee", "melee", window.meleeCombo,
            "Close-range fallback carried on the belt or back." },
    }
    for index, spec in ipairs(weaponSpecs) do
        local title, kind, slot, combo, help = spec[1], spec[2], spec[3], spec[4], spec[5]
        local column, row = (index - 1) % weaponColumns,
            math.floor((index - 1) / weaponColumns)
        local tile = Creator.addPickerTile(loadout,
            px(12) + column * (weaponTileW + weaponGap),
            px(34) + row * (weaponTileH + px(8)), weaponTileW, weaponTileH,
            title, combo, function()
                Creator.openItemPicker(window, kind, slot, combo, title .. " choices")
            end, help .. " Click to open the full vanilla and modded icon catalog. Right-click to clear this slot.")
        Creator.setPickerTileClear(tile, function()
            return Creator.clearLoadoutSlot(window, slot, combo)
        end)
        window.weaponTiles[#window.weaponTiles + 1] = tile
    end
    local weaponRows = math.ceil(#weaponSpecs / weaponColumns)
    local ammoY = px(44) + weaponRows * (weaponTileH + px(8))
    local wideAmmo = formW >= px(560)
    local ammoCardH = wideAmmo and px(218) or px(254)
    local ammoCard = Creator.addSectionCard(loadout, px(4), ammoY, formW - px(8), ammoCardH,
        "AMMUNITION", "Counts are complete magazines, tubes or cylinders - not loose rounds.")
    if wideAmmo then
        local ammoHalf = math.floor((ammoCard.width - px(34)) / 2)
        Creator.addLabel(ammoCard, px(12), px(54), "Primary magazines", Creator.palette.MUTED)
        window.primaryMagazines = Creator.addEntry(ammoCard, px(132), px(51), px(56), "0", true)
        window.primaryCapacityLabel = Creator.addLabel(ammoCard, px(198), px(55), "", Creator.palette.TEXT)
        Creator.addLabel(ammoCard, px(12) + ammoHalf + px(10), px(54), "Sidearm magazines", Creator.palette.MUTED)
        window.secondaryMagazines = Creator.addEntry(ammoCard, px(132) + ammoHalf + px(10), px(51), px(56), "0", true)
        window.secondaryCapacityLabel = Creator.addLabel(ammoCard,
            px(198) + ammoHalf + px(10), px(55), "", Creator.palette.TEXT)
        window.infiniteAmmo = Creator.addTick(ammoCard, px(12), px(91), ammoCard.width - px(24),
            "Infinite ammunition")
    else
        Creator.addLabel(ammoCard, px(12), px(54), "Primary magazines", Creator.palette.MUTED)
        window.primaryMagazines = Creator.addEntry(ammoCard, px(132), px(51), px(52), "0", true)
        window.primaryCapacityLabel = Creator.addLabel(ammoCard, px(194), px(55), "", Creator.palette.TEXT)
        Creator.addLabel(ammoCard, px(12), px(90), "Sidearm magazines", Creator.palette.MUTED)
        window.secondaryMagazines = Creator.addEntry(ammoCard, px(132), px(87), px(52), "0", true)
        window.secondaryCapacityLabel = Creator.addLabel(ammoCard, px(194), px(91), "", Creator.palette.TEXT)
        window.infiniteAmmo = Creator.addTick(ammoCard, px(12), px(127), ammoCard.width - px(24),
            "Infinite ammunition")
    end
    Creator.addTooltip(window.infiniteAmmo,
        "Unlimited combat reloads. Death loot still rolls once per authored magazine below.")
    window.dropAmmo = Creator.addTick(ammoCard, px(12), ammoCardH - px(79), ammoCard.width - px(24),
        "Drop magazines on death")
    Creator.addLabel(ammoCard, px(12), ammoCardH - px(42), "Magazine drop chance (%)", Creator.palette.MUTED)
    window.magazineDropChance = Creator.addEntry(ammoCard, px(190), ammoCardH - px(45), px(56), "35", true)
    Creator.addTooltip(window.magazineDropChance,
        "One independent roll per primary/sidearm magazine. Three magazines at 20% means three rolls, even with infinite ammo. Fixed magazines drop loose rounds.")
    local attachmentsY = ammoY + ammoCardH + px(10)
    window.weaponAttachmentsButton = Creator.addButton(loadout, px(4), attachmentsY,
        formW - px(8), "FIREARM ATTACHMENTS", function()
            Creator.harvestProfile(window)
            Creator.openWeaponAttachmentPicker(window)
        end, true)
    Creator.addTooltip(window.weaponAttachmentsButton,
        "Configure compatible scopes, sights, slings, recoil pads and other parts for the selected firearms.")

    Creator.scrollPage(loadout, attachmentsY + px(80))
    window.primaryAmmo, window.secondaryAmmo, window.ammoMode = nil, nil, nil
    window.syncLoadoutTiles = function()
        Creator.syncPickerTiles(window.appearanceTiles)
        Creator.syncAppearanceMakeup(window)
        Creator.syncPickerTiles(window.weaponTiles)
        local primary = Creator.firstPoolChoice(Creator.selectedData(window.primaryCombo))
        local secondary = Creator.firstPoolChoice(Creator.selectedData(window.secondaryCombo))
        local primaryCapacity, secondaryCapacity = Creator.itemCapacity(primary),
            Creator.itemCapacity(secondary)
        local primaryMags = math.max(0, math.floor(tonumber(
            window.primaryMagazines:getText()) or 0))
        local secondaryMags = math.max(0, math.floor(tonumber(
            window.secondaryMagazines:getText()) or 0))
        window.primaryCapacityLabel:setName(primaryCapacity > 0 and
            (tostring(primaryCapacity) .. " each | " ..
                tostring(primaryCapacity * primaryMags) .. " total") or "-")
        window.secondaryCapacityLabel:setName(secondaryCapacity > 0 and
            (tostring(secondaryCapacity) .. " each | " ..
                tostring(secondaryCapacity * secondaryMags) .. " total") or "-")
        if window.currentProfile then
            window.currentProfile.weapons = window.currentProfile.weapons or {}
            window.currentProfile.weapons.primary = Creator.selectedData(window.primaryCombo) or "none"
            window.currentProfile.weapons.secondary = Creator.selectedData(window.secondaryCombo) or "none"
            window.currentProfile.weapons.melee = Creator.selectedData(window.meleeCombo) or "none"
            local weaponSignature = table.concat({
                tostring(window.currentProfile.weapons.primary),
                tostring(window.currentProfile.weapons.secondary),
                tostring(window.currentProfile.weapons.melee),
            }, "\31")
            if weaponSignature ~= window.avatarWeaponSignature then
                window.avatarWeaponSignature = weaponSignature
                Creator.refreshAvatar(window)
            else
                Creator.refreshAvatarLoadout(window)
            end
        end
    end
end

return Creator
