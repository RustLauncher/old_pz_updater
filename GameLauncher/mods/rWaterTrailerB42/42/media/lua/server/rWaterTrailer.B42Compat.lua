-- Server commands formerly supplied by RotatorsLib.

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "rWaterTrailerB42" or not args then
        return
    end

    if command == "SetVehicleHeadlights" then
        local vehicle = getVehicleById(args.vehicleId)
        if vehicle and type(args.set) == "boolean" then
            vehicle:setHeadlightsOn(args.set)
        end
    elseif command == "SetVehicleBattery" then
        local vehicle = getVehicleById(args.vehicleId)
        local part = vehicle and vehicle:getPartById(args.partId or "Battery")
        local item = part and part:getInventoryItem()
        if item and type(args.battery) == "number" then
            item:setUsedDelta(args.battery)
            vehicle:transmitPartUsedDelta(part)
        end
    elseif command == "SpillFluid" then
        local tractor = player and player:getVehicle()
        local vehicle = getVehicleById(args.vehicleId)
        local part = vehicle and vehicle:getPartById(args.partId)
        local loss = tonumber(args.amount) or 0
        -- Re-derive every condition on the server. A client may request only the
        -- small periodic loss used by the driving mechanic, never an arbitrary drain.
        if not tractor or not tractor:isDriver(player) or tractor:getVehicleTowing() ~= vehicle then return end
        if math.abs(tractor:getCurrentSpeedKmHour()) < 5 then return end
        if loss <= 0 or loss > 10 then return end
        if not (rWaterTrailer and rWaterTrailer.VFluid
                and rWaterTrailer.VFluid.IsCargoTank(vehicle, part)
                and rWaterTrailer.VFluid.IsLidOpen(vehicle)) then return end
        local endpoint = VFluid and VFluid.transferEndpointFor
            and VFluid.transferEndpointFor(vehicle, part)
        if endpoint then
            endpoint.set(math.max(0, endpoint.get() - loss))
            if endpoint.sync then endpoint.sync() end
        end
    end
end)
