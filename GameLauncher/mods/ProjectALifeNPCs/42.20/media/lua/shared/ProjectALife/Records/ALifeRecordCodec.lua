ProjectALife = ProjectALife or {}

local Codec = {
    VERSION = 1,
    HEADER = "@alife-records 1",
    CLOSE = "end",
    INDENT = "  ",
    SETS = { "A", "B", "C", "D", "E", "F" },
    reserved = { id = true, kind = true, source = true, line = true },
    escapes = { ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" },
    unescapes = { ["\\"] = "\\", n = "\n", r = "\r", t = "\t", s = " " },
}
ProjectALife.RecordCodec = Codec

Codec.schema = {
    faction = {
        general = { "about", { name = "title", category = "heading", description = "blurb",
            deleted = "removed" } },
        spawn = { "presence", {
            enabled = "active", natural = "roams",
            encounterPool = "encounters", program = "routine", programPool = "routines",
            hourStart = "fromHour", hourEnd = "toHour",
            partyMode = "partyStyle", loneMin = "soloFewest", loneMax = "soloMost",
            partyGroupMin = "bandFewest", partyGroupMax = "bandMost",
            loneWeight = "soloOdds", groupWeight = "bandOdds",
            spawnRangeMin = "nearTiles", spawnRangeMax = "farTiles",
            locationMode = "placeRule", allTowns = "everyTown", specificPlacePool = "places",
            includeWilderness = "wilds", seats = "holds", backupMode = "backup",
            visitorOnly = "doorOnly",
        } },
        support = { "reinforce", { policy = "rule", type = "means", size = "squad",
            maxCalls = "calls", heli = "aircraft" } },
        modules = { "hooks" },
        relations = { "stance" },
        memberModules = { "habits" },
        outfitSeason = { "attireSeason" },
        outfitNames = { "attireNames" },
    },
    member = {
        general = { "who", {
            faction = "who.faction", name = "who.title", voiceProfile = "who.voice",
            profession = "who.trade", spawnWeight = "who.odds", deleted = "who.removed",
            female = "body.sex", skin = "body.tone", healthHP = "body.hitPoints",
            strength = "body.might", endurance = "body.stamina", awareness = "body.alertness",
            aiming = "body.marksmanship", aimPlayerPercent = "body.aimAtPlayers",
            aimZombiePercent = "body.aimAtDead", damageReduction = "body.soak",
            damageOutput = "body.punch",
            hairStyle = "look.hair", hairColor = "look.hairTint",
            beardStyle = "look.beard", beardColor = "look.beardTint",
            lookFixed = "look.fixed", lookVary = "look.vary", toneFixed = "look.toneFixed",
            defaultActivity = "mind.defaultTask", behaviorProfile = "mind.temper",
            primaryBehavior = "mind.focus", combatReady = "mind.readiness",
            ammoMode = "kit.ammoStyle", primaryMagazines = "kit.mainMags",
            secondaryMagazines = "kit.sideMags", infiniteAmmo = "kit.bottomless",
            supportCaller = "radio.caller", supportPolicy = "radio.rule",
            supportType = "radio.means", supportHeli = "radio.aircraft",
            dropAmmo = "loot.rounds", magazineDropMax = "loot.magsMost",
            magazineDropChance = "loot.magsOdds", dropWeapon = "loot.gun",
            dropWeaponChance = "loot.gunOdds", dropWeaponPreset = "loot.gunRule",
            dropWeaponCondition = "loot.gunWear", dropArmorChance = "loot.armorOdds",
            armorCondition = "loot.armorWear",
        }, { female = { "female", "male" } } },
        clothing = { "attire" },
        outfitEnabled = { "attireOn" },
        outfitSeason = { "attireSeason" },
        weapons = { "arms", { primary = "main", secondary = "side", melee = "closeIn" } },
        ammo = { "rounds", { primary = "main", secondary = "side" } },
        weaponAttachments = { "fittings" },
        modules = { "hooks" },
        moduleOverrides = { "habits" },
    },
}
for _, set in ipairs(Codec.SETS) do
    Codec.schema.member["outfit" .. set] = { "attire" .. set }
    Codec.schema.member["tint" .. set] = { "dye" .. set }
end
for _, set in ipairs({ "A", "B", "C", "D" }) do
    Codec.schema.faction["outfit" .. set] = { "attire" .. set }
    Codec.schema.faction["tint" .. set] = { "dye" .. set }
end

function Codec.build()
    Codec.out, Codec.into = {}, {}
    for kind, sections in pairs(Codec.schema) do
        local out, into = {}, {}
        for section, spec in pairs(sections) do
            local group = spec[1]
            local route = { group = group, paths = {}, flags = {} }
            out[section] = route
            into[group] = into[group] or { section = section, fields = {}, flags = {} }
            for key, target in pairs(spec[2] or {}) do
                local dot = string.find(target, ".", 1, true)
                local owner, field = group, target
                if dot ~= nil then
                    owner, field = string.sub(target, 1, dot - 1), string.sub(target, dot + 1)
                end
                into[owner] = into[owner] or { section = section, fields = {}, flags = {} }
                route.paths[key] = owner .. "." .. field
                into[owner].fields[field] = key
                local flag = spec[3] and spec[3][key]
                if flag ~= nil then
                    route.flags[key] = flag
                    into[owner].flags[field] = flag
                end
            end
        end
        Codec.out[kind], Codec.into[kind] = out, into
    end
end
Codec.build()

function Codec.validId(id)
    return type(id) == "string" and string.match(id, "^[%w_%-%.]+$") ~= nil
end

function Codec.scalar(value)
    if value == "true" then return true end
    if value == "false" then return false end
    if value == "" then return "" end
    local number = tonumber(value)
    if number ~= nil then return number end
    return value
end

Codec.escaped, Codec.escapedCount = {}, 0

function Codec.escape(text)
    text = tostring(text)
    if text == "" then return text end
    local cached = Codec.escaped[text]
    if cached ~= nil then return cached end
    local source = text
    if string.find(text, "[\\\r\n\t]") then
        text = string.gsub(text, "[\\\r\n\t]", function(char) return Codec.escapes[char] end)
    end
    if string.sub(text, 1, 1) == " " then text = "\\s" .. string.sub(text, 2) end
    if string.sub(text, -1) == " " then text = string.sub(text, 1, -2) .. "\\s" end
    if #source <= 64 then
        if Codec.escapedCount >= 4096 then Codec.escaped, Codec.escapedCount = {}, 0 end
        Codec.escaped[source] = text
        Codec.escapedCount = Codec.escapedCount + 1
    end
    return text
end

function Codec.unescape(text)
    return (string.gsub(text, "\\(.)", function(char)
        return Codec.unescapes[char] or ("\\" .. char)
    end))
end

function Codec.path(kind, section, key)
    local routes = Codec.out[kind]
    local route = routes and routes[section]
    if route == nil then return section .. "." .. tostring(key) end
    return route.paths[key] or (route.group .. "." .. tostring(key))
end

function Codec.valueText(kind, section, key, value)
    local routes = Codec.out[kind]
    local flag = routes and routes[section] and routes[section].flags[key]
    if flag ~= nil then
        if value == true or value == "true" then return flag[1] end
        if value == false or value == "false" then return flag[2] end
    end
    if type(value) == "boolean" then return value and "true" or "false" end
    if value == nil then return "" end
    return tostring(value)
end

function Codec.line(kind, section, key, value)
    local text = Codec.escape(Codec.valueText(kind, section, key, value))
    local path = Codec.INDENT .. Codec.path(kind, section, key)
    if text == "" then return path end
    return path .. " " .. text
end

function Codec.begin(kind, id)
    return { kind = kind, lines = { tostring(kind) .. " " .. tostring(id) } }
end

function Codec.put(block, section, key, value)
    block.lines[#block.lines + 1] = Codec.line(block.kind, section, key, value)
end

function Codec.finish(block)
    block.lines[#block.lines + 1] = Codec.CLOSE
    return table.concat(block.lines, "\n")
end

function Codec.document(blocks)
    if #blocks == 0 then return "" end
    return Codec.HEADER .. "\n\n" .. table.concat(blocks, "\n\n") .. "\n"
end

Codec.routeCap = 2048

function Codec.clock()
    if type(getTimestampMs) == "function" then return tonumber(getTimestampMs()) end
    return nil
end

function Codec.decodeStart(text, options)
    if type(text) ~= "string" then return nil, "record_text_required", "record_text_required" end
    options = options or {}
    local lenient = options.lenient == true
    return {
        text = text, size = #text, cursor = 1, lineNumber = 0,
        source = tostring(options.source or "records"), want = options.kind,
        keepText = options.text == true, lenient = lenient,
        rejects = lenient and type(options.rejects) == "table" and options.rejects or nil,
        records = {}, byId = {}, count = 0, skipping = false,
        crlf = string.find(text, "\r", 1, true) ~= nil,
        tabbed = string.find(text, "\t", 1, true) ~= nil,
        routes = {}, routeCount = 0,
    }
end

function Codec.decodeFail(state, lineNumber, code, detail)
    local message = state.source .. ":" .. tostring(lineNumber) .. ":" .. code
    if detail ~= nil then message = message .. ":" .. tostring(detail) end
    state.finished, state.failure, state.failCode = true, message, code
    return true, nil, message, code
end

function Codec.decodeSkip(state, lineNumber, code, line, record)
    local rejects = state.rejects
    if rejects == nil then return end
    rejects[#rejects + 1] = { line = lineNumber, code = code, text = line,
        record = record and record.id, recordLine = record and record.line }
end

function Codec.decodeRoute(state, into, key, dot)
    local owner = into or state
    local known = state.routes[owner]
    if known == nil then
        known = {}
        state.routes[owner] = known
    end
    local entry = known[key]
    if entry ~= nil then return entry end
    local group, field = string.sub(key, 1, dot - 1), string.sub(key, dot + 1)
    local route = into and into[group]
    local section, name, flag = group, field, nil
    if route ~= nil then
        section, name, flag = route.section, route.fields[field] or field, route.flags[field]
    end
    entry = { section = section, name = name, flag = flag,
        bad = group == "" or field == "" or Codec.reserved[section] ~= nil }
    if state.routeCount >= Codec.routeCap then
        known = {}
        state.routes, state.routeCount = { [owner] = known }, 0
    end
    known[key] = entry
    state.routeCount = state.routeCount + 1
    return entry
end

function Codec.decodeStep(state, budgetMs)
    if state.finished then return true, state.result, state.failure, state.failCode end
    local text, size, crlf, tabbed = state.text, state.size, state.crlf, state.tabbed
    local cursor, lineNumber = state.cursor, state.lineNumber
    local current, into, skipping = state.current, state.into, state.skipping
    local lenient, keepText, want = state.lenient, state.keepText, state.want
    local records, byId = state.records, state.byId
    local startedAt, spent = nil, 0
    if budgetMs ~= nil then startedAt = Codec.clock() end
    local find, sub, byte = string.find, string.sub, string.byte
    while cursor <= size do
        if startedAt ~= nil then
            spent = spent + 1
            if spent % 64 == 0 then
                local now = Codec.clock()
                if now == nil or now < startedAt or now - startedAt >= budgetMs then break end
            end
        end
        local ending
        if crlf then ending = find(text, "[\r\n]", cursor) else ending = find(text, "\n", cursor, true) end
        local line = sub(text, cursor, ending and ending - 1 or size)
        cursor = ending and ending + 1 or size + 1
        if crlf and ending and byte(text, ending) == 13 and byte(text, cursor) == 10 then cursor = cursor + 1 end
        lineNumber = lineNumber + 1
        local first, head = nil, byte(line, 1)
        if head ~= nil and head > 32 and head < 127 then first = 1
        elseif head == 32 and byte(line, 2) == 32 then
            head = byte(line, 3)
            if head ~= nil and head > 32 and head < 127 then first = 3 end
        end
        if first == nil then
            first = find(line, "%S")
            head = first and byte(line, first) or nil
        end
        if head == 64 then
            local version = string.match(line, "^%s*@alife%-records%s+(%d+)")
            if version ~= nil and tonumber(version) > Codec.VERSION and not lenient then
                return Codec.decodeFail(state, lineNumber, "record_version", version)
            end
        elseif head ~= nil and not (head == 45 and byte(line, first + 1) == 45) then
            local gap
            if tabbed then gap = find(line, "[ \t]", first) else gap = find(line, " ", first, true) end
            local key = sub(line, first, gap and gap - 1 or -1)
            local dot = find(key, ".", 1, true)
            if dot == nil then
                local rest = gap and string.match(sub(line, gap), "^%s*(.-)%s*$") or ""
                if key == Codec.CLOSE then
                    if current == nil and not skipping and not lenient then
                        return Codec.decodeFail(state, lineNumber, "stray_end")
                    end
                    if current == nil and not skipping then Codec.decodeSkip(state, lineNumber, "stray_end", line) end
                    current, into, skipping = nil, nil, false
                elseif string.match(key, "^%a+$") ~= nil and Codec.validId(rest) then
                    if (current ~= nil or skipping) and not lenient then
                        return Codec.decodeFail(state, lineNumber, "unclosed_record", current and current.id or rest)
                    end
                    if current ~= nil then Codec.decodeSkip(state, lineNumber, "unclosed_record", line, current) end
                    current, into, skipping = nil, nil, false
                    if want ~= nil and key ~= want then
                        if not lenient then return Codec.decodeFail(state, lineNumber, "wrong_kind", rest) end
                        Codec.decodeSkip(state, lineNumber, "wrong_kind", line)
                        skipping = true
                    elseif byId[rest] ~= nil and not lenient then
                        return Codec.decodeFail(state, lineNumber, "duplicate_record", rest)
                    else
                        current = { id = rest, kind = key, source = state.source, line = lineNumber }
                        records[#records + 1] = current
                        byId[rest] = current
                        into = Codec.into[key]
                    end
                elseif not lenient then
                    if current == nil and not skipping then return Codec.decodeFail(state, lineNumber, "outside_record") end
                    return Codec.decodeFail(state, lineNumber, "bad_line")
                elseif not skipping then
                    Codec.decodeSkip(state, lineNumber, current == nil and "outside_record" or "bad_line", line, current)
                end
            elseif current == nil then
                if not skipping and not lenient then return Codec.decodeFail(state, lineNumber, "outside_record") end
                if not skipping then Codec.decodeSkip(state, lineNumber, "outside_record", line) end
            else
                local entry = Codec.decodeRoute(state, into, key, dot)
                if entry.bad then
                    if not lenient then return Codec.decodeFail(state, lineNumber, "bad_field", key) end
                    Codec.decodeSkip(state, lineNumber, "bad_field", line, current)
                else
                    local value = ""
                    local from = nil
                    if gap ~= nil then
                        local lead = byte(line, gap + 1)
                        if lead ~= nil and lead > 32 and lead < 127 then from = gap + 1 else from = find(line, "%S", gap) end
                    end
                    if from ~= nil then
                        value = sub(line, from)
                        local last = byte(value, -1)
                        if last == 32 or last == 9 then value = string.match(value, "^(.-)[ \t]+$") end
                        if find(value, "\\", 1, true) then value = Codec.unescape(value) end
                    end
                    local flag = entry.flag
                    if flag ~= nil then
                        if value == flag[1] then value = "true" elseif value == flag[2] then value = "false" end
                    end
                    if not keepText then value = Codec.scalar(value) end
                    local section, name = entry.section, entry.name
                    local bucket = current[section]
                    if bucket == nil then
                        bucket = {}
                        current[section] = bucket
                    elseif bucket[name] ~= nil and not lenient then
                        return Codec.decodeFail(state, lineNumber, "duplicate_field", current.id .. ":" .. key)
                    elseif bucket[name] ~= nil then
                        Codec.decodeSkip(state, lineNumber, "duplicate_field", line, current)
                    end
                    bucket[name] = value
                end
            end
        end
    end
    state.cursor, state.lineNumber = cursor, lineNumber
    state.current, state.into, state.skipping = current, into, skipping
    state.count = #records
    if cursor <= size then return false end
    if current ~= nil and not lenient then return Codec.decodeFail(state, lineNumber, "unclosed_record", current.id) end
    if current ~= nil then Codec.decodeSkip(state, lineNumber, "unclosed_record", "", current) end
    state.finished, state.result = true, { records = records, byId = byId }
    return true, state.result
end

function Codec.decode(text, options)
    local state, message, code = Codec.decodeStart(text, options)
    if state == nil then return nil, message, code end
    local _, result, failure, failCode = Codec.decodeStep(state, nil)
    if result == nil then return nil, failure, failCode end
    return result
end

function Codec.validatePart(text, kind, seen)
    local parsed, reason = Codec.decode(text, { kind = kind, text = true })
    if parsed == nil then return false, reason end
    if #parsed.records ~= 1 then return false, "prepared_record_count" end
    local id = parsed.records[1].id
    if seen[id] then return false, "duplicate_record" end
    seen[id] = true
    return true
end

return Codec
