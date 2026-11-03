ProjectALife = ProjectALife or {}

local Compat = {
    active = nil,        
    reported = false,
    lines = {},
    previewOffLogged = false,
    noticeShown = false, 
    metrics = { detected = 0, previewsRejected = 0, notices = 0 },
}
ProjectALife.ModCompat = Compat

Compat.known = {

    ProjectALifeReconstructed = { name = "Project A-Life, two builds", pair = "ProjectALifeNPCs", verdict = "incompatible",
        note = "two A-Life builds are enabled at once (ProjectALifeReconstructed and ProjectALifeNPCs); every file of one shadows the other -- enable only one" },
    ProjectALifeDevBuild = { name = "Project A-Life, two builds", pair = "ProjectALifeNPCs", verdict = "incompatible",
        note = "two A-Life builds are enabled at once (ProjectALifeDevBuild and ProjectALifeNPCs); every file of one shadows the other -- enable only one" },

    ProjectALifeJimmy = { adapter = "JeemResidents", name = "Project A-Life - Jeem Extension", verdict = "adapted",
        note = "its picked-over buildings, war dead and staged boarding are built into A-Life now; while the extension is enabled A-Life leaves those to it, so nothing runs twice. Its other features are unchanged" },
    WeaponLoadout = { name = "Weapon Loadout", verdict = "partial",
        note = "42.20.1 equip hooks checked: A-Life NPC equip and cleanup calls are guarded; player hooks stay active. Hooks registered before the shield are not covered" },
    CyesPushDoors = { adapter = "CyesPushDoors", name = "Cye's Push Doors", verdict = "adapted",
        note = "a pushed door hit A-Life NPCs as zombies (damage, knockdown, kill); the adapter keeps NPCs out of its target check, players and zombies unchanged" },
    moreTraitsDefinitive = { adapter = "MoreTraits", name = "More Traits Definitive", verdict = "partial",
        note = "trait bonus damage killed A-Life NPCs outright through MT.KillZombie; the adapter keeps NPCs out of it. Battering Ram and Bouncer knockdowns still reach NPCs (no seam in that mod)" },
    hf_point_blank = { adapter = "PointBlank", name = "Point Blank", verdict = "adapted",
        note = "its close-range execution picked A-Life NPCs as zombies and killed them in one shot; the adapter keeps NPCs out of its target check, plain zombies still get it" },
    GaelGunStore_B42 = { adapter = "GaelGunStore", name = "GaelGunStore-Firearms", verdict = "partial",
        note = "NPC-held Gael firearms draw correctly; later equip hooks are filtered but earlier hooks may still receive NPCs. Its zombie scan preserves stamped NPC guns. Presets need attachments. Its bow and grenade launcher still damage NPCs outside A-Life" },
    WanderingZombies = { adapter = "WanderingZombies", name = "Wandering Zombies", verdict = "adapted",
        note = "it re-pathed every zombie it saw, A-Life NPCs included (wander, homing, hordes); the adapter keeps NPCs out of its validity check, zombies unchanged. The WIP version has its own id and needs nothing" },
    PROJECTRVInterior42 = { adapter = "RVInterior", name = "Project RV Interior", verdict = "adapted",
        note = "RV insides are map cells far to the south-east and leaving one deletes every zombie near the room, NPCs included; nothing of A-Life is placed there, and a player inside counts as standing at his parked RV. The military add-on's cells are not covered" },
    Advanced_trajectorys_Realistic_Overhaul = { adapter = "AdvancedTrajectory", name = "Advanced Trajectory's Realistic Overhaul", verdict = "partial",
        note = "players report its bullets no longer hurt NPCs (they seem immune); a one-time notice says so in game. Its low-health finisher killed NPCs outright and in MP was replayed on every client, the adapter keeps NPCs out of it. Explosions (throwables, off by default) still kill NPCs in their radius outright" },
    Viewpoint3DTracerFix = { name = "Project Viewpoint - 3D Tracer Fix", verdict = "compatible",
        note = "it wraps A-Life's tracer add and render entry points and reads the tracer rounds to draw 3D streaks and a 3D muzzle flash under Project Viewpoint; A-Life keeps that table and those two functions stable, and its own 2D flash and streaks go quiet while the 3D view is on. A-Life's muzzle light and shot sounds still apply. The bridge flashes every shot, suppressed weapons included, and needs A-Life's bullet streaks option on" },
    PixelStrikeIndicator = { adapter = "PixelStrike", name = "Pixel Strike Indicator", verdict = "adapted",
        note = "its health bars kept the highest health ever seen as full, and A-Life lifts health for the length of each hit, so NPC bars sat near empty; the adapter measures NPCs against their own maximum" },
    AutoAll = { adapter = "AutoAll", name = "Auto All", verdict = "partial",
        note = "its \"ignore NPCs\" option did not recognise A-Life NPCs, so any NPC in sight stopped a job; with the option on, NPCs that are not hostile no longer stop it in single player and on a host. On a dedicated server's clients every NPC still stops the job" },
    GunsOfMarz = { name = "Guns of Marz", verdict = "compatible",
        note = "works, attachments included; with vanilla weapon replacement on it swaps vanilla guns hung on every zombie's back and holster for Marz ones, NPCs included (A-Life hangs its own back), and turns vanilla guns and ammo in an NPC's inventory into Marz items when he dies" },
    GoMAttachmentWorkbench = { name = "GoM Attachment Workbench", verdict = "compatible",
        note = "player crafting window only; nothing reaches NPCs" },
    ImprovisedSilencers = { name = "Improvised Silencers", verdict = "compatible",
        note = "its equip hook reads only the weapon, so an NPC gun with its suppressor gets the suppressor's stats" },
    WeaponModifiersFrameworkB42 = { name = "Weapon Modifiers B42", verdict = "partial",
        note = "equip hooks registered after the A-Life shield skip NPCs; earlier registrations are not protected. Loot rolls also give modifiers to guns dropped by NPCs" },
    AmmoLootDropGunsOfMarzB42 = { name = "Ammo Loot Drop (Guns of Marz)", verdict = "unsupported",
        note = "adds ammo to zombie corpse loot; not tested whether NPC corpses get it on top of their own drop" },
    ProjectExile = { adapter = "ProjectExile", name = "Project Exile", verdict = "adapted",
        note = "its gear affixes added damage and a stomp execution to player hits through setHealth, past A-Life's hit model; the adapter keeps NPCs out of that hit hook. NPC corpses' worn gear still gets its affixes (loot only)" },
    MarzGuns = { name = "Guns of Marz (old version)", verdict = "compatible",
        note = "works, attachments included; it restyles weapons hung on every zombie's back and holster, NPCs included" },

    ImmersiveSnow = { name = "Immersive Snow", verdict = "compatible",
        note = "footprints, vehicle snow and snow on clothes are visual, and snow wets a player's clothes; nothing there moves or targets NPCs. The NPC cold system reads the same vanilla climate values and treats the mod's ground snow like wet feet" },
    coldwinters = { name = "Cold Winters", verdict = "compatible",
        note = "it only lowers winter temperatures and adds blizzards through the climate manager; NPCs feel the colder air and get chilled sooner, no hook in common" },

    NeatUI_Framework = { name = "NeatUI Framework", verdict = "compatible",
        note = "replaces no vanilla function A-Life uses; on 42.20 it only adds three missing ISUIElement helpers" },
    Neat_Rocco = { name = "Neat Rocco's UI", verdict = "compatible",
        note = "restyles the A-Life creator's three confirm dialogs (its ISModalDialog redirect); YES/NO still reach A-Life unchanged" },
    Neat_Crafting = { name = "Neat Crafting", verdict = "compatible",
        note = "no shared hook with A-Life; a 55-mod log with all four Neat mods shows no Neat/A-Life error" },
    Neat_Building = { name = "Neat Building", verdict = "compatible",
        note = "no shared hook with A-Life" },
    NeatLockpicking = { name = "Neat Lockpicking", verdict = "compatible",
        note = "no shared hook with A-Life (its own sandbox tooltips log format errors with or without A-Life)" },

    ["Band" .. "itsWeekOne"] = { verdict = "incompatible",
        note = "A-Life NPCs vanish while it runs; not forced -- enable one or the other" },
    ["Band" .. "its2"] = { verdict = "unsupported",
        note = "another NPC system on zombie bodies; not tested together with A-Life" },
    KnoxEventExpandedNpc = { name = "Knox Event Expanded NPC", verdict = "unsupported",
        note = "replaces engine classes (IsoPlayer, BodyDamage, CombatManager) for its own NPCs" },
    KnoxEventExpandedNpcLegacy = { name = "Knox Event Expanded NPC Legacy", verdict = "unsupported",
        note = "as Knox Event Expanded, and ships a 42.12 copy of the vanilla character creation screen" },

    improvedhairmenubuild42 = { name = "Improved Hair Menu", verdict = "adapted",
        note = "with Reorganized Info Screen it replaces ISUI3DModel without setAnimSetName/clearVariables; if so the A-Life creator's 3D preview switches itself off and everything else in the creator keeps working" },

    ["FantasyWorkshopVS42_4.0"] = { name = "oldcat body textures", verdict = "compatible",
        note = "reskins female living bodies, A-Life NPCs included" },
}

Compat.warnings = {
    Advanced_trajectorys_Realistic_Overhaul = "Advanced Trajectory's Realistic Overhaul is enabled.\n"
        .. "Players report that with it, your gunshots stop hurting A-Life NPCs,\n"
        .. "so NPCs seem immune to bullets. Disable it if your shots do not hurt NPCs.",
}

for _, id in ipairs({ "42_VSGirlBodySFW", "42_VSGirlBodyNSFW", "42_VSGirlBodyL",
        "42_VSGirlBodyL_M", "42_VSGirlBodyAll_female" }) do
    Compat.known[id] = { name = "VariableSkin", verdict = "compatible",
        note = "reskins living bodies -- A-Life NPCs included, the same as the player" }
end

local function readActive()
    local set = {}
    pcall(function()
        if type(getActivatedMods) ~= "function" then return end
        local mods = getActivatedMods()
        if mods == nil then return end
        local ids = {}
        if type(mods.size) == "function" and type(mods.get) == "function" then
            for index = 0, mods:size() - 1 do ids[#ids + 1] = mods:get(index) end
        elseif type(mods.toArray) == "function" then
            ids = mods:toArray()
        end
        for _, value in pairs(ids or {}) do
            local id = string.gsub(tostring(value), "^\\+", "")
            set[id], set[string.lower(id)] = true, true
        end
    end)
    return set
end

function Compat.activeSet()
    if Compat.active == nil then Compat.active = readActive() end
    return Compat.active
end

function Compat.refreshActiveSet()
    Compat.active = readActive()
    return Compat.active
end

function Compat.isActive(id)
    local set = Compat.activeSet()
    return set[id] == true or set[string.lower(tostring(id))] == true
end

Compat.layout = "domains"
Compat.ownIds = { ProjectALifeNPCs = true, ProjectALifeReconstructed = true, ProjectALifeDevBuild = true }

Compat.probePaths = {
    "media/lua/client/ProjectALife/UI/ALifeCreatorScreen.lua",
    "media/lua/client/ProjectALife/UI/ALifeContextMenu.lua",
    "media/lua/client/ProjectALife/UI/ALifeMenuPrefs.lua",
    "media/lua/client/ProjectALife/UI/ALifeDebugSpawner.lua",
    "media/lua/shared/ProjectALife/Data/ALifeCatalog.lua",
    "media/lua/shared/ProjectALife/Data/ALifeOutpostPresets.lua",
    "media/lua/shared/ProjectALife/Dialogue/ALifeDialogueData.lua",
    "media/lua/server/ProjectALife/Runtime/ALifeRuntime.lua",
    "media/lua/client/ProjectALife/Interface/Creator/ALifeCreatorCore.lua",
    "media/lua/client/ProjectALife/Interface/ALifeContextMenu.lua",
    "media/lua/shared/ProjectALife/Compat/ALifeEquipEventShield.lua",
    "media/lua/shared/ProjectALife/Presentation/ALifeAnimations.lua",
}

function Compat.shipsFile(modId, path)
    if type(getModFileReader) ~= "function" then return false end
    local ok, reader = pcall(getModFileReader, modId, path, false)
    if not ok or reader == nil then return false end
    if type(reader.close) == "function" then pcall(reader.close, reader) end
    return true
end

function Compat.modDir(id)
    if type(getModInfoByID) ~= "function" then return nil end
    local ok, info = pcall(getModInfoByID, id)
    if not ok or info == nil or type(info.getDir) ~= "function" then return nil end
    local read, dir = pcall(info.getDir, info)
    if not read or dir == nil or tostring(dir) == "" then return nil end
    dir = string.lower((string.gsub(tostring(dir), "\\", "/")))
    if string.sub(dir, -1) ~= "/" then dir = dir .. "/" end
    return dir
end

function Compat.ownerOf(path, dirs)
    local owner, size = nil, 0
    for _, entry in ipairs(dirs) do
        if #entry.dir > size and string.find(path, entry.dir, 1, true) == 1 then
            owner, size = entry.id, #entry.dir
        end
    end
    return owner
end

function Compat.isOwn(id)
    if Compat.ownIds[id] then return true end
    local low = string.lower(tostring(id))
    for own in pairs(Compat.ownIds) do
        if string.lower(own) == low then return true end
    end
    return false
end

function Compat.distinctIds(active)
    local ids, mixed = {}, {}
    for id in pairs(active or {}) do
        if id ~= string.lower(id) then mixed[string.lower(id)] = true end
    end
    for id in pairs(active or {}) do
        if not Compat.isOwn(id) and (id ~= string.lower(id) or not mixed[id]) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

function Compat.foreignLua(active)
    local shipped = {}
    if type(getLoadedLuaCount) ~= "function" or type(getLoadedLua) ~= "function" then return shipped end
    local own, other = {}, {}
    for id in pairs(active or {}) do
        local dir = Compat.isOwn(id) and Compat.modDir(id) or nil
        if dir ~= nil then own[#own + 1] = { id = id, dir = dir } end
    end
    for _, id in ipairs(Compat.distinctIds(active)) do
        local dir = Compat.modDir(id)
        if dir ~= nil then other[#other + 1] = { id = id, dir = dir } end
    end
    if #other == 0 then return shipped end
    for index = 0, (tonumber(getLoadedLuaCount()) or 0) - 1 do
        local raw = string.gsub(tostring(getLoadedLua(index) or ""), "\\", "/")
        local low = string.lower(raw)
        local at = string.find(low, "/media/lua/[^/]+/projectalife/")

        if at ~= nil and Compat.ownerOf(low, own) == nil then
            local owner = Compat.ownerOf(low, other)
            if owner ~= nil and shipped[owner] == nil then
                shipped[owner] = string.sub(#raw == #low and raw or low, at + 1)
            end
        end
    end
    return shipped
end

function Compat.foreignCopies(active)
    local lines = {}
    local ids = Compat.distinctIds(active)
    local found, rebound = {}, {}
    local scanned, shipped = pcall(Compat.foreignLua, active)
    if not scanned then
        print("[A-Life] compat: loaded Lua scan failed: " .. tostring(shipped))
        shipped = {}
    end
    for _, id in ipairs(ids) do
        local copied = false
        for _, path in ipairs(Compat.probePaths) do
            if Compat.shipsFile(id, path) then
                found[#found + 1] = id
                lines[#lines + 1] = string.format("%s (%s) -> incompatible: ships its own copy of A-Life's %s; "
                    .. "it replaces or runs beside A-Life's file and breaks on updates. "
                    .. "A translation should ship only Translate files", id, id, path)
                copied = true
                break
            end
        end
        if not copied and shipped[id] ~= nil then
            found[#found + 1] = id
            lines[#lines + 1] = string.format("%s (%s) -> incompatible: ships Lua inside A-Life's folders (%s); "
                .. "it replaces or runs beside A-Life's files and breaks on updates. "
                .. "A translation should ship only Translate files", id, id, shipped[id])
        end
    end
    local creator = ProjectALife.CreatorScreen
    if type(creator) == "table" and creator.layout ~= Compat.layout then
        rebound[#rebound + 1] = "ProjectALife.CreatorScreen"
        lines[#lines + 1] = "A-Life Creator -> incompatible: another mod re-bound ProjectALife.CreatorScreen "
            .. "with an old copy of the Creator; remove that mod's A-Life Lua files"
    end
    local shield = ProjectALife.EquipEventShield
    if type(shield) == "table" and type(shield.withCleanup) ~= "function" then
        rebound[#rebound + 1] = "ProjectALife.EquipEventShield"
        lines[#lines + 1] = "A-Life equip shield -> incompatible: another mod re-bound ProjectALife.EquipEventShield "
            .. "with an old copy that has no withCleanup; every NPC spawn fails until that mod's A-Life Lua files are removed"
    end
    local animations = ProjectALife.Animations
    if type(animations) == "table" and type(animations.migrateHeldBump) ~= "function" then
        rebound[#rebound + 1] = "ProjectALife.Animations"
        lines[#lines + 1] = "A-Life animations -> incompatible: another mod re-bound ProjectALife.Animations "
            .. "with an old copy that has no migrateHeldBump; NPCs throw errors and stutter until that mod's A-Life Lua files are removed"
    end
    return lines, found, rebound
end

function Compat.displayName(id)
    if type(getModInfoByID) ~= "function" then return id end
    for _, key in ipairs({ id, "\\" .. id }) do
        local ok, info = pcall(getModInfoByID, key)
        if ok and info ~= nil and type(info.getName) == "function" then
            local named, name = pcall(info.getName, info)
            if named and name ~= nil and tostring(name) ~= "" then
                return tostring(name) .. " (" .. id .. ")"
            end
        end
    end
    return id
end

function Compat.noticeText(found, rebound)
    found, rebound = found or {}, rebound or {}
    if #found == 0 and #rebound == 0 then return nil end
    local names = {}
    for _, id in ipairs(found) do names[#names + 1] = Compat.displayName(id) end

    local effect = "A-Life NPCs can throw errors, freeze or fail to spawn until "
    for _, name in ipairs(rebound) do
        if name == "ProjectALife.EquipEventShield" then effect = "A-Life NPCs will not spawn until " end
    end
    local text
    if #names == 0 then
        text = "Project A-Life: another mod replaced part of A-Life's Lua with an old copy.\n"
            .. effect .. "that mod is disabled."
    elseif #names == 1 then
        text = "Project A-Life: the mod " .. names[1] .. "\n"
            .. "ships Lua files inside A-Life's own folders.\n"
            .. effect .. "it is disabled."
    else
        text = "Project A-Life: these mods ship Lua files inside A-Life's own folders:\n"
            .. table.concat(names, "\n") .. "\n"
            .. effect .. "they are disabled."
    end
    text = text .. "\nDisable or unsubscribe " .. (#names > 1 and "them" or "it")
        .. " in the mod list. A translation should ship only Translate files."
    if #rebound > 0 then text = text .. "\nReplaced: " .. table.concat(rebound, ", ") end
    return text
end

function Compat.warningText(active)
    local texts = {}
    for id, text in pairs(Compat.warnings) do
        if type(active) == "table" and (active[id] == true or active[string.lower(id)] == true) then
            local entry, registry = Compat.known[id], ProjectALife.CompatRegistry
            if entry ~= nil and entry.adapter ~= nil and registry ~= nil then
                local state = registry.status(entry.adapter)
                text = text .. "\nA-Life adapter " .. entry.adapter .. ": " .. state
                if state ~= "applied" then text = text .. "; its protection is not active in this realm" end
            end
            texts[#texts + 1] = "Project A-Life: " .. text
        end
    end
    if #texts == 0 then return nil end
    table.sort(texts)
    return table.concat(texts, "\n\n")
end

function Compat.showNotice(text)
    if text == nil or Compat.noticeShown then return false end
    if type(isServer) == "function" and isServer() == true then return false end
    local dialog = ISModalDialog
    if type(dialog) ~= "table" or type(dialog.new) ~= "function" or type(getCore) ~= "function" then return false end
    Compat.noticeShown = true
    local ok, failure = pcall(Compat.openNotice, dialog, text)
    if not ok then
        print("[A-Life] compat: notice failed: " .. tostring(failure))
        return false
    end
    Compat.metrics.notices = Compat.metrics.notices + 1
    return true
end

function Compat.openNotice(dialog, text)
    local core = getCore()
    local width, height = 560, 170
    local modal = dialog:new(core:getScreenWidth() / 2 - width / 2, core:getScreenHeight() / 2 - height / 2,
        width, height, text, false, nil, nil, 0)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
    if type(JoypadState) == "table" and type(JoypadState.players) == "table"
            and JoypadState.players[1] ~= nil and type(setJoypadFocus) == "function" then
        setJoypadFocus(0, modal)
    end
end

function Compat.report()
    if Compat.reported then return Compat.lines end
    Compat.reported = true
    local active = Compat.activeSet()
    local lines = {}
    for id, entry in pairs(Compat.known) do
        local present = active[id] == true or active[string.lower(id)] == true
        if entry.pair ~= nil then present = present and active[entry.pair] == true end
        if present then
            lines[#lines + 1] = Compat.entryLine(id, entry)
        end
    end
    local copies, found, rebound = Compat.foreignCopies(active)
    for _, line in ipairs(copies) do lines[#lines + 1] = line end
    table.sort(lines)
    Compat.lines = lines
    Compat.metrics.detected = #lines
    for _, line in ipairs(lines) do print("[A-Life] compat: " .. line) end
    local text, warning = Compat.noticeText(found, rebound), Compat.warningText(active)
    if text == nil then
        text = warning
    elseif warning ~= nil then
        text = text .. "\n\n" .. warning
    end
    Compat.showNotice(text)
    return lines
end

function Compat.entryLine(id, entry)
    local registry = ProjectALife.CompatRegistry
    local verdict, note = entry.verdict, entry.note
    if entry.adapter ~= nil and registry ~= nil then
        local state, reason = registry.status(entry.adapter)
        if state ~= "applied" then
            verdict = "unadapted"
            note = "A-Life adapter " .. entry.adapter .. " is " .. state .. " (" .. tostring(reason or "startup")
                .. "); its protection is not active in this realm"
        else
            note = note .. " [adapter " .. entry.adapter .. "=applied]"
        end
    end
    return string.format("%s (%s) -> %s: %s", entry.name or id, id, verdict, note)
end

function Compat.onStart()
    local registry = ProjectALife.CompatRegistry
    if registry ~= nil and type(registry.start) == "function" then registry.start() end
    return Compat.report()
end

function Compat.snapshot()
    return { detected = Compat.metrics.detected, lines = Compat.lines,
        previewsRejected = Compat.metrics.previewsRejected }
end

function Compat.previewSupported(avatar)
    return avatar ~= nil and avatar.setAnimSetName ~= nil and avatar.clearVariables ~= nil
end

function Compat.supportedPreviews(list)
    if type(list) ~= "table" then return {} end
    local allGood = true
    for _, avatar in ipairs(list) do
        if not Compat.previewSupported(avatar) then allGood = false break end
    end
    if allGood then return list end
    local kept = {}
    for _, avatar in ipairs(list) do
        if Compat.previewSupported(avatar) then
            kept[#kept + 1] = avatar
        else
            Compat.metrics.previewsRejected = Compat.metrics.previewsRejected + 1
            pcall(function() avatar:setVisible(false) end)
        end
    end
    if not Compat.previewOffLogged then
        Compat.previewOffLogged = true
        print("[A-Life] compat: incompatible: another mod replaced ISUI3DModel without "
            .. "setAnimSetName/clearVariables (Improved Hair Menu with Reorganized Info Screen does this); "
            .. "the A-Life creator's 3D preview is off, the rest of the creator works")
    end
    return kept
end

if type(Events) == "table" then
    for _, name in ipairs({ "OnGameStart", "OnServerStarted" }) do
        local event = Events[name]
        if event ~= nil and type(event.Add) == "function" then event.Add(Compat.onStart) end
    end
end

return Compat
