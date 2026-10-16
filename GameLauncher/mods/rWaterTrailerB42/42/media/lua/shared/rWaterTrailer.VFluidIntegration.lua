-- Water Trailer <-> Vehicle Fluid Logistics integration.
--
-- VFluid owns composition and transfers. This file supplies the vehicle-specific
-- mechanics VFluid cannot infer from contentType alone: the physical tank lid,
-- the original pump/filter parts, legacy taint migration and our default service.

rWaterTrailer = rWaterTrailer or {}
rWaterTrailer.VFluid = rWaterTrailer.VFluid or {}
rWaterTrailer.VFluid.Create = rWaterTrailer.VFluid.Create or {}
rWaterTrailer.Vehicle = rWaterTrailer.Vehicle or { Create = {}, ContainerAccess = {} }
rWaterTrailer.Vehicle.Create = rWaterTrailer.Vehicle.Create or {}
rWaterTrailer.Vehicle.ContainerAccess = rWaterTrailer.Vehicle.ContainerAccess or {}

local Integration = rWaterTrailer.VFluid

-- VFluid's tank-cleaning tooltip contains four replacement markers, but its
-- helper requests translations without supplying values. Build 42 still
-- returns the text, while also flooding the log with missing-argument warnings.
-- Supplying the markers as their own values keeps the text available for
-- VFluid's later substitutions and makes every other lookup behave normally.
if VFluid and type(VFluid.tr) == "function" and not Integration._translationGuardPatched then
	local function translated(key, default)
		if getTextOrNull then
			local ok, value = pcall(getTextOrNull, key, "%1", "%2", "%3", "%4")
			if ok and value then return value end
		end
		if getText then
			local ok, value = pcall(getText, key, "%1", "%2", "%3", "%4")
			if ok and value and value ~= key then return value end
		end
		return default
	end
	VFluid.tr = translated
	Integration._translationGuardPatched = true
end

local WATER_TRAILERS = {
	TrailerWaterSmall = true,
	TrailerWaterBig = true,
	TrailerM967tankerWater = true,
}

function Integration.IsWaterTrailer(vehicle)
	local script = vehicle and vehicle.getScript and vehicle:getScript()
	local name = script and script.getName and script:getName()
	return name ~= nil and WATER_TRAILERS[name] == true
end

function Integration.IsCargoTank(vehicle, part)
	return Integration.IsWaterTrailer(vehicle)
		and part ~= nil
		and part.isContainer and part:isContainer()
		and part.getCategory and part:getCategory() == "watertank"
		and part.getInventoryItem and part:getInventoryItem() ~= nil
end

function Integration.IsLidOpen(vehicle)
	local lid = vehicle and vehicle.getPartById and vehicle:getPartById("WaterTankLid")
	-- A missing/unfitted lid leaves an open tank.
	if not lid or not lid:getInventoryItem() then return true end
	local door = lid:getDoor()
	return door == nil or door:isOpen()
end

function Integration.HasWorkingFilter(vehicle)
	local filter = vehicle and vehicle.getPartById and vehicle:getPartById("WaterTankFilter")
	return filter ~= nil and filter:getInventoryItem() ~= nil and (filter:getCondition() or 0) > 0
end

function Integration.HasWorkingPump(vehicle)
	local pump = vehicle and vehicle.getPartById and vehicle:getPartById("WaterTankPump")
	-- Vehicle mechanics already resolves an absent install to condition 0. Using
	-- that same observable state avoids rejecting the installed 88% pump shown
	-- in mechanics because of a differing item/structural-slot interpretation.
	return pump ~= nil and (pump:getCondition() or 0) > 0
end

local function tankFromSpec(spec)
	if not spec or spec.kind ~= "vpart" or not getVehicleById then return nil, nil end
	local vehicle = getVehicleById(spec.vehicle)
	local part = vehicle and vehicle:getPartById(spec.part)
	if not Integration.IsCargoTank(vehicle, part) then return nil, nil end
	return vehicle, part
end

local function endpointTank(endpoint)
	local vehicle = endpoint and endpoint.vehicle
	local part = endpoint and endpoint.part
	if not Integration.IsCargoTank(vehicle, part) then return nil, nil end
	return vehicle, part
end

local function isNaturalWaterEndpoint(endpoint)
	return endpoint and endpoint.holder and VFluid and VFluid.isOpenWaterSquare
		and VFluid.isOpenWaterSquare(endpoint.holder)
end

local function gasPumpRejects(endpoint, fluidName)
	-- Piped fuel pumps expose only an amount, so VFluid otherwise assigns the
	-- destination tank's selected fluid to that amount.  A forecourt pump can
	-- supply Petrol and must never become a source of water or other fluids.
	return endpoint ~= nil
		and endpoint.supplyKind == "gaspump"
		and fluidName ~= "Petrol"
end

local function purifiedShares(shares)
	if not shares or not shares.TaintedWater or shares.TaintedWater <= 0 then return shares end
	local out = {}
	for fluidName, share in pairs(shares) do
		if fluidName ~= "TaintedWater" then out[fluidName] = share end
	end
	out.Water = (out.Water or 0) + shares.TaintedWater
	return out
end

local function taintedShares(shares)
	if not shares or not shares.Water or shares.Water <= 0 then return shares end
	local out = {}
	for fluidName, share in pairs(shares) do
		if fluidName ~= "Water" then out[fluidName] = share end
	end
	out.TaintedWater = (out.TaintedWater or 0) + shares.Water
	return out
end

local function actionOutletVehicle(action)
	local vehicle = action and action.src and action.src.vehicle
	local part = action and action.src and action.src.part
	if not Integration.IsCargoTank(vehicle, part) then return nil end
	local kind = action.dst and action.dst.kind
	if kind ~= "item" and kind ~= "drainable" and kind ~= "mouth" then return nil end
	return vehicle
end

local function outletComposition(vehicle, fluidName, shares)
	if Integration.HasWorkingFilter(vehicle) then
		if fluidName == "TaintedWater" then fluidName = "Water" end
		return fluidName, purifiedShares(shares)
	end
	-- These are untreated storage tanks: without their outlet filter, even
	-- previously clean-looking stored water leaves as contaminated water.
	if fluidName == "Water" then fluidName = "TaintedWater" end
	return fluidName, taintedShares(shares)
end

-- The script callback used by every tank. New tanks use VFluid's spawn load,
-- but start in unlocked Multi Fluid mode so an empty tank can automatically
-- change service from water to fuel (or another compatible VFluid service).
function Integration.Create.FilledMultiTank(vehicle, part)
	if not (VFluid and VFluid.Create and VFluid.Create.FilledTank) then return end
	VFluid.Create.FilledTank(vehicle, part)
	local axis = VFluid.axisFor and VFluid.axisFor(vehicle, part)
	if not axis then return end
	Integration.EnsureMulti(vehicle, part, axis)
end

-- Existing trailers predate the VFluid callback above. Upgrade each one lazily
-- the first time a transfer inspects it, on both the menu and authority side.
-- The marker makes this a one-time migration and preserves later player choices.
function Integration.EnsureMulti(vehicle, part, axis)
	if not Integration.IsCargoTank(vehicle, part) then return end
	local md = part:getModData()
	if md.rWaterTrailerVFluidReady == true then return end
	-- Mark first so designation helpers cannot re-enter this migration indirectly.
	md.rWaterTrailerVFluidReady = true
	axis = axis or (VFluid and VFluid.axisFor and VFluid.axisFor(vehicle, part))
	if not axis then return end
	if VFluid.setDesignation and VFluid.MODE_MULTI then
		VFluid.setDesignation(vehicle, part, axis, VFluid.MODE_MULTI, nil)
	end
	if VFluid.setDesignationLock then
		VFluid.setDesignationLock(vehicle, part, axis, false)
	end
	if vehicle and vehicle.transmitPartModData then vehicle:transmitPartModData(part) end
end

-- The container is physically accessible only beside the tank and with its lid
-- open. The transfer gates below enforce the same rule for VFluid endpoints.
function rWaterTrailer.Vehicle.ContainerAccess.WaterTank(vehicle, part, character)
	if not vehicle or not part or not character then return false end
	if character:getVehicle() then return false end
	if part:getArea() and not vehicle:isInArea(part:getArea(), character) then return false end
	return Integration.IsLidOpen(vehicle)
end

if VFluid then
	-- VFluid is the sole transfer owner for this version of the mod.
	VFluid.deferTo = VFluid.deferTo or {}
	VFluid.deferTo.rWaterTrailerB42 = false

	-- Natural surface water requires suction. The large trailer and M967 can fit
	-- the original pump; the small trailer has no pump slot and therefore cannot
	-- draw directly from a river/lake (it may still receive bottles or another tank).
	if VFluid.registerPumpPart then VFluid.registerPumpPart("WaterTankPump") end
	if VFluid.registerPumpRate then
		VFluid.registerPumpRate("RotatorsB42.WaterTrailerTankPump", 2.0)
	end
	if VFluid.updateVehicle then
		VFluid.updateVehicle("TrailerWaterSmall", {
			pumpPart = "WaterTankPump", requiresPump = false,
		})
		VFluid.updateVehicle("TrailerWaterBig", {
			pumpPart = "WaterTankPump", requiresPump = false,
		})
		VFluid.updateVehicle("TrailerM967tankerWater", {
			pumpPart = "WaterTankPump", requiresPump = false,
		})
	end

	-- Convert saves created by the old water-only action. It stored taint as a
	-- boolean beside a clean-looking amount; VFluid needs the contaminant in its
	-- ledger so bottles, tooltips and drinking all agree.
	if type(VFluid.ledger) == "function" and not Integration._ledgerWrapped then
		local previousLedger = VFluid.ledger
		VFluid.ledger = function(vehicle, part, axis)
			local ledger = previousLedger(vehicle, part, axis)
			if Integration.IsCargoTank(vehicle, part) and part:hasModData() then
				local md = part:getModData()
				-- Legacy saves used md.Tainted. Also make an unfiltered tank's
				-- untreated status immediate, including water stored before this fix.
				if md.Tainted == true or not Integration.HasWorkingFilter(vehicle) then
					local changed = false
					local clean = ledger and ledger.Water or 0
					if clean > 0 and VFluid.setLedger then
						local converted = {}
						for name, amount in pairs(ledger) do converted[name] = amount end
						converted.Water = nil
						converted.TaintedWater = (converted.TaintedWater or 0) + clean
						ledger = VFluid.setLedger(vehicle, part, converted)
						changed = true
					end
					if md.Tainted ~= nil then md.Tainted = nil; changed = true end
					if changed and vehicle.transmitPartModData then vehicle:transmitPartModData(part) end
				end
			end
			return ledger
		end
		Integration._ledgerWrapped = true
	end

	-- All transfer directions, including Drain and tank-to-tank, require the lid
	-- on every participating Water Trailer tank to be open.
	if type(VFluid.canTransfer) == "function" and not Integration._transferGateWrapped then
		local previousCanTransfer = VFluid.canTransfer
		VFluid.canTransfer = function(from, to, fluidName)
			if gasPumpRejects(from, fluidName) then
				return false, "fuel pumps dispense Petrol only"
			end
			for _, endpoint in ipairs({ from, to }) do
				local vehicle, part = endpointTank(endpoint)
				if vehicle then Integration.EnsureMulti(vehicle, part, endpoint.axis) end
				if vehicle and not Integration.IsLidOpen(vehicle) then
					return false, "open the tank lid first"
				end
			end
			local targetVehicle = endpointTank(to)
			if targetVehicle and isNaturalWaterEndpoint(from)
					and not Integration.HasWorkingPump(targetVehicle) then
				return false, "requires a working Water Tank Pump"
			end
			return previousCanTransfer(from, to, fluidName)
		end
		Integration._transferGateWrapped = true
	end

	-- Server/SP authority gate. This closes the race where the menu was opened,
	-- the action queued and the lid closed before the first transfer slice arrived.
	if type(VFluid.applyMove) == "function" and not Integration._applyMoveWrapped then
		local previousApplyMove = VFluid.applyMove
		VFluid.applyMove = function(playerObj, srcSpec, dstSpec, amount, fluidName, shares)
			local srcVehicle, srcPart = tankFromSpec(srcSpec)
			local dstVehicle, dstPart = tankFromSpec(dstSpec)
			if srcVehicle then Integration.EnsureMulti(srcVehicle, srcPart) end
			if dstVehicle then Integration.EnsureMulti(dstVehicle, dstPart) end
			if (srcVehicle and not Integration.IsLidOpen(srcVehicle))
					or (dstVehicle and not Integration.IsLidOpen(dstVehicle)) then
				return 0
			end

			-- Re-resolve world supplies on the authority side.  The network spec
			-- contains coordinates rather than the endpoint kind, so this check is
			-- required even though the client menu already calls canTransfer().
			if dstVehicle and srcSpec and srcSpec.kind == "supply"
					and VFluid.resolveEndpoint and VFluid.axisFor then
				local axis = VFluid.axisFor(dstVehicle, dstPart)
				local source = axis and VFluid.resolveEndpoint(srcSpec, axis, playerObj)
				if gasPumpRejects(source, fluidName) then return 0 end
			end

			-- Natural surface water is contaminated. Wells and piped supplies retain
			-- their own composition; only a square carrying the open-water flag changes.
			if dstVehicle and srcSpec and srcSpec.kind == "supply"
					and getWorld and VFluid.isOpenWaterSquare then
				local cell = getWorld() and getWorld():getCell()
				local square = cell and cell:getGridSquare(srcSpec.x, srcSpec.y, srcSpec.z or 0)
				if square and VFluid.isOpenWaterSquare(square) then
					if not Integration.HasWorkingPump(dstVehicle) then return 0 end
					fluidName, shares = "TaintedWater", { TaintedWater = 1 }
				end
			end

			-- The original outlet filter purifies water going to a hand container or
			-- the player. It does not rewrite what remains inside the tank.
			if srcVehicle and dstSpec
					and (dstSpec.kind == "item" or dstSpec.kind == "mouth")
					then
				fluidName, shares = outletComposition(srcVehicle, fluidName, shares)
			end

			return previousApplyMove(playerObj, srcSpec, dstSpec, amount, fluidName, shares)
		end
		Integration._applyMoveWrapped = true
	end

	-- Direct drinking and washing use dedicated VFluid gates rather than
	-- canTransfer, so they receive the same lid rule explicitly.
	if type(VFluid.canDrink) == "function" and not Integration._drinkGateWrapped then
		local previousCanDrink = VFluid.canDrink
		VFluid.canDrink = function(vehicle, part, axis)
			if Integration.IsCargoTank(vehicle, part) and not Integration.IsLidOpen(vehicle) then
				return false, "lid closed"
			end
			return previousCanDrink(vehicle, part, axis)
		end
		Integration._drinkGateWrapped = true
	end

	if type(VFluid.holdsOnlyWater) == "function" and not Integration._washGateWrapped then
		local previousHoldsOnlyWater = VFluid.holdsOnlyWater
		VFluid.holdsOnlyWater = function(vehicle, part, axis)
			if Integration.IsCargoTank(vehicle, part) and not Integration.IsLidOpen(vehicle) then
				return false
			end
			return previousHoldsOnlyWater(vehicle, part, axis)
		end
		Integration._washGateWrapped = true
	end
end

-- SP and server-side timed actions write their endpoints directly rather than
-- going through applyMove. Patch the common action so the lid and filter behave
-- identically on every machine.
if VFluidTransferAction then
	if type(VFluidTransferAction.isValid) == "function" and not Integration._actionGateWrapped then
		local previousIsValid = VFluidTransferAction.isValid
		function VFluidTransferAction:isValid()
			local part = self:getPart()
			if Integration.IsCargoTank(self.vehicle, part)
					and not Integration.IsLidOpen(self.vehicle) then return false end
			if Integration.IsCargoTank(self.vehicle, part)
					and self.direction == "supply"
					and gasPumpRejects(self.src or self.supplyEp, self:movingFluid()) then
				return false
			end
			if Integration.IsCargoTank(self.vehicle, part)
					and self.direction == "supply" and isNaturalWaterEndpoint(self.src)
					and not Integration.HasWorkingPump(self.vehicle) then return false end
			local targetVehicle = self.targetPart and self.targetPart:getVehicle()
			if Integration.IsCargoTank(targetVehicle, self.targetPart)
					and not Integration.IsLidOpen(targetVehicle) then return false end
			return previousIsValid(self)
		end
		Integration._actionGateWrapped = true
	end

	if type(VFluidTransferAction.movingFluid) == "function"
			and not Integration._actionFluidWrapped then
		local previousMovingFluid = VFluidTransferAction.movingFluid
		function VFluidTransferAction:movingFluid()
			local fluidName = previousMovingFluid(self)
			local vehicle = actionOutletVehicle(self)
			if vehicle then fluidName = outletComposition(vehicle, fluidName, nil) end
			return fluidName
		end
		Integration._actionFluidWrapped = true
	end

	if type(VFluidTransferAction.movingMixture) == "function"
			and not Integration._actionMixtureWrapped then
		local previousMovingMixture = VFluidTransferAction.movingMixture
		function VFluidTransferAction:movingMixture()
			local shares = previousMovingMixture(self)
			local vehicle = actionOutletVehicle(self)
			if vehicle then
				local _, treated = outletComposition(vehicle, nil, shares)
				return treated
			end
			return shares
		end
		Integration._actionMixtureWrapped = true
	end
end
