require "ProjectALife/Core/ALifeText"
require "ProjectALife/Records/ALifeRepLevels"
require "ProjectALife/Records/ALifeRepIcons"

ProjectALife = ProjectALife or {}
local Screen = { wrapped = false }
ProjectALife.RepScreen = Screen

function Screen.personal()
    local store = ProjectALife.StatusStore
    local reputation = store ~= nil and store.reputation or nil
    local personal = type(reputation) == "table" and reputation.personal or nil
    if type(personal) ~= "table" or type(personal.level) ~= "string" then return nil, reputation end
    return personal, reputation
end

function Screen.levelName()
    local personal = Screen.personal()
    if personal == nil then return nil end
    return ProjectALife.RepIcons.label(personal.level, personal.score)
end

function Screen.popup(payload, player)
    local notify = ProjectALife.RepNotify
    if type(payload) ~= "table" or notify == nil or type(notify.receive) ~= "function" then return false end
    return notify.receive(payload, player)
end

function Screen.onServerCommand(module, command, arguments)
    if module ~= "ProjectALife" or command ~= "repPopup" or type(arguments) ~= "table" then return end
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil
    Screen.popup(arguments, player)
end

function Screen.blurb()
    local personal = Screen.personal()
    local levels = ProjectALife.RepLevels
    if personal == nil or levels == nil or type(levels.blurb) ~= "function" then return nil end
    local text = levels.blurb(personal.level)
    return text ~= nil and ProjectALife.Text.ui(text) or nil
end

function Screen.lines(text, width, font, manager)
    local lines, line = {}, ""
    for word in string.gmatch(text, "%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if line ~= "" and manager:MeasureStringX(font, try) > width then
            lines[#lines + 1] = line
            line = word
        else
            line = try
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

Screen.requestGapMs = 4000
Screen.requestLastMs = -1000000
Screen.border = 10
Screen.iconSize = 16

function Screen.rowInfo(panel)
    local text = ProjectALife.Text
    local name = Screen.levelName()
    if name ~= nil then
        local personal = Screen.personal()
        return name, nil, Screen.blurb(), personal.level
    end
    local store = ProjectALife.StatusStore
    local synced = store ~= nil and type(store.reputation) == "table"
    local levels = ProjectALife.RepLevels
    local neutral = levels ~= nil and type(levels.neutralId) == "function" and levels.neutralId() or nil
    local base = neutral ~= nil and type(levels.name) == "function" and levels.name(neutral) or nil
    local blurb = neutral ~= nil and type(levels.blurb) == "function" and levels.blurb(neutral) or nil
    if base == nil then base = text.ui("Neutral") end
    local tip = blurb ~= nil and text.ui(blurb) or ""
    if synced then
        local off = text.ui("Reputation tracking is off. Turn on Track personal reputation in the sandbox options.")
        return base, text.ui("tracking off"), tip == "" and off or (tip .. " " .. off), nil
    end
    if store ~= nil and type(store.request) == "function" and type(getTimestampMs) == "function" then
        local now = getTimestampMs()
        if now - Screen.requestLastMs >= Screen.requestGapMs then
            Screen.requestLastMs = now
            local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(tonumber(panel.playerNum) or 0) or nil
            if player ~= nil then pcall(store.request, player) end
        end
    end
    return base, text.ui("waiting for the server"), tip ~= "" and tip or nil, nil
end

function Screen.hover(panel, x, y, w, h, font, manager, text)
    if type(panel.getMouseX) ~= "function" or type(panel.getMouseY) ~= "function" then return end
    local mx, my = panel:getMouseX(), panel:getMouseY()
    if mx < x or mx > x + w or my < y or my > y + h then return end
    if text == nil then return end
    local lines = Screen.lines(text, 280, font, manager)
    local step = manager:getFontHeight(font) + 2
    local height = #lines * step + 12
    local top = math.max(2, y - height - 4)
    panel:drawRect(x, top, 296, height, 0.92, 0.05, 0.06, 0.05)
    panel:drawRectBorder(x, top, 296, height, 1, 0.35, 0.4, 0.35)
    for index, line in ipairs(lines) do
        panel:drawText(line, x + 8, top + 6 + (index - 1) * step, 0.9, 0.92, 0.85, 1, font)
    end
end

function Screen.column(panel, font, manager)
    local widest = 0
    for _, key in ipairs({ "IGUI_char_Favourite_Weapon", "IGUI_char_Zombies_Killed", "IGUI_char_Survived_For" }) do
        if type(getText) == "function" then widest = math.max(widest, manager:MeasureStringX(font, getText(key))) end
    end
    if widest <= 0 then return math.floor(panel:getWidth() / 2) end
    return 20 + widest
end

function Screen.humans(panel)
    local _, reputation = Screen.personal()
    local count = type(reputation) == "table" and tonumber(reputation.humans) or nil
    if count ~= nil then return count end
    local player = panel.char
    if player == nil and type(getSpecificPlayer) == "function" then player = getSpecificPlayer(tonumber(panel.playerNum) or 0) end
    if player == nil or type(player.hasModData) ~= "function" or player:hasModData() ~= true then return 0 end
    local data = player:getModData()
    if type(data) ~= "table" then return 0 end
    return math.max(0, math.floor(tonumber(data.palHumansKilled) or 0))
end

function Screen.drawHumans(panel, x, y, font)
    local label = ProjectALife.Text.ui("Humans Killed:")
    if type(panel.drawTextRight) == "function" then panel:drawTextRight(label, x, y, 1, 1, 1, 1, font) end
    panel:drawText(tostring(Screen.humans(panel)), x + Screen.border, y, 1, 1, 1, 0.5, font)
end

function Screen.drawReputation(panel, x, y, font, manager, row)
    local name, suffix, tip, levelId = Screen.rowInfo(panel)
    if name == nil then return end
    local label = ProjectALife.Text.ui("Reputation:")
    if type(panel.drawTextRight) == "function" then panel:drawTextRight(label, x, y, 1, 1, 1, 1, font) end
    local textX = x + Screen.border
    local icons = ProjectALife.RepIcons
    local texture = levelId ~= nil and icons ~= nil and icons.texture(levelId) or nil
    if texture ~= nil and type(panel.drawTextureScaled) == "function" then
        panel:drawTextureScaled(texture, textX, y - 1, Screen.iconSize, Screen.iconSize, 1, 1, 1, 1)
        textX = textX + Screen.iconSize + 4
    end
    panel:drawText(name, textX, y, 1, 1, 1, 0.5, font)
    local valueWidth = manager:MeasureStringX(font, name)
    if suffix ~= nil then
        panel:drawText(" (" .. suffix .. ")", textX + valueWidth, y, 0.6, 0.6, 0.6, 0.9, font)
        valueWidth = manager:MeasureStringX(font, name .. " (" .. suffix .. ")")
    end
    local labelWidth = manager:MeasureStringX(font, label)
    Screen.hover(panel, x - labelWidth, y, labelWidth + (textX - x) + valueWidth, row - 4, font, manager, tip)
end

function Screen.intercept(panel, plan)
    local right, text = panel.drawTextRight, panel.drawText
    if plan.label == nil or type(right) ~= "function" or type(text) ~= "function" then return false end
    panel.drawTextRight = function(self, str, x, y, ...)
        if plan.slot == nil and str == plan.label then
            Screen.drawHumans(self, x, y, plan.font)
            plan.slot = y
            return right(self, str, x, y + plan.rowH, ...)
        end
        return right(self, str, x, y, ...)
    end
    panel.drawText = function(self, str, x, y, ...)
        if plan.slot ~= nil and plan.valueDone ~= true and y == plan.slot then
            plan.valueDone = true
            return text(self, str, x, y + plan.rowH, ...)
        end
        return text(self, str, x, y, ...)
    end
    return true
end

function Screen.release(panel)
    panel.drawTextRight = nil
    panel.drawText = nil
end

function Screen.draw(panel, plan)
    if type(panel.drawText) ~= "function" or type(panel.getHeight) ~= "function" then return end
    local manager = type(getTextManager) == "function" and getTextManager() or nil
    local font = UIFont and UIFont.Small or nil
    if manager == nil or font == nil then return end
    local row = plan ~= nil and plan.rowH or manager:getFontHeight(font) + 6
    local base = panel:getHeight()
    local x = Screen.column(panel, font, manager)
    local shifted = plan ~= nil and plan.slot ~= nil
    local y = base - Screen.border
    if shifted then
        y = y + row
    else
        Screen.drawHumans(panel, x, base - row - Screen.border, font)
    end
    Screen.drawReputation(panel, x, y, font, manager, row)
    if type(panel.setHeightAndParentHeight) == "function" then
        if shifted then
            panel:setHeightAndParentHeight(base + row * 2)
        else
            panel:setHeightAndParentHeight(base + row)
        end
    end
end

function Screen.render(panel, original, ...)
    local manager = type(getTextManager) == "function" and getTextManager() or nil
    local font = UIFont and UIFont.Small or nil
    if manager == nil or font == nil then return original(panel, ...) end
    local label = nil
    if type(getText) == "function" then label = getText("IGUI_char_Survived_For") end
    local plan = { rowH = manager:getFontHeight(font) + 6, font = font, label = label }
    Screen.intercept(panel, plan)
    local ok, failure = pcall(original, panel, ...)
    Screen.release(panel)
    if not ok then error(failure, 0) end
    pcall(Screen.draw, panel, plan)
end

function Screen.wrap()
    if Screen.wrapped or ISCharacterScreen == nil or type(ISCharacterScreen.render) ~= "function" then return false end
    local original = ISCharacterScreen.render
    ISCharacterScreen.render = function(self, ...)
        Screen.render(self, original, ...)
    end
    Screen.wrapped = true
    return true
end

if type(Events) == "table" and Events.OnGameStart ~= nil and type(Events.OnGameStart.Add) == "function" then
    Events.OnGameStart.Add(Screen.wrap)
end
if type(Events) == "table" and Events.OnServerCommand ~= nil and type(Events.OnServerCommand.Add) == "function" then
    Events.OnServerCommand.Add(Screen.onServerCommand)
end

return Screen
