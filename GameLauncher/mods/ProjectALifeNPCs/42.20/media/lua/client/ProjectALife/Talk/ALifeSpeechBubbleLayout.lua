ProjectALife = ProjectALife or {}

local Layout = {
    HIDDEN = 0,
    HEAD = 1,
    PIN = 2,
    sample = "The quick brown fox jumps over the",
    insetCache = {},
    settings = {
        maxLive = 3,
        maxTotal = 6,
        fadeMs = 150,
        holdBaseMs = 1400,
        holdPerCharMs = 60,
        holdMinMs = 2400,
        holdMaxMs = 9000,
        maxPageLines = 4,
        radius = 4,
        padX = 8,
        padY = 5,
        tail = 10,
        tailHalf = 5,
        edgePad = 10,
        arrow = 14,
        arrowGap = 3,
        stackGap = 4,
        lineGap = 1,
        nameGap = 3,
        headRise = 0.66,
        losMs = 250,
        aliveMs = 150,
        duplicateMs = 400,
        occludedAlpha = 0.55,
        ambientAlpha = 0.75,
    },
}
ProjectALife.SpeechBubbleLayout = Layout

function Layout.clamp(value, low, high)
    if high < low then return low end
    if value < low then return low end
    if value > high then return high end
    return value
end

function Layout.px(value, factor)
    return math.max(1, math.floor(value * factor + 0.5))
end

function Layout.scale(entry, unit)
    unit = tonumber(unit)
    if unit == nil or unit ~= unit or unit < 8 then unit = 14 end
    local factor = unit / 14
    local s = Layout.settings
    entry.factor = factor
    entry.padX = Layout.px(s.padX, factor)
    entry.padY = Layout.px(s.padY, factor)
    entry.radius = math.max(3, Layout.px(s.radius, factor))
    entry.tail = Layout.px(s.tail, factor)
    entry.tailHalf = Layout.px(s.tailHalf, factor)
    entry.pad = Layout.px(s.edgePad, factor)
    entry.arrow = Layout.px(s.arrow, factor)
    entry.arrowGap = Layout.px(s.arrowGap, factor)
    entry.stackGap = Layout.px(s.stackGap, factor)
    return entry
end

function Layout.words(text)
    local list, at = {}, 1
    if type(text) ~= "string" then return list end
    while true do
        local first, last = string.find(text, "%S+", at)
        if first == nil then break end
        list[#list + 1] = string.sub(text, first, last)
        at = last + 1
    end
    return list
end

function Layout.fitPrefix(word, maxWidth, measure)
    local fit = 1
    for count = 2, #word do
        if measure(string.sub(word, 1, count)) > maxWidth then break end
        fit = count
    end
    return fit
end

function Layout.wrap(text, maxWidth, measure)
    local lines, current = {}, ""
    local words = Layout.words(text)
    for index = 1, #words do
        local word = words[index]
        while #word > 1 and measure(word) > maxWidth do
            local cut = Layout.fitPrefix(word, maxWidth, measure)
            if current ~= "" then
                lines[#lines + 1] = current
                current = ""
            end
            lines[#lines + 1] = string.sub(word, 1, cut)
            word = string.sub(word, cut + 1)
        end
        if current == "" then
            current = word
        elseif measure(current .. " " .. word) <= maxWidth then
            current = current .. " " .. word
        else
            lines[#lines + 1] = current
            current = word
        end
    end
    if current ~= "" then lines[#lines + 1] = current end
    return lines
end

function Layout.paginate(lines, perPage)
    local total = #lines
    if total == 0 then return { {} } end
    perPage = math.max(1, math.floor(tonumber(perPage) or 4))
    local pageCount = math.ceil(total / perPage)
    local size = math.ceil(total / pageCount)
    local pages, index = {}, 1
    while index <= total do
        local page = {}
        for offset = 0, size - 1 do
            local line = lines[index + offset]
            if line == nil then break end
            page[#page + 1] = line
        end
        pages[#pages + 1] = page
        index = index + size
    end
    return pages
end

function Layout.holdMs(chars)
    local s = Layout.settings
    local count = math.max(0, tonumber(chars) or 0)
    local ms = s.holdBaseMs + count * s.holdPerCharMs
    return math.floor(math.max(s.holdMinMs, math.min(s.holdMaxMs, ms)))
end

function Layout.fade(now, startMs, endMs)
    local fade = Layout.settings.fadeMs
    local age, left = now - startMs, endMs - now
    if age < 0 or left <= 0 then return 0 end
    local alpha = 1
    if age < fade then alpha = age / fade end
    if left < fade and left / fade < alpha then alpha = left / fade end
    return alpha
end

function Layout.pageAt(pageMs, count, elapsed)
    local index, spent = 1, 0
    while index < count do
        spent = spent + pageMs[index]
        if elapsed < spent then break end
        index = index + 1
    end
    return index
end

function Layout.insets(radius)
    local cached = Layout.insetCache[radius]
    if cached ~= nil then return cached end
    local list = {}
    for row = 0, radius - 1 do
        local reach = radius - row - 0.5
        list[row + 1] = math.floor(radius - math.sqrt(radius * radius - reach * reach) + 0.5)
    end
    Layout.insetCache[radius] = list
    return list
end

function Layout.overlap(a, b, gap)
    return a.x < b.x + b.w + gap and b.x < a.x + a.w + gap
        and a.y < b.y + b.h + gap and b.y < a.y + a.h + gap
end

function Layout.onScreen(view, hx, hy, pad)
    return hx >= pad and hx <= view.w - pad and hy >= pad and hy <= view.h - pad
end

function Layout.placeHead(e, view, hx, hy)
    e.w = e.wHead
    local x = Layout.clamp(hx - e.w * 0.5, e.pad, view.w - e.pad - e.w)
    local y = hy - e.tail - e.h
    if y < e.pad then y = e.pad end
    e.x, e.y = x, y
    e.tipX, e.tipY = hx, hy
    e.mode = Layout.HEAD
end

function Layout.finishTail(e)
    local low = e.x + e.radius + e.tailHalf
    local high = e.x + e.w - e.radius - e.tailHalf
    e.baseX = Layout.clamp(e.tipX, low, high)
    if e.y + e.h * 0.5 <= e.tipY then
        e.baseY = e.y + e.h
        e.tailLength = e.tipY - e.baseY
    else
        e.baseY = e.y
        e.tailLength = e.baseY - e.tipY
    end
    e.tailVisible = e.tailLength >= 3
end

function Layout.pin(e, view, tx, ty)
    e.w = e.wPin
    local pad = e.pad
    local cx, cy = view.w * 0.5, view.h * 0.5
    local dx, dy = tx - cx, ty - cy
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.001 then
        dx, dy, length = 0, -1, 1
    end
    dx, dy = dx / length, dy / length
    local left, right, top, bottom = pad, view.w - pad, pad, view.h - pad
    local reach, side = 1e9, "top"
    if dx > 1e-6 then
        local t = (right - cx) / dx
        if t < reach then reach, side = t, "right" end
    elseif dx < -1e-6 then
        local t = (left - cx) / dx
        if t < reach then reach, side = t, "left" end
    end
    if dy > 1e-6 then
        local t = (bottom - cy) / dy
        if t < reach then reach, side = t, "bottom" end
    elseif dy < -1e-6 then
        local t = (top - cy) / dy
        if t < reach then reach, side = t, "top" end
    end
    local px, py = cx + dx * reach, cy + dy * reach
    local w, h, gap = e.w, e.h, e.arrow + e.arrowGap
    local x, y
    if side == "right" then
        x, y = px - gap - w, py - h * 0.5
    elseif side == "left" then
        x, y = px + gap, py - h * 0.5
    elseif side == "bottom" then
        x, y = px - w * 0.5, py - gap - h
    else
        x, y = px - w * 0.5, py + gap
    end
    e.x = Layout.clamp(x, pad, view.w - pad - w)
    e.y = Layout.clamp(y, pad, view.h - pad - h)
    e.arrowX, e.arrowY = px, py
    e.arrowBaseX, e.arrowBaseY = px - dx * e.arrow, py - dy * e.arrow
    e.dirX, e.dirY, e.side = dx, dy, side
    e.mode = Layout.PIN
end

function Layout.blocker(list, upto, e, below)
    local blocked = nil
    for other = 1, upto do
        local o = list[other]
        if Layout.overlap(e, o, e.stackGap) then
            if blocked == nil then
                blocked = o
            elseif below and o.y + o.h > blocked.y + blocked.h then
                blocked = o
            elseif not below and o.y < blocked.y then
                blocked = o
            end
        end
    end
    return blocked
end

function Layout.stack(list, count, view)
    for index = 2, count do
        local e = list[index]
        local natural = e.y
        local settled = false
        for _ = 1, count do
            local blocked = Layout.blocker(list, index - 1, e, false)
            if blocked == nil then
                settled = true
                break
            end
            e.y = blocked.y - e.h - e.stackGap
            if e.y < e.pad then break end
        end
        if not settled then
            e.y = natural
            for _ = 1, count do
                local blocked = Layout.blocker(list, index - 1, e, true)
                if blocked == nil then
                    settled = true
                    break
                end
                e.y = blocked.y + blocked.h + e.stackGap
                if e.y + e.h > view.h - e.pad then break end
            end
        end
        if not settled then e.y = Layout.clamp(natural, e.pad, view.h - e.pad - e.h) end
    end
end

return Layout
