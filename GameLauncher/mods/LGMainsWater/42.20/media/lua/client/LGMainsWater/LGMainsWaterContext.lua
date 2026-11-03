require "ISUI/ISWorldObjectContextMenu"
require "LGMainsWater/LGMainsWaterCore"
require "TimedActions/LGPlumbMainsAction"

local MW = LGMainsWater

local function predicateNotBroken(item)
    return not item:isBroken()
end

local function findWrench(playerObj)
    local inventory = playerObj:getInventory()
    return inventory:getFirstTypeEvalRecurse("PipeWrench", predicateNotBroken)
        or inventory:getFirstTagEvalRecurse(ItemTag.PIPE_WRENCH, predicateNotBroken)
end

--- A separate entry from vanilla's "Plumb", not a replacement for it. The two do
--- genuinely different jobs -- vanilla's attaches a rain collector barrel, this
--- one connects to the building's own supply -- so both are offered where both
--- apply, and nothing of vanilla's plumbing is overridden.
function MW.onPlumbMains(worldobjects, player, fixture)
    local playerObj = getSpecificPlayer(player)
    local wrench = findWrench(playerObj)
    if not wrench then return end
    ISWorldObjectContextMenu.equip(playerObj, playerObj:getPrimaryHandItem(), wrench, true)
    ISTimedActionQueue.add(LGPlumbMainsAction:new(playerObj, fixture, wrench))
end

--- `worldobjects` is not the list vanilla built.
---
--- Every handler on OnFillWorldObjectContextMenu is handed the SAME table, so one
--- that ran earlier and appended to it has changed what this one reads. Vanilla's
--- own AdminContextMenu.doMenu does exactly that -- it pushes every object on the
--- clicked square into the caller's table, and the `removeDuplicates` line under
--- the loop rebinds a local rather than undoing it. It runs for an admin or a
--- moderator and for nobody else, which on a hosted co-op game means the host and
--- none of their friends.
---
--- Nothing here is hurt by the extra entries -- this walks the whole square anyway,
--- and the loop below is idempotent -- but it is why the handler is guarded rather
--- than trusted, and why nothing in this file assumes an object is one vanilla
--- vouched for.
local function findFixture(worldobjects)
    for _, object in ipairs(worldobjects) do
        local square = object:getSquare()
        if square then
            local objects = square:getObjects()
            for i = 0, objects:size() - 1 do
                local candidate = objects:get(i)
                if MW.canPlumbToMains(candidate) then return candidate end
            end
        end
    end
    return nil
end

--- Vanilla's "Plumb <fixture>" is built Java-side, by
--- ISWorldObjectContextMenuLogic.doWaterPipeMenu inside createMenuEntries, and
--- createMenuEntries runs to completion before ISWorldObjectContextMenu.createMenu
--- fires OnFillWorldObjectContextMenu -- so by the time this file is called the
--- vanilla option is already sitting in context.options and can be inserted after.
---
--- ISContextMenu:insertOptionAfter matches on the option's display text, and
--- vanilla's is getText("ContextMenu_PlumbItem", <moveable display name>). Rather
--- than assume vanilla picked the same object we did, the label is found by
--- matching that translation with its argument wildcarded: the two menus reach the
--- fixture by different routes (vanilla walks worldobjects, findFixture below walks
--- the whole square), so the names can in principle disagree.
local function findVanillaPlumbOptionName(context)
    -- getText with no arguments returns the entry unformatted, placeholder intact.
    local template = getText("ContextMenu_PlumbItem")
    local placeholder = "\1"
    template = template:gsub("%%1%$s", placeholder):gsub("%%1", placeholder)
    local escaped = template:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    local pattern = "^" .. escaped:gsub(placeholder, ".*") .. "$"

    for _, option in ipairs(context.options) do
        if option.name and option.name:match(pattern) then return option.name end
    end
    return nil
end

--- Vanilla's *Plumb* is only offered in some of the cases ours is -- it wants a
--- rain barrel overhead, or the town water still running -- so anchoring on it
--- alone drops the option to the bottom of the menu the rest of the time, which
--- is a different place for the same fixture depending on the day.
---
--- The slot itself is stable even when the option that marks it is not. Java adds
--- the plumbing option immediately before the fixture's own fluid menu, and that
--- menu's parent option is labelled with getMoveableDisplayName -- the same name
--- this file already builds its label from. So the fixture's own submenu pins the
--- position from below, and the option sits above it either way:
---
---     Plumb Sink                 <- vanilla, when it applies
---     Connect Sink to water...   <- always here
---     Sink                    >  <- vanilla's fluid menu for the same fixture
local function anchorFor(context, name)
    local plumb = findVanillaPlumbOptionName(context)
    if plumb then return context.insertOptionAfter, plumb end
    if name ~= "" and context:getOptionFromName(name) then
        return context.insertOptionBefore, name
    end
    return nil, nil
end

--- context:addGetUpOption, but placed at that anchor. There is no insert-at
--- counterpart to it, so this repeats what it does: the get-up wrapper is the
--- real onSelect, with the caller's function and arguments carried as params.
local function insertGetUpOption(context, place, anchor, label, worldobjects, onSelect, player, fixture)
    if not place then
        return context:addGetUpOption(label, worldobjects, onSelect, player, fixture)
    end
    return place(context, anchor, label, context, context.onGetUpAndThen,
        onSelect, worldobjects, player, fixture)
end

local function onFillWorldObjectContextMenu(player, context, worldobjects, test)
    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end

    local fixture = findFixture(worldobjects)
    if not fixture then return end

    if test then return ISWorldObjectContextMenu.setTest() end

    local name = ISWorldObjectContextMenu.getMoveableDisplayName(fixture) or ""
    local label = getText("ContextMenu_LGMainsWater_Plumb", name)
    local place, anchor = anchorFor(context, name)
    local option = insertGetUpOption(context, place, anchor, label,
        worldobjects, MW.onPlumbMains, player, fixture)
    option.iconTexture = getTexture("Item_PipeWrench")

    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip:setName(label)
    if findWrench(playerObj) then
        tooltip.description = getText("Tooltip_LGMainsWater_Plumb")
    else
        option.notAvailable = true
        tooltip.description = getText("Tooltip_NeedWrench", getItemNameFromFullType("Base.PipeWrench"))
    end
    option.toolTip = tooltip
end

--- Guarded as a whole, and reported once.
---
--- This runs inside ISWorldObjectContextMenu.createMenu, and every mod's world menu
--- entries share the one event. An error escaping a handler stops the handlers
--- registered after it from ever running -- so a mistake here does not read to a
--- player as this mod being broken, it reads as some other mod being broken. And it
--- is silent: Event.java wraps each callback in protectedCallVoid and logs, so the
--- options are simply absent with nothing on screen to say why.
---
--- If this fails the cost is one missing option, which is the right trade against
--- every other mod's entries. Once per session rather than once per menu: this
--- fires from a right-click, so a repeating fault would be a line per click.
local reportedFault = false

Events.OnFillWorldObjectContextMenu.Add(function(player, context, worldobjects, test)
    local ok, err = pcall(onFillWorldObjectContextMenu, player, context, worldobjects, test)
    if not ok and not reportedFault then
        reportedFault = true
        print("[LGMainsWater] ERROR adding the connect option: " .. tostring(err)
            .. " (reported once; further failures are silent)")
    end
end)
