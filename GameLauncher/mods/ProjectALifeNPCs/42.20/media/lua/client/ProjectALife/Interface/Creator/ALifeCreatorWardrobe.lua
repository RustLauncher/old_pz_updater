require "ProjectALife/Interface/Creator/ALifeCreatorCore"
require "ProjectALife/Records/ALifeSeasonalWardrobe"
require "ProjectALife/Records/ALifeSeasonalOutfitGenerator"
require "ISUI/ISUI3DModel"

local Creator = ProjectALife.CreatorScreen

Creator.seasonSpecs = {
    { id = "A", season = "spring", label = "Spring" },
    { id = "B", season = "summer", label = "Summer" },
    { id = "C", season = "autumn", label = "Autumn" },
    { id = "D", season = "winter", label = "Winter" },
}

function Creator.copyFactionWardrobe(record, faction)
    for _, spec in ipairs(Creator.seasonSpecs) do
        faction["outfit" .. spec.id] = Creator.deepCopy(record["outfit" .. spec.id])
        faction["tint" .. spec.id] = Creator.deepCopy(record["tint" .. spec.id])
    end
    faction.outfitSeason = Creator.deepCopy(record.outfitSeason or {})
    faction.outfitNames = Creator.deepCopy(record.outfitNames or {})
    return faction
end

function Creator.memberSeasonTitle(profile, id, status)
    local season = profile.outfitSeason and profile.outfitSeason[id]
    local suffix = status == " +" and " +" or status == "  OFF" and " -" or ""
    for _, spec in ipairs(Creator.seasonSpecs) do
        if spec.season == season then return id .. " " .. spec.label .. suffix end
    end
    return id .. " Any" .. suffix
end

Creator.seasonStatusCache = {}

function Creator.invalidateFactionSeasonStatus(faction)
    if type(faction) == "table" and type(faction.id) == "string" then
        Creator.seasonStatusCache[faction.id] = nil
    else
        Creator.seasonStatusCache = {}
    end
end

function Creator.factionSeasonStatus(faction)
    local id = type(faction) == "table" and faction.id or nil
    local entry = type(id) == "string" and Creator.seasonStatusCache[id] or nil
    if entry ~= nil and entry.record == faction and entry.outfitA == faction.outfitA and entry.outfitB == faction.outfitB
            and entry.outfitC == faction.outfitC and entry.outfitD == faction.outfitD
            and entry.outfitSeason == faction.outfitSeason then
        return entry.text, entry.count
    end
    local count = ProjectALife.SeasonalWardrobe.coverage(faction)
    local text = tostring(count) .. "/4 seasons"
    if type(id) == "string" then
        Creator.seasonStatusCache[id] = { record = faction, outfitA = faction.outfitA, outfitB = faction.outfitB,
            outfitC = faction.outfitC, outfitD = faction.outfitD, outfitSeason = faction.outfitSeason,
            text = text, count = count }
    end
    return text, count
end

function Creator.drawFactionSeasonBadge(card)
    local text, count = Creator.factionSeasonStatus(card.record)
    local color = count == 4 and Creator.palette.TEXT or Creator.palette.ROSE
    card:drawTextRight(text, card.width - Creator.px(8), Creator.px(14),
        color.r, color.g, color.b, 1, UIFont.Small)
end

function Creator.wardrobePreviewProfile(window, row)
    local profile = ProjectALife.CustomProfiles.blank("wardrobe_" .. tostring(window.currentFaction and window.currentFaction.id or "preview"))
    if window.currentProfile then profile.general = Creator.deepCopy(window.currentProfile.general) end
    profile.outfits = { [row.id] = Creator.deepCopy(row.clothing) }
    profile.outfitTints = { [row.id] = Creator.deepCopy(row.tints) }
    profile.clothing = profile.outfits[row.id]
    return profile
end

function Creator.syncFactionWardrobe(window)
    if not window.currentFaction or not window.factionSeasonRows then return end
    local rows = ProjectALife.SeasonalWardrobe.rows(window.currentFaction)
    local badge, count = Creator.factionSeasonStatus(window.currentFaction)
    window.factionWardrobeStatus:setName(badge .. (count < 4 and " - incomplete or fewer distinct outfits" or " - four distinct seasonal outfits"))
    for index, row in ipairs(rows) do
        local ui = window.factionSeasonRows[index]
        ui.data = row
        ui.label:setName(row.id .. " - " .. row.label)
        ui.name:setName(Creator.fitText(row.name, UIFont.Small, math.max(20, ui.width - Creator.px(205))))
        local signature = Creator.signature({ row.clothing, row.tints, window.currentProfile and window.currentProfile.general.female })
        if signature ~= ui.previewSignature then
            ui.previewSignature = signature
            local profile = Creator.wardrobePreviewProfile(window, row)
            local desc, _, visualSignature = Creator.createPortraitDescriptor(profile, row.id, ui.tintCache, 0)
            Creator.markModelDirty(ui.model, desc, "idle", visualSignature)
        end
    end
end

function Creator.closeFactionWardrobeEditor(window)
    local editor = window.factionWardrobeEditor
    if not editor then return end
    Creator.closeItemPicker(editor)
    if editor.parent then editor.parent:removeChild(editor) end
    window.factionWardrobeEditor = nil
end

function Creator.editFactionSeason(window, id)
    if not window.currentFaction or not Creator.flushEdits(window) then return false end
    Creator.closeFactionWardrobeEditor(window)
    local px = Creator.px
    local width, height = math.min(window.width - px(32), px(900)), math.max(px(380), window.height - px(48))
    local editor = Creator.createFramedPanel(window, math.floor((window.width - width) / 2), px(24), width, height)
    editor.backgroundColor = { r = 0.025, g = 0.028, b = 0.035, a = 1 }
    editor.currentFaction = window.currentFaction
    editor.seasonFixed = true
    editor.currentProfile = ProjectALife.CustomProfiles.blank("wardrobe_editor")
    if window.currentProfile then editor.currentProfile.general = Creator.deepCopy(window.currentProfile.general) end
    editor.currentProfile.outfits, editor.currentProfile.outfitTints = {}, {}
    editor.currentProfile.outfitSeason = Creator.deepCopy(window.currentFaction.outfitSeason)
    for _, row in ipairs(ProjectALife.SeasonalWardrobe.rows(window.currentFaction)) do
        editor.currentProfile.outfits[row.id] = Creator.deepCopy(row.clothing)
        editor.currentProfile.outfitTints[row.id] = Creator.deepCopy(row.tints)
    end
    editor.currentProfile.clothing = Creator.deepCopy(editor.currentProfile.outfits.A)
    Creator.addLabel(editor, px(16), px(12), "FACTION WARDROBE - " .. tostring(window.currentFaction.general.name), Creator.palette.ROSE, UIFont.Medium)
    Creator.addLabel(editor, px(16), px(31), Creator.seasonHint(), Creator.palette.MUTED)
    local page = ISPanel:new(px(12), px(48), width - px(24), height - px(100))
    page:initialise()
    editor:addChild(page)
    editor.profilePages = { appearance = page }
    Creator.buildAppearancePage(editor, page.width)
    Creator.showOutfit(editor, id, true)
    Creator.addButton(editor, px(16), height - px(40), px(130), "CANCEL", function() Creator.closeFactionWardrobeEditor(window) end)
    Creator.addButton(editor, width - px(190), height - px(40), px(174), "SAVE WARDROBE", function()
        Creator.showOutfit(editor, editor.activeOutfit)
        for _, spec in ipairs(Creator.seasonSpecs) do
            window.currentFaction["outfit" .. spec.id] = Creator.deepCopy(editor.currentProfile.outfits[spec.id])
            window.currentFaction["tint" .. spec.id] = Creator.deepCopy(editor.currentProfile.outfitTints[spec.id])
        end
        window.currentFaction.outfitSeason = Creator.deepCopy(editor.currentProfile.outfitSeason)
        Creator.invalidateFactionSeasonStatus(window.currentFaction)
        Creator.syncFactionWardrobe(window)
        if Creator.saveFaction(window) then Creator.closeFactionWardrobeEditor(window) end
    end, true)
    window.factionWardrobeEditor = editor
    editor:bringToTop()
    return true
end

function Creator.buildFactionWardrobePage(window)
    local page, px = window.factionEditorPages.wardrobe, Creator.px
    Creator.addLabel(page, px(10), px(4), "WARDROBE BY SEASON", Creator.palette.ROSE, UIFont.Medium)
    window.factionWardrobeStatus = Creator.addLabel(page, px(10), px(32), "0/4 seasons - incomplete", Creator.palette.MUTED)
    Creator.addLabel(page, px(10), px(56), "Faction defaults; enabled member seasonal outfits take priority.", Creator.palette.MUTED)
    window.factionSeasonRows = {}
    for index, spec in ipairs(Creator.seasonSpecs) do
        local row = ISPanel:new(px(10), px(88) + (index - 1) * px(130), page.width - px(24), px(122))
        row:initialise()
        row.id, row.owner, row.tintCache = spec.id, window, {}
        row.backgroundColor = { r = 0.045, g = 0.05, b = 0.06, a = 0.95 }
        page:addChild(row)
        row.label = Creator.addLabel(row, px(112), px(16), spec.id .. " - " .. spec.label, Creator.palette.TEXT, UIFont.Medium)
        row.name = Creator.addLabel(row, px(112), px(49), spec.label .. " outfit", Creator.palette.MUTED)
        row.model = ISUI3DModel:new(px(4), px(3), px(100), px(116))
        row.model:initialise()
        row:addChild(row.model)
        row.model.palAnimate = false
        row.model.prerender = function(model)
            if type(ISUI3DModel.prerender) == "function" then ISUI3DModel.prerender(model) end
            if model.javaObject and type(model.setSurvivorDesc) == "function" and type(model.setState) == "function" then Creator.submitPortrait(model) end
            if model.javaObject and type(model.javaObject.setAnimate) == "function" then model.javaObject:setAnimate(false) end
        end
        if row.model.javaObject then
            for method, value in pairs({ setDirection = IsoDirections.S, setIsometric = false, setDoRandomExtAnimations = false, setZoom = -3, setYOffset = 0 }) do
                if type(row.model[method]) == "function" then row.model[method](row.model, value) end
            end
        end
        row.editButton = Creator.addButton(row, row.width - px(92), px(76), px(80), "EDIT", function() Creator.editFactionSeason(window, spec.id) end, true)
        window.factionSeasonRows[index] = row
    end
    Creator.buildSeasonalActions(window, page, px(618))
    Creator.scrollPage(page, px(756))
end

function Creator.buildSeasonalActions(window, page, y)
    local px = Creator.px
    local width = math.max(px(100), math.floor((page.width - px(30)) / 2))
    Creator.addButton(page, px(10), y, width, "GENERATE THIS FACTION", function() Creator.previewSeasonalAction(window, false, false) end, true)
    Creator.addButton(page, px(18) + width, y, width, "GENERATE ALL FACTIONS", function() Creator.previewSeasonalAction(window, true, false) end)
    Creator.addButton(page, px(10), y + px(34), width, "UPDATE FROM SHIPPED", function() Creator.previewSeasonalAction(window, false, true) end)
    Creator.addButton(page, px(18) + width, y + px(34), width, "SHOW SHIPPED ONLY", function(_, button)
        window.seasonalShippedOnly = not window.seasonalShippedOnly
        button:setTitle(window.seasonalShippedOnly and "SHOW ALL FACTIONS" or "SHOW SHIPPED ONLY")
        window.factionPage = 1
        Creator.rebuildFactionCards(window)
        Creator.setRootPage(window, "workbench")
    end)
    Creator.addLabel(page, px(10), y + px(68), "Generate fills missing sets and season tags. NPCs that already have their own untagged outfits are skipped:", Creator.palette.MUTED, UIFont.Small, page.width - px(24))
    Creator.addLabel(page, px(10), y + px(88), "their outfits and tags stay exactly as authored, and the game still dresses them for the season on its own.", Creator.palette.MUTED, UIFont.Small, page.width - px(24))
end

return Creator
