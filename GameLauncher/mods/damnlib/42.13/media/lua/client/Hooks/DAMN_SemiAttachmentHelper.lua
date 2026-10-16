--[[
    This file is part of that DAMN Library (Workshop ID 3171167894) authored by KI5 / bikinihorst.
    No permission is given for redistribution, repacking or modifying this or other files contained within the named
    workshop item, regardless of visibility or target community size, except if explicitly allowed by the author.
    TIS / Steam modding policy: https://projectzomboid.com/blog/modding-policy/
    This mod is "On Lockdown": https://theindiestone.com/forums/index.php?/topic/2530-mod-permissions/#findComment-36479
]]--

require "Vehicles/ISVehicleTrailerUtils";

DAMN = DAMN or {};
DAMN.SemiAttachmentHelper = DAMN.SemiAttachmentHelper or {};

-- registration

DAMN.SemiAttachmentHelper["byScriptName"] = {};

function DAMN.SemiAttachmentHelper:registerVehicleScript(semiVehicleScriptName, allowedTrailersVehicleScriptNames)
    DAMN.SemiAttachmentHelper["byScriptName"][semiVehicleScriptName] = DAMN.SemiAttachmentHelper["byScriptName"][semiVehicleScriptName] or {};

    for i, trailerScriptName in ipairs(allowedTrailersVehicleScriptNames or {})
    do
        if not DAMN:itemIsInArray(DAMN.SemiAttachmentHelper["byScriptName"][semiVehicleScriptName], trailerScriptName)
        then
            table.insert(DAMN.SemiAttachmentHelper["byScriptName"][semiVehicleScriptName], trailerScriptName);
        end
    end
end

-- checks

function DAMN.SemiAttachmentHelper:vehicleIsRegistered(vehicle)
    return DAMN.SemiAttachmentHelper["byScriptName"][vehicle:getScript():getFullName()] or false;
end

function DAMN.SemiAttachmentHelper:trailerIsAllowed(semiVehicle, trailerVehicle)
    local semiScript = semiVehicle:getScript():getFullName();

    if DAMN:arrayIsEmpty(DAMN.SemiAttachmentHelper["byScriptName"][semiScript])
    then
        return true;
    end

    return DAMN:itemIsInArray(DAMN.SemiAttachmentHelper["byScriptName"][semiScript], trailerVehicle:getScript():getFullName());
end

-- hooks

local orgGetTowableVehicleNear = ISVehicleTrailerUtils.getTowableVehicleNear;

function ISVehicleTrailerUtils.getTowableVehicleNear(square, ignoreVehicle, attachmentA, attachmentB)
    if DAMN.SemiAttachmentHelper:vehicleIsRegistered(ignoreVehicle)
    then
        local vehicles = square:getCell():getVehicles();

        for i = 0, vehicles:size() - 1
        do
            local vehicle = vehicles:get(i);

            if vehicle and vehicle ~= ignoreVehicle and DAMN.SemiAttachmentHelper:trailerIsAllowed(ignoreVehicle, vehicle) and ignoreVehicle:canAttachTrailer(vehicle, attachmentA, attachmentB)
            then
                return vehicle;
            end
        end

        return nil;
    end

    return orgGetTowableVehicleNear(square, ignoreVehicle, attachmentA, attachmentB);
end