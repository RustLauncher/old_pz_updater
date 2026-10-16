ProjectALife = ProjectALife or {}

require "ProjectALife/Core/ALifeText"
require "ProjectALife/Records/ALifeCustomProfiles"
require "ProjectALife/Interface/Creator/ALifeCreatorCore"

local Creator = ProjectALife.CreatorScreen

local Loader = {
    state = nil,
    panel = nil,
    stepGapMs = 6,
    lastStepEnd = nil,
    lastSource = nil,
    seenClock = nil,
    clockAdvances = false,
    frames = 0,
    panelWidth = 380,
    panelHeight = 78,
}
ProjectALife.CreatorLoader = Loader
Creator.loader = Loader
Loader.priorOpen = Creator.open

function Loader.clock()
    if type(getTimestampMs) ~= "function" then return 0 end
    return tonumber(getTimestampMs()) or 0
end

function Loader.enabled()
    if type(isClient) == "function" and isClient() then return false end
    return type(ProjectALife.CustomProfiles) == "table" and type(ProjectALife.CustomProfiles.loadBegin) == "function"
end

function Loader.busy()
    return Loader.state ~= nil
end

function Loader.progress()
    local state = Loader.state
    if state == nil then return 0, 0 end
    return ProjectALife.CustomProfiles.loadProgress(state)
end

function Loader.text()
    local done, total = Loader.progress()
    if total > 0 then
        return ProjectALife.Text.ui("Loading profiles {n} of {m}", { n = done, m = total })
    end
    return ProjectALife.Text.ui("Loading profiles")
end

function Loader.drawPanel(panel)
    local done, total = Loader.progress()
    local width = panel.width
    panel:drawTextCentre(Loader.text(), width / 2, 14, 0.92, 0.92, 0.92, 1, UIFont.Medium)
    local barX, barY, barW, barH = 20, panel.height - 26, width - 40, 8
    panel:drawRect(barX, barY, barW, barH, 0.9, 0.12, 0.12, 0.13)
    if total > 0 then
        panel:drawRect(barX, barY, math.max(1, math.floor(barW * done / total)), barH, 0.95, 0.62, 0.16, 0.24)
    end
end

function Loader.showPanel()
    if ISPanel == nil or type(getCore) ~= "function" then return nil end
    local ok, panel = pcall(function()
        local core = getCore()
        local width, height = Loader.panelWidth, Loader.panelHeight
        local shown = ISPanel:new(math.floor(core:getScreenWidth() / 2 - width / 2),
            math.floor(core:getScreenHeight() / 2 - height / 2), width, height)
        shown:initialise()
        shown.backgroundColor = { r = 0.015, g = 0.017, b = 0.018, a = 0.94 }
        shown.borderColor = { r = 0.36, g = 0.36, b = 0.37, a = 1 }
        shown.render = function(self) Loader.drawPanel(self) end
        shown:addToUIManager()
        shown:setAlwaysOnTop(true)
        shown:bringToTop()
        return shown
    end)
    if not ok then return nil end
    return panel
end

function Loader.hidePanel()
    local panel = Loader.panel
    Loader.panel = nil
    if panel ~= nil and type(panel.removeFromUIManager) == "function" then pcall(panel.removeFromUIManager, panel) end
end

function Loader.fresh(source)
    local now = Loader.clock()
    if Loader.seenClock ~= nil and now ~= Loader.seenClock then Loader.clockAdvances = true end
    Loader.seenClock = now
    local last = Loader.lastStepEnd
    if Loader.clockAdvances and last ~= nil and source ~= Loader.lastSource and now >= last
            and now - last < Loader.stepGapMs then return false end
    Loader.lastSource = source
    return true
end

function Loader.finish()
    local shown = Loader.panel ~= nil
    Loader.state = nil
    Loader.hidePanel()
    local Custom = ProjectALife.CustomProfiles
    Custom.primed = true
    local ok, result = pcall(Loader.priorOpen)
    Custom.primed = nil
    if not ok then print("[ProjectALife] Creator open failed: " .. tostring(result)) end
    if shown and ok and result ~= false and type(Creator.notifyCue) == "function" then Creator.notifyCue("loaded") end
    return ok and result or false
end

function Loader.step(source)
    local state = Loader.state
    if state == nil or not Loader.fresh(source) then return false end
    Loader.frames = Loader.frames + 1
    local Custom = ProjectALife.CustomProfiles
    local ran, done = pcall(Custom.loadStep, state, Custom.loadMs)
    Loader.lastStepEnd = Loader.clock()
    if ran and not done then return false end
    if not ran then print("[ProjectALife] Creator profile load failed: " .. tostring(done)) end
    Loader.finish()
    return true
end

function Loader.open()
    if Loader.state ~= nil then return false end
    if not Loader.enabled() or type(Creator.adminAllowed) ~= "function" or not Creator.adminAllowed(0) then
        return Loader.priorOpen()
    end
    if Creator.window ~= nil and not Creator.close() then return false end
    local queue = ProjectALife.CreatorSaveQueue
    if queue ~= nil and type(queue.busy) == "function" and queue.busy() then return Loader.priorOpen() end
    local Custom = ProjectALife.CustomProfiles
    local ok, state = pcall(Custom.loadBegin)
    if not ok or type(state) ~= "table" or state.phase == "done" then return Loader.priorOpen() end
    Loader.state, Loader.frames = state, 0
    Loader.lastStepEnd, Loader.lastSource = nil, nil
    local startedAt = Loader.clock()
    local ran, done
    repeat
        ran, done = pcall(Custom.loadStep, state, Custom.loadMs)
    until not ran or done or Loader.clock() - startedAt >= Custom.loadMs
    if not ran then print("[ProjectALife] Creator profile load failed: " .. tostring(done)) end
    if not ran or done then return Loader.finish() end
    Loader.panel = Loader.showPanel()
    return true
end

Creator.open = Loader.open

if type(Events) == "table" and Events.OnPreUIDraw and type(Events.OnPreUIDraw.Add) == "function" then
    Events.OnPreUIDraw.Add(function() Loader.step("ui") end)
end
if type(Events) == "table" and Events.OnTick and type(Events.OnTick.Add) == "function" then
    Events.OnTick.Add(function() Loader.step("tick") end)
end

return Loader
