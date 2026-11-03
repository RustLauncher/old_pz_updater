require "ProjectALife/Core/ALifeText"
require "ProjectALife/Shells/ALifeWounds"

ProjectALife = ProjectALife or {}

local Data = {
    order = { "head", "torso", "arm_l", "arm_r", "leg_l", "leg_r" },
    groups = {
        head = { 8, 9 }, torso = { 6, 7, 10 }, arm_l = { 4, 2, 0 }, arm_r = { 5, 3, 1 },
        leg_l = { 11, 13, 15 }, leg_r = { 12, 14, 16 },
    },
    slots = {
        head = { 8, 9 }, torso = { 6, 7 }, arm_l = { 4, 2 }, arm_r = { 5, 3 }, leg_l = { 11, 13 }, leg_r = { 12, 14 },
    },
    breaks = { head = { 8 }, torso = { 6 }, arm_l = { 2 }, arm_r = { 3 }, leg_l = { 13 }, leg_r = { 14 } },
    segments = {
        [0] = { tex = "hand_left", bps = "left-hand", z = 0 },
        [1] = { tex = "hand_right", bps = "right-hand", z = 0 },
        [2] = { tex = "lowerarm_left", bps = "lower-left-arm", z = 0 },
        [3] = { tex = "lowerarm_right", bps = "lower-right-arm", z = 0 },
        [4] = { tex = "upperarm_left", bps = "upper-left-arm", z = 0 },
        [5] = { tex = "upperarm_right", bps = "upper-right-arm", z = 0 },
        [6] = { tex = "chest", bps = "chest", z = 30 },
        [7] = { tex = "abdomen", bps = "abdomen", z = 50 },
        [8] = { tex = "head", bps = "head", z = 0 },
        [9] = { tex = "neck", bps = "neck", z = 0 },
        [10] = { tex = "groin", bps = "groin", z = 100 },
        [11] = { tex = "upperleg_left", bps = "left-thigh", z = 0 },
        [12] = { tex = "upperleg_right", bps = "right-thigh", z = 0 },
        [13] = { tex = "lowerleg_left", bps = "left-calf", z = 0 },
        [14] = { tex = "lowerleg_right", bps = "right-calf", z = 0 },
        [15] = { tex = "foot_left", bps = "left-foot", z = 0 },
        [16] = { tex = "foot_right", bps = "right-foot", z = 0 },
    },
    overlays = { scratch = "scratch", laceration = "scratch", deep = "deepwound", bite = "bite", bullet = "bullet", burn = "burn" },
    absent = {
        bones = { abdomen = true, groin = true, neck = true },
        splint = { chest = true, abdomen = true, head = true, neck = true, groin = true },
    },
    absentMale = { bones = { head = true } },
    frame = { x = -5, y = -9, width = 116, height = 291 },
    bar = { gap = 10, width = 25, height = 258, fillWidth = 23, fillHeight = 256 },
    palette = {
        windowBg = { r = 0.035, g = 0.042, b = 0.038, a = 0.97 },
        windowBorder = { r = 0.34, g = 0.39, b = 0.31, a = 1 },
        listBg = { r = 0.015, g = 0.02, b = 0.017, a = 0.85 },
        listBorder = { r = 0.2, g = 0.25, b = 0.2, a = 1 },
        select = { r = 1, g = 1, b = 1, a = 0.2 },
        hover = { r = 1, g = 1, b = 1, a = 0.07 },
        clear = { r = 0, g = 0, b = 0, a = 0 },
    },
    tones = {
        bad = { 0.89, 0.28, 0.28 }, good = { 0.28, 0.89, 0.28 }, warn = { 1, 0.58, 0 },
        plain = { 1, 1, 1 }, dim = { 0.62, 0.66, 0.6 }, alert = { 1, 0.28, 0 },
    },
    levels = { { 1, 1, 1 }, { 1, 0.9, 0.3 }, { 1, 0.6, 0.2 }, { 1, 0.3, 0.3 } },
    levelNames = { "treated", "minor", "moderate", "severe" },
    kindWords = {
        scratch = { "IGUI_health_Scratched", "Scratched" },
        laceration = { "IGUI_health_Cut", "Laceration" },
        deep = { "IGUI_health_DeepWound", "Deep Wound" },
        bite = { "IGUI_health_Bitten", "Bitten" },
        fracture = { "IGUI_health_Fracture", "Fracture" },
        burn = { "IGUI_health_Burned", "Burned" },
    },
    worded = { laceration = true, deep = true, fracture = true, bullet = true },
    statusRows = {
        { 90, "IGUI_health_Slight_damage", "Slight damage" }, { 80, "IGUI_health_Very_Minor_damage", "Very Minor damage" },
        { 70, "IGUI_health_Minor_damage", "Minor damage" }, { 60, "IGUI_health_Moderate_damage", "Moderate damage" },
        { 50, "IGUI_health_Severe_damage", "Severe damage" }, { 40, "IGUI_health_Very_Severe_damage", "Very Severe damage" },
        { 20, "IGUI_health_Crital_damage", "Critical damage" }, { 10, "IGUI_health_Highly_Crital_damage", "Highly Critical damage" },
        { 0, "IGUI_health_Terminal_damage", "Terminal damage" },
    },
    dressings = { "Base.AlcoholBandage", "Base.Bandage", "Base.AlcoholRippedSheets", "Base.RippedSheets" },
    splintItem = "Base.Splint",
}
ProjectALife.WoundPanelData = Data

Data.partOf = {}
for part, list in pairs(Data.groups) do
    for _, index in ipairs(list) do Data.partOf[index] = part end
end

function Data.color(name)
    local source = Data.palette[name] or Data.palette.clear
    return { r = source.r, g = source.g, b = source.b, a = source.a }
end

function Data.tone(name)
    local row = Data.tones[name] or Data.tones.plain
    return row[1], row[2], row[3]
end

function Data.levelColor(rank)
    local row = Data.levels[rank] or Data.levels[1]
    return row[1], row[2], row[3]
end

function Data.capital(text)
    if type(text) ~= "string" or text == "" then return "" end
    return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

function Data.vanilla(key, english)
    if type(getTextOrNull) == "function" then
        local ok, value = pcall(getTextOrNull, key)
        if ok and type(value) == "string" and value ~= "" and value ~= key then return value end
    end
    return english
end

function Data.word(key, english)
    return ProjectALife.Text.get(key, english)
end

function Data.reasonText(id)
    local Text = ProjectALife.Text
    if id == "dead" then return Text.ui("They are beyond help.") end
    if id == "too_far" then return Text.ui("Get closer to check their wounds.") end
    if id == "hostile" then return Text.ui("They won't let you near their wounds.") end
    if id == "not_needed" then return Text.ui("Nothing there needs a dressing.") end
    if id == "no_kit" then return Text.ui("You need a bandage or ripped sheets.") end
    if id == "no_splint" then return Text.ui("You need a splint.") end
    if id == "no_fracture" then return Text.ui("There is no fracture to splint.") end
    if id == "not_down" then return Text.ui("They are not in a state to be helped.") end
    if id == "no_medical" then return Text.ui("You need a bandage or medical supplies.") end
    if id == "not_modelled" then return Text.ui("Survivors' wounds only need a bandage.") end
    return Text.ui("They can't be treated now.")
end

function Data.worldHours()
    local sim = ProjectALife.ShellSimulation
    if sim ~= nil and type(sim.worldHours) == "function" then return tonumber(sim.worldHours()) or 0 end
    return 0
end

function Data.listOf(injuries)
    if type(injuries) == "table" then return injuries end
    return {}
end

function Data.available(overlay, suffix, female)
    local row = Data.absent[overlay]
    if row ~= nil and row[suffix] == true then return false end
    if female ~= true then
        local male = Data.absentMale[overlay]
        if male ~= nil and male[suffix] == true then return false end
    end
    return true
end

function Data.overlayFor(injury)
    if injury.b == true then return "bandage" end
    if injury.k == "fracture" then
        if injury.sp == true then return "splint" end
        return "bones"
    end
    return Data.overlays[injury.k]
end

function Data.textureName(female, overlay, suffix)
    return "media/ui/BodyDamage/" .. (female == true and "female" or "male") .. "_" .. overlay .. "_" .. suffix
end

function Data.place(injuries, female)
    local placed, used = {}, {}
    for _, injury in ipairs(Data.listOf(injuries)) do
        local part = injury.p
        local broken = injury.k == "fracture"
        local pool = broken and Data.breaks[part] or Data.slots[part]
        if pool ~= nil then
            local key = broken and (tostring(part) .. "#break") or part
            local turn = used[key] or 0
            used[key] = turn + 1
            local segment = pool[turn % #pool + 1]
            local overlay = Data.overlayFor(injury)
            if overlay ~= nil and not Data.available(overlay, Data.segments[segment].tex, female) then overlay = nil end
            placed[#placed + 1] = { part = part, segment = segment, overlay = overlay, injury = injury }
        end
    end
    return placed
end

function Data.rank(injury, hours, dead)
    local severity = tonumber(injury.s) or 0
    if injury.b == true or injury.sp == true then return 1 end
    if dead ~= true and ProjectALife.Wounds.bleeding(injury, hours) then return 4 end
    if severity >= 60 then return 4 end
    if severity >= 35 or injury.k == "fracture" then return 3 end
    return 2
end

function Data.ranks(injuries, hours, dead)
    local out = {}
    for _, injury in ipairs(Data.listOf(injuries)) do
        local part = injury.p
        if Data.groups[part] ~= nil then
            local rank = Data.rank(injury, hours, dead)
            if rank > (out[part] or 0) then out[part] = rank end
        end
    end
    return out
end

function Data.kindText(kind)
    local row = Data.kindWords[kind]
    if row ~= nil then return Data.word(row[1], row[2]) end
    if kind == "bullet" then return ProjectALife.Text.ui("Bullet wound") end
    if kind == "bruise" then return ProjectALife.Text.ui("Bruise") end
    return Data.capital(ProjectALife.Wounds.label(kind))
end

function Data.severityWord(injury)
    if Data.worded[injury.k] ~= true then return nil end
    local severity = tonumber(injury.s) or 0
    if severity >= 60 then return Data.word("IGUI_health_Severe", "Severe") end
    if severity >= 35 then return Data.word("IGUI_health_Moderate", "Moderate") end
    return nil
end

function Data.lineOf(injury, hours, dead)
    local text = "- " .. Data.kindText(injury.k)
    local word = Data.severityWord(injury)
    if word ~= nil then text = text .. " (" .. word .. ")" end
    local tone = "warn"
    if injury.sp == true then
        text = text .. ", " .. Data.word("IGUI_health_Splinted", "Splinted")
        tone = "good"
    elseif injury.b == true then
        text = text .. ", " .. Data.word("IGUI_health_Bandaged", "Bandaged")
        tone = "good"
    elseif dead ~= true and ProjectALife.Wounds.bleeding(injury, hours) then
        text = text .. ", " .. Data.word("IGUI_health_Bleeding", "Bleeding")
        tone = "bad"
    elseif (tonumber(injury.s) or 0) >= 35 and injury.k ~= "bruise" then
        tone = "bad"
    end
    return { text = text, tone = tone }
end

function Data.byUrgency(hours, dead)
    return function(a, b)
        local ab = dead ~= true and ProjectALife.Wounds.bleeding(a, hours)
        local bb = dead ~= true and ProjectALife.Wounds.bleeding(b, hours)
        if ab ~= bb then return ab end
        return (tonumber(a.s) or 0) > (tonumber(b.s) or 0)
    end
end

function Data.rows(injuries, hours, dead)
    local grouped = {}
    for _, injury in ipairs(Data.listOf(injuries)) do
        local part = injury.p
        if Data.groups[part] ~= nil then
            local list = grouped[part]
            if list == nil then
                list = {}
                grouped[part] = list
            end
            list[#list + 1] = injury
        end
    end
    local ranks = Data.ranks(injuries, hours, dead)
    local rows = {}
    for _, part in ipairs(Data.order) do
        local list = grouped[part]
        if list ~= nil then
            table.sort(list, Data.byUrgency(hours, dead))
            local lines = {}
            for _, injury in ipairs(list) do lines[#lines + 1] = Data.lineOf(injury, hours, dead) end
            rows[#rows + 1] = { part = part, title = Data.capital(ProjectALife.Wounds.partLabel(part)),
                lines = lines, rank = ranks[part] or 1 }
        end
    end
    return rows
end

function Data.openCount(injuries)
    local kinds, count = ProjectALife.Wounds.kinds, 0
    for _, injury in ipairs(Data.listOf(injuries)) do
        local kind = kinds[injury.k]
        if kind ~= nil and kind.bleed ~= nil and injury.b ~= true then count = count + 1 end
    end
    return count
end

function Data.brokenCount(injuries)
    local count = 0
    for _, injury in ipairs(Data.listOf(injuries)) do
        if injury.k == "fracture" and injury.sp ~= true then count = count + 1 end
    end
    return count
end

function Data.bleedingNow(injuries, hours)
    for _, injury in ipairs(Data.listOf(injuries)) do
        if ProjectALife.Wounds.bleeding(injury, hours) then return true end
    end
    return false
end

function Data.statusWord(hp, dead)
    local value = tonumber(hp) or 100
    if dead == true or value <= 0 then return Data.word("IGUI_health_Deceased", "Deceased") end
    if value >= 100 then return Data.word("IGUI_health_ok", "OK") end
    for _, row in ipairs(Data.statusRows) do
        if value > row[1] then return Data.word(row[2], row[3]) end
    end
    return Data.word("IGUI_health_Terminal_damage", "Terminal damage")
end

function Data.statusTint(hp)
    local value = tonumber(hp) or 100
    return math.max((100 - value) / 100, 0.2)
end

function Data.stateLine(snapshot)
    local Text = ProjectALife.Text
    if snapshot.dead == true then return Text.ui("Dead"), "bad" end
    if snapshot.downed == true then return Text.ui("Bleeding out"), "alert" end
    if snapshot.state == "down" then return Text.ui("Down - needs help"), "warn" end
    return Text.ui("Conscious"), "dim"
end

function Data.treatments(facts)
    local out = {}
    local dead = facts.dead == true
    local open = Data.openCount(facts.injuries)
    local kits = type(facts.kits) == "table" and facts.kits or {}
    local bandage = { id = "bandage", label = Data.vanilla("ContextMenu_Bandage", "Bandage"), kits = kits, enabled = true }
    if dead then
        bandage.enabled, bandage.reason = false, "dead"
    elseif open == 0 and facts.downed ~= true then
        bandage.enabled, bandage.reason = false, "not_needed"
    elseif #kits == 0 then
        bandage.enabled, bandage.reason = false, "no_kit"
    end
    out[#out + 1] = bandage
    local unmodelled = "not_modelled"
    if dead then unmodelled = "dead" end
    out[#out + 1] = { id = "disinfect", label = Data.vanilla("ContextMenu_Disinfect", "Disinfect"), enabled = false,
        reason = unmodelled }
    out[#out + 1] = { id = "stitch", label = Data.vanilla("ContextMenu_Stitch", "Stitch"), enabled = false,
        reason = unmodelled }
    local splint = { id = "splint", label = Data.vanilla("ContextMenu_Splint", "Splint"), enabled = true }
    if dead then
        splint.enabled, splint.reason = false, "dead"
    elseif Data.brokenCount(facts.injuries) == 0 then
        splint.enabled, splint.reason = false, "no_fracture"
    elseif facts.splint ~= true then
        splint.enabled, splint.reason = false, "no_splint"
    end
    out[#out + 1] = splint
    out[#out + 1] = { id = "painkillers", label = ProjectALife.Text.ui("Painkillers"), enabled = false, reason = unmodelled }
    if facts.medical == true then
        local medical = { id = "medical", label = ProjectALife.Text.ui("Give bandage / medical"), enabled = true }
        if dead then
            medical.enabled, medical.reason = false, "dead"
        elseif facts.state ~= "down" then
            medical.enabled, medical.reason = false, "not_down"
        elseif facts.medicalKit ~= true then
            medical.enabled, medical.reason = false, "no_medical"
        end
        out[#out + 1] = medical
    end
    if facts.near == false then
        for _, entry in ipairs(out) do
            if entry.enabled then entry.enabled, entry.reason = false, "too_far" end
        end
    end
    return out
end

function Data.fit(text, width, measure)
    if type(text) ~= "string" or type(measure) ~= "function" then return text end
    if measure(text) <= width then return text end
    local cut = #text
    while cut > 1 and measure(string.sub(text, 1, cut) .. "...") > width do cut = cut - 1 end
    return string.sub(text, 1, cut) .. "..."
end

function Data.signature(snapshot, hours)
    local parts = { tostring(snapshot.hp), tostring(snapshot.downed), tostring(snapshot.state), tostring(snapshot.dead) }
    for _, injury in ipairs(Data.listOf(snapshot.injuries)) do
        parts[#parts + 1] = tostring(injury.p) .. ":" .. tostring(injury.k) .. ":" .. tostring(injury.s) .. ":"
            .. tostring(injury.b) .. ":" .. tostring(injury.sp) .. ":"
            .. tostring(snapshot.dead ~= true and ProjectALife.Wounds.bleeding(injury, hours))
    end
    return table.concat(parts, "|")
end

function Data.hit(boxes, x, y)
    local best, bestZ = nil, -1
    for _, box in ipairs(type(boxes) == "table" and boxes or {}) do
        if x >= box.x and x <= box.x + box.w and y >= box.y and y <= box.y + box.h and box.z > bestZ then
            best, bestZ = box.index, box.z
        end
    end
    return best
end

function Data.layout(titleHeight, fontHeight, mediumHeight)
    local pad = 10
    local frame, bar = Data.frame, Data.bar
    local lay = { pad = pad, headTop = titleHeight + 6, portraitWidth = 72, portraitHeight = 84 }
    local headHeight = math.max(lay.portraitHeight, mediumHeight + fontHeight * 3 + 8)
    lay.bodyX = pad
    lay.bodyY = lay.headTop + headHeight + 10
    lay.barX = lay.bodyX + frame.width + bar.gap
    lay.textX = lay.barX + bar.width + pad + 4
    lay.listX = lay.textX
    lay.listY = lay.bodyY + fontHeight * 3 + 10
    lay.listWidth = math.max(240, fontHeight * 20)
    lay.listHeight = lay.bodyY + frame.height - lay.listY
    lay.bottomY = lay.bodyY + frame.height + 10
    lay.messageY = lay.bottomY + fontHeight + 2
    lay.width = lay.listX + lay.listWidth + pad
    lay.height = lay.messageY + fontHeight + pad
    return lay
end

return Data
