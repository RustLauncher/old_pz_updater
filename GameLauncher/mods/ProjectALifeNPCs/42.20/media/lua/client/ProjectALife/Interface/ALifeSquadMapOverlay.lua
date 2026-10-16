ProjectALife = ProjectALife or {}

require "ISUI/ISPanel"
require "ProjectALife/Core/ALifeText"
require "ProjectALife/Interface/ALifeMenuPrefs"

local Overlay = ISPanel:derive("ALifeSquadMapOverlay")
ProjectALife.SquadMapOverlay = Overlay
Overlay.instance = nil

Overlay.hoverRadius = 14
Overlay.hitPad = 4

Overlay.groupOrder = { "civilian", "military", "law", "medical", "crime", "elite", "unknown" }
Overlay.stateOrder = { "live", "offline", "place", "outpost" }
Overlay.blocGroups = {
    civilian = "civilian", family = "civilian", worker = "civilian", federation = "civilian",
    military = "military",
    law = "law",
    rescue = "medical", medical = "medical",
    crime = "crime", club = "crime", gang = "crime", raider = "crime", prison = "crime",
    elite = "elite",
}
Overlay.palette = {
    civilian = { 0.35, 0.72, 0.95 },
    military = { 0.28, 0.68, 0.25 },
    law = { 0.18, 0.32, 0.92 },
    medical = { 0.96, 0.52, 0.78 },
    crime = { 0.90, 0.20, 0.16 },
    elite = { 1.00, 0.84, 0.16 },
    unknown = { 0.62, 0.62, 0.62 },
}
Overlay.ringLive = { 1.00, 1.00, 1.00 }
Overlay.ringOffline = { 0.04, 0.04, 0.04 }
Overlay.shapes = {}
Overlay.factionBlocs = {}

function Overlay.attach(worldMap, provider, caption)
    if worldMap == nil then return nil end
    local existing = Overlay.instance
    if existing ~= nil and existing.parent == worldMap then
        existing.provider = provider
        existing.caption = caption
        existing:setVisible(true)
        return existing
    end
    local panel = Overlay:new(0, 0, worldMap.width, worldMap.height)
    panel.provider = provider
    panel.caption = caption
    panel.worldMap = worldMap
    panel:initialise()
    panel:setAnchorRight(true)
    panel:setAnchorBottom(true)
    panel.background = false
    worldMap:addChild(panel)

    pcall(function()
        if panel.javaObject ~= nil then panel.javaObject:setConsumeMouseEvents(false) end
    end)
    Overlay.instance = panel
    return panel
end

function Overlay.detach()
    local panel = Overlay.instance
    if panel == nil then return end
    pcall(function()
        if panel.parent ~= nil then panel.parent:removeChild(panel) end
    end)
    Overlay.instance = nil
end

function Overlay:onMouseDown() return false end
function Overlay:onMouseUp() return false end

function Overlay.menuOn()
    local prefs = ProjectALife.MenuPrefs
    return prefs ~= nil and type(prefs.rightClickOn) == "function" and prefs.rightClickOn() == true
end

function Overlay:onRightMouseDown() return Overlay.menuOn() and self.hovered ~= nil end

function Overlay.menuEntries(row)
    if type(row) ~= "table" then return {} end
    local entries = {}
    if row.outpost == true then
        entries[#entries + 1] = { label = "Send a squad out now", action = "spawnNow" }
        entries[#entries + 1] = { label = "Delay next squad by 1 hour", action = "delay", value = 1 }
        entries[#entries + 1] = { label = "Delay next squad by 24 hours", action = "delay", value = 24 }
        entries[#entries + 1] = { label = "Delay next squad by 7 days", action = "delay", value = 24 * 7 }
        entries[#entries + 1] = { label = "Delay next squad by 30 days", action = "delay", value = 24 * 30 }
        entries[#entries + 1] = { label = "Max squads +1", action = "cap", value = 1 }
        entries[#entries + 1] = { label = "Max squads -1", action = "cap", value = -1 }
    elseif row.groupId ~= nil then
        local members = tonumber(row.members) or 0
        entries[#entries + 1] = { label = "Delete this squad (" .. tostring(members)
            .. (members == 1 and " person)" or " people)"), action = "delete" }
    end
    return entries
end

function Overlay:onRightMouseUp(x, y)
    if not Overlay.menuOn() then return false end
    local row = self.hovered
    local entries = Overlay.menuEntries(row)
    if #entries == 0 then return false end
    local squadMap = ProjectALife.SquadMap
    if squadMap == nil or type(squadMap.act) ~= "function"
            or type(ISContextMenu) ~= "table" or type(ISContextMenu.get) ~= "function" then
        return false
    end

    if type(getPlayerContextMenu) ~= "function" then return false end
    local playerMenu = getPlayerContextMenu(squadMap.playerNum or 0)
    if type(playerMenu) ~= "table" or type(playerMenu.hideAndChildren) ~= "function" then
        return false
    end
    local opened = pcall(function()
        local menu = ISContextMenu.get(squadMap.playerNum or 0,
            self:getAbsoluteX() + x, self:getAbsoluteY() + y)
        for _, entry in ipairs(entries) do
            menu:addOption(entry.label, row, function(target, action, value)
                squadMap.act(action, target, value)
            end, entry.action, entry.value)
        end
    end)
    return opened == true
end
function Overlay:onMouseWheel() return false end

function Overlay.formatHours(hours)
    hours = math.max(0, tonumber(hours) or 0)
    local minutes = math.floor(hours * 60 + 0.5)
    if minutes < 1 then return "under a minute" end
    local h, m = math.floor(minutes / 60), minutes % 60
    if h == 0 then return "~" .. tostring(m) .. " min" end
    if m == 0 then return "~" .. tostring(h) .. " h" end
    return "~" .. tostring(h) .. " h " .. tostring(m) .. " min"
end

function Overlay.bodyWaitReason(reason)
    if reason == "owner_window" then return "waiting for a nearby owning client" end
    if reason == "unloaded" then return "waiting for the area to load" end
    if reason == "no_square" then return "waiting for a free spawn square" end
    return tostring(reason or "pending")
end

function Overlay.tooltipLines(squad)
    if type(squad) ~= "table" then return {} end
    local members = tonumber(squad.members) or 0
    local kind = "squad"
    if squad.outpost == true then kind = "outpost"
    elseif squad.offline == true then kind = "offline squad" end
    local lines = { tostring(squad.label or "squad") .. "  -  " .. kind .. ", "
        .. tostring(members) .. (members == 1 and " person" or " people") }
    if squad.place == true then lines[1] = tostring(squad.label or "place") .. "  -  planned place" end
    if (tonumber(squad.dormant) or 0) > 0 then
        local why = Overlay.bodyWaitReason(squad.holdReason)
        lines[#lines + 1] = "Awaiting bodies: " .. tostring(squad.dormant) .. " (" .. why .. ")"
        local waits = type(squad.bodyWaits) == "table" and squad.bodyWaits or {}
        for index = 1, math.min(#waits, 6) do
            local wait = waits[index]
            if type(wait) == "table" then
                local text = tostring(wait.uid or "member") .. ": " .. Overlay.bodyWaitReason(wait.reason)
                if tonumber(wait.distance) ~= nil then text = text .. " (" .. tostring(wait.distance) .. " tiles)" end
                if (tonumber(wait.retryS) or 0) > 0 then text = text .. ", retry in " .. tostring(wait.retryS) .. "s" end
                lines[#lines + 1] = text
            end
        end
        local omitted = (tonumber(squad.dormant) or 0) - math.min(#waits, 6)
        if omitted > 0 and #waits > 0 then lines[#lines + 1] = "+" .. tostring(omitted) .. " more waiting members" end
    end
    if type(squad.bloc) == "string" and squad.bloc ~= "" then lines[#lines + 1] = "Bloc: " .. squad.bloc end
    if squad.home ~= nil then lines[#lines + 1] = "From: " .. tostring(squad.home) end
    if squad.task ~= nil then lines[#lines + 1] = "Task: " .. tostring(squad.task) end
    if squad.activity ~= nil then lines[#lines + 1] = "Now: " .. tostring(squad.activity) end
    if squad.dest ~= nil then lines[#lines + 1] = "Going to: " .. tostring(squad.dest) end
    if squad.census ~= nil then lines[#lines + 1] = "Faction census: " .. tostring(squad.census) end
    local eta = tonumber(squad.eta)
    if eta ~= nil then
        lines[#lines + 1] = "Arrives in " .. Overlay.formatHours(eta) .. " (game time)"
    end
    if squad.outpost == true then
        local nextIn = tonumber(squad.nextSquadHours)
        if nextIn ~= nil then
            lines[#lines + 1] = "Next squad in " .. Overlay.formatHours(nextIn) .. " (game time)"
        end
        if squad.squadCap ~= nil then
            lines[#lines + 1] = "Squads out: " .. tostring(squad.squadsOut or 0) .. " of " .. tostring(squad.squadCap)
        end
    elseif squad.persistent ~= nil then
        lines[#lines + 1] = squad.persistent == true and "Saved with the world" or "This session only"
    end
    if type(Overlay.menuEntries) == "function" and #Overlay.menuEntries(squad) > 0 then
        lines[#lines + 1] = "Right-click for actions"
    end
    return lines
end

local function textWidth(font, text)
    local width = #text * 7
    pcall(function() width = getTextManager():MeasureStringX(font, text) end)
    return width
end

local function lineHeight(font)
    local height = 14
    pcall(function() height = getTextManager():getFontHeight(font) + 2 end)
    return height
end

function Overlay:drawTooltip(squad, mx, my)
    local lines = Overlay.tooltipLines(squad)
    if #lines == 0 then return end
    local font = UIFont.Small
    local lineH, width = lineHeight(font), 0
    for _, line in ipairs(lines) do
        local w = textWidth(font, line)
        if w > width then width = w end
    end
    local pad = 8
    local boxW, boxH = width + pad * 2, #lines * lineH + pad * 2
    local x, y = mx + 16, my + 12
    if x + boxW > self.width then x = math.max(0, mx - boxW - 8) end
    if y + boxH > self.height then y = math.max(0, my - boxH - 8) end
    self:drawRect(x, y, boxW, boxH, 0.92, 0.07, 0.07, 0.09)
    self:drawRectBorder(x, y, boxW, boxH, 0.9, 0.72, 0.55, 0.32)
    for index, line in ipairs(lines) do
        local r, g, b = 0.85, 0.85, 0.85
        if index == 1 then r, g, b = 1, 1, 1 end
        self:drawText(line, x + pad, y + pad + (index - 1) * lineH, r, g, b, 1, font)
    end
end

function Overlay:drawCaption()
    local text = self.caption
    if type(text) == "function" then text = text() end
    if type(text) ~= "string" or text == "" then return end
    local w = textWidth(UIFont.Small, text)
    local x, y = 12, 12
    self:drawRect(x - 6, y - 4, w + 12, 22, 0.75, 0.07, 0.07, 0.09)
    self:drawText(text, x, y, 0.9, 0.85, 0.7, 1, UIFont.Small)
end

function Overlay.rowHalf(radius, dy)
    if dy < -radius or dy > radius then return nil end
    return radius
end

function Overlay.addRects(rects, y, height, half, hole)
    if hole == nil then
        rects[#rects + 1] = { -half, y, half * 2 + 1, height }
    elseif half > hole then
        local width = half - hole
        rects[#rects + 1] = { -half, y, width, height }
        rects[#rects + 1] = { hole + 1, y, width, height }
    end
end

function Overlay.buildShape(outer, inner)
    local rects = {}
    local runY, runHalf, runHole
    for dy = -outer, outer + 1 do
        local half, hole
        if dy <= outer then
            half = Overlay.rowHalf(outer, dy)
            if inner ~= nil then hole = Overlay.rowHalf(inner, dy) end
        end
        if runY ~= nil and (half ~= runHalf or hole ~= runHole) then
            Overlay.addRects(rects, runY, dy - runY, runHalf, runHole)
            runY = nil
        end
        if half ~= nil and runY == nil then runY, runHalf, runHole = dy, half, hole end
    end
    return rects
end

function Overlay.shape(outer, inner)
    local byOuter = Overlay.shapes[outer]
    if byOuter == nil then
        byOuter = {}
        Overlay.shapes[outer] = byOuter
    end
    local key = inner or -1
    local rects = byOuter[key]
    if rects == nil then
        rects = Overlay.buildShape(outer, inner)
        byOuter[key] = rects
    end
    return rects
end

function Overlay.hitRadius(radius)
    return math.max(Overlay.hoverRadius, (tonumber(radius) or 0) + Overlay.hitPad)
end

function Overlay.hitDistance(dx, dy, radius)
    local d = dx * dx + dy * dy
    if math.abs(dx) <= radius and math.abs(dy) <= radius then return d end
    return nil
end

function Overlay.blocGroup(bloc)
    if type(bloc) ~= "string" then return "unknown" end
    local group = Overlay.blocGroups[bloc]
    if group == nil then group = Overlay.blocGroups[string.lower(bloc)] end
    if group == nil then return "unknown" end
    return group
end

function Overlay.rowBloc(row)
    local bloc = row.bloc
    if type(bloc) == "string" and bloc ~= "" then return bloc end
    local id = row.factionId
    if type(id) ~= "string" or id == "" then return nil end
    bloc = Overlay.factionBlocs[id]
    if bloc ~= nil then return bloc end
    local catalog, rules = ProjectALife.Catalog, ProjectALife.FactionSpawnRules
    if catalog == nil or type(catalog.faction) ~= "function" then return nil end
    if rules == nil or type(rules.blocOf) ~= "function" then return nil end
    local faction = catalog.faction(id)
    if type(faction) ~= "table" then return nil end
    bloc = rules.blocOf(faction)
    if type(bloc) ~= "string" or bloc == "" then return nil end
    Overlay.factionBlocs[id] = bloc
    return bloc
end

function Overlay.colorOf(group)
    local color = Overlay.palette[group]
    if color == nil then return Overlay.palette.unknown end
    return color
end

function Overlay.markerKind(row)
    if row.outpost == true then return "outpost" end
    if row.place == true then return "place" end
    if row.encounter == true then return "encounter" end
    if row.offline == true then return "offline" end
    return "live"
end

function Overlay.markerRadius(kind, members)
    if kind == "outpost" then return 5 end
    if kind == "place" then return 3 end
    if kind == "encounter" then return 4 end
    if (tonumber(members) or 1) >= 3 then return 4 end
    return 3
end

function Overlay.markerExtent(kind, radius)
    if kind == "outpost" then return radius + 3 end
    if kind == "live" then return radius + 2 end
    return radius + 1
end

function Overlay:drawShape(cx, cy, outer, inner, color, alpha)
    local rects = Overlay.shape(outer, inner)
    local r, g, b = color[1], color[2], color[3]
    for index = 1, #rects do
        local rect = rects[index]
        self:drawRect(cx + rect[1], cy + rect[2], rect[3], rect[4], alpha, r, g, b)
    end
end

function Overlay:drawMarker(kind, color, radius, cx, cy)
    if kind == "place" or kind == "encounter" then
        self:drawShape(cx, cy, radius + 1, radius, Overlay.ringOffline, 0.95)
        self:drawShape(cx, cy, radius, radius - 2, color, 0.95)
    elseif kind == "outpost" then
        self:drawShape(cx, cy, radius + 3, nil, Overlay.ringOffline, 0.95)
        self:drawShape(cx, cy, radius + 2, nil, Overlay.ringLive, 0.95)
        self:drawShape(cx, cy, radius + 1, nil, Overlay.ringOffline, 0.95)
        self:drawShape(cx, cy, radius, nil, color, 0.95)
    elseif kind == "live" then
        self:drawShape(cx, cy, radius + 2, nil, Overlay.ringOffline, 0.95)
        self:drawShape(cx, cy, radius + 1, nil, Overlay.ringLive, 0.95)
        self:drawShape(cx, cy, radius, nil, color, 0.95)
    else
        self:drawShape(cx, cy, radius + 1, nil, Overlay.ringOffline, 0.95)
        self:drawShape(cx, cy, radius, nil, color, 0.95)
    end
end

function Overlay.drawRow(self, api, squad, mx, my)
    local sx = api:worldToUIX(squad.x, squad.y)
    local sy = api:worldToUIY(squad.x, squad.y)
    if sx < -40 or sy < -40 or sx > self.width + 40 or sy > self.height + 40 then return nil end
    sx, sy = math.floor(sx + 0.5), math.floor(sy + 0.5)
    local kind = Overlay.markerKind(squad)
    local radius = Overlay.markerRadius(kind, squad.members)
    self:drawMarker(kind, Overlay.colorOf(Overlay.blocGroup(Overlay.rowBloc(squad))), radius, sx, sy)
    local extent = Overlay.markerExtent(kind, radius)
    if kind ~= "place" then
        local label = tostring(squad.label or "squad")
        if (tonumber(squad.members) or 1) > 1 then
            label = label .. "  (" .. tostring(squad.members) .. ")"
        end
        self:drawText(label, sx + extent + 4, sy - 7, 1, 1, 1, 1, UIFont.Small)
    end
    return Overlay.hitDistance(mx - sx, my - sy, Overlay.hitRadius(extent))
end

function Overlay.legendNames()
    local names = Overlay.legendText
    if names ~= nil then return names end
    local ready = ProjectALife.Text ~= nil and type(ProjectALife.Text.ui) == "function"
    names = {}
    names.heading = ready and ProjectALife.Text.ui("Squad key") or "Squad key"
    names.civilian = ready and ProjectALife.Text.ui("Civilian") or "Civilian"
    names.military = ready and ProjectALife.Text.ui("Military") or "Military"
    names.law = ready and ProjectALife.Text.ui("Law") or "Law"
    names.medical = ready and ProjectALife.Text.ui("Medical") or "Medical"
    names.crime = ready and ProjectALife.Text.ui("Crime") or "Crime"
    names.elite = ready and ProjectALife.Text.ui("Elite") or "Elite"
    names.unknown = ready and ProjectALife.Text.ui("Unknown") or "Unknown"
    names.live = ready and ProjectALife.Text.ui("Live") or "Live"
    names.offline = ready and ProjectALife.Text.ui("Offline") or "Offline"
    names.place = ready and ProjectALife.Text.ui("Place") or "Place"
    names.outpost = ready and ProjectALife.Text.ui("Outpost") or "Outpost"
    Overlay.legendText = names
    return names
end

function Overlay:legendOrigin(boxW, boxH)
    local key = self.worldMap ~= nil and self.worldMap.keyUI or nil
    if type(key) == "table" and type(key.isVisible) == "function" and key:isVisible() == true then
        local left, top = tonumber(key.x) or 10, tonumber(key.y) or 10
        local below = top + (tonumber(key.height) or 0) + 8
        if below + boxH <= self.height - 8 then return left, below end
        return left + (tonumber(key.width) or 0) + 10, 42
    end
    return 10, 42
end

function Overlay:drawLegend()
    local names = Overlay.legendNames()
    local font = UIFont.Small
    local lineH = lineHeight(font)
    local rowH = math.max(lineH, 14)
    local textW = Overlay.legendWidth
    if textW == nil then
        textW = textWidth(font, names.heading)
        for index = 1, #Overlay.groupOrder do
            textW = math.max(textW, textWidth(font, names[Overlay.groupOrder[index]]))
        end
        for index = 1, #Overlay.stateOrder do
            textW = math.max(textW, textWidth(font, names[Overlay.stateOrder[index]]))
        end
        Overlay.legendWidth = textW
    end
    local pad, sampleX, textX = 6, 16, 32
    local outpostH = math.max(rowH, 2 * Overlay.markerExtent("outpost", Overlay.markerRadius("outpost")) + 4)
    local boxW = textX + textW + pad
    local boxH = pad * 2 + rowH * (#Overlay.groupOrder + #Overlay.stateOrder) + 6 + outpostH
    local x, y = self:legendOrigin(boxW, boxH)
    self:drawRect(x, y, boxW, boxH, 0.92, 0.30, 0.30, 0.30)
    self:drawRectBorder(x, y, boxW, boxH, 0.9, 0.72, 0.72, 0.72)
    local top = y + pad
    self:drawText(names.heading, x + pad, top, 1, 1, 1, 1, font)
    top = top + rowH
    for index = 1, #Overlay.groupOrder do
        local id = Overlay.groupOrder[index]
        self:drawShape(x + sampleX, top + math.floor(rowH / 2), 4, nil, Overlay.colorOf(id), 0.95)
        self:drawText(names[id], x + textX, top + math.floor((rowH - lineH) / 2), 1, 1, 1, 1, font)
        top = top + rowH
    end
    self:drawRect(x + pad, top + 2, boxW - pad * 2, 1, 0.8, 0.72, 0.72, 0.72)
    top = top + 6
    for index = 1, #Overlay.stateOrder do
        local id = Overlay.stateOrder[index]
        local height = rowH
        if id == "outpost" then height = outpostH end
        self:drawMarker(id, Overlay.palette.unknown, Overlay.markerRadius(id), x + sampleX, top + math.floor(height / 2))
        self:drawText(names[id], x + textX, top + math.floor((height - lineH) / 2), 1, 1, 1, 1, font)
        top = top + height
    end
end

function Overlay:render()
    local squads = type(self.provider) == "function" and self.provider() or nil
    if type(squads) ~= "table" or #squads == 0 then
        self.hovered = nil
        self:drawCaption()
        return
    end
    local api
    pcall(function() api = self.worldMap.mapAPI end)
    if api == nil then return end
    self:setWidth(self.worldMap.width)
    self:setHeight(self.worldMap.height)

    local mx, my = -100000, -100000
    pcall(function() mx, my = self:getMouseX(), self:getMouseY() end)
    local hovered, hoveredDistance = nil, math.huge
    for _, squad in ipairs(squads) do
        local ok, hit = pcall(Overlay.drawRow, self, api, squad, mx, my)
        if not ok then
            Overlay.skipped = (Overlay.skipped or 0) + 1
        elseif hit ~= nil and hit < hoveredDistance then
            hovered, hoveredDistance = squad, hit
        end
    end

    self.hovered = hovered
    pcall(self.drawLegend, self)
    if hovered ~= nil then
        pcall(function() self:drawTooltip(hovered, mx, my) end)
    end
    self:drawCaption()
end

return Overlay
