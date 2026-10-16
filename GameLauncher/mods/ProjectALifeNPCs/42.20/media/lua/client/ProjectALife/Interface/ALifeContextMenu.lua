require "ISUI/ISWorldObjectContextMenu"
require "ProjectALife/Interface/ALifeStatusWindow"
require "ProjectALife/Admin/ALifeDebugSpawner"
require "ProjectALife/Admin/ALifeAdminBoot"
require "ProjectALife/Interface/ALifeSquadMap"
require "ProjectALife/World/ALifeEncounters"
require "ProjectALife/Outposts/ALifeOutpostPresets"
require "ProjectALife/Interface/ALifeEncounterCompass"
require "ProjectALife/Interface/ALifeEncounterConsole"
require "ProjectALife/Interface/ALifeMenuPrefs"
require "ProjectALife/Admin/ALifeBlackBox"
require "ProjectALife/Core/ALifeText"
require "ProjectALife/Talk/ALifeTalkUi"
require "ProjectALife/Interface/ALifeSafehouseClient"
require "ProjectALife/Interface/ALifeInjuryMenu"

local Text = ProjectALife.Text

local function debugAllowed(player)
    return ProjectALife.MenuPrefs.allowed(player)
end

local function clickedSquare(worldobjects)
    for _, object in ipairs(type(worldobjects) == "table" and worldobjects or {}) do
        local ok, square = pcall(function() return object:getSquare() end)
        if ok and square ~= nil then return square end
    end
    return nil
end

local function ownedShell(worldobjects, square)
    local function owned(candidate)
        local ok, data = pcall(function() return candidate:getModData() end)
        return ok and type(data) == "table" and data.ProjectALifeOwned == true
            and type(data.ProjectALifeUID) == "string" and candidate or nil
    end
    for _, candidate in ipairs(type(worldobjects) == "table" and worldobjects or {}) do
        local match = owned(candidate)
        if match ~= nil then return match end
    end
    local moving
    pcall(function() moving = square and square:getMovingObjects() end)
    if moving ~= nil then
        local count = 0
        pcall(function() count = moving:size() end)
        for index = 0, count - 1 do
            local candidate
            pcall(function() candidate = moving:get(index) end)
            local match = owned(candidate)
            if match ~= nil then return match end
        end
    end
    return nil
end

local function openCreator()
    if ProjectALife.CreatorScreen == nil then
        pcall(require, "ProjectALife/Interface/Creator/ALifeCreatorScreen")
    end
    local creator = ProjectALife.CreatorScreen
    if creator ~= nil and type(creator.open) == "function" then creator.open() end
end

local function shellFlags(shell)
    local state = { persistent = false, invulnerable = false,
        stationary = false, leashRadius = 0 }
    pcall(function()
        local data = shell:getModData()
        state.uid = data.ProjectALifeUID
        state.persistent = data.ProjectALifeAdminPersistent == true
        state.invulnerable = data.ProjectALifeInvulnerable == true
        state.stationary = data.ProjectALifeAdminStationary == true
        state.leashRadius = math.max(0, math.min(100,
            tonumber(data.ProjectALifeLeashRadius) or 0))
    end)
    return state
end

local function editActorFlag(playerNum, uid, name, value)
    local player = getSpecificPlayer(playerNum)
    if player == nil or type(uid) ~= "string" then return end
    sendClientCommand(player, "ProjectALife", "adminActorFlags", {
        uid = uid,
        flags = { [name] = value },
    })
end

local function checkedOption(menu, label, playerNum, uid, name, current)
    local option = menu:addOption(label, playerNum, editActorFlag,
        uid, name, not current)
    option.checkMark = current == true
    return option
end

local function addActorEditor(menu, playerNum, shell)
    if shell == nil then return end
    local flags = shellFlags(shell)
    if type(flags.uid) ~= "string" then return end
    local editOption = menu:addOption(Text.ui("Edit NPC..."))
    local editMenu = menu:getNew(menu)
    menu:addSubMenu(editOption, editMenu)
    checkedOption(editMenu, Text.ui("Persistent"), playerNum, flags.uid,
        "persistent", flags.persistent)
    checkedOption(editMenu, Text.ui("Invulnerable"), playerNum, flags.uid,
        "invulnerable", flags.invulnerable)
    checkedOption(editMenu, Text.ui("Stationary"), playerNum, flags.uid,
        "stationary", flags.stationary)
    local leashOption = editMenu:addOption(Text.ui("Leash radius..."))
    local leashMenu = editMenu:getNew(editMenu)
    editMenu:addSubMenu(leashOption, leashMenu)
    for _, radius in ipairs({ 0, 10, 25, 50, 100 }) do
        local label = Text.ui("Off")
        if radius ~= 0 then label = Text.ui("{n} tiles", { n = radius }) end
        local option = leashMenu:addOption(label, playerNum, editActorFlag,
            flags.uid, "leashRadius", radius)
        option.checkMark = math.floor(flags.leashRadius + 0.5) == radius
    end
end

local function playMetaEvent(playerNum, kind)
    local player = getSpecificPlayer(playerNum)
    if kind == "siren" then
        local client = ProjectALife.MetaClient
        if client ~= nil then
            client.sessionAlarmPlayed = false

            client.sessionAlarm(true)
        end
        if player ~= nil then player:Say(Text.ui("A-Life: session siren")) end
        return
    end
    if player ~= nil and type(sendClientCommand) == "function" then
        sendClientCommand(player, "ProjectALife", "debugMetaEvent", { kind = kind })
    end
    if player ~= nil then player:Say(Text.ui("A-Life: meta event {kind}", { kind = tostring(kind) })) end
end

local function spawnEncounter(playerNum, square, encounterId)
    ALifeDebugSpawnerWindow.openClassic(playerNum, square, encounterId)
end

local function squadEncounterId()
    local encounters = ProjectALife.Encounters
    if encounters ~= nil and type(encounters.get) == "function" then
        local definition = encounters.get("raid")
        if definition ~= nil then return definition.id end
    end
    return "raid"
end

local function spawnFaction(playerNum, square, factionId)
    ALifeDebugSpawnerWindow.openClassic(playerNum, square, squadEncounterId(), factionId)
end

local function factionCatalog(player, playerNum)
    local spawner = ALifeDebugSpawnerWindow
    for attempt = 1, 2 do
        local catalog = spawner.catalog
        if type(catalog) == "table" and type(catalog.factions) == "table"
                and (#catalog.factions > 0 or catalog.stamp ~= nil) then return catalog.factions end
        if attempt == 2 or player == nil or type(spawner.requestCatalog) ~= "function"
                or spawner.requestCatalog(playerNum or 0) ~= "sent" then
            return nil
        end
    end
    return nil
end

local function addFactionChoices(menu, playerNum, square, callback, presetId)
    local player = getSpecificPlayer(playerNum)
    local factions = factionCatalog(player, playerNum)
    if factions == nil then
        local waiting = menu:addOption(ProjectALife.MenuRules.catalogWaitText(playerNum))
        waiting.notAvailable = true
        return false
    end
    if #factions == 0 then
        local empty = menu:addOption(Text.ui("No faction in the catalog has members"))
        empty.notAvailable = true
        return false
    end
    for _, faction in ipairs(factions) do
        if faction.visitorOnly ~= true then
            menu:addOption(Text.ui(tostring(faction.name)), playerNum, callback, square,
                presetId or faction.id, presetId and faction.id or nil)
        end
    end
    return true
end

local function deleteOutpost(playerNum, square)
    if square == nil or type(sendClientCommand) ~= "function" then return end
    local player = getSpecificPlayer(playerNum)
    if player == nil then return end
    sendClientCommand(player, "ProjectALife", "debugOutpostDelete",
        { x = square:getX(), y = square:getY(), reach = 60 })
end

local function buildOutpost(playerNum, square, presetId, factionId)
    ALifeDebugSpawnerWindow.openClassic(playerNum, square,
        ALifeDebugSpawnerWindow.outpostEncounterId(presetId), factionId)
end

local function addOutpostPreset(menu, label, presetId, playerNum, square)
    local option = menu:addOption(label)
    local submenu = menu:getNew(menu)
    menu:addSubMenu(option, submenu)

    submenu:addOption(Text.ui("Automatic faction"), playerNum, buildOutpost, square,
        presetId, nil)
    local factions = factionCatalog(getSpecificPlayer(playerNum), playerNum)
    if factions == nil then
        local waiting = submenu:addOption(ProjectALife.MenuRules.catalogWaitText(playerNum))
        waiting.notAvailable = true
        return
    end
    for _, faction in ipairs(factions) do
        if faction.visitorOnly ~= true then
            submenu:addOption(Text.ui(tostring(faction.name)), playerNum, buildOutpost,
                square, presetId, faction.id)
        end
    end
end

local function addDiagnostics(menu, playerNum)
    local diagnosticsOption = menu:addOption(Text.ui("Diagnostics..."))
    local diagnostics = menu:getNew(menu)
    menu:addSubMenu(diagnosticsOption, diagnostics)
    diagnostics:addOption(Text.ui("Toggle encounter arrows"), playerNum,
        function(playerIndex)
            local compass = ProjectALife.EncounterCompass
            if compass ~= nil then compass.toggle(playerIndex) end
        end)
    diagnostics:addOption(Text.ui("Toggle A-Life squads on world map"), playerNum,
        function(playerIndex)
            local squadMap = ProjectALife.SquadMap
            if squadMap ~= nil then squadMap.toggle(playerIndex) end
        end)
    diagnostics:addOption(Text.ui("Dump module QA to console.txt"), playerNum,
        function(playerIndex)
            local subject = getSpecificPlayer(playerIndex)
            if subject ~= nil then
                sendClientCommand(subject, "ProjectALife", "debugModuleQA", {})
            end
        end)

    diagnostics:addOption(Text.ui("Silence world audio (stuck helicopter)"), playerNum,
        function(playerIndex)
            local subject = getSpecificPlayer(playerIndex)
            local stopped = 0

            pcall(function()
                local meta = ProjectALife.MetaClient
                if meta ~= nil and type(meta.reset) == "function" then
                    stopped = stopped + #(meta.active or {})
                    meta.reset()
                end
            end)

            pcall(function()
                local support = ProjectALife.SupportClient
                if support == nil then return end
                if support.heli ~= nil then stopped = stopped + 1 end
                if type(support.reset) == "function" then support.reset()
                elseif type(support.stopHeli) == "function" then support.stopHeli() end
            end)

            pcall(function()
                local raid = ProjectALife.RaidClient
                if raid ~= nil and type(raid.reset) == "function" then raid.reset() end
            end)
            if subject ~= nil then
                subject:Say(Text.ui("A-Life: world audio silenced ({n})", { n = stopped }))
            end
        end)
    diagnostics:addOption(Text.ui("Dump NPC blackbox to console.txt"), playerNum,
        function(playerIndex)
            local subject = getSpecificPlayer(playerIndex)
            if subject ~= nil then
                sendClientCommand(subject, "ProjectALife", "debugBlackbox", {})
            end
        end)

    diagnostics:addOption(Text.ui("Dump town census to console.txt"), playerNum,
        function(playerIndex)
            local subject = getSpecificPlayer(playerIndex)
            if subject ~= nil then
                sendClientCommand(subject, "ProjectALife", "debugTownCensus", {})
            end
        end)
    diagnostics:addOption(Text.ui("Make this building picked over"), playerNum,
        function(playerIndex)
            local subject = getSpecificPlayer(playerIndex)
            if subject ~= nil then
                sendClientCommand(subject, "ProjectALife", "debugPickedOver", { action = "mark", level = 3 })
            end
        end)
    diagnostics:addOption(Text.ui("Picked-over state of this building"), playerNum,
        function(playerIndex)
            local subject = getSpecificPlayer(playerIndex)
            if subject ~= nil then
                sendClientCommand(subject, "ProjectALife", "debugPickedOver", { action = "info" })
            end
        end)
end

ProjectALife.MenuRules = ProjectALife.MenuRules or {}

function ProjectALife.MenuRules.catalogReasonText(reason, playerNum)
    if reason == "admin_required" then return Text.ui("the server does not list you as an admin") end
    if reason == "diagnostics_disabled" then
        return ProjectALife.MenuPrefs.refusedText(getSpecificPlayer(playerNum or 0))
    end
    if reason == "catalog_unavailable" then return Text.ui("the server could not load its catalog") end
    if reason == "faction_not_found" then return Text.ui("that faction is no longer in the catalog") end
    if reason == "timed_out" then return Text.ui("no answer from the server") end
    return tostring(reason or "unknown")
end

function ProjectALife.MenuRules.catalogWaitText(playerNum)
    local spawner = ALifeDebugSpawnerWindow
    local status = type(spawner) == "table" and type(spawner.catalogStatus) == "function"
        and spawner.catalogStatus() or {}
    local reason = status.reason
    if reason == nil or reason == "rate_limited" then
        return Text.ui("Loading factions ({n}s) - reopen this menu", { n = status.seconds or 0 })
    end
    if reason == "diagnostics_disabled" then
        return ProjectALife.MenuRules.catalogReasonText(reason, playerNum)
    end
    if reason == "timed_out" and status.pending then
        return Text.ui("No answer from the server - asking again (try {n})", { n = status.attempts or 1 })
    end
    if reason == "timed_out" then
        return Text.ui("No answer from the server after {n} tries - reopen to retry", { n = status.attempts or 1 })
    end
    return Text.ui("Factions refused: {reason}",
        { reason = ProjectALife.MenuRules.catalogReasonText(reason, playerNum) })
end

function ProjectALife.MenuRules.confirmThen(playerNum, text, callback, square)
    local console = ProjectALife.AdminConsole
    if console == nil or type(console.confirm) ~= "function" then return false end
    return console.confirm(playerNum, text, function() callback(playerNum, square) end)
end

function ProjectALife.MenuRules.openConsole(playerNum, square)
    local console = ProjectALife.AdminConsole
    if console == nil then return ALifeDebugSpawnerWindow.openClassic(playerNum, square, nil) end
    local window = console.open(playerNum, { square = square })
    if window == nil then return ALifeDebugSpawnerWindow.openClassic(playerNum, square, nil) end
    return window
end

function ProjectALife.MenuRules.setSpawnTarget(playerNum, square)
    local console = ProjectALife.AdminConsole
    if console == nil then return false end
    return console.setSpot(playerNum, square)
end

function ProjectALife.MenuRules.purgeRadius(playerNum, reach, square)
    local subject = getSpecificPlayer(playerNum)
    if subject == nil or type(sendClientCommand) ~= "function" then return end
    local ox, oy = subject:getX(), subject:getY()
    if square ~= nil then
        pcall(function() ox, oy = square:getX(), square:getY() end)
    end
    sendClientCommand(subject, "ProjectALife", "debugPurgeActors", { radius = reach, x = ox, y = oy })
    subject:Say(Text.ui("A-Life: removing actors within {n} tiles", { n = reach }))
end

function ProjectALife.MenuRules.purgeEverything(playerNum)
    local subject = getSpecificPlayer(playerNum)
    if subject == nil or type(sendClientCommand) ~= "function" then return end
    sendClientCommand(subject, "ProjectALife", "debugPurgeActors", {})
    subject:Say(Text.ui("A-Life: removing every actor"))
end

function ProjectALife.MenuRules.purgeSquads(playerNum)
    local subject = getSpecificPlayer(playerNum)
    if subject == nil or type(sendClientCommand) ~= "function" then return end
    sendClientCommand(subject, "ProjectALife", "debugSquadDelete", { all = true })
    subject:Say(Text.ui("A-Life: removing every squad"))
end

function ProjectALife.MenuRules.resetCreator(playerNum)
    local subject = getSpecificPlayer(playerNum)
    if subject == nil or type(sendClientCommand) ~= "function" then return end
    sendClientCommand(subject, "ProjectALife", "debugResetCreator", {})
    subject:Say(Text.ui("A-Life: custom profiles and factions cleared"))
end

function ProjectALife.MenuRules.creatorAllowed(playerNum)
    if type(isClient) ~= "function" then return false end
    local okClient, client = pcall(isClient)
    if not okClient then return false end
    if client ~= true then return true end
    if type(isAdmin) == "function" then
        local okAdmin, admin = pcall(isAdmin)
        if okAdmin and admin == true then return true end
    end
    if type(getSpecificPlayer) ~= "function" then return false end
    local player = getSpecificPlayer(playerNum or 0)
    if player == nil or type(player.getAccessLevel) ~= "function" then return false end
    local okLevel, level = pcall(player.getAccessLevel, player)
    return okLevel and string.lower(tostring(level or "")) == "admin"
end

function ProjectALife.MenuRules.addCreator(menu, playerNum)
    local option = menu:addOption(Text.ui("Open faction & NPC Creator"), playerNum, openCreator)
    if not ProjectALife.MenuRules.creatorAllowed(playerNum) then
        option.notAvailable = true
        if ISToolTip ~= nil then
            local tooltip = ISToolTip:new()
            tooltip.description = Text.ui("Only a server admin can change factions and NPCs here.")
            option.toolTip = tooltip
        end
    end
    return option
end

ProjectALife.MenuRules.creatorKey = "ALife_OpenCreator"
ProjectALife.MenuRules.statusKey = "ALife_WorldStatus"

function ProjectALife.MenuRules.registerKeys()
    if type(keyBinding) ~= "table" or type(Keyboard) ~= "table" then return false end
    for _, bind in ipairs(keyBinding) do
        if bind.value == ProjectALife.MenuRules.creatorKey then return true end
    end
    table.insert(keyBinding, { value = "[ProjectALife]" })
    table.insert(keyBinding, { value = ProjectALife.MenuRules.creatorKey, key = Keyboard.KEY_INSERT })
    table.insert(keyBinding, { value = ProjectALife.MenuRules.statusKey, key = Keyboard.KEY_HOME })
    return true
end

function ProjectALife.MenuRules.onKeyPressed(key)
    if key == nil or key == 0 or type(getCore) ~= "function" then return false end
    local core = getCore()
    if core == nil or type(core.isKey) ~= "function" then return false end
    if core:isKey(ProjectALife.MenuRules.creatorKey, key) then return ProjectALife.MenuRules.openCreatorKey(0) end
    if core:isKey(ProjectALife.MenuRules.statusKey, key) then return ProjectALife.MenuRules.openStatus(0) end
    return false
end

function ProjectALife.MenuRules.openCreatorKey(playerNum)
    local creator = ProjectALife.CreatorScreen
    if creator ~= nil and creator.window ~= nil then return false end
    if not ProjectALife.MenuRules.creatorAllowed(playerNum) then
        local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(playerNum or 0) or nil
        if player ~= nil and type(player.Say) == "function" then
            player:Say(Text.ui("Only a server admin can change factions and NPCs here."))
        end
        return false
    end
    openCreator()
    return true
end

function ProjectALife.MenuRules.openStatus(playerNum)
    if type(ALifeStatusWindow) ~= "table" or type(ALifeStatusWindow.toggle) ~= "function" then return false end
    if type(getSpecificPlayer) ~= "function" or getSpecificPlayer(playerNum or 0) == nil then return false end
    ALifeStatusWindow.toggle(playerNum or 0)
    return true
end

function ProjectALife.MenuRules.leavePause()
    local screen = MainScreen and MainScreen.instance or nil
    if screen == nil or screen.inGame ~= true or type(screen.isVisible) ~= "function" or not screen:isVisible() then return end
    if type(ToggleEscapeMenu) == "function" and type(KeybindId) == "table" and type(getCore) == "function" then
        ToggleEscapeMenu(getCore():getKey(KeybindId.MAIN_MENU))
    end
end

function ProjectALife.MenuRules.pauseHit(button)
    if button == nil then return false end
    if button.enable == false or button.visible == false then return false end
    if type(button.getIsVisible) == "function" and button:getIsVisible() ~= true then return false end
    if type(button.isMouseOver) == "function" and button:isMouseOver() ~= true then return false end
    return true
end

function ProjectALife.MenuRules.pauseStatus(_, button)
    if not ProjectALife.MenuRules.pauseHit(button) then return false end
    ProjectALife.MenuRules.leavePause()
    return ProjectALife.MenuRules.openStatus(0)
end

function ProjectALife.MenuRules.pauseCreator(_, button)
    if not ProjectALife.MenuRules.pauseHit(button) then return false end
    return ProjectALife.MenuRules.openCreatorKey(0)
end

ProjectALife.MenuRules.pauseBox = { width = 220, height = 26, gap = 6, top = 24, right = 24 }

function ProjectALife.MenuRules.placePause(button, x, y)
    if button == nil then return end
    if type(button.setX) == "function" then button:setX(x) else button.x = x end
    if type(button.setY) == "function" then button:setY(y) else button.y = y end
end

function ProjectALife.MenuRules.layoutPause(access)
    if access == nil or access.status == nil then return end
    local box = ProjectALife.MenuRules.pauseBox
    local x = getCore():getScreenWidth() - box.width - box.right
    ProjectALife.MenuRules.placePause(access.status, x, box.top)
    ProjectALife.MenuRules.placePause(access.creator, x, box.top + box.height + box.gap)
end

function ProjectALife.MenuRules.attachPauseMenu()
    local screen = MainScreen and MainScreen.instance or nil
    if screen == nil or screen.inGame ~= true or screen.alifeAccess ~= nil then return false end
    if type(ISButton) ~= "table" or type(getCore) ~= "function" then return false end
    local box = ProjectALife.MenuRules.pauseBox
    local access = {}
    access.status = ISButton:new(0, 0, box.width, box.height, Text.ui("A-Life world status"), access,
        ProjectALife.MenuRules.pauseStatus)
    access.creator = ISButton:new(0, 0, box.width, box.height, Text.ui("A-Life Creator"), access,
        ProjectALife.MenuRules.pauseCreator)
    for _, button in ipairs({ access.status, access.creator }) do
        button:initialise()
        button:instantiate()
        screen:addChild(button)
    end
    access.status.onEnterFromGame = function() ProjectALife.MenuRules.refreshPauseMenu(access) end
    screen.alifeAccess = access
    ProjectALife.MenuRules.refreshPauseMenu(access)
    return true
end

function ProjectALife.MenuRules.refreshPauseMenu(access)
    if access == nil or access.creator == nil then return end
    local allowed = ProjectALife.MenuRules.creatorAllowed(0)
    access.creator.enable = allowed
    access.creator:setVisible(allowed)
    ProjectALife.MenuRules.layoutPause(access)
end

function ProjectALife.MenuRules.dropTools(player)
    local prefs = ProjectALife.MenuPrefs
    if player ~= nil and prefs ~= nil and prefs.allowed(player) then return false end
    local compass = ProjectALife.EncounterCompass
    if compass ~= nil and type(compass.hide) == "function" then compass.hide() end
    local squadMap = ProjectALife.SquadMap
    if squadMap ~= nil and type(squadMap.hide) == "function" then squadMap.hide() end
    local spawner = ALifeDebugSpawnerWindow
    if type(spawner) == "table" and spawner.instance ~= nil and type(spawner.instance.close) == "function" then
        spawner.instance:close()
    end
    local adminConsole = ProjectALife.AdminConsole
    if adminConsole ~= nil and type(adminConsole.closeAll) == "function" then adminConsole.closeAll() end
    local console = ProjectALife.EncounterConsole
    if console ~= nil and type(console.closeInstance) == "function" then console.closeInstance() end
    local status = ALifeStatusWindow
    if type(status) == "table" and status.instance ~= nil and type(status.instance.close) == "function" then
        status.instance:close()
    end
    return true
end

function ProjectALife.MenuRules.apply(player, quiet)
    local prefs = ProjectALife.MenuPrefs
    local permitted = player ~= nil and prefs.permitted(player)
    local recorder = permitted and prefs.recorder()
    local box = ProjectALife.BlackBox
    if box ~= nil then
        if type(box.setEnabled) == "function" then box.setEnabled(recorder)
        else box.enabled = recorder end
    end
    ProjectALife.MenuRules.dropTools(player)
    if player == nil or quiet == true then return false end
    local payload = { enabled = permitted and prefs.diagnostics() == true, recorder = recorder }

    if type(isClient) == "function" and isClient()
            and type(sendClientCommand) == "function" then
        sendClientCommand(player, "ProjectALife", "alifeDiagnostics", payload)
        return true
    end
    local service = ProjectALife.DebugService
    if service ~= nil and type(service.handle) == "function" then
        service.handle("ProjectALife", "alifeDiagnostics", player, payload)
        return true
    end
    return false
end

local function fill(playerNum, context, worldobjects, test)
    local prefs = ProjectALife.MenuPrefs
    if prefs == nil or type(prefs.rightClickOn) ~= "function" or not prefs.rightClickOn() then return end
    if test then
        local subject = getSpecificPlayer(playerNum)
        if subject == nil or not prefs.safehouseTools(subject) then return end
        if ISWorldObjectContextMenu and type(ISWorldObjectContextMenu.setTest) == "function" then
            return ISWorldObjectContextMenu.setTest()
        end
        return true
    end
    if type(context) ~= "table" or type(context.addOption) ~= "function"
            or type(context.getNew) ~= "function" or type(context.addSubMenu) ~= "function" then
        return
    end
    local player = getSpecificPlayer(playerNum)
    if player == nil then return end
    if not debugAllowed(player) then
        if not prefs.safehouseTools(player) then return end
        local lite = context:addOption(Text.ui("[A-LIFE] Project A-Life"))
        local liteMenu = context:getNew(context)
        context:addSubMenu(lite, liteMenu)
        if ProjectALife.SafehouseClient ~= nil then
            ProjectALife.SafehouseClient.addMenu(liteMenu, playerNum, clickedSquare(worldobjects))
        end
        local more = liteMenu:addOption(Text.ui("More tools: tick Diagnostics in Options > Project A-Life"))
        more.notAvailable = true
        return
    end

    ProjectALife.MenuPrefs.reannounce(player,
        type(getTimestampMs) == "function" and getTimestampMs() or 0)

    local square = clickedSquare(worldobjects)

    local root = context:addOption(Text.ui("[A-LIFE] Project A-Life"))
    pcall(function()
        root.iconTexture = getTexture("media/textures/ProjectALifeIcon.png")
    end)
    local menu = context:getNew(context)
    context:addSubMenu(root, menu)
    ProjectALife.MenuRules.addCreator(menu, playerNum)
    menu:addOption(Text.ui("Admin console..."), playerNum, ProjectALife.MenuRules.openConsole, square)

    menu:addOption(Text.ui("Runtime status"), playerNum, ALifeStatusWindow.toggle)
    addDiagnostics(menu, playerNum)
    if ProjectALife.SafehouseClient ~= nil then ProjectALife.SafehouseClient.addMenu(menu, playerNum, square) end
    addActorEditor(menu, playerNum, ownedShell(worldobjects, square))
    if ProjectALife.InjuryMenu ~= nil then
        ProjectALife.InjuryMenu.addDebug(menu, playerNum, ownedShell(worldobjects, square))
    end
    menu:addOption(Text.ui("Open classic spawn panel"), playerNum,
        ALifeDebugSpawnerWindow.openClassic, square, nil)
    menu:addOption(Text.ui("Delete nearest outpost"), playerNum, ProjectALife.MenuRules.confirmThen,
        Text.ui("Delete the nearest outpost and everyone staffing it?"), deleteOutpost, square)
    local outpostOption = menu:addOption(Text.ui("Build staffed outpost here..."))
    local outpostMenu = menu:getNew(menu)
    menu:addSubMenu(outpostOption, outpostMenu)
    for _, preset in ipairs(ProjectALife.OutpostPresets.list or {}) do
        addOutpostPreset(outpostMenu, Text.ui(preset.label), preset.id, playerNum, square)
    end
    menu:addOption(Text.ui("Configure full-scale raid..."), playerNum,
        spawnEncounter, square, "fullscale_raid")

    local metaOption = menu:addOption(Text.ui("Play a meta event here..."))
    local metaMenu = menu:getNew(menu)
    menu:addSubMenu(metaOption, metaMenu)
    for _, entry in ipairs({
        { "Distant gunfire", "gunfire" },
        { "Helicopter", "heli" },
        { "Car crash", "crash" },
        { "Ambience (siren, scream, radio)", "ambience" },
        { "Session siren", "siren" },
    }) do
        metaMenu:addOption(Text.ui(entry[1]), playerNum, playMetaEvent, entry[2])
    end

    local removeOption = menu:addOption(Text.ui("Remove NPCs..."))
    local removeMenu = menu:getNew(menu)
    menu:addSubMenu(removeOption, removeMenu)
    for _, reach in ipairs({ 15, 40, 100 }) do
        removeMenu:addOption(Text.ui("Within {n} tiles of here", { n = reach }),
            playerNum, ProjectALife.MenuRules.confirmThen,
            Text.ui("Remove every A-Life NPC within {n} tiles of here?", { n = reach }),
            function(playerIndex, clicked) ProjectALife.MenuRules.purgeRadius(playerIndex, reach, clicked) end, square)
    end
    removeMenu:addOption(Text.ui("Every A-Life NPC on the map"), playerNum, ProjectALife.MenuRules.confirmThen,
        Text.ui("Remove EVERY A-Life NPC in the world? Saved squads are lost too."), ProjectALife.MenuRules.purgeEverything)
    removeMenu:addOption(Text.ui("Every squad on the map"), playerNum, ProjectALife.MenuRules.confirmThen,
        Text.ui("Delete EVERY squad on the map?"), ProjectALife.MenuRules.purgeSquads)
    menu:addOption(Text.ui("Reset creator overrides"), playerNum, ProjectALife.MenuRules.confirmThen,
        Text.ui("Reset the Creator? This deletes every custom profile and faction on this world."),
        ProjectALife.MenuRules.resetCreator)
end

if type(Events) == "table" and Events.OnPreFillWorldObjectContextMenu ~= nil then
    Events.OnPreFillWorldObjectContextMenu.Add(ProjectALife.TalkUi.guarded(fill))
end

ProjectALife.MenuRules.registerKeys()
if type(Events) == "table" and Events.OnKeyPressed ~= nil
        and type(Events.OnKeyPressed.Add) == "function" then
    Events.OnKeyPressed.Add(ProjectALife.MenuRules.onKeyPressed)
end
if type(Events) == "table" and Events.OnGameStart ~= nil
        and type(Events.OnGameStart.Add) == "function" then
    Events.OnGameStart.Add(ProjectALife.MenuRules.attachPauseMenu)
end

if type(Events) == "table" and Events.OnCreatePlayer ~= nil then
    Events.OnCreatePlayer.Add(function(playerIndex, player)

        ProjectALife.MenuPrefs.resetAnnounce()
        ProjectALife.MenuRules.apply(player or getSpecificPlayer(playerIndex or 0))
    end)
end

return true
