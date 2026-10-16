ProjectALife = ProjectALife or {}
if ProjectALife.SplashScreen ~= nil then return ProjectALife.SplashScreen end

local Splash = { imagePath = "media/ui/ProjectALifeSplash.png", soundId = nil, durationMs = 3500 }
ProjectALife.SplashScreen = Splash

function Splash.now()
    if type(getTimestampMs) ~= "function" then return nil end
    local ok, value = pcall(getTimestampMs)
    return ok and tonumber(value) or nil
end

function Splash.close()
    local panel = Splash.panel
    Splash.panel = nil
    if panel ~= nil and type(panel.removeFromUIManager) == "function" then
        pcall(panel.removeFromUIManager, panel)
    end
end

function Splash.show()
    if Splash.attempted then return false, "attempted" end
    if type(getTexture) ~= "function" or type(getCore) ~= "function"
            or type(ISPanel) ~= "table" or type(ISPanel.new) ~= "function" then return false, "ui_unavailable" end
    Splash.attempted = true
    local ok, texture = pcall(getTexture, Splash.imagePath)
    if not ok or texture == nil then return false, "asset_missing" end
    local now = Splash.now()
    if now == nil then return false, "clock_unavailable" end
    local created, reason = pcall(function()
        local core = getCore()
        if core == nil or type(core.getScreenWidth) ~= "function" or type(core.getScreenHeight) ~= "function"
                or type(texture.getWidth) ~= "function" or type(texture.getHeight) ~= "function" then return "dimensions" end
        local width, height = tonumber(core:getScreenWidth()), tonumber(core:getScreenHeight())
        local imageWidth, imageHeight = tonumber(texture:getWidth()), tonumber(texture:getHeight())
        if width == nil or height == nil or imageWidth == nil or imageHeight == nil
                or width <= 0 or height <= 0 or imageWidth <= 0 or imageHeight <= 0 then return "dimensions" end
        local panel = ISPanel:new(0, 0, width, height)
        Splash.panel = panel
        panel.background = false
        panel.prerender = function(self)
            self:drawRect(0, 0, width, height, 1, 0, 0, 0)
            local scale = math.min(width / imageWidth, height / imageHeight)
            local w, h = imageWidth * scale, imageHeight * scale
            self:drawTextureScaled(texture, (width - w) / 2, (height - h) / 2, w, h, 1, 1, 1, 1)
        end
        panel.update = function()
            local current = Splash.now()
            if current == nil or current - now >= Splash.durationMs then Splash.close() end
        end
        panel.onMouseDown = function() Splash.close(); return true end
        panel.onRightMouseDown = panel.onMouseDown
        if type(panel.initialise) ~= "function" or type(panel.addToUIManager) ~= "function" then return "ui_unavailable" end
        panel:initialise()
        panel:addToUIManager()
        if type(panel.setAlwaysOnTop) == "function" then panel:setAlwaysOnTop(true) end
        return nil
    end)
    if not created or reason ~= nil then Splash.close(); return false, reason or "ui_error" end
    if type(Splash.soundId) == "string" and Splash.soundId ~= "" and type(getSoundManager) == "function" then
        pcall(function()
            local sound = getSoundManager()
            if sound ~= nil and type(sound.playUISound) == "function" then sound:playUISound(Splash.soundId) end
        end)
    end
    return true
end

if type(Events) == "table" and Events.OnMainMenuEnter ~= nil and type(Events.OnMainMenuEnter.Add) == "function" then
    Events.OnMainMenuEnter.Add(Splash.show)
end
if type(Events) == "table" and Events.OnGameStart ~= nil and type(Events.OnGameStart.Add) == "function" then
    Events.OnGameStart.Add(Splash.close)
end

return Splash
