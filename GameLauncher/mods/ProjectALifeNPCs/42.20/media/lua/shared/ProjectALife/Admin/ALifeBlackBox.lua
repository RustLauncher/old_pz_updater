require "ProjectALife/Compat/ALifeCompatRegistry"
ProjectALife = ProjectALife or {}

local BlackBox = {
    marker = "[ALIFE-BB]",

    BUILD = "1.3.15",
    buildRead = false,
    settings = {

        ringSize = 48,

        freezeMs = 2600,

        stationaryActionFreezeMs = 8000,

        stillEpsilon = 0.02,

        dumpCooldownMs = 10000,

        beatGapResetMs = 1500,

        traversalGraceMs = 1000,

        autoDumpsPerMinute = 6,
        autoRingLines = 12,
        autoTraceLines = 6,

        traceEveryMs = 500,
        traceSize = 16,

        detectCooldownMs = 30000,
        detectLinesPerMinute = 20,
        homingSamples = 6,
        homingIssuesPerSecond = 0.6,
        homingGoalTiles = 1.0,
        homingTargetMoveTiles = 1.5,
        wrongWayTiles = 12,
        wrongWayGainTiles = 1.5,
        backWalkSamples = 4,
        backWalkTiles = 1.2,
        backWalkStepTiles = 0.15,
        backWalkAngle = 120,

        wrongWayFreshMs = 5000,
        edgeStuckMs = 4000,
        edgeRefusalMs = 10000,

        climbHoldMs = 8000,

        uidIdleMs = 600000,
        digestEveryMs = 60000,
    },

    tracked = setmetatable({}, { __mode = "k" }),
    pathWatch = setmetatable({}, { __mode = "k" }),

    byUid = {},

    enabled = false,
    metrics = { events = 0, freezes = 0, dumps = 0, autoDumps = 0, suppressed = 0,
        rebased = 0, linesHeld = 0, detect = {}, freezeKinds = {} },
    budget = { windowAtMs = nil, used = 0, suppressed = 0, linesAtMs = nil, lines = 0 },
    nextDigestAtMs = nil,
    digestBase = {},
}
ProjectALife.BlackBox = BlackBox

BlackBox.stationaryPhases = { reload = true, reload_rack = true, aim = true, cover = true,
    draw = true, recovery = true, hold = true }
BlackBox.deadlineModes = { native = true, native_pending = true, picking = true }

BlackBox.retreatWords = { "retreat", "flee", "withdraw", "fall_back", "fallback", "panic",
    "cover", "reposition", "kite", "regroup" }

BlackBox.groundStates = { "onground", "falldown", "getdown", "getup", "knockeddown",
    "staggerback-knockeddown", "hitreaction-onfloor", "hitreaction-gettingup",
    "vehiclecollision-falldown", "vehiclecollision-onground", "fakedead" }
BlackBox.groundMemo, BlackBox.groundMemoSize = {}, 0

BlackBox.atan2 = math.atan2 or math.atan

function BlackBox.readBuild()
    local catalog = ProjectALife.Catalog
    if BlackBox.buildRead == true or catalog == nil then return BlackBox.BUILD end
    BlackBox.buildRead = true
    local id = catalog.MOD_ID
    if type(id) == "string" and id ~= "" and type(getModInfoByID) == "function" then
        BlackBox.BUILD = BlackBox.modVersion(id) or BlackBox.BUILD
    end
    local stamp = catalog.BUILD_STAMP
    if type(stamp) == "string" and stamp ~= "" then BlackBox.BUILD = BlackBox.BUILD .. "+" .. stamp end
    return BlackBox.BUILD
end

function BlackBox.modVersion(id)
    for _, key in ipairs({ id, "\\" .. id }) do
        local ok, info = pcall(getModInfoByID, key)
        if ok and info ~= nil and type(info.getModVersion) == "function" then
            local read, version = pcall(info.getModVersion, info)
            if read and version ~= nil and tostring(version) ~= "" then return tostring(version) end
        end
    end
    return nil
end

function BlackBox.setEnabled(enabled)
    local was = BlackBox.enabled == true
    BlackBox.enabled = enabled == true
    local plus = ProjectALife.BlackBoxPlus
    if plus ~= nil and was ~= BlackBox.enabled then pcall(plus.onSwitch, BlackBox.enabled) end
    if not BlackBox.enabled then
        BlackBox.tracked = setmetatable({}, { __mode = "k" })
        BlackBox.byUid = {}
        BlackBox.budget = { windowAtMs = nil, used = 0, suppressed = 0, linesAtMs = nil, lines = 0 }
        BlackBox.nextDigestAtMs = nil
    end
    return BlackBox.enabled
end

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function BlackBox.saveReport(kind, text)
    if type(getFileWriter) ~= "function" then return false end
    local name = "alife_blackbox_latest.txt"
    if kind == "qa" then name = "alife_qa_latest.txt"
    elseif kind == "towns" then name = "alife_towns_latest.txt"
    elseif kind == "safehouse" then name = "alife_safehouse_latest.txt" end
    local writer
    local ok = pcall(function()
        writer = getFileWriter(name, true, false)
        if writer == nil then return end
        writer:write("capturedAtMs=" .. tostring(nowMs()) .. "\n" .. tostring(text) .. "\n")
    end)
    if writer == nil then return false end
    local closed = pcall(function() writer:close() end)
    return ok and closed
end

function BlackBox.forget(shell)
    if shell == nil then return false end
    BlackBox.tracked[shell] = nil
    BlackBox.pathWatch[shell] = nil
    return true
end

function BlackBox.newEntry()
    return { ring = {}, head = 0, count = 0, watch = {} }
end

local function record(shell)
    local entry = BlackBox.tracked[shell]
    if entry == nil then
        entry = BlackBox.newEntry()
        BlackBox.tracked[shell] = entry
    end
    return entry
end

function BlackBox.ringIndex(head, offset, size)
    local index = head - offset
    if index < 1 then index = index + size end
    return index
end

function BlackBox.push(entry, atMs, kind, detail)
    local size = BlackBox.settings.ringSize
    local head = (tonumber(entry.head) or 0) + 1
    if head > size then head = 1 end
    entry.head = head
    local slot = entry.ring[head]
    if slot == nil then
        slot = {}
        entry.ring[head] = slot
    end
    slot.atMs, slot.kind, slot.detail = atMs, kind, detail
    local count = (tonumber(entry.count) or 0) + 1
    if count > size then count = size end
    entry.count = count
    entry.lastEventAtMs = atMs
    BlackBox.metrics.events = BlackBox.metrics.events + 1
end

function BlackBox.note(shell, kind, detail)
    if not BlackBox.enabled or shell == nil then return end
    BlackBox.push(record(shell), nowMs(), tostring(kind or "?"), tostring(detail or ""))
end

function BlackBox.liveElsewhere(known, shell, now)
    local other = known.shell
    if other == nil or other == shell or BlackBox.tracked[other] ~= known then return false end
    local gap = now - (tonumber(known.lastTickAtMs) or -math.huge)
    return gap >= 0 and gap <= BlackBox.settings.beatGapResetMs
end

function BlackBox.duplicate(shell, entry, known, uid, now)
    entry.dupOf = known
    local x, y = BlackBox.xyOf(shell)
    local here = BlackBox.number(x) .. "," .. BlackBox.number(y)
    local there = BlackBox.number(known.x) .. "," .. BlackBox.number(known.y)
    BlackBox.push(entry, now, "dup-uid", "other at " .. there)
    local quietSince = known.lastEventAtMs
    BlackBox.push(known, now, "dup-uid", "other at " .. here)
    known.lastEventAtMs = quietSince
    local counts = BlackBox.metrics.detect
    counts["dup-uid"] = (counts["dup-uid"] or 0) + 1
    if BlackBox.spendLine(now) then
        print(BlackBox.marker .. " detect=dup-uid uid=" .. tostring(uid) .. " at=" .. here .. " other=" .. there)
    end
end

function BlackBox.bindUid(shell, entry, uid, now)
    if type(uid) ~= "string" then return entry end
    now = tonumber(now) or nowMs()
    local known = BlackBox.byUid[uid]
    if entry.uid == uid then
        if known ~= entry then
            if known ~= nil and BlackBox.liveElsewhere(known, shell, now) then

                if entry.dupOf ~= known then BlackBox.duplicate(shell, entry, known, uid, now) end
            else

                BlackBox.byUid[uid] = entry
            end
        end
        return entry
    end
    if entry.uid ~= nil then
        entry = BlackBox.newEntry()
        BlackBox.tracked[shell] = entry
    end
    if known ~= nil and known ~= entry and BlackBox.liveElsewhere(known, shell, now) then
        BlackBox.duplicate(shell, entry, known, uid, now)
    else
        if known ~= nil and known ~= entry then
            local size = BlackBox.settings.ringSize
            for offset = size - 1, 0, -1 do
                local slot = entry.ring[BlackBox.ringIndex(entry.head, offset, size)]
                if slot ~= nil and slot.atMs ~= nil then
                    BlackBox.push(known, slot.atMs, slot.kind, slot.detail)
                end
            end
            BlackBox.push(known, now, "rebound", "new body")
            known.lastX, known.lastY, known.lastRequest = nil, nil, nil

            if known.shell ~= nil and BlackBox.tracked[known.shell] == known then
                BlackBox.tracked[known.shell] = nil
            end
            BlackBox.tracked[shell] = known
            entry = known
        end
        BlackBox.byUid[uid] = entry
    end
    entry.uid, entry.shell = uid, shell
    return entry
end

function BlackBox.describeObject(object)
    if object == nil then return "nil" end
    local parts = {}
    local function put(label, fn)
        local ok, value = pcall(fn)
        if ok and value ~= nil and value ~= "" then
            parts[#parts + 1] = label .. "=" .. tostring(value)
        end
    end
    put("class", function()
        local name = tostring(object)

        local short = string.match(name, "([%w_]+)@") or name
        return short
    end)
    put("sprite", function()
        return object:getSprite() and object:getSprite():getName()
    end)
    put("open", function()
        if object.IsOpen == nil then return nil end
        return object:IsOpen()
    end)
    put("locked", function()
        if object.isLocked == nil then return nil end
        return object:isLocked()
    end)
    put("byKey", function()
        if object.isLockedByKey == nil then return nil end
        return object:isLockedByKey()
    end)
    put("barricaded", function()
        if object.isBarricaded == nil then return nil end
        return object:isBarricaded()
    end)
    put("smashed", function()
        if object.isSmashed == nil then return nil end
        return object:isSmashed()
    end)
    put("hoppable", function()
        if object.isHoppable == nil then return nil end
        return object:isHoppable()
    end)
    return table.concat(parts, " ")
end

function BlackBox.variable(shell, name)
    if shell == nil or shell.getVariableString == nil then return "" end
    local ok, value = pcall(shell.getVariableString, shell, name)
    if not ok then return "" end
    return tostring(value or "")
end

function BlackBox.diffInto(entry, key, value, now, quiet)
    value = tostring(value or "")
    local watch = entry.watch
    if watch[key] ~= value then
        watch[key] = value
        local quietSince = entry.lastEventAtMs
        BlackBox.push(entry, now, key, value)
        if quiet == true and quietSince ~= nil then entry.lastEventAtMs = quietSince end
    end
end

function BlackBox.dataOf(shell)
    if shell == nil then return nil end
    if shell.hasModData ~= nil then
        local ok, has = pcall(shell.hasModData, shell)
        if ok and has == false then return nil end
    end
    if shell.getModData == nil then return nil end
    local ok, data = pcall(shell.getModData, shell)
    if ok and type(data) == "table" then return data end
    return nil
end

function BlackBox.shellUid(shell)
    local data = BlackBox.dataOf(shell)
    return data ~= nil and data.ProjectALifeUID or nil
end

function BlackBox.xyOf(object)
    if object == nil or object.getX == nil or object.getY == nil then return nil end
    local okX, x = pcall(object.getX, object)
    local okY, y = pcall(object.getY, object)
    if okX and okY and type(x) == "number" and type(y) == "number" then return x, y end
    return nil
end

function BlackBox.headingOf(shell)
    if shell == nil or shell.getForwardDirection == nil then return nil end
    local ok, vector = pcall(shell.getForwardDirection, shell)
    if not ok or vector == nil then return nil end
    local x, y = BlackBox.xyOf(vector)
    if x == nil or (x == 0 and y == 0) then return nil end
    return math.deg(BlackBox.atan2(y, x))
end

function BlackBox.angleGap(a, b)
    local gap = a - b
    while gap > 180 do gap = gap - 360 end
    while gap < -180 do gap = gap + 360 end
    return gap
end

function BlackBox.number(value, digits)
    local number = tonumber(value)
    if number == nil then return "?" end
    return string.format(digits == 0 and "%.0f" or "%.1f", number)
end

function BlackBox.targetId(target)
    if target == nil then return "-" end
    local uid = BlackBox.shellUid(target)
    if uid ~= nil then return tostring(uid) end
    if type(instanceof) == "function" then
        local ok, player = pcall(instanceof, target, "IsoPlayer")
        if ok and player == true and target.getUsername ~= nil then
            local named, name = pcall(target.getUsername, target)
            if named and name ~= nil then return "player:" .. tostring(name) end
        end
    end

    if target.getOnlineID ~= nil then
        local ok, id = pcall(target.getOnlineID, target)
        if ok and tonumber(id) ~= nil and tonumber(id) ~= -1 then return "online:" .. tostring(id) end
    end
    local objectId
    if target.getID ~= nil then
        local ok, id = pcall(target.getID, target)
        if ok then objectId = tonumber(id) end
    end

    if objectId == nil then objectId = tonumber(string.match(tostring(target), "ID:%s*(%-?%d+)")) end
    if objectId ~= nil then return string.format("obj:%d", math.floor(objectId)) end
    local hash = string.match(tostring(target), "@(%x+)")
    if hash ~= nil then return "z@" .. hash end
    return "?"
end

function BlackBox.hostileOf(data)
    local perception = ProjectALife.Perception
    local uid = type(data) == "table" and data.ProjectALifeUID or nil
    if perception == nil or uid == nil then return nil end
    local held = type(perception.engagements) == "table" and perception.engagements[uid] or nil
    if type(held) == "table" then
        local x, y = BlackBox.xyOf(held.target)
        if x == nil then x, y = tonumber(held.x), tonumber(held.y) end
        if x ~= nil and y ~= nil then return x, y, held.kind, held.target, held.atMs, false end
    end
    local known = type(perception.lastKnown) == "table" and perception.lastKnown[uid] or nil
    if type(known) == "table" and tonumber(known.x) ~= nil and tonumber(known.y) ~= nil then
        return tonumber(known.x), tonumber(known.y), known.kind, known.target, known.atMs, true
    end
    return nil
end

function BlackBox.combatRequest(shell)
    local combat = ProjectALife.Combat
    local requests = combat ~= nil and combat.pathRequests or nil
    if type(requests) ~= "table" then return nil end
    local request = requests[shell]
    return type(request) == "table" and request or nil
end

function BlackBox.refusalOf(shell, now)
    local traversal = ProjectALife.ObstacleTraversal
    if traversal == nil or shell == nil then return nil end
    if type(traversal.lastRefusal) == "function" then
        local ok, kind, atMs, edgeKey = pcall(traversal.lastRefusal, shell)
        local at = ok and tonumber(atMs) or nil
        if ok and kind ~= nil and at ~= nil then return tostring(kind), edgeKey, at, now - at end
    end
    local refused = type(traversal.climbRefusedAtMs) == "table"
        and tonumber(traversal.climbRefusedAtMs[shell]) or nil
    if refused == nil then return nil end
    local edge = type(traversal.lastEdgeKey) == "table" and traversal.lastEdgeKey[shell] or nil
    return "climb", edge, refused, now - refused
end

function BlackBox.edgeText(shell, edgeKey, now)
    local traversal = ProjectALife.ObstacleTraversal
    local parts = { "edge=" .. tostring(edgeKey or "-") }
    if traversal == nil then return parts[1] .. " traversal=?" end
    if edgeKey ~= nil then
        local banned = type(traversal.edgeBans) == "table" and tonumber(traversal.edgeBans[edgeKey]) or nil
        parts[#parts + 1] = (banned ~= nil and banned > now) and ("ban+" .. math.floor(banned - now) .. "ms") or "ban=-"
        local by = type(traversal.edgeBanBy) == "table" and traversal.edgeBanBy[edgeKey] or nil
        if by ~= nil then parts[#parts + 1] = "banBy=" .. tostring(by) end
        local lease = type(traversal.reservations) == "table" and traversal.reservations[edgeKey] or nil
        if type(lease) == "table" and now < (tonumber(lease.untilMs) or 0) then
            local holder = lease.owner == shell and "self" or (BlackBox.shellUid(lease.owner) or "?")
            parts[#parts + 1] = "lease=" .. tostring(holder) .. "+" .. math.floor(lease.untilMs - now) .. "ms"
        else
            parts[#parts + 1] = "lease=-"
        end
    end
    local log = type(traversal.climbLog) == "table" and traversal.climbLog[shell] or nil
    if type(log) == "table" then
        parts[#parts + 1] = "budget=" .. tostring(log.count or 0) .. "/" .. tostring(traversal.climbBudget or "?")
    end
    return table.concat(parts, " ")
end

function BlackBox.legOf(data)
    local decisions = ProjectALife.DecisionLoop
    local uid = type(data) == "table" and data.ProjectALifeUID or nil
    if decisions == nil or type(decisions.states) ~= "table" or uid == nil then return nil end
    local state = decisions.states[uid]
    return type(state) == "table" and state or nil
end

function BlackBox.heldDown(data)
    return data.ProjectALifeInjured ~= nil or data.ProjectALifeBleedOutAtMs ~= nil
        or data.ProjectALifeDownedUntilMs ~= nil
end

function BlackBox.groundState(state)
    if type(state) ~= "string" or state == "" then return false end
    local known = BlackBox.groundMemo[state]
    if known ~= nil then return known end
    local lowered = string.lower(state)
    local grounded = false
    local list = BlackBox.groundStates
    for index = 1, #list do
        local prefix = list[index]
        if string.sub(lowered, 1, #prefix) == prefix then
            grounded = true
            break
        end
    end
    if BlackBox.groundMemoSize >= 64 then
        BlackBox.groundMemo, BlackBox.groundMemoSize = {}, 0
    end
    BlackBox.groundMemo[state] = grounded
    BlackBox.groundMemoSize = BlackBox.groundMemoSize + 1
    return grounded
end

function BlackBox.downed(shell, data, entry, now)
    if data.ProjectALifeInjured ~= nil or data.ProjectALifeBleedOutAtMs ~= nil then return "held" end
    local lease = tonumber(data.ProjectALifeDownedUntilMs)
    if lease ~= nil and (tonumber(now) or 0) < lease then return "held" end
    local watch = type(entry) == "table" and entry.watch or nil
    if type(watch) == "table" and BlackBox.groundState(watch.state) then return "ground" end
    local fence = ProjectALife.AIFence
    if type(fence) == "table" and type(fence.proneSinceMs) == "table" and fence.proneSinceMs[shell] ~= nil then
        return "prone"
    end
    if type(shell.isDead) == "function" then
        local ok, dead = pcall(shell.isDead, shell)
        if ok and dead == true then return "dead" end
    end
    return nil
end

function BlackBox.retreating(data)
    for _, key in ipairs({ "ProjectALifeBehaviorState", "ProjectALifeBehaviorIntent",
            "ProjectALifeCombatPhase", "ProjectALifeTacticalRole" }) do
        local value = data[key]
        if type(value) == "string" then
            local lower = string.lower(value)
            for _, word in ipairs(BlackBox.retreatWords) do
                if string.find(lower, word, 1, true) then return true end
            end
        end
    end
    return false
end

function BlackBox.goalText(shell, data, now, x, y)
    local request = BlackBox.combatRequest(shell)
    if request ~= nil and tonumber(request.x) ~= nil then
        local gx, gy = tonumber(request.x), tonumber(request.y) or 0
        local entry = BlackBox.tracked[shell]
        return "combat " .. BlackBox.number(gx) .. "," .. BlackBox.number(gy)
            .. " dist=" .. (x ~= nil and BlackBox.number(math.sqrt((gx - x) ^ 2 + (gy - y) ^ 2)) or "?")
            .. " age=" .. (tonumber(request.atMs) and math.floor(now - request.atMs) or "?")
            .. " progress=" .. (tonumber(request.lastProgressAtMs) and math.floor(now - request.lastProgressAtMs) or "?")
            .. " started=" .. tostring(request.started) .. " pace=" .. tostring(request.pace)
            .. " rebuilds=" .. tostring(entry and entry.rebuilds or 0)
            .. " reaims=" .. tostring(entry and entry.reaims or 0)
            .. BlackBox.leashGoal(shell, gx, gy)
    end
    local state = BlackBox.legOf(data)
    if state == nil then
        return ProjectALife.DecisionLoop == nil and "?" or "none"
    end
    local action = type(state.action) == "table" and state.action or nil
    local target = action ~= nil and type(action.target) == "table" and action.target or nil
    if target == nil or tonumber(target.x) == nil then
        return "leg=" .. tostring(state.kind) .. "/" .. tostring(state.intent) .. " none"
            .. BlackBox.leashGoal(shell, nil, nil)
    end
    local tx, ty = tonumber(target.x), tonumber(target.y) or 0

    local started = tonumber(state.startedAtMs)
    local issued = tonumber(action.startedAtMs)
    local lanes = ProjectALife.DecisionLoop.lanes
    local near = type(lanes) == "table" and type(lanes.nearest2) == "table"
        and tonumber(lanes.nearest2[data.ProjectALifeUID]) or nil
    return "leg=" .. tostring(state.kind) .. "/" .. tostring(state.intent)
        .. " " .. BlackBox.number(tx) .. "," .. BlackBox.number(ty)
        .. " goalDist=" .. (x ~= nil and BlackBox.number(math.sqrt((tx - x) ^ 2 + (ty - y) ^ 2)) or "?")
        .. " legAge=" .. (started ~= nil and math.floor(now - started) or "?")
        .. " issueAge=" .. (issued ~= nil and math.floor(now - issued) or "?")
        .. " roam=" .. tostring(state.roamLeg == true)
        .. " nearestPlayer=" .. (near ~= nil and BlackBox.number(math.sqrt(near)) or "?")
        .. BlackBox.leashGoal(shell, tx, ty)
end

function BlackBox.leashGoal(shell, gx, gy)
    local combat, records = ProjectALife.Combat, ProjectALife.ActorRegistry
    if combat == nil or type(combat.leashOutside) ~= "function" or type(combat.leashFor) ~= "function"
            or records == nil or type(records.peek) ~= "function" then return "" end
    local data = BlackBox.dataOf(shell)
    local uid = data ~= nil and data.ProjectALifeUID or nil
    local actor = type(uid) == "string" and records.peek(uid) or nil
    if type(actor) ~= "table" then return "" end
    local anchor, range = combat.leashFor(actor)
    local fromAnchor = combat.leashOutside(shell, anchor, range)
    if fromAnchor == nil then return "" end
    local text = " fromAnchor=" .. BlackBox.number(fromAnchor) .. " r=" .. BlackBox.number(range)

    local slack = type(combat.settings) == "table" and tonumber(combat.settings.leashReturnSlack) or 1
    local ax, ay, r = tonumber(anchor.x), tonumber(anchor.y), tonumber(range) + slack
    gx, gy = tonumber(gx), tonumber(gy)
    if gx ~= nil and gy ~= nil and (gx - ax) ^ 2 + (gy - ay) ^ 2 <= r * r then
        return " return=leash" .. text
    end
    return " leash=outside" .. text .. " noReturn"
end

function BlackBox.holdLive(shell, now, ageMs)
    local combat = ProjectALife.Combat
    local holdMs = combat ~= nil and type(combat.settings) == "table" and tonumber(combat.settings.climbHoldMs)
        or BlackBox.settings.climbHoldMs
    local traversal = ProjectALife.ObstacleTraversal
    if traversal ~= nil and type(traversal.climbRefusedRecently) == "function" then
        local ok, live = pcall(traversal.climbRefusedRecently, shell, now, holdMs)
        if ok then return live == true end
    end
    return tonumber(ageMs) ~= nil and ageMs < holdMs
end

function BlackBox.leashText(shell, now)
    local combat, registry = ProjectALife.Combat, ProjectALife.ActorRegistry
    if combat == nil or type(combat.leashFor) ~= "function"
            or registry == nil or type(registry.peek) ~= "function" then return nil end
    local data = BlackBox.dataOf(shell)
    local uid = data ~= nil and data.ProjectALifeUID or nil
    if type(uid) ~= "string" then return nil end
    local actor = registry.peek(uid)
    if type(actor) ~= "table" then return nil end
    local anchor, range = combat.leashFor(actor)
    if type(anchor) ~= "table" or tonumber(range) == nil then return nil end
    local stance = type(actor.memory) == "table" and actor.memory.stance or nil
    local x, y = BlackBox.xyOf(shell)
    local ax, ay = tonumber(anchor.x), tonumber(anchor.y)
    local text = "leash " .. tostring(stance) .. " r=" .. BlackBox.number(range)
        .. " fromAnchor=" .. ((x ~= nil and ax ~= nil and ay ~= nil)
            and BlackBox.number(math.sqrt((x - ax) ^ 2 + (y - ay) ^ 2)) or "?")
    local aim = type(combat.aimState) == "table" and combat.aimState[shell] or nil
    local since = type(aim) == "table" and tonumber(aim.leashHoldSinceMs) or nil
    if since ~= nil and tonumber(now) ~= nil then
        text = text .. " held=" .. math.floor(now - since) .. "ms"
    end
    return text
end

function BlackBox.holdText(shell, now)
    local traversal = ProjectALife.ObstacleTraversal
    if traversal == nil then return "?" end
    local kind, edge, refusedAt, ageMs = BlackBox.refusalOf(shell, now)
    if kind == nil or refusedAt == nil then return BlackBox.leashText(shell, now) or "none" end
    local live = BlackBox.holdLive(shell, now, ageMs)

    if not live then
        local leash = BlackBox.leashText(shell, now)
        if leash ~= nil then
            return leash .. " lastRefusal=" .. kind .. " " .. math.floor(ageMs) .. "ms ago "
                .. BlackBox.edgeText(shell, edge, now)
        end
    end
    local text = kind .. " age=" .. math.floor(ageMs) .. "ms " .. (live and "live" or "over")
    if type(traversal.queueHoldMs) == "function" then
        local ok, cap = pcall(traversal.queueHoldMs, shell, now)
        if ok and tonumber(cap) ~= nil then text = text .. " queueCap=" .. math.floor(cap) .. "ms" end
    end
    return text .. " " .. BlackBox.edgeText(shell, edge, now)
end

function BlackBox.targetText(data, now, x, y)
    local tx, ty, kind, target, atMs = BlackBox.hostileOf(data)
    if tx == nil then return ProjectALife.Perception == nil and "?" or "none" end
    return "id=" .. BlackBox.targetId(target) .. " kind=" .. tostring(kind)
        .. " dist=" .. (x ~= nil and BlackBox.number(math.sqrt((tx - x) ^ 2 + (ty - y) ^ 2)) or "?")
        .. " seenAgo=" .. (tonumber(atMs) and math.floor(now - atMs) or "?")
end

function BlackBox.drivenHere(shell)
    local fence = ProjectALife.AIFence
    if fence == nil or type(fence.authorityFor) ~= "function" then return true end
    local ok, answer = pcall(fence.authorityFor, shell)
    return not ok or answer ~= false
end

function BlackBox.whyLines(shell, data, now, lines)
    local marker = BlackBox.marker
    local x, y = BlackBox.xyOf(shell)
    lines[#lines + 1] = marker .. " pathWhy=" .. tostring(data.ProjectALifePathWhy or "none")
    lines[#lines + 1] = marker .. " why decide=" .. tostring(data.ProjectALifeBehaviorState)
        .. "/" .. tostring(data.ProjectALifeBehaviorIntent)
        .. " tactic=" .. tostring(data.ProjectALifeTacticalRole)
        .. " tgtDist=" .. BlackBox.number(data.ProjectALifeTargetDistance)
    if not BlackBox.drivenHere(shell) then
        lines[#lines + 1] = marker .. " why goal=? (driven elsewhere)"
        lines[#lines + 1] = marker .. " why hold=? (driven elsewhere)"
        lines[#lines + 1] = marker .. " why target=? (driven elsewhere)"
        return
    end
    local ok, text = pcall(BlackBox.goalText, shell, data, now, x, y)
    lines[#lines + 1] = marker .. " why goal=" .. (ok and tostring(text) or "?")
    ok, text = pcall(BlackBox.holdText, shell, now)
    lines[#lines + 1] = marker .. " why hold=" .. (ok and tostring(text) or "?")
    ok, text = pcall(BlackBox.targetText, data, now, x, y)
    lines[#lines + 1] = marker .. " why target=" .. (ok and tostring(text) or "?")
end

function BlackBox.snapshotFields(shell, now)
    now = tonumber(now) or nowMs()
    local data = BlackBox.dataOf(shell) or {}
    local x, y = BlackBox.xyOf(shell)
    local parts = {}
    local health
    if shell ~= nil and shell.getHealth ~= nil then
        local ok, value = pcall(shell.getHealth, shell)
        if ok then health = value end
    end
    parts[#parts + 1] = "hp=" .. BlackBox.number(health) .. "/" .. BlackBox.number(data.ProjectALifeMaximumHealth)
    parts[#parts + 1] = "beh=" .. tostring(data.ProjectALifeBehaviorState) .. "/" .. tostring(data.ProjectALifeBehaviorIntent)
    parts[#parts + 1] = "phase=" .. tostring(data.ProjectALifeCombatPhase) .. "/" .. tostring(data.ProjectALifeTacticalRole)
    parts[#parts + 1] = "abort=" .. tostring(data.ProjectALifeCombatAbortReason)
    parts[#parts + 1] = "upper=" .. tostring(data.ProjectALifeUpperPursuitReason)
    parts[#parts + 1] = "tgtd=" .. BlackBox.number(data.ProjectALifeTargetDistance)
    parts[#parts + 1] = "path=" .. (data.ProjectALifePathActive == true and "on" or "off")
    parts[#parts + 1] = "pathWhy=" .. tostring(data.ProjectALifePathWhy or "none")
    if BlackBox.drivenHere(shell) then
        local ok, goal = pcall(BlackBox.goalText, shell, data, now, x, y)
        parts[#parts + 1] = "goal=[" .. (ok and tostring(goal) or "?") .. "]"
        local okHold, hold = pcall(BlackBox.holdText, shell, now)
        parts[#parts + 1] = "hold=[" .. (okHold and tostring(hold) or "?") .. "]"
    else
        parts[#parts + 1] = "goal=[? elsewhere] hold=[? elsewhere]"
    end
    local traversal = ProjectALife.ObstacleTraversal
    local active = traversal ~= nil and type(traversal.active) == "table" and traversal.active[shell] or nil
    if type(active) == "table" then
        parts[#parts + 1] = "trav=" .. tostring(active.mode) .. "/" .. tostring(active.nativeKind)
            .. (tonumber(active.deadlineAtMs) and ("+" .. math.floor(active.deadlineAtMs - now)) or "")
    else
        parts[#parts + 1] = "trav=-"
    end
    local entry = BlackBox.tracked[shell]
    parts[#parts + 1] = "still=" .. ((entry ~= nil and entry.lastMoveAtMs ~= nil)
        and (math.floor(now - entry.lastMoveAtMs) .. "ms") or "?")
    parts[#parts + 1] = "pace=" .. tostring(data.ProjectALifePace)
    local state
    if shell ~= nil and shell.getActionStateName ~= nil then
        local okState, value = pcall(shell.getActionStateName, shell)
        if okState then state = value end
    end
    parts[#parts + 1] = "st=" .. tostring(state)
    parts[#parts + 1] = "det=" .. tostring(entry ~= nil and entry.lastDetect or "-")
    return table.concat(parts, " ")
end

function BlackBox.relationLines(shell, lines)
    local registry, relations, locator = ProjectALife.ActorRegistry, ProjectALife.Relations, ProjectALife.PlayerLocator
    if registry == nil or type(registry.peek) ~= "function"
            or relations == nil or type(relations.auditLine) ~= "function"
            or locator == nil or type(locator.list) ~= "function" then return end
    local data = BlackBox.dataOf(shell)
    local actor = data and registry.peek(data.ProjectALifeUID)
    local x, y = BlackBox.xyOf(shell)
    if actor == nil or x == nil or y == nil then return end
    for _, player in ipairs(locator.list()) do
        if type(player.getX) == "function" and type(player.getY) == "function" then
            local dx, dy = player:getX() - x, player:getY() - y
            if dx * dx + dy * dy <= 90 * 90 then
                local text = relations.auditLine(actor, player)
                if text ~= nil then lines[#lines + 1] = text end
            end
        end
    end
end

function BlackBox.hordeLines(shell, lines)
    local horde = ProjectALife.HordeRelations
    if horde ~= nil and type(horde.auditLines) == "function" then horde.auditLines(shell, lines) end
end

function BlackBox.dump(shell, reason, automatic)
    if shell == nil then return end
    local startedAt = nowMs()
    local lines = {}
    local function line(text) lines[#lines + 1] = text end
    local now = startedAt
    local data = BlackBox.dataOf(shell) or {}
    local held = ""
    if automatic == true and BlackBox.budget.suppressed > 0 then
        held = " suppressed=" .. BlackBox.budget.suppressed
        BlackBox.budget.suppressed = 0
    end
    line(BlackBox.marker .. " ==== dump reason=" .. tostring(reason or "manual")
        .. " uid=" .. tostring(data.ProjectALifeUID) .. held)
    pcall(function()
        local registry = ProjectALife.ActorRegistry
        local actor = registry and registry.read(data.ProjectALifeUID)
        line(BlackBox.marker .. " generation=" .. tostring(data.ProjectALifeGeneration)
            .. " onlineId=" .. tostring(shell:getOnlineID())
            .. " lifecycle=" .. tostring(actor and actor.lifecycle)
            .. " nativeExists=" .. tostring(shell:isExistInTheWorld())
            .. " health=" .. tostring(shell:getHealth())
            .. " maximumHealth=" .. tostring(data.ProjectALifeMaximumHealth)
            .. " healthRevision=" .. tostring(data.ProjectALifeHealthRevision))
    end)
    pcall(function()
        line(BlackBox.marker .. " pos=" .. string.format("%.1f,%.1f,%d",
            shell:getX(), shell:getY(), shell:getZ())
            .. " state=" .. tostring(shell:getActionStateName())
            .. " aiming=" .. tostring(shell:isAiming())
            .. " moving=" .. tostring(shell:isMoving()))
    end)
    line(BlackBox.marker .. " phase=" .. tostring(data.ProjectALifeCombatPhase)
        .. " conduct=" .. tostring(data.ProjectALifeConduct)
        .. " pathActive=" .. tostring(data.ProjectALifePathActive)
        .. " pace=" .. tostring(data.ProjectALifePace)
        .. " abort=" .. tostring(data.ProjectALifeCombatAbortReason)
        .. " upper=" .. tostring(data.ProjectALifeUpperPursuitReason))
    line(BlackBox.marker .. " bump=" .. BlackBox.variable(shell, "BumpType")
        .. " bumpDone=" .. BlackBox.variable(shell, "BumpDone")
        .. " bumpFinished=" .. BlackBox.variable(shell, "BumpAnimFinished")
        .. " gesture=" .. BlackBox.variable(shell, "ALifeGesture"))
    local stamps = {}
    for _, key in ipairs({ "ProjectALifeStaggerUntilMs", "ProjectALifeLastHitAtMs",
            "ProjectALifeHoldFireUntilMs", "ProjectALifeHealDoneAtMs",
            "ProjectALifeSuppressUntilMs", "ProjectALifeSprintUntilMs",
            "ProjectALifeCombatAbortUntilMs" }) do
        local value = tonumber(data[key])
        if value ~= nil then
            stamps[#stamps + 1] = string.gsub(key, "ProjectALife", "")
                .. (value > now and ("+" .. (value - now)) or ("-" .. (now - value)))
        end
    end
    line(BlackBox.marker .. " stamps: " .. (stamps[1] and table.concat(stamps, " ") or "none"))
    pcall(function()
        local traversal = ProjectALife.ObstacleTraversal
        local active = traversal and traversal.active and traversal.active[shell]
        if active ~= nil then
            line(BlackBox.marker .. " traversal mode=" .. tostring(active.mode)
                .. " kind=" .. tostring(active.nativeKind)
                .. " deadline" .. (tonumber(active.deadlineAtMs)
                    and ("+" .. (active.deadlineAtMs - now)) or "=?"))
        end
    end)
    BlackBox.whyLines(shell, data, now, lines)
    BlackBox.relationLines(shell, lines)
    if automatic ~= true then BlackBox.hordeLines(shell, lines) end
    local entry = BlackBox.tracked[shell]
    if entry ~= nil then
        BlackBox.traceLines(entry, now, lines, automatic == true
            and BlackBox.settings.autoTraceLines or BlackBox.settings.traceSize)
        local size = BlackBox.settings.ringSize
        local shown = size
        if automatic == true then shown = BlackBox.settings.autoRingLines end
        line(BlackBox.marker .. " ring " .. tostring(entry.count or 0) .. "/" .. size
            .. " head=" .. tostring(entry.head))
        for offset = shown - 1, 0, -1 do
            local index = BlackBox.ringIndex(entry.head, offset, size)
            local slot = entry.ring[index]
            if slot ~= nil and slot.atMs ~= nil then
                line(BlackBox.marker .. string.format("  -%5dms %-12s %s",
                    now - slot.atMs, slot.kind, slot.detail))
            end
        end
    end
    line(BlackBox.marker .. " ==== end")
    print(table.concat(lines, "\n"))
    BlackBox.metrics.dumps = BlackBox.metrics.dumps + 1
    local spent = nowMs() - startedAt
    local runtime = ProjectALife.Runtime
    if spent > 16 and runtime ~= nil and type(runtime.noteDetail) == "function" then
        pcall(runtime.noteDetail, "blackbox_dump", spent)
    end
    return table.concat(lines, "\n")
end

function BlackBox.traceAt(entry, back)
    local size = BlackBox.settings.traceSize
    if entry.trace == nil or back >= (entry.traceCount or 0) then return nil end
    return entry.trace[BlackBox.ringIndex(entry.traceHead, back, size)]
end

function BlackBox.traceLines(entry, now, lines, count)
    local total = math.min(entry.traceCount or 0, count)
    for back = total - 1, 0, -1 do
        local slot = BlackBox.traceAt(entry, back)
        if slot ~= nil then
            lines[#lines + 1] = BlackBox.marker .. " trace -" .. math.floor(now - slot.t) .. "ms"
                .. " at=" .. BlackBox.number(slot.x) .. "," .. BlackBox.number(slot.y)
                .. " hd=" .. BlackBox.number(slot.heading, 0)
                .. " td=" .. BlackBox.number(slot.td)
                .. " goal=" .. (slot.gx ~= nil and (BlackBox.number(slot.gx) .. "," .. BlackBox.number(slot.gy)) or "-")
                .. " issues=" .. tostring(slot.issues)
                .. " beh=" .. tostring(slot.beh) .. " phase=" .. tostring(slot.phase)
        end
    end
end

function BlackBox.watchPath(shell, entry)
    local request = BlackBox.combatRequest(shell)
    if request == nil then
        entry.lastRequest = nil
        return
    end
    if request ~= entry.lastRequest then
        entry.lastRequest, entry.lastRequestAtMs = request, request.atMs
        entry.rebuilds = (entry.rebuilds or 0) + 1
    elseif request.atMs ~= entry.lastRequestAtMs then
        entry.lastRequestAtMs = request.atMs
        entry.reaims = (entry.reaims or 0) + 1
    end
end

function BlackBox.sample(shell, data, entry, now, active)
    local size = BlackBox.settings.traceSize
    if entry.trace == nil then entry.trace, entry.traceHead, entry.traceCount = {}, 0, 0 end
    local head = entry.traceHead + 1
    if head > size then head = 1 end
    entry.traceHead = head
    if entry.traceCount < size then entry.traceCount = entry.traceCount + 1 end
    local slot = entry.trace[head]
    if slot == nil then
        slot = {}
        entry.trace[head] = slot
    end
    slot.t, slot.x, slot.y = now, entry.x, entry.y
    slot.heading = BlackBox.headingOf(shell)
    local tx, ty, kind, target, seenAt, remembered = BlackBox.hostileOf(data)
    slot.tx, slot.ty, slot.tkind, slot.target = tx, ty, kind, target
    slot.stale = remembered == true
        and now - (tonumber(seenAt) or -math.huge) > BlackBox.settings.wrongWayFreshMs
    slot.td = nil
    if tx ~= nil and entry.x ~= nil then slot.td = math.sqrt((tx - entry.x) ^ 2 + (ty - entry.y) ^ 2) end
    local request = BlackBox.combatRequest(shell)
    slot.gx, slot.gy = nil, nil
    if request ~= nil and tonumber(request.x) ~= nil and tonumber(request.y) ~= nil then
        slot.gx, slot.gy = tonumber(request.x), tonumber(request.y)
    end
    slot.rebuilds, slot.reaims = entry.rebuilds or 0, entry.reaims or 0
    slot.issues = slot.rebuilds + slot.reaims
    slot.beh, slot.intent = data.ProjectALifeBehaviorState, data.ProjectALifeBehaviorIntent
    slot.phase, slot.pace = data.ProjectALifeCombatPhase, data.ProjectALifePace
    BlackBox.detectHoming(shell, data, entry, now)
    BlackBox.detectWrongWay(shell, data, entry, now)
    BlackBox.detectBackWalk(shell, data, entry, now)
    BlackBox.detectEdgeStuck(shell, data, entry, now, active)
end

function BlackBox.detected(shell, data, entry, now, name, detail)
    entry.detectAtMs = entry.detectAtMs or {}
    local last = entry.detectAtMs[name]
    if last ~= nil and now - last < BlackBox.settings.detectCooldownMs then return false end
    entry.detectAtMs[name] = now
    entry.lastDetect = name
    local counts = BlackBox.metrics.detect
    counts[name] = (counts[name] or 0) + 1

    local quietSince = entry.lastEventAtMs
    BlackBox.push(entry, now, "detect", name)
    entry.lastEventAtMs = quietSince
    if not BlackBox.spendLine(now) then return true end
    print(BlackBox.marker .. " detect=" .. name .. " uid=" .. tostring(data.ProjectALifeUID)
        .. " at=" .. BlackBox.number(entry.x) .. "," .. BlackBox.number(entry.y) .. " " .. tostring(detail))
    return true
end

function BlackBox.spendLine(now)
    local budget = BlackBox.budget
    if budget.linesAtMs == nil or now < budget.linesAtMs or now - budget.linesAtMs >= 60000 then
        budget.linesAtMs, budget.lines = now, 0
    end
    if (budget.lines or 0) >= BlackBox.settings.detectLinesPerMinute then
        BlackBox.metrics.linesHeld = (BlackBox.metrics.linesHeld or 0) + 1
        return false
    end
    budget.lines = (budget.lines or 0) + 1
    return true
end

function BlackBox.detectHoming(shell, data, entry, now)
    local settings = BlackBox.settings
    local span = settings.homingSamples
    local newest, oldest = BlackBox.traceAt(entry, 0), BlackBox.traceAt(entry, span)
    if newest == nil or oldest == nil or newest.tx == nil or oldest.tx == nil then return false end
    local seconds = (newest.t - oldest.t) / 1000
    if seconds <= 0 then return false end
    local rate = (newest.issues - oldest.issues) / seconds
    if rate < settings.homingIssuesPerSecond then return false end
    local onTarget, errorSum, errorCount = 0, 0, 0
    local reach = settings.homingGoalTiles * settings.homingGoalTiles
    for back = 0, span - 1 do
        local slot = BlackBox.traceAt(entry, back)
        if slot.gx ~= nil and slot.tx ~= nil
                and (slot.gx - slot.tx) ^ 2 + (slot.gy - slot.ty) ^ 2 <= reach then
            onTarget = onTarget + 1
        end
        if slot.heading ~= nil and slot.tx ~= nil and slot.x ~= nil then
            local bearing = math.deg(BlackBox.atan2(slot.ty - slot.y, slot.tx - slot.x))
            errorSum = errorSum + math.abs(BlackBox.angleGap(bearing, slot.heading))
            errorCount = errorCount + 1
        end
    end
    if onTarget < span - 1 then return false end
    local moved = math.sqrt((newest.tx - oldest.tx) ^ 2 + (newest.ty - oldest.ty) ^ 2)
    if moved < settings.homingTargetMoveTiles then return false end
    return BlackBox.detected(shell, data, entry, now, "homing",
        "issues=" .. string.format("%.2f", rate) .. "/s"
        .. " rebuilds=" .. (newest.rebuilds - oldest.rebuilds)
        .. " reaims=" .. (newest.reaims - oldest.reaims)
        .. " goalOnTarget=" .. onTarget .. "/" .. span
        .. " targetMoved=" .. BlackBox.number(moved)
        .. " dist=" .. BlackBox.number(oldest.td) .. "->" .. BlackBox.number(newest.td)
        .. " aimErr=" .. (errorCount > 0 and BlackBox.number(errorSum / errorCount, 0) or "?")
        .. " pace=" .. tostring(newest.pace) .. " tactic=" .. tostring(data.ProjectALifeTacticalRole)
        .. " target=" .. BlackBox.targetId(newest.target))
end

function BlackBox.strafeBlend(shell)
    if type(shell.GetVariable) ~= "function" then return false end
    local readOk, flag = pcall(shell.GetVariable, shell, "ALifeStrafe")
    if not readOk or tostring(flag) ~= "true" then return false end
    local okX, rawX = pcall(shell.GetVariable, shell, "ALifeStrafeX")
    local okY, rawY = pcall(shell.GetVariable, shell, "ALifeStrafeY")
    local blendX, blendY = okX and tonumber(rawX) or 0, okY and tonumber(rawY) or 0
    if blendX == 0 and blendY == 0 then return true, nil end
    return true, math.deg(BlackBox.atan2(blendX, blendY))
end

function BlackBox.detectBackWalk(shell, data, entry, now)
    local settings = BlackBox.settings
    local span = settings.backWalkSamples
    local oldest, newest = BlackBox.traceAt(entry, span - 1), BlackBox.traceAt(entry, 0)
    if oldest == nil or newest == nil or oldest.x == nil or newest.x == nil then return false end
    if data.ProjectALifePathActive ~= true or BlackBox.heldDown(data) then return false end
    if (newest.x - oldest.x) ^ 2 + (newest.y - oldest.y) ^ 2 < settings.backWalkTiles ^ 2 then return false end
    local animations = ProjectALife.Animations
    local clip = type(animations) == "table" and type(animations.current) == "table" and animations.current[shell] or nil
    if clip == "drag_carry" or clip == "drag_body" then return false end
    local strafing, offset = BlackBox.strafeBlend(shell)
    if strafing and offset == nil then return false end
    local gapSum = 0
    for back = span - 1, 1, -1 do
        local from, to = BlackBox.traceAt(entry, back), BlackBox.traceAt(entry, back - 1)
        if from == nil or to == nil or from.x == nil or to.x == nil or to.heading == nil then return false end
        local sx, sy = to.x - from.x, to.y - from.y
        if sx * sx + sy * sy < settings.backWalkStepTiles ^ 2 then return false end
        local reference = to.heading + (offset or 0)
        local gap = math.abs(BlackBox.angleGap(math.deg(BlackBox.atan2(sy, sx)), reference))
        if gap < settings.backWalkAngle then return false end
        gapSum = gapSum + gap
    end
    return BlackBox.detected(shell, data, entry, now, strafing and "strafe-mismatch" or "back-walk",
        "beh=" .. tostring(data.ProjectALifeBehaviorState) .. "/" .. tostring(data.ProjectALifeBehaviorIntent)
        .. " phase=" .. tostring(data.ProjectALifeCombatPhase) .. " pace=" .. tostring(data.ProjectALifePace)
        .. " clip=" .. tostring(clip) .. " held=" .. tostring(data.ProjectALifeHeldBump)
        .. " aimWalk=" .. tostring(data.ProjectALifeAimWalk == true)
        .. " moved=" .. BlackBox.number(math.sqrt((newest.x - oldest.x) ^ 2 + (newest.y - oldest.y) ^ 2))
        .. " turn=" .. BlackBox.number(gapSum / (span - 1), 0)
        .. " blend=" .. (offset ~= nil and BlackBox.number(offset, 0) or "-")
        .. " hostile=" .. tostring(newest.tkind) .. ":" .. BlackBox.targetId(newest.target)
        .. " td=" .. BlackBox.number(oldest.td) .. "->" .. BlackBox.number(newest.td))
end

function BlackBox.detectWrongWay(shell, data, entry, now)
    local settings = BlackBox.settings
    local first, last = BlackBox.traceAt(entry, 6), BlackBox.traceAt(entry, 0)
    if first == nil or last == nil then return false end
    if BlackBox.heldDown(data) then return false end
    local previous
    for back = 6, 0, -2 do
        local slot = BlackBox.traceAt(entry, back)
        if slot.td == nil or slot.x == nil or slot.stale == true then return false end
        if previous ~= nil and slot.td <= previous.td then return false end
        previous = slot
    end
    if first.td > settings.wrongWayTiles then return false end
    local before = math.sqrt((first.x - first.tx) ^ 2 + (first.y - first.ty) ^ 2)
    local after = math.sqrt((last.x - first.tx) ^ 2 + (last.y - first.ty) ^ 2)
    if after - before < settings.wrongWayGainTiles then return false end
    if BlackBox.retreating(data) then return false end
    local state = BlackBox.legOf(data)
    local action = state ~= nil and type(state.action) == "table" and state.action or nil
    local goal = action ~= nil and type(action.target) == "table" and action.target or nil
    local lanes = ProjectALife.DecisionLoop ~= nil and ProjectALife.DecisionLoop.lanes or nil
    local nearest = type(lanes) == "table" and type(lanes.nearest2) == "table"
        and tonumber(lanes.nearest2[data.ProjectALifeUID]) or nil
    return BlackBox.detected(shell, data, entry, now, "wrong-way",
        "beh=" .. tostring(data.ProjectALifeBehaviorState) .. "/" .. tostring(data.ProjectALifeBehaviorIntent)
        .. " phase=" .. tostring(data.ProjectALifeCombatPhase)
        .. " hostile=" .. tostring(last.tkind) .. ":" .. BlackBox.targetId(last.target)
        .. " dist=" .. BlackBox.number(first.td) .. "->" .. BlackBox.number(last.td)
        .. " away=" .. BlackBox.number(after - before)
        .. " leg=" .. (goal ~= nil and (BlackBox.number(goal.x) .. "," .. BlackBox.number(goal.y)) or "-")
        .. " nearestPlayer=" .. (nearest ~= nil and BlackBox.number(math.sqrt(nearest)) or "?"))
end

function BlackBox.detectEdgeStuck(shell, data, entry, now, active)
    if active ~= nil or not BlackBox.busy(data, active) then return false end
    local settings = BlackBox.settings
    local still = now - (entry.lastMoveAtMs or now)
    if still < settings.edgeStuckMs then return false end
    local kind, edge, refusedAt, ageMs = BlackBox.refusalOf(shell, now)
    if kind == nil or refusedAt == nil or ageMs > settings.edgeRefusalMs then return false end
    local tx, ty, tkind, target = BlackBox.hostileOf(data)
    return BlackBox.detected(shell, data, entry, now, "edge-stuck",
        "hold=" .. kind .. " " .. (BlackBox.holdLive(shell, now, ageMs) and "live" or "over")
        .. " age=" .. math.floor(ageMs) .. "ms still=" .. math.floor(still) .. "ms "
        .. BlackBox.edgeText(shell, edge, now)
        .. " pathWhy=" .. tostring(data.ProjectALifePathWhy or "none")
        .. " target=" .. (tx ~= nil and (tostring(tkind) .. ":" .. BlackBox.targetId(target)) or "-")
        .. " targetDist=" .. ((tx ~= nil and entry.x ~= nil)
            and BlackBox.number(math.sqrt((tx - entry.x) ^ 2 + (ty - entry.y) ^ 2)) or "?")
        .. " beh=" .. tostring(data.ProjectALifeBehaviorState))
end

function BlackBox.freezeKind(shell, data, now, active, phase)
    if active ~= nil then
        local deadline = tonumber(active.deadlineAtMs)
        if deadline ~= nil and BlackBox.deadlineModes[tostring(active.mode)] == true then
            if now < deadline + BlackBox.settings.traversalGraceMs then return nil end
            return "trav-hung"
        end
        return "traversal"
    end
    local refusal, edge, refusedAt, ageMs = BlackBox.refusalOf(shell, now)
    if refusal ~= nil and refusedAt ~= nil and BlackBox.holdLive(shell, now, ageMs) then
        return "edge-stuck"
    end
    if BlackBox.stationaryPhases[phase] == true then return "stationary" end
    if data.ProjectALifePathActive == true then return "path" end
    return "combat"
end

function BlackBox.spendAutoDump(now)
    local budget = BlackBox.budget
    if budget.windowAtMs == nil or now < budget.windowAtMs or now - budget.windowAtMs >= 60000 then
        budget.windowAtMs, budget.used = now, 0
    end
    if budget.used >= BlackBox.settings.autoDumpsPerMinute then
        budget.suppressed = budget.suppressed + 1
        BlackBox.metrics.suppressed = BlackBox.metrics.suppressed + 1
        return false
    end
    budget.used = budget.used + 1
    BlackBox.metrics.autoDumps = BlackBox.metrics.autoDumps + 1
    return true
end

function BlackBox.busy(data, active)
    local phase = tostring(data.ProjectALifeCombatPhase or "idle")
    return (phase ~= "idle" and phase ~= "" and phase ~= "aborted")
        or data.ProjectALifePathActive == true
        or active ~= nil
end

function BlackBox.freezeCheck(shell, data, entry, now, active)
    local settings = BlackBox.settings
    local phase = tostring(data.ProjectALifeCombatPhase or "idle")

    if BlackBox.downed(shell, data, entry, now) ~= nil then
        entry.downedAtMs = now
        return false
    end
    if not BlackBox.busy(data, active) then return false end
    local freezeMs = settings.freezeMs
    if BlackBox.stationaryPhases[phase] == true then
        freezeMs = settings.stationaryActionFreezeMs
    end
    local stillFor = now - (entry.lastMoveAtMs or now)
    local quietFor = now - (entry.lastEventAtMs or now)
    local upFor = now - (entry.downedAtMs or -math.huge)
    if stillFor < freezeMs or quietFor < freezeMs or (upFor >= 0 and upFor < freezeMs)
            or now - (entry.lastDumpAtMs or -math.huge) < settings.dumpCooldownMs then
        return false
    end
    local kind = BlackBox.freezeKind(shell, data, now, active, phase)
    if kind == nil then return false end
    entry.lastDumpAtMs = now
    BlackBox.metrics.freezes = BlackBox.metrics.freezes + 1
    local kinds = BlackBox.metrics.freezeKinds
    kinds[kind] = (kinds[kind] or 0) + 1
    if not BlackBox.spendAutoDump(now) then return true end
    BlackBox.dump(shell, "freeze still=" .. stillFor .. "ms quiet=" .. quietFor .. "ms kind=" .. kind, true)
    return true
end

function BlackBox.digest(now)
    if BlackBox.nextDigestAtMs == nil or now < BlackBox.nextDigestAtMs - BlackBox.settings.digestEveryMs then
        BlackBox.nextDigestAtMs = now + BlackBox.settings.digestEveryMs
        return false
    end
    if now < BlackBox.nextDigestAtMs then return false end
    BlackBox.nextDigestAtMs = now + BlackBox.settings.digestEveryMs
    local metrics, base = BlackBox.metrics, BlackBox.digestBase
    local npcs = BlackBox.pruneTracked(now)
    local function delta(key, value)
        local previous = base[key] or 0
        base[key] = value
        return value - previous
    end
    local plus = ProjectALife.BlackBoxPlus
    local extra = ""
    if plus ~= nil then
        pcall(plus.beforeMinute, now)
        local ok, text = pcall(plus.minuteText, now)
        if ok and type(text) == "string" then extra = text end
    end
    local funnel = ProjectALife.Funnel
    if type(funnel) == "table" and type(funnel.minuteText) == "function" then
        local ok, text = pcall(funnel.minuteText)
        if ok and type(text) == "string" then extra = extra .. text end
    end
    print(BlackBox.marker .. " minute npcs=" .. npcs
        .. " freezes=" .. delta("freezes", metrics.freezes)
        .. " edgeStuck=" .. delta("edge-stuck", metrics.detect["edge-stuck"] or 0)
        .. " homing=" .. delta("homing", metrics.detect.homing or 0)
        .. " wrongWay=" .. delta("wrong-way", metrics.detect["wrong-way"] or 0)
        .. " backWalk=" .. delta("back-walk", metrics.detect["back-walk"] or 0)
        .. " strafeMismatch=" .. delta("strafe-mismatch", metrics.detect["strafe-mismatch"] or 0)
        .. " travHung=" .. delta("trav-hung", metrics.freezeKinds["trav-hung"] or 0)
        .. " dupUid=" .. delta("dup-uid", metrics.detect["dup-uid"] or 0)
        .. " linesHeld=" .. delta("linesHeld", metrics.linesHeld or 0)
        .. " rebased=" .. delta("rebased", metrics.rebased)
        .. " dumps=" .. delta("dumps", metrics.dumps)
        .. " suppressed=" .. delta("suppressed", metrics.suppressed)
        .. " events=" .. delta("events", metrics.events) .. extra)
    if plus ~= nil then pcall(plus.afterMinute, now) end
    BlackBox.pruneUids(now)
    return true
end

function BlackBox.pruneTracked(now)
    local idle, window = BlackBox.settings.uidIdleMs, BlackBox.settings.digestEveryMs
    local stale, live = {}, 0
    for shell, entry in pairs(BlackBox.tracked) do
        local seen = tonumber(entry.lastTickAtMs) or tonumber(entry.lastEventAtMs) or now
        if now - seen > idle then
            stale[#stale + 1] = shell
        elseif now - seen <= window then
            live = live + 1
        end
    end
    for _, shell in ipairs(stale) do BlackBox.tracked[shell] = nil end
    return live, #stale
end

function BlackBox.pruneUids(now)
    local idle = BlackBox.settings.uidIdleMs
    local stale = {}
    for uid, entry in pairs(BlackBox.byUid) do
        local seen = math.max(tonumber(entry.lastEventAtMs) or 0, tonumber(entry.lastTickAtMs) or 0)
        if now - seen > idle then stale[#stale + 1] = uid end
    end
    for _, uid in ipairs(stale) do BlackBox.byUid[uid] = nil end
    return #stale
end

function BlackBox.recoverPath(shell, data, now)
    local traversal = ProjectALife.ObstacleTraversal
    local phase = tostring(data.ProjectALifeCombatPhase or "idle")
    if data.ProjectALifePathActive ~= true
            or (phase ~= "idle" and phase ~= "" and phase ~= "approach" and phase ~= "aborted")
            or data.ProjectALifeHeldBump ~= nil
            or (traversal ~= nil and traversal.active ~= nil and traversal.active[shell] ~= nil) then
        BlackBox.pathWatch[shell] = nil
        return false
    end
    local state = tostring(shell:getActionStateName() or "")
    local lowered = string.lower(state)
    if string.find(lowered, "climb", 1, true)
            or string.find(lowered, "hit", 1, true)
            or shell:isDead() then
        BlackBox.pathWatch[shell] = nil
        return false
    end
    local x, y = shell:getX(), shell:getY()
    local entry = BlackBox.pathWatch[shell]
    if entry == nil or now < entry.at
            or (x - entry.x)^2 + (y - entry.y)^2 > BlackBox.settings.stillEpsilon then
        entry = entry or {}
        entry.x, entry.y, entry.at, entry.state, entry.phase = x, y, now, state, phase
        BlackBox.pathWatch[shell] = entry
        return false
    end
    if now - entry.at < BlackBox.settings.stationaryActionFreezeMs then return false end
    entry.at = now
    local combat = ProjectALife.Combat
    if combat ~= nil and type(combat.unstick) == "function" then
        return combat.unstick(shell, "path_no_progress")
    end
    return false
end

function BlackBox.tick(shell, data, now)
    if not BlackBox.enabled or shell == nil or type(data) ~= "table" then return end
    local settings = BlackBox.settings
    local entry = BlackBox.bindUid(shell, record(shell), data.ProjectALifeUID, now)

    local gap = now - (entry.lastTickAtMs or now)
    entry.lastTickAtMs = now
    if gap > settings.beatGapResetMs or gap < 0 then
        entry.lastMoveAtMs, entry.lastEventAtMs = now, now
        BlackBox.metrics.rebased = BlackBox.metrics.rebased + 1
    end
    local x, y = BlackBox.xyOf(shell)
    if x ~= nil then
        if entry.lastX == nil or entry.lastY == nil then
            entry.lastX, entry.lastY = x, y
            entry.lastMoveAtMs = now
        else

            local dx = x - entry.lastX
            local dy = y - entry.lastY
            if dx * dx + dy * dy > settings.stillEpsilon then
                entry.lastX, entry.lastY = x, y
                entry.lastMoveAtMs = now
            end
        end
        entry.x, entry.y = x, y
    end

    local stateOk, state = false, nil
    if shell.getActionStateName ~= nil then stateOk, state = pcall(shell.getActionStateName, shell) end
    BlackBox.diffInto(entry, "state", stateOk and state or nil, now)
    BlackBox.diffInto(entry, "phase", data.ProjectALifeCombatPhase, now)
    BlackBox.diffInto(entry, "bump", BlackBox.variable(shell, "BumpType"), now)
    BlackBox.diffInto(entry, "beh", data.ProjectALifeBehaviorState, now, true)
    BlackBox.diffInto(entry, "intent", data.ProjectALifeBehaviorIntent, now, true)
    BlackBox.diffInto(entry, "path", data.ProjectALifePathActive == true and "on" or nil, now)
    local traversal = ProjectALife.ObstacleTraversal
    local active = traversal ~= nil and type(traversal.active) == "table" and traversal.active[shell] or nil
    BlackBox.diffInto(entry, "traversal", active ~= nil and active.mode or nil, now)
    BlackBox.watchPath(shell, entry)
    if now >= (entry.nextTraceAtMs or -math.huge) then
        entry.nextTraceAtMs = now + settings.traceEveryMs
        BlackBox.sample(shell, data, entry, now, active)
    end
    BlackBox.freezeCheck(shell, data, entry, now, active)
    local plus = ProjectALife.BlackBoxPlus
    if plus ~= nil then pcall(plus.tick, shell, data, entry, now, active) end
    BlackBox.digest(now)
end

function BlackBox.context()
    local lines = {}
    local function add(label, value)
        lines[#lines + 1] = "  " .. label .. ": " .. tostring(value)
    end

    add("alife_build", BlackBox.readBuild())
    local runtime = ProjectALife.Runtime
    if runtime ~= nil and runtime.BUILD ~= nil and runtime.BUILD ~= BlackBox.BUILD then
        add("runtime_build", runtime.BUILD)
    end

    local side = "singleplayer"
    pcall(function()
        local client = type(isClient) == "function" and isClient()
        local server = type(isServer) == "function" and isServer()
        if client and server then side = "host (listen server)"
        elseif server then side = "dedicated server"
        elseif client then side = "multiplayer client" end
    end)
    add("side", side)
    pcall(function()
        local players = getOnlinePlayers and getOnlinePlayers() or nil
        local online = players ~= nil and players:size() or 0

        if online <= 0 and type(getSpecificPlayer) == "function" then
            online = getSpecificPlayer(0) ~= nil and 1 or 0
        end
        add("players_online", online)
    end)
    pcall(function()
        add("world_day", math.floor((getGameTime():getWorldAgeHours() or 0) / 24))
    end)

    pcall(function()
        local mods = getActivatedMods()
        if mods == nil then return end
        local names = {}
        for index = 0, mods:size() - 1 do names[#names + 1] = tostring(mods:get(index)) end
        add("mods_active", #names)
        lines[#lines + 1] = "  mods: " .. table.concat(names, ", ")
    end)

    pcall(function()
        local compat = ProjectALife.ModCompat
        if compat == nil then return end
        local registry = ProjectALife.CompatRegistry
        if registry ~= nil and type(registry.qaLine) == "function" then lines[#lines + 1] = registry.qaLine() end
        for _, line in ipairs(compat.report()) do
            lines[#lines + 1] = "  compat: " .. line
        end
        local shield = ProjectALife.EquipEventShield
        if shield ~= nil then
            add("equip_shield_filtered", shield.metrics.filtered)
        end
    end)

    pcall(function()
        local s = ProjectALife.Settings and ProjectALife.Settings.current
        if type(s) ~= "table" then return end
        add("preset", s.presetWorld)
        add("max_hostiles", s.maximumHostileActors)
        add("spawn_multiplier", s.spawnMultiplier)
        add("simulation_radius", s.simulationRadius)
        add("outposts_max", s.outpostsMaxSites)
    end)
    pcall(BlackBox.capLines, add)

    pcall(function()
        local m = ProjectALife.Runtime and ProjectALife.Runtime.metrics
        if type(m) ~= "table" then return end
        add("ticks", m.ticks)
        add("last_tick_ms", m.lastTickMs)
        add("worst_tick_ms", m.maximumTickMs)
        add("tick_overruns", m.overruns or 0)
    end)
    pcall(function()
        local registry = ProjectALife.ActorRegistry
        if registry ~= nil and type(registry.list) == "function" then
            add("actors_in_registry", #registry.list())
        end

        if registry == nil or type(registry.records) ~= "table" then return end
        local counts, parts = {}, {}
        for _, actor in pairs(registry.records) do
            local state = tostring(actor.lifecycle or "unknown")
            counts[state] = (counts[state] or 0) + 1
        end
        for state, count in pairs(counts) do
            parts[#parts + 1] = state .. "=" .. tostring(count)
        end
        table.sort(parts)
        add("actor_lifecycles", #parts > 0 and table.concat(parts, " ") or "none")
    end)

    pcall(function()
        local guard = ProjectALife.OrphanGuard
        if type(guard) ~= "table" then return end
        add("orphan_guard", "scans=" .. tostring(guard.scans or 0) .. " removed=" .. tostring(guard.removed or 0)
            .. " disarmed=" .. tostring(guard.disarmed or 0) .. " ghosts=" .. tostring(guard.ghosts or 0))
    end)

    for _, row in ipairs({
        { "SceneKit", "scenes" }, { "EncounterDirector", "encounters" },
        { "OutpostDirector", "outposts" }, { "Executor", "executor" },
        { "ObstacleTraversal", "traversal" }, { "AIFence", "guard" },
        { "Entrances", "entrances" }, { "ModuleBreach", "breach" },

        { "Runtime", "runtime" }, { "Population", "population" },
        { "OfflineDirector", "offline" }, { "Watchdog", "watchdog" },

        { "HordeRelations", "horde" }, { "VehicleRules", "vehicles" },

        { "MirrorTransport", "mirror" },
        { "Interop", "interop" },
        { "BlackBox", "recorder" },
    }) do
        pcall(function()
            local module = ProjectALife[row[1]]
            local m = module ~= nil and module.metrics or nil
            if type(m) ~= "table" then return end
            local parts = {}
            for key, value in pairs(m) do
                if type(value) == "number" then
                    parts[#parts + 1] = key .. "=" .. tostring(value)
                elseif type(value) == "table" then

                    local inner = {}
                    for reason, count in pairs(value) do
                        if type(count) == "number" then
                            inner[#inner + 1] = tostring(reason) .. ":" .. tostring(count)
                        end
                    end
                    table.sort(inner)
                    if #inner > 0 then
                        parts[#parts + 1] = key .. "=" .. table.concat(inner, ",")
                    end
                end
            end
            table.sort(parts)
            if #parts > 0 then add(row[2], table.concat(parts, " ")) end
        end)
    end

    return table.concat(lines, "\n")
end

function BlackBox.sandboxValue(name)
    if type(getSandboxOptions) == "function" then
        local options = getSandboxOptions()
        local option = options ~= nil and options.getOptionByName ~= nil
            and options:getOptionByName("ALife." .. name) or nil
        if option ~= nil and option.getValue ~= nil then return option:getValue() end
    end
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(vars) == "table" then return vars[name] end
    return nil
end

function BlackBox.pressuredCap(cap, pressure)
    cap = tonumber(cap) or 0
    if cap <= 0 then return cap end
    return math.max(math.min(3, cap), math.floor(cap * pressure + 0.5))
end

function BlackBox.capLines(add)
    local remote = type(isClient) == "function" and isClient() == true
        and not (type(isServer) == "function" and isServer() == true)
    local settings = ProjectALife.Settings
    local s = type(settings) == "table" and type(settings.current) == "table" and settings.current or {}
    local offline, ledger = ProjectALife.OfflineDirector, ProjectALife.SquadLedger
    local persistence = ProjectALife.Persistence
    local running, maximum, alive, now, pressure, saved = "n/a", "n/a", "n/a", "n/a", "n/a", "n/a"
    if not remote then
        running = offline ~= nil and type(offline.settings) == "table" and offline.settings.squadCap or nil
        maximum = ledger ~= nil and type(ledger.settings) == "table" and ledger.settings.maximum or nil
        if ledger ~= nil and type(ledger.count) == "function" then
            local ok, count = pcall(ledger.count)
            if ok then alive = count end
        end
        local world = ProjectALife.WorldPressure
        local hours = type(getGameTime) == "function" and getGameTime():getWorldAgeHours() or 0
        pressure = world ~= nil and type(world.at) == "function" and world.at(hours) or 1
        now = running ~= nil and BlackBox.pressuredCap(running, pressure) or nil
        pressure = string.format("%.2f", pressure)
        saved = persistence ~= nil and persistence.squadCap or nil
    end
    add("offline_squads", "set=" .. tostring(BlackBox.sandboxValue("Offline_SquadCap"))
        .. " read=" .. tostring(s.offlineSquadCap) .. " running=" .. tostring(running)
        .. " ledger_max=" .. tostring(maximum) .. " pressure=" .. tostring(pressure)
        .. " now=" .. tostring(now) .. " alive=" .. tostring(alive))
    add("saved_squads", "set=" .. tostring(BlackBox.sandboxValue("Population_PersistentSquadCap"))
        .. " read=" .. tostring(s.persistentSquadCap) .. " running=" .. tostring(saved))

    local rate = BlackBox.sandboxValue("Rate_Groups")
    local rateScale = type(settings) == "table" and type(settings.rateScale) == "function"
        and rate ~= nil and settings.rateScale(rate) or nil
    add("rate_groups", "set=" .. tostring(rate) .. " set_scale=" .. tostring(rateScale)
        .. " read_scale=" .. tostring(s.rateGroups))
    add("world_mode", "set=" .. tostring(BlackBox.sandboxValue("World_Mode"))
        .. " read=" .. tostring(s.worldMode))
    add("census", BlackBox.censusText(remote))
end

function BlackBox.censusText(remote)
    local census = ProjectALife.WorldPressure
    if remote or type(census) ~= "table" or type(census.censusBrief) ~= "function" then return "n/a" end
    local ok, brief = pcall(census.censusBrief)
    if not ok or type(brief) ~= "table" then return "none" end
    return "set=" .. tostring(BlackBox.sandboxValue("Census_Size")) .. " total=" .. tostring(brief.total)
        .. " living=" .. tostring(brief.living) .. " alive=" .. tostring(brief.alive)
        .. " killed=" .. tostring(brief.dead) .. " arrivals=" .. tostring(brief.arrived)
        .. " room=" .. tostring(brief.room) .. " spent=" .. tostring(brief.spent)
end

function BlackBox.dumpAll(reason)
    local count, retired, reports = 0, 0, {}
    for shell in pairs(BlackBox.tracked) do

        local ok, live = pcall(function()
            local data = shell:getModData()
            return type(data) == "table" and type(data.ProjectALifeUID) == "string"
                and type(data.ProjectALifeGeneration) == "number" and not shell:isDead()
        end)
        if ok and live then
            reports[#reports + 1] = BlackBox.dump(shell, reason or "manual")
            count = count + 1
        else
            BlackBox.tracked[shell] = nil
            retired = retired + 1
        end
    end
    BlackBox.pruneUids(nowMs())
    print(BlackBox.marker .. " summary reason=" .. tostring(reason or "manual") .. " live_shells=" .. tostring(count)
        .. " retired_records=" .. tostring(retired))
    reports[#reports + 1] = BlackBox.marker .. " live_shells=" .. tostring(count) .. " retired_records=" .. tostring(retired)

    local head = "=== PROJECT A-LIFE BLACKBOX ==="
    pcall(function() head = head .. "\n" .. BlackBox.context() end)
    local plus = ProjectALife.BlackBoxPlus
    local extras = ""
    if plus ~= nil then
        local ok, text = pcall(plus.dumpText, nowMs())
        if ok and type(text) == "string" and text ~= "" then extras = "\n\n=== RECORDER EXTRAS ===\n" .. text end
    end
    local safehouse = ""
    local director = ProjectALife.SafehouseDirector
    if director ~= nil and type(director.diagnosticText) == "function" then
        local ok, text = pcall(director.diagnosticText)
        if ok and type(text) == "string" then safehouse = "\n\n" .. text
        else safehouse = "\n\n=== SAFEHOUSE DIAGNOSTICS ===\nreport_read_failed" end
    end
    BlackBox.saveReport("blackbox", head .. extras .. safehouse .. "\n\n=== SHELLS ===\n" .. table.concat(reports, "\n"))
    return count
end

return BlackBox
