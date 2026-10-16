require "TimedActions/ISBaseTimedAction"

local BCBConfig = require("BetterCorpseBurning/config")

local BCB = {}

local function isUsableFire(item)
	if item == nil then return false end
	-- Vanilla method: getCurrentUsesFloat() works on DrainableComboItem
	if instanceof(item, "DrainableComboItem") and item.getCurrentUsesFloat then
		local ok, val = pcall(item.getCurrentUsesFloat, item)
		if ok and val ~= nil then
			return val > 0
		end
	end
	-- Fallback: try getDrainableUsesLeft
	if item.getDrainableUsesLeft then
		local ok1, r1 = pcall(item.getDrainableUsesLeft, item)
		if ok1 and r1 ~= nil then
			return r1 > 0
		end
	end
	-- Fallback: try getUsedDelta
	if item.getUsedDelta then
		local ok2, r2 = pcall(item.getUsedDelta, item)
		if ok2 and r2 ~= nil then
			return r2 > 0
		end
	end
	return true
end

local function isCorpseOnFire(corpse)
	if not corpse then return false end
	local square = corpse:getSquare()
	if square then
		local ok, burning = pcall(square.has, square, IsoFlagType.burning)
		if ok and burning then return true end
	end
	if corpse.isOnFire and corpse:isOnFire() then return true end
	return false
end

local function isFavoriteFireItem(item)
	if item == nil or item.isFavorite == nil then return false end
	local ok, favorite = pcall(item.isFavorite, item)
	return ok and favorite == true
end

local function findFireItem(character)
	local inv = character:getInventory()
	local favoriteItem = nil
	local function consider(item)
		if not isUsableFire(item) then return nil end
		if isFavoriteFireItem(item) then
			favoriteItem = favoriteItem or item
			return nil
		end
		return item
	end

	local ok, tagged = pcall(inv.getAllTagRecurse, inv, ItemTag.START_FIRE, ArrayList.new())
	if ok and tagged then
		for i = 0, tagged:size() - 1 do
			local item = consider(tagged:get(i))
			if item then return item end
		end
	end
	for _, typeName in ipairs({"Lighter", "LighterBBQ", "Lighter_Battery", "LighterDisposable", "Matches", "Matchbox"}) do
		local items = inv:getAllTypeRecurse(typeName, ArrayList.new())
		if items then
			for i = 0, items:size() - 1 do
				local item = consider(items:get(i))
				if item then return item end
			end
		end
	end
	return favoriteItem
end

BCB.findFireItem = findFireItem

function BCB.isIndoorSquare(square)
	if not square then return false end
	local ok, room = pcall(square.getRoom, square)
	return ok and room ~= nil
end

-- Search an inventory tree, including fuel containers inside bags.
-- Keep the helper item-based so the returned item can still be consumed
-- directly with FluidContainer:adjustAmount().
local function findFluidInItems(items, fluidType, minimumAmount)
	if not items then return nil end
	for i = 0, items:size() - 1 do
		local item = items:get(i)
		local fc = item.getFluidContainer and item:getFluidContainer()
		if fc and fc:contains(fluidType) and fc:getAmount() >= minimumAmount - 0.001 then
			return item
		end

		if instanceof(item, "InventoryContainer") and item.getInventory then
			local nested = findFluidInItems(item:getInventory():getItems(), fluidType, minimumAmount)
			if nested then return nested end
		end
	end
	return nil
end

local function findPetrolItem(character)
	local inv = character:getInventory()
	local need = BCBConfig.PETROL_PER_BURN or 0.1
	return findFluidInItems(inv:getItems(), Fluid.Petrol, need)
end

BCB.findPetrolItem = findPetrolItem

--- Find an item with a specific fluid type and enough amount
local function findFuelByFluid(character, fluidType, minAmount)
	local inv = character:getInventory()
	return findFluidInItems(inv:getItems(), fluidType, minAmount)
end

--- Alcohol item type names in PZ B42 (searched by item name, not fluid type)
local ALCOHOL_ITEM_NAMES = {
	"BeerBottle", "BeerCan", "BeerImported",
	"Brandy", "Champagne", "Cider",
	"Gin", "Port", "Rum", "Scotch", "Sherry",
	"Tequila", "Vodka", "Whiskey",
	"Wine", "Wine2", "WineOpen", "Wine2Open", "WineAged", "WineScrewtop",
}

--- Find alcohol item (any alcoholic beverage)
local function findAlcoholItem(character)
	local inv = character:getInventory()
	local minAmount = BCBConfig.ALCOHOL_PER_BURN or 0.2
	-- First try fluid-based search (for fluid types that exist as globals)
	for _, fluidName in ipairs({"Beer", "Vodka", "Whiskey", "Wine", "Gin", "Rum", "Tequila", "Brandy", "Scotch", "Champagne", "Cider", "Sherry", "Port", "Mead", "CoffeeLiqueur", "Curacao", "Grenadine", "Vermouth"}) do
		local fluidType = Fluid[fluidName]
		if fluidType then
			local ok, item = pcall(findFuelByFluid, character, fluidType, minAmount)
			if ok and item then return item end
		end
	end
	-- Fallback: search by item type name
	for _, itemName in ipairs(ALCOHOL_ITEM_NAMES) do
		local items = inv:getAllTypeRecurse(itemName, ArrayList.new())
		if items then
			for i = 0, items:size() - 1 do
				local item = items:get(i)
				local fc = item.getFluidContainer and item:getFluidContainer()
				if fc and fc:getAmount() >= minAmount - 0.001 then
					return item
				end
			end
		end
	end
	return nil
end

BCB.findAlcoholItem = findAlcoholItem

--- Find cologne item
local function findCologneItem(character)
	local inv = character:getInventory()
	local minAmount = BCBConfig.COLOGNE_PER_BURN or 0.05
	-- Try fluid-based search first (Fluid.Cologne)
	local ok, byFluid = pcall(findFuelByFluid, character, Fluid.Cologne, minAmount)
	if ok and byFluid then return byFluid end
	-- Fallback: search by item type name
	local items = inv:getAllTypeRecurse("Cologne", ArrayList.new())
	if items then
		for i = 0, items:size() - 1 do
			local item = items:get(i)
			local fc = item.getFluidContainer and item:getFluidContainer()
			if fc and fc:getAmount() >= minAmount - 0.001 then
				return item
			end
		end
	end
	return nil
end

BCB.findCologneItem = findCologneItem

--- Consume fuel from a fluid container
local function consumeFuel(item, amount)
	if not item then return end
	local fc = item.getFluidContainer and item:getFluidContainer()
	if fc then
		fc:adjustAmount(fc:getAmount() - amount)
	end
end

function BCB.findCorpsesOnSquare(square)
	local found = {}
	if not square then return found end
	local okObjs, objects = pcall(square.getStaticMovingObjects, square)
	if not okObjs or not objects then return found end
	for i = 0, objects:size() - 1 do
		local obj = objects:get(i)
		if instanceof(obj, "IsoDeadBody") and not isCorpseOnFire(obj) then
			found[#found + 1] = obj
		end
	end
	return found
end

------------------------------------------------------------
-- Burn a single corpse (fire spread handled by server).
------------------------------------------------------------
local ISBCBBurnAction = ISBaseTimedAction:derive("BCB_ISBCBBurnAction")

--- Check if at least one required fuel type is available (OR logic)
local function hasRequiredFuel(character)
	local hasPetrol = BCBConfig.NEED_PETROL and BCB.findPetrolItem(character) ~= nil
	local hasAlcohol = BCBConfig.NEED_ALCOHOL and BCB.findAlcoholItem(character) ~= nil
	local hasCologne = BCBConfig.NEED_COLOGNE and BCB.findCologneItem(character) ~= nil
	-- If no fuel type is required, always OK
	if not BCBConfig.NEED_PETROL and not BCBConfig.NEED_ALCOHOL and not BCBConfig.NEED_COLOGNE then
		return true
	end
	-- At least one required fuel type must be available
	return hasPetrol or hasAlcohol or hasCologne
end

function ISBCBBurnAction:isValid()
	if self.corpse == nil then return false end
	if self.corpse:getStaticMovingObjectIndex() < 0 then return false end
	if isCorpseOnFire(self.corpse) then return false end
	if BCB.findFireItem(self.character) == nil then return false end
	if not hasRequiredFuel(self.character) then return false end
	if not BCBConfig.ALLOW_INDOOR and BCB.isIndoorSquare(self.corpse:getSquare()) then return false end
	return true
end

--- Ortak yakma mantığı, idempotent: hem update() hem complete() çağırır.
--- Neden: Java zamanlayıcı gerçek zamanlıdır (FPS bağımsız), update sayacı
--- frame bazlıdır. Düşük FPS'de Java önce davranıp perform()+complete()
--- çağırır; yüksek FPS'de update sayacı önce dolar. Hangi yol önce
--- gelirse gelsin tek kez çalışır (bcbDone guard).
local function doBurn(self)
	if self.bcbDone then return end
	self.bcbDone = true

	-- Consume fire item
	local fire = BCB.findFireItem(self.character)
	if fire then
		local uses = math.max(0, tonumber(BCBConfig.FIRE_USES_PER_CORPSE) or 1)
		for _ = 1, uses do
			if not isUsableFire(fire) then
				fire = BCB.findFireItem(self.character)
				if not fire then break end
			end
			pcall(fire.UseAndSync, fire)
		end
	end

	-- Consume fuel (any available type, OR logic)
	if BCBConfig.NEED_PETROL then
		local fuel = BCB.findPetrolItem(self.character)
		if fuel then consumeFuel(fuel, BCBConfig.PETROL_PER_BURN or 0.1)
		elseif BCBConfig.NEED_ALCOHOL then
			local fuel2 = BCB.findAlcoholItem(self.character)
			if fuel2 then consumeFuel(fuel2, BCBConfig.ALCOHOL_PER_BURN or 0.2)
			elseif BCBConfig.NEED_COLOGNE then
				local fuel3 = BCB.findCologneItem(self.character)
				if fuel3 then consumeFuel(fuel3, BCBConfig.COLOGNE_PER_BURN or 0.05) end
			end
		end
	elseif BCBConfig.NEED_ALCOHOL then
		local fuel = BCB.findAlcoholItem(self.character)
		if fuel then consumeFuel(fuel, BCBConfig.ALCOHOL_PER_BURN or 0.2)
		elseif BCBConfig.NEED_COLOGNE then
			local fuel2 = BCB.findCologneItem(self.character)
			if fuel2 then consumeFuel(fuel2, BCBConfig.COLOGNE_PER_BURN or 0.05) end
		end
	elseif BCBConfig.NEED_COLOGNE then
	local fuel = BCB.findCologneItem(self.character)
	if fuel then consumeFuel(fuel, BCBConfig.COLOGNE_PER_BURN or 0.05) end
	end

	-- Client-side burn visual
	pcall(self.character.burnCorpse, self.character, self.corpse)

	-- Send to server for fire spread
	local square = self.corpse:getSquare()
	if square then
		sendClientCommand(self.character, "BCB", "burnCorpse", {
			x = square:getX(),
			y = square:getY(),
			z = square:getZ(),
			spreadRadius = BCBConfig.FIRE_SPREAD_RADIUS,
		})
	end
end

function ISBCBBurnAction:update()
	if not self._bcbLogged then
		self._bcbLogged = true
		print("[BCB] update() first call, maxTime=" .. tostring(self.maxTime) .. ", instant=" .. tostring(self.character:isTimedActionInstant()))
	end
	self.character:faceThisObject(self.corpse)

	-- Progress bar (vanilla ISBurnCorpseAction deseni)
	local fire = BCB.findFireItem(self.character)
	if fire and fire.setJobDelta then
		pcall(fire.setJobDelta, fire, self:getJobDelta())
	end

	-- Build 42 multiplayer: perform() triggers server validation which rejects
	-- custom actions. Use our own frame counter instead of self.current.
	self.bcbFrame = (self.bcbFrame or 0) + 1

	-- Java ilerlemesi FPS bağımsızdır (host co-op'ta frame sayacı yetmeyebilir).
	-- Hangisi önce dolarsa doBurn çalışır, guard çift çalışmayı engeller.
	local okJd, jd = pcall(self.getJobDelta, self)
	local jdDone = okJd and jd ~= nil and tonumber(jd) ~= nil and tonumber(jd) >= 1

	if self.bcbFrame >= self.maxTime or jdDone then
		doBurn(self)

		-- MP: stop from update() because server validation rejects custom actions
		-- SP: action system also calls stop() after perform(), bcbDone guard prevents double-work
		ISBaseTimedAction.stop(self)
	end
end

function ISBCBBurnAction:start()
	self:setActionAnim(CharacterActionAnims.Pour)
	local fire = BCB.findFireItem(self.character)
	if fire then
		pcall(self.setOverrideHandModels, self, fire:getStaticModel(), nil)
		if fire.setJobType then
			pcall(fire.setJobType, fire, getText("IGUI_JobType_Burn"))
		end
		if fire.setJobDelta then
			pcall(fire.setJobDelta, fire, 0.0)
		end
	else
		print("[BCB] WARN: start() no fire item found")
	end
end

function ISBCBBurnAction:stop()
	ISBaseTimedAction.stop(self)
	local fire = BCB.findFireItem(self.character)
	if fire and fire.setJobDelta then
		pcall(fire.setJobDelta, fire, 0.0)
	end
end

-- All burn logic lives in update(). perform/complete are vanilla-compatible stubs.
function ISBCBBurnAction:perform()
	ISBaseTimedAction.perform(self)
end

function ISBCBBurnAction:complete()
	-- Vanilla yolu: düşük FPS'de Java zamanlayıcı update sayacından önce
	-- davranıp perform()+complete() çağırır. doBurn guard sayesinde çift çalışmaz.
	doBurn(self)
	return true
end

function ISBCBBurnAction:getDuration()
	if self.character:isTimedActionInstant() then
		return 50
	end
	return BCBConfig.TIME_PER_CORPSE or 110
end

function ISBCBBurnAction:new(character, corpse)
	local o = ISBaseTimedAction.new(self, character)
	o.corpse = corpse
	o.maxTime = o:getDuration()
	return o
end

if ISBCBBurnAction.Type then
	_G[ISBCBBurnAction.Type] = ISBCBBurnAction
end

BCB.BurnAction = ISBCBBurnAction

return BCB
