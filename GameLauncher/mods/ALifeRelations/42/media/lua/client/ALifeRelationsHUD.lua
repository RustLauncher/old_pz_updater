-- In-world parts: change notifications, faction tags over NPCs, outpost marks on the world map.
require "ISUI/Maps/ISWorldMap"
require "PZAPI/ModOptions"
require "ALifeRelations"

local M = ALifeRelations

local TAG_REFRESH_MS = 500
local MODULE = "ALifeRelations"

-- Options > Mods, saved per player. Created at load so the game can fill in saved values; read live, so changes
-- apply at once. Tag range and the server switches are sandbox options (see ALifeRelations.lua).
local options = PZAPI.ModOptions:create(MODULE, "A-Life Faction Relations")
-- No "%" in labels or tooltips: the game passes them through getText, which reads % as a format code.
options:addTickBox("tags", "Faction tags", true,
    "Faction names over the A-Life NPCs you can see. The server can switch tags off for everyone.")
options:addSlider("tagHeight", "Tag height", 30, 150, 5, 85,
    "Moves faction tags up or down over NPCs' heads. 100 = one floor above the feet.")
options:addTickBox("map", "Outpost marks on the map", true,
    "Outposts you've been near, on the world map. The server can switch marks off for everyone.")
options:addTickBox("notify", "Change notifications", true,
    "A message over your head when your standing with a faction changes. History records changes either way.")
options:addKeyBind("window", "Faction Relations window", 0,
    "Opens or closes the Faction Relations window. Not bound at first, so it can't clash with another mod's key.")

local function option(id)
    return options:getOption(id):getValue()
end

-- The window's key, if one is bound; not while typing in chat.
Events.OnKeyPressed.Add(function(key)
    if key == nil or key <= 0 or key ~= option("window") or (ISChat and ISChat.focused) then return end
    local player = getSpecificPlayer(0)
    if player and not player:isDead() and M.available() and M.toggle then M.toggle(0) end
end)

-- Factions this character has met (see M.markSeen), saved with the player.
function M.seen(player)
    local data = player and player:getModData()
    if data == nil then return {} end
    data.ALifeRelationsSeen = data.ALifeRelationsSeen or {}
    return data.ALifeRelationsSeen
end

-- Changes to this character's standings (see M.addHistory), saved with the player.
function M.history(player)
    local data = player and player:getModData()
    if data == nil then return {} end
    data.ALifeRelationsHistory = data.ALifeRelationsHistory or {}
    return data.ALifeRelationsHistory
end

function M.request(playerNum, command)
    local player = getSpecificPlayer(playerNum)
    if isClient() then
        sendClientCommand(player, MODULE, command, {})
    elseif ALifeRelationsServer then
        ALifeRelationsServer.handle(player, command)
    end
end

-- Server -> client data ("outposts", "kills", "standing"); single player calls this directly.
function M.receive(command, args)
    if command == "outposts" then M.outposts = args.sites end
    if command == "kills" then M.kills = args.kills end
    if command == "standing" then M.standing = args end
    -- Single player hands over the server's own table, so a new count doesn't change the reference.
    if command ~= "outposts" and M.window then M.window.dirty = true end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module == MODULE then M.receive(command, args) end
    -- A-Life announces a new reputation level with a popup, not a resync. Ask for one so tags and marks catch up.
    if module == "ProjectALife" and command == "repPopup" and type(args) == "table" and args.from ~= nil then
        local store, player = ProjectALife.StatusStore, getSpecificPlayer(0)
        if store and store.request and player then store.request(player) end
    end
end)

local function myOverrides()
    return M.overrides(M.myRelations(), getGameTime():getWorldAgeHours())
end

-- 1. Notify when the server changes our standing with a faction.
local lastRelations, primed = nil, false

local function notify(player, relations)
    for _, change in ipairs(M.diff(lastRelations, relations)) do
        local faction = M.faction(change.factionId)
        if faction then
            local status, cause = change.status, change.cause
            if status == nil then
                -- The grudge was lifted; we're back to the faction's normal stance.
                status = M.towardMe(faction, player, {})
                M.addHistory(M.history(player), { factionId = change.factionId, status = status, cause = "cleared",
                    atHours = getGameTime():getWorldAgeHours() })
            end
            cause = M.causeText(cause)
            local text = M.nameOf(faction) .. ": now " .. string.upper(status)
                .. (cause and (" (" .. tostring(cause) .. ")") or "")
            if option("notify") then
                if status == "hostile" or status == "careful" then
                    HaloTextHelper.addBadText(player, text)
                else
                    HaloTextHelper.addGoodText(player, text)
                end
            end
        end
    end
end

local function checkReputation()
    local store = ProjectALife.StatusStore
    local reputation = store and store.reputation
    if reputation == nil or reputation.relations == lastRelations then return end
    local player = getSpecificPlayer(0)
    -- A standing change means we dealt with that faction. On the first sync this also backfills older history.
    -- History gets A-Life's raw entries; display text like "5h left" is added only when drawing.
    if player then
        local seen, history = M.seen(player), M.history(player)
        for _, entry in ipairs(reputation.relations or {}) do
            M.markSeen(seen, entry.factionId, tonumber(entry.atHours))
            M.addHistory(history, entry)
        end
    end
    -- The first sync after joining is old news; only report later changes.
    if primed and player then notify(player, reputation.relations) end
    lastRelations, primed = reputation.relations, true
end

-- 5. Faction tags over A-Life NPCs the player can see.
local tags, nextTagRefreshMs = {}, 0

local function recordOf(zombie)
    local data = zombie:hasModData() and zombie:getModData() or nil
    local uid = data and data.ProjectALifeUID
    if uid == nil then return nil end
    -- MP clients get nearby actor records mirrored; single player can read the registry directly.
    local mirror = ProjectALife.MirrorTransport
    local record = mirror and mirror.client and mirror.client.records and mirror.client.records[uid]
    if record == nil and ProjectALife.ActorRegistry then
        local ok, found = pcall(ProjectALife.ActorRegistry.peek, uid)
        record = ok and found or nil
    end
    return record
end

local function canSee(player, playerNum, zombie)
    local ok, alpha = pcall(zombie.getAlpha, zombie, playerNum)
    if ok and type(alpha) == "number" then return alpha > 0.1 end
    local seen
    ok, seen = pcall(player.CanSee, player, zombie)
    return ok and seen == true
end

local function refreshTags(player)
    tags = {}
    local cell = getCell()
    if cell == nil then return end
    local zombies = cell:getZombieList()
    local overrides, seen, hours = myOverrides(), M.seen(player), getGameTime():getWorldAgeHours()
    local range = M.serverNumber("TagRange", 15)
    for i = 0, zombies:size() - 1 do
        local zombie = zombies:get(i)
        if not zombie:isDead() and zombie:DistTo(player) <= range and canSee(player, 0, zombie) then
            local record = recordOf(zombie)
            local faction = record and M.faction(record.factionId)
            if faction then
                M.markSeen(seen, faction.id, hours)
                local profile = M.npc(record.profileId)
                tags[#tags + 1] = { zombie = zombie, name = M.nameOf(faction), title = profile and M.nameOf(profile),
                    color = M.COLORS[M.towardMe(faction, player, overrides)] }
            end
        end
    end
end

-- Where a faction tag goes on screen: the game's isometric projection. For add-ons with their own camera (a first or
-- third person view): replace ALifeRelations.tagScreenPos(x, y, z) to return screen x and y, or nil to skip that tag
-- (behind the camera). x, y and z are world tiles, z in floors with the tag height added. Kept if an add-on set it
-- before this file ran again (the game reloads mods when joining a server).
M.tagScreenPos = M.tagScreenPos or function(x, y, z)
    return isoToScreenX(0, x, y, z), isoToScreenY(0, x, y, z)
end

local function drawTags()
    local player = getSpecificPlayer(0)
    if player == nil or not M.available() or not M.serverAllows("Tags") or not option("tags") then return end
    local text, headZ = getTextManager(), option("tagHeight") / 100 -- label height above the feet, in floor levels
    local lineHeight = text:getFontHeight(UIFont.Small)
    for _, tag in ipairs(tags) do
        local zombie = tag.zombie
        if not zombie:isDead() then
            local x, y, z = zombie:getX(), zombie:getY(), zombie:getZ() + headZ
            local sx, sy = M.tagScreenPos(x, y, z)
            if sx and sy then
                text:DrawStringCentre(UIFont.Small, sx, sy, tag.name, tag.color[1], tag.color[2], tag.color[3], 1)
                -- The NPC's title (A-Life profile name) under the faction, dimmer.
                if tag.title then
                    text:DrawStringCentre(UIFont.Small, sx, sy + lineHeight, tag.title, 0.75, 0.75, 0.75, 0.8)
                end
            end
        end
    end
end

Events.OnTick.Add(function()
    if not M.available() then return end
    checkReputation()
    -- Scan even with tags off: the same pass records which factions we've met. drawTags checks the toggle.
    local player = getSpecificPlayer(0)
    if player == nil then
        tags = {}
        return
    end
    local now = getTimestampMs()
    if now >= nextTagRefreshMs then
        nextTagRefreshMs = now + TAG_REFRESH_MS
        refreshTags(player)
    end
end)

Events.OnPreUIDraw.Add(drawTags)

-- 6. Outposts the server says we've been near, drawn over the world map like vanilla stash maps.
local GONE = { 0.55, 0.55, 0.55 }

local function drawOutposts(map)
    local player = getSpecificPlayer(map.playerNum or 0)
    if player == nil or M.outposts == nil or not M.available() or not M.serverAllows("MapMarks")
        or not option("map") then return end
    local overrides = myOverrides()
    for _, site in pairs(M.outposts) do
        local faction = M.faction(site.factionId)
        local sx, sy = map.mapAPI:worldToUIX(site.x, site.y), map.mapAPI:worldToUIY(site.x, site.y)
        if faction and sx > 0 and sy > 0 and sx < map.width and sy < map.height then
            local color = site.gone and GONE or M.COLORS[M.towardMe(faction, player, overrides)]
            local label = M.nameOf(faction) .. (site.gone and (" (last seen day " .. site.lastSeenDay .. ")") or "")
            map:drawRect(sx - 5, sy - 5, 10, 10, 1, color[1], color[2], color[3])
            map:drawRectBorder(sx - 5, sy - 5, 10, 10, 1, 0, 0, 0)
            -- Dark backing: light stance colours are hard to read on the paper-coloured map.
            local width = getTextManager():MeasureStringX(UIFont.Small, label)
            map:drawRect(sx - width / 2 - 3, sy + 6, width + 6, getTextManager():getFontHeight(UIFont.Small) + 2,
                0.75, 0, 0, 0)
            map:drawTextCentre(label, sx, sy + 7, color[1], color[2], color[3], 1, UIFont.Small)
        end
    end
end

local baseRender = ISWorldMap.render
function ISWorldMap:render()
    baseRender(self)
    drawOutposts(self)
end
