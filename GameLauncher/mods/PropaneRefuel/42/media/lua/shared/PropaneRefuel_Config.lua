PropaneRefuel = PropaneRefuel or {}

PropaneRefuel.defaults = {
	PropaneTankCost = 20,
	BlowTorchCost = 4,
	PropaneBottleCost = 6,
	AllowBlowTorch = true,
	AllowPropaneBottle = true,
	AllowPropaneTruck = true,
	AllowTankerRefill = true,
	PropaneTruckReserveMin = 0,
	PropaneTruckReserveMax = 200,
	AllowIndustrialTanks = true,
	IndustrialTankSpawnMin = 0,
	IndustrialTankSpawnMax = 500,
	IndustrialTankCapacity = 1000,
}

-- fullType -> {
--   cost  = sandbox option holding the pump units needed for a full refill,
--   allow = optional sandbox boolean that can switch the item off entirely,
-- }
-- Other mods may add entries here to make their own propane drainables refuellable.
PropaneRefuel.refillable = {
	["Base.PropaneTank"]    = { cost = "PropaneTankCost" },
	["Base.BlowTorch"]      = { cost = "BlowTorchCost",     allow = "AllowBlowTorch" },
	["Base.Propane_Refill"] = { cost = "PropaneBottleCost", allow = "AllowPropaneBottle" },
}

-- getText() hands back the key itself when a translation is missing, which is how raw
-- "ContextMenu_PropaneRefuel_Refill" text ends up on screen. Always fall back to English.
function PropaneRefuel.getText(key, fallback)
	local value = getText(key)
	if value == nil or value == "" or value == key then
		return fallback
	end
	return value
end

-- ---------------------------------------------------------------------------------
-- Timed action plumbing shared by all three actions
-- ---------------------------------------------------------------------------------

-- Where a running action reads its progress from, and it is not the same everywhere.
--
-- On a dedicated server an action is the server's emulation of a remote player's:
-- animEvent drives it from netAction, ISBaseTimedAction:begin() never ran, and so
-- action.action is nil. getJobDelta() goes straight through action.action, so touching
-- it there errors on every tick -- which takes the refill down for every client on the
-- server. Vanilla draws exactly this line in ISAddGasolineToVehicle and
-- ISPickupFishAction: netAction on the server, getJobDelta() otherwise.
--
-- A co-op host can have both, and its netAction is not necessarily being driven, so take
-- whichever is further along. That is what keeps the host's own action moving.
function PropaneRefuel.actionProgress(action)
	local progress = 0
	if action.netAction then
		progress = action.netAction:getProgress() or 0
	end
	if action.action then
		progress = math.max(progress, action:getJobDelta())
	end
	return progress
end

-- start() re-plans against the source as it stands, so the duration has to be re-applied
-- with it: a "Fill All" whose last item only earns a splash should not take as long as
-- the first one that filled completely.
--
-- ISBaseTimedAction:setTime only writes maxTime, which the Java action already read in
-- create() -- called from begin(), before start() -- so by then it changes nothing. The
-- live action is what has to be told, the way vanilla ISOpenVehicleDoor does it.
function PropaneRefuel.applyActionDuration(action)
	local duration = action:getDuration()
	action.maxTime = duration
	if action.action then
		action.action:setTime(action:adjustMaxTime(duration))
	end
end

function PropaneRefuel.getOption(name)
	local vars = SandboxVars and SandboxVars.PropaneRefuel
	local value = vars and vars[name]
	if value == nil then
		return PropaneRefuel.defaults[name]
	end
	return value
end

-- Pump units consumed to take an item from empty to full, or nil if it is not refuellable.
function PropaneRefuel.getPumpCost(item)
	local entry = PropaneRefuel.refillable[item:getFullType()]
	if not entry then return nil end
	if entry.allow and not PropaneRefuel.getOption(entry.allow) then
		return nil
	end
	return math.max(1, PropaneRefuel.getOption(entry.cost))
end

function PropaneRefuel.canRefill(item)
	if not instanceof(item, "DrainableComboItem") then return false end
	if item:isBroken() then return false end
	if item:getCurrentUsesFloat() >= 1.0 then return false end
	return PropaneRefuel.getPumpCost(item) ~= nil
end

-- Vanilla's own pump lookup (ISVehiclePartMenu.getNearbyFuelPump) accepts ANY object
-- reporting piped fuel and sweeps a 5x5 area around the target. Anything stricter than
-- that recognises fewer pumps than the game itself does -- which is exactly how players
-- ended up at a pump that filled a gas can normally but offered no propane option.
-- So: match vanilla, and filter only the fuel storage other mods add.
PropaneRefuel.excludedPumpNames = {
	FuelBarrel = true,
}

function PropaneRefuel.isGasPump(object)
	if not instanceof(object, "IsoObject") then return false end
	if object:getPipedFuelAmount() <= 0 then return false end

	local name = object:getName()
	if name and PropaneRefuel.excludedPumpNames[name] then return false end

	return true
end

-- A pump is a machine, and a machine with no power does not run. Nothing here checked
-- that, which is how propane could be drawn from a dead station with no generator going
-- while the vanilla petrol option on the same pump was correctly hidden.
--
-- The expression is lifted from ISVehicleMenu's "Refuel from pump" option rather than
-- invented, so the propane option now appears in exactly the cases the vanilla petrol one
-- does: no pump that fills a car refuses a propane tank, and no pump that refuses a car
-- quietly hands out propane. That includes the grid still being on early in a run, which
-- is why hasGridPower() is here and not just the generator test.
--
-- AllowExteriorGenerator is the GAME's sandbox option, not one of this mod's, so it is
-- read straight off SandboxVars -- getOption() only ever looks inside SandboxVars.PropaneRefuel.
--
-- Deliberately kept out of isGasPump(). A pump with the power off is still a pump; it is
-- only temporarily unusable, and the menu says so in the label rather than vanishing --
-- an option that simply disappears is indistinguishable from the mod being broken.
function PropaneRefuel.isPumpPowered(pump)
	local square = pump and pump:getSquare()
	if not square then return false end

	if square:hasGridPower() then return true end
	if SandboxVars and SandboxVars.AllowExteriorGenerator and square:haveElectricity() then return true end

	return false
end

-- ---------------------------------------------------------------------------------
-- Propane tankers from other mods
--
-- Entirely opt-in and dependency-free: matched purely on vehicle script name, so if the
-- mod that adds the vehicle is not installed, nothing here ever matches and nothing
-- about the pump behaviour changes. Add a line to support another mod's tanker.
--
-- Script names differ between releases of the same mod, so both are listed. The B41-era
-- Filibuster Rhymes' Used Cars called its tanker "f700propane"; the Build 42 rebuild
-- renamed it "fr_fo_f700_90_propane". Matching only the old name is why the truck showed
-- no propane options at all.
--
-- Neither truck exposes propane this mod can read: the B41 one is livery only, and the
-- B42 one stores it in its own FRPropaneTank part handled by that mod's own Lua. The
-- reserve here is therefore something this mod keeps itself, in its own ModData key.
-- ---------------------------------------------------------------------------------
PropaneRefuel.propaneVehicles = {
	f700propane = true,
	fr_fo_f700_90_propane = true,

	-- StepVan_Propane is livery only -- a delivery van with propane branding and no
	-- tank. Treating it as bulk storage put two propane sources next to each other at
	-- the same gas station, which read as one truck holding two different amounts.
	-- StepVan_Propane = true,
}

-- The reserve lives in the GasTank part's ModData purely because a vehicle part is the
-- one thing with a vanilla-proven multiplayer sync call (transmitPartModData, as used by
-- ISRefuelFromGasPump). Only our own key is ever touched.
local RESERVE_KEY = "PropaneRefuelReserve"

-- One bucket in 0..999, spread evenly, from any integer seed.
--
-- Written the long way round on purpose. Lua numbers are doubles, exact only below 2^53,
-- and the obvious `(seed * 1103515245 + 12345) % 2147483648` blows straight past that as
-- soon as the seed is large -- a map coordinate hash is comfortably over 2^40. Past 2^53
-- the low bits are simply gone, and it is the low bits the modulo keeps, so whole runs of
-- seeds collapse onto the same bucket: every tank found holding exactly the same amount.
-- Splitting the multiply into 16-bit halves keeps every intermediate under 2^48, which is
-- exact, and is mathematically the same value the naive form was reaching for.
local function seededBucket(seed)
	local value = math.floor(seed) % 2147483648
	local hi = math.floor(value / 65536)
	local lo = value % 65536
	local hash = ((hi * 1103515245) % 2147483648 * 65536 + lo * 1103515245 + 12345) % 2147483648
	return math.floor(hash / 2147483648 * 1000)
end

-- Randomised per vehicle, but derived from the vehicle id rather than ZombRand, so every
-- client and the server independently arrive at the same starting figure with no sync.
-- A random roll per machine would have each player seeing a different amount of propane
-- in the same truck.
local function seededReserve(vehicle)
	local minUnits = PropaneRefuel.getOption("PropaneTruckReserveMin")
	local maxUnits = PropaneRefuel.getOption("PropaneTruckReserveMax")
	if maxUnits <= minUnits then return math.max(0, minUnits) end

	local bucket = seededBucket(vehicle:getId() or 0)
	return minUnits + math.floor(bucket * (maxUnits - minUnits + 1) / 1000)
end

function PropaneRefuel.isPropaneVehicle(vehicle)
	if not vehicle then return false end
	if not PropaneRefuel.getOption("AllowPropaneTruck") then return false end

	-- Called only with real BaseVehicles, from getVehicleContainer/getNearVehicle, so
	-- getScriptName always exists. Testing for it by field access first would be a
	-- Lua idiom, not a Kahlua one -- on a Java object that lookup does not reliably
	-- resolve methods, and a nil there would silently disable the whole feature.
	local script = vehicle:getScriptName()
	if not script then return false end

	-- getScriptName returns the MODULE-QUALIFIED name at runtime -- the scripts file
	-- declares "fr_fo_f700_90_propane" but the game hands back
	-- "Base.fr_fo_f700_90_propane". Matching only the bare name silently found nothing.
	-- Accept either form so entries can be written either way, under any module.
	if PropaneRefuel.propaneVehicles[script] ~= true then
		local bare = string.match(script, "([^.]+)$")
		if not bare or PropaneRefuel.propaneVehicles[bare] ~= true then return false end
	end

	-- No part means no way to persist or sync a reserve. Refusing here rather than
	-- later stops a modded tanker without a GasTank becoming an infinite supply.
	return vehicle:getPartById("GasTank") ~= nil
end

-- A BaseVehicle handed straight to a timed action is not guaranteed to survive the trip
-- to a dedicated server: vanilla's own ISRefuelFromGasPump carries a VehiclePart and
-- re-derives the vehicle from it rather than passing one. An id is a plain number and
-- always survives, so carry that too and resolve from it whenever the reference is gone.
-- Without this the truck works in singleplayer and silently does nothing on a server.
function PropaneRefuel.resolveVehicle(action)
	if action.vehicle then return action.vehicle end
	-- Testing a global by name is a plain table lookup, unlike probing for a method on a
	-- Java object, so this guard is safe and costs nothing if the function is absent.
	if action.vehicleId and getVehicleById then
		action.vehicle = getVehicleById(action.vehicleId)
	end
	return action.vehicle
end

function PropaneRefuel.getVehicleReserve(vehicle)
	local part = vehicle and vehicle:getPartById("GasTank")
	if not part then return 0 end

	local stored = part:getModData()[RESERVE_KEY]
	if stored == nil then return seededReserve(vehicle) end
	return math.max(0, stored)
end

-- The reserve maximum doubles as the tanker's capacity: a truck is found holding a
-- random amount up to what it can hold, and refilling tops it back up to the same
-- figure. One number, one meaning.
function PropaneRefuel.getTankerCapacity()
	return math.max(0, PropaneRefuel.getOption("PropaneTruckReserveMax"))
end

function PropaneRefuel.setVehicleReserve(vehicle, amount)
	local part = vehicle and vehicle:getPartById("GasTank")
	if not part then return end

	local capped = math.min(math.max(0, amount), PropaneRefuel.getTankerCapacity())
	part:getModData()[RESERVE_KEY] = capped
	vehicle:transmitPartModData(part)
end

local function squaresWithin(a, b, range)
	if not a or not b then return false end
	if a:getZ() ~= b:getZ() then return false end
	return math.max(math.abs(a:getX() - b:getX()), math.abs(a:getY() - b:getY())) <= range
end

-- A tanker is refuellable from a pump only while actually parked at it. Without this
-- the option would appear for a truck left anywhere in shouting distance of the player.
PropaneRefuel.tankerPumpRange = 4

function PropaneRefuel.isTankerAtPump(vehicle, pump)
	if not PropaneRefuel.getOption("AllowTankerRefill") then return false end
	if not vehicle or not pump then return false end
	return squaresWithin(vehicle:getSquare(), pump:getSquare(), PropaneRefuel.tankerPumpRange)
end

-- ---------------------------------------------------------------------------------
-- Industrial propane tanks (the large static ones already on the map)
--
-- These are unnamed scenery: the tile definitions give them no CustomName and no
-- property that marks them out, so they can only be matched on sprite name. Add the
-- names here to make them functional. Enable debug mode and right-click one to have
-- the mod print the sprite name to the console.
--
-- Deliberately not refillable -- a static industrial tank is a one-time find.
--
-- NOTE: while this table is empty the whole feature is dormant. isPropaneTankObject can
-- never return true, so no tank option appears anywhere and the four IndustrialTank
-- sandbox options have no effect. That is the current shipped state, not a fault.
-- ---------------------------------------------------------------------------------
PropaneRefuel.propaneTankSprites = {
	-- ["industry_02_XX"] = true,
}

local OBJECT_RESERVE_KEY = "PropaneRefuelObjectReserve"

function PropaneRefuel.isPropaneTankObject(object)
	if not PropaneRefuel.getOption("AllowIndustrialTanks") then return false end
	if not instanceof(object, "IsoObject") then return false end

	local sprite = object:getSprite()
	local name = sprite and sprite:getName()
	return name ~= nil and PropaneRefuel.propaneTankSprites[name] == true
end

function PropaneRefuel.getObjectCapacity()
	return math.max(0, PropaneRefuel.getOption("IndustrialTankCapacity"))
end

-- Seeded from position rather than ZombRand for the same reason the tankers are: every
-- client and the server have to arrive at the same figure without a sync round-trip.
-- Position is stable for a static object, so the same tank always starts the same.
local function seededObjectReserve(object)
	local minUnits = math.max(0, PropaneRefuel.getOption("IndustrialTankSpawnMin"))
	local maxUnits = math.max(0, PropaneRefuel.getOption("IndustrialTankSpawnMax"))
	maxUnits = math.min(maxUnits, PropaneRefuel.getObjectCapacity())
	if maxUnits <= minUnits then return math.min(minUnits, maxUnits) end

	local square = object:getSquare()
	if not square then return 0 end

	local key = square:getX() * 73856093 + square:getY() * 19349663 + square:getZ() * 83492791
	local bucket = seededBucket(key)
	return minUnits + math.floor(bucket * (maxUnits - minUnits + 1) / 1000)
end

function PropaneRefuel.getObjectReserve(object)
	if not object then return 0 end
	local modData = object:getModData()
	local stored = modData and modData[OBJECT_RESERVE_KEY]
	if stored == nil then return seededObjectReserve(object) end
	return math.max(0, stored)
end

function PropaneRefuel.setObjectReserve(object, amount)
	if not object then return end
	local modData = object:getModData()
	if not modData then return end

	modData[OBJECT_RESERVE_KEY] = math.min(math.max(0, amount), PropaneRefuel.getObjectCapacity())
	object:transmitModData()
end

-- How much of an item's charge is worth in pump units, used when pouring it into a tank.
-- Same scale as the refill cost, so a full propane tank deposits exactly what it costs
-- to fill one.
function PropaneRefuel.getItemUnits(item)
	local cost = PropaneRefuel.getPumpCost(item)
	if not cost then return 0 end
	return math.floor(item:getCurrentUsesFloat() * cost)
end

function PropaneRefuel.canDeposit(item)
	if not instanceof(item, "DrainableComboItem") then return false end
	if item:isBroken() then return false end
	return PropaneRefuel.getItemUnits(item) > 0
end

PropaneRefuel.pumpSearchRadius = 2

local function pumpOnSquare(square)
	local objects = square and square:getObjects()
	if not objects then return nil end
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		if PropaneRefuel.isGasPump(object) then
			return object
		end
	end
	return nil
end

function PropaneRefuel.findPump(worldobjects)
	local cell = getCell()
	if not cell then return nil end
	local radius = PropaneRefuel.pumpSearchRadius

	-- worldobjects usually holds several objects standing on the same tile, and this
	-- runs on every right-click anywhere in the world, so sweep each tile only once.
	local origins, seenOrigin = {}, {}
	for _, worldObject in ipairs(worldobjects) do
		local square = worldObject:getSquare()
		if square then
			local key = square:getX() .. "," .. square:getY() .. "," .. square:getZ()
			if not seenOrigin[key] then
				seenOrigin[key] = true
				origins[#origins + 1] = square
			end
		end
	end

	-- Clicked tiles first, so clicking a pump picks that pump and not a neighbour.
	for _, square in ipairs(origins) do
		local found = pumpOnSquare(square)
		if found then return found end
	end

	local visited = {}
	for _, origin in ipairs(origins) do
		local z = origin:getZ()
		for dy = -radius, radius do
			for dx = -radius, radius do
				local x, y = origin:getX() + dx, origin:getY() + dy
				local key = x .. "," .. y .. "," .. z
				if not visited[key] then
					visited[key] = true
					-- Unlike vanilla, a missing square skips rather than aborting the
					-- sweep -- an unloaded chunk edge should not hide a real pump.
					local found = pumpOnSquare(cell:getGridSquare(x, y, z))
					if found then return found end
				end
			end
		end
	end
	return nil
end

-- Static tanks are only ever the clicked object -- no sweeping, so right-clicking one
-- specific tank never picks up its neighbour.
function PropaneRefuel.findPropaneTankObject(worldobjects)
	for _, worldObject in ipairs(worldobjects) do
		local square = worldObject:getSquare()
		local objects = square and square:getObjects()
		if objects then
			for i = 0, objects:size() - 1 do
				local object = objects:get(i)
				if PropaneRefuel.isPropaneTankObject(object) then
					return object
				end
			end
		end
	end
	return nil
end

-- The large map tanks carry no name or property that identifies them, so the sprite
-- name is the only handle. This prints it for whatever you right-click, but only in
-- debug mode, so it costs normal players nothing.
function PropaneRefuel.reportSpriteNames(worldobjects, playerObj)
	if not isDebugEnabled() then return end

	for _, worldObject in ipairs(worldobjects) do
		local sprite = worldObject:getSprite()
		if sprite and sprite:getName() then
			print("PropaneRefuel debug: sprite = " .. tostring(sprite:getName()))
		end

		-- A vehicle is not a world sprite, so it has to be reported separately -- this
		-- is the only way to learn the script name a tanker actually uses.
		local square = worldObject:getSquare()
		local onTile = square and square:getVehicleContainer()
		if onTile then
			print("PropaneRefuel debug: vehicle on clicked tile = " .. tostring(onTile:getScriptName())
				.. "  id=" .. tostring(onTile:getId())
				.. "  matched=" .. tostring(PropaneRefuel.isPropaneVehicle(onTile))
				.. "  reserve=" .. tostring(PropaneRefuel.getVehicleReserve(onTile)))
		end
	end

	local near = playerObj and playerObj:getNearVehicle()
	if near then
		print("PropaneRefuel debug: nearest vehicle = " .. tostring(near:getScriptName())
			.. "  matched=" .. tostring(PropaneRefuel.isPropaneVehicle(near))
			.. "  hasGasTank=" .. tostring(near:getPartById("GasTank") ~= nil))
	end
end

-- Pairing a tanker with the pump it is parked at has to work from either click target:
-- the player may right-click the truck or the pump, and whichever they pick, the other
-- one has to be found. Without these the fill option only ever appeared in the rare case
-- where a single click found both.
function PropaneRefuel.findPumpNear(square, range)
	local cell = getCell()
	if not cell or not square then return nil end

	local z = square:getZ()
	for dy = -range, range do
		for dx = -range, range do
			local found = pumpOnSquare(cell:getGridSquare(square:getX() + dx, square:getY() + dy, z))
			if found then return found end
		end
	end
	return nil
end

function PropaneRefuel.findTankerNear(square, range)
	if not PropaneRefuel.getOption("AllowPropaneTruck") then return nil end
	local cell = getCell()
	if not cell or not square then return nil end

	-- Sweeps tiles rather than asking the cell for its vehicle list. IsoCell.getVehicles
	-- exists in the class but is only called from one vanilla debug UI, and it is not
	-- callable from Lua here -- it threw "tried to call nil" and took the whole context
	-- menu build down with it. getVehicleContainer is what ISVehicleMenu uses on the
	-- live path, so it is the one that can be relied on.
	local z = square:getZ()
	for dy = -range, range do
		for dx = -range, range do
			local gridSquare = cell:getGridSquare(square:getX() + dx, square:getY() + dy, z)
			local vehicle = gridSquare and gridSquare:getVehicleContainer()
			if PropaneRefuel.isPropaneVehicle(vehicle) then
				return vehicle
			end
		end
	end
	return nil
end

-- Used both as a fuel source in its own right and, when a pump is also present, to
-- decide whether a tanker is parked at that pump.
function PropaneRefuel.findPropaneVehicle(worldobjects, playerObj)
	if not PropaneRefuel.getOption("AllowPropaneTruck") then return nil end

	local clickedSquare, vehicleOnClickedTile
	for _, worldObject in ipairs(worldobjects) do
		local square = worldObject:getSquare()
		clickedSquare = clickedSquare or square
		local vehicle = square and square:getVehicleContainer()
		if vehicle then
			vehicleOnClickedTile = vehicleOnClickedTile or vehicle
			if PropaneRefuel.isPropaneVehicle(vehicle) then
				return vehicle
			end
		end
	end

	-- You clicked a vehicle, just not a propane one. Stop here rather than wandering off
	-- to a different truck: with two tankers parked together, falling through to
	-- getNearVehicle made opposite sides of the same vehicle report different reserves,
	-- because each side was silently resolving to a different truck.
	if vehicleOnClickedTile then return nil end

	-- Nothing clicked was a vehicle at all, so fall back to whatever the player is
	-- standing beside. Bounded to the clicked area, otherwise right-clicking something
	-- across the street while stood next to a tanker would offer propane from it.
	local near = playerObj and playerObj:getNearVehicle()
	if PropaneRefuel.isPropaneVehicle(near)
		and squaresWithin(near:getSquare(), clickedSquare, PropaneRefuel.tankerPumpRange)
	then
		return near
	end
	return nil
end
