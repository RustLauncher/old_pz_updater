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

function DAMN.ServerHandlers.savePartsCondition(playerObj, args)
	if DAMN["commandsDebug"]
	then
		DAMN:log("DAMN.ServerHandlers.savePartsCondition(" .. playerObj:getUsername() .. ", " .. args["_vehicleId"] .. ", " .. tostring(args["_vehicle"]) .. ")");
	end

    if args["_vehicle"]
	then
		for i = 0, args["_vehicle"]:getPartCount() -1
		do
			local part = args["_vehicle"]:getPartByIndex(i);

			if part -- DAMN.Parts:partIsInstalled(part)
			then
                DAMN.Parts:fixPropanePartCondition(part, part:getId());

				local modData = part:getModData();
				local condition = not args["erase"]
					and part:getCondition()
					or nil;

				modData["saveCond"] = condition; -- backwards compatibility with older armor code
				modData["damn:savedCondition"] = condition;

				if DAMN["commandsDebug"]
				then
					DAMN:log(" - " .. tostring(part:getId()) .. " = " .. tostring(condition));
				end

				args["_vehicle"]:transmitPartModData(part);
			end
		end
	elseif DAMN["commandsDebug"]
	then
		DAMN:log(" -> unable to find vehicle");
	end
end

function DAMN.ServerHandlers.updatePartConditions(playerObj, args)
	if DAMN["commandsDebug"]
	then
		DAMN:log("DAMN.ServerHandlers.updatePartConditions(" .. playerObj:getUsername() .. ", " .. args["_vehicleId"] .. ", " .. tostring(args["_vehicle"]) .. ")");
		DAMN:logArray(args);
	end

	if args["_vehicle"] and args["conditions"]
	then
		for partId, condition in pairs(args["conditions"])
		do
			local part = args["_vehicle"]:getPartById(partId);

			if part
			then
				part:setCondition(tonumber(condition));
				part:doInventoryItemStats(part:getInventoryItem(), part:getMechanicSkillInstaller());

				args["_vehicle"]:transmitPartCondition(part);
			end
		end
	end
end