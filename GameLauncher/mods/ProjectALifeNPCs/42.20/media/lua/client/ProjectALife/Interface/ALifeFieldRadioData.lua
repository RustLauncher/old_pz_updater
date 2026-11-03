require "ProjectALife/Core/ALifeText"
require "ProjectALife/Interface/ALifeSafehouseClient"
require "ProjectALife/World/ALifeMetaClient"

ProjectALife = ProjectALife or {}

local Data = {
    radio = {},
    notes = {},
    contacts = {},
    radioMax = 40,
    notesMax = 24,
    contactsMax = 40,
    lineMax = 240,
    revision = 0,
    hooked = false,
    metaLabels = {
        gunfire = "Distant gunfire",
        heli = "A helicopter passed over",
        military = "Military aircraft overhead",
        crash = "A car crash in the distance",
        ambience = "A siren, a scream or a radio in the distance",
        siren = "A siren over the county",
    },
}
ProjectALife.FieldRadioData = Data

function Data.pad2(value)
    local number = math.floor(tonumber(value) or 0)
    if number < 10 then return "0" .. tostring(number) end
    return tostring(number)
end

function Data.clock()
    local clock = { day = 1, hour = 0, minute = 0 }
    local time = type(getGameTime) == "function" and getGameTime() or nil
    if time == nil then return clock end
    if type(time.getNightsSurvived) == "function" then clock.day = math.floor(tonumber(time:getNightsSurvived()) or 0) + 1 end
    if type(time.getHour) == "function" then clock.hour = math.floor(tonumber(time:getHour()) or 0) end
    if type(time.getMinutes) == "function" then clock.minute = math.floor(tonumber(time:getMinutes()) or 0) end
    return clock
end

function Data.when(entry)
    if type(entry) ~= "table" or entry.day == nil then return "" end
    return ProjectALife.Text.ui("Day {n}, {time}", {
        n = entry.day,
        time = Data.pad2(entry.hour) .. ":" .. Data.pad2(entry.minute),
    })
end

function Data.sameMinute(left, right)
    return left.day == right.day and left.hour == right.hour and left.minute == right.minute
end

function Data.clean(text, multiline)
    if type(text) ~= "string" then return "" end
    text = string.gsub(text, "<[^>]*>", "")
    text = string.gsub(text, "%[img=[^%]]*%]", "")
    if multiline then
        text = string.gsub(text, "\r\n", "\n")
        text = string.gsub(text, "\r", "\n")
        text = string.gsub(text, "[ \t\f\v]+", " ")
        text = string.gsub(text, " *\n *", "\n")
    else
        text = string.gsub(text, "%s+", " ")
    end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if not multiline and #text > Data.lineMax then text = string.sub(text, 1, Data.lineMax - 3) .. "..." end
    return text
end

function Data.push(list, entry, limit)
    table.insert(list, 1, entry)
    while #list > limit do table.remove(list) end
    Data.revision = Data.revision + 1
    return entry
end

function Data.stamp(entry)
    local clock = Data.clock()
    entry.day, entry.hour, entry.minute = clock.day, clock.hour, clock.minute
    return entry
end

function Data.addRadio(text, station, kind)
    text = Data.clean(text, true)
    if text == "" then return false end
    local entry = Data.stamp({ text = text, station = station, kind = kind or "radio" })
    local top = Data.radio[1]
    if top ~= nil and top.text == text and Data.sameMinute(top, entry) then return false end
    Data.push(Data.radio, entry, Data.radioMax)
    return true
end

function Data.addNote(text, mark)
    text = Data.clean(text)
    if text == "" then return false end
    local entry = Data.stamp({ text = text, mark = type(mark) == "string" and mark or nil, read = false })
    local top = Data.notes[1]
    if top ~= nil and top.text == text and top.day == entry.day then return false end
    Data.push(Data.notes, entry, Data.notesMax)
    return true
end

function Data.unreadNotes()
    local count = 0
    for _, note in ipairs(Data.notes) do
        if note.read ~= true then count = count + 1 end
    end
    return count
end

function Data.markRead(note)
    if type(note) ~= "table" or note.read == true then return false end
    note.read = true
    Data.revision = Data.revision + 1
    return true
end

function Data.markAllRead()
    local changed = false
    for _, note in ipairs(Data.notes) do
        if note.read ~= true then
            note.read = true
            changed = true
        end
    end
    if changed then Data.revision = Data.revision + 1 end
    return changed
end

function Data.addContact(arguments, marked)
    if type(arguments) ~= "table" then return false end
    local x, y = tonumber(arguments.x), tonumber(arguments.y)
    if x == nil or y == nil then return false end
    x, y = math.floor(x), math.floor(y)
    local npc = type(arguments.npc) == "string" and arguments.npc or ""
    local uid = arguments.uid ~= nil and tostring(arguments.uid) or nil
    local clock = Data.clock()
    for index, contact in ipairs(Data.contacts) do
        local same = contact.x == x and contact.y == y
        if same and uid ~= nil and contact.uid ~= nil then same = contact.uid == uid end
        if same and uid == nil and npc ~= "" and contact.npc ~= "" then same = contact.npc == npc end
        if same then
            table.remove(Data.contacts, index)
            contact.day, contact.hour, contact.minute = clock.day, clock.hour, clock.minute
            if marked == true then contact.marked = true end
            if npc ~= "" then contact.npc = npc end
            table.insert(Data.contacts, 1, contact)
            Data.revision = Data.revision + 1
            return true
        end
    end
    local entry = {
        npc = npc,
        uid = uid,
        faction = type(arguments.faction) == "string" and arguments.faction or "",
        place = type(arguments.name) == "string" and arguments.name or "Camp",
        x = x,
        y = y,
        marked = marked == true,
    }
    Data.stamp(entry)
    Data.push(Data.contacts, entry, Data.contactsMax)
    return true
end

function Data.mapSymbols()
    local instance = ISWorldMap_instance
    if instance == nil or instance.mapAPI == nil then return nil end
    if type(instance.mapAPI.getSymbolsAPI) ~= "function" then return nil end
    return instance.mapAPI:getSymbolsAPI()
end

function Data.symbolMatches(symbol, contact)
    if symbol == nil or type(symbol.getWorldX) ~= "function" or type(symbol.getWorldY) ~= "function" then return false end
    if math.abs(symbol:getWorldX() - contact.x) > 1.5 or math.abs(symbol:getWorldY() - contact.y) > 1.5 then return false end
    local text = nil
    if type(symbol.getUntranslatedText) == "function" then text = symbol:getUntranslatedText() end
    if text == nil and type(symbol.getTranslatedText) == "function" then text = symbol:getTranslatedText() end
    return text == contact.place
end

function Data.removeMarker(contact)
    if type(contact) ~= "table" then return false, "no_contact" end
    local api = Data.mapSymbols()
    if api == nil then return false, "map_closed" end
    if type(api.getSymbolCount) ~= "function" or type(api.getSymbolByIndex) ~= "function"
            or type(api.removeSymbolByIndex) ~= "function" then
        return false, "unsupported"
    end
    local removed = 0
    for index = api:getSymbolCount() - 1, 0, -1 do
        if Data.symbolMatches(api:getSymbolByIndex(index), contact) then
            api:removeSymbolByIndex(index)
            removed = removed + 1
        end
    end
    if removed == 0 then return false, "not_found" end
    contact.marked = false
    Data.revision = Data.revision + 1
    return true, nil
end

function Data.showOnMap(contact, playerNum)
    if type(contact) ~= "table" then return false end
    if ISWorldMap == nil or type(ISWorldMap.ShowWorldMap) ~= "function" then return false end
    return pcall(ISWorldMap.ShowWorldMap, playerNum or 0, contact.x, contact.y, 12.0)
end

function Data.onParty(arguments)
    if type(arguments) ~= "table" or arguments.active ~= true then
        if Data.party ~= nil then Data.revision = Data.revision + 1 end
        Data.party = nil
        return true
    end
    local party = { leader = Data.clean(tostring(arguments.leader or "")), group = Data.clean(tostring(arguments.group or "")),
        members = math.floor(tonumber(arguments.members) or 0) }
    if type(arguments.task) == "table" then
        party.task = Data.clean(tostring(arguments.task.text or ""))
        party.progress = Data.clean(tostring(arguments.task.progress or ""))
    end
    Data.party = party
    Data.revision = Data.revision + 1
    return true
end

function Data.onServerCommand(module, command, arguments)
    if module == "ProjectALife" and command == "partyState" then Data.onParty(arguments) end
end

function Data.reset()
    Data.party = nil
    Data.radio, Data.notes, Data.contacts = {}, {}, {}
    Data.revision = Data.revision + 1
end

function Data.onDeviceText(guid, codes, x, y, z, line)
    if type(line) ~= "string" then return end
    local station = nil
    if type(guid) == "string" and string.sub(guid, 1, 8) == "PAL-KNOX" then station = "Knox County Radio" end
    if station == nil and string.sub(line, 1, 18) == "Knox County Radio:" then station = "Knox County Radio" end
    Data.addRadio(line, station, "radio")
end

function Data.wrap(owner, field, after)
    if type(owner) ~= "table" or type(owner[field]) ~= "function" then return false end
    local flag = "fieldRadioWrapped_" .. field
    if owner[flag] == true then return true end
    local original = owner[field]
    owner[field] = function(first, second)
        local result = original(first, second)
        pcall(after, result, first, second)
        return result
    end
    owner[flag] = true
    return true
end

function Data.afterNotice(result, arguments, player)
    if result ~= true or type(arguments) ~= "table" then return end
    Data.addNote(arguments.text, arguments.mark)
end

function Data.afterMark(result, arguments, player)
    if type(arguments) ~= "table" then return end
    Data.addContact(arguments, result == true)
end

function Data.afterMeta(result, payload)
    if result ~= true or type(payload) ~= "table" then return end
    local label = Data.metaLabels[tostring(payload.kind)]
    if label == nil then return end
    Data.addRadio(ProjectALife.Text.ui(label), nil, "meta")
end

function Data.hook()
    if Data.hooked then return true end
    Data.wrap(ProjectALife.SafehouseClient, "notice", Data.afterNotice)
    Data.wrap(ProjectALife.SafehouseClient, "mark", Data.afterMark)
    Data.wrap(ProjectALife.MetaClient, "onEvent", Data.afterMeta)
    Data.hooked = true
    return true
end

Data.hook()

if type(Events) == "table" then
    if Events.OnGameStart ~= nil and type(Events.OnGameStart.Add) == "function" then
        Events.OnGameStart.Add(Data.hook)
    end
    if Events.OnServerCommand ~= nil and type(Events.OnServerCommand.Add) == "function" then
        Events.OnServerCommand.Add(Data.onServerCommand)
    end
    if Events.OnDeviceText ~= nil and type(Events.OnDeviceText.Add) == "function" then
        Events.OnDeviceText.Add(Data.onDeviceText)
    end
    if Events.OnMainMenuEnter ~= nil and type(Events.OnMainMenuEnter.Add) == "function" then
        Events.OnMainMenuEnter.Add(Data.reset)
    end
end

return Data
