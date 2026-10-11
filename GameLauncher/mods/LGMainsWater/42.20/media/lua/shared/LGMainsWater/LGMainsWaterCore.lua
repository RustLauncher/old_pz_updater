--- Connects a fixture the player installed to the building's water system.
---
--- A fixture the player places is stamped `canBeWaterPiped = true` by
--- ISMoveableSpriteProps, and that flag alone makes IsoObject.isWaterInfinite()
--- bail out -- so a placed sink is dry even while the supply is still running,
--- and the only thing vanilla lets you pipe it to is a rain collector barrel.
---
--- The whole of isWaterInfinite() is:
---
---     sprite waterAmount >= 9999                -> true   (camping water sources)
---     square == null or square:getRoom() == nil -> false
---     sprite lacks waterPiped                   -> false
---     getUsesExternalWaterSource()              -> false
---     square:isNoWater()                        -> false
---     past the shutoff day                      -> false
---     modData.canBeWaterPiped == true           -> false
---     otherwise                                    true
---
--- Every line is either already true of a placed fixture, or is a flag this
--- action sets, bar one: getRoom(), which is map data and cannot be forged.
---
--- So the job is to leave the fixture holding exactly the flags a fixture the map
--- spawned holds, and then get out of the way. What that is worth is the world's
--- business, and it is the same answer for this fixture as for the ones the
--- building came with.
---
--- Whether to OFFER the connect is a separate question from what the connect
--- writes, and it is the one place this file does look outward. A fixture
--- connected to a supply that is off, or to a building that never had one, has
--- gained precisely nothing -- plumb() zeroes the pipe reserve in exactly that
--- case -- so the option is not shown when there is nothing at the other end of
--- the pipe. See MW.isMainsSupplyOn, which re-asks the game on every right-click
--- rather than settling the answer once.
---
--- The two flags, and what each means:
---
---   canBeWaterPiped         "this was carried in and is not connected to
---                           anything". Cleared, exactly as vanilla's own plumb
---                           action clears it.
---   usesExternalWaterSource "this runs off a rain barrel above it". Every water
---                           read on the object short-circuits to that barrel
---                           when it is set, which is why setting it on a working
---                           sink cuts the sink off from the mains. This mod only
---                           ever clears it, and only offers to when there is no
---                           barrel overhead to run off; vanilla's plumb action
---                           still sets it, and is left alone to do so.

LGMainsWater = LGMainsWater or {}
local MW = LGMainsWater

--- Fixtures the game itself treats as plumbed in: sinks, baths, showers,
--- toilets, washing machines and washer/dryers all carry the waterPiped flag.
--- isWaterInfinite() and isUnmovedPipedWaterSource() both require it, so this is
--- not a choice -- it is the exact set the building's water system can reach.
function MW.isPlumbableFixture(obj)
    if not obj or not obj:getSquare() then return false end
    local sprite = obj:getSprite()
    return sprite ~= nil and sprite:getProperties():has(IsoFlagType.waterPiped)
end

--- Is this fixture already part of the building's water system?
--- A fixture the map spawned has no canBeWaterPiped key at all and no barrel
--- attached, and that is the state MW.plumb produces, so the same test covers
--- both and the option is never offered for something already connected.
---
--- Audited: hasModData() is `table != null && !table.isEmpty()` (IsoObject.java), so
--- it answers false for an EMPTY table and not only a missing one - which is the
--- weakness that cost Extended Plumbing a dead context menu. It is harmless here, and
--- deliberately left alone. An empty table has no canBeWaterPiped key, so dropping the
--- guard would give the identical answer in every case; it is there to avoid
--- materialising getModData()'s table for every fixture examined, not to decide
--- anything. Nothing downstream can be hurt by the fallible direction, because the
--- fallible direction is "treat a fixture as already plumbed", which is the state the
--- map ships them in.
function MW.isOnBuildingSupply(obj)
    if obj:getUsesExternalWaterSource() then return false end
    return not (obj:hasModData() and obj:getModData().canBeWaterPiped == true)
end

--- Is this square inside a building the map defines, as opposed to a structure
--- the player raised from nothing?
---
--- getRoom() alone is not that test, and answers differently on the two sides of
--- a multiplayer game. An enclosed player-built region is turned into a RoomDef
--- by WorldRegionToMetaGrid.regionToRoomDef and merged onto the metagrid, and
--- IsoRegions.update() runs that only when GameServer.server is false -- so in
--- singleplayer and on a multiplayer client a player-built shack has a room,
--- while on the dedicated server the same square has roomId -1 and no room at
--- all. Testing getRoom() by itself would offer the option on a client and then
--- have the server disagree about whether the fixture has water.
---
--- The synthesised RoomDefs are flagged `userDefined`, and regionToRoomDef is the
--- only place in the game that ever writes that field, so it means exactly
--- "grown from a player-built region" and nothing else. Testing both agrees on
--- every side:
---
---                              dedicated server   singleplayer / MP client
---   map-defined building       room, not user     room, not user      -> yes
---   freestanding player shack  no room            room, userDefined   -> no
---   lean-to against a house    no room            no room             -> no
---
--- The lean-to case is not an oversight of the game's: a synthesised building
--- adjacent to or overlapping a predefined one is discarded rather than merged
--- (isAdjacentToOrOverlappingAPredefinedBuilding -> discardBuilding), so those
--- squares end up in no room on either side. Renovating *inside* an original
--- building is different and still qualifies -- the original's map RoomDef still
--- covers the square, which is the right answer.
function MW.isInSpawnedBuilding(square)
    return square:getRoom() ~= nil and not square:isUserDefinedRoom()
end

--- Is the town water supply still running, right now?
---
--- There is no engine flag for this and no getter to call. The whole of the world
--- supply is one comparison, written out longhand in each of the three places
--- that ask it -- IsoObject.isWaterInfinite(), the `preWaterShutoff` local in
--- ISWorldObjectContextMenuLogic.fetch that gates vanilla's own Plumb option, and
--- ParameterWaterSupply for the audio -- and this is a fourth copy of it:
---
---     worldAgeHours / 24 + (timeSinceApo - 1) * 30 >= WaterShutModifier  -> off
---
--- Both ends of the sandbox range fall out of the plain comparison, so neither is
--- special-cased: SandboxOptions.randomWaterShut yields -1 for "Instant" (day
--- zero is already past -1) and Integer.MAX_VALUE for "Never".
---
--- ## Why this is dynamic
---
--- Read off the live SandboxOptions object, NOT off the SandboxVars table, and
--- that is the whole of what makes it answer a mod that turns the supply back on.
--- SandboxVars is a Lua copy taken once at load (initSandboxVars -> fromTable,
--- toTable); IntegerConfigOption.getValue() hands back the Java field, and the
--- Java field is the one isWaterInfinite() reads. A mod that restores the mains
--- has to move that field or the water does not actually come back on -- so
--- asking for it agrees with the game by construction, however the mod did it,
--- and asking on every right-click means a supply restored mid-session is picked
--- up with no event to subscribe to and nothing to invalidate.
---
--- ## Why it is not asked of the object, as plumb() asks
---
--- plumb() gets away with reading getFluidCapacity() because by the time it does,
--- the fixture already holds a spawned fixture's flags, and with those set the
--- engine reports 10000 exactly when isWaterInfinite() is true. Here the fixture
--- still carries canBeWaterPiped -- that is what is about to be cleared -- and
--- that flag alone makes isWaterInfinite() false, so the object answers "no
--- supply" for every fixture the option would ever be offered on. It cannot be
--- the question and the answer.
---
--- ## On a multiplayer client
---
--- This runs client-side, where the context menu is built, and it is as right
--- there as vanilla's own gate: GameTime and the sandbox options are both server
--- state pushed to the client, and ISWorldObjectContextMenuLogic.fetch does this
--- identical arithmetic on the same side for the same purpose.
function MW.isMainsSupplyOn()
    local sandbox = getSandboxOptions()
    local days = getGameTime():getWorldAgeHours() / 24
        + (sandbox:getTimeSinceApo() - 1) * 30
    return days < sandbox:getWaterShutModifier()
end

--- Should the connect option be offered?
function MW.canPlumbToMains(obj)
    if not MW.isPlumbableFixture(obj) then return false end
    if MW.isOnBuildingSupply(obj) then return false end

    local square = obj:getSquare()

    -- Also the one condition of isWaterInfinite() that cannot be set from Lua:
    -- getRoom() returns null whenever roomId is -1, and roomId is map data. There
    -- are no pipes under a field either way.
    if not MW.isInSpawnedBuilding(square) then return false end

    -- And the two that decide whether there is anything at the far end of the
    -- pipe. Connecting is not wrong in either case -- it leaves the fixture as dry
    -- as the building's own, which is the honest answer -- but it is a wrench, a
    -- walk and a hundred ticks spent on a fixture that gains nothing, and plumb()
    -- empties the reserve rather than handing out a free 20 units, so there is not
    -- even that.
    --
    -- isNoWater() is the building side and never changes: a derelict square, or a
    -- NoWater / NoPowerOrWater zone, is map data. isMainsSupplyOn() is the world
    -- side and does change, in both directions.
    if square:isNoWater() then return false end
    if not MW.isMainsSupplyOn() then return false end

    -- A fixture on a rain barrel is only offered the mains when the barrel is not
    -- there. The engine makes the two exclusive -- every water read short-circuits
    -- to the external source once usesExternalWaterSource is set -- so offering this
    -- over a working collector just swaps one for the other, and vanilla's Plumb
    -- swaps it back: the see-saw of BR-LGMW-002.
    --
    -- The case that is left is a real one. Vanilla's own Plumb is offered on a
    -- carried-in fixture before the shutoff with NOTHING overhead (the `getRoom()
    -- != null && preWaterShutoff && vCanBeWaterPiped` branch of its gate), and taking
    -- it leaves a fixture attached to nothing: dry, and never offered vanilla's row
    -- again. This is the way back.
    --
    -- FindExternalWaterSource() is the uncached search and the same call vanilla's
    -- gate makes, so the two rows agree about what is overhead. It returns an EMPTY
    -- collector too, so an empty barrel still counts as attached, as it does for
    -- vanilla; only no collector at all in the 3x3 above is "nothing there".
    if obj:getUsesExternalWaterSource() and obj:FindExternalWaterSource() ~= nil then
        return false
    end
    return true
end

--- Connect the fixture to the building's water system, leaving it holding the
--- flags a fixture the map spawned holds.
---
--- Runs on the authority and nowhere else, and that is arranged by the engine
--- rather than by a guard here. The only caller is LGPlumbMainsAction:complete(),
--- and LuaTimedActionNew.complete() is wrapped in `if (!GameClient.client)` -- so
--- on a multiplayer client the action is sent instead, the server rebuilds a fresh
--- one out of the packet (NetTimedAction.parse, keyed on `new`'s parameter names)
--- and calls complete() there. In singleplayer the same complete() runs locally,
--- which IS the authority. There is no third path and so no server/ folder: this
--- mod holds no standing state, no registry and no sweep, and everything it needs
--- lives in the fixture's own modData, which the engine syncs.
---
--- (This used to say "see LGMainsWaterServer". There has never been such a file.)
---
--- Deliberately unconditional. Whether the town supply is still up, and whether
--- this building ever had one, are questions the game answers downstream and
--- answers identically for the fixtures the building came with:
---
---   supply up          isWaterInfinite() -> unlimited, clean, "Water: Unlimited"
---   supply shut off    isUnmovedPipedWaterSource() -> the sprite's own pipe
---                      reserve, 20 units for a sink, then dry
---   NoWater building   getReserveWaterAmount() short-circuits on isNoWater(),
---                      so dry, as the orphanage's own sinks are
---
--- and in every one of those the fixture is now indistinguishable from the sink
--- next to it. The one thing it does check is whether that supply is live, and
--- only to decide whether there is any standing water to inherit -- see the end
--- of the function.
---
--- Unconditional here even though canPlumbToMains no longer offers the option in
--- the last two rows, and neither does LGPlumbMainsAction:complete() re-test them.
--- That is on purpose. The menu gate is about not wasting a player's time; this is
--- the write, and the write is correct in every row above. Re-testing the shutoff
--- at completion would put the two sides of a multiplayer game in a race over
--- which side crossed the shutoff day first, and lose a legitimate action to it,
--- to defend against a fabricated packet whose entire prize is a dry sink.
function MW.plumb(obj)
    -- false rather than deleting the key: both readers test `instanceof Boolean`
    -- before reading it, so absent and false are the same to the game, and false
    -- is what vanilla's own plumb action writes and what syncs cleanly.
    obj:getModData().canBeWaterPiped = false

    -- Detach any rain barrel. A fixture on the building's supply is not on a
    -- barrel, and leaving this set would short-circuit every water read on it.
    if obj:getUsesExternalWaterSource() then
        obj:setUsesExternalWaterSource(false)
        obj:sendObjectChange(IsoObjectChange.USES_EXTERNAL_WATER_SOURCE, { value = false })
    end

    -- Connecting to a supply that is already down inherits no standing water, so
    -- empty the pipes. Otherwise the sprite's reserve is handed out fresh every
    -- time, and a sink can be drained, taken up, put back down and drained again.
    --
    -- Asked of the object rather than worked out from the calendar: with the
    -- flags above already set, getFluidCapacity() reports 10000 exactly when
    -- isWaterInfinite() is true, so this is the game's own answer to "does this
    -- fixture have a live supply" -- and it covers a NoWater building, a
    -- derelict square and the shutoff day by the same test.
    if obj:getFluidCapacity() < 9999 and obj:getFluidAmount() > 0 then
        obj:getModData().waterAmount = 0
    end

    obj:transmitModData()
end
