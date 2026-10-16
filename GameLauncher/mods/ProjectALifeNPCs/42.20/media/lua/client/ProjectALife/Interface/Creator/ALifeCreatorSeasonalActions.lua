require "ProjectALife/Interface/Creator/ALifeCreatorCore"
require "ProjectALife/Interface/Creator/ALifeCreatorWardrobe"
require "ProjectALife/Records/ALifeSeasonalOutfitGenerator"
require "ProjectALife/Records/ALifeCustomProfiles"
require "ProjectALife/Records/ALifeCustomFactions"

local Creator = ProjectALife.CreatorScreen

function Creator.seasonalFactionVisible(window, record)
    if not window.seasonalShippedOnly then return true end
    local shipped = ProjectALife.Catalog.shipped
    return shipped ~= nil and shipped.factions[record.id] ~= nil
        and ProjectALife.CustomFactions.get(record.id) == nil
end

function Creator.seasonalNonempty(outfit)
    if type(outfit) ~= "table" then return false end
    for _, value in pairs(outfit) do
        if type(value) == "string" and value ~= "" and value ~= "none" then return true end
    end
    return false
end

function Creator.seasonalProfileFromRecord(record)
    local copied = Creator.profileFromRecord(record)
    if type(record.clothing) == "table" then copied.clothing = Creator.deepCopy(record.clothing) end
    return copied
end

function Creator.mergeShippedWardrobe(record, shipped, member)
    local copied = member and Creator.seasonalProfileFromRecord(record) or Creator.copyFactionWardrobe(record, Creator.deepCopy(record))
    if not shipped then return copied end
    if member and ProjectALife.SeasonalOutfitGenerator.keepsAuthored(copied) ~= nil then return copied end
    for _, spec in ipairs(Creator.seasonSpecs) do
        local old = member and copied.outfits[spec.id] or copied["outfit" .. spec.id]
        if member and type(ProjectALife.CustomProfiles.syntheticOutfit) == "function"
                and ProjectALife.CustomProfiles.syntheticOutfit(copied, spec.id) then old = nil end
        local source = shipped["outfit" .. spec.id] or shipped.outfits and shipped.outfits[spec.id]
        if not Creator.seasonalNonempty(old) and Creator.seasonalNonempty(source) then
            if member then
                copied.outfits[spec.id] = Creator.deepCopy(source)
                copied.outfitTints[spec.id] = Creator.deepCopy(shipped["tint" .. spec.id] or shipped.outfitTints and shipped.outfitTints[spec.id] or {})
                if not record.outfitEnabled or record.outfitEnabled[spec.id] ~= false then copied.outfitEnabled[spec.id] = true end
                if spec.id == "A" then copied.syntheticOutfitA = nil end
            else
                copied["outfit" .. spec.id] = Creator.deepCopy(source)
                copied["tint" .. spec.id] = Creator.deepCopy(shipped["tint" .. spec.id] or {})
            end
        end
        copied.outfitSeason = copied.outfitSeason or {}
        if copied.outfitSeason[spec.id] == nil and shipped.outfitSeason then copied.outfitSeason[spec.id] = shipped.outfitSeason[spec.id] end
        if not member then
            copied.outfitNames = copied.outfitNames or {}
            if copied.outfitNames[spec.id] == nil and shipped.outfitNames then copied.outfitNames[spec.id] = shipped.outfitNames[spec.id] end
        end
    end
    return copied
end

function Creator.seasonalDiff(before, after, member)
    local changes = {}
    for _, spec in ipairs(Creator.seasonSpecs) do
        local old = member and before.outfits and before.outfits[spec.id] or before["outfit" .. spec.id]
        local new = member and after.outfits and after.outfits[spec.id] or after["outfit" .. spec.id]
        if Creator.signature(old) ~= Creator.signature(new) then changes[#changes + 1] = spec.id .. " outfit" end
        if (before.outfitSeason or {})[spec.id] ~= (after.outfitSeason or {})[spec.id] then changes[#changes + 1] = spec.id .. " season" end
        local oldTint = member and before.outfitTints and before.outfitTints[spec.id] or before["tint" .. spec.id]
        local newTint = member and after.outfitTints and after.outfitTints[spec.id] or after["tint" .. spec.id]
        if Creator.signature(oldTint) ~= Creator.signature(newTint) then changes[#changes + 1] = spec.id .. " tint" end
        if not member and (before.outfitNames or {})[spec.id] ~= (after.outfitNames or {})[spec.id] then changes[#changes + 1] = spec.id .. " name" end
    end
    return table.concat(changes, ", ")
end

function Creator.seasonalBucket(records, includeDeleted)
    local buckets = {}
    for _, record in ipairs(records or {}) do
        local general = record.general
        if general and general.deleted ~= true and type(general.faction) == "string"
                and (includeDeleted or not ProjectALife.CustomProfiles.isDeleted(record.id)) then
            local bucket = buckets[general.faction]
            if bucket == nil then
                bucket = {}
                buckets[general.faction] = bucket
            end
            bucket[#bucket + 1] = record
        end
    end
    return buckets
end

function Creator.planSeasonalBegin(window, all, updateShipped)
    local catalog, shipped = window.catalog, ProjectALife.Catalog.shipped
    if not catalog then return nil end
    local state = { window = window, catalog = catalog, shipped = shipped, updateShipped = updateShipped,
        factions = {}, factionIndex = 1, memberIndex = 1, done = 0, total = 0, members = {}, seen = {},
        plan = { factions = {}, profiles = {}, diffs = {}, warnings = {}, notes = {}, before = {},
            mode = updateShipped and "Update from shipped" or "Generate seasonal outfits" } }
    state.byFaction = Creator.seasonalBucket(catalog.npcOrder, false)
    if updateShipped and shipped then state.shippedByFaction = Creator.seasonalBucket(shipped.npcOrder, true) end
    for _, faction in ipairs(catalog.factionOrder or {}) do
        if not (faction.general and faction.general.deleted == true)
                and (all or window.currentFaction and faction.id == window.currentFaction.id) then
            state.factions[#state.factions + 1] = faction
            state.total = state.total + #(state.byFaction[faction.id] or {}) + 1
        end
    end
    return state
end

function Creator.planSeasonalMember(state, faction, record)
    local plan = state.plan
    local before = Creator.seasonalProfileFromRecord(record)
    local nextProfile, summary
    if state.updateShipped then
        nextProfile = Creator.mergeShippedWardrobe(before, state.shipped and state.shipped.npcs[record.id], true)
    else nextProfile, summary = ProjectALife.SeasonalOutfitGenerator.profile(before, faction) end
    state.members[#state.members + 1], state.seen[record.id] = nextProfile, true
    local diff = Creator.seasonalDiff(before, nextProfile, true)
    if diff ~= "" then
        plan.profiles[#plan.profiles + 1] = nextProfile
        plan.diffs[#plan.diffs + 1] = "NPC " .. tostring(before.general.name) .. ": " .. diff
        plan.before["member:" .. record.id] = Creator.signature(record)
    end
    local kept, open
    if state.updateShipped then
        if state.shipped and state.shipped.npcs[record.id] ~= nil then kept, open = ProjectALife.SeasonalOutfitGenerator.keepsAuthored(before) end
    elseif summary and summary.reason == "authored" then kept, open = summary.kept, summary.openSeasons end
    if kept ~= nil and open > 0 then
        plan.notes[#plan.notes + 1] = "NPC " .. tostring(before.general.name) .. ": authored, skipped " .. tostring(open) .. (open == 1 and " season" or " seasons")
    end
    for _, warning in ipairs(summary and summary.warnings or {}) do plan.warnings[#plan.warnings + 1] = record.id .. ": " .. tostring(warning) end
end

function Creator.planSeasonalFaction(state, faction)
    local plan, shipped, catalog = state.plan, state.shipped, state.catalog
    if state.updateShipped and shipped then
        for _, record in ipairs(state.shippedByFaction[faction.id] or {}) do
            if not state.seen[record.id] and not catalog.npcs[record.id] and not ProjectALife.CustomProfiles.isDeleted(record.id) then
                local copied = Creator.seasonalProfileFromRecord(record)
                plan.profiles[#plan.profiles + 1], state.members[#state.members + 1] = copied, copied
                plan.diffs[#plan.diffs + 1] = "ADD missing shipped NPC " .. tostring(record.general.name)
                plan.before["member:" .. record.id] = "missing"
            end
        end
    end
    local nextFaction, summary
    if state.updateShipped then nextFaction = Creator.mergeShippedWardrobe(faction, shipped and shipped.factions[faction.id], false)
    else nextFaction, summary = ProjectALife.SeasonalOutfitGenerator.faction(faction, state.members) end
    local diff = Creator.seasonalDiff(faction, nextFaction, false)
    if diff ~= "" then
        plan.factions[#plan.factions + 1] = nextFaction
        plan.diffs[#plan.diffs + 1] = "FACTION " .. tostring(faction.general.name) .. ": " .. diff
        plan.before["faction:" .. faction.id] = Creator.signature(faction)
    end
    for _, warning in ipairs(summary and summary.warnings or {}) do plan.warnings[#plan.warnings + 1] = faction.id .. ": " .. tostring(warning) end
end

function Creator.planSeasonalStep(state, budgetMs)
    local clock = ProjectALife.RecordMigration.transactionClock
    local startedAt = budgetMs ~= nil and clock() or nil
    local units = 0
    while state.factionIndex <= #state.factions do
        local faction = state.factions[state.factionIndex]
        local list = state.byFaction[faction.id]
        if list ~= nil and state.memberIndex <= #list then
            Creator.planSeasonalMember(state, faction, list[state.memberIndex])
            state.memberIndex = state.memberIndex + 1
        else
            Creator.planSeasonalFaction(state, faction)
            state.factionIndex, state.memberIndex, state.members, state.seen = state.factionIndex + 1, 1, {}, {}
        end
        state.done, units = state.done + 1, units + 1
        if budgetMs ~= nil then
            local now = startedAt ~= nil and clock() or nil
            if now == nil and units >= 8 or now ~= nil and (now < startedAt or now - startedAt >= budgetMs) then return false end
        end
    end
    state.finished = true
    return true
end

function Creator.planSeasonalAction(window, all, updateShipped)
    local state = Creator.planSeasonalBegin(window, all, updateShipped)
    if not state then return nil end
    Creator.planSeasonalStep(state, nil)
    return state.plan
end

function Creator.closeSeasonalPreview(window)
    if Creator.seasonalJob then return false end
    if window.seasonalPreview then window:removeChild(window.seasonalPreview) end
    window.seasonalPreview, window.seasonalPlan = nil, nil
    return true
end

function Creator.seasonalCue(reason)
    if type(Creator.notifyCue) == "function" then return Creator.notifyCue(reason) end
    return false
end

function Creator.seasonalSay(window, text, cue)
    local preview = window and window.seasonalPreview
    if preview and preview.status then preview.status:setName(text) end
    if cue ~= nil then Creator.seasonalCue(cue) end
end

function Creator.seasonalWindowAlive(window)
    return window ~= nil and Creator.window == window
end

function Creator.drawSeasonalProgress(panel, job)
    local state = job.state
    local width = panel.width
    panel:drawTextCentre("Planning " .. tostring(state.done) .. " of " .. tostring(state.total), width / 2, 14, 0.92, 0.92, 0.92, 1, UIFont.Medium)
    local barX, barY, barW, barH = 20, 52, width - 40, 8
    panel:drawRect(barX, barY, barW, barH, 0.9, 0.12, 0.12, 0.13)
    if state.total > 0 then
        panel:drawRect(barX, barY, math.max(1, math.floor(barW * state.done / state.total)), barH, 0.95, 0.62, 0.16, 0.24)
    end
end

function Creator.stopSeasonalPlanning(job)
    if Creator.seasonalPlanJob == job then Creator.seasonalPlanJob = nil end
    local overlay = job.overlay
    job.overlay, job.panel = nil, nil
    if overlay ~= nil and job.window ~= nil and Creator.seasonalWindowAlive(job.window) then
        pcall(function() job.window:removeChild(overlay) end)
    end
end

function Creator.cancelSeasonalPlanning()
    local job = Creator.seasonalPlanJob
    if not job then return false end
    Creator.stopSeasonalPlanning(job)
    if Creator.seasonalWindowAlive(job.window) then
        Creator.paintSaveStatus(job.window.factionSaveStateLabel, "PLANNING CANCELLED - NOTHING WAS CHANGED", "saving")
    end
    return true
end

function Creator.startSeasonalPlanning(window, state)
    local px = Creator.px
    local job = { window = window, state = state }
    Creator.seasonalPlanJob = job
    local overlay = ISPanel:new(0, 0, window.width, window.height)
    overlay:initialise()
    overlay.backgroundColor = { r = 0, g = 0, b = 0, a = 0.6 }
    overlay.onMouseDown = function() return true end
    overlay.onMouseUp = function() return true end
    window:addChild(overlay)
    local width, height = px(420), px(110)
    local panel = Creator.createFramedPanel(overlay, math.floor((window.width - width) / 2), math.floor((window.height - height) / 2), width, height)
    panel.backgroundColor = { r = 0.025, g = 0.028, b = 0.035, a = 1 }
    panel.render = function(self) Creator.drawSeasonalProgress(self, job) end
    Creator.addButton(panel, width - px(116), height - px(40), px(100), "CANCEL", function() Creator.cancelSeasonalPlanning() end)
    job.overlay, job.panel = overlay, panel
    overlay:bringToTop()
    return job
end

function Creator.finishSeasonalPlanning(job)
    local window, plan = job.window, job.state.plan
    Creator.stopSeasonalPlanning(job)
    Creator.showSeasonalPreview(window, plan)
end

function Creator.stepSeasonalPlan(source)
    local job = Creator.seasonalPlanJob
    if not job then return false end
    if not Creator.seasonalWindowAlive(job.window) then
        Creator.stopSeasonalPlanning(job)
        return false
    end
    local clock = ProjectALife.RecordMigration.transactionClock()
    if job.lastEnd ~= nil and clock ~= nil and source ~= job.lastSource and clock >= job.lastEnd and clock - job.lastEnd < 6 then return false end
    local ran, finished = pcall(Creator.planSeasonalStep, job.state, Creator.seasonalPlanBudgetMs)
    job.lastSource, job.lastEnd = source, ProjectALife.RecordMigration.transactionClock()
    if not ran then
        print("[ProjectALife] Seasonal planning failed: " .. tostring(finished))
        Creator.stopSeasonalPlanning(job)
        Creator.paintSaveStatus(job.window.factionSaveStateLabel, "PLANNING FAILED - NOTHING WAS CHANGED", "error")
        return false
    end
    if finished then Creator.finishSeasonalPlanning(job) end
    return finished
end

Creator.seasonalPlanBudgetMs = 5

function Creator.previewSeasonalAction(window, all, updateShipped)
    if ProjectALife.CustomProfiles.serverManaged or ProjectALife.CustomFactions.serverManaged
            or type(isClient) == "function" and isClient() then
        Creator.paintSaveStatus(window.factionSaveStateLabel, "BULK WARDROBE: OPEN THE LOCAL CREATOR STORE OUTSIDE MULTIPLAYER", "error")
        Creator.seasonalCue("seasonal_refused")
        return false
    end
    if Creator.seasonalJob or Creator.seasonalPlanJob or ProjectALife.CreatorSaveQueue.busy() then
        Creator.paintSaveStatus(window.factionSaveStateLabel, "WAIT FOR THE CURRENT SAVE OR PLAN, THEN PREVIEW AGAIN", "saving")
        Creator.seasonalCue("seasonal_refused")
        return false
    end
    if not Creator.flushEdits(window) then
        Creator.paintSaveStatus(window.factionSaveStateLabel, "SAVE OPEN EDITS FIRST, THEN PREVIEW AGAIN", "saving")
        Creator.seasonalCue("seasonal_refused")
        return false
    end
    local state = Creator.planSeasonalBegin(window, all, updateShipped)
    if not state then return false end
    Creator.closeSeasonalPreview(window)
    Creator.startSeasonalPlanning(window, state)
    return true
end

function Creator.showSeasonalPreview(window, plan)
    Creator.closeSeasonalPreview(window)
    window.seasonalPlan = plan
    local px = Creator.px
    local width, height = math.min(window.width - px(24), px(900)), math.min(window.height - px(24), px(610))
    local overlay = ISPanel:new(0, 0, window.width, window.height)
    overlay:initialise()
    overlay.backgroundColor = { r = 0, g = 0, b = 0, a = 0.85 }
    overlay.onMouseDown = function() return true end
    overlay.onMouseUp = function() return true end
    window:addChild(overlay)
    local panel = Creator.createFramedPanel(overlay, math.floor((window.width - width) / 2), px(12), width, height)
    panel.backgroundColor = { r = 0.025, g = 0.028, b = 0.035, a = 1 }
    window.seasonalPreview = overlay
    Creator.addLabel(panel, px(16), px(12), plan.mode .. " - PREVIEW ONLY", Creator.palette.ROSE, UIFont.Medium)
    panel.status = Creator.addLabel(panel, px(16), px(46), tostring(#plan.factions) .. " factions, " .. tostring(#plan.profiles) .. " NPCs change; "
        .. tostring(#plan.notes) .. " NPCs keep their own outfits; " .. tostring(#plan.warnings) .. " warnings", Creator.palette.TEXT)
    Creator.addLabel(panel, px(16), px(70), "Only listed missing wardrobe fields are filled. NPCs with their own untagged outfits are skipped:", Creator.palette.MUTED, UIFont.Small, width - px(32))
    Creator.addLabel(panel, px(16), px(88), "their outfits and season tags stay exactly as authored and the game still dresses them for the season.", Creator.palette.MUTED, UIFont.Small, width - px(32))
    panel.lines = {}
    local capacity = math.max(1, math.floor((height - px(190)) / px(23)))
    for index = 1, capacity do panel.lines[index] = Creator.addLabel(panel, px(16), px(116) + (index - 1) * px(23), "", Creator.palette.MUTED) end
    panel.page = 1
    panel.drawPage = function()
        for index, label in ipairs(panel.lines) do
            local offset = (panel.page - 1) * capacity + index
            local text = plan.diffs[offset] or plan.notes[offset - #plan.diffs] or plan.warnings[offset - #plan.diffs - #plan.notes]
            label:setName(Creator.fitText(text or "", UIFont.Small, width - px(32)))
        end
    end
    Creator.addButton(panel, px(16), height - px(42), px(100), "CANCEL", function() Creator.closeSeasonalPreview(window) end)
    Creator.addButton(panel, px(130), height - px(42), px(45), "<", function() panel.page = math.max(1, panel.page - 1); panel.drawPage() end)
    Creator.addButton(panel, px(185), height - px(42), px(45), ">", function() panel.page = math.min(math.max(1, math.ceil((#plan.diffs + #plan.notes + #plan.warnings) / capacity)), panel.page + 1); panel.drawPage() end)
    panel.confirm = Creator.addButton(panel, width - px(220), height - px(42), px(204), "CONFIRM AND SAVE", function() Creator.confirmSeasonalAction(window) end, true)
    overlay.status, overlay.confirm = panel.status, panel.confirm
    panel.confirm:setEnable(#plan.factions + #plan.profiles > 0)
    panel.drawPage()
    overlay:bringToTop()
    if #plan.warnings > 0 or #plan.notes > 0 then Creator.seasonalCue("seasonal_conflicts") end
    return true
end

function Creator.seasonalRefusal(plan)
    local Profiles, Factions = ProjectALife.CustomProfiles, ProjectALife.CustomFactions
    if Profiles.batchLocked() then return "Another bulk save is still running. Wait for it to finish, then press CONFIRM AND SAVE again." end
    if #plan.profiles > 0 and Profiles.loadFailed then
        return "The NPC store could not be read at startup, so nothing was changed. Close and reopen the Creator, then preview again."
    end
    if #plan.factions > 0 and Factions.loadFailed then
        return "The faction store could not be read at startup, so nothing was changed. Close and reopen the Creator, then preview again."
    end
    local seen = {}
    for _, profile in ipairs(plan.profiles) do
        if type(profile) ~= "table" or type(profile.id) ~= "string" then
            return "The plan holds an NPC without an id, so nothing was changed. Cancel and preview again."
        end
        if seen[profile.id] then
            return "The plan lists the NPC " .. profile.id .. " twice, so nothing was changed. Cancel and preview again."
        end
        seen[profile.id] = true
    end
    return nil
end

Creator.seasonalSnapshotReasons = {
    snapshot_index_unreadable = "The list of safety copies could not be read, so nothing was changed.",
    snapshot_name_invalid = "The safety copy name was refused, so nothing was changed.",
    snapshot_source_unreadable = "The current store file could not be read for the safety copy, so nothing was changed.",
    snapshot_write_failed = "The safety copy of the current store could not be written (disk full or read-only?), so nothing was changed.",
    snapshot_verify_failed = "The safety copy of the current store did not match the original, so nothing was changed.",
    snapshot_index_failed = "The safety copy list could not be updated, so nothing was changed.",
}

function Creator.seasonalSnapshotReason(reason)
    return Creator.seasonalSnapshotReasons[reason] or "The safety copy of the current store failed, so nothing was changed."
end

function Creator.seasonalSnapshotSources()
    return { ProjectALife.CustomProfiles.fileName, ProjectALife.CustomFactions.fileName }
end

function Creator.confirmSeasonalAction(window)
    local plan = window.seasonalPlan
    if not plan or Creator.seasonalJob or Creator.seasonalPlanJob or ProjectALife.CreatorSaveQueue.busy() then return false end
    if not Creator.flushEdits(window) then Creator.seasonalSay(window, "OPEN EDITS CHANGED - wait for save, then cancel and preview again", "seasonal_refused"); return false end
    for key, expected in pairs(plan.before) do
        local kind, id = key:match("^(%w+):(.*)$")
        local record = kind == "member" and window.catalog.npcs[id] or window.catalog.factions[id]
        local actual = record and Creator.signature(record) or "missing"
        if actual ~= expected then Creator.seasonalSay(window, "DATA CHANGED - cancel and preview again", "seasonal_refused"); return false end
    end
    if ProjectALife.CustomProfiles.serverManaged or ProjectALife.CustomFactions.serverManaged
            or type(isClient) == "function" and isClient() then
        Creator.seasonalSay(window, "Bulk seasonal changes require the local Creator store, not an active multiplayer client.", "seasonal_refused")
        return false
    end
    local refusal = Creator.seasonalRefusal(plan)
    if refusal then Creator.seasonalSay(window, refusal, "seasonal_refused"); return false end
    local handle
    if #plan.profiles > 0 then
        handle = ProjectALife.CustomProfiles.prepareManySave(plan.profiles)
        if not handle then
            Creator.seasonalSay(window, Creator.seasonalRefusal(plan) or "The NPC store refused the update, so nothing was changed. Cancel, wait a moment and preview again.", "seasonal_refused")
            return false
        end
    end
    local snapshot, reason = ProjectALife.RecordMigration.snapshotBegin(Creator.seasonalSnapshotSources())
    if not snapshot then
        if handle then ProjectALife.CustomProfiles.cancelPrepared(handle) end
        Creator.seasonalSay(window, Creator.seasonalSnapshotReason(reason), "seasonal_refused")
        return false
    end
    Creator.seasonalJob = { window = window, plan = plan, handle = handle, snapshot = snapshot }
    Creator.seasonalSay(window, "SAVING - first a safety copy of the current store, then one background profile transaction, then faction defaults")
    if window.seasonalPreview and window.seasonalPreview.confirm then window.seasonalPreview.confirm:setEnable(false) end
    return true
end

function Creator.seasonalCopyNote(job)
    if job.names == nil or #job.names == 0 then return "" end
    return " - old store kept as " .. job.names[1] .. " (" .. tostring(job.stamp) .. ")" .. (#job.names > 1 and " and its factions twin" or "")
end

function Creator.stepSeasonalSnapshot(job)
    local ok, done, reason = ProjectALife.RecordMigration.snapshotStep(job.snapshot, 5)
    if not ok then
        if job.handle then ProjectALife.CustomProfiles.cancelPrepared(job.handle) end
        Creator.seasonalJob = nil
        Creator.seasonalSay(job.window, Creator.seasonalSnapshotReason(reason), "seasonal_failed")
        if job.window.seasonalPreview and job.window.seasonalPreview.confirm then job.window.seasonalPreview.confirm:setEnable(true) end
        return
    end
    if not done then return end
    job.names, job.stamp, job.snapshot = job.snapshot.names, job.snapshot.stamp, nil
    Creator.seasonalSay(job.window, "SAVING" .. Creator.seasonalCopyNote(job) .. " - writing profiles, then faction defaults")
end

function Creator.stepSeasonalAction()
    local job = Creator.seasonalJob
    if not job then return end
    if job.snapshot ~= nil then return Creator.stepSeasonalSnapshot(job) end
    local ok, ready = true, true
    if job.handle then ok, ready = ProjectALife.CustomProfiles.stepPrepared(job.handle) end
    if ok and not ready then return end
    if ok and job.handle then ok = ProjectALife.CustomProfiles.saveManyPrepared(job.plan.profiles, job.handle) end
    if job.handle then ProjectALife.CustomProfiles.cancelPrepared(job.handle) end
    if ok and #job.plan.factions > 0 then ok = ProjectALife.CustomFactions.saveMany(job.plan.factions) end
    Creator.seasonalJob = nil
    local window = job.window
    if not ok then
        Creator.seasonalSay(window, "SAVE FAILED OR PARTIAL" .. Creator.seasonalCopyNote(job) .. "; normal backups retained; reload and preview again", "seasonal_failed")
        if window.seasonalPreview and window.seasonalPreview.confirm then window.seasonalPreview.confirm:setEnable(false) end
        return
    end
    local wanted = window.currentFaction and window.currentFaction.id
    Creator.closeSeasonalPreview(window)
    Creator.refreshFactions(window, wanted)
    local note = Creator.seasonalCopyNote(job)
    Creator.paintSaveStatus(window.factionSaveStateLabel, "SEASONAL WARDROBE SAVED" .. note, "saved")
    Creator.seasonalCue("seasonal_done")
    print("[ProjectALife] Seasonal wardrobe saved; old store files kept: " .. table.concat(job.names or {}, ", "))
end

function Creator.stepSeasonalEvents(source)
    Creator.stepSeasonalAction()
    Creator.stepSeasonalPlan(source)
end

if type(Events) == "table" and Events.OnTick and type(Events.OnTick.Add) == "function" then Events.OnTick.Add(function() Creator.stepSeasonalEvents("tick") end) end
if type(Events) == "table" and Events.OnPreUIDraw and type(Events.OnPreUIDraw.Add) == "function" then Events.OnPreUIDraw.Add(function() Creator.stepSeasonalEvents("ui") end) end

return Creator
