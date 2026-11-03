require "ProjectALife/Audio/ALifeInteractionCues"

ProjectALife = ProjectALife or {}

local Frisk = {
    startTiles = 2.0,
    standTiles = 1.15,
    abortTiles = 3.5,
    maxAborts = 2,
    short = { { "search_high", 0.4 }, { "search_mid", 0.35 }, { "search_low", 0.25 } },
    long = { { "search_high", 0.25 }, { "search_mid", 0.25 }, { "search_low", 0.25 }, { "search_mid", 0.25 } },
    adapters = {},
    metrics = { started = 0, completed = 0, aborted = 0, picks = 0, fallbackPicks = 0, soundsPlayed = 0,
        soundStops = 0, poses = 0, bySound = {} },
}
ProjectALife.Frisk = Frisk

function Frisk.reset()
    Frisk.metrics = { started = 0, completed = 0, aborted = 0, picks = 0, fallbackPicks = 0, soundsPlayed = 0,
        soundStops = 0, poses = 0, bySound = {} }
end

function Frisk.enabled()
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(vars) ~= "table" then return true end
    return vars.Robbery_FriskScripted ~= false
end

function Frisk.xy(object)
    if object == nil or type(object.getX) ~= "function" or type(object.getY) ~= "function" then return nil end
    return object:getX(), object:getY()
end

function Frisk.gap(a, b)
    local ax, ay = Frisk.xy(a)
    local bx, by = Frisk.xy(b)
    if ax == nil or bx == nil then return math.huge end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

function Frisk.fit(state, uid)
    local registry = ProjectALife.ModuleRegistry
    local actors = ProjectALife.ActorRegistry
    local record = actors ~= nil and actors.read(uid) or nil
    if registry ~= nil and type(registry.conductOf) == "function" and record ~= nil
            and registry.conductOf(record) == "medic" then return false end
    local robbery = ProjectALife.ModuleRobbery
    local shell = robbery ~= nil and robbery.shellFor(uid) or nil
    local animations = ProjectALife.Animations
    if shell ~= nil and animations ~= nil and type(animations.bodyDown) == "function" and animations.bodyDown(shell) then
        return false
    end
    return true
end

function Frisk.nearest(state, pool)
    local robbery = ProjectALife.ModuleRobbery
    local best, bestGap = nil, math.huge
    for _, uid in ipairs(pool) do
        local gap = Frisk.gap(robbery.shellFor(uid), state.player)
        if best == nil or gap < bestGap or (gap == bestGap and tostring(uid) < tostring(best)) then best, bestGap = uid, gap end
    end
    return best
end

function Frisk.pick(state, skip)
    local hands, guns = {}, {}
    for _, uid in ipairs(state.members) do
        if uid ~= skip and uid ~= state.leaderUid and Frisk.fit(state, uid) then
            if state.roles[uid] == "gun" then guns[#guns + 1] = uid else hands[#hands + 1] = uid end
        end
    end
    Frisk.metrics.picks = Frisk.metrics.picks + 1
    local pool = #hands > 0 and hands or guns
    if #pool > 0 then return Frisk.nearest(state, pool) end
    Frisk.metrics.fallbackPicks = Frisk.metrics.fallbackPicks + 1
    return state.leaderUid or state.members[1]
end

function Frisk.plan(seconds)
    seconds = tonumber(seconds) or 0
    local rows = seconds >= 5 and Frisk.long or Frisk.short
    local total = math.floor(seconds * 1000 + 0.5)
    local plan, share = {}, 0
    for index, row in ipairs(rows) do
        plan[index] = { id = row[1], atMs = math.floor(total * share) }
        share = share + row[2]
    end
    return plan
end

function Frisk.pose(state, f, shell, now)
    local animations = ProjectALife.Animations
    if animations == nil or type(animations.apply) ~= "function" or shell == nil then return false end
    local elapsed = now - f.startedAtMs
    local index = 1
    for position, row in ipairs(f.plan) do
        if elapsed >= row.atMs then index = position end
    end
    if f.segment == index and animations.current ~= nil and animations.current[shell] == f.plan[index].id then return true end
    f.segment = index
    local ok, applied = pcall(animations.apply, shell, f.plan[index].id, true)
    if ok and applied == true then Frisk.metrics.poses = Frisk.metrics.poses + 1 end
    return ok and applied == true
end

function Frisk.stopSound(shell, id)
    if type(id) ~= "string" then return false end
    if type(Frisk.adapters.stopSound) == "function" then return Frisk.adapters.stopSound(shell, id) == true end
    if shell == nil or type(shell.getEmitter) ~= "function" then return false end
    local stopped = false
    pcall(function()
        local emitter = shell:getEmitter()
        if emitter ~= nil and type(emitter.stopSoundByName) == "function" then
            emitter:stopSoundByName(id)
            stopped = true
        end
    end)
    if stopped then Frisk.metrics.soundStops = Frisk.metrics.soundStops + 1 end
    return stopped
end

function Frisk.stop(state, early)
    local f = state.frisk
    if f == nil then return false end
    state.frisk = nil
    local robbery = ProjectALife.ModuleRobbery
    local shell = robbery ~= nil and robbery.shellFor(f.uid) or nil
    if early == true and f.soundId ~= nil then Frisk.stopSound(shell, f.soundId) end
    local animations = ProjectALife.Animations
    if shell ~= nil and animations ~= nil and type(animations.clear) == "function" then pcall(animations.clear, shell) end
    return true
end

function Frisk.start(state, shell, now)
    local cues = ProjectALife.InteractionCues
    local uid = state.grabberUid
    local id, seconds
    if cues ~= nil then id, seconds = cues.pick("frisk", uid) end
    if id == nil then
        id, seconds = nil, (tonumber(ProjectALife.ModuleRobbery.settings.searchMs) or 6000) / 1000
    end
    local f = { uid = uid, soundId = id, seconds = seconds, startedAtMs = now,
        endsAtMs = now + math.floor(seconds * 1000 + 0.5), plan = Frisk.plan(seconds), segment = 0 }
    state.frisk, state.searchSaid, state.searchAtMs = f, true, now
    Frisk.metrics.started = Frisk.metrics.started + 1
    if id ~= nil then
        Frisk.metrics.bySound[id] = (Frisk.metrics.bySound[id] or 0) + 1
        if cues.play(shell, id) then Frisk.metrics.soundsPlayed = Frisk.metrics.soundsPlayed + 1 end
    end
    Frisk.pose(state, f, shell, now)
    ProjectALife.ModuleRobbery.broadcastPhase(state)
    return f
end

function Frisk.abort(state, now)
    Frisk.stop(state, true)
    Frisk.metrics.aborted = Frisk.metrics.aborted + 1
    state.friskAborts = (state.friskAborts or 0) + 1
    state.searchSaid, state.grabberSentAtMs = false, now
    state.grabberRetries = 0
    ProjectALife.ModuleRobbery.broadcastPhase(state)
    return "aborted"
end

function Frisk.advance(state, now)
    local robbery = ProjectALife.ModuleRobbery
    local settings = robbery.settings
    state.grabberSentAtMs = state.grabberSentAtMs or state.phaseAtMs
    if state.grabberUid == nil or not robbery.memberLives(state, state.grabberUid) then
        Frisk.stop(state, true)
        state.grabberUid, state.grabberSentAtMs, state.searchSaid = robbery.pickGrabber(state), now, false
        robbery.broadcastPhase(state)
    end
    local frisker = robbery.shellFor(state.grabberUid)
    local gap = Frisk.gap(frisker, state.player)
    local f = state.frisk
    if f ~= nil then
        if gap > Frisk.abortTiles then return Frisk.abort(state, now) end
        if now >= f.endsAtMs then
            Frisk.stop(state, false)
            Frisk.metrics.completed = Frisk.metrics.completed + 1
            return "release"
        end
        Frisk.pose(state, f, frisker, now)
        return nil
    end
    if gap <= Frisk.startTiles then
        Frisk.start(state, frisker, now)
        return nil
    end
    if now - state.grabberSentAtMs >= settings.grabberRetryMs and (state.grabberRetries or 0) < settings.grabberRetries
            and #state.members > 1 then
        state.grabberRetries = (state.grabberRetries or 0) + 1
        state.grabberUid, state.grabberSentAtMs, state.searchSaid = robbery.pickGrabber(state, state.grabberUid), now, false
        robbery.metrics.regrabbed = (robbery.metrics.regrabbed or 0) + 1
        robbery.broadcastPhase(state)
    end
    if now - state.phaseAtMs >= settings.searchTimeoutMs then
        robbery.metrics.outOfReach = (robbery.metrics.outOfReach or 0) + 1
        return "release"
    end
    return nil
end

return Frisk
