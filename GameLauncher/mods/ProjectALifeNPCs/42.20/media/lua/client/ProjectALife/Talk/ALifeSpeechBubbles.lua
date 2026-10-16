ProjectALife = ProjectALife or {}
require "ProjectALife/Core/ALifeText"
require "ProjectALife/Records/ALifeNames"
require "ProjectALife/Talk/ALifeSpeech"
require "ProjectALife/Talk/ALifeTalkUi"
require "ProjectALife/Talk/ALifeSpeechBubbleLayout"

local Layout = ProjectALife.SpeechBubbleLayout
local Speech = ProjectALife.Speech

local Bubbles = {
    layers = {},
    session = 1,
    faults = 0,
    failed = nil,
    manager = nil,
    font = nil,
    metrics = { shown = 0, offscreen = 0, dropped = 0, fallback = 0, merged = 0, faults = 0 },
}
ProjectALife.SpeechBubbles = Bubbles

Bubbles.maxFaults = 3
Bubbles.fillAlpha = 0.82
Bubbles.borderAlpha = 0.55
Bubbles.calmMix = 0.65
Bubbles.soft = { 0.93, 0.93, 0.90 }

function Bubbles.enabled()
    if Bubbles.failed ~= nil then return false end
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(vars) == "table" and vars.Text_Bubbles == false then return false end
    return true
end

function Bubbles.now()
    if type(getTimestampMs) ~= "function" then return nil end
    return getTimestampMs()
end

function Bubbles.textManager()
    if type(getTextManager) ~= "function" then return nil end
    local manager = getTextManager()
    if manager == nil or type(manager.MeasureStringX) ~= "function" or type(manager.getFontHeight) ~= "function" then
        return nil
    end
    return manager
end

function Bubbles.measureCurrent(text)
    return Bubbles.manager:MeasureStringX(Bubbles.font, text)
end

function Bubbles.position(object)
    local kind = type(object)
    if object == nil or kind == "number" or kind == "string" or kind == "boolean" then return nil end
    if type(object.getX) ~= "function" or type(object.getY) ~= "function" or type(object.getZ) ~= "function" then
        return nil
    end
    local x, y, z = object:getX(), object:getY(), object:getZ()
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    if type(z) ~= "number" then z = 0 end
    return x, y, z
end

function Bubbles.speakerHere(shell)
    if type(Speech.alive) == "function" and Speech.alive(shell) ~= true then return false end
    if type(shell.getCurrentSquare) == "function" and shell:getCurrentSquare() == nil then return false end
    return true
end

function Bubbles.pinRange()
    local range = 0
    if type(Speech.textRange) == "function" then range = tonumber(Speech.textRange()) or 0 end
    if range <= 0 then range = tonumber(Speech.settings.earshot) or 40 end
    return range
end

function Bubbles.screenRect(num)
    if type(getPlayerScreenLeft) == "function" and type(getPlayerScreenTop) == "function"
            and type(getPlayerScreenWidth) == "function" and type(getPlayerScreenHeight) == "function" then
        local width, height = getPlayerScreenWidth(num), getPlayerScreenHeight(num)
        if type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
            return getPlayerScreenLeft(num), getPlayerScreenTop(num), width, height
        end
    end
    if type(getCore) == "function" then
        local core = getCore()
        if core ~= nil and type(core.getScreenWidth) == "function" and type(core.getScreenHeight) == "function" then
            return 0, 0, core:getScreenWidth(), core:getScreenHeight()
        end
    end
    return nil
end

function Bubbles.playerNumber(player, fallback)
    if player ~= nil and type(player.getPlayerNum) == "function" then
        local num = player:getPlayerNum()
        if type(num) == "number" then return num end
    end
    return fallback
end

function Bubbles.cleanName(name)
    local cleaned = string.gsub(name, "[<>]", "")
    return cleaned
end

function Bubbles.stranger()
    if ProjectALife.Text ~= nil and type(ProjectALife.Text.ui) == "function" then return ProjectALife.Text.ui("Stranger") end
    return "Stranger"
end

function Bubbles.recordOf(uid)
    local menu = ProjectALife.TalkMenu
    if menu ~= nil and type(menu.recordFor) == "function" then
        local ok, record = pcall(menu.recordFor, uid)
        if ok and type(record) == "table" then return record end
    end
    return nil
end

function Bubbles.nameFor(uid, player)
    local names = ProjectALife.Names
    if uid == nil or tostring(uid) == "" or names == nil or type(names.shown) ~= "function" then
        return Bubbles.stranger()
    end
    local record = Bubbles.recordOf(tostring(uid))
    if record == nil then return Bubbles.stranger() end
    local key = nil
    if type(Speech.playerKey) == "function" then
        local ok, value = pcall(Speech.playerKey, player)
        if ok then key = value end
    end
    local ok, name, known = pcall(names.shown, record, key)
    if ok and known == true and type(name) == "string" and name ~= "" then return Bubbles.cleanName(name) end
    return Bubbles.stranger()
end

function Bubbles.tilesText(count)
    if ProjectALife.Text == nil or type(ProjectALife.Text.ui) ~= "function" then return tostring(count) .. " tiles" end
    if count == 1 then return ProjectALife.Text.ui("1 tile") end
    return ProjectALife.Text.ui("{n} tiles", { n = count })
end

function Bubbles.colorOf(color, uid)
    if type(color) ~= "table" and type(Speech.colorFor) == "function" then color = Speech.colorFor(uid, nil) end
    local r, g, b = 0.82, 0.82, 0.82
    if type(color) == "table" then
        r = Layout.clamp(tonumber(color[1]) or r, 0, 1)
        g = Layout.clamp(tonumber(color[2]) or g, 0, 1)
        b = Layout.clamp(tonumber(color[3]) or b, 0, 1)
    end
    return r, g, b
end

function Bubbles.textColor(r, g, b, color)
    if type(color) == "table" and color.exact == true then return r, g, b end
    local mix, soft = Bubbles.calmMix, Bubbles.soft
    return r + (soft[1] - r) * mix, g + (soft[2] - g) * mix, b + (soft[3] - b) * mix
end

function Bubbles.build(shell, text, color, kind, uid, player, now)
    local manager = Bubbles.textManager()
    if manager == nil or UIFont == nil then return nil end
    local s = Layout.settings
    local ambient = kind == "ambient"
    local nameFont, textFont = UIFont.Small, UIFont.Medium
    if ambient then textFont = UIFont.Small end
    local e = { shell = shell, uid = uid, kind = kind, ambient = ambient, text = text, startMs = now,
        checkAt = 0, losAt = 0, mode = Layout.HIDDEN, page = 1, alpha = 0, occluded = false, here = true }
    e.r, e.g, e.b = Bubbles.colorOf(color, uid)
    e.tr, e.tg, e.tb = Bubbles.textColor(e.r, e.g, e.b, color)
    Layout.scale(e, manager:getFontHeight(UIFont.Small))
    e.accentW = Layout.px(3, e.factor)
    e.gap = Layout.px(8, e.factor)
    e.nameGap = Layout.px(s.nameGap, e.factor)
    e.inner = 2 + e.accentW + e.padX
    e.nameFont, e.textFont = nameFont, textFont
    e.lineH = manager:getFontHeight(textFont) + s.lineGap
    e.nameH = manager:getFontHeight(nameFont)
    Bubbles.manager, Bubbles.font = manager, textFont
    local lines = Layout.wrap(text, manager:MeasureStringX(textFont, Layout.sample), Bubbles.measureCurrent)
    local pages = Layout.paginate(lines, s.maxPageLines)
    e.pages, e.pageCount, e.pageMs = pages, #pages, {}
    local textW, maxLines, total = 0, 1, 0
    for index = 1, #pages do
        local page = pages[index]
        local chars = 0
        for row = 1, #page do
            local width = manager:MeasureStringX(textFont, page[row])
            if width > textW then textW = width end
            chars = chars + #page[row]
        end
        if #page > maxLines then maxLines = #page end
        e.pageMs[index] = Layout.holdMs(chars)
        total = total + e.pageMs[index]
    end
    e.totalMs = total
    e.endMs = now + total
    e.name = Bubbles.nameFor(uid, player)
    e.nameW = manager:MeasureStringX(nameFont, e.name)
    local tagW = 0
    if e.pageCount > 1 then
        e.tags = {}
        for index = 1, e.pageCount do e.tags[index] = tostring(index) .. "/" .. tostring(e.pageCount) end
        tagW = manager:MeasureStringX(nameFont, tostring(e.pageCount) .. "/" .. tostring(e.pageCount))
    end
    local headRight = tagW
    local pinRight = manager:MeasureStringX(nameFont, Bubbles.tilesText(99))
    if tagW > 0 then pinRight = pinRight + e.gap + tagW end
    local headName = e.nameW
    if headRight > 0 then headName = headName + e.gap + headRight end
    e.wHead = e.inner + math.max(textW, headName) + e.padX
    e.wPin = e.inner + math.max(textW, e.nameW + e.gap + pinRight) + e.padX
    if ambient then e.wPin = e.wHead end
    e.w = e.wHead
    e.h = e.padY * 2 + e.nameH + e.nameGap + maxLines * e.lineH - s.lineGap
    if e.tags ~= nil then e.rightText = e.tags[1] end
    return e
end

function Bubbles.rightOf(e, count, page)
    local text = Bubbles.tilesText(count)
    if e.tags ~= nil then text = text .. "  " .. e.tags[page] end
    return text
end

function Bubbles.locate(layer, e, now, player)
    local s = Layout.settings
    if now >= e.checkAt then
        e.checkAt = now + s.aliveMs
        e.here = Bubbles.speakerHere(e.shell)
    end
    local x, y, z
    if e.here then x, y, z = Bubbles.position(e.shell) end
    if x ~= nil then
        e.lx, e.ly, e.lz = x, y, z
    elseif e.kind == "final" and e.lx ~= nil then
        x, y, z = e.lx, e.ly, e.lz
    else
        return false
    end
    local num = layer.playerNum
    local rise = z + s.headRise
    local hx = isoToScreenX(num, x, y, rise) - layer.left
    local hy = isoToScreenY(num, x, y, rise) - layer.top
    local px, py, pz = Bubbles.position(player)
    local distance = 0
    if px ~= nil then
        local dx, dy = x - px, y - py
        distance = math.sqrt(dx * dx + dy * dy)
    end
    e.distance = distance
    if now >= e.losAt then
        e.losAt = now + s.losMs
        local clear = true
        if px ~= nil then
            clear = math.floor(pz) == math.floor(z) and Speech.sees(player, e.shell) == true
        end
        e.occluded = not clear
    end
    local view = layer.view
    local page = Layout.pageAt(e.pageMs, e.pageCount, now - e.startMs)
    if Layout.onScreen(view, hx, hy, e.pad) then
        Layout.placeHead(e, view, hx, hy)
        e.distanceCount = nil
        if e.tags ~= nil then e.rightText = e.tags[page] else e.rightText = nil end
    elseif e.ambient ~= true and distance <= Bubbles.pinRange() then
        Layout.pin(e, view, hx, hy)
        local count = math.floor(distance + 0.5)
        if count ~= e.distanceCount or page ~= e.rightPage then
            e.distanceCount, e.rightPage = count, page
            e.rightText = Bubbles.rightOf(e, count, page)
        end
    else
        e.mode = Layout.HIDDEN
    end
    e.page = page
    return true
end

function Bubbles.liveCount(layer)
    local live = 0
    for index = 1, layer.count do
        if layer.entries[index].fading ~= true then live = live + 1 end
    end
    return live
end

function Bubbles.victim(layer, incomingAmbient)
    local oldest, oldestAmbient = nil, nil
    for index = 1, layer.count do
        local e = layer.entries[index]
        if e.fading ~= true then
            if oldest == nil then oldest = e end
            if e.ambient and oldestAmbient == nil then oldestAmbient = e end
        end
    end
    if oldestAmbient ~= nil then return oldestAmbient end
    if incomingAmbient then return nil end
    return oldest
end

function Bubbles.remove(layer, index)
    local entries = layer.entries
    local count = layer.count
    for slot = index, count - 1 do entries[slot] = entries[slot + 1] end
    entries[count] = nil
    layer.count = count - 1
    if layer.count == 0 then
        for slot = 1, #layer.order do layer.order[slot] = nil end
        layer:setVisible(false)
    end
end

function Bubbles.fadeOut(e, now)
    e.fading = true
    local last = now + Layout.settings.fadeMs
    if e.endMs > last then e.endMs = last end
end

function Bubbles.attach(layer, e, now)
    local s = Layout.settings
    local entries = layer.entries
    if Bubbles.liveCount(layer) >= s.maxLive then
        local victim = Bubbles.victim(layer, e.ambient)
        if victim == nil then
            Bubbles.metrics.dropped = Bubbles.metrics.dropped + 1
            return false
        end
        Bubbles.fadeOut(victim, now)
    end
    if layer.count >= s.maxTotal then
        for index = 1, layer.count do
            if entries[index].fading == true then
                Bubbles.remove(layer, index)
                Bubbles.metrics.dropped = Bubbles.metrics.dropped + 1
                break
            end
        end
    end
    layer.count = layer.count + 1
    entries[layer.count] = e
    return true
end

function Bubbles.offer(shell, text, color, kind, uid, player, num, now)
    local layer = Bubbles.layerFor(num)
    if layer == nil then return false end
    Bubbles.syncRect(layer)
    local entries = layer.entries
    for index = 1, layer.count do
        local other = entries[index]
        if other.shell == shell and other.text == text and now - other.startMs < Layout.settings.duplicateMs then
            Bubbles.metrics.merged = Bubbles.metrics.merged + 1
            return true
        end
    end
    local e = Bubbles.build(shell, text, color, kind, uid, player, now)
    if e == nil then return false end
    if Bubbles.locate(layer, e, now, player) == false or e.mode == Layout.HIDDEN then
        Bubbles.metrics.dropped = Bubbles.metrics.dropped + 1
        return true
    end
    if Bubbles.attach(layer, e, now) then
        Bubbles.metrics.shown = Bubbles.metrics.shown + 1
        layer:setVisible(true)
    end
    return true
end

function Bubbles.accept(shell, text, color, kind, uid)
    if type(text) ~= "string" or text == "" then return false end
    if string.find(text, "%S") == nil then return true end
    if type(isoToScreenX) ~= "function" or type(isoToScreenY) ~= "function" then return false end
    if Bubbles.layerClass() == nil then return false end
    local players = Speech.localPlayers()
    if #players == 0 then return false end
    if kind ~= "ambient" and kind ~= "final" then kind = "directed" end
    if uid == nil or tostring(uid) == "" then uid = Speech.variable(shell, "ALifeUID") end
    local now = Bubbles.now()
    if now == nil then return false end
    local handled = false
    for index = 1, #players do
        local player = players[index]
        local num = Bubbles.playerNumber(player, index - 1)
        if Bubbles.offer(shell, text, color, kind, uid, player, num, now) then handled = true end
    end
    return handled
end

function Bubbles.show(shell, text, color, kind, uid)
    if not Bubbles.enabled() then return false end
    local ok, handled = pcall(Bubbles.accept, shell, text, color, kind, uid)
    if ok and handled == true then return true end
    if not ok then Bubbles.fault(handled) end
    Bubbles.metrics.fallback = Bubbles.metrics.fallback + 1
    return false
end

function Bubbles.fault(err)
    Bubbles.faults = Bubbles.faults + 1
    Bubbles.metrics.faults = Bubbles.faults
    Bubbles.clear()
    if Bubbles.faults >= Bubbles.maxFaults and Bubbles.failed == nil then
        Bubbles.failed = tostring(err)
        print("[ALIFE-UI] speech bubbles off for this session: " .. Bubbles.failed)
    end
end

function Bubbles.discard(layer)
    if layer == nil then return end
    if type(layer.removeFromUIManager) == "function" then pcall(layer.removeFromUIManager, layer) end
    layer.removed = true
end

function Bubbles.clear()
    for num, layer in pairs(Bubbles.layers) do
        Bubbles.discard(layer)
        Bubbles.layers[num] = nil
    end
end

function Bubbles.restart()
    Bubbles.clear()
    Bubbles.session = Bubbles.session + 1
end

function Bubbles.empty(layer)
    for index = layer.count, 1, -1 do layer.entries[index] = nil end
    layer.count = 0
    for slot = #layer.order, 1, -1 do layer.order[slot] = nil end
    layer:setVisible(false)
end

function Bubbles.onDeath(player)
    local num = Bubbles.playerNumber(player, nil)
    if num == nil then return end
    local layer = Bubbles.layers[num]
    if layer ~= nil then Bubbles.empty(layer) end
end

function Bubbles.syncRect(layer)
    local left, top, width, height = Bubbles.screenRect(layer.playerNum)
    if left == nil then return false end
    if left ~= layer.left or top ~= layer.top then
        layer:setX(left)
        layer:setY(top)
        layer.left, layer.top = left, top
    end
    if width ~= layer.vw or height ~= layer.vh then
        layer:setWidth(width)
        layer:setHeight(height)
        layer.vw, layer.vh = width, height
        layer.view.w, layer.view.h = width, height
    end
    return true
end

function Bubbles.step(layer, now)
    local player = nil
    if type(getSpecificPlayer) == "function" then player = getSpecificPlayer(layer.playerNum) end
    if player == nil then
        Bubbles.empty(layer)
        return 0
    end
    local entries, order = layer.entries, layer.order
    local shown, index = 0, 1
    while index <= layer.count do
        local e = entries[index]
        if now >= e.endMs then
            Bubbles.remove(layer, index)
        elseif Bubbles.locate(layer, e, now, player) == false then
            Bubbles.metrics.dropped = Bubbles.metrics.dropped + 1
            Bubbles.remove(layer, index)
        else
            if e.mode ~= Layout.HIDDEN then
                shown = shown + 1
                order[shown] = e
                local alpha = Layout.fade(now, e.startMs, e.endMs)
                if e.ambient then alpha = alpha * Layout.settings.ambientAlpha end
                if e.occluded and e.mode == Layout.HEAD then alpha = alpha * Layout.settings.occludedAlpha end
                e.alpha = alpha
                if e.mode == Layout.PIN and e.pinCounted ~= true then
                    e.pinCounted = true
                    Bubbles.metrics.offscreen = Bubbles.metrics.offscreen + 1
                end
            end
            index = index + 1
        end
    end
    for slot = shown + 1, #order do order[slot] = nil end
    Layout.stack(order, shown, layer.view)
    for slot = 1, shown do
        if order[slot].mode == Layout.HEAD then Layout.finishTail(order[slot]) end
    end
    return shown
end

function Bubbles.fillTriangle(layer, ax, ay, bx, by, cx, cy, alpha, r, g, b, dash)
    local x1, y1, x2, y2, x3, y3 = ax, ay, bx, by, cx, cy
    if y2 < y1 then x1, y1, x2, y2 = x2, y2, x1, y1 end
    if y3 < y1 then x1, y1, x3, y3 = x3, y3, x1, y1 end
    if y3 < y2 then x2, y2, x3, y3 = x3, y3, x2, y2 end
    local height = y3 - y1
    if height < 1 then
        local low, high = math.min(x1, x2, x3), math.max(x1, x2, x3)
        layer:drawRect(low, y1, high - low + 1, 1, alpha, r, g, b)
        return
    end
    local step = math.max(1, math.ceil(height / 24))
    local row, y = 0, y1
    while y < y3 do
        local sample = y + step * 0.5
        if sample > y3 then sample = y3 end
        local long = x1 + (x3 - x1) * (sample - y1) / height
        local short
        if sample < y2 then
            local span = y2 - y1
            if span > 0 then short = x1 + (x2 - x1) * (sample - y1) / span else short = x2 end
        else
            local span = y3 - y2
            if span > 0 then short = x2 + (x3 - x2) * (sample - y2) / span else short = x2 end
        end
        local low, high = long, short
        if low > high then low, high = high, low end
        if dash ~= true or row % 2 == 0 then
            layer:drawRect(low, y, high - low + 1, math.min(step, y3 - y), alpha, r, g, b)
        end
        y = y + step
        row = row + 1
    end
end

function Bubbles.roundFill(layer, x, y, w, h, radius, alpha, r, g, b)
    local insets = Layout.insets(radius)
    for row = 1, radius do
        local inset = insets[row]
        layer:drawRect(x + inset, y + row - 1, w - 2 * inset, 1, alpha, r, g, b)
        layer:drawRect(x + inset, y + h - row, w - 2 * inset, 1, alpha, r, g, b)
    end
    layer:drawRect(x, y + radius, w, h - 2 * radius, alpha, r, g, b)
end

function Bubbles.roundBorder(layer, x, y, w, h, radius, alpha, r, g, b)
    local insets = Layout.insets(radius)
    layer:drawRect(x + insets[1], y, w - 2 * insets[1], 1, alpha, r, g, b)
    layer:drawRect(x + insets[1], y + h - 1, w - 2 * insets[1], 1, alpha, r, g, b)
    for row = 2, radius do
        local inset = insets[row]
        local run = math.max(1, insets[row - 1] - inset)
        layer:drawRect(x + inset, y + row - 1, run, 1, alpha, r, g, b)
        layer:drawRect(x + w - inset - run, y + row - 1, run, 1, alpha, r, g, b)
        layer:drawRect(x + inset, y + h - row, run, 1, alpha, r, g, b)
        layer:drawRect(x + w - inset - run, y + h - row, run, 1, alpha, r, g, b)
    end
    layer:drawRect(x, y + radius, 1, h - 2 * radius, alpha, r, g, b)
    layer:drawRect(x + w - 1, y + radius, 1, h - 2 * radius, alpha, r, g, b)
end

function Bubbles.shadowText(layer, str, x, y, r, g, b, alpha, font)
    layer:drawText(str, x + 1, y + 1, 0, 0, 0, alpha * 0.8, font)
    layer:drawText(str, x - 1, y - 1, 0, 0, 0, alpha * 0.8, font)
    layer:drawText(str, x + 1, y - 1, 0, 0, 0, alpha * 0.8, font)
    layer:drawText(str, x - 1, y + 1, 0, 0, 0, alpha * 0.8, font)
    layer:drawText(str, x, y, r, g, b, alpha, font)
end

function Bubbles.shadowRight(layer, str, x, y, r, g, b, alpha, font)
    layer:drawTextRight(str, x + 1, y + 1, 0, 0, 0, alpha * 0.8, font)
    layer:drawTextRight(str, x - 1, y - 1, 0, 0, 0, alpha * 0.8, font)
    layer:drawTextRight(str, x + 1, y - 1, 0, 0, 0, alpha * 0.8, font)
    layer:drawTextRight(str, x - 1, y + 1, 0, 0, 0, alpha * 0.8, font)
    layer:drawTextRight(str, x, y, r, g, b, alpha, font)
end

function Bubbles.paintLink(layer, e)
    local alpha = e.alpha
    if alpha <= 0.01 then return end
    if e.mode == Layout.HEAD then
        if e.tailVisible then
            Bubbles.fillTriangle(layer, e.baseX - e.tailHalf, e.baseY, e.baseX + e.tailHalf, e.baseY,
                e.tipX, e.tipY, alpha * Bubbles.fillAlpha * layer.shade, 0.04, 0.05, 0.06, e.occluded)
        end
        return
    end
    local half = e.arrow * 0.6
    local nx, ny = -e.dirY, e.dirX
    local lx, ly = e.arrowBaseX + nx * half, e.arrowBaseY + ny * half
    local rx, ry = e.arrowBaseX - nx * half, e.arrowBaseY - ny * half
    Bubbles.fillTriangle(layer, lx + 1, ly + 1, rx + 1, ry + 1, e.arrowX + 1, e.arrowY + 1, alpha * 0.7, 0, 0, 0, false)
    Bubbles.fillTriangle(layer, lx, ly, rx, ry, e.arrowX, e.arrowY, alpha, e.r, e.g, e.b, false)
end

function Bubbles.paintBox(layer, e)
    local alpha = e.alpha
    if alpha <= 0.01 then return end
    local x, y, w, h, radius = e.x, e.y, e.w, e.h, e.radius
    Bubbles.roundFill(layer, x, y, w, h, radius, alpha * Bubbles.fillAlpha * layer.shade, 0.04, 0.05, 0.06)
    Bubbles.roundBorder(layer, x, y, w, h, radius, alpha * Bubbles.borderAlpha * layer.shade, 0.62, 0.66, 0.70)
    layer:drawRect(x + 2, y + radius, e.accentW, h - 2 * radius, alpha * 0.9, e.r, e.g, e.b)
    local left = x + e.inner
    local top = y + e.padY
    Bubbles.shadowText(layer, e.name, left, top, 0.93, 0.93, 0.93, alpha, e.nameFont)
    if e.rightText ~= nil then
        Bubbles.shadowRight(layer, e.rightText, x + w - e.padX, top, 0.70, 0.74, 0.78, alpha, e.nameFont)
    end
    local page = e.pages[e.page]
    local lineY = top + e.nameH + e.nameGap
    for row = 1, #page do
        Bubbles.shadowText(layer, page[row], left, lineY, e.tr, e.tg, e.tb, alpha, e.textFont)
        lineY = lineY + e.lineH
    end
end

function Bubbles.paintBody(layer)
    if layer.count == 0 then return end
    local now = Bubbles.now()
    if now == nil then return end
    layer.shade = ProjectALife.TalkUi.opacity()
    local shown = Bubbles.step(layer, now)
    if shown == 0 then return end
    local order = layer.order
    for index = 1, shown do Bubbles.paintLink(layer, order[index]) end
    for index = 1, shown do Bubbles.paintBox(layer, order[index]) end
end

function Bubbles.paint(layer)
    local ok, err = pcall(Bubbles.paintBody, layer)
    if not ok then Bubbles.fault(err) end
end

function Bubbles.layerClass()
    if Bubbles.class ~= nil then return Bubbles.class end
    if ISUIElement == nil or type(ISUIElement.derive) ~= "function" then return nil end
    local class = ISUIElement:derive("ALifeSpeechBubbleLayer")
    function class:prerender()
        Bubbles.syncRect(self)
    end
    function class:render()
        Bubbles.paint(self)
    end
    Bubbles.class = class
    return class
end

function Bubbles.layerFor(num)
    local layer = Bubbles.layers[num]
    if layer ~= nil and layer.session == Bubbles.session and layer.removed ~= true then return layer end
    if layer ~= nil then
        Bubbles.discard(layer)
        Bubbles.layers[num] = nil
    end
    local class = Bubbles.layerClass()
    if class == nil then return nil end
    local left, top, width, height = Bubbles.screenRect(num)
    if left == nil then return nil end
    layer = class:new(left, top, width, height)
    ProjectALife.TalkUi.passThrough(layer)
    layer.playerNum = num
    layer.session = Bubbles.session
    layer.left, layer.top, layer.vw, layer.vh = left, top, width, height
    layer.view = { w = width, h = height }
    layer.entries, layer.order, layer.count = {}, {}, 0
    layer.shade = 1
    layer:initialise()
    layer:addToUIManager()
    layer:setVisible(false)
    if type(layer.backMost) == "function" then layer:backMost() end
    Bubbles.layers[num] = layer
    return layer
end

function Bubbles.qaLine()
    local m = Bubbles.metrics
    local state = "on"
    if Bubbles.failed ~= nil then state = "failed" elseif not Bubbles.enabled() then state = "off" end
    return "[ALIFE-QA] Bubbles: shown=" .. tostring(m.shown) .. " offscreen=" .. tostring(m.offscreen)
        .. " dropped=" .. tostring(m.dropped) .. " fallback=" .. tostring(m.fallback)
        .. " merged=" .. tostring(m.merged)
        .. " faults=" .. tostring(m.faults) .. " state=" .. state
end

function Bubbles.reset()
    Bubbles.clear()
    Bubbles.session = 1
    Bubbles.faults = 0
    Bubbles.failed = nil
    Bubbles.metrics = { shown = 0, offscreen = 0, dropped = 0, fallback = 0, merged = 0, faults = 0 }
end

if type(Events) == "table" then
    if Events.OnGameStart ~= nil and type(Events.OnGameStart.Add) == "function" then Events.OnGameStart.Add(Bubbles.restart) end
    if Events.OnPlayerDeath ~= nil and type(Events.OnPlayerDeath.Add) == "function" then
        Events.OnPlayerDeath.Add(Bubbles.onDeath)
    end
end

return Bubbles
