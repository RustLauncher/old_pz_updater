require "ISUI/ISEmoteRadialMenu"

ProjectALife = ProjectALife or {}

local Shout = { registered = false, pressedAtMs = nil, radialWasVisible = false }
ProjectALife.ShoutListener = Shout

local function noteShout(character)
    pcall(function()
        if character == nil or not instanceof(character, "IsoPlayer") then return end

        local guard = ProjectALife.AIFence
        local authoritative = guard == nil
            or type(guard.authoritative) ~= "function"
            or guard.authoritative() == true
        if not authoritative then
            if type(sendClientCommand) == "function" then
                sendClientCommand(character, "ProjectALife", "shout", {})
            end

            local executor = ProjectALife.Executor
            if not (executor ~= nil and type(executor.clientAuthority) == "function"
                    and executor.clientAuthority() == true) then
                return
            end
        end
        local investigation = ProjectALife.Investigation
        if investigation ~= nil and type(investigation.noteShout) == "function" then
            investigation.noteShout(character:getX(), character:getY(),
                character:getZ(), character)
        end
    end)
end

Shout.note = noteShout

function Shout.wrapKeyboard()
    local menu = ISEmoteRadialMenu
    if menu == nil or menu.alifeKeyboardWrapped then return end
    if type(menu.onKeyPressed) ~= "function" or type(menu.onKeyReleased) ~= "function"
            or type(menu.checkKey) ~= "function" then return end
    local pressed, released = menu.onKeyPressed, menu.onKeyReleased
    menu.onKeyPressed = function(key)
        if menu.checkKey(key) then
            Shout.pressedAtMs = getTimestampMs()
            Shout.radialWasVisible = getPlayerRadialMenu(0):isReallyVisible()
        end
        return pressed(key)
    end
    menu.onKeyReleased = function(key)
        local player = getSpecificPlayer(0)
        local callout = menu.checkKey(key) and getCore():isKey("Shout", key)
            and Shout.pressedAtMs ~= nil and getTimestampMs() - Shout.pressedAtMs < 450
            and not Shout.radialWasVisible and not getPlayerRadialMenu(0):isReallyVisible()
            and player ~= nil and player:getVehicle() == nil
        local result = released(key)
        if getCore():isKey("Shout", key) or getCore():isKey("Emote", key) then
            Shout.pressedAtMs = nil
        end
        if callout then noteShout(player) end
        return result
    end
    Events.OnKeyStartPressed.Remove(pressed)
    Events.OnKeyStartPressed.Add(menu.onKeyPressed)
    Events.OnKeyPressed.Remove(released)
    Events.OnKeyPressed.Add(menu.onKeyReleased)
    menu.alifeKeyboardWrapped = true
end

local function wrapEntryPoints()
    Shout.wrapKeyboard()
    pcall(function()
        if ISEmoteRadialMenu ~= nil and ISEmoteRadialMenu.emote ~= nil
                and ISEmoteRadialMenu.alifeWrapped ~= true then
            local original = ISEmoteRadialMenu.emote
            ISEmoteRadialMenu.emote = function(self, emote, ...)
                if emote == "shout" then noteShout(self.character) end
                return original(self, emote, ...)
            end
            ISEmoteRadialMenu.alifeWrapped = true
        end
    end)
    pcall(function()
        if ISDPadWheels ~= nil and ISDPadWheels.onShout ~= nil
                and ISDPadWheels.alifeWrapped ~= true then
            local original = ISDPadWheels.onShout
            ISDPadWheels.onShout = function(playerObj, ...)
                noteShout(playerObj)
                return original(playerObj, ...)
            end
            ISDPadWheels.alifeWrapped = true
        end
    end)
end

function Shout.register()
    if Shout.registered then return true end
    if type(Events) ~= "table" then return false, "events_unavailable" end

    if Events.OnGameStart ~= nil and type(Events.OnGameStart.Add) == "function" then
        Events.OnGameStart.Add(wrapEntryPoints)
    else
        wrapEntryPoints()
    end
    Shout.registered = true
    return true
end

Shout.register()

local function postWeaponNoise(character, weapon)
    pcall(function()
        if type(isClient) ~= "function" or not isClient() then return end
        if type(isServer) == "function" and isServer() then return end
        if not instanceof(character, "IsoPlayer") then return end
        if not character:isLocalPlayer() then return end

        pcall(function()
            local executor = ProjectALife.Executor
            if not (executor ~= nil and type(executor.clientAuthority) == "function"
                    and executor.clientAuthority() == true) then return end
            local investigation = ProjectALife.Investigation
            if investigation == nil or type(investigation.note) ~= "function" then return end
            local radius = 10
            if weapon ~= nil and weapon:isAimedFirearm() then
                radius = tonumber(weapon:getSoundRadius()) or radius
            end
            investigation.note(character:getX(), character:getY(), character:getZ(),
                math.max(4, math.min(120, radius)), 20000, nil, "noise", nil, character)
        end)
        Shout.weaponReportSequence = (Shout.weaponReportSequence or 0) + 1
        sendClientCommand(character, "ProjectALife", "weaponNoise", {
            sequence = Shout.weaponReportSequence,
            weapon = tostring(weapon and weapon:getFullType() or ""),
        })
    end)
end

if type(Events) == "table" and Events.OnWeaponSwing ~= nil
        and type(Events.OnWeaponSwing.Add) == "function" then
    Events.OnWeaponSwing.Add(postWeaponNoise)
end

return Shout
