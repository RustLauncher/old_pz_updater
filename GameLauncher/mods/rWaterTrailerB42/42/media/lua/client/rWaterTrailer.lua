require "ISUI/ISToolTip"

require "Vehicles/ISUI/ISVehicleMechanics"
require "Vehicles/ISUI/ISVehicleMenu"
require "Vehicles/ISUI/ISVehiclePartMenu"
require "Vehicles/TimedActions/ISAddGasolineToVehicle"
require "Vehicles/TimedActions/ISTakeGasolineFromVehicle"
require "Vehicles/TimedActions/ISCloseVehicleDoor"
require "Vehicles/TimedActions/ISOpenVehicleDoor"
require "Vehicles/TimedActions/ISAttachTrailerToVehicle"
require "Vehicles/TimedActions/ISDetachTrailerFromVehicle"
require "Vehicles/ISVehicleTrailerUtils"

require "TimedActions/rWaterTrailer/rTransferWater"

require "luautils"
rWaterTrailer = rWaterTrailer or {}
require "rWaterTrailer.B42Compat"

rWaterTrailer.Hook = rWaterTrailer.Hook or {}
local rWaterTrailerCompat = rWaterTrailer.Compat
local W900_WATER_SEARCH_RADIUS = 8
local W900_TANKER_WATER_SEARCH_RADIUS = 10

local function HasVFluid()
	return VFluid ~= nil and VFluid.CAPS ~= nil and VFluid.CAPS.transfer == 1
end

local function IsW900SemiTruck(vehicle)
	if not vehicle or not vehicle.getScript then
		return false
	end

	local fullName = vehicle:getScript():getFullName()
	return string.find(fullName, "^Base%.SemiTruck") ~= nil
end

local function GetW900WaterAttachments(waterTrailer)
	local script = waterTrailer and waterTrailer:getScript()
	local scriptName = script and script:getFullName()
	if scriptName == "Base.SemiTrailerCistern"
		or scriptName == "RotatorsSemiB42.TrailerM967tankerWater" then
		-- These are true semitrailers.  Use the fifth-wheel pair so the W900
		-- does not attach at its rear bumper and lift its back axle.
		return "trailerTruck", "trailerTruck"
	end
	return "trailer", "trailer"
end

local function IsW900WaterCandidate(vehicle)
	if rWaterTrailer.GetWaterStorage(vehicle) then
		return true
	end

	local script = vehicle and vehicle:getScript()
	return script and script:getFullName() == "RotatorsSemiB42.TrailerM967tankerWater"
end

local function IsW900SmallWaterTrailer(vehicle)
	local script = vehicle and vehicle:getScript()
	return script and script:getFullName() == "RotatorsB42.TrailerWaterSmall"
end

local function GetW900WaterSearchRadius(vehicle)
	local script = vehicle and vehicle:getScript()
	if script and script:getFullName() == "RotatorsSemiB42.TrailerM967tankerWater" then
		return W900_TANKER_WATER_SEARCH_RADIUS
	end
	return W900_WATER_SEARCH_RADIUS
end

local function FindW900WaterTrailer(tractor)
	local square = tractor and tractor:getSquare()
	if not square then
		return nil
	end

	local closest
	local closestDistance = math.huge
	local seen = {}
	-- Keep detection forgiving; the attach action walks the character to the
	-- tractor's real hitch point before sending the attach command.
	local function ConsiderVehicle(object)
		if not object or not instanceof(object, "BaseVehicle") then
			return
		end

		local objectId = object:getId()
		if seen[objectId] then
			return
		end
		seen[objectId] = true

		if object ~= tractor
			and not object:getVehicleTowing()
			and not object:getVehicleTowedBy()
			and IsW900WaterCandidate(object) then
			local dx = object:getX() - tractor:getX()
			local dy = object:getY() - tractor:getY()
			local distance = dx * dx + dy * dy
			local searchRadius = GetW900WaterSearchRadius(object)
			local maxDistance = searchRadius * searchRadius
			if distance <= maxDistance and distance < closestDistance then
				closest = object
				closestDistance = distance
			end
		end
	end

	local cell = getCell()
	for y = square:getY() - W900_TANKER_WATER_SEARCH_RADIUS, square:getY() + W900_TANKER_WATER_SEARCH_RADIUS do
		for x = square:getX() - W900_TANKER_WATER_SEARCH_RADIUS, square:getX() + W900_TANKER_WATER_SEARCH_RADIUS do
			local square2 = cell and cell:getGridSquare(x, y, square:getZ())
			if square2 then
				local movingObjects = square2:getMovingObjects()
				if movingObjects then
					for i = 1, movingObjects:size() do
						ConsiderVehicle(movingObjects:get(i - 1))
					end
				end
				ConsiderVehicle(square2:getVehicleContainer())
			end
		end
	end

	return closest
end

local function EnsureW900WaterAttachSlice(radial, player, vehicleA, vehicleB)
	if not radial or not radial.slices then
		return false
	end

	local aName = ISVehicleMenu.getVehicleDisplayName(vehicleA)
	local bName = ISVehicleMenu.getVehicleDisplayName(vehicleB)
	local text = getText("ContextMenu_Vehicle_AttachTrailer", bName, aName)

	for index, slice in ipairs(radial.slices) do
		local command = slice and slice.command
		local callback = command and command[1]
		if command and command[3] == vehicleA and callback == rWaterTrailer.AttachW900WaterTrailer
			and command[4] == vehicleB then
			return true
		end

		if command and command[3] == vehicleA and callback == ISVehicleMenu.onAttachTrailer then
			local nativeAttachmentA = command[4]
			local nativeAttachmentB = command[5]
			if IsW900SmallWaterTrailer(vehicleB) then
				-- The Small trailer already has a valid native trailer option on
				-- semi-trucks.  Do not add our fallback beside it.
				return true
			end
			local nativeVehicleB = nativeAttachmentA and nativeAttachmentB
				and ISVehicleTrailerUtils.getTowableVehicleNear(vehicleA:getSquare(), vehicleA, nativeAttachmentA, nativeAttachmentB)
			local nativeMatchesWater = nativeVehicleB == vehicleB
			if not nativeMatchesWater and not nativeVehicleB and IsW900WaterCandidate(vehicleB) then
				-- Some water trailers pass the menu's first compatibility check but
				-- are not returned by its second nearby-vehicle lookup.  The custom
				-- search already identified this exact water trailer, so reuse the
				-- native slice instead of adding a duplicate.
				nativeMatchesWater = true
			end
			if not nativeMatchesWater and nativeAttachmentA and nativeAttachmentB
				and IsW900WaterCandidate(vehicleB) then
				nativeMatchesWater = vehicleA:canAttachTrailer(vehicleB, nativeAttachmentA, nativeAttachmentB)
			end
			if nativeMatchesWater then
				-- Keep one menu entry, but route it through the W900 fifth-wheel
				-- action.  The normal trailer attachment remains available to the
				-- Oshkosh when its own menu is opened.
				command[1] = rWaterTrailer.AttachW900WaterTrailer
				command[2] = player
				command[3] = vehicleA
				command[4] = vehicleB
				command[5] = nil
				command[6] = nil
				command[7] = nil
				radial:setSliceText(index, text)
				return true
			end
		end
	end

	return false
end

-- Keep the normal walk/animation and attachment pair.  Only the second
-- nearby-vehicle search is bypassed when vanilla rejects the water trailer.
function rWaterTrailer.AttachW900WaterTrailer(player, vehicleA, vehicleB)
	if not player or not vehicleA or not vehicleB then
		return
	end

	local attachmentA, attachmentB = GetW900WaterAttachments(vehicleB)
	local action = ISAttachTrailerToVehicle:new(player, vehicleA, vehicleB, attachmentA, attachmentB)
	action.attachTrailer = function(self)
		local args =
		{
			vehicleA = self.vehicleA:getId(),
			vehicleB = self.vehicleB:getId(),
			attachmentA = self.attachmentA,
			attachmentB = self.attachmentB,
		}
		sendClientCommand(self.character, "vehicle", "attachTrailer", args)
	end

	ISVehicleTrailerUtils.walkToTrailer(player, vehicleA, attachmentA, action)
end

-- Replace the small event bridge that used to be provided by RotatorsLib.
if not ISVehicleMenu._rWaterTrailerB42Hooked then
	local ISVM_onToggleHeadlights = ISVehicleMenu.onToggleHeadlights
	function ISVehicleMenu.onToggleHeadlights(player, ...)
		ISVM_onToggleHeadlights(player, ...)
		local vehicle = player:getVehicle()
		if vehicle then
			rWaterTrailerCompat.Events.Run("Vehicle.ToggleHeadlights", player, vehicle)
		end
	end

	local ISAttach_perform = ISAttachTrailerToVehicle.perform
	function ISAttachTrailerToVehicle:perform(...)
		local character, vehicleA, vehicleB = self.character, self.vehicleA, self.vehicleB
		ISAttach_perform(self, ...)
		if character and vehicleA and vehicleB then
			rWaterTrailerCompat.Events.Run("Vehicle.AttachVehicle", character, vehicleA, vehicleB)
		end
	end

	local ISDetach_perform = ISDetachTrailerFromVehicle.perform
	function ISDetachTrailerFromVehicle:perform(...)
		local character, vehicle = self.character, self.vehicle
		local vehicleB = vehicle and vehicle:getVehicleTowing()
		ISDetach_perform(self, ...)
		if character and vehicle and vehicleB then
			rWaterTrailerCompat.Events.Run("Vehicle.DetachVehicle", character, vehicle, vehicleB)
		end
	end

	ISVehicleMenu._rWaterTrailerB42Hooked = true
end

-- main hooks --

local ISVM_FillPartMenu = ISVehicleMenu.FillPartMenu
function ISVehicleMenu.FillPartMenu(playerIdx, context, radial, trailer, ...)
	ISVM_FillPartMenu(playerIdx, context, radial, trailer, ...)

	local tank = rWaterTrailer.GetWaterStorage(trailer)
	if not tank then
		return
	end

	local player = getSpecificPlayer(playerIdx)
	local playerItems = player:getInventory():getItems() -- non-recursive, aka main inventory only --

	rWaterTrailer.Hook.FillPartMenu(player, playerItems, trailer, tank, context, radial)
end

local ISVM_doTowingMenu = ISVehicleMenu.doTowingMenu
function ISVehicleMenu.doTowingMenu(player, trailer, radial, ...)
	ISVM_doTowingMenu(player, trailer, radial, ...)

	-- Keep the option on the W900 side only. Vanilla already creates the normal
	-- option when the tank advertises its trailer attachment; add one fallback
	-- only when that native option is absent.
	if radial then
		local vehicleA
		local vehicleB

		if IsW900SemiTruck(trailer) and not trailer:getVehicleTowing() and not trailer:getVehicleTowedBy() then
			vehicleA = trailer
			vehicleB = FindW900WaterTrailer(trailer)
		end

		if vehicleA and vehicleB and not EnsureW900WaterAttachSlice(radial, player, vehicleA, vehicleB) then
			local aName = ISVehicleMenu.getVehicleDisplayName(vehicleA)
			local bName = ISVehicleMenu.getVehicleDisplayName(vehicleB)
			local text = getText("ContextMenu_Vehicle_AttachTrailer", bName, aName)
			radial:addSlice(text, getTexture("media/ui/ZoomIn.png"), rWaterTrailer.AttachW900WaterTrailer, player, vehicleA, vehicleB)
		end
	end

	local tank = rWaterTrailer.GetWaterStorage(trailer)
	if not tank then
		return
	end

	local playerItems = player:getInventory():getItems() -- non-recursive, aka main inventory only --

	rWaterTrailer.Hook.DoTowingMenu(player, playerItems, trailer, tank, radial)
end

local ISVM_renderPartDetail = ISVehicleMechanics.renderPartDetail
function ISVehicleMechanics:renderPartDetail(part, ...)
	-- VFluid owns the contents-aware mechanics display when installed. Calling the
	-- previously wrapped function preserves both vanilla and VFluid's own panel.
	if HasVFluid() then
		return ISVM_renderPartDetail(self, part, ...)
	end

	local vehicle = part:getVehicle()
	local tank = rWaterTrailer.GetWaterStorage(vehicle)
	if tank and part:getId() == tank:getId() then
		local x = self.xCarTexOffset + (self.width - 10 - self.xCarTexOffset) / 2 - 60;
		local y = self:titleBarHeight() + 10 + getTextManager():getFontHeight(UIFont.Medium) + 5;
		local h = getTextManager():getFontHeight(UIFont.Small)
		-- The vanilla vehicle-script line occupies the top of this panel.
		-- Start this add-on block two rows lower to keep both UI layers separate.
		y = y + h * 2

		rWaterTrailer.Hook.RenderPartDetail(self, vehicle, part, x, y, h)
	else
		ISVM_renderPartDetail(self, part, ...)
	end
end

---

local function CanDrawNaturalWater(trailer)
	return rWaterTrailer.VFluid
		and rWaterTrailer.VFluid.HasWorkingPump
		and rWaterTrailer.VFluid.HasWorkingPump(trailer)
end

local function GetNaturalWaterEndpoint(trailer, tank)
	if not (HasVFluid() and VFluid.axisFor and VFluid.naturalWaterEndpoint) then return nil end
	-- Do not scan or expose open-water sources for the small trailers: they do
	-- not have a pump slot. The same guard also hides the action when a pump on
	-- a large trailer or M967 is absent or broken.
	if not CanDrawNaturalWater(trailer) then return nil end
	local axis = VFluid.axisFor(trailer, tank)
	local center = trailer and trailer:getCurrentSquare()
	local cell = getWorld() and getWorld():getCell()
	if not axis or not center or not cell then return nil end
	local best, bestDistance
	for dx = -rWaterTrailer.GetPumpRange(trailer), rWaterTrailer.GetPumpRange(trailer) do
		for dy = -rWaterTrailer.GetPumpRange(trailer), rWaterTrailer.GetPumpRange(trailer) do
			local square = cell:getGridSquare(center:getX() + dx, center:getY() + dy, center:getZ())
			local endpoint = square and VFluid.naturalWaterEndpoint(square, axis)
			local distance = dx * dx + dy * dy
			if endpoint and (bestDistance == nil or distance < bestDistance) then
				best, bestDistance = endpoint, distance
			end
		end
	end
	return best, axis
end

function rWaterTrailer.OnFillFromNaturalWater(player, trailer, tank)
	if not rWaterTrailer.IsLidOpen(trailer) then return end
	local source, axis = GetNaturalWaterEndpoint(trailer, tank)
	local target = VFluid and VFluid.transferEndpointFor and VFluid.transferEndpointFor(trailer, tank)
	if not source or not target or not axis then return end
	local ok = VFluid.canTransfer(source, target, "TaintedWater")
	if not ok then return end
	if VFluidMenu and VFluidMenu.onFillFromSupply then
		VFluidMenu.onFillFromSupply(player, tank, source, "TaintedWater")
	end
end

function rWaterTrailer.Hook.FillPartMenu(player, playerItems, trailer, tank, context, radial)
	local item = nil

	local contextOption
	local contextMenu
	local waterToTank = {}
	local waterToItem = {}

	local lid = trailer:getPartById("WaterTankLid")
	local tankLidOpen = rWaterTrailer.IsLidOpen(trailer)

	if lid and lid:getInventoryItem() then
		local lidText = lid:getDoor():isOpen() and "ContextMenu_Close_TankLid" or "ContextMenu_Open_TankLid"
		if radial then
			radial:addSlice(getText(lidText), getTexture("media/ui/rWaterTrailer/vehicle_tank_lid.png"), rWaterTrailer.OnLidOpenClose, player, trailer, lid)
		elseif context then
			context:addOption(getText(lidText), player, rWaterTrailer.OnLidOpenClose, trailer, lid)
		end
	end

	-- VFluid supplies safe, composition-aware fill/drain/drink/transfer actions.
	-- Keep this mod's lid and natural-water actions, but do not add the other
	-- legacy water-only actions too. VFluid intentionally omits supply fills from
	-- right-click menus, while Water Trailer has always exposed one here.
	if HasVFluid() then
		local source, axis = GetNaturalWaterEndpoint(trailer, tank)
		if source and axis then
			local target = VFluid.transferEndpointFor(trailer, tank)
			local ok, why = false, nil
			if tankLidOpen and target then
				ok, why = VFluid.canTransfer(source, target, "TaintedWater")
			elseif not tankLidOpen then
				why = "open the tank lid first"
			end
			if radial and ok then
				radial:addSlice(getText("ContextMenu_Add_Water_To_Trailer"),
					getTexture("media/ui/rWaterTrailer/vehicle_water_pump.png"),
					rWaterTrailer.OnFillFromNaturalWater, player, trailer, tank)
			elseif context then
				local option = context:addOption(getText("ContextMenu_Add_Water_To_Trailer"),
					player, rWaterTrailer.OnFillFromNaturalWater, trailer, tank)
				if not ok then
					option.notAvailable = true
					if why and why ~= "" then
						local tooltip = ISToolTip:new()
						tooltip.description = tostring(why)
						option.toolTip = tooltip
					end
				end
			end
		end
		return
	end

	if tankLidOpen and tank:getContainerContentAmount() < tank:getContainerCapacity() then -- tank not full --
		if rWaterTrailer.IsNearRiver(trailer) then
			if radial then
				radial:addSlice(getText("ContextMenu_Add_Water_To_Trailer"), getTexture("media/ui/rWaterTrailer/vehicle_water_pump.png"), rWaterTrailer.OnTransferWater, player, trailer, tank, "<-", "void", tank:getArea())
			elseif context then
				context:addOption(getText("ContextMenu_Add_Water_To_Trailer"), player, rWaterTrailer.OnTransferWater, trailer, tank, "<-", "void", tank:getArea())
			end
		end

		for idx = 0,playerItems:size()-1 do
			item = playerItems:get(idx)
			if rWaterTrailer.IsWaterItemState(item, "not empty") then
				table.insert(waterToTank, item)
			end
		end
	end

	if tankLidOpen and tank:getContainerContentAmount() > 0 then -- tank not empty --
		if radial then
			radial:addSlice(getText("ContextMenu_Drain_Tank"), getTexture("media/ui/rWaterTrailer/vehicle_drain_tank.png"), rWaterTrailer.OnTransferWater, player, trailer, tank, "->", "void", tank:getArea())
		elseif context then
			context:addOption(getText("ContextMenu_Drain_Tank"), player, rWaterTrailer.OnTransferWater, trailer, tank, "->", "void", tank:getArea())
		end

		if rWaterTrailer.IsTankWaterDrinkable(trailer, tank) then
			local waterNeed = math.floor((player:getStats():get(CharacterStat.THIRST) + 0.005) / 0.1)
			local waterHave = math.min(waterNeed, tank:getContainerContentAmount())
			rWaterTrailerCompat.dhalo(player, "waterNeed=%d waterHave=%d", waterNeed, waterHave)

			if waterHave > 0 then
				if radial then
					radial:addSlice(getText("ContextMenu_Drink"), getTexture("media/ui/rWaterTrailer/vehicle_faucet.png"), rWaterTrailer.OnTransferWater, player, trailer, tank, "->", player, tank:getArea())
				else
					context:addOption(getText("ContextMenu_Drink"), player, rWaterTrailer.OnTransferWater, trailer, tank, "->", player, tank:getArea())
				end
			end
		end

		for idx = 0,playerItems:size()-1 do
			item = playerItems:get(idx)
			if rWaterTrailer.IsWaterItemState(item, "not full") or rWaterTrailer.IsWaterItemState(item, "empty") then
				table.insert(waterToItem, item)
			end
		end
	end

	if #waterToItem > 0 then
		if radial then
			local text = getText("ContextMenu_VehicleAddWaterToItem")
			local texture = getTexture("media/ui/rWaterTrailer/vehicle_take_water.png")
			local func = rWaterTrailer.OnRadialSubMenu

			if #waterToItem == 1 then
				waterToItem = waterToItem[1]
				text = getText("ContextMenu_Fill") .. waterToItem:getName() .. getText("ContextMenu_VehicleAddWaterToSingleItem")
				texture = waterToItem:getTexture()
				func = rWaterTrailer.OnTransferWater
			end

			radial:addSlice(text, texture, func, player, trailer, tank, "->", waterToItem)
		elseif context then
			contextOption = context:addOption(getText("ContextMenu_Fill"), player, nil)
			contextMenu = ISContextMenu:getNew(context)
			context:addSubMenu(contextOption, contextMenu)

			for idx,item in ipairs(waterToItem) do
				rWaterTrailer.SetWaterTooltip(contextMenu:addOption(item:getName(), player, rWaterTrailer.OnTransferWater, trailer, tank, "->", item), item)
			end
		end
	end

	if #waterToTank > 0 then
		if radial then
			local text = getText("ContextMenu_AddWaterFromItem")
			local texture = getTexture("media/ui/rWaterTrailer/vehicle_add_water.png")
			local func = rWaterTrailer.OnRadialSubMenu

			if #waterToTank == 1 then
				waterToTank = waterToTank[1]
				text = getText("ContextMenu_VehicleAddSingleWater") .. waterToTank:getName()
				texture = waterToTank:getTexture()
				func = rWaterTrailer.OnTransferWater
			end

			radial:addSlice(text, texture, func, player, trailer, tank, "<-", waterToTank)
		elseif context then
			contextOption = context:addOption(luautils.trim(getText("ContextMenu_AddWaterFromItem")), player, nil)
			contextMenu = ISContextMenu:getNew(context)
			context:addSubMenu(contextOption, contextMenu)

			for idx,item in ipairs(waterToTank) do
				rWaterTrailer.SetWaterTooltip(contextMenu:addOption(item:getName(), player, rWaterTrailer.OnTransferWater, trailer, tank, "<-", item), item)
			end
		end
	end
end

function rWaterTrailer.Hook.DoTowingMenu(player, playerItems, trailer, tank, radial)
	-- ISVehicleMenu.showRadialMenuOutside() thinks trunks lids on small trailer are doors, due to custom parts names --

	if radial and radial.slices then
		for idx,slice in ipairs(radial.slices) do
			if slice.text == getText("ContextMenu_Open_door") then
				radial:setSliceText(idx, getText("IGUI_OpenTrunk"))
			elseif slice.text == getText("ContextMenu_Close_door") then
				radial:setSliceText(idx, getText("IGUI_CloseTrunk"))
			elseif slice.text == getText("ContextMenu_LockDoor") then
				radial:setSliceText(idx, getText("IGUI_LockTrunk"))
			end
		end
	end
end

function rWaterTrailer.Hook.RenderPartDetail(ui, trailer, tank, x, y, h)
	-- just like vanilla (except debug mode string) --

	local capacity = ui:roundContainerContentAmount(tank) .. " / " .. tank:getContainerCapacity();
	if tank:getItemContainer() then
		capacity = round(tank:getItemContainer():getCapacityWeight(), 2) .. " / " .. tank:getContainerCapacity(self.chr);
	end
	local label = getTextOrNull("IGUI_Vehicle_ContainerCapacity_" .. tank:getContainerContentType(), capacity)
	if not label then
		label = getText("IGUI_Vehicle_ContainerCapacity_Other", tank:getContainerContentType(), capacity)
	end
	if round(tank:getContainerContentAmount(), 2) < 5 then
		ui:drawText(label, x, y, 1, 0, 0, 1);
	else
		ui:drawText(label, x, y, 1, 1, 1, 1);
	end
	y = y + h;

	-- custom --

	if tank:getContainerContentAmount() <= 0 then
		return
	elseif not rWaterTrailer.IsTankWaterDrinkable(trailer, tank) then
		ui:drawText(getText("Tooltip_item_TaintedWater"), x, y, 1, 0.5, 0.5, 1) -- not so sure about that, it might look meh in other langs --
		y = y + h * 2
	else
		ui:drawText(getText("Tooltip_item_DrinkableWater"), x, y, 1, 1, 1, 1) -- hmm --
		y = y + h
	end
end

---

function rWaterTrailer.Find(square, distance)
	for y = square:getY() - distance, square:getY() + distance do
		for x = square:getX() - distance, square:getX() + distance do
			local otherSquare = getCell():getGridSquare(x, y, square:getZ())
			if otherSquare then
				for i=0, otherSquare:getMovingObjects():size()-1 do
					local object = otherSquare:getMovingObjects():get(i)
					local tank = rWaterTrailer.GetWaterStorage(object)
					if object and tank then
						return object
					end
				end
			end
		end
	end
end

function rWaterTrailer.GetWaterStorage(trailer)
	if not trailer or not instanceof(trailer, "BaseVehicle") then
		return nil
	end

	for i=0, trailer:getPartCount()-1 do
		local part = trailer:getPartByIndex(i)
		local category = part:getCategory() or "NOT A CAT"
		if category == "watertank" and part:getInventoryItem() and part:isContainer() and part:getContainerContentType() == "Water Storage" then
			return part
		end
	end

	return nil
end

function rWaterTrailer.GetWaterFilter(trailer)
	if not trailer or not instanceof(trailer, "BaseVehicle") then
		return nil
	end

	local filter = trailer:getPartById("WaterTankFilter")
	if not filter or not filter:getInventoryItem() then
		return nil
	end

	return filter
end

function rWaterTrailer.GetPumpRange(trailer)
	return 6
end

function rWaterTrailer.GetSquares(trailer, mode, param)
	local squares = {}
	if mode ~= nil and mode ~= "" and param ~= nil then
		local trailerSquare = trailer:getCurrentSquare()

		if mode == "range" then -- param=distance
			for y = trailerSquare:getY() - param, trailerSquare:getY() + param do
				for x=trailerSquare:getX() - param, trailerSquare:getX()+ param do
					local square = getCell():getGridSquare(x, y, trailerSquare:getZ())
					if square then
						table.insert(squares, square)
					end
				end
			end
		end
	end

	return squares
end

function rWaterTrailer.GetSquaresRiver(trailer)
	function isWater(square)
		return square ~= nil and square:has(IsoFlagType.water)
	end

	local result = {}
	local squares = rWaterTrailer.GetSquares(trailer, "range", rWaterTrailer.GetPumpRange(trailer))
	for _,square in ipairs(squares) do
		if isWater(square) then
			table.insert(result, square)
		end
	end

	return result
end

function rWaterTrailer.GetSquaresBarrels(trailer)
	function isBarrel(object)
		if not object then
			return false
		end
		if not instanceof(object, "IsoThumpable") then
			return false
		end
		if object:getWaterMax() <= 0 then
			return false
		end

		local prop = object:getProperties()

		if prop and prop:Val("GroupName") == "Water" and prop:Val("CustomName") == "Dispenser" then
			return false
		end

		return true
	end

	local resultSquares = {}
	local resultBarrels = {}
	local squares = rWaterTrailer.GetSquares(trailer, "range", rWaterTrailer.GetPumpRange(trailer))
	for _,square in ipairs(squares) do
		local objects = square:getObjects()
		for o=0, objects:size()-1 do
			local object = objects:get(o)
			if isBarrel(object) then
				table.insert(resultSquares, square)
				table.insert(resultBarrels, object)
			end
		end
	end

	return resultSquares, resultBarrels
end

function rWaterTrailer.SetWaterTooltip(option, item)
	if not item then
		return
	end

	local tooltip = ISToolTip:new()
	local tx = getTextManager():MeasureStringX(tooltip.font, getText("ContextMenu_WaterName") .. ":") + 20
	local fluidContainer = item:getFluidContainer()
	if fluidContainer then
		tooltip.description = string.format("%s: <SETX:%d> %.2f / %.2f", getText("ContextMenu_WaterName"), tx, fluidContainer:getAmount(), fluidContainer:getCapacity())
	elseif instanceof(item, "DrainableComboItem") and item:getUseDelta() then
		tooltip.description = string.format("%s: <SETX:%d> %d / %d", getText("ContextMenu_WaterName"), tx, item:getDrainableUsesInt(), 1.0 / item:getUseDelta() + 0.0001)
	else
		return
	end
	if (fluidContainer and fluidContainer:contains(Fluid.TaintedWater)) or (not fluidContainer and item:isWaterSource() and item:isTaintedWater()) then
		tooltip.description = tooltip.description .. " <BR> <RGB:1,0.5,0.5>" .. getText("Tooltip_item_TaintedWater")
	end

	option.toolTip = tooltip
end

function rWaterTrailer.IsNearRiver(trailer)
	local squares = rWaterTrailer.GetSquaresRiver(trailer)

	return #squares > 0
end

function rWaterTrailer.IsLidOpen(trailer)
	local lid = trailer and trailer:getPartById("WaterTankLid")
	if not lid or not lid:getInventoryItem() then
		return true
	end
	local door = lid:getDoor()
	return not door or door:isOpen()
end

function rWaterTrailer.IsTankWaterDrinkable(vehicle, tank)
	if tank:getContainerContentAmount() <= 0 then
		return false
	end

	if tank:getModData().Tainted then
		local filter = rWaterTrailer.GetWaterFilter(vehicle)
		if not filter or filter:getCondition() <= 0 then
			return false
		end
	end

	return true
end

function rWaterTrailer.IsWaterItemState(item, state) -- because i don't want to research this again, ever --
	if item == nil or state == nil then
		return false
	end

	local fluidContainer = item:getFluidContainer()
	if fluidContainer then
		local isWater = fluidContainer:contains(Fluid.Water) or fluidContainer:contains(Fluid.TaintedWater)
		local amount = fluidContainer:getAmount()
		local capacity = fluidContainer:getCapacity()
		if state == "empty" then
			return item:canStoreWater() and fluidContainer:isEmpty() and not item:isBroken()
		elseif state == "not empty" then
			return item:canStoreWater() and isWater and amount > 0 and not item:isBroken()
		elseif state == "not full" then
			return item:canStoreWater() and isWater and amount < capacity and not item:isBroken()
		elseif state == "full" then
			return item:canStoreWater() and isWater and amount >= capacity and not item:isBroken()
		end
	end

	if state == "empty" and item:canStoreWater() and not item:isWaterSource() and not item:isBroken() then
		return true
	elseif state == "not empty" and item:IsDrainable() and item:canStoreWater() and item:isWaterSource() and not item:isBroken() then
		return true
	elseif state == "not full" and item:IsDrainable() and item:canStoreWater() and item:isWaterSource() and not item:isBroken() and item:getUsedDelta() < 1 then
		return true
	elseif state == "full" and item:IsDrainable() and item:canStoreWater() and item:isWaterSource() and not item:isBroken() and item:getUsedDelta() == 1 then
		return true
	end

	return false
end

function rWaterTrailer.WalkToTarget(player, trailer, target, onFail)
	if instanceof(target, "IsoThumpable") then
		if not luautils.walkAdj(player, target:getSquare(), true) then
		rWaterTrailerCompat.dhalo(player, "WalkToTarget : walkAdj fail")
			return false
		else
		rWaterTrailerCompat.dhalo(player, "WalkToTarget : walkAdj")
		end
	elseif type(target) == "string" then
		rWaterTrailerCompat.dhalo(player, "WalkToTarget : pathToVehicleArea : %s", target)
		local action = ISPathFindAction:pathToVehicleArea(player, trailer, target)
		if onFail then
			action:setOnFail(onFail, player)
		end
		ISTimedActionQueue.add(action)
	else
		rWaterTrailerCompat.dhalo(player, "WalkToTarget : ???")
		target = rWaterTrailer.GetWaterStorage(trailer)
		rWaterTrailer.WalkToTarget(player, trailer, target:getArea(), onFail)
	end
end

rWaterTrailer.DebugMarkers = {}
local function ClearTankDebugMarkers()
	if getWorldMarkers then
		for _,marker in ipairs(rWaterTrailer.DebugMarkers) do
			getWorldMarkers():removeGridSquareMarker(marker)
		end
	end
	rWaterTrailer.DebugMarkers = {}
end

function rWaterTrailer.OnLidOpenClose(player, trailer, lid)
	if player:getVehicle() then
		ISVehicleMenu.onExit(player)
	end

	-- Markers are only a debug aid. Clear any previous tank's markers before
	-- deciding whether this trailer is physically able to draw open water.
	if getDebug() then ClearTankDebugMarkers() end

	-- Tank lids are not key-locked; opening is controlled by the part itself.
	if lid:getDoor() and lid:getDoor():isLocked() then
		lid:getDoor():setLocked(false)
	end

	if lid:getDoor():isOpen() then
		rWaterTrailer.WalkToTarget(player, trailer, lid:getArea())
		ISTimedActionQueue.add(ISCloseVehicleDoor:new(player, trailer, lid))
	else
		rWaterTrailer.WalkToTarget(player, trailer, lid:getArea())
		ISTimedActionQueue.add(ISOpenVehicleDoor:new(player, trailer, lid))

		if getDebug() and CanDrawNaturalWater(trailer) then
			function addMarker(square, r, g, b)
				local marker = getWorldMarkers():addGridSquareMarker(square, r, g, b, true, 0.5)
				marker:setScaleCircleTexture(true);
				table.insert(rWaterTrailer.DebugMarkers, marker)
			end

			local riverSquares = rWaterTrailer.GetSquaresRiver(trailer)
			for _,square in ipairs(riverSquares) do
				addMarker(square, 0, 0, 0.5)
			end
			local barrelSquares, barrels = rWaterTrailer.GetSquaresBarrels(trailer)
			for _,square in ipairs(barrelSquares) do
				addMarker(square, 0, 0.5, 0)
			end

			rWaterTrailerCompat.dprint("riverSquares=%d barrelSquares=%d", #riverSquares, #barrelSquares)
		end
	end
end

function rWaterTrailer.OnRadialSubMenu(player, trailer, tank, flow, items)
	local radial = getPlayerRadialMenu(player:getPlayerNum())

	radial:clear()
	radial:addSlice(getText("IGUI_Emote_Back"), getTexture("media/ui/emotes/back.png"), rWaterTrailerCompat.UI.UpdateAndCall, ISVehicleMenu.showRadialMenu, player)

	for _,item in ipairs(items) do
		radial:addSlice(item:getName(), item:getTexture(), rWaterTrailer.OnTransferWater, player, trailer, tank, flow, item)
	end

	radial:center()
	radial:addToUIManager()
end

function rWaterTrailer.OnTransferWater(player, trailer, tank, flow, item, area)
	if player:getVehicle() then
		ISVehicleMenu.onExit(player)
	end

	if tank and flow and item and rWaterTrailer.IsLidOpen(trailer) then
		rWaterTrailer.WalkToTarget(player, trailer, area or item)
		if item and (instanceof(item, "DrainableComboItem") or instanceof(item, "InventoryItem")) then
			ISVehiclePartMenu.toPlayerInventory(player, item)
		end
		ISTimedActionQueue.add(rTransferWater:new(player, tank, flow, item))
	end
end

-- An open or missing tank lid loses fluid while its towing vehicle moves. The
-- server/SP write goes through VFluid so mixtures keep their real proportions.
function rWaterTrailer.SpillWaterWithoutLid(player)
	local tractor = player and player:getVehicle()
	if not tractor or not tractor:isDriver(player) then
		return
	end

	local trailer = tractor:getVehicleTowing()
	local tank = rWaterTrailer.GetWaterStorage(trailer)
	local lid = trailer and trailer:getPartById("WaterTankLid")
	-- A fitted lid protects the tank only while it is actually closed.
	if not tank or (lid and lid:getInventoryItem() and lid:getDoor() and not lid:getDoor():isOpen()) then
		return
	end

	local speed = math.abs(tractor:getCurrentSpeedKmHour())
	if speed < 5 or tank:getContainerContentAmount() <= 0 then
		return
	end

	-- OnPlayerUpdate frequency depends on frame rate, so use game time instead of ticks.
	local now = getGameTime():getWorldAgeHours() * 3600
	rWaterTrailer.SpillLastAt = rWaterTrailer.SpillLastAt or {}
	local trailerId = trailer:getId()
	local lastAt = rWaterTrailer.SpillLastAt[trailerId]
	if lastAt and now - lastAt < 10 then
		return
	end
	rWaterTrailer.SpillLastAt[trailerId] = now

	local loss = math.max(1, math.floor(speed / 40))
	if isClient() then
		sendClientCommand(player, "rWaterTrailerB42", "SpillFluid", {
			vehicleId = trailerId,
			partId = tank:getId(),
			amount = loss,
		})
	elseif VFluid and VFluid.transferEndpointFor then
		local endpoint = VFluid.transferEndpointFor(trailer, tank)
		if endpoint then
			endpoint.set(math.max(0, endpoint.get() - loss))
			if endpoint.sync then endpoint.sync() end
		end
	end
end

if not rWaterTrailer.SpillHooked then
	Events.OnPlayerUpdate.Add(rWaterTrailer.SpillWaterWithoutLid)
	rWaterTrailer.SpillHooked = true
end

--- Sync Tail Lights ---

function rWaterTrailer.ToggleHeadlights(player, vehicle)
	assert(instanceof(player, "IsoPlayer"))
	assert(instanceof(vehicle, "BaseVehicle"))

	local trailer = vehicle:getVehicleTowing()
	if not trailer or not rWaterTrailer.IsWaterTrailer(trailer) then
		return
	end

	rWaterTrailerCompat.Commands.SendToServer(player, "SetVehicleHeadlights", {vehicleId = trailer:getId(), set = not vehicle:getHeadlightsOn()}, true)
end

function rWaterTrailer.IsWaterTrailer(vehicle)
	if not vehicle or not vehicle.getScript then
		return false
	end

	local fullName = vehicle:getScript():getFullName()
	return fullName == "RotatorsB42.TrailerWaterSmall"
		or fullName == "RotatorsB42.TrailerWaterBig"
		or fullName == "RotatorsSemiB42.TrailerM967tankerWater"
end

function rWaterTrailer.AttachDetachVehicle(player, vehicleA, vehicleB)
	assert(instanceof(player, "IsoPlayer"))
	assert(instanceof(vehicleA, "BaseVehicle"))
	assert(instanceof(vehicleB, "BaseVehicle"))

	if not rWaterTrailer.IsWaterTrailer(vehicleB) then
		return
	end

	local batteryPart = vehicleA:getPartById("Battery")
	if batteryPart then
		local batteryInv = batteryPart:getInventoryItem()
		local batteryVar = batteryInv and batteryInv:getCurrentUsesFloat() or 0
		if batteryInv and batteryVar > 0 then
			rWaterTrailerCompat.Commands.SendToServer(player, "SetVehicleBattery",
			{
				vehicleId = vehicleB:getId(),
				battery = rWaterTrailerCompat.Events.Current == "Vehicle.AttachVehicle" and batteryVar or 0
			}, true)
		end
	end

	rWaterTrailerCompat.Commands.SendToServer(player, "SetVehicleHeadlights",
	{
		vehicleId = vehicleB:getId(),
		set = rWaterTrailerCompat.Events.Current == "Vehicle.AttachVehicle" and vehicleA:getHeadlightsOn() or false
	}, true)
end

rWaterTrailerCompat.Events.On("Vehicle.ToggleHeadlights", rWaterTrailer.ToggleHeadlights)
rWaterTrailerCompat.Events.On("Vehicle.AttachVehicle", rWaterTrailer.AttachDetachVehicle)
rWaterTrailerCompat.Events.On("Vehicle.DetachVehicle", rWaterTrailer.AttachDetachVehicle)
