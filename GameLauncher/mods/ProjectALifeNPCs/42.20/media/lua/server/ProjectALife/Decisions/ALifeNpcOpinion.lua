require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Decisions/ALifeReputation"

ProjectALife = ProjectALife or {}

local Opinion = {
    minimum = -100,
    maximum = 100,
    keep = 8,
    groupShare = 50,
    factionShare = 20,
    factionCap = 16,
    rateMs = 5000,
    lastAt = {},
    events = {
        gift = { 8, "You shared food or water with them." },
        medicine = { 12, "You patched someone up." },
        help_fight = { 15, "You fought beside them." },
        saved = { 25, "You saved a life." },
        trade = { 3, "You dealt fairly." },
        promise = { 5, "You kept your word." },
        door_kind = { 6, "You treated them well at the door." },
        walk = { 3, "You walked the road together." },
        threat_failed = { -6, "You threatened them and it did not work." },
        rude = { -4, "You were rude to them." },
        robbery = { -25, "You took things from them." },
        hit = { -20, "You hit one of theirs." },
        killed_mate = { -45, "You killed one of their own." },
        betrayal = { -60, "You broke a deal." },
        party_task = { 6, "You came through for the group." },
        party_fail = { -4, "You let the group down on a job." },
        party_desert = { -8, "You left them when it mattered." },
    },
    public = { robbery = true, killed_mate = true, betrayal = true },
    stanceValue = { hostile = -40, careful = -15, neutral = 0, friendly = 18, allied = 30 },
    tierValue = { bad = -22, neutral = 0, good = 22 },
    temperamentValue = { fresh = 4, seasoned = 0, veteran = -3, predator = -6 },
    labels = {
        { -71, "Hates you" },
        { -41, "Resents you" },
        { -16, "Distrusts you" },
        { 16, "Unsure of you" },
        { 41, "Likes you" },
        { 71, "Trusts you" },
        { 101, "Would stand by you" },
    },
    infoTopics = { ASK_NEWS = true, ASK_DANGER = true, ASK_LOOT_SPOT = true, ASK_ADVICE = true,
        ASK_WHAT_HAPPENED = true, ASK_ABOUT_ME = true },
    doorEvents = { DOOR_GIVE = "gift", DOOR_TREAT = "medicine", DOOR_TRADE_CONFIRM = "trade", DOOR_PAY = "trade",
        DOOR_INVITE = "door_kind", DOOR_LEND = "door_kind", DOOR_HAND_GUNS = "door_kind", DOOR_TREAT_ME = "door_kind",
        DOOR_JOB = "promise", DOOR_BLUFF = "threat_failed", DOOR_LEAVE_RUDE = "rude" },
    metrics = { notes = 0, learned = 0, refused = 0, attached = 0 },
}
ProjectALife.NpcOpinion = Opinion

function Opinion.sandbox(key, fallback)
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(vars) ~= "table" then return fallback end
    local value = vars[key]
    if value == nil then return fallback end
    return value
end

function Opinion.enabled()
    if type(isClient) == "function" and isClient() == true and not (type(isServer) == "function" and isServer() == true) then
        return false
    end
    return Opinion.sandbox("Reputation_NpcOpinion", true) ~= false
end

function Opinion.percent(key, fallback, low, high)
    local value = tonumber(Opinion.sandbox(key, fallback))
    if value == nil or value ~= value then value = fallback end
    return math.max(low, math.min(high, value))
end

function Opinion.scale() return Opinion.percent("Reputation_NpcOpinionScale", 100, 25, 300) / 100 end
function Opinion.effects() return Opinion.percent("Reputation_NpcOpinionEffects", 100, 0, 200) / 100 end
function Opinion.decay() return Opinion.percent("Reputation_NpcOpinionDecay", 3, 0, 20) end

function Opinion.hours()
    if type(getGameTime) ~= "function" then return 0 end
    local clock = getGameTime()
    if clock == nil or type(clock.getWorldAgeHours) ~= "function" then return 0 end
    return tonumber(clock:getWorldAgeHours()) or 0
end

function Opinion.nowMs()
    if type(getTimestampMs) == "function" then return tonumber(getTimestampMs()) or 0 end
    return math.floor(os.time() * 1000)
end

function Opinion.clamp(value)
    return math.max(Opinion.minimum, math.min(Opinion.maximum, math.floor((tonumber(value) or 0) + 0.5)))
end

function Opinion.keyOf(player)
    if type(player) == "string" then return player end
    local reputation = ProjectALife.Reputation
    if player == nil or reputation == nil or type(reputation.playerKey) ~= "function" then return nil end
    local ok, key = pcall(reputation.playerKey, player)
    if ok and key ~= nil then return tostring(key) end
    return nil
end

function Opinion.recordOf(ref)
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.read) ~= "function" or ref == nil then return nil end
    if type(ref) == "string" then return registry.read(ref) end
    if type(ref) == "table" and ref.uid ~= nil then return registry.read(ref.uid) or ref end
    if type(ref.getModData) == "function" then
        local ok, data = pcall(ref.getModData, ref)
        if ok and type(data) == "table" and data.ProjectALifeUID ~= nil then return registry.read(data.ProjectALifeUID) end
    end
    return nil
end

function Opinion.spread(record)
    local uid = tostring(record.uid or "")
    local sum = 0
    for index = 1, #uid do sum = (sum + string.byte(uid, index) * index) % 997 end
    local value = (sum % 7) - 3
    local roles = ProjectALife.DialogueRoles
    if roles ~= nil and type(roles.describe) == "function" then
        local ok, who = pcall(roles.describe, record, 0)
        if ok and type(who) == "table" then value = value + (Opinion.temperamentValue[tostring(who.temperament)] or 0) end
    end
    return math.max(-10, math.min(10, value))
end

function Opinion.baseline(record, player)
    local base = 0
    local relations = ProjectALife.Relations
    if relations ~= nil and type(relations.playerStance) == "function" then
        local ok, word = pcall(relations.playerStance, record, player)
        if ok and word ~= nil then base = base + (Opinion.stanceValue[tostring(word)] or 0) end
    end
    local personal = ProjectALife.PersonalRep
    if personal ~= nil and personal.enabled == true and type(personal.band) == "function" then
        local ok, band = pcall(personal.band, player)
        if ok and band ~= nil then base = base + (Opinion.tierValue[tostring(band)] or 0) end
    end
    return Opinion.clamp(base + Opinion.spread(record))
end

function Opinion.rowOf(record, key)
    local memory = type(record) == "table" and record.memory or nil
    local map = type(memory) == "table" and memory.opinion or nil
    return type(map) == "table" and key ~= nil and type(map[key]) == "table" and map[key] or nil
end

function Opinion.drift(row, base, now)
    local value = tonumber(row.v) or base
    local days = math.max(0, (now - (tonumber(row.at) or now)) / 24)
    local step = Opinion.decay() * days
    if value > base then value = math.max(base, value - step) elseif value < base then value = math.min(base, value + step) end
    return value
end

function Opinion.valueOf(record, player)
    local key = Opinion.keyOf(player)
    local base = Opinion.baseline(record, player)
    local row = Opinion.rowOf(record, key)
    if row == nil then return base, nil, base end
    return Opinion.clamp(Opinion.drift(row, base, Opinion.hours())), row, base
end

function Opinion.labelOf(value)
    for _, entry in ipairs(Opinion.labels) do
        if value < entry[1] then return entry[2] end
    end
    return Opinion.labels[#Opinion.labels][2]
end

function Opinion.payload(record, player)
    if not Opinion.enabled() or type(record) ~= "table" or player == nil then return nil end
    local value, row = Opinion.valueOf(record, player)
    local reason = row ~= nil and type(row.why) == "string" and row.why or "A stranger so far, judged by what they have heard."
    return { value = value, label = Opinion.labelOf(value), reason = reason }
end

function Opinion.write(uid, mutate)
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.read) ~= "function" or type(registry.update) ~= "function" then return false end
    local current = registry.read(uid)
    if current == nil then return false end
    local ok, updated = pcall(registry.update, current.uid, current.revision, function(record)
        record.memory = type(record.memory) == "table" and record.memory or {}
        mutate(record.memory)
    end)
    return ok and updated ~= nil and updated ~= false
end

function Opinion.store(memory, key, base, now)
    memory.opinion = type(memory.opinion) == "table" and memory.opinion or {}
    local row = memory.opinion[key]
    if type(row) ~= "table" then
        row = { v = base, at = now }
        memory.opinion[key] = row
    end
    local count, oldestKey, oldest = 0, nil, math.huge
    for other, entry in pairs(memory.opinion) do
        count = count + 1
        local at = type(entry) == "table" and tonumber(entry.at) or -math.huge
        if other ~= key and at < oldest then oldestKey, oldest = other, at end
    end
    if count > Opinion.keep and oldestKey ~= nil then memory.opinion[oldestKey] = nil end
    return row
end

function Opinion.touch(record, player)
    local key = Opinion.keyOf(player)
    if key == nil or Opinion.rowOf(record, key) ~= nil then return false end
    local base, now = Opinion.baseline(record, player), Opinion.hours()
    return Opinion.write(record.uid, function(memory) Opinion.store(memory, key, base, now) end)
end

function Opinion.adjust(record, player, delta, why, extra)
    local key = Opinion.keyOf(player)
    if key == nil or type(record) ~= "table" or record.uid == nil then return false end
    local base, now = Opinion.baseline(record, player), Opinion.hours()
    local drift = Opinion.drift
    return Opinion.write(record.uid, function(memory)
        local row = Opinion.store(memory, key, base, now)
        local current = drift(row, base, now)
        row.v = Opinion.clamp(current + delta)
        row.at = now
        local weight = math.abs(delta)
        if weight >= (tonumber(row.w) or 0) * 0.6 then
            row.why, row.w = why, weight
        else
            row.w = (tonumber(row.w) or 0) * 0.9
        end
        if type(extra) == "function" then extra(memory) end
    end)
end

function Opinion.rounded(value)
    if value >= 0 then return math.max(1, math.floor(value + 0.5)) end
    return math.min(-1, -math.floor(-value + 0.5))
end

function Opinion.spreadTo(record, player, delta, why, wide)
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.each) ~= "function" then return 0 end
    local memory = type(record.memory) == "table" and record.memory or {}
    local group, faction = memory.groupId, record.factionId
    local heard, seen, wideSeen = {}, 0, 0
    registry.each(function(other)
        if other.uid ~= record.uid and other.lifecycle ~= "dead" and type(other.memory) == "table" then
            if group ~= nil and other.memory.groupId == group then
                heard[#heard + 1] = { other, Opinion.groupShare }
            elseif wide and faction ~= nil and other.factionId == faction and wideSeen < Opinion.factionCap then
                wideSeen = wideSeen + 1
                heard[#heard + 1] = { other, Opinion.factionShare }
            end
        end
        seen = seen + 1
        return seen > 4000
    end)
    local count = 0
    for _, entry in ipairs(heard) do
        local share = Opinion.rounded(delta * entry[2] / 100)
        if Opinion.adjust(entry[1], player, share, "Word reached them: " .. string.lower(string.sub(why, 1, 1)) .. string.sub(why, 2)) then
            count = count + 1
        end
    end
    Opinion.metrics.learned = Opinion.metrics.learned + count
    return count
end

function Opinion.note(kind, ref, player, options)
    if not Opinion.enabled() then return false end
    local event = Opinion.events[kind]
    if event == nil or player == nil then return false end
    local key = Opinion.keyOf(player)
    if key == nil then return false end
    local record = Opinion.recordOf(ref)
    if record == nil then return false end
    local social = ProjectALife.TalkSocial
    if social ~= nil and type(social.deedAllowed) == "function" and social.deedAllowed(kind, record, player) ~= true then
        return false
    end
    local limit = tostring(record.uid) .. ":" .. key .. ":" .. kind
    local now = Opinion.nowMs()
    if kind == "hit" and now - (Opinion.lastAt[limit] or -1e12) < Opinion.rateMs then return false end
    Opinion.lastAt[limit] = now
    local delta = Opinion.rounded(event[1] * Opinion.scale())
    Opinion.metrics.notes = Opinion.metrics.notes + 1
    local extra = nil
    if social ~= nil and type(social.deedStamp) == "function" then extra = social.deedStamp(kind, player) end
    local own = options ~= nil and options.skipOwn == true or Opinion.adjust(record, player, delta, event[2], extra)
    local party = ProjectALife.Party
    if party ~= nil and type(party.onOpinion) == "function" then pcall(party.onOpinion, kind, record, player) end
    local personal = ProjectALife.PersonalRep
    if personal ~= nil and type(personal.onOpinion) == "function" and not (type(options) == "table" and options.door == true) then
        pcall(personal.onOpinion, kind, record, player)
    end
    local wide = Opinion.public[kind] == true or (type(options) == "table" and options.witnessed == true)
    Opinion.spreadTo(record, player, delta, event[2], wide)
    return own
end

function Opinion.noteKill(victim, killerKey, killer)
    if not Opinion.enabled() or type(victim) ~= "table" then return false end
    local player = killer or killerKey
    local event = Opinion.events.killed_mate
    local delta = Opinion.rounded(event[1] * Opinion.scale())
    local memory = type(victim.memory) == "table" and victim.memory or {}
    if memory.groupId == nil then return false end
    local registry = ProjectALife.ActorRegistry
    local mates = {}
    registry.each(function(other)
        if other.uid ~= victim.uid and other.lifecycle ~= "dead" and type(other.memory) == "table"
                and other.memory.groupId == memory.groupId then
            mates[#mates + 1] = other
        end
        return false
    end)
    for _, mate in ipairs(mates) do Opinion.adjust(mate, player, delta, event[2]) end
    Opinion.spreadTo(victim, player, delta, event[2], true)
    return #mates > 0
end

function Opinion.noteDoor(intent, record, player)
    local kind = Opinion.doorEvents[tostring(intent)]
    if kind == nil then return false end
    return Opinion.note(kind, record, player, { door = true })
end

function Opinion.attach(result, uid, player)
    if type(result) ~= "table" or not Opinion.enabled() then return result end
    local record = Opinion.recordOf(uid)
    if record == nil then return result end
    Opinion.touch(record, player)
    result.opinion = Opinion.payload(Opinion.recordOf(uid) or record, player)
    if result.opinion ~= nil then Opinion.metrics.attached = Opinion.metrics.attached + 1 end
    return result
end

function Opinion.priceFactor(record, player)
    local strength = Opinion.effects()
    if not Opinion.enabled() or strength <= 0 or type(record) ~= "table" then return 1 end
    local value = Opinion.valueOf(record, player)
    if value <= -30 then return 1 + 0.15 * strength end
    if value >= 30 then return 1 - 0.1 * strength end
    return 1
end

function Opinion.dealRefusal(record, player)
    if not Opinion.enabled() or Opinion.effects() <= 0 or type(record) ~= "table" then return false end
    return Opinion.valueOf(record, player) < -25
end

function Opinion.orderShift(record, player)
    local strength = Opinion.effects()
    if not Opinion.enabled() or strength <= 0 or type(record) ~= "table" then return 0 end
    return math.floor(Opinion.valueOf(record, player) / 6 * strength + 0.5)
end

function Opinion.refusalText(kind, record, player, fallback)
    local social = ProjectALife.TalkSocial
    if social ~= nil and type(social.text) == "function" then
        local text = social.text(kind, record, player)
        if text ~= nil then return text end
    end
    return fallback
end

function Opinion.talkRefusal(player, record, choice)
    local strength = Opinion.effects()
    if not Opinion.enabled() or strength <= 0 or type(choice) ~= "table" or type(record) ~= "table" then return nil end
    local value = Opinion.valueOf(record, player)
    local shift = (strength - 1) * 10
    if Opinion.infoTopics[choice.id] and value < -25 - shift then
        Opinion.metrics.refused = Opinion.metrics.refused + 1
        return Opinion.refusalText("TALK_NO_INFO", record, player, "I'm not telling you anything.")
    end
    if choice.id == "ASK_HOME" and value < 10 - shift then
        Opinion.metrics.refused = Opinion.metrics.refused + 1
        return Opinion.refusalText("TALK_NOT_FAMILIAR", record, player, "I don't know you well enough for that.")
    end
    if choice.id == "WALK_WITH_ME" and value < 25 - shift then
        Opinion.metrics.refused = Opinion.metrics.refused + 1
        return Opinion.refusalText("TALK_NOT_YET", record, player, "Not yet. Ask me when I trust you more.")
    end
    return nil
end

function Opinion.greetTone(record, player)
    if not Opinion.enabled() or type(record) ~= "table" then return "plain" end
    local value = Opinion.valueOf(record, player)
    if value < -15 then return "cold" end
    if value >= 35 then return "warm" end
    return "plain"
end

function Opinion.factionMood(factionId, keys)
    local registry = ProjectALife.ActorRegistry
    if not Opinion.enabled() or registry == nil or type(registry.each) ~= "function" or factionId == nil
            or type(keys) ~= "table" or #keys == 0 then return nil end
    local sum, count, seen = 0, 0, 0
    local now = Opinion.hours()
    registry.each(function(record)
        seen = seen + 1
        if record.factionId == factionId and type(record.memory) == "table" and type(record.memory.opinion) == "table" then
            for _, key in ipairs(keys) do
                local row = record.memory.opinion[key]
                if type(row) == "table" then
                    sum, count = sum + Opinion.clamp(Opinion.drift(row, tonumber(row.v) or 0, now)), count + 1
                end
            end
        end
        return seen > 4000
    end)
    if count == 0 then return nil end
    return sum / count
end

function Opinion.betrayScale(factionId, keys)
    local strength = Opinion.effects()
    if strength <= 0 then return 1 end
    local mood = Opinion.factionMood(factionId, keys)
    if mood == nil then return 1 end
    return math.max(0.4, math.min(1.8, 1 - mood / 150 * strength))
end

function Opinion.reset()
    Opinion.lastAt = {}
    Opinion.metrics = { notes = 0, learned = 0, refused = 0, attached = 0 }
    return true
end

return Opinion
