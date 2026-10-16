require "ISUI/ISButton"
require "ProjectALife/Core/ALifeText"
require "ProjectALife/Talk/ALifeSpeech"
require "ProjectALife/Talk/ALifeTalkUi"
require "ProjectALife/Talk/ALifeSpeechBubbles"
require "ProjectALife/Talk/ALifeTalkMenu"
require "ProjectALife/Interface/ALifeSafehouseClient"

ProjectALife = ProjectALife or {}

local Prompt = {
    settings = { scanMs = 250, questionMs = 30000, reachSq = 36, findMs = 1500, noteCap = 16, gap = 22, height = 26,
        pad = 16, margin = 8, fallbackRise = 170, afterMs = 2500, stoopSq = 6.25 },
    noted = {}, noteOrder = {}, slots = {}, findAt = {}, found = {},
    class = nil, failed = nil, faults = 0, nextAt = 0, quietUntil = 0,
    metrics = { shown = 0, clicks = 0, opened = 0, refused = 0, faults = 0 },
}
ProjectALife.TalkPrompt = Prompt

Prompt.look = {
    fadeInMs = 150, fadeOutMs = 120, holdMs = 400, pulseMs = 1800,
    rise = 6, below = 22, tail = 6, radius = 4, accentW = 3, padX = 9, padY = 6, gap = 7, pillPad = 6,
    fillAlpha = 0.82, borderAlpha = 0.62,
    fill = { 0.04, 0.05, 0.06 }, edge = { 0.62, 0.66, 0.70 }, name = { 0.93, 0.93, 0.93 }, text = { 0.72, 0.76, 0.80 },
    calm = { 0.46, 0.68, 0.74 },
    stances = {
        friendly = { 0.40, 0.84, 0.76 }, neutral = { 0.58, 0.68, 0.78 },
        careful = { 0.92, 0.72, 0.34 }, hostile = { 0.92, 0.40, 0.36 },
    },
    chips = { door = { 0.70, 0.62, 0.86 }, window = { 0.62, 0.76, 0.96 } },
}

function Prompt.now()
    if type(getTimestampMs) ~= "function" then return nil end
    return getTimestampMs()
end

function Prompt.note(shell, text, kind, uid)
    if not ProjectALife.TalkUi.startButton() then return false end
    if kind == "ambient" or type(text) ~= "string" then return false end
    if string.find(text, "%?[\"')]*%s*$") == nil then return false end
    if uid == nil or tostring(uid) == "" then uid = ProjectALife.Speech.variable(shell, "ALifeUID") end
    if uid == nil or tostring(uid) == "" then return false end
    local now = Prompt.now()
    if now == nil then return false end
    uid = tostring(uid)
    local entry = Prompt.noted[uid]
    if entry == nil then
        if #Prompt.noteOrder >= Prompt.settings.noteCap then
            local oldest = table.remove(Prompt.noteOrder, 1)
            Prompt.noted[oldest] = nil
        end
        entry = {}
        Prompt.noted[uid] = entry
        Prompt.noteOrder[#Prompt.noteOrder + 1] = uid
    end
    entry.shell, entry.at = shell, now
    return true
end

function Prompt.forget(uid)
    uid = tostring(uid)
    Prompt.noted[uid] = nil
    for index = #Prompt.noteOrder, 1, -1 do
        if Prompt.noteOrder[index] == uid then table.remove(Prompt.noteOrder, index) end
    end
end

function Prompt.playerOk(player)
    if player == nil then return false end
    if type(player.isDead) == "function" and player:isDead() then return false end
    if type(player.isAsleep) == "function" and player:isAsleep() then return false end
    return true
end

function Prompt.windowOpen()
    local menu = ProjectALife.TalkMenu
    local window = menu ~= nil and menu.instance or nil
    return window ~= nil and type(window.isVisible) == "function" and window:isVisible() == true
end

function Prompt.near(player, shell)
    local speech = ProjectALife.Speech
    local px, py, pz = speech.pointOf(player)
    local sx, sy, sz = speech.pointOf(shell)
    if px == nil or sx == nil or math.floor(pz) ~= math.floor(sz) then return false end
    if (px - sx) ^ 2 + (py - sy) ^ 2 > Prompt.settings.reachSq then return false end
    return speech.sees(player, shell) == true
end

function Prompt.hostileHint(record, player)
    local memory = type(record) == "table" and record.memory or nil
    if type(memory) ~= "table" then return false end
    if record.stance == "hostile" or memory.surrender ~= nil or memory.robbery ~= nil then return true end
    local key = ProjectALife.Speech.playerKey(player)
    local hostile = memory.hostileToPlayerKeys
    return key ~= nil and type(hostile) == "table" and hostile[key] == true
end

function Prompt.fromQuestion(player, now)
    local menu, speech = ProjectALife.TalkMenu, ProjectALife.Speech
    for index = #Prompt.noteOrder, 1, -1 do
        local uid = Prompt.noteOrder[index]
        local entry = Prompt.noted[uid]
        if entry == nil or now - entry.at > Prompt.settings.questionMs or speech.alive(entry.shell) ~= true then
            Prompt.forget(uid)
        else
            local record = menu.recordFor(uid)
            if record ~= nil and menu.canTalk(entry.shell, record) and not Prompt.hostileHint(record, player)
                    and Prompt.near(player, entry.shell) then
                return { kind = "question", uid = uid, shell = entry.shell, record = record }
            end
        end
    end
    return nil
end

function Prompt.shellOf(uid, now)
    local at = Prompt.findAt[uid]
    if at ~= nil and now - at < Prompt.settings.findMs then return Prompt.found[uid] end
    Prompt.findAt[uid] = now
    Prompt.found[uid] = ProjectALife.Speech.findShell(uid)
    return Prompt.found[uid]
end

function Prompt.guestInside(record, pendingId)
    local memory = type(record) == "table" and type(record.memory) == "table" and record.memory or nil
    local guest = memory ~= nil and memory.guest or nil
    return type(guest) == "table" and guest.pendingId == pendingId
end

function Prompt.admitted(saved, record, now)
    if saved.admitted == true then return true end
    if Prompt.guestInside(record, saved.pendingId) then return true end
    local inside = false
    local door = saved.door
    if type(door) == "table" and tonumber(door.x1) ~= nil and tonumber(door.x2) ~= nil
            and tonumber(door.y1) ~= nil and tonumber(door.y2) ~= nil then
        local shell = Prompt.shellOf(saved.uid, now)
        local x, y = nil, nil
        if shell ~= nil then x, y = ProjectALife.Speech.pointOf(shell) end
        if x ~= nil and y ~= nil and x >= door.x1 and x < door.x2 and y >= door.y1 and y < door.y2
                and (x - (tonumber(door.sx) or 0) - 0.5) ^ 2 + (y - (tonumber(door.sy) or 0) - 0.5) ^ 2 > Prompt.settings.stoopSq then
            inside = true
        end
    end
    if inside then saved.admitted = true end
    return inside
end

function Prompt.fromVisit(num, player, now)
    local client, menu = ProjectALife.SafehouseClient, ProjectALife.TalkMenu
    if client == nil or type(client.doorVisit) ~= "function" or type(client.knocks) ~= "table" then return nil end
    if client.knocks[num] == nil then return nil end
    local saved = client.doorVisit(num)
    local savedRecord = saved ~= nil and menu.recordFor(saved.uid) or nil
    local leaving = savedRecord ~= nil and type(savedRecord.memory) == "table"
        and type(savedRecord.memory.visit) == "table" and savedRecord.memory.visit.leaving == true
    if leaving then return nil end
    if saved ~= nil and not Prompt.admitted(saved, menu.recordFor(saved.uid), now) then
        local kind = "door"
        if type(saved.door) == "table" and saved.door.kind == "window" then kind = "window" end
        return { kind = kind, uid = saved.uid, saved = saved, x = saved.door.ix + 0.5, y = saved.door.iy + 0.5, z = saved.door.z }
    end
    local knock = client.knocks[num]
    local record = menu.recordFor(knock.uid)
    local stamp = ProjectALife.TalkUi.visitStamp(record)
    if stamp == nil or stamp.pendingId ~= knock.pendingId then return nil end
    local shell = Prompt.shellOf(knock.uid, now)
    if shell ~= nil and menu.canTalk(shell, record) and Prompt.near(player, shell) then
        local kind = (knock.admitted == true or Prompt.guestInside(record, knock.pendingId)) and "guest" or "visitor"
        return { kind = kind, uid = knock.uid, shell = shell, record = record }
    end
    return nil
end

function Prompt.fromOrder(player, now)
    local menu, speech = ProjectALife.TalkMenu, ProjectALife.Speech
    for uid, entry in pairs(speech.orders) do
        if now > entry.untilMs then
            speech.orders[uid] = nil
        else
            local shell = Prompt.shellOf(uid, now)
            local record = shell ~= nil and menu.recordFor(uid) or nil
            if record ~= nil and menu.canTalk(shell, record) and speech.orderRule(entry, player, shell, now) then
                return { kind = "question", uid = uid, shell = shell, record = record, order = true }
            end
        end
    end
    return nil
end

function Prompt.onOrder(args)
    return ProjectALife.Speech.orderNote(args, Prompt.now())
end

function Prompt.onServerCommand(module, command, args)
    if module == "ProjectALife" and command == "talkOrder" then Prompt.onOrder(args) end
end

function Prompt.choose(num, player, now)
    return Prompt.fromQuestion(player, now) or Prompt.fromOrder(player, now) or Prompt.fromVisit(num, player, now)
end

function Prompt.labelFor(candidate, player)
    local name = ProjectALife.SpeechBubbles.nameFor(candidate.uid, player)
    if candidate.kind == "question" then return ProjectALife.Text.ui("Answer {name}", { name = name }), name end
    if candidate.kind == "door" then return ProjectALife.Text.ui("Talk to {name} at the door", { name = name }), name end
    if candidate.kind == "window" then return ProjectALife.Text.ui("Talk to {name} at the window", { name = name }), name end
    return ProjectALife.Text.ui("Talk to {name}", { name = name }), name
end

function Prompt.tipFor(candidate)
    if candidate.kind == "question" then return ProjectALife.Text.ui("Click to answer. Right-clicking them works too.") end
    return ProjectALife.Text.ui("Click to start the conversation. Right-clicking works too.")
end

function Prompt.screenRect(num)
    local bubbles = ProjectALife.SpeechBubbles
    return bubbles.screenRect(num)
end

function Prompt.place(button)
    local slot = button.slot
    local x, y, z = slot.x, slot.y, slot.z
    local shell = slot.shell
    if shell ~= nil and type(shell.getX) == "function" and type(shell.getY) == "function" and type(shell.getZ) == "function" then
        x, y, z = shell:getX(), shell:getY(), shell:getZ()
    end
    local s = Prompt.settings
    local left, top, width, height = Prompt.screenRect(slot.num)
    if left == nil then return end
    local m = slot.m
    local drop, margin = s.gap, s.margin
    if m ~= nil and Prompt.plain ~= true then
        drop = m.below
        if m.tail + 2 > margin then margin = m.tail + 2 end
    end
    local ax, ay, bx, by
    if type(isoToScreenX) == "function" and type(isoToScreenY) == "function" and type(x) == "number" and type(y) == "number" then
        ax = isoToScreenX(slot.num, x, y, z or 0)
        ay = isoToScreenY(slot.num, x, y, z or 0)
        bx = ax - button.width / 2
        by = ay + drop
    else
        bx = left + (width - button.width) / 2
        by = top + height - s.fallbackRise
    end
    local low, high = left + margin, left + width - button.width - margin
    if high < low then high = low end
    if bx < low then bx = low elseif bx > high then bx = high end
    low, high = top + margin, top + height - button.height - margin
    if high < low then high = low end
    if by < low then by = low elseif by > high then by = high end
    local fx, fy = math.floor(bx), math.floor(by)
    button:setX(fx)
    button:setY(fy)
    Prompt.aim(button, ax, ay, fx, fy)
end

function Prompt.aim(button, ax, ay, bx, by)
    button.arrow = 0
    local m = button.slot.m
    if ax == nil or ay == nil or m == nil then return end
    local w, h = button.width, button.height
    if ax >= bx and ax <= bx + w and ay >= by and ay <= by + h then return end
    local dx, dy = ax - (bx + w / 2), ay - (by + h / 2)
    local edge = m.radius + m.tail
    local at
    if math.abs(dx) * h > math.abs(dy) * w then
        if dx < 0 then button.arrow = 3 else button.arrow = 4 end
        at = ay - by
        if at > h - edge then at = h - edge end
        if at < edge then at = edge end
    else
        if dy < 0 then button.arrow = 1 else button.arrow = 2 end
        at = ax - bx
        if at > w - edge then at = w - edge end
        if at < edge then at = edge end
    end
    button.arrowAt = at
end

function Prompt.step(slot, now)
    local look = Prompt.look
    local dt = now - (slot.stepAt or now)
    slot.stepAt = now
    if dt < 0 then dt = 0 end
    if slot.target == 1 then
        slot.alpha = slot.alpha + dt / look.fadeInMs
        if slot.alpha > 1 then slot.alpha = 1 end
    else
        slot.alpha = slot.alpha - dt / look.fadeOutMs
        if slot.alpha <= 0 then
            slot.alpha = 0
            slot.button:setVisible(false)
        end
    end
end

function Prompt.aiming(num)
    local player = getSpecificPlayer(num)
    return player ~= nil and type(player.isAiming) == "function" and player:isAiming() == true
end

function Prompt.interactive(button)
    return not Prompt.aiming(button.slot.num)
end

function Prompt.frame(button)
    local slot = button.slot
    Prompt.step(slot, Prompt.now() or 0)
    slot.passive = not Prompt.interactive(button)
    if slot.passive then
        if button.pressed == true then button.pressed = false end
        if type(button.tooltipUI) == "table" and button.tooltipUI:getIsVisible() then
            button.tooltipUI:setVisible(false)
            button.tooltipUI:removeFromUIManager()
        end
    elseif type(button.updateTooltip) == "function" then
        button:updateTooltip()
    end
end

function Prompt.buttonClass()
    if Prompt.class ~= nil then return Prompt.class end
    if ISButton == nil or type(ISButton.derive) ~= "function" then return nil end
    local class = ISButton:derive("ALifeTalkPromptButton")
    function class:prerender()
        local ok, err = pcall(Prompt.place, self)
        if not ok then Prompt.fault(err) end
        if Prompt.plain == true then
            ISButton.prerender(self)
            return
        end
        ok, err = pcall(Prompt.frame, self)
        if not ok then Prompt.fault(err) end
    end
    function class:onMouseDown(x, y)
        if not Prompt.interactive(self) then return false end
        ISButton.onMouseDown(self, x, y)
        return true
    end
    function class:onMouseUp(x, y)
        local was = self.pressed == true
        if not Prompt.interactive(self) then
            self.pressed = false
            return false
        end
        ISButton.onMouseUp(self, x, y)
        return was
    end
    function class:onRightMouseDown(x, y)
        return false
    end
    function class:onRightMouseUp(x, y)
        return false
    end
    function class:render()
        if Prompt.plain == true then
            ISButton.render(self)
            return
        end
        local ok, err = pcall(Prompt.paint, self)
        if not ok then Prompt.styleFault(err) end
    end
    Prompt.class = class
    return class
end

function Prompt.slotFor(num)
    local slot = Prompt.slots[num]
    if slot ~= nil and slot.button.removed ~= true then return slot end
    local class = Prompt.buttonClass()
    if class == nil or UIFont == nil then return nil end
    slot = { num = num, alpha = 0, target = 0 }
    local button = class:new(0, 0, 200, Prompt.settings.height, "", slot, Prompt.click)
    button:initialise()
    button.slot = slot
    button.font = UIFont.Small
    if type(button.setWantMouseEvents) == "function" then button:setWantMouseEvents(false) end
    if type(button.enableAcceptColor) == "function" then button:enableAcceptColor() end
    button:addToUIManager()
    button:setVisible(false)
    slot.button = button
    Prompt.slots[num] = slot
    return slot
end

function Prompt.measure(label)
    local manager = getTextManager()
    return manager:MeasureStringX(UIFont.Small, label) + Prompt.settings.pad * 2
end

function Prompt.px(value, factor)
    return math.max(1, math.floor(value * factor + 0.5))
end

function Prompt.tagOf(candidate)
    if candidate.kind == "door" then return ProjectALife.Text.ui("Door"), "door" end
    if candidate.kind == "window" then return ProjectALife.Text.ui("Window"), "window" end
    return nil, nil
end

function Prompt.layout(slot, label, name, tag, tagKind)
    local look = Prompt.look
    local manager = getTextManager()
    local font = UIFont.Small
    local fh = manager:getFontHeight(font)
    local factor = fh / 14
    if fh < 8 then factor = 1 end
    local px = Prompt.px
    local m = slot.m
    if m == nil then
        m = {}
        slot.m = m
    end
    m.fh = fh
    m.padX, m.gap, m.accentW = px(look.padX, factor), px(look.gap, factor), px(look.accentW, factor)
    m.radius = math.max(3, px(look.radius, factor))
    m.tail, m.below, m.rise = px(look.tail, factor), px(look.below, factor), px(look.rise, factor)
    m.h = fh + px(look.padY, factor) * 2
    m.textY = math.floor((m.h - fh) / 2)
    m.bs = m.h - px(5, factor) * 2
    m.mw = 2 * math.floor(m.bs / 5) + 1
    m.mh = math.floor(m.bs * 0.8)
    m.btn = math.floor(m.mh * 0.42)
    m.pre, m.nm, m.post = label, "", ""
    m.preW, m.nmW = 0, 0
    if type(name) == "string" and name ~= "" then
        local first, last = string.find(label, name, 1, true)
        if first ~= nil then
            m.pre, m.nm, m.post = string.sub(label, 1, first - 1), name, string.sub(label, last + 1)
            m.preW = manager:MeasureStringX(font, m.pre)
            m.nmW = manager:MeasureStringX(font, m.pre .. name) - m.preW
        end
    end
    m.labelW = manager:MeasureStringX(font, label)
    m.tag, m.tagKind, m.tagW, m.pillH, m.glyphW = tag, tagKind, 0, 0, 0
    local width = 2 + m.accentW + m.padX + m.bs + m.gap + m.labelW + m.padX
    if tag ~= nil then
        m.pillH = fh + 2
        m.glyphW = px(6, factor) + px(4, factor)
        m.tagW = manager:MeasureStringX(font, tag) + px(look.pillPad, factor) * 2 + m.glyphW
        m.pillPad = px(look.pillPad, factor)
        width = width + m.gap + m.tagW
    end
    m.w = width
    return m
end

function Prompt.fit(slot, label, name, tag, tagKind)
    local button = slot.button
    if Prompt.plain == true then
        button:setHeight(Prompt.settings.height)
        button:setWidth(Prompt.measure(label))
        local color = button.backgroundColor
        if type(color) == "table" then color.a = 0.9 * ProjectALife.TalkUi.opacity() end
        return
    end
    local m = Prompt.layout(slot, label, name, tag, tagKind)
    button:setWidth(m.w)
    button:setHeight(m.h)
end

function Prompt.tint(slot, candidate, player)
    local look = Prompt.look
    local menu = ProjectALife.TalkMenu
    local record = candidate.record
    if record == nil and menu ~= nil and type(menu.recordFor) == "function" then record = menu.recordFor(candidate.uid) end
    local color = look.calm
    if Prompt.hostileHint(record, player) then
        color = look.stances.hostile
    elseif type(record) == "table" and menu ~= nil and type(menu.mystery) == "function" and menu.mystery() ~= true then
        local pick = look.stances[record.stance or ""]
        if pick ~= nil then color = pick end
    end
    slot.ar, slot.ag, slot.ab = color[1], color[2], color[3]
    slot.nr, slot.ng, slot.nb = ProjectALife.SpeechBubbles.colorOf(nil, candidate.uid)
end

function Prompt.release(slot, now, hard)
    if slot.target == 0 then return end
    if hard ~= true then
        if slot.lostAt == nil then slot.lostAt = now end
        if now - slot.lostAt < Prompt.look.holdMs then return end
    end
    slot.target, slot.candidate, slot.lostAt = 0, nil, nil
    Prompt.step(slot, now)
end

function Prompt.apply(num, player, candidate, now, hard)
    local slot = Prompt.slots[num]
    if now == nil then now = Prompt.now() or 0 end
    if candidate == nil then
        if slot ~= nil and slot.button:isVisible() then Prompt.release(slot, now, hard) end
        return false
    end
    slot = Prompt.slotFor(num)
    if slot == nil then return false end
    local button = slot.button
    local label, name = Prompt.labelFor(candidate, player)
    if slot.label ~= label or slot.kind ~= candidate.kind then
        slot.label, slot.kind = label, candidate.kind
        button:setTitle(label)
        button.tooltip = Prompt.tipFor(candidate)
        local tag, tagKind = Prompt.tagOf(candidate)
        Prompt.fit(slot, label, name, tag, tagKind)
    end
    Prompt.tint(slot, candidate, player)
    slot.candidate, slot.shell = candidate, candidate.shell
    slot.x, slot.y, slot.z = candidate.x, candidate.y, candidate.z
    slot.target, slot.lostAt = 1, nil
    if not button:isVisible() then
        slot.alpha, slot.stepAt = 0, now
        button:setVisible(true)
        button:bringToTop()
        Prompt.metrics.shown = Prompt.metrics.shown + 1
    end
    Prompt.step(slot, now)
    return true
end

function Prompt.tri(button, cx, cy, ux, uy, half, length, alpha, r, g, b)
    local vx, vy = -uy, ux
    ProjectALife.SpeechBubbles.fillTriangle(button, cx - vx * half, cy - vy * half, cx + vx * half, cy + vy * half,
        cx + ux * length, cy + uy * length, alpha, r, g, b, false)
end

function Prompt.paintTail(button, m, oy, alpha, er, eg, eb, fr, fg, fb)
    local arrow, at, t = button.arrow, button.arrowAt, m.tail
    local cx, cy, ux, uy
    if arrow == 1 then
        cx, cy, ux, uy = at, oy + 1, 0, -1
    elseif arrow == 2 then
        cx, cy, ux, uy = at, oy + button.height - 1, 0, 1
    elseif arrow == 3 then
        cx, cy, ux, uy = 1, oy + at, -1, 0
    else
        cx, cy, ux, uy = button.width - 1, oy + at, 1, 0
    end
    Prompt.tri(button, cx, cy, ux, uy, t, t + 1, alpha, er, eg, eb)
    Prompt.tri(button, cx, cy, ux, uy, t - 2, t - 1, 0.96 * alpha, fr, fg, fb)
end

function Prompt.paintMouse(button, m, x, y, a, lit, ar, ag, ab)
    local gx = x + math.floor((m.bs - m.mw) / 2)
    local gy = y + math.floor((m.bs - m.mh) / 2)
    local half = math.floor(m.mw / 2)
    local w, h = m.mw, m.mh
    button:drawRect(gx + 1, gy + 1, half - 1, m.btn, a * lit, ar, ag, ab)
    button:drawRect(gx + half + 1, gy + 1, w - 2 - half, m.btn, a * 0.18, 0.93, 0.93, 0.93)
    button:drawRect(gx + 1, gy, w - 2, 1, a * 0.95, 0.93, 0.93, 0.93)
    button:drawRect(gx + 1, gy + h - 1, w - 2, 1, a * 0.95, 0.93, 0.93, 0.93)
    button:drawRect(gx, gy + 1, 1, h - 2, a * 0.95, 0.93, 0.93, 0.93)
    button:drawRect(gx + w - 1, gy + 1, 1, h - 2, a * 0.95, 0.93, 0.93, 0.93)
    button:drawRect(gx + half, gy + 1, 1, m.btn, a * 0.8, 0.93, 0.93, 0.93)
    button:drawRect(gx + 1, gy + 1 + m.btn, w - 2, 1, a * 0.8, 0.93, 0.93, 0.93)
end

function Prompt.paintGlyph(button, m, x, py, a, r, g, b)
    local size = m.glyphW - math.floor(m.glyphW * 0.4)
    if m.tagKind == "door" then
        local y = py + math.floor((m.pillH - size - 3) / 2)
        button:drawRect(x + 1, y + 1, size - 2, size + 1, a * 0.22, r, g, b)
        button:drawRectBorder(x, y, size, size + 3, a * 0.95, r, g, b)
        button:drawRect(x + size - 3, y + math.floor((size + 3) / 2), 1, 1, a, r, g, b)
    else
        local y = py + math.floor((m.pillH - size - 1) / 2)
        button:drawRect(x + 1, y + 1, size - 1, size - 1, a * 0.22, r, g, b)
        button:drawRectBorder(x, y, size + 1, size + 1, a * 0.95, r, g, b)
        button:drawRect(x + math.floor((size + 1) / 2), y + 1, 1, size - 1, a * 0.85, r, g, b)
        button:drawRect(x + 1, y + math.floor((size + 1) / 2), size - 1, 1, a * 0.85, r, g, b)
    end
end

function Prompt.paintPill(button, m, oy, a, shade)
    local chip = Prompt.look.chips[m.tagKind]
    if chip == nil then return end
    local bubbles = ProjectALife.SpeechBubbles
    local px = button.width - m.padX - m.tagW
    local py = oy + math.floor((button.height - m.pillH) / 2)
    bubbles.roundFill(button, px, py, m.tagW, m.pillH, 3, a * 0.2 * shade, chip[1], chip[2], chip[3])
    bubbles.roundBorder(button, px, py, m.tagW, m.pillH, 3, a * 0.6 * shade, chip[1], chip[2], chip[3])
    Prompt.paintGlyph(button, m, px + m.pillPad, py, a, chip[1], chip[2], chip[3])
    button:drawText(m.tag, px + m.pillPad + m.glyphW, py + 1, chip[1], chip[2], chip[3], a, UIFont.Small)
end

function Prompt.paint(button)
    local slot = button.slot
    local m, p = slot.m, slot.alpha
    if m == nil or p == nil or p <= 0.01 then return end
    local look, bubbles = Prompt.look, ProjectALife.SpeechBubbles
    local shade = ProjectALife.TalkUi.opacity()
    local a = p * (2 - p)
    if slot.passive == true then a = a * 0.45 end
    local hot, down = button.mouseOver == true, button.pressed == true
    if slot.passive == true then hot, down = false, false end
    local w, h = button.width, button.height
    local oy = math.floor((1 - a) * m.rise + 0.5)
    local ar, ag, ab = slot.ar, slot.ag, slot.ab
    local fr, fg, fb = look.fill[1], look.fill[2], look.fill[3]
    local er = look.edge[1] + (ar - look.edge[1]) * 0.55
    local eg = look.edge[2] + (ag - look.edge[2]) * 0.55
    local eb = look.edge[3] + (ab - look.edge[3]) * 0.55
    local borderA = look.borderAlpha
    local lit, textLift = 0.7, 0
    if down then
        fr, fg, fb = fr * 0.6 + ar * 0.1, fg * 0.6 + ag * 0.1, fb * 0.6 + ab * 0.1
        er, eg, eb, borderA, lit, textLift = ar, ag, ab, 0.95, 1, 1
    elseif hot then
        fr, fg, fb = fr + (ar - fr) * 0.18, fg + (ag - fg) * 0.18, fb + (ab - fb) * 0.18
        er, eg, eb, borderA, lit = ar, ag, ab, 0.95, 0.95
    else
        local now = Prompt.now() or 0
        borderA = borderA * (0.86 + 0.14 * math.sin((now % look.pulseMs) * 6.2832 / look.pulseMs))
    end
    bubbles.roundFill(button, 0, oy, w, h, m.radius, a * look.fillAlpha * shade, fr, fg, fb)
    bubbles.roundBorder(button, 0, oy, w, h, m.radius, a * borderA * shade, er, eg, eb)
    if button.arrow ~= 0 then Prompt.paintTail(button, m, oy, a * shade, er, eg, eb, fr, fg, fb) end
    button:drawRect(2, oy + m.radius, m.accentW, h - 2 * m.radius, a * 0.9, slot.nr, slot.ng, slot.nb)
    local x = 2 + m.accentW + m.padX
    local badgeY = oy + math.floor((h - m.bs) / 2)
    local badgeFill = 0.2
    if hot or down then badgeFill = 0.34 end
    bubbles.roundFill(button, x, badgeY, m.bs, m.bs, 3, a * badgeFill, ar, ag, ab)
    bubbles.roundBorder(button, x, badgeY, m.bs, m.bs, 3, a * 0.75, ar, ag, ab)
    Prompt.paintMouse(button, m, x, badgeY, a, lit, ar, ag, ab)
    local tx, ty = x + m.bs + m.gap, oy + m.textY + textLift
    local tr, tg, tb = look.text[1], look.text[2], look.text[3]
    if hot or down then tr, tg, tb = 0.9, 0.93, 0.95 end
    local font = UIFont.Small
    if m.pre ~= "" then button:drawText(m.pre, tx, ty, tr, tg, tb, a, font) end
    if m.nm ~= "" then button:drawText(m.nm, tx + m.preW, ty, look.name[1], look.name[2], look.name[3], a, font) end
    if m.post ~= "" then button:drawText(m.post, tx + m.preW + m.nmW, ty, tr, tg, tb, a, font) end
    if m.tag ~= nil then Prompt.paintPill(button, m, oy, a, shade) end
end

function Prompt.styleFault(err)
    if Prompt.plain == true then return end
    Prompt.plain = true
    print("[ALIFE-UI] talk prompt style fell back to the plain button: " .. tostring(err))
    for num = 0, 3 do
        local slot = Prompt.slots[num]
        if slot ~= nil and slot.label ~= nil then Prompt.fit(slot, slot.label, nil, nil, nil) end
    end
end

function Prompt.refuse(num, reason)
    Prompt.metrics.refused = Prompt.metrics.refused + 1
    print("[ALIFE-UI] talk prompt refused reason=" .. tostring(reason))
    local menu = ProjectALife.TalkMenu
    local player = getSpecificPlayer(num)
    local message = ProjectALife.Text.ui(menu.refusalText(reason) or menu.messages.fallback)
    if player ~= nil and HaloTextHelper ~= nil and type(HaloTextHelper.addText) == "function" then
        HaloTextHelper.addText(player, message)
    end
    return false
end

function Prompt.open(num, candidate)
    local menu, client = ProjectALife.TalkMenu, ProjectALife.SafehouseClient
    if candidate.kind == "door" or candidate.kind == "window" then
        local saved = client.doorVisit(num)
        if saved == nil or saved.uid ~= candidate.uid then return Prompt.refuse(num, "not_door_peer") end
        if client.openDoor(num, saved, "DOOR_WHO") == false then return Prompt.refuse(num, "fallback") end
        return true
    end
    local record = menu.recordFor(candidate.uid)
    if record == nil or not menu.canTalk(candidate.shell, record) then return Prompt.refuse(num, "unavailable") end
    local player = getSpecificPlayer(num)
    local key = type(ProjectALife.Speech.playerKey) == "function" and ProjectALife.Speech.playerKey(player) or nil
    local _, name, faction, role, known = menu.describe(record, key, 1)
    menu.open(num, candidate.uid, candidate.shell, name, faction, role, known)
    return true
end

function Prompt.click(slot, button)
    Prompt.metrics.clicks = Prompt.metrics.clicks + 1
    local candidate = slot.candidate
    if candidate == nil then return end
    slot.button:setVisible(false)
    slot.candidate = nil
    local ok, result = pcall(Prompt.open, slot.num, candidate)
    if not ok then
        Prompt.fault(result)
        Prompt.refuse(slot.num, "fallback")
    elseif result == true then
        Prompt.metrics.opened = Prompt.metrics.opened + 1
        if candidate.kind == "question" then Prompt.forget(candidate.uid) end
    end
end

function Prompt.scan(now)
    local enabled = ProjectALife.TalkUi.startButton()
    local busy = Prompt.windowOpen()
    if busy then Prompt.quietUntil = now + Prompt.settings.afterMs end
    local client = ProjectALife.SafehouseClient
    for num = 0, 3 do
        local player = getSpecificPlayer(num)
        local candidate = nil
        local hard = true
        if enabled and not busy and now >= Prompt.quietUntil and Prompt.playerOk(player) then
            hard = false
            local knocks = client ~= nil and type(client.knocks) == "table" and client.knocks[num] or nil
            if #Prompt.noteOrder > 0 or knocks ~= nil or ProjectALife.Speech.orderLive(now) then
                candidate = Prompt.choose(num, player, now)
            end
        end
        if candidate ~= nil or Prompt.slots[num] ~= nil then Prompt.apply(num, player, candidate, now, hard) end
    end
end

function Prompt.onTick()
    if Prompt.failed ~= nil then return end
    local now = Prompt.now()
    if now == nil or now < Prompt.nextAt then return end
    Prompt.nextAt = now + Prompt.settings.scanMs
    local ok, err = pcall(Prompt.scan, now)
    if not ok then Prompt.fault(err) end
end

function Prompt.fault(err)
    Prompt.faults = Prompt.faults + 1
    Prompt.metrics.faults = Prompt.faults
    if Prompt.faults >= 3 and Prompt.failed == nil then
        Prompt.failed = tostring(err)
        print("[ALIFE-UI] talk prompt off for this session: " .. Prompt.failed)
        for num = 0, 3 do
            local slot = Prompt.slots[num]
            if slot ~= nil then slot.button:setVisible(false) end
        end
    end
end

function Prompt.qaLine()
    local m = Prompt.metrics
    local state = "on"
    if Prompt.failed ~= nil then state = "failed" elseif not ProjectALife.TalkUi.startButton() then state = "off"
    elseif Prompt.plain == true then state = "plain" end
    return "[ALIFE-QA] TalkPrompt: shown=" .. tostring(m.shown) .. " clicks=" .. tostring(m.clicks) .. " opened=" .. tostring(m.opened)
        .. " refused=" .. tostring(m.refused) .. " faults=" .. tostring(m.faults) .. " state=" .. state
end

function Prompt.reset()
    for num = 0, 3 do
        local slot = Prompt.slots[num]
        if slot ~= nil then
            if type(slot.button.removeFromUIManager) == "function" then pcall(slot.button.removeFromUIManager, slot.button) end
            slot.button.removed = true
        end
    end
    Prompt.noted, Prompt.noteOrder, Prompt.slots, Prompt.findAt, Prompt.found = {}, {}, {}, {}, {}
    ProjectALife.Speech.orders = {}
    Prompt.failed, Prompt.faults, Prompt.nextAt, Prompt.quietUntil = nil, 0, 0, 0
    Prompt.plain = nil
    Prompt.metrics = { shown = 0, clicks = 0, opened = 0, refused = 0, faults = 0 }
end

if type(Events) == "table" then
    if Events.OnTick ~= nil and type(Events.OnTick.Add) == "function" then Events.OnTick.Add(Prompt.onTick) end
    if Events.OnServerCommand ~= nil and type(Events.OnServerCommand.Add) == "function" then
        Events.OnServerCommand.Add(Prompt.onServerCommand)
    end
    if Events.OnGameStart ~= nil and type(Events.OnGameStart.Add) == "function" then Events.OnGameStart.Add(Prompt.reset) end
end

return Prompt
