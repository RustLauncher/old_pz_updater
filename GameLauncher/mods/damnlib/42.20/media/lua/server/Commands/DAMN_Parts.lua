--[[
    This file is part of that DAMN Library (Workshop ID 3171167894) authored by KI5 / bikinihorst.
    No permission is given for redistribution, repacking or modifying this or other files contained within the named
    workshop item, regardless of visibility or target community size, except if explicitly allowed by the author.
    TIS / Steam modding policy: https://projectzomboid.com/blog/modding-policy/
    This mod is "On Lockdown": https://theindiestone.com/forums/index.php?/topic/2530-mod-permissions/#findComment-36479
]]--

DAMN = DAMN or {};
DAMN.ServerHandlers = DAMN.ServerHandlers or {};

-- handlers

function DAMN.ServerHandlers.silentPartInstall(playerObj, args)
	local item = args["item"];
	local part = args["part"];

	if args["_vehicle"] and part and item
	then
		if DAMN["commandsDebug"]
		then
			DAMN:log("DAMN.ServerHandlers.silentPartInstall(" .. playerObj:getUsername() .. ", " .. part .. ", " .. item .. ")");
		end

		item = instanceItem(item);
		part = args["_vehicle"]:getPartById(part);

		if part and item
		then
			part:setInventoryItem(item);
			args["_vehicle"]:transmitPartItem(part);

			local installTable = part:getTable("install");

			if installTable and installTable["complete"]
			then
				VehicleUtils.callLua(installTable["complete"], args["_vehicle"], part);
			end

			part:setRandomCondition(item);

            DAMN.Parts:fixPropanePartCondition(part, args["part"]);

			part:doInventoryItemStats(part:getInventoryItem(), part:getMechanicSkillInstaller());

			local wheelIndex = part:getWheelIndex();

			if wheelIndex ~= nil and wheelIndex > -1
			then
				part:setContainerContentAmount(ZombRand(25, 35));
			end

			args["_vehicle"]:transmitPartCondition(part);
			args["_vehicle"]:transmitPartModData(part);
		elseif DAMN["commandsDebug"]
		then
			DAMN:log(" -> no item generated");
		end
	elseif DAMN["commandsDebug"]
	then
		DAMN:log(" -> vehicle, part or item missing");
	end
end

function DAMN.ServerHandlers.syncPartAnimation(playerObj, args)
    local players = getOnlinePlayers();

    if players and args["animation"]
    then
        local vehicle = getVehicleById(args["vehicle"]);

        if vehicle and DAMN:vehicleIsManaged(vehicle:getScript():getFullName())
        then
            --local vehicleSquare = vehicle:getSquare();
            --local triggeredBy = playerObj:getDisplayName();

            for i = 0, players:size() - 1
            do
                local onlinePlayer = players:get(i);

                if onlinePlayer --and onlinePlayer:getDisplayName() ~= triggeredBy
                then
                    --local distance = vehicleSquare:DistToProper(onlinePlayer:getSquare());

                    --if onlinePlayer and distance and distance <= 150
                    --then
                        --DAMN:log(" - sending command to user " .. tostring(onlinePlayer:getDisplayName())
                            --.. " (distance: " .. tostring(distance) .. ")"
                        --);

                        sendServerCommand(onlinePlayer, "that_damn_lib", "playPartAnimation", {
                            vehicleId = args["vehicle"],
                            partId = args["part"],
                            animation = args["animation"],
                        });
                    --else
                        --DAMN:log(" - user " .. tostring(onlinePlayer:getDisplayName()) .. " too far away (distance: " .. tostring(distance) .. ")");
                    --end
                --else
                    --DAMN:log(" - skipping because user [" .. tostring(triggeredBy) .. "] triggered the event or is offline");
                end
            end
        end
    end
end