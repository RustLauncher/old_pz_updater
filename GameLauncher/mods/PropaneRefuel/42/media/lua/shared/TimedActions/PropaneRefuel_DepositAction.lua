require "TimedActions/ISBaseTimedAction"
require "TimedActions/PropaneRefuel_RefillAction"

PropaneRefuelDepositAction = ISBaseTimedAction:derive("PropaneRefuelDepositAction")

-- Pours a propane item into a static industrial tank -- the reverse of
-- PropaneRefuelAction. Same authority model throughout: the server owns every mutation,
-- an MP client only draws the animation, and progress falls back to the local timer
-- whenever no netAction is driving it (which is what makes co-op hosts work).

function PropaneRefuelDepositAction:recalculate()
	if self.appliedProgress and self.appliedProgress > 0 then return end
	if not self.item or not self.tankObject then return end

	self.unitsMoved = 0
	self.appliedProgress = 0
	self.units = 0
	self.startDelta = self.item:getCurrentUsesFloat()
	self.targetDelta = self.startDelta

	local cost = PropaneRefuel.getPumpCost(self.item)
	if not cost then return end

	local reserve = PropaneRefuel.getObjectReserve(self.tankObject)
	local space = math.max(0, PropaneRefuel.getObjectCapacity() - reserve)
	self.startReserve = reserve
	self.units = math.max(0, math.min(PropaneRefuel.getItemUnits(self.item), space))
	self.targetDelta = math.max(0, self.startDelta - self.units / cost)
end

function PropaneRefuelDepositAction:isValid()
	if not self.item or not self.tankObject or self.units <= 0 then
		return false
	end

	if isClient() then
		return self.character:getInventory():containsID(self.item:getID())
	end
	return self.character:getInventory():contains(self.item)
end

function PropaneRefuelDepositAction:waitToStart()
	if self.square then
		self.character:faceLocation(self.square:getX(), self.square:getY())
	end
	return self.character:shouldBeTurning()
end

function PropaneRefuelDepositAction:applyProgress(progress)
	if not self.item or not self.tankObject then return end

	progress = math.max(math.min(progress, 1.0), self.appliedProgress)
	self.appliedProgress = progress

	-- Conservation rule, in this direction too: the item loses exactly what the tank
	-- gains. Draining the item straight from progress while the tank silently capped at
	-- capacity would destroy propane rather than create it -- the mirror of the refill
	-- bug, and just as wrong.
	local wanted = math.floor(self.units * progress) - self.unitsMoved
	local moved = 0
	if wanted > 0 then
		local reserve = PropaneRefuel.getObjectReserve(self.tankObject)
		local space = math.max(0, PropaneRefuel.getObjectCapacity() - reserve)
		moved = math.min(wanted, space)
		if moved > 0 then
			PropaneRefuel.setObjectReserve(self.tankObject, reserve + moved)
			self.unitsMoved = self.unitsMoved + moved
		end
	end

	local cost = PropaneRefuel.getPumpCost(self.item)
	if cost and cost > 0 then
		self.item:setUsedDelta(math.max(0, self.startDelta - self.unitsMoved / cost))
	end

	if moved > 0 and isServer() then
		sendItemStats(self.item)
	end
end

-- See PropaneRefuel.actionProgress: on a dedicated server there is no local timed action
-- behind this, so getJobDelta() must not be touched and there is nothing to animate.
function PropaneRefuelDepositAction:update()
	local progress = PropaneRefuel.actionProgress(self)

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

function PropaneRefuelDepositAction:start()
	if isClient() and self.item then
		local resolved = self.character:getInventory():getItemById(self.item:getID())
		if resolved then
			self.item = resolved
		end
	end

	self:recalculate()
	PropaneRefuel.applyActionDuration(self)

	self.item:setJobType(PropaneRefuel.getText("ContextMenu_PropaneRefuel_Deposit", "Store Propane"))
	self.item:setJobDelta(0.0)

	self:setOverrideHandModels(nil, self.item:getStaticModel())
	self:setActionAnim("TakeGasFromPump")

	self.sound = self.character:playSound("CanisterAddFuelFromGasPump")
end

function PropaneRefuelDepositAction:finishItemVisuals()
	if not self.item then return end
	self.item:setJobDelta(0.0)
	local container = self.item:getContainer()
	if container then
		container:setDrawDirty(true)
	end
end

function PropaneRefuelDepositAction:stop()
	self.character:stopOrTriggerSound(self.sound)
	self:finishItemVisuals()
	ISBaseTimedAction.stop(self)
end

function PropaneRefuelDepositAction:perform()
	self.character:stopOrTriggerSound(self.sound)
	self:finishItemVisuals()
	ISBaseTimedAction.perform(self)
end

function PropaneRefuelDepositAction:complete()
	if not isClient() then
		self:applyProgress(1.0)
		if isServer() then
			sendItemStats(self.item)
		end
	end
	return true
end

function PropaneRefuelDepositAction:serverStart()
	self:recalculate()
	emulateAnimEvent(self.netAction, 100, "depositPropane", nil)
end

function PropaneRefuelDepositAction:animEvent(event, parameter)
	if isServer() and event == "depositPropane" then
		self:update()
	end
end

function PropaneRefuelDepositAction:serverStop()
	if not self.item then return end
	if self.netAction then
		self:applyProgress(self.netAction:getProgress())
	end
	sendItemStats(self.item)
end

function PropaneRefuelDepositAction:getDuration()
	if self.character:isTimedActionInstant() then
		return 1
	end
	return math.max(30, self.units * 50)
end

function PropaneRefuelDepositAction:new(character, tankObject, item)
	local o = ISBaseTimedAction.new(self, character)
	o.tankObject = tankObject
	o.item = item
	o.square = tankObject and tankObject:getSquare()
	o.stopOnWalk = true
	o.stopOnRun = true

	o.unitsMoved = 0
	o.appliedProgress = 0
	o.units = 0
	o.startReserve = 0
	o.startDelta = item and item:getCurrentUsesFloat() or 0
	o.targetDelta = o.startDelta

	o:recalculate()
	o.maxTime = o:getDuration()
	return o
end
