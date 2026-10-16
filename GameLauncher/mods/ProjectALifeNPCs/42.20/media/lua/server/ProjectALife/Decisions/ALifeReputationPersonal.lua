require "ProjectALife/Decisions/ALifeReputation"
require "ProjectALife/Records/ALifeRepLevels"
require "ProjectALife/Records/ALifeRepStamps"
require "ProjectALife/Core/ALifePlayerLocator"

ProjectALife = ProjectALife or {}

local Reputation = ProjectALife.Reputation
local Levels = ProjectALife.RepLevels
local PlayerLocator = ProjectALife.PlayerLocator
local Personal = {
    TAG = "ProjectALife.PersonalRep.v1",
    SCHEMA = 1,
    adapters = {},
    storage = nil,
    dirty = false,
    enabled = true,
    settings = {
        showScore = true,
        showOthers = false,

        driftPerDay = 5,

        killScale = 100,

        gainCapPerDay = 60,
        overCapPercent = 25,
        hysteresis = 15,

        npcFightIsHostile = true,
        robberyKeepMs = 1800000,
        kill = { hostile = 10, crime = 15, neutral = -40, careful = -40, friendly = -80,
            surrendered = -100, attackedFirst = 0, unknown = 0 },
        deedWeight = { surrendered = 5, friendly = 4, neutral = 3, careful = 3, spree = 2,
            hostile = 1, crime = 1 },
        deed = { let_in = 5, let_sleep = 10, treated_wounded = 10, sheltered_chased = 10, neighbour_watch = 6,
            gave_food = 5, fair_trade = 3, census_answer = 2, finished_job = 12, answered_call = 12,
            helped_fight = 6, walk = 2, party_task = 5, kind_word = 1,
            robbery = -12, betrayal = -20, party_desert = -4, party_fail = -2, threat_failed = -2 },
        deedPerDay = { let_in = 2, let_sleep = 2, treated_wounded = 2, sheltered_chased = 2, neighbour_watch = 1,
            gave_food = 3, fair_trade = 2, census_answer = 1, finished_job = 2, answered_call = 2, helped_fight = 3,
            walk = 2, party_task = 3, robbery = 3, betrayal = 2, kind_word = 1 },
        deedPerDayDefault = 2,
        deedCapPercent = 150,
        hostBonusPerHour = 1,
        hostBonusMax = 6,
        deedKeepDays = 7,
        spreeKills = 3,
        countedRing = 64,
        stampKeys = 4,
        othersMax = 8,
        spawnHours = 2,
        safehouseRudeNo = -2,
        radioNames = true,
        radioBadNews = true,
        radioHoldHours = 6,
        radioDelayHours = 2,
        radioCooldownHours = 48,
    },
    metrics = { kills = 0, counted = 0, lives = 0, deaths = 0, drifted = 0, capped = 0, overCapCredited = 0, byClass = {} },
}
ProjectALife.PersonalRep = Personal

function Personal.nowHours()
    if type(Personal.adapters.nowHours) == "function" then
        return tonumber(Personal.adapters.nowHours()) or 0
    end
    if type(getGameTime) == "function" then
        local time = getGameTime()
        if time ~= nil and type(time.getWorldAgeHours) == "function" then
            return tonumber(time:getWorldAgeHours()) or 0
        end
    end
    return 0
end

function Personal.nowMs()
    if type(Personal.adapters.nowMs) == "function" then return tonumber(Personal.adapters.nowMs()) or 0 end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return 0
end

function Personal.authoritative()
    local value = Personal.adapters.authoritative
    if type(value) == "function" then return value() == true end
    if value ~= nil then return value == true end
    return not (type(isClient) == "function" and isClient()
        and (type(isServer) ~= "function" or not isServer()))
end

function Personal.day(hours)
    return math.floor((tonumber(hours) or 0) / 24)
end

function Personal.store()
    if Personal.storage ~= nil then return Personal.storage end
    local result
    if type(Personal.adapters.getOrCreate) == "function" then
        result = Personal.adapters.getOrCreate(Personal.TAG)
    elseif ModData ~= nil and type(ModData.getOrCreate) == "function" then
        result = ModData.getOrCreate(Personal.TAG)
    end
    if type(result) ~= "table" then return nil, "mod_data_unavailable" end
    if result.schema == nil then
        result.schema = Personal.SCHEMA
        result.players = {}
        Personal.dirty = true
    elseif result.schema ~= Personal.SCHEMA then
        return nil, "personal_schema_unsupported:" .. tostring(result.schema)
    end
    if type(result.players) ~= "table" then result.players = {} end
    Personal.storage = result
    return result
end

function Personal.freshRow(now)
    local day = Personal.day(now)
    return {
        life = 1, score = 0, level = Levels.neutralId(), day = day, gained = 0, dgained = 0, driftAt = now,
        dead = false, kills = { day = day, n = 0 }, radio = {}, counted = {},
    }
end

function Personal.normalise(row, now)
    row.life = math.max(1, math.floor(tonumber(row.life) or 1))
    row.score = Levels.clamp(row.score)
    if Levels.rowOf(row.level) == nil then row.level = Levels.at(row.score).id end
    row.day = tonumber(row.day) or Personal.day(now)
    row.gained = tonumber(row.gained) or 0
    row.dgained = tonumber(row.dgained) or 0
    if row.dn ~= nil and type(row.dn) ~= "table" then row.dn = nil end
    row.driftAt = tonumber(row.driftAt) or now
    if type(row.kills) ~= "table" then row.kills = { day = row.day, n = 0 } end
    if type(row.radio) ~= "table" then row.radio = {} end
    if type(row.counted) ~= "table" then row.counted = {} end
    return row
end

function Personal.isPlayer(player)
    if player == nil or type(player) == "string" then return false end
    if type(instanceof) == "function" then return instanceof(player, "IsoPlayer") == true end
    return type(player.getUsername) == "function"
end

function Personal.playerFor(key, hint)
    if Personal.isPlayer(hint) and Reputation.playerKey(hint) == key then return hint end
    for _, player in ipairs(PlayerLocator.list(Reputation.adapters.players)) do
        if Reputation.playerKey(player) == key then return player end
    end
    return nil
end

function Personal.keyOf(playerOrKey)
    if type(playerOrKey) == "string" then
        if playerOrKey == "" then return nil end
        return playerOrKey
    end
    return Reputation.playerKey(playerOrKey)
end

function Personal.hoursSurvived(player)
    if not Personal.isPlayer(player) or type(player.getHoursSurvived) ~= "function" then return nil end
    return tonumber(player:getHoursSurvived())
end

function Personal.isDead(player)
    if player == nil or type(player.isDead) ~= "function" then return false end
    return player:isDead() == true
end

function Personal.characterName(player)
    if not Personal.isPlayer(player) or type(player.getDescriptor) ~= "function" then return nil end
    local descriptor = player:getDescriptor()
    if descriptor == nil then return nil end
    local parts = {}
    if type(descriptor.getForename) == "function" then parts[#parts + 1] = descriptor:getForename() end
    if type(descriptor.getSurname) == "function" then parts[#parts + 1] = descriptor:getSurname() end
    local name = table.concat(parts, " ")
    if name == "" then return nil end
    return name
end

function Personal.townAt(x, y)
    local regions = ProjectALife.TownRegions
    if regions == nil or type(regions.distanceToTown) ~= "function" or tonumber(x) == nil then return nil end
    local distance, town = regions.distanceToTown({ x = tonumber(x), y = tonumber(y) })
    if town == nil or (tonumber(distance) or math.huge) > 600 then return nil end
    return town.label
end

function Personal.positionOf(object)
    if object == nil or type(object.getX) ~= "function" or type(object.getY) ~= "function" then return nil, nil end
    return object:getX(), object:getY()
end

function Personal.startLife(row, player, now, hours)
    row.name = Personal.characterName(player)
    row.spawn = nil
    if hours ~= nil and hours < Personal.settings.spawnHours then
        row.spawn = Personal.townAt(Personal.positionOf(player))
    end
    row.hours = hours
end

function Personal.refreshLife(row, player, now)
    if not Personal.isPlayer(player) or Personal.isDead(player) then return false end
    local hours = Personal.hoursSurvived(player)
    local renewed = row.dead == true
    if not renewed and hours ~= nil and tonumber(row.hours) ~= nil and hours + 0.01 < tonumber(row.hours) then
        renewed = true
    end
    if renewed then
        local day = Personal.day(now)
        row.life = row.life + 1
        row.score, row.level = 0, Levels.neutralId()
        row.day, row.gained, row.dgained, row.driftAt = day, 0, 0, now
        row.deed, row.counted, row.dn, row.doorCounted = nil, {}, nil, nil
        row.kills = { day = day, n = 0 }
        row.radio = { optOut = row.radio.optOut }
        row.dead = false
        Personal.startLife(row, player, now, hours)
        Personal.metrics.lives = Personal.metrics.lives + 1
        Personal.dirty = true
        return true
    end
    if hours ~= nil then row.hours = hours end
    return false
end

function Personal.applyDrift(row, now)
    local perDay = tonumber(Personal.settings.driftPerDay) or 0
    local since = tonumber(row.driftAt) or now
    if since > now or perDay <= 0 or row.score == 0 or not Levels.drifts(row.level) then
        row.driftAt = now
        return 0
    end
    local steps = math.floor((now - since) * perDay / 24)
    if steps <= 0 then return 0 end
    local magnitude = math.abs(row.score)
    if steps > magnitude then steps = magnitude end
    if row.score > 0 then row.score = row.score - steps else row.score = row.score + steps end
    if row.score == 0 then
        row.driftAt = now
    else
        row.driftAt = since + steps * 24 / perDay
    end
    local previous = row.level
    row.level = Levels.at(row.score, row.level, Personal.settings.hysteresis).id
    Personal.noteRadioLevel(row, previous, now)
    Personal.metrics.drifted = Personal.metrics.drifted + steps
    Personal.dirty = true
    return steps
end

function Personal.rowFor(key, player, create)
    if type(key) ~= "string" then return nil, "player_required" end
    local state, reason = Personal.store()
    if state == nil then return nil, reason end
    local now = Personal.nowHours()
    local row = state.players[key]
    if row ~= nil and type(row) ~= "table" then
        state.players[key] = nil
        row = nil
        Personal.dirty = true
    end
    if row == nil then
        if create ~= true then return nil, "no_row" end
        row = Personal.freshRow(now)
        state.players[key] = row
        Personal.startLife(row, player, now, Personal.hoursSurvived(player))
        Personal.dirty = true
    else
        Personal.normalise(row, now)
    end
    Personal.refreshLife(row, player, now)
    Personal.applyDrift(row, now)
    return row
end

function Personal.overCapCredit(change, room)
    local cap = tonumber(Personal.settings.gainCapPerDay) or 0
    local share = tonumber(Personal.settings.overCapPercent) or 0
    if cap <= 0 or share <= 0 then return room end
    local extra = math.max(1, math.floor((change - room) * share / 100 + 0.5))
    return math.min(change, room + extra)
end

function Personal.deedCap()
    local cap = tonumber(Personal.settings.gainCapPerDay) or 0
    return math.floor(cap * (tonumber(Personal.settings.deedCapPercent) or 100) / 100 + 0.5)
end

function Personal.rollDay(row, now)
    local day = Personal.day(now)
    if row.day ~= day then row.day, row.gained, row.dgained, row.dn = day, 0, 0, nil end
    return day
end

function Personal.adjust(row, delta, now, hostileKill, bucket)
    local change = tonumber(delta) or 0
    Personal.rollDay(row, now)
    if change > 0 then
        local field, cap = "gained", tonumber(Personal.settings.gainCapPerDay) or 0
        if bucket == "deed" then field, cap = "dgained", Personal.deedCap() end
        local room = math.max(0, cap - (tonumber(row[field]) or 0))
        if change > room then
            if hostileKill == true then
                change = Personal.overCapCredit(change, room)
                Personal.metrics.overCapCredited = (Personal.metrics.overCapCredited or 0) + 1
            else
                change = room
            end
            Personal.metrics.capped = Personal.metrics.capped + 1
        end
        row[field] = (tonumber(row[field]) or 0) + change
    end
    local before = row.score
    row.score = Levels.clamp(before + change)
    local previous = row.level
    row.level = Levels.at(row.score, row.level, Personal.settings.hysteresis).id
    Personal.noteRadioLevel(row, previous, now)
    return row.score - before, previous
end

function Personal.announce(player, cause, applied, from)
    local change = tonumber(applied) or 0
    if change == 0 or Personal.enabled ~= true or player == nil then return false end
    local payload = { cause = tostring(cause or ""), gain = change > 0, delta = change }
    local row = Personal.rowFor(Reputation.playerKey(player), player, false)
    if row ~= nil then
        payload.level = row.level
        if from ~= nil and from ~= row.level then payload.from = from end
        if Personal.settings.showScore ~= false then payload.score = row.score end
    end
    local track = ProjectALife.RepTrack
    if track ~= nil and type(track.decorate) == "function" then pcall(track.decorate, player, payload) end
    if type(isServer) == "function" and isServer() == true then
        if type(sendServerCommand) ~= "function" then return false end
        return pcall(sendServerCommand, player, "ProjectALife", "repPopup", payload)
    end
    local screen = ProjectALife.RepScreen
    if screen == nil or type(screen.popup) ~= "function" then return false end
    return pcall(screen.popup, payload, player)
end

function Personal.noteRadioLevel(row, previous, now)
    if previous == row.level then return end
    row.radio = type(row.radio) == "table" and row.radio or {}
    row.radio.levelAt = now
end

function Personal.deedValue(kind, extra)
    local base = tonumber(Personal.settings.deed[kind])
    if base == nil then return nil end
    local hosted = type(extra) == "table" and tonumber(extra.hosted) or nil
    if kind == "let_sleep" and hosted ~= nil and hosted > 0 then
        local bonus = math.floor(hosted * (tonumber(Personal.settings.hostBonusPerHour) or 0))
        base = base + math.max(0, math.min(tonumber(Personal.settings.hostBonusMax) or 0, bonus))
    end
    return base
end

function Personal.kindRoom(row, kind, day)
    local counts = row.dn
    if type(counts) ~= "table" or counts.day ~= day or type(counts.n) ~= "table" then
        counts = { day = day, n = {} }
        row.dn = counts
    end
    local limit = tonumber(Personal.settings.deedPerDay[kind]) or tonumber(Personal.settings.deedPerDayDefault) or 1
    if (counts.n[kind] or 0) >= limit then return false end
    counts.n[kind] = (counts.n[kind] or 0) + 1
    return true
end

function Personal.tokenSeen(row, token)
    row.doorCounted = type(row.doorCounted) == "table" and row.doorCounted or {}
    for _, saved in ipairs(row.doorCounted) do if saved == token then return true end end
    row.doorCounted[#row.doorCounted + 1] = token
    while #row.doorCounted > Personal.settings.countedRing do table.remove(row.doorCounted, 1) end
    return false
end

function Personal.credit(player, key, kind, token, extra)
    local base = Personal.deedValue(kind, extra)
    if base == nil then return false, "personal_deed_unsupported" end
    if type(token) ~= "string" or #token < 1 or #token > 160 then return false, "deed_token_required" end
    if player == nil or Personal.isDead(player) then return false, "player_unavailable" end
    local row, why = Personal.rowFor(key, player, true)
    if row == nil then return false, why end
    if Personal.tokenSeen(row, token) then return false, "deed_replayed" end
    local now = Personal.nowHours()
    if not Personal.kindRoom(row, kind, Personal.rollDay(row, now)) then
        Personal.metrics.deedHeld = (Personal.metrics.deedHeld or 0) + 1
        Personal.dirty = true
        return true, 0, "kind_limit"
    end
    local value = Personal.scaled(base)
    local changed, from
    if value > 0 then
        changed, from = Personal.adjust(row, value, now, false, "deed")
    else
        changed, from = Personal.adjust(row, value, now)
    end
    Personal.dirty = true
    Personal.metrics.deeds = (Personal.metrics.deeds or 0) + 1
    if changed ~= 0 then
        if Personal.isPlayer(player) then pcall(Reputation.sync, player) end
        Personal.announce(player, "deed_" .. kind, changed, from)
    end
    return true, changed
end

function Personal.onDeed(kind, key, factionId, uid, token, extra)
    if Personal.enabled ~= true then return false, "personal_disabled" end
    if not Personal.authoritative() then return false, "client_authority" end
    if kind ~= "rude_no" then
        if Personal.settings.deed[kind] == nil then return false, "personal_deed_unsupported" end
        if type(token) ~= "string" or #token < 1 or #token > 160 then return false, "deed_token_required" end
        return Personal.credit(Personal.playerFor(key), key, kind, token, extra)
    end
    if type(token) ~= "string" or #token < 1 or #token > 160 then return false, "deed_token_required" end
    local player = Personal.playerFor(key)
    if player == nil or Personal.isDead(player) then return false, "player_unavailable" end
    local row, why = Personal.rowFor(key, player, true)
    if row == nil then return false, why end
    if Personal.tokenSeen(row, token) then return false, "deed_replayed" end
    local delta = math.min(0, tonumber(Personal.settings.safehouseRudeNo) or -2)
    local changed, from = Personal.adjust(row, delta, Personal.nowHours())
    Personal.dirty = true
    Personal.announce(player, "door_rude", changed, from)
    return true, changed
end

Personal.opinionKinds = { walk = true, party_task = true, party_desert = true, party_fail = true, robbery = true,
    betrayal = true, threat_failed = true }

function Personal.onOpinion(kind, record, player)
    if Personal.opinionKinds[kind] ~= true or Personal.enabled ~= true or not Personal.authoritative() then return false end
    if type(record) ~= "table" or record.uid == nil or not Personal.isPlayer(player) then return false end
    local key = Reputation.playerKey(player)
    if key == nil then return false end
    local token = tostring(record.uid) .. ":" .. kind .. ":" .. tostring(Personal.day(Personal.nowHours()))
    return Personal.credit(player, key, kind, token) == true
end

function Personal.setRadioOptOut(player, optOut)
    if not Personal.authoritative() or not Personal.isPlayer(player) or type(optOut) ~= "boolean" then return false end
    local key = Reputation.playerKey(player)
    if key == nil then return false end
    local row = Personal.rowFor(key, player, true)
    if row == nil then return false end
    row.radio.optOut = optOut
    Personal.dirty = true
    if type(Reputation.sync) == "function" then Reputation.sync(player) end
    return true
end

function Personal.onRaidSurvived(player, raid)
    if Personal.enabled == false or not Personal.authoritative() or not Personal.isPlayer(player)
            or Personal.isDead(player) or type(raid) ~= "table" or raid.raidId == nil then return false end
    local key = Reputation.playerKey(player)
    if key == nil then return false end
    local row = Personal.rowFor(key, player, true)
    if row == nil or row.dead == true then return false end
    local previous = row.radio.raid
    if type(previous) == "table" and previous.id == raid.raidId then return false end
    local now = Personal.nowHours()
    row.radio.raid = { id = raid.raidId, at = now, place = Personal.townAt(raid.objectiveX, raid.objectiveY) }
    Personal.dirty = true
    return true
end

function Personal.scaled(value)
    local scaled = (tonumber(value) or 0) * (tonumber(Personal.settings.killScale) or 100) / 100
    if scaled >= 0 then return math.floor(scaled + 0.5) end
    return -math.floor(-scaled + 0.5)
end

function Personal.stamp(map, key, hours, firstOnly)
    return ProjectALife.RepStamps.stamp(map, key, hours, firstOnly, Personal.settings.stampKeys)
end

function Personal.modData(shell)
    if shell == nil or type(shell.getModData) ~= "function" then return nil end
    local data = shell:getModData()
    if type(data) ~= "table" then return nil end
    return data
end

function Personal.fighting(actor)
    local talk = ProjectALife.Talk
    if talk ~= nil and type(talk.inCombat) == "function" then return talk.inCombat(actor) == true end
    local activity, intent = tostring(actor.activity or ""), tostring(actor.intent or "")
    return activity == "combat" or string.find(intent, "attack", 1, true) ~= nil
        or string.find(intent, "engage", 1, true) ~= nil or string.find(intent, "manhunt", 1, true) ~= nil
end

function Personal.surrendered(shell, killer, nowMs)
    if shell == nil then return false end
    local animations = ProjectALife.Animations
    if animations ~= nil and type(animations.current) == "table" and animations.current[shell] == "surrender" then
        return true
    end
    local data = Personal.modData(shell)
    if data ~= nil and data.ProjectALifeHeldAct == "surrender" then return true end
    local panic = ProjectALife.ModulePanic
    if Personal.isPlayer(killer) and panic ~= nil and type(panic.fearLive) == "function"
            and type(panic.fearsThis) == "function" then
        return panic.fearLive(shell, nowMs) == true and panic.fearsThis(shell, killer) == true
    end
    return false
end

function Personal.unarmed(shell)
    if shell == nil then return false end
    if type(shell.getPrimaryHandItem) == "function" then
        local item = shell:getPrimaryHandItem()
        if item ~= nil then
            local weapon = type(item.IsWeapon) == "function" and item:IsWeapon() == true
            local fullType
            if type(item.getFullType) == "function" then fullType = item:getFullType() end
            if weapon and fullType ~= "Base.BareHands" then return false end
        end
    end
    local data = Personal.modData(shell)
    if data == nil then return false end
    local active = data.ProjectALifeActiveWeaponType
    if type(active) == "string" and active ~= "" and active ~= "Base.BareHands" then return false end
    return data.ProjectALifeEquippedSlot == "none"
end

function Personal.preStance(actor, player)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if memory.hostileOverride == true then return "hostile" end
    if memory.hostileOverride == false then return "friendly" end
    local relations = ProjectALife.Relations
    if relations ~= nil and type(relations.baselineStance) == "function" then
        return (relations.baselineStance(actor, player))
    end
    return Reputation.defaultStatus(actor, player)
end

function Personal.fightingOther(actor, killerKey)
    if not Personal.fighting(actor) then return false end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local kind = memory.combatTargetKind
    if kind == "actor" then return Personal.settings.npcFightIsHostile ~= false end
    if kind == "player" then
        local other = memory.combatTargetPlayerKey
        return type(other) == "string" and other ~= killerKey
    end
    return false
end

function Personal.engagedFirst(actor, killerKey)
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local engaged = type(memory.engagedAt) == "table" and tonumber(memory.engagedAt[killerKey]) or nil
    if engaged == nil then return false end
    local hit = type(memory.hitByAt) == "table" and tonumber(memory.hitByAt[killerKey]) or nil
    return hit == nil or engaged < hit
end

Personal.blocMemo = {}

function Personal.repBlocOf(actor)
    local memoKey = type(actor) == "table" and actor.factionId or nil
    local memo = memoKey ~= nil and Personal.blocMemo[memoKey] or nil
    if memo ~= nil then return memo end
    local found = Personal.resolveBloc(actor)
    if found ~= nil and memoKey ~= nil and ProjectALife.Catalog ~= nil
            and type(ProjectALife.Catalog.faction) == "function" and ProjectALife.Catalog.faction(memoKey) ~= nil then
        Personal.blocMemo[memoKey] = found
    end
    return found
end

function Personal.resolveBloc(actor)
    local catalog, rules = ProjectALife.Catalog, ProjectALife.FactionSpawnRules
    local faction
    if catalog ~= nil and type(catalog.faction) == "function" and actor.factionId ~= nil then
        faction = catalog.faction(actor.factionId)
    end
    local bloc
    if rules ~= nil and type(rules.blocOf) == "function" then bloc = rules.blocOf(faction) end
    local repBloc = Levels.repBlocOf(bloc, actor.factionId)
    if repBloc ~= nil then return repBloc end
    local roles = ProjectALife.DialogueRoles
    if roles ~= nil and type(roles.describe) == "function" then
        local role = roles.describe(actor, Personal.day(Personal.nowHours()))
        if type(role) == "table" then return Levels.repBlocOfRegister(role.register) end
    end
    return nil
end

function Personal.firstContact(player, actor, authored)
    if Personal.enabled == false or not Personal.authoritative() or type(actor) ~= "table" then return nil end
    if authored == "hostile" then return nil end
    local cell, word = Levels.cell(Personal.levelId(player), Personal.repBlocOf(actor))
    if cell == nil then return nil end
    if authored == "allied" and cell.stance ~= "friendly" and cell.stance ~= "neutral" then return "neutral" end
    return word
end

function Personal.robberyMode(player, actor)
    if Personal.enabled == false or not Personal.authoritative() or type(actor) ~= "table" then return nil end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    if memory.spawnStance ~= nil or memory.hostileOverride ~= nil then return nil end
    local key = Personal.keyOf(player)
    if type(memory.hostileToPlayerKeys) == "table" and memory.hostileToPlayerKeys[key] == true then return nil end
    local reputation = ProjectALife.Reputation
    if reputation ~= nil and type(reputation.recordedStatus) == "function"
            and reputation.recordedStatus(player, actor) ~= nil then return nil end
    if Personal.repBlocOf(actor) ~= "crime" then return nil end
    return Levels.robbery(Personal.levelId(player))
end

function Personal.counted(row, token)
    for _, seen in ipairs(row.counted) do
        if seen == token then return true end
    end
    return false
end

function Personal.remember(row, token)
    row.counted[#row.counted + 1] = token
    local ring = math.max(1, math.floor(tonumber(Personal.settings.countedRing) or 64))
    while #row.counted > ring do table.remove(row.counted, 1) end
end

function Personal.classify(actor, shell, killerKey, killer, row, nowMs)
    if type(actor) ~= "table" or type(killerKey) ~= "string" then return "unknown" end
    if row ~= nil then
        local token = tostring(actor.uid) .. ":" .. tostring(actor.generation)
        if Personal.counted(row, token) then return "counted" end
    end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local robbedAt = type(memory.robbedAt) == "table" and tonumber(memory.robbedAt[killerKey]) or nil
    if robbedAt ~= nil and math.abs((tonumber(nowMs) or 0) - robbedAt) <= Personal.settings.robberyKeepMs then
        if Personal.repBlocOf(actor) == "crime" then return "crime" end
        return "hostile"
    end
    local fighting = Personal.fighting(actor)
    if Personal.surrendered(shell, killer, nowMs) or (not fighting and Personal.unarmed(shell)) then
        return "surrendered"
    end
    local pre = Personal.preStance(actor, killer or killerKey)
    if pre == "hostile" or Personal.fightingOther(actor, killerKey) then
        local repBloc = Personal.repBlocOf(actor)
        if repBloc == "crime" or repBloc == "raider" then return "crime" end
        return "hostile"
    end
    if Personal.engagedFirst(actor, killerKey) then return "attackedFirst" end
    if pre == "allied" then return "friendly" end
    if pre == "neutral" or pre == "careful" or pre == "friendly" then return pre end
    return "unknown"
end

function Personal.noteKill(row, class, actor, shell, now)
    local day = Personal.day(now)
    if tonumber(row.kills.day) ~= day then row.kills = { day = day, n = 0 } end
    row.kills.n = (tonumber(row.kills.n) or 0) + 1
    row.radio = type(row.radio) == "table" and row.radio or {}
    if row.kills.n >= 3 and tonumber(row.radio.spreeDay) ~= day then
        row.radio.spreeDay, row.radio.spreeAt = day, now
    end
    local kind = class
    if class == "hostile" or class == "crime" then
        row.kills.hostile = (tonumber(row.kills.hostile) or 0) + 1
        if row.kills.hostile >= Personal.settings.spreeKills then kind = "spree" end
    end
    local weight = Personal.settings.deedWeight[kind]
    if weight == nil then return false end
    local deed = row.deed
    local stale = type(deed) == "table" and day - (tonumber(deed.day) or day) > Personal.settings.deedKeepDays
    if type(deed) == "table" and not stale and weight < (tonumber(deed.weight) or 0) then return false end
    local x, y = Personal.positionOf(shell)
    if x == nil and type(actor.worldPosition) == "table" then x, y = actor.worldPosition.x, actor.worldPosition.y end
    row.deed = { kind = kind, place = Personal.townAt(x, y), day = day, weight = weight }
    return true
end

function Personal.onActorKilled(actor, shell, killerKey, killer)
    if Personal.enabled == false then return false, "disabled" end
    if not Personal.authoritative() then return false, "server_authority_required" end
    if type(actor) ~= "table" or actor.uid == nil then return false, "actor_required" end
    local key = killerKey
    if type(key) ~= "string" and killer ~= nil then key = Reputation.playerKey(killer) end
    if type(key) ~= "string" then return false, "player_required" end
    local live = Personal.playerFor(key, killer)
    local row, reason = Personal.rowFor(key, live, true)
    if row == nil then return false, reason end
    if row.dead == true then return false, "player_dead" end
    local class = Personal.classify(actor, shell, key, live or killer, row, Personal.nowMs())
    if class == "counted" then
        Personal.metrics.counted = Personal.metrics.counted + 1
        return false, "counted"
    end
    Personal.remember(row, tostring(actor.uid) .. ":" .. tostring(actor.generation))
    local now = Personal.nowHours()
    local applied, from = Personal.adjust(row, Personal.scaled(Personal.settings.kill[class]), now,
        class == "hostile" or class == "crime")
    Personal.noteKill(row, class, actor, shell, now)
    Personal.metrics.kills = Personal.metrics.kills + 1
    Personal.metrics.byClass[class] = (Personal.metrics.byClass[class] or 0) + 1
    Personal.dirty = true
    if live ~= nil then pcall(Reputation.sync, live) end
    Personal.announce(live, "kill_" .. class, applied, from)
    return true, class, applied
end

function Personal.forgetPlayer(key)
    if Personal.enabled == false or not Personal.authoritative() or type(key) ~= "string" then return false end
    local state = Personal.store()
    local row = state ~= nil and state.players[key] or nil
    if type(row) ~= "table" or row.dead == true then return false end
    row.dead = true
    Personal.dirty = true
    return true
end

function Personal.onPlayerDied(player)
    if Personal.enabled == false then return false, "disabled" end
    if not Personal.authoritative() then return false, "server_authority_required" end
    local key = Reputation.playerKey(player)
    if key == nil then return false, "player_required" end
    if Personal.isPlayer(player) and type(player.isDead) == "function" and player:isDead() ~= true then
        return false, "alive"
    end
    local state, reason = Personal.store()
    if state == nil then return false, reason end
    local row = state.players[key]
    if type(row) ~= "table" then return false, "no_row" end
    if row.dead == true then return false, "unchanged" end
    row.dead = true
    Personal.metrics.deaths = Personal.metrics.deaths + 1
    Personal.dirty = true
    return true
end

function Personal.othersFor(key)
    local state = Personal.store()
    if state == nil then return nil end
    local list = {}
    for _, player in ipairs(PlayerLocator.list(Reputation.adapters.players)) do
        local other = Reputation.playerKey(player)
        local row = other ~= nil and other ~= key and state.players[other] or nil
        if type(row) == "table" and type(row.name) == "string" and Levels.rowOf(row.level) ~= nil then
            list[#list + 1] = { name = row.name, level = row.level }
            if #list >= Personal.settings.othersMax then break end
        end
    end
    return list
end

function Personal.snapshotFor(player)
    if Personal.enabled == false then return nil end
    local key = Reputation.playerKey(player)
    if key == nil then return nil end
    local row = Personal.rowFor(key, player, true)
    if row == nil then return nil end
    local result = { level = row.level, band = Levels.band(row.level), life = row.life,
        radioOptOut = row.radio.optOut == true }
    if Personal.settings.showScore ~= false then result.score = row.score end
    if Personal.settings.showOthers == true then result.others = Personal.othersFor(key) end
    local track = ProjectALife.RepTrack
    if track ~= nil and type(track.decorate) == "function" then pcall(track.decorate, player, result) end
    return result
end

function Personal.stampActor(shell, field, playerKey)
    if Personal.enabled == false or not Personal.authoritative() or type(playerKey) ~= "string" then return false end
    local data = Personal.modData(shell)
    local uid = type(data) == "table" and data.ProjectALifeUID or nil
    local registry = ProjectALife.ActorRegistry
    if uid == nil or registry == nil or type(registry.read) ~= "function" or type(registry.update) ~= "function" then return false end
    local actor = registry.read(uid)
    if actor == nil then return false end
    local now = Personal.nowMs()
    local ok = registry.update(uid, actor.revision, function(record)
        record.memory = type(record.memory) == "table" and record.memory or {}
        local map = type(record.memory[field]) == "table" and record.memory[field] or {}
        record.memory[field] = (Personal.stamp(map, playerKey, now, field == "engagedAt"))
    end)
    return ok ~= nil and ok ~= false
end

function Personal.noteHit(player, shell)
    if not Personal.isPlayer(player) then return false end
    return Personal.stampActor(shell, "hitByAt", Reputation.playerKey(player))
end

function Personal.noteEngaged(shell, player)
    if not Personal.isPlayer(player) then return false end
    return Personal.stampActor(shell, "engagedAt", Reputation.playerKey(player))
end

Personal.recognizeOn = true
Personal.recognizeDays = 7
Personal.recognizePercent = 20
Personal.recognizedBy = {
    policeofficer = "law", parkranger = "law", securityguard = "law", veteran = "military",
    fireofficer = "civilian", doctor = "civilian", nurse = "civilian",
}
Personal.recognizeLines = {
    policeofficer = "Wait, you were a cop, weren't you? You've still got the look",
    parkranger = "Ranger, right? You walk like you know the woods",
    securityguard = "Security, right? I'd know that walk anywhere",
    veteran = "You served, didn't you? It's in how you stand",
    fireofficer = "Fire department, yeah? I remember you from before",
    doctor = "You're a doctor, aren't you? Thank God, we could use you",
    nurse = "You're a nurse, right? Thank God, we could use you",
    other = "Don't I know you? From before all this, I mean",
}

function Personal.recognize(player, record, shell)
    if Personal.enabled ~= true or Personal.recognizeOn == false or not Personal.authoritative() then return nil end
    if type(record) ~= "table" or not Personal.isPlayer(player) then return nil end
    local key = Reputation.playerKey(player)
    local layers = ProjectALife.RelationLayers
    if key == nil or layers == nil or type(layers.professionOf) ~= "function" then return nil end
    local memory = type(record.memory) == "table" and record.memory or {}
    if type(memory.recognized) == "table" and memory.recognized[key] ~= nil then return nil end
    local day = Personal.nowHours() / 24
    if day >= Personal.recognizeDays then return nil end
    local strength = day <= 4 and 1 or math.max(0, (Personal.recognizeDays - day) / (Personal.recognizeDays - 4))
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.update) ~= "function" then return nil end
    registry.update(record.uid, record.revision, function(entry)
        entry.memory = type(entry.memory) == "table" and entry.memory or {}
        entry.memory.recognized = type(entry.memory.recognized) == "table" and entry.memory.recognized or {}
        entry.memory.recognized[key] = true
    end)
    local roll = type(ZombRand) == "function" and ZombRand(100) or 100
    if roll >= Personal.recognizePercent * strength then return nil end
    local profession = layers.professionOf(player)
    if profession == nil then return nil end
    local wanted = Personal.recognizedBy[profession]
    local bloc = Personal.repBlocOf(record)
    if wanted ~= nil and bloc ~= wanted then return nil end
    if wanted == nil and bloc ~= "civilian" and bloc ~= "family" then return nil end
    return Personal.recognizeLines[profession] or Personal.recognizeLines.other
end

Personal.mentionLines = {
    bad = {
        "Heard on the roads that {player} is going by {title} now - keep your doors shut and stay clear{extra}",
        "Folks are talking about {player}, the one they call {title} - nobody's got a good word for them{extra}",
    },
    neutral = {
        "Somebody new out there, {player}{from} - nobody knows much about them yet{extra}",
        "Keep an ear out for {player}{from}, quiet so far{extra}",
    },
    good = {
        "Good word going round about {player}, folks started calling them {title} - say hi if you see them{extra}",
        "{player} keeps turning up where help's needed, folks call them {title} now{extra}",
    },
}
Personal.mentionExtra = {
    spree = " - word is there's been a lot of fighting{place} lately",
    raid = " - and they held their ground against a raid{place}",
}

function Personal.mentionTrigger(row, now)
    local radio, settings = row.radio, Personal.settings
    if type(radio) ~= "table" or radio.optOut == true or row.dead == true then return nil end
    if now - (tonumber(radio.mentionAt) or -math.huge) < settings.radioCooldownHours then return nil end
    local best, bestAt
    local function consider(kind, at, marker)
        at = tonumber(at)
        if at ~= nil and radio[marker] ~= at and (bestAt == nil or at < bestAt) then best, bestAt = kind, at end
    end
    if tonumber(radio.levelAt) ~= nil and now - radio.levelAt >= settings.radioHoldHours then
        consider("level", radio.levelAt, "levelAired")
    end
    if tonumber(radio.spreeAt) ~= nil and now - radio.spreeAt >= settings.radioDelayHours then
        consider("spree", radio.spreeAt, "spreeAired")
    end
    local raid = radio.raid
    if type(raid) == "table" and now - (tonumber(raid.at) or now) >= settings.radioDelayHours then
        consider("raid", raid.at, "raidAired")
    end
    return best, bestAt
end

function Personal.mentionText(row, kind)
    local band = Levels.band(row.level)
    local pool = Personal.mentionLines[band] or Personal.mentionLines.neutral
    local lineIndex = type(ZombRand) == "function" and ZombRand(#pool) + 1 or 1
    local rowInfo = Levels.rowOf(row.level)
    local place = kind == "spree" and type(row.deed) == "table" and row.deed.place or nil
    if kind == "raid" and type(row.radio.raid) == "table" then place = row.radio.raid.place end
    local extra = Personal.mentionExtra[kind] or ""
    local near = type(place) == "string" and place ~= "" and (" near " .. place) or ""
    extra = string.gsub(extra, "{place}", function() return near end)
    local text = pool[lineIndex]
    local from = type(row.spawn) == "string" and row.spawn ~= "" and (" out of " .. row.spawn) or ""
    text = string.gsub(text, "{player}", function() return tostring(row.name or "a survivor") end)
    text = string.gsub(text, "{title}", function() return tostring(rowInfo and rowInfo.en or "") end)
    text = string.gsub(text, "{from}", function() return from end)
    text = string.gsub(text, "{extra}", function() return extra end)
    return text
end

function Personal.nextMention(now)
    if Personal.enabled == false or not Personal.authoritative() or Personal.settings.radioNames ~= true then return nil end
    local state = Personal.store()
    if state == nil then return nil end
    local pickRow, pickKind, pickAt
    for _, row in pairs(state.players) do
        if type(row) == "table" and type(row.radio) == "table" then
            local kind, at = Personal.mentionTrigger(row, now)
            if kind ~= nil and (pickAt == nil or at < pickAt) then pickRow, pickKind, pickAt = row, kind, at end
        end
    end
    if pickRow == nil then return nil end
    local marker = pickKind == "level" and "levelAired" or pickKind == "spree" and "spreeAired" or "raidAired"
    pickRow.radio[marker] = pickKind == "raid" and pickRow.radio.raid.at or pickAt
    pickRow.radio.mentionAt = now
    Personal.dirty = true
    if Levels.band(pickRow.level) == "bad" and Personal.settings.radioBadNews ~= true then return nil end
    return Personal.mentionText(pickRow, pickKind)
end

Personal.deedWords = {
    surrendered = "you shot someone who had already given up",
    friendly = "you killed people who were on your side",
    neutral = "you killed someone who meant you no harm",
    careful = "you killed someone who only wanted to be left alone",
    spree = "you went through a lot of people in one day",
    hostile = "you put down people who came looking for trouble",
    crime = "you dealt with a gang of crooks",
}

function Personal.aboutLine(player)
    if Personal.enabled == false then return "Can't say I've heard anything about you" end
    local view = Personal.view(player) or {}
    local row = Levels.rowOf(view.level)
    local text
    if row == nil or row.neutral == true then
        text = "Haven't heard a thing about you, which around here is usually good"
    else
        text = "People around here call you " .. tostring(row.en) .. "."
    end
    if type(view.deed) == "table" and Personal.deedWords[view.deed.kind] ~= nil then
        local place = type(view.deed.place) == "string" and view.deed.place ~= "" and (" near " .. view.deed.place) or ""
        text = text .. " Word is " .. Personal.deedWords[view.deed.kind] .. place .. "."
    end
    return text
end

function Personal.levelId(playerOrKey)
    if Personal.enabled == false then return nil end
    local key = Personal.keyOf(playerOrKey)
    local player
    if type(playerOrKey) ~= "string" then player = playerOrKey end
    local row = Personal.rowFor(key, player, false)
    return row and row.level or nil
end

function Personal.band(playerOrKey)
    return Levels.band(Personal.levelId(playerOrKey))
end

function Personal.view(playerOrKey, hint)
    if Personal.enabled == false or not Personal.authoritative() then return nil end
    local key = Personal.keyOf(playerOrKey)
    if key == nil then return nil end
    local player = hint
    if type(playerOrKey) ~= "string" then player = playerOrKey end
    player = Personal.playerFor(key, player)
    local row = Personal.rowFor(key, player, false)
    if row == nil then return nil end
    local result = { level = row.level, band = Levels.band(row.level), tier = Levels.tiers(row.level)[1], spawn = row.spawn }
    local deed = row.deed
    local deedDay = type(deed) == "table" and tonumber(deed.day) or nil
    local day = Personal.day(Personal.nowHours())
    if deedDay ~= nil and day >= deedDay and day - deedDay <= Personal.settings.deedKeepDays then
        result.deed = { kind = deed.kind, place = deed.place, day = deedDay, weight = deed.weight }
    end
    return result
end

function Personal.word(playerOrKey)
    local row = Levels.rowOf(Personal.levelId(playerOrKey))
    return row and row.en or nil
end

function Personal.score(playerOrKey)
    if Personal.enabled == false then return nil end
    local row = Personal.rowFor(Personal.keyOf(playerOrKey), nil, false)
    return row and row.score or nil
end

function Personal.houseView(residentKeys)
    if Personal.enabled == false or type(residentKeys) ~= "table" then return nil end
    local total, count, lowestKey, lowestScore = 0, 0, nil, nil
    for _, entry in ipairs(residentKeys) do
        local key = Personal.keyOf(entry)
        if key ~= nil then
            local row = Personal.rowFor(key, nil, false)
            local score = 0
            if row ~= nil then score = row.score end
            total, count = total + score, count + 1
            if lowestScore == nil or score < lowestScore then lowestKey, lowestScore = key, score end
        end
    end
    if count == 0 then return nil end
    local average = total / count
    local rounded
    if average >= 0 then rounded = math.floor(average + 0.5) else rounded = -math.floor(-average + 0.5) end
    return { average = average, averageLevel = Levels.at(rounded).id, lowestKey = lowestKey, lowestScore = lowestScore }
end

Personal.refusedTopics = { ASK_FOOD = true, ASK_ADVICE = true, ASK_HOME = true, JOIN_REQUEST = true, WALK_WITH_ME = true }
Personal.pricePercent = { bad = 120, neutral = 100, good = 90 }

function Personal.priceFactor(player)
    if Personal.enabled == false or not Personal.authoritative() then return 1 end
    local percent = Personal.pricePercent[Personal.band(player) or "neutral"] or 100
    return percent / 100
end

function Personal.talkRefusal(player, record, choice, stance)
    if Personal.enabled == false or not Personal.authoritative() or type(choice) ~= "table" then return nil end
    local band = Personal.band(player)
    if band == nil then return nil end
    if choice.id == "WALK_WITH_ME" and band ~= "good" then return "Maybe once I know you a little better" end
    if band == "bad" and stance ~= "friendly" and Personal.refusedTopics[choice.id] == true then
        local bloc = Personal.repBlocOf(record)
        if bloc == "civilian" or bloc == "family" or bloc == "law" then return "I've heard about you, so back off" end
    end
    return nil
end

function Personal.configure(options)
    options = type(options) == "table" and options or {}
    Personal.blocMemo = {}
    if options.enabled ~= nil then Personal.enabled = options.enabled ~= false end
    local settings = Personal.settings
    for _, name in ipairs({ "showScore", "showOthers", "npcFightIsHostile", "radioNames", "radioBadNews" }) do
        if type(options[name]) == "boolean" then settings[name] = options[name] end
    end
    for _, name in ipairs({ "driftPerDay", "killScale", "gainCapPerDay", "overCapPercent", "hysteresis" }) do
        if tonumber(options[name]) ~= nil then settings[name] = tonumber(options[name]) end
    end
    if type(options.kill) == "table" then
        for class, value in pairs(options.kill) do
            if settings.kill[class] ~= nil and tonumber(value) ~= nil then settings.kill[class] = tonumber(value) end
        end
    end
    if type(options.adapters) == "table" then Personal.adapters = options.adapters end
    Personal.storage = nil
    return true
end

function Personal.reset()
    local state = Personal.store()
    if state ~= nil then
        state.schema, state.players = Personal.SCHEMA, {}
        Personal.dirty = true
    end
    Personal.metrics = { kills = 0, counted = 0, lives = 0, deaths = 0, drifted = 0, capped = 0, overCapCredited = 0, byClass = {} }
    return state ~= nil
end

function Personal.flush()
    if not Personal.dirty then return true, false end
    if type(Personal.adapters.transmit) == "function" then
        local ok, result = pcall(Personal.adapters.transmit, Personal.TAG)
        if not ok or result == false then return false, "personal_transmit_failed" end
    end
    Personal.dirty = false
    return true, true
end

return Personal
