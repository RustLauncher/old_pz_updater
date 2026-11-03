require "ProjectALife/Interface/Creator/ALifeCreatorCore"
require "ProjectALife/Core/ALifeText"

local Creator = ProjectALife.CreatorScreen

function Creator.buildFactionIdentityPage(window, setFactionEditorPage)
    local px = Creator.px
    local overview = window.factionEditorPages.overview
    local fieldX, fieldW = px(10), overview.width - px(40)
    Creator.addLabel(overview, px(10), px(14), "FACTION IDENTITY", Creator.palette.ROSE)
    Creator.addLabel(overview, px(10), px(50), "Faction name", Creator.palette.MUTED)
    window.factionName = Creator.addEntry(overview, fieldX, px(76), fieldW, "")
    Creator.addLabel(overview, px(10), px(122), "Category", Creator.palette.MUTED)
    window.factionCategory = Creator.addEntry(overview, fieldX, px(148), fieldW, "")
    Creator.addLabel(overview, px(10), px(194), "Description", Creator.palette.MUTED)
    window.factionDescription = Creator.addEntry(overview, fieldX, px(220), fieldW, "")
    Creator.addLabel(overview, px(10), px(273), "Unknown faction disposition", Creator.palette.MUTED)
    window.factionUnknownRelation = Creator.addCombo(overview, fieldX, px(299), fieldW, Creator.relationChoices)
    window.factionVisitorOnly = Creator.addTick(overview, fieldX, px(345), fieldW,
        "Visitor only: appears at your door during visits, never in the open world")
    window.factionVisitorOnly.changeOptionTarget = window
    window.factionVisitorOnly.changeOptionMethod = Creator.onVisitorTick
    Creator.addTooltip(window.factionVisitorOnly, "A visitor-only faction never spawns on its own, joins raids or counts toward world pressure. Its members only walk up to your door during visits.")
    local shortcutW = math.floor((fieldW - px(10)) / 2)
    Creator.addButton(overview, px(10), px(395), shortcutW, "SET UP SPAWNING", function() setFactionEditorPage("spawning") end, true)
    Creator.addButton(overview, px(20) + shortcutW, px(395), shortcutW, "SET UP SUPPORT", function() setFactionEditorPage("support") end)
    Creator.scrollPage(overview, px(446))
end

function Creator.onVisitorTick(window)
    if type(window) ~= "table" then return false end
    Creator.syncVisitorOnly(window)
    return true
end

function Creator.drawVisitorBadge(card)
    local record = card.record
    if type(record) ~= "table" or type(record.spawn) ~= "table" or record.spawn.visitorOnly ~= true then return end
    card:drawTextRight(ProjectALife.Text.ui("VISITOR"), card.width - Creator.px(8), Creator.px(38),
        Creator.palette.ROSE.r, Creator.palette.ROSE.g, Creator.palette.ROSE.b, 1, UIFont.Small)
end

function Creator.setFactionVisitorOnly(window, factionId, on)
    local record = window.catalog and window.catalog.factions and window.catalog.factions[factionId] or nil
    if record == nil then return false end
    if not Creator.flushEdits(window) then return false end
    local faction = Creator.factionFromRecord(record)
    faction.spawn = faction.spawn or {}
    if on then
        ProjectALife.CustomFactions.forceVisitorSpawn(faction.spawn)
    else
        ProjectALife.CustomFactions.releaseVisitorSpawn(faction.spawn, true)
    end
    if not ProjectALife.CustomFactions.save(faction) then
        if window.statusLabel then
            window.statusLabel:setName(ProjectALife.Text.ui("FACTION CHANGE FAILED - COULD NOT SAVE"))
        end
        return false
    end
    Creator.refreshFactions(window, window.currentFaction and window.currentFaction.id or nil)
    return true
end

function Creator.dragNeedsQuestion(window, factionId, toFolderId, proceed)
    local Folders = ProjectALife.CreatorFolders
    local record = window.catalog and window.catalog.factions and window.catalog.factions[factionId] or nil
    local current = Folders.folderForFaction(factionId)
    local kind = Folders.dragQuestion(record, current and current.id or Folders.unfiledId,
        toFolderId or Folders.unfiledId)
    if kind == nil then return false end
    Creator.askVisitorMove(window, kind, factionId, proceed)
    return true
end

function Creator.visitorQuestion(kind)
    if kind == "in" then
        return ProjectALife.Text.ui("Make this faction visitor-only? It will stop spawning in the open world.")
    end
    return ProjectALife.Text.ui("Return this faction to the open world?")
end

function Creator.askVisitorMove(window, kind, factionId, proceed)
    local modal = ISModalDialog:new(0, 0, Creator.px(440), Creator.px(150), Creator.visitorQuestion(kind), true,
        { window = window, kind = kind, id = factionId, proceed = proceed }, function(subject, button)
            if button.internal ~= "YES" then return end
            if Creator.setFactionVisitorOnly(subject.window, subject.id, subject.kind == "in") then
                subject.proceed()
            end
        end, nil)
    modal:initialise()
    modal:addToUIManager()
    modal.moveWithMouse = true
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
    window.visitorAsk = { kind = kind, factionId = factionId, modal = modal }
    return modal
end

return Creator
