require "ProjectALife/Core/ALifePersistence"
require "ProjectALife/Core/ALifeActorRegistry"
require "ProjectALife/Talk/ALifeSpeech"
require "ProjectALife/Talk/ALifeTalk"
require "ProjectALife/Talk/ALifeTalkOrders"
require "ProjectALife/Talk/ALifePartyRows"

ProjectALife = ProjectALife or {}

local Party = {
    settings = {
        tickMs = 3000, nearTiles = 45, lagTiles = 30, lagMs = 15000, lagLineGapMs = 45000,
        waitMs = 40000, waitGapMs = 240000, warnTiles = 16, warnGapMs = 60000, hearTiles = 25,
        stillMs = 30000, storyScanMs = 9000, storyGapMs = 600000, storyRetryMs = 20000,
        storyNearTiles = 22, pushMs = 30000, taskCalmMs = 8000, taskMinGapHours = 0.25,
        firstTaskHours = 0.15, scoutRadii = { 30, 42, 54 }, watchTiles = 14, watchHours = 0.4,
        clearKills = 6, fetchCount = { water = 2, food = 3, meds = 2 },
    },
    classShift = { civilian = -5, family = -8, worker = -3, rescue = -5, law = 3, swat = 6, military = 6,
        elite = 10, outlaw = 8, raider = 14, gang = 10, club = 8, crime = 10, prison = 12 },
    tempShift = { fresh = -4, seasoned = 0, veteran = 3, predator = 8 },
    endText = {
        left = "You left the group.",
        desert = "The group moved on without you.",
        kicked = "The group doesn't want you around any more.",
        hostile = "The group turned on you.",
        gone = "Your group is gone.",
    },
    state = { players = {}, storyAt = {}, pos = {}, tickAt = 0, storyScanAt = 0 },
    metrics = { joined = 0, refused = 0, left = 0, ended = 0, tasks = 0, done = 0, failed = 0, stories = 0, warned = 0 },
}
ProjectALife.Party = Party

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function roll(maximum)
    if type(ZombRand) == "function" then return ZombRand(maximum) end
    return 0
end

local function registry() return ProjectALife.ActorRegistry end

function Party.hours()
    if type(getGameTime) ~= "function" then return 0 end
    local clock = getGameTime()
    if clock == nil or type(clock.getWorldAgeHours) ~= "function" then return 0 end
    return clock:getWorldAgeHours()
end

function Party.option(name, default)
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    local value = nil
    if type(vars) == "table" then value = vars[name] end
    if value == nil then return default end
    return value
end

function Party.enabled()
    if type(isClient) == "function" and isClient() == true and not (type(isServer) == "function" and isServer() == true) then
        return false
    end
    return Party.option("Party_Enabled", true) ~= false
end

function Party.reset()
    Party.state = { players = {}, storyAt = {}, pos = {}, tickAt = 0, storyScanAt = 0 }
    Party.fallback = nil
    for name in pairs(Party.metrics) do Party.metrics[name] = 0 end
end

function Party.store()
    local persistence = ProjectALife.Persistence
    local value = persistence ~= nil and type(persistence.bucket) == "function"
        and persistence.bucket("party", { byGroup = {}, byPlayer = {} }) or nil
    if type(value) ~= "table" then
        Party.fallback = Party.fallback or { byGroup = {}, byPlayer = {} }
        value = Party.fallback
    end
    value.byGroup = type(value.byGroup) == "table" and value.byGroup or {}
    value.byPlayer = type(value.byPlayer) == "table" and value.byPlayer or {}
    return value
end

function Party.dirty()
    local persistence = ProjectALife.Persistence
    if persistence ~= nil and type(persistence.touch) == "function" then persistence.touch() end
end

function Party.keyOf(player)
    if player == nil then return nil end
    return ProjectALife.Speech.playerKey(player)
end

function Party.posOf(object)
    if object == nil or type(object.getX) ~= "function" then return nil end
    local ok, x, y, z = pcall(function() return object:getX(), object:getY(), object:getZ() end)
    if ok and x ~= nil then return x, y, z or 0 end
    return nil
end

function Party.entryPos(entry)
    if entry.shell ~= nil then return Party.posOf(entry.shell) end
    local at = entry.record.worldPosition
    if type(at) == "table" and tonumber(at.x) ~= nil and tonumber(at.y) ~= nil then
        return tonumber(at.x), tonumber(at.y), tonumber(at.z) or 0
    end
    return nil
end

function Party.roster(gid)
    local list = {}
    local reg, talk = registry(), ProjectALife.Talk
    if reg == nil or gid == nil or talk == nil then return list end
    reg.each(function(record)
        local memory = type(record.memory) == "table" and record.memory or nil
        if memory ~= nil and memory.groupId == gid and record.lifecycle ~= "dead" then
            local shell = nil
            if record.lifecycle == "active" then shell = talk.shellFor(record.uid) end
            list[#list + 1] = { record = record, shell = shell }
        end
        return false
    end)
    return list
end

function Party.leaderOf(roster)
    local best = nil
    for _, entry in ipairs(roster) do
        local memory = entry.record.memory
        if memory.groupRole == "leader" then return entry end
        if best == nil or (tonumber(memory.groupIndex) or 99) < (tonumber(best.record.memory.groupIndex) or 99) then
            best = entry
        end
    end
    return best
end

function Party.friendly(record, player)
    if type(record) ~= "table" or type(record.memory) ~= "table" or record.memory.groupId == nil then return false end
    local store = Party.store()
    local entry = store.byGroup[record.memory.groupId]
    if entry == nil then return false end
    local key = Party.keyOf(player)
    return key ~= nil and entry.members[key] ~= nil
end

function Party.sharesGroup(record, x, y)
    if type(record) ~= "table" or type(record.memory) ~= "table" or record.memory.groupId == nil then return false end
    local entry = Party.store().byGroup[record.memory.groupId]
    if entry == nil then return false end
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil then return true end
    for key in pairs(entry.members) do
        local px, py = Party.posOf(ProjectALife.TalkOrders.playerByKey(key))
        if px ~= nil and (px - x) ^ 2 + (py - y) ^ 2 <= 1600 then return true end
    end
    return false
end

function Party.vars(player)
    local name = nil
    pcall(function() name = player:getDescriptor():getForename() end)
    if type(name) ~= "string" or name == "" then name = "friend" end
    return { name = name }
end

function Party.contextFor(record, player)
    local context = ProjectALife.Speech.contextFor(record, player)
    context.stance = "friendly"
    return context
end

function Party.say(record, shell, player, event, context)
    local talk = ProjectALife.Talk
    if talk == nil or shell == nil or record == nil then return nil end
    local ok, text = pcall(talk.bark, record, shell, player, event, context or Party.contextFor(record, player), Party.vars(player))
    if ok and type(text) == "string" then return text end
    return nil
end

function Party.speaker(roster, player, preferred)
    local px, py = Party.posOf(player)
    if px == nil then return nil end
    local limit = Party.settings.hearTiles
    local best, bestD = nil, limit * limit
    if preferred ~= nil and preferred.shell ~= nil then
        local x, y = Party.posOf(preferred.shell)
        if x ~= nil and (x - px) ^ 2 + (y - py) ^ 2 <= bestD then return preferred end
    end
    for _, entry in ipairs(roster) do
        if entry.shell ~= nil then
            local x, y = Party.posOf(entry.shell)
            if x ~= nil then
                local d = (x - px) ^ 2 + (y - py) ^ 2
                if d <= bestD and entry.record.activity ~= "combat" then best, bestD = entry, d end
            end
        end
    end
    return best
end

function Party.send(player, command, payload)
    if player == nil then return false end
    if type(isServer) == "function" and isServer() == true then
        if type(sendServerCommand) == "function" then
            return pcall(sendServerCommand, player, "ProjectALife", command, payload)
        end
        return false
    end
    if command == "partyState" then
        local data = ProjectALife.FieldRadioData
        if data ~= nil and type(data.onParty) == "function" then return pcall(data.onParty, payload) end
    elseif command == "safehouseNotice" then
        local client = ProjectALife.SafehouseClient
        if client ~= nil and type(client.notice) == "function" then return pcall(client.notice, payload, player) end
    end
    return false
end

function Party.notice(player, text)
    return Party.send(player, "safehouseNotice", { text = text })
end

function Party.mark(player, task)
    local havens = ProjectALife.Havens
    if task.mark ~= true or havens == nil or type(havens.sendMarker) ~= "function" then return false end
    return havens.sendMarker(player, { x = math.floor(task.x), y = math.floor(task.y), name = "Job: " .. tostring(task.label) })
end

function Party.payload(key, gid)
    local store = Party.store()
    local entry = store.byGroup[gid]
    local mine = entry ~= nil and entry.members[key] or nil
    if mine == nil then return { active = false } end
    local roster = Party.roster(gid)
    local lead = Party.leaderOf(roster)
    local who, group = nil, nil
    if lead ~= nil then
        local names = ProjectALife.Names
        if names ~= nil and type(names.shown) == "function" then who = names.shown(lead.record, key) end
        local catalog = ProjectALife.Catalog
        local faction = catalog ~= nil and type(catalog.faction) == "function" and catalog.faction(lead.record.factionId) or nil
        if type(faction) == "table" and type(faction.general) == "table" then group = faction.general.name end
    end
    local payload = { active = true, leader = who or "The group leader", group = group or "Survivors",
        members = #roster, sinceHours = mine.sinceHours }
    local task = mine.task
    if type(task) == "table" then
        payload.task = { text = task.text, progress = task.progressText, x = task.mark == true and task.x or nil,
            y = task.mark == true and task.y or nil }
    end
    return payload
end

function Party.push(key, gid, player)
    player = player or ProjectALife.TalkOrders.playerByKey(key)
    if player == nil then return false end
    return Party.send(player, "partyState", Party.payload(key, gid))
end

function Party.danger(lead, roster, now)
    local leader = ProjectALife.ModuleLeader
    local gid = lead.record.memory.groupId
    local group = leader ~= nil and type(leader.groups) == "table" and leader.groups[gid] or nil
    if type(group) == "table" and group.inContact == true then return true end
    for _, entry in ipairs(roster) do
        if entry.record.activity == "combat" then return true end
    end
    local caution = ProjectALife.Caution
    if caution ~= nil and lead.shell ~= nil and type(caution.zombiesNear) == "function" then
        local ok, near = pcall(caution.zombiesNear, lead.shell, now, 12)
        if ok and near == true then return true end
    end
    return false
end

function Party.threshold(record, player)
    local need = tonumber(Party.option("Party_MinOpinion", 20)) or 20
    local context = ProjectALife.Speech.contextFor(record, nil)
    need = need + (Party.classShift[context.register] or 0) + (Party.tempShift[context.temperament] or 0)
    local reputation = ProjectALife.Reputation
    if reputation ~= nil and type(reputation.recordedStatus) == "function" then
        local ok, status = pcall(reputation.recordedStatus, player, record)
        if ok and status == "careful" then need = need + 10 elseif ok and status == "friendly" then need = need - 5 end
    end
    return need
end

function Party.verdict(lead, roster, gid, player, now)
    if lead == nil then return "PARTY_JOIN_NO_LEADER" end
    local entry = Party.store().byGroup[gid]
    local players = 0
    if entry ~= nil then
        for _ in pairs(entry.members) do players = players + 1 end
    end
    if #roster + players + 1 > (tonumber(Party.option("Party_MaxSize", 6)) or 6) then return "PARTY_JOIN_NO_ROOM" end
    if Party.danger(lead, roster, now) then return "PARTY_JOIN_NO_DANGER" end
    local opinion = ProjectALife.NpcOpinion
    local value = opinion ~= nil and type(opinion.valueOf) == "function" and opinion.valueOf(lead.record, player) or 0
    local need = Party.threshold(lead.record, player)
    if value < need then
        if value >= need - 15 then return "PARTY_JOIN_NO_OPINION" end
        return "PARTY_JOIN_NO_TRUST"
    end
    return nil
end

function Party.enter(gid, key, roster, lead, player)
    local store = Party.store()
    local hours = Party.hours()
    local entry = store.byGroup[gid]
    if entry == nil then
        entry = { members = {}, sinceHours = hours, leaderUid = lead.record.uid }
        store.byGroup[gid] = entry
    end
    entry.leaderUid = lead.record.uid
    entry.members[key] = { sinceHours = hours, nextTaskHours = hours + Party.settings.firstTaskHours }
    store.byPlayer[key] = gid
    Party.state.players[key] = { lastNearMs = nowMs() }
    local names, talk = ProjectALife.Names, ProjectALife.Talk
    if names ~= nil and type(names.markIntroduced) == "function" then
        for _, member in ipairs(roster) do
            talk.writeMemory(member.record.uid, function(memory) names.markIntroduced(memory, key) end)
        end
    end
    Party.metrics.joined = Party.metrics.joined + 1
    Party.dirty()
    Party.push(key, gid, player)
    Party.notice(player, "You joined the group.")
end

function Party.hold(roster, untilMs)
    local decisions = ProjectALife.DecisionLoop
    if decisions == nil or type(decisions.setOrder) ~= "function" then return 0 end
    local count = 0
    for _, entry in ipairs(roster) do
        local x, y, z = Party.entryPos(entry)
        if entry.shell ~= nil and x ~= nil then
            local ok, accepted = pcall(decisions.setOrder, entry.record.uid, entry.record.generation, {
                kind = "hold", anchor = { x = x, y = y, z = z }, untilMs = untilMs, quiet = true, source = "leader" })
            if ok and accepted == true then count = count + 1 end
        end
    end
    return count
end

function Party.release(roster)
    local decisions = ProjectALife.DecisionLoop
    if decisions == nil or type(decisions.clearLeaderOrder) ~= "function" then return end
    for _, entry in ipairs(roster) do
        pcall(decisions.clearLeaderOrder, entry.record.uid, entry.record.generation)
    end
end

function Party.finish(key, reason)
    local store = Party.store()
    local gid = store.byPlayer[key]
    if gid == nil then return false end
    local entry = store.byGroup[gid]
    local roster = Party.roster(gid)
    local danger = false
    if reason == "desert" and #roster > 0 then
        local lead = Party.leaderOf(roster)
        danger = lead ~= nil and Party.danger(lead, roster, nowMs())
    end
    if entry ~= nil then
        entry.members[key] = nil
        local any = false
        for _ in pairs(entry.members) do any = true end
        if not any then
            store.byGroup[gid] = nil
            Party.release(roster)
        end
    end
    store.byPlayer[key] = nil
    Party.state.players[key] = nil
    local player = ProjectALife.TalkOrders.playerByKey(key)
    if reason == "desert" and danger then
        local opinion, lead = ProjectALife.NpcOpinion, Party.leaderOf(roster)
        if opinion ~= nil and lead ~= nil and player ~= nil then pcall(opinion.note, "party_desert", lead.record, player) end
    end
    if reason == "left" then Party.metrics.left = Party.metrics.left + 1 end
    Party.metrics.ended = Party.metrics.ended + 1
    Party.dirty()
    if player ~= nil then
        Party.send(player, "partyState", { active = false })
        Party.notice(player, Party.endText[reason] or Party.endText.left)
        if reason == "desert" or reason == "kicked" then
            local speaker = Party.speaker(roster, player, nil)
            if speaker ~= nil then
                Party.say(speaker.record, speaker.shell, player, reason == "kicked" and "PARTY_KICK" or "PARTY_LEFT_BEHIND")
            end
        end
    end
    return true
end

function Party.join(record, shell, player, context, now)
    local key = Party.keyOf(player)
    if not Party.enabled() or key == nil then return nil end
    local gid = type(record.memory) == "table" and record.memory.groupId or nil
    if gid == nil then
        return Party.say(record, shell, player, "PARTY_JOIN_NO_LEADER", context) or "[Shakes head]", "refused"
    end
    local store = Party.store()
    local current = store.byPlayer[key]
    if current == gid then
        return Party.say(record, shell, player, "PARTY_JOIN_OK", context) or "[Nods]", "answered"
    elseif current ~= nil then
        return Party.say(record, shell, player, "PARTY_JOIN_ELSEWHERE", context) or "[Shakes head]", "refused"
    end
    local roster = Party.roster(gid)
    local lead = Party.leaderOf(roster)
    local verdict = Party.verdict(lead, roster, gid, player, now)
    if verdict ~= nil then
        Party.metrics.refused = Party.metrics.refused + 1
        return Party.say(record, shell, player, verdict, context) or "[Shakes head]", "refused"
    end
    Party.enter(gid, key, roster, lead, player)
    return Party.say(record, shell, player, "PARTY_JOIN_OK", context) or "[Nods]", "answered"
end

function Party.mineFor(record, player)
    local key = Party.keyOf(player)
    local gid = type(record.memory) == "table" and record.memory.groupId or nil
    if key == nil or gid == nil then return nil end
    local entry = Party.store().byGroup[gid]
    local mine = entry ~= nil and entry.members[key] or nil
    if mine == nil then return nil end
    return mine, key, gid, entry
end

function Party.onLeave(record, shell, player, context, now)
    local mine, key = Party.mineFor(record, player)
    if mine == nil then return Party.say(record, shell, player, "PARTY_JOIN_ELSEWHERE", context) or "[Blinks]", "answered" end
    local text = Party.say(record, shell, player, "PARTY_LEAVE_OK", context)
    Party.finish(key, "left")
    return text or "[Nods]", "answered"
end

function Party.snapshot(key, gid, now)
    local store = Party.store()
    local entry = store.byGroup[gid]
    local mine = entry ~= nil and entry.members[key] or nil
    if mine == nil then return nil end
    local roster = Party.roster(gid)
    local lead = Party.leaderOf(roster)
    local player = ProjectALife.TalkOrders.playerByKey(key)
    if lead == nil or player == nil then return nil end
    local px, py, pz = Party.posOf(player)
    if px == nil then return nil end
    local nearD, leadD = math.huge, math.huge
    for _, member in ipairs(roster) do
        local x, y = Party.entryPos(member)
        if x ~= nil then
            local d = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
            if d < nearD then nearD = d end
            if member == lead then leadD = d end
        end
    end
    return { key = key, gid = gid, entry = entry, mine = mine, roster = roster, lead = lead, player = player,
        px = px, py = py, pz = pz, nearD = nearD, leadD = leadD, now = now, hours = Party.hours() }
end

function Party.buildingKey(building)
    local havens = ProjectALife.Havens
    if building == nil or havens == nil or type(havens.boundsOf) ~= "function" then return nil end
    local bounds = havens.boundsOf(building)
    if bounds == nil then return nil end
    return havens.keyOf(bounds), bounds
end

function Party.playerBuildingKey(player)
    local key = nil
    pcall(function()
        local square = player:getCurrentSquare()
        local building = square ~= nil and square:getBuilding() or nil
        key = Party.buildingKey(building)
    end)
    return key
end

function Party.kills(player)
    local count = nil
    pcall(function() count = player:getZombieKills() end)
    return tonumber(count)
end

function Party.matching(player, kind, limit)
    local robbery, supplies = ProjectALife.ModuleRobbery, ProjectALife.TalkSupplies
    local found = {}
    if robbery == nil or supplies == nil or type(robbery.gatherItems) ~= "function" then return found end
    local ok, list = pcall(robbery.gatherItems, player, { playerOnly = true, limit = 256 })
    if not ok or type(list) ~= "table" then return found end
    for _, entry in ipairs(list) do
        if entry.source == "player" and entry.item ~= nil then
            local matched, safe = pcall(supplies.matches, entry.item, kind)
            if matched and safe == true then
                found[#found + 1] = entry
                if #found >= limit then break end
            end
        end
    end
    return found
end

function Party.takeItems(player, shell, kind, count)
    local robbery = ProjectALife.ModuleRobbery
    local entries = Party.matching(player, kind, count)
    if #entries < count or robbery == nil or shell == nil then return false end
    local destination = nil
    pcall(function() destination = shell:getInventory() end)
    if destination == nil then return false end
    local moved = 0
    for _, entry in ipairs(entries) do
        local ok = robbery.removeItem(entry, destination, shell)
        if ok then moved = moved + 1 end
    end
    return moved >= count
end

function Party.hasSpare(shell, kind)
    local supplies = ProjectALife.TalkSupplies
    local found = false
    pcall(function()
        local items = shell:getInventory():getItems()
        for index = 0, items:size() - 1 do
            if supplies.matches(items:get(index), kind) then found = true return end
        end
    end)
    return found
end

Party.types = {}

Party.types.scout = {
    offer = "PARTY_TASK_SCOUT", hours = 1.5,
    begin = function(ctx)
        local havens = ProjectALife.Havens
        local shell = ctx.lead.shell
        if havens == nil or shell == nil or type(havens.squareAt) ~= "function" then return nil end
        local lx, ly = Party.posOf(shell)
        if lx == nil then return nil end
        for _, radius in ipairs(Party.settings.scoutRadii) do
            local first = roll(8)
            for step = 0, 7 do
                local angle = ((step + first) % 8) * math.pi / 4
                local square = havens.squareAt(lx + math.cos(angle) * radius, ly + math.sin(angle) * radius, 0)
                local building = square ~= nil and type(square.getBuilding) == "function" and square:getBuilding() or nil
                local id, bounds = Party.buildingKey(building)
                if id ~= nil then
                    return { type = "scout", label = "scout", buildingId = id, entered = false, mark = true,
                        x = (bounds.x1 + bounds.x2) / 2, y = (bounds.y1 + bounds.y2) / 2,
                        text = "Scout the building marked on your map, then come back to the group." }
                end
            end
        end
        return nil
    end,
    check = function(task, ctx)
        if not task.entered and Party.playerBuildingKey(ctx.player) == task.buildingId then task.entered = true end
        if task.entered then
            task.progressText = "Report back to the group."
            if ctx.nearD <= 14 then return "done" end
        end
        return nil
    end,
}

for kind, label in pairs({ water = "ASK_WATER", food = "ASK_FOOD", meds = "ASK_MEDS" }) do
    local noun = { water = "bottles of water or seltzer", food = "portions of food", meds = "medical items" }
    Party.types["fetch_" .. kind] = {
        offer = "PARTY_TASK_" .. string.upper(kind), hours = 4, turnIn = true,
        begin = function(ctx)
            local count = Party.settings.fetchCount[kind]
            return { type = "fetch_" .. kind, label = "supplies", kind = label, count = count,
                text = "Bring the group " .. count .. " " .. noun[kind] .. ", then tell them it's done." }
        end,
        check = function(task, ctx)
            local have = #Party.matching(ctx.player, task.kind, task.count)
            task.progressText = "You carry " .. have .. " of " .. task.count .. "."
            if have >= task.count then return "ready" end
            return nil
        end,
    }
end

Party.types.watch = {
    offer = "PARTY_TASK_WATCH", hours = 2,
    begin = function(ctx)
        local x, y = Party.posOf(ctx.lead.shell)
        if x == nil then return nil end
        return { type = "watch", label = "keep watch", x = x, y = y, progress = 0, mark = true, lastHours = ctx.hours,
            text = "Keep watch around the group for a while. Stay close and stay awake." }
    end,
    check = function(task, ctx)
        local dt = math.max(0, math.min(0.2, ctx.hours - (tonumber(task.lastHours) or ctx.hours)))
        task.lastHours = ctx.hours
        if (ctx.px - task.x) ^ 2 + (ctx.py - task.y) ^ 2 <= Party.settings.watchTiles ^ 2 then
            task.progress = (tonumber(task.progress) or 0) + dt
        end
        local need = Party.settings.watchHours
        task.progressText = "On watch: " .. math.min(100, math.floor((task.progress / need) * 100)) .. "%."
        if task.progress >= need then return "done" end
        return nil
    end,
}

Party.types.clear = {
    offer = "PARTY_TASK_CLEAR", hours = 2,
    begin = function(ctx)
        local kills = Party.kills(ctx.player)
        if kills == nil then return nil end
        return { type = "clear", label = "clear the street", kills0 = kills, need = Party.settings.clearKills,
            text = "Thin out the dead around the group. Put down " .. Party.settings.clearKills .. " of them." }
    end,
    check = function(task, ctx)
        local kills = Party.kills(ctx.player)
        if kills == nil then return nil end
        local got = math.max(0, kills - task.kills0)
        task.progressText = "Put down " .. math.min(got, task.need) .. " of " .. task.need .. "."
        if got >= task.need and ctx.nearD <= 60 then return "done" end
        return nil
    end,
}

Party.order = { "scout", "fetch_water", "fetch_food", "fetch_meds", "watch", "clear" }

function Party.assign(ctx, force)
    local mine = ctx.mine
    if mine.task ~= nil then return false end
    local freq = tonumber(Party.option("Party_TaskFrequency", 45)) or 45
    if freq <= 0 and not force then return false end
    local first = roll(#Party.order)
    for step = 0, #Party.order - 1 do
        local name = Party.order[(first + step) % #Party.order + 1]
        if name ~= mine.lastType or #Party.order == 1 then
            local def = Party.types[name]
            local task = def.begin(ctx)
            if task ~= nil then
                task.deadlineHours = ctx.hours + def.hours
                mine.task, mine.lastType = task, name
                Party.metrics.tasks = Party.metrics.tasks + 1
                local speaker = Party.speaker(ctx.roster, ctx.player, ctx.lead)
                if speaker ~= nil then Party.say(speaker.record, speaker.shell, ctx.player, def.offer) end
                Party.notice(ctx.player, "New job: " .. task.text)
                Party.mark(ctx.player, task)
                Party.dirty()
                Party.push(ctx.key, ctx.gid, ctx.player)
                return true
            end
        end
    end
    return false
end

function Party.settle(ctx, success)
    local mine, task = ctx.mine, ctx.mine.task
    if task == nil then return end
    local opinion = ProjectALife.NpcOpinion
    local speaker = Party.speaker(ctx.roster, ctx.player, ctx.lead)
    local freq = tonumber(Party.option("Party_TaskFrequency", 45)) or 45
    mine.task = nil
    mine.nextTaskHours = ctx.hours + math.max(Party.settings.taskMinGapHours, freq / 60 * (0.8 + roll(5) / 10))
    if success then
        Party.metrics.done = Party.metrics.done + 1
        mine.done = (tonumber(mine.done) or 0) + 1
        if opinion ~= nil then pcall(opinion.note, "party_task", ctx.lead.record, ctx.player) end
        if speaker ~= nil then
            Party.say(speaker.record, speaker.shell, ctx.player, "PARTY_TASK_DONE")
            local supplies = ProjectALife.TalkSupplies
            if not Party.types[task.type].turnIn and roll(100) < 40 and supplies ~= nil
                    and speaker.shell ~= nil and Party.hasSpare(speaker.shell, "ASK_FOOD") then
                pcall(supplies.respond, speaker.record, speaker.shell, ctx.player, "ASK_FOOD", ctx.now)
            end
        end
        Party.notice(ctx.player, "Job done.")
    else
        Party.metrics.failed = Party.metrics.failed + 1
        if opinion ~= nil then pcall(opinion.note, "party_fail", ctx.lead.record, ctx.player) end
        if speaker ~= nil then Party.say(speaker.record, speaker.shell, ctx.player, "PARTY_TASK_FAIL") end
        Party.notice(ctx.player, "You let the group down on that job.")
    end
    Party.dirty()
    Party.push(ctx.key, ctx.gid, ctx.player)
end

function Party.taskStep(ctx, state)
    local mine = ctx.mine
    local task = mine.task
    if task ~= nil then
        local def = Party.types[task.type]
        if def == nil then mine.task = nil return end
        if ctx.hours > task.deadlineHours then
            Party.settle(ctx, false)
            return
        end
        if def.turnIn ~= true and def.check(task, ctx) == "done" then Party.settle(ctx, true) end
        return
    end
    if ctx.hours < (tonumber(mine.nextTaskHours) or 0) then return end
    if ctx.leadD > 10 or ctx.now - (state.leadStillSince or ctx.now) < Party.settings.taskCalmMs then return end
    if Party.danger(ctx.lead, ctx.roster, ctx.now) then return end
    Party.assign(ctx, false)
end

function Party.onTask(record, shell, player, context, now)
    local mine, key, gid = Party.mineFor(record, player)
    if mine == nil then return Party.say(record, shell, player, "PARTY_JOIN_ELSEWHERE", context) or "[Blinks]", "answered" end
    local ctx = Party.snapshot(key, gid, now)
    if ctx == nil then return nil end
    if mine.task ~= nil then
        local line = Party.say(record, shell, player, "PARTY_TASK_REMIND", context) or ""
        return line .. " [Job: " .. mine.task.text .. "]", "answered"
    end
    if Party.danger(ctx.lead, ctx.roster, now) then
        return Party.say(record, shell, player, "PARTY_TASK_NONE", context) or "[Shrugs]", "answered"
    end
    if ctx.hours - (tonumber(mine.nextTaskHours) or 0) < -Party.settings.taskMinGapHours * 2 then
        return Party.say(record, shell, player, "PARTY_TASK_NONE", context) or "[Shrugs]", "answered"
    end
    if Party.assign(ctx, true) then
        return "[The leader gives you a job. Check your radio panel.]", "answered"
    end
    return Party.say(record, shell, player, "PARTY_TASK_NONE", context) or "[Shrugs]", "answered"
end

function Party.onTurnIn(record, shell, player, context, now)
    local mine, key, gid = Party.mineFor(record, player)
    if mine == nil then return Party.say(record, shell, player, "PARTY_JOIN_ELSEWHERE", context) or "[Blinks]", "answered" end
    local ctx = Party.snapshot(key, gid, now)
    local task = mine.task
    if ctx == nil or task == nil then
        return Party.say(record, shell, player, "PARTY_TASK_NONE", context) or "[Shrugs]", "answered"
    end
    local def = Party.types[task.type]
    local verdict = def ~= nil and def.check(task, ctx) or nil
    if verdict == "ready" then
        if Party.takeItems(player, shell, task.kind, task.count) then
            Party.settle(ctx, true)
            return "[You hand it over.]", "answered"
        end
        return Party.say(record, shell, player, "PARTY_TASK_NOT_YET", context) or "[Frowns]", "answered"
    end
    if verdict == "done" then
        Party.settle(ctx, true)
        return "[Done.]", "answered"
    end
    return Party.say(record, shell, player, "PARTY_TASK_NOT_YET", context) or "[Frowns]", "answered"
end

function Party.tellStory(shell, record, now, forced)
    local gossip = ProjectALife.Gossip
    if gossip == nil or type(gossip.tryStart) ~= "function" or type(gossip.groupKey) ~= "function" then return false, "no_gossip" end
    local key = gossip.groupKey(record)
    if string.sub(key, 1, 5) == "solo:" then return false, "solo" end
    if forced then
        local canonical = gossip.canonicalGroup(shell, key)
        gossip.armedAt[canonical] = 0
        gossip.setCooldown(canonical, "ambient", 0)
        gossip.globalCooldown.ambient = 0
    end
    local ok, result = gossip.tryStart(shell, { context = "ambient", groupId = key, topic = "story", now = now })
    if ok then Party.metrics.stories = Party.metrics.stories + 1 end
    return ok == true, result
end

function Party.onStory(record, shell, player, context, now)
    if Party.option("Party_Stories", true) == false then
        return Party.say(record, shell, player, "PARTY_STORY_NO", context) or "[Shrugs]", "answered"
    end
    local gossip, talk = ProjectALife.Gossip, ProjectALife.Talk
    local key = gossip ~= nil and type(gossip.groupKey) == "function" and gossip.groupKey(record) or "solo:"
    if string.sub(key, 1, 5) == "solo:" then
        return Party.say(record, shell, player, "PARTY_STORY_NO", context) or "[Shrugs]", "answered"
    end
    local canonical = gossip.canonicalGroup(shell, key)
    if gossip.active[canonical] ~= nil then
        return Party.say(record, shell, player, "PARTY_STORY_BUSY", context) or "[Raises a hand]", "answered"
    end
    local caution = ProjectALife.Caution
    local unsafe = talk.inCombat(record)
    if not unsafe and caution ~= nil and type(caution.zombiesNear) == "function" then
        local ok, near = pcall(caution.zombiesNear, shell, now, 14)
        unsafe = ok and near == true
    end
    if unsafe then
        return Party.say(record, shell, player, "PARTY_STORY_DANGER", context) or "[Looks around]", "answered"
    end
    if now < (Party.state.storyAt[canonical] or 0) - Party.settings.storyGapMs + 60000 then
        return Party.say(record, shell, player, "PARTY_STORY_NO", context) or "[Shrugs]", "answered"
    end
    local data = ProjectALife.DialogueData
    data.load()
    local text, chosen = talk.speak(record, shell, player, data.replies.TELL_STORY, context, {})
    if text == nil then
        return Party.say(record, shell, player, "PARTY_STORY_NO", context) or "Not now, can't get my head straight", "answered"
    end
    Party.state.storyAt[canonical] = now + Party.settings.storyGapMs
    Party.metrics.stories = Party.metrics.stories + 1
    return text, chosen ~= nil and chosen.beats ~= nil and "scripted" or "answered"
end

function Party.stories(now)
    if Party.option("Party_Stories", true) == false then return 0 end
    local state = Party.state
    if now < state.storyScanAt then return 0 end
    state.storyScanAt = now + Party.settings.storyScanMs
    local presence, reg, talk, gossip = ProjectALife.ModuleTalkPresence, registry(), ProjectALife.Talk, ProjectALife.Gossip
    if presence == nil or reg == nil or talk == nil or gossip == nil or type(gossip.groupKey) ~= "function" then return 0 end
    local players = presence.players()
    if #players == 0 then return 0 end
    local spots = {}
    for _, player in ipairs(players) do
        local x, y, z = Party.posOf(player)
        if x ~= nil then spots[#spots + 1] = { x = x, y = y, z = math.floor(z), player = player } end
    end
    local limit = Party.settings.storyNearTiles ^ 2
    local buckets, order = {}, {}
    reg.each(function(record)
        if record.lifecycle ~= "active" or type(record.memory) ~= "table" then return false end
        local shell = talk.shellFor(record.uid)
        local x, y, z = Party.posOf(shell)
        if x == nil then return false end
        local near, nearest, nearD = false, nil, limit
        for _, spot in ipairs(spots) do
            local d = (spot.x - x) ^ 2 + (spot.y - y) ^ 2
            if d <= nearD and spot.z == math.floor(z) then near, nearest, nearD = true, spot, d end
        end
        local known = state.pos[record.uid]
        if known == nil or (known.x - x) ^ 2 + (known.y - y) ^ 2 > 6.25 then
            known = { x = x, y = y, sinceMs = now }
            state.pos[record.uid] = known
        end
        known.seenMs = now
        if not near then return false end
        local key = gossip.groupKey(record)
        if string.sub(key, 1, 5) == "solo:" then return false end
        local bucket = buckets[key]
        if bucket == nil then
            bucket = { key = key, count = 0, still = true, player = nearest.player, rep = record, shell = shell, repD = nearD }
            buckets[key] = bucket
            order[#order + 1] = key
        end
        local memory = record.memory
        bucket.count = bucket.count + 1
        if now - known.sinceMs < Party.settings.stillMs or record.activity == "combat"
                or memory.orderedTo ~= nil or memory.robbery ~= nil or memory.visit ~= nil then
            bucket.still = false
        end
        if nearD < bucket.repD then bucket.rep, bucket.shell, bucket.repD = record, shell, nearD end
        return false
    end)
    for uid, known in pairs(state.pos) do
        if now - (known.seenMs or 0) > 120000 then state.pos[uid] = nil end
    end
    table.sort(order)
    local relations = ProjectALife.Relations
    for _, key in ipairs(order) do
        local bucket = buckets[key]
        if bucket.still and bucket.count >= 2 and now >= (state.storyAt[key] or 0) then
            local hostile = false
            if relations ~= nil and type(relations.playerStance) == "function" then
                local ok, stance = pcall(relations.playerStance, bucket.rep, bucket.player)
                hostile = ok and stance == "hostile"
            end
            if not hostile then
                local ok, reason = Party.tellStory(bucket.shell, bucket.rep, now, false)
                if ok then
                    state.storyAt[key] = now + Party.settings.storyGapMs
                    return 1
                end
                local retry = Party.settings.storyRetryMs
                if reason == "gossip_corpus_unmatched" or reason == "gossip_corpus_empty" then retry = retry * 6 end
                state.storyAt[key] = now + retry
            end
        end
    end
    return 0
end

function Party.service(key, gid, now)
    local ctx = nil
    local store = Party.store()
    local entry = store.byGroup[gid]
    if entry == nil or entry.members[key] == nil then
        store.byPlayer[key] = nil
        return
    end
    local state = Party.state.players[key]
    if state == nil then
        state = { lastNearMs = now }
        Party.state.players[key] = state
    end
    local roster = Party.roster(gid)
    if #roster == 0 then
        Party.finish(key, "gone")
        return
    end
    local lead = Party.leaderOf(roster)
    entry.leaderUid = lead.record.uid
    local player = ProjectALife.TalkOrders.playerByKey(key)
    local dead = false
    if player ~= nil and type(player.isDead) == "function" then
        local ok, value = pcall(player.isDead, player)
        dead = ok and value == true
    end
    if dead then
        Party.finish(key, "left")
        return
    end
    local px, py = Party.posOf(player)
    local nearD, leadD, nearest, nearestD = math.huge, math.huge, nil, math.huge
    if px ~= nil then
        for _, member in ipairs(roster) do
            local x, y = Party.entryPos(member)
            if x ~= nil then
                local d = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
                if d < nearD then nearD = d end
                if member == lead then leadD = d end
                if member.shell ~= nil and d < nearestD then nearest, nearestD = member, d end
            end
        end
    end
    if px ~= nil and nearD <= Party.settings.nearTiles then state.lastNearMs = now end
    local awayMs = (tonumber(Party.option("Party_AwayMinutes", 10)) or 10) * 60000
    if now - state.lastNearMs > awayMs then
        Party.finish(key, "desert")
        return
    end
    if px == nil then return end
    local opinion = ProjectALife.NpcOpinion
    if opinion ~= nil and type(opinion.valueOf) == "function" and opinion.valueOf(lead.record, player) < 0 then
        Party.finish(key, "kicked")
        return
    end
    local lx, ly = Party.entryPos(lead)
    if lx ~= nil then
        local last = state.leadAt
        if last == nil or (last.x - lx) ^ 2 + (last.y - ly) ^ 2 > 2.25 then
            state.leadAt = { x = lx, y = ly }
            state.leadStillSince = now
        end
    end
    local settings = Party.settings
    if leadD > settings.lagTiles and leadD <= 120 then
        state.lagSince = state.lagSince or now
        if now - state.lagSince >= settings.lagMs then
            if now >= (state.lagLineAt or 0) and nearest ~= nil and nearestD <= settings.hearTiles + 15 then
                Party.say(nearest.record, nearest.shell, player, "PARTY_LAG")
                state.lagLineAt = now + settings.lagLineGapMs
            end
            if now >= (state.waitCooldownAt or 0) then
                Party.hold(roster, now + settings.waitMs)
                state.waitUntil, state.waitCooldownAt = now + settings.waitMs, now + settings.waitGapMs
            end
        end
    else
        state.lagSince = nil
        if state.waitUntil ~= nil and leadD <= 14 then
            Party.release(roster)
            state.waitUntil = nil
        end
    end
    if state.waitUntil ~= nil and now > state.waitUntil + 5000 then state.waitUntil = nil end
    if now >= (state.warnAt or 0) and nearest ~= nil and nearestD <= settings.hearTiles then
        local caution = ProjectALife.Caution
        if caution ~= nil and type(caution.bodies) == "function" then
            local ok, rows = pcall(caution.bodies, now)
            local count, limit = 0, settings.warnTiles ^ 2
            if ok and type(rows) == "table" then
                for index = 1, #rows do
                    local row = rows[index]
                    if (row.x - px) ^ 2 + (row.y - py) ^ 2 <= limit then
                        count = count + 1
                        if count >= 4 then break end
                    end
                end
            end
            if count > 0 then
                local speaker = Party.speaker(roster, player, nil)
                if speaker ~= nil then
                    Party.say(speaker.record, speaker.shell, player, count >= 4 and "PARTY_WARN_HORDE" or "PARTY_WARN_ZOMBIES")
                    Party.metrics.warned = Party.metrics.warned + 1
                end
                state.warnAt = now + settings.warnGapMs
            end
        end
    end
    ctx = { key = key, gid = gid, entry = entry, mine = entry.members[key], roster = roster, lead = lead, player = player,
        px = px, py = py, nearD = nearD, leadD = leadD, now = now, hours = Party.hours() }
    Party.taskStep(ctx, state)
    if now - (state.pushedMs or 0) >= settings.pushMs then
        state.pushedMs = now
        Party.push(key, gid, player)
    end
end

function Party.tick(now)
    if not Party.enabled() then return 0 end
    now = tonumber(now) or nowMs()
    if now - Party.state.tickAt < Party.settings.tickMs then return 0 end
    Party.state.tickAt = now
    local store = Party.store()
    local keys, work = {}, 0
    for key in pairs(store.byPlayer) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local gid = store.byPlayer[key]
        if gid ~= nil then
            pcall(Party.service, key, gid, now)
            work = work + 1
        end
    end
    local ok, started = pcall(Party.stories, now)
    if ok then work = work + (tonumber(started) or 0) end
    return work
end

Party.breakers = { hit = true, robbery = true, killed_mate = true, betrayal = true }

function Party.onOpinion(kind, record, player)
    if Party.breakers[kind] ~= true or type(record) ~= "table" or type(record.memory) ~= "table" then return false end
    local gid = record.memory.groupId
    local key = Party.keyOf(player)
    if gid == nil or key == nil or Party.store().byPlayer[key] ~= gid then return false end
    return Party.finish(key, "hostile")
end

function Party.decorate(result, uid, player)
    if type(result) ~= "table" then return result end
    result.party, result.partyTask = false, false
    local reg = registry()
    local record = reg ~= nil and reg.read(uid) or nil
    if record == nil then return result end
    local mine = Party.mineFor(record, player)
    if mine ~= nil then
        result.party = true
        result.partyTask = mine.task ~= nil
    end
    return result
end

function Party.register()
    local talk = ProjectALife.Talk
    if talk == nil then return end
    talk.choiceHandlers.PARTY_JOIN = Party.join
    talk.choiceHandlers.PARTY_LEAVE = Party.onLeave
    talk.choiceHandlers.PARTY_TASK_ASK = Party.onTask
    talk.choiceHandlers.PARTY_TASK_REMIND = Party.onTask
    talk.choiceHandlers.PARTY_TASK_DONE = Party.onTurnIn
    talk.choiceHandlers.PARTY_STORY = Party.onStory
end
Party.register()

return Party
