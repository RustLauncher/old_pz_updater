require "ProjectALife/Core/ALifeText"
require "ProjectALife/Talk/ALifeSpeech"
require "ProjectALife/Shells/ALifeWounds"
require "ProjectALife/Shells/ALifeShellSimulation"

ProjectALife = ProjectALife or {}

local WoundsMenu = { reach = 3, dressings = { "Base.AlcoholBandage", "Base.Bandage", "Base.AlcoholRippedSheets", "Base.RippedSheets" },
    reasons = {
        too_far = "Get closer to check their wounds.",
        unavailable = "They can't be treated now.",
        hostile = "They won't let you near their wounds.",
        not_needed = "Nothing there needs a dressing.",
        no_kit = "You need a bandage or ripped sheets.",
        no_splint = "You need a splint.",
    } }
ProjectALife.WoundsMenu = WoundsMenu

function WoundsMenu.uidOf(body)
    if body == nil or type(instanceof) ~= "function" or not instanceof(body, "IsoZombie") then return nil end
    local uid = ProjectALife.Speech.variable(body, "ALifeUID")
    if uid == nil or tostring(uid) == "" then return nil end
    return tostring(uid)
end

function WoundsMenu.patientNear(square)
    if square == nil or type(getCell) ~= "function" then return nil end
    local cell = getCell()
    local best, bestUid, bestDistance = nil, nil, 2.5
    local x, y, z = square:getX(), square:getY(), square:getZ()
    for dx = -1, 1 do
        for dy = -1, 1 do
            local around = cell:getGridSquare(x + dx, y + dy, z)
            local bodies = around ~= nil and around:getMovingObjects() or nil
            for index = 0, (bodies ~= nil and bodies:size() or 0) - 1 do
                local body = bodies:get(index)
                local uid = WoundsMenu.uidOf(body)
                if uid ~= nil and not body:isDead() then
                    local distance = math.sqrt((body:getX() - x - 0.5) ^ 2 + (body:getY() - y - 0.5) ^ 2)
                    if distance < bestDistance then best, bestUid, bestDistance = body, uid, distance end
                end
            end
        end
    end
    return best, bestUid
end

function WoundsMenu.clickedSquare(worldobjects)
    for _, object in ipairs(type(worldobjects) == "table" and worldobjects or {}) do
        if object ~= nil and type(object.getSquare) == "function" then
            local square = object:getSquare()
            if square ~= nil then return square end
        end
    end
    return nil
end

function WoundsMenu.hasDressing(player)
    local inventory = player:getInventory()
    if inventory == nil then return false end
    for _, itemType in ipairs(WoundsMenu.dressings) do
        if inventory:getFirstTypeRecurse(itemType) ~= nil then return true end
    end
    return false
end

function WoundsMenu.send(player, uid, treat)
    local args = { uid = uid, treat = treat == true or nil, splint = treat == "splint" or nil }
    WoundsMenu.pending = { player = player, treat = treat ~= nil and treat ~= false }
    if type(isClient) == "function" and isClient() then
        if type(sendClientCommand) == "function" then sendClientCommand(player, "ProjectALife", "npcWounds", args) end
        return
    end
    local health = ProjectALife.Health
    if health ~= nil and type(health.onClientCommand) == "function" then
        health.onClientCommand("ProjectALife", "npcWounds", player, args)
    end
end

function WoundsMenu.check(playerNum, uid, body)
    local player = getSpecificPlayer(playerNum)
    if player == nil then return end
    local panel = ProjectALife.WoundPanel
    if panel ~= nil and type(panel.open) == "function" and panel.open(playerNum, uid, body) then return end
    WoundsMenu.send(player, uid, false)
end

function WoundsMenu.treat(playerNum, uid)
    local player = getSpecificPlayer(playerNum)
    if player ~= nil then WoundsMenu.send(player, uid, true) end
end

function WoundsMenu.splint(playerNum, uid)
    local player = getSpecificPlayer(playerNum)
    if player ~= nil then WoundsMenu.send(player, uid, "splint") end
end

function WoundsMenu.say(player, text, good)
    if player == nil or text == nil or text == "" then return end
    if HaloTextHelper ~= nil then
        if good == false and type(HaloTextHelper.addBadText) == "function" then return HaloTextHelper.addBadText(player, text) end
        if type(HaloTextHelper.addText) == "function" then return HaloTextHelper.addText(player, text) end
    end
    if type(player.Say) == "function" then player:Say(text) end
end

function WoundsMenu.receive(payload)
    if type(payload) ~= "table" then return end
    local panel = ProjectALife.WoundPanel
    if panel ~= nil and type(panel.take) == "function" and panel.take(payload) then return end
    local pending = WoundsMenu.pending
    local player = pending ~= nil and pending.player or (type(getPlayer) == "function" and getPlayer() or nil)
    WoundsMenu.pending = nil
    local Text = ProjectALife.Text
    if payload.reason ~= nil then
        WoundsMenu.say(player, Text.ui(WoundsMenu.reasons[payload.reason] or WoundsMenu.reasons.unavailable), false)
        return
    end
    local described, count = ProjectALife.Wounds.describe(payload.injuries, tonumber(payload.hours) or 0, 3)
    local text
    if count == 0 then
        text = Text.ui("No wounds you can see.")
    else
        text = described
        if count > 3 then text = text .. " " .. Text.ui("(+{n} more)", { n = count - 3 }) end
    end
    if payload.treated == true then text = Text.ui("Dressed.") .. " " .. text end
    if payload.downed == true then text = Text.ui("Bleeding out.") .. " " .. text end
    WoundsMenu.say(player, text, true)
end

ProjectALife.WoundsClientReceive = WoundsMenu.receive

function WoundsMenu.onServerCommand(module, command, payload)
    if module ~= "ProjectALife" then return end
    if command == "putDownCorpse" then return WoundsMenu.receivePutDown(payload) end
    if command == "turnCleared" then return WoundsMenu.clearTurning(payload) end
    if command ~= "npcWounds" then return end
    WoundsMenu.receive(payload)
end

function WoundsMenu.fill(playerNum, context, worldobjects, test)
    if test or type(context) ~= "table" or type(context.addOption) ~= "function" then return end
    local ok = pcall(WoundsMenu.addOptions, playerNum, context, worldobjects)
    if not ok then WoundsMenu.faults = (WoundsMenu.faults or 0) + 1 end
end

WoundsMenu.putDown = { reach = 2.5, actionTicks = 40 }

function WoundsMenu.putDownReason(reason)
    local Text = ProjectALife.Text
    if reason == "no_weapon" then return Text.ui("You need a weapon") end
    if reason == "too_far" then return Text.ui("Get closer") end
    if reason == "not_pending" then return Text.ui("Nothing to put down here") end
    return Text.ui("You can't do that now")
end

function WoundsMenu.pendingCorpseNear(square)
    if square == nil or type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil then return nil end
    local best, bestUid, bestDistance = nil, nil, 2.5
    local x, y, z = square:getX(), square:getY(), square:getZ()
    for dx = -1, 1 do
        for dy = -1, 1 do
            local around = cell:getGridSquare(x + dx, y + dy, z)
            local bodies = nil
            if around ~= nil and type(around.getDeadBodys) == "function" then bodies = around:getDeadBodys() end
            local count = 0
            if bodies ~= nil then count = bodies:size() end
            for index = 0, count - 1 do
                local body = bodies:get(index)
                local uid = WoundsMenu.pendingUid(body)
                if uid ~= nil then
                    local distance = math.sqrt((body:getX() - x - 0.5) ^ 2 + (body:getY() - y - 0.5) ^ 2)
                    if distance < bestDistance then best, bestUid, bestDistance = body, uid, distance end
                end
            end
        end
    end
    return best, bestUid
end

function WoundsMenu.pendingUid(body)
    if body == nil or type(body.getModData) ~= "function" then return nil end
    if type(body.hasModData) == "function" and body:hasModData() ~= true then return nil end
    local data = body:getModData()
    if type(data) ~= "table" or data.ProjectALifeTurnPending ~= true then return nil end
    local uid = data.ProjectALifeCorpseOf
    if type(uid) ~= "string" or uid == "" then return nil end
    return uid
end

function WoundsMenu.putDownReady(player, body)
    if player == nil or body == nil then return false end
    if math.abs(body:getZ() - player:getZ()) > 0.5 then return false end
    local dx, dy = body:getX() - player:getX(), body:getY() - player:getY()
    return dx * dx + dy * dy <= WoundsMenu.putDown.reach ^ 2
end

function WoundsMenu.weaponTip(option)
    local pool = ISInventoryPaneContextMenu
    if pool == nil or type(pool.addToolTip) ~= "function" then return end
    local tip = pool.addToolTip()
    if tip == nil then return end
    tip.description = WoundsMenu.putDownReason("no_weapon")
    option.toolTip = tip
end

function WoundsMenu.fillPutDown(playerNum, context, square, player)
    if square == nil or player == nil then return false end
    local body, uid = WoundsMenu.pendingCorpseNear(square)
    if body == nil or not WoundsMenu.putDownReady(player, body) then return false end
    local option = context:addOption(ProjectALife.Text.ui("Put down"), playerNum, WoundsMenu.startPutDown, uid, body)
    local sim = ProjectALife.ShellSimulation
    local weapon = nil
    if sim ~= nil and type(sim.putDownWeapon) == "function" then weapon = sim.putDownWeapon(player) end
    if weapon == nil then
        option.notAvailable = true
        WoundsMenu.weaponTip(option)
    end
    return true
end

function WoundsMenu.putDownClass()
    if WoundsMenu.PutDownAction ~= nil then return WoundsMenu.PutDownAction end
    if type(ISBaseTimedAction) ~= "table" then return nil end
    local Action = ISBaseTimedAction:derive("ALifePutDown")

    function Action:isValid()
        return WoundsMenu.pendingUid(self.body) == self.uid and WoundsMenu.putDownReady(self.character, self.body)
    end

    function Action:waitToStart()
        self.character:faceThisObject(self.body)
        return self.character:shouldBeTurning()
    end

    function Action:update()
        self.character:faceThisObject(self.body)
    end

    function Action:start()
        self:setActionAnim("Loot")
        self:setAnimVariable("LootPosition", "Low")
        self.character:reportEvent("EventLootItem")
    end

    function Action:stop()
        ISBaseTimedAction.stop(self)
    end

    function Action:perform()
        ISBaseTimedAction.perform(self)
        WoundsMenu.sendPutDown(self.character, self.uid)
    end

    function Action:new(character, body, uid)
        local o = ISBaseTimedAction.new(self, character)
        o.body, o.uid = body, uid
        o.maxTime = WoundsMenu.putDown.actionTicks
        o.stopOnWalk = true
        o.stopOnRun = true
        if type(character.isTimedActionInstant) == "function" and character:isTimedActionInstant() == true then o.maxTime = 1 end
        return o
    end

    WoundsMenu.PutDownAction = Action
    return Action
end

function WoundsMenu.startPutDown(playerNum, uid, body)
    local player = getSpecificPlayer(playerNum)
    if player == nil or not WoundsMenu.putDownReady(player, body) then return false end
    local Action = WoundsMenu.putDownClass()
    if Action == nil or type(ISTimedActionQueue) ~= "table" then
        WoundsMenu.sendPutDown(player, uid)
        return true
    end
    ISTimedActionQueue.add(Action:new(player, body, uid))
    return true
end

function WoundsMenu.sendPutDown(player, uid)
    local args = { uid = uid }
    if type(isClient) == "function" and isClient() then
        if type(sendClientCommand) == "function" then sendClientCommand(player, "ProjectALife", "putDownCorpse", args) end
        return true
    end
    local life = ProjectALife.Lifecycle
    if life ~= nil and type(life.putDown) == "function" then
        life.putDown(player, args)
        return true
    end
    return false
end

function WoundsMenu.receivePutDown(payload)
    if type(payload) ~= "table" then return false end
    local player = type(getPlayer) == "function" and getPlayer() or nil
    local text
    if payload.ok == true then
        text = ProjectALife.Text.ui("It won't get up now")
    else
        text = WoundsMenu.putDownReason(payload.reason)
    end
    WoundsMenu.say(player, text, payload.ok == true)
    return true
end

ProjectALife.PutDownReceive = WoundsMenu.receivePutDown

function WoundsMenu.clearTurning(payload)
    if type(payload) ~= "table" or type(payload.uid) ~= "string" or type(getCell) ~= "function" then return false end
    local cell = getCell()
    local x, y, z = tonumber(payload.x), tonumber(payload.y), tonumber(payload.z)
    if cell == nil or x == nil or y == nil or z == nil then return false end
    x, y, z = math.floor(x), math.floor(y), math.floor(z)
    local cleared = false
    for dx = -1, 1 do
        for dy = -1, 1 do
            local around = cell:getGridSquare(x + dx, y + dy, z)
            local bodies = nil
            if around ~= nil and type(around.getDeadBodys) == "function" then bodies = around:getDeadBodys() end
            local count = 0
            if bodies ~= nil then count = bodies:size() end
            for index = 0, count - 1 do
                local body = bodies:get(index)
                if WoundsMenu.pendingUid(body) == payload.uid then
                    body:getModData().ProjectALifeTurnPending = nil
                    cleared = true
                end
            end
        end
    end
    return cleared
end

function WoundsMenu.addOptions(playerNum, context, worldobjects)
    local player = getSpecificPlayer(playerNum)
    if player == nil then return end
    pcall(WoundsMenu.fillPutDown, playerNum, context, WoundsMenu.clickedSquare(worldobjects), player)
    local body, uid = WoundsMenu.patientNear(WoundsMenu.clickedSquare(worldobjects))
    if body == nil then
        local panel = ProjectALife.WoundPanel
        if panel ~= nil and type(panel.fillCorpse) == "function" then
            panel.fillCorpse(playerNum, context, WoundsMenu.clickedSquare(worldobjects), player)
        end
        return
    end
    if math.abs(body:getZ() - player:getZ()) > 0.5
            or (body:getX() - player:getX()) ^ 2 + (body:getY() - player:getY()) ^ 2 > WoundsMenu.reach ^ 2 then
        return
    end
    local Text = ProjectALife.Text
    context:addOption(Text.ui("Check wounds"), playerNum, WoundsMenu.check, uid, body)
    local option = context:addOption(Text.ui("Dress their wounds"), playerNum, WoundsMenu.treat, uid)
    if not WoundsMenu.hasDressing(player) then option.notAvailable = true end
    local inventory = player:getInventory()
    if inventory ~= nil and inventory:getFirstTypeRecurse("Base.Splint") ~= nil then
        context:addOption(Text.ui("Splint their fracture"), playerNum, WoundsMenu.splint, uid)
    end
end

if type(Events) == "table" and Events.OnFillWorldObjectContextMenu ~= nil
        and type(Events.OnFillWorldObjectContextMenu.Add) == "function" then
    Events.OnFillWorldObjectContextMenu.Add(WoundsMenu.fill)
end
if type(Events) == "table" and Events.OnServerCommand ~= nil and type(Events.OnServerCommand.Add) == "function" then
    Events.OnServerCommand.Add(WoundsMenu.onServerCommand)
end

return WoundsMenu
