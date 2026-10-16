-- The scrub action: equips gloves and mop for the animation, restores what was worn when it
-- ends - on completion and on interruption alike.

require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISWearClothing"
require "TimedActions/ISEquipWeaponAction"
require "TimedActions/ISUnequipAction"

VFluid = VFluid or {}

VFluidCleanAction = ISBaseTimedAction:derive("VFluidCleanAction")

function VFluidCleanAction:resolve()
	local v = self.vehicleId and getVehicleById and getVehicleById(self.vehicleId)
	local part = v and v:getPartById(self.partId)
	local axis = (v and part) and VFluid.axisFor(v, part) or nil
	return v, part, axis
end

function VFluidCleanAction:isValid()
	local v, part, axis = self:resolve()
	if not part or not axis then return false end
	return VFluid.cleaningPlan(self.character, v, part, axis).ok == true
end

function VFluidCleanAction:waitToStart()
	local v = self:resolve()
	if not v then return false end
	self.character:faceThisObject(v)
	return self.character:shouldBeTurning()
end

function VFluidCleanAction:start()
	self:setActionAnim("ScrubWall_Mop")
	self:setOverrideHandModels(self.character:getPrimaryHandItem(), nil)
	self.sound = self.character:playSound("CleanBloodScrub")
end

function VFluidCleanAction:stop()
	if self.sound then self.character:stopOrTriggerSound(self.sound) end
	self:restoreEquipped()
	ISBaseTimedAction.stop(self)
end

function VFluidCleanAction:perform()
	if self.sound then self.character:stopOrTriggerSound(self.sound) end
	local v, part, axis = self:resolve()
	if part and axis then
		if isClient and isClient() then
			sendClientCommand(self.character, "vfluid", "clean",
				{ vehicle = self.vehicleId, part = self.partId })
		else
			VFluid.performClean(self.character, v, part, axis)
		end
	end
	self:restoreEquipped()
	ISBaseTimedAction.perform(self)
end

function VFluidCleanAction:restoreEquipped()
	local r = self.restoreGear
	if not r or self._gearRestored then return end
	self._gearRestored = true
	local playerObj = self.character
	local inv = playerObj and playerObj.getInventory and playerObj:getInventory()
	local function carried(item) return item ~= nil and inv ~= nil and inv:contains(item) end
	if r.hand then
		if carried(r.hand.prev) then
			local two = (r.hand.prev.isTwoHandWeapon and r.hand.prev:isTwoHandWeapon()) or false
			ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj, r.hand.prev, 50, true, two))
		elseif carried(r.hand.ours) then
			ISTimedActionQueue.add(ISUnequipAction:new(playerObj, r.hand.ours, 50))
		end
	end
	if r.gloves then
		if carried(r.gloves.prev) then
			ISTimedActionQueue.add(ISWearClothing:new(playerObj, r.gloves.prev))
		elseif carried(r.gloves.ours) then
			ISTimedActionQueue.add(ISUnequipAction:new(playerObj, r.gloves.ours, 50))
		end
	end
end

function VFluidCleanAction:getDuration()
	if self.character:isTimedActionInstant() then return 1 end
	return 450
end

function VFluidCleanAction:new(character, vehicle, part)
	local o = ISBaseTimedAction.new(self, character)
	o.vehicleId = vehicle and vehicle:getId() or nil
	o.partId = part and part:getId() or nil
	o.stopOnWalk = true
	o.stopOnRun = true
	o.caloriesModifier = 5
	o.maxTime = o:getDuration()
	return o
end

--------------------------------------------------------------------------------
-- gear: equip for the scrub, restore what was worn
--------------------------------------------------------------------------------
local function isWorn(playerObj, item)
	if not item then return false end
	if playerObj.isEquippedClothing then
		local ok, worn = pcall(function() return playerObj:isEquippedClothing(item) end)
		if ok then return worn == true end
	end
	return item.isEquipped and item:isEquipped() == true
end

function VFluidCleanAction.queue(playerObj, vehicle, part, axis)
	if not playerObj or not vehicle or not part or not axis then return false end
	local plan = VFluid.cleaningPlan(playerObj, vehicle, part, axis)
	if not plan.ok then return false, plan.why end

	ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, vehicle, part:getArea()))

	local restore = nil
	if plan.gear and not isWorn(playerObj, plan.gear) then
		local loc = plan.gear.getBodyLocation and plan.gear:getBodyLocation() or nil
		restore = restore or {}
		restore.gloves = { prev = loc and playerObj:getWornItem(loc) or nil, ours = plan.gear }
		ISTimedActionQueue.add(ISWearClothing:new(playerObj, plan.gear))
	end
	if plan.tool and playerObj:getPrimaryHandItem() ~= plan.tool then
		restore = restore or {}
		restore.hand = { prev = playerObj:getPrimaryHandItem(), ours = plan.tool }
		ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj, plan.tool, 50, true, false))
	end

	local act = VFluidCleanAction:new(playerObj, vehicle, part)
	act.restoreGear = restore
	ISTimedActionQueue.add(act)
	return true
end
