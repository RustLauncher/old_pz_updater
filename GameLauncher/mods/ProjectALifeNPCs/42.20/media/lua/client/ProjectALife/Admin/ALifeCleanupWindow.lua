require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISTickBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISScrollingListBox"

ProjectALife = ProjectALife or {}

local Client = {
    state = nil, lists = {}, listKind = "pending", overrides = {}, message = nil, markersOn = false,
    markerText = "[A-Life site]", lastScanTotal = nil, requestedAt = {},
}
ProjectALife.CleanupClient = Client

Client.reasons = {
    admin_required = "Only an admin may use this.",
    cleanup_busy = "A scan or a cleanup is already running.",
    cleanup_running = "A cleanup is already running.",
    confirm_phrase_required = "Type the confirmation phrase exactly.",
    second_confirmation_required = "Type the second confirmation phrase too.",
    no_scope = "Tick at least one thing to remove.",
    runtime_not_started = "A-Life is not running in this world yet. Wait for it to start.",
    already_done = "The cleanup is finished. Use 'Let A-Life spawn again' to undo the lock.",
    nothing_to_cancel = "Nothing to cancel.",
    nothing_to_finish = "There is no running cleanup to finish.",
    rate_limited = "Too fast, try again in a moment.",
    no_job = "Run a scan first.",
    unknown_list = "That list does not exist.",
}

Client.rows = {
    { key = "npcs", label = "People: NPCs, squads, visitors, raiders", count = "npcs.found", on = true },
    { key = "bases", label = "Bases: outposts, camps, scenes, props", count = "bases.found", on = true },
    { key = "vehicles", label = "Vehicles A-Life placed", count = "vehicles.found", on = true },
    { key = "markers", label = "Map markers and contact lists", count = "markers.havens", on = true },
    { key = "worldState", label = "A-Life world data (mod data)", count = "world.tables", on = true },
    { key = "corpsesAndLoot", label = "NPC corpses and A-Life issued loot", count = "loot.corpses", on = false },
    { key = "companions", label = "Companions that follow you", count = "npcs.companions", on = false },
    { key = "reputation", label = "Reputation (risky)", count = "reputation.tables", on = false, risky = true },
    { key = "unverified", label = "Unverified objects (risky)", count = "bases.unverified", on = false, risky = true },
    { key = "safehouses", label = "Also objects inside safehouses", count = "bases.protected", on = false },
    { key = "creatorStore", label = "Server copy of Creator data (risky)", count = "creator.tables", on = false, risky = true },
}

Client.tabs = {
    { kind = "pending", label = "Pending" }, { kind = "sites", label = "Sites" }, { kind = "skipped", label = "Skipped" },
    { kind = "protected", label = "Protected" }, { kind = "unverified", label = "Unverified" },
    { kind = "companions", label = "Companions" }, { kind = "report", label = "Report" },
}

function Client.send(command, args)
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil
    if player == nil or type(sendClientCommand) ~= "function" then return false end
    sendClientCommand(player, "ProjectALife", command, args or {})
    return true
end

function Client.counts()
    local state = Client.state
    local job = type(state) == "table" and state.job or nil
    return type(job) == "table" and job.counts or {}
end

function Client.mode()
    local state = Client.state
    return type(state) == "table" and state.mode or "idle"
end

function Client.sumFound(counts)
    local total = 0
    for _, key in ipairs({ "npcs.found", "bases.found", "vehicles.found", "loot.corpses", "bases.protected", "bases.unverified" }) do
        total = total + (tonumber(counts[key]) or 0)
    end
    return total
end

function Client.removedTotal(counts)
    local total = 0
    for key, value in pairs(counts) do
        if string.sub(key, -8) == ".removed" then total = total + (tonumber(value) or 0) end
    end
    return total
end

function Client.reasonText(reason)
    return Client.reasons[tostring(reason)] or tostring(reason)
end

function Client.clearMarkers(arguments)
    local instance = ISWorldMap_instance
    local api = instance ~= nil and instance.mapAPI ~= nil and type(instance.mapAPI.getSymbolsAPI) == "function"
        and instance.mapAPI:getSymbolsAPI() or nil
    local removed = 0
    if api ~= nil and type(api.getSymbolCount) == "function" and type(api.removeSymbolByIndex) == "function" then
        local prefixes = { "Camp", "House", "Outpost", "Post", "Home" }
        for index = api:getSymbolCount() - 1, 0, -1 do
            local symbol = api:getSymbolByIndex(index)
            if symbol ~= nil and type(symbol.getWorldX) == "function" then
                local text = nil
                if type(symbol.getUntranslatedText) == "function" then text = symbol:getUntranslatedText() end
                if text == nil and type(symbol.getTranslatedText) == "function" then text = symbol:getTranslatedText() end
                local named = false
                for _, prefix in ipairs(prefixes) do
                    if type(text) == "string" and string.sub(text, 1, #prefix) == prefix then named = true end
                end
                if text == Client.markerText then named = true end
                if named then
                    for _, row in ipairs(type(arguments.rows) == "table" and arguments.rows or {}) do
                        if math.abs(symbol:getWorldX() - tonumber(row.x)) <= 1.5 and math.abs(symbol:getWorldY() - tonumber(row.y)) <= 1.5 then
                            api:removeSymbolByIndex(index)
                            removed = removed + 1
                            break
                        end
                    end
                end
            end
        end
    end
    local radio = ProjectALife.FieldRadioData
    if radio ~= nil and type(radio.reset) == "function" then pcall(radio.reset) end
    Client.message = "Map markers removed here: " .. tostring(removed)
    return removed
end

function Client.toggleMarkers()
    local instance = ISWorldMap_instance
    if instance == nil and ISWorldMap ~= nil and type(ISWorldMap.ShowWorldMap) == "function" then
        pcall(ISWorldMap.ShowWorldMap, 0, 0, 0, 1.0)
        instance = ISWorldMap_instance
    end
    local api = instance ~= nil and instance.mapAPI ~= nil and type(instance.mapAPI.getSymbolsAPI) == "function"
        and instance.mapAPI:getSymbolsAPI() or nil
    if api == nil then
        Client.message = "Open the world map once, then press this again."
        return false
    end
    if Client.markersOn then
        for index = api:getSymbolCount() - 1, 0, -1 do
            local symbol = api:getSymbolByIndex(index)
            local text = symbol ~= nil and type(symbol.getUntranslatedText) == "function" and symbol:getUntranslatedText() or nil
            if text == Client.markerText then api:removeSymbolByIndex(index) end
        end
        Client.markersOn = false
        return true
    end
    local rows = {}
    for _, kind in ipairs({ "pending", "sites", "protected", "unverified", "skipped" }) do
        local list = Client.lists[kind]
        for _, row in ipairs(list ~= nil and list.rows or {}) do rows[#rows + 1] = row end
    end
    for _, row in ipairs(type(Client.state) == "table" and Client.state.pendingRows or {}) do rows[#rows + 1] = row end
    for _, row in ipairs(rows) do
        if tonumber(row.x) ~= nil and tonumber(row.y) ~= nil then
            pcall(function()
                local symbol = api:addUntranslatedText(Client.markerText, api:getDefaultTextLayerID(), tonumber(row.x), tonumber(row.y))
                symbol:setRGBA(0.9, 0.2, 0.2, 1.0)
                symbol:setAnchor(0.5, 0.5)
            end)
        end
    end
    Client.markersOn = true
    return true
end

function Client.teleport(row)
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil
    if player == nil or type(row) ~= "table" or tonumber(row.x) == nil or tonumber(row.y) == nil then return false end
    local x, y, z = math.floor(tonumber(row.x)), math.floor(tonumber(row.y)), math.floor(tonumber(row.z) or 0)
    if type(isClient) == "function" and isClient() == true then
        if type(SendCommandToServer) ~= "function" then return false end
        SendCommandToServer("/teleportto " .. x .. "," .. y .. "," .. z)
        return true
    end
    if type(player.teleportTo) == "function" then
        return pcall(player.teleportTo, player, x + 0.5, y + 0.5, z)
    end
    local ok = pcall(function()
        player:setX(x + 0.5)
        player:setY(y + 0.5)
        player:setZ(z)
        player:setLx(x + 0.5)
        player:setLy(y + 0.5)
        player:setLz(z)
    end)
    return ok
end

function Client.showOnMap(row)
    if type(row) ~= "table" or tonumber(row.x) == nil or ISWorldMap == nil or type(ISWorldMap.ShowWorldMap) ~= "function" then
        return false
    end
    return pcall(ISWorldMap.ShowWorldMap, 0, tonumber(row.x), tonumber(row.y), 12.0)
end

function Client.receive(module, command, args)
    if module ~= "ProjectALife" or type(command) ~= "string" or string.sub(command, 1, 7) ~= "cleanup" then return end
    args = type(args) == "table" and args or {}
    if command == "cleanupMarkers" then
        Client.clearMarkers(args)
    elseif command == "cleanupListResult" then
        if args.ok == true and args.kind ~= nil then Client.lists[args.kind] = args else Client.message = Client.reasonText(args.reason) end
    else
        if args.ok == false and args.reason ~= nil then Client.message = Client.reasonText(args.reason) else Client.message = nil end
        if args.mode ~= nil then
            Client.state = args
            local job = args.job
            if type(job) == "table" and job.kind == "scan" and job.finished == true then
                Client.lastScanTotal = Client.sumFound(job.counts or {})
            end
        end
    end
    local window = ALifeCleanupWindow ~= nil and ALifeCleanupWindow.instance or nil
    if window ~= nil then window:refresh() end
end

ALifeCleanupWindow = ISCollapsableWindow:derive("ALifeCleanupWindow")
ALifeCleanupWindow.instance = nil

function ALifeCleanupWindow:new()
    local width, height = 780, 640
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    local window = ISCollapsableWindow.new(self, math.max(10, (screenW - width) / 2), math.max(10, (screenH - height) / 2), width, height)
    window.resizable = false
    window:setTitle("CLEANUP A-LIFE")
    window.backgroundColor = { r = 0.055, g = 0.060, b = 0.064, a = 0.97 }
    window.borderColor = { r = 0.72, g = 0.55, b = 0.32, a = 1 }
    return window
end

function ALifeCleanupWindow:addButton(x, y, w, label, handler)
    local button = ISButton:new(x, y, w, 24, label, self, handler)
    button:initialise()
    button:instantiate()
    button.backgroundColor = { r = 0.095, g = 0.100, b = 0.105, a = 0.96 }
    button.borderColor = { r = 0.30, g = 0.32, b = 0.33, a = 1 }
    self:addChild(button)
    return button
end

function ALifeCleanupWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top = self:titleBarHeight()
    self.ticks = ISTickBox:new(14, top + 90, 10, 18, "", self, ALifeCleanupWindow.onTick)
    self.ticks:initialise()
    self.ticks:instantiate()
    self.ticks.autoWidth = true
    self:addChild(self.ticks)
    for _, row in ipairs(Client.rows) do self.ticks:addOption(row.label, row.key) end
    for index, row in ipairs(Client.rows) do self.ticks:setSelected(index, row.on == true) end

    self.phrase = ISTextEntryBox:new("", 14, top + 422, 180, 22)
    self.phrase:initialise()
    self.phrase:instantiate()
    self:addChild(self.phrase)
    self.phrase2 = ISTextEntryBox:new("", 204, top + 422, 170, 22)
    self.phrase2:initialise()
    self.phrase2:instantiate()
    self:addChild(self.phrase2)

    self.scanButton = self:addButton(14, top + 452, 110, "1. Scan", ALifeCleanupWindow.onScan)
    self.runButton = self:addButton(132, top + 452, 130, "2. REMOVE", ALifeCleanupWindow.onRun)
    self.cancelButton = self:addButton(270, top + 452, 104, "Cancel run", ALifeCleanupWindow.onCancel)
    self.finishButton = self:addButton(14, top + 482, 178, "Finish, leave pending", ALifeCleanupWindow.onFinish)
    self.reopenButton = self:addButton(200, top + 482, 174, "Let A-Life spawn again", ALifeCleanupWindow.onReopen)
    self.refreshButton = self:addButton(14, top + 512, 110, "Refresh", ALifeCleanupWindow.onRefresh)
    self.closeButton = self:addButton(132, top + 512, 110, "Close", ALifeCleanupWindow.onClose)
    self.mapButton = self:addButton(250, top + 512, 124, "Markers on map", ALifeCleanupWindow.onToggleMarkers)

    local x0 = 392
    self.tabButtons = {}
    for index, tab in ipairs(Client.tabs) do
        local button = self:addButton(x0 + (index - 1) * 54, top + 214, 52, tab.label, ALifeCleanupWindow.onTab)
        button.internal = tab.kind
        self.tabButtons[#self.tabButtons + 1] = button
    end
    self.list = ISScrollingListBox:new(x0, top + 242, 374, 262)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = 20
    self.list.font = UIFont.Small
    self.list.drawBorder = true
    self.list.backgroundColor = { r = 0.07, g = 0.075, b = 0.078, a = 0.98 }
    self:addChild(self.list)
    self.teleportButton = self:addButton(x0, top + 512, 90, "Teleport", ALifeCleanupWindow.onTeleport)
    self.mapRowButton = self:addButton(x0 + 96, top + 512, 90, "Show on map", ALifeCleanupWindow.onMapRow)
    self.overrideButton = self:addButton(x0 + 192, top + 512, 182, "Include this site's protected", ALifeCleanupWindow.onOverride)
    self:refresh()
end

function ALifeCleanupWindow:scopes()
    local list = {}
    for index, row in ipairs(Client.rows) do
        if self.ticks:isSelected(index) then list[#list + 1] = row.key end
    end
    return list
end

function ALifeCleanupWindow:risky()
    for index, row in ipairs(Client.rows) do
        if row.risky and self.ticks:isSelected(index) then return true end
    end
    for _ in pairs(Client.overrides) do return true end
    return false
end

function ALifeCleanupWindow:onTick()
    self:refresh()
end

function ALifeCleanupWindow:onScan()
    Client.lists = {}
    Client.send("cleanupScan", { scopes = {} })
end

function ALifeCleanupWindow:onRun()
    Client.send("cleanupRun", { scopes = self:scopes(), confirm = self.phrase:getText(), confirm2 = self.phrase2:getText(),
        overrides = Client.overrides })
end

function ALifeCleanupWindow:onCancel()
    Client.send("cleanupCancel", {})
end

function ALifeCleanupWindow:onFinish()
    Client.send("cleanupFinish", { confirm = self.phrase:getText() })
end

function ALifeCleanupWindow:onReopen()
    Client.send("cleanupCancel", { reopen = true })
end

function ALifeCleanupWindow:onRefresh()
    Client.send("cleanupStatus", {})
    Client.send("cleanupList", { kind = Client.listKind })
end

function ALifeCleanupWindow:onClose()
    self:setVisible(false)
    self:removeFromUIManager()
    ALifeCleanupWindow.instance = nil
end

function ALifeCleanupWindow:close()
    self:onClose()
end

function ALifeCleanupWindow:onToggleMarkers()
    Client.toggleMarkers()
end

function ALifeCleanupWindow:onTab(button)
    Client.listKind = button.internal
    Client.send("cleanupList", { kind = Client.listKind })
    self:refresh()
end

function ALifeCleanupWindow:selectedRow()
    local list = self.list
    local entry = list.items ~= nil and list.items[list.selected] or nil
    return entry ~= nil and entry.item or nil
end

function ALifeCleanupWindow:onTeleport()
    Client.teleport(self:selectedRow())
end

function ALifeCleanupWindow:onMapRow()
    Client.showOnMap(self:selectedRow())
end

function ALifeCleanupWindow:onOverride()
    local row = self:selectedRow()
    local id = type(row) == "table" and (row.site or row.id) or nil
    if id == nil then return end
    if Client.overrides[id] ~= nil then
        Client.overrides[id] = nil
    else
        Client.overrides[id] = { safehouse = true, playerBuilt = true, unverified = true }
    end
    self:refresh()
end

function ALifeCleanupWindow.rowText(kind, row)
    if type(row) ~= "table" then return tostring(row) end
    if kind == "report" then return tostring(row) end
    local place = tostring(row.x) .. ", " .. tostring(row.y) .. ", " .. tostring(row.z or 0)
    local mark = ""
    local id = row.site or row.id
    if id ~= nil and Client.overrides[id] ~= nil then mark = " [override]" end
    if kind == "pending" then
        return tostring(row.kind) .. " " .. tostring(row.id) .. "  at " .. place .. "  (" .. tostring(row.left) .. " left)" .. mark
    elseif kind == "sites" then
        return tostring(row.id) .. " " .. tostring(row.preset) .. " " .. tostring(row.state) .. "  at " .. place
            .. "  rows " .. tostring(row.rows) .. mark
    elseif kind == "companions" then
        return tostring(row.name or row.profile) .. "  group " .. tostring(row.group)
    end
    return tostring(row.what) .. "  " .. tostring(row.why) .. "  at " .. place .. (row.site ~= nil and ("  " .. tostring(row.site)) or "") .. mark
end

function ALifeCleanupWindow:refresh()
    if self.ticks == nil then return end
    local counts = Client.counts()
    local state = Client.state
    for index, row in ipairs(Client.rows) do
        local suffix = ""
        if counts[row.count] ~= nil then suffix = "  (" .. tostring(counts[row.count]) .. ")" end
        if self.ticks.options ~= nil and self.ticks.options[index] ~= nil then
            self.ticks.options[index] = row.label .. suffix
            if self.ticks.optionsIndex ~= nil then self.ticks.optionsIndex[index] = row.label .. suffix end
        end
    end
    local kind = Client.listKind
    local rows
    local data = Client.lists[kind]
    if kind == "pending" and (data == nil or data.rows == nil) and type(state) == "table" then
        rows = state.pendingRows or {}
    elseif data ~= nil then
        rows = data.rows or {}
    else
        rows = {}
    end
    self.list:clear()
    for _, row in ipairs(rows) do self.list:addItem(ALifeCleanupWindow.rowText(kind, row), row) end
    local mode = Client.mode()
    local scanning = type(state) == "table" and type(state.job) == "table" and state.job.kind == "scan" and state.job.finished ~= true
    local running = mode == "running"
    self.runButton:setEnable(not running and not scanning)
    self.cancelButton:setEnable(running or scanning)
    self.finishButton:setEnable(running)
    self.reopenButton:setEnable(mode == "done")
    self.scanButton:setEnable(not running and not scanning)
end

function ALifeCleanupWindow:prerender()
    ISCollapsableWindow.prerender(self)
    local top = self:titleBarHeight()
    self:drawTextCentre("CLEANUP A-LIFE", self.width / 2, top + 4, 0.72, 0.55, 0.32, 1, UIFont.Large)
    local hint = {
        "Safe uninstall: 1. back up the save.  2. Scan.  3. Remove with the ticked scopes.",
        "4. Walk to the Pending places until the counter is 0.  5. Scan again: all zero.  6. Disable the mod.",
        "Only things A-Life made are removed. Player builds, safehouses and other mods are skipped and listed.",
    }
    for index, line in ipairs(hint) do
        self:drawText(line, 14, top + 34 + (index - 1) * 16, 0.68, 0.69, 0.68, 1, UIFont.Small)
    end
    self:drawText("Confirmation: type REMOVE ALIFE", 14, top + 404, 0.9, 0.85, 0.7, 1, UIFont.Small)
    self:drawText("Second: I UNDERSTAND", 204, top + 404, 0.9, 0.85, 0.7, 1, UIFont.Small)
    local risky = self:risky()
    self:drawText(risky and "Risky scope or override ticked: the second phrase is required." or "Risky scopes are off.",
        14, top + 544, risky and 0.9 or 0.6, risky and 0.45 or 0.65, risky and 0.4 or 0.6, 1, UIFont.Small)
    local state = Client.state
    local mode = Client.mode()
    local label = "World: no cleanup started"
    if mode == "running" then label = "World: CLEANUP RUNNING, A-Life spawning is locked"
    elseif mode == "done" then label = "World: CLEANUP DONE, A-Life is inert in this world" end
    self:drawText(label, 392, top + 34, 0.95, 0.88, 0.6, 1, UIFont.Small)
    local y = top + 54
    local job = type(state) == "table" and state.job or nil
    local counts = type(job) == "table" and job.counts or {}
    local lines = {
        "Last job: " .. (job ~= nil and (tostring(job.kind) .. " / " .. tostring(job.stage)) or "none"),
        "Removed " .. tostring(Client.removedTotal(counts)) .. "  skipped " .. tostring(job and job.skippedTotal or 0)
            .. "  errors " .. tostring(job and job.errors or 0) .. "  pending " .. tostring(job and job.pending or 0),
        "Sites " .. tostring(counts["bases.sites"] or 0) .. " (tagged " .. tostring(counts["bases.sites_tagged"] or 0)
            .. ", old worlds " .. tostring(counts["bases.sites_legacy"] or 0) .. ")  proven " .. tostring(counts["bases.found"] or 0)
            .. "  unverified " .. tostring(counts["bases.unverified"] or 0),
        "People " .. tostring(counts["npcs.found"] or counts["npcs.removed"] or 0) .. "  live " .. tostring(counts["npcs.live"] or 0)
            .. "  companions " .. tostring(counts["npcs.companions"] or counts["npcs.companions_kept"] or 0),
    }
    for _, line in ipairs(lines) do
        self:drawText(line, 392, y, 0.85, 0.88, 0.92, 1, UIFont.Small)
        y = y + 16
    end
    local total = Client.lastScanTotal
    local fraction = 0
    if running or mode == "done" then
        if total ~= nil and total > 0 then
            fraction = math.min(1, (Client.removedTotal(counts) + (job and job.skippedTotal or 0)) / total)
        else
            fraction = mode == "done" and 1 or 0
        end
    end
    if mode == "done" then fraction = 1 end
    self:drawRectBorder(392, y + 4, 374, 14, 1, 0.4, 0.4, 0.4)
    self:drawRect(393, y + 5, 372 * fraction, 12, 0.9, 0.72, 0.55, 0.32)
    self:drawText(running and string.format("%d%%", math.floor(fraction * 100)) or "", 392 + 160, y + 4, 1, 1, 1, 1, UIFont.Small)
    if Client.message ~= nil then
        self:drawText(Client.message, 392, y + 24, 0.9, 0.45, 0.4, 1, UIFont.Small)
    end
    local refusals = type(state) == "table" and state.refusals or nil
    local refused = 0
    for _, entry in ipairs(refusals or {}) do refused = refused + (tonumber(entry.count) or 0) end
    self:drawText("Spawns refused while locked: " .. tostring(refused), 392, y + 40, 0.6, 0.65, 0.6, 1, UIFont.Small)
    local phraseOk = self.phrase ~= nil and self.phrase:getText() == "REMOVE ALIFE"
    if self.runButton ~= nil then
        self.runButton.textColor = phraseOk and { r = 1, g = 0.82, b = 0.82, a = 1 } or { r = 0.5, g = 0.5, b = 0.5, a = 1 }
    end
    local list = Client.lists[Client.listKind]
    if list ~= nil and tonumber(list.total) ~= nil then
        self:drawText(tostring(Client.listKind) .. ": " .. tostring(list.total) .. " rows", 392 + 270, top + 220, 0.6, 0.65, 0.6, 1, UIFont.Small)
    end
end

function ALifeCleanupWindow.open(playerNum)
    if ALifeCleanupWindow.instance ~= nil then ALifeCleanupWindow.instance:onClose() end
    local window = ALifeCleanupWindow:new()
    window:initialise()
    window:addToUIManager()
    ALifeCleanupWindow.instance = window
    Client.send("cleanupStatus", {})
    Client.send("cleanupList", { kind = Client.listKind })
    return window
end

local Window = { open = ALifeCleanupWindow.open }
Window.tab = { id = "cleanup", title = "Cleanup", open = ALifeCleanupWindow.open }
ProjectALife.CleanupWindow = Window

function Window.register()
    if Window.registered == true then return true end
    Window.registered = true
    return true
end

Window.register()

if type(Events) == "table" then
    if Events.OnServerCommand ~= nil and type(Events.OnServerCommand.Add) == "function" then
        Events.OnServerCommand.Add(Client.receive)
    end
    if Events.OnGameStart ~= nil and type(Events.OnGameStart.Add) == "function" then
        Events.OnGameStart.Add(Window.register)
    end
end

return Window
