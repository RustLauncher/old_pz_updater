ProjectALife = ProjectALife or {}
require "ProjectALife/Records/ALifeRecordMigration"

local Folders = {
    fileName = "alife_creator_folders.ini",
    unfiledId = "__unfiled",
    folders = {},
    order = {},
    serial = 0,
}
ProjectALife.CreatorFolders = Folders

local function cleanName(value)
    local name = tostring(value or "")
        :gsub("[\r\n]", " ")
        :gsub("[%[%]=]", "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
    if name == "" then return "New Folder" end
    return name:sub(1, 48)
end

local function cleanId(value)
    return tostring(value or ""):gsub("[^%w_%-]", "_")
end

local function newId()
    Folders.serial = Folders.serial + 1
    local stamp = type(getTimestampMs) == "function" and getTimestampMs()
        or (os.time and os.time() or 0)
    return "folder_" .. tostring(stamp) .. "_" .. tostring(Folders.serial)
end

local function blank(id, name)
    return {
        id = cleanId(id),
        name = cleanName(name),
        collapsed = false,
        factions = {},
    }
end

Folders.cleanName = cleanName
Folders.blank = blank

function Folders.get(id)
    for _, folder in ipairs(Folders.folders) do
        if folder.id == id then return folder end
    end
    return nil
end

function Folders.parse(source)
    local folders, current, order, settings = {}, nil, {}, false
    Folders.known, Folders.seeded = nil, nil
    for line in string.gmatch(tostring(source or "") .. "\n", "([^\n]*)\n") do
        local id = string.match(line, "^%[([%w_%-]+)%]%s*$")
        if id ~= nil then
            settings = id == "__settings"
            if settings then
                current = nil
            else
                current = blank(id, "New Folder")
                folders[#folders + 1] = current
            end
        elseif settings then
            local key, value = string.match(line, "^([%w_%-]+)%s*=%s*(.-)%s*$")
            if key == "order" then
                for factionId in string.gmatch(tostring(value or ""), "([^|]+)") do
                    factionId = cleanId(factionId)
                    if factionId ~= "" then order[#order + 1] = factionId end
                end
            elseif key == "seeded" then
                Folders.seeded = tostring(value or "")
            elseif key == "known" then
                Folders.known = {}
                for factionId in string.gmatch(tostring(value or ""), "([^|]+)") do
                    factionId = cleanId(factionId)
                    if factionId ~= "" then Folders.known[factionId] = true end
                end
            end
        elseif current ~= nil then
            local key, value = string.match(line, "^([%w_%-]+)%s*=%s*(.-)%s*$")
            if key == "name" then
                current.name = cleanName(value)
            elseif key == "collapsed" then
                current.collapsed = value == "true"
            elseif key == "factions" then
                for factionId in string.gmatch(tostring(value or ""), "([^|]+)") do
                    factionId = cleanId(factionId)
                    if factionId ~= "" then current.factions[factionId] = true end
                end
            end
        end
    end
    Folders.order = order
    return folders
end

function Folders.serializeAll()
    local records = {
        "[__settings]\norder = " .. table.concat(Folders.order or {}, "|")
            .. "\nseeded = " .. tostring(Folders.seeded or "")
            .. "\nknown = " .. table.concat(Folders.knownList(), "|"),
    }
    for _, folder in ipairs(Folders.folders) do
        local factionIds = {}
        for factionId, included in pairs(folder.factions or {}) do
            if included == true then factionIds[#factionIds + 1] = cleanId(factionId) end
        end
        table.sort(factionIds)
        records[#records + 1] = table.concat({
            "[" .. cleanId(folder.id) .. "]",
            "name = " .. cleanName(folder.name),
            "collapsed = " .. tostring(folder.collapsed == true),
            "factions = " .. table.concat(factionIds, "|"),
        }, "\n")
    end
    return table.concat(records, "\n\n")
end

function Folders.ensureOrder(records)
    local previous = Folders.serializeAll()
    local seen, changed = {}, false
    local compact = {}
    for _, id in ipairs(Folders.order or {}) do
        id = cleanId(id)
        if id ~= "" and not seen[id] then
            seen[id] = true
            compact[#compact + 1] = id
        else
            changed = true
        end
    end
    for _, record in ipairs(records or {}) do
        local id = cleanId(type(record) == "table" and record.id or record)
        if id ~= "" and not seen[id] then
            seen[id] = true
            compact[#compact + 1] = id
            changed = true
        end
    end
    Folders.order = compact
    if changed then Folders.persist(previous) end
    return Folders.order
end

function Folders.rank(factionId)
    factionId = cleanId(factionId)
    local order = Folders.order or {}
    local index = Folders.rankIndex
    if index == nil or Folders.rankIndexOf ~= order or Folders.rankIndexSize ~= #order then
        index = {}
        for position, id in ipairs(order) do
            if index[id] == nil then index[id] = position end
        end
        Folders.rankIndex, Folders.rankIndexOf, Folders.rankIndexSize = index, order, #order
    end
    return index[factionId] or math.huge
end

Folders.defaults = {
    { id = "alife_law", name = "ALife Law Enforcement", blocs = { law = true }, ids = { alife_police = true } },
    { id = "alife_government", name = "ALife Government", blocs = { military = true, elite = true, rescue = true },
        ids = { alife_guard = true, alife_cordon = true, alife_fire = true } },
    { id = "alife_families", name = "ALife Families", blocs = { family = true, prison = true },
        ids = { alife_riverside = true } },
    { id = "alife_businesses", name = "ALife Businesses", blocs = { worker = true, crime = true },
        ids = { alife_kettle = true } },
    { id = "alife_lone", name = "ALife Lone Survivors", blocs = { civilian = true }, ids = {} },
    { id = "alife_outlaws", name = "ALife Outlaws", blocs = { club = true, gang = true, raider = true },
        ids = {} },
    { id = "alife_commonwealth", name = "ALife Commonwealth", blocs = { federation = true }, ids = {} },
}
Folders.seedVersion = "2"

function Folders.knownList()
    local list = {}
    for id, seen in pairs(Folders.known or {}) do
        if seen == true then list[#list + 1] = id end
    end
    table.sort(list)
    return list
end

function Folders.seedDefaults(records)
    local previous = Folders.serializeAll()
    local first = Folders.seeded ~= Folders.seedVersion
    local known = type(Folders.known) == "table" and Folders.known or {}
    Folders.known = known
    if first then
        for _, spec in ipairs(Folders.defaults) do
            if Folders.get(spec.id) == nil then
                Folders.folders[#Folders.folders + 1] = blank(spec.id, spec.name)
            end
        end
    end
    local changed = first
    for _, record in ipairs(records or {}) do
        local id = cleanId(type(record) == "table" and record.id or record)
        local refile = first and string.sub(id, 1, 6) == "alife_"
        if id ~= "" and (known[id] ~= true or refile) and not Folders.visitorOnly(record) then
            known[id] = true
            changed = true
            if Folders.folderForFaction(id) == nil then
                local bloc = type(record) == "table" and type(record.relations) == "table"
                    and record.relations.bloc or nil
                for _, spec in ipairs(Folders.defaults) do
                    if spec.ids[id] == true or (bloc ~= nil and spec.blocs[bloc] == true) then
                        local folder = Folders.get(spec.id)
                        if folder ~= nil then folder.factions[id] = true end
                        break
                    end
                end
            end
        end
    end
    if not changed then return false end
    Folders.seeded = Folders.seedVersion
    return Folders.persist(previous)
end

Folders.visitorsId = "alife_visitors"
Folders.visitorsName = "Visitors"
Folders.visitorsSentinel = "__visitors_folder"

function Folders.visitorOnly(record)
    return type(record) == "table" and type(record.spawn) == "table" and record.spawn.visitorOnly == true
end

function Folders.seedVisitors(records)
    local previous = Folders.serializeAll()
    local known = type(Folders.known) == "table" and Folders.known or {}
    Folders.known = known
    local pending = {}
    for _, record in ipairs(records or {}) do
        local id = cleanId(type(record) == "table" and record.id or record)
        if id ~= "" and known[id] ~= true and Folders.visitorOnly(record) then pending[#pending + 1] = id end
    end
    if #pending == 0 then return false end
    local folder = Folders.get(Folders.visitorsId)
    if folder == nil and known[Folders.visitorsSentinel] ~= true then
        folder = blank(Folders.visitorsId, Folders.visitorsName)
        local isDefault, last = {}, nil
        for _, spec in ipairs(Folders.defaults) do isDefault[spec.id] = true end
        for index, existing in ipairs(Folders.folders) do
            if isDefault[existing.id] then last = index end
        end
        table.insert(Folders.folders, last ~= nil and last + 1 or #Folders.folders + 1, folder)
    end
    known[Folders.visitorsSentinel] = true
    for _, id in ipairs(pending) do
        known[id] = true
        if folder ~= nil and Folders.folderForFaction(id) == nil then folder.factions[id] = true end
    end
    return Folders.persist(previous)
end

function Folders.dragQuestion(record, fromId, toId)
    local visitor = Folders.visitorOnly(record)
    if toId == Folders.visitorsId and fromId ~= Folders.visitorsId and not visitor then return "in" end
    if fromId == Folders.visitorsId and toId ~= Folders.visitorsId and visitor then return "out" end
    return nil
end

function Folders.move(factionId, targetId, after)
    factionId, targetId = cleanId(factionId), cleanId(targetId)
    if factionId == "" or targetId == "" or factionId == targetId then return false end
    local order = Folders.order or {}
    local found = false
    for _, id in ipairs(order) do if id == targetId then found = true break end end
    if not found then return false end
    local previous = Folders.serializeAll()
    local moved = false
    for index = #order, 1, -1 do
        if order[index] == factionId then table.remove(order, index); moved = true end
    end
    local targetIndex
    for index, id in ipairs(order) do
        if id == targetId then targetIndex = index break end
    end
    if not targetIndex then return false end
    table.insert(order, targetIndex + (after and 1 or 0), factionId)
    Folders.order = order
    Folders.rankIndex = nil
    return Folders.persist(previous)
end

function Folders.moveFolder(folderId, targetId, after)
    folderId, targetId = cleanId(folderId), cleanId(targetId)
    if folderId == "" or targetId == "" or folderId == targetId
            or folderId == Folders.unfiledId or targetId == Folders.unfiledId then
        return false
    end
    local sourceIndex, targetIndex
    for index, folder in ipairs(Folders.folders or {}) do
        if folder.id == folderId then sourceIndex = index end
        if folder.id == targetId then targetIndex = index end
    end
    if not sourceIndex or not targetIndex then return false end
    local previous = Folders.serializeAll()
    local folder = table.remove(Folders.folders, sourceIndex)
    if sourceIndex < targetIndex then targetIndex = targetIndex - 1 end
    table.insert(Folders.folders, targetIndex + (after and 1 or 0), folder)
    return Folders.persist(previous)
end

function Folders.stepFolder(folderId, direction)
    folderId = cleanId(folderId)
    direction = tonumber(direction) or 0
    local sourceIndex
    for index, folder in ipairs(Folders.folders or {}) do
        if folder.id == folderId then sourceIndex = index break end
    end
    local targetIndex = sourceIndex and sourceIndex + (direction < 0 and -1 or 1) or nil
    if not sourceIndex or not targetIndex or targetIndex < 1
            or targetIndex > #(Folders.folders or {}) then return false end
    local previous = Folders.serializeAll()
    local folder = table.remove(Folders.folders, sourceIndex)
    table.insert(Folders.folders, targetIndex, folder)
    return Folders.persist(previous)
end

function Folders.removeFromOrder(factionId)
    local previous = Folders.serializeAll()
    factionId = cleanId(factionId)
    for index = #(Folders.order or {}), 1, -1 do
        if Folders.order[index] == factionId then table.remove(Folders.order, index) end
    end
    Folders.rankIndex = nil
    return Folders.persist(previous)
end

function Folders.validSaved(text)
    if type(text) ~= "string" then return nil end
    local current, seen = nil, {}
    for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
        if string.find(line, "%S") then
            local id = string.match(line, "^%[([%w_%-]+)%]%s*$")
            if id then
                if seen[id] then return nil end
                current = { id = id }
                seen[id] = current
            else
                local key = string.match(line, "^([%w_%-]+)%s*=")
                if not current or not key or current[key] ~= nil then return nil end
                if current.id == "__settings" then
                    if key ~= "order" and key ~= "seeded" and key ~= "known" then return nil end
                elseif key ~= "name" and key ~= "collapsed" and key ~= "factions" then return nil end
                current[key] = true
            end
        end
    end
    for id, fields in pairs(seen) do
        if id == "__settings" and not fields.order then return nil end
        if id ~= "__settings" and not (fields.name and fields.collapsed and fields.factions) then return nil end
    end
    return text
end

function Folders.load()
    if type(getFileReader) ~= "function" then return Folders.folders end
    local ok, loaded = pcall(function()
        local text = ProjectALife.RecordMigration.readSaved(Folders.fileName, Folders.validSaved)
        if text == nil then return false end
        Folders.folders = Folders.parse(text)
        Folders.rankIndex = nil
        return true
    end)
    Folders.loadFailed = not (ok and loaded)
    if Folders.loadFailed then print("[A-Life] Folder file unreadable; saving blocked to preserve it") end
    return Folders.folders
end

function Folders.persist(previous)
    local ok, written = pcall(function()
        if Folders.loadFailed then return false end
        return ProjectALife.RecordMigration.persistSaved(Folders.fileName,
            Folders.serializeAll(), Folders.validSaved)
    end)
    if ok and written == true then Folders.lastError = nil; return true end
    if previous ~= nil then Folders.folders = Folders.parse(previous) end
    Folders.rankIndex = nil
    Folders.lastError = "Could not save folders."
    return false
end

function Folders.create(name)
    local previous = Folders.serializeAll()
    local folder = blank(newId(), name)
    Folders.folders[#Folders.folders + 1] = folder
    if not Folders.persist(previous) then return nil end
    return folder
end

function Folders.rename(id, name)
    local folder = Folders.get(id)
    if not folder then return false end
    local previous = Folders.serializeAll()
    folder.name = cleanName(name)
    return Folders.persist(previous)
end

function Folders.delete(id)
    id = cleanId(id)
    for index, folder in ipairs(Folders.folders) do
        if folder.id == id then
            table.remove(Folders.folders, index)
            if Folders.persist() then return true end
            table.insert(Folders.folders, index, folder)
            return false
        end
    end
    return false
end

function Folders.toggle(id)
    local folder = Folders.get(id)
    if not folder then return nil end
    local previous = Folders.serializeAll()
    folder.collapsed = not folder.collapsed
    if not Folders.persist(previous) then return nil end
    return folder.collapsed
end

function Folders.folderForFaction(factionId)
    for _, folder in ipairs(Folders.folders) do
        if folder.factions and folder.factions[factionId] == true then return folder end
    end
    return nil
end

function Folders.assign(factionId, folderId)
    factionId = cleanId(factionId)
    if factionId == "" then return false end
    local destination = folderId ~= nil and folderId ~= Folders.unfiledId
        and Folders.get(folderId) or nil
    if folderId ~= nil and folderId ~= Folders.unfiledId and destination == nil then
        return false
    end
    local previous = Folders.serializeAll()
    for _, folder in ipairs(Folders.folders) do
        folder.factions = folder.factions or {}
        folder.factions[factionId] = nil
    end
    if destination then destination.factions[factionId] = true end
    return Folders.persist(previous)
end

function Folders.copyPlan(folderId, factionOrder, membersOf, newId, copyFaction, copyProfile)
    local source = Folders.get(folderId)
    if source == nil then return nil end
    local plan = { name = cleanName(source.name):sub(1, 41) .. " (copy)", factions = {}, profiles = {} }
    local filed, copied = {}, {}
    for _, record in ipairs(factionOrder or {}) do
        if source.factions[record.id] == true then filed[#filed + 1] = record end
    end
    table.sort(filed, function(a, b) return Folders.rank(a.id) < Folders.rank(b.id) end)
    for _, record in ipairs(filed) do
        local faction = copyFaction(record)
        faction.id = newId("custom_faction")
        faction.general.name = tostring(faction.general.name or "") .. " (copy)"
        copied[record.id] = faction.id
        plan.factions[#plan.factions + 1] = faction
        for _, member in ipairs(membersOf(record.id) or {}) do
            local profile = copyProfile(member)
            profile.id = newId("custom_npc")
            profile.general.faction = faction.id
            plan.profiles[#plan.profiles + 1] = profile
        end
    end
    for _, faction in ipairs(plan.factions) do
        faction.relations = faction.relations or {}
        for sourceId, copyId in pairs(copied) do
            if faction.relations[sourceId] ~= nil then
                faction.relations[copyId] = faction.relations[sourceId]
            end
            if faction.relations["folder:" .. sourceId] ~= nil then
                faction.relations["folder:" .. copyId] = faction.relations["folder:" .. sourceId]
            end
        end
        if type(faction.support) == "table" and type(faction.support.answerers) == "string" then
            faction.support.answerers = string.gsub(faction.support.answerers, "[^|,%s]+",
                function(id) return copied[id] end)
        end
    end
    return plan
end

return Folders
