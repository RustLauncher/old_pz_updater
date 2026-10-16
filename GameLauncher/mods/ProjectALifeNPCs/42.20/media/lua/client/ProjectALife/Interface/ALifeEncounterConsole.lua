require "ISUI/ISCollapsableWindow"
require "ISUI/ISPanel"
require "ProjectALife/World/ALifeEncounters"
require "ProjectALife/Interface/ALifeEncounterCompass"
require "ProjectALife/Interface/ALifeMenuPrefs"

ProjectALife = ProjectALife or {}

local Console = ISCollapsableWindow:derive("ALifeEncounterConsole")
ProjectALife.EncounterConsole = Console
Console.instance = nil

local ACCENT = { r = 0.72, g = 0.55, b = 0.32, a = 0.95 }
local TEXT = { r = 0.92, g = 0.91, b = 0.88, a = 1 }
local MUTED = { r = 0.68, g = 0.69, b = 0.68, a = 1 }
local PANEL = { r = 0.055, g = 0.060, b = 0.064, a = 0.94 }
local ROW = { r = 0.085, g = 0.090, b = 0.095, a = 0.90 }
local ROW_ON = { r = 0.17, g = 0.135, b = 0.09, a = 0.95 }
local LINE = { r = 0.30, g = 0.32, b = 0.33, a = 0.85 }

local STANCE_COLOR = {
    blockade = { r = 0.95, g = 0.55, b = 0.22 },
    garrison = { r = 0.42, g = 0.70, b = 0.98 },
    occupy_high = { r = 0.72, g = 0.45, b = 0.95 },
    defend = { r = 0.35, g = 0.85, b = 0.55 },
    route = { r = 0.95, g = 0.85, b = 0.35 },
    repair = { r = 0.90, g = 0.40, b = 0.55 },
    camp = { r = 0.94, g = 0.68, b = 0.30 },
}
local STANCE_LABEL = {
    blockade = "HOLDS A LINE",
    garrison = "HOLDS A BUILDING",
    occupy_high = "HOLDS A FLOOR", defend = "HOLDS A PLACE",
    route = "WALKS A CIRCUIT", repair = "WORKS ON A CAR",
    camp = "LIVES AT A CAMP",
}

local function copyPoint(point)
    if type(point) ~= "table" then return nil end
    local x, y, z = tonumber(point.x), tonumber(point.y), tonumber(point.z)
    if x == nil or y == nil then return nil end
    return { x = x, y = y, z = z or 0 }
end

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function send(playerNum, command, arguments)
    local player = getSpecificPlayer(playerNum)
    if player == nil or type(sendClientCommand) ~= "function" then return false end
    sendClientCommand(player, "ProjectALife", command, arguments or {})
    return true
end

local List = ISPanel:derive("ALifeConsoleList")

function List:new(x, y, width, height, onPick)
    local panel = ISPanel.new(self, x, y, width, height)
    panel.rows = {}
    panel.selected = nil
    panel.scroll = 0
    panel.onPick = onPick
    panel.rowHeight = 30
    panel.background = false
    return panel
end

function List:setRows(rows)
    self.rows = type(rows) == "table" and rows or {}
    if self.selected ~= nil and self.selected > #self.rows then
        self.selected = nil
    end
    if self.selected == nil and #self.rows > 0 then
        self.selected = 1
        if type(self.onPick) == "function" then self.onPick(self.rows[1]) end
    end
end

function List:selectedRow()
    if self.selected == nil then return nil end
    return self.rows[self.selected]
end

function List:onMouseWheel(delta)
    local visible = math.floor(self.height / self.rowHeight)
    local maximum = math.max(0, #self.rows - visible)
    self.scroll = math.max(0, math.min(maximum, self.scroll + delta))
    return true
end

function List:onMouseUp(x, y)
    local index = self.scroll + math.floor(y / self.rowHeight) + 1
    if self.rows[index] == nil then return false end
    self.selected = index
    if type(self.onPick) == "function" then self.onPick(self.rows[index]) end
    return true
end

function List:render()
    self:drawRect(0, 0, self.width, self.height, PANEL.a, PANEL.r, PANEL.g, PANEL.b)
    self:drawRectBorder(0, 0, self.width, self.height, LINE.a, LINE.r, LINE.g, LINE.b)
    local visible = math.floor(self.height / self.rowHeight)
    for offset = 0, visible - 1 do
        local index = self.scroll + offset + 1
        local row = self.rows[index]
        if row ~= nil then
            local y = offset * self.rowHeight
            local on = index == self.selected
            local fill = on and ROW_ON or ROW
            self:drawRect(2, y + 2, self.width - 4, self.rowHeight - 4,
                fill.a, fill.r, fill.g, fill.b)
            if on then
                self:drawRectBorder(2, y + 2, self.width - 4, self.rowHeight - 4,
                    ACCENT.a, ACCENT.r, ACCENT.g, ACCENT.b)
            end
            local badge = row.badgeColor
            local textX = 10
            if badge ~= nil then
                self:drawRect(8, y + 9, 8, 12, 0.95, badge.r, badge.g, badge.b)
                textX = 24
            end
            local color = on and TEXT or MUTED
            self:drawText(tostring(row.label or "?"), textX, y + 4,
                color.r, color.g, color.b, 1, UIFont.Small)
            if row.detail ~= nil then
                self:drawText(tostring(row.detail), textX, y + 16,
                    MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
            end
        end
    end
    if #self.rows == 0 then
        self:drawText("(empty)", 10, 8, MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
    end
end

function Console.open(playerNum, targetPosition)

    local prefs = ProjectALife.MenuPrefs
    if prefs ~= nil and type(prefs.allowed) == "function"
            and not prefs.allowed(getSpecificPlayer(playerNum)) then
        return nil
    end
    local spawner = ALifeDebugSpawnerWindow
    if spawner ~= nil and type(spawner.open) == "function" then
        return spawner.open(playerNum, targetPosition)
    end
    return Console.openLegacy(playerNum, targetPosition)
end

function Console.openLegacy(playerNum, targetPosition)
    local existing = Console.instance
    if existing ~= nil then
        existing.playerNum = playerNum or existing.playerNum or 0
        existing.targetPosition = copyPoint(targetPosition)
        existing:setVisible(true)
        existing:bringToTop()
        existing:refresh()
        return existing
    end
    local width = math.min(720, getCore():getScreenWidth() - 30)
    local height = math.min(520, getCore():getScreenHeight() - 30)
    local window = Console:new(
        math.floor((getCore():getScreenWidth() - width) / 2),
        math.floor((getCore():getScreenHeight() - height) / 2), width, height)
    window.playerNum = playerNum or 0
    window.targetPosition = copyPoint(targetPosition)
    window:initialise()
    window:addToUIManager()
    Console.instance = window
    window:refresh()
    return window
end

function Console:new(x, y, width, height)
    local window = ISCollapsableWindow.new(self, x, y, width, height)
    window.title = "A-LIFE  ::  ENCOUNTER CONSOLE"
    window:setResizable(false)
    window.playerNum = 0
    window.factions = {}
    window.encounters = {}
    window.count = 0
    window.persistent = nil
    window.advancedOpen = false
    window.message = "Choose a squad and encounter, then deploy both with one action."
    window.messageColor = MUTED
    window.director = nil
    window.marks = {}
    return window
end

function Console:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top = 42
    local gap = 12
    local available = self.width - gap * 4
    local factionW = math.floor(available * 0.30)
    local encounterW = math.floor(available * 0.36)
    local actionW = available - factionW - encounterW
    local factionX = gap
    local encounterX = gap * 2 + factionW
    local actionX = gap * 3 + factionW + encounterW
    self.factionX, self.encounterX, self.actionX = factionX, encounterX, actionX

    self.factionList = List:new(factionX, top + 20, factionW, 210, function(row)
        self.message = "Faction: " .. tostring(row.label)
        self.messageColor = MUTED
    end)
    self.factionList:initialise()
    self:addChild(self.factionList)

    self.encounterList = List:new(encounterX, top + 20, encounterW, 210,
        function(row)
            self.count = 0
            self.persistent = nil
            self.message = tostring(row.summary or row.label)
            self.messageColor = MUTED
        end)
    self.encounterList:initialise()
    self:addChild(self.encounterList)

    local right, rightW = actionX, actionW

    self.primaryButton = ISButton:new(right, top + 20, rightW, 34,
        "SPAWN ENCOUNTER + SQUAD", self, Console.onSpawnEncounter)
    self.primaryButton:initialise()
    self.primaryButton:instantiate()
    self.primaryButton.backgroundColor = { r = 0.20, g = 0.15, b = 0.09, a = 0.98 }
    self.primaryButton.backgroundColorMouseOver = { r = 0.28, g = 0.21, b = 0.12, a = 1 }
    self.primaryButton.borderColor = ACCENT
    self:addChild(self.primaryButton)

    self.advancedToggle = ISButton:new(right, top + 62, rightW, 24,
        "ADVANCED OPTIONS  >", self, Console.onToggleAdvanced)
    self.advancedToggle:initialise()
    self.advancedToggle:instantiate()
    self:addChild(self.advancedToggle)

    self.hereButton = ISButton:new(right, top + 92, rightW, 20,
        "SIMULATE HERE", self, Console.onSimulateHere)
    self.hereButton:initialise()
    self.hereButton:instantiate()
    self:addChild(self.hereButton)

    self.ruleButton = ISButton:new(right, top + 116, rightW, 20,
        "SIMULATE BY RULE", self, Console.onSimulateByRule)
    self.ruleButton:initialise()
    self.ruleButton:instantiate()
    self:addChild(self.ruleButton)

    self.squadButton = ISButton:new(right, top + 140, rightW, 20,
        "SPAWN FACTION SQUAD", self, Console.onSpawnSquad)
    self.squadButton:initialise()
    self.squadButton:instantiate()
    self:addChild(self.squadButton)

    self.countUp = ISButton:new(right, top + 164, 26, 20, "+", self, Console.onCountUp)
    self.countUp:initialise(); self.countUp:instantiate(); self:addChild(self.countUp)
    self.countDown = ISButton:new(right + 30, top + 164, 26, 20, "-", self, Console.onCountDown)
    self.countDown:initialise(); self.countDown:instantiate(); self:addChild(self.countDown)

    self.persistToggle = ISButton:new(right, top + 188, rightW, 20,
        "PERSISTENT: DEFAULT", self, Console.onTogglePersistent)
    self.persistToggle:initialise(); self.persistToggle:instantiate()
    self:addChild(self.persistToggle)

    local debugY = top + 250
    local debugGap = 8
    local debugW = math.floor((self.width - gap * 2 - debugGap * 3) / 4)
    self.arrowsButton = ISButton:new(gap, debugY, debugW, 24,
        "ENCOUNTER ARROWS", self, Console.onToggleArrows)
    self.arrowsButton:initialise(); self.arrowsButton:instantiate()
    self:addChild(self.arrowsButton)

    self.mapButton = ISButton:new(gap + debugW + debugGap, debugY, debugW, 24,
        "SQUADS ON WORLD MAP", self, Console.onToggleMap)
    self.mapButton:initialise(); self.mapButton:instantiate()
    self:addChild(self.mapButton)

    self.blackboxButton = ISButton:new(gap + (debugW + debugGap) * 2,
        debugY, debugW, 24,
        "BLACK BOX DUMP", self, Console.onBlackbox)
    self.blackboxButton:initialise(); self.blackboxButton:instantiate()
    self:addChild(self.blackboxButton)

    self.qaButton = ISButton:new(gap + (debugW + debugGap) * 3,
        debugY, debugW, 24,
        "MODULE QA DUMP", self, Console.onModuleQA)
    self.qaButton:initialise(); self.qaButton:instantiate()
    self:addChild(self.qaButton)

    self.refreshButton = ISButton:new(self.width - 110, self.height - 32, 98, 24,
        "REFRESH", self, Console.onRefresh)
    self.refreshButton:initialise(); self.refreshButton:instantiate()
    self:addChild(self.refreshButton)

    self.advancedControls = { self.hereButton, self.ruleButton, self.squadButton,
        self.countUp, self.countDown, self.persistToggle }
    self:populateEncounters()
    self:applyAdvancedVisibility()
end

function Console:applyAdvancedVisibility()
    local advanced = self.advancedOpen == true
    for _, control in ipairs(self.advancedControls or {}) do control:setVisible(advanced) end
    if self.advancedToggle then
        self.advancedToggle:setTitle(advanced
            and "ADVANCED OPTIONS  v"
            or "ADVANCED OPTIONS  >")
    end
end

function Console:onToggleAdvanced()
    self.advancedOpen = not self.advancedOpen
    self:applyAdvancedVisibility()
end

function Console:populateEncounters(specifications)
    local rows = {}
    if type(specifications) == "table" and #specifications > 0 then
        for _, entry in ipairs(specifications) do
            local stance = entry.stance
            local amount = tostring(entry.minCount or "?") .. "-"
                .. tostring(entry.maxCount or "?") .. " NPCs"
            rows[#rows + 1] = {
                id = entry.id,
                label = tostring(entry.label or entry.id),
                detail = (stance ~= nil and (STANCE_LABEL[stance] or stance)
                    or "FIGHTS AND MOVES") .. "  |  " .. amount,
                badgeColor = stance ~= nil and STANCE_COLOR[stance] or nil,
                summary = entry.summary,
                definition = entry,
            }
        end
    else
        local encounters = ProjectALife.Encounters
        if encounters ~= nil and type(encounters.list) == "function" then
        for _, entry in ipairs(encounters.list()) do
            local definition = type(encounters.get) == "function"
                and encounters.get(entry.id) or nil
            local stance = definition ~= nil and definition.stance or nil
            rows[#rows + 1] = {
                id = entry.id,
                label = tostring(entry.label or entry.id),
                detail = stance ~= nil and (STANCE_LABEL[stance] or stance)
                    or "FIGHTS AND MOVES",
                badgeColor = stance ~= nil and STANCE_COLOR[stance] or nil,
                summary = entry.summary,
                definition = definition,
            }
        end
        end
    end
    self.encounterList:setRows(rows)
end

function Console:applyCatalog(payload)
    if type(payload) ~= "table" or self.factionList == nil then return end

    local counts = {}
    for _, profile in ipairs(type(payload.profiles) == "table" and payload.profiles or {}) do
        local id = tostring(profile.factionId or "")
        counts[id] = (counts[id] or 0) + 1
    end
    local list = {}
    for _, faction in ipairs(type(payload.factions) == "table" and payload.factions or {}) do
        if type(faction) == "table" and faction.id ~= nil then
            local id = tostring(faction.id)
            list[#list + 1] = {
                id = id,
                label = tostring(faction.name or id),
                detail = tostring(tonumber(faction.count) or counts[id] or 0) .. " profiles",
            }
        end
    end
    self.factionList:setRows(list)
    if type(payload.encounters) == "table" then
        self:populateEncounters(payload.encounters)
    end
end

function Console:applyCatalogRefusal(text)
    self.message = "FACTIONS REFUSED: " .. tostring(text or "unknown")
    self.messageColor = ACCENT
end

function Console:applyDirector(payload)
    if type(payload) ~= "table" then return end
    if payload.ok ~= true then
        self.message = "REFRESH REFUSED: " .. tostring(payload.reason or "unknown")
        self.messageColor = ACCENT
        return
    end
    self.director = payload.director
    self.marks = type(payload.encounters) == "table" and payload.encounters or {}
end

function Console:applyDumpResult(kind, payload)
    payload = type(payload) == "table" and payload or {}
    if payload.ok == true then
        local where = tostring(payload.where or "console.txt")
        self.message = (kind == "qa"
            and "Module QA written to " or "Black box written to ") .. where
        self.messageColor = { r = 0.35, g = 0.85, b = 0.55, a = 1 }
    else
        self.message = string.upper(kind) .. " DUMP REFUSED: "
            .. tostring(payload.reason or "unknown")
        self.messageColor = ACCENT
    end
end

function Console:applyResult(payload)
    if type(payload) ~= "table" then return end
    if payload.ok == true then
        local origin = type(payload.origin) == "table" and payload.origin or nil
        local scene = payload.scene ~= nil and (" + " .. tostring(payload.scene) .. " scene") or ""
        local anchor = origin ~= nil and (" @ " .. tostring(math.floor(origin.x or 0))
            .. "," .. tostring(math.floor(origin.y or 0))) or ""
        self.message = "Queued " .. tostring(payload.accepted or "?")
            .. " NPCs" .. scene .. anchor
        self.messageColor = { r = 0.35, g = 0.85, b = 0.55, a = 1 }
    else
        local text = type(payload.text) == "string" and payload.text ~= "" and payload.text or nil
        self.message = "REFUSED: " .. tostring(text or payload.reason or "unknown")
            .. (text ~= nil and payload.reason ~= nil and (" [" .. tostring(payload.reason) .. "]") or "")
        self.messageColor = ACCENT
    end
    self:refresh(false)
end

local function squareUnderPlayer(playerNum)
    local player = getSpecificPlayer(playerNum or 0)
    if player == nil then return nil end
    local point
    pcall(function()
        point = { x = player:getX(), y = player:getY(), z = player:getZ() }
    end)
    return point
end

function Console:spawnArguments(placement)
    local encounter = self.encounterList:selectedRow()
    if encounter == nil then
        self.message = "Pick an encounter first."
        self.messageColor = ACCENT
        return nil
    end
    local faction = self.factionList:selectedRow()
    local arguments = {
        requestId = "console:" .. tostring(encounter.id) .. ":" .. tostring(nowMs()),
        encounterId = encounter.id,
        factionId = faction ~= nil and faction.id or nil,
        placementMode = placement,
    }
    if self.count > 0 then arguments.count = self.count end
    if self.persistent ~= nil then arguments.persistent = self.persistent end
    if placement == "here" then
        local point = copyPoint(self.targetPosition) or squareUnderPlayer(self.playerNum)
        if point == nil then
            self.message = "No position for this player."
            self.messageColor = ACCENT
            return nil
        end
        arguments.x, arguments.y, arguments.z = point.x, point.y, point.z
    end
    return arguments
end

function Console:onSpawnEncounter()
    local arguments = self:spawnArguments("here")
    if arguments == nil then return end
    local faction = self.factionList:selectedRow()
    local encounter = self.encounterList:selectedRow()
    self.message = "Building " .. tostring(encounter and encounter.label or "encounter")
        .. " + " .. tostring(faction and faction.label or "automatic") .. " squad..."
    self.messageColor = MUTED
    send(self.playerNum, "debugSpawnCatalog", arguments)
end

function Console:onSimulateHere()
    local arguments = self:spawnArguments("here")
    if arguments == nil then return end
    self.message = "Simulating here..."
    self.messageColor = MUTED
    send(self.playerNum, "debugSpawnCatalog", arguments)
end

function Console:onSimulateByRule()
    local arguments = self:spawnArguments("rule")
    if arguments == nil then return end
    self.message = "Placing by the encounter's own rule..."
    self.messageColor = MUTED
    send(self.playerNum, "debugSpawnCatalog", arguments)
end

function Console:onSpawnSquad()
    local faction = self.factionList:selectedRow()
    if faction == nil then
        self.message = "Pick a faction first."
        self.messageColor = ACCENT
        return
    end
    local arguments = self:spawnArguments("here")
    if arguments == nil then return end

    arguments.factionOnly = true
    self.message = "Spawning " .. tostring(faction.label) .. " squad..."
    self.messageColor = MUTED
    send(self.playerNum, "debugSpawnCatalog", arguments)
end

function Console:onCountUp()
    self.count = math.min(8, (self.count or 0) + 1)
end

function Console:onCountDown()
    self.count = math.max(0, (self.count or 0) - 1)
end

function Console:onTogglePersistent()
    if self.persistent == nil then self.persistent = true
    elseif self.persistent == true then self.persistent = false
    else self.persistent = nil end
    self.persistToggle:setTitle(self.persistent == nil and "PERSISTENT: DEFAULT"
        or (self.persistent and "PERSISTENT: YES" or "PERSISTENT: NO"))
end

function Console:onToggleArrows()
    local compass = ProjectALife.EncounterCompass
    if compass ~= nil then compass.toggle(self.playerNum) end
end

function Console:onToggleMap()
    local squadMap = ProjectALife.SquadMap
    if squadMap ~= nil then squadMap.toggle(self.playerNum) end
end

function Console:onBlackbox()
    self.message = "Requesting black box dump..."
    self.messageColor = MUTED
    if not send(self.playerNum, "debugBlackbox", {}) then
        self:applyDumpResult("black box", { ok = false, reason = "send_failed" })
    end
end

function Console:onModuleQA()
    self.message = "Requesting module QA dump..."
    self.messageColor = MUTED
    if not send(self.playerNum, "debugModuleQA", {}) then
        self:applyDumpResult("qa", { ok = false, reason = "send_failed" })
    end
end

function Console:onRefresh()
    self:refresh()
end

function Console:refresh(force)
    local spawner = ALifeDebugSpawnerWindow
    if type(spawner) == "table" and type(spawner.requestCatalog) == "function" then
        if spawner.catalog ~= nil then self:applyCatalog(spawner.catalog) end
        if force ~= false or spawner.catalog == nil then
            spawner.requestCatalog(self.playerNum, nil, true)
        end
    else
        send(self.playerNum, "debugCatalog", {})
    end
    send(self.playerNum, "debugDirectorState", {})
end

function Console:prerender()
    ISCollapsableWindow.prerender(self)
    self:drawRect(0, 16, self.width, self.height - 16,
        0.92, 0.03, 0.035, 0.045)
end

function Console:render()
    ISCollapsableWindow.render(self)
    local gap, top = 12, 42
    local factionX = self.factionX or gap
    local encounterX = self.encounterX or (gap * 2 + 210)
    local right = self.actionX or (gap * 3 + 460)
    self:drawText("1  SQUAD", factionX, top, ACCENT.r, ACCENT.g, ACCENT.b, 1, UIFont.Small)
    self:drawText("2  ENCOUNTER", encounterX, top, ACCENT.r, ACCENT.g, ACCENT.b, 1, UIFont.Small)
    self:drawText("3  DEPLOY", right, top, ACCENT.r, ACCENT.g, ACCENT.b, 1, UIFont.Small)

    local countText = self.count > 0 and tostring(self.count) or "auto"
    if self.advancedOpen == true then
        self:drawText("SIZE: " .. countText, right + 64, top + 166,
            TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
    else
        self:drawText("SCENE + SQUAD, ONE DEPLOY",
            right, top + 98, MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
        self:drawText("Advanced: place / size / persist",
            right, top + 114, MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
    end
    local target = self.targetPosition
    local targetText = target ~= nil and ("tile " .. tostring(math.floor(target.x))
        .. "," .. tostring(math.floor(target.y))) or "player position"
    if self.advancedOpen ~= true then
        self:drawText("Target: " .. targetText, right, top + 180,
            MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
    end

    local y = top + 202
    if self.advancedOpen ~= true then
        self:drawText("DIRECTOR", right, y, ACCENT.r, ACCENT.g, ACCENT.b, 1, UIFont.Small)
        local director = self.director
        if type(director) == "table" then
            self:drawText("rolls " .. tostring(director.rolls or 0)
                .. "  placed " .. tostring(director.spawned or 0)
                .. "  refused " .. tostring(director.forfeits or 0),
                right, y + 14, MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
            self:drawText(tostring(director.lastOutcome or "(nothing yet)"),
                right, y + 28, MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
        else
            self:drawText("(no report yet)", right, y + 14,
                MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
        end
    end

    local listY = top + 286
    self:drawText("ON THE MAP", gap, listY, ACCENT.r, ACCENT.g, ACCENT.b, 1, UIFont.Small)
    local shown = 0
    for _, mark in ipairs(self.marks or {}) do
        if shown >= 5 then break end
        local color = mark.stance ~= nil and STANCE_COLOR[mark.stance] or MUTED
        local age = math.floor((tonumber(mark.ageMs) or 0) / 1000)
        self:drawRect(gap, listY + 16 + shown * 15, 6, 10, 0.95, color.r, color.g, color.b)
        self:drawText(tostring(mark.label or mark.id) .. "  x" .. tostring(mark.count or "?")
            .. "   " .. tostring(math.floor(tonumber(mark.x) or 0))
            .. "," .. tostring(math.floor(tonumber(mark.y) or 0))
            .. "   " .. tostring(age) .. "s ago",
            gap + 12, listY + 12 + shown * 15, TEXT.r, TEXT.g, TEXT.b, 1, UIFont.Small)
        shown = shown + 1
    end
    if shown == 0 then
        self:drawText("nothing placed yet", gap + 12, listY + 12,
            MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
    end

    local color = self.messageColor or MUTED
    self:drawText(tostring(self.message or ""), gap, self.height - 28,
        color.r, color.g, color.b, 1, UIFont.Small)
end

function Console:close()
    Console.instance = nil
    self:removeFromUIManager()
end

function Console.closeInstance()
    local window = Console.instance
    if window == nil or type(window.close) ~= "function" then return false end
    window:close()
    return true
end

return Console
