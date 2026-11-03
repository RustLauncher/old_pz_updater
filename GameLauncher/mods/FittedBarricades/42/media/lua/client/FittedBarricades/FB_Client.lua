-- Rendering side (singleplayer and MP clients): keep every fitted
-- barricade wearing its fitted sprite.
--
-- Java re-derives a barricade's sprite from its state whenever that
-- state changes, straight from its own code paths - a zombie breaking
-- a plank (IsoBarricade.Damage -> chooseSprite, no Lua event), a
-- square streaming in (load -> chooseSprite), an MP state sync
-- (loadChange -> updateSprite) - and each time the vanilla sprite is
-- back. So the swap is re-asserted from OnTick over a registry of the
-- barricade SIDES this side has seen: OnTick fires at the end of
-- IngameState.update, after every world update and before the frame
-- renders, so a Java revert never reaches the screen.
--
-- A side - one square, one facing - is a stack of one or more layers
-- (FB_Core.lua), and its sprites are one thing: the first layer wears
-- the art of every layer's planks, sheets or bars together, the others
-- a blank tile. So the registry keys on the side, and a refit walks
-- the side's layers afresh: a layer added, a layer destroyed and the
-- next becoming first, a plank on any layer - all show up in the
-- stack's signature and refit the whole side.
--
-- The registry is filled from every way a barricade can appear here:
--   * LoadGridsquare - barricades already on a square when it streams
--     in (saves, and the map's own pre-placed barricades, which
--     MOBarricade.lua turns into IsoBarricade objects on that same
--     event, registered before this handler);
--   * OnObjectAdded - a barricade an MP client receives from the server
--     (AddItemToMapPacket, the only place the engine fires it) - built
--     by anyone, or a map one the server created;
--   * the build recipe's OnCreate (FB_Build.lua, SP/host) - a barricade
--     the local player builds;
--   * a sweep of the cell's window list, spread so that every window
--     is visited once per SWEEP_TICKS, as a safety net for anything the
--     above missed (in singleplayer the barricades Java hangs itself as
--     a stash house generates arrive through no Lua event at all).
-- A layer leaving - a zombie finishing it, the player unbarricading,
-- the server's removal reaching a client - always passes through
-- IsoGridSquare.RemoveTileObject, which fires OnObjectAboutToBeRemoved
-- first (RemoveItemFromSquarePacket fires it too on the way in): the
-- side is marked and refitted on the next tick, once the object has
-- left the square's lists. Sides with no layer left are dropped as
-- they are found. A chunk unloading fires nothing per object: the
-- registry is pruned of squares the cell no longer holds once per
-- SWEEP_TICKS, and no side is ever refitted on such a square (its
-- objects are dead copies; the reloaded square's barricades come back
-- through LoadGridsquare and replace the entry).
--
-- In singleplayer a fit that finds the stack changed (or first sees
-- it) also puts a near side's layers straight after their opening in
-- the square's object list - the render order among the translucent
-- objects of a square, which vanilla's end-of-list placement gets
-- wrong under a canopy (FB_Core.lua order). An MP client leaves the
-- list as the server sent it: MP packets address objects by index.
--
-- Cost: the tick is a change DETECTOR, not a re-derivation. Every
-- state change Java makes to a layer goes through chooseSprite and
-- puts a vanilla sprite on it - that is exactly what the mod exists to
-- undo - so per tick and tracked side the check is one getSprite per
-- layer against the IsoSprite the last fit left there (the sprite
-- manager hands out one object per name; an unchanged reference is an
-- unchanged sprite). Only a mismatch, a marked removal, or an opening
-- not yet found (a far-side barricade whose window sits on a square
-- not streamed in, an MP client handed the barricade before the
-- window: one getBarricadedObject per tick until it is) costs a full
-- refit: the special-object walk, the signature and - only when the
-- signature changed - the class lookup (which walks the square's
-- objects for overlays) and the sprites. A side on an opening the
-- vanilla barricade already covers (no class) is not checked at all.
-- A dedicated server never renders and registers nothing.

require "FittedBarricades/FB_Core"

if isServer() then return end

local FB = FittedBarricades

local SWEEP_TICKS = 120  -- ~2 s at 60 fps

-- key -> { sq = IsoGridSquare, x, y, z = its coordinates,
--          dir = IsoDirections,
--          layers = the side's IsoBarricades in special-object order
--                   (FB.layers scratch, refilled on every refit),
--          have = the IsoSprite each layer wore after the last fit,
--          sig = stack signature,
--          opening = the barricaded object the sprites were fitted to,
--          class = its size class (nil: the vanilla barricade covers it),
--          sprites = the layers' sprite names (FB.stackSprites),
--          dirty = a layer is being removed: refit on the next tick }
local tracked = {}
local tickCount = 0
local sweepIndex = 0

local function key(x, y, z, dir)
	return x .. ":" .. y .. ":" .. z .. ":" .. tostring(dir)
end

-- Still loaded on this side: the square the entry was made on is the
-- one the cell holds at those coordinates.
local function loaded(entry)
	return getCell():getGridSquare(entry.x, entry.y, entry.z) == entry.sq
end

-- Debug trace (FB.debug = true, e.g. from a harness): one console line
-- per entry whenever what fit() computes changes, plus drops.
FB.debug = FB.debug or false
local function dbg(msg)
	if FB.debug then print("[FittedBarricades] " .. msg) end
end

-- Put `want` on the layer unless it wears it already, and hand back
-- the sprite it wears afterwards - what the tick compares against. A
-- nil `want` (no class, nothing in the stack) leaves the layer as it
-- is; its sprite is still remembered, so a change on it is noticed.
local function fitLayer(layer, want)
	local sprite = layer:getSprite()
	if want and not (sprite and sprite:getName() == want) then
		layer:setSpriteFromName(want)
		sprite = layer:getSprite()
	end
	return sprite
end

-- Fit every layer of the entry's side from a fresh walk of its square.
-- Returns false when there is no layer left to fit (the entry is dropped).
local function fit(entry)
	local layers = FB.layers(entry.sq, entry.dir, entry.layers)
	entry.layers = layers
	entry.dirty = nil
	if #layers == 0 then return false end
	local sig = FB.signature(layers)
	-- refit on a change of state; retry while there is no opening to
	-- fit to (nil until its square is loaded here)
	if entry.sig ~= sig or entry.opening == nil then
		local opening = layers[1]:getBarricadedObject()
		local class = FB.targetClass(opening)
		entry.sig, entry.opening, entry.class = sig, opening, class
		entry.sprites = FB.stackSprites(layers, class)
		-- singleplayer: the layers' place in the square's object list
		-- too (FB_Core order); an MP client draws the server's list
		if class ~= nil and not isClient() then
			FB.orderLayers(entry.sq, opening, layers)
		end
		if FB.debug then
			local msg = "fit " .. key(entry.x, entry.y, entry.z, entry.dir) .. " layers=" .. #layers .. " sig=" .. tostring(sig)
				.. " opening=" .. (opening and tostring(opening:getObjectName()) or "nil")
				.. " class=" .. tostring(class) .. " sprite=" .. tostring(entry.sprites and entry.sprites[1])
			if msg ~= entry.lastMsg then
				entry.lastMsg = msg
				dbg(msg)
			end
		end
	end
	local sprites, have = entry.sprites, entry.have
	for i = 1, #layers do
		have[i] = fitLayer(layers[i], sprites and sprites[i])
	end
	for i = #have, #layers + 1, -1 do have[i] = nil end
	return true
end

-- Refit a tracked side; drop it when its square is gone from the cell
-- or no layer is left.
local function refit(k, entry)
	if not loaded(entry) then
		dbg("drop " .. k .. ": square unloaded")
		tracked[k] = nil
	elseif not fit(entry) then
		dbg("drop " .. k .. ": no layers")
		tracked[k] = nil
	end
end

-- Track a barricade's side and fit it right away. No-op for anything
-- else.
FB.track = function(obj)
	if not instanceof(obj, "IsoBarricade") then return end
	local sq, dir = obj:getSquare(), obj:getDir()
	if not sq then return end
	local x, y, z = sq:getX(), sq:getY(), sq:getZ()
	local k = key(x, y, z, dir)
	local entry = tracked[k]
	if not entry or entry.sq ~= sq then
		entry = { sq = sq, x = x, y = y, z = z, dir = dir, layers = {}, have = {} }
		tracked[k] = entry
	end
	if not fit(entry) then tracked[k] = nil end
end

-- Track every barricade side on a square (they are special objects).
FB.trackSquare = function(sq)
	if not sq then return end
	local specials = sq:getSpecialObjects()
	if specials:isEmpty() then return end
	for i = 0, specials:size() - 1 do
		FB.track(specials:get(i))
	end
end

-- Track the barricades of one barricadeable object (either side).
FB.trackOpening = function(obj)
	if not obj then return end
	local near, far = obj:getBarricadeOnSameSquare(), obj:getBarricadeOnOppositeSquare()
	if near then FB.track(near) end
	if far then FB.track(far) end
end

-- What the registry holds for one side (debugging aid).
FB.trackedInfo = function(sq, dir)
	local entry = tracked[key(sq:getX(), sq:getY(), sq:getZ(), dir)]
	if not entry then return "untracked" end
	return "tracked sq=" .. (entry.sq == sq and "same" or "STALE") .. " sig=" .. tostring(entry.sig)
		.. " opening=" .. (entry.opening and tostring(entry.opening:getObjectName()) or "nil")
		.. " sprite=" .. tostring(entry.sprites and entry.sprites[1])
end

-- One side, one tick: a marked removal or a changed sprite on any
-- layer refits it; a side still waiting for its opening asks for it
-- again; a side on an opening the vanilla barricade covers is left.
local function checkSide(k, entry)
	if entry.dirty then
		refit(k, entry)
		return
	end
	local layers = entry.layers
	if entry.opening == nil then
		if layers[1]:getBarricadedObject() then refit(k, entry) end
		return
	end
	if entry.class == nil then return end
	local have = entry.have
	for i = 1, #layers do
		if layers[i]:getSprite() ~= have[i] then
			refit(k, entry)
			return
		end
	end
end

-- Drop every side whose square the cell no longer holds.
local function prune()
	for k, entry in pairs(tracked) do
		if not loaded(entry) then
			dbg("drop " .. k .. ": square unloaded")
			tracked[k] = nil
		end
	end
end

-- The safety-net sweep, spread out: a few windows per tick, so that
-- every window of the cell's list is visited once per SWEEP_TICKS,
-- instead of the whole list in one frame every SWEEP_TICKS (a town
-- holds thousands, three engine calls each). The list is live -
-- windows come and go with the chunks - so the cursor simply wraps;
-- a window shifted past it is seen on the next lap.
local function sweepSome()
	local windows = getCell():getWindowList()
	local size = windows:size()
	if size == 0 then
		sweepIndex = 0
		return
	end
	if sweepIndex >= size then sweepIndex = 0 end
	local last = math.min(size, sweepIndex + math.ceil(size / SWEEP_TICKS)) - 1
	for i = sweepIndex, last do
		FB.trackOpening(windows:get(i))
	end
	sweepIndex = last + 1
end

local function onTick()
	for k, entry in pairs(tracked) do
		checkSide(k, entry)
	end
	tickCount = tickCount + 1
	if tickCount >= SWEEP_TICKS then
		tickCount = 0
		prune()
	end
	sweepSome()
end

local function onObjectAdded(obj)
	FB.track(obj)
end

-- A layer on its way out: mark its side, refit on the next tick once
-- it has left the square's lists (the event fires before that, and a
-- handler must not remove anything itself - RemoveTileObject throws).
local function onObjectAboutToBeRemoved(obj)
	if not instanceof(obj, "IsoBarricade") then return end
	local sq = obj:getSquare()
	if not sq then return end
	local entry = tracked[key(sq:getX(), sq:getY(), sq:getZ(), obj:getDir())]
	if entry then entry.dirty = true end
end

Events.LoadGridsquare.Add(FB.trackSquare)
Events.OnObjectAdded.Add(onObjectAdded)
Events.OnObjectAboutToBeRemoved.Add(onObjectAboutToBeRemoved)
Events.OnTick.Add(onTick)
