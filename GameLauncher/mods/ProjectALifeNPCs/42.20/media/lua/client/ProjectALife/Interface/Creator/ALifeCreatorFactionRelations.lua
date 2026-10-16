require "ProjectALife/Interface/Creator/ALifeCreatorCore"
require "ProjectALife/Core/ALifeText"
require "ProjectALife/Records/ALifeRelationLayers"

local Creator = ProjectALife.CreatorScreen

Creator.relationViewIds = { "faction", "folder", "profession" }

Creator.professionFallback = {
    { "burgerflipper", "Burger Flipper" }, { "burglar", "Burglar" }, { "carpenter", "Carpenter" },
    { "chef", "Chef" }, { "constructionworker", "Construction Worker" }, { "doctor", "Doctor" },
    { "electrician", "Electrician" }, { "engineer", "Engineer" }, { "farmer", "Farmer" },
    { "fireofficer", "Firefighter" }, { "fisherman", "Fishing Guide" },
    { "fitnessinstructor", "Fitness Instructor" }, { "lumberjack", "Lumberjack" },
    { "mechanics", "Mechanic" }, { "metalworker", "Welder" }, { "nurse", "Nurse" },
    { "parkranger", "Park Ranger" }, { "policeofficer", "Police Officer" }, { "rancher", "Rancher" },
    { "repairman", "DIY Expert" }, { "securityguard", "Security Guard" }, { "smither", "Blacksmith" },
    { "tailor", "Tailor" }, { "unemployed", "Unemployed" }, { "veteran", "Veteran" },
}

local function copyColor(value)
    return { r = value.r, g = value.g, b = value.b, a = value.a }
end

function Creator.relationViewLabel(id)
    if id == "folder" then return ProjectALife.Text.ui("BY FOLDER") end
    if id == "profession" then return ProjectALife.Text.ui("BY PROFESSION") end
    return ProjectALife.Text.ui("BY FACTION")
end

function Creator.relationViewHint(id)
    if id == "folder" then
        return ProjectALife.Text.ui("One stance toward every faction in a folder. It overrides their rows until you change one.")
    end
    if id == "profession" then
        return ProjectALife.Text.ui("Toward players by profession. Encounters still roll on the player disposition.")
    end
    return ProjectALife.Text.ui("Toward each faction. A folder override shows its folder; change the row to make an exception.")
end

function Creator.relationSearchHint(id)
    if id == "folder" then return ProjectALife.Text.ui("Search folder...") end
    if id == "profession" then return ProjectALife.Text.ui("Search profession...") end
    return ProjectALife.Text.ui("Search faction name...")
end

function Creator.relationLabel(word)
    for _, spec in ipairs(Creator.relationChoices) do
        if spec[2] == word then return spec[1] end
    end
    return tostring(word or "-")
end

function Creator.relationWhy(layer, bloc, shift)
    if layer == "bloc" then return ProjectALife.Text.ui("bloc {bloc}", { bloc = tostring(bloc) }) end
    if layer == "unknown" then return ProjectALife.Text.ui("unknown factions") end
    if layer == "legacy" then return ProjectALife.Text.ui("spawn flag") end
    if layer == "faction" then return ProjectALife.Text.ui("player disposition") end
    if layer == "profession_default" then
        if (tonumber(shift) or 0) > 0 then
            return ProjectALife.Text.ui("{bloc} +{shift}", { bloc = tostring(bloc), shift = tostring(shift) })
        end
        return ProjectALife.Text.ui("{bloc} {shift}", { bloc = tostring(bloc), shift = tostring(shift) })
    end
    return ""
end

function Creator.relationDefaultLabel(word, why)
    if why ~= nil and why ~= "" then
        return ProjectALife.Text.ui("Default ({word} - {why})", { word = Creator.relationLabel(word), why = why })
    end
    return ProjectALife.Text.ui("Default ({word})", { word = Creator.relationLabel(word) })
end

function Creator.buildFactionRelationsPage(window)
    local px = Creator.px
    local page = window.factionEditorPages.relations
    Creator.addLabel(page, px(10), px(12), ProjectALife.Text.ui("RELATIONS"), Creator.palette.ROSE)
    window.effectiveRelationStatus = Creator.addLabel(page, px(10), px(40),
        ProjectALife.Text.ui("PLAYER  -"), Creator.palette.TEXT)
    Creator.addButton(page, page.width - px(126), px(32), px(116), ProjectALife.Text.ui("REFRESH LIVE"), function()
        local store = ProjectALife.StatusStore
        local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil
        if store and player then store.request(player) end
        window.relationStatusAt = nil
        Creator.refreshEffectiveRelation(window)
    end, true)
    window.relationViewButtons = {}
    local count = #Creator.relationViewIds
    local tabW = math.floor((page.width - px(20) - (count - 1) * px(5)) / count)
    for index, id in ipairs(Creator.relationViewIds) do
        local button = Creator.addButton(page, px(10) + (index - 1) * (tabW + px(5)), px(70), tabW,
            Creator.relationViewLabel(id), function() Creator.setRelationView(window, id) end)
        Creator.addTooltip(button, Creator.relationViewHint(id))
        window.relationViewButtons[id] = button
    end
    window.relationSearch = Creator.addEntry(page, px(10), px(104), page.width - px(20), "")
    local top = px(136)
    window.relationAreas = {}
    for _, id in ipairs(Creator.relationViewIds) do
        local area = ISPanel:new(px(10), top, page.width - px(20), page.height - top - px(12))
        area:initialise()
        area.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        area.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        page:addChild(area)
        Creator.scrollPage(area)
        window.relationAreas[id] = area
    end
    window.relationListArea = window.relationAreas.faction
    window.relationFolderArea = window.relationAreas.folder
    window.relationProfessionArea = window.relationAreas.profession
    Creator.setRelationView(window, "faction")
end

function Creator.setRelationView(window, id)
    if window.relationAreas == nil or window.relationAreas[id] == nil then return false end

    local relations = window.currentFaction and window.currentFaction.relations
    if relations then Creator.harvestRelationRows(window, relations) end
    window.relationView = id
    for viewId, area in pairs(window.relationAreas) do area:setVisible(viewId == id) end
    for viewId, button in pairs(window.relationViewButtons or {}) do
        Creator.styleButton(button, viewId == id)
    end
    if window.relationSearch and type(window.relationSearch.setPlaceholderText) == "function" then
        window.relationSearch:setPlaceholderText(Creator.relationSearchHint(id))
    end
    Creator.rebuildRelationView(window)
    return true
end

function Creator.rebuildRelationView(window)
    local view = window.relationView or "faction"
    if view == "folder" then return Creator.rebuildRelationFolders(window) end
    if view == "profession" then return Creator.rebuildRelationProfessions(window) end
    return Creator.rebuildRelationControls(window)
end

function Creator.fillFactionRelations(window)
    Creator.rebuildRelationControls(window)
    Creator.rebuildRelationFolders(window)
    Creator.rebuildRelationProfessions(window)
    window.relationStatusAt = nil
end

function Creator.relationQuery(window)
    return string.lower(tostring(window.relationSearch and window.relationSearch:getText() or ""))
end

function Creator.relationMatches(query, name, id)
    if query == "" then return true end
    return string.find(string.lower(tostring(name)), query, 1, true) ~= nil
        or string.find(string.lower(tostring(id)), query, 1, true) ~= nil
end

function Creator.clearRelationArea(window, area, key)
    for _, control in ipairs(window[key] or {}) do
        control:setVisible(false)
        if type(area.removeChild) == "function" then area:removeChild(control) end
    end
    window[key] = {}
end

function Creator.relationCard(area, row, name, badge, options, value)
    local px, palette = Creator.px, Creator.palette
    local narrow = area.width < px(630)
    local card = ISPanel:new(0, row * px(76), area.width - px(12), px(68))
    card:initialise()
    card.backgroundColor = copyColor(palette.CARD_BG)
    card.borderColor = copyColor(palette.CONTROL_BORDER)
    area:addChild(card)
    local nameRoom = narrow and math.floor(card.width * 0.58) or math.floor(card.width * 0.44)
    Creator.addLabel(card, px(12), narrow and px(5) or px(12), name, palette.TEXT, nil, nameRoom)
    local badgeX = narrow and math.floor(card.width * 0.62) or px(12)
    card.alifeBadge = Creator.addLabel(card, badgeX, narrow and px(5) or px(36), badge or "",
        palette.MUTED, nil, narrow and card.width - badgeX - px(12) or nameRoom)
    local combo = Creator.addCombo(card, narrow and px(12) or math.floor(card.width * 0.48),
        narrow and px(32) or px(21),
        narrow and card.width - px(24) or math.floor(card.width * 0.52) - px(12), options)
    Creator.selectData(combo, value)
    combo.alifeBadge = card.alifeBadge
    return card, combo
end

function Creator.relationOptions(defaultLabel, extra)
    local options = { { defaultLabel, "inherit" } }
    for _, spec in ipairs(Creator.relationChoices) do options[#options + 1] = spec end
    if extra ~= nil then options[#options + 1] = extra end
    return options
end

function Creator.rebuildRelationControls(window)
    local area = window.relationListArea
    if not area then return end
    Creator.clearRelationArea(window, area, "relationControls")
    window.relationCombos = {}
    local layers, folders = ProjectALife.RelationLayers, ProjectALife.CreatorFolders
    local faction = window.currentFaction
    local relations = faction and faction.relations or {}
    local query, row = Creator.relationQuery(window), 0
    for _, record in ipairs(window.catalog and window.catalog.factionOrder or {}) do
        local name = Creator.safeText(record.general and record.general.name or record.id)
        if (not faction or record.id ~= faction.id) and Creator.relationMatches(query, name, record.id) then
            local inherited, layer, bloc = layers.inheritedTowardFaction(faction or {}, record)
            local options = Creator.relationOptions(Creator.relationDefaultLabel(inherited,
                Creator.relationWhy(layer, bloc)))
            local override = layers.word(relations[layers.folderKey(record.id)])
            local value, badge = relations[record.id] or "inherit", ""
            if override ~= nil then
                local folder = folders and folders.folderForFaction(record.id) or nil
                value = override
                if folder ~= nil then
                    local folderName = Creator.safeText(folder.name)
                    badge = ProjectALife.Text.ui("FOLDER  {name}", { name = folderName })
                else
                    badge = ProjectALife.Text.ui("FOLDER OVERRIDE")
                end
            elseif relations[record.id] ~= nil then
                badge = ProjectALife.Text.ui("SET HERE")
            end
            local card, combo = Creator.relationCard(area, row, name, badge, options, value)
            combo.alifeOverride = override
            window.relationControls[#window.relationControls + 1] = card
            window.relationCombos[record.id] = combo
            row = row + 1
        end
    end
    if area.setScrollHeight then area:setScrollHeight(math.max(area.height, row * Creator.px(76))) end
end

function Creator.folderMembers(window, folderId)
    local folders = ProjectALife.CreatorFolders
    local folder = folders and folders.get(folderId) or nil
    local members = {}
    if folder == nil then return members end
    local current = window.currentFaction and window.currentFaction.id or nil
    local known = window.catalog and window.catalog.factions or {}
    for id, filed in pairs(folder.factions or {}) do
        if filed == true and id ~= current and known[id] ~= nil then members[#members + 1] = id end
    end
    table.sort(members, function(a, b)
        local ra, rb = folders.rank(a), folders.rank(b)
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    return members
end

function Creator.folderRelationState(window, folderId)
    local layers = ProjectALife.RelationLayers
    local relations = window.currentFaction and window.currentFaction.relations or {}
    local members = Creator.folderMembers(window, folderId)
    local common, set = nil, 0
    for _, id in ipairs(members) do
        local word = layers.word(relations[layers.folderKey(id)])
        if word ~= nil then
            set = set + 1
            if common == nil then common = word elseif common ~= word then common = "mixed" end
        end
    end
    if set == 0 then return "inherit", 0, members end
    if set < #members then common = "mixed" end
    return common, set, members
end

function Creator.rebuildRelationFolders(window)
    local area = window.relationFolderArea
    if not area then return end
    Creator.clearRelationArea(window, area, "relationFolderControls")
    window.relationFolderCombos = {}
    window.relationFoldersStale = nil
    local folders = ProjectALife.CreatorFolders
    local query, row = Creator.relationQuery(window), 0
    for _, folder in ipairs(folders and folders.folders or {}) do
        if Creator.relationMatches(query, folder.name, folder.id) then
            local common, set, members = Creator.folderRelationState(window, folder.id)
            local extra = nil
            if common == "mixed" then
                extra = { ProjectALife.Text.ui("Mixed ({set} of {count})", { set = set, count = #members }), "mixed" }
            end
            local badge = ProjectALife.Text.ui("{count} factions", { count = #members })
            if set > 0 then
                badge = ProjectALife.Text.ui("{count} factions  -  override on {set}", { count = #members, set = set })
            end
            local folderName = Creator.safeText(folder.name)
            local card, combo = Creator.relationCard(area, row, folderName, badge,
                Creator.relationOptions(ProjectALife.Text.ui("No override"), extra), common)
            combo.alifeFolderId, combo.target = folder.id, window
            combo.onChange = Creator.onFolderRelationChanged
            window.relationFolderControls[#window.relationFolderControls + 1] = card
            window.relationFolderCombos[folder.id] = combo
            row = row + 1
        end
    end
    if area.setScrollHeight then area:setScrollHeight(math.max(area.height, row * Creator.px(76))) end
end

function Creator.onFolderRelationChanged(window, combo)
    if combo == nil then return end
    Creator.applyFolderRelation(window, combo.alifeFolderId, Creator.selectedData(combo))
end

function Creator.applyFolderRelation(window, folderId, value)
    local faction = window and window.currentFaction
    if faction == nil or value == nil or value == "mixed" then return false, 0 end
    local layers = ProjectALife.RelationLayers
    faction.relations = faction.relations or {}
    Creator.harvestRelationRows(window, faction.relations)
    local members = Creator.folderMembers(window, folderId)
    for _, id in ipairs(members) do
        if value == "inherit" then
            faction.relations[layers.folderKey(id)] = nil
        else
            faction.relations[layers.folderKey(id)] = value
        end
    end
    Creator.rebuildRelationControls(window)
    window.relationFoldersStale = true
    return true, #members
end

function Creator.professionList()
    if Creator.professionCache ~= nil then return Creator.professionCache end
    local list, seen = {}, {}
    local layers, definitions = ProjectALife.RelationLayers, CharacterProfessionDefinition
    local all = nil
    if definitions ~= nil and type(definitions.getProfessions) == "function" then all = definitions.getProfessions() end
    local size = all ~= nil and type(all.size) == "function" and all:size() or 0
    for index = 0, size - 1 do
        local definition = all:get(index)
        local profession = nil
        if definition ~= nil and type(definition.getType) == "function" then profession = definition:getType() end
        local id = layers.professionId(profession)
        if id ~= nil and not seen[id] then
            seen[id] = true
            local label = type(definition.getUIName) == "function" and definition:getUIName() or nil
            list[#list + 1] = { id, tostring(label or id) }
        end
    end
    if #list == 0 then

        for _, spec in ipairs(Creator.professionFallback) do list[#list + 1] = { spec[1], spec[2] } end
        return list
    end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    Creator.professionCache = list
    return list
end

function Creator.rebuildRelationProfessions(window)
    local area = window.relationProfessionArea
    if not area then return end
    Creator.clearRelationArea(window, area, "relationProfessionControls")
    window.relationProfessionCombos = {}
    local layers = ProjectALife.RelationLayers
    local faction = window.currentFaction
    local relations = faction and faction.relations or {}
    window.relationProfessionBase = tostring(relations.player)
    local query, row = Creator.relationQuery(window), 0
    for _, profession in ipairs(Creator.professionList()) do
        local id, label = profession[1], profession[2]
        if Creator.relationMatches(query, label, id) then
            local inherited, layer, shift, bloc = layers.inheritedTowardPlayer(faction or {}, id)
            local explicit = relations[layers.professionKey(id)]
            local badge = ""
            if explicit ~= nil then badge = ProjectALife.Text.ui("SET HERE") end
            local labelText = Creator.safeText(label)
            local card, combo = Creator.relationCard(area, row, labelText, badge,
                Creator.relationOptions(Creator.relationDefaultLabel(inherited,
                    Creator.relationWhy(layer, bloc, shift))), explicit or "inherit")
            window.relationProfessionControls[#window.relationProfessionControls + 1] = card
            window.relationProfessionCombos[id] = combo
            row = row + 1
        end
    end
    if area.setScrollHeight then area:setScrollHeight(math.max(area.height, row * Creator.px(76))) end
end

function Creator.harvestRelationRows(window, relations)
    if type(relations) ~= "table" then return end
    local layers = ProjectALife.RelationLayers
    for id, combo in pairs(window.relationCombos or {}) do
        local value = Creator.selectedData(combo)
        if combo.alifeOverride == nil or value ~= combo.alifeOverride then
            if combo.alifeOverride ~= nil then
                relations[layers.folderKey(id)] = nil
                combo.alifeOverride = nil
                if combo.alifeBadge then combo.alifeBadge:setName(ProjectALife.Text.ui("SET HERE")) end
            end
            if value == nil or value == "inherit" then relations[id] = nil else relations[id] = value end
        end
    end
    for id, combo in pairs(window.relationProfessionCombos or {}) do
        local value = Creator.selectedData(combo)
        local key = layers.professionKey(id)
        if value == nil or value == "inherit" then relations[key] = nil else relations[key] = value end
    end
end

function Creator.filterRelations(window)
    local relations = window.currentFaction and window.currentFaction.relations
    if relations then Creator.harvestRelationRows(window, relations) end
    Creator.rebuildRelationView(window)
end

function Creator.viewerProfession(mirror)
    if type(mirror) == "table" and type(mirror.profession) == "string" then
        if mirror.profession == "" then return nil end
        return mirror.profession
    end
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil
    if player == nil then return nil end
    return ProjectALife.RelationLayers.professionOf(player)
end

function Creator.mirroredPlayerRelation(window)
    local faction = window and window.currentFaction or nil
    local mirror = ProjectALife.StatusStore and ProjectALife.StatusStore.reputation
    local fallback = faction and faction.relations and faction.relations.player
        or (faction and faction.spawn and faction.spawn.peaceable == true and "friendly")
        or "hostile"
    for _, entry in ipairs(type(mirror) == "table" and mirror.relations or {}) do
        if faction and tostring(entry.factionId or "") == tostring(faction.id) then
            return tostring(entry.status or fallback), ProjectALife.Text.ui("LIVE")
        end
    end
    local value = Creator.selectedData(window and window.factionPlayerRelation) or fallback
    local professionId = Creator.viewerProfession(mirror)
    if faction ~= nil and professionId ~= nil then
        local word, layer = ProjectALife.RelationLayers.towardPlayer(faction, professionId)
        if layer == "profession" or layer == "profession_default" then
            return tostring(word), ProjectALife.Text.ui("YOUR PROFESSION ({name})", { name = string.upper(professionId) })
        end
    end
    if mirror then return tostring(value), ProjectALife.Text.ui("DEFAULT") end
    return tostring(value), ProjectALife.Text.ui("OFFLINE DEFAULT")
end

function Creator.refreshEffectiveRelation(window)
    if not window or not window.effectiveRelationStatus then return end
    local now = type(getTimestampMs) == "function" and getTimestampMs() or 0
    if window.relationStatusAt ~= nil and now >= window.relationStatusAt and now - window.relationStatusAt < 250 then
        return
    end
    window.relationStatusAt = now
    if window.relationFoldersStale then Creator.rebuildRelationFolders(window) end
    local relations = window.currentFaction and window.currentFaction.relations
    if relations and window.relationProfessionBase ~= tostring(relations.player) then
        Creator.harvestRelationRows(window, relations)
        Creator.rebuildRelationProfessions(window)
    end
    local value, source = Creator.mirroredPlayerRelation(window)
    window.effectiveRelationStatus:setName(ProjectALife.Text.ui("PLAYER  {value}  /  {source}",
        { value = string.upper(value), source = source }))
end

return Creator
