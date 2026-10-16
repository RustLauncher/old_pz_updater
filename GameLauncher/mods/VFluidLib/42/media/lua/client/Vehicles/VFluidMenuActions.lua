-- The menu's actions: container pickers and the handlers rows invoke. A handler leaves the
-- vehicle, resolves the container, walks, equips, then queues - skipping a step would start
-- an action the player is nowhere near.

VFluidMenu = VFluidMenu or {}

local V2V_RANGE_DEFAULT = 6

local function v2vRange()
	local sv = SandboxVars and SandboxVars.VFluidLib
	local n = sv and sv.TransferRange
	if type(n) == "number" and n > 0 then return n end
	return V2V_RANGE_DEFAULT
end

local function loadedVehicles()
	local out = {}
	pcall(function()
		local vm = VehicleManager and VehicleManager.instance
		local list = vm and vm:getVehicles()
		for i = 0, (list and list:size() or 0) - 1 do out[#out + 1] = list:get(i) end
	end)
	if #out > 0 then return out end
	pcall(function()
		local cell = getWorld() and getWorld():getCell()
		local set = cell and cell:getVehicles()
		local it = set and set:iterator()
		while it and it:hasNext() do out[#out + 1] = it:next() end
	end)
	return out
end

function VFluidMenu.transferFilter(vehicle, part, axis, tankEp)
	if not tankEp then return nil end
	return function(item, itemEp, wantSource)
		local fluid = wantSource and VFluid.itemFluidName(item)
			or VFluid.primaryFluidOf(vehicle, part, axis)
		if not fluid then return false end
		local src = wantSource and itemEp or tankEp
		local dst = wantSource and tankEp or itemEp
		return (VFluid.canTransfer(src, dst, fluid)) and true or false
	end
end

function VFluidMenu.equippedHandContainer(playerObj, axis, wantSource, validate)
	if not playerObj then return nil end
	local function usable(item, allowDevice)
		if not item then return nil end
		if not allowDevice and VFluid.isUnitDevice(item) then return nil end
		local ep = VFluid.itemEndpoint(item, axis)
		if not ep then return nil end
		if wantSource then
			if ep.get() <= 0 then return nil end
		elseif ep.free() <= 0 then
			return nil
		end
		if validate and not validate(item, ep, wantSource) then return nil end
		return ep
	end
	-- Two passes: a vessel is taken over a device, so a torch in hand can never hide a bottle.
	-- The device is still reachable on the second pass, which is what keeps a torch drainable.
	local primary = playerObj:getPrimaryHandItem()
	local secondary = playerObj.getSecondaryHandItem and playerObj:getSecondaryHandItem()
	for _, allowDevice in ipairs({ false, true }) do
		local ep = usable(primary, allowDevice)
		if ep then return primary, ep end
		if secondary and secondary ~= primary then
			ep = usable(secondary, allowDevice)
			if ep then return secondary, ep end
		end
	end
	return nil
end

function VFluidMenu.allHandContainers(playerObj, axis, wantSource, anyAxis)
	local out = {}
	local inv = playerObj and playerObj:getInventory()
	if not inv or not inv.getAllEvalRecurse then return out end
	local function onAxis(it)
		local ep = VFluid.itemEndpoint(it, axis)
		if not ep then return nil end
		if not anyAxis and axis and ep.axis and ep.axis.id ~= axis.id then return nil end
		if anyAxis and ep.axis and ep.axis.kind ~= "fluid" then return nil end
		return ep
	end
	local ok, items = pcall(function()
		return inv:getAllEvalRecurse(function(it)
			local ep = onAxis(it)
			if not ep then return false end
			if wantSource then return ep.get() > 0 end
			return ep.free() > 0
		end)
	end)
	if not ok or not items then return out end
	for i = 0, items:size() - 1 do
		local it = items:get(i)
		out[#out + 1] = { item = it, ep = VFluid.itemEndpoint(it, axis), idx = i }
	end
	table.sort(out, function(a, b)
		local av, bv = a.ep.get(), b.ep.get()
		if av ~= bv then
			if wantSource then return av > bv end
			return av < bv
		end
		return a.idx < b.idx
	end)
	return out
end

function VFluidMenu.pickTorch(playerObj, axis)
	if not playerObj or not axis or axis.kind ~= "unit" then return nil end
	local inv = playerObj:getInventory()
	if not inv then return nil end
	local function usable(it)
		if not it or it:getFullType() ~= "Base.BlowTorch" then return nil end
		local ep = VFluid.itemEndpoint(it, axis)
		if not ep or ep.free() <= 0 then return nil end
		return ep
	end
	local equipped = playerObj:getPrimaryHandItem()
	local ep = usable(equipped)
	if ep then return equipped, ep end
	local ok, items = pcall(function()
		return inv:getAllEvalRecurse(function(it) return usable(it) ~= nil end)
	end)
	if not ok or not items then return nil end
	local best, bestEp, bestAmt
	for i = 0, items:size() - 1 do
		local it = items:get(i)
		local e = usable(it)
		if e and (bestAmt == nil or e.get() < bestAmt) then best, bestEp, bestAmt = it, e, e.get() end
	end
	if not best then return nil end
	return best, bestEp
end

-- The radial carries ONE container per direction, so what wins matters. A vessel always beats a
-- device: a welding torch in hand must never take the slot a propane bottle needs. The device is
-- still picked when nothing else qualifies, which is what keeps a torch emptiable into a tank.
function VFluidMenu.pickHandContainer(playerObj, axis, wantSource, validate)
	local equipped = playerObj:getPrimaryHandItem()
	local function consider(item, allowDevice)
		if not allowDevice and VFluid.isUnitDevice(item) then return nil end
		local ep = VFluid.itemEndpoint(item, axis)
		if not ep then return nil end
		if wantSource then
			if ep.get() <= 0 then return nil end
			if validate and not validate(item, ep, true) then return nil end
			return ep.get(), ep
		end
		if ep.free() <= 0 then return nil end
		if validate and not validate(item, ep, false) then return nil end
		return -ep.get(), ep
	end
	local inv = playerObj:getInventory()
	local items = inv and inv:getItems()
	for _, allowDevice in ipairs({ false, true }) do
		if equipped then
			local score, ep = consider(equipped, allowDevice)
			if score then return equipped, ep end
		end
		local best, bestScore = nil, nil
		for i = 0, (items and items:size() or 0) - 1 do
			local item = items:get(i)
			local score = consider(item, allowDevice)
			if score and (bestScore == nil or score > bestScore) then best, bestScore = item, score end
		end
		if best then return best, VFluid.itemEndpoint(best, axis) end
	end
	return nil
end

function VFluidMenu.onRefuel(playerObj, sourcePart, destPart, fluidName)
	if playerObj:getVehicle() then ISVehicleMenu.onExit(playerObj) end
	local destVehicle = destPart:getVehicle()
	ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, destVehicle, destPart:getArea()))
	ISTimedActionQueue.add(VFluidTransferAction:new(playerObj, sourcePart, nil, "withdraw", fluidName, destPart))
end

local function isFuelDest(dest)
	return dest ~= nil and dest.kind == "supply"
end

function VFluidMenu.sourcesInReach(playerObj, vehicle, dest)
	local out = {}
	local wantAxis = isFuelDest(dest) and "fuel" or (dest.axis and dest.axis.id)
	if not wantAxis then return out end

	local function collect(v, label)
		local eps = VFluid.vehicleEndpoints(v)
		for i = 1, #eps do
			local ep = eps[i]
			if ep.kind == "tank" and ep ~= dest and ep.part ~= dest.part
					and ep.axis and ep.axis.id == wantAxis and ep.get() > 0 then
				out[#out + 1] = { ep = ep, part = ep.part, label = label, vehicle = v }
			end
		end
	end

	collect(vehicle, getText("IGUI_VFluid_ThisVehicle"))

	local towing, towedBy = vehicle:getVehicleTowing(), vehicle:getVehicleTowedBy()
	local dx0, dy0, range = vehicle:getX(), vehicle:getY(), v2vRange()
	local hitchedOk = VFluid.hitchedRefuelAllowed()
	local all = loadedVehicles()
	for i = 1, #all do
		local v = all[i]
		local hitchedToUs = (v == towing or v == towedBy)
		local barred = hitchedToUs and isFuelDest(dest) and not hitchedOk
		if v and v ~= vehicle and not v:isRemovedFromWorld() and v:getSquare() and not barred then
			local inReach = hitchedToUs and hitchedOk
			if not inReach then
				local dx, dy = v:getX() - dx0, v:getY() - dy0
				inReach = math.sqrt(dx * dx + dy * dy) <= range
			end
			if inReach then collect(v, VFluidMenu.vehicleLabel(v)) end
		end
	end
	return out
end

local function betterSupply(cand, cur)
	if not cur then return true end
	if cand.usable ~= cur.usable then return cand.usable end
	if cand.rank ~= (cur.rank or 0) then return cand.rank > (cur.rank or 0) end
	if cand.powered ~= cur.powered then return cand.powered end
	return cand.ep.get() > cur.ep.get()
end

local function supplyUsable(ep, sq)
	local needsPower = ep.needsPower
	if needsPower == nil then needsPower = true end
	local powered = ep.powered
	if powered == nil then powered = sq and sq.haveElectricity and sq:haveElectricity() or false end
	powered = powered and true or false
	return (not needsPower) or powered, powered, needsPower
end

function VFluidMenu.supplyTargets(playerObj, axis, fluidName)
	local out = {}
	local cell = getWorld() and getWorld():getCell()
	if not cell then return out end
	local px, py, pz = math.floor(playerObj:getX()), math.floor(playerObj:getY()), math.floor(playerObj:getZ())
	local range = 6
	for dx = -range, range do
		for dy = -range, range do
			local sq = cell:getGridSquare(px + dx, py + dy, pz)
			if sq then
				local wet = VFluid.naturalWaterEndpoint(sq, axis)
				if wet then
					local cand = { ep = wet, powered = false, label = wet.label,
						rank = wet.supplyRank or 0 }
					local cur = out[1]
					if not cur or cand.rank > (cur.rank or 0)
							or (cand.rank == (cur.rank or 0)
								and not cur.powered and cur.ep.get() < math.huge) then
						out[1] = cand
					end
				end
				local objs = sq:getObjects()
				for i = 0, objs:size() - 1 do
					local ep = VFluid.worldEndpoint(objs:get(i), axis, playerObj)
					if ep and ep.sourceOnly and ep.get() > 0 then
						local powered = ep.powered
						if powered == nil then
							powered = sq.haveElectricity and sq:haveElectricity()
						end
						local cand = { ep = ep, powered = powered and true or false,
							label = tostring(ep.label), rank = ep.supplyRank or 0 }
						local cur = out[1]
						if not cur or cand.rank > (cur.rank or 0)
								or (cand.rank == (cur.rank or 0)
									and ((cand.powered and not cur.powered)
										or (cand.powered == cur.powered and ep.get() > cur.ep.get()))) then
							out[1] = cand
						end
					end
				end
			end
		end
	end
	return out
end

local function supplySquareOf(supplyEp)
	local h = supplyEp and supplyEp.holder
	if not h then return nil end
	local sq = h
	if h.getSquare then
		local ok, s2 = pcall(function() return h:getSquare() end)
		if ok and s2 then sq = s2 end
	end
	if not sq or not sq.getX then return nil end
	return sq:getX(), sq:getY(), sq:getZ()
end

function VFluidMenu.onFillFromSupply(playerObj, part, supplyEp, fluidName)
	if playerObj:getVehicle() then ISVehicleMenu.onExit(playerObj) end
	local vehicle = part:getVehicle()
	ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, vehicle, part:getArea()))
	ISTimedActionQueue.add(VFluidTransferAction:new(playerObj, part, nil, "supply", fluidName, nil,
		supplyEp, supplySquareOf(supplyEp)))
end

function VFluidMenu.onDrain(playerObj, part, fluidName)
	if playerObj:getVehicle() then ISVehicleMenu.onExit(playerObj) end
	local vehicle = part:getVehicle()
	ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, vehicle, part:getArea()))
	ISTimedActionQueue.add(VFluidTransferAction:new(playerObj, part, nil, "drain", fluidName))
end

function VFluidMenu.onDrink(playerObj, part)
	if playerObj:getVehicle() then ISVehicleMenu.onExit(playerObj) end
	local vehicle = part:getVehicle()
	ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, vehicle, part:getArea()))
	ISTimedActionQueue.add(VFluidTransferAction:new(playerObj, part, nil, "drink", nil))
end

function VFluidMenu.needsWashing(item)
	if not item then return false end
	if instanceof(item, "Clothing") or instanceof(item, "InventoryContainer") then
		local covered = BloodClothingType.getCoveredParts(item:getBloodClothingType())
		if covered then
			for i = 0, covered:size() - 1 do
				if item:getBlood(covered:get(i)) > 0 then return true end
			end
		end
		local ok, dirt = pcall(function() return item:getDirtiness() end)
		if ok and dirt and dirt > 0 then return true end
		return false
	end
	local ok, blood = pcall(function() return item:getBloodLevel() end)
	return ok and blood ~= nil and blood > 0
end

function VFluidMenu.wornClothing(playerObj)
	local out = {}
	local worn = playerObj and playerObj.getWornItems and playerObj:getWornItems()
	for i = 0, (worn and worn:size() or 0) - 1 do
		local entry = worn:get(i)
		local item = entry and entry.getItem and entry:getItem()
		if item and VFluidMenu.needsWashing(item) then out[#out + 1] = item end
	end
	return out
end

local function delegateWash(playerObj, part, call)
	local vehicle = part:getVehicle()
	local ep = VFluid.transferEndpointFor(vehicle, part)
	if not ep or not ISWorldObjectContextMenu then return end
	local sink = VFluidWashAction.makeSink(vehicle, part, ep, playerObj)

	ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, vehicle, part:getArea()))
	ISTimedActionQueue.add(VFluidThenAction:new(playerObj, function()
		local q = ISTimedActionQueue.getTimedActionQueue(playerObj)
		local before = (q and q.queue) and #q.queue or 0
		call(sink)
		if not (q and q.queue) then return end
		for i = before + 1, #q.queue do
			local act = q.queue[i]
			if act and act.update and act.sink == sink then
				local orig = act.update
				act.vehicle = vehicle
				act.update = function(self)
					local real = self.sink
					self.sink = self.vehicle
					local ok = pcall(orig, self)
					self.sink = real
					if not ok and self.vehicle then
						self.character:faceThisObjectAlt(self.vehicle)
					end
				end
			end
		end
	end))
end
function VFluidMenu.onWash(playerObj, part)
	if playerObj:getVehicle() then ISVehicleMenu.onExit(playerObj) end
	delegateWash(playerObj, part, function(sink)
		local soaps = playerObj:getInventory():getSoapList(nil, false)
		ISWorldObjectContextMenu.onWashYourself(playerObj, sink, soaps)
	end)
end

function VFluidMenu.onWashClothing(playerObj, part, item)
	if playerObj:getVehicle() then ISVehicleMenu.onExit(playerObj) end
	local list = item and { item } or VFluidMenu.wornClothing(playerObj)
	if #list == 0 then return end
	delegateWash(playerObj, part, function(sink)
		local soaps = playerObj:getInventory():getSoapList(nil, false)
		ISWorldObjectContextMenu.onWashClothing(playerObj, sink, soaps, list, nil)
	end)
end

function VFluidMenu.onTransfer(playerObj, part, direction, fluidName, chosenItem)
	if playerObj:getVehicle() then ISVehicleMenu.onExit(playerObj) end
	local vehicle = part:getVehicle()
	local nearEp = VFluid.transferEndpointFor(vehicle, part)
	if not nearEp then return end
	local axis = nearEp.axis
	if not axis then return end
	local item = chosenItem
	if item then
		if not VFluid.itemEndpoint(item, axis) then return end
	else
		item = VFluidMenu.pickHandContainer(playerObj, axis, direction == "deposit")
	end
	if not item then return end

	ISVehiclePartMenu.toPlayerInventory(playerObj, item)
	ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, vehicle, part:getArea()))
	ISInventoryPaneContextMenu.equipWeapon(item, true, false, playerObj:getPlayerNum())
	ISTimedActionQueue.add(VFluidTransferAction:new(playerObj, part, item, direction, fluidName))
end
