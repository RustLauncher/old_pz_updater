--[[
    This file is part of that DAMN Library (Workshop ID 3171167894) authored by KI5 / bikinihorst.
    No permission is given for redistribution, repacking or modifying this or other files contained within the named
    workshop item, regardless of visibility or target community size, except if explicitly allowed by the author.
    TIS / Steam modding policy: https://projectzomboid.com/blog/modding-policy/
    This mod is "On Lockdown": https://theindiestone.com/forums/index.php?/topic/2530-mod-permissions/#findComment-36479
]]--

DAMN = DAMN or {};
DAMN.ServerHandlers = DAMN.ServerHandlers or {};

-- helpers

function DAMN:setVehicleModData(vehicle, data, skipTransmit)
    if DAMN["modDataDebug"]
    then
        DAMN:log("DAMN.BackCompat:setVehicleModData() -> Setting vehicle moddata");
    end

    local modData = vehicle:getModData();

    for k, v in pairs(data)
    do
        if k ~= "_vehicleId" and k ~= "contentAmount"
        then
            if DAMN["modDataDebug"]
            then
                DAMN:log("- saving " .. tostring(k) .. " = " .. tostring(v));
            end

            modData[k] = v;
        end
    end

    if not skipTransmit
    then
        vehicle:transmitModData();
    end

    return modData;
end

-- handlers

function DAMN.ServerHandlers.setPartModData(playerObj, args)
	local vehicle = args["_vehicle"] or getVehicleById(args["vehicle"]);

	if vehicle and args.data
	then
		local part = vehicle:getPartById(args.part);

		if part
		then
			local modData = part:getModData();

			for key, value in pairs(args.data)
			do
				modData[key] = value;
			end

			vehicle:transmitPartModData(part);
		end
	end
end

function DAMN.ServerHandlers.setVehicleData(playerObj, args)
	if DAMN["commandsDebug"]
	then
		DAMN:log("DAMN.ServerHandlers.setVehicleData(" .. playerObj:getUsername() .. ", " .. args["_vehicleId"] .. ")");
	end

    if args["_vehicle"]
	then
		DAMN:setVehicleModData(args["_vehicle"], args);
	elseif DAMN["commandsDebug"]
	then
		DAMN:log(" -> unable to find vehicle");
	end
end