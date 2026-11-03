ProjectALife = ProjectALife or {}

require "ProjectALife/Behaviours/ALifeModuleRegistry"

local Registry = ProjectALife.ModuleRegistry

local Leader = {
    settings = {
        beatMs = 1500,

        stationRange = 9,

        deploySpread = 3.5,
        deployAdvance = 1.0,

        rallyDistance = 20,
        rallyHoldMs = 45000,

        aimedFallbackDistance = 13,

        orderMs = 20000,
    },

    groups = {},
    metrics = { beats = 0, deployments = 0, rallies = 0, scatters = 0 },
}
ProjectALife.ModuleLeader = Leader

local function nowMsFallback()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Leader.configure(options)
    options = type(options) == "table" and options or {}
    for key, value in pairs(options) do
        if Leader.settings[key] ~= nil and tonumber(value) ~= nil then
            Leader.settings[key] = tonumber(value)
        end
    end
    return true
end

function Leader.reset()
    Leader.groups = {}
end

local function eachMember(groupId, exceptUid, visit)
    pcall(function()
        local watchdog = ProjectALife.Watchdog
        local registry = ProjectALife.ActorRegistry
        if watchdog == nil or registry == nil then return end
        for uid, binding in pairs(watchdog.bindings) do
            if uid ~= exceptUid and binding ~= nil and binding.shell ~= nil then
                local actor = registry.read(uid)
                if actor ~= nil and actor.lifecycle == "active"
                        and actor.memory ~= nil and actor.memory.groupId == groupId then
                    visit(uid, actor, binding.shell)
                end
            end
        end
    end)
end

local function order(uid, actor, kind, anchor, untilMs)
    local stance = actor.memory and actor.memory.stance
    if stance == "blockade" or stance == "garrison" or stance == "holdout" or stance == "occupy_high" or stance == "shelter" then return false end
    local accepted = false
    pcall(function()
        local decisions = ProjectALife.DecisionLoop
        if decisions == nil then return end
        accepted = decisions.setOrder(uid, actor.generation, {
            kind = kind, anchor = anchor, untilMs = untilMs, quiet = true, source = "leader",
        }) == true
    end)
    return accepted
end

function Leader.pressing(actor, contact)
    if type(contact) ~= "table" then return false end
    local resistance = ProjectALife.Resistance
    if resistance == nil or type(resistance.crewPresses) ~= "function" then return false end
    return resistance.crewPresses(actor, contact) == true
end

function Leader.releaseOrders(uid, actor, groupId)
    local decisions = ProjectALife.DecisionLoop
    if decisions == nil or type(decisions.clearLeaderOrder) ~= "function" then return end
    decisions.clearLeaderOrder(uid, actor.generation)
    eachMember(groupId, uid, function(memberUid, memberActor)
        decisions.clearLeaderOrder(memberUid, memberActor.generation)
    end)
end

local function groupContact(groupId, now)
    local contact
    pcall(function()
        local tactics = ProjectALife.SquadTactics
        if tactics == nil or type(tactics.contacts) ~= "table" then return end
        local held = tactics.contacts[groupId]
        if type(held) ~= "table" then return end
        if held.target and held.target.isDead and held.target:isDead() then return end
        if now - (tonumber(held.atMs) or 0) > 12000 then return end

        local kind = tostring(held.kind or "")
        if kind ~= "actor" and kind ~= "player" then return end

        contact = {
            kind = kind,
            playerKey = kind == "player" and held.target and held.target.getUsername and held.target:getUsername() or nil,
            targetUid = kind == "actor" and held.target and held.target:getModData().ProjectALifeUID or nil,
            target = kind == "player" and held.target or nil,
            atMs = tonumber(held.atMs),
            x = held.position and tonumber(held.position.x) or nil,
            y = held.position and tonumber(held.position.y) or nil,
            z = held.position and tonumber(held.position.z) or 0,
        }
    end)
    return contact
end

local function rallyPoint(shell, contact, distance)
    local point
    pcall(function()
        local sx, sy, sz = shell:getX(), shell:getY(), shell:getZ()
        local dx, dy = sx - (tonumber(contact.x) or sx), sy - (tonumber(contact.y) or sy)
        local length = math.sqrt(dx * dx + dy * dy)
        if length < 0.001 then dx, dy, length = 1, 0, 1 end
        dx, dy = dx / length, dy / length
        point = { x = sx + dx * distance, y = sy + dy * distance, z = sz }
    end)

    pcall(function()
        local cell = getCell()
        local square = cell and cell:getGridSquare(
            math.floor(point.x), math.floor(point.y), math.floor(point.z))
        local probe = square or shell:getCurrentSquare()
        local building = probe and probe:getBuilding()
        if building == nil then return end
        local definition = building:getDef()
        if definition == nil or definition.getRooms == nil then return end
        local rooms = definition:getRooms()
        if rooms == nil then return end
        local here = math.floor(shell:getZ())
        local count = math.min(rooms:size(), 6)
        for index = 0, count - 1 do
            local room = rooms:get(index)
            if room ~= nil then
                local tile
                pcall(function() tile = cell:getFreeTile(room) end)
                if tile ~= nil and math.floor(tile:getZ()) == here then
                    point = { x = tile:getX() + 0.5, y = tile:getY() + 0.5,
                        z = tile:getZ() }
                    return
                end
            end
        end
    end)
    return point
end

function Leader.tick(shell, data, now)
    if data.ProjectALifeConduct ~= "leader" then return end
    if not Registry.isEnabled("leader") then return end
    local uid = data.ProjectALifeUID
    if type(uid) ~= "string" then return end
    local registry = ProjectALife.ActorRegistry
    if registry == nil then return end
    local actor = registry.read(uid)
    if actor == nil or actor.lifecycle ~= "active"
            or actor.memory == nil or actor.memory.groupId == nil then
        return
    end
    local groupId = actor.memory.groupId
    local group = Leader.groups[groupId]
    if group == nil then
        group = { leaderUid = uid, size = tonumber(actor.memory.groupSize) or 0 }
        Leader.groups[groupId] = group
    end
    if now < (group.nextBeatAtMs or 0) then return end
    group.nextBeatAtMs = now + Leader.settings.beatMs
    Leader.metrics.beats = Leader.metrics.beats + 1

    local contact = groupContact(groupId, now)
    local rallying = now < (group.rallyUntilMs or 0)
    local pressing = Leader.pressing(actor, contact)
    if pressing and (rallying or group.deployedAtMs ~= nil) then
        group.rallyUntilMs, group.deployedAtMs, rallying = nil, nil, false
        Leader.releaseOrders(uid, actor, groupId)
    end

    if contact ~= nil then
        group.contactAtMs = now
        group.inContact = true
    elseif group.inContact == true and now - (tonumber(group.contactAtMs) or 0) > 8000 then
        group.inContact = false
        group.fightEndedAtMs = now
        pcall(function()
            local voice = ProjectALife.Voice
            if voice ~= nil then voice.play(shell, "COMBAT_END") end
        end)
    end

    local alive, members = 1, {}
    eachMember(groupId, uid, function(memberUid, memberActor, memberShell)
        alive = alive + 1
        members[#members + 1] = { uid = memberUid, actor = memberActor, shell = memberShell }
    end)
    if (group.size or 0) < alive then group.size = alive end
    local losses = math.max(0, (group.size or alive) - alive)
    local rallyLosses = math.max(1, math.floor((group.size or alive) * 0.2 + 0.5))

    if not rallying and losses >= rallyLosses and contact ~= nil and not pressing then
        group.rallyUntilMs = now + Leader.settings.rallyHoldMs
        Leader.metrics.rallies = Leader.metrics.rallies + 1
        local fallback = rallyPoint(shell, contact, Leader.settings.rallyDistance)
        if fallback ~= nil then
            local band = Leader.settings.aimedFallbackDistance or 13
            local bandSq = band * band

            local farSq = (Leader.settings.rallyDistance + band) ^ 2
            local function fallBackMember(memberUid, memberActor, memberShell)

                local clear, far = true, false
                pcall(function()
                    local dx = memberShell:getX() - (tonumber(contact.x) or memberShell:getX())
                    local dy = memberShell:getY() - (tonumber(contact.y) or memberShell:getY())
                    clear = (dx * dx + dy * dy) >= bandSq
                    far = (dx * dx + dy * dy) > farSq
                end)
                if far then return end
                if clear then

                    if order(memberUid, memberActor, "hold", fallback,
                            now + Leader.settings.rallyHoldMs) then
                        pcall(function()
                            memberShell:getModData().ProjectALifeSprintUntilMs = now + 6000
                        end)
                    end
                end
            end
            for _, member in ipairs(members) do
                fallBackMember(member.uid, member.actor, member.shell)
            end
            fallBackMember(uid, actor, shell)
        end
        return
    end

    local leaderUnderFire = false
    pcall(function()
        local hitAt = tonumber(data.ProjectALifeLastHitAtMs)
        leaderUnderFire = hitAt ~= nil and now - hitAt < 4000
    end)
    if leaderUnderFire and not rallying and not pressing then
        local sx, sy, sz = 0, 0, 0
        pcall(function() sx, sy, sz = shell:getX(), shell:getY(), shell:getZ() end)
        for _, member in ipairs(members) do
            pcall(function()
                member.shell:getModData().ProjectALifeHoldFireUntilMs = nil
            end)
            order(member.uid, member.actor, "hold",
                { x = sx, y = sy, z = sz }, now + 6000)
        end
        group.deployedAtMs = nil

        group.coordinated = false
        return
    end

    if contact ~= nil then
        pcall(function()
            local panic = ProjectALife.ModulePanic
            if panic ~= nil then panic.steady(groupId, shell, members, now) end
        end)
    end

    pcall(function()
        local breach = ProjectALife.ModuleBreach
        if breach == nil then return end

        local stance = type(actor.memory) == "table" and actor.memory.stance or nil
        if stance ~= nil and breach.holdingStances ~= nil
                and breach.holdingStances[stance] == true then
            return
        end
        breach.leaderBeat(actor, shell, groupId, members, now)
    end)

    if contact ~= nil and not rallying then
        if not pressing and (group.deployedAtMs == nil or now - group.deployedAtMs > 10000) then
            group.deployedAtMs = now
            group.released = nil
            Leader.metrics.deployments = Leader.metrics.deployments + 1

            pcall(function()
                local support = ProjectALife.Support
                if support ~= nil then support.request(actor, shell, contact, now) end
            end)
            pcall(function()
                local voice = ProjectALife.Voice
                if voice ~= nil then voice.play(shell, "LEADER_ORDER") end
            end)
            local sx, sy, sz = 0, 0, 0
            pcall(function() sx, sy, sz = shell:getX(), shell:getY(), shell:getZ() end)
            local dx, dy = (tonumber(contact.x) or sx) - sx, (tonumber(contact.y) or sy) - sy
            local length = math.sqrt(dx * dx + dy * dy)
            if length < 0.001 then dx, dy, length = 1, 0, 1 end
            dx, dy = dx / length, dy / length

            local px, py = -dy, dx
            local rifles, blades = {}, {}
            for _, member in ipairs(members) do
                local carry = ""
                pcall(function()
                    carry = tostring(member.shell:getModData().ProjectALifeWeaponClass or "")
                end)
                if carry == "rifle" or carry == "handgun" then
                    rifles[#rifles + 1] = member
                else
                    blades[#blades + 1] = member
                end
            end
            for index, member in ipairs(rifles) do
                local side = (index % 2 == 0) and 1 or -1
                local rank = math.ceil(index / 2)
                local anchor = {
                    x = sx + dx * Leader.settings.deployAdvance
                        + px * side * rank * Leader.settings.deploySpread,
                    y = sy + dy * Leader.settings.deployAdvance
                        + py * side * rank * Leader.settings.deploySpread,
                    z = sz,
                }
                order(member.uid, member.actor, "hold", anchor,
                    now + Leader.settings.orderMs)
            end
            for index, member in ipairs(blades) do
                local side = (index % 2 == 0) and 1 or -1
                local anchor = {
                    x = sx + px * side * 1.5, y = sy + py * side * 1.5, z = sz,
                }
                order(member.uid, member.actor, "hold", anchor,
                    now + Leader.settings.orderMs)
            end
        end

        group.coordinated, group.released = false, true
        data.ProjectALifeHoldFireUntilMs = nil
        for _, member in ipairs(members) do
            member.shell:getModData().ProjectALifeHoldFireUntilMs = nil
        end
        return
    end

    if contact == nil and not rallying then
        if group.deployedAtMs ~= nil then
            local decisions = ProjectALife.DecisionLoop
            if decisions and decisions.clearLeaderOrder then
                decisions.clearLeaderOrder(uid, actor.generation)
                for _, member in ipairs(members) do
                    decisions.clearLeaderOrder(member.uid, member.actor.generation)
                end
            end
        end
        group.deployedAtMs = nil
        group.released = nil
        group.coordinated = nil
        local sx, sy, sz = 0, 0, 0
        pcall(function() sx, sy, sz = shell:getX(), shell:getY(), shell:getZ() end)
        local reach = Leader.settings.stationRange
        local formation = ProjectALife.GroupSpread
        if formation ~= nil and type(formation.reach) == "function" then
            reach = math.max(reach, formation.reach(#members + 1))
        end
        local resting = ProjectALife.GroupLife
        if resting ~= nil and type(resting.stateOf) == "function" and resting.stateOf(groupId) ~= nil then
            reach = math.huge
        end
        for _, member in ipairs(members) do
            local far = false
            pcall(function()
                local dx = member.shell:getX() - sx
                local dy = member.shell:getY() - sy
                far = dx * dx + dy * dy > reach * reach
            end)
            if far then
                local anchor = { x = sx, y = sy, z = sz }
                local spread = ProjectALife.GroupSpread
                if spread ~= nil and type(spread.stationPoint) == "function" then
                    anchor = spread.stationPoint(member.actor, member.shell, anchor, now) or anchor
                end
                order(member.uid, member.actor, "hold", anchor, now + Leader.settings.orderMs)
            end
        end
    end
end

function Leader.onActorDied(actor)
    if type(actor) ~= "table" or actor.memory == nil then return end
    if actor.memory.conduct ~= "leader" then return end
    local groupId = actor.memory.groupId
    if groupId == nil then return end
    Leader.groups[groupId] = nil
    Leader.metrics.scatters = Leader.metrics.scatters + 1
    local now = nowMsFallback()
    local pressing = Leader.pressing(actor, groupContact(groupId, now))
    local index = 0

    local successor, successorIndex = nil, math.huge
    eachMember(groupId, actor.uid, function(memberUid, memberActor, memberShell)
        index = index + 1
        local rank = tonumber(memberActor.memory and memberActor.memory.groupIndex) or (100 + index)
        if rank < successorIndex then
            successor, successorIndex = { uid = memberUid, actor = memberActor, shell = memberShell }, rank
        end
        pcall(function()
            local decisions = ProjectALife.DecisionLoop
            if decisions ~= nil and type(decisions.orders) == "table" then
                decisions.orders[memberUid] = nil
            end
        end)
        pcall(function()
            local memberData = memberShell:getModData()
            memberData.ProjectALifeHoldFireUntilMs = nil
            memberData.ProjectALifeSprintUntilMs = now + 5000
        end)

        local angle = (index % 8) * (math.pi / 4)
        local anchor
        pcall(function()
            anchor = {
                x = memberShell:getX() + math.cos(angle) * 14,
                y = memberShell:getY() + math.sin(angle) * 14,
                z = memberShell:getZ(),
            }
        end)
        if anchor ~= nil and not pressing then
            order(memberUid, memberActor, "hold", anchor, now + 15000)
        end
    end)

    Leader.promote(groupId, successor, now)
end

function Leader.promote(groupId, successor, now)
    if type(successor) ~= "table" or successor.uid == nil then return false end
    local registry = ProjectALife.ActorRegistry
    if registry == nil then return false end
    local fresh = registry.read(successor.uid)
    if fresh == nil or fresh.lifecycle ~= "active" then return false end
    local updated = registry.update(fresh.uid, fresh.revision, function(record)
        record.memory = record.memory or {}
        record.memory.conduct = "leader"
        record.memory.groupRole = "leader"
        record.memory.promotedAtMs = now
    end)
    if updated == nil then return false end
    pcall(function() successor.shell:getModData().ProjectALifeConduct = "leader" end)
    Leader.groups[groupId] = { leaderUid = successor.uid, promotedAtMs = now }
    Leader.metrics.promotions = (Leader.metrics.promotions or 0) + 1
    pcall(function()
        local voice = ProjectALife.Voice
        if voice ~= nil then voice.play(successor.shell, "LEADER_ORDER", { force = true }) end
    end)
    return true
end

Registry.register({
    id = "leader",
    kind = "doctrine",
    primary = true,
    label = "Squad leader",
    summary = "Keeps the group together, deploys it on contact and rallies it after losses. Orders never delay shooting; its death scatters the group.",
    defaultEnabled = true,
    evaluate = function() return nil end,
})

return Leader
