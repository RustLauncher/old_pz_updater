-- Server-side (also runs in singleplayer): re-skin vanilla half-tile
-- sheets that hang on big windows when they stream in. Two ways such a
-- curtain exists:
--   * world gen: Java hangs vanilla sheets as a building first generates
--     - the randomized buildings (RBSafehouse, RBGunstoreSiege,
--     RBJackieJaye) call IsoWindow.addSheet on the building's windows,
--     and stash houses roll IsoWindow.addRandomBarricades - none of it
--     goes through the Lua timed action FT_AddSheet wraps;
--   * saves from before this mod (or with it disabled for a while).
--
-- The actual swap is FT_Core.reskin - the same slot-and-state-preserving
-- replacement the add-sheet wrapper uses - so the sweeps add nothing but
-- the pairing of curtains to their windows. Only curtains wearing the
-- vanilla WINDOW SHEET sprites are touched (FT.isVanillaSheet); the
-- moveable fabric-curtain furniture in the same tileset is left alone.
--
-- Two events drive it:
--   * LoadGridsquare, per square, for anything already hanging when the
--     square loads (saves). Both halves of an edge may live in different
--     chunks (a far-side curtain sits on the square NEXT to its window),
--     so the sweep looks in both directions from whichever square loads:
--     windows on this square are checked against curtains on this square
--     and the far neighbour, and curtains on this square are traced back
--     to their window's square. If the other square is not loaded yet,
--     its own LoadGridsquare re-runs the sweep from the other end.
--   * LoadChunk, per chunk, for the world-gen sheets. Java hangs those
--     from IsoChunk.randomizeBuildingsEtc, which runs on EVERY chunk load
--     (disk or brand new) AFTER every LoadGridsquare of the chunk (same
--     method, later in it), and only once the whole building is streamed
--     in - so the windows it dresses may sit in chunks swept earlier.
--     LoadChunk fires at the very end of that load (same method again,
--     after the randomization), so the sweep re-walks every building
--     this chunk touches, edge to edge, all its levels. Which buildings
--     is decided the way RandomizedBuildingBase.ChunkLoaded decides it:
--     the building must be FULLY streamed in (BuildingDef.isFullyStreamedIn)
--     and at least one of the chunks it overlaps must be brand new
--     (BuildingDef.isAnyChunkNewlyLoaded) - NOT the chunk that fired,
--     which is often an old one read back from disk that happens to
--     complete a building whose other chunks were generated just now.
--     Each building is walked once per session (the completing chunk is
--     the first to see it fully streamed in, and that is the one sweep
--     that can find anything); later chunks touching it are skipped.
--
-- The same sweep also puts a sheet fitted by an earlier version (hung at
-- the end of its square's object list, as vanilla hangs its own) in its
-- place straight after the window, so the furniture in front of the
-- window paints over it (FT_Core.lua, "order").
--
-- Cost: LoadGridsquare fires for every square that streams in, so the
-- sweep is gated on a single fact the engine already keeps. Windows and
-- curtains are both SPECIAL objects (IsoGridSquare.getCurtain and
-- getWindow iterate the specialObjects list, nothing else), so an empty
-- list settles a square in two Java calls; only the rare square that
-- passes goes on to the targeted getWindow / getCurtain lookups. The
-- object list is walked only for a square with a sheet on a big window:
-- once for the overlay clip of a re-skin, once to place the sheet.

require "FittedSheets/FT_Core"

-- MP clients never act: they only receive the server's remove + place
-- transmits. isClient() is fixed for the session by the time this file
-- loads (Lua reloads on joining a server), so gate the whole file the way
-- vanilla's server/ systems do and register nothing on a client.
if isClient() then return end

local FT = FittedSheets

local CHUNK_SIZE = 8  -- squares per chunk side (IsoChunk.getGridSquare bounds)

-- Re-skin a vanilla sheet in one of this square's FAR slots (curtainS /
-- curtainE): it hangs on the far side of a window that sits on the square
-- south / east of this one, on that square's north / west edge. The near
-- slots (curtainN / curtainW) belong to this square's own windows and are
-- covered by FT.reskinWindowSheets below.
local FAR_SLOTS = {
	{ type = IsoObjectType.curtainS, dx = 0, dy = 1, north = true },
	{ type = IsoObjectType.curtainE, dx = 1, dy = 0, north = false },
}

local function reskinFarSlot(square, slot)
	local curtain = square:getCurtain(slot.type)
	if not FT.isVanillaSheet(curtain) then return end
	local edgeSquare = getCell():getGridSquare(
		square:getX() + slot.dx, square:getY() + slot.dy, square:getZ())
	local window = edgeSquare and edgeSquare:getWindow(FT.edgeFacing(slot.north))
	if window then FT.reskin(curtain, window) end
end

-- Re-skin every vanilla sheet on this square's windows (either slot of
-- their edge) and every vanilla sheet on this square whose window sits on
-- the neighbouring square. Idempotent: every step is a fresh slot lookup
-- and a fitted sheet never matches isVanillaSheet again.
local function sweepSquare(square)
	-- the gate: no special objects, no window and no curtain, nothing to do
	if square:getSpecialObjects():isEmpty() then return end
	-- getWindow(facing) is Java's own lookup - the first IsoWindow of that
	-- facing in the special-objects list
	local window = square:getWindow(FT.edgeFacing(true))
	if window then FT.reskinWindowSheets(window) end
	window = square:getWindow(FT.edgeFacing(false))
	if window then FT.reskinWindowSheets(window) end
	reskinFarSlot(square, FAR_SLOTS[1])
	reskinFarSlot(square, FAR_SLOTS[2])
end

-- Every loaded square of a building, its far edges included: BuildingDef
-- x2/y2 are exclusive, and a window on a room's south or east wall sits
-- on the square just outside it (the north/west edge of that square).
local function sweepBuilding(def)
	local cell = getCell()
	for z = def:getMinLevel(), def:getMaxLevel() do
		for y = def:getY(), def:getY2() do
			for x = def:getX(), def:getX2() do
				local sq = cell:getGridSquare(x, y, z)
				if sq then sweepSquare(sq) end
			end
		end
	end
end

-- The chunk's world origin (its local 0,0), read off the first square it
-- has on any level: IsoChunk keeps it in public instance fields (wx/wy)
-- that Kahlua does not expose, so it is recovered from a square instead.
-- A chunk with no square at all has no building either: nil.
local function chunkOrigin(chunk)
	for z = chunk:getMinLevel(), chunk:getMaxLevel() do
		for ly = 0, CHUNK_SIZE - 1 do
			for lx = 0, CHUNK_SIZE - 1 do
				local sq = chunk:getGridSquare(lx, ly, z)
				if sq then return sq:getX() - lx, sq:getY() - ly end
			end
		end
	end
	return nil
end

-- The buildings whose rooms touch this chunk, asked of the meta grid with
-- the box IsoChunk.doLoadGridsquare feeds the randomizer (the chunk's 8x8
-- squares plus a one-square margin on every side; the meta grid lists
-- each building once).
local function buildingsTouching(chunk)
	local defs = ArrayList.new()
	local ox, oy = chunkOrigin(chunk)
	if not ox then return defs end
	getWorld():getMetaGrid():getBuildingsIntersecting(
		ox - 1, oy - 1, CHUNK_SIZE + 2, CHUNK_SIZE + 2, defs)
	return defs
end

-- Buildings this session has already walked, by BuildingDef id. The
-- randomizer dresses a building at most once, on the load that completes
-- it; every later chunk touching the building while its new chunk is
-- still loaded would otherwise re-walk the whole footprint for nothing.
local swept = {}

local function onLoadChunk(chunk)
	local defs = buildingsTouching(chunk)
	for i = 0, defs:size() - 1 do
		local def = defs:get(i)
		local id = def:getID()
		if not swept[id] and def:isFullyStreamedIn() and def:isAnyChunkNewlyLoaded() then
			swept[id] = true
			sweepBuilding(def)
		end
	end
end

Events.LoadGridsquare.Add(sweepSquare)
Events.LoadChunk.Add(onLoadChunk)
