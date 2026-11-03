require "CyesPushDoors/Core"
require "CyesPushDoors/Settings"

CyesPushDoors = CyesPushDoors or {}
local CPD = CyesPushDoors
local C = CPD.Config

local CHORD_FILE = "CyesPushDoors_ForcedOpeningKey.ini"
local DEFAULT_KEY_E = Keyboard and Keyboard.KEY_E or 18
local DEFAULT_KEY_ALT = Keyboard and Keyboard.KEY_LMENU or 56
local MAX_MOUSE_BUTTON = 7
local MIN_CAPTURE_MOUSE_BUTTON = 2
local CAPTURE_TIMEOUT_MS = 15000
local chord = {
    first = { kind="key", code=DEFAULT_KEY_ALT },
    second = { kind="key", code=DEFAULT_KEY_E },
}
local captureActive = false
local captureStartedAt = 0
local captureInputs = {}
local captureMouseWasDown = {}
local chordLatched = false
local chordButtonOption = nil

local LEGACY_MODIFIER_CODES = {
    ctrl = Keyboard and Keyboard.KEY_LCONTROL or 29,
    alt = Keyboard and Keyboard.KEY_LMENU or 56,
    shift = Keyboard and Keyboard.KEY_LSHIFT or 42,
}

local function nowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local MODIFIER_KEY_PAIRS = {
    {
        left = Keyboard and Keyboard.KEY_LSHIFT or 42,
        right = Keyboard and Keyboard.KEY_RSHIFT or 54,
        label = "Shift",
    },
    {
        left = Keyboard and Keyboard.KEY_LCONTROL or 29,
        right = Keyboard and Keyboard.KEY_RCONTROL or 157,
        label = "Ctrl",
    },
    {
        left = Keyboard and Keyboard.KEY_LMENU or 56,
        right = Keyboard and Keyboard.KEY_RMENU or 184,
        label = "Alt",
    },
}

function CPD.selectForcedOpeningAnimation(character)
    local side = CPD.selectForcedOpeningSide(character)
    if not side then return nil, nil end
    local actionAnim = CPD.getForcedOpeningAnimationForSide(side)
    return actionAnim, side
end

local function parseBool(value)
    return string.lower(tostring(value or "")) == "true"
end

local function keyDown(keyCode)
    if not keyCode or not isKeyDown then return false end
    local ok, value = pcall(isKeyDown, keyCode)
    return ok and value == true
end

local function mouseDown(buttonCode)
    buttonCode = tonumber(buttonCode)
    if buttonCode == nil or buttonCode < 0 then return false end
    if isMouseButtonDown then
        local ok, value = pcall(isMouseButtonDown, buttonCode)
        if ok then return value == true end
    end
    if Mouse and Mouse.isButtonDown then
        local ok, value = pcall(Mouse.isButtonDown, buttonCode)
        if ok then return value == true end
    end
    return false
end

local function keyName(keyCode)
    keyCode = tonumber(keyCode)
    for i = 1, #MODIFIER_KEY_PAIRS do
        local pair = MODIFIER_KEY_PAIRS[i]
        if keyCode == pair.left or keyCode == pair.right then return pair.label end
    end
    if getKeyName then
        local ok, value = pcall(getKeyName, keyCode)
        if ok and value and tostring(value) ~= "" then return tostring(value) end
    end
    if Keyboard and Keyboard.getKeyName then
        local ok, value = pcall(Keyboard.getKeyName, keyCode)
        if ok and value and tostring(value) ~= "" then return tostring(value) end
    end
    if tonumber(keyCode) == 18 then return "E" end
    return tostring(keyCode)
end

local function translatedText(key, fallback)
    if getText then
        local ok, value = pcall(getText, key)
        if ok and value and tostring(value) ~= key then return tostring(value) end
    end
    return fallback
end

local function mouseName(buttonCode)
    buttonCode = math.floor(tonumber(buttonCode) or -1)
    if buttonCode == 0 then
        return translatedText("IGUI_CyesPushDoors_MouseLeft", "Left Click")
    end
    if buttonCode == 1 then
        return translatedText("IGUI_CyesPushDoors_MouseRight", "Right Click")
    end
    if buttonCode == 2 then
        return translatedText("IGUI_CyesPushDoors_MouseMiddle", "Middle Click")
    end
    local prefix = translatedText("IGUI_CyesPushDoors_MouseButton", "Mouse Button")
    return prefix .. " " .. tostring(buttonCode + 1)
end

local function copyInput(input)
    if type(input) ~= "table" then return nil end
    local kind = tostring(input.kind or "")
    local code = tonumber(input.code)
    if kind ~= "key" and kind ~= "mouse" then return nil end
    if code == nil or code < 0 then return nil end
    if kind == "key" and code <= 0 then return nil end
    if kind == "mouse" and code > MAX_MOUSE_BUTTON then return nil end
    code = math.floor(code)
    if kind == "key" then
        for i = 1, #MODIFIER_KEY_PAIRS do
            local pair = MODIFIER_KEY_PAIRS[i]
            if code == pair.right then
                code = pair.left
                break
            end
        end
    end
    return { kind=kind, code=code }
end

local function sameInput(a, b)
    return a and b
        and a.kind == b.kind
        and tonumber(a.code) == tonumber(b.code)
end

local function inputName(input)
    if not input then return "?" end
    if input.kind == "mouse" then return mouseName(input.code) end
    return keyName(input.code)
end

local function inputDown(input)
    if not input then return false end
    if input.kind == "mouse" then return mouseDown(input.code) end
    local code = tonumber(input.code)
    for i = 1, #MODIFIER_KEY_PAIRS do
        local pair = MODIFIER_KEY_PAIRS[i]
        if code == pair.left or code == pair.right then
            return keyDown(pair.left) or keyDown(pair.right)
        end
    end
    return keyDown(input.code)
end

local function validChord(first, second)
    first = copyInput(first)
    second = copyInput(second)
    if not first or not second or sameInput(first, second) then return nil end
    return { first=first, second=second }
end

function CPD.getForcedOpeningChord()
    return {
        first = copyInput(chord.first),
        second = copyInput(chord.second),
    }
end

function CPD.getForcedOpeningChordLabel()
    return inputName(chord.first) .. " + " .. inputName(chord.second)
end

local function updateChordButtonTitle(text)
    if not chordButtonOption then return end
    text = tostring(text or CPD.getForcedOpeningChordLabel())
    chordButtonOption.name = text
    local element = chordButtonOption.element
    if element then
        local set = pcall(function() element:setTitle(text) end)
        if not set then element.title = text end
    end
end

local function saveChord()
    if not getFileWriter then return false end
    local writer = nil
    local ok = pcall(function() writer = getFileWriter(CHORD_FILE, true, false) end)
    if not ok or not writer then
        ok = pcall(function() writer = getFileWriter(CHORD_FILE, true) end)
    end
    if not ok or not writer then return false end
    local saved = pcall(function()
        writer:writeln("format=3")
        writer:writeln("input1=" .. tostring(chord.first.kind) .. ":" .. tostring(chord.first.code))
        writer:writeln("input2=" .. tostring(chord.second.kind) .. ":" .. tostring(chord.second.code))
        writer:close()
    end)
    if not saved then pcall(function() writer:close() end) end
    return saved
end

local function parseInput(value)
    local kind, rawCode = tostring(value or ""):match("^(%a+):(%d+)$")
    if kind ~= "key" and kind ~= "mouse" then return nil end
    return copyInput({ kind=kind, code=tonumber(rawCode) })
end

local function migrateLegacyChord(loaded)
    local key = tonumber(loaded.key)
    if not key or key <= 0 then return nil end

    local activeModifiers = {}
    local modifierOrder = { "ctrl", "alt", "shift" }
    for i = 1, #modifierOrder do
        local name = modifierOrder[i]
        if parseBool(loaded[name]) then
            activeModifiers[#activeModifiers + 1] = {
                kind="key",
                code=LEGACY_MODIFIER_CODES[name],
            }
        end
    end

    local wasOldDefault = key == DEFAULT_KEY_E
        and parseBool(loaded.shift)
        and not parseBool(loaded.ctrl)
        and not parseBool(loaded.alt)
    if wasOldDefault then return validChord(chord.first, chord.second) end
    if #activeModifiers ~= 1 then return nil end
    return validChord(activeModifiers[1], { kind="key", code=key })
end

local function isPreviousDefaultChord(value)
    if not value then return false end
    local rightClick = { kind="mouse", code=1 }
    local eKey = { kind="key", code=DEFAULT_KEY_E }
    return sameInput(value.first, rightClick) and sameInput(value.second, eKey)
        or sameInput(value.first, eKey) and sameInput(value.second, rightClick)
end

function CPD.loadForcedOpeningChord()
    if not getFileReader then return false end
    local reader = nil
    local ok = pcall(function() reader = getFileReader(CHORD_FILE, false) end)
    if not ok or not reader then return false end
    local loaded = {}
    local loadedOk = pcall(function()
        while true do
            local line = reader:readLine()
            if line == nil then break end
            local name, value = tostring(line):match("^([%w_]+)=(.*)$")
            if name then loaded[name] = value end
        end
        reader:close()
    end)
    if not loadedOk then
        pcall(function() reader:close() end)
        return false
    end
    local loadedFormat = tonumber(loaded.format) or 1
    local loadedChord = validChord(parseInput(loaded.input1), parseInput(loaded.input2))
    local migrated = false
    if loadedChord then
        if isPreviousDefaultChord(loadedChord) then
            loadedChord = validChord(
                { kind="key", code=DEFAULT_KEY_ALT },
                { kind="key", code=DEFAULT_KEY_E }
            )
            migrated = true
        elseif loadedFormat < 3 then
            migrated = true
        end
    elseif not loadedChord then
        loadedChord = migrateLegacyChord(loaded)
        migrated = loadedChord ~= nil
    end
    if loadedChord then chord = loadedChord end
    if migrated then saveChord() end
    chordLatched = false
    updateChordButtonTitle()
    return true
end

function CPD.registerForcedOpeningChordButton(option)
    chordButtonOption = option
    updateChordButtonTitle()
end

function CPD.beginForcedOpeningChordCapture(option)
    if option then CPD.registerForcedOpeningChordButton(option) end
    captureActive = true
    captureStartedAt = nowMs()
    captureInputs = {}
    chordLatched = false
    captureMouseWasDown = {}
    for buttonCode = MIN_CAPTURE_MOUSE_BUTTON, MAX_MOUSE_BUTTON do
        captureMouseWasDown[buttonCode] = mouseDown(buttonCode)
    end
    local prompt = translatedText(
        "IGUI_CyesPushDoors_ForcedOpeningKey_Prompt",
        "Press exactly two inputs (left/right click unavailable)..."
    )
    updateChordButtonTitle(prompt)
    if CPD.mpDebug then
        CPD.mpDebug("FORCED_OPENING_CAPTURE_START", "timeoutMs=" .. tostring(CAPTURE_TIMEOUT_MS))
    end
end

function CPD.cancelForcedOpeningChordCapture(reason)
    if not captureActive then return false end
    captureActive = false
    captureStartedAt = 0
    captureInputs = {}
    captureMouseWasDown = {}
    chordLatched = false
    updateChordButtonTitle()
    if CPD.mpDebug then
        CPD.mpDebug("FORCED_OPENING_CAPTURE_CANCEL", "reason=" .. tostring(reason or "external"))
    end
    return true
end

function CPD.isForcedOpeningChordCaptureActive()
    return captureActive == true
end

local function eatKey(keyCode)
    if GameKeyboard and GameKeyboard.eatKeyPress then
        pcall(GameKeyboard.eatKeyPress, keyCode)
    end
end

local function finishChordCapture()
    local captured = validChord(captureInputs[1], captureInputs[2])
    if not captured then return false end
    chord = captured
    captureActive = false
    captureStartedAt = 0
    captureInputs = {}
    chordLatched = false
    local saved = saveChord()
    if not saved and CPD and CPD.log then CPD.log("FORCED_OPENING_CHORD_SAVE_FAILED") end
    updateChordButtonTitle()
    if CPD.mpDebug then
        CPD.mpDebug(
            "FORCED_OPENING_CAPTURE_SAVED",
            "input1=" .. tostring(chord.first.kind) .. ":" .. tostring(chord.first.code) ..
            " input2=" .. tostring(chord.second.kind) .. ":" .. tostring(chord.second.code)
        )
    end
    return true
end

local function captureInput(kind, code)
    if not captureActive then return false end
    if kind == "mouse" and tonumber(code) and tonumber(code) < MIN_CAPTURE_MOUSE_BUTTON then
        return false
    end
    local input = copyInput({ kind=kind, code=code })
    if not input then return false end
    for i = 1, #captureInputs do
        if sameInput(captureInputs[i], input) then return true end
    end
    if #captureInputs >= 2 then return true end
    captureInputs[#captureInputs + 1] = input
    if #captureInputs == 1 then
        updateChordButtonTitle(inputName(input) .. " + ...")
        return true
    end
    return finishChordCapture()
end

local function sameSquare(a, b)
    return a and b
        and a:getX() == b:getX()
        and a:getY() == b:getY()
        and a:getZ() == b:getZ()
end

local function queueWalkToForcedOpeningSquare(player, standSquare, door)
    if sameSquare(player and player:getCurrentSquare(), standSquare) then return true end
    if ISWalkToTimedAction and type(ISWalkToTimedAction.new) == "function" then
        ISTimedActionQueue.add(ISWalkToTimedAction:new(player, standSquare))
        return true
    end
    if luautils and type(luautils.walkAdj) == "function" then
        local doorSquare = door and door:getSquare() or nil
        if not doorSquare then return false end
        local ok, queued = pcall(luautils.walkAdj, player, doorSquare)
        return ok and queued == true
    end
    return false
end

local function attachedDoor(object)
    if not object or not CPD.isSupportedDoor(object) then return false end
    local square = object:getSquare()
    if not square then return false end
    local index = object:getObjectIndex()
    return index == nil or tonumber(index) == nil or tonumber(index) >= 0
end

local function findForcedOpeningCandidate(player)
    if not player or not player:isAlive() then return nil end
    local psq = player:getCurrentSquare()
    if not psq then return nil end
    local radius = math.max(1, math.floor(tonumber(C.FORCED_OPENING_SEARCH_RADIUS) or 4))
    local px, py, pz = psq:getX(), psq:getY(), psq:getZ()
    local nearestDoor = nil
    local nearestDistanceSq = math.huge

    for x = px - radius, px + radius do
        for y = py - radius, py + radius do
            local square = getCell():getGridSquare(x, y, pz)
            local objects = square and square:getObjects() or nil
            if objects then
                for i = 0, objects:size() - 1 do
                    local door = objects:get(i)
                    if attachedDoor(door) then
                        local distanceSq = CPD.getPlayerDoorDistanceSq(player, door)
                        if distanceSq < nearestDistanceSq then
                            nearestDoor = door
                            nearestDistanceSq = distanceSq
                        end
                    end
                end
            end
        end
    end
    if not nearestDoor then return nil end
    local state, reason = CPD.getForcedOpeningState(player, nearestDoor)
    return {
        door = nearestDoor,
        state = state,
        reason = reason,
        distanceSq = nearestDistanceSq,
    }
end

local function queueForcedOpening(player, candidate)
    if not ISTimedActionQueue
        or not ISCPDForceDoorPrepareAction
        or not ISCPDForceDoorAction then
        CPD.log("FORCED_OPENING_ACTION_UNAVAILABLE")
        return false
    end
    local standSquare = candidate.state and candidate.state.standSquare or nil
    if not standSquare then return false end

    ISTimedActionQueue.clear(player)
    if not queueWalkToForcedOpeningSquare(player, standSquare, candidate.door) then
        CPD.log("FORCED_OPENING_WALK_UNAVAILABLE")
        return false
    end
    local useCustomAnimation = CPD.Settings.animationsEnabled()
    local actionAnim = nil
    if useCustomAnimation then
        actionAnim = CPD.selectForcedOpeningAnimation(player)
        if not actionAnim then return false end
    end
    ISTimedActionQueue.add(ISCPDForceDoorPrepareAction:new(
        player,
        candidate.door
    ))
    ISTimedActionQueue.add(ISCPDForceDoorAction:new(
        player,
        candidate.door,
        actionAnim,
        useCustomAnimation
    ))
    return true
end

function CPD.tryStartForcedOpening(player)
    local candidate = findForcedOpeningCandidate(player)
    if not candidate then return false end
    if candidate.reason == "wrong-side" then
        CPD.playKickDoorAnimationForOpener(
            player,
            candidate.door,
            nil,
            false,
            "open",
            "CPDPushDoorFail"
        )
        CPD.notifyForcedOpeningMessage(player, "wrong-side")
        return true
    end
    if candidate.reason == "both-arms-fractured" then
        CPD.playKickDoorAnimationForOpener(
            player,
            candidate.door,
            nil,
            false,
            "open",
            "CPDPushDoorFail"
        )
        CPD.notifyForcedOpeningMessage(player, "both-arms-fractured")
        return true
    end
    if not candidate.state or candidate.state.blocked ~= true or candidate.reason ~= nil then
        local zombieCount = candidate.state and tonumber(candidate.state.zombieCount) or 0
        local capacity = candidate.state and tonumber(candidate.state.capacity) or -1
        local exactCapacity = candidate.reason == "not-crowd-blocked"
            and zombieCount > 0
            and zombieCount == capacity
        CPD.notifyForcedOpeningMessage(player, exactCapacity and "manageable" or "not-needed")
        return true
    end
    return queueForcedOpening(player, candidate)
end

function CPD.requestForcedDoorOpening(player, door, forcedActionAnim, useCustomAnimation)
    if not player or not door then return false end
    if useCustomAnimation == nil then
        useCustomAnimation = CPD.Settings.animationsEnabled()
    else
        useCustomAnimation = useCustomAnimation == true
    end
    if useCustomAnimation and CPD.getForcedOpeningAnimationSide(forcedActionAnim) == nil then
        forcedActionAnim = CPD.selectForcedOpeningAnimation(player)
        if not forcedActionAnim then return false end
    elseif not useCustomAnimation then
        forcedActionAnim = nil
    end
    if isClient and isClient() then
        local args = CPD.makeDoorArgs(door, nil, true, "open")
        if not args or not sendClientCommand then return false end
        args.forcedOpening = true
        args.forcedOpeningUseAnimation = useCustomAnimation
        if useCustomAnimation then args.forcedOpeningAction = forcedActionAnim end
        return pcall(function()
            sendClientCommand(player, "CyesPushDoors", "forceOpenDoor", args)
        end)
    end
    local ok, success = pcall(
        CPD.resolveForcedDoorOpening,
        player,
        door,
        forcedActionAnim,
        useCustomAnimation
    )
    if not ok then
        CPD.log("FORCED_OPENING_SP_ERROR " .. tostring(success))
        return false
    end
    return success == true
end

function CPD.handleForcedOpeningInput(keyCode)
    keyCode = tonumber(keyCode)
    if not keyCode then return false, false end

    if captureActive then
        eatKey(keyCode)
        local escapeKey = Keyboard and Keyboard.KEY_ESCAPE or 1
        if keyCode == escapeKey then
            CPD.cancelForcedOpeningChordCapture()
            return true, false
        end
        captureInput("key", keyCode)
        return true, true
    end

    local keyIsPartOfChord = chord.first.kind == "key" and keyCode == tonumber(chord.first.code)
        or chord.second.kind == "key" and keyCode == tonumber(chord.second.code)
    if not keyIsPartOfChord then return false, false end
    if not inputDown(chord.first) or not inputDown(chord.second) then return false, false end
    if chordLatched then return false, false end

    chordLatched = true
    local player = getPlayer and getPlayer() or nil
    if CPD.tryStartForcedOpening(player) then
        eatKey(keyCode)
        return true, true
    end
    return false, false
end

function CPD.updateForcedOpeningInput()
    if captureActive then
        if nowMs() - captureStartedAt >= CAPTURE_TIMEOUT_MS then
            CPD.cancelForcedOpeningChordCapture("timeout")
            return
        end
        for buttonCode = MIN_CAPTURE_MOUSE_BUTTON, MAX_MOUSE_BUTTON do
            local down = mouseDown(buttonCode)
            if down and captureMouseWasDown[buttonCode] ~= true then
                captureInput("mouse", buttonCode)
                if not captureActive then break end
            end
            captureMouseWasDown[buttonCode] = down
        end
        return
    end

    local bothDown = inputDown(chord.first) and inputDown(chord.second)
    if not bothDown then
        chordLatched = false
        return
    end
    if chordLatched then return end

    chordLatched = true
    local player = getPlayer and getPlayer() or nil
    CPD.tryStartForcedOpening(player)
end

local function captureKeyFromMenus(keyCode)
    if not captureActive then return end
    if CPD._hookInputEventInstalled == true then return end
    CPD.handleForcedOpeningInput(keyCode)
end

local function updateCaptureFromMenus()
    if captureActive then CPD.updateForcedOpeningInput() end
end

CPD.loadForcedOpeningChord()

if Events and Events.OnKeyStartPressed then
    Events.OnKeyStartPressed.Add(captureKeyFromMenus)
end
if Events and Events.OnTick then
    Events.OnTick.Add(updateCaptureFromMenus)
end
if Events and Events.OnPreUIDraw then
    Events.OnPreUIDraw.Add(updateCaptureFromMenus)
end

return CPD
