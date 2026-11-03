require "ProjectALife/Records/ALifeFactionSpawnRules"

ProjectALife = ProjectALife or {}

local Layers = {
    professionPrefix = "player:",
    folderPrefix = "folder:",
    blocPrefix = "bloc_",

    rungs = { careful = 1, neutral = 2, friendly = 3 },
    ladder = { "careful", "neutral", "friendly" },
    cacheMs = 10000,
    cacheLimit = 64,
    cache = {},
    cacheSize = 0,
    professionKeys = {},
    folderKeys = {},
    blocKeys = {},
}
ProjectALife.RelationLayers = Layers

Layers.shifts = {
    policeofficer = { law = 1, rescue = 1, crime = -1, gang = -1, club = -1, prison = -1, raider = -1 },
    securityguard = { law = 1, worker = 1, crime = -1 },
    fireofficer = { rescue = 1, law = 1, civilian = 1, family = 1 },
    parkranger = { law = 1, rescue = 1, civilian = 1 },
    veteran = { law = 1, raider = -1 },
    doctor = { rescue = 1, civilian = 1, family = 1 },
    nurse = { rescue = 1, civilian = 1, family = 1 },
    burglar = { crime = 1, gang = 1, law = -1, family = -1 },
    farmer = { family = 1, civilian = 1 },
    rancher = { family = 1, civilian = 1 },
    carpenter = { worker = 1 },
    constructionworker = { worker = 1 },
    electrician = { worker = 1 },
    engineer = { worker = 1 },
    lumberjack = { worker = 1 },
    mechanics = { worker = 1 },
    metalworker = { worker = 1 },
    repairman = { worker = 1 },
    smither = { worker = 1 },
    burgerflipper = {},
    chef = {},
    fisherman = {},
    fitnessinstructor = {},
    tailor = {},
    unemployed = {},
}

function Layers.word(value)
    if value == nil then return nil end
    value = string.lower(tostring(value))
    if value == "suspicious" then return "careful" end
    if value == "allied" or value == "friendly" or value == "neutral"
            or value == "careful" or value == "hostile" then
        return value
    end
    return nil
end

function Layers.memo(cache, prefix, id)
    local key = cache[id]
    if key == nil then
        key = prefix .. tostring(id)
        cache[id] = key
    end
    return key
end

function Layers.professionKey(professionId)
    return Layers.memo(Layers.professionKeys, Layers.professionPrefix, professionId)
end

function Layers.folderKey(factionId)
    return Layers.memo(Layers.folderKeys, Layers.folderPrefix, factionId)
end

function Layers.blocKey(bloc)
    return Layers.memo(Layers.blocKeys, Layers.blocPrefix, bloc)
end

function Layers.blocOf(faction)
    local rules = ProjectALife.FactionSpawnRules
    if rules ~= nil and type(rules.blocOf) == "function" then
        local bloc = rules.blocOf(faction)
        if bloc ~= nil then return bloc end
    end
    if type(faction) == "table" and type(faction.relations) == "table" then
        return faction.relations.bloc
    end
    return nil
end

function Layers.shifted(word, delta)
    local rung = Layers.rungs[word]
    delta = tonumber(delta) or 0
    if rung == nil or delta == 0 then return word end
    rung = math.max(1, math.min(#Layers.ladder, rung + delta))
    return Layers.ladder[rung]
end

function Layers.professionEnabled()
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    return type(vars) == "table" and vars.ProfessionAffectsAttitude == true
end

function Layers.shiftFor(faction, professionId)
    if not Layers.professionEnabled() then return 0, nil end
    if professionId == nil then return 0, nil end
    local row = Layers.shifts[professionId]
    if row == nil then return 0, nil end
    local bloc = Layers.blocOf(faction)
    if bloc == nil then return 0, nil end
    return tonumber(row[bloc]) or 0, bloc
end

function Layers.inheritedTowardPlayer(faction, professionId)
    if type(faction) ~= "table" then return nil, nil, 0, nil end
    local relations = type(faction.relations) == "table" and faction.relations or nil
    local word, layer = nil, "faction"
    if relations ~= nil then word = Layers.word(relations.player) end
    if word == nil then
        layer, word = "legacy", "hostile"
        if type(faction.spawn) == "table" and faction.spawn.peaceable == true then word = "friendly" end
    end
    local shift, bloc = Layers.shiftFor(faction, professionId)
    if layer == "faction" and word == "friendly" and shift < 0 then shift = 0 end
    local moved = Layers.shifted(word, shift)
    if moved ~= word then return moved, "profession_default", shift, bloc end
    return word, layer, shift, bloc
end

function Layers.towardPlayer(faction, professionId)
    if type(faction) ~= "table" then return nil, nil end
    if Layers.professionEnabled() and professionId ~= nil and type(faction.relations) == "table" then
        local explicit = Layers.word(faction.relations[Layers.professionKey(professionId)])
        if explicit ~= nil then return explicit, "profession" end
    end
    local word, layer = Layers.inheritedTowardPlayer(faction, professionId)
    return word, layer
end

function Layers.inheritedTowardFaction(source, target)
    if type(source) ~= "table" or type(target) ~= "table" then return nil, nil, nil end
    local relations = type(source.relations) == "table" and source.relations or nil
    local bloc = Layers.blocOf(target)
    if relations ~= nil then
        if bloc ~= nil then
            local byBloc = Layers.word(relations[Layers.blocKey(bloc)])
            if byBloc ~= nil then return byBloc, "bloc", bloc end
        end
        local fallback = Layers.word(relations.unknown)
        if fallback ~= nil then return fallback, "unknown", bloc end
    end
    local sourceFriendly = type(source.spawn) == "table" and source.spawn.peaceable == true
    local targetFriendly = type(target.spawn) == "table" and target.spawn.peaceable == true
    if sourceFriendly and targetFriendly then return "friendly", "legacy", bloc end
    return "hostile", "legacy", bloc
end

function Layers.towardFaction(source, target)
    if type(source) ~= "table" or type(target) ~= "table" then return nil, nil end
    local relations = type(source.relations) == "table" and source.relations or nil
    if relations ~= nil and target.id ~= nil then
        local word = Layers.word(relations[Layers.folderKey(target.id)])
        if word ~= nil then return word, "folder" end
        word = Layers.word(relations[target.id])
        if word ~= nil then return word, "faction" end
    end
    local word, layer = Layers.inheritedTowardFaction(source, target)
    return word, layer
end

function Layers.now()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return 0
end

function Layers.professionId(profession)
    local kind = type(profession)
    if kind ~= "userdata" and kind ~= "table" then return nil end
    if type(profession.getName) ~= "function" then return nil end
    local name = profession:getName()
    if name == nil then return nil end
    local id = (string.gsub(string.lower(tostring(name)), "[^%w_%-%.]", "_"))
    if id == "" then return nil end
    return id
end

function Layers.readProfession(player)
    if type(instanceof) == "function" then
        local ok, isPlayer = pcall(instanceof, player, "IsoPlayer")
        if not ok or isPlayer ~= true then return nil, false end
    end
    if type(player.getDescriptor) ~= "function" then return nil, false end
    local descriptor = player:getDescriptor()
    if descriptor == nil or type(descriptor.getCharacterProfession) ~= "function" then return nil, true end
    return Layers.professionId(descriptor:getCharacterProfession()), true
end

function Layers.professionOf(player)
    local kind = type(player)
    if kind ~= "userdata" and kind ~= "table" then return nil end
    local now = Layers.now()
    local entry = Layers.cache[player]
    if entry ~= nil and now < entry.untilMs then return entry.id end
    local id, isPlayer = Layers.readProfession(player)
    if not isPlayer then return nil end
    if entry == nil then
        if Layers.cacheSize >= Layers.cacheLimit then Layers.forget() end
        entry = {}
        Layers.cache[player] = entry
        Layers.cacheSize = Layers.cacheSize + 1
    end
    entry.id, entry.untilMs = id, now + Layers.cacheMs
    return id
end

function Layers.forget()
    Layers.cache, Layers.cacheSize = {}, 0
end

return Layers
