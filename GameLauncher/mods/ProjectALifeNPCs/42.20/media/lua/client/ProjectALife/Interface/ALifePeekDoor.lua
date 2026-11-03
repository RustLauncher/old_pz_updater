require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISUI3DModel"
require "ProjectALife/Core/ALifeText"
require "ProjectALife/Interface/ALifeMenuPrefs"
require "ProjectALife/Interface/ALifePeekDoorData"
require "ProjectALife/Interface/ALifePeekScene"
require "ProjectALife/Interface/ALifePeekLens"
require "ProjectALife/Talk/ALifeTalkUi"
require "ProjectALife/Talk/ALifeTalkMenu"

ProjectALife = ProjectALife or {}

local Text = ProjectALife.Text
local Data = ProjectALife.PeekData
local Lens = ProjectALife.PeekLens
local Peek = {
    windows = {},
    fading = {},
    metrics = { opens = 0, closes = 0, scans = 0, refused = 0, notices = 0, faults = 0, lensFrames = 0, lensCalls = 0, lensPeak = 0,
        lensFaults = 0, fullFaults = 0, escCloses = 0 },
    keysHooked = false,
    keysDirty = false,
    inKey = false,
    keyName = "ALife_PeekDoor",
    steps = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } },
    empty = {},
}
ProjectALife.PeekDoor = Peek

function Peek.log(text)
    print("[ALIFE-PEEK] " .. text)
end

function Peek.nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return 0
end

function Peek.ask(object, name, argument)
    local kind = type(object)
    if object == nil or kind == "number" or kind == "string" or kind == "boolean" then return nil end
    local method = object[name]
    if type(method) ~= "function" then return nil end
    local ok, value
    if argument == nil then
        ok, value = pcall(method, object)
    else
        ok, value = pcall(method, object, argument)
    end
    if ok then return value end
    return nil
end

function Peek.prefOn()
    local prefs = ProjectALife.MenuPrefs
    if prefs ~= nil and type(prefs.peekDoorOn) == "function" then return prefs.peekDoorOn() == true end
    return true
end

function Peek.revealOn(player)
    local prefs = ProjectALife.MenuPrefs
    if prefs ~= nil and type(prefs.allowed) == "function" then return prefs.allowed(player) == true end
    return false
end

function Peek.liveOn()
    local prefs = ProjectALife.MenuPrefs
    local wanted = true
    if prefs ~= nil and type(prefs.peekLiveOn) == "function" then wanted = prefs.peekLiveOn() == true end
    return wanted and ProjectALife.PeekScene ~= nil and type(getTexture) == "function"
end

function Peek.fallBack(window, err)
    if window.live ~= true then return false end
    window.live = false
    window.sceneFault = tostring(err)
    ProjectALife.PeekScene.metrics.faults = ProjectALife.PeekScene.metrics.faults + 1
    Peek.log("real view off: " .. string.sub(window.sceneFault, 1, 120))
    return true
end

function Peek.lensOn()
    local prefs = ProjectALife.MenuPrefs
    local wanted = true
    if prefs ~= nil and type(prefs.peekLensOn) == "function" then wanted = prefs.peekLensOn() == true end
    return wanted and Lens ~= nil
end

function Peek.lensFault(window, err)
    if window.lens ~= true then return false end
    window.lens = false
    Lens.detach(window)
    Lens.metrics.faults = Lens.metrics.faults + 1
    Peek.metrics.lensFaults = Peek.metrics.lensFaults + 1
    Peek.log("lens off: " .. string.sub(tostring(err), 1, 120))
    return true
end

function Peek.fullOn()
    local prefs = ProjectALife.MenuPrefs
    local wanted = true
    if prefs ~= nil and type(prefs.peekFullOn) == "function" then wanted = prefs.peekFullOn() == true end
    return wanted and Lens ~= nil and type(Lens.fullView) == "function"
end

function Peek.screenOf(playerNum)
    local left, top, screenW, screenH = 0, 0, 1280, 720
    if type(getPlayerScreenLeft) == "function" then
        left, top = getPlayerScreenLeft(playerNum), getPlayerScreenTop(playerNum)
        screenW, screenH = getPlayerScreenWidth(playerNum), getPlayerScreenHeight(playerNum)
    elseif type(getCore) == "function" then
        screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    end
    return left, top, screenW, screenH
end

function Peek.windowedSize(lens, screenW, screenH, barH)
    local width, height = 520, 360
    if lens then width, height = Lens.width, Lens.height end
    local scale = math.min(1, (screenW - 40) / width, (screenH - 40) / (height + barH))
    if scale <= 0.4 then scale = 0.4 end
    return math.floor(width * scale), math.floor(height * scale)
end

function Peek.escDown()
    if type(Keyboard) ~= "table" or type(Keyboard.isKeyDown) ~= "function" then return false end
    return Keyboard.isKeyDown(Keyboard.KEY_ESCAPE) == true
end

function Peek.wantKeys()
    for playerNum = 0, 3 do
        local window = Peek.windows[playerNum]
        if window ~= nil and window.lens == true then return true end
    end
    return false
end

function Peek.syncKeys()
    local event = type(Events) == "table" and Events.OnKeyPressed or nil
    if event == nil then return false end
    local want = Peek.wantKeys()
    if want and not Peek.keysHooked and type(event.Add) == "function" then
        event.Add(Peek.escKey)
        Peek.keysHooked = true
    elseif not want and Peek.keysHooked and not Peek.inKey and type(event.Remove) == "function" then
        event.Remove(Peek.escKey)
        Peek.keysHooked = false
    end
    Peek.keysDirty = not want and Peek.keysHooked
    return Peek.keysHooked
end

function Peek.escKey(key)
    if type(Keyboard) ~= "table" or key ~= Keyboard.KEY_ESCAPE then return end
    local window = Peek.windows[0]
    if window == nil or window.lens ~= true then return end
    Peek.inKey = true
    pcall(window.close, window, "esc")
    Peek.inKey = false
    Peek.metrics.escCloses = Peek.metrics.escCloses + 1
end

function Peek.calmOn()
    local prefs = ProjectALife.MenuPrefs
    if prefs ~= nil and type(prefs.calmOn) == "function" then return prefs.calmOn() == true end
    return true
end

function Peek.sandbox(name, default)
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(vars) ~= "table" then return default end
    local value = vars[name]
    if value == nil then return default end
    return value
end

function Peek.enabled()
    return Data.enabled(Peek.prefOn(), Peek.sandbox("Peek_Enabled", true))
end

function Peek.noticePercent()
    local value = tonumber(Peek.sandbox("Peek_NoticeChancePercent", Data.noticeDefault)) or Data.noticeDefault
    return Data.clamp(value, 0, 100)
end

function Peek.playerOf(playerNum)
    if type(getSpecificPlayer) ~= "function" then return nil end
    return getSpecificPlayer(playerNum or 0)
end

function Peek.usable(player)
    if player == nil or type(player.isDead) ~= "function" or player:isDead() then return false end
    if type(player.isAsleep) == "function" and player:isAsleep() then return false end
    if type(player.getVehicle) == "function" and player:getVehicle() ~= nil then return false end
    return true
end

function Peek.say(player, text)
    if player ~= nil and HaloTextHelper ~= nil and type(HaloTextHelper.addText) == "function" then
        HaloTextHelper.addText(player, text)
    end
end

function Peek.squareAt(x, y, z)
    local cell = type(getCell) == "function" and getCell() or nil
    if cell == nil or type(cell.getGridSquare) ~= "function" then return nil end
    return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z))
end

function Peek.inside(square)
    if square == nil then return false end
    return Peek.ask(square, "getBuilding") ~= nil or Peek.ask(square, "getRoom") ~= nil
end

function Peek.isDoorObject(object)
    if object == nil or type(instanceof) ~= "function" then return false end
    if instanceof(object, "IsoDoor") then return true end
    return instanceof(object, "IsoThumpable") and Peek.ask(object, "isDoor") == true
end

function Peek.garage(object)
    local method = IsoDoor ~= nil and IsoDoor.getGarageDoorIndex or nil
    if type(method) ~= "function" or type(instanceof) ~= "function" or not instanceof(object, "IsoDoor") then return false end
    local ok, index = pcall(method, object)
    return ok and (tonumber(index) or -1) >= 0
end

function Peek.doorClosed(object)
    return Peek.ask(object, "IsOpen") == false
end

function Peek.blocked(object)
    return Peek.ask(object, "isBarricaded") == true
end

function Peek.curtainClosed(object)
    local curtain = Peek.ask(object, "HasCurtains")
    if curtain == nil then return false end
    return Peek.ask(curtain, "IsOpen") == false
end

function Peek.geometryFor(object, player, reach)
    local square = Peek.ask(object, "getSquare")
    local north = Peek.ask(object, "getNorth")
    if square == nil or type(north) ~= "boolean" then return nil, "no_edge" end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local ox, oy = Data.edgeOther(x, y, north)
    local other = Peek.squareAt(ox, oy, z)
    if other == nil then return nil, "no_edge" end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    if math.abs(pz - z) > 0.9 then return nil, "floor" end
    local ownOut, otherOut = not Peek.inside(square), not Peek.inside(other)
    local ownDist = (px - (x + 0.5)) ^ 2 + (py - (y + 0.5)) ^ 2
    local otherDist = (px - (ox + 0.5)) ^ 2 + (py - (oy + 0.5)) ^ 2
    local farIsOwn = Data.chooseFar(ownOut, otherOut, ownDist, otherDist)
    if farIsOwn == nil then return nil, "outside" end
    local geo = Data.geometry(x, y, north, farIsOwn)
    geo.z = z
    if farIsOwn then
        geo.nearSquare, geo.farSquare = other, square
    else
        geo.nearSquare, geo.farSquare = square, other
    end
    if ownOut ~= otherOut and not Peek.inside(Peek.ask(player, "getCurrentSquare")) then return nil, "wrong_side" end
    if (px - geo.cx) ^ 2 + (py - geo.cy) ^ 2 > reach * reach then return nil, "far" end
    return geo
end

function Peek.visitSaved(playerNum)
    local client = ProjectALife.SafehouseClient
    if client == nil or type(client.doorVisit) ~= "function" or type(client.knocks) ~= "table"
            or client.knocks[playerNum] == nil or ProjectALife.TalkMenu == nil then return nil end
    local saved = client.doorVisit(playerNum)
    if type(saved) ~= "table" or type(saved.door) ~= "table" then return nil end
    return saved
end

function Peek.sameEdge(geo, door)
    return door.z == geo.z and door.ix == geo.nearX and door.iy == geo.nearY
        and door.sx == geo.farX and door.sy == geo.farY
end

function Peek.candidate(player, object, visit)
    if Peek.isDoorObject(object) then
        if not Peek.doorClosed(object) or Peek.garage(object) or Peek.blocked(object) then return nil end
        local geo = Peek.geometryFor(object, player, Data.reach)
        if geo == nil and visit ~= nil and visit.door.kind ~= "window" then
            geo = Peek.geometryFor(object, player, Data.visitReach)
            if geo ~= nil and not Peek.sameEdge(geo, visit.door) then geo = nil end
        end
        if geo == nil then return nil end
        return "door", geo
    end
    if visit ~= nil and visit.door.kind == "window" and type(instanceof) == "function" and instanceof(object, "IsoWindow") then
        if Peek.blocked(object) or Peek.curtainClosed(object) then return nil end
        local geo = Peek.geometryFor(object, player, Data.visitReach)
        if geo ~= nil and Peek.sameEdge(geo, visit.door) then return "window", geo end
    end
    return nil
end

function Peek.findTarget(playerNum, player, worldobjects)
    local visit = Peek.visitSaved(playerNum)
    for index, object in ipairs(worldobjects) do
        if index > 24 then break end
        if object ~= nil then
            local kind, geo = Peek.candidate(player, object, visit)
            if kind ~= nil then return object, kind, geo end
        end
    end
    return nil
end

function Peek.fill(playerNum, context, worldobjects, test)
    if type(worldobjects) ~= "table" or type(instanceof) ~= "function" then return end
    if Peek.windows[playerNum] ~= nil or not Peek.enabled() then return end
    local player = Peek.playerOf(playerNum)
    if not Peek.usable(player) then return end
    local object, kind = Peek.findTarget(playerNum, player, worldobjects)
    if object == nil then return end
    if test == true then
        if ISWorldObjectContextMenu ~= nil and type(ISWorldObjectContextMenu.setTest) == "function" then
            return ISWorldObjectContextMenu.setTest()
        end
        return
    end
    if type(context) ~= "table" or type(context.addOption) ~= "function" then return end
    if kind == "window" then
        context:addOption(Text.ui("Peek through the window"), playerNum, Peek.begin, object, kind)
    else
        context:addOption(Text.ui("Peek through the door"), playerNum, Peek.begin, object, kind)
    end
end

function Peek.begin(playerNum, object, kind)
    if not Peek.enabled() then
        Peek.metrics.refused = Peek.metrics.refused + 1
        return false
    end
    local player = Peek.playerOf(playerNum)
    local Lean = Peek.leanClass()
    if not Peek.usable(player) or Lean == nil or type(ISTimedActionQueue) ~= "table"
            or type(ISWalkToTimedAction) ~= "table" then return false end
    local found, geo = Peek.candidate(player, object, Peek.visitSaved(playerNum))
    if found == nil then
        Peek.metrics.refused = Peek.metrics.refused + 1
        Peek.say(player, Text.ui("You cannot peek through that"))
        return false
    end
    local near = geo.nearSquare
    if type(near.canStand) == "function" and near:canStand() ~= true then
        Peek.metrics.refused = Peek.metrics.refused + 1
        Peek.say(player, Text.ui("Something blocks the way to the door"))
        return false
    end
    ISTimedActionQueue.clear(player)
    local lean = Lean:new(player, object, geo, found, playerNum)
    if Peek.ask(player, "getCurrentSquare") ~= near then
        ISTimedActionQueue.addGetUpAndThen(player, ISWalkToTimedAction:new(player, near))
        ISTimedActionQueue.add(lean)
    else
        ISTimedActionQueue.addGetUpAndThen(player, lean)
    end
    return true
end

function Peek.leanValid(action)
    local player = action.character
    if not Peek.enabled() or not Peek.usable(player) then return false end
    if Peek.ask(action.door, "getObjectIndex") == -1 then return false end
    if action.kind == "door" and Peek.ask(action.door, "IsOpen") == true then return false end
    return true
end

function Peek.leanClass()
    if Peek.Lean ~= nil then return Peek.Lean end
    if type(ISBaseTimedAction) ~= "table" then return nil end
    local Lean = ISBaseTimedAction:derive("ALifePeekLean")

    function Lean:isValid()
        return Peek.leanValid(self)
    end

    function Lean:waitToStart()
        self.character:faceThisObject(self.door)
        return self.character:shouldBeTurning()
    end

    function Lean:update()
        self.character:faceThisObject(self.door)
        if Peek.nowMs() - (self.startMs or 0) >= self.leanMs then self:forceComplete() end
    end

    function Lean:start()
        self:setActionAnim("Loot")
        self:setAnimVariable("LootPosition", "")
        self.character:reportEvent("EventLootItem")
        self.startMs = Peek.nowMs()
    end

    function Lean:stop()
        ISBaseTimedAction.stop(self)
    end

    function Lean:perform()
        ISBaseTimedAction.perform(self)
        Peek.open(self.playerNum, self.door, self.geo, self.kind)
    end

    function Lean:new(character, door, geo, kind, playerNum)
        local o = ISBaseTimedAction.new(self, character)
        o.door, o.geo, o.kind, o.playerNum = door, geo, kind, playerNum
        o.maxTime = -1
        o.stopOnWalk = true
        o.stopOnRun = true
        o.leanMs = Data.leanMs
        if type(character.isTimedActionInstant) == "function" and character:isTimedActionInstant() == true then o.leanMs = 0 end
        return o
    end

    Peek.Lean = Lean
    return Lean
end

function Peek.openDoor(playerNum, door)
    local menu = ISWorldObjectContextMenu
    if type(menu) ~= "table" or type(menu.onOpenCloseDoor) ~= "function" then return false end
    menu.onOpenCloseDoor(nil, door, playerNum)
    return true
end

function Peek.who(playerNum, geo)
    local client = ProjectALife.SafehouseClient
    local saved = Peek.visitSaved(playerNum)
    if saved == nil or not Peek.sameEdge(geo, saved.door) or type(client.openDoor) ~= "function" then return false end
    return client.openDoor(playerNum, saved, "DOOR_WHO") ~= false
end

function Peek.nearbyDoor(player)
    local square = Peek.ask(player, "getCurrentSquare")
    if square == nil then return nil end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local fx, fy = 0, 0
    local forward = Peek.ask(player, "getForwardDirection")
    if forward ~= nil then fx, fy = forward:getX(), forward:getY() end
    local best, bestDot
    for index = 1, #Peek.steps do
        local step = Peek.steps[index]
        local other = Peek.squareAt(x + step[1], y + step[2], z)
        if other ~= nil then
            local door = Peek.ask(square, "getDoorTo", other)
            if door ~= nil and Peek.isDoorObject(door) then
                local dot = fx * step[1] + fy * step[2]
                if best == nil or dot > bestDot then best, bestDot = door, dot end
            end
        end
    end
    return best
end

function Peek.fromKey(playerNum)
    local window = Peek.windows[playerNum]
    if window ~= nil then
        window:close("key")
        return true
    end
    local player = Peek.playerOf(playerNum)
    if not Peek.usable(player) then return false end
    if not Peek.enabled() then
        Peek.say(player, Text.ui("Peeking through doors is switched off"))
        return false
    end
    local door = Peek.nearbyDoor(player)
    if door == nil then
        Peek.say(player, Text.ui("No door close enough to peek through"))
        return false
    end
    return Peek.begin(playerNum, door, "door")
end

function Peek.onKey(key)
    if key == nil or key == 0 or type(getCore) ~= "function" then return false end
    local core = getCore()
    if core == nil or type(core.isKey) ~= "function" or not core:isKey(Peek.keyName, key) then return false end
    return Peek.fromKey(0)
end

function Peek.registerKey()
    if type(keyBinding) ~= "table" or type(Keyboard) ~= "table" then return false end
    for _, bind in ipairs(keyBinding) do
        if bind.value == Peek.keyName then return true end
    end
    table.insert(keyBinding, { value = Peek.keyName, key = Keyboard.KEY_NONE })
    return true
end

function Peek.health(player)
    local value = Peek.ask(Peek.ask(player, "getBodyDamage"), "getOverallBodyHealth")
    return tonumber(value) or 100
end

function Peek.dataOf(object)
    if Peek.ask(object, "hasModData") == true then
        local data = Peek.ask(object, "getModData")
        if type(data) == "table" then return data end
    end
    return Peek.empty
end

function Peek.speech()
    local speech = ProjectALife.Speech
    if speech == nil or type(speech.alive) ~= "function" then return nil end
    return speech
end

function Peek.uidOf(object)
    local value = Peek.ask(object, "GetVariable", "ALifeUID")
    if type(value) == "string" and value ~= "" then return value end
    local data = Peek.dataOf(object)
    if data.ProjectALifeUID ~= nil then return tostring(data.ProjectALifeUID) end
    return nil
end

function Peek.relationOf(record, player)
    if type(record) ~= "table" then return nil end
    local relations = ProjectALife.Relations
    if relations ~= nil and type(relations.playerStance) == "function" then
        local ok, stance = pcall(relations.playerStance, record, player)
        if ok and type(stance) == "string" then return stance end
    end
    local catalog = ProjectALife.Catalog
    if catalog ~= nil and type(catalog.faction) == "function" then
        local ok, faction = pcall(catalog.faction, record.factionId)
        if ok and type(faction) == "table" and type(faction.relations) == "table" and type(faction.relations.player) == "string" then
            return faction.relations.player
        end
    end
    return nil
end

function Peek.holdName(object, data)
    local item = Peek.ask(object, "getPrimaryHandItem")
    if item ~= nil then
        local name = Peek.ask(item, "getDisplayName")
        if type(name) == "string" and name ~= "" then return name end
    end
    local itemType = data.ProjectALifeActiveWeaponType
    if data.ProjectALifeWeaponHeld == true and type(itemType) == "string" and itemType ~= "" and type(getItemNameFromFullType) == "function" then
        local ok, name = pcall(getItemNameFromFullType, itemType)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return nil
end

function Peek.describeNpc(window, fig, object)
    local menu = ProjectALife.TalkMenu
    local record = nil
    if menu ~= nil and type(menu.recordFor) == "function" then record = menu.recordFor(fig.uid) end
    fig.record = record
    if record ~= nil and type(menu.describe) == "function" then
        local _, name, faction, role, known = menu.describe(record, window.playerKey, fig.n)
        fig.name, fig.faction, fig.role, fig.known = name, faction, role, known
        fig.roleShown = known == true and menu.mystery ~= nil and menu.mystery() ~= true
    end
    local data = Peek.dataOf(object)
    local phase = tostring(data.ProjectALifeCombatPhase or "idle")
    local aim = data.ProjectALifeAimWalk == true or phase ~= "idle"
    local held = data.ProjectALifeWeaponHeld == true
    fig.stance = Data.stanceOf(Peek.relationOf(record, window.player),
        { danger = data.ProjectALifeDangerPosture, aim = aim, held = held })
    fig.raised = aim and (held or Peek.ask(object, "getPrimaryHandItem") ~= nil)
    if held or fig.raised then fig.hold = Peek.holdName(object, data) end
    fig.down = data.ProjectALifeDownedUntilMs ~= nil or data.ProjectALifeBleedOutAtMs ~= nil
    fig.bleeding = data.ProjectALifeBleedOutAtMs ~= nil
end

function Peek.describePlayer(window, fig, object)
    local name = Peek.ask(object, "getDisplayName")
    if type(name) ~= "string" or name == "" then name = Peek.ask(object, "getUsername") end
    if type(name) == "string" then fig.name = name end
    fig.known = true
    fig.stance = 1
    fig.raised = Peek.ask(object, "isAiming") == true
    local item = Peek.ask(object, "getPrimaryHandItem")
    if item ~= nil then
        local label = Peek.ask(item, "getDisplayName")
        if type(label) == "string" and label ~= "" then fig.hold = label end
    end
    local damage = Peek.ask(object, "getBodyDamage")
    local bleeding = tonumber(Peek.ask(damage, "getNumPartsBleeding")) or 0
    fig.bleeding = bleeding > 0
end

function Peek.classify(window, object)
    if type(instanceof) ~= "function" or object == window.player then return nil end
    local speech = Peek.speech()
    if instanceof(object, "IsoZombie") then
        if speech ~= nil and not speech.alive(object) then return nil end
        if Peek.ask(object, "isFakeDead") == true then return nil end
        local uid = Peek.uidOf(object)
        if uid ~= nil then return "npc", uid end
        return "zombie"
    end
    if instanceof(object, "IsoPlayer") then
        if Peek.ask(object, "isDead") == true or Peek.ask(object, "isGhostMode") == true then return nil end
        return "player"
    end
    if instanceof(object, "IsoAnimal") then
        if Peek.ask(object, "isDead") == true then return nil end
        return "animal"
    end
    if instanceof(object, "BaseVehicle") then return "vehicle" end
    return nil
end

function Peek.figureOf(window, object)
    local kind, uid = Peek.classify(window, object)
    if kind == nil then return nil end
    local x, y = Peek.ask(object, "getX"), Peek.ask(object, "getY")
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    local depth, lateral = Data.coords(window.geo, x, y)
    if not Data.inCone(depth, lateral, window.depth) then return nil end
    if window.live == true and ProjectALife.PeekScene.hidden(window, depth, lateral) then return nil end
    local entry = window.track[object]
    if entry == nil then
        window.nextId = window.nextId + 1
        entry = { id = window.nextId }
        window.track[object] = entry
    end
    entry.seen = window.scanNo
    local fig = { obj = object, kind = kind, uid = uid, depth = depth, lateral = lateral, entry = entry, id = entry.id, n = entry.id,
        dist = math.sqrt(depth * depth + lateral * lateral) }
    if kind == "npc" then
        Peek.describeNpc(window, fig, object)
    elseif kind == "player" then
        Peek.describePlayer(window, fig, object)
    elseif kind == "zombie" then
        fig.down = Peek.ask(object, "isCrawling") == true
    end
    return fig
end

function Peek.scan(window)
    local figs, seen, objects = {}, {}, 0
    local cells = window.cells
    local z = window.geo.z
    window.scanNo = window.scanNo + 1
    for index = 1, #cells do
        local spec = cells[index]
        local list = Peek.ask(Peek.squareAt(spec[1], spec[2], z), "getMovingObjects")
        if list ~= nil and type(list.size) == "function" then
            for slot = 0, list:size() - 1 do
                local object = list:get(slot)
                if object ~= nil and seen[object] == nil then
                    seen[object] = true
                    objects = objects + 1
                    local fig = Peek.figureOf(window, object)
                    if fig ~= nil then figs[#figs + 1] = fig end
                    if objects >= Data.maxObjects or #figs >= Data.maxFigures then return figs end
                end
            end
        end
    end
    return figs
end

function Peek.contact(window)
    local player = window.player
    local px, py = player:getX(), player:getY()
    local z = player:getZ()
    local speech = Peek.speech()
    local calm = Peek.calmOn()
    local limit = Data.contactRange * Data.contactRange
    for dx = -1, 1 do
        for dy = -1, 1 do
            local list = Peek.ask(Peek.squareAt(px + dx, py + dy, z), "getMovingObjects")
            if list ~= nil and type(list.size) == "function" then
                for slot = 0, list:size() - 1 do
                    local object = list:get(slot)
                    if object ~= nil and type(instanceof) == "function" and instanceof(object, "IsoZombie")
                            and (speech == nil or speech.alive(object)) then
                        local ox, oy = Peek.ask(object, "getX"), Peek.ask(object, "getY")
                        if type(ox) == "number" and type(oy) == "number" and (ox - px) ^ 2 + (oy - py) ^ 2 <= limit then
                            if Peek.uidOf(object) == nil or not calm then return true end
                        end
                    end
                end
            end
        end
    end
    return false
end

function Peek.state(window)
    local player = window.player
    local state = {}
    if not Peek.usable(player) then
        state.gone = true
        return state
    end
    state.moved = Data.span(player:getX(), player:getY(), window.startX, window.startY)
    state.floor = math.floor(player:getZ() + 0.5)
    state.startFloor = window.startFloor
    state.damage = window.startHealth - Peek.health(player)
    local door = window.door
    if Peek.ask(door, "getObjectIndex") == -1 then state.doorGone = true end
    if window.kind == "door" and Peek.ask(door, "IsOpen") == true then state.doorOpen = true end
    if Peek.blocked(door) then state.doorGone = true end
    if not Peek.enabled() then state.gone = true end
    state.contact = Peek.contact(window)
    return state
end

function Peek.exterior(manager)
    local color = Peek.ask(Peek.ask(manager, "getGlobalLight"), "getExterior")
    local r, g, b = Peek.ask(color, "getRedFloat"), Peek.ask(color, "getGreenFloat"), Peek.ask(color, "getBlueFloat")
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    return nil, nil, nil
end

function Peek.climate()
    if type(getClimateManager) ~= "function" then return Data.weather(nil, nil, nil, nil) end
    local manager = getClimateManager()
    local light, overcast, rain = Data.weather(Peek.ask(manager, "getDayLightStrength"), Peek.ask(manager, "getCloudIntensity"),
        Peek.ask(manager, "getRainIntensity"), Peek.ask(manager, "getFogIntensity"))
    local r, g, b = Peek.exterior(manager)
    return light, overcast, rain, r, g, b
end

function Peek.floorKinds(window)
    local geo = window.geo
    local kinds = {}
    for k = 0, Data.maxDepth - 1 do
        local square = Peek.squareAt(geo.farX + k * geo.ox, geo.farY + k * geo.oy, geo.z)
        local floor = Peek.ask(square, "getFloor")
        kinds[k + 1] = Data.floorKind(Peek.ask(floor, "getTextureName"))
    end
    return kinds
end

function Peek.measure(text)
    if type(getTextManager) ~= "function" then return #text * 6 end
    return getTextManager():MeasureStringX(UIFont.Small, text)
end

function Peek.decorate(window, fig)
    local label = Data.labelFor(fig, window.reveal)
    local lines = label.lines
    if #lines > 0 then
        lines[1].text = lines[1].text .. " - " .. Data.distanceText(fig.dist)
    end
    local widest = 0
    for index = 1, #lines do
        lines[index].w = Peek.measure(lines[index].text)
        if lines[index].w > widest then widest = lines[index].w end
    end
    label.w = widest
    fig.label = label
end

function Peek.place(window, fig)
    local view = window.view
    local t
    if window.live == true or window.lens == true then
        t = Data.projectLive(fig.depth, fig.lateral, view)
    else
        t = Data.project(fig.depth, fig.lateral, view)
    end
    if fig.down == true and Data.isHuman(fig.kind) then
        t.w, t.h = t.h * 0.9, t.h * 0.22
    end
    local x = Data.fitX(view, t.x, t.feet, t.w, t.h)
    local entry = fig.entry
    entry.tx, entry.ty, entry.tw, entry.th = x, t.feet, t.w, t.h
    if entry.x == nil then entry.x, entry.y, entry.w, entry.h = x, t.feet, t.w, t.h end
end

function Peek.overlap(a, b)
    return math.abs(a.x - b.x) * 2 < a.w + b.w and math.abs((a.y - a.h / 2) - (b.y - b.h / 2)) * 2 < a.h + b.h
end

function Peek.layers(figs)
    for index = 1, #figs do
        local fig = figs[index]
        fig.layer = "bottom"
        if fig.slot == nil then
            for other = 1, #figs do
                local model = figs[other]
                if model.slot ~= nil and model.depth > fig.depth and Peek.overlap(fig.entry, model.entry) then
                    fig.layer = "top"
                    break
                end
            end
        end
    end
end

function Peek.modelPrerender(model)
    if model.javaObject ~= nil then model.javaObject:setAnimate(false) end
end

function Peek.noMouse()
    return false
end

function Peek.newModel(window)
    local panel = ISUI3DModel:new(0, 0, 40, 80)
    panel:initialise()
    window:addChild(panel)
    panel:setIsometric(false)
    panel:setDirection(IsoDirections.S)
    panel:setDoRandomExtAnimations(false)
    panel:setState("idle")
    panel:setZoom(Data.modelZoom)
    panel:setYOffset(Data.modelYOffset)
    panel.prerender = Peek.modelPrerender
    panel.onMouseDown, panel.onMouseUp, panel.onMouseMove = Peek.noMouse, Peek.noMouse, Peek.noMouse
    panel.onMouseMoveOutside, panel.onMouseUpOutside = Peek.noMouse, Peek.noMouse
    return panel
end

function Peek.bindSlot(window, slot, shell)
    if slot.panel == nil then
        local ok, panel = pcall(Peek.newModel, window)
        if not ok or panel == nil then
            window.no3d = true
            Peek.metrics.faults = Peek.metrics.faults + 1
            Peek.log("models off: " .. string.sub(tostring(panel), 1, 120))
            return false
        end
        slot.panel = panel
    end
    local ok = pcall(slot.panel.setCharacter, slot.panel, shell)
    if not ok then
        window.no3d = true
        Peek.metrics.faults = Peek.metrics.faults + 1
        return false
    end
    slot.obj = shell
    slot.panel:setVisible(true)
    return true
end

function Peek.slotFar(a, b)
    if a.depth ~= b.depth then return a.depth > b.depth end
    return a.n < b.n
end

function Peek.assignModels(window, figs)
    local slots = window.slots
    local want = {}
    if window.no3d ~= true then
        local humans = {}
        for index = 1, #figs do
            local fig = figs[index]
            if Data.modelKinds[fig.kind] == true and fig.down ~= true and fig.depth <= Data.modelRange then humans[#humans + 1] = fig end
        end
        table.sort(humans, Data.modelFirst)
        for index = 1, math.min(#humans, Data.maxModels) do want[#want + 1] = humans[index] end
    end
    for index = 1, #slots do
        slots[index].keep = false
        slots[index].depth = -1
    end
    local pending = {}
    for index = 1, #want do
        local fig = want[index]
        local found = nil
        for s = 1, #slots do
            if slots[s].obj == fig.obj and slots[s].panel ~= nil and not slots[s].keep then found = slots[s]; break end
        end
        if found ~= nil then
            found.keep, found.depth = true, fig.depth
            fig.slot = found
        else
            pending[#pending + 1] = fig
        end
    end
    for index = 1, #pending do
        local fig = pending[index]
        local free = nil
        for s = 1, #slots do
            if not slots[s].keep then free = slots[s]; break end
        end
        if free == nil and #slots < Data.maxModels then
            free = { n = #slots + 1, keep = false, depth = -1 }
            slots[#slots + 1] = free
        end
        if free ~= nil and window.no3d ~= true and Peek.bindSlot(window, free, fig.obj) then
            free.keep, free.depth = true, fig.depth
            fig.slot = free
        end
    end
    local shown = 0
    for index = 1, #slots do
        local slot = slots[index]
        if slot.keep then
            shown = shown + 1
        elseif slot.panel ~= nil and slot.obj ~= nil then
            slot.panel:setVisible(false)
            slot.obj = nil
        end
    end
    Peek.orderModels(window)
    return shown
end

function Peek.orderModels(window)
    local list = {}
    for index = 1, #window.slots do
        if window.slots[index].panel ~= nil then list[#list + 1] = window.slots[index] end
    end
    table.sort(list, Peek.slotFar)
    local changed = #list ~= #window.order
    if not changed then
        for index = 1, #list do
            if list[index] ~= window.order[index] then changed = true; break end
        end
    end
    if not changed then return end
    for index = 1, #list do window:removeChild(list[index].panel) end
    for index = 1, #list do window:addChild(list[index].panel) end
    window.order = list
end

function Peek.noticeRoll(window)
    local percent = Peek.noticePercent()
    if percent <= 0 then return false end
    local best = nil
    for index = 1, #window.figs do
        local fig = window.figs[index]
        if fig.kind == "npc" and fig.depth <= Data.noticeRange and (best == nil or fig.depth < best.depth) then best = fig end
    end
    if best == nil then return false end
    local roll = 100
    if type(ZombRand) == "function" then roll = ZombRand(100) end
    if not Data.noticeNeeded(percent, roll) then return false end
    local speech = ProjectALife.Speech
    if speech == nil or type(speech.bark) ~= "function" or best.record == nil then return false end
    local ok, line = pcall(speech.bark, best.record, best.obj, "CONTACT_PLAYER", { player = window.player })
    Peek.metrics.notices = Peek.metrics.notices + 1
    Peek.log("notice uid=" .. tostring(best.uid) .. " spoke=" .. tostring(ok and line ~= nil))
    return ok and line ~= nil
end

function Peek.refresh(window)
    local now = Peek.nowMs()
    local reason = Data.closeReason(Peek.state(window))
    if reason ~= nil then
        window:close(reason)
        return false
    end
    local figs = Peek.scan(window)
    local stale = {}
    for object, entry in pairs(window.track) do
        if entry.seen ~= window.scanNo then stale[#stale + 1] = object end
    end
    for index = 1, #stale do window.track[stale[index]] = nil end
    for index = 1, #figs do
        Peek.decorate(window, figs[index])
        Peek.place(window, figs[index])
    end
    Data.sortFigures(figs)
    window.models = Peek.assignModels(window, figs)
    Peek.layers(figs)
    window.figs = figs
    window.counts = Data.counts(figs)
    window.status = Data.statusLines(window.counts)
    for index = 1, #window.status do window.status[index].w = Peek.measure(window.status[index].text) end
    window.light, window.overcast, window.rain, window.ar, window.ag, window.ab = Peek.climate()
    if window.lens == true then
        Lens.setGrade(window)
        Lens.watch(window, figs, now)
    end
    if window.live == true then ProjectALife.PeekScene.layers(window, figs) end
    if window.counts.people > window.peak then window.peak = window.counts.people end
    Peek.metrics.scans = Peek.metrics.scans + 1
    if now >= window.nextNotice then
        window.nextNotice = now + Data.noticeGapMs
        Peek.noticeRoll(window)
    end
    return true
end

function Peek.animate(window)
    local figs = window.figs
    local s = Data.smooth
    for index = 1, #figs do
        local fig = figs[index]
        local e = fig.entry
        e.x = e.x + (e.tx - e.x) * s
        e.y = e.y + (e.ty - e.y) * s
        e.w = e.w + (e.tw - e.w) * s
        e.h = e.h + (e.th - e.h) * s
        local slot = fig.slot
        if slot ~= nil and slot.panel ~= nil then
            local panel = slot.panel
            panel:setX(math.floor(e.x - e.w / 2))
            panel:setY(math.floor(e.y - e.h))
            panel:setWidth(math.max(8, math.floor(e.w)))
            panel:setHeight(math.max(16, math.floor(e.h)))
        end
    end
end

function Peek.tick(window)
    local now = Peek.nowMs()
    if now >= window.nextScan then
        window.nextScan = now + Data.refreshMs
        if not Peek.refresh(window) then return end
    end
    if window.live == true then
        local ok, err = pcall(ProjectALife.PeekScene.tick, window, now)
        if not ok then Peek.fallBack(window, err) end
    end
    Peek.animate(window)
end

function Peek.open(playerNum, door, geo, kind)
    if Peek.Window == nil or not Peek.enabled() then return nil end
    local player = Peek.playerOf(playerNum)
    if not Peek.usable(player) then return nil end
    local previous = Peek.windows[playerNum]
    if previous ~= nil then previous:close("replaced") end
    local lens = Peek.lensOn()
    local full = lens and Peek.fullOn()
    local left, top, screenW, screenH = Peek.screenOf(playerNum)
    local fontH = 14
    if type(getTextManager) == "function" then fontH = getTextManager():getFontHeight(UIFont.Small) end
    local barH = math.max(30, fontH + 16)
    local window, width, height
    if full then
        window = Peek.Window:new(math.floor(left), math.floor(top), math.floor(screenW), math.floor(screenH))
        window.full = true
        window:setWantMouseEvents(true)
        if type(window.setForceCursorVisible) == "function" then window:setForceCursorVisible(true) end
    else
        width, height = Peek.windowedSize(lens, screenW, screenH, barH)
        window = Peek.Window:new(math.floor(left + (screenW - width) / 2), math.floor(top + (screenH - height - barH) / 2),
            width, height + barH)
    end
    window.playerNum, window.player, window.door, window.geo, window.kind = playerNum, player, door, geo, kind
    window.barH = barH
    if full then
        window.view = Lens.fullView(window.width, window.height, fontH, barH)
    else
        window.view = Data.view(width, height)
    end
    if lens then
        window.lens = true
        if not full then window.view = Lens.view(width, height) end
        window.grade = Lens.newGrade()
        window.lt = Lens.bind()
        Lens.attach(window)
    end
    window.live = Peek.liveOn()
    window.depth = Data.maxDepth
    if window.live then window.depth = Data.liveDepth end
    window.cells = Data.cells(geo, window.depth)
    window.kinds = Peek.floorKinds(window)
    window.indoor = Peek.inside(geo.farSquare)
    if full then
        window.maskRows = Lens.fullRows(window.view)
    else
        window.maskRows = Data.maskRows(window.view)
    end
    window.track, window.figs, window.slots, window.order, window.status = {}, {}, {}, {}, {}
    window.counts = Data.counts(window.figs)
    window.nextId, window.scanNo, window.peak, window.models = 0, 0, 0, 0
    window.light, window.overcast, window.rain, window.ar, window.ag, window.ab = Peek.climate()
    if lens then Lens.setGrade(window) end
    if window.live then
        local made, built = pcall(ProjectALife.PeekScene.open, window)
        if made then made, built = pcall(ProjectALife.PeekScene.build, window, Peek.nowMs()) end
        if not made then Peek.fallBack(window, built) end
    end
    window.startX, window.startY, window.startFloor = player:getX(), player:getY(), math.floor(player:getZ() + 0.5)
    window.startHealth = Peek.health(player)
    window.openedAt = Peek.nowMs()
    window.nextScan, window.nextNotice = window.openedAt + Data.refreshMs, window.openedAt
    local visit = Peek.visitSaved(playerNum)
    window.hasWho = visit ~= nil and Peek.sameEdge(geo, visit.door)
    window.reveal = Peek.revealOn(player)
    local speech = ProjectALife.Speech
    window.playerKey = speech ~= nil and type(speech.playerKey) == "function" and speech.playerKey(player) or nil
    window:setWantKeyEvents(true)
    window:initialise()
    window:addToUIManager()
    if full then
        if type(window.setAlwaysOnTop) == "function" then window:setAlwaysOnTop(true) end
        if type(window.bringToTop) == "function" then window:bringToTop() end
    end
    if lens then window.escDown = Peek.escDown() end
    Peek.windows[playerNum] = window
    Peek.syncKeys()
    Peek.metrics.opens = Peek.metrics.opens + 1
    local ok, err = pcall(Peek.refresh, window)
    if not ok then
        window.failed = tostring(err)
        Peek.metrics.faults = Peek.metrics.faults + 1
        window:close("failed")
        return nil
    end
    if window.closed then return nil end
    local counts = window.counts
    Peek.log("open kind=" .. kind .. " at=" .. geo.x .. "," .. geo.y .. "," .. geo.z .. " out=" .. geo.ox .. "," .. geo.oy
        .. " people=" .. counts.people .. " zombies=" .. counts.zombies .. " animals=" .. counts.animals
        .. " vehicles=" .. counts.vehicles .. " models=" .. window.models .. " cells=" .. #window.cells
        .. " live=" .. tostring(window.live) .. Peek.sceneLine(window) .. " lens=" .. tostring(window.lens == true)
        .. " full=" .. tostring(window.full == true))
    return window
end

function Peek.windowize(window)
    local left, top, screenW, screenH = Peek.screenOf(window.playerNum)
    local width, height = Peek.windowedSize(true, screenW, screenH, window.barH)
    window:setX(math.floor(left + (screenW - width) / 2))
    window:setY(math.floor(top + (screenH - height - window.barH) / 2))
    window:setWidth(width)
    window:setHeight(height + window.barH)
    window.view = Lens.view(width, height)
    window.maskRows = Data.maskRows(window.view)
    window.drops = nil
    window.figs = {}
    window.track = {}
    window.nextScan = 0
    window:setWantMouseEvents(false)
    window:layoutButtons()
    if window.live == true then
        local made, built = pcall(ProjectALife.PeekScene.open, window)
        if made then made, built = pcall(ProjectALife.PeekScene.build, window, Peek.nowMs()) end
        if not made then Peek.fallBack(window, built) end
    end
end

function Peek.fullFault(window, err)
    if window.full ~= true then return false end
    window.full = false
    Peek.metrics.fullFaults = Peek.metrics.fullFaults + 1
    Peek.log("full screen off: " .. string.sub(tostring(err), 1, 120))
    local ok, why = pcall(Peek.windowize, window)
    if not ok then
        Peek.lensFault(window, why)
        return false
    end
    return true
end

function Peek.sceneLine(window)
    local scene = window.scene
    if window.live ~= true or scene == nil then return "" end
    local metrics = ProjectALife.PeekScene.metrics
    return " sprites=" .. scene.used .. " hidden=" .. (scene.hidden or 0) .. " unloaded=" .. metrics.unloaded
        .. " noTexture=" .. metrics.missing
end

function Peek.finish(window)
    window.fadeAt = nil
    for index = #Peek.fading, 1, -1 do
        if Peek.fading[index] == window then table.remove(Peek.fading, index) end
    end
    window:setVisible(false)
    window:removeFromUIManager()
    Peek.syncKeys()
end

function Peek.reset()
    for playerNum = 0, 3 do
        local window = Peek.windows[playerNum]
        if window ~= nil then pcall(window.close, window, "reset") end
        Peek.windows[playerNum] = nil
    end
    for index = #Peek.fading, 1, -1 do
        local window = table.remove(Peek.fading, index)
        if window.fadeAt ~= nil then pcall(Peek.finish, window) end
    end
end

function Peek.figureColor(window, fig)
    local fog = Data.clamp(fig.depth / 12, 0, 0.6)
    local hr, hg, hb = Data.skyColor(1, window.light, window.overcast)
    local r, g, b = 0.12, 0.12, 0.14
    if fig.kind == "zombie" then
        r, g, b = 0.08, 0.11, 0.08
    elseif fig.kind == "animal" then
        r, g, b = 0.16, 0.11, 0.07
    elseif fig.kind == "vehicle" then
        r, g, b = 0.16, 0.18, 0.22
    end
    local shade = 0.4 + 0.6 * window.light
    return Data.lerp(r * shade, hr, fog), Data.lerp(g * shade, hg, fog), Data.lerp(b * shade, hb, fog)
end

function Peek.drawHuman(window, fig, r, g, b)
    local e = fig.entry
    local h = e.h
    local cx, top = e.x, e.y - e.h
    if fig.down == true and Data.isHuman(fig.kind) then
        window:drawRect(math.floor(cx - e.w / 2), math.floor(e.y - e.h), math.floor(e.w), math.max(2, math.floor(e.h)), 1, r, g, b)
        return
    end
    local hs = math.max(2, math.floor(h * 0.13))
    local lean = 0
    if fig.kind == "zombie" then lean = math.floor(h * 0.03) end
    window:drawRect(math.floor(cx - hs / 2) + lean, math.floor(top), hs, math.max(2, math.floor(hs * 1.2)), 1, r, g, b)
    local tw = math.max(3, math.floor(h * 0.26))
    local ty = math.floor(top + hs * 1.3)
    local th = math.max(3, math.floor(h * 0.34))
    window:drawRect(math.floor(cx - tw / 2), ty, tw, th, 1, r, g, b)
    local aw = math.max(1, math.floor(h * 0.07))
    local armLen = math.max(2, math.floor(h * 0.30))
    if fig.kind == "zombie" then
        window:drawRect(math.floor(cx - tw / 2 - aw), ty, aw, math.floor(armLen * 0.5), 1, r, g, b)
        window:drawRect(math.floor(cx + tw / 2), ty, aw, math.floor(armLen * 0.5), 1, r, g, b)
        window:drawRect(math.floor(cx - tw / 2 - aw), ty, aw * 3, aw, 1, r, g, b)
        window:drawRect(math.floor(cx + tw / 2 - aw * 2), ty, aw * 3, aw, 1, r, g, b)
    else
        window:drawRect(math.floor(cx - tw / 2 - aw), ty, aw, armLen, 1, r, g, b)
        window:drawRect(math.floor(cx + tw / 2), ty, aw, armLen, 1, r, g, b)
    end
    local lw = math.max(2, math.floor(h * 0.11))
    local ly = ty + th
    local ll = math.max(2, math.floor(e.y - ly))
    window:drawRect(math.floor(cx - lw - 1), ly, lw, ll, 1, r, g, b)
    window:drawRect(math.floor(cx + 1), ly, lw, ll, 1, r, g, b)
    if fig.kind == "zombie" and h > 40 then
        local eye = math.max(1, math.floor(hs * 0.2))
        window:drawRect(math.floor(cx - hs / 4) + lean, math.floor(top + hs * 0.4), eye, eye, 1, 0.75, 0.12, 0.10)
        window:drawRect(math.floor(cx + hs / 4) + lean - eye, math.floor(top + hs * 0.4), eye, eye, 1, 0.75, 0.12, 0.10)
    end
end

function Peek.drawAnimal(window, fig, r, g, b)
    local e = fig.entry
    local h = e.h * 0.45
    local w = e.h * 0.8
    local top = e.y - h
    window:drawRect(math.floor(e.x - w / 2), math.floor(top), math.floor(w), math.max(2, math.floor(h * 0.6)), 1, r, g, b)
    window:drawRect(math.floor(e.x + w / 2 - w * 0.2), math.floor(top - h * 0.25), math.max(2, math.floor(w * 0.22)),
        math.max(2, math.floor(h * 0.5)), 1, r, g, b)
    local lw = math.max(1, math.floor(w * 0.08))
    window:drawRect(math.floor(e.x - w / 2), math.floor(top + h * 0.6), lw, math.max(1, math.floor(h * 0.4)), 1, r, g, b)
    window:drawRect(math.floor(e.x + w / 2 - lw), math.floor(top + h * 0.6), lw, math.max(1, math.floor(h * 0.4)), 1, r, g, b)
end

function Peek.drawVehicle(window, fig, r, g, b)
    local e = fig.entry
    local w = e.h * 1.6
    local h = e.h * 0.7
    local top = e.y - h
    window:drawRect(math.floor(e.x - w / 2), math.floor(top), math.floor(w), math.floor(h * 0.7), 1, r, g, b)
    window:drawRect(math.floor(e.x - w * 0.3), math.floor(top - h * 0.3), math.floor(w * 0.6), math.floor(h * 0.4), 1, r * 0.8, g * 0.8, b * 0.9)
    local ww = math.max(2, math.floor(w * 0.14))
    window:drawRect(math.floor(e.x - w / 2), math.floor(e.y - h * 0.3), ww, math.max(2, math.floor(h * 0.3)), 1, 0.02, 0.02, 0.02)
    window:drawRect(math.floor(e.x + w / 2 - ww), math.floor(e.y - h * 0.3), ww, math.max(2, math.floor(h * 0.3)), 1, 0.02, 0.02, 0.02)
end

function Peek.drawFigure(window, fig)
    if window.lens == true then return Lens.figure(window, fig) end
    local r, g, b = Peek.figureColor(window, fig)
    if fig.kind == "animal" then
        Peek.drawAnimal(window, fig, r, g, b)
    elseif fig.kind == "vehicle" then
        Peek.drawVehicle(window, fig, r, g, b)
    else
        Peek.drawHuman(window, fig, r, g, b)
    end
end

function Peek.drawSky(window)
    local view = window.view
    local bands = 10
    local horizon = math.floor(view.horizon)
    for index = 1, bands do
        local y0 = math.floor(horizon * (index - 1) / bands)
        local y1 = math.floor(horizon * index / bands)
        local t = (index - 0.5) / bands
        local r, g, b
        if window.indoor then
            r, g, b = Data.wallColor(t, 0.7)
        else
            r, g, b = Data.skyColor(t, window.light, window.overcast)
        end
        window:drawRect(0, y0, view.w, y1 - y0 + 1, 1, r, g, b)
    end
end

function Peek.drawGround(window)
    local view = window.view
    local horizon = math.floor(view.horizon)
    local far = math.floor(Data.groundY(Data.maxDepth, view))
    local r, g, b = Data.groundColor(window.kinds[Data.maxDepth] or "paved", Data.maxDepth, window.light, window.overcast)
    window:drawRect(0, horizon, view.w, math.max(1, far - horizon) + 1, 1, r, g, b)
    for k = Data.maxDepth - 1, 0, -1 do
        local top = math.max(Data.groundY(k + 1, view), view.horizon)
        local bottom = math.min(Data.groundY(k, view), view.h)
        if bottom > top then
            r, g, b = Data.groundColor(window.kinds[k + 1] or "paved", k + 0.5, window.light, window.overcast)
            window:drawRect(0, math.floor(top), view.w, math.ceil(bottom - top) + 1, 1, r, g, b)
        end
    end
end

function Peek.drawScene(window, front)
    local view = window.view
    if window.lens == true then
        window:setStencilRect(view.sx, view.sy, view.sw, view.sh)
    else
        window:setStencilRect(0, 0, view.w, view.h)
    end
    local ok, drawn = pcall(ProjectALife.PeekScene.draw, window, front)
    window:clearStencilRect()
    if ok and drawn == true then return true end
    Peek.fallBack(window, ok and "no_scene" or drawn)
    return false
end

function Peek.drawRain(window)
    local view = window.view
    window:setStencilRect(0, 0, view.w, view.h)
    local ok, err = pcall(ProjectALife.PeekScene.rain, window, Peek.nowMs())
    window:clearStencilRect()
    if not ok then Peek.fallBack(window, err) end
end

function Peek.drawBack(window)
    if window.lens == true then
        local ok, err = pcall(Lens.back, window)
        if ok then return end
        if Peek.fullFault(window, err) then
            ok, err = pcall(Lens.back, window)
            if ok then return end
        end
        Peek.lensFault(window, err)
    end
    window:drawRect(0, 0, window.width, window.height, 1, 0.015, 0.015, 0.015)
    Peek.drawSky(window)
    if window.live == true and Peek.drawScene(window, false) then return end
    Peek.drawGround(window)
    local figs = window.figs
    for index = 1, #figs do
        local fig = figs[index]
        if fig.slot == nil and fig.layer ~= "top" then Peek.drawFigure(window, fig) end
    end
end

function Peek.drawLabel(window, fig)
    local label = fig.label
    if label == nil or #label.lines == 0 then return end
    local fh = window.fontH
    local count = #label.lines
    local plateW = label.w + 10
    local plateH = count * fh + 4
    local px, py = Data.labelBox(window.view, fig.entry, plateW, plateH)
    px, py = math.floor(px), math.floor(py)
    window:drawRect(px, py, plateW, plateH, 0.62, 0.02, 0.02, 0.02)
    for index = 1, count do
        local line = label.lines[index]
        local r, g, b = Data.tone(line.tone)
        window:drawTextCentre(line.text, px + plateW / 2, py + 2 + (index - 1) * fh, r, g, b, 1, UIFont.Small)
    end
end

function Peek.drawMarks(window, fig)
    local e = fig.entry
    if fig.bleeding == true and Data.isHuman(fig.kind) then
        window:drawRectBorder(math.floor(e.x - e.w / 2 - 2), math.floor(e.y - e.h - 2), math.floor(e.w) + 4, math.floor(e.h) + 4,
            0.85, 0.9, 0.15, 0.15)
    end
    if fig.raised == true and (fig.label == nil or #fig.label.lines == 0) then
        window:drawRect(math.floor(e.x - 4), math.floor(e.y - e.h - 7), 8, 3, 1, 1.0, 0.62, 0.25)
    end
end

function Peek.drawVignette(window)
    local view = window.view
    local rows = window.maskRows
    for index = 1, #rows do
        local row = rows[index]
        local y, step, left, right = row[1], row[2], row[3], row[4]
        if left > 0 then window:drawRect(0, y, left, step, 1, 0.012, 0.012, 0.014) end
        if right < view.w then window:drawRect(right, y, view.w - right, step, 1, 0.012, 0.012, 0.014) end
        if row[5] then
            window:drawRect(left, y, 9, step, 0.42, 0.012, 0.012, 0.014)
            window:drawRect(right - 9, y, 9, step, 0.42, 0.012, 0.012, 0.014)
        end
    end
end

function Peek.drawFront(window)
    if window.lens == true then
        local ok, err = pcall(Lens.front, window)
        if ok then return end
        if Peek.fullFault(window, err) then
            ok, err = pcall(Lens.front, window)
            if ok then return end
        end
        Peek.lensFault(window, err)
    end
    local figs = window.figs
    local view = window.view
    local night = Data.nightAlpha(window.light)
    if window.live == true and Peek.drawScene(window, true) then
        night = night * 0.5
        Peek.drawRain(window)
    else
        for index = 1, #figs do
            local fig = figs[index]
            if fig.slot == nil and fig.layer == "top" then Peek.drawFigure(window, fig) end
        end
    end
    if night > 0.01 then window:drawRect(0, 0, view.w, view.h, night, 0, 0, 0.03) end
    Peek.drawVignette(window)
    for index = 1, #figs do
        Peek.drawMarks(window, figs[index])
        Peek.drawLabel(window, figs[index])
    end
    local y = 8
    for index = 1, #window.status do
        local line = window.status[index]
        local r, g, b = Data.tone(line.tone)
        window:drawText(line.text, 12, y, r, g, b, 1, UIFont.Small)
        y = y + window.fontH + 2
    end
    window:drawTextRight(window.s.hint, view.w - 12, view.h - window.fontH - 8, 0.62, 0.66, 0.60, 1, UIFont.Small)
    window:drawRectBorder(0, 0, window.width, window.height, 1, 0.42, 0.37, 0.27)
    window:drawRect(0, view.h, window.width, 1, 1, 0.42, 0.37, 0.27)
end

if type(ISPanel) == "table" then
    local Window = ISPanel:derive("ALifePeekWindow")
    Peek.Window = Window

    function Window:new(x, y, width, height)
        local o = ISPanel.new(self, x, y, width, height)
        o.backgroundColor = { r = 0.015, g = 0.015, b = 0.015, a = 1 }
        o.borderColor = { r = 0.42, g = 0.37, b = 0.27, a = 1 }
        o.moveWithMouse = false
        return o
    end

    function Window:createChildren()
        self.fontH = 14
        if type(getTextManager) == "function" then self.fontH = getTextManager():getFontHeight(UIFont.Small) end
        self.s = { hint = Text.ui("Esc: back away") }
        local list = {}
        if self.kind == "door" then list[#list + 1] = { "open", Text.ui("Open the door") } end
        if self.hasWho then list[#list + 1] = { "who", Text.ui("Who is it?") } end
        list[#list + 1] = { "back", Text.ui("Back away") }
        self.buttons = {}
        for index = 1, #list do
            local bx, by, bw, bh = self:buttonRect(index, #list)
            local button = ISButton:new(bx, by, bw, bh, list[index][2], self, Window.onButton)
            button.action = list[index][1]
            if self.lens == true then
                button.backgroundColor = { r = 0.03, g = 0.04, b = 0.04, a = 0.92 }
                button.backgroundColorMouseOver = { r = 0.10, g = 0.12, b = 0.11, a = 0.95 }
                button.borderColor = { r = 0.30, g = 0.32, b = 0.30, a = 0.9 }
                button.textColor = { r = 0.80, g = 0.82, b = 0.78, a = 1 }
            end
            button:initialise()
            button:instantiate()
            self:addChild(button)
            self.buttons[index] = button
        end
    end

    function Window:buttonRect(index, count)
        local view = self.view
        if self.full == true then
            local gap = math.max(8, view.pad)
            local each = Data.clamp(math.floor((self.width - 2 * view.pad - gap * (count - 1)) / count), 40, Lens.fullButtonW)
            local total = each * count + gap * (count - 1)
            return math.floor((self.width - total) / 2) + (index - 1) * (each + gap), view.btnY, each, view.btnH
        end
        local gap = 8
        local each = math.floor((self.width - gap * (count + 1)) / count)
        return gap + (index - 1) * (each + gap), view.h + 6, each, self.barH - 12
    end

    function Window:layoutButtons()
        local count = #self.buttons
        for index = 1, count do
            local button = self.buttons[index]
            local bx, by, bw, bh = self:buttonRect(index, count)
            button:setX(bx)
            button:setY(by)
            button:setWidth(bw)
            button:setHeight(bh)
        end
    end

    function Window.onButton(window, button)
        local action = button.action
        if action == "open" then
            window:close("open")
            Peek.openDoor(window.playerNum, window.door)
        elseif action == "who" then
            window:close("who")
            Peek.who(window.playerNum, window.geo)
        else
            window:close("back")
        end
    end

    function Window:prerender()
        if self.failed ~= nil or (self.closed and self.fadeAt == nil) then return end
        local ok, err = pcall(Peek.drawBack, self)
        if not ok then self.failed = tostring(err) end
    end

    function Window:render()
        if self.failed ~= nil or (self.closed and self.fadeAt == nil) then return end
        local ok, err = pcall(Peek.drawFront, self)
        if not ok then self.failed = tostring(err) end
    end

    function Window:update()
        ISPanel.update(self)
        if self.closed then
            if self.fadeAt ~= nil and Peek.nowMs() - self.fadeAt >= Lens.closeMs then
                Peek.finish(self)
            elseif Peek.keysDirty then
                Peek.syncKeys()
            end
            return
        end
        if self.lens == true then
            local down = Peek.escDown()
            if down and not self.escDown then
                self.escDown = down
                self:close("esc")
                return
            end
            self.escDown = down
        end
        if self.failed ~= nil then
            Peek.metrics.faults = Peek.metrics.faults + 1
            self:close("failed")
            return
        end
        local ok, err = pcall(Peek.tick, self)
        if not ok then
            self.failed = tostring(err)
            Peek.metrics.faults = Peek.metrics.faults + 1
            Peek.log("fault " .. string.sub(self.failed, 1, 160))
            self:close("failed")
        end
    end

    function Window:isKeyConsumed(key)
        return (not self.closed or self.fadeAt ~= nil) and type(Keyboard) == "table" and key == Keyboard.KEY_ESCAPE and self:isVisible()
    end

    function Window:onKeyPress(key)
        if self.lens == true and not self.closed and type(Keyboard) == "table" and key == Keyboard.KEY_ESCAPE then self:close("esc") end
    end

    function Window:onMouseDown(x, y)
        if self.closed then return false end
        if self.full == true then return true end
        return ISPanel.onMouseDown(self, x, y)
    end

    function Window:onMouseUp(x, y)
        if self.closed then return false end
        if self.full == true then return true end
        return ISPanel.onMouseUp(self, x, y)
    end

    function Window:onMouseMove(dx, dy)
        if self.closed then return false end
        if self.full == true then return true end
        return ISPanel.onMouseMove(self, dx, dy)
    end

    function Window:onMouseWheel(del)
        if self.closed then return false end
        if self.full == true then return true end
        return ISPanel.onMouseWheel(self, del)
    end

    function Window:onRightMouseDown(x, y)
        if self.closed then return false end
        if self.lens == true then return true end
        return ISPanel.onRightMouseDown(self, x, y)
    end

    function Window:onRightMouseUp(x, y)
        if self.closed then return false end
        if self.lens ~= true then return ISPanel.onRightMouseUp(self, x, y) end
        if not self.closed then self:close("back") end
        return true
    end

    function Window:onKeyRelease(key)
        if not self.closed and type(Keyboard) == "table" and key == Keyboard.KEY_ESCAPE then self:close("esc") end
    end

    function Window:close(reason)
        if self.closed then return end
        self.closed = true
        if Peek.windows[self.playerNum] == self then Peek.windows[self.playerNum] = nil end
        if type(self.setWantMouseEvents) == "function" then self:setWantMouseEvents(false) end
        if self.full == true and type(self.setForceCursorVisible) == "function" then self:setForceCursorVisible(false) end
        if self.lens == true and self.failed == nil and Lens.softClose(reason) then
            self.fadeAt = Peek.nowMs()
            Peek.fading[#Peek.fading + 1] = self
        else
            self:setVisible(false)
            self:removeFromUIManager()
        end
        Peek.syncKeys()
        Peek.metrics.closes = Peek.metrics.closes + 1
        Peek.log("close reason=" .. tostring(reason) .. " ms=" .. (Peek.nowMs() - (self.openedAt or 0)) .. " scans=" .. (self.scanNo or 0)
            .. " peakPeople=" .. (self.peak or 0) .. " models=" .. (self.models or 0))
    end
end

if type(Events) == "table" then
    if Events.OnFillWorldObjectContextMenu ~= nil and type(Events.OnFillWorldObjectContextMenu.Add) == "function" then
        Events.OnFillWorldObjectContextMenu.Add(ProjectALife.TalkUi.guarded(Peek.fill))
    end
    if Events.OnKeyPressed ~= nil and type(Events.OnKeyPressed.Add) == "function" then
        Events.OnKeyPressed.Add(Peek.onKey)
    end
    if Events.OnMainMenuEnter ~= nil and type(Events.OnMainMenuEnter.Add) == "function" then
        Events.OnMainMenuEnter.Add(Peek.reset)
    end
end

Peek.registerKey()

return Peek
