require "PZAPI/ModOptions"
require "ProjectALife/Core/ALifeText"
require "ProjectALife/Interface/ALifeDiscordLink"

ProjectALife = ProjectALife or {}

local Prefs = {
    fileName = "alife_menu_prefs.ini",
    loaded = false,

    values = { diagnostics = false, recorder = false, rightClick = false, fieldRadio = true, cinematicTalk = true, calm = true,
        repNotify = true, repTab = true },
    legacyKeys = { fieldRadio = "pda" },

    serverAck = nil,
    announceRefused = nil,
    lastAnnounceMs = nil,
    lastTickMs = nil,
    wasAdmin = nil,
    tickMs = 1000,
    announceGapMs = 5000,
    retryGapMs = 3000,
    refusedGapMs = 30000,
    offText = "A-Life diagnostics were off on the server for you - turned on, press again",
    retryText = "A-Life diagnostics were off on the server for you - turned on, retrying",
    disabledText = "A-Life diagnostics are off - Options > Project A-Life",

    optionsId = "ProjectALife",
}
ProjectALife.MenuPrefs = Prefs
Prefs.values.woundPanel = true
Prefs.values.peekDoor = true
Prefs.values.peekLive = true
Prefs.values.peekLens = true
Prefs.values.peekFull = true
Prefs.values.creatorAsyncSave = true
Prefs.values.creatorCompactSave = true
Prefs.values.creatorSeasonFilter = true
Prefs.values.talkTheme = true

function Prefs.load()
    if Prefs.loaded then return Prefs.values end
    Prefs.loaded = true
    if type(getFileReader) ~= "function" then return Prefs.values end
    local stale = false
    pcall(function()
        local reader = getFileReader(Prefs.fileName, true)
        if reader == nil then return end
        local legacy, seenCurrent = nil, false
        while true do
            local line = reader:readLine()
            if line == nil then break end
            local key, value = string.match(line, "^%s*([%a%d_]+)%s*=%s*(%a+)%s*$")

            if key ~= nil and key == Prefs.legacyKeys.fieldRadio then
                legacy = value == "true"
            elseif key ~= nil and Prefs.values[key] ~= nil then
                Prefs.values[key] = value == "true"
                if key == "fieldRadio" then seenCurrent = true end
            end
        end
        reader:close()
        if not seenCurrent and legacy ~= nil then Prefs.values.fieldRadio = legacy end
        stale = legacy ~= nil
    end)
    if stale then
        Prefs.persist()
    end
    return Prefs.values
end

function Prefs.persist()
    if type(getFileWriter) ~= "function" then return false end
    local ok, written = pcall(function()
        local writer = getFileWriter(Prefs.fileName, true, false)
        if writer == nil then return false end
        writer:write("diagnostics = "
            .. tostring(Prefs.values.diagnostics == true) .. "\n")
        writer:write("recorder = "
            .. tostring(Prefs.values.recorder == true) .. "\n")
        writer:write("rightClick = "
            .. tostring(Prefs.values.rightClick == true) .. "\n")
        writer:write("fieldRadio = "
            .. tostring(Prefs.values.fieldRadio ~= false) .. "\n")
        writer:write("cinematicTalk = "
            .. tostring(Prefs.values.cinematicTalk == true) .. "\n")
        writer:write("calm = "
            .. tostring(Prefs.values.calm ~= false) .. "\n")
        writer:write("woundPanel = "
            .. tostring(Prefs.values.woundPanel ~= false) .. "\n")
        writer:write("repNotify = "
            .. tostring(Prefs.values.repNotify ~= false) .. "\n")
        writer:write("repTab = "
            .. tostring(Prefs.values.repTab ~= false) .. "\n")
        writer:write("peekDoor = "
            .. tostring(Prefs.values.peekDoor ~= false) .. "\n")
        writer:write("peekLive = "
            .. tostring(Prefs.values.peekLive ~= false) .. "\n")
        writer:write("peekLens = "
            .. tostring(Prefs.values.peekLens ~= false) .. "\n")
        writer:write("peekFull = "
            .. tostring(Prefs.values.peekFull ~= false) .. "\n")
        writer:write("creatorAsyncSave = "
            .. tostring(Prefs.values.creatorAsyncSave ~= false) .. "\n")
        writer:write("creatorCompactSave = "
            .. tostring(Prefs.values.creatorCompactSave ~= false) .. "\n")
        writer:write("creatorSeasonFilter = "
            .. tostring(Prefs.values.creatorSeasonFilter ~= false) .. "\n")
        writer:write("talkTheme = "
            .. tostring(Prefs.values.talkTheme ~= false) .. "\n")
        writer:close()
        return true
    end)
    return ok and written == true
end

function Prefs.diagnostics()
    return Prefs.load().diagnostics == true
end

function Prefs.recorder()
    local values = Prefs.load()
    return values.diagnostics == true and values.recorder == true
end

function Prefs.rightClickOn()
    local values = Prefs.load()
    return values.rightClick == true or values.diagnostics == true
end

function Prefs.radioPanelOn()
    return Prefs.load().fieldRadio ~= false
end

function Prefs.talkStyle()
    if Prefs.load().cinematicTalk == false then return "Classic" end
    return "Cinematic"
end

function Prefs.setTalkStyle(style)
    Prefs.load().cinematicTalk = style ~= "Classic"
    Prefs.persist()
    Prefs.syncOptions()
    return Prefs.talkStyle()
end

function Prefs.talkTheme()
    if Prefs.load().talkTheme == false then return "Classic" end
    return "A-Life"
end

function Prefs.setTalkTheme(theme)
    Prefs.load().talkTheme = theme ~= "Classic"
    Prefs.persist()
    Prefs.syncOptions()
    return Prefs.talkTheme()
end

function Prefs.calmOn()
    return Prefs.load().calm ~= false
end

function Prefs.woundPanelOn()
    return Prefs.load().woundPanel ~= false
end

function Prefs.repNotifyOn()
    return Prefs.load().repNotify ~= false
end

function Prefs.repTabOn()
    return Prefs.load().repTab ~= false
end

function Prefs.peekDoorOn()
    return Prefs.load().peekDoor ~= false
end

function Prefs.peekLiveOn()
    return Prefs.load().peekLive ~= false
end

function Prefs.peekLensOn()
    return Prefs.load().peekLens ~= false
end

function Prefs.peekFullOn()
    return Prefs.load().peekFull ~= false
end

function Prefs.creatorAsyncSaveOn()
    return Prefs.load().creatorAsyncSave ~= false
end

function Prefs.creatorCompactSaveOn()
    return Prefs.load().creatorCompactSave ~= false
end

function Prefs.creatorSeasonFilterOn()
    return Prefs.load().creatorSeasonFilter ~= false
end

function Prefs.setRightClick(enabled)
    Prefs.load().rightClick = enabled == true
    Prefs.persist()
    Prefs.syncOptions()
    return Prefs.values.rightClick
end

function Prefs.setDiagnostics(enabled)
    Prefs.load().diagnostics = enabled == true
    Prefs.persist()
    Prefs.syncOptions()
    return Prefs.values.diagnostics
end

function Prefs.warnSlow()
    if not Prefs.diagnostics() then return false end
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil
    if player == nil or HaloTextHelper == nil or type(HaloTextHelper.addText) ~= "function" then return false end
    local line = "A-Life Diagnostics is ON and slows the game. Turn it off in Options > Project A-Life"
    local text = type(ProjectALife) == "table" and ProjectALife.Text or nil
    if type(text) == "table" and type(text.ui) == "function" then
        local ok, translated = pcall(text.ui, line)
        if ok and type(translated) == "string" then line = translated end
    end
    return pcall(HaloTextHelper.addText, player, line) == true
end

function Prefs.setRecorder(enabled)
    Prefs.load().recorder = enabled == true
    Prefs.persist()
    Prefs.syncOptions()
    return Prefs.recorder()
end

function Prefs.optionValue(id)
    return Prefs.load()[id] == true
end

function Prefs.syncOptions()
    local api = PZAPI and PZAPI.ModOptions
    if api == nil or type(api.Dict) ~= "table" then return false end
    local options = api.Dict[Prefs.optionsId]
    if options == nil or type(options.getOption) ~= "function" then return false end
    local values = Prefs.load()
    local diagnostics, recorder = options:getOption("diagnostics"), options:getOption("recorder")
    if diagnostics ~= nil and type(diagnostics.setValue) == "function" then
        diagnostics:setValue(values.diagnostics == true)
    end
    if recorder ~= nil and type(recorder.setValue) == "function" then
        recorder:setValue(values.recorder == true)
    end
    local rightClick = options:getOption("rightClick")
    if rightClick ~= nil and type(rightClick.setValue) == "function" then
        rightClick:setValue(values.rightClick == true)
    end
    local fieldRadio = options:getOption("fieldRadio")
    if fieldRadio ~= nil and type(fieldRadio.setValue) == "function" then
        fieldRadio:setValue(values.fieldRadio ~= false)
    end
    local cinematic = options:getOption("cinematicTalk")
    if cinematic ~= nil and type(cinematic.setValue) == "function" then
        cinematic:setValue(values.cinematicTalk ~= false)
    end
    local calm = options:getOption("calm")
    if calm ~= nil and type(calm.setValue) == "function" then
        calm:setValue(values.calm ~= false)
    end
    local woundPanel = options:getOption("woundPanel")
    if woundPanel ~= nil and type(woundPanel.setValue) == "function" then
        woundPanel:setValue(values.woundPanel ~= false)
    end
    local repNotify = options:getOption("repNotify")
    if repNotify ~= nil and type(repNotify.setValue) == "function" then
        repNotify:setValue(values.repNotify ~= false)
    end
    local repTab = options:getOption("repTab")
    if repTab ~= nil and type(repTab.setValue) == "function" then
        repTab:setValue(values.repTab ~= false)
    end
    local peekDoor = options:getOption("peekDoor")
    if peekDoor ~= nil and type(peekDoor.setValue) == "function" then
        peekDoor:setValue(values.peekDoor ~= false)
    end
    local peekLive = options:getOption("peekLive")
    if peekLive ~= nil and type(peekLive.setValue) == "function" then
        peekLive:setValue(values.peekLive ~= false)
    end
    local peekLens = options:getOption("peekLens")
    if peekLens ~= nil and type(peekLens.setValue) == "function" then
        peekLens:setValue(values.peekLens ~= false)
    end
    local peekFull = options:getOption("peekFull")
    if peekFull ~= nil and type(peekFull.setValue) == "function" then
        peekFull:setValue(values.peekFull ~= false)
    end
    local creatorAsyncSave = options:getOption("creatorAsyncSave")
    if creatorAsyncSave ~= nil and type(creatorAsyncSave.setValue) == "function" then
        creatorAsyncSave:setValue(values.creatorAsyncSave ~= false)
    end
    local creatorCompactSave = options:getOption("creatorCompactSave")
    if creatorCompactSave ~= nil and type(creatorCompactSave.setValue) == "function" then
        creatorCompactSave:setValue(values.creatorCompactSave ~= false)
    end
    local creatorSeasonFilter = options:getOption("creatorSeasonFilter")
    if creatorSeasonFilter ~= nil and type(creatorSeasonFilter.setValue) == "function" then
        creatorSeasonFilter:setValue(values.creatorSeasonFilter ~= false)
    end
    local talkTheme = options:getOption("talkTheme")
    if talkTheme ~= nil and type(talkTheme.setValue) == "function" then
        talkTheme:setValue(values.talkTheme ~= false)
    end
    Prefs.followDiagnostics(options, values.diagnostics == true)
    return true
end

function Prefs.followDiagnostics(options, enabled)
    if options == nil or type(options.getOption) ~= "function" then return end
    local recorder = options:getOption("recorder")
    if recorder ~= nil and type(recorder.setEnabled) == "function" then recorder:setEnabled(enabled == true) end
    local rightClick = options:getOption("rightClick")
    if rightClick ~= nil and type(rightClick.setEnabled) == "function" then rightClick:setEnabled(enabled ~= true) end
end

function Prefs.toggleDiagnostics()
    return Prefs.setDiagnostics(not Prefs.diagnostics())
end

function Prefs.toggleRecorder()
    return Prefs.setRecorder(not (Prefs.load().recorder == true))
end

function Prefs.sandboxWanted()
    local sandbox = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(sandbox) ~= "table" then return true end
    local value = sandbox.Debug_ShowAdminTools
    if value == nil then return true end
    return value == true
end

function Prefs.serverAdmin(player)
    if type(isAdmin) == "function" and isAdmin() then return true end

    if player == nil or type(player.getAccessLevel) ~= "function" then return false end
    local ok, level = pcall(player.getAccessLevel, player)
    level = ok and string.lower(tostring(level or "")) or ""
    return level == "admin"
end

function Prefs.adminAccess(player)

    if Prefs.serverAdmin(player) then return true end
    return type(isDebugEnabled) == "function" and isDebugEnabled() == true
end

function Prefs.permitted(player)
    if Prefs.adminAccess(player) then return true end
    return type(isClient) ~= "function" or not isClient()
end

function Prefs.allowed(player)
    if not Prefs.permitted(player) then return false end
    if not Prefs.diagnostics() then return false end
    if Prefs.adminAccess(player) then return true end
    return Prefs.sandboxWanted()
end

function Prefs.safehouseTools(player)
    return Prefs.rightClickOn() and Prefs.permitted(player)
end

function Prefs.resetAnnounce()
    Prefs.serverAck = nil
    Prefs.announceRefused = nil
    Prefs.lastAnnounceMs = nil
    Prefs.lastTickMs = nil
    Prefs.wasAdmin = nil
end

function Prefs.announceDue(nowMs, gapMs)
    if Prefs.serverAck == true then return false end
    local now, last = tonumber(nowMs) or 0, tonumber(Prefs.lastAnnounceMs)
    if last ~= nil and now >= last
            and now - last < (tonumber(gapMs) or Prefs.announceGapMs) then
        return false
    end
    Prefs.lastAnnounceMs = now
    return true
end

function Prefs.reannounce(player, nowMs, gapMs)
    local rules = ProjectALife.MenuRules
    if player == nil or rules == nil or type(rules.apply) ~= "function" then return false end
    if not Prefs.allowed(player) or not Prefs.announceDue(nowMs, gapMs) then return false end
    return rules.apply(player) == true
end

function Prefs.acknowledge(reply)
    if type(reply) ~= "table" then return false end
    local refused = nil
    if reply.ok ~= true then refused = tostring(reply.reason or "refused") end
    local changed = refused ~= nil and refused ~= Prefs.announceRefused
    Prefs.serverAck = reply.ok == true and reply.enabled == true
    Prefs.announceRefused = refused
    return changed
end

function Prefs.diagnosticsRefused(player, nowMs)
    local now, last = tonumber(nowMs) or 0, tonumber(Prefs.lastAnnounceMs)

    if last == nil or now < last or now - last >= Prefs.retryGapMs then
        Prefs.serverAck = nil
    end
    Prefs.reannounce(player, now, Prefs.retryGapMs)
    if player ~= nil and Prefs.allowed(player) then return Prefs.lastAnnounceMs end
    return nil
end

function Prefs.refusedText(player)
    if player ~= nil and Prefs.allowed(player) then return ProjectALife.Text.ui(Prefs.offText) end
    return ProjectALife.Text.ui(Prefs.disabledText)
end

function Prefs.serviceForgot(player)
    if player == nil or (type(isClient) == "function" and isClient()) then return false end
    local service = ProjectALife.DebugService
    if service == nil or type(service.diagnosticsAllowed) ~= "function" then return false end
    return service.diagnosticsAllowed(player) ~= true
end

function Prefs.announceTick()
    if not Prefs.diagnostics() then return false end
    local now = type(getTimestampMs) == "function" and getTimestampMs() or 0
    local last = Prefs.lastTickMs
    if last ~= nil and now >= last and now - last < Prefs.tickMs then return false end
    Prefs.lastTickMs = now
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil
    local admin = player ~= nil and Prefs.serverAdmin(player)
    if Prefs.wasAdmin ~= nil and admin ~= Prefs.wasAdmin then
        Prefs.serverAck = nil
        Prefs.announceRefused = nil
        Prefs.lastAnnounceMs = nil
    end
    Prefs.wasAdmin = admin
    if Prefs.serverAck == true and Prefs.serviceForgot(player) then Prefs.serverAck = nil end
    if player == nil or not Prefs.permitted(player) then
        local rules = ProjectALife.MenuRules
        if rules ~= nil and type(rules.apply) == "function" then rules.apply(player, true) end
        return false
    end
    if Prefs.serverAck == true then return false end
    local gap = Prefs.announceGapMs
    if Prefs.announceRefused ~= nil then gap = Prefs.refusedGapMs end
    return Prefs.reannounce(player, now, gap)
end

if type(Events) == "table" and Events.OnTick ~= nil
        and type(Events.OnTick.Add) == "function" then
    Events.OnTick.Add(Prefs.announceTick)
end

function Prefs.registerOptions()
    local api = PZAPI and PZAPI.ModOptions
    if api == nil then return false end
    local Text = ProjectALife.Text
    local options = api:getOptions("ProjectALife")
    if options == nil then
        options = api:create("ProjectALife", Text.ui("Project A-Life"))
        options:addButton("discord", Text.ui("Join our Discord for more help"),
            Text.ui("Opens discord.gg/alife in your browser or the Steam overlay."),
            ProjectALife.DiscordLink.onButton)
        options:addDescription(Text.ui("Questions, bug reports and faction share codes: the A-Life Discord is at discord.gg/alife."))
        options:addTickBox("rightClick", Text.ui("Show A-Life in the right-click menu"),
            Prefs.load().rightClick == true,
            Text.ui("Shows A-Life entries in right-click menus (outpost radio, squad map). Off by default. NPC talk is always there. The admin tools and the Creator entry also need Diagnostics. The A-Life Creator (Insert) and world status (Home) are always on keys in Key Bindings and on buttons in the pause menu."))
        options:addTickBox("fieldRadio",Text.ui("Enable the A-Life radio panel"), Prefs.radioPanelOn(),
            Text.ui("On by default. Adds an A-Life Radio entry to the right-click menu of any radio or walkie-talkie, and a button in the radio window. It opens one panel with your standing, the people who told you where they live, what you heard on the air and notes from your base. Off removes the entries at once, no restart."))
        options:addTickBox("cinematicTalk", Text.ui("Cinematic talk window"), Prefs.talkStyle() == "Cinematic",
            Text.ui("On: the new Fallout-style talk window with portrait, opinion bar and numbered answers. Off: the classic window. Takes effect the next time you start a conversation."))
        options:addTickBox("talkTheme", Text.ui("A-Life colors in the talk window"), Prefs.talkTheme() == "A-Life",
            Text.ui("On by default: the talk window uses the A-Life blue-grey palette. Off: the classic dark green and gold look. Takes effect the next time you start a conversation."))
        options:addTickBox("calm", Text.ui("Calm around NPCs"), Prefs.calmOn(),
            Text.ui("On by default. While only A-Life NPCs are near, they do not raise your panic moodle and do not trigger the zombie surprise sound. Real zombies still do, and so does damage. Affects only you, on this computer."))
        options:addTickBox("woundPanel", Text.ui("Wound check panel"), Prefs.woundPanelOn(),
            Text.ui("On by default. Check wounds on a survivor opens a health panel like the vanilla one, with a body silhouette, the wound list and a treatment menu. Off: the wounds are only shown as a line of text over their head. Applies the next time you check wounds."))
        options:addTickBox("repNotify", Text.ui("Reputation notifications"), Prefs.repNotifyOn(),
            Text.ui("On by default. A floating note shows each change to your reputation with the reason, and a banner announces a new level. Affects only you, on this computer."))
        options:addTickBox("repTab", Text.ui("Reputation tab in the character window"), Prefs.repTabOn(),
            Text.ui("On by default. Adds a Reputation tab next to Temperature that lists every level you have unlocked. Takes effect at once. Affects only you, on this computer."))
        options:addTickBox("peekDoor", Text.ui("Peek through the door"), Prefs.peekDoorOn(),
            Text.ui("On by default. Right-click a closed door you can reach and choose Peek through the door: you lean in and get a peephole view of who or what is standing in front of it. Nothing outside notices you except by a small chance the server sets. Off hides the entry and the key."))
        options:addTickBox("peekLive", Text.ui("Real view in the peephole"), Prefs.peekLiveOn(),
            Text.ui("On by default. The peephole draws the real ground, walls, trees and fences in front of the door, lit by the real time of day and weather. Off: the old stylised view with a flat ground colour. Applies the next time you peek."))
        options:addTickBox("peekLens", Text.ui("Peek style: Lens"), Prefs.peekLensOn(),
            Text.ui("On by default: the peephole is a dark round lens with a night-vision, dusk or daylight grade, film grain and a blink when you look. Off: the Classic look, a plain framed window. Applies the next time you peek."))
        options:addTickBox("peekFull", Text.ui("Peek full screen"), Prefs.peekFullOn(),
            Text.ui("On by default: the peephole takes over the whole screen, black around the lens, and Esc, right-click or Back away leaves it. Off: the lens floats in a window over the game. Needs Peek style: Lens. Applies the next time you peek."))
        options:addTickBox("creatorAsyncSave", Text.ui("Creator saves in the background"), Prefs.creatorAsyncSaveOn(),
            Text.ui("On by default. The Creator writes your NPC in the background in small slices, so closing it or switching NPC never freezes the game. Turn it off only if saving misbehaves: the old save, which can take a long time on a big NPC list, comes back."))
        options:addTickBox("creatorCompactSave", Text.ui("Creator writes short profile files"), Prefs.creatorCompactSaveOn(),
            Text.ui("On by default. The Creator leaves out clothing and loadout lines that only repeat the default value, so the NPC file is a third of the size and opens much faster. The file is rewritten this way on your next save, and the old copy is kept next to it as a backup. Older files still load. Turn it off to write every line again."))
        options:addTickBox("creatorSeasonFilter", Text.ui("Creator suggests clothing by season and role"), Prefs.creatorSeasonFilterOn(),
            Text.ui("On by default. The Creator's clothing pickers list the items that suit the outfit set's season and the member's role first, mark novelty, protective and out-of-era items, warn about collisions before you choose, and each outfit set shows a health badge with a Suggest fix button. SHOW ALL in a picker lists everything. Turn it off to get the plain alphabetical lists back."))
        options:addTickBox("diagnostics", Text.ui("Diagnostics (SLOWS THE GAME, KEEP OFF)"), Prefs.diagnostics(),
            Text.ui("WARNING: THIS TANKS PERFORMANCE WHILE IT IS ON. Leave it off unless you are testing or sending a bug report. Off by default. Shows the A-Life right-click entries: the test tools (spawner, dumps, map layers) and the Creator. In multiplayer the server accepts them only from an admin."))
        options:addTickBox("recorder", Text.ui("Flight recorder (blackbox)"),
            Prefs.load().recorder == true,
            Text.ui("Off by default. Records NPC activity for bug reports. Needs Diagnostics and slows the game while on. Costs nothing while off."))
    end
    function options:apply()
        local prefs = ProjectALife.MenuPrefs
        local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil
        local values = prefs.load()
        local diagnostics, recorder = self:getOption("diagnostics"), self:getOption("recorder")
        local rightClick, previousRightClick = self:getOption("rightClick"), values.rightClick
        local fieldRadio, previousFieldRadio = self:getOption("fieldRadio"), values.fieldRadio
        local previousDiagnostics, previousRecorder = values.diagnostics, values.recorder
        local calm, previousCalm = self:getOption("calm"), values.calm
        if calm ~= nil then values.calm = calm:getValue() == true end
        local woundPanel, previousWoundPanel = self:getOption("woundPanel"), values.woundPanel
        if woundPanel ~= nil then values.woundPanel = woundPanel:getValue() == true end
        local repNotify, previousRepNotify = self:getOption("repNotify"), values.repNotify
        if repNotify ~= nil then values.repNotify = repNotify:getValue() == true end
        local repTab, previousRepTab = self:getOption("repTab"), values.repTab
        if repTab ~= nil then values.repTab = repTab:getValue() == true end
        local peekDoor, previousPeekDoor = self:getOption("peekDoor"), values.peekDoor
        if peekDoor ~= nil then values.peekDoor = peekDoor:getValue() == true end
        local peekLive, previousPeekLive = self:getOption("peekLive"), values.peekLive
        if peekLive ~= nil then values.peekLive = peekLive:getValue() == true end
        local peekLens, previousPeekLens = self:getOption("peekLens"), values.peekLens
        if peekLens ~= nil then values.peekLens = peekLens:getValue() == true end
        local peekFull, previousPeekFull = self:getOption("peekFull"), values.peekFull
        if peekFull ~= nil then values.peekFull = peekFull:getValue() == true end
        local creatorAsyncSave, previousCreatorAsyncSave = self:getOption("creatorAsyncSave"), values.creatorAsyncSave
        if creatorAsyncSave ~= nil then values.creatorAsyncSave = creatorAsyncSave:getValue() == true end
        local creatorCompactSave, previousCreatorCompactSave = self:getOption("creatorCompactSave"), values.creatorCompactSave
        if creatorCompactSave ~= nil then values.creatorCompactSave = creatorCompactSave:getValue() == true end
        local creatorSeasonFilter, previousCreatorSeasonFilter = self:getOption("creatorSeasonFilter"), values.creatorSeasonFilter
        if creatorSeasonFilter ~= nil then values.creatorSeasonFilter = creatorSeasonFilter:getValue() == true end
        local talkTheme, previousTalkTheme = self:getOption("talkTheme"), values.talkTheme
        if talkTheme ~= nil then values.talkTheme = talkTheme:getValue() == true end
        values.diagnostics, values.recorder = diagnostics:getValue() == true, recorder:getValue() == true
        if rightClick ~= nil then values.rightClick = rightClick:getValue() == true end
        if fieldRadio ~= nil then values.fieldRadio = fieldRadio:getValue() == true end
        local cinematic, previousCinematic = self:getOption("cinematicTalk"), values.cinematicTalk
        if cinematic ~= nil then values.cinematicTalk = cinematic:getValue() == true end
        if ProjectALife.TalkCinema ~= nil then ProjectALife.TalkCinema.disabled = false end
        if not prefs.persist() then
            values.diagnostics, values.recorder = previousDiagnostics, previousRecorder
            values.rightClick = previousRightClick
            values.fieldRadio = previousFieldRadio
            if fieldRadio ~= nil then fieldRadio:setValue(previousFieldRadio) end
            values.cinematicTalk = previousCinematic
            if cinematic ~= nil then cinematic:setValue(previousCinematic ~= false) end
            values.calm = previousCalm
            if calm ~= nil then calm:setValue(previousCalm ~= false) end
            values.woundPanel = previousWoundPanel
            if woundPanel ~= nil then woundPanel:setValue(previousWoundPanel ~= false) end
            values.repNotify = previousRepNotify
            if repNotify ~= nil then repNotify:setValue(previousRepNotify ~= false) end
            values.repTab = previousRepTab
            if repTab ~= nil then repTab:setValue(previousRepTab ~= false) end
            values.peekDoor = previousPeekDoor
            if peekDoor ~= nil then peekDoor:setValue(previousPeekDoor ~= false) end
            values.peekLive = previousPeekLive
            if peekLive ~= nil then peekLive:setValue(previousPeekLive ~= false) end
            values.peekLens = previousPeekLens
            if peekLens ~= nil then peekLens:setValue(previousPeekLens ~= false) end
            values.peekFull = previousPeekFull
            if peekFull ~= nil then peekFull:setValue(previousPeekFull ~= false) end
            values.creatorAsyncSave = previousCreatorAsyncSave
            if creatorAsyncSave ~= nil then creatorAsyncSave:setValue(previousCreatorAsyncSave ~= false) end
            values.creatorCompactSave = previousCreatorCompactSave
            if creatorCompactSave ~= nil then creatorCompactSave:setValue(previousCreatorCompactSave ~= false) end
            values.creatorSeasonFilter = previousCreatorSeasonFilter
            if creatorSeasonFilter ~= nil then creatorSeasonFilter:setValue(previousCreatorSeasonFilter ~= false) end
            values.talkTheme = previousTalkTheme
            if talkTheme ~= nil then talkTheme:setValue(previousTalkTheme ~= false) end
            diagnostics:setValue(previousDiagnostics)
            recorder:setValue(previousRecorder)
            if rightClick ~= nil then rightClick:setValue(previousRightClick) end
            print("[A-Life] Could not save diagnostics settings.")
            return false
        end
        prefs.followDiagnostics(self, values.diagnostics)
        local radioPanel = ProjectALife.RadioPanel
        if radioPanel ~= nil and type(radioPanel.apply) == "function" then radioPanel.apply() end
        local repTabModule = ProjectALife.RepTab
        if repTabModule ~= nil and type(repTabModule.apply) == "function" then pcall(repTabModule.apply) end
        local rules = ProjectALife.MenuRules
        if rules == nil or type(rules.apply) ~= "function" then return true end

        if not prefs.permitted(player) then
            rules.apply(player, true)
            return true
        end
        local count = type(getNumActivePlayers) == "function" and getNumActivePlayers() or 1
        for index = 0, math.max(1, count) - 1 do
            local subject = type(getSpecificPlayer) == "function" and getSpecificPlayer(index) or nil
            rules.apply(subject)
        end
        return true
    end
    Prefs.syncOptions()
    return true
end

function Prefs.installTab()
    if type(MainOptions) ~= "table" or type(MainOptions.addModOptionsPanel) ~= "function" then return false end
    local hook = ProjectALife.MenuPrefsTab
    if hook ~= nil and (hook.target == MainOptions or MainOptions.addModOptionsPanel == hook.wrapper) then return true end
    hook = { base = MainOptions.addModOptionsPanel, target = MainOptions }
    hook.wrapper = function(screen, ...)
        local prefs = ProjectALife.MenuPrefs
        if prefs == nil or type(prefs.addPanels) ~= "function" then return hook.base(screen, ...) end
        return prefs.addPanels(screen, hook.base, ...)
    end
    ProjectALife.MenuPrefsTab = hook
    MainOptions.addModOptionsPanel = hook.wrapper
    return true
end

function Prefs.tabTitle()
    return ProjectALife.Text.ui("PROJECT A-LIFE")
end

function Prefs.literalPercentLabel(name)
    if type(name) ~= "string" or not string.find(name, "%", 1, true) then return name end
    for _, prefix in ipairs({ "UI_", "Moodles_", "SurvivalGuide_", "Farming_", "IGUI_", "ContextMenu_",
            "GameSound_", "Sandbox_", "Tooltip_", "Challenge_", "MakeUp", "Stash_", "RM_",
            "SurvivorName_", "SurvivorSurname_", "Attributes_", "Fluid_", "Print_Media_", "Print_Text_",
            "EC_", "RD_", "BODYPART_", "MapLabel_", "credits_", "AEBS_" }) do
        if string.sub(name, 1, #prefix) == prefix then return name end
    end
    local parts, index = {}, 1
    while index <= #name do
        local char = string.sub(name, index, index)
        if char == "%" then
            parts[#parts + 1] = "%%"
            if string.sub(name, index + 1, index + 1) == "%" then index = index + 1 end
        else
            parts[#parts + 1] = char
        end
        index = index + 1
    end
    return table.concat(parts)
end

function Prefs.prepareSliderLabels(options)
    local changed = {}
    for _, group in ipairs(options) do
        if type(group.data) == "table" then
            for _, option in ipairs(group.data) do
                for _, field in ipairs({ "name", "tooltip", "text" }) do
                    local value = option[field]
                    local safe = Prefs.literalPercentLabel(value)
                    if safe ~= value then
                        changed[#changed + 1] = { option = option, field = field, value = value }
                        option[field] = safe
                    end
                end
            end
        end
    end
    return changed
end

function Prefs.addPanels(screen, base, ...)
    if Prefs.buildingFor ~= nil and Prefs.buildingFor == screen then return base(screen, ...) end
    local api = PZAPI and PZAPI.ModOptions
    local all = api ~= nil and api.Data or nil
    local ours = api ~= nil and type(api.Dict) == "table" and api.Dict[Prefs.optionsId] or nil
    if type(all) ~= "table" or ours == nil or type(screen) ~= "table"
            or type(screen.addPage) ~= "function" or type(screen.addYesNo) ~= "function"
            or type(screen.addHorizontalLine) ~= "function" or type(screen.gameOptions) ~= "table"
            or type(GameOption) ~= "table" or type(MainOptions) ~= "table" or type(MainOptions.style) ~= "table" then
        return base(screen, ...)
    end
    local others = {}
    for index = 1, #all do
        if all[index] ~= ours then others[#others + 1] = all[index] end
    end
    Prefs.buildingFor = screen
    if #others > 0 then
        local labels = Prefs.prepareSliderLabels(others)
        api.Data = others
        local ok, failure = pcall(base, screen, ...)
        for _, label in ipairs(labels) do label.option[label.field] = label.value end
        api.Data = all
        if not ok then
            Prefs.buildingFor = nil
            error(failure)
        end
    elseif type(api.load) == "function" then

        api:load()
    end
    local built, failure = pcall(Prefs.buildPage, screen, ours)
    Prefs.buildingFor = nil
    Prefs.syncOptions()
    if not built then print("[A-Life] options page: " .. tostring(failure)) end
    return true
end

function Prefs.buildPage(screen, options)
    local style = MainOptions.style
    screen:addPage(Prefs.tabTitle())
    local y = tonumber(style.initialY) or 0
    screen.addY = 0
    local x = screen:getWidth() / 3
    screen:addHorizontalLine(y, getText(options.name))
    for index = 1, #options.data do
        local option = options.data[index]
        if option.type == "tickbox" then Prefs.addTickRow(screen, options, option, x, y)
        elseif option.type == "button" then Prefs.addLinkRow(screen, option, x, y)
        elseif option.type == "description" then Prefs.addNoteRow(screen, option, y) end
    end
    local panel = screen.mainPanel
    if panel ~= nil and type(panel.setScrollHeight) == "function" then
        panel:setScrollHeight(y + (tonumber(screen.addY) or 0) + 20)
    end
    return true
end

function Prefs.addLinkRow(screen, option, x, y)
    if type(screen.addButton) ~= "function" then return nil end
    local button = screen:addButton(x - 20, y, getText(option.name))
    option.element = button
    if type(button.enableAcceptColor) == "function" then button:enableAcceptColor() end
    if type(button.setOnClick) == "function" then button:setOnClick(option.onclick) end
    if option.tooltip and type(button.setTooltip) == "function" then button:setTooltip(getText(option.tooltip)) end
    return button
end

function Prefs.addNoteRow(screen, option, y)
    if type(screen.addDescription) ~= "function" then return nil end
    screen:addDescription(20, y, tostring(option.text))
    return true
end

function Prefs.addTickRow(screen, options, option, x, y)
    local height = MainOptions.style.buttonHeight
    local box = screen:addYesNo(x, y, height, height, getText(option.name))
    if option.tooltip then box.tooltip = getText(option.tooltip) end
    option.element = box
    if not option.isEnabled then box:disableOption("", true) end
    local row = GameOption:new(options.modOptionsID .. "." .. option.id, box)
    function row.toUI(self)
        local prefs = ProjectALife.MenuPrefs
        local value = prefs.optionValue(option.id)
        option.value = value
        self.control:setSelected(1, value)
        if option.id == "diagnostics" then prefs.followDiagnostics(options, value) end
    end
    function row.apply(self)
        local selected = self.control:isSelected(1)
        if option.onChangeApply and option.value ~= selected then option:onChangeApply(selected) end
        option.value = selected
    end
    function row.onChange(self, index, selected)
        if option.id == "diagnostics" then ProjectALife.MenuPrefs.followDiagnostics(options, selected) end
        if option.onChange then option:onChange(selected) end
    end
    screen.gameOptions:add(row)
    return box
end

Prefs.installTab()
if type(Events) == "table" and Events.OnGameBoot ~= nil
        and type(Events.OnGameBoot.Add) == "function" then
    Events.OnGameBoot.Add(Prefs.installTab)
end

Prefs.registerOptions()
if type(Events) == "table" and Events.OnGameStart ~= nil and type(Events.OnGameStart.Add) == "function" then
    Events.OnGameStart.Add(Prefs.warnSlow)
end

return Prefs
