require "ProjectALife/Records/ALifeRecordCodec"
require "ProjectALife/Records/ALifeCustomFactions"
require "ProjectALife/Records/ALifeCustomProfiles"

ProjectALife = ProjectALife or {}

local Share = { header = "@alife-pack 1", legacyHeader = "PALF1", maxBytes = 500000,
    retiredReason = "share_code_before_1_2" }
ProjectALife.FactionShare = Share

local Factions = ProjectALife.CustomFactions
local Profiles = ProjectALife.CustomProfiles

local function unfence(value)
    value = string.gsub(tostring(value or ""), "\r\n", "\n")
    value = string.gsub(value, "^%s*```[%w_%-]*\n", "")
    return string.gsub(value, "\n```%s*$", "")
end

local function validFaction(record)
    return type(record) == "table" and type(record.id) == "string"
        and string.match(record.id, "^[%w_%-]+$") ~= nil
        and type(record.general) == "table" and type(record.spawn) == "table"
end

Share.vanillaModId = "pz-vanilla"

Share.skipSections = { id = true, general = true, modules = true,
    moduleOverrides = true, outfitEnabled = true, outfitTints = true }
Share.engine = {}

function Share.engine.itemMod(fullType)
    local manager = type(getScriptManager) == "function" and getScriptManager() or nil
    if manager == nil or manager.FindItem == nil then return nil end
    local ok, script = pcall(function() return manager:FindItem(fullType) end)
    if not ok or script == nil then return nil end
    if script.getModID == nil then return Share.vanillaModId end
    local modOk, modId = pcall(function() return script:getModID() end)
    if not modOk or type(modId) ~= "string" or modId == "" then return Share.vanillaModId end
    return modId
end

function Share.engine.modInfo(modId)
    if type(getModInfoByID) ~= "function" then return nil, nil end
    local ok, info = pcall(getModInfoByID, modId)
    if not ok or info == nil then return nil, nil end
    local name, workshop = nil, nil
    if info.getName ~= nil then pcall(function() name = info:getName() end) end
    if info.getWorkshopID ~= nil then pcall(function() workshop = info:getWorkshopID() end) end
    return name, workshop
end

function Share.itemCandidates(profiles)
    local seen, list = {}, {}
    local function visit(value, depth)
        if depth > 6 then return end
        if type(value) == "table" then
            for key, child in pairs(value) do
                if depth > 0 or not Share.skipSections[key] then visit(child, depth + 1) end
            end
        elseif type(value) == "string" then
            for token in string.gmatch(value, "[^|,]+") do
                token = string.match(token, "^%s*(.-)%s*$")
                if not seen[token] and string.match(token, "^[%a_][%w_]*%.[%w_%-]+$") then
                    seen[token] = true
                    list[#list + 1] = token
                end
            end
        end
    end
    for _, profile in ipairs(type(profiles) == "table" and profiles or {}) do visit(profile, 0) end
    table.sort(list)
    return list
end

function Share.requirementsFor(profiles, engine)
    engine = engine or Share.engine
    local byId, order = {}, {}
    for _, fullType in ipairs(Share.itemCandidates(profiles)) do
        local modId = engine.itemMod(fullType)
        if modId ~= nil and modId ~= Share.vanillaModId then
            local mod = byId[modId]
            if mod == nil then
                local name, workshop = engine.modInfo(modId)
                mod = { id = modId, name = tostring(name or modId),
                    workshop = tostring(workshop or ""), items = {} }
                byId[modId] = mod
                order[#order + 1] = mod
            end
            mod.items[#mod.items + 1] = fullType
        end
    end
    return order
end

function Share.clean(value)
    return (string.gsub(tostring(value or ""), "[|\r\n]", "/"))
end

function Share.needsBlocks(requires)
    local Codec = ProjectALife.RecordCodec
    local blocks = {}
    for index, mod in ipairs(type(requires) == "table" and requires or {}) do
        local items = {}
        for _, item in ipairs(mod.items or {}) do items[#items + 1] = Share.clean(item) end
        local block = Codec.begin("needs", string.format("%d", index))
        Codec.put(block, "mod", "id", Share.clean(mod.id))
        Codec.put(block, "mod", "workshop", Share.clean(mod.workshop))
        Codec.put(block, "mod", "title", Share.clean(mod.name))
        Codec.put(block, "mod", "items", table.concat(items, "|"))
        blocks[#blocks + 1] = Codec.finish(block)
    end
    return blocks
end

function Share.needsFrom(record)
    local mod = type(record.mod) == "table" and record.mod or {}
    local items = {}
    for item in string.gmatch(tostring(mod.items or ""), "[^|]+") do items[#items + 1] = item end
    return { id = tostring(mod.id or ""), workshop = tostring(mod.workshop or ""),
        name = tostring(mod.title or ""), items = items }
end

function Share.missingFor(pack, engine)
    engine = engine or Share.engine
    local report = { mods = {}, items = {}, count = 0 }
    local vouched = {}
    for _, mod in ipairs(type(pack) == "table" and pack.requires or {}) do
        local lost = {}
        for _, item in ipairs(mod.items) do
            vouched[item] = true
            if engine.itemMod(item) == nil then lost[#lost + 1] = item end
        end
        if #lost > 0 then
            report.mods[#report.mods + 1] = { id = mod.id, name = mod.name,
                workshop = mod.workshop, items = lost }
            report.count = report.count + #lost
        end
    end
    for _, item in ipairs(Share.itemCandidates(type(pack) == "table" and pack.profiles or {})) do
        if not vouched[item] and engine.itemMod(item) == nil then
            report.items[#report.items + 1] = item
            report.count = report.count + 1
        end
    end
    if report.count == 0 then return nil end
    return report
end

function Share.describeMissing(report)
    local lines = { "This code uses items your game does not have.",
        "NPCs will spawn without them.", "" }
    local shown = 0
    for _, mod in ipairs(report.mods or {}) do
        if shown >= 4 then break end
        local where = mod.workshop ~= nil and mod.workshop ~= ""
            and (" - Workshop " .. mod.workshop) or ""
        lines[#lines + 1] = "Mod: " .. tostring(mod.name) .. where
            .. " (" .. string.format("%d", #mod.items) .. " items)"
        shown = shown + 1
    end
    if #(report.mods or {}) > shown then
        lines[#lines + 1] = "+ " .. string.format("%d", #report.mods - shown) .. " more mods"
    end
    local items = report.items or {}
    if #items > 0 then
        local names = {}
        for index = 1, math.min(3, #items) do names[index] = items[index] end
        lines[#lines + 1] = "Unknown items: " .. table.concat(names, ", ")
            .. (#items > 3 and (" + " .. string.format("%d", #items - 3) .. " more") or "")
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Import it anyway?"
    return table.concat(lines, "\n")
end

function Share.encode(faction, profiles)
    if not validFaction(faction) then return nil, "faction_required" end
    local validProfiles = {}
    for _, profile in ipairs(type(profiles) == "table" and profiles or {}) do
        if type(profile) == "table" and type(profile.id) == "string"
                and type(profile.general) == "table" then
            validProfiles[#validProfiles + 1] = profile
        end
    end
    local requires = Share.requirementsFor(validProfiles)
    local blocks = Share.needsBlocks(requires)
    blocks[#blocks + 1] = Factions.serializeFaction(faction)
    for _, profile in ipairs(validProfiles) do
        blocks[#blocks + 1] = Profiles.serializeProfile(profile)
    end
    local text = Share.header .. "\n" .. table.concat(blocks, "\n") .. "\n"
    if #text > Share.maxBytes then return nil, "pack_too_large" end
    return text, nil, requires
end

Share.codeHeader = "ALIFEPACK1"
Share.legacyCodeHeader = "PALF2"

Share.chainLimit = 16
Share.niceLength = 1024
Share.b64Char, Share.b64Value, Share.byteChar = {}, {}, {}
do
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for index = 1, 64 do
        local char = string.sub(alphabet, index, index)
        Share.b64Char[index - 1] = char
        Share.b64Value[char] = index - 1
    end
    for value = 0, 255 do Share.byteChar[value] = string.char(value) end
end

function Share.toUnits(text)
    local units, count = {}, 0
    for index = 1, #text do
        local unit = string.byte(text, index)
        if unit >= 256 or unit == 1 then
            units[count + 1] = 1
            units[count + 2] = math.floor(unit / 256)
            units[count + 3] = unit % 256
            count = count + 3
        else
            count = count + 1
            units[count] = unit
        end
    end
    return units, count
end

function Share.fromUnits(units, count)
    local parts, part, index = {}, 0, 1
    local byteChar = Share.byteChar
    while index <= count do
        local unit = units[index]
        if unit == 1 then
            if index + 2 > count then return nil end
            part = part + 1
            parts[part] = string.char(units[index + 1] * 256 + units[index + 2])
            index = index + 3
        else
            local char = byteChar[unit]
            if char == nil then return nil end
            part = part + 1
            parts[part] = char
            index = index + 1
        end
    end
    return table.concat(parts)
end

function Share.checksum(units, count)
    local sum = 0
    for index = 1, count do sum = (sum * 31 + units[index]) % 16777213 end
    return sum
end

function Share.compress(src, count)
    local out, size = {}, 0
    local head, prev = {}, {}
    local chainLimit, niceLength = Share.chainLimit, Share.niceLength
    local pending, position = 1, 1
    while position <= count do
        local bestLength, bestDistance = 0, 0
        if position + 3 <= count then
            local key = ((src[position] * 256 + src[position + 1]) * 256
                + src[position + 2]) * 256 + src[position + 3]
            local candidate, steps = head[key], 0
            local limit = count - position + 1
            if limit > 65535 then limit = 65535 end
            while candidate ~= nil and steps < chainLimit do
                local distance = position - candidate
                if distance > 65535 then break end

                if src[candidate + bestLength] == src[position + bestLength] then
                    local length = 0
                    while length < limit
                            and src[candidate + length] == src[position + length] do
                        length = length + 1
                    end
                    if length > bestLength then
                        bestLength, bestDistance = length, distance
                        if length >= niceLength then break end
                    end
                end
                candidate = prev[candidate]
                steps = steps + 1
            end
        end
        local advance = 1
        if bestLength >= 4 then
            size = Share.flushLiterals(src, pending, position, out, size)
            if bestLength < 130 then
                size = size + 1
                out[size] = bestLength + 124
            else
                out[size + 1] = 254
                out[size + 2] = math.floor(bestLength / 256)
                out[size + 3] = bestLength % 256
                size = size + 3
            end
            out[size + 1] = math.floor(bestDistance / 256)
            out[size + 2] = bestDistance % 256
            size = size + 2
            advance = bestLength
        end
        for index = position, position + advance - 1 do
            if index + 3 <= count then
                local key = ((src[index] * 256 + src[index + 1]) * 256
                    + src[index + 2]) * 256 + src[index + 3]
                prev[index] = head[key]
                head[key] = index
            end
        end
        position = position + advance
        if advance > 1 then pending = position end
    end
    size = Share.flushLiterals(src, pending, count + 1, out, size)
    return out, size
end

function Share.flushLiterals(src, from, to, out, size)
    while from < to do
        local run = to - from
        if run > 128 then run = 128 end
        size = size + 1
        out[size] = run - 1
        for index = from, from + run - 1 do
            size = size + 1
            out[size] = src[index]
        end
        from = from + run
    end
    return size
end

function Share.decompress(tokens, count, expected)
    local out, size, index = {}, 0, 1
    while index <= count do
        local token = tokens[index]
        index = index + 1
        if token < 128 then
            local run = token + 1
            if index + run - 1 > count or size + run > expected then return nil end
            for offset = 0, run - 1 do
                size = size + 1
                out[size] = tokens[index + offset]
            end
            index = index + run
        elseif token <= 254 then
            local length = token - 124
            if token == 254 then
                if index + 1 > count then return nil end
                length = tokens[index] * 256 + tokens[index + 1]
                index = index + 2
            end
            if index + 1 > count then return nil end
            local distance = tokens[index] * 256 + tokens[index + 1]
            index = index + 2
            local from = size - distance
            if distance < 1 or from < 0 or size + length > expected then return nil end
            for offset = 1, length do
                size = size + 1
                out[size] = out[from + offset]
            end
        else
            return nil
        end
    end
    if size ~= expected then return nil end
    return out, size
end

function Share.base64(units, count)
    local chars, parts, part = Share.b64Char, {}, 0
    for index = 1, count, 3 do
        local second, third = units[index + 1] or 0, units[index + 2] or 0
        local value = units[index] * 65536 + second * 256 + third
        parts[part + 1] = chars[math.floor(value / 262144)]
        parts[part + 2] = chars[math.floor(value / 4096) % 64]
        part = part + 2
        if index + 1 <= count then
            part = part + 1
            parts[part] = chars[math.floor(value / 64) % 64]
        end
        if index + 2 <= count then
            part = part + 1
            parts[part] = chars[value % 64]
        end
    end
    return table.concat(parts)
end

function Share.unbase64(text)
    local values, units, count = Share.b64Value, {}, 0
    local accumulator, bits = 0, 0
    for index = 1, #text do
        local char = string.sub(text, index, index)
        local value = values[char]
        if value ~= nil then
            accumulator = accumulator * 64 + value
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                local scale = 2 ^ bits
                count = count + 1
                units[count] = math.floor(accumulator / scale)
                accumulator = accumulator % scale
            end
        elseif char ~= " " and char ~= "\n" and char ~= "\r" and char ~= "\t" then
            break
        end
    end
    return units, count
end

function Share.toCode(text)
    if type(text) ~= "string" or #text == 0 then return nil, "pack_required" end
    local units, count = Share.toUnits(text)
    if count > Share.maxBytes then return nil, "pack_too_large" end
    local tokens, size = Share.compress(units, count)
    return Share.codeHeader .. "-" .. string.format("%d", count) .. "-"
        .. string.format("%d", Share.checksum(units, count)) .. "-"
        .. Share.base64(tokens, size)
end

function Share.fromCode(source, header)
    header = header or Share.codeHeader
    local at = string.find(tostring(source or ""), header .. "-", 1, true)
    if at == nil then return nil, "invalid_share_code" end
    local expectedText, sumText, body = string.match(string.sub(source, at + #header + 1),
        "^([%d%.]+)%-([%d%.]+)%-(.*)$")
    local expected, sum = tonumber(expectedText), tonumber(sumText)
    if expected == nil or sum == nil or body == nil then return nil, "invalid_share_code" end
    if expected < 1 or expected > Share.maxBytes then return nil, "pack_too_large" end
    local tokens, count = Share.unbase64(body)
    local ok, units, size = pcall(Share.decompress, tokens, count, expected)
    if not ok or units == nil then return nil, "share_code_incomplete" end
    if Share.checksum(units, size) ~= sum then return nil, "share_code_damaged" end
    local text = Share.fromUnits(units, size)
    if text == nil then return nil, "share_code_damaged" end
    return text
end

function Share.decode(source)
    source = unfence(source)
    if #source == 0 then return nil, "clipboard_empty" end
    if string.find(source, Share.codeHeader .. "-", 1, true) then
        local text, reason = Share.fromCode(source, Share.codeHeader)
        if text == nil then return nil, reason end
        source = text
    elseif string.find(source, Share.legacyCodeHeader .. "-", 1, true) then
        return nil, Share.retiredReason
    end
    if #source > Share.maxBytes then return nil, "pack_too_large" end
    if string.sub(source, 1, #Share.header + 1) == Share.header .. "\n" then
        return Share.decodePack(source)
    end
    if string.sub(source, 1, #Share.legacyHeader + 1) == Share.legacyHeader .. "\n" then
        return nil, Share.retiredReason
    end
    return nil, "invalid_faction_pack"
end

function Share.decodePack(source)
    local parsed = ProjectALife.RecordCodec.decode(source, { source = "pack", text = true })
    if parsed == nil then return nil, "invalid_faction_pack" end
    local factionRecords, memberRecords, requires = {}, {}, {}
    for _, record in ipairs(parsed.records) do
        if record.kind == "faction" then
            factionRecords[#factionRecords + 1] = record
        elseif record.kind == "member" then
            memberRecords[#memberRecords + 1] = record
        elseif record.kind == "needs" then
            requires[#requires + 1] = Share.needsFrom(record)
        else
            return nil, "invalid_faction_pack"
        end
    end
    local factions = Factions.fromRecords(factionRecords)
    if #factions ~= 1 or not validFaction(factions[1]) then
        return nil, "invalid_faction_record"
    end
    if factions[1].spawn.visitorOnly == true then Factions.forceVisitorSpawn(factions[1].spawn) end
    local profiles, reason = Profiles.fromRecords(memberRecords, true)
    if profiles == nil then return nil, reason or "invalid_profile_records" end
    profiles, reason = Profiles.checkAmmo(profiles)
    if profiles == nil then return nil, reason end
    for _, profile in ipairs(profiles) do
        if profile.general.faction ~= factions[1].id then
            return nil, "profile_belongs_to_another_faction"
        end
    end
    return { faction = factions[1], profiles = profiles, requires = requires }
end

function Share.importAsNew(source, newId)
    if type(newId) ~= "function" then return nil, "id_factory_required" end
    local pack, reason = Share.decode(source)
    if pack == nil then return nil, reason end
    return Share.adoptAsNew(pack, newId)
end

function Share.adoptAsNew(pack, newId)
    if type(newId) ~= "function" then return nil, "id_factory_required" end
    if type(pack) ~= "table" or pack.faction == nil then return nil, "invalid_faction_pack" end
    local faction = pack.faction
    faction.id = newId("custom_faction")
    for _, profile in ipairs(pack.profiles) do
        profile.id = newId("custom_npc")
        profile.general.faction = faction.id
    end
    return faction, pack.profiles
end

return Share
