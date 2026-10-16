require "ProjectALife/Core/ALifeText"

ProjectALife = ProjectALife or {}

local Link = ProjectALife.DiscordLink or {}
ProjectALife.DiscordLink = Link

Link.url = "https://discord.gg/alife"
Link.shortUrl = "discord.gg/alife"
Link.method = nil
Link.box = nil

function Link.overlayOn()
    if type(isSteamOverlayEnabled) ~= "function" or type(activateSteamOverlayToWebPage) ~= "function" then
        return false
    end
    local ok, enabled = pcall(isSteamOverlayEnabled)
    return ok and enabled == true
end

function Link.open()
    local url = Link.url
    local opened = false
    if Link.overlayOn() and pcall(activateSteamOverlayToWebPage, url) then
        Link.method = "overlay"
        opened = true
    elseif type(openUrl) == "function" and pcall(openUrl, url) then
        Link.method = "browser"
        opened = true
    end
    if not opened then Link.method = "copybox" end
    print("[ALIFE-UI] discord method=" .. tostring(Link.method))
    Link.showCopyBox()
    return opened
end

function Link.copy()
    if type(Clipboard) ~= "table" or type(Clipboard.setClipboard) ~= "function" then return false end
    return pcall(Clipboard.setClipboard, Link.url)
end

function Link.onButton()
    Link.open()
end

function Link.closeBox()
    local box = Link.box
    Link.box = nil
    if box == nil then return end
    pcall(function() box:setVisible(false) end)
    pcall(function() box:removeFromUIManager() end)
end

function Link.showCopyBox()
    Link.closeBox()
    if type(ISPanel) ~= "table" or type(ISButton) ~= "table" or type(ISTextEntryBox) ~= "table"
            or type(getCore) ~= "function" or type(getTextManager) ~= "function" then
        return false
    end
    local Text = ProjectALife.Text
    local core = getCore()
    local fontH = getTextManager():getFontHeight(UIFont.Small)
    local pad = math.max(10, fontH)
    local rowH = fontH + 10
    local width = math.min(core:getScreenWidth() - 40, math.max(360, fontH * 28))
    local height = pad * 2 + fontH * 2 + rowH * 2 + pad * 3
    local box = ISPanel:new(math.floor((core:getScreenWidth() - width) / 2),
        math.floor((core:getScreenHeight() - height) / 2), width, height)
    box:initialise()
    box.backgroundColor = { r = 0.02, g = 0.025, b = 0.03, a = 0.98 }
    box.borderColor = { r = 0.34, g = 0.52, b = 0.57, a = 1 }
    box.moveWithMouse = true
    local title = Text.ui("Join the A-Life Discord")
    local hint = Text.ui("If nothing opened, select the link and copy it with Ctrl+C.")
    box.prerender = function(self)
        ISPanel.prerender(self)
        self:drawText(title, pad, pad, 0.92, 0.91, 0.88, 1, UIFont.Medium)
        self:drawText(hint, pad, pad + fontH + 8, 0.68, 0.69, 0.68, 1, UIFont.Small)
    end
    local entryY = pad * 2 + fontH * 2 + 8
    local entry = ISTextEntryBox:new(Link.url, pad, entryY, width - pad * 2, rowH)
    entry:initialise()
    entry:instantiate()
    box:addChild(entry)
    if type(entry.setEditable) == "function" then entry:setEditable(false) end
    local buttonW = math.max(90, fontH * 6)
    local buttonY = entryY + rowH + pad
    local copy = ISButton:new(width - pad - buttonW * 2 - 8, buttonY, buttonW, rowH,
        Text.ui("COPY LINK"), box, function() Link.copy() end)
    copy:initialise()
    copy:instantiate()
    box:addChild(copy)
    local close = ISButton:new(width - pad - buttonW, buttonY, buttonW, rowH,
        Text.ui("CLOSE"), box, function() Link.closeBox() end)
    close:initialise()
    close:instantiate()
    box:addChild(close)
    box:addToUIManager()
    box:setAlwaysOnTop(true)
    box:bringToTop()
    Link.box = box
    return true
end

return Link
