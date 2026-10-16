-- The transfer itself, litre-quantum steps: each step re-validates against the same rules
-- the menu used, moves both endpoints, syncs both machines, and stops cleanly when either
-- side fills, empties, or leaves.

require "TimedActions/ISBaseTimedAction"

VFluid = VFluid or {}

VFluidTransferAction = ISBaseTimedAction:derive("VFluidTransferAction")

function VFluidTransferAction:getPart()
	return self.vehicle and self.vehicle:getPartById(self.partId)
end

VFluid = VFluid or {}
VFluid.debugSupply = VFluid.debugSupply or false

-- EXPERIMENT SCAFFOLDING, default off: with it on the SERVER alone writes and the client only
-- animates, which is the shape every vanilla fluid action uses. Off is the shipped behaviour and
-- nothing below changes. Delete this switch and make the server path unconditional once the
-- question it exists to answer is settled.
if VFluid.serverOnlyTransfer == nil then VFluid.serverOnlyTransfer = false end

local function dbg(...)
	if not VFluid.debugSupply then return end
	local who = isServer() and "SERVER" or (isClient() and "CLIENT" or "SP")
	local parts = { "[VFluidSupply " .. who .. "]" }
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	print(table.concat(parts, " "))
end

function VFluidTransferAction:makeEndpoints()
	dbg("makeEndpoints dir=", self.direction, "supplyEp=", self.supplyEp ~= nil,
		"supplyX=", self.supplyX, "item=", self.item ~= nil, "targetPart=", self.targetPart ~= nil)
	local part = self:getPart()
	if not part then return false end
	local tankEp = VFluid.transferEndpointFor(self.vehicle, part)
	if not tankEp then return false end

	if self.direction == "drain" then
		self.axis = tankEp.axis
		self.src, self.dst = tankEp, VFluid.voidEndpoint(tankEp.axis)
		return true
	end

	if self.direction == "drink" then
		self.axis = tankEp.axis
		local vehicle, axis = self.vehicle, tankEp.axis
		local mixtureOf = function()
			local part = self:getPart()
			return part and VFluid.ledger(vehicle, part, axis) or nil
		end
		self.src, self.dst = tankEp, VFluid.mouthEndpoint(self.character, axis, mixtureOf)
		return self.dst ~= nil
	end

	local otherEp
	if not self.supplyEp and self.supplyX then
		self.supplyEp = VFluid.supplyAt(self.supplyX, self.supplyY, self.supplyZ,
			tankEp.axis, self.character)
	end
	if not self.supplyEp and self.direction == "supply" then
		self.supplyEp = VFluid.bestSupplyNear(self.character, tankEp.axis, 6)
		dbg("rebuilt supply ->", self.supplyEp and self.supplyEp.label or "NOTHING FOUND")
	end
	if self.supplyEp then
		otherEp = self.supplyEp
	elseif self.item then
		otherEp = VFluid.itemEndpoint(self.item, tankEp.axis)
	elseif self.targetPart then
		local tv = self.targetPart:getVehicle()
		local teps = VFluid.vehicleEndpoints(tv)
		for i = 1, #teps do
			if teps[i].part == self.targetPart then otherEp = teps[i] break end
		end
	end
	if not otherEp then return false end

	self.axis = tankEp.axis
	dbg("resolved otherEp=", otherEp and (otherEp.label or otherEp.kind) or "NIL")
	if self.direction == "deposit" or self.direction == "supply" then
		self.src, self.dst = otherEp, tankEp
	else
		self.src, self.dst = tankEp, otherEp
	end
	return true
end

function VFluidTransferAction:isValid()
	if self.item then
		if isClient() and not self.character:getInventory():containsID(self.item:getID()) then
			return false
		elseif not self.character:getInventory():contains(self.item) then
			return false
		end
	elseif self.targetPart then
		local tv = self.targetPart:getVehicle()
		if not tv or tv:isRemovedFromWorld() then return false end
		if not self.targetPart:getInventoryItem() then return false end
	elseif self.supplyEp or self.direction == "supply" then
		if self.supplyEp and self.supplyEp.get() <= 0 then return false end
	elseif self.direction == "drain" or self.direction == "drink" then
	else
		return false
	end
	local part = self:getPart()
	if not part or not part:getInventoryItem() then return false end
	return (self.units or 0) > 0
end

function VFluidTransferAction:focusVehicle()
	if self.targetPart then
		local v = self.targetPart:getVehicle()
		if v then return v end
	end
	return self.vehicle
end

function VFluidTransferAction:waitToStart()
	self.character:faceThisObject(self:focusVehicle())
	return self.character:shouldBeTurning()
end

function VFluidTransferAction.inFlight()
	return (VFluid.transfersInFlight or 0) > 0
end

local registered = false

local function flight(delta)
	if not registered and VFluid and VFluid.registerActivity then
		registered = VFluid.registerActivity("vfluid.transfer", VFluidTransferAction.inFlight)
	end
	VFluid.transfersInFlight = math.max(0, (VFluid.transfersInFlight or 0) + delta)
end

function VFluidTransferAction:start()
	flight(1)
	self:makeEndpoints()
	self:getDuration()
	if self.direction == "drink" then
		self:setActionAnim("drink_tap")
		if self.character.playSound then
			self.drinkAudio = self.character:playSound("DrinkingFromTap")
		end
	else
		self:setActionAnim("fill_container_tap")
	end
	if self.item and self.item.getStaticModel then
		self:setOverrideHandModels(nil, self.item:getStaticModel())
	end
end

function VFluidTransferAction:movingMixture()
	if not self.axis or self.axis.kind ~= "fluid" then return nil end
	if self.src and self.src.mixture then return self.src.mixture() end
	return nil
end

local function specFor(ep)
	if not ep then return nil end
	if ep.part and ep.part.getId then
		local v = ep.vehicle or (ep.part.getVehicle and ep.part:getVehicle())
		if v and v.getId then
			return { kind = "vpart", vehicle = v:getId(), part = ep.part:getId() }
		end
	end
	local k = ep.kind
	if k == "pump" then
		local h, sq = ep.holder, ep.holder
		if h and h.getSquare then
			local ok, s2 = pcall(function() return h:getSquare() end)
			if ok and s2 then sq = s2 end
		end
		if not sq or not sq.getX then return nil end
		return { kind = "supply", x = sq:getX(), y = sq:getY(), z = sq:getZ() }
	elseif k == "item" or k == "drainable" then
		local it = ep.holder
		return { kind = "item", item = it and it.getID and it:getID() or nil }
	elseif k == "void" then
		return { kind = "ground" }
	elseif k == "mouth" then
		return { kind = "mouth" }
	end
	return nil
end

function VFluidTransferAction:requestMove(amount)
	local src, dst = specFor(self.src), specFor(self.dst)
	if not src or not dst or not amount or amount <= 0 then return false end
	sendClientCommand(self.character, "vfluid", "move", {
		amount = amount, fluid = self:movingFluid(),
		shares = VFluid.encodeShares(self.movedShares),
		srcKind = src.kind, srcVehicle = src.vehicle, srcPart = src.part,
		srcX = src.x, srcY = src.y, srcZ = src.z, srcItem = src.item,
		dstKind = dst.kind, dstVehicle = dst.vehicle, dstPart = dst.part,
		dstX = dst.x, dstY = dst.y, dstZ = dst.z, dstItem = dst.item,
	})
	return true
end

function VFluidTransferAction:sliceDue(progress)
	if progress >= 1 then return true end

	local now = getTimestampMs()
	local since = self.lastSliceMs and (now - self.lastSliceMs) or math.huge

	if since < (VFluid.SYNC_MS or 100) then return false end

	if since >= (VFluid.SYNC_MAX_MS or 1000) then
		self.lastSliceMs = now
		return true
	end

	local units = self.units or 0
	local quantum = units / (VFluid.SYNC_SLICES or 60)
	if quantum > 0 then
		local pending = units * (progress - (self.lastProgress or 0))
		if pending < quantum then return false end
	end

	self.lastSliceMs = now
	return true
end

function VFluidTransferAction:flushSlice()
	if isServer() or not self:getPart() then return end
	pcall(function() self:advanceTo(self:getJobDelta()) end)
end

function VFluidTransferAction:advanceTo(progress)
	local last = self.lastProgress or 0
	if progress <= last then return 0 end
	-- Arrears, not a per-slice delta: a slice too small to move a whole quantum leaves the debt
	-- standing for the next one instead of dropping it.
	local want = (self.units or 0) * progress - (self.movedTotal or 0)
	local srcHas, dstFree = self.src.get(), self.dst.free()
	local moved = math.min(want, srcHas, dstFree)
	moved = VFluid.snapToQuantum(moved, VFluid.transferQuantum(self.src, self.dst))
	dbg("advanceTo dir=", self.direction, "progress=", progress, "want=", want,
		"srcHas=", srcHas, "dstFree=", dstFree, "moved=", moved)
	local applied = 0
	if moved > 0 then
		local shares = self:movingMixture()
		self.movedShares = shares
		if isClient() and VFluid.serverOnlyTransfer then
			-- the server drives the whole transfer off netAction progress; nothing to send
			dbg("client is a passenger - server writes")
		elseif isClient() then
			self:requestMove(moved)
			applied = moved
		else
			-- Destination first, then debit exactly what it took. Nothing leaves the source that
			-- the destination could not store, so an abort mid-transfer can lose nothing. A sink
			-- (ground, mouth) has no level to read back: it took what it was handed.
			local before = self.dst.get()
			self.dst.set(before + moved, self:movingFluid(), shares)
			applied = self.dst.sinkOnly and moved or (self.dst.get() - before)
			if applied > 0 then self.src.set(self.src.get() - applied) end
		end
	end
	self.lastProgress = progress
	if applied > 0 then self.movedTotal = (self.movedTotal or 0) + applied end
	return applied
end

-- On an MP client the SERVER owns the write and replicates it back; syncing here pushes our own
-- copy over the authoritative one, and ours is a step behind. Costs a whole quantum every time.
function VFluidTransferAction:syncBoth()
	if isClient() and not isServer() then return end
	self.src.sync()
	self.dst.sync()
end

function VFluidTransferAction:update()
	local progress
	if isServer() then
		progress = self.netAction:getProgress()
	else
		progress = self:getJobDelta()
	end

	if not isServer() then
		self.character:faceThisObject(self:focusVehicle())
		if self.item then self.item:setJobDelta(progress) end
	end

	if self:sliceDue(progress) then
		if self:advanceTo(progress) > 0 then self:syncBoth() end
	end

	self.character:setMetabolicTarget(Metabolics.HeavyDomestic)
end

function VFluidTransferAction:animEvent(event, parameter)
	if isServer() and event == "update" then self:update() end
end

function VFluidTransferAction:serverStart()
	-- src/dst are closures, so they cannot cross the wire: whatever the server is going to write
	-- through, it has to build here. start() is the client's hook, not this one.
	if VFluid.serverOnlyTransfer then
		local ok = self:makeEndpoints()
		dbg("serverStart makeEndpoints ->", ok, "src=", self.src ~= nil, "dst=", self.dst ~= nil)
		if ok then self:getDuration() end
	end
	emulateAnimEvent(self.netAction, VFluid.SYNC_MS or 500, "update", nil)
end

function VFluidTransferAction:serverStop()
	self:advanceTo(self.netAction:getProgress())
	self:settleLedger()
	self.src.sync()
	self.dst.sync()
end

function VFluidTransferAction:hushDrink()
	if not self.drinkAudio or self.drinkAudio == 0 then return end
	local emitter = self.character.getEmitter and self.character:getEmitter()
	if emitter and emitter:isPlaying(self.drinkAudio) then
		self.character:stopOrTriggerSound(self.drinkAudio)
	end
	self.drinkAudio = nil
end

function VFluidTransferAction:stop()
	self:flushSlice()
	flight(-1)
	self:hushDrink()
	if not isServer() and self.item then self.item:setJobDelta(0.0) end
	ISBaseTimedAction.stop(self)
end

function VFluidTransferAction:perform()
	flight(-1)
	self:hushDrink()
	if not isServer() and self.item then self.item:setJobDelta(0.0) end
	ISBaseTimedAction.perform(self)
end

function VFluidTransferAction:movingFluid()
	if not self.axis or self.axis.kind ~= "fluid" then return nil end
	if self.fluidName then return self.fluidName end
	if self.direction == "withdraw" or self.direction == "drink" then
		local part = self:getPart()
		local fluids = part and VFluid.rawLedger(part)
		local best, bestAmt
		if fluids then
			for name, amt in pairs(fluids) do
				if not bestAmt or amt > bestAmt then best, bestAmt = name, amt end
			end
		end
		if best then return best end
	end
	return self.axis.defaultFluid
end

function VFluidTransferAction:settleLedger()
	if not self.axis or self.axis.kind ~= "fluid" then return end
	local part = self:getPart()
	if not part then return end
	VFluid.ledger(self.vehicle, part, self.axis)

end

function VFluidTransferAction:complete()
	dbg("complete() reached, dir=", self.direction)
	if not self:getPart() then dbg("complete: NO PART"); return false end
	self:advanceTo(1)
	self:settleLedger()
	self:syncBoth()
	return true
end

function VFluidTransferAction:getDuration()
	local amount = math.min(self.src.get(), self.dst.cap() - self.dst.get())
	if amount < 0 then amount = 0 end
	-- A remnant too small for one whole quantum never enters the plan, so reaching progress 1
	-- means every step that could land has landed and the action ends on its own.
	amount = VFluid.snapToQuantum(amount, VFluid.transferQuantum(self.src, self.dst))
	self.units = amount
	self.lastProgress = 0
	self.movedTotal = 0
	if self.direction == "drink" then
		return (amount * 100) + 15
	end
	dbg("getDuration units=", self.units)
	local perUnit = (self.axis and self.axis.secondsPerUnit) or 12
	local speed = (VFluid.pumpSpeed and VFluid.pumpSpeed(self.src, self.dst)) or 1.0
	if speed and speed > 1 then perUnit = perUnit / speed end
	return math.max(10, amount * perUnit)
end

function VFluidTransferAction:new(character, part, item, direction, fluidName, targetPart, supplyEp,
		supplyX, supplyY, supplyZ)
	local o = ISBaseTimedAction.new(self, character)
	o.part = part
	o.vehicle = part:getVehicle()
	o.partId = part:getId()
	o.item = item
	o.targetPart = targetPart
	o.supplyEp = supplyEp
	o.supplyX, o.supplyY, o.supplyZ = supplyX, supplyY, supplyZ
	o.direction = direction
	o.fluidName = fluidName
	o.stopOnWalk = true
	o.stopOnRun = true
	if not o:makeEndpoints() then return o end
	o.maxTime = o:getDuration()
	return o
end
