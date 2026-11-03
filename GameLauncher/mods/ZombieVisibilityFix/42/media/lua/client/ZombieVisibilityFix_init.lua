-- having this whole thing in one file is messy but i need to abuse upvalues for performance
-- this is normally completely idiotic, but this stuff will have to run for hundreds and hundreds of zombies per frame, so even small micro-optimisations will add up

-- local declaration limit is 200 within a scope and upvalue limit is 60 within a closure's scope
-- there are currently 155 locals declared within the top-level scope of this script

local options = PZAPI.ModOptions:getOptions("ZombieVisibilityFix")

local option_enabled, option_toggle
local option = {} -- this will get gc'd immediately, this is just so i don't have to type as much

if options then
	-- hot-loading breaks options if i don't do this
	option_enabled = options:getOption("enabled")
	option.aiming = options:getOption("aimingonly")
	option.zomvision = options:getOption("zomvision")
	option.stairs = options:getOption("stairs_beta")
	option.tracefn = options:getOption("raytracefn")
	option.alpha = options:getOption("alpha")
	option.alpha_stairs = options:getOption("alpha_stairs")
	option.maxzoms = options:getOption("maxzoms")
	option.maxdist = options:getOption("maxdist")
	option_toggle = options:getOption("togglekey")
else
	options = PZAPI.ModOptions:create("ZombieVisibilityFix", getText"UI_ZomVisFix_ModName")

	options:addTitle(getText"UI_ZomVisFix_Options_Title")

	option_enabled = options:addTickBox("enabled", getText"UI_ZomVisFix_Options_Enable_Name", true)
	options:addDescription("UI_ZomVisFix_Options_Enable_Desc")

	option.aiming = options:addTickBox("aimingonly", getText"UI_ZomVisFix_Options_AimingOnly_Name", false)
	options:addDescription("UI_ZomVisFix_Options_AimingOnly_Desc")

	option.zomvision = options:addTickBox("zomvision", getText"UI_ZomVisFix_Options_ZombieVision_Name", true)
	options:addDescription("UI_ZomVisFix_Options_ZombieVision_Desc")

	option.stairs = options:addTickBox("stairs_beta", getText"UI_ZomVisFix_Options_StairOVision_Name", true)
	options:addDescription("UI_ZomVisFix_Options_StairOVision_Desc")

	option.tracefn = options:addComboBox("raytracefn", getText"UI_ZomVisFix_Options_RaytracerFunc_Name")
	option.tracefn:addItem("UI_ZomVisFix_Options_RaytracerFunc_Item_SubTile")
	option.tracefn:addItem("UI_ZomVisFix_Options_RaytracerFunc_Item_TileBased")
	option.tracefn:addItem("UI_ZomVisFix_Options_RaytracerFunc_Item_Both", true)
	options:addDescription("UI_ZomVisFix_Options_RaytracerFunc_Desc")

	option.alpha = options:addSlider("alpha", getText"UI_ZomVisFix_Options_ZombieOpacity_Name", 0, 1, 0.01, 0.6)
	options:addDescription("UI_ZomVisFix_Options_ZombieOpacity_Desc")

	option.alpha_stairs = options:addSlider("alpha_stairs", getText"UI_ZomVisFix_Options_ZombieOpacityStairs_Name", 0, 1, 0.01, 0.6)
	options:addDescription("UI_ZomVisFix_Options_ZombieOpacityStairs_Desc")

	option.maxzoms = options:addSlider("maxzoms", getText"UI_ZomVisFix_Options_ZombieProcessingLimit_Name", 0, 4000, 20, 2000)
	options:addDescription("UI_ZomVisFix_Options_ZombieProcessingLimit_Desc")

	option.maxdist = options:addSlider("maxdist", getText"UI_ZomVisFix_Options_ZombieDistanceLimit_Name", 0, 100, 1, 0)
	options:addDescription("UI_ZomVisFix_Options_ZombieDistanceLimit_Desc")

	option_toggle = options:addKeyBind("togglekey", getText"UI_ZomVisFix_Options_ToggleKey_Name", Keyboard.KEY_NONE)
	options:addDescription("UI_ZomVisFix_Options_ToggleKey_Desc")
end

-- i think these wont trigger if a diff mod tries to change this mod's settings, but who cares lol

local MOD_DISABLED = not option_enabled:getValue()

function option_enabled:onChangeApply(value)
	MOD_DISABLED = not value
end

local AIMING_ONLY = option.aiming:getValue()

function option.aiming:onChangeApply(value)
	AIMING_ONLY = value
end

local ZOMBIE_DETECTION = option.zomvision:getValue()

function option.zomvision:onChangeApply(value)
	ZOMBIE_DETECTION = value
end

local STAIR_O_VISION = option.stairs:getValue()

function option.stairs:onChangeApply(value)
	STAIR_O_VISION = value
end

local RAYTRACE_FN = option.tracefn:getValue()

function option.tracefn:onChangeApply(value)
	RAYTRACE_FN = value
end

local TARGET_ALPHA = option.alpha:getValue()

function option.alpha:onChangeApply(value)
	TARGET_ALPHA = value
end

local TARGET_ALPHA_STAIRS = option.alpha_stairs:getValue()

function option.alpha_stairs:onChangeApply(value)
	TARGET_ALPHA_STAIRS = value
end

local MAX_ZOMBIES_PER_TICK = option.maxzoms:getValue()
MAX_ZOMBIES_PER_TICK = MAX_ZOMBIES_PER_TICK ~= 0 and MAX_ZOMBIES_PER_TICK or nil

function option.maxzoms:onChangeApply(value)
	MAX_ZOMBIES_PER_TICK = value ~= 0 and value or nil
end

local MAX_ZOMBIE_DISTANCE = option.maxdist:getValue()
MAX_ZOMBIE_DISTANCE = MAX_ZOMBIE_DISTANCE ~= 0 and MAX_ZOMBIE_DISTANCE or nil

function option.maxdist:onChangeApply(value)
	MAX_ZOMBIE_DISTANCE = value ~= 0 and value or nil
end

_G.ZombieVisibilityFix = _G.ZombieVisibilityFix or {events={}}

-- this lets me hot-reload the script in-game for easier development
local function hook_event(ev, fn)
	local glob = _G.ZombieVisibilityFix

	if glob.events[ev] then
		Events[ev].Remove(glob.events[ev])
	end

	glob.events[ev] = fn

	return Events[ev].Add(fn)
end

hook_event("OnKeyPressed", function(key)
	if key ~= option_toggle:getValue() then
		return
	end

	MOD_DISABLED = option_enabled:getValue()

	option_enabled:setValue(not MOD_DISABLED)

	local text = MOD_DISABLED and "[ZomVisFix] OFF" or "[ZomVisFix] ON"

	print(text)

	local ply = getPlayer()

	if ply then
		local pfx = MOD_DISABLED and "[col=255,0,0]" or "[col=0,255,0]"

		-- skips the HaloTextHelper queue so it's more responsive
		ply:setHaloNote(pfx .. text .. "[/]")
	end
end)

-- saves a java call compared to obj:doMethod() which does metatable lookups in java
-- this has some actual perf gain but completely murders readability
local function get_method(cls, name)
	return __classmetatables[cls.class].__index[name]
end

local current_tick, current_time, current_delta = 0, 0, 0.01

-- for splitscreen this supports only the first player (the kbm player)
-- but i need the upvalues for perf and nobody plays splitscreen anyway lol
local localPlayer
local ply_x, ply_y, ply_z, ply_zLast, ply_zUp, ply_fakeZ
local ply_viewDist, ply_detectDist
local ply_lookX, ply_lookY, ply_cone
local ply_aiming
local ply_square, ply_stair, ply_stairSquare
local ply_stairMinX, ply_stairMinY, ply_stairMaxX, ply_stairMaxY

local _getPlayerIndex = get_method(IsoPlayer, "getIndex")

hook_event("OnPlayerUpdate", function(ply)
	if ply ~= localPlayer then
		if _getPlayerIndex(ply) ~= 0 then
			return
		end

		localPlayer = ply
	end

	-- nulling y and lookY is kinda unnecessary
	ply_zLast, ply_x, ply_y, ply_z, ply_zUp, ply_fakeZ, ply_viewDist, ply_detectDist, ply_lookX, ply_lookY, ply_cone, ply_aiming, ply_square = ply_z
end)

local singleton_IsoCell

local STAIRS_MAX = IsoObjectType.MAX
local STAIRS_TN, STAIRS_MN, STAIRS_BN = IsoObjectType.stairsTN, IsoObjectType.stairsMN, IsoObjectType.stairsBN
local STAIRS_TW, STAIRS_MW, STAIRS_BW = IsoObjectType.stairsTW, IsoObjectType.stairsMW, IsoObjectType.stairsBW

local _getGridSquare = get_method(zombie.iso.IsoCell, "getGridSquare")
local _getStairs = get_method(zombie.iso.IsoGridSquare, "getStairs")

local function calculateStairBounds(stair, x, y, z)
	-- note: this should never be called when stair is MAX

	local cell = singleton_IsoCell
	if not cell then
		cell = getCell()
		singleton_IsoCell = cell
	end

	local _getGridSquare, _getStairs = _getGridSquare, _getStairs

	if stair == STAIRS_TN or stair == STAIRS_MN or stair == STAIRS_BN then
		local left = x - 1
		for i = left, x - 32, -1 do
			left = i
			local adj = _getGridSquare(cell, i, y, z)
			if not adj or _getStairs(adj) ~= stair then
				break
			end
		end

		local right = x + 1
		for i = right, x + 32 do
			right = i
			local adj = _getGridSquare(cell, i, y, z)
			if not adj or _getStairs(adj) ~= stair then
				break
			end
		end

		if stair == STAIRS_TN then
			return left, y - 2, right + 1, y + 1
		elseif stair == STAIRS_MN then
			return left, y - 3, right + 1, y
		else -- STAIRS_BN
			return left, y - 3, right + 1, y - 2
		end
	else--if stair == STAIRS_TW or stair == STAIRS_MW or stair == STAIRS_BW then
		local left = y - 1
		for i = left, y - 32, -1 do
			left = i
			local adj = _getGridSquare(cell, x, i, z)
			if not adj or _getStairs(adj) ~= stair then
				break
			end
		end

		local right = y + 1
		for i = right, y + 32 do
			right = i
			local adj = _getGridSquare(cell, x, i, z)
			if not adj or _getStairs(adj) ~= stair then
				break
			end
		end

		if stair == STAIRS_TW then
			return x - 2, left, x + 1, right + 1
		elseif stair == STAIRS_MW then
			return x - 3, left, x, right + 1
		else -- STAIRS_BW
			return x - 3, left, x - 2, right + 1
		end
	end
end

local _getLookVector = get_method(zombie.characters.IsoPlayer, "getLookVector")
local _getVecX = get_method(zombie.iso.Vector2, "getX")
local _getVecY = get_method(zombie.iso.Vector2, "getY")
local _getVehicle = get_method(zombie.characters.IsoPlayer, "getVehicle")
local _isAiming = get_method(zombie.characters.IsoPlayer, "isAiming")
local _isLookingWhileInVehicle = get_method(zombie.characters.IsoPlayer, "isLookingWhileInVehicle")
local _isDriver = get_method(zombie.vehicles.BaseVehicle, "isDriver")
local _getCurrentSpeedKmHour = get_method(zombie.vehicles.BaseVehicle, "getCurrentSpeedKmHour")

local outLookVec = Vector2.new()

local function calculateLookDir(ply)
	_getLookVector(ply, outLookVec)
	local lookX, lookY = _getVecX(outLookVec), _getVecY(outLookVec)

	local veh = _getVehicle(ply)

	if ( -- look direction is flipped while reversing a car
		veh
		and not _isAiming(ply)
		and not _isLookingWhileInVehicle(ply)
		and _isDriver(veh, ply)
		and _getCurrentSpeedKmHour(veh) < -1
	) then
		lookX, lookY = -lookX, -lookY
	end

	return lookX, lookY
end

local _getLightInfo = get_method(zombie.iso.IsoGridSquare, "getLightInfo")
local _getColR = get_method(zombie.core.textures.ColorInfo, "getR")
local _getColG = get_method(zombie.core.textures.ColorInfo, "getG")
local _getColB = get_method(zombie.core.textures.ColorInfo, "getB")

local function getLuma(sqr, pidx)
	if not sqr then
		return 0
	end

	local ci = _getLightInfo(sqr, pidx)

	if not ci then
		return 0
	end

	return _getColR(ci) * 0.299 + _getColG(ci) * 0.587 + _getColB(ci) * 0.114
end

local _getDayLightStrength = get_method(zombie.iso.weather.ClimateManager, "getDayLightStrength")
local _getPlayerStats = get_method(zombie.characters.IsoPlayer, "getStats")
local _getPlayerMoodles = get_method(zombie.characters.IsoPlayer, "getMoodles")
local _getStat = get_method(zombie.characters.Stats, "get")
local _isStatAtMaximum = get_method(zombie.characters.Stats, "isAtMaximum")
local _getMoodleLevel = get_method(zombie.characters.Moodles.Moodles, "getMoodleLevel")
local _getCurrentSquare = get_method(zombie.characters.IsoGameCharacter, "getCurrentSquare")
local _getAdjacentSquare = get_method(zombie.iso.IsoGridSquare, "getAdjacentSquare")
local _getPlayerDir = get_method(zombie.characters.IsoPlayer, "getDir")
local _isPlayerInARoom = get_method(zombie.characters.IsoPlayer, "isInARoom")
local _hasTrait = get_method(zombie.characters.IsoPlayer, "hasTrait")
local _getHeadlightsOn = get_method(zombie.vehicles.BaseVehicle, "getHeadlightsOn")
local _getHeadlightCanEmitLight = get_method(zombie.vehicles.BaseVehicle, "getHeadlightCanEmmitLight")
local _getWornItemsVisionMultiplier = get_method(zombie.characters.IsoPlayer, "getWornItemsVisionMultiplier")

local STAT_FATIGUE, STAT_INTOXICATION = CharacterStat.FATIGUE, CharacterStat.INTOXICATION
local MOODLE_DRUNK, MOODLE_PANIC = MoodleType.DRUNK, MoodleType.PANIC
local TRAIT_EAGLE_EYED, TRAIT_NIGHT_VISION = CharacterTrait.EAGLE_EYED, CharacterTrait.NIGHT_VISION

local singleton_ClimateManager

-- reimplemented LightingJNI.calculateVisionCone because zomboid doesn't expose this for some reason
local function calculateCone(ply, pidx)
	if not singleton_ClimateManager then
		singleton_ClimateManager = getClimateManager()
	end

	local dayStr = _getDayLightStrength(singleton_ClimateManager)
	local dayInv = 1 - dayStr

	local veh = _getVehicle(ply)

	local stats, moods = _getPlayerStats(ply), _getPlayerMoodles(ply)
	local c

	if not veh then
		c = 144 - 72 * _getStat(stats, STAT_FATIGUE)

		if c > 144 then
			-- copied from java impl, probably unreachable, i don't think fatigue will ever be negative
			c = 144
		end

		if _isStatAtMaximum(stats, STAT_FATIGUE) then
			c = c - 36
		end

		if _getMoodleLevel(moods, MOODLE_DRUNK) >= 2 then
			c = c - 0.36 * _getStat(stats, STAT_INTOXICATION)
		end

		if _getMoodleLevel(moods, MOODLE_PANIC) == 4 then
			c = c - 36
		end

		local lumaInv = 1

		local sqr = ply_square

		if not sqr then
			sqr = _getCurrentSquare(ply)
			ply_square = sqr
		end

		if sqr then
			local lumaCur = getLuma(sqr, pidx)
			local lumaAdj = getLuma(_getAdjacentSquare(sqr, _getPlayerDir(ply)), pidx)

			lumaInv = 1 - (lumaCur > lumaAdj and lumaCur or lumaAdj) -- max(lumaCur, lumaAdj)
		end

		if _isPlayerInARoom(ply) then
			c = c - 126 * lumaInv
		else
			c = c - 126 * (dayInv < lumaInv and dayInv or lumaInv) -- min(dayInv, lumaInv)
		end

		c = c > 18 and (c < 180 and c or 180) or 18 -- clamp(c, 18, 180)

		if _hasTrait(ply, TRAIT_EAGLE_EYED) then
			c = c + 36 * dayStr
		end

		if _hasTrait(ply, TRAIT_NIGHT_VISION) then
			c = c + 36 * dayInv
		end
	else
		c = 324 - 540 * dayInv

		if _isStatAtMaximum(stats, STAT_FATIGUE) then
			c = c - 36
		end

		if _getMoodleLevel(moods, MOODLE_DRUNK) >= 2 then
			c = c - 0.36 * _getStat(stats, STAT_INTOXICATION)
		end

		if _getMoodleLevel(moods, MOODLE_PANIC) == 4 then
			c = c - 36
		end

		if _hasTrait(ply, TRAIT_NIGHT_VISION) then
			c = c + 36 * dayInv
		end

		if _getHeadlightsOn(veh) and _getHeadlightCanEmitLight(veh) and c < 36 then
			c = 36
		end
	end

	c = c * _getWornItemsVisionMultiplier(ply)

	return c > 18 and (c < 360 and c or 360) or 18 -- clamp(c, 18, 360)
end

local function encodeCoords(x, y, z)
	-- only 53 bits are useable for this because kahlua doesnt have bitwise operators
	-- 6 bits for z (-32 to 31), 23 bits for y (-4194304 to 4194303), 24 bits for x (-8388608 to 8388607)
	--return (x + 0x800000) * 0x20000000 + (y + 0x400000) * 0x40 + (z + 0x20)
	return x * 0x20000000 + y * 0x40 + z + 0x10000010000020
end
local function decodeCoords(key)
	local y = key % 0x20000000
	local z = y % 0x40
	local x = (key - y) * (1 / 0x20000000) - 0x800000
	y = (y - z) * (1 / 0x40) - 0x400000
	z = z - 0x20
	return x, y, z
end

-- note: unlike standard lua tables that can have both a hash and an array part,
-- kahlua tables can have only a hash part or an array part if created with table.newarray
local table_newarray, table_wipe = table.newarray, table.wipe

local tileInfoCache, tileCacheCount, tileCacheAdded = {}, 0, false
local doorTiles, doorTilesCount = table_newarray(), 0
-- this should pre-allocate 257 slots according to se.krka.kahlua.vm.KahluaTable.rawset
doorTiles[129] = false

-- event name is misleading, this is actually the only event that will trigger when doors and curtains are toggled
-- other random actions like felling trees also trigger this, it's very awful, but nothing i can do about it
hook_event("OnContainerUpdate", function(obj)
	if obj then
		-- this often means it was triggered by inventory stuff or corpse stuff
		return
	end

	if doorTilesCount == 0 or tileCacheCount == 0 then
		return
	end

	if doorTilesCount == -1 then
		table_wipe(tileInfoCache)
		tileCacheCount, doorTilesCount = 0, 0
		return
	end

	local doorTiles = doorTiles
	local cache = tileInfoCache

	for i = 1, doorTilesCount do
		local key = doorTiles[i]

		if cache[key] then
			cache[key] = nil
			tileCacheCount = tileCacheCount - 1
		end
	end

	doorTilesCount = 0
end)

local newchunks = false

hook_event("LoadChunk", function(sqr)
	newchunks = true
end)

local zombie_count = 0

local chunkClearCooldown = 0

local stairZombies, stairZombiesFade = table_newarray(), {}
local stairZombiesCount, stairZombiesTime

local singleton_GameTime

local _getRealworldSecondsSinceLastUpdate = get_method(zombie.GameTime, "getRealworldSecondsSinceLastUpdate")
local _getChunkMap = get_method(zombie.iso.IsoCell, "getChunkMap")
local _getWorldXMinTiles = get_method(zombie.iso.IsoChunkMap, "getWorldXMinTiles")
local _getWorldYMinTiles = get_method(zombie.iso.IsoChunkMap, "getWorldYMinTiles")
local _getWorldXMaxTiles = get_method(zombie.iso.IsoChunkMap, "getWorldXMaxTiles")
local _getWorldYMaxTiles = get_method(zombie.iso.IsoChunkMap, "getWorldYMaxTiles")

local pairs = pairs

hook_event("OnTick", function(ticks)
	current_tick = ticks

	if not singleton_GameTime then
		singleton_GameTime = GameTime.getInstance()
	end

	current_delta = _getRealworldSecondsSinceLastUpdate(singleton_GameTime)

	if current_delta < 0.0001 then
		current_delta = 0.0001
	end

	current_time = current_time + current_delta

	zombie_count = 0

	if stairZombiesTime and current_time > stairZombiesTime + 0.5 then
		stairZombiesCount, stairZombiesTime = nil
		table_wipe(stairZombies)
		table_wipe(stairZombiesFade)
	end

	if not newchunks then
		return
	end

	if current_time < chunkClearCooldown then
		-- this cooldown is so that this doesnt trigger constantly while driving fast
		-- driving in vanilla is already stuttery as fuck and i dont wanna add to that
		return
	end

	newchunks = false

	if tileCacheCount == 0 or not tileCacheAdded then
		return
	end

	chunkClearCooldown = current_time + 3

	if not singleton_IsoCell then
		singleton_IsoCell = getCell()
	end

	local cm = _getChunkMap(singleton_IsoCell, 0)

	if not cm then
		return
	end

	-- unreadable shit, but this is faster than decoding the keys
	local minX = (_getWorldXMinTiles(cm) + 0x800000) * 0x20000000
	local minY = (_getWorldYMinTiles(cm) + 0x400000) * 0x40
	local maxX = (_getWorldXMaxTiles(cm) + 0x800001) * 0x20000000
	local maxY = (_getWorldYMaxTiles(cm) + 0x400001) * 0x40

	local cache = tileInfoCache

	-- kahlua pairs() returns a stateful iterator that allocates a snapshot of the table keys
	-- but there's no other way around this that isnt just as slow or slower
	for key in pairs(cache) do repeat
		if key >= minX and key < maxX then
			local r = key % 0x20000000

			if r >= minY and r < maxY then
				break
			end
		end

		cache[key] = nil
		tileCacheCount = tileCacheCount - 1
	until true end

	tileCacheAdded = false
end)

local _getObjectSquare = get_method(zombie.iso.IsoObject, "getSquare")
local _getSquareX = get_method(zombie.iso.IsoGridSquare, "getX")
local _getSquareY = get_method(zombie.iso.IsoGridSquare, "getY")
local _getSquareZ = get_method(zombie.iso.IsoGridSquare, "getZ")

local function onObjectAddedOrRemoved(obj)
	if not obj then
		return
	end

	ply_stair, ply_stairSquare = nil

	if tileCacheCount == 0 then
		return
	end

	local sqr = _getObjectSquare(obj)

	if not sqr then
		return
	end

	local x, y, z = _getSquareX(sqr), _getSquareY(sqr), _getSquareZ(sqr)

	local key = x * 0x20000000 + y * 0x40 + z + 0x10000010000020 -- encodeCoords(x, y, z)

	local cache = tileInfoCache

	if cache[key] then
		cache[key] = nil
		tileCacheCount = tileCacheCount - 1
	end

	local keyEast = key + 0x20000000

	if cache[keyEast] then
		cache[keyEast] = nil
		tileCacheCount = tileCacheCount - 1
	end

	local keySouth = key + 0x40

	if cache[keySouth] then
		cache[keySouth] = nil
		tileCacheCount = tileCacheCount - 1
	end
end

hook_event("OnTileRemoved", onObjectAddedOrRemoved)

-- this doesnt fire on walls being built for some reason which is really annoying
-- nobody's going to be doing house construction in the middle of a horde so this is probably fine tbh
hook_event("OnObjectAdded", onObjectAddedOrRemoved)

local TILE_CLEAR = 0x0
local WALL_NORTH = 0x1
local WALL_WEST  = 0x2
local WALL_BOTH  = 0x3
local TILE_SOLID = 0x4

-- tostring on a userdata is slow so i need to use a pointer comparison
-- LosUtil.TestResults.Blocked is inaccessible for some reason so i need to catch it as a function return first
local RESULT_BLOCKED

local PROPERTY_BLOCKSIGHT = IsoFlagType.blocksight

local DIRECTION_NORTH, DIRECTION_WEST = IsoDirections.N, IsoDirections.W

local _getTree = get_method(zombie.iso.IsoGridSquare, "getTree")
local _getTreeProperties = get_method(zombie.iso.objects.IsoTree, "getProperties")
local _hasProperty = get_method(zombie.core.properties.PropertyContainer, "has")
local _isSolid = get_method(zombie.iso.IsoGridSquare, "isSolid")
local _testVisionAdjacent = get_method(zombie.iso.IsoGridSquare, "testVisionAdjacent")
local _getDoorOrWindowOrWindowFrame = get_method(zombie.iso.IsoGridSquare, "getDoorOrWindowOrWindowFrame")

local function tileInfo(x, y, z, key)
	if not singleton_IsoCell then
		singleton_IsoCell = getCell()
	end

	local sqr = _getGridSquare(singleton_IsoCell, x, y, z)

	if not sqr then
		return
	end

	local flags = 0x0 -- TILE_CLEAR

	local tree = _getTree(sqr)

	if tree then
		local props = _getTreeProperties(tree)

		if props and _hasProperty(props, PROPERTY_BLOCKSIGHT) then
			flags = 0x4 -- TILE_SOLID
		end
	elseif _isSolid(sqr) then
		flags = 0x4 -- TILE_SOLID
	end

	if flags ~= 0x4 --[[ TILE_SOLID ]] then
		if not RESULT_BLOCKED then
			-- these invalid coords always give a blocked result
			RESULT_BLOCKED = _testVisionAdjacent(sqr, -2, -2, -2, false, false)
		end

		if _testVisionAdjacent(sqr, 0, -1, 0, false, false) == RESULT_BLOCKED then
			flags = flags + 0x1 -- WALL_NORTH
		end

		if _testVisionAdjacent(sqr, -1, 0, 0, false, false) == RESULT_BLOCKED then
			flags = flags + 0x2 -- WALL_WEST
		end
	end

	if not tileInfoCache[key] then
		if tileCacheCount >= 16384 then -- i think this should be around 1 MB
			tileInfoCache, tileCacheCount, doorTilesCount = {}, 0, 0 -- just let gc wipe this
		end

		tileCacheCount = tileCacheCount + 1
		tileCacheAdded = true

		if doorTilesCount ~= -1 and (
			_getDoorOrWindowOrWindowFrame(sqr, DIRECTION_NORTH, false)
			or _getDoorOrWindowOrWindowFrame(sqr, DIRECTION_WEST, false)
		) then
			if doorTilesCount < 256 then
				doorTilesCount = doorTilesCount + 1
				doorTiles[doorTilesCount] = key
			else
				-- this sentinel means just invalidate the whole cache
				doorTilesCount = -1
			end
		end
	end

	tileInfoCache[key] = flags

	return flags
end

local INFINITY = math.huge

-- normally i'd avoid kahlua math lib functions because theyre slow, but using arithmetics for this is slower
local floor = math.floor

local function lineClear(x1, y1, x2, y2, z)
	local x, y = floor(x1), floor(y1)
	local tx, ty = floor(x2), floor(y2)

	local n = (tx > x and tx - x or x - tx) + (ty > y and ty - y or y - ty)

	if n == 0 then
		return true -- same tile
	end

	local key = x * 0x20000000 + y * 0x40 + z + 0x10000010000020 -- encodeCoords(x, y, z)
	local cur = tileInfoCache[key] or tileInfo(x, y, z, key)

	if not cur then
		return false -- tile is probably unloaded or something
	end

	if cur == 0x4  --[[ TILE_SOLID ]] then
		return false -- inside a solid tile or tree
	end

	local dx, dy = x2 - x1, y2 - y1
	local sx, sy = dx > 0 and 1 or -1, dy > 0 and 1 or -1
	local px, py = sx > 0, sy > 0

	local tdx = dx ~= 0 and (1 / (dx < 0 and -dx or dx)) or INFINITY -- abs(dx)
	local tdy = dy ~= 0 and (1 / (dy < 0 and -dy or dy)) or INFINITY -- abs(dy)
	local tmx = x ~= tx and ((px and x + 1 - x1 or x1 - x) * tdx) or INFINITY
	local tmy = y ~= ty and ((py and y + 1 - y1 or y1 - y) * tdy) or INFINITY

	-- this is faster than decoding and reencoding
	local keyStepX, keyStepY = sx * 0x20000000, sy * 0x40

	for i = n, 1, -1 do
		if tmx < tmy then
			local nkey = key + keyStepX
			local v = tileInfoCache[nkey] or tileInfo(x + sx, y, z, nkey)

			if not v then
				return false -- tile is invalid for some reason
			end

			local c = px and v or cur

			if c == 0x2 --[[ WALL_WEST ]] or c == 0x3 --[[ WALL_BOTH ]] then
				return false
			end

			if v == 0x4 --[[ TILE_SOLID ]] and i ~= 1 then
				return false
			end

			x, key, cur, tmx = x + sx, nkey, v, tmx + tdx

			if x == tx then
				tmx = INFINITY -- target x is reached
			end
		else
			local nkey = key + keyStepY
			local v = tileInfoCache[nkey] or tileInfo(x, y + sy, z, nkey)

			if not v then
				return false -- tile is invalid for some reason
			end

			local c = py and v or cur

			if c == 0x1 --[[ WALL_NORTH ]] or c == 0x3 --[[ WALL_BOTH ]] then
				return false
			end

			if v == 0x4 --[[ TILE_SOLID ]] and i ~= 1 then
				return false
			end

			y, key, cur, tmy = y + sy, nkey, v, tmy + tdy

			if y == ty then
				tmy = INFINITY -- target y is reached
			end
		end
	end

	return true -- raytrace is clear :)
end

-- this is outside because OnZombieUpdate hits the upvalue limit lmfao
-- tail call optimisation makes this faster anyway
local function addStairZombie(zom)
	stairZombiesTime = current_time

	local fade = stairZombiesFade[zom]

	if fade then
		if current_time > fade then
			stairZombiesFade[zom] = current_time
		end
	else
		stairZombiesCount = (stairZombiesCount or 0) + 1
		stairZombies[stairZombiesCount] = zom
		stairZombiesFade[zom] = ply_zUp == ply_zLast and current_time or current_time + 0.25
	end
end

local _getZombieTargetAlpha = get_method(zombie.characters.IsoZombie, "getTargetAlpha")
local _setZombieTargetAlpha = get_method(zombie.characters.IsoZombie, "setTargetAlpha")
local _getZombieAlpha = get_method(zombie.characters.IsoZombie, "getAlpha")
local _getX = get_method(zombie.characters.IsoGameCharacter, "getX")
local _getY = get_method(zombie.characters.IsoGameCharacter, "getY")
local _getZ = get_method(zombie.characters.IsoGameCharacter, "getZ")
local _isOnScreen = get_method(zombie.iso.IsoGridSquare, "IsOnScreen")
local _getViewDist = get_method(zombie.GameTime, "getViewDist")
local _getDetectionRange = get_method(zombie.characters.IsoPlayer, "getDetectionRange")
local _getZombieTarget = get_method(zombie.characters.IsoZombie, "getTarget")
local _isCouldSee = get_method(zombie.iso.IsoGridSquare, "isCouldSee")
local _couldSeeHeadSquare = get_method(zombie.characters.IsoZombie, "couldSeeHeadSquare")
local _TestZombieSpotPlayer = get_method(zombie.characters.IsoPlayer, "TestZombieSpotPlayer")

local LosUtil_lineClear = zombie.iso.LosUtil.lineClear

-- this doesn't really need to be cleaned up since this is just gonna be a bunch of doubles and bools
local doNotStagger = {}

hook_event("OnZombieUpdate", function(zom)
	if MOD_DISABLED then
		return
	end

	if not localPlayer then
		return
	end

	if AIMING_ONLY then
		local aiming = ply_aiming

		if aiming == nil then
			aiming = _isAiming(localPlayer)
			ply_aiming = aiming
		end

		if not aiming then
			return
		end
	end

	zombie_count = zombie_count + 1

	if MAX_ZOMBIES_PER_TICK and zombie_count > MAX_ZOMBIES_PER_TICK then
		return
	end

	local nostag

	if (current_tick + zombie_count) % 4 ~= 0 then
		nostag = doNotStagger[zombie_count]

		if nostag then
			doNotStagger[zombie_count] = nil
		else
			return
		end
	end

	local pZ = ply_z

	if not pZ then
		pZ = floor(ply_fakeZ or _getZ(localPlayer))
		ply_z, ply_zUp = pZ, pZ + 1
	end

	local zZ = floor(_getZ(zom))

	local upstairs = STAIR_O_VISION and not ply_fakeZ and ply_zUp == zZ

	if upstairs then
		local sqr = ply_square

		if not sqr then
			sqr = _getCurrentSquare(localPlayer)
			ply_square = sqr

			if not sqr then
				return -- erm what the fauci
			end
		end

		if sqr ~= ply_stairSquare then
			ply_stairSquare = sqr
			ply_stair = _getStairs(sqr)
			ply_stairMinX = nil

			if ply_stair == STAIRS_MAX then
				ply_stair = nil
				return -- not stairs
			end
		elseif not ply_stair then
			return
		end
	else
		if pZ ~= zZ then
			return -- ignore if not on the same level
		end

		if not nostag and _getZombieTargetAlpha(zom) ~= 0 then
			return -- already visible, skip this zombie
		end
	end

	local zSqr = _getCurrentSquare(zom)

	if not zSqr then
		return -- not sure why this would happen
	end

	if nostag and not upstairs and _isCouldSee(zSqr, 0) then
		return
	end

	if not _isOnScreen(zSqr, true) then
		return -- should be off-screen, but i kinda dont trust this function tbh
	end

	local zX, zY = _getX(zom), _getY(zom)

	local pX, pY = ply_x, ply_y

	if not pX then
		pX, pY = _getX(localPlayer), _getY(localPlayer)
		ply_x, ply_y = pX, pY
	end

	local dirX, dirY = zX - pX, zY - pY
	local distSq = dirX * dirX + dirY * dirY

	local viewDist = ply_viewDist

	if not viewDist then
		if not singleton_GameTime then
			singleton_GameTime = GameTime.getInstance()
		end

		viewDist = _getViewDist(singleton_GameTime)

		local maxdist = MAX_ZOMBIE_DISTANCE

		if maxdist and viewDist > maxdist then
			viewDist = maxdist
		end

		viewDist = viewDist * viewDist
		ply_viewDist = viewDist
	end

	if distSq > viewDist then
		return -- outside of view distance (depends on weather i think)
	end

	local detectDist = ply_detectDist

	if not detectDist then
		detectDist = _getDetectionRange(localPlayer)
		detectDist = detectDist * detectDist
		ply_detectDist = detectDist
	end

	if distSq > detectDist then -- outside of "hearing" radius
		local lookX, lookY = ply_lookX, ply_lookY

		if not lookX then
			lookX, lookY = calculateLookDir(localPlayer)
			ply_lookX, ply_lookY = lookX, lookY
		end

		local cone = ply_cone

		if not cone then
			cone = (180 - calculateCone(localPlayer, 0)) * (1 / 180)
			cone = cone * (cone < 0 and -cone or cone) -- abs(cone)
			ply_cone = cone
		end

		local dot = dirX * lookX + dirY * lookY

		if dot * (dot < 0 and -dot or dot) < cone * distSq then -- abs(dot)
			return -- not within view cone
		end
	end

	local z = pZ

	if upstairs then
		local minX, minY, maxX, maxY = ply_stairMinX, ply_stairMinY, ply_stairMaxX, ply_stairMaxY

		if not minX then
			minX, minY, maxX, maxY = calculateStairBounds(
				ply_stair, floor(pX), floor(pY), z
			)
			ply_stairMinX, ply_stairMinY, ply_stairMaxX, ply_stairMaxY = minX, minY, maxX, maxY
		end

		if zX < minX or zX >= maxX or zY < minY or zY >= maxY then
			return -- not close to stairs
		end

		z = ply_zUp
	end

	local seenEpicStyle

	if RAYTRACE_FN == 1 then
		if not lineClear(pX, pY, zX, zY, z) then
			return -- line of sight is blocked
		end
	else
		if not singleton_IsoCell then
			singleton_IsoCell = getCell()
		end

		if not RESULT_BLOCKED then
			-- these invalid coords always give a blocked result
			RESULT_BLOCKED = _testVisionAdjacent(zSqr, -2, -2, -2, false, false)
		end

		-- i made a whole caching system for this and when i benched it it was slower, very sad
		if RESULT_BLOCKED == LosUtil_lineClear(
			singleton_IsoCell, pX, pY, z, zX, zY, z, false
		) then
			if RAYTRACE_FN == 3 and lineClear(pX, pY, zX, zY, z) then
				seenEpicStyle = false
			else
				return
			end
		elseif RAYTRACE_FN == 3 then
			seenEpicStyle = true
		end
	end

	if ZOMBIE_DETECTION and (
		current_tick % ((seenEpicStyle == false and 0.5 or 0.1) / current_delta) < 1
	) and not (
		-- these mean that the game has already handled detection
		_getZombieTarget(zom) or _isCouldSee(zSqr, 0) or _couldSeeHeadSquare(zom, localPlayer)
	) then
		_TestZombieSpotPlayer(localPlayer, zom)
	end

	doNotStagger[zombie_count] = true

	if upstairs then
		return addStairZombie(zom)
	end

	return _setZombieTargetAlpha(zom, seenEpicStyle and 1 or TARGET_ALPHA)
end)

local PeekAView_StairView, PeekAView_Enabled

local _setZombieAlpha = get_method(zombie.characters.IsoZombie, "setAlpha")
--local _renderZombieShadow = get_method(zombie.characters.IsoZombie, "renderShadow")
local _renderZombie = get_method(zombie.characters.IsoZombie, "render")

local DUMMY_COLOR = zombie.core.textures.ColorInfo.new(1,1,1,1)

hook_event("RenderOpaqueObjectsInWorld", function(pIdx, _, _, pZ)
	if pIdx ~= 0 then
		return
	end

	if PeekAView_StairView and PeekAView_StairView:getValue() and PeekAView_Enabled:getValue() then
		if not ply_fakeZ and localPlayer then
			ply_fakeZ = _getZ(localPlayer)
		end

		return
	end

	if not stairZombiesCount then
		return
	end

	local zombies, fade = stairZombies, stairZombiesFade
	local _getZ, _setZombieAlpha, _renderZombie = _getZ, _setZombieAlpha, _renderZombie
	local current_time, TARGET_ALPHA_STAIRS, DUMMY_COLOR = current_time, TARGET_ALPHA_STAIRS, DUMMY_COLOR

	for i = stairZombiesCount, 1, -1 do
		local zom = zombies[i]

		if zom then
			local t = current_time - fade[zom]

			if t < 0.5 and _getZ(zom) > pZ then
				local alpha

				if t < 0 then
					alpha = TARGET_ALPHA_STAIRS * ((t + 0.25) * (1 / 0.25))
				elseif t < 0.1 then
					alpha = TARGET_ALPHA_STAIRS
				else
					alpha = TARGET_ALPHA_STAIRS * (1 - (t - 0.1) * (1 / 0.4))
				end

				_setZombieAlpha(zom, alpha)
				_renderZombie(zom, 0, 0, 0, DUMMY_COLOR, false, false, nil)
			else
				local last = zombies[stairZombiesCount]
				zombies[i] = last
				zombies[stairZombiesCount] = nil
				stairZombiesCount = stairZombiesCount ~= 1 and stairZombiesCount - 1 or nil
				fade[zom] = nil
			end
		end
	end
end)

-- i think lua state gets reset when loading into a save, so this is probably unnecessary
hook_event("OnGameStart", function()
	print("[ZomVisFix] OnGameStart")

	current_tick, current_time, current_delta = 0, 0, 0.01

	tileInfoCache, tileCacheCount, tileCacheAdded = {}, 0, false
	doorTiles, doorTilesCount = table_newarray(), 0
	doorTiles[129] = false

	stairZombies, stairZombiesFade = table_newarray(), {}
	stairZombiesCount, stairZombiesTime = nil

	chunkClearCooldown = 0

	localPlayer = nil
	ply_x, ply_y, ply_z, ply_zLast, ply_zUp, ply_fakeZ = nil
	ply_viewDist, ply_detectDist = nil
	ply_lookX, ply_lookY, ply_cone = nil
	ply_aiming = nil
	ply_square, ply_stair, ply_stairSquare = nil
	ply_stairMinX, ply_stairMinY, ply_stairMaxX, ply_stairMaxY = nil

	singleton_IsoCell, singleton_GameTime, singleton_ClimateManager = nil
end)

print("[ZomVisFix] lua file loaded")

;(function()
	--if not getActivatedMods():contains("PeekAView") then
	--	return
	--end

	local pavopts = PZAPI.ModOptions:getOptions("PeekAView")

	if not pavopts then
		return
	end

	local pavopt_stair = pavopts:getOption("stairEnabled")

	if not (pavopt_stair and pavopt_stair.getValue) then
		return
	end

	local pavopt_enabled = pavopts:getOption("enable")

	if not (pavopt_enabled and pavopt_enabled.getValue) then
		return
	end

	PeekAView_StairView = pavopt_stair
	PeekAView_Enabled = pavopt_enabled

	print("[ZomVisFix] PeekAView detected")
end)()
