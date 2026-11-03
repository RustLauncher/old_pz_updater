require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ProjectALife/Interface/ALifeStatusStore"
require "ProjectALife/Interface/ALifeSafehouseClient"
require "ProjectALife/Interface/ALifeDiscordLink"

ProjectALife = ProjectALife or {}

local StatusStore = ProjectALife.StatusStore
ALifeStatusWindow = ISCollapsableWindow:derive("ALifeStatusWindow")
ALifeStatusWindow.instance = nil

function ALifeStatusWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.refresh = ISButton:new(
        12, self.height - 34, 100, 24, "Refresh", self, ALifeStatusWindow.onRefresh)
    self.refresh:initialise()
    self.refresh:instantiate()
    self.refresh.anchorTop = false
    self.refresh.anchorBottom = true
    self:addChild(self.refresh)
    self.discord = ISButton:new(120, self.height - 34, 220, 24,
        ProjectALife.Text.ui("Join the A-Life Discord"), self, ProjectALife.DiscordLink.onButton)
    self.discord:initialise()
    self.discord:instantiate()
    self.discord.anchorTop = false
    self.discord.anchorBottom = true
    self:addChild(self.discord)
end

function ALifeStatusWindow:onRefresh()
    StatusStore.request(getSpecificPlayer(self.playerNum))
end

function ALifeStatusWindow:prerender()
    ISCollapsableWindow.prerender(self)
    local status = self.status
    local lines
    if status == nil then
        lines = { "Waiting for server status..." }
    else
        local runtimeState = "running"
        if status.runtimeEnabled == false then
            runtimeState = "disabled"
        elseif status.runtimeStarted ~= true then
            runtimeState = "starting"
        elseif (tonumber(status.tickCount) or 0) == 0 then
            runtimeState = "waiting for first tick"
        end
        lines = {
            "Actors: " .. tostring(status.total or 0),
            "Active / spawning: " .. tostring(status.active or 0)
                .. " / " .. tostring(status.spawning or 0),
            "Dormant / dead: " .. tostring(status.dormant or 0)
                .. " / " .. tostring(status.dead or 0),
            "Physical shells: " .. tostring(status.shells or 0),
            "Running actions: " .. tostring(status.runningActions or 0),
            "Pending spawns: " .. tostring(status.pendingSpawns or 0),
            "Watchdog recoveries: " .. tostring(status.recoveries or 0),

            "Offline squads on the map: " .. tostring(status.offlineSquads or 0),
            "Offline founded / refused: " .. tostring(status.offlineFounded or 0)
                .. " / " .. tostring(status.offlineRefused or 0)
                .. (status.offlineRefusedWhy ~= nil
                    and (" (" .. tostring(status.offlineRefusedWhy) .. ")") or ""),
            "Encounter rolls / spawned: " .. tostring(status.encounterRolls or 0)
                .. " / " .. tostring(status.encounterPlaced or 0),
            "Runtime: " .. runtimeState,
            "Pacing: " .. tostring(status.worldPressureCommitted or 0)
                .. " new crews, " .. tostring(status.worldPressureRefused or 0) .. " refusals",
            "Last pacing refusal: " .. tostring(status.worldPressureReason or "none")
                .. " (last delay " .. tostring(status.worldPressureRetryHours or 0) .. "h)",
            "World census: " .. tostring(status.censusAlive or 0) .. " in the world, "
                .. tostring(status.censusLiving or 0) .. " living of " .. tostring(status.censusTotal or 0)
                .. ", killed " .. tostring(status.censusKilled or 0)
                .. ", arrivals " .. tostring(status.censusArrivals or 0),
            "Census by faction (alive/killed/arrived): " .. tostring(status.censusFactions or "none"),
            "Health: " .. ((status.healthOk == true) and "OK" or
                (tostring(status.healthErrors or 0) .. " error(s)")),
            "Runtime faults / overruns: " .. tostring(status.runtimeFaults or 0)
                .. " / " .. tostring(status.tickOverruns or 0),
            "Protected areas: " .. tostring(status.noSpawnZones or 0),
            "Tick ms (last / max): " .. tostring(status.lastTickMs or 0)
                .. " / " .. tostring(status.maximumTickMs or 0),
            "Tick count / budget: " .. tostring(status.tickCount or 0)
                .. " / " .. tostring(status.tickBudget or 0),
        }
    end
    local knock = ProjectALife.SafehouseClient.statusText(self.playerNum)
    local step = math.max(14, math.min(20, math.floor((self.height - self:titleBarHeight() - 80) / (#lines + 8))))
    local room = math.floor((self.height - 40 - self:titleBarHeight() - 14 - 26 - 6 * step) / step)
    while #lines > room - (knock ~= nil and 1 or 0) and #lines > 1 do table.remove(lines) end
    if knock ~= nil then lines[#lines + 1] = knock end
    local y = self:titleBarHeight() + 14
    for _, line in ipairs(lines) do
        self:drawText(line, 14, y, 0.9, 0.95, 1, 1, UIFont.Small)
        y = y + step
    end
    y = y + 6
    self:drawText("Reputation (last known)", 14, y,
        0.95, 0.65, 0.75, 1, UIFont.Small)
    y = y + step
    local screen = ProjectALife.RepScreen
    local levelText = screen ~= nil and type(screen.levelName) == "function" and screen.levelName() or nil
    if levelText ~= nil then
        local personal = screen.personal()
        local icons = ProjectALife.RepIcons
        local texture = icons ~= nil and personal ~= nil and icons.texture(personal.level) or nil
        local x = 14
        if texture ~= nil then
            self:drawTextureScaled(texture, 14, y - 2, 16, 16, 1, 1, 1, 1)
            x = 36
        end
        self:drawText(levelText, x, y, 0.95, 0.88, 0.6, 1, UIFont.Small)
        y = y + step
    end
    local reputation = StatusStore.reputation
    local relations = reputation and reputation.relations or nil
    if type(relations) ~= "table" or #relations == 0 then
        self:drawText("No faction overrides", 14, y,
            0.65, 0.7, 0.75, 1, UIFont.Small)
    else
        for index = 1, math.min(6, #relations) do
            local entry = relations[index]
            local cause = entry.cause and " (" .. tostring(entry.cause) .. ")" or ""
            self:drawText(tostring(entry.factionName or entry.factionId) .. ": "
                .. tostring(entry.status or "neutral") .. cause,
                14, y, 0.85, 0.9, 0.95, 1, UIFont.Small)
            y = y + step
        end
    end
end

function ALifeStatusWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
    ALifeStatusWindow.instance = nil
end

function ALifeStatusWindow:new(playerNum)
    local width, height = 590, math.min(660, getCore():getScreenHeight() - 40)
    local x = math.max(20, (getCore():getScreenWidth() - width) / 2)
    local y = math.max(20, (getCore():getScreenHeight() - height) / 2)
    local window = ISCollapsableWindow.new(self, x, y, width, height)
    window.playerNum = playerNum
    window.status = StatusStore.value
    window.resizable = false
    window:setTitle("Project A-Life Status")
    return window
end

function ALifeStatusWindow.toggle(playerNum)
    if ALifeStatusWindow.instance ~= nil then
        ALifeStatusWindow.instance:close()
        return
    end
    local window = ALifeStatusWindow:new(playerNum)
    window:initialise()
    window:addToUIManager()
    ALifeStatusWindow.instance = window
    StatusStore.request(getSpecificPlayer(playerNum))
end

StatusStore.subscribe(function(status)
    if ALifeStatusWindow.instance ~= nil then
        ALifeStatusWindow.instance.status = status
    end
end)

return ALifeStatusWindow
