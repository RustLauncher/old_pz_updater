require "ProjectALife/Interface/ALifePeekDoorData"

ProjectALife = ProjectALife or {}

local Data = ProjectALife.PeekData
local Lens = {
    dir = "media/ui/ProjectALife/PeekLens/",
    files = { mask = "lens_mask", grain = "lens_grain", scan = "lens_scan", glow = "lens_glow", out = "lens_out", inn = "lens_in" },
    keys = { "mask", "grain", "scan", "glow", "out", "inn" },
    textures = {},
    failed = {},
    retryMs = 20000,
    width = 480,
    height = 420,
    hole = 0.78,
    horizon = -0.12,
    fullFrac = 0.76,
    fullMinR = 24,
    fullLines = 3,
    fullButtonW = 200,
    blackIris = 0.35,
    openMs = 560,
    closeMs = 220,
    shakeMs = 340,
    kickRange = 2.6,
    tenseRange = 5,
    grainTile = 128,
    shadowCap = 10,
    rimCap = 6,
    rimMin = 16,
    soft = { esc = true, key = true, back = true, moved = true, damage = true, contact = true, door_open = true, door_gone = true,
        floor = true, gone = true },
    metrics = { frames = 0, faults = 0, shakes = 0, fallbacks = 0 },
    gradeKeys = { "tr", "tg", "tb", "fr", "fg", "fb", "wr", "wg", "wb", "wa", "sr", "sg", "sb", "rr", "rg", "rb", "ra",
        "grain", "scan", "glow", "hr", "hg", "hb", "gain" },
    palette = {
        night = { tr = 0.30, tg = 1.0, tb = 0.42, fr = 0.08, fg = 0.26, fb = 0.12, wr = 0.02, wg = 0.16, wb = 0.05, wa = 0.40,
            sr = 0.006, sg = 0.028, sb = 0.010, rr = 0.45, rg = 1.0, rb = 0.55, ra = 0.50, grain = 0.30, scan = 0.20, glow = 0.13,
            hr = 0.45, hg = 0.95, hb = 0.55, gain = 0.64 },
        dusk = { tr = 0.66, tg = 0.76, tb = 0.92, fr = 0.20, fg = 0.25, fb = 0.34, wr = 0.14, wg = 0.18, wb = 0.26, wa = 0.36,
            sr = 0.012, sg = 0.016, sb = 0.030, rr = 0.60, rg = 0.74, rb = 0.95, ra = 0.40, grain = 0.16, scan = 0.10, glow = 0.08,
            hr = 0.72, hg = 0.82, hb = 0.94, gain = 0.80 },
        day = { tr = 1.0, tg = 0.95, tb = 0.86, fr = 0.64, fg = 0.61, fb = 0.56, wr = 0.52, wg = 0.50, wb = 0.46, wa = 0.30,
            sr = 0.020, sg = 0.018, sb = 0.016, rr = 1.0, rg = 0.95, rb = 0.85, ra = 0.22, grain = 0.09, scan = 0.05, glow = 0.06,
            hr = 0.92, hg = 0.89, hb = 0.82, gain = 1.0 },
    },
}
ProjectALife.PeekLens = Lens

function Lens.nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return 0
end

function Lens.smooth(a, b, x)
    local t = Data.clamp((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)
end

function Lens.texture(key)
    local cached = Lens.textures[key]
    if cached ~= nil then return cached end
    local now = Lens.nowMs()
    local failed = Lens.failed[key]
    if failed ~= nil and now - failed < Lens.retryMs then return nil end
    if type(getTexture) ~= "function" or Lens.files[key] == nil then return nil end
    local ok, texture = pcall(getTexture, Lens.dir .. Lens.files[key] .. ".png")
    if ok and texture ~= nil then
        Lens.textures[key] = texture
        Lens.failed[key] = nil
        return texture
    end
    Lens.failed[key] = now
    return nil
end

function Lens.bind()
    local bound = {}
    for index = 1, #Lens.keys do
        local key = Lens.keys[index]
        bound[key] = Lens.texture(key)
    end
    return bound
end

function Lens.view(width, height)
    local view = Data.view(width, height)
    local radius = math.floor(math.min(width, height) / 2) - 4
    view.lens = true
    view.R = radius
    view.rx, view.ry = radius, radius
    view.focal = radius / Data.fovTan
    view.horizon = view.cy + Lens.horizon * radius
    view.sx, view.sy, view.sw, view.sh = view.cx - radius, view.cy - radius, radius * 2, radius * 2
    view.capH = radius * 1.8
    view.footY = view.cy + radius * 0.92
    return view
end

function Lens.fullView(width, height, fontH, barH)
    local view = Data.view(width, height)
    local short = math.min(width, height)
    local pad = math.max(6, math.floor(short * 0.02))
    local base = pad + fontH + 6 + barH + 8
    local lines = Lens.fullLines
    local gap = math.ceil(short * Lens.fullFrac / 2 * 0.08) + 6
    local reserve = base + lines * (fontH + 2) + gap - 8
    local room = math.floor((height - reserve - pad) / 2)
    if room < Lens.fullMinR then
        lines = 0
        reserve = base
        room = math.floor((height - reserve - pad) / 2)
    end
    local radius = math.min(math.floor(short * Lens.fullFrac / 2), room, math.floor(width / 2) - pad)
    radius = math.min(math.max(radius, Lens.fullMinR), math.floor(short / 2))
    radius = math.max(radius, 1)
    local cy = math.min(math.floor(height / 2), height - reserve - radius)
    if cy < radius + pad then cy = radius + pad end
    if cy + radius > height then cy = height - radius end
    view.lens, view.full = true, true
    view.R = radius
    view.cy = cy
    view.rx, view.ry = radius, radius
    view.focal = radius / Data.fovTan
    view.horizon = cy + Lens.horizon * radius
    view.sx, view.sy, view.sw, view.sh = view.cx - radius, cy - radius, radius * 2, radius * 2
    view.capH = radius * 1.8
    view.footY = cy + radius * 0.92
    view.pad = pad
    view.statusLines = lines
    view.statusY = cy + radius + math.ceil(radius * 0.08) + 6
    view.hintY = math.max(0, height - pad - fontH)
    view.btnH = barH
    view.btnY = math.max(0, view.hintY - 6 - barH)
    local rim = math.max(0, math.min(math.ceil(radius * 0.08) + 2, view.btnY - (cy + radius) - 2))
    view.mx, view.my = math.max(0, view.sx - rim), math.max(0, view.sy - rim)
    view.mw = math.min(width, view.sx + view.sw + rim) - view.mx
    view.mh = math.min(height, view.sy + view.sh + rim) - view.my
    return view
end

function Lens.fullRows(view)
    local rows = {}
    local y = view.sy
    local last = view.sy + view.sh
    while y < last do
        local edge = math.abs((y + 0.5 - view.cy) / view.ry)
        local step = 4
        if edge > 0.88 then
            step = 1
        elseif edge > 0.6 then
            step = 2
        end
        if y + step > last then step = last - y end
        local ratio = (y + step / 2 - view.cy) / view.ry
        local half = 0
        if ratio > -1 and ratio < 1 then half = view.rx * math.sqrt(1 - ratio * ratio) end
        rows[#rows + 1] = { y, step, math.max(view.sx, math.floor(view.cx - half)), math.min(view.sx + view.sw, math.ceil(view.cx + half)),
            step == 4 }
        y = y + step
    end
    return rows
end

function Lens.newGrade()
    local grade = { mode = "day", flick = 1 }
    for index = 1, #Lens.gradeKeys do grade[Lens.gradeKeys[index]] = 0 end
    return grade
end

function Lens.weights(light)
    local n = Data.clamp((0.34 - light) / 0.22, 0, 1)
    local d = Data.clamp((light - 0.52) / 0.20, 0, 1)
    return n, 1 - n - d, d
end

function Lens.setGrade(window)
    local grade = window.grade
    if grade == nil then return false end
    local n, u, d = Lens.weights(window.light or 0.6)
    local pn, pu, pd = Lens.palette.night, Lens.palette.dusk, Lens.palette.day
    local keys = Lens.gradeKeys
    for index = 1, #keys do
        local key = keys[index]
        grade[key] = pn[key] * n + pu[key] * u + pd[key] * d
    end
    local gain = grade.gain * (1 - 0.16 * (window.rain or 0))
    local pale = (window.overcast or 0) * 0.4 * (1 - n)
    local mean = (grade.tr + grade.tg + grade.tb) / 3
    grade.tr = (grade.tr + (mean - grade.tr) * pale) * gain
    grade.tg = (grade.tg + (mean - grade.tg) * pale) * gain
    grade.tb = (grade.tb + (mean - grade.tb) * pale) * gain
    grade.mode = "dusk"
    if n >= 0.5 then
        grade.mode = "night"
    elseif d >= 0.5 then
        grade.mode = "day"
    end
    return true
end

function Lens.flicker(now)
    local a = math.sin(now * 0.0211) * math.sin(now * 0.0067 + 1.3)
    local f = 1 - 0.05 * a * a - 0.03 * (0.5 + 0.5 * math.sin(now * 0.131))
    if math.floor(now / 160) % 37 == 0 then f = f * 0.86 end
    return f
end

function Lens.sway(window, now)
    local dx = math.sin(now * 0.00113) * 1.7 + math.sin(now * 0.00047 + 2.0) * 1.2
    local dy = math.sin(now * 0.00091 + 1.0) * 2.0
    local until_ = window.shakeUntil
    if until_ ~= nil and now < until_ then
        local k = (until_ - now) / Lens.shakeMs
        dx = dx + math.sin(now * 0.093) * 4.0 * k
        dy = dy + math.cos(now * 0.117 + 1.0) * 3.0 * k
    end
    return dx, dy
end

function Lens.iris(window, now)
    local o
    if window.fadeAt ~= nil then
        o = 1 - (now - window.fadeAt) / Lens.closeMs
    else
        o = (now - (window.openedAt or now)) / Lens.openMs
    end
    return Data.clamp(o, 0, 1)
end

function Lens.blackout(window, iris)
    if window.full ~= true then return 1 end
    return Lens.smooth(0, Lens.blackIris, iris)
end

function Lens.softClose(reason)
    return Lens.soft[reason] == true
end

function Lens.watch(window, figs, now)
    local near, threat = 99, 99
    for index = 1, #figs do
        local fig = figs[index]
        local dist = fig.dist
        if dist ~= nil and dist < near then near = dist end
        if dist ~= nil and dist < threat and (fig.kind == "zombie" or fig.stance == 3) then threat = dist end
    end
    window.tension = Data.clamp((Lens.tenseRange - threat) / (Lens.tenseRange - 1), 0, 1)
    local previous = window.nearest
    window.nearest = near
    if previous ~= nil and previous > Lens.kickRange and near <= Lens.kickRange then
        window.shakeUntil = now + Lens.shakeMs
        Lens.metrics.shakes = Lens.metrics.shakes + 1
    end
end

function Lens.countRect(window, x, y, w, h, a, r, g, b)
    window.calls = window.calls + 1
    return ISPanel.drawRect(window, x, y, w, h, a, r, g, b)
end

function Lens.attach(window)
    window.calls = 0
    window.rims, window.shadows = 0, 0
    window.tiling = type(window.drawTextureTiled) == "function"
    if type(ISPanel) == "table" and type(ISPanel.drawRect) == "function" then window.drawRect = Lens.countRect end
end

function Lens.detach(window)
    window.drawRect = nil
end

function Lens.fill(window, x, y, w, h, a, r, g, b)
    if w <= 0 or h <= 0 then return end
    window:drawRect(math.floor(x), math.floor(y), math.ceil(w), math.ceil(h), a, r, g, b)
end

function Lens.blit(window, texture, x, y, w, h, a, r, g, b)
    window.calls = window.calls + 1
    window:drawTextureScaled(texture, x, y, w, h, a, r, g, b)
end

function Lens.flat(window, f)
    local view, grade = window.view, window.grade
    local hor = view.horizon
    local bottom = view.sy + view.sh
    Lens.fill(window, view.sx, view.sy, view.sw, hor - view.sy, 1, grade.fr * 0.40 * f, grade.fg * 0.40 * f, grade.fb * 0.40 * f)
    local bands = 8
    for index = 1, bands do
        local t0, t1 = (index - 1) / bands, index / bands
        local y0 = hor + (bottom - hor) * t0 * t0
        local y1 = hor + (bottom - hor) * t1 * t1
        local shade = 0.95 - 0.65 * (index - 0.5) / bands
        Lens.fill(window, view.sx, y0, view.sw, y1 - y0 + 1, 1, grade.fr * shade * f, grade.fg * shade * f, grade.fb * shade * f)
    end
end

function Lens.backdrop(window, f)
    local view, grade, lt = window.view, window.grade, window.lt
    local texture = lt.out
    if window.indoor then texture = lt.inn end
    if texture == nil then
        Lens.flat(window, f)
        return
    end
    Lens.blit(window, texture, view.sx, view.sy, view.sw, view.sh, 1, grade.tr * f, grade.tg * f, grade.tb * f)
end

function Lens.shadow(window, fig)
    if window.shadows >= Lens.shadowCap then return end
    window.shadows = window.shadows + 1
    local e = fig.entry
    local w = e.w * 1.6
    if fig.kind == "vehicle" then
        w = e.h * 2.0
    elseif fig.kind == "animal" then
        w = e.h
    end
    local h = Data.clamp(e.h * 0.07, 2, 8)
    local x, y = e.x - w / 2, e.y - h / 2
    Lens.fill(window, x, y, w, h, 0.26, 0, 0, 0)
    Lens.fill(window, x + w * 0.16, y - 1, w * 0.68, h + 2, 0.26, 0, 0, 0)
    Lens.fill(window, x + w * 0.32, y - 2, w * 0.36, h + 4, 0.30, 0, 0, 0)
end

function Lens.modelShadows(window)
    local figs = window.figs
    for index = 1, #figs do
        local fig = figs[index]
        if fig.slot ~= nil then Lens.shadow(window, fig) end
    end
end

function Lens.human(window, fig, r, g, b)
    local e = fig.entry
    local h, cx = e.h, e.x
    local top = e.y - h
    if fig.down == true and Data.isHuman(fig.kind) then
        window:drawRect(math.floor(cx - e.w / 2), math.floor(top), math.floor(e.w), math.max(2, math.floor(h)), 1, r, g, b)
        return
    end
    local zombie = fig.kind == "zombie"
    local lean = 0
    if zombie then lean = h * 0.035 end
    local hw = h * 0.115
    local hx = cx - hw / 2 + lean
    window:drawRect(math.floor(hx), math.floor(top), math.max(2, math.floor(hw)), math.max(2, math.floor(h * 0.075)), 1, r, g, b)
    window:drawRect(math.floor(hx + hw * 0.1), math.floor(top + h * 0.075), math.max(2, math.floor(hw * 0.8)),
        math.max(1, math.floor(h * 0.05)), 1, r, g, b)
    window:drawRect(math.floor(cx - h * 0.03 + lean * 0.6), math.floor(top + h * 0.12), math.max(1, math.floor(h * 0.06)),
        math.max(1, math.floor(h * 0.035)), 1, r, g, b)
    window:drawRect(math.floor(cx - h * 0.135 + lean * 0.5), math.floor(top + h * 0.15), math.max(3, math.floor(h * 0.27)),
        math.max(2, math.floor(h * 0.14)), 1, r, g, b)
    window:drawRect(math.floor(cx - h * 0.105 + lean * 0.3), math.floor(top + h * 0.29), math.max(3, math.floor(h * 0.21)),
        math.max(2, math.floor(h * 0.17)), 1, r, g, b)
    local aw = math.max(1, math.floor(h * 0.045))
    local arm = math.max(2, math.floor(h * 0.30))
    if zombie then arm = math.max(2, math.floor(h * 0.20)) end
    window:drawRect(math.floor(cx - h * 0.18 + lean * 0.5), math.floor(top + h * 0.16), aw, arm, 1, r, g, b)
    window:drawRect(math.floor(cx + h * 0.135 + lean * 0.5), math.floor(top + h * 0.16), aw, arm, 1, r, g, b)
    if zombie then
        window:drawRect(math.floor(cx - h * 0.21 + lean), math.floor(top + h * 0.34), aw * 2, aw, 1, r, g, b)
        window:drawRect(math.floor(cx + h * 0.135 + lean), math.floor(top + h * 0.34), aw * 2, aw, 1, r, g, b)
    end
    local lw = math.max(2, math.floor(h * 0.10))
    local legTop = top + h * 0.46
    local legLen = math.max(2, math.floor(e.y - legTop))
    window:drawRect(math.floor(cx - lw - 1), math.floor(legTop), lw, legLen, 1, r, g, b)
    window:drawRect(math.floor(cx + 1), math.floor(legTop), lw, legLen, 1, r, g, b)
    if zombie and h > 40 then
        local eye = math.max(1, math.floor(hw * 0.2))
        window:drawRect(math.floor(hx + hw * 0.22), math.floor(top + h * 0.03), eye, eye, 1, 0.75, 0.12, 0.10)
        window:drawRect(math.floor(hx + hw * 0.78) - eye, math.floor(top + h * 0.03), eye, eye, 1, 0.75, 0.12, 0.10)
    end
end

function Lens.shape(window, fig, r, g, b)
    local peek = ProjectALife.PeekDoor
    if fig.kind == "animal" then
        peek.drawAnimal(window, fig, r, g, b)
    elseif fig.kind == "vehicle" then
        peek.drawVehicle(window, fig, r, g, b)
    else
        Lens.human(window, fig, r, g, b)
    end
end

function Lens.figure(window, fig)
    local grade = window.grade
    Lens.shadow(window, fig)
    local fog = Data.clamp(fig.depth / 14, 0, 0.6) * 0.8
    local r = Data.lerp(grade.sr, grade.fr * 0.55, fog)
    local g = Data.lerp(grade.sg, grade.fg * 0.55, fog)
    local b = Data.lerp(grade.sb, grade.fb * 0.55, fog)
    local e = fig.entry
    if e.h >= Lens.rimMin and window.rims < Lens.rimCap and fig.down ~= true then
        window.rims = window.rims + 1
        local rim = grade.ra * (1 - fog)
        e.x = e.x - 1
        Lens.shape(window, fig, Data.lerp(r, grade.rr, rim), Data.lerp(g, grade.rg, rim), Data.lerp(b, grade.rb, rim))
        e.x = e.x + 1
    end
    Lens.shape(window, fig, r, g, b)
end

function Lens.back(window)
    local peek = ProjectALife.PeekDoor
    local grade = window.grade
    local now = peek.nowMs()
    window.frameMs = now
    window.calls, window.rims, window.shadows = 0, 0, 0
    local iris = Lens.iris(window, now)
    window.iris = iris
    local f = Lens.flicker(now)
    grade.flick = f
    local black = Lens.blackout(window, iris)
    local tint, blue = 0.004, 0.006
    if window.full == true then tint, blue = 0, 0 end
    if black > 0 then Lens.fill(window, 0, 0, window.width, window.height, black, tint, tint, blue) end
    if iris <= 0.03 then return end
    Lens.backdrop(window, f)
    if window.live == true and peek.drawScene(window, false) then
        Lens.modelShadows(window)
        return
    end
    local figs = window.figs
    for index = 1, #figs do
        local fig = figs[index]
        if fig.slot == nil and fig.layer ~= "top" then peek.drawFigure(window, fig) end
    end
    Lens.modelShadows(window)
end

function Lens.film(window, now, f)
    local view, grade, lt = window.view, window.grade, window.lt
    local bucket = math.floor(now / 55) % 1009
    local tile = Lens.grainTile
    if lt.grain ~= nil and window.tiling then
        local jx, jy = (bucket * 37) % tile, (bucket * 91 + 17) % tile
        window.calls = window.calls + 1
        window:drawTextureTiled(lt.grain, view.sx - jx, view.sy - jy, view.sw + tile, view.sh + tile, grade.hr, grade.hg, grade.hb,
            grade.grain * (0.8 + 0.4 * f) * (1 + 0.5 * (window.tension or 0)))
        jx, jy = (bucket * 53 + 7) % tile, (bucket * 29 + 3) % tile
        window.calls = window.calls + 1
        window:drawTextureTiled(lt.grain, view.sx - jx, view.sy - jy, view.sw + tile, view.sh + tile, grade.hr, grade.hg, grade.hb,
            grade.grain * 0.45)
    end
    if lt.scan ~= nil and window.tiling then
        window.calls = window.calls + 1
        window:drawTextureTiled(lt.scan, view.sx, view.sy, view.sw, view.sh, 0, 0, 0, grade.scan)
    end
    local span = view.sh * 1.5
    local bar = view.sy - view.sh * 0.25 + (now * 0.03) % span
    Lens.fill(window, view.sx, bar, view.sw, view.sh * 0.10, grade.scan * 0.22, grade.hr, grade.hg, grade.hb)
end

function Lens.rain(window, now)
    local scene = ProjectALife.PeekScene
    if scene == nil or type(scene.rain) ~= "function" then return end
    scene.rain(window, now)
end

function Lens.bands(window, view, mx, my, mw, mh, a)
    local r, g, b = 0.004, 0.004, 0.006
    local x0, top, x1, last = 0, 0, view.w, view.h
    if view.full == true then r, g, b = 0, 0, 0 end
    if view.full == true then x0, top, x1, last = view.sx, view.sy, view.sx + view.sw, view.sy + view.sh end
    local bottom = my + mh
    if my > top then Lens.fill(window, x0, top, x1 - x0, my - top, a, r, g, b) end
    if bottom < last then Lens.fill(window, x0, bottom, x1 - x0, last - bottom, a, r, g, b) end
    local y0 = math.max(top, my)
    local y1 = math.min(last, bottom)
    if mx > x0 then Lens.fill(window, x0, y0, mx - x0, y1 - y0, a, r, g, b) end
    if mx + mw < x1 then Lens.fill(window, mx + mw, y0, x1 - mx - mw, y1 - y0, a, r, g, b) end
end

function Lens.fullRim(window, a)
    local view = window.view
    local rows = window.maskRows
    local x1 = view.sx + view.sw
    for index = 1, #rows do
        local row = rows[index]
        local y, step, left, right = row[1], row[2], row[3], row[4]
        if left > view.sx then Lens.fill(window, view.sx, y, left - view.sx, step, a, 0.012, 0.012, 0.014) end
        if right < x1 then Lens.fill(window, right, y, x1 - right, step, a, 0.012, 0.012, 0.014) end
        if row[5] then
            Lens.fill(window, left, y, 9, step, 0.42 * a, 0.012, 0.012, 0.014)
            Lens.fill(window, right - 9, y, 9, step, 0.42 * a, 0.012, 0.012, 0.014)
        end
    end
end

function Lens.mask(window, now)
    local view, grade, lt = window.view, window.grade, window.lt
    local o = window.iris or 1
    local e = o
    if window.fadeAt == nil then e = 1 - (1 - o) * (1 - o) * (1 - o) end
    local squeeze = 1
    local tension = window.tension or 0
    if tension > 0 then squeeze = 1 - 0.022 * tension * (0.5 + 0.5 * math.sin(now * 0.0070)) end
    local hw = view.R * (0.30 + 0.70 * e) * squeeze
    local hh = view.R * (0.03 + 0.97 * Lens.smooth(0.10, 0.85, o)) * squeeze
    local dx, dy = Lens.sway(window, now)
    local black = Lens.blackout(window, o)
    if lt.mask == nil then
        if view.full == true then
            Lens.fullRim(window, black)
            if o < 1 then Lens.fill(window, view.sx, view.sy, view.sw, view.sh, 1 - o, 0.004, 0.004, 0.006) end
            return
        end
        local peek = ProjectALife.PeekDoor
        peek.drawVignette(window)
        if o < 1 then Lens.fill(window, 0, 0, view.w, view.h, 1 - o, 0.004, 0.004, 0.006) end
        return
    end
    local mw, mh = 2 * hw / Lens.hole, 2 * hh / Lens.hole
    local mx, my = view.cx + dx - mw / 2, view.cy + dy - mh / 2
    if view.full == true then
        window:setStencilRect(view.mx, view.my, view.mw, view.mh)
    else
        window:setStencilRect(0, 0, view.w, view.h)
    end
    local ok, err = pcall(Lens.blit, window, lt.mask, mx, my, mw, mh, black, grade.hr, grade.hg, grade.hb)
    window:clearStencilRect()
    if not ok then error(err, 0) end
    Lens.bands(window, view, mx, my, mw, mh, black)
end

function Lens.tone(grade, name)
    local r, g, b = Data.tone(name)
    return Data.lerp(r, grade.hr, 0.5), Data.lerp(g, grade.hg, 0.5), Data.lerp(b, grade.hb, 0.5)
end

function Lens.label(window, fig, ia)
    local label = fig.label
    if label == nil or #label.lines == 0 then return end
    local view, grade = window.view, window.grade
    local e = fig.entry
    local fh = window.fontH
    local count = #label.lines
    local plateW, plateH = label.w + 8, count * fh + 2
    local pcx, pcy = e.x, e.y + 5 + plateH / 2
    local limit = view.R * 0.90
    local half = math.sqrt(plateW * plateW + plateH * plateH) / 2
    local dx, dy = pcx - view.cx, pcy - view.cy
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist + half > limit then
        local above = e.y - e.h - 5 - plateH / 2
        local ay = above - view.cy
        if math.sqrt(dx * dx + ay * ay) + half <= limit then
            pcy, dy = above, ay
            dist = math.sqrt(dx * dx + dy * dy)
        end
    end
    if dist + half > limit and dist > 0.001 then
        local k = math.max(0, (limit - half) / dist)
        pcx, pcy = view.cx + dx * k, view.cy + dy * k
        dist = dist * k
    end
    local a = Data.clamp((view.R * 0.98 - dist) / (view.R * 0.30), 0.35, 1) * ia
    local px, py = math.floor(pcx - plateW / 2), math.floor(pcy - plateH / 2)
    Lens.fill(window, px, py, plateW, plateH, 0.40 * a, 0.004, 0.006, 0.005)
    for index = 1, count do
        local line = label.lines[index]
        local r, g, b = Lens.tone(grade, line.tone)
        window:drawTextCentre(line.text, px + plateW / 2, py + 1 + (index - 1) * fh, r, g, b, a, UIFont.Small)
    end
end

function Lens.marks(window, fig, ia)
    local e = fig.entry
    if fig.bleeding == true and Data.isHuman(fig.kind) then
        window:drawRectBorder(math.floor(e.x - e.w / 2 - 2), math.floor(e.y - e.h - 2), math.floor(e.w) + 4, math.floor(e.h) + 4,
            0.7 * ia, 0.9, 0.18, 0.15)
    end
    if fig.raised == true and (fig.label == nil or #fig.label.lines == 0) then
        window:drawRect(math.floor(e.x - 4), math.floor(e.y - e.h - 7), 8, 3, ia, 1.0, 0.62, 0.25)
    end
end

function Lens.hudFull(window, ia, f)
    local view, grade = window.view, window.grade
    local y = view.statusY
    local shown = math.min(#window.status, view.statusLines)
    for index = 1, shown do
        local line = window.status[index]
        local r, g, b = Lens.tone(grade, line.tone)
        window:drawTextCentre(line.text, view.cx, y, r, g, b, 0.85 * ia * f, UIFont.Small)
        y = y + window.fontH + 2
    end
    window:drawTextCentre(window.s.hint, view.cx, view.hintY, grade.hr * 0.7, grade.hg * 0.7, grade.hb * 0.7, 0.8 * ia, UIFont.Small)
end

function Lens.hud(window, ia, f)
    local view, grade = window.view, window.grade
    if view.full == true then return Lens.hudFull(window, ia, f) end
    local y = 8
    for index = 1, #window.status do
        local line = window.status[index]
        local r, g, b = Lens.tone(grade, line.tone)
        window:drawText(line.text, 12, y, r, g, b, 0.85 * ia * f, UIFont.Small)
        y = y + window.fontH + 2
    end
    window:drawTextRight(window.s.hint, view.w - 12, view.h - window.fontH - 8, grade.hr * 0.7, grade.hg * 0.7, grade.hb * 0.7, 0.8 * ia,
        UIFont.Small)
end

function Lens.front(window)
    local peek = ProjectALife.PeekDoor
    local view, grade, lt = window.view, window.grade, window.lt
    local now = window.frameMs or peek.nowMs()
    local ia, f = Data.clamp(((window.iris or 1) - 0.45) / 0.5, 0, 1), grade.flick or 1
    local figs = window.figs
    if not (window.live == true and peek.drawScene(window, true)) then
        for index = 1, #figs do
            local fig = figs[index]
            if fig.slot == nil and fig.layer == "top" then peek.drawFigure(window, fig) end
        end
    end
    Lens.rain(window, now)
    Lens.fill(window, view.sx, view.sy, view.sw, view.sh, grade.wa * (1 + (1 - f) * 2), grade.wr, grade.wg, grade.wb)
    if lt.glow ~= nil then
        local size = view.R * 1.7
        local gx = view.cx + math.sin(now * 0.00031) * view.R * 0.10 - size / 2
        Lens.blit(window, lt.glow, gx, view.horizon - size * 0.45, size, size, grade.glow * f, grade.hr, grade.hg, grade.hb)
    end
    if lt.grain ~= nil or lt.scan ~= nil then
        window:setStencilRect(view.sx, view.sy, view.sw, view.sh)
        local ok, err = pcall(Lens.film, window, now, f)
        window:clearStencilRect()
        if not ok then error(err, 0) end
    end
    Lens.mask(window, now)
    if ia > 0.02 then
        for index = 1, #figs do
            Lens.marks(window, figs[index], ia)
            Lens.label(window, figs[index], ia)
        end
        Lens.hud(window, ia, f)
    end
    if view.full ~= true then
        window:drawRectBorder(0, 0, window.width, window.height, 1, 0.09, 0.11, 0.10)
        Lens.fill(window, 0, view.h, window.width, 1, 1, 0.09, 0.11, 0.10)
    end
    local metrics = peek.metrics
    metrics.lensFrames = metrics.lensFrames + 1
    metrics.lensCalls = window.calls
    if window.calls > metrics.lensPeak then metrics.lensPeak = window.calls end
    Lens.metrics.frames = Lens.metrics.frames + 1
end

return Lens
