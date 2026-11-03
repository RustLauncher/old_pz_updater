require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/PropaneRefuel_RefillAction"
require "TimedActions/PropaneRefuel_FillTankerAction"
require "TimedActions/PropaneRefuel_DepositAction"

-- Every silent exit reports itself under debug mode. "No option appeared" was costing
-- whole rounds of guesswork, because a missing menu entry looks identical whatever the
-- cause -- mod not actually loaded, no pump found, unreachable tile, or an error
-- swallowed by the pcall guarding the menu build.
--
-- Defined at the top on purpose: a Lua local is only visible to functions declared after
-- it, so putting this lower down would make it a nil global inside anything above.
local function bail(reason)
	if isDebugEnabled() then
		print("PropaneRefuel debug: menu not shown - " .. reason)
	end
	return nil
end

local function predicateRefillable(item)
	return PropaneRefuel.canRefill(item)
end

local function predicateDepositable(item)
	return PropaneRefuel.canDeposit(item)
end

local function onDeposit(worldobjects, tankObject, items, playerNum)
	local playerObj = getSpecificPlayer(playerNum)
	if not playerObj or not tankObject then return end

	local square = tankObject:getSquare()
	if not square then return end

	local playerInv = playerObj:getInventory()
	local walked = false

	for _, item in ipairs(items) do
		local container = item and item:getContainer()
		if container then
			if not walked then
				if not luautils.walkAdj(playerObj, square, true) then return end
				walked = true
			end

			local returnToContainer = container:isInCharacterInventory(playerObj) and container
			ISWorldObjectContextMenu.transferIfNeeded(playerObj, item)
			ISInventoryPaneContextMenu.equipWeapon(item, false, false, playerNum)
			ISTimedActionQueue.add(PropaneRefuelDepositAction:new(playerObj, tankObject, item))

			if returnToContainer and returnToContainer ~= playerInv then
				ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(playerObj, item, playerInv, returnToContainer))
			end
		end
	end
end

-- source is { pump = <IsoObject> } or { vehicle = <BaseVehicle> }.
local function onRefill(worldobjects, source, items, playerNum)
	local playerObj = getSpecificPlayer(playerNum)
	if not playerObj or not source then return end

	local sourceSquare = (source.pump and source.pump:getSquare())
		or (source.vehicle and source.vehicle:getSquare())
		or (source.tank and source.tank:getSquare())
	if not sourceSquare then return bail("source has no square") end

	local playerInv = playerObj:getInventory()
	local walked = false

	for _, item in ipairs(items) do
		-- An item can be dropped or eaten by another action between the menu opening
		-- and this running, which leaves it with no container.
		local container = item and item:getContainer()
		if container then
			if not walked then
				if not luautils.walkAdj(playerObj, sourceSquare, true) then
					return
				end
				walked = true
			end

			local returnToContainer = container:isInCharacterInventory(playerObj) and container
			ISWorldObjectContextMenu.transferIfNeeded(playerObj, item)
			ISInventoryPaneContextMenu.equipWeapon(item, false, false, playerNum)
			ISTimedActionQueue.add(PropaneRefuelAction:new(playerObj, source.pump, item, source.vehicle, source.tank))

			if returnToContainer and returnToContainer ~= playerInv then
				ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(playerObj, item, playerInv, returnToContainer))
			end
		end
	end
end

local function onFillTanker(worldobjects, fuelStation, vehicle, playerNum)
	local playerObj = getSpecificPlayer(playerNum)
	if not playerObj or not fuelStation or not vehicle then return end

	local square = fuelStation:getSquare()
	if not square or not luautils.walkAdj(playerObj, square, true) then return end

	ISTimedActionQueue.add(PropaneRefuelTankerAction:new(playerObj, fuelStation, vehicle))
end

-- Resolved at call time, not load time, so this does not depend on file load order.
local function text(key, fallback)
	return PropaneRefuel.getText(key, fallback)
end

-- "Propane Tank (52%)". The fill level used to live in a tooltip; inline keeps the
-- useful part with nothing popping up on hover. Empty items are skipped because the
-- item name already ends in "(Empty)" and "(Empty) (0%)" reads badly.
local function itemLabel(item)
	local percent = math.floor(item:getCurrentUsesFloat() * 100)
	if percent <= 0 then
		return item:getName()
	end
	return string.format("%s (%d%%)", item:getName(), percent)
end

local function buildMenu(playerNum, context, worldobjects)
	local playerObj = getSpecificPlayer(playerNum)
	if not playerObj or playerObj:isDead() then return bail("no living player") end

	PropaneRefuel.reportSpriteNames(worldobjects, playerObj)

	local fuelStation = PropaneRefuel.findPump(worldobjects)
	local tanker = PropaneRefuel.findPropaneVehicle(worldobjects, playerObj)
	local tankObject = PropaneRefuel.findPropaneTankObject(worldobjects)

	-- Whichever of the two was clicked, look for the other nearby. Clicking the pump
	-- rarely finds the truck (it is not on that tile and getNearVehicle needs you right
	-- beside it), and clicking the truck only sweeps 2 tiles for a pump -- so the fill
	-- option almost never appeared even with the truck parked at the pump.
	local range = PropaneRefuel.tankerPumpRange
	if fuelStation and not tanker then
		tanker = PropaneRefuel.findTankerNear(fuelStation:getSquare(), range)
	elseif tanker and not fuelStation then
		fuelStation = PropaneRefuel.findPumpNear(tanker:getSquare(), range)
	end

	-- A dead pump is not a source. Checked once here and reused below, so the menu can
	-- never offer and refuse on two different readings of the same pump.
	local pumpPowered = fuelStation ~= nil and PropaneRefuel.isPumpPowered(fuelStation)

	-- A clicked industrial tank wins outright: you asked for that tank specifically.
	-- Otherwise a WORKING pump first, so a tanker parked at a station never shadows the
	-- pump -- but an unpowered one steps aside instead, since a truck parked at a dark
	-- station is still perfectly usable and should not be hidden behind a pump that is not.
	local source
	if tankObject then
		source = { tank = tankObject }
	elseif fuelStation and pumpPowered then
		source = { pump = fuelStation }
	elseif tanker then
		-- Deliberately not requiring reserve > 0. A tanker can be seeded empty, and
		-- hiding the entry then makes a recognised truck look unsupported -- and leaves
		-- no way to tell "empty" apart from "this mod does not know about this truck".
		source = { vehicle = tanker }
	elseif fuelStation then
		-- Unpowered, and nothing else to fall back on. Kept as the source so the entry
		-- below can say why it is greyed out rather than there being no entry at all.
		source = { pump = fuelStation }
	end
	if not source then return bail("no pump or propane vehicle found near the click") end

	local sourceSquare = (source.pump and source.pump:getSquare())
		or (source.vehicle and source.vehicle:getSquare())
		or (source.tank and source.tank:getSquare())
	if not sourceSquare then return bail("source has no square") end
	if sourceSquare:getBuilding() ~= playerObj:getBuilding() then return bail("source is in a different building") end
	if not AdjacentFreeTileFinder.Find(sourceSquare, playerObj) then return bail("no free tile adjacent to the source") end

	-- Storing propane into a tank is offered before the "what can be filled" check
	-- below, since depositing needs full items and refilling needs unfilled ones.
	if source.tank then
		local reserve = math.floor(PropaneRefuel.getObjectReserve(source.tank))
		local capacity = math.floor(PropaneRefuel.getObjectCapacity())
		local depositable = playerObj:getInventory():getAllEvalRecurse(predicateDepositable)

		if not depositable:isEmpty() then
			local storeItems = {}
			for i = 0, depositable:size() - 1 do
				table.insert(storeItems, depositable:get(i))
			end
			table.sort(storeItems, function(a, b) return not string.sort(a:getName(), b:getName()) end)

			local storeLabel = string.format("%s (%d/%d)",
				text("ContextMenu_PropaneRefuel_Deposit", "Store Propane"), reserve, capacity)

			if reserve >= capacity then
				local full = context:addOption(storeLabel, worldobjects, nil)
				full.notAvailable = true
			else
				local storeOption = context:addOption(storeLabel, worldobjects, nil)
				local storeMenu = ISContextMenu:getNew(context)
				context:addSubMenu(storeOption, storeMenu)

				if #storeItems > 1 then
					storeMenu:addGetUpOption(text("ContextMenu_PropaneRefuel_StoreAll", "Store All"),
						worldobjects, onDeposit, source.tank, storeItems, playerNum)
				end
				for _, item in ipairs(storeItems) do
					local entry = storeMenu:addGetUpOption(itemLabel(item), worldobjects, onDeposit, source.tank, { item }, playerNum)
					entry.itemForTexture = item
				end
			end
		end
	end

	-- Filling the tanker itself needs nothing in your inventory, so it is offered
	-- before the item checks below can bail out. The level goes in the label because
	-- there is otherwise no way at all to see how much propane a truck is holding.
	if fuelStation and tanker and PropaneRefuel.isTankerAtPump(tanker, fuelStation) then
		-- Floored because the reserve comes back out of ModData, where an integer can
		-- return as a float, and "%d" on a fractional value is not safe.
		local reserve = math.floor(PropaneRefuel.getVehicleReserve(tanker))
		local capacity = math.floor(PropaneRefuel.getTankerCapacity())
		local fillLabel = string.format("%s (%d/%d)",
			text("ContextMenu_PropaneRefuel_FillTanker", "Fill Propane Tanker"), reserve, capacity)

		if reserve >= capacity then
			-- Greyed with the reason inline rather than hidden, so a full tanker does
			-- not look like the mod has stopped working.
			local full = context:addOption(fillLabel, worldobjects, nil)
			full.notAvailable = true
		elseif not pumpPowered then
			-- Same treatment, different reason: the truck has room, the pump just is not
			-- running. Saying so is what tells the player to go start the generator.
			local unpowered = context:addOption(
				fillLabel .. " (" .. text("ContextMenu_FuelPumpNoPower", "Fuel Pump has No Power") .. ")",
				worldobjects, nil)
			unpowered.notAvailable = true
		elseif fuelStation:getPipedFuelAmount() > 0 then
			context:addGetUpOption(fillLabel, worldobjects, onFillTanker, fuelStation, tanker, playerNum)
		end
	end

	local label = text("ContextMenu_PropaneRefuel_Refill", "Take Propane")

	-- Level goes on first, so every branch below reports it -- including the ones that
	-- grey the entry out. Seeing "Take Propane (140/200)" is what tells you the truck
	-- is recognised at all.
	if source.vehicle then
		local reserve = math.floor(PropaneRefuel.getVehicleReserve(source.vehicle))
		label = string.format("%s (%d/%d)", label, reserve, math.floor(PropaneRefuel.getTankerCapacity()))
		if reserve <= 0 then
			local empty = context:addOption(label, worldobjects, nil)
			empty.notAvailable = true
			return
		end
	elseif source.tank then
		local reserve = math.floor(PropaneRefuel.getObjectReserve(source.tank))
		label = string.format("%s (%d/%d)", label, reserve, math.floor(PropaneRefuel.getObjectCapacity()))
		-- Greyed for the same reason the tanker is: an empty tank offering a live "Take
		-- Propane" that quietly does nothing when clicked reads as the mod being broken.
		-- The "Store Propane" entry above is still there, which is the useful one here.
		if reserve <= 0 then
			local empty = context:addOption(label, worldobjects, nil)
			empty.notAvailable = true
			return
		end
	elseif source.pump and not pumpPowered then
		-- Only reachable with a dead pump and nothing else nearby to draw from. Greyed
		-- with the reason inline, exactly like the empty and full cases above, so a dark
		-- station reads as "switched off" and not as "this mod does nothing here". This
		-- is the whole fix from the player's side: before it, this entry was live and
		-- handed out propane from a pump the game itself would not sell petrol from.
		local unpowered = context:addOption(
			label .. " (" .. text("ContextMenu_FuelPumpNoPower", "Fuel Pump has No Power") .. ")",
			worldobjects, nil)
		unpowered.notAvailable = true
		return
	end

	local found = playerObj:getInventory():getAllEvalRecurse(predicateRefillable)
	if found:isEmpty() then
		-- Falling silent here made a working truck look unsupported: with nothing
		-- fillable in your bag there was no entry at all, and no way to tell that from
		-- the mod not recognising the vehicle. Vanilla shows "No Container for Fuel"
		-- in the same situation, so say the same thing.
		local blocked = context:addOption(
			label .. " (" .. text("ContextMenu_FuelPumpNoContainer", "No Container for Fuel") .. ")",
			worldobjects, nil)
		blocked.notAvailable = true
		return
	end

	local items = {}
	for i = 0, found:size() - 1 do
		table.insert(items, found:get(i))
	end
	table.sort(items, function(a, b) return not string.sort(a:getName(), b:getName()) end)

	-- Reasons go inline in the label, the way vanilla's BBQ menu does it, so nothing
	-- has to pop up on hover to explain a greyed-out entry.
	if playerObj:hasFullInventory() then
		local blocked = context:addOption(label .. " (" .. text("ContextMenu_FullInventory", "Inventory is full") .. ")", worldobjects, nil)
		blocked.notAvailable = true
		return
	end

	local option = context:addOption(label, worldobjects, nil)
	local subMenu = ISContextMenu:getNew(context)
	context:addSubMenu(option, subMenu)

	if #items > 1 then
		subMenu:addGetUpOption(text("ContextMenu_FillAll", "Fill All"), worldobjects, onRefill, source, items, playerNum)
	end

	for _, item in ipairs(items) do
		local itemOption = subMenu:addGetUpOption(itemLabel(item), worldobjects, onRefill, source, { item }, playerNum)
		itemOption.itemForTexture = item
	end
end

-- An error thrown from a context menu hook aborts ISWorldObjectContextMenu.createMenu,
-- which can take vanilla's options and other mods' options down with it. Contain ours.
local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
	if test then return end

	local ok, err = pcall(buildMenu, playerNum, context, worldobjects)
	if not ok then
		print("PropaneRefuel ERROR building context menu: " .. tostring(err))
	end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
