if isClient() then return end

--[[ Trains -- raising the inside of a car (DESIGN.md 5.2).

    Runs in single player and on any server. A room is built the first time
    somebody is standing in it, because **nothing can be built into ground
    that has not streamed in, and ground streams in only round a player**
    (pz_trekship DESIGN.md, constraint 1). So the order is always: the
    player is moved in and held (TRN_Inside), this file sees the ground is
    loaded and builds round them, and they are let go.

    Everything here is the Shuttlecraft's builder, cut down (pz_trekship
    TREK_Build.lua, PLAYED there), and the Sewers mod's way with a picture
    on a wall (pz_sewars SEW_Build.lua, PLAYED there):

      * **the floor.** In single player IsoGridSquare.addFloor, which is
        what the Shuttlecraft's cabin has always stood on. On a server
        addFloor tells no client, so there the floor is an object with a
        floor's sprite, sent with transmitAddObjectToSquare. addFloor never
        replaces a floor that is there, so a room floored by an older
        revision is given its new sprite the way vanilla's shovel does it:
        setSprite, and the sprite sent to every client;
      * **the walls** are vanilla's, on the north or west edge of a square,
        derived from the room's shape, each added once: a wall of our own
        would have no collision the engine trusts and no depth;
      * **what a car looks like** is ours: a picture *attached* to each wall
        the camera sees (AttachExistingAnim, and the sprite sent). The
        camera's cutaway cuts a wall and what is attached to it and nothing
        else; a picture that is an object of its own stays full height over
        a cut wall;
      * **the roof** is vanilla's invisible floor a storey up, so the engine
        counts the room as indoors: no rain;
      * **the fittings** (a cabin car's seats) are placed **once, ever**.
        The room is a player's to build in: a seat that is not where it was
        put has been moved by somebody, and is not put back
        (pz_trekship BUILDING.md);
      * **the hull always comes back**: floor, walls, pictures and roof are
        checked on every build, and a hole is mended.

    **Where the map under the rooms is not loaded** (tools/gen_void_map.py:
    a world's maps are fixed when the world is made, so every save older
    than the mod's map), the cell is wilderness, and the dead walk in it.
    Three things are done about that, none of them as good as the map:
    what the engine grew is taken off a room's own ground as it is raised;
    off the ground round it, ground and all, a little at a time, which
    leaves black (B.blacken); and a zombie in the rooms' ground is taken
    out of the world (B.unhaunt). Played 2026-10-08, before the last two:
    "the outside is grass and trees ... there is a zombie there".
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"
require "TRN/TRN_Time"
require "TRN/TRN_Clock"
require "TRN/TRN_Rooms"
require "TRN/TRN_Setup"
require "TRN/TRN_Garden"
require "TRN/TRN_Herd"

TRN = TRN or {}
local C, U, T, K, R = TRN.Config, TRN.Util, TRN.Time, TRN.Clock, TRN.Rooms
local Garden, Herd = TRN.Garden, TRN.Herd

local B = {}
TRN.Build = B

B.stats = { black = 0, buses = 0, topped = 0, stocked = 0, rooms = 0, floors = 0, walls = 0, roofs = 0, fittings = 0, pictures = 0, wild = 0,
            cleared = 0, zombies = 0, beds = 0, crops = 0, troughs = 0, animals = 0, plumbed = 0, unlit = 0 }

---------------------------------------------------------------------------
-- Squares and objects
---------------------------------------------------------------------------
local function loaded(x, y, z)
    local cell = U.cell()
    if not cell then return false end
    return U.try("build.chunk", function()
        return cell:getChunkForGridSquare(math.floor(x), math.floor(y), math.floor(z))
    end) ~= nil
end

--- The square, made if it is not there. Nil when its ground is not loaded:
--- a square made there is an orphan, and the first call on it throws.
local function square(x, y, z)
    local sq = U.square(x, y, z)
    if sq then return sq end
    if not loaded(x, y, z) then return nil end
    return U.try("build.makeSquare", function()
        return U.cell():getOrCreateGridSquare(math.floor(x), math.floor(y), math.floor(z))
    end)
end

local function eachObject(sq, fn)
    local objs = U.try("build.objects", function() return sq:getObjects() end)
    local n = objs and (U.try("build.objectCount", function() return objs:size() end) or 0) or 0
    for i = n - 1, 0, -1 do
        local o = U.try("build.objectAt", function() return objs:get(i) end)
        if o then fn(o) end
    end
end

local function spriteOf(o)
    return U.try("build.sprite", function()
        local spr = o:getSprite()
        return spr and spr:getName()
    end)
end

local function find(sq, sprite)
    local found = nil
    eachObject(sq, function(o)
        if spriteOf(o) == sprite then found = o end
    end)
    return found
end

--- An object with this sprite on the square, made, tagged and sent unless
--- one is already there. Returns whether it is there, and whether it was
--- made now.
local fill

local function place(sq, sprite, tag, stock)
    if not sq then return false, false end
    if find(sq, sprite) then return true, false end
    local obj = U.try("build.new", function() return IsoObject.new(sq, sprite, "") end)
    if not obj then return false, false end
    U.try("build.tag", function() obj:getModData()[C.Rooms.tag] = tag end)
    -- A rack is somewhere to put things only once it is told to be: an
    -- object made in Lua has no container until its sprite's properties
    -- are read for one (pz_trekship TREK_AdirondackServer).
    if tag == "fitting" then fill(obj, stock) end
    local sent = U.try("build.add", function()
        sq:transmitAddObjectToSquare(obj, -1)
        return true
    end) == true
    return sent, sent
end

--- A fitting's cupboard, made and filled before the fitting is sent, so it
--- goes to every client with what is in it. Marked as looked in already, or
--- the engine rolls loot of its own into it the first time somebody opens
--- it, on top of ours (pz_trekship TREK_Build.prepareContainer).
fill = function(obj, stock)
    U.try("build.containers", function() obj:createContainersFromSpriteProperties() end)
    local box = U.try("build.box", function() return obj:getContainer() end)
    if not box then return 0 end
    U.try("build.explored", function() box:setExplored(true) end)
    local n = 0
    for _, e in ipairs(stock and C.Rooms.stock[stock] or {}) do
        if U.try("build.stock", function()
            box:AddItems(e[1], e[2])
            return true
        end) then n = n + e[2] end
    end
    B.stats.stocked = B.stats.stocked + n
    return n
end

--- A stove somebody can cook on: the engine's own class of object, not a
--- picture of one with a cupboard in it (pz_trekship TREK_Build.placeStove).
local function placeStove(sq, sprite, stock)
    if not sq then return false, false end
    if find(sq, sprite) then return true, false end
    local obj = U.try("build.stove", function() return IsoStove.new(getCell(), sq, getSprite(sprite)) end)
    if not obj then return place(sq, sprite, "fitting", stock) end
    U.try("build.tag", function() obj:getModData()[C.Rooms.tag] = "fitting" end)
    fill(obj, stock)
    local sent = U.try("build.add", function()
        sq:transmitAddObjectToSquare(obj, -1)
        return true
    end) == true
    return sent, sent
end

--- A television's own power, full (pz_trekship TREK_Power.energise, PLAYED
--- there): it is told it runs off a cell, and that the cell is not one
--- somebody can take out.
local function energise(obj)
    return U.try("build.energise", function()
        local data = obj:getDeviceData()
        if not data then return false end
        data:setIsBatteryPowered(true)
        data:setHasBattery(false)
        if (data:getPower() or 0) < C.Rooms.tvPower then data:setPower(C.Rooms.tvPower) end
        return true
    end) == true
end

--- A television somebody can switch on: the engine's own class of object,
--- given the workings of the item it is (pz_trekship TREK_Build.placeDevice).
local function placeTV(sq, sprite, device)
    if not sq then return false, false end
    if find(sq, sprite) then return true, false end
    local obj = U.try("build.tv", function() return IsoTelevision.new(getCell(), sq, getSprite(sprite)) end)
    if not obj then return place(sq, sprite, "fitting") end
    U.try("build.tag", function() obj:getModData()[C.Rooms.tag] = "fitting" end)
    local data = U.try("build.tvData", function() return obj:cloneDeviceDataFromItem(device) end)
    if not data then
        data = U.try("build.tvItem", function()
            local proto = instanceItem(device)
            return proto and proto:getDeviceData() or nil
        end)
    end
    if data then U.try("build.tvSet", function() obj:setDeviceData(data) end) end
    if not energise(obj) then U.warnOnce("build.tv", "a television has no workings: " .. tostring(device)) end
    local sent = U.try("build.add", function()
        sq:transmitAddObjectToSquare(obj, -1)
        return true
    end) == true
    return sent, sent
end

--- A trough animals feed and drink from: the engine's own class of object,
--- made as vanilla makes one of a sprite on its map (MOFeedingTrough.lua,
--- ReplaceExistingObject). A picture of one with a cupboard in it feeds
--- nothing, **and vanilla makes that picture into a trough of its own the
--- next time its ground is loaded**, emptying it as it does.
local function placeTrough(sq, sprite)
    if not sq then return false, false end
    if find(sq, sprite) then return true, false end
    local obj = U.try("build.trough", function() return IsoFeedingTrough.new(sq, sprite, nil) end)
    if not obj then return place(sq, sprite, "fitting") end
    U.try("build.troughSet", function()
        obj:getModData()[C.Rooms.tag] = "fitting"
        obj:setNorth(true)
        obj:initWithDef()
    end)
    local sent = U.try("build.troughAdd", function()
        sq:AddSpecialObject(obj)
        obj:transmitCompleteItemToClients()
        return true
    end) == true
    if sent then B.stats.troughs = B.stats.troughs + 1 end
    return sent, sent
end

--- Water in a trough that is for water, to its brim; feed in one that is
--- for feed, when it is empty. Returns whether anything was added.
local function serveTrough(obj, what)
    return U.try("build.troughKeep", function()
        if what == "water" then
            if obj:getFluidContainer() == nil then obj:createFluidContainer() end
            local max, have = obj:getMaxWater() or 0, obj:getWater() or 0
            if have >= max then return false end
            obj:addWater(FluidType.Water, max - have)
            return true
        end
        -- A trough of several squares keeps its feed in one of them.
        if obj:getMasterTrough() ~= obj then return false end
        local box = obj:getContainer()
        if not box or not box:isEmpty() then return false end
        for _, e in ipairs(C.Stable.feed) do
            local items = box:AddItems(e[1], e[2])
            -- A cupboard everybody already has: its new things are sent (vanilla's own call for it).
            if isServer() then sendAddItemsToContainer(box, items) end
        end
        obj:checkOverlayFull(false)
        return true
    end) == true
end

--- Fills what holds water, and gives it something to hold if it has
--- nothing. Never what holds something that is not water. Returns whether
--- any was added.
local function water(obj)
    if not obj then return false end
    return U.try("build.water", function()
        local cap = obj:getFluidCapacity() or 0
        if cap <= 0 then
            local f = ComponentType.FluidContainer:CreateComponent()
            f:setCapacity(C.Rooms.water)
            f:addFluid(FluidType.Water, C.Rooms.water)
            GameEntityFactory.AddComponent(obj, true, f)
            return true
        end
        local have = obj:getFluidAmount() or 0
        if have >= cap then return false end
        if have > 0 then
            local fluid = obj:getPrimaryFluid()
            if fluid and fluid:getFluidType() ~= FluidType.Water then return false end
        end
        obj:addFluid(FluidType.Water, cap - have)
        return true
    end) == true
end

--- True for a thing that is a water fixture by its tile's own properties:
--- a sink, a bath, a rain barrel, whoever put it there.
local function plumbed(obj)
    return U.try("build.plumbed", function()
        local spr = obj:getSprite()
        local props = spr and spr:getProperties()
        if not props then return false end
        for _, name in ipairs(C.Rooms.plumbed) do
            if props:has(name) then return true end
        end
        return false
    end) == true
end

--- The generator under a car that has power: there, fuelled, mended and
--- running. Returns it. With `on` false (the sandbox's Power) none is set,
--- and one that is there is stopped.
local function powerBus(room, at, on)
    local x, y = room.x0 + at.dx, room.y0 + at.dy
    local sq = square(x, y, room.z - 1)
    if not sq then return nil end
    local gen = nil
    eachObject(sq, function(o)
        if not gen and instanceof(o, "IsoGenerator") then gen = o end
    end)
    if on == false then
        if gen and U.try("build.busStop", function()
            if not gen:isActivated() then return false end
            gen:setActivated(false)
            return true
        end) == true then
            B.stats.unlit = B.stats.unlit + 1
            U.log("build: the power bus under %d,%d was stopped: the sandbox has the cars without power", x, y)
        end
        return gen
    end
    if not gen then
        local item = U.try("build.busItem", function() return instanceItem(C.Rooms.powerItem) end)
        if not item then
            U.warnOnce("build.bus", "no item " .. tostring(C.Rooms.powerItem) .. ": a galley has no power")
            return nil
        end
        U.try("build.busSetup", function()
            item:setCondition(100)
            item:getModData().fuel = 10.0
        end)
        gen = U.try("build.busGen", function() return IsoGenerator.new(item, getCell(), sq) end)
        if not gen then return nil end
        U.try("build.busTag", function()
            gen:getModData()[C.Rooms.tag] = "power"
            gen:transmitModData()
            gen:setConnected(true)
        end)
        B.stats.buses = B.stats.buses + 1
        U.log("build: a power bus was set under %d,%d", x, y)
    end
    U.try("build.busKeep", function()
        local max = gen:getMaxFuel() or 10
        if (gen:getFuel() or 0) < max then gen:setFuel(max) end
        if gen:getCondition() < 100 then gen:setCondition(100) end
        if not gen:isActivated() then gen:setActivated(true) end
    end)
    return gen
end

--- Running water and power for a room somebody is in. Returns how many
--- things were topped up.
---
--- **Every car, and everything in it** (the author, 2026-10-11: "all cars
--- should be automatically connected to water and power"): the fittings a
--- room came with, and whatever else stands in it that is a water fixture
--- by its tile's own properties, a sink somebody carried aboard as much as
--- the galley's. The generator under the room is every car's. Each by the
--- sandbox: Water, Power; and a feed trough's feed by Animals.
function B.service(room, kind)
    local style = C.Rooms.styles[C.Cars[kind] and C.Cars[kind].inside or ""]
    if not style or not B.loaded(room) then return 0 end
    local Su = TRN.Setup
    local wet, lit, kept = Su.on("Water"), Su.on("Power"), Su.animals() == "kept"
    local n = 0
    for _, f in ipairs(style.fittings) do
        local sq = U.square(room.x0 + f.dx, room.y0 + f.dy, room.z)
        if wet and f.water and water(sq and find(sq, f.sprite)) then n = n + 1 end
        if f.tv and lit then
            local tv = sq and find(sq, f.sprite)
            if tv then energise(tv) end
        end
        if f.trough and ((f.trough == "water" and wet) or (f.trough ~= "water" and kept)) then
            local trough = sq and find(sq, f.sprite)
            -- Only the engine's own: a trough of an older build is a picture until vanilla remakes it.
            if trough and instanceof(trough, "IsoFeedingTrough") and serveTrough(trough, f.trough) then n = n + 1 end
        end
    end
    if wet then
        local more = 0
        for x = room.x0, room.x1 do
            for y = room.y0, room.y1 do
                local sq = U.square(x, y, room.z)
                if sq then
                    eachObject(sq, function(o)
                        if plumbed(o) and water(o) then more = more + 1 end
                    end)
                end
            end
        end
        B.stats.plumbed = B.stats.plumbed + more
        n = n + more
    end
    powerBus(room, style.power or C.Rooms.powerAt, lit)
    -- A greenhouse that could not be sown as it was raised (B.garden) is sown now.
    if style.crops and K.state and not (K.state.gardens and K.state.gardens[room.index .. ":" .. room.car]) then
        B.garden(room, style, false)
    end
    B.stats.topped = B.stats.topped + n
    return n
end

--- What this machine has built for the cars' water, power, beds and animals, for TRN_Status().
function B.status()
    local s = B.stats
    U.log("status: build: %d room(s) raised or mended; %d thing(s) topped up, %d of them a rider's own (plumbed); "
          .. "%d power bus(es) set, %d stopped; %d bed(s), %d crop(s) sown; %d trough(s) made, %d animal(s); the "
          .. "sandbox's Water: %s, Power: %s", s.rooms, s.topped, s.plumbed, s.buses, s.unlit, s.beds, s.crops, s.troughs,
          s.animals, tostring(TRN.Setup.on("Water")), tostring(TRN.Setup.on("Power")))
end

--- What the engine grew, by its sprite's name (pz_trekship TREK_Util.isWild).
local function isWild(o)
    local name = spriteOf(o)
    if type(name) ~= "string" then return false end
    -- Trees, bushes and grass, natural ground, and (played 2026-10-08:
    -- "I still see rocks") boulders and the litter the engine scatters.
    return name:sub(1, 2) == "e_" or name:sub(1, 11) == "vegetation_"
        or name:sub(1, 15) == "blends_natural_" or name:sub(1, 2) == "f_"
        or name:sub(1, 12) == "blends_grass" or name:sub(1, 9) == "boulders_"
        or name:sub(1, 2) == "d_"
end

---------------------------------------------------------------------------
-- The pieces
---------------------------------------------------------------------------
local oldFloors = nil
local function isOldFloor(name)
    if not oldFloors then
        oldFloors = {}
        for _, n in ipairs(C.Rooms.oldFloors) do oldFloors[n] = true end
    end
    return oldFloors[name] == true or (type(name) == "string" and name:sub(1, 8) == "trains_0")
end

--- A floor of this sprite under a square: laid if there is none, and a
--- floor of the room's own from an older revision given its new sprite. A
--- floor somebody else laid is theirs, and is left.
local function floorAt(x, y, z, sprite)
    local sq = square(x, y, z)
    if not sq then return false end
    local floor = U.try("build.getFloor", function() return sq:getFloor() end)
    if floor then
        local name = spriteOf(floor)
        if name == sprite or not isOldFloor(name) then return false end
        return U.try("build.reFloor", function()
            floor:setSprite(getSprite(sprite))
            if isServer() then floor:transmitUpdatedSpriteToClients() end
            return true
        end) == true
    end
    if isServer() then
        local _, made = place(sq, sprite, "floor")
        return made
    end
    return U.try("build.addFloor", function()
        sq:addFloor(sprite)
        return true
    end) == true
end

--- The invisible floor a storey up, sent, and the column under it roofed.
local function roofAt(x, y, z)
    local sq = square(x, y, z)
    if not sq then return false end
    local _, made = place(sq, C.Rooms.roof, "roof")
    if made then U.try("build.roofCheck", function() getCell():checkHaveRoof(x, y) end) end
    return made
end

--- A picture of ours on the wall of this sprite on a square: attached to
--- it, as vanilla hangs a wall overlay, unless it already is.
local function hang(sq, wallSprite, picture)
    if not sq or not picture or picture == "" then return false end
    local wall = find(sq, wallSprite)
    if not wall then return false end
    return U.try("build.hang", function()
        local spr = getSprite(picture)
        if not spr then error("no sprite " .. tostring(picture)) end
        if wall:isAttachedAnimSprite(spr) then return false end
        wall:AttachExistingAnim(spr, 0, 0, false, 0, false, 0.0)
        if isServer() then wall:transmitUpdatedSpriteToClients() end
        return true
    end) == true
end

--- Takes what the engine grew off a square. With `everything`, whatever is
--- there: for ground nobody can reach and nothing was built on, where
--- anything at all is the engine's, a loose stone as much as a tree. (Never
--- on a room's own squares once it stands: TRN_Rooms.claimed.)
local function unwild(x, y, z, everything)
    local sq = U.square(x, y, z)
    if not sq then return 0 end
    local doomed = {}
    eachObject(sq, function(o)
        if everything or isWild(o) then doomed[#doomed + 1] = o end
    end)
    local n = 0
    for _, o in ipairs(doomed) do
        if U.try("build.unwild", function()
            sq:transmitRemoveItemFromSquare(o)
            return true
        end) then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- For the track (TRN_Track.lua): one square at a time
---------------------------------------------------------------------------
--- What the engine grew that stands on the ground, and never the ground:
--- under a rail the grass and the dirt stay.
local function isGrown(o)
    local name = spriteOf(o)
    if type(name) ~= "string" or not isWild(o) then return false end
    return name:sub(1, 7) ~= "blends_"
end

--- True when a square is there to be built on: nil is "cannot tell yet".
function B.there(x, y, z)
    return U.square(x, y, z) ~= nil
end

--- An object of this sprite on a square, tagged and sent, unless one is
--- there. Returns whether it was made now.
function B.lay(x, y, z, sprite, tag)
    local _, made = place(U.square(x, y, z), sprite, tag)
    return made
end

--- Takes the objects of one sprite off a square. Returns how many.
function B.takeSprite(x, y, z, sprite)
    local sq = U.square(x, y, z)
    if not sq then return 0 end
    local doomed = {}
    eachObject(sq, function(o)
        if spriteOf(o) == sprite then doomed[#doomed + 1] = o end
    end)
    local n = 0
    for _, o in ipairs(doomed) do
        if U.try("build.takeSprite", function()
            sq:transmitRemoveItemFromSquare(o)
            return true
        end) then n = n + 1 end
    end
    return n
end

--- Takes what has grown on a square off it, and leaves its ground.
function B.takeGrown(x, y, z)
    local sq = U.square(x, y, z)
    if not sq then return 0 end
    local doomed = {}
    eachObject(sq, function(o)
        if isGrown(o) then doomed[#doomed + 1] = o end
    end)
    local n = 0
    for _, o in ipairs(doomed) do
        if U.try("build.takeGrown", function()
            sq:transmitRemoveItemFromSquare(o)
            return true
        end) then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- A room
---------------------------------------------------------------------------
local function key(room)
    return room.index .. ":" .. room.car
end

--- Forgets one room, by its key: it is raised afresh the next time somebody
--- goes in, and sown and stocked afresh if it is a car that is.
function B.forget(roomKey)
    local s = K.state
    if not s then return end
    if s.rooms then s.rooms[roomKey] = nil end
    if s.gardens then s.gardens[roomKey] = nil end
    if s.stables then s.stables[roomKey] = nil end
end

--- What stands on a square of a room that is not the room's own hull: the
--- things of `was` among it that the builder put there (to be taken), and
--- whether there is anything else at all (somebody's, or a fitting).
local function standing(sq, was)
    local floor = U.try("build.getFloor", function() return sq:getFloor() end)
    local ours, strange = {}, false
    eachObject(sq, function(o)
        if o == floor then return end
        local tag = U.try("build.tagOf", function() return o:getModData()[C.Rooms.tag] end)
        if tag == "wall" or tag == "floor" or tag == "mat" or tag == "roof" then return end
        if tag == "fitting" and was[spriteOf(o) or ""] then
            ours[#ours + 1] = o
        else
            strange = true
        end
    end)
    return ours, strange, floor
end

--- A bed of a greenhouse raised before its beds were soil (0.16.0 to
--- 0.28.0): the planter that was an ornament is taken out, where it still
--- stands where the builder put it, and the floor under it is made soil.
--- False, and nothing touched, where anything else is on the square or its
--- floor is not the room's own: that bed is somebody's now.
local function clearBed(sq, style)
    local was = {}
    for _, name in ipairs(style.was or {}) do was[name] = true end
    local ours, strange, floor = standing(sq, was)
    if strange or not floor then return false end
    local under = spriteOf(floor)
    local own = under == style.soil or under == style.aisle[1]
    for _, row in ipairs(style.floor) do
        for _, name in ipairs(row) do
            if name == under then own = true end
        end
    end
    if not own then return false end
    for _, o in ipairs(ours) do
        U.try("build.unbed", function() sq:transmitRemoveItemFromSquare(o) end)
    end
    if under ~= style.soil then
        U.try("build.soil", function()
            floor:setSprite(getSprite(style.soil))
            if isServer() then floor:transmitUpdatedSpriteToClients() end
        end)
    end
    return true
end

--- The beds of a greenhouse car, once for each room: soil, and by the
--- sandbox's Garden a crop in each (TRN_Garden.sow). Returns how many were
--- sown. After that the beds are their riders' to pick and dig and sow.
function B.garden(room, style, first)
    if not style.crops or not K.state then return 0 end
    K.state.gardens = K.state.gardens or {}
    if K.state.gardens[key(room)] then return 0 end
    local way = TRN.Setup.garden()
    -- Not before vanilla's farming is there to sow in: asked again the next time the room is served.
    if way ~= "bare" and not Garden.ready() then
        U.warnOnce("build.garden", "the game's farming is not there yet: room %s is not sown", key(room))
        return 0
    end
    local beds, sown = 0, 0
    for _, crop in ipairs(style.crops) do
        local sq = U.square(room.x0 + crop.dx, room.y0 + crop.dy, room.z)
        if sq and (first or clearBed(sq, style)) then
            beds = beds + 1
            if way ~= "bare" and Garden.sow(sq, crop.seed, crop.stage) then sown = sown + 1 end
        end
    end
    K.state.gardens[key(room)] = way
    B.stats.beds = B.stats.beds + beds
    B.stats.crops = B.stats.crops + sown
    U.log("build: room %s is a greenhouse: %d bed(s) of soil, %d sown (the sandbox's Garden: %s)%s", key(room), beds, sown,
          way, first and "" or "; a room of an older build, its planters taken out where they still stood")
    return sown
end

--- The animals of a livestock car, once for each room, by the sandbox's
--- Animals: a livestock zone over the room and each of its animals
--- (TRN_Herd). In a room of an older build its new troughs are set down
--- first, where their squares are still bare. Returns how many animals.
function B.stable(room, style, first)
    if not style.animals or not K.state then return 0 end
    K.state.stables = K.state.stables or {}
    if K.state.stables[key(room)] then return 0 end
    if not first then
        for _, f in ipairs(style.fittings) do
            local sq = f.trough and square(room.x0 + f.dx, room.y0 + f.dy, room.z)
            if sq and not find(sq, f.sprite) then
                local _, strange = standing(sq, {})
                if not strange then placeTrough(sq, f.sprite) end
            end
        end
    end
    local way = TRN.Setup.animals()
    local n = 0
    if way ~= "none" then
        Herd.zone(room, C.Stable.zone .. key(room))
        n = Herd.stock(room, style.animals)
    end
    K.state.stables[key(room)] = way
    B.stats.animals = B.stats.animals + n
    U.log("build: room %s is a stable: %d animal(s) put in it (the sandbox's Animals: %s)", key(room), n, way)
    return n
end

--- True when every corner of a room, and its middle, is on loaded ground.
function B.loaded(room)
    return loaded(room.x0 - 1, room.y0 - 1, room.z) and loaded(room.x1 + 1, room.y0 - 1, room.z)
       and loaded(room.x0 - 1, room.y1 + 1, room.z) and loaded(room.x1 + 1, room.y1 + 1, room.z)
       and loaded((room.x0 + room.x1) / 2, room.y0 + 1, room.z)
end

--- True when a room stands and was built by this revision.
function B.current(room)
    local built = K.state and K.state.rooms
    return built ~= nil and built[key(room)] == C.Rooms.rev
end

--- Raises a room, or mends one. Returns false, and builds nothing, while
--- its ground is not loaded. `kind` is the car's kind: what it looks like
--- inside, and what is in it to begin with.
function B.ensure(room, kind)
    if not K.state then return false end
    K.state.rooms = K.state.rooms or {}
    if not B.sweepOld() then return false end
    if B.current(room) and B.sound(room) then return true end
    if not B.loaded(room) then return false end
    local G = C.Rooms
    local style = G.styles[C.Cars[kind] and C.Cars[kind].inside or "box"] or G.styles.box
    local aisle = room.y0 + math.floor(G.wid / 2)
    -- A room's walls are vanilla's own: its hull one family of them, and
    -- the walls inside it another if its style says so. On some of them a
    -- picture of ours is hung: a window, a door, a speaker.
    local base = style.base or { W = G.wallW, N = G.wallN, doorW = G.frameW, doorN = G.frameN }
    local inner = style.inner or base
    local was = K.state.rooms[key(room)]
    local first = was == nil
    -- A room raised before the builder knew a rock from a floor has what
    -- the engine grew taken off it once more. Only that: what a rider has
    -- put in it since is theirs.
    local tidy = first or was < G.tidyRev
    local floors, walls, roofs, wild, fittings, pictures = 0, 0, 0, 0, 0, 0

    -- The room and the ring its walls stand on: stripped of anything the
    -- engine grew, floored, and roofed. The aisle is the middle row.
    for x = room.x0 - 1, room.x1 + 1 do
        for y = room.y0 - 1, room.y1 + 1 do
            -- Only as the room is first raised (and once for an old one):
            -- after that a plant on its floor is one a rider put there.
            if tidy then wild = wild + unwild(x, y, room.z, first) end
            local inside = R.within(room, x, y)
            -- Outside the walls, on the ring they stand on, the floor is
            -- the invisible one: a wall wants a floor under it, and a
            -- strip of planks in the dark outside the car is not the car.
            local sprite = G.roof
            if inside then
                -- A floor is a pattern of a few tiles, repeated, so a
                -- stain is not under every seat; the aisle is a row of its own.
                local row = style.floor[U.mod(y - room.y0, #style.floor) + 1]
                if y == aisle then row = style.aisle end
                sprite = row[U.mod(x - room.x0, #row) + 1]
            end
            if floorAt(x, y, room.z, sprite) then floors = floors + 1 end
            if roofAt(x, y, room.z + G.roofUp) then roofs = roofs + 1 end
            -- The roof of an older build, one storey up: taken down.
            if G.roofUp ~= 1 then unwild(x, y, room.z + 1, true) end
        end
    end
    -- Walls: on the west edge of the first column and of the one past the
    -- last, and on the north edge of the first row and of the one past the
    -- last. A wall is on the north or west edge of its own square.
    for y = room.y0, room.y1 do
        for _, x in ipairs({ room.x0, room.x1 + 1 }) do
            local _, made = place(square(x, y, room.z), base.W, "wall")
            if made then walls = walls + 1 end
        end
    end
    for x = room.x0, room.x1 do
        for _, y in ipairs({ room.y0, room.y1 + 1 }) do
            local _, made = place(square(x, y, room.z), base.N, "wall")
            if made then walls = walls + 1 end
        end
    end
    -- The walls inside it, if it is a car of more than one room: each on the
    -- north or west edge of its own square, vanilla's wall or vanilla's
    -- wall with a doorway, and our picture on it. No door hangs in a
    -- doorway yet.
    for _, wl in ipairs(style.walls or {}) do
        local sq = square(room.x0 + wl.dx, room.y0 + wl.dy, room.z)
        local sprite = wl.side == "N" and (wl.door and inner.doorN or inner.N) or (wl.door and inner.doorW or inner.W)
        local _, made = place(sq, sprite, "wall")
        if made then walls = walls + 1 end
        if hang(sq, sprite, wl.sprite) then pictures = pictures + 1 end
    end
    -- What the car looks like: a picture on each square of the two walls
    -- the camera sees, and a plate on the floor before each door it cannot.
    for x = room.x0, room.x1 do
        if hang(U.square(x, room.y0, room.z), base.N, style.wallN[x - room.x0 + 1]) then pictures = pictures + 1 end
    end
    for y = room.y0, room.y1 do
        if hang(U.square(room.x0, y, room.z), base.W, style.wallW[y - room.y0 + 1]) then pictures = pictures + 1 end
    end
    for door, sprite in pairs({ rear = G.matRear, side = G.matSide }) do
        local x, y = R.spot(room, door)
        local _, made = place(U.square(x, y, room.z), sprite, "mat")
        if made then pictures = pictures + 1 end
    end
    -- Fittings: once, ever. After that the room is its riders' own.
    if first then
        for _, f in ipairs(style.fittings) do
            local sq = square(room.x0 + f.dx, room.y0 + f.dy, room.z)
            local _, made
            if f.tv then
                _, made = placeTV(sq, f.sprite, f.tv)
            elseif f.trough then
                _, made = placeTrough(sq, f.sprite)
            elseif f.stove then
                _, made = placeStove(sq, f.sprite, f.stock)
            else
                _, made = place(sq, f.sprite, "fitting", f.stock)
            end
            if made then fittings = fittings + 1 end
        end
    end

    -- What grows and what lives in it: once for each room, a room of an
    -- older build as much as a new one (K.state.gardens, K.state.stables).
    B.garden(room, style, first)
    B.stable(room, style, first)

    K.state.rooms[key(room)] = G.rev
    B.stats.rooms = B.stats.rooms + 1
    B.stats.floors = B.stats.floors + floors
    B.stats.walls = B.stats.walls + walls
    B.stats.roofs = B.stats.roofs + roofs
    B.stats.fittings = B.stats.fittings + fittings
    B.stats.pictures = B.stats.pictures + pictures
    B.stats.wild = B.stats.wild + wild
    U.log("build: room %s (%s) at %d,%d: %d floor(s), %d wall(s), %d picture(s), %d roof(s), %d fitting(s)%s",
          key(room), tostring(kind), room.x0, room.y0, floors, walls, pictures, roofs, fittings,
          first and "" or "; mended, not furnished again")
    if wild > 0 then
        U.log("build: %d thing(s) the engine grew were taken off room %s", wild, key(room))
    end
    return true
end

--- The rooms of an older build are forgotten, once: every car's room is
--- then raised for the first time, which strips everything on its ground
--- before it is built, and the black laid round it (B.blacken) takes what
--- is left of the old ones nearby. **Dev builds only lose things this way**:
--- a released version that moves its rooms owes its riders a migration
--- (pz_trekship DEV_GUIDE.md, "moving geometry is a migration").
---
--- This once swept the whole row the first rooms stood in, and waited for
--- all of it to be loaded. A row is longer than the engine keeps loaded
--- round one rider: in a world that had never had a room, whoever went
--- into the third car first waited for ever (found by the sleeper's test,
--- 2026-10-08, not in play).
function B.sweepOld()
    local s = K.state
    if not s then return false end
    local G = C.Rooms
    -- And when a host changes what a train is made of (sandbox Length,
    -- Consist): car 5 is another car, and its room is no longer its room.
    -- A world from before there was such a setting has what it always had.
    -- And when a host moves the rooms (sandbox RoomsX, RoomsY): a room is
    -- where it was raised, and that is not where its car's room is now.
    local cars, cell = TRN.Setup.cars(), R.where()
    local home = G.cell.x .. "," .. G.cell.y
    if s.geom == G.geom and (s.cars or C.Roll.carsAsBuilt) == cars and (s.cell or home) == cell then
        s.cars, s.cell = cars, cell
        return true
    end
    local had = false
    for _ in pairs(s.rooms or {}) do had = true end
    local why = (s.geom ~= G.geom) and "the rooms of an older build"
        or ((s.cell or home) ~= cell) and "the cars' insides were moved: the rooms that stood where they were"
        or "the trains are made of other cars now: their rooms"
    s.rooms, s.geom, s.cars, s.cell = {}, G.geom, cars, cell
    -- And what was sown and stocked in them: a room raised afresh is sown and stocked afresh.
    s.gardens, s.stables = {}, {}
    if had then
        U.log("build: %s are forgotten; every car's room is raised afresh, and emptied first", why)
    end
    return true
end

--- True when a room that should be standing has a floor under each of its
--- doors. A cheap look, made each time somebody is in it: the hull always
--- comes back, so a hole is found and the room is built again.
function B.sound(room)
    if not B.loaded(room) then return true end        -- cannot tell: not a reason to rebuild
    for _, door in ipairs({ "front", "rear", "side" }) do
        local x, y = R.spot(room, door)
        local sq = U.square(x, y, room.z)
        if not sq then return false end
        if U.try("build.sound", function() return sq:getFloor() ~= nil end) ~= true then return false end
    end
    return true
end

---------------------------------------------------------------------------
-- Where the map under the rooms is not loaded
---------------------------------------------------------------------------
B.mapKnown, B.mapThere = false, false

--- True when the map under the rooms is one of this world's. A world's maps
--- are fixed when it is made: a save older than the mod's map does not have
--- it, and never will. Said once, either way.
function B.mapLoaded()
    -- Rooms a host has moved (sandbox RoomsX, RoomsY) have no map under
    -- them wherever the mod's own is: their ground is cleared as it is for
    -- a world with no map at all.
    if not R.atHome() then
        if not B.movedNoted then
            B.movedNoted = true
            U.log("NOTICE: the sandbox has the cars' insides in cells %s, not the mod's own %d,%d: no map is under "
                  .. "them there. The ground is cleared round each room as somebody goes in", R.where(),
                  C.Rooms.cell.x, C.Rooms.cell.y)
        end
        return false
    end
    if B.mapKnown then return B.mapThere end
    local found = U.try("build.lots", function()
        local dirs = getLotDirectories()
        if not dirs then return nil end
        return dirs:contains(C.Rooms.map) and "yes" or "no"
    end)
    if not found then return false end                 -- cannot tell yet: asked again
    B.mapKnown, B.mapThere = true, found == "yes"
    if B.mapThere then
        U.log("build: the '%s' map is loaded: the cars' insides stand in black", C.Rooms.map)
    else
        U.log("NOTICE: the '%s' map is not one of this world's, so the ground the cars' insides stand on "
              .. "is wilderness. It is cleared round each room as somebody goes in. A world made with the "
              .. "mod enabled has the map; a dedicated server needs Map=%s;Muldraugh, KY",
              C.Rooms.map, C.Rooms.map)
    end
    return B.mapThere
end

B.cursors = {}          -- room key -> how far round the room the clearing has got
B.passes = {}           -- room key -> how many times it has been all the way round

--- True when the ground round a room has been gone over once, or need not
--- be: nobody is let into a room until it is, so that they do not watch a
--- wood being taken away (played 2026-10-08: "still grass is there then it
--- disappears").
function B.cleared(room)
    return B.mapLoaded() or ((B.passes[key(room)] or 0) >= 1 and (B.grownPasses[key(room)] or 0) >= 1)
end

B.grownCursors = {}     -- room key -> how far the wider sweep for what grows has got
B.grownPasses = {}      -- room key -> how many times it has been all the way round

--- Takes everything that grows off the ground round a room, out to
--- C.Rooms.grown squares, a part at a time and round again for as long as
--- it is called: ground streams in round a rider after the first pass. A
--- square in any car's room is left alone: a plant there is a rider's.
---
--- PLAYED 2026-10-08: inside a car, half the room was not drawn. The log had
--- one exception a frame, IsoTree.isPlayerInsideARoom: a room of ours is
--- walled and roofed, so the engine's regions make it a player's room and
--- IsoGridSquare.isInARoom is true in it; IsoTree.render then asks the
--- square for its map room, which a room raised at runtime has not got.
function B.ungrow(room)
    if B.mapLoaded() then return 0 end
    local G = C.Rooms
    local x0, y0 = room.x0 - G.grown, room.y0 - G.grown
    local w, h = (room.x1 - room.x0 + 1) + 2 * G.grown, (room.y1 - room.y0 + 1) + 2 * G.grown
    local cursor = B.grownCursors[key(room)] or 0
    local taken = 0
    for _ = 1, G.grownPerPass do
        local x, y = x0 + U.mod(cursor, w), y0 + math.floor(cursor / w)
        -- (A slot no room has been raised in yet is wilderness like the
        -- rest: left alone, its trees were two cars away and in view.)
        local index, car = R.slot(x, y)
        if not index or not (K.state.rooms and K.state.rooms[index .. ":" .. car]) then
            taken = taken + unwild(x, y, room.z, false)
        end
        cursor = cursor + 1
        if cursor >= w * h then
            cursor = 0
            B.grownPasses[key(room)] = (B.grownPasses[key(room)] or 0) + 1
        end
    end
    B.grownCursors[key(room)] = cursor
    if taken > 0 then B.stats.cleared = B.stats.cleared + taken end
    return taken
end

--- Takes what the engine grew off the ground round a room, ground and all,
--- C.Rooms.clearPerPass squares at a time, round and round: ground that had
--- not streamed in on one pass has by the next. Does nothing where the map
--- is loaded. Returns how many things it took.
function B.blackened(room)
    return (B.passes[key(room)] or 0) >= 1
end

function B.blacken(room)
    local G = C.Rooms
    local x0, y0 = room.x0 - 1 - G.clear, room.y0 - 1 - G.clear
    local w, h = (room.x1 - room.x0 + 3) + 2 * G.clear, (room.y1 - room.y0 + 3) + 2 * G.clear
    local cursor = B.cursors[key(room)] or 0
    local taken = 0
    for _ = 1, G.clearPerPass do
        local x, y = x0 + U.mod(cursor, w), y0 + math.floor(cursor / w)
        -- Not a room that stands, or the ring its walls stand on: this
        -- one's, or the next car's, which is nearer than the clearing
        -- reaches, and what is in it is somebody's. Where a room has yet to
        -- be raised there is only what the engine made, and it goes.
        local index, car = R.slot(x, y)
        if not index or not (K.state.rooms and K.state.rooms[index .. ":" .. car]) then
            taken = taken + unwild(x, y, room.z, true)
            -- And a floor of our own in its place, black: what is outside
            -- a car is meant, not left over, map or no map.
            if floorAt(x, y, room.z, G.black) then B.stats.black = B.stats.black + 1 end
        end
        cursor = cursor + 1
        if cursor >= w * h then
            -- Once round is enough for one call: going on would take up
            -- and lay again the first of what was just laid.
            cursor = 0
            B.passes[key(room)] = (B.passes[key(room)] or 0) + 1
            break
        end
    end
    B.cursors[key(room)] = cursor
    if taken > 0 then
        B.stats.cleared = B.stats.cleared + taken
        if not B.clearNoted then
            B.clearNoted = true
            U.log("build: clearing the wilderness round room %s to black, a little at a time", key(room))
        end
    end
    return taken
end

--- Takes every zombie in the rooms' ground out of the world. There should
--- never be one: with the map loaded none is ever made there.
function B.unhaunt()
    local cell = U.cell()
    local list = cell and U.try("build.zombies", function() return cell:getZombieList() end)
    local n = list and (U.try("build.zombieCount", function() return list:size() end) or 0) or 0
    local gone = 0
    local each = U.batch("build.unhaunt")
    for i = n - 1, 0, -1 do
        local zed = U.try("build.zombieAt", function() return list:get(i) end)
        if zed and each(function()
            if not R.ground(zed:getX(), zed:getY()) then return false end
            zed:removeFromWorld()
            zed:removeFromSquare()
            return true
        end) then gone = gone + 1 end
    end
    if gone > 0 then
        B.stats.zombies = B.stats.zombies + gone
        U.log("build: %d of the dead taken out of the rooms' ground", gone)
        -- Nothing is ever made on ground that is mapped empty. So this ground
        -- is not, whatever the world's list of maps says (PLAYED 2026-10-09,
        -- a new world, the map in its list, and room 10:6 raised among 207
        -- things the engine grew and dozens of the dead): it is wilderness,
        -- and is treated as wilderness from here on.
        if B.mapKnown and B.mapThere then
            B.mapThere = false
            U.log("NOTICE: the '%s' map is in this world's list and the dead are on its ground all the same: the "
                  .. "ground round each room is cleared as somebody goes in", C.Rooms.map)
        end
    end
    return gone
end

return B
