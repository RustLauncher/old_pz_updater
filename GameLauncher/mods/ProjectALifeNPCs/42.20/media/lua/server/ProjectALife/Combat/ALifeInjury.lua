require "ProjectALife/Behaviours/ALifeInjuryRules"
require "ProjectALife/Combat/ALifeHealth"
require "ProjectALife/Shells/ALifeAnimations"
require "ProjectALife/Shells/ALifeShellSimulation"
require "ProjectALife/Shells/ALifeWounds"
require "ProjectALife/Talk/ALifeSpeech"

ProjectALife = ProjectALife or {}

local Rules = ProjectALife.InjuryRules
local Health = ProjectALife.Health

local Injury = {
    motion = setmetatable({}, { __mode = "k" }),
    metrics = { entered = 0, bleedOutsTaken = 0, bleedOutsDeclined = 0, recovered = 0, selfRecovered = 0, aided = 0,
        released = 0, restored = 0, barks = 0, rescueStarted = 0, rescueDone = 0, rescueAborted = 0,
        interrogations = 0, interrogationDeaths = 0, debugMade = 0, debugHealed = 0,
        deaths = 0, pinned = 0, spread = 0, debugRescues = 0, crawled = 0, shuffled = 0, crawlBlocked = 0,
        handedDown = 0 },
    events = { "INJURED_DOWN", "INJURED_BEG", "INJURED_RESCUED", "INJURED_UP", "INJURED_DEATH" },
}
ProjectALife.Injury = Injury

do
    local speech = ProjectALife.Speech
    if type(speech) == "table" and type(speech.downedEvents) == "table" then
        for _, event in ipairs(Injury.events) do speech.downedEvents[event] = true end
    end
end

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function roll(limit)
    if type(ZombRand) == "function" then return ZombRand(limit) end
    return 0
end

function Injury.now()
    return nowMs()
end

function Injury.roll(limit)
    return roll(limit)
end

function Injury.log(text)
    print("[ALIFE-INJURY] " .. tostring(text))
end

function Injury.singlePlayer()
    local server = type(isServer) == "function" and isServer() == true
    local client = type(isClient) == "function" and isClient() == true
    return not server and not client
end

function Injury.multiplayerAllowed()
    return Injury.singlePlayer() or Rules.flag("Injury_MultiplayerEnabled", true)
end

function Injury.enabled()
    return not (type(isServer) == "function" and isServer()) and Rules.flag("Injury_Enabled", true)
        and Injury.multiplayerAllowed()
end

function Injury.serverDelegates()
    local executor = ProjectALife.Executor
    return type(isServer) == "function" and isServer() == true and executor ~= nil
        and type(executor.serverDelegates) == "function" and executor.serverDelegates() == true
end

function Injury.drives(shell)
    if type(isServer) == "function" and isServer() then return false end
    local fence = ProjectALife.AIFence
    if fence ~= nil and type(fence.drivesBody) == "function" then return fence.drivesBody(shell) == true end
    return Injury.singlePlayer()
end

function Injury.dataOf(shell)
    if shell == nil or type(shell.getModData) ~= "function" then return nil end
    local ok, data = pcall(shell.getModData, shell)
    if not ok or type(data) ~= "table" then return nil end
    return data
end

function Injury.alive(shell)
    if shell == nil or type(shell.isDead) ~= "function" then return false end
    local ok, dead = pcall(shell.isDead, shell)
    return ok and dead ~= true
end

function Injury.xyz(shell)
    if shell == nil or type(shell.getX) ~= "function" then return nil end
    local ok, x, y, z = pcall(function() return shell:getX(), shell:getY(), shell:getZ() end)
    if not ok or x == nil then return nil end
    return x, y, z or 0
end

function Injury.hours()
    local hours = ProjectALife.ShellSimulation ~= nil and ProjectALife.ShellSimulation.worldHours() or nil
    return tonumber(hours) or 0
end

function Injury.recordOf(data)
    local registry = ProjectALife.ActorRegistry
    local uid = type(data) == "table" and data.ProjectALifeUID or nil
    if registry == nil or type(uid) ~= "string" or type(registry.peek) ~= "function" then return nil end
    return registry.peek(uid)
end

function Injury.shellOf(uid)
    local watchdog = ProjectALife.Watchdog
    local binding = watchdog ~= nil and type(watchdog.bindings) == "table" and watchdog.bindings[uid] or nil
    local shell = binding ~= nil and binding.shell or nil
    if shell == nil or not Injury.alive(shell) then return nil end
    return shell, binding
end

function Injury.healthOf(shell)
    local sim = ProjectALife.ShellSimulation
    local maximum = tonumber(sim.maximumFor(shell)) or 0
    local current = tonumber(sim.trueHealth(shell)) or 0
    return current, maximum
end

function Injury.setHealth(shell, health)
    local sim = ProjectALife.ShellSimulation
    return sim.setHealth(shell, math.max(0.01, health))
end

function Injury.applyMemory(record)
    record.memory = type(record.memory) == "table" and record.memory or {}
    record.memory.injury = Injury.pendingMemory
end

function Injury.writeMemory(data, payload)
    local registry = ProjectALife.ActorRegistry
    local uid = type(data) == "table" and data.ProjectALifeUID or nil
    if registry == nil or type(uid) ~= "string" or type(registry.peek) ~= "function"
            or type(registry.updateTransient) ~= "function" then return false end
    local current = registry.peek(uid)
    if current == nil then return false end
    Injury.pendingMemory = payload
    local ok, written = pcall(registry.updateTransient, current.uid, current.revision, Injury.applyMemory, true)
    Injury.pendingMemory = nil
    return ok and written == true
end

function Injury.persist(data)
    local state = data.ProjectALifeInjured
    if state == nil then return Injury.writeMemory(data, nil) end
    local stored = Rules.lying(state) and "down" or (state == "healing" and "down" or state)
    return Injury.writeMemory(data, {
        s = stored,
        h = tonumber(data.ProjectALifeInjurySinceHours) or Injury.hours(),
        f = tonumber(data.ProjectALifeInjuryStartFraction),
        a = data.ProjectALifeInjuryAided == true and 1 or nil,
    })
end

function Injury.say(shell, data, event, player)
    local speech = ProjectALife.Speech
    if speech == nil or not Injury.alive(shell) then return nil end
    local record = Injury.recordOf(data)
    local text
    if record ~= nil and type(speech.bark) == "function" then
        local listener = player ~= nil and type(player.getUsername) == "function" and player or nil
        local ok, picked = pcall(speech.bark, record, shell, event, { player = listener, face = player })
        if ok and type(picked) == "string" then text = picked end
    end
    if text == nil and type(speech.say) == "function" then
        local line = Rules.line(event, roll(1000))
        if line ~= nil then
            local ok, said = pcall(speech.say, shell, line, { downedOk = true, face = player })
            if ok and said == true then text = line end
        end
    end
    if text ~= nil then Injury.metrics.barks = Injury.metrics.barks + 1 end
    return text
end

function Injury.playerRows()
    local locator = ProjectALife.PlayerLocator
    local rows = {}
    if locator == nil or type(locator.list) ~= "function" or type(locator.position) ~= "function" then return rows end
    for _, player in ipairs(locator.list() or {}) do
        local dead = false
        if type(player.isDead) == "function" then
            local ok, value = pcall(player.isDead, player)
            dead = ok and value == true
        end
        local at = locator.position(player)
        if not dead and type(at) == "table" then
            rows[#rows + 1] = { x = at.x, y = at.y, z = at.z, body = player }
        end
    end
    return rows
end

function Injury.playerNear(shell, range)
    local x, y = Injury.xyz(shell)
    if x == nil then return true end
    local adapter = ProjectALife.ShellAdapter
    if adapter ~= nil and type(adapter.zombieWatched) == "function" then
        local ok, watched = pcall(adapter.zombieWatched, shell)
        if ok and watched == true then return true end
    end
    return Rules.playerInRange(Injury.playerRows(), x, y, range)
end

function Injury.stopBleeding(shell, data)
    local list = Health.injuriesOf(shell, data)
    if list == nil or #list == 0 then
        pcall(Health.addInjury, shell, data, "firearm", "torso")
        list = Health.injuriesOf(shell, data)
    end
    if list == nil then return 0 end
    local covered = ProjectALife.Wounds.bandage(list)
    pcall(Health.persistInjuries, data)
    pcall(Health.applyInjuries, data, list, Injury.hours())
    data.ProjectALifeWounds = nil
    return covered
end

function Injury.stamp(shell, data, now)
    local lease = Rules.settings().leaseMs
    data.ProjectALifeInjuryHoldUntilMs = now + lease
    data.ProjectALifeDownedUntilMs = now + lease
    data.ProjectALifeBleedOutAtMs = nil
    data.ProjectALifeDragUntilMs = now + lease
end

function Injury.freeze(shell, data, now)
    if not Injury.drives(shell) then return false end
    local uid, generation = data.ProjectALifeUID, data.ProjectALifeGeneration
    if type(uid) == "string" then
        pcall(function()
            if ProjectALife.Movement ~= nil then ProjectALife.Movement.stop(shell) end
        end)
        pcall(function()
            if ProjectALife.ActionLedger ~= nil then ProjectALife.ActionLedger.cancelActor(uid, generation, "injured") end
        end)
        pcall(function()
            if ProjectALife.Scavenging ~= nil and type(ProjectALife.Scavenging.cancelActor) == "function" then
                ProjectALife.Scavenging.cancelActor(uid, generation, "injured")
            end
        end)
        local decisions = ProjectALife.DecisionLoop
        if decisions ~= nil and type(decisions.states) == "table" then
            if type(decisions.orders) == "table" then decisions.orders[uid] = nil end
            decisions.states[uid] = { kind = "idle", intent = "injured", cooldownUntilMs = now + 1500 }
        end
    end
    pcall(function() shell:setMoving(false) end)
    pcall(function() shell:setTarget(nil) end)
    data.ProjectALifeAimAtX, data.ProjectALifeAimAtY = nil, nil
    Injury.stamp(shell, data, now)
end

function Injury.clearAnchor(data)
    data.ProjectALifeInjuryAnchorX, data.ProjectALifeInjuryAnchorY = nil, nil
end

function Injury.lyingNear(shell, x, y, z, reach)
    local rows = {}
    local watchdog = ProjectALife.Watchdog
    if watchdog == nil or type(watchdog.bindings) ~= "table" then return rows end
    local limit = reach * reach
    for _, binding in pairs(watchdog.bindings) do
        local other = type(binding) == "table" and binding.shell or nil
        if other ~= nil and other ~= shell then
            local data = Injury.dataOf(other)
            if data ~= nil and Rules.lying(data.ProjectALifeInjured) and Injury.alive(other) then
                local ox, oy, oz = Injury.xyz(other)
                if ox ~= nil and math.abs(oz - z) < 1 and (ox - x) ^ 2 + (oy - y) ^ 2 < limit then
                    rows[#rows + 1] = { x = ox, y = oy }
                end
            end
        end
    end
    return rows
end

function Injury.spread(shell, data)
    local x, y, z = Injury.xyz(shell)
    if x == nil or #Injury.lyingNear(shell, x, y, z, 0.9) == 0 then return false end
    local fence = ProjectALife.AIFence
    local square = type(shell.getCurrentSquare) == "function" and shell:getCurrentSquare() or nil
    if fence == nil or square == nil or type(fence.moveBody) ~= "function" or type(fence.stepClear) ~= "function" then
        return false
    end
    local first = roll(8)
    for attempt = 0, 7 do
        local angle = ((first + attempt) % 8) * math.pi / 4
        local nx, ny = x + math.cos(angle), y + math.sin(angle)
        if #Injury.lyingNear(shell, nx, ny, z, 0.9) == 0 and fence.stepClear(shell, square, x, y, nx, ny) == true then
            fence.moveBody(shell, nx, ny)
            Injury.metrics.spread = Injury.metrics.spread + 1
            Injury.log("spread uid=" .. tostring(data.ProjectALifeUID) .. " from=" .. string.format("%.1f,%.1f", x, y)
                .. " to=" .. string.format("%.1f,%.1f", nx, ny))
            return true
        end
    end
    return false
end

function Injury.groupPull(shell, data, record, x, y, z, tiles)
    local rescue, watchdog = ProjectALife.InjuryRescue, ProjectALife.Watchdog
    if rescue == nil or record == nil or watchdog == nil or type(watchdog.bindings) ~= "table" then return nil end
    local limit = tiles * tiles
    local sx, sy, count = 0, 0, 0
    for uid, binding in pairs(watchdog.bindings) do
        local other = type(binding) == "table" and binding.shell or nil
        if other ~= nil and other ~= shell and uid ~= data.ProjectALifeUID and Injury.alive(other) then
            local ox, oy, oz = Injury.xyz(other)
            if ox ~= nil and math.abs(oz - z) < 1 and (ox - x) ^ 2 + (oy - y) ^ 2 <= limit then
                local otherData = Injury.dataOf(other)
                local mate = ProjectALife.ActorRegistry ~= nil and ProjectALife.ActorRegistry.peek(uid) or nil
                if otherData ~= nil and otherData.ProjectALifeInjured == nil and mate ~= nil
                        and mate.lifecycle == "active" and rescue.sameTeam(record, mate) then
                    sx, sy, count = sx + ox, sy + oy, count + 1
                end
            end
        end
    end
    if count == 0 then return nil end
    return sx / count, sy / count, count
end

function Injury.nudge(shell, data, ux, uy, step, now)
    local fence = ProjectALife.AIFence
    if fence == nil or type(fence.stepClear) ~= "function" or type(fence.moveBody) ~= "function"
            or type(shell.getCurrentSquare) ~= "function" then return false end
    local x, y, z = Injury.xyz(shell)
    local square = shell:getCurrentSquare()
    if x == nil or square == nil then return false end
    for _, turn in ipairs({ 0, 35, -35, 70, -70 }) do
        local dx, dy = Rules.rotate(ux, uy, turn)
        local nx, ny = x + dx * step, y + dy * step
        local ok, clear = pcall(fence.stepClear, shell, square, x, y, nx, ny)
        if ok and clear == true and #Injury.lyingNear(shell, nx, ny, z, 0.6) == 0 then
            Injury.motion[shell] = { x = x, y = y, tx = nx, ty = ny, atMs = now,
                durationMs = Rules.settings().beatMs }
            data.ProjectALifeInjuryWritheUntilMs = now + 700
            local rescue = ProjectALife.InjuryRescue
            if rescue ~= nil and type(rescue.face) == "function" then rescue.face(shell, x - dx * 4, y - dy * 4, now) end
            return true, dx, dy
        end
    end
    Injury.metrics.crawlBlocked = Injury.metrics.crawlBlocked + 1
    return false
end

function Injury.moveFrame(shell, data, now)
    local move = Injury.motion[shell]
    if move == nil then return false end
    local rescue = ProjectALife.InjuryRescue
    if data.ProjectALifeInjured ~= "down" or now < move.atMs
            or (rescue ~= nil and rescue.active[data.ProjectALifeUID] ~= nil) then
        Injury.motion[shell] = nil
        return false
    end
    local fraction = math.min(1, (now - move.atMs) / move.durationMs)
    local x, y = shell:getX(), shell:getY()
    local nx, ny = move.x + (move.tx - move.x) * fraction, move.y + (move.ty - move.y) * fraction
    local fence = ProjectALife.AIFence
    local square = shell:getCurrentSquare()
    if square == nil or not fence.stepClear(shell, square, x, y, nx, ny) then
        Injury.motion[shell] = nil
        Injury.metrics.crawlBlocked = Injury.metrics.crawlBlocked + 1
        return false
    end
    fence.moveBody(shell, nx, ny)
    data.ProjectALifeInjuryAnchorX, data.ProjectALifeInjuryAnchorY = nx, ny
    if fraction >= 1 then Injury.motion[shell] = nil end
    return true
end

function Injury.crawl(shell, data, now, settings, x, y, z, record, tx, ty)
    local ux, uy = Rules.unit(x - tx, y - ty)
    local gx, gy = Injury.groupPull(shell, data, record, x, y, z, settings.crawlGroupTiles)
    if gx ~= nil then
        local px, py = Rules.unit(gx - x, gy - y)
        if px * ux + py * uy > -0.3 then ux, uy = Rules.unit(ux + px * 0.6, uy + py * 0.6) end
    end
    local travelled = tonumber(data.ProjectALifeInjuryCrawled) or 0
    if travelled >= settings.crawlMax then return false end
    local moved = Injury.nudge(shell, data, ux, uy, settings.crawlStep, now)
    if moved then
        data.ProjectALifeInjuryCrawled = travelled + settings.crawlStep
        Injury.metrics.crawled = Injury.metrics.crawled + 1
    end
    return moved
end

function Injury.shuffle(shell, data, now, settings, x, y, z, record)
    local current = data.ProjectALifeInjuryShuffle
    if current == nil then
        if now < (tonumber(data.ProjectALifeInjuryNextShuffleMs) or 0) then return false end
        data.ProjectALifeInjuryNextShuffleMs = now + settings.shuffleMinMs + roll(settings.shuffleSpanMs)
        local ox, oy = tonumber(data.ProjectALifeInjuryOriginX), tonumber(data.ProjectALifeInjuryOriginY)
        if ox == nil then ox, oy = x, y end
        data.ProjectALifeInjuryOriginX, data.ProjectALifeInjuryOriginY = ox, oy
        local ux, uy
        local gx, gy = Injury.groupPull(shell, data, record, x, y, z, settings.crawlGroupTiles)
        if gx ~= nil and (gx - x) ^ 2 + (gy - y) ^ 2 > 16 then
            ux, uy = Rules.unit(gx - x, gy - y)
        else
            local angle = roll(8) * math.pi / 4
            ux, uy = math.cos(angle), math.sin(angle)
        end
        local nx, ny = x + ux * settings.shuffleTiles, y + uy * settings.shuffleTiles
        if (nx - ox) ^ 2 + (ny - oy) ^ 2 > settings.shuffleRadius ^ 2 then ux, uy = Rules.unit(ox - x, oy - y) end
        current = { ux = ux, uy = uy, left = settings.shuffleTiles }
        data.ProjectALifeInjuryShuffle = current
    end
    local step = math.min(settings.shuffleStep, current.left)
    local moved = Injury.nudge(shell, data, current.ux, current.uy, step, now)
    current.left = current.left - step
    if not moved or current.left <= 0.001 then data.ProjectALifeInjuryShuffle = nil end
    if moved then Injury.metrics.shuffled = Injury.metrics.shuffled + 1 end
    return moved
end

function Injury.drift(shell, data, now, settings)
    settings = settings or Rules.settings()
    if settings.crawl ~= true or data.ProjectALifeInjured ~= "down" then return false end
    local rescue = ProjectALife.InjuryRescue
    if rescue == nil or rescue.active[data.ProjectALifeUID] ~= nil then return false end
    if now < (tonumber(data.ProjectALifeInjuryFallUntilMs) or 0) then return false end
    local x, y, z = Injury.xyz(shell)
    if x == nil then return false end
    local record = Injury.recordOf(data)
    if record ~= nil then
        local kind, tx, ty = rescue.threatNear(record, x, y, z, now, settings.crawlThreatTiles)
        if kind ~= nil then
            data.ProjectALifeInjuryShuffle = nil
            return Injury.crawl(shell, data, now, settings, x, y, z, record, tx, ty)
        end
    end
    return Injury.shuffle(shell, data, now, settings, x, y, z, record)
end

function Injury.anchor(shell, data)
    pcall(Injury.spread, shell, data)
    local x, y = Injury.xyz(shell)
    if x == nil then return false end
    data.ProjectALifeInjuryAnchorX, data.ProjectALifeInjuryAnchorY = x, y
    return true
end

function Injury.pin(shell, data)
    Injury.moveFrame(shell, data, Injury.now())
    if data.ProjectALifeInjured ~= "down" then return false end
    local ax, ay = data.ProjectALifeInjuryAnchorX, data.ProjectALifeInjuryAnchorY
    if type(ax) ~= "number" or type(ay) ~= "number" then return false end
    local dx, dy = shell:getX() - ax, shell:getY() - ay
    local drift = dx * dx + dy * dy
    if drift < 0.0009 then return false end
    if drift > 4 then
        data.ProjectALifeInjuryAnchorX, data.ProjectALifeInjuryAnchorY = shell:getX(), shell:getY()
        return false
    end
    local fence = ProjectALife.AIFence
    if fence == nil or type(fence.moveBody) ~= "function" then return false end
    fence.moveBody(shell, ax, ay)
    Injury.metrics.pinned = Injury.metrics.pinned + 1
    return true
end

function Injury.pose(shell, data, now, first)
    if not Injury.drives(shell) then return false end
    local animations = ProjectALife.Animations
    if animations == nil or type(animations.apply) ~= "function" then return false end
    local want = "drag_lie"
    if first == true then
        want = "drag_fall"
        data.ProjectALifeInjuryFallUntilMs = now + 1000
        Injury.clearAnchor(data)
    elseif now < (tonumber(data.ProjectALifeInjuryFallUntilMs) or 0) then
        return true
    else
        if data.ProjectALifeInjuryAnchorX == nil then Injury.anchor(shell, data) end
        local writhe = tonumber(data.ProjectALifeInjuryWritheUntilMs)
        if writhe ~= nil and now < writhe then
            want = "drag_writhe"
        elseif now >= (tonumber(data.ProjectALifeInjuryNextWritheMs) or 0) then
            data.ProjectALifeInjuryWritheUntilMs = now + 2500 + roll(2500)
            data.ProjectALifeInjuryNextWritheMs = now + 9000 + roll(9000)
            want = "drag_writhe"
        end
    end
    if data.ProjectALifeInjuryClip == want and animations.current[shell] == want then return true end
    local ok, applied = pcall(animations.apply, shell, want)
    if ok and applied == true then
        data.ProjectALifeInjuryClip = want
        return true
    end
    return false
end

function Injury.enter(shell, data, now, source)
    if not Injury.drives(shell) then return false, "not_owner" end
    if not Injury.enabled() then return false, "disabled" end
    if data == nil or not Injury.alive(shell) then return false, "no_body" end
    if Health.invulnerable(shell, data) then return false, "invulnerable" end
    local state = data.ProjectALifeInjured
    if Rules.holds(state) then return false, "already" end
    local settings = Rules.settings()
    local current, maximum = Injury.healthOf(shell)
    if maximum <= 0 then return false, "no_health" end
    local target = maximum * settings.downHpPercent / 100
    if source == "debug" or current < target then Injury.setHealth(shell, target) end
    data.ProjectALifeInjured = "down"
    data.ProjectALifeInjurySinceMs = now
    data.ProjectALifeInjurySinceHours = Injury.hours()
    data.ProjectALifeInjuryAided = nil
    data.ProjectALifeInjuryStartFraction = nil
    data.ProjectALifeInjuryNextBarkMs = now + 2500 + roll(3000)
    data.ProjectALifeInjuryClip = nil
    data.ProjectALifeInjuryNextWritheMs = now + 6000 + roll(6000)
    data.ProjectALifeInjuryNextShuffleMs = now + 5000 + roll(5000)
    data.ProjectALifeInjuryShuffle, data.ProjectALifeInjuryCrawled = nil, nil
    data.ProjectALifeInjuryOriginX, data.ProjectALifeInjuryOriginY = nil, nil
    Injury.stopBleeding(shell, data)
    Injury.freeze(shell, data, now)
    Injury.pose(shell, data, now, true)
    Injury.persist(data)
    Injury.metrics.entered = Injury.metrics.entered + 1
    Injury.log("state uid=" .. tostring(data.ProjectALifeUID) .. " down source=" .. tostring(source)
        .. " hp=" .. tostring(math.floor(Injury.healthOf(shell) * 10) / 10))
    return true
end

function Injury.handDown(shell, data, now)
    if type(data) ~= "table" or type(data.ProjectALifeUID) ~= "string" then return false end
    if not Rules.flag("Injury_Enabled", true) or not Injury.multiplayerAllowed() then return false end
    if Health.invulnerable(shell, data) then return false end
    local record = Injury.recordOf(data)
    if record == nil then return false end
    local held = type(record.memory) == "table" and record.memory.injury or nil
    if type(held) == "table" and Rules.holds(held.s) then return true end
    if now < (tonumber(data.ProjectALifeInjuryDeclinedUntilMs) or 0) then return false end
    local settings = Rules.settings()
    if not Rules.autoEnters(settings.autoPercent, roll(100)) then
        data.ProjectALifeInjuryDeclinedUntilMs = now + 30000
        Injury.metrics.bleedOutsDeclined = Injury.metrics.bleedOutsDeclined + 1
        return false
    end
    if not Injury.writeMemory(data, { s = "down", h = Injury.hours(), n = 1 }) then return false end
    Health.holdOwner(shell, false)
    Injury.metrics.bleedOutsTaken = Injury.metrics.bleedOutsTaken + 1
    Injury.metrics.handedDown = Injury.metrics.handedDown + 1
    Injury.log("state uid=" .. tostring(data.ProjectALifeUID) .. " down source=server")
    return true
end

function Injury.interceptBleed(shell, data, now)
    if Injury.serverDelegates() then return Injury.handDown(shell, data, now) end
    if not Injury.drives(shell) then return false end
    if type(data) ~= "table" or not Injury.enabled() then return false end
    if Rules.holds(data.ProjectALifeInjured) then return true end
    if now < (tonumber(data.ProjectALifeInjuryDeclinedUntilMs) or 0) then
        return false
    end
    local settings = Rules.settings()
    if not Rules.autoEnters(settings.autoPercent, roll(100)) then
        data.ProjectALifeInjuryDeclinedUntilMs = now + 30000
        Injury.metrics.bleedOutsDeclined = Injury.metrics.bleedOutsDeclined + 1
        return false
    end
    local ok = Injury.enter(shell, data, now, "bleed")
    if ok then Injury.metrics.bleedOutsTaken = Injury.metrics.bleedOutsTaken + 1 end
    return ok == true
end

function Injury.clearHold(data)
    data.ProjectALifeInjuryHoldUntilMs = nil
    data.ProjectALifeInjuryRole = nil
    data.ProjectALifeDragUntilMs = nil
    data.ProjectALifeDownedUntilMs = nil
    data.ProjectALifeInjuryClip = nil
    data.ProjectALifeInjuryFallUntilMs = nil
    data.ProjectALifeInjuryWritheUntilMs = nil
    data.ProjectALifeInjuryShuffle, data.ProjectALifeInjuryCrawled = nil, nil
    data.ProjectALifeInjuryOriginX, data.ProjectALifeInjuryOriginY = nil, nil
    data.ProjectALifeInjuryNextShuffleMs = nil
    Injury.clearAnchor(data)
end

function Injury.onUnbind(uid)
    local rescue = ProjectALife.InjuryRescue
    if type(uid) == "string" and rescue ~= nil and type(rescue.dropUid) == "function" then
        return rescue.dropUid(uid, "unbound")
    end
    return 0
end

function Injury.onDeath(shell, data)
    if type(data) ~= "table" then data = Injury.dataOf(shell) end
    if type(data) ~= "table" then return false end
    local uid = data.ProjectALifeUID
    local rescue = ProjectALife.InjuryRescue
    if type(uid) == "string" and rescue ~= nil and type(rescue.dropUid) == "function" then
        pcall(rescue.dropUid, uid, "died")
    end
    if data.ProjectALifeInjured == nil and data.ProjectALifeInjuryHoldUntilMs == nil then return false end
    data.ProjectALifeInjured = nil
    data.ProjectALifeInjuryAided = nil
    data.ProjectALifeInjuryStartFraction, data.ProjectALifeInjuryLastFraction = nil, nil
    data.ProjectALifeInjurySinceHours, data.ProjectALifeInjurySinceMs = nil, nil
    data.ProjectALifeInjuryNextBarkMs, data.ProjectALifeInjuryNextWritheMs = nil, nil
    data.ProjectALifeHeldBump, data.ProjectALifeHeldAct = nil, nil
    Injury.clearHold(data)
    pcall(Injury.persist, data)
    Injury.metrics.deaths = Injury.metrics.deaths + 1
    Injury.log("state uid=" .. tostring(uid) .. " dead")
    return true
end

function Injury.standUp(shell, data, now)
    Injury.clearHold(data)
    if not Injury.drives(shell) then return false end
    local animations = ProjectALife.Animations
    if animations ~= nil and type(animations.apply) == "function" then
        pcall(animations.apply, shell, "get_up_back", true)
    end
    pcall(function() shell:setMoving(false) end)
    local decisions = ProjectALife.DecisionLoop
    local uid = data.ProjectALifeUID
    if decisions ~= nil and type(decisions.states) == "table" and type(uid) == "string" then
        decisions.states[uid] = { kind = "idle", intent = "injured_up", cooldownUntilMs = now + 1300 }
    end
end

function Injury.recover(shell, data, now, reason, fraction, aided)
    local state = data.ProjectALifeInjured
    local wasLying = Rules.holds(state)
    local current, maximum = Injury.healthOf(shell)
    if maximum > 0 and fraction ~= nil and current < maximum * fraction then
        Injury.setHealth(shell, maximum * fraction)
        current = maximum * fraction
    end
    data.ProjectALifeInjured = "recovering"
    data.ProjectALifeInjurySinceHours = Injury.hours()
    data.ProjectALifeInjuryStartFraction = Rules.fraction(current, maximum)
    data.ProjectALifeInjuryLastFraction = data.ProjectALifeInjuryStartFraction
    data.ProjectALifeInjuryAided = aided == true or data.ProjectALifeInjuryAided
    data.ProjectALifeWoundLeg = true
    if wasLying then Injury.standUp(shell, data, now) else Injury.clearHold(data) end
    Injury.persist(data)
    if reason == "timeout" then Injury.metrics.selfRecovered = Injury.metrics.selfRecovered + 1 end
    Injury.log("state uid=" .. tostring(data.ProjectALifeUID) .. " recovering reason=" .. tostring(reason))
    return true
end

function Injury.finish(shell, data, now, reason)
    local list = Health.injuriesOf(shell, data)
    data.ProjectALifeInjured = nil
    data.ProjectALifeInjuryAided = nil
    data.ProjectALifeInjuryStartFraction, data.ProjectALifeInjuryLastFraction = nil, nil
    data.ProjectALifeInjurySinceHours, data.ProjectALifeInjurySinceMs = nil, nil
    Injury.clearHold(data)
    if data.ProjectALifeWoundLeg == true then
        data.ProjectALifeWoundLeg = nil
        if list ~= nil then pcall(Health.applyInjuries, data, list, Injury.hours()) end
    end
    Injury.persist(data)
    Injury.metrics.recovered = Injury.metrics.recovered + 1
    Injury.log("state uid=" .. tostring(data.ProjectALifeUID) .. " none reason=" .. tostring(reason))
    return true
end

function Injury.release(shell, data, now, reason, fullHeal)
    local lying = Rules.holds(data.ProjectALifeInjured)
    local rescue = ProjectALife.InjuryRescue
    if rescue ~= nil and type(rescue.dropFor) == "function" then pcall(rescue.dropFor, data.ProjectALifeUID, reason) end
    data.ProjectALifeInjured = nil
    data.ProjectALifeInjuryAided = nil
    data.ProjectALifeInjuryStartFraction, data.ProjectALifeInjuryLastFraction = nil, nil
    data.ProjectALifeInjurySinceHours, data.ProjectALifeInjurySinceMs = nil, nil
    if lying then Injury.standUp(shell, data, now) else Injury.clearHold(data) end
    if fullHeal == true then
        local _, maximum = Injury.healthOf(shell)
        if maximum > 0 then Injury.setHealth(shell, maximum) end
        data.ProjectALifeWoundLeg = nil
        pcall(Health.heal, shell, data)
    end
    Injury.persist(data)
    Injury.metrics.released = Injury.metrics.released + 1
    Injury.log("state uid=" .. tostring(data.ProjectALifeUID) .. " none reason=" .. tostring(reason))
    return true
end

function Injury.observe(shell, data, now)
    if not Injury.drives(shell) then return false end
    if type(data.ProjectALifeUID) ~= "string" then return false end
    data.ProjectALifeInjuryChecked = true
    if not Injury.enabled() then return false end
    local record = Injury.recordOf(data)
    local stored = record ~= nil and type(record.memory) == "table" and record.memory.injury or nil
    if type(stored) ~= "table" then return false end
    local settings = Rules.settings()
    data.ProjectALifeInjurySinceHours = tonumber(stored.h) or Injury.hours()
    data.ProjectALifeInjuryStartFraction = tonumber(stored.f)
    data.ProjectALifeInjuryLastFraction = tonumber(stored.f)
    data.ProjectALifeInjuryAided = stored.a == 1 or nil
    if stored.s == "down" then
        data.ProjectALifeInjured = "down"
        data.ProjectALifeInjurySinceMs = now
        data.ProjectALifeInjuryNextBarkMs = now + 3000 + roll(3000)
        Injury.freeze(shell, data, now)
        Injury.pose(shell, data, now, true)
    elseif stored.s == "recovering" then
        data.ProjectALifeInjured = "recovering"
        data.ProjectALifeWoundLeg = true
    else
        return false
    end
    Injury.metrics.restored = Injury.metrics.restored + 1
    Injury.log("state uid=" .. tostring(data.ProjectALifeUID) .. " restored " .. tostring(stored.s))
    return settings ~= nil
end

function Injury.bark(shell, data, now)
    if now < (tonumber(data.ProjectALifeInjuryNextBarkMs) or 0) then return end
    local settings = Rules.settings()
    data.ProjectALifeInjuryNextBarkMs = now + settings.barkMinMs + roll(settings.barkSpanMs)
    local rows = Injury.playerRows()
    local x, y = Injury.xyz(shell)
    local near, distance
    if x ~= nil then near, distance = Rules.nearestPlayer(rows, x, y) end
    local event, player = "INJURED_DOWN", nil
    if near ~= nil and distance ~= nil and distance <= 12 then event, player = "INJURED_BEG", near.body end
    Injury.say(shell, data, event, player)
end

function Injury.tickRecovering(shell, data, now)
    local settings = Rules.settings()
    data.ProjectALifeWoundLeg = true
    local elapsed = Injury.hours() - (tonumber(data.ProjectALifeInjurySinceHours) or Injury.hours())
    local start = tonumber(data.ProjectALifeInjuryStartFraction) or 0.3
    local fraction, done = Rules.recovered(start, elapsed, settings.recoverHours)
    local last = tonumber(data.ProjectALifeInjuryLastFraction) or start
    local current, maximum = Injury.healthOf(shell)
    if fraction > last and maximum > 0 then
        Injury.setHealth(shell, math.min(maximum, current + (fraction - last) * maximum))
        data.ProjectALifeInjuryLastFraction = fraction
    end
    if done then return Injury.finish(shell, data, now, "healed") end
    return false
end

function Injury.tickLying(shell, data, now)
    local settings = Rules.settings()
    Injury.stamp(shell, data, now)
    local state = data.ProjectALifeInjured
    if state == "down" then
        Injury.pose(shell, data, now, false)
        Injury.bark(shell, data, now)
        local drifted, driftError = pcall(Injury.drift, shell, data, now, settings)
        if not drifted then
            Injury.metrics.faults = (Injury.metrics.faults or 0) + 1
            Injury.lastFault = tostring(driftError)
        end
        local elapsed = Injury.hours() - (tonumber(data.ProjectALifeInjurySinceHours) or Injury.hours())
        if elapsed >= settings.downHours then
            return Injury.recover(shell, data, now, "timeout", settings.reviveFraction, false)
        end
    end
    local rescue = ProjectALife.InjuryRescue
    if rescue ~= nil and type(rescue.step) == "function" then
        local ok, err = pcall(rescue.step, shell, data, now)
        if not ok then
            Injury.metrics.faults = (Injury.metrics.faults or 0) + 1
            Injury.lastFault = tostring(err)
            local plus = ProjectALife.BlackBoxPlus
            if plus ~= nil then pcall(plus.luaError, "injury", err, true, "rescue") end
        end
    end
    return false
end

function Injury.beat(shell, data, now)
    if not Injury.drives(shell) then return false end
    Injury.moveFrame(shell, data, now)
    local state = data.ProjectALifeInjured
    if state == nil then
        if data.ProjectALifeInjuryChecked == true then return false end
        if not Injury.alive(shell) then return false end
        return Injury.observe(shell, data, now)
    end
    if not Injury.alive(shell) then return Injury.onDeath(shell, data) end
    if not Injury.enabled() then return Injury.release(shell, data, now, "off", false) end
    local settings = Rules.settings()
    if now < (tonumber(data.ProjectALifeInjuryNextMs) or 0) then return false end
    data.ProjectALifeInjuryNextMs = now + settings.beatMs
    if state == "recovering" then return Injury.tickRecovering(shell, data, now) end
    return Injury.tickLying(shell, data, now)
end

function Injury.receiveState(shell, data, stored, now)
    if not Injury.drives(shell) then return false end
    if stored == false then return Injury.release(shell, data, now, "server", false) end
    if type(stored) ~= "table" or (stored.s ~= "down" and stored.s ~= "recovering") then return false end
    if stored.n == 1 and stored.s == "down" and not Rules.holds(data.ProjectALifeInjured) then
        data.ProjectALifeInjuryChecked = true
        return Injury.enter(shell, data, now, "server") == true
    end
    local wasLying = Rules.holds(data.ProjectALifeInjured)
    local state = { s = stored.s, h = tonumber(stored.h) or Injury.hours(),
        f = tonumber(stored.f), a = stored.a == 1 and 1 or nil }
    Injury.writeMemory(data, state)
    data.ProjectALifeInjured = nil
    data.ProjectALifeInjuryChecked = nil
    if not Injury.observe(shell, data, now) then return false end
    if state.s == "recovering" then
        Injury.clearHold(data)
        if wasLying then Injury.standUp(shell, data, now) end
    end
    return true
end

function Injury.reply(player, payload)
    if type(isServer) == "function" and isServer() == true then
        if type(sendServerCommand) == "function" then sendServerCommand(player, "ProjectALife", "injuryResult", payload) end
        return true
    end
    if type(ProjectALife.InjuryClientReceive) == "function" then
        ProjectALife.InjuryClientReceive(payload)
        return true
    end
    return false
end

function Injury.debugCommand(player, args)
    local result = Injury.debugRun(player, args)
    result.kind = "debug"
    pcall(Injury.reply, player, result)
    return result
end

function Injury.debugRun(player, args)
    local uid = type(args) == "table" and tostring(args.uid or "") or ""
    local action = type(args) == "table" and tostring(args.action or "") or ""
    if not Injury.singlePlayer() then return { ok = false, reason = "sp_only" } end
    if not Rules.flag("Injury_Enabled", true) then return { ok = false, reason = "option_off" } end
    local shell = uid ~= "" and Injury.shellOf(uid) or nil
    local data = Injury.dataOf(shell)
    if shell == nil or data == nil then return { ok = false, reason = "no_body" } end
    local now = nowMs()
    if action == "injure" then
        local ok, reason = Injury.enter(shell, data, now, "debug")
        if ok then Injury.metrics.debugMade = Injury.metrics.debugMade + 1 end
        return { ok = ok == true, reason = reason, uid = uid, action = action }
    end
    if action == "heal" then
        Injury.release(shell, data, now, "debug_heal", true)
        Injury.metrics.debugHealed = Injury.metrics.debugHealed + 1
        return { ok = true, uid = uid, action = action }
    end
    if action == "rescue" then
        local rescue = ProjectALife.InjuryRescue
        if rescue == nil or type(rescue.force) ~= "function" then return { ok = false, reason = "rescue_missing" } end
        local ok, reason = rescue.force(shell, data, now)
        if ok == true then Injury.metrics.debugRescues = Injury.metrics.debugRescues + 1 end
        Injury.log("debug rescue uid=" .. uid .. " ok=" .. tostring(ok == true) .. " reason=" .. tostring(reason))
        return { ok = ok == true, reason = reason, uid = uid, action = action }
    end
    return { ok = false, reason = "unknown_action" }
end

function Injury.qaLine()
    local m = Injury.metrics
    local rescue = ProjectALife.InjuryRescue
    local active = 0
    if rescue ~= nil and type(rescue.active) == "table" then
        for _ in pairs(rescue.active) do active = active + 1 end
    end
    return "[ALIFE-QA] Injury: enabled=" .. tostring(Injury.enabled()) .. " entered=" .. tostring(m.entered)
        .. " bleedTaken=" .. tostring(m.bleedOutsTaken) .. " bleedDeclined=" .. tostring(m.bleedOutsDeclined)
        .. " recovered=" .. tostring(m.recovered) .. " selfRecovered=" .. tostring(m.selfRecovered)
        .. " aided=" .. tostring(m.aided) .. " released=" .. tostring(m.released) .. " restored=" .. tostring(m.restored)
        .. " rescueActive=" .. tostring(active) .. " rescueStarted=" .. tostring(m.rescueStarted)
        .. " rescueDone=" .. tostring(m.rescueDone) .. " rescueAborted=" .. tostring(m.rescueAborted)
        .. " interrogations=" .. tostring(m.interrogations) .. " interrogationDeaths=" .. tostring(m.interrogationDeaths)
        .. " barks=" .. tostring(m.barks) .. " faults=" .. tostring(m.faults or 0)
        .. " deaths=" .. tostring(m.deaths) .. " pinned=" .. tostring(m.pinned) .. " spread=" .. tostring(m.spread)
        .. " debugRescues=" .. tostring(m.debugRescues)
        .. " crawled=" .. tostring(m.crawled) .. " shuffled=" .. tostring(m.shuffled)
        .. " crawlBlocked=" .. tostring(m.crawlBlocked) .. " handedDown=" .. tostring(m.handedDown)
        .. " mpAllowed=" .. tostring(Injury.multiplayerAllowed()) .. Injury.rescueQa()
        .. " speechRefusedDead=" .. tostring(Injury.speechCounter("speechRefusedDead"))
        .. " corpsesHushed=" .. tostring(Injury.speechCounter("corpsesHushed"))
end

function Injury.rescueQa()
    local rescue = ProjectALife.InjuryRescue
    local m = type(rescue) == "table" and rescue.metrics or nil
    if type(m) ~= "table" then return "" end
    return " rescueConsidered=" .. tostring(m.considered) .. " rescueNoTeam=" .. tostring(m.noTeam)
        .. " rescuePlayerNear=" .. tostring(m.playerNear) .. " rescueDanger=" .. tostring(m.danger)
        .. " rescueAllied=" .. tostring(m.allied) .. " rescueNoSight=" .. tostring(m.noSight)
        .. " rescueModuleOff=" .. tostring(m.moduleOff) .. " rescueDragged=" .. tostring(m.dragged)
        .. " rescueHealedInPlace=" .. tostring(m.healedInPlace) .. " rescueDragOff=" .. tostring(m.dragOff)
        .. " rescueLines=" .. tostring(m.lines)
end

function Injury.speechCounter(name)
    local speech = ProjectALife.Speech
    local metrics = type(speech) == "table" and speech.metrics or nil
    return type(metrics) == "table" and tonumber(metrics[name]) or 0
end

return Injury
