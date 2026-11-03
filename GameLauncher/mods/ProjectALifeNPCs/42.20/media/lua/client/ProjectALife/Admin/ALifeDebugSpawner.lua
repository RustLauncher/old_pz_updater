require "ISUI/ISCollapsableWindow"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"
require "ProjectALife/Shells/ALifeAnimations"
require "ProjectALife/Interface/ALifeStatusStore"
require "ProjectALife/Interface/ALifeEncounterConsole"
require "ProjectALife/Records/ALifeDropPolicy"
require "ProjectALife/Interface/ALifeMenuPrefs"

ProjectALife = ProjectALife or {}

local StatusStore = ProjectALife.StatusStore

local ROSE = { r = 0.72, g = 0.55, b = 0.32, a = 1 }
local ROSE_DARK = { r = 0.13, g = 0.10, b = 0.065, a = 0.96 }
local PANEL_BG = { r = 0.055, g = 0.060, b = 0.064, a = 0.97 }
local CARD_BG = { r = 0.070, g = 0.075, b = 0.078, a = 0.98 }
local CONTROL_BG = { r = 0.095, g = 0.100, b = 0.105, a = 0.96 }
local CONTROL_BORDER = { r = 0.30, g = 0.32, b = 0.33, a = 1 }
local TEXT = { r = 0.92, g = 0.91, b = 0.88, a = 1 }
local MUTED = { r = 0.68, g = 0.69, b = 0.68, a = 1 }
local BAD = { r = 0.82, g = 0.36, b = 0.34, a = 1 }
local ACCENT = ROSE

local function copyColor(value)
    if type(value) ~= "table" then return value end
    return { r = value.r, g = value.g, b = value.b, a = value.a }
end

local ROW_H = 26
local LABEL_W = 196
local PAD = 14

local USE_PROFILE = { "Use profile", "profile" }
local CHOICES = {
    doctrine = { USE_PROFILE,
        { "Individual AI", "individual" },
        { "Fireteam coordination", "fireteam" },
        { "CQB entry team", "cqb" } },
    role = { USE_PROFILE,
        { "Generalist", "none" },
        { "Team leader", "leader" },
        { "Medic", "medic" },
        { "Marksman", "sniper" },
        { "Gunner / suppression", "gunner" } },

    hostility = { { "Use faction", "profile" },
        { "Ally -- friendly to players", "friendly" },
        { "Neutral -- leave players alone", "neutral" },
        { "Careful -- warn, then shoot", "careful" },
        { "Hostile -- attack on sight", "hostile" } },
    yesNo = { { "No", "false" }, { "Yes", "true" } },
    yesNoProfile = { USE_PROFILE, { "Yes", "true" }, { "No", "false" } },
    facing = { { "Automatic", "auto" }, { "North", "N" }, { "North-east", "NE" },
        { "East", "E" }, { "South-east", "SE" }, { "South", "S" },
        { "South-west", "SW" }, { "West", "W" }, { "North-west", "NW" } },

    supportPolicy = { USE_PROFILE,
        { "Any squad member may call", "any" },
        { "Radio operators only", "radio" },
        { "Nobody may call", "disabled" } },
    supportType = { USE_PROFILE,
        { "Ground + helicopter", "both" },
        { "Ground reinforcements", "ground" },
        { "Helicopter only", "heli" },
        { "No support at all", "none" } },
    heli = { USE_PROFILE,
        { "No helicopter", "none" },
        { "Spotlight only", "spotlight" },
        { "Helicopter support", "support" } },
    placement = { { "Right here", "here" }, { "Wherever the plan fits", "rule" } },

    arrival = { { "Default -- just appear", "foot" },
        { "Helicopter and rope", "heli" },
        { "By car", "ground" } },
}

CHOICES.weaponCondition = { USE_PROFILE }
CHOICES.clothingCondition = { USE_PROFILE }
CHOICES.weaponChance = { USE_PROFILE }

ALifeDebugSpawnerWindow = ISCollapsableWindow:derive("ALifeDebugSpawnerWindow")

function ALifeDebugSpawnerWindow.buildGearChoices()
    if #CHOICES.weaponCondition > 1 then return true end
    local policy = ProjectALife.DropPolicy
    if type(policy) ~= "table" or type(policy.conditions) ~= "table"
            or type(policy.presets) ~= "table" then return false end
    for _, row in ipairs(policy.conditions) do
        CHOICES.weaponCondition[#CHOICES.weaponCondition + 1] = { row[1], tostring(row[2]) }
        CHOICES.clothingCondition[#CHOICES.clothingCondition + 1] = { row[1], tostring(row[2]) }
    end
    for _, row in ipairs(policy.presets) do
        CHOICES.weaponChance[#CHOICES.weaponChance + 1] = { row[1], row[2] }
    end
    return true
end
ALifeDebugSpawnerWindow.instance = nil
ALifeDebugSpawnerWindow.catalog = nil
ALifeDebugSpawnerWindow.requests = {}
ALifeDebugSpawnerWindow.requestSequence = 0
ALifeDebugSpawnerWindow.lastMessage = nil

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

local function squarePosition(square)
    if square == nil then return nil end

    if type(square) == "table" and tonumber(square.x) ~= nil then
        return { x = math.floor(tonumber(square.x)),
            y = math.floor(tonumber(square.y) or 0),
            z = math.floor(tonumber(square.z) or 0) }
    end
    local ok, x, y, z = pcall(function()
        return square:getX(), square:getY(), square:getZ()
    end)
    if not ok or x == nil then return nil end
    return { x = math.floor(x), y = math.floor(y), z = math.floor(z) }
end

local function shortUid(uid)
    local value = tostring(uid or "unknown")
    return #value > 20 and string.sub(value, -20) or value
end

local function styleButton(button, accent)
    button.backgroundColor = copyColor(accent and ROSE_DARK or CONTROL_BG)
    button.borderColor = copyColor(accent and ROSE or CONTROL_BORDER)
    button.textColor = copyColor(accent and { r = 1, g = 0.82, b = 0.89, a = 1 } or TEXT)
    if button.borderColorEnabled ~= nil then
        button.borderColorEnabled = copyColor(button.borderColor)
        button.backgroundColorEnabled = copyColor(button.backgroundColor)
    end
end

local function addButton(parent, x, y, width, label, callback, accent)
    local button = ISButton:new(x, y, width, 24, label, parent, callback)
    button:initialise()
    button:instantiate()
    styleButton(button, accent)
    parent:addChild(button)
    return button
end

local function addCombo(parent, x, y, width)
    local combo = ISComboBox:new(x, y, width, 22)
    combo:initialise()
    combo:instantiate()
    combo.backgroundColor = copyColor(CONTROL_BG)
    combo.borderColor = copyColor(CONTROL_BORDER)
    parent:addChild(combo)
    return combo
end

local function addEntry(parent, x, y, width, value)
    local entry = ISTextEntryBox:new(tostring(value or ""), x, y, width, 22)
    entry:initialise()
    entry:instantiate()
    entry:setOnlyNumbers(true)
    entry.backgroundColor = copyColor(CONTROL_BG)
    entry.borderColor = copyColor(CONTROL_BORDER)
    parent:addChild(entry)
    return entry
end

local function fill(combo, rows, selected)
    combo:clear()
    local chosen = 1
    for index, row in ipairs(rows) do
        combo:addOptionWithData(row[1], row[2])
        if row[2] == selected then chosen = index end
    end
    combo.selected = chosen
    return combo
end

local function dataOf(combo)
    if combo == nil or combo.selected == nil then return nil end
    return combo:getOptionData(combo.selected)
end

function ALifeDebugSpawnerWindow.chosen(value)
    if value == nil or value == "profile" or value == "" then return nil end
    return value
end

function ALifeDebugSpawnerWindow.number(text, minimum, maximum, sentinel)
    local value = tonumber(text)
    if value == nil then return nil end
    if sentinel ~= nil and value == sentinel then return nil end
    return math.max(minimum, math.min(maximum, value))
end

ALifeDebugSpawnerWindow.headings = {
    N = 0, NE = 0.7853981634, E = 1.5707963268, SE = 2.3561944902,
    S = 3.1415926536, SW = 3.9269908170, W = 4.7123889804, NW = 5.4977871438,
}

function ALifeDebugSpawnerWindow.headingFor(compass)
    if type(compass) ~= "string" then return nil end
    return ALifeDebugSpawnerWindow.headings[compass]
end

function ALifeDebugSpawnerWindow.matchingProfiles(profiles, factionId)
    local matches = {}
    if type(profiles) ~= "table" then return matches end
    for index = 1, #profiles do
        local profile = profiles[index]
        if type(profile) == "table" and type(profile.id) == "string"
            and (factionId == nil or factionId == "*" or profile.factionId == factionId) then
            matches[#matches + 1] = profile
        end
    end
    return matches
end

function ALifeDebugSpawnerWindow:addLog(message, severity)
    local text = tostring(message or "")
    self.status = text
    ALifeDebugSpawnerWindow.lastMessage = text
    if text == "" then return end
    self.log = self.log or {}
    self.log[#self.log + 1] = { text = text, severity = severity or "info" }
    while #self.log > 40 do table.remove(self.log, 1) end
end

ALifeDebugSpawnerWindow.leftRows = {
    { "faction", "NPC faction", "combo" },
    { "encounter", "Encounter", "combo" },
    { "doctrine", "Behaviour doctrine", "combo", "doctrine" },
    { "role", "Specialist role", "combo", "role" },
    { "hostility", "Stance toward players", "combo", "hostility" },
    { "placement", "Placement", "combo", "placement" },
    { "animation", "Arrival animation", "combo" },
    { "arrival", "How they arrive", "combo", "arrival" },
    { "persistent", "Save squad (within limit)", "combo", "yesNoProfile" },
    { "invulnerable", "Invulnerable NPCs", "combo", "yesNo" },
    { "stationary", "Position locked", "combo", "yesNo" },
    { "facing", "Facing / line heading", "combo", "facing" },
    { "canCallSupport", "Can call support", "combo", "yesNoProfile" },
    { "supportPolicy", "Who may call", "combo", "supportPolicy" },
    { "supportType", "Allowed support", "combo", "supportType" },
    { "heli", "Helicopter", "combo", "heli" },
}
ALifeDebugSpawnerWindow.rightRows = {
    { "count", "Group / wave size", "entry", 0 },
    { "distance", "Spawn distance", "entry", -1 },
    { "separation", "Unit spacing", "entry", -1 },
    { "radius", "Behaviour radius", "entry", -1 },
    { "awareness", "Detection range", "entry", 0 },
    { "leash", "Movement leash", "entry", 0 },
    { "health", "Exact HP", "entry", 0 },
    { "damageReduction", "Damage reduction %", "entry", -1 },
    { "damageOutput", "Damage output %", "entry", -1 },
    { "supportSize", "Support squad size", "entry", 0 },
    { "supportMaxCalls", "Support calls (max)", "entry", 0 },
    { "supportCooldownHours", "Support cooldown (h)", "entry", 0 },
    { "waves", "Raid waves (1-12)", "entry", 3 },
    { "waveDelayMinutes", "Game minutes per wave", "entry", 5 },
    { "raidHeli", "Raid helicopter", "combo", "yesNoProfile" },

    { "weaponChance", "Weapon drop chance", "combo", "weaponChance" },
    { "weaponCondition", "Weapon condition", "combo", "weaponCondition" },
    { "clothingCondition", "Clothing condition", "combo", "clothingCondition" },
}

ALifeDebugSpawnerWindow.defaults = {
    faction = "*", encounter = "", doctrine = "profile",
    role = "profile", hostility = "profile", placement = "here",
    animation = "normal", arrival = "foot",
    persistent = "profile", invulnerable = "false",
    stationary = "false", facing = "auto", canCallSupport = "profile",
    supportPolicy = "profile", supportType = "profile", heli = "profile",
    count = "0", distance = "-1", separation = "-1", radius = "-1",
    awareness = "0", leash = "0", health = "0", damageReduction = "-1",
    damageOutput = "-1", supportSize = "0", supportMaxCalls = "0", supportCooldownHours = "0",
    waves = "3", waveDelayMinutes = "5",
    raidHeli = "profile",
    weaponChance = "profile", weaponCondition = "profile",
    clothingCondition = "profile",
}

function ALifeDebugSpawnerWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    ALifeDebugSpawnerWindow.buildGearChoices()
    local top = self:titleBarHeight() + 52
    local columnW = math.floor((self.width - PAD * 3) / 2)
    local bodyH = self.height - top - 132

    self.combos, self.entries = {}, {}

    local function columnRender(panel)
        panel.prerender = function(self)
            ISPanel.prerender(self)
            self:setStencilRect(1, 1, self.width - 2, self.height - 2)
            self:drawText(self.heading, 14, 8, ROSE.r, ROSE.g, ROSE.b, 1, UIFont.Small)
            for index, row in ipairs(self.rows or {}) do
                self:drawText(row[2], 14, 30 + (index - 1) * ROW_H + 4,
                    MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
            end
        end
        panel.render = function(self) self:clearStencilRect() end
        panel.onMouseWheel = function(self, delta)
            self:setYScroll(self:getYScroll() - delta * ROW_H * 3)
            return true
        end
    end

    local left = ISPanel:new(PAD, top, columnW, bodyH)
    left:initialise()
    left.backgroundColor = copyColor(CARD_BG)
    left.borderColor = copyColor(ROSE)
    left.heading = "IDENTITY, AI & RULES"
    left.rows = ALifeDebugSpawnerWindow.leftRows
    columnRender(left)
    self:addChild(left)
    self.leftPanel = left
    left:setScrollChildren(true)
    left:addScrollBars()
    left:setScrollHeight(38 + #ALifeDebugSpawnerWindow.leftRows * ROW_H)

    local right = ISPanel:new(PAD * 2 + columnW, top, columnW, bodyH)
    right:initialise()
    right.backgroundColor = copyColor(CARD_BG)
    right.borderColor = copyColor(ROSE)
    right.heading = "COMBAT, SUPPORT & EVENTS"
    right.rows = ALifeDebugSpawnerWindow.rightRows
    columnRender(right)
    self:addChild(right)
    self.rightPanel = right
    right:setScrollChildren(true)
    right:addScrollBars()

    local controlX = LABEL_W
    local controlW = columnW - LABEL_W - 24
    for index, row in ipairs(ALifeDebugSpawnerWindow.leftRows) do
        local y = 30 + (index - 1) * ROW_H
        if row[3] == "combo" then
            self.combos[row[1]] = addCombo(left, controlX, y, controlW)
        else
            self.entries[row[1]] = addEntry(left, controlX, y, controlW,
                ALifeDebugSpawnerWindow.defaults[row[1]])
        end
    end
    for index, row in ipairs(ALifeDebugSpawnerWindow.rightRows) do
        local y = 30 + (index - 1) * ROW_H
        if row[3] == "combo" then
            self.combos[row[1]] = addCombo(right, controlX, y, controlW)
        else
            self.entries[row[1]] = addEntry(right, controlX, y, controlW,
                ALifeDebugSpawnerWindow.defaults[row[1]])
        end
    end

    for _, row in ipairs(ALifeDebugSpawnerWindow.leftRows) do
        local list = row[4] and CHOICES[row[4]] or nil
        if list ~= nil then
            fill(self.combos[row[1]], list, ALifeDebugSpawnerWindow.defaults[row[1]])
        end
    end
    for _, row in ipairs(ALifeDebugSpawnerWindow.rightRows) do
        local list = row[4] and CHOICES[row[4]] or nil
        if list ~= nil then
            fill(self.combos[row[1]], list, ALifeDebugSpawnerWindow.defaults[row[1]])
        end
    end
    fill(self.combos.faction, { { "Any hostile faction", "*" } }, "*")
    fill(self.combos.encounter, { { "Roaming squad (no encounter)", "" } }, "")
    fill(self.combos.animation, { { "Normal", "normal" } }, "normal")

    self.combos.encounter.target = self
    self.combos.encounter.onChange = ALifeDebugSpawnerWindow.onEncounterChanged
    self.combos.faction.target = self
    self.combos.faction.onChange = ALifeDebugSpawnerWindow.onFactionChanged

    local toolY = 30 + #ALifeDebugSpawnerWindow.rightRows * ROW_H + 14
    local toolW = math.floor((columnW - 42) / 2)
    local tools = {
        { "Encounter arrows", self.onToggleArrows },
        { "Squads on the map", self.onToggleMap },
        { "Runtime status", self.onStatus },
        { "NPC report", self.onActors },
        { "Diagnostics", self.onDiagnostics },
        { "Repair runtime", self.onRepair },
        { "Reputation +10", self.onRepUp },
        { "Reputation -10", self.onRepDown },
        { "Black box dump", self.onBlackbox },
        { "Module QA dump", self.onModuleQA },
        { "Town census", self.onTownCensus },
        { "No-spawn area here", self.onProtect },
        { "Clear no-spawn areas", self.onClearZones },
        { "Cleanup A-Life", function(window) if ProjectALife.CleanupWindow ~= nil then ProjectALife.CleanupWindow.open(window.playerNum) end end },

        { "Meta: gunfire", function(window) window:onMetaEvent("gunfire") end },
        { "Meta: helicopter", function(window) window:onMetaEvent("heli") end },
        { "Meta: searchlight", function(window) window:onMetaEvent("searchlight") end },
        { "Meta: ambience", function(window) window:onMetaEvent("ambience") end },
        { "Meta: car crash", function(window) window:onMetaEvent("crash") end },
    }
    for index, tool in ipairs(tools) do
        local column = (index - 1) % 2
        local rowIndex = math.floor((index - 1) / 2)
        local handler = tool[2]
        addButton(right, 14 + column * (toolW + 14), toolY + rowIndex * 28,
            toolW, tool[1], function() handler(self) end)
    end
    right:setScrollHeight(toolY + math.ceil(#tools / 2) * 28 + 8)

    local footY = self.height - 68
    addButton(self, PAD, footY, 128, "Faction defaults", function() self:onLoadDefaults() end)
    addButton(self, PAD + 136, footY, 128, "Reset fields", function() self:onResetFields() end)
    self.presetName = ISTextEntryBox:new("", PAD + 272, footY + 1, 150, 22)
    self.presetName:initialise()
    self.presetName:instantiate()
    self.presetName.backgroundColor = copyColor(CONTROL_BG)
    self.presetName.borderColor = copyColor(CONTROL_BORDER)
    self:addChild(self.presetName)
    self.presetList = addCombo(self, PAD + 430, footY + 1, 190)
    local actionY = footY + 32
    addButton(self, PAD, actionY, 110, "Load preset", function() self:onLoadPreset() end)
    addButton(self, PAD + 118, actionY, 110, "Save preset", function() self:onSavePreset() end)
    addButton(self, self.width - PAD - 208, actionY, 100, "Close",
        function() self:close() end)
    self.spawnButton = addButton(self, self.width - PAD - 102, actionY, 102, "SPAWN",
        function() self:onDeploy() end, true)
    self:refreshPresetList()
    self:addLog("Pick a faction and an encounter, then press SPAWN.")
end

function ALifeDebugSpawnerWindow:populate(catalog)
    ALifeDebugSpawnerWindow.catalog = catalog
    if self.combos == nil then return end
    local haveCatalog = type(catalog) == "table"

    local factions = { { "Any hostile faction", "*" } }
    for _, faction in ipairs(haveCatalog and type(catalog.factions) == "table"
        and catalog.factions or {}) do
        if type(faction) == "table" and faction.id ~= nil then
            local label = tostring(faction.name or faction.id)
            if faction.visitorOnly == true then label = "[Visitor] " .. label end
            factions[#factions + 1] = { label, faction.id }
        end
    end
    fill(self.combos.faction, factions, dataOf(self.combos.faction) or "*")

    local encounters = { { "Roaming squad (no encounter)", "" } }
    self.encounterSpecs = {}
    for _, spec in ipairs(haveCatalog and type(catalog.encounters) == "table"
        and catalog.encounters or {}) do
        if type(spec) == "table" and type(spec.id) == "string" then
            self.encounterSpecs[spec.id] = spec
            encounters[#encounters + 1] = { tostring(spec.label or spec.id), spec.id }
        end
    end

    for _, preset in ipairs(haveCatalog and type(catalog.outpostPresets) == "table"
        and catalog.outpostPresets or {}) do
        if type(preset) == "table" and type(preset.id) == "string" then
            local id = ALifeDebugSpawnerWindow.outpostEncounterId(preset.id)
            self.encounterSpecs[id] = {
                id = id, label = "Staffed outpost: " .. tostring(preset.label or preset.id),
                outpostPreset = preset.id, mode = "guard", stance = "garrison",
                minCount = preset.garrisonMin, maxCount = preset.garrisonMax,
                placement = preset.class == "building" and "building" or nil,
                admin = { leash = 10, doctrine = "fireteam" },
            }
            encounters[#encounters + 1] = { self.encounterSpecs[id].label, id }
        end
    end
    fill(self.combos.encounter, encounters, dataOf(self.combos.encounter) or "")

    if self.preferredEncounter ~= nil and self.encounterSpecs[self.preferredEncounter] then
        fill(self.combos.encounter, encounters, self.preferredEncounter)
        self.preferredEncounter = nil
        self:onEncounterChanged(self.combos.encounter)
        self:writeFields({ placement = "here" })
    end
    if self.preferredFaction ~= nil then
        fill(self.combos.faction, factions, self.preferredFaction)
        if dataOf(self.combos.faction) == self.preferredFaction then
            self.preferredFaction = nil
        end
    end

    local animations = {}
    for _, preset in ipairs(haveCatalog and type(catalog.animations) == "table"
        and catalog.animations or {}) do
        if type(preset) == "table" and preset.id ~= nil then
            animations[#animations + 1] = { tostring(preset.label or preset.id), preset.id }
        end
    end
    if #animations == 0 then animations[1] = { "Normal", "normal" } end
    fill(self.combos.animation, animations, dataOf(self.combos.animation) or "normal")

    local count = haveCatalog and tonumber(catalog.profileCount) or nil
    if count == nil then
        count = haveCatalog and type(catalog.profiles) == "table" and #catalog.profiles or 0
    end
    local factionCount = 0
    if haveCatalog and type(catalog.factions) == "table" then factionCount = #catalog.factions end
    self:addLog(tostring(count) .. " profiles in " .. tostring(factionCount) .. " factions ready.", "success")
    ALifeDebugSpawnerWindow.requestFactionProfiles(self.playerNum, dataOf(self.combos.faction))
end

function ALifeDebugSpawnerWindow.outpostEncounterId(presetId)
    return "outpost:" .. tostring(presetId)
end

function ALifeDebugSpawnerWindow.outpostPresetOf(encounterId)
    if type(encounterId) ~= "string" then return nil end
    if string.sub(encounterId, 1, 8) ~= "outpost:" then return nil end
    local presetId = string.sub(encounterId, 9)
    if presetId == "" then return nil end
    return presetId
end

function ALifeDebugSpawnerWindow.encounterDefaults(spec)
    local encounters = ProjectALife.Encounters
    if encounters ~= nil and type(encounters.adminDefaults) == "function" then
        return encounters.adminDefaults(spec)
    end
    local values = { doctrine = "profile", role = "profile", hostility = "profile",
        placement = "here", stationary = "false", leash = "0" }
    if type(spec) ~= "table" then return values end
    local admin = type(spec.admin) == "table" and spec.admin or {}
    if spec.placement ~= nil then values.placement = "rule" end
    if tonumber(admin.leash) ~= nil then values.leash = tostring(math.floor(tonumber(admin.leash))) end
    if admin.stationary == true or spec.stance == "occupy_high" then values.stationary = "true" end
    if admin.hostility ~= nil then values.hostility = tostring(admin.hostility) end
    if admin.doctrine ~= nil then values.doctrine = tostring(admin.doctrine) end
    return values
end

function ALifeDebugSpawnerWindow:onEncounterChanged(combo)
    local id = dataOf(combo or self.combos.encounter)
    local spec = (self.encounterSpecs or {})[id or ""]
    local values = ALifeDebugSpawnerWindow.encounterDefaults(spec)
    self:writeFields(values)
    local staffed = ALifeDebugSpawnerWindow.outpostPresetOf(id) ~= nil
    for _, key in ipairs({ "placement", "persistent", "raidHeli" }) do
        local control = self.combos[key]
        if control and type(control.setEnable) == "function" then control:setEnable(not staffed) end
    end
    for _, key in ipairs({ "distance", "separation", "radius", "waves", "waveDelayMinutes" }) do
        local control = self.entries[key]
        if control and type(control.setEditable) == "function" then control:setEditable(not staffed) end
    end
    if staffed then self:addLog("Built at the clicked location. Saved site; session-only crew. Layout sets spacing.") end
    if spec == nil then
        self:addLog("Roaming squad: the faction and the profile decide.")
        return
    end
    self:addLog(tostring(spec.label or id) .. " decides: program "
        .. tostring(spec.mode or "guard") .. ", leash " .. tostring(values.leash)
        .. (values.stationary == "true" and ", holds ground" or "")
        .. (values.placement == "rule" and ", placed by its own rule" or ", placed here") .. ".")
end

function ALifeDebugSpawnerWindow:onFactionChanged(combo)
    local id = dataOf(combo or self.combos.faction)
    if id == nil or id == "*" then return end
    local entry = ALifeDebugSpawnerWindow.factionProfiles[id]
    if entry ~= nil and entry.complete then
        self:addLog(tostring(#entry.rows) .. " profiles ready in " .. tostring(id) .. ".")
    else
        self:addLog("Loading the profiles of " .. tostring(id) .. "...")
    end

    ALifeDebugSpawnerWindow.requestFactionProfiles(self.playerNum, id)
end

function ALifeDebugSpawnerWindow:programFor(encounterId)
    local spec = (self.encounterSpecs or {})[encounterId or ""]
    if type(spec) == "table" and type(spec.mode) == "string" then return spec.mode end
    return "roam"
end

local function presetStore()
    local store
    pcall(function()
        if type(ModData) == "table" and type(ModData.getOrCreate) == "function" then
            store = ModData.getOrCreate("ProjectALifeSpawnPresets")
        end
    end)
    if type(store) ~= "table" then
        ALifeDebugSpawnerWindow.fallbackPresets =
            ALifeDebugSpawnerWindow.fallbackPresets or {}
        return ALifeDebugSpawnerWindow.fallbackPresets
    end
    store.presets = type(store.presets) == "table" and store.presets or {}
    return store.presets
end

function ALifeDebugSpawnerWindow:readFields()
    local values = {}
    for key, combo in pairs(self.combos or {}) do
        values[key] = dataOf(combo)
    end
    for key, entry in pairs(self.entries or {}) do
        values[key] = tostring(entry:getText() or "")
    end
    return values
end

function ALifeDebugSpawnerWindow:writeFields(values)
    if type(values) ~= "table" then return end
    for key, combo in pairs(self.combos or {}) do
        if values[key] ~= nil then
            for index = 1, combo:getOptionCount() do
                if combo:getOptionData(index) == values[key] then
                    combo.selected = index
                    break
                end
            end
        end
    end
    for key, entry in pairs(self.entries or {}) do
        if values[key] ~= nil then entry:setText(tostring(values[key])) end
    end
end

function ALifeDebugSpawnerWindow:refreshPresetList()
    if self.presetList == nil then return end
    local rows, store = {}, presetStore()
    local names = {}
    for name in pairs(store) do names[#names + 1] = tostring(name) end
    table.sort(names)
    for _, name in ipairs(names) do rows[#rows + 1] = { name, name } end
    if #rows == 0 then rows[1] = { "No saved presets", "" } end
    fill(self.presetList, rows, dataOf(self.presetList))
end

function ALifeDebugSpawnerWindow:onSavePreset()
    local name = tostring(self.presetName and self.presetName:getText() or "")
    if name == "" then
        self:addLog("Name the preset first.", "error")
        return
    end
    presetStore()[name] = self:readFields()
    self:refreshPresetList()
    self:addLog("Preset saved: " .. name, "success")
end

function ALifeDebugSpawnerWindow:onLoadPreset()
    local name = dataOf(self.presetList)
    local values = name ~= nil and name ~= "" and presetStore()[name] or nil
    if values == nil then
        self:addLog("No preset chosen.", "error")
        return
    end
    self:writeFields(values)
    self:addLog("Preset loaded: " .. tostring(name), "success")
end

function ALifeDebugSpawnerWindow:onResetFields()
    self:writeFields(ALifeDebugSpawnerWindow.defaults)
    self:addLog("Fields reset to the profile's own settings.")
end

function ALifeDebugSpawnerWindow:onLoadDefaults()

    local values = {}
    for key, value in pairs(ALifeDebugSpawnerWindow.defaults) do values[key] = value end
    values.faction = dataOf(self.combos.faction) or "*"
    values.encounter = dataOf(self.combos.encounter) or ""
    self:writeFields(values)
    self:addLog("Every override cleared -- the faction decides.")
end

function ALifeDebugSpawnerWindow:setSpawnSquare(square)
    self.targetPosition = squarePosition(square)
end

function ALifeDebugSpawnerWindow:beginRequest(prefix, expected, mode)
    ALifeDebugSpawnerWindow.requestSequence = ALifeDebugSpawnerWindow.requestSequence + 1
    local requestId = prefix .. ":" .. tostring(self.playerNum) .. ":"
        .. tostring(nowMs()) .. ":" .. tostring(ALifeDebugSpawnerWindow.requestSequence)
    ALifeDebugSpawnerWindow.requests[requestId] = {
        requested = expected, accepted = 0, rejected = 0, started = 0,
        completed = 0, active = 0, failed = 0, jobs = {}, mode = mode,
    }
    return requestId
end

function ALifeDebugSpawnerWindow:buildArguments()
    local pick = ALifeDebugSpawnerWindow.chosen
    local number = ALifeDebugSpawnerWindow.number
    local combo = function(key) return pick(dataOf(self.combos[key])) end
    local text = function(key)
        return self.entries[key] and self.entries[key]:getText() or nil
    end
    local faction = dataOf(self.combos.faction)
    local arguments = {
        factionId = (faction ~= nil and faction ~= "*") and faction or nil,

        mode = self:programFor(dataOf(self.combos.encounter)),
        animation = dataOf(self.combos.animation) or "normal",
        placementMode = dataOf(self.combos.placement) or "here",

        arrival = dataOf(self.combos.arrival) or "foot",
        profile = combo("doctrine"),

        hostileOverride = (combo("hostility") == "friendly"
            or combo("hostility") == "hostile") and combo("hostility") or nil,
        playerStance = combo("hostility"),

        weaponChance = combo("weaponChance"),
        weaponCondition = combo("weaponCondition"),
        clothingCondition = combo("clothingCondition"),
        heading = ALifeDebugSpawnerWindow.headingFor(combo("facing")),
        supportPolicy = combo("supportPolicy"),
        supportType = combo("supportType"),
        supportHeli = combo("heli"),
        count = number(text("count"), 1,
            dataOf(self.combos.encounter) == "fullscale_raid" and 12 or 8, 0),
        distance = number(text("distance"), 0, 80, -1),
        separation = number(text("separation"), 1, 8, -1),
        radius = number(text("radius"), 6, 80, -1),

        awareness = number(text("awareness"), 2, 90, 0),
        leashRadius = number(text("leash"), 1, 100, 0),
        health = number(text("health"), 1, 400, 0),
        damageReduction = number(text("damageReduction"), 0, 90, -1),
        damageOutput = number(text("damageOutput"), 1, 500, -1),
        supportSize = number(text("supportSize"), 1, 8, 0),
        supportMaxCalls = number(text("supportMaxCalls"), 0, 10, 0),
        supportCooldownHours = number(text("supportCooldownHours"), 0, 168, 0),
        waves = number(text("waves"), 1, 12, nil),
        waveDelayMinutes = number(text("waveDelayMinutes"), 1, 60, nil),
    }
    local persistent = combo("persistent")
    if combo("raidHeli") ~= nil then arguments.raidHeli = combo("raidHeli") == "true" end
    if persistent ~= nil then arguments.persistent = persistent == "true" end
    if dataOf(self.combos.invulnerable) == "true" then arguments.invulnerable = true end
    if dataOf(self.combos.stationary) == "true" then arguments.stationary = true end
    if combo("canCallSupport") == "false" then arguments.supportPolicy = "disabled" end
    local role = combo("role")
    if role ~= nil and role ~= "none" then arguments.conducts = { role } end
    return arguments
end

function ALifeDebugSpawnerWindow:onDeploy()
    local arguments = self:buildArguments()
    local encounterId = ALifeDebugSpawnerWindow.chosen(dataOf(self.combos.encounter))
    if self.targetPosition ~= nil and arguments.placementMode == "here" then
        arguments.x, arguments.y, arguments.z =
            self.targetPosition.x, self.targetPosition.y, self.targetPosition.z
    end
    local presetId = ALifeDebugSpawnerWindow.outpostPresetOf(encounterId)
    if presetId ~= nil then

        local build = arguments
        build.presetId, build.persistent = presetId, false
        if self.targetPosition ~= nil then
            build.x, build.y, build.z = self.targetPosition.x, self.targetPosition.y, self.targetPosition.z
        end
        local specification = (self.encounterSpecs or {})[encounterId] or {}
        self:addLog("Building " .. tostring(specification.label or presetId) .. "...")
        if not send(self.playerNum, "debugBuildOutpost", build) then
            self:addLog("The request could not be sent.", "error")
        end
        return
    end
    if encounterId ~= nil then
        local specification = (self.encounterSpecs or {})[encounterId] or {}
        local expected = (tonumber(arguments.count) or 0) > 0 and arguments.count or math.max(1, math.floor(
            ((tonumber(specification.minCount) or 2)
                + (tonumber(specification.maxCount) or 4)) / 2))
        arguments.requestId = self:beginRequest("encounter", expected,
            tostring(specification.mode or encounterId))
        arguments.encounterId = encounterId
        self:addLog("Spawning " .. tostring(specification.label or encounterId) .. "...")
        if not send(self.playerNum, "debugSpawnCatalog", arguments) then
            ALifeDebugSpawnerWindow.requests[arguments.requestId] = nil
            self:addLog("The request could not be sent.", "error")
        end
        return
    end
    local matches = ALifeDebugSpawnerWindow.matchingProfiles(
        ALifeDebugSpawnerWindow.profilesFor(dataOf(self.combos.faction)),
        dataOf(self.combos.faction))
    local count = (tonumber(arguments.count) or 0) > 0 and arguments.count or 4
    arguments.count = count

    arguments.requestId = self:beginRequest("client", count, arguments.mode)
    arguments.anchor = arguments.mode == "guard"
    self:addLog("Spawning " .. tostring(count) .. " x "
        .. tostring(matches[1] and (matches[1].name or matches[1].id) or "faction members")
        .. " (" .. tostring(arguments.mode) .. ")...")
    if not send(self.playerNum, "debugSpawn", arguments) then
        ALifeDebugSpawnerWindow.requests[arguments.requestId] = nil
        self:addLog("The request could not be sent.", "error")
    end
end

function ALifeDebugSpawnerWindow:onRefresh()
    local asked = ALifeDebugSpawnerWindow.requestCatalog(self.playerNum, nowMs(), true)
    if asked == "pending" then
        self:addLog("The faction catalog is already on its way...")
    else
        self:addLog("Asking the server for the faction catalog...")
    end
end

function ALifeDebugSpawnerWindow:onStatus()
    self:addLog("Requesting runtime status...")
    StatusStore.request(getSpecificPlayer(self.playerNum))
end

function ALifeDebugSpawnerWindow:onToggleArrows()
    local compass = ProjectALife.EncounterCompass
    if compass ~= nil then compass.toggle(self.playerNum) end
    self:addLog("Encounter arrows toggled.")
end

function ALifeDebugSpawnerWindow:onToggleMap()
    local squadMap = ProjectALife.SquadMap
    if squadMap ~= nil then squadMap.show(self.playerNum) end
    self:addLog("Squad map opened.")
end

function ALifeDebugSpawnerWindow:onMetaEvent(kind)
    self:addLog("Meta event: " .. tostring(kind) .. "...")
    send(self.playerNum, "debugMetaEvent", { kind = kind })
end

function ALifeDebugSpawnerWindow:onBlackbox()
    self:addLog("Requesting the black box dump...")
    send(self.playerNum, "debugBlackbox", {})
end

function ALifeDebugSpawnerWindow:onModuleQA()
    self:addLog("Requesting the module QA dump...")
    send(self.playerNum, "debugModuleQA", {})
end

function ALifeDebugSpawnerWindow:onTownCensus()
    self:addLog("Requesting the town census...")
    send(self.playerNum, "debugTownCensus", {})
end

function ALifeDebugSpawnerWindow:onDiagnostics()
    self:addLog("Running server diagnostics...")
    send(self.playerNum, "debugDiagnostics", {})
end

function ALifeDebugSpawnerWindow:onActors()
    self:addLog("Reading NPC behaviour and endurance...")
    send(self.playerNum, "debugActors", {})
end

function ALifeDebugSpawnerWindow:onRepUp()
    self:addLog("Adding 10 reputation...")
    send(self.playerNum, "debugRepAdjust", { delta = 10 })
end

function ALifeDebugSpawnerWindow:onRepDown()
    self:addLog("Removing 10 reputation...")
    send(self.playerNum, "debugRepAdjust", { delta = -10 })
end

function ALifeDebugSpawnerWindow:onRepair()
    self:addLog("Repairing invalid runtime state...")
    send(self.playerNum, "debugRepair", {})
end

function ALifeDebugSpawnerWindow:onProtect()
    self:addLog("Adding a protected no-spawn area...")
    send(self.playerNum, "debugAddNoSpawnZone", { radius = 20 })
end

function ALifeDebugSpawnerWindow:onClearZones()
    self:addLog("Clearing the protected areas...")
    send(self.playerNum, "debugClearNoSpawnZones", {})
end

function ALifeDebugSpawnerWindow.onKeyPressed(key)
    local window = ALifeDebugSpawnerWindow.instance
    if window == nil or window:getIsVisible() == false then return end
    if key == Keyboard.KEY_RETURN then window:onDeploy()
    elseif key == Keyboard.KEY_R then window:onRefresh()
    elseif key == Keyboard.KEY_ESCAPE then window:close() end
end

function ALifeDebugSpawnerWindow:prerender()
    ISCollapsableWindow.prerender(self)
    local top = self:titleBarHeight()
    self:drawTextCentre("NPC FACTION  --  SPAWN", self.width / 2, top + 4,
        ROSE.r, ROSE.g, ROSE.b, 1, UIFont.Large)
    local doctrine = dataOf(self.combos and self.combos.doctrine)
    self:drawTextCentre((doctrine == nil or doctrine == "profile")
        and "Doctrine: use each profile's saved coordination behaviour."
        or "Doctrine override: every member of this group runs it.",
        self.width / 2, top + 30, MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)

end

function ALifeDebugSpawnerWindow:render()
    ISCollapsableWindow.render(self)
    local log = self.log or {}
    local first = math.max(1, #log - 3 + 1)
    local y = self.height - 112
    for index = first, #log do
        local entry = log[index]
        local bad = entry.severity == "error"
        local text = entry.text
        if #text > 130 then text = string.sub(text, 1, 129) .. "..." end
        self:drawText(text, PAD, y, bad and BAD.r or MUTED.r,
            bad and BAD.g or MUTED.g, bad and BAD.b or MUTED.b, 1, UIFont.Small)
        y = y + 15
    end
    local target = self.targetPosition
    self:drawTextRight(target ~= nil
        and ("target " .. tostring(target.x) .. ", " .. tostring(target.y)
            .. ", " .. tostring(target.z))
        or "target: your position",
        self.width - PAD, self.height - 112, MUTED.r, MUTED.g, MUTED.b, 1, UIFont.Small)
end

function ALifeDebugSpawnerWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
    ALifeDebugSpawnerWindow.instance = nil
end

function ALifeDebugSpawnerWindow:new(playerNum, square, preferredMode, preferredFaction)
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    local width = math.min(1080, math.max(760, screenW - 60))
    local height = math.min(700, math.max(560, screenH - 60))
    local window = ISCollapsableWindow.new(self, (screenW - width) / 2,
        math.max(10, (screenH - height) / 2), width, height)
    window.playerNum = playerNum
    window.preferredEncounter = preferredMode
    window.preferredFaction = preferredFaction
    window.targetPosition = squarePosition(square)
    window.resizable = false
    window.log = {}
    window.backgroundColor = copyColor(PANEL_BG)
    window.borderColor = copyColor(ROSE)
    window:setTitle("Project A-Life")
    return window
end

function ALifeDebugSpawnerWindow.open(playerNum, square, preferredMode, preferredFaction)
    local console = ProjectALife.AdminConsole
    if console ~= nil and type(console.openFromClassic) == "function" then
        local opened = console.openFromClassic(playerNum, square, preferredMode, preferredFaction)
        if opened ~= nil then return opened end
    end
    return ALifeDebugSpawnerWindow.openClassic(playerNum, square, preferredMode, preferredFaction)
end

function ALifeDebugSpawnerWindow.openClassic(playerNum, square, preferredMode, preferredFaction)

    local prefs = ProjectALife.MenuPrefs
    if prefs ~= nil and type(prefs.allowed) == "function"
            and not prefs.allowed(getSpecificPlayer(playerNum)) then
        return nil
    end
    if ALifeDebugSpawnerWindow.instance ~= nil then
        ALifeDebugSpawnerWindow.instance:close()
    end
    local window = ALifeDebugSpawnerWindow:new(playerNum, square, preferredMode, preferredFaction)
    window:initialise()
    window:addToUIManager()
    ALifeDebugSpawnerWindow.instance = window
    if ALifeDebugSpawnerWindow.catalog ~= nil then
        window:populate(ALifeDebugSpawnerWindow.catalog)
    end

    if prefs ~= nil and type(prefs.reannounce) == "function" then
        prefs.reannounce(getSpecificPlayer(playerNum), nowMs())
    end
    ALifeDebugSpawnerWindow.requestCatalog(playerNum, nowMs(), true)
    StatusStore.request(getSpecificPlayer(playerNum))
    return window
end

function ALifeDebugSpawnerWindow.toggle(playerNum, square)
    local console = ProjectALife.AdminConsole
    if console ~= nil and type(console.current) == "function" and console.current(playerNum) ~= nil then
        console.close(playerNum)
        return
    end
    if ALifeDebugSpawnerWindow.instance ~= nil then
        ALifeDebugSpawnerWindow.instance:close()
        return
    end
    return ALifeDebugSpawnerWindow.open(playerNum, square, nil)
end

local function activeWindow(message, severity)
    local window = ALifeDebugSpawnerWindow.instance
    if window ~= nil then window:addLog(message, severity)
    else ALifeDebugSpawnerWindow.lastMessage = tostring(message or "") end
    return window
end

function ALifeDebugSpawnerWindow.diagnosticsRefused()
    local prefs = ProjectALife.MenuPrefs
    if prefs == nil or type(prefs.diagnosticsRefused) ~= "function" then return nil end
    local window = ALifeDebugSpawnerWindow.instance
    return prefs.diagnosticsRefused(getSpecificPlayer(window ~= nil and window.playerNum or 0), nowMs())
end

function ALifeDebugSpawnerWindow.reasonText(reason)
    local prefs = ProjectALife.MenuPrefs
    if reason ~= "diagnostics_disabled" or prefs == nil
            or type(prefs.refusedText) ~= "function" then
        local encounters = ProjectALife.Encounters
        if encounters ~= nil and type(encounters.refusalText) == "function" then
            local friendly = encounters.refusalText(reason)
            if friendly ~= tostring(reason) then return friendly .. " [" .. tostring(reason) .. "]" end
        end
        return tostring(reason)
    end
    local window = ALifeDebugSpawnerWindow.instance
    return prefs.refusedText(getSpecificPlayer(window ~= nil and window.playerNum or 0))
end

function ALifeDebugSpawnerWindow.outpostLine(arguments)
    if arguments.ok then
        return "Outpost building: " .. tostring(arguments.ops or 0) .. " ops; its squad comes once nobody is within "
            .. tostring(arguments.keepAway or 40) .. " tiles."
    end
    local plan = ProjectALife.SpawnPlan
    if plan ~= nil and type(plan.refusalText) == "function" then
        return "Outpost refused: " .. plan.refusalText(arguments.reason) .. " [" .. tostring(arguments.reason) .. "]"
    end
    return "Outpost refused: " .. ALifeDebugSpawnerWindow.reasonText(arguments.reason)
end

function ALifeDebugSpawnerWindow.shownReply(arguments)
    if arguments.reason ~= "diagnostics_disabled" then return arguments end
    local shown = {}
    for key, value in pairs(arguments) do shown[key] = value end
    shown.reason = ALifeDebugSpawnerWindow.reasonText(arguments.reason)
    return shown
end

ALifeDebugSpawnerWindow.catalogTimeoutMs = 10000
ALifeDebugSpawnerWindow.catalogRetries = 3
ALifeDebugSpawnerWindow.catalogRetryGapMs = 1500
ALifeDebugSpawnerWindow.catalogRefusedGapMs = 3000
ALifeDebugSpawnerWindow.catalogMaxParts = 256
ALifeDebugSpawnerWindow.catalogMetaKeys = { "animations", "modes", "encounters", "outpostPresets" }

function ALifeDebugSpawnerWindow.resetCatalogState()
    ALifeDebugSpawnerWindow.catalogState = {
        pending = false, sentAt = nil, lastPartAt = nil, attempts = 0, retries = 0,
        timeouts = 0, reason = nil, refusedAt = nil, retryAt = nil, playerNum = 0,
        stamp = nil, parts = nil, got = 0, pieces = {},
    }
    ALifeDebugSpawnerWindow.factionProfiles = {}
    return ALifeDebugSpawnerWindow.catalogState
end
ALifeDebugSpawnerWindow.resetCatalogState()

function ALifeDebugSpawnerWindow.toolsAllowed(playerNum)
    local prefs = ProjectALife.MenuPrefs
    if prefs == nil or type(prefs.allowed) ~= "function" then return true end
    return prefs.allowed(getSpecificPlayer(playerNum or 0)) == true
end

function ALifeDebugSpawnerWindow.requestCatalog(playerNum, now, force)
    local state = ALifeDebugSpawnerWindow.catalogState
    now = tonumber(now) or nowMs()
    playerNum = playerNum or 0
    if state.pending and now - (state.lastPartAt or state.sentAt or now)
            < ALifeDebugSpawnerWindow.catalogTimeoutMs then
        return "pending"
    end
    if force ~= true and force ~= "retry" and state.refusedAt ~= nil and now >= state.refusedAt
            and now - state.refusedAt < ALifeDebugSpawnerWindow.catalogRefusedGapMs then
        return "refused"
    end
    if not ALifeDebugSpawnerWindow.toolsAllowed(playerNum) then
        state.pending, state.retryAt = false, nil
        return "unsent"
    end

    state.pending, state.sentAt, state.lastPartAt, state.retryAt = true, now, nil, nil
    state.playerNum = playerNum
    state.attempts = state.attempts + 1
    if force ~= "retry" then state.retries = 0 end
    if not send(playerNum, "debugCatalog", {}) then
        state.pending = false
        state.attempts = state.attempts - 1
        return "unsent"
    end
    return "sent"
end

function ALifeDebugSpawnerWindow.catalogStatus(now)
    local state = ALifeDebugSpawnerWindow.catalogState
    now = tonumber(now) or nowMs()
    local seconds = 0
    if state.pending and state.sentAt ~= nil and now >= state.sentAt then
        seconds = math.floor((now - state.sentAt) / 1000)
    end
    return { pending = state.pending == true, reason = state.reason, seconds = seconds,
        attempts = state.attempts, retries = state.retries }
end

function ALifeDebugSpawnerWindow.catalogReasonText(reason, playerNum)
    local rules = ProjectALife.MenuRules
    if rules ~= nil and type(rules.catalogReasonText) == "function" then
        return rules.catalogReasonText(reason, playerNum)
    end
    return ALifeDebugSpawnerWindow.reasonText(reason)
end

function ALifeDebugSpawnerWindow.catalogTick()
    local state = ALifeDebugSpawnerWindow.catalogState
    if not state.pending and state.retryAt == nil then return false end
    local now = nowMs()
    if not state.pending then
        if now < state.retryAt then return false end
        state.retryAt = nil
        return ALifeDebugSpawnerWindow.requestCatalog(state.playerNum, now, "retry") == "sent"
    end
    local since = state.lastPartAt or state.sentAt or now
    if now - since < ALifeDebugSpawnerWindow.catalogTimeoutMs then return false end
    state.pending = false
    state.timeouts = state.timeouts + 1
    state.reason, state.refusedAt = "timed_out", now
    local seconds = tostring(math.floor(ALifeDebugSpawnerWindow.catalogTimeoutMs / 1000))
    if state.retries >= ALifeDebugSpawnerWindow.catalogRetries then
        activeWindow("Catalog: no answer in " .. seconds .. " s after " .. tostring(state.attempts)
            .. " tries. Press R to ask again.", "error")
        return false
    end
    state.retries = state.retries + 1
    activeWindow("Catalog: no answer in " .. seconds .. " s, asking again ("
        .. tostring(state.retries) .. "/" .. tostring(ALifeDebugSpawnerWindow.catalogRetries) .. ").", "warning")
    return ALifeDebugSpawnerWindow.requestCatalog(state.playerNum, now, "retry") == "sent"
end

function ALifeDebugSpawnerWindow.partOf(arguments)
    local parts = math.floor(tonumber(arguments.parts) or 1)
    local part = math.floor(tonumber(arguments.part) or 1)
    if parts < 1 or parts > ALifeDebugSpawnerWindow.catalogMaxParts or part < 1 or part > parts then
        return nil, nil
    end
    return part, parts
end

function ALifeDebugSpawnerWindow.receiveCatalog(arguments, now)
    local state = ALifeDebugSpawnerWindow.catalogState
    now = tonumber(now) or nowMs()
    if arguments.ok ~= true then
        local reason = tostring(arguments.reason or "refused")
        local fresh = reason ~= state.reason
        state.pending, state.reason, state.refusedAt = false, reason, now
        if reason == "rate_limited" or reason == "diagnostics_disabled" then
            state.retryAt = now + ALifeDebugSpawnerWindow.catalogRetryGapMs
        end
        return false, fresh
    end
    local part, parts = ALifeDebugSpawnerWindow.partOf(arguments)
    if part == nil then return nil end
    if state.stamp ~= arguments.stamp or state.parts ~= parts then
        state.stamp, state.parts, state.got, state.pieces = arguments.stamp, parts, 0, {}
    end
    if state.pieces[part] == nil then
        state.pieces[part] = arguments
        state.got = state.got + 1
    end
    state.lastPartAt = now
    if state.got < parts then return nil end
    local catalog = { ok = true, stamp = arguments.stamp, factions = {}, profiles = {},
        factionCount = arguments.factionCount, profileCount = arguments.profileCount }
    for index = 1, parts do
        local piece = state.pieces[index]
        for _, row in ipairs(type(piece.factions) == "table" and piece.factions or {}) do
            catalog.factions[#catalog.factions + 1] = row
        end

        for _, row in ipairs(type(piece.profiles) == "table" and piece.profiles or {}) do
            catalog.profiles[#catalog.profiles + 1] = row
        end
        for _, key in ipairs(ALifeDebugSpawnerWindow.catalogMetaKeys) do
            if piece[key] ~= nil then catalog[key] = piece[key] end
        end
    end
    state.pending, state.reason, state.refusedAt, state.retryAt = false, nil, nil, nil
    state.retries, state.pieces, state.got, state.parts = 0, {}, 0, nil
    ALifeDebugSpawnerWindow.catalog = catalog
    return catalog
end

function ALifeDebugSpawnerWindow.requestFactionProfiles(playerNum, factionId, now)
    if type(factionId) ~= "string" or factionId == "" or factionId == "*" then return nil end
    now = tonumber(now) or nowMs()
    local entries = ALifeDebugSpawnerWindow.factionProfiles
    local entry = entries[factionId]
    local catalog = ALifeDebugSpawnerWindow.catalog
    local stamp = type(catalog) == "table" and catalog.stamp or nil
    if entry ~= nil and entry.complete and (stamp == nil or entry.stamp == stamp) then return entry.rows end
    if entry ~= nil and entry.pending and now - (entry.lastPartAt or entry.sentAt or now)
            < ALifeDebugSpawnerWindow.catalogTimeoutMs then
        return nil
    end
    if not ALifeDebugSpawnerWindow.toolsAllowed(playerNum) then return nil end
    entry = { pending = true, sentAt = now, got = 0, pieces = {}, rows = {}, complete = false }
    entries[factionId] = entry
    if not send(playerNum or 0, "debugCatalogFaction", { factionId = factionId }) then
        entries[factionId] = nil
        return nil
    end

    if entry.complete then return entry.rows end
    return nil
end

function ALifeDebugSpawnerWindow.receiveFactionProfiles(arguments, now)
    local factionId = type(arguments.factionId) == "string" and arguments.factionId or nil
    if factionId == nil then return false end
    now = tonumber(now) or nowMs()
    local entries = ALifeDebugSpawnerWindow.factionProfiles
    local entry = entries[factionId]
    if arguments.ok ~= true then
        if entry ~= nil then entry.pending, entry.reason = false, tostring(arguments.reason or "refused") end
        return false
    end
    local part, parts = ALifeDebugSpawnerWindow.partOf(arguments)
    if part == nil then return nil end
    if entry == nil then
        entry = { pending = true, sentAt = now, got = 0, pieces = {}, rows = {}, complete = false }
        entries[factionId] = entry
    end
    if entry.stamp ~= arguments.stamp or entry.parts ~= parts then
        entry.stamp, entry.parts, entry.got, entry.pieces = arguments.stamp, parts, 0, {}
    end
    if entry.pieces[part] == nil then
        entry.pieces[part] = type(arguments.profiles) == "table" and arguments.profiles or {}
        entry.got = entry.got + 1
    end
    entry.lastPartAt = now
    if entry.got < parts then return nil end
    local rows = {}
    for index = 1, parts do
        for _, row in ipairs(entry.pieces[index]) do rows[#rows + 1] = row end
    end
    entry.rows, entry.complete, entry.pending, entry.pieces, entry.reason = rows, true, false, {}, nil
    return rows
end

function ALifeDebugSpawnerWindow.profilesFor(factionId)
    local entry = ALifeDebugSpawnerWindow.factionProfiles[factionId or ""]
    if entry ~= nil and entry.complete then return entry.rows end
    local catalog = ALifeDebugSpawnerWindow.catalog
    return type(catalog) == "table" and catalog.profiles or nil
end

function ALifeDebugSpawnerWindow.routeCatalog(command, arguments, window)
    local console = ProjectALife.EncounterConsole
    local consoleOpen = console ~= nil and console.instance ~= nil
    if command == "debugCatalogFactionResult" then
        local rows = ALifeDebugSpawnerWindow.receiveFactionProfiles(arguments)
        if window ~= nil and rows then
            window:addLog(tostring(#rows) .. " profiles ready in " .. tostring(arguments.factionId) .. ".", "success")
        elseif window ~= nil and rows == false then
            window:addLog("Faction profiles refused: " .. ALifeDebugSpawnerWindow.catalogReasonText(
                arguments.reason, window.playerNum), "error")
        end
        return rows
    end
    local catalog, fresh = ALifeDebugSpawnerWindow.receiveCatalog(arguments)
    if catalog then
        if consoleOpen then console.instance:applyCatalog(catalog) end
        if window ~= nil then window:populate(catalog) end
        return catalog
    end
    if catalog ~= false then return nil end
    local playerNum = window ~= nil and window.playerNum or ALifeDebugSpawnerWindow.catalogState.playerNum or 0
    local shown = ALifeDebugSpawnerWindow.catalogReasonText(arguments.reason, playerNum)
    if consoleOpen and type(console.instance.applyCatalogRefusal) == "function" then
        console.instance:applyCatalogRefusal(shown)
    end
    if window ~= nil then
        window:addLog("Catalog error: " .. shown, "error")
    elseif not consoleOpen and fresh and arguments.reason ~= "rate_limited" then

        local rules = ProjectALife.MenuRules
        local player = getSpecificPlayer(playerNum)
        if player ~= nil and rules ~= nil and type(rules.catalogWaitText) == "function" then
            player:Say(rules.catalogWaitText(playerNum))
        end
    end
    return false
end

local function onSpawnAccepted(arguments)
    local requestId = tostring(arguments.requestId or "")
    local state = ALifeDebugSpawnerWindow.requests[requestId]
    if state == nil then
        state = { requested = 0, accepted = 0, rejected = 0, started = 0,
            completed = 0, active = 0, failed = 0, jobs = {} }
        ALifeDebugSpawnerWindow.requests[requestId] = state
    end
    state.accepted = tonumber(arguments.accepted) or 0
    state.rejected = tonumber(arguments.failed) or 0
    state.groupId = arguments.groupId
    state.mode = arguments.mode or state.mode
    state.scene = arguments.scene
    state.origin = arguments.origin
    if arguments.ok then
        local origin = type(state.origin) == "table" and (" @ "
            .. tostring(math.floor(tonumber(state.origin.x) or 0)) .. ","
            .. tostring(math.floor(tonumber(state.origin.y) or 0))) or ""
        local scene = state.scene ~= nil and (" + complete "
            .. tostring(state.scene) .. " scene") or ""
        activeWindow("Group queued: " .. tostring(state.accepted) .. " accepted, "
            .. tostring(state.rejected) .. " rejected | " .. tostring(state.mode)
            .. scene .. origin,
            state.rejected > 0 and "warning" or "success")
    else
        activeWindow(ALifeDebugSpawnerWindow.refusalLine(arguments), "error")
    end
end

function ALifeDebugSpawnerWindow.refusalLine(arguments)
    local named = type(arguments.encounterId) == "string" and (" (" .. arguments.encounterId .. ")") or ""
    local text = arguments.text
    if type(text) == "string" and text ~= "" and text ~= tostring(arguments.reason) then
        return "Spawn rejected" .. named .. ": " .. text .. " [" .. tostring(arguments.reason) .. "]"
    end
    return "Spawn rejected" .. named .. ": " .. ALifeDebugSpawnerWindow.reasonText(arguments.reason)
end

local function onSpawnJob(arguments)
    local requestId = tostring(arguments.requestId or "")
    local state = ALifeDebugSpawnerWindow.requests[requestId]
    if state == nil then
        state = { requested = tonumber(arguments.requested) or 0,
            accepted = tonumber(arguments.accepted) or 0,
            rejected = tonumber(arguments.rejected) or 0,
            started = 0, completed = 0, active = 0, failed = 0, jobs = {} }
        ALifeDebugSpawnerWindow.requests[requestId] = state
    end
    local operationId = tostring(arguments.operationId or arguments.jobIndex or "unknown")
    local job = state.jobs[operationId] or { started = false, completed = false }
    state.jobs[operationId] = job
    if arguments.completed == true then
        if not job.completed then
            job.completed = true
            state.completed = state.completed + 1
            if arguments.ok then state.active = state.active + 1
            else state.failed = state.failed + 1 end
        end
        activeWindow("Spawn progress: " .. tostring(state.completed) .. "/"
            .. tostring(state.accepted) .. " settled (" .. tostring(state.active)
            .. " active, " .. tostring(state.failed) .. " failed)"
            .. (arguments.ok and "" or " | " .. tostring(arguments.reason)),
            arguments.ok and "info" or "error")
    elseif arguments.ok and not job.started then
        job.started = true
        state.started = state.started + 1
        activeWindow("Starting group member " .. tostring(arguments.jobIndex or state.started)
            .. "/" .. tostring(state.accepted) .. "...")
    elseif not arguments.ok then
        activeWindow("Spawn job failed: " .. tostring(arguments.reason), "error")
    end
end

local function onSpawnGroup(arguments)
    local requestId = tostring(arguments.requestId or "")
    local state = ALifeDebugSpawnerWindow.requests[requestId] or {}
    state.accepted = tonumber(arguments.accepted) or state.accepted or 0
    state.rejected = tonumber(arguments.rejected) or state.rejected or 0
    state.completed = tonumber(arguments.completedCount) or state.completed or 0
    state.active = tonumber(arguments.active) or state.active or 0
    state.failed = tonumber(arguments.failed) or state.failed or 0
    state.groupId = arguments.groupId or state.groupId
    state.mode = arguments.mode or state.mode
    ALifeDebugSpawnerWindow.requests[requestId] = state
    local why = ALifeDebugSpawnerWindow.refusalCounts(arguments.reasons)
    activeWindow("Group complete: " .. tostring(state.active) .. "/"
        .. tostring(state.accepted) .. " active, " .. tostring(state.failed)
        .. " failed | " .. tostring(state.mode or "roam") .. " | "
        .. tostring(state.groupId or "no group id")
        .. (arguments.reason ~= nil and (" | first refusal: " .. ALifeDebugSpawnerWindow.reasonText(arguments.reason)) or "")
        .. (why ~= "" and (" | refused: " .. why) or ""),
        arguments.ok and "success" or "error")

    if arguments.ok ~= true and type(isDebugEnabled) == "function"
            and isDebugEnabled() == true then
        local player = getSpecificPlayer(0)
        if player ~= nil and type(player.Say) == "function" then
            player:Say(ALifeDebugSpawnerWindow.shortGroupText(state.active,
                tonumber(arguments.requested) or state.accepted, why, arguments.reason))
        end
    end
    ALifeDebugSpawnerWindow.tellSquadMap("debugSpawnGroupResult", arguments)
end

function ALifeDebugSpawnerWindow.shortGroupText(active, requested, why, first)
    local tail = why
    if tail == nil or tail == "" then tail = first ~= nil and tostring(first) or "" end
    local text = "A-Life: spawned " .. tostring(active or 0) .. " of " .. tostring(requested or 0)
    if tail ~= "" then text = text .. " (" .. tail .. ")" end
    return text
end

function ALifeDebugSpawnerWindow.refusalCounts(reasons)
    if type(reasons) ~= "table" then return "" end
    local parts = {}
    for reason, count in pairs(reasons) do
        parts[#parts + 1] = ALifeDebugSpawnerWindow.reasonText(reason) .. " x" .. tostring(count)
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

function ALifeDebugSpawnerWindow.tellSquadMap(command, arguments)
    if type(isClient) == "function" and isClient() then return false end
    local squadMap = ProjectALife.SquadMap
    if squadMap == nil or type(squadMap.receive) ~= "function" then return false end
    squadMap.receive("ProjectALife", command, arguments)
    return true
end

local function onDiagnostics(arguments)
    local healthy = arguments.ok == true
    local window = activeWindow((healthy and "Diagnostics healthy: " or "Diagnostics found faults: ")
        .. tostring(arguments.active or 0) .. " active, "
        .. tostring(arguments.errors or 0) .. " error(s), "
        .. tostring(arguments.warnings or 0) .. " warning(s), "
        .. tostring(arguments.pendingAdminSpawns or 0) .. " admin spawn(s) pending.",
        healthy and "success" or "error")
    if window == nil then return end
    local movement = arguments.movement
    if type(movement) == "table" then
        window:addLog("Movement: " .. tostring(movement.pathRequested or 0)
            .. " paths, " .. tostring(movement.stalls or 0) .. " stalls, "
            .. tostring(movement.traversalFailures or 0) .. " traversal failure(s), "
            .. tostring(movement.unreachableFailures or 0) .. " unreachable target(s).",
            (movement.stalls or 0) > 0 and "warning" or "info")
    end
    for index, issue in ipairs(type(arguments.issues) == "table" and arguments.issues or {}) do
        if index > 6 then break end
        window:addLog(tostring(issue.severity or "error") .. ": "
            .. tostring(issue.code or "unknown") .. " " .. tostring(issue.detail or ""),
            issue.severity == "warning" and "warning" or "error")
    end
end

local function enduranceText(actor)
    local current = tonumber(actor.endurance)
    local maximum = tonumber(actor.enduranceMaximum)
    if current and maximum and maximum > 0 then
        local filled = math.max(0, math.min(10, math.floor(current / maximum * 10 + 0.5)))
        return "[" .. string.rep("#", filled) .. string.rep("-", 10 - filled) .. "] "
            .. string.format("%.2f/%.2f", current, maximum)
    end
    if current then return string.format("%.2f", current) end
    return tostring(actor.profileEndurance or "?")
end

local function onActors(arguments)
    local actors = type(arguments.actors) == "table" and arguments.actors or {}
    local window = activeWindow("NPC inspector: " .. tostring(#actors)
        .. (arguments.truncated and "+" or "") .. " actor(s), "
        .. tostring(arguments.pendingAdminSpawns or 0) .. " admin spawn(s) pending.")
    if window == nil then return end
    for index, actor in ipairs(actors) do
        if index > 24 then
            window:addLog("...additional actors omitted from this panel.", "warning")
            break
        end
        window:addLog(shortUid(actor.uid) .. " | " .. tostring(actor.lifecycle)
            .. "/" .. tostring(actor.activity) .. " | "
            .. tostring(actor.behavior or actor.intent) .. " | combat "
            .. tostring(actor.combatMode or actor.activity) .. " | END "
            .. enduranceText(actor) .. " | " .. tostring(actor.profileName or actor.profileId)
            .. " @ " .. tostring(actor.x) .. "," .. tostring(actor.y) .. "," .. tostring(actor.z))
    end
end

ALifeDebugSpawnerWindow.clientQANames = { "HeliLight", "Executor", "DecisionLoop", "Movement", "Combat", "Speech",
    "TalkInput", "ModuleRobbery", "ShellSimulation", "Lifecycle", "Perception", "SceneKit",
    "EncounterDirector", "ProfileHydrator", "AnimationClient", "Watchdog", "ObstacleTraversal",
    "Entrances", "ModuleBreach", "Risk", "Gait", "BlackBox", "ModuleFear", "Interop" }

function ALifeDebugSpawnerWindow.clientQALines()
    local lines = {}
    local compat = ProjectALife.CompatRegistry
    if compat ~= nil and type(compat.qaLine) == "function" then lines[#lines + 1] = compat.qaLine() end
    for _, name in ipairs(ALifeDebugSpawnerWindow.clientQANames) do
        local system = ProjectALife[name]
        local metrics = type(system) == "table" and type(system.metrics) == "table" and system.metrics or nil
        local parts = {}
        for key, value in pairs(metrics or {}) do
            if type(value) == "table" then
                local inner = {}
                for reason, count in pairs(value) do
                    if type(count) ~= "table" then inner[#inner + 1] = tostring(reason) .. ":" .. tostring(count) end
                end
                table.sort(inner)
                if #inner > 0 then parts[#parts + 1] = tostring(key) .. "={" .. table.concat(inner, ";") .. "}" end
            else
                parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
            end
        end
        table.sort(parts)
        if #parts > 0 then lines[#lines + 1] = "[ALIFE-QA] client " .. name .. ": " .. table.concat(parts, " ") end
    end
    local guard = ProjectALife.OrphanGuard
    if type(guard) == "table" then
        lines[#lines + 1] = "[ALIFE-QA] client OrphanGuard: scans=" .. tostring(guard.scans or 0)
            .. " removed=" .. tostring(guard.removed or 0) .. " disarmed=" .. tostring(guard.disarmed or 0)
            .. " ghosts=" .. tostring(guard.ghosts or 0)
    end
    local box = ProjectALife.BlackBox
    local visuals = ProjectALife.AnimationClient
    if visuals ~= nil and type(visuals.visualsQALine) == "function" then lines[#lines + 1] = visuals.visualsQALine() end
    local bubbles = ProjectALife.SpeechBubbles
    if bubbles ~= nil and type(bubbles.qaLine) == "function" then lines[#lines + 1] = bubbles.qaLine() end
    local armor = ProjectALife.Armor
    if armor ~= nil and type(armor.qaLine) == "function" then lines[#lines + 1] = armor.qaLine() end
    local cof = ProjectALife.CryOfFearAdapter
    if cof ~= nil and type(cof.qaLine) == "function" then lines[#lines + 1] = cof.qaLine() end
    if box ~= nil and type(box.readBuild) == "function" then box.readBuild() end
    lines[#lines + 1] = "[ALIFE-QA] client build=" .. tostring(box ~= nil and box.BUILD or "unknown")
    return lines
end

function ALifeDebugSpawnerWindow.applyAdminFlags(arguments)
    local executor = ProjectALife.Executor
    local uid = type(arguments.uid) == "string" and arguments.uid or nil
    local executed = executor ~= nil and type(executor.executed) == "table" and executor.executed or nil
    local entry = uid ~= nil and executed ~= nil and executed[uid] or nil
    if entry == nil or entry.shell == nil then return false end
    if tonumber(arguments.generation) ~= nil and tonumber(entry.generation) ~= tonumber(arguments.generation) then
        return false
    end
    local shell, flags = entry.shell, type(arguments.flags) == "table" and arguments.flags or {}
    if type(shell.getModData) ~= "function" then return false end
    local data = shell:getModData()
    if type(data) ~= "table" then return false end
    local leash = type(flags.leash) == "table" and flags.leash or nil
    data.ProjectALifeAdminManaged = true
    data.ProjectALifeAdminPersistent = flags.persistent == true
    data.ProjectALifeInvulnerable = flags.invulnerable == true
    data.ProjectALifeAdminStationary = flags.stationary == true
    data.ProjectALifeLeashX = leash and tonumber(leash.x) or nil
    data.ProjectALifeLeashY = leash and tonumber(leash.y) or nil
    data.ProjectALifeLeashZ = leash and tonumber(leash.z) or nil
    data.ProjectALifeLeashRadius = leash and tonumber(leash.radius) or nil
    local registry = ProjectALife.ActorRegistry
    local record = registry ~= nil and type(registry.records) == "table" and registry.records[uid] or nil
    if type(record) == "table" then
        record.memory = type(record.memory) == "table" and record.memory or {}
        record.memory.admin = flags
    end
    local simulation = ProjectALife.ShellSimulation
    if flags.invulnerable == true and simulation ~= nil and type(simulation.setHealth) == "function"
            and type(simulation.maximumFor) == "function" then
        pcall(simulation.setHealth, shell, simulation.maximumFor(shell))
    end
    local movement = ProjectALife.Movement
    if flags.stationary == true and movement ~= nil and type(movement.stop) == "function" then
        pcall(movement.stop, shell)
    end
    local animations = ProjectALife.Animations
    if animations ~= nil and type(animations.syncPresentation) == "function" then
        pcall(animations.syncPresentation, shell)
    end
    return true
end

local function onServerCommand(module, command, arguments)
    if module ~= "ProjectALife" or type(arguments) ~= "table" then return end
    if command == "adminActorFlagsApply" then
        ALifeDebugSpawnerWindow.applyAdminFlags(arguments)
        return
    end
    local console = ProjectALife.AdminConsole
    if console ~= nil and type(console.tap) == "function" then pcall(console.tap, command, arguments) end
    local window = ALifeDebugSpawnerWindow.instance

    if arguments.reason == "diagnostics_disabled" then
        ALifeDebugSpawnerWindow.diagnosticsRefused()
    end
    if command == "debugCatalogResult" or command == "debugCatalogFactionResult" then

        ALifeDebugSpawnerWindow.routeCatalog(command, arguments, window)
        return
    elseif command == "debugDirectorStateResult" then
        local console = ProjectALife.EncounterConsole
        if console ~= nil and console.instance ~= nil then
            console.instance:applyDirector(ALifeDebugSpawnerWindow.shownReply(arguments))
        end
        return
    elseif command == "debugMetaEventResult" then
        if window ~= nil then
            window:addLog(arguments.ok and ("  server fired meta " .. tostring(arguments.kind) .. ".")
                or ("  server refused meta " .. tostring(arguments.kind) .. ": "
                    .. ALifeDebugSpawnerWindow.reasonText(arguments.reason)))
        end
        return
    elseif command == "debugModuleQAResult" or command == "debugBlackboxResult" then
        local kind = command == "debugModuleQAResult" and "qa" or "black box"

        if type(isClient) == "function" and isClient() then
            local recorder = ProjectALife.BlackBox
            if recorder ~= nil and type(recorder.dumpAll) == "function" then
                local ok, count = pcall(recorder.dumpAll, "requested-client-" .. kind)
                print("[ALIFE-QA] client dump: ok=" .. tostring(ok) .. " live_shells=" .. tostring(count))
            end
            print(table.concat(ALifeDebugSpawnerWindow.clientQALines(), "\n"))
            arguments.where = tostring(arguments.where or "the SERVER log") .. "; client recorder in your console.txt"
        end
        local console = ProjectALife.EncounterConsole
        local consoleOpen = console ~= nil and console.instance ~= nil
        if consoleOpen then
            console.instance:applyDumpResult(kind, ALifeDebugSpawnerWindow.shownReply(arguments))
        end
        if window ~= nil then

            local where = tostring(arguments.where or "console.txt")
            window:addLog(arguments.ok and ((kind == "qa"
                    and "Module QA written to " or "Black box written to ") .. where)
                or (string.upper(kind) .. " dump failed: "
                    .. ALifeDebugSpawnerWindow.reasonText(arguments.reason or "unknown")),
                arguments.ok and "success" or "error")
        elseif not consoleOpen and arguments.reason == "diagnostics_disabled" then

            local player = getSpecificPlayer(0)
            if player ~= nil then player:Say(ALifeDebugSpawnerWindow.reasonText(arguments.reason)) end
        end
        return
    elseif command == "debugPickedOverResult" then
        local player = getSpecificPlayer(0)
        if player ~= nil then
            local Text = ProjectALife.Text
            if arguments.ok == true then
                player:Say(Text.ui("Picked-over building: level {level}, {applied}",
                    { level = tostring(arguments.level or 0), applied = tostring(arguments.applied or "") }))
            else
                player:Say(Text.ui("Picked-over: {reason}", { reason = ALifeDebugSpawnerWindow.reasonText(arguments.reason or "unknown") }))
            end
        end
        return
    elseif command == "debugTownCensusResult" then

        if window ~= nil then
            window:addLog(arguments.ok and ("Town census (" .. tostring(arguments.count or 0)
                    .. " towns) written to " .. tostring(arguments.where or "console.txt"))
                or ("Town census failed: " .. ALifeDebugSpawnerWindow.reasonText(arguments.reason or "unknown")),
                arguments.ok and "success" or "error")
        elseif arguments.reason == "diagnostics_disabled" then

            local player = getSpecificPlayer(0)
            if player ~= nil then player:Say(ALifeDebugSpawnerWindow.reasonText(arguments.reason)) end
        end
        return
    elseif command == "alifeDiagnosticsResult" then

        local prefs = ProjectALife.MenuPrefs
        local newRefusal = arguments.ok ~= true
        if prefs ~= nil and type(prefs.acknowledge) == "function" then
            newRefusal = prefs.acknowledge(arguments)
        end
        if arguments.ok == true then
            activeWindow("Diagnostics " .. (arguments.enabled and "on" or "off")
                .. ", flight recorder " .. (arguments.recorder and "on" or "off") .. ".", "success")
        elseif newRefusal then
            activeWindow("Diagnostics refused by the server: " .. tostring(arguments.reason), "error")
        end
        return
    elseif command == "debugSafehouseResult" or command == "safehouseHelloResult" then
        local safehouse = ProjectALife.SafehouseClient
        if safehouse ~= nil and type(safehouse.receive) == "function" then safehouse.receive(command, arguments) end
        return
    elseif command == "debugEncounterMarksResult" then
        local compass = ProjectALife.EncounterCompass
        if compass ~= nil then compass.apply(arguments) end
        return
    elseif command == "outpostRadioListResult" or command == "outpostRadioDisableResult"
            or command == "outpostRadioUseResult" then

        local menu = ProjectALife.OutpostRadioMenu
        if menu ~= nil and type(menu.receive) == "function"
                and not (type(isClient) == "function" and isClient()) then
            menu.receive("ProjectALife", command, arguments)
        end
        return
    elseif ProjectALife.SquadMap ~= nil and type(ProjectALife.SquadMap.actionResults) == "table"
            and ProjectALife.SquadMap.actionResults[command] ~= nil then

        ProjectALife.SquadMap.receive("ProjectALife", command, arguments)
        return
    elseif command == "debugSquadMapResult" then

        local squadMap = ProjectALife.SquadMap
        if squadMap ~= nil and type(squadMap.receive) == "function" then
            squadMap.receive("ProjectALife", command, arguments)
        end
        return
    elseif command == "debugSpawnResult" then
        local console = ProjectALife.EncounterConsole
        if console ~= nil and console.instance ~= nil then
            console.instance:applyResult(ALifeDebugSpawnerWindow.shownReply(arguments))
        end
        onSpawnAccepted(arguments)
        ALifeDebugSpawnerWindow.tellSquadMap(command, arguments)
    elseif command == "debugPurgeActorsResult" then
        activeWindow("Removed " .. tostring(arguments.removed or 0) .. " actor(s), "
            .. tostring(arguments.failed or 0) .. " failed.", arguments.ok and "success" or "error")
        ALifeDebugSpawnerWindow.tellSquadMap(command, arguments)
    elseif command == "debugSpawnJobResult" then
        onSpawnJob(arguments)
    elseif command == "debugSpawnGroupResult" then
        onSpawnGroup(arguments)
    elseif command == "debugDiagnosticsResult" then
        onDiagnostics(arguments)
    elseif command == "debugActorsResult" then
        onActors(arguments)
    elseif command == "debugRepAdjustResult" then
        activeWindow(arguments.ok and ("Reputation " .. tostring(arguments.before) .. " -> " .. tostring(arguments.score)
            .. " (" .. tostring(arguments.level) .. ")") or "Reputation change refused.",
            arguments.ok and "success" or "error")
    elseif command == "debugRepairResult" then
        local report = arguments.report
        activeWindow("Repair: " .. tostring(arguments.repaired or 0) .. " fixed, "
            .. tostring(arguments.failed or 0) .. " failed; health "
            .. tostring(type(report) == "table" and report.ok == true and "OK" or "needs review"),
            arguments.ok and "success" or "error")
    elseif command == "debugAddNoSpawnZoneResult" then
        activeWindow(arguments.ok and "Protected area added."
            or ("Protection failed: " .. ALifeDebugSpawnerWindow.reasonText(arguments.reason)),
            arguments.ok and "success" or "error")
    elseif command == "debugClearNoSpawnZonesResult" then
        activeWindow(arguments.ok
            and ("Cleared " .. tostring(arguments.cleared or 0) .. " protected area(s).")
            or ("Clear failed: " .. ALifeDebugSpawnerWindow.reasonText(arguments.reason)),
            arguments.ok and "success" or "error")
    elseif command == "debugBuildOutpostResult" then
        activeWindow(ALifeDebugSpawnerWindow.outpostLine(arguments), arguments.ok and "success" or "error")
    end
end

ProjectALife.DebugClientReceive = onServerCommand

StatusStore.subscribe(function(status)
    local window = ALifeDebugSpawnerWindow.instance
    if window == nil or type(status) ~= "table" then return end
    window:addLog("Runtime " .. (status.runtimeEnabled == false and "disabled" or "enabled")
        .. " | health " .. (status.healthOk and "OK" or
            (tostring(status.healthErrors or 0) .. " error(s)"))
        .. " | actors " .. tostring(status.active or 0) .. "/" .. tostring(status.total or 0)
        .. " | shells " .. tostring(status.shells or 0)
        .. " | pending " .. tostring(status.pendingSpawns or 0),
        status.healthOk and "success" or "error")
end)

if type(Events) == "table" and Events.OnServerCommand ~= nil then
    Events.OnServerCommand.Add(onServerCommand)
end

if type(Events) == "table" and Events.OnKeyPressed ~= nil then
    Events.OnKeyPressed.Add(ALifeDebugSpawnerWindow.onKeyPressed)
end

if type(Events) == "table" and Events.OnTick ~= nil then
    Events.OnTick.Add(ALifeDebugSpawnerWindow.catalogTick)
end

return ALifeDebugSpawnerWindow
