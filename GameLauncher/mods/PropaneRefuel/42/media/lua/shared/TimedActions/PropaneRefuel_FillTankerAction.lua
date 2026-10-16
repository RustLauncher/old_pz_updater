require "TimedActions/ISBaseTimedAction"
require "TimedActions/PropaneRefuel_RefillAction"

PropaneRefuelTankerAction = ISBaseTimedAction:derive("PropaneRefuelTankerAction")

-- Fills a propane tanker's reserve from a gas pump. Deliberately a separate action from
-- PropaneRefuelAction rather than a generalisation of it: that one moves fuel into an
-- inventory item, this moves it into vehicle ModData, and the item path is well tested
-- and not worth destabilising to save a few shared lines.
--
-- Same authority model as everything else here:
--   singleplayer     -> update() drives applyProgress()
--   MP client        -> visuals only, never mutates the pump or the vehicle
--   dedicated server -> animEvent()/serverStop() drive applyProgress()

-- This action only ever draws from a pump, so unlike the item refill there is no
-- non-pump case to let through -- but it is written the same way for the same reason:
-- the menu check is client-side and cannot see power dying halfway through the fill.
function PropaneRefuelTankerAction:sourceIsPowered()
	return self.fuelStation ~= nil and PropaneRefuel.isPumpPowered(self.fuelStation)
end

function PropaneRefuelTankerAction:recalculate()
	if self.appliedProgress and self.appliedProgress > 0 then return end

	self.unitsMoved = 0
	self.appliedProgress = 0
	self.units = 0
	local vehicle = PropaneRefuel.resolveVehicle(self)
	if not self.fuelStation or not vehicle then return end
	-- Leaves units at 0, so isValid() is false and not a drop moves.
	if not self:sourceIsPowered() then return end

	self.startReserve = PropaneRefuel.getVehicleReserve(vehicle)
	local space = math.max(0, PropaneRefuel.getTankerCapacity() - self.startReserve)
	local available = math.floor(self.fuelStation:getPipedFuelAmount())
	self.units = math.max(0, math.min(space, available))
end

function PropaneRefuelTankerAction:isValid()
	if not self.fuelStation or not PropaneRefuel.resolveVehicle(self) or self.units <= 0 then
		return false
	end
	-- Unlike the item refill this has no isClient() branch to keep clear of, because the
	-- action never mutates anything client-side: applyProgress is already gated on
	-- not isClient(), so stopping early on a client costs nothing but the animation.
	return self.fuelStation:getPipedFuelAmount() > 0 and self:sourceIsPowered()
end

function PropaneRefuelTankerAction:waitToStart()
	if self.square then
		self.character:faceLocation(self.square:getX(), self.square:getY())
	end
	return self.character:shouldBeTurning()
end

function PropaneRefuelTankerAction:applyProgress(progress)
	-- Reachable from serverStop as well as the tick loop, so it cannot assume the
	-- pump and vehicle are still around.
	local vehicle = PropaneRefuel.resolveVehicle(self)
	if not self.fuelStation or not vehicle then return end

	progress = math.max(math.min(progress, 1.0), self.appliedProgress)
	self.appliedProgress = progress

	-- Conservation rule: the tanker gains exactly what the pump loses. Crediting the
	-- tanker with the amount wanted while clamping the pump at zero would mint propane
	-- whenever the pump ran dry mid-fill.
	local wanted = math.floor(self.units * progress) - self.unitsMoved
	if wanted > 0 then
		local available = math.max(0, self.fuelStation:getPipedFuelAmount())
		local taken = math.min(wanted, available)
		if taken > 0 then
			self.fuelStation:setPipedFuelAmount(available - taken)
			self.unitsMoved = self.unitsMoved + taken
			PropaneRefuel.setVehicleReserve(vehicle, self.startReserve + self.unitsMoved)
		end
	end
end

-- See PropaneRefuel.actionProgress for why the progress source differs per machine, and
-- why the facing is only driven where there is a local timed action behind it.
function PropaneRefuelTankerAction:update()
	local progress = PropaneRefuel.actionProgress(self)

	if self.action then
		if self.square then
			self.character:faceLocation(self.square:getX(), self.square:getY())
		end
		self.character:setMetabolicTarget(Metabolics.LightWork)
	end

	if not isClient() then
		self:applyProgress(progress)
	end
end

function PropaneRefuelTankerAction:start()
	self:recalculate()
	PropaneRefuel.applyActionDuration(self)

	-- Same rate-limited warning the item refill uses, so a dry pump explains itself
	-- rather than the action just quietly doing nothing.
	if self.units <= 0 and not isServer() then
		local now = getTimestampMs()
		if now - PropaneRefuelAction.lastEmptyWarning > 3000 then
			PropaneRefuelAction.lastEmptyWarning = now
			-- Same split as the item refill: a dead pump and a dry one need different
			-- things done about them, so they do not share a message.
			local message = PropaneRefuel.getText("IGUI_PropaneRefuel_PumpEmpty", "The pump is empty")
			if not self:sourceIsPowered() then
				message = PropaneRefuel.getText("IGUI_PropaneRefuel_PumpNoPower", "The pump has no power")
			end
			HaloTextHelper.addBadText(self.character, message)
		end
	end

	self:setActionAnim("TakeGasFromPump")
	self.sound = self.character:playSound("VehicleAddFuelFromGasPump")
end

function PropaneRefuelTankerAction:stop()
	self.character:stopOrTriggerSound(self.sound)
	ISBaseTimedAction.stop(self)
end

function PropaneRefuelTankerAction:perform()
	self.character:stopOrTriggerSound(self.sound)
	ISBaseTimedAction.perform(self)
end

function PropaneRefuelTankerAction:complete()
	if not isClient() then
		self:applyProgress(1.0)
	end
	return true
end

function PropaneRefuelTankerAction:serverStart()
	self:recalculate()
	emulateAnimEvent(self.netAction, 100, "fillPropaneTanker", nil)
end

function PropaneRefuelTankerAction:animEvent(event, parameter)
	if isServer() and event == "fillPropaneTanker" then
		self:update()
	end
end

function PropaneRefuelTankerAction:serverStop()
	if self.netAction then
		self:applyProgress(self.netAction:getProgress())
	end
end

function PropaneRefuelTankerAction:getDuration()
	if self.character:isTimedActionInstant() then
		return 1
	end
	-- Slower per unit than filling a hand-held item; this is a truck.
	return math.max(50, self.units * 20)
end

function PropaneRefuelTankerAction:new(character, fuelStation, vehicle)
	local o = ISBaseTimedAction.new(self, character)
	o.fuelStation = fuelStation
	o.vehicle = vehicle
	o.vehicleId = vehicle and vehicle:getId()
	o.square = fuelStation and fuelStation:getSquare()
	o.stopOnWalk = true
	o.stopOnRun = true

	o.unitsMoved = 0
	o.appliedProgress = 0
	o.units = 0
	o.startReserve = 0

	o:recalculate()
	o.maxTime = o:getDuration()
	return o
end
