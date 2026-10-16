require "TimedActions/ISBaseTimedAction"

PropaneRefuelAction = ISBaseTimedAction:derive("PropaneRefuelAction")

-- Shared across queued actions so one dry pump produces one warning, not one per item.
PropaneRefuelAction.lastEmptyWarning = 0

-- The action draws from either a gas pump or a propane tanker. Everything downstream
-- goes through these two, so the pump path is unchanged by the tanker support.
function PropaneRefuelAction:sourceAmount()
	local vehicle = PropaneRefuel.resolveVehicle(self)
	if vehicle then
		return PropaneRefuel.getVehicleReserve(vehicle)
	end
	if self.tankObject then
		return PropaneRefuel.getObjectReserve(self.tankObject)
	end
	if self.fuelStation then
		return self.fuelStation:getPipedFuelAmount()
	end
	return 0
end

function PropaneRefuelAction:setSourceAmount(amount)
	local vehicle = PropaneRefuel.resolveVehicle(self)
	if vehicle then
		PropaneRefuel.setVehicleReserve(vehicle, amount)
	elseif self.tankObject then
		PropaneRefuel.setObjectReserve(self.tankObject, amount)
	elseif self.fuelStation then
		self.fuelStation:setPipedFuelAmount(amount)
	end
end

function PropaneRefuelAction:hasSource()
	return (PropaneRefuel.resolveVehicle(self) ~= nil)
		or (self.tankObject ~= nil)
		or (self.fuelStation ~= nil)
end

-- Only a pump needs power: a tanker and a static tank are valves you turn by hand, and
-- gating those on the grid would break them for no reason.
--
-- The menu already refuses to offer an unpowered pump, so this is the second line rather
-- than the first -- but it is the one that matters. The menu runs on the client, and on a
-- server the client is not the authority; and power can die mid-pour, which no menu check
-- can catch. Both are handled here, where recalculate() and isValid() are re-run against
-- the world as it actually stands.
function PropaneRefuelAction:sourceIsPowered()
	if PropaneRefuel.resolveVehicle(self) or self.tankObject then return true end
	if not self.fuelStation then return true end
	return PropaneRefuel.isPumpPowered(self.fuelStation)
end

-- Authority model, matching vanilla ISConsolidateDrainable / ISAddFluidFromItemAction:
--   singleplayer      -> update() drives applyProgress()
--   MP client         -> visuals only, never mutates the item or the pump
--   dedicated server  -> animEvent()/serverStop() drive applyProgress() and push item stats

-- "Fill All" queues every item up front, so if these numbers were only worked out in
-- new() the third item would still be planning against the pump level the first one
-- started with -- draining fuel that is no longer there, or refusing to run at all.
-- Read the pump and the item again at the moment this action actually starts.
function PropaneRefuelAction:recalculate()
	-- Once fuel has actually moved, re-planning would reset unitsDrained and let the
	-- same units be drained twice. Only plan while nothing has happened yet.
	if self.appliedProgress and self.appliedProgress > 0 then return end
	if not self.item then return end

	self.unitsDrained = 0
	self.appliedProgress = 0
	self.startDelta = self.item:getCurrentUsesFloat()
	self.targetDelta = self.startDelta
	self.units = 0

	local cost = PropaneRefuel.getPumpCost(self.item)
	if not cost or not self:hasSource() then return end

	-- Leaves units at 0, which makes isValid() false and the action a no-op that never
	-- touches the item. Bailing here rather than later keeps the "nothing to do" path
	-- identical to the dry-pump one, which is already well tested.
	if not self:sourceIsPowered() then return end

	local available = math.floor(self:sourceAmount())
	self.units = math.max(0, math.min(math.ceil((1.0 - self.startDelta) * cost), available))
	self.targetDelta = math.min(1.0, self.startDelta + self.units / cost)
end

function PropaneRefuelAction:isValid()
	if not self.item or not self:hasSource() or self.units <= 0 then
		return false
	end

	-- Deliberately NOT checking whether the item is now full: that flips false at the
	-- exact moment a refill finishes, which would cancel the action instead of
	-- completing it, skipping perform() and leaving the inventory panel stale.
	-- recalculate() already bounds the work through self.units.
	if isClient() then
		return self.character:getInventory():containsID(self.item:getID())
	end

	-- The power test sits on the authoritative path alongside the fuel test: a generator
	-- running dry mid-pour stops the refill there and then, and the player keeps only what
	-- had actually been pumped by that point. Left off the client branch on purpose --
	-- clients own no state here, and a momentary local disagreement about the grid should
	-- not cut short a refill the server is happily still running.
	return self.character:getInventory():contains(self.item)
		and self:sourceAmount() > 0
		and self:sourceIsPowered()
end

function PropaneRefuelAction:waitToStart()
	if self.square then
		self.character:faceLocation(self.square:getX(), self.square:getY())
	end
	return self.character:shouldBeTurning()
end

function PropaneRefuelAction:applyProgress(progress)
	-- Never let progress run backwards, so this stays safe to call from both
	-- animEvent and serverStop.
	progress = math.max(math.min(progress, 1.0), self.appliedProgress)
	self.appliedProgress = progress

	-- Conservation rule: the item gains exactly what the source loses, never more.
	--
	-- This previously advanced unitsDrained by the amount it WANTED and filled the item
	-- straight from progress, while clamping the source at zero. Any time the source
	-- could not supply -- it ran dry mid-action, another player drained it, or the plan
	-- was made against a stale reading -- the item filled for free. That is a free
	-- propane generator, so the item's level is now derived from units actually taken.
	local wanted = math.floor(self.units * progress) - self.unitsDrained
	local taken = 0
	if wanted > 0 then
		local available = math.max(0, self:sourceAmount())
		taken = math.min(wanted, available)
		if taken > 0 then
			self:setSourceAmount(available - taken)
			self.unitsDrained = self.unitsDrained + taken
		end
	end

	local cost = PropaneRefuel.getPumpCost(self.item)
	if cost and cost > 0 then
		self.item:setUsedDelta(math.min(1.0, self.startDelta + self.unitsDrained / cost))
	end

	-- Push to clients when a whole pump unit moved, rather than on every tick.
	if taken > 0 and isServer() then
		sendItemStats(self.item)
	end
end

function PropaneRefuelAction:update()
	local progress = PropaneRefuel.actionProgress(self)

	-- Animation, facing and the item's progress bar belong to the machine that is
	-- actually playing them. Guarded on self.action for the reason set out in
	-- PropaneRefuel.actionProgress: with no local timed action there is nobody to animate
	-- here, and getJobDelta() would be reaching through a nil.
	if self.action then
		if self.square then
			self.character:faceLocation(self.square:getX(), self.square:getY())
		end
		self.item:setJobDelta(progress)
		self.character:setMetabolicTarget(Metabolics.LightWork)
	end

	if not isClient() then
		self:applyProgress(progress)
	end
end

function PropaneRefuelAction:start()
	-- Re-resolve the item against the inventory we actually have right now.
	if isClient() and self.item then
		local resolved = self.character:getInventory():getItemById(self.item:getID())
		if resolved then
			self.item = resolved
		end
	end

	self:recalculate()
	PropaneRefuel.applyActionDuration(self)

	-- A "Fill All" that outlasts the pump would otherwise just stop happening, with
	-- no indication why. Rate-limited so one dry pump does not stack a message per
	-- queued item.
	if self.units <= 0 and not isServer() then
		local now = getTimestampMs()
		if now - PropaneRefuelAction.lastEmptyWarning > 3000 then
			PropaneRefuelAction.lastEmptyWarning = now
			-- "Empty" and "no power" are different problems with different fixes -- one
			-- means find another station, the other means go and start the generator --
			-- so a queued action that dies because the lights went out has to say so
			-- rather than blaming the fuel level.
			local message = PropaneRefuel.getText("IGUI_PropaneRefuel_PumpEmpty", "The pump is empty")
			if not self:sourceIsPowered() then
				message = PropaneRefuel.getText("IGUI_PropaneRefuel_PumpNoPower", "The pump has no power")
			end
			-- addBadText rather than addText with getBadHighlitedColor(): same colour,
			-- but it is the form vanilla actually calls, and this path is rare enough
			-- that a wrong overload would go unnoticed until it fired on someone's server.
			HaloTextHelper.addBadText(self.character, message)
		end
	end

	self.item:setJobType(PropaneRefuel.getText("ContextMenu_PropaneRefuel_Refill", "Take Propane"))
	self.item:setJobDelta(0.0)

	self:setOverrideHandModels(nil, self.item:getStaticModel())
	self:setActionAnim("TakeGasFromPump")

	self.sound = self.character:playSound("CanisterAddFuelFromGasPump")
end

-- Without this the inventory panel keeps drawing the old fill level, so a "Fill All"
-- looks like it only filled the one item that happened to redraw. Needed on the
-- interrupted path too, where the item still gained whatever fuel it earned.
function PropaneRefuelAction:finishItemVisuals()
	if not self.item then return end
	self.item:setJobDelta(0.0)
	local container = self.item:getContainer()
	if container then
		container:setDrawDirty(true)
	end
end

function PropaneRefuelAction:stop()
	self.character:stopOrTriggerSound(self.sound)
	self:finishItemVisuals()
	ISBaseTimedAction.stop(self)
end

function PropaneRefuelAction:perform()
	self.character:stopOrTriggerSound(self.sound)
	self:finishItemVisuals()
	ISBaseTimedAction.perform(self)
end

function PropaneRefuelAction:complete()
	if not isClient() then
		self:applyProgress(1.0)
		if isServer() then
			sendItemStats(self.item)
		end
	end
	return true
end

function PropaneRefuelAction:serverStart()
	-- The server plans against its own, authoritative view of the pump right now.
	self:recalculate()
	emulateAnimEvent(self.netAction, 100, "refillPropane", nil)
end

function PropaneRefuelAction:animEvent(event, parameter)
	if isServer() and event == "refillPropane" then
		self:update()
	end
end

-- Finalises whatever the player actually earned, whether the action completed or
-- was interrupted partway through.
function PropaneRefuelAction:serverStop()
	if not self.item then return end
	if self.netAction then
		self:applyProgress(self.netAction:getProgress())
	end
	sendItemStats(self.item)
end

function PropaneRefuelAction:getDuration()
	if self.character:isTimedActionInstant() then
		return 1
	end
	return math.max(30, self.units * 50)
end

-- Exactly one of fuelStation / vehicle is set. Callers that only ever refuel at a pump
-- can keep passing three arguments as before.
function PropaneRefuelAction:new(character, fuelStation, item, vehicle, tankObject)
	local o = ISBaseTimedAction.new(self, character)
	o.fuelStation = fuelStation
	o.vehicle = vehicle
	-- Plain number, so it survives the hop to a dedicated server even if the vehicle
	-- reference does not. See PropaneRefuel.resolveVehicle.
	o.vehicleId = vehicle and vehicle:getId()
	o.tankObject = tankObject
	o.square = (fuelStation and fuelStation:getSquare())
		or (vehicle and vehicle:getSquare())
		or (tankObject and tankObject:getSquare())
	o.item = item
	o.stopOnWalk = true
	o.stopOnRun = true

	-- Defaults first: recalculate() bails out early when there is no item or no source,
	-- and getDuration() below would then be doing arithmetic on a nil.
	o.unitsDrained = 0
	o.appliedProgress = 0
	o.units = 0
	o.startDelta = item and item:getCurrentUsesFloat() or 0
	o.targetDelta = o.startDelta

	-- Only an estimate, so the queued action has a sensible duration. start() and
	-- serverStart() redo this against the pump as it stands when the action runs.
	o:recalculate()
	o.maxTime = o:getDuration()
	return o
end
