ProjectALife = ProjectALife or {}

require "ProjectALife/Records/ALifeCustomProfiles"
require "ProjectALife/Interface/Creator/ALifeCreatorCore"

local Creator = ProjectALife.CreatorScreen

local Queue = {
    jobs = {},
    active = nil,
    failedAt = {},
    retryMs = 5000,
    maxAttempts = 3,
    maxRestarts = 6,
    warmEvery = 4,
    frame = 0,
    stepGapMs = 6,
    lastStepEnd = nil,
    lastSource = nil,
    seenClock = nil,
    clockAdvances = false,
    noticeText = nil,
    noticeUntil = 0,
    openWhenIdle = false,
}
ProjectALife.CreatorSaveQueue = Queue
Creator.saveQueue = Queue

local legacy = {
    begin = Creator.beginProfileSave,
    step = Creator.stepProfileSave,
    flush = Creator.flushEdits,
    open = Creator.open,
}
Queue.legacy = legacy

function Queue.clock()
    if type(getTimestampMs) ~= "function" then return 0 end
    return tonumber(getTimestampMs()) or 0
end

function Queue.enabled()
    if type(isClient) == "function" and isClient() then return false end
    local prefs = ProjectALife.MenuPrefs
    if prefs ~= nil and type(prefs.creatorAsyncSaveOn) == "function" then return prefs.creatorAsyncSaveOn() == true end
    return true
end

function Queue.busy()
    return Queue.active ~= nil or #Queue.jobs > 0
end

function Queue.submitted(id, signature)
    local active = Queue.active
    if active ~= nil and active.id == id and active.signature == signature then return true end
    for _, job in ipairs(Queue.jobs) do
        if job.id == id and job.signature == signature then return true end
    end
    return false
end

function Queue.pendingFor(id)
    if Queue.active ~= nil and Queue.active.id == id then return true end
    for _, job in ipairs(Queue.jobs) do
        if job.id == id then return true end
    end
    return false
end

function Queue.say(text)
    Queue.noticeText, Queue.noticeUntil = text, Queue.clock() + 4000
    if type(getSpecificPlayer) ~= "function" then return false end
    local player = getSpecificPlayer(0)
    local helper = HaloTextHelper
    if player == nil or helper == nil or type(helper.addText) ~= "function" then return false end
    return pcall(helper.addText, player, text)
end

function Queue.menuText()
    if Queue.busy() then return "Saving NPC..." end
    if Queue.noticeText ~= nil then
        if Queue.clock() < Queue.noticeUntil then return Queue.noticeText end
        Queue.noticeText = nil
    end
    return nil
end

function Queue.submit(window, profile, signature)
    local job = { id = profile.id, profile = profile, signature = signature, window = window, attempts = 0, restarts = 0 }
    for index = #Queue.jobs, 1, -1 do
        if Queue.jobs[index].id == job.id then table.remove(Queue.jobs, index) end
    end
    Queue.jobs[#Queue.jobs + 1] = job
    return job
end

function Queue.begin(window)
    if Creator.seasonalJob then return false end
    if not window.currentProfile or not window.currentFaction then return true end
    local profile = Creator.harvestProfile(window)
    if not profile then return true end
    profile.general.faction = window.currentFaction.id
    local signature = Creator.signature(profile)
    if Queue.submitted(profile.id, signature) then return false end
    local failed = Queue.failedAt[profile.id]
    if failed ~= nil and Queue.clock() - failed < Queue.retryMs then return false end
    local Custom = ProjectALife.CustomProfiles
    local snapshot = Custom.copyPreparedRecord(profile)
    Queue.submit(window, snapshot, signature)
    Creator.applyProfileRecord(window, Custom.copyPreparedRecord(snapshot))
    if window.saveError == "Could not save NPC. Your edits are still open." then window.saveError = nil end
    Creator.paintSaveStatus(window.saveStateLabel, "SAVING", "saving")
    return false
end

function Queue.requeue(job)
    for _, other in ipairs(Queue.jobs) do
        if other.id == job.id then return false end
    end
    table.insert(Queue.jobs, 1, job)
    return true
end

function Queue.settle(job)
    if Queue.active == job then Queue.active = nil end
    if job.handle ~= nil then
        ProjectALife.CustomProfiles.cancelPrepared(job.handle)
        job.handle = nil
    end
end

function Queue.fail(job, reason)
    Queue.settle(job)
    job.attempts = job.attempts + 1
    print("[ProjectALife] Creator background save problem for " .. tostring(job.id) .. ": " .. tostring(reason)
        .. " attempt " .. tostring(job.attempts))
    if job.attempts < Queue.maxAttempts then
        job.retryAt = Queue.clock() + 1500
        Queue.requeue(job)
        return
    end
    Queue.failedAt[job.id] = Queue.clock()
    local window = job.window
    if window ~= nil and Creator.window == window then
        if window.currentProfile and window.currentProfile.id == job.id and window.profileBaseline == job.signature then
            window.profileBaseline = "unsaved|" .. tostring(job.signature)
        end
        window.saveError = "Could not save NPC. Your edits are still open."
        Creator.paintSaveStatus(window.saveStateLabel, window.saveError, "error")
    end
    Queue.say("NPC save failed")
    if type(Creator.notifyCue) == "function" then Creator.notifyCue("error") end
    Queue.afterJob()
end

function Queue.afterJob()
    if Queue.busy() then return end
    local window = Creator.window
    if window ~= nil then window.profileSaveRetryNotice = nil end
    if Queue.openWhenIdle then
        Queue.openWhenIdle = false
        local ok, result = pcall(Creator.open)
        if not ok then print("[ProjectALife] Creator open failed: " .. tostring(result)) end
    end
end

function Queue.commit(job)
    local Custom = ProjectALife.CustomProfiles
    local saved = Custom.savePrepared(job.profile, job.handle)
    if not saved then
        Queue.fail(job, "commit_refused")
        return
    end
    job.handle = nil
    Queue.settle(job)
    Queue.failedAt[job.id] = nil
    local window = job.window
    if window ~= nil and Creator.window == window and window.currentProfile and window.currentProfile.id == job.id then
        if window.saveError == "Could not save NPC. Your edits are still open." then window.saveError = nil end
    end
    if Creator.window == nil then Queue.say("NPC saved") end
    if type(Creator.notifyCue) == "function" then Creator.notifyCue("saved") end
    Queue.afterJob()
end

function Queue.nextJob()
    local now = Queue.clock()
    for index, job in ipairs(Queue.jobs) do
        if job.retryAt == nil or job.retryAt <= now then
            table.remove(Queue.jobs, index)
            return job
        end
    end
    return nil
end

function Queue.stepChecked(job)
    local Custom = ProjectALife.CustomProfiles
    local ran, ok, ready = pcall(Custom.stepPrepared, job.handle)
    if not ran then return Queue.fail(job, "step_error") end
    if not ok then
        if not Custom.preparationCurrent(job.handle) and job.restarts < Queue.maxRestarts then
            job.restarts = job.restarts + 1
            Queue.settle(job)
            Queue.requeue(job)
            return
        end
        return Queue.fail(job, "step_failed")
    end
    if ready == true then Queue.commit(job) end
end

function Queue.fresh(source)
    local now = Queue.clock()
    if Queue.seenClock ~= nil and now ~= Queue.seenClock then Queue.clockAdvances = true end
    Queue.seenClock = now
    local last = Queue.lastStepEnd
    if Queue.clockAdvances and last ~= nil and source ~= Queue.lastSource and now >= last
            and now - last < Queue.stepGapMs then return false end
    Queue.lastSource = source
    return true
end

function Queue.step(source)
    if not Queue.fresh(source) then return end
    Queue.frame = Queue.frame + 1
    local Custom = ProjectALife.CustomProfiles
    local job = Queue.active
    if job == nil then
        job = Queue.nextJob()
        if job == nil then
            if Creator.window ~= nil and Queue.frame % Queue.warmEvery == 0 and type(Custom.warmStep) == "function"
                    and Queue.enabled() then
                pcall(Custom.warmStep)
            end
            Queue.lastStepEnd = Queue.clock()
            return
        end
        Queue.active = job
        job.handle = Custom.prepareSave(job.profile)
        if job.handle == nil then
            Queue.fail(job, "prepare_refused")
            Queue.lastStepEnd = Queue.clock()
            return
        end
    end
    Queue.stepChecked(job)
    Queue.lastStepEnd = Queue.clock()
end

function Queue.flushWork(window)
    if window.autosaveGuard then return true end
    local invalid = Creator.validateFactionFields(window)
    if invalid then
        Creator.paintSaveStatus(window.factionSaveStateLabel, invalid, "error")
        return false
    end
    if window.currentProfile and window.profileBaseline
            and Creator.signature(Creator.harvestProfile(window)) ~= window.profileBaseline then
        Queue.begin(window)
    end
    if window.currentFaction and window.factionBaseline
            and Creator.signature(Creator.harvestFaction(window)) ~= window.factionBaseline then
        if not Creator.saveFaction(window) then return false end
    end
    return true
end

function Creator.beginProfileSave(window)
    if not Queue.enabled() then return legacy.begin(window) end
    return Queue.begin(window)
end

function Creator.flushEdits(window)
    if Creator.seasonalJob then return false end
    if not Queue.enabled() then return legacy.flush(window) end
    if not Queue.flushWork(window) then return false end
    if Queue.busy() then
        window.profileSaveRetryNotice = true
        Creator.paintSaveStatus(window.saveStateLabel, "SAVING - RETRY WHEN SAVED", "saving")
        return false
    end
    window.profileSaveRetryNotice = nil
    return true
end

function Creator.flushLeave(window)
    if Creator.seasonalJob or window.seasonalPreview or window.factionWardrobeEditor then return false end
    if not Queue.enabled() then return legacy.flush(window) end
    return Queue.flushWork(window)
end

function Creator.stepProfileSave(window)
    Queue.step("window")
    return legacy.step(window)
end

function Creator.open()
    if Queue.enabled() and Queue.busy() then
        Queue.openWhenIdle = true
        Queue.say("Saving NPC... the Creator opens when it is done")
        return false
    end
    return legacy.open()
end

if type(Events) == "table" and Events.OnPreUIDraw and type(Events.OnPreUIDraw.Add) == "function" then
    Events.OnPreUIDraw.Add(function() Queue.step("ui") end)
end
if type(Events) == "table" and Events.OnTick and type(Events.OnTick.Add) == "function" then
    Events.OnTick.Add(function() Queue.step("tick") end)
end

return Queue
