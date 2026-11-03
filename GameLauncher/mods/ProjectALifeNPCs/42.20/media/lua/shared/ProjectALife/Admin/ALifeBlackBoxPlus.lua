ProjectALife = ProjectALife or {}

local Plus = {
    marker = "[ALIFE-BB]",
    settings = {
        eventSize = 160,
        uidGapMs = 60000,
        uidMemory = 256,
        bornMemory = 256,
        ringFallback = 70,
        vanishTiles = 60,
        hitGapMs = 10000,
        stareMs = 8000,
        stareHalfMs = 4000,
        stareGapMs = 60000,
        stareTiles = 30,
        stareEveryMs = 1000,
        stareMoveTiles = 1.5,
        stareCloseTiles = 1.0,
        stareChecksPerSecond = 8,
        errorSignatures = 40,
        errorChars = 80,
        errorTop = 3,
        rejectTop = 3,
        groupCap = 12,
        groupScan = 800,
        groupTrack = 64,
        changedCap = 60,
        modsCap = 40,
        playerCacheMs = 250,
        spawnTop = 4,
        holdTop = 3,
        lastHoldChars = 48,
    },
    caps = { ["pop-in"] = 10, ["vanish"] = 10, ["stare"] = 6, ["hit-rejected"] = 6, ["lua-error"] = 10 },
    counts = {},
    base = {},
    events = {},
    eventHead = 0,
    eventCount = 0,
    budgets = {},
    uidAt = {},
    uidAtCount = 0,
    born = {},
    bornCount = 0,
    errors = {},
    errorCount = 0,
    errorOverflow = 0,
    errorTotal = 0,
    waits = {},
    hitAtMs = nil,
    stareWindowAt = nil,
    stareChecks = 0,
    headerDone = false,
    playerRows = nil,
    playerAtMs = nil,
    scan = nil,
    faultCategories = { runtime_fault = true, action_handler_failed = true },
    luaMarks = { "attempt to", "tried to call nil", "bad argument", "stack traceback", ".lua:" },
    waitWords = {
        { "standoff", "standoff" }, { "robbery", "robbery_pending" }, { "warn", "warning" },
        { "order_changed", "order_changed" }, { "directive_changed", "order_changed" },
        { "recover_endurance", "endurance" }, { "talk_hold", "hold" },
    },
    sources = {
        { "acceptedOrdered", "ExecutorHits", "acceptedOrdered" },
        { "hitGraceOk", "ExecutorHits", "graceAccepted" },
        { "hitGraceNo", "ExecutorHits", "graceRefused" },
        { "hitSlack", "ExecutorHits", "slackAccepted" },
        { "damageApi", "Wounds", "damageApiFailures" },
        { "damageFallbackOk", "Wounds", "damageFallbackApplied" },
        { "damageFallbackNo", "Wounds", "damageFallbackFailed" },
        { "damageFloorWounds", "Wounds", "damageZeroFloored" },
        { "damageFloorBlows", "AIFence", "damageZeroFloored" },
        { "speechDead", "Speech", "speechRefusedDead" },
        { "corpsesHushed", "Speech", "corpsesHushed" },
        { "doorsUnlocked", "ObstacleTraversal", "doorsUnlocked" },
    },
}
ProjectALife.BlackBoxPlus = Plus

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function onBox()
    local box = ProjectALife.BlackBox
    if box ~= nil and box.enabled == true then return box end
    return nil
end

function Plus.onSwitch(enabled)
    Plus.events, Plus.eventHead, Plus.eventCount = {}, 0, 0
    Plus.budgets, Plus.uidAt, Plus.uidAtCount = {}, {}, 0
    Plus.born, Plus.bornCount = {}, 0
    Plus.playerRows, Plus.playerAtMs, Plus.scan = nil, nil, nil
    Plus.hitAtMs, Plus.stareWindowAt, Plus.stareChecks = nil, nil, 0
    Plus.headerDone = false
    if enabled == true then Plus.prime() end
    return true
end

function Plus.count(name, amount)
    Plus.counts[name] = (Plus.counts[name] or 0) + (amount or 1)
end

function Plus.delta(key, value)
    local previous = Plus.base[key] or 0
    Plus.base[key] = value
    return value - previous
end

function Plus.metric(moduleName, field)
    local module = ProjectALife[moduleName]
    local metrics = type(module) == "table" and module.metrics or nil
    if type(metrics) ~= "table" then return 0 end
    return tonumber(metrics[field]) or 0
end

function Plus.prime()
    for index = 1, #Plus.sources do
        local row = Plus.sources[index]
        Plus.base[row[1]] = Plus.metric(row[2], row[3])
    end
    local executor = ProjectALife.Executor
    local by = type(executor) == "table" and type(executor.metrics) == "table" and executor.metrics.rejectedBy or nil
    Plus.primeMap("rej:", by)
    local relay = ProjectALife.NPCHitRelay
    by = type(relay) == "table" and type(relay.metrics) == "table" and relay.metrics.refusedBy or nil
    Plus.primeMap("rel:", by)
    Plus.base.luaErrors = Plus.errorTotal
    pcall(Plus.spawnText)
end

function Plus.primeMap(prefix, map)
    if type(map) ~= "table" then return end
    for reason, count in pairs(map) do
        if type(count) == "number" then Plus.base[prefix .. tostring(reason)] = count end
    end
end

function Plus.record(now, text)
    local size = Plus.settings.eventSize
    local head = Plus.eventHead + 1
    if head > size then head = 1 end
    Plus.eventHead = head
    local slot = Plus.events[head]
    if slot == nil then
        slot = {}
        Plus.events[head] = slot
    end
    slot.atMs, slot.text = now, text
    if Plus.eventCount < size then Plus.eventCount = Plus.eventCount + 1 end
end

function Plus.spend(name, now)
    local cap = Plus.caps[name] or 6
    local row = Plus.budgets[name]
    if row == nil then
        row = { atMs = now, used = 0 }
        Plus.budgets[name] = row
    end
    if now < row.atMs or now - row.atMs >= 60000 then row.atMs, row.used = now, 0 end
    if row.used >= cap then return false end
    row.used = row.used + 1
    return true
end

function Plus.gapOk(name, uid, now)
    local key = name .. "|" .. tostring(uid)
    local last = Plus.uidAt[key]
    if last ~= nil and now >= last and now - last < Plus.settings.uidGapMs then return false end
    if last == nil then
        if Plus.uidAtCount >= Plus.settings.uidMemory then Plus.uidAt, Plus.uidAtCount = {}, 0 end
        Plus.uidAtCount = Plus.uidAtCount + 1
    end
    Plus.uidAt[key] = now
    return true
end

function Plus.say(box, name, now, uid, x, y, detail, entry)
    local counts = box.metrics.detect
    counts[name] = (counts[name] or 0) + 1
    local text = "detect=" .. name .. " uid=" .. tostring(uid) .. " at=" .. box.number(x) .. "," .. box.number(y)
        .. " " .. tostring(detail)
    Plus.record(now, text)
    if entry ~= nil then
        local quietSince = entry.lastEventAtMs
        box.push(entry, now, "detect", name)
        entry.lastEventAtMs = quietSince
        entry.lastDetect = name
    end
    if Plus.spend(name, now) and box.spendLine(now) then
        print(Plus.marker .. " " .. text)
        return true
    end
    box.metrics.linesHeld = (box.metrics.linesHeld or 0) + 1
    return false
end

function Plus.reloadNote(name, uid, x, y, detail)
    local box = onBox()
    if box == nil then return false end
    local now = nowMs()
    return Plus.say(box, name, now, uid, tonumber(x) or 0, tonumber(y) or 0, tostring(detail or ""), nil)
end

function Plus.rows(now)
    local fair = ProjectALife.SpawnFairness
    if fair ~= nil and type(fair.players) == "function" then
        local ok, rows = pcall(fair.players)
        if ok and type(rows) == "table" then return rows end
    end
    if Plus.playerRows ~= nil and now >= Plus.playerAtMs and now - Plus.playerAtMs < Plus.settings.playerCacheMs then
        return Plus.playerRows
    end
    local rows = {}
    local locator = ProjectALife.PlayerLocator
    if locator ~= nil and type(locator.list) == "function" and type(locator.position) == "function" then
        local list = locator.list() or {}
        for index = 1, #list do
            local at = locator.position(list[index])
            if type(at) == "table" and tonumber(at.x) ~= nil and tonumber(at.y) ~= nil then
                rows[#rows + 1] = { x = tonumber(at.x), y = tonumber(at.y), z = tonumber(at.z) or 0,
                    player = list[index], index = index }
            end
        end
    end
    Plus.playerRows, Plus.playerAtMs = rows, now
    return rows
end

function Plus.nearest(rows, x, y)
    local best, row = nil, nil
    for index = 1, #rows do
        local p = rows[index]
        local dx, dy = x - p.x, y - p.y
        local d2 = dx * dx + dy * dy
        if best == nil or d2 < best then best, row = d2, p end
    end
    if row == nil then return nil, nil end
    return row, math.sqrt(best)
end

function Plus.visible(rows, x, y, z)
    local fair = ProjectALife.SpawnFairness
    if fair == nil or type(fair.seen) ~= "function" then return "unknown" end
    local ok, seen, deferred = pcall(fair.seen, x, y, z, rows, true)
    if not ok then return "unknown" end
    if deferred == true then return "unknown" end
    if seen == true then return "yes" end
    return "no"
end

function Plus.ringOf(row, now)
    local fair = ProjectALife.SpawnFairness
    if fair ~= nil and type(fair.ringFor) == "function" then
        local ok, ring = pcall(fair.ringFor, row, now)
        if ok and tonumber(ring) ~= nil then return tonumber(ring) end
    end
    return Plus.settings.ringFallback
end

function Plus.cellOf(x, y)
    local fair = ProjectALife.SpawnFairness
    if fair == nil or type(fair.kindAt) ~= "function" then return "?" end
    local ok, kind = pcall(fair.kindAt, x, y)
    if ok and kind ~= nil then return tostring(kind) end
    return "?"
end

function Plus.kindOf(actor)
    local memory = type(actor) == "table" and type(actor.memory) == "table" and actor.memory or nil
    if memory == nil then return "offline" end
    if memory.debugSpawn == true or memory.adminAnchor == true or type(memory.admin) == "table" then return "admin" end
    if type(memory.visit) == "table" or type(memory.guest) == "table" then return "visitor" end
    local label = string.lower(tostring(memory.encounterKind or memory.encounter or "") .. " "
        .. tostring(memory.adminMode or ""))
    if string.find(label, "raid", 1, true) or string.find(label, "assault", 1, true) then return "raid" end
    if memory.encounter ~= nil then return "encounter" end
    if memory.persistent == true or memory.garrisonPost ~= nil or memory.outpostSquadId ~= nil then return "town" end
    return "offline"
end

function Plus.placeOf(box, actor, shell, position)
    local x, y = box.xyOf(shell)
    local z = 0
    if x ~= nil and type(shell.getZ) == "function" then
        local ok, value = pcall(shell.getZ, shell)
        if ok and tonumber(value) ~= nil then z = tonumber(value) end
    end
    if x == nil then
        local at = position
        if type(at) ~= "table" and type(actor) == "table" then at = actor.worldPosition end
        if type(at) == "table" and tonumber(at.x) ~= nil and tonumber(at.y) ~= nil then
            x, y, z = tonumber(at.x), tonumber(at.y), tonumber(at.z) or 0
        end
    end
    return x, y, z
end

function Plus.noteBorn(uid, now)
    if uid == nil then return end
    if Plus.born[uid] == nil then
        if Plus.bornCount >= Plus.settings.bornMemory then Plus.born, Plus.bornCount = {}, 0 end
        Plus.bornCount = Plus.bornCount + 1
    end
    Plus.born[uid] = now
end

function Plus.lifeOf(uid, now)
    local at = Plus.born[uid]
    if at == nil then
        local population = ProjectALife.Population
        local active = type(population) == "table" and type(population.activeSinceMs) == "table"
            and population.activeSinceMs[uid] or nil
        at = tonumber(active)
    end
    if at == nil or now < at then return "?" end
    return tostring(math.floor((now - at) / 1000)) .. "s"
end

function Plus.popIn(actor, shell, operationId)
    local box = onBox()
    if box == nil or type(actor) ~= "table" then return end
    local now = nowMs()
    local uid = actor.uid
    Plus.noteBorn(uid, now)
    local x, y, z = Plus.placeOf(box, actor, shell, nil)
    if x == nil then return end
    local rows = Plus.rows(now)
    local player, distance = Plus.nearest(rows, x, y)
    if player == nil then return end
    local ring = Plus.ringOf(player, now)
    local seen = Plus.visible(rows, x, y, z)
    if distance > ring and seen ~= "yes" then return end
    if not Plus.gapOk("pop-in", uid, now) then return end
    local memory = type(actor.memory) == "table" and actor.memory or {}
    local fair = ProjectALife.SpawnFairness
    local mode = "?"
    if fair ~= nil and type(fair.actorMode) == "function" then
        local ok, value = pcall(fair.actorMode, actor, false, false)
        if ok and value ~= nil then mode = tostring(value) end
    end
    local path = string.match(tostring(operationId or ""), "^([^:]+)") or "?"
    Plus.say(box, "pop-in", now, uid, x, y, "kind=" .. Plus.kindOf(actor) .. " d=" .. box.number(distance)
        .. " vis=" .. seen .. " cell=" .. Plus.cellOf(x, y) .. " path=" .. path .. " mode=" .. mode
        .. " ring=" .. box.number(ring) .. " squad=" .. tostring(memory.squadId or memory.groupId or "-"), nil)
end

function Plus.doingOf(box, actor, shell)
    local data = shell ~= nil and box.dataOf(shell) or nil
    if type(data) == "table" and data.ProjectALifeBehaviorState ~= nil then
        return tostring(data.ProjectALifeBehaviorState) .. "/" .. tostring(data.ProjectALifeBehaviorIntent)
            .. " phase=" .. tostring(data.ProjectALifeCombatPhase)
    end
    if type(actor) == "table" then
        return tostring(actor.activity) .. "/" .. tostring(actor.intent) .. " phase=-"
    end
    return "?/? phase=-"
end

function Plus.vanish(actor, reason, position, shell)
    local box = onBox()
    if box == nil or type(actor) ~= "table" or reason == "world_save" then return end
    local now = nowMs()
    local uid = actor.uid
    local x, y, z = Plus.placeOf(box, actor, nil, position)
    if x == nil then return end
    local rows = Plus.rows(now)
    local player, distance = Plus.nearest(rows, x, y)
    if player == nil then return end
    local seen = Plus.visible(rows, x, y, z)
    if distance > Plus.settings.vanishTiles and seen ~= "yes" then return end
    local life = Plus.lifeOf(uid, now)
    Plus.born[uid] = nil
    if not Plus.gapOk("vanish", uid, now) then return end
    Plus.say(box, "vanish", now, uid, x, y, "kind=" .. Plus.kindOf(actor) .. " reason=" .. tostring(reason)
        .. " d=" .. box.number(distance) .. " vis=" .. seen .. " cell=" .. Plus.cellOf(x, y)
        .. " doing=" .. Plus.doingOf(box, actor, shell) .. " life=" .. life, nil)
end

function Plus.lookup(list, word)
    for index = 1, #list do
        if string.find(word, list[index][1], 1, true) then return list[index][2] end
    end
    return nil
end

function Plus.legitWait(box, data, uid, now)
    local found = Plus.lookup(Plus.waitWords, tostring(data.ProjectALifeBehaviorIntent or ""))
    if found ~= nil then return found end
    local phase = tostring(data.ProjectALifeCombatPhase or "")
    if phase == "recovery" then return "recovering" end
    if phase == "reload" or phase == "reload_rack" then return "reload" end
    local endurance = ProjectALife.Endurance
    if type(endurance) == "table" and type(endurance.snapshot) == "function" and uid ~= nil then
        local snap = endurance.snapshot(uid)
        if type(snap) == "table" and (tonumber(snap.retreatUntilMs) or 0) > now then return "endurance" end
    end
    return nil
end

function Plus.noteWait(reason, st, now)
    Plus.waits[reason] = (Plus.waits[reason] or 0) + 1
    st.waitReason, st.waitAt = reason, now
end

function Plus.rebase(st, now, x, y, shot, strike, distance)
    st.since, st.bx, st.by, st.shot, st.strike, st.bd = now, x, y, shot, strike, distance
end

function Plus.attackAge(st, shot, now)
    local last = math.max(tonumber(shot) or -math.huge, tonumber(st.attackAt) or -math.huge)
    if last == -math.huge or now < last then return "-" end
    return tostring(math.floor((now - last) / 1000)) .. "s"
end

function Plus.stareBudget(now)
    if Plus.stareWindowAt == nil or now < Plus.stareWindowAt or now - Plus.stareWindowAt >= 1000 then
        Plus.stareWindowAt, Plus.stareChecks = now, 0
    end
    if Plus.stareChecks >= Plus.settings.stareChecksPerSecond then return false end
    Plus.stareChecks = Plus.stareChecks + 1
    return true
end

function Plus.lineOfSight(shell, player, x, y)
    local sight = ProjectALife.Sight
    if sight == nil or type(sight.between) ~= "function" then return false end
    local z = 0
    if type(shell.getZ) == "function" then
        local ok, value = pcall(shell.getZ, shell)
        if ok and tonumber(value) ~= nil then z = tonumber(value) end
    end
    local answer = sight.between(x, y, z, player.x, player.y, player.z or 0)
    return answer ~= nil and answer ~= "blocked" and answer ~= "door"
end

function Plus.stareDetail(box, shell, data, actor, st, shot, distance, now)
    local health
    if type(shell.getHealth) == "function" then
        local ok, value = pcall(shell.getHealth, shell)
        if ok then health = value end
    end
    local endurance = ProjectALife.Endurance
    local snap = type(endurance) == "table" and type(endurance.snapshot) == "function"
        and endurance.snapshot(actor.uid) or nil
    local warning = ProjectALife.ModuleWarning
    local warns, holdSeconds, timeouts = "?", "?", "?"
    if type(warning) == "table" and type(warning.decide) == "function" then
        local ok, allowed, _, raid = pcall(warning.decide, actor)
        if ok then
            if raid == true then warns = "raid" elseif allowed == true then warns = "yes" else warns = "no" end
        end
        if type(warning.holdMs) == "function" then holdSeconds = tostring(math.floor(warning.holdMs() / 1000)) end
        if type(warning.metrics) == "table" then timeouts = tostring(warning.metrics.holdTimeouts or 0) end
    end
    local resistance = ProjectALife.Resistance
    local res = "?"
    if type(resistance) == "table" and type(resistance.metrics) == "table" then
        local m = resistance.metrics
        res = tostring(m.holdWhileSeen or 0) .. "/" .. tostring(m.enduranceRestRefusedInSight or 0)
            .. "/" .. tostring(m.sprintHeld or 0)
    end
    local waitText = "-"
    if st.waitReason ~= nil then
        waitText = st.waitReason .. "@" .. tostring(math.floor((now - st.waitAt) / 1000)) .. "s"
    end
    return "d=" .. box.number(distance) .. " hp=" .. box.number(health) .. "/"
        .. box.number(data.ProjectALifeMaximumHealth)
        .. " end=" .. (snap ~= nil and (box.number(snap.value) .. "/" .. box.number(snap.maximum)) or "?")
        .. " lastAttack=" .. Plus.attackAge(st, shot, now)
        .. " beh=" .. tostring(data.ProjectALifeBehaviorState) .. "/" .. tostring(data.ProjectALifeBehaviorIntent)
        .. " phase=" .. tostring(data.ProjectALifeCombatPhase) .. " los=yes still="
        .. tostring(math.floor((now - st.since) / 1000)) .. "s warns=" .. warns .. " holdLimit=" .. holdSeconds
        .. "s warnTimeouts=" .. timeouts .. " res=" .. res .. " lastWait=" .. waitText
end

function Plus.stare(box, shell, data, entry, now, active)
    local st = entry.plus
    if st == nil then
        st = {}
        entry.plus = st
    end
    if now < (st.nextAt or 0) then return end
    st.nextAt = now + Plus.settings.stareEveryMs
    local x, y = entry.x, entry.y
    if x == nil or y == nil then return end
    local settings = Plus.settings
    local shot, strike = tonumber(data.ProjectALifeLastShotAtMs), tonumber(data.ProjectALifeNextStrikeAtMs)
    if type(box.downed) == "function" and box.downed(shell, data, entry, now) ~= nil then
        Plus.rebase(st, now, x, y, shot, strike, nil)
        return
    end
    if st.since == nil or active ~= nil then
        Plus.rebase(st, now, x, y, shot, strike, nil)
        return
    end
    if shot ~= st.shot or strike ~= st.strike then
        st.attackAt = now
        Plus.rebase(st, now, x, y, shot, strike, nil)
        return
    end
    local dx, dy = x - st.bx, y - st.by
    if dx * dx + dy * dy > settings.stareMoveTiles * settings.stareMoveTiles then
        Plus.rebase(st, now, x, y, shot, strike, nil)
        return
    end
    local elapsed = now - st.since
    if elapsed < settings.stareHalfMs then return end
    if not Plus.stareBudget(now) then
        st.nextAt = now + 250
        return
    end
    local rows = Plus.rows(now)
    local player, distance = Plus.nearest(rows, x, y)
    if player == nil or distance > settings.stareTiles then
        Plus.rebase(st, now, x, y, shot, strike, nil)
        return
    end
    if st.bd ~= nil and distance < st.bd - settings.stareCloseTiles then
        Plus.rebase(st, now, x, y, shot, strike, distance)
        return
    end
    if st.bd == nil or distance < st.bd then st.bd = distance end
    local uid = data.ProjectALifeUID
    local legit = Plus.legitWait(box, data, uid, now)
    local registry = ProjectALife.ActorRegistry
    local actor = registry ~= nil and type(registry.peek) == "function" and uid ~= nil and registry.peek(uid) or nil
    if legit == nil and type(actor) == "table" and type(actor.memory) == "table" and actor.memory.orderedTo ~= nil then
        legit = "hold"
    end
    if legit ~= nil then
        Plus.noteWait(legit, st, now)
        Plus.rebase(st, now, x, y, shot, strike, distance)
        return
    end
    local relations = ProjectALife.Relations
    local hostile = false
    if type(actor) == "table" and relations ~= nil and type(relations.hostileToPlayer) == "function" then
        local ok, answer = pcall(relations.hostileToPlayer, actor, player.player)
        hostile = ok and answer == true
    end
    if not hostile or not Plus.lineOfSight(shell, player, x, y) then
        Plus.rebase(st, now, x, y, shot, strike, distance)
        return
    end
    if elapsed < settings.stareMs then return end
    if st.stareAt ~= nil and now >= st.stareAt and now - st.stareAt < settings.stareGapMs then
        Plus.rebase(st, now, x, y, shot, strike, distance)
        return
    end
    st.stareAt = now
    local detail = Plus.stareDetail(box, shell, data, actor, st, shot, distance, now)
    Plus.say(box, "stare", now, uid, x, y, detail, entry)
    Plus.rebase(st, now, x, y, shot, strike, distance)
end

function Plus.tick(shell, data, entry, now, active)
    local box = onBox()
    if box == nil or entry == nil or type(data) ~= "table" then return end
    Plus.stare(box, shell, data, entry, now, active)
end

function Plus.hitRejected(player, message, reason)
    local box = onBox()
    if box == nil then return end
    Plus.count("hitRejected")
    local now = nowMs()
    if Plus.hitAtMs ~= nil and now >= Plus.hitAtMs and now - Plus.hitAtMs < Plus.settings.hitGapMs then return end
    Plus.hitAtMs = now
    local message = type(message) == "table" and message or {}
    local uid = message.uid
    local watchdog = ProjectALife.Watchdog
    local binding = watchdog ~= nil and type(watchdog.bindings) == "table" and uid ~= nil
        and watchdog.bindings[uid] or nil
    local shell = type(binding) == "table" and binding.shell or nil
    local executor = ProjectALife.Executor
    local victim
    if executor ~= nil and type(executor.playerByOnlineId) == "function" then
        local ok, found = pcall(executor.playerByOnlineId, message.online)
        if ok then victim = found end
    end
    local x, y = box.xyOf(shell)
    local vx, vy = box.xyOf(victim)
    local distance = "?"
    if x ~= nil and vx ~= nil then distance = box.number(math.sqrt((x - vx) ^ 2 + (y - vy) ^ 2)) end
    local registry = ProjectALife.ActorRegistry
    local record = registry ~= nil and type(registry.peek) == "function" and uid ~= nil and registry.peek(uid) or nil
    local relations = ProjectALife.Relations
    local stance = "?"
    if type(record) == "table" and victim ~= nil and relations ~= nil and type(relations.playerStance) == "function" then
        local ok, value = pcall(relations.playerStance, record, victim)
        if ok and value ~= nil then stance = tostring(value) end
    end
    local order = "-"
    local memory = type(record) == "table" and type(record.memory) == "table" and record.memory or nil
    if memory ~= nil then
        if type(memory.orderedTo) == "table" and memory.orderedTo.kind ~= nil then order = tostring(memory.orderedTo.kind)
        elseif memory.adminMode ~= nil then order = tostring(memory.adminMode) end
    end
    local name = tostring(message.online)
    if victim ~= nil and type(victim.getUsername) == "function" then
        local ok, value = pcall(victim.getUsername, victim)
        if ok and value ~= nil then name = tostring(value) end
    end
    Plus.say(box, "hit-rejected", now, uid, x, y, "reason=" .. tostring(reason) .. " victim=" .. name
        .. " d=" .. distance .. " rel=" .. stance .. " order=" .. order .. " weapon=" .. tostring(message.weapon), nil)
end

function Plus.sideOf(shell)
    if shell == nil or type(shell.getCurrentSquare) ~= "function" then return "?" end
    local ok, square = pcall(shell.getCurrentSquare, shell)
    if not ok or square == nil or type(square.getRoom) ~= "function" then return "?" end
    local read, room = pcall(square.getRoom, square)
    if not read then return "?" end
    return room ~= nil and "inside" or "outside"
end

function Plus.lockOf(object, from)
    local policy = ProjectALife.DoorPolicy
    if type(policy) ~= "table" or type(policy.lockKind) ~= "function" then return nil end
    local ok, kind = pcall(policy.lockKind, object, from)
    if ok and kind ~= nil then return tostring(kind) end
    return nil
end

function Plus.pointText(box, object)
    local policy = ProjectALife.DoorPolicy
    if type(policy) ~= "table" or type(policy.pointOf) ~= "function" then return "?,?" end
    local ok, x, y = pcall(policy.pointOf, object)
    if not ok or x == nil then return "?,?" end
    return box.number(x) .. "," .. box.number(y)
end

function Plus.doorOpened(shell, object, square, keyed, locked, grouped, readable, open)
    local box = onBox()
    if box == nil then return end
    Plus.count("doorsOpened")
    local lock = Plus.lockOf(object, square)
    if lock == nil then
        if keyed == true then lock = "key" elseif locked == true then lock = "locked" else lock = "none" end
    end
    local after = "unknown"
    if grouped == true then after = "toggled"
    elseif readable == true then after = open == true and "open" or "closed" end
    local detail = "who=" .. tostring(box.shellUid(shell)) .. " before=closed after=" .. after .. " lock=" .. lock
        .. " side=" .. Plus.sideOf(shell) .. " at=" .. Plus.pointText(box, object)
    box.note(shell, "door-opened", detail)
    Plus.record(nowMs(), "door-opened " .. detail)
end

function Plus.breach(shell, phase, kind, object, reason, success)
    local box = onBox()
    if box == nil then return end
    local now = nowMs()
    local lock = Plus.lockOf(object, nil)
    local detail = "phase=" .. tostring(phase) .. " kind=" .. tostring(kind) .. " lock=" .. tostring(lock or "none")
        .. " who=" .. tostring(box.shellUid(shell)) .. " at=" .. Plus.pointText(box, object)
    if phase == "start" then
        local policy = ProjectALife.DoorPolicy
        local may = "?"
        if type(policy) == "table" and type(policy.mayBreach) == "function" then
            local ok, answer = pcall(policy.mayBreach, shell, object, lock)
            if ok then may = answer == true and "yes" or "no" end
        end
        local traversal = ProjectALife.ObstacleTraversal
        local allowed = "?"
        if type(traversal) == "table" and type(traversal.breachAllowed) == "function" then
            local ok, answer = pcall(traversal.breachAllowed, shell, object)
            if ok then allowed = answer == true and "yes" or "no" end
        end
        detail = detail .. " mayBreach=" .. may .. " courtesyOk=" .. allowed
    else
        detail = detail .. " ok=" .. tostring(success == true) .. " reason=" .. tostring(reason)
        if success == true and (kind == "door" or kind == "barricade") then Plus.count("doorsBreached") end
    end
    box.note(shell, "door-breach", detail)
    Plus.record(now, "door-breach " .. detail)
end

function Plus.looksLua(text)
    for index = 1, #Plus.luaMarks do
        if string.find(text, Plus.luaMarks[index], 1, true) then return true end
    end
    return false
end

function Plus.signature(source, subsystem, text)
    local at = string.find(text, "[%w_]+%.lua")
    if at ~= nil and at > 1 then text = string.sub(text, at) end
    local stripped = string.gsub(text, "%d+", "#")
    stripped = string.gsub(stripped, "%s+", "_")
    stripped = string.gsub(stripped, ":", ".")
    local label = tostring(subsystem or source)
    label = string.gsub(label, "[%s:]", "_")
    return label .. "." .. string.sub(stripped, 1, Plus.settings.errorChars)
end

function Plus.luaError(source, message, forced, subsystem)
    local box = onBox()
    if box == nil then return end
    local text = tostring(message)
    if forced ~= true and Plus.faultCategories[source] ~= true and not Plus.looksLua(text) then return end
    local now = nowMs()
    Plus.errorTotal = Plus.errorTotal + 1
    local sig = Plus.signature(source, subsystem, text)
    local known = Plus.errors[sig]
    if known ~= nil then
        Plus.errors[sig] = known + 1
        return
    end
    if Plus.errorCount >= Plus.settings.errorSignatures then
        Plus.errorOverflow = Plus.errorOverflow + 1
        return
    end
    Plus.errors[sig] = 1
    Plus.errorCount = Plus.errorCount + 1
    Plus.say(box, "lua-error", now, "-", nil, nil, "sig=" .. sig, nil)
end

function Plus.rowOrder(a, b)
    if a[2] ~= b[2] then return a[2] > b[2] end
    return a[1] < b[1]
end

function Plus.topOf(rows, limit, joiner)
    if #rows == 0 then return "-" end
    table.sort(rows, Plus.rowOrder)
    local out = {}
    for index = 1, math.min(limit, #rows) do out[index] = rows[index][1] .. ":" .. tostring(rows[index][2]) end
    return table.concat(out, joiner)
end

function Plus.mapDelta(prefix, map, limit)
    local rows = {}
    if type(map) == "table" then
        for reason, count in pairs(map) do
            if type(count) == "number" then
                local key = prefix .. tostring(reason)
                local change = Plus.delta(key, count)
                if change > 0 then rows[#rows + 1] = { tostring(reason), change } end
            end
        end
    end
    return Plus.topOf(rows, limit, ",")
end

function Plus.errorTop()
    local rows = {}
    for sig, count in pairs(Plus.errors) do rows[#rows + 1] = { sig, count } end
    return Plus.topOf(rows, Plus.settings.errorTop, ";")
end

function Plus.rise(key, value)
    local previous = Plus.base[key] or 0
    Plus.base[key] = value
    if value < previous then return value end
    return value - previous
end

function Plus.riseTop(prefix, map, limit)
    local rows = {}
    if type(map) == "table" then
        for reason, count in pairs(map) do
            if type(count) == "number" then
                local change = Plus.rise(prefix .. tostring(reason), count)
                if change > 0 then rows[#rows + 1] = { tostring(reason), change } end
            end
        end
    end
    return Plus.topOf(rows, limit, ",")
end

function Plus.metricsOf(moduleName)
    local module = ProjectALife[moduleName]
    local metrics = type(module) == "table" and module.metrics or nil
    if type(metrics) == "table" then return metrics end
    return nil
end

function Plus.spawnText()
    local fairMetrics = Plus.metricsOf("SpawnFairness")
    local renderMetrics = Plus.metricsOf("RenderProtocol")
    local populationMetrics = Plus.metricsOf("Population")
    if fairMetrics == nil and renderMetrics == nil and populationMetrics == nil then return nil end
    local fair = ProjectALife.SpawnFairness
    local reasons = type(fair) == "table" and fair.reasons or nil
    local holdBy = renderMetrics ~= nil and renderMetrics.holdBy or nil
    local last = renderMetrics ~= nil and renderMetrics.lastHold or nil
    if type(last) ~= "string" or last == "" then last = "-" end
    local settings = Plus.settings
    if #last > settings.lastHoldChars then last = string.sub(last, 1, settings.lastHoldChars) end
    local rise = Plus.rise
    return Plus.marker .. " spawn fair=" .. Plus.riseTop("sf:", reasons, settings.spawnTop)
        .. " hydrated=" .. rise("sm:natural", Plus.metric("SpawnFairness", "hydratedNatural"))
        .. "/" .. rise("sm:atRing", Plus.metric("SpawnFairness", "hydratedAtRing"))
        .. "/" .. rise("sm:inside", Plus.metric("SpawnFairness", "hydratedInside"))
        .. " despawnRefused=" .. rise("sm:near", Plus.metric("SpawnFairness", "despawnRefusedNear"))
        .. "/" .. rise("sm:sight", Plus.metric("SpawnFairness", "despawnRefusedSight"))
        .. " hold=" .. Plus.riseTop("rh:", holdBy, settings.holdTop)
        .. " lastHold=" .. last
        .. " pop=" .. Plus.riseTop("pm:", populationMetrics, settings.spawnTop)
end

function Plus.minuteText(now)
    local box = onBox()
    if box == nil then return "" end
    local detect = box.metrics.detect
    local d = Plus.delta
    local executor = ProjectALife.Executor
    local rejected = type(executor) == "table" and type(executor.metrics) == "table"
        and executor.metrics.rejectedBy or nil
    local relay = ProjectALife.NPCHitRelay
    local refused = type(relay) == "table" and type(relay.metrics) == "table" and relay.metrics.refusedBy or nil
    local ext = {}
    for index = 1, #Plus.sources do
        local row = Plus.sources[index]
        ext[row[1]] = d(row[1], Plus.metric(row[2], row[3]))
    end
    return " popIn=" .. d("pop-in", detect["pop-in"] or 0)
        .. " vanish=" .. d("vanish", detect["vanish"] or 0)
        .. " stare=" .. d("stare", detect["stare"] or 0)
        .. " hitRejected=" .. d("hitRejected", Plus.counts.hitRejected or 0)
        .. " rejectedBy=" .. Plus.mapDelta("rej:", rejected, Plus.settings.rejectTop)
        .. " relayRefusedBy=" .. Plus.mapDelta("rel:", refused, Plus.settings.rejectTop)
        .. " acceptedOrdered=" .. ext.acceptedOrdered
        .. " hitGrace=" .. ext.hitGraceOk .. "/" .. ext.hitGraceNo
        .. " hitSlack=" .. ext.hitSlack
        .. " damageApiFailures=" .. ext.damageApi
        .. " damageFallback=" .. ext.damageFallbackOk .. "/" .. ext.damageFallbackNo
        .. " damageZeroFloored=" .. ext.damageFloorWounds .. "/" .. ext.damageFloorBlows
        .. " speechRefusedDead=" .. ext.speechDead
        .. " corpsesHushed=" .. ext.corpsesHushed
        .. " doorsOpened=" .. d("doorsOpened", Plus.counts.doorsOpened or 0)
        .. " doorsUnlocked=" .. ext.doorsUnlocked
        .. " doorsBreached=" .. d("doorsBreached", Plus.counts.doorsBreached or 0)
        .. " luaErrors=" .. d("luaErrors", Plus.errorTotal)
        .. " top=" .. Plus.errorTop()
end

function Plus.verdictText()
    local box = ProjectALife.BlackBox
    local detect = box ~= nil and type(box.metrics) == "table" and box.metrics.detect or {}
    return " popIn=" .. tostring(detect["pop-in"] or 0) .. " vanish=" .. tostring(detect["vanish"] or 0)
        .. " stare=" .. tostring(detect["stare"] or 0) .. " hitRejected=" .. tostring(Plus.counts.hitRejected or 0)
        .. " doorsOpened=" .. tostring(Plus.counts.doorsOpened or 0)
        .. " doorsBreached=" .. tostring(Plus.counts.doorsBreached or 0)
        .. " luaErrors=" .. tostring(Plus.errorTotal)
end

function Plus.modeText()
    local client = type(isClient) == "function" and isClient() == true
    local server = type(isServer) == "function" and isServer() == true
    if client and server then return "coop" end
    if server then return "server" end
    if client then return "client" end
    return "sp"
end

function Plus.playersText()
    local online = 0
    if type(getOnlinePlayers) == "function" then
        local ok, list = pcall(getOnlinePlayers)
        if ok and list ~= nil and type(list.size) == "function" then online = tonumber(list:size()) or 0 end
    end
    if online <= 0 and type(getSpecificPlayer) == "function" then
        local ok, first = pcall(getSpecificPlayer, 0)
        if ok and first ~= nil then online = 1 end
    end
    return tostring(online)
end

function Plus.modsText()
    if type(getActivatedMods) ~= "function" then return "?", "?" end
    local ok, mods = pcall(getActivatedMods)
    if not ok or mods == nil or type(mods.size) ~= "function" then return "?", "?" end
    local total = mods:size()
    local names = {}
    for index = 0, math.min(total, Plus.settings.modsCap) - 1 do names[#names + 1] = tostring(mods:get(index)) end
    local text = #names > 0 and table.concat(names, ",") or "-"
    if total > #names then text = text .. ",+" .. tostring(total - #names) end
    return text, tostring(total)
end

function Plus.same(a, b)
    if tonumber(a) ~= nil and tonumber(b) ~= nil then return tonumber(a) == tonumber(b) end
    return tostring(a) == tostring(b)
end

function Plus.changedText()
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(vars) ~= "table" or type(getSandboxOptions) ~= "function" then return "?" end
    local options = getSandboxOptions()
    if options == nil or type(options.getOptionByName) ~= "function" then return "?" end
    local names = {}
    for name in pairs(vars) do
        if type(name) == "string" then names[#names + 1] = name end
    end
    table.sort(names)
    local out, extra = {}, 0
    for index = 1, #names do
        local name = names[index]
        local option = options:getOptionByName("ALife." .. name)
        if option ~= nil and type(option.getValue) == "function" and type(option.getDefaultValue) == "function" then
            local value, default = option:getValue(), option:getDefaultValue()
            if not Plus.same(value, default) then
                if #out < Plus.settings.changedCap then out[#out + 1] = name .. "=" .. tostring(value)
                else extra = extra + 1 end
            end
        end
    end
    if #out == 0 then return "-" end
    local text = table.concat(out, ",")
    if extra > 0 then text = text .. ",+" .. tostring(extra) end
    return text
end

function Plus.prefsText()
    local prefs = ProjectALife.MenuPrefs
    local values = type(prefs) == "table" and prefs.values or nil
    if type(values) ~= "table" then return "-" end
    local out = {}
    for key, value in pairs(values) do
        if type(key) == "string" then out[#out + 1] = key .. ":" .. tostring(value) end
    end
    if #out == 0 then return "-" end
    table.sort(out)
    return table.concat(out, ",")
end

function Plus.headerText()
    local box = ProjectALife.BlackBox
    local catalog = ProjectALife.Catalog
    local stamp = type(catalog) == "table" and catalog.BUILD_STAMP or nil
    local modId = type(catalog) == "table" and catalog.MOD_ID or nil
    local build = (type(stamp) == "string" and stamp ~= "") and stamp or nil
    if build == nil and box ~= nil then build = tostring(box.BUILD) end
    local version = "?"
    if box ~= nil and type(box.modVersion) == "function" and type(modId) == "string"
            and type(getModInfoByID) == "function" then
        version = box.modVersion(modId) or "?"
    end
    local mods, modCount = Plus.modsText()
    local okChanged, changed = pcall(Plus.changedText)
    return Plus.marker .. " header build=" .. tostring(build or "?") .. " mod=" .. tostring(modId or "?")
        .. " version=" .. version .. " mode=" .. Plus.modeText() .. " players=" .. Plus.playersText()
        .. " modCount=" .. modCount .. " mods=" .. mods
        .. " changed=" .. (okChanged and changed or "?") .. " prefs=" .. Plus.prefsText()
end

function Plus.beforeMinute(now)
    local box = onBox()
    if box == nil or Plus.headerDone then return false end
    Plus.headerDone = true
    print(Plus.headerText())
    return true
end

function Plus.visit(record)
    local scan = Plus.scan
    scan.visited = scan.visited + 1
    if type(record) == "table" and record.lifecycle == "active" then
        local memory = type(record.memory) == "table" and record.memory or nil
        local key
        if memory ~= nil then
            key = memory.groupId
            if type(key) ~= "string" or key == "" then key = memory.squadId end
        end
        if type(key) == "string" and key ~= "" then
            local row = scan.rows[key]
            if row == nil and scan.count < Plus.settings.groupTrack then
                row = { key = key, n = 0, faction = record.factionId, roles = {} }
                scan.rows[key] = row
                scan.count = scan.count + 1
                scan.list[scan.count] = row
            end
            if row ~= nil then
                row.n = row.n + 1
                local at = record.worldPosition
                if row.x == nil and type(at) == "table" and tonumber(at.x) ~= nil then
                    row.x, row.y = tonumber(at.x), tonumber(at.y)
                end
                local role = memory.role
                if type(role) ~= "string" then role = memory.supportRole end
                if type(role) ~= "string" then role = "member" end
                row.roles[role] = (row.roles[role] or 0) + 1
            end
        end
    end
    return scan.visited >= Plus.settings.groupScan
end

function Plus.groupOrder(a, b)
    if a.d ~= b.d then return a.d < b.d end
    return a.key < b.key
end

function Plus.groupLine(box, row, level)
    local planText, class = "-", tostring(row.faction or "-")
    local plans = ProjectALife.GroupPlan
    if type(plans) == "table" and type(plans.current) == "function" then
        local ok, plan = pcall(plans.current, row.key)
        if ok and type(plan) == "table" then
            planText = tostring(plan.kind) .. ":" .. tostring(plan.stage)
            if plan.class ~= nil then class = tostring(plan.class) end
        end
    end
    local lifeText = "-"
    local life = ProjectALife.GroupLife
    if type(life) == "table" and type(life.stateOf) == "function" then
        local ok, phase = pcall(life.stateOf, row.key)
        if ok and phase ~= nil then
            lifeText = tostring(phase)
            if type(life.kindOf) == "function" then
                local okKind, venue = pcall(life.kindOf, row.key)
                if okKind and venue ~= nil then lifeText = lifeText .. "/" .. tostring(venue) end
            end
        end
    end
    local chatter = "-"
    local director = ProjectALife.ChatterDirector
    local scene = type(director) == "table" and type(director.scenes) == "table" and director.scenes[row.key] or nil
    if type(scene) == "table" and scene.topic ~= nil then chatter = tostring(scene.topic) end
    local roles = {}
    for role, count in pairs(row.roles) do roles[#roles + 1] = { role, count } end
    return Plus.marker .. " group id=" .. row.key .. " n=" .. tostring(row.n) .. " class=" .. class
        .. " plan=" .. planText .. " life=" .. lifeText .. " panic=" .. level .. " chatter=" .. chatter
        .. " roles=" .. Plus.topOf(roles, 6, ",") .. " d=" .. (row.d == math.huge and "-" or box.number(row.d))
end

function Plus.groupLines(now)
    local box = onBox()
    if box == nil then return {} end
    local registry = ProjectALife.ActorRegistry
    if registry == nil or type(registry.each) ~= "function" then return {} end
    Plus.scan = { visited = 0, count = 0, rows = {}, list = {} }
    registry.each(Plus.visit)
    local list = Plus.scan.list
    Plus.scan = nil
    local rows = Plus.rows(now)
    for index = 1, #list do
        local row = list[index]
        local _, distance = nil, nil
        if row.x ~= nil then _, distance = Plus.nearest(rows, row.x, row.y) end
        row.d = distance or math.huge
    end
    table.sort(list, Plus.groupOrder)
    local level = "?"
    local firstDays = ProjectALife.FirstDays
    if type(firstDays) == "table" and type(firstDays.globalLevel) == "function" then
        local ok, value = pcall(firstDays.globalLevel, now)
        if ok and tonumber(value) ~= nil then level = string.format("%.2f", tonumber(value)) end
    end
    local lines = {}
    for index = 1, math.min(#list, Plus.settings.groupCap) do
        lines[index] = Plus.groupLine(box, list[index], level)
    end
    return lines
end

function Plus.afterMinute(now)
    local box = onBox()
    if box == nil then return 0 end
    local spawnOk, spawn = pcall(Plus.spawnText)
    if spawnOk and type(spawn) == "string" then print(spawn) end
    local lines = Plus.groupLines(now)
    if #lines > 0 then print(table.concat(lines, "\n")) end
    return #lines
end

function Plus.countersText()
    local waits = {}
    for reason, count in pairs(Plus.waits) do waits[#waits + 1] = { reason, count } end
    return Plus.marker .. " plus" .. Plus.verdictText()
        .. " errorsTracked=" .. tostring(Plus.errorCount) .. " errorsOverflow=" .. tostring(Plus.errorOverflow)
        .. " stareWaits=" .. Plus.topOf(waits, 8, ",") .. " doorDesync=n/a"
end

function Plus.dumpLines(now)
    local lines = { Plus.headerText(), Plus.countersText() }
    lines[#lines + 1] = Plus.marker .. " events " .. tostring(Plus.eventCount) .. "/" .. tostring(Plus.settings.eventSize)
    local size = Plus.settings.eventSize
    for offset = Plus.eventCount - 1, 0, -1 do
        local index = Plus.eventHead - offset
        if index < 1 then index = index + size end
        local slot = Plus.events[index]
        if slot ~= nil and slot.atMs ~= nil then
            lines[#lines + 1] = Plus.marker .. string.format("  -%5dms %s", math.max(0, now - slot.atMs), slot.text)
        end
    end
    local sigs = {}
    for sig, count in pairs(Plus.errors) do sigs[#sigs + 1] = { sig, count } end
    lines[#lines + 1] = Plus.marker .. " errors " .. Plus.topOf(sigs, Plus.settings.errorSignatures, ";")
    local groups = Plus.groupLines(now)
    for index = 1, #groups do lines[#lines + 1] = groups[index] end
    return lines
end

function Plus.dumpText(now)
    local box = onBox()
    if box == nil then
        local header = Plus.headerText()
        print(header)
        return header
    end
    local lines = Plus.dumpLines(now or nowMs())
    print(lines[1])
    return table.concat(lines, "\n")
end

return Plus
