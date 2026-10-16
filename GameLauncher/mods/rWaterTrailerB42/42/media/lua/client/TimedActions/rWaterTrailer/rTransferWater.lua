-- Based on: ISAddGasolineToVehicle.lua, ISTakeGasolineFromVehicle --

require "TimedActions/ISBaseTimedAction"

require "rWaterTrailer.B42Compat"

local rWaterTrailerCompat = rWaterTrailer.Compat

rTransferWater = ISBaseTimedAction:derive("rTransferWater")

local function isTaintedWater(item, isFluid)
	if isFluid then
		return item:getFluidContainer():contains(Fluid.TaintedWater)
	end
	return item:isTaintedWater()
end

function rTransferWater:isValid()
	return true
end

function rTransferWater:waitToStart()
	if self.itemIsThumpable then
		self.character:faceThisObject(self.item)
	else
		self.character:faceThisObject(self.vehicle)
	end

	return self.character:shouldBeTurning()
end

function rTransferWater:start()

	--[[ optional parts ]]--

	local pumpSpeed = 30
	local filterBreak = 20

	self.filter = self.vehicle:getPartById("WaterTankFilter")
	self.filterUsed = false
	self.pump = self.vehicle:getPartById("WaterTankPump")
	self.pumpUsed = false

	-- make sure parts are installed --
	if self.filter and not self.filter:getInventoryItem() then
		self.filter = nil
	end
	if self.pump and not self.pump:getInventoryItem() then
		self.pump = nil
	end

	if self.pump then
		pumpSpeed = pumpSpeed - (self.pump:getCondition() / 10) * 2
	end

	if self.filter and (self.itemIsDrainable or self.itemIsPlayer) and self.flow == "toItem" then
		self.filterUsed = true
		if self.filter:getCondition() < filterBreak then
			self.filterUsed = ZombRand(100) <= ((filterBreak - self.filter:getCondition()) / 5) * 25

			if not self.filterUsed and self.itemIsPlayer and self.tank:getModData().Tainted then
				self.character:Say(getText(self.filter:getCondition() <= 0 and "FILTER GONE" or "FILTER DANGEROUS TO USE"))
				self:forceStop()
			end
		end
	end

	--[[ math ]]--

	if self.flow == "toItem" and self.itemIsDrainable and not self.itemIsFluid and self.item:canStoreWater() and not self.item:isWaterSource() then -- deal with empty legacy drainables --
		local newItemType = self.item:getReplaceOnUseOn()
		if newItemType then
			newItemType = string.sub(newItemType,13) -- legacy B41 drainable format
			newItemType = self.item:getModule() .. "." .. newItemType
			local newItem = self.character:getInventory():AddItem(newItemType)
			newItem:setCondition(self.item:getCondition())
			newItem:setFavorite(self.item:isFavorite())
			newItem:setUsedDelta(0)
			self.character:getInventory():DoRemoveItem(self.item)
			self.item = newItem
		end
	end

	local add, take

	self.tankStart = self.tank:getContainerContentAmount()

	if self.itemIsVoid or self.itemIsPlayer then
		self.itemStart = 0
	elseif self.itemIsThumpable then
		self.itemStart = self.item:getWaterAmount()
		self.itemMax = self.item:getWaterMax()
	elseif self.itemIsFluid then
		self.itemStart = self.item:getFluidContainer():getAmount()
		self.itemMax = self.item:getFluidContainer():getCapacity()
	elseif self.itemIsDrainable then -- legacy drainables
		self.itemStart = self.item:getDrainableUsesInt()
		self.itemMax = 1.0 / self.item:getUseDelta() + 0.0001 -- from ISWorldObjectContextMenu --
	end

	if self.flow == "toItem" then
		if self.itemIsVoid then -- tank -> ground --
			add = self.tankStart
		elseif self.itemIsPlayer then -- tank -> mouth --
			add = math.floor((self.character:getStats():get(CharacterStat.THIRST) + 0.005) / 0.1)
		else
			add = self.itemMax - self.itemStart
		end

		take = math.min(add, self.tankStart)

		self.tankTarget = self.tankStart - take
		self.itemTarget = self.itemStart + take
	elseif self.flow == "toTank" then
		add = self.tank:getContainerCapacity() - self.tankStart

		if self.itemIsVoid then -- lake -> tank --
			take = add
		else
			take = math.min(add, self.itemStart)
		end

		self.tankTarget = self.tankStart + take
		self.itemTarget = self.itemStart - take
	end

	self.amountSent = self.tankStart

	--[[ sound / time ]]--

	local noiseStart = 0

	if self.itemIsVoid then
		self.soundLake = self.character:getEmitter():playSound("GetWaterFromLake")
	end

	if self.itemIsVoid and self.flow == "toItem" then
		self.action:setTime(take * 30)
		self.soundTap = self.vehicle:getEmitter():playSound("GetWaterFromTap")
		noiseStart = 25
	elseif (self.itemIsVoid and self.flow == "toTank") or self.itemIsThumpable then
		self.action:setTime(take * pumpSpeed)
		if self.pump then
			self.soundGenerator = self.vehicle:getEmitter():playSound("GeneratorLoop")
			self.pumpUsed = true
			noiseStart = 20
		else
			noiseStart = 15
		end
	elseif self.itemIsDrainable then
		self.action:setTime(take * 45) -- using faucet --
		if self.flow == "toItem" then
			self.soundTap = self.vehicle:getEmitter():playSound("GetWaterFromTap")
		end
		noiseStart = 10
	elseif self.itemIsPlayer and self.flow == "toItem" then
		self.action:setTime((take * 10) + 15)
	end

	if self.flow == "toTank" then
		self.soundTapTank = self.character:getEmitter():playSound("GetWaterFromTapMetalBig")
	end

	if noiseStart > 0 then
		addSound(self.character, self.character:getX(), self.character:getY(), self.character:getZ(), noiseStart, 1)
	end

	--[[ animation / ui ]]--

	if self.itemIsDrainable then
		if self.itemIsFluid then
			self:setAnimVariable("PourType", self.item:getPourType())
		else
			self:setAnimVariable("FoodType", self.item:getEatType())
		end
		self:setActionAnim("fill_container_tap")
		self:setOverrideHandModels(self.character:getPrimaryHandItem(), self.item:getStaticModel()) --  left = drainable --

		if self.flow == "toItem" then
			self.item:setJobType(getText("ContextMenu_VehicleSiphonWater"))
		elseif self.flow == "toTank" then
			self.item:setJobType(getText("ContextMenu_VehicleAddWater"))
		end
		if self.itemIsFluid then
			self.item:setBeingFilled(true)
		end
		self.item:setJobDelta(self:getJobDelta())
	elseif self.itemIsPlayer then
		self:setActionAnim("drink_tap")
		self:setOverrideHandModels(nil, nil)
	else
		self:setActionAnim("fill_container_tap")
		self:setOverrideHandModels(self.character:getPrimaryHandItem(), nil) -- left = pump/nothing --
	end

	if self.itemIsThumpable then
		self.character:faceThisObject(self.item)
	else
		self.character:faceThisObject(self.vehicle)
	end
end

function rTransferWater:update()
	if self.itemIsDrainable then
		self.character:faceThisObject(self.vehicle)
	end

	if self.itemIsDrainable then
		self.item:setJobDelta(self:getJobDelta())
	end

	local litres = self.tankStart + (self.tankTarget - self.tankStart) * self:getJobDelta()
	litres = math.ceil(litres)

	local itemDiff = 0
	if litres ~= self.amountSent then
		local tankDiff = litres - self.amountSent
		itemDiff = -tankDiff
		local args = { vehicle = self.vehicle:getId(), part = self.tank:getId(), amount = self.tank:getContainerContentAmount() + tankDiff }
		sendClientCommand(self.character, 'vehicle', 'setContainerContentAmount', args)
		self.amountSent = litres
	end

	local litresTaken, itemAmount
	if self.flow == "toItem" then
		litresTaken = self.tankStart - litres
		if not self.itemIsVoid then
			itemAmount = self.itemStart + litresTaken
		end
	elseif self.flow == "toTank" then
		litresTaken = litres - self.tankStart
		if not self.itemIsVoid then
			itemAmount = self.itemStart - litresTaken
		end
	end

	if self.pump and self.pumpUsed then
		local sound = false

		if self.pump:getCondition() > 0 and ZombRand(3000) == 0 then
			self.pump:setCondition(self.pump:getCondition() - 1)
			self.vehicle:transmitPartCondition(self.pump)
			sound = true
		elseif self.pump:getCondition() == 0 and ZombRand(600) == 0 then
			sound = true
		end

		if sound then
			addSound(self.character, self.character:getX(), self.character:getY(), self.character:getZ(), 20 - self.pump:getCondition() / 10, 1)
		end
	end

	if self.filter and self.filterUsed and self.flow == "toItem" and (self.itemIsDrainable or self.itemIsPlayer) and self.filter:getCondition() > 0 and ZombRand(600) == 0 then
		-- by design: filter is getting used even if water inside is clean --
		self.filter:setCondition(self.filter:getCondition() - 1)
		self.vehicle:transmitPartCondition(self.filter)

		if self.filter:getCondition() <= 0 then
			self.filterUsed = false
		end
	end

	if self.itemIsThumpable and itemDiff ~= 0 then
		rWaterTrailerCompat.dprint("rTransferWater : thumbable " .. (itemDiff > 0 and "+" or "") .. itemDiff)
		local args = { x = self.item:getX(), y = self.item:getY(), z = self.item:getZ(), index = self.item:getObjectIndex(), amount = self.item:getWaterAmount() + itemDiff }
		sendClientCommand(self.character, 'object', 'setWaterAmount', args)
	elseif self.itemIsFluid then
		local fluidContainer = self.item:getFluidContainer()
		if fluidContainer:isEmpty() and itemAmount > 0 then
			local fluid = self.tank:getModData().Tainted and not self.filterUsed and Fluid.TaintedWater or Fluid.Water
			fluidContainer:addFluid(fluid, itemAmount)
		else
			fluidContainer:adjustAmount(itemAmount)
		end
		self.item:syncItemFields()
	elseif self.itemIsDrainable then
		self.item:setUsedDelta(itemAmount / self.itemMax)
	elseif self.itemIsPlayer and self.flow == "toItem" and itemDiff > 0 then
		if not self.filterUsed and self.tank:getModData().Tainted then
			self.character:Say(getText("FILTER GONE"))
			self:forceStop()
		end

		local thirst = self.character:getStats():get(CharacterStat.THIRST) - (itemDiff / 10)
		self.character:getStats():set(CharacterStat.THIRST, math.max(thirst, 0.0))
	end

	if self.itemIsVoid then
		if self.flow == "toTank" and not self.tank:getModData().Tainted then
			self.tank:getModData().Tainted = true
			self.vehicle:transmitPartModData(self.tank)

			rWaterTrailerCompat.dprint("rTransferWater : tank tainted")
		end
	else
		if self.flow == "toTank" and isTaintedWater(self.item, self.itemIsFluid) and not self.tank:getModData().Tainted then
			self.tank:getModData().Tainted = true
			self.vehicle:transmitPartModData(self.tank)

			rWaterTrailerCompat.dprint("rTransferWater : tank tainted")
		elseif self.flow == "toItem" and self.tank:getModData().Tainted and not isTaintedWater(self.item, self.itemIsFluid) and not self.filterUsed then
			if not self.itemIsFluid then
				self.item:setTaintedWater(true)
			end

			rWaterTrailerCompat.dprint("rTransferWater : item tainted")
		end
	end

	self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function rTransferWater:stop()
	if self.itemIsDrainable then
		if self.itemIsFluid then
			self.item:setBeingFilled(false)
		end
		self.item:setJobDelta(0)
	end

	self:stopAllSounds()

	rWaterTrailerCompat.dprint("rTransferWater : STOP")

	ISBaseTimedAction.stop(self)
end

function rTransferWater:stopSound(source, sound)
	if source and sound and source:getEmitter():isPlaying(sound) then
		source:getEmitter():stopSound(sound)
	end
end

function rTransferWater:stopAllSounds()
	self:stopSound(self.vehicle, self.soundGenerator)
	self:stopSound(self.vehicle, self.soundTap)
	self:stopSound(self.character, self.soundTapTank)
	self:stopSound(self.character, self.soundLake)
end

function rTransferWater:perform()
	if self.itemIsFluid then
		self.item:setBeingFilled(false)
		self.item:setJobDelta(0)
		self.item:getFluidContainer():adjustAmount(self.itemTarget)
		self.item:syncItemFields()
	elseif self.itemIsDrainable then
		self.item:setJobDelta(0)
		self.item:setUsedDelta(self.itemTarget / self.itemMax)
	end

	self:stopAllSounds()

	if self.itemIsDrainable and not self.itemIsFluid and self.flow == "toTank" and self.item:getUsedDelta() <= 0 then
		self.item:Use()
	end

	rWaterTrailerCompat.dprint("rTransferWater : PERFORM")

	-- needed to remove from queue / start next.
	ISBaseTimedAction.perform(self)
end

function rTransferWater:new(player, tank, flow, item)
	local r = {}
	setmetatable(r, self)
	self.__index = self
	r.character = player
	r.vehicle = tank:getVehicle()
	r.tank = tank
	r.item = type(item) ~= "string" and item
	r.itemIsVoid = item == "void"
	r.itemIsThumpable = instanceof(item, "IsoThumpable")
	r.itemIsFluid = r.item and r.item:getFluidContainer() ~= nil
	r.itemIsDrainable = instanceof(item, "DrainableComboItem") or instanceof(item, "InventoryItem")
	r.itemIsPlayer = instanceof(item, "IsoPlayer")
	r.stopOnWalk = true
	r.stopOnRun = true
	r.maxTime = 50

	assert(r.itemIsVoid or r.itemIsThumpable or r.itemIsDrainable or r.itemIsPlayer, "Unknown item instance")

	if flow == "<-" or flow == "toTank" then
		r.flow = "toTank"
	elseif flow == "->" or flow == "toItem" then
		r.flow = "toItem"
	else
		error("Unknown flow '" .. flow .. "'")
		return nil
	end

	if r.itemIsPlayer and r.flow == "toTank" then
		error("you can't spit into tank, what is wrong with you?")
		return nil
	end

	return r
end
