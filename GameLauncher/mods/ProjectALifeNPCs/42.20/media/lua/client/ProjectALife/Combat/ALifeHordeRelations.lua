require "ProjectALife/Shells/ALifeAIFence"
require "ProjectALife/Senses/ALifeSneakProfile"
require "ProjectALife/Senses/ALifeZombieRetarget"
require "ProjectALife/Compat/ALifeInterop"
require "ProjectALife/Shells/ALifeArmor"

ProjectALife = ProjectALife or {}

local Interop = ProjectALife.Interop
local BITE_BUMP = "ALifeGnawUpright"
local BITE_BUMP_LOW = "ALifeGnawDowned"
local BITE_CLAW = "ALifeClawUpright"

local function playBite(zombie, low, claw, typed)
    local ok = pcall(function()
        zombie:setBumpFall(false)
        zombie:setVariable("BumpFall", false)
        zombie:setBumpType(low and BITE_BUMP_LOW or (claw and BITE_CLAW or BITE_BUMP))
        if typed then
            zombie:setVariable("AttackType", claw and "scratch" or "bite")
            zombie:setVariable("AttackOutcome", "success")
            zombie:setVariable("AttackDidDamage", false)
        end
        zombie:setBumpDone(false)
        zombie:setVariable("BumpDone", false)
        zombie:setVariable("BumpAnimFinished", false)
        zombie:setVariable("ALifeBiteLanded", false)
        zombie:setVariable("ALifeBiteDone", false)
    end)
    return ok
end

local function writeBiteWindow(actor, durationMs)
    local data = actor:getModData()
    if type(data) == "table" then
        data.ProjectALifeBiteUntilMs = getTimestampMs() + durationMs
    end
end

local function markBiteWindow(actor, durationMs)
    pcall(writeBiteWindow, actor, durationMs)
end

local Horde = {

    metrics = {
        chases = 0,         
        contacts = 0,       
        bites = 0,          
        posed = 0,          
        damaged = 0,        
        reclaimed = 0,      
        switched = 0,       
        bumped = 0,         
        settled = 0,        
        farQuiet = 0,       
        blocked = 0,        
        bitesRefused = 0,   
        unstuck = 0,        
        remoteSkipped = 0,  
        drawn = 0,          
        sightRefused = 0,   
        sightRays = 0,      
        rayCapped = 0,
        rayPeak = 0,
        sightHeld = 0,
        meleeNoise = 0,
        biteWaits = {},     
        biteMisses = {},    
        wounds = {},
        infections = 0,
        lunges = 0,
        fed = 0,
        stunned = 0,
        bitesCut = 0,
        pathHeld = 0,
        pathBudget = 0,
        pathStalled = 0,
        pathLatencyCount = 0,
        pathLatencySumMs = 0,
        pathLatencyMaxMs = 0,
    },
    pathBucket = { tokens = 0 },
    bites = setmetatable({}, { __mode = "k" }),

    biteCount = 0,

    thinkIntervalMs = 200,
    timing = { thinkIntervalMs = 200, senseRetryMs = 1000, farChaseMs = 600, contactGraceMs = 400, actorCacheMs = 500 },
    tuning = { reactPercent = 500, attackAnims = true, scratchPercent = 35, dragDown = true, dragCount = 4, dragMs = 3000 },
    tuneAtMs = 0,
    dragging = {},
    settings = {

        noticeTiles = 20,
        giveUpTiles = 26,

        senseTiles = 4,
        senseRetryMs = 1000,
        senseRays = 3,
        rayFrameCap = 120,

        rememberMs = 3000,
        awareRemembered = 0.9,

        meleeNoticeTiles = 10,
        meleeHoldMs = 5000,

        gunfireNoticeTiles = 45,

        gunfireHoldMs = 15000,

        nearHalfTiles = 5,
        switchRatio = 1.15,
        preyHoldMs = 1200,

        awareSeen = 1.0,
        awareSensed = 0.5,
        awareNamed = 0.8,
        awareSpotted = 1.0,

        hitWeight = 3,
        hitWindowMs = 9000,
        preyWeight = 1.0,

        vehicleWeight = 0.5,

        floorBand = 0.5,

        contactRangeSquared = 2.25,

        lungeTiles = 3.5,

        overlapSquared = 0.01,

        biteConeCos = 0.82,

        biteStartWithinMs = 900,
        biteLandAfterMs = 520,
        biteReleaseAfterMs = 1500,
        biteWindowMs = 1600,

        damageCooldownMs = 4500,

        bitePoseGapMs = 1700,
        bitePoseSpreadMs = 900,

    maximumBiters = 8,

        maximumBiteFraction = 0.085,

        contactGraceMs = 400,
        flinchEveryMs = 2600,
        flinchWindowMs = 500,

        retaliateMs = 6000,

        holdLeaseMs = 5000,

        steerRadiusTiles = 40,

        farIdleMs = 1000,
        farChaseMs = 600,
        farChaseTiles = 10,

        repathMs = 900,
        repathMaxMs = 6400,
        pathWaitMs = 4000,
        pathGoalTiles = 2.5,
        pathPerSecond = 16,
        pathBurst = 8,

        feedEveryMs = 3000,
        feedTiles = 10,
        feedEaters = 3,
        corpseLimit = 16,
    },

    corpses = {},
    feedAtMs = 0,

    marks = {},
    markCache = { marks = {}, xs = {}, ys = {}, count = 0 },
    quietMemo = setmetatable({}, { __mode = "k" }),
    frameTiming = { spentMs = 0, calls = 0, frames = 0, busyFrames = 0, sumMs = 0, maxMs = 0, callsSum = 0,
        over4 = 0, over8 = 0, over16 = 0 },
    markLimit = 16,
    sightFactor = { [1] = 1.75, [2] = 1, [3] = 0.35, [4] = 1, [5] = 0.7 },
    sightApplied = 1,

    farBeats = {},

    lowerMemo = {},
    lowerMemoSize = 0,
    verdictMemo = {},
    verdictMemoSize = 0,
    memoLimit = 256,

    sprinting = {},
    sprintCount = 0,
    lunging = setmetatable({}, { __mode = "k" }),
    sprintLimit = 1024,

    senseAnswer = {},
    senseUntil = {},
    senseCount = 0,
    sightMemo = setmetatable({}, { __mode = "k" }),
    rayStamp = nil,
    rayCount = 0,

    preyIds = {},
    preyIdCount = 0,

    dealNear = {},
    dealMine = {},
    dealMarked = {},

    picks = {},
    look = {},
    choice = { kind = "none" },
}
ProjectALife.HordeRelations = Horde

local DOWN_STATE_PREFIXES = {
    "onground", "falldown", "knockeddown", "getup", "getdown",
    "staggerback-knockeddown", "hitreaction-onfloor",
}

function Horde.isDownState(state)
    if type(state) ~= "string" then return false end
    for index = 1, #DOWN_STATE_PREFIXES do
        local prefix = DOWN_STATE_PREFIXES[index]
        if string.sub(state, 1, #prefix) == prefix then return true end
    end
    return false
end

local function actionState(character)

    if character == nil or character.getActionStateName == nil then return "" end
    local ok, state = pcall(character.getActionStateName, character)
    if not ok then return "" end
    if state ~= nil then
        local known = Horde.lowerMemo[state]
        if known ~= nil then return known end
    end

    local lowered = string.lower(tostring(state or ""))
    if state ~= nil then Horde.rememberLower(state, lowered) end
    return lowered
end

function Horde.rememberLower(state, lowered)
    if Horde.lowerMemoSize >= (Horde.memoLimit or 256) then
        Horde.lowerMemo, Horde.lowerMemoSize = {}, 0
    end
    Horde.lowerMemo[state] = lowered
    Horde.lowerMemoSize = Horde.lowerMemoSize + 1
end

function Horde.protectsNativeState(state)
    return string.sub(state, 1, 11) == "hitreaction"
        or string.sub(state, 1, 11) == "staggerback"
        or string.sub(state, 1, 5) == "climb"
        or string.find(state, "ragdoll", 1, true) ~= nil
end

function Horde.stateVerdict(state)
    if state ~= nil then
        local known = Horde.verdictMemo[state]
        if known ~= nil then return known or nil end
    end
    local verdict = Horde.stateVerdictOf(state)
    if state ~= nil then
        if Horde.verdictMemoSize >= (Horde.memoLimit or 256) then
            Horde.verdictMemo, Horde.verdictMemoSize = {}, 0
        end
        Horde.verdictMemo[state] = verdict or false
        Horde.verdictMemoSize = Horde.verdictMemoSize + 1
    end
    return verdict
end

function Horde.stateVerdictOf(state)
    if Horde.protectsNativeState(state) then return "wait" end
    if Horde.isDownState(state) then return "down" end
    if state == "bumped" or state == "turnalerted" then return "posing" end
    return nil
end

function Horde.markedOurs(body)
    if body == nil or body.getModData == nil then return false end

    if body.hasModData ~= nil and body:hasModData() == false then return false end
    local data = body:getModData()
    return type(data) == "table"
        and (data.ProjectALifeOwned == true or data.ProjectALifeActor == true)
end

function Horde.dataOf(body)
    if body == nil or body.getModData == nil then return nil end
    if body.hasModData ~= nil and body:hasModData() == false then return nil end
    local ok, data = pcall(body.getModData, body)
    if not ok or type(data) ~= "table" then return nil end
    return data
end

local function isOwnedActor(character)
    if not Horde.markedOurs(character) then return false end

    if type(character.isReanimatedForGrappleOnly) ~= "function" then return true end
    local grappleOk, grappled = pcall(character.isReanimatedForGrappleOnly, character)
    return not (grappleOk and grappled == true)
end

local function isAlive(character)
    if character == nil then return false end
    if character.isDead ~= nil then return character:isDead() ~= true end
    if character.isAlive ~= nil then return character:isAlive() == true end
    return false
end

function Horde.pairPosition(a, b)
    return a:getX(), a:getY(), a:getZ(), b:getX(), b:getY(), b:getZ()
end

local function distanceSquared(a, b)
    local ok, ax, ay, az, bx, by, bz = pcall(Horde.pairPosition, a, b)
    if not ok then return math.huge, math.huge end
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy, math.abs(az - bz)
end

Horde.frameNowMs = nil
Horde.roster = nil
Horde.rosterListed = nil
Horde.rosterAtMs = nil

Horde.beatPhase = 0

function Horde.sandboxNumber(key, default, low, high)
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    local value = type(vars) == "table" and tonumber(vars[key]) or nil
    if value == nil then return default end
    return math.max(low, math.min(high, value))
end

function Horde.sandboxFlag(key, default)
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    local value = nil
    if type(vars) == "table" then value = vars[key] end
    if value == nil then return default end
    return value == true
end

function Horde.sightScale()
    local lore = type(SandboxVars) == "table" and SandboxVars.ZombieLore or nil
    local value = type(lore) == "table" and tonumber(lore.Sight) or nil
    return Horde.sightFactor[value or 2] or 1
end

function Horde.applyTuning(now)
    Horde.tuneAtMs = now + 3000
    local tuning, timing, settings = Horde.tuning, Horde.timing, Horde.settings
    tuning.reactPercent = Horde.sandboxNumber("Zombies_ReactSpeed", 500, 100, 1000)
    tuning.attackAnims = Horde.sandboxFlag("Zombies_AttackAnims", true)
    tuning.scratchPercent = Horde.sandboxNumber("Zombies_ScratchPercent", 35, 0, 100)
    tuning.dragDown = Horde.sandboxFlag("Zombies_DragDown", true)
    tuning.dragCount = math.floor(Horde.sandboxNumber("Zombies_DragDownCount", 4, 2, 8))
    tuning.dragMs = math.floor(Horde.sandboxNumber("Zombies_DragDownTenths", 30, 5, 60) * 100)
    local scale = tuning.reactPercent / 100
    Horde.thinkIntervalMs = math.max(40, math.floor(timing.thinkIntervalMs / scale))
    settings.senseRetryMs = math.max(150, math.floor(timing.senseRetryMs / scale))
    settings.farChaseMs = math.max(120, math.floor(timing.farChaseMs / scale))
    settings.contactGraceMs = timing.contactGraceMs
    local sight = Horde.sightScale()
    if sight ~= Horde.sightApplied then
        settings.noticeTiles = settings.noticeTiles / Horde.sightApplied * sight
        settings.giveUpTiles = settings.giveUpTiles / Horde.sightApplied * sight
        Horde.sightApplied = sight
    end
    Horde.actorCacheMs = math.max(250, math.floor(timing.actorCacheMs / math.min(scale, 2)))
end

Horde.dragVoiceMs = 1800

function Horde.dragVoice(actor, drag)
    local policy = ProjectALife.AudioPolicy
    if policy == nil or type(policy.nearSound) ~= "function" then return end
    local female = false
    pcall(function() female = actor:isFemale() == true end)
    pcall(policy.nearSound, actor, female and "FemaleBeingEatenDeath" or "MaleBeingEatenDeath",
        { key = drag, gapMs = 5000, maxMs = Horde.dragVoiceMs })
end

function Horde.checkDrag(actor, zombie, now)
    local tuning = Horde.tuning
    if tuning.dragDown ~= true or Horde.dragging[actor] ~= nil or not isAlive(actor) then return false end
    if Horde.mouthsOn(actor) < tuning.dragCount then return false end
    local health = ProjectALife.Health
    if health ~= nil and type(health.invulnerable) == "function" then
        local ok, immune = pcall(health.invulnerable, actor)
        if ok and immune == true then return false end
    end
    local fallAt = now + math.min(900, math.floor(tuning.dragMs * 0.3))
    local drag = { killAtMs = now + tuning.dragMs, startedAtMs = now, zombie = zombie, fallAtMs = fallAt,
        lieAtMs = fallAt + math.min(950, math.floor(tuning.dragMs * 0.3)) }
    Horde.dragging[actor] = drag
    markBiteWindow(actor, tuning.dragMs + 600)
    pcall(function() actor:setZombiesDontAttack(true) end)
    pcall(function() actor:getModData().ProjectALifeDragUntilMs = now + tuning.dragMs + 800 end)
    Horde.dragStep(actor, drag, now)
    Horde.dragVoice(actor, drag)
    Horde.metrics.dragged = (Horde.metrics.dragged or 0) + 1
    return true
end

function Horde.dragStep(actor, drag, now)
    if drag.onFloor == true then return false end
    local want = "drag_grab"
    drag.lying = now >= drag.lieAtMs
    if drag.shown == want then return true end
    local data = Horde.dataOf(actor)
    if data ~= nil then
        data.ProjectALifeDragDurationMs = drag.killAtMs - (drag.startedAtMs or now)
    end
    local animations = ProjectALife.Animations
    local applied = false
    if animations ~= nil and type(animations.apply) == "function" then
        local ok, result = pcall(animations.apply, actor, want)
        applied = ok and result == true
    end
    if applied then
        drag.shown = want
        return true
    end
    if drag.shown == nil then
        drag.onFloor = true
        pcall(function() actor:setOnFloor(true) end)
    end
    return false
end

function Horde.clearDrag(actor)
    local data = Horde.dataOf(actor)
    if data ~= nil then
        data.ProjectALifeDragUntilMs, data.ProjectALifeDragDurationMs = nil, nil
        if data.ProjectALifeHeldBump == "ALifeDragGrab" then data.ProjectALifeHeldBump = nil end
    end
    local animations = ProjectALife.Animations
    if animations ~= nil and animations.current[actor] == "drag_grab" then
        if isAlive(actor) then animations.clear(actor)
        else animations.current[actor], animations.active[actor] = nil, nil end
    end
end

function Horde.finishDrag(now)
    for actor, drag in pairs(Horde.dragging) do
        if not isAlive(actor) then
            Horde.dragging[actor] = nil
            Horde.clearDrag(actor)
        elseif now < drag.killAtMs then
            Horde.dragStep(actor, drag, now)
        else
            Horde.dragging[actor] = nil
            pcall(function()
                local simulation = ProjectALife.ShellSimulation
                if simulation ~= nil and type(simulation.setHealth) == "function" then simulation.setHealth(actor, 0)
                else actor:setHealth(0) end
            end)
            pcall(function() actor:Kill(drag.zombie) end)
            Horde.clearDrag(actor)
            Horde.reportDeath(actor)
            Horde.metrics.dragKills = (Horde.metrics.dragKills or 0) + 1
        end
    end
end

Horde.guardLimit = 20
Horde.guardFailures = {}
Horde.guardDisabled = {}

function Horde.guard(name, callback)
    if type(callback) ~= "function" then return function() end end
    return function(...)
        if Horde.guardDisabled[name] == true then return end
        local ok, err = pcall(callback, ...)
        if ok then
            if Horde.guardFailures[name] ~= nil then Horde.guardFailures[name] = nil end
            return
        end
        local plus = ProjectALife.BlackBoxPlus
        if plus ~= nil then pcall(plus.luaError, "horde", err, true, name) end
        local count = (Horde.guardFailures[name] or 0) + 1
        Horde.guardFailures[name] = count
        Horde.metrics.guardErrors = (Horde.metrics.guardErrors or 0) + 1
        if count >= Horde.guardLimit then
            Horde.guardDisabled[name] = true
            Horde.metrics.guardDisabled = (Horde.metrics.guardDisabled or 0) + 1
            print("[ALIFE-HORDE] handler " .. tostring(name) .. " disabled after " .. count
                .. " consecutive errors: " .. tostring(err))
        end
    end
end

function Horde.stampFrame()
    if type(getTimestampMs) ~= "function" then return end
    local now = getTimestampMs()
    Horde.frameNowMs = now
    if now >= Horde.tuneAtMs and type(Horde.applyTuning) == "function" then Horde.applyTuning(now) end
    if type(Horde.finishDrag) == "function" then
        for _ in pairs(Horde.dragging) do
            Horde.finishDrag(now)
            break
        end
    end
    if #Horde.corpses > 0 and type(Horde.feedBeat) == "function" then Horde.feedBeat() end
end

function Horde.rosterRow(player)
    if player == nil or player.getX == nil or player.getY == nil then return nil end
    local row = { x = player:getX(), y = player:getY(), body = player }
    if player.getOnlineID ~= nil then row.id = tonumber(player:getOnlineID()) end
    if player.isLocalPlayer ~= nil then row.mine = player:isLocalPlayer() == true end
    row.seated = Horde.seated(player)
    if player.getZ ~= nil and player.isInvisible ~= nil and player.isGhostMode ~= nil then
        row.z = player:getZ()
        row.visible = isAlive(player) and player:isInvisible() ~= true
            and player:isGhostMode() ~= true
    end
    return row
end

function Horde.gatherPlayers(players, roster)
    local listed = tonumber(players:size()) or 0
    for index = 0, listed - 1 do
        local row = Horde.rosterRow(players:get(index))
        if row ~= nil then roster[#roster + 1] = row end
    end
    return listed
end

function Horde.sweepPlayers()
    local roster, listed = {}, 0
    local okList, players = pcall(getOnlinePlayers)
    if okList and players ~= nil and players.size ~= nil and players.get ~= nil then
        local okScan, count = pcall(Horde.gatherPlayers, players, roster)
        listed = okScan and (tonumber(count) or 0) or #roster
    end
    if listed == 0 then
        local okLocal, player = pcall(getPlayer)
        if okLocal then
            local okRow, row = pcall(Horde.rosterRow, player)
            if okRow and row ~= nil then roster[#roster + 1] = row end
        end
    end
    return roster, listed
end

function Horde.frameRoster()
    local stamp = Horde.frameNowMs
    if stamp == nil then return nil end
    if Horde.roster ~= nil and Horde.rosterAtMs == stamp then
        return Horde.roster, Horde.rosterListed
    end
    local roster, listed = Horde.sweepPlayers()
    Horde.roster, Horde.rosterListed, Horde.rosterAtMs = roster, listed, stamp
    return roster, listed
end

function Horde.offerLivePlayer(look, player)
    if player == nil then return end
    Horde.visit(look, player)
    if not isAlive(player) then return end
    if player.isInvisible == nil or player.isGhostMode == nil then return end
    if player:isInvisible() == true or player:isGhostMode() == true then return end
    local x, y, z = Horde.positionOf(player)
    Horde.offer(look, player, "player", x, y, z, Horde.seated(player))
end

function Horde.seated(player)
    if player == nil or player.getVehicle == nil then return false end
    return player:getVehicle() ~= nil
end

function Horde.offerListed(look, players)
    local listed = tonumber(players:size()) or 0
    for index = 0, listed - 1 do
        Horde.offerLivePlayer(look, players:get(index))
    end
    return listed
end

function Horde.offerPlayers(look)
    local roster = Horde.frameRoster()
    if roster ~= nil then
        for index = 1, #roster do
            local man = roster[index]
            if man.body ~= nil then
                Horde.visit(look, man.body)
                if man.visible == true then
                    Horde.offer(look, man.body, "player", man.x, man.y, man.z, man.seated)
                end
            end
        end
        return
    end
    local listed = 0
    if type(getOnlinePlayers) == "function" then
        local okList, players = pcall(getOnlinePlayers)
        if okList and players ~= nil and players.size ~= nil and players.get ~= nil then
            local okScan, count = pcall(Horde.offerListed, look, players)
            if okScan then listed = tonumber(count) or 0 end
        end
    end
    if listed == 0 and type(getPlayer) == "function" then
        local okLocal, player = pcall(getPlayer)
        if okLocal and player ~= nil then pcall(Horde.offerLivePlayer, look, player) end
    end
end

local actorCache, actorCacheAtMs = {}, 0

local chaseMemory = setmetatable({}, { __mode = "k" })

local nextThinkAt = setmetatable({}, { __mode = "k" })

local function refreshActorCache()

    local now = Horde.frameNowMs or getTimestampMs()
    if now < actorCacheAtMs then return end
    actorCacheAtMs = now + (Horde.actorCacheMs or 500)
    local previous = actorCache
    actorCache = {}

    Horde.preyAtMs = nil
    local cellOk, cell = pcall(getCell)
    if not cellOk or cell == nil or cell.getZombieList == nil then return end
    local listOk, zombies = pcall(cell.getZombieList, cell)
    if not listOk or zombies == nil or zombies.size == nil then return end
    local sizeOk, count = pcall(zombies.size, zombies)
    if not sizeOk then return end
    for index = 0, count - 1 do
        local candidate = zombies:get(index)

        if candidate ~= nil and isOwnedActor(candidate) and isAlive(candidate)
                and candidate:getCurrentSquare() ~= nil then
            actorCache[#actorCache + 1] = candidate
        end
    end
    if Horde.rosterChanged(previous, actorCache) then Horde.recallAllFar(now) end
end

function Horde.rosterChanged(previous, current)
    if #previous ~= #current then return true end
    for index = 1, #current do
        if previous[index] ~= current[index] then return true end
    end
    return false
end

function Horde.idleBeat(zombie)
    if #actorCache > 0 or chaseMemory[zombie] ~= nil then return false end

    if Horde.sprinting[zombie] ~= nil then return false end
    if zombie == nil or zombie.getModData == nil then return true end
    if zombie.hasModData ~= nil and zombie:hasModData() == false then return true end
    local data = zombie:getModData()
    return type(data) ~= "table" or (data.ALifeHold == nil and data.ALifeChasePathX == nil)
end

function Horde.positionOf(body)
    if body == nil or body.getX == nil or body.getY == nil or body.getZ == nil then return nil end
    return body:getX(), body:getY(), body:getZ()
end

Horde.preyList = nil
Horde.preyAtMs = nil

function Horde.preyRows(cache)
    local stamp = Horde.frameNowMs
    local rows = Horde.preyList
    if rows ~= nil and stamp ~= nil and Horde.preyAtMs == stamp then return rows end
    if rows == nil then rows = {}; Horde.preyList = rows end

    local kept = 0
    for index = 1, #cache do
        local candidate = cache[index]
        local cx, cy, cz = Horde.positionOf(candidate)
        if cx ~= nil then
            kept = kept + 1
            local row = rows[kept]
            if row == nil then row = {}; rows[kept] = row end
            row.body, row.x, row.y, row.z = candidate, cx, cy, cz
            row.live = isAlive(candidate) and candidate:getCurrentSquare() ~= nil
        end
    end
    for index = #rows, kept + 1, -1 do rows[index] = nil end
    Horde.preyAtMs = stamp
    return rows
end

local function nearestActor(zombie)
    local settings = Horde.settings
    local best, bestDistance = nil, settings.noticeTiles * settings.noticeTiles
    local zx, zy, zz = Horde.positionOf(zombie)
    if zx == nil then return nil, nil end
    local rows = Horde.preyRows(actorCache)

    local nearest = math.huge
    for index = 1, #rows do
        local row = rows[index]
        local candidate = row.body
        if candidate ~= zombie then
            local dx, dy = zx - row.x, zy - row.y
            local flat = dx * dx + dy * dy
            if flat < nearest then nearest = flat end
            if math.abs(zz - row.z) < settings.floorBand and flat < bestDistance
                    and row.live then
                best, bestDistance = candidate, flat
            end
        end
    end

    if best == nil then return nil, nil, nearest end
    return best, bestDistance, nearest
end

function Horde.inSight(x0, y0, z0, x1, y1, z1)
    if LosUtil == nil or type(LosUtil.lineClear) ~= "function" or type(getCell) ~= "function" then
        return nil
    end
    local okCell, cell = pcall(getCell)
    if not okCell or cell == nil then return nil end
    local ok, result = pcall(LosUtil.lineClear, cell, math.floor(x0), math.floor(y0), math.floor(z0),
        math.floor(x1), math.floor(y1), math.floor(z1), false)
    if not ok or result == nil then return nil end
    Horde.metrics.sightRays = (Horde.metrics.sightRays or 0) + 1
    local outcomes = LosUtil.TestResults
    if outcomes ~= nil and outcomes.Blocked ~= nil and type(result) ~= "string" then
        return result ~= outcomes.Blocked and result ~= outcomes.ClearThroughClosedDoor
    end
    local name = tostring(result)
    return name ~= "Blocked" and name ~= "ClearThroughClosedDoor"
end

function Horde.noteSense(zombie, answer, untilMs)
    if Horde.senseUntil[zombie] == nil then
        if Horde.senseCount >= Horde.sprintLimit then
            Horde.senseAnswer, Horde.senseUntil, Horde.senseCount = {}, {}, 0
        end
        Horde.senseCount = Horde.senseCount + 1
    end
    Horde.senseAnswer[zombie] = answer
    Horde.senseUntil[zombie] = untilMs
end

function Horde.present(body)
    if body == nil or not isAlive(body) then return false end
    return body.getCurrentSquare ~= nil and body:getCurrentSquare() ~= nil
end

function Horde.visit(look, body)
    if body == look.prey then look.preyVisited = true end
    if body == look.hitActor then look.hitVisited = true end
    if body == look.claimPlayer then look.claimVisited = true end
    if body == look.target then look.targetVisited = true end
    if body == look.shooter then look.shooterVisited = true end
end

function Horde.openLook(look, zombie, zx, zy, zz, now, memory, target)
    local settings = Horde.settings
    look.zombie, look.zx, look.zy, look.zz, look.now = zombie, zx, zy, zz, now
    look.count, look.actors, look.rays, look.lastSeen = 0, 0, 0, nil
    look.rayBudget = tonumber(settings.senseRays) or 3
    look.halfSquared = settings.nearHalfTiles * settings.nearHalfTiles
    look.preyRow, look.freshHit, look.target = nil, false, target
    look.preyVisited, look.hitVisited, look.claimVisited = false, false, false
    look.targetVisited, look.shooterVisited = false, false

    local claim = Horde.playerClaims[zombie]
    if claim ~= nil and (now >= claim.untilMs or not Horde.present(claim.player)) then
        Horde.playerClaims[zombie] = nil
        claim = nil
    end
    look.claimPlayer = nil
    if claim ~= nil then look.claimPlayer = claim.player end
    local prey, kind, drawn, sinceMs, hitActor = nil, nil, false, now, nil
    if memory ~= nil then
        prey, kind = memory.prey, memory.kind
        sinceMs = tonumber(memory.sinceMs) or now
        drawn = memory.drawnUntilMs ~= nil and memory.drawnUntilMs > now
        if memory.provoked ~= nil and memory.provokedUntilMs ~= nil and memory.provokedUntilMs > now then
            hitActor = memory.provoked
        end
    end

    if kind == "player" and prey ~= target and prey ~= look.claimPlayer then prey = nil end
    look.prey, look.preyKind, look.drawn, look.sinceMs, look.hitActor = prey, kind, drawn, sinceMs, hitActor
    look.preyBumped = memory ~= nil and memory.bumped == true
    local reach = settings.giveUpTiles
    if drawn and settings.gunfireNoticeTiles > reach then reach = settings.gunfireNoticeTiles end
    look.preyReachSquared = reach * reach

    local mark = Horde.markFor(now, zx, zy)
    look.shooter, look.markSquared, look.markUntilMs, look.markHoldMs = nil, 0, nil, nil
    look.markRow, look.memory, look.drawVerdict = mark, memory, "draw"
    if mark ~= nil then
        look.shooter, look.markSquared, look.markUntilMs = mark.shooter, mark.radiusSquared, mark.untilMs
        look.markHoldMs = mark.holdMs
    end

    look.canLook = LosUtil ~= nil and type(LosUtil.lineClear) == "function" and type(getCell) == "function"
    local seen = nil
    if now < (Horde.senseUntil[zombie] or 0) then
        seen = Horde.senseAnswer[zombie]
        if seen ~= false and not Horde.present(seen) then seen = nil end
    end
    look.seen = seen
    look.memo = Horde.sightMemoFor(zombie, now)
    if mark ~= nil then look.drawVerdict = Horde.drawVerdictFor(look, memory, now) end
end

function Horde.holdsPrey(look, memory, now)
    if look.target ~= nil or look.claimPlayer ~= nil then return true end
    local prey = look.prey
    if prey == nil or look.preyKind ~= "actor" then return false end
    local rows, found = Horde.preyList, nil
    if rows == nil then return false end
    for index = 1, #rows do
        if rows[index].body == prey then found = rows[index] break end
    end
    if found == nil or not found.live then return false end
    local dx, dy = look.zx - found.x, look.zy - found.y
    if dx * dx + dy * dy >= look.preyReachSquared then return false end
    if not look.drawn then return true end
    local memo = look.memo
    local seen = memo ~= nil and memo.seen ~= nil and memo.seen[prey] or nil
    local policy = ProjectALife.ZombieRetarget
    local keep = policy ~= nil and policy.settings.keepSeenMs or 4000
    return seen ~= nil and now - seen < keep
end

function Horde.drawVerdictFor(look, memory, now)
    local policy = ProjectALife.ZombieRetarget
    if policy == nil then return "draw" end
    local prey = memory ~= nil and memory.prey or nil
    if prey == nil then
        if look.target == nil and look.claimPlayer == nil then return "draw" end
        return "kept"
    end
    return policy.drawVerdict(memory, Horde.holdsPrey(look, memory, now), now)
end

function Horde.mayDraw(look)
    local policy = ProjectALife.ZombieRetarget
    if policy == nil then return true end
    local verdict = look.drawVerdict
    if verdict ~= nil and verdict ~= "draw" then
        policy.noteSkip(look.memory, verdict, look.markUntilMs)
        return false
    end
    if not policy.capOpen(look.markRow) then
        policy.noteCapped(look.memory, look.markRow)
        return false
    end
    return true
end

function Horde.markUsable(mark, now)
    return mark ~= nil and now < (tonumber(mark.untilMs) or 0) and isAlive(mark.shooter)
        and isOwnedActor(mark.shooter) and mark.shooter:getCurrentSquare() ~= nil
end

function Horde.markRows(now)
    local stamp = Horde.frameNowMs
    local cache = Horde.markCache
    if stamp ~= nil and cache.stamp == stamp and cache.now == now
            and cache.list == Horde.marks and cache.latest == Horde.gunfire then
        return cache
    end
    local marks, kept = Horde.marks, 0
    local rows, xs, ys = cache.marks, cache.xs, cache.ys
    for index = 1, #marks do
        local mark = marks[index]
        if Horde.markUsable(mark, now) then
            local sx, sy = Horde.positionOf(mark.shooter)
            if sx ~= nil then
                kept = kept + 1
                rows[kept], xs[kept], ys[kept] = mark, sx, sy
            end
        end
    end
    for index = #rows, kept + 1, -1 do rows[index], xs[index], ys[index] = nil, nil, nil end
    cache.count = kept
    cache.latestUsable = Horde.markUsable(Horde.gunfire, now)
    cache.stamp, cache.now, cache.list, cache.latest = stamp, now, Horde.marks, Horde.gunfire
    return cache
end

function Horde.markFor(now, zx, zy)
    local cache = Horde.markRows(now)
    local rows, xs, ys = cache.marks, cache.xs, cache.ys
    local best, bestFlat = nil, nil
    for index = 1, cache.count do
        local mark = rows[index]
        local flat = (zx - xs[index]) * (zx - xs[index]) + (zy - ys[index]) * (zy - ys[index])
        if flat < mark.radiusSquared and (bestFlat == nil or flat < bestFlat) then
            best, bestFlat = mark, flat
        end
    end
    if best ~= nil then return best end
    if cache.latestUsable then return Horde.gunfire end
    return nil
end

function Horde.quietScales(quiet, body)
    local stamp = Horde.frameNowMs
    if stamp == nil then return quiet.noticeScale(body), quiet.senseScale(body) end
    local row = Horde.quietMemo[body]
    if row == nil then
        row = {}
        Horde.quietMemo[body] = row
    end
    if row.stamp ~= stamp then
        row.stamp = stamp
        row.hush, row.hear = quiet.noticeScale(body), quiet.senseScale(body)
    end
    return row.hush, row.hear
end

function Horde.markLive(now)
    local marks = Horde.marks
    for index = 1, #marks do
        if now < (tonumber(marks[index].untilMs) or 0) then return true end
    end
    local latest = Horde.gunfire
    return latest ~= nil and now < (tonumber(latest.untilMs) or 0)
end

function Horde.sightMemoFor(zombie, now)
    local memo = Horde.sightMemo[zombie]
    if memo == nil then
        memo = { untilMs = 0, answers = setmetatable({}, { __mode = "k" }), seen = setmetatable({}, { __mode = "k" }) }
        Horde.sightMemo[zombie] = memo
    end
    if now >= memo.untilMs or now < memo.untilMs - 5000 then
        memo.answers = setmetatable({}, { __mode = "k" })
        memo.untilMs = now + (tonumber(Horde.settings.senseRetryMs) or 1000)
    end
    return memo
end

function Horde.offer(look, body, kind, x, y, z, seated)
    if body == nil or x == nil or body == look.zombie then return nil end
    local settings = Horde.settings
    if math.abs(look.zz - z) >= settings.floorBand then return nil end
    local dx, dy = look.zx - x, look.zy - y
    local flat = dx * dx + dy * dy
    local isPrey = body == look.prey
    local hit = body == look.hitActor or body == look.claimPlayer
    local spotted = body == look.target
    local named = body == look.shooter and flat < look.markSquared
    if named and body ~= look.prey and not Horde.mayDraw(look) then named = false end
    local giveUp = settings.giveUpTiles * settings.giveUpTiles
    local notice = settings.noticeTiles * settings.noticeTiles
    if flat >= notice and not isPrey and not hit and not spotted and not named then return nil end
    local quiet = kind == "actor" and ProjectALife.SneakProfile or nil
    local hush, hear = 1, 1
    if quiet ~= nil then
        hush, hear = Horde.quietScales(quiet, body)
        notice = notice * hush * hush
    end
    if not ((isPrey and flat < look.preyReachSquared) or ((hit or spotted) and flat < giveUp)
            or named or flat < notice) then
        return nil
    end

    if kind == "actor" then look.actors = look.actors + 1 end

    local aware, source = nil, "sight"
    if spotted then aware, source = settings.awareSpotted, "spotted"
    elseif hit then aware, source = settings.awareSeen, "hit"
    elseif isPrey and not look.drawn then aware, source = settings.awareSeen, "prey"
    elseif named then
        source = "named"
        if flat >= notice then aware = settings.awareNamed end
    elseif isPrey then aware, source = settings.awareNamed, "drawn" end
    local sense = settings.senseTiles * hear
    local lo = 0
    if flat <= sense * sense then lo = settings.awareSensed end
    if source == "named" and lo < settings.awareNamed then lo = settings.awareNamed end
    local rem = 0
    local memo = look.memo
    if memo ~= nil and memo.seen ~= nil then
        local stamp = memo.seen[body]
        if stamp ~= nil and look.now - stamp < settings.rememberMs then rem = settings.awareRemembered end
    end
    if rem < lo then rem = lo end
    if aware == nil then
        local known = nil
        if look.memo ~= nil then known = look.memo.answers[body] end
        if not look.canLook or body == look.seen or known == true then
            aware, source = settings.awareSeen, "sight"
        elseif known == false then
            aware = rem
        end
    end
    if aware ~= nil and aware <= 0 then return nil end
    local weight = 1
    if hit then weight = weight * settings.hitWeight end
    if isPrey then weight = weight * settings.preyWeight end
    if seated == true then weight = weight * settings.vehicleWeight end
    local count = look.count + 1
    local row = Horde.picks[count]
    if row == nil then
        row = {}
        Horde.picks[count] = row
    end
    look.count = count
    row.body, row.kind, row.x, row.y, row.z, row.flat = body, kind, x, y, z, flat
    row.prey, row.hit, row.source, row.lo, row.out = isPrey, hit, source, lo, false
    row.rem = rem
    row.seated = seated == true
    row.near = 1 / (1 + flat / look.halfSquared)
    row.weight = weight
    if aware ~= nil then
        row.resolved, row.aware, row.score = true, aware, row.near * aware * weight
    else
        row.resolved, row.aware, row.score = false, nil, nil
    end
    if isPrey then look.preyRow = row end
    if hit and not isPrey then look.freshHit = true end
    return row
end

function Horde.offerTied(look, body, kind)
    Horde.visit(look, body)
    if not Horde.present(body) then return end
    if kind == "actor" and not isOwnedActor(body) then return end
    local seated = false
    if kind == "player" then seated = Horde.seated(body) end
    local x, y, z = Horde.positionOf(body)
    Horde.offer(look, body, kind, x, y, z, seated)
end

function Horde.offerActors(look, rows)
    for index = 1, #rows do
        local row = rows[index]
        local body = row.body
        if body ~= look.zombie then
            Horde.visit(look, body)
            if row.live then Horde.offer(look, body, "actor", row.x, row.y, row.z) end
        end
    end
end

function Horde.rowValue(row)
    if row.resolved then return row.score end
    return row.near * Horde.settings.awareSeen * row.weight
end

function Horde.ranksAbove(a, av, b, bv)
    if av ~= bv then return av > bv end
    if (a.source == "spotted") ~= (b.source == "spotted") then return a.source == "spotted" end
    if a.kind ~= b.kind then return a.kind == "actor" end
    return a.prey == true and b.prey ~= true
end

function Horde.beatsRest(look, row, value, skip)
    local picks = Horde.picks
    for index = 1, look.count do
        local other = picks[index]
        if other ~= row and other ~= skip and not other.out
                and not Horde.ranksAbove(row, value, other, Horde.rowValue(other)) then
            return false
        end
    end
    return true
end

function Horde.settleSight(row, aware)
    row.resolved, row.aware = true, aware
    row.score = row.near * aware * row.weight
    row.out = aware <= 0
end

function Horde.lookAt(look, row, floor, skip)
    local sensed = row.near * row.lo * row.weight
    if sensed > 0 and sensed >= floor and row.source ~= "named"
            and Horde.beatsRest(look, row, sensed, skip) then
        return Horde.settleSight(row, row.lo)
    end
    if look.rays >= look.rayBudget then return Horde.settleSight(row, row.rem) end
    if Horde.rayStamp ~= Horde.frameNowMs then Horde.rayStamp, Horde.rayCount = Horde.frameNowMs, 0 end
    if Horde.rayCount >= Horde.settings.rayFrameCap then
        Horde.metrics.rayCapped = (Horde.metrics.rayCapped or 0) + 1
        return Horde.settleSight(row, row.rem)
    end
    Horde.rayCount = Horde.rayCount + 1
    if Horde.rayCount > (Horde.metrics.rayPeak or 0) then Horde.metrics.rayPeak = Horde.rayCount end
    look.rays = look.rays + 1
    if Horde.inSight(look.zx, look.zy, look.zz, row.x, row.y, row.z) == false then
        Horde.metrics.sightRefused = (Horde.metrics.sightRefused or 0) + 1
        if look.memo ~= nil then look.memo.answers[row.body] = false end
        if row.rem > row.lo then Horde.metrics.sightHeld = (Horde.metrics.sightHeld or 0) + 1 end
        return Horde.settleSight(row, row.rem)
    end
    if look.memo ~= nil then
        look.memo.answers[row.body] = true
        if look.memo.seen ~= nil then look.memo.seen[row.body] = look.now end
    end
    look.lastSeen = row.body
    row.source = "sight"
    return Horde.settleSight(row, Horde.settings.awareSeen)
end

function Horde.bestPick(look, floor, skip, onlyHits)
    local picks = Horde.picks
    while true do
        local top, topValue = nil, nil
        for index = 1, look.count do
            local row = picks[index]
            if row ~= skip and not row.out and (not onlyHits or row.hit) then
                local value = Horde.rowValue(row)
                if value >= floor and (top == nil or Horde.ranksAbove(row, value, top, topValue)) then
                    top, topValue = row, value
                end
            end
        end
        if top == nil or top.resolved then return top end
        Horde.lookAt(look, top, floor, skip)
    end
end

Horde.targetFields = { "npc", "player", "none", "acquireNpc", "acquirePlayer",
    "playerCloser", "playerNpcsBlind", "playerSpotted" }

function Horde.tallyField(field)
    local now = Horde.frameNowMs or getTimestampMs()
    local stats = Horde.targetStats
    if stats == nil then
        stats = { startMs = now, cur = {}, last = {}, total = {} }
        Horde.targetStats = stats
    end
    if now - stats.startMs >= 60000 then
        stats.last, stats.cur, stats.startMs = stats.cur, {}, now
    end
    stats.cur[field] = (stats.cur[field] or 0) + 1
    stats.total[field] = (stats.total[field] or 0) + 1
end

function Horde.tally(choice, memory)
    local look = Horde.look
    if (look.actors or 0) <= 0 then return end
    local kind = choice.kind
    if kind == "actor" then
        Horde.tallyField("npc")
        if memory == nil or memory.prey ~= choice.body then Horde.tallyField("acquireNpc") end
    elseif kind == "player" then
        Horde.tallyField("player")
        if memory == nil or memory.prey ~= choice.body then Horde.tallyField("acquirePlayer") end
        if look.target ~= nil and look.target == choice.body then Horde.tallyField("playerSpotted") end
        local live, picks = 0, Horde.picks
        for index = 1, look.count do
            local row = picks[index]
            if row.kind == "actor" and not row.out then live = live + 1 end
        end
        if live == 0 then Horde.tallyField("playerNpcsBlind") else Horde.tallyField("playerCloser") end
    else
        Horde.tallyField("none")
    end
end

function Horde.targetText(window)
    local parts, fields = {}, Horde.targetFields
    for index = 1, #fields do
        parts[#parts + 1] = fields[index] .. "=" .. tostring(window[fields[index]] or 0)
    end
    return table.concat(parts, " ")
end

function Horde.targetLine()
    local stats = Horde.targetStats
    if stats == nil then return "[ALIFE-QA] HordeTargets: no contested zombie thinks yet" end
    local now = Horde.frameNowMs or getTimestampMs()
    if now - stats.startMs >= 60000 then
        stats.last, stats.cur, stats.startMs = stats.cur, {}, now
    end
    return "[ALIFE-QA] HordeTargets: lastMinute{" .. Horde.targetText(stats.last)
        .. "} thisMinute{" .. Horde.targetText(stats.cur)
        .. "} total{" .. Horde.targetText(stats.total)
        .. "} rays=" .. tostring(Horde.metrics.sightRays or 0)
        .. " blocked=" .. tostring(Horde.metrics.sightRefused or 0)
        .. " rayCapped=" .. tostring(Horde.metrics.rayCapped or 0)
        .. " rayPeak=" .. tostring(Horde.metrics.rayPeak or 0)
        .. " held=" .. tostring(Horde.metrics.sightHeld or 0)
        .. " marks=" .. tostring(#Horde.marks)
        .. " meleeNoise=" .. tostring(Horde.metrics.meleeNoise or 0)
end

function Horde.preyScore(look, prey)
    if not prey.resolved then Horde.lookAt(look, prey, math.huge, nil) end
    return prey.score
end

function Horde.decide(look, choice, now)
    local settings = Horde.settings
    local prey = look.preyRow
    local pick, reason = nil, nil
    if prey == nil then
        pick = Horde.bestPick(look, 0, nil, false)
    elseif prey.flat <= settings.contactRangeSquared then
        local held = Horde.preyScore(look, prey)
        pick = Horde.bestPick(look, held, prey, true)
        if pick == nil or not Horde.ranksAbove(pick, pick.score, prey, held) then
            pick, reason = prey, "contact"
        end
    elseif look.freshHit then
        pick = Horde.bestPick(look, 0, nil, false)
    elseif now - look.sinceMs < settings.preyHoldMs then
        pick, reason = prey, "hold"
    else
        pick = Horde.bestPick(look, Horde.preyScore(look, prey) * settings.switchRatio, prey, false)
        if pick == nil then pick, reason = prey, "keep" end
    end
    if pick == nil then return end
    if reason == nil then
        if pick == prey then reason = "keep"
        elseif pick.hit then reason = "hit"
        elseif prey == nil then reason = "new"
        else reason = "switch" end
    end
    if not (pick == prey and look.preyBumped and now - look.sinceMs < settings.preyHoldMs)
            and Horde.outOfReach(look, pick) then
        local bumped = Horde.bumpPick(look, pick)
        if bumped ~= nil then
            pick, reason = bumped, "bump"
            Horde.metrics.bumped = (Horde.metrics.bumped or 0) + 1
        end
    end
    choice.kind, choice.body, choice.reason, choice.row = pick.kind, pick.body, reason, pick
end

function Horde.outOfReach(look, pick)
    local settings = Horde.settings
    if pick.seated then return true end
    if pick.flat > settings.contactRangeSquared then return true end
    return pick.kind == "actor" and not Horde.mouthReaches(look.zombie, pick.body)
end

function Horde.bumpPick(look, pick)
    local settings = Horde.settings
    local picks, reach = Horde.picks, settings.contactRangeSquared
    local best, bestValue = nil, nil
    for index = 1, look.count do
        local row = picks[index]
        if row ~= pick and not row.out and row.flat <= reach and row.kind == "actor" then
            local value = row.near * settings.awareSeen * row.weight
            if (best == nil or Horde.ranksAbove(row, value, best, bestValue))
                    and Horde.mouthReaches(look.zombie, row.body) then
                best, bestValue = row, value
            end
        end
    end
    if best ~= nil and not (best.resolved and best.aware >= settings.awareSeen) then
        Horde.settleSight(best, settings.awareSeen)
    end
    return best
end

function Horde.choosePrey(zombie, now, rows, memory, target)
    local choice, look = Horde.choice, Horde.look
    choice.kind, choice.body, choice.reason, choice.row = "none", nil, "none", nil
    local zx, zy, zz = Horde.positionOf(zombie)
    if zx == nil then return choice end
    Horde.openLook(look, zombie, zx, zy, zz, now, memory, target)
    if rows ~= nil then Horde.offerActors(look, rows) end

    if look.drawn and look.prey ~= nil and look.preyKind == "actor" and not look.preyVisited then
        Horde.offerTied(look, look.prey, "actor")
    end
    if look.hitActor ~= nil and not look.hitVisited then Horde.offerTied(look, look.hitActor, "actor") end
    if look.shooter ~= nil and not look.shooterVisited then Horde.offerTied(look, look.shooter, "actor") end
    if look.actors == 0 and look.claimPlayer == nil then return choice end
    Horde.offerPlayers(look)
    if look.claimPlayer ~= nil and not look.claimVisited then Horde.offerTied(look, look.claimPlayer, "player") end
    if look.target ~= nil and not look.targetVisited then Horde.offerTied(look, look.target, "player") end
    Horde.decide(look, choice, now)
    if look.rays > 0 then
        Horde.noteSense(zombie, look.lastSeen or false, now + (tonumber(Horde.settings.senseRetryMs) or 1000))
    end
    return choice
end

function Horde.remember(zombie, memory, body, kind, drawnUntil, now, bumped)
    if memory == nil then
        memory = { sinceMs = now }
        chaseMemory[zombie] = memory
    elseif memory.prey ~= body then
        if memory.prey ~= nil then Horde.metrics.switched = (Horde.metrics.switched or 0) + 1 end
        memory.sinceMs = now
    end
    if memory.prey ~= body then memory.bumped = bumped == true end
    memory.prey, memory.kind, memory.drawnUntilMs = body, kind, drawnUntil
    return memory
end

function Horde.applyBiteDamage(actor, zombie, timestamp)
    if not isAlive(actor) then return false, "actor_dead" end
    local dataOk, data = pcall(function() return actor:getModData() end)
    if not dataOk or type(data) ~= "table" then return false, "actor_data_missing" end

    local now = tonumber(timestamp) or getTimestampMs()

    local biterOk, biterData = pcall(function() return zombie:getModData() end)
    biterOk = biterOk and type(biterData) == "table"
    if biterOk then
        if now < (tonumber(biterData.ProjectALifeNextBiteAtMs) or 0) then
            return false, "bite_cooldown"
        end
    elseif now < (tonumber(data.ProjectALifeNextZombieDamageAtMs) or 0) then

        return false, "bite_cooldown"
    end

    local slots = data.ProjectALifeBiterSlots
    if type(slots) ~= "table" then slots = {} end
    local live = 0
    for key, untilMs in pairs(slots) do
        if type(untilMs) == "number" and now < untilMs then
            live = live + 1
        else
            slots[key] = nil
        end
    end
    if live >= (tonumber(Horde.settings.maximumBiters) or 3) then
        return false, "bite_crowded"
    end

    local healthOk, health = pcall(function()
        local simulation = ProjectALife.ShellSimulation
        if simulation ~= nil and type(simulation.trueHealth) == "function" then
            return simulation.trueHealth(actor)
        end
        return actor:getHealth()
    end)
    health = healthOk and tonumber(health) or nil
    if health == nil or health <= 0 then return false, "actor_dead" end

    local maximum = tonumber(data.ProjectALifeMaximumHealth)
    if maximum == nil or maximum <= 0 then

        local settings = ProjectALife.BehaviorSettings
        local standard = tonumber(settings and settings.combat
            and settings.combat.standardHealth) or 50
        local simulation = ProjectALife.ShellSimulation
        local scale = simulation and simulation.healthScale() or 1
        maximum = math.max(math.max(0.1, health), standard * scale)
        data.ProjectALifeMaximumHealth = maximum
    end
    local damage = maximum * Horde.settings.maximumBiteFraction
    local tuned = ProjectALife.NpcHealth
    if tuned ~= nil and type(tuned.biteScale) == "function" then
        local ok, scale = pcall(tuned.biteScale, data)
        if ok and tonumber(scale) ~= nil then damage = damage * tonumber(scale) end
    end
    local strike = Horde.armorStrike(actor, zombie, damage)
    local blocked = strike ~= nil and strike.outcome == "blocked"
    if strike ~= nil then damage = strike.damage end
    local remaining = math.max(0, health - math.max(0.01, damage))

    if biterOk then
        biterData.ProjectALifeNextBiteAtMs = now + Horde.settings.damageCooldownMs
    end

    local slotKey
    pcall(function()
        local mine = zombie:getModData()
        if type(mine) ~= "table" then return end
        slotKey = mine.ProjectALifeBiterKey
        if slotKey == nil then
            slotKey = tostring(now) .. ":" .. tostring(math.floor(zombie:getX() * 8))
                .. ":" .. tostring(math.floor(zombie:getY() * 8))
            mine.ProjectALifeBiterKey = slotKey
        end
    end)
    slots[slotKey or tostring(zombie)] = now + Horde.settings.damageCooldownMs
    data.ProjectALifeBiterSlots = slots
    data.ProjectALifeNextZombieDamageAtMs = now + Horde.settings.damageCooldownMs
    if blocked then
        Horde.metrics.armorBlocked = (Horde.metrics.armorBlocked or 0) + 1
        return true, health, "blocked"
    end
    data.ProjectALifeLastHealth = remaining
    Horde.woundAndInfect(actor, data, remaining, strike ~= nil and strike.kind or nil)
    Horde.markWound(actor, zombie, remaining, maximum, now)

    local applied = pcall(function()
        local simulation = ProjectALife.ShellSimulation
        if simulation ~= nil then simulation.setHealth(actor, remaining)
        else actor:setHealth(remaining) end
    end)
    if not applied then return false, "health_write_failed" end
    Interop.hit(actor, zombie, health - remaining)
    Horde.metrics.damaged = Horde.metrics.damaged + 1
    if remaining <= 0 then
        pcall(function() actor:Kill(zombie) end)
        Horde.reportDeath(actor)
    end
    return true, remaining
end

function Horde.armorStrike(actor, zombie, damage)
    local armor = ProjectALife.Armor
    if armor == nil or type(armor.strike) ~= "function" then return nil end
    local ok, strike = pcall(armor.strike, actor, zombie, damage)
    if ok and type(strike) == "table" then return strike end
    if not ok and type(armor.metrics) == "table" then armor.metrics.errors = (armor.metrics.errors or 0) + 1 end
    return nil
end

function Horde.woundAndInfect(actor, data, remaining, forced)
    local sim = ProjectALife.ShellSimulation
    if sim == nil or type(sim.woundKind) ~= "function" or type(sim.infect) ~= "function"
            or type(sim.woundInfects) ~= "function" or type(ZombRand) ~= "function" then return nil end
    local kind = forced
    if kind == nil then kind = sim.woundKind(ZombRand(100), ZombRand(100)) end
    if (tonumber(remaining) or 1) <= 0 then kind = "killed" end
    data.ProjectALifeLastWound = kind
    Horde.noteReason("wounds", kind)
    if sim.woundInfects(kind, ZombRand(100)) and sim.infect(actor, kind, ZombRand(1001) / 1000) then
        Horde.metrics.infections = (Horde.metrics.infections or 0) + 1
    end
    Horde.relayBite(actor, kind)
    return kind
end

function Horde.relayBite(actor, kind)
    local executor = ProjectALife.Executor
    if executor == nil or type(executor.relayBite) ~= "function" then return false end
    local ok, sent = pcall(executor.relayBite, actor, kind)
    return ok and sent == true
end

function Horde.reportDeath(actor)
    local executor = ProjectALife.Executor
    if executor == nil or type(executor.reportDeath) ~= "function" or type(executor.byShell) ~= "table"
            or executor.byShell[actor] == nil then return false end
    if type(actor.isDead) ~= "function" or actor:isDead() ~= true then return false end
    local ok = pcall(executor.reportDeath, actor)
    return ok
end

function Horde.markWound(actor, zombie, remaining, maximum, now)
    local health = ProjectALife.Health
    if health == nil or health.enabled ~= true or type(health.recordWound) ~= "function"
            or (tonumber(remaining) or 0) <= 0 then return false end
    if type(health.invulnerable) == "function" and health.invulnerable(actor) then return false end
    health.recordWound(zombie, actor, "torso", remaining, maximum, now)
    return true
end

function Horde.teethFree(actor, zombie, now)
    local mine, data = zombie:getModData(), actor:getModData()
    local clock
    if type(mine) == "table" then
        clock = mine.ProjectALifeNextBiteAtMs
    elseif type(data) == "table" then
        clock = data.ProjectALifeNextZombieDamageAtMs
    end
    if now < (tonumber(clock) or 0) then
        return false
    end
    local live = 0
    local slots = type(data) == "table" and data.ProjectALifeBiterSlots or nil
    if type(slots) == "table" then
        for _, untilMs in pairs(slots) do
            if type(untilMs) == "number" and now < untilMs then live = live + 1 end
        end
    end

    for other, bite in pairs(Horde.bites) do
        if other ~= zombie and bite.actor == actor and bite.landed ~= true then
            live = live + 1
        end
    end
    return live < (tonumber(Horde.settings.maximumBiters) or 3)
end

function Horde.teethReady(actor, zombie, now)
    local ok, ready = pcall(Horde.teethFree, actor, zombie, now)
    if not ok then return true end
    if ready ~= true then Horde.biteWait("teeth") end
    return ready
end

function Horde.noteReason(field, reason)
    local metrics = Horde.metrics
    local ledger = metrics[field]
    if type(ledger) ~= "table" then
        ledger = {}
        metrics[field] = ledger
    end
    local key = tostring(reason)
    ledger[key] = (ledger[key] or 0) + 1
end

function Horde.biteWait(reason)
    Horde.noteReason("biteWaits", reason)
    return false
end

local function clearBite(key)
    if Horde.bites[key] == nil then return false end
    if Horde.bites[key].typed then
        pcall(function()
            key:setVariable("AttackType", "")
            key:setVariable("AttackOutcome", "")
        end)
    end
    Horde.bites[key] = nil
    Horde.biteCount = math.max(0, (Horde.biteCount or 0) - 1)
    return true
end

local function openBite(key, actor, low, claw, typed)
    local existing = Horde.bites[key]
    if existing == nil then
        Horde.bites[key] = { actor = actor, low = low, claw = claw, typed = typed }
        Horde.biteCount = (Horde.biteCount or 0) + 1
        return
    end
    existing.actor, existing.low, existing.claw, existing.typed = actor, low, claw, typed
    existing.posedAtMs, existing.landed = nil, nil
end

function Horde.biteSignal(zombie, name)
    local ok, value = pcall(zombie.getVariableBoolean, zombie, name)
    return ok and value == true
end

function Horde.isBiteName(bump)
    local animations = ProjectALife.Animations
    if animations ~= nil and type(animations.bumpName) == "function" then
        bump = animations.bumpName(bump)
    end
    return bump == BITE_BUMP or bump == BITE_BUMP_LOW or bump == BITE_CLAW
end

function Horde.renameBite(zombie, bump)
    if bump == BITE_BUMP or bump == BITE_BUMP_LOW or bump == BITE_CLAW then return end
    local animations = ProjectALife.Animations
    if animations ~= nil and type(animations.renameLiveBump) == "function" then
        animations.renameLiveBump(zombie, bump)
    end
end

function Horde.bitePlaying(zombie)
    if zombie == nil then return false end
    local ok, bump = pcall(zombie.getBumpType, zombie)
    if not (ok and Horde.isBiteName(bump) and actionState(zombie) == "bumped") then return false end
    Horde.renameBite(zombie, bump)
    return true
end

function Horde.dropUnstartedPose(zombie)
    pcall(function()
        if actionState(zombie) == "bumped" then return end
        local bump = zombie:getBumpType()
        if Horde.isBiteName(bump) then
            zombie:setBumpType("")
            zombie:setBumpDone(true)
            zombie:setVariable("BumpDone", true)
        end
    end)
end

function Horde.mouthsOn(actor)
    local count = 0
    for _, bite in pairs(Horde.bites) do
        if bite.actor == actor then count = count + 1 end
    end
    return count
end

Horde.biteSounds = { prone = "NeckBite", wounded = "ZombieBite", fresh = "ZombieScratch" }

function Horde.biteSound(low, remaining, maximum, claw)
    if low then return Horde.biteSounds.prone end
    if claw == true then return Horde.biteSounds.fresh end
    if Horde.tuning.attackAnims == true then return Horde.biteSounds.wounded end
    if maximum ~= nil and maximum > 0 and (tonumber(remaining) or 0) < maximum * 0.5 then
        return Horde.biteSounds.wounded
    end
    return Horde.biteSounds.fresh
end

function Horde.biteAftermath(actor, zombie, low, remaining, now, claw, outcome)
    local data
    pcall(function() data = actor:getModData() end)
    if type(data) ~= "table" then return end
    local settings = Horde.settings
    data.ProjectALifeLastBiteAtMs = now
    local guard = ProjectALife.AIFence
    if guard ~= nil and type(guard.hitWindowUntilMs) == "table" then
        guard.hitWindowUntilMs[actor] = now
            + (tonumber(guard.hitCleanupWindowMs) or settings.flinchWindowMs)
    end
    local uid = data.ProjectALifeUID
    if type(uid) == "string" then
        pcall(function()
            local perception = ProjectALife.Perception
            if perception ~= nil and type(perception.noteAttacker) == "function" then
                perception.noteAttacker(uid, zombie, settings.retaliateMs, "zombie")
            end
        end)
        pcall(function()
            local registry, tactics = ProjectALife.ActorRegistry, ProjectALife.SquadTactics
            if registry == nil or tactics == nil or type(registry.read) ~= "function"
                    or type(tactics.reportThreat) ~= "function" then return end
            local victim = registry.read(uid)
            if victim ~= nil then tactics.reportThreat(victim, zombie, "zombie", now) end
        end)
    end
    if outcome == "blocked" then return end
    local maximum = tonumber(data.ProjectALifeMaximumHealth)
    local policy = ProjectALife.AudioPolicy
    if policy ~= nil and type(policy.nearSound) == "function" then
        pcall(policy.nearSound, actor, Horde.biteSound(low, remaining, maximum, claw), { key = actor })
    end
    pcall(function()
        if actor.addBlood ~= nil then actor:addBlood(nil, false, true, false) end
    end)
    if now < (tonumber(data.ProjectALifeNextFlinchAtMs) or 0) then return end

    if Horde.mouthsOn(actor) > 1 then return end

    if string.sub(actionState(actor), 1, 5) == "climb" then return end
    data.ProjectALifeNextFlinchAtMs = now + settings.flinchEveryMs
    data.ProjectALifeStaggerUntilMs = now + settings.flinchWindowMs
    local animations = ProjectALife.Animations
    if animations ~= nil and type(animations.apply) == "function" then
        pcall(animations.apply, actor, "hit_react")
    end
end

function Horde.landBite(zombie, bite, now)
    local actor = bite.actor
    if actor == nil then return false end
    local settings = Horde.settings
    local flat, vertical = distanceSquared(zombie, actor)
    if flat > settings.contactRangeSquared or vertical >= settings.floorBand then
        Horde.noteReason("biteMisses", "reach")
        return false
    end
    if not Horde.mouthReaches(zombie, actor) then
        Horde.noteReason("biteMisses", "edge")
        return false
    end
    local okCall, applied, remaining, outcome = pcall(Horde.applyBiteDamage, actor, zombie, now)
    if not (okCall and applied == true) then
        Horde.noteReason("biteMisses", okCall and remaining or "error")
        return false
    end
    Horde.biteAftermath(actor, zombie, bite.low, remaining, now, bite.claw, outcome)
    Horde.checkDrag(actor, zombie, now)
    return true
end

function Horde.chaseOf(zombie)
    return chaseMemory[zombie]
end

function Horde.foreignPose(zombie, bite, now)
    local adapter = ProjectALife.CryOfFearAdapter
    if adapter == nil or type(adapter.forcePose) ~= "function" then return false end
    local ok, forced = pcall(adapter.forcePose, zombie, bite, now, Horde.settings.biteStartWithinMs)
    return ok and forced == true
end

local function advanceBite(zombie)

    if (Horde.biteCount or 0) <= 0 then return false end
    local key = zombie
    local bite = Horde.bites[key]
    if bite == nil then return false end
    if not isAlive(zombie) then clearBite(key); return true end
    if bite.landed ~= true and Horde.stunned(zombie) then Horde.cancelBite(zombie); return true end

    if Horde.protectsNativeState(actionState(zombie)) then return false end
    local settings = Horde.settings
    local now = getTimestampMs()
    local playing = Horde.bitePlaying(zombie)
    if not playing and bite.posedAtMs == nil then playing = Horde.foreignPose(zombie, bite, now) end
    if not playing and bite.forced == true then playing = true end
    if bite.posedAtMs == nil then
        if not playing then
            if now - (tonumber(bite.openedAtMs) or now) >= settings.biteStartWithinMs then
                Horde.dropUnstartedPose(zombie)
                clearBite(key)
            end
            return false
        end
        bite.posedAtMs = now
        Horde.metrics.posed = Horde.metrics.posed + 1
    end
    markBiteWindow(bite.actor, settings.biteWindowMs)
    local elapsed = now - bite.posedAtMs
    if bite.landed ~= true and (Horde.biteSignal(zombie, "ALifeBiteLanded")
            or elapsed >= settings.biteLandAfterMs) then
        bite.landed = true
        Horde.landBite(zombie, bite, now)
    end
    local finished = not playing or elapsed >= settings.biteReleaseAfterMs
        or (bite.landed == true and Horde.biteSignal(zombie, "ALifeBiteDone"))
    if finished then

        pcall(function() bite.actor:setZombiesDontAttack(true) end)
        clearBite(key)
    end
    return true
end

function Horde.pursueStep(zombie, actor)
    local data = zombie:getModData()

    data.ALifeContactSinceMs = nil
    local x, y, z = actor:getX(), actor:getY(), actor:getZ()
    local now = getTimestampMs()

    local identity = actor:getModData()
    local known, targetId = Horde.preyIds[actor], nil
    if known ~= nil and identity.ProjectALifeUID ~= nil and known.uid == identity.ProjectALifeUID
            and known.generation == identity.ProjectALifeGeneration then
        targetId = known.id
    end
    if targetId == nil then
        targetId = tostring(identity.ProjectALifeUID or actor:getID())
            .. ":" .. tostring(identity.ProjectALifeGeneration or 0)
        Horde.rememberPreyId(actor, identity, targetId)
    end
    local targetChanged = data.ALifeChaseTargetId ~= targetId
    local repathDue = now >= (tonumber(data.ALifeChaseRepathAtMs) or 0)
    local zx, zy = zombie:getX(), zombie:getY()
    local progressed = data.ALifeChaseLastX == nil
        or (zx - data.ALifeChaseLastX) ^ 2 + (zy - data.ALifeChaseLastY) ^ 2 >= 0.04
    if progressed then
        data.ALifeChaseLastX, data.ALifeChaseLastY = zx, zy
        data.ALifeChaseProgressAt = now
        data.ALifeChaseBackoffMs = nil
        local issued = data.ALifeChaseIssuedAtMs
        if issued ~= nil and data.ALifeChaseTimedAtMs ~= issued then
            data.ALifeChaseTimedAtMs = issued
            Horde.noteLatency(now - issued)
        end
    end

    local stalled = now - (data.ALifeChaseProgressAt or now) >= 2500
    local state = actionState(zombie)
    local walking = state == "walktoward"
    local reacquire = targetChanged or stalled or not walking
    local moved = Horde.goalMoved(data, x, y)
    if stalled and state == "pathfind" then Horde.metrics.pathStalled = (Horde.metrics.pathStalled or 0) + 1 end
    if state == "pathfind" and not targetChanged and not moved
            and Horde.pathHeld(zombie, data, now, stalled) then
        Horde.metrics.pathHeld = (Horde.metrics.pathHeld or 0) + 1
        return
    end
    if reacquire then
        if not (targetChanged or moved or repathDue) then return end
        if not targetChanged and not Horde.pathToken(now) then
            Horde.metrics.pathBudget = (Horde.metrics.pathBudget or 0) + 1
            return
        end
    elseif now < (tonumber(data.ALifeChaseGoalAtMs) or 0) then
        return
    end
    local goalX, goalY = x, y
    local sampledAt = tonumber(data.ALifeChaseSampleAtMs)
    local lastX, lastY = data.ALifeChasePathX, data.ALifeChasePathY
    if not reacquire and sampledAt ~= nil and lastX ~= nil then
        local span = now - sampledAt
        if span >= 100 and span <= 1500 then
            local driftX, driftY = x - lastX, y - lastY
            local awayX, awayY = x - zx, y - zy
            if driftX * awayX + driftY * awayY > 0
                    and awayX * awayX + awayY * awayY > 4 then
                local ahead = 600 / span
                local leadX, leadY = driftX * ahead, driftY * ahead
                local reach = math.sqrt(leadX * leadX + leadY * leadY)
                if reach > 2 then
                    leadX, leadY = leadX * 2 / reach, leadY * 2 / reach
                end
                goalX, goalY = x + leadX, y + leadY
            end
        end
    end
    if reacquire then
        Horde.releasePath(zombie)

        if WalkTowardState ~= nil and ZombieIdleState ~= nil
                and zombie:getCurrentState() == WalkTowardState.instance() then
            zombie:changeState(ZombieIdleState.instance())
        end

        data.ALifeChaseRepathAtMs = now + Horde.repathWait(data, stalled and not targetChanged)
    end

    zombie:pathToSound(math.floor(goalX), math.floor(goalY), math.floor(z))
    data.ALifeChaseTargetId = targetId
    data.ALifeChasePathX, data.ALifeChasePathY = x, y
    data.ALifeChaseGoalX, data.ALifeChaseGoalY = math.floor(goalX), math.floor(goalY)
    data.ALifeChaseIssuedAtMs = now
    data.ALifeChaseSampleAtMs = now

    data.ALifeChaseGoalAtMs = now + 150
end

function Horde.noteLatency(ms)
    local metrics = Horde.metrics
    metrics.pathLatencyCount = (metrics.pathLatencyCount or 0) + 1
    metrics.pathLatencySumMs = (metrics.pathLatencySumMs or 0) + ms
    if ms > (metrics.pathLatencyMaxMs or 0) then metrics.pathLatencyMaxMs = ms end
end

function Horde.goalMoved(data, x, y)
    local fromX, fromY = data.ALifeChasePathX, data.ALifeChasePathY
    if fromX == nil or fromY == nil then return false end
    local reach = Horde.settings.pathGoalTiles
    return (x - fromX) ^ 2 + (y - fromY) ^ 2 >= reach * reach
end

function Horde.pathHeld(zombie, data, now, stalled)
    local goalX, goalY = data.ALifeChaseGoalX, data.ALifeChaseGoalY
    if goalX == nil or goalY == nil then return false end
    local settings = Horde.settings
    if stalled and now - (tonumber(data.ALifeChaseIssuedAtMs) or 0) >= settings.pathWaitMs then return false end
    local finder = zombie:getPathFindBehavior2()
    if finder == nil or type(finder.getTargetX) ~= "function" or type(finder.getTargetY) ~= "function" then
        return false
    end
    local reach = settings.pathGoalTiles
    return math.abs(finder:getTargetX() - goalX) <= reach and math.abs(finder:getTargetY() - goalY) <= reach
end

function Horde.pathToken(now)
    local bucket, settings = Horde.pathBucket, Horde.settings
    if bucket.atMs == nil or now < bucket.atMs then
        bucket.atMs = now
        bucket.tokens = settings.pathBurst
    elseif now > bucket.atMs then
        bucket.tokens = math.min(settings.pathBurst, bucket.tokens + (now - bucket.atMs) * settings.pathPerSecond / 1000)
        bucket.atMs = now
    end
    if bucket.tokens < 1 then return false end
    bucket.tokens = bucket.tokens - 1
    return true
end

function Horde.repathWait(data, stalled)
    local settings = Horde.settings
    if not stalled then
        data.ALifeChaseBackoffMs = nil
        return settings.repathMs
    end
    local wait = math.min(settings.repathMaxMs, (tonumber(data.ALifeChaseBackoffMs) or settings.repathMs) * 2)
    data.ALifeChaseBackoffMs = wait
    return wait
end

function Horde.rememberPreyId(actor, identity, id)
    if identity.ProjectALifeUID == nil then return end
    local known = Horde.preyIds[actor]
    if known == nil then
        if Horde.preyIdCount >= (Horde.memoLimit or 256) then Horde.preyIds, Horde.preyIdCount = {}, 0 end
        known = {}
        Horde.preyIds[actor] = known
        Horde.preyIdCount = Horde.preyIdCount + 1
    end
    known.uid, known.generation, known.id = identity.ProjectALifeUID, identity.ProjectALifeGeneration, id
end

local function pursueByLocation(zombie, actor)
    pcall(Horde.pursueStep, zombie, actor)
end

function Horde.steeringPlayerIsLocal(zombie)
    if type(getOnlinePlayers) ~= "function" then return true end
    local roster, listed = Horde.frameRoster()
    if roster == nil then roster, listed = Horde.sweepPlayers() end
    return Horde.dealt(zombie, roster, listed)
end

function Horde.steerKey(zombie)
    return zombie:getOnlineID(), zombie:getX(), zombie:getY()
end

function Horde.dealt(zombie, roster, listed)
    if roster == nil or (tonumber(listed) or 0) <= 1 then return true end
    local okZombie, zombieId, zx, zy = pcall(Horde.steerKey, zombie)
    zombieId = okZombie and tonumber(zombieId) or nil
    if zombieId == nil or zombieId < 0 then return true end
    local radiusSquared = Horde.settings.steerRadiusTiles ^ 2

    local near, localIds, marked = Horde.dealNear, Horde.dealMine, Horde.dealMarked
    for index = #near, 1, -1 do near[index] = nil end
    for index = #marked, 1, -1 do
        localIds[marked[index]] = nil
        marked[index] = nil
    end
    local nearestId, nearestSquared = nil, nil
    for index = 1, #roster do
        local man = roster[index]
        local id = man.id
        if id ~= nil then
            local squared = (man.x - zx) ^ 2 + (man.y - zy) ^ 2
            if squared <= radiusSquared then near[#near + 1] = id end
            if nearestSquared == nil or squared < nearestSquared
                    or (squared == nearestSquared and id < nearestId) then
                nearestId, nearestSquared = id, squared
            end
            if man.mine then
                localIds[id] = true
                marked[#marked + 1] = id
            end
        end
    end

    if nearestId == nil then return true end
    if #near == 0 then near[1] = nearestId end
    local pool = near
    table.sort(pool)
    return localIds[pool[(math.floor(zombieId) % #pool) + 1]] == true
end

function Horde.dropPath(zombie)
    local finder = zombie:getPathFindBehavior2()
    if finder ~= nil then finder:cancel() end
    zombie:setPath2(nil)
    if finder ~= nil then finder:reset() end
end

function Horde.releasePath(zombie)
    pcall(Horde.dropPath, zombie)
end

function Horde.clearChase(zombie, data)
    Horde.releasePath(zombie)
    data.ALifeChasePathX, data.ALifeChasePathY = nil, nil
    data.ALifeChaseTargetId = nil
    data.ALifeChaseLastX, data.ALifeChaseLastY = nil, nil
    data.ALifeChaseProgressAt = nil
    data.ALifeChaseRepathAtMs = nil
    data.ALifeChaseGoalX, data.ALifeChaseGoalY = nil, nil
    data.ALifeChaseIssuedAtMs = nil
    data.ALifeChaseTimedAtMs = nil
    data.ALifeChaseBackoffMs = nil
end

function Horde.endChase(zombie)
    if zombie == nil then return false end
    local data = Horde.dataOf(zombie)
    if data == nil or data.ALifeChasePathX == nil then return false end
    pcall(Horde.clearChase, zombie, data)
    return true
end

function Horde.isSprinter(zombie)
    if type(zombie.getSpeedType) ~= "function" then return false end
    return zombie:getSpeedType() == 1
end

function Horde.setSprint(zombie, value)
    if type(zombie.setVariable) ~= "function" then return false end
    zombie:setVariable("ALifeHordeChase", value)
    return true
end

function Horde.markSprint(zombie)
    local previous = Horde.sprinting[zombie]
    local okType, sprinter = pcall(Horde.isSprinter, zombie)
    local wantsSprint = okType and sprinter == true
    if previous ~= nil and (not okType or previous == wantsSprint) then return end
    if previous == nil and Horde.sprintCount >= Horde.sprintLimit then Horde.dropAllSprints() end
    local raised = false
    if wantsSprint or previous == true then
        local okSet, set = pcall(Horde.setSprint, zombie, wantsSprint)
        if okSet and set == true then
            raised = wantsSprint
        elseif previous ~= nil then
            return
        end
    end
    Horde.sprinting[zombie] = raised
    if previous == nil then Horde.sprintCount = Horde.sprintCount + 1 end
end

function Horde.dropSprint(zombie)
    local raised = Horde.sprinting[zombie]
    if raised == nil then return end
    Horde.sprinting[zombie] = nil
    Horde.sprintCount = math.max(0, Horde.sprintCount - 1)
    if raised == true then pcall(Horde.setSprint, zombie, false) end
end

function Horde.dropAllSprints()
    for zombie, raised in pairs(Horde.sprinting) do
        if raised == true then pcall(Horde.setSprint, zombie, false) end
    end
    Horde.sprinting, Horde.sprintCount = {}, 0
end

function Horde.setLunge(zombie, value)
    if type(zombie.setVariable) ~= "function" then return false end
    zombie:setVariable("ALifeHordeLunge", value)
    return true
end

function Horde.lungeLine(zombie, actor)
    if LosUtil == nil or type(LosUtil.lineClear) ~= "function" or type(getCell) ~= "function" then return true end
    local zx, zy, zz = Horde.positionOf(zombie)
    local ax, ay, az = Horde.positionOf(actor)
    if zx == nil or ax == nil then return false end
    local okCell, cell = pcall(getCell)
    if not okCell or cell == nil then return false end
    local ok, result = pcall(LosUtil.lineClear, cell, math.floor(zx), math.floor(zy), math.floor(zz),
        math.floor(ax), math.floor(ay), math.floor(az), false)
    if not ok or result == nil then return false end
    local outcomes = LosUtil.TestResults
    if outcomes ~= nil and outcomes.Blocked ~= nil and type(result) ~= "string" then
        return result ~= outcomes.Blocked and result ~= outcomes.ClearThroughClosedDoor
    end
    local name = tostring(result)
    return name ~= "Blocked" and name ~= "ClearThroughClosedDoor"
end

function Horde.lungeReady(zombie, actor, row)
    local reach = tonumber(Horde.settings.lungeTiles) or 3.5
    if row == nil or row.flat > reach * reach or row.out == true then return false end
    local okType, sprinter = pcall(Horde.isSprinter, zombie)
    if okType and sprinter == true then return false end
    if type(zombie.isCrawling) == "function" and zombie:isCrawling() == true then return false end
    if Horde.lunging[zombie] == true then return true end
    return Horde.lungeLine(zombie, actor)
end

function Horde.markLunge(zombie, wanted)
    wanted = wanted == true
    if wanted == (Horde.lunging[zombie] == true) then return end
    local ok, set = pcall(Horde.setLunge, zombie, wanted)
    if not ok or set ~= true then return end
    if wanted then Horde.lunging[zombie] = true else Horde.lunging[zombie] = nil end
    if wanted then Horde.metrics.lunges = (Horde.metrics.lunges or 0) + 1 end
end

function Horde.dropLunge(zombie)
    if Horde.lunging[zombie] ~= nil then Horde.markLunge(zombie, false) end
end

function Horde.settleStep(zombie)
    if WalkTowardState == nil or ZombieIdleState == nil or zombie.getCurrentState == nil then return false end
    if zombie:getCurrentState() ~= WalkTowardState.instance() then return false end
    zombie:changeState(ZombieIdleState.instance())
    Horde.metrics.settled = (Horde.metrics.settled or 0) + 1
    return true
end

function Horde.settle(zombie)
    local ok, settled = pcall(Horde.settleStep, zombie)
    return ok and settled == true
end

function Horde.settleFree(zombie, memory)
    if memory ~= nil and memory.drawnUntilMs ~= nil then return false end
    local ok, target = pcall(zombie.getTarget, zombie)
    if not ok or target ~= nil then return false end
    return Horde.settle(zombie)
end

function Horde.wake(zombie)
    local ok, parked = pcall(zombie.isUseless, zombie)
    if ok and parked == true then pcall(zombie.setUseless, zombie, false) end
end

function Horde.applyHold(zombie, now)
    local data = zombie:getModData()
    local record = data.ALifeHold
    if type(record) ~= "table" then
        record = { sinceMs = now }
        data.ALifeHold = record
    end
    record.renewedAtMs = now

    if actionState(zombie) == "lunge" then
        if ZombieIdleState == nil or type(ZombieIdleState.instance) ~= "function"
                or type(zombie.changeState) ~= "function" then return false end
        zombie:changeState(ZombieIdleState.instance())
    end
    zombie:setTarget(nil)
    zombie:clearAggroList()
end

function Horde.hold(zombie, now)
    pcall(Horde.applyHold, zombie, now)
end

function Horde.release(zombie)
    if zombie == nil then return false end

    if zombie.hasModData ~= nil and zombie:hasModData() == false then return false end
    local ok, data = pcall(zombie.getModData, zombie)
    if not ok or type(data) ~= "table" or data.ALifeHold == nil then return false end
    data.ALifeHold = nil
    return true
end

function Horde.unstick(zombie, now)
    if Horde.bites[zombie] ~= nil then return end
    if zombie == nil then return end
    local data = Horde.dataOf(zombie)
    local record = data ~= nil and data.ALifeHold or nil
    local stale = type(record) == "table"
        and (tonumber(now) or 0) - (tonumber(record.renewedAtMs) or 0) > Horde.settings.holdLeaseMs
    if stale and Horde.sprinting[zombie] ~= nil then Horde.dropSprint(zombie) end
    if stale and Horde.release(zombie) then
        Horde.metrics.unstuck = (Horde.metrics.unstuck or 0) + 1
    end
end

local function stopPursuit(zombie)
    local released = Horde.release(zombie)
    local ended = Horde.endChase(zombie)
    Horde.dropLunge(zombie)
    if Horde.sprinting[zombie] ~= nil then Horde.dropSprint(zombie) end
    return released or ended
end

Horde.playerClaims = setmetatable({}, { __mode = "k" })

function Horde.isPlayer(body)
    if body == nil or type(instanceof) ~= "function" then return false end
    if instanceof(body, "IsoPlayer") ~= true then return false end
    if type(body.isAnimal) ~= "function" then return true end
    local ok, animal = pcall(body.isAnimal, body)
    return not (ok and animal == true)
end

function Horde.onPlayerHitZombie(zombie, attacker)
    if zombie == nil or attacker == nil or not Horde.enabled then return end
    if type(instanceof) ~= "function" or not instanceof(attacker, "IsoPlayer") then return end
    if isOwnedActor(zombie) then return end
    Horde.playerClaims[zombie] = { player = attacker, untilMs = getTimestampMs() + Horde.settings.hitWindowMs }
    Horde.recallFar(zombie)
end

function Horde.yieldToPlayer(zombie, now)
    if Horde.bites[zombie] ~= nil then return false end
    local claim = Horde.playerClaims[zombie]
    if claim == nil then return false end
    if now >= claim.untilMs or not isAlive(claim.player)
            or claim.player:getCurrentSquare() == nil then
        Horde.playerClaims[zombie] = nil
        return false
    end
    if not claim.released then
        stopPursuit(zombie)
        Horde.wake(zombie)
        local ok = pcall(zombie.setTarget, zombie, claim.player)
        if not ok then return false end
        claim.released = true
    end
    return true
end

function Horde.handBack(zombie, now, memory, choice, spotted)
    if stopPursuit(zombie) then
        Horde.metrics.reclaimed = Horde.metrics.reclaimed + 1
        if not spotted then Horde.settle(zombie) end
    end
    local look = Horde.look
    if look.claimPlayer ~= nil and choice.body == look.claimPlayer then Horde.yieldToPlayer(zombie, now) end
    if look.actors == 0 then
        chaseMemory[zombie] = nil
        return
    end
    Horde.remember(zombie, memory, choice.body, "player", nil, now, choice.reason == "bump")
end

Horde.enabled = true

function Horde.steersHere(zombie)
    if isOwnedActor(zombie) then return false end
    local okRemote, remote = pcall(zombie.isRemoteZombie, zombie)
    if not okRemote or remote ~= true then return true end
    if Horde.steeringPlayerIsLocal(zombie) then return true end
    Horde.metrics.remoteSkipped = (Horde.metrics.remoteSkipped or 0) + 1

    if Horde.sprinting[zombie] ~= nil then Horde.dropSprint(zombie) end
    return false
end

function Horde.clearNativeActorTarget(zombie)
    if zombie == nil or type(zombie.getTarget) ~= "function"
            or type(zombie.setTarget) ~= "function" or type(zombie.clearAggroList) ~= "function" then
        return false
    end
    local target = zombie:getTarget()
    if target == nil or not isOwnedActor(target) then return false end
    if not Horde.steersHere(zombie) then return false end
    if actionState(zombie) == "lunge" then
        if ZombieIdleState == nil or type(ZombieIdleState.instance) ~= "function"
                or type(zombie.changeState) ~= "function" then return false end
        zombie:changeState(ZombieIdleState.instance())
    end
    zombie:setTarget(nil)
    zombie:clearAggroList()
    return true
end

function Horde.onZombieUpdate(zombie)
    if not Horde.enabled or zombie == nil then return end
    Horde.clearNativeActorTarget(zombie)
    local cleared = true

    if (Horde.biteCount or 0) > 0 and Horde.bites[zombie] ~= nil then
        cleared = false
        if not Horde.steersHere(zombie) then return end
        if advanceBite(zombie) then return end
    end

    local now = Horde.frameNowMs or getTimestampMs()
    local due = nextThinkAt[zombie]
    if due ~= nil and now < due then return end
    nextThinkAt[zombie] = now + Horde.thinkIntervalMs

    if due == nil then
        Horde.beatPhase = (Horde.beatPhase + 37) % Horde.thinkIntervalMs
        nextThinkAt[zombie] = nextThinkAt[zombie] - Horde.beatPhase
    end
    if Horde.farBeats[zombie] ~= nil then Horde.farBeats[zombie] = nil end
    if not Horde.steersHere(zombie) then return end

    if not isAlive(zombie) then Horde.dropSprint(zombie); chaseMemory[zombie] = nil; return end
    Horde.think(zombie, now, cleared)
end

function Horde.zombieEntry(zombie)
    local fence = ProjectALife.AIFence
    if fence == nil or fence.frameSampling ~= true then return Horde.onZombieUpdate(zombie) end
    local started = getTimestampMs()
    Horde.onZombieUpdate(zombie)
    local timing = Horde.frameTiming
    timing.spentMs = timing.spentMs + math.max(0, getTimestampMs() - started)
    timing.calls = timing.calls + 1
end

function Horde.closeSampledFrame()
    local timing = Horde.frameTiming
    timing.frames = timing.frames + 1
    if timing.calls <= 0 then return false end
    local spent = timing.spentMs
    timing.busyFrames = timing.busyFrames + 1
    timing.callsSum = timing.callsSum + timing.calls
    timing.sumMs = timing.sumMs + spent
    if spent > timing.maxMs then timing.maxMs = spent end
    if spent > 4 then timing.over4 = timing.over4 + 1 end
    if spent > 8 then timing.over8 = timing.over8 + 1 end
    if spent > 16 then timing.over16 = timing.over16 + 1 end
    timing.spentMs, timing.calls = 0, 0
    return true
end

function Horde.reportFrameTiming(windowMs)
    local timing = Horde.frameTiming
    local line
    if timing.busyFrames > 0 and windowMs >= 0 then
        line = string.format("[ALIFE-PERF] frame_horde %ds sampled=%d/%d zombies=%.1f avg=%.2fms max=%dms over4=%d over8=%d over16=%d",
            math.floor(windowMs / 1000), timing.busyFrames, timing.frames, timing.callsSum / timing.busyFrames,
            timing.sumMs / timing.busyFrames, math.floor(timing.maxMs), timing.over4, timing.over8, timing.over16)
        print(line)
    end
    timing.spentMs, timing.calls, timing.frames, timing.busyFrames = 0, 0, 0, 0
    timing.sumMs, timing.maxMs, timing.callsSum, timing.over4, timing.over8, timing.over16 = 0, 0, 0, 0, 0, 0
    return line
end

function Horde.lyingFlags(zombie)
    return zombie:isProne() == true or zombie:isOnFloor() == true
        or zombie:isKnockedDown() == true or zombie:isCrawling() == true
        or zombie:getVariableBoolean("bOnFloor") == true
end

function Horde.slowBeat(zombie, now, ms)
    local interval = Horde.thinkIntervalMs
    local extra = (tonumber(ms) or interval) - interval
    if extra <= 0 then return end
    nextThinkAt[zombie] = (nextThinkAt[zombie] or now + interval) + extra
    Horde.farBeats[zombie] = true
end

function Horde.plainBeat(zombie, now)
    local due, interval = nextThinkAt[zombie], Horde.thinkIntervalMs
    if due ~= nil and due > now + interval then
        nextThinkAt[zombie] = due - math.floor((due - now) / interval) * interval
    end
end

function Horde.recallAllFar(now)
    local any = false
    for zombie in pairs(Horde.farBeats) do
        now = now or Horde.frameNowMs or getTimestampMs()
        Horde.plainBeat(zombie, now)
        any = true
    end
    if any then Horde.farBeats = {} end
end

function Horde.recallFar(zombie)
    if Horde.farBeats[zombie] == nil then return end
    Horde.farBeats[zombie] = nil
    Horde.plainBeat(zombie, Horde.frameNowMs or getTimestampMs())
end

function Horde.farFromPrey(zombie, now, memory, nearestFlat)
    if memory ~= nil or nearestFlat == nil then return false end
    if Horde.playerClaims[zombie] ~= nil or Horde.bites[zombie] ~= nil then return false end
    if Horde.markLive(now) then return false end
    local settings = Horde.settings
    local reach = math.max(settings.noticeTiles, settings.giveUpTiles) + 2
    return nearestFlat >= reach * reach
end

function Horde.farQuiet(zombie, now, memory, cache)
    if Horde.frameNowMs == nil then return false end
    if memory ~= nil or Horde.sprinting[zombie] ~= nil then return false end
    if Horde.playerClaims[zombie] ~= nil or Horde.bites[zombie] ~= nil then return false end
    if Horde.markLive(now) then return false end
    local data = Horde.dataOf(zombie)
    if data ~= nil and (data.ALifeHold ~= nil or data.ALifeChasePathX ~= nil) then return false end
    local zx, zy = Horde.positionOf(zombie)
    if zx == nil then return false end
    local settings = Horde.settings
    local reach = math.max(settings.noticeTiles, settings.giveUpTiles) + 2
    reach = reach * reach
    local rows = Horde.preyRows(cache)
    for index = 1, #rows do
        local row = rows[index]
        if row.body ~= zombie then
            local dx, dy = zx - row.x, zy - row.y
            if dx * dx + dy * dy < reach then return false end
        end
    end
    local okTarget, target = pcall(zombie.getTarget, zombie)
    if not okTarget or (target ~= nil and Horde.markedOurs(target)) then return false end
    Horde.metrics.farQuiet = (Horde.metrics.farQuiet or 0) + 1
    Horde.slowBeat(zombie, now, settings.farIdleMs)
    return true
end

function Horde.think(zombie, now, cleared)
    if cleared ~= true then Horde.clearNativeActorTarget(zombie) end
    refreshActorCache()

    if Horde.idleBeat(zombie) then return end
    Horde.unstick(zombie, now)
    if Horde.stunned(zombie, now) then
        if Horde.bites[zombie] ~= nil then Horde.cancelBite(zombie) end
        stopPursuit(zombie)
        return
    end
    if Horde.farQuiet(zombie, now, chaseMemory[zombie], actorCache) then return end
    local state = actionState(zombie)
    local verdict = Horde.stateVerdict(state)

    if verdict == "wait" then return end
    if #actorCache == 0 then
        if stopPursuit(zombie) then Horde.settleFree(zombie, chaseMemory[zombie]) end
        chaseMemory[zombie] = nil
        return
    end

    local targetOk, target = pcall(zombie.getTarget, zombie)
    if targetOk and target ~= nil and isOwnedActor(target) then Horde.hold(zombie, now) end

    if (Horde.biteCount or 0) > 0 and Horde.bites[zombie] ~= nil then return end
    local down = verdict == "down"
    if not down then
        local lyingOk, lying = pcall(Horde.lyingFlags, zombie)
        down = lyingOk and lying == true
    end
    if down then

        stopPursuit(zombie)
        return
    end
    if verdict == "posing" then return end

    local _, _, nearestFlat = nearestActor(zombie)
    local memory = chaseMemory[zombie]

    local spotted = targetOk and Horde.isPlayer(target)
    local choice = Horde.choosePrey(zombie, now, Horde.preyList, memory, spotted and target or nil)
    Horde.tally(choice, memory)
    if choice.kind == "none" then
        stopPursuit(zombie); chaseMemory[zombie] = nil
        if Horde.farFromPrey(zombie, now, memory, nearestFlat) then
            Horde.slowBeat(zombie, now, Horde.settings.farIdleMs)
        end

        if memory ~= nil then Horde.settleFree(zombie, memory) end
        return
    end
    if choice.kind == "player" then
        Horde.handBack(zombie, now, memory, choice, spotted)
        return
    end

    local settings = Horde.settings
    local actor, distance = choice.body, choice.row.flat
    local actorTiles = math.sqrt(distance)

    local drawn, drawnUntil = false, nil
    if choice.row.source == "named" then
        drawn, drawnUntil = true, Horde.look.markUntilMs + (Horde.look.markHoldMs or settings.gunfireHoldMs)
    elseif choice.row.source == "drawn" then
        drawn, drawnUntil = true, memory.drawnUntilMs
    end
    local freshDraw = drawn and (memory == nil or memory.prey ~= actor or memory.drawnUntilMs == nil)
    if freshDraw then
        Horde.metrics.drawn = (Horde.metrics.drawn or 0) + 1
    end
    Horde.wake(zombie)
    memory = Horde.remember(zombie, memory, actor, "actor", drawnUntil, now, choice.reason == "bump")
    if freshDraw and choice.row.source == "named" then
        local policy = ProjectALife.ZombieRetarget
        if policy ~= nil then policy.claim(Horde.look.markRow, memory, now) end
    end

    local claim = Horde.playerClaims[zombie]
    if claim ~= nil then claim.released = nil end
    Horde.hold(zombie, now)
    Horde.metrics.chases = Horde.metrics.chases + 1
    Horde.markLunge(zombie, Horde.lungeReady(zombie, actor, choice.row))
    if not drawn and actorTiles > (tonumber(settings.farChaseTiles) or 10) then
        Horde.slowBeat(zombie, now, settings.farChaseMs)
    end
    if distance >= settings.contactRangeSquared then
        Horde.markSprint(zombie)
        pursueByLocation(zombie, actor)
        return
    end
    Horde.closeIn(zombie, actor, distance, now)
end

function Horde.sealedEdge(a, b)
    if a == nil or b == nil or type(a.isBlockedTo) ~= "function"
            or type(b.isBlockedTo) ~= "function" or type(a.isHoppableTo) ~= "function" then return true end
    return a:isBlockedTo(b) == true or b:isBlockedTo(a) == true or a:isHoppableTo(b) == true
end

function Horde.mouthOpen(zombie, actor)
    local sealed = Horde.sealedEdge
    if zombie == nil or actor == nil or type(zombie.getSquare) ~= "function"
            or type(actor.getSquare) ~= "function" then return false end
    local from, to = zombie:getSquare(), actor:getSquare()
    if from == nil or to == nil then return false end
    if from == to then return true end
    if sealed(from, to) then return false end
    if type(from.getX) ~= "function" or type(from.getY) ~= "function" or type(from.getZ) ~= "function"
            or type(to.getX) ~= "function" or type(to.getY) ~= "function" then return false end
    if from:getX() == to:getX() or from:getY() == to:getY() then return true end
    if type(getCell) ~= "function" then return false end
    local cell, z = getCell(), from:getZ()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return false end
    local sideX = cell:getGridSquare(to:getX(), from:getY(), z)
    local sideY = cell:getGridSquare(from:getX(), to:getY(), z)
    return not (sealed(from, sideX) or sealed(sideX, to))
        or not (sealed(from, sideY) or sealed(sideY, to))
end

function Horde.mouthReaches(zombie, actor)
    local ok, reaches = pcall(Horde.mouthOpen, zombie, actor)
    return ok and reaches == true
end

function Horde.hopEdge(a, b)
    if a == nil or b == nil or type(a.isHoppableTo) ~= "function" or type(b.isHoppableTo) ~= "function"
            or type(a.isWindowBlockedTo) ~= "function" or type(b.isWindowBlockedTo) ~= "function"
            or type(a.isDoorBlockedTo) ~= "function" or type(b.isDoorBlockedTo) ~= "function" then
        return false
    end
    if a:isHoppableTo(b) ~= true and b:isHoppableTo(a) ~= true then return false end
    return a:isWindowBlockedTo(b) ~= true and b:isWindowBlockedTo(a) ~= true
        and a:isDoorBlockedTo(b) ~= true and b:isDoorBlockedTo(a) ~= true
end

function Horde.passable(a, b)
    return not Horde.sealedEdge(a, b) or Horde.hopEdge(a, b)
end

function Horde.climbable(zombie, actor)
    if zombie == nil or actor == nil or type(zombie.getSquare) ~= "function"
            or type(actor.getSquare) ~= "function" then return false end
    local from, to = zombie:getSquare(), actor:getSquare()
    if from == nil or to == nil or from == to or type(from.getX) ~= "function" or type(from.getY) ~= "function"
            or type(from.getZ) ~= "function" or type(to.getX) ~= "function" or type(to.getY) ~= "function"
            or type(to.getZ) ~= "function" then return false end
    local fx, fy, tx, ty, z = from:getX(), from:getY(), to:getX(), to:getY(), from:getZ()
    if z ~= to:getZ() or math.abs(fx - tx) > 1 or math.abs(fy - ty) > 1 then return false end
    if fx == tx or fy == ty then return Horde.hopEdge(from, to) end
    if type(getCell) ~= "function" then return false end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return false end
    local sideX, sideY = cell:getGridSquare(tx, fy, z), cell:getGridSquare(fx, ty, z)
    return (sideX ~= nil and Horde.passable(from, sideX) and Horde.passable(sideX, to))
        or (sideY ~= nil and Horde.passable(from, sideY) and Horde.passable(sideY, to))
end

function Horde.climbs(zombie, actor)
    local ok, climbs = pcall(Horde.climbable, zombie, actor)
    return ok and climbs == true
end

function Horde.inBiteCone(zombie, actor)
    local forward = zombie:getForwardDirection()
    local dx, dy = actor:getX() - zombie:getX(), actor:getY() - zombie:getY()
    local fx, fy = forward:getX(), forward:getY()
    local scale = math.sqrt((dx * dx + dy * dy) * (fx * fx + fy * fy))
    return scale > 0 and (fx * dx + fy * dy) / scale >= Horde.settings.biteConeCos
end

function Horde.turnToward(zombie, actor)
    zombie:faceLocationF(actor:getX(), actor:getY())
end

function Horde.facesVictim(zombie, actor)
    local coneOk, facing = pcall(Horde.inBiteCone, zombie, actor)
    if coneOk and facing then return true end
    pcall(Horde.turnToward, zombie, actor)
    return false
end

function Horde.victimDown(actor)
    local drag = Horde.dragging[actor]
    if drag ~= nil and drag.lying == true then return true end
    if Horde.isDownState(actionState(actor)) then return true end
    local grounded = false
    pcall(function() grounded = actor:isOnFloor() == true end)
    return grounded
end

function Horde.contactGrace(zombie, now, settings, actor)
    local data = zombie:getModData()
    local since = tonumber(data.ALifeContactSinceMs)
    local victim = Horde.dataOf(actor)
    local uid = victim ~= nil and victim.ProjectALifeUID or tostring(actor)
    if since == nil or data.ALifeContactUID ~= uid then
        data.ALifeContactSinceMs = now
        data.ALifeContactUID = uid
        Horde.metrics.contacts = (Horde.metrics.contacts or 0) + 1
    elseif now - since >= settings.contactGraceMs then
        return true
    end
    return false
end

function Horde.victimPresent(actor)
    local present = actor:isDead() ~= true and actor:getCurrentSquare() ~= nil
    return present
end

function Horde.closeIn(zombie, actor, distance, now)
    local settings = Horde.settings
    local reaches = Horde.mouthReaches(zombie, actor)
    if not reaches and Horde.climbs(zombie, actor) then
        Horde.markSprint(zombie)
        pursueByLocation(zombie, actor)
        return Horde.biteWait("climb")
    end

    Horde.endChase(zombie)
    local graceCall, graceOk = pcall(Horde.contactGrace, zombie, now, settings, actor)
    if not (graceCall and graceOk == true) then return Horde.biteWait("grace") end
    if not reaches then
        Horde.metrics.blocked = (Horde.metrics.blocked or 0) + 1
        return Horde.biteWait("edge")
    end
    if distance > settings.overlapSquared and not Horde.facesVictim(zombie, actor) then
        Horde.metrics.blocked = (Horde.metrics.blocked or 0) + 1
        return Horde.biteWait("facing")
    end
    local bumpOk, bump = pcall(zombie.getBumpType, zombie)
    if bumpOk and Horde.isBiteName(bump) then
        Horde.renameBite(zombie, bump)
        return
    end

    local presentCall, present = pcall(Horde.victimPresent, actor)
    present = presentCall and present == true
    if not present then
        Horde.metrics.bitesRefused = (Horde.metrics.bitesRefused or 0) + 1
        stopPursuit(zombie)
        return
    end

    if not Horde.teethReady(actor, zombie, now) then return end
    local nextPose = Horde.poseGapUntil(zombie, now)
    if nextPose ~= nil and now < nextPose then return end
    Horde.startBite(zombie, actor, now)
end

function Horde.poseGapUntil(zombie, now)
    local poseOk, poseData = pcall(zombie.getModData, zombie)
    local nextPose
    if poseOk and type(poseData) == "table" then nextPose = tonumber(poseData.ALifeNextBitePoseAtMs) end
    if nextPose ~= nil and now < nextPose then Horde.biteWait("pose_gap") end
    return nextPose
end

function Horde.startBite(zombie, actor, now)

    Horde.wake(zombie)
    local low = Horde.victimDown(actor)

    Horde.metrics.bites = Horde.metrics.bites + 1
    markBiteWindow(actor, Horde.settings.biteWindowMs)
    pcall(function() actor:setZombiesDontAttack(true) end)
    local claw = false
    if not low and Horde.tuning.attackAnims == true and type(ZombRand) == "function" then
        claw = ZombRand(100) < Horde.tuning.scratchPercent
    end
    local typed = Horde.tuning.attackAnims == true
    playBite(zombie, low, claw, typed)
    pcall(function()
        local spread = type(ZombRand) == "function" and ZombRand(Horde.settings.bitePoseSpreadMs + 1) or 0
        zombie:getModData().ALifeNextBitePoseAtMs = now + Horde.settings.bitePoseGapMs + spread
    end)

    pcall(function()
        local data = actor:getModData()
        local perception = ProjectALife.Perception
        if type(data) == "table" and perception ~= nil
                and type(perception.noteAttacker) == "function"
                and type(data.ProjectALifeUID) == "string" then
            perception.noteAttacker(data.ProjectALifeUID, zombie, Horde.settings.retaliateMs, "zombie")
        end
    end)
    openBite(zombie, actor, low, claw, typed)
    Horde.bites[zombie].openedAtMs = now
    Horde.checkDrag(actor, zombie, now)
end

function Horde.noteCorpse(body)
    if body == nil or type(body.getModData) ~= "function" then return end
    if type(body.hasModData) == "function" and body:hasModData() ~= true then return end
    local data = body:getModData()
    if type(data) ~= "table" or (data.ProjectALifeCorpseOf == nil and data.ProjectALifeUID == nil) then return end
    local x, y, z = Horde.positionOf(body)
    if x == nil then return end
    local corpses = Horde.corpses
    if #corpses >= (tonumber(Horde.settings.corpseLimit) or 16) then table.remove(corpses, 1) end
    corpses[#corpses + 1] = { body = body, x = x, y = y, z = z }
end

function Horde.corpseLive(row)
    local body = nil
    if row ~= nil then body = row.body end
    if body == nil or type(body.getStaticMovingObjectIndex) ~= "function" then return false end
    return body:getStaticMovingObjectIndex() ~= -1
end

function Horde.hungry(zombie)
    if zombie == nil or isOwnedActor(zombie) or not isAlive(zombie) then return false end
    if type(zombie.setBodyToEat) ~= "function" or type(zombie.getEatBodyTarget) ~= "function"
            or type(zombie.getTarget) ~= "function" then return false end
    if zombie:getEatBodyTarget() ~= nil or zombie:getTarget() ~= nil then return false end
    if type(zombie.isCrawling) == "function" and zombie:isCrawling() == true then return false end
    if chaseMemory[zombie] ~= nil or Horde.bites[zombie] ~= nil then return false end
    return actionState(zombie) == "idle"
end

function Horde.eatersOf(body)
    if type(body.getEatingZombies) ~= "function" then return 0 end
    local eaters = body:getEatingZombies()
    if eaters == nil or type(eaters.size) ~= "function" then return 0 end
    return tonumber(eaters:size()) or 0
end

function Horde.corpseFor(zombie)
    local zx, zy, zz = Horde.positionOf(zombie)
    if zx == nil then return nil end
    local settings = Horde.settings
    local reach = tonumber(settings.feedTiles) or 10
    local best, bestFlat = nil, reach * reach
    for index = 1, #Horde.corpses do
        local row = Horde.corpses[index]
        local dx, dy = row.x - zx, row.y - zy
        local flat = dx * dx + dy * dy
        if flat < bestFlat and math.abs(row.z - zz) < settings.floorBand
                and Horde.eatersOf(row.body) < (tonumber(settings.feedEaters) or 3)
                and Horde.lungeLine(zombie, row.body) then
            best, bestFlat = row, flat
        end
    end
    return best
end

function Horde.feed(now)
    local corpses = Horde.corpses
    for index = #corpses, 1, -1 do
        if not Horde.corpseLive(corpses[index]) then table.remove(corpses, index) end
    end
    if #corpses == 0 or type(getCell) ~= "function" then return 0 end
    local cell = getCell()
    if cell == nil or type(cell.getZombieList) ~= "function" then return 0 end
    local list = cell:getZombieList()
    if list == nil or type(list.size) ~= "function" or type(list.get) ~= "function" then return 0 end
    local fed = 0
    for index = 0, list:size() - 1 do
        local zombie = list:get(index)
        if Horde.hungry(zombie) and Horde.steersHere(zombie) then
            local row = Horde.corpseFor(zombie)
            if row ~= nil then
                zombie:setBodyToEat(row.body)
                fed = fed + 1
            end
        end
    end
    Horde.metrics.fed = (Horde.metrics.fed or 0) + fed
    return fed
end

function Horde.feedBeat()
    if #Horde.corpses == 0 or not Horde.enabled then return end
    local now = Horde.frameNowMs or getTimestampMs()
    if now < (Horde.feedAtMs or 0) then return end
    Horde.feedAtMs = now + (tonumber(Horde.settings.feedEveryMs) or 3000)
    pcall(Horde.feed, now)
end

Horde.gunfire = nil

function Horde.provoke(zombie, actor)
    if zombie == nil or actor == nil then return end
    if isOwnedActor(zombie) then return end
    local untilMs = getTimestampMs() + Horde.settings.hitWindowMs
    local memory = chaseMemory[zombie]
    if memory == nil then
        chaseMemory[zombie] = { provoked = actor, provokedUntilMs = untilMs }
    else
        memory.provoked, memory.provokedUntilMs = actor, untilMs
    end
    Horde.recallFar(zombie)
end

function Horde.stunMs()
    return math.floor(Horde.sandboxNumber("Combat_ZombieStunMs", 1100, 0, 3000))
end

function Horde.stunned(zombie, now)
    local data = Horde.dataOf(zombie)
    local untilMs = data ~= nil and tonumber(data.ALifeStunUntilMs) or nil
    if untilMs == nil then return false end
    if (tonumber(now) or getTimestampMs()) >= untilMs then
        data.ALifeStunUntilMs = nil
        return false
    end
    return true
end

function Horde.cancelBite(zombie)
    if Horde.bites[zombie] == nil then return false end
    pcall(function()
        zombie:setBumpType("")
        zombie:setBumpDone(true)
        zombie:setVariable("BumpDone", true)
        zombie:setVariable("BumpAnimFinished", true)
    end)
    clearBite(zombie)
    Horde.metrics.bitesCut = (Horde.metrics.bitesCut or 0) + 1
    return true
end

function Horde.stun(zombie, attacker, durationMs)
    if zombie == nil or not Horde.enabled or isOwnedActor(zombie) or not isAlive(zombie) then return false end
    local span = tonumber(durationMs) or Horde.stunMs()
    if span <= 0 then return false end
    local data = Horde.dataOf(zombie)
    if data == nil then return false end
    local now = Horde.frameNowMs or getTimestampMs()
    if now + span > (tonumber(data.ALifeStunUntilMs) or 0) then data.ALifeStunUntilMs = now + span end
    local bite = Horde.bites[zombie]
    if bite ~= nil and bite.landed ~= true then Horde.cancelBite(zombie) end
    stopPursuit(zombie)
    Horde.metrics.stunned = (Horde.metrics.stunned or 0) + 1
    return true
end

function Horde.noteGunfire(shooter, radius, untilMs, holdMs)
    local reach = math.min(tonumber(radius) or 20, Horde.settings.gunfireNoticeTiles)
    local now = Horde.frameNowMs
    if now == nil and type(getTimestampMs) == "function" then now = getTimestampMs() end
    now = now or 0
    local policy = ProjectALife.ZombieRetarget
    local newEvent = policy == nil or policy.markVerdict(shooter, now)
    local marks, fresh, mark = Horde.marks, {}, nil
    for index = 1, #marks do
        local entry = marks[index]
        if entry.shooter == shooter then mark = entry
        elseif now < (tonumber(entry.untilMs) or 0) and #fresh < Horde.markLimit - 1 then
            fresh[#fresh + 1] = entry
        end
    end
    local squared = reach * reach
    if mark == nil then
        mark = { shooter = shooter }
    elseif now < (tonumber(mark.untilMs) or 0) then
        if (mark.radiusSquared or 0) > squared then squared = mark.radiusSquared end
        if (mark.holdMs or 0) > (tonumber(holdMs) or 0) then holdMs = mark.holdMs end
    end
    mark.radiusSquared, mark.untilMs, mark.holdMs = squared, tonumber(untilMs) or 0, holdMs
    if newEvent then mark.drawCount = 0 end
    fresh[#fresh + 1] = mark
    Horde.marks = fresh
    Horde.gunfire = mark

    if newEvent then Horde.recallAllFar() end
end

function Horde.noteMelee(shooter, untilMs)
    local settings = Horde.settings
    local now = Horde.frameNowMs
    if now == nil and type(getTimestampMs) == "function" then now = getTimestampMs() end
    now = now or 0
    local marks = Horde.marks
    for index = 1, #marks do
        local mark = marks[index]
        if mark.shooter == shooter and now < (tonumber(mark.untilMs) or 0) - 2000 then return end
    end
    Horde.metrics.meleeNoise = (Horde.metrics.meleeNoise or 0) + 1
    Horde.noteGunfire(shooter, settings.meleeNoticeTiles, untilMs, settings.meleeHoldMs)
end

function Horde.reset()
    for actor in pairs(Horde.dragging) do Horde.clearDrag(actor) end
    Horde.dragging = {}
    Horde.tuneAtMs = 0
    Horde.bites = setmetatable({}, { __mode = "k" })
    Horde.biteCount = 0
    Horde.playerClaims = setmetatable({}, { __mode = "k" })
    nextThinkAt = setmetatable({}, { __mode = "k" })
    actorCache, actorCacheAtMs = {}, 0
    Horde.gunfire = nil
    Horde.marks = {}
    if ProjectALife.ZombieRetarget ~= nil then ProjectALife.ZombieRetarget.reset() end
    Horde.markCache = { marks = {}, xs = {}, ys = {}, count = 0 }
    Horde.quietMemo = setmetatable({}, { __mode = "k" })

    Horde.frameNowMs, Horde.roster = nil, nil
    Horde.rosterListed, Horde.rosterAtMs = nil, nil
    Horde.preyList, Horde.preyAtMs = nil, nil
    Horde.beatPhase = 0
    Horde.farBeats = {}
    Horde.lowerMemo, Horde.lowerMemoSize = {}, 0
    Horde.verdictMemo, Horde.verdictMemoSize = {}, 0
    Horde.memoLimit = 256
    Horde.dropAllSprints()
    Horde.lunging = setmetatable({}, { __mode = "k" })
    Horde.senseAnswer, Horde.senseUntil, Horde.senseCount = {}, {}, 0
    Horde.sightMemo = setmetatable({}, { __mode = "k" })
    Horde.rayStamp, Horde.rayCount = nil, 0
    Horde.targetStats = nil
    Horde.preyIds, Horde.preyIdCount = {}, 0
    Horde.dealNear, Horde.dealMine, Horde.dealMarked = {}, {}, {}
    Horde.picks, Horde.look, Horde.choice = {}, {}, { kind = "none" }
    local metrics = Horde.metrics
    metrics.biteWaits = type(metrics.biteWaits) == "table" and metrics.biteWaits or {}
    metrics.biteMisses = type(metrics.biteMisses) == "table" and metrics.biteMisses or {}
    metrics.wounds = type(metrics.wounds) == "table" and metrics.wounds or {}
    metrics.infections, metrics.lunges, metrics.fed = metrics.infections or 0, metrics.lunges or 0, metrics.fed or 0
    metrics.stunned, metrics.bitesCut = metrics.stunned or 0, metrics.bitesCut or 0
    metrics.pathHeld, metrics.pathBudget = metrics.pathHeld or 0, metrics.pathBudget or 0
    metrics.pathStalled = metrics.pathStalled or 0
    metrics.pathLatencyCount, metrics.pathLatencySumMs = metrics.pathLatencyCount or 0, metrics.pathLatencySumMs or 0
    metrics.pathLatencyMaxMs = metrics.pathLatencyMaxMs or 0
    Horde.pathBucket = { tokens = 0 }
    Horde.corpses, Horde.feedAtMs = {}, 0
    metrics.sightRefused = metrics.sightRefused or 0
    metrics.sightRays = metrics.sightRays or 0
    metrics.switched = metrics.switched or 0
    metrics.bumped = metrics.bumped or 0
    local settings = Horde.settings
    settings.farIdleMs = settings.farIdleMs or 1000
    settings.farChaseMs = settings.farChaseMs or 600
    settings.farChaseTiles = settings.farChaseTiles or 10
    settings.nearHalfTiles = settings.nearHalfTiles or 5
    settings.switchRatio = settings.switchRatio or 1.15
    settings.preyHoldMs = settings.preyHoldMs or 1200
    settings.awareSeen = settings.awareSeen or 1.0
    settings.awareSensed = settings.awareSensed or 0.5
    settings.awareNamed = settings.awareNamed or 0.8
    settings.awareSpotted = settings.awareSpotted or 1.0
    settings.hitWeight = settings.hitWeight or 3
    settings.hitWindowMs = settings.hitWindowMs or 9000
    settings.preyWeight = settings.preyWeight or 1.0
    settings.vehicleWeight = settings.vehicleWeight or 0.5
    settings.rayFrameCap = settings.rayFrameCap or 120
    settings.rememberMs = settings.rememberMs or 3000
    settings.awareRemembered = settings.awareRemembered or 0.9
    settings.meleeNoticeTiles = settings.meleeNoticeTiles or 10
    settings.meleeHoldMs = settings.meleeHoldMs or 5000
    settings.senseTiles = settings.senseTiles or 4
    settings.repathMs = settings.repathMs or 900
    settings.repathMaxMs = settings.repathMaxMs or 6400
    settings.pathWaitMs = settings.pathWaitMs or 4000
    settings.pathGoalTiles = settings.pathGoalTiles or 2.5
    settings.pathPerSecond = settings.pathPerSecond or 16
    settings.pathBurst = settings.pathBurst or 8
end

function Horde.auditLines(actor, lines)
    if actor == nil or type(lines) ~= "table" or type(getCell) ~= "function"
            or type(actor.getX) ~= "function" or type(actor.getY) ~= "function"
            or type(actor.getZ) ~= "function" or type(actor.getModData) ~= "function" then return end
    local cell = getCell()
    if cell == nil or type(cell.getZombieList) ~= "function" then return end
    local list = cell:getZombieList()
    if list == nil or type(list.size) ~= "function" or type(list.get) ~= "function" then return end
    local ax, ay, az, data = actor:getX(), actor:getY(), actor:getZ(), actor:getModData()
    local now = type(getTimestampMs) == "function" and getTimestampMs() or 0
    local count = 0
    for index = 0, list:size() - 1 do
        local zombie = list:get(index)
        if zombie ~= nil and zombie ~= actor and type(zombie.getX) == "function"
                and type(zombie.getY) == "function" and type(zombie.getZ) == "function"
                and type(zombie.getModData) == "function" and not Horde.markedOurs(zombie) then
            local dx, dy, dz = zombie:getX() - ax, zombie:getY() - ay, zombie:getZ() - az
            local flat = dx * dx + dy * dy
            if flat <= 900 then
                local memory, bite = chaseMemory[zombie], Horde.bites[zombie]
                local chasing = memory ~= nil and memory.prey == actor
                local contact = flat < Horde.settings.contactRangeSquared and math.abs(dz) < Horde.settings.floorBand
                local seen = "unknown"
                if now < (Horde.senseUntil[zombie] or 0) then
                    seen = tostring(Horde.senseAnswer[zombie] == actor)
                end
                local preyText = ""
                if memory ~= nil and memory.prey ~= nil and memory.prey ~= actor then
                    local px, py = Horde.positionOf(memory.prey)
                    preyText = " preyKind=" .. tostring(memory.kind)
                    if px ~= nil then
                        preyText = preyText .. " preyDist=" .. string.format("%.1f",
                            math.sqrt((px - zombie:getX()) ^ 2 + (py - zombie:getY()) ^ 2))
                    end
                end
                local refused = "no_chase_record"
                if not Horde.enabled then refused = "disabled"
                elseif math.abs(dz) >= Horde.settings.floorBand then refused = "floor"
                elseif bite ~= nil and bite.actor == actor then refused = "none"
                elseif memory ~= nil and memory.prey ~= actor then refused = "other_prey"
                elseif chasing then refused = "none" end
                local id = type(zombie.getID) == "function" and zombie:getID() or "unknown"
                lines[#lines + 1] = "[ALIFE-HORDE] zombie=" .. tostring(id)
                    .. " npc=" .. tostring(type(data) == "table" and data.ProjectALifeUID or "unknown")
                    .. " dist=" .. string.format("%.2f", math.sqrt(flat)) .. " seen=" .. seen
                    .. " chasing=" .. tostring(chasing) .. " contact=" .. tostring(contact)
                    .. " bite=" .. tostring(bite ~= nil and bite.actor == actor) .. " refusedBy=" .. refused .. preyText
                count = count + 1
                if count >= 128 then return end
            end
        end
    end
end

function Horde.register()
    if Horde.registered then return true end
    if type(Events) ~= "table" or Events.OnZombieUpdate == nil
            or type(Events.OnZombieUpdate.Add) ~= "function" then
        return false, "on_zombie_update_unavailable"
    end
    Events.OnZombieUpdate.Add(Horde.guard("onZombieUpdate", Horde.zombieEntry))
    if Events.OnHitZombie ~= nil and type(Events.OnHitZombie.Add) == "function" then
        Events.OnHitZombie.Add(Horde.onPlayerHitZombie)
    end

    local frame = Events.OnTickEvenPaused or Events.OnTick
    if frame ~= nil and type(frame.Add) == "function" then
        frame.Add(Horde.guard("stampFrame", Horde.stampFrame))
    end
    if Events.OnDeadBodySpawn ~= nil and type(Events.OnDeadBodySpawn.Add) == "function" then
        Events.OnDeadBodySpawn.Add(Horde.noteCorpse)
    end
    Horde.registered = true
    return true
end

Horde.register()

return Horde
