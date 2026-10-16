--[[
    This file is part of that DAMN Library (Workshop ID 3171167894) authored by KI5 / bikinihorst.
    No permission is given for redistribution, repacking or modifying this or other files contained within the named
    workshop item, regardless of visibility or target community size, except if explicitly allowed by the author.
    TIS / Steam modding policy: https://projectzomboid.com/blog/modding-policy/
    This mod is "On Lockdown": https://theindiestone.com/forums/index.php?/topic/2530-mod-permissions/#findComment-36479
]]--

DAMN = DAMN or {};
DAMN.ClientHandlers = DAMN.ClientHandlers or {};

-- handlers

function DAMN.ClientHandlers.playPartAnimation(args)
    local vehicle = getVehicleById(args["vehicleId"]);

    if vehicle
    then
        local part = vehicle:getPartById(args["partId"]);

        if part
        then
            vehicle:playPartAnim(part, args["animation"]);

            if args["animation"] == "Closed" or args["animation"] == "Opened"
            then
                local player = getPlayer();
                local seat = vehicle:getSeat(player);

                vehicle:playPartSound(part, player, args["animation"]);

                if seat
                then
                    vehicle:playPassengerAnim(seat, (args["animation"] == "Opened"
                        and "openDoor"
                        or "closeDoor"
                    ), player);
                else
                    vehicle:playActorAnim(part, args["animation"], player);
                end
            end
        end
    end
end