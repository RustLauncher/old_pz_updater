require "ProjectALife/Admin/ALifeAdminConsole"
require "ProjectALife/Admin/ALifeAdminUI"

ProjectALife = ProjectALife or {}

local Browser = { folders = nil, folderFile = "alife_creator_folders.ini", collapsed = {}, textures = {} }
ProjectALife.SpawnerBrowser = Browser

function Browser.parseFolders(lines)
    local folders, current = {}, nil
    for _, line in ipairs(lines) do
        local id = string.match(line, "^%[([%w_%-]+)%]%s*$")
        if id ~= nil then
            if id == "__settings" then current = nil
            else
                current = { id = id, name = id, factions = {} }
                folders[#folders + 1] = current
            end
        elseif current ~= nil then
            local key, value = string.match(line, "^([%w_%-]+)%s*=%s*(.-)%s*$")
            if key == "name" and value ~= "" then
                current.name = value
            elseif key == "factions" then
                for factionId in string.gmatch(value, "([^|]+)") do current.factions[factionId] = true end
            end
        end
    end
    return folders
end

function Browser.loadFolders(force)
    if Browser.folders ~= nil and not force then return Browser.folders end
    Browser.folders = {}
    local prefs = ProjectALife.AdminPrefs
    local ok, lines = pcall(prefs.readLines, Browser.folderFile)
    if ok and lines ~= nil then Browser.folders = Browser.parseFolders(lines) end
    return Browser.folders
end

function Browser.folderOf(factionId)
    for _, folder in ipairs(Browser.loadFolders()) do
        if folder.factions[factionId] == true then return folder.name end
    end
    return nil
end

function Browser.groupName(row)
    local folder = Browser.folderOf(row.id)
    if folder ~= nil then return folder end
    if type(row.category) == "string" and row.category ~= "" then return row.category end
    return "Unfiled"
end

function Browser.matches(row, query)
    local words = ProjectALife.AdminActions.words(query)
    if #words == 0 then return true end
    local text = string.lower(tostring(row.name or row.label or "") .. " " .. tostring(row.id or "") .. " "
        .. tostring(row.category or "") .. " " .. tostring(row.detail or "") .. " " .. tostring(row.relation or "")
        .. " " .. tostring(row.class or ""))
    for _, word in ipairs(words) do
        if string.find(text, word, 1, true) == nil then return false end
    end
    return true
end

function Browser.factionRows(query, withAutomatic)
    local console = ProjectALife.AdminConsole
    local groups, order = {}, {}
    for _, faction in ipairs(console.factions.rows) do
        if Browser.matches(faction, query) then
            local name = Browser.groupName(faction)
            if groups[name] == nil then
                groups[name] = {}
                order[#order + 1] = name
            end
            groups[name][#groups[name] + 1] = faction
        end
    end
    table.sort(order, function(left, right)
        if left == "Unfiled" then return false end
        if right == "Unfiled" then return true end
        return string.lower(left) < string.lower(right)
    end)
    local rows = {}
    if withAutomatic then
        rows[#rows + 1] = { kind = "automatic", id = nil, label = "Automatic faction", detail = "the server picks one", tip = "Let the server pick the cast." }
    end
    local searching = string.find(tostring(query or ""), "%S") ~= nil
    for _, name in ipairs(order) do
        local list = groups[name]
        local folded = Browser.collapsed[name] == true and not searching
        rows[#rows + 1] = { kind = "folder", id = name, label = (folded and "+ " or "v ") .. name .. " (" .. tostring(#list) .. ")",
            tip = "Click to fold or unfold this group." }
        if not folded then
            for _, faction in ipairs(list) do
                rows[#rows + 1] = { kind = "faction", id = faction.id, label = faction.name,
                    detail = tostring(faction.count) .. " members", relation = faction.relation, class = faction.class,
                    custom = faction.custom == true, closed = faction.open == false, program = faction.program,
                    tip = tostring(faction.id) .. "  stance " .. tostring(faction.relation or "?") .. "  class "
                        .. tostring(faction.class or "-") .. (faction.custom and "  (custom)" or "")
                        .. (faction.open == false and "  (outside its day window today)" or "") }
            end
        end
    end
    return rows
end

function Browser.encounterRows(query)
    local catalog = ProjectALife.AdminConsole.catalog()
    local rows = {}
    for _, spec in ipairs(catalog ~= nil and type(catalog.encounters) == "table" and catalog.encounters or {}) do
        local row = { kind = "encounter", id = spec.id, label = tostring(spec.label or spec.id),
            detail = tostring(spec.minCount or "?") .. "-" .. tostring(spec.maxCount or "?") .. " NPCs  "
                .. tostring(spec.mode or "roam"), tip = tostring(spec.summary or spec.id), name = spec.label }
        if Browser.matches(row, query) then rows[#rows + 1] = row end
    end
    return rows
end

function Browser.presetRows(query)
    local catalog = ProjectALife.AdminConsole.catalog()
    local rows = {}
    for _, preset in ipairs(catalog ~= nil and type(catalog.outpostPresets) == "table" and catalog.outpostPresets or {}) do
        local row = { kind = "preset", id = preset.id, label = tostring(preset.label or preset.id),
            detail = tostring(preset.class or "") .. "  crew " .. tostring(preset.garrisonMin or "?") .. "-" .. tostring(preset.garrisonMax or "?"),
            tip = preset.class == "building" and "Needs a building at the target: right-click one and use it as the spawn target."
                or "Built in the open at the target.", name = preset.label }
        if Browser.matches(row, query) then rows[#rows + 1] = row end
    end
    return rows
end

function Browser.visitRows(query)
    local rows = {}
    local lastGroup = nil
    for _, entry in ipairs(ProjectALife.AdminConsole.visitEvents()) do
        local row = { kind = "visit", id = entry.id, label = entry.label, detail = entry.group,
            tip = "Forces the safehouse event " .. entry.id .. " for your test base.", group = entry.group, name = entry.label }
        if entry.group == "Visitors" and Browser.matches(row, query) then rows[#rows + 1] = row end
    end
    return rows
end

function Browser.memberRows(factionId, query)
    local console = ProjectALife.AdminConsole
    local entry = factionId ~= nil and console.members[factionId] or nil
    local rows = {}
    if entry == nil then return rows, "pick a faction" end
    if not entry.complete then return rows, "loading members..." end
    for _, member in ipairs(entry.rows) do
        local row = { kind = "member", id = member.id, label = tostring(member.name), role = member.role,
            primary = member.primary, melee = member.melee, female = member.female, weight = member.weight, name = member.name }
        row.detail = ProjectALife.SpawnPlan.rosterLine({ name = "", role = member.role, primary = member.primary, melee = member.melee })
        row.tip = tostring(member.id) .. "  weight " .. tostring(member.weight)
        if Browser.matches(row, query) then rows[#rows + 1] = row end
    end
    return rows
end

function Browser.weaponTexture(fullType)
    if type(fullType) ~= "string" or fullType == "" or fullType == "none" then return nil end
    local first = string.match(fullType, "^([^|]+)") or fullType
    local cached = Browser.textures[first]
    if cached ~= nil then return cached or nil end
    local texture = nil
    if type(getScriptManager) == "function" then
        local manager = getScriptManager()
        local item = manager ~= nil and type(manager.FindItem) == "function" and manager:FindItem(first) or nil
        if item ~= nil and type(item.getNormalTexture) == "function" then texture = item:getNormalTexture() end
    end
    Browser.textures[first] = texture or false
    return texture
end

function Browser.drawRow(list, row, y, selected)
    local UI = ProjectALife.AdminUI
    local colors = UI.colors
    local kind = row.kind
    local half = list.rowH
    if kind == "folder" then
        list:drawText(UI.fit(row.label, list.width - 16), 8, y + 4, colors.accent.r, colors.accent.g, colors.accent.b, 1, UIFont.Small)
        return
    end
    local color = colors.text
    local indent = kind == "faction" and 18 or 8
    if kind == "faction" then
        if row.relation == "hostile" then color = colors.bad
        elseif row.relation == "friendly" or row.relation == "allied" then color = colors.good
        elseif row.relation == "careful" then color = colors.warn end
        if row.closed then color = colors.muted end
    end
    if kind == "member" then
        local texture = Browser.weaponTexture(row.primary) or Browser.weaponTexture(row.melee)
        if texture ~= nil and type(list.drawTextureScaledAspect) == "function" then
            list:drawTextureScaledAspect(texture, 6, y + 2, half - 4, half - 4, 1, 1, 1, 1)
        end
        indent = half + 4
    end
    local right = row.detail ~= nil and UI.measure(row.detail) + 14 or 0
    if kind == "member" then right = math.min(list.width * 0.55, right) end
    local nameWidth = list.width - indent - right - 12
    list:drawText(UI.fit(row.label, nameWidth), indent, y + 4, color.r, color.g, color.b, 1, UIFont.Small)
    if row.detail ~= nil then
        list:drawTextRight(UI.fit(row.detail, right - 8), list.width - 10, y + 4, colors.muted.r, colors.muted.g, colors.muted.b, 1, UIFont.Small)
    end
    if row.custom then list:drawText("C", indent - 12, y + 4, colors.warn.r, colors.warn.g, colors.warn.b, 1, UIFont.Small) end
end

return Browser
