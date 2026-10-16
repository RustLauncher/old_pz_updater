-- Wash at a tank: vanilla's own wash flow pointed at a vehicle part as the water source.

require "TimedActions/ISWashYourself"

VFluidWashAction = VFluidWashAction or {}

function VFluidWashAction.makeSink(vehicle, part, ep, character)
	return {
		getSquare = function() return vehicle and vehicle:getSquare() or nil end,
		getFluidAmount = function() return ep.get() end,
		useFluid = function(_, n)
			if not n or n <= 0 then return 0 end
			local moved = math.min(n, ep.get())
			if moved <= 0 then return 0 end
			if isClient() then
				sendClientCommand(character, "vfluid", "move", {
					amount = moved, fluid = ep.axis and ep.axis.defaultFluid or nil,
					srcKind = "vpart", srcVehicle = vehicle and vehicle:getId() or nil,
					srcPart = part and part:getId() or nil,
					dstKind = "ground",
				})
				return moved
			end
			ep.set(ep.get() - moved)
			if ep.axis then VFluid.ledger(vehicle, part, ep.axis) end
			return moved
		end,
		transmitModData = function() if ep.sync then ep.sync() end end,
	}
end

local makeSink = VFluidWashAction.makeSink

function VFluidWashAction:new(character, part)
	if not ISWashYourself or not ISWashYourself.new then return nil end
	local vehicle = part and part:getVehicle()
	local ep = vehicle and VFluid.transferEndpointFor(vehicle, part)
	if not ep then return nil end
	local sink = makeSink(vehicle, part, ep, character)

	local o = ISWashYourself:new(character, sink)
	if not o then return nil end
	o.vehicle, o.part, o.ep = vehicle, part, ep

	o.update = function(self)
		if self.vehicle then self.character:faceThisObjectAlt(self.vehicle) end
		self.character:setMetabolicTarget(Metabolics.LightDomestic)
	end
	o.isValid = function(self)
		return self.ep ~= nil and self.ep.get() > 0
	end
	return o
end

function VFluidWashAction.clothing(character, part, item, noSoap)
	if not ISWashClothing or not ISWashClothing.new or not item then return nil end
	local vehicle = part and part:getVehicle()
	local ep = vehicle and VFluid.transferEndpointFor(vehicle, part)
	if not ep then return nil end

	local blood, dirt = 0, 0
	if instanceof(item, "Clothing") or instanceof(item, "InventoryContainer") then
		local covered = BloodClothingType.getCoveredParts(item:getBloodClothingType())
		if covered then
			for j = 0, covered:size() - 1 do
				blood = blood + item:getBlood(covered:get(j))
			end
		end
		if item:getDirtiness() > 0 then dirt = item:getDirtiness() end
	else
		blood = item:getBloodLevel()
	end

	local o = ISWashClothing:new(character, makeSink(vehicle, part, ep, character), item, blood, dirt, noSoap)
	if not o then return nil end
	o.vehicle, o.part, o.ep = vehicle, part, ep
	o.update = function(self)
		if self.vehicle then self.character:faceThisObjectAlt(self.vehicle) end
		self.character:setMetabolicTarget(Metabolics.LightDomestic)
	end
	return o
end
