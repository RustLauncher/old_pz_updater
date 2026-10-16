require "ProjectALife/Core/ALifeText"
require "ProjectALife/Behaviours/ALifeInjuryRules"
require "ProjectALife/Talk/ALifeSpeech"

ProjectALife = ProjectALife or {}

local Rules = ProjectALife.InjuryRules

local Menu = {}
ProjectALife.InjuryMenu = Menu

function Menu.reasonText(reason)
    local Text = ProjectALife.Text
    if reason == "too_far" then return Text.ui("Get closer first.") end
    if reason == "no_kit" then return Text.ui("You need a bandage or medical supplies.") end
    if reason == "not_injured" then return Text.ui("They are not in a state to be helped.") end
    if reason == "disabled" or reason == "option_off" then return Text.ui("The injury option is off.") end
    if reason == "busy" then return Text.ui("Give them a moment.") end
    if reason == "sp_only" then return Text.ui("Injury test is single player only.") end
    if reason == "no_body" then return Text.ui("No NPC body found.") end
    if reason == "unknown_question" then return Text.ui("They can't answer that.") end
    if reason == "fault" then return Text.ui("Something went wrong.") end
    return Text.ui("They can't be reached now.")
end

function Menu.questionLabel(id)
    local Text = ProjectALife.Text
    if id == "who" then return Text.ui("Who are you?") end
    if id == "group" then return Text.ui("Where is your group?") end
    if id == "origin" then return Text.ui("Where do you come from?") end
    if id == "culprit" then return Text.ui("Who did this to you?") end
    return Text.ui("Anything else?")
end

function Menu.available()
    if type(isClient) == "function" and isClient() == true then return false end
    if type(isServer) == "function" and isServer() == true then return false end
    return Rules ~= nil and Rules.flag("Injury_Enabled", true) == true
end

function Menu.uidOf(body)
    if body == nil or type(instanceof) ~= "function" or not instanceof(body, "IsoZombie") then return nil end
    local uid = ProjectALife.Speech.variable(body, "ALifeUID")
    if uid == nil or tostring(uid) == "" then return nil end
    return tostring(uid)
end

function Menu.stateOf(body)
    local ok, data = pcall(function() return body:getModData() end)
    if not ok or type(data) ~= "table" then return nil end
    return data.ProjectALifeInjured
end

function Menu.bodyNear(square)
    if square == nil or type(getCell) ~= "function" then return nil end
    local cell = getCell()
    local best, bestUid, bestDistance = nil, nil, 3
    local x, y, z = square:getX(), square:getY(), square:getZ()
    for dx = -1, 1 do
        for dy = -1, 1 do
            local around = cell:getGridSquare(x + dx, y + dy, z)
            local bodies = around ~= nil and around:getMovingObjects() or nil
            for index = 0, (bodies ~= nil and bodies:size() or 0) - 1 do
                local body = bodies:get(index)
                local uid = Menu.uidOf(body)
                if uid ~= nil and not body:isDead() and Menu.stateOf(body) == "down" then
                    local distance = math.sqrt((body:getX() - x - 0.5) ^ 2 + (body:getY() - y - 0.5) ^ 2)
                    if distance < bestDistance then best, bestUid, bestDistance = body, uid, distance end
                end
            end
        end
    end
    return best, bestUid
end

function Menu.clickedSquare(worldobjects)
    for _, object in ipairs(type(worldobjects) == "table" and worldobjects or {}) do
        if object ~= nil and type(object.getSquare) == "function" then
            local square = object:getSquare()
            if square ~= nil then return square end
        end
    end
    return nil
end

function Menu.hasKit(player)
    local inventory = player:getInventory()
    if inventory == nil then return false end
    return Rules.kitOf(inventory) ~= nil
end

function Menu.send(player, command, args)
    local aid = ProjectALife.InjuryAid
    if aid ~= nil and type(aid.onClientCommand) == "function" then
        aid.onClientCommand("ProjectALife", command, player, args)
        return true
    end
    return false
end

function Menu.ask(playerNum, uid, question)
    local player = getSpecificPlayer(playerNum)
    if player ~= nil then Menu.send(player, "injuryInterrogate", { uid = uid, question = question }) end
end

function Menu.aid(playerNum, uid)
    local player = getSpecificPlayer(playerNum)
    if player ~= nil then Menu.send(player, "injuryAid", { uid = uid }) end
end

function Menu.say(player, text, good)
    if player == nil or text == nil or text == "" then return end
    local helper = HaloTextHelper
    if helper ~= nil then
        if good == false and type(helper.addBadText) == "function" then return helper.addBadText(player, text) end
        if good == true and type(helper.addGoodText) == "function" then return helper.addGoodText(player, text) end
        if type(helper.addText) == "function" then return helper.addText(player, text) end
    end
    if type(player.setHaloNote) == "function" then
        if good == false then return player:setHaloNote(text, 235, 70, 60, 200) end
        return player:setHaloNote(text, 220, 220, 220, 200)
    end
    if type(player.Say) == "function" then player:Say(text) end
end

function Menu.receive(payload)
    if type(payload) ~= "table" then return end
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil
    local Text = ProjectALife.Text
    if payload.kind == "debug" then
        if payload.ok == true then
            if payload.action == "heal" then Menu.say(player, Text.ui("Injury: healed"), true)
            elseif payload.action == "rescue" then Menu.say(player, Text.ui("Injury: rescue started"), true)
            else Menu.say(player, Text.ui("Injury: made injured"), true) end
            return
        end
        Menu.say(player, Text.ui("Injury debug: {reason}", { reason = tostring(payload.reason or "failed") }), false)
        return
    end
    if payload.ok ~= true then
        Menu.say(player, Menu.reasonText(payload.reason), false)
        return
    end
    if payload.kind == "interrogate" and payload.died == true then
        Menu.say(player, Text.ui("Looks like they bled out..."), false)
        return
    end
    if payload.kind == "aid" then Menu.say(player, Text.ui("They will make it."), true) end
end

ProjectALife.InjuryClientReceive = Menu.receive

function Menu.onServerCommand(module, command, payload)
    if module ~= "ProjectALife" or command ~= "injuryResult" then return end
    Menu.receive(payload)
end

function Menu.addDebugEntry(menu, playerNum, uid, label, action)
    menu:addOption(label, playerNum, Menu.debug, uid, action)
end

function Menu.debug(playerNum, uid, action)
    local player = getSpecificPlayer(playerNum)
    if player == nil or type(sendClientCommand) ~= "function" then return end
    sendClientCommand(player, "ProjectALife", "debugInjury", { uid = uid, action = action })
end

function Menu.addDebug(menu, playerNum, shell)
    if shell == nil or menu == nil then return end
    local ok, data = pcall(function() return shell:getModData() end)
    local uid = ok and type(data) == "table" and data.ProjectALifeUID or nil
    if type(uid) ~= "string" then return end
    local Text = ProjectALife.Text
    Menu.addDebugEntry(menu, playerNum, uid, Text.ui("Injury: make injured"), "injure")
    Menu.addDebugEntry(menu, playerNum, uid, Text.ui("Injury: heal"), "heal")
    Menu.addDebugEntry(menu, playerNum, uid, Text.ui("Injury: force rescue now"), "rescue")
end

function Menu.addOptions(playerNum, context, worldobjects)
    if not Menu.available() then return end
    local player = getSpecificPlayer(playerNum)
    if player == nil then return end
    local body, uid = Menu.bodyNear(Menu.clickedSquare(worldobjects))
    if body == nil then return end
    if math.abs(body:getZ() - player:getZ()) > 0.5
            or (body:getX() - player:getX()) ^ 2 + (body:getY() - player:getY()) ^ 2 > Rules.settings().reachTiles ^ 2 then
        return
    end
    if type(context.getNew) ~= "function" or type(context.addSubMenu) ~= "function" then return end
    local Text = ProjectALife.Text
    local root = context:addOption(Text.ui("Injured survivor"))
    local menu = context:getNew(context)
    context:addSubMenu(root, menu)
    local talk = menu:addOption(Text.ui("Talk (they can barely speak)"))
    talk.notAvailable = true
    local ask = menu:addOption(Text.ui("Interrogate..."))
    local askMenu = menu:getNew(menu)
    menu:addSubMenu(ask, askMenu)
    for _, row in ipairs(Rules.questions) do
        askMenu:addOption(Menu.questionLabel(row.id), playerNum, Menu.ask, uid, row.id)
    end
    local give = menu:addOption(Text.ui("Give bandage / medical"), playerNum, Menu.aid, uid)
    if not Menu.hasKit(player) then give.notAvailable = true end
end

function Menu.fill(playerNum, context, worldobjects, test)
    if test or type(context) ~= "table" or type(context.addOption) ~= "function" then return end
    local ok = pcall(Menu.addOptions, playerNum, context, worldobjects)
    if not ok then Menu.faults = (Menu.faults or 0) + 1 end
end

if type(Events) == "table" and Events.OnFillWorldObjectContextMenu ~= nil
        and type(Events.OnFillWorldObjectContextMenu.Add) == "function" then
    Events.OnFillWorldObjectContextMenu.Add(Menu.fill)
end
if type(Events) == "table" and Events.OnServerCommand ~= nil and type(Events.OnServerCommand.Add) == "function" then
    Events.OnServerCommand.Add(Menu.onServerCommand)
end

return Menu
