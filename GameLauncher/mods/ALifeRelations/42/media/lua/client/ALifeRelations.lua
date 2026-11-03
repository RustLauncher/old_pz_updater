-- Data logic for A-Life Faction Relations. No UI here, so it runs in the test harness.
-- Reads A-Life's own data (Catalog, RelationLayers, StatusStore.reputation); never writes to it.
ALifeRelations = ALifeRelations or {}
local M = ALifeRelations

M.COLORS = {
    friendly = { 0.45, 0.9, 0.45 },
    neutral = { 0.85, 0.85, 0.85 },
    careful = { 0.95, 0.8, 0.3 },
    hostile = { 0.95, 0.35, 0.35 },
}
M.FILTERS = { "all", "met", "friendly", "neutral", "careful", "hostile" }
M.RANK = { friendly = 1, neutral = 2, careful = 3, hostile = 4 }
local RANK = M.RANK
-- Causes other mods write into A-Life's reputation, shown in plain words.
M.JEEM_CAUSE = "jimmy_standing" -- Jeem Extension's label from its points
M.CAUSES = { [M.JEEM_CAUSE] = "Jeem points" }
-- A recorded grudge's cause, as a line on a faction's "why" page.
M.GRUDGES = { attack = "you attacked them", kill = "you killed one of them", wound = "you hurt one of them",
    provoked = "you ignored their warning", admin = "set by an admin" }

-- Mirrors A-Life's server-only Reputation.provokedForgetHours: CalmDown_Hours while A-Life's "calm down" is on
-- (Jeem Extension hands its own copy over to it), otherwise 24.
local function provokedHours()
    local calm = ProjectALife and ProjectALife.CalmDown
    if calm and calm.active() then return calm.hours() end
    return 24
end

-- Server settings (sandbox options, page "A-Life Faction Relations"). A switch the admin turned off is off for everyone.
function M.serverAllows(name)
    local vars = SandboxVars and SandboxVars.ALifeRelations
    return not (vars and vars[name] == false)
end

function M.serverNumber(name, default)
    local vars = SandboxVars and SandboxVars.ALifeRelations
    return vars and tonumber(vars[name]) or default
end

-- How far A-Life hears /say and /yell: its Talk.settings listenRadius and loudRadius. That file only runs on the
-- server, so the numbers are copied here; the test checks them against A-Life's source.
M.SAY_TILES, M.SHOUT_TILES = 12, 25

-- Say and Shout in the right-click menu everywhere, or (the default) only while an A-Life NPC can hear you.
function M.talkAnywhere()
    local vars = SandboxVars and SandboxVars.ALifeRelations
    return vars ~= nil and vars.TalkAnywhere == true
end

-- Lines for the right-click Say/Shout menus, with the A-Life intent each must hit (checked in the test).
M.PHRASES = {
    { "Don't shoot!", "DONT_SHOOT" },
    { "I'm friendly.", "I_AM_FRIENDLY" },
    { "Calm down.", "CALM_DOWN" },
    { "Any news?", "ASK_NEWS" },
    { "Any advice?", "ASK_ADVICE" },
    { "Any settlements?", "ASK_OUTPOST" },
    { "Where do those raiders hide?", "ASK_DEN" },
    { "Got any food?", "ASK_FOOD" },
    { "Got any water?", "ASK_WATER" },
    { "Got any bandages?", "ASK_MEDS" },
    { "Can I come with you?", "JOIN_REQUEST" },
    { "Follow me.", "FOLLOW_ME" },
    { "Hands up!", "HANDS_UP" },
    { "Drop your weapon!", "DROP_WEAPON" },
    { "Give me your stuff!", "DEMAND_ITEMS" },
}

-- Same word mapping A-Life uses: allied -> friendly, suspicious -> careful.
local function norm(word)
    word = string.lower(tostring(word or ""))
    if word == "allied" then return "friendly" end
    if word == "suspicious" then return "careful" end
    return RANK[word] and word or nil
end

function M.nameOf(faction)
    return faction.general and faction.general.name or faction.id
end

function M.available()
    return ProjectALife ~= nil and ProjectALife.Catalog ~= nil and ProjectALife.RelationLayers ~= nil
end

-- MP clients don't load A-Life's catalog on their own (only its creator UI does). Load it on demand;
-- after a failed read stop retrying so per-tick callers don't hit the disk.
local loadFailed = false
local function catalog()
    local Catalog = ProjectALife.Catalog
    if Catalog.current == nil and not loadFailed then
        local ok, loaded = pcall(Catalog.load, true)
        loadFailed = not ok or loaded == nil
    end
    return Catalog.current
end

function M.faction(id)
    if id == nil then return nil end
    catalog()
    return ProjectALife.Catalog.faction(id)
end

-- NPC profile (its general.name is the title A-Life uses, e.g. "Drifter Scout").
function M.npc(id)
    if id == nil or ProjectALife.Catalog.npc == nil then return nil end
    catalog()
    return ProjectALife.Catalog.npc(id)
end

-- Shipped + custom factions; server copies (Catalog.network) win over local ones.
function M.factions()
    local Catalog = ProjectALife.Catalog
    local current = catalog()
    local list, seen = {}, {}
    local function add(faction)
        if type(faction) ~= "table" or faction.id == nil or seen[faction.id] then return end
        seen[faction.id] = true
        if not (faction.general and faction.general.deleted == true) then list[#list + 1] = faction end
    end
    for _, faction in ipairs(current and current.factionOrder or {}) do add(Catalog.faction(faction.id)) end
    for _, faction in pairs(Catalog.network and Catalog.network.factions or {}) do add(faction) end
    return list
end

-- factionId -> entry, from a Reputation snapshot's relations list.
function M.overrides(relations, nowHours)
    local result, forget = {}, provokedHours()
    for _, entry in ipairs(type(relations) == "table" and relations or {}) do
        local expired = entry.cause == "provoked"
            and nowHours - (tonumber(entry.atHours) or 0) > forget
        if not expired and norm(entry.status) then result[entry.factionId] = entry end
    end
    return result
end

function M.myRelations()
    local store = ProjectALife.StatusStore
    return store and store.reputation and store.reputation.relations
end

-- The player's reputation (level, e.g. "rep_p1" = Helper, and score), synced with the relations; nil when A-Life's
-- tracking is off.
function M.myPersonal()
    local store = ProjectALife.StatusStore
    local personal = store and store.reputation and store.reputation.personal
    return type(personal) == "table" and personal or nil
end

function M.myLevel()
    local personal = M.myPersonal()
    return personal and personal.level
end

-- "Reputation: Helper 72" (no score when the server hides it) and its colour by A-Life's band: good green, bad amber
-- (a level only ever makes blocs careful), nil for Neutral. nil text when there's no level to show.
function M.repSummary(personal)
    local Levels = ProjectALife.RepLevels
    local name = Levels and type(personal) == "table" and Levels.name(personal.level)
    if not name then return nil end
    local score = tonumber(personal.score)
    local band = Levels.band(personal.level)
    return "Reputation: " .. name .. (score and (" " .. math.floor(score)) or ""),
        band == "good" and M.COLORS.friendly or band == "bad" and M.COLORS.careful or nil
end

-- Faction-level stance only; individual NPCs can still hold timed truces or grudges.
-- With no recorded standing, A-Life moves whole blocs by the player's reputation level (Personal.firstContact).
function M.stanceFor(faction, professionId, overrides)
    local entry = overrides[faction.id]
    if entry then return norm(entry.status), entry.cause, tonumber(entry.atHours) end
    local Layers, Levels, level = ProjectALife.RelationLayers, ProjectALife.RepLevels, M.myLevel()
    local stance = norm(Layers.towardPlayer(faction, professionId)) or "neutral"
    if Levels and level and stance ~= "hostile" then
        local cell = Levels.cell(level, Levels.repBlocOf(Layers.blocOf(faction), faction.id))
        if cell then return cell.stance, "reputation" end
    end
    return stance
end

-- Display text for a cause. A provoked grudge lapses after provokedHours(), so show the time left.
-- Display only: history and diffs keep the raw cause.
function M.causeText(cause, atHours, nowHours)
    if cause == "provoked" and atHours then
        local left = math.ceil(provokedHours() - (nowHours - atHours))
        if left >= 1 then return "provoked, " .. left .. "h left" end
    end
    return M.CAUSES[cause] or cause
end

function M.towardMe(faction, player, overrides)
    return M.stanceFor(faction, ProjectALife.RelationLayers.professionOf(player), overrides)
end

function M.between(source, target)
    local vars = SandboxVars and SandboxVars.ALife
    if vars and vars.World_FactionWarfare == false then return "neutral" end
    if source.id == target.id then return "friendly" end
    return norm(ProjectALife.RelationLayers.towardFaction(source, target)) or "hostile"
end

-- seen: factionId -> world-age hours this character last saw that faction (kept in player modData by the HUD).
function M.markSeen(seen, factionId, hours)
    if factionId == nil or hours == nil then return end
    if seen[factionId] == nil or hours > seen[factionId] then seen[factionId] = hours end
end

function M.ago(hours)
    if hours < 1 then return "just now" end
    if hours < 24 then return math.floor(hours) .. "h ago" end
    local days = math.floor(hours / 24)
    return days .. (days == 1 and " day ago" or " days ago")
end

-- history: list of { factionId, status, cause, atHours }, oldest first, raw causes from A-Life's relations.
M.HISTORY_LIMIT = 100

function M.addHistory(history, entry)
    local status, at = norm(entry.status), tonumber(entry.atHours)
    if entry.factionId == nil or status == nil or at == nil then return false end
    for _, old in ipairs(history) do
        if old.factionId == entry.factionId and old.status == status and old.cause == entry.cause
            and old.atHours == at then return false end
    end
    history[#history + 1] = { factionId = entry.factionId, status = status, cause = entry.cause, atHours = at }
    table.sort(history, function(a, b) return a.atHours < b.atHours end)
    while #history > M.HISTORY_LIMIT do table.remove(history, 1) end
    return true
end

-- Newest first. Every faction in the history has been met, so seenAt is set for the "met" filter.
function M.historyRows(history)
    local rows = {}
    for _, h in ipairs(history or {}) do
        local faction = M.faction(h.factionId)
        if faction then
            rows[#rows + 1] = { faction = faction, name = M.nameOf(faction), status = h.status, cause = h.cause,
                atHours = h.atHours, seenAt = h.atHours }
        end
    end
    table.sort(rows, function(a, b) return a.atHours > b.atHours end)
    return rows
end

-- kills: factionId -> how many of its NPCs this player has killed (counted by the server). Most first.
function M.killRows(kills, player, nowHours, seen)
    local overrides = M.overrides(M.myRelations(), nowHours)
    local rows = {}
    for id, count in pairs(kills or {}) do
        local faction = M.faction(id)
        if faction then
            local status, cause, causeAt = M.towardMe(faction, player, overrides)
            rows[#rows + 1] = { faction = faction, name = M.nameOf(faction), status = status, cause = cause,
                causeAt = causeAt, kills = count, seenAt = seen and seen[id] }
        end
    end
    table.sort(rows, function(a, b)
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.name < b.name
    end)
    return rows
end

-- When a recorded grudge ends, as A-Life 1.4 has it: provoked lapses after provokedHours(), kill and wound against
-- a usually friendly faction are cleared when you die, the rest stay (Jeem Extension turns them into points).
local function grudgeNote(cause, atHours, nowHours, usual)
    local ends
    if cause == "provoked" then
        ends = "ends in " .. math.max(1, math.ceil(provokedHours() - (nowHours - (atHours or nowHours)))) .. "h"
    elseif (cause == "kill" or cause == "wound") and usual == "friendly" then
        ends = "cleared if you die"
    elseif cause == "admin" then
        ends = "until an admin resets it"
    else
        ends = M.hasStanding() and "Jeem points can lift it" or "permanent"
    end
    return atHours and (M.ago(nowHours - atHours) .. ", " .. ends) or ends
end

-- A faction's "why" page: the steps behind how it treats the player, in M.stanceFor's order (usual stance, your
-- reputation, Jeem points, a recorded grudge), only those A-Life looks at, with the one that decides marked and the
-- rest dim. The answer itself comes from M.stanceFor. standing: the server's Jeem snapshot, if any.
-- Returns status, cause, causeAt, rows.
function M.whyRows(faction, player, nowHours, standing)
    local Layers = ProjectALife.RelationLayers
    local professionId = Layers.professionOf(player)
    local overrides = M.overrides(M.myRelations(), nowHours)
    local status, cause, causeAt = M.stanceFor(faction, professionId, overrides)
    local word, layer = Layers.towardPlayer(faction, professionId)
    local usual = norm(word) or "neutral"
    local entry, jeem = overrides[faction.id], standing and standing.factions and standing.factions[faction.id]
    local rows = { { name = "usually", status = usual, change = usual,
        note = (layer == "profession" or layer == "profession_default") and "your profession" or nil } }
    local decides = rows[1]
    if entry == nil and cause == "reputation" then
        local name = ProjectALife.RepLevels.name(M.myLevel())
        decides = { name = "your reputation (" .. tostring(name) .. ")", status = status, change = status }
        rows[#rows + 1] = decides
    end
    if jeem or (entry and entry.cause == M.JEEM_CAUSE) then
        local row = { name = "Jeem points", status = jeem and norm(jeem.label) or status }
        if jeem then
            row.label, row.change = jeem.label, jeem.label .. string.format(" %+d", math.floor(jeem.points))
            row.note = jeem.toNext and (math.ceil(jeem.toNext) .. " to the next step") or "as high as it goes"
        end
        rows[#rows + 1] = row
        if entry and entry.cause == M.JEEM_CAUSE then decides = row end
    end
    if entry and entry.cause ~= M.JEEM_CAUSE then
        decides = { name = M.GRUDGES[entry.cause] or tostring(entry.cause), status = status, change = status,
            note = grudgeNote(entry.cause, causeAt, nowHours, usual) }
        rows[#rows + 1] = decides
    end
    for _, row in ipairs(rows) do row.dim = row ~= decides end
    -- The marked line shows the answer even if the Jeem snapshot is a moment behind A-Life's label.
    decides.status, decides.decides = status, true
    if decides.label and norm(decides.label) ~= status then decides.label, decides.change = nil, nil end
    decides.change = decides.change or status
    return status, cause, causeAt, rows
end

-- The list opens on met factions, or on all of them for a character who has met none yet.
function M.defaultFilter(seen)
    for _ in pairs(seen or {}) do return "met" end -- the game's Lua has no next function
    return "all"
end

-- Met factions first (most recently seen first), then the rest by stance and name.
local function sortRows(rows)
    table.sort(rows, function(a, b)
        if (a.seenAt ~= nil) ~= (b.seenAt ~= nil) then return a.seenAt ~= nil end
        if a.seenAt ~= b.seenAt then return a.seenAt > b.seenAt end
        if a.status ~= b.status then return RANK[a.status] < RANK[b.status] end
        return a.name < b.name
    end)
    return rows
end

-- subject == nil: how every faction treats the player; otherwise how subject treats the others.
function M.rows(subject, player, nowHours, seen)
    local overrides = subject == nil and M.overrides(M.myRelations(), nowHours) or nil
    local rows = {}
    for _, faction in ipairs(M.factions()) do
        if subject == nil or faction.id ~= subject.id then
            local status, cause, causeAt
            if subject == nil then
                status, cause, causeAt = M.towardMe(faction, player, overrides)
            else
                status = M.between(subject, faction)
            end
            rows[#rows + 1] = { faction = faction, name = M.nameOf(faction), status = status, cause = cause,
                causeAt = causeAt, seenAt = seen and seen[faction.id] }
        end
    end
    return sortRows(rows)
end

-- Blocs (law, gang, raider...) group the 148 factions into a readable summary.
function M.blocOf(faction)
    return ProjectALife.RelationLayers.blocOf(faction) or "unaligned"
end

function M.blocs()
    local blocs, order = {}, {}
    for _, faction in ipairs(M.factions()) do
        local bloc = M.blocOf(faction)
        if blocs[bloc] == nil then
            blocs[bloc] = {}
            order[#order + 1] = bloc
        end
        table.insert(blocs[bloc], faction)
    end
    return blocs, order
end

-- Most common status in a list, plus its share (1.0 = unanimous). Ties go to the friendlier word.
function M.majority(statuses)
    local counts, best = {}, nil
    for _, status in ipairs(statuses) do counts[status] = (counts[status] or 0) + 1 end
    for _, status in ipairs({ "friendly", "neutral", "careful", "hostile" }) do
        if counts[status] and (best == nil or counts[status] > counts[best]) then best = status end
    end
    return best, best and counts[best] / #statuses or 0
end

local function blocRow(bloc, size, statuses, seenAt)
    local status, share = M.majority(statuses)
    if status == nil then return nil end
    local cause = share < 1 and (math.floor(share * 100 + 0.5) .. "%") or nil
    return { bloc = bloc, name = bloc .. " (" .. size .. ")", status = status, cause = cause, seenAt = seenAt }
end

-- subjectBloc == nil: how each bloc treats the player; otherwise how subjectBloc treats each bloc.
function M.blocRows(subjectBloc, player, nowHours, seen)
    local blocs, order = M.blocs()
    local overrides = subjectBloc == nil and M.overrides(M.myRelations(), nowHours) or nil
    local rows = {}
    for _, bloc in ipairs(order) do
        local statuses, seenAt = {}, nil
        for _, target in ipairs(blocs[bloc]) do
            local at = seen and seen[target.id]
            if at and (seenAt == nil or at > seenAt) then seenAt = at end
            if subjectBloc == nil then
                statuses[#statuses + 1] = (M.towardMe(target, player, overrides))
            else
                for _, source in ipairs(blocs[subjectBloc]) do
                    if source.id ~= target.id then statuses[#statuses + 1] = M.between(source, target) end
                end
            end
        end
        rows[#rows + 1] = blocRow(bloc, #blocs[bloc], statuses, seenAt)
    end
    return sortRows(rows)
end

-- Jeem Extension's standing: points per faction that move its label (hostile .. allied) up and down a ladder.
function M.hasStanding()
    local vars = SandboxVars and SandboxVars.ALifeJimmy
    return ProjectALifeJimmy ~= nil and not (vars and vars.Standing_Enabled == false)
end

-- Points on an even scale, -1 .. 1: every step between Jeem's thresholds (25, 75, 150, 250, then its clamp 400)
-- gets the same width, so the first step isn't a sliver.
function M.scale(points, thresholds, clamp)
    local edges = { 0 }
    for _, t in ipairs(thresholds) do edges[#edges + 1] = t end
    edges[#edges + 1] = clamp
    local size, sign = math.abs(points), points < 0 and -1 or 1
    for i = 2, #edges do
        if size <= edges[i] then
            return sign * (i - 2 + (size - edges[i - 1]) / (edges[i] - edges[i - 1])) / (#edges - 1)
        end
    end
    return sign
end

-- Jeem's standing labels, low to high. Allied gets its own colour here; elsewhere A-Life folds it into friendly.
M.LADDER = { "hostile", "careful", "neutral", "friendly", "allied" }
M.COLORS.allied = { 0.4, 0.85, 0.85 }
local LADDER_RANK = {}
for i, label in ipairs(M.LADDER) do LADDER_RANK[label] = i end

-- Where a standing sits on the ladder bar, 0 (hostile end) .. 1 (allied end), each label the same width.
-- 0 points is the middle of the faction's usual label; every threshold crossed is the edge of the next label,
-- so the marker lands on the label Jeem gives. Where Jeem decides otherwise (its own people are always allied),
-- the marker goes to the middle of Jeem's label.
function M.ladderPos(entry, thresholds, clamp)
    local n, points = #M.LADDER, entry.points
    local steps = math.abs(M.scale(points, thresholds, clamp)) * (#thresholds + 1) -- 25 -> 1, 75 -> 2 ...
    local shift = steps <= 1 and steps / 2 or steps - 0.5
    local at = (LADDER_RANK[entry.default] or 3) + (points < 0 and -shift or shift)
    local onLabel = points < 0 and math.ceil(at - 0.5) or math.floor(at + 0.5) -- an edge belongs to the new label
    local want = LADDER_RANK[entry.label]
    if want and math.max(1, math.min(n, onLabel)) ~= want then at = want end
    return (math.max(0.5, math.min(n + 0.5, at)) - 0.5) / n
end

-- standing: the server's snapshot (ALifeRelationsServer.standingOf). Highest points first. status is A-Life's
-- word for filters (allied -> friendly); label keeps Jeem's. pos and usualPos place the bar's marker and notch.
function M.standingRows(standing, seen)
    local rows = {}
    for id, entry in pairs(standing and standing.factions or {}) do
        local faction = M.faction(id)
        rows[#rows + 1] = { id = id, faction = faction, name = faction and M.nameOf(faction) or id,
            status = norm(entry.label) or "neutral", label = entry.label, points = math.floor(entry.points),
            pos = M.ladderPos(entry, standing.thresholds, standing.clamp),
            usualPos = ((LADDER_RANK[entry.default] or 3) - 0.5) / #M.LADDER, seenAt = seen and seen[id] }
    end
    table.sort(rows, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        return a.name < b.name
    end)
    return rows
end

-- What moved one faction's points (Jeem keeps the last 12), newest first.
function M.standingEvents(entry)
    local rows = {}
    for _, event in ipairs(entry and entry.events or {}) do
        local points = math.floor(tonumber(event.points) or 0) -- rounded down, as Jeem's own pages show it
        rows[#rows + 1] = { name = tostring(event.kind) .. (event.place and (" near " .. event.place) or ""),
            status = points < 0 and "hostile" or points > 0 and "friendly" or "neutral",
            change = string.format("%+d", points), atHours = tonumber(event.hours) }
    end
    table.sort(rows, function(a, b) return (a.atHours or 0) > (b.atHours or 0) end)
    return rows
end

-- Changes between two Reputation snapshots' relations lists, for notifications.
-- Returns { { factionId, status, cause } }; status == nil means the override was cleared.
function M.diff(old, new)
    local before, after, changes = {}, {}, {}
    for _, entry in ipairs(old or {}) do before[entry.factionId] = entry end
    for _, entry in ipairs(new or {}) do
        after[entry.factionId] = entry
        local previous = before[entry.factionId]
        if previous == nil or previous.status ~= entry.status or previous.cause ~= entry.cause then
            changes[#changes + 1] = { factionId = entry.factionId, status = norm(entry.status), cause = entry.cause }
        end
    end
    for id in pairs(before) do
        if after[id] == nil then changes[#changes + 1] = { factionId = id } end
    end
    return changes
end

return M
