require "ProjectALife/Core/ALifeText"
require "ProjectALife/Talk/ALifeTalkUi"
require "ProjectALife/Talk/ALifeTalkMenu"

ProjectALife = ProjectALife or {}

local Text = ProjectALife.Text

local Client = {
    hello = { tries = 0, acked = false, ticks = 0, nextTick = 300, maxTries = 6 },
    knocks = {},
}
ProjectALife.SafehouseClient = Client

Client.events = {
    { "letter_thanks", "Thank-you letter" },
    { "letter_warning", "Warning letter" },
    { "letter_threat", "Threat letter" },
    { "letter_demand", "Demand letter" },
    { "letter_trade", "Trade offer" },
    { "map_honest", "Honest map" },
    { "letter_apology", "Apology" },
    { "missing_person", "Missing person notice" },
    { "territory_notice", "Territory notice" },
    { "last_letter", "Last letter" },
    { "gift", "Gift" },
    { "beggar", "Visitor: beggar" },
    { "trader", "Visitor: trader" },
    { "law_stay_inside", "Visitor: law, stay inside (window)" },
    { "law_census", "Visitor: law, census" },
    { "sleep_one_night", "Visitor: asks to sleep one night" },
    { "chased", "Visitor: being chased" },
    { "wounded", "Visitor: wounded at the window" },
    { "racket", "Visitor: protection racket" },
    { "neighbour", "Visitor: neighbour" },
    { "returning_things", "Visitor: returning your things" },
    { "drunk", "Visitor: drunk (window)" },
    { "preacher", "Visitor: preacher" },
    { "law_fake", "Visitor: fake police" },
    { "medic_rounds", "Visitor: medic on rounds" },
    { "messenger", "Visitor: messenger with a job (window)" },
    { "neighbour_borrow", "Visitor: neighbour borrows a tool" },
    { "law_guns", "Visitor: police collecting weapons" },
    { "asks_help", "Visitor: asks you to come help (window)" },
    { "family_in_need", "Visitor: a family in need (party)" },
    { "returning_guest", "Visitor: a returning guest" },
    { "lodger_request", "Visitor: asks to lodge a few nights" },
    { "panic_knock", "Visitor: panicked knock, the dead behind" },
    { "weather_shelter", "Visitor: shelter from the weather" },
    { "medical_visit", "Visitor: needs medical help" },
    { "mark_paint_x", "Ladder 2: paint X by the door" },
    { "sabotage", "Ladder 3: sabotage while away" },
    { "raid_night", "Ladder 4: night raid" },
    { "raid_lure", "Ladder 4: horde lure raid" },
    { "raid_power", "Ladder 4: power cut raid" },
    { "raid_siege", "Ladder 4: siege" },
    { "gas_siphoned", "Sign: fuel siphoned from a car" },
    { "garden_raided", "Sign: garden picked" },
    { "flashlight_window", "Night: flashlight at the window" },
    { "camp_traces", "Sign: camp traces" },
    { "door_left_open", "Sign: front door left open" },
    { "chalk_mark", "Mark: chalk symbol" },
    { "tally_marks", "Mark: tally marks" },
    { "faction_flag", "Mark: faction colours" },
    { "knock_nobody", "Night: knock, nobody there" },
    { "radio_chatter", "Radio: your house mentioned" },
    { "distant_gunshot", "Night: distant gunshots" },
    { "dog_barking", "Night: a dog barking" },
    { "glass_breaks_near", "Night: glass breaks nearby" },
    { "blood_smear", "Mark: blood by the door" },
}

function Client.send(playerNum, args)
    if type(getSpecificPlayer) ~= "function" or type(sendClientCommand) ~= "function" then return false end
    local player = getSpecificPlayer(playerNum or 0)
    if player == nil then return false end
    sendClientCommand(player, "ProjectALife", "debugSafehouse", args)
    return true
end

Client.groupOrder = { "Visitors", "Letters and gifts", "Signs and marks", "Night and radio", "Warning ladder", "Raid variants" }

Client.groupOf = {
    beggar = "Visitors", trader = "Visitors", law_stay_inside = "Visitors", law_census = "Visitors",
    sleep_one_night = "Visitors", chased = "Visitors", wounded = "Visitors", racket = "Visitors",
    neighbour = "Visitors", returning_things = "Visitors", drunk = "Visitors", preacher = "Visitors",
    law_fake = "Visitors", medic_rounds = "Visitors", messenger = "Visitors", neighbour_borrow = "Visitors",
    law_guns = "Visitors", asks_help = "Visitors", family_in_need = "Visitors", returning_guest = "Visitors",
    lodger_request = "Visitors", panic_knock = "Visitors", weather_shelter = "Visitors", medical_visit = "Visitors",
    letter_thanks = "Letters and gifts", letter_warning = "Letters and gifts", letter_demand = "Letters and gifts",
    letter_trade = "Letters and gifts", map_honest = "Letters and gifts", letter_apology = "Letters and gifts",
    missing_person = "Letters and gifts", territory_notice = "Letters and gifts", last_letter = "Letters and gifts",
    gift = "Letters and gifts",
    camp_traces = "Signs and marks", door_left_open = "Signs and marks", chalk_mark = "Signs and marks",
    tally_marks = "Signs and marks", faction_flag = "Signs and marks", gas_siphoned = "Signs and marks",
    garden_raided = "Signs and marks",
    flashlight_window = "Night and radio", knock_nobody = "Night and radio", radio_chatter = "Night and radio",
    distant_gunshot = "Night and radio", dog_barking = "Night and radio", glass_breaks_near = "Night and radio",
    blood_smear = "Signs and marks",
    letter_threat = "Warning ladder", mark_paint_x = "Warning ladder", sabotage = "Warning ladder",
    raid_night = "Raid variants", raid_lure = "Raid variants", raid_power = "Raid variants",
    raid_siege = "Raid variants",
}

function Client.popupTest(playerNum, gain)
    local screen = ProjectALife.RepScreen
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(playerNum or 0) or nil
    if screen == nil or player == nil then return false end
    screen.popupLastMs = -1000000
    return screen.popup({ cause = gain and "helped" or "kill_neutral", gain = gain == true }, player)
end

function Client.spot(square)
    if square == nil or type(square.getX) ~= "function" or type(square.getY) ~= "function" then return nil end
    local ok, x, y, z = pcall(function() return square:getX(), square:getY(), type(square.getZ) == "function" and square:getZ() or 0 end)
    if not ok or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return { x = x, y = y, z = z }
end

function Client.hasBuilding(square)
    if square == nil or type(square.getBuilding) ~= "function" then return false end
    local ok, building = pcall(square.getBuilding, square)
    return ok and building ~= nil
end

function Client.hint(square)
    if square == nil then return Text.ui("Triggers need a base: stand inside a house and create a test base") end
    if Client.hasBuilding(square) then return Text.ui("Triggers need a base: this house becomes the test base") end
    return Text.ui("Triggers need a base: right-click a house, or stand inside one")
end

function Client.addGroups(parent, playerNum, at)
    local lists, extra = {}, {}
    for index = 1, #Client.events do
        local entry = Client.events[index]
        local group = Client.groupOf[entry[1]]
        if group == nil then
            extra[#extra + 1] = entry
        else
            lists[group] = lists[group] or {}
            lists[group][#lists[group] + 1] = entry
        end
    end
    local order = {}
    for index = 1, #Client.groupOrder do order[#order + 1] = Client.groupOrder[index] end
    if #extra > 0 then lists.Other = extra; order[#order + 1] = "Other" end
    local total = 0
    for index = 1, #order do
        local list = lists[order[index]]
        if list ~= nil then
            local groupOption = parent:addOption(Text.ui(order[index]) .. " (" .. #list .. ")")
            local group = parent:getNew(parent)
            parent:addSubMenu(groupOption, group)
            for position = 1, #list do
                local entry = list[position]
                group:addOption(Text.ui(entry[2]), playerNum, Client.send, { action = "trigger", event = entry[1], at = at })
                total = total + 1
            end
        end
    end
    return total
end

function Client.addMenu(menu, playerNum, square)
    if type(menu) ~= "table" or type(menu.addOption) ~= "function" or type(menu.getNew) ~= "function" then return nil end
    local at = Client.spot(square)
    local option = menu:addOption(Text.ui("Safehouse interactions (debug)"))
    local submenu = menu:getNew(menu)
    menu:addSubMenu(option, submenu)
    local hint = submenu:addOption(Client.hint(square))
    hint.notAvailable = true
    submenu:addOption(Text.ui("Create test base here"), playerNum, Client.send, { action = "mark", at = at })
    Client.addGroups(submenu, playerNum, at)
    submenu:addOption(Text.ui("Show safehouse state"), playerNum, Client.send, { action = "state" })
    submenu:addOption(Text.ui("Dump safehouse diagnostics"), playerNum, Client.send, { action = "diagnostics", at = at })
    submenu:addOption(Text.ui("Run placement self-test (all rows, no spawning)"), playerNum, Client.send, { action = "selftest", at = at })
    submenu:addOption(Text.ui("Visitors: show spawn points"), playerNum, Client.send, { action = "spawnpoints", at = at })
    submenu:addOption(Text.ui("Clear test base"), playerNum, Client.send, { action = "clear" })
    submenu:addOption(Text.ui("Wash any mark off the wall"), playerNum, Client.wash)
    local repOption = submenu:addOption(Text.ui("Reputation text..."))
    local rep = submenu:getNew(submenu)
    submenu:addSubMenu(repOption, rep)
    rep:addOption(Text.ui("Show a loss message"), playerNum, Client.popupTest, false)
    rep:addOption(Text.ui("Show a gain message"), playerNum, Client.popupTest, true)
    submenu:addOption(Text.ui("Force next director tick"), playerNum, Client.send, { action = "tick", at = at })
    return submenu
end

function Client.reasonText(reason)
    if reason == "admin_required" then return Text.ui("the server does not list you as an admin") end
    if reason == "diagnostics_disabled" then
        local prefs = ProjectALife.MenuPrefs
        if prefs ~= nil and type(prefs.refusedText) == "function" and type(getSpecificPlayer) == "function" then
            return prefs.refusedText(getSpecificPlayer(0))
        end
        return Text.ui("diagnostics are off")
    end
    if reason == "rate_limited" then return Text.ui("too fast, try again in a second") end
    if reason == "safehouse_unavailable" then return Text.ui("the safehouse director is not running") end
    if reason == "safehouse_failed" then return Text.ui("the safehouse director failed; see the server log") end
    return tostring(reason or "unknown")
end

function Client.say(text)
    if type(getSpecificPlayer) ~= "function" then return end
    local player = getSpecificPlayer(0)
    if player == nil or type(player.Say) ~= "function" then return end
    player:Say(text)
    if HaloTextHelper ~= nil and type(HaloTextHelper.addText) == "function" then HaloTextHelper.addText(player, text) end
end

function Client.show(lines)
    local text = table.concat(lines, " <LINE> ")
    print("[ALIFE-SAFEHOUSE] " .. table.concat(lines, "\n[ALIFE-SAFEHOUSE] "))
    if ISModalRichText == nil or type(ISModalRichText.new) ~= "function" or type(getCore) ~= "function" then return false end
    local width, height = 640, 560
    local x = math.max(0, (getCore():getScreenWidth() - width) / 2)
    local y = math.max(0, (getCore():getScreenHeight() - height) / 2)
    local modal = ISModalRichText:new(x, y, width, height, text, false, nil, nil, 0)
    modal:initialise()
    modal:addToUIManager()
    return true
end

function Client.receive(command, arguments)
    if type(arguments) ~= "table" then return end
    if command == "debugSafehouseResult" then
        print("[ALIFE-SAFEHOUSE] " .. tostring(arguments.action) .. " " .. tostring(arguments.event or "")
            .. " ok=" .. tostring(arguments.ok == true) .. " " .. tostring(arguments.say or arguments.reason or ""))
        if type(arguments.console) == "table" then
            for index = 1, math.min(#arguments.console, 200) do print("[ALIFE-SAFEHOUSE] " .. tostring(arguments.console[index])) end
        end
        if type(arguments.points) == "table" then Client.showPoints(arguments.points) end
    end
    if command == "safehouseHelloResult" then
        Client.hello.acked = arguments.ok == true
        return
    end
    if type(arguments.lines) == "table" and #arguments.lines > 0 then Client.show(arguments.lines) end
    if arguments.say ~= nil then
        Client.say(tostring(arguments.say))
    elseif arguments.ok ~= true and arguments.lines == nil then
        Client.say(Text.ui("A-Life safehouse refused: {reason}", { reason = Client.reasonText(arguments.reason) }))
    end
end

Client.pointsLiveMs = 30000

function Client.clearPoints()
    local shown = Client.shown
    if shown == nil then return false end
    Client.shown = nil
    for index = 1, #shown.markers do
        local marker = shown.markers[index]
        if marker ~= nil and type(marker.remove) == "function" then pcall(marker.remove, marker) end
    end
    local overlay = shown.overlay
    if overlay ~= nil and type(overlay.removeFromUIManager) == "function" then pcall(overlay.removeFromUIManager, overlay) end
    return true
end

function Client.overlayClass()
    if Client.overlayType ~= nil then return Client.overlayType end
    if ISUIElement == nil or type(ISUIElement.derive) ~= "function" then return nil end
    local class = ISUIElement:derive("ALifeSpawnPoints")
    function class:render()
        local shown = Client.shown
        if shown == nil or type(getTimestampMs) ~= "function" then return end
        if getTimestampMs() > shown.untilMs then Client.clearPoints(); return end
        if type(isoToScreenX) ~= "function" or type(isoToScreenY) ~= "function" or UIFont == nil then return end
        for index = 1, #shown.points do
            local point = shown.points[index]
            local sx, sy = isoToScreenX(0, point.x, point.y, point.z), isoToScreenY(0, point.x, point.y, point.z)
            local r, g, b = 0.4, 1.0, 0.5
            if not point.ok then r, g, b = 1.0, 0.45, 0.4 end
            self:drawTextCentre(point.label, sx, sy - 40, r, g, b, 1.0, UIFont.Small)
        end
    end
    Client.overlayType = class
    return class
end

function Client.showPoints(points)
    Client.clearPoints()
    if type(getTimestampMs) ~= "function" or type(points) ~= "table" then return false end
    local shown = { untilMs = getTimestampMs() + Client.pointsLiveMs, markers = {}, points = {} }
    local cell = type(getCell) == "function" and getCell() or nil
    local markers = type(getWorldMarkers) == "function" and getWorldMarkers() or nil
    for index = 1, math.min(#points, 24) do
        local point = points[index]
        if type(point) == "table" and tonumber(point.x) ~= nil and tonumber(point.y) ~= nil then
            local z = math.floor(tonumber(point.z) or 0)
            shown.points[#shown.points + 1] = { x = point.x + 0.5, y = point.y + 0.5, z = z, ok = point.ok == true,
                label = tostring(point.label or "") }
            local square = cell ~= nil and type(cell.getGridSquare) == "function" and cell:getGridSquare(math.floor(point.x), math.floor(point.y), z) or nil
            if square ~= nil and markers ~= nil and type(markers.addGridSquareMarker) == "function" then
                local r, g, b = 0.2, 0.9, 0.3
                if point.ok ~= true then r, g, b = 0.95, 0.25, 0.2 end
                local made = nil
                pcall(function() made = markers:addGridSquareMarker(square, r, g, b, true, 0.6) end)
                if made ~= nil then
                    if type(made.setScaleCircleTexture) == "function" then pcall(made.setScaleCircleTexture, made, true) end
                    shown.markers[#shown.markers + 1] = made
                end
            end
        end
    end
    local class = Client.overlayClass()
    if class ~= nil then
        local overlay = ISUIElement:new(0, 0, 1, 1)
        setmetatable(overlay, class)
        class.__index = class
        ProjectALife.TalkUi.passThrough(overlay)
        overlay:initialise()
        overlay:addToUIManager()
        shown.overlay = overlay
    end
    Client.shown = shown
    return #shown.points > 0
end

function Client.knock(arguments, recipient)
    if type(arguments) ~= "table" or type(getSpecificPlayer) ~= "function"
            or type(arguments.pendingId) ~= "string" or #arguments.pendingId > 200
            or type(arguments.house) ~= "string" or type(arguments.uid) ~= "string"
            or type(arguments.username) ~= "string" or arguments.username == ""
            or type(arguments.row) ~= "string" then return false end
    for _, field in ipairs({ "x", "y", "z", "generation", "untilHours" }) do
        local value = arguments[field]
        if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return false end
    end
    local time = type(getGameTime) == "function" and getGameTime() or nil
    if time == nil or type(time.getWorldAgeHours) ~= "function" or time:getWorldAgeHours() > arguments.untilHours then return false end
    local door
    if type(arguments.door) == "table" then
        door = {}
        for _, field in ipairs({ "sx", "sy", "ix", "iy", "z", "x1", "y1", "x2", "y2" }) do
            local value = arguments.door[field]
            if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then door = nil; break end
            door[field] = value
        end
        if door ~= nil and arguments.door.kind == "window" then door.kind = "window" end
    end
    for index = 0, 3 do
        local player = getSpecificPlayer(index)
        if player ~= nil and (recipient == nil or recipient == player)
                and type(player.getUsername) == "function" and player:getUsername() == arguments.username
                and type(player.isDead) == "function" and player:isDead() == false
                and type(player.isAsleep) == "function" and player:isAsleep() == false
                and type(player.getX) == "function" and type(player.getY) == "function"
                and (player:getX() - arguments.x)^2 + (player:getY() - arguments.y)^2 <= 3600 then
            local previous = Client.knocks[index]
            if previous == nil or previous.pendingId ~= arguments.pendingId or previous.username ~= arguments.username then
                local text = Text.ui("Someone is at your safehouse door.")
                if door ~= nil and door.kind == "window" then text = Text.ui("Someone is at your window.") end
                Client.knocks[index] = { pendingId = arguments.pendingId, house = arguments.house,
                    uid = arguments.uid, generation = arguments.generation, row = arguments.row,
                    x = arguments.x, y = arguments.y, z = arguments.z, untilHours = arguments.untilHours,
                    username = arguments.username, text = text, door = door }
                if arguments.cued ~= true and HaloTextHelper ~= nil and type(HaloTextHelper.addText) == "function" then
                    HaloTextHelper.addText(player, text)
                end
            end
        end
    end
    return true
end

function Client.statusText(playerNum)
    local saved = Client.knocks[playerNum or 0]
    if saved == nil or type(getSpecificPlayer) ~= "function" then return nil end
    local player = getSpecificPlayer(playerNum or 0)
    if player == nil or type(player.getUsername) ~= "function" or player:getUsername() ~= saved.username then return nil end
    local time = type(getGameTime) == "function" and getGameTime() or nil
    if time == nil or type(time.getWorldAgeHours) ~= "function" or time:getWorldAgeHours() > saved.untilHours then return nil end
    return Text.ui("Last safehouse knock: someone arrived.")
end

function Client.doorVisit(playerNum)
    if Client.statusText(playerNum) == nil then return nil end
    local saved = Client.knocks[playerNum or 0]
    local door, player = saved.door, getSpecificPlayer(playerNum or 0)
    if type(door) ~= "table" or type(player.isDead) ~= "function" or player:isDead()
            or type(player.isAsleep) ~= "function" or player:isAsleep()
            or type(player.getX) ~= "function" or type(player.getY) ~= "function" or type(player.getZ) ~= "function" then return nil end
    local x, y, z = player:getX(), player:getY(), player:getZ()
    if x < door.x1 or x >= door.x2 or y < door.y1 or y >= door.y2
            or math.abs(z - door.z) > 1 or (x - door.ix)^2 + (y - door.iy)^2 > 64 then return nil end
    local record = ProjectALife.TalkMenu.recordFor(saved.uid)
    local visit = record and type(record.memory) == "table" and record.memory.visit or nil
    if record == nil or record.lifecycle ~= "active" or record.generation ~= saved.generation
            or type(visit) ~= "table" or visit.pendingId ~= saved.pendingId or visit.house ~= saved.house
            or visit.generation ~= saved.generation then return nil end
    return saved, player
end

function Client.openDoor(playerNum, saved, choice)
    if Client.doorVisit(playerNum) ~= saved then return false end
    return ProjectALife.TalkMenu.open(playerNum, saved.uid, nil, Text.ui("Visitor"), "", nil, nil, choice)
end

function Client.syncDoor(playerNum)
    if type(playerNum) ~= "number" or playerNum < 0 or playerNum > 3 or playerNum % 1 ~= 0
            or type(getSpecificPlayer) ~= "function" then return false end
    local player = getSpecificPlayer(playerNum)
    if player == nil or type(player.isDead) ~= "function" or player:isDead()
            or type(player.isAsleep) ~= "function" or player:isAsleep() then return false end
    if type(isClient) == "function" and isClient() == true then
        if type(sendClientCommand) ~= "function" then return false end
        sendClientCommand(player, "ProjectALife", "safehouseDoorSync", {})
        return true
    end
    local visit = ProjectALife.SafehouseVisit
    return visit ~= nil and type(visit.syncDoor) == "function" and visit.syncDoor(player) == true
end

function Client.created(playerNum)
    if type(playerNum) ~= "number" or playerNum < 0 or playerNum > 3 or playerNum % 1 ~= 0 then return end
    Client.knocks[playerNum] = nil
    Client.syncDoor(playerNum)
end

function Client.contextObjects(worldobjects)
    local found, seen = {}, {}
    for index, object in ipairs(worldobjects) do
        if index > 16 then break end
        if not seen[object] then found[#found + 1], seen[object] = object, true end
        local square = type(object.getSquare) == "function" and object:getSquare() or nil
        local objects = square ~= nil and type(square.getObjects) == "function" and square:getObjects() or nil
        if objects ~= nil and type(objects.size) == "function" and type(objects.get) == "function" then
            for offset = 0, math.min(objects:size(), 64) - 1 do
                local other = objects:get(offset)
                if other ~= nil and not seen[other] then found[#found + 1], seen[other] = other, true end
            end
        end
    end
    return found
end

function Client.fill(playerNum, context, worldobjects, test)
    local saved, player = Client.doorVisit(playerNum)
    if saved ~= nil then
        local record = ProjectALife.TalkMenu.recordFor(saved.uid)
        local guest = record ~= nil and type(record.memory) == "table" and record.memory.guest or nil
        if type(guest) == "table" and guest.pendingId == saved.pendingId then saved = nil end
    end
    if type(worldobjects) ~= "table" or type(instanceof) ~= "function" then return end
    worldobjects = Client.contextObjects(worldobjects)
    if saved == nil then
        if test ~= true then
            for index, object in ipairs(worldobjects) do
                if index > 1040 then break end
                if object ~= nil and (instanceof(object, "IsoDoor") or instanceof(object, "IsoWindow")
                        or (instanceof(object, "IsoThumpable") and type(object.isDoor) == "function" and object:isDoor())) then
                    Client.syncDoor(playerNum)
                    if Client.markSeen == true and type(context) == "table" and type(context.addOption) == "function" then
                        context:addOption(Text.ui("Wash any mark off the wall"), playerNum, Client.wash)
                    end
                    break
                end
            end
        end
        return
    end
    local matching
    local window = saved.door.kind == "window"
    for index, object in ipairs(worldobjects) do
        if index > 1040 then break end
        local fits = false
        if object ~= nil then
            if window then
                fits = instanceof(object, "IsoWindow") == true
            else
                fits = instanceof(object, "IsoDoor") or (instanceof(object, "IsoThumpable")
                    and type(object.isDoor) == "function" and object:isDoor())
            end
        end
        if fits and type(object.getSquare) == "function" and type(object.getOppositeSquare) == "function" then
            local square = object:getSquare()
            local opposite = object:getOppositeSquare()
            if square ~= nil and type(square.getX) == "function" and type(square.getY) == "function" and type(square.getZ) == "function"
                    and opposite ~= nil and type(opposite.getX) == "function" and type(opposite.getY) == "function" and type(opposite.getZ) == "function" then
                local x, y, z = square:getX(), square:getY(), square:getZ()
                local ox, oy, oz = opposite:getX(), opposite:getY(), opposite:getZ()
                if z == saved.door.z and oz == z and ((x == saved.door.ix and y == saved.door.iy and ox == saved.door.sx and oy == saved.door.sy)
                        or (x == saved.door.sx and y == saved.door.sy and ox == saved.door.ix and oy == saved.door.iy)) then
                    matching = object; break
                end
            end
        end
    end
    if matching == nil then return end
    if test == true then
        if ISWorldObjectContextMenu ~= nil and type(ISWorldObjectContextMenu.setTest) == "function" then return ISWorldObjectContextMenu.setTest() end
        return
    end
    if type(context) ~= "table" or type(context.addOption) ~= "function" then return end
    context:addOption(Text.ui("Who is it?"), playerNum, Client.openDoor, saved, "DOOR_WHO")
    context:addOption(Text.ui("Put your weapons down"), playerNum, Client.openDoor, saved, "DOOR_WEAPONS_DOWN")
    context:addOption(Text.ui("Tell them to leave"), playerNum, Client.openDoor, saved, "DOOR_LEAVE")
    if not window and type(matching.IsOpen) == "function" and matching:IsOpen()
            and math.floor(player:getZ()) == math.floor(saved.z)
            and (player:getX() - saved.x)^2 + (player:getY() - saved.y)^2 <= 4 then
        context:addOption(Text.ui("Search them"), playerNum, Client.openDoor, saved, "DOOR_SEARCH")
        if saved.row == "beggar" then context:addOption(Text.ui("Give food"), playerNum, Client.openDoor, saved, "DOOR_GIVE") end
    end
end

function Client.notice(arguments, player)
    if type(arguments) ~= "table" or type(arguments.text) ~= "string" or #arguments.text > 400 then return false end
    player = player or (type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil)
    if player == nil then return false end
    if HaloTextHelper ~= nil and type(HaloTextHelper.addText) == "function" then HaloTextHelper.addText(player, arguments.text) end
    Client.lastNotice = { text = arguments.text }
    if type(arguments.mark) == "string" then Client.markSeen = true end
    return true
end

Client.sweeps = {}

function Client.light(arguments)
    if type(arguments) ~= "table" or tonumber(arguments.x1) == nil or tonumber(arguments.y2) == nil then return false end
    local stamp = type(getTimestampMs) == "function" and getTimestampMs() or 0
    local width, height = arguments.x2 - arguments.x1, arguments.y2 - arguments.y1
    local z = math.floor(tonumber(arguments.z) or 0)
    local windows = type(arguments.windows) == "table" and arguments.windows or {}
    if #windows > 0 then
        for step = 0, math.max(#windows, 4) - 1 do
            local window = windows[1 + step % #windows]
            if type(window) == "table" and tonumber(window.x) ~= nil and tonumber(window.y) ~= nil then
                Client.sweeps[#Client.sweeps + 1] = { atMs = stamp + step * 450, x = math.floor(window.x),
                    y = math.floor(window.y), z = z }
            end
        end
    else
        for step = 0, 5 do
            local t = step / 5
            Client.sweeps[#Client.sweeps + 1] = { atMs = stamp + step * 450, x = math.floor(arguments.x1 + width * t),
                y = math.floor(arguments.y2 + 1), z = z }
        end
    end
    while #Client.sweeps > 12 do table.remove(Client.sweeps, 1) end
    return true
end

function Client.sweepTick()
    if #Client.sweeps == 0 or type(getTimestampMs) ~= "function" or type(getCell) ~= "function" or IsoLightSource == nil then return end
    local now, kit = getTimestampMs(), ProjectALife.NightKit
    for index = #Client.sweeps, 1, -1 do
        local sweep = Client.sweeps[index]
        if now >= sweep.atMs then
            table.remove(Client.sweeps, index)
            local cell = getCell()
            if cell ~= nil and kit ~= nil and type(kit.queueLight) == "function" then
                pcall(function()
                    kit.queueLight(cell, IsoLightSource.new(sweep.x, sweep.y, sweep.z, 1.0, 0.95, 0.75, 9, 45))
                end)
            end
        end
    end
end

if type(Events) == "table" and Events.OnTick ~= nil and type(Events.OnTick.Add) == "function" then
    Events.OnTick.Add(Client.sweepTick)
end

function Client.hasMark(api, text, x, y)
    if type(api.getSymbolCount) ~= "function" or type(api.getSymbolByIndex) ~= "function" then return false end
    for index = 0, api:getSymbolCount() - 1 do
        local symbol = api:getSymbolByIndex(index)
        if symbol ~= nil and type(symbol.getWorldX) == "function" and type(symbol.getWorldY) == "function"
                and math.abs(symbol:getWorldX() - x) <= 1.5 and math.abs(symbol:getWorldY() - y) <= 1.5 then
            local shown = nil
            if type(symbol.getUntranslatedText) == "function" then shown = symbol:getUntranslatedText() end
            if shown == nil and type(symbol.getTranslatedText) == "function" then shown = symbol:getTranslatedText() end
            if shown == text then return true end
        end
    end
    return false
end

function Client.mark(arguments, player)
    if type(arguments) ~= "table" or tonumber(arguments.x) == nil or tonumber(arguments.y) == nil then return false end
    local text = type(arguments.name) == "string" and string.sub(arguments.name, 1, 60) or "Camp"
    local instance = ISWorldMap_instance
    if instance == nil and ISWorldMap ~= nil and type(ISWorldMap.ShowWorldMap) == "function" then
        pcall(ISWorldMap.ShowWorldMap, 0, arguments.x, arguments.y, 12.0)
        instance = ISWorldMap_instance
    end
    local api = instance ~= nil and instance.mapAPI ~= nil and instance.mapAPI:getSymbolsAPI() or nil
    if api == nil or type(api.addUntranslatedText) ~= "function" then return false end
    if Client.hasMark(api, text, tonumber(arguments.x), tonumber(arguments.y)) then return true end
    local ok = pcall(function()
        local symbol = api:addUntranslatedText(text, api:getDefaultTextLayerID(), arguments.x, arguments.y)
        symbol:setRGBA(1.0, 0.7, 0.1, 1.0)
        symbol:setAnchor(0.5, 0.5)
        symbol:setScale(1.0)
    end)
    if ok and player ~= nil and HaloTextHelper ~= nil and type(HaloTextHelper.addText) == "function" then
        HaloTextHelper.addText(player, Text.ui("{name} marked on your map", { name = text }))
    end
    return ok
end

function Client.wash(playerNum)
    if type(getSpecificPlayer) ~= "function" then return false end
    local player = getSpecificPlayer(playerNum or 0)
    if player == nil then return false end
    if type(isClient) == "function" and isClient() == true then
        if type(sendClientCommand) ~= "function" then return false end
        sendClientCommand(player, "ProjectALife", "safehouseWash", {})
        Client.markSeen = nil
        return true
    end
    local director = ProjectALife.SafehouseDirector
    return director ~= nil and type(director.wash) == "function" and director.wash(player) == true
end

function Client.onServerCommand(module, command, arguments)
    if module == "ProjectALife" and command == "safehouseNotice" then Client.notice(arguments) end
    if module == "ProjectALife" and command == "safehouseLight" then Client.light(arguments) end
    if module == "ProjectALife" and command == "havenMarker" then
        Client.mark(arguments, type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil)
    end
    if module == "ProjectALife" and command == "safehouseKnock" then Client.knock(arguments) end
end

function Client.helloTick()
    local hello = Client.hello
    if hello.acked or hello.tries >= hello.maxTries then
        if Events ~= nil and Events.OnTick ~= nil and type(Events.OnTick.Remove) == "function" then
            Events.OnTick.Remove(Client.helloTick)
        end
        return
    end
    if not (type(isClient) == "function" and isClient()) then hello.tries = hello.maxTries; return end
    if type(isCoopHost) ~= "function" or isCoopHost() ~= true then hello.tries = hello.maxTries; return end
    hello.ticks = hello.ticks + 1
    if hello.ticks < hello.nextTick or type(getSpecificPlayer) ~= "function" then return end
    local player = getSpecificPlayer(0)
    if player == nil or type(sendClientCommand) ~= "function" then return end
    sendClientCommand(player, "ProjectALife", "safehouseHello", { coopHost = true })
    hello.tries, hello.nextTick = hello.tries + 1, hello.ticks + 600
end

if type(Events) == "table" and Events.OnFillWorldObjectContextMenu ~= nil and type(Events.OnFillWorldObjectContextMenu.Add) == "function" then
    Events.OnFillWorldObjectContextMenu.Add(ProjectALife.TalkUi.guarded(Client.fill))
end

if type(Events) == "table" and Events.OnServerCommand ~= nil and type(Events.OnServerCommand.Add) == "function" then
    Events.OnServerCommand.Add(Client.onServerCommand)
end

if type(Events) == "table" and Events.OnCreatePlayer ~= nil and type(Events.OnCreatePlayer.Add) == "function" then
    Events.OnCreatePlayer.Add(Client.created)
end

if type(Events) == "table" and Events.OnTick ~= nil and type(Events.OnTick.Add) == "function" then
    Events.OnTick.Add(Client.helloTick)
end

return Client
